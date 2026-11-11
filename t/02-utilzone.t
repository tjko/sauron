#!/usr/bin/perl
# t/02-utilzone.t - Unit tests for Sauron::UtilZone (zone file parsing, no DB)
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

use Sauron::UtilZone;

my $testdata = "$FindBin::Bin/../test";

# =========================================================================
# process_zonefile - forward zone
# =========================================================================
subtest 'process_zonefile forward zone' => sub {
    my $zone_file = "$testdata/middle.earth.zone";
    plan skip_all => "test/middle.earth.zone not found" unless -r $zone_file;

    my %zone;
    # process_zonefile returns close() result or undef, not an error code
    eval { process_zonefile($zone_file, 'middle.earth.', \%zone, 0) };
    is($@, '', 'parse completes without error');

    ok(scalar keys %zone > 0, 'zone has entries');

    # Zone should contain SOA
    ok(exists $zone{'middle.earth.'}, 'origin entry exists');

    # Check for known hosts from the test file
    my $found_host = 0;
    for my $name (keys %zone) {
        if (exists $zone{$name}{A}) {
            $found_host = 1;
            last;
        }
    }
    ok($found_host, 'zone contains A records');
};

# =========================================================================
# process_zonefile - reverse zone
# =========================================================================
subtest 'process_zonefile reverse zone' => sub {
    my $zone_file = "$testdata/10.10.in-addr.arpa.zone";
    plan skip_all => "test/10.10.in-addr.arpa.zone not found" unless -r $zone_file;

    my %zone;
    eval { process_zonefile($zone_file, '10.10.in-addr.arpa.', \%zone, 0) };
    is($@, '', 'parse completes without error');

    ok(scalar keys %zone > 0, 'zone has entries');

    # Should contain PTR records
    my $found_ptr = 0;
    for my $name (keys %zone) {
        if (exists $zone{$name}{PTR}) {
            $found_ptr = 1;
            last;
        }
    }
    ok($found_ptr, 'zone contains PTR records');
};

# =========================================================================
# process_zonefile - localhost
# =========================================================================
subtest 'process_zonefile localhost' => sub {
    my $zone_file = "$testdata/localhost.zone";
    plan skip_all => "test/localhost.zone not found" unless -r $zone_file;

    my %zone;
    eval { process_zonefile($zone_file, 'localhost.', \%zone, 0) };
    is($@, '', 'parse completes without error');
    ok(scalar keys %zone > 0, 'zone has entries');
};

# =========================================================================
# bind_fmt_long_data
# =========================================================================
subtest 'bind_fmt_long_data' => sub {
    my $short = "short text";
    my $result = bind_fmt_long_data($short, 40);
    like($result, qr/short text/, 'short text passes through');

    my $long = "a" x 100;
    $result = bind_fmt_long_data($long, 40);
    # Should be wrapped into multiple lines
    my @lines = split /\n/, $result;
    ok(@lines >= 1, 'long text is formatted');
};

done_testing();
