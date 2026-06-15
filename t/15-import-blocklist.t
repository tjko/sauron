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
    my ($filename, $entries_ref) = @_;
    open(my $fh, '>:utf8', $filename) or die "Cannot create $filename: $!";
    print $fh "URL,DATUM_ZAPISU,DATUM_VYMAZU,ZDROJ,NAZEV_DATOVE_SADY\n";
    for my $e (@$entries_ref) {
        print $fh "$e->{url},$e->{added},$e->{removed},$e->{source},$e->{dataset}\n";
    }
    close($fh);
}

# Create test config file
sub create_test_config {
    my ($filename, $csv_file, $zone, $cname_target) = @_;
    $cname_target ||= '*.blocked.example.cz.';
    open(my $fh, '>:utf8', $filename) or die "Cannot create $filename: $!";
    print $fh <<EOF;
{
  "sources": [
    {
      "name": "test-source",
      "description": "Test blocklist source",
      "csv_file": "$csv_file",
      "csv_columns": {
        "domain": "URL",
        "date_added": "DATUM_ZAPISU",
        "date_removed": "DATUM_VYMAZU",
        "source": "ZDROJ",
        "dataset": "NAZEV_DATOVE_SADY"
      },
      "filters": {
        "source_regex": "Test"
      },
      "zone": "$zone",
      "cname_target": "$cname_target",
      "txt_info_prefix": "Test"
    }
  ],
  "global_settings": {
    "remove_expired": true
  }
}
EOF
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