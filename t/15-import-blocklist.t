#!/usr/bin/perl
# t/15-import-blocklist.t - Test for import-blocklist script
#
# Requires running PostgreSQL with initialized Sauron DB and installed Sauron.
# Skipped unless SAURON_TEST_DSN and SAURON_INSTALL_DIR are set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Path qw(mkpath);
use File::Copy qw(copy);

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
my $dsn         = $ENV{SAURON_TEST_DSN}    || '';

unless ($dsn && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for E2E tests';
}

my $testdata = "$FindBin::Bin/../test";
my $tmpdir   = tempdir(CLEANUP => 1);

sub shell_quote {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/'/'"'"'/g;
    return "'$s'";
}

# Helper to run import-blocklist
sub run_import {
    my (@args) = @_;
    my $cmd = shell_quote("$install_dir/import-blocklist") . ' '
        . join(' ', map { shell_quote($_) } @args) . ' 2>&1';
    my $out = `$cmd`;
    my $exit = ($? == -1) ? -1 : ($? >> 8);
    return ($exit, $out);
}

# Create test CSV file with blocklist data
sub create_test_csv {
    my ($filename, $entries_ref, $headers_ref) = @_;
    my @headers = $headers_ref ? @$headers_ref : qw(URL DATUM_ZAPISU DATUM_VYMAZU ZDROJ NAZEV_DATOVE_SADY);
    open(my $fh, '>:utf8', $filename) or die "Cannot create $filename: $!";
    print $fh join(',', @headers) . "\n";
    for my $e (@$entries_ref) {
        if ($headers_ref) {
            print $fh join(',', map { defined $e->{$_} ? $e->{$_} : '' } @headers) . "\n";
        } else {
            print $fh "$e->{url},$e->{added},$e->{removed},$e->{source},$e->{dataset}\n";
        }
    }
    close($fh);
}

# Create test config file
sub create_test_config {
    my ($filename, $csv_file, $zone, $cname_target, $opts) = @_;
    $cname_target ||= '*.blocked.example.cz.';
    $opts ||= {};
    my $source_regex = $opts->{source_regex} || 'Test';
    my $txt_columns = $opts->{txt_columns} || undef;
    open(my $fh, '>:utf8', $filename) or die "Cannot create $filename: $!";
        print $fh "{\n";
        print $fh "  \"sources\": [\n";
        print $fh "    {\n";
        print $fh "      \"name\": \"test-source\",\n";
        print $fh "      \"description\": \"Test blocklist source\",\n";
        print $fh "      \"csv_file\": \"$csv_file\",\n";
        print $fh "      \"csv_columns\": {\n";
        print $fh "        \"domain\": \"URL\",\n";
        print $fh "        \"date_added\": \"DATUM_ZAPISU\",\n";
        print $fh "        \"date_removed\": \"DATUM_VYMAZU\",\n";
        print $fh "        \"source\": \"ZDROJ\",\n";
        print $fh "        \"dataset\": \"NAZEV_DATOVE_SADY\"\n";
        print $fh "      },\n";
        print $fh "      \"filters\": {\n";
        print $fh "        \"source_regex\": \"$source_regex\"\n";
        print $fh "      },\n";
        print $fh "      \"zone\": \"$zone\",\n";
        print $fh "      \"cname_target\": \"$cname_target\",\n";
        print $fh "      \"txt_info_prefix\": \"Test\"";
        if ($txt_columns) {
                print $fh ",\n";
                print $fh "      \"txt_columns\": {\n";
                my @labels = sort keys %$txt_columns;
                for my $i (0..$#labels) {
                        my $label = $labels[$i];
                        my $comma = $i == $#labels ? '' : ',';
                        print $fh "        \"$label\": \"$txt_columns->{$label}\"$comma\n";
                }
                print $fh "      }\n";
        } else {
                print $fh "\n";
        }
        print $fh "    }\n";
        print $fh "  ],\n";
        print $fh "  \"global_settings\": {\n";
        print $fh "    \"remove_expired\": true\n";
        print $fh "  }\n";
        print $fh "}\n";
    close($fh);
}

# =========================================================================
# Setup: Create test zone
# =========================================================================
my $serverid;
my $zoneid;

# Database connection parameters from environment
my $db_user  = $ENV{SAURON_TEST_USER} || $ENV{PGUSER} || 'postgres';
my $db_pass  = $ENV{SAURON_TEST_PASSWORD} || $ENV{PGPASSWORD} || '';
my $db_host  = $ENV{PGHOST} || 'localhost';
my $db_name  = $ENV{POSTGRES_DB} || 'sauron';

# Helper function to run psql commands
sub run_psql {
    my ($sql) = @_;

    # Use machine-friendly psql output and stop immediately on SQL errors.
    my $cmd = 'psql -X -q -A -t -v ON_ERROR_STOP=1 '
        . '-h ' . shell_quote($db_host) . ' '
        . '-U ' . shell_quote($db_user) . ' '
        . '-d ' . shell_quote($db_name) . ' '
        . '-P pager=off -c ' . shell_quote($sql) . ' 2>&1';
    if (length $db_pass) {
        $cmd = 'PGPASSWORD=' . shell_quote($db_pass) . ' ' . $cmd;
    }

    my $out = `$cmd`;
    my @lines = grep { length $_ } map {
        my $line = $_;
        $line =~ s/\r//g;
        $line =~ s/^\s+//;
        $line =~ s/\s+$//;
        $line;
    } split /\n/, $out;

    for my $line (@lines) {
        return $line if $line =~ /^\d+$/;
    }

    for my $line (@lines) {
        return $line if $line =~ /^ERROR:/;
    }

    return $lines[0] // '';
}

subtest 'Setup: Create test zone' => sub {
    # First we need to find or create a server
    my $out = run_psql("SELECT id FROM servers WHERE name='test-server'");
    
    if ($out && $out =~ /^\d+$/) {
        $serverid = $out;
    } else {
        # Create test server
        $out = run_psql("INSERT INTO servers (name, comment) VALUES ('test-server', 'Test server') RETURNING id");
        if ($out && $out =~ /^\d+$/ && $out > 0) {
            $serverid = $out;
            ok(1, "Created test server");
        } else {
            BAIL_OUT("Failed to create test server: $out");
        }
    }
    
    # Check if zone exists
    $out = run_psql("SELECT id FROM zones WHERE name='test-rpz.example.cz' AND server=$serverid");
    
    if ($out && $out =~ /^\d+$/) {
        $zoneid = $out;
        ok(1, "Using existing test RPZ zone");
    } else {
        # Create test RPZ zone
        $out = run_psql("INSERT INTO zones (name, server, type, comment) VALUES ('test-rpz.example.cz', $serverid, 'M', 'Test RPZ zone') RETURNING id");
        if ($out && $out =~ /^\d+$/ && $out > 0) {
            $zoneid = $out;
            ok(1, "Created test RPZ zone");
        } else {
            BAIL_OUT("Failed to create test RPZ zone: $out");
        }
    }
};

plan skip_all => 'Failed to setup test zone'
    unless (defined $zoneid && $zoneid =~ /^\d+$/ && $zoneid > 0);

# =========================================================================
# Test 1: Import initial blocklist
# =========================================================================
subtest 'Import initial blocklist' => sub {
    my $csv_file = "$tmpdir/test1.csv";
    my $config_file = "$tmpdir/test1.conf";
    
    create_test_csv($csv_file, [
        { url => 'blocked1.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked2.example.com', added => '2024-01-02', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked3.example.com', added => '2024-01-03', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    like($out, qr/ADD:\s+3/, "Added 3 entries");
    
    # Verify in database
    my $count = run_psql("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid AND type=4 AND comment LIKE 'blocklist:test-source:%'");
    is($count, 3, "Database has 3 entries");
};

# =========================================================================
# Test 2: Re-run with same data (no changes expected)
# =========================================================================
subtest 'Re-run with same data (no changes)' => sub {
    my $csv_file = "$tmpdir/test2.csv";
    my $config_file = "$tmpdir/test2.conf";
    
    create_test_csv($csv_file, [
        { url => 'blocked1.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked2.example.com', added => '2024-01-02', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked3.example.com', added => '2024-01-03', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    like($out, qr/ADD:\s+0/, "No new entries added");
    like($out, qr/MODIFY:\s+0/, "No entries modified");
    like($out, qr/DELETE:\s+0/, "No entries deleted");
};

# =========================================================================
# Test 3: Add new entry
# =========================================================================
subtest 'Add new entry' => sub {
    my $csv_file = "$tmpdir/test3.csv";
    my $config_file = "$tmpdir/test3.conf";
    
    create_test_csv($csv_file, [
        { url => 'blocked1.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked2.example.com', added => '2024-01-02', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked3.example.com', added => '2024-01-03', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked4.example.com', added => '2024-01-04', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    like($out, qr/ADD:\s+1/, "Added 1 new entry");
    
    # Verify count
    my $count = run_psql("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid AND type=4 AND comment LIKE 'blocklist:test-source:%'");
    is($count, 4, "Database has 4 entries");
};

# =========================================================================
# Test 4: Remove entry (mark as removed in CSV)
# =========================================================================
subtest 'Remove entry (mark as removed)' => sub {
    my $csv_file = "$tmpdir/test4.csv";
    my $config_file = "$tmpdir/test4.conf";
    
    create_test_csv($csv_file, [
        { url => 'blocked1.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked2.example.com', added => '2024-01-02', removed => '2024-06-01', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked3.example.com', added => '2024-01-03', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'blocked4.example.com', added => '2024-01-04', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    like($out, qr/DELETE:\s+1/, "Deleted 1 entry");
    
    # Verify count
    my $count = run_psql("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid AND type=4 AND comment LIKE 'blocklist:test-source:%'");
    is($count, 3, "Database has 3 entries after deletion");
};

# =========================================================================
# Test 5: Dry-run mode (no changes should be made)
# =========================================================================
subtest 'Dry-run mode' => sub {
    my $csv_file = "$tmpdir/test5.csv";
    my $config_file = "$tmpdir/test5.conf";
    
    create_test_csv($csv_file, [
        { url => 'blocked1.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'new-entry.example.com', added => '2024-01-05', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import(
        "--config", $config_file,
        "--source", "test-source",
        "--dry-run",
        "--max-changes-percent=0",
        "--max-delete=0"
    );
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    like($out, qr/\[DRY-RUN\]/, "Dry-run mode indicated");
    
    # Verify count unchanged
    my $count = run_psql("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid AND type=4 AND comment LIKE 'blocklist:test-source:%'");
    is($count, 3, "Database still has 3 entries (dry-run made no changes)");
};

# =========================================================================
# Test 6: Test --max-changes-percent limit
# =========================================================================
subtest 'Test --max-changes-percent limit' => sub {
    my $csv_file = "$tmpdir/test6.csv";
    my $config_file = "$tmpdir/test6.conf";
    
    # Empty CSV should trigger 100% deletion
    create_test_csv($csv_file, []);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    # With default 25% limit, this should fail
    my ($exit, $out) = run_import(
        "--config", $config_file,
        "--source", "test-source",
        "--dry-run"
    );
    isnt($exit, 0, "import-blocklist fails with too many changes") or diag($out);
    like($out, qr/Changes exceed maximum allowed percentage/, "Error message indicates percentage limit");
};

# =========================================================================
# Test 7: Duplicate domains in CSV (should be deduplicated)
# =========================================================================
subtest 'Duplicate domains in CSV' => sub {
    my $csv_file = "$tmpdir/test7.csv";
    my $config_file = "$tmpdir/test7.conf";
    
    create_test_csv($csv_file, [
        { url => 'duplicate.example.com', added => '2024-01-01', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'duplicate.example.com', added => '2024-01-02', removed => '', source => 'Test Source', dataset => 'Test List' },
        { url => 'duplicate.example.com', added => '2024-01-03', removed => '', source => 'Test Source', dataset => 'Test List' },
    ]);
    
    create_test_config($config_file, $csv_file, 'test-rpz.example.cz');
    
    my ($exit, $out) = run_import(
        "--config", $config_file,
        "--source", "test-source",
        "--dry-run",
        "--max-changes-percent=0",
        "--max-delete=0"
    );
    is($exit, 0, "import-blocklist exits 0") or diag($out);
    # Should only show 1 ADD, not 3
    like($out, qr/ADD:\s+1/, "Duplicates deduplicated to 1 entry");
};

# =========================================================================
# Test 8: Generated TXT records and wildcard suppression
# =========================================================================
subtest 'Generated TXT records and wildcard suppression' => sub {
    my $csv_file = "$tmpdir/test8.csv";
    my $config_file = "$tmpdir/test8.conf";

    create_test_csv($csv_file, [
        {
            URL => '1xbet14.com',
            DATUM_ZAPISU => '2018-02-15',
            DATUM_VYMAZU => '',
            ZDROJ => 'Test Source',
            NAZEV_DATOVE_SADY => 'Test List',
            LEGAL => '186/2016 Sb.',
            EVIDENCE => 'zverejneno 15.2.2018',
            SHA256SUM => 'ad58d3f193322030f2c5ec8226ab63c417956bdbc3fa75c92dda963bee42b27b b1.pdf',
            WILDCARD => '0',
        },
        {
            URL => 'wildcard-txt.example.com',
            DATUM_ZAPISU => '2024-01-01',
            DATUM_VYMAZU => '',
            ZDROJ => 'Test Source',
            NAZEV_DATOVE_SADY => 'Test List',
            LEGAL => 'Law X',
            EVIDENCE => 'Evidence X',
            SHA256SUM => 'deadbeef',
            WILDCARD => '1',
        },
    ], [qw(URL DATUM_ZAPISU DATUM_VYMAZU ZDROJ NAZEV_DATOVE_SADY LEGAL EVIDENCE SHA256SUM WILDCARD)]);

    create_test_config($config_file, $csv_file, 'test-rpz.example.cz', undef, {
        source_regex => 'Test Source',
        txt_columns => {
            _info => 'generated:info',
            _legal => 'LEGAL',
            _sha256sum => 'SHA256SUM',
        },
    });

    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);

    my $base_txt_count = run_psql("SELECT COUNT(*) FROM txt_entries te JOIN hosts h ON te.ref = h.id WHERE h.zone=$zoneid AND h.domain='1xbet14.com' AND te.type=2");
    is($base_txt_count, 3, "Base host has three TXT records");

    my $wildcard_txt_count = run_psql("SELECT COUNT(*) FROM txt_entries te JOIN hosts h ON te.ref = h.id WHERE h.zone=$zoneid AND h.domain='*.wildcard-txt.example.com' AND te.type=2");
    is($wildcard_txt_count, 0, "Wildcard host has no TXT records");

    my $wildcard_host = run_psql("SELECT COUNT(*) FROM hosts WHERE zone=$zoneid AND domain='*.wildcard-txt.example.com'");
    is($wildcard_host, 1, "Wildcard host exists");
};

# =========================================================================
# Test 9: Updated entry is marked pending
# =========================================================================
subtest 'Updated entry is marked pending' => sub {
    my $csv_file = "$tmpdir/test9.csv";
    my $config_file = "$tmpdir/test9.conf";

    create_test_csv($csv_file, [
        {
            URL => '1xbet14.com',
            DATUM_ZAPISU => '2018-02-15',
            DATUM_VYMAZU => '',
            ZDROJ => 'Test Source',
            NAZEV_DATOVE_SADY => 'Test List',
            LEGAL => '186/2016 Sb. updated',
            EVIDENCE => 'zverejneno 15.2.2018',
            SHA256SUM => 'ad58d3f193322030f2c5ec8226ab63c417956bdbc3fa75c92dda963bee42b27b b1.pdf',
            WILDCARD => '0',
        },
    ], [qw(URL DATUM_ZAPISU DATUM_VYMAZU ZDROJ NAZEV_DATOVE_SADY LEGAL EVIDENCE SHA256SUM WILDCARD)]);

    create_test_config($config_file, $csv_file, 'test-rpz.example.cz', undef, {
        source_regex => 'Test Source',
        txt_columns => {
            _info => 'generated:info',
            _legal => 'LEGAL',
            _sha256sum => 'SHA256SUM',
        },
    });

    my ($exit, $out) = run_import("--config", $config_file, "--source", "test-source");
    is($exit, 0, "import-blocklist exits 0") or diag($out);

    my $pending = run_psql("SELECT CASE WHEN h.mdate > z.serial_date THEN 1 ELSE 0 END FROM hosts h JOIN zones z ON h.zone=z.id WHERE h.zone=$zoneid AND h.domain='1xbet14.com'");
    is($pending, 1, "Updated host is pending against zone serial_date");
};

# =========================================================================
# Cleanup
# =========================================================================
END {
    if ($zoneid && $serverid) {
        # Clean up test data
        run_psql("DELETE FROM hosts WHERE zone=$zoneid AND comment LIKE 'blocklist:%'");
        
        # Optionally delete the zone too
        # run_psql("DELETE FROM zones WHERE id=$zoneid");
    }
}

done_testing();