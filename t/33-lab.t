#!/usr/bin/perl
# t/33-lab.t - Sauron training lab: seed, checks and reference solution
#
# Loads the lab data (lab/seed.sh), checks that no task is done yet,
# completes all tasks with the reference solution (lab/solve) and checks
# that lab-check reports every task as done. Keeps the lab tasks working
# when Sauron changes.
#
# Requires an installed Sauron (SAURON_INSTALL_DIR) with an initialized DB
# reachable through the PG* variables, i.e. the E2E stack (make test-e2e).
#
use strict;
use warnings;
use Test::More;
use JSON::PP;
use File::Temp qw(tempfile);

my $install = $ENV{SAURON_INSTALL_DIR} || '';
plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for E2E tests'
  unless ($ENV{SAURON_TEST_DSN} && $install && -x "$install/lab/lab-check");

my $lab = "$install/lab";

my (undef, $errfile) = tempfile(UNLINK => 1);

# lab-check --json; stderr (warnings) kept apart from the JSON report
sub run_check {
  my $out = `"$lab/lab-check" --json --lang=en 2>"$errfile"`;
  my $rc = $? >> 8;
  my $err = do { local (@ARGV, $/) = ($errfile); <> } // '';
  diag("lab-check stderr: $err") if $err ne '';
  my $res = eval { JSON::PP->new->utf8->decode($out) };
  BAIL_OUT("lab-check output is not JSON: $out") unless ref $res eq 'HASH';
  return ($rc, $res);
}

my $out = `"$lab/seed.sh" 2>&1`;
is($? >> 8, 0, 'seed.sh succeeds') or BAIL_OUT($out);

$out = `"$lab/seed.sh" 2>&1`;
is($? >> 8, 0, 'seed.sh is idempotent') or diag($out);

my ($rc, $res) = run_check();
is($rc, 1, 'lab-check fails before the tasks are done');
ok($res->{total} >= 15, "lab-check knows $res->{total} tasks");
is($res->{accounts}{user}, $ENV{SAURON_LAB_USER} || 'user', 'report names the lab user');
is($res->{done}, 0, 'no task is done on fresh lab data')
  or diag(join("\n", map { "$_->{id} done" } grep { $_->{ok} } @{$res->{tasks}}));

$out = `"$lab/solve" 2>&1`;
is($? >> 8, 0, 'reference solution succeeds') or diag($out);

($rc, $res) = run_check();
is($rc, 0, 'lab-check succeeds after the reference solution');
for my $t (@{$res->{tasks}}) {
  ok($t->{ok}, "$t->{id} $t->{title}") or diag(join("\n", @{$t->{messages}}));
}

done_testing();
