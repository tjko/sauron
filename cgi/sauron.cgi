#!/usr/bin/perl
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000.
#
# $Id$
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
$self_url = $s_url . $pathinfo;
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

}
else {
  print p,"unknown menu '$menu'";
}

print h1("foo");
print "<p>script name: " . script_name() ." $formmode\n";
print "<p>extra path: " . path_info() ."<br>framemode=$frame_mode\n";
print "<p>cookie='$scookie'\n";
print "<p>s_url='$s_url' '$self_url'<hr>\n";
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
    print p,"edit...";
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
      $state{'server'}=$server;
      $state{'serverid'}=$serverid;
      save_state($scookie);
      print "<TABLE border=1>",Tr,th(['Key','Value']);
      foreach $key (keys %serv) {
	print Tr,td([$key,$serv{$key}]);
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
            startform(-method=>'POST',-action=>$self_url),
            hidden('menu','servers'),p,
            "Available servers:",p,
            scrolling_list(-width=>'100%',-name=>'server_list',
			   -size=>'10',-values=>@l),
            br,submit,end_form;
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
    print p,"<a href=\"$url\">Select zone</a><br>",
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
