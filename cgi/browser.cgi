#!/usr/bin/perl
#
# browser.cgi
# $Id$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2001.
# All Rights Reserved.
#
use Sys::Syslog;
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
use Digest::MD5;
use Net::Netmask;

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 10000; # max 10k posts

#$|=1;
$debug_mode = 0;

if (-f "/etc/sauron/config") {
  $conf_dir='/etc/sauron';
}
elsif (-f "/opt/etc/sauron/config") {
  $conf_dir='/opt/etc/sauron';
}
elsif (-f "/usr/local/etc/sauron/config") {
  $conf_dir='/usr/local/etc/sauron';
}
else {
  error("cannot find configuration file!");
}

do "$conf_dir/config" || error("cannot load configuration!");

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";


%yes_no_enum = (D=>'Default',Y=>'Yes', N=>'No');

%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
	     8=>'SRV record');


%host_form = (
 data=>[
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>30},
  {ftype=>5, tag=>'ip', name=>'IP address', iff=>['type','[16]']},
  {ftype=>9, tag=>'alias_d', name=>'Alias for', idtag=>'alias',
   iff=>['type','4'], iff2=>['alias','\d+']},
  {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
   len=>60, iff=>['type','4'], iff2=>['alias','-1']},
  {ftype=>8, tag=>'alias_a', name=>'Alias for host(s)', fields=>3,
   arec=>1, iff=>['type','7']},
#  {ftype=>4, tag=>'id', name=>'Host ID'},
#  {ftype=>4, tag=>'alias', name=>'Alias ID', iff=>['type','4']},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
#  {ftype=>4, tag=>'class', name=>'Class'},
  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1,
   definfo=>['','Default']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>1, iff=>['type','1']},
  {ftype=>0, name=>'Equipment info', iff=>['type','1']},
  {ftype=>1, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>12,
   iff=>['type','1'], empty=>1},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer', iff=>['type','1']},
  {ftype=>1, tag=>'ether_alias_info', name=>'Ethernet alias', no_empty=>1,
   empty=>1, type=>'domain', len=>30, iff=>['type','1'] },

#  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>30, empty=>1, 
#   no_empty=>1, iff=>['type','1']},
#  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>20,
#   empty=>1, no_empty=>1, iff=>['type','1']},
#  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
#   no_empty=>1, iff=>['type','1']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},

  {ftype=>0, name=>'Host specific',iff=>['type','[12]']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['text','text'], 
   fields=>2, 
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'wks_l', name=>'WKS', no_empty=>1,
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,0,1], 
   elabels=>['Protocol','Services','comment'], iff=>['type','1']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', 
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], 
   empty=>[0,0,1], no_empty=>1,
   elabels=>['Priority','MX','comment'], iff=>['type','[13]']},
  {ftype=>2, tag=>'txt_l', name=>'TXT', type=>['text','text'], 
   fields=>2, no_empty=>1,
   len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','1']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries', no_empty=>1,
   type=>['text','text'], fields=>2,len=>[40,20], empty=>[0,1], 
   elabels=>['PRINTER','comment'], iff=>['type','[15]']},

  {ftype=>0, name=>'Aliases', no_edit=>1, iff=>['type','1']},
  {ftype=>8, tag=>'alias_l', name=>'Aliases', fields=>3, iff=>['type','1']},

  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,10],
   empty=>[0,0,0,0,1],elabels=>['Priority','Weight','Port','Target','Comment'],
   type=>['priority','priority','priority','fqdn','text'],
   iff=>['type','8']},

  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);


sub logmsg($$) {
  my($type,$msg)=@_;

  open(LOGFILE,">>$LOG_DIR/sauron.log");
  print LOGFILE localtime(time) . " sauron: $msg\n";
  close(LOGFILE);

  #openlog("sauron","cons,pid","user");
  #syslog($type,"foo: %s\n",$msg);
  #closelog();
}


#####################################################################

db_connect2() || error("Cannot estabilish connection with database");
if (($res=cgi_disabled())) { error("CGI interface disabled: $res"); }
error("Invalid log path") unless (-d $LOG_DIR);

$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$remote_addr = $ENV{'REMOTE_ADDR'};
$remote_host = remote_host();

set_muser('browser');
$bgcolor='white';

print header(-type=>'text/html; charset=iso-8859-1'),
      start_html(-title=>"Sauron $VER",-BGCOLOR=>$bgcolor,
		 -meta=>{'keywords'=>'GNU Sauron DNS DHCP tool'}),
      "\n\n<!-- Sauron DNS Browser $VER -->\n",
      "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2001. -->\n\n";



$key = $pathinfo;
$key =~ s/[^a-z0-9\-]//g;

error2("Invalid parameters!") unless (@{$$BROWSER_CONF{$key}} == 2);
$server=$$BROWSER_CONF{$key}[0];
$zone=$$BROWSER_CONF{$key}[1];

#print "server '$server', zone '$zone'\n";

$serverid=get_server_id($server);
error2("Invalid configuration: cannot find server") unless ($serverid > 0);
$zoneid=get_zone_id($zone,$serverid);
error2("Invalid configuration: cannot find zone") unless ($zoneid > 0);

if (@{$$BROWSER_HELP{$key}} == 2) {
  $help_str = 
    "<a href=\"$$BROWSER_HELP{$key}[1]\">$$BROWSER_HELP{$key}[0]</a>";
}

$show_max=$BROWSER_MAX;
$show_max=100 unless ($show_max > 0);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$timestamp = sprintf "%d.%d.%d %02d:%02d",$mday,$mon,$year+1900,$hour,$min;


print "<TABLE width=\"100%\" cellpadding=3 cellspacing=0 border=0 ",
      " bgcolor=\"#aaaaaa\">",
      "<TR bgcolor=\"#002d5f\">",
      "<TD height=24><FONT color=\"#ffffff\">Sauron DNS browser</FONT>",
      "</TD><TD><FONT color=\"#ffffff\">Zone: $zone</FONT></TD>",
      "<TD align=\"right\"><FONT color=\"#ffffff\">$timestamp</FONT>",
      "</TD></TR><TR><TD colspan=3>";

@search_types=('Host (regexp)',
	       'IP (or CIDR)',
	       'Ethernet address',
	       'Info (regexp)');

if (param('reset')) {
  param('type','');
  param('mask','');
  param('id','');
}

print startform(-method=>'POST',-action=>$selfurl),
      "Search type: ",
      popup_menu(-name=>'type',-values=>\@search_types), " ",
      textfield(-name=>'mask',-size=>40,-maxlength=>40), " ",
      submit(-name=>'search',-value=>'Search'), " ",
      submit(-name=>'reset',-value=>'Clear'),
      " &nbsp; &nbsp; $help_str &nbsp;",end_form,"</TD></TR></TABLE>\n";

if (($id=param('id')) > 0) {
  display_host($id);
} else {
  do_search();
}


if ($debug_mode) {
  print "<hr><FONT size=-1><p>script name: " . script_name() ." $formmode\n";
  print "<br>extra path: " . path_info() ."<br>framemode=$frame_mode\n",
         "<br>cookie='$scookie'\n",
        "<br>s_url='$s_url' '$selfurl'\n",
        "<br>url()=" . url(),
        "<p>remote_addr=$remote_addr",
        "<p>";
  @names = param();
  foreach $var (@names) {
    print "$var = '" . param($var) . "'<br>\n";
  }

  print "<hr><p>\n";
}


print "\n<!-- end of page -->\n", end_html();

exit;
#####################################################################

sub do_search() {
  $type=param('type');
  $mask=param('mask');

  if ($mask =~ /^\s*$/) {
    #alert2("Nothing to search for!");
    return;
  }

  $order = "3";

  if ($type =~ /^Host/) {
    $mask =~ s/\\/\\\\/g;
    $mask =~ s/\'/\\\'/g;
    $rule = " h.domain ~ '$mask' ";
    $alias=1;
  }
  elsif ($type =~ /^Info/) {
    $mask =~ s/\\/\\\\/g;
    $mask =~ s/\'/\\\'/g;
    $rule = " (h.location ~* '$mask' OR h.huser ~* '$mask'" .
            " OR h.dept ~* '$mask' OR h.info ~* '$mask')  ";
  }
  elsif ($type =~ /^IP/) {
    $mask =~ s/\s//g;
    unless (is_cidr($mask)) {
      alert1("Invalid IP (or CIDR)");
      return;
    }
    $rule = " a.ip <<= '$mask' ";
    $order="4";
  }
  elsif ($type =~ /^Ether/) {
    $mask = "\U$mask";
    $mask =~ s/(\s|:)//g;
    print "mask='$mask'";
    unless ($mask =~ /^(\^)?([0-9A-F]+)(\$)?$/) {
      alert1("Invalid Ethernet address");
      return;
    }
    $mask =~ s/[^A-Z0-9\^\$]//g;

    $rule = " h.ether ~ '$mask' ";
    $rule = " h.ether = '$mask' " if ($mask =~ /^[A-F0-9]{12}$/);
  }

  $sql  = "SELECT h.id,h.type,h.domain,a.ip,'',h.ether,h.info,h.huser, ".
          " h.dept,h.location " .
          "FROM hosts h, a_entries a " .
	  "WHERE h.zone=$zoneid AND a.host=h.id AND h.type=1 AND $rule ";

  if ($alias) {
    $sql2 = "SELECT h.id,h.type,h.domain,NULL,b.domain,h.ether,h.info, " .
            " h.huser,h.dept,h.location " .
            "FROM hosts h, hosts b " .
	    "WHERE h.zone=$zoneid AND h.alias=b.id AND " .
	    " h.type=4 AND $rule ";
    $sql3 = "SELECT h.id,h.type,h.domain,NULL,b.domain,h.ether,h.info, " .
            " h.huser,h.dept,h.location " .
            "FROM hosts h, hosts b, arec_entries a " .
	    "WHERE h.zone=$zoneid AND a.host=h.id AND a.arec=b.id AND " .
	    " h.type=7 AND $rule ";
    $sql = "$sql UNION $sql2 UNION $sql3";
  }

  $sql .= " ORDER BY $order";

  #print "<p>sql '$sql'";
  db_query($sql,\@q);
  print "<br> " . db_errormsg()  if (db_errormsg());
  $count = @q;

  unless ($count > 0) {
    alert2("No matching records found.");
    return;
  }

  $count=$show_max if ($count > $show_max);

  print "<TABLE width=\"100%\" cellspacing=2 border=0>\n",
        "<TR bgcolor=\"aaaaee\">",th("#"),th("Domain"),th("IP (or alias)"),
	th("Ether"),th("Info"),"</TR>";
  for $i (0..($count-1)) {
    $color = (($i % 2) ? "#eeeeee" : "#ffffcc");
    $url=self_url();
    $name="<a href=\"$url&id=$q[$i][0]\">$q[$i][2]</a>";
    $type = $q[$i][1];
    if ($type == 1) {
      $ip=$q[$i][3];
      $ip =~ s/\/32//;
      $ether=($q[$i][5] ? "<PRE>$q[$i][5]</PRE>" : '&nbsp;');
      $info=$q[$i][6];
      $info.=", " if ($info && $q[$i][7]);
      $info.=$q[$i][7];
      $info.=", " if ($info && $q[$i][8]);
      $info.=$q[$i][8];
      $info.=", " if ($info && $q[$i][9]);
      $info.=$q[$i][9];
      $info="&nbsp;" unless ($info);
    } else {
      $ip=$q[$i][4];
      $ether=($type==4 ? '(Alias)' : '(AREC alias)');
      $info="&nbsp;";
    }

    print "<TR bgcolor=\"$color\">",td("$i."),
          td($name),td($ip),td($ether),td($info),
          "</TR>\n";
  }
  print "<TR bgcolor=\"#aaaaee\"><TD colspan=5>&nbsp;</TD></TR></TABLE>\n";

  print "<p>Only first $show_max records of $count " .
        "matching records displayed." if (@q > $show_max);
}

sub display_host($) {
  my($id) = @_;

  if (get_host($id,\%host)) {
    alert2("Cannot get host record (id=$id)");
    return;
  }
  $url=self_url();
  $url =~ s/id=\d+//;

  $host_form{alias_l_url}="$url&id=";
  $host_form{alias_a_url}="$url&id=";
  $host_form{alias_d_url}="$url&id=";

  display_form(\%host,\%host_form);
}

#####################################################################
# form_check_field($field,$value,$n) 
#
# checks if given field in form contains valid data
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
      #print "<br>check $p ",param($p);
      return 1 if (form_check_field($rec,param($p),0) ne '');
      #print p,"$p changed! '",$data->{$tag},"' '",param($p),"'\n" if ($data->{$tag} ne param($p));
      $data->{$tag}=param($p);
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
  my($i,$j,$k,$n,$key,$rec,$a,$formdata,$h_bg,$e_str,$p1,$p2,$val,$e,$enum,
     $values,$ip,$t,@lst,%lsth,%tmpl_rec,$maxlen,$len,@q,$tmp);

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
  print ">\n";


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
      get_mx_template_list($zoneid,\%lsth,\@lst);
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
      get_wks_template_list($serverid,\%lsth,\@lst);
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
	if (($id=domain_in_use($zoneid,param($p1."_".($a+1)."_2")))>0) {
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
      get_group_list($serverid,\%lsth,\@lst);
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
  print ">";

  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];

    if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
    else { $h_bg=$SAURON_BGCOLOR; }
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
            $rec->{name},"</TH>\n";
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
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>\n";
    } elsif ($rec->{ftype} == 2) {
      $a=$data->{$rec->{tag}};
      next if ($rec->{no_empty} && @{$a}<2);
      print Tr,td($rec->{name}),
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
      print "</TABLE></TD>\n";
    } elsif ($rec->{ftype} == 3) {
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>\n";
    } elsif ($rec->{ftype} == 4) {
      $val='&nbsp;' if ($val eq '');
      print "<TR><TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "<FONT color=\"$form->{ro_color}\">$val</FONT></TD></TR>\n";
    } elsif ($rec->{ftype} == 5) {
      print Tr,td($rec->{name}),"<TD><TABLE>",Tr;
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
      print "</TABLE></TD>\n";
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
      print "</TABLE></TD>\n";
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


#####################################################################

sub error($) {
  my($msg)=@_;

  print header,start_html("sauron dns browser: error"),
    h1("Error: $msg"),end_html();
  exit;
}


sub error2($) {
  my($msg)=@_;

  print h1("Error: $msg"),end_html();
  exit;
}

sub alert1($) {
  my($msg)=@_;
  print "<H2><FONT color=\"red\">$msg</FONT></H2>";
}

sub alert2($) {
  my($msg)=@_;
  print "<H3><FONT color=\"red\">$msg</FONT></H3>";
}


# eof

