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

$SAURON_CGI_VER = ' $Revision$ $Date$ ';

$PLEVEL_VLANS = 5 unless (defined($PLEVEL_VLANS));
#$|=1;
$debug_mode = 0;

if (-f "/etc/sauron/config") {
  $conf_dir='/etc/sauron';
}
elsif (-f "/usr/local/etc/sauron/config") {
  $conf_dir='/usr/local/etc/sauron';
}
else {
  die("cannot find configuration file!");
}

do "$conf_dir/config" || die("cannot load configuration!");

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";
do "$PROG_DIR/cgi_util.pl";

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
   fields=>2, len=>[35,20], empty=>[0,1],elabels=>['dhcptab line','comment']},

  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
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
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'domain', len=>50},
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
   name=>'[Stealth] Servers to notify (also-notify)', type=>['ip','text'],
   fields=>2, len=>[40,15], empty=>[0,1], elabels=>['IP','comment'],
   iff=>['type','M']},

  {ftype=>0, name=>'DHCP', iff=>['type','M']},
  {ftype=>2, tag=>'dhcp', name=>'Zone specific DHCP entries',
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment'], iff=>['type','M']},

  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>4, name=>'Pending host record changes', tag=>'pending_info', 
   no_edit=>1, iff=>['type','M']}
 ]
);



%host_types=(0=>'Any type',1=>'Host',2=>'Delegation',3=>'Plain MX',
	     4=>'Alias',5=>'Printer',6=>'Glue record',7=>'AREC Alias',
	     8=>'SRV record',9=>'DHCP only');

%host_form = (
 data=>[
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain',
   conv=>'L', len=>40},
  {ftype=>5, tag=>'ip', name=>'IP address', iff=>['type','[169]']},
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
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50, 
   empty=>1, iff=>['type','1']},
  {ftype=>0, name=>'Equipment info', iff=>['type','1']},
#  {ftype=>1, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
#   empty=>1, iff=>['type','1']},
#  {ftype=>1, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo', len=>25,
#   empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], empty=>1},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer', 
   iff=>['type','[19]']},
  {ftype=>1, tag=>'ether_alias_info', name=>'Ethernet alias', no_empty=>1,
   empty=>1, type=>'domain', len=>30, iff=>['type','1'] },

  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>40, empty=>1, 
   no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>30,
   empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   no_empty=>1, iff=>['type','1']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','[13]']},
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
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']},
  {ftype=>4, name=>'Last seen by DHCP server', tag=>'dhcp_date_str', 
   no_edit=>1, iff=>['type','[19]']}
 ]
);


%restricted_host_form = (
 data=>[
  {ftype=>0, name=>'Host (restricted edit)' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', 
   conv=>'L', len=>40},
  {ftype=>5, tag=>'ip', name=>'IP address', restricted=>1,
   iff=>['type','[169]']},
  {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
   len=>60, iff=>['type','4'], iff2=>['alias','-1']},
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50, 
   empty=>1, iff=>['type','1']},
  {ftype=>0, name=>'Equipment info', iff=>['type','1']},
#  {ftype=>1, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
#   empty=>1, iff=>['type','1']},
#  {ftype=>1, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo', len=>20,
#   empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], iff2=>['ether_alias_info',''], empty=>0},
  {ftype=>4, tag=>'ether_alias_info', name=>'Ethernet alias', 
   iff=>['type','1']}, 

  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>30,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']},
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
  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>1,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], empty=>1},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>30, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
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
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>25, empty=>0,
   iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>25,
   empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50, 
   empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   lastempty=>0, empty=>0, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO sowftware', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   lastempty=>0, empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], empty=>0},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>30, empty=>1, 
   iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>20,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>40, empty=>1, 
   iff=>['type','1']},
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
  {ftype=>4, tag=>'user', name=>'Login'},
  {ftype=>4, tag=>'name', name=>'User Name'},
  {ftype=>4, tag=>'email', name=>'Email'},
  {ftype=>4, tag=>'groupname', name=>'Group'},
  {ftype=>4, tag=>'login', name=>'Last login', type=>'localtime'},
  {ftype=>4, tag=>'addr', name=>'Host'},
  {ftype=>4, tag=>'superuser', name=>'Superuser', iff=>['superuser','yes']},
  {ftype=>0, name=>'Current selections'},
  {ftype=>4, tag=>'server', name=>'Server'},
  {ftype=>4, tag=>'zone', name=>'Zone'},
  {ftype=>4, tag=>'sid', name=>'Session ID (SID)'}
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
  {ftype=>1, tag=>'plevel', name=>'Privilege level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>3, tag=>'vlan', name=>'VLAN', type=>'enum', conv=>'L',
   enum=>\%vlan_list_hash, restricted=>1},
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
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment']},

  {ftype=>0, name=>'Record info', no_edit=>0},
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
  {ftype=>4, tag=>'id', name=>'ID', no_edit=>1},
  {ftype=>1, tag=>'description', name=>'Description', type=>'text',
   len=>60, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text',
   len=>60, empty=>1},

  {ftype=>0, name=>'Record info', no_edit=>0},
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
  {ftype=>1, tag=>'plevel', name=>'Privilege level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1},
  {ftype=>2, tag=>'dhcp', name=>'DHCP entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['DHCP','comment']},
  {ftype=>2, tag=>'printer', name=>'PRINTER entries', 
   type=>['text','text'], fields=>2,
   len=>[40,20], empty=>[0,1], elabels=>['PRINTER','comment']},
  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%new_group_form=(
 data=>[
  {ftype=>0, name=>'New Group'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',
   len=>40, empty=>0},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum',enum=>\%group_type_hash},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
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


%mx_template_form=(
 data=>[
  {ftype=>0, name=>'MX template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'plevel', name=>'Privilege level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', 
   type=>['priority','mx','text'], fields=>3, len=>[5,30,20], 
   empty=>[0,0,1],elabels=>['Priority','MX','comment']},
  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

%wks_template_form=(
 data=>[
  {ftype=>0, name=>'WKS template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'plevel', name=>'Privilege level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,1,1], 
   elabels=>['Protocol','Services','comment']},
  {ftype=>0, name=>'Record info', no_edit=>0},
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
  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
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
  {ftype=>0, name=>'Record info', no_edit=>0},
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

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();
$s_url = script_name();
$selfurl = $s_url . $pathinfo;
$menu=param('menu');
#$menu='login' unless ($menu);
$remote_addr = $ENV{'REMOTE_ADDR'};
$remote_host = remote_host();

$scookie = cookie(-name=>"sauron-$SERVER_ID");
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
  update_lastlog($state{uid},$state{sid},4,$remote_addr,$remote_host);
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Welcome (again)",$scookie);
}

if ((time() - $state{'last'}) > $USER_TIMEOUT) {
  logmsg("notice","connection timed out for $remote_addr " .
	 $state{'user'});
  update_lastlog($state{uid},$state{sid},3,$remote_addr,$remote_host);
  print header(-target=>'_top'),
        start_html(-title=>"Sauron Login",-BGCOLOR=>'white');
  login_form("Your session timed out. Login again",$scookie);
}

if ($remote_addr ne $state{'addr'}) {
  logmsg("notice",
	 "cookie reseived from wrong host: " . $remote_addr .
	 " ($state{user})");
  error("Unauthorized Access denied!");
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
  error("cannot get permissions!")
    if (get_permissions($state{uid},$state{gid},\%perms));
} else {
  $perms{plevel}=999 if ($state{superuser});
}

if (param('csv')) {
  print header(-type=>'text/csv',-target=>'_new');
  hosts_menu();
  exit(0);
}

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

  goto select_server if ($serverid && check_perms('server','R'));

  if ($sub eq 'add') {
    return if (check_perms('superuser',''));

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
    goto select_server if(check_perms('server','R'));
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
  return if (check_perms('server','R'));

  if ($sub eq 'add') {
    return if (check_perms('superuser',''));

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
    goto display_zone if ($res == 2);
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
	$|=1 if ($frame_mode);
	print p,"Copying zone...please wait few minutes (or hours :)";
	$res=copy_zone($zoneid,$serverid,$data{name},1);
	if ($res < 0) {
	  print '<FONT color="red">',h2('Zone copy failed (result=$res!'),
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
    print h2("Pending changes to host records:");

    undef @q;
    db_query("SELECT h.id,h.domain,h.cdate,h.mdate,h.cuser,h.muser " .
	     "FROM hosts h, zones z " .
	     "WHERE z.id=$zoneid AND h.zone=z.id " .
	     " AND (h.mdate > z.serial_date OR h.cdate > z.serial_date) " .
	     "ORDER BY h.domain LIMIT 100;",\@q);
    print "<TABLE width=\"98%\" bgcolor=\"#eeeebf\" cellspacing=1 border=0>",
          "<TR bgcolor=\"#aaaaff\">",th("#"),th("Hostname"),
	  "<TH>Action</TH><TH>Date</TH><TH>By</TH></TR>";
    for $i (0..$#q) {
      $action=($q[$i][2] > $q[$i][3] ? 'Create' : 'Modify');
      $date=localtime(($action eq 'Create' ? $q[$i][2] : $q[$i][3]));
      $user=($action eq 'Create' ? $q[$i][4] : $q[$i][5]);
      print "<TR>",td($i."."),
	    td("<a href=\"$selfurl?menu=hosts&h_id=$q[$i][0]\">$q[$i][1]</a>"),
	    td($action),td($date),td($user),"</TR>";
    }
    print "</TABLE>";
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
  print h2("Select zone:"),p,"<TABLE width=98% bgcolor=white border=0>",
        "<TR bgcolor=\"#aaaaff\">",th(['Zone','Type','Reverse','Comments']);

  $list=get_zone_list($serverid);
  for $i (0 .. $#{$list}) {
    $type=$$list[$i][2];
    if ($type eq 'M') { $type='Master'; $color='#f0f000'; }
    elsif ($type eq 'S') { $type='Slave'; $color='#eeeebf'; }
    $rev=($$list[$i][3] eq 't' ? 'Yes' : 'No');
    $id=$$list[$i][1];
    $name=$$list[$i][0];
    $comment=$$list[$i][4].'&nbsp;';
    print "<TR bgcolor=$color>",td([
	"<a href=\"$selfurl?menu=zones&selected_zone=$name\">$name</a>",
				    $type,$rev,$comment]);
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
  return if (check_perms('server','R'));

  $sub=param('sub');
  $host_form{alias_l_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_a_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_d_url}="$selfurl?menu=hosts&h_id=";
  $host_form{plevel}=$restricted_host_form{plevel}=$perms{plevel};
  $new_host_form{plevel}=$restricted_new_host_form{plevel}=$perms{plevel};

  if ($sub eq 'Delete') {
    if (get_host(param('h_id'),\%host)) {
	alert2("Cannot get host record (id=$id)!");
	return;
    }
    goto show_host_record if (check_perms('host',$host{domain}));

    $res=delete_magic('h','Host','hosts',\%host_form,\&get_host,\&delete_host,
		      param('h_id'));
    goto show_host_record if ($res == 2);
    if ($res==1) {
      update_history($state{uid},$state{sid},1,
		    "DELETE: $host_types{$host{type}} ",
		    "domain: $host{domain}",$host{id});
    }
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
    $id=param('h_id');
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }
    goto show_host_record if (check_perms('host',$host{domain}));

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
	} elsif (check_perms('ip',param('new_ip'),1)) {
	  alert1('Invalid IP number: outside allowed range(s)');
	} else {
	  $old_ip=$host{ip}[1][1];
	  $host{ip}[1][1]=param('new_ip');
	  $host{ip}[1][4]=1;
	  $host{location}=param('new_loc') 
	    unless (param('new_loc') =~ /^\s*$/);
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
      $newloc=$host{location};
      print p,startform(-method=>'GET',-action=>$selfurl),
            hidden('menu','hosts'),hidden('h_id',$id),hidden('sub','Move'),
            hidden('move_confirm'),hidden('move_net'),p,
	    "<TABLE><TR><TD>New IP:</TD>",
            td(textfield(-name=>'new_ip',-maxlength=>15,-default=>$newip)),
            "<TD>",submit(-name=>'move_confirm2',-value=>'Update'), " ",
            submit(-name=>'move_cancel',-value=>'Cancel'), "</TD></TR>",
	    "<TR><TD>New Location:</TD>",
	    td(textfield(-name=>'new_loc',-maxlength=>15,-default=>$newloc)),
	    td(),"</TR></TABLE>",end_form;
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
    $id=param('h_id');
    if (get_host($id,\%host)) {
	alert2("Cannot get host record (id=$id)!");
	return;
    }
    goto show_host_record if (check_perms('host',$host{domain}));
    $hform=(check_perms('zone','RWX',1) ? \%restricted_host_form :\%host_form);

    if (param('h_cancel')) {
      print h2("No changes made to host record.");
      goto show_host_record;
    }

    if (param('h_submit')) {
      for $i (1..$#{$host{ip}}) { $old_ips[$i]=$host{ip}[$i][1]; }

      unless (($res=form_check_form('h',\%host,$hform))) {
	if (check_perms('host',$host{domain},1)) {
	  alert2("Invalid hostname: does not conform to your restrictions");
	} else {
	  $update_ok=1;

	  if ($host{type}==1) {
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
	    $res=update_host(\%host);
	    if ($res < 0) {
	      alert1("Host record update failed! ($res)");
	      alert2(db_lasterrormsg());
	    } else {
	      update_history($state{uid},$state{sid},1,
			    "EDIT: $host_types{$host{type}} ",
			   "domain: $host{domain}",$host{id});
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
  elsif ($sub eq 'Show Network Settings') {
    $id=param('h_id');
    if (get_host($id,\%host)) {
	alert2("Cannot get host record (id=$id)!");
	return;
    }
    get_host_network_settings($serverid,$host{ip}[1][1],\%data);
    print "Current network settings for: $host{domain}<p>";
    display_form(\%data,\%host_net_info_form);
    print "<br><hr noshade><br>";
    goto show_host_record;
  }
  elsif ($sub eq 'browse') {
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
      if ($state{searchopts} =~ /^(\d+),(\d+),(\d+),(\d+),(\S*),(\S*)$/) {
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
      $tmp=$browse_search_f[param('bh_stype')];
      $tmp2=param('bh_pattern');
      if ($tmp eq 'ether') {
	$tmp2 = "\U$tmp2";
	$tmp2 =~ s/[^0-9A-F]//g;
	#print "<br>ether=$tmp2";
      }
      if ($tmp) {
	$extrarule=" AND a.$tmp LIKE " .
	           db_encode_str('%' . $tmp2 . '%') . " ";
	#print p,$extrarule;
      }
    }

    undef @q;
    $fields="a.id,a.type,a.domain,a.ether,a.info,a.huser,a.dept,a.location";
    $fields.=",a.cdate,a.mdate,a.dhcp_date" if (param('csv'));
            
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
      $csv_format =
	  '"%s","%s","%s","%s","%s","%s","%s","%s","%s","%s","%s"'."\n";
      printf $csv_format,'Domain','Type','IP','Ether','User','Dept.',
	                 'Location','Info','cdate','edate','dhcpdate';
      for $i (0..$#q) {
	printf $csv_format,$q[$i][4],$host_types{$q[$i][3]},$q[$i][0],
	                   $q[$i][5],$q[$i][7],$q[$i][8],$q[$i][9],
			   $q[$i][6],$q[$i][10],$q[$i][11],$q[$i][12];
      }
      return;
    }

    if ($count == 1) {
      param('h_id',$q[0][2]);
      goto show_host_record;
    }

    print "<TABLE width=\"99%\" cellspacing=0 cellpadding=1 border=0 " .
          "BGCOLOR=\"aaaaff\">",
          "<TR><TD><B>Zone:</B> $zone</TD>",
          "<TD align=right>Page: ".($page+1)."</TD></TR></TABLE>";

    $sorturl="$selfurl?menu=hosts&sub=browse&lastsearch=1";
    print 
      "<TABLE width=\"99%\" cellspacing=0 cellpadding=1 BGCOLOR=\"#eeeeff\">",
      Tr,Tr,
      "<TR bgcolor=#aaaaff>",
      th(['#',
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
      $ether='N/A' unless($ether);
      #$hostname=add_origin($q[$i][4],$zone);
      $hostname="<A HREF=\"$selfurl?menu=hosts&h_id=$q[$i][2]\">".
	        "$q[$i][4]</A>";
      $info=$q[$i][6];
      if ($q[$i][7]) { 	$info.=", " if($info); 	$info.=$q[$i][7]; }
      if ($q[$i][8]) { 	$info.=", " if($info); 	$info.=$q[$i][8]; }
      if ($q[$i][9]) { 	$info.=", " if($info); 	$info.=$q[$i][9]; }

      $trcolor='#eeeeee';
      $trcolor='#ffffcc' if ($i % 2 == 0);
      print "<TR bgcolor=\"$trcolor\">",
	    "<TD><FONT size=-1>".($i+1).".</FONT></TD>",
	    td([$hostname,"<FONT size=-1>$host_types{$q[$i][3]}</FONT>",$ip,
	       "<PRE>$ether&nbsp;</PRE>",
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
          "<div align=right><font size=-1>",
          "<a name=\"foo.csv\" href=\"$sorturl&csv=1\">Download results in CSV format</a>",
          " &nbsp;</font></div>";
    return;
  }
  elsif ($sub eq 'add') {
    return if (check_perms('zone','RW'));
    $type=param('type');
    return if (($type!=1) && check_perms('zone','RWX'));
    $newhostform = (check_perms('zone','RWX',1) ? \%restricted_new_host_form :
		    \%new_host_form);
    unless ($host_types{$type}) {
      alert2('Invalid add type!');
      return;
    }
    if ($type == 1) {
      make_net_list($serverid,0,\%new_host_nets,\@new_host_netsl,1);
      $new_host_nets{MANUAL}='<Manual IP>';
      push @new_host_netsl, 'MANUAL';
      $data{net}='MANUAL';
      $data{net}=$new_host_netsl[0] if ($new_host_netsl[0]);
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
      unless (($res=form_check_form('addhost',\%data,$newhostform))) {
	if ($data{net} eq 'MANUAL' && not is_cidr($data{ip})) {
	  alert1("IP number must be specified if using Manual IP!");
	} elsif (domain_in_use($zoneid,$data{domain})) {
	  alert1("Domain name already in use!");
	} elsif (is_cidr($data{ip}) && ip_in_use($serverid,$data{ip})) {
	  alert1("IP number already in use!");
	} elsif (check_perms('host',$data{domain},1)) {
	  alert1("Invalid hostname: does not conform your restrictions");
	} elsif (is_cidr($data{ip}) && check_perms('ip',$data{ip},1)) {
	  alert1("Invalid IP number: outside allowed range(s)");
	} else {
	  print h2("Add");
	  if ($data{type} == 1) {
	    if ($data{ip} && $data{net} eq 'MANUAL') {
	      $ip=$data{ip};
	      delete $data{ip};
	      $data{ip}=[[$ip,'t','t','']];
	    } else {
	      $tmpnet=new Net::Netmask($data{net});
	      $ip=auto_address($serverid,$tmpnet->desc());
	      unless (is_cidr($ip)) { 
		logmsg("notice","auto_address($serverid,$data{net}) failed!");
		alert1("Cannot get IP: $ip");
		return;
	      }
	      $data{ip}=[[$ip,'t','t','']];
	    }
	  } elsif ($data{type} == 6) {
	    $ip=$data{glue}; delete $data{glue};
	    $data{ip}=[[$ip,'t','t','']];
	  } elsif ($data{type} == 9) {
	    $ip=$data{ip}; delete $data{ip};
	    $data{ip}=[[$ip,'f','f','']];
	  }
	  delete $data{net};
	  #show_hash(\%data);
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
	      alert2("Duplicate Ethernet (MAC) address");
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
    form_magic('addhost',\%data,$newhostform);
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
          hidden('menu','hosts'),hidden('h_id',$id);
    unless (check_perms('zone','RW',1)) {
      print submit(-name=>'sub',-value=>'Edit'), " ",
            submit(-name=>'sub',-value=>'Delete'), " ";
      print submit(-name=>'sub',-value=>'Move'), " " if ($host{type} == 1);
      print submit(-name=>'sub',-value=>'Alias'), " " if ($host{type} == 1);
    }
    print "&nbsp;&nbsp;",submit(-name=>'sub',-value=>'Refresh'), " ",
           "&nbsp;&nbsp; <FONT size=-1>",
	   submit(-name=>'sub',-value=>'Show Network Settings'),
	   "</FONT>",end_form;
    return;
  }


 browse_hosts:
  param('sub','browse');
  make_net_list($serverid,1,\%nethash,\@netkeys,0);

  %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>0,size=>3);
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
    return if (check_perms('superuser',''));

    $data{type}=1;
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
    return if (check_perms('superuser',''));
    $res=edit_magic('grp','Group','groups',\%group_form,
		    \&get_group,\&update_group,$id);
    goto browse_groups if ($res == -1);
    goto show_group_record if ($res > 0);
    return;		    
  }
  elsif ($sub eq 'Delete') {
    return if (check_perms('superuser',''));
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
      get_group_list($serverid,\%lsth,\@lst,$perms{plevel});
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
	    unless (check_perms('superuser','',1));
    print hidden('grp_id',$id),end_form;
    return;
  }

 browse_groups:
  db_query("SELECT id,name,comment,type,plevel FROM groups " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  if (@q < 1) {
    print h2("No groups found!");
    return;
  }

  print "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
        th("Name"),th("Type"),th("Comment"),th("Lvl"),"</TR>";

  for $i (0..$#q) {
    print "<TR bgcolor=\"#eeeebf\">";

    $name=$q[$i][1];
    $name='&nbsp;' if ($name eq '');
    $comment=$q[$i][2];
    $comment='&nbsp;' if ($comment eq '');
    print "<td><a href=\"$selfurl?menu=groups&grp_id=$q[$i][0]\">$name</a>",
          "</td>",td($group_type_hash{$q[$i][3]}),
          td($comment),td($q[$i][4].'&nbsp;'),"</TR>";
  }

  print "</TABLE>";
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
      return if (check_perms('level',$PLEVEL_VLANS));

      if (get_vlan($v_id,\%vlan)) {
	  alert2("Cannot get vlan record (id=$v_id)");
	  return;
      }

      if ($sub eq 'Edit') {
	  return if (check_perms('superuser',''));
	  $res=edit_magic('vlan','VLAN','vlans',\%vlan_form,
			  \&get_vlan,\&update_vlan,$v_id);
	  goto browse_vlans if ($res == -1);
	  return unless ($res > 0);
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
      return if (check_perms('level',$PLEVEL_VLANS));
      undef @q;
      db_query("SELECT id,name,description,comment FROM vlans " .
	       "WHERE server=$serverid ORDER BY name;",\@q);
      print h3("VLANs");
      print "<TABLE cellspacing=2 border=0><TR bgcolor=\"#aaaaff\">",
            "<TH>Name</TH>",th("Description"),th("Comments"),"</TR>";
      for $i (0..$#q) {
	  print "<TR bgcolor=\"#eeeeee\">",
                td("<a href=\"$selfurl?menu=nets&vlan_id=$q[$i][0]\">".
                   "$q[$i][1]</a>"),
	        td($q[$i][2].'&nbsp;'),
	        td($q[$i][3].'&nbsp;'), "</TR>";
      }
      print "</TABLE>";
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
    get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list);
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

 show_net_record:
  if ($id > 0) {
    if (get_net($id,\%net)) {
      print h2("Cannot get net record (id=$id)!");
      return;
    }
    if (check_perms('level',$PLEVEL_VLANS,1)) {
	$net_form{mode}=0;
    } else {
	get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list);
    }
    display_form(\%net,\%net_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','nets');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete'), " &nbsp;&nbsp;&nbsp; "
	    unless (check_perms('superuser','',1));
    print submit(-name=>'sub',-value=>'Net Info'),
          hidden('net_id',$id),end_form;
    return;
  }

 browse_nets:
  db_query("SELECT id,name,net,subnet,comment,no_dhcp,vlan,netname,plevel " .
	   "FROM nets " .
	   "WHERE server=$serverid AND plevel <= $perms{plevel} " .
	   "ORDER BY subnet,net;",\@q);
  if (@q < 1) {
    print h2("No networks found!");
    return;
  }
  if (check_perms('level',$PLEVEL_VLANS,1)) {
    $novlans=1;
  } else {
    get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list);
    $novlans=0;
  }

  print "<TABLE cellspacing=2 border=0><TR bgcolor=\"#aaaaff\">",
        "<TH>Net</TH>",th("NetName"),th("Description"),th("Type"),
        th("DHCP"),($novlans?'':th("VLAN")),th("Comments"),th("Lvl"),"</TR>";

  for $i (0..$#q) {
      $dhcp=($q[$i][5] eq 't' ? 'No' : 'Yes' );
      if ($q[$i][3] eq 't') {
	print ($dhcp eq 'Yes' ? "<TR bgcolor=\"#eeeebf\">" :
	       "<TR bgcolor=\"#eeeeee\">");
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
	  td("<FONT size=-1>$comment</FONT>"), td($q[$i][8].'&nbsp;'),"</TR>";
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
    db_query("SELECT id,name,comment,plevel FROM mx_templates " .
	     "WHERE zone=$zoneid ORDER BY name;",\@q);
    if (@q < 1) {
      print h2("No MX templates found for this zone!"); 
      return;
    }

    print h3("MX templates for zone: $zone"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Name"),th("Comment"),th("Lvl"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][1];
      $name='&nbsp;' if ($name eq '');
      $comment=$q[$i][2];
      $comment='&nbsp;' if ($comment eq '');
      print "<TR bgcolor=\"#eeeebf\">",
	td("<a href=\"$selfurl?menu=templates&mx_id=$q[$i][0]\">$name</a>"),
	td($comment),td($q[$i][3].'&nbsp;'),"</TR>";
    }
    print "</TABLE>";
    return;
  }
  elsif ($sub eq 'wks') {
    db_query("SELECT id,name,comment,plevel FROM wks_templates " .
	     "WHERE server=$serverid ORDER BY name;",\@q);
    if (@q < 1) {
      print h2("No WKS templates found for this server!");
      return;
    }

    print h3("WKS templates for server: $server"),
          "<TABLE width=\"100%\"><TR bgcolor=\"#aaaaff\">",
          th("Name"),th("Comment"),th("Lvl"),"</TR>";

    for $i (0..$#q) {
      $name=$q[$i][1];
      $name='&nbsp;' if ($name eq '');
      $comment=$q[$i][2];
      $comment='&nbsp;' if ($comment eq '');
      print "<TR bgcolor=\"#eeeebf\">",
	td("<a href=\"$selfurl?menu=templates&wks_id=$q[$i][0]\">$name</a>"),
	td($comment),td($q[$i][3].'&nbsp;'),"</TR>";
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
    return if (check_perms('superuser',''));

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
    return if (check_perms('superuser',''));

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
	get_mx_template_list($zoneid,\%lsth,\@lst,$perms{plevel});
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
	get_wks_template_list($serverid,\%lsth,\@lst,$perms{plevel});
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
    return if (check_perms('superuser',''));
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
    return if (check_perms('superuser',''));
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
    return if (check_perms('superuser',''));
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
	    unless (check_perms('superuser','',1));
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
  
  if (get_user($state{user},\%user) < 0) {
      fatal("Cannot get user record!");
  };

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
  elsif ($sub eq 'lastlog') {
    return if (check_perms('superuser',''));
    $count=get_lastlog(20,'',\@lastlog);
    print h2("Lastlog:");
    print "<TABLE bgcolor=\"#eeeebf\" width=\"100%\">",
          "<TR bgcolor=\"aaaaff\">",th("User"),th("SID"),th("Host"),
	    th("Login"),th("Logout (session length)"),"</TR>";
    for $i (0..($count-1)) {
      print Tr(td($lastlog[$i][0]),td($lastlog[$i][1]),td($lastlog[$i][2]),
	       td($lastlog[$i][3]),td($lastlog[$i][4]));
    }
    print "</TABLE>\n";
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
	print "<TABLE bgcolor=\"#eeeebf\" width=\"100%\">",
              "<TR bgcolor=\"aaaaff\">",th("SID"),th("User"),th("Login"),
	      th("Logout"),th("From"),"</TR>";
	$date1=localtime($q[0][1]);
	$date2=($q[0][2] > 0 ? localtime($q[0][2]) : '&nbsp;');
	print Tr(td($session_id),td($q[0][4]),td($date1),td($date2),
		 td($q[0][3])),"</TABLE>";
      }

      undef @q;
      db_query("SELECT date,type,ref,action,info " .
	       "FROM history WHERE sid=$session_id;",\@q);
      if (@q > 0) {
	print h3("Session history:");
	print "<TABLE bgcolor=\"#eeeebf\" width=\"100%\">",
              "<TR bgcolor=\"aaaaff\">",th("Date"),th("Type"),th("Ref"),
	      th("Action"),th("Info"),"</TR>";
	for $i (0..$#q) {
	  $date1=localtime($q[$i][0]);
	  $type=$q[$i][1];
	  print Tr(td($date1),td($type),
		   td($q[$i][2]),td($q[$i][3]),td($q[$i][4]));
	}
	print "</TABLE>";
      }
    }
  }
  elsif ($sub eq 'motd') {
    print h2("News & motd (message of day) messages:");
    get_news_list($serverid,10,\@list);
    print "<TABLE cellspacing=0 cellpadding=4  bgcolor=\"#dddddd\">";
    print "<TR bgcolor=\"aaaaff\"><TH width=\"70%\">Message</TH>",
          th("Date"),th("Type"),th("By"),"</TR>";
    for $i (0..$#list) {
      $date=localtime($list[$i][0]);
      $type=($list[$i][2] < 0 ? 'Global' : 'Local');
      $msg=$list[$i][3];
      $msg =~ s/\n/<BR>/g;
      print "<TR><TD bgcolor=\"#ddeeff\">$msg</TD>",
		   td($date),td($type),td($list[$i][1]),"</TR>";
    }
    print "</TABLE>";
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
    print h2("User info:");
    $state{email}=$user{email};
    $state{name}=$user{name};
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

    # plevel permissions
    print "<TR bgcolor=\"#dddddd\">",td("Level"),td($perms{plevel}),
	     td("(general privilege level)"),"</TR>";


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

    print "<P><BR><CENTER>",
        "<a href=\"http://sauron.jyu.fi/\" target=\"sauron\">",
        "<IMG src=\"$ICON_PATH/logo_large.png\" border=\"0\" alt=\"Sauron\">",
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
	print "<FONT color=\"red\">",h1("$name record update failed!"),
	      "<br>result code=$res",
	      "<br>error: " . db_errormsg() ."</FONT>";
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
	print "<FONT color=\"red\">",h1("Adding $name record failed!"),
	      "<br>result code=$res</FONT>";
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
  $c=cookie(-name=>"sauron-$SERVER_ID",-value=>'logged off',-expires=>'+1s',
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
  $state{'superuser'}='no';
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
	$state{'gid'}=$user{'gid'};
	$state{'sid'}=new_sid();
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

	# print news/MOTD stuff
	get_news_list($state{serverid},3,\@newslist);
	if (@newslist > 0) {
	  print h2("Message(s) of the day:"),"<TABLE bgcolor=\"#eeeeff\">";
	  for $i (0..$#newslist) {
	    $msg=$newslist[$i][3];
	    $msg =~ s/\n/<BR>/g;
	    $date=localtime($newslist[$i][0]);
	    print 
	      Tr(td($msg . "<FONT size=-1><I>" .
                  "<BR> &nbsp; &nbsp; -- $newslist[$i][1] $date </I></FONT>"));
	  }
	  print "</TABLE>";
	}

	logmsg("notice","user ($u) logged in from " . $ENV{'REMOTE_ADDR'});
	db_exec("UPDATE users SET last=$ticks WHERE id=$user{'id'};");
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
  fix_utmp($USER_TIMEOUT*2);
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
    print Tr(td("<a href=\"$url\">Show Current</a>")),
          Tr(td("<a href=\"$url&sub=select\">Select</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add\">Add</a>")),
          Tr(td("<a href=\"$url&sub=del\">Delete</a>")),
          Tr(td("<a href=\"$url&sub=edit\">Edit</a>"));
  } elsif ($menu eq 'zones') {
    $url.='?menu=zones';
    print Tr(td("<a href=\"$url\">Show Current</a>")),
          Tr(td("<a href=\"$url&sub=pending\">Show pending</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=select\">Select</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=add\">Add</a>")),
          Tr(td("<a href=\"$url&sub=Copy\">Copy</a>")),
          Tr(td("<a href=\"$url&sub=Delete\">Delete</a>")),
          Tr(td("<a href=\"$url&sub=Edit\">Edit</a>"));
  } elsif ($menu eq 'nets') {
    $url.='?menu=nets';
    print Tr(td("<a href=\"$url\">Networks</a>")),
          Tr(td("<a href=\"$url&sub=addnet\">Add net</a>")),
          Tr(td("<a href=\"$url&sub=addsub\">Add subnet</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=vlans\">VLANs</a>")),
          Tr(td("<a href=\"$url&sub=addvlan\">Add vlan</a>"));
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
          Tr(td("<a href=\"$url&sub=add&type=9\">Add DHCP entry</a>")),
          Tr(td("<a href=\"$url&sub=add&type=5\">Add printer</a>"));
  } elsif ($menu eq 'login') {
    $url.='?menu=login';
    print Tr(td("<a href=\"$url\">User info</a>")),
          Tr(td("<a href=\"$url&sub=who\">Who</a>")),
          Tr(td("<a href=\"$url&sub=motd\">News (motd)</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=login\">Login</a>")),
          Tr(td("<a href=\"$url&sub=logout\">Logout</a>")),
          Tr(),Tr(),Tr(td("<a href=\"$url&sub=passwd\">Change password</a>")),
          Tr(td("<a href=\"$url&sub=save\">Save defaults</a>"));
    if ($frame_mode) {
      print Tr(td("<a href=\"$script_name\" target=\"_top\">Frames OFF</a>"));
    } else {
      print Tr(td("<a href=\"$s_url/frames\" target=\"_top\">Frames ON</a>"));
    }
    if ($state{superuser} eq 'yes') {
      print Tr(),Tr(),
	    Tr(td("<a href=\"$url&sub=lastlog\">Lastlog</a>")),
	    Tr(td("<a href=\"$url&sub=session\">Session info</a>")),
	    Tr(),Tr(),
	    Tr(td("<a href=\"$url&sub=addmotd\">Add news message</a>"));
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
        "Server: $server<br>Zone: $zone<br>SID: $state{sid}<br></FONT>";

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
  return cookie(-name=>"sauron-$SERVER_ID",-expires=>'+7d',
		-value=>$val,-path=>$s_url);
}

sub save_state($) {
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

  error("cannot save stat '$id'") if ($res < 0);
}


sub load_state($) {
  my($id)=@_;
  my(@q);

  undef %state;
  $state{'auth'}='no';

  undef @q;
  db_query("SELECT uid,addr,auth,mode,serverid,server,zoneid,zone," .
      "uname,last,login,searchopts,searchdomain,searchpattern,superuser, " .
      "gid,sid " .
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
    $state{'gid'}=$q[0][15];
    $state{'sid'}=$q[0][16];

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
    return 0 if ($perms{plevel} >= $rule);
    alert1("Higher privilege level required") unless($quiet);
    return 1;
  }
  elsif ($type eq 'server') {
    return 0 if ($perms{server}->{$serverid} =~ /$rule/);
  }
  elsif ($type eq 'zone') {
    return 0 if ($perms{server}->{$serverid} =~ /$rule/);
    return 0 if ($perms{zone}->{$zoneid} =~ /$rule/);
  }
  elsif ($type eq 'host') {
    return 0  if ($perms{server}->{$serverid} =~ /RW/);
    if ($perms{zone}->{$zoneid} =~ /RW/) {
      return 0 if (@{$perms{hostname}} == 0);

      for $i (0..$#{$perms{hostname}}) {
	$re=$perms{hostname}[$i];
	#print p,"regexp='$re' '$rule'";
	return 0 if ($rule =~ /$re/);
      }
    }
    return 1 if ($quiet);
    alert1("You are not authorized to modify this host record");
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

    return 1 if ($quiet);
    alert1("Invalid IP (IP is outsize allowed net(s))");
    return 1;
  }

  return 1 if ($quiet);
  alert1("Access to $type denied");
  return 1;
}

############################################################################


sub restricted_add_host($) {
  my($rec)=@_;

  if (check_perms('host',$rec->{domain},1)) {
    alert1("Invalid hostname: doest not conform your restrictions");
    return -101;
  }

  return add_host($rec);
}
			

# eof

