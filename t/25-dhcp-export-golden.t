#!/usr/bin/perl
# t/25-dhcp-export-golden.t - golden test of the ISC DHCP export
#
# Builds a server with DHCP data covering all parts of the dhcpd.conf /
# dhcpd6.conf generator (global/local entries, shared-networks, subnets,
# routers, dynamic pools, groups with %{macros}, classes, ether aliases,
# auto domain names, expired hosts, DHCPv6 DUIDs, failover primary) and a
# slave server 'ns2' (failover secondary, site specific 'ns2' handling),
# and compares the generated files with references in test/golden/.
#
# The reference files are the output of the generator before the DHCP
# model refactoring; any difference is a regression. To regenerate them
# (only when the output change is intended) set SAURON_GOLDEN_UPDATE to a
# writable directory, the generated files are copied there.
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
set_muser('golden-test');

my $testdata = "$FindBin::Bin/../test";
my $golden   = "$testdata/golden";
my $server   = 'dhcp-golden';
my $slave    = 'ns2';
my $tmp      = tempdir(CLEANUP => 1);

sub sql {
    my ($q) = @_;
    my $r = db_exec($q);
    die("SQL failed: $q\n" . db_errormsg() . "\n") if ($r < 0);
    return $r;
}

sub val {
    my ($q) = @_;
    my @r;
    db_query($q, \@r);
    die("SQL failed: $q\n" . db_errormsg() . "\n") if (db_errormsg());
    die("no result: $q\n") unless (@r);
    return $r[0][0];
}

sub run {
    my ($cmd) = @_;
    my $out = `$cmd 2>&1`;
    is($? >> 8, 0, $cmd) or diag($out);
    return $out;
}

# =========================================================================
# setup
# =========================================================================
# remove test servers left by a previous run (slave first)
sub cleanup {
    foreach my $name ($slave, $server) {
        my @r;
        db_query("SELECT id FROM servers WHERE name='$name'", \@r);
        next unless (@r);
        die("cannot delete server $name: " . db_errormsg() . "\n")
            if (delete_server($r[0][0]) < 0);
    }
}
cleanup();

# dhcp_flags: 0x01 = auto domain names, 0x02 = failover; DHCPv6 failover
# (KEA HA only) in hot-standby (split 255)
sql("INSERT INTO servers (name,hostname,hostmaster,comment,dhcp_flags," .
    "dhcp_flags6,df_split6,hostaddr) " .
    "VALUES ('$server','ns1.middle.earth.','hostmaster.middle.earth.'," .
    "'golden test',3,2,255,'192.0.2.10')");
my $sid = val("SELECT id FROM servers WHERE name='$server'");
sql("INSERT INTO servers (name,hostname,hostmaster,comment,masterserver,hostaddr) " .
    "VALUES ('$slave','ns2.middle.earth.','hostmaster.middle.earth.'," .
    "'golden slave',$sid,'192.0.2.11')");
my $slave_id = val("SELECT id FROM servers WHERE name='$slave'");
sql("INSERT INTO nets (server,net,netname,name,vlan,subnet) VALUES " .
    "($sid,'10.10.0.0/16','net','net',-1,false)," .
    "($sid,'2001:db8::/32','net6','net6',-1,false)");

open(my $zf, '>', "$tmp/golden.test.zone") or die $!;
print $zf <<'EOF';
$TTL 3600
@	IN	SOA	ns1.middle.earth. hostmaster.middle.earth. ( 1 3600 900 604800 3600 )
	IN	NS	ns1.middle.earth.
dyn1	IN	A	10.10.120.10
dyn2	IN	A	10.10.120.11
dyn3	IN	A	10.10.120.12
dyn4	IN	A	10.10.120.13
dyn5	IN	A	10.10.120.20
pxe1	IN	A	10.10.120.50
alias1	IN	A	10.10.100.60
h6a	IN	AAAA	2001:db8:250::10
h6b	IN	AAAA	2001:db8:250::11
h6c	IN	AAAA	2001:db8:250::12
dyn6a	IN	AAAA	2001:db8:250::100
dyn6b	IN	AAAA	2001:db8:250::101
gw6	IN	AAAA	2001:db8:250::1
EOF
close($zf);

subtest 'import data' => sub {
    run("$install_dir/import-zone $server middle.earth $testdata/middle.earth.zone");
    run("$install_dir/import-zone $server golden.test $tmp/golden.test.zone");
    run("$install_dir/import-dhcp --global $server $testdata/dhcpd.conf");
};

# host id by name (in zone middle.earth or golden.test)
sub hid {
    my ($name, $zone) = @_;
    $zone //= 'golden.test';
    return val("SELECT h.id FROM hosts h JOIN zones z ON h.zone=z.id " .
               "WHERE z.server=$sid AND z.name='$zone' AND h.domain='$name'");
}

sub new_group {
    my ($name, $type) = @_;
    sql("INSERT INTO groups (server,name,type) VALUES ($sid,'$name',$type)");
    return val("SELECT id FROM groups WHERE server=$sid AND name='$name'");
}

sub dhcp {
    my ($type, $ref, $text, $comment) = @_;
    $text =~ s/'/''/g;
    $comment = defined $comment ? "'$comment'" : 'NULL';
    sql("INSERT INTO dhcp_entries (type,ref,dhcp,comment) " .
        "VALUES ($type,$ref,'$text',$comment)");
}

subtest 'extra DHCP data' => sub {
    # server: local (7/17) and global (1/11) entries
    dhcp(7,  $sid, 'log-facility local7', 'local c');
    dhcp(1,  $sid, 'option domain-name "middle.earth"', 'global c');
    dhcp(17, $sid, 'log-facility local6');
    dhcp(11, $sid, 'default-lease-time 3600', 'global6 c');
    dhcp(7,  $slave_id, 'log-facility local5', 'slave local c');

    # shared-network and subnet entries
    my $vlan = val("SELECT id FROM vlans WHERE server=$sid AND name='servers1'");
    dhcp(6, $vlan, 'option domain-name "servers.middle.earth"', 'vlan c');
    dhcp(16, $vlan, 'option dhcp6.domain-search "servers.middle.earth"');
    my $net = val("SELECT id FROM nets WHERE server=$sid AND net='10.10.100.0/24'");
    dhcp(4, $net, 'default-lease-time 600', 'subnet c');
    dhcp(4, $net, 'max-lease-time 1200');

    # DHCPv6 subnet in VLAN servers1, router host
    sql("INSERT INTO nets (server,net,netname,name,vlan,subnet) VALUES " .
        "($sid,'2001:db8:250::/64','net6-250','net6-250',$vlan,true)");
    my $net6 = val("SELECT id FROM nets WHERE server=$sid AND net='2001:db8:250::/64'");
    dhcp(4, $net6, 'option dhcp6.name-servers 2001:db8::1', 'subnet6 c');
    sql("UPDATE hosts SET router=1 WHERE id=" . hid('gw6'));

    # dynamic pools (two ranges in v4 because of the gap)
    my $pool = new_group('dynpool', 2);
    dhcp(5, $pool, 'max-lease-time 1800');
    dhcp(5, $pool, 'allow members of "vip"');
    sql("UPDATE hosts SET grp=$pool WHERE id=" . hid($_))
        foreach (qw(dyn1 dyn2 dyn3 dyn4 dyn5));
    my $pool6 = new_group('dynpool6', 2);
    dhcp(15, $pool6, 'preferred-lifetime 600');
    sql("UPDATE hosts SET grp=$pool6 WHERE id=" . hid($_))
        foreach (qw(dyn6a dyn6b));

    # classes: MAC based (3) with members via grp and group_entries,
    # custom (103)
    my $vip = new_group('vip', 3);
    dhcp(5, $vip, 'option domain-name "vip.middle.earth"', 'vip c');
    dhcp(15, $vip, 'option dhcp6.domain-search "vip.middle.earth"');
    my $pxe1 = hid('pxe1');
    sql("UPDATE hosts SET grp=$vip, ether='0A0B0C0D0E01' WHERE id=$pxe1");
    sql("INSERT INTO group_entries (host,grp) VALUES (" .
        hid('ws1', 'middle.earth') . ",$vip)");
    my $pxe = new_group('pxe', 103);
    dhcp(5, $pxe, 'match if substring(option vendor-class-identifier,0,9) = "PXEClient"');
    dhcp(5, $pxe, 'filename "pxelinux.0"');

    # group with per-host macros
    my $grp = val("SELECT grp FROM hosts WHERE id=" . hid('terminal1', 'middle.earth'));
    dhcp(5, $grp, 'option host-name "%{host}"');
    dhcp(5, $grp, 'filename "%{host}-%{ether}.cfg"', 'macro c');
    # not used: added after a filename macro
    dhcp(5, $grp, 'option merit-dump "%{fqdn}"');

    # host entries, ether alias, expired host
    my $ws2 = hid('ws2', 'middle.earth');
    dhcp(3, $ws2, 'option host-name "ws2-dhcp"', 'host c');
    dhcp(3, $ws2, 'option domain-name "other.middle.earth"');
    sql("UPDATE hosts SET ether_alias=" . hid('ws3', 'middle.earth') .
        " WHERE id=" . hid('alias1'));
    sql("UPDATE hosts SET expiration=1 WHERE id=" . hid('ws8', 'middle.earth'));

    # DHCPv6 hosts: DUID, group, class member, host entry
    sql("UPDATE hosts SET duid='000100012a3b4c5d0a0b0c0d0e10' WHERE id=" . hid('h6a'));
    sql("UPDATE hosts SET duid='000100012a3b4c5d0a0b0c0d0e11', grp=$grp WHERE id=" . hid('h6b'));
    sql("UPDATE hosts SET duid='000100012a3b4c5d0a0b0c0d0e12', grp=$vip WHERE id=" . hid('h6c'));
    dhcp(13, hid('h6a'), 'option dhcp6.sntp-servers 2001:db8::123', 'host6 c');

    # explicit KEA subnet ids (KEA only entries): the default, nets.id,
    # depends on the state of the database sequence
    my @nets;
    db_query("SELECT id FROM nets WHERE server=$sid AND subnet ORDER BY id", \@nets);
    my $kid = 15;
    sql("INSERT INTO dhcp_entries (type,ref,dhcp,fmt) " .
        "VALUES (4,$_->[0],'{\"id\":" . $kid++ . "}',2)") foreach (@nets);
    pass('extra data inserted');
};

# =========================================================================
# generate and compare
# =========================================================================
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

subtest 'generate and compare' => sub {
    my $gen = "$tmp/gen";
    mkdir($gen) or die $!;
    mkdir("$gen/ns2") or die $!;
    run("$install_dir/sauron --dhcp $server $gen");
    run("$install_dir/sauron --dhcp6 $server $gen");
    run("$install_dir/sauron --dhcp --dhcpclass vip $server $gen");
    run("$install_dir/sauron --dhcp $slave $gen/ns2");
    run("$install_dir/sauron --dhcp6 $slave $gen/ns2");
    run("$install_dir/sauron --kea --kea6 $server $gen");
    run("$install_dir/sauron --kea --kea6 $slave $gen/ns2");

    foreach my $f ('dhcpd.conf', 'dhcpd6.conf', 'vip.class',
                   'ns2/dhcpd.conf', 'ns2/dhcpd6.conf',
                   'kea-dhcp4.conf', 'kea-dhcp6.conf',
                   'ns2/kea-dhcp4.conf', 'ns2/kea-dhcp6.conf') {
        ok(-r "$gen/$f", "$f generated") or next;
        my $fam = ($f =~ /6\.conf$/ ? 6 : 4);
        if ($f =~ /kea-/) { validate_kea("$gen/$f", $fam); }
        elsif ($f !~ /\.class$/) { validate_isc("$gen/$f", $fam); }
        my $got = normalize("$gen/$f");

        if (my $dir = $ENV{SAURON_GOLDEN_UPDATE}) {
            mkdir("$dir/ns2") unless (-d "$dir/ns2");
            open(my $out, '>', "$dir/$f") or die "$dir/$f: $!";
            print $out $got;
            close($out);
            diag("golden file written: $dir/$f");
        }

        unless (-r "$golden/$f") {
            fail("reference $golden/$f missing");
            next;
        }
        my $exp = normalize("$golden/$f");
        if ($got eq $exp) {
            pass("$f matches golden reference");
        } else {
            fail("$f differs from golden reference");
            diag(`diff -u $golden/$f $gen/$f`);
        }
    }
};

cleanup();

done_testing();
