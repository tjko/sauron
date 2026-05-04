#!/usr/bin/perl -I/opt/sauron

=head1 Test Audit Log Recording

Test that audit log properly records:
- Submitted event with requestor username
- Email events with 'system' user
- Approval/Rejection events with approver username

=cut

use strict;
use warnings;
use Sauron::DB;
use Sauron::Approval;
use Sauron::SetupIO;
use Sauron::Sauron;

set_encoding();
load_config();

unless (db_connect()) {
	print "Failed to connect to database\n";
	exit 1;
}

# Test request #10 audit log
my @audit_log;
db_query("SELECT id, user_id, user_name, event, message, created_at " .
	 "FROM dns_change_audit_log WHERE request_id = 10 " .
	 "ORDER BY id ASC", \@audit_log);

print "=== AUDIT LOG FOR REQUEST #10 ===\n\n";
print "Found " . scalar(@audit_log) . " audit entries:\n\n";

my %event_names = (
	'S' => 'Submitted',
	'E' => 'Email',
	'A' => 'Approved',
	'R' => 'Rejected',
	'P' => 'Applied',
	'X' => 'Error',
	'C' => 'Changed'
);

for my $entry (@audit_log) {
	my ($id, $uid, $uname, $event, $msg, $created) = @$entry;
	my $event_name = $event_names{$event} || "Unknown ($event)";
	
	printf("%-3d | %-30s | %-15s | %-40s | %s\n",
		$id, 
		($uname ? $uname : 'NULL'),
		"user_id=$uid",
		$event_name,
		$msg || '');
}

print "\n=== EXPECTED RESULTS ===\n";
print "- ID 40: 'Submitted' should have requestor username in user_name\n";
print "- ID 41: 'Email' should have 'system' in user_name\n";
print "- ID 42: 'Rejected' should have approver username in user_name\n";

print "\n=== ANALYSIS ===\n";

if (@audit_log >= 3) {
	my ($id40_uname) = @{$audit_log[0]}[2];
	my ($id41_uname) = @{$audit_log[1]}[2];
	my ($id42_uname) = @{$audit_log[2]}[2];
	
	if ($id40_uname && $id40_uname ne '') {
		print "✓ Submitted event has username\n";
	} else {
		print "✗ Submitted event MISSING username (got: '$id40_uname')\n";
	}
	
	if ($id41_uname && $id41_uname eq 'system') {
		print "✓ Email event has 'system' username\n";
	} else {
		print "✗ Email event MISSING 'system' username (got: '$id41_uname')\n";
	}
	
	if ($id42_uname && $id42_uname ne '') {
		print "✓ Rejected event has username\n";
	} else {
		print "✗ Rejected event MISSING username (got: '$id42_uname')\n";
	}
} else {
	print "✗ Not enough audit entries found\n";
}

print "\n";
db_disconnect();
