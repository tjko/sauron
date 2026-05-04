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

sub _example_code {
  my ($text) = @_;
  return code({-style=>'background-color:#f5f5f5; padding:2px 6px; border:1px solid #ddd; border-radius:3px; font-family:monospace;'}, $text);
}

sub _bool_to_icon {
  my ($value, $label) = @_;
  my $checkmark = chr(0x2705);  # ✅ green checkmark
  my $cross = chr(0x274C);      # ❌ red cross
  if ($value eq 't') {
    return '<span title="' . encode_entities($label || 'Yes') . '" style="cursor:pointer; font-size:1.2em;">' . $checkmark . '</span>';
  } else {
    return '<span title="' . encode_entities($label || 'No') . '" style="cursor:pointer; font-size:1.2em;">' . $cross . '</span>';
  }
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

  # Require zone selection for approval management
  # Only list_policies can show cross-zone view for policy admins
  if ($zoneid <= 0 && $sub ne 'list_policies') {
    print h2('Zone selection required');
    print p('Approval management requires a zone to be selected.');
    print p(a({-href=>"$selfurl?menu=zones"}, 'Select a zone'));
    return;
  }

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
    _list_approvers(scalar param('level_id'));
  }
  elsif ($sub eq 'add_approver') {
    return unless _require_policy_admin();
    _add_approver(scalar param('level_id'));
  }
  elsif ($sub eq 'delete_approver') {
    return unless _require_policy_admin();
    my $id = scalar param('id');
    my $level_id = scalar param('level_id');
    $id = scalar param('aa_id') unless ($id > 0);
    $level_id = scalar param('aa_level_id') unless ($level_id > 0);
    _delete_approver($id, $level_id);
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
    _list_pending($zoneid, $selfurl);
  }
  elsif ($sub eq 'all_requests') {
    _list_all_requests($zoneid, $selfurl);
  }
  elsif ($sub eq 'show_request') {
    _show_request(scalar param('req_id'), $zoneid, $selfurl);
  }
  elsif ($sub eq 'approve_action') {
    my $req_id = scalar param('req_id');
    my $action = lc(scalar param('action') || '');  # Convert to lowercase
    my $reason = scalar param('decision_reason') || '';
    _process_approval_action($req_id, $action, $reason, $selfurl);
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
  return 1 if (check_perms('zone', 'A', 1) == 0);
  return 0;
}

sub _get_level_name {
  my ($policy_id, $level_order, $cache_ref) = @_;
  my @lvl;
  my $key;

  return '' unless ($policy_id > 0 && defined $level_order);
  $key = int($policy_id) . ':' . $level_order;

  if (defined $cache_ref && ref($cache_ref) eq 'HASH' && exists $cache_ref->{$key}) {
    return $cache_ref->{$key};
  }

  db_query("SELECT name FROM approval_levels WHERE policy_id = \$1 AND level_order = \$2",
           \@lvl, int($policy_id), $level_order);

  my $name = (@lvl > 0 && defined $lvl[0][0] ? $lvl[0][0] : '');
  if (defined $cache_ref && ref($cache_ref) eq 'HASH') {
    $cache_ref->{$key} = $name;
  }
  return $name;
}

sub _format_level_display {
  my ($level_order, $level_name) = @_;
  my $display = encode_entities(defined $level_order ? "$level_order" : '?');

  if (defined $level_name && $level_name ne '') {
    $display .= ' (' . encode_entities($level_name) . ')';
  }

  return $display;
}

# _is_user_approver_for_request(req_id) - Check if current logged-in user is an approver
sub _is_user_approver_for_request {
  my ($req_id) = @_;
  my (@req, @level, @approvers);
  my ($current_user_id, $policy_id, $current_level, $level_id);
  
  return 0 unless (defined $req_id && $req_id > 0);
  return 0 unless (defined $main::state{uid});
  $current_user_id = $main::state{uid};
  
  # Superusers can always approve requests
  return 1 if ($main::state{superuser} eq 'yes');
  
  # Get request's policy and current level
  db_query("SELECT policy_id, current_level FROM dns_change_requests WHERE id = \$1",
           \@req, $req_id);
  return 0 unless (@req > 0);
  ($policy_id, $current_level) = @{$req[0]};
  
  # Get level_id for current approval level
  db_query("SELECT id FROM approval_levels WHERE policy_id = \$1 AND level_order = \$2",
           \@level, $policy_id, $current_level);
  return 0 unless (@level > 0);
  $level_id = $level[0][0];
  
  # Check if current user is an approver for this level
  db_query("SELECT user_id FROM approval_level_approvers WHERE level_id = \$1 AND user_id = \$2",
           \@approvers, $level_id, $current_user_id);
  return (@approvers > 0 ? 1 : 0);
}

sub _can_view_request {
  my ($selected_zone_id, $request_zone_id) = @_;

  return 1 if ($main::state{superuser} eq 'yes');
  return 0 unless ($selected_zone_id > 0 && $request_zone_id > 0);
  return 0 unless ($selected_zone_id == $request_zone_id);

  return (check_perms('zone', 'R', 1) == 0 ? 1 : 0);
}

sub _list_policies {
  my ($zoneid, $selfurl) = @_;
  my (@q, @qa, $qsql, $msg);
  my $is_admin = _is_policy_admin();
  my %zone_names = (); # Cache for zone names

  print h2('Approval policies');
  
  if ($zoneid > 0) {
    if ($is_admin) {
      print p, a({-href=>"$selfurl?menu=approvals&sub=add_policy"}, 'Add policy');
      print p("How to configure approvals: 1) create policy, 2) add rule(s), 3) add level(s), 4) add approver(s) to each level.");
    }
    db_query("SELECT id, zone_id, name, active, on_add, on_modify, on_delete, match_mode " .
             "FROM approval_policies WHERE zone_id = " . int($zoneid) . " ORDER BY name",
             \@q);
    db_query("SELECT id FROM approval_policies ORDER BY id", \@qa);
    if (@q == 0 && @qa > 0) {
      $msg = "No policies for current zone. Policies exist in other zones.";
      print p({-style=>'color:#aa0000;'}, $msg);
    }
  } else {
    # No zone selected - show cross-zone policy view for admins only
    if (!$is_admin) {
      print p('Zone selection is required to manage approvals.');
      print p(a({-href=>"$selfurl?menu=zones"}, 'Select a zone'));
      return;
    }
    db_query("SELECT id, zone_id, name, active, on_add, on_modify, on_delete, match_mode " .
             "FROM approval_policies ORDER BY zone_id, name", \@q);
    print p({-style=>'color:#aa0000;'}, 'Zone is not selected. Showing policies from all zones (admin view only).');
    
    # Load zone names for displaying instead of IDs
    my @zone_ids;
    for my $row (@q) {
      push @zone_ids, $row->[1]; # zone_id is at index 1
    }
    if (@zone_ids > 0) {
      my @zone_rows;
      my $zone_ids_str = join(',', grep { $_ > 0 } @zone_ids);
      if ($zone_ids_str) {
        db_query("SELECT id, name FROM zones WHERE id IN ($zone_ids_str)", \@zone_rows);
        for my $z (@zone_rows) {
          $zone_names{$z->[0]} = $z->[1];
        }
      }
    }
  }

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  my @headers;
  if ($zoneid > 0) {
    @headers = qw(Name Active Add Modify Delete Match View);
  } else {
    @headers = qw(Zone Name Active Add Modify Delete Match View);
  }
  push @headers, 'Edit' if $is_admin;
  print "<TR bgcolor=\"#aaaaff\"><th>" . join("</th><th>", @headers) . "</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $zid, $name, $active, $on_add, $on_mod, $on_del, $match_mode) = @{$q[$i]};
    
    # Map single-letter values to human-readable format (with emoji icons)
    my $active_display = _bool_to_icon($active, 'Active');
    my $on_add_display = _bool_to_icon($on_add, 'On add');
    my $on_mod_display = _bool_to_icon($on_mod, 'On modify');
    my $on_del_display = _bool_to_icon($on_del, 'On delete');
    my $match_display = ($match_mode eq 'A') ? 'AND' : 'OR';
    
    print "<TR bgcolor=\"#bfeebf\">\n";
    if ($zoneid == 0) {
      # Show zone name when no zone is selected
      my $zone_name = $zone_names{$zid} || "Zone $zid";
      print "  <td>" . encode_entities($zone_name) . "</td>\n";
    }
    print "  <td>" . encode_entities($name || '') . "</td>\n";
    print "  <td style=\"text-align:center;\">$active_display</td>\n";
    print "  <td style=\"text-align:center;\">$on_add_display</td>\n";
    print "  <td style=\"text-align:center;\">$on_mod_display</td>\n";
    print "  <td style=\"text-align:center;\">$on_del_display</td>\n";
    print "  <td>$match_display</td>\n";
    
    # View links (Rules and Levels) for all users
    my $view_actions = join(' ',
      a({-href=>"$selfurl?menu=approvals&sub=rules&policy_id=$id"}, 'Rules'),
      a({-href=>"$selfurl?menu=approvals&sub=levels&policy_id=$id"}, 'Levels')
    );
    print "  <td>$view_actions</td>\n";
    
    if ($is_admin) {
      my $edit_actions = join(' ',
        a({-href=>"$selfurl?menu=approvals&sub=edit_policy&id=$id"}, 'Edit'),
        a({-href=>"$selfurl?menu=approvals&sub=delete_policy&id=$id"}, 'Delete')
      );
      print "  <td>$edit_actions</td>\n";
    }
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _add_policy {
  my ($zoneid) = @_;
  my %data = (zone_id => $zoneid, active => 't', on_modify => 't', match_mode => 'O');
  my $res = add_magic('add_policy','Policy','approvals',\%policy_form,\&add_policy,\%data);
  if ($res > 0) {
    print p, a({-href=>"?menu=approvals"}, 'Back to policies');
  }
}

sub _edit_policy {
  my ($id) = @_;
  my $res = edit_magic('ap','Policy','approvals',\%policy_form,\&get_policy,\&update_policy,$id);
  if ($res > 0) {
    print p, a({-href=>"?menu=approvals"}, 'Back to policies');
  }
}

sub _delete_policy {
  my ($id) = @_;
  my $res = delete_magic('ap','Policy','approvals',\%policy_form,\&get_policy,\&delete_policy,$id);
  if ($res > 0) {
    print p, a({-href=>"?menu=approvals"}, 'Back to policies');
  }
}

sub _list_rules {
  my ($policy_id) = @_;
  my (@q, $is_admin);
  $is_admin = _is_policy_admin();

  print h2('Approval rules');
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: " . _example_code('^www\\.') . ', ' . _example_code('^(host|srv)\\d+\\.'));
  print p("Record types examples: " . _example_code('1,6') . ', ' . _example_code('HOST,A,AAAA') . ', ' . _example_code('re:^(A|AAAA|HOST)$'));
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  if ($is_admin) {
    print p, a({-href=>"?menu=approvals&sub=add_rule&policy_id=$policy_id"}, 'Add rule');
  }

  db_query("SELECT id, record_types, domain_regexp, comment " .
           "FROM approval_rules WHERE policy_id = " . int($policy_id) . " ORDER BY id",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  my @headers = ('Record types', 'Domain regexp', 'Comment');
  push @headers, 'Actions' if $is_admin;
  print "<TR bgcolor=\"#aaaaff\"><th>" . join("</th><th>", @headers) . "</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $types, $re, $comment) = @{$q[$i]};
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>" . encode_entities($types || '') . "</td>\n";
    print "  <td>" . encode_entities($re || '') . "</td>\n";
    print "  <td>" . encode_entities($comment || '') . "</td>\n";
    if ($is_admin) {
      my $actions = join(' ',
        a({-href=>"?menu=approvals&sub=edit_rule&id=$id&policy_id=$policy_id"}, 'Edit'),
        a({-href=>"?menu=approvals&sub=delete_rule&id=$id&policy_id=$policy_id"}, 'Delete')
      );
      print "  <td>$actions</td>\n";
    }
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _add_rule {
  my ($policy_id) = @_;
  $policy_id = scalar param('policy_id') unless ($policy_id > 0);
  my %data = (policy_id => $policy_id);
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: " . _example_code('^www\\.') . ', ' . _example_code('^(host|srv)\\d+\\.'));
  print p("Record types examples: " . _example_code('1,6') . ', ' . _example_code('HOST,A,AAAA') . ', ' . _example_code('re:^(A|AAAA|HOST)$'));
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  my $res = add_magic('add_rule','Rule','approvals',\%rule_form,\&add_rule,\%data);
  if ($res > 0) {
    # Re-load policy_id from parameter after POST
    $policy_id = scalar param('policy_id') unless ($policy_id > 0);
    print p, a({-href=>"?menu=approvals&sub=rules&policy_id=$policy_id"}, 'Back to rules');
  }
}

sub _edit_rule {
  my ($id, $policy_id) = @_;
  print p('Rule match behavior: empty field means any value.');
  print p("Domain regexp examples: " . _example_code('^www\\.') . ', ' . _example_code('^(host|srv)\\d+\\.'));
  print p("Record types examples: " . _example_code('1,6') . ', ' . _example_code('HOST,A,AAAA') . ', ' . _example_code('re:^(A|AAAA|HOST)$'));
  print p('Supported symbolic names: HOST, DELEGATION, MX, ALIAS/CNAME, GLUE, SRV, DHCP, SSHFP, TLSA, TXT, NAPTR, CAA, RESERVATION, A, AAAA.');
  my $res = edit_magic('ar','Rule','approvals',\%rule_form,\&get_rule,\&update_rule,$id);
  if ($res > 0) {
    # Load policy_id from DB if not provided
    unless ($policy_id > 0) {
      my @q;
      db_query("SELECT policy_id FROM approval_rules WHERE id = " . int($id), \@q);
      $policy_id = $q[0][0] if (@q > 0);
    }
    print p, a({-href=>"?menu=approvals&sub=rules&policy_id=$policy_id"}, 'Back to rules');
  }
}

sub _delete_rule {
  my ($id, $policy_id) = @_;
  my $res = delete_magic('ar','Rule','approvals',\%rule_form,\&get_rule,\&delete_rule,$id);
  if ($res > 0) {
    # Load policy_id from DB if not provided
    unless ($policy_id > 0) {
      my @q;
      db_query("SELECT policy_id FROM approval_rules WHERE id = " . int($id), \@q);
      $policy_id = $q[0][0] if (@q > 0);
    }
    print p, a({-href=>"?menu=approvals&sub=rules&policy_id=$policy_id"}, 'Back to rules');
  }
}

sub _list_levels {
  my ($policy_id) = @_;
  my (@q, @u, $is_admin);
  $is_admin = _is_policy_admin();

  print h2('Approval levels');
  if ($is_admin) {
    print p, a({-href=>"?menu=approvals&sub=add_level&policy_id=$policy_id"}, 'Add level');
  }

  db_query("SELECT id, level_order, name, level_type FROM approval_levels " .
           "WHERE policy_id = " . int($policy_id) . " ORDER BY level_order",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  my @headers = qw(Order Name Type Approvers);
  push @headers, 'Actions' if $is_admin;
  print "<TR bgcolor=\"#aaaaff\"><th>" . join("</th><th>", @headers) . "</th></TR>\n";
  
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
    
    if ($is_admin) {
      my $actions = join(' ',
        a({-href=>"?menu=approvals&sub=edit_level&id=$id&policy_id=$policy_id"}, 'Edit'),
        a({-href=>"?menu=approvals&sub=delete_level&id=$id&policy_id=$policy_id"}, 'Delete'),
        a({-href=>"?menu=approvals&sub=approvers&level_id=$id"}, 'Approvers')
      );
      print "  <td rowspan=$rowspan>$actions</td>\n";
    }
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
  my $res = add_magic('add_level','Level','approvals',\%level_form,\&add_level,\%data);
  if ($res > 0) {
    # Re-load policy_id from parameter after POST
    $policy_id = scalar param('policy_id') unless ($policy_id > 0);
    print p, a({-href=>"?menu=approvals&sub=levels&policy_id=$policy_id"}, 'Back to levels');
  }
}

sub _edit_level {
  my ($id, $policy_id) = @_;
  my $res = edit_magic('al','Level','approvals',\%level_form,\&get_level,\&update_level,$id);
  if ($res > 0) {
    # Load policy_id from DB if not provided
    unless ($policy_id > 0) {
      my @q;
      db_query("SELECT policy_id FROM approval_levels WHERE id = " . int($id), \@q);
      $policy_id = $q[0][0] if (@q > 0);
    }
    print p, a({-href=>"?menu=approvals&sub=levels&policy_id=$policy_id"}, 'Back to levels');
  }
}

sub _delete_level {
  my ($id, $policy_id) = @_;
  my $res = delete_magic('al','Level','approvals',\%level_form,\&get_level,\&delete_level,$id);
  if ($res > 0) {
    # Load policy_id from DB if not provided
    unless ($policy_id > 0) {
      my @q;
      db_query("SELECT policy_id FROM approval_levels WHERE id = " . int($id), \@q);
      $policy_id = $q[0][0] if (@q > 0);
    }
    print p, a({-href=>"?menu=approvals&sub=levels&policy_id=$policy_id"}, 'Back to levels');
  }
}

sub _list_approvers {
  my ($level_id) = @_;
  my (@q, $is_admin);
  $is_admin = _is_policy_admin();

  print h2('Approvers');
  print p('Approvers assigned here are the users who receive approval emails for this level.');
  if ($is_admin) {
    print p, a({-href=>"?menu=approvals&sub=add_approver&level_id=$level_id"}, 'Add approver');
  }

  db_query("SELECT a.id, u.username, u.name, a.comment " .
           "FROM approval_level_approvers a, users u " .
           "WHERE a.level_id = " . int($level_id) . " AND a.user_id = u.id ORDER BY u.username",
           \@q);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  my @headers = qw(User Name Comment);
  push @headers, 'Actions' if $is_admin;
  print "<TR bgcolor=\"#aaaaff\"><th>" . join("</th><th>", @headers) . "</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $username, $name, $comment) = @{$q[$i]};
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>" . encode_entities($username || '') . "</td>\n";
    print "  <td>" . encode_entities($name || '') . "</td>\n";
    print "  <td>" . encode_entities($comment || '') . "</td>\n";
    if ($is_admin) {
      my $actions = a({-href=>"?menu=approvals&sub=delete_approver&id=$id&level_id=$level_id"}, 'Delete');
      print "  <td>$actions</td>\n";
    }
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
  my $res = add_magic('add_approver','Approver','approvals',\%local_approver_form,\&add_approver,\%data);
  if ($res > 0) {
    # Re-load level_id from parameter after POST
    $level_id = int(scalar param('add_approver_level_id')) unless ($level_id > 0);
    print p, a({-href=>"?menu=approvals&sub=approvers&level_id=$level_id"}, 'Back to approvers');
  }
}

sub _delete_approver {
  my ($id, $level_id) = @_;
  my $res = delete_magic('aa','Approver','approvals',\%approver_form,\&get_approver,\&delete_approver,$id);
  if ($res > 0) {
    # Load level_id from DB if not provided
    unless ($level_id > 0) {
      my @q;
      db_query("SELECT level_id FROM approval_level_approvers WHERE id = " . int($id), \@q);
      $level_id = $q[0][0] if (@q > 0);
    }
    print p, a({-href=>"?menu=approvals&sub=approvers&level_id=$level_id"}, 'Back to approvers');
  }
}

sub _list_pending {
  my ($zoneid, $selfurl) = @_;
  my @q;
  my @policies;
  my %user_cache;
  my %policy_cache;
  my %level_name_cache;
  my %op_name = ('A' => 'Add', 'M' => 'Modify', 'D' => 'Delete');

  print h2('Pending approvals');
  @q = get_zone_pending_requests($zoneid);
  
  # Load policies for zone to get policy_id -> level_id mapping
  db_query("SELECT id FROM approval_policies WHERE zone_id = \$1", \@policies, $zoneid);

  print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Request ID</th><th>Domain / Record</th><th>Requestor</th><th>Operation</th><th>Level</th><th>Created</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $req_id, $req_email, $op, $status, $level, $cdate, $change_data, $policy_id) = @{$q[$i]};
    my $level_name = _get_level_name($policy_id, $level, \%level_name_cache);
    my $level_display = _format_level_display($level, $level_name);
    
    # Get requestor name
    my $req_name = '';
    if (!defined $user_cache{$req_id}) {
      my @usr;
      db_query("SELECT username FROM users WHERE id = \$1", \@usr, $req_id);
      $user_cache{$req_id} = (@usr > 0 ? $usr[0][0] : '?');
    }
    $req_name = $user_cache{$req_id};
    
    # Deserialize change_data to get domain and type
    my $domain = '?';
    my $type_name = '?';
    if (defined $change_data) {
      my $rec = _deserialize($change_data);
      if ($rec && ref($rec) eq 'HASH') {
        $domain = $rec->{domain} || '?';
        my $type = $rec->{type} || 0;
        my %type_names = (
          1 => 'Host (A/AAAA)', 2 => 'Delegation (NS)', 3 => 'Nameserver (MX)', 
          4 => 'Alias (CNAME)', 5 => 'Printer', 6 => 'Glue', 8 => 'SRV',
          9 => 'DHCP', 11 => 'SSHFP', 12 => 'TLSA', 13 => 'TXT', 
          14 => 'NAPTR', 15 => 'CAA', 101 => 'Reservation'
        );
        $type_name = $type_names{$type} || "Type $type";
      }
    }
    
    # Create request link
    my $request_link = "<a href=\"$selfurl?menu=approvals&sub=show_request&req_id=$id\">$id</a>";
    
    # Create level link to Approval Levels if policy_id exists
    my $level_link = $level_display;
    if ($policy_id > 0) {
      $level_link = "<a href=\"$selfurl?menu=approvals&sub=levels&policy_id=$policy_id\">$level_display</a>";
    }
    
    print "<TR bgcolor=\"#bfeebf\">\n";
    print "  <td>$request_link</td>\n";
    print "  <td>" . encode_entities($domain) . " (" . encode_entities($type_name) . ")</td>\n";
    print "  <td>" . encode_entities($req_name) . " (" . encode_entities($req_email || '') . ")</td>\n";
    print "  <td>" . encode_entities($op_name{$op} || $op) . "</td>\n";
    print "  <td>$level_link</td>\n";
    print "  <td>$cdate</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
}

sub _list_all_requests {
  my ($zoneid, $selfurl) = @_;
  my @q;
  my %user_cache;
  my %level_name_cache;
  my %status_name = ('P' => 'Pending', 'A' => 'Approved', 'R' => 'Rejected');
  my %op_name = ('A' => 'Add', 'M' => 'Modify', 'D' => 'Delete');

  print h2('All DNS change requests');
  
  # Get ALL requests for the zone, regardless of status
  db_query("SELECT id, requestor_id, requestor_email, operation, status, current_level, " .
           "cdate, change_data, policy_id FROM dns_change_requests WHERE zone_id = \$1 " .
           "ORDER BY cdate DESC", \@q, $zoneid);

  if (@q == 0) {
    print "<p><i>No requests found.</i></p>\n";
    print "<p><a href=\"$selfurl?menu=approvals&sub=pending\">Back to Pending Approvals</a></p>\n";
    return;
  }

  print "<TABLE bgcolor=\"#e0e0ff\" width=\"99%\" cellspacing=1 cellpadding=1 border=0>\n";
  print "<TR bgcolor=\"#aaaaff\"><th>Request ID</th><th>Domain / Record</th><th>Requestor</th><th>Operation</th><th>Status</th><th>Level</th><th>Created</th></TR>\n";
  for my $i (0..$#q) {
    my ($id, $req_id, $req_email, $op, $status, $level, $cdate, $change_data, $policy_id) = @{$q[$i]};
    my $level_name = _get_level_name($policy_id, $level, \%level_name_cache);
    my $level_display = _format_level_display($level, $level_name);
    
    # Get requestor name
    my $req_name = '';
    if (!defined $user_cache{$req_id}) {
      my @usr;
      db_query("SELECT username FROM users WHERE id = \$1", \@usr, $req_id);
      $user_cache{$req_id} = (@usr > 0 ? $usr[0][0] : '?');
    }
    $req_name = $user_cache{$req_id};
    
    # Deserialize change_data to get domain and type
    my $domain = '?';
    my $type_name = '?';
    if (defined $change_data) {
      my $rec = _deserialize($change_data);
      if ($rec && ref($rec) eq 'HASH') {
        $domain = $rec->{domain} || '?';
        my $type = $rec->{type} || 0;
        my %type_names = (
          1 => 'Host (A/AAAA)', 2 => 'Delegation (NS)', 3 => 'Nameserver (MX)', 
          4 => 'Alias (CNAME)', 5 => 'Printer', 6 => 'Glue', 8 => 'SRV',
          9 => 'DHCP', 11 => 'SSHFP', 12 => 'TLSA', 13 => 'TXT', 
          14 => 'NAPTR', 15 => 'CAA', 101 => 'Reservation'
        );
        $type_name = $type_names{$type} || "Type $type";
      }
    }
    
    # Create request link
    my $request_link = "<a href=\"$selfurl?menu=approvals&sub=show_request&req_id=$id\">$id</a>";
    
    # Status color based on status
    my $status_color;
    if ($status eq 'P') {
      $status_color = '#ffffcc';  # Yellow for pending
    } elsif ($status eq 'A') {
      $status_color = '#ccffcc';  # Green for approved
    } elsif ($status eq 'R') {
      $status_color = '#ffcccc';  # Red for rejected
    } else {
      $status_color = '#f0f0f0';  # Gray for unknown
    }
    
    my $status_display = $status_name{$status} || $status;
    
    print "<TR bgcolor=\"$status_color\">\n";
    print "  <td>$request_link</td>\n";
    print "  <td>" . encode_entities($domain) . " (" . encode_entities($type_name) . ")</td>\n";
    print "  <td>" . encode_entities($req_name) . " (" . encode_entities($req_email || '') . ")</td>\n";
    print "  <td>" . encode_entities($op_name{$op} || $op) . "</td>\n";
    print "  <td>" . encode_entities($status_display) . "</td>\n";
    print "  <td>$level_display</td>\n";
    print "  <td>$cdate</td>\n";
    print "</TR>\n";
  }
  print "</TABLE>\n";
  
  print "<p><a href=\"$selfurl?menu=approvals&sub=pending\">Back to Pending Approvals</a></p>\n";
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

# Helper function to deserialize change_data
sub _deserialize {
	my ($text) = @_;
	return undef unless (defined $text);
	my $VAR1;
	# Handle both $VAR1 = {...} format and terse {...} format
	$text = '$VAR1 = ' . $text unless ($text =~ /^\$VAR1\s*=/);
	eval $text;
	return $@ ? undef : $VAR1;
}

# Show approval request details
sub _show_request {
	my ($req_id, $zoneid, $selfurl) = @_;
	my (@req, @usr, @lvl, @tokens);
	my ($zone_id, $policy_id, $requestor_id, $requestor_email, $operation, 
	    $status, $current_level, $host_id, $change_data, $reason, $cdate);
	my %op_name = ('A' => 'Add', 'M' => 'Modify', 'D' => 'Delete');
	my %status_name = ('P' => 'Pending', 'A' => 'Approved', 'R' => 'Rejected');

	return unless (defined $req_id && $req_id > 0);

	# Get request details
	db_query("SELECT zone_id, policy_id, requestor_id, requestor_email, operation, " .
		 "status, current_level, host_id, change_data, reason, cdate " .
		 "FROM dns_change_requests WHERE id = \$1", \@req, $req_id);
	return unless (@req > 0);

	($zone_id, $policy_id, $requestor_id, $requestor_email, $operation, 
	 $status, $current_level, $host_id, $change_data, $reason, $cdate) = @{$req[0]};

  unless (_can_view_request($zoneid, $zone_id)) {
    print h2('Access Denied');
    print p('This request is outside your current zone access.');
    print "<p><a href=\"$selfurl?menu=approvals&sub=pending\">Back to Pending Approvals</a></p>\n";
    return;
  }

	# Deserialize change_data
	my $rec = _deserialize($change_data);
	return unless ($rec && ref($rec) eq 'HASH');

	# Get requestor name
	db_query("SELECT username FROM users WHERE id = \$1", \@usr, $requestor_id);
	my $requestor_name = (@usr > 0 ? $usr[0][0] : '?');
  my $level_name = _get_level_name($policy_id, $current_level);
  my $current_level_display = _format_level_display($current_level, $level_name);

	# Map type
	my %type_names = (
		1 => 'Host (A/AAAA)', 2 => 'Delegation (NS)', 3 => 'Nameserver (MX)',
		4 => 'Alias (CNAME)', 5 => 'Printer', 6 => 'Glue', 8 => 'SRV',
		9 => 'DHCP', 11 => 'SSHFP', 12 => 'TLSA', 13 => 'TXT',
		14 => 'NAPTR', 15 => 'CAA', 101 => 'Reservation'
	);
	my $type_name = $type_names{$rec->{type} || 0} || "Type " . ($rec->{type} || 'unknown');

	print h2('Approval Request Details');

	# Display request information
	print "<TABLE bgcolor=\"#ccccff\" width=\"99%\" cellspacing=1 cellpadding=2 border=0>\n";
	print "<TR bgcolor=\"#aaaaff\"><th colspan=\"2\">Request Information</th></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Request ID:</td><td>$req_id</td></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Domain:</td><td>" . encode_entities($rec->{domain} || '?') . "</td></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Record Type:</td><td>" . encode_entities($type_name) . "</td></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Operation:</td><td>" . encode_entities($op_name{$operation} || $operation) . "</td></TR>\n";
  print "<TR bgcolor=\"#bfeebf\"><td>Status:</td><td>" . encode_entities($status_name{$status} || $status) . "</td></TR>\n";
  print "<TR bgcolor=\"#bfeebf\"><td>Current Level:</td><td>$current_level_display</td></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Requestor:</td><td>" . encode_entities($requestor_name) . " (" . encode_entities($requestor_email || '') . ")</td></TR>\n";
	print "<TR bgcolor=\"#bfeebf\"><td>Created:</td><td>$cdate</td></TR>\n";
	if (defined $reason && $reason ne '') {
		print "<TR bgcolor=\"#bfeebf\"><td>Reason:</td><td>" . encode_entities($reason) . "</td></TR>\n";
	}
	print "</TABLE>\n";

	# Display record data in a structured format
	print h3('Record Data');
	print "<TABLE bgcolor=\"#e0e0e0\" width=\"99%\" cellspacing=1 cellpadding=2 border=0>\n";
	print "<TR bgcolor=\"#aaaaaa\"><th align=\"left\" colspan=\"2\"><FONT color=\"white\">Fields</FONT></th></TR>\n";

	# Display key fields from change_data
	my @fields = ('domain', 'type', 'ether', 'email', 'comment', 'info');
	for my $field (@fields) {
		next unless (defined $rec->{$field});
		next if ($field eq 'domain' || $field eq 'type'); # Already shown above
		my $val = $rec->{$field};
		next if ($val eq '' || !defined $val);
		print "<TR bgcolor=\"#f0f0f0\"><td>" . encode_entities($field) . ":</td><td>" . encode_entities($val) . "</td></TR>\n";
	}

	# Display IP addresses if present
	if (defined $rec->{ip} && ref($rec->{ip}) eq 'ARRAY' && @{$rec->{ip}} > 0) {
		print "<TR bgcolor=\"#aaaaaa\"><th align=\"left\" colspan=\"2\"><FONT color=\"white\">IP Addresses</FONT></th></TR>\n";
		for my $ip_entry (@{$rec->{ip}}) {
			if (ref($ip_entry) eq 'ARRAY' && @$ip_entry > 0) {
				print "<TR bgcolor=\"#f0f0f0\"><td>IP:</td><td>" . encode_entities($ip_entry->[1]) . "</td></TR>\n";
			}
		}
	}

	print "</TABLE>\n";

	# Display approval history (previous decisions at this level)
	if ($status eq 'P') {
    db_query("SELECT t.id, t.user_id, t.decision, t.reason, t.decided_at, u.username, u.name " .
       "FROM dns_change_approvals t " .
			 "LEFT JOIN users u ON t.user_id = u.id " .
			 "WHERE t.request_id = \$1 AND t.level_id = " .
			 "(SELECT id FROM approval_levels WHERE policy_id = \$2 AND level_order = \$3) " .
			 "ORDER BY t.decided_at DESC", \@tokens, $req_id, $policy_id, $current_level);
		
		if (@tokens > 0) {
			print h3('Approvals at current level');
			print "<TABLE bgcolor=\"#ffffcc\" width=\"99%\" cellspacing=1 cellpadding=2 border=0>\n";
			print "<TR bgcolor=\"#ffaa00\"><th>Approver</th><th>Decision</th><th>Reason</th><th>Decided</th></TR>\n";
			for my $t (@tokens) {
				my ($tid, $uid, $dec, $reason, $decided, $uname, $fname) = @$t;
				# Display fullname if available, otherwise username
				my $approver_display = $fname ? encode_entities("$fname ($uname)") : encode_entities($uname || 'unknown');
				my $dec_display = (!defined $dec || $dec eq '') ? 'Pending' : ($dec eq 'A' ? 'Approved' : 'Rejected');
				my $color = (!defined $dec || $dec eq '') ? '#f0f0f0' : ($dec eq 'A' ? '#ccffcc' : '#ffcccc');
				print "<TR bgcolor=\"$color\">\n";
				print "  <td>$approver_display</td>\n";
				print "  <td>$dec_display</td>\n";
				print "  <td>" . encode_entities($reason || '') . "</td>\n";
				print "  <td>" . encode_entities($decided || '') . "</td>\n";
				print "</TR>\n";
			}
			print "</TABLE>\n";
		}
	}

	# Display approval buttons only if request is pending AND current user is an approver
	if ($status eq 'P') {
		if (_is_user_approver_for_request($req_id)) {
			print h3('Approval Action');
			print "<p><b>As an approver, you can make a decision below:</b></p>\n";
			print "<FORM method=\"POST\" action=\"$selfurl\">\n";
			print "<input type=\"hidden\" name=\"menu\" value=\"approvals\">\n";
			print "<input type=\"hidden\" name=\"sub\" value=\"approve_action\">\n";
			print "<input type=\"hidden\" name=\"req_id\" value=\"$req_id\">\n";
			print "<p><label for=\"decision_reason\"><b>Decision Reason (optional):</b></label><br>\n";
			print "<textarea name=\"decision_reason\" id=\"decision_reason\" rows=\"4\" cols=\"70\" maxlength=\"500\"></textarea></p>\n";
			print "<input type=\"submit\" name=\"action\" value=\"Approve\">\n";
			print "<input type=\"submit\" name=\"action\" value=\"Reject\">\n";
			print "</FORM>\n";
		} else {
			print h3('Approval Workflow');
			print "<p><b>You are not an approver for this request.</b> An approval notification has been sent to the assigned approvers.</p>\n";
		}
	}

	# Display audit log for this request
	print h3('Audit Log');
	my @audit_log;
	db_query("SELECT id, user_id, user_name, event, message, created_at " .
		 "FROM dns_change_audit_log WHERE request_id = \$1 " .
		 "ORDER BY id DESC", \@audit_log, $req_id);
	
	if (@audit_log > 0) {
		print "<TABLE bgcolor=\"#ffe0e0\" width=\"99%\" cellspacing=1 cellpadding=2 border=0>\n";
		print "<TR bgcolor=\"#ff9999\"><th>Event</th><th>User</th><th>Message</th><th>Date/Time</th></TR>\n";
		
		my %event_names = (
			'S' => 'Submitted',
			'E' => 'Email',
			'A' => 'Approved',
			'R' => 'Rejected',
			'P' => 'Applied',
			'X' => 'Error',
			'C' => 'Changed'
		);
		
		for my $audit (@audit_log) {
			my ($id, $uid, $uname, $event, $msg, $created) = @$audit;
			my $event_name = $event_names{$event} || "Unknown ($event)";
			my $event_color = ($event eq 'A' ? '#ccffcc' : 
						$event eq 'R' ? '#ffcccc' : 
						$event eq 'P' ? '#ccff99' : 
						$event eq 'X' ? '#ffcccc' : 
						'#f0f0f0');
			print "<TR bgcolor=\"$event_color\">\n";
			print "  <td>" . encode_entities($event_name) . "</td>\n";
			print "  <td>" . encode_entities($uname || 'system') . "</td>\n";
			print "  <td>" . encode_entities($msg || '') . "</td>\n";
			print "  <td>" . encode_entities($created || '') . "</td>\n";
			print "</TR>\n";
		}
		print "</TABLE>\n";
	} else {
		print "<p><i>No audit entries yet.</i></p>\n";
	}

	print "<p><a href=\"$selfurl?menu=approvals&sub=pending\">Back to Pending Approvals</a></p>\n";
}

# _process_approval_action(req_id, action, reason, selfurl)
# Process approval decision by recording it directly (web-based, no tokens required)
sub _process_approval_action {
	my ($req_id, $action, $reason, $selfurl) = @_;
	my (@req, $user_id);

	return unless (defined $req_id && $req_id > 0);
	
	# Validate action parameter
	unless ($action =~ /^(approve|reject)$/) {
		print h2('Invalid Action');
		print p("Invalid approval action. Please use Approve or Reject.");
		return;
	}

	# Get current user ID
	$user_id = $main::state{uid};
	return unless ($user_id > 0);
	
	# Check if current user is an approver for this request
	unless (_is_user_approver_for_request($req_id)) {
		print h2('Access Denied');
		print p("You are not an authorized approver for this request.");
		print p, a({-href=>"$selfurl?menu=approvals&sub=show_request&req_id=$req_id"}, 'Back to request');
		return;
	}

	# Convert action to decision code: 'approve' -> 'A', 'reject' -> 'R'
	my $decision_code = ($action eq 'approve' ? 'A' : 'R');
	
	# Log the action in audit trail
	write2log("Approval decision by user_id=$user_id for request $req_id: $action");

	# Record the approval decision
	my ($status, $msg) = record_approval_decision_web($req_id, $user_id, $decision_code, $reason);
	
	# Display result
	print h2('Approval Decision Recorded');
	if ($status eq 'ok' || $status eq 'pending' || $status eq 'rejected' || $status eq 'approved') {
		print p("Your decision: <b>" . ($decision_code eq 'A' ? 'APPROVED' : 'REJECTED') . "</b>");
		if (defined $reason && $reason ne '') {
			print p("Reason: " . encode_entities($reason));
		}
		print p("Status: " . encode_entities($msg));
		write2log("User $user_id decision recorded for request $req_id - $msg");
	} else {
		print p({-style=>'color:#cc0000;'}, "Error: " . encode_entities($msg));
		write2log("ERROR: Failed to record decision for request $req_id - $msg");
	}

	print p, a({-href=>"$selfurl?menu=approvals&sub=show_request&req_id=$req_id"}, 'Back to request');
}

1;
