# Sauron::UtilZone.pm - BIND zone file reading/parsing routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000,2002.
# $Id$
#
package Sauron::UtilZone;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(process_zonefile);

use Sauron::Util;
#use strict;

my $debug = 0;

# parse zone file, build hash of all domain names in zone
#
# resoure record format:
# {<domain>|@|<blank>} [<ttl>] [<class>] <type> <rdata> [<comment>]
#
sub process_zonefile($$$$$$) {
  my ($handle,$filename,$origin,$zonedata,$ext_flag,$PROG_DIR)=@_;

  my ($ZONEFILE);
  my ($domain,$i,$c,@line,$ttl,$class,$fline,$type);
  my ($rec,$zone_ttl);
  my (@line,@tmpline,$tmporigin,$tmp);

  $class='IN';
  $handle++;
  $zone_ttl=-1;
  $ext_flag=0 if (! $ext_flag);
  $origin.="." unless ($origin =~ /\.$/);

  print "process_zonefile($handle,$filename,$origin,ZONEDATA,",
        "$ext_flag,$PROG_DIR)\n" if ($debug);

  die("Cannot excecute $PROG_DIR/parse-hosts-rows!")
    unless (-x "$PROG_DIR/parse-hosts-rows");

  open($handle,"$PROG_DIR/parse-hosts-rows $filename |") 
    || die("Cannot open zonefile: $filename");

  while (<$handle>) {
    chomp;
    $fline=$_;
    #s/;.*$//o;
    next if /^\s*$/;
    next if /^#/;
    #print "line: $_\n";

    if (/^\$ORIGIN\s+(\S+)(\s|$)/) {
      #print "\$ORIGIN: '$1'\n";
      $origin=add_origin($1,$origin);
      next;
    }
    if (/^\$INCLUDE\s+(\S+)(\s+(\S+))?(\s|$)/) {
      #print "\$INCLUDE: '$1' '$3'\n";
      $tmporigin=$3;
      $tmporigin=$origin if ($3 eq '');
      process_zonefile($handle,$1,$tmporigin,$zonedata,$ext_flag);
      next;
    }
    if (/^\$TTL\s+(\S+)(\s|$)/) {
      print "\$TTL: $1\n";
      $tmp=$1;
      $zone_ttl = $tmp if ($tmp =~ /(\d+)/);
      next;
    }

    unless (/^(\S+)?\s+((\d+)\s+)?(([iI][nN]|[cC][sS]|[cC][hH]|[hH][sS])\s+)?(\S+)\s+(.*)\s*$/) {
      print STDERR "Invalid line ($filename): $fline\n" if ($ext_flag < 0);
      next;
    }

    $domain=$1 unless ($1 eq '');
    if ($3 eq '') { $ttl=$zone_ttl; } else { $ttl=$3; }
    $class="\U$5" unless ($5 eq '');
    $type = "\U$6";
    $_ = $7;
    next if ($domain eq '');

    # domain
    $domain=add_origin($domain,$origin);
    warn("invalid domainname $domain\n$fline") 
      if (! valid_domainname($domain) && $ext_flag < 0);

    # class
	
    die("Invalid or missing RR class") unless ($class =~ /^(IN|CS|CH|HS)$/);

    # type
    unless ($type =~ /^(SOA|A|PTR|CNAME|MX|NS|TXT|HINFO|WKS|MB|MG|MD|MF|MINFO|MR|AFSDB|ISDN|RP|RT|X25|PX|SRV)$/) {
      if ($ext_flag > 0) {
	unless ($type =~ /^(DHCP|ALIAS|AREC|ROUTER|PRINTER|BOOTP|INFO|ETHER2?|GROUP|BOOTP|MUUTA[0-9]|TYPE|SERIAL|PCTCP)$/) {
	  print STDERR "unsupported RR type '$type' in $filename\n$fline\n";
	  next;
	}
      } else {
	print STDERR 
	  "invalid/unsupported RR type '$type' in $filename:\n$fline\n";
	next;
      }
    }


    if (! $zonedata->{$domain}) {
      $rec= { TTL => $ttl,
	      CLASS => $class,
	      SOA => '',
	      A => [],
	      PTR => [],
	      CNAME => '',
	      MX => [],
	      NS => [],
	      TXT => [],
	      HINFO => ['',''],
	      WKS => [],

	      RP => [],
	      SRV => [],

	      SERIAL => '',
	      TYPE => '',
	      MUUTA => [],
	      ETHER => '',
	      ETHER2 => '',
	      DHCP => [],
	      ROUTER => '',
	      ROUTER_DHCP => [],
	      PRINTER => [],
	      INFO => '',
	      ALIAS => [],
	      AREC=> [],

	      ID => -1
	    };

      $zonedata->{$domain}=$rec;
      #print "Adding domain: $domain\n";
    }

    $rec=$zonedata->{$domain};
    @line = split;

    # check & parse records
    if ($type eq 'A') {
      die("invalid A record: $fline")
	unless (/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
      push @{$rec->{A}}, $1;
    }
    elsif ($type eq 'SOA') {
      die("dublicate SOA record: $fline")  if (length($rec->{SOA}) > 0);
      #print join(",",@line)."\n";
      die("invalid source-dname in SOA record: $fline") 
	unless ($line[0] =~ /^\S+\.$/);
      die("invalid mailbox in SOA record: $fline")
	unless ($line[1] =~ /^\S+\.$/);
      for($i=2;$i <= $#line; $i+=1) {
	die("invalid values '$line[$i]' in SOA record: $fline")
	  unless ($line[$i] =~ /^\d+$/);
      }
      die("invalid SOA record, too many fields: $fline") if ($#line > 6);
      $rec->{SOA} = join(" ",@line);
    }
    elsif ($type eq 'PTR') {
      push @{$rec->{PTR}}, $line[0];
    }
    elsif ($type eq 'CNAME') {
      $rec->{CNAME} = add_origin($line[0],$origin);
    }
    elsif ($type eq 'MX') {
      die ("invalid MX preference '$line[0]': $fline")
	unless ($line[0] =~ /^\d+$/);
      die ("invalid MX exchange-dname '$line[1]': $fline")
	unless ($line[1] =~ /^\S+$/);

      $line[1]="\L$line[1]";
      if (remove_origin($line[1],$origin) eq remove_origin($domain,$origin)) {
	#print "'$line[1] match $domain \n";
	$line[1]='$DOMAIN';
      }

      push @{$rec->{MX}}, "$line[0]" . " " . "$line[1]";
    }
    elsif ($type eq 'NS') {
      push @{$rec->{NS}}, $line[0];
    }
    elsif ($type eq 'HINFO') {
      $rec->{HINFO}[0]=$line[0];
      $rec->{HINFO}[1]=$line[1];
    }
    elsif ($type eq 'WKS') {
      shift @line; # get rid of IP 
      die ("invalid protocol in WKS '$line[0]': $fline")
	unless ("\U$line[0]" =~ /^(TCP|UDP)$/);
      push @{$rec->{WKS}}, join(" ",@line);
    }
    elsif ($type eq 'SRV') {
      die("invalid SRV record: $fline") 
	unless ($line[0]=~/^\d+$/ && $line[1]=~/^\d+$/ && $line[2]=~/^\d$+/
		&& $line[3] ne '');
      push @{$rec->{SRV}}, "$line[0] $line[1] $line[2] $line[3]";
    }
    elsif ($type eq 'TXT') {
      s/(^\s*"|"\s*$)//g;
      push @{$rec->{TXT}}, $_;
    }
    #
    # Otto's (jyu.fi's) extensions for automagic generation of DHCP/BOOTP/etc 
    # configs
    #
    elsif ($type eq 'ALIAS' || $type eq 'AREC' || 
	   $type eq 'PCTCP' || $type eq 'BOOTP') {
      # ignored...
      push(@{$rec->{ALIAS}}, $_) if ($type eq 'ALIAS');
      push(@{$rec->{AREC}}, $_) if ($type eq 'AREC');
    }
    elsif ($type =~ /MUUTA[0-9]/) {
      s/(^\s*"|"\s*$)//g;
      push (@{$rec->{MUUTA}}, $_) if ($_ ne '');
    }
    elsif ($type eq 'TYPE') {
      s/(^\s*"|"\s*$)//g;
      $rec->{TYPE} = $_;
    }
    elsif ($type eq 'INFO') {
      s/(^\s*"|"\s*$)//g;
      $rec->{INFO} = $_;
    }
    elsif ($type eq 'SERIAL') {
      s/(^\s*"|"\s*$)//g;
      $rec->{SERIAL} = $_;
    }
    elsif ($type eq 'ETHER') {
      die("Invalid ethernet address for $domain\n$fline")
	unless (/^([0-9a-f]{12})$/i);
      $rec->{ETHER} = "\U$1";
    }
    elsif ($type eq 'ETHER2') {
      s/(^\s*"|"\s*$)//g;
      $rec->{ETHER2} = $_;
    }
    elsif ($type eq 'DHCP') {
      #s/(^\s*"|"\s*$)//g;
      push (@{$rec->{DHCP}}, $_) if ($_ ne '');
    }
    elsif ($type eq 'GROUP') {
      $rec->{GROUP}=$1 if (/^(\S+)(\s|$)/);
    }
    elsif ($type eq 'ROUTER') {
      if (/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(\s+(\S+)(\s|$))?/) {
	#print "ROUTER '$1' '$2' '$4'\n";
	$rec->{ROUTER} = "$1 $2 $4";
      } else {
	#print "ROUTER: '$_'\n";
	push @{$rec->{ROUTER_DHCP}}, $_;
	push @{$rec->{DHCP}}, $_;
      }
    }
    elsif ($type eq 'PRINTER') {
      #print "PRINTER '$_'\n";
      push @{$rec->{PRINTER}}, $_;
    }
    else {
      #unrecognized record
      warn("unsupported record (ignored) '$domain':\n$fline");
    }

  }


  close($handle);
  #print "exit: $handle, $filename\n";
}


1;
# eof
