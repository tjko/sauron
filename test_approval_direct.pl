#!/usr/bin/perl
use strict;
use warnings;
use lib '/opt/sauron';

# Load configuration like CGI does
use Sauron::Sauron;
use Sauron::DB;
use Sauron::Approval;

# Load config
load_config();

# Connect to database
unless (db_connect2()) {
    die "Cannot connect to database: $DBI::errstr";
}

my $zone_id = 5;
my $operation = 'A';
my $host_type = 1;
my $domain = 'test21';

print "Testing check_approval_needed($zone_id, '$operation', $host_type, '$domain')\n";
print "DB_DSN: $main::DB_DSN\n";
print "\n";

my $policy_id = check_approval_needed($zone_id, $operation, $host_type, $domain);

if (defined $policy_id) {
    print "✓ RESULT: policy_id=$policy_id\n";
    print "  → Approval IS required for test21\n";
} else {
    print "✗ RESULT: undef\n";
    print "  → Approval NOT required (ERROR!)\n";
}

db_disconnect();
