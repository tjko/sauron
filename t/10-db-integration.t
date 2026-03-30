#!/usr/bin/perl
# t/10-db-integration.t - Integration tests requiring a running PostgreSQL
#
# These tests are skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove t/10-db-integration.t
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run DB integration tests';
}

use Sauron::DB;

# =========================================================================
# Database connection
# =========================================================================
subtest 'db_connect' => sub {
    my $ret = db_connect();
    is($ret, 0, 'db_connect succeeds');
};

# =========================================================================
# Basic query
# =========================================================================
subtest 'db_query simple' => sub {
    my @result;
    my $ret = db_query("SELECT 1 AS one", \@result);
    is($ret, 0, 'query returns 0');
    ok(@result > 0, 'got results');
    is($result[0][0], 1, 'value is 1');
};

# =========================================================================
# Schema check - pokemon base table should exist after createtables
# =========================================================================
subtest 'schema tables exist' => sub {
    my @result;
    my $ret = db_query(
        "SELECT table_name FROM information_schema.tables " .
        "WHERE table_schema = 'public' AND table_name = 'servers'",
        \@result
    );
    is($ret, 0, 'query ok');
    ok(@result > 0, 'servers table exists');
};

done_testing();
