#!/usr/bin/perl

use strict;
use warnings;
use Test::More;

use lib '.';
use Sauron::Approval;

my %policies = (
	1 => {
		zone_id => 1,
		match_mode => 'O',
		on_add => 1,
		on_modify => 0,
		on_delete => 0,
		rules => [
			{ record_types => '1', domain_regexp => '' },
			{ record_types => '', domain_regexp => '^www\.' }
		]
	},
	2 => {
		zone_id => 1,
		match_mode => 'A',
		on_add => 0,
		on_modify => 1,
		on_delete => 0,
		rules => [
			{ record_types => '1', domain_regexp => '^api\.' },
			{ record_types => '', domain_regexp => '^api\.' }
		]
	},
	3 => {
		zone_id => 1,
		match_mode => 'O',
		on_add => 1,
		on_modify => 0,
		on_delete => 0,
		rules => [
			{ record_types => '1', domain_regexp => '^mail\.' }
		]
	}
);

no warnings qw(redefine prototype);
*Sauron::Approval::db_query = sub {
	my ($sql, $aref, @params) = @_;
	@$aref = ();

	if ($sql =~ /FROM approval_policies/) {
		my $zone_id = $params[0];
		my $flag = ($sql =~ /on_add/) ? 'on_add' :
		           ($sql =~ /on_modify/) ? 'on_modify' :
		           ($sql =~ /on_delete/) ? 'on_delete' : '';
		for my $id (sort { $a <=> $b } keys %policies) {
			my $p = $policies{$id};
			next unless ($p->{zone_id} == $zone_id);
			next unless ($flag && $p->{$flag});
			push @$aref, [$id, $p->{match_mode}];
		}
		return scalar @$aref;
	}

	if ($sql =~ /FROM approval_rules/) {
		my $policy_id = $params[0];
		for my $r (@{$policies{$policy_id}->{rules} || []}) {
			push @$aref, [$r->{record_types}, $r->{domain_regexp}];
		}
		return scalar @$aref;
	}

	return 0;
};

is(check_approval_needed(1, 'A', 1, 'www.example'), 1, 'OR policy matches type');
is(check_approval_needed(1, 'A', 2, 'www.example'), 1, 'OR policy matches regexp');
is(check_approval_needed(1, 'M', 1, 'api.example'), 2, 'AND policy matches all rules');
ok(!defined check_approval_needed(1, 'M', 1, 'www.example'), 'AND policy fails without all matches');
ok(!defined check_approval_needed(1, 'M', 1, 'mail.example'), 'on_modify disabled policy ignored');

done_testing();
