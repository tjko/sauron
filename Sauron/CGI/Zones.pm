# Sauron::CGI::Zones.pm
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id:$
#
package Sauron::CGI::Zones;
require Exporter;
use CGI qw/:standard *table -utf8/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::Util;
use Sauron::CGI::Utils;
use strict;
use vars qw($VERSION @ISA @EXPORT);
use Sys::Syslog qw(:DEFAULT setlogsock);
Sys::Syslog::setlogsock('unix');

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


my %new_zone_form=(
 data=>[
  {ftype=>0, name=>'New zone'},
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'zonename',
   len=>72, empty=>0},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward'}},
  {ftype=>3, tag=>'reverse', name=>'Reverse', type=>'enum',  conv=>'L',
   enum=>{f=>'No',t=>'Yes'}}
 ]
);


my %zone_form = (
 data=>[
  {ftype=>0, name=>'Zone' },
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'zonename', len=>72},
  {ftype=>4, tag=>'reversenet', name=>'Reverse net', iff=>['reverse','t']},
  {ftype=>4, tag=>'id', name=>'Zone ID'},
# {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>60,
#  empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, # TVu.
   empty=>1, anchor=>1, whitesp=>'P'},
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
   len=>[43,45], empty=>[0,1], elabels=>['IP','comment'], iff=>['type','S']},
  {ftype=>1, tag=>'hostmaster', name=>'Hostmaster', type=>'domain', len=>30,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','M']},
  {ftype=>3, tag=>'chknames', name=>'Check-names', type=>'enum',
   conv=>'U', enum=>\%check_names_enum},
  {ftype=>3, tag=>'nnotify', name=>'Notify', type=>'enum', conv=>'U',
   enum=>\%yes_no_enum, iff=>['type','M']},
  {ftype=>3, tag=>'forward', name=>'Forward', type=>'enum', conv=>'U',
   enum=>{D=>'Default',O=>'Only',F=>'First'}, iff=>['type','F'] },
  {ftype=>1, tag=>'transfer_source', name=>'Transfer-Source (address)',
   type=>'ip4', len=>39,
   empty=>1, definfo=>['','Default (from server)'], iff=>['type','S']},
  {ftype=>1, tag=>'transfer_source_v6', name=>'Transfer-Source (IPv6 address)',
   type=>'ip6', len=>39,
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
  {ftype=>5, tag=>'ip', name=>'IP addresses', iff=>['type','M'],
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'ns', name=>'Name servers (NS)', type=>['fqdn','text'],
   fields=>2, whitesp=>['','P'], maxlen=>[400,20],
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment'], iff=>['type','M']},
  {ftype=>2, tag=>'mx', name=>'Mail exchanges (MX)', maxlen=>[5,400,20],
#  type=>['int','text','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   type=>['int','mx','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], whitesp=>['','','P'], iff=>['type','M'],
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'txt', name=>'Info (TXT)', type=>['text','text'], fields=>2,
   len=>[68,15], maxlen=>[220,15], empty=>[0,1], elabels=>['TXT','comment'], whitesp=>['P','P'],
   iff=>['type','M'], iff2=>['reverse','f']},

# New version of Custom zone file entries: Multiple textareas instead
# of multiple indivdual rows. Single column. 2020-07-30 TVu
  {ftype => 2, tag => 'zentries_ta', name => 'Custom Zone File Entries (current)',
   type => ['area'], fields => 1, rows => 6, len => [90], linelen => [253], # [15],
   empty => [0], elabels => ['Zone Entries (current)'],
   extrainfo => 'Use zone file syntax', whitesp => ['N'], iff => ['type', 'M'] },

# -------------------------------------------------------------------------------
# Custom zone file entries have been changed into a textarea to make editing
# easier, but this changes the way data is stored in DB, and if the new code is
# used in production environment, there is no way to go back, should bugs be
# found. For this reason, the new code is not used at this time (18 May 2017),
# though it will be activated once it has been properly tested. [TVu]

# Old code, still in use.
  {ftype=>2, tag=>'zentries', name=>'Custom zone file entries (depre&shy;cated)',
   type=>['text','text'], fields=>2, len=>[68,15], maxlen=>[255,20],
   empty=>[0,1], elabels=>['Zone Entry (deprecated)','Comment'], whitesp=>['N','P'],
   iff=>['type','M']},

# New code, will be used later.
#  {ftype=>13, tag=>'zentries', name=>'Custom zone file entries', type=>'cust_entr', # Textarea 12 Apr 2017 TVu
#   linelen=>220, rows=>10, cols=>100, empty=>1, whitesp=>'N', iff=>['type','M']},

# Another similar significant change is in BackEnd.pm (sub update_zone). Most
# of the changes are in CGIutil.pm, but there is no need to change that file to
# start using the new version. Search the word 'textarea' to find the changes.
# -------------------------------------------------------------------------------

  {ftype=>12, tag=>'allow_update', whitesp=>['','','','','','P'],
   name=>'Allow dynamic updates (allow-update)', iff=>['type','M']},
  {ftype=>12, tag=>'allow_query', whitesp=>['','','','','','P'],
   name=>'Allow queries from (allow-query)'},
  {ftype=>12, tag=>'allow_transfer', whitesp=>['','','','','','P'],
   name=>'Allow zone-transfers from (allow-transfer)', iff=>['type','M']},
  {ftype=>2, tag=>'also_notify',
   name=>'[Stealth] Servers to notify (also-notify)', type=>['ip','text'],
   fields=>2, len=>[39,15], empty=>[0,1], elabels=>['IP','comment'],
   whitesp=>['','P'], iff=>['type','M']},
  {ftype=>2, tag=>'forwarders',name=>'Forwarders', type=>['ip','int','text'],
   fields=>3, len=>[39,6,15], empty=>[0,1,1], elabels=>['IP','Port','comment'],
   iff=>['type','F']},

  {ftype=>0, name=>'DHCP', iff=>['type','M']},
  {ftype=>2, tag=>'dhcp', name=>'Zone specific DHCP entries',
   type=>['text','text'], fields=>2, maxlen=>[200,20], whitesp=>['N','P'],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment'], iff=>['type','M']},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1},
  {ftype=>1, name=>'Expiration date', tag=>'expiration', len=>30,
   type=>'expiration', empty=>1},
  {ftype=>4, name=>'Pending host record changes', tag=>'pending_info',
   no_edit=>1, iff=>['type','M']}
 ]
);



my %copy_zone_form=(
 data=>[
  {ftype=>0, name=>'Source zone'},
  {ftype=>4, tag=>'source', name=>'Source zone'},
  {ftype=>0, name=>'Target zone'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'domain', len=>40, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1, whitesp=>'P'}
 ]
);


# ZONES menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my($i,@q,$res,%data,%zonelist,%server,%zone);

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};
  my %ztypenames=(M=>'Master',S=>'Slave',F=>'Forward',H=>'Hint');

  $zone_form{serverid}=$state->{serverid};
  $zone_form{zoneid}=$state->{zoneid};

# Zone names are used when checking lengths of domain names,
# unless they are FQDNs. TVu 2020-06-01
  $zone_form{'zonename'} = $state->{zone};

  my $sub=param('sub');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

# Write CSV list with the same content as the selection list.
  if (param('csv')) {
      print print_csv(['#','Zone','Type','Reverse','Comments'], 1) . "\n";
      # 2022-08-10 mesrik: add expired last arg, no skipping here
      # my $list=get_zone_list($serverid,0,0);
      my $list=get_zone_list($serverid,0,0,0);
      my $ord = 1;
      for $i (0 .. $#{$list}) {
	  my $type=$ztypenames{$$list[$i][2]};
	  my $rev=(($$list[$i][3] eq 't' || $$list[$i][3] == 1) ? 'Yes' : 'No');
	  my $id=$$list[$i][1];
	  my $name=$$list[$i][0];
	  my $comment=$$list[$i][4];
	  my $filter = param('select_filter');
	  if ($main::SAURON_PRIVILEGE_MODE==1) {
	      next unless ( $perms->{zone}->{$id} =~ /R/ ||
			    !check_perms('superuser','',1) );
	  }
	  next if ($filter && $name !~ /$filter/);
	  print print_csv([$ord, $name, $type, $rev, $comment], 1) . "\n";
	  $ord++;
      }
      return;
  }

  if ($sub eq 'add') {
    return if (check_perms('superuser',''));

    $data{server}=$serverid;
    if (param('add_submit')) {
      unless (($res=form_check_form('addzone',\%data,\%new_zone_form))) {
	if ($data{reverse} eq 't' || $data{reverse} == 1) {
# For reverse zone, change cidr to in-addr.arpa or ip6.arpa format name. TVu
	    if (is_cidr($data{name}) && $data{name} =~ /\/\d{1,3}$/) {
		$data{name} = cidr2arpa($data{name});
	    }
	  my $new_net=arpa2cidr($data{name});
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
          start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','zones'),hidden('sub','add');
    form_magic('addzone',\%data,\%new_zone_form);
    print 'Tip: The cidr of a forward zone can be used<br>' . # ****
          'as the name of the corresponding reverse zone.<br>' .
	  'Mask length must be a multiple of 8 (IPv4) or 4 (IPv6).<br>';
    print submit(-name=>'add_submit',-value=>"Create Zone"),end_form;
    return;
  }
  elsif ($sub eq 'Delete') {
    return if (check_perms('superuser',''));

    $|=1; # if ($frame_mode);
    $res=delete_magic('zn','Zone','zones',\%zone_form,\&get_zone,
		      \&delete_zone,$zoneid);
    if ($res == 1) {
      $state->{'zone'}='';
      $state->{'zoneid'}=-1;
      save_state($state->{cookie},$state);
      goto select_zone;
    }
    param('selected_zone', $state->{'zone'}); # Show selected zone.
    goto display_zone if ($res == 2);
    goto select_zone if ($res == -1);
    return;
  }
  elsif ($sub eq 'Edit') {
    return if (check_perms('superuser',''));

    $res=edit_magic('zn','Zone','zones',\%zone_form,\&get_zone,\&update_zone,
		    $zoneid);
    goto select_zone if ($res == -1);
    param('selected_zone', $state->{'zone'}); # Show selected zone.
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
          start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','zones'),hidden('sub','Copy');
    form_magic('copy',\%data,\%copy_zone_form);
    print submit(-name=>'copy_confirm',-value=>'Copy Zone')," ",
          submit(-name=>'copy_cancel',-value=>'Cancel'),end_form;
    return;
  }
  elsif ($sub eq 'pending') {
    my @plist;
    return if (check_perms('zone','R'));
    print h2("Pending changes to host records:");

    # check for removed hosts...
    get_zone($zoneid,\%zone);
    if ($zone{rdate} > $zone{serial_date}) {
      push @plist, ['','&lt;removed host(s)&gt;','',
		    localtime($zone{rdate}).'',''];
    }

    db_query("SELECT h.id,h.domain,h.cdate,h.mdate,h.cuser,h.muser,h.type " .
	     "FROM hosts h, zones z " .
	     "WHERE z.id=$zoneid AND h.zone=z.id " .
	     " AND (h.mdate > z.serial_date OR h.cdate > z.serial_date) " .
	     "ORDER BY h.domain LIMIT 100;",\@q);

    for $i (0..$#q) {
      my $action=($q[$i][2] > $q[$i][3] ? 'Create' : 'Modify');
      my $date=localtime(($action eq 'Create' ? $q[$i][2] : $q[$i][3]));
      my $user=($action eq 'Create' ? $q[$i][4] : $q[$i][5]);
      my $name="<a href=\"$selfurl?menu=hosts&h_id=$q[$i][0]\">$q[$i][1]</a>";
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
  elsif ($sub eq 'Current') {
      param('selected_zone', $state->{'zone'}); # Show selected zone.
      goto display_zone;
  }
#  elsif ($sub eq 'select') {
#      goto select_zone;
#  }

 display_zone:
  $zone=param('selected_zone');
# By default, go to zone selection instead of showing previously selected zone.
# $zone=$state->{'zone'} unless ($zone);
  if ($zone && $sub ne 'select') {
    #display selected zone info
    $zoneid=get_zone_id($zone,$serverid);
    if ($zoneid < 1) {
      print h3("Cannot select zone '$zone'!"),p;
      goto select_zone;
    }
    my %state_save = %{$state};
    $state->{'zone'}=$zone;
    $state->{'zoneid'}=$zoneid;
    if (check_perms('zone','R')) {
      %{$state}=%state_save;
      goto select_zone;
    }
    print h2("Selected zone: $zone"),p;
    get_zone($zoneid,\%data);
    save_state($state->{cookie},$state);

    display_form(\%data,\%zone_form);
    return;
  }


 select_zone:
  #display zone selection list
  my %ztypecolors=(M=>'#c0ffc0',S=>'#eeeeff',F=>'#eedfdf',H=>'#eeeebf');
  # 2022-08-10 mesrik: add last expired arg, no skipping here
  # my $list=get_zone_list($serverid,0,0);
  my $list=get_zone_list($serverid,0,0,0);
# my $zlimit = 50; # Limit removed.

  if ($state->{'zone'}) {
      print h2("Selected zone: <a href='$selfurl?menu=zones&amp;selected_zone=" .
	       "$state->{'zone'}'>$state->{'zone'}</a>");
  }

  print start_form(-method=>'GET',-action=>$selfurl),
        hidden('menu','zones'),hidden('sub','select'),"Zone display filter: ",
	textfield(-name=>'select_filter',-size=>20,-maxlength=>80),"  ",
	submit(-name=>'filter',-value=>'Go'),end_form,
        h2("Select zone:"),
#       ((@{$list} > $zlimit && ! param('select_filter')) ? # Limit removed.
#        "(only first $zlimit zones displayed)":""),
	p,"<TABLE width=98% bgcolor=white border=0>",
        "<TR bgcolor=\"#aaaaff\">",th(['#','Zone','Type','Reverse','Comments']);

  my $ord = 1;

  for $i (0 .. $#{$list}) {
    my $type=$ztypenames{$$list[$i][2]};
    # 2022-08-10 mesrik: hack - show expiry more information
    my $expires = $$list[$i][5];
    my ($color,$title);
    if ($expires > 0 && $expires < time()) {
	$color = '#ffcccc'; # has already expired
	$title = sprintf "Expired %s",utimefmt($expires,'rfc822date');
    } elsif ($expires > 0 && ($expires - ($main::SAURON_REMOVE_EXPIRED_DELAY * 86400)) < time()) {
	$color='#eeeebf'; # upcoming expiration
	$title = sprintf "Expires %s",utimefmt($expires,'rfc822date');
    } elsif ($expires > 0) {
	$color='#ddffdd'; # remark expire is set
	$title = sprintf "Expires %s",utimefmt($expires,'rfc822date');
    } else {
	$color=$ztypecolors{$$list[$i][2]};
	$title = "Expiry undefined";
    }
    my $rev=(($$list[$i][3] eq 't' || $$list[$i][3] == 1) ? 'Yes' : 'No');
    my $id=$$list[$i][1];
    my $name=$$list[$i][0];
    my $comment=$$list[$i][4].'&nbsp;';
    my $filter = param('select_filter');

    if ($main::SAURON_PRIVILEGE_MODE==1) {
      next unless ( $perms->{zone}->{$id} =~ /R/ ||
		    !check_perms('superuser','',1) );
    }

    next if ($filter && $name !~ /$filter/);
#   last if ($i >= $zlimit && ! $filter); # Limit removed. TVu

# If the comment is an URL, show it as a link. TVu
    $comment = url2link($comment);
    print "<TR bgcolor=\"$color\">",td([$ord,
	"<a href=\"$selfurl?menu=zones&selected_zone=$name\"" .
	" title=\"$title\">$name</a>",$type,$rev,$comment]);
    $ord++;
    $zonelist{$name}=$id;
  }
  print "</TABLE><BR>";

  print "<table width='99%'><tr align=right><td>";
  print start_form(-method=>'POST',-action=>$selfurl),
  hidden('menu','zones'),hidden('sub','select'),
  hidden('select_filter',scalar(param('select_filter'))),
  hidden('csv','1'),
  submit(-name=>'results.csv',-value=>'Download CSV');
  print end_form;
  print "</td></tr></table>\n";

  get_server($serverid,\%server);
  if ($server{masterserver} > 0) {
    %ztypecolors=(M=>'#eedeff',S=>'#eeeeff',F=>'#eedfdf',H=>'#eeeebf');
    %ztypenames=(M=>'Slave (Master)',S=>'Slave',F=>'Forward',H=>'Hint');

    print h4("Zones from master server:"),
          p,"<TABLE width=98% bgcolor=white border=0>",
        "<TR bgcolor=\"#aaaaff\">",th(['Zone','Type','Reverse','Comments']);
    # 2022-08-10 mesrik: add no_expired arg
    # $list=get_zone_list($server{masterserver},0,0);
    $list=get_zone_list($server{masterserver},0,0,0);
    for $i (0 .. $#{$list}) {
      my $type=$$list[$i][2];
      next if ($server{named_flags_isz}!=1 && $type !~ /^M/);
      next unless ($type =~ /^[MS]$/);
      $type=$ztypenames{$$list[$i][2]};
      my $color=$ztypecolors{$$list[$i][2]};
      my $rev=(($$list[$i][3] eq 't' || $$list[$i][3] == 1) ? 'Yes' : 'No');
      my $id=$$list[$i][1];
      my $name=$$list[$i][0];
      my $comment=$$list[$i][4].'&nbsp;';
      next if ($zonelist{$name});
# If the comment is an URL, show it as a link. TVu
      $comment = url2link($comment);
      print "<TR bgcolor=$color>",td([$name,$type,$rev,$comment]);
    }
    print "</TABLE><BR>";

  }


}



1;
# eof
