# Sauron::CGI::Hosts.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003-2005.
# $Id$
#
package Sauron::CGI::Hosts;
require Exporter;
use CGI qw/:standard *table -no_xhtml/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Util;
use Sauron::Sauron;
use Sauron::CGI::Utils;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );

my $hinfo_addempty_mode = (defined($main::SAURON_HINFO_MODE) ?
			   $main::SAURON_HINFO_MODE : 1);
my $chr_group;

my %host_form = (
 data=>[
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain',
   conv=>'L', len=>64, iff=>['type','([^82]|101)']},
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)', type=>'zonename',
   len=>64,conv=>'L', iff=>['type','[2]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>64,
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
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   maxlen=>60, chr=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   maxlen=>100, empty=>1},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer',
   iff=>['type','[19]']},
  {ftype=>1, tag=>'ether_alias_info', name=>'Ethernet alias', no_empty=>1,
   empty=>1, type=>'domain', len=>30, iff=>['type','1'] },

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>1, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50, empty=>1,
   no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50, empty=>1,
   no_empty=>1, iff=>['type','(1|101)']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[159]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[159]']},
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[159]']},
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
 ],
 chr_group=>\$chr_group
);


my %restricted_host_form = (
 data=>[
  {ftype=>0, name=>'Host (restricted edit)' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain',
   conv=>'L', len=>64},
  {ftype=>5, tag=>'ip', name=>'IP address', restricted_mode=>1,
   iff=>['type','([169]|101)']},
  {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
   len=>64, iff=>['type','4'], iff2=>['alias','-1']},
  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   empty=>$main::SAURON_RHF{huser}, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   empty=>$main::SAURON_RHF{dept}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30, 
   maxlen=>60, empty=>$main::SAURON_RHF{location}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>$main::SAURON_RHF{email}, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   maxlen=>100, empty=>$main::SAURON_RHF{info}},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], iff2=>['ether_alias_info',''],
   empty=>$main::SAURON_RHF{ether}},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','101'], iff2=>['ether_alias_info',''], empty=>1},
  {ftype=>4, tag=>'ether_alias_info', name=>'Ethernet alias',
   iff=>['type','1']},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$main::SAURON_RHF{asset_id}, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   empty=>$main::SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>$main::SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   empty=>$main::SAURON_RHF{misc}, iff=>['type','(1|101)']},

#  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Group', iff=>['type','[15]']},
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ],
 chr_group=>\$chr_group
);


my %new_host_nets = (dummy=>'dummy');
my @new_host_netsl = ('dummy');

my %new_host_form = (
 data=>[
  {ftype=>0, name=>'New record' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>64,
   conv=>'L', iff=>['type','[^82]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (reservation)',
   type=>'domain', len=>64, conv=>'L', iff=>['type','101']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>64,
   conv=>'L', iff=>['type','[8]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)',
   type=>'zonename', len=>64, conv=>'L', iff=>['type','[2]']},
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
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','[13]']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   maxlen=>60, empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, maxlen=>100,
   empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','(1|9|101)'], empty=>1},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>1, no_empty=>1, chr=>1, iff=>['type','1']},
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
 ],
 chr_group=>\$chr_group
);

my %restricted_new_host_form = (
 data=>[
  {ftype=>0, name=>'New record (restricted)' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>64,
   conv=>'L'},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>64,
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
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   empty=>$main::SAURON_RHF{huser}, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   empty=>$main::SAURON_RHF{dept}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   maxlen=>60, empty=>$main::SAURON_RHF{location}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>$main::SAURON_RHF{email}, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   maxlen=>100, empty=>$main::SAURON_RHF{info} },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>0, iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>0, iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
   conv=>'U', iff=>['type','[19]'], empty=>$main::SAURON_RHF{ether}},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$main::SAURON_RHF{asset_id}, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   empty=>$main::SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   empty=>$main::SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   empty=>$main::SAURON_RHF{misc}, iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ],
 chr_group=>\$chr_group
);


my %new_alias_form = (
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


my %browse_page_size=(0=>'25',1=>'50',2=>'100',3=>'256',4=>'512',5=>'1000');
my %browse_search_fields=(0=>'Ether',1=>'Info',2=>'User',3=>'Location',
			  4=>'Department',5=>'Model',6=>'Serial',7=>'Misc',
			  8=>'Asset ID',
			  -1=>'<ANY>');
my @browse_search_f=('ether','info','huser','location','dept','model',
		  'serial','misc','asset_id');
my %browse_search_datefields=(0=>'Last lease (DHCP)',1=>'Last seen (DHCP)',
			      2=>'Creation',3=>'Modification');
my @browse_search_df=('dhcp_date','dhcp_last','cdate','mdate');

my %browse_hosts_form=(
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
  {ftype=>3, tag=>'sdtype', name=>'Search field', type=>'enum',
   enum=>\%browse_search_datefields},
  {ftype=>1, tag=>'dates',name=>'Dates',type=>'daterange',len=>17,
   extrainfo=>'Enter date range as -YYYYMMDD, YYYYMMDD-, or YYYYMMDD-YYYYMMDD',
   empty=>1},
  {ftype=>3, tag=>'stype', name=>'Search field', type=>'enum',
   enum=>\%browse_search_fields},
  {ftype=>1, tag=>'pattern',name=>'Pattern (regexp)',type=>'text',len=>40,
   empty=>1}
 ]
);



my %host_net_info_form=(
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



sub make_net_list($$$$$$) {
  my($id,$flag,$h,$l,$pcheck,$perms) = @_;
  my($i,$nets,$pc);


  $pcheck=0 if (keys %{$perms->{net}} < 1);

  $nets=get_net_list($id,1,$perms->{alevel});
  undef %{$h}; undef @{$l};

  if ($flag > 0) {
    $h->{'ANY'}='<Any net>';
    $$l[0]='ANY';
  }
  for $i (0..$#{$nets}) { 
    next unless ($$nets[$i][2]);
    next if ($pcheck && !($perms->{net}->{$$nets[$i][1]})); 
    $h->{$$nets[$i][0]}="$$nets[$i][0] - " . substr($$nets[$i][2],0,25);
    push @{$l}, $$nets[$i][0];
  }
}

sub restricted_add_host($) {
  my($rec)=@_;

  if (check_perms('host',$rec->{domain},1)) {
    alert1("Invalid hostname: does not conform your restrictions");
    return -101;
  }

  if ($rec->{type} == 4 && check_perms('flags','CNAME',1)) {
    alert1("You don't have permission to add CNAME Aliases");
    return -104;
  }

  if ($rec->{type} == 7 && check_perms('flags','AREC',1)) {
    alert1("You don't have permission to add AREC Aliases");
    return -107;
  }

  return add_host($rec);
}

# HOSTS menu
#
sub menu_handler {
  my($state,$perms) = @_;


  my($i,$tmp,$tmp2,$res,$ip,$newip,$p1,$p2,$p3,$p4,$type,$newhostform);
  my($u_id);
  my(%data,%bdata,%host,%nethash,@netkeys,@q);

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};
  $chr_group=$perms->{groups};

  unless ($serverid > 0) {
    alert1("Server not selected!");
    return;
  }
  unless ($zoneid > 0) {
    alert1("Zone not selected!");
    return;
  }
  return if (check_perms('zone','R'));

  my $id=param('h_id');
  if ($id > 0) {
    if (get_host($id,\%host)) {
      alert2("Cannot get host record (id=$id)!");
      return;
    }
  }

  my $sub=param('sub');
  $host_form{alias_l_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_a_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alias_d_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alevel}=$restricted_host_form{alevel}=$perms->{alevel};
  $new_host_form{alevel}=$restricted_new_host_form{alevel}=$perms->{alevel};

  if ($sub eq 'Delete') {
    return unless ($id > 0);
    goto show_host_record if (check_perms('delhost',$host{domain}));

    $res=delete_magic('h','Host','hosts',\%host_form,\&get_host,\&delete_host,
		      $id);
    goto show_host_record if ($res == 2);
    if ($res==1) {
      update_history($state->{uid},$state->{sid},1,
		    "DELETE: $host_types{$host{type}} ",
		    "domain: $host{domain}, ip:$host{ip}[1][1], " .
		    "ether: $host{ether}",$host{id});
    }
    return;
  }
  elsif ($sub eq 'Disable') {
    return unless ($id > 0);
    goto show_host_record if (check_perms('delhost',$host{domain}));
    if (update_host({id=>$id,type=>101}) < 0) {
      alert2("Failed to update host record (id=$id)");
    } else {
      update_history($state->{uid},$state->{sid},1,
		    "DISABLE: $host_types{$host{type}} ",
		    "domain: $host{domain}, ip:$host{ip}[1][1], " .
		    "ether: $host{ether}",$host{id});
      print h3("Host disabled (converted to a host reservation)");
    }
    goto show_host_record;
  }
  elsif ($sub eq 'Alias') { # add static alias
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
      update_history($state->{uid},$state->{sid},1,
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
	  my $old_ip=$host{ip}[1][1];
	  $host{ip}[1][1]=param('new_ip');
	  $host{ip}[1][4]=1;
	  $host{huser}=param('new_user') unless (param('new_user') =~ /^\s*$/);
	  $host{dept}=param('new_dept') unless (param('new_dept') =~ /^\s*$/);
	  $host{location}=param('new_loc')
	    unless (param('new_loc') =~ /^\s*$/);
	  $host{info}=param('new_info') unless (param('new_info') =~ /^\s*$/);
	  unless (($res=update_host(\%host)) < 0) {
	    update_history($state->{uid},$state->{sid},1,
			   "MOVE: $host_types{$host{type}} ",
		   "domain: $host{domain}, IP: $old_ip --> $host{ip}[1][1]",
			  $host{id});
	    print h2('Host moved.');
	    goto show_host_record;
	  } else {
	    alert1("Host update failed! ($res)");
	  }
	}
      }
      print h2("Move host to another IP");
      my $tmpnet=new Net::Netmask(param('move_net'));
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
    elsif (param('move_confirm2')) {
	my %newzone;
	my $newzoneid = param('move_zone');
	my %mystate = %main::state;
	$mystate{zoneid}=$newzoneid;
	if ($zoneid == $newzoneid) {
	    alert1("Cannot move to same zone!")
	}
	elsif (chk_perms(\%mystate,'zone','RW',1)) {
	    alert1("Not authorized to move hosts to this zone");
	}
	elsif (get_zone($newzoneid,\%newzone) < 0) {
	    alert1("Cannot get zone record (id=$newzoneid)");
	}
	else {
	    my $newzone = $newzone{name};
	    if ($newzone =~ /^(.*)\.($zone)\.?$/) {
		my $tmp = ".$1";
		if ($host{domain} =~ /^($.)($tmp)$/) {
		    my $newdomain = $1;
		    print "(renaming host record from '$host{domain}' " .
			  "to '$newdomain')<br>";
		    $host{domain}=$newdomain;
		}
	    }
	    $host{zone}=$newzoneid;
	    $host{mx}=-1;
	    $res=update_host(\%host);
	    unless ($res < 0 ) {
		print h2("Host moved from $zone to $newzone{name}");
		return;
	    }
	    alert1("Failed to move host to another zone ($res)");
	}
    }
    make_net_list($serverid,0,\%nethash,\@netkeys,1,$perms);
    my(%zonehash,@zonelist);
    get_zone_list2($serverid,\%zonehash,\@zonelist);
    $ip=$host{ip}[1][1];
    undef @q;
    db_query("SELECT net FROM nets WHERE server=$serverid AND subnet=true " .
	     "AND net >> '$ip';",\@q);
    print h2("Move host to another subnet or zone: ");
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id),
          hidden('sub','Move'),
          "Move host to: <TABLE><TR><TD>",
          popup_menu(-name=>'move_net',-values=>\@netkeys,
		     -default=>$q[0][0],-labels=>\%nethash),"</TD><TD>",
          submit(-name=>'move_confirm',-value=>'Move (to another subnet)'), 
          "</TD></TR><TR><TD>",
          popup_menu(-name=>'move_zone',-values=>\@zonelist,
		     -default=>$host{zone},-labels=>\%zonehash),"</TD><TD>",
          submit(-name=>'move_confirm2',-value=>'Move (to another zone)'), 
          "</TD></TR></TABLE>",
          submit(-name=>'move_cancel',-value=>'Cancel'), " ",
          end_form;
    display_form(\%host,\%host_form);
    return;
  }
  elsif ($sub eq 'Edit' || $sub eq 'Enable') {
    $host{type}=1 if ($sub eq 'Enable');
    return unless ($id > 0);
    goto show_host_record if (check_perms('host',$host{domain}));
    my $hform=(check_perms('zone','RWX',1) ?
	       \%restricted_host_form :\%host_form);

    if (param('h_cancel')) {
      print h2("No changes made to host record.");
      goto show_host_record;
    }

    if (param('h_submit')) {
      my $update_ok;
      my %oldhost=%host;
      my @old_ips;
      for $i (1..$#{$host{ip}}) { $old_ips[$i]=$host{ip}[$i][1]; }
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
	    if ($perms->{elimit} > 0) { # enforce expiration limit, if it exists
	      $tmp=time()+$perms->{elimit}*86400;
	      $host{expiration}=$tmp
		unless ($host{expiration} > 0 && $host{expiration} < $tmp)
	      }
	    $res=update_host(\%host);
	    if ($res < 0) {
	      alert1("Host record update failed! ($res)");
	      alert2(db_lasterrormsg());
	    } else {
	      update_history($state->{uid},$state->{sid},1,
			     ($sub eq 'Enable' ? 'ENABLE' : 'EDIT') .
			     ": $host_types{$host{type}} ",
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
	  hidden('menu','hosts'),hidden('sub','Edit');
    form_magic('h',\%host,$hform);
    print submit(-name=>'h_submit',-value=>'Apply')," ",
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
    return if check_perms('level',$main::ALEVEL_PING);
    goto show_host_record unless ($id > 0 && $host{type} == 1);
    if ($main::SAURON_PING_PROG && -x $main::SAURON_PING_PROG) {
      ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      if (is_cidr($ip)) {
	update_history($state->{uid},$state->{sid},1,
		       "PING","domain: $host{domain}, ip: $ip",$host{id});
	print "Pinging $host{domain} ($ip)...<br><pre>";
	$main::SAURON_PING_ARGS = '-c5' unless ($main::SAURON_PING_ARGS);
	$main::SAURON_PING_TIMEOUT = 15 unless ($main::SAURON_PING_TIMEOUT > 0);
	$|=1;
	$res= run_command($main::SAURON_PING_PROG,[$main::SAURON_PING_ARGS,$ip],
			 $main::SAURON_PING_TIMEOUT);
	print "</pre><br>";
	print "<FONT color=\"red\">PING TIMED OUT!</FONT><BR>"
	  if (($res& 255) == 14);
      } else {
	alert2("Missing/invalid IP address");
      }
    } else {
      alert2("Ping not configured!");
    }
  }
  elsif ($sub eq 'Traceroute') {
    return if check_perms('level',$main::ALEVEL_TRACEROUTE);
    goto show_host_record unless ($id > 0 && $host{type} == 1);
    if ($main::SAURON_TRACEROUTE_PROG && -x $main::SAURON_TRACEROUTE_PROG) {
      ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      if (is_cidr($ip)) {
	update_history($state->{uid},$state->{sid},1,
		      "TRACEROUTE","domain: $host{domain}, ip: $ip",$host{id});
	print "Tracing route to $host{domain} ($ip)...<br><pre>";
	my @arguments;
	push @arguments, $main::SAURON_TRACEROUTE_ARGS
	  if ($main::SAURON_TRACEROUTE_ARGS);
	push @arguments, $ip;
	$main::SAURON_TRACEROUTE_TIMEOUT = 15 
	  unless ($main::SAURON_TRACEROUTE_TIMEOUT > 0);
	$|=1;
	$res= run_command($main::SAURON_TRACEROUTE_PROG,\@arguments,
			 $main::SAURON_TRACEROUTE_TIMEOUT);
	print "</pre><br>";
	print "<FONT color=\"red\">TRACEROUTE TIMED OUT!</FONT><BR>"
	  if (($res& 255) == 14);
      } else {
	alert2("Missing/invalid IP address");
      }
    } else {
      alert2("Traceroute not configured!");
    }
  }
  elsif ($sub eq 'History') {
    return if (check_perms('level',$main::ALEVEL_HISTORY));
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
	param('bh_net',$q[$#q][0]); param('bh_sdtype','0');
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
	param('bh_sdtype','0');
	param('bh_dates','');

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
      $state->{searchopts}=param('bh_type').",".param('bh_order').",".
                   param('bh_size').",".param('bh_stype').",".
		   param('bh_sdtype').",".param('bh_net').",".
                   param('bh_cidr').",".param('bh_dates');
      $state->{searchdomain}=param('bh_domain');
      $state->{searchpattern}=param('bh_pattern');
      save_state($state->{cookie},$state);
    }
    elsif (param('lastsearch')) {
      if ($state->{searchopts} =~
	  /^(\d+),(\d+),(\d+),(-?\d+),(\d+),(\S*),(\S*),(\S*)$/) {
	param('bh_type',$1);
	param('bh_order',$2) unless (param('bh_order'));
	param('bh_size',$3);
	param('bh_stype',$4);
	param('bh_sdtype',$5);
	param('bh_net',$6) if ($6);
	param('bh_cidr',$7) if ($7);
	param('bh_dates',$8) if ($8);
      } else {
	print h2('No previous search found');
	goto browse_hosts;
      }
      param('bh_domain',$state->{searchdomain});
      param('bh_pattern',$state->{searchpattern});
    }

    my $typerule;
    my $typerule2;
    my $limit=$browse_page_size{param('bh_size')};
    $limit='100' unless ($limit > 0);
    my $page=param('bh_page');
    my $offset=$page*$limit;

    $type=param('bh_type');
    if ($type > 0) {
      $typerule=" AND a.type=$type ";
      $typerule=" AND (a.type=$type OR a.type=101) " if ($type==1);
    } else {
      $typerule2=" AND (a.type=1 OR a.type=6) ";
    }
    my $netrule;
    if (param('bh_net') ne 'ANY') {
      $netrule=" AND b.ip << '" . param('bh_net') . "' ";
    }
    if (param('bh_cidr')) {
      $netrule=" AND b.ip <<= '" . param('bh_cidr') . "' ";
    }
    my $domainrule;
    if (param('bh_domain') ne '') {
      $tmp=param('bh_domain');
      $domainrule=" AND a.domain ~* " . db_encode_str($tmp) . " ";
    }

    my $sorder;
    if (param('bh_order') == 1) { $sorder='5,1';  }
    elsif (param('bh_order') == 3) { $sorder='6,1'; }
    elsif (param('bh_order') == 4) { $sorder='7,8,1'; }
    else { $sorder='1,5'; }

    #if (param('bh_cidr') || param('bh_net') ne 'ANY') {
    #  $type=1;
    #}

    my $extrarule;
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
	  "OR a.model ~* $tmp2 OR a.misc ~* $tmp2 OR a.asset_id ~* $tmp2) ";
	#print p,"foobar";
      }
    }

    my $extrarule2;
    if (param('bh_dates')) {
      $tmp=$browse_search_df[param('bh_sdtype')];
      my $dates = decode_daterange_str(param('bh_dates'));
      if ($tmp) {
	if ($$dates[0] > 0 && $$dates[1] > 0) {
	  $extrarule2=" AND (a.$tmp >= $$dates[0] AND a.$tmp <= $$dates[1]) ";
	}
	elsif ($$dates[0] > 0) {
	  $extrarule2=" AND a.$tmp >= $$dates[0] ";
	}
	elsif ($$dates[1] > 0) {
	  $extrarule2.=" AND (a.$tmp <= $$dates[1] OR a.$tmp ISNULL) ";
	}
      }
      #print "extrarule2='$extrarule2'<br>";
    }


    undef @q;
    my $fields="a.id,a.type,a.domain,a.ether,a.info,a.huser,a.dept," .
	    "a.location,a.expiration,a.ether_alias";
    $fields.=",a.cdate,a.mdate,a.expiration,a.dhcp_date," .
             "a.hinfo_hw,a.hinfo_sw,a.model,a.serial,a.misc,a.asset_id"
	       if (param('csv'));

    my $sql;
    my $sql1="SELECT b.ip,'',$fields " .
             "FROM hosts a LEFT JOIN a_entries b ON b.host=a.id " .
	     "WHERE a.zone=$zoneid  $typerule $typerule2 " .
	     " $netrule $domainrule $extrarule $extrarule2 ";
    my $sql2="SELECT '0.0.0.0'::cidr,b.domain,$fields FROM hosts a,hosts b " .
             "WHERE a.zone=$zoneid AND a.alias=b.id AND a.type=4 " .
	     " $domainrule  ";
    my $sql3="SELECT '0.0.0.0'::cidr,a.cname_txt,$fields FROM hosts a  " .
             "WHERE a.zone=$zoneid AND a.alias=-1 AND a.type=4 " .
	     " $domainrule ";

    if ($type == 4) {
      $sql="$sql2 UNION $sql3 ORDER BY $sorder,2";
    } elsif ($type == 0) {
      $sql="$sql1 UNION $sql2 UNION $sql3 ORDER BY $sorder,3";
    }
    else { $sql="$sql1 ORDER BY $sorder,1"; }
    $sql.=" LIMIT $limit OFFSET $offset;" unless (param('csv'));
    #print "<br>$sql";
    db_query($sql,\@q);
    my $count=scalar @q;
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

    my %nmaphash;
    my $pingsweep=0;

    if (param('pingsweep')) {
      my @pingiplist;
      if (check_perms('level',$main::ALEVEL_NMAP,1)) {
	logmsg("warning","unauthorized ping sweep attempt: $state->{user}");
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
      update_history($state->{uid},$state->{sid},2,"Hosts PING Sweep",
		     "zone: $zone ($pingiplist[0]..$pingiplist[-1])",$zoneid);
      $res = run_ping_sweep(\@pingiplist,\%nmaphash,$state->{user});
      if ($res < 0) {
	alert2("Ping Sweep not configured!");
      } elsif ($res == 1) {
	alert2("Ping Sweep timed out!");
      } else {
	$pingsweep=1;
      }
    }

    my $sorturl="$selfurl?menu=hosts&sub=browse&lastsearch=1";
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
      my($nro,$ip);
      my $type=$q[$i][3];
      ($ip=$q[$i][0]) =~ s/\/\d{1,2}$//g;
      $ip="(".add_origin($q[$i][1],$zone).")" if ($type==4);
      $ip='N/A' if ($ip eq '0.0.0.0');
      my $ether=$q[$i][5];
      # $ether =~  s/^(..)(..)(..)(..)(..)(..)$/\1:\2:\3:\4:\5:\6/;
      $ether='<font color="#009900">ALIASED</font>' if ($q[$i][11] > 0);
      $ether='<font color="#990000">N/A</a>' unless($ether);
      my $hostname="<A HREF=\"$selfurl?menu=hosts&h_id=$q[$i][2]\">".
	        "$q[$i][4]</A>";
      my $info = join_strings(', ',(@{$q[$i]})[6,7,8,9]);

      my $trcolor='#eeeeee';
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

    my $params="bh_type=".param('bh_type')."&bh_order=".param('bh_order').
             "&bh_net=".param('bh_net')."&bh_cidr=".param('bh_cidr').
	     "&bh_stype=".param('bh_stype')."&bh_pattern=".param('bh_pattern').
	     "&bh_domain=".param('bh_domain')."&bh_size=".param('bh_size');

    my $npage;
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

    if ($main::SAURON_NMAP_PROG && param('bh_type') == 1 &&
	!check_perms('level',$main::ALEVEL_NMAP,1)) {

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
    $data{subgroups}=[];
    $data{dept}=$perms->{defdept} if ($perms->{defdept});
    $data{expiration}=time()+$perms->{elimit}*86400 if ($perms->{elimit} > 0);

  copy_add_label:
    $newhostform = \%new_host_form;
    return if (check_perms('zone','RW'));
    if (check_perms('zone','RWX',1)) {
      # check privilege flags if user doesn't have RWX permissions
      if ($type==1) { }
      elsif ($type==2) { return if check_perms('flags','DELEG'); }
      elsif ($type==3) { return if check_perms('flags','MX'); }
      elsif ($type==4) { return if check_perms('flags','SCNAME'); }
      elsif ($type==5) { return if check_perms('flags','PRINTER'); }
      elsif ($type==6) { return if check_perms('flags','GLUE'); }
      elsif ($type==8) { return if check_perms('flags','SRV'); }
      elsif ($type==9) { return if check_perms('flags','DHCP'); }
      elsif ($type==101) {
	if (check_perms('level',$main::ALEVEL_RESERVATIONS,1) &&
	    check_perms('flags','RESERV',1)) {
	  alert1("You are not authorized to add host reservations!");
	  return;
	}
      }
      else {
	alert1("Access Denied!");
	return;
      }

      $newhostform = \%restricted_new_host_form if ($type==1);
    }

    unless ($host_types{$type}) {
      alert2('Invalid add type!');
      return;
    }
    if ($type == 1 || $type == 101) {
      make_net_list($serverid,0,\%new_host_nets,\@new_host_netsl,1,$perms);
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
	if ($data{type}==1 && $data{net} ne 'MANUAL' &&
	    not is_cidr($data{ip})) {
	  my $tmpnet=new Net::Netmask($data{net});
	  $ip=auto_address($serverid,$tmpnet->desc());
	  unless (is_cidr($ip)) {
	    logmsg("notice","auto_address($serverid,$data{net}) failed!");
	    alert1("Cannot get free IP: $ip");
	    return;
	  }
	  $data{ip}=$ip;
	}

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
	  alert1("Invalid IP number: outside allowed range(s): $data{ip}");
	} else {
	  print h2("Add");
	  if ($data{type} == 1 || $data{type} == 101) {
	    $ip=$data{ip}; delete $data{ip};
	    $data{ip}=[[0,$ip,'t','t','']];
	  } elsif ($data{type} == 6) {
	    $ip=$data{glue}; delete $data{glue};
	    $data{ip}=[[0,$ip,'t','t','']];
	  } elsif ($data{type} == 9) {
	    $ip=$data{ip}; delete $data{ip};
	    $data{ip}=[[0,$ip,'f','f','']] if (is_cidr($ip));
	  }
	  delete $data{net};
	  #show_hash(\%data);
	  if ($perms->{elimit} > 0) { # enforce expiration limit, if it exists
	    $tmp=time()+$perms->{elimit}*86400;
	    $data{expiration}=$tmp
	      unless ($data{expiration} > 0 && $data{expiration} < $tmp)
	  }
	  $res=add_host(\%data);
	  if ($res > 0) {
	    update_history($state->{uid},$state->{sid},1,
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
	my $p3len=length(($p3=$1));
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
      if (!check_perms('level',$main::ALEVEL_HISTORY,1));
    print submit(-name=>'sub',-value=>'Network Settings'), " "
      if ($host{type} == 1);
    print submit(-name=>'sub',-value=>'Ping'), " "
      if ($host{type} == 1 && $main::SAURON_PING_PROG &&
	  !check_perms('level',$main::ALEVEL_PING,1));
    print submit(-name=>'sub',-value=>'Traceroute')
      if ($host{type} == 1 && $main::SAURON_TRACEROUTE_PROG &&
	  !check_perms('level',$main::ALEVEL_TRACEROUTE,1));
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
      print submit(-name=>'sub',-value=>'Disable'), " " if ($host{type} == 1);
      print submit(-name=>'sub',-value=>'Enable'), " " if ($host{type} == 101);
    }
    print end_form,"<br><br>";
    return;
  }


 browse_hosts:
  param('sub','browse');
  make_net_list($serverid,1,\%nethash,\@netkeys,0,$perms);

  %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>0,size=>3,sdtype=>0);
  if ($state->{searchopts} =~
      /^(\d+),(\d+),(\d+),(-?\d+),(\d+),(\S*),(\S*),(\S*)$/) {
    $bdata{type}=$1;
    $bdata{order}=$2;
    $bdata{size}=$3;
    $bdata{stype}=$4;
    $bdata{sdtype}=$5;
    $bdata{net}=$6 if ($6);
    $bdata{cidr}=$7 if ($7);
    $bdata{dates}=$8 if ($8);
  }
  $bdata{domain}=$state->{searchdomain} if ($state->{searchdomain});
  $bdata{pattern}=$state->{searchpattern} if ($state->{searchpattern});

  print start_form(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','browse'),
          hidden('bh_page','0');
  form_magic('bh',\%bdata,\%browse_hosts_form);
  print submit(-name=>'bh_submit',-value=>'Search')," &nbsp;&nbsp; ",
        submit(-name=>'bh_submit',-value=>'Clear'),
        end_form;

}





1;
# eof
