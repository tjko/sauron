# Sauron::Util.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000-2002.
# $Id$
#
package Sauron::Util;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     valid_domainname_check
	     valid_domainname
	     valid_texthandle
	     is_cidr
	     arpa2cidr
	     cidr2arpa
	     ip2int
	     int2ip
	     adjust_ip
	     remove_origin
	     add_origin
	     pwd_crypt_md5
	     pwd_crypt_unix
	     pwd_make
	     pwd_check
	     pwd_external_check
	     fatal
	     error
	     show_hash
	     check_ipmask
	     dhcpether
	     run_command
	     print_csv
	    );


use Digest::MD5;
use strict;


# returns nonzero in case given domainname is valid
sub valid_domainname_check($$) {
  my($domain,$mode)= @_;
  my($dom);

  $dom="\L$domain";

  if ($dom =~ 
      /^(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)?\d{1,3}\.in-addr\.arpa\.?$/)  {
    return 1;
  }

  if ($mode == 1) {
    # test for valid zone name
    if ($dom =~ /([^a-z0-9\-\._])/) {
      #warn("invalid character '$1' in domainname: '$domain'");
      return 0;
    }

    unless ($dom =~ /^[a-z0-9_]/) {
      #warn("domainname starts with invalid character: '$domain'");
      return 0;
    }
  }
  elsif ($mode == 2) {
    # test for valid SRV record domain name
    if ($dom =~ /([^a-z0-9\-\.\*_])/) {
      warn("invalid character '$1' in domainname: '$domain'");
      return 0;
    }

    unless ($dom =~ /^[a-z_\*]/) {
      warn("domainname starts with invalid character: '$domain'");
      return 0;
    }
    return 1;
  }
  else {
    if ($dom =~ /([^a-z0-9\-\.])/) {
      #warn("invalid character '$1' in domainname: '$domain'");
      return 0;
    }

    unless ($dom =~ /^[a-z]/) {
      #warn("domainname starts with invalid character: '$domain'");
      return 0;
    }
  }


  if ($dom =~ /([^a-z0-9])\./) {
    #warn("invalid character '$1' before dot in domainname: '$domain'");
    return 0;
  }

  return 1;
}

sub valid_domainname($) {
  my($domain) = @_;

  return valid_domainname_check($domain,0);
}

sub valid_texthandle($) {
  my($str) = @_;

  return ($str =~ /^[a-zA-Z0-9_\-]+$/ ? 1 : 0);
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
  my($i,$s,$cidr,@m);
  my($r_begin,$r_end,$range);

  # support for smaller than class-C delegations
  if ($arpa =~ /^(\d+)\-(\d+)(\..*)$/) {
      $r_begin=$1;
      $r_end=$2;
      $range=$r_end - $r_begin + 1;
      $arpa=$1 . $3;
      return '0.0.0.0/0' 
	  unless ($range==2 || $range==4 || $range==8 || $range==16 ||
		  $range==32 || $range==64 || $range==128);
      $range=int(log($range)/log(2));
  }

  return '0.0.0.0/0' unless $arpa =~ 
    /^(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)?(\d{1,3}\.)in-addr\.arpa/;
  @m = (0,$1,$2,$3,$4);

  $s=4;
  for($i=4;$i>0;$i--) {
    next if ($m[$i] eq '');
    $cidr.=$m[$i];
    $s--;
  }
  for($i=$s;$i>0;$i--) {
    $cidr.='0.';
  }
  $cidr =~ s/\.$//g;
  #print $s;
  if ($range) { 
    $s=32-$range; 
  } else { 
    $s=(32-($s*8)); 
  }

  return $cidr . "/" . $s;
}


# convert CIDR format address into in-addr.arpa format address
sub cidr2arpa($) {
  my($cidr) = @_;
  my($i,@a,$e,$arpa);

  @a=4; $e=0;
  $arpa='';

  if ($cidr =~ /^\s*(\d{1,3})(\.(\d{1,3}))?(\.(\d{1,3}))?(\.(\d{1,3}))?(\/(\d{1,2}))?\s*$/) {
    #print "1=$1 3=$3 5=$5 7=$7 9=$9\n";
    $a[0]=$1; $e=8;
    if (defined $3) { $a[1]=$3; $e=16; } else { $a[1]=0; }
    if (defined $5) { $a[2]=$5; $e=24; } else { $a[2]=0; }
    if (defined $7) { $a[3]=$7; $e=32; } else { $a[3]=0; }
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
sub pwd_crypt_md5($$) {
  my($password,$salt) = @_;
  my($ctx);

  $ctx=new Digest::MD5;
  $ctx->add("$salt$password\n");
  return "MD5:" . $salt . ":" . $ctx->hexdigest;
}

sub pwd_crypt_unix($$) {
  my($password,$salt) = @_;

  return "CRYPT:" . crypt($password,$salt);
}


# encrypts given password
sub pwd_make_md5($) {
  my($password) = @_;
  my($salt);

  $salt=int(rand(9000000)+1000000);
  return pwd_crypt_md5($password,$salt);
}

# encrypts given password
sub pwd_make_unix($) {
  my($password) = @_;
  my($salt,$smap,$sl,$i);

  $smap = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./';
  $sl = length($smap);

  $salt='';
  for $i (1..2) { $salt .= substr($smap,int(rand($sl)),1); }
  return pwd_crypt_unix($password,$salt);
}

# encrypt given password using configured method
sub pwd_make($$) {
  my($password,$mode) = @_;

  return pwd_make_unix($password) if ($mode == 1);
  return pwd_make_md5($password)
}


# check if passwords match (currently supports standard Unix crypt
# passwords and our own simple md5 based passwords)
sub pwd_check($$) {
  my($password,$pwd) = @_;
  my($salt);

  if ($pwd =~ /^CRYPT:(\S{2})(\S{11})$/) {
    $salt=$1;
    return -1 if (pwd_crypt_unix($password,$salt) ne $pwd);
    return 0;
  }

  $salt=$1;
  if ($pwd =~ /^MD5:(\S+):(\S+)$/) {
    $salt=$1;
    return -1 if (pwd_crypt_md5($password,$salt) ne $pwd);
    return 0;
  }

  return -2;
}

sub pwd_external_check($$$) {
  my($cmd,$user,$password) = @_;

  my($res);

  return 1 unless ($cmd && -x $cmd);
  return 2 unless ($user);
  return 3 unless (defined $password);

  open(OLDOUT,">&STDOUT");
  open(OLDERR,">&STDERR");
  open(STDOUT,"> /dev/null");
  open(STDERR,">&STDOUT");

  $res=-1;
  if (open(PIPE,"| $cmd")) {
    print PIPE "$user $password\n";
    close(PIPE);
    $res = $?;
  }

  close(STDOUT);
  close(STDERR);

  open(STDOUT,">&OLDOUT");
  open(STDERR,">&OLDERR");
  close(OLDOUT);
  close(OLDERR);

  return ($res >> 8);
}

# print error message and exit program
sub fatal($) {
  my($msg) = @_;
  my($prog) = $0 =~ /^.*\/(.*)$/;
  print STDERR "$prog: $msg\n";
  exit(1);
}

# print error message
sub error($) {
  my($msg) = @_;
  my($prog) = $0 =~ /^.*\/(.*)$/;
  print STDERR "$prog: $msg\n";
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


# checks for valid IP-mask and also can test if given IP is within the mask
# (dirty hack, clean up the code someday :)
#
sub check_ipmask($$) {
    my($mask,$ip) = @_;

    my($tmp,$a_1,$a_2,$a_3,$b_1,$b_2,$b_3,$c_1,$c_2,$c_3,$d_1,$d_2,$d_3);

    # print "check '$mask' '$ip'\n";
    return 0 unless ($mask =~ /^(\*|(\d{1,3})(\-\d{1,3})?)\.(\*|(\d{1,3})(\-\d{1,3})?)\.(\*|(\d{1,3})(\-\d{1,3})?)\.(\*|(\d{1,3})(\-\d{1,3})?)$/ );

    $a_1=$1; $a_2=$2; $a_3=$3;
    $b_1=$4; $b_2=$5; $b_3=$6;
    $c_1=$7; $c_2=$8; $c_3=$9;
    $d_1=$10; $d_2=$11; $d_3=$12;

    return 1 if ($ip eq '');

    return 0 unless ($ip =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);

    if ($a_1 eq '*') { $a_2=0; $a_3=255; }
    elsif ($a_3 eq '') { $a_3=$a_2; }
    else { $a_3=-$a_3; }
    # print "$1 , $a_2 - $a_3\n";
    return 0 unless ($1 >= $a_2 && $1 <= $a_3);

    if ($b_1 eq '*') { $b_2=0; $b_3=255; }
    elsif ($b_3 eq '') { $b_3=$b_2; }
    else { $b_3=-$b_3; }
    # print "$2 , $b_2 - $b_3\n";
    return 0 unless ($2 >= $b_2 && $2 <= $b_3);

    if ($c_1 eq '*') { $c_2=0; $c_3=255; }
    elsif ($c_3 eq '') { $c_3=$c_2; }
    else { $c_3=-$c_3; }
    # print "$3 , $c_2 - $c_3\n";
    return 0 unless ($3 >= $c_2 && $3 <= $c_3);

    if ($d_1 eq '*') { $d_2=0; $d_3=255; }
    elsif ($d_3 eq '') { $d_3=$d_2; }
    else { $d_3=-$d_3; }
    # print "$4 , $d_2 - $d_3\n";
    return 0 unless ($4 >= $d_2 && $4 <= $d_3);

    return 1;
}


# convert ethernet address to format suitable for dhcpd.conf
sub dhcpether($) {
  my ($e) = @_;

  $e="\L$e";
  if ($e =~ /(..)(..)(..)(..)(..)(..)/) {
    return "$1:$2:$3:$4:$5:$6";
  }

  return "00:00:00:00:00:00";
}


# custom "system" command with timeout option
sub run_command($$$)
{
  my ($cmd,$args,$timeout) = @_;
  my ($err,$pid);
  my $stat = 0;

  return -1 unless ($cmd && -x $cmd);
  return -2 unless ($timeout > 0);

  if ($pid = fork()) {
    # parent...
    local $SIG{ALRM} = sub { $stat=1; kill(15,$pid); };
    alarm($timeout);
    waitpid($pid,0);
    $err = $?;
    alarm(0);
  } else {
    # child...
    exec($cmd,@{$args});
  }

  $err = 14 if ($stat);
  return $err;
}


sub print_csv($$)
{
  my($lst,$mode) = @_;
  my($i,$val,$line,$quote);

  for $i (0..$#{$lst}) {
    $val = $$lst[$i];
    $quote = 0;

    if ($mode==1) {
      $quote=1;
    } else {
      $quote = 1 unless ($val =~ /^[\+\-]{0,1}\d+(\.\d*)?$/);
    }

    if ($quote) {
      $val =~ s/\"/""/g;
      $val = "\"$val\"";
    }
    $line .= "," if ($line);
    $line .= $val;
  }

  return $line;
}

1;
# eof
