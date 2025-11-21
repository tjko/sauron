#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use Net::DNS::ZoneFile;
use Digest::MD5 qw(md5_hex);

my ($z1_file, $z2_file, $ignore_soa, $ignore_ns, $verbose);
GetOptions(
    'zone1=s'    => \$z1_file,
    'zone2=s'    => \$z2_file,
    'ignore-soa'=> \$ignore_soa,
    'ignore-ns' => \$ignore_ns,
) or die "Bad options\n";

die "Both zone files required\n" unless $z1_file && $z2_file;

sub load {
    my ($file) = @_;
    my $zf = Net::DNS::ZoneFile->new($file);
    my %rec;

    while (my $rr = $zf->read) {
        # $rr je objekt Net::DNS::RR
        my $type = $rr->type;
        next if $ignore_soa && $type eq 'SOA';
        next if $ignore_ns && $type eq 'NS' && $rr->name eq $zf->origin;

        my $key = join('|', $rr->name, $type, $rr->class);
        my $content = join(' ', $rr->ttl, $rr->rdstring);
        $rec{$key} = { ttl=>$rr->ttl, rdata=>[$rr->rdata], hash=>md5_hex($content), obj=>$rr, line=>$rr->string };
    }
    return \%rec;
}

# -------------------------------------------------
# Read zone files
# -------------------------------------------------
my $zone1 = load($z1_file);
my $zone2 = load($z2_file);
my $zone2_full = load($z2_file);

# -------------------------------------------------
# Comparing
# -------------------------------------------------
my @only_in_1;
my @only_in_2;
my @changed;

foreach my $key (sort keys %$zone1) {
    if (!exists $zone2->{$key}) {
        push @only_in_1, $key;
    } else {
        # The record exists in both – we compare the hash of the content
        if ($zone1->{$key}{hash} ne $zone2->{$key}{hash}) {
            push @changed, $key;
        }
        delete $zone2->{$key};   # we will not check it again
    }
}
# The remaining keys in %$zone2 are only in the second zone
@only_in_2 = sort keys %$zone2;

# -------------------------------------------------
# Print results
# -------------------------------------------------
sub fmt_key {
    my ($key) = @_;
    my ($name,$type,$class) = split /\|/, $key;
    return "$name $type $class";
}

print "\n=== Records only in the first zone ($z1_file) ===\n";
if (@only_in_1) {
    foreach my $k (@only_in_1) {
        print fmt_key($k), "  => ", $zone1->{$k}{line}, "\n";
    }
} else {
    print "(none)\n";
}

print "\n=== Records only in the second zone ($z2_file) ===\n";
if (@only_in_2) {
    foreach my $k (@only_in_2) {
        print fmt_key($k), "  => ", $zone2->{$k}{line}, "\n";
    }
} else {
    print "(none)\n";
}

print "\n=== Records that differ (same name+type, but different content) ===\n";
if (@changed) {
    foreach my $k (@changed) {
        print ">>> ", fmt_key($k), "\n";
        print "    ", $zone1->{$k}{line}, " ; $z1_file\n";
        print "    ", $zone2_full->{$k}{line}, " ; $z2_file\n";
    }
} else {
    print "(none)\n";
}

exit 0;

