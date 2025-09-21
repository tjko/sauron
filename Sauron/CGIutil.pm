# Sauron::CGIutil.pm  --  generic CGI stuff
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2001-2003,2005.
# $Id:$
#
package Sauron::CGIutil;
require Exporter;
use CGI qw/:standard/;
use Time::Local;
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Net::IP qw(:PROC);
# use Data::Dumper;

use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     cgi_util_set_zone
	     cgi_util_set_server
	     valid_safe_string

	     form_check_field
	     form_get_defaults
	     form_check_form
	     form_magic

	     display_form
	     display_dialog
	     display_list

	     alert1
	     alert2
	     html_error
	     html_error2
	    );


my($CGI_UTIL_zoneid,$CGI_UTIL_zone);
my($CGI_UTIL_serverid,$CGI_UTIL_server);

my %aml_type_hash = (0=>'CIDR',1=>'ACL',2=>'Key');
our $inetFamily4 = 0;
our $inetFamily6 = 0;
our $inetNet = undef;
our $formduid = undef;
our $zonename;

sub cgi_util_set_zone($$) {
  my ($id,$name) = @_;
  $CGI_UTIL_zoneid = $id;
  $CGI_UTIL_zone = $name;
}

sub cgi_util_set_server($$) {
  my ($id,$name) = @_;
  $CGI_UTIL_serverid = $id;
  $CGI_UTIL_server = $name;
}


sub valid_safe_string($$) {
    my($str,$maxlen) = @_;
    my($i,$c);

    return 0 if (($maxlen > 0) && (length($str) > $maxlen));

    for $i (1..length($str)) {
        $c = ord(substr($str,$i-1,1));
        return 0 if ($c < 32);
        return 0 if ($c >= 254);
    }

    return 1;
}

sub chr_check_field($$$) {
  my($field,$val,$groups) = @_;
  my($i,$g,$rec,@grp);

  return '' unless ($val);
  @grp = split(',',$$groups);
  return '' unless (defined($main::SAURON_CHR));
  if ($main::SAURON_CHR->{$CGI_UTIL_server}) {
    $rec = $main::SAURON_CHR->{$CGI_UTIL_server}->{$field};
    return '' unless ($rec);
    for $i (0..$#{$rec}) {
      foreach $g (@grp) {
	if ($g =~ /$$rec[$i][0]/) {
	  return ($$rec[$i][2] ? $$rec[$i][2] :
		  "Invalid value for this field ($$rec[$i][1])")
	    unless ($val =~ /$$rec[$i][1]/);
	}
      }
    }
  }
  return '';
}

# Length of host name as a FQDN must not exceed <limit> characters.
# Returns error message or empty string.
sub domainname_max_length($) { # TVu 2020-06-01
    my ($host) = @_;
    my $limit = 253;

    return 0 if (!$zonename);
    unless ($host =~ /\.$/) { $host .= ".$zonename"; }
    my $len = length($host);
    return $len <= $limit ? 0 : 'Domain name is too long by ' .
	($len - $limit) . ' character' . ($len - $limit > 1 ? 's' : '');
}

#####################################################################
# form_check_field($field,$value,$n)
#
# checks if given field (in a form) contains valid data
#
sub form_check_field($$$) {
  my($field,$value,$n) = @_;
  my($type,$empty,$t,$tmp1,$tmp2,$linelen);


  if ($n > 0) {
    $empty=${$field->{empty}}[$n-1];
    $type=${$field->{type}}[$n-1];
    $linelen=${$field->{linelen}}[$n-1];
  }
  else {
    $empty=$field->{empty};
    $type=$field->{type};
    $linelen=$field->{linelen};
  }

  if ($type ne 'duid') {
      unless ($empty == 1) {
        return 'Empty field not allowed!' if ($value =~ /^\s*$/);
      } else {
        return '' if ($value =~ /^\s*$/);
      }
  }

  if ($type eq 'fqdn' || $type eq 'domain') {
# Conditionally allow %{id} in domain name; this will be replaced later.
# Length of id can't be known - assume up to millions of hosts. TVu 2020-06-01
    my $tvalue = $value;
    if ($field->{defhost}) { $tvalue =~ s/%\{id\}/1234567/; }
# Check that domain name or fqdn is not too long. TVu 2020-06-01
    $tmp1 = domainname_max_length($tvalue);
    return $tmp1 if ($tmp1);
    if ($type eq 'domain') {
	return 'Valid domain name required!' unless (valid_domainname($tvalue));
    } else {
	return 'FQDN required!'
	    unless (valid_domainname($value) && $value=~/\.$/ ||
		    $field->{'dot'} && $value eq '.'); # Allow a single dot to superuser. TVu 2020-08-11
    }
  } elsif ($type eq 'zonename') {
    return 'valid zone name required!'
      unless (valid_domainname_check($value,1));
  } elsif ($type eq 'srvname') {
    return 'valid SRV name required!'
      unless (valid_domainname_check($value,2));
  } elsif ($type eq 'path') {
    return 'valid pathname required!'
      unless ($value =~ /^(|\S+\/)$/);
  } elsif ($type =~ /ip[46]?/) {
    my $ipversion = ip_get_version($value);
     return 'IPv4 address required!' if $type eq 'ip4' and $ipversion == 6;
     return 'IPv6 address required!' if $type eq 'ip6' and $ipversion == 4;

      if ($inetNet eq 'MANUAL' || !$inetNet ) {
        $inetFamily4 |= ($ipversion == 4 ? 1 : 0);
        $inetFamily6 |= ($ipversion == 6 ? 1 : 0);
      }

    return 'valid IP address required!' unless is_cidr($value);
  } elsif ($type eq 'cidr') {
    return 'valid CIDR (IP) required!' unless (is_cidr($value));
  } elsif ($type eq 'text') {
    return '';
  } elsif ($type eq 'email') {
    return 'valid email address required!'
      unless (($tmp1,$tmp2)=($value =~ /^(\S+)\@(\S+)$/));
    return 'invalid domain part in email address!'
      unless (valid_domainname($tmp2));
    return 'invalid email address!'
      unless ($tmp1 =~ /^[A-Za-z0-9_\.\+\-]+$/);
  } elsif ($type eq 'passwd') {
    return '';
  } elsif ($type eq 'enum') {
    return '';
  } elsif ($type eq 'mx') {
# Check that domain name is not too long. TVu 2020-06-01
    $tmp1 = domainname_max_length($value);
    return $tmp1 if ($tmp1);
    return 'valid domain or "$DOMAIN" required!'
      unless(($value eq '$DOMAIN') || valid_domainname($value));
  } elsif ($type eq 'int' || $type eq 'priority') {
    return 'integer required!' unless ($value =~ /^(-?\d+)$/);
    $t=$1;
    if ($type eq 'priority') {
      return 'priority (0..n) required!' unless ($t >= 0);
    }
    if (defined $field->{'limits'} && # TVu 2021-02-11
	($value < ${$field->{'limits'}}[0] || $value > ${$field->{'limits'}}[1])) {
	return 'Value outside limits ' .
	    "(${$field->{'limits'}}[0] .. ${$field->{'limits'}}[1])";
    }
  } elsif ($type eq 'port') {
    return 'port number required!' unless ($value > 0 && $value < 65535);
  } elsif ($type eq 'bool') {
    return 'boolean value required!' unless ($value =~ /^(t|f)$/);
  } elsif ($type eq 'mac') {
    return 'MAC address required!' if ($value !~ /^([0-9A-Fa-f]{12})$/ and $inetFamily4);
  } elsif ($type eq 'duid') {
    $formduid = $value if $value !~ /^\s*$/;
    return 'Empty field not allowed (if IPv6 address is entered)!'
	if $value =~ /^\s*$/ and !$empty and ((!$inetFamily4 and !$inetFamily6) || $inetFamily6);
    return 'Empty DUID required! (IPv6 address not set)' if $value !~ /^\s*$/ and $inetFamily4 and !$inetFamily6;
    return 'Valid DUID required!' if ($value !~ /^([0-9A-Fa-f]{24,40})$/ and $inetFamily6 and !$empty);
  } elsif ($type eq 'iaid') {
    return 'Empty IAID required! (IPv6 address not set)' if $value !~ /^\s*$/ and !$inetFamily6;
    return 'IAID can\'t be used without DUID' if $value !~ /^\s*$/ and $inetFamily6 and !$formduid;
    return 'Valid IAID required!' if !(($value > 0) and ($value < (2**32))) and $inetFamily6;
  } elsif ($type eq 'printer_class') {
    return 'Valid printer class name required!'
      unless ($value =~ /^\@[a-zA-Z]+$/);
  } elsif ($type eq 'hinfo') {
    return 'Valid HINFO required!'
      unless ($value =~ /^([A-Z0-9-\+\/]+)$/);
  } elsif ($type eq 'textarea') {
    return '';

  } elsif ($type eq 'area') { # Textarea (check length of each line) 2020-07-30 TVu
# Some sources say that line breaks in textarea depend on the client.
      $value =~ s/\r(?=\n)//gms; # cr/nl => nl (for Windows client)
      $value =~ s/\r/\n/gms; # cr => nl (for Mac client)
      my @cust = split("\n", $value);
      my $tx = '';
      for my $ind1 (0..$#cust) {
	  $tx .= length($cust[$ind1]) . " characters on line " . ($ind1 + 1) . ': "' .
	      substr($cust[$ind1], 0, 30) . " ...\" &mdash; limit is $linelen<br>"
	      if (length($cust[$ind1]) > $linelen);
      }
      return $tx;

  } elsif ($type eq 'cust_entr') { # Textarea (check length) 12 Apr 2017 TVu
      my @cust = @{$value};
      my $tx = '';
      for my $ind1 (0..$#cust) {
	  $tx .= "<br>More than $field->{linelen} characters on line " . ($ind1 + 1)
	      if (length($cust[$ind1]) > $field->{linelen});
      }
      return $tx;
  } elsif ($type eq 'texthandle') {
    return 'Valid handle string required!'
      unless ($value =~ /^[a-zA-Z0-9_\-\.]+$/);
    return '';
  } elsif ($type eq 'expiration') {
    return 'Invalid expiration date specification'
      unless ($value =~ /^(\d{1,2}[\-\.\/]\d{1,2}[\-\.\/]\d{4}|\+\d+[dmy])$/);
    return '';
  } elsif ($type eq 'daterange') {
    return 'Invalid date range specification'
      unless ($value =~ /^\s*(\d{8})?-(\d{8})?\s*$/);
    return 'Invalid (empty) date range' unless ($value =~ /\d+/);
    return '';
  } else {
    return "unknown typecheck for form_check_field: $type !";
  }

  return '';
}


####################################################################
# form_get_defaults($form)
#
# initializes unset form properties to default valuse
#
sub form_get_defaults($) {
  my($form) = @_;

  return unless ($form);
  $form->{tbl_bgcolor}='#ccccff' unless ($form->{tbl_bgcolor});
  $form->{bgcolor}="#eeeebf" unless ($form->{bgcolor});
  $form->{heading_bg}="#aaaaff" unless ($form->{heading_bg});
  $form->{ro_color}="#646464" unless ($form->{ro_color});
  $form->{border}=0 unless ($form->{border});
  $form->{width}="99%" unless ($form->{width});
  $form->{nwidth}="30%" unless ($form->{nwidth});
}


#####################################################################
# form_check_form($prefix,$data,$form)
#
# checks if form contains valid data and updates 'data' hash
#
sub form_check_form($$$) {
  my($prefix,$data,$form) = @_;
  my($formdata,$i,$j,$k,$type,$p,$p2,$tag,$list,$id,$ind,$f,$new,$tmp,$val,$e);
  my($rec);

# If nothing else has been defined (attribute 'whitesp'), all whitespace except newlines
# is removed. Other options: If attribute 'whitesp' (a string) contains (case sensitive,
# processed in this order, any combination is allowed but not all of them make sense):
# W: Non-space Whitespace charaters are not converted to spaces
# A: All whitespace is retained (skips the rest; does not imply W)
# L: Leading whitespace is removed
# E: Embedded whitespace is removed
# C: Embedded whitespace is Compressed into a single space
# T: Trailing whitespace is removed
# N: Normalization, same as CT
# P: Pack, same as LCT (this is by far the most common option)
# Example: CT changes all non-space whitespace into spaces (since there was no W),
# compresses embedded consequtive spaces into a single space and removes trailing
# spaces, but keeps leading spaces like this: "  foo\t  bar  " => "  foo bar"
# Example: AW = make no changes (same as W alone but marginally faster)
  sub remove_whitespace($$) {
      my ($val, $whitesp) = @_;

# Return original value if whitespace removal is not enabled.
      if (!$main::SAURON_REMOVE_WHITESPACE) { return $val; }

# Multi-line strings are processed one line at a time.
# Seems that some things just don't work otherwise.
      if ($val =~ /\n/) {
	  my @arr = split(/\n/, $val);
	  for my $ind1 (0..$#arr) {
	      $arr[$ind1] = remove_whitespace($arr[$ind1], $whitesp);
	  }
	  return join("\n", @arr);
      }

      if (!$whitesp) {
	  $val =~ s/\s+//g; # Remove all whitespace.
      } else {
	  if ($whitesp !~ /W/) {
	      $val =~ s/\s/ /g; # Turn all non-space whitespace into spaces.
	  }
	  if ($whitesp !~ /A/) {
	      if ($whitesp =~ /[LP]/) {
		  $val =~ s/^\s+//g; # Remove leading whitespace.
	      }
	      if ($whitesp =~ /E/) {
# **		  $val =~ s/(\S)\s+(\S)/$1$2/g; # Remove embedded whitespace.
		  $val =~ s/(\S)\s+(?=\S)/$1/g; # Remove embedded whitespace.
	      }
	      if ($whitesp =~ /[CNP]/) {
# **		  $val =~ s/(\S)\s+(\S)/$1 $2/g; # Compress embedded whitespace.
		  $val =~ s/(\S)\s+(?=\S)/$1 /g; # Compress embedded whitespace.
	      }
	      if ($whitesp =~ /[TNP]/) {
		  $val =~ s/\s+$//g; # Remove trailing whitespace.
	      }
	  }
      }
      return $val;
  }

  $formdata=$form->{data};
  $zonename = $form->{'zonename'} || ''; # TVu 2020-06-01

# This is needed to allow wildcards when adding a CNAME alias. If %new_alias_form
# and field type is CNAME alias, make the same setting as if the data had come
# from the database (as it appears when editing a CNAME alias). TVu 2020-06-11
  if ($form->{'new_alias'} and		# %new_alias_form
      param($prefix . '_type') == 4) {	# CNAME alias.
      $data->{'cname_alias'} = 1;
  }

# Make note if this is a Static alias. 2020-12-17 TVu
    my @names = multi_param(); # Names of parameters.
    foreach my $var (@names) {
	if ($var eq $prefix . '_static_alias') {
	    $data->{'static_alias'} = 1;
	    last;
	}
    }

  for $i (0..$#{$formdata}) {

    $rec=$$formdata[$i];
    $type=$rec->{ftype};
    $tag=$rec->{tag};
    $p=$prefix."_".$tag;

    if ($rec->{restricted}) {
	next unless ($rec->{restricted} eq $form->{mode});
    }
    if ($rec->{iff}) {
      $val=param($prefix."_".${$rec->{iff}}[0]);
      $e=${$rec->{iff}}[1];
      next unless ($val =~ /^($e)$/);
    }
    if ($rec->{iff2}) {
      $val=param($prefix."_".${$rec->{iff2}}[0]);
      $e=${$rec->{iff2}}[1];
      next unless ($val =~ /^($e)$/);
    }

    $val=param($p);
    $val="\L$val" if ($rec->{conv} eq 'L');
    $val="\U$val" if ($rec->{conv} eq 'U');

# Remove unnecessary whitespace from individual input fields.
    if (!($type == 2 || $type==5 || $type==11 || $type==12 || $type == 13
	  || ($type==8 && $rec->{arec}))) {
	$val = remove_whitespace($val, $rec->{whitesp});
	param($p, $val);
    }

    #print "<br>check $p,$type";

#   if ($type == 1) {
    if ($type == 1 || $tag eq 'cname_txt' && $data->{'static_alias'}) { # 2020-12-17 TVu

      if ($rec->{type} eq 'mac' or $rec->{type} eq 'duid' or $rec->{type} eq "iaid") {
	$val="\U$val";
	$val =~ s/[\s:\-\.]//g;

    #IAID in HEX will be converted to DEC
	$val = hex($val) if $rec->{type} eq "iaid" and ($val !~ /^\d+$/ and $val ne "");
      } elsif ($rec->{type} eq 'textarea') {
	#$val =~ s/\r//g;
	#$val =~ s/\n/\\n/g;
	#print "textarea:<BR><PRE>",$val,"</PRE><BR>END.";
      }
      if ($form->{defhost} && $rec->{type} eq 'domain') {
	  $rec->{defhost} = 1;
      }

# Allow *. at the beginning of domain name when adding or editing Static or CNAME alias.
# Remove *. for the duration of the format check. TVu 2020-06-11 2020-07-16
      my $wild = 0;
      if ($rec->{'tag'} eq 'domain' and $rec->{'type'} eq 'domain' and
	  ($data->{'cname_alias'} or $data->{'static_alias'}) and
	  $val =~ /^\*\./) {
	  $val =~ s/^\*\.//;
	  $wild = 1;
      }

      #print "<br>check $p ",param($p);
      return 1 if (form_check_field($rec,$val,0) ne '');

      $val = '*.' . $val if ($wild); # Restore value. TVu 2020-06-11

      if ($rec->{chr} == 1) {
	return 1 if (chr_check_field($rec->{tag},$val,$form->{chr_group})
		     ne '');
      }
#     print p,"$p changed! '",$data->{$tag},"' '",param($p),"'\n" if ($data->{$tag} ne param($p));
      if ($rec->{type} eq 'expiration') {
        if ($val =~ /^\+(\d+)d/) {
	  $val=time()+int($1 * 86400);
	} elsif ($val =~ /^\+(\d+)m/) {
	  $val=time()+int($1 * 86400*30);
	} elsif ($val =~ /^\+(\d+)y/) {
	  $val=time()+int($1 * 86400*365);
	} elsif ($val =~ /^(\d{1,2})[\-\.\/](\d{1,2})[\-\.\/](\d{4})/) {
	  $val=timelocal(0,0,0,$1,$2-1,$3-1900);
	} else {
	  $val=0;
	}
      }
      $data->{$tag}=$val;
    }
    elsif ($type == 101) {
      $tmp=param($p);
      $tmp=param($p."_l") if ($tmp eq '');
      return 101 if (form_check_field($rec,$tmp,0) ne '');
      $data->{$tag}=$tmp;
    }
    elsif  ($type == 2 || $type==5 || $type==11 || $type==12
	    || ($type==8 && $rec->{arec})) {
      $f=$rec->{fields};
      $f=1 if ($type==8 || $type==11);
      $f=3 if ($type==5);
      $f=6 if ($type==12);
      $rec->{type}=['ip','text','text'] if ($type==5);
      $rec->{type}=['int','cidr','int','int','int','text'] if ($type==12);
      $rec->{empty}=[0,1,1] if ($type==5);
      $rec->{empty}=[0,1,0,0,0,1] if ($type==12);
      $a=param($p."_count");
      $a=0 unless ($a > 0);
      for $j (1..$a) {
	next if ($type==8 || $type==11); # AREC aliases and subgroups need no format check or whitespace removal.
	next if (param($p."_".$j."_del") eq 'on'); # skip if 'delete' checked
	for $k (1..$f) {
# Remove unnecessary whitespace from indexed input fields.
# **	    if ($rec->{rows}
	    param($p."_".$j."_".$k,
		  remove_whitespace(param($p."_".$j."_".$k),
				    $rec->{'whitesp'}[$k-1] || ''));
	    return 2
		if (form_check_field($rec,param($p."_".$j."_".$k),$k) ne '');
	}
      }

      # if we get this far, check what records we need to add/update/delete
      $list=$data->{$tag};
      for $j (1..$a) {
	$p2=$p."_".$j;
	$id=param($p2."_id");
	if ($id) {
	  $ind=-1;
	  for $k (0..$#{$list}) {
	    if ($$list[$k][0] eq $id) { $ind=$k; last; }
	  }
	} else { $ind=-1; }
	#print p,"foo $p2 id=$id ind=$ind";

	if (param($p2."_del") eq 'on') {
	  if ($ind >= 0) {
	    $$list[$ind][$f+1]=-1;
	    #print p,"$p2 delete record";
	  }
	} else {
	  unless ($ind > 0) {
	    #print p,"$p2 add new record";
	    $new=[];
	    $$new[$f+1]=2;
	    for $k (1..$f) {
	      $tmp=param($p2."_".$k);
	      $tmp=($tmp eq 'on' ? 't':'f') if ($type==5 && $k>1);
	      $$new[$k]=$tmp;
	    }
	    push @{$list}, $new;
	  } else {
	    for $k (1..$f) {
	      if (param($p2."_".$k) ne $$list[$ind][$k]) {
		$$list[$ind][$f+1]=1;
		$tmp=param($p2."_".$k);
		$tmp=($tmp eq 'on' ? 't':'f') if ($type==5 && $k>1);
		$$list[$ind][$k]=$tmp;
		#print p,"$p2 modified record (field $k)";
	      }
	    }
	  }
	}
      }
    }
    elsif ($type == 3) {
      next if ($rec->{type} eq 'list');
      return 3 unless (${$rec->{enum}}{scalar(param($p))});
      $data->{$tag}=param($p);
      if ($rec->{tag} eq 'net') {
        $inetNet = param($p);
        if ($inetNet ne 'MANUAL') {
            $inetNet =~ s/\/(\d+){1,3}//g;
            $inetFamily4 = (ip_get_version($inetNet) == 4 ? 1 : 0);
            $inetFamily6 = (ip_get_version($inetNet) == 6 ? 1 : 0);
        }
      }
    }
    elsif ($type == 6 || $type == 7 || $type == 10) {
      return 6 unless (param($p) =~ /^-?\d+$/);
      $data->{$tag}=param($p);
    }
    elsif ($type == 13) { # Textarea (check input) 12 Apr 2017 TVu
# Some sources say that line breaks in textarea depend on the client.
	$val =~ s/\r(?=\n)//gms; # cr/nl => nl (for Windows client)
	$val =~ s/\r/\n/gms; # cr => nl (for Mac client)
	my @val_arr = split(/\n/, $val);
	my @val_arr2;
	for my $ind1 (0..$#val_arr) {
# Remove unnecessary whitespace from each line of textarea.
	    $val_arr[$ind1] = remove_whitespace($val_arr[$ind1], $rec->{whitesp});
	    @{$val_arr2[$ind1]} = (0, $val_arr[$ind1]);
	}
	@val_arr = split(/\n/, join("\n", @val_arr));
	unshift(@val_arr2, "-\n-");
	$data->{$tag} = \@val_arr2;
	$data->{$tag . '_id'} = param($p . '_id');
	param($p, join("\n", @val_arr));
	param($p . '_id', param($p . '_id'));
	return 13 if (form_check_field($rec, \@val_arr, 0));
    }
  }
  return 0;
}



#####################################################################
# form_magic($prefix,$data,$form)
#
# generates HTML form
#
sub form_magic($$$) {
  my($prefix,$data,$form) = @_;
  my($i,$j,$k,$n,$key,$rec,$a,$formdata,$h_bg,$e_str,$p1,$p2,$val,$e,$enum);
  my($values,$ip,$t,@lst,%lsth,%tmpl_rec,$maxlen,$len,@q,$tmp,$def_info,$id);
  my($invalid_host,$unknown_host,%host,$tmpd,$tmpm,$tmpy,$no_aster);


  form_get_defaults($form);
  $formdata=$form->{data};
  $zonename = $form->{'zonename'} || ''; # TVu 2020-06-01
  $h_bg=$form->{heading_bg};

  # CGI_UTIL_ variables will go away eventually...temporary hack until then
  my $serverid = ($form->{serverid} > 0 ?
		  $form->{serverid} : $CGI_UTIL_serverid);
  my $zoneid = ($form->{zoneid} > 0 ?
		$form->{zoneid} : $CGI_UTIL_zoneid);


    param($prefix . '_cname_alias', 1) if ($data->{'cname_alias'}); # 2020-12-17 TVu
    param($prefix . '_static_alias', 1) if ($data->{'static_alias'}); # 2020-12-17 TVu
    param($prefix . '_cname_txt', $data->{'cname_txt'}) if ($data->{'cname_txt'});

  # initialize fields
  unless (param($prefix . "_re_edit") eq '1' || ! $data) {

    for $i (0..$#{$formdata}) {
      $rec=$$formdata[$i];
      $val=$data->{$rec->{tag}};
      $val="\L$val" if ($rec->{conv} eq 'L');
      $val="\U$val" if ($rec->{conv} eq 'U');
      $val=~ s/\s+$//;
      $p1=$prefix."_".$rec->{tag};
#      if ($val eq '' && $rec->{default}) {
#	$val=$rec->{default};
#      }

      if ($rec->{ftype} == 1 || $rec->{ftype} == 101) {

	$val =~ s/\/32$// if ($rec->{type} eq 'ip');
	$val =~ s/\/128$// if ($rec->{type} eq 'ip'); # For IPv6.
        if ($rec->{type} eq 'expiration') {
	  if ($val > 0) {
	    ($tmpd,$tmpm,$tmpy)=(localtime($val))[3,4,5];
	    $tmpm++; $tmpy+=1900;
	    $val="$tmpd-$tmpm-$tmpy";
	  } else {
	    $val='';
	  }
	}
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 2 || $rec->{ftype} == 8 ||
	     $rec->{ftype} == 11 || $rec->{ftype} == 12) {
	$a=$data->{$rec->{tag}};
	$rec->{fields}=6 if ($rec->{ftype}==12);
	#param($p1."_serverid",$$a[0][1]) if ($rec->{ftype} == 12);

	for $j (1..$#{$a}) {
	  param($p1."_".$j."_id",$$a[$j][0]);
	  for $k (1..$rec->{fields}) {
	    $val=$$a[$j][$k];
	    $val =~ s/\/32$// if ($rec->{type}[$k-1] eq 'ip');
	    $val =~ s/\/128$// if ($rec->{type}[$k-1] eq 'ip');
	    param($p1."_".$j."_".$k,$val);
	  }
	}
	param($p1."_count",($#{$a} < 0 ? 0 : $#{$a}));
      }
      elsif ($rec->{ftype} == 0 || $rec->{ftype} == 9) {
	# do nothing...
      }
      elsif ($rec->{ftype} == 3) {
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 4) {
	#$val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 5) {
	$rec->{fields}=3;
	$a=$data->{$rec->{tag}};
	for $j (1..$#{$a}) {
	  param($p1."_".$j."_id",$$a[$j][0]);
	  $ip=$$a[$j][1];
	  $ip =~ s/\/\d{1,3}$//g;
	  param($p1."_".$j."_1",$ip);
	  $t=''; $t='on' if ($$a[$j][2] eq 't' || $$a[$j][2] == 1);
	  param($p1."_".$j."_2",$t);
	  $t=''; $t='on' if ($$a[$j][3] eq 't' || $$a[$j][3] == 1);
	  param($p1."_".$j."_3",$t);
	  #param($p1."_".$j."_4",$$a[$j][4]);
	}
	param($p1."_count",$#{$a});
      }
      elsif ($rec->{ftype} == 6 || $rec->{ftype} == 7 || $rec->{ftype} == 10) {
	param($p1,$val);
      }
      else {
	error("internal error (form_magic):". $rec->{ftype});
      }
    }
  }

  #generate form fields
  print hidden($prefix."_re_edit",1),"\n<TABLE ";
  print "BGCOLOR=\"" . $form->{tbl_bgcolor} . "\" " if ($form->{tbl_bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
# netscape sekoilee muuten no-frame modessa...
#  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . ($form->{border}>0?$form->{border}:0) . "\" ";
  print " cellspacing=\"1\" cellpadding=\"1\">\n";

#  print Dumper(\%{$data});

  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $p1=$prefix."_".$rec->{tag};

    if ($rec->{hidden}) {
      print hidden($p1,scalar(param($p1)));
      next;
    }
    if ($rec->{restricted}) {
	next unless ($rec->{restricted} eq $form->{mode});
    }
    if ($rec->{iff}) {
      $val=param($prefix."_".${$rec->{iff}}[0]);
      $e=${$rec->{iff}}[1];
      unless ($val =~ /^($e)$/) {
	print hidden($p1,scalar(param($p1))) if ($rec->{iff}[2]);
	next;
      }
    }
    if ($rec->{iff2}) {
      $val=param($prefix."_".${$rec->{iff2}}[0]);
      $e=${$rec->{iff2}}[1];
      next unless ($val =~ /^($e)$/);
    }
    next if ($rec->{no_edit});

    print "<TR ".($form->{bgcolor}?" bgcolor=\"$form->{bgcolor}\" ":'').">";

    if ($rec->{ftype} == 0) {
      print "<TH COLSPAN=2 ALIGN=\"left\" FGCOLOR=\"$rec->{ro_color}\"",
            "  BGCOLOR=\"$h_bg\">",$rec->{name},"</TH>\n";
#   } elsif ($rec->{ftype} == 1) {
    } elsif ($rec->{ftype} == 1 ||
	     $rec->{tag} eq 'cname_txt' && $data->{'static_alias'}) { # 2020-12-17 TVu
      $maxlen=$rec->{len};
      $maxlen=$rec->{maxlen} if ($rec->{maxlen} > 0);
      if ($rec->{title}) { # Added if to handle titles. TVu 2020-11-03
	  print "<TD TITLE='$rec->{title}'>$rec->{name}</TD><TD>";
      } else {
	  print td($rec->{name}),"<TD>";
      }
      if ($rec->{type} eq 'passwd') {
	print password_field(-name=>$p1,-size=>$rec->{len},
			     -maxlength=>$maxlen,-value=>scalar(param($p1)));
      } elsif ($rec->{type} eq 'textarea') {
	print textarea(-name=>$p1,-rows=>$rec->{rows},
		       -columns=>$rec->{columns},-value=>scalar(param($p1)));
      } else {
	print textfield(-name=>$p1,-size=>$rec->{len},-maxlength=>$maxlen,
		    -value=>scalar(param($p1)));
	if ($data->{'static_alias'}) { # 2020-12-17 TVu
	    print hidden(-name=>$prefix.'_static_alias',-value=>1);
	}
      }
      if ($rec->{extrainfo}) {
	print '<BR><FONT size=-2 color="blue">'.$rec->{extrainfo}.'</FONT>';
      } elsif ($rec->{type} eq 'expiration') {
	print '<BR><FONT size=-1 color="blue">' .
	      'Enter expiration date as DD-MM-YYYY '.
              'or +&lt;number&gt;d (Days), +&lt;number&gt;m (Months), ' .
              ' +&lt;number&gt;y (Years)</FONT>';
      }
      if ($rec->{definfo}) {
	$def_info=$rec->{definfo}[0];
	$def_info='empty' if ($def_info eq '');
	print "<FONT size=-1 color=\"blue\"> ($def_info = default)</FONT>";
      }
# Can search hosts in any zone the user has access to.
      if ($rec->{anydomain}) {
	  print checkbox(-label=>'Any zone', -name=>$p1."_anydom",
			 -checked=>$$data{$p1."_anydom"}, -value=>'on');
      }
      if ($rec->{macnotify} && $data->{ip_policy} == 20) {
	  print '(In the pre-selected subnet<br>' .
	      'IPv6 address will be derived from MAC address, which you must give)';
      }
      if ($form->{defhost} && $rec->{type} eq 'domain') { # ****
	  $rec->{defhost} = 1;
      }

#     print "<FONT size=-1 color=\"red\"><BR> " .
#           form_check_field($rec,param($p1),0) . "</FONT>";

# Allow *. at the beginning of domain name when editing CNAME and Static aliases.
      $no_aster = param($p1); # 2020-09-01 TVu
      $no_aster =~ s/^\*\.// if ($rec->{'tag'} eq 'domain' and
				$rec->{'type'} eq 'domain' and
				($data->{'cname_alias'} or
				 $data->{'static_alias'}) and
				$no_aster =~ /^\*\./);
      print "<FONT size=-1 color=\"red\"><BR> " .
	  form_check_field($rec, $no_aster, 0) . "</FONT>";

      if ($rec->{chr} == 1) {
	print "<FONT size=-1 color=\"red\">" .
	      chr_check_field($rec->{tag},param($p1),$form->{chr_group}) .
	      "</FONT>";
      }
      print "</TD>";
    } elsif ($rec->{ftype} == 2) {
      print td($rec->{name}),"<TD><TABLE><TR>";
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	$a=$a+1;
	param($p1."_count",$a);
      }
      $a=0 if (!$a || $a < 0);
      #if ($a > 50) { $a = 50; }
      print hidden(-name=>$p1."_count",-value=>$a);
      for $k (1..$rec->{fields}) {
	print "<TH><FONT size=-2>",${$rec->{elabels}}[$k-1],"</FONT></TH>";
      }
      print "</TR>";
      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",scalar(param($p2."_id")));
	for $k (1..$rec->{fields}) {
	  $n=$p2."_".$k;
	  $maxlen=${$rec->{maxlen}}[$k-1];
	  $maxlen=${$rec->{len}}[$k-1] unless ($maxlen > 0);

	  if (${$rec->{type}}[$k-1] eq 'area') { # 2020-07-30 TVu
	      print "<TD>",textarea(-name=>$n,
				    -rows => $rec->{rows},
				    -columns => ${$rec->{len}}[$k-1],
				    -value => scalar(param($n)));
	  } else {

	      print "<TD>",textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
				     -maxlength=>$maxlen,-value=>scalar(param($n)));

	  }

	  print "<FONT size=-1 color=\"red\"><BR>",
                form_check_field($rec,param($n),$k),"</FONT></TD>";
        }
        print td("<FONT size=-2>",checkbox(-label=>'Delete',
		     -name=>$p2."_del",-checked=>scalar(param($p2."_del"))),
		 "</FONT>"),
	       "</TR>";
      }
      print "<TR>";
      $j=$a+1;
      for $k (1..$rec->{fields}) {
	$n=$prefix."_".$rec->{tag}."_".$j."_".$k;
	$maxlen=${$rec->{maxlen}}[$k-1];
	$maxlen=${$rec->{len}}[$k-1] unless ($maxlen > 0);

	if (${$rec->{type}}[$k-1] eq 'area') { # 2020-07-30 TVu
	    print td(textarea(-name=>$n,
			      -rows => $rec->{rows},
			      -columns => ${$rec->{len}}[$k-1],
			      -value => scalar(param($n))));
	} else {

	    print td(textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
			       -maxlength=>$maxlen,-value=>scalar(param($n))));

	}

      }
      print td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));

#     print "</TR></TABLE></TD>\n";

      print "</TR></TABLE>\n"; # 2020-07-21 TVu
      if ($rec->{extrainfo}) {
	print '<FONT color="blue">'.$rec->{extrainfo}.'</FONT>';
      }
      print "</TD>\n";

    } elsif ($rec->{ftype} == 3) {
      if ($rec->{type} eq 'enum') {
	  if ($rec->{ip_type_sensitive}) { # ****
	      $rec->{enum} = ip_policy_names($data->{net});
	  }
	$enum=$rec->{enum};
	if ($rec->{elist}) { $values=$rec->{elist}; }
	else { $values=[sort keys %{$enum}]; }
      } elsif ($rec->{type} eq 'list') {
	$enum=$data->{$rec->{list}};
	if ($rec->{listkeys}) {
	  $values=$data->{$rec->{listkeys}};
	} else {
	  $values=[sort keys %{$enum}];
	}
      }
      my $selection = param($p1);
      if ($rec->{preselectnet} && $selection eq 'MANUAL') {
	  $selection = $data->{preselectnet};
      }
      print td($rec->{name}),
	    td(popup_menu(-name=>$p1,-values=>$values,
			  -override=>1,
			  -default=>"$selection",
			  -labels=>$enum));
    } elsif ($rec->{ftype} == 4) {
      $val=param($p1);
      $val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
#     print td($rec->{name}),"<TD><FONT color=\"$form->{ro_color}\">",
      print "<td title='$rec->{title}'>$rec->{name}</td>","<TD><FONT color=\"$form->{ro_color}\">",
	  "$val</FONT></TD>", hidden($p1,scalar(param($p1)));
    } elsif ($rec->{ftype} == 5) {
      $rec->{fields}=5;
      $rec->{type}=['ip','text','text','text'];
      print td($rec->{name}),"<TD><TABLE><TR>";
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	$a=$a+1;
	param($p1."_count",$a);
      }
      $a=0 if (!$a || $a < 0);
      #if ($a > 50) { $a = 50; }
      print hidden(-name=>$p1."_count",-value=>$a);
      print td('IP'),td('Forward'),td('Reverse');
      print td("(",
	       checkbox(-label=>'allow duplicate IPs',name=>$p1."_allowdup",
			-checked=>'0'),")")  unless ($rec->{restricted_mode});
      print "</TR>";

      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",-value=>scalar(param($p2."_id")));

	$n=$p2."_1";
	if (!param($n) && param('subnetlist') && param('subnetlist') ne 'null') { # ****
	    param($n, param('subnetlist'));
	}
	print "<TD>",textfield(-name=>$n,-size=>40,-value=>scalar(param($n)));
        print "<FONT size=-1 color=\"red\"><BR>",
              #Value to be deleted won't be checked.
              (param($p2."_del") eq 'on' ? '' : form_check_field($rec,param($n),1)),"</FONT></TD>";
              #form_check_field($rec,param($n),1),"</FONT></TD>";
	if ($rec->{restricted_mode}) {
	  $n=$p2."_3";
	  print hidden(-name=>$n,-value=>scalar(param($n))),
	        td((param($n) eq 'on' ? 'on':'off'));
	  $n=$p2."_2";
	  print hidden(-name=>$n,-value=>scalar(param($n))),
	        td((param($n) eq 'on' ? 'on':'off'));
	}
	else {
	  $n=$p2."_3";
	  print td(checkbox(-label=>' A',-name=>$n,-checked=>scalar(param($n)))) if ip_is_ipv4(scalar(param($p2 . "_1")));
	  print td(checkbox(-label=>' AAAA',-name=>$n,-checked=>scalar(param($n)))) if ip_is_ipv6(scalar(param($p2 . "_1")));
	  $n=$p2."_2";
	  print td(checkbox(-label=>' PTR',-name=>$n,-checked=>scalar(param($n))));

	  print td(checkbox(-label=>' Delete',
			    -name=>$p2."_del",-checked=>scalar(param($p2."_del")) )),
			      "</TR>";
	}
      }

      unless ($rec->{restricted_mode}) {
	$j=$a+1;
	$n=$prefix."_".$rec->{tag}."_".$j."_1";
	my $subnetlist = '';
	if ($rec->{subnetlist}) { # ****
	    $subnetlist = get_ip_sugg($data->{hostid}, $serverid, $data->{perms});
	}
	print "<TR>",td(textfield(-name=>$n,-size=>40,-value=>scalar(param($n)))),
	td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add')),
	"<td colspan=2>$subnetlist</td>",
	"</TR>";
      }

      print "</TABLE></TD>\n";
    } elsif ($rec->{ftype} == 6) {
      get_mx_template_list($CGI_UTIL_zoneid,\%lsth,\@lst,$form->{alevel});
      get_mx_template(param($p1),\%tmpl_rec);
      print td($rec->{name}),"<TD><TABLE WIDTH=\"99%\">\n<TR>",
	    td(popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>scalar(param($p1)),-labels=>\%lsth),
            submit(-name=>$prefix."_".$rec->{tag}."_update",
		      -value=>'Update')),"</TR>\n<TR>",
	    "<TD>";
      print_mx_template(\%tmpl_rec);
      print "</TD></TR></TABLE></TD>";
    } elsif ($rec->{ftype} == 7) {
      get_wks_template_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel});
      get_wks_template(param($p1),\%tmpl_rec);
      print td($rec->{name}),"<TD><TABLE WIDTH=\"99%\">\n<TR>",
	    td(popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>scalar(param($p1)),-labels=>\%lsth),
            submit(-name=>$prefix."_".$rec->{tag}."_update",
		      -value=>'Update')),"</TR>\n<TR>",
	    "<TD>";
      print_wks_template(\%tmpl_rec);
      print "</TD></TR></TABLE></TD>";
    } elsif ($rec->{ftype} == 8) {
      next unless ($rec->{arec});
      # do nothing...unless editing arec aliases

      print td($rec->{name}),"<TD><TABLE><TR>";
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	if (($id=domain_in_use($CGI_UTIL_zoneid,
			       param($p1."_".($a+1)."_2")))>0) {
	  get_host($id,\%host);
	  if ($host{type}==1) {
	    $a=$a+1;
	    param($p1."_count",$a);
	    param($p1."_".$a."_1",$id);
	    $unknown_host=0;
	  } else { $invalid_host=1; }
	}
	else { $unknown_host=1; }
      }
      $a=0 unless ($a > 0);
      print hidden(-name=>$p1."_count",-value=>$a);

      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",scalar(param($p2."_id")));
	$n=$p2."_1";
	print hidden($n,scalar(param($n)));
	$n=$p2."_2";
	print td(param($n)),scalar(hidden($n,param($n)));
        print td(checkbox(-label=>' Delete',
	             -name=>$p2."_del",-checked=>scalar(param($p2."_del")) )),"</TR>";
      }
      $j=$a+1;
      $n=$prefix."_".$rec->{tag}."_".$j."_2";
      print "<TR><TD>",textfield(-name=>$n,-size=>25,-value=>scalar(param($n)));
      print "<BR><FONT color=\"red\">Uknown host!</FONT>"
	if ($unknown_host);
      print "<BR><FONT color=\"red\">Invalid host!</FONT>"
	if ($invalid_host);
      print "</TD>",
	td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));
      print "</TR></TABLE></TD>\n";
    }
    elsif ($rec->{ftype} == 9) {
      # do nothing...
    } elsif ($rec->{ftype} == 10) {
# This Czech-made limitation is incompatible with the way Sauron is used in
# University of Jyväskylä. It must be possible to attach a host to groups of both
# types 1 and 2 at the same time. Also, groups of all types 1-3 must appear in
# Host Search now that this search also finds hosts based on their subgroups.
# Any distinction between Group and Subgroups is purely historical. Properly,
# the current concept of Group should be discarded and Subgroups should be
# renamed Groups. 24 Jun 2015 TVu
#     get_group_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel},[1,2]);
#     get_group_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel},'');
# This limitation had to be partly re-introduced, because DHCP client classes
# only work as subgroups. ** 2021-11-29 TVu
# Group types: 1 = Normal, 2 = Dynamic Address Pool, 3 = DHCP class, 103 = Custom DHCP class
      get_group_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel},
		     $rec->{'no_dhcp'} ? [1,2] : '');
      get_group(param($p1),\%tmpl_rec);
      print td($rec->{name}),"<TD>",
	    popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>scalar(param($p1)),-labels=>\%lsth),
            "</TD>";
    }
    elsif ($rec->{ftype} == 11) {
# This Czech-made limitation is incompatible with the way
# Sauron is used in University of Jyväskylä. 24 Jun 2015 TVu
#     get_group_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel},[3]);
      get_group_list($CGI_UTIL_serverid,\%lsth,\@lst,$form->{alevel},'');
      $a=(param($p1."_count") > 0 ? param($p1."_count") : 0);

      if (param($p1."_add")) {
	my $newid = param($p1."_".($a+1)."_1");
	my $addok = ($newid > 0 ? 1 : 0);

	for $j (1..$a) { $addok=0 if (param($p1."_".$j."_1") == $newid); }
	if ($addok) {
	  $a++;
	  param($p1."_count",$a);
	  param($p1."_".$a."_2",$lsth{param($p1."_".$a."_1")});
	}
      }

      print td($rec->{name}),"<TD>";
      print hidden(-name=>$p1."_count",-value=>$a);
      for $j (1..$a) {
	$p2=$p1."_".$j;
	print hidden($p2."_id",scalar(param($p2."_id"))),
	      hidden($p2."_1",scalar(param($p2."_1"))),
	      hidden($p2."_2",scalar(param($p2."_2"))),
	      "[".param($p2."_2")," ",
	      checkbox(-label=>' (delete)',-name=>$p2."_del",
		       -checked=>scalar(param($p2."_del"))),"] ";
	print "<br>" if ($j % 4 == 0);
      }
      $n=$p1."_".($a+1)."_1";
      param($n,"-1") unless (param($n));
      print "<br>",
	    popup_menu(-name=>$n,-values=>\@lst,-default=>scalar(param($n)),
		       -labels=>\%lsth), " ",
	    submit(-name=>$p1."_add",-value=>'Add');
      print "</TD>";
    }
    elsif ($rec->{ftype} == 12) {
	my(@aml_key_l,%aml_key_h,@aml_acl_l,%aml_acl_h);
	get_acl_list($serverid,\%aml_acl_h,\@aml_acl_l,
		     ($rec->{acl_mode} == 1 ? param($prefix."_id") : 0));
	get_key_list($serverid,\%aml_key_h,\@aml_key_l,157);
	print td($rec->{name}),"<TD><TABLE><TR>",
 	      th(["<FONT size=-2>Type</FONT>",
		  "<FONT size=-2>Op</FONT>",
		  "<FONT size=-2>Rule</FONT>",
		  "<FONT size=-2>Comments</FONT>"]);
	$a=param($p1."_count");
	if (param($p1."_add") ne '') {
	    my $addmode=param($p1."_add");
	    my $b=$a+1;
	    if ($addmode eq 'Add CIDR') {
		param($p1."_".$b."_1",0);
		param($p1."_".$b."_3",-1);
		param($p1."_".$b."_4",-1);
		$a=$a+1 if (param($p1."_".$b."_2") ne '');
	    }
	    elsif ($addmode eq 'Add ACL') {
		param($p1."_".$b."_1",1);
		param($p1."_".$b."_2",'');
		param($p1."_".$b."_4",-1);
		$a=$a+1 if (param($p1."_".$b."_3") > 0);
	    }
	    else {
		param($p1."_".$b."_1",2);
		param($p1."_".$b."_2",'');
		param($p1."_".$b."_3",-1);
		$a=$a+1 if (param($p1."_".$b."_4") > 0);
	    }
	    param($p1."_count",$a);
	}
	$a=0 unless ($a > 0);
	print hidden(-name=>$p1."_count",-value=>$a),"</TR>";
	for $j (1..$a) {
	    $p2=$p1."_".$j;
	    my $aml_id = param($p2."_id");
	    my $aml_mode = param($p2."_1");
	    my $aml_cidr = param($p2."_2");
	    my $aml_acl = param($p2."_3");
	    my $aml_key = param($p2."_4");
	    my $aml_op = param($p2."_5");
	    my $aml_comment = param($p2."_6");
	    print "<TR>",hidden(-name=>$p2."_id",$aml_id),
	          hidden(-name=>$p2."_1",$aml_mode),
	          td($aml_type_hash{$aml_mode}.'&nbsp;'),
	          td(popup_menu(-name=>$p2."_5",-default=>$aml_op,
				-values=>[0,1],-labels=>{0=>' ',1=>'NOT'})),
	          "<TD>";
	    if ($aml_mode == 0) {
		print textfield(-name=>$p2."_2",-size=>43,-maxlength=>43,
				-value=>$aml_cidr),
		      hidden(-name=>$p2."_3",$aml_acl),
  		      hidden(-name=>$p2."_4",$aml_key);
	    }
	    elsif ($aml_mode == 1) {
		print popup_menu(-name=>$p2."_3",-default=>$aml_acl,
				 -values=>\@aml_acl_l,-labels=>\%aml_acl_h),
		      "<FONT size=-2> ACL</FONT> ",
		      hidden(-name=>$p2."_2",$aml_cidr),
  		      hidden(-name=>$p2."_4",$aml_key);
	    }
	    else {
		print popup_menu(-name=>$p2."_4",-default=>$aml_key,
				 -values=>\@aml_key_l,-labels=>\%aml_key_h),
		      "<FONT size=-2> Key</FONT> ",
		      hidden(-name=>$p2."_2",$aml_cidr),
  		      hidden(-name=>$p2."_3",$aml_acl);
	    }
	    print "</TD>",
	          td(textfield(-name=>$p2."_6",-size=>25,-maxlength=>80,
			       -value=>$aml_comment)),
	          td("<FONT size=-2>",checkbox(-label=>'Delete',
	             -name=>$p2."_del",-checked=>scalar(param($p2."_del")) ),
		     "</FONT>"),
	          "</TR>";
	}
	# add line...
	$j=$a+1;
	$p2=$p1."_".$j;
	print "<TR><TD rowspan=3>&nbsp;</TD>",
	      "<TD rowspan=3 bgcolor=\"#efefef\">",
	      popup_menu(-name=>$p2."_5",-default=>'0',
			    -values=>[0,1],-labels=>{0=>' ',1=>'NOT'}),"</TD>",
	      "<TD>",textfield(-name=>$p2."_2",-size=>43,-maxlength=>43,
			   -value=>''),
	      "</TD><TD rowspan=3 bgcolor=\"#efefef\">",
	      textfield(-name=>$p2."_6",-size=>25,-maxlength=>80,
			       -value=>''),"</TD>",
	      td(submit(-name=>$p1."_add",-value=>"Add CIDR")),"</TR><TR>",
	      "<TD bgcolor=\"#efefef\">",
	      popup_menu(-name=>$p2."_3",-default=>-1,
			 -values=>\@aml_acl_l,-labels=>\%aml_acl_h),"</TD>",
	      td(submit(-name=>$p1."_add",-value=>'Add ACL')),"</TR><TR>",
	      "<TD bgcolor=\"#efefef\">",
	      popup_menu(-name=>$p2."_4",-default=>-1,
			 -values=>\@aml_key_l,-labels=>\%aml_key_h),"</TD>",
	      td(submit(-name=>$p1."_add",-value=>'Add KEY')),"</TR>";

	print "</TABLE></TD>";
    }
    elsif ($rec->{ftype} == 13) { # Textarea (edit) 12 Apr 2017 TVu
      print td($rec->{name});
      my (@id, @tx);
      for $j (1..$#{$data->{$rec->{tag}}}) {
	  push (@id, ${$data->{$rec->{tag}}}[$j][0]);
	  push (@tx, '; ' . ${$data->{$rec->{tag}}}[$j][2])
	      if (${$data->{$rec->{tag}}}[$j][2]); # Prserve comments.
	  push (@tx, ${$data->{$rec->{tag}}}[$j][1]);
      }
      @tx = split(/\n/, join("\n", @tx));
      if (param($p1 . '_id')) { @id = split(/,/, param($p1 . '_id')); }
      print '<TD bgcolor="#e0e0e0">' .
	  hidden(-name=>$p1 . '_id', -value=>join(',', @id)) .
	  "<TEXTAREA NAME='$p1' ROWS=$rec->{rows} COLS=$rec->{cols}>" .
	  join("\n", @tx) . '</TEXTAREA>';
	  print "<FONT size=-1 color=\"red\">",
                form_check_field($rec, \@tx, 0),"</FONT></TD>";
      param($p1 . '_id', join(",", @id));
      param($p1, join("\n", @tx));
    }
    elsif ($rec->{ftype} == 101) {
      undef @q; undef @lst; undef %lsth;
      $maxlen=$rec->{len};
      $maxlen=$rec->{maxlen} if ($rec->{maxlen} > 0);
      db_query($rec->{sql},\@q);
      for $i (0..$#q) {
	push @lst,$q[$i][0];
	$lsth{$q[$i][0]}=$q[$i][0];
      }
      if ($rec->{addempty} > 0) {
	push @lst,'';
	$lsth{''}='<none>';
      }
      elsif ($rec->{addempty} < 0) {
	unshift @lst,'';
	$lsth{''}='<none>';
      }
      param($p1."_l",$lst[0])
	if (param($p1) eq '' && ($lst[0] ne '') && (not param($p1."_l")));

      if ($lsth{param($p1)} && (param($p1) ne '')) {
	param($p1."_l",param($p1));
	param($p1,'');
      }

      print td($rec->{name}),"<TD>",
	    popup_menu(-name=>$p1."_l",-values=>\@lst,-default=>$lst[0],
		       -labels=>\%lsth),
	    " ",textfield(-name=>$p1,-size=>$rec->{len},-maxlength=>$maxlen,
			  -value=>scalar(param($p1)));

      $tmp=param($p1);
      $tmp=param($p1."_l") if ($tmp eq '');
      print "<FONT size=-1 color=\"red\"><BR> ",
	    form_check_field($rec,$tmp,0),"</FONT></TD>";
    }
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

#####################################################################
# display_form($data,$form)
#
# generates HTML code that displays the form
#
sub display_form($$) {
  my($data,$form) = @_;
  my($i,$j,$k,$a,$rec,$formdata,$h_bg,$val,$e);
  my($ip,$ipinfo,$com,$url);


  form_get_defaults($form);
  $formdata=$form->{data};

  print "\n<TABLE border=\"0\" cellspacing=\"0\" cellpadding=\"1\" ";
  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "><TR><TD>\n";
  print "<TABLE ";
  print "BGCOLOR=\"" . $form->{tbl_bgcolor} . "\" " if ($form->{tbl_bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
  #print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . ($form->{border}>0?$form->{border}:0) . "\" ";
  print " width=\"100%\" cellspacing=\"1\" cellpadding=\"1\">\n";

  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];

    if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
    else { $h_bg='#ddddff'; }

    next if ($rec->{hidden});
    if ($rec->{restricted}) {
	next unless ($rec->{restricted} eq $form->{mode});
    }
    if ($rec->{iff}) {
      $val=$data->{${$rec->{iff}}[0]};
      $e=${$rec->{iff}}[1];
      next unless ($val =~ /^($e)$/);
    }
    if ($rec->{iff2}) {
      $val=$data->{${$rec->{iff2}}[0]};
      $e=${$rec->{iff2}}[1];
      next unless ($val =~ /^($e)$/);
    }
    if ($rec->{'no_false'}) {
      $val=$data->{$rec->{tag}};
      next if ($val =~ /^(f|F|false|0)$/);
    }

    $val=$data->{$rec->{tag}};
    $val="\L$val" if ($rec->{conv} eq 'L');
    $val="\U$val" if ($rec->{conv} eq 'U');
    $val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
    $val=localtime($val) if ($rec->{type} eq 'localtime');
    $val=gmtime($val) if ($rec->{type} eq 'gmtime');
    if ($rec->{tag} eq 'type' && $data->{type} == 4) {
	$val = ($data->{static_alias} || $data->{alias} == -1 ? 'Static ' : 'CNAME ') . $val;
    }

    print "<TR ".($form->{bgcolor}?" bgcolor=\"$form->{bgcolor}\" ":'').">\n";

    if ($rec->{ftype} == 0) {
      print "<TH COLSPAN=2 ALIGN=\"left\" BGCOLOR=\"$h_bg\">",
            $rec->{name},"</TH>\n";
    } elsif ($rec->{ftype} == 1 || $rec->{ftype} == 101) {
      next if ($rec->{no_empty} && $val eq '');

      $val =~ s/\/32$// if ($rec->{type} eq 'ip');
      $val =~ s/\/128$// if ($rec->{type} eq 'ip');
      $val = $val . sprintf(" (0x%0" . $rec->{extrahex} . "x)", $val) if ($rec->{extrahex} and $val ne "");
      if ($rec->{type} eq 'expiration') {
	unless ($val > 0) {
	  $val = '<FONT color="blue">NO expiration date set</FONT>';
	} else {
	  $val = (time() > $ val ?  localtime($val) .
		  ' <FONT color="red"> (EXPIRED!) </FONT>' : localtime($val));
	}
      }

      #print Tr,td([$rec->{name},$data->{$rec->{tag}}]);
      if ($rec->{definfo}) {
	if ($val eq $rec->{definfo}[0]) {
	  $val="<FONT color=\"blue\">$rec->{definfo}[1]</FONT>";
	}
      }
# If there is an URL, show it as a link, when requested. TVu
      if ($rec->{anchor}) { $val = url2link($val); }
      $val='&nbsp;' if ($val eq '');
      print "<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>";
    } elsif ($rec->{ftype} == 2) {
      $a=$data->{$rec->{tag}};
      next if ($rec->{no_empty} && @{$a}<2);
      print td($rec->{name}),
	    "<TD><TABLE width=\"100%\" bgcolor=\"#e0e0e0\">",
            "<TR bgcolor=\"#efefef\">";
      for $k (1..$rec->{fields}) {
	print "<TH><FONT size=-2>&nbsp;",$$a[0][$k-1],"&nbsp;</FONT></TH>";
      }
      print "</TR>";
      for $j (1..$#{$a}) {
	print "<TR>";
	for $k (1..$rec->{fields}) {
	  $val=$$a[$j][$k];
	  $val =~ s/\/32$// if ($rec->{type}[$k-1] eq 'ip');
	  $val =~ s/\/128$// if ($rec->{type}[$k-1] eq 'ip');
# Leading spaces on each line are processed before replacing newline characters.
	  $val =~ s/^( +)/'&nbsp;' x (length($1) * 2)/gem # 2020-07-30 TVu
	      if ($rec->{type}[$k-1] eq 'area');
	  $val =~ s/\n/<br>/g if ($rec->{type}[$k-1] eq 'area'); # 2020-07-30 TVu
	  $val='&nbsp;' if ($val eq '');
	  print td($val);
	}
	print "</TR>";
      }
      if (@{$a} < 2) { print "<TR><TD>&nbsp;</TD></TR>"; }
      print "</TABLE></TD>";
    } elsif ($rec->{ftype} == 3) {
	  if ($rec->{ip_type_sensitive}) { # ****
	      $rec->{enum} = ip_policy_names($data->{net});
	      $val = $rec->{enum}->{$data->{ip_policy}};
	  }
      print "<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>";
    } elsif ($rec->{ftype} == 4) {
      $val='&nbsp;' if ($val eq '');
      print "<TD WIDTH=\"",$form->{nwidth},"\" TITLE=\"",$rec->{title},"\">",$rec->{name},"</TD><TD>",
            "<FONT color=\"$form->{ro_color}\">$val</FONT></TD>";
    } elsif ($rec->{ftype} == 5) {
      print td($rec->{name}),"<TD><TABLE>";
      $a=$data->{$rec->{tag}};
      for $j (1..$#{$a}) {
	#$com=$$a[$j][4];
	$ip=$$a[$j][1];
	$ip=~ s/\/\d{1,3}$//g;
	$ipinfo='';
	$ipinfo.=' (no reverse)' if ($$a[$j][2] ne 't' && $$a[$j][2] != 1);
	$ipinfo.=' (no A record)' if ($$a[$j][3] ne 't' && $$a[$j][3] != 1 and ip_is_ipv4($ip));
	$ipinfo.=' (no AAAA record)' if ($$a[$j][3] ne 't' && $$a[$j][3] != 1 and ip_is_ipv6($ip));
	print Tr(td($ip),td($ipinfo));
      }
      print "</TABLE></TD>";
    } elsif (($rec->{ftype} == 6) || ($rec->{ftype} ==7) ||
	     ($rec->{ftype} == 10)) {
      print td($rec->{name});
      if ($val > 0) {
	print "<TD>";
	print_mx_template($data->{mx_rec}) if ($rec->{ftype}==6);
	print_wks_template($data->{wks_rec}) if ($rec->{ftype}==7);
	print $data->{grp_rec}->{name} if ($rec->{ftype}==10);
	print "</TD>";
      } else { print td("&lt;Not selected&gt;"); }
    } elsif ($rec->{ftype} == 8) {
      $a=$data->{$rec->{tag}};
      $url=$form->{$rec->{tag}."_url"};
      next unless (defined $a);
      next unless (@{$a}>1);
      print td($rec->{name}),"<TD><TABLE><TR>";
      #for $k (1..$rec->{fields}) { print "<TH>",$$a[0][$k-1],"</TH>";  }
      for $j (1..$#{$a}) {
	$k=' ';
	$k='&nbsp;(CNAME)' if ($$a[$j][3] eq '4' && $$a[$j][4] == 1);
	$k='&nbsp;(Static)' if ($$a[$j][3] eq '4' && $$a[$j][4] == -1);
	$k='&nbsp;(AREC)' if ($$a[$j][3] eq '7');
	print "<TR>",td("<a href=\"$url$$a[$j][1]\">".$$a[$j][2]."</a> "),
	          td($k),"</TR>";
      }
      print "</TABLE></TD>";
    } elsif ($rec->{ftype} == 9) {

#     $url=$form->{$rec->{tag}."_url"}.$data->{$rec->{idtag}};
#     print td($rec->{name}),td("<a href=\"$url\">$val</a>");

# Create link only if it points to something internal. 2020-09-02 TVu
      print td($rec->{name});
      if ($data->{$rec->{idtag}} =~ /^\d+$/) {
	  $url=$form->{$rec->{tag}."_url"}.$data->{$rec->{idtag}};
	  print td("<a href=\"$url\">$val</a>");
      } else {
	  print td($val);
      }

    } elsif ($rec->{ftype} == 11) {
      $a=$data->{$rec->{tag}};
      print td($rec->{name}),"<TD>";
      if (@{$a} > 1) {
	for $j (1..$#{$a}) {
	  print "$$a[$j][2] ";
	}
      } else {
	print "&lt;None&gt;";
      }
      print "</TD>";
    } elsif ($rec->{ftype} == 12) {
	print td($rec->{name}),
	      "<TD><TABLE width=\"100%\" bgcolor=\"#e0e0e0\">",
	      "<TR bgcolor=\"#efefef\">",
  	     th(["<FONT size=-2>Type</FONT>",
		 "<FONT size=-2>Op</FONT>",
		 "<FONT size=-2>Rule</FONT>",
		 "<FONT size=-2>Comments</FONT>"]),"</TR>";
	$a=$data->{$rec->{tag}};
	for $j (1..$#{$a}) {
	    if ($$a[$j][1] == 0) { $val=$$a[$j][2]; }
	    elsif ($$a[$j][1] == 1) { $val=$$a[$j][8]; }
	    else { $val=$$a[$j][9]; }
	    print "<TR>",
	          td($aml_type_hash{$$a[$j][1]}.'&nbsp;'),
	          td($$a[$j][5]==1?'!':''),
	          td($val),td($$a[$j][6]),"</TR>";
	}

	if (@{$a} < 2) { print "<TR><TD>&nbsp;</TD></TR>"; }
	print "</TABLE></TD>";
    } elsif ($rec->{ftype} == 13) { # Textarea (show) 12 Apr 2017 TVu
      $a = $data->{$rec->{tag}};
      print td($rec->{name});
      my @tx;
      for $j (1..$#{$a}) {
	  push (@tx, '; ' . $$a[$j][2]) if ($$a[$j][2]); # Prserve comments.
	  push (@tx, $$a[$j][1]);
      }
      $a = join("\n", @tx);
      $a =~ s/\n/<br>\n/g;
      $a =~ s/^(\s+)/'&nbsp;' x (length($1) * 2)/emg; # Prserve indentation.
      print "<TD bgcolor='#e0e0e0'>$a</TD>";
    } else {
      error("internal error (display_form)");
    }
    print "</TR>\n";
  }

  print "</TABLE></TD></TR></TABLE>\n";
}

sub print_mx_template($) {
  my($rec)=@_;
  my($i,$l);

  return unless ($rec);
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaeae0\">",
        "<TR bgcolor=\"#afffe0\"><TD colspan=\"2\">",
        $rec->{name},"</TH></TR>";
  $l=$rec->{mx_l};
  for $i (1..$#{$l}) {
    print "<TR>",td($$l[$i][1]),td($$l[$i][2]),"</TR>";
  }
  print "</TABLE>";
}

sub print_wks_template($) {
  my($rec)=@_;
  my($i,$l);

  return unless ($rec);
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaeae0\">",
        "<TR bgcolor=\"#afffe0\"><TD colspan=\"2\">",
        $rec->{name},"</TD></TR>";
  $l=$rec->{wks_l};
  for $i (1..$#{$l}) {
    print "<TR>",td($$l[$i][1]),td($$l[$i][2]),"</TR>";
  }
  print "</TABLE>";
}


########################################################################
# display_dialog($msg,$dataq,$form,$hidden,$selfurl)
#
# displays standard OK/Cancel dialog using given form
#
sub display_dialog($$$$$) {
  my($msg,$data,$form,$hidden,$self_url) = @_;
  my(@f,$i);

  if (param('dialog_cancel')) {
    return -1;
  }
  elsif (param('dialog_ok')) {
    unless (form_check_form('DIALOG',$data,$form)) {
      return 1;
    }
    alert2("Invalid data in form!");
  }

  print h2($msg);
  print start_form(-method=>'POST',-action=>$self_url);
  @f=split(',',$hidden);
  for $i (0..$#f) { print hidden($f[$i]); }
  form_magic('DIALOG',$data,$form);
  print submit(-name=>'dialog_ok',-value=>'OK'),
        submit(-name=>'dialog_cancel',-value=>'Cancel'),
	end_form();
  return 0;
}

sub display_list($$$)
{
  my($header,$list,$offset) = @_;
  my($i,$j,$cols,$val);

  $offset = 0 unless ($offset > 0);
  $cols = $#{$header};
  print "<TABLE width=\"99%\" bgcolor=\"#ccccff\" cellspacing=1>\n",
        "<TR bgcolor=\"#aaaaff\">";
  for $i (0..$cols) {
    print th(($$header[$i] ? $$header[$i] : '&nbsp;'));
  }
  print "</TR>\n";
  for $i (0..$#{$list}) {
    print "<TR bgcolor=\"#eeeebf\">";
    for $j (0..$cols) {
      $val = $$list[$i][$offset+$j];
      if ($$header[$j] =~ /Date/) {
	$val = localtime($val)." " if ($val > 0);
      }
      print td(($val ne '' ? $val : '&nbsp;'));
    }
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

########################################################################

sub alert1($) {
  my($msg)=@_;
  print "<H2><FONT color=\"red\">$msg</FONT></H2>";
}

sub alert2($) {
  my($msg)=@_;
  print "<H3><FONT color=\"red\">$msg</FONT></H3>";
}


sub html_error($) {
  my($msg)=@_;
  print header(),start_html("CGI: error"),h1("Error: $msg"),end_html();
  exit;
}

sub html_error2($) {
  my($msg)=@_;
  print h1("Error: $msg"),end_html();
  exit;
}


1;
# eof
