# Sauron::CGI::Groups.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id$
#
package Sauron::CGI::Groups;
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



my %group_type_hash = (1=>'Normal', 2=>'Dynamic Address Pool',
		    3=>'DHCP class', 103=>'Custom DHCP class');

my %vmps_list_hash;
my @vmps_list_lst;

my %group_form=(
 data=>[
  {ftype=>0, name=>'Group'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text', len=>40, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum', enum=>\%group_type_hash},
  {ftype=>3, tag=>'vmps', name=>'VMPS Domain', type=>'enum', conv=>'L',
   enum=>\%vmps_list_hash, elist=>\@vmps_list_lst, restricted=>0},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority',
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1},
  {ftype=>2, tag=>'dhcp', name=>'DHCP entries', 
   type=>['text','text'], fields=>2, maxlen=>[200,20],
   len=>[50,20], empty=>[0,1], elabels=>['DHCP','comment']},
  {ftype=>2, tag=>'printer', name=>'PRINTER entries',
   type=>['text','text'], fields=>2, len=>[40,20], empty=>[0,1],
   elabels=>['PRINTER','comment'], iff=>['type','[1]']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);



sub restricted_add_group($) {
  my($rec)=@_;

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to create");
    return -101;
  }
  return add_group($rec);
}

sub restricted_get_group($$) {
  my($id,$rec)=@_;

  my($r);
  $r=get_group($id,$rec);
  return $r if ($r < 0);

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to modify");
    return -101;
  }
  return $r;
}

sub restricted_update_group($) {
  my($rec)=@_;

  if (check_perms('grpmask',$rec->{name},1)) {
    alert1("Invalid group name: not authorized to update");
    return -101;
  }
  return update_group($rec);
}



# GROUPS menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my(@q,$i,$res,$new_id,$name);
  my(%data,%group,%lsth,@lst,@list);

  my $serverid = $state->{serverid};
  my $server = $state->{server};
  my $selfurl = $state->{selfurl};

  my $sub=param('sub');
  my $id=param('grp_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));

  get_vmps_list($serverid,\%vmps_list_hash,\@vmps_list_lst);

  if ($sub eq 'add') {
    $data{type}=1; $data{alevel}=0; $data{dhcp}=[]; $data{printer}=[];
    $data{server}=$serverid;
    $res=add_magic('add','Group','groups',\%group_form,
		   \&restricted_add_group,\%data);
    if ($res > 0) {
      #show_hash(\%data);
      #print "<p>$res $data{name}";
      $id=$res;
      goto show_group_record;
    }
    return;
  }
  elsif ($sub eq 'Edit') {
    $res=edit_magic('grp','Group','groups',\%group_form,
		    \&restricted_get_group,
		    \&restricted_update_group,$id);
    goto browse_groups if ($res == -1);
    goto show_group_record if ($res > 0);
    return;
  }
  elsif ($sub eq 'Delete') {
    if (get_group($id,\%group)) {
      print h2("Cannot get group (id=$id)");
      return;
    }
    return if (check_perms('grpmask',$group{name}));
    if (param('grp_cancel')) {
      print h2('Group not removed');
      goto show_group_record;
    }
    elsif (param('grp_confirm')) {
      $new_id=param('grp_new');
      if ($new_id eq $id) {
	print h2("Cannot change host records to point the group " .
		 "being deleted!");
	goto show_group_record;
      }
      $new_id=-1 unless ($new_id > 0);
      if (db_exec("UPDATE hosts SET grp=$new_id WHERE grp=$id;") < 0) {
	print h2('Cannot update records pointing to this group!');
	return;
      }
      if (delete_group($id) < 0) {
	print "<FONT color=\"red\">",h1("Group delete failed!"),
	        "</FONT>";
	return;
      }
      print h2("Group successfully deleted.");
      return;
    }

    undef @q;
    db_query("SELECT COUNT(id) FROM hosts WHERE grp=$id;",\@q);
    print p,"$q[0][0] host records use this group.",
	      startform(-method=>'GET',-action=>$selfurl);
    if ($q[0][0] > 0) {
      get_group_list($serverid,\%lsth,\@lst,$perms->{alevel});
      print p,"Change those host records to point to: ",
	        popup_menu(-name=>'grp_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
    }
    print hidden('menu','groups'),hidden('sub','Delete'),
	      hidden('grp_id',$id),p,
	      submit(-name=>'grp_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'grp_cancel',-value=>'Cancel'),end_form;
    display_form(\%group,\%group_form);
    return;
  }

 show_group_record:
  if ($id > 0) {
    if (get_group($id,\%group)) {
      print h2("Cannot get group record (id=$id)!");
      return;
    }
    display_form(\%group,\%group_form);
    print p,startform(-method=>'GET',-action=>$selfurl),
          hidden('menu','groups');
    print submit(-name=>'sub',-value=>'Edit'), "  ",
          submit(-name=>'sub',-value=>'Delete')
	    unless (check_perms('grpmask',$group{name},1));
    print hidden('grp_id',$id),end_form;
    return;
  }

 browse_groups:
  db_query("SELECT id,name,comment,type,alevel FROM groups " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  if (@q < 1) {
    print h2("No groups found!");
    return;
  }

  for $i (0..$#q) {
    $name = "<a href=\"$selfurl?menu=groups&grp_id=$q[$i][0]\">$q[$i][1]</a>";
    push @list, [$name,$group_type_hash{$q[$i][3]},$q[$i][2],$q[$i][4]];
  }
  print h3("Groups for server: $server");
  display_list(['Name','Type','Comment','Lvl'],\@list,0);
  print "<br>";
}


1;
# eof
