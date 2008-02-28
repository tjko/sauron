# Sauron::CGI::Servers.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003-2005.
# $Id$
#
package Sauron::CGI::Servers;
require Exporter;
use CGI qw/:standard *table -no_xhtml/;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::CGI::Utils;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );


my %server_form = (
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
  {ftype=>12, tag=>'allow_transfer', name=>'Allow-transfer',
   iff=>['named_flags_ac','0']},
  {ftype=>12, tag=>'allow_query', name=>'Allow-query',
   iff=>['named_flags_ac','0']},
  {ftype=>12, tag=>'allow_query_cache', name=>'Allow-query-cache',
   iff=>['named_flags_ac','0']},
  {ftype=>12, tag=>'allow_recursion', name=>'Allow-recursion',
   iff=>['named_flags_ac','0']},
  {ftype=>12, tag=>'allow_notify', name=>'Allow-notify',
   iff=>['named_flags_ac','0']},
  {ftype=>12, tag=>'blackhole', name=>'Blackhole',
   iff=>['named_flags_ac','0']},

  {ftype=>0, name=>'BIND settings'},
  {ftype=>2, tag=>'bind_globals', name=>'Global BIND settings',
   type=>['text','text'], fields=>2, len=>[50,20], maxlen=>[100,20],
   empty=>[0,1], elabels=>['BIND globals','comment']},

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

my %master_servers;
my @master_serversl;

my %new_server_form=(
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


# SERVERS menu
#
sub menu_handler {
  my ($state,$perms) = @_;

  my $sub=param('sub');

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $scookie = $state->{cookie};

  $server_form{serverid}=$serverid;
  $server_form{zoneid}=$state->{zoneid};

  my($res,%data,%serv,%srec,@l,$server);

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
	$state->{'zone'}=''; $state->{'zoneid'}=-1;
	$state->{'server'}=''; $state->{'serverid'}=-1;
	save_state($scookie,$state);
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
    unless ($serverid > 0) {
      print h3("Cannot select server!"),p;
      goto select_server;
    }
    my $serveridsave = $state->{'serverid'};
    $state->{'serverid'}=$serverid;
    my $pcheck = check_perms('server','R');
    $state->{'serverid'}=$serveridsave;
    goto select_server if ($pcheck);
    get_server($serverid,\%serv);
    $server=$serv{name};
    print h2("Selected server: $server"),p;
    if ($state->{'serverid'} ne $serverid) {
      $state->{'zone'}='';
      $state->{'zoneid'}=-1;
      $state->{'server'}=$server;
      $state->{'serverid'}=$serverid;
      save_state($scookie,$state);
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



1;
# eof
