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
use Digest::MD5;
use Net::Netmask;
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::Sauron;

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;

$SAURON_CGI_VER = ' $Revision$ $Date$ ';
#$|=1;
$debug_mode = 0;

load_config();

%check_names_enum = (D=>'Default',W=>'Warn',F=>'Fail',I=>'Ignore');
%yes_no_enum = (D=>'Default',Y=>'Yes', N=>'No');
%boolean_enum = (f=>'No',t=>'Yes');


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
	  'servers'=>\&servers_menu,
	  'zones'=>\&zones_menu,
	  'login'=>\&login_menu,
	  'hosts'=>\&hosts_menu,
	  'about'=>\&about_menu,
	  'nets'=>\&nets_menu,
	  'templates'=>\&templates_menu,
	  'groups'=>\&groups_menu
);

%menuhash=(
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
		     ['Add net','sub=addnet'],
		     ['Add subnet','sub=addsub'],
		     [],
		     ['VLANs','sub=vlans'],
		     ['Add vlan','sub=addvlan']
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


sub make_cookie($);
sub login_form($$);
sub login_auth();
sub load_state($);
sub logout();
sub hosts_menu();
sub top_menu($);
sub left_menu($);
sub frame_set();
sub frame_set2();
sub frame_1();
sub frame_2();


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

html_error("Invalid log path (LOG_DIR)") unless (-d $LOG_DIR);
html_error("Cannot write to log file")
  if (logmsg(($debug_mode ? "debug":"test"),"CGI access from $remote_addr")
      < 0);
html_error("No database connection defined (DB_CONNECT)") unless ($DB_CONNECT);
html_error("Cannot connect to database") unless (db_connect2($DB_CONNECT));
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
  unless (load_state($scookie)) {
    logmsg("notice","invalid cookie ($scookie) supplied by $remote_addr");
    undef $scookie;
  }
}

unless ($scookie) {
  logmsg("notice","new connection from: $remote_addr");
  $new_cookie=make_cookie($script_path);
  print header(-cookie=>$new_cookie,-charset=>$SAURON_CHARSET,
	       -target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome",$ncookie);
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
  login_form("Welcome (again)",$scookie);
}

if ((time() - $state{'last'}) > $SAURON_USER_TIMEOUT) {
  logmsg("notice","connection timed out for $remote_addr " .
	 $state{'user'});
  update_lastlog($state{uid},$state{sid},3,$remote_addr,$remote_host);
  print header(-charset=>$SAURON_CHARSET,-target=>'_top',-expires=>'now'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Your session timed out. Login again",$scookie);
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


if ($pathinfo ne '') {
  $frame_mode=1 if ($pathinfo =~ /^\/frame/);
  logout() if ($pathinfo eq '/logout');
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
}


cgi_util_set_zoneid($zoneid);
cgi_util_set_serverid($serverid);
set_muser($state{user});
$bgcolor='black';
$bgcolor='white' if ($frame_mode);

unless ($state{superuser} eq 'yes') {
  html_error("cannot get permissions!")
    if (get_permissions($state{uid},$state{gid},\%perms));
  foreach $rhf_key (keys %{$perms{rhf}}) {
    $SAURON_RHF{$rhf_key}=$perms{rhf}->{$rhf_key};
  }
} else {
  $perms{alevel}=999 if ($state{superuser});
}

if (param('csv')) {
  print header(-type=>'text/csv',-target=>'_new',-attachment=>'results.csv');
  hosts_menu();
  exit(0);
}

####################################################################

%server_form = (
 data=>[
  {ftype=>0, name=>'Server' },
  {ftype=>1, tag=>'name', name=>'Server name', type=>'text', len=>20},
  {ftype=>4, tag=>'id', name=>'Server ID'},
  {ftype=>4, tag=>'masterserver', name=>'Masterserver ID', hidden=>1},
  {ftype=>4, tag=>'server_type', name=>'Server type'},
  {ftype=>1, tag=>'hostname', name=>'Hostname',type=>'fqdn', len=>40,
   default=>'ns.my.domain.'},
  {ftype=>1, tag=>'hostaddr', name=>'IP address',type=>'ip',empty=>0,len=>15},
  {ftype=>3, tag=>'zones_only', name=>'Output mode', type=>'enum',
   conv=>'L', enum=>{t=>'Generate named.zones',f=>'Generate full named.conf'}},
  {ftype=>1, tag=>'comment', name=>'Comments',  type=>'text', len=>60,
   empty=>1},
  {ftype=>3, tag=>'named_flags_isz',
   name=>'Include also slave zones from master',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}, iff=>['masterserver','\d+']},

  {ftype=>0, name=>'Defaults for zones'},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'fqdn', len=>30,
   default=>'hostmaster.my.domain.'},
  {ftype=>1, tag=>'refresh', name=>'Refresh', type=>'int', len=>10},
  {ftype=>1, tag=>'retry', name=>'Retry', type=>'int', len=>10},
  {ftype=>1, tag=>'expire', name=>'Expire', type=>'int', len=>10},
  {ftype=>1, tag=>'minimum', name=>'Minimum (negative caching TTL)',
   type=>'int', len=>10},
  {ftype=>1, tag=>'ttl', name=>'Default TTL', type=>'int', len=>10},
  {ftype=>2, tag=>'txt', name=>'Default zone TXT', type=>['text','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['TXT','comment']},

  {ftype=>0, name=>'Paths'},
  {ftype=>1, tag=>'directory', name=>'Configuration directory', type=>'path',
   len=>30, empty=>0},
  {ftype=>1, tag=>'pzone_path', name=>'Primary zone-file path', type=>'path',
   len=>30, empty=>1},
  {ftype=>1, tag=>'szone_path', name=>'Slave zone-file path', type=>'path',
   len=>30, empty=>1, default=>'NS2/'},
  {ftype=>1, tag=>'named_ca', name=> 'Root-server file', type=>'text', len=>30,
   default=>'named.ca'},
  {ftype=>1, tag=>'pid_file', name=>'pid-file path', type=>'text',
   len=>30, empty=>1},
  {ftype=>1, tag=>'dump_file', name=>'dump-file path', type=>'text',
   len=>30, empty=>1},
  {ftype=>1, tag=>'stats_file', name=>'statistics-file path', type=>'text',
   len=>30, empty=>1},
  {ftype=>1, tag=>'memstats_file', name=>'memstatistics-file path',
   type=>'text', len=>30, empty=>1},
  {ftype=>1, tag=>'named_xfer', name=>'named-xfer path', type=>'text',
   len=>30, empty=>1},

  {ftype=>0, name=>'Server bindings'},
  {ftype=>3, tag=>'forward', name=>'Forward (mode)', type=>'enum',
   conv=>'U', enum=>{'D'=>'Default','O'=>'Only','F'=>'First'}},
  {ftype=>2, tag=>'forwarders', name=>'Forwarders', fields=>2,
   type=>['ip','text'], len=>[20,30], empty=>[0,1],elabels=>['IP','comment']},
  {ftype=>1, tag=>'transfer_source', name=>'Transfer source IP',
   type=>'ip', empty=>1, definfo=>['','Default'], len=>15},
  {ftype=>1, tag=>'query_src_ip', name=>'Query source IP',
   type=>'ip', empty=>1, definfo=>['','Default'], len=>15},
  {ftype=>1, tag=>'query_src_port', name=>'Query source port', 
   type=>'port', empty=>1, definfo=>['','Default port'], len=>5},
  {ftype=>1, tag=>'listen_on_port', name=>'Listen on port',
   type=>'port', empty=>1, definfo=>['','Default port'], len=>5},
  {ftype=>2, tag=>'listen_on', name=>'Listen-on', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1],
   elabels=>['CIDR','comment']},

  {ftype=>0, name=>'Access control'},
  {ftype=>3, tag=>'named_flags_ac', name=>'Use access control from master',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}, iff=>['masterserver','\d+',1]},
  {ftype=>2, tag=>'allow_transfer', name=>'Allow-transfer', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1],
   elabels=>['CIDR','comment'], iff=>['named_flags_ac','0']},
  {ftype=>2, tag=>'allow_query', name=>'Allow-query', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1],
   elabels=>['CIDR','comment'], iff=>['named_flags_ac','0']},
  {ftype=>2, tag=>'allow_recursion', name=>'Allow-recursion', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1],
   elabels=>['CIDR','comment'], iff=>['named_flags_ac','0']},
  {ftype=>2, tag=>'blackhole', name=>'Blackhole', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1],
   elabels=>['CIDR','comment'], iff=>['named_flags_ac','0']},

  {ftype=>0, name=>'BIND options' },
  {ftype=>3, tag=>'named_flags_hinfo', name=>'Do not generate HINFO records',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}},
  {ftype=>3, tag=>'named_flags_wks', name=>'Do not generate WKS records',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}},
  {ftype=>3, tag=>'nnotify', name=>'Notify', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'authnxdomain', name=>'Auth-nxdomain', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'recursion', name=>'Recursion', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'dialup', name=>'Dialup mode', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'multiple_cnames', name=>'Allow multiple CNAMEs',
   type=>'enum',conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'rfc2308_type1', name=>'RFC2308 Type 1 mode',
   type=>'enum',conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'checknames_m', name=>'Check-names (Masters)', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'checknames_s', name=>'Check-names (Slaves)', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'checknames_r', name=>'Check-names (Responses)',type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>1, tag=>'version', name=>'Version string',  type=>'text', len=>60,
   empty=>1, definfo=>['','Default']},
  {ftype=>2, tag=>'logging', name=>'Logging options', type=>['text','text'],
   fields=>2, len=>[50,20], maxlen=>[100,20], empty=>[0,1],
   elabels=>['logging option','comment']},
  {ftype=>2, tag=>'custom_opts', name=>'Custom (BIND) options',
   type=>['text','text'], fields=>2, len=>[50,20], maxlen=>[100,20],
   empty=>[0,1], elabels=>['BIND option','comment']},

  {ftype=>0, name=>'DHCP Settings'},
  {ftype=>3, tag=>'dhcp_flags_ad', name=>'auto-domainnames',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}, iff=>['masterserver','-1']},
  {ftype=>2, tag=>'dhcp', name=>'Global DHCP Settings', type=>['text','text'],
   fields=>2, len=>[50,20], maxlen=>[200,20], empty=>[0,1],
   elabels=>['dhcptab line','comment'], iff=>['masterserver','-1']},

  {ftype=>0, name=>'DHCP Failover Settings'},
  {ftype=>3, tag=>'dhcp_flags_fo', name=>'Enable failover protocol',
   type=>'enum', enum=>{0=>'No',1=>'Yes'}, iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_port', name=>'Port number', type=>'int', len=>5,
   iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_max_delay', name=>'Max Response Delay',
   type=>'int', len=>5, iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_max_uupdates', name=>'Max Unacked Updates',
   type=>'int', len=>5, iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_mclt', name=>'MCLT', type=>'int', len=>6,
   iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_split', name=>'Split', type=>'int', len=>5,
   iff=>['masterserver','-1']},
  {ftype=>1, tag=>'df_loadbalmax', name=>'Load balance max (seconds)',
   type=>'int', len=>5, iff=>['masterserver','-1']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
# bgcolor=>'#eeeebf',
# border=>'0',		
# width=>'100%',
# nwidth=>'30%',
# heading_bg=>'#aaaaff'
);

%new_server_form=(
 data=>[
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>20, empty=>0},
  {ftype=>1, tag=>'hostname', name=>'Hostname',type=>'fqdn', len=>40,
   default=>'ns.my.domain.'},
  {ftype=>1, tag=>'hostaddr', name=>'IP address',type=>'ip',empty=>0,len=>15},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'fqdn', len=>30,
   default=>'hostmaster.my.domain.'},
  {ftype=>1, tag=>'directory', name=>'Configuration directory', type=>'path',
   len=>30, empty=>0},
  {ftype=>3, tag=>'masterserver', name=>'Slave for', type=>'enum',
   enum=>\%master_servers,elist=>\@master_serversl},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ]
);

%new_zone_form=(
 data=>[
  {ftype=>0, name=>'New zone'},
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'zonename',
   len=>60, empty=>0},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward'}},
  {ftype=>3, tag=>'reverse', name=>'Reverse', type=>'enum',  conv=>'L',
   enum=>{f=>'No',t=>'Yes'}}
 ]
);

%zone_form = (
 data=>[
  {ftype=>0, name=>'Zone' },
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'zonename', len=>60},
  {ftype=>4, tag=>'reversenet', name=>'Reverse net', iff=>['reverse','t']},
  {ftype=>4, tag=>'id', name=>'Zone ID'},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>60,
   empty=>1},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward'}},
  {ftype=>4, tag=>'reverse', name=>'Reverse', type=>'enum',
   enum=>{f=>'No',t=>'Yes'}, iff=>['type','M']},
  {ftype=>3, tag=>'txt_auto_generation',
   name=>'Info TXT record auto generation', type=>'enum',
   enum=>{0=>'No',1=>'Yes'}, iff=>['type','M']},
  {ftype=>3, tag=>'dummy', name=>'"Dummy" zone', type=>'enum',
   enum=>\%boolean_enum, iff=>['type','M'] },
  {ftype=>3, tag=>'class', name=>'Class', type=>'enum', conv=>'L',
   enum=>{in=>'IN (internet)',hs=>'HS',hesiod=>'HESIOD',chaos=>'CHAOS'}},
  {ftype=>2, tag=>'masters', name=>'Masters', type=>['ip','text'], fields=>2,
   len=>[15,45], empty=>[0,1], elabels=>['IP','comment'], iff=>['type','S']},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'domain', len=>30,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>3, tag=>'chknames', name=>'Check-names', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'nnotify', name=>'Notify', type=>'enum', conv=>'U',
   enum=>\%yes_no_enum, iff=>['type','M']},
  {ftype=>3, tag=>'forward', name=>'Forward', type=>'enum', conv=>'U',
   enum=>{D=>'Default',O=>'Only',F=>'First'}, iff=>['type','F'] },
  {ftype=>1, tag=>'transfer_src', name=>'Transfer-Source (address)',
   type=>'ip', len=>12, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','S']},
  {ftype=>4, tag=>'serial', name=>'Serial', iff=>['type','M']},
  {ftype=>1, tag=>'refresh', name=>'Refresh', type=>'int', len=>10, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'retry', name=>'Retry', type=>'int', len=>10, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'expire', name=>'Expire', type=>'int', len=>10,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'minimum', name=>'Minimum (negative caching TTL)',
   empty=>1, definfo=>['','Default (from server)'], type=>'int', len=>10,
   iff=>['type','M']},
  {ftype=>1, tag=>'ttl', name=>'Default TTL', type=>'int', len=>10,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>5, tag=>'ip', name=>'IP addresses (A)', iff=>['type','M'],
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'ns', name=>'Name servers (NS)', type=>['text','text'],
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'mx', name=>'Mail exchanges (MX)', 
   type=>['int','text','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1], 
   elabels=>['Priority','MX','comment'], iff=>['type','M'], 
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'txt', name=>'Info (TXT)', type=>['text','text'], fields=>2,
   len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','M'],
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'zentries', name=>'Custom zone file entries',
   type=>['text','text'], fields=>2, len=>[40,15], maxlen=>[100,20],
   empty=>[0,1], elabels=>['Zone Entry','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'allow_update', 
   name=>'Allow dynamic updates (allow-update)', type=>['cidr','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['CIDR','comment'],
   iff=>['type','M']},
  {ftype=>2, tag=>'allow_query', 
   name=>'Allow queries from (allow-query)', type=>['cidr','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['CIDR','comment'],
   iff=>['type','M']},
  {ftype=>2, tag=>'allow_transfer', 
   name=>'Allow zone-transfers from (allow-transfer)', type=>['cidr','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['CIDR','comment'],
   iff=>['type','M']},
  {ftype=>2, tag=>'also_notify', 
   name=>'[Stealth] Servers to notify (also-notify)', type=>['ip','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['IP','comment'],
   iff=>['type','M']},
  {ftype=>2, tag=>'forwarders',name=>'Forwarders', type=>['ip','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['IP','comment'],
   iff=>['type','F']},

  {ftype=>0, name=>'DHCP', iff=>['type','M']},
  {ftype=>2, tag=>'dhcp', name=>'Zone specific DHCP entries',
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment'], iff=>['type','M']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>4, name=>'Pending host record changes', tag=>'pending_info',
   no_edit=>1, iff=>['type','M']}
 ]
);



%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
	     8=>'SRV record',9=>'DHCP only',10=>'zone',
	     101=>'Host reservation');

%host_form = (
 data=>[
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain',
   conv=>'L', len=>40, iff=>['type','([^82]|101)']},
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)', type=>'zonename',
   len=>40,conv=>'L', iff=>['type','[2]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>40,
   conv=>'L', iff=>['type','[8]']},
  {ftype=>5, tag=>'ip', name=>'IP address', iff=>['type','([169]|101)']},
  {ftype=>9, tag=>'alias_d', name=>'Alias for', idtag=>'alias',
   iff=>['type','4'], iff2=>['alias','\d+']},
  {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
   len=>60, iff=>['type','4'], iff2=>['alias','-1']},
  {ftype=>8, tag=>'alias_a', name=>'Alias for host(s)', fields=>3,
   arec=>1, iff=>['type','7']},
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'alias', name=>'Alias ID', iff=>['type','4']},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>4, tag=>'class', name=>'Class'},
  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1,
   definfo=>['','Default']},
  {ftype=>1, tag=>'router', name=>'Router (priority)', type=>'priority',
   len=>10, empty=>0,definfo=>['0','No'], iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   empty=>1},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer',
   iff=>['type','[19]']},
  {ftype=>1, tag=>'ether_alias_info', name=>'Ethernet alias', no_empty=>1,
   empty=>1, type=>'domain', len=>30, iff=>['type','1'] },

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50, empty=>1,
   no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50, empty=>1,
   no_empty=>1, iff=>['type','(1|101)']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','[13]']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},

  {ftype=>0, name=>'Host specific',iff=>['type','[12]']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['domain','text'],
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
  {ftype=>2, tag=>'dhcp_l', name=>'DHCP entries', no_empty=>1,
   type=>['text','text'], fields=>2,len=>[50,20], maxlen=>[200,20],
   empty=>[0,1],elabels=>['DHCP','comment'], iff=>['type','[15]']},

  {ftype=>0, name=>'Aliases', no_edit=>1, iff=>['type','1']},
  {ftype=>8, tag=>'alias_l', name=>'Aliases', fields=>3, iff=>['type','1']},

  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,10],
   empty=>[0,0,0,0,1],elabels=>['Priority','Weight','Port','Target','Comment'],
   type=>['priority','priority','priority','fqdn','text'],
   iff=>['type','8']},

  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']},
  {ftype=>4, name=>'Last lease issued by DHCP server', tag=>'dhcp_date_str',
   no_edit=>1, iff=>['type','[19]']}
 ]
);


%restricted_host_form = (
 data=>[
  {ftype=>0, name=>'Host (restricted edit)' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain',
   conv=>'L', len=>40},
  {ftype=>5, tag=>'ip', name=>'IP address', restricted_mode=>1,
   iff=>['type','([169]|101)']},
  {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
   len=>60, iff=>['type','4'], iff2=>['alias','-1']},
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40,
   empty=>$SAURON_RHF{huser}, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30,
   empty=>$SAURON_RHF{dept}, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   empty=>$SAURON_RHF{location}, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   empty=>$SAURON_RHF{info}},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], iff2=>['ether_alias_info',''],
   empty=>$SAURON_RHF{ether}},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','101'], iff2=>['ether_alias_info',''], empty=>1},
  {ftype=>4, tag=>'ether_alias_info', name=>'Ethernet alias',
   iff=>['type','1']},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$SAURON_RHF{asset_id}, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   empty=>$SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>$SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   empty=>$SAURON_RHF{misc}, iff=>['type','(1|101)']},

#  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ]
);


%new_host_nets = (dummy=>'dummy');
@new_host_netsl = ('dummy');

%new_host_form = (
 data=>[
  {ftype=>0, name=>'New record' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>40,
   conv=>'L', iff=>['type','[^82]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (reservation)',
   type=>'domain', len=>40, conv=>'L', iff=>['type','101']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>40,
   conv=>'L', iff=>['type','[8]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)',
   type=>'zonename', len=>40, conv=>'L', iff=>['type','[2]']},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>60,
   iff=>['type','4']},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'enum',
   enum=>\%new_host_nets,elist=>\@new_host_netsl, iff=>['type','(1|101)']},
  {ftype=>1, tag=>'ip',
   name=>'IP<FONT size=-1>(only if "Manual IP" selected from above)</FONT>',
   type=>'ip', len=>15, empty=>1, iff=>['type','(1|101)']},
  {ftype=>1, tag=>'ip', name=>'IP',
   type=>'ip', len=>15, empty=>1, iff=>['type','9']},
  {ftype=>1, tag=>'glue',name=>'IP',type=>'ip', len=>15, iff=>['type','6']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)',
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], iff=>['type','3']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['domain','text'],
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2,len=>[40,20], empty=>[0,1], 
   elabels=>['PRINTER','comment'], iff=>['type','5']},
  {ftype=>1, tag=>'router', name=>'Router (priority)', type=>'priority', 
   len=>10, empty=>0,definfo=>['0','No'], iff=>['type','1']},
  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','(1|9|101)'], empty=>1},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20, 
   empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50, empty=>1, 
   iff=>['type','(1|101)']},

  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,10],
   empty=>[0,0,0,0,1],elabels=>['Priority','Weight','Port','Target','Comment'],
   type=>['priority','priority','priority','fqdn','text'],
   iff=>['type','8']},

  {ftype=>0, name=>'Record info', iff=>['type','[147]']},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ]
);

%restricted_new_host_form = (
 data=>[
  {ftype=>0, name=>'New record (restricted)' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>40,
   conv=>'L'},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>60,
   iff=>['type','4']},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'enum',
   enum=>\%new_host_nets,elist=>\@new_host_netsl,iff=>['type','1']},
  {ftype=>1, tag=>'ip', 
   name=>'IP<FONT size=-1>(only if "Manual IP" selected from above)</FONT>', 
   type=>'ip', len=>15, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ip', name=>'IP', 
   type=>'ip', len=>15, empty=>1, iff=>['type','9']},
  {ftype=>1, tag=>'glue',name=>'IP',type=>'ip', len=>15, iff=>['type','6']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)',
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], iff=>['type','3']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['text','text'],
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2,len=>[40,20], empty=>[0,1], 
   elabels=>['PRINTER','comment'], iff=>['type','5']},
 # {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40,
   empty=>$SAURON_RHF{huser}, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30,
   empty=>$SAURON_RHF{dept}, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   empty=>$SAURON_RHF{location}, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   empty=>$SAURON_RHF{info} },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>0, empty=>0, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>0, empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], empty=>$SAURON_RHF{ether}},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$SAURON_RHF{asset_id}, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   empty=>$SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>$SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   empty=>$SAURON_RHF{misc}, iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ]
);


%new_alias_form = (
 data=>[
  {ftype=>0, name=>'New Alias' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>40},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum',
   enum=>{4=>'CNAME',7=>'AREC'}},
  {ftype=>0, name=>'Alias for'},
  {ftype=>4, tag=>'aliasname', name=>'Host'},
  {ftype=>4, tag=>'alias', name=>'ID'}
 ]
);


%browse_page_size=(0=>'25',1=>'50',2=>'100',3=>'256',4=>'512',5=>'1000');
%browse_search_fields=(0=>'Ether',1=>'Info',2=>'User',3=>'Location',
		       4=>'Department',5=>'Model',6=>'Serial',7=>'Misc',
		       -1=>'<ANY>');
@browse_search_f=('ether','info','huser','location','dept','model',
		  'serial','misc');

%browse_hosts_form=(
 data=>[
  {ftype=>0, name=>'Search scope' },
  {ftype=>3, tag=>'type', name=>'Record type', type=>'enum',
   enum=>\%host_types},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'list', listkeys=>'nets_k', 
   list=>'nets'},
  {ftype=>1, tag=>'cidr', name=>'CIDR (block) or IP', type=>'cidr',
   len=>20, empty=>1},
  {ftype=>1, tag=>'domain', name=>'Domain pattern (regexp)', type=>'text',
   len=>40, empty=>1},
  {ftype=>0, name=>'Options' },
  {ftype=>3, tag=>'order', name=>'Sort order', type=>'enum',
   enum=>{1=>'by hostname',2=>'by IP'}},
  {ftype=>3, tag=>'size', name=>'Entries per page', type=>'enum',
   enum=>\%browse_page_size},
  {ftype=>0, name=>'Search' },
  {ftype=>3, tag=>'stype', name=>'Search field', type=>'enum',
   enum=>\%browse_search_fields},
  {ftype=>1, tag=>'pattern',name=>'Pattern (regexp)',type=>'text',len=>40,
   empty=>1}
 ]
);

%user_info_form=(
 data=>[
  {ftype=>0, name=>'User info' },
  {ftype=>4, tag=>'user', name=>'Login'},
  {ftype=>4, tag=>'name', name=>'User Name'},
  {ftype=>4, tag=>'groupname', name=>'Group'},
  {ftype=>4, tag=>'login', name=>'Last login', type=>'localtime'},
  {ftype=>4, tag=>'addr', name=>'Host'},
  {ftype=>4, tag=>'last_pwd', name=>'Last password change', type=>'localtime'},
  {ftype=>4, tag=>'expiration', name=>'Account expiration'},
  {ftype=>4, tag=>'superuser', name=>'Superuser', iff=>['superuser','yes']},
  {ftype=>0, name=>'Personal settings'},
  {ftype=>4, tag=>'email', name=>'Email'},
  {ftype=>4, tag=>'email_notify', name=>'Email notifications',type=>'enum',
   enum=>{0=>'Disabled',1=>'Enabled'}},
  {ftype=>0, name=>'Current selections'},
  {ftype=>4, tag=>'server', name=>'Server'},
  {ftype=>4, tag=>'zone', name=>'Zone'},
  {ftype=>4, tag=>'sid', name=>'Session ID (SID)'}
 ]
);

%user_settings_form=(
 data=>[
  {ftype=>0, name=>'Settings' },
  {ftype=>1, tag=>'email', name=>'Email', type=>'email'},
  {ftype=>3, tag=>'email_notify', name=>'Email notifications',type=>'enum',
   enum=>{0=>'Disabled',1=>'Enabled'}},
 ]
);


%new_net_form=(
 data=>[
  {ftype=>1, tag=>'netname', name=>'NetName', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'name', name=>'Description', type=>'text',
   len=>60, empty=>0},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ]
);

%net_form=(
 data=>[
  {ftype=>0, name=>'Net'},
  {ftype=>1, tag=>'netname', name=>'NetName', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'name', name=>'Description', type=>'text',
   len=>60, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>3, tag=>'vlan', name=>'VLAN', type=>'enum', conv=>'L',
   enum=>\%vlan_list_hash, elist=>\@vlan_list_lst, restricted=>1},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>3, tag=>'private_flag', name=>'Private (hide from browser)',
   type=>'enum',enum=>{0=>'No',1=>'Yes'}},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1},
  {ftype=>0, name=>'Auto assign address range', iff=>['subnet','t']},
  {ftype=>1, tag=>'range_start', name=>'Range start', type=>'ip', 
   empty=>1, iff=>['subnet','t']},
  {ftype=>1, tag=>'range_end', name=>'Range end', type=>'ip',
   empty=>1, iff=>['subnet','t']},
  {ftype=>0, name=>'DHCP'},
  {ftype=>3, tag=>'no_dhcp', name=>'DHCP', type=>'enum', conv=>'L',
   enum=>{f=>'Enabled',t=>'Disabled'}},
  {ftype=>2, tag=>'dhcp_l', name=>'Net specific DHCP entries', 
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ],
 mode=>1
);


%vlan_form=(
 data=>[
  {ftype=>0, name=>'VLAN (Layer-2 Network / Shared Network)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>4, tag=>'id', name=>'ID', no_edit=>0},
  {ftype=>1, tag=>'description', name=>'Description', type=>'text',
   len=>60, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text',
   len=>60, empty=>1},

  {ftype=>0, name=>'DHCP'},
  {ftype=>2, tag=>'dhcp_l', name=>'VLAN specific DHCP entries',
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%new_vlan_form=(
 data=>[
  {ftype=>0, name=>'VLAN (Layer-2 Network / Shared Network)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'description', name=>'Description', type=>'text',
   len=>40, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text',
   len=>60, empty=>1}
 ]
);


%net_info_form=(
 data=>[
  {ftype=>0, name=>'Net'},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>1, tag=>'base', name=>'Base', type=>'cidr'},
  {ftype=>1, tag=>'netmask', name=>'Netmask', type=>'cidr'},
  {ftype=>1, tag=>'hostmask', name=>'Hostmask', type=>'cidr'},
  {ftype=>1, tag=>'broadcast', name=>'Broadcast address', type=>'cidr'},
  {ftype=>1, tag=>'size', name=>'Size', type=>'int'},
  {ftype=>0, name=>'Usable address range'},
  {ftype=>1, tag=>'first', name=>'Start', type=>'int'},
  {ftype=>1, tag=>'last', name=>'End', type=>'int'},
  {ftype=>1, tag=>'ssize', name=>'Usable addresses', type=>'int'},
  {ftype=>0, name=>'Address Usage'},
  {ftype=>1, tag=>'inuse', name=>'Addresses in use', type=>'int'},
  {ftype=>1, tag=>'inusep', name=>'Usage', type=>'int'},
  {ftype=>0, name=>'Routers'},
  {ftype=>1, tag=>'gateways', name=>'Gateway(s)', type=>'text'}
 ],
 nwidth=>'40%'
);


%host_net_info_form=(
 data=>[
  {ftype=>0, name=>'Host Network Settings'},
  {ftype=>1, tag=>'ip', name=>'IP', type=>'cidr'},
  {ftype=>1, tag=>'mask', name=>'Netmask', type=>'cidr'},
  {ftype=>1, tag=>'gateway', name=>'Gateway (default)', type=>'cidr'},
  {ftype=>0, name=>'Additional Network Settings'},
  {ftype=>1, tag=>'base', name=>'Network address', type=>'cidr'},
  {ftype=>1, tag=>'broadcast', name=>'Broadcast address', type=>'cidr'}
 ],
 nwidth=>'40%'
);


%group_type_hash = (1=>'Normal',2=>'Dynamic Address Pool',3=>'DHCP class');

%group_form=(
 data=>[
  {ftype=>0, name=>'Group'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text', len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', enum=>\%group_type_hash},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1},
  {ftype=>2, tag=>'dhcp', name=>'DHCP entries', 
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment']},
  {ftype=>2, tag=>'printer', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2, len=>[40,20], empty=>[0,1], 
   elabels=>['PRINTER','comment'], iff=>['type','[1]']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%copy_zone_form=(
 data=>[
  {ftype=>0, name=>'Source zone'},
  {ftype=>4, tag=>'source', name=>'Source zone'},
  {ftype=>0, name=>'Target zone'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'domain', len=>40, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1}
 ]
);

%mx_template_form=(
 data=>[
  {ftype=>0, name=>'MX template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)',
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20],
   empty=>[0,0,1],elabels=>['Priority','MX','comment']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%wks_template_form=(
 data=>[
  {ftype=>0, name=>'WKS template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,1,1], 
   elabels=>['Protocol','Services','comment']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%printer_class_form=(
 data=>[
  {ftype=>0, name=>'PRINTER class'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'printer_class',len=>20,
   empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER', 
   type=>['text','text'], fields=>2, len=>[60,10], empty=>[0,1],
   elabels=>['Printer','comment']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%hinfo_template_form=(
 data=>[
  {ftype=>0, name=>'HINFO template'},
  {ftype=>1, tag=>'hinfo', name=>'HINFO', type=>'hinfo',len=>20, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID', iff=>['id','\d+']},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum',
   enum=>{0=>'Hardware',1=>'Software'}},
  {ftype=>1, tag=>'pri', name=>'Priority', type=>'priority',len=>4, empty=>0},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);


%new_motd_enum = (-1=>'Global');

%new_motd_form=(
 data=>[
  {ftype=>0, name=>'Add news message'},
  {ftype=>3, tag=>'server', name=>'Message type', type=>'enum',
   enum=>\%new_motd_enum},
  {ftype=>1, tag=>'info', name=>'Message', type=>'textarea', rows=>5,
   columns=>50 }
 ]
);


%change_passwd_form=(
 data=>[
  {ftype=>1, tag=>'old', name=>'Old password', type=>'passwd', len=>20 },
  {ftype=>0, name=>'Type new password twice'},
  {ftype=>1, tag=>'new1', name=>'New password', type=>'passwd', len=>20 },
  {ftype=>1, tag=>'new2', name=>'New password', type=>'passwd', len=>20 }
 ]
);

%session_id_form=(
 data=>[
  {ftype=>0, name=>'Session browser'},
  {ftype=>1, tag=>'sid', name=>'SID', type=>'int', len=>8, empty=>1 }
 ]
);

########################################################################

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
		   -meta=>{keywords=>'Sauron DNS DHCP tool'},-head=>$refresh);
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
  print "</TD><TD align=\"left\" valign=\"top\" bgcolor=\"#ffffff\">\n";
} else {
  #print "<TABLE width=100%><TR bgcolor=\"#ffffff\"><TD>";
}


print "<br>" unless ($frame_mode);
if ($menuref=$menus{$menu}) { &$menuref; }
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

# SERVERS menu
#
sub servers_menu() {
  $sub=param('sub');

  goto select_server if ($serverid && check_perms('server','R'));


  if ($sub eq 'add') {
    return if (check_perms('superuser',''));
    get_server_list(-1,\%master_servers,\@master_serversl);
    $data{masterserver}=-1;
    $res=add_magic('srvadd','Server','servers',\%new_server_form,
		   \&add_server,\%data);
    if ($res > 0) {
      #print "<p>$res $data{name}";
      $serverid=$res;
      goto display_new_server;
    }

    return;
  }

  if (($sub eq 'del') && ($serverid > 0)) {
    return if (check_perms('superuser',''));

    if (param('srvdel_submit') ne '') {
      if (delete_server($serverid) < 0) {
	print h2("Cannot delete server!");
      } else {
	print h2('Server deleted successfully!');
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
    return if (check_perms('superuser',''));

    $res=edit_magic('srv','Server','servers',\%server_form,
		    \&get_server,\&update_server,$serverid);
    goto select_zone if ($res == -1);
    goto display_new_server if ($res == 1 || $res == 2);
    return;
  }


  $serverid=param('server_list') if (param('server_list'));
 display_new_server:
  if ($serverid && $sub ne 'select') {
    #display selected server info
    if ($serverid < 1) {
      print h3("Cannot select server!"),p;
      goto select_server;
    }
    goto select_server if(check_perms('server','R'));
    get_server($serverid,\%serv);
    $server=$serv{name};
    print h2("Selected server: $server"),p;
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
  get_server_list(-1,\%srec,\@l);
  delete $srec{-1};
  shift @l;
  print h2("Select server:"),p,
    startform(-method=>'POST',-action=>$selfurl),
    hidden('menu','servers'),p,
    "Available servers:",p,
      scrolling_list(-width=>'100%',-name=>'server_list',
		   -size=>'10',-values=>\@l,-labels=>\%srec),
      br,submit(-name=>'server_select_submit',-value=>'Select server'),
      end_form;

}


# ZONES menu
#
sub zones_menu() {
  $sub=param('sub');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

  if ($sub eq 'add') {
    return if (check_perms('superuser',''));

    $data{server}=$serverid;
    if (param('add_submit')) {
      unless (($res=form_check_form('addzone',\%data,\%new_zone_form))) {
	if ($data{reverse} eq 't' || $data{reverse} == 1) {
	  $new_net=arpa2cidr($data{name});
	  if ($new_net eq '0.0.0.0/0') {
	    print h2('Invalid name for reverse zone!');
	    goto new_zone_edit;
	  }
	  $data{reversenet}=$new_net;
	}

	$res=add_zone(\%data);
	if ($res < 0) {
	  print "<FONT color=\"red\">",h1("Adding Zone record failed!"),
	      "result code=$res</FONT>";
	} else {
	  param('selected_zone',$data{name});
	  goto display_zone;
	}
      } else {
	print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
      }
    }
  new_zone_edit:
    unless (param('addzone_re_edit')) { $data{type}='M'; }
    print h2("New Zone:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','zones'),hidden('sub','add');
    form_magic('addzone',\%data,\%new_zone_form);
    print submit(-name=>'add_submit',-value=>"Create Zone"),end_form;
    return;
  }
  elsif ($sub eq 'Delete') {
    return if (check_perms('superuser',''));

    $|=1 if ($frame_mode);
    $res=delete_magic('zn','Zone','zones',\%zone_form,\&get_zone,
		      \&delete_zone,$zoneid);
    if ($res == 1) {
      $state{'zone'}='';
      $state{'zoneid'}=-1;
      save_state($scookie);
      goto select_zone;
    }
    goto display_zone if ($res == 2);
    goto select_zone if ($res == -1);
    return;
  }
  elsif ($sub eq 'Edit') {
    return if (check_perms('superuser',''));

    $res=edit_magic('zn','Zone','zones',\%zone_form,\&get_zone,\&update_zone,
		    $zoneid);
    goto select_zone if ($res == -1);
    goto display_zone if ($res == 2 || $res == 1);
    return;
  }
  elsif ($sub eq 'Copy') {
    return if (check_perms('superuser',''));

    if ($zoneid < 1) {
      print h2("No zone selected!");
      return;
    }
    if (param('copy_cancel')) {
      print h2("Zone copy cancelled.");
      return;
    }
    if (param('copy_confirm')) {
      unless ($res=form_check_form('copy',\%data,\%copy_zone_form)) {
	$|=1; # if ($frame_mode);
	print p,"Copying zone...please wait few minutes (or hours :)";
	$res=copy_zone($zoneid,$serverid,$data{name},1);
	if ($res < 0) {
	  print '<FONT color="red">',h2("Zone copy failed! ($res)"),
	        '</FONT>';
	} else {
	  print h2("Zone successfully copied (id=$res).");
	}
	return;
      } else {
	print '<FONT color="red">',h2('Invalid data in form!'),'</FONT>';
      }
    }

    $data{source}=$zone;
    print h2("Copy Zone:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','zones'),hidden('sub','Copy');
    form_magic('copy',\%data,\%copy_zone_form);
    print submit(-name=>'copy_confirm',-value=>'Copy Zone')," ",
          submit(-name=>'copy_cancel',-value=>'Cancel'),end_form;
    return;
  }
  elsif ($sub eq 'pending') {
    return if (check_perms('zone','R'));
    print h2("Pending changes to host records:");

    undef @q;
    db_query("SELECT h.id,h.domain,h.cdate,h.mdate,h.cuser,h.muser,h.type " .
	     "FROM hosts h, zones z " .
	     "WHERE z.id=$zoneid AND h.zone=z.id " .
	     " AND (h.mdate > z.serial_date OR h.cdate > z.serial_date) " .
	     "ORDER BY h.domain LIMIT 100;",\@q);

    for $i (0..$#q) {
      $action=($q[$i][2] > $q[$i][3] ? 'Create' : 'Modify');
      $date=localtime(($action eq 'Create' ? $q[$i][2] : $q[$i][3]));
      $user=($action eq 'Create' ? $q[$i][4] : $q[$i][5]);
      $name="<a href=\"$selfurl?menu=hosts&h_id=$q[$i][0]\">$q[$i][1]</a>";
      push @plist, ["$i.",$name,$host_types{$q[$i][6]},$action,$date,$user];
    }
    display_list(['#','Hostname','Type','Action','Date','By'],\@plist,0);
    print "<br>";
    return;
  }
  elsif ($sub eq 'AddDefaults') {
    return if (check_perms('superuser',''));
    print h2("Adding default zones...");
    print "<br><pre>";
    add_default_zones($serverid,1);
    print "</pre><br>";
    return;
  }

 display_zone:
  $zone=param('selected_zone');
  $zone=$state{'zone'} unless ($zone);
  if ($zone && $sub ne 'select') {
    #display selected zone info
    $zoneid=get_zone_id($zone,$serverid);
    if ($zoneid < 1) {
      print h3("Cannot select zone '$zone'!"),p;
      goto select_zone;
    }
    goto select_zone if (check_perms('zone','R'));
    print h2("Selected zone: $zone"),p;
    get_zone($zoneid,\%zn);
    $state{'zone'}=$zone;
    $state{'zoneid'}=$zoneid;
    save_state($scookie);

    display_form(\%zn,\%zone_form);
    return;
  }


 select_zone:
  #display zone selection list
  %ztypecolors=(M=>'#c0ffc0',S=>'#eeeeff',F=>'#eedfdf',H=>'#eeeebf');
  %ztypenames=(M=>'Master',S=>'Slave',F=>'Forward',H=>'Hint');

  print h2("Select zone:"),p,"<TABLE width=98% bgcolor=white border=0>",
        "<TR bgcolor=\"#aaaaff\">",th(['Zone','Type','Reverse','Comments']);
  $list=get_zone_list($serverid,0,0);
  for $i (0 .. $#{$list}) {
    $type=$ztypenames{$$list[$i][2]};
    $color=$ztypecolors{$$list[$i][2]};
    $rev=(($$list[$i][3] eq 't' || $$list[$i][3] == 1) ? 'Yes' : 'No');
    $id=$$list[$i][1];
    $name=$$list[$i][0];
    $comment=$$list[$i][4].'&nbsp;';

    if ($SAURON_PRIVILEGE_MODE==1) {
      next unless ($perms{zone}->{$id} =~ /R/);
    }

    print "<TR bgcolor=\"$color\">",td([
	"<a href=\"$selfurl?menu=zones&selected_zone=$name\">$name</a>",
				    $type,$rev,$comment]);
    $zonelist{$name}=$id;
  }
  print "</TABLE><BR>";

  get_server($serverid,\%server);
  if ($server{masterserver} > 0) {
    %ztypecolors=(M=>'#eedeff',S=>'#eeeeff',F=>'#eedfdf',H=>'#eeeebf');
    %ztypenames=(M=>'Slave (Master)',S=>'Slave',F=>'Forward',H=>'Hint');

    print h4("Zones from master server:"),
          p,"<TABLE width=98% bgcolor=white border=0>",
        "<TR bgcolor=\"#aaaaff\">",th(['Zone','Type','Reverse','Comments']);
    $list=get_zone_list($server{masterserver},0,0);
    for $i (0 .. $#{$list}) {
      $type=$$list[$i][2];
      next if ($server{named_flags_isz}!=1 && $type !~ /^M/);
      next unless ($type =~ /^[MS]$/);
      $type=$ztypenames{$$list[$i][2]};
      $color=$ztypecolors{$$list[$i][2]};
      $rev=(($$list[$i][3] eq 't' || $$list[$i][3] == 1) ? 'Yes' : 'No');
      $id=$$list[$i][1];
      $name=$$list[$i][0];
      $comment=$$list[$i][4].'&nbsp;';
      next if ($zonelist{$name});
      print "<TR bgcolor=$color>",td([$name,$type,$rev,$comment]);
    }
    print "</TABLE><BR>";

  }


}


# HOSTS menu
#
sub hosts_menu() {
  unless ($serverid > 0) {
    alert1("Server not selected!");
    return;
  }
  unless ($zoneid > 0) {
    alert1("Zone not selected!");
    return;
  }
  return if (check_perms('zone','R'));

  $id=param('h_id');
  if ($id > 0) {
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }
  }

  $sub=param('sub');
  $host_form{alias_l_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_a_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_d_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alevel}=$restricted_host_form{alevel}=$perms{alevel};
  $new_host_form{alevel}=$restricted_new_host_form{alevel}=$perms{alevel};

  if ($sub eq 'Delete') {
    return unless ($id > 0);
    goto show_host_record if (check_perms('delhost',$host{domain}));

    $res=delete_magic('h','Host','hosts',\%host_form,\&get_host,\&delete_host,
		      $id);
    goto show_host_record if ($res == 2);
    if ($res==1) {
      update_history($state{uid},$state{sid},1,
		    "DELETE: $host_types{$host{type}} ",
		    "domain: $host{domain}, ip:$host{ip}[1][1], " .
		    "ether: $host{ether}",$host{id});
    }
    return;
  }
  elsif ($sub eq 'Alias') {
    if ($id > 0) {
      $data{alias}=$id;
      $data{aliasname}=$host{domain};
      goto show_host_record if (check_perms('host',$host{domain}));
    }

    $data{type}=4;
    $data{zone}=$zoneid;
    $data{alias}=param('aliasadd_alias') if (param('aliasadd_alias'));
    $res=add_magic('aliasadd','ALIAS','hosts',\%new_alias_form,
		   \&restricted_add_host,\%data);
    if ($res > 0) {
      update_history($state{uid},$state{sid},1,
	   	    "ALIAS: $host_types{$data{type}} ",
		    "domain: $data{domain}, alias=$data{alias}",$res);
      param('h_id',$res);
      goto show_host_record;
    }
    elsif ($res < 0) {
      param('h_id',param('aliasadd_alias'));
      goto show_host_record;
    }
    return;
  }
  elsif ($sub eq 'Move') {
    return unless ($id > 0);
    goto show_host_record if (check_perms('host',$host{domain}));

    if ($#{$host{ip}} > 1) {
      alert2("Host has multiple IPs!");
      print  p,"Move of hosts with multiple IPs not supported (yet)";
      return;
    }
    if (param('move_cancel')) {
      print h2("Host record not moved");
      goto show_host_record;
    } elsif (param('move_confirm')) {
      if (param('move_confirm2')) {
	if (not is_cidr(param('new_ip'))) {
	  alert1('Invalid IP!');
	} elsif (ip_in_use($serverid,param('new_ip'))) {
	  alert1('IP already in use!');
	} elsif (check_perms('ip',param('new_ip'),1)) {
	  alert1('Invalid IP number: outside allowed range(s)');
	} else {
	  $old_ip=$host{ip}[1][1];
	  $host{ip}[1][1]=param('new_ip');
	  $host{ip}[1][4]=1;
	  $host{huser}=param('new_user') unless (param('new_user') =~ /^\s*$/);
	  $host{dept}=param('new_dept') unless (param('new_dept') =~ /^\s*$/);
	  $host{location}=param('new_loc')
	    unless (param('new_loc') =~ /^\s*$/);
	  $host{info}=param('new_info') unless (param('new_info') =~ /^\s*$/);
	  unless (update_host(\%host)) {
	    update_history($state{uid},$state{sid},1,
			   "MOVE: $host_types{$host{type}} ",
		   "domain: $host{domain}, IP: $old_ip --> $host{ip}[1][1]",
			  $host{id});
	    print h2('Host moved.');
	    goto show_host_record;
	  } else {
	    alert1('Host update failed!');
	  }
	}
      }
      print h2("Move host to another IP");
      $tmpnet=new Net::Netmask(param('move_net'));
      $newip=auto_address($serverid,$tmpnet->desc());
      unless(is_cidr($newip)) {
	logmsg("notice","auto_address($serverid,".param('move_net').
	       ") failed!");
	print h3($newip);
	$newip=$host{ip}[1][1];
      }
      print p,startform(-method=>'GET',-action=>$selfurl),
            hidden('menu','hosts'),hidden('h_id',$id),hidden('sub','Move'),
            hidden('move_confirm'),hidden('move_net'),p,"<TABLE>",
	    Tr(td("New IP:"),
	       td(textfield(-name=>'new_ip',-size=>15, -maxlength=>15,
			    -default=>$newip))),
	    Tr(td("New User:"),
	       td(textfield(-name=>'new_user',-size=>40,-maxlength=>40,
			 -default=>$host{huser}))),
	    Tr(td("New Department:"),
	       td(textfield(-name=>'new_dept',-size=>30,-maxlength=>30,
			 -default=>$host{dept}))),
	    Tr(td("New Location:"),
	       td(textfield(-name=>'new_loc',-size=>30,-maxlength=>30,
			    -default=>$host{location}))),
	    Tr(td("New Info:"),
	       td(textfield(-name=>'new_info',-size=>30,-maxlength=>30,
			    -default=>$host{info}))),
	    "</TR></TABLE><BR>",
	    submit(-name=>'move_confirm2',-value=>'Update'), " ",
	    submit(-name=>'move_cancel',-value=>'Cancel'),p,
	    end_form;
      display_form(\%host,\%host_form);
      return;
    }
    make_net_list($serverid,0,\%nethash,\@netkeys,1);
    $ip=$host{ip}[1][1];
    undef @q;
    db_query("SELECT net FROM nets WHERE server=$serverid AND subnet=true " .
	     "AND net >> '$ip';",\@q);
    print h2("Move host to another subnet: ");
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id),hidden('sub','Move'),
          p,"Move host to: ",
          popup_menu(-name=>'move_net',-values=>\@netkeys,-default=>'ANY',
		     -default=>$q[0][0],-labels=>\%nethash),
          submit(-name=>'move_confirm',-value=>'Move'), " ",
          submit(-name=>'move_cancel',-value=>'Cancel'), " ",
          end_form;
    display_form(\%host,\%host_form);
    return;
  }
  elsif ($sub eq 'Edit') {
    return unless ($id > 0);
    goto show_host_record if (check_perms('host',$host{domain}));
    $hform=(check_perms('zone','RWX',1) ? \%restricted_host_form :\%host_form);

    if (param('h_cancel')) {
      print h2("No changes made to host record.");
      goto show_host_record;
    }

    if (param('h_submit')) {
      for $i (1..$#{$host{ip}}) { $old_ips[$i]=$host{ip}[$i][1]; }
      %oldhost=%host;
      unless (($res=form_check_form('h',\%host,$hform))) {
	if (check_perms('host',$host{domain},1)) {
	  alert2("Invalid hostname: does not conform to your restrictions");
	} else {
	  $update_ok=1;

	  if ($host{type}==1 || $host{type}==101) {
	    for $i (1..($#{$host{ip}})) {
	      #print "<p>check $i, $old_ips[$i], $host{ip}[$i][1]";
	      if (check_perms('ip',$host{ip}[$i][1],1)) {
		alert2("Invalid IP number: outside allowed range(s) " .
		       $host{ip}[$i][1]);
		$update_ok=0;
	      }
	      if (($old_ips[$i] ne $host{ip}[$i][1]) &&
		  ip_in_use($serverid,$host{ip}[$i][1])) {
		alert2("IP number already in use: $host{ip}[$i][1]");
		$update_ok=0;
		$update_ok=1 
		  if (param('h_ip_allowdup') && 
		      check_perms('zone','RWX',1)==0);
	      }
	    }

	    if ($host{ether_alias_info}) {
	      undef @q;
	      db_query("SELECT id FROM hosts WHERE zone=$zoneid " .
		       " AND domain='$host{ether_alias_info}';",\@q);
	      unless ($q[0][0] > 0) {
		alert2("Cannot find host specified in 'Ethernet alias' field");
		$update_ok=0;
	      } else {
		$host{ether_alias}=$q[0][0];
	      }
	    } else {
	      $host{ether_alias}=-1;
	    }
	  }

	  if ($update_ok) {
	    $host{ether_alias}=-1 if ($host{ether});
	    if ($perms{elimit} > 0) { # enforce expiration limit, if it exists
	      $tmp=time()+$perms{elimit}*86400;
	      $host{expiration}=$tmp
		unless ($host{expiration} > 0 && $host{expiration} < $tmp)
	      }
	    $res=update_host(\%host);
	    if ($res < 0) {
	      alert1("Host record update failed! ($res)");
	      alert2(db_lasterrormsg());
	    } else {
	      update_history($state{uid},$state{sid},1,
			    "EDIT: $host_types{$host{type}} ",
			     ($host{domain} eq $oldhost{domain} ?
			      "domain: $host{domain} " :
			      "domain: $oldhost{domain} --> $host{domain} ") .
			     ($host{ether} ne $oldhost{ether} ?
			      "ether: $oldhost{ether} --> $host{ether} ":"") .
			     ($host{ip}[1][1] ne $old_ips[1] ?
			      "ip: $old_ips[1] --> $host{ip}[1][1] ":""),
			     $host{id});
	      print h2("Host record succesfully updated.");
	      goto show_host_record;
	    }
	  }
	}
      } else {
	alert1("Invalid data in form! ($res)");
      }
    }

    print h2("Edit host:"),p,startform(-method=>'POST',-action=>$selfurl),
	  hidden('menu',$menu),hidden('sub','Edit');
    form_magic('h',\%host,$hform);
    print submit(-name=>'h_submit',-value=>'Make changes')," ",
          submit(-name=>'h_cancel',-value=>'Cancel'),end_form;
    return;
  }
  elsif ($sub eq 'Network Settings') {
    goto show_host_record unless ($id > 0 && $host{type} == 1);
    get_host_network_settings($serverid,$host{ip}[1][1],\%data);
    print "Current network settings for: $host{domain}<p>";
    display_form(\%data,\%host_net_info_form);
    print "<br><hr noshade><br>";
    goto show_host_record;
  }
  elsif ($sub eq 'Ping') {
    return if check_perms('level',$ALEVEL_PING);
    goto show_host_record unless ($id > 0 && $host{type} == 1);
    if ($SAURON_PING_PROG && -x $SAURON_PING_PROG) {
      ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      if (is_cidr($ip)) {
	update_history($state{uid},$state{sid},1,
		       "PING","domain: $host{domain}, ip: $ip",$host{id});
	print "Pinging $host{domain} ($ip)...<br><pre>";
	$SAURON_PING_ARGS = '-c5' unless ($SAURON_PING_ARGS);
	$SAURON_PING_TIMEOUT = 15 unless ($SAURON_PING_TIMEOUT > 0);
	$|=1;
	$r = run_command($SAURON_PING_PROG,[$SAURON_PING_ARGS,$ip],
			 $SAURON_PING_TIMEOUT);
	print "</pre><br>";
	print "<FONT color=\"red\">PING TIMED OUT!</FONT><BR>"
	  if (($r & 255) == 14);
      } else {
	alert2("Missing/invalid IP address");
      }
    } else {
      alert2("Ping not configured!");
    }
  }
  elsif ($sub eq 'Traceroute') {
    return if check_perms('level',$ALEVEL_TRACEROUTE);
    goto show_host_record unless ($id > 0 && $host{type} == 1);
    if ($SAURON_TRACEROUTE_PROG && -x $SAURON_TRACEROUTE_PROG) {
      ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      if (is_cidr($ip)) {
	update_history($state{uid},$state{sid},1,
		      "TRACEROUTE","domain: $host{domain}, ip: $ip",$host{id});
	print "Tracing route to $host{domain} ($ip)...<br><pre>";
	undef @arguments;
	push @arguments, $SAURON_TRACEROUTE_ARGS if ($SAURON_TRACEROUTE_ARGS);
	push @arguments, $ip;
	$SAURON_TRACEROUTE_TIMEOUT = 15 
	  unless ($SAURON_TRACEROUTE_TIMEOUT > 0);
	$|=1;
	$r = run_command($SAURON_TRACEROUTE_PROG,\@arguments,
			 $SAURON_TRACEROUTE_TIMEOUT);
	print "</pre><br>";
	print "<FONT color=\"red\">TRACEROUTE TIMED OUT!</FONT><BR>"
	  if (($r & 255) == 14);
      } else {
	alert2("Missing/invalid IP address");
      }
    } else {
      alert2("Traceroute not configured!");
    }
  }
  elsif ($sub eq 'History') {
    return if (check_perms('level',$ALEVEL_HISTORY));
    goto show_host_record unless ($id > 0);
    print "History for host record: $id ($host{domain}):<br>";
    get_history_host($id,\@q);
    unshift @q, [$host{cdate},'CREATE','record created',$host{cuser}];
    display_list(['Date','Action','Info','By'],\@q,0);
  }
  elsif ($sub eq '-> This Subnet') {
    if (is_cidr(($ip=$host{ip}[1][1]))) {
      db_query("SELECT net FROM nets " .
	       "WHERE server=$serverid AND '$ip' << net " .
	       "ORDER BY subnet,net",\@q);
      if (@q > 0) {
	param('bh_type','1'); param('bh_order','2');
	param('bh_size','3'); param('bh_stype','0');
	param('bh_net',$q[$#q][0]);
	param('bh_submit','Search');
	goto browse_hosts_jump_point;
      }
    }
  }
  elsif ($sub eq 'browse') {
  browse_hosts_jump_point:
    %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>0,size=>3);
    if (param('bh_submit')) {
      if (param('bh_submit') eq 'Clear') {
	param('bh_pattern','');
	param('bh_stype','0');

	param('bh_type','1');
	param('bh_net','');
	param('bh_cidr','');
	param('bh_domain','');

	param('bh_order','2');
	param('bh_size','3');
	goto browse_hosts;
      }
      if (form_check_form('bh',\%bdata,\%browse_hosts_form)) {
	alert2("Invalid parameters.");
	goto browse_hosts;
      }
      $state{searchopts}=param('bh_type').",".param('bh_order').",".
                   param('bh_size').",".param('bh_stype').",".
		   param('bh_net').",".param('bh_cidr');
      $state{searchdomain}=param('bh_domain');
      $state{searchpattern}=param('bh_pattern');
      save_state($scookie);
    }
    elsif (param('lastsearch')) {
      if ($state{searchopts} =~ /^(\d+),(\d+),(\d+),(-?\d+),(\S*),(\S*)$/) {
	param('bh_type',$1);
	param('bh_order',$2) unless (param('bh_order'));
	param('bh_size',$3);
	param('bh_stype',$4);
	param('bh_net',$5) if ($5);
	param('bh_cidr',$6) if ($6);
      } else {
	print h2('No previous search found');
	goto browse_hosts;
      }
      param('bh_domain',$state{searchdomain});
      param('bh_pattern',$state{searchpattern});
    }

    undef $typerule;
    $limit=$browse_page_size{param('bh_size')};
    $limit='100' unless ($limit > 0);
    $page=param('bh_page');
    $offset=$page*$limit;

    $type=param('bh_type');
    if ($type > 0) {
      $typerule=" AND a.type=$type ";
      $typerule=" AND (a.type=$type OR a.type=101) " if ($type==1);
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
      $domainrule=" AND a.domain ~* " . db_encode_str($tmp) . " "; 
    }
    if (param('bh_order') == 1) { $sorder='5,1';  }
    elsif (param('bh_order') == 3) { $sorder='6,1'; }
    elsif (param('bh_order') == 4) { $sorder='7,8,1'; }
    else { $sorder='1,5'; }

    #if (param('bh_cidr') || param('bh_net') ne 'ANY') {
    #  $type=1;
    #}

    undef %extrarule;
    if (param('bh_pattern')) {
      if (param('bh_stype') >= 0) { $tmp=$browse_search_f[param('bh_stype')]; }
      else { $tmp=''; }
      $tmp2=param('bh_pattern');
      if ($tmp eq 'ether') {
	$tmp2 = "\U$tmp2";
	$tmp2 =~ s/[^0-9A-F]//g;
	print "Searching for Ethernet address pattern '$tmp2'<br><br>"
	  if (param('bh_pattern') =~ /[^A-Fa-f0-9:\-\ ]/);
	#print "<br>ether=$tmp2";
      }
      $tmp2=db_encode_str($tmp2);
      if ($tmp) {
	$extrarule=" AND a.$tmp ~* $tmp2 ";
	#print p,$extrarule;
      } else {
	$extrarule= " AND (a.location ~* $tmp2 OR a.huser ~* $tmp2 " .
	  "OR a.dept ~* $tmp2 OR a.info ~* $tmp2 OR a.serial ~* $tmp2 " .
	  "OR a.model ~* $tmp2 OR a.misc ~* $tmp2) ";
	#print p,"foobar";
      }
    }

    undef @q;
    $fields="a.id,a.type,a.domain,a.ether,a.info,a.huser,a.dept," .
	    "a.location,a.expiration,a.ether_alias";
    $fields.=",a.cdate,a.mdate,a.expiration,a.dhcp_date," .
             "a.hinfo_hw,a.hinfo_sw,a.model,a.serial,a.misc,a.asset_id"
	       if (param('csv'));

    $sql1="SELECT b.ip,'',$fields FROM hosts a,a_entries b " .
	  "WHERE a.zone=$zoneid AND b.host=a.id $typerule $typerule2 " .
	  " $netrule $domainrule $extrarule ";
    $sql2="SELECT '0.0.0.0'::cidr,'',$fields FROM hosts a " .
          "WHERE a.zone=$zoneid AND (a.type!=1 AND a.type!=6 AND a.type!=4) " .
	  " $typerule $domainrule ";
    $sql3="SELECT '0.0.0.0'::cidr,b.domain,$fields FROM hosts a,hosts b " .
          "WHERE a.zone=$zoneid AND a.alias=b.id AND a.type=4 " .
	  " $domainrule  ";
    $sql4="SELECT '0.0.0.0'::cidr,a.cname_txt,$fields FROM hosts a  " .
          "WHERE a.zone=$zoneid AND a.alias=-1 AND a.type=4 " .
	  " $domainrule ";

    if ($type == 1 || $type == 6) {
      $sql="$sql1 ORDER BY $sorder,1";
    } elsif ($type == 4) {
      $sql="$sql3 UNION $sql4 ORDER BY $sorder,2";
    } elsif ($type == 0) {
      $sql="$sql1 UNION $sql2 UNION $sql3 UNION $sql4 ORDER BY $sorder,3";
    }
    else { $sql="$sql2 ORDER BY $sorder"; }
    $sql.=" LIMIT $limit OFFSET $offset;";
    #print "<br>$sql";
    db_query($sql,\@q);
    $count=scalar @q;
    if ($count < 1) {
      alert2("No matching records found.");
      goto browse_hosts;
    }

    if (param('csv')) {
      printf print_csv(['Domain','Type','IP','Ether','User','Dept.',
	                 'Location','Info','Hardware','Software',
			 'Model','Serial','Misc','AssetID',
			 'cdate','mdate','edate','dhcpdate'],1) . "\n";
      for $i (0..$#q) {
	$q[$i][5]=dhcpether($q[$i][5])
	  unless (dhcpether($q[$i][5]) eq '00:00:00:00:00:00');
	printf print_csv([ $q[$i][4],$host_types{$q[$i][3]},$q[$i][0],
	                   $q[$i][5],$q[$i][7],$q[$i][8],$q[$i][9],
			   $q[$i][6],$q[$i][16],$q[$i][17],
			   $q[$i][18],$q[$i][19],$q[$i][20],$q[$i][21],
			   $q[$i][12],$q[$i][13],$q[$i][14],$q[$i][15]
			 ],1) . "\n";
      }
      return;
    }

    if ($count == 1) {
      param('h_id',$q[0][2]);
      goto show_host_record;
    }

    print "<TABLE width=\"99%\" cellspacing=1 cellpadding=1 border=0 " .
          "BGCOLOR=\"ffffff\">",
          "<TR><TD><B>Zone:</B> $zone</TD>",
          "<TD align=right>Page: ".($page+1)."</TD></TR></TABLE>";

    if (param('pingsweep')) {
      if (check_perms('level',$ALEVEL_NMAP,1)) {
	logmsg("warning","unauthorized ping sweep attempt: $state{user}");
	alert1("Access denied.");
	return;
      }

      undef @pingiplist;
      for $i (0..$#q) {
	next unless ($q[$i][3] == 1);
	($ip=$q[$i][0]) =~ s/\/\d{1,2}$//g;
	push @pingiplist, $ip;
      }

      print h3("Please wait...Running Ping sweep.");
      update_history($state{uid},$state{sid},2,"Hosts PING Sweep",
		     "zone: $zone ($pingiplist[0]..$pingiplist[-1])",$zoneid);
      $r = run_ping_sweep(\@pingiplist,\%nmaphash,$state{user});
      if ($r < 0) {
	alert2("Ping Sweep not configured!");
      } elsif ($r == 1) {
	alert2("Ping Sweep timed out!");
      } else {
	$pingsweep=1;
      }
    }

    $sorturl="$selfurl?menu=hosts&sub=browse&lastsearch=1";
    print 
      "<TABLE width=\"99%\" border=0 cellspacing=1 cellpadding=1 ".
      " BGCOLOR=\"#ccccff\"><TR bgcolor=#aaaaff>",
      th([($pingsweep ? 'Status':'#'),
	  "<a href=\"$sorturl&bh_order=1\">Hostname</a>",
	  'Type',
	  "<a href=\"$sorturl&bh_order=2\">IP</a>",
	  "<a href=\"$sorturl&bh_order=3\">Ether</a>",
	  "<a href=\"$sorturl&bh_order=4\">Info</a>"]);

    for $i (0..$#q) {
      $type=$q[$i][3];
      ($ip=$q[$i][0]) =~ s/\/\d{1,2}$//g;
      $ip="(".add_origin($q[$i][1],$zone).")" if ($type==4);
      $ip='N/A' if ($ip eq '0.0.0.0');
      $ether=$q[$i][5];
      # $ether =~  s/^(..)(..)(..)(..)(..)(..)$/\1:\2:\3:\4:\5:\6/;
      $ether='<font color="#009900">ALIASED</font>' if ($q[$i][11] > 0);
      $ether='<font color="#990000">N/A</a>' unless($ether);
      #$hostname=add_origin($q[$i][4],$zone);
      $hostname="<A HREF=\"$selfurl?menu=hosts&h_id=$q[$i][2]\">".
	        "$q[$i][4]</A>";
      $info = join_strings(', ',(@{$q[$i]})[6,7,8,9]);

      $trcolor='#eeeeee';
      $trcolor='#ffffcc' if ($i % 2 == 0);
      $trcolor='#ffcccc' if ($q[$i][10] > 0 && $q[$i][10] < time());
      $trcolor='#ccffff' if (param('bh_type')==1 && $type == 101);

      if ($pingsweep) {
	if ($type == 1) {
	  if ($nmaphash{$ip} =~ /^Up/) {
	    $nro = "<FONT color=\"green\" size=-1>Up</FONT>";
	  } else {
	    $nro = "<FONT color=\"red\" size=-1>Down $nmaphash{$ip}</FONT>";
	  }
	} else {
	  $nro = "&nbsp;";
	}
      } else {
	$nro = "<FONT size=-1>".($i+1)."</FONT>";
      }
      print "<TR bgcolor=\"$trcolor\">",
	    td([$nro, $hostname,
		"<FONT size=-1>$host_types{$q[$i][3]}</FONT>",$ip,
	        "<font size=-3 face=\"courier\">$ether&nbsp;</font>",
	        "<FONT size=-1>".$info."&nbsp;</FONT>"]),"</TR>";

    }
    print "</TABLE><BR><CENTER>[";

    $params="bh_type=".param('bh_type')."&bh_order=".param('bh_order').
            "&bh_net=".param('bh_net')."&bh_cidr=".param('bh_cidr').
	    "&bh_stype=".param('bh_stype')."&bh_pattern=".param('bh_pattern').
	    "&bh_domain=".param('bh_domain')."&bh_size=".param('bh_size');

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

    print "]</CENTER><BR>",
          "<div align=right><font size=-2>",
          "<a title=\"foo.csv\" href=\"$sorturl&csv=1\">",
          "[Download results in CSV format]</a> &nbsp;</font></div>";

    if ($SAURON_NMAP_PROG && param('bh_type') == 1 &&
	!check_perms('level',$ALEVEL_NMAP,1)) {

      print startform(-method=>'POST',-action=>$selfurl),
	    hidden('menu','hosts'),hidden('sub','browse'),
	    hidden('bh_page',$page),
	    hidden('lastsearch','1'),hidden('pingsweep','1');
      print submit(-name=>'foobar',-value=>'Ping Sweep');
      print end_form;
    }

    return;
  }
  elsif ($sub eq 'add') {
    $type=param('type');
    $data{type}=$type;
    $data{zone}=$zoneid;
    $data{router}=0;
    $data{grp}=-1; $data{mx}=-1; $data{wks}=-1;
    $data{mx_l}=[]; $data{ns_l}=[]; $data{printer_l}=[]; $data{srv_l}=[];
    $data{dept}=$perms{defdept} if ($perms{defdept});
    $data{expiration}=time()+$perms{elimit}*86400 if ($perms{elimit} > 0);

  copy_add_label:
    return if (check_perms('zone','RW'));
    return if (($type!=1 && $type!=101) && check_perms('zone','RWX'));
    return if ($type==101 && check_perms('level',$ALEVEL_RESERVATIONS));
    $newhostform = (check_perms('zone','RWX',1) ? \%restricted_new_host_form :
		    \%new_host_form);
    $newhostform = \%new_host_form if ($type == 101);
    unless ($host_types{$type}) {
      alert2('Invalid add type!');
      return;
    }
    if ($type == 1 || $type == 101) {
      make_net_list($serverid,0,\%new_host_nets,\@new_host_netsl,1);
      $new_host_nets{MANUAL}='<Manual IP>';
      $data{net}='MANUAL';
      if (check_perms('superuser','',1)) {
	push @new_host_netsl, 'MANUAL';
	$data{net}=$new_host_netsl[0] if ($new_host_netsl[0]);
      } else {
	unshift @new_host_netsl, 'MANUAL';
      }
    }

    if (param('addhost_cancel')) {
      print h2("$host_types{$type} record creation canceled.");
      if (param('copy_id')) {
	param('h_id',param('copy_id'));
	goto show_host_record;
      }
      return;
    }
    elsif (param('addhost_submit')) {
      unless (($res=form_check_form('addhost',\%data,$newhostform))) {
	if ($data{net} eq 'MANUAL' && not is_cidr($data{ip})) {
	  alert1("IP number must be specified if using Manual IP!");
	} elsif ($u_id=domain_in_use($zoneid,$data{domain})) {
	  alert1("Domain name already in use!");
	  print "Conflicting host: ",
	     "<a href=\"$selfurl?menu=hosts&h_id=$u_id\">$data{domain}</a>.";
	} elsif (is_cidr($data{ip}) && ip_in_use($serverid,$data{ip})) {
	  alert1("IP number already in use!");
	} elsif (check_perms('host',$data{domain},1)) {
	  alert1("Invalid hostname: does not conform your restrictions");
	} elsif (is_cidr($data{ip}) && check_perms('ip',$data{ip},1)) {
	  alert1("Invalid IP number: outside allowed range(s)");
	} else {
	  print h2("Add");
	  if ($data{type} == 1 || $data{type} == 101) {
	    if ($data{ip} && $data{net} eq 'MANUAL') {
	      $ip=$data{ip};
	      delete $data{ip};
	      $data{ip}=[[0,$ip,'t','t','']];
	    } else {
	      $tmpnet=new Net::Netmask($data{net});
	      $ip=auto_address($serverid,$tmpnet->desc());
	      unless (is_cidr($ip)) {
		logmsg("notice","auto_address($serverid,$data{net}) failed!");
		alert1("Cannot get IP: $ip");
		return;
	      }
	      $data{ip}=[[0,$ip,'t','t','']];
	    }
	  } elsif ($data{type} == 6) {
	    $ip=$data{glue}; delete $data{glue};
	    $data{ip}=[[0,$ip,'t','t','']];
	  } elsif ($data{type} == 9) {
	    $ip=$data{ip}; delete $data{ip};
	    $data{ip}=[[0,$ip,'f','f','']];
	  }
	  delete $data{net};
	  #show_hash(\%data);
	  if ($perms{elimit} > 0) { # enforce expiration limit, if it exists
	    $tmp=time()+$perms{elimit}*86400;
	    $data{expiration}=$tmp
	      unless ($data{expiration} > 0 && $data{expiration} < $tmp)
	  }
	  $res=add_host(\%data);
	  if ($res > 0) {
	    update_history($state{uid},$state{sid},1,
			   "ADD: $host_types{$data{type}} ",
			   "domain: $data{domain}",$res);
	    print h2("Host added successfully");
	    param('h_id',$res);
	    goto show_host_record;
	  } else {
	    alert1("Cannot add host record!");
	    if (db_lasterrormsg() =~ /ether_key/) {
	      alert2("Duplicate Ethernet (MAC) address $data{ether}");
	      db_query("SELECT id,domain FROM hosts " .
		       "WHERE ether='$data{ether}' AND zone=$zoneid",\@q);
	      if ($q[0][0] > 0) {
		print "Conflicting host: ",
  	          "<a href=\"$selfurl?menu=hosts&h_id=$q[0][0]\">$q[0][1]</a>";
	      }
	    } else {
	      alert2(db_lasterrormsg());
	    }
	  }
	}
      } else {
	alert1("Invalid data in form!");
      }
    }
    print h2("Add $host_types{$type} record");

    print startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','add'),hidden('type',$type);
    print hidden('copy_id') if (param('copy_id'));
    form_magic('addhost',\%data,$newhostform);
    print submit(-name=>'addhost_submit',-value=>'Create'), " ",
          submit(-name=>'addhost_cancel',-value=>'Cancel'),end_form;
    return;
  }
  elsif ($sub eq 'Copy') {
    return unless ($id > 0);
    %data=%host;
    delete $data{ip};
    delete $data{ether};
    delete $data{serial};
    delete $data{asset_id};
    $data{ip}=$host{ip}[1][1];
    $type=$host{type};
    param('copy_id',$id);
    param('sub','add');
    if ($host{domain} =~ /^([^\.]+)(\..*)?$/) {
      $p1=$1; $p2=$2;
      if ($p1 =~ /(\d+)/) {
	$p3len=length(($p3=$1));
	$p4 = sprintf("%0${p3len}d",$p3+1);
	$p1 =~ s/${p3}/${p4}/;
	$data{domain}=$p1.$p2;
      } else {
	$data{domain}=$p1.'2'.$p2;
      }
    }
    $data{ip}=$newip if (($newip=next_free_ip($serverid,$data{ip})));
    goto copy_add_label;
  }


  if (param('h_id')) {
  show_host_record:
    $id=param('h_id');
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }

    $host_form{bgcolor}='#ffcccc'
	if ($host{expiration} > 0 && $host{expiration} < time());
#    $host_form{bgcolor}='#ccffff' if ($host{type}==101);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id);
    print "<table width=\"99%\"><tr><td align=\"left\">",
          submit(-name=>'sub',-value=>'Refresh')," &nbsp; ";
    print submit(-name=>'sub',-value=>'-> This Subnet') if ($host{type} == 1);
    print "</td><td align=\"right\">";
    print submit(-name=>'sub',-value=>'History'), " "
      if (!check_perms('level',$ALEVEL_HISTORY,1));
    print submit(-name=>'sub',-value=>'Network Settings'), " "
      if ($host{type} == 1);
    print submit(-name=>'sub',-value=>'Ping'), " "
      if ($host{type} == 1 && $SAURON_PING_PROG &&
	  !check_perms('level',$ALEVEL_PING,1));
    print submit(-name=>'sub',-value=>'Traceroute')
      if ($host{type} == 1 && $SAURON_TRACEROUTE_PROG &&
	  !check_perms('level',$ALEVEL_TRACEROUTE,1));
    print "</td></tr></table>";

    display_form(\%host,\%host_form);
    unless (check_perms('zone','RW',1)) {
      print submit(-name=>'sub',-value=>'Edit'), " ",
            submit(-name=>'sub',-value=>'Delete'), " ",
#	    submit(-name=>'sub',-value=>'Rename'), " ",
	    submit(-name=>'sub',-value=>'Copy'),
	    " ";
      print submit(-name=>'sub',-value=>'Move'), " " if ($host{type} == 1);
      print submit(-name=>'sub',-value=>'Alias'), " " if ($host{type} == 1);
    }
    print end_form,"<br><br>";
    return;
  }


 browse_hosts:
  param('sub','browse');
  make_net_list($serverid,1,\%nethash,\@netkeys,0);

  %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>0,size=>3);
  if ($state{searchopts} =~ /^(\d+),(\d+),(\d+),(-?\d+),(\S*),(\S*)$/) {
    $bdata{type}=$1;
    $bdata{order}=$2;
    $bdata{size}=$3;
    $bdata{stype}=$4;
    $bdata{net}=$5 if ($5);
    $bdata{cidr}=$6 if ($6);
  }
  $bdata{domain}=$state{searchdomain} if ($state{searchdomain});
  $bdata{pattern}=$state{searchpattern} if ($state{searchpattern});

  print start_form(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','browse'),
          hidden('bh_page','0');
  form_magic('bh',\%bdata,\%browse_hosts_form);
  print submit(-name=>'bh_submit',-value=>'Search')," &nbsp;&nbsp; ",
        submit(-name=>'bh_submit',-value=>'Clear'),
        end_form;

}

sub make_net_list($$$$$) {
  my($id,$flag,$h,$l,$pcheck) = @_;
  my($i,$nets,$pc);

  $pcheck=0 if (keys %{$perms{net}} < 1);

  $nets=get_net_list($id,1);
  undef %{$h}; undef @{$l};

  if ($flag > 0) {
    $h->{'ANY'}='<Any net>';
    $$l[0]='ANY';
  }
  for $i (0..$#{$nets}) { 
    next unless ($$nets[$i][2]);
    next if ($pcheck && !($perms{net}->{$$nets[$i][1]})); 
    $h->{$$nets[$i][0]}="$$nets[$i][0] - " . substr($$nets[$i][2],0,25);
    push @{$l}, $$nets[$i][0];
  }
}


# GROUPS menu
#
sub groups_menu() {
  my(@q,$i,$id);

  $sub=param('sub');
  $id=param('grp_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

  if ($sub eq 'add') {
    $data{type}=1; $data{alevel}=0; $data{dhcp}=[]; $data{printer}=[];
    $data{server}=$serverid;
    $res=add_magic('add','Group','groups',\%group_form,
		   \&restricted_add_group,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $id=$res;
      goto show_group_record;
    }
    return;
  }
  elsif ($sub eq 'Edit') {
    $res=edit_magic('grp','Group','groups',\%group_form,
		    \&restricted_get_group,
		    \&restricted_update_group,$id);
    goto browse_groups if ($res == -1);
    goto show_group_record if ($res > 0);
    return;
  }
  elsif ($sub eq 'Delete') {
    if (get_group($id,\%group)) {
      print h2("Cannot get group (id=$id)");
      return;
    }
    return if (check_perms('grpmask',$group{name}));
    if (param('grp_cancel')) {
      print h2('Group not removed');
      goto show_group_record;
    } 
    elsif (param('grp_confirm')) {
      $new_id=param('grp_new');
      if ($new_id eq $id) {
	print h2("Cannot change host records to point the group " .
		 "being deleted!");
	goto show_group_record;
      }
      $new_id=-1 unless ($new_id > 0);
      if (db_exec("UPDATE hosts SET grp=$new_id WHERE grp=$id;") < 0) {
	print h2('Cannot update records pointing to this group!');
	return;
      }
      if (delete_group($id) < 0) {
	print "<FONT color=\"red\">",h1("Group delete failed!"),
	        "</FONT>";
	return;
      }
      print h2("Group successfully deleted.");
      return;
    }

    undef @q;
    db_query("SELECT COUNT(id) FROM hosts WHERE grp=$id;",\@q);
    print p,"$q[0][0] host records use this group.",
	      startform(-method=>'GET',-action=>$selfurl);
    if ($q[0][0] > 0) {
      get_group_list($serverid,\%lsth,\@lst,$perms{alevel});
      print p,"Change those host records to point to: ",
	        popup_menu(-name=>'grp_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
    }
    print hidden('menu','groups'),hidden('sub','Delete'),
	      hidden('grp_id',$id),p,
	      submit(-name=>'grp_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'grp_cancel',-value=>'Cancel'),end_form;
    display_form(\%group,\%group_form);
    return;
  }

 show_group_record:
  if ($id > 0) {
    if (get_group($id,\%group)) {
      print h2("Cannot get group record (id=$id)!");
      return;
    }
    display_form(\%group,\%group_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','groups');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('grpmask',$group{name},1));
    print hidden('grp_id',$id),end_form;
    return;
  }

 browse_groups:
  db_query("SELECT id,name,comment,type,alevel FROM groups " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  if (@q < 1) {
    print h2("No groups found!");
    return;
  }

  for $i (0..$#q) {
    $name = "<a href=\"$selfurl?menu=groups&grp_id=$q[$i][0]\">$q[$i][1]</a>";
    push @list, [$name,$group_type_hash{$q[$i][3]},$q[$i][2],$q[$i][4]];
  }
  print h3("Groups for server: $server");
  display_list(['Name','Type','Comment','Lvl'],\@list,0);
  print "<br>";
}


# NETS menu
#
sub nets_menu() {
  my(@q,$i,$id);

  $sub=param('sub');
  $id=param('net_id');
  $v_id=param('vlan_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

 show_vlan_record:
  if ($v_id > 0) {
      return if (check_perms('level',$ALEVEL_VLANS));

      if (get_vlan($v_id,\%vlan)) {
	  alert2("Cannot get vlan record (id=$v_id)");
	  return;
      }

      if ($sub eq 'Edit') {
	  return if (check_perms('superuser',''));
	  $res=edit_magic('vlan','VLAN','vlans',\%vlan_form,
			  \&get_vlan,\&update_vlan,$v_id);
	  #goto browse_vlans if ($res == -1);
	  return unless ($res == 2);
	  get_vlan($v_id,\%vlan);
      }
      elsif ($sub eq 'Delete') {
	  return if (check_perms('superuser',''));
	  $res=delete_magic('vlan','VLAN','vlans',\%vlan_form,\&get_vlan,
			    \&delete_vlan,$v_id);
	  return unless ($res == 2);
	  get_vlan($v_id,\%vlan);
      }

      display_form(\%vlan,\%vlan_form);
      print p,startform(-method=>'GET',-action=>$selfurl),
            hidden('menu','nets'),hidden('vlan_id',$v_id);
      print submit(-name=>'sub',-value=>'Edit'), "  ",
            submit(-name=>'sub',-value=>'Delete'), " &nbsp;&nbsp;&nbsp; "
	    unless (check_perms('superuser','',1));
      print end_form;
      return;
  }

  if ($sub eq 'vlans') {
    browse_vlans:
      return if (check_perms('level',$ALEVEL_VLANS));
      undef @q;
      db_query("SELECT id,name,description,comment FROM vlans " .
	       "WHERE server=$serverid ORDER BY name;",\@q);
      print h3("VLANs");
      for $i (0..$#q) {
	$q[$i][1]="<a href=\"$selfurl?menu=nets&vlan_id=$q[$i][0]\">".
	          "$q[$i][1]</a>";
      }
      display_list(['Name','Description','Comments'],\@q,1);
      print "<br>";
      return;
  }
  elsif ($sub eq 'addvlan') {
    return if (check_perms('superuser',''));
    $data{server}=$serverid;
    $res=add_magic('addvlan','VLAN','nets',\%new_vlan_form,
		   \&add_vlan,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $v_id=$res;
      goto show_vlan_record;
    }
    print db_lasterrormsg();
    return;
  }
  elsif ($sub eq 'addnet') {
    return if (check_perms('superuser',''));
    $data{subnet}='f';
    $data{server}=$serverid;
    $res=add_magic('addnet','Network','nets',\%new_net_form,
		   \&add_net,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $id=$res;
      goto show_net_record;
    }
    return;
  }
  elsif ($sub eq 'addsub') {
    return if (check_perms('superuser',''));
    $data{subnet}='t';
    $data{server}=$serverid;
    $res=add_magic('addnet','Subnet','nets',\%new_net_form,
		   \&add_net,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $id=$res;
      goto show_net_record;
    }
    return;
  }
  elsif ($sub eq 'Edit') {
    return if (check_perms('superuser',''));
    get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list_lst);
    $res=edit_magic('net','Net','nets',\%net_form,\&get_net,\&update_net,$id);
    goto browse_nets if ($res == -1);
    goto show_net_record if ($res > 0);
    return;
  }
  elsif ($sub eq 'Delete') {
    return if (check_perms('superuser',''));
    $res=delete_magic('net','Net','nets',\%net_form,\&get_net,
		      \&delete_net,$id);
    goto show_net_record if ($res == 2);
    return;
  }
  elsif ($sub eq 'Net Info') {
    if (($id < 0) || get_net($id,\%net)) {
      alert2("Cannot get net record (id=$id)");
      return;
    }

    db_query("SELECT a.ip,h.router,h.domain " .
             "FROM a_entries a, hosts h, zones z " .
	     "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	     " AND a.ip << '$net{net}' ORDER BY a.ip;",\@q);
    $net{inuse}=@q;
    for $i (0..$#q) {
      $ip=$q[$i][0]; $ip=~s/\/32$//;
      $netmap{$ip}=1;
      $net{gateways}.="$q[$i][0] " . ($q[$i][2] ? "($q[$i][2])":'') .
	              "<br>" if ($q[$i][1] > 0);
    }

    $net = new Net::Netmask($net{net});
    $net{base}=$net->base();
    $net{netmask}=$net->mask();
    $net{hostmask}=$net->hostmask();
    $net{broadcast}=$net->broadcast();
    $net{size}=$net->size();
    $net{first}=$net->nth(1);
    $net{last}=$net->nth(-2);
    $net{ssize}=$net->size()-2;
    $net{inusep}=sprintf("%3.0f", ($net{inuse} / $net{size})*100) ."%";

    $state=($netmap{$net{first}} > 0 ? 1 : 0);
    $si=1;
    for $i (1..($net->size()-1)) {
      $ip=$net->nth($i);
      $nstate=($netmap{$ip} > 0 ? 1 : 0);
      if ($nstate != $state) {
	push @blocks, [$state,($i-$si),$net->nth($si),$net->nth($i-1)];
	$si=$i;
      }
      $state=$nstate;
    }
    $i=$net->size()-1;
    push( @blocks, [$state,($i-$si),$net->nth($si),$net->nth($i-1)] )
      if ($si < $i);

    print "<TABLE width=\"100%\"><TR><TD valign=\"top\">";

    display_form(\%net,\%net_info_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','nets'),
          submit(-name=>'sub',-value=>'<-- Back'),
          hidden('net_id',$id),end_form;

    print "</TD><TD valign=\"top\">";

    if ($net{subnet} eq 't') {
      print "<TABLE cellspacing=0 cellpadding=3 border=0 bgcolor=\"eeeeef\">",
          "<TR><TH colspan=3 bgcolor=\"#ffffff\">Net usage map</TH></TR>",
	  "<TR bgcolor=\"#aaaaff\">",td("Size"),td("Start"),td("End"),"</TR>";
      $state=0;
      $state=1 if ($q[0][0] =~ /^($net{first})(\/32)?/);
      for $i (0..$#blocks) {
	if ($blocks[$i][0] == 1) { print "<TR bgcolor=\"#00ff00\">"; }
	else { print "<TR bgcolor=\"#eeeebf\">"; }
	print td("$blocks[$i][1] &nbsp;"),td($blocks[$i][2]),
	  td($blocks[$i][3]),"</TR>";
      }
      print "<TR><TH colspan=3 bgcolor=\"#aaaaff\">&nbsp;</TH></TR></TABLE>";
      print p,"Legend: <TABLE><TR bgcolor=\"#00ff00\"><TD>in use</TD></TR>",
	    "<TR bgcolor=\"#eeeebf\"><TD>unused</TD></TR></TABLE>";
    }

    print "</TD></TR></TABLE>";
    return;
  }
  elsif ($sub eq 'Ping Sweep') {
    if (get_net($id,\%net)) {
      print h2("Cannot get net record (id=$id)!");
      return;
    }
    print h3("Ping Sweep for $net{net}...");
    update_history($state{uid},$state{sid},4,"Net PING Sweep",
		   "net: $net{net}",$net{id});
    undef @pingiplist;
    push @pingiplist, $net{net};
    $r = run_ping_sweep(\@pingiplist,\%nmaphash,$state{user});
    if ($r < 0) {
      alert2("Ping Sweep not configured!");
    } elsif ($r == 1) {
      alert2("Ping Sweep timed out!");
    } else {
      db_query("SELECT h.id,h.domain,a.ip,h.huser,h.dept,h.location,h.info " .
               "FROM zones z,hosts h,a_entries a " .
	       "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	       " AND a.ip << '$net{net}' ORDER BY a.ip",\@q);
      undef %netmap;
      for $i (0..$#q) { $netmap{$q[$i][2]}=$q[$i]; }
      @iplist = net_ip_list($net{net});
      for $i (0..$#iplist) {
	$ip=$iplist[$i];
	next unless ($nmaphash{$ip} || $netmap{$ip});
	$hid=$netmap{$ip}->[0];
	if ($nmaphash{$ip} =~ /^Up/) {
	  $status="<font color=\"green\">UP</font>";
	} else {
	  $status="<font color=\"red\">DOWN $nmaphash{$ip}</font>";
	}
	$domain=$netmap{$ip}->[1];
	$domain="UNKNOWN" unless ($domain);
	$domain="<a href=\"$selfurl?menu=hosts&h_id=$hid\">".$domain."</a>" 
	  if ($hid > 0);
	$info = "<font size=-1>" .
	        join_strings(', ',(@{$netmap{$ip}})[6,3,4,5]) . "</font>";
	push @pingsweep, [$status,$ip,$domain,$info];
      }

      print startform(-method=>'POST',-action=>$selfurl),
	    hidden('menu','nets'),hidden('net_id',$id),
            submit(-name=>'foobar',-value=>' <-- '),end_form;
      display_list(['Status','IP','Domain','Info'],
		   \@pingsweep,0);
      print p,br;
    }
    return;
  }

 show_net_record:
  if ($id > 0) {
    if (get_net($id,\%net)) {
      print h2("Cannot get net record (id=$id)!");
      return;
    }
    if (check_perms('level',$ALEVEL_VLANS,1)) {
	$net_form{mode}=0;
    } else {
	get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list);
    }
    display_form(\%net,\%net_form);
    print p,"<TABLE><TR><TD> ",startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','nets');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'), " &nbsp;&nbsp;&nbsp; "
	    unless (check_perms('superuser','',1));
    print submit(-name=>'sub',-value=>'Net Info')," ";
    print submit(-name=>'sub',-value=>'Ping Sweep')
            unless (check_perms('level',$ALEVEL_NMAP,1));
    print hidden('net_id',$id),end_form,"</TD><TD>";
    param('menu','hosts');
    param('sub','browse');
    print startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','browse'),
	  hidden('bh_type','1'),hidden('bh_order','2'),
	  hidden('bh_size','3'),hidden('bh_stype','0'),
	  hidden('bh_net',$net{net}),hidden('bh_submit','Search'),
          submit(-name=>'foobar',-value=>'Show Hosts'),end_form,
	  "</TD></TR></TABLE>";
    return;
  }

 browse_nets:
  db_query("SELECT id,name,net,subnet,comment,no_dhcp,vlan,netname,alevel " .
	   "FROM nets " .
	   "WHERE server=$serverid AND alevel <= $perms{alevel} " .
	   "ORDER BY subnet,net;",\@q);
  if (@q < 1) {
    print h2("No networks found!");
    return;
  }
  if (check_perms('level',$ALEVEL_VLANS,1)) {
    $novlans=1;
  } else {
    get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list);
    $novlans=0;
  }

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 " .
        " cellpadding=1 border=0>",
        "<TR bgcolor=\"#aaaaff\">",
        th("Net"),th("NetName"),th("Description"),th("Type"),
        th("DHCP"),($novlans?'':th("VLAN")),th("Lvl"),"</TR>";

  for $i (0..$#q) {
      $dhcp=(($q[$i][5] eq 't' || $q[$i][5] == 1) ? 'No' : 'Yes' );
      if ($q[$i][3] eq 't' || $q[$i][3] == 1) {
	print $dhcp eq 'Yes' ? "<TR bgcolor=\"#eeeebf\">" :
	       "<TR bgcolor=\"#eeeeee\">";
	$type='Subnet';
      } else {
	print "<TR bgcolor=\"#ddffdd\">";
	$type='Net';
      }

      $vlan=($q[$i][6] > 0 ? $vlan_list_hash{$q[$i][6]} : '&nbsp;');
      $netname=($q[$i][7] eq '' ? '&nbsp;' : $q[$i][7]);
      $name=($q[$i][1] eq '' ? '&nbsp;' : $q[$i][1]);
      $comment=$q[$i][4];
      $comment='&nbsp;' if ($comment eq '');
      print "<td><a href=\"$selfurl?menu=nets&net_id=$q[$i][0]\">",
	  "$q[$i][2]</a></td>",td($netname),
          td("<FONT size=-1>$name</FONT>"), td("<FONT size=-1>$type</FONT>"),
          td("<FONT size=-1>$dhcp</FONT>"),
	  ($novlans?'':td("<FONT size=-1>$vlan</FONT>")),
	  # td("<FONT size=-1>$comment</FONT>"),
	  td($q[$i][8].'&nbsp;'),"</TR>";
  }

  print "</TABLE>&nbsp;";
}


# TEMPLATES menu
#
sub templates_menu() {
  my(@q,$i,$id);

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  unless ($zoneid > 0) {
    print h2("Zone not selected!");
    return;
  }
  return if (check_perms('server','R'));

  $sub=param('sub');
  $mx_id=param('mx_id');
  $wks_id=param('wks_id');
  $pc_id=param('pc_id');
  $hinfo_id=param('hinfo_id');

  if ($sub eq 'mx') {
  show_mx_template_list:
    db_query("SELECT name,comment,alevel,id FROM mx_templates " .
	     "WHERE zone=$zoneid ORDER BY name;",\@q);
    print h3("MX templates for zone: $zone");
    for $i (0..$#q) {
	$q[$i][0]=
	  "<a href=\"$selfurl?menu=templates&mx_id=$q[$i][3]\">$q[$i][0]</a>";
    }
    display_list(['Name','Comment','Lvl'],\@q,0);
    print "<br>";
    return;
  }
  elsif ($sub eq 'wks') {
    db_query("SELECT name,comment,alevel,id FROM wks_templates " .
	     "WHERE server=$serverid ORDER BY name;",\@q);
    print h3("WKS templates for server: $server");

    for $i (0..$#q) {
      $q[$i][0]=
	"<a href=\"$selfurl?menu=templates&wks_id=$q[$i][3]\">$q[$i][0]</a>";
    }
    display_list(['Name','Comment','Lvl'],\@q,0);
    print "<br>";
    return;
  }
  elsif ($sub eq 'pc') {
    db_query("SELECT id,name,comment FROM printer_classes " .
	     "ORDER BY name;",\@q);
    print h3("PRINTER Classes (global)");

    for $i (0..$#q) {
      $q[$i][1]=
	"<a href=\"$selfurl?menu=templates&pc_id=$q[$i][0]\">$q[$i][1]</a>";
    }
    display_list(['Name','Comment'],\@q,1);
    print "<br>";
    return;
  }
  elsif ($sub eq 'hinfo') {
    db_query("SELECT id,type,hinfo,pri FROM hinfo_templates " .
	     "ORDER BY type,pri,hinfo;",\@q);

    print h3("HINFO templates (global)");

    for $i (0..$#q) {
	$q[$i][1]=($q[$i][1]==0 ? "Hardware" : "Software");
	$q[$i][2]="<a href=\"$selfurl?menu=templates&hinfo_id=$q[$i][0]\">" .
	          "$q[$i][2]</a>";
    }
    display_list(['Type','HINFO','Priority'],\@q,1);
    print "<br>";
    return;
  }
  elsif ($sub eq 'Edit') {
    if ($mx_id > 0) {
      $res=edit_magic('mx','MX template','templates',\%mx_template_form,
		      \&restricted_get_mx_template,
		      \&restricted_update_mx_template,$mx_id);
      goto show_mxt_record if ($res > 0);
    } elsif ($wks_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('wks','WKS template','templates',\%wks_template_form,
		      \&get_wks_template,\&update_wks_template,$wks_id);
      goto show_wkst_record if ($res > 0);
    } elsif ($pc_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('pc','PRINTER class','templates',\%printer_class_form,
		      \&get_printer_class,\&update_printer_class,$pc_id);
      goto show_pc_record if ($res > 0);
    } elsif ($hinfo_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('hinfo','HINFO template','templates',
		      \%hinfo_template_form,
		      \&get_hinfo_template,\&update_hinfo_template,$hinfo_id);
      goto show_hinfo_record if ($res > 0);
    } else { print p,"Unknown template type!"; }
    return;
  }
  elsif ($sub eq 'Delete') {
    if ($mx_id > 0) {
      if (get_mx_template($mx_id,\%h)) {
	print h2("Cannot get mx template (id=$mx_id)");
	return;
      }
      return if (check_perms('tmplmask',$h{name}));
      if (param('mx_cancel')) {
	print h2('MX template not removed');
	goto show_mxt_record;
      }
      elsif (param('mx_confirm')) {
	$new_id=param('mx_new');
	if ($new_id eq $mx_id) {
	  print h2("Cannot change host records to point template " .
		   "being deleted!");
	  goto show_mxt_record;
	}
	$new_id=-1 unless ($new_id > 0);
	if (db_exec("UPDATE hosts SET mx=$new_id WHERE mx=$mx_id;") < 0) {
	  print h2('Cannot update records pointing to this template!');
	  return;
	}
	if (delete_mx_template($mx_id) < 0) {
	  print "<FONT color=\"red\">",h1("MX template delete failed!"),
	        "</FONT>";
	  return;
	}
	print h2("MX template successfully deleted.");
	return;
      }

      undef @q;
      db_query("SELECT COUNT(id) FROM hosts WHERE mx=$mx_id;",\@q);
      print p,"$q[0][0] host records use this template.",
	      startform(-method=>'GET',-action=>$selfurl);
      if ($q[0][0] > 0) {
	get_mx_template_list($zoneid,\%lsth,\@lst,$perms{alevel});
	print p,"Change those host records to point to: ",
	        popup_menu(-name=>'mx_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
      }
      print hidden('menu','templates'),hidden('sub','Delete'),
	      hidden('mx_id',$mx_id),p,
	      submit(-name=>'mx_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'mx_cancel',-value=>'Cancel'),end_form;
      display_form(\%h,\%mx_template_form);

    } elsif ($wks_id > 0) {
      return if (check_perms('superuser',''));
      if (get_wks_template($wks_id,\%h)) {
	print h2("Cannot get wks template (id=$wks_id)");
	return;
      }
      if (param('wks_cancel')) {
	print h2('WKS template not removed');
	goto show_wkst_record;
      } 
      elsif (param('wks_confirm')) {
	$new_id=param('wks_new');
	if ($new_id eq $wks_id) {
	  print h2("Cannot change host records to point template " .
		   "being deleted!");
	  goto show_wkst_record;
	}
	$new_id=-1 unless ($new_id > 0);
	if (db_exec("UPDATE hosts SET wks=$new_id WHERE wks=$wks_id;") < 0) {
	  print h2('Cannot update records pointing to this template!');
	  return;
	}
	if (delete_wks_template($wks_id) < 0) {
	  print "<FONT color=\"red\">",h1("WKS template delete failed!"),
	        "</FONT>";
	  return;
	}
	print h2("WKS template successfully deleted.");
	return;
      }

      undef @q;
      db_query("SELECT COUNT(id) FROM hosts WHERE wks=$wks_id;",\@q);
      print p,"$q[0][0] host records use this template.",
	      startform(-method=>'GET',-action=>$selfurl);
      if ($q[0][0] > 0) {
	get_wks_template_list($serverid,\%lsth,\@lst,$perms{alevel});
	print p,"Change those host records to point to: ",
	        popup_menu(-name=>'wks_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
      }
      print hidden('menu','templates'),hidden('sub','Delete'),
	      hidden('wks_id',$wks_id),p,
	      submit(-name=>'wks_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'wks_cancel',-value=>'Cancel'),end_form;
      display_form(\%h,\%wks_template_form);

    }
    elsif ($pc_id > 0) {
      return if (check_perms('superuser',''));
      $res=delete_magic('pc','PRINTER class','templates',\%printer_class_form,
			\&get_printer_class,\&delete_printer_class,$pc_id);
      goto show_pc_record if ($res==2);
    }
    elsif ($hinfo_id > 0) {
      return if (check_perms('superuser',''));
      $res=delete_magic('hinfo','HINFO template','templates',
			\%hinfo_template_form,\&get_hinfo_template,
			\&delete_hinfo_template,$hinfo_id);
      goto show_hinfo_record if ($res==2);
    }
    else { print p,"Unknown template type!"; }
    return;
  }
  elsif ($sub eq 'addmx') {
    $data{zone}=$zoneid; $data{alevel}=0; $data{mx_l}=[];
    $res=add_magic('addmx','MX template','templates',\%mx_template_form,
		   \&restricted_add_mx_template,\%data);
    if ($res > 0) {
      $mx_id=$res;
      goto show_mxt_record;
    }
    return;
  }
  elsif ($sub eq 'addwks') {
    return if (check_perms('superuser',''));
    $data{server}=$serverid; $data{alevel}=0; $data{wks_l}=[];
    $res=add_magic('addwks','WKS template','templates',\%wks_template_form,
		   \&add_wks_template,\%data);
    if ($res > 0) {
      $wks_id=$res;
      goto show_wkst_record;
    }
    return;
  }
  elsif ($sub eq 'addpc') {
    return if (check_perms('superuser',''));
    $data{printer_l}=[];
    $res=add_magic('addwpc','PRINTER class','templates',
		   \%printer_class_form,\&add_printer_class,\%data);
    if ($res > 0) {
      $pc_id=$res;
      goto show_pc_record;
    }
    return;
  }
  elsif ($sub eq 'addhinfo') {
    return if (check_perms('superuser',''));
    $data{type}=0;
    $data{pri}=100;
    $res=add_magic('addhinfo','HINFO template','templates',
		   \%hinfo_template_form,\&add_hinfo_template,\%data);
    if ($res > 0) {
      $hinfo_id=$res;
      goto show_hinfo_record;
    }
    return;
  }
  elsif ($mx_id > 0) {
  show_mxt_record:
    if (get_mx_template($mx_id,\%mxhash)) {
      print h2("Cannot get MX template (id=$mx_id)!");
      return;
    }
    display_form(\%mxhash,\%mx_template_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','templates');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('tmplmask',$mxhash{name},1));
    print hidden('mx_id',$mx_id),end_form;
    return;
  }
  elsif ($wks_id > 0) {
  show_wkst_record:
    if (get_wks_template($wks_id,\%wkshash)) {
      print h2("Cannot get WKS template (id=$wks_id)!");
      return;
    }
    display_form(\%wkshash,\%wks_template_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','templates');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('superuser','',1));
    print hidden('wks_id',$wks_id),end_form;
    return;
  }
  elsif ($pc_id > 0) {
  show_pc_record:
    if (get_printer_class($pc_id,\%pchash)) {
      print h2("Cannot get PRINTER class (id=$pc_id)!");
      return;
    }
    display_form(\%pchash,\%printer_class_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','templates');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('superuser','',1));
    print hidden('pc_id',$pc_id),end_form;
    return;
  }
  elsif ($hinfo_id > 0) {
  show_hinfo_record:
    if (get_hinfo_template($hinfo_id,\%hinfohash)) {
      print h2("Cannot get HINFO template (id=$hinfo_id)!");
      return;
    }
    display_form(\%hinfohash,\%hinfo_template_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','templates');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('superuser','',1));
    print hidden('hinfo_id',$hinfo_id),end_form;
    return;
  }

  # display MX template list by default
  goto show_mx_template_list;
}


# LOGIN menu
#
sub login_menu() {
  $sub=param('sub');

  if (get_user($state{user},\%user) < 0) {
      fatal("Cannot get user record!");
  };

  if ($sub eq 'login') {
    print h2("Login as another user?"),p,
          "Click <a href=\"$s_url/login\" target=\"_top\">here</a> ",
          "if you want to login as another user.";
  }
  elsif ($sub eq 'logout') {
    print h2("Logout from the system?"),p,
          "Click <a href=\"$s_url/logout\" target=\"_top\">here</a> ",
          "if you want to logout.";
  }
  elsif ($sub eq 'passwd') {
    if ($SAURON_AUTH_PROG) {
      print h3("External authentication in use. " .
	       "Cannot change password through here.");
      return;
    }
    if (param('passwd_cancel')) {
      print h2("Password not changed.");
      return;
    }
    elsif (param('passwd_submit') ne '') {
      unless (($res=form_check_form('passwd',\%h,\%change_passwd_form))) {
	if (param('passwd_new1') ne param('passwd_new2')) {
	  print "<FONT color=\"red\">",h2("New passwords dont match!"),
	        "</FONT>";
	} else {
	  unless (pwd_check(param('passwd_old'),$user{password})) {
	    $password=pwd_make(param('passwd_new1'),$SAURON_PWD_MODE);
	    $ticks=time();
	    if (db_exec("UPDATE users SET password='$password', " .
			"last_pwd=$ticks WHERE id=$state{uid};") < 0) {
	      print "<FONT color=\"red\">",
	             h2("Password update failed!"),"</FONT>";
	      return;
	    }
	    print p,h2("Password changed succesfully.");
	    return;
	  }
	  print "<FONT color=\"red\">",h2("Invalid password!"),"</FONT>";
	}
      } else {
	print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
      }
    }
    print h2("Change password:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','passwd');
    form_magic('passwd',\%h,\%change_passwd_form);
    print submit(-name=>'passwd_submit',-value=>'Change password')," ",
          submit(-name=>'passwd_cancel',-value=>'Cancel'), end_form;
    return;
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
      print h3('Defaults saved successfully!');
    }
  }
  elsif ($sub eq 'edit') {
    %data=%user;
    $res=display_dialog("Personal Settings",\%data,\%user_settings_form,
			 'menu,sub',$selfurl);
    if ($res == 1) {
      $tmp= ($data{email_notify} ? ($user{flags} | 0x0001) :
	                           ($user{flags} & 0xfffe));
      $sqlstr="UPDATE users SET email=".db_encode_str($data{email}).", ".
	      "flags=$tmp WHERE id=$state{uid}";
      $res=db_exec($sqlstr);
      if ($res < 0) {
	print h3("Cannot save personal settings!");
      } else {
	print h3("Personal settings successfully updated.");
      }
      get_user($state{user},\%user);
      goto show_user_info;
    } elsif ($res == -1) {
      print h2("No changes made.");
    }
  }
  elsif ($sub eq 'who') {
    $timeout=$SAURON_USER_TIMEOUT;
    unless ($timeout > 0) {
      print h2("error: $SAURON_USER_TIMEOUT not defined in configuration!");
      return;
    }
    undef @wholist;
    get_who_list(\@wholist,$timeout);
    print h2("Current users:");
    display_list(['User','Name','From','Idle','Login'],\@wholist,0);
    print "<br>";
  }
  elsif ($sub eq 'lastlog') {
    return if (check_perms('superuser',''));
    $count=get_lastlog(40,'',\@lastlog);
    print h2("Lastlog:");
    for $i (0..($count-1)) {
      $lastlog[$i][1] = "<a href=\"$selfurl?menu=login&sub=session&session_sid=$lastlog[$i][1]\">$lastlog[$i][1]</a>";
    }
    display_list(['User','SID','Host','Login','Logout (session length)'],
		 \@lastlog,0);
    print "<br>";
  }
  elsif ($sub eq 'session') {
    return if (check_perms('superuser',''));
    print startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','session');
    form_magic('session',\%h,\%session_id_form);
    print submit(-name=>'session_submit',-value=>'Select'), end_form, "<HR>";

    if (param('session_sid') > 0) {
      $session_id=param('session_sid');
      undef @q;
      db_query("SELECT l.uid,l.date,l.ldate,l.host,u.username " .
	       "FROM lastlog l, users u " .
	       "WHERE l.uid=u.id AND l.sid=$session_id;",\@q);
      if (@q > 0) {
	print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1>",
              "<TR bgcolor=\"#aaaaff\">",th("SID"),th("User"),th("Login"),
	      th("Logout"),th("From"),"</TR>";
	$date1=localtime($q[0][1]);
	$date2=($q[0][2] > 0 ? localtime($q[0][2]) : '&nbsp;');
	print "<TR bgcolor=\"#eeeebf\">",
	         td($session_id),td($q[0][4]),td($date1),td($date2),
		 td($q[0][3]),"</TR></TABLE>";
      }

      undef @q;
      get_history_session($session_id,\@q);
      print h3("Session history:");
      display_list(['Date','Type','Ref','Action','Info'],\@q,0);
    }
  }
  elsif ($sub eq 'motd') {
    print h2("News & motd (message of day) messages:");
    get_news_list($serverid,10,\@list);
    print "<TABLE width=\"99%\" cellspacing=1 cellpadding=4 " .
          " bgcolor=\"#ccccff\">";
    print "<TR bgcolor=\"#aaaaff\"><TH width=\"70%\">Message</TH>",
          th("Date"),th("Type"),th("By"),"</TR>";
    for $i (0..$#list) {
      $date=localtime($list[$i][0]);
      $type=($list[$i][2] < 0 ? 'Global' : 'Local');
      $msg=$list[$i][3];
      #$msg =~ s/\n/<BR>/g;
      print "<TR bgcolor=\"#ddeeff\"><TD>$msg</TD>",
		   td($date),td($type),td($list[$i][1]),"</TR>";
    }
    print "</TABLE><br>";
  }
  elsif ($sub eq 'addmotd') {
    return if (check_perms('superuser',''));

    $new_motd_enum{$serverid}='Local (this server only)';
    $data{server}=-1 unless (param('motdadd_server'));
    $res=add_magic('motdadd','News','news',\%new_motd_form,
		   \&add_news,\%data);
    if ($res > 0) {
      # print "<p>$data{info}";
    }

    return;
  }
  else {
  show_user_info:
    print h2("User info:");
    $state{email}=$user{email};
    $state{name}=$user{name};
    $state{last_pwd}=$user{last_pwd};
    $state{expiration}=($user{expiration} > 0 ? 
			localtime($user{expiration}) : 'None');
    $state{email_notify}=$user{email_notify};
    if ($state{gid} > 0) {
	undef @q;
	db_query("SELECT name FROM user_groups WHERE id=$state{gid}",\@q);
	$state{groupname}=$q[0][0];
    } else {
	$state{groupname}='&lt;None&gt;';
    }
    display_form(\%state,\%user_info_form);

    # server permissions
    print h3("Permissions:"),"<TABLE border=0 cellspacing=1>",
	  "<TR bgcolor=\"#aaaaff\"><TD>Type</TD><TD>Ref.</TD>",
	  "<TD>Permissions</TD></TR>";
    foreach $s (keys %{$perms{server}}) {
      undef @q; 
      db_query("SELECT name FROM servers WHERE id=$s;",\@q);
      $s_name=$q[0][0];
      print "<TR bgcolor=\"#dddddd\">",td("Server"),td("$s_name"),
            td($perms{server}->{$s}." &nbsp;"),"</TR>";
    }

    # zone permissions
    foreach $s (keys %{$perms{zone}}) {
      undef @q; 
      db_query("SELECT s.name,z.name FROM zones z, servers s " .
	       "WHERE z.server=s.id AND z.id=$s;",\@q);
      $z_name="$q[0][0]:$q[0][1]";
      print "<TR bgcolor=\"#dddddd\">",td("Zone"),td("$z_name"),
	     td($perms{zone}->{$s}." &nbsp;"),"</TR>";
    }

    # net permissions
    foreach $s (keys %{$perms{net}}) {
      undef @q; 
      db_query("SELECT s.name,n.net,n.range_start,n.range_end " .
	       "FROM servers s, nets n WHERE n.server=s.id AND n.id=$s;",\@q);
      $z_name="$q[0][0]:$q[0][1]" . db_lasterrormsg();
      print "<TR bgcolor=\"#dddddd\">",td("Net"),td("$z_name"),
	     td($perms{net}->{$s}[0]." - ".$perms{net}->{$s}[1]),"</TR>";
    }

    # host permissions
    foreach $s (@{$perms{hostname}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Hostname"),td("$s"),
	     td("(hostname constraint)"),"</TR>";
    }

    # IP-mask permissions
    foreach $s (@{$perms{ipmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("IP-mask"),td("$s"),
	     td("(IP address constraint)"),"</TR>";
    }
    # Delete-mask permissions
    foreach $s (@{$perms{delmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Del-mask"),td("$s"),
	     td("(Delete host mask)"),"</TR>";
    }
    # Template-mask permissions
    foreach $s (@{$perms{tmplmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Template-mask"),td("$s"),
	     td("(Template modify mask)"),"</TR>";
    }
    # Group-mask permissions
    foreach $s (@{$perms{grpmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Group-mask"),td("$s"),
	     td("(Group modify mask)"),"</TR>";
    }

    # RHF
    foreach $s (sort keys %{$perms{rhf}}) {
      print "<TR bgcolor=\"#dddddd\">",td("ReqHostField"),td("$s"),
	    td(($perms{rhf}->{$s} ? 'Optional':'Required')),"</TR>";
    }

    # alevel permissions
    print "<TR bgcolor=\"#dddddd\">",td("Level"),td($perms{alevel}),
	     td("(authorization level)"),"</TR>";


    print "</TABLE><P>&nbsp;";
  }
}

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

sub edit_magic($$$$$$$) {
  my($prefix,$name,$menu,$form,$get_func,$update_func,$id) = @_;
  my(%h);

  if (($id eq '') || ($id < 1)) {
    print h2("$name id not specified!");
    return -1;
  }

  if (param($prefix . '_cancel') ne '') {
    print h2("No changes made to $name record.");
    return 2;
  }

  if (param($prefix . '_submit') ne '') {
    if(&$get_func($id,\%h) < 0) {
      print h2("Cannot find $name record anymore! ($id)");
      return -2;
    }
    unless (($res=form_check_form($prefix,\%h,$form))) {
      $res=&$update_func(\%h);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("$name record update failed! ($res)"),
	      "</FONT>";
      } else {
	print h2("$name record successfully updated");
	#&$get_func($id,\%h);
	#display_form(\%h,$form);
	return 1;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  unless (param($prefix . '_re_edit') eq '1') {
    if (&$get_func($id,\%h)) {
      print h2("Cannot get $name record (id=$id)!");
      return -3;
    }
  }

  print h2("Edit $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Edit');
  form_magic($prefix,\%h,$form);
  print submit(-name=>$prefix . '_submit',-value=>'Make changes'), "  ",
        submit(-name=>$prefix . '_cancel',-value=>'Cancel'),
        end_form;

  return 0;
}

sub add_magic($$$$$$) {
  my($prefix,$name,$menu,$form,$add_func,$data) = @_;
  my(%h);

  if (param($prefix . '_cancel')) {
    print h2("$name record not created!");
    return -1;
  }

  if (param($prefix . '_submit') ne '') {
    unless (($res=form_check_form($prefix,$data,$form))) {
      $res=&$add_func($data);
      if ($res < 0) {
	print "<FONT color=\"red\">",h1("Adding $name record failed! ($res)"),
	      "</FONT>";
      } else {
	print h3("$name record successfully added");
	return $res;
      }
    } else {
      print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
    }
  }

  print h2("New $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub',$prefix);
  form_magic($prefix,\%data,$form);
  print submit(-name=>$prefix . '_submit',-value=>"Create $name")," ",
        submit(-name=>$prefix . '_cancel',-value=>"Cancel"),end_form;
  return 0;
}

sub delete_magic($$$$$$$) {
  my($prefix,$name,$menu,$form,$get_func,$del_func,$id) = @_;
  my(%h);

  if (($id eq '') || ($id < 1)) {
    print h2("$name id not specified!");
    return -1;
  }

  if (param($prefix . '_cancel') ne '') {
    print h2("$name record not deleted.");
    return 2;
  }

  if (param($prefix . '_confirm') ne '') {
    if(&$get_func($id,\%h) < 0) {
      print h2("Cannot find $name record anymore! ($id)");
      return -2;
    }

    $res=&$del_func($id);
    if ($res < 0) {
      print "<FONT color=\"red\">",h1("$name record delete failed!"),
      "<br>result code=$res</FONT>";
      return -10;
    } else {
      print h2("$name record successfully deleted");
      return 1;
    }
  }


  if (&$get_func($id,\%h)) {
    print h2("Cannot get $name record (id=$id)!");
    return -3;
  }

  print h2("Delete $name:"),p,
          startform(-method=>'POST',-action=>$selfurl),
          hidden('menu',$menu),hidden('sub','Delete'),
          hidden($prefix . "_id",$id);
  print submit(-name=>$prefix . '_confirm',-value=>'Delete'),"  ",
        submit(-name=>$prefix . '_cancel',-value=>'Cancel'),end_form;
  display_form(\%h,$form);
  return 0;
}



sub logout() {
  my($c,$u);
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
        h1("Sauron"),p,p,"You are now logged out...",
        end_html();
  exit;
}

sub login_form($$) {
  my($msg,$c)=@_;
  my($host);

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
        submit(-name=>'submit',-value=>'Login'),end_form,
        p,"<br><br>You need to have cookies enabled for this site...",
        "<br></CENTER></TD></TR></TABLE>",end_html();

  $state{'mode'}='1';
  $state{'auth'}='no';
  $state{'superuser'}='no';
  save_state($c);
  exit;
}

sub login_auth() {
  my($u,$p);
  my(%user,%h,$ticks,$pwd_chk);

  $ticks=time();
  $state{'auth'}='no';
  $state{'mode'}='0';
  $u=param('login_name');
  $p=param('login_pwd');
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
      if ($SAURON_AUTH_PROG) {
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
	$state{'gid'}=$user{'gid'};
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
	    startform(-method=>'POST',-action=>$s_url),
	    submit(-name=>'submit',-value=>'No Frames'),end_form,
	    "</TD><TD> ",
	    startform(-method=>'POST',-action=>"$s_url/frames"),
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

	print "</CENTER></td></tr></table>\n";
	logmsg("notice","user ($u) logged in from: $remote_addr");
	$last_from = db_encode_str($remote_addr);
	db_exec("UPDATE users SET last=$ticks,last_from=$last_from " .
		"WHERE id=$user{'id'};");
	update_lastlog($state{uid},$state{sid},1,
		       $remote_addr,$remote_host);
      }
    }
  }

  print p,h1("Login failed."),p,"<a href=\"$selfurl\">try again</a>"
    unless ($state{'auth'} eq 'yes');

  print p,p,"</CENTER>";

  print "</TABLE>\n" unless ($frame_mode);
  print end_html();
  save_state($scookie);
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

#####################################################################

sub make_cookie($) {
  my($path) = @_;

  my($val,$ctx);

  $val=rand 100000;

  $ctx=new Digest::MD5;
  $ctx->add($val);
  $ctx->add($$);
  $ctx->add(time);
  $ctx->add(rand 1000000);
  $val=$ctx->hexdigest;

  undef %state;
  $state{auth}='no';
  #$state{'host'}=remote_host();
  $state{addr}=($remote_addr ? $remote_addr : '0.0.0.0');
  save_state($val);
  $ncookie=$val;
  return cookie(-name=>"sauron-$SERVER_ID",-expires=>'+7d',
		-value=>$val,-path=>$path,
		-secure=>($SAURON_SECURE_COOKIES ? 1 :0));
}

sub save_state($) {
  my($id)=@_;
  my(@q,$res,$s_auth,$s_addr,$other,$s_mode);

  undef @q;
  db_query("SELECT uid,cookie FROM utmp WHERE cookie='$id';",\@q);
  unless (@q > 0) {
      if (db_exec("INSERT INTO utmp (uid,cookie,auth) " .
		  "VALUES(-1,'$id',false);") < 0) {
	logmsg("notice","cannot create utmp entry ($id): $remote_addr : ".
	                db_errormsg());
	html_error("cannot create utmp entry ($id)");
      }
  }

  $s_superuser = ($state{'superuser'} eq 'yes' ? 'true' : 'false');
  $s_auth=($state{'auth'} eq 'yes' ? 'true' : 'false');
  $s_mode=($state{'mode'} ? $state{'mode'} : 0);
  $s_addr=$state{'addr'};

  $other='';
  if ($state{'uid'}) { $other.=", uid=".$state{'uid'}." ";  }
  if ($state{'gid'}) { $other.=", gid=".$state{'gid'}." ";  }
  if ($state{'sid'}) { $other.=", sid=".$state{'sid'}." ";  }
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
  $other.=", searchopts=". db_encode_str($state{'searchopts'}) . " ";
  $other.=", searchdomain=". db_encode_str($state{'searchdomain'}) . " ";
  $other.=", searchpattern=". db_encode_str($state{'searchpattern'}) . " ";

  $res=db_exec("UPDATE utmp SET auth=$s_auth, addr='$s_addr', mode=$s_mode " .
	       ", superuser=$s_superuser $other " .
	       "WHERE cookie='$id';");

  if ($res < 0) {
    logmsg("notice","cannot save state '$id' " .
	            "(addr=$s_addr,uid=$state{uid},user=$state{user}): " .
                    db_errormsg());
    html_error("cannot save state '$id' ($state{uid},$state{user})");
  }
}


sub load_state($) {
  my($id)=@_;
  my(@q);

  undef %state;
  $state{'auth'}='no';

  db_query("SELECT uid,addr,auth,mode,serverid,server,zoneid,zone," .
	   " uname,last,login,searchopts,searchdomain,searchpattern," .
           " superuser,gid,sid " .
           "FROM utmp WHERE cookie='$id'",\@q);

  if (@q > 0) {
    $state{'uid'}=$q[0][0];
    $state{'addr'}=$q[0][1];
    $state{'addr'} =~ s/\/32\s*$//;
    $state{'auth'}='yes' if ($q[0][2] eq 't' || $q[0][2] == 1);
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
    $state{'login'}=$q[0][10];
    $state{'searchopts'}=$q[0][11];
    $state{'searchdomain'}=$q[0][12];
    $state{'searchpattern'}=$q[0][13];
    $state{'superuser'}='yes' if ($q[0][14] eq 't' || $q[0][14] == 1);
    $state{'gid'}=$q[0][15];
    $state{'sid'}=$q[0][16];

    #logmsg("debug","load_state: " . join(',',@{$q[0]}));
    db_exec("UPDATE utmp SET last=" . time() . " WHERE cookie='$id';");
    return 1;
  }

  return 0;
}

sub remove_state($) {
  my($id) = @_;

  db_exec("DELETE FROM utmp WHERE cookie='$id';") if ($id);
  undef %state;
}

sub check_perms($$$) {
  my($type,$rule,$quiet) = @_;
  my($i,$re,@n,$s,$e,$ip);

  return 0 if ($state{superuser} eq 'yes');

  if ($type eq 'superuser') {
    return 1 if ($quiet);
    alert1("Access denied: administrator priviliges required.");
    return 1;
  }
  elsif ($type eq 'level') {
    return 0 if ($perms{alevel} >= $rule);
    alert1("Higher authorization level required") unless($quiet);
    return 1;
  }
  elsif ($type eq 'server') {
    return 0 if ($perms{server}->{$serverid} =~ /$rule/);
  }
  elsif ($type eq 'zone') {
    return 0 if ($SAURON_PRIVILEGE_MODE==0 &&
		 $perms{server}->{$serverid} =~ /$rule/);
    return 0 if ($perms{zone}->{$zoneid} =~ /$rule/);
  }
  elsif ($type eq 'host' || $type eq 'delhost') {
    return 0  if ($perms{server}->{$serverid} =~ /RW/);
    if ($perms{zone}->{$zoneid} =~ /RW/) {
      return 0 if (@{$perms{hostname}} == 0);

      for $i (0..$#{$perms{hostname}}) {
	$re=$perms{hostname}[$i];
	return 0 if ($rule =~ /$re/);
      }

      if ($type eq 'delhost') {
	for $i (0..$#{$perms{delmask}}) {
	  $re=$perms{delmask}[$i];
	  return 0 if ($rule =~ /$re/);
	}
      }
    }

    alert1("You are not authorized to modify this host record")
      unless ($quiet);
    return 1;
  }
  elsif ($type eq 'ip') {
    @n=keys %{$perms{net}};
    return 0  if (@n < 1 && @{$perms{ipmask}} < 1);
    $ip=ip2int($rule); #print "<br>ip=$rule ($ip)";

    for $i (0..$#n) {
      $s=ip2int($perms{net}->{$n[$i]}[0]);
      $e=ip2int($perms{net}->{$n[$i]}[1]);
      if (($s > 0) && ($e > 0)) {
	#print "<br>$i $n[$i] $s,$e : $ip";
	return 0 if (($s <= $ip) && ($ip <= $e));
      }
    }
    for $i (0..$#{$perms{ipmask}}) {
	$re=$perms{ipmask}[$i];
	#print p,"regexp='$re' '$rule'";
	return 0 if (check_ipmask($re,$rule));
    }

    alert1("Invalid IP (IP is outsize allowed net(s))") unless ($quiet);
    return 1;
  }
  elsif ($type eq 'tmplmask') {
    for $i (0..$#{$perms{tmplmask}}) {
      $re=$perms{tmplmask}[$i];
      return 0 if ($rule =~ /$re/);
    }
    alert1("You are not authorized to modify this template") unless ($quiet);
    return 1;
  }
  elsif ($type eq 'grpmask') {
    for $i (0..$#{$perms{grpmask}}) {
      $re=$perms{grpmask}[$i];
      return 0 if ($rule =~ /$re/);
    }
    alert1("You are not authorized to modify this group") unless ($quiet);
    return 1;
  }

  alert1("Access to $type denied") unless ($quiet);
  return 1;
}

############################################################################


sub restricted_add_host($) {
  my($rec)=@_;

  if (check_perms('host',$rec->{domain},1)) {
    alert1("Invalid hostname: does not conform your restrictions");
    return -101;
  }

  return add_host($rec);
}

sub restricted_add_mx_template($) {
  my($rec)=@_;

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to create");
    return -101;
  }
  return add_mx_template($rec);
}

sub restricted_update_mx_template($) {
  my($rec)=@_;

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to update");
    return -101;
  }
  return update_mx_template($rec);
}

sub restricted_get_mx_template($$) {
  my($id,$rec)=@_;

  my($r);
  $r=get_mx_template($id,$rec);
  return $r if ($r < 0);

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to modify");
    return -101;
  }
  return $r;
}

sub restricted_add_group($) {
  my($rec)=@_;

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to create");
    return -101;
  }
  return add_group($rec);
}

sub restricted_get_group($$) {
  my($id,$rec)=@_;

  my($r);
  $r=get_group($id,$rec);
  return $r if ($r < 0);

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to modify");
    return -101;
  }
  return $r;
}

sub restricted_update_group($) {
  my($rec)=@_;

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to update");
    return -101;
  }
  return update_group($rec);
}


sub add_default_zones($$) {
  my($serverid,$verbose) = @_;

  my($id,%zone,%host);


  %zone=(name=>'localhost',type=>'M',reverse=>'f',server=>$serverid,
	 ns=>[[0,'localhost.','']],ip=>[[0,'127.0.0.1','t','t','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'127.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'0.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

  %zone=(name=>'255.in-addr.arpa',type=>'M',reverse=>'t',server=>$serverid,
	ns=>[[0,'localhost.','']]);
  print "Adding zone: $zone{name}...";
  if (($id=add_zone(\%zone)) < 0) {
    print "failed (zone already exists? $id)\n";
  } else {
    print "OK (id=$id)\n";
  }

}			


sub run_ping_sweep($$$)
{
  my($iplist,$resulthash,$user) = @_;
  my($i,$r,$ip);
  my($nmap_file,$nmap_log);

  unless (-d $SAURON_NMAP_TMPDIR && -w $SAURON_NMAP_TMPDIR) {
    logmsg("notice","SAURON_NMAP_TMPDIR misconfigured");
    return -1;
  }
  $nmap_file = "$SAURON_NMAP_TMPDIR/nmap-$$.input";
  $nmap_log = "$SAURON_NMAP_TMPDIR/nmap-$$.log";

  # print h3("Please wait...Running Ping sweep.");
  logmsg("notice","running nmap (ping sweep): $user");

  unless (open(FILE,">$nmap_file")) {
    logmsg("notice","cannot write tmp file for nmap: $nmap_file");
    return -2;
  }
  for $i (0..$#{$iplist}) {
    $ip=$$iplist[$i];
    next unless (is_cidr($ip));
    print FILE "$ip\n";
  }
  close(FILE);

  $SAURON_NMAP_ARGS = '-n -sP' unless ($SAURON_NMAP_ARGS);
  $r = run_command_quiet($SAURON_NMAP_PROG,
			 [split(/\s+/,$SAURON_NMAP_ARGS),
			 '-oG',$nmap_log,'-iL',$nmap_file],
			 $SAURON_NMAP_TIMEOUT);
  unlink($nmap_file);
  unless ($r == 0) {
    return 1 if (($r & 255) == 14);
    return -3;
  }

  unless (open(FILE,"$nmap_log")) {
    logmsg("notice","failed to read nmap output file: $nmap_log");
    return -4;
  }

  while (<FILE>) {
    next if (/^\#/);
    next unless (/^\s*Host:\s+(\d+\.\d+\.\d+\.\d+)\s.*(Status:\s+(\S+))/);
    $nmaphash{$1}=$3;
  }
  close(FILE);
  unlink($nmap_log);

  return 0;
}

# eof

