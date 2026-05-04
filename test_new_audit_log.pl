#!/usr/bin/perl -I/opt/sauron

=head1 Create Test Approval Request

Create a new DNS change request and verify audit log is properly recorded.

=cut

use strict;
use warnings;
use Sauron::DB;
use Sauron::Approval;
use Sauron::BackEnd;
use Sauron::SetupIO;
use Sauron::Sauron;

set_encoding();
load_config();

unless (db_connect()) {
	print "Failed to connect to database\n";
	exit 1;
}

# Get test zone and user
my @zones;
db_query("SELECT id FROM zones WHERE name LIKE '%example%' LIMIT 1", \@zones);
unless (@zones > 0) {
	print "Could not find test zone\n";
	exit 1;
}
my $zone_id = $zones[0][0];

my @users;
db_query("SELECT id FROM users WHERE id > 0 LIMIT 1", \@users);
unless (@users > 0) {
	print "Could not find any user\n";
	exit 1;
}
my $user_id = $users[0][0];

# Get policy for this zone
my @policies;
db_query("SELECT id FROM approval_policies WHERE zone_id = \$1 LIMIT 1", \@policies, $zone_id);
my $policy_id = (@policies > 0 ? $policies[0][0] : 0);

print "Zone ID: $zone_id\n";
print "User ID: $user_id\n";
print "Policy ID: $policy_id\n\n";

# Create a test request
my $change_data = {
	domain => 'testaudit.example.com',
	type => 1,
	ip => [[0, '192.0.2.100']]
};

my $req_id = submit_change_request(
	$zone_id,
	$policy_id,
	$user_id,
	'admin@example.com',
	'A',  # Add operation
	0,    # No host_id
	$change_data,
	undef,
	'Test audit log recording'
);

if (!$req_id) {
	print "Failed to create request\n";
	db_disconnect();
	exit 1;
}

print "Created request ID: $req_id\n\n";

# Check audit log
my @audit_log;
db_query("SELECT id, user_id, user_name, event, message, created_at " .
	 "FROM dns_change_audit_log WHERE request_id = \$1 " .
	 "ORDER BY id ASC", \@audit_log, $req_id);

print "=== AUDIT LOG FOR REQUEST #$req_id ===\n\n";

my %event_names = (
	'S' => 'Submitted',
	'E' => 'Email',
	'A' => 'Approved',
	'R' => 'Rejected',
);

for my $entry (@audit_log) {
	my ($id, $uid, $uname, $event, $msg, $created) = @$entry;
	my $event_name = $event_names{$event} || "Unknown ($event)";
	
	printf("%-3d | %-40s | %-15s | %s\n",
		$id, 
		"user_name=" . ($uname ? "'$uname'" : "NULL"),
		"user_id=$uid",
		$event_name);
}

print "\n";
# Exit without cleanup
