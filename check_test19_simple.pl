#!/usr/bin/perl

use strict;
use warnings;
use lib '.';
use Sauron::DB;
use Sauron::Approval;

open(OUT, '>', '/tmp/test19_check.txt') or die "Cannot open output file: $!";

sub pout {
  my $msg = shift;
  print OUT $msg;
  print $msg;  # Also print to screen
}

pout "=== TEST19 APPROVAL WORKFLOW CHECK ===\n\n";

# Initialize database
my $dbh = db_connect();
die "Cannot connect to database!" unless $dbh;

my $zone_id = 5;  # acad.cz

# Check 1: Host test19
pout "Check 1: Finding host test19 in zone acad.cz (zone_id=$zone_id)\n";
my @hosts;
db_query("SELECT id, domain, type FROM hosts WHERE domain = 'test19' AND zone = ?", \@hosts, $zone_id);

if (@hosts) {
  pout "✓ FOUND: host_id=" . $hosts[0][0] . ", domain='" . $hosts[0][1] . "', type=" . $hosts[0][2] . "\n";
  my $host_id = $hosts[0][0];
  my $host_type = $hosts[0][2];
  
  # Check 2: Approval policies
  pout "\nCheck 2: Finding approval policies for acad.cz\n";
  my @policies;
  db_query("SELECT id, name, active, on_add, on_modify, match_mode " .
           "FROM approval_policies WHERE zone_id = ?", \@policies, $zone_id);
  
  if (@policies) {
    pout "✓ FOUND " . scalar(@policies) . " policy(ies):\n";
    
    foreach my $p (@policies) {
      my ($pid, $pname, $active, $on_add, $on_mod, $match_mode) = @$p;
      pout "\n  Policy ID=$pid:\n";
      pout "    name: '$pname'\n";
      pout "    active: " . ($active ? 'true' : 'false') . "\n";
      pout "    on_add: " . ($on_add ? 'true' : 'false') . "\n";
      pout "    on_modify: " . ($on_mod ? 'true' : 'false') . "\n";
      pout "    match_mode: $match_mode (O=OR, A=AND)\n";
      
      # Get rules for this policy
      pout "    Rules:\n";
      my @rules;
      db_query("SELECT id, record_types, domain_regexp FROM approval_rules WHERE policy_id = ?", \@rules, $pid);
      
      if (@rules) {
        foreach my $r (@rules) {
          pout "      Rule " . $r->[0] . ": record_types='" . ($r->[1] // '(any)') . "', domain_regexp='" . ($r->[2] // '(any)') . "'\n";
        }
      } else {
        pout "      (no rules - applies to all records)\n";
      }
    }
  } else {
    pout "✗ NO POLICIES FOUND for acad.cz\n";
    pout "  → This explains why approval didn't trigger!\n";
  }
  
  # Check 3: Test check_approval_needed
  pout "\nCheck 3: Testing check_approval_needed() function\n";
  pout "  Calling: check_approval_needed($zone_id, 'A', $host_type, 'test19')\n";
  
  my $policy_id = check_approval_needed($zone_id, 'A', $host_type, 'test19');
  
  if (defined $policy_id) {
    pout "✓ Result: policy_id=$policy_id (APPROVAL REQUIRED)\n";
  } else {
    pout "✗ Result: undef (NO APPROVAL REQUIRED)\n";
    pout "  → This confirms approval was NOT triggered\n";
  }
  
  # Check 4: Host type aliases
  pout "\nCheck 4: Host type $host_type aliases\n";
  my @aliases = @{$Sauron::Approval::host_type_aliases{$host_type} || []};
  pout "  Type $host_type aliases: [" . join(', ', @aliases) . "]\n";
  
  # Check 5: Look for any approval requests
  pout "\nCheck 5: Looking for approval requests for test19\n";
  my @requests;
  db_query("SELECT id, operation, status FROM dns_change_requests WHERE zone_id = ? AND host_id = ?", \@requests, $zone_id, $host_id);
  
  if (@requests) {
    pout "✓ FOUND " . scalar(@requests) . " request(s):\n";
    foreach my $req (@requests) {
      pout "  Request ID=" . $req->[0] . ", operation=" . $req->[1] . ", status=" . $req->[2] . "\n";
    }
  } else {
    pout "✗ NO APPROVAL REQUESTS found\n";
    pout "  → Confirms that host was added WITHOUT approval workflow\n";
  }
  
} else {
  pout "✗ HOST test19 NOT FOUND in database\n";
}

# Summary
pout "\n=== SUMMARY ===\n";
pout "If 'NO APPROVAL REQUIRED' appears in Check 3, then one of these is true:\n";
pout "  1. No approval policies exist for acad.cz\n";
pout "  2. Policies exist but are inactive (active != true)\n";
pout "  3. Policies have on_add=false\n";
pout "  4. Policies exist but rules don't match type $host_type (Host) or domain 'test19'\n";
pout "\nMost likely: Approval rules are configured incorrectly\n";
pout "Check that record_types in rules contains '1', 'HOST', 'A', or 'AAAA'\n";

db_disconnect();
pout "\n=== END ===\n";

close(OUT);
print "\nOutput saved to /tmp/test19_check.txt\n";
