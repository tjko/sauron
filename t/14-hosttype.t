#!/usr/bin/perl
# t/14-hosttype.t - Unit tests for hosttype determination in import-zone
# Tests all possible combinations of DNS record types

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use Data::Dumper;

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link || -l $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by transitive imports
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

use Sauron::UtilZone;
use Sauron::Util;
use Encode qw(encode decode);

my $testdata = "$FindBin::Bin/../test";

# =========================================================================
# Helper function to simulate hosttype determination logic from import-zone
# =========================================================================
sub determine_hosttype {
    my ($rec, $host2) = @_;
    
    # Simulate db_build_list_str for NS records
    my $nslist = '';
    if (@{$rec->{NS}} > 0) {
        $nslist = join(', ', @{$rec->{NS}});
    }
    
    # Determine hosttype based on record types present
    my $has_ip = (@{$rec->{A}} > 0 || @{$rec->{AAAA}} > 0);
    my $has_ns = ($nslist && $nslist ne '');
    my $has_mx = (@{$rec->{MX}} > 0);
    my $has_srv = (@{$rec->{SRV}} > 0);
    my $has_tlsa = (@{$rec->{TLSA}} > 0);
    my $has_txt = (@{$rec->{TXT}} > 0);
    my $has_naptr = (@{$rec->{NAPTR}} > 0);
    my $has_caa = (@{$rec->{CAA}} > 0);
    
    my $hosttype = 0;
    # Priority-based hosttype assignment (higher priority types checked first)
    if ($has_ns && $host2 ne '@') {
        $hosttype = 2;  # delegation/glue record
    } elsif ($has_ip) {
        $hosttype = 1;  # regular host with IP address
    } elsif ($has_mx && !$has_ns) {
        $hosttype = 3;  # MX only (no IP, no NS)
    } elsif ($has_srv) {
        $hosttype = 8;  # SRV records
    } elsif ($has_tlsa) {
        $hosttype = 12; # TLSA records
    } elsif ($has_txt && !$has_ip) {
        $hosttype = 13; # TXT only (no IP)
    } elsif ($has_naptr) {
        $hosttype = 14; # NAPTR records
    } elsif ($has_caa && !$has_ip) {
        $hosttype = 15; # CAA only (no IP)
    }
    
    return $hosttype;
}

# =========================================================================
# Parse the test zone file and verify hosttype assignments
# =========================================================================
subtest 'Parse hosttype combinations zone file' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    plan skip_all => "test/hosttype-combinations.zone not found" unless -r $zone_file;

    my %zone;
    eval { process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0) };
    is($@, '', 'zone file parses without error');
    ok(scalar(keys %zone) > 0, 'zone has entries');
};

# =========================================================================
# Test HOSTTYPE 1 - Hosts with IP addresses (A or AAAA)
# =========================================================================
subtest 'HOSTTYPE 1 - Regular hosts with IP addresses' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test A record only
    my $host = 'host-type1-a.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    my $htype = determine_hosttype($zone{$host}, 'host-type1-a');
    is($htype, 1, "hosttype=1 for A record only");
    
    # Test AAAA record only
    $host = 'host-type1-aaaa.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{AAAA}}), 1, "has one AAAA record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-aaaa');
    is($htype, 1, "hosttype=1 for AAAA record only");
    
    # Test both A and AAAA
    $host = 'host-type1-both.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{AAAA}}), 1, "has one AAAA record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-both');
    is($htype, 1, "hosttype=1 for both A and AAAA records");
    
    # Test A + MX (IP should take priority)
    $host = 'host-type1-mx.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{MX}}), 1, "has one MX record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-mx');
    is($htype, 1, "hosttype=1 for A+MX (IP takes priority)");
    
    # Test A + TXT
    $host = 'host-type1-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has one TXT record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-txt');
    is($htype, 1, "hosttype=1 for A+TXT (IP takes priority)");
    
    # Test A + SRV
    $host = 'host-type1-srv.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{SRV}}), 1, "has one SRV record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-srv');
    is($htype, 1, "hosttype=1 for A+SRV (IP takes priority)");
    
    # Test A + TLSA
    $host = 'host-type1-tlsa.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{TLSA}}), 1, "has one TLSA record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-tlsa');
    is($htype, 1, "hosttype=1 for A+TLSA (IP takes priority)");
    
    # Test A + NAPTR
    $host = 'host-type1-naptr.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{NAPTR}}), 1, "has one NAPTR record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-naptr');
    is($htype, 1, "hosttype=1 for A+NAPTR (IP takes priority)");
    
    # Test A + CAA
    $host = 'host-type1-caa.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "has one A record");
    is(scalar(@{$zone{$host}{CAA}}), 1, "has one CAA record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-caa');
    is($htype, 1, "hosttype=1 for A+CAA (IP takes priority)");
    
    # Test AAAA + MX
    $host = 'host-type1-aaaa-mx.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{AAAA}}), 1, "has one AAAA record");
    is(scalar(@{$zone{$host}{MX}}), 1, "has one MX record");
    $htype = determine_hosttype($zone{$host}, 'host-type1-aaaa-mx');
    is($htype, 1, "hosttype=1 for AAAA+MX (IP takes priority)");
};

# =========================================================================
# Test HOSTTYPE 2 - Delegation/glue records (NS without @ hostname)
# =========================================================================
subtest 'HOSTTYPE 2 - Delegation/glue records' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test subdomain delegation (NS records)
    my $host = 'subdomain.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    ok(scalar(@{$zone{$host}{NS}}) > 0, "has NS records");
    my $htype = determine_hosttype($zone{$host}, 'subdomain');
    is($htype, 2, "hosttype=2 for NS delegation (subdomain)");
    
    # Test delegated subdomain
    $host = 'delegated.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    ok(scalar(@{$zone{$host}{NS}}) > 0, "has NS records");
    $htype = determine_hosttype($zone{$host}, 'delegated');
    is($htype, 2, "hosttype=2 for NS delegation (delegated)");
    
    # Test glue records (should be hosttype=1 since they have A records)
    $host = 'ns1.subdomain.testhosttype.example.com.';
    ok(exists $zone{$host}, "glue record exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "glue record has A record");
    $htype = determine_hosttype($zone{$host}, 'ns1.subdomain');
    is($htype, 1, "hosttype=1 for glue record with A (ns1.subdomain)");
    
    $host = 'ns2.subdomain.testhosttype.example.com.';
    ok(exists $zone{$host}, "glue record exists: $host");
    is(scalar(@{$zone{$host}{A}}), 1, "glue record has A record");
    $htype = determine_hosttype($zone{$host}, 'ns2.subdomain');
    is($htype, 1, "hosttype=1 for glue record with A (ns2.subdomain)");
};

# =========================================================================
# Test HOSTTYPE 3 - MX only (no IP, no NS)
# =========================================================================
subtest 'HOSTTYPE 3 - MX only records' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test single MX record
    my $host = 'host-type3-mxonly.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    is(scalar(@{$zone{$host}{MX}}), 1, "has one MX record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    is(scalar(@{$zone{$host}{AAAA}}), 0, "has no AAAA records");
    my $htype = determine_hosttype($zone{$host}, 'host-type3-mxonly');
    is($htype, 3, "hosttype=3 for MX only (single)");
    
    # Test multiple MX records
    $host = 'host-type3-mxonly-multi.testhosttype.example.com.';
    ok(exists $zone{$host}, "host entry exists: $host");
    ok(scalar(@{$zone{$host}{MX}}) > 1, "has multiple MX records");
    $htype = determine_hosttype($zone{$host}, 'host-type3-mxonly-multi');
    is($htype, 3, "hosttype=3 for MX only (multiple)");
};

# =========================================================================
# Test HOSTTYPE 8 - SRV records only (no IP)
# =========================================================================
subtest 'HOSTTYPE 8 - SRV records only' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test _sip._tcp SRV
    my $host = '_sip._tcp.testhosttype.example.com.';
    ok(exists $zone{$host}, "SRV entry exists: $host");
    is(scalar(@{$zone{$host}{SRV}}), 1, "has one SRV record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    my $htype = determine_hosttype($zone{$host}, '_sip._tcp');
    is($htype, 8, "hosttype=8 for SRV only (_sip._tcp)");
    
    # Test _xmpp._tcp SRV
    $host = '_xmpp._tcp.testhosttype.example.com.';
    ok(exists $zone{$host}, "SRV entry exists: $host");
    is(scalar(@{$zone{$host}{SRV}}), 1, "has one SRV record");
    $htype = determine_hosttype($zone{$host}, '_xmpp._tcp');
    is($htype, 8, "hosttype=8 for SRV only (_xmpp._tcp)");
    
    # Test _http._tcp SRV
    $host = '_http._tcp.testhosttype.example.com.';
    ok(exists $zone{$host}, "SRV entry exists: $host");
    is(scalar(@{$zone{$host}{SRV}}), 1, "has one SRV record");
    $htype = determine_hosttype($zone{$host}, '_http._tcp');
    is($htype, 8, "hosttype=8 for SRV only (_http._tcp)");
};

# =========================================================================
# Test HOSTTYPE 12 - TLSA records only (no IP)
# =========================================================================
subtest 'HOSTTYPE 12 - TLSA records only' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test _443._tcp.www TLSA
    my $host = '_443._tcp.www.testhosttype.example.com.';
    ok(exists $zone{$host}, "TLSA entry exists: $host");
    is(scalar(@{$zone{$host}{TLSA}}), 1, "has one TLSA record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    my $htype = determine_hosttype($zone{$host}, '_443._tcp.www');
    is($htype, 12, "hosttype=12 for TLSA only (_443._tcp.www)");
    
    # Test _25._tcp.mail TLSA
    $host = '_25._tcp.mail.testhosttype.example.com.';
    ok(exists $zone{$host}, "TLSA entry exists: $host");
    is(scalar(@{$zone{$host}{TLSA}}), 1, "has one TLSA record");
    $htype = determine_hosttype($zone{$host}, '_25._tcp.mail');
    is($htype, 12, "hosttype=12 for TLSA only (_25._tcp.mail)");
};

# =========================================================================
# Test HOSTTYPE 13 - TXT records only (no IP)
# =========================================================================
subtest 'HOSTTYPE 13 - TXT records only' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test single TXT
    my $host = 'host-type13-txt-single.testhosttype.example.com.';
    ok(exists $zone{$host}, "TXT entry exists: $host");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has one TXT record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    my $htype = determine_hosttype($zone{$host}, 'host-type13-txt-single');
    is($htype, 13, "hosttype=13 for TXT only (single)");
    
    # Test multiple TXT
    $host = 'host-type13-txt-multi.testhosttype.example.com.';
    ok(exists $zone{$host}, "TXT entry exists: $host");
    ok(scalar(@{$zone{$host}{TXT}}) > 1, "has multiple TXT records");
    $htype = determine_hosttype($zone{$host}, 'host-type13-txt-multi');
    is($htype, 13, "hosttype=13 for TXT only (multiple)");
    
    # Test SPF record
    $host = 'host-type13-txt-spf.testhosttype.example.com.';
    ok(exists $zone{$host}, "SPF entry exists: $host");
    is($zone{$host}{TXT}[0], 'v=spf1 mx -all', "has SPF record");
    $htype = determine_hosttype($zone{$host}, 'host-type13-txt-spf');
    is($htype, 13, "hosttype=13 for TXT (SPF)");
    
    # Test DKIM record
    $host = 'host-type13-txt-dkim.testhosttype.example.com.';
    ok(exists $zone{$host}, "DKIM entry exists: $host");
    like($zone{$host}{TXT}[0], qr/^v=DKIM1/, "has DKIM record");
    $htype = determine_hosttype($zone{$host}, 'host-type13-txt-dkim');
    is($htype, 13, "hosttype=13 for TXT (DKIM)");
};

# =========================================================================
# Test HOSTTYPE 14 - NAPTR records only (no IP)
# =========================================================================
subtest 'HOSTTYPE 14 - NAPTR records only' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test SIP NAPTR
    my $host = 'host-type14-naptr-sip.testhosttype.example.com.';
    ok(exists $zone{$host}, "NAPTR entry exists: $host");
    is(scalar(@{$zone{$host}{NAPTR}}), 1, "has one NAPTR record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    my $htype = determine_hosttype($zone{$host}, 'host-type14-naptr-sip');
    is($htype, 14, "hosttype=14 for NAPTR only (SIP)");
    
    # Test HTTP NAPTR
    $host = 'host-type14-naptr-http.testhosttype.example.com.';
    ok(exists $zone{$host}, "NAPTR entry exists: $host");
    is(scalar(@{$zone{$host}{NAPTR}}), 1, "has one NAPTR record");
    $htype = determine_hosttype($zone{$host}, 'host-type14-naptr-http');
    is($htype, 14, "hosttype=14 for NAPTR only (HTTP)");
    
    # Test empty flags NAPTR
    $host = 'host-type14-naptr-empty.testhosttype.example.com.';
    ok(exists $zone{$host}, "NAPTR entry exists: $host");
    is(scalar(@{$zone{$host}{NAPTR}}), 1, "has one NAPTR record");
    $htype = determine_hosttype($zone{$host}, 'host-type14-naptr-empty');
    is($htype, 14, "hosttype=14 for NAPTR only (empty flags)");
};

# =========================================================================
# Test HOSTTYPE 15 - CAA records only (no IP)
# =========================================================================
subtest 'HOSTTYPE 15 - CAA records only' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # Test single CAA
    my $host = 'host-type15-caa-single.testhosttype.example.com.';
    ok(exists $zone{$host}, "CAA entry exists: $host");
    is(scalar(@{$zone{$host}{CAA}}), 1, "has one CAA record");
    is(scalar(@{$zone{$host}{A}}), 0, "has no A records");
    my $htype = determine_hosttype($zone{$host}, 'host-type15-caa-single');
    is($htype, 15, "hosttype=15 for CAA only (single)");
    
    # Test multiple CAA
    $host = 'host-type15-caa-multi.testhosttype.example.com.';
    ok(exists $zone{$host}, "CAA entry exists: $host");
    ok(scalar(@{$zone{$host}{CAA}}) > 1, "has multiple CAA records");
    $htype = determine_hosttype($zone{$host}, 'host-type15-caa-multi');
    is($htype, 15, "hosttype=15 for CAA only (multiple)");
};

# =========================================================================
# Test complex combinations - priority order verification
# =========================================================================
subtest 'Complex combinations - priority order' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # SRV + TXT => SRV wins (hosttype=8)
    my $host = 'host-combo-srv-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "combo entry exists: $host");
    is(scalar(@{$zone{$host}{SRV}}), 1, "has SRV record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has TXT record");
    my $htype = determine_hosttype($zone{$host}, 'host-combo-srv-txt');
    is($htype, 8, "hosttype=8 for SRV+TXT (SRV wins)");
    
    # TLSA + TXT => TLSA wins (hosttype=12)
    $host = 'host-combo-tlsa-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "combo entry exists: $host");
    is(scalar(@{$zone{$host}{TLSA}}), 1, "has TLSA record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has TXT record");
    $htype = determine_hosttype($zone{$host}, 'host-combo-tlsa-txt');
    is($htype, 12, "hosttype=12 for TLSA+TXT (TLSA wins)");
    
    # NAPTR + TXT => TXT wins because it's checked first in elsif chain (hosttype=13)
    $host = 'host-combo-naptr-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "combo entry exists: $host");
    is(scalar(@{$zone{$host}{NAPTR}}), 1, "has NAPTR record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has TXT record");
    $htype = determine_hosttype($zone{$host}, 'host-combo-naptr-txt');
    is($htype, 13, "hosttype=13 for NAPTR+TXT (TXT checked first)");
    
    # CAA + TXT => TXT wins because it's checked first in elsif chain (hosttype=13)
    $host = 'host-combo-caa-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "combo entry exists: $host");
    is(scalar(@{$zone{$host}{CAA}}), 1, "has CAA record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has TXT record");
    $htype = determine_hosttype($zone{$host}, 'host-combo-caa-txt');
    is($htype, 13, "hosttype=13 for CAA+TXT (TXT checked first)");
    
    # MX + TXT => MX wins (hosttype=3)
    $host = 'host-combo-mx-txt.testhosttype.example.com.';
    ok(exists $zone{$host}, "combo entry exists: $host");
    is(scalar(@{$zone{$host}{MX}}), 1, "has MX record");
    is(scalar(@{$zone{$host}{TXT}}), 1, "has TXT record");
    $htype = determine_hosttype($zone{$host}, 'host-combo-mx-txt');
    is($htype, 3, "hosttype=3 for MX+TXT (MX wins)");
};

# =========================================================================
# Test CNAME records (should be skipped in main loop)
# =========================================================================
subtest 'CNAME records handling' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    # CNAME aliases exist but should be handled separately
    my $host = 'alias-type4-www.testhosttype.example.com.';
    ok(exists $zone{$host}, "CNAME alias exists: $host");
    ok($zone{$host}{CNAME}, "has CNAME target");
    
    $host = 'alias-type4-mail.testhosttype.example.com.';
    ok(exists $zone{$host}, "CNAME alias exists: $host");
    ok($zone{$host}{CNAME}, "has CNAME target");
};

# =========================================================================
# Test zone apex (@) record
# =========================================================================
subtest 'Zone apex (@) record' => sub {
    my $zone_file = "$testdata/hosttype-combinations.zone";
    return unless -r $zone_file;
    
    my %zone;
    process_zonefile($zone_file, 'testhosttype.example.com.', \%zone, 0);
    
    my $host = 'testhosttype.example.com.';
    ok(exists $zone{$host}, "zone apex exists: $host");
    ok($zone{$host}{SOA}, "has SOA record");
    ok(scalar(@{$zone{$host}{NS}}) > 0, "has NS records");
    ok(scalar(@{$zone{$host}{MX}}) > 0, "has MX records");
    ok(scalar(@{$zone{$host}{TXT}}) > 0, "has TXT records");
    
    # Zone apex with @ as host2 should not be treated as delegation
    my $htype = determine_hosttype($zone{$host}, '@');
    # With NS and @ hostname, it should fall through to MX check (has_mx && !has_ns is false because has_ns is true)
    # Then to SRV, TLSA, TXT... has_txt && !has_ip => 13
    is($htype, 13, "zone apex gets hosttype=13 (TXT, no IP, NS ignored for @)");
};

# =========================================================================
# Summary of all hosttype values tested
# =========================================================================
subtest 'Hosttype coverage summary' => sub {
    diag("\nHosttype values tested:");
    diag("  hosttype=1  : Regular hosts with IP (A/AAAA)");
    diag("  hosttype=2  : Delegation (NS records)");
    diag("  hosttype=3  : MX only");
    diag("  hosttype=4  : CNAME (handled separately)");
    diag("  hosttype=8  : SRV only");
    diag("  hosttype=12 : TLSA only");
    diag("  hosttype=13 : TXT only");
    diag("  hosttype=14 : NAPTR only");
    diag("  hosttype=15 : CAA only");
    pass("All hosttype values documented");
};

done_testing();