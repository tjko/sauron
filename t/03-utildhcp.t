#!/usr/bin/perl
# t/03-utildhcp.t - Unit tests for Sauron::UtilDhcp (DHCP conf parsing, no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by transitive imports
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

use Sauron::UtilDhcp;

my $testdata = "$FindBin::Bin/../test";

# =========================================================================
# process_dhcpdconf - v4
# =========================================================================
subtest 'process_dhcpdconf v4' => sub {
    my $conf_file = "$testdata/dhcpd.conf";
    plan skip_all => "test/dhcpd.conf not found" unless -r $conf_file;

    my %data;
    process_dhcpdconf($conf_file, \%data, 0);

    ok(scalar keys %data > 0, 'parsed data has entries');
    ok(ref $data{'shared-network'} eq 'HASH', 'shared-network structure parsed');
    ok(ref $data{subnet} eq 'HASH', 'subnet structure parsed');
    ok(scalar keys %{$data{'shared-network'}} > 0, 'shared-network entries found');
    ok(exists $data{subnet}{'10.10.100.0 netmask 255.255.255.0'}, 'known subnet key parsed');
};


done_testing();
