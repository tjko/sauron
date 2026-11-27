#!/usr/bin/perl
# t/04-sauron-module.t - Unit tests for Sauron::Sauron (non-DB parts)
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

use Sauron::Sauron;

# =========================================================================
# Module loads correctly
# =========================================================================
subtest 'module loaded' => sub {
    ok(defined $Sauron::Sauron::VERSION, 'VERSION defined');
    can_ok('Sauron::Sauron',
        'sauron_version', 'load_browser_config', 'load_config');
};

# =========================================================================
# Defaults
# =========================================================================
subtest 'set_defaults' => sub {
    Sauron::Sauron::set_defaults();
    # Used as placeholder IP for aliases in host browse (Sauron::CGI::Hosts);
    # empty value made the SQL fail with "invalid input syntax for type cidr".
    is($main::SAURON_ZERO_IP, '0.0.0.0', 'SAURON_ZERO_IP defaults to 0.0.0.0');
};

done_testing();
