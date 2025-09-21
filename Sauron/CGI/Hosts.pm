# Sauron::CGI::Hosts.pm
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003-2005.
# $Id:$
#
package Sauron::CGI::Hosts;
require Exporter;
use CGI qw/:standard *table -utf8/;
#use CGI qw/:cgi/; # enable when debugging with url()
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Util;
use Sauron::Sauron;
use Sauron::CGI::Utils;
use Sys::Syslog qw(:DEFAULT setlogsock);
Sys::Syslog::setlogsock('unix');
use Net::IP qw(:PROC);
use Data::Dumper;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );


sub write2log{
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", "$msg");
  Sys::Syslog::closelog();
} # End of write2log



my $hinfo_addempty_mode = (defined($main::SAURON_HINFO_MODE) ?
			   $main::SAURON_HINFO_MODE : 1);
my $chr_group;

my %host_form = (
 data=>[
  {ftype=>0, name=>'Host' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', maxlen=>400,
   conv=>'L', len=>64, iff=>['type','([^82]|101)']},
  {ftype=>4, tag=>'fqdn', name=>'FQDN', title=>'Fully Qualified Domain Name'}, # ****
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)', type=>'zonename',
   len=>64,conv=>'L', iff=>['type','[2]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>64,
   conv=>'L', iff=>['type','[8]']},
  {ftype=>5, tag=>'ip', len=> 39, name=>'IP address', iff=>['type','([169]|101)'], subnetlist=>1},

  {ftype=>9, tag=>'alias_d', name=>'Alias for', idtag=>'alias', maxlen=>253, # maxlen added by TVu.
#  iff=>['type','4'], iff2=>['alias','\d+']},
   iff=>['type','4'], iff2=>['cname_alias','1']},

# {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
#  len=>60, maxlen=>400, iff=>['type','4'], iff2=>['alias','-1']}, # maxlen added by TVu.

# {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
#  len=>60, maxlen=>254, iff=>['type','4'], iff2=>['alias','-1']},

  {ftype=>9, tag=>'cname_txt', name=>'Static alias for', type=>'domain', idtag=>'alias',
   len=>60, maxlen=>400, iff=>['type','4'], iff2=>['static_alias','1']}, # 2020-12-15 TVu

  {ftype=>8, tag=>'alias_a', name=>'Alias for host(s)', fields=>3, maxlen=>253, # maxlen added by TVu.
   arec=>1, iff=>['type','7']},

  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'alias', name=>'Alias ID', iff=>['type','4']},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>4, tag=>'class', name=>'Class'},

# {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1,
#  definfo=>['','Default']},

  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1, # TVu 2021-02-11
   no_edit=>check_perms('flags','TTL',1), limits=>[$main::TTL_MIN_SEC, $main::TTL_MAX_SEC],
   definfo=>['','Default']},

  {ftype=>1, tag=>'router', name=>'Router (priority)', type=>'priority',
   len=>10, empty=>0,definfo=>['0','No'], iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   whitesp=>'P', empty=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   whitesp=>'P', empty=>1, chr=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   whitesp=>'P', maxlen=>60, chr=>1, empty=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   whitesp=>'P', maxlen=>100, empty=>1},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|9|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','[19]']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','[19]']},
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac', len=>20, maxlen=>17,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},
  {ftype=>4, tag=>'card_info', name=>'Card manufacturer',
   iff=>['type','[19]']},
  {ftype=>1, tag=>'ether_alias_info', name=>'Ethernet alias', no_empty=>1,
   empty=>1, type=>'domain', len=>30, maxlen=>400, iff=>['type','1'] },
  {ftype=>1, tag=>'duid', name=>'DUID', type=>'duid', len=>40,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},
   {ftype=>1, tag=>'iaid', name=>'IAID', type=>'iaid', len=>11,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1, extrahex=>8},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>1, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50, empty=>1,
   whitesp=>'P', no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   whitesp=>'P', empty=>1, no_empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50, empty=>1,
   whitesp=>'P', no_empty=>1, iff=>['type','(1|101)']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[159]']},
  {ftype=>10, tag=>'grp', name=>'Base group', iff=>['type','[159]'],
   no_dhcp=>1}, # ** Base, no_dhcp 2021-11-29 TVu
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[159]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','[13]']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},

  {ftype=>0, name=>'Host specific',iff=>['type','[12]']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['domain','text'],
   fields=>2, maxlen=>[400,80],
   len=>[50,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'wks_l', name=>'WKS', no_empty=>1, whitesp=>['','P','P'],
   type=>['text','text','text'], fields=>3, len=>[10,37,20], empty=>[0,0,1],
   elabels=>['Protocol','Services','Comment'], iff=>['type','1'], maxlen=>[10,400,80]},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)',
   type=>['priority','mx','text'], fields=>3, len=>[5,42,20], maxlen=>[5,400,80],
   empty=>[0,0,1], no_empty=>1, whitesp=>['','','P'],
   elabels=>['Priority','MX','comment'], iff=>['type','[13]']},

  {ftype=>2, tag=>'txt_l', name=>'TXT', type=>['text','text'],
   whitesp=>['P','P'], fields=>2, maxlen=>[253, 80],
#  len=>[40,15], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','1']},
#  len=>[50,20], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','[13]']},
   len=>[50,20], empty=>[0,1], elabels=>['TXT','comment'], iff=>['type','[137]']},
# TVu 2020-06-17 Changed '1' to [13] on previous line. For future: Changing to [134]
# will allow TXT records for CNAME aliases, including static aliases, which is not
# permitted by current rules.
# TVu 2020-11-02 Added type 7 (AREC aliases).

  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries', no_empty=>1,
   type=>['text','text'], fields=>2,len=>[50,20], empty=>[0,1],
   elabels=>['PRINTER','Comment'], iff=>['type','[15]']},
  {ftype=>2, tag=>'dhcp_l', name=>'DHCP entries', no_empty=>1, whitesp=>['N','P'],
   type=>['text','text'], fields=>2,len=>[50,20], maxlen=>[200,80],
   empty=>[0,1],elabels=>['DHCP','comment'], iff=>['type','[15]']},
  {ftype=>2, tag=>'dhcp_l6', name=>'DHCPv6 entries', no_empty=>1, whitesp=>['N','P'],
   type=>['text','text'], fields=>2,len=>[50,20], maxlen=>[200,80],
   empty=>[0,1],elabels=>['DHCP','comment'], iff=>['type','[15]']},
  {ftype=>0, name=>'Aliases', no_edit=>1, iff=>['type','1']},
  {ftype=>8, tag=>'alias_l', name=>'Aliases', fields=>3, iff=>['type','1']},
  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,20],
# Dot (.) allowed to superuser. 2020-08-10 TVu
   maxlen=>[5,5,5,400,80], dot=>check_perms('superuser','',1) ? 0 : 1,
   empty=>[0,0,0,0,1],elabels=>['Priority','Weight','Port','Target','Comment'],
   type=>['priority','priority','priority','fqdn','text'],
   iff=>['type','8']},

  {ftype=>0, name=>'Record info', no_edit=>0},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[1479]']},
  {ftype=>4, name=>'Last lease issued by DHCP server', tag=>'dhcp_date_str',
   no_edit=>1, iff=>['type','[19]|101']} # 101 (host reservation) added by TVu 27 May 2015
 ],
 chr_group=>\$chr_group
);


my %restricted_host_form = (
 data=>[
  {ftype=>0, name=>'Host (restricted edit)' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', maxlen=>400,
   conv=>'L', len=>64},
  {ftype=>4, tag=>'fqdn', name=>'FQDN', title=>'Fully Qualified Domain Name'}, # ****
  {ftype=>5, tag=>'ip', name=>'IP address', restricted_mode=>1, len=>39,
   iff=>['type','([16]|101)']},

# {ftype=>1, tag=>'cname_txt', name=>'Static alias for', type=>'domain',
#  len=>64, maxlen=>400, iff=>['type','4'], iff2=>['alias','-1']}, # maxlen added by TVu.
#  len=>64, maxlen=>400, iff=>['type','4'], iff2=>['cname_txt','\\S+']},
#  len=>64, maxlen=>400, iff=>['type','4'], iff2=>['static_alias','1']},

  {ftype=>9, tag=>'cname_txt', name=>'Static alias for', type=>'domain', idtag=>'alias',
   len=>64, maxlen=>400, iff=>['type','4'], iff2=>['static_alias','1']}, # 2020-12-15 TVu

  {ftype=>4, tag=>'id', name=>'Host ID'},
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},

  {ftype=>1, tag=>'ttl', name=>'TTL', type=>'int', len=>10, empty=>1, # TVu 2021-02-11
   no_edit=>check_perms('flags','TTL',1), limits=>[$main::TTL_MIN_SEC, $main::TTL_MAX_SEC],
   definfo=>['','Default']},

  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   whitesp=>'P', empty=>$main::SAURON_RHF{huser}, iff=>['type','[19]']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   whitesp=>'P', empty=>$main::SAURON_RHF{dept}, chr=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   whitesp=>'P', maxlen=>60, empty=>$main::SAURON_RHF{location}, chr=>1, iff=>['type','[19]']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>$main::SAURON_RHF{email}, iff=>['type','[19]']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   whitesp=>'P', maxlen=>100, empty=>$main::SAURON_RHF{info}},

  {ftype=>0, name=>'Equipment info', iff=>['type','1|9|101']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','[19]']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>25,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','[19]']},
# {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac', len=>20, maxlen=>17,
   conv=>'U', iff=>['type','[19]'], iff2=>['ether_alias_info',''],
   empty=>$main::SAURON_RHF{ether}},
# {ftype=>1, tag=>'ether', name=>'Ethernet address', type=>'mac', len=>17,
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac', len=>20, maxlen=>17,
   conv=>'U', iff=>['type','101'], iff2=>['ether_alias_info',''], empty=>1},
  {ftype=>1, tag=>'duid', name=>'DUID', type=>'duid', len=>40,
   conv=>'U', iff=>['type','([19]|101)'], empty=>$main::SAURON_RHF{duid}},

  {ftype=>1, tag=>'iaid', name=>'IAID', type=>'iaid', len=>11,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1, extrahex=>8},

  {ftype=>4, tag=>'ether_alias_info', name=>'Ethernet alias',
   iff=>['type','1']},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$main::SAURON_RHF{asset_id}, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   whitesp=>'P', empty=>$main::SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   whitesp=>'P', empty=>$main::SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   whitesp=>'P', empty=>$main::SAURON_RHF{misc}, iff=>['type','(1|101)']},

  {ftype=>0, name=>'Group/Template selections', iff=>['type','[159]']},
  {ftype=>10, tag=>'grp', name=>'Base group', iff=>['type','[159]'],
   no_dhcp=>1}, # ** Base, no_dhcp 2021-11-29 TVu
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[159]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[1479]']}
 ],
 chr_group=>\$chr_group
);


my %new_host_nets = (dummy=>'dummy');
my @new_host_netsl = ('dummy');

my %new_host_form = (
 data=>[
  {ftype=>0, name=>'New record' },
  {ftype=>4, tag=>'type', name=>'Type', type=>'enum', enum=>\%host_types},
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>64, maxlen=>400,
   conv=>'L', iff=>['type','[^82]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (reservation)', maxlen=>400,
   type=>'domain', len=>64, maxlen=>400, conv=>'L', iff=>['type','101']},
  {ftype=>1, tag=>'domain', name=>'Hostname (SRV)', type=>'srvname', len=>64,
   conv=>'L', iff=>['type','[8]']},
  {ftype=>1, tag=>'domain', name=>'Hostname (delegation)',
   type=>'zonename', len=>64, conv=>'L', iff=>['type','[2]']},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>60,
   maxlen=>400, # maxlen added by TVu.
   iff=>['type','4']},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'enum', preselectnet=>1,
   enum=>\%new_host_nets,elist=>\@new_host_netsl, iff=>['type','(1|101)']},
  {ftype=>1, tag=>'ip', macnotify=>1,
   name=>'IP <FONT size=-1>(only if "Manual IP" selected from above)</FONT>',
   type=>'ip', len=>39, empty=>1, iff=>['type','(1|101)']},
  {ftype=>1, tag=>'ip', name=>'IP',
   type=>'ip', len=>39, empty=>1, iff=>['type','9']},
  {ftype=>1, tag=>'glue',name=>'IP',type=>'ip', len=>40, iff=>['type','6']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', whitesp=>['','','P'],
   type=>['priority','mx','text'], fields=>3, len=>[5,42,20], maxlen=>[5,400,80], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], iff=>['type','3']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['domain','text'],
   fields=>2, maxlen=>[400,80],
   len=>[50,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries',
   type=>['text','text'], fields=>2,len=>[50,20], empty=>[0,1],
   elabels=>['PRINTER','Comment'], iff=>['type','5']},
  {ftype=>1, tag=>'router', name=>'Router (priority)', type=>'priority',
   len=>10, empty=>0,definfo=>['0','No'], iff=>['type','1']},
  {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Base group', iff=>['type','[15]'],
   no_dhcp=>1}, # ** Base, no_dhcp 2021-11-29 TVu
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','[13]']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   whitesp=>'P', empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   whitesp=>'P', empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   whitesp=>'P', maxlen=>60, empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'Info', type=>'text', len=>50, maxlen=>100,
   whitesp=>'P', empty=>1 },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>1, conv=>'U', iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac', len=>20, maxlen=>17,
   conv=>'U', iff=>['type','(1|9|101)'], empty=>1},
  {ftype=>1, tag=>'duid', name=>'DUID', type=>'duid', len=>40,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},
  {ftype=>1, tag=>'iaid', name=>'IAID', type=>'iaid', len=>10,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1},

  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>1, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50, empty=>1,
   whitesp=>'P', iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   whitesp=>'P', empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50, empty=>1,
   whitesp=>'P', iff=>['type','(1|101)']},

  {ftype=>0, name=>'SRV records', no_edit=>1, iff=>['type','8']},
  {ftype=>2, tag=>'srv_l', name=>'SRV entries', fields=>5,len=>[5,5,5,30,20],

#  maxlen=>[5,5,5,400,10], dot=>1,

# Dot (.) allowed to superuser. 2020-08-10 TVu
   maxlen=>[5,5,5,400,80], dot=>check_perms('superuser','',1) ? 0 : 1,

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
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>64, maxlen=>400,
   conv=>'L'},
  {ftype=>1, tag=>'cname_txt', name=>'Alias for', type=>'fqdn', len=>64, maxlen=>400, # maxlen added by TVu.
   iff=>['type','4']},
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'enum', preselectnet=>1,
   enum=>\%new_host_nets,elist=>\@new_host_netsl, iff=>['type','1']},
  {ftype=>1, tag=>'ip', macnotify=>1,
   name=>'IP <FONT size=-1>(only if "Manual IP" selected from above)</FONT>',
   type=>'ip', len=>30, empty=>1, iff=>['type','1']},
  {ftype=>1, tag=>'ip', name=>'IP',
   type=>'ip', len=>39, empty=>1, iff=>['type','9']},
  {ftype=>1, tag=>'glue', name=>'IP', type=>'ip', len=>40, iff=>['type','6']},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', whitesp=>['','','P'],
   type=>['priority','mx','text'], fields=>3, len=>[5,42,20], maxlen=>[5,400,80], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], iff=>['type','3']},
  {ftype=>2, tag=>'ns_l', name=>'Name servers (NS)', type=>['text','text'],
   fields=>2, maxlen=>[400,80],
   len=>[50,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','2']},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER entries',
   type=>['text','text'], fields=>2,len=>[50,20], empty=>[0,1],
   elabels=>['PRINTER','Comment'], iff=>['type','5']},
 # {ftype=>0, name=>'Group/Template selections', iff=>['type','[15]']},
  {ftype=>10, tag=>'grp', name=>'Base group', iff=>['type','[15]'],
   no_dhcp=>1}, # ** Base, no_dhcp 2021-11-29 TVu
  {ftype=>11, tag=>'subgroups', name=>'SubGroups', fields=>2,
   iff=>['type','[15]']},
  {ftype=>6, tag=>'mx', name=>'MX template', iff=>['type','1']},
  {ftype=>7, tag=>'wks', name=>'WKS template', iff=>['type','1']},
  {ftype=>0, name=>'Host info',iff=>['type','1']},
  {ftype=>1, tag=>'huser', name=>'User', type=>'text', len=>40, maxlen=>80,
   whitesp=>'P', empty=>$main::SAURON_RHF{huser}, iff=>['type','1']},
  {ftype=>1, tag=>'dept', name=>'Dept.', type=>'text', len=>30, maxlen=>60,
   whitesp=>'P', empty=>$main::SAURON_RHF{dept}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'location', name=>'Location', type=>'text', len=>30,
   whitesp=>'P', maxlen=>60, empty=>$main::SAURON_RHF{location}, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'email', name=>'User Email', type=>'email', len=>30,
   maxlen=>60, chr=>1, empty=>$main::SAURON_RHF{email}, iff=>['type','1']},
  {ftype=>1, tag=>'info', name=>'[Extra] Info', type=>'text', len=>50,
   whitesp=>'P', maxlen=>100, empty=>$main::SAURON_RHF{info} },
  {ftype=>0, name=>'Equipment info',iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_hw', name=>'HINFO hardware', type=>'hinfo', len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=0 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>0, conv=>'U', iff=>['type','1']},
  {ftype=>101, tag=>'hinfo_sw', name=>'HINFO software', type=>'hinfo',len=>20,
   sql=>"SELECT hinfo FROM hinfo_templates WHERE type=1 ORDER BY pri,hinfo;",
   addempty=>$hinfo_addempty_mode, empty=>0, conv=>'U', iff=>['type','1']},
  {ftype=>1, tag=>'ether', name=>'MAC address', type=>'mac', len=>20, maxlen=>17,
   conv=>'U', iff=>['type','[19]'], empty=>$main::SAURON_RHF{ether}},
  {ftype=>1, tag=>'duid', name=>'DUID', type=>'duid', len=>40,
   conv=>'U', iff=>['type','([19]|101)'], empty=>$main::SAURON_RHF{duid}},
  {ftype=>1, tag=>'iaid', name=>'IAID', type=>'iaid', len=>11,
   conv=>'U', iff=>['type','([19]|101)'], empty=>1, extrahex=>8},


  {ftype=>1, tag=>'asset_id', name=>'Asset ID', type=>'text', len=>20,
   empty=>$main::SAURON_RHF{asset_id}, no_empty=>1, chr=>1, iff=>['type','1']},
  {ftype=>1, tag=>'model', name=>'Model', type=>'text', len=>50,
   whitesp=>'P', empty=>$main::SAURON_RHF{model}, iff=>['type','1']},
  {ftype=>1, tag=>'serial', name=>'Serial no.', type=>'text', len=>35,
   whitesp=>'P', empty=>$main::SAURON_RHF{serial}, iff=>['type','1']},
  {ftype=>1, tag=>'misc', name=>'Misc.', type=>'text', len=>50,
   whitesp=>'P', empty=>$main::SAURON_RHF{misc}, iff=>['type','1']},
  {ftype=>0, name=>'Record info'},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1, iff=>['type','[147]']}
 ],
 chr_group=>\$chr_group
);


my %new_alias_form = (
 data=>[
  {ftype=>0, name=>'New Alias' },
  {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>40, maxlen=>400},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum',
   enum=>{4=>'CNAME',7=>'AREC'}},
  {ftype=>0, name=>'Alias for', maxlen=>254}, # maxlen added by TVu.
  {ftype=>4, tag=>'aliasname', name=>'Host'},
  {ftype=>4, tag=>'alias', name=>'ID'}
 ],
 new_alias=>1
);

# starts from 1 because used directly as param('csv') value
my %csv_timestamp=(1=>'Unix [epoch]',2=>'Standard [US]',
                   3=>'Spreadsheet [Excel]',4=>'ISO 8601:2004',
                   5=>'Email [RFC 822]');
my @csv_timestamp_f=('epoch','us-std','excel','iso8601:2004','rfc822date');
my %browse_page_size=(0=>'All',1=>'25',2=>'50',3=>'100',4=>'250',5=>'500',6=>'1000');
my %browse_search_fields=(0=>'Ether', 1=>'DUID', 2=>'Info',3=>'User',4=>'Location',
			  5=>'Department',6=>'Model',7=>'Serial',8=>'Misc', 9=>'Asset ID', 10=>'IAID',
			  11=>'HINFO',12=>'Has MX', # Has MX 2022-05-12 TVu
			  -1=>'<ANY>');
my @browse_search_f=('ether','duid', 'info','huser','location','dept','model',
		  'serial','misc','asset_id', 'iaid', 'hinfo', 'has_mx'); # has_mx 2022-05-12 TVu
my %browse_search_datefields=(0=>'Last lease (DHCP)',1=>'Last seen (DHCP)',
			      2=>'Creation',3=>'Modification',4=>'Expiration');
my @browse_search_df=('dhcp_date','dhcp_last','cdate','mdate','expiration');

my %browse_hosts_form=(
 data=>[
  {ftype=>0, name=>'Search scope' },
  {ftype=>3, tag=>'type', name=>'Record type', type=>'enum',
   enum=>\%host_types},
  {ftype=>10, tag=>'grp', name=>'Group' },
  {ftype=>3, tag=>'net', name=>'Subnet', type=>'list', listkeys=>'nets_k',
   list=>'nets'},
  {ftype=>1, tag=>'cidr', name=>'CIDR (block) or IP', type=>'cidr',
   len=>43, empty=>1},
  {ftype=>1, tag=>'domain', name=>'Domain pattern (regexp)', type=>'text',
   len=>40, empty=>1, anydomain=>1},
  {ftype=>0, name=>'Options' },
  {ftype=>3, tag=>'order', name=>'Sort order', type=>'enum',
   enum=>{1=>'by hostname',2=>'by IP'}},
  {ftype=>3, tag=>'size', name=>'Entries per page', type=>'enum',
   enum=>\%browse_page_size},
  {ftype=>0, name=>'Search' },
  {ftype=>3, tag=>'sdtype', name=>'Search field', type=>'enum',
   enum=>\%browse_search_datefields},
  {ftype=>1, tag=>'dates',name=>'Dates',type=>'daterange',len=>17,
   extrainfo=>'Enter date range as -YYYYMMDD, YYYYMMDD- or YYYYMMDD-YYYYMMDD',
   empty=>1},
  {ftype=>3, tag=>'stype', name=>'Search field', type=>'enum',
   enum=>\%browse_search_fields},
  {ftype=>1, tag=>'pattern',name=>'Pattern (regexp)',type=>'text',len=>40,
   whitesp=>'P', empty=>1},
  {ftype=>1, tag=>'search_txt', name=>'TXT (regexp)', type=>'text', len=>40, # TVu 2020-11-03
   whitesp=>'P', empty=>1, maxlen=>80, title=>'If you use TXT and choose ' .
       '"Any type", only types "Host", "Plain MX" and "AREC Alias" can ' .
       'be found, since only they can have TXT records. If you choose ' .
       'one of these three types, TXT is used to limit the search. If ' .
       'you choose any other specific type, TXT is ignored.'}
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
  {ftype=>1, tag=>'broadcast', name=>'Broadcast address', type=>'cidr',
   iff=>['broadcast','\S+'] },
  {ftype=>1, tag=>'netname', name=>'Network name', type=>'text' },
  {ftype=>1, tag=>'vlan', name=>'VLAN', type=>'text', iff=>['vlan','.+( \(\d+\))?'] }
 ],
 nwidth=>'40%'
);



sub make_net_list($$$$$$) {
  my($id,$flag,$h,$l,$pcheck,$perms) = @_;
  my($i,$nets,$pc);

# $id = serverid
# $flag = 1 = Include <Any Net> in result
# $h = hash for cidrs and names with cidr as key (result)
# $l = array for cidrs (result)
# $pcheck = 1 = Exclude nets for which user has no permission
# $perms = hash of user's permissions

  $pcheck=0 if (keys %{$perms->{net}} < 1);

# Get array of cidrs, ids and names.
  $nets=get_net_list($id,1,$perms->{alevel});
  undef %{$h}; undef @{$l};

  if ($flag > 0) {
    $h->{'ANY'}='<Any net>';
    $$l[0]='ANY';
  }
  for my $i (0..$#{$nets}) {
    next unless ($$nets[$i][2]);
    next if ($pcheck && !($perms->{net}->{$$nets[$i][1]}));
#    $h->{$$nets[$i][0]}="$$nets[$i][0] - " . substr($$nets[$i][2],0,25);
    $h->{$$nets[$i][0]}="$$nets[$i][0] - " . substr($$nets[$i][2],0,60); # mesrik
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

sub show_host_record($$)
{
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $id=param('h_id');
  my (%host);

  if (get_host($id,\%host)) {
    alert2("Cannot get host record (id=$id)!");
    return 1;
  }

  $host_form{bgcolor}='#ffcccc'
    if ($host{expiration} > 0 && $host{expiration} < time());
  # The following line was previously commented out. Why? TVu 20.09.2016
  $host_form{bgcolor}='#ccffff' if ($host{type}==101);
  print p,start_form(-method=>'GET',-action=>$selfurl),
    hidden('menu','hosts'),hidden('h_id',$id);
  print "<table width=\"99%\"><tr><td align=\"left\">",
    submit(-name=>'sub',-value=>'Refresh')," &nbsp; ";
  print submit(-name=>'sub',-value=>'-> This Subnet')," &nbsp; " if ($host{type} == 1);

  # This drop-down list is not strictly for IPv6, but will probably be useful with it.
  # It is used to select IP for "This subnet", "Ping", "Traceroute", "Copy" and "Move"
  # when a host has multiple IP addresses, especially both IPv4 and IPv6.
  my @opt;
  for my $ind1 (1..$#{$host{ip}}) {
    push @opt, $host{ip}[$ind1][1];
  }
  if (@opt) { print popup_menu('select_ip', \@opt); }

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
  my %fqdnzone; # ****
  if (get_zone($host{zone}, \%fqdnzone) == 0) {
    $host{fqdn} = $host{domain} . '.' . $fqdnzone{name} . '.';
  }
  display_form(\%host,\%host_form);

  # 2020-11-11 TVu
  # User's right to add, edit and delete SRV records or AREC, CNAME or Static aliases:
  # No RW permission to the zone => None of the above
  # RWX permission to the zone => All of the above
  # RW permission to the zone => Right to a specific type if user has that flag set
  # Flags don't affect reading

  # 2021-03-01 TVu
  # Only superusers are allowed to edit, delete or copy Delegations (2) and Glue
  # records (6). The same is true for adding, but that is handled in sauron.cgi.

  unless (check_perms('zone','RW',1) ||
	  ($host{type} == 2 || $host{type} == 6) && check_perms('superuser','',1)) {
    my $rwx = check_perms('zone','RWX',1);
    print submit(-name=>'sub',-value=>'Edit'), " ",
      submit(-name=>'sub',-value=>'Delete'), " "
      # Check alias permission flags. 2020-09-07 TVu
      # Added check of SRV flag. TVu 2020-11-09
      unless ($host{type} == 4 &&
	      ($host{cname_alias} && $rwx && check_perms('flags','CNAME',1) ||
	       $host{static_alias} && $rwx && check_perms('flags','SCNAME',1)) ||
	      $host{type} == 7 && $rwx && check_perms('flags','AREC',1) ||
	      $host{type} == 8 && $rwx && check_perms('flags','SRV',1));

    # CNAME and AREC aliases can't be copied because there are bugs in the program,
    # and finding those bugs proved to be too time-consuming. 2020-09-14 TVu
    # Please fix if you know how.
    print submit(-name=>'sub',-value=>'Copy'), " "
      # Check static alias permission flag.
      # Added check of SRV flag. TVu 2020-11-09
      unless ($host{type} == 4 && ($host{cname_alias} || $host{static_alias} && $rwx && check_perms('flags','SCNAME',1)) ||
	      $host{type} == 7 ||
	      $host{type} == 8 && $rwx && check_perms('flags','SRV',1));

    print submit(-name=>'sub',-value=>'Move'), " " if ($host{type} == 1);

    #print submit(-name=>'sub',-value=>'Alias'), " " if ($host{type} == 1);

    # Show button to create a CNAME or AREC alias if permission flags allow at least one of them.
    print submit(-name=>'sub',-value=>'Alias'), " " # 2020-09-07 TVu

      #	    if ($host{type} == 1 && !$rwx &&
      #		(!check_perms('flags','CNAME',1) || !check_perms('flags','AREC',1)));

      if ($host{type} == 1 && (!$rwx || # ** 2022-02-21 TVu
			       !check_perms('flags','CNAME',1) || !check_perms('flags','AREC',1)));

    print submit(-name=>'sub',-value=>'Disable'), " " if ($host{type} == 1);
    print submit(-name=>'sub',-value=>'Enable'), " " if ($host{type} == 101);
  }
  print end_form,"<br><br>";

  return 0;
}

sub browse_hosts($$)
{
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my (%nethash,@netkeys);

  param('sub','browse');
  make_net_list($serverid,1,\%nethash,\@netkeys,0,$perms);
  $browse_hosts_form{alevel}=$perms->{alevel};

  my %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	     type=>1,order=>2,stype=>0,size=>3,sdtype=>0,grp=>-1);
  if ($state->{searchopts} =~
#     /^(\d+),(\d+),(\d+),(-?\d+),(\d+),(\S*),(\S*),(\S*),(-?\d+)$/) {
      /^(\d+),(\d+),(\d+),(-?\d+),(\d+),(\S*),(\S*),(\S*),(-?\d+),(\S*),(\S*)$/) { # ****
    $bdata{type}=$1;
    $bdata{order}=$2;
    $bdata{size}=$3;
    $bdata{stype}=$4;
    $bdata{sdtype}=$5;
    $bdata{net}=$6 if ($6);
    $bdata{cidr}=$7 if ($7);
    $bdata{dates}=$8 if ($8);
    $bdata{grp}=$9;
    $bdata{bh_domain_anydom}=$10; # ****
    $bdata{search_txt}=$11 if ($11); # TVu 2020-11-03
  }
  $bdata{domain}=$state->{searchdomain} if ($state->{searchdomain});
  $bdata{pattern}=$state->{searchpattern} if ($state->{searchpattern});
  $bdata{search_txt}=$state->{search_txt} if ($state->{search_txt}); # TVu 2020-11-03

  print start_form(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','browse'),
          hidden('bh_page','0');
  form_magic('bh',\%bdata,\%browse_hosts_form);
  print submit(-name=>'bh_submit',-value=>'Search')," &nbsp;&nbsp; ",
        submit(-name=>'bh_submit',-value=>'Clear'),
        end_form;

  return 0;
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

# Zone names are used when checking lengths of domain names,
# unless they are FQDNs. TVu 2020-06-01
  $host_form{'zonename'} = $restricted_host_form{'zonename'} =
      $new_host_form{'zonename'} = $restricted_new_host_form{'zonename'} =
      $new_alias_form{'zonename'} = $state->{zone};

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
  $host_form{cname_txt_url}="$selfurl?menu=hosts&h_id=";
  $host_form{alevel}=$restricted_host_form{alevel}=$perms->{alevel};
  $new_host_form{alevel}=$restricted_new_host_form{alevel}=$perms->{alevel};

  if ($sub eq 'Delete') {
    return unless ($id > 0);

    return -102 if (check_perms('zone','RW'));
    if (check_perms('zone','RWX',1)) {
# Check alias permission flags. 2020-09-07 TVu
	if ($host{type} == 4 && $host{cname_alias} && check_perms('flags','CNAME',1)) {
	    alert1("You don't have permission to delete CNAME Aliases");
	    return -104;
	}
	if ($host{type} == 4 && $host{static_alias} && check_perms('flags','SCNAME',1)) {
	    alert1("You don't have permission to delete Static Aliases");
	    return -104;
	}
	if ($host{type} == 7 && check_perms('flags','AREC',1)) {
	    alert1("You don't have permission to delete AREC Aliases");
	    return -107;
	}
# Added check of SRV flag. TVu 2020-11-09
	if ($host{type} == 8 && check_perms('flags','SRV',1)) {
	    alert1("You don't have permission to delete SRV records");
	    return -108;
	}
    }

    if (check_perms('delhost',$host{domain})) {
      show_host_record($state,$perms);
      return;
    }

    $res=delete_magic('h','Host','hosts',\%host_form,\&get_host,\&delete_host,
		      $id);
    if ($res == 2) {
      show_host_record($state,$perms);
      return;
    }
    if ($res==1) {
      update_history($state->{uid},$state->{sid},1,
		    "DELETE: $host_types{$host{type}} ",
		    "domain: $host{domain}, ip:$host{ip}[1][1], " .
		    "ether: $host{ether}",$host{id}) if ip_is_ipv4($host{ip}[1][1]);
      update_history($state->{uid},$state->{sid},1,
		    "DELETE: $host_types{$host{type}} ",
		    "domain: $host{domain}, ip:$host{ip}[1][1], " .
		    "duid: $host{duid}",$host{id}) if ip_is_ipv6($host{ip}[1][1]);

# Create navigation buttons.

      my $select_ip = param('select_ip');
      my $net_cidr = get_net_cidr_by_ip($serverid, $select_ip);
      my $net_id = get_net_by_cidr($serverid, $net_cidr);

      my $old_menu = param('menu');
      my $old_sub = param('sub');
      my $old_bh_net = param('bh_net');
      my $old_list = param('list');
      my $old_net_id = param('net_id');

      print "\n<table><tr><td>";

      if ($select_ip) {

	  param('menu', 'hosts');
	  param('sub', 'browse');
	  param('bh_net', $net_cidr);
	  print start_form(-method=>'GET', -action=>$selfurl),
	  hidden('menu', 'hosts'), hidden('sub', 'browse'),
	  hidden('bh_net', $net_cidr);
	  print submit(-name=>'foobar', -value=>'Browse This Subnet');
	  print end_form,"\n";

	  print "</td><td>";

	  param('menu', 'nets');
	  param('net_id', $net_id);
	  print start_form(-method=>'GET', -action=>$selfurl),
	  hidden('menu', 'nets'), hidden('net_id', $net_id);
	  print submit(-name=>'foobar', -value=>'Go to This Subnet');
	  print end_form,"\n";

	  print "</td><td>";

	  param('menu', 'nets');
	  param('sub', 'Net Info');
	  param('net_id', $net_id);
	  print start_form(-method=>'GET', -action=>$selfurl),
	  hidden('menu', 'nets'), hidden('sub', 'Net Info'),
	  hidden('net_id', $net_id);
	  print submit(-name=>'foobar', -value=>'Go to Net Info');
	  print end_form,"\n";

	  print "</td><td>";

      }

# If a CNAME alias was deleted, create a button to navigate to the host the alias referred to.
      if ($host{type} == 4 && $host{cname_alias} == 1 &&
	  $host{alias} > 0 && $host{alias_d}) {
	  param('menu', 'hosts');
	  param('h_id', $host{alias});
	  print start_form(-method=>'GET', -action=>$selfurl),
	  hidden('menu', 'hosts'), hidden('h_id', $host{alias});
	  print submit(-name=>'foobar', -value=>"Go to $host{alias_d}", autofocus=>'true');
	  print end_form,"\n";

	  print "</td><td>";

      }

      param('menu', 'nets');
      param('list', 'all');
      print start_form(-method=>'GET', -action=>$selfurl),
      hidden('menu', 'nets'), hidden('list', 'all');
      print submit(-name=>'foobar', -value=>'Go to Nets/All');
      print end_form,"\n";

      print "</td></table>";

      param('menu', $old_menu);
      param('sub', $old_sub);
      param('bh_net', $old_bh_net);
      param('list', $old_list);
      param('net_id', $old_net_id);

    }
    return;
  }
  elsif ($sub eq 'Disable') {
    return unless ($id > 0);
    if (!check_perms('delhost',$host{domain})) {
      if (update_host({id=>$id,type=>101}) < 0) {
	alert2("Failed to update host record (id=$id)");
      } else {
	update_history($state->{uid},$state->{sid},1,
		       "DISABLE: $host_types{$host{type}} ",
		       "domain: $host{domain}, ip:$host{ip}[1][1], " .
		       "ether: $host{ether}",$host{id});
	print h3("Host disabled (converted to a host reservation)");
      }
    }
    show_host_record($state,$perms);
    return;
  }
  elsif ($sub eq 'Alias') { # add static alias - This really adds AREC and CNAME aliases!
    if ($id > 0) {
      $data{alias}=$id;
      $data{aliasname}=$host{domain};
      if (check_perms('host',$host{domain})) {
	show_host_record($state,$perms);
	return;
      }
    }

    $data{type}=4;
    $data{zone}=$zoneid;
    $data{alias}=param('aliasadd_alias') if (param('aliasadd_alias'));
    $res=add_magic('aliasadd','ALIAS','hosts',\%new_alias_form,
		   \&restricted_add_host,\%data);
    if ($res > 0) {
      # Alias inherits TTL from host. 2019-01-08 TVu
      if (param('aliasadd_alias')) {
	my $sql = "update hosts set ttl = (select ttl from hosts where id = " .
	  param('aliasadd_alias') . ") where id = $res;";
	db_exec($sql); # No error checking.
      }
      update_history($state->{uid},$state->{sid},1,
		     "ALIAS: $host_types{$data{type}} ",
		     "domain: $data{domain}, alias=$data{alias}",$res);
      param('h_id',$res);
      show_host_record($state,$perms);
      return;
    }
    elsif ($res < 0) {
      param('h_id',param('aliasadd_alias'));
      show_host_record($state,$perms);
      return;
    }
    return;
  }
  elsif ($sub eq 'Move') {
    return unless ($id > 0);
    if (check_perms('host',$host{domain})) {
      show_host_record($state,$perms);
      return;
    }
    # These moves are now supported.
    #   if ($#{$host{ip}} > 1) {
    #     alert2("Host has multiple IPs!");
    #     print  p,"Move of hosts with multiple IPs not supported (yet)";
    #     return;
    #   }
    if (param('move_cancel')) {
      print h2("Host record not moved");
      show_host_record($state,$perms);
      return;
    } elsif (param('move_confirm')) {
      if (param('move_confirm2')) {
	if (not is_cidr(param('new_ip'))) {
	  alert1('Invalid IP!');
	} elsif (ip_in_use($serverid,param('new_ip'))) {
	  alert1('IP already in use!');
	} elsif (check_perms('ip',param('new_ip'),1)) {
	  alert1('Invalid IP number: outside allowed range(s)');
	} else {
	  # Old code.
	  #	    my $old_ip=$host{ip}[1][1];
	  #	    $host{ip}[1][1]=param('new_ip');
	  #	    $host{ip}[1][4]=1;
	  # Support for moving hosts with multiple IPs, one IP at a time.
	  # The selected IP will be replaced. TVu
	  my $old_ip = param('select_ip');
	  my $ind2;
	  for my $ind1 (1..$#{$host{ip}}) {
	    if ($old_ip eq $host{ip}[$ind1][1]) { $ind2 = $ind1; last; }
	  }
	  if (!$ind2) {
	    alert2("Someone has changed the IP that you were trying to change!");
	    return;
	  }
	  $host{ip}[$ind2][1] = param('new_ip');
	  $host{ip}[$ind2][4] = 1;
	  # End of new code.
	  $host{huser}=param('new_user') unless (param('new_user') =~ /^\s*$/);
	  $host{dept}=param('new_dept') unless (param('new_dept') =~ /^\s*$/);
	  $host{location}=param('new_loc')
	    unless (param('new_loc') =~ /^\s*$/);
	  $host{info}=param('new_info') unless (param('new_info') =~ /^\s*$/);
	  unless (($res=update_host(\%host)) < 0) {
	    update_history($state->{uid},$state->{sid},1,
			   "MOVE: $host_types{$host{type}} ",
			   "domain: $host{domain}, IP: $old_ip --> $host{ip}[$ind2][1]",
			   $host{id});
	    print h2('Host moved.');
	    show_host_record($state,$perms);
	    return;
	  } else {
	    alert1("Host update failed! ($res)");
	  }
	}
      }
      print h2("Move host to another IP");
      # my $tmpnet=new Net::IP(param('move_net'));
      # $newip=auto_address($serverid,param('move_net'));
      $newip = get_free_ip_by_net($serverid, param('move_net'), $data{ether}, '',
				  get_net_ip_policy($serverid, param('move_net')));
      unless (is_cidr($newip)) {
	logmsg("notice","get_free_ip_by_net($serverid, '" . param('move_net') . "', '" .
	       $data{ether} . "', '', " . get_net_ip_policy($serverid, param('move_net')) . ") failed!");
	print h3($newip);
	# Support for moving hosts with multiple IPs.
	# $newip=$host{ip}[1][1];
	$newip = param('select_ip');
      }
      print p,start_form(-method=>'GET',-action=>$selfurl),
            hidden('menu','hosts'),hidden('h_id',$id),hidden('sub','Move'),
            hidden('select_ip', param('select_ip')),
            hidden('move_confirm'),hidden('move_net'),p,"<TABLE>",
# Support for moving hosts with multiple IPs.
	    Tr(td("Current IP:"),
	       td(param('select_ip'))),
	    Tr(td("New IP:"),
	       td(textfield(-name=>'new_ip',-size=>40, -maxlength=>40,
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
	elsif (chk_perms(\%mystate,'host',$host{domain},1)) {
	   alert1("Not authorized to move host in target zone with that name");
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
		update_history($state->{uid},$state->{sid},1,
			       "MOVE: $host_types{$host{type}} ",
			       "domain: $host{domain} move: $zone --> " .
			       "$newzone{name}",$host{id});
		print h2("Host moved from $zone to $newzone{name}");
		return;
	    }
	    alert1("Failed to move host to another zone ($res)");
	}
    }
    make_net_list($serverid,0,\%nethash,\@netkeys,1,$perms);
    my(%zonehash,@zonelist);
    get_zone_list2($serverid,\%zonehash,\@zonelist);
# Support for moving hosts with multiple IPs.
#   $ip=$host{ip}[1][1];
    $ip = param('select_ip');
    undef @q;
    db_query("SELECT net FROM nets WHERE server=$serverid AND subnet=true " .
	     "AND net >> '$ip';",\@q);
    print h2("Move host to another subnet or zone: ");
    print p,start_form(-method=>'GET',-action=>$selfurl),
          hidden('menu','hosts'),hidden('h_id',$id),
          hidden('select_ip', param('select_ip')),
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

#      print Dumper(\%host);

    return -102 if (check_perms('zone','RW'));
    if (check_perms('zone','RWX',1)) {
# Check alias permission flags. 2020-09-07 TVu
	if ($host{type} == 4 && $host{cname_alias} && check_perms('flags','CNAME',1)) {
	    alert1("You don't have permission to edit CNAME Aliases");
	    return -104;
	}
	if ($host{type} == 4 && $host{static_alias} && check_perms('flags','SCNAME',1)) {
	    alert1("You don't have permission to edit Static Aliases");
	    return -104;
	}
	if ($host{type} == 7 && check_perms('flags','AREC',1)) {
	    alert1("You don't have permission to edit AREC Aliases");
	    return -107;
	}
# Added check of SRV flag. TVu 2020-11-09
	if ($host{type} == 8 && check_perms('flags','SRV',1)) {
	    alert1("You don't have permission to edit SRV records");
	    return -108;
	}
    }

    $host{type}=1 if ($sub eq 'Enable');
    return unless ($id > 0);
    if (check_perms('host',$host{domain})) {
      show_host_record($state,$perms);
      return;
    }
    # my $hform=(check_perms('zone','RW',1) || check_perms('flags','SRV') ?
    my $hform=(check_perms('zone','RW',1) || check_perms('flags','SRV',1) ? # 2020-10-19 TVu
	       \%restricted_host_form : \%host_form);

    # An ordinary user can't edit TTL if superuser has set a value, which is outside limits.
    # TVu 2021-02-15
    if (defined($host{'ttl'}) && $host{'ttl'} > 0 &&
	!check_perms('flags','TTL',1) && check_perms('superuser','',1)) {
	for my $item (@{$$hform{'data'}}) {
	    if ($item->{'tag'} eq 'ttl' && $item->{'limits'} &&
		($host{'ttl'} < $item->{'limits'}[0] || $host{'ttl'} > $item->{'limits'}[1])) {
		$item->{'no_edit'} = 1;
		last;
	    }
	}
    }

    if (param('h_cancel')) {
      print h2("No changes made to host record.");
      show_host_record($state,$perms);
      return;
    }

    if (param('h_submit')) {

#	my @names = param();
#	foreach my $var (@names) { print "$var, " . param($var) . "<BR>"; }

#	print Dumper(\%host);

      my $update_ok;
      my %oldhost=%host;
      my @old_ips;
      my $useInet4 = 0;
      my $useInet6 = 0;
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

	  #for $i (1..$#{$host{ip}}) {
      #      $useInet4 = 1 if ip_is_ipv4($host{ip}[$i][1]) and param("h_ip_".$i."_del") ne "on";
	  #      $useInet6 = 1 if ip_is_ipv6($host{ip}[$i][1]) and param("h_ip_".$i."_del") ne "on";
      #}


	  #if($useInet6 == 0 and $host{duid} ne ""){
	  #	    alert2("IPv6 address not set -> empty DUID required!");
      #      $update_ok = 0;
	  #}

      #if($useInet6 == 0 and $host{iaid} ne ""){
      #      alert2("IPv6 address not set -> empty IAID required!");
      #      $update_ok = 0;
      #}

      #if($useInet6 == 1 and $host{iaid} ne "" and $host{duid} eq ""){
      #      alert2("DUID not set -> non empty DUID required!");
      #      $update_ok = 0;
      #}

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
			     ($host{duid} ne $oldhost{duid} ?
			      "DUID: $oldhost{duid} --> $host{duid} ":"") .
			     ($host{iaid} ne $oldhost{iaid} ?
			      "IAID: $oldhost{iaid} --> $host{iaid} ":"") .
			     ($host{ip}[1][1] ne $old_ips[1] ?
			      "ip: $old_ips[1] --> $host{ip}[1][1] ":""),
			     $host{id});
	      print h2("Host record succesfully updated.");
	      show_host_record($state,$perms);
	      return;
	    }
	  }
	}
      } else {
	alert1("Invalid data in form! ($res)");
      }
    }

    print h2("Edit host:"),p,start_form(-method=>'POST',-action=>$selfurl),
	  hidden('menu','hosts'),hidden('sub','Edit');
    $host{hostid} = $host{id};
    $host{perms} = $perms;
#    my %fqdnzone;
#    if (get_zone($host{zone}, \%fqdnzone) == 0) {
#	$host{fqdn} = $host{domain} . '.' . $fqdnzone{name} . '.';
#    }
    form_magic('h',\%host,$hform);
    print submit(-name=>'h_submit',-value=>'Apply')," ",
          submit(-name=>'h_cancel',-value=>'Cancel'),end_form;
    return;
  }
  elsif ($sub eq 'Network Settings') {
    unless ($id > 0 && $host{type} == 1) {
      show_host_record($state,$perms);
      return;
    }
    # get_host_network_settings($serverid,$host{ip}[1][1],\%data);
    print "Current network settings for: $host{domain}<p>";
    # display_form(\%data,\%host_net_info_form);
    # Show network settings for all IP addresses that the host has, not just
    # the first one. Unrelated to IPv6, but probably useful with it.
    for my $ind1 (1..$#{$host{ip}}) {
        undef %data;
        get_host_network_settings($serverid,$host{ip}[$ind1][1],\%data);
        display_form(\%data,\%host_net_info_form);
        print "<br>";
    }
    print "<br><hr noshade><br>";
    show_host_record($state,$perms);
    return;
  }
  elsif ($sub eq 'Ping') {
    return if check_perms('level',$main::ALEVEL_PING);
    unless ($id > 0 && $host{type} == 1) {
      show_host_record($state,$perms);
      return;
    }
    if ($main::SAURON_PING_PROG && -x $main::SAURON_PING_PROG) {
# Selected IP address instead of the first one only.
#     ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      ($ip=param('select_ip')) =~ s/\/32\s*$//;
      $ip =~ s/\/128\s*$//; # For IPv6.
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
    unless ($id > 0 && $host{type} == 1) {
      show_host_record($state,$perms);
      return;
    }
    if ($main::SAURON_TRACEROUTE_PROG && -x $main::SAURON_TRACEROUTE_PROG) {
# Selected IP address instead of the first one only.
#     ($ip=$host{ip}[1][1]) =~ s/\/32\s*$//;
      ($ip=param('select_ip')) =~ s/\/32\s*$//;
      $ip =~ s/\/128\s*$//; # For IPv6.
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
    unless ($id > 0) {
      show_host_record($state,$perms);
      return;
    }
    print "History for host record: $id ($host{domain}):<br>";
    get_history_host($id,\@q);
    unshift @q, [$host{cdate},'CREATE','record created',$host{cuser}];
    display_list(['Date','Action','Info','By'],\@q,0);
  }
  elsif ($sub eq '-> This Subnet') {
# Selected IP address instead of the first one only.
#   if (is_cidr(($ip=$host{ip}[1][1]))) {
    if (is_cidr(($ip=param('select_ip')))) {
      db_query("SELECT net FROM nets " .
	       "WHERE server=$serverid AND '$ip' << net " .
	       "ORDER BY subnet,net",\@q);
      if (@q > 0) {
	param('bh_type','1'); param('bh_order','2');
	param('bh_size','0'); param('bh_stype','0'); param('bh_grp','-1');
	param('bh_net',$q[$#q][0]); param('bh_sdtype','0');
	param('bh_submit','Search');
	goto browse_hosts_jump_point;
      }
    }
  }
  elsif ($sub eq 'browse') {
  browse_hosts_jump_point:
    %bdata=(domain=>'',net=>'ANY',nets=>\%nethash,nets_k=>\@netkeys,
	    type=>1,order=>2,stype=>0,size=>3,grp=>-1);
    if (param('bh_submit')) {
      if (param('bh_submit') eq 'Clear') {
	param('bh_pattern','');
	param('bh_search_txt',''); # TVu 2020-11-03
	param('bh_stype','0');
	param('bh_sdtype','0');
	param('bh_dates','');

	param('bh_type','1');
	param('bh_net','');
	param('bh_cidr','');
	param('bh_domain','');
	param('bh_domain_anydom','');

	param('bh_order','2');
	param('bh_size','0');
	param('bh_grp','-1');
	browse_hosts($state,$perms);
	return;
      }
      if (form_check_form('bh',\%bdata,\%browse_hosts_form)) {
	alert2("Invalid parameters.");
	browse_hosts($state,$perms);
	return;
      }
      $state->{searchopts}=param('bh_type').",".param('bh_order').",".
                   param('bh_size').",".param('bh_stype').",".
		   param('bh_sdtype').",".param('bh_net').",".
                   param('bh_cidr').",".param('bh_dates').",".
#		   param('bh_grp');
		   param('bh_grp').",".param('bh_domain_anydom').",".
		   param('bh_search_txt'); # TVu 2020-11-03
      $state->{searchdomain}=param('bh_domain');
      $state->{searchpattern}=param('bh_pattern');
      $state->{search_txt}=param('bh_search_txt'); # TVu 2020-11-03
      save_state($state->{cookie},$state);
    }
    elsif (param('lastsearch')) {
      if ($state->{searchopts} =~
	  /^(\d+),(\d+),(\d+),(-?\d+),(\d+),(\S*),(\S*),(\S*),(-?\d+),(\S*),(\S*)$/) {
	param('bh_type',$1);
	param('bh_order',$2) unless (param('bh_order'));
	param('bh_size',$3);
	param('bh_stype',$4);
	param('bh_sdtype',$5);
	param('bh_net',$6) if ($6);
	param('bh_cidr',$7) if ($7);
	param('bh_dates',$8) if ($8);
	param('bh_grp',$9);
	param('bh_domain_anydom',$10);
	param('bh_search_txt',$11) if ($11); # TVu 2020-11-03
      } else {
	print h2('No previous search found');
	browse_hosts($state,$perms);
	return;
      }
      param('bh_domain',$state->{searchdomain});
      param('bh_pattern',$state->{searchpattern});
      param('bh_search_txt',$state->{search_txt}); # TVu 2020-11-03
    }

# Assemble sql select clause to find hosts based on user-supplied selection criteria.

    my $typerule;
    my $typerule2;
    my $limit=$browse_page_size{param('bh_size')};
    $limit = 1e8 if ($limit eq 'All');
    $limit='100' unless ($limit > 0);
    my $page=param('bh_page');
    my $offset=$page*$limit;

    $type=param('bh_type');
    if ($type > 0) {
      $typerule=" AND a.type=$type ";
      $typerule=" AND (a.type=$type OR a.type=101) " if ($type==1);
    } else {
#     $typerule2 = " AND (a.type = 1 OR a.type = 6) ";
# Removed type limits for 'Any type' 08.04.2016 TVu
#     $typerule2 = " AND (a.type = 1 OR a.type = 6 OR a.type = 7) ";
      $typerule2 = " AND a.type != 4 "; # Avoids duplicates TVu 04.04.2017
    }
    my $netrule;
    if (param('bh_net') ne 'ANY') {
      $netrule=" AND b.ip << '" . param('bh_net') . "' ";
      $typerule=" AND (a.type=1 OR a.type=6 OR a.type=101) " # Include glue records with "Show
	  if (param('foobar') eq 'Show Hosts');              # Hosts" (subnet). TVu 2021-02-01
    }
    if (param('bh_cidr')) {
      $netrule=" AND b.ip <<= '" . param('bh_cidr') . "' ";
    }
    my $domainrule;
    if (param('bh_domain') ne '') {
      $tmp=param('bh_domain');
# For host names of the form *.domain (CNAME aliases, SRV records). TVu 2020-07-14
      if ($tmp =~ /^\*\./) { $tmp = "\\$tmp"; }
      $domainrule=" AND a.domain ~* " . db_encode_str($tmp) . " ";
    }
    my $grouprule;
    if (param('bh_grp') > 0) {
#	$grouprule=" AND a.grp = " . db_encode_str(param('bh_grp')) . "  ";
# Includes also hosts whose any subgroup matches the selected group. TVu
	$grouprule = ' and a.id in (select h.id from hosts h where h.grp = ' .
	    db_encode_str(param('bh_grp')) .
	    ' union select h.id from hosts h, group_entries ge where ge.grp = ' .
	    db_encode_str(param('bh_grp')) .
	    ' and ge.host = h.id)';
    }

    my $sorder;
    if (param('bh_order') == 1) { $sorder='5,1';  }
    elsif (param('bh_order') == 3) { $sorder='6,1'; }
    elsif (param('bh_order') == 4) { $sorder='7,8,1'; }
    elsif (param('bh_order') == 5) { $sorder='13,1'; }
    elsif (param('bh_order') == 6) { $sorder='14,1'; }
    else { $sorder='1,5'; }

    #if (param('bh_cidr') || param('bh_net') ne 'ANY') {
    #  $type=1;
    #}

    my $extrarule;
    my $from_mx = ''; # 2022-05-12 TVu
    my $where_mx = ''; # 2022-05-12 TVu

#   if (param('bh_pattern')) {

    if (param('bh_pattern') or
	param('bh_stype') >= 0 and $browse_search_f[param('bh_stype')] eq 'has_mx') { # 2022-05-12 TVu

      if (param('bh_stype') >= 0) { $tmp=$browse_search_f[param('bh_stype')]; }
      else { $tmp=''; }
      $tmp2=param('bh_pattern');
      if ($tmp eq 'ether') {
	$tmp2 = "\U$tmp2";
	$tmp2 =~ s/[^0-9A-F]//g;
	print "Searching for MAC address pattern '$tmp2'<br><br>"
	  if (param('bh_pattern') =~ /[^A-Fa-f0-9:\-\ ]/);
	#print "<br>ether=$tmp2";
      }
      elsif ($tmp eq 'duid') {
          $tmp2 = "\U$tmp2";
          $tmp2 =~ s/[^0-9A-F]//g;
          print "Searching for DUID pattern '$tmp2'<br><br>";
      }
      elsif ($tmp eq 'iaid') {
          $tmp2 = "\U$tmp2";
          $tmp2 =~ s/[^0-9A-F]//g;

          if($tmp2 !~ /^\d+$/) {
              $tmp2 = hex($tmp2) if ($tmp2 !~ /^\d+$/ and $tmp2 ne "");
          }

          if(($tmp2 > 0) and ($tmp2 < (2**32))) {
              my $tmp2hex = sprintf("(0x%08x)", $tmp2);
              print "Searching for IAID pattern '$tmp2' $tmp2hex <br><br>";
          }
          else {
              alert2("Invalid pattern for IAID!");
	      browse_hosts($state,$perms);
	      return;
          }
      }


      $tmp2=db_encode_str($tmp2);
      if ($tmp) {
    #Becouse IAID is a number in DB
	  $extrarule= ($tmp ne "iaid" ? " AND a.$tmp ~* $tmp2 " : " AND a.$tmp = $tmp2 ");
	  if ($tmp eq 'hinfo') {
	      $extrarule = " and ( a.hinfo_hw ~* $tmp2 or a.hinfo_sw ~* $tmp2 )";
	  }
	  #print p,$extrarule;
      } else {
	$extrarule= " AND (a.location ~* $tmp2 OR a.huser ~* $tmp2 " .
	  "OR a.dept ~* $tmp2 OR a.info ~* $tmp2 OR a.serial ~* $tmp2 " .
	  "OR a.model ~* $tmp2 OR a.misc ~* $tmp2 OR a.asset_id ~* $tmp2 " .
	  "OR a.hinfo_hw ~* $tmp2 OR a.hinfo_sw ~* $tmp2) ";

# Missing: ether duid iaid

	  #print p,$extrarule;
	#print p,"foobar";
      }

      if ($tmp eq 'has_mx') { # 2022-05-12 TVu
	  $from_mx = ' mx_templates mx, ';
	  $where_mx = ' a.mx = mx.id and mx.zone = z.id and ';
	  if (param('bh_pattern')) {
	      $where_mx .= 'mx.name ~ \'' . param('bh_pattern') . '\' and ';
	  }
	  $extrarule = '';
      }

    }

    my $extrarule2;
    if (param('bh_dates')) {
      $tmp=$browse_search_df[param('bh_sdtype')];
      my $dates = decode_daterange_str(param('bh_dates'));
#     print "$$dates[0] $$dates[1]\n";
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
#     print "extrarule2='$extrarule2'<br>";
    }

#    if ($main::SAURON_PRIVILEGE_MODE==1) {
#      next unless ( $perms->{zone}->{$id} =~ /R/ ||
#		    !check_perms('superuser','',1) );
#    }

# Regular expression search for TXT. TVu 2020-11-03
    my ($txtrule1, $txtrule2);
# If user chose something other than Any type (0), Host (1),
# Plain MX (3) or AREC alias (7), TXT is ignored.
    if (param('bh_search_txt') && param('bh_type') =~ /^(0|1|3|7)$/) {
	$txtrule1 = 'txt_entries te,';
	$txtrule2 = 'and te.type = 2 and te.ref = a.id and te.txt ~* ' .
	    db_encode_str(param('bh_search_txt'));
# If user chose Any type and gave a TXT, only types 1, 3 and 7 are searched.
# These are the only types that should have TXT records.
# The main purpose of this limitation is to avoid finding hosts which represent zones.
	if (param('bh_type') == 0) {
	    $txtrule2 .= ' and (a.type = 1 or a.type = 3 or a.type = 7) ';
	}
    }

# If user didn't select "Any zone", use current zone only.
# If user selected "Any zone", show hosts in any zone the user has read privileges to, unless
# she is a superuser or restrictions are not used, in which case show hosts in all zones.
    my $zonerule = 'TRUE';
    my $combrule1 = 'a.domain';
    my $combrule2 = 'join zones z on a.zone = z.id';
    my $combrule3 = ', zones z';
    my $combrule4 = 'and a.zone = z.id';
    my $serverrule = "and z.server = $serverid";
    if (param('bh_domain_anydom') eq 'on') {
	if ($main::SAURON_PRIVILEGE_MODE == 1 && check_perms('superuser','',1)) {
	    $zonerule = "a.zone in (select ur.rref from user_rights ur, zones z " .
		"where ur.ref = $state->{uid} and ur.type = 2 and ur.rtype = 2 " .
		"and ur.rule ~ 'R' and ur.rref = z.id and z.server = $serverid union " .
		"select ur2.rref from user_rights ur1, user_groups ug, user_rights ur2, zones z " .
		"where ur1.ref = $state->{uid} and ur1.type = 2 and ur1.rtype = 0 " .
		"and ur1.rref = ug.id and ug.id = ur2.ref and ur2.type = 1 and ur2.rtype = 2" .
		" and ur2.rule ~ 'R' and ur2.rref = z.id and z.server = $serverid)";
	}
	$combrule1 = "a.domain || '.' || z.name";
    } else {
	$zonerule = "a.zone = $zoneid";
    }

    undef @q;
#   my $fields="a.id,a.type,a.domain,a.ether,a.info,a.huser,a.dept," .
    my $fields="a.id,a.type,$combrule1,a.ether,a.info,a.huser,a.dept," . # ****
	    "a.location,a.expiration,a.ether_alias, a.duid, a.iaid";
    $fields.=",a.cdate,a.mdate,a.expiration,a.dhcp_date," .
             "a.hinfo_hw,a.hinfo_sw,a.model,a.serial,a.misc,a.asset_id"
	       if (param('csv'));

    my $sql;
    my $sql1="SELECT distinct b.ip,'',$fields " .
#            "FROM hosts a LEFT JOIN a_entries b ON b.host=a.id " .
             "FROM $from_mx $txtrule1 hosts a $combrule2 LEFT JOIN a_entries b ON b.host=a.id " . # $from_mx 2022-05-12 TVu
#	     "WHERE a.zone=$zoneid  $typerule $typerule2 " .
	     "WHERE $where_mx $zonerule $serverrule $typerule $typerule2 $txtrule2 " . # $where_mx 2022-05-12 TVu
	     " $netrule $domainrule $grouprule $extrarule $extrarule2 ";

#   my $sql2="SELECT '0.0.0.0'::cidr,b.domain,$fields FROM hosts a,hosts b " .
#   my $sql2="SELECT '$main::SAURON_ZERO_IP'::cidr,b.domain,$fields FROM hosts a,hosts b " . # For IPv6.
    my $sql2="SELECT '$main::SAURON_ZERO_IP'::cidr,b.domain,$fields FROM $from_mx $txtrule1 hosts a,hosts b$combrule3 " .  # $from_mx 2022-05-12 TVu
#            "WHERE a.zone=$zoneid AND a.alias=b.id AND a.type=4 " .
	     "WHERE $where_mx $zonerule $serverrule and a.alias=b.id AND a.type=4 " .  # $where_mx 2022-05-12 TVu
	     " $domainrule $combrule4 $extrarule $extrarule2 $txtrule2 ";

#   my $sql3="SELECT '0.0.0.0'::cidr,a.cname_txt,$fields FROM hosts a  " .
#   my $sql3="SELECT '$main::SAURON_ZERO_IP'::cidr,a.cname_txt,$fields FROM hosts a " . # For IPv6.
    my $sql3="SELECT '$main::SAURON_ZERO_IP'::cidr,a.cname_txt,$fields FROM $from_mx $txtrule1  hosts a$combrule3 " .  # $from_mx 2022-05-12 TVu
#            "WHERE a.zone=$zoneid AND a.alias=-1 AND a.type=4 " .
             "WHERE $where_mx $zonerule $serverrule and a.alias=-1 AND a.type=4 " . # $where_mx 2022-05-12 TVu
	     " $domainrule $combrule4 $extrarule $extrarule2 $txtrule2 ";

    if ($type == 4) {		# Static aliases and CNAME aliases.
	$sql="$sql2 UNION $sql3 ORDER BY $sorder,2";
    } elsif ($type == 0) {	# Any type.
	$sql="$sql1 UNION $sql2 UNION $sql3 ORDER BY $sorder,3";
    } else {			# Selected type other than alias.
	$sql="$sql1 ORDER BY $sorder,1";
    }
    $sql.=" LIMIT $limit OFFSET $offset;" unless (param('csv'));
#   print "<br>$sql";
    db_query($sql,\@q);
    my $count=scalar @q;
    if ($count < 1) {
#     alert2("No matching records found.");
      alert2('No matching records found' .
	     (param('bh_domain_anydom') eq 'on' ? '' : ' in this zone') . '.'); # 14 Jun 2017 TVu
      browse_hosts($state,$perms);
      return;
    }

    #print "\n",url(-path_info=>1,-query=>1),"\n";

    if (param('csv')) {
      printf print_csv(['Domain','Type','IP','Ether','DUID', 'IAID', 'User','Dept.',
	                 'Location','Info','Hardware','Software',
			 'Model','Serial','Misc','AssetID',
			 'cdate','mdate','edate','dhcpdate'],1) . "\n";

      my $csv_fmt = $csv_timestamp_f[param('csv') -1];

      for $i (0..$#q) {
	$q[$i][5]=dhcpether($q[$i][5])
	  unless (dhcpether($q[$i][5]) eq '00:00:00:00:00:00');
	my $host_ty = $host_types{$q[$i][3]};
	if ($host_ty eq 'Alias') { # TVu 08.04.2016
	    get_host($q[$i][2], \%host);
	    if ($host{'cname_alias'}) { $host_ty = 'CNAME Alias'; }
	    else { $host_ty = 'Static Alias'; }
	}
#	printf print_csv([ $q[$i][4],$host_types{$q[$i][3]},$q[$i][0],
	printf print_csv([ $q[$i][4],$host_ty,$q[$i][0], # TVu 08.04.2016
	                   $q[$i][5],$q[$i][12],$q[$i][13], $q[$i][7],$q[$i][8],$q[$i][9],
			   $q[$i][6],$q[$i][18],$q[$i][19],
			   $q[$i][20],$q[$i][21],$q[$i][22],$q[$i][23],
			   utimefmt($q[$i][14],$csv_fmt),
			   utimefmt($q[$i][15],$csv_fmt),
			   utimefmt($q[$i][16],$csv_fmt),
			   utimefmt($q[$i][17],$csv_fmt)
			 ],1) . "\n";
      }

      #print "\n",url(-path_info=>1,-query=>1),"\n";

      return;
    }

    if ($count == 1) {
      param('h_id',$q[0][2]);
      show_host_record($state,$perms);
      return;
    }

    #    print "<TABLE width=\"99%\" cellspacing=1 cellpadding=1 border=0 " .
    #          "BGCOLOR=\"ffffff\">",
    #          "<TR><TD><B>Zone:</B> $zone</TD>",
    #          "<TD align=right>Page: ".($page+1)."</TD></TR></TABLE>";

    print "<TABLE width=\"99%\" cellspacing=1 cellpadding=1 border=0 " .
	  "BGCOLOR=\"ffffff\"><TR>"; # ****
    print "<TD><B>Zone:</B> $zone</TD>" unless (param('bh_domain_anydom') eq 'on'); # ****
    if (param('bh_net') && param('bh_net') ne 'ANY') { # ****
	my @net;
	db_query("SELECT netname, name FROM nets " .
		 "WHERE net = '" . param('bh_net') . "'", \@net);
	print '<TD><B>Net:</B> ' . param('bh_net') . " &ndash; $net[0][0] &ndash; $net[0][1]<TD>";
    }
    print "<TD align=right>Page: ".($page+1)."</TD></TR></TABLE>"; # ****

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
	if ($ip =~ /:/) {
	    alert1('Ping Sweep for IPv6 not implemented yet');
	    return;
	}
	push @pingiplist, $ip;
      }

      print h3("Please wait..." .
	       "Running Ping sweep ($pingiplist[0]..$pingiplist[-1])...");
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
	  "<a href=\"$sorturl&bh_order=5\">DUID</a>",
	  "<a href=\"$sorturl&bh_order=6\">IAID</a>",
	  "<a href=\"$sorturl&bh_order=4\">Info</a>"]);

    for $i (0..$#q) {
      my($nro,$ip);
      my $type=$q[$i][3];
      ($ip=$q[$i][0]) =~ s/\/\d{1,3}$//g; # 2 -> 3 for IPv6.
      $ip="(".add_origin($q[$i][1],$zone).")" if ($type==4);
#     $ip='N/A' if ($ip eq '0.0.0.0');
      $ip='N/A' if ($ip eq '0.0.0.0' or # For IPv6.
		    ipv6compress(cidr64ok($ip) ? ipv64unmix($ip) : $ip) eq '::');
      my $ether=$q[$i][5];
      # $ether =~  s/^(..)(..)(..)(..)(..)(..)$/\1:\2:\3:\4:\5:\6/;
      $ether='<font color="#009900">ALIASED</font>' if ($q[$i][11] > 0);
      $ether='<font color="#990000">N/A</a>' unless($ether);
      my $duid = $q[$i][12];
      $duid = '<font color="#990000">N/A</a>' unless($duid);
      my $iaid = $q[$i][13];
      my $iaidhex;

      unless($iaid) {
        $iaid = '<font color="#990000">N/A</a>';
        $iaidhex = '';
      }
      else {
        $iaidhex = sprintf("(0x%08x)", $iaid);
      }

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
      my $host_ty = $host_types{$q[$i][3]};
      if ($host_ty eq 'Alias') { # TVu 08.04.2016
	  get_host($q[$i][2], \%host);
	  if ($host{'cname_alias'}) { $host_ty = 'CNAME Alias'; }
	  else { $host_ty = 'Static Alias'; }
      }
      print "<TR bgcolor=\"$trcolor\">",
	    td([$nro, $hostname,
#		"<FONT size=-1>$host_types{$q[$i][3]}</FONT>",$ip,
		"<FONT size=-1>$host_ty</FONT>",$ip,
	        "<font size=-3 face=\"courier\">$ether&nbsp;</font>",
	        "<font size=-3 face=\"courier\">$duid&nbsp;</font>",
	        "<font size=-3 face=\"courier\">$iaid $iaidhex</font>",
	        "<FONT size=-1>".$info."&nbsp;</FONT>"]),"</TR>";

    }
    print "</TABLE><BR><CENTER>[";

    my $params="bh_type=".param('bh_type')."&bh_order=".param('bh_order').
             "&bh_net=".param('bh_net')."&bh_cidr=".param('bh_cidr').
	     "&bh_stype=".param('bh_stype')."&bh_pattern=".param('bh_pattern').
	     "&bh_search_txt=".param('bh_search_txt'). # TVu 2020-11-03
	     "&bh_domain=".param('bh_domain')."&bh_domain_anydom=".param('bh_domain_anydom'). # ****
	     "&bh_size=".param('bh_size')."&bh_grp=".param('bh_grp');

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

#    print "]</CENTER><BR>",
#          "<div align=right><font size=-2>",
#          "<a title=\"foo.csv\" href=\"$sorturl&csv=1\">",
#          "[Download results in CSV format]</a> &nbsp;</font></div>";

    print "]</CENTER><BR>\n";

    print "<table width=100% border=0 cellspacing=5 cellpadding=5 align=top>" .
	"<tr><td>"; #  width=50%

    if ($main::SAURON_NMAP_PROG && param('bh_type') == 1 &&
	!check_perms('level',$main::ALEVEL_NMAP,1)) {
	print start_form(-method=>'POST',-action=>$selfurl),
	hidden('menu','hosts'),hidden('sub','browse'),
	hidden('bh_page',$page),
	hidden('lastsearch','1'),hidden('pingsweep','1');
	print submit(-name=>'foobar',-value=>'Ping Sweep');
	print end_form;
    }
# Create buttons for Net and Net Info if a cidr was passed as parameter.
    if (param('bh_net') && is_cidr(param('bh_net'))) {
	my $old_menu = param('menu');
	my $old_sub = param('sub');
	param('menu', 'nets');
	param('sub', 'Net Info');
	print "</td><td>";
	print "\n\n",start_form(-method=>'GET',-action=>$selfurl),
	hidden('menu','nets'),"\n",
	hidden('net_id',get_net_by_cidr($serverid, param('bh_net'))),"\n";
	print submit(-name=>'foobar',-value=>'Net');
	print end_form,"\n\n";
	print "</td><td>";
	print start_form(-method=>'GET',-action=>$selfurl),
	hidden('menu','nets'),"\n",hidden('sub','Net Info'),"\n",
	hidden('net_id',get_net_by_cidr($serverid, param('bh_net'))),"\n";
	print submit(-name=>'foobar',-value=>'Net Info');
	print end_form,"\n\n";
	param('menu', $old_menu);
	param('sub', $old_sub);
    }

    print "</td><td><div align=right>";

    my $csv_timestamp_v=[sort keys %csv_timestamp];
    print start_form(-method=>'POST',-action=>$selfurl),
	    hidden('menu','hosts'),hidden('sub','browse'),
            hidden('lastsearch','1'),
            "CSV Timestamps&nbsp;",
            popup_menu(-name=>'csv',-values=>$csv_timestamp_v,
		       -labels=>\%csv_timestamp),
            submit(-name=>'results.csv',-value=>'Download CSV');

    print end_form;

    print "</div></td></tr></table>\n";

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

    # Use default host name template, if defined. TVu 02 Jun 2015
    if ($perms->{defhost}) {
	$data{domain} = $perms->{defhost};
	# $newhostform->{defhost} = 1;
    }
    $newhostform->{defhost} = 1; # Allow anyone to use variable %{id} to name hosts. TVu 23 May 2017

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
	show_host_record($state,$perms);
	return;
      }
      return;
    }
    elsif (param('addhost_submit')) {

      # Adding a Static alias. As if the data had come from the database
      # (as it appears when editing a Static alias). 2020-07-16 TVu
      if ($type == 4) { $data{'static_alias'} = 1; }

      unless (($res=form_check_form('addhost',\%data,$newhostform))) {
	if (($data{type}==1 || $data{type} == 101) && $data{net} ne 'MANUAL' &&
	    not is_cidr($data{ip})) {
	  # my $tmpnet=new Net::Netmask($data{net});
	  # $ip=auto_address($serverid,$tmpnet->desc());
	  # print "$data{net}\n";
	  # $ip=auto_address($serverid,$data{net});
	  # print $data{net} . "<br>\n";
	  $ip = get_free_ip_by_net($serverid, $data{net}, $data{ether}, '',
				   get_net_ip_policy($serverid, $data{net}));
	  unless (is_cidr($ip)) {
	    logmsg("notice","get_free_ip_by_net($serverid, $data{net}, '" .
		   "$data{ether}', '', " . get_net_ip_policy($serverid, $data{net}) . ") failed!");
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
	    show_host_record($state,$perms);
	    return;
	  } else {
	    alert1("Cannot add host record!");
	    if (db_lasterrormsg() =~ /ether_key/) {
	      alert2("Duplicate MAC (Ethernet) address $data{ether}");
	      db_query("SELECT id,domain FROM hosts " .
		       "WHERE ether='$data{ether}' AND zone=$zoneid",\@q);
	      if ($q[0][0] > 0) {
		print "Conflicting host: ",
  	          "<a href=\"$selfurl?menu=hosts&h_id=$q[0][0]\">$q[0][1]</a>";
	      }
	    } elsif(db_lasterrormsg() =~ /duid_key/) {
              alert2("Duplicate DUID $data{duid}");
              db_query("SELECT id,domain FROM hosts " .
                       "WHERE duid='$data{duid}' AND zone=$zoneid",\@q);
              if ($q[0][0] > 0) {
                print "Conflicting host: ",
                  "<a href=\"$selfurl?menu=hosts&h_id=$q[0][0]\">$q[0][1]</a>";
              }
            }
          elsif(db_lasterrormsg() =~ /duid_iaid_key/) {
              alert2("Duplicate DUID+IAID $data{duid} - $data{'iaid'}");
              db_query("SELECT id,domain FROM hosts " .
                       "WHERE duid='$data{duid}' AND iaid='$data{'iaid'}' AND zone=$zoneid",\@q);
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

    print start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','hosts'),hidden('sub','add'),hidden('type',$type);
    print hidden('copy_id') if (param('copy_id'));
    if (param('select_ip')) { # select_ip exists only when host is added using Copy TVu 15.03.2017
	$data{ip_policy} = get_net_ip_policy($serverid, param('select_ip'));
    }
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
    delete $data{duid};
    delete $data{iaid};
    delete $data{serial};
    delete $data{asset_id};
    # Selected IP address instead of the first one only.
    # $data{ip}=$host{ip}[1][1];
    # $data{ip} = param('select_ip');
    $data{ip} = param('select_ip') if (param('select_ip') =~ /\./); # IPv4 only. ****
    $data{preselectnet} = get_net_cidr_by_ip($serverid, param('select_ip'));
    $type=$host{type};
    param('copy_id',$id);
    param('sub','add');
    if ($host{domain} =~ /^([^\.]+)(\..*)?$/) {
      $p1=$1; $p2=$2;
      if ($p1 =~ /(\d+)/) {
	my $p3len=length(($p3=$1));
	# Added checks for hostname_in_use, TVu 20.11.2012.
	do {
	    $p4 = sprintf("%0${p3len}d",$p3+1);
	    $p1 =~ s/${p3}/${p4}/;
	    $data{domain}=$p1.$p2;
	    $p3++;
	} while hostname_in_use($zoneid, $data{domain});
      } else {
	  $p3 = 2;
	  do {
	      $data{domain}=$p1.$p3.$p2;
	      $p3++;
	  } while hostname_in_use($zoneid, $data{domain});
      }
    }
    # Use default host name template, if defined. TVu 02 Jun 2015
    if ($perms->{defhost}) {
	$data{domain} = $perms->{defhost};
	# $newhostform->{defhost} = 1;
    }
    $newhostform->{defhost} = 1; # Allow anyone to use variable %{id} to name hosts. TVu 23 May 2017
    # New ip by network policy instead of 'next free'. This really only works for Lowest or Highest free.
    # $data{ip}=$newip if (($newip=next_free_ip($serverid,$data{ip})));
    $data{ip} = $newip if (is_ip($newip = get_free_ip_by_net($serverid, $data{preselectnet},
				     '', '', get_net_ip_policy($serverid, $data{preselectnet}))));
    #   print "$serverid $data{preselectnet}<br>\n";
    goto copy_add_label;
  }

  if (param('h_id')) {
    show_host_record($state,$perms);
  } else {
    browse_hosts($state,$perms);
  }

}


1;
# eof
