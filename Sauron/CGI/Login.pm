# Sauron::CGI::Login.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id$
#
package Sauron::CGI::Login;
require Exporter;
use CGI qw/:standard *table -no_xhtml/;
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



my %user_info_form=(
 data=>[
  {ftype=>0, name=>'User info' },
  {ftype=>4, tag=>'user', name=>'Login'},
  {ftype=>4, tag=>'name', name=>'User Name'},
  {ftype=>4, tag=>'groupname', name=>'Group(s)'},
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
   columns=>50 }
 ]
);


my %change_passwd_form=(
 data=>[
  {ftype=>1, tag=>'old', name=>'Old password', type=>'passwd', len=>20 },
  {ftype=>0, name=>'Type new password twice'},
  {ftype=>1, tag=>'new1', name=>'New password', type=>'passwd', len=>20 },
  {ftype=>1, tag=>'new2', name=>'New password', type=>'passwd', len=>20 }
 ]
);

my %session_id_form=(
 data=>[
  {ftype=>0, name=>'Session browser'},
  {ftype=>1, tag=>'sid', name=>'SID', type=>'int', len=>8, empty=>1 }
 ]
);



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
	  print "<FONT color=\"red\">",h2("New passwords dont match!"),
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
          startform(-method=>'POST',-action=>$selfurl),
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
      get_user($state->{user},\%user);
      goto show_user_info;
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
    print startform(-method=>'POST',-action=>$selfurl),
          hidden('menu','login'),hidden('sub','session');
    form_magic('session',\%h,\%session_id_form);
    print submit(-name=>'session_submit',-value=>'Select'), end_form, "<HR>";

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
  elsif ($sub eq 'motd') {
    print h2("News & motd (message of day) messages:");
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
  show_user_info:
    print h2("User info:");
    $state->{email}=$user{email};
    $state->{name}=$user{name};
    $state->{last_pwd}=$user{last_pwd};
    $state->{expiration}=($user{expiration} > 0 ? 
			localtime($user{expiration}) : 'None');
    $state->{email_notify}=$user{email_notify};
    db_query("SELECT g.name FROM user_groups g, user_rights r " .
	     "WHERE g.id=r.rref AND r.rtype=0 AND r.type=2 " .
	     " AND r.ref=$state->{uid} ORDER BY g.id",\@q);
    $state->{groupname}='';
    for $i (0..$#q) {
      $state->{groupname}.=", " if ($state->{groupname});
      $state->{groupname}.=$q[$i][0];
    }
    display_form($state,\%user_info_form);

    # server permissions
    print h3("Permissions:"),"<TABLE border=0 cellspacing=1>",
	  "<TR bgcolor=\"#aaaaff\"><TD>Type</TD><TD>Ref.</TD>",
	  "<TD>Permissions</TD></TR>";
    foreach $s (keys %{$perms->{server}}) {
      undef @q; 
      db_query("SELECT name FROM servers WHERE id=$s;",\@q);
      $tmp=$q[0][0];
      print "<TR bgcolor=\"#dddddd\">",td("Server"),td("$tmp"),
            td($perms->{server}->{$s}." &nbsp;"),"</TR>";
    }

    # zone permissions
    foreach $s (keys %{$perms->{zone}}) {
      undef @q; 
      db_query("SELECT s.name,z.name FROM zones z, servers s " .
	       "WHERE z.server=s.id AND z.id=$s;",\@q);
      $tmp="$q[0][0]:$q[0][1]";
      print "<TR bgcolor=\"#dddddd\">",td("Zone"),td("$tmp"),
	     td($perms->{zone}->{$s}." &nbsp;"),"</TR>";
    }

    # net permissions
    foreach $s (keys %{$perms->{net}}) {
      undef @q; 
      db_query("SELECT s.name,n.net,n.range_start,n.range_end " .
	       "FROM servers s, nets n WHERE n.server=s.id AND n.id=$s;",\@q);
      $tmp="$q[0][0]:$q[0][1]";
      print "<TR bgcolor=\"#dddddd\">",td("Net"),td("$tmp"),
	     td($perms->{net}->{$s}[0]." - ".$perms->{net}->{$s}[1]),"</TR>";
    }

    # host permissions
    foreach $s (@{$perms->{hostname}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Hostname"),td("$s"),
	     td("(hostname constraint)"),"</TR>";
    }

    # IP-mask permissions
    foreach $s (@{$perms->{ipmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("IP-mask"),td("$s"),
	     td("(IP address constraint)"),"</TR>";
    }
    # Delete-mask permissions
    foreach $s (@{$perms->{delmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Del-mask"),td("$s"),
	     td("(Delete host mask)"),"</TR>";
    }
    # Template-mask permissions
    foreach $s (@{$perms->{tmplmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Template-mask"),td("$s"),
	     td("(Template modify mask)"),"</TR>";
    }
    # Group-mask permissions
    foreach $s (@{$perms->{grpmask}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Group-mask"),td("$s"),
	     td("(Group modify mask)"),"</TR>";
    }

    # RHF
    foreach $s (sort keys %{$perms->{rhf}}) {
      print "<TR bgcolor=\"#dddddd\">",td("ReqHostField"),td("$s"),
	    td(($perms->{rhf}->{$s} ? 'Optional':'Required')),"</TR>";
    }

    # Flags
    foreach $s (sort keys %{$perms->{flags}}) {
      print "<TR bgcolor=\"#dddddd\">",td("Flag"),td("$s"),
	    td('(add/modify permission)'),"</TR>";
    }

    # alevel permissions
    print "<TR bgcolor=\"#dddddd\">",td("Level"),td($perms->{alevel}),
	     td("(authorization level)"),"</TR>";


    print "</TABLE><P>&nbsp;";
  }
}



1;
# eof
