#!/usr/bin/perl
# t/zone-canonicalize.pl - Canonicalize BIND zone file for comparison
#
# Parses a BIND zone file using Sauron::UtilZone::process_zonefile()
# and outputs sorted, canonical records (one per line) suitable for diff.
#
# SOA serial number is replaced with "SERIAL" placeholder.
# All domain names are lowercased and fully qualified.
#
# Usage:
#   perl t/zone-canonicalize.pl <zone-origin> <zone-file>
#
# Example:
#   perl t/zone-canonicalize.pl roundtrip.example.com test/roundtrip.example.com.zone
#   perl t/zone-canonicalize.pl roundtrip.example.com /tmp/generated/roundtrip.example.com.zone
#
# For round-trip comparison:
#   diff <(perl t/zone-canonicalize.pl roundtrip.example.com test/original.zone) \
#        <(perl t/zone-canonicalize.pl roundtrip.example.com /tmp/generated.zone)
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by transitive imports
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);

use Sauron::UtilZone;
use Sauron::Util;
use Net::IP qw(:PROC);

my $origin = shift @ARGV or die "Usage: $0 <zone-origin> <zone-file>\n";
my $zonefile = shift @ARGV or die "Usage: $0 <zone-origin> <zone-file>\n";

$origin .= '.' unless $origin =~ /\.$/;

die "Cannot read zone file: $zonefile\n" unless -r $zonefile;

my %zonedata;
process_zonefile($zonefile, $origin, \%zonedata, 0);

my @canonical = canonicalize_zone(\%zonedata, $origin);

for my $line (sort @canonical) {
    print "$line\n";
}

exit(0);


# Convert parsed zone data into sorted canonical record lines.
#
# Each line: "<owner> <CLASS> <TYPE> <RDATA>"
# TTL is omitted from comparison (zone default vs explicit is ambiguous).
# SOA serial is replaced with SERIAL.
# All names are FQDN and lowercased.
#
sub canonicalize_zone {
    my ($zonedata, $origin) = @_;
    my @records;
    my $lc_origin = lc($origin);

    for my $domain (keys %{$zonedata}) {
        my $rec = $zonedata->{$domain};
        my $owner = lc($domain);

        # SOA
        if ($rec->{SOA} && length($rec->{SOA}) > 0) {
            my @soa = split(/\s+/, $rec->{SOA});
            # soa[0]=mname, soa[1]=rname, soa[2]=serial, soa[3..6]=refresh,retry,expire,minimum
            $soa[2] = 'SERIAL';
            push @records, "$owner IN SOA " . join(' ', @soa);
        }

        # NS
        for my $ns (@{$rec->{NS}}) {
            push @records, "$owner IN NS " . lc($ns);
        }

        # A
        for my $a (sort @{$rec->{A}}) {
            push @records, "$owner IN A $a";
        }

        # AAAA
        for my $aaaa (sort @{$rec->{AAAA}}) {
            # Normalize IPv6 to compressed form
            my $normalized = ip_compress_address(lc($aaaa), 6);
            push @records, "$owner IN AAAA $normalized";
        }

        # CNAME
        if ($rec->{CNAME} && length($rec->{CNAME}) > 0) {
            push @records, "$owner IN CNAME " . lc($rec->{CNAME});
        }

        # MX
        for my $mx (sort @{$rec->{MX}}) {
            # MX stored as "priority target" where target may contain $DOMAIN
            # $DOMAIN represents the short hostname (without origin).
            # process_zonefile stores: "pri $DOMAIN.origin." when MX target = owner
            my ($pri, $target) = split(/\s+/, $mx, 2);
            if ($target && $target =~ /\$DOMAIN/) {
                # Replace $DOMAIN with the short name part of owner
                my $shortname = $owner;
                $shortname =~ s/\.\Q$lc_origin\E$//;
                $target =~ s/\$DOMAIN/$shortname/;
            }
            $target = lc($target) if $target;
            push @records, "$owner IN MX $pri $target";
        }

        # TXT
        for my $txt (sort @{$rec->{TXT}}) {
            push @records, "$owner IN TXT \"$txt\"";
        }

        # HINFO
        if ($rec->{HINFO} && ($rec->{HINFO}[0] ne '' || $rec->{HINFO}[1] ne '')) {
            push @records, "$owner IN HINFO $rec->{HINFO}[0] $rec->{HINFO}[1]";
        }

        # WKS
        for my $wks (sort @{$rec->{WKS}}) {
            push @records, "$owner IN WKS $wks";
        }

        # SRV
        for my $srv (sort @{$rec->{SRV}}) {
            push @records, "$owner IN SRV $srv";
        }

        # SSHFP
        for my $sshfp (sort @{$rec->{SSHFP}}) {
            push @records, "$owner IN SSHFP " . uc($sshfp);
        }

        # TLSA
        for my $tlsa (sort @{$rec->{TLSA}}) {
            push @records, "$owner IN TLSA " . uc($tlsa);
        }

        # NAPTR
        for my $naptr (sort @{$rec->{NAPTR}}) {
            push @records, "$owner IN NAPTR $naptr";
        }

        # DS
        for my $ds (sort @{$rec->{DS}}) {
            push @records, "$owner IN DS " . uc($ds);
        }

        # CAA
        for my $caa (sort @{$rec->{CAA}}) {
            push @records, "$owner IN CAA $caa";
        }

        # PTR (for reverse zones)
        for my $ptr (sort @{$rec->{PTR}}) {
            push @records, "$owner IN PTR " . lc($ptr);
        }
    }

    return sort @records;
}
