#!/usr/bin/perl
#
# sauron.cgi
# $Id$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000.
#
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
$CGI::DISABLE_UPLOADS =1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts


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
  print STDERR "cannot find configuration file!\n";
  exit(-1);
}

do "$conf_dir/config" || error("cannot load configuration!");

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";

error("invalid directory configuration") 
  unless (-d $CGI_STATE_PATH && -w $CGI_STATE_PATH);

#####################################################################

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$scookie = cookie(-name=>'sauron');
$menu=param('menu');
$menu='login' unless ($menu);

if ($pathinfo ne '') {
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
  $frame_mode=1 if ($pathinfo =~ /^\/frame3/);
}




unless($scookie) {
  $new_cookie=make_cookie();
  print header(-cookie=>$new_cookie);
} else {
  print header();
}

print start_html(-title=>"Sauron $VER",-BGCOLOR=>'white');

unless ($frame_mode) {
  top_menu(0);
  print "<TABLE bgcolor=\"green\" border=\"0\" cellspacing=\"5\" " .
          "width=\"100%\">\n" .
        "<TR><TD align=\"left\" valign=\"top\" bgcolor=\"white\" " .
          "width=\"15%\">\n";
  left_menu(0);
  print "<TD align=\"left\" valign=\"top\" bgcolor=\"white\">\n";
}

login_form("Welcome",$ncookie) unless ($scookie);
load_state($scookie);
login_auth() if ($state{'mode'} eq 'auth');
login_form("Your session timed out",$scookie) unless ($state{'auth'} eq 'yes');

db_connect();

if ($menu eq 'servers') {
  servers();
}
elsif ($menu eq 'zones') {
  zones();
}
else {
  print p,"unknown menu '$menu'";
}

print h1("foo");
print "<p>script name: " . script_name() ." $formmode\n";
print "<p>extra path: " . path_info() ."<br>framemode=$frame_mode\n";
print "<p>cookie='$scookie'\n";
print "<p>s_url='$s_url' '$selfurl'<hr>\n";
print "<p>url()=" . url();
print "<p>self_url()=" . self_url();
@names = param();
foreach $var (@names) {
  print "$var = '" . param($var) . "'<br>\n";
}

print "<hr>state vars<p>\n";
foreach $key (keys %state) {
  print " $key=" . $state{$key} . "<br>";
}
print "<p>\n";
print "</TABLE>\n" unless ($frame_mode);
print end_html();

exit;


#####################################################################
sub servers() {
  $sub=param('sub');

  if ($sub eq 'add') {
    print p,"add...";
  }
  elsif ($sub eq 'del') {
    print p,"del...";
  }
  elsif ($sub eq 'edit') {
    $server=$state{'server'};
    $serverid=$state{'serverid'};
    if ($serverid eq '') {
      print p,"Server not selected";
      goto select_server;
    }

    unless (param('server_re_edit') eq '1') {
      get_server($serverid,\%serv);
      param('srv_name',$serv{'name'});
      param('srv_comment',$serv{'comment'});
      param('srv_hostmaster',$serv{'hostmaster'});
      param('srv_hostname',$serv{'hostname'});
      param('srv_pzone',$serv{'pzone_path'});
      param('srv_szone',$serv{'szone_path'});
      param('srv_namedca',$serv{'named_ca'});
    }
    
    print h2("Edit server: $server"),p,
            startform(-method=>'POST',-action=>$selfurl),
            hidden('menu','servers'),hidden('sub','edit'),
            hidden('server_re_edit',1),
            "<TABLE border=0 width=100%>",
            Tr,td(["Server name",
		textfield(-name=>'srv_name',-value=>param('srv_name'))]),
            Tr,td(["Comments",
		textfield(-name=>'srv_comment',-size=>'60',
			  -value=>param('srv_comment'))]),
            Tr,Tr,
            Tr,td(["Hostmaster",
		textfield(-name=>'srv_hostmaster',-size=>'30',
			  -value=>param('srv_hostmaster'))]),
            Tr,td(["Hostname",
		textfield(-name=>'srv_hostname',-size=>'30',
			  -value=>param('srv_hostname'))]),
            Tr,td(["Primary zone-file path",
		textfield(-name=>'srv_pzone',-size=>'30',
			  -value=>param('srv_pzone'))]),
            Tr,td(["Slave zone-file path",
		textfield(-name=>'srv_szone',-size=>'30',
			  -value=>param('srv_szone'))]),
            Tr,td(["Root-server file",
		textfield(-name=>'srv_namedca',-size=>'30',
			  -value=>param('srv_namedca'))]),
            
            "</TABLE>",
            submit,end_form;
    
  }
  else {
    $server=param('server_list');
    $server=$state{'server'} unless ($server);
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
	delete $state{'zone'};
	delete $state{'zoneid'};
	$state{'server'}=$server;
	$state{'serverid'}=$serverid;
	save_state($scookie);
      }
      print "<TABLE BGCOLOR=#f0f000 WIDTH=\"100%\">",
         Tr,"<TH align=left width=30% bgcolor=white>Server<TH>",
         Tr,td(['Server name',$serv{'name'}]),
         Tr,td(['Server ID',$serv{'id'}]),
         Tr,td(['Comments',$serv{'comment'}]),
         Tr,Tr,"<TH align=left width=30% bgcolor=white>BIND",
         Tr,td(['Hostmaster',$serv{'hostmaster'}]),
         Tr,td(['Hostname',$serv{'hostname'}]),
         Tr,td(['Directory',$serv{'directory'}]),
         Tr,td(['Primary zone-file path',$serv{'pzone_path'}]),
         Tr,td(['Slave zone-file path',$serv{'szone_path'}]),
         Tr,td(['Root-server file',$serv{'named_ca'}]),
         Tr,td('Allow transfer'),td;
      $at=$serv{'allow_transfer'};
      for $i (0 .. $#{$at}) {
	print $$at[$i] . "<br>";
      }
      print Tr,Tr,"<TH align=left width=30% bgcolor=white>DHCP",
            Tr,td('Global settings'),td;
      $dh=$serv{'dhcp'};
      for $i (0 .. $#{$dh}) {
	print $$dh[$i] . "<br>";
      }
      print "</TABLE>";
    }
    else {
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
            br,submit,end_form;
    }
  }
}

sub zones() {
  $sub=param('sub');
  $server=$state{'server'};
  $serverid=$state{'serverid'};
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
  elsif ($sub eq 'edit') {
    print p,"edit...";
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
      
      $type=$zn{'type'};
      if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
      elsif ($type eq 'S') { $type='Slave'; $color='#a0a0f0'; }
      $rev='No';
      $rev='Yes' if ($zn{'reverse'} eq 't');

      print "<TABLE bgcolor=$color width=\"100%\">",
         Tr,"<TH align=left width=30% bgcolor=white>Zone<TH>",
         Tr,td(['Zone name',$zn{'name'}]),
         Tr,td(['Zone Id',$zn{'id'}]),
         Tr,td(['Comments',$zn{'comment'}]),
         Tr,td(['Type',$type]),
         Tr,td(['Reverse',$zn{'reverse'}]),
         Tr,
         Tr,td(['Class',"\U$zn{'class'}"]);
      if ($type eq 'Master') {
	print 
         Tr,td(['Hostmaster',$zn{'hostmaster'}]),
         Tr,td(['Serial',$zn{'serial'}]),
         Tr,td(['Refresh',$zn{'refresh'}]),
         Tr,td(['Retry',$zn{'retry'}]),
         Tr,td(['Expire',$zn{'expire'}]),
         Tr,td(['Minimum',$zn{'minimum'}]),
         Tr,td(['TTL',$zn{'ttl'}]),
	 Tr,td("Name servers (NS)"),td;
	$list=$zn{'ns'};
	for $i (0 .. $#{$list}) {
	  print $$list[$i],"<br>";
	}
	if ($rev eq 'Yes') {
	  print Tr,td(['Reversenet',$zn{'reversenet'}]),
	        Tr,td("Zones used to build reverse"),td;
	  $list2=get_zone_list($serverid);
	  $list=$zn{'reverses'};
	  for $i (0 .. $#{$list}) {
	    $name='N/A';
	    for $j (0 .. $#{$list2}) {
	      $name=$$list2[$j][0] if ($$list[$i] eq $$list2[$j][1]);
	    }
	    print $$list[$i]," ($name)<br>";
	  }
	} else {
	  print Tr,td("Mail exchanges (MX)"),td;
	  $list=$zn{'mx'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	  print Tr,td("Info (TXT)"),td;
	  $list=$zn{'txt'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	  print Tr,td("DHCP"),td;
	  $list=$zn{'dhcp'};
	  for $i (0 .. $#{$list}) {
	    print $$list[$i],"<br>";
	  }
	}
      } else {
	print Tr,td("Masters"),td;
	$list=$zn{'masters'};
	for $i (0 .. $#{$list}) {
	  print $$list[$i],"<br>";
	}
      }
      
      #         Tr,Tr,"<TH align=left width=30% bgcolor=white>BIND",
#         Tr,td(['Hostmaster',$serv{'hostmaster'}]),
#         Tr,td(['Hostname',$serv{'hostname'}]),
#         Tr,td(['Directory',$serv{'directory'}]),
#         Tr,td(['Primary zone-file path',$serv{'pzone_path'}]),
#         Tr,td(['Slave zone-file path',$serv{'szone_path'}]),
#         Tr,td(['Root-server file',$serv{'named_ca'}]),
#         Tr,td('Allow transfer'),td;
#      $at=$serv{'allow_transfer'};
#      for $i (0 .. $#{$at}) {
#	print $$at[$i] . "<br>";
#      }
#      print Tr,Tr,"<TH align=left width=30% bgcolor=white>DHCP",
#            Tr,td('Global settings'),td;
#      $dh=$serv{'dhcp'};
#      for $i (0 .. $#{$dh}) {
#	print $$dh[$i] . "<br>";
#      }

      print "</TABLE>";
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

#####################################################################

sub login_form($$) {
  my($msg,$c)=@_;
  print start_form,h2($msg),p,
        "Login: ",textfield(-name=>'login_name',-maxlength=>'8'),p,
        "Password: ",password_field(-name=>'login_pwd',-maxlength=>'30'),p,
        submit,end_form;

  print "</TABLE>\n" unless($frame_mode);
  print end_html();
  $state{'mode'}='auth';
  save_state($c);
  exit;      
}

sub login_auth() {
  my($u,$p);  

  delete $state{'mode'};
  $u=param('login_name');
  $p=param('login_pwd');
  print "<P><BR><BR><BR><BR><CENTER>";
  if ($u eq '' || $p eq '') {
    print p,h1("login failure");
  } else {
    print p,h1("login ok");
    $state{'auth'}='yes';
    $state{'user'}=$u;
  }

  print p,p,"Select server to continue...</CENTER>";

  print "</TABLE>\n" unless ($frame_mode);
  print end_html();
  save_state($scookie);
  exit;
}

sub top_menu($) {
  my($mode)=@_;
  
  print '<TABLE bgcolor="white" border="0" cellspacing="0" width="100%">' .
        '<TR align="left" valign="bottom"><TD rowspan="2">' . 
	'<IMG src="' .$ICON_PATH . '/logo.png" alt="">';

  print "<TD>mode=$mode<TD>foo<TD>foo<TD>";
  print '<TR align="left" valign="bottom">';
  print "<TD><A HREF=\"$s_url?menu=servers\">servers</A>" .
        "<TD><A HREF=\"$s_url?menu=zones\">zones</A><TD>foo2";
  print "</TABLE>";
}

sub left_menu($) {
  my($mode)=@_;
  my($url);
    
  $url=$s_url;
  print h3("Menu:<br>$menu");
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
  } else {
    print "<p><p>empty menu\n";
  }
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
        "<FRAMESET border=\"1\" cols=\"15%,85%\">\n" .
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
  
  $val=rand 100;
  undef %state;
  $state{'auth'}='no';
  save_state($val);
  $ncookie=$val;
  return cookie(-name=>'sauron',-expires=>'+1h',-value=>$val);
}

sub save_state($id) {
  my($id)=@_;

  open(STATEFILE,">$CGI_STATE_PATH/$id") || error("cannot save state");
  if (keys(%state) > 0) {
    foreach $key (keys %state) {
      print STATEFILE "$key=" . $state{$key} ."\n";
    }
  } else {
      print STATEFILE "auth=no\n";
  }
  close(STATEFILE);
}


sub load_state($) {
  my($id)=@_;
  undef %state;
  $state{'auth'}='no';
  open(STATEFILE,"$CGI_STATE_PATH/$id") || return;
  while (<STATEFILE>) {
    next if /^\#/;
    next unless /^\s*(\S+)\s*\=\s*(\S+)\s*$/;
    $state{$1}=$2;
  }
  close(STATEFILE);
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
