#!/usr/bin/perl

=head1 Diagnostic Script for test19 Approval Workflow

This script checks why test19 was added to acad.cz without approval

=cut

use strict;
use warnings;
use lib '.';
use Sauron::DB;
use Sauron::Approval;

print "=== TEST19 APPROVAL WORKFLOW DIAGNOSTICS ===\n\n";

# Initialize database
my $dbh = db_connect();
die "Cannot connect to database!" unless $dbh;

my $zone_id = 5;  # acad.cz

# Step 1: Check host test19 exists
print "Step 1: Looking for host test19 in acad.cz\n";
my @hosts;
db_query("SELECT id, domain, type FROM hosts WHERE domain = 'test19' AND zone = ?", \@hosts, $zone_id);

if (@hosts) {
  print "  ✓ Found: ID=" . $hosts[0][0] . ", type=" . $hosts[0][2] . " (Host)\n";
} else {
  print "  ✗ Host test19 NOT FOUND in database\n";
  db_disconnect();
  exit 1;
}

# Step 2: Check approval policies for acad.cz
print "\nStep 2: Checking approval policies for acad.cz (zone_id=$zone_id)\n";
my @policies;
db_query("SELECT id, name, active, on_add, on_modify, on_delete, match_mode " .
         "FROM approval_policies WHERE zone_id = ?", \@policies, $zone_id);

if (@policies) {
  foreach my $p (@policies) {
    my ($pid, $pname, $active, $on_add, $on_mod, $on_del, $match_mode) = @$p;
    print "\n  Policy ID=$pid: '$pname'\n";
    print "    Active: " . ($active ? 'YES' : 'NO') . "\n";
    print "    on_add: " . ($on_add ? 'YES' : 'NO') . "\n";
    print "    on_modify: " . ($on_mod ? 'YES' : 'NO') . "\n";
    print "    on_delete: " . ($on_del ? 'YES' : 'NO') . "\n";
    print "    match_mode: $match_mode (O=OR, A=AND)\n";
    
    # Check rules for this policy
    print "\n    Rules for policy $pid:\n";
    my @rules;
    db_query("SELECT id, record_types, domain_regexp FROM approval_rules " .
             "WHERE policy_id = ?", \@rules, $pid);
    
    if (@rules) {
      foreach my $r (@rules) {
        my ($rid, $types, $re) = @$r;
        print "      Rule $rid:\n";
        print "        record_types: '" . ($types // '<ANY>') . "'\n";
        print "        domain_regexp: '" . ($re // '<ANY>') . "'\n";
      }
    } else {
      print "      (no rules - applies to all records)\n";
    }
  }
} else {
  print "  ✗ NO POLICIES FOUND for acad.cz\n";
  print "    This is likely the reason approval didn't trigger!\n";
}

# Step 3: Test check_approval_needed for test19
print "\nStep 3: Testing check_approval_needed() for test19\n";
print "  Operation: 'A' (Add)\n";
print "  Type: 1 (Host)\n";
print "  Domain: 'test19'\n";

my $policy_id = check_approval_needed($zone_id, 'A', 1, 'test19');

if (defined $policy_id) {
  print "  ✓ RESULT: Approval REQUIRED (policy_id=$policy_id)\n";
} else {
  print "  ✗ RESULT: Approval NOT required\n";
}

# Step 4: Check if approval request exists
print "\nStep 4: Checking for approval requests (dns_change_requests)\n";
my @requests;
db_query("SELECT id, operation, status FROM dns_change_requests " .
         "WHERE zone_id = ? AND host_id = ?", \@requests, $zone_id, $hosts[0][0]);

if (@requests) {
  foreach my $req (@requests) {
    print "  Request ID=" . $req->[0] . ", operation=" . $req->[1] . ", status=" . $req->[2] . "\n";
  }
} else {
  print "  ✗ NO APPROVAL REQUESTS FOUND\n";
  print "    This confirms the record was added WITHOUT approval!\n";
}

# Step 5: Check the code path
print "\nStep 5: Code Path Analysis\n";
print "  Host type 1 is assigned 'A' and 'AAAA' aliases in the approval system.\n";
print "  When check_approval_needed is called with:\n";
print "    - operation='A' (Add)\n";
print "    - host_type=1 (Host)\n";
print "    - domain='test19'\n";
print "\n  The function should check if ANY policy matches:\n";
print "    1. Policy must have zone_id=5 AND active=true AND on_add=true\n";
print "    2. For each policy, check if rules match:\n";
print "       - If record_types includes '1', 'HOST', 'A', or 'AAAA' (for type 1)\n";
print "       - If domain_regexp matches 'test19' (or is empty)\n";
print "       - If match_mode='O' (OR), need only 1 rule to match\n";
print "       - If match_mode='A' (AND), need ALL rules to match\n";

# Step 6: Detailed Rule Matching Analysis
print "\nStep 6: Detailed Rule Matching Analysis\n";
if (@policies) {
  foreach my $p (@policies) {
    my ($pid, $pname, $active, $on_add, $on_mod, $on_del, $match_mode) = @$p;
    
    if (!$active || !$on_add) {
      print "  Policy $pid: SKIPPED (not active or on_add=false)\n";
      next;
    }
    
    print "  Policy $pid: Checking rules\n";
    
    my @rules;
    db_query("SELECT id, record_types, domain_regexp FROM approval_rules " .
             "WHERE policy_id = ?", \@rules, $pid);
    
    if (!@rules) {
      print "    → NO RULES: Applies to ALL records\n";
      print "    → RESULT: ✓ MATCHES (no rules = match all)\n";
      next;
    }
    
    my $match_count = 0;
    foreach my $r (@rules) {
      my ($rid, $types, $re) = @$r;
      
      print "    Rule $rid:\n";
      
      # Check type match
      my $type_match = 1;
      if ($types && $types ne '') {
        $type_match = 0;
        my @type_list = split(/\s*,\s*/, $types);
        foreach my $t (@type_list) {
          if ($t eq '1' || uc($t) eq 'HOST' || uc($t) eq 'A' || uc($t) eq 'AAAA') {
            $type_match = 1;
            print "      Type: '$types' → MATCHES type=1 (Host/A/AAAA)\n";
            last;
          }
        }
        unless ($type_match) {
          print "      Type: '$types' → DOES NOT MATCH type=1\n";
        }
      } else {
        print "      Type: (any) → MATCHES\n";
      }
      
      # Check domain match
      my $domain_match = 1;
      if ($re && $re ne '') {
        $domain_match = 0;
        if ('test19' =~ /$re/) {
          $domain_match = 1;
          print "      Domain: regex '$re' → MATCHES 'test19'\n";
        } else {
          print "      Domain: regex '$re' → DOES NOT MATCH 'test19'\n";
        }
      } else {
        print "      Domain: (any) → MATCHES\n";
      }
      
      if ($type_match && $domain_match) {
        $match_count++;
        print "      Result: ✓ RULE MATCHES\n";
      } else {
        print "      Result: ✗ RULE DOES NOT MATCH\n";
      }
    }
    
    print "    Match count: $match_count / " . scalar(@rules) . "\n";
    
    if ($match_mode eq 'O') {
      if ($match_count > 0) {
        print "    Mode: OR → FINAL: ✓ MATCHES (at least 1 rule matched)\n";
      } else {
        print "    Mode: OR → FINAL: ✗ NO MATCH (no rules matched)\n";
      }
    } elsif ($match_mode eq 'A') {
      if ($match_count == scalar(@rules)) {
        print "    Mode: AND → FINAL: ✓ MATCHES (all rules matched)\n";
      } else {
        print "    Mode: AND → FINAL: ✗ NO MATCH (not all rules matched)\n";
      }
    }
  }
}

db_disconnect();
print "\n=== END DIAGNOSTICS ===\n";
