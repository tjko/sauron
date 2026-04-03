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
use Sauron::SetupIO;
use HTML::Entities;
use strict;
use vars qw($VERSION @ISA @EXPORT);
use Sys::Syslog qw(:DEFAULT setlogsock);
eval { local $SIG{__WARN__} = sub {}; Sys::Syslog::setlogsock('unix') };

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );


sub write2log{
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", encode_str("$msg"));
  Sys::Syslog::closelog();
} # End of write2log


my %ztypenames=(M=>'master',S=>'slave',F=>'forward',H=>'hint',C=>'catalog');

my %naptr_flags=(
    0=>'(non-terminal)',
    1=>'S',
    2=>'A',
    3=>'U',
    4=>'P'
);

my %new_zone_form=(
 data=>[
  {ftype=>0, name=>'New zone'},
  {ftype=>1, tag=>'name', name=>'Zone name', type=>'zonename',
   len=>72, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, 
   empty=>1, anchor=>1, whitesp=>'P'},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', conv=>'U',
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward', C=>'Catalog'}},
  {ftype=>3, tag=>'reverse', name=>'Reverse', type=>'enum',  conv=>'L',
   enum=>{f=>'No',t=>'Yes'}, iff=>['type','M']}
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
   enum=>{M=>'Master', S=>'Slave', H=>'Hint', F=>'Forward', C=>'Catalog'}},
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
   len=>[30,20], empty=>[0,1], elabels=>['NS','comment']},
  {ftype=>2, tag=>'mx', name=>'Mail exchanges (MX)', maxlen=>[5,400,20],
#  type=>['int','text','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   type=>['int','mx','text'], fields=>3, len=>[5,30,20], empty=>[0,0,1],
   elabels=>['Priority','MX','comment'], whitesp=>['','','P'], iff=>['type','M'],
   iff2=>['reverse','f']},
  {ftype=>2, tag=>'txt', name=>'Info (TXT)', type=>['text','text'], fields=>2,
   len=>[68,15], maxlen=>[220,15], empty=>[0,1], elabels=>['TXT','comment'], whitesp=>['P','P'],
   iff=>['type','M'], iff2=>['reverse','f']},
  {ftype=>2, tag=>'naptr', name=>'NAPTR entries', fields=>7, len=>[3,3,2,5,20,20,20],
   empty=>[0,0,1,1,1,0,1], maxlen=>[5,5,2,20,100,100,80], addempty=>[-1,-1,-1,-1,-1,-1,0],
   elabels=>['Order','Preference','Flags','Service','Regexp','Replacement','Comment'],
   type=>['priority','priority','enum','text','text','text','text'],
   enum=>[undef, undef, \%naptr_flags, undef, undef, undef, undef],
   iff=>['type','M'], iff2=>['reverse','f']},

# New version of Custom zone file entries: Multiple textareas instead
# of multiple indivdual rows. Single column. 2020-07-30 TVu
  {ftype => 2, tag => 'zentries_ta', name => 'Custom Zone File Entries (current)',
   type => ['area'], fields => 1, rows => 6, len => [90], linelen => [253], # [15],
   empty => [0], elabels => ['Zone Entries (current)'],
   extrainfo => 'Use zone file syntax', whitesp => ['N'], iff => ['type', '[MC]'] },

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
   iff=>['type','[MC]']},

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
   name=>'Allow zone-transfers from (allow-transfer)', iff=>['type','[MC]']},
  {ftype=>2, tag=>'also_notify',
   name=>'[Stealth] Servers to notify (also-notify)', type=>['ip','text'],
   fields=>2, len=>[39,15], empty=>[0,1], elabels=>['IP','comment'],
   whitesp=>['','P'], iff=>['type','M']},
  {ftype=>2, tag=>'forwarders',name=>'Forwarders', type=>['ip','int','text'],
   fields=>3, len=>[39,6,15], empty=>[0,1,1], elabels=>['IP','Port','comment'],
   iff=>['type','F']},

  {ftype=>0, name=>'Catalog Zones', iff=>['type','C'], no_edit=>1},
  {ftype=>0, name=>'Catalog Zones', iff=>['type','M']},
  {ftype=>4, tag=>'catalog_member_count', name=>'Member zones count',
   no_edit=>1, iff=>['type','C']},
  {ftype=>4, tag=>'catalog_members_list', name=>'Member zones',
   no_edit=>1, iff=>['type','C']},
  {ftype=>4, tag=>'catalog_group_defs_list', name=>'Defined groups',
   no_edit=>1, iff=>['type','C']},
  {ftype=>4, tag=>'catalog_group_manage_link', name=>'Manage groups',
   no_edit=>1, iff=>['type','C']},
  {ftype=>4, tag=>'zone_catalog_count', name=>'Number of catalogs',
   no_edit=>1, iff=>['type','M']},
#  {ftype=>4, tag=>'zone_catalogs_list', name=>'Included in catalogs',
#   no_edit=>1, iff=>['type','M']}, # duplicity
  {ftype=>14, tag=>'catalog_zones_selected', name=>'Member of catalog zones',
   iff=>['type','M']},
  {ftype=>15, tag=>'member_groups', name=>'Catalog zone groups (RFC 9432)',
   iff=>['type','M']},

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


# Wrapper for update_zone that cleans up computed/formatted fields before updating
sub update_zone_wrapper($) {
  my($rec) = @_;
  
  # Remove all computed/formatted fields that should not be saved to database
  delete $rec->{catalog_members};
  delete $rec->{catalog_member_count};
  delete $rec->{catalog_members_list};
  delete $rec->{zone_catalogs};
  delete $rec->{zone_catalog_count};
  delete $rec->{zone_catalogs_list};
  delete $rec->{available_catalogs};
  delete $rec->{catalog_zones_selected_links};
  delete $rec->{catalog_group_defs};
  delete $rec->{catalog_group_defs_list};
  delete $rec->{catalog_group_manage_link};
  delete $rec->{cdate_str};
  delete $rec->{mdate_str};
  delete $rec->{pending_info};
  delete $rec->{fqdn};
  
  # Call the actual update_zone function from BackEnd
  return Sauron::BackEnd::update_zone($rec);
}


sub select_zone($$)
{
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};
  my (%server,%zonelist);

  #display zone selection list
  my %ztypecolors=(M=>'#c0ffc0',C=>'#add0fe',S=>'#eeeeff',F=>'#eedfdf',H=>'#eeeebf');
  # 2022-08-10 mesrik: add last expired arg, no skipping here
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

  for my $i (0 .. $#{$list}) {
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
    for my $i (0 .. $#{$list}) {
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

  return 0;
}


sub display_zone($$)
{
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};

  my $zone = param('selected_zone');
  my $sub = param('sub');

# By default, go to zone selection instead of showing previously selected zone.
# $zone=$state->{'zone'} unless ($zone);
  if ($zone && $sub ne 'select') {
    #display selected zone info
    my $zoneid=get_zone_id($zone,$serverid);
    if ($zoneid < 1) {
      print h3("Cannot select zone '" . encode_entities($zone) . "'!"),p;
      select_zone($state,$perms);
      return;
    }
    my %state_save = %{$state};
    $state->{'zone'}=$zone;
    $state->{'zoneid'}=$zoneid;
    if (check_perms('zone','R')) {
      %{$state}=%state_save;
      select_zone($state,$perms);
      return
    }
    print h2("Selected zone: $zone"),p;
    my %data;
    get_zone($zoneid,\%data);
    save_state($state->{cookie},$state);

    # Format catalog zones list with links
    if ($data{zone_catalogs} && @{$data{zone_catalogs}} > 0) {
      my @catalog_links;
      for my $cat (@{$data{zone_catalogs}}) {
        my $cat_name = $cat->[1];
        my $cat_link = "<a href=\"$selfurl?menu=zones&selected_zone=$cat_name\">$cat_name</a>";
        push @catalog_links, $cat_link;
      }
      $data{zone_catalogs_list} = join(', ', @catalog_links);
    }

    # Format member zones list with links (for catalog zones)
    if ($data{catalog_members} && @{$data{catalog_members}} > 0) {
      my @member_links;
      my %zone_type_names = (M=>'master', S=>'slave', F=>'forward', H=>'hint', C=>'catalog');
      for my $member (@{$data{catalog_members}}) {
        my $zone_name = $member->[1];    # zone name
        my $zone_type = $member->[2];    # zone type
        my $server_name = $member->[4];  # server name
        my $type_label = $zone_type_names{$zone_type} || $zone_type;
        my $groups = $member->[7];       # groups arrayref
        my $group_str = '';
        if (ref($groups) eq 'ARRAY' && @{$groups}) {
          $group_str = ' [' . join(', ', @{$groups}) . ']';
        }
        my $member_link = "<a href=\"$selfurl?menu=zones&selected_zone=$zone_name\" title=\"Select $type_label zone $zone_name\">$zone_name</a>$group_str";
        push @member_links, $member_link;
      }
      $data{catalog_members_list} = join(', ', @member_links);
    }

    # Add manage groups link for catalog zones
    if ($data{type} && $data{type} eq 'C') {
      $data{catalog_group_manage_link} =
        "<a href=\"$selfurl?menu=zones&sub=CatalogGroups\"><B>[ Manage Groups ]</B></a>";
    }

    # Format catalog zones selected list with links (for Member of catalog zones field)
    if ($data{catalog_zones_selected} && @{$data{catalog_zones_selected}} > 0) {
      my @selected_cat_ids = @{$data{catalog_zones_selected}};
      my @catalog_zone_links;
      if ($data{available_catalogs} && @{$data{available_catalogs}} > 0) {
        # Create a mapping of catalog IDs to catalog names
        my %cat_id_to_name;
        for my $cat (@{$data{available_catalogs}}) {
          $cat_id_to_name{$cat->[0]} = $cat->[1];  # ID => NAME
        }
        # Create links for selected catalog zones
        for my $cat_id (@selected_cat_ids) {
          if (exists $cat_id_to_name{$cat_id}) {
            my $cat_name = $cat_id_to_name{$cat_id};
            my $cat_link = "<a href=\"$selfurl?menu=zones&selected_zone=$cat_name\" title=\"Select catalog zone $cat_name\">$cat_name</a>";
            push @catalog_zone_links, $cat_link;
          }
        }
      }
      $data{catalog_zones_selected_links} = join(', ', sort @catalog_zone_links) if @catalog_zone_links;
    }

    display_form(\%data,\%zone_form);
    return;
  }

  select_zone($state,$perms);

  return 0;
}


sub new_zone_edit($$)
{
  my($state,$data) = @_;

  my $selfurl = $state->{selfurl};

  unless (param('addzone_re_edit')) { $data->{type}='M'; }
  print h2("New Zone:"),p,
    start_form(-method=>'POST',-action=>$selfurl),
    hidden('menu','zones'),hidden('sub','add');
  form_magic('addzone',$data,\%new_zone_form);
  print 'Tip: The cidr of a forward zone can be used<br>' . # ****
    'as the name of the corresponding reverse zone.<br>' .
    'Mask length must be a multiple of 8 (IPv4) or 4 (IPv6).<br>';
  print submit(-name=>'add_submit',-value=>"Create Zone"),end_form;

  return 0;
}


# ZONES menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my($i,@q,$res,%data,%zone);

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};

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
	    new_zone_edit($state,\%data);
	    return;
	  }
	  $data{reversenet}=$new_net;
	}

	$res=add_zone(\%data);
	if ($res < 0) {
	  print "<FONT color=\"red\">",h1("Adding Zone record failed!"),
	      "result code=$res</FONT>";
	} else {
	  param('selected_zone',$data{name});
	  display_zone($state,$perms);
	  return;
	}
      } else {
	print "<FONT color=\"red\">",h2("Invalid data in form!"),"</FONT>";
      }
    }
    new_zone_edit($state,\%data);
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
      select_zone($state,$perms);
      return;
    }
    param('selected_zone', $state->{'zone'}); # Show selected zone.
    if ($res == 2) {
      display_zone($state,$perms);
    }
    elsif ($res == -1) {
      select_zone($state,$perms);
    }
    return;
  }
  elsif ($sub eq 'Edit') {
    return if (check_perms('superuser',''));

    $res=edit_magic('zn','Zone','zones',\%zone_form,\&get_zone,\&update_zone_wrapper,
		    $zoneid);
    if ($res == -1) {
      select_zone($state,$perms);
    } else {
      param('selected_zone', $state->{'zone'}); # Show selected zone.
      display_zone($state,$perms) if ($res == 2 || $res == 1);
    }
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
  elsif ($sub eq 'CatalogGroups') {
    return if (check_perms('superuser',''));

    if ($zoneid < 1) {
      print h2("No zone selected!");
      select_zone($state,$perms);
      return;
    }

    # Verify this is a catalog zone
    my $is_cat = is_catalog_zone($zoneid);
    if ($is_cat != 1) {
      print h2("Selected zone is not a catalog zone."),
            p,"Only catalog zones (type C) can have group definitions.",
            p,"<a href=\"$selfurl?menu=zones&sub=select\">Select a zone</a>";
      return;
    }

    my $zone_name = $zone || $state->{zone} || '';

    # Handle form actions
    my $action = param('grp_action') || '';

    # Add group
    if ($action eq 'add') {
      my $new_name = param('grp_new_name') || '';
      my $new_comment = param('grp_new_comment') || '';
      $new_name =~ s/^\s+|\s+$//g;
      $new_comment =~ s/^\s+|\s+$//g;

      if ($new_name eq '') {
        print "<FONT color=\"red\">",h3("Group name cannot be empty!"),"</FONT>";
      } elsif ($new_name =~ /[^a-zA-Z0-9_\-.]/) {
        print "<FONT color=\"red\">",h3("Group name can only contain letters, digits, hyphens, dots and underscores!"),"</FONT>";
      } else {
        $res = add_catalog_group_def($zoneid, $new_name, $new_comment);
        if ($res == -10) {
          print "<FONT color=\"red\">",h3("Group '$new_name' already exists!"),"</FONT>";
        } elsif ($res < 0) {
          print "<FONT color=\"red\">",h3("Failed to add group (error: $res)"),"</FONT>";
        } else {
          print h3("Group '<B>$new_name</B>' added successfully.");
        }
      }
    }

    # Confirm delete
    if ($action eq 'confirm_delete') {
      my $del_name = param('grp_del_name') || '';
      $del_name =~ s/^\s+|\s+$//g;

      if ($del_name ne '') {
        $res = delete_catalog_group_def($zoneid, $del_name);
        if ($res < 0) {
          print "<FONT color=\"red\">",h3("Failed to delete group (error: $res)"),"</FONT>";
        } else {
          print h3("Group '<B>$del_name</B>' deleted.");
        }
      }
    }

    # Delete check - show usage warning before actual deletion
    if ($action eq 'delete') {
      my $del_name = param('grp_del_name') || '';
      $del_name =~ s/^\s+|\s+$//g;

      if ($del_name ne '') {
        my %usage;
        get_catalog_group_usage($zoneid, $del_name, \%usage);

        print h2("Delete group: $del_name"),
              start_form(-method=>'POST',-action=>$selfurl),
              hidden('menu','zones'),hidden('sub','CatalogGroups');

        if ($usage{count} > 0) {
          print "<FONT color=\"red\"><B>Warning:</B> This group is currently assigned to $usage{count} zone(s):</FONT>",
                "<UL>";
          my %zone_type_names = (M=>'master', S=>'slave', F=>'forward', H=>'hint');
          for my $zu (@{$usage{zones}}) {
            my $zu_name = $zu->[1];
            my $zu_type = $zone_type_names{$zu->[2]} || $zu->[2];
            print "<LI><a href=\"$selfurl?menu=zones&selected_zone=$zu_name\">$zu_name</a> ($zu_type)</LI>";
          }
          print "</UL>",
                "<P>Deleting this group will <B>remove it from all these zones</B>.</P>";
        } else {
          print p,"This group is not assigned to any zone.";
        }

        print hidden('grp_action','confirm_delete'),
              hidden('grp_del_name',$del_name),
              submit(-name=>'grp_confirm_del',-value=>'Confirm Delete')," ",
              submit(-name=>'grp_cancel_del',-value=>'Cancel'),
              end_form;
        return;
      }
    }

    # Main display: list existing groups + add form
    print h2("Catalog Zone Groups: $zone_name");

    # Load current group definitions
    my %gdefs;
    get_catalog_group_defs($zoneid, \%gdefs);

    # Display existing groups as a table
    print "<TABLE width=\"80%\" bgcolor=\"white\" border=0>",
          "<TR bgcolor=\"#aaaaff\">",th(['#','Group Name','Comment','Usage','Actions']),"</TR>";

    if ($gdefs{count} > 0) {
      my $ord = 1;
      for my $gdef (@{$gdefs{groups}}) {
        my $gid = $gdef->[0];
        my $gname = $gdef->[1];
        my $gcomment = $gdef->[2] || '&nbsp;';

        # Check usage count
        my %usage;
        get_catalog_group_usage($zoneid, $gname, \%usage);
        my $usage_str = $usage{count} > 0
            ? "<FONT color=\"#cc6600\">$usage{count} zone(s)</FONT>"
            : "<FONT color=\"green\">unused</FONT>";

        # Delete button in a mini-form
        my $del_form = "<FORM method=POST action=\"$selfurl\" style=\"display:inline\">" .
                       "<INPUT type=hidden name=menu value=zones>" .
                       "<INPUT type=hidden name=sub value=CatalogGroups>" .
                       "<INPUT type=hidden name=grp_action value=delete>" .
                       "<INPUT type=hidden name=grp_del_name value=\"" . encode_entities($gname) . "\">" .
                       "<INPUT type=submit value=Delete></FORM>";

        print "<TR bgcolor=\"#f0f0f0\">",
              td([$ord, "<B>$gname</B>", $gcomment, $usage_str, $del_form]),
              "</TR>";
        $ord++;
      }
    } else {
      print "<TR><TD colspan=5 align=center><I>No groups defined for this catalog zone.</I></TD></TR>";
    }
    print "</TABLE><BR>";

    # Add group form
    print h3("Add New Group"),
          start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','zones'),hidden('sub','CatalogGroups'),
          hidden('grp_action','add'),
          "<TABLE>",
          "<TR><TD>Group name:</TD><TD>",
          textfield(-name=>'grp_new_name',-size=>30,-maxlength=>63),
          "</TD></TR>",
          "<TR><TD>Comment:</TD><TD>",
          textfield(-name=>'grp_new_comment',-size=>50,-maxlength=>200),
          "</TD></TR>",
          "<TR><TD></TD><TD>",
          submit(-name=>'grp_add_submit',-value=>'Add Group'),
          "</TD></TR>",
          "</TABLE>",
          end_form;

    # Link back to zone display
    print "<BR><a href=\"$selfurl?menu=zones&selected_zone=$zone_name\">&laquo; Back to zone $zone_name</a>";

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
  }

 display_zone($state,$perms);
}



1;
# eof
