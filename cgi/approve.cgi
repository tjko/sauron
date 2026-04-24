#!/usr/bin/perl -I/opt/sauron

use CGI qw/:standard *table -utf8/;
use Sauron::DB;
use Sauron::Sauron;
use Sauron::Approval;
use Sauron::SetupIO;
use Sauron::Util;
use strict;
use warnings;
use open ':locale';

set_encoding();
load_config();

my $q = CGI->new;
my $token = $q->param('token') || '';
my $decision = $q->param('decision') || '';
my $reason = $q->param('reason') || '';

print $q->header(-type=>'text/html', -charset=>($main::SAURON_CHARSET || 'utf-8'));
print $q->start_html(-title=>'Sauron Approval');

if (!$token) {
	print h2('Missing token');
	print $q->end_html;
	exit 0;
}

unless (db_connect()) {
	print h2('Database connection failed');
	print $q->end_html;
	exit 0;
}

my @qinfo;
db_query("SELECT t.id, t.token_expires, r.id, r.operation, r.status, r.zone_id, " .
         "r.change_data, r.original_data, r.reason " .
         "FROM dns_change_approval_tokens t, dns_change_requests r " .
         "WHERE t.token = $1 AND t.request_id = r.id", \@qinfo, $token);

if (@qinfo == 0) {
	print h2('Invalid token');
	print $q->end_html;
	exit 0;
}

my ($token_id, $expires, $req_id, $operation, $status, $zone_id, $change_data, $original_data, $req_reason) = @{$qinfo[0]};

if ($decision) {
	my ($st, $msg) = record_decision($token, $decision, $reason);
	print h2('Decision recorded');
	print p($msg);
	print $q->end_html;
	exit 0;
}

print h2('Approval request');
print p("Request ID: $req_id");
print p("Zone ID: $zone_id");
print p("Operation: $operation");
print p("Status: $status");
print p("Request reason: " . escapeHTML($req_reason || ''));
print p("Token expires: " . ($expires || 'n/a'));

print h3('Original data');
print pre(escapeHTML($original_data || ''));
print h3('Proposed data');
print pre(escapeHTML($change_data || ''));

print start_form(-method=>'POST');
print hidden('token', $token);
print p('Reason (required):');
print textarea(-name=>'reason', -rows=>4, -columns=>60, -required=>1);
print p(submit(-name=>'decision', -value=>'A'), ' ', submit(-name=>'decision', -value=>'R'));
print end_form;

print $q->end_html;
