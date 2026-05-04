#!/usr/bin/perl -I/opt/sauron

use strict;
use Sauron::DB;
use Sauron::Approval;
use Sauron::Sauron;
use Sauron::SetupIO;

# Initialize
load_config();
set_encoding();

unless (db_connect()) {
    die "Cannot connect to database\n";
}

print "=== TEST record_approval_decision_web ===\n\n";

# Request 2 has token for user 8
my $req_id = 2;
my $user_id = 8;

print "Testing request $req_id with user $user_id\n\n";

# Check current state
print "Current state:\n";
my @current;
db_query("SELECT request_id, policy_id, current_level, status FROM dns_change_requests WHERE id = \$1", 
         \@current, $req_id);
if (@current > 0) {
    print "  Request status: " . $current[0][3] . ", Level: " . $current[0][2] . ", Policy: " . $current[0][1] . "\n";
}

my @tokens;
db_query("SELECT user_id, decision FROM dns_change_approval_tokens WHERE request_id = \$1",
         \@tokens, $req_id);
print "  Tokens: " . scalar(@tokens) . " total\n";
for my $t (@tokens) {
    print "    User $t->[0]: decision=" . ($t->[1] ? $t->[1] : 'PENDING') . "\n";
}

print "\nCalling record_approval_decision_web(\$req_id=$req_id, \$user_id=$user_id, 'A', 'Test approval')\n";

my ($status, $msg) = record_approval_decision_web($req_id, $user_id, 'A', 'Test approval');

print "  Result: status='$status', msg='$msg'\n\n";

# Check what changed
print "After record_approval_decision_web:\n";
my @after;
db_query("SELECT request_id, policy_id, current_level, status FROM dns_change_requests WHERE id = \$1", 
         \@after, $req_id);
if (@after > 0) {
    print "  Request status: " . $after[0][3] . ", Level: " . $after[0][2] . ", Policy: " . $after[0][1] . "\n";
}

my @after_tokens;
db_query("SELECT user_id, decision, decided_at FROM dns_change_approval_tokens WHERE request_id = \$1",
         \@after_tokens, $req_id);
print "  Tokens after:\n";
for my $t (@after_tokens) {
    print "    User $t->[0]: decision=" . ($t->[1] ? $t->[1] : 'PENDING') . ", decided_at=" . ($t->[2] ? 'YES' : 'NO') . "\n";
}

print "\n=== END TEST ===\n";
