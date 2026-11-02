#!/usr/bin/perl
# t/08-dhcp-model.t - Unit tests for Sauron::DhcpDefs and Sauron::DhcpModel
#                     (ISC <-> KEA statement conversion, no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

use Sauron::DhcpDefs;
use Sauron::DhcpModel;

sub isc  { parse_isc_statement($_[0], $_[1] // 4, $_[2]) }
sub kea  { isc_statement_to_kea($_[0], $_[1]) }

# re-format a parsed statement from its structure (not the original text)
sub reformat {
    my ($st) = @_;
    my %copy = %$st;
    delete $copy{text};
    return format_isc_statement(\%copy);
}

# =========================================================================
# definitions
# =========================================================================
subtest 'option/param definitions' => sub {
    my $d = dhcp_option_def(4, 'code', 6);
    is($d->{isc}, 'domain-name-servers', 'v4 option by code');
    is($d->{kea}, 'domain-name-servers', 'v4 KEA name equals ISC name');
    $d = dhcp_option_def(6, 'isc', 'dhcp6.name-servers');
    is($d->{kea}, 'dns-servers', 'v6 ISC name maps to KEA name');
    is(dhcp_option_def(6, 'kea', 'dns-servers')->{code}, 23, 'v6 by KEA name');
    ok(!dhcp_option_def(4, 'isc', 'dhcp6.name-servers'), 'v6 option not in v4');

    is(dhcp_param_def('isc', 'default-lease-time', 4)->{kea}, 'valid-lifetime',
       'default-lease-time <-> valid-lifetime');
    ok(!dhcp_param_def('isc', 'filename', 6), 'filename is v4 only');
    is(dhcp_param_def('kea', 'preferred-lifetime', 6)->{isc},
       'preferred-lifetime', 'v6 preferred-lifetime');
};

# =========================================================================
# ISC parser
# =========================================================================
subtest 'parse ISC options' => sub {
    my $st = isc('option domain-name "example.com";');
    is($st->{kind}, 'option', 'kind option');
    is_deeply($st->{values}, ['example.com'], 'text value unquoted');
    is($st->{text}, 'option domain-name "example.com"', 'text keeps original, no ;');

    $st = isc('option domain-name-servers ns1.middle.earth, 10.0.0.2');
    is_deeply($st->{values}, ['ns1.middle.earth', '10.0.0.2'], 'ip list split');

    $st = isc('option domain-search "a.example", "b.example"');
    is_deeply($st->{values}, ['a.example', 'b.example'], 'domain list split');

    $st = isc('option dhcp6.name-servers 2001:db8::1, 2001:db8::2', 6);
    is($st->{def}{kea}, 'dns-servers', 'v6 option recognised');

    $st = isc('option foo-bar 1');
    is($st->{kind}, 'option', 'unknown option still an option');
    is($st->{fmt}, DHCP_FMT_ISC, 'unknown option is ISC only');
    is(reformat($st), 'option foo-bar 1', 'unknown option re-formatted');
};

subtest 'parse ISC parameters and other statements' => sub {
    my $st = isc('default-lease-time 600');
    is($st->{kind}, 'param', 'param');
    is($st->{value}, 600, 'param value');

    $st = isc('filename "pxelinux.0"');
    is($st->{value}, 'pxelinux.0', 'filename unquoted');

    is(isc('authoritative')->{value}, 1, 'authoritative');
    is(isc('not authoritative')->{value}, 0, 'not authoritative');
    is(isc('authoritative', 6)->{fmt}, DHCP_FMT_ISC, 'authoritative is v4 only in KEA');

    $st = isc('allow members of "vip"');
    is_deeply([@$st{qw(kind action what class)}], ['permit','allow','members','vip'],
              'permit members');
    $st = isc('deny unknown-clients');
    is_deeply([@$st{qw(kind action what)}], ['permit','deny','unknown-clients'],
              'permit unknown-clients');

    $st = isc('range 10.0.0.10 10.0.0.20');
    is_deeply([@$st{qw(kind start end)}], ['range','10.0.0.10','10.0.0.20'], 'range');
    is(isc('range dynamic-bootp 10.0.0.1 10.0.0.2')->{fmt}, DHCP_FMT_ISC,
       'dynamic-bootp range is ISC only');
    is(isc('range6 2001:db8::/64', 6)->{prefix}, '2001:db8::/64', 'range6 prefix');

    is_deeply(isc('fixed-address 10.0.0.1, 10.0.0.2')->{addresses},
              ['10.0.0.1','10.0.0.2'], 'fixed-address list');
    $st = isc('hardware ethernet 00:11:22:AA:BB:CC');
    is_deeply([@$st{qw(kind type value)}], ['host-id','hw-address','00:11:22:aa:bb:cc'],
              'hardware ethernet');
    is(isc('host-identifier option dhcp6.client-id 00:01:02', 6)->{type}, 'duid',
       'DUID host identifier');

    $st = isc('match if substring(option vendor-class-identifier,0,9) = "PXEClient"');
    is($st->{kind}, 'match', 'match if');

    $st = isc('ddns-update-style none');
    is($st->{kind}, 'raw', 'unknown statement is raw');
    is($st->{fmt}, DHCP_FMT_ISC, 'raw statement is ISC only');
    is(format_isc_statement($st), 'ddns-update-style none', 'raw kept verbatim');
};

subtest 'ISC re-format from structure' => sub {
    my @lines = (
        'option domain-name "example.com"',
        'option domain-name-servers 10.0.0.1, 10.0.0.2',
        'option domain-search "a.example", "b.example"',
        'option root-path "/export/root \"x\""',
        'option dhcp-client-identifier 01:00:11:22:33:44:55',
        'default-lease-time 600',
        'filename "pxelinux.0"',
        'not authoritative',
        'allow members of "vip"',
        'deny unknown-clients',
        'range 10.0.0.10 10.0.0.20',
        'fixed-address 10.0.0.1',
        'hardware ethernet 00:11:22:aa:bb:cc',
        'match if option user-class = "x"',
    );
    is(reformat(isc($_)), $_, "round trip: $_") foreach (@lines);
    is(reformat(isc('option dhcp6.name-servers 2001:db8::1', 6)),
       'option dhcp6.name-servers 2001:db8::1', 'round trip v6 option');
};

# =========================================================================
# ISC -> KEA
# =========================================================================
subtest 'ISC statement to KEA' => sub {
    my $r = kea(isc('option domain-name "example.com"'));
    is_deeply($r->{'option-data'}, { name => 'domain-name', code => 15,
                                     data => 'example.com' }, 'text option');

    $r = kea(isc('option domain-search "a.example", "b.example"'));
    is($r->{'option-data'}{data}, 'a.example, b.example', 'list option');

    $r = kea(isc('option root-path "a,b"'));
    is($r->{'option-data'}{data}, 'a\\,b', 'comma escaped in KEA text');

    $r = kea(isc('option dhcp6.name-servers 2001:db8::1', 6));
    is($r->{'option-data'}{name}, 'dns-servers', 'v6 option renamed');

    $r = kea(isc('option domain-name-servers ns1.middle.earth, 10.0.0.2'));
    like($r->{error}, qr/cannot resolve 'ns1\.middle\.earth'/, 'hostname needs resolver');
    $r = kea(isc('option domain-name-servers ns1.middle.earth, 10.0.0.2'),
             sub { $_[0] eq 'ns1.middle.earth' ? '10.0.0.1' : undef });
    is($r->{'option-data'}{data}, '10.0.0.1, 10.0.0.2', 'hostname resolved');

    $r = kea(isc('option vendor-class-identifier "PXE"'));
    is($r->{'option-data'}{data}, '505845', 'binary text to hex');
    $r = kea(isc('option dhcp-client-identifier 1:0:11:22:33:44:55'));
    is($r->{'option-data'}{data}, '01001122334455', 'binary colon hex to hex');

    is_deeply(kea(isc('default-lease-time 600'))->{param},
              ['valid-lifetime', 600], 'lease time param');
    is_deeply(kea(isc('filename "pxe.0"'))->{param},
              ['boot-file-name', 'pxe.0'], 'filename param');
    is_deeply(kea(isc('not authoritative'))->{param},
              ['authoritative', 0], 'authoritative flag');
    like(kea(isc('next-server tftp.example'))->{error}, qr/cannot resolve/,
         'next-server hostname needs resolver');

    is(kea(isc('allow members of "vip"'))->{'client-class'}, 'vip', 'pool class');
    is(kea(isc('deny unknown-clients'))->{'client-class'}, 'KNOWN',
       'deny unknown-clients -> KNOWN');
    is(kea(isc('allow unknown-clients'))->{'client-class'}, 'UNKNOWN',
       'allow unknown-clients -> UNKNOWN');
    ok(kea(isc('deny members of "x"'))->{error}, 'deny members of unsupported');

    ok(kea(isc('ddns-update-style none'))->{error}, 'raw statement not in KEA');
    like(kea(isc('match if option user-class = "x"'))->{error},
         qr/needs translation/, 'ISC expression is not copied to KEA');
};

subtest 'option-def' => sub {
    my $m = dhcp_model_new(4);
    dhcp_scope_add_isc($m, $m->{global}, 'option wpad code 252 = text');
    my $st = dhcp_scope_add_isc($m, $m->{global}, 'option wpad "http://x/wpad.dat"');
    ok($st->{def}, 'custom option typed after option-def');
    is_deeply($st->{values}, ['http://x/wpad.dat'], 'custom option value');

    my $k = dhcp_scope_to_kea($m, $m->{global});
    is_deeply($k->{'option-def'}, [ { name => 'wpad', code => 252, type => 'string',
                                      array => 0, space => 'dhcp4' } ],
              'KEA option-def');
    is($k->{'option-data'}[0]{name}, 'wpad', 'KEA custom option-data');

    $st = parse_isc_statement('option foo code 200 = array of ip-address', 4);
    my $d = dhcp_option_def_from_isc($st);
    is_deeply([@$d{qw(type array)}], ['ip4', 1], 'array of ip-address');
    $st = parse_isc_statement('option bar code 201 = { ip-address, text }', 4);
    is($st->{fmt}, DHCP_FMT_ISC, 'record option-def is ISC only');
};

# =========================================================================
# KEA -> ISC
# =========================================================================
subtest 'KEA option-data to statement' => sub {
    my $st = kea_option_to_statement({ name => 'domain-name', data => 'example.com' }, 4);
    is(format_isc_statement($st), 'option domain-name "example.com"', 'text quoted');

    $st = kea_option_to_statement({ code => 66, data => 'tftp.example' }, 4);
    is(format_isc_statement($st), 'option tftp-server-name "tftp.example"',
       'option by code only');

    $st = kea_option_to_statement({ name => 'dns-servers', data => '2001:db8::1, 2001:db8::2' }, 6);
    is(format_isc_statement($st), 'option dhcp6.name-servers 2001:db8::1, 2001:db8::2',
       'v6 option renamed and list kept');

    $st = kea_option_to_statement({ name => 'domain-search', data => 'a.example,b.example' }, 4);
    is(format_isc_statement($st), 'option domain-search "a.example", "b.example"',
       'fqdn list quoted per item');

    $st = kea_option_to_statement({ name => 'root-path', data => 'a\\,b' }, 4);
    is(format_isc_statement($st), 'option root-path "a,b"', 'escaped comma');

    $st = kea_option_to_statement({ name => 'vendor-class-identifier',
                                    data => '505845', 'csv-format' => JSON::PP::false() }, 4);
    is(format_isc_statement($st), 'option vendor-class-identifier 50:58:45', 'hex payload');

    $st = kea_option_to_statement({ name => 'routers', data => '0A000001',
                                    'csv-format' => JSON::PP::false() }, 4);
    is($st->{fmt}, DHCP_FMT_KEA, 'non-binary hex payload is KEA only');
    ok(!defined format_isc_statement($st), 'KEA only option not in ISC');
    is_deeply(kea($st)->{'option-data'}, { name => 'routers', data => '0A000001',
                                          'csv-format' => JSON::PP::false() },
              'KEA only option passed through verbatim');

    $st = kea_option_to_statement({ name => 'some-vendor-opt', data => 'x' }, 4);
    is($st->{fmt}, DHCP_FMT_KEA, 'unknown KEA option is KEA only');

    $st = kea_option_to_statement({ name => 'domain-name-servers', data => '10.0.0.1',
                                    'always-send' => JSON::PP::true() }, 4);
    ok(kea($st)->{'option-data'}{'always-send'}, 'always-send preserved for KEA');
    is(format_isc_statement($st), 'option domain-name-servers 10.0.0.1',
       'always-send ignored for ISC');
};

subtest 'KEA parameters to statement' => sub {
    my $st = kea_param_to_statement('valid-lifetime', 3600, 4);
    is(format_isc_statement($st), 'default-lease-time 3600', 'valid-lifetime');
    $st = kea_param_to_statement('boot-file-name', 'pxe.0', 4);
    is(format_isc_statement($st), 'filename "pxe.0"', 'boot-file-name');
    $st = kea_param_to_statement('authoritative', JSON::PP::false(), 4);
    is(format_isc_statement($st), 'not authoritative', 'authoritative false');

    $st = kea_param_to_statement('renew-timer', 900, 4);
    is($st->{kind}, 'kea', 'KEA only param');
    ok(!defined format_isc_statement($st), 'KEA only param not in ISC');
    is_deeply(kea($st)->{param}, ['renew-timer', 900], 'KEA only param round trip');

    $st = kea_param_to_statement('boot-file-name', 'x', 6);
    is($st->{kind}, 'kea', 'v4 only param in v6 context stays KEA only');
};

# =========================================================================
# model
# =========================================================================
subtest 'model and scopes' => sub {
    my $m = dhcp_model_new(4);
    my $net = dhcp_model_add($m, 'nets', { cidr => '10.1.0.0/24', name => 'net-1' });
    ok($net->{scope}, 'scope created');
    is(dhcp_model_find($m, 'nets', 'cidr', '10.1.0.0/24'), $net, 'find node');
    my $h = dhcp_model_add($m, 'hosts', { name => 'h1' });
    is_deeply($h->{classes}, [], 'host defaults');

    dhcp_scope_add_isc($m, $net->{scope}, $_) foreach (
        'option routers 10.1.0.1', 'default-lease-time 600',
        'ddns-update-style none', 'allow members of "vip"');
    dhcp_scope_add_kea_params($m, $net->{scope},
        { 'renew-timer' => 100, subnet => '10.1.0.0/24', pools => [] },
        [ 'subnet', 'pools' ]);
    dhcp_scope_add_kea_options($m, $net->{scope},
        [ { name => 'unknown-x', data => '1' } ]);

    my $k = dhcp_scope_to_kea($m, $net->{scope});
    is_deeply($k->{params}, { 'valid-lifetime' => 600, 'renew-timer' => 100 },
              'KEA params collected');
    is(scalar @{$k->{'option-data'}}, 2, 'KEA options collected');
    is($k->{'client-class'}, 'vip', 'client-class');

    $m->{warnings} = [];
    is_deeply([ dhcp_scope_to_isc($m, $net->{scope}) ],
              [ 'option routers 10.1.0.1', 'default-lease-time 600',
                'ddns-update-style none', 'allow members of "vip"' ],
              'ISC lines, KEA only statements skipped');
    is(scalar @{$m->{warnings}}, 2, 'skipped statements reported');
};

# =========================================================================
# real data: every DHCP statement of the fixtures parses and re-formats
# =========================================================================
subtest 'fixture statements' => sub {
    my $dump = "$FindBin::Bin/../test/sauron-demo.dump";
    plan skip_all => 'demo dump not found' unless -r $dump;
    open(my $fh, '<', $dump) or die $!;
    my ($in, $n) = (0, 0);
    while (<$fh>) {
        if (/^COPY dhcp_entries /) { $in = 1; next; }
        next unless $in;
        last if /^\\\./;
        chomp;
        my $line = (split /\t/)[3];
        my $st = isc($line);
        is(format_isc_statement($st), $line, "verbatim: $line");
        if ($st->{kind} ne 'raw' && ($st->{fmt} // 0) == DHCP_FMT_BOTH) {
            my $again = isc(reformat($st));
            is_deeply($again->{values} // $again->{value}, $st->{values} // $st->{value},
                      "structural round trip: $line");
        }
        $n++;
    }
    close($fh);
    ok($n > 0, "checked $n entries");
};

done_testing();
