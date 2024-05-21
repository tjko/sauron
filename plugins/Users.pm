# Users.pm -- sauron CGI interface plugin to view and modify user information
#
# Copyright (c) Teppo Vuori 2014.
# $Id:$
#

package Sauron::Plugins::Users;

require Exporter;
use CGI qw/:standard *table -no_xhtml/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::CGI::Utils;
use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );

my %user_info_form=(
 data=>[
  {ftype=>0, name=>'User'},
  {ftype=>1, tag=>'login', name=>'Login', type=>'text', len=>20},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text', len=>40},
  {ftype=>1, tag=>'edate', name=>'Expiration', type=>'edate_str', len=>30},
  {ftype=>1, tag=>'id', name=>'Id', type=>'int', len=>8},
  {ftype=>1, tag=>'superuser', name=>'Superuser', type=>'text', len=>3},
  {ftype=>1, tag=>'last', name=>'Last login time', type=>'cdate_str'},
  {ftype=>1, tag=>'last_pwd', name=>'Last password change', type=>'cdate_str'},
  {ftype=>1, tag=>'search_opts', name=>'Default search options', type=>'text'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text'},
  {ftype=>1, tag=>'email', name=>'Email address', type=>'text'},
  {ftype=>1, tag=>'last_from', name=>'Last login from', type=>'cidr'},
  {ftype=>1, tag=>'notes', name=>'Email notifications', type=>'text'},

  {ftype=>0, name=>'Usable address range'},

  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ],
 nwidth=>'40%'
);

my %group_form = ( # ** Kesken !!!
 data=>[

  {ftype=>0, name=>'User Group' },

  {ftype=>1, tag=>'name', name=>'Name', type=>'???',
   conv=>'L', len=>30, maxlen=>60},

  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',
   len=>60, maxlen=>100},

  {ftype=>4, tag=>'id', name=>'Group ID'},

  {ftype=>0, name=>'Members in This Group' },

  {ftype=>11, tag=>'user_groups', name=>'Users', fields=>2}

 ]
);

###########################################################################

sub menu_handler {
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $sub = param('sub');

  my (%user,@data,$i, @q, $status);

  if (get_user($state->{user},\%user) < 0) {
      fatal("Cannot get user record!");
  };

  if ($sub eq 'Pl_Users_Users') {

      print h3("Users");

# Show buttons.
      { # TVu 2021-04-19
	  my $par_menu = param('menu');
	  my $par_sub = param('sub');
	  print "\n<table><tr><td>";
	  print startform(-method=>'GET', -action=>$selfurl);
	  param('menu', 'login'); print hidden('menu', 'login');
	  param('sub', 'Add-user'); print hidden('sub', 'Add-user');
	  print submit(-name=>'foobar', -value=>'Add user');
	  print end_form,"\n";
	  print "</td>\n<td>";
	  print startform(-method=>'GET', -action=>$selfurl);
	  param('menu', 'login'); print hidden('menu', 'login');
	  param('sub', 'Pl_Users_Groups'); print hidden('sub', 'Pl_Users_Groups');
	  print submit(-name=>'foobar', -value=>'User groups');
	  print end_form,"\n";
	  print "</td>\n<td>";
	  print "</td></table>\n";
	  param('menu', $par_menu);
	  param('sub', $par_sub);
      }

# Get list of users.
      undef @q;
      db_query("select u.username, u.name, coalesce(u.expiration, 0), u.superuser, z.name, " .
	       "s.name, coalesce(ur.rule, '0'), u.id " .
	       "from users u " .
	       "left outer join zones z on u.zone = z.id " .
	       "left outer join servers s on u.server = s.id " .
	       "left outer join user_rights ur on u.id = ur.ref and ur.type = 2 and ur.rtype = 6 " .
	       "order by u.username;", \@q);
      print "<TABLE bgcolor=\"#ccccff\" cellspacing=1 " .
	  " cellpadding=1 border=0>",
	  "<TR bgcolor=\"#aaaaff\">",
	  th("Username"),th("Name"),th('Flags'),th("Zone"),
	  th("Server"),"</TR>\n";
      for $i (0..$#q) {
	  my $trcolor = '#eeeeee';
	  $trcolor = '#ffffcc' if ($i % 2 == 0);
	  $status = get_user_status($q[$i][7]);
	  print "<TR bgcolor='$trcolor'>",
	  td("<a href=\"$selfurl?menu=login&user_id=$q[$i][0]\">$q[$i][0]</a>"),
	  td($q[$i][1]), td($status),
	  td($q[$i][4]),td($q[$i][5]),"\n";
      }
      print "</TABLE>\n";
      print '<BR>Flags:<BR>E = Expired<BR>L = Locked<BR>S = Superuser<BR>' .
	  "Digit(s) = Authorization level (default 0)<BR>&nbsp;\n";

  } elsif ($sub eq 'Pl_Users_Groups') {

      print h3("User Groups");

# Show buttons.
      { # TVu 2021-04-21
	  my $par_menu = param('menu');
	  my $par_sub = param('sub');
	  print "\n<table><tr><td>";
	  print startform(-method=>'GET', -action=>$selfurl);
	  param('menu', 'login'); print hidden('menu', 'login');
	  param('sub', 'Pl_Users_Add-group'); print hidden('sub', 'Pl_Users_Add-group');
	  print submit(-name=>'foobar', -value=>'Add group');
	  print end_form,"\n";
	  print "</td>\n<td>";
	  print startform(-method=>'GET', -action=>$selfurl);
	  param('menu', 'login'); print hidden('menu', 'login');
	  param('sub', 'Pl_Users_Users'); print hidden('sub', 'Pl_Users_Users');
	  print submit(-name=>'foobar', -value=>'Users');
	  print end_form,"\n";
	  print "</td>\n<td>";
	  print "</td></table>\n";
	  param('menu', $par_menu);
	  param('sub', $par_sub);
      }

# Get list of user groups. TVu 2021-04-21
      undef @q;
      db_query("select name, comment " .
	       "from user_groups " .
	       "order by name;", \@q);
      print "<TABLE bgcolor=\"#ccccff\" cellspacing=1 " .
	  " cellpadding=1 border=0>",
	  "<TR bgcolor=\"#aaaaff\">",
	  th("Group name"),th("Comment"),"</TR>\n";
      for $i (0..$#q) {
	  my $trcolor = '#eeeeee';
	  $trcolor = '#ffffcc' if ($i % 2 == 0);
	  print "<TR bgcolor='$trcolor'>", td("<a href=\"$selfurl?" .
		"menu=login&sub=Pl_Users_Show_group&group_id=$q[$i][0]\">$q[$i][0]</a>"),
	        td($q[$i][1]), "\n";
      }
      print "</TABLE>\n";

  }

}

1;
# eof :-)
