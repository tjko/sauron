#!/usr/bin/perl
# t/01-util.t - Unit tests for Sauron::Util (pure functions, no DB needed)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

# Ensure DB.pm symlink exists for transitive imports
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Set globals that Util.pm references via $main::
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

# NetAddr::IP is used by Util.pm but not explicitly imported there
use NetAddr::IP;
use Sauron::Util;

# =========================================================================
# valid_base64
# =========================================================================
subtest 'valid_base64' => sub {
    ok(valid_base64('dGVzdA=='), 'simple base64');
    ok(valid_base64('YWJj'), 'no padding');
    ok(valid_base64(''), 'empty string');
    ok(!valid_base64('not valid!'), 'rejects special chars');
    ok(!valid_base64('abc def'), 'rejects spaces');
};

# =========================================================================
# valid_hex
# =========================================================================
subtest 'valid_hex' => sub {
    ok(valid_hex('0123456789abcdefABCDEF'), 'all hex chars');
    ok(valid_hex(''), 'empty string');
    ok(!valid_hex('xyz'), 'rejects non-hex');
    ok(!valid_hex('12 34'), 'rejects spaces');
};

# =========================================================================
# valid_texthandle
# =========================================================================
subtest 'valid_texthandle' => sub {
    ok(valid_texthandle('myhost-01'), 'alphanumeric with dash');
    ok(valid_texthandle('test_handle'), 'with underscore');
    ok(!valid_texthandle('has spaces'), 'rejects spaces');
    ok(!valid_texthandle('dot.name'), 'rejects dots');
    ok(!valid_texthandle(''), 'rejects empty');
};

# =========================================================================
# IPv4 CIDR validation (cidr4ok)
# =========================================================================
subtest 'cidr4ok' => sub {
    ok(cidr4ok('10.0.0.0/8'), 'class A');
    ok(cidr4ok('192.168.1.0/24'), 'class C');
    ok(cidr4ok('192.168.1.1'), 'host address');
    ok(!cidr4ok('not-an-ip'), 'rejects garbage');
    ok(!cidr4ok('2001:db8::/32'), 'rejects IPv6');
};

# =========================================================================
# IPv6 CIDR validation (cidr6ok)
# =========================================================================
subtest 'cidr6ok' => sub {
    ok(cidr6ok('2001:db8::/32'), 'standard prefix');
    ok(cidr6ok('::1/128'), 'loopback');
    ok(!cidr6ok('192.168.1.0/24'), 'rejects IPv4');
    ok(!cidr6ok('2001:db8::/33'), 'rejects non-nibble mask');
};

# =========================================================================
# cidrok (combined)
# =========================================================================
subtest 'cidrok' => sub {
    ok(cidrok('10.0.0.0/8'), 'IPv4');
    ok(cidrok('2001:db8::/32'), 'IPv6');
    ok(!cidrok('garbage'), 'rejects garbage');
};

# =========================================================================
# is_cidr / is_ip
# =========================================================================
subtest 'is_cidr and is_ip' => sub {
    ok(is_cidr('10.0.0.0/8'), 'CIDR is cidr');
    ok(is_cidr('10.0.0.1'), 'single IP is cidr');
    ok(is_ip('10.0.0.1'), 'single IP');
    ok(!is_ip('10.0.0.0/8'), 'CIDR is not just an IP');
    ok(!is_cidr('not-cidr'), 'garbage not cidr');
};

# =========================================================================
# ip2int / int2ip round-trip
# =========================================================================
subtest 'ip2int and int2ip' => sub {
    is(ip2int('10.0.0.1'), (10 << 24) + 1, 'ip2int 10.0.0.1');
    is(ip2int('0.0.0.0'), 0, 'ip2int 0.0.0.0');
    is(ip2int('255.255.255.255'), 0xFFFFFFFF, 'ip2int max');
    is(int2ip(0), '0.0.0.0', 'int2ip zero');
    is(int2ip((192 << 24) + (168 << 16) + (1 << 8) + 100), '192.168.1.100', 'int2ip host');
    is(int2ip(-1), '0.0.0.0', 'int2ip negative');

    # round-trip
    for my $ip ('10.0.0.1', '192.168.1.254', '172.16.0.0', '255.255.255.255') {
        is(int2ip(ip2int($ip)), $ip, "round-trip $ip");
    }
};

# =========================================================================
# adjust_ip
# =========================================================================
subtest 'adjust_ip' => sub {
    is(adjust_ip('10.0.0.1', 1), '10.0.0.2', 'increment by 1');
    is(adjust_ip('10.0.0.255', 1), '10.0.1.0', 'carry over');
    is(adjust_ip('10.0.0.5', -3), '10.0.0.2', 'decrement');
};

# =========================================================================
# arpa2cidr
# =========================================================================
subtest 'arpa2cidr' => sub {
    is(arpa2cidr('10.in-addr.arpa'), '10.0.0.0/8', 'class A');
    is(arpa2cidr('168.192.in-addr.arpa'), '192.168.0.0/16', 'class B');
    is(arpa2cidr('1.168.192.in-addr.arpa'), '192.168.1.0/24', 'class C');
    is(arpa2cidr('0.1.168.192.in-addr.arpa'), '192.168.1.0/32', 'host');
};

# =========================================================================
# cidr2arpa
# =========================================================================
subtest 'cidr2arpa' => sub {
    is(cidr2arpa('10.0.0.0/8'), '10.in-addr.arpa', 'class A');
    is(cidr2arpa('192.168.0.0/16'), '168.192.in-addr.arpa', 'class B');
    is(cidr2arpa('192.168.1.0/24'), '1.168.192.in-addr.arpa', 'class C');
};

# =========================================================================
# IPv6 functions
# =========================================================================
subtest 'normalize_ip6' => sub {
    is(normalize_ip6('::1'),
       '0000:0000:0000:0000:0000:0000:0000:0001', 'loopback');
    is(normalize_ip6('2001:db8::1'),
       '2001:0db8:0000:0000:0000:0000:0000:0001', 'compressed');
    is(normalize_ip6('::'), '0000:0000:0000:0000:0000:0000:0000:0000', 'unspecified');
    is(normalize_ip6('not-ipv6'), '', 'rejects garbage');
};

subtest 'ipv6compress' => sub {
    is(ipv6compress('2001:0db8:0000:0000:0000:0000:0000:0001'),
       '2001:db8::1', 'compress loopback-like');
    is(ipv6compress('fe80:0000:0000:0000:0001:0002:0003:0004'),
       'fe80::1:2:3:4', 'compress link-local');
};

subtest 'ipv6decompress' => sub {
    is(ipv6decompress('2001:db8::1'),
       '2001:0db8:0000:0000:0000:0000:0000:0001', 'decompress');
};

subtest 'is_ip6' => sub {
    ok(is_ip6('2001:db8::1'), 'valid IPv6');
    ok(is_ip6('::1'), 'loopback');
    ok(!is_ip6('192.168.1.1'), 'rejects IPv4');
};

# =========================================================================
# remove_origin / add_origin
# =========================================================================
subtest 'remove_origin' => sub {
    is(remove_origin('host.example.com', 'example.com'), 'host', 'strip origin');
    is(remove_origin('host.sub.example.com', 'example.com'), 'host.sub', 'strip nested');
};

subtest 'add_origin' => sub {
    is(add_origin('host', 'example.com'), 'host.example.com', 'add origin');
    is(add_origin('@', 'example.com'), 'example.com', '@ becomes origin');
    is(add_origin('host.example.com.', 'example.com'), 'host.example.com.', 'FQDN unchanged');
};

# =========================================================================
# Password functions
# =========================================================================
subtest 'pwd_crypt_md5 and pwd_check' => sub {
    my $hash = pwd_crypt_md5('testpassword', '1234567');
    like($hash, qr/^MD5:1234567:/, 'MD5 hash format');
    is(pwd_check('testpassword', $hash), 0, 'correct password matches');
    is(pwd_check('wrongpassword', $hash), -1, 'wrong password fails');
};

subtest 'pwd_crypt_unix' => sub {
    my $hash = pwd_crypt_unix('testpassword', 'ab');
    like($hash, qr/^CRYPT:ab/, 'CRYPT hash format');
    is(pwd_check('testpassword', $hash), 0, 'correct password matches');
    is(pwd_check('wrongpassword', $hash), -1, 'wrong password fails');
};

subtest 'pwd_make and pwd_check' => sub {
    my $hash_md5 = pwd_make('mypassword', 0);
    is(pwd_check('mypassword', $hash_md5), 0, 'MD5 round-trip');

    my $hash_unix = pwd_make('mypassword', 1);
    is(pwd_check('mypassword', $hash_unix), 0, 'Unix round-trip');
};

# =========================================================================
# dhcpether
# =========================================================================
subtest 'dhcpether' => sub {
    is(dhcpether('001122334455'), '00:11:22:33:44:55', 'format MAC');
    is(dhcpether('AABBCCDDEEFF'), 'aa:bb:cc:dd:ee:ff', 'lowercase');
};

# =========================================================================
# CSV functions
# =========================================================================
subtest 'print_csv' => sub {
    is(print_csv(['a', 'b', 'c'], 0), '"a","b","c"', 'string fields quoted');
    is(print_csv([1, 2, 3], 0), '1,2,3', 'numeric fields unquoted');
    is(print_csv(['a', 1, 'b'], 0), '"a",1,"b"', 'mixed');
    is(print_csv(['a', 'b'], 1), '"a","b"', 'force quote mode');
};

subtest 'parse_csv' => sub {
    my @r = parse_csv('"hello","world",123');
    is_deeply(\@r, ['hello', 'world', '123'], 'basic parse');
};

# =========================================================================
# join_strings
# =========================================================================
subtest 'join_strings' => sub {
    is(join_strings(',', 'a', 'b', 'c'), 'a,b,c', 'simple join');
    is(join_strings(',', 'a', '', 'c'), 'a,c', 'skip empty');
    is(join_strings(',', '', '', ''), '', 'all empty');
};

# =========================================================================
# trim
# =========================================================================
subtest 'trim' => sub {
    is(trim('  hello  '), 'hello', 'both sides');
    is(trim('hello'), 'hello', 'no whitespace');
    is(trim("  \t\n hi \n\t  "), 'hi', 'mixed whitespace');
};

# =========================================================================
# decode_daterange_str
# =========================================================================
subtest 'decode_daterange_str' => sub {
    my $r = decode_daterange_str('20200101-20201231');
    ok($r->[0] > 0, 'start date parsed');
    ok($r->[1] > 0, 'end date parsed');
    ok($r->[1] > $r->[0], 'end > start');

    $r = decode_daterange_str('-20201231');
    is($r->[0], -1, 'no start date');
    ok($r->[1] > 0, 'end date parsed');

    $r = decode_daterange_str('20200101-');
    ok($r->[0] > 0, 'start date parsed');
    is($r->[1], -1, 'no end date');

    $r = decode_daterange_str('garbage');
    is($r->[0], -1, 'garbage start');
    is($r->[1], -1, 'garbage end');
};

# =========================================================================
# check_ipmask
# =========================================================================
subtest 'check_ipmask' => sub {
    ok(check_ipmask('192.168.1.*', ''), 'valid mask without IP');
    ok(check_ipmask('192.168.1.*', '192.168.1.5'), 'IP in wildcard');
    ok(!check_ipmask('192.168.1.*', '192.168.2.5'), 'IP not in mask');
    ok(check_ipmask('10.0.0-255.*', '10.0.100.1'), 'range mask');
};

# =========================================================================
# is_iaid
# =========================================================================
subtest 'is_iaid' => sub {
    ok(is_iaid('12345'), 'numeric IAID');
    is(is_iaid('0'), 0, 'zero is invalid');
    is(is_iaid('99999999999'), 0, 'too large');
};

# =========================================================================
# new_serial
# =========================================================================
subtest 'new_serial' => sub {
    my $s = new_serial('2020010100');
    ok($s > 2020010100, 'serial incremented past old value');
    like($s, qr/^\d{10}$/, 'serial has 10 digits');
};

done_testing();
