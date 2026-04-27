# Sauron::Approval.pm -- DNS change approval workflow
#
package Sauron::Approval;
require Exporter;
use Sauron::DB;
use Sauron::BackEnd;
use Sauron::Util;
use Sauron::Sauron;
use Sauron::SetupIO;
use Digest::MD5 qw(md5_hex);
use Data::Dumper;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '1.0';

@ISA = qw(Exporter);
@EXPORT = qw(
	check_approval_needed
	submit_change_request
	process_approval_level
	record_decision
	apply_change
	send_reminder_emails
	get_zone_pending_requests
	get_user_pending_approvals
);

my %host_type_aliases = (
	0 => ['ANY'],
	1 => ['HOST','A','AAAA'],
	2 => ['DELEGATION','NS','DS'],
	3 => ['MX'],
	4 => ['ALIAS','CNAME'],
	5 => ['PRINTER'],
	6 => ['GLUE','A','AAAA'],
	7 => ['AREC','AREC_ALIAS'],
	8 => ['SRV'],
	9 => ['DHCP'],
	10 => ['ZONE'],
	11 => ['SSHFP'],
	12 => ['TLSA'],
	13 => ['TXT'],
	14 => ['NAPTR'],
	15 => ['CAA'],
	101 => ['RESERVATION','A','AAAA','DHCP']
);


# check_approval_needed(zone_id, operation, host_type, domain)
#   Returns policy_id if approval is needed, undef otherwise.
sub check_approval_needed {
	my ($zone_id, $operation, $host_type, $domain) = @_;
	my ($flag_col, @pols, @rules);
	my $i;

	return undef unless ($zone_id > 0);
	return undef unless ($operation =~ /^[AMD]$/);

	$flag_col = ($operation eq 'A' ? 'on_add' :
		     $operation eq 'M' ? 'on_modify' :
		     'on_delete');

	db_query("SELECT id, match_mode FROM approval_policies " .
		 "WHERE zone_id = \$1 AND active = true AND $flag_col = true",
		 \@pols, $zone_id);

	for $i (0..$#pols) {
		my ($policy_id, $match_mode) = @{$pols[$i]};
		my @r; my $rmatch; my $match_count = 0; my $rule_count = 0;

		db_query("SELECT record_types, domain_regexp FROM approval_rules " .
			 "WHERE policy_id = \$1", \@r, $policy_id);
		$rule_count = scalar @r;

		if ($rule_count == 0) {
			return $policy_id;
		}

		for my $ri (0..$#r) {
			my ($types, $re) = @{$r[$ri]};
			my $types_ok = 1;
			my $re_ok = 1;

			if (defined $types && $types ne '') {
				$types_ok = 0;
				my @aliases = @{$host_type_aliases{$host_type} || []};
				my %alias_set = map { uc($_) => 1 } @aliases;
				for my $t (split(/\s*,\s*/, $types)) {
					next if ($t eq '');
					if ($t =~ /^\d+$/ && $t == $host_type) {
						$types_ok = 1;
						last;
					}
					if ($t =~ /^re:(.+)$/i) {
						my $tre = $1;
						eval {
							for my $an (@aliases) {
								if ($an =~ /$tre/i) { $types_ok = 1; last; }
							}
						};
						if ($@) {
							write2log("approval: invalid record_types regexp '$tre' for policy $policy_id");
						}
						last if ($types_ok);
						next;
					}
					if ($alias_set{uc($t)}) {
						$types_ok = 1;
						last;
					}
				}
			}

			if (defined $re && $re ne '') {
				$re_ok = 0;
				eval {
					$re_ok = ($domain =~ /$re/) ? 1 : 0;
				};
				if ($@) {
					write2log("approval: invalid regexp '$re' for policy $policy_id");
					$re_ok = 0;
				}
			}

			if ($types_ok && $re_ok) {
				$match_count++;
				if ($match_mode eq 'O') {
					return $policy_id;
				}
			}
		}

		if ($match_mode eq 'A' && $match_count == $rule_count) {
			return $policy_id;
		}
	}

	return undef;
}


# submit_change_request(...) -> request_id or undef
sub submit_change_request {
	my ($zone_id, $policy_id, $requestor_id, $requestor_email,
	    $operation, $host_id, $change_data_ref, $original_data_ref, $reason) = @_;
	my ($change_data, $original_data, $res, $request_id);

	return undef unless ($zone_id > 0 && $requestor_id > 0);
	return undef unless ($operation =~ /^[AMD]$/);

	$change_data = _serialize($change_data_ref);
	$original_data = _serialize($original_data_ref) if ($original_data_ref);

	$res = db_exec("INSERT INTO dns_change_requests " .
		       "(zone_id, policy_id, requestor_id, requestor_email, " .
		       "operation, status, current_level, host_id, change_data, " .
		       "original_data, reason) " .
		       "VALUES (" .
		       $zone_id . "," .
		       ($policy_id > 0 ? $policy_id : 'NULL') . "," .
		       $requestor_id . "," .
		       db_encode_str($requestor_email) . "," .
		       db_encode_str($operation) . "," .
		       "'P',1," .
		       ($host_id > 0 ? $host_id : 'NULL') . "," .
		       db_encode_str($change_data) . "," .
		       db_encode_str($original_data) . "," .
		       db_encode_str($reason) . ") " .
		       "RETURNING id");
	return undef if ($res < 0);

	$request_id = db_lastid();
	return undef unless ($request_id > 0);

	_audit($request_id, $requestor_id, undef, 'S', 1, 'Request submitted');
	process_approval_level($request_id);

	return $request_id;
}


# process_approval_level(request_id)
sub process_approval_level {
	my ($request_id) = @_;
	my (@rq, @lv, @ap);
	my ($policy_id, $current_level, $level_id, $level_order, $level_type);

	db_query("SELECT policy_id, current_level FROM dns_change_requests " .
		 "WHERE id = \$1", \@rq, $request_id);
	return 0 unless (@rq > 0);
	($policy_id, $current_level) = @{$rq[0]};

	db_query("SELECT id, level_order, level_type FROM approval_levels " .
		 "WHERE policy_id = \$1 AND level_order = \$2", \@lv,
		 $policy_id, $current_level);

	if (@lv == 0) {
		return apply_change($request_id);
	}

	($level_id, $level_order, $level_type) = @{$lv[0]};

	db_query("SELECT user_id FROM approval_level_approvers WHERE level_id = \$1",
		 \@ap, $level_id);
	return 0 unless (@ap > 0);

	for my $ai (0..$#ap) {
		my $user_id = $ap[$ai][0];
		my $token = _generate_token();
		my $ttl = $main::SAURON_APPROVAL_TOKEN_TTL_HOURS || 72;
		my $res = db_exec("INSERT INTO dns_change_approval_tokens " .
			 "(request_id, level_id, user_id, token, token_expires) " .
			 "VALUES (" .
			 $request_id . "," .
			 $level_id . "," .
			 $user_id . "," .
			 db_encode_str($token) . "," .
			 "CURRENT_TIMESTAMP + (INTERVAL '" . $ttl . " hours')) " .
			 "RETURNING id");
		if ($res < 0) {
			write2log("approval: failed to insert token for request $request_id");
			next;
		}
		my $token_id = db_lastid();
		_send_approval_email($token_id);
	}

	return 1;
}


# record_decision(token, decision, reason) -> (status, message)
sub record_decision {
	my ($token, $decision, $reason) = @_;
	my (@tok, @lvl, @all);
	my ($token_id, $request_id, $level_id, $user_id, $expires);
	my ($level_type, $level_order, $pending, $approved, $rejected);

	return ('error', 'Invalid decision') unless ($decision =~ /^[AR]$/);

	db_query("SELECT id, request_id, level_id, user_id, token_expires " .
		 "FROM dns_change_approval_tokens WHERE token = \$1", \@tok, $token);
	return ('error', 'Invalid token') unless (@tok > 0);
	($token_id, $request_id, $level_id, $user_id, $expires) = @{$tok[0]};

	if (defined $expires) {
		my @t; db_query("SELECT (token_expires < CURRENT_TIMESTAMP) " .
			 "FROM dns_change_approval_tokens WHERE id = \$1", \@t, $token_id);
		if (@t > 0 && $t[0][0] eq 't') {
			_audit($request_id, $user_id, undef, 'X', undef, 'Token expired');
			return ('error', 'Token expired');
		}
	}

	my $res = db_exec("UPDATE dns_change_approval_tokens SET " .
		       "decision = " . db_encode_str($decision) . ", " .
		       "reason = " . db_encode_str($reason) . ", " .
		       "decided_at = CURRENT_TIMESTAMP " .
		       "WHERE id = " . $token_id . " AND decision IS NULL");
	return ('error', 'Decision already recorded') if ($res < 1);

	_audit($request_id, $user_id, undef, ($decision eq 'A' ? 'A' : 'R'),
	       undef, $reason);

	db_query("SELECT level_type, level_order FROM approval_levels WHERE id = \$1",
		 \@lvl, $level_id);
	return ('error', 'Level not found') unless (@lvl > 0);
	($level_type, $level_order) = @{$lvl[0]};

	db_query("SELECT decision FROM dns_change_approval_tokens " .
		 "WHERE request_id = \$1 AND level_id = \$2", \@all,
		 $request_id, $level_id);

	$pending = 0; $approved = 0; $rejected = 0;
	for my $i (0..$#all) {
		my $d = $all[$i][0];
		if (!defined $d || $d eq '') {
			$pending++;
		} elsif ($d eq 'A') {
			$approved++;
		} elsif ($d eq 'R') {
			$rejected++;
		}
	}

	if ($level_type eq 'O') {
		if ($approved > 0) {
			return _advance_or_apply($request_id, $level_order);
		}
		if ($pending == 0 && $rejected > 0) {
			return _reject_request($request_id, $reason);
		}
		return ('pending', 'Waiting for other approvals');
	}

	# AND
	if ($rejected > 0) {
		return _reject_request($request_id, $reason);
	}
	if ($pending == 0 && $approved > 0) {
		return _advance_or_apply($request_id, $level_order);
	}

	return ('pending', 'Waiting for other approvals');
}


# apply_change(request_id) -> 1/0
sub apply_change {
	my ($request_id) = @_;
	my (@rq, @usr);
	my ($operation, $host_id, $change_data, $original_data, $requestor_id);
	my ($requestor_name, $status);

	db_query("SELECT requestor_id, operation, host_id, change_data, original_data " .
		 "FROM dns_change_requests WHERE id = \$1", \@rq, $request_id);
	return 0 unless (@rq > 0);
	($requestor_id, $operation, $host_id, $change_data, $original_data) = @{$rq[0]};

	db_query("SELECT username FROM users WHERE id = \$1", \@usr, $requestor_id);
	$requestor_name = (@usr > 0 ? $usr[0][0] : 'approval');
	set_muser($requestor_name);

	my $rec = _deserialize($change_data);
	if (!$rec || ref($rec) ne 'HASH') {
		write2log("approval: invalid change_data for request $request_id");
		return 0;
	}

	if ($operation eq 'A') {
		$status = add_host($rec);
	} elsif ($operation eq 'M') {
		$rec->{id} = $host_id if ($host_id > 0 && !defined $rec->{id});
		$status = update_host($rec);
	} else {
		$status = delete_host($host_id);
	}

	if ($status < 0) {
		write2log("approval: apply failed for request $request_id (status $status)");
		return 0;
	}

	db_exec("UPDATE dns_change_requests SET status = 'A' WHERE id = " . $request_id);
	_audit($request_id, $requestor_id, $requestor_name, 'P', undef, 'Applied');
	_send_decision_email($request_id, 'A');
	return 1;
}


# send_reminder_emails(hours) -> count
sub send_reminder_emails {
	my ($hours) = @_;
	my (@q, $count, $i);

	$hours = 24 unless ($hours > 0);
	$count = 0;

	db_query("SELECT id FROM dns_change_approval_tokens " .
		 "WHERE decision IS NULL AND " .
		 "(email_sent IS NULL OR email_sent < (CURRENT_TIMESTAMP - (\$1 || ' hours')::interval)) " .
		 "AND (token_expires IS NULL OR token_expires > CURRENT_TIMESTAMP)",
		 \@q, $hours);

	for $i (0..$#q) {
		my $token_id = $q[$i][0];
		if (_send_approval_email($token_id)) {
			$count++;
		}
	}

	return $count;
}


# get_zone_pending_requests(zone_id) -> list
sub get_zone_pending_requests {
	my ($zone_id) = @_;
	my @q;
	db_query("SELECT id, requestor_id, requestor_email, operation, status, current_level, " .
		 "cdate, change_data FROM dns_change_requests WHERE zone_id = \$1 AND status = 'P' " .
		 "ORDER BY cdate", \@q, $zone_id);
	return @q;
}


# get_user_pending_approvals(user_id) -> list
sub get_user_pending_approvals {
	my ($user_id) = @_;
	my @q;
	db_query("SELECT t.request_id, r.zone_id, r.operation, r.cdate " .
		 "FROM dns_change_approval_tokens t, dns_change_requests r " .
		 "WHERE t.user_id = \$1 AND t.decision IS NULL AND t.request_id = r.id " .
		 "ORDER BY r.cdate", \@q, $user_id);
	return @q;
}


# ---- internal helpers -------------------------------------------------

sub _advance_or_apply {
	my ($request_id, $level_order) = @_;
	my (@nxt);

	db_query("SELECT id FROM approval_levels l, dns_change_requests r " .
		 "WHERE r.id = \$1 AND l.policy_id = r.policy_id AND l.level_order = \$2",
		 \@nxt, $request_id, $level_order + 1);

	if (@nxt > 0) {
		db_exec("UPDATE dns_change_requests SET current_level = " .
			($level_order + 1) . " WHERE id = " . $request_id);
		process_approval_level($request_id);
		return ('ok', 'Advanced to next level');
	}

	if (apply_change($request_id)) {
		return ('ok', 'Approved and applied');
	}

	return ('error', 'Failed to apply change');
}

sub _reject_request {
	my ($request_id, $reason) = @_;
	db_exec("UPDATE dns_change_requests SET status = 'R' WHERE id = " . $request_id);
	_audit($request_id, undef, undef, 'R', undef, $reason);
	_send_decision_email($request_id, 'R');
	return ('rejected', 'Request rejected');
}

sub _send_approval_email {
	my ($token_id) = @_;
	my (@q, $token, $email, $req_id, $zone_id, $operation);
	my ($base_url, $path, $url);

	return 0 unless ($token_id > 0);
	return 0 unless ($main::SAURON_MAILER);

	db_query("SELECT t.token, u.email, r.id, r.zone_id, r.operation " .
		 "FROM dns_change_approval_tokens t, users u, dns_change_requests r " .
		 "WHERE t.id = \$1 AND t.user_id = u.id AND t.request_id = r.id",
		 \@q, $token_id);
	return 0 unless (@q > 0);
	($token, $email, $req_id, $zone_id, $operation) = @{$q[0]};

	$base_url = $main::SAURON_BASE_URL || '';
	$path = $main::SAURON_APPROVE_CGI_PATH || '/cgi-bin/approve.cgi';
	$url = $base_url . $path . '?token=' . $token;

	return 0 unless ($email);
	return 0 unless (_send_mail($email,
		 "[sauron] Approval request",
		 "Approval required for DNS change request $req_id\n" .
		 "Zone ID: $zone_id\n" .
		 "Operation: $operation\n\n" .
		 "Approve or reject here:\n$url\n"));

	db_exec("UPDATE dns_change_approval_tokens SET email_sent = CURRENT_TIMESTAMP " .
		 "WHERE id = " . $token_id);
	_audit($req_id, undef, undef, 'E', undef, "Email sent to $email");
	return 1;
}

sub _send_decision_email {
	my ($request_id, $decision) = @_;
	my (@q, $email, $operation, $status);

	return 0 unless ($main::SAURON_MAILER);

	db_query("SELECT requestor_email, operation, status " .
		 "FROM dns_change_requests WHERE id = \$1", \@q, $request_id);
	return 0 unless (@q > 0);
	($email, $operation, $status) = @{$q[0]};
	return 0 unless ($email);

	return _send_mail($email,
		 "[sauron] Approval decision",
		 "DNS change request $request_id has been " .
		 ($decision eq 'A' ? 'approved' : 'rejected') . ".\n" .
		 "Operation: $operation\n" .
		 "Status: $status\n");
}

sub _send_mail {
	my ($to, $subject, $body) = @_;
	my $from = $main::SAURON_MAIL_FROM || 'sauron';

	return 0 unless ($to);
	open(my $pipe, "| $main::SAURON_MAILER $main::SAURON_MAILER_ARGS")
		|| return 0;
	print $pipe "From: Sauron <$from>\n";
	print $pipe "To: $to\n";
	print $pipe "Subject: $subject\n\n";
	print $pipe $body;
	close($pipe);
	return ($? == 0);
}

sub _audit {
	my ($request_id, $user_id, $user_name, $event, $level_order, $message) = @_;
	my $uid = (defined $user_id && $user_id ne '' ? $user_id : 'NULL');
	my $lvl = (defined $level_order && $level_order ne '' ? $level_order : 'NULL');
	db_exec("INSERT INTO dns_change_audit_log " .
		 "(request_id, user_id, user_name, event, level_order, message) " .
		 "VALUES (" .
		 $request_id . "," .
		 $uid . "," .
		 db_encode_str(defined $user_name ? $user_name : '') . "," .
		 db_encode_str($event) . "," .
		 $lvl . "," .
		 db_encode_str(defined $message ? $message : '') . ")");
}

sub _generate_token {
	my $seed1 = time . $$ . rand();
	my $seed2 = rand() . $$ . time;
	return md5_hex($seed1) . md5_hex($seed2);
}

sub _serialize {
	my ($ref) = @_;
	return undef unless ($ref);
	my $d = Data::Dumper->new([$ref]);
	$d->Terse(1);
	$d->Indent(0);
	return $d->Dump();
}

sub _deserialize {
	my ($text) = @_;
	return undef unless (defined $text);
	my $VAR1;
	eval $text;
	return $@ ? undef : $VAR1;
}

1;
