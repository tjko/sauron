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

if (-f "/etc/sauron/config-browser") {
  $conf_dir='/etc/sauron';
}
elsif (-f "/opt/etc/sauron/config-browser") {
  $conf_dir='/opt/etc/sauron';
}
elsif (-f "/usr/local/etc/sauron/config-browser") {
  $conf_dir='/usr/local/etc/sauron';
}
else {
  die("cannot find configuration file!\n");
}

do "$conf_dir/config-browser" || die("cannot load configuration!");
die("invalid configuration file") unless ($DB_CONNECT);

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";
do "$PROG_DIR/cgi_util.pl";

%yes_no_enum = (D=>'Default',Y=>'Yes', N=>'No');

%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
	     8=>'SRV record',9=>'DHCP only');


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


#####################################################################

db_connect2() || error("Cannot estabilish connection with database");
if (($res=cgi_disabled())) { error("CGI interface disabled: $res"); }

$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$remote_addr = $ENV{'REMOTE_ADDR'};
$remote_host = remote_host();

set_muser('browser');
$bgcolor='white';

print header(-type=>'text/html; charset=iso-8859-1'),
      start_html(-title=>"Sauron DNS Browser $VER",-BGCOLOR=>$bgcolor,
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

cgi_util_set_zoneid($zoneid);
cgi_util_set_serverid($serverid);

$help_str = ( @{$$BROWSER_HELP{$key}} == 2 ? 
	  "<a href=\"$$BROWSER_HELP{$key}[1]\">$$BROWSER_HELP{$key}[0]</a>" :
          "&nbsp;" );

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
      "</TD></TR>",
      "<TR><TD colspan=3 align=\"right\">$help_str</TD></TR>",
      "<TR><TD colspan=3>";

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
      textfield(-name=>'mask',-size=>30,-maxlength=>40), " ",
      submit(-name=>'search',-value=>'Search'), " ",
      submit(-name=>'reset',-value=>'Clear'),
      end_form,"</TD></TR>",
      "</TABLE>\n";

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
  $mask_str = db_encode_str($mask);

  if ($type =~ /^Host/) {
    $rule = " h.domain ~* $mask_str ";
    $alias=1;
  }
  elsif ($type =~ /^Info/) {
    $rule = " (h.location ~* $mask_str OR h.huser ~* $mask_str" .
            " OR h.dept ~* $mask_str OR h.info ~* $mask_str)  ";
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
    if ($mask =~ /^\s*([0-9A-F]{1,2}):([0-9A-F]{1,2}):([0-9A-F]{1,2}):([0-9A-F]{1,2}):([0-9A-F]{1,2}):([0-9A-F]{1,2})\s*$/) {
      $mask=sprintf("%2s%2s%2s%2s%2s%2s",$1,$2,$3,$4,$5,$6);
      $mask =~ s/ /0/g;
    }
    $mask =~ s/(\s|:)//g;
    #print "mask='$mask'";
    unless ($mask =~ /^(\^)?([0-9A-F]+)(\$)?$/) {
      alert1("Invalid Ethernet address");
      return;
    }
    $mask =~ s/[^A-Z0-9\^\$]//g;

    $rule = " h.ether ~ '$mask' ";
    $rule = " h.ether = '$mask' " if ($mask =~ /^[A-F0-9]{12}$/);
  }
  else {
    return;
  }

  $sql  = "SELECT h.id,h.type,h.domain,a.ip,''::text,h.ether,h.info,h.huser, ".
          " h.dept,h.location " .
          "FROM hosts h, a_entries a " .
	  "WHERE h.zone=$zoneid AND a.host=h.id AND h.type=1 AND $rule ";

  if ($alias) {
    $sql2 = "SELECT h.id,h.type,h.domain,NULL,b.domain,h.ether,h.info, " .
            " h.huser,h.dept,h.location " .
            "FROM hosts h, hosts b " .
	    "WHERE h.zone=$zoneid AND h.alias=b.id AND " .
	    " h.type=4 AND $rule ";

    $sql2b = "SELECT h.id,h.type,h.domain,NULL,h.cname_txt,h.ether,h.info, " .
            " h.huser,h.dept,h.location " .
            "FROM hosts h, hosts b " .
	    "WHERE h.zone=$zoneid AND h.alias=-1 AND " .
	    " h.type=4 AND $rule ";

    $sql3 = "SELECT h.id,h.type,h.domain,NULL,b.domain,h.ether,h.info, " .
            " h.huser,h.dept,h.location " .
            "FROM hosts h, hosts b, arec_entries a " .
	    "WHERE h.zone=$zoneid AND a.host=h.id AND a.arec=b.id AND " .
	    " h.type=7 AND $rule ";
    $sql = "$sql UNION $sql2 UNION $sql2b UNION $sql3";
  }

  if (($sortparam=param('sort'))) {
    $order='3' if ($sortparam == 1);
    $order='4' if ($sortparam == 2);
    $order='6' if ($sortparam == 3);
    $order='7' if ($sortparam == 4);
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
  $url=self_url();
  $url =~ s/&sort=\d//g;

  print "<TABLE width=\"100%\" cellspacing=2 border=0>\n",
        "<TR bgcolor=\"aaaaee\">",th("#"),
	th("<a href=\"$url&sort=1\">Domain</a>"),
	th("<a href=\"$url&sort=2\">IP (or alias)</a>"),
	th("<a href=\"$url&sort=3\">Ether</a>"),
	th("<a href=\"$url&sort=4\">Info</a>"),
	"</TR>";

  for $i (0..($count-1)) {
    $color = (($i % 2) ? "#eeeeee" : "#ffffcc");
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

    print "<TR bgcolor=\"$color\">",td(($i+1)."."),
          td($name),td($ip),td($ether),td($info),
          "</TR>\n";
  }
  print "<TR bgcolor=\"#aaaaee\"><TD colspan=5>&nbsp;</TD></TR></TABLE>\n";

  print "<p>Only first $show_max records of " . @q .
        " matching records displayed." if (@q > $show_max);
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



# eof

