# Sauron::CGI::Approvals.pm
#
package Sauron::CGI::Approvals;
require Exporter;
use CGI qw/:standard *table -utf8/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::Util;
use Sauron::Approval;
use Sauron::CGI::Utils;
use Sauron::SetupIO;
use HTML::Entities;
use strict;
use vars qw($VERSION @ISA @EXPORT);
use Sys::Syslog qw(:DEFAULT setlogsock);
eval { local $SIG{__WARN__} = sub {}; Sys::Syslog::setlogsock('unix') };

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(
	
);


sub write2log{
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", encode_str("$msg"));
  Sys::Syslog::closelog();
} # End of write2log


sub _audit_user {
  my $user = ($main::state{user} ? $main::state{user} : 'unknown');
  return $user;
}


my %match_mode_enum = (O=>'OR (any rule)', A=>'AND (all rules)');
my %level_type_enum = (O=>'OR (any approver)', A=>'AND (all approvers)');

my %policy_form = (
 data=>[
  {ftype=>0, name=>'Approval policy' },
  {ftype=>4, tag=>'id', name=>'Policy ID'},
  {ftype=>1, tag=>'name', name=>'Policy name', type=>'text', len=>60, maxlen=>200},
  {ftype=>3, tag=>'active', name=>'Active', type=>'enum', enum=>\%boolean_enum},
  {ftype=>3, tag=>'on_add', name=>'On add', type=>'enum', enum=>\%boolean_enum},
  {ftype=>3, tag=>'on_modify', name=>'On modify', type=>'enum', enum=>\%boolean_enum},
  {ftype=>3, tag=>'on_delete', name=>'On delete', type=>'enum', enum=>\%boolean_enum},
  {ftype=>3, tag=>'match_mode', name=>'Match mode', type=>'enum', enum=>\%match_mode_enum},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, empty=>1, anchor=>1, whitesp=>'P'}
 ]
);

my %rule_form = (
 data=>[
  {ftype=>0, name=>'Approval rule' },
  {ftype=>4, tag=>'id', name=>'Rule ID'},
  {ftype=>4, tag=>'policy_id', name=>'Policy ID'},
  {ftype=>1, tag=>'record_types', name=>'Record types (CSV)', type=>'text', len=>40, maxlen=>200, empty=>1},
  {ftype=>1, tag=>'domain_regexp', name=>'Domain regexp', type=>'text', len=>60, maxlen=>200, empty=>1},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, empty=>1, anchor=>1, whitesp=>'P'}
 ]
);

my %level_form = (
 data=>[
  {ftype=>0, name=>'Approval level' },
  {ftype=>4, tag=>'id', name=>'Level ID'},
  {ftype=>4, tag=>'policy_id', name=>'Policy ID'},
  {ftype=>1, tag=>'name', name=>'Level name', type=>'text', len=>60, maxlen=>200},
  {ftype=>1, tag=>'level_order', name=>'Order', type=>'int', len=>4},
  {ftype=>3, tag=>'level_type', name=>'Level type', type=>'enum', enum=>\%level_type_enum},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, empty=>1, anchor=>1, whitesp=>'P'}
 ]
);

my %approver_form = (
 data=>[
  {ftype=>0, name=>'Approver' },
  {ftype=>4, tag=>'id', name=>'Approver ID'},
  {ftype=>4, tag=>'level_id', name=>'Level ID'},
  {ftype=>3, tag=>'user_id', name=>'User', type=>'enum', enum=>{}},
  {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, empty=>1, anchor=>1, whitesp=>'P'}
 ]
);


sub menu_handler {
  my($state,$perms) = @_;
  my $sub = param('sub') || 'list_policies';
  my $zoneid = $state->{zoneid};
  my $selfurl = $state->{selfurl};

  if ($sub eq 'list_policies') {
    _list_policies($zoneid, $selfurl);
  }
  elsif ($sub eq 'add_policy') {
    return unless _require_policy_admin();
    _add_policy($zoneid);
  }
  elsif ($sub eq 'edit_policy') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    $id = scalar param('ap_id') unless ($id > 0);
    _edit_policy($id);
  }
  elsif ($sub eq 'delete_policy') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    $id = scalar param('ap_id') unless ($id > 0);
    _delete_policy($id);
  }
  elsif ($sub eq 'rules') {
    return unless _require_policy_admin();
    _list_rules(scalar param('policy_id'));
  }
  elsif ($sub eq 'add_rule') {
    return unless _require_policy_admin();
    _add_rule(scalar param('policy_id'));
  }
  elsif ($sub eq 'edit_rule') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    my $policy_id = scalar param('policy_id');
    $id = scalar param('ar_id') unless ($id > 0);
    $policy_id = scalar param('ar_policy_id') unless ($policy_id > 0);
    _edit_rule($id, $policy_id);
  }
  elsif ($sub eq 'delete_rule') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    my $policy_id = scalar param('policy_id');
    $id = scalar param('ar_id') unless ($id > 0);
    $policy_id = scalar param('ar_policy_id') unless ($policy_id > 0);
    _delete_rule($id, $policy_id);
  }
  elsif ($sub eq 'levels') {
    return unless _require_policy_admin();
    _list_levels(scalar param('policy_id'));
  }
  elsif ($sub eq 'add_level') {
    return unless _require_policy_admin();
    _add_level(scalar param('policy_id'));
  }
  elsif ($sub eq 'edit_level') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    my $policy_id = scalar param('policy_id');
    $id = scalar param('al_id') unless ($id > 0);
    $policy_id = scalar param('al_policy_id') unless ($policy_id > 0);
    _edit_level($id, $policy_id);
  }
  elsif ($sub eq 'delete_level') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    my $policy_id = scalar param('policy_id');
    $id = scalar param('al_id') unless ($id > 0);
    $policy_id = scalar param('al_policy_id') unless ($policy_id > 0);
    _delete_level($id, $policy_id);
  }
  elsif ($sub eq 'approvers') {
    return unless _require_policy_admin();
    _list_approvers(scalar param('level_id'));
  }
  elsif ($sub eq 'add_approver') {
    return unless _require_policy_admin();
    _add_approver(scalar param('level_id'));
  }
  elsif ($sub eq 'delete_approver') {
    return unless _require_policy_admin();
    _delete_approver(scalar param('id'), scalar param('level_id'));
  }
  elsif ($sub eq 'Edit') {
    return unless _require_policy_admin();
    if (param('ap_id')) {
      _edit_policy(scalar param('ap_id'));
    } elsif (param('ar_id')) {
      _edit_rule(scalar param('ar_id'), scalar param('ar_policy_id'));
    } elsif (param('al_id')) {
      _edit_level(scalar param('al_id'), scalar param('al_policy_id'));
    } else {
      _list_policies($zoneid, $selfurl);
    }
  }
  elsif ($sub eq 'Delete') {
    return unless _require_policy_admin();
    if (param('ap_id')) {
      _delete_policy(scalar param('ap_id'));
    } elsif (param('ar_id')) {
      _delete_rule(scalar param('ar_id'), scalar param('ar_policy_id'));
    } elsif (param('al_id')) {
      _delete_level(scalar param('al_id'), scalar param('al_policy_id'));
    } elsif (param('aa_id')) {
      _delete_approver(scalar param('aa_id'), scalar param('aa_level_id'));
    } else {
      _list_policies($zoneid, $selfurl);
    }
  }
  elsif ($sub eq 'pending') {
    _list_pending($zoneid);
  }
  else {
    _list_policies($zoneid, $selfurl);
  }
}


# ---- UI helpers -------------------------------------------------------

sub _require_policy_admin {
  return 1 if (_is_policy_admin());
  alert1("Access denied: approval policy admin rights required.");
  return 0;
}

sub _is_policy_admin {
  return 1 if (check_perms('level', $main::ALEVEL_APPROVAL_ADMIN, 1) == 0);
  return 1 if (check_perms('zone', 'RW', 1) == 0);
  return 0;
}

sub _list_policies {
  my ($zoneid, $selfurl) = @_;
  my (@q, @qa, $qsql, $msg);

  print h2('Approval policies');
  print p, a({-href=>"$selfurl?menu=approvals&sub=add_policy"}, 'Add policy');
  print p("How to configure approvals: 1) create policy, 2) add rule(s), 3) add level(s), 4) add approver(s) to each level.");

  if ($zoneid > 0) {
    db_query("SELECT id, zone_id, name, active, on_add, on_modify, on_delete, match_mode " .
             "FROM approval_policies WHERE zone_id = " . int($zoneid) . " ORDER BY name",
             \@q);
    db_query("SELECT id FROM approval_policies ORDER BY id", \@qa);
    if (@q == 0 && @qa > 0) {
      $msg = "No policies for current zone id=$zoneid. Policies exist in other zones.";
      print p({-style=>'color:#aa0000;'}, $msg);
    }
  } else {
    db_query("SELECT id, zone_id, name, active, on_add, on_modify, on_delete, match_mode " .
             "FROM approval_policies ORDER BY zone_id, name", \@q);
    print p({-style=>'color:#aa0000;'}, 'Zone is not selected. Showing policies from all zones.');
  }

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Zone</th><th>Name</th><th>Active</th><th>Add</th><th>Modify</th><th>Delete</th><th>Match</th><th>Actions</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $zid, $name, $active, $on_add, $on_mod, $on_del, $match_mode) = @{$q[$i]};
    
    # Map single-letter values to human-readable format
    my $active_display = ($active eq 't') ? 'true' : 'false';
    my $on_add_display = ($on_add eq 't') ? 'true' : 'false';
    my $on_mod_display = ($on_mod eq 't') ? 'true' : 'false';
    my $on_del_display = ($on_del eq 't') ? 'true' : 'false';
    my $match_display = ($match_mode eq 'A') ? 'AND' : 'OR';
    
    my $actions = join(' ',
      a({-href=>"$selfurl?menu=approvals&sub=edit_policy&id=$id"}, 'Edit'),
      a({-href=>"$selfurl?menu=approvals&sub=delete_policy&id=$id"}, 'Delete'),
      a({-href=>"$selfurl?menu=approvals&sub=rules&policy_id=$id"}, 'Rules'),
      a({-href=>"$selfurl?menu=approvals&sub=levels&policy_id=$id"}, 'Levels')
    );
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>$zid</td>\n";
    print "  <td>" . encode_entities($name || '') . "</td>\n";
    print "  <td>$active_display</td>\n";
    print "  <td>$on_add_display</td>\n";
    print "  <td>$on_mod_display</td>\n";
    print "  <td>$on_del_display</td>\n";
    print "  <td>$match_display</td>\n";
    print "  <td>$actions</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _add_policy {
  my ($zoneid) = @_;
  my %data = (zone_id => $zoneid, active => 't', on_modify => 't', match_mode => 'O');
  add_magic('add_policy','Policy','approvals',\%policy_form,\&add_policy,\%data);
}

sub _edit_policy {
  my ($id) = @_;
  edit_magic('ap','Policy','approvals',\%policy_form,\&get_policy,\&update_policy,$id);
}

sub _delete_policy {
  my ($id) = @_;
  delete_magic('ap','Policy','approvals',\%policy_form,\&get_policy,\&delete_policy,$id);
}

sub _list_rules {
  my ($policy_id) = @_;
  my @q;

  print h2('Approval rules');
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: '^www\\.', '^(host|srv)\\d+\\.'");
  print p("Record types examples: '1,6', 'HOST,A,AAAA', 're:^(A|AAAA|HOST)$'");
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  print p, a({-href=>"?menu=approvals&sub=add_rule&policy_id=$policy_id"}, 'Add rule');

  db_query("SELECT id, record_types, domain_regexp, comment " .
           "FROM approval_rules WHERE policy_id = " . int($policy_id) . " ORDER BY id",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Record types</th><th>Domain regexp</th><th>Comment</th><th>Actions</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $types, $re, $comment) = @{$q[$i]};
    my $actions = join(' ',
      a({-href=>"?menu=approvals&sub=edit_rule&id=$id&policy_id=$policy_id"}, 'Edit'),
      a({-href=>"?menu=approvals&sub=delete_rule&id=$id&policy_id=$policy_id"}, 'Delete')
    );
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>" . encode_entities($types || '') . "</td>\n";
    print "  <td>" . encode_entities($re || '') . "</td>\n";
    print "  <td>" . encode_entities($comment || '') . "</td>\n";
    print "  <td>$actions</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _add_rule {
  my ($policy_id) = @_;
  $policy_id = scalar param('policy_id') unless ($policy_id > 0);
  my %data = (policy_id => $policy_id);
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: '^www\\.', '^(host|srv)\\d+\\.'");
  print p("Record types examples: '1,6', 'HOST,A,AAAA', 're:^(A|AAAA|HOST)$'");
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  add_magic('add_rule','Rule','approvals',\%rule_form,\&add_rule,\%data);
}

sub _edit_rule {
  my ($id, $policy_id) = @_;
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: '^www\\.', '^(host|srv)\\d+\\.'");
  print p("Record types examples: '1,6', 'HOST,A,AAAA', 're:^(A|AAAA|HOST)$'");
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  edit_magic('ar','Rule','approvals',\%rule_form,\&get_rule,\&update_rule,$id);
}

sub _delete_rule {
  my ($id, $policy_id) = @_;
  delete_magic('ar','Rule','approvals',\%rule_form,\&get_rule,\&delete_rule,$id);
}

sub _list_levels {
  my ($policy_id) = @_;
  my (@q, @u);

  print h2('Approval levels');
  print p, a({-href=>"?menu=approvals&sub=add_level&policy_id=$policy_id"}, 'Add level');

  db_query("SELECT id, level_order, name, level_type FROM approval_levels " .
           "WHERE policy_id = " . int($policy_id) . " ORDER BY level_order",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Order</th><th>Name</th><th>Type</th><th>Approvers</th><th>Actions</th></TR>\n";
  
  for my $i (0..$#q) {
    my ($id, $order, $name, $type) = @{$q[$i]};
    
    # Map type to description
    my $type_desc = ($type eq 'A') ? 'AND (all approvers)' : 'OR (any approver)';
    
    # Get approvers for this level with name and email
    db_query("SELECT u.username, u.name FROM approval_level_approvers a, users u " .
             "WHERE a.level_id = " . int($id) . " AND a.user_id = u.id ORDER BY u.username",
             \@u);
    
    my @approver_list = ();
    for my $approver (@u) {
      my ($username, $fullname) = @{$approver};
      if ($fullname && $fullname ne '') {
        push @approver_list, encode_entities("$fullname ($username)");
      } else {
        push @approver_list, encode_entities($username);
      }
    }
    
    my $actions = join(' ',
      a({-href=>"?menu=approvals&sub=edit_level&id=$id&policy_id=$policy_id"}, 'Edit'),
      a({-href=>"?menu=approvals&sub=delete_level&id=$id&policy_id=$policy_id"}, 'Delete'),
      a({-href=>"?menu=approvals&sub=approvers&level_id=$id"}, 'Approvers')
    );
    
    # First row with level info
    my $rowspan = scalar(@approver_list) || 1;  # At least 1 row even with no approvers
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td rowspan=$rowspan>$order</td>\n";
    print "  <td rowspan=$rowspan>" . encode_entities($name || '') . "</td>\n";
    print "  <td rowspan=$rowspan>$type_desc</td>\n";
    if (@approver_list) {
      print "  <td>" . $approver_list[0] . "</td>\n";
    } else {
      print "  <td><em>(none)</em></td>\n";
    }
    print "  <td rowspan=$rowspan>$actions</td>\n";
    print "</TR>\n";
    
    # Additional rows for remaining approvers
    for my $j (1..$#approver_list) {
      print "<TR bgcolor=\"#bfeebf\">\n";
      print "  <td>" . $approver_list[$j] . "</td>\n";
      print "</TR>\n";
    }
  }
  
  print "</TABLE>\n";
}

sub _add_level {
  my ($policy_id) = @_;
  $policy_id = scalar param('policy_id') unless ($policy_id > 0);
  my %data = (policy_id => $policy_id, level_order => 1, level_type => 'O');
  add_magic('add_level','Level','approvals',\%level_form,\&add_level,\%data);
}

sub _edit_level {
  my ($id, $policy_id) = @_;
  edit_magic('al','Level','approvals',\%level_form,\&get_level,\&update_level,$id);
}

sub _delete_level {
  my ($id, $policy_id) = @_;
  delete_magic('al','Level','approvals',\%level_form,\&get_level,\&delete_level,$id);
}

sub _list_approvers {
  my ($level_id) = @_;
  my @q;

  print h2('Approvers');
  print p('Approvers assigned here are the users who receive approval emails for this level.');
  print p, a({-href=>"?menu=approvals&sub=add_approver&level_id=$level_id"}, 'Add approver');

  db_query("SELECT a.id, u.username, u.name, a.comment " .
           "FROM approval_level_approvers a, users u " .
           "WHERE a.level_id = " . int($level_id) . " AND a.user_id = u.id ORDER BY u.username",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>User</th><th>Name</th><th>Comment</th><th>Actions</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $username, $name, $comment) = @{$q[$i]};
    my $actions = a({-href=>"?menu=approvals&sub=delete_approver&id=$id&level_id=$level_id"}, 'Delete');
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>" . encode_entities($username || '') . "</td>\n";
    print "  <td>" . encode_entities($name || '') . "</td>\n";
    print "  <td>" . encode_entities($comment || '') . "</td>\n";
    print "  <td>$actions</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _get_level_approvers {
  my ($level_id, $users, $lst) = @_;
  my @q;

  undef @{$lst};
  undef %{$users};

  push @{$lst}, -1;
  $users->{-1} = '--None--';

  db_query(
    "SELECT u.id, u.username || ' - ' || COALESCE(u.name, '') " .
    "FROM users u " .
    "JOIN (" .
      "SELECT ur.ref AS user_id " .
      "FROM approval_levels al, approval_policies ap, zones z, user_rights ur " .
      "WHERE al.id = " . int($level_id) . " " .
      "AND al.policy_id = ap.id " .
      "AND ap.zone_id = z.id " .
      "AND ur.type = 2 AND ur.rtype = 2 AND ur.rref = z.id " .
      "UNION " .
      "SELECT ur_members.ref AS user_id " .
      "FROM approval_levels al, approval_policies ap, zones z, user_rights ur_zone, user_rights ur_members " .
      "WHERE al.id = " . int($level_id) . " " .
      "AND al.policy_id = ap.id " .
      "AND ap.zone_id = z.id " .
      "AND ur_zone.type = 1 AND ur_zone.rtype = 2 AND ur_zone.rref = z.id " .
      "AND ur_members.type = 2 AND ur_members.rtype = 0 AND ur_members.rref = ur_zone.ref" .
    ") eligible ON eligible.user_id = u.id " .
    "WHERE (COALESCE(u.expiration, 0) <= 0 OR COALESCE(u.expiration, 0) > extract(epoch from now())) " .
    "AND lower(COALESCE(u.password, '')) !~ '^locked:' " .
    "AND u.id NOT IN (SELECT user_id FROM approval_level_approvers WHERE level_id = " . int($level_id) . ") " .
    "ORDER BY u.id",
    \@q
  );

  for my $row (@q) {
    push @{$lst}, $row->[0];
    $users->{$row->[0]} = $row->[1];
  }
}

sub _add_approver {
  my ($level_id) = @_;
  # Fallback for POST re-edit: level_id comes from hidden field
  $level_id = int(scalar param('add_approver_level_id')) unless ($level_id > 0);
  
  my (%users, @lst);
  _get_level_approvers($level_id, \%users, \@lst);

  # Create local form definition with dynamically populated enum
  my %local_approver_form = (
    data => [
      {ftype=>0, name=>'Approver' },
      {ftype=>4, tag=>'id', name=>'Approver ID'},
      {ftype=>4, tag=>'level_id', name=>'Level ID'},
      {ftype=>3, tag=>'user_id', name=>'User', type=>'enum', enum=>\%users},
      {ftype=>1, tag=>'comment', name=>'Comments', type=>'text', len=>80, maxlen=>200, empty=>1, anchor=>1, whitesp=>'P'}
    ]
  );

  my %data = (level_id => $level_id);
  add_magic('add_approver','Approver','approvals',\%local_approver_form,\&add_approver,\%data);
}

sub _delete_approver {
  my ($id, $level_id) = @_;
  delete_magic('aa','Approver','approvals',\%approver_form,\&get_approver,\&delete_approver,$id);
}

sub _list_pending {
  my ($zoneid) = @_;
  my @q;

  print h2('Pending approvals');
  @q = get_zone_pending_requests($zoneid);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Request ID</th><th>Requestor ID</th><th>Operation</th><th>Level</th><th>Created</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $req_id, $op, $status, $level, $cdate) = @{$q[$i]};
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>$id</td>\n";
    print "  <td>$req_id</td>\n";
    print "  <td>" . encode_entities($op || '') . "</td>\n";
    print "  <td>$level</td>\n";
    print "  <td>$cdate</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
}


# ---- DB helpers -------------------------------------------------------

sub get_policy {
  my ($id, $rec) = @_;
  my @q;
  db_query("SELECT id, zone_id, name, active, on_add, on_modify, on_delete, " .
           "match_mode, comment FROM approval_policies WHERE id = " . int($id),
           \@q);
  return -1 unless (@q > 0);
  ($rec->{id}, $rec->{zone_id}, $rec->{name}, $rec->{active}, $rec->{on_add},
   $rec->{on_modify}, $rec->{on_delete}, $rec->{match_mode}, $rec->{comment})
    = @{$q[0]};
  return 0;
}

sub add_policy {
  my ($rec) = @_;
  my $user = _audit_user();
  my $res = db_exec("INSERT INTO approval_policies " .
                    "(zone_id, name, active, on_add, on_modify, on_delete, match_mode, comment, cuser, muser) " .
                    "VALUES (" .
                    $rec->{zone_id} . "," .
                    db_encode_str($rec->{name}) . "," .
                    db_encode_str($rec->{active}) . "," .
                    db_encode_str($rec->{on_add}) . "," .
                    db_encode_str($rec->{on_modify}) . "," .
                    db_encode_str($rec->{on_delete}) . "," .
                    db_encode_str($rec->{match_mode}) . "," .
                    db_encode_str($rec->{comment}) . "," .
                    db_encode_str($user) . "," .
                    db_encode_str($user) . ") RETURNING id");
  return ($res < 0 ? -1 : db_lastid());
}

sub update_policy {
  my ($rec) = @_;
  my $user = _audit_user();
  return db_exec("UPDATE approval_policies SET " .
                 "name=" . db_encode_str($rec->{name}) . ", " .
                 "active=" . db_encode_str($rec->{active}) . ", " .
                 "on_add=" . db_encode_str($rec->{on_add}) . ", " .
                 "on_modify=" . db_encode_str($rec->{on_modify}) . ", " .
                 "on_delete=" . db_encode_str($rec->{on_delete}) . ", " .
                 "match_mode=" . db_encode_str($rec->{match_mode}) . ", " .
                 "comment=" . db_encode_str($rec->{comment}) . ", " .
                 "mdate=CURRENT_TIMESTAMP, muser=" . db_encode_str($user) .
                 " WHERE id=" . $rec->{id});
}

sub delete_policy {
  my ($id) = @_;
  return db_exec("DELETE FROM approval_policies WHERE id = " . $id);
}

sub get_rule {
  my ($id, $rec) = @_;
  my @q;
  db_query("SELECT id, policy_id, record_types, domain_regexp, comment " .
           "FROM approval_rules WHERE id = " . int($id), \@q);
  return -1 unless (@q > 0);
  ($rec->{id}, $rec->{policy_id}, $rec->{record_types}, $rec->{domain_regexp}, $rec->{comment})
    = @{$q[0]};
  return 0;
}

sub add_rule {
  my ($rec) = @_;
  my $user = _audit_user();
  my $policy_id = int($rec->{policy_id});
  $policy_id = int(scalar param('policy_id')) unless ($policy_id > 0);
  $policy_id = int(scalar param('add_rule_policy_id')) unless ($policy_id > 0);
  return -1 unless ($policy_id > 0);

  my $res = db_exec("INSERT INTO approval_rules " .
                    "(policy_id, record_types, domain_regexp, comment, cuser, muser) " .
                    "VALUES (" .
                    $policy_id . "," .
                    db_encode_str($rec->{record_types}) . "," .
                    db_encode_str($rec->{domain_regexp}) . "," .
                    db_encode_str($rec->{comment}) . "," .
                    db_encode_str($user) . "," .
                    db_encode_str($user) . ") RETURNING id");
  return ($res < 0 ? -1 : db_lastid());
}

sub update_rule {
  my ($rec) = @_;
  my $user = _audit_user();

  return db_exec("UPDATE approval_rules SET " .
                 "record_types=" . db_encode_str($rec->{record_types}) . ", " .
                 "domain_regexp=" . db_encode_str($rec->{domain_regexp}) . ", " .
                 "comment=" . db_encode_str($rec->{comment}) . ", " .
                 "mdate=CURRENT_TIMESTAMP, muser=" . db_encode_str($user) .
                 " WHERE id=" . $rec->{id});
}

sub delete_rule {
  my ($id) = @_;
  return db_exec("DELETE FROM approval_rules WHERE id = " . $id);
}

sub get_level {
  my ($id, $rec) = @_;
  my @q;
  db_query("SELECT id, policy_id, level_order, level_type, name, comment " .
           "FROM approval_levels WHERE id = " . int($id), \@q);
  return -1 unless (@q > 0);
  ($rec->{id}, $rec->{policy_id}, $rec->{level_order}, $rec->{level_type}, $rec->{name}, $rec->{comment})
    = @{$q[0]};
  return 0;
}

sub add_level {
  my ($rec) = @_;
  my $user = _audit_user();
  my $policy_id = int($rec->{policy_id});
  my $level_order = int($rec->{level_order});

  $policy_id = int(scalar param('policy_id')) unless ($policy_id > 0);
  $policy_id = int(scalar param('add_level_policy_id')) unless ($policy_id > 0);
  return -1 unless ($policy_id > 0);

  $level_order = 1 unless ($level_order > 0);

  my $res = db_exec("INSERT INTO approval_levels " .
                    "(policy_id, level_order, level_type, name, comment, cuser, muser) " .
                    "VALUES (" .
                    $policy_id . "," .
                    $level_order . "," .
                    db_encode_str($rec->{level_type}) . "," .
                    db_encode_str($rec->{name}) . "," .
                    db_encode_str($rec->{comment}) . "," .
                    db_encode_str($user) . "," .
                    db_encode_str($user) . ") RETURNING id");
  return ($res < 0 ? -1 : db_lastid());
}

sub update_level {
  my ($rec) = @_;
  my $user = _audit_user();
  return db_exec("UPDATE approval_levels SET " .
                 "level_order=" . $rec->{level_order} . ", " .
                 "level_type=" . db_encode_str($rec->{level_type}) . ", " .
                 "name=" . db_encode_str($rec->{name}) . ", " .
                 "comment=" . db_encode_str($rec->{comment}) . ", " .
                 "mdate=CURRENT_TIMESTAMP, muser=" . db_encode_str($user) .
                 " WHERE id=" . $rec->{id});
}

sub delete_level {
  my ($id) = @_;
  return db_exec("DELETE FROM approval_levels WHERE id = " . $id);
}

sub get_approver {
  my ($id, $rec) = @_;
  my @q;
  db_query("SELECT id, level_id, user_id, comment FROM approval_level_approvers WHERE id = " . int($id),
           \@q);
  return -1 unless (@q > 0);
  ($rec->{id}, $rec->{level_id}, $rec->{user_id}, $rec->{comment}) = @{$q[0]};
  return 0;
}

sub add_approver {
  my ($rec) = @_;
  my $user = _audit_user();
  my $res = db_exec("INSERT INTO approval_level_approvers (level_id, user_id, comment) " .
                    "VALUES (" .
                    $rec->{level_id} . "," .
                    $rec->{user_id} . "," .
                    db_encode_str($rec->{comment}) . ") RETURNING id");

  if ($res >= 0) {
    my $id = db_lastid();
    db_exec("UPDATE approval_level_approvers SET " .
            "mdate=CURRENT_TIMESTAMP, cuser=" . db_encode_str($user) . ", " .
            "muser=" . db_encode_str($user) . " WHERE id=" . $id);
    return $id;
  }
  return -1;
}

sub delete_approver {
  my ($id) = @_;
  return db_exec("DELETE FROM approval_level_approvers WHERE id = " . $id);
}


1;
