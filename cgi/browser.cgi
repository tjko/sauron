#!/usr/bin/perl -I/opt/sauron
#
# browser.cgi
# $Id:$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2001-2005.
# All Rights Reserved.
#
use CGI qw/:standard *table -no_xhtml/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
# use Net::Netmask;
use NetAddr::IP; # For IPv6.
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::Sauron;

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 10000; # max 10k posts

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;
#$|=1;
$debug_mode = 0;

load_browser_config();


#%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
#	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
#	     8=>'SRV record',9=>'DHCP only',10=>'Zone',
#	     101=>'Host reservation');

%host_types = get_host_types();

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
#  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1,
#   definfo=>['','Default']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1,
   iff=>['type','1'], no_empty=>1},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>1,
   iff=>['type','1'], no_empty=>1},
  {ftype=>1, tag=>'dept', name=>'Department', type=>'text', len=>25, empty=>1,
   iff=>['type','1'], no_empty=>1},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>1, iff=>['type','1'], no_empty=>1},
  {ftype=>0, name=>'Equipment info', iff=>['type','1']},
  {ftype=>1, tag=>'hinfo_hw', name=>'Hardware (HINFO)', type=>'hinfo', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'hinfo_sw', name=>'Software (HINFO)', type=>'hinfo', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac',len=>12,
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
 ],
 tbl_bgcolor => '#ccccff'
);


sub display_host($);
sub do_search();

#####################################################################

db_connect2() || html_error("Cannot estabilish connection with database");
html_error("CGI interface disabled: $res") if (($res=cgi_disabled()));
$VER=sauron_version();

$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$remote_addr = $ENV{'REMOTE_ADDR'};
$remote_host = remote_host();

set_muser('browser');
$bgcolor='white';

print header(-charset=>$BROWSER_CHARSET),
      start_html(-title=>"Sauron DNS Browser $VER",-BGCOLOR=>$bgcolor,
		 -meta=>{'keywords'=>'GNU Sauron DNS DHCP tool'}),
      "\n\n<!-- Sauron DNS Browser v$VER -->\n",
      "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2001-2005. -->\n\n";


$key = $pathinfo;
$key =~ s/[^a-z0-9\-]//g;

html_error2("Invalid parameters!") unless (@{$$BROWSER_CONF{$key}} == 2);
$server=$$BROWSER_CONF{$key}[0];
$zone=$$BROWSER_CONF{$key}[1];

#print "server '$server', zone '$zone'\n";

$serverid=get_server_id($server);
html_error2("Invalid configuration: cannot find server") unless ($serverid>0);
$zoneid=get_zone_id($zone,$serverid);
html_error2("Invalid configuration: cannot find zone") unless ($zoneid>0);

cgi_util_set_zone($zoneid,$zone);
cgi_util_set_server($serverid,$server);

$help_str = ( @{$$BROWSER_HELP{$key}} == 2 ?
	  "<a href=\"$$BROWSER_HELP{$key}[1]\">$$BROWSER_HELP{$key}[0]</a>" :
          "&nbsp;" );

$show_max=($BROWSER_MAX > 0 ? $BROWSER_MAX : 100);

($min,$hour,$mday,$mon,$year) = (localtime(time))[1, 2, 3, 4, 5];
$timestamp = sprintf "%d.%d.%d %02d:%02d",$mday,$mon+1,$year+1900,$hour,$min;


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
	       'MAC address',
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

if (($id=int(param('id'))) > 0) {
  display_host($id);
} else {
  do_search();
}


if ($debug_mode) {
  print "<hr><FONT size=-1><p>script_name: " . script_name(),
  print "<br>path_info: " . path_info(),
        "<br>s_url='$s_url' '$selfurl'\n",
        "<br>url()=" . url(),
        "<p>remote_addr=$remote_addr<p>";
  @names = param();
  foreach $var (@names) { print "$var = '" . param($var) . "'<br>\n"; }
  print "<hr><p>\n";
}

print "\n<!-- end of page -->\n", end_html();
exit;

#####################################################################

sub do_search() {
  $type=param('type');
  $mask=param('mask');

  unless (valid_safe_string($type,255) and valid_safe_string($mask,255)) {
    alert2("Invalid input!");
    return;
  }
  return if ($mask =~ /^\s*$/);
  if ($mask =~ /^[\*\?]$/) {
    alert2("Invalid regular expression");
    return;
  }

  $info_search = 0;
  $order = "3";
  $mask_str = db_encode_str($mask);

  if ($type =~ /^Host/) {
    $rule = " h.domain ~* $mask_str ";
    $alias=1;
  }
  elsif ($type =~ /^Info/) {
    push @irules, "h.location ~* $mask_str"  if ($BROWSER_SHOW_FIELDS =~ /location/);
    push @irules, "h.huser ~* $mask_str"  if ($BROWSER_SHOW_FIELDS =~ /huser/);
    push @irules, "h.dept ~* $mask_str"  if ($BROWSER_SHOW_FIELDS =~ /dept/);
    push @irules, "h.info ~* $mask_str"  if ($BROWSER_SHOW_FIELDS =~ /info/);
    $rule = " (" . join(' OR ',@irules) . ") ";
    $info_search = 1;
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
      alert1("Invalid MAC address");
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
	  "WHERE h.zone=$zoneid AND a.host=h.id AND (h.type=1 OR h.type=9) " .
	  "AND $rule ";


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
  if (db_errormsg()) {
      my $errmsg = db_errormsg();
      if ($errmsg =~ /invalid regular expression/) {
	  alert2("Invalid regular expression");
      } else {
	  print "SQL error: " . db_errormsg() ."<br>";
      }
      return;
  }
  $count = @q;

  $count=$show_max if ($count > $show_max);
  $url=self_url();
  $url =~ s/&sort=\d//g;

  print "<TABLE width=\"100%\" cellspacing=1 cellpadding=1 border=0>",
        "<TR><TD height=2></TD></TR></TABLE>";
  print "<TABLE width=\"100%\" cellspacing=1 cellpadding=1 border=0 " .
        "  bgcolor=\"#ccccff\">\n",
        "<TR bgcolor=\"aaaaee\">",th("#"),
	th("<a href=\"$url&sort=1\">Domain</a>"),
	th("<a href=\"$url&sort=2\">IP (or alias)</a>"),
	th("<a href=\"$url&sort=3\">Ether</a>"),
	th("<a href=\"$url&sort=4\">Info</a>"),
	"</TR>";

  unless ($count > 0) {
    print "</TABLE>";
    alert2("No matching records found.");
    return;
  }

  # get list of networks to hide...
  db_query("SELECT id,net,type FROM nets WHERE type > 0",\@nlist);
# my $blocktable = {};
  my $blocktable = []; # For IPv6.
  for $i (0..$#nlist) {
    next unless ($nlist[$i][2] & 0x01);
#   $tmp = new Net::Netmask($nlist[$i][1]);
#   $tmp->storeNetblock($blocktable);
    push @$blocktable, new NetAddr::IP($nlist[$i][1]); # For IPv6.
  }

  for $i (0..($count-1)) {
    $color = (($i % 2) ? "#eeeeee" : "#ffffcc");
    $name="<a href=\"$url&id=$q[$i][0]\">$q[$i][2]</a>";
    $type = $q[$i][1];
    if ($type == 1 || $type == 9) {
      $ip=$q[$i][3];
      $ip =~ s/\/32//;
      $ip =~ s/\/128//; # For IPv6.
      $ether=($q[$i][5] ? "<PRE>$q[$i][5]</PRE>" : '&nbsp;');
      $info='';

      # check if host ip falls within a net with private flag on
#     if (findNetblock($ip,$blocktable)) {
      if (is_in_netblock($ip,$blocktable)) { # For IPv6.
	#print "PRIVATE: $ip $name<br>";
	next if ($BROWSER_HIDE_PRIVATE || $info_search);
	$info.=$q[$i][7] unless ($BROWSER_HIDE_FIELDS =~ /huser/);
	unless ($BROWSER_HIDE_FIELDS =~ /dept/) {
	    $info.=", " if ($info && $q[$i][8]);
	    $info.=$q[$i][8];
	}
	unless ($BROWSER_HIDE_FIELDS =~ /location/) {
	    $info.=", " if ($info && $q[$i][9]);
	    $info.=$q[$i][9];
	}
      } else {
        $info.=$q[$i][6] if ($BROWSER_SHOW_FIELDS =~ /info/);
	if ($BROWSER_SHOW_FIELDS =~ /huser/) {
	    $info.=", " if ($info && $q[$i][7]);
	    $info.=$q[$i][7];
	}
	if ($BROWSER_SHOW_FIELDS =~ /dept/) {
	    $info.=", " if ($info && $q[$i][8]);
	    $info.=$q[$i][8];
	}
	if ($BROWSER_SHOW_FIELDS =~ /location/) {
	    $info.=", " if ($info && $q[$i][9]);
	    $info.=$q[$i][9];
	}
      }
      $info="&nbsp;" unless ($info);
      $info=substr($info,0,80) if (length($info) > 80);
    } else {
      $ip=$q[$i][4];
      $ether=($type==4 ? '(Alias)' : '(AREC alias)');
      $info="&nbsp;";
    }

    print "<TR bgcolor=\"$color\">",td(($i+1)."."),
          td($name),td($ip),td($ether),td('<font size=-1>'.$info.'</font>'),
          "</TR>\n";
    $printcount++;
  }
  #print "<TR bgcolor=\"#aaaaee\"><TD colspan=5>&nbsp;</TD></TR>";
  print "</TABLE>\n";

  unless ($printcount > 0) {
    alert2("No matching records found.");
    return;
  }

  print "<p>Only first $show_max records of " . @q .
        " matching records displayed." if (@q > $show_max);
}

sub display_host($) {
  my($id) = @_;
  my(@q, @r, $i, $j, $url);

  if (get_host($id,\%host)) {
    alert2("Cannot get host record (id=$id)");
    return;
  }
  $url=self_url();
  $url =~ s/id=\d+//;

  $host{huser}='' unless ($BROWSER_SHOW_FIELDS =~ /huser/);
  $host{dept}='' unless ($BROWSER_SHOW_FIELDS =~ /dept/);
  $host{info}='' unless ($BROWSER_SHOW_FIELDS =~ /info/);
  $host{location}='' unless ($BROWSER_SHOW_FIELDS =~ /location/);

  # check if host has A record within network marked as private
  for $i (1..$#{$host{ip}}) {
    #print "foo$i: $host{ip}[$i][1]<br>";
    db_query("SELECT id,net,type FROM nets " .
             "WHERE server=$serverid AND type > 0 " .
	     " AND '$host{ip}[$i][1]' << net;",\@q);
    for $j (0..$#q) {
      if ($q[$j][2] & 0x01) {
	if ($BROWSER_HIDE_PRIVATE) {
	  print "<h3>Cannot display record: $host{domain}</h3>";
	  return;
	}
	@r = split(/,/,$BROWSER_HIDE_FIELDS);
	for $k (0..$#r) {
	  $host{$r[$k]}='********' if (defined $host{$r[$k]});
	}
	last;
      }
    }
  }

  $host_form{alias_l_url}="$url&id=";
  $host_form{alias_a_url}="$url&id=";
  $host_form{alias_d_url}="$url&id=";

  display_form(\%host,\%host_form);
}



# eof

