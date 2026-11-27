#!/usr/bin/perl
# t/08-dhcp-model.t - Unit tests for Sauron::DhcpDefs and Sauron::DhcpModel
#                     (ISC <-> KEA statement conversion, no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

use JSON::PP;
use Sauron::DhcpDefs;
use Sauron::DhcpModel;

my $JSON = JSON::PP->new->canonical;

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

    $st = isc('one-lease-per-client true');
    is($st->{kind}, 'raw', 'unknown statement is raw');
    is($st->{fmt}, DHCP_FMT_ISC, 'raw statement is ISC only');
    is(format_isc_statement($st), 'one-lease-per-client true', 'raw kept verbatim');
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

    $r = kea(isc('option vendor-class-identifier "PXEClient"'));
    is($r->{'option-data'}{data}, 'PXEClient', 'vendor-class-identifier is a KEA string');
    $r = kea(isc('option vendor-class-identifier 50:58:45'));
    is($r->{'option-data'}{data}, 'PXE', 'string given as hex decoded to text');
    ok(kea(isc('option vendor-class-identifier 00:01'))->{error},
       'non-printable string rejected');
    $r = kea(isc('option dhcp-client-identifier "abc"'));
    is($r->{'option-data'}{data}, '616263', 'binary text to hex');
    $r = kea(isc('option dhcp-client-identifier 1:0:11:22:33:44:55'));
    is($r->{'option-data'}{data}, '01001122334455', 'binary colon hex to hex');

    is_deeply(kea(isc('default-lease-time 600'))->{param},
              ['valid-lifetime', 600], 'lease time param');
    is_deeply(kea(isc('filename "pxe.0"'))->{param},
              ['boot-file-name', 'pxe.0'], 'filename param');
    is($JSON->encode(kea(isc('not authoritative'))->{param}),
       '["authoritative",false]', 'authoritative is a JSON boolean');
    is($JSON->encode(kea(isc('authoritative'))->{param}),
       '["authoritative",true]', 'authoritative true');

    is(kea(isc('option ip-forwarding off'))->{'option-data'}{data}, 'false',
       'ISC boolean off -> false');
    is(kea(isc('option ip-forwarding on'))->{'option-data'}{data}, 'true',
       'ISC boolean on -> true');
    ok(kea(isc('option ip-forwarding maybe'))->{error}, 'invalid boolean rejected');

    like(kea(isc('option routers 999.1.1.1'))->{error}, qr/cannot resolve/,
         'invalid IPv4 address rejected');
    like(kea(isc('option dhcp6.name-servers 1.2.3.4:', 6))->{error}, qr/cannot resolve/,
         'invalid IPv6 address rejected');
    like(kea(isc('next-server tftp.example'))->{error}, qr/cannot resolve/,
         'next-server hostname needs resolver');

    is(kea(isc('allow members of "vip"'))->{'client-class'}, 'vip', 'pool class');
    is(kea(isc('deny unknown-clients'))->{'client-class'}, 'KNOWN',
       'deny unknown-clients -> KNOWN');
    is(kea(isc('allow unknown-clients'))->{'client-class'}, 'UNKNOWN',
       'allow unknown-clients -> UNKNOWN');
    ok(kea(isc('deny members of "x"'))->{error}, 'deny members of unsupported');

    ok(kea(isc('one-lease-per-client true'))->{error}, 'raw statement not in KEA');
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
    is($JSON->encode($k->{'option-def'}),
       '[{"array":false,"code":252,"name":"wpad","space":"dhcp4","type":"string"}]',
       'KEA option-def with JSON boolean and numeric code');
    is($JSON->encode($k->{'option-data'}),
       '[{"code":252,"data":"http://x/wpad.dat","name":"wpad","space":"dhcp4"}]',
       'KEA custom option-data with numeric code');

    # vendor space definitions must not shadow standard options
    dhcp_scope_add_isc($m, $m->{global}, 'option PXE.mtftp-ip code 1 = ip-address');
    my $st2 = kea_option_to_statement({ code => 1, data => '255.255.255.0' }, 4,
                                      $m->{option_defs});
    is($st2->{name}, 'subnet-mask', 'code 1 in dhcp4 space is subnet-mask');
    $st2 = kea_option_to_statement({ space => 'PXE', name => 'mtftp-ip',
                                     data => '10.0.0.1' }, 4, $m->{option_defs});
    is(format_isc_statement($st2), 'option PXE.mtftp-ip 10.0.0.1',
       'vendor space option found by space and name');
    $st2 = isc('option PXE.mtftp-ip 10.0.0.1', 4, $m->{option_defs});
    is(kea($st2)->{'option-data'}{space}, 'PXE', 'vendor space kept for KEA');

    $st = parse_isc_statement('option foo code 200 = array of ip-address', 4);
    my $d = dhcp_option_def_from_isc($st);
    is_deeply([@$d{qw(type array)}], ['ip4', 1], 'array of ip-address');
    $st = parse_isc_statement('option bar code 201 = { ip-address, text }', 4);
    is($st->{fmt}, DHCP_FMT_ISC, 'record option-def is ISC only');
};

subtest 'KEA option-def' => sub {
    my $m = dhcp_model_new(4);
    dhcp_scope_add_kea_option_defs($m, $m->{global}, [
        { name => 'wpad', code => 252, type => 'string' },
        { name => 'srvs', code => 200, type => 'ipv4-address', array => JSON::PP::true() },
        { name => 'rec', code => 201, type => 'record', 'record-types' => 'uint8, string' },
    ]);
    dhcp_scope_add_kea_params($m, $m->{global},
        { 'option-def' => [ { name => 'x' } ], 'valid-lifetime' => 10 }, []);
    dhcp_scope_add_kea_options($m, $m->{global},
        [ { name => 'wpad', data => 'http://x/wpad.dat' } ]);

    is_deeply([ dhcp_scope_to_isc($m, $m->{global}) ],
              [ 'option wpad code 252 = text',
                'option srvs code 200 = array of ip-address',
                'default-lease-time 10',
                'option wpad "http://x/wpad.dat"' ],
              'KEA option-def imported, used for typing, not a param');
    my $k = dhcp_scope_to_kea($m, $m->{global});
    is(scalar @{$k->{'option-def'}}, 3, 'all option-defs in KEA output');
    is($k->{'option-def'}[2]{'record-types'}, 'uint8, string',
       'record option-def passed through verbatim');
    ok(!exists $k->{params}{'option-def'}, 'option-def not duplicated as param');
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

    $st = kea_option_to_statement({ name => 'vendor-class-identifier', data => 'PXEClient' }, 4);
    is(format_isc_statement($st), 'option vendor-class-identifier "PXEClient"',
       'KEA string option quoted in ISC');

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
        'one-lease-per-client true', 'allow members of "vip"');
    dhcp_scope_add_kea_params($m, $net->{scope},
        { 'renew-timer' => 100, subnet => '10.1.0.0/24', pools => [] },
        [ 'subnet', 'pools' ]);
    dhcp_scope_add_kea_options($m, $net->{scope},
        [ { name => 'unknown-x', data => '1' } ]);

    my $k = dhcp_scope_to_kea($m, $net->{scope}, undef, 'subnet');
    is_deeply($k->{params}, { 'valid-lifetime' => 600, 'renew-timer' => 100 },
              'KEA params collected');
    is(scalar @{$k->{'option-data'}}, 2, 'KEA options collected');
    ok(!defined $k->{'client-class'}, 'permit list ignored outside pool');
    ok((grep { /permit list outside of a pool/ } @{$m->{warnings}}),
       'permit outside pool reported');

    my $pool = dhcp_model_add($m, 'pools', { name => 'p1' });
    dhcp_scope_add_isc($m, $pool->{scope}, 'deny unknown-clients');
    is(dhcp_scope_to_kea($m, $pool->{scope}, undef, 'pool')->{'client-class'},
       'KNOWN', 'permit list used in pool');

    $m->{warnings} = [];
    is_deeply([ dhcp_scope_to_isc($m, $net->{scope}) ],
              [ 'option routers 10.1.0.1', 'default-lease-time 600',
                'one-lease-per-client true', 'allow members of "vip"' ],
              'ISC lines, KEA only statements skipped');
    is(scalar @{$m->{warnings}}, 2, 'skipped statements reported');
};

# =========================================================================
# dynamic DNS
# =========================================================================
subtest 'DDNS statements' => sub {
    my $J = JSON::PP->new->canonical->allow_nonref;
    my @c = (
        [ 'ddns-update-style none', '{"none":1}' ],
        [ 'ddns-update-style interim', '{"param":["dhcp-ddns",{"enable-updates":true}]}' ],
        [ 'ddns-updates off', '{"param":["ddns-send-updates",false]}' ],
        [ 'ddns-updates on', '{"param":["ddns-send-updates",true]}' ],
        [ 'ddns-domainname "dyn.example"', '{"param":["ddns-qualifying-suffix","dyn.example"]}' ],
        [ 'ignore client-updates', '{"param":["ddns-override-client-update",true]}' ],
        [ 'deny client-updates', '{"param":["ddns-override-client-update",true]}' ],
        [ 'allow client-updates', '{"param":["ddns-override-client-update",false]}' ],
    );
    foreach my $c (@c) {
        my $st = isc($c->[0]);
        is($J->encode(kea($st)), $c->[1], "$c->[0] -> KEA");
        is(reformat($st), $c->[0], "$c->[0] re-formatted");
    }
    ok(kea(isc('ddns-update-style ad-hoc'))->{error}, 'ad-hoc has no KEA equivalent');
    is($J->encode(kea(isc('ddns-update-style Interim'))),
       '{"param":["dhcp-ddns",{"enable-updates":true}]}', 'style is case-insensitive');
    is($J->encode(kea(isc('ddns-update-style NONE'))), '{"none":1}', 'NONE = none');
    like(kea(isc('client-updates bogus'))->{error}, qr/invalid client-updates/,
         'invalid client-updates rejected');

    # ddns-update-style next to a KEA only dhcp-ddns with connection settings
    my $m = dhcp_model_new(4);
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement(
        '{"dhcp-ddns":{"server-ip":"10.0.0.5","enable-updates":false}}', 4));
    dhcp_scope_add_isc($m, $m->{global}, 'ddns-update-style interim');
    is($J->encode(dhcp_scope_to_kea($m, $m->{global})->{params}{'dhcp-ddns'}),
       '{"enable-updates":true,"server-ip":"10.0.0.5"}', 'dhcp-ddns members merged');
    my ($e, $w) = dhcp_entry_check('ddns-update-style none', 0, 4);
    is($w, '', 'ddns-update-style none needs no hint (KEA default)');

    is(format_isc_statement(kea_param_to_statement('ddns-send-updates', JSON::PP::true(), 4)),
       'ddns-updates on', 'KEA ddns-send-updates -> ISC');
    is(format_isc_statement(kea_param_to_statement('ddns-override-client-update',
                                                   JSON::PP::false(), 4)),
       'allow client-updates', 'KEA ddns-override-client-update -> ISC');
    is(kea_param_to_statement('dhcp-ddns', { 'enable-updates' => JSON::PP::true() }, 4)->{kind},
       'kea', 'dhcp-ddns stays KEA only');
};

# =========================================================================
# entry validation (web UI / API)
# =========================================================================
subtest 'dhcp_entry_check' => sub {
    my @c = (
        [ 'default-lease-time 600', 0, 4, '', '' ],
        [ 'option routers gw.example', 0, 4, '', '' ],
        [ 'one-lease-per-client true', 0, 4, '', qr/no KEA equivalent/ ],
        [ 'one-lease-per-client true', 1, 4, '', '' ],
        [ 'match if option user-class = "x"', 0, 4, '', qr/not converted to KEA/ ],
        [ '{"renew-timer":900}', 2, 4, '', '' ],
        [ '{"renew-timer":900}', 0, 4, qr/set the format to KEA only/, '' ],
        [ '{"renew-timer":900', 2, 4, qr/invalid KEA entry/, '' ],
        [ 'x', 5, 4, qr/invalid format/, '' ],
        [ 'option dhcp6.name-servers 2001:db8::1', 0, 6, '', '' ],
    );
    foreach my $c (@c) {
        my ($t, $f, $fam, $e, $w) = @$c;
        my ($ge, $gw) = dhcp_entry_check($t, $f, $fam);
        ref $e ? like($ge, $e, "error: $t [$f]") : is($ge, $e, "no error: $t [$f]");
        ref $w ? like($gw, $w, "warning: $t [$f]") : is($gw, $w, "no warning: $t [$f]");
    }
};

# =========================================================================
# ISC writer with statements that have no database text (KEA import)
# =========================================================================
subtest 'ISC writer' => sub {
    require Sauron::DhcpIsc;
    Sauron::DhcpIsc->import();
    my $m = dhcp_model_new(4);
    $m->{server} = { name => 'srv', comment => 'c' };
    $m->{local} = dhcp_scope_new();
    $m->{netblocks} = [ { cidr => '10.1.0.0/16' } ];
    dhcp_scope_add_kea_params($m, $m->{global},
        { 'valid-lifetime' => 600, 'renew-timer' => 100 }, []);
    my $vl = dhcp_model_add($m, 'vlans', { name => 'lab', nets => [] });
    my $net = dhcp_model_add($m, 'nets', { cidr => '10.1.2.0/24', name => 'n1',
                                           router => '10.1.2.1', pools => [] });
    push @{$vl->{nets}}, $net;
    dhcp_scope_add_kea_options($m, $net->{scope},
        [ { name => 'domain-name', data => 'lab.example' } ]);
    my $h = dhcp_model_add($m, 'hosts', { name => 'h1.lab.example', net => 0,
                                          hw_address => 'aa:bb:cc:dd:ee:ff',
                                          address_text => '10.1.2.10' });
    $m->{ungrouped} = 1;
    $m->{ungrouped_hosts} = [ $h ];

    my $out = '';
    open(my $fh, '>', \$out) or die;
    dhcp_isc_write($fh, $m, { filename => 'dhcpd.conf', version => 'x',
                              user => 'u', time => 't' });
    close($fh);
    like($out, qr/^default-lease-time 600;\n/m, 'param formatted from structure');
    unlike($out, qr/renew-timer/, 'KEA only param not written');
    like($out, qr/^\t\toption routers 10\.1\.2\.1;\n\t\toption domain-name "lab\.example";\n/m,
         'router and quoted option in subnet');
    like($out, qr/^host h1\.lab\.example \{\n\tfixed-address 10\.1\.2\.10;\n/m, 'host');
    ok(!(grep { /renew-timer/ } @{$m->{warnings}}), 'KEA only statement skipped silently');
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

subtest 'dhcp_ip_in' => sub {
    my $a6 = dhcp_ip_obj(1, '2001:db8::5');
    ok(dhcp_ip_in(1, dhcp_ip_obj(1, '2001:db8::/64'), $a6), 'v6 address in /64');
    ok(dhcp_ip_in(1, dhcp_ip_obj(1, '2001:db8::5/128'), $a6), 'v6 address in its own /128');
    ok(!dhcp_ip_in(1, dhcp_ip_obj(1, '2001:db9::/64'), $a6), 'v6 address outside');
    my $a4 = dhcp_ip_obj(0, '10.0.0.5');
    ok(dhcp_ip_in(0, dhcp_ip_obj(0, '10.0.0.5/32'), $a4), 'v4 address in its own /32');
    ok(!dhcp_ip_in(0, dhcp_ip_obj(0, '10.0.1.0/24'), $a4), 'v4 address outside');
};

done_testing();
