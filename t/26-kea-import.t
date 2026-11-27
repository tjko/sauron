#!/usr/bin/perl
# t/26-kea-import.t - import of a KEA configuration (import-dhcp) and the
#                     resulting ISC dhcpd.conf / dhcpd6.conf
#
# Imports test/kea-import.json into a new server with a zone of matching
# hosts, checks the stored data (hosts, groups, KEA only entries with
# dhcp_entries.fmt = 2) and compares the generated configuration with
# test/golden/kea-import/ (SAURON_GOLDEN_UPDATE=<dir> writes fresh output).
#
# Requires running PostgreSQL with initialized Sauron DB and installed
# Sauron. Skipped unless SAURON_TEST_DSN and SAURON_INSTALL_DIR are set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
unless ($DB_DSN && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for E2E tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('kea-import-test');

my $testdata = "$FindBin::Bin/../test";
my $golden   = "$testdata/golden/kea-import";
my $server   = 'kea-import';
my $tmp      = tempdir(CLEANUP => 1);

sub sql {
    my ($q) = @_;
    die("SQL failed: $q\n" . db_errormsg() . "\n") if (db_exec($q) < 0);
}

sub rows {
    my ($q) = @_;
    my @r;
    db_query($q, \@r);
    die("SQL failed: $q\n" . db_errormsg() . "\n") if (db_errormsg());
    return \@r;
}

sub run {
    my ($cmd) = @_;
    my $out = `$cmd 2>&1`;
    is($? >> 8, 0, $cmd) or diag($out);
    return $out;
}

sub cleanup {
    my $r = rows("SELECT id FROM servers WHERE name='$server'");
    die("cannot delete server $server\n")
        if (@$r && delete_server($r->[0][0]) < 0);
}
cleanup();

sql("INSERT INTO servers (name,hostname,hostmaster,comment) VALUES " .
    "('$server','ns1.kea.test.','hostmaster.kea.test.','KEA import test')");
my $sid = rows("SELECT id FROM servers WHERE name='$server'")->[0][0];
sql("INSERT INTO nets (server,net,netname,name,vlan,subnet) VALUES " .
    "($sid,'10.30.0.0/16','net','net',-1,false)," .
    "($sid,'2001:db8:30::/48','net6','net6',-1,false)");

open(my $zf, '>', "$tmp/kea.test.zone") or die $!;
print $zf <<'EOF';
$TTL 3600
@	IN	SOA	ns1.kea.test. hostmaster.kea.test. ( 1 3600 900 604800 3600 )
	IN	NS	ns1.kea.test.
ns1	IN	A	10.30.0.2
gw1	IN	A	10.30.1.1
gw2	IN	A	10.30.2.1
ws1	IN	A	10.30.1.10
ws1	IN	AAAA	2001:db8:30:1::10
ws2	IN	A	10.30.1.11
ws3	IN	A	10.30.1.12
dyn1	IN	A	10.30.1.100
dyn2	IN	A	10.30.1.101
printer	IN	A	10.30.2.9
EOF
close($zf);

subtest 'import' => sub {
    run("$install_dir/import-zone $server kea.test $tmp/kea.test.zone");
    my $out = run("$install_dir/import-dhcp --kea --global $server $testdata/kea-import.json");
    like($out, qr/reservation ws3\.kea\.test: no supported identifier/,
         'unsupported identifier reported');
    run("$install_dir/import-dhcp --kea --dhcp6 --global $server $testdata/kea-import.json");
};

sub host {
    my ($name) = @_;
    my $r = rows("SELECT h.id,h.ether,h.duid,h.grp,h.router FROM hosts h " .
                 "JOIN zones z ON h.zone=z.id WHERE z.server=$sid AND h.domain='$name'");
    return $r->[0];
}

subtest 'stored data' => sub {
    is(host('ws1')->[1], '0A0000000001', 'MAC from hw-address');
    is(host('ws2')->[1], '0A0000000002', 'MAC from client-id');
    ok(!host('ws3')->[1], 'no MAC from flex-id');
    is(lc(host('ws1')->[2]), '000100012a3b4c5d0a0000000001', 'DUID');
    is(host('gw1')->[4], 1, 'router from subnet routers option');

    my $pool = rows("SELECT id FROM groups WHERE server=$sid AND type=2")->[0][0];
    is(host('dyn1')->[3], $pool, 'pool member');
    is(host('dyn2')->[3], $pool, 'pool member');

    my $vip = rows("SELECT id FROM groups WHERE server=$sid AND name='vip'")->[0][0];
    is(rows("SELECT count(*) FROM group_entries WHERE host=" . host('ws1')->[0] .
            " AND grp=$vip")->[0][0], 1, 'class membership from client-classes');
    is(rows("SELECT type FROM groups WHERE id=$vip")->[0][0], 3, 'membership class');
    is(rows("SELECT type FROM groups WHERE server=$sid AND name='pxe'")->[0][0], 103,
       'test expression class');

    my $kea = rows("SELECT type,dhcp FROM dhcp_entries WHERE fmt=2 AND " .
                   "((type IN (1,11) AND ref=$sid) OR " .
                   " (type IN (3,13) AND ref IN (SELECT h.id FROM hosts h JOIN zones z " .
                   "   ON h.zone=z.id WHERE z.server=$sid)) OR " .
                   " (type IN (4,5,6,15,16) AND ref IN (SELECT id FROM nets WHERE server=$sid " .
                   "   UNION SELECT id FROM groups WHERE server=$sid " .
                   "   UNION SELECT id FROM vlans WHERE server=$sid))) ORDER BY id");
    my @kea = map { $_->[1] } @$kea;
    ok((grep { $_ eq '{"renew-timer":900}' } @kea), 'global KEA only parameter stored');
    ok((grep { $_ eq '{"id":1}' } @kea), 'subnet id stored');
    ok((grep { /^\{"test":/ } @kea), 'class test stored');
    ok((grep { $_ eq q({"flex-id":"'ws3'"}) } @kea), 'flex-id stored');
    ok((grep { /^\{"pd-pools":/ } @kea), 'pd-pools stored');
    ok((grep { /"always-send":true/ } @kea), 'option with always-send kept for KEA');
    is(rows("SELECT count(*) FROM dhcp_entries WHERE type=1 AND ref=$sid AND fmt=1 " .
            "AND dhcp='option domain-name-servers 10.30.0.2, 10.30.0.3'")->[0][0], 1,
       'its ISC form stored as ISC only');
    is(rows("SELECT count(*) FROM dhcp_entries WHERE type=15 AND ref=$vip")->[0][0], 1,
       'DHCPv6 entries added to the class created by the DHCPv4 import');
};

subtest 're-import does not duplicate host data' => sub {
    my $ws1 = host('ws1')->[0];
    my $q = "SELECT (SELECT count(*) FROM dhcp_entries WHERE type=3 AND ref=$ws1)," .
            " (SELECT count(*) FROM group_entries WHERE host=$ws1)";
    my $before = rows($q)->[0];
    run("$install_dir/import-dhcp --kea $server $testdata/kea-import.json");
    is_deeply(rows($q)->[0], $before, 'host entries and class memberships unchanged');
    my $pool = host('dyn1')->[3];
    is(rows("SELECT name FROM groups WHERE id=$pool")->[0][0], 'pool-2',
       'pool of the second import gets an unused name');
};

# validate a generated dhcpd.conf with ISC dhcpd, when installed
sub validate_isc {
    my ($file, $family) = @_;
    my ($dhcpd) = grep { -x $_ } ('/usr/sbin/dhcpd', '/usr/local/sbin/dhcpd');
  SKIP: {
        skip('ISC dhcpd not installed', 1) unless ($dhcpd);
        my $out = `$dhcpd -$family -t -cf $file 2>&1`;
        is($? >> 8, 0, "dhcpd -$family -t accepts $file") or diag($out);
    }
}

# validate a generated KEA configuration, when KEA is installed
sub validate_kea {
    my ($file, $family) = @_;
    my ($kea) = grep { -x $_ } ("/usr/sbin/kea-dhcp$family", "/usr/local/sbin/kea-dhcp$family");
  SKIP: {
        skip("kea-dhcp$family not installed", 1) unless ($kea);
        my $out = `$kea -t $file 2>&1`;
        is($? >> 8, 0, "kea-dhcp$family -t accepts $file") or diag($out);
    }
}

sub normalize {
    my ($file) = @_;
    open(my $fh, '<', $file) or die "$file: $!";
    my @l = <$fh>;
    close($fh);
    s/^((?:#|\/\/)\s+created by ).*$/${1}USER at TIME/ foreach (@l);
    return join('', @l);
}

subtest 'generated configuration' => sub {
    my $gen = "$tmp/gen";
    mkdir($gen) or die $!;
    run("$install_dir/sauron --dhcp $server $gen");
    run("$install_dir/sauron --dhcp6 $server $gen");

    foreach my $f ('dhcpd.conf', 'dhcpd6.conf') {
        validate_isc("$gen/$f", ($f =~ /6/ ? 6 : 4));
        my $got = normalize("$gen/$f");
        if (my $dir = $ENV{SAURON_GOLDEN_UPDATE}) {
            mkdir("$dir/kea-import") unless (-d "$dir/kea-import");
            open(my $out, '>', "$dir/kea-import/$f") or die $!;
            print $out $got;
            close($out);
            diag("golden file written: $dir/kea-import/$f");
        }
        unless (-r "$golden/$f") {
            fail("reference $golden/$f missing");
            next;
        }
        if ($got eq normalize("$golden/$f")) {
            pass("$f matches golden reference");
        } else {
            fail("$f differs from golden reference");
            diag(`diff -u $golden/$f $gen/$f`);
        }
        unlike($got, qr/renew-timer|pd-pools|flex-id|option\[60\]/,
               "$f: no KEA only statements");
    }
};

subtest 'KEA export of the imported data' => sub {
    my $gen = "$tmp/kea";
    mkdir($gen) or die $!;
    run("$install_dir/sauron --kea --kea6 $server $gen");
    validate_kea("$gen/kea-dhcp4.conf", 4);
    validate_kea("$gen/kea-dhcp6.conf", 6);

    my $json = sub {
        open(my $fh, '<', $_[0]) or die $!;
        local $/;
        my $t = <$fh>;
        $t =~ s{^//[^\n]*\n}{}mg;
        return JSON::PP->new->decode($t);
    };
    my $d4 = $json->("$gen/kea-dhcp4.conf")->{Dhcp4};
    is($d4->{'renew-timer'}, 900, 'KEA only global parameter exported');
    is($d4->{'valid-lifetime'}, 3600, 'ISC parameter converted back');
    my ($dns) = grep { $_->{name} eq 'domain-name-servers' } @{$d4->{'option-data'}};
    ok($dns && $dns->{'always-send'}, 'always-send kept');
    my ($pxe) = grep { $_->{name} eq 'pxe' } @{$d4->{'client-classes'}};
    is($pxe->{test}, "substring(option[60].hex,0,9) == 'PXEClient'", 'class test kept');
    my ($lab) = grep { $_->{name} eq 'lab' } @{$d4->{'shared-networks'}};
    my $s1 = $lab->{subnet4}[0];
    is($s1->{id}, 1, 'KEA subnet id kept');
    my ($ws1) = grep { $_->{hostname} eq 'ws1.kea.test' } @{$s1->{reservations}};
    is($ws1->{'hw-address'}, '0a:00:00:00:00:01', 'reservation exported');
    is_deeply($ws1->{'client-classes'}, ['vip'], 'reservation class');
    is($s1->{pools}[0]{'client-class'}, 'vip', 'pool class');

    my $d6 = $json->("$gen/kea-dhcp6.conf")->{Dhcp6};
    ok($d6->{subnet6}[0]{'pd-pools'}, 'pd-pools kept');
};

cleanup();

done_testing();
