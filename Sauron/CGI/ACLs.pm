# Sauron::CGI::ACLs.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2005.
# $Id$
#
package Sauron::CGI::ACLs;
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


my %key_algorithm_hash = (0=>'Reserved', 1=>'RSA/MD5',2=>'Diffie-Hellman',
			  3=>'DSA',4=>'ECC',157=>'HMAC MD5');


my %acl_form=(
 data=>[
  {ftype=>0, name=>'ACL (Access Control List)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle', len=>25, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1},
  {ftype=>12, tag=>'acl', name=>'ACL Rules', acl_mode=>1 },
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);



sub show_acl_record($$) {
    my($id,$url) = @_;
    my(%acl);
    
    if (get_acl($id,\%acl)) {
	print h2("Cannot get ACL record (id=$id)!");
	return;
    }

    display_form(\%acl,\%acl_form);
    print p,startform(-method=>'GET',-action=>$url),
          hidden('menu','acls'), hidden('acl_id',$id),
          submit(-name=>'sub',-value=>'Edit'),"  ",
          submit(-name=>'sub',-value=>'Delete'), end_form;
}

sub browse_acls($$$) {
    my($serverid,$server,$url) = @_;
    my($i,@q,@list);

    db_query("SELECT id,name,comment,server FROM acls " .
	     "WHERE server=$serverid OR server=-1 ORDER BY server,id;",\@q);
    if (@q < 1) {
	print h2("No ACLs found!");
	return;
    }

    for $i (0..$#q) {
	my $name = "<a href=\"$url$q[$i][0]\">$q[$i][1]</a>";
	if ($q[$i][3] > 0) { push @list, [$name,$q[$i][2]]; }
	else { push @list, [$q[$i][1],'(Built-in)']; }
    }
    print h3("ACLs for server: $server");
    display_list(['Name','Comment'],\@list,0);
    print "<br>";
}

sub browse_keys($$$) {
    my($serverid,$server,$url) = @_;
    my($i,@q,@list);

    db_query("SELECT id,name,algorithm,keysize,mode,comment,cdate,mdate " .
	     "FROM keys WHERE type=1 AND ref=$serverid ORDER BY name;",\@q);
    if (@q < 1) {
	print h2("No Keys found!");
	return;
    }

    for $i (0..$#q) {
        my $date = ($q[$i][7] > 0 ? $q[$i][7] : $q[$i][6]);
	if ($date > 0) {
	  $date="".localtime($date);
	} else { $date=''; }
	#my $name = "<a href=\"$url$q[$i][0]\">$q[$i][1]</a>";
	push @list, [$q[$i][1], 
		     $key_algorithm_hash{$q[$i][2]},
		     $q[$i][3],
		     ($q[$i][4] == 0 ? 'Automatic' : 'Manual (Static)'),
		     $date,
		     $q[$i][5]];
    }
    print h3("Keys for server: $server");
    display_list(['Name','Algorithm','Key size','Mode','Key Generated',
		  'Comment'],
		 \@list,0);
    print "<br>";

}


# ACLs menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my(@q,$i,$res,$new_id,$name);
  my(%data,%group,%lsth,@lst,@list);

  my $serverid = $state->{serverid};
  my $server = $state->{server};
  my $selfurl = $state->{selfurl};

  $acl_form{serverid}=$state->{serverid};
  $acl_form{zoneid}=$state->{zoneid};

  my $sub=param('sub');
  my $id=param('acl_id');

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  return if (check_perms('server','R'));



  if ($sub eq 'addacl') {
      return if (check_perms('superuser',''));

      $data{acl}=[['aml',$serverid]];
      $data{server}=$serverid;
      $res=add_magic('add','ACL','acls',\%acl_form,
		   \&add_acl,\%data);
      if ($res > 0) {
	  #show_hash(\%data);
	  #print "<p>$res $data{name}";
	  show_acl_record($res,$selfurl);
      }
      return;
  }
  elsif ($sub eq 'Edit' && $id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('acl','ACL','acls',\%acl_form,
		      \&get_acl,\&update_acl,$id);
      browse_acls($serverid,$server,"$selfurl?menu=acls&acl_id=")
	  if($res == -1);
      show_acl_record($id,$selfurl) if ($res > 0);
      return;
  }
  elsif ($sub eq 'Delete' && $id > 0) {
      return if (check_perms('superuser',''));
      my %acl;
      if (get_acl($id,\%acl)) {
	  print h2("Cannot get group (id=$id)");
	  return;
      }
     
      if (param('acl_cancel')) {
	  print h2("ACL not removed");
	  show_acl_record($id,$selfurl);
	  return;
      }
      elsif (param('acl_confirm')) {
	  my $new_id = param('acl_new');
	  if ($new_id == $id) {
	      print 
		 h2("Cannot change references to point to ACL being deleted!");
	      show_acl_record($id,$selfurl);
	      return;
	  }
	  $new_id=-1 unless ($new_id > 0);
	  if (delete_acl($id,$new_id) < 0) {
	      alert1("ACL delete failed!");
	      return;
	  }
	  print h2("ACL successfully removed.");
	  return;
      }
      
      my (@q,@lst,%lsth);
      db_query("SELECT COUNT(id) FROM cidr_entries WHERE acl=$id",\@q);
      print p,"$q[0][0] rules use this ACL.",
            startform(-method=>'GET',-action=>$selfurl);
      if ($q[0][0] > 0) {
	  get_acl_list($serverid,\%lsth,\@lst,0);
	  print p,"Change references to this ACL to point to: ",
	        popup_menu(-name=>'acl_new',-values=>\@lst,
			   -default=>-1,labels=>\%lsth);
      }
      print hidden('menu','acls'),hidden('sub','Delete'),
            hidden('acl_id',$id),p,
            submit(-name=>'acl_confirm',-value=>'Delete'),"  ",
            submit(-name=>'acl_cancel',-value=>'Cancel'),end_form;
      display_form(\%acl,\%acl_form);
      return;
  }


  return if (check_perms('level',$main::ALEVEL_ACLS));
  
  if ($sub eq 'keys') {
      browse_keys($serverid,$server,'');
      return;
  }

  if ($id > 0) {
      show_acl_record($id,$selfurl);
  } else {
      browse_acls($serverid,$server,"$selfurl?menu=acls&acl_id=");
  }

}


1;
# eof
