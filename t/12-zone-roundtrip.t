#!/usr/bin/perl
# t/12-zone-roundtrip.t - Zone import → generate → compare round-trip test
#
# Tests that importing a zone file into Sauron and then generating it back
# produces an equivalent zone (same DNS records, ignoring SOA serial,
# comments, and formatting differences).
#
# Requires:
#   SAURON_TEST_DSN       - PostgreSQL DSN (e.g. dbi:Pg:dbname=sauron_test)
#   SAURON_INSTALL_DIR    - Path to installed Sauron (with import-zone, sauron)
#
# Optional:
#   SAURON_TEST_VERBOSE   - Show detailed progress
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);
use File::Find;

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
my $dsn         = $ENV{SAURON_TEST_DSN}    || '';
my $verbose     = $ENV{SAURON_TEST_VERBOSE} || 0;

unless ($dsn && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for round-trip tests';
}

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by transitive imports
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

use Sauron::UtilZone;
use Sauron::Util;
use Net::IP qw(:PROC);

my $testdata = "$FindBin::Bin/../test";
my $canonicalize = "$FindBin::Bin/zone-canonicalize.pl";

# Test server name used for import (must match what's configured in the test DB)
my $server = 'roundtrip-test';

# =========================================================================
# Zone configurations for round-trip testing
# =========================================================================
my @test_zones = (
    {
        name     => 'roundtrip.example.com',
        file     => "$testdata/roundtrip.example.com.zone",
        # WKS output depends on server flags.
        # We compare what process_zonefile can parse from both sides.
        skip_types => {
            'WKS'  => 'WKS output depends on named_flags_wks server setting',
        },
    },
);


# =========================================================================
# Helpers
# =========================================================================

# Parse a zone file and return canonical records hash: { "owner TYPE rdata" => 1 }
sub parse_zone_records {
    my ($file, $origin, $skip_types) = @_;
    $skip_types //= {};

    $origin .= '.' unless $origin =~ /\.$/;
    my $lc_origin = lc($origin);

    my %zonedata;
    eval { process_zonefile($file, $origin, \%zonedata, 0) };
    return (undef, "Failed to parse $file: $@") if $@;

    my %records;

    for my $domain (keys %zonedata) {
        my $rec = $zonedata{$domain};
        my $owner = lc($domain);

        # SOA - compare everything except serial
        if ($rec->{SOA} && length($rec->{SOA}) > 0) {
            my @soa = split(/\s+/, $rec->{SOA});
            $soa[2] = 'SERIAL';
            my $key = "$owner IN SOA " . join(' ', @soa);
            $records{$key} = 1;
        }

        # NS
        for my $ns (@{$rec->{NS}}) {
            $records{"$owner IN NS " . lc($ns)} = 1;
        }

        # A
        for my $a (@{$rec->{A}}) {
            $records{"$owner IN A $a"} = 1;
        }

        # AAAA
        for my $aaaa (@{$rec->{AAAA}}) {
            my $normalized = ip_compress_address(lc($aaaa), 6);
            $records{"$owner IN AAAA $normalized"} = 1;
        }

        # CNAME
        if ($rec->{CNAME} && length($rec->{CNAME}) > 0) {
            $records{"$owner IN CNAME " . lc($rec->{CNAME})} = 1;
        }

        # MX
        unless ($skip_types->{MX}) {
            for my $mx (@{$rec->{MX}}) {
                my ($pri, $target) = split(/\s+/, $mx, 2);
                if ($target && $target =~ /\$DOMAIN/) {
                    my $shortname = $owner;
                    $shortname =~ s/\.\Q$lc_origin\E$//;
                    $target =~ s/\$DOMAIN/$shortname/;
                }
                $target = lc($target) if $target;
                $records{"$owner IN MX $pri $target"} = 1;
            }
        }

        # TXT
        for my $txt (@{$rec->{TXT}}) {
            $records{"$owner IN TXT \"$txt\""} = 1;
        }

        # HINFO
        unless ($skip_types->{HINFO}) {
            if ($rec->{HINFO} && ($rec->{HINFO}[0] ne '' || $rec->{HINFO}[1] ne '')) {
                $records{"$owner IN HINFO $rec->{HINFO}[0] $rec->{HINFO}[1]"} = 1;
            }
        }

        # WKS
        unless ($skip_types->{WKS}) {
            for my $wks (@{$rec->{WKS}}) {
                $records{"$owner IN WKS $wks"} = 1;
            }
        }

        # SRV
        for my $srv (@{$rec->{SRV}}) {
            $records{"$owner IN SRV $srv"} = 1;
        }

        # SSHFP
        for my $sshfp (@{$rec->{SSHFP}}) {
            $records{"$owner IN SSHFP " . uc($sshfp)} = 1;
        }

        # TLSA
        for my $tlsa (@{$rec->{TLSA}}) {
            $records{"$owner IN TLSA " . uc($tlsa)} = 1;
        }

        # NAPTR
        for my $naptr (@{$rec->{NAPTR}}) {
            $records{"$owner IN NAPTR $naptr"} = 1;
        }

        # DS
        for my $ds (@{$rec->{DS}}) {
            $records{"$owner IN DS " . uc($ds)} = 1;
        }

        # CAA
        unless ($skip_types->{CAA}) {
            for my $caa (@{$rec->{CAA}}) {
                $records{"$owner IN CAA $caa"} = 1;
            }
        }

        # PTR
        for my $ptr (@{$rec->{PTR}}) {
            $records{"$owner IN PTR " . lc($ptr)} = 1;
        }
    }

    return (\%records, undef);
}


# Compare two record sets. Returns (missing, extra) arrayrefs.
sub compare_record_sets {
    my ($original, $generated) = @_;

    my @missing;  # in original but not in generated
    my @extra;    # in generated but not in original

    for my $rec (sort keys %$original) {
        push @missing, $rec unless exists $generated->{$rec};
    }
    for my $rec (sort keys %$generated) {
        push @extra, $rec unless exists $original->{$rec};
    }

    return (\@missing, \@extra);
}


# Find the generated zone file in the output directory
sub find_generated_zone {
    my ($gendir, $zonename) = @_;

    my $found;
    find(sub {
        $found = $File::Find::name if ($_ eq "$zonename.zone");
    }, $gendir);

    return $found;
}


# =========================================================================
# Main test flow
# =========================================================================

for my $tz (@test_zones) {
    subtest "round-trip: $tz->{name}" => sub {
        my $zonename = $tz->{name};
        my $zonefile = $tz->{file};

        plan skip_all => "Zone file not found: $zonefile" unless -r $zonefile;

        # Step 1: Import the zone
        diag("Importing zone: $zonename") if $verbose;
        my $cmd = "$install_dir/import-zone $server $zonename $zonefile 2>&1";
        my $out = `$cmd`;
        my $rc = $? >> 8;
        is($rc, 0, "import-zone $zonename exits 0") or do {
            diag("import-zone output:\n$out");
            return;
        };
        diag("import-zone output:\n$out") if $verbose;

        # Step 2: Generate zone files
        my $gendir = tempdir(CLEANUP => 1);
        diag("Generating zone to: $gendir") if $verbose;
        $cmd = "$install_dir/sauron --verbose --bind $server $gendir 2>&1";
        $out = `$cmd`;
        $rc = $? >> 8;
        is($rc, 0, "sauron --bind exits 0") or do {
            diag("sauron output:\n$out");
            return;
        };
        diag("sauron output:\n$out") if $verbose;

        # Step 3: Find the generated zone file
        my $generated_file = find_generated_zone($gendir, $zonename);
        ok($generated_file && -r $generated_file, "generated zone file found")
            or do {
                diag("Generated files in $gendir:");
                diag(`find $gendir -type f`);
                return;
            };
        diag("Generated file: $generated_file") if $verbose;

        # Step 4: Parse both zone files
        my ($orig_records, $orig_err) = parse_zone_records(
            $zonefile, $zonename, $tz->{skip_types}
        );
        ok(!$orig_err, "parsed original zone") or do {
            diag("Parse error: $orig_err");
            return;
        };

        my ($gen_records, $gen_err) = parse_zone_records(
            $generated_file, $zonename, $tz->{skip_types}
        );
        ok(!$gen_err, "parsed generated zone") or do {
            diag("Parse error: $gen_err");
            return;
        };

        # Step 5: Compare record sets
        my ($missing, $extra) = compare_record_sets($orig_records, $gen_records);

        # Report differences
        if (@$missing > 0) {
            diag("");
            diag("=== MISSING RECORDS (in original but not in generated) ===");
            for my $rec (@$missing) {
                diag("  - $rec");
            }
        }
        if (@$extra > 0) {
            diag("");
            diag("=== EXTRA RECORDS (in generated but not in original) ===");
            for my $rec (@$extra) {
                diag("  + $rec");
            }
        }

        # Handle known skipped types info
        if ($tz->{skip_types} && keys %{$tz->{skip_types}}) {
            diag("");
            diag("=== SKIPPED RECORD TYPES ===");
            for my $type (sort keys %{$tz->{skip_types}}) {
                diag("  [$type] $tz->{skip_types}{$type}");
            }
        }

        # The actual comparison test
        my $total_diff = scalar(@$missing) + scalar(@$extra);
        is($total_diff, 0,
           "zone records match after round-trip (${\scalar keys %$orig_records} original, " .
           "${\scalar keys %$gen_records} generated)")
            or diag("Total differences: $total_diff " .
                    "(${\scalar @$missing} missing, ${\scalar @$extra} extra)");

        # Detailed per-type statistics
        if ($verbose || $total_diff > 0) {
            my %type_stats;
            for my $rec (keys %$orig_records) {
                if ($rec =~ /^\S+\s+IN\s+(\S+)\s/) {
                    $type_stats{$1}{original}++;
                }
            }
            for my $rec (keys %$gen_records) {
                if ($rec =~ /^\S+\s+IN\s+(\S+)\s/) {
                    $type_stats{$1}{generated}++;
                }
            }
            diag("");
            diag("=== RECORD TYPE STATISTICS ===");
            diag(sprintf("  %-8s  %8s  %8s", "TYPE", "ORIGINAL", "GENERATED"));
            for my $type (sort keys %type_stats) {
                diag(sprintf("  %-8s  %8d  %8d",
                    $type,
                    $type_stats{$type}{original} || 0,
                    $type_stats{$type}{generated} || 0));
            }
        }
    };
}

done_testing();
