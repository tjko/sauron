#!/usr/bin/perl
#
# sauron.cgi
# $Id$
# åäö
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000,2001.
# All Rights Reserved.
#
use Sys::Syslog;
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
use Digest::MD5;
use Net::Netmask;

$CGI::DISABLE_UPLOADS = 1; # no uploads
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

%check_names_enum = (D=>'Default',W=>'Warn',F=>'Fail',I=>'Ignore');
%yes_no_enum = (D=>'Default',Y=>'Yes', N=>'No');

%server_form = (
 data=>[
  {ftype=>0, name=>'Server' },
  {ftype=>1, tag=>'name', name=>'Server name', type=>'text', len=>20},
  {ftype=>4, tag=>'id', name=>'Server ID'},
  {ftype=>3, tag=>'zones_only', name=>'Output mode', type=>'enum',
   conv=>'L', enum=>{t=>'Generate named.zones',f=>'Generate full named.conf'}},
  {ftype=>3, tag=>'nnotify', name=>'Notify', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'recursion', name=>'Recursion', type=>'enum',
   conv=>'U', enum=>\%yes_no_enum},
  {ftype=>3, tag=>'checknames_m', name=>'Check-names (Masters)', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'checknames_s', name=>'Check-names (Slaves)', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'checknames_r', name=>'Check-names (Responses)',type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>1, tag=>'comment', name=>'Comments',  type=>'text', len=>60,
   empty=>1},

  {ftype=>0, name=>'Defaults for zones'},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'fqdn', len=>30,
   default=>'hostmaster.my.domain.'},
  {ftype=>1, tag=>'hostname', name=>'Hostname',type=>'fqdn', len=>30,
   default=>'ns.my.domain.'},
  {ftype=>1, tag=>'refresh', name=>'Refresh', type=>'int', len=>10},
  {ftype=>1, tag=>'retry', name=>'Rery', type=>'int', len=>10},
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
  {ftype=>1, tag=>'stats_file', name=>'stats-file path', type=>'text',
   len=>30, empty=>1},
  {ftype=>1, tag=>'named_xfer', name=>'named-xfer path', type=>'text',
   len=>30, empty=>1},

  {ftype=>0, name=>'Access control'},
  {ftype=>2, tag=>'allow_transfer', name=>'Allow-transfer', fields=>2,
   type=>['cidr','text'], len=>[20,30], empty=>[0,1], 
   elabels=>['IP','comment']},

  {ftype=>0, name=>'DHCP'},
  {ftype=>2, tag=>'dhcp', name=>'Global DHCP', type=>['text','text'], 
   fields=>2, len=>[35,20], empty=>[0,1],elabels=>['dhcptab line','comment']} 
 ]
# bgcolor=>'#eeeebf',
# border=>'0',		
# width=>'100%',
# nwidth=>'30%',
# heading_bg=>'#aaaaff'
);

%new_zone_form=(
 data=>[
  {ftype=>0, name=>'New zone'},
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'domain',len=>40, empty=>0},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward'}},
  {ftype=>3, tag=>'reverse', name=>'Reverse', type=>'enum',  conv=>'L',
   enum=>{f=>'No',t=>'Yes'}}
 ]
);

%zone_form = (
 data=>[
  {ftype=>0, name=>'Zone' },
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'domain', len=>30},
  {ftype=>4, tag=>'reversenet', name=>'Reverse net', iff=>['reverse','t']},
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
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>3, tag=>'chknames', name=>'Check-names', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'nnotify', name=>'Notify', type=>'enum', conv=>'U',
   enum=>\%yes_no_enum, iff=>['type','M']},
  {ftype=>4, tag=>'serial', name=>'Serial', iff=>['type','M']},
  {ftype=>1, tag=>'refresh', name=>'Refresh', type=>'int', len=>10, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'retry', name=>'Rery', type=>'int', len=>10, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'expire', name=>'Expire', type=>'int', len=>10,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>1, tag=>'minimum', name=>'Minimum (negative caching TTL)', 
   empty=>1, definfo=>['','Default (from server)'], type=>'int', len=>10, 
   iff=>['type','M']},
  {ftype=>1, tag=>'ttl', name=>'Default TTL', type=>'int', len=>10, 
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
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
   name=>'(Stealth) Servers to notify (also-notify)', type=>['ip','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['IP','comment'],
   iff=>['type','M']},

  {ftype=>0, name=>'DHCP', iff=>['type','M']},
  {ftype=>2, tag=>'dhcp', name=>'Zone specific DHCP entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment'], iff=>['type','M']}
 ]
);



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
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>4, tag=>'class', name=>'Class'},
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
   iff=>['type','1']},
  {ftype=>1, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo', len=>20,
   iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>12,
   iff=>['type','1'], iff2=>['ether_alias','-1'], empty=>1},
  {ftype=>4, tag=>'ether_alias_info', name=>'ETHER2', 
   iff=>['type','1'], iff2=>['ether_alias','\d+']},

  {ftype=>4, tag=>'card_info', name=>'Card manufacturer', iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>30, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']},
  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host specific',iff=>['type','[12]']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['text','text'], 
   fields=>2,
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,0,1], 
   elabels=>['Protocol','Services','comment'], iff=>['type','1']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', 
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], 
   empty=>[0,0,1], 
   elabels=>['Priority','MX','comment'], iff=>['type','[13]']},
  {ftype=>2, tag=>'txt_l', name=>'TXT', type=>['text','text'], 
   fields=>2,
   len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','1']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2,len=>[40,20], empty=>[0,1], 
   elabels=>['PRINTER','comment'], iff=>['type','[15]']},
  {ftype=>0, name=>'Aliases', no_edit=>1, iff=>['type','1']},
  {ftype=>8, tag=>'alias_l', name=>'Aliases', fields=>3, iff=>['type','1']},

  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,10],
   empty=>[0,0,0,0,1],elabels=>['Priority','Weight','Port','Target','Comment'],
   type=>['priority','priority','priority','fqdn','text'],
   iff=>['type','8']}
 ]
);

%new_host_nets = (dummy=>'dummy');
@new_host_netsl = ('dummy');

%new_host_form = (
 data=>[
  {ftype=>0, name=>'New record' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>40},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>60,
   iff=>['type','4']},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'enum',
   enum=>\%new_host_nets,elist=>\@new_host_netsl,iff=>['type','1']},
  {ftype=>1, tag=>'ip', 
   name=>'IP<FONT size=-1>(only if "Manual IP" selected)</FONT>', 
   type=>'ip', len=>15, empty=>1, iff=>['type','1']},
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
  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>12,
   iff=>['type','1'], empty=>1},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>30, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']}
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
		       4=>'Department',5=>'Model',6=>'Serial',7=>'Misc');
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
  {ftype=>1, tag=>'pattern',name=>'Pattern (substring)',type=>'text',len=>40,
   empty=>1}
 ]
);

%user_info_form=(
 data=>[
  {ftype=>0, name=>'User info' },
  {ftype=>4, tag=>'user', name=>'User name'},
  {ftype=>4, tag=>'login', name=>'Last login', type=>'localtime'},
  {ftype=>4, tag=>'addr', name=>'Host'},
  {ftype=>0, name=>'Current selections'},
  {ftype=>4, tag=>'server', name=>'Server'},
  {ftype=>4, tag=>'zone', name=>'Zone'}
 ]
);


%new_server_form=(
 data=>[
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>20, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ]
);

%new_net_form=(
 data=>[
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>40, empty=>0},
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
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>1, tag=>'vlan', name=>'VLAN', type=>'int',
   iff=>['subnet','t']},
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
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment']}
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
  {ftype=>1, tag=>'inusep', name=>'Usage', type=>'int'}
 ],
 nwidth=>'40%'
);

%group_form=(
 data=>[
  {ftype=>0, name=>'Group'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text', len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1},
  {ftype=>2, tag=>'dhcp', name=>'DHCP entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment']},
  {ftype=>2, tag=>'printer', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['PRINTER','comment']}
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

%new_template_form=(
 data=>[
  {ftype=>0, name=>'New template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>40, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ]
);

%new_group_form = %new_template_form;

%mx_template_form=(
 data=>[
  {ftype=>0, name=>'MX template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', 
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], 
   empty=>[0,0,1],elabels=>['Priority','MX','comment']}
 ]
);

%wks_template_form=(
 data=>[
  {ftype=>0, name=>'WKS template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,0,1], 
   elabels=>['Protocol','Services','comment']}
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
   elabels=>['Printer','comment']}
 ]
);

%new_printer_class_form=(
 data=>[
  {ftype=>0, name=>'New PRINTER class'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'printer_class',len=>20,
   empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1}
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
if (($res=cgi_disabled())) { error("CGI interface disabled: $res"); }
error("Invalid log path") unless (-d $LOG_DIR);

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
  login_form("Welcome",$ncookie);
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
  login_form("Welcome (again)",$scookie);
}

if ((time() - $state{'last'}) > $USER_TIMEOUT) {
  logmsg("notice","connection timed out for $remote_addr " .
	 $state{'user'});
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Your session timed out. Login again",$scookie);
}

error("Unauthorized Access denied!")
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
  $frame_mode=1 if ($pathinfo =~ /^\/frame/);
  logout() if ($pathinfo eq '/logout');
  frame_set() if ($pathinfo eq '/frames');
  frame_set2() if ($pathinfo eq '/frames2');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo =~ /^\/frame2/);
}

unless ($state{superuser} eq 'yes') {
  error("cannot get permissions!") if (get_permissions($state{uid},\%perms));
}

$bgcolor='black';
$bgcolor='white' if ($frame_mode);

print header(-type=>'text/html; charset=iso-8859-1'),
      start_html(-title=>"Sauron $VER",-BGCOLOR=>$bgcolor,
		 -meta=>{'keywords'=>'GNU Sauron DNS DHCP tool'}),
      "\n\n<!-- Sauron $VER -->\n",
      "<!-- Copyright (c) Timo Kokkonen <tjko\@iki.fi>  2000,2001. -->\n\n";

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

if ($menu eq 'servers') { servers_menu(); }
elsif ($menu eq 'zones') { zones_menu(); }
elsif ($menu eq 'login') { login_menu(); }
elsif ($menu eq 'hosts') { hosts_menu(); }
elsif ($menu eq 'about') { about_menu(); }
elsif ($menu eq 'nets') { nets_menu(); }
elsif ($menu eq 'templates') { templates_menu(); }
elsif ($menu eq 'templates') { templates_menu(); }
elsif ($menu eq 'groups') { groups_menu(); }
else { print p,"Unknown menu '$menu'"; }


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

  print "<hr>state vars<p>\n";
  foreach $key (keys %state) {
    print " $key=" . $state{$key} . "<br>";
  }
  print "<hr><p>\n";
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
    $data{server}=$serverid;
    if (param('add_submit')) {
      unless (($res=form_check_form('addzone',\%data,\%new_zone_form))) {
	if ($data{reverse} eq 't') {
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
    $res=edit_magic('zn','Zone','zones',\%zone_form,\&get_zone,\&update_zone,
		    $zoneid);
    goto select_zone if ($res == -1);
    goto display_zone if ($res == 2);
    return;
  }
  elsif ($sub eq 'Copy') {
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
	$|=1 if ($frame_mode);
	print p,"Copying zone...please wait few minutes (or hours :)";
	$res=copy_zone($zoneid,$serverid,$data{name},1);
	if ($res < 0) {
	  print '<FONT color="red">',h2('Zone copy failed (result=$res!'),
	        '</FONT>';
	} else {
	  print h2("Zone succesfully copied (id=$res).");
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
  print h2("Select zone:"),
            p,"<TABLE width=98% bgcolor=white border=0>",
            "<TR bgcolor=\"#aaaaff\">",th(['Zone','Type','Reverse']);

  $list=get_zone_list($serverid);
  for $i (0 .. $#{$list}) {
    $type=$$list[$i][2];
    if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
    elsif ($type eq 'S') { $type='Slave'; $color='#eeeebf'; }
    $rev='No';
    $rev='Yes' if ($$list[$i][3] eq 't');
    $id=$$list[$i][1];
    $name=$$list[$i][0];
	
    print "<TR bgcolor=$color>",td([
	"<a href=\"$selfurl?menu=zones&selected_zone=$name\">$name</a>",
					$type,$rev]);
  }

  print "</TABLE><BR>";

}


# HOSTS menu
#
sub hosts_menu() {
  unless ($serverid) {
    alert1("Server not selected!");
    return;
  }
  unless ($zoneid) {
    alert1("Zone not selected!");
    return;
  }

  $sub=param('sub');
  $host_form{alias_l_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_a_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_d_url}="$selfurl?menu=hosts&h_id=";

  if ($sub eq 'Delete') {
    $res=delete_magic('h','Host','hosts',\%host_form,\&get_host,\&delete_host,
		      param('h_id'));
    goto show_host_record if ($res == 2);
    return;
  }
  elsif ($sub eq 'Alias') {
    $id=param('h_id');
    if ($id > 0) {
      $data{alias}=$id;
      if (get_host($id,\%host)) {
	alert2("Cannot get host record (id=$id)!");
	return;
      }
      $data{aliasname}=$host{domain};
    }
    $data{type}=4;
    $data{zone}=$zoneid;
    $data{alias}=param('aliasadd_alias') if (param('aliasadd_alias'));
    $res=add_magic('aliasadd','ALIAS','hosts',\%new_alias_form,
		   \&add_host,\%data);
    if ($res > 0) {
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
    $id=param('h_id');
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }
    if ($#{$h{ip}} > 1) {
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
	} else {
	  $host{ip}[1][1]=param('new_ip'); 
	  $host{ip}[1][4]=1;
	  unless (update_host(\%host)) {
	    print h2('Host moved.');
	    goto show_host_record;
	  } else {
	    alert1('Host update failed!');
	  }
	}
      }
      print h2("Move host to another IP");
      $newip=auto_address($serverid,param('move_net'));
      unless(is_cidr($newip)) {
	print h3($newip);
	$newip=$host{ip}[1][1];
      }
      print p,startform(-method=>'GET',-action=>$selfurl),
            hidden('menu','hosts'),hidden('h_id',$id),hidden('sub','Move'),
            hidden('move_confirm'),hidden('move_net'),p,"New IP: ",
            textfield(-name=>'new_ip',-maxlength=>15,-default=>$newip), " ",
            submit(-name=>'move_confirm2',-value=>'Update'), " ",
            submit(-name=>'move_cancel',-value=>'Cancel'), " ",
            end_form;
      display_form(\%host,\%host_form);
      return;
    }
    make_net_list($serverid,0,\%nethash,\@netkeys);
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
    $res=edit_magic('h','Host','hosts',\%host_form,\&get_host,\&update_host,
		   param('h_id'));
    goto browse_hosts if ($res == -1);
    goto show_host_record if ($res > 0);
    return;
  }
  elsif ($sub eq 'browse') {
    %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>1,size=>3);
    if (param('bh_submit')) {
      if (param('bh_submit') eq 'Clear') {
	param('bh_pattern','');
	param('bh_stype','1');

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
      if ($state{searchopts} =~ /^(\d+),(\d+),(\d+),(\d+),(\S*),(\S*)$/) {
	param('bh_type',$1);
	param('bh_order',$2);
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

    #if (param('bh_cidr') || param('bh_net') ne 'ANY') {
    #  $type=1;
    #}

    undef %extrarule;
    if (param('bh_pattern')) {
      $tmp=$browse_search_f[param('bh_stype')];
      if ($tmp) {
	$extrarule=" AND a.$tmp LIKE " .
	           db_encode_str('%' . param('bh_pattern') . '%') . " ";
	#print p,$extrarule;
      }
    }

    undef @q;
    $fields="a.id,a.type,a.domain,a.ether,a.info";
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
    } elsif ($count == 1) {
      param('h_id',$q[0][2]);
      goto show_host_record;
    }

    print "<TABLE width=\"99%\" cellspacing=0 cellpadding=1 border=0 " .
          "BGCOLOR=\"aaaaff\">",
          "<TR><TD><B>Zone:</B> $zone</TD>",
          "<TD align=right>Page: ".($page+1)."</TD></TR></TABLE>";

    print "<TABLE width=\"99%\" cellspacing=0 cellpadding=1 BGCOLOR=\"#eeeeff\">",
          Tr,Tr,
          "<TR bgcolor=#aaaaff>",th(['#','Hostname','Type','IP','Ether','Info']);
    for $i (0..$#q) {
      $type=$q[$i][3];
      ($ip=$q[$i][0]) =~ s/\/\d{1,2}$//g;
      $ip="(".add_origin($q[$i][1],$zone).")" if ($type==4);
      $ip='N/A' if ($ip eq '0.0.0.0');
      $ether=$q[$i][5];
      $ether='N/A' unless($ether);
      #$hostname=add_origin($q[$i][4],$zone);
      $hostname="<A HREF=\"$selfurl?menu=hosts&h_id=$q[$i][2]\">".
	        "$q[$i][4]</A>";
      $trcolor='#eeeeee';
      $trcolor='#ffffcc' if ($i % 2 == 0);
      print "<TR bgcolor=\"$trcolor\">",
	    "<TD><FONT size=-1>".($i+1).".</FONT></TD>",
	    td([$hostname,$host_types{$q[$i][3]},$ip,
	       "<PRE>$ether&nbsp;</PRE>",
	       "<FONT size=-1>".$q[$i][6]."&nbsp;</FONT>"]),"</TR>";

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

    print "]</CENTER><BR>";
    return;
  }
  elsif ($sub eq 'add') {
    $type=param('type');
    unless ($host_types{$type}) {
      alert2('Invalid add type!');
      return;
    }
    if ($type == 1) {
      make_net_list($serverid,0,\%new_host_nets,\@new_host_netsl);
      $new_host_nets{MANUAL}='<Manual IP>';
      push @new_host_netsl, 'MANUAL';
      $data{net}='MANUAL';
    }
    $data{type}=$type;
    $data{zone}=$zoneid;
    $data{grp}=-1; $data{mx}=-1; $data{wks}=-1;
    $data{mx_l}=[]; $data{ns_l}=[]; $data{printer_l}=[];


    if (param('addhost_cancel')) {
      print h2("$host_types{$type} record creation canceled.");
      return;
    }
    elsif (param('addhost_submit')) {
      unless (($res=form_check_form('addhost',\%data,\%new_host_form))) {
	if ($data{net} eq 'MANUAL' && not is_cidr($data{ip})) {
	  alert1("IP number must be specified if using Manual IP!");
	} elsif (domain_in_use($zoneid,$data{domain})) {
	  alert1("Domain name already in use!");
	} elsif (is_cidr($data{ip}) && ip_in_use($serverid,$data{ip})) {
	  alert1("IP number already in use!");
	} else {
	  print h2("Add");
	  if ($data{type} == 1) {
	    if ($data{ip} && $data{net} eq 'MANUAL') {
	      $ip=$data{ip};
	      delete $data{ip};
	      $data{ip}=[[$ip,'t','t','']];
	    } else {
	      $ip=auto_address($serverid,$data{net});
	      unless (is_cidr($ip)) { alert1("Cannot get IP: $ip"); return; }
	      $data{ip}=[[$ip,'t','t','']];
	    }
	  } elsif ($data{type} == 6) {
	    $ip=$data{glue}; delete $data{glue};
	    $data{ip}=[[$ip,'t','t','']];
	  }
	  delete $data{net};
	  #show_hash(\%data);
	  $res=add_host(\%data);
	  if ($res > 0) {
	    print h2("Host added successfully");
	    param('h_id',$res);
	    goto show_host_record;
	  }
	  alert1("Cannot add host record!") if ($res < 0);
	}
      } else {
	alert1("Invalid data in form! $res");
      }
    }
    print h2("Add $host_types{$type} record");

    print startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','add'),hidden('type',$type);
    form_magic('addhost',\%data,\%new_host_form);
    print submit(-name=>'addhost_submit',-value=>'Create'), " ",
          submit(-name=>'addhost_cancel',-value=>'Cancel'),end_form;
    return;
  }


  if (param('h_id')) {
  show_host_record:
    $id=param('h_id');
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }

    display_form(\%host,\%host_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id),
          submit(-name=>'sub',-value=>'Edit'), " ",
          submit(-name=>'sub',-value=>'Delete'), " ";
    print submit(-name=>'sub',-value=>'Move'), " " if ($host{type} == 1);
    print submit(-name=>'sub',-value=>'Alias'), " " if ($host{type} == 1);
    print "&nbsp;&nbsp;",submit(-name=>'sub',-value=>'Refresh'), " ",end_form;
    return;
  }


 browse_hosts:
  param('sub','browse');
  make_net_list($serverid,1,\%nethash,\@netkeys);

  %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>1,size=>3);
  if ($state{searchopts} =~ /^(\d+),(\d+),(\d+),(\d+),(\S*),(\S*)$/) {
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

sub make_net_list($$$$) {
  my($id,$flag,$h,$l) = @_;
  my($i,$nets);

  $nets=get_net_list($id,1);
  undef %{$h}; undef @{$l};

  if ($flag > 0) {
    $h->{'ANY'}='<Any net>';
    $$l[0]='ANY';
  }
  for $i (0..$#{$nets}) { 
    next unless ($$nets[$i][2]);
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

  if ($sub eq 'add') {
    $data{server}=$serverid;
    $res=add_magic('add','Group','groups',\%new_group_form,
		   \&add_group,\%data);
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
		    \&get_group,\&update_group,$id);
    goto browse_groups if ($res == -1);
    goto show_group_record if ($res > 0);
    return;		    
  }
  elsif ($sub eq 'Delete') {
    if (get_group($id,\%group)) {
      print h2("Cannot get group (id=$id)");
      return;
    }
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
      get_group_list($serverid,\%lsth,\@lst);
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
          hidden('menu','groups'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'),
          hidden('grp_id',$id),end_form;
    return;
  }

 browse_groups:
  db_query("SELECT id,name,comment FROM groups " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  if (@q < 1) {
    print h2("No groups found!");
    return;
  }

  print "<TABLE width=\"90%\"><TR bgcolor=\"#aaaaff\">",
        th("Name"),th("Comment"),"</TR>";

  for $i (0..$#q) {
    print "<TR bgcolor=\"#eeeebf\">";

    $name=$q[$i][1];
    $name='&nbsp;' if ($name eq '');
    $comment=$q[$i][2];
    $comment='&nbsp;' if ($comment eq '');
    print "<td><a href=\"$selfurl?menu=groups&grp_id=$q[$i][0]\">$name</a></td>",
          td($comment),"</TR>";
  }

  print "</TABLE>";
}


# NETS menu
#
sub nets_menu() {
  my(@q,$i,$id);

  $sub=param('sub');
  $id=param('net_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }

  if ($sub eq 'addnet') {
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
    $data{subnet}='t';
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
  elsif ($sub eq 'Edit') {
    $res=edit_magic('net','Net','nets',\%net_form,\&get_net,\&update_net,$id);
    goto browse_nets if ($res == -1);
    goto show_net_record if ($res > 0);
    return;
  }
  elsif ($sub eq 'Delete') {
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

    db_query("SELECT a.ip FROM a_entries a, hosts h, zones z " .
	     "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	     " AND a.ip << '$net{net}' ORDER BY a.ip;",\@q);
    $net{inuse}=@q;
    for $i (0..$#q) {
      $ip=$q[$i][0]; $ip=~s/\/32$//;
      $netmap{$ip}=1;
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
          "<TR><TH colspan=3 bgcolor=\"#aaaaff\">Net usage map</TH></TR>";
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

 show_net_record:
  if ($id > 0) {
    if (get_net($id,\%net)) {
      print h2("Cannot get net record (id=$id)!");
      return;
    }
    display_form(\%net,\%net_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','nets'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'), " &nbsp;&nbsp;&nbsp; ",
          submit(-name=>'sub',-value=>'Net Info'),
          hidden('net_id',$id),end_form;
    return;
  }

 browse_nets:
  db_query("SELECT id,name,net,subnet,comment FROM nets " .
	   "WHERE server=$serverid ORDER BY subnet,net;",\@q);
  if (@q < 1) {
    print h2("No networks found!");
    return;
  }

  print "<TABLE><TR bgcolor=\"#aaaaff\">",
        "<TH>Net</TH>",th("Name"),th("Type"),th("Comment"),"</TR>";
  
  for $i (0..$#q) {
      if ($q[$i][3] eq 't') {  
	print "<TR bgcolor=\"#eeeebf\">";
	$type='Subnet';
      } else { 
	print "<TR bgcolor=\"#ddffdd\">";
	$type='Network';
      }
				   
    $name=$q[$i][1];
    $name='&nbsp;' if ($name eq '');
    $comment=$q[$i][4];
    $comment='&nbsp;' if ($comment eq '');
    print "<td><a href=\"$selfurl?menu=nets&net_id=$q[$i][0]\">$q[$i][2]</a></td>",
          td($name),td($type),td($comment),"</TR>";
  }
 
  print "</TABLE>";
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

  $sub=param('sub');
  $mx_id=param('mx_id');
  $wks_id=param('wks_id');
  $pc_id=param('pc_id');
  $hinfo_id=param('hinfo_id');

  if ($sub eq 'mx') {
    db_query("SELECT id,name,comment FROM mx_templates " .
	     "WHERE zone=$zoneid ORDER BY name;",\@q);
    if (@q < 1) {
      print h2("No MX templates found for this zone!"); 
      return;
    }

    print h3("MX templates for zone: $zone"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Name"),th("Comment"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][1];
      $name='&nbsp;' if ($name eq '');
      $comment=$q[$i][2];
      $comment='&nbsp;' if ($comment eq '');
      print "<TR bgcolor=\"#eeeebf\">",
	td("<a href=\"$selfurl?menu=templates&mx_id=$q[$i][0]\">$name</a>"),
	td($comment),"</TR>";
    }
    print "</TABLE>";
    return;
  }
  elsif ($sub eq 'wks') {
    db_query("SELECT id,name,comment FROM wks_templates " .
	     "WHERE server=$serverid ORDER BY name;",\@q);
    if (@q < 1) {
      print h2("No WKS templates found for this server!");
      return;
    }

    print h3("WKS templates for server: $server"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Name"),th("Comment"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][1];
      $name='&nbsp;' if ($name eq '');
      $comment=$q[$i][2];
      $comment='&nbsp;' if ($comment eq '');
      print "<TR bgcolor=\"#eeeebf\">",
	td("<a href=\"$selfurl?menu=templates&wks_id=$q[$i][0]\">$name</a>"),
	td($comment),"</TR>";
    }
    print "</TABLE>";
    return;
  }
  elsif ($sub eq 'pc') {
    db_query("SELECT id,name,comment FROM printer_classes " .
	     "ORDER BY name;",\@q);
    if (@q < 1) {
      print h2("No PRINTER classes found!");
      return;
    }

    print h3("PRINTER Classes (global)"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Name"),th("Comment"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][1];
      $name='&nbsp;' if ($name eq '');
      $comment=$q[$i][2];
      $comment='&nbsp;' if ($comment eq '');
      print "<TR bgcolor=\"#eeeebf\">",
	td("<a href=\"$selfurl?menu=templates&pc_id=$q[$i][0]\">$name</a>"),
	td($comment),"</TR>";
    }
    print "</TABLE>";
    return;
  }
  elsif ($sub eq 'hinfo') {
    db_query("SELECT id,type,hinfo,pri FROM hinfo_templates " .
	     "ORDER BY type,pri,hinfo;",\@q);
    if (@q < 1) {
      print h2("No HINFO templates found!");
      return;
    }

    print h3("HINFO templates (global)"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Type"),th("HINFO"),th("Priority"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][2];
      $name='&nbsp;' if ($name eq '');
      print "<TR bgcolor=\"" . ($q[$i][1]==0?"#eeeebf":"#eebfee") . "\">",
	td(($q[$i][1]==0 ? "Hardware" : "Software")),
	td("<a href=\"$selfurl?menu=templates&hinfo_id=$q[$i][0]\">$name</a>"),
	td($q[$i][3]),"</TR>";
    }
    print "</TABLE>";
    return;
  }
  elsif ($sub eq 'Edit') {
    if ($mx_id > 0) {
      $res=edit_magic('mx','MX template','templates',\%mx_template_form,
		      \&get_mx_template,\&update_mx_template,$mx_id);
      goto show_mxt_record if ($res > 0);
    } elsif ($wks_id > 0) {
      $res=edit_magic('wks','WKS template','templates',\%wks_template_form,
		      \&get_wks_template,\&update_wks_template,$wks_id);
      goto show_wkst_record if ($res > 0);
    } elsif ($pc_id > 0) {
      $res=edit_magic('pc','PRINTER class','templates',\%printer_class_form,
		      \&get_printer_class,\&update_printer_class,$pc_id);
      goto show_pc_record if ($res > 0);
    } elsif ($hinfo_id > 0) {
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
	get_mx_template_list($zoneid,\%lsth,\@lst);
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
	get_wks_template_list($serverid,\%lsth,\@lst);
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
      $res=delete_magic('pc','PRINTER class','templates',\%printer_class_form,
			\&get_printer_class,\&delete_printer_class,$pc_id);
      goto show_pc_record if ($res==2);
    }
    elsif ($hinfo_id > 0) {
      $res=delete_magic('hinfo','HINFO template','templates',
			\%hinfo_template_form,\&get_hinfo_template,
			\&delete_hinfo_template,$hinfo_id);
      goto show_hinfo_record if ($res==2);
    }
    else { print p,"Unknown template type!"; }
    return;
  }
  elsif ($sub eq 'addmx') {
    $data{zone}=$zoneid;
    $res=add_magic('addmx','MX template','templates',\%new_template_form,
		   \&add_mx_template,\%data);
    if ($res > 0) {
      $mx_id=$res;
      goto show_mxt_record;
    }
    return;
  }
  elsif ($sub eq 'addwks') {
    $data{server}=$serverid;
    $res=add_magic('addwks','WKS template','templates',\%new_template_form,
		   \&add_wks_template,\%data);
    if ($res > 0) {
      $wks_id=$res;
      goto show_wkst_record;
    }
    return;
  }
  elsif ($sub eq 'addpc') {
    #$data{server}=$serverid;
    $res=add_magic('addwpc','PRINTER class','templates',
		   \%new_printer_class_form,\&add_printer_class,\%data);
    if ($res > 0) {
      $pc_id=$res;
      goto show_pc_record;
    }
    return;
  }
  elsif ($sub eq 'addhinfo') {
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
          hidden('menu','templates'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'),
          hidden('mx_id',$mx_id),end_form;
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
          hidden('menu','templates'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'),
          hidden('wks_id',$wks_id),end_form;
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
          hidden('menu','templates'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'),
          hidden('pc_id',$pc_id),end_form;
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
          hidden('menu','templates'),
          submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'),
          hidden('hinfo_id',$hinfo_id),end_form;
    return;
  }

  print "<p><br><ul>",
    "<li><a href=\"$selfurl?menu=templates&sub=mx\">" .
      "Show MX templates</a></li>",
    "<li><a href=\"$selfurl?menu=templates&sub=wks\">" .
      "Show WKS templates</a></li>",
    "<li><a href=\"$selfurl?menu=templates&sub=pc\">" .
      "Show PRINTER classes</a></li>",
    "<li><a href=\"$selfurl?menu=templates&sub=hinfo\">" .
      "Show HINFO templates</a></li>",
    "</ul>";
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
    if (param('passwd_submit') ne '') {
      unless (($res=form_check_form('passwd',\%h,\%change_passwd_form))) {
	if (param('passwd_new1') ne param('passwd_new2')) {
	  print "<FONT color=\"red\">",h2("New passwords dont match!"),
	        "</FONT>";
	} else {
	  get_user($state{user},\%user);
	  unless (pwd_check(param('passwd_old'),$user{password})) {
	    $password=pwd_make(param('passwd_new1'));
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
    print submit(-name=>'passwd_submit',-value=>'Change password'),
          end_form;
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
      print h3('Defaults saved succesfully!');
    }
  }
  elsif ($sub eq 'who') {
    $timeout=$USER_TIMEOUT;
    unless ($timeout > 0) {
      print h2("error: $USER_TIMEOUT not defined in configuration!");
      return;
    }
    undef @wholist;
    get_who_list(\@wholist,$timeout);
    print h2("Current users:");
    print "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th('User'),th('Name'),th('From'),th('Idle'),th('Login'),"</TR>";
    for $i (0..$#wholist) {
      print "<TR bgcolor=\"#eeeebf\">",	
	td($wholist[$i][0]),td($wholist[$i][1]),td($wholist[$i][2]),
	  td($wholist[$i][3]),td($wholist[$i][4]),"</TR>";
    }
    print "</TABLE>";
  }
  else {
    print h2("User info:");
    display_form(\%state,\%user_info_form);
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
    print "<P><BR><CENTER>",
        "<a href=\"http://sauron.jyu.fi/\" target=\"sauron\">",
        "<IMG src=\"$ICON_PATH/logo_large.png\" border=\"0\" alt=\"Sauron\">",
          "</a><BR>Version $VER<P>",
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
	print "<FONT color=\"red\">",h1("$name record update failed!"),
	      "<br>result code=$res</FONT>";
      } else {
	print h2("$name record succefully updated");
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
	print "<FONT color=\"red\">",h1("Adding $name record failed!"),
	      "<br>result code=$res</FONT>";
      } else {
	print h3("$name record succefully added");
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

  print "<FONT color=\"blue\">";
  print "<CENTER><TABLE width=\"50%\" cellspacing=0 border=0>",
        "<TR bgcolor=\"#0000ff\"><TD> Sauron</TD>",
	"<TD align=\"right\">$host </TD>",
	"<TR><TD colspan=2 bgcolor=\"#dddddd\">";

  print start_form,"<BR><CENTER>",h2($msg),p,"<TABLE>",
        Tr,td("Login:"),td(textfield(-name=>'login_name',-maxlength=>'8')),
        Tr,td("Password:"),
                   td(password_field(-name=>'login_pwd',-maxlength=>'30')),
              "</TABLE>",
        hidden(-name=>'login',-default=>'yes'),
        submit(-name=>'submit',-value=>'Login'),end_form,"</CENTER>";

  print "</TD></TR></TABLE>";

  #print "</TABLE>\n" unless($frame_mode);
  print p,"You should have cookies enabled for this site...",end_html();
  $state{'mode'}='1';
  $state{'auth'}='no';
  save_state($c);
  exit;
}

sub login_auth() {
  my($u,$p);
  my(%user,%h,$ticks);

  $ticks=time();
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
      if (pwd_check($p,$user{'password'}) == 0) {
	$state{'auth'}='yes';
	$state{'user'}=$u;
	$state{'uid'}=$user{'id'};
	$state{'login'}=$ticks;
	$state{'serverid'}=$user{'server'};
	$state{'zoneid'}=$user{'zone'};
	$state{'superuser'}='yes' if ($user{superuser} eq 't');
	if ($state{'serverid'} > 0) {
	  $state{'server'}=$h{'name'} 
	    unless(get_server($state{'serverid'},\%h));
	}
	if ($state{'zoneid'} > 0) {
	  $state{'zone'}=$h{'name'} 
	    unless(get_zone($state{'zoneid'},\%h));
	}
	print p,h1("Login ok!"),p,"<TABLE><TR><TD>",
	    startform(-method=>'POST',-action=>$s_url),
	    submit(-name=>'submit',-value=>'No Frames'),end_form,
	    "</TD><TD> ",
	    startform(-method=>'POST',-action=>"$s_url/frames"),
	    submit(-name=>'submit',-value=>'Frames'),end_form,
	    "</TD></TR></TABLE>";
	logmsg("notice","user ($u) logged in from " . $ENV{'REMOTE_ADDR'});
	db_exec("UPDATE users SET last=$ticks WHERE id=$user{'id'};");
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
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);

  ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

  if ($frame_mode) {
    print '<TABLE border="0" cellspacing="0" width="100%">',
          '<TR bgcolor="#002d5f"><TD rowspan=2>',
          '<a href="http://sauron.jyu.fi/" target="sauron">',
          '<IMG src="' .$ICON_PATH . '/logo.png" widht="80" height="70" border="0" alt=""></a></TD>',
          '<TD colspan=2><FONT size=+2 color="white">Sauron</WHITE></TD></TR>',
	  '<TR bgcolor="#002d5f" align="left" valign="center">',
          '<TD><FONT color="white">';
  } else {
    print '<a href="http://sauron.jyu.fi/" target="sauron">',
      '<IMG src="' .$ICON_PATH . '/logo.png" border="0" alt=""></a>';

    print '<TABLE border="0" cellspacing="0" width="100%">';

    print '<TR bgcolor="#002d5f" align="left" valign="center">',
      '<TD width="15%" height="24">',
      '<FONT color="white">&nbsp;Sauron </FONT></TD>',
      '<TD height="24"><FONT color="white">';
  }
  print
    "<A HREF=\"$s_url?menu=hosts\"><FONT color=\"#ffffff\">",
      "Hosts</FONT></A> | ",
    "<A HREF=\"$s_url?menu=zones\"><FONT color=\"#ffffff\">",
      "Zones</FONT></A> | ",
    "<A HREF=\"$s_url?menu=nets\"><FONT color=\"#ffffff\">",
      "Nets</FONT></A> | ",
    "<A HREF=\"$s_url?menu=templates\"><FONT color=\"#ffffff\">",
      "Templates</FONT></A> | ",
    "<A HREF=\"$s_url?menu=groups\"><FONT color=\"#ffffff\">",
      "Groups</FONT></A> | ",
    "<A HREF=\"$s_url?menu=servers\"><FONT color=\"#ffffff\">",
      "Servers</FONT></A> | ",
    "<A HREF=\"$s_url?menu=login\"><FONT color=\"#ffffff\">",
      "Login</FONT></A> | ",
    "<A HREF=\"$s_url?menu=about\"><FONT color=\"#ffffff\">About</FONT></A> ",
    '</FONT></TD>';

  print  "<TD align=\"right\">";
  if ($frame_mode) { print "&nbsp;"; } 
  else {
    printf "<FONT color=\"#ffffff\">%d.%d.%d %02d:%02d </FONT></TD>",
           $mday,$mon,$year+1900,$hour,$min;
  }
  print "</TR></TABLE>";
}

sub left_menu($) {
  my($mode)=@_;
  my($url,$w);

  $w="\"100\"";

  $url=$s_url;
  print "<TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" " .
        "cellspacing=\"3\" cellpadding=\"0\">", # Tr,th(h4("$menu")),
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " ,
	 "border=\"0\">",
         "<TR><TH><FONT color=\"#ffffff\">$menu</FONT></TH></TR>",
	  "<TR><TD BGCOLOR=\"#eeeeee\"><FONT size=\"-1\">";
  #print "<p>mode=$mode";
  print "<TABLE width=\"100%\" bgcolor=\"#cccccc\" cellspacing=2 border=0>";

  if ($menu eq 'servers') {
    $url.='?menu=servers';
    print Tr(td("<a href=\"$url\">Current</a>")),
          Tr(td("<a href=\"$url&sub=select\">Select</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add\">Add</a>")),
          Tr(td("<a href=\"$url&sub=del\">Delete</a>")),
          Tr(td("<a href=\"$url&sub=edit\">Edit</a>"));
  } elsif ($menu eq 'zones') {
    $url.='?menu=zones';
    print Tr(td("<a href=\"$url\">Current</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=select\">Select</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add\">Add</a>")),
          Tr(td("<a href=\"$url&sub=Copy\">Copy</a>")),
          Tr(td("<a href=\"$url&sub=Delete\">Delete</a>")),
          Tr(td("<a href=\"$url&sub=Edit\">Edit</a>"));
  } elsif ($menu eq 'nets') {
    $url.='?menu=nets';
    print Tr(td("<a href=\"$url\">Networks</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=addnet\">Add net</a>")),
          Tr(td("<a href=\"$url&sub=addsub\">Add subnet</a>"));
  } elsif ($menu eq 'templates') {
    $url.='?menu=templates';
    print Tr(td("<a href=\"$url&sub=mx\">Show MX</a>")),
          Tr(td("<a href=\"$url&sub=wks\">Show WKS</a><br>")),
          Tr(td("<a href=\"$url&sub=pc\">Show Prn Class</a><br>")),
          Tr(td("<a href=\"$url&sub=hinfo\">Show HINFO</a><br>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=addmx\">Add MX</a>")),
          Tr(td("<a href=\"$url&sub=addwks\">Add WKS</a>")),
          Tr(td("<a href=\"$url&sub=addpc\">Add Prn Class</a>")),
          Tr(td("<a href=\"$url&sub=addhinfo\">Add HINFO</a>"));
  } elsif ($menu eq 'groups') {
    $url.='?menu=groups';
    print Tr(td("<a href=\"$url\">Groups</a>")),
          Tr(),Tr(td("<a href=\"$url&sub=add\">Add</a>"));
  } elsif ($menu eq 'hosts') {
    $url.='?menu=hosts';
    print Tr(td("<a href=\"$url\">Search</a>")),
          Tr(td("<a href=\"$url&sub=browse&lastsearch=1\">Last Search</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add&type=1\">Add host</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add&type=4\">Add alias</a>")),
	  Tr(td("<a href=\"$url&sub=add&type=3\">Add MX entry</a>")),
          Tr(td("<a href=\"$url&sub=add&type=2\">Add delegation</a>")),
          Tr(td("<a href=\"$url&sub=add&type=6\">Add glue rec.</a>")),
          Tr(td("<a href=\"$url&sub=add&type=5\">Add printer</a>"));
  } elsif ($menu eq 'login') {
    $url.='?menu=login';
    print Tr(td("<a href=\"$url&sub=login\">Login</a>")),
          Tr(td("<a href=\"$url&sub=logout\">Logout</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=who\">Who</a>")),
          Tr(td("<a href=\"$url\">User info</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=passwd\">Change password</a>")),
          Tr(td("<a href=\"$url&sub=save\">Save defaults</a>"));
    if ($frame_mode) {
      print Tr(td("<a href=\"$script_name\" target=\"_top\">Frames OFF</a>"));
    } else {
      print Tr(td("<a href=\"$s_url/frames\" target=\"_top\">Frames ON</a>"));
    }
  } elsif ($menu eq 'about') {
    $url.='?menu=about';
    print Tr(td("<a href=\"$url\">About</a>")),
          Tr(td("<a href=\"$url&sub=copyright\">Copyright</a>")),
          Tr(td("<a href=\"$url&sub=copying\">License</a>"));
  } else {
    print "<p><p>empty menu\n";
  }
  print "</TABLE>";
  print "</FONT></TR></TABLE></TD></TABLE><BR>";

  print "<TABLE width=$w bgcolor=\"#002d5f\" border=\"0\" cellspacing=\"3\" " .
        "cellpadding=\"0\">", #<TR><TD><H4>Current selections</H4></TD></TR>",
        "<TR><TD><TABLE width=\"100%\" cellspacing=\"2\" cellpadding=\"1\" " .
	"border=\"0\">",
	"<TR><TH><FONT color=white size=-1>Current selections</FONT></TH></TR>",
	"<TR><TD BGCOLOR=\"#eeeeee\">";

  print "<FONT size=-1>",
        "Server: $server",br,
        "Zone: $zone",br,
        "</FONT>";

  print "</FONT></TABLE></TD></TR></TABLE><BR>";

}

sub frame_set() {
  print header;

  print "<HTML><FRAMESET border=\"0\" rows=\"90,*\" >\n" .
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
        "<FRAMESET border=\"0\" cols=\"17%,*\">\n" .
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
  return cookie(-name=>'sauron',-expires=>'+7d',-value=>$val,-path=>$s_url);
}

sub save_state($id) {
  my($id)=@_;
  my(@q,$res,$s_auth,$s_addr,$other,$s_mode);

  undef @q;
  db_query("SELECT uid FROM utmp WHERE cookie='$id';",\@q);
  unless (@q > 0) {
    db_exec("INSERT INTO utmp (uid,cookie,auth) VALUES(-1,'$id',false);");
  }

  $s_superuser = ($state{'superuser'} eq 'yes' ? 'true' : 'false');
  $s_auth=($state{'auth'} eq 'yes' ? 'true' : 'false');
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

  $other.=", searchopts=". db_encode_str($state{'searchopts'}) . " ";
  $other.=", searchdomain=". db_encode_str($state{'searchdomain'}) . " ";
  $other.=", searchpattern=". db_encode_str($state{'searchpattern'}) . " ";

  $res=db_exec("UPDATE utmp SET auth=$s_auth, addr='$s_addr', mode=$s_mode " .
	       ", superuser=$s_superuser $other " .
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
       "uname,last,login,searchopts,searchdomain,searchpattern,superuser " .
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
    $state{'login'}=$q[0][10];
    $state{'searchopts'}=$q[0][11];
    $state{'searchdomain'}=$q[0][12];
    $state{'searchpattern'}=$q[0][13];
    $state{'superuser'}='yes' if ($q[0][14] eq 't');

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
      $a=param($p."_count");
      $a=0 if (!$a || $a < 0);
      for $j (1..$a) {
	next if ($type==8);
	next if (param($p."_".$j."_del") eq 'on'); # skip if 'delete' checked
	for $k (1..$f) {
	  return 2 
	    if (form_check_field($rec,param($p."_".$j."_".$k),$k) ne '');
	}
	if ($type==5) {
	  param($p."_".$j."_2",(param($p."_".$j."_2") eq 'on' ? 't':'f'));
	  param($p."_".$j."_3",(param($p."_".$j."_3") eq 'on' ? 't':'f'));
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
	print "<TR>",hidden(-name=>$p2."_id",param($p2."_id"));

	$n=$p2."_1";
	print "<TD>",textfield(-name=>$n,-size=>15,-value=>param($n));
        print "<FONT size=-1 color=\"red\"><BR>",
              form_check_field($rec,param($n),1),"</FONT></TD>";
	$n=$p2."_2";
	print td(checkbox(-label=>' A',-name=>$n,-checked=>param($n)));
	$n=$p2."_3";
	print td(checkbox(-label=>' PTR',-name=>$n,-checked=>param($n)));

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
      param($p1."_l",$lst[0]) if (($lst[0] ne '') && (not param($p1."_l")));

      if ($lsth{param($p1)}) {
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
      print Tr,td($rec->{name}),
	"<TD><TABLE width=\"100%\" bgcolor=\"#e0e0e0\">",Tr;
      $a=$data->{$rec->{tag}};
      for $k (1..$rec->{fields}) { 
	#print "<TH>",$$a[0][$k-1],"</TH>";
      }
      for $j (1..$#{$a}) {
	print Tr;
	for $k (1..$rec->{fields}) {
	  $val=$$a[$j][$k];
	  $val =~ s/\/32$// if ($rec->{type}[$k-1] eq 'ip');
	  $val='&nbsp;' if ($val eq '');
	  print td($val);
	}
      }
      print "</TABLE></TD>\n";
    } elsif ($rec->{ftype} == 3) {
      print Tr,"<TD WIDTH=\"",$form->{nwidth},"\">",$rec->{name},"</TD><TD>",
            "$val</TD>\n";
    } elsif ($rec->{ftype} == 4) {
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
      print "<TR>",td($rec->{name}),"<TD><TABLE><TR>";
      $a=$data->{$rec->{tag}};
      $url=$form->{$rec->{tag}."_url"};
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

  print header,start_html("sauron: error"),h1("Error: $msg"),end_html();
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

