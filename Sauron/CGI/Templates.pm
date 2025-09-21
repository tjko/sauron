# Sauron::CGI::Templates.pm
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id:$
#
package Sauron::CGI::Templates;
require Exporter;
use CGI qw/:standard *table -utf8/;
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



my %mx_template_form=(
 data=>[
  {ftype=>0, name=>'MX template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0,
   whitesp=>'P'},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1,
   whitesp=>'P'},
  {ftype=>2, tag=>'mx_l', name=>'Mail exchanges (MX)', whitesp=>['','','P'],
   type=>['priority','mx','text'], fields=>3, len=>[5,45,30], maxlen=>[5,400,60],
   empty=>[0,0,1],elabels=>['Priority','MX','comment']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

my %wks_template_form=(
 data=>[
  {ftype=>0, name=>'WKS template'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'text',len=>40, empty=>0,
   whitesp=>'P'},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'alevel', name=>'Authorization level', type=>'priority', 
   len=>3, empty=>0},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1,
   whitesp=>'P'},
  {ftype=>2, tag=>'wks_l', name=>'WKS', 
   type=>['text','text','text'], fields=>3, len=>[10,30,10], empty=>[0,1,1], 
   elabels=>['Protocol','Services','comment'], whitesp=>['','P','P']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

my %printer_class_form=(
 data=>[
  {ftype=>0, name=>'PRINTER class'},
  {ftype=>1, tag=>'name', name=>'Name', type=>'printer_class',len=>20,
   empty=>0},
  {ftype=>4, tag=>'id', name=>'ID'},
  {ftype=>1, tag=>'comment', name=>'Comment', type=>'text',len=>60, empty=>1,
   whitesp=>'P'},
  {ftype=>2, tag=>'printer_l', name=>'PRINTER', whitesp=>['P','P'],
   type=>['text','text'], fields=>2, len=>[60,10], empty=>[0,1],
   elabels=>['Printer','comment']},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);

my %hinfo_template_form=(
 data=>[
  {ftype=>0, name=>'HINFO template'},
  {ftype=>1, tag=>'hinfo', name=>'HINFO', type=>'hinfo',len=>20, empty=>0},
  {ftype=>4, tag=>'id', name=>'ID', iff=>['id','\d+']},
  {ftype=>3, tag=>'type', name=>'Type', type=>'enum',
   enum=>{0=>'Hardware',1=>'Software'}},
  {ftype=>1, tag=>'pri', name=>'Priority', type=>'priority',len=>4, empty=>0},
  {ftype=>0, name=>'Record info', no_edit=>1},
  {ftype=>4, name=>'Record created', tag=>'cdate_str', no_edit=>1},
  {ftype=>4, name=>'Last modified', tag=>'mdate_str', no_edit=>1}
 ]
);



sub restricted_add_mx_template($) {
  my($rec)=@_;

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to create");
    return -101;
  }
  return add_mx_template($rec);
}

sub restricted_update_mx_template($) {
  my($rec)=@_;

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to update");
    return -101;
  }
  return update_mx_template($rec);
}

sub restricted_get_mx_template($$) {
  my($id,$rec)=@_;

  my($r);
  $r=get_mx_template($id,$rec);
  return $r if ($r < 0);

  if (check_perms('tmplmask',$rec->{name},1)) {
    alert1("Invalid template name: not authorized to modify");
    return -101;
  }
  return $r;
}


sub show_mx_template_list($)
{
  my($state) = @_;

  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};
  my $selfurl = $state->{selfurl};
  my(@q);

  db_query("SELECT name,comment,alevel,id FROM mx_templates " .
	   "WHERE zone=$zoneid ORDER BY name;",\@q);
  print h3("MX templates for zone: $zone");
  for my $i (0..$#q) {
    $q[$i][0]=
      "<a href=\"$selfurl?menu=templates&mx_id=$q[$i][3]\">$q[$i][0]</a>";
  }
  display_list(['Name','Comment','Lvl'],\@q,0);
  print "<br>";

  return 0;
}


sub show_mxt_record($$)
{
  my($state, $mx_id) = @_;

  my $selfurl = $state->{selfurl};
  my(%mxhash);

  if (get_mx_template($mx_id,\%mxhash)) {
    print h2("Cannot get MX template (id=$mx_id)!");
    return 1;
  }
  display_form(\%mxhash,\%mx_template_form);
  print p,start_form(-method=>'GET',-action=>$selfurl),
    hidden('menu','templates');
  print submit(-name=>'sub',-value=>'Edit'), "  ",
    submit(-name=>'sub',-value=>'Delete')
    unless (check_perms('tmplmask',$mxhash{name},1));
  print hidden('mx_id',$mx_id),end_form;

  return 0;
}

sub show_wkst_record($$)
{
  my($state, $wks_id) = @_;

  my $selfurl = $state->{selfurl};
  my(%wkshash);

  if (get_wks_template($wks_id,\%wkshash)) {
    print h2("Cannot get WKS template (id=$wks_id)!");
    return 1;
  }
  display_form(\%wkshash,\%wks_template_form);
  print p,start_form(-method=>'GET',-action=>$selfurl),
    hidden('menu','templates');
  print submit(-name=>'sub',-value=>'Edit'), "  ",
    submit(-name=>'sub',-value=>'Delete')
    unless (check_perms('superuser','',1));
  print hidden('wks_id',$wks_id),end_form;

  return 0;
}

sub show_pc_record($$)
{
  my($state, $pc_id) = @_;

  my $selfurl = $state->{selfurl};
  my(%pchash);

  if (get_printer_class($pc_id,\%pchash)) {
    print h2("Cannot get PRINTER class (id=$pc_id)!");
    return 1;
  }
  display_form(\%pchash,\%printer_class_form);
  print p,start_form(-method=>'GET',-action=>$selfurl),
    hidden('menu','templates');
  print submit(-name=>'sub',-value=>'Edit'), "  ",
    submit(-name=>'sub',-value=>'Delete')
    unless (check_perms('superuser','',1));
  print hidden('pc_id',$pc_id),end_form;

  return 0;
}

sub show_hinfo_record($$)
{
  my($state, $hinfo_id) = @_;

  my $selfurl = $state->{selfurl};
  my(%hinfohash);

  if (get_hinfo_template($hinfo_id,\%hinfohash)) {
    print h2("Cannot get HINFO template (id=$hinfo_id)!");
    return;
  }
  display_form(\%hinfohash,\%hinfo_template_form);
  print p,start_form(-method=>'GET',-action=>$selfurl),
    hidden('menu','templates');
  print submit(-name=>'sub',-value=>'Edit'), "  ",
    submit(-name=>'sub',-value=>'Delete')
    unless (check_perms('superuser','',1));
  print hidden('hinfo_id',$hinfo_id),end_form;

  return 0;
}


# TEMPLATES menu
#
sub menu_handler {
  my($state,$perms) = @_;

  my(@q,$i,$id,$res,$new_id);
  my(%data,%lsth,@lst,%mxhash,%wkshash,%pchash,%hinfohash,%h);

  my $serverid = $state->{serverid};
  my $server = $state->{server};
  my $zoneid = $state->{zoneid};
  my $zone = $state->{zone};
  my $selfurl = $state->{selfurl};

  unless ($serverid > 0) {
    print h2("Server not selected!");
    return;
  }
  unless ($zoneid > 0) {
    print h2("Zone not selected!");
    return;
  }
  return if (check_perms('server','R'));

# Zone names are used when checking lengths of domain names,
# unless they are FQDNs. TVu 2020-06-01
  $mx_template_form{'zonename'} = $state->{zone};

  my $sub=param('sub');
  my $mx_id=param('mx_id');
  my $wks_id=param('wks_id');
  my $pc_id=param('pc_id');
  my $hinfo_id=param('hinfo_id');

  if ($sub eq 'mx') {
    show_mx_template_list($state);
    return;
  }
  elsif ($sub eq 'wks') {
    db_query("SELECT name,comment,alevel,id FROM wks_templates " .
	     "WHERE server=$serverid ORDER BY name;",\@q);
    print h3("WKS templates for server: $server");

    for $i (0..$#q) {
      $q[$i][0]=
	"<a href=\"$selfurl?menu=templates&wks_id=$q[$i][3]\">$q[$i][0]</a>";
    }
    display_list(['Name','Comment','Lvl'],\@q,0);
    print "<br>";
    return;
  }
  elsif ($sub eq 'pc') {
    db_query("SELECT id,name,comment FROM printer_classes " .
	     "ORDER BY name;",\@q);
    print h3("PRINTER Classes (global)");

    for $i (0..$#q) {
      $q[$i][1]=
	"<a href=\"$selfurl?menu=templates&pc_id=$q[$i][0]\">$q[$i][1]</a>";
    }
    display_list(['Name','Comment'],\@q,1);
    print "<br>";
    return;
  }
  elsif ($sub eq 'hinfo') {
    db_query("SELECT id,type,hinfo,pri FROM hinfo_templates " .
	     "ORDER BY type,pri,hinfo;",\@q);

    print h3("HINFO templates (global)");

    for $i (0..$#q) {
	$q[$i][1]=($q[$i][1]==0 ? "Hardware" : "Software");
	$q[$i][2]="<a href=\"$selfurl?menu=templates&hinfo_id=$q[$i][0]\">" .
	          "$q[$i][2]</a>";
    }
    display_list(['Type','HINFO','Priority'],\@q,1);
    print "<br>";
    return;
  }
  elsif ($sub eq 'Edit') {
    if ($mx_id > 0) {
      $res=edit_magic('mx','MX template','templates',\%mx_template_form,
		      \&restricted_get_mx_template,
		      \&restricted_update_mx_template,$mx_id);
      if ($res > 0) {
	show_mxt_record($state, $mx_id);
	return;
      }
    } elsif ($wks_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('wks','WKS template','templates',\%wks_template_form,
		      \&get_wks_template,\&update_wks_template,$wks_id);
      if ($res > 0) {
	show_wkst_record($state, $wks_id);
	return;
      }
    } elsif ($pc_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('pc','PRINTER class','templates',\%printer_class_form,
		      \&get_printer_class,\&update_printer_class,$pc_id);
      if ($res > 0) {
	show_pc_record($state, $pc_id);
	return;
      }
    } elsif ($hinfo_id > 0) {
      return if (check_perms('superuser',''));
      $res=edit_magic('hinfo','HINFO template','templates',
		      \%hinfo_template_form,
		      \&get_hinfo_template,\&update_hinfo_template,$hinfo_id);
      if ($res > 0) {
	show_hinfo_record($state, $hinfo_id);
	return;
      }
    } else { print p,"Unknown template type!"; }
    return;
  }
  elsif ($sub eq 'Delete') {
    if ($mx_id > 0) {
      if (get_mx_template($mx_id,\%h)) {
	print h2("Cannot get mx template (id=$mx_id)");
	return;
      }
      return if (check_perms('tmplmask',$h{name}));
      if (param('mx_cancel')) {
	print h2('MX template not removed');
	show_mxt_record($state, $mx_id);
	return;
      }
      elsif (param('mx_confirm')) {
	$new_id=param('mx_new');
	if ($new_id eq $mx_id) {
	  print h2("Cannot change host records to point template " .
		   "being deleted!");
	  show_mxt_record($state, $mx_id);
	  return;
	}
	$new_id=-1 unless ($new_id > 0);
	if (db_exec("UPDATE hosts SET mx=$new_id WHERE mx=$mx_id;") < 0) {
	  print h2('Cannot update records pointing to this template!');
	  return;
	}
	if (delete_mx_template($mx_id) < 0) {
	  print "<FONT color=\"red\">",h1("MX template delete failed!"),
	        "</FONT>";
	  return;
	}
	print h2("MX template successfully deleted.");
	return;
      }

      undef @q;
      db_query("SELECT COUNT(id) FROM hosts WHERE mx=$mx_id;",\@q);
      print p,"$q[0][0] host records use this template.",
	      start_form(-method=>'GET',-action=>$selfurl);
      if ($q[0][0] > 0) {
	get_mx_template_list($zoneid,\%lsth,\@lst,$perms->{alevel});
	print p,"Change those host records to point to: ",
	        popup_menu(-name=>'mx_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
      }
      print hidden('menu','templates'),hidden('sub','Delete'),
	      hidden('mx_id',$mx_id),p,
	      submit(-name=>'mx_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'mx_cancel',-value=>'Cancel'),end_form;
      display_form(\%h,\%mx_template_form);

    } elsif ($wks_id > 0) {
      return if (check_perms('superuser',''));
      if (get_wks_template($wks_id,\%h)) {
	print h2("Cannot get wks template (id=$wks_id)");
	return;
      }
      if (param('wks_cancel')) {
	print h2('WKS template not removed');
	show_wkst_record($state, $wks_id);
	return;
      }
      elsif (param('wks_confirm')) {
	$new_id=param('wks_new');
	if ($new_id eq $wks_id) {
	  print h2("Cannot change host records to point template " .
		   "being deleted!");
	  show_wkst_record($state, $wks_id);
	  return;
	}
	$new_id=-1 unless ($new_id > 0);
	if (db_exec("UPDATE hosts SET wks=$new_id WHERE wks=$wks_id;") < 0) {
	  print h2('Cannot update records pointing to this template!');
	  return;
	}
	if (delete_wks_template($wks_id) < 0) {
	  print "<FONT color=\"red\">",h1("WKS template delete failed!"),
	        "</FONT>";
	  return;
	}
	print h2("WKS template successfully deleted.");
	return;
      }

      undef @q;
      db_query("SELECT COUNT(id) FROM hosts WHERE wks=$wks_id;",\@q);
      print p,"$q[0][0] host records use this template.",
	      start_form(-method=>'GET',-action=>$selfurl);
      if ($q[0][0] > 0) {
	get_wks_template_list($serverid,\%lsth,\@lst,$perms->{alevel});
	print p,"Change those host records to point to: ",
	        popup_menu(-name=>'wks_new',-values=>\@lst,
			   -default=>-1,-labels=>\%lsth);
      }
      print hidden('menu','templates'),hidden('sub','Delete'),
	      hidden('wks_id',$wks_id),p,
	      submit(-name=>'wks_confirm',-value=>'Delete'),"  ",
	      submit(-name=>'wks_cancel',-value=>'Cancel'),end_form;
      display_form(\%h,\%wks_template_form);

    }
    elsif ($pc_id > 0) {
      return if (check_perms('superuser',''));
      $res=delete_magic('pc','PRINTER class','templates',\%printer_class_form,
			\&get_printer_class,\&delete_printer_class,$pc_id);
      if ($res == 2) {
	show_pc_record($state, $pc_id);
	return;
      }
    }
    elsif ($hinfo_id > 0) {
      return if (check_perms('superuser',''));
      $res=delete_magic('hinfo','HINFO template','templates',
			\%hinfo_template_form,\&get_hinfo_template,
			\&delete_hinfo_template,$hinfo_id);
      if ($res == 2) {
	show_hinfo_record($state, $hinfo_id);
	return;
      }
    }
    else { print p,"Unknown template type!"; }
    return;
  }
  elsif ($sub eq 'addmx') {
    $data{zone}=$zoneid; $data{alevel}=0; $data{mx_l}=[];
    $res=add_magic('addmx','MX template','templates',\%mx_template_form,
		   \&restricted_add_mx_template,\%data);
    if ($res > 0) {
      show_mxt_record($state, $res);
    }
    return;
  }
  elsif ($sub eq 'addwks') {
    return if (check_perms('superuser',''));
    $data{server}=$serverid; $data{alevel}=0; $data{wks_l}=[];
    $res=add_magic('addwks','WKS template','templates',\%wks_template_form,
		   \&add_wks_template,\%data);
    if ($res > 0) {
      show_wkst_record($state, $res);
    }
    return;
  }
  elsif ($sub eq 'addpc') {
    return if (check_perms('superuser',''));
    $data{printer_l}=[];
    $res=add_magic('addwpc','PRINTER class','templates',
		   \%printer_class_form,\&add_printer_class,\%data);
    if ($res > 0) {
      show_pc_record($state, $res);
    }
    return;
  }
  elsif ($sub eq 'addhinfo') {
    return if (check_perms('superuser',''));
    $data{type}=0;
    $data{pri}=100;
    $res=add_magic('addhinfo','HINFO template','templates',
		   \%hinfo_template_form,\&add_hinfo_template,\%data);
    if ($res > 0) {
      show_hinfo_record($state, $res);
    }
    return;
  }
  elsif ($mx_id > 0) {
    show_mxt_record($state, $mx_id);
    return;
  }
  elsif ($wks_id > 0) {
    show_wkst_record($state, $wks_id);
    return;
  }
  elsif ($pc_id > 0) {
    show_pc_record($state, $pc_id);
    return;
  }
  elsif ($hinfo_id > 0) {
    show_hinfo_record($state, $hinfo_id);
    return;
  }

  # display MX template list by default
  show_mx_template_list($state);
}


1;
# eof
