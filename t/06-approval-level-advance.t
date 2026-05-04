#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib '.';
use Sauron::Approval;

my @db_exec_calls;
my @process_calls;
my @apply_calls;

no warnings qw(redefine prototype);
*Sauron::Approval::db_query = sub {
	my ($sql, $aref, @params) = @_;
	@$aref = ();

	if ($sql =~ /SELECT l\.level_order FROM approval_levels l, dns_change_requests r/ &&
	    $sql =~ /l\.level_order > \$2/ &&
	    $sql =~ /ORDER BY l\.level_order LIMIT 1/) {
		my ($request_id, $current_level) = @params;
		if ($request_id == 13 && $current_level == 2) {
			@$aref = ([10]);
		} elsif ($request_id == 99 && $current_level == 20) {
			@$aref = ();
		}
		return scalar @$aref;
	}

	return 0;
};

*Sauron::Approval::db_exec = sub {
	my ($sql) = @_;
	push @db_exec_calls, $sql;
	return 1;
};

*Sauron::Approval::process_approval_level = sub {
	my ($request_id) = @_;
	push @process_calls, $request_id;
	return 1;
};

*Sauron::Approval::apply_change = sub {
	my ($request_id) = @_;
	push @apply_calls, $request_id;
	return 1;
};

# Non-contiguous policy levels (1,2,10,20): advance from 2 to 10.
my ($status1, $msg1) = Sauron::Approval::_advance_or_apply(13, 2);
is($status1, 'ok', 'advance returns ok for next non-contiguous level');
is($msg1, 'Advanced to next level', 'advance returns expected message');
is(scalar @process_calls, 1, 'process_approval_level called once for advance');
is($process_calls[0], 13, 'process_approval_level called with request id');
is(scalar @apply_calls, 0, 'apply_change not called when higher level exists');
like($db_exec_calls[0], qr/SET current_level = 10 WHERE id = 13/, 'current_level updated to nearest higher level');

# No higher level: apply request.
my ($status2, $msg2) = Sauron::Approval::_advance_or_apply(99, 20);
is($status2, 'ok', 'apply returns ok when no next level exists');
is($msg2, 'Approved and applied', 'apply returns expected message');
is(scalar @apply_calls, 1, 'apply_change called once when no higher level');
is($apply_calls[0], 99, 'apply_change called with request id');

# Ensure no extra current_level update occurred in apply path.
is(scalar @db_exec_calls, 1, 'only one current_level update executed');

done_testing();
