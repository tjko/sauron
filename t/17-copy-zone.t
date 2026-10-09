#!/usr/bin/perl
# t/17-copy-zone.t - copy_zone() (web UI "Copy zone")
#
# Copies a master zone with a host, A record and allow-transfer entry and
# checks that the copy is really stored.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/17-copy-zone.t
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
    plan skip_all => 'Set SAURON_TEST_DSN to run copy_zone DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('copy-test');

my $srvid  = 910001;
my $zoneid = 910002;
my $hostid = 910003;

sub cleanup {
    my @z;
    db_query("SELECT id FROM zones WHERE server=$srvid", \@z);
    my $zl = join(',', $zoneid, map { $_->[0] } @z);
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone IN ($zl))");
    db_exec("DELETE FROM hosts WHERE zone IN ($zl)");
    db_exec("DELETE FROM cidr_entries WHERE ref IN ($zl)");
    db_exec("DELETE FROM zones WHERE id IN ($zl)");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

cleanup();
db_exec("INSERT INTO servers (id,name) VALUES ($srvid,'copy-test-srv')");
db_exec("INSERT INTO zones (id,server,type,name) " .
        "VALUES ($zoneid,$srvid,'M','copy.example.')");
db_exec("INSERT INTO hosts (id,zone,type,domain) " .
        "VALUES ($hostid,$zoneid,1,'www')");
db_exec("INSERT INTO a_entries (host,ip) VALUES ($hostid,'192.0.2.80')");
db_exec("INSERT INTO cidr_entries (type,ref,mode,ip) " .
        "VALUES (5,$zoneid,0,'192.0.2.53')");

subtest 'copy_zone stores the copy' => sub {
    my $newid = copy_zone($zoneid, $srvid, 'copy2.example.', 0);
    ok($newid > 0, "copy_zone returns new id") or diag("res=$newid");

    my %c;
    is(get_zone($newid, \%c), 0, "copied zone exists");
    is($c{name}, 'copy2.example.', "copied zone name");
    is($c{type}, 'M', "copied zone type");

    my @a;
    db_query("SELECT h.domain,a.ip FROM hosts h, a_entries a " .
             "WHERE a.host=h.id AND h.zone=$newid", \@a);
    is(scalar(@a), 1, "host with A record copied");
    is($a[0][0], 'www', "host name copied");
    like($a[0][1], qr{^192\.0\.2\.80(/32)?$}, "A record copied");

    my @t;
    db_query("SELECT ip FROM cidr_entries WHERE type=5 AND ref=$newid", \@t);
    is(scalar(@t), 1, "allow-transfer entry copied");
};

cleanup();
done_testing();
