#!/usr/bin/perl -I/opt/sauron
#
# sauron.cgi
# 
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000-2005.
# All Rights Reserved.
#
use CGI qw/:standard *table -utf8/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
# use Net::Netmask;
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::CGI::Utils;
use Sauron::Sauron;
use HTML::Entities;
use Data::Dumper;
use strict;
use warnings;
use open ':locale';

# variables used globally; needed with strict
use vars qw(
    $debug_mode @menulist %menus %menuhooks %menuhash
    $pathinfo $script_name $script_path $s_url $selfurl
    $menu $remote_addr $remote_host $remote_user
    $scookie $new_cookie $server $serverid $zone $zoneid $res $refresh
    $hook @names $var $menuref $arg $arg_str
    $login_debug $login_time $login_debug_log $ticks $pwd_chk $last_from
    $msg $date $i $u
    %state %perms
    $rhf_key $key
);

# configuration globals populated by load_config()
use vars qw(
    $SAURON_DEBUG_MODE $ALEVEL_SHOW_UNALLOCATED_CIDRS $ALEVEL_HISTORY_SEARCH
    $SAURON_TOPMENU_BGCOLOR $SAURON_TOPMENU_FONTCOLOR $SAURON_ENV_NAME
    $SAURON_ICON_PATH $SAURON_CHARSET
    $SERVER_ID $SAURON_USER_TIMEOUT $SAURON_AUTH_MODE
    $SAURON_NO_REMOTE_ADDR_AUTH $LOG_DIR $SAURON_PLUGINS $PROG_DIR
    %SAURON_RHF $SAURON_TEMP_LOCK $SAURON_SECURE_COOKIES
    $SAURON_AUTH_PROG
);

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;

load_config();

my $SAURON_CGI_VER = ' $Revision: 1.204 $ $Date: 2005/01/27 09:24:44 $ ';
$debug_mode = $SAURON_DEBUG_MODE;
#$|=1;

@menulist = (
	  ['Hosts','menu=hosts',0],
	  ['Zones','menu=zones',0],
    ['Approvals','menu=approvals',0],
	  ['Nets','menu=nets',0],
	  ['Templates','menu=templates',0],
	  ['Groups','menu=groups',0],
	  ['ACLs','menu=acls',0],
	  ['Servers','menu=servers&sub=select',0],
	  ['Login','menu=login',0],
	  ['About','menu=about',0],
	 );

%menus = (
	  'servers'=>'Sauron::CGI::Servers',
	  'groups'=>'Sauron::CGI::Groups',
	  'acls'=>'Sauron::CGI::ACLs',
	  'zones'=>'Sauron::CGI::Zones',
	  'login'=>'Sauron::CGI::Login',
	  'hosts'=>'Sauron::CGI::Hosts',
    'approvals'=>'Sauron::CGI::Approvals',
	  'nets'=>'Sauron::CGI::Nets',
	  'templates'=>'Sauron::CGI::Templates'
);

%menuhooks = ();

# $menuhooks{'login'}->{'Groups'} = ['Users', "$PROG_DIR/plugins/Users.pm"];

%menuhash =(
	    'servers'=>[
			['Show Current',''],
			['Select','sub=select'],
			[],
			['Add','sub=add','root'],
			['Delete','sub=del','root'],
			['Edit','sub=edit','root']
		       ],
	    'zones'=>[
		      ['Show Current','sub=Current'],
		      ['Show pending','sub=pending'],
		      [],
		      ['Select','sub=select'],
		      [],
		      ['Add','sub=add','root'],
		      ['Copy','sub=Copy','root'],
		      ['Delete','sub=Delete','root'],
		      ['Edit','sub=Edit','root'],
		      [],
		      ['Catalog Groups','sub=CatalogGroups','root'],
		      ['Add Default Zones','sub=AddDefaults','root']
		     ],
      'approvals'=>[
          ['Policies','sub=list_policies'],
          ['Pending','sub=pending'],
          ['All Requests','sub=all_requests'],
          [],
          ['Add Policy','sub=add_policy']
         ],
	    'nets'=>[
		     ['Networks',''],
		     ['&nbsp; + Subnets','list=sub'],
		     ['&nbsp; + All','list=all'],
		     ['&nbsp; + Free','list=free',['level',$ALEVEL_SHOW_UNALLOCATED_CIDRS]],
		     [],
		     ['Add net','sub=addnet','root'],
		     ['Add subnet','sub=addsub','root'],
		     ['Add virtual subnet','sub=addvsub','root'],
		     [],
		     ['VLANs','sub=vlans',['level',$main::ALEVEL_VLANS]],
		     ['Add vlan','sub=addvlan','root'],
		     [],
		     ['VMPS','sub=vmps',['level',$main::ALEVEL_VLANS]],
		     ['Add VMPS','sub=addvmps','root']
		    ],
	    'templates'=>[
			  ['Show MX','sub=mx'],
			  ['Show WKS','sub=wks'],
			  ['Show Prn Class','sub=pc'],
			  ['Show HINFO','sub=hinfo'],
			  [],
			  ['Add MX','sub=addmx',['flags','MX']],
			  ['Add WKS','sub=addwks','root'],
			  ['Add Prn Class','sub=addpc','root'],
			  ['Add HINFO','sub=addhinfo','root']
			 ],
	    'groups'=>[
		       ['Groups',''],
		       [],
		       ['Add','sub=add',['zone','RW']]
		      ],
	    'acls'=>[
		       ['ACLs','',['level', $main::ALEVEL_ACLS]],
		       ['Keys','sub=keys',['level', $main::ALEVEL_ACLS]],
		       [],
		       ['Add ACL','sub=addacl',['level', $main::ALEVEL_ACLS]]
		      ],
	    'hosts'=>[
		      ['Search',''],
		      ['Last Search','sub=browse&lastsearch=1'],
		      ['New Search','sub=browse&bh_submit=Clear&bh_re_edit=1'],
		      [],
		      ['Add host','sub=add&type=1',['zone','RW']],
		      [],
		      ['Add alias','sub=add&type=4',['flags','SCNAME']], 
		      [],
		      ['Add MX entry','sub=add&type=3',['flags','MX']],
		      ['Add delegation','sub=add&type=2',['flags','DELEG']], 
		      ['Add glue rec.','sub=add&type=6',['flags','GLUE']], 
		      ['Add DHCP entry','sub=add&type=9',['flags','DHCP']],
		      ['Add printer','sub=add&type=5',['flags','PRINTER']],
		      ['Add SRV rec.','sub=add&type=8',['flags','SRV']],
		      ['Add TLSA rec.','sub=add&type=12',['flags','TLSA']],
		      ['Add TXT rec.','sub=add&type=13',['flags','TXT']],
		      ['Add NAPTR rec.','sub=add&type=14',['flags','NAPTR']],
          ['Add CAA rec.','sub=add&type=15',['flags','CAA']],
		      [],
		      ['Add reservation','sub=add&type=101',['flags','RESERV']]
		     ],
	    'login'=>[
		      ['User Info',''],
		      ['Who','sub=who'],
		      ['News (motd)','sub=motd'],
		      [],
		      ['Login','sub=login',['equal',[$main::SAURON_AUTH_MODE, '0']]],
		      [],
		      ['Change password','sub=passwd',['equal',[$main::SAURON_AUTH_MODE, '0']]],
		      ['Edit settings','sub=edit'],
		      ['Save defaults','sub=save'],
		      ['Clear defaults','sub=clear'],
		      [],
		      ['Lastlog','sub=lastlog','root'],
		      ['Session Info','sub=session','root'],
		      ['History Search','sub=history', $ALEVEL_HISTORY_SEARCH || 'root'],
		      ['Add news msg','sub=addmotd','root'],
		      ['Deployment theme','sub=theme','root']
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
sub logout($); # **** 2020-09-16 TVu
sub top_menu($);
sub left_menu($);
sub init_plugins($);
sub is_superuser();

#####################################################################

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

($scookie = cookie(-name=>"sauron-$SERVER_ID") // '') =~ s/[^A-Fa-f0-9]//g;
if ($scookie) {
  fix_utmp($SAURON_USER_TIMEOUT, 1);
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
        start_html(-title=>"Sauron Login",theme_stylesheet_args());
  print theme_style_block();
  login_auth() if ($SAURON_AUTH_MODE==1);
  login_form("Welcome",$scookie);
}

if ($state{'mode'} eq '1' && (param('login') // '') eq 'yes') {
  logmsg("debug","login authentication: $remote_addr");
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",theme_stylesheet_args());
  print theme_style_block();
  login_auth();
}

if ($state{'auth'} ne 'yes' || $pathinfo eq '/login') {
  logmsg("notice","reconnect from: $remote_addr");
  update_lastlog($state{uid},$state{sid},4,$remote_addr,$remote_host);
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",theme_stylesheet_args());
  print theme_style_block();
  login_auth() if ($SAURON_AUTH_MODE==1);
  login_form("Welcome (again)",$scookie);
}

if ($SAURON_AUTH_MODE==0) {
  if ((time() - $state{'last'}) > $SAURON_USER_TIMEOUT) {
    logmsg("notice","connection timed out for $remote_addr " .
	   $state{'user'});
    update_lastlog($state{uid},$state{sid},3,$remote_addr,$remote_host);
    print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
      start_html(-title=>"Sauron Login",theme_stylesheet_args());
  print theme_style_block();
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
$zone=$state{'zone'} || '';
$zoneid=$state{'zoneid'};

unless ($menu) {
  $menu='hosts';
  $menu='zones' unless ($zoneid > 0);
  $menu='servers' unless ($serverid > 0);
}

init_plugins($SAURON_PLUGINS);

if ($pathinfo ne '') {
  logout(1) if ($pathinfo eq '/logout'); # **** 2020-09-16 TVu
  # Frameset URLs from very old bookmarks land at the script root.
  if ($pathinfo =~ m{^/frames?\d?$}) {
      print redirect($script_name);
      exit 0;
  }
}


cgi_util_set_zone($zoneid,$zone);
cgi_util_set_server($serverid,$server);
set_muser($state{user});

unless (is_superuser()) {
  html_error("cannot get permissions!")
    if (get_permissions($state{uid},\%perms));
  foreach $rhf_key (keys %{$perms{rhf}}) {
    $SAURON_RHF{$rhf_key}=$perms{rhf}->{$rhf_key};
  }
} else {
  $perms{alevel}=999 if (is_superuser());
}




########################################################################

if (param('csv')) {
  print header(-type=>'text/csv',-target=>'_new',-attachment=>'results.csv');
  #hosts_menu();
  #exit(0);
} else {
  print header(-charset=>$SAURON_CHARSET,-expires=>'now');
  $refresh=meta({-http_equiv=>'Refresh',-content=>'1800'})
      if (is_superuser() && (defined(param('menu')) && param('menu') eq 'login') &&
	  (defined(param('sub')) && param('sub') eq 'who'));
  my $page_title = "Sauron" . ($SAURON_ENV_NAME ? " [$SAURON_ENV_NAME]" : '') . " \x{2014} $SERVER_ID";
  print start_html(-charset=>$SAURON_CHARSET,-title=>$page_title,
		   -meta=>{keywords=>'Sauron DNS DHCP tool'},
		   theme_stylesheet_args(),
		   -head=>$refresh);
  print theme_style_block();
  print '<a class="s-skip-link" href="#main">Skip to content</a>', "\n";

  print "\n\n<!-- Generated by Sauron v" . sauron_version() . " at " .
        localtime(time()) . " -->\n\n",
        "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2000-2003.\n",
        "     All Rights Reserved. -->\n\n";

  top_menu(0);

  # Context bar: shows server/zone breadcrumb between the topbar and the
  # shell grid so operators always know which context they are operating in.
  print '<div class="s-context-bar">';
  print '<nav class="s-context-bar__crumb" aria-label="Context"',
        ' data-serverid="', ($serverid+0), '"',
        ' data-zoneid="', ($zoneid+0), '">';
  if ($server) {
      print '<span class="s-context-bar__label">Server</span>',
            '<span class="s-context-bar__segment">', encode_entities($server), '</span>';
  }
  if ($zone) {
      print '<span class="s-context-bar__sep" aria-hidden="true">&rsaquo;</span>',
            '<span class="s-context-bar__label">Zone</span>',
            '<span class="s-context-bar__segment">', encode_entities($zone), '</span>';
  }
  print '</nav>';
  print '<div class="s-context-bar__actions"></div>';
  print "</div>\n";

  print "<div class=\"s-shell\">\n",
        "<aside class=\"s-sidebar\">\n";
  left_menu(0);
  print "</aside>\n",
        "<main class=\"s-main\" id=\"main\">\n";
}


if ($menu eq 'about') {
  about_menu();
}
elsif ($menuref=$menus{$menu}) {
  my $fail = 0;
  my $module = $menuref;
  my $sub = param('sub');

  # check if we should call a plugin instead of default menu handler module
#  print "$menuref<BR>";
#  print param('sub') . '<BR>';
#  print Dumper(\%menuhooks) . '<br>';
  if (defined $menuhooks{$menu} && defined $menuhooks{$menu}->{$sub}) {
    if (($hook = $menuhooks{$menu}->{$sub})) {
      #print h2("HOOK: $$hook[0] ($$hook[1])");
      $module="\"$$hook[1]\"";
      $menuref="Sauron::Plugins::$$hook[0]";
      #   print "$menuref<BR>";
    }
  }

  # load module containing menu handler
  eval "require $module;";
  if ($@) {
    alert2("Failed to load module: $module");
  }
  else {
    $state{selfurl} = $selfurl;
    # call menu_hanlder() routine in the module
    $menuref .= '::menu_handler(\%state,\%perms)';
#   print "$menuref<BR>";
    eval "$menuref;";
    if ($@) {
      alert2("Call failed: $menuref");
      print "<br>$@<br>";
    }
    exit(0) if (param('csv'));
  }
}
else { print p,"Unknown menu '" . encode_entities($menu) . "'"; }


if ($debug_mode) {
  print "<hr><p>script name: " . script_name(),
        ", script_path: $script_path",
	" (NO_REMOTE_ADDR_AUTH=$SAURON_NO_REMOTE_ADDR_AUTH) ",
        "<br>path_info: " . path_info(),
        "<br>cookie='$scookie'\n",
        "<br>s_url='$s_url', selfurl='$selfurl'\n",
        "<br>url: " . url(),
        "<br>remote_addr=$remote_addr",
        "<br>remote_user=$remote_user",
        "<p><table><tr valign=\"top\"><td><table border=1>Parameters:";
  @names = multi_param();
  foreach $var (@names) { print Tr(td($var),td(param($var)));  }
  print "</table></td><td>State vars:<table border=1>\n";
  foreach $key (keys %state) { print Tr(td($key),td($state{$key})); }
  print "</table></td></tr></table><hr><p>\n";
}

print "</main>\n",
      "</div>\n",
      '<footer class="s-footer">&nbsp;</footer>',
      "\n";
print "\n<!-- end of page -->\n";
print end_html();

exit;

#####################################################################




# ABOUT menu
#
sub about_menu() {
  my $sub=param('sub') // '';
  my ($VER);

  if ($sub eq 'copyright') {
    open(FILE,"$PROG_DIR/COPYRIGHT") || return;
    print '<article class="s-document"><pre>';
    while (<FILE>) { print encode_entities($_); }
    print '</pre></article>';
  }
  elsif ($sub eq 'copying') {
    open(FILE,"$PROG_DIR/COPYING") || return;
    my $text = do { local $/; <FILE> };
    close(FILE);
    print '<article class="s-document s-document--license" lang="en">', "\n";
    for my $block (split /\n{2,}/, $text) {
      $block =~ s/\r//g;
      next unless $block =~ /\S/;
      my @lines = split(/\n/, $block);
      my $max_ind = 0;
      for my $ln (@lines) {
        my $li = ($ln =~ /^( +)/) ? length($1) : 0;
        $max_ind = $li if $li > $max_ind;
      }
      if ($max_ind >= 8) {
        # Heading block — each non-empty line as its own <p>
        for my $line (@lines) {
          $line =~ s/^\s+|\s+$//g;
          next unless $line;
          print '<p class="center">', encode_entities($line), "</p>\n";
        }
      } else {
        my $indent = ($block =~ /^( +)/) ? length($1) : 0;
        $block =~ s/\n/ /g;
        $block =~ s/ {2,}/ /g;
        $block =~ s/^\s+|\s+$//g;
        next unless $block;
        my $cls = $block =~ /^[a-z]\)/ ? 'subitem' : 'just';
        my $ti = ($cls eq 'just' && $indent >= 2)
          ? sprintf(' style="text-indent:%.1fem"', $indent * 0.5) : '';
        print '<p class="', $cls, '"', $ti, '>', encode_entities($block), "</p>\n";
      }
    }
    print '</article>';
  }
  else {
    $SAURON_CGI_VER =~ s/(\$|\d{1,2}:\d{1,2}:\d{1,2})//g;
    $VER=sauron_version();

    print '<article class="s-about">',
        '<div class="s-about__hero">',
        '<a href="https://github.com/tjko/sauron/" target="sauron">',
        '<img src="', $SAURON_ICON_PATH, '/logo_large.png" ',
        '  alt="Sauron" class="s-about__logo"></a>',
        '<p class="s-about__version">Version ', $VER, '<br>',
        '<small>CGI ', $SAURON_CGI_VER, '</small></p>',
        '<p class="s-about__tagline">A Free DNS &amp; DHCP Management System</p>',
        '</div>',

        '<hr class="s-about__divider">',
        '<h3>Original Author</h3>',
        '<p>Timo Kokkonen <i>&lt;tjko@iki.fi&gt;</i></p>',

        '<hr class="s-about__divider">',
        '<h3>Further Development</h3>',
        '<p>Michal Kostenec <i>&lt;kostenec@civ.zcu.cz&gt;</i><br>',
        'Ales Padrta <i>&lt;apadrta@civ.zcu.cz&gt;</i> (IPv6 Support)<br>',
        'Riku Meskanen <i>&lt;mesrik@iki.fi&gt;</i><br>',
        'Teppo Vuori <i>&lt;sauron@teppovuori.fi&gt;</i> (Additional Features)<br>',
        'Tapani Tarvainen <i>&lt;sauron@tapanitarvainen.fi&gt;</i></p>',

        '<hr class="s-about__divider">',
        '<h3>Logo Design</h3>',
        '<p>Teemu L&auml;hteenm&auml;ki <i>&lt;tola@iki.fi&gt;</i></p>',

        '</article>';

  }
}

#####################################################################


sub logout($) { # **** 2020-09-16 TVu
  my($full)=@_; # **** 2020-09-16 TVu
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

# Headers etc. not needed if user is logged out because web interface is blocked.
  if ($full) { # **** 2020-09-16 TVu
      print header(-charset=>$SAURON_CHARSET,-target=>'_top',-cookie=>$c),
            start_html(-title=>"Sauron Logout",theme_stylesheet_args());
      print theme_style_block();
  }
  print '<div class="s-login-wrap">',
        '<div class="s-login-card">',
        '<header class="s-login-card__head">',
        '<span>Sauron</span>',
        '<span>', encode_entities($host), '</span>',
        '</header>',
        '<div class="s-login-card__body">',
        h2("You have been logged out."), p,
        a({-href=>script_name},"Click to enter login screen again."),
        '</div></div></div>',
        end_html();

  exit;
}

sub login_form($$) {
  my($msg,$c)=@_;
  my($host,$arg);

  $host = (self_url =~ /https?\:\/\/([^\/]+)\//) ? $1 : $SERVER_ID;

  print '<div class="s-login-wrap">',
        '<div class="s-login-card">',
        '<header class="s-login-card__head">',
        '<span>Sauron</span>',
        '<span>', encode_entities($host), '</span>',
        '</header>',
        '<div class="s-login-card__body">';

  # Show errors (failed login, timeout) as alert; welcome messages as heading.
  my $msg_html = ($msg =~ /failed|timed out/i) ? do { alert1($msg); '' } : h2($msg);
  print start_form(-action=>$s_url,-target=>'_top'), $msg_html,
        '<div class="s-login-fields">',
        '<label for="login">Login:</label>',
        textfield(-id=>"login",-name=>'login_name'),
        '<label for="login_pwd">Password:</label>',
        password_field(-name=>'login_pwd', -id=>'login_pwd',
                       -maxlength=>'40', -size=>20),
        '</div>',
        hidden(-name=>'login',-default=>'yes'),
        submit(-name=>'submit',-value=>'Login',-class=>'s-btn s-btn--primary'),
        p, '<small>You need to have cookies enabled for this site.</small>',
        '</div></div></div>';

  # save arguments (allows linking to "pages" in Sauron)
  foreach $arg (multi_param()) { print hidden($arg,scalar(param($arg))); }

  print end_form,
        end_html();

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
  if (! (valid_safe_string($u,0) && valid_safe_string($p,255))) {
    alert1("Invalid arguments!");
  }
  if ($u eq '' || $p eq '') {
    alert1("Username or password empty!");
  }
  elsif ($u !~ /^[a-zA-Z0-9\-\.@]+$/) {
    alert1("Invalid username!");
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
      if ( ($pwd_chk == 0) && (!defined($user{expiration}) ||
	   $user{expiration} == 0 || $user{expiration} > time()) ) {
	$state{'auth'}='yes';
	$state{'user'}=$u;
	$state{'uid'}=$user{'id'};
	$state{'sid'}=new_sid();
	$state{'login'}=$ticks;
	$state{'serverid'}=$user{'server'};
	$state{'zoneid'}=$user{'zone'};
	$state{'superuser'}='yes' if ($user{superuser} eq 't' ||
				      $user{superuser} eq 1);
	if ($state{'serverid'} > 0) {
	  $state{'server'}=$h{'name'}
	    unless(get_server($state{'serverid'},\%h));
	}
	if ($state{'zoneid'} > 0) {
	  $state{'zone'}=$h{'name'}
	    unless(get_zone($state{'zoneid'},\%h));
	}

	foreach $arg (multi_param()) {
	  next if ($arg =~ /^(login_name|login_pwd|login|submit)$/);
	  $arg_str .= hidden($arg,scalar(param($arg)));
	}

	print '<div class="s-login-wrap">',
	      '<div class="s-login-card">',
	      '<header class="s-login-card__head">',
	      '<span><img src="', $SAURON_ICON_PATH, '/logo.png"',
	      ' alt="Sauron" width="56" height="50"> Sauron v',
	      sauron_version(), '</span>',
	      '<span>', encode_entities($SERVER_ID), '</span>',
	      '</header>',
	      '<div class="s-login-card__body">';

# Is login allowed to superusers only?
	if ($SAURON_TEMP_LOCK && !is_superuser()) {
	    alert1("Sauron is temporarily closed.");
	    logout(0);
	}

	success1("Login ok."); print p,
	      start_form(-method=>'POST',-action=>$s_url), $arg_str || '',
	      submit(-name=>'submit',-value=>'Continue',
		     autofocus=>'true'), end_form;

	# warn about expiring account
	if (defined($user{expiration}) && ($user{expiration} > 0) &&
	     ($user{expiration} < time() + 14*86400) ) {
	  warning1("NOTE! Your account will expire soon (" .
		   localtime($user{expiration}) . ").");
	}

	# print news/MOTD stuff
	my @newslist;
	get_news_list($state{serverid},3,\@newslist);
	if (@newslist > 0) {
	  print '<section class="s-motd" aria-label="Messages of the day">',
	        '<h2 class="s-motd__heading">Message(s) of the day</h2>',
	        '<ul class="s-motd__list">';
	  for $i (0..$#newslist) {
	    $msg=$newslist[$i][3];
	    $date=localtime($newslist[$i][0]);
	    print '<li class="s-motd__item">', $msg,
	          '<div class="s-motd__byline">',
	          encode_entities("-- $newslist[$i][1] $date"),
	          '</div></li>';
	  }
	  print "</ul></section>\n";
	}

	# advertise "save defaults" option for users not having any defaults...
	unless ($state{serverid} > 0 && $state{zoneid} > 0) {
	  print h4("Hint! You can save your server and zone selection using " .
		   "the \"Save Defaults\" command in Login menu.");
	}

	print '</div></div></div>', "\n";
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

  unless ($state{'auth'} eq 'yes') {
    login_form("Login failed.", $scookie);
    # login_form() exits — lines below only reached on successful auth
  }

  print '</div></div></div>', "\n";
  print end_html();
  save_state($scookie,\%state);
  load_state($scookie,\%state) if ($SAURON_AUTH_MODE==1);
  fix_utmp($SAURON_USER_TIMEOUT*2, 0);
  exit;
}

sub top_menu($) {
  my ($mode) = @_;
  my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
  my $env = $SAURON_ENV_NAME // '';

  print '<header class="s-topbar">',
        '<a class="s-topbar__logo" href="https://github.com/tjko/sauron/" target="sauron">',
        '<img src="', $SAURON_ICON_PATH, '/logo.png" width="56" height="50" ',
            'alt="Sauron - DNS/DHCP management">',
        '</a>',
        '<h1 class="s-topbar__title">Sauron</h1>';
  print '<span class="s-topbar__env">', encode_entities($env), '</span>' if (length $env);
  print '<nav class="s-topbar__nav" aria-label="Primary">';
  for my $i (0..$#menulist) {
    my $active = ($menulist[$i][1] =~ /menu=\Q$menu\E(?:&|$)/) ? ' s-topbar__link--active' : '';
    print '<a class="s-topbar__link', $active, '" href="', $s_url, '?', $menulist[$i][1], '">',
          encode_entities($menulist[$i][0]), '</a>';
  }
  print '</nav>';
  printf '<div class="s-topbar__server">%s &nbsp; %d.%d.%d %02d:%02d</div>',
         encode_entities($SERVER_ID), $mday, $mon+1, $year+1900, $hour, $min;
  print '<a class="s-topbar__logout" href="', $s_url, '/logout" target="_top">Logout</a>';
  print '</header>';

  if ($SAURON_TEMP_LOCK == 1 && !is_superuser()) {
      warning1('Please log out from Sauron - maintenance break imminent!');
  }
  if ($SAURON_TEMP_LOCK == 2 && !is_superuser()) {
      alert1('Sorry, Sauron is temporarily closed');
      logout(0);
  }
}



sub left_menu($) {
  my ($mode) = @_;
  my $url = "$s_url?menu=$menu";
  my $l = $menuhash{$menu};

  print '<nav class="s-sidebar__menu" aria-label="', encode_entities($menu), '">',
        '<h2 class="s-sidebar__heading">', encode_entities($menu), '</h2>',
        '<ul class="s-sidebar__list">';
  if (defined $l) {
    for my $i (0..$#{$l}) {
      next if (ref($$l[$i][2]) eq 'ARRAY') and check_perms($$l[$i][2][0], $$l[$i][2][1], 1);
      if ($#{$$l[$i]} < 1) {
        # Separator row from %menuhash (empty array).
        print '<li class="s-sidebar__sep" aria-hidden="true"></li>';
        next;
      }
      next if (defined($$l[$i][2]) && $$l[$i][2] =~ /(^|\|)root/ && !is_superuser());
      next if (defined($$l[$i][2]) && $$l[$i][2] =~ /(^|\|)noframes/);
      next if (defined($$l[$i][2]) && $$l[$i][2] =~ /(^|\|)frames/);
      next if (defined($$l[$i][2]) && $$l[$i][2] =~ /(^|\|)(\d{1,3})$/ && check_perms('level', $2, 1));
      my $name   = $$l[$i][0];
      my $ref    = $$l[$i][1];
      my $u      = $ref ? "$url&$ref" : $url;
      my $cur_sub = param('sub') // '';
      my $active  = '';
      if ($ref) {
        # All key=value pairs in the ref must match the current CGI params.
        # This handles sub=browse&lastsearch=1 vs sub=browse&bh_re_edit=1
        # and sub=add&type=1 vs sub=add&type=4 without special-casing.
        my $match = 1;
        for my $pair (split /&/, $ref) {
          my ($k, $v) = split /=/, $pair, 2;
          $v //= '';
          unless ((param($k) // '') eq $v) { $match = 0; last; }
        }
        $active = ' s-sidebar__link--active' if $match;
      } else {
        # Empty ref = default view; active only when sub is also empty.
        $active = ' s-sidebar__link--active' if $cur_sub eq '';
      }
      print '<li class="s-sidebar__item">',
            '<a class="s-sidebar__link', $active, '" href="', $u, '">',
            $name, '</a>',
            '</li>';
    }
  } else {
    print '<li class="s-sidebar__empty">empty menu</li>';
  }
  print '</ul></nav>';
  # Server/zone context moved to .s-context-bar above the shell grid.
}

sub init_plugins($) {
  my($plugins) = @_;
  my(@plugs) = split(/,/,$plugins);
  my($ALEVEL, $j, $MENU, $MENUDATA, $ret, $i, $file, $file2, $NAME);

  for $i (0..$#plugs) {
    $file="$PROG_DIR/plugins/$plugs[$i].conf";
    $file2="$PROG_DIR/plugins/$plugs[$i].pm";
    if (-r $file) {
      $ALEVEL = 0; # Default required authorization level to use plugin.
      $ret = do "$file";
      if ($@) {
	logmsg("notice","parse error in plugin info: $file");
      } elsif (not $ret) {
	logmsg("notice", "failed to process plugin info: $file");
      }
# Check authorization level of user and plugin. TVu
      next unless (!check_perms('level', $ALEVEL, 1));
      # add commands defined by plugin into appropriate menu...
      for $j (0..$#{$MENUDATA}) {
	push @{$menuhash{$MENU}}, [$$MENUDATA[$j][0],$$MENUDATA[$j][1]];

	# add hook for command (if necessary)...
#	if ($$MENUDATA[$j][2]) {
#	  $menuhooks{$MENU}->{$$MENUDATA[$j][2]}=[$NAME,$file2];

# Add hooks for all 'sub's (it is necessary).
	for my $ind1 (2..$#{$$MENUDATA[$j]}) { # TVu 2021-04-21
	    $menuhooks{$MENU}->{$$MENUDATA[$j][$ind1]}=[$NAME,$file2] if (defined([$NAME,$file2]));
	}
      }
    }
  }

}

# verify first value is defined before testing against passed argument
sub is_superuser() {
    return (defined($state{superuser}) && $state{superuser} eq 'yes') ? 1 : 0;
}
# eof
