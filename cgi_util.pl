# cgi_util.pl  --  generic CGI stuff
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2001.
# $Id$
#

use CGI;
use strict;

my($CGI_UTIL_zoneid,$CGI_UTIL_serverid);

sub cgi_util_set_zoneid($) {
  my ($id) = @_;
  $CGI_UTIL_zoneid = $id;
}

sub cgi_util_set_serverid($) {
  my ($id) = @_;
  $CGI_UTIL_serverid = $id;
}

#####################################################################
# form_check_field($field,$value,$n) 
#
# checks if given field (in a form) contains valid data
#
sub form_check_field($$$) {
  my($field,$value,$n) = @_;
  my($type,$empty,$t);

  if ($n > 0) {
    $empty=${$field->{empty}}[$n-1];
    $type=${$field->{type}}[$n-1];
  }
  else {
    $empty=$field->{empty};
    $type=$field->{type};
  }

  unless ($empty == 1) {
    return 'Empty field not allowed!' if ($value =~ /^\s*$/);
  } else {
    return '' if ($value =~ /^\s*$/);
  }


  if ($type eq 'fqdn' || $type eq 'domain') {
    if ($type eq 'domain') {
      return 'valid domain name required!' unless (valid_domainname($value));
    } else {
      return 'FQDN required!'
	unless (valid_domainname($value) && $value=~/\.$/);
    }
  } elsif ($type eq 'path') {
    return 'valid pathname required!'
      unless ($value =~ /^(|\S+\/)$/);
  } elsif ($type eq 'ip') {
    return 'valid IP number required!' unless 
      ($value =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/);
  } elsif ($type eq 'cidr') {
    return 'valid CIDR (IP) required!' unless (is_cidr($value));
  } elsif ($type eq 'text') {
    return '';
  } elsif ($type eq 'passwd') {
    return '';
  } elsif ($type eq 'enum') {
    return '';
  } elsif ($type eq 'mx') {
    return 'valid domain or "$DOMAIN" required!'
      unless(($value eq '$DOMAIN') || valid_domainname($value));
  } elsif ($type eq 'int' || $type eq 'priority') {
    return 'integer required!' unless ($value =~ /^(-?\d+)$/);
    $t=$1;
    if ($type eq 'priority') {
      return 'priority (0..n) required!' unless ($t >= 0);
    }
  } elsif ($type eq 'bool') {
    return 'boolean value required!' unless ($value =~ /^(t|f)$/);
  } elsif ($type eq 'mac') {
    return 'Ethernet address required!'
      unless ($value =~ /^([0-9A-Z]{12})$/);
  } elsif ($type eq 'printer_class') {
    return 'Valid printer class name required!'
      unless ($value =~ /^\@[a-zA-Z]+$/);
  } elsif ($type eq 'hinfo') {
    return 'Valid HINFO required!'
      unless ($value =~ /^[A-Z]+([A-Z0-9-\+]+)?$/);
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
  $form->{bgcolor}="#eeeebf" unless ($form->{bgcolor});
  $form->{heading_bg}="#aaaaff" unless ($form->{heading_bg});
  $form->{ro_color}="#646464" unless ($form->{ro_color});
  $form->{border}=0 unless ($form->{border});
  $form->{width}="100%" unless ($form->{width});
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

  $formdata=$form->{data};
  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $type=$rec->{ftype};
    $tag=$rec->{tag};
    $p=$prefix."_".$tag;

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

    #print "<br>check $p,$type";

    if ($type == 1) {
      $val=param($p);
      if ($rec->{type} eq 'mac') {
	$val="\U$val";
	$val =~ s/[\s:-]//g;
      }
      #print "<br>check $p ",param($p);
      return 1 if (form_check_field($rec,$val,0) ne '');
      #print p,"$p changed! '",$data->{$tag},"' '",param($p),"'\n" if ($data->{$tag} ne param($p));
      $data->{$tag}=$val;
    }
    elsif ($type == 101) {
      $tmp=param($p);
      $tmp=param($p."_l") if ($tmp eq '');
      return 101 if (form_check_field($rec,$tmp,0) ne '');
      $data->{$tag}=$tmp;
    }
    elsif  ($type == 2 || $type==5 || ($type==8 && $rec->{arec})) {
      $f=$rec->{fields};
      $f=1 if ($type==8);
      $f=3 if ($type==5);
      $rec->{type}=['ip','text','text'] if ($type==5);
      $rec->{empty}=[0,1,1] if ($type==5);
      $a=param($p."_count");
      $a=0 if (!$a || $a < 0);
      for $j (1..$a) {
	next if ($type==8);
	next if (param($p."_".$j."_del") eq 'on'); # skip if 'delete' checked
	for $k (1..$f) {
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
	  if ($ind < 0) {
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
      return 3 unless (${$rec->{enum}}{param($p)});
      $data->{$tag}=param($p);
    }
    elsif ($type == 6 || $type == 7 || $type == 10) {
      return 6 unless (param($p) =~ /^-?\d+$/);
      $data->{$tag}=param($p);
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
  my($invalid_host,$unknown_host,%host);

  form_get_defaults($form);
  $formdata=$form->{data};
  $h_bg=$form->{heading_bg};

  # initialize fields
  unless (param($prefix . "_re_edit") eq '1' || ! $data) {
    for $i (0..$#{$formdata}) {
      $rec=$$formdata[$i];
      $val=$data->{$rec->{tag}};
      $val="\L$val" if ($rec->{conv} eq 'L');
      $val="\U$val" if ($rec->{conv} eq 'U');
      $val=~ s/\s+$//;
      $p1=$prefix."_".$rec->{tag};

      if ($rec->{ftype} == 1 || $rec->{ftype} == 101) {
	$val =~ s/\/32$// if ($rec->{type} eq 'ip');
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 2 || $rec->{ftype} == 8) {
	$a=$data->{$rec->{tag}};
	for $j (1..$#{$a}) {
	  param($p1."_".$j."_id",$$a[$j][0]);
	  for $k (1..$rec->{fields}) {
	    $val=$$a[$j][$k];
	    $val =~ s/\/32$// if ($rec->{type}[$k-1] eq 'ip');
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
	  $ip =~ s/\/\d{1,2}$//g;
	  param($p1."_".$j."_1",$ip);
	  $t=''; $t='on' if ($$a[$j][2] eq 't');
	  param($p1."_".$j."_2",$t);
	  $t=''; $t='on' if ($$a[$j][3] eq 't');
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
  print "BGCOLOR=\"" . $form->{bgcolor} . "\" " if ($form->{bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
# netscape sekoilee muuten no-frame modessa...
#  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . $form->{border} . "\" " if ($form->{border});
  print " cellspacing=\"0\" cellpadding=\"1\">\n";


  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $p1=$prefix."_".$rec->{tag};

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

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" FGCOLOR=\"$rec->{ro_color}\" BGCOLOR=\"$h_bg\">",
             $rec->{name},"</TH></TR>\n" unless ($rec->{no_edit});
    } elsif ($rec->{ftype} == 1) {
      $maxlen=$rec->{len};
      $maxlen=$rec->{maxlen} if ($rec->{maxlen} > 0);
      if ($rec->{type} eq 'passwd') {
	print "<TR>",td($rec->{name}),"<TD>",
	  password_field(-name=>$p1,-size=>$rec->{len},-maxlength=>$maxlen,
			 -value=>param($p1));
      } else {
	print "<TR>",td($rec->{name}),"<TD>",
	  textfield(-name=>$p1,-size=>$rec->{len},-maxlength=>$maxlen,
		    -value=>param($p1));
      }
      if ($rec->{definfo}) {
	$def_info=$rec->{definfo}[0];
	$def_info='empty' if ($def_info eq '');
	print "<FONT size=-1 color=\"blue\"> ($def_info = default)</FONT>";
      }
      print "<FONT size=-1 color=\"red\"><BR> ",
            form_check_field($rec,param($p1),0),
            "</FONT></TD></TR>";
    } elsif ($rec->{ftype} == 2) {
      print "<TR>",td($rec->{name}),"<TD><TABLE><TR>";
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	$a=$a+1;
	param($p1."_count",$a);
      }
      $a=0 if (!$a || $a < 0);
      #if ($a > 50) { $a = 50; }
      print hidden(-name=>$p1."_count",-value=>$a);
      for $k (1..$rec->{fields}) { 
	print "<TD>",${$rec->{elabels}}[$k-1],"</TD>"; 
      }
      print "</TR>";
      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",param($p2."_id"));
	for $k (1..$rec->{fields}) {
	  $n=$p2."_".$k;
	  print "<TD>",textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
	                         -value=>param($n));
	  print "<FONT size=-1 color=\"red\"><BR>",
              form_check_field($rec,param($n),$k),
              "</FONT></TD>";
        }
        print td(checkbox(-label=>' Delete',
	             -name=>$p2."_del",-checked=>param($p2."_del") )),
	       "</TR>";
      }
      print "<TR>";
      $j=$a+1;
      for $k (1..$rec->{fields}) {
	$n=$prefix."_".$rec->{tag}."_".$j."_".$k;
	print td(textfield(-name=>$n,-size=>${$rec->{len}}[$k-1],
		 -value=>param($n)));
      }
      print td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));
      print "</TR></TABLE></TD></TR>\n";
    } elsif ($rec->{ftype} == 3) {
      if ($rec->{type} eq 'enum') {
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
      print "<TR>",td($rec->{name}),
	    td(popup_menu(-name=>$p1,-values=>$values,
	                  -default=>param($p1),-labels=>$enum)),"</TR>";
    } elsif ($rec->{ftype} == 4) {
      $val=param($p1);
      $val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
      print "<TR>",td($rec->{name}),"<TD><FONT color=\"$form->{ro_color}\">",
	    "$val</FONT></TD>",hidden($p1,param($p1)),"</TR>";
    } elsif ($rec->{ftype} == 5) {
      $rec->{fields}=5;
      $rec->{type}=['ip','text','text','text'];
      print "<TR>",td($rec->{name}),"<TD><TABLE><TR>";
      $a=param($p1."_count");
      if (param($p1."_add") ne '') {
	$a=$a+1;
	param($p1."_count",$a);
      }
      $a=0 if (!$a || $a < 0);
      #if ($a > 50) { $a = 50; }
      print hidden(-name=>$p1."_count",-value=>$a);
      print td('IP'),td('Reverse'),td('Forward'),"</TR>";

      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",-value=>param($p2."_id"));

	$n=$p2."_1";
	print "<TD>",textfield(-name=>$n,-size=>15,-value=>param($n));
        print "<FONT size=-1 color=\"red\"><BR>",
              form_check_field($rec,param($n),1),"</FONT></TD>";

	if ($rec->{restricted}) {
	  $n=$p2."_2";
	  print hidden(-name=>$n,-value=>param($n)),
	        td((param($n) eq 'on' ? 'on':'off'));
	  $n=$p2."_3";
	  print hidden(-name=>$n,-value=>param($n)),
	        td((param($n) eq 'on' ? 'on':'off'));
	}
	else {
	  $n=$p2."_2";
	  print td(checkbox(-label=>' A',-name=>$n,-checked=>param($n)));
	  $n=$p2."_3";
	  print td(checkbox(-label=>' PTR',-name=>$n,-checked=>param($n)));

	  print td(checkbox(-label=>' Delete',
			    -name=>$p2."_del",-checked=>param($p2."_del") )),
			      "</TR>";
	}
      }

      unless ($rec->{restricted}) {
	$j=$a+1;
	$n=$prefix."_".$rec->{tag}."_".$j."_1";
	print "<TR>",td(textfield(-name=>$n,-size=>15,-value=>param($n))),
	      td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add')),
	      "</TR>";
      }

      print "</TABLE></TD></TR>\n";
    } elsif ($rec->{ftype} == 6) {
      get_mx_template_list($CGI_UTIL_zoneid,\%lsth,\@lst);
      get_mx_template(param($p1),\%tmpl_rec);
      print "<TR>",td($rec->{name}),"<TD><TABLE WIDTH=\"99%\">\n<TR>",
	    td(popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>param($p1),-labels=>\%lsth),
            submit(-name=>$prefix."_".$rec->{tag}."_update",
		      -value=>'Update')),"</TR>\n<TR>",
	    "<TD>";
      print_mx_template(\%tmpl_rec);
      print "</TD></TR></TABLE></TD></TR>";
    } elsif ($rec->{ftype} == 7) {
      get_wks_template_list($CGI_UTIL_serverid,\%lsth,\@lst);
      get_wks_template(param($p1),\%tmpl_rec);
      print "<TR>",td($rec->{name}),"<TD><TABLE WIDTH=\"99%\">\n<TR>",
	    td(popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>param($p1),-labels=>\%lsth),
            submit(-name=>$prefix."_".$rec->{tag}."_update",
		      -value=>'Update')),"</TR>\n<TR>",
	    "<TD>";
      print_wks_template(\%tmpl_rec);
      print "</TD></TR></TABLE></TD></TR>";
    } elsif ($rec->{ftype} == 8) {
      next unless ($rec->{arec});
      # do nothing...unless editing arec aliases

      print "<TR>",td($rec->{name}),"<TD><TABLE><TR>";
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
	print "<TR>",hidden(-name=>$p2."_id",param($p2."_id"));
	$n=$p2."_1";
	print hidden($n,param($n));
	$n=$p2."_2";
	print td(param($n)),hidden($n,param($n));
        print td(checkbox(-label=>' Delete',
	             -name=>$p2."_del",-checked=>param($p2."_del") )),"</TR>";
      }
      $j=$a+1;
      $n=$prefix."_".$rec->{tag}."_".$j."_2";
      print "<TR><TD>",textfield(-name=>$n,-size=>25,-value=>param($n));
      print "<BR><FONT color=\"red\">Uknown host!</FONT>" 
	if ($unknown_host);
      print "<BR><FONT color=\"red\">Invalid host!</FONT>" 
	if ($invalid_host);
      print "</TD>",
	td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));
      print "</TR></TABLE></TD></TR>\n";
    }
    elsif ($rec->{ftype} == 9) {
      # do nothing...
    } elsif ($rec->{ftype} == 10) {
      get_group_list($CGI_UTIL_serverid,\%lsth,\@lst);
      get_group(param($p1),\%tmpl_rec);
      print "<TR>",td($rec->{name}),"<TD>",
	    popup_menu(-name=>$p1,-values=>\@lst,
	                  -default=>param($p1),-labels=>\%lsth),
            "</TD></TR>";
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
      if ($rec->{lastempty}) {
	push @lst,'';
	$lsth{''}='<none>';
      }
      param($p1."_l",$lst[0]) 
	if (param($p1) eq '' && ($lst[0] ne '') && (not param($p1."_l")));

      if ($lsth{param($p1)} && (param($p1) ne '')) {
	param($p1."_l",param($p1));
	param($p1,'');
      }

      print "<TR>",td($rec->{name}),"<TD>",
	    popup_menu(-name=>$p1."_l",-values=>\@lst,-default=>param($p1),
		       -labels=>\%lsth),
	    " ",textfield(-name=>$p1,-size=>$rec->{len},-maxlength=>$maxlen,
			  -value=>param($p1));

      $tmp=param($p1);
      $tmp=param($p1."_l") if ($tmp eq '');
      print "<FONT size=-1 color=\"red\"><BR> ",
	    form_check_field($rec,$tmp,0),
	    "</FONT></TD></TR>";
    }
    print "\n";
  }
  print "</TABLE>";
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

  print "<TABLE ";
  print "BGCOLOR=\"" . $form->{bgcolor} . "\" " if ($form->{bgcolor});
  print "FGCOLOR=\"" . $form->{fgcolor} . "\" " if ($form->{fgcolor});
  print "WIDTH=\"" . $form->{width} . "\" " if ($form->{width});
  print "BORDER=\"" . $form->{border} . "\" " if ($form->{border});
  print " cellspacing=\"0\" cellpadding=\"1\">";

  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];

    if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
    else { $h_bg='#ddddff'; }
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

    $val=$data->{$rec->{tag}};
    $val="\L$val" if ($rec->{conv} eq 'L');
    $val="\U$val" if ($rec->{conv} eq 'U');
    $val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
    $val=localtime($val) if ($rec->{type} eq 'localtime');
    $val=gmtime($val) if ($rec->{type} eq 'gmtime');

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" BGCOLOR=\"$h_bg\">",
            $rec->{name},"</TH></TR>\n";
    } elsif ($rec->{ftype} == 1 || $rec->{ftype} == 101) {
      next if ($rec->{no_empty} && $val eq '');

      $val =~ s/\/32$// if ($rec->{type} eq 'ip');
      #print Tr,td([$rec->{name},$data->{$rec->{tag}}]);
      if ($rec->{definfo}) {
	if ($val eq $rec->{definfo}[0]) {
	  $val="<FONT color=\"blue\">$rec->{definfo}[1]</FONT>";
	}
      }

      $val='&nbsp;' if ($val eq '');
      print "<TR><TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD></TR>\n";
    } elsif ($rec->{ftype} == 2) {
      $a=$data->{$rec->{tag}};
      next if ($rec->{no_empty} && @{$a}<2);
      print "<TR>",td($rec->{name}),
	    "<TD><TABLE width=\"100%\" bgcolor=\"#e0e0e0\">";
      for $k (1..$rec->{fields}) { 
	#print "<TH>",$$a[0][$k-1],"</TH>";
      }
      for $j (1..$#{$a}) {
	print "<TR>";
	for $k (1..$rec->{fields}) {
	  $val=$$a[$j][$k];
	  $val =~ s/\/32$// if ($rec->{type}[$k-1] eq 'ip');
	  $val='&nbsp;' if ($val eq '');
	  print td($val);
	}
	print "</TR>";
      }
      print "</TABLE></TD></TR>\n";
    } elsif ($rec->{ftype} == 3) {
      print "<TR><TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD></TR>\n";
    } elsif ($rec->{ftype} == 4) {
      $val='&nbsp;' if ($val eq '');
      print "<TR><TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "<FONT color=\"$form->{ro_color}\">$val</FONT></TD></TR>\n";
    } elsif ($rec->{ftype} == 5) {
      print "<TR>",td($rec->{name}),"<TD><TABLE>";
      $a=$data->{$rec->{tag}};
      for $j (1..$#{$a}) {
	#$com=$$a[$j][4];
	$ip=$$a[$j][1];
	$ip=~ s/\/\d{1,2}$//g;
	$ipinfo='';
	$ipinfo.=' (no reverse)' if ($$a[$j][2] ne 't');
	$ipinfo.=' (no A record)' if ($$a[$j][3] ne 't');
	print Tr(td($ip),td($ipinfo));
      }
      print "</TABLE></TD></TR>\n";
    } elsif (($rec->{ftype} == 6) || ($rec->{ftype} ==7) ||
	     ($rec->{ftype} == 10)) {
      print "<TR>",td($rec->{name});
      if ($val > 0) { 
	print "<TD>";
	print_mx_template($data->{mx_rec}) if ($rec->{ftype}==6);
	print_wks_template($data->{wks_rec}) if ($rec->{ftype}==7);
	print $data->{grp_rec}->{name} if ($rec->{ftype}==10);
	print "</TD>";
      } else { print td("Not selected"); }
      print "</TR>";
    } elsif ($rec->{ftype} == 8) {
      $a=$data->{$rec->{tag}};
      $url=$form->{$rec->{tag}."_url"};
      next unless (@{$a}>1);
      print "<TR>",td($rec->{name}),"<TD><TABLE><TR>";
      #for $k (1..$rec->{fields}) { print "<TH>",$$a[0][$k-1],"</TH>";  }
      for $j (1..$#{$a}) {
	$k=' ';
	$k=' (AREC)' if ($$a[$j][3] eq '7');
	print "<TR>",td("<a href=\"$url$$a[$j][1]\">".$$a[$j][2]."</a> "),
	          td($k),"</TR>";
      }
      print "</TABLE></TD></TR>\n";
    } elsif ($rec->{ftype} == 9) {
      $url=$form->{$rec->{tag}."_url"}.$data->{$rec->{idtag}};
      print "<TR>",td($rec->{name}),td("<a href=\"$url\">$val</a>"),"</TR>";
    } else {
      error("internal error (display_form)");
    }
  }

  print "</TABLE>";
}

sub print_mx_template($) {
  my($rec)=@_;
  my($i,$l);

  return unless ($rec);
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaeae0\"><TR><TD colspan=\"2\">",
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
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaeae0\"><TR><TD colspan=\"2\">",
        $rec->{name},"</TD></TR>";
  $l=$rec->{wks_l};
  for $i (1..$#{$l}) {
    print "<TR>",td($$l[$i][1]),td($$l[$i][2]),"</TR>";
  }
  print "</TABLE>";
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


sub error($) {
  my($msg)=@_;
  print header(),start_html("sauron: error"),h1("Error: $msg"),end_html();
  exit;
}

sub error2($) {
  my($msg)=@_;
  print h1("Error: $msg"),end_html();
  exit;
}

