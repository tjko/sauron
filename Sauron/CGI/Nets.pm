# Sauron::CGI::Nets.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id$
#
package Sauron::CGI::Nets;
require Exporter;
use CGI qw/:standard *table -no_xhtml/;
use Sauron::Util;
use Sauron::DB;
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

my (%vlan_list_hash,@vlan_list_lst);

my %new_net_form=(
 data=>[
  {ftype=>1, tag=>'netname', name=>'NetName', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'name', name=>'Description', type=>'text',
   len=>60, empty=>0},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>4, tag=>'dummy', name=>'Virtual subnet', type=>'enum',
   enum=>{t=>'Yes',f=>'No'},iff=>['subnet','t']},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, empty=>1}
 ]
);

my %net_form=(
 data=>[
  {ftype=>0, name=>'Net'},
  {ftype=>1, tag=>'netname', name=>'NetName', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'name', name=>'Description', type=>'text',
   len=>60, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>4, tag=>'subnet', name=>'Type', type=>'enum',
   enum=>{t=>'Subnet',f=>'Net'}},
  {ftype=>4, tag=>'dummy', name=>'Virtual subnet', type=>'enum',
   enum=>{t=>'Yes',f=>'No'},iff=>['subnet','t']},
  {ftype=>1, tag=>'net', name=>'Net (CIDR)', type=>'cidr'},
  {ftype=>3, tag=>'vlan', name=>'VLAN', type=>'enum', conv=>'L',
   enum=>\%vlan_list_hash, elist=>\@vlan_list_lst, restricted=>1,
   iff=>['dummy','f']},
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
  {ftype=>0, name=>'DHCP',iff=>['dummy','f']},
  {ftype=>3, tag=>'no_dhcp', name=>'DHCP', type=>'enum', conv=>'L',
   enum=>{f=>'Enabled',t=>'Disabled'},iff=>['dummy','f']},
  {ftype=>2, tag=>'dhcp_l', name=>'Net specific DHCP entries',
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment'],
   iff=>['dummy','f']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ],
 mode=>1
);


my %vmps_form=(
 data=>[
  {ftype=>0, name=>'VMPS Domain'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>4, tag=>'id', name=>'ID', no_edit=>0},
  {ftype=>1, tag=>'description', name=>'Description', type=>'text',
   len=>60, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text',
   len=>60, empty=>1},

  {ftype=>3, tag=>'mode', name=>'Mode', type=>'enum', conv=>'L',
   enum=>{0=>'Open',1=>'Secure'}},
  {ftype=>3, tag=>'nodomainreq', name=>'no-domain-req',
   type=>'enum', conv=>'L', enum=>{0=>'Allow',1=>'Deny'}},
  {ftype=>3, tag=>'fallback', name=>'Fallback VLAN', type=>'enum', conv=>'L',
   enum=>\%vlan_list_hash, elist=>\@vlan_list_lst, restricted=>0},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);


my %vlan_form=(
 data=>[
  {ftype=>0, name=>'VLAN (Layer-2 Network / Shared Network)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle',
   len=>32, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID', no_edit=>0},
  {ftype=>1, tag=>'vlanno', name=>'VLAN No.', type=>'priority',
   len=>5, empty=>1},
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

my %new_vlan_form=(
 data=>[
  {ftype=>0, name=>'VLAN (Layer-2 Network / Shared Network)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle',
   len=>32, conv=>'L', empty=>0},
  {ftype=>1, tag=>'vlanno', name=>'VLAN No.', type=>'priority',
   len=>5, empty=>1},
  {ftype=>1, tag=>'description', name=>'Description', type=>'text',
   len=>40, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text',
   len=>60, empty=>1}
 ]
);


my %net_info_form=(
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



# NETS menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my(@q,$i,$res,$comment,$netname,$vlan,$type,$name,$dhcp,$ip,$info,$novlans);
  my (%data,%net,%vlan,,%vmps,%nmaphash,%netmap);
  my (@vlan_list,@pingsweep,@iplist,@pingiplist,@blocks);

  my $serverid = $state->{serverid};
  my $selfurl = $state->{selfurl};

  my $sub=param('sub');
  my $id=param('net_id');
  my $v_id=param('vlan_id');
  my $vm_id=param('vmps_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

 show_vmps_record:
  if ($vm_id > 0) {
      return if (check_perms('level',$main::ALEVEL_VLANS));
      if (get_vmps($vm_id,\%vmps)) {
	  alert2("Cannot get vmps record (id=$vm_id)");
	  return;
      }
      get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list_lst);
      $vlan_list_hash{-2}='--Default--';
      unshift @vlan_list_lst, -2;

      if ($sub eq 'Edit') {
	  return if (check_perms('superuser',''));
	  $res=edit_magic('vmps','VMPS Domain','vmps',\%vmps_form,
			  \&get_vmps,\&update_vmps,$vm_id);
	  return unless ($res == 2 || $res == 1);
	  get_vmps($vm_id,\%vmps);
      }
      elsif ($sub eq 'Delete') {
	  return if (check_perms('superuser',''));
	  $res=delete_magic('vmps','VMPS Domain','vmps',\%vmps_form,
			    \&get_vmps,\&delete_vmps,$vm_id);
	  return unless ($res == 2);
	  get_vlan($v_id,\%vlan);
      }

      display_form(\%vmps,\%vmps_form);
      print p,startform(-method=>'GET',-action=>$selfurl),
            hidden('menu','nets'),hidden('vmps_id',$vm_id);
      print submit(-name=>'sub',-value=>'Edit'), "  ",
            submit(-name=>'sub',-value=>'Delete'), " &nbsp;&nbsp;&nbsp; "
	    unless (check_perms('superuser','',1));
      print end_form;
      return;
  }
 show_vlan_record:
  if ($v_id > 0) {
      return if (check_perms('level',$main::ALEVEL_VLANS));

      if (get_vlan($v_id,\%vlan)) {
	  alert2("Cannot get vlan record (id=$v_id)");
	  return;
      }

      if ($sub eq 'Edit') {
	  return if (check_perms('superuser',''));
	  $res=edit_magic('vlan','VLAN','vlans',\%vlan_form,
			  \&get_vlan,\&update_vlan,$v_id);
	  return unless ($res == 2 || $res == 1);
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

  if ($sub eq 'vmps') {
      return if (check_perms('level',$main::ALEVEL_VLANS));
      undef @q;
      db_query("SELECT id,name,description,comment FROM vmps " .
	       "WHERE server=$serverid ORDER BY name;",\@q);
      print h3("VMPS Domains");
      for $i (0..$#q) {
	$q[$i][1]="<a href=\"$selfurl?menu=nets&vmps_id=$q[$i][0]\">".
	          "$q[$i][1]</a>";
      }
      display_list(['Name','Description','Comments'],\@q,1);
      print "<br>";
      return;
  }
  elsif ($sub eq 'vlans') {
    browse_vlans:
      return if (check_perms('level',$main::ALEVEL_VLANS));
      undef @q;
      db_query("SELECT id,name,vlanno,description,comment FROM vlans " .
	       "WHERE server=$serverid ORDER BY name;",\@q);
      print h3("VLANs");
      for $i (0..$#q) {
	$q[$i][1]="<a href=\"$selfurl?menu=nets&vlan_id=$q[$i][0]\">".
	          "$q[$i][1]</a>";
      }
      display_list(['Name','VLAN No.','Description','Comments'],\@q,1);
      print "<br>";
      return;
  }
  elsif ($sub eq 'addvmps') {
    return if (check_perms('superuser',''));
    get_vlan_list($serverid,\%vlan_list_hash,\@vlan_list_lst);
    $data{server}=$serverid;
    $res=add_magic('addvmps','VMPS Domain','vmps',\%vmps_form,
		   \&add_vmps,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $vm_id=$res;
      goto show_vmps_record;
    }
    print db_lasterrormsg();
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
    $data{dummy}='f';
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
    $data{dummy}='f';
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
  elsif ($sub eq 'addvsub') {
    return if (check_perms('superuser',''));
    $data{subnet}='t';
    $data{dummy}='t';
    $data{server}=$serverid;
    $res=add_magic('addnet','Virtual Subnet','nets',\%new_net_form,
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
    my $si;
    my $sta;
    my $nstate;

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

    my $netmask = new Net::Netmask($net{net});
    $net{base}=$netmask->base();
    $net{netmask}=$netmask->mask();
    $net{hostmask}=$netmask->hostmask();
    $net{broadcast}=$netmask->broadcast();
    $net{size}=$netmask->size();
    $net{first}=$netmask->nth(1);
    $net{last}=$netmask->nth(-2);
    $net{ssize}=$netmask->size()-2;
    $net{inusep}=sprintf("%3.0f", ($net{inuse} / $net{size})*100) ."%";

    $sta=($netmap{$net{first}} > 0 ? 1 : 0);
    $si=1;
    for $i (1..($netmask->size()-1)) {
      $ip=$netmask->nth($i);
      $nstate=($netmap{$ip} > 0 ? 1 : 0);
      if ($nstate != $sta) {
	push @blocks, [$sta,($i-$si),$netmask->nth($si),$netmask->nth($i-1)];
	$si=$i;
      }
      $sta=$nstate;
    }
    $i=$netmask->size()-1;
    push( @blocks, [$sta,($i-$si),$netmask->nth($si),$netmask->nth($i-1)] )
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
      $sta=0;
      $sta=1 if ($q[0][0] =~ /^($net{first})(\/32)?/);
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
    update_history($state->{uid},$state->{sid},4,"Net PING Sweep",
		   "net: $net{net}",$net{id});
    undef @pingiplist;
    push @pingiplist, $net{net};
    $res = run_ping_sweep(\@pingiplist,\%nmaphash,$state->{user});
    if ($res < 0) {
      alert2("Ping Sweep not configured!");
    } elsif ($res == 1) {
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
	my $status;
	my $domain;
	my $hid;

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
    if (check_perms('level',$main::ALEVEL_VLANS,1)) {
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
            unless (check_perms('level',$main::ALEVEL_NMAP,1));
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
  db_query("SELECT id,name,net,subnet,comment,no_dhcp,vlan,netname,alevel," .
	   "dummy FROM nets " .
	   "WHERE server=$serverid AND alevel <= $perms->{alevel} " .
	   "ORDER BY net;",\@q);
  if (@q < 1) {
    print h2("No networks found!");
    return;
  }
  if (check_perms('level',$main::ALEVEL_VLANS,1)) {
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

  my @path;
  push @path, '0.0.0.0/0';
  my $listmode = param('list');

  for $i (0..$#q) {
    if ($listmode =~ /^(sub|)$/) {
      next if ($q[$i][9] =~ /(t|1)/);
    }
    if ($listmode =~ /^\s*$/) {
      next if ($q[$i][3] =~ /(t|1)/);
    }

    my $parent = $path[-1];
    if (is_cidr_within_cidr($q[$i][2],$parent)) {
      push @path, $q[$i][2];
    } else {
      do {
	pop @path;
	$parent = $path[-1];
      } while (@path > 0 && not is_cidr_within_cidr($q[$i][2],$parent));
      push @path, $q[$i][2];
    }


    $dhcp=(($q[$i][5] eq 't' || $q[$i][5] == 1) ? 'No' : 'Yes' );
    if ($q[$i][3] =~ /(1|t)/) {
      if ($q[$i][9] =~ /(1|t)/) {
	print "<TR bgcolor=\"#bfeeee\">";
	$type='Virtual';
      } else {
	print $dhcp eq 'Yes' ? "<TR bgcolor=\"#eeeebf\">" :
	  "<TR bgcolor=\"#eeeeee\">";
	$type='Subnet';
      }
    } else {
      print "<TR bgcolor=\"#ddffdd\">";
      $type='Net';
    }

    my $spacer = "&nbsp;&nbsp;" x ($#path -1);
    $vlan=($q[$i][6] > 0 ? $vlan_list_hash{$q[$i][6]} : '&nbsp;');
    $netname=($q[$i][7] eq '' ? '&nbsp;' : $q[$i][7]);
    $name=($q[$i][1] eq '' ? '&nbsp;' : $q[$i][1]);
    $comment=$q[$i][4];
    $comment='&nbsp;' if ($comment eq '');
    print "<td>$spacer<a href=\"$selfurl?menu=nets&net_id=$q[$i][0]\">",
	  "$q[$i][2]</a></td>",td($netname),
          td("<FONT size=-1>$name</FONT>"), td("<FONT size=-1>$type</FONT>"),
          td("<FONT size=-1>$dhcp</FONT>"),
	  ($novlans?'':td("<FONT size=-1>$vlan</FONT>")),
	  # td("<FONT size=-1>$comment</FONT>"),
	  td($q[$i][8].'&nbsp;'),"</TR>";
  }

  print "</TABLE>&nbsp;";
}




1;
# eof
