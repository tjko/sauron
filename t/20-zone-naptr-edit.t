#!/usr/bin/perl
# t/20-zone-naptr-edit.t - update_zone() saves zone apex NAPTR entries
#
# Rows of the zone 'naptr' list carry the add/update/delete state after the
# id and 7 fields; update_zone() must read it from there. Checks that adding,
# modifying and deleting a NAPTR entry through get_zone() -> update_zone()
# reaches the database.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/20-zone-naptr-edit.t
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
    plan skip_all => 'Set SAURON_TEST_DSN to run zone NAPTR DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('naptr-test');

my $srvid  = 940001;
my $zoneid = 940002;
my $apexid = 940003;

sub cleanup {
    db_exec("DELETE FROM naptr_entries WHERE type=1 AND ref=$apexid");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

sub db_naptr {
    my @q;
    db_query("SELECT order_val,preference,service,comment FROM naptr_entries " .
             "WHERE type=1 AND ref=$apexid ORDER BY id", \@q);
    return \@q;
}

# Load the zone, let $edit change its naptr list, save it
sub edit_zone {
    my ($edit) = @_;
    my %zone;
    get_zone($zoneid, \%zone) == 0 or BAIL_OUT("get_zone($zoneid) failed");
    $edit->($zone{naptr});
    cmp_ok(update_zone(\%zone), '>=', 0, 'update_zone succeeds');
}

cleanup();
setup_ok("INSERT INTO servers (id,name) VALUES ($srvid,'naptr-test')");
setup_ok("INSERT INTO zones (id,server,type,name,reverse) " .
         "VALUES ($zoneid,$srvid,'M','naptr.example',false)");
setup_ok("INSERT INTO hosts (id,zone,type,domain) VALUES ($apexid,$zoneid,10,'\@')");

subtest 'add' => sub {
    edit_zone(sub {
        push @{$_[0]}, [undef, 100, 10, 'U', 'E2U+sip',
                        '!^.*$!sip:info@example.com!', '.', 'c1', 2];
    });
    is_deeply(db_naptr(), [[100, 10, 'E2U+sip', 'c1']], 'NAPTR added');
};

subtest 'modify' => sub {
    edit_zone(sub { my $row = $_[0][1]; @$row[1, 7, 8] = (200, 'c2', 1); });
    is_deeply(db_naptr(), [[200, 10, 'E2U+sip', 'c2']], 'NAPTR updated');
};

subtest 'delete' => sub {
    edit_zone(sub { $_[0][1][8] = -1; });
    is_deeply(db_naptr(), [], 'NAPTR deleted');
};

cleanup();
done_testing();
