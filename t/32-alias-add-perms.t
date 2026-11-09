#!/usr/bin/perl
# t/32-alias-add-perms.t - privilege flags when adding an alias in the web UI
#
# restricted_add_host() (web UI 'Alias' button) must require the CNAME/AREC
# privilege flags only from users without RWX on the zone; RWX users may
# add any alias type, as they may edit and delete them.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/32-alias-add-perms.t
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our $SAURON_PRIVILEGE_MODE = 0;
our (%perms, %state);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run alias add permission tests';
}

use Sauron::DB;
use Sauron::BackEnd;
use Sauron::CGI::Hosts;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('alias-perms-test');

my $srvid  = 932001;
my $zoneid = 932002;
my $hostid = 932003;

sub cleanup {
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

cleanup();
db_exec("INSERT INTO servers (id,name) VALUES ($srvid,'alias-perms-srv')");
db_exec("INSERT INTO zones (id,server,type,name) " .
        "VALUES ($zoneid,$srvid,'M','alias-perms.example.')");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hostid,$zoneid,1,'target')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hostid,'192.0.2.20')");

%state = (superuser => 'no', serverid => $srvid, zoneid => $zoneid);

sub try_add {
    my ($mode, $flags, $type, $name) = @_;
    %perms = (alevel => 0, server => { $srvid => 'R' },
              zone => { $zoneid => $mode }, flags => $flags,
              hostname => [], net => {}, ipmask => []);
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select($fh);
    my $res = Sauron::CGI::Hosts::restricted_add_host(
        { type => $type, zone => $zoneid, domain => $name, alias => $hostid });
    select($old);
    close($fh);
    return ($res, $out);
}

my ($res, $out);

($res) = try_add('RWX', {}, 4, 'cname-rwx');
ok($res > 0, 'RWX without flags can add CNAME alias') or diag("res=$res");
($res) = try_add('RWX', {}, 7, 'arec-rwx');
ok($res > 0, 'RWX without flags can add AREC alias') or diag("res=$res");

($res, $out) = try_add('RW', {}, 4, 'cname-rw');
is($res, -104, 'RW without CNAME flag cannot add CNAME alias');
like($out, qr/permission to add CNAME/, 'error message shown');
($res) = try_add('RW', {}, 7, 'arec-rw');
is($res, -107, 'RW without AREC flag cannot add AREC alias');

($res) = try_add('RW', { CNAME => 1 }, 4, 'cname-rw-flag');
ok($res > 0, 'RW with CNAME flag can add CNAME alias') or diag("res=$res");
($res) = try_add('RW', { CNAME => 1 }, 7, 'arec-rw-flag');
is($res, -107, 'CNAME flag does not allow AREC alias');

cleanup();
done_testing();
