# Sauron::UtilZone.pm - BIND zone file reading/parsing routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000,2002.
# $Id$
#
package Sauron::UtilZone;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     process_zonefile
	     process_zonedns
	    );

use IO::File;
use Net::DNS;
use Sauron::Util;
use strict;

sub process_zonefile($$$$);

my $debug = 0;

# parse zone file, build hash of all domain names in zone containing
# all the RRs
#
# resoure record format:
# {<domain>|@|<blank>} [<ttl>] [<class>] <type> <rdata> [<comment>]
#
sub process_zonefile($$$$) {
  my ($filename,$origin,$zonedata,$ext_flag)=@_;

  my ($domain,$i,$c,$prev,$ttl,$class,$fline,$type);
  my ($rec,$zone_ttl);
  my (@line,@tmpline,$tmporigin,$tmp,$paren,$quote);
  my $fh = IO::File->new();

  $class='IN';
  $zone_ttl=-1;
  $ext_flag=0 unless ($ext_flag);
  $origin.="." unless ($origin =~ /\.$/);

  print "process_zonefile($filename,$origin,ZONEDATA,$ext_flag)\n" if ($debug);

  fatal("cannot read zonefile: $filename") unless (-r $filename);
  open($fh,$filename) || fatal("cannot open zonefile: $filename");

  while (<$fh>) {
    chomp;
    $fline=$_;
    next if (/^\s*$/);
    next if (/^\s*;/);

    #print "line: '$_'\n";
    $tmp=''; $quote=0; $paren=0;
    do {
      s/\s+/\ /g; s/\s+$//;

      for $i (0..length($_)-1) {
	$prev=($i > 0 ? substr($_,$i-1,1) : ' ');
	$c=substr($_,$i,1);
        $quote=($quote ? 0 : 1)	if (($c eq '"') && ($prev ne '\\'));
	unless ($quote) {
	  if ($c eq '(') { $paren++; $c=' '; }
	  elsif ($c eq ')') {
	    $paren--; $c=' ';
	    fatal("$filename($.): misordered parenthesis!\n") if ($paren < 0);
	  }
	  elsif ($c eq ';') { last; }
	}
	$tmp .= $c;
      }
      chomp ($_=<$fh>) if ($paren);
    } while($paren and not eof($fh));

    fatal("$filename($.): unterminated quoted string!\n") if ($quote);
    $_=$tmp;
    s/\s+/\ /g;
    s/\s+$//;
    #print "LINE '$_'\n";

    if (/^\$ORIGIN\s+(\S+)(\s|$)/) {
      print "\$ORIGIN: '$1'\n" if ($debug);
      $origin=add_origin($1,$origin);
      next;
    }
    if (/^\$INCLUDE\s+(\S+)(\s+(\S+))?(\s|$)/) {
      print "\$INCLUDE: '$1' '$3'\n" if ($debug);
      $tmporigin=$3;
      $tmporigin=$origin if ($3 eq '');
      process_zonefile($1,$tmporigin,$zonedata,$ext_flag);
      next;
    }
    if (/^\$TTL\s+(\S+)(\s|$)/) {
      print "\$TTL: $1\n" if ($debug);
      $tmp=$1;
      $zone_ttl = $tmp if ($tmp =~ /(\d+)/);
      next;
    }

    unless (/^(\S+)?\s+((\d+)\s+)?(([iI][nN]|[cC][sS]|[cC][hH]|[hH][sS])\s+)?(\S+)\s+(.*)\s*$/) {
      print STDERR "$filename($.): invalid line: $fline\n" if ($ext_flag < 1);
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
    warn("$filename($.): invalid domainname $domain\n")
      if (! valid_domainname($domain) && $ext_flag < 0);

    # class
	
    fatal("$filename($.):Invalid or missing RR class\n")
	unless ($class =~ /^(IN|CS|CH|HS)$/);

    # type
    unless ($type =~ /^(SOA|A|PTR|CNAME|MX|NS|TXT|HINFO|WKS|MB|MG|MD|MF|MINFO|MR|AFSDB|ISDN|RP|RT|X25|PX|SRV)$/) {
      if ($ext_flag > 0) {
	unless ($type =~ /^(DHCP|ALIAS|AREC|ROUTER|PRINTER|BOOTP|INFO|ETHER2?|GROUP|BOOTP|MUUTA[0-9]|TYPE|SERIAL|PCTCP)$/) {
	  print STDERR "$filename($.): unsupported RR type '$type'\n";
	  next;
	}
      } else {
	print STDERR "$filename($.): invalid/unsupported RR type '$type'\n";
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
      fatal("$filename($.): invalid A record: $fline")
	unless (/^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/);
      push @{$rec->{A}}, $1;
    }
    elsif ($type eq 'SOA') {
      fatal("$filename($.): dublicate SOA record: $fline")
	if (length($rec->{SOA}) > 0);
      #print join(",",@line)."\n";
      fatal("$filename($.): invalid source-dname in SOA record: $fline")
	unless ($line[0] =~ /^\S+\.$/);
      fatal("$filename($.): invalid mailbox in SOA record: $fline")
	unless ($line[1] =~ /^\S+\.$/);
      for($i=2;$i <= $#line; $i+=1) {
	fatal("$filename($.): invalid values '$line[$i]' in SOA record: $fline")
	  unless ($line[$i] =~ /^\d+$/);
      }
      fatal("$filename($.): invalid SOA record, too many fields: $fline")
	if ($#line > 6);
      $rec->{SOA} = join(" ",@line);
    }
    elsif ($type eq 'PTR') {
      push @{$rec->{PTR}}, $line[0];
    }
    elsif ($type eq 'CNAME') {
      $rec->{CNAME} = add_origin($line[0],$origin);
    }
    elsif ($type eq 'MX') {
      fatal ("$filename($.): invalid MX preference '$line[0]': $fline")
	unless ($line[0] =~ /^\d+$/);
      fatal ("$filename($.): invalid MX exchange-dname '$line[1]': $fline")
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
      fatal ("$filename($.): invalid protocol in WKS '$line[0]': $fline")
	unless ("\U$line[0]" =~ /^(TCP|UDP)$/);
      push @{$rec->{WKS}}, join(" ",@line);
    }
    elsif ($type eq 'SRV') {
      fatal("$filename($.): invalid SRV record: $fline")
	unless ($line[0]=~/^\d+$/ && $line[1]=~/^\d+$/ && $line[2]=~/^\d$+/
		&& $line[3] ne '');
      push @{$rec->{SRV}}, "$line[0] $line[1] $line[2] $line[3]";
    }
    elsif ($type eq 'TXT') {
      s/(^\s*"|"\s*$)//g;
      s/\\\"/\"/g;
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
      fatal("$filename($.): invalid ethernet address for $domain\n")
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
      warn("$filename($.): unsupported record (ignored) '$domain':\n$fline");
    }

  }

  close($fh);
}


# reads zone from DNS using zone transfer, produces simila hash as
# result as process_zone function
#
sub process_zonedns($$$$) {
    my ($zone,$data,$nameserver,$verbose) = @_;
    my (@zonedata,$rr,$domain,$type,$class,$ttl,$c,$rec,$tmp);
    my $resolver = Net::DNS::Resolver->new;
    my $ucount = 0;
    my $origin = $zone;

    $origin .= '.' unless ($origin =~ /\.$/);


    $resolver->nameservers($nameserver) if ($nameserver);
    print "Zone transfer...\n" if ($verbose);
    @zonedata = $resolver->axfr($zone);
    fatal("zone transfer failed: " . $resolver->errorstring)
	if (@zonedata < 1);

    foreach $rr (@zonedata) {
	$domain = $rr->name . '.';
	$type = $rr->type;
	$class = $rr->class;
	$ttl = $rr->ttl;

	next unless ($class eq 'IN');
	unless ($type =~ /^(SOA|A|PTR|CNAME|MX|NS|TXT|HINFO|SRV|WKS)$/) {
	    $ucount++;
	    print "Skipping: " . $rr->string . "\n" if ($verbose);
	    next;
	}

	unless ($data->{$domain}) {
	    $data->{$domain} = {
		TTL => $ttl,
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
		SRV => []
	      };
	}

	$rec = $data->{$domain};

	if ($type eq 'A') {
	    push @{$rec->{A}}, $rr->address;
	}
	elsif ($type eq 'SOA') {
	    $rec->{SOA} = join(" ",($rr->mname,$rr->rname,$rr->serial,
				    $rr->refresh,$rr->retry,
				    $rr->expire,$rr->minimum));
	}
	elsif ($type eq 'PTR') {
	    push @{$rec->{PTR}}, $rr->ptrdname;
	}
	elsif ($type eq 'CNAME') {
	    $rec->{CNAME} = $rr->cname . '.';
	}
	elsif ($type eq 'MX') {
	    $tmp = $rr->exchange . '.';
	    $tmp = '$DOMAIN'
		if (remove_origin($tmp,$origin) eq
		    remove_origin($domain,$origin));

	    push @{$rec->{MX}}, $rr->preference . " " . $tmp;
	}
	elsif ($type eq 'NS') {
	    push @{$rec->{NS}}, $rr->nsdname . '.';
	}
	elsif ($type eq 'TXT') {
	    push @{$rec->{TXT}}, $rr->txtdata;
	}
	elsif ($type eq 'WKS') {
	   # ignore... no support in Net:DNS yet...
	}
	elsif ($type eq 'HINFO') {
	    $rec->{HINFO}[0] = $rr->cpu;
	    $rec->{HINFO}[1] = $rr->os;
	}
	elsif ($type eq 'SRV') {
	    push @{$rec->{SRV}}, join(" ",($rr->priority,$rr->weight,
					   $rr->port,$rr->target . '.'));
	}
	else {
	    fatal("internal error: unsupported RR-type $type");
	}

	$c++;
    }

    print "Processed $c records (ignored $ucount records)\n"
	if ($verbose);

}


1;
# eof
