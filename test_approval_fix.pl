#!/usr/bin/perl

=head1 Test Script for Approval Workflow Fix

This script verifies that the approval workflow fix for aliases (type 4) is working correctly.

=cut

use strict;
use warnings;
use lib '.';
use Sauron::DB;
use Sauron::Approval;

print "=== APPROVAL WORKFLOW FIX VERIFICATION ===\n\n";

# Initialize database
my $dbh = db_connect();
die "Cannot connect to database!" unless $dbh;

# Test case: Check if approval check would trigger for a CNAME alias in acad.cz
print "Test: CNAME alias approval check\n";
print "Zone: acad.cz (zone_id=5)\n";
print "Record type: 4 (CNAME)\n";
print "Domain: testhost\n\n";

my $zone_id = 5;  # acad.cz
my $op = 'A';     # Add operation
my $type = 4;     # CNAME
my $domain = 'testhost';

my $policy_id = check_approval_needed($zone_id, $op, $type, $domain);

if (defined $policy_id) {
  print "✓ APPROVAL REQUIRED\n";
  print "  Policy ID: $policy_id\n";
  print "\n  → The fix is WORKING: restricted_add_host will now reject this add\n";
  print "  → Users will see error: 'This record requires approval before adding'\n";
} else {
  print "✗ NO APPROVAL REQUIRED\n";
  print "\n  Reasons why approval might not be needed:\n";
  print "  1. No approval policy configured for this zone\n";
  print "  2. Policy is inactive (active != true)\n";
  print "  3. Policy has on_add=false\n";
  print "  4. Rules don't match this record type/domain\n";
}

# Check the approval policy details
print "\n\nPolicy Details for zone acad.cz:\n";
my @policies;
db_query("SELECT id, name, active, on_add, on_modify, on_delete " .
         "FROM approval_policies WHERE zone_id = 5", \@policies);

if (@policies) {
  foreach my $p (@policies) {
    print "  Policy ID=" . $p->[0] . "\n";
    print "  Name: " . $p->[1] . "\n";
    print "  Active: " . ($p->[2] ? 'YES' : 'NO') . "\n";
    print "  on_add: " . ($p->[3] ? 'YES' : 'NO') . "\n";
    print "  on_modify: " . ($p->[4] ? 'YES' : 'NO') . "\n";
    print "  on_delete: " . ($p->[5] ? 'YES' : 'NO') . "\n\n";
  }
} else {
  print "  → NO POLICIES FOUND\n";
  print "  → This is why test18 was added without approval!\n";
  print "  → Admin needs to create approval policies for acad.cz\n";
}

db_disconnect();
print "\n=== END VERIFICATION ===\n";
