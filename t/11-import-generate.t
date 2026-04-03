#!/usr/bin/perl
# t/11-import-generate.t - End-to-end integration: import zone → generate config
#
# Requires running PostgreSQL with initialized Sauron DB and installed Sauron.
# Skipped unless SAURON_TEST_DSN and SAURON_INSTALL_DIR are set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
my $dsn         = $ENV{SAURON_TEST_DSN}    || '';

unless ($dsn && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for E2E tests';
}

my $testdata = "$FindBin::Bin/../test";

# =========================================================================
# import-zone
# =========================================================================
subtest 'import-zone middle.earth' => sub {
    my $cmd = "$install_dir/import-zone example middle.earth $testdata/middle.earth.zone 2>&1";
    my $out = `$cmd`;
    is($? >> 8, 0, "import-zone exits 0") or diag($out);
};

# =========================================================================
# generatehosts
# =========================================================================
subtest 'generatehosts' => sub {
    my $cmd = "$install_dir/generatehosts example middle.earth 'test0:N:' '2001:db8::1:1' 5 --commit --info ':DEP::' 2>&1";
    my $out = `$cmd`;
    is($? >> 8, 0, "generatehosts exits 0") or diag($out);
};

# =========================================================================
# import-dhcp
# =========================================================================
subtest 'import-dhcp' => sub {
    my $cmd = "$install_dir/import-dhcp --global example $testdata/dhcpd.conf 2>&1";
    my $out = `$cmd`;
    is($? >> 8, 0, "import-dhcp exits 0") or diag($out);
};

# =========================================================================
# generate configs (bind, dhcp, dhcp6)
# =========================================================================
subtest 'sauron generate' => sub {
    my $gendir = tempdir(CLEANUP => 1);

    for my $mode (qw(--bind --dhcp --dhcp6)) {
        my $cmd = "$install_dir/sauron --verbose $mode example $gendir 2>&1";
        my $out = `$cmd`;
        is($? >> 8, 0, "sauron $mode exits 0") or diag($out);
    }

    # Check that some output files exist
    my @files = glob("$gendir/*");
    ok(@files > 0, "generated files in output dir");
};

done_testing();
