#!/usr/bin/perl
# t/21-cname-alias-move.t - moving a CNAME alias to another host
#
# The web UI 'Move' action on a CNAME alias only changes hosts.alias and
# saves the record via update_host(). Checks that the alias then points to
# the new host and is listed among its aliases, and not the old host's.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/21-cname-alias-move.t
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
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run CNAME alias move DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('cname-move-test');

my $srvid   = 930001;
my $zoneid  = 930002;
my $hosta   = 930003;
my $hostb   = 930004;
my $aliasid = 930005;

sub cleanup {
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

sub alias_names {
    my ($hid) = @_;
    my %h;
    get_host($hid, \%h);
    my @l = @{$h{alias_l} || []};
    shift @l;
    return [ map { $_->[2] } @l ];
}

cleanup();
db_exec("INSERT INTO servers (id,name) VALUES ($srvid,'cname-move-srv')");
db_exec("INSERT INTO zones (id,server,type,name) " .
        "VALUES ($zoneid,$srvid,'M','cname-move.example.')");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hosta,$zoneid,1,'host-a')");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hostb,$zoneid,1,'host-b')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hosta,'192.0.2.10')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hostb,'192.0.2.11')");
db_exec("INSERT INTO hosts (id,zone,type,domain,alias,ttl,info) " .
        "VALUES ($aliasid,$zoneid,4,'www',$hosta,600,'keep me')");

subtest 'alias initially points to host-a' => sub {
    my %h;
    is(get_host($aliasid, \%h), 0, "alias exists");
    is($h{alias}, $hosta, "alias target is host-a");
    is($h{alias_d}, 'host-a', "alias_d is host-a");
    is_deeply(alias_names($hosta), ['www'], "host-a lists the alias");
    is_deeply(alias_names($hostb), [], "host-b has no alias");
};

subtest 'move alias to host-b' => sub {
    my %h;
    get_host($aliasid, \%h);
    $h{alias} = $hostb;
    my $res = update_host(\%h);
    ok($res >= 0, "update_host succeeds") or diag("res=$res");

    my %n;
    is(get_host($aliasid, \%n), 0, "alias still exists");
    is($n{id}, $aliasid, "alias keeps its id");
    is($n{alias}, $hostb, "alias target is host-b");
    is($n{alias_d}, 'host-b', "alias_d is host-b");
    is($n{ttl}, 600, "TTL preserved");
    is($n{info}, 'keep me', "info preserved");
    is_deeply(alias_names($hosta), [], "host-a no longer lists the alias");
    is_deeply(alias_names($hostb), ['www'], "host-b lists the alias");
};

cleanup();
done_testing();
