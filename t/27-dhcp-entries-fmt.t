#!/usr/bin/perl
# t/27-dhcp-entries-fmt.t - DHCP entry lists with the format column
#                           (dhcp_entries.fmt) in BackEnd and CGI forms
#
# Rows of DHCP entry lists are [id, dhcp, comment, fmt, marker]. Checks
# reading/updating them through BackEnd, the former 4 element row layout,
# quoting in add_net/add_vlan, and the row check of the CGI form field.
#
# Skipped unless SAURON_TEST_DSN is set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

plan skip_all => 'Set SAURON_TEST_DSN to run DHCP entry DB tests' unless ($DB_DSN);

use CGI qw/:standard/;
use Sauron::DB;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::DhcpDefs;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('dhcp-fmt-test');

my $server = 'dhcp-fmt-test';
sub rows {
    my @r;
    db_query($_[0], \@r);
    die(db_errormsg()) if (db_errormsg());
    return \@r;
}
sub cleanup {
    my $r = rows("SELECT id FROM servers WHERE name='$server'");
    delete_server($r->[0][0]) if (@$r);
}
cleanup();
db_exec("INSERT INTO servers (name,hostname,hostmaster) VALUES " .
        "('$server','ns.fmt.test.','hostmaster.fmt.test.')");
my $sid = rows("SELECT id FROM servers WHERE name='$server'")->[0][0];

subtest 'BackEnd lists with fmt' => sub {
    my $gid = add_group({ server => $sid, name => 'fmtgrp', type => 1,
        dhcp => [ [ undef, 'default-lease-time 600', 'c1', 0, 2 ],
                  [ undef, '{"renew-timer":100}', '', 2, 2 ],
                  [ undef, 'one-lease-per-client true' ],
                  [ 0, 'max-lease-time 1', '', 2 ] ] });   # former layout
    ok($gid > 0, 'add_group with DHCP entries');

    my %g;
    get_group($gid, \%g);
    is_deeply($g{dhcp}[0], [ 'DHCP', 'Comments', 'Format' ], 'header has Format');
    is_deeply([ map { [ @$_[1..3] ] } @{$g{dhcp}}[1..4] ],
              [ [ 'default-lease-time 600', 'c1', 0 ],
                [ '{"renew-timer":100}', undef, 2 ],
                [ 'one-lease-per-client true', undef, 0 ],
                [ 'max-lease-time 1', undef, 0 ] ],
              'rows with fmt (missing fmt 0, 4 element row = former layout)');

    $g{dhcp}[3][3] = 1;              # mark ISC only
    $g{dhcp}[3][4] = 1;
    push @{$g{dhcp}}, [ undef, 'max-lease-time 900', '', 2 ];   # former layout
    ok(update_group(\%g) >= 0, 'update_group');
    my $r = rows("SELECT dhcp,fmt FROM dhcp_entries WHERE type=5 AND ref=$gid ORDER BY id");
    is_deeply($r, [ [ 'default-lease-time 600', 0 ], [ '{"renew-timer":100}', 2 ],
                    [ 'one-lease-per-client true', 1 ], [ 'max-lease-time 1', 0 ],
                    [ 'max-lease-time 900', 0 ] ],
              'fmt updated, former row layout stored as 0');

    my %g2;
    get_group($gid, \%g2);
    push @{$g2{dhcp}}, [ undef, 'min-lease-time 60', '', 7, 2 ];
    ok(update_group(\%g2) < 0, 'invalid fmt rejected by update');
    ok(add_group({ server => $sid, name => 'fmtbad', type => 1,
                   dhcp => [ [ undef, 'x', '', 'KEA', 2 ] ] }) < 0,
       'invalid fmt rejected by add');
};

subtest 'add_net / add_vlan quoting' => sub {
    my $vid = add_vlan({ server => $sid, name => 'fmtvlan',
        dhcp_l => [ [ undef, q(option domain-name "it's"), 'quote', 0, 2 ] ],
        dhcp_l6 => [ [ undef, '{"rapid-commit":true}', '', 2, 2 ] ] });
    ok($vid > 0, 'add_vlan with quote in entry');
    my $r = rows("SELECT type,dhcp,comment,fmt FROM dhcp_entries WHERE ref=$vid " .
                 "AND type IN (6,16) ORDER BY id");
    is_deeply($r, [ [ 6, q(option domain-name "it's"), 'quote', 0 ],
                    [ 16, '{"rapid-commit":true}', undef, 2 ] ], 'VLAN entries stored');

    my $nid = add_net({ server => $sid, net => '10.77.0.0/24', netname => 'fmtnet',
                        name => 'fmtnet', subnet => 'true', vlan => -1,
                        dhcp_l => [ [ undef, q(option root-path "/a'b"), 'c', 1, 2 ] ] });
    ok($nid > 0, 'add_net with quote in entry');
    is_deeply(rows("SELECT dhcp,comment,fmt FROM dhcp_entries WHERE type=4 AND ref=$nid"),
              [ [ q(option root-path "/a'b"), 'c', 1 ] ], 'net entry with comment and fmt');
};

subtest 'CGI form row check' => sub {
    my $form = { data => [ dhcp_field('dhcp', 'DHCP entries', 4) ] };
    my $set = sub {
        my ($text, $fmt) = @_;
        CGI::delete_all();
        param('t_dhcp_count', 1);
        param('t_dhcp_1_id', '');
        param('t_dhcp_1_1', $text);
        param('t_dhcp_1_2', '');
        param('t_dhcp_1_3', '');
        param('t_dhcp_1_3_enum', $fmt);
        my %data = (dhcp => [ [ 'DHCP', 'Comments', 'Format' ] ]);
        my $res = form_check_form('t', \%data, $form);
        return ($res, \%data);
    };
    my ($res, $data) = $set->('{"renew-timer":5}', 2);
    is($res, 0, 'valid KEA entry accepted');
    is_deeply([ @{$data->{dhcp}[1]}[1..4] ], [ '{"renew-timer":5}', '', 2, 2 ],
              'new row [id, dhcp, comment, fmt, marker]');
    ($res) = $set->('{"renew-timer":5', 2);
    is($res, 2, 'invalid KEA JSON rejected');
    ($res) = $set->('{"renew-timer":5}', 0);
    is($res, 2, 'KEA JSON with ISC format rejected');
    ($res) = $set->('one-lease-per-client true', 0);
    is($res, 0, 'ISC statement without KEA equivalent accepted (warning only)');
    my ($e, $w) = Sauron::CGIutil::form_row_check($form->{data}[0],
                                                  [ 'one-lease-per-client true', '', 0 ]);
    like($w, qr/no KEA equivalent/, 'warning shown for it');

    # existing rows: unchanged ones are neither marked modified nor block
    CGI::delete_all();
    param('t_dhcp_count', 2);
    param('t_dhcp_1_id', 501); param('t_dhcp_1_1', '{bad'); param('t_dhcp_1_2', '');
    param('t_dhcp_1_3_enum', 0);
    param('t_dhcp_2_id', 502); param('t_dhcp_2_1', 'default-lease-time 9');
    param('t_dhcp_2_2', 'new comment'); param('t_dhcp_2_3_enum', 1);
    my %d = (dhcp => [ [ 'DHCP', 'Comments', 'Format' ],
                       [ 501, '{bad', '', 0, 0 ], [ 502, 'default-lease-time 9', '', 0, 0 ] ]);
    is(form_check_form('t', \%d, $form), 0, 'stored invalid row does not block saving');
    is($d{dhcp}[1][4], 0, 'unchanged row not marked modified');
    is_deeply([ @{$d{dhcp}[2]}[2..4] ], [ 'new comment', 1, 1 ], 'changed row updated');

    # net entries: family from the net address
    my $nf = { data => [ dhcp_field('dhcp_l', 'Net', 0) ] };
    my (undef, $w6) = Sauron::CGIutil::form_row_check($nf->{data}[0],
        [ 'preferred-lifetime 3600', '', 0 ], { net => '2001:db8::/64' });
    is($w6, '', 'IPv6 net: v6 parameter checked as DHCPv6');
    my (undef, $w4) = Sauron::CGIutil::form_row_check($nf->{data}[0],
        [ 'preferred-lifetime 3600', '', 0 ], { net => '10.0.0.0/24' });
    like($w4, qr/no KEA equivalent/, 'IPv4 net: same parameter has no DHCPv4 equivalent');
};

cleanup();
done_testing();
