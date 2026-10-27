#!/usr/bin/perl
# t/03-utildhcp.t - Unit tests for Sauron::UtilDhcp (DHCP conf parsing, no DB)
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempfile);

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by transitive imports
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

use Sauron::UtilDhcp;

my $testdata = "$FindBin::Bin/../test";

# =========================================================================
# process_dhcpdconf - v4
# =========================================================================
subtest 'process_dhcpdconf v4' => sub {
    my $conf_file = "$testdata/dhcpd.conf";
    plan skip_all => "test/dhcpd.conf not found" unless -r $conf_file;

    my %data;
    process_dhcpdconf($conf_file, \%data, 0);

    ok(scalar keys %data > 0, 'parsed data has entries');
    ok(ref $data{'shared-network'} eq 'HASH', 'shared-network structure parsed');
    ok(ref $data{subnet} eq 'HASH', 'subnet structure parsed');
    ok(scalar keys %{$data{'shared-network'}} > 0, 'shared-network entries found');
    ok(exists $data{subnet}{'10.10.100.0 netmask 255.255.255.0'}, 'known subnet key parsed');
};

# =========================================================================
# KEA format detection
# =========================================================================
subtest 'is_kea_dhcpconf detection' => sub {
    my $isc_conf = "$testdata/dhcpd.conf";
    my $kea_conf = "$testdata/kea-dhcp.json";
    plan skip_all => "KEA/ISC fixtures not found" unless -r $isc_conf && -r $kea_conf;

    ok(!is_kea_dhcpconf($isc_conf), 'ISC dhcpd.conf is not detected as KEA');
    ok(is_kea_dhcpconf($kea_conf), 'KEA JSON is detected');
};

# =========================================================================
# process_kea_dhcpconf - v4
# =========================================================================
subtest 'process_kea_dhcpconf v4' => sub {
    my $conf_file = "$testdata/kea-dhcp.json";
    plan skip_all => "test/kea-dhcp.json not found" unless -r $conf_file;

    my %data;
    process_kea_dhcpconf($conf_file, \%data, 0);

    ok(exists $data{'shared-network'}{'kea-lab'}, 'shared-network imported from KEA');
    ok(exists $data{subnet}{'10.250.1.0 netmask 255.255.255.0'}, 'KEA subnet converted to netmask format');
    ok(exists $data{pool}{'pool-1'}, 'KEA pool imported');
    ok(exists $data{host}{'kea-ws1.middle.earth'}, 'KEA reservation imported as host');

    like(join("\n", @{$data{GLOBAL}}),
        qr/option domain-name-servers ns1\.middle\.earth,ns2\.middle\.earth;/,
        'KEA global option converted');
    like(join("\n", @{$data{subnet}{'10.250.1.0 netmask 255.255.255.0'}}),
        qr/^VLAN kea-lab/m,
        'subnet bound to shared-network via VLAN marker');
    like($data{pool}{'pool-1'}->[0],
        qr/^range 10\.250\.1\.100 10\.250\.1\.110;/,
        'pool range converted to ISC-like syntax');
    like(join("\n", @{$data{host}{'kea-ws1.middle.earth'}}),
        qr/hardware ethernet 00:30:40:50:60:70;/,
        'host hardware address retained');
};

# =========================================================================
# process_kea_dhcpconf - v6
# =========================================================================
subtest 'process_kea_dhcpconf v6' => sub {
    my $conf_file = "$testdata/kea-dhcp.json";
    plan skip_all => "test/kea-dhcp.json not found" unless -r $conf_file;

    my %data;
    process_kea_dhcpconf($conf_file, \%data, 1);

    ok(exists $data{subnet6}{'2001:db8:250::/64'}, 'KEA DHCPv6 subnet imported');
    ok(exists $data{pool6}{'pool6-1'}, 'KEA DHCPv6 pool imported');
    ok(exists $data{host}{'kea-host6.middle.earth'}, 'KEA DHCPv6 reservation imported as host');

    like($data{pool6}{'pool6-1'}->[0],
        qr/^range6 2001:db8:250::100 2001:db8:250::1ff;/,
        'DHCPv6 pool converted to range6 syntax');
    like(join("\n", @{$data{host}{'kea-host6.middle.earth'}}),
        qr/fixed-address6 2001:db8:250::10;/,
        'DHCPv6 fixed address retained');
    like(join("\n", @{$data{host}{'kea-host6.middle.earth'}}),
        qr/host-identifier option dhcp6\.client-id 00:03:00:01:00:11:22:33:44:55;/,
        'DUID normalized for import-dhcp parser');
};

# =========================================================================
# process_kea_dhcpconf - class null-safety
# =========================================================================
subtest 'process_kea_dhcpconf class non-string test ignored' => sub {
        my ($fh, $tmpfile) = tempfile();
        print {$fh} <<'JSON';
{
    "Dhcp4": {
        "client-classes": [
            {
                "name": "non-string-test",
                "test": {"invalid": true}
            }
        ]
    }
}
JSON
        close $fh;

        my %data;
        process_kea_dhcpconf($tmpfile, \%data, 0);

        ok(exists $data{class}{'non-string-test'}, 'class record is imported');
        is_deeply($data{class}{'non-string-test'}, [], 'non-string class test does not produce match-if line');
};

done_testing();
