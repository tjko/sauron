#!/usr/bin/perl -I/usr/local/sauron
#
# sauron.cgi
# $Id$
# [åäö~]
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000-2003.
# All Rights Reserved.
#
use CGI qw/:standard *table -no_xhtml/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
use Net::Netmask;
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::CGI::Utils;
use Sauron::Sauron;
#use strict;

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;

load_config();

$SAURON_CGI_VER = ' $Revision$ $Date$ ';
$debug_mode = $SAURON_DEBUG_MODE;
#$|=1;


@menulist = (
	  ['Hosts','menu=hosts',0],
	  ['Zones','menu=zones',0],
	  ['Nets','menu=nets',0],
	  ['Templates','menu=templates',0],
	  ['Groups','menu=groups',0],
	  ['Servers','menu=servers',0],
	  ['Login','menu=login',0],
	  ['About','menu=about',0],
	 );

%menus = (
	  'servers'=>'Sauron::CGI::Servers',
	  'groups'=>'Sauron::CGI::Groups',
	  'zones'=>'Sauron::CGI::Zones',
	  'login'=>'Sauron::CGI::Login',
	  'hosts'=>'Sauron::CGI::Hosts',
	  'nets'=>'Sauron::CGI::Nets',
	  'templates'=>'Sauron::CGI::Templates'
);

%menuhooks = ();

%menuhash =(
	    'servers'=>[
			['Show Current',''],
			['Select','sub=select'],
			[],
			['Add','sub=add'],
			['Delete','sub=del'],
			['Edit','sub=edit']
		       ],
	    'zones'=>[
		      ['Show Current',''],
		      ['Show pending','sub=pending'],
		      [],
		      ['Select','sub=select'],
		      [],
		      ['Add','sub=add'],
		      ['Copy','sub=Copy'],
		      ['Delete','sub=Delete'],
		      ['Edit','sub=Edit'],
		      [],
		      ['Add Default Zones','sub=AddDefaults']
		     ],
	    'nets'=>[
		     ['Networks',''],
		     ['&nbsp; + Subnets','list=sub'],
		     ['&nbsp; + All','list=all'],
		     [],
		     ['Add net','sub=addnet'],
		     ['Add subnet','sub=addsub'],
		     ['Add virtual subnet','sub=addvsub'],
		     [],
		     ['VLANs','sub=vlans'],
		     ['Add vlan','sub=addvlan'],
		     [],
		     ['VMPS','sub=vmps'],
		     ['Add VMPS','sub=addvmps']
		    ],
	    'templates'=>[
			  ['Show MX','sub=mx'],
			  ['Show WKS','sub=wks'],
			  ['Show Prn Class','sub=pc'],
			  ['Show HINFO','sub=hinfo'],
			  [],
			  ['Add MX','sub=addmx'],
			  ['Add WKS','sub=addwks'],
			  ['Add Prn Class','sub=addpc'],
			  ['Add HINFO','sub=addhinfo']
			 ],
	    'groups'=>[
		       ['Groups',''],
		       [],
		       ['Add','sub=add']
		      ],
	    'hosts'=>[
		      ['Search',''],
		      ['Last Search','sub=browse&lastsearch=1'],
		      ['New Search','sub=browse&bh_submit=Clear&bh_re_edit=1'],
		      [],
		      ['Add host','sub=add&type=1'],
		      [],
		      ['Add alias','sub=add&type=4'],
		      [],
		      ['Add MX entry','sub=add&type=3'],
		      ['Add delegation','sub=add&type=2'],
		      ['Add glue rec.','sub=add&type=6'],
		      ['Add DHCP entry','sub=add&type=9'],
		      ['Add printer','sub=add&type=5'],
		      ['Add SRV rec.','sub=add&type=8'],
		      [],
		      ['Add reservation','sub=add&type=101']
		     ],
	    'login'=>[
		      ['User Info',''],
		      ['Who','sub=who'],
		      ['News (motd)','sub=motd'],
		      [],
		      ['Login','sub=login'],
		      ['Logout','sub=logout'],
		      [],
		      ['Change password','sub=passwd'],
		      ['Edit settings','sub=edit'],
		      ['Save defaults','sub=save'],
		      ['Clear defaults','sub=clear'],
		      ['Frames OFF','FRAMEOFF','frames'],
		      ['Frames ON','FRAMEON','noframes'],
		      [],
		      ['Lastlog','sub=lastlog','root'],
		      ['Session Info','sub=session','root'],
		      ['Add news msg','sub=addmotd','root']
		     ],
	    'about'=>[
		      ['About',''],
		      ['Copyright','sub=copyright'],
		      ['License','sub=copying']
		     ]
);

sub about_menu();
sub login_form($$);
sub login_auth();
sub logout();
sub top_menu($);
sub left_menu($);
sub frame_set();
sub frame_set2();
sub frame_1();
sub frame_2();
sub init_plugins($);


#####################################################################

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();
($script_path = $script_name) =~ s/[^\/]+$//;
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$menu=param('menu');
#$menu='login' unless ($menu);
$remote_addr = $ENV{'REMOTE_ADDR'};
$remote_host = remote_host();
$remote_user = remote_user();

html_error("Invalid log path (LOG_DIR)") unless (-d $LOG_DIR);
html_error("Cannot write to log file")
  if (logmsg(($debug_mode ? "debug":"test"),"CGI access from $remote_addr")
      < 0);
html_error("Cannot connect to database") unless (db_connect2());
html_error("Database format mismatch!")
  if (sauron_db_version() ne get_db_version());
html_error("CGI interface disabled: $res") if (($res=cgi_disabled()));

unless (is_cidr($remote_addr)) {
  logmsg("notice","Warning: www server does not set standard CGI " .
	          "environment variable: REMOTE_ADDR!!! ($remote_addr)");
  $remote_addr = '0.0.0.0';
}

($scookie = cookie(-name=>"sauron-$SERVER_ID")) =~ s/[^A-Fa-f0-9]//g;
if ($scookie) {
  unless (load_state($scookie,\%state)) {
    logmsg("notice","invalid cookie ($scookie) supplied by $remote_addr");
    undef $scookie;
  }
}

unless ($scookie) {
  $new_cookie=make_cookie($script_path,\$scookie);
  logmsg("notice","new connection from: $remote_addr ($scookie)");
  print header(-cookie=>$new_cookie,-charset=>$SAURON_CHARSET,
	       -target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_auth() if ($SAURON_AUTH_MODE==1);
  login_form("Welcome",$scookie);
}

if ($state{'mode'} eq '1' && param('login') eq 'yes') {
  logmsg("debug","login authentication: $remote_addr");
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_auth();
}

if ($state{'auth'} ne 'yes' || $pathinfo eq '/login') {
  logmsg("notice","reconnect from: $remote_addr");
  update_lastlog($state{uid},$state{sid},4,$remote_addr,$remote_host);
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_auth() if ($SAURON_AUTH_MODE==1);
  login_form("Welcome (again)",$scookie);
}

if ($SAURON_AUTH_MODE==0) {
  if ((time() - $state{'last'}) > $SAURON_USER_TIMEOUT) {
    logmsg("notice","connection timed out for $remote_addr " .
	   $state{'user'});
    update_lastlog($state{uid},$state{sid},3,$remote_addr,$remote_host);
    print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
      start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
    login_form("Your session timed out. Login again",$scookie);
  }
}

unless ($SAURON_NO_REMOTE_ADDR_AUTH) {
  if ($remote_addr ne $state{'addr'}) {
    logmsg("notice",
	   "cookie for '$state{user}' reseived from wrong host: " .
	   $remote_addr . " (expecting it from: $state{addr})");
    html_error("Unauthorized Access denied!");
  }
}


$server=$state{'server'};
$serverid=$state{'serverid'};
$zone=$state{'zone'};
$zoneid=$state{'zoneid'};

unless ($menu) {
  $menu='hosts';
  $menu='zones' unless ($zoneid > 0);
  $menu='servers' unless ($serverid > 0);
}

init_plugins($SAURON_PLUGINS);

if ($pathinfo ne '') {
  $frame_mode=1 if ($pathinfo =~ /^\/frame/);
  logout() if ($pathinfo eq '/logout');
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
}


cgi_util_set_zone($zoneid,$zone);
cgi_util_set_server($serverid,$server);
set_muser($state{user});
$bgcolor='black';
$bgcolor='white' if ($frame_mode);

unless ($state{superuser} eq 'yes') {
  html_error("cannot get permissions!")
    if (get_permissions($state{uid},\%perms));
  foreach $rhf_key (keys %{$perms{rhf}}) {
    $SAURON_RHF{$rhf_key}=$perms{rhf}->{$rhf_key};
  }
} else {
  $perms{alevel}=999 if ($state{superuser});
}



########################################################################

if (param('csv')) {
  print header(-type=>'text/csv',-target=>'_new',-attachment=>'results.csv');
  #hosts_menu();
  #exit(0);
} else {
  print header(-charset=>$SAURON_CHARSET,-expires=>'now');
  if ($SAURON_DTD_HACK) {
    print "<!DOCTYPE HTML PUBLIC \"-//IETF//DTD HTML//EN\">\n",
          "<html><head><title>Sauron ($SERVER_ID)</title>\n",
          "<meta NAME=\"keywords\" CONTENT=\"Sauron DNS DHCP tool\">\n",
          "</head><body bgcolor=\"$bgcolor\">\n";
  } else {
    $refresh=meta({-http_equiv=>'Refresh',-content=>'1800'})
      if (($state{superuser} eq 'yes') && (param('menu') eq 'login') &&
	  (param('sub') eq 'who'));
    print start_html(-title=>"Sauron ($SERVER_ID)",-BGCOLOR=>$bgcolor,
		     -meta=>{keywords=>'Sauron DNS DHCP tool'},
		     -head=>$refresh);
  }

  print "\n\n<!-- Generated by Sauron v" . sauron_version() . " at " .
        localtime(time()) . " -->\n\n",
        "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2000-2003.\n",
        "     All Rights Reserved. -->\n\n";

  unless ($frame_mode) {
    top_menu(0);
    print "<TABLE bgcolor=\"black\" border=\"0\" cellspacing=\"0\" " .
          "width=\"100%\">\n" .
	  "<TR><TD align=\"left\" valign=\"top\" bgcolor=\"white\" " .
          "width=\"15%\">\n";
    left_menu(0);
    print "</TD><TD align=\"left\" valign=\"top\" bgcolor=\"#ffffff\">\n<br>";
  } else {
    #print "<TABLE width=100%><TR bgcolor=\"#ffffff\"><TD>";
  }
}


if ($menu eq 'about') {
  about_menu();
}
elsif ($menuref=$menus{$menu}) {
  my $fail = 0;
  my $module = $menuref;

  # check if we should call a plugin instead of default menu handler module
  if (($hook = $menuhooks{$menu}->{param('sub')})) {
    #print h2("HOOK: $$hook[0] ($$hook[1])");
    $module="\"$$hook[1]\"";
    $menuref="Sauron::Plugins::$$hook[0]";
  }

  # load module containing menu handler
  eval "require $module;";
  if ($@) {
    alert2("Failed to load module: $module");
  }
  else {
    $state{selfurl}=$selfurl;
    # call menu_hanlder() routine in the module
    $menuref .= '::menu_handler(\%state,\%perms)';
    eval "$menuref;";
    if ($@) {
      alert2("Call failed: $menuref");
      print "<br>$@<br>";
    }
    exit(0) if (param('csv'));
  }
}
else { print p,"Unknown menu '$menu'"; }


if ($debug_mode) {
  print "<hr><FONT size=-1><p>script name: " . script_name(),
        ", script_path: $script_path, frame_mode=$frame_mode",
	" (DTD_HACK=$SAURON_DTD_HACK ",
	" (NO_REMOTE_ADDR_AUTH=$SAURON_NO_REMOTE_ADDR_AUTH) ",
        "<br>path_info: " . path_info(),
        "<br>cookie='$scookie'\n",
        "<br>s_url='$s_url', selfurl='$selfurl'\n",
        "<br>url: " . url(),
        "<br>remote_addr=$remote_addr",
        "<br>remote_user=$remote_user",
        "<p><table><tr valign=\"top\"><td><table border=1>Parameters:";
  @names = param();
  foreach $var (@names) { print Tr(td($var),td(param($var)));  }
  print "</table></td><td>State vars:<table border=1>\n";
  foreach $key (keys %state) { print Tr(td($key),td($state{$key})); }
  print "</table></td></tr></table><hr><p>\n";
}

unless ($frame_mode) {
  print "</TD></TR><TR bgcolor=\"#002d5f\">",
        "<TD height=\"20\" colspan=\"2\" color=white align=\"right\">",
        "&nbsp;";
  print "</TD></TR></TABLE>\n";
}
print "\n<!-- end of page -->\n";
print end_html();

exit;

#####################################################################




# ABOUT menu
#
sub about_menu() {
  $sub=param('sub');

  if ($sub eq 'copyright') {
    open(FILE,"$PROG_DIR/COPYRIGHT") || return;
    print "<PRE>\n\n";
    while (<FILE>) { print " $_"; }
    print "</PRE>";
  }
  elsif ($sub eq 'copying') {
    open(FILE,"$PROG_DIR/COPYING") || return;
    print "<FONT size=\"-1\"><PRE>";
    while (<FILE>) { print " $_"; }
    print "</PRE></FONT>";
  }
  else {
    $SAURON_CGI_VER =~ s/(\$|\d{1,2}:\d{1,2}:\d{1,2})//g;
    $VER=sauron_version();

    print "<P><BR><CENTER>",
        "<a href=\"http://sauron.jyu.fi/\" target=\"sauron\">",
        "<IMG src=\"$SAURON_ICON_PATH/logo_large.png\" border=\"0\" ",
	"  alt=\"Sauron\">",
        "</a><BR>Version $VER<BR>(CGI $SAURON_CGI_VER)<P>",
        "a free DNS & DHCP management system<p>",
        "<hr noshade width=\"40%\"><b>Author:</b>",
        "<br>Timo Kokkonen <i>&lt;tjko\@iki.fi&gt;</i>",
        "<hr width=\"30%\"><b>Logo Design:</b>",
        "<br>Teemu Lähteenmäki <i>&lt;tola\@iki.fi&gt;</i>",
        "<hr noshade width=\"40%\"><p>",
	"</CENTER><BR><BR>";
  }
}

#####################################################################


sub logout() {
  my($c,$um,$host);

  $host='localhost???';
  $host=$1 if (self_url =~ /https?\:\/\/([^\/]+)\//);

  $u=$state{'user'};
  update_lastlog($state{uid},$state{sid},2,$remote_addr,$remote_host);
  logmsg("notice","user ($u) logged off from $remote_addr");
  $c=cookie(-name=>"sauron-$SERVER_ID",
	    -value=>'logged off',
	    -expires=>'+1s',
	    -path=>$script_path,
	    -secure=>($SAURON_SECURE_COOKIES ? 1 :0));
  remove_state($scookie);
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-cookie=>$c),
        start_html(-title=>"Sauron Logout",-BGCOLOR=>'white'),
        "<CENTER><TABLE width=\"50%\" cellspacing=0 border=0>",
        "<TR bgcolor=\"#002d5f\">",
        "<TD><FONT color=\"white\"> &nbsp; Sauron",
        "</FONT></TD><TD align=\"right\"><FONT color=\"white\">",
        "$host &nbsp;</FONT></TD></FONT>",
        "<TR><TD colspan=2 bgcolor=\"#efefff\"><CENTER>", 
        h2("You have been logged out."),p
        a({-href=>script_name},"Click to enter login screen again."),
	"</CENTER></TD></TR></CENTER>",,end_html();
  exit;
}

sub login_form($$) {
  my($msg,$c)=@_;
  my($host,$arg);

  $host='localhost???';
  $host=$1 if (self_url =~ /https?\:\/\/([^\/]+)\//);

  print "<FONT color=\"blue\">";
  print "<CENTER><TABLE width=\"50%\" cellspacing=0 border=0>",
        "<TR bgcolor=\"#002d5f\">",
        "<TD><FONT color=\"white\"> &nbsp; Sauron",
        "</FONT></TD><TD align=\"right\"><FONT color=\"white\">",
	"$host &nbsp;</FONT></TD></FONT>",
	"<TR><TD colspan=2 bgcolor=\"#efefff\">";

  print start_form(-target=>'_top'),"<BR><CENTER>",h2($msg),p,"<TABLE>",
        Tr,td("Login:"),td(textfield(-name=>'login_name',-maxlength=>'8')),
        Tr,td("Password:"),
                   td(password_field(-name=>'login_pwd',-maxlength=>'30')),
              "</TABLE>",
        hidden(-name=>'login',-default=>'yes'),
        submit(-name=>'submit',-value=>'Login'),
        p,"<br><br>You need to have cookies enabled for this site...",
        "<br></CENTER></TD></TR></TABLE>";

  # save arguments (allows linking to "pages" in Sauron)
  foreach $arg (param()) { print hidden($arg,param($arg)); }

  print end_form,end_html();

  $state{'mode'}='1';
  $state{'auth'}='no';
  $state{'superuser'}='no';
  save_state($c,\%state);
  exit;
}

sub login_auth() {
  my($u,$p);
  my(%user,%h,$ticks,$pwd_chk,$arg,$arg_str);
  my($login_debug,$login_time,$login_debug_log);

  # 0 == no debug, 1 == debug on
  $login_debug=0;
  $login_debug_log="/var/tmp/login-debug.log";
  $login_time = time;

  $ticks=time();
  $state{'auth'}='no';
  $state{'mode'}='0';

  if ($SAURON_AUTH_MODE == 1) {
    $u=$remote_user;
    $p='foobar';
  } else {
    $u=param('login_name');
    $p=param('login_pwd');
  }
  if ($login_debug) {
      open (LOGIN_DEBUG, ">>$login_debug_log");
      printf LOGIN_DEBUG "%s: [%s] %s\n",
      $login_time,scalar localtime($login_time),$u;
  }

  $p=~s/\ \t\n//g;
  print "<P><CENTER>";
  if (! (valid_safe_string($u,255) && valid_safe_string($p,255))) {
    print p,h1("Invalid arguments!");
  }
  if ($u eq '' || $p eq '') {
    print p,h1("Username or password empty!");
  }
  elsif ($u !~ /^[a-zA-Z0-9\.\-]+$/) {
    print p,h1("Invalid username!");
  }
  else {
    unless (get_user($u,\%user)) {
      $pwd_chk = -1;
      if ($SAURON_AUTH_MODE==1) {
	$pwd_chk=0;
      }
      elsif ($SAURON_AUTH_PROG) {
	if (-x $SAURON_AUTH_PROG) {
	  $pwd_chk = pwd_external_check($SAURON_AUTH_PROG,$u,$p);
	} else {
	  alert2("Authentication services unavailable!");
	}
      } else {
	$pwd_chk = pwd_check($p,$user{password});
      }
      if ( ($pwd_chk == 0) &&
	   ($user{expiration} == 0 || $user{expiration} > time()) ) {
	$state{'auth'}='yes';
	$state{'user'}=$u;
	$state{'uid'}=$user{'id'};
	$state{'sid'}=new_sid();
	$state{'login'}=$ticks;
	$state{'serverid'}=$user{'server'};
	$state{'zoneid'}=$user{'zone'};
	$state{'superuser'}='yes' if ($user{superuser} eq 't' ||
				      $user{superuser} == 1);
	if ($state{'serverid'} > 0) {
	  $state{'server'}=$h{'name'}
	    unless(get_server($state{'serverid'},\%h));
	}
	if ($state{'zoneid'} > 0) {
	  $state{'zone'}=$h{'name'}
	    unless(get_zone($state{'zoneid'},\%h));
	}

	foreach $arg (param()) {
	  next if ($arg =~ /^(login_name|login_pwd|login|submit)$/);
	  $arg_str .= hidden($arg,param($arg));
	}

	print "<TABLE border=0 cellspacing=0 bgcolor=\"#efefff\" " .
	      " width=\"70%\">",
	      "<TR bgcolor=\"#002d5f\">",
	      "<td width=\"80\"><IMG src=\"$SAURON_ICON_PATH/logo.png\" " .
		" alt=\"\" width=\"80\" height=\"70\" border=0></td>",
	      "<td valign=\"bottom\" align=\"left\">",
	      "<font color=\"white\"> &nbsp; Sauron v".sauron_version().
	      "</font></td>",
	      "<td valign=\"bottom\" align=\"right\">",
	      "<font color=\"white\">$SERVER_ID &nbsp; </font></td>",
	      "</TR><TR><TD colspan=3><CENTER>\n";
	print h1("Login ok!"),p,"<TABLE><TR><TD>",
	      startform(-method=>'POST',-action=>$s_url),$arg_str,
	      submit(-name=>'submit',-value=>'No Frames'),end_form,
	      "</TD><TD> ",
	      startform(-method=>'POST',-action=>"$s_url/frames"),$arg_str,
	      submit(-name=>'submit',-value=>'Frames'),end_form,
	      "</TD></TR></TABLE>";

	# warn about expiring account
	if ( ($user{expiration} > 0) &&
	     ($user{expiration} < time() + 14*86400) ) {
	  print "<FONT color=\"red\">",
	        h2("NOTE! Your account will expire soon!"),
	        "(account expiration date: " . localtime($user{expiration}) .
		")</FONT><p><br>";
	}

	# print news/MOTD stuff
	get_news_list($state{serverid},3,\@newslist);
	if (@newslist > 0) {
	  print h2("Message(s) of the day:"),
	        "<TABLE width=\"80%\" bgcolor=\"#eaeaff\">";
	  for $i (0..$#newslist) {
	    $msg=$newslist[$i][3];
	    #$msg =~ s/\n/<BR>/g;
	    $date=localtime($newslist[$i][0]);
	    print 
	      Tr(td($msg . "<FONT size=-1><I>" .
                  "<BR> &nbsp; &nbsp; -- $newslist[$i][1] $date </I></FONT>"));
	  }
	  print "</TABLE><BR>";
	}

	# advertise "save defaults" option for users not having any defaults...
	unless ($state{serverid} > 0 && $state{zoneid} > 0) {
	  print h4("Hint! You can save your server and zone selection using " .
		   "the \"Save Defaults\" command in Login menu.");
	}

	print "</CENTER></td></tr></table>\n";
	logmsg("notice","user ($u) logged in from: $remote_addr");
	$last_from = db_encode_str($remote_addr);
	db_exec("UPDATE users SET last=$ticks,last_from=$last_from " .
		"WHERE id=$user{'id'};");
	update_lastlog($state{uid},$state{sid},1,
		       $remote_addr,$remote_host);
      }
    }
    if ($login_debug) {
	print LOGIN_DEBUG $login_time,": ", $u, "\n", 
	map { "\t$_ => $user{$_}\n" } keys %user;
    }
  }

  print p,h1("Login failed."),p,"<a href=\"$selfurl\">try again</a>"
    unless ($state{'auth'} eq 'yes');

  print p,p,"</CENTER>";

  print "</TABLE>\n" unless ($frame_mode);
  print end_html();
  save_state($scookie,\%state);
  load_state($scookie,\%state) if ($SAURON_AUTH_MODE==1);
  fix_utmp($SAURON_USER_TIMEOUT*2);
  exit;
}

sub top_menu($) {
  my($mode)=@_;
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst,$i);

  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  if ($frame_mode) {
    print '<TABLE border="0" cellspacing="0" width="100%">',
          '<TR bgcolor="#002d5f"><TD rowspan=2>',
          '<a href="http://sauron.jyu.fi/" target="sauron">',
          '<IMG src="' .$SAURON_ICON_PATH .
	  '/logo.png" width="80" height="70" border="0" alt=""></a></TD>',
          '<TD colspan=2><FONT size=+2 color="white">Sauron</WHITE></TD></TR>',
	  '<TR bgcolor="#002d5f" align="left" valign="center">',
          '<TD><FONT color="white">';
  } else {
    print '<a href="http://sauron.jyu.fi/" target="sauron">',
          '<IMG src="' .$SAURON_ICON_PATH .
          '/logo.png" width="80" height="70" border="0" alt=""></a>';

    print '<TABLE border="0" cellspacing="0" width="100%">';

    print '<TR bgcolor="#002d5f" align="left" valign="center">',
      '<TD width="15%" height="24">',
      '<FONT color="white">&nbsp;Sauron </FONT></TD>',
      '<TD height="24"><FONT color="white">';
  }

  for $i (0..$#menulist) {
    print "<A HREF=\"$s_url?$menulist[$i][1]\"><FONT color=\"#ffffff\">",
          "$menulist[$i][0]</FONT></A>";
    print " | " if ($i < $#menulist);
  }

  print  "<TD align=\"right\"><FONT color=\"#ffffff\">";
  if ($frame_mode) { print "$SERVER_ID &nbsp;"; }
  else {
    printf "%s &nbsp; &nbsp; %d.%d.%d %02d:%02d ",
           $SERVER_ID,$mday,$mon+1,$year+1900,$hour,$min;
  }
  print "</FONT></TD></TR></TABLE>";
}



sub left_menu($) {
  my($mode)=@_;
  my($url,$w,$l,$i,$name,$u,$ref,$target);

  $w="\"100\"";

  $url=$s_url;
  print "<TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" " .
        "cellspacing=\"3\" cellpadding=\"0\">", # Tr,th(h4("$menu")),
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " ,
	 "border=\"0\">",
         "<TR><TH><FONT color=\"#ffffff\">$menu</FONT></TH></TR>",
	  "<TR><TD BGCOLOR=\"#eeeeee\"><FONT size=\"-1\">";
  #print "<p>mode=$mode";
  print "<TABLE width=\"100%\" bgcolor=\"#cccccc\" cellpadding=1 " .
        " cellspacing=3 border=0>";

  $l=$menuhash{$menu};
  $url.="?menu=$menu";
  if (defined $l) {
    for $i (0..$#{$l}) {
      if ($#{$$l[$i]} < 1) {
	print Tr({-bgcolor=>'#cccccc',-height=>5},td(''));
	next;
      }
      next if ($$l[$i][2] =~ /(^|\|)root/ && $state{superuser} ne 'yes');
      next if ($$l[$i][2] =~ /(^|\|)noframes/ && $frame_mode);
      next if ($$l[$i][2] =~ /(^|\|)frames/ && not $frame_mode);
      $name=$$l[$i][0];
      $ref=$$l[$i][1];
      $u="$url";
      $u.="&".$ref if ($ref);
      $target='';
      if ($ref eq 'FRAMEOFF') {
	$target='target="_top"';
	$u=$script_name;
      }
      elsif ($ref eq 'FRAMEON') {
	$target='target="_top"';
	$u="$s_url/frames";
      }

      print Tr({-bgcolor=>'#bbbbbb'},td("<a href=\"$u\" $target>$name</a>"));
    }
  } else {
    print Tr(td('empty menu'));
  }

  print "</TABLE></FONT></TR></TABLE></TD></TABLE><BR>";

  print "<TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" cellspacing=\"3\" " .
        "cellpadding=\"0\">", #<TR><TD><H4>Current selections</H4></TD></TR>",
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " .
	"border=\"0\">",
	"<TR><TH><FONT color=white size=-1>Current selections</FONT></TH></TR>",
	"<TR><TD BGCOLOR=\"#eeeeee\">";

  print "<FONT size=-1>",
        "Server: $server<br>Zone: $zone<br>SID: $state{sid}<br></FONT>";

  print "</FONT></TABLE></TD></TR></TABLE><BR>";

}

sub frame_set() {
  print header(-charset=>$SAURON_CHARSET);

  print "<HTML>" .
        "<HEAD><TITLE>Sauron ($SERVER_ID)</TITLE></HEAD>" .
        "<FRAMESET border=\"0\" rows=\"90,*\" >\n" .
        "  <FRAME src=\"$script_name/frame1\" noresize scrolling=\"no\" " .
	"   frameborder=\"0\" marginheight=\"5\" marginwidth=\"5\">\n" .
        "  <FRAME src=\"$script_name/frames2\" name=\"bottom\" " .
	"   frameborder=\"0\" marginheight=\"0\" marginwidth=\"0\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";

  exit 0;
}

sub frame_set2() {
  print header(-charset=>$SAURON_CHARSET);
  $menu="?menu=" . param('menu') if ($menu);

  print "<HTML>" .
        "<FRAMESET border=\"0\" cols=\"120,*\">\n" .
#        "  <TITLE>Sauron ($SERVER_ID)</TITLE>" .
	"  <FRAME src=\"$script_name/frame2$menu\" name=\"menu\" noresize " .
	"   scrolling=\"no\" frameborder=\"0\" " .
	"   marginheight=\"5\" marginwidth=\"5\">\n" .
        "  <FRAME src=\"$script_name/frame3$menu\" name=\"main\" " .
	"   frameborder=\"0\" marginheight=\"5\" marginwidth=\"5\">\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}


sub frame_1() {
  print header(-charset=>$SAURON_CHARSET),
        start_html(-title=>"sauron: top menu",-BGCOLOR=>'#efefff',
		   -target=>'bottom');

  $s_url .= '/frames2';
  top_menu(1);

  print end_html();
  exit 0;
}

sub frame_2() {
  print header(-charset=>$SAURON_CHARSET),
        start_html(-title=>"sauron: left menu",-BGCOLOR=>'#efefff',
		   -target=>'main');

  $s_url .= '/frame3';
  left_menu(1);
  print end_html();
  exit 0;
}


sub init_plugins($) {
  my($plugins) = @_;

  my(@plugs) = split(/,/,$plugins);
  my($ret,$i,$file,$file2);

  for $i (0..$#plugs) {
    $file="$PROG_DIR/plugins/$plugs[$i].conf";
    $file2="$PROG_DIR/plugins/$plugs[$i].pm";
    if (-r $file) {
      $ret = do "$file";
      if ($@) {
	logmsg("notice","parse error in plugin info: $file");
      } elsif (not $ret) {
	logmsg("notice", "failed to process plugin info: $file");
      }

      # add commands defined by plugin into appropriate menu...
      for $j (0..$#{$MENUDATA}) {
	push @{$menuhash{$MENU}}, [$$MENUDATA[$j][0],$$MENUDATA[$j][1]];

	# add hook for command (if necessary)...
	if ($$MENUDATA[$j][2]) {
	  $menuhooks{$MENU}->{$$MENUDATA[$j][2]}=[$NAME,$file2];
	}
      }
    }
  }

}

# eof

