#!/usr/bin/perl
# t/09-dhcp-kea.t - Unit tests for Sauron::DhcpKea (KEA configuration
#                   reader) and KEA only statements (no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

use Sauron::DhcpDefs;
use Sauron::DhcpModel;
use Sauron::DhcpKea;

my $testdata = "$FindBin::Bin/../test";
my $tmp = tempdir(CLEANUP => 1);

sub write_file {
    my ($name, $text) = @_;
    open(my $fh, '>', "$tmp/$name") or die $!;
    print $fh $text;
    close($fh);
    return "$tmp/$name";
}

# statements of a scope as text: ISC syntax, or [KEA] JSON
sub stmts {
    my ($scope) = @_;
    return [ map { my $t = format_isc_statement($_);
                   defined $t ? $t : '[KEA] ' . kea_statement_to_json($_) }
             @{$scope->{stmts}} ];
}

sub model {
    my ($text, $family) = @_;
    my $f = write_file('kea.json', $text);
    return dhcp_model_from_kea(dhcp_kea_read_file($f), $family);
}

# =========================================================================
subtest 'format detection' => sub {
    ok(!is_kea_conf("$testdata/dhcpd.conf"), 'ISC dhcpd.conf is not KEA');
    ok(is_kea_conf("$testdata/kea-dhcp.json"), 'KEA JSON detected');
    ok(is_kea_conf(write_file('c.json', "// comment\n# x\n{ }\n")),
       'KEA JSON after comments detected');
};

# =========================================================================
subtest 'fixture test/kea-dhcp.json' => sub {
    my $root = dhcp_kea_read_file("$testdata/kea-dhcp.json");
    my $m = dhcp_model_from_kea($root, 4);
    is($m->{vlans}[0]{name}, 'kea-lab', 'shared-network');
    is($m->{nets}[0]{cidr}, '10.250.1.0/24', 'subnet');
    is($m->{nets}[0]{vlan}, 'kea-lab', 'subnet in shared-network');
    is($m->{nets}[0]{router}, '10.250.1.1', 'single router taken as subnet router');
    is_deeply(stmts($m->{nets}[0]{scope}), [], 'router option removed from scope');
    is(format_isc_statement($m->{pools}[0]{ranges}[0]),
       'range 10.250.1.100 10.250.1.110', 'pool range');
    is($m->{hosts}[0]{hw_address}, '00:30:40:50:60:70', 'reservation MAC');
    is_deeply(stmts($m->{global}),
              [ 'option domain-name-servers ns1.middle.earth, ns2.middle.earth' ],
              'global option');

    my $m6 = dhcp_model_from_kea($root, 6);
    is($m6->{hosts}[0]{duid}, '000100012a3b4c5d001122334455', 'reservation DUID');
    is_deeply($m6->{hosts}[0]{addresses}, ['2001:db8:250::10'], 'v6 address');
    is(format_isc_statement($m6->{pools}[0]{ranges}[0]),
       'range6 2001:db8:250::100 2001:db8:250::1ff', 'v6 pool');

    eval { dhcp_model_from_kea({ Dhcp4 => {} }, 6) };
    like($@, qr/does not include Dhcp6/, 'missing section reported');
};

# =========================================================================
subtest 'comments and includes' => sub {
    write_file('opts.json', qq([ { "name": "domain-name", "data": "inc.example" } ]));
    mkdir("$tmp/sub");
    write_file('sub/nets.json', qq([ { "subnet": "10.9.0.0/24" } ]));
    my $f = write_file('main.json', <<'EOF');
// line comment
{
  /* block comment */
  "Dhcp4": {
    # hash comment with "quote, don't break // parsing
    "option-data": <?include "opts.json"?>,
    "subnet4": <?include "sub/nets.json"?>,
    "boot-file-name": "http://x/a//b"
  }
}
EOF
    my $m = dhcp_model_from_kea(dhcp_kea_read_file($f), 4);
    is_deeply(stmts($m->{global}),
              [ 'option domain-name "inc.example"', 'filename "http://x/a//b"' ],
              'include expanded, // inside string kept');
    is($m->{nets}[0]{cidr}, '10.9.0.0/24', 'nested include relative to file');

    # include directory given explicitly (import-dhcp --dir)
    write_file('sub/o.json', qq([ { "name": "domain-name", "data": "dir.example" } ]));
    my $d = write_file('d.json', qq({ "Dhcp4": { "option-data": <?include "o.json"?> } }));
    my $m2 = dhcp_model_from_kea(dhcp_kea_read_file($d, "$tmp/sub"), 4);
    is_deeply(stmts($m2->{global}), [ 'option domain-name "dir.example"' ],
              'include looked up in given directory');
    eval { dhcp_kea_read_file($d) };
    like($@, qr/cannot read KEA configuration: .*o\.json/, 'missing include reported');

    eval { dhcp_kea_read_file(write_file('bad.json', '{ "Dhcp4": ')) };
    like($@, qr/cannot parse KEA configuration/, 'syntax error reported');
};

# =========================================================================
subtest 'v4 conversion' => sub {
    my $m = model(<<'EOF', 4);
{ "Dhcp4": {
    "valid-lifetime": 3600, "renew-timer": 900, "authoritative": true,
    "interfaces-config": { "interfaces": [ "eth0" ] },
    "option-def": [ { "name": "wpad", "code": 252, "type": "string" } ],
    "option-data": [ { "name": "wpad", "data": "http://w/wpad.dat" },
                     { "code": 66, "data": "tftp.example" } ],
    "client-classes": [
      { "name": "pxe", "test": "substring(option[60].hex,0,9) == 'PXEClient'",
        "boot-file-name": "pxe.0" },
      { "name": "vip" },
      { "name": "bad", "test": { "invalid": true } } ],
    "reservations": [ { "hostname": "glob", "hw-address": "AA-BB-CC-DD-EE-01",
                        "ip-address": "10.1.0.50" } ],
    "subnet4": [ {
      "id": 7, "subnet": "10.1.0.0/24",
      "option-data": [ { "name": "routers", "data": "10.1.0.1, 10.1.0.2" } ],
      "pools": [ { "pool": "10.1.0.100-10.1.0.150", "client-class": "vip" },
                 { "pool": "10.1.0.200 - 10.1.0.210", "client-class": "KNOWN" },
                 { "pool": "10.1.0.220 - 10.1.0.230", "client-class": "UNKNOWN" },
                 { "pool": "bogus" },
                 { "pool": "10.1.0.10-10.1.0.x" } ],
      "reservations": [
        { "hostname": "cid", "client-id": "01:aa:bb:cc:dd:ee:02", "ip-address": "10.1.0.51" },
        { "hostname": "flex", "flex-id": "'abc'", "ip-address": "10.1.0.52" },
        { "hw-address": "aa:bb:cc:dd:ee:03", "ip-address": "10.1.0.53",
          "client-classes": [ "vip" ],
          "option-data": [ { "name": "host-name", "data": "h3" } ] } ] } ]
} }
EOF
    is_deeply(stmts($m->{global}), [
        'option wpad code 252 = text',
        'option wpad "http://w/wpad.dat"',
        'option tftp-server-name "tftp.example"',
        'authoritative',
        '[KEA] {"interfaces-config":{"interfaces":["eth0"]}}',
        '[KEA] {"renew-timer":900}',
        'default-lease-time 3600',
    ], 'global scope: ISC statements and KEA only parameters');

    my $net = $m->{nets}[0];
    ok(!defined $net->{router}, 'two routers are not a single subnet router');
    is_deeply(stmts($net->{scope}), [ 'option routers 10.1.0.1, 10.1.0.2', '[KEA] {"id":7}' ],
              'subnet scope');
    is(scalar @{$net->{pools}}, 3, 'invalid pool skipped');
    is_deeply([ map { stmts($_->{scope})->[0] } @{$net->{pools}} ],
              [ 'allow members of "vip"', 'deny unknown-clients', 'deny known-clients' ],
              'pool client classes');
    ok((grep { /invalid range: bogus/ } @{$m->{warnings}}), 'invalid pool reported');
    ok((grep { /invalid range: 10\.1\.0\.10-10\.1\.0\.x/ } @{$m->{warnings}}),
       'pool with invalid address reported');

    my %h = map { ($_->{name} => $_) } @{$m->{hosts}};
    is($h{glob}{hw_address}, 'aa:bb:cc:dd:ee:01', 'global reservation, MAC normalised');
    is($h{cid}{hw_address}, 'aa:bb:cc:dd:ee:02', 'client-id 01:<mac> used as MAC');
    ok(!$h{flex}{hw_address}, 'flex-id is not a MAC');
    is_deeply(stmts($h{flex}{scope}), [ q([KEA] {"flex-id":"'abc'"}) ],
              'unsupported identifier kept for KEA');
    my ($h3) = grep { $_->{name} =~ /^host-/ } @{$m->{hosts}};
    is_deeply($h3->{classes}, ['vip'], 'reservation client-classes');
    is_deeply(stmts($h3->{scope}), [ 'option host-name "h3"' ], 'reservation options');

    my %c = map { ($_->{name} => $_) } @{$m->{classes}};
    is($c{pxe}{type}, 103, 'class with test is custom class');
    is_deeply(stmts($c{pxe}{scope}),
              [ q([KEA] {"test":"substring(option[60].hex,0,9) == 'PXEClient'"}),
                'filename "pxe.0"' ], 'class test kept for KEA, params converted');
    is($c{vip}{type}, 3, 'class without test is a membership class');
    is_deeply(stmts($c{bad}{scope}), [], 'non-string class test ignored');
};

# =========================================================================
subtest 'v6 conversion' => sub {
    my $m = model(<<'EOF', 6);
{ "Dhcp6": {
    "option-data": [ { "name": "dns-servers", "data": "2001:db8::1" } ],
    "subnet6": [ { "subnet": "2001:db8:1::/64", "preferred-lifetime": 3000,
      "pools": [ { "pool": "2001:db8:1::/80" } ],
      "pd-pools": [ { "prefix": "2001:db8:8::", "prefix-len": 56, "delegated-len": 64 } ],
      "reservations": [
        { "hostname": "a", "duid": "00:01:00:01:2A:3B:4C:5D:0A:0B:0C:0D:0E:10",
          "ip-addresses": [ "2001:db8:1::10", "2001:db8:1::11" ],
          "prefixes": [ "2001:db8:9::/64" ] },
        { "hostname": "b", "hw-address": "aa:bb:cc:dd:ee:04", "ip-addresses": [ "2001:db8:1::12" ] },
        { "hostname": "c", "duid": "00:03:00:01:aa:bb:cc:dd:ee:05", "ip-addresses": [ "2001:db8:1::13" ] } ] } ]
} }
EOF
    is_deeply(stmts($m->{global}), [ 'option dhcp6.name-servers 2001:db8::1' ], 'v6 option renamed');
    is_deeply(stmts($m->{nets}[0]{scope}),
              [ '[KEA] {"pd-pools":[{"delegated-len":64,"prefix":"2001:db8:8::","prefix-len":56}]}',
                'preferred-lifetime 3000' ], 'pd-pools kept for KEA');
    is(format_isc_statement($m->{pools}[0]{ranges}[0]), 'range6 2001:db8:1::/80', 'prefix pool');
    my %h = map { ($_->{name} => $_) } @{$m->{hosts}};
    is($h{a}{duid}, '000100012a3b4c5d0a0b0c0d0e10', 'DUID normalised');
    is_deeply($h{a}{addresses}, [ '2001:db8:1::10', '2001:db8:1::11' ], 'all addresses');
    is_deeply(stmts($h{a}{scope}), [ '[KEA] {"prefixes":["2001:db8:9::/64"]}' ], 'prefixes kept');
    ok(!$h{b}{duid}, 'hw-address is not a DUID');
    ok((grep { /reservation b: no supported identifier/ } @{$m->{warnings}}),
       'unsupported v6 identifier reported');
    ok(!$h{c}{duid}, 'short DUID (DUID-LL) not used');
    ok((grep { /reservation c: unsupported DUID length/ } @{$m->{warnings}}),
       'short DUID reported');
    is_deeply(stmts($h{c}{scope}), [ '[KEA] {"duid":"00:03:00:01:aa:bb:cc:dd:ee:05"}' ],
              'short DUID kept for KEA');
};

# =========================================================================
subtest 'KEA writer' => sub {
    my $m = dhcp_model_new(4);
    $m->{server} = { name => 's', comment => 'c' };
    $m->{local} = dhcp_scope_new();
    dhcp_scope_add_isc($m, $m->{global}, $_) foreach (
        'default-lease-time 600', 'one-lease-per-client true',
        'option domain-name-servers ns1.example');
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement('{"renew-timer":100}', 4));
    my $cl = dhcp_model_add($m, 'classes', { name => 'vip', type => 3,
        members => [ { id => 'aa:bb:cc:dd:ee:01', name => 'h1' },
                     { id => 'aa:bb:cc:dd:ee:09', name => 'dyn' } ] });
    my $pxe = dhcp_model_add($m, 'classes', { name => 'pxe', type => 103, members => [] });
    dhcp_scope_add_stmt($m, $pxe->{scope}, kea_json_to_statement('{"test":"member(\'x\')"}', 4));
    my $vl = dhcp_model_add($m, 'vlans', { name => 'lab', id => 5, nets => [] });
    my $net = dhcp_model_add($m, 'nets', { cidr => '10.1.0.0/24', id => 42,
                                           router => '10.1.0.1', pools => [] });
    push @{$vl->{nets}}, $net;
    # same router given by code only: replaces the router option
    dhcp_scope_add_stmt($m, $net->{scope},
        kea_json_to_statement('{"option-data":{"code":3,"data":"10.1.0.254"}}', 4));
    dhcp_scope_add_stmt($m, $net->{scope}, kea_json_to_statement('{"lease-database":{}}', 4));
    dhcp_scope_add_isc($m, $net->{scope}, 'option wpad code 252 = text');
    my $net2 = dhcp_model_add($m, 'nets', { cidr => '10.2.0.0/24', id => 7, pools => [] });
    dhcp_scope_add_stmt($m, $net2->{scope}, kea_json_to_statement('{"id":42}', 4));
    my $net3 = dhcp_model_add($m, 'nets', { cidr => '10.3.0.0/24', id => 1, pools => [] });
    my $pool = dhcp_model_add($m, 'pools', { name => 'p' });
    push @{$pool->{ranges}}, parse_isc_statement('range 10.1.0.100 10.1.0.110', 4);
    dhcp_scope_add_isc($m, $pool->{scope}, $_)
        foreach ('allow members of "vip"', 'max-lease-time 900');
    push @{$net->{pools}}, $pool;
    my $grp = dhcp_model_add($m, 'groups', { name => 'g' });
    dhcp_scope_add_isc($m, $grp->{scope}, 'option root-path "/r"');
    my $h = dhcp_model_add($m, 'hosts', { name => 'h1.example', group => 'g',
        hw_address => 'aa:bb:cc:dd:ee:01', addresses => [ '10.1.0.10', '10.2.0.1' ] });
    dhcp_scope_add_isc($m, $h->{scope}, 'option host-name "h1"');

    my $cfg = dhcp_model_to_kea($m, sub { $_[0] eq 'ns1.example' ? '10.0.0.53' : undef })->{Dhcp4};
    is($cfg->{'valid-lifetime'}, 600, 'global parameter');
    is($cfg->{'renew-timer'}, 100, 'KEA only global parameter');
    is($cfg->{'option-data'}[0]{data}, '10.0.0.53', 'hostname resolved');
    is_deeply([ map { $_->{name} } @{$cfg->{'client-classes'}} ], [ 'vip', 'pxe' ], 'classes');
    is($cfg->{'client-classes'}[1]{test}, "member('x')", 'class test');
    my $sn = $cfg->{'shared-networks'}[0];
    is($sn->{name}, 'lab', 'shared network');
    my $s = $sn->{subnet4}[0];
    is($s->{id}, 2, 'Sauron id clashing with a KEA id replaced by an unused one');
    is_deeply($s->{'option-data'}, [ { code => 3, data => '10.1.0.254' } ],
              'router replaced by the same option given by code');
    ok(!exists $s->{'option-def'}, 'no option-def in subnet');
    is_deeply([ map { $_->{name} } @{$cfg->{'option-def'}} ], [ 'wpad' ], 'option-def global');
    ok(!exists $s->{'lease-database'}, 'global only parameter left out of subnet');
    my %ids = map { ($_->{subnet} => $_->{id}) } @{$cfg->{subnet4}};
    is_deeply(\%ids, { '10.2.0.0/24' => 42, '10.3.0.0/24' => 1 },
              'explicit KEA id and Sauron ids kept');
    is_deeply($s->{pools}, [ { pool => '10.1.0.100 - 10.1.0.110', 'client-class' => 'vip' } ],
              'pool with class, lifetime left out');
    my $r = $s->{reservations}[0];
    is($r->{'ip-address'}, '10.1.0.10', 'reservation in its subnet');
    is_deeply($r->{'client-classes'}, ['vip'], 'reservation class');
    is_deeply([ sort map { $_->{name} } @{$r->{'option-data'}} ], [ 'host-name', 'root-path' ],
              'host and group options merged');
    my %w = map { $_ => 1 } @{$m->{warnings}};
    ok($w{'skipped in KEA output: ISC only statement: one-lease-per-client true'}, 'ISC only reported');
    ok($w{'pool p: parameter max-valid-lifetime is not allowed in a KEA pool, ignored'},
       'pool lifetime reported');
    ok($w{'subnet 10.1.0.0/24: subnet id 42 already used, using 2'}, 'id clash reported');
    is_deeply($cfg->{reservations},
              [ { 'hw-address' => 'aa:bb:cc:dd:ee:09', 'client-classes' => ['vip'] } ],
              'class member without reservation gets a global reservation');
    ok($cfg->{'reservations-global'} && $cfg->{'reservations-in-subnet'},
       'global and subnet reservations enabled');
};

# =========================================================================
subtest 'KEA High Availability' => sub {
    my $mk = sub {
        my $m = dhcp_model_new(4);
        $m->{local} = dhcp_scope_new();
        $m->{ha} = { this => 'a', mode => 'load-balancing', max_response_delay => 60000,
                     peers => [ { name => 'a', url => 'http://192.0.2.1:8001/', role => 'primary' },
                                { name => 'b', url => 'http://192.0.2.2:8001/', role => 'secondary' } ] };
        return $m;
    };
    my $cfg = dhcp_model_to_kea($mk->())->{Dhcp4};
    my $h = $cfg->{'hooks-libraries'};
    is_deeply([ map { $_->{library} } @$h ], [ 'libdhcp_lease_cmds.so', 'libdhcp_ha.so' ],
              'lease_cmds and ha hooks');
    my $ha = $h->[1]{parameters}{'high-availability'}[0];
    is($ha->{'this-server-name'}, 'a', 'this server');
    is($ha->{mode}, 'load-balancing', 'mode');
    is($ha->{'max-response-delay'}, 60000, 'max-response-delay in ms');
    ok($ha->{'multi-threading'}{'http-dedicated-listener'}, 'dedicated listener');

    my $m = $mk->();
    $m->{hooks_dir} = '/opt/kea/hooks';
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement(
        '{"hooks-libraries":[{"library":"/x/libdhcp_lease_cmds.so"}]}', 4));
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement(
        '{"multi-threading":{"enable-multi-threading":false}}', 4));
    $cfg = dhcp_model_to_kea($m)->{Dhcp4};
    is_deeply([ map { $_->{library} } @{$cfg->{'hooks-libraries'}} ],
              [ '/x/libdhcp_lease_cmds.so', '/opt/kea/hooks/libdhcp_ha.so' ],
              'existing lease_cmds kept, hooks directory used');
    ok(!exists $cfg->{'hooks-libraries'}[1]{parameters}{'high-availability'}[0]{'multi-threading'},
       'no dedicated listener when multi-threading is disabled');

    $m = $mk->();
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement(
        '{"hooks-libraries":[{"library":"/usr/lib/kea/hooks/libdhcp_ha.so.70","parameters":{}}]}', 4));
    $cfg = dhcp_model_to_kea($m)->{Dhcp4};
    is(scalar @{$cfg->{'hooks-libraries'}}, 2, 'configured (versioned) ha hook not duplicated');
    ok((grep { /already contain libdhcp_ha/ } @{$m->{warnings}}), 'reported');

    # the model is not changed by the conversion
    $m = $mk->();
    dhcp_scope_add_stmt($m, $m->{global}, kea_json_to_statement(
        '{"hooks-libraries":[{"library":"libdhcp_lease_cmds.so"}]}', 4));
    my $c1 = JSON::PP->new->canonical->encode(dhcp_model_to_kea($m));
    my $c2 = JSON::PP->new->canonical->encode(dhcp_model_to_kea($m));
    is($c1, $c2, 'converting twice gives the same configuration');
    ok(!(grep { /already contain/ } @{$m->{warnings}}), 'no false warning');

    $m = $mk->();
    $m->{ha}{max_response_delay} = 5000;
    $ha = dhcp_model_to_kea($m)->{Dhcp4}{'hooks-libraries'}[1]{parameters}{'high-availability'}[0];
    is($ha->{'heartbeat-delay'}, 2500, 'heartbeat below a short max-response-delay');
};

# =========================================================================
subtest 'KEA DHCP-DDNS (D2) configuration' => sub {
    my $d2 = { domains => [ { name => 'a.example.', reverse => 0, key_id => 1 },
                            { name => 'b.example.', reverse => 0, key_id => 2 },
                            { name => '10.in-addr.arpa.', reverse => 1, key_id => 1 },
                            { name => 'c.example.', reverse => 0 },
                            { name => 'd.example.', reverse => 0, key_id => 2 } ],
               keys => { 1 => { id => 1, name => 'k1', algorithm => 157 },
                         2 => { id => 2, name => 'k2', algorithm => 999 } } };
    my @w;
    my $cfg = dhcp_kea_d2_config($d2, { dns_ip => '192.0.2.53',
        algorithm => sub { $_[0]{algorithm} == 157 ? 'HMAC-MD5' : undef },
        secret => sub { 'c2VjcmV0' }, warn => sub { push @w, $_[0] } })->{DhcpDdns};
    is_deeply($cfg->{'tsig-keys'}, [ { name => 'k1', algorithm => 'HMAC-MD5', secret => 'c2VjcmV0' } ],
              'used key listed once');
    is_deeply([ map { $_->{name} . ':' . ($_->{'key-name'} // '-') } @{$cfg->{'forward-ddns'}{'ddns-domains'}} ],
              [ 'a.example.:k1', 'c.example.:-' ], 'forward domains, unusable key left out');
    is($cfg->{'reverse-ddns'}{'ddns-domains'}[0]{name}, '10.in-addr.arpa.', 'reverse domain');
    is_deeply($cfg->{'forward-ddns'}{'ddns-domains'}[0]{'dns-servers'},
              [ { 'ip-address' => '192.0.2.53', port => 53 } ], 'DNS server');
    like($w[0], qr/key k2: unsupported algorithm, dynamic DNS for b\.example\. not generated/,
         'unusable key reported');
    like($w[1], qr/dynamic DNS for d\.example\. not generated/, 'each dropped domain reported');
};

# =========================================================================
subtest 'KEA only statements in the database' => sub {
    my @cases = (
        [ kea_param_to_statement('renew-timer', 900, 4), '{"renew-timer":900}' ],
        [ kea_option_to_statement({ name => 'x-opt', data => '1' }, 4),
          '{"option-data":{"data":"1","name":"x-opt"}}' ],
        [ kea_option_def_to_statement({ name => 'r', code => 201, type => 'record',
                                        'record-types' => 'uint8, string' }, 4),
          '{"option-def":{"code":201,"name":"r","record-types":"uint8, string","type":"record"}}' ],
        [ { kind => 'match', kea_test => "member('x')", fmt => DHCP_FMT_KEA },
          q({"test":"member('x')"}) ],
        [ kea_param_to_statement('authoritative', JSON::PP::true(), 6), '{"authoritative":true}' ],
    );
    foreach my $c (@cases) {
        my ($st, $json) = @$c;
        is(kea_statement_to_json($st), $json, "encode $json");
        my $back = kea_json_to_statement($json, 4);
        is(kea_statement_to_json($back), $json, "decode/encode round trip $json");
        is($back->{fmt}, DHCP_FMT_KEA, 'decoded statement is KEA only');
        ok(!defined format_isc_statement($back), 'not written to ISC');
        ok(!isc_statement_to_kea($back)->{error}, 'converts to KEA');
    }
    ok(!defined kea_statement_to_json(parse_isc_statement('default-lease-time 1', 4)),
       'ISC statement is not KEA only');
    my $bad = kea_json_to_statement('{"a":1,"b":2}', 4);
    like($bad->{error}, qr/one member/, 'invalid KEA entry reported');
};

done_testing();
