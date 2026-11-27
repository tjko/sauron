#!/usr/bin/perl
# t/08-acme-txt.t - request parsing and validation of acme-txt (no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

require "$FindBin::Bin/../acme-txt";

my $val = 'A' x 20 . '-_' . 'b9' x 10 . 'z';    # 43 chars
is(length($val), 43, 'sample value has 43 characters');

subtest 'valid_acme_value' => sub {
    ok(valid_acme_value($val), 'base64url, 43 chars');
    ok(!valid_acme_value(undef), 'undef');
    ok(!valid_acme_value(''), 'empty');
    ok(!valid_acme_value(substr($val, 1)), '42 chars');
    ok(!valid_acme_value("${val}x"), '44 chars');
    ok(!valid_acme_value(substr($val, 1) . '='), 'padding');
    ok(!valid_acme_value(substr($val, 1) . '"'), 'quote');
    ok(!valid_acme_value(substr($val, 1) . ';'), 'semicolon');
};

subtest 'parse_request' => sub {
    is_deeply([parse_request('add', '_acme-challenge.a.cz', $val)],
              ['add', '_acme-challenge.a.cz', $val], 'add');
    is_deeply([parse_request('del', '_acme-challenge.a.cz', $val)],
              ['del', '_acme-challenge.a.cz', $val], 'del');
    is_deeply([parse_request('rm', '_acme-challenge.a.cz', $val)], [],
              'unknown action');
    is_deeply([parse_request('add', '_acme-challenge.a.cz')], [],
              'missing value');
    is_deeply([parse_request('add', 'x', $val, 'extra')], [],
              'extra argument');
};

subtest 'match_acme_name' => sub {
    my @z = ('example.cz', 'sub.example.cz.');
    is_deeply([match_acme_name('_acme-challenge.example.cz', @z)],
              ['example.cz', '_acme-challenge'], 'apex (also wildcard)');
    is_deeply([match_acme_name('_ACME-challenge.www.Example.CZ.', @z)],
              ['example.cz', '_acme-challenge.www'], 'case and trailing dot');
    is_deeply([match_acme_name('_acme-challenge.www.sub.example.cz', @z)],
              ['sub.example.cz', '_acme-challenge.www'],
              'longest matching zone wins');
    is_deeply([match_acme_name('_acme-challenge.sub.example.cz', @z)],
              ['sub.example.cz', '_acme-challenge'], 'apex of subzone');
    is_deeply([match_acme_name('www.example.cz', @z)], [], 'no prefix');
    is_deeply([match_acme_name('x._acme-challenge.example.cz', @z)], [],
              'prefix not first');
    is_deeply([match_acme_name('_acme-challengex.example.cz', @z)], [],
              'prefix not a whole label');
    is_deeply([match_acme_name('_acme-challenge.example.com', @z)], [],
              'other zone');
    is_deeply([match_acme_name('_acme-challenge.badexample.cz', @z)], [],
              'zone suffix without label boundary');
    is_deeply([match_acme_name('_acme-challenge..example.cz', @z)], [],
              'empty label');
    is_deeply([match_acme_name('_acme-challenge.a b.example.cz', @z)], [],
              'space');
    is_deeply([match_acme_name("_acme-challenge.a';.example.cz", @z)], [],
              'quote');
    is_deeply([match_acme_name(undef, @z)], [], 'undef');
    my $l63 = 'a' x 63;
    is_deeply([match_acme_name("_acme-challenge.$l63.example.cz", @z)],
              ['example.cz', "_acme-challenge.$l63"], '63-character label');
    is_deeply([match_acme_name("_acme-challenge.${l63}a.example.cz", @z)], [],
              '64-character label');
    my $long = '_acme-challenge.' . join('.', ('a' x 60) x 4) . '.example.cz';
    cmp_ok(length($long), '>', 253, 'long name over 253');
    is_deeply([match_acme_name($long, @z)], [], 'name over 253 characters');
};

done_testing();
