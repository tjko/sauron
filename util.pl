# util.pl
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000.
# $Id$
#
use Digest::MD5;

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
  if ( $s =~ /((\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})|(\d{1,3}(\.\d{1,3}(\.\d{1,3}(\.\d{1,3})?)?)?\/\d{1,3}))/ ) {
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
    next if ($$i eq '');
    $cidr.=$$i;
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


# eof
