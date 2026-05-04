#!/usr/bin/perl -I/opt/sauron

use strict;
use Sauron::DB;
use Sauron::Approval;
use Sauron::Sauron;
use Sauron::SetupIO;
use Data::Dumper;

# Initialize
load_config();
set_encoding();

unless (db_connect()) {
    die "Cannot connect to database\n";
}

print "=== WEB-BASED APPROVAL WORKFLOW TEST ===\n\n";

# Test 1: Get info about the most recent request
print "Step 1: Get latest approval request\n";
my @latest;
db_query("SELECT id, zone_id, policy_id, status, current_level FROM dns_change_requests ORDER BY id DESC LIMIT 1", \@latest);
my $latest_id = $latest[0][0] if (@latest > 0);
print "Latest request ID: $latest_id\n\n" if ($latest_id);

# Test 2: Get approval tokens for the latest request
print "Step 2: Check approval tokens for request $latest_id\n";
my @tokens;
db_query("SELECT request_id, level_id, user_id, decision, decided_at FROM dns_change_approval_tokens WHERE request_id = \$1 ORDER BY user_id", 
         \@tokens, $latest_id);

if (@tokens == 0) {
    print "No approval tokens found. Request may not need approval or hasn't been submitted yet.\n\n";
} else {
    print "Found " . scalar(@tokens) . " approval token(s):\n";
    for my $t (@tokens) {
        print "  Request: $t->[0], Level: $t->[1], Approver: $t->[2], Decision: " . 
              ($t->[3] ? $t->[3] : 'PENDING') . "\n";
    }
    print "\n";
}

# Test 3: Check if there are any pending approvals (decisions not yet recorded)
print "Step 3: Check for pending approvals\n";
my @pending;
db_query("SELECT id, user_id, level_id FROM dns_change_approval_tokens WHERE decision IS NULL", \@pending);

if (@pending == 0) {
    print "No pending approvals.\n\n";
} else {
    print "Found " . scalar(@pending) . " pending approval(s):\n";
    for my $p (@pending) {
        print "  Token ID: $p->[0], Approver user_id: $p->[1], Level: $p->[2]\n";
    }
    
    # Test the web-based approval function with first pending approval
    my $test_token = $pending[0];
    my $req_id = $test_token->[0];  # This won't work directly, need to get from query
    
    # Get request_id for this token
    my @req_info;
    db_query("SELECT request_id FROM dns_change_approval_tokens WHERE id = \$1", \@req_info, $test_token->[0]);
    if (@req_info > 0) {
        $req_id = $req_info[0][0];
        my $test_user_id = $test_token->[1];
        
        print "\n  Test record_approval_decision_web for request $req_id, user $test_user_id\n";
        
        # Try to record an approval decision
        my ($status, $msg) = record_approval_decision_web($req_id, $test_user_id, 'A', 'Test approval via web-based function');
        
        print "  Result: status='$status', msg='$msg'\n";
        
        # Check what happened
        my @check;
        db_query("SELECT decision, decided_at FROM dns_change_approval_tokens WHERE request_id = \$1 AND user_id = \$2", 
                 \@check, $req_id, $test_user_id);
        if (@check > 0) {
            print "  DB Check: decision=" . ($check[0][0] || 'NULL') . ", decided_at=" . ($check[0][1] || 'NULL') . "\n";
        }
    }
    print "\n";
}

# Test 4: Check approval level structure for policy 1
print "Step 4: Check approval level structure\n";
my @levels;
db_query("SELECT id, policy_id, level_order, level_type FROM approval_levels WHERE policy_id = 1 ORDER BY level_order", \@levels);

print "Levels for policy 1:\n";
for my $l (@levels) {
    print "  Level ID: $l->[0], Order: $l->[1], Type: " . ($l->[2] eq 'O' ? 'OR' : 'AND') . "\n";
    
    # Get approvers for this level
    my @approvers;
    db_query("SELECT user_id FROM approval_level_approvers WHERE level_id = \$1", \@approvers, $l->[0]);
    print "    Approvers: " . join(", ", map {$_->[0]} @approvers) . "\n";
}

print "\n=== END TEST ===\n";

db_disconnect();
