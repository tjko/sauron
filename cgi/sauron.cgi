#!/usr/bin/perl
#
# sauron.cgi
# $Id$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000,2001.
# All Rights Reserved.
#
use Sys::Syslog;
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
use Digest::MD5;

$CGI::DISABLE_UPLOADS =1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts

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

#error("invalid directory configuration") 
#  unless (-d $CGI_STATE_PATH && -w $CGI_STATE_PATH);


%server_form = ( 
 data=>[
  {ftype=>0, name=>'Server' },  
  {ftype=>1, tag=>'name', name=>'Server name', type=>'text', len=>20},
  {ftype=>4, tag=>'id', name=>'Server ID'},
  {ftype=>1, tag=>'comment', name=>'Comments',  type=>'text', len=>60,
   empty=>1},
  {ftype=>0, name=>'DNS'},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'fqdn', len=>30,
   default=>'hostmaster.my.domain.'},
  {ftype=>1, tag=>'hostname', name=>'Hostname',type=>'fqdn', len=>30,
   default=>'ns.my.domain.'},
  {ftype=>1, tag=>'pzone_path', name=>'Primary zone-file path', type=>'path',
   len=>30, empty=>1},
  {ftype=>1, tag=>'szone_path', name=>'Slave zone-file path', type=>'path',
   len=>30, empty=>1, default=>'NS2/'},
  {ftype=>1, tag=>'named_ca', name=> 'Root-server file', type=>'text', len=>30,
   default=>'named.ca'},
  {ftype=>2, tag=>'allow_transfer', name=>'Allow-transfer', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1], 
   elabels=>['IP','comment']},
  {ftype=>0, name=>'DHCP'},
  {ftype=>2, tag=>'dhcp', name=>'Global DHCP', type=>['text','text'], 
   fields=>2, len=>[35,20], empty=>[0,1],elabels=>['dhcptab line','comment']} 
 ],
 bgcolor=>'#eeeebf',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#ca4444'
);

%zone_form = (
 data=>[
  {ftype=>0, name=>'Zone' },
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'domain', len=>30},
  {ftype=>4, tag=>'id', name=>'Zone ID'},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>60,
   empty=>1},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward'}},
  {ftype=>4, tag=>'reverse', name=>'Reverse', type=>'enum', 
   enum=>{f=>'No',t=>'Yes'}, iff=>['type','M']},
  {ftype=>3, tag=>'class', name=>'Class', type=>'enum', conv=>'L',
   enum=>{in=>'IN (internet)',hs=>'HS',hesiod=>'HESIOD',chaos=>'CHAOS'}},
  {ftype=>2, tag=>'masters', name=>'Masters', type=>['cidr','text'], fields=>2,
   len=>[15,45], empty=>[0,1], elabels=>['IP','comment'], iff=>['type','S']},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'domain', len=>30,
   empty=>1, iff=>['type','M']},
  {ftype=>4, tag=>'serial', name=>'Serial', iff=>['type','M']},
  {ftype=>1, tag=>'refresh', name=>'Refresh', type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>1, tag=>'retry', name=>'Rery', type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>1, tag=>'expire', name=>'Expire', type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>1, tag=>'minimum', name=>'Minimum', type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>1, tag=>'ttl', name=>'Default TTL', type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>2, tag=>'ns', name=>'Name servers (NS)', type=>['text','text'], 
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'mx', name=>'Mail exchanges (MX)', 
   type=>['int','text','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1], 
   elabels=>['Priority','MX','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'txt', name=>'Info (TXT)', type=>['text','text'], fields=>2,
   len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'allow_update', 
   name=>'Allow dynamic updates (allow-update)', type=>['cidr','text'],
   fields=>2,
   len=>[40,15], empty=>[0,1], elabels=>['IP','comment']},

  {ftype=>0, name=>'DHCP', iff=>['type','M']},
  {ftype=>2, tag=>'dhcp', name=>'Zone specific DHCP entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment'], iff=>['type','M']}
 ],	      
 bgcolor=>'#eeeebf',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#bfee00'
);



%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record');


%host_form = (
 data=>[	    
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>30},
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>4, tag=>'class', name=>'Class'},
  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10},
  {ftype=>5, tag=>'ip', name=>'IP address', iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>12,
   iff=>['type','1']},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer', iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1},
  {ftype=>0, name=>'Group selections'},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host specific'},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['text','text'], 
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,0,1], 
   elabels=>['Protocol','Services','comment'], iff=>['type','1']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', 
   type=>['priority','domain','text'], fields=>3, len=>[5,30,20], 
   empty=>[0,0,1], 
   elabels=>['Priority','MX','comment'], iff=>['type','[13]']},
  {ftype=>2, tag=>'txt_l', name=>'TXT', type=>['text','text'], 
   fields=>2,
   len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','1']}

 ],
 bgcolor=>'#eeeebf',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#aaaaff'
);


%browse_hosts_form=(
 data=>[
  {ftype=>0, name=>'Browse hosts' },
  {ftype=>3, tag=>'type', name=>'Record type', type=>'enum',
   enum=>\%host_types},
  {ftype=>3, tag=>'order', name=>'Sort order', type=>'enum',
   enum=>{1=>'by hostname',2=>'by IP'}},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'list', listkeys=>'nets_k', 
   list=>'nets'},
  {ftype=>1, tag=>'cidr', name=>'CIDR (block)', type=>'cidr',
   len=>20, empty=>1},
  {ftype=>1, tag=>'domain', name=>'Domain pattern (regexp)', type=>'text',
   len=>40, empty=>1}
 ],
 bgcolor=>'#eeeebf',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#aaaaff'
);

%new_server_form=(
 data=>[
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>20, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ],
 bgcolor=>'#eeeebf',
 border=>'0',		
 width=>'100%',
 nwidth=>'30%',
 heading_bg=>'#aaaaff'
);

sub logmsg($$) {
  my($type,$msg)=@_;

  open(LOGFILE,">>/tmp/sauron.log");
  print LOGFILE localtime(time) . " sauron: $msg\n";
  close(LOGFILE);
  
  #openlog("sauron","cons,pid","user");
  #syslog($type,"foo: %s\n",$msg);
  #closelog();
}


#####################################################################

db_connect2() || error("Cannot estabilish connection with database");

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$menu=param('menu');
#$menu='login' unless ($menu);
$remote_addr = $ENV{'REMOTE_ADDR'};

$scookie = cookie(-name=>'sauron');
if ($scookie) {
  unless (load_state($scookie)) { 
    logmsg("notice","invalid cookie ($scookie) supplied by $remote_addr"); 
    undef $scookie;
  }
}

unless ($scookie) {
  logmsg("notice","new connection from: $remote_addr");
  $new_cookie=make_cookie();
  print header(-cookie=>$new_cookie,-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome (1)",$ncookie);
}

if ($state{'mode'} eq '1' && param('login') eq 'yes') {
  logmsg("debug","login authentication: $remote_addr");
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_auth(); 
}

if ($state{'auth'} ne 'yes' || $pathinfo eq '/login') {
  logmsg("notice","reconnect from: $remote_addr");
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome (2)",$scookie);
}

if ((time() - $state{'last'}) > $USER_TIMEOUT) {
  logmsg("notice","connection timed out for $remote_addr " .
	 $state{'user'});
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Your session timed out. Login again",$scookie);
}

error("Unauthorized Access denied! $remote_addr") 
  if ($remote_addr ne $state{'addr'}) ;

$server=$state{'server'};
$serverid=$state{'serverid'};
$zone=$state{'zone'};
$zoneid=$state{'zoneid'};

unless ($menu) {
  $menu='hosts';
  $menu='zones' unless ($zoneid > 0);
  $menu='servers' unless ($serverid > 0);
}


if ($pathinfo ne '') {
  logout() if ($pathinfo eq '/logout');
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
  $frame_mode=1 if ($pathinfo =~ /^\/frame3/);
}


print header(-type=>'text/html; charset=iso-8859-1'),
      start_html(-title=>"Sauron $VER",-BGCOLOR=>'white',
		 -meta=>{'keywords'=>'GNU Sauron DNS DHCP tool'}),
      "\n\n<!-- Sauron $VER -->\n",
      "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2000,2001. -->\n\n";

unless ($frame_mode) {
  top_menu(0);
  print "<TABLE bgcolor=\"green\" border=\"0\" cellspacing=\"5\" " .
          "width=\"100%\">\n" .
        "<TR><TD align=\"left\" valign=\"top\" bgcolor=\"white\" " .
          "width=\"15%\">\n";
  left_menu(0);
  print "<TD align=\"left\" valign=\"top\" bgcolor=\"white\">\n";
}



if ($menu eq 'servers') { servers_menu(); }
elsif ($menu eq 'zones') { zones_menu(); }
elsif ($menu eq 'login') { login_menu(); }
elsif ($menu eq 'hosts') { hosts_menu(); }
else {
  print p,"unknown menu '$menu'";
}


if ($debug_mode) {
  print "<hr><FONT size=-1><p>script name: " . script_name() ." $formmode\n";
  print "<br>extra path: " . path_info() ."<br>framemode=$frame_mode\n",
         "<br>cookie='$scookie'\n",
        "<br>s_url='$s_url' '$selfurl'\n",
        "<br>url()=" . url(),
#       "<p>remote_addr=$remote_addr",
        "<p>";
  @names = param();
  foreach $var (@names) {
    print "$var = '" . param($var) . "'<br>\n";
  }

  print "<hr>state vars<p>\n";
  foreach $key (keys %state) {
    print " $key=" . $state{$key} . "<br>";
  }
  print "<hr><p>\n";
  foreach $key (keys %server_form) {
    print "$key,";
  }
}
 
print "</TABLE> <!-- end of page -->\n" unless ($frame_mode);
print "<p><hr>Sauron";
print end_html();

exit;
#####################################################################

# SERVERS menu
#
sub servers_menu() {
  $sub=param('sub');

  if ($sub eq 'add') {
    $res=add_magic('srvadd','Server','servers',\%new_server_form,
		   \&add_server,\%data);
    if ($res > 0) {
      print "<p>$res $data{name}";
      #param('server_list',$data{'name'});
      $server=$data{name};
      goto display_new_server;
    }

    return;
  }

  if (($sub eq 'del') && ($serverid > 0)) {
    if (param('srvdel_submit') ne '') {
      if (delete_server($serverid) < 0) {
	print h2("Cannot delete server!");
      } else {
	print h2('Server deleted succesfully!');
	$state{'zone'}=''; $state{'zoneid'}=-1;
	$state{'server'}=''; $state{'serverid'}=-1;
	save_state($scookie);
	goto select_server;
      }
      return;
    }

    get_server($serverid,\%serv);
    print h2('Delete this server?');
    display_form(\%serv,\%server_form);
    print start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','servers'),hidden('sub','del'),
          submit(-name=>'srvdel_submit',-value=>'Delete Server'),end_form;
    return;
  }

  if ($sub eq 'edit') {
    $res=edit_magic('srv','Server','servers',\%server_form,
		    \&get_server,\&update_server,$serverid);
    goto select_zone if ($res == -1);
    return;
  }


  $server=param('server_list');
  $server=$state{'server'} unless ($server);
 display_new_server:
  if ($server && $sub ne 'select') {
    #display selected server info
    $serverid=get_server_id($server);
    if ($serverid < 1) {
      print h3("Cannot select server!"),p;
      goto select_server;
    }
    print h2("Selected server: $server"),p;
    get_server($serverid,\%serv);
    if ($state{'serverid'} ne $serverid) {
      $state{'zone'}='';
      $state{'zoneid'}=-1;
      $state{'server'}=$server;
      $state{'serverid'}=$serverid;
      save_state($scookie);
    }
    display_form(\%serv,\%server_form); # display server record 
    return;
  }

  select_server:
  #display server selection dialig
  $list=get_server_list();
  for $i (0 .. $#{$list}) {
    push @l,$$list[$i][0];
  }
  print h2("Select server:"),p,
    startform(-method=>'POST',-action=>$selfurl),
    hidden('menu','servers'),p,
    "Available servers:",p,
      scrolling_list(-width=>'100%',-name=>'server_list',
		   -size=>'10',-values=>\@l),
      br,submit(-name=>'server_select_submit',-value=>'Select server'),
      end_form;

}


# ZONES menu
#
sub zones_menu() {
  $sub=param('sub');

  if ($server eq '') { 
    print h2("Server not selected!");
    return;
  }

  if ($sub eq 'add') {
    print p,"add...";
  }
  elsif ($sub eq 'del') {
    print p,"del...";
  }
  elsif (($sub eq 'edit') || ($sub eq 'Edit')) {
    $res=edit_magic('zn','Zone','zones',\%zone_form,\&get_zone,\&update_zone,
		    $zoneid);
    goto select_zone if ($res == -1);
    return;
  }
  else {
    $zone=param('selected_zone');
    $zone=$state{'zone'} unless ($zone);
    if ($zone && $sub ne 'select') {
      #display selected zone info
      $zoneid=get_zone_id($zone,$serverid);
      if ($zoneid < 1) {
	print h3("Cannot select zone '$zone'!"),p;
	goto select_zone;
      }
      print h2("Selected zone: $zone"),p;
      get_zone($zoneid,\%zn);
      $state{'zone'}=$zone;
      $state{'zoneid'}=$zoneid;
      save_state($scookie);

      display_form(\%zn,\%zone_form);
      
    }
    else {
     select_zone:
      #display zone selection list
      print h2("Zones for server: $server"),
            p,"<TABLE width=90% bgcolor=white border=0>",
            Tr,th(['Zone','Id','Type','Reverse']);
            
      $list=get_zone_list($serverid);
      for $i (0 .. $#{$list}) {
	$type=$$list[$i][2];
	if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
	elsif ($type eq 'S') { $type='Slave'; $color='#a0a0f0'; }
	$rev='No';
	$rev='Yes' if ($$list[$i][3] eq 't');
	$id=$$list[$i][1];
	$name=$$list[$i][0];
	
	print "<TR bgcolor=$color>",td([
	  "<a href=\"$selfurl?menu=zones&selected_zone=$name\">$name</a>",
					$id,$type,$rev]);
      }
      
      print "</TABLE>";

    }
  }
}


# HOSTS menu
#
sub hosts_menu() {
  unless ($serverid) {
    print h2("Server not selected!");
    return;
  }
  unless ($zoneid) {
    print h2("Zone not selected!");
    return;
  }
  
  $sub=param('sub');
  
  if ($sub eq 'Edit') {
    $res=edit_magic('h','Host','hosts',\%host_form,\&get_host,\&update_host,
		   param('h_id'));
    goto browse_hosts if ($res == -1);
    return;
  }
  elsif ($sub eq 'viewhost') {
    $id=param('id');
    if (get_host($id,\%host)) {
      print h2("Cannot get host record (id=$id)!");
      return;
    }

    display_form(\%host,\%host_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id),
          submit(-name=>'sub',-value=>'Edit')," ",
          submit(-name=>'sub',-value=>'Delete'),end_form;
  }
  elsif ($sub eq 'browse') {
    %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2);
    if (form_check_form('bh',\%bdata,\%browse_hosts_form)) {
      print p,'<FONT color="red">Invalid parameters.</FONT>';
      goto browse_hosts;
    }

    undef $typerule;
    $limit=param('bh_psize');
    $page=param('bh_page');
    $offset=$page*$limit;

    $type=param('bh_type');
    if (param('bh_type') > 0) {
      $typerule=" AND a.type=".param('bh_type')." ";
    } else {
      $typerule2=" AND (a.type=1 OR a.type=6) ";
    }
    undef $netrule; 
    if (param('bh_net') ne 'ANY') {
      $netrule=" AND b.ip << '" . param('bh_net') . "' ";
    }
    if (param('bh_cidr')) {
      $netrule=" AND b.ip <<= '" . param('bh_cidr') . "' ";
    }
    undef $domainrule;
    if (param('bh_domain') ne '') {
      $tmp=param('bh_domain');
      $tmp =~ s/\\/\\\\/g;
      $domainrule=" AND a.domain ~ '$tmp' "; 
    }
    if (param('bh_order') == 1) { $sorder='5,1';  }
    else { $sorder='1,5'; }

    if (param('bh_cidr') || param('bh_net') ne 'ANY') {
      $type=1;
    }

    undef @q;
    $fields="a.id,a.type,a.domain,a.ether,a.info";
    $sql1="SELECT b.ip,'',$fields FROM hosts a,rr_a b " .
	  "WHERE a.zone=$zoneid AND b.host=a.id $typerule $typerule2 " .
	  " $netrule $domainrule ";
    $sql2="SELECT '0.0.0.0'::cidr,'',$fields FROM hosts a " .
          "WHERE a.zone=$zoneid AND (a.type!=1 AND a.type!=6 AND a.type!=4) " .
	  " $typerule $domainrule ";
    $sql3="SELECT '0.0.0.0'::cidr,b.domain,$fields FROM hosts a,hosts b " .
          "WHERE a.zone=$zoneid AND a.alias=b.id AND a.type=4 " .
	  " $domainrule ";
    $sql4="SELECT '0.0.0.0'::cidr,a.cname_txt,$fields FROM hosts a  " .
          "WHERE a.zone=$zoneid AND a.alias=-1 AND a.type=4 " .
	  " $domainrule ";

    if ($type == 1 || $type == 6) { 
      $sql="$sql1 ORDER BY $sorder"; 
    } elsif ($type == 4) { 
      $sql="$sql3 UNION $sql4 ORDER BY $sorder"; 
    } elsif ($type == 0) { 
      $sql="$sql1 UNION $sql2 UNION $sql3 UNION $sql4 ORDER BY $sorder"; 
    } 
    else { $sql="$sql2 ORDER BY $sorder"; }
    $sql.=" LIMIT $limit OFFSET $offset;";
    #print p,$sql;
    db_query($sql,\@q);
    $count=scalar @q;
    print "<TABLE width=\"100%\" cellpadding=1 BGCOLOR=\"#eeeeff\">",
          Tr,"<TD colspan=5 bgcolor=#aadaff><B>Zone:</B> $zone</TD>",
          Tr,"<TD align=right colspan=5 bgcolor=#aadaff>Page: " .
	      ($page+1)."</TD>",
          Tr,Tr,
          "<TR bgcolor=#aaaaff>",th(['Hostname','Type','IP','Ether','Info']);
    for $i (0..$#q) {
      $type=$q[$i][3];
      ($ip=$q[$i][0]) =~ s/\/\d{1,2}$//g;
      $ip="(".add_origin($q[$i][1],$zone).")" if ($type==4);
      $ip='N/A' if ($ip eq '0.0.0.0');
      $ether=$q[$i][5];
      $ether='N/A' unless($ether);
      #$hostname=add_origin($q[$i][4],$zone);
      $hostname="<A HREF=\"$selfurl?menu=hosts&sub=viewhost&id=$q[$i][2]\">".
	        "$q[$i][4]</A>";
      print Tr,td([$hostname,$host_types{$q[$i][3]},$ip,
		   "<PRE>$ether</PRE>",$q[$i][6]]);
      last if ($i > 50);
    }
    print "</TABLE><BR><CENTER>[";

    $params="bh_type=".param('bh_type')."&bh_order=".param('bh_order').
            "&bh_net=".param('bh_net')."&bh_cidr=".param('bh_cidr').
	    "&bh_domain=".param('bh_domain')."&bh_psize=".param('bh_psize');
    
    if ($page > 0) {
      $npage=$page-1;;
      print "<A HREF=\"$selfurl?menu=hosts&sub=browse&bh_page=$npage&".
	      "$params\">prev</A>";
    } else { print "prev"; }
    print "] [";
    if ($count >= $limit) {
      $npage=$page+1;
      print "<A HREF=\"$selfurl?menu=hosts&sub=browse&bh_page=$npage&".
	      "$params\">next</A>";
    } else { print "next"; }
    
    print "]</CENTER><BR>";
  }
  else {
  browse_hosts:
    param('sub','browse');
    #$nethash=get_nets($serverid);
    $nets=get_net_list($serverid,1);
    undef %nethash; undef @netkeys;
    $nethash{'ANY'}='Any net';
    $netkeys[0]='ANY';
    for $i (0..$#{$nets}) { 
      #print p,$$nets[$i][0]; 
      $nethash{$$nets[$i][0]}="$$nets[$i][0] - $$nets[$i][2]";
      push @netkeys, $$nets[$i][0];
    }
    %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2);
    print start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','browse'),
          hidden('bh_page','0'),hidden('bh_psize','50');
    form_magic('bh',\%bdata,\%browse_hosts_form);
    print submit(-name=>'bh_submit',-value=>'Search'),end_form;
  }
}


# LOGIN menu
#
sub login_menu() {
  $sub=param('sub');

  if ($sub eq 'login') {
    print h2("Login as another user?"),p,
          "Click <a href=\"$s_url/login\">here</a> ",
          "if you want to login as another user.";
  }
  elsif ($sub eq 'logout') {
    print h2("Logout from the system?"),p,
          "Click <a href=\"$s_url/logout\">here</a> ",
          "if you want to logout.";
  }
  elsif ($sub eq 'passwd') {
    print h2("Change password"),p,
          "Click <a href=\"$s_url/logout\">here</a> ",
          "if you want to logout.";
  }
  elsif ($sub eq 'save') {
    $uid=$state{'uid'};
    return if ($uid < 1);
    $sqlstr="UPDATE users SET server=$serverid,zone=$zoneid " .
            "WHERE id=$uid;";
    $res=db_exec($sqlstr);
    if ($res < 0) {
      print h3('Saving defaults failed!');
    } else {
      print h3('Defaults saved succesfully!');
    }
  }
  else {
    #print p,"Unknown menu selection!";
  }
}

#####################################################################

sub edit_magic($$$$$$$) {
  my($prefix,$name,$menu,$form,$get_func,$update_func,$id) = @_;
  my(%h);

  if (($id eq '') || ($id < 1)) {
    print h2("$name id not specified!");
    return -1;
  }
  
  if (param($prefix . '_submit') ne '') {
    if(&$get_func($id,\%h) < 0) {
      print h2("Cannot find $name record anymore! ($id)");
      return -2;
    }
    unless (($res=form_check_form($prefix,\%h,$form))) {
      $res=&$update_func(\%h);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("$name record update failed!"),
	      "<br>result code=$res</FONT>";
      } else {
	print h2("$name record succefully updated:");
	&$get_func($id,\%h);
	display_form(\%h,$form);
	return 0;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  unless (param($prefix . '_re_edit') eq '1') {
    if (&$get_func($id,\%h)) {
      print h2("Cannot get $name record (id=$id)!");
      return;
    }
  }

  print h2("Edit $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Edit');
  form_magic($prefix,\%h,$form);
  print submit(-name=>$prefix . '_submit',-value=>'Make changes'),end_form;

  return 0;
}

sub add_magic($$$$$$) {
  my($prefix,$name,$menu,$form,$add_func,$data) = @_;
  my(%h);

  
  if (param($prefix . '_submit') ne '') {
    unless (($res=form_check_form($prefix,\%h,$form))) {
      $res=&$add_func(\%h);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("Adding $name record failed!"),
	      "<br>result code=$res</FONT>";
      } else {
	print h3("$name record succefully added");
	%$data=%h;
	return $res;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  print h2("New $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Edit');
  form_magic($prefix,\%h,$form);
  print submit(-name=>$prefix . '_submit',-value=>"Create $name"),end_form;
  return 0;
}

sub logout() {
  my($c,$u);
  $u=$state{'user'};
  logmsg("notice","user ($u) logged off from $remote_addr");
  $c=cookie(-name=>'sauron',-value=>'logged off',-expires=>'+1s',
	    -path=>$s_url);
  remove_state($scookie);
  print header(-target=>'_top',-cookie=>$c),
        start_html(-title=>"Sauron Logout",-BGCOLOR=>'white'),
        h1("Sauron"),p,p,"You are now logged out...",
        end_html();
  exit;
}

sub login_form($$) {
  my($msg,$c)=@_;
  my($host);

  $host='localhost???';
  $host=$1 if (self_url =~ /https?\:\/\/([^\/]+)\//);

  print start_form,"<CENTER>",h1("Sauron at $host"),hr,h2($msg),p,"<TABLE>",
        Tr,td("Login:"),td(textfield(-name=>'login_name',-maxlength=>'8')),
        Tr,td("Password:"),
                   td(password_field(-name=>'login_pwd',-maxlength=>'30')),
              "</TABLE>",
        hidden(-name=>'login',-default=>'yes'),
        submit,end_form,p,"</CENTER>";

  #print "</TABLE>\n" unless($frame_mode);
  print p,hr,"You should have cookies enabled for this site...",end_html();
  $state{'mode'}='1';
  $state{'auth'}='no';
  save_state($c);
  exit;      
}

sub login_auth() {
  my($u,$p);  
  my(%user,$ctx,$salt,$pass,$digest,%h);
  
  $state{'auth'}='no';
  $state{'mode'}='0';
  $u=param('login_name');
  $p=param('login_pwd');
  $p=~s/\ \t\n//g;
  print "<P><BR><BR><BR><BR><CENTER>";
  if ($u eq '' || $p eq '') {
    print p,h1("Username or password empty!");
  } else {
    unless (get_user($u,\%user)) {
      $salt='';
      if ($user{'password'} =~ /^MD5:(\S+)\:(\S+)$/) {
	$salt=$1; 
      }
      #print p,h1("user ok<br>" . $user{'password'});
      if ($salt ne '') {
	$digest=pwd_crypt($p,$salt);
	if ($digest eq $user{'password'}) {
	  $state{'auth'}='yes';
	  $state{'user'}=$u;
	  $state{'uid'}=$user{'id'};
	  $state{'login'}=time();
	  $state{'serverid'}=$user{'server'};
	  $state{'zoneid'}=$user{'zone'};
	  if ($state{'serverid'} > 0) {
	    $state{'server'}=$h{'name'} 
	      unless(get_server($state{'serverid'},\%h));
	  }
	  if ($state{'zoneid'} > 0) {
	    $state{'zone'}=$h{'name'} 
	      unless(get_zone($state{'zoneid'},\%h));
	  }
	  print p,h1("Login ok!"),p,
	      "Come in... <a href=\"$s_url/frames\">frames version</a> ",
              "or <a href=\"$s_url\">table version (recommended for now)</a>";
	  logmsg("notice","user ($u) logged in from " . $ENV{'REMOTE_ADDR'});
	}
      }
    } 
  }

  print p,h1("Login failed."),p,"<a href=\"$selfurl\">try again</a>"
    unless ($state{'auth'} eq 'yes');

  print p,p,"</CENTER>";

  print "</TABLE>\n" unless ($frame_mode);
  print end_html();
  save_state($scookie);
  exit;
}

sub top_menu($) {
  my($mode)=@_;
  
  print	'<IMG src="' .$ICON_PATH . '/logo.png" alt="Sauron">';

  print '<TABLE border="0" cellspacing="0" width="100%">';
#        '<TR align="left" valign="bottom"><TD rowspan="1">' . 
#	'<IMG src="' .$ICON_PATH . '/logo.png" alt=""></TD>';

  #print "<TD>mode=$mode<TD>foo<TD>foo<TD>";
  print '<TR bgcolor="#002d5f" align="left" valign="center">',
        '<TD width="17%" height="24">',
        '<FONT color="white">&nbsp;GNU/Sauron</FONT></TD>',
        '<TD><FONT color="#ffffff">',
        "<A HREF=\"$s_url?menu=hosts\"><FONT color=\"#ffffff\">Hosts</FONT></A> | " ,
        "<A HREF=\"$s_url?menu=zones\"><FONT color=\"#ffffff\">Zones</FONT></A> | ",
        "<A HREF=\"$s_url?menu=servers\"><FONT color=\"#ffffff\">Servers</FONT></A> | ",
	"<A HREF=\"$s_url?menu=login\"><FONT color=\"#ffffff\">login</FONT></A> | ";
  print "</FONT></TABLE>";
}

sub left_menu($) {
  my($mode)=@_;
  my($url,$w);
  
  $w="\"100\"";
  
  $url=$s_url;
  print "<BR><TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" " .
        "cellspacing=\"0\" cellpadding=\"0\">", # Tr,th(h4("$menu")),
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " ,
	 "border=\"0\">",
         "<TR><TH><FONT color=\"#ffffff\">$menu</FONT></TH></TR>",
	  "<TR><TD BGCOLOR=\"#eeeeee\">";
  #print "<p>mode=$mode";

  if ($menu eq 'servers') {
    $url.='?menu=servers';
    print p,"<a href=\"$url\">Current server</a><br>",
          "<a href=\"$url&sub=select\">Select server</a><br>",
          p,"<a href=\"$url&sub=add\">Add server</a><br>",
          "<a href=\"$url&sub=del\">Delete server</a><br>",
          "<a href=\"$url&sub=edit\">Edit server</a><br>";
  } elsif ($menu eq 'zones') {
    $url.='?menu=zones';
    print p,"<a href=\"$url\">Current zone</a><br>",
          p,"<a href=\"$url&sub=select\">Select zone</a><br>",
          p,"<a href=\"$url&sub=add\">Add zone</a><br>",
          "<a href=\"$url&sub=del\">Delete zone</a><br>",
          "<a href=\"$url&sub=edit\">Edit zone</a><br>";
  } elsif ($menu eq 'hosts') {
    $url.='?menu=hosts';
    print p,"<a href=\"$url\">Browse hosts</a><br>",
          "<a href=\"$url&sub=edit\">Edit hosts</a><br>";
  } elsif ($menu eq 'login') {
    $url.='?menu=login';
    print "<a href=\"$url&sub=login\">Login</a>",
          "<br><a href=\"$url&sub=logout\">Logout</a>",
          "<br><a href=\"$url&sub=passwd\">Change password</a>",
          "<br><a href=\"$url&sub=save\">Save defaults</a>";
  } else {
    print "<p><p>empty menu\n";
  }
  print "</TR></TABLE></TD></TABLE><BR>";

  print "<TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" cellspacing=\"0\" " .
        "cellpadding=\"0\">", #<TR><TD><H4>Current selections</H4></TD></TR>",
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " .
	"border=\"0\">",
	"<TR><TH><FONT color=white size=-1>Current selections</FONT></TH></TR>",
	"<TR><TD BGCOLOR=\"white\">";

  print "<FONT size=-1>",
        "Server: $server",br,
        "Zone: $zone",br,
        "</FONT>";

  print "</FONT></TABLE></TD></TR></TABLE><BR>";

  
}

sub frame_set() {
  print header;
  
  print "<HTML><FRAMESET border=\"1\" rows=\"130,*\">\n" .
        "  <FRAME src=\"$script_name/frame1\" noresize>\n" .
        "  <FRAME src=\"$script_name/frames2\" name=\"bottom\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}

sub frame_set2() {
  print header;
  $menu="?menu=" . param('menu') if ($menu);
  
  print "<HTML>" .
        "<FRAMESET border=\"0\" cols=\"15%,85%\">\n" .
	"  <FRAME src=\"$script_name/frame2$menu\" name=\"menu\" noresize>\n" .
        "  <FRAME src=\"$script_name/frame3$menu\" name=\"main\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}


sub frame_1() {
  print header,
        start_html(-title=>"sauron: top menu",-BGCOLOR=>'white',
		   -target=>'bottom');

  $s_url .= '/frames2';
  top_menu(1);

  print end_html();
  exit 0;
}

sub frame_2() {
  print header,
        start_html(-title=>"sauron: left menu",-BGCOLOR=>'white',
		   -target=>'main');

  $s_url .= '/frame3';
  left_menu(1);

  print end_html();
  exit 0;
}

#####################################################################
sub make_cookie() {
  my($val);
  my($ctx);

  $val=rand 100000;

  $ctx=new Digest::MD5;
  $ctx->add($val);
  $ctx->add($$);
  $ctx->add(time);
  $ctx->add(rand 1000000);
  $val=$ctx->hexdigest;
  
  undef %state;
  $state{'auth'}='no';
  #$state{'host'}=remote_host();
  $state{'addr'}=$ENV{'REMOTE_ADDR'};
  save_state($val);
  $ncookie=$val;
  return cookie(-name=>'sauron',-expires=>'+1d',-value=>$val,-path=>$s_url);
}

sub save_state($id) {
  my($id)=@_;
  my(@q,$res,$s_auth,$s_addr,$other,$s_mode);

  undef @q;
  db_query("SELECT uid FROM utmp WHERE cookie='$id';",\@q);
  unless (@q > 0) {
    db_exec("INSERT INTO utmp (uid,cookie,auth) VALUES(-1,'$id',false);");
  }
  
  $s_auth='false';
  $s_auth='true' if ($state{'auth'} eq 'yes');
  $s_mode=0;
  $s_mode=$state{'mode'} if ($state{'mode'});
  $s_addr=$state{'addr'};
  $other='';
  if ($state{'uid'}) { $other.=", uid=".$state{'uid'}." ";  }
  if ($state{'serverid'}) {
    $other.=", serverid=".$state{'serverid'}." ";
    $other.=", server='".$state{'server'}."' ";
  }
  if ($state{'zoneid'}) {
    $other.=", zoneid=".$state{'zoneid'}." ";
    $other.=", zone='".$state{'zone'}."' ";
  }
  if ($state{'user'}) { $other.=", uname='".$state{'user'}."' "; }
  if ($state{'login'}) { $other.=", login=".$state{'login'}." "; }

  $res=db_exec("UPDATE utmp SET auth=$s_auth, addr='$s_addr', mode=$s_mode " .
	       " $other " .
	       "WHERE cookie='$id';");

  error("cannot save stat '$id'") if ($res < 0);
}


sub load_state($) {
  my($id)=@_;
  my(@q);

  undef %state;
  $state{'auth'}='no';

  undef @q;
  db_query("SELECT uid,addr,auth,mode,serverid,server,zoneid,zone," .
	   "uname,last " .
	   "FROM utmp WHERE cookie='$id';",\@q);
  if (@q > 0) {
    $state{'uid'}=$q[0][0];
    $state{'addr'}=$q[0][1];
    $state{'addr'} =~ s/\/32\s*$//;
    $state{'auth'}='yes' if ($q[0][2] eq 't');
    $state{'mode'}=$q[0][3];
    if ($q[0][4] > 0) {
      $state{'serverid'}=$q[0][4];
      $state{'server'}=$q[0][5];
    }
    if ($q[0][6] > 0) {
      $state{'zoneid'}=$q[0][6];
      $state{'zone'}=$q[0][7];
    }
    $state{'user'}=$q[0][8] if ($q[0][8] ne '');
    $state{'last'}=$q[0][9];
    
    db_exec("UPDATE utmp SET last=" . time() . " WHERE cookie='$id';");
    return 1;
  }

  return 0;
}

sub remove_state($) {
  my($id) = @_;

  db_exec("DELETE FROM utmp WHERE cookie='$id';");
  undef %state;
}

############################################################################


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
  } elsif ($type eq 'enum') {
    return '';
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
  } else {
    return "unknown typecheck for form_check_field: $type !";
  }

  return '';
}


#####################################################################
# form_check_form($prefix,$data,$form)
# 
# checks if form contains valid data and updates 'data' hash 
#
sub form_check_form($$$) {
  my($prefix,$data,$form) = @_;
  my($formdata,$i,$j,$k,$type,$p,$p2,$tag,$list,$id,$ind,$f,$new);

  $formdata=$form->{data};
  for $i (0..$#{$formdata}) {
    $rec=$$formdata[$i];
    $type=$rec->{ftype};
    $tag=$rec->{tag};
    $p=$prefix."_".$tag;

    if ($type == 1) {
      #print "<br>check $p ",param($p);
      return 1 if (form_check_field($rec,param($p),0) ne '');
      #print p,"$p changed! '",$data->{$tag},"' '",param($p),"'\n" if ($data->{$tag} ne param($p));
      $data->{$tag}=param($p);
    } 
    elsif  ($type == 2) {
      $f=$rec->{fields};
      $a=param($p."_count");
      $a=0 if (!$a || $a < 0);
      for $j (1..$a) {
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
	    for $k (1..$f) { $$new[$k]=param($p2."_".$k); }
	    push @{$list}, $new;
	  } else {
	    for $k (1..$f) {
	      if (param($p2."_".$k) ne $$list[$ind][$k]) {
		$$list[$ind][$f+1]=1;
		$$list[$ind][$k]=param($p2."_".$k);
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
    elsif ($type == 6 || $type == 7) {
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
     $values,$ip,$t,@lst,%lsth,%tmpl_rec);

  $formdata=$form->{data};
  if ($form->{heading_bg}) { $h_bg=$form->{heading_bg}; }
  else { $h_bg=$SAURON_BGCOLOR; }


  # initialize fields
  unless (param($prefix . "_re_edit") eq '1' || ! $data) {
    for $i (0..$#{$formdata}) {
      $rec=$$formdata[$i];
      $val=$data->{$rec->{tag}};
      $val="\L$val" if ($rec->{conv} eq 'L');
      $val="\U$val" if ($rec->{conv} eq 'U');
      $p1=$prefix."_".$rec->{tag};

      if ($rec->{ftype} == 1) { 
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 2) {
	$a=$data->{$rec->{tag}};
	for $j (1..$#{$a}) {
	  param($p1."_".$j."_id",$$a[$j][0]);
	  for $k (1..$rec->{fields}) {
	    param($p1."_".$j."_".$k,$$a[$j][$k]);
	  }
	}
	param($p1."_count",$#{$a});
      }
      elsif ($rec->{ftype} == 0) {
	# do nothing...
      }
      elsif ($rec->{ftype} == 3) {
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 4) {
	#$val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');
	param($p1,$val);
      }
      elsif ($rec->{ftype} == 2 || $rec->{ftype} == 5) {
	$rec->{fields}=5;
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
	  param($p1."_".$j."_4",$$a[$j][4]);
	}
	param($p1."_count",$#{$a});
      }
      elsif ($rec->{ftype} == 6 || $rec->{ftype} == 7) {
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

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" BGCOLOR=\"$h_bg\">",
             $rec->{name},"</TH></TR>\n";
    } elsif ($rec->{ftype} == 1) {
      print "<TR>",td($rec->{name}),"<TD>",
            textfield(-name=>$p1,-size=>$rec->{len},-value=>param($p1));

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
	$values=[sort keys %{$enum}];
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
      print "<TR>",td($rec->{name}),td($val),hidden($p1,param($p1)),"</TR>";
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
      print td('IP'),td('Reverse'),td('Forward'),td('Comments'),"</TR>";

      for $j (1..$a) {
	$p2=$p1."_".$j;
	print "<TR>",hidden(-name=>$p2."_id",param($p2."_id"));

	$n=$p2."_1";
	print "<TD>",textfield(-name=>$n,-size=>15,-value=>param($n));
        print "<FONT size=-1 color=\"red\"><BR>",
              form_check_field($rec,param($n),1),"</FONT></TD>";
	$n=$p2."_2";
	print td(checkbox(-label=>'Reverse',-name=>$n,-checked=>param($n)));
	$n=$p2."_3";
	print td(checkbox(-label=>'Forward',-name=>$n,-checked=>param($n)));

        print td(checkbox(-label=>' Delete',
	             -name=>$p2."_del",-checked=>param($p2."_del") )),
	     "</TR>";
      }
      #print Tr,Tr,Tr,Tr;
      $j=$a+1;
      $n=$prefix."_".$rec->{tag}."_".$j."_1";
      print "<TR>",td(textfield(-name=>$n,-size=>15,-value=>param($n)));
      
      print td(submit(-name=>$prefix."_".$rec->{tag}."_add",-value=>'Add'));
      print "</TR></TABLE></TD></TR>\n";
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
  my($ip,$ipinfo,$com);

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

    $val=$data->{$rec->{tag}};
    $val="\L$val" if ($rec->{conv} eq 'L');
    $val="\U$val" if ($rec->{conv} eq 'U');
    $val=${$rec->{enum}}{$val}  if ($rec->{type} eq 'enum');

    if ($rec->{ftype} == 0) {
      print "<TR><TH COLSPAN=2 ALIGN=\"left\" ",
            "BGCOLOR=\"$h_bg\">",
            $rec->{name},"</TH>\n";
    } elsif ($rec->{ftype} == 1) {
      #print Tr,td([$rec->{name},$data->{$rec->{tag}}]);
      $val='&nbsp;' if ($val eq '');
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>\n";
    } elsif ($rec->{ftype} == 2) {
      print Tr,td($rec->{name}),"<TD><TABLE>",Tr;
      $a=$data->{$rec->{tag}};
      for $k (1..$rec->{fields}) { 
	#print "<TH>",$$a[0][$k-1],"</TH>"; 
      }
      for $j (1..$#{$a}) {
	print Tr;
	for $k (1..$rec->{fields}) { print td($$a[$j][$k]); }
      }
      print "</TABLE></TD>\n";
    } elsif ($rec->{ftype} == 4 || $rec->{ftype} == 3) {
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>\n";
    } elsif ($rec->{ftype} == 5) {
      print Tr,td($rec->{name}),"<TD><TABLE>",Tr;
      $a=$data->{$rec->{tag}};
      for $j (1..$#{$a}) {
	$com=$$a[$j][4];
	$ip=$$a[$j][1];
	$ip=~ s/\/\d{1,2}$//g;
	$ipinfo='';
	$ipinfo.=' (no reverse)' if ($$a[$j][2] ne 't');
	$ipinfo.=' (no A record)' if ($$a[$j][3] ne 't');
	print Tr,td($ip),td($ipinfo),td($com);
      }
      print "</TABLE></TD>\n";
    } elsif (($rec->{ftype} == 6) || ($rec->{ftype} ==7)) {
      print "<TR>",td($rec->{name});
      if ($val > 0) { 
	print "<TD>";
	print_mx_template($data->{mx_rec}) if ($rec->{ftype}==6);
	print_wks_template($data->{wks_rec}) if ($rec->{ftype}==7);
	print "</TD>";
      } else { print td("Not selected"); }
      print "</TR>";
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
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaff00\"><TR><TD colspan=\"2\">",
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
  print "<TABLE WIDTH=\"95%\" BGCOLOR=\"#aaff00\"><TR><TD colspan=\"2\">",
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
  
  print header,
        start_html("sauron: error"),
        h1("Error: $msg"),
        end_html();
  exit;
}


sub error2($) {
  my($msg)=@_;
  
  print h1("Error: $msg"),
        end_html();
  exit;
}
