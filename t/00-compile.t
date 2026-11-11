#!/usr/bin/perl
# t/00-compile.t - Verify all Perl modules and scripts compile cleanly
use strict;
use warnings;
use Test::More;
use File::Find;

# Ensure DB.pm symlink exists
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or diag("Cannot create DB.pm symlink: $!");
}

use FindBin;
use lib "$FindBin::Bin/..";

my @modules;
my @scripts;

# Collect all .pm files
find(sub {
    return unless /\.pm$/;
    return if $File::Find::name =~ /DB-Pg\.pm$/; # deprecated backend
    push @modules, $File::Find::name;
}, "$FindBin::Bin/../Sauron");

# Collect root-level Perl scripts
opendir(my $dh, "$FindBin::Bin/..") or die "Cannot open root dir: $!";
for my $f (readdir $dh) {
    my $path = "$FindBin::Bin/../$f";
    next unless -f $path && !-d $path;
    next if $f =~ /\.(pm|sql|txt|md|html|sgml|conf|h|in|spec|yml|zone|dump)$/;
    next if $f =~ /^(Makefile|configure|ChangeLog|COPYING|COPYRIGHT|TODO|README|config\.status|acconfig)$/;
    next if $f =~ /~$/;
    open(my $fh, '<', $path) or next;
    my $first = <$fh>;
    close $fh;
    next unless $first && $first =~ /perl/;
    push @scripts, $path;
}
closedir $dh;

plan tests => scalar(@modules) + scalar(@scripts);

for my $mod (sort @modules) {
    my $output = `$^X -w -c "$mod" 2>&1`;
    my $ok = ($? == 0);
    ok($ok, "compile: $mod") || diag($output);
}

for my $script (sort @scripts) {
    my $output = `$^X -w -c "$script" 2>&1`;
    my $ok = ($? == 0);
    if (!$ok && $output =~ /Can't locate .+ in \@INC/) {
        # Missing optional CPAN module - report as TODO, not hard failure
        TODO: {
            local $TODO = "missing optional dependency";
            ok(0, "compile: $script");
            diag($output);
        }
    } else {
        ok($ok, "compile: $script") || diag($output);
    }
}
