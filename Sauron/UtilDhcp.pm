# Sauron::UtilDhcp.pm - ISC DHCPD config file reading/parsing routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000,2002.
# $Id$
#
package Sauron::UtilDhcp;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(process_dhcpdconf);

use IO::File;
use strict;

my $debug = 1;

# parse dhcpd.conf file, build hash of all entries in the file
#
sub process_dhcpdconf($$) {
  my ($filename,$data)=@_;

  my $fh = IO::File->new();
  my ($i,$c,$tmp,$quote,$lend,$fline,$prev,%state);

  print "process_dhcpdconf($filename,DATA)\n" if ($debug);

  die("cannot read conf file: $filename") unless (-r $filename);
  open($fh,$filename) || die("cannot open conf file: $filename");

  $tmp='';
  while (<$fh>) {
    chomp;
    next if (/^\s*$/);
    next if (/^\s*#/);

    $quote=0;
#    print "line '$_'\n";
    s/\s+/\ /g; s/\s+$//; # s/^\s+//;

    for $i (0..length($_)-1) {
      $prev=($i > 0 ? substr($_,$i-1,1) : ' ');
      $c=substr($_,$i,1);
      $quote=($quote ? 0 : 1)	if (($c eq '"') && ($prev ne '\\'));
      unless ($quote) {
	last if ($c eq '#');
	$lend = ($c =~ /^[;{}]$/ ? 1 : 0);
      }
      $tmp .= $c;
      if ($lend) {
	process_line($tmp,$data,\%state);
	$tmp='';
      }
    }

    die("$filename($.): unterminated quoted string!\n") if ($quote);
  }
  process_line($tmp,$data,\%state);

  close($fh);

  return 0;
}

sub process_line($$$) {
  my($line,$data,$state) = @_;

  my($tmp,$block,$rest);

  return if ($line =~ /^\s*$/);
  $line =~ s/(^\s+|\s+$)//g;


  if ($line =~ /^(\S+)\s+(\S.*)?{$/) {
    #print "begin '$1' '$2'\n";
    $rest=$2;
    unshift @{$$state{blocks}}, $1;
  }
  elsif ($line =~ /^\s*}\s*$/) {
    #print "end '$$state{blocks}->[0]'\n";
    shift @{$$state{blocks}};
  }
  $block=$$state{blocks}->[0];
  print "line($block) '$line'\n";

  if ($block eq 'class') {
    if ($line =~ /^(class)\s+(\S+)\s+{$/) {
      ($tmp=$2) =~ s/^\"|\"$//g;
      print "class: '$tmp'\n";
      unshift @{$$state{groups}},$tmp;
    }
  }



  return 0;
}

1;
# eof
