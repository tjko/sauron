# Sauron::CGI::ACLs.pm
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2005.
# $Id:$
#
package Sauron::CGI::ACLs;
require Exporter;
use CGI qw/:standard *table/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::CGI::Utils;

use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );


my %key_algorithm_hash = (0=>'Reserved', 1=>'RSA/MD5',2=>'Diffie-Hellman',
			  3=>'DSA',4=>'ECC',
			  157=>'HMAC-MD5', 158=>'HMAC-SHA1',
			  159=>'HMAC-SHA256', 160=>'HMAC-SHA384',
			  161=>'HMAC-SHA512');


my %acl_form=(
 data=>[
  {ftype=>0, name=>'ACL (Access Control List)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle', len=>25, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60, empty=>1, whitesp=>'P'},
  {ftype=>12, tag=>'acl', name=>'ACL Rules', acl_mode=>1, whitesp=>['','','','','','P'] },
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);


# TLS profile form (DNS Zone Transfer over TLS, XoT, RFC 9103)
my %tls_yn_enum = (D=>'Default', Y=>'Yes', N=>'No');

my %tls_form=(
 data=>[
  {ftype=>0, name=>'TLS Profile (DNS Zone Transfer over TLS, RFC 9103)'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'texthandle', len=>25, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'cert_file', name=>'cert-file', type=>'text', len=>50,
   empty=>1, whitesp=>'P'},
  {ftype=>1, tag=>'key_file', name=>'key-file', type=>'text', len=>50,
   empty=>1, whitesp=>'P'},
  {ftype=>1, tag=>'ca_file', name=>'ca-file (peer verification)', type=>'text',
   len=>50, empty=>1, whitesp=>'P'},
  {ftype=>1, tag=>'dhparam_file', name=>'dhparam-file', type=>'text', len=>50,
   empty=>1, whitesp=>'P'},
  {ftype=>1, tag=>'protocols', name=>'protocols', type=>'text', len=>30,
   empty=>1, whitesp=>'P', extrainfo=>'e.g. TLSv1.2 TLSv1.3'},
  {ftype=>1, tag=>'ciphers', name=>'ciphers', type=>'text', len=>50,
   empty=>1, whitesp=>'P'},
  {ftype=>3, tag=>'prefer_server_ciphers', name=>'prefer-server-ciphers',
   type=>'enum', conv=>'U', enum=>\%tls_yn_enum},
  {ftype=>3, tag=>'session_tickets', name=>'session-tickets',
   type=>'enum', conv=>'U', enum=>\%tls_yn_enum},
  {ftype=>1, tag=>'remote_hostname', name=>'remote-hostname (outgoing auth)',
   type=>'text', len=>40, empty=>1, whitesp=>'P'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text', len=>60,
   empty=>1, whitesp=>'P'},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);



sub show_acl_record($$) {
    my($id,$url) = @_;
    my(%acl);
    
    if (get_acl($id,\%acl)) {
	alert1("Cannot get ACL record (id=$id).");
	return;
    }

    display_form(\%acl,\%acl_form);
    print p,start_form(-method=>'GET',-action=>$url),
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
	warning1("No ACLs found.");
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
	warning1("No Keys found.");
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

sub show_tls_record($$) {
    my($id,$url) = @_;
    my(%tls);

    if (get_tls_profile($id,\%tls)) {
	alert1("Cannot get TLS profile record (id=$id).");
	return;
    }

    display_form(\%tls,\%tls_form);
    print p,start_form(-method=>'GET',-action=>$url),
          hidden('menu','acls'), hidden('tls_id',$id),
          submit(-name=>'sub',-value=>'Edit'),"  ",
          submit(-name=>'sub',-value=>'Delete'), end_form;
}

sub browse_tls($$$) {
    my($serverid,$server,$url) = @_;
    my($i,@q,@list);

    db_query("SELECT id,name,cert_file,protocols,comment FROM tls_profiles " .
	     "WHERE type=1 AND ref=$serverid ORDER BY name;",\@q);
    if (@q < 1) {
	warning1("No TLS profiles found.");
	return;
    }

    for $i (0..$#q) {
	my $name = "<a href=\"$url$q[$i][0]\">$q[$i][1]</a>";
	push @list, [$name,$q[$i][2],$q[$i][3],$q[$i][4]];
    }
    print h3("TLS profiles for server: $server");
    display_list(['Name','cert-file','protocols','Comment'],\@list,0);
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
  my $tls_id=param('tls_id');

  unless ($serverid > 0) {
    alert1("Server not selected.");
    return;
  }
  return if (check_perms('server','R'));


  # --- TLS profiles (DNS Zone Transfer over TLS, XoT, RFC 9103) ---
  if ($sub eq 'addtls') {
      return if (check_perms('superuser',''));

      $data{ref}=$serverid;
      $data{type}=1;
      $res=add_magic('addtls','TLS Profile','acls',\%tls_form,
		     \&add_tls_profile,\%data);
      show_tls_record($res,$selfurl) if ($res > 0);
      return;
  }
  elsif ($sub eq 'Edit' && $tls_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('tls','TLS Profile','acls',\%tls_form,
		      \&get_tls_profile,\&update_tls_profile,$tls_id);
      browse_tls($serverid,$server,"$selfurl?menu=acls&tls_id=")
	  if ($res == -1);
      show_tls_record($tls_id,$selfurl) if ($res > 0);
      return;
  }
  elsif ($sub eq 'Delete' && $tls_id > 0) {
      return if (check_perms('superuser',''));
      my %tls;
      if (get_tls_profile($tls_id,\%tls)) {
	  alert1("Cannot get TLS profile (id=$tls_id).");
	  return;
      }
      if (param('tls_cancel')) {
	  alert1("TLS profile not removed.");
	  show_tls_record($tls_id,$selfurl);
	  return;
      }
      elsif (param('tls_confirm')) {
	  if (delete_tls_profile($tls_id) < 0) {
	      alert1("TLS profile delete failed!");
	      return;
	  }
	  success1("TLS profile successfully removed.");
	  return;
      }
      print p,"Delete TLS profile \"$tls{name}\"?",
	    start_form(-method=>'GET',-action=>$selfurl),
	    hidden('menu','acls'),hidden('sub','Delete'),
	    hidden('tls_id',$tls_id),p,
	    submit(-name=>'tls_confirm',-value=>'Delete'),"  ",
	    submit(-name=>'tls_cancel',-value=>'Cancel'),end_form;
      display_form(\%tls,\%tls_form);
      return;
  }



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
	  alert1("Cannot get group (id=$id).");
	  return;
      }
     
      if (param('acl_cancel')) {
	  alert1("ACL not removed.");
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
	  success1("ACL successfully removed.");
	  return;
      }
      
      my (@q,@lst,%lsth);
      db_query("SELECT COUNT(id) FROM cidr_entries WHERE acl=$id",\@q);
      print p,"$q[0][0] rules use this ACL.",
            start_form(-method=>'GET',-action=>$selfurl);
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

  if ($sub eq 'tls') {
      browse_tls($serverid,$server,"$selfurl?menu=acls&tls_id=");
      return;
  }

  if ($tls_id > 0) {
      show_tls_record($tls_id,$selfurl);
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
