#!/usr/bin/perl
# t/31-acme-txt.t - acme-txt: add/delete ACME DNS-01 TXT records
#
# Runs the installed acme-txt against the test database: first value goes
# to hosts.cname_txt of a TXT host (type 13), a second concurrent value for
# the same name (certificate for example + *.example) to txt_entries; both
# are written to the zone; deleting removes one value at a time and the
# host with the last one. Names outside the allowed zone, without the
# _acme-challenge prefix, or used by another host type are refused.
#
# Requires an installed Sauron whose config points to the test database:
#   SAURON_TEST_DSN=... SAURON_INSTALL_DIR=/usr/local/sauron prove -lv t/31-acme-txt.t
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

our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';
my $install_dir  = $ENV{SAURON_INSTALL_DIR}   || '';

unless ($DB_DSN && $install_dir && -x "$install_dir/acme-txt") {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR (with acme-txt)';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';

my $srvid    = 960001;
my $zoneid   = 960002;
my $wwwid    = 960003;
my $zoneid2  = 960004;   # other zone with an alias to our record
my $srvname  = 'acmetxt-test';
my $zonename = 'acmetxt.example';
my $v1 = 'a' x 43;
my $v2 = 'B' x 42 . '-';
my $v3 = '_' x 43;

sub cleanup {
    db_exec("DELETE FROM txt_entries WHERE type=2 AND ref IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM hosts WHERE zone IN ($zoneid,$zoneid2)");
    db_exec("DELETE FROM zones WHERE id IN ($zoneid,$zoneid2)");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

sub acme {
    my (@args) = @_;
    my $user = 't25';
    $user = shift(@args) =~ s/^user=//r if (@args && $args[0] =~ /^user=/);
    my $cmd = join(' ', "$install_dir/acme-txt", "--server=$srvname",
                   "--zone=$zonename", "--user=$user", @args) . ' 2>&1';
    my $out = `$cmd`;
    return ($? >> 8, $out);
}

sub acme_ssh {
    my ($request) = @_;
    local $ENV{SSH_ORIGINAL_COMMAND} = $request;
    return acme('--ssh');
}

# (type, cname_txt, ttl, expiration, [txt_entries values])
sub host_state {
    my ($domain) = @_;
    my (@q, @t);
    db_query("SELECT id,type,cname_txt,ttl,expiration FROM hosts " .
             "WHERE zone=$zoneid AND domain='$domain'", \@q);
    return () unless (@q);
    db_query("SELECT txt FROM txt_entries WHERE type=2 AND ref=$q[0][0] " .
             "ORDER BY id", \@t);
    return ($q[0][1], $q[0][2], $q[0][3], $q[0][4], [map { $$_[0] } @t]);
}

sub zone_file {
    my $dir = tempdir(CLEANUP => 1);
    my $out = `$install_dir/sauron --bind $srvname $dir 2>&1`;
    is($? >> 8, 0, 'sauron --bind exits 0') or diag($out);
    my $zfile = `find $dir -name '$zonename.zone'`;
    chomp($zfile);
    open(my $fh, '<', $zfile) or return '';
    my $zone = do { local $/; <$fh> };
    close($fh);
    return $zone;
}

cleanup();
setup_ok("INSERT INTO servers (id,name,hostname,hostmaster) VALUES " .
         "($srvid,'$srvname','ns.$zonename.','hostmaster.$zonename.')");
setup_ok("INSERT INTO zones (id,server,name,type,reverse) " .
         "VALUES ($zoneid,$srvid,'$zonename','M',false)");
setup_ok("INSERT INTO hosts (id,zone,type,domain) " .
         "VALUES ($wwwid,$zoneid,1,'www')");
setup_ok("INSERT INTO a_entries (host,ip) VALUES ($wwwid,'192.0.2.10')");

subtest 'add first value' => sub {
    my ($rc, $out) = acme('add', "_acme-challenge.$zonename", $v1);
    is($rc, 0, 'exit 0') or diag($out);
    my ($type, $txt, $ttl, $exp, $extra) = host_state('_acme-challenge');
    is($type, 13, 'TXT host created');
    is($txt, $v1, 'value in cname_txt');
    is($ttl, 60, 'short TTL');
    cmp_ok($exp, '>', time, 'expiration set in the future');
    is_deeply($extra, [], 'no txt_entries');

    ($rc, $out) = acme('add', "_acme-challenge.$zonename", $v1);
    is($rc, 0, 'adding the same value again is ok') or diag($out);
    is_deeply((host_state('_acme-challenge'))[4], [], 'still no txt_entries');
};

subtest 'second value for the same name (wildcard)' => sub {
    my ($rc, $out) = acme_ssh("add _acme-challenge.$zonename $v2");
    is($rc, 0, 'exit 0 (--ssh)') or diag($out);
    my ($type, $txt, undef, undef, $extra) = host_state('_acme-challenge');
    is($txt, $v1, 'first value kept');
    is_deeply($extra, [$v2], 'second value in txt_entries');

    ($rc, $out) = acme('add', "_acme-challenge.www.$zonename", $v3);
    is($rc, 0, 'name below the apex') or diag($out);
    is((host_state('_acme-challenge.www'))[1], $v3, 'stored');
};

subtest 'zone file' => sub {
    my $zone = zone_file();
    like($zone, qr/^_acme-challenge\s+60\s.*TXT.*\Q$v1\E/m, 'first value');
    like($zone, qr/^_acme-challenge\s.*TXT.*\Q$v2\E/m, 'second value');
    like($zone, qr/^_acme-challenge\.www\s.*TXT.*\Q$v3\E/m, 'www value');
};

subtest 'refused requests' => sub {
    my ($rc, $out) = acme('add', '_acme-challenge.other.example', $v1);
    is($rc, 2, 'other zone') or diag($out);
    ($rc, $out) = acme('add', "www.$zonename", $v1);
    is($rc, 2, 'no _acme-challenge prefix') or diag($out);
    ($rc, $out) = acme('add', "_acme-challenge.$zonename", 'short');
    is($rc, 2, 'invalid value') or diag($out);
    ($rc, $out) = acme_ssh("add _acme-challenge.$zonename $v1; id");
    is($rc, 1, 'extra words in SSH command') or diag($out);
    ($rc, $out) = acme('--zone=other.example', '--ssh', 'x');
    is($rc, 1, 'arguments with --ssh') or diag($out);

    setup_ok("INSERT INTO hosts (zone,type,domain,alias,cname_txt) VALUES " .
             "($zoneid,4,'_acme-challenge.cn',-1,'x.acme.example.net.')");
    ($rc, $out) = acme('add', "_acme-challenge.cn.$zonename", $v1);
    is($rc, 2, 'name used by a CNAME') or diag($out);
    ($rc, $out) = acme('del', "_acme-challenge.cn.$zonename", $v1);
    is($rc, 2, 'CNAME is not deleted') or diag($out);
    is((host_state('_acme-challenge.cn'))[0], 4, 'CNAME still there');

    setup_ok("INSERT INTO hosts (zone,type,domain,alias,cname_txt,cuser) " .
             "VALUES ($zoneid,13,'_acme-challenge.manual',-1,'$v1','admin')");
    ($rc, $out) = acme('add', "_acme-challenge.manual.$zonename", $v2);
    is($rc, 2, 'add to a TXT host not created by acme-txt') or diag($out);
    like($out, qr/managed outside acme-txt/, 'message');
    ($rc, $out) = acme('del', "_acme-challenge.manual.$zonename", $v1);
    is($rc, 2, 'del of a TXT host not created by acme-txt') or diag($out);
    my ($type, $txt, undef, undef, $extra) = host_state('_acme-challenge.manual');
    is($txt, $v1, 'manual host unchanged');
    is_deeply($extra, [], 'manual host has no new values');

    ($rc, $out) = acme('user=t25other', 'add', "_acme-challenge.www.$zonename", $v1);
    is($rc, 2, 'add to a record of another acme-txt user') or diag($out);
    like($out, qr/another acme-txt user/, 'message');
    ($rc, $out) = acme('user=t25other', 'del', "_acme-challenge.www.$zonename", $v3);
    is($rc, 2, 'del of a record of another acme-txt user') or diag($out);
    is((host_state('_acme-challenge.www'))[1], $v3, 'record unchanged');

    setup_ok("INSERT INTO hosts (zone,type,domain,alias,cname_txt,cuser) " .
             "VALUES ($zoneid,13,'_ACME-challenge.Mixed',-1,'$v1','admin')");
    ($rc, $out) = acme('add', "_acme-challenge.mixed.$zonename", $v2);
    is($rc, 2, 'name of a host stored in another case') or diag($out);

    setup_ok("INSERT INTO hosts (zone,type,domain) VALUES ($zoneid,2,'sub')");
    ($rc, $out) = acme('add', "_acme-challenge.sub.$zonename", $v1);
    is($rc, 2, 'name in a delegated zone') or diag($out);
    like($out, qr/delegated zone sub/, 'message');
    ($rc, $out) = acme('add', "_acme-challenge.x.sub.$zonename", $v1);
    is($rc, 2, 'name below a delegated zone') or diag($out);
    ($rc, $out) = acme('add', "_acme-challenge.xsub.$zonename", $v1);
    is($rc, 0, 'name only ending like a delegation is allowed') or diag($out);
    ($rc, $out) = acme('del', "_acme-challenge.xsub.$zonename", $v1);
    is($rc, 0, 'and deleted') or diag($out);
};

subtest 'limits and expiration' => sub {
    my $name = "_acme-challenge.lim.$zonename";
    for my $i (1..10) {
        my ($rc, $out) = acme('add', $name, sprintf('%043d', $i));
        is($rc, 0, "value $i") or diag($out);
    }
    my ($rc, $out) = acme('add', $name, sprintf('%043d', 11));
    is($rc, 2, '11th value refused') or diag($out);
    is(scalar(@{(host_state('_acme-challenge.lim'))[4]}), 9,
       '1 value in cname_txt + 9 in txt_entries');
    ($rc, $out) = acme('add', $name, sprintf('%043d', 10));
    is($rc, 0, 'existing value is still accepted at the limit') or diag($out);

    setup_ok("UPDATE hosts SET expiration=" . (time - 10) . ",mdate=0" .
             " WHERE zone=$zoneid AND domain='_acme-challenge.www'");
    ($rc, $out) = acme('add', "_acme-challenge.www.$zonename", $v3);
    is($rc, 0, 'add an existing value again') or diag($out);
    cmp_ok((host_state('_acme-challenge.www'))[3], '>', time,
           'expiration moved forward');
    my @q;
    db_query("SELECT mdate FROM hosts WHERE zone=$zoneid " .
             "AND domain='_acme-challenge.www'", \@q);
    cmp_ok($q[0][0], '>', time - 60, 'mdate updated, so the zone is pending');

    setup_ok("UPDATE hosts SET expiration=" . (time - 10) .
             " WHERE zone=$zoneid AND domain='_acme-challenge.lim'");
    ($rc, $out) = acme('--expire=0', 'add', $name, sprintf('%043d', 1));
    is($rc, 0, 'add with --expire=0 to an expired record') or diag($out);
    is((host_state('_acme-challenge.lim'))[3] || 0, 0, 'expiration cleared');
};

subtest 'name length' => sub {
    my ($rc, $out) = acme('add', '_acme-challenge.' . ('a' x 64) . ".$zonename",
                          $v1);
    is($rc, 2, 'label over 63 characters') or diag($out);
};

subtest 'concurrent requests are serialized' => sub {
    my $name = "_acme-challenge.par.$zonename";
    my $base = join(' ', "$install_dir/acme-txt", "--server=$srvname",
                    "--zone=$zonename", "--user=t25", 'add', $name);
    my $cmd = join(' ', map { "$base " . sprintf('%043d', $_) . ' >/dev/null 2>&1 &' }
                   1..12) . ' wait';
    system('sh', '-c', $cmd);
    my ($type, $txt, undef, undef, $extra) = host_state('_acme-challenge.par');
    is($type, 13, 'one TXT host');
    is(1 + scalar(@$extra), 10, 'exactly 10 values despite 12 parallel adds');
    my %seen;
    $seen{$_}++ for ($txt, @$extra);
    is(scalar(keys %seen), 10, 'no duplicate values');
};

subtest 'aliases to a deleted record are kept' => sub {
    setup_ok("INSERT INTO hosts (zone,type,domain,alias) " .
             "SELECT $zoneid,4,'_acme-challenge.dyn',id FROM hosts " .
             "WHERE zone=$zoneid AND domain='_acme-challenge.lim'");
    for my $i (1..10) {
        my ($rc, $out) = acme('del', "_acme-challenge.lim.$zonename",
                              sprintf('%043d', $i));
        is($rc, 0, "delete value $i") or diag($out);
    }
    is_deeply([host_state('_acme-challenge.lim')], [], 'host removed');
    my @a;
    db_query("SELECT alias,cname_txt FROM hosts WHERE zone=$zoneid " .
             "AND domain='_acme-challenge.dyn'", \@a);
    is_deeply(\@a, [[-1, "_acme-challenge.lim.$zonename."]],
              'alias of the host id turned into a static alias');

    setup_ok("INSERT INTO zones (id,server,name,type,reverse) " .
             "VALUES ($zoneid2,$srvid,'other.example','M',false)");
    setup_ok("INSERT INTO hosts (zone,type,domain,alias,cname_txt,cuser) " .
             "VALUES ($zoneid2,4,'_acme-challenge',-1," .
             "'_acme-challenge.del.$zonename.','admin')");
    my ($rc, $out) = acme('add', "_acme-challenge.del.$zonename", $v1);
    is($rc, 0, 'add') or diag($out);
    my @q;
    db_query("SELECT rdate FROM zones WHERE id=$zoneid", \@q);
    my $rdate = $q[0][0] || 0;
    sleep(1);
    ($rc, $out) = acme('del', "_acme-challenge.del.$zonename", $v1);
    is($rc, 0, 'delete last value') or diag($out);
    is_deeply([host_state('_acme-challenge.del')], [], 'host removed');
    db_query("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid2 AND type=4", \@q);
    is($q[0][0], 1, 'static alias in the other zone kept');
    db_query("SELECT rdate FROM zones WHERE id=$zoneid", \@q);
    cmp_ok($q[0][0], '>', $rdate, 'zone rdate updated');
};

subtest 'cleanup of expired records' => sub {
    my ($rc, $out) = acme('add', "_acme-challenge.old.$zonename", $v1);
    is($rc, 0, 'add') or diag($out);
    setup_ok("UPDATE hosts SET expiration=" . (time - 10) .
             " WHERE zone=$zoneid AND domain='_acme-challenge.old'");
    setup_ok("UPDATE hosts SET expiration=" . (time - 10) .
             " WHERE zone=$zoneid AND domain='_acme-challenge.manual'");

    ($rc, $out) = acme('--cleanup');
    is($rc, 1, '--cleanup with --zone is a usage error') or diag($out);
    local $ENV{SSH_ORIGINAL_COMMAND} = '';
    $out = `$install_dir/acme-txt --server=$srvname --cleanup --ssh 2>&1`;
    is($? >> 8, 1, '--cleanup with --ssh is a usage error') or diag($out);

    $out = `$install_dir/acme-txt --server=$srvname --cleanup --verbose 2>&1`;
    is($? >> 8, 0, '--cleanup exits 0') or diag($out);
    like($out, qr/deleted expired TXT _acme-challenge\.old\.\Q$zonename\E/,
         'reported');
    is_deeply([host_state('_acme-challenge.old')], [], 'expired record deleted');
    ok(scalar(host_state('_acme-challenge.manual')),
       'expired host not created by acme-txt kept');
    ok(scalar(host_state('_acme-challenge.www')), 'valid record kept');
};

subtest 'delete' => sub {
    my ($rc, $out) = acme('del', "_acme-challenge.$zonename", $v1);
    is($rc, 0, 'delete first value') or diag($out);
    my ($type, $txt, undef, undef, $extra) = host_state('_acme-challenge');
    is($txt, $v2, 'second value moved to cname_txt');
    is_deeply($extra, [], 'txt_entries empty');

    ($rc, $out) = acme('del', "_acme-challenge.$zonename", $v1);
    is($rc, 0, 'deleting a missing value is ok') or diag($out);
    is((host_state('_acme-challenge'))[1], $v2, 'nothing changed');

    ($rc, $out) = acme_ssh("del _acme-challenge.$zonename $v2");
    is($rc, 0, 'delete last value') or diag($out);
    is_deeply([host_state('_acme-challenge')], [], 'host removed');

    ($rc, $out) = acme('del', "_acme-challenge.$zonename", $v2);
    is($rc, 0, 'deleting a missing host is ok') or diag($out);

    setup_ok("INSERT INTO txt_entries (type,ref,txt) SELECT 2,id,'$v1' " .
             "FROM hosts WHERE zone=$zoneid AND domain='_acme-challenge.www'");
    ($rc, $out) = acme('del', "_acme-challenge.www.$zonename", $v1);
    is($rc, 0, 'delete a txt_entries value') or diag($out);
    ($type, $txt, undef, undef, $extra) = host_state('_acme-challenge.www');
    is($txt, $v3, 'cname_txt kept');
    is_deeply($extra, [], 'txt_entries value removed');

    my @q;
    db_query("SELECT COUNT(*) FROM history WHERE type=1 " .
             "AND action LIKE 'ACME:%' AND info LIKE '%(user: t25)'", \@q);
    cmp_ok($q[0][0], '>=', 6, 'changes recorded in history');
};

db_exec("DELETE FROM history WHERE type=1 AND action LIKE 'ACME:%' " .
        "AND (info LIKE '%(user: t25)' OR info LIKE '%$zonename (expired)')");
cleanup();
done_testing();
