# Sauron::CGI::Login.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id:$
#
package Sauron::CGI::Login;
require Exporter;
use CGI qw/:standard *table -utf8/;
use Sauron::DB;
use Sauron::Util;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::CGI::Utils;
#use Data::Dumper;
# use Storable qw(nstore store_fd nstore_fd freeze thaw dclone); # TVu 2021-03-15
#use Storable qw(freeze thaw); # TVu 2021-03-15
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );



my %user_info_form=(
 data=>[
  {ftype=>0, name=>'User info' },
  {ftype=>4, tag=>'user', name=>'Login'},
  {ftype=>4, tag=>'name', name=>'User Name'},
  {ftype=>4, tag=>'groupname', name=>'Group(s)'},
  {ftype=>4, tag=>'login', name=>'Last login', type=>'localtime'},
  {ftype=>4, tag=>'addr', name=>'Host', iff=>['addr', '\S+']}, # iff TVu 2021-03-15
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
  {ftype=>4, tag=>'sid', name=>'Session ID (SID)', iff=>['sid', '\d+']} # iff TVu 2021-03-15
 ]
);

my %user_settings_form=(
 data=>[
  {ftype=>0, name=>'Settings' },
  {ftype=>1, tag=>'email', name=>'Email', type=>'email'},
  {ftype=>3, tag=>'email_notify', name=>'Email notifications',type=>'enum',
   enum=>{0=>'Disabled',1=>'Enabled'}},
 ]
);


my %new_motd_enum = (-1=>'Global');

my %new_motd_form=(
 data=>[
  {ftype=>0, name=>'Add news message'},
  {ftype=>3, tag=>'server', name=>'Message type', type=>'enum',
   enum=>\%new_motd_enum},
  {ftype=>1, tag=>'info', name=>'Message', type=>'textarea', rows=>5,
   whitesp=>'AW', columns=>50 }
 ]
);


my %change_passwd_form=(
 data=>[
# {ftype=>1, tag=>'old', name=>'Old password', type=>'passwd', len=>20 },
  {ftype=>1, tag=>'old', name=>'Old password', type=>'passwd', len=>40, whitesp=>'AW' }, # 2020-10-19 TVu
  {ftype=>0, name=>'Type new password twice'},
# {ftype=>1, tag=>'new1', name=>'New password', type=>'passwd', len=>20 },
  {ftype=>1, tag=>'new1', name=>'New password', type=>'passwd', len=>40, whitesp=>'AW' }, # 2020-10-19 TVu
# {ftype=>1, tag=>'new2', name=>'New password', type=>'passwd', len=>20 }
  {ftype=>1, tag=>'new2', name=>'New password', type=>'passwd', len=>40, whitesp=>'AW' } # 2020-10-19 TVu
 ]
);

my %session_id_form=(
 data=>[
  {ftype=>0, name=>'Session browser'},
  {ftype=>1, tag=>'sid', name=>'SID', type=>'int', len=>8, empty=>1 }
 ]
);

my %history_form=(
 data=>[
  {ftype=>0, name=>'History search'},
  {ftype=>1, tag=>'user', name=>'User', type=>'text', len=>10, maxlen=>8, empty=>1 },
  {ftype=>1, tag=>'date', name=>'Dates', type=>'daterange', len=>20, empty=>1,
   extrainfo=>'Enter date range as -YYYYMMDD, YYYYMMDD- or YYYYMMDD-YYYYMMDD' },
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', len=>8,
   enum=>{ 0 => 'Any', 1 => 'Hosts', 2 => 'Zones' , 3 => 'Servers' , 4 => 'Nets' , 5 => 'Users' } },
  {ftype=>1, tag=>'ref', name=>'Ref (Id)', type=>'int', len=>10, empty=>1 },
  {ftype=>1, tag=>'action', name=>'Action (regexp)', type=>'text', len=>20, maxlen=>30, empty=>1 },
  {ftype=>1, tag=>'info', name=>'Info (regexp)', type=>'text', len=>40, maxlen=>100, empty=>1 }
 ]
);

# -------------------------------------------------
# Show rows related to a particular type of user rights.
sub display_rows($) { # TVu 2021-03-15
    my($list) = @_;
    my($i,$j,$val);
    use feature 'state';
    state $row;

    for $i (0..$#{$list}) {
	$row++;
	print "<TR bgcolor='#eeeebf'><TD ALIGN='RIGHT'>$row</TD>";
	for $j (0..2) {
	    $val = $$list[$i][$j];
	    print td($val ne '' ? $val : '&nbsp;');
	}
	print "</TR>\n";
    }
}

# Find all user rights of a user or a user group.
sub list_privs($$) { # TVu 2021-03-15
  my ($id, $utype) = @_;
  my ($i, @d);

  db_query("SELECT 'Server', b.name, a.rule FROM user_rights a, servers b " .
	   "WHERE a.rtype=1 AND a.rref=b.id AND a.ref=$id AND a.type=$utype ".
	   "ORDER BY b.name",\@d);
  display_rows(\@d);

  db_query("SELECT 'Zone', c.name || ': ' || b.name, a.rule " .
	   "FROM user_rights a, zones b, servers c " .
	   "WHERE a.rtype=2 AND a.rref=b.id AND b.server=c.id AND " .
	   " a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

# db_query("SELECT 'Net', c.name || ': ' || b.net, '(IP constraint)' " .
  db_query("SELECT 'Net', c.name || ': ' || b.net, b.range_start || ' - ' || b.range_end " .
	   "FROM user_rights a, nets b, servers c " .
	   "WHERE a.rtype=3 AND a.rref=b.id AND b.server=c.id " .
           "  AND a.ref=$id AND a.type=$utype ORDER BY c.name, b.net",\@d);
  for $i (0..$#d) {
      $d[$i][2] =~ s/\/\d+//g;
  }
  display_rows(\@d);

  db_query("SELECT 'Hostmask', a.rule, '(Hostname constraint)', null FROM user_rights a " .
	   "WHERE a.rtype=4 AND a.ref=$id AND a.type=$utype AND a.rref=-1 " .
	   "UNION ALL " .
	   "SELECT 'Hostmask', a.rule, '(Hostname constraint)', z.name FROM user_rights a " .
	   "JOIN zones z ON a.rref=z.id " .
	   "WHERE a.rtype=4 AND a.ref=$id AND a.type=$utype ORDER BY 4,2",\@d);
  for $i (0..$#d) {
      $d[$i][1] = ($d[$i][3] ? "$d[$i][3]: " : '') . $d[$i][1];
  }
  display_rows(\@d);

  db_query("SELECT 'IP mask', a.rule, '(IP address constraint)' FROM user_rights a " .
	   "WHERE a.rtype=5 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'DelMask', a.rule, '(Delete host mask)', null FROM user_rights a " .
          "WHERE a.rtype=11 AND a.ref=$id AND a.type=$utype AND a.rref=-1 " .
          "UNION ALL " .
          "SELECT 'DelMask', a.rule, '(Delete host mask)', z.name FROM user_rights a " .
          "JOIN zones z ON a.rref=z.id " .
          "WHERE a.rtype=11 AND a.ref=$id AND a.type=$utype ORDER BY 4,2",\@d);
  for $i (0..$#d) {
      $d[$i][1] = ($d[$i][3] ? "$d[$i][3]: " : '') . $d[$i][1];
  }
  display_rows(\@d);

  db_query("SELECT 'ELimit', a.rule, '(Expiration limit, days)' FROM user_rights a " .
	   "WHERE a.rtype=7 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'DefDept', a.rule, '(Default department string)' FROM user_rights a " .
	   "WHERE a.rtype=8 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'DefHost', a.rule, '(Default hostname template)' FROM user_rights a " .
	   "WHERE a.rtype=14 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'Template Mask', a.rule, '(Template modify mask)' FROM user_rights a " .
	   "WHERE a.rtype=9 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'GrpMask', a.rule, '(Group mask)' FROM user_rights a " .
	   "WHERE a.rtype=10 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'ReqHostField', a.rule, a.rref FROM user_rights a " .
	   "WHERE a.rtype=12 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  for $i (0..$#d) {
      $d[$i][2] = $d[$i][2] ? 'Optional' : 'Required';
  }
  display_rows(\@d);

  db_query("SELECT 'Flag', a.rule, '(Permission to add / modify)' FROM user_rights a " .
	   "WHERE a.rtype=13 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);

  db_query("SELECT 'Level', a.rule, '(Authorization level)' FROM user_rights a " .
	   "WHERE a.rtype=6 AND a.ref=$id AND a.type=$utype ORDER BY 2",\@d);
  display_rows(\@d);
}


sub show_user_info($$)
{
  my($state_o,$perms_o) = @_;

  my $selfurl = $state_o->{selfurl};
  my(%user,$state,$perms,@q);

  print h2("User info:");

  my $uname = $state_o->{user};
  $uname = param('user_id') if (param('user_id'));

  if (get_user($uname,\%user)) {
    html_error2("Cannot get user record: $uname");
    return;
  }

  # Permissions.
  $perms = {};
  if (get_permissions($user{'id'}, $perms)) {
    html_error2("Cannot get permissions: $user{'id'}");
    return;
  };


  # Simulated session state information, where possible
  # (the selected user may not have a current session).
  $state->{user} = $user{'username'}; # Login name.
  $state->{login} = $user{'last'};    # Last login.
  $state->{superuser} = $user{'superuser'} eq 't' ? 'yes' : 'no';
  # alevel defaults to 0 when absent in the database (BackEnd.pm).
  # When a superuser logs in, alevel is set to 999. Simulated here.
  $perms->{alevel} = 999 if ($user{superuser} eq 't');

  if (param('user_id')) {
      undef @q;
      if ($user{'server'} && $user{'zone'}) {
	  db_query("select s.name, z.name from servers s, zones z " .
		   "where s.id = $user{'server'} and z.id = $user{'zone'} and " .
		   "z.server = s.id;",\@q);
      }
      $state->{server} = $q[0][0] || $user{'server'};
      $state->{zone} = $q[0][1] || $user{'zone'};
  } else {
      $state->{server} = $state_o->{server};
      $state->{zone} = $state_o->{zone};
      $state->{sid} = $state_o->{sid};
  }

  $state->{email}=$user{email};
  $state->{name}=$user{name};
  $state->{last_pwd}=$user{last_pwd};
  $state->{expiration}=($user{expiration} > 0 ?
			localtime($user{expiration}) : 'None');
  $state->{email_notify}=$user{email_notify};
  $state->{groupname}=$perms->{groups};
  display_form($state,\%user_info_form);

  # Show buttons if there is a plugin to handle their functions.
  if ($main::menuhooks{'login'}->{'Pl_Users_Users'} && param('user_id')) { # TVu 2021-04-19
    my $par_menu = param('menu');
    my $par_sub = param('sub');
    print "\n<table><tr><td>";
    print start_form(-method=>'GET', -action=>$selfurl);
    param('menu', 'login'); print hidden('menu', 'login');
    param('sub', 'Edit-user'); print hidden('sub', 'Edit-user');
    print hidden('user_id', param('user_id'));
    print submit(-name=>'foobar', -value=>'Edit');
    print end_form,"\n";
    print "</td>\n<td>";
    print start_form(-method=>'GET', -action=>$selfurl);
    param('menu', 'login'); print hidden('menu', 'login');
    param('sub', 'Copy-user'); print hidden('sub', 'Copy-user');
    print hidden('user_id', param('user_id'));
    print submit(-name=>'foobar', -value=>'Copy');
    print end_form,"\n";
    print "</td>\n<td>";
    print start_form(-method=>'GET', -action=>$selfurl);
    param('menu', 'login'); print hidden('menu', 'login');
    param('sub', 'Anonymize-user'); print hidden('sub', 'Anonymize-user');
    print hidden('user_id', param('user_id'));
    print submit(-name=>'foobar', -value=>'Anonymize', -title=>
		 'To completely delete a user, use command-line tool deluser');
    print end_form,"\n";
    print "</td></table>\n";
    param('menu', $par_menu);
    param('sub', $par_sub);
    # ** Button to lock or unlock user.
  }

  # Note! It is important to sort everything that can be sorted, so that if the same information
  # is viewd on two or more computers at the same time, line numbers are the same for everybody!

  print h3("Individual permissions:");
  print '<TABLE BGCOLOR="#ccccff" BORDER="0" cellspacing="1" cellpadding="1">' .
    '<TR bgcolor="#aaaaff"><TD>#</TD><TD>Type</TD><TD>Ref.</TD><TD>Permissions</TD>';
  list_privs($user{'id'}, 2);
  print '</TABLE>';

  for my $ind1 (sort split(',', $state->{groupname})) { # TVu 2021-03-15
    db_query("SELECT id, comment FROM user_groups WHERE name='$ind1'",\@q);
    my $gid = $q[0][0];
    print h3("Permissions via group $ind1<BR>($q[0][1]):");
    print '<TABLE BGCOLOR="#ccccff" BORDER="0" cellspacing="1" cellpadding="1">' .
      '<TR bgcolor="#aaaaff"><TD>#</TD><TD>Type</TD><TD>Ref.</TD><TD>Permissions</TD>';
    list_privs($gid, 1);
    print '</TABLE>';
  }

  print "<P>";
  # No longer showing combined permissions. 2021-04-14 TVu
  if (0) {
    my($tmp,$s);

    print h3("Combined permissions:"),"<TABLE border=0 cellspacing=1>",
      "<TR bgcolor=\"#aaaaff\"><TD>Type</TD><TD>Ref.</TD>",
      "<TD>Permissions</TD></TR>";

    # Server permissions
    foreach my $s (keys %{$perms->{server}}) {
      undef @q;
      db_query("SELECT name FROM servers WHERE id=$s;",\@q);
      $tmp=$q[0][0];
      print "<TR bgcolor=\"#dddddd\">",td("Server"),td("$tmp"),
	td($perms->{server}->{$s}." &nbsp;"),"</TR>";
    }

    # Zone permissions
    foreach my $s (keys %{$perms->{zone}}) {
      undef @q;
      db_query("SELECT s.name,z.name FROM zones z, servers s " .
	       "WHERE z.server=s.id AND z.id=$s;",\@q);
      $tmp="$q[0][0]: $q[0][1]";
      print "<TR bgcolor=\"#dddddd\">",td("Zone"),td("$tmp"),
	td($perms->{zone}->{$s}." &nbsp;"),"</TR>";
    }

    # Net permissions
    # FIXME:  output is not sorted properly raising order server:cidr
    #foreach $s (keys %{$perms->{net}}) {
    #  undef @q;
    #  db_query("SELECT s.name,n.net,n.range_start,n.range_end " .
    #       "FROM servers s, nets n WHERE n.server=s.id AND n.id=$s;",\@q);
    #  $tmp="$q[0][0]:$q[0][1]";
    #  print "<TR bgcolor=\"#dddddd\">",td("Net"),td("$tmp"),
    #     td($perms->{net}->{$s}[0]." - ".$perms->{net}->{$s}[1]),"</TR>";
    #}

    # Net permissions
    # Fixed better than previous, but still a bit hack
    $s = join(',',(keys %{$perms->{net}})) . "\n";
    if ($s) { # Empty $s caused sql errors 13.03.2017 TVu
      undef @q;
      db_query("SELECT s.name,n.net,n.range_start,n.range_end " .
	       "FROM servers s, nets n WHERE n.server=s.id AND " .
	       "n.id in ($s) ORDER BY name,net;",\@q);
      for $s (0..$#q) {
	$tmp="$q[$s][0]: $q[$s][1]";
	print "<TR bgcolor=\"#dddddd\">",td("Net"),td("$tmp"),
	  td($q[$s][2]." - ".$q[$s][3]),"</TR>";
      }
    }

    # Host permissions
    foreach $s (@{$perms->{hostname}}) {
      if (@{$s}[0] != -1) {
	undef @q;
	db_query("SELECT z.name FROM zones z, servers s " .
		 "WHERE z.server=s.id AND z.id=@{$s}[0];",\@q);
	$tmp="$q[0][0]: @{$s}[1]";
      } else {
	$tmp="@{$s}[1]";
      }
      print "<TR bgcolor=\"#dddddd\">",
	td("Hostmask"),td("$tmp"),td("(Hostname constraint)"),
	"</TR>";
    }

    # IP mask permissions
    foreach $s (@{$perms->{ipmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("IP mask"),td("$s"),
	td("(IP address constraint)"),"</TR>";
    }

    # Delete mask permissions
    foreach $s (@{$perms->{delmask}}) {
      if (@{$s}[0] != -1) {
	undef @q;
	db_query("SELECT z.name FROM zones z, servers s " .
		 "WHERE z.server=s.id AND z.id=@{$s}[0];",\@q);
	$tmp="$q[0][0]: @{$s}[1]";
      } else {
	$tmp="@{$s}[1]";
      }
      print "<TR bgcolor=\"#dddddd\">",
	td("Delmask"),td("$tmp"),td("(Delete host mask)"),
	"</TR>";
    }

    # Expiration limit ** TVu 2021-04-07
    if (defined $perms->{'elimit'}) {
      print "<TR bgcolor=\"#dddddd\">",td("Elimit"),td($perms->{'elimit'}),
	td("(Expiration limit, days)"),"</TR>";
    }

    # Default department ** TVu 2021-04-07
    if ($perms->{'defdept'}) {
      print "<TR bgcolor=\"#dddddd\">",td("DefDept"),td($perms->{'defdept'}),
	td("(Default department string)"),"</TR>";
    }

    # Default hostname ** TVu 2021-04-07
    if ($perms->{'defhost'}) {
      print "<TR bgcolor=\"#dddddd\">",td("DefHost"),td($perms->{'defhost'}),
	td("(Default hostname template)"),"</TR>";
    }

    # Template masks
    foreach $s (@{$perms->{tmplmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Template mask"),td("$s"),
	td("(Template modify mask)"),"</TR>";
    }

    # Group masks
    foreach $s (@{$perms->{grpmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("GrpMask"),td("$s"),
	td("(Group modify mask)"),"</TR>";
    }

    # Required host fields
    foreach $s (sort keys %{$perms->{rhf}}) {
      print "<TR bgcolor=\"#dddddd\">",td("ReqHostField"),td("$s"),
	td(($perms->{rhf}->{$s} ? 'Optional':'Required')),"</TR>";
    }

    # Flags
    foreach $s (sort keys %{$perms->{flags}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Flag"),td("$s"),
	td('(Permission to add / modify)'),"</TR>";
    }

    # Alevel permission
    print "<TR bgcolor=\"#dddddd\">",td("Level"),td($perms->{alevel}),
      td("(Authorization level)"),"</TR>";

    print "</TABLE><P>&nbsp;";
  }


  return 0;
}

# -------------------------------------------------
# LOGIN menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my($i,$s,@q,$res,$tmp,$sqlstr);
  my(%user,%data,%h,@list,@lastlog,@wholist);

  my $s_url = script_name();
  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $sub=param('sub');

  if (get_user($state->{user},\%user) < 0) {
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
    if ($main::SAURON_AUTH_PROG) {
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
	  print "<FONT color=\"red\">",h2("New passwords don't match!"),
	        "</FONT>";
	} else {
	  unless (pwd_check(param('passwd_old'),$user{password})) {
	    my $password=pwd_make(param('passwd_new1'),$main::SAURON_PWD_MODE);
	    my $ticks=time();
	    if (db_exec("UPDATE users SET password='$password', " .
			"last_pwd=$ticks WHERE id=$state->{uid};") < 0) {
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
          start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','passwd');
    form_magic('passwd',\%h,\%change_passwd_form);
    print submit(-name=>'passwd_submit',-value=>'Change password')," ",
          submit(-name=>'passwd_cancel',-value=>'Cancel'), end_form;
    return;
  }
  elsif ($sub eq 'save') {
    my $uid=$state->{'uid'};
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
  elsif ($sub eq 'clear') {
    my $uid=$state->{'uid'};
    return if ($uid < 1);
    $sqlstr="UPDATE users SET server=NULL,zone=NULL WHERE id=$uid;";
    $res=db_exec($sqlstr);
    if ($res < 0) {
      print h3('Clearing defaults failed!');
    } else {
      print h3('Defaults cleared successfully!');
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
	      "flags=$tmp WHERE id=$state->{uid}";
      $res=db_exec($sqlstr);
      if ($res < 0) {
	print h3("Cannot save personal settings!");
      } else {
	print h3("Personal settings successfully updated.");
      }
      show_user_info($state,$perms);
      return;
    } elsif ($res == -1) {
      print h2("No changes made.");
    }
  }
  elsif ($sub eq 'who') {
    my $timeout=$main::SAURON_USER_TIMEOUT;
    unless ($timeout > 0) {
      print h2("error: $main::SAURON_USER_TIMEOUT " .
	       "not defined in configuration!");
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
    my $count=get_lastlog(40,'',\@lastlog);
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
# Increment or decrement session id number.
    if (param('session_sid') > 0) {
      my $session_id = param('session_sid');
      if (param('session_inc_submit')) { $session_id++; }
      if (param('session_dec_submit')) { $session_id--; }
      param('session_sid', $session_id);
    }
    print start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','session');
    form_magic('session',\%h,\%session_id_form);
    print submit(-name=>'session_submit',-value=>'Select');
# Show increment/decrement buttons.
    if (param('session_sid') > 0) {
	print submit(-name=>'session_inc_submit',-value=>'Next SID');
	print submit(-name=>'session_dec_submit',-value=>'Previous SID');
    }
    print end_form, "<HR>";
    if (param('session_sid') > 0) {
      my $session_id=param('session_sid');
      undef @q;
      db_query("SELECT l.uid,l.date,l.ldate,l.host,u.username " .
	       "FROM lastlog l, users u " .
	       "WHERE l.uid=u.id AND l.sid=$session_id;",\@q);
      if (@q > 0) {
	print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1>",
              "<TR bgcolor=\"#aaaaff\">",th("SID"),th("User"),th("Login"),
	      th("Logout"),th("From"),"</TR>";
	my $date1=localtime($q[0][1]);
	my $date2=($q[0][2] > 0 ? localtime($q[0][2]) : '&nbsp;');
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
  elsif ($sub eq 'history') {
    print start_form(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','history');
    form_magic('history',\%h,\%history_form);
    print submit(-name=>'history_submit',-value=>'Search') . "\n";
    print "<input type='reset' value='Clear'>\n";
   print end_form, "<HR>";
# No search criterion, no search.
    if (param('history_user') !~ /\S/ && param('history_date') !~ /\S/ && param('history_type') == 0 &&
	param('history_ref') <= 0 && param('history_action') !~ /\S/ && param('history_info') !~ /\S/) {
	return;
    }
    $sqlstr = 'select u.username, h.sid, h.date, h.type, h.ref, h.action, h.info, ho.id, n.id ' .
	'from history h left join users u on h.uid = u.id left join hosts ho on h.type = 1 and h.ref = ho.id ' .
	'left join nets n on h.type = 4 and h.ref = n.id where true ';
    if (param('history_user') =~ /\S/) { $sqlstr .= "and u.username = '" . lc(param('history_user')) . "' "; }
    if (param('history_date') =~ /\S/) {
	my $dates = decode_daterange_str(param('history_date'));
	if ($$dates[0] > 0) { $sqlstr .= "and h.date >= $$dates[0] "; }
	if ($$dates[1] > 0) { $sqlstr .= "and h.date <= $$dates[1] "; }
    }
# If 'Users' (5) was selected, get history of users (5) and user groups (6).
    if (param('history_type') != 0) {
	if (param('history_type') == 5) {
	    $sqlstr .= 'and (h.type = 5 or h.type = 6) ';
	} else {
	    $sqlstr .= 'and h.type = ' . param('history_type') . ' ';
	}
    }
    if (param('history_ref') > 0) { $sqlstr .= 'and h.ref = ' . param('history_ref') . ' '; }
    if (param('history_action') =~ /\S/) { $sqlstr .= "and h.action ~* " . db_encode_str(param('history_action')) . " "; }
    if (param('history_info') =~ /\S/) { $sqlstr .= "and h.info ~* " . db_encode_str(param('history_info')) . " "; }
    $sqlstr .= 'order by h.date;';
#   print "<P>$sqlstr\n";
    undef @q;
    db_query($sqlstr, \@q);
    if (@q) {
	for my $ind1 (0..$#q) {
# Session id -1 = command line script.
	    if ($q[$ind1][1] != -1) {
		$q[$ind1][1] = "<a href='$selfurl?menu=login&amp;sub=session&amp;session_sid=$q[$ind1][1]'>$q[$ind1][1]</a>";
	    }
# Create links to hosts and nets only if they still exist.
# For deleted hosts, create links to hosts' history.
	    if ($q[$ind1][3] == 1) {
		if ($q[$ind1][7]) {
		    $q[$ind1][4] = "<a href='$selfurl?menu=hosts&amp;h_id=$q[$ind1][4]'>$q[$ind1][4]</a>";
		} else {
		    $q[$ind1][4] = "<a href='$selfurl?menu=login&amp;sub=history&amp;history_type=1&amp;history_ref=$q[$ind1][4]'>$q[$ind1][4]</a>";
		}
	    }
	    if ($q[$ind1][3] == 4 && $q[$ind1][8]) {
		$q[$ind1][4] = "<a href='$selfurl?menu=nets&amp;net_id=$q[$ind1][4]'>$q[$ind1][4]</a>";
	    }
# In future, links will be created to users and user groups, according to type.
# Create links to user or user group histories. 03.04.2017 TVu
	    if ($q[$ind1][3] == 5 || $q[$ind1][3] == 6) {
		$q[$ind1][4] = "<a href='$selfurl?menu=login&amp;sub=history&amp;history_type=5&amp;history_ref=$q[$ind1][4]'>$q[$ind1][4]</a>";
	    }
	}
	display_list(['User', 'SID', 'Date', 'Type', 'Ref<br>(Id)', 'Action','Info'], \@q, 0);
    }
  }
  elsif ($sub eq 'motd') {
    print h2("News & motd (message of the day) messages:");
    get_news_list($serverid,10,\@list);
    print "<TABLE width=\"99%\" cellspacing=1 cellpadding=4 " .
          " bgcolor=\"#ccccff\">";
    print "<TR bgcolor=\"#aaaaff\"><TH width=\"70%\">Message</TH>",
          th("Date"),th("Type"),th("By"),"</TR>";
    for $i (0..$#list) {
      my $date=localtime($list[$i][0]);
      my $type=($list[$i][2] < 0 ? 'Global' : 'Local');
      my $msg=$list[$i][3];
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
    show_user_info($state,$perms);
  }

}

1;
# eof
