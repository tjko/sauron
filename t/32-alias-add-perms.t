#!/usr/bin/perl
# t/32-alias-add-perms.t - privilege flags when adding records in the web UI
#
# Privilege flags extend users with RW on the zone, RWX allows all record
# types (as for editing and deleting):
# - restricted_add_host() ('Alias' button) requires the CNAME/AREC flags
#   only from RW users,
# - the Hosts 'Add' handler (sub=add&type=N) requires the type's flag from
#   RW users; Delegations, Glue records and reservations need the flag
#   (or authorization level) also with RWX.
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
    db_exec("DELETE FROM arec_entries WHERE host IN " .
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

%state = (superuser => 'no', serverid => $srvid, zoneid => $zoneid,
          zone => 'alias-perms.example.', selfurl => '/sauron.cgi');
our $ALEVEL_RESERVATIONS = 1;

sub set_perms {
    my ($mode, $flags, $alevel) = @_;
    %perms = (alevel => $alevel // 0, server => { $srvid => 'R' },
              zone => { $zoneid => $mode }, flags => $flags,
              hostname => [], net => {}, ipmask => [], groups => []);
}

sub capture {
    my ($code) = @_;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select($fh);
    $code->();
    select($old);
    close($fh);
    return $out;
}

# Hosts 'Add' handler: returns 1 if the add form is shown
sub add_form_shown {
    my ($type) = @_;
    CGI::delete_all();
    CGI::param('menu', 'hosts');
    CGI::param('sub', 'add');
    CGI::param('type', $type);
    my $out = capture(sub {
        Sauron::CGI::Hosts::menu_handler(\%state, \%perms) });
    return ($out =~ /addhost_submit/ ? 1 : 0, $out);
}

sub try_add {
    my ($mode, $flags, $type, $name) = @_;
    set_perms($mode, $flags);
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

subtest 'Add handler: RWX allows all types except DELEG/GLUE/RESERV' => sub {
    set_perms('RWX', {});
    for my $t (1, 3, 4, 8, 13, 15) {
        is((add_form_shown($t))[0], 1, "RWX without flags: type $t form shown");
    }
    for my $t (2, 6, 101) {
        is((add_form_shown($t))[0], 0, "RWX without flags: type $t denied");
    }
    set_perms('RWX', { DELEG => 1, GLUE => 1, RESERV => 1 });
    for my $t (2, 6, 101) {
        is((add_form_shown($t))[0], 1, "RWX with flag: type $t form shown");
    }
    set_perms('RWX', {}, 1);
    is((add_form_shown(101))[0], 1, 'RWX with reservation level: form shown');
};

subtest 'Add handler: RW needs the type flag' => sub {
    set_perms('RW', {});
    is((add_form_shown(1))[0], 1, 'RW: host form shown');
    for my $t (2, 3, 4, 6, 8, 13, 15, 101) {
        is((add_form_shown($t))[0], 0, "RW without flags: type $t denied");
    }
    set_perms('RW', { MX => 1, SCNAME => 1 });
    is((add_form_shown(3))[0], 1, 'RW with MX flag: MX form shown');
    is((add_form_shown(4))[0], 1, 'RW with SCNAME flag: alias form shown');
    is((add_form_shown(13))[0], 0, 'RW with MX flag: TXT still denied');
};

subtest "check_perms('hostflag')" => sub {
    set_perms('RWX', {});
    is(Sauron::CGI::Utils::check_perms('hostflag', 'MX', 1), 0, 'RWX: allowed');
    set_perms('RW', {});
    is(Sauron::CGI::Utils::check_perms('hostflag', 'MX', 1), 1, 'RW: denied');
    set_perms('RW', { MX => 1 });
    is(Sauron::CGI::Utils::check_perms('hostflag', 'MX', 1), 0, 'RW+flag: allowed');
    set_perms('R', { MX => 1 });
    is(Sauron::CGI::Utils::check_perms('hostflag', 'MX', 1), 1, 'R+flag: denied');
};

cleanup();
done_testing();
