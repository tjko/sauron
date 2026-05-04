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

my $request_id = 1;
my $user_id = 8;  # Michal Švamberg

# Get token for this user
my @token_data;
db_query("SELECT token FROM dns_change_approval_tokens WHERE request_id = \$1 AND user_id = \$2 AND decision IS NULL",
         \@token_data, $request_id, $user_id);

if (@token_data == 0) {
    print "No pending token found for request $request_id, user $user_id\n";
    my @all_tokens;
    db_query("SELECT id, user_id, decision FROM dns_change_approval_tokens WHERE request_id = \$1", \@all_tokens, $request_id);
    print "All tokens for request $request_id:\n";
    for my $t (@all_tokens) {
        print "  ID: $t->[0], user_id: $t->[1], decision: " . ($t->[2] || 'NULL') . "\n";
    }
    exit 1;
}

my $token = $token_data[0][0];
print "Found token: " . substr($token, 0, 16) . "...\n";

# Record decision
print "Calling record_decision with token=" . substr($token, 0, 16) . ", decision=A, reason='Test approval'\n";
my ($status, $msg) = record_decision($token, 'A', 'Test approval');
print "Result: status='$status', msg='$msg'\n";

# Check database
print "\nChecking database after record_decision:\n";
my @check_data;
db_query("SELECT id, user_id, decision, reason, decided_at FROM dns_change_approval_tokens WHERE request_id = \$1 AND user_id = \$2",
         \@check_data, $request_id, $user_id);
if (@check_data > 0) {
    print "Token decision: " . ($check_data[0][2] || 'NULL') . "\n";
    print "Token reason: " . ($check_data[0][3] || 'NULL') . "\n";
    print "Token decided_at: " . ($check_data[0][4] || 'NULL') . "\n";
}

db_disconnect();
print "Done.\n";
