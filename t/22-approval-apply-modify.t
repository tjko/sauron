#!/usr/bin/perl
# t/22-approval-apply-modify.t - applying approved Modify requests
#
# apply_change() checks a Modify request for IP conflicts before calling
# update_host(). The record comes from get_host(), whose ip list starts
# with a header row; the host's own unchanged addresses must not count as
# a conflict either. Checks that approved modifies of a host and of a
# CNAME alias (no addresses) are applied, and that an address used by
# another host is still rejected.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/22-approval-apply-modify.t
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

# Ensure DB.pm symlink (mirrors t/10)
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $SAURON_MAILER = '';
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run approval apply DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;
use Sauron::Approval;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('approval-apply-test');

my $srvid   = 940001;
my $zoneid  = 940002;
my $hosta   = 940003;
my $hostb   = 940004;
my $aliasid = 940005;
my $userid  = 940006;
my $polid   = 940007;

sub cleanup {
    my $rq = "SELECT id FROM dns_change_requests WHERE zone_id=$zoneid";
    db_exec("DELETE FROM dns_change_audit_log WHERE request_id IN ($rq)");
    db_exec("DELETE FROM dns_change_approvals WHERE request_id IN ($rq)");
    db_exec("DELETE FROM dns_change_requests WHERE zone_id=$zoneid");
    db_exec("DELETE FROM approval_policies WHERE id=$polid");
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
    db_exec("DELETE FROM users WHERE id=$userid");
}

sub field {
    my ($sql) = @_;
    my @q;
    db_query($sql, \@q);
    return $q[0][0];
}

# Submit a Modify request for $id with $change applied to the get_host()
# record, then apply it as an approver would.
sub approve_modify {
    my ($id, $change) = @_;
    my (%orig, %rec);
    get_host($id, \%orig);
    get_host($id, \%rec);
    $change->(\%rec);
    my $req = submit_change_request($zoneid, $polid, $userid, '', 'M', $id,
                                    \%rec, \%orig, 'test');
    ok($req, "request submitted") or return (undef, 0);
    return ($req, apply_change($req));
}

cleanup();
db_exec("INSERT INTO users (id,username) VALUES ($userid,'approval-apply-test')");
db_exec("INSERT INTO servers (id,name) VALUES ($srvid,'approval-apply-srv')");
db_exec("INSERT INTO zones (id,server,type,name) " .
        "VALUES ($zoneid,$srvid,'M','approval-apply.example.')");
db_exec("INSERT INTO approval_policies (id,zone_id,name,on_modify) " .
        "VALUES ($polid,$zoneid,'apply-test',true)");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hosta,$zoneid,1,'host-a')");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hostb,$zoneid,1,'host-b')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hosta,'192.0.2.10')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hostb,'192.0.2.11')");
db_exec("INSERT INTO hosts (id,zone,type,domain,alias) " .
        "VALUES ($aliasid,$zoneid,4,'www',$hosta)");

subtest 'host modify keeping its address is applied' => sub {
    my ($req, $res) = approve_modify($hosta, sub { $_[0]{info} = 'changed' });
    is($res, 1, "apply_change succeeds");
    is(field("SELECT status FROM dns_change_requests WHERE id=$req"), 'A',
       "request approved");
    is(field("SELECT info FROM hosts WHERE id=$hosta"), 'changed',
       "change applied");
};

subtest 'host modify to a free address is applied' => sub {
    my ($req, $res) = approve_modify($hosta, sub {
        $_[0]{ip}[1][1] = '192.0.2.20';
        $_[0]{ip}[1][4] = 1;
    });
    is($res, 1, "apply_change succeeds");
    like(field("SELECT ip FROM a_entries WHERE host=$hosta"),
         qr{^192\.0\.2\.20(/32)?$}, "address changed");
};

subtest 'host modify to an address of another host is rejected' => sub {
    my ($req, $res) = approve_modify($hosta, sub {
        $_[0]{ip}[1][1] = '192.0.2.11';
        $_[0]{ip}[1][4] = 1;
    });
    is($res, 0, "apply_change fails");
    is(field("SELECT status FROM dns_change_requests WHERE id=$req"), 'R',
       "request rejected");
    like(field("SELECT ip FROM a_entries WHERE host=$hosta"),
         qr{^192\.0\.2\.20(/32)?$}, "address unchanged");
};

subtest 'CNAME alias modify (no addresses) is applied' => sub {
    my ($req, $res) = approve_modify($aliasid, sub { $_[0]{alias} = $hostb });
    is($res, 1, "apply_change succeeds");
    is(field("SELECT alias FROM hosts WHERE id=$aliasid"), $hostb,
       "alias points to host-b");
};

cleanup();
done_testing();
