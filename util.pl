# util.pl
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000.
# $Id$
#
use Digest::MD5;
#use strict;

# returns nonzero in case given domainname is valid
sub valid_domainname($) {
  my($domain)= @_;
  my($dom);

  $dom="\L$domain";

  if ($dom =~ 
      /^(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)?\d{1,3}\.in-addr\.arpa\.?$/)  {
    return 1;
  }
  
  if ($dom =~ /([^a-z0-9\-\.])/) {
    #warn("invalid character '$1' in domainname: '$domain'");
    return 0;
  }

  unless ($dom =~ /^[a-z]/) {
    #warn("domainname starts with invalid character: '$domain'");
    return 0;
  }

  if ($dom =~ /([^a-z0-9])\./) {
    #warn("invalid character '$1' before dot in domainname: '$domain'");
    return 0;
  }

  return 1;
}

# check if parameter contains a valid CIDR...returns 0 if not.
sub is_cidr($) {
  my($s) = @_;
  if ( $s =~ /^\s*((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})|(\d{1,3}(\.\d{1,3}(\.\d{1,3}(\.\d{1,3})?)?)?\/\d{1,3}))\s*$/ ) {
    return $1;
  }
  return 0;
}

# convert in-addr.arpa format address into CIDR format address
sub arpa2cidr($) {
  my($arpa) = @_;
  my($i,$s,$cidr);
  
  return '0.0.0.0/0' unless $arpa =~ 
    /^(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)in-addr\.arpa/;
  #print "'$4' '$3' '$2' '$1'\n";

  $s=4;
  for($i=4;$i>0;$i--) {
    next if (${$i} eq '');
    $cidr.=${$i};
    $s--;
  }
  for($i=$s;$i>0;$i--) {
    $cidr.='0.';
  }
  $cidr =~ s/\.$//g;
  #print $s;
  $s=(32-($s*8));
  return $cidr . "/" . $s;
}


# convert CIDR format address into in-addr.arpa format address
sub cidr2arpa($) {
  my($cidr) = @_;
  my($i,@a,$e,$arpa);

  @a=4;
  $arpa='';

  if ($cidr =~ /^\s*(\d{1,3})(\.(\d{1,3}))?(\.(\d{1,3}))?(\.(\d{1,3}))?(\/(\d{1,2}))?\s*$/) {
    #print "1=$1 3=$3 5=$5 7=$7 9=$9\n";
    $a[0]=$1; $e=8;
    if ($3) { $a[1]=$3; $e=16; } else { $a[1]=0; }
    if ($5) { $a[2]=$5; $e=24; } else { $a[2]=0; }
    if ($7) { $a[3]=$7; $e=32; } else { $a[3]=0; }
    if ($9) { $e=$9; }
  }
  else {
    $a[0]=0; $a[1]=0; $a[2]=0; $a[3]=0; $e=0;
  }

  $e=0 if ($e < 0);
  $e=32 if ($e > 32);
  $e=$e >> 3;

  for($i=$e-1;$i >= 0;$i--) {
    $arpa.="$a[$i].";
  }
  $arpa.='0.' if ($e == 0);
  $arpa.="in-addr.arpa";

  return $arpa;
}


sub ip2int($) {
  my($ip)=@_;
  my($a,$b,$c,$d);

  return -1 unless ($ip =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)(\/\d+)?/);
  $a=($1) & 0xFF;
  $b=($2) & 0xFF;
  $c=($3) & 0xFF;
  $d=($4) & 0xFF;
  return ($a<<24)+($b<<16)+($c<<8)+$d;
}

sub int2ip($) {
  my($i)=@_;
  my($a,$b,$c,$d);

  return '0.0.0.0' if ($i < 0);
  $a=($i>>24) & 0xFF;
  $b=($i>>16) & 0xFF;
  $c=($i>>8) & 0xFF;
  $d=($i) & 0xFF;
  return "$a.$b.$c.$d";
}

sub adjust_ip($$) {
  my($ip,$step)=@_;
  my($i);

  $i = ip2int($ip);
  return '' if ($i < 0);
  $i += $step;
  return int2ip($i);
}

# remove_origin($domain,$origin) - strip origin from domain
sub remove_origin($$) {
  my($domain,$origin) = @_;

  $domain="\L$domain";
  $origin="\L$origin";
  $origin =~ s/\./\\\./g;
  #print "before: $domain $origin\n";
  $domain =~ s/\.$origin$//g;
  #print "after: $domain\n";

  return $domain;
}


# add_origin($domain,$origin) - add origin into domain
sub add_origin($$) {
  my($domain,$origin) = @_;

  $domain="\L$domain";
  $origin="\L$origin";
  if ($domain eq '@') {  $domain=$origin; }
  elsif (! ($domain =~ /\.$/)) { $domain.=".$origin"; }
  return $domain;
}


# encrypts given pasword using salt... (MD5 based)
sub pwd_crypt($$) {
  my($password,$salt) = @_;
  my($ctx);

  $ctx=new Digest::MD5;
  $ctx->add("$salt$password\n");
  return "MD5:" . $salt . ":" . $ctx->hexdigest;
}

# encrypts given password 
sub pwd_make($) {
  my($password) = @_;
  my($salt);

  $salt=int(rand(900000)+100000);
  return pwd_crypt($password,$salt);
}

# check if passwords match
sub pwd_check($$) {
  my($password,$pwd) = @_;
  my($salt,$t);

  $salt=$1 if ($pwd =~ /^MD5:(\S+):(\S+)$/);
  return -2 if ($salt eq '');
  $t=pwd_crypt($password,$salt);
  return -1 if ($t ne $pwd);
  return 0;
}

# print error message and exit program
sub fatal($) {
  my ($msg) = @_;
  print STDERR "$0: $msg\n";
  exit(1);
}

# show hash in HTML format
sub show_hash($) {
  my($rec) = @_;
  my($key);

  unless (ref($rec) eq 'HASH') {
    print "<P>Parameter is not a HASH!\n";
    return;
  }

  print "<TABLE border=\"3\"><TR><TH>key</TH><TH>value</TH></TR>";
  foreach $key (keys %{$rec}) {
    print "<TR><TD>$key</TD><TD>" . $$rec{$key} . "</TD></TR>";
  }
  print "</TABLE>";
}

# eof
