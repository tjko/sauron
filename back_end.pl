#!/usr/bin/perl
#
# back_end.pl  -- Sauron back-end routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000.
# $Id$
#
use strict;

sub new_serial($) {
  my ($serial) = @_;
  my ($sec,$min,$hour,$day,$mon,$year,$s);

  if (! $serial) {
    warn("no serial number passed to new_serial() !");
    return "0";
  }

  ($sec,$min,$hour,$day,$mon,$year) = localtime(time);
  
  $s=sprintf("%04d%02d%02d%02d",1900+$year,1+$mon,$day,$hour);
  $s=$serial + 1 if ($s <= $serial);

  die("new_serial($serial) failed! return value='$s'")
    if ($s <= $serial);

  return $s;
}



#####################################################################

sub get_record($$$$$) {
  my ($table,$fields,$key,$rec,$keyname) = @_;
  my (@list,$res,$i,$val);

  $keyname='id' unless ($keyname);
  undef %{$rec};
  @list = split(",",$fields);
  $fields =~ s/\@//g;
  $res=db_exec("SELECT $fields FROM $table WHERE $keyname='$key';");
  return -1 if ($res < 1);

  $$rec{$keyname}=$key;
  for($i=0; $i < @list; $i++) {
    $val=db_getvalue(0,$i);
    if ($list[$i] =~ /^\@/ ) {
      $$rec{substr($list[$i],1)}=db_decode_list_str($val);
    } else {
      $$rec{$list[$i]}=$val;
    }
  }

  return 0;
}

sub get_array_field($$$$$$$) {
  my($table,$count,$fields,$desc,$rule,$rec,$keyname) = @_;
  my(@list,$l,$i);

  db_query("SELECT $fields FROM $table WHERE $rule;",\@list);
  $l=[];
  push @{$l}, [split(",",$desc)];
  for $i (0..$#list) {
    $list[$i][$count]=0;
    push @{$l}, $list[$i];
  }

  $$rec{$keyname}=$l;
}

sub get_field($$$$$) {
  my($table,$field,$rule,$tag,$rec)=@_;
  my(@list);
  
  db_query("SELECT $field FROM $table WHERE $rule;",\@list);
  if ($#list >= 0) {
    $rec->{$tag}=$list[0][0];
  }
}

sub update_array_field($$$$$$) {
  my($table,$count,$fields,$keyname,$rec,$vals) = @_;
  my($list,$i,$j,$m,$str,$id,$flag,@f);
  
  return -128 unless ($table);
  return -1 unless (ref($rec) eq 'HASH');
  return -2 unless ($$rec{'id'} > 0);
  $list=$$rec{$keyname};
  return 0 unless ($list);
  @f=split(",",$fields);

  for $i (1..$#{$list}) {
    $m=$$list[$i][$count];
    $id=$$list[$i][0];
    if ($m == -1) { # delete record
      $str="DELETE FROM $table WHERE id=$id;";
      print "<P>delete record $id $str";
      return -5 if (db_exec($str) < 0);
    } 
    elsif ($m == 1) { # update record
      $flag=0;
      $str="UPDATE $table SET ";
      for $j(1..($count-1)) {
	$str.=", " if ($flag);
	$str.="$f[$j-1]=". db_encode_str($$list[$i][$j]);
	$flag=1 if (!$flag);
      }
      $str.=" WHERE id=$id;";
      print "<P>update record $id $str";
      return -6 if (db_exec($str) < 0);
    } 
    elsif ($m == 2) { # add record
      $flag=0;
      $str="INSERT INTO $table ($fields) VALUES(";
      for $j(1..($count-1)) {
	$str.=", " if ($flag);
	$str.=db_encode_str($$list[$i][$j]);
	$flag=1 if (!$flag);
      }
      $str.=",$vals);";
      print "<P>add record $id $str";
      return -7 if (db_exec($str) < 0);
    }
  }

  return 0;
}
		       

sub update_record($$) {
  my ($table,$rec) = @_;
  my ($key,$sqlstr,$id,$flag,$r);
  
  return -128 unless ($table);
  return -129 unless (ref($rec) eq 'HASH');
  return -130 unless ($$rec{'id'} > 0);

  $id=$$rec{'id'};
  $sqlstr="UPDATE $table SET ";

  foreach $key (keys %{$rec}) {
    next if ($key eq 'id');
    next if (ref($$rec{$key}) eq 'ARRAY');

    $sqlstr.="," if ($flag);
    $sqlstr.="$key=" . db_encode_str($$rec{$key});
   
    $flag=1 if (! $flag);
  }

  $sqlstr.=" WHERE id=$id;";
  #print "<p>sql=$sqlstr\n";

  return db_exec($sqlstr);
}


sub add_record($$) {
  my($table,$rec) = @_;
  my($sqlstr,@l,$key,$flag,$res,$oid,@q);

  return -130 unless ($table);
  return -131 unless ($rec);

  delete $$rec{'id'}; # paranoid....
  @l = keys %{$rec};
  $sqlstr="INSERT INTO $table (" . join(',',@l) . ") VALUES(";
  #@l = map { $$rec{$_} }  @l;
  foreach $key (@l) {
    $sqlstr .= ',' if ($flag);
    $sqlstr .= db_encode_str($$rec{$key});
    $flag=1 unless ($flag);
  }
  $sqlstr.=");";

  #print "sql '$sqlstr'\n";
  $res=db_exec($sqlstr);
  return -1 if ($res < 0);
  $oid=db_lastoid();
  db_query("SELECT id FROM $table WHERE OID=$oid;",\@q);
  return -2 if (@q < 1);
  return $q[0][0];
}

############################################################################
# server table functions

sub get_server_id($) {
  my ($server) = @_;

  return -1 unless ($server);
  return -1 
    unless (db_exec("SELECT id FROM servers WHERE name='$server';")>0);
  return db_getvalue(0,0);
}

sub get_server_list() {
  my ($res,$list,$i,$id,$name,$rec,$comment);

  $list=[];
  $res=db_exec("SELECT name,id,comment FROM servers ORDER BY name;");

  for($i=0; $i < $res; $i++) {
    $name=db_getvalue($i,0);
    $id=db_getvalue($i,1);
    $comment=db_getvalue($i,2);
    $rec=[$name,$id,$comment];
    push @{$list}, $rec;
  }
  return $list;
}


	       
sub get_server($$) {
  my ($id,$rec) = @_;
  my ($res);

  $res = get_record("servers",
		    "name,directory,named_ca," .
		    "pzone_path,szone_path,hostname,hostmaster,comment",
		    $id,
		    $rec,"id");

  return -1 if ($res < 0);
  
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=1 AND ref=$id ORDER BY ip",$rec,'allow_transfer');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=1 AND ref=$id ORDER BY dhcp",$rec,'dhcp');

  return 0;
}



sub update_server($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('servers',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'allow_transfer',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -12; }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp',$rec,
		        "1,$id");
  if ($r < 0) { db_rollback(); return -13; }

  return db_commit();
}

sub add_server($) {
  my($rec) = @_;

  return add_record('servers',$rec);
}

sub delete_server($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # cidr_entries 
  $res=db_exec("DELETE FROM cidr_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM cidr_entries WHERE id IN ( " .
	        "SELECT a.id FROM cidr_entries a, zones z " .
	        "WHERE z.server=$id AND (a.type=3 OR a.type=2) " .
	        " AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -2; }

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -3; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, zones z " .
	        "WHERE z.server=$id AND a.type=2 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -4; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, zones z, hosts h " .
	        "WHERE z.server=$id AND h.zone=z.id AND a.type=3 " .
	        " AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -5; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, nets n " .
	        "WHERE n.server=$id AND a.type=4 AND a.ref=n.id);");
  if ($res < 0) { db_rollback(); return -6; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, groups g " .
	        "WHERE g.server=$id AND a.type=5 AND a.ref=g.id);");
  if ($res < 0) { db_rollback(); return -7; }

  # host_info
  # FIXME

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, zones z " .
	       "WHERE z.server=$id AND a.type=1 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -8; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -9; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, zones z, mx_templates m " .
	  "WHERE z.server=$id AND m.zone=z.id AND a.type=3 AND a.ref=m.id);");
  if ($res < 0) { db_rollback(); return -10; }
  
  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
	       "SELECT a.id FROM wks_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=1 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -11; }
  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
	       "SELECT a.id FROM wks_entries a, wks_templates w " .
	       "WHERE w.server=$id AND a.type=2 AND a.ref=w.id);");
  if ($res < 0) { db_rollback(); return -12; }


  # ns_entries
  $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " .
	       "SELECT a.id FROM ns_entries a, zones z " .
	       "WHERE z.server=$id AND a.type=1 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -13; }
  $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " .
	       "SELECT a.id FROM ns_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -14; }
  

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
	       "SELECT a.id FROM printer_entries a, groups g " .
	       "WHERE g.server=$id AND a.type=1 AND a.ref=g.id);");
  if ($res < 0) { db_rollback(); return -15; }
  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
	       "SELECT a.id FROM printer_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -16; }


  # txt_entries
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
	       "SELECT a.id FROM txt_entries a, zones z " .
	       "WHERE z.server=$id AND a.type=1 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -17; }
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
	       "SELECT a.id FROM txt_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -18; }


  # rr_a
  $res=db_exec("DELETE FROM rr_a WHERE id IN ( " .
	       "SELECT a.id FROM rr_a a, zones z, hosts h " .
	       "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { db_rollback(); return -18; }

  # wks_templates
  $res=db_exec("DELETE FROM wks_templates WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -19; }
  
  # mx_templates
  $res=db_exec("DELETE FROM mx_templates WHERE id IN ( " .
	       "SELECT a.id FROM mx_templates a, zones z " .
	       "WHERE z.server=$id AND a.zone=z.id);");
  if ($res < 0) { db_rollback(); return -20; }

  # groups
  $res=db_exec("DELETE FROM groups WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -21; }

  # nets
  $res=db_exec("DELETE FROM nets WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -22; }

  # hosts
  $res=db_exec("DELETE FROM hosts WHERE id IN ( " .
	       "SELECT a.id FROM hosts a, zones z " .
	       "WHERE z.server=$id AND a.zone=z.id);");
  if ($res < 0) { db_rollback(); return -23; }

  # zones
  $res=db_exec("DELETE FROM zones WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -24; }

  $res=db_exec("DELETE FROM servers WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -25; }

  return db_commit();
  #return db_rollback();
}

############################################################################
# zone table functions

sub get_zone_id($$) {
  my ($zone,$serverid) = @_;

  return -1 unless ($zone && $serverid);
  return -1 
    unless (db_exec("SELECT id FROM zones " .
		    "WHERE server=$serverid AND name='$zone';")>0);
  return db_getvalue(0,0);
}

sub get_zone_list($$$) {
  my ($serverid,$type,$reverse) = @_;
  my ($res,$list,$i,$id,$name,$rec);

  if ($type) {
    $type=" AND type='$type' ";
  } else {
    $type='';
  }

  if ($reverse) {
    $reverse=" AND reverse='$reverse' ";
  } else {
    $reverse='';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  $res=db_exec("SELECT name,id,type,reverse FROM zones " .
	       "WHERE server=$serverid $type $reverse " .
	       "ORDER BY type,reverse,reversenet,name;");

  for($i=0; $i < $res; $i++) {
    $name=db_getvalue($i,0);
    $id=db_getvalue($i,1);
    $rec=[$name,$id,db_getvalue($i,2),db_getvalue($i,3)];
    push @{$list}, $rec;
  }
  return $list;
}

sub get_zone($$) {
  my ($id,$rec) = @_;
  my ($res);
 
  $res = get_record("zones",
	       "server,active,dummy,type,reverse,class,name," .
	       "hostmaster,serial,refresh,retry,expire,minimum,ttl," .
	       "chknames,reversenet,comment", 
#	       "\@ns,\@mx,\@txt,\@dhcp,comment,\@reverses,reversenet," .
#	       "\@masters",
	       $id,$rec,"id");

  return -1 if ($res < 0);

  get_array_field("ns_entries",3,"id,ns,comment","NS,Comments",
		  "type=1 AND ref=$id ORDER BY ns",$rec,'ns');
  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comments",
		  "type=1 AND ref=$id ORDER BY pri,mx",$rec,'mx');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=1 AND ref=$id ORDER BY id",$rec,'txt');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=2 AND ref=$id ORDER BY dhcp",$rec,'dhcp');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=2 AND ref=$id ORDER BY ip",$rec,'allow_update');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=3 AND ref=$id ORDER BY ip",$rec,'masters');

  return 0;
}

sub update_zone($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('zones',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("ns_entries",3,"ns,comment,type,ref",
			'ns',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -12; }
  $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			'mx',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -13; }
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'txt',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -14; }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -15; }
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'allow_update',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -16; }
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'masters',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -17; }

  return db_commit();
}


############################################################################
# hosts table functions

sub get_host($$) {
  my ($id,$rec) = @_;
  my ($res,$t,$wrec,$mrec);
 
  $res = get_record("hosts",
	       "zone,type,domain,ttl,class,grp,alias,cname,cname_txt," .
	       "hinfo_hw,hinfo_sw,wks,mx,rp_mbox,rp_txt,router," .
	       "prn,ether,info,comment",$id,$rec,"id");

  return -1 if ($res < 0);

  get_array_field("rr_a",5,"id,ip,reverse,forward,comment",
		  "IP,reverse,forward,Comments","host=$id ORDER BY ip",
		  $rec,'ip');

  get_array_field("ns_entries",3,"id,ns,comment","NS,Comments",
		  "type=2 AND ref=$id ORDER BY ns",$rec,'ns_l');
  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comments",
		  "type=1 AND ref=$id ORDER BY proto,services",$rec,'wks_l');
  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comments",
		  "type=2 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=2 AND ref=$id ORDER BY id",$rec,'txt_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=3 AND ref=$id ORDER BY dhcp",$rec,'dhcp_l');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=2 AND ref=$id ORDER BY printer",$rec,'printer_l');

  if ($rec->{ether}) {
    $t=substr($rec->{ether},0,6);
    get_field("ether_info","info","ea='$t'","card_info",$rec);
  }

  if ($rec->{wks} > 0) {
    $wrec={};
    print "<p>Error getting WKS template!\n" 
      if (get_wks_template($rec->{wks},$wrec));
    $rec->{wks_rec}=$wrec;
  }

  if ($rec->{mx} > 0) {
    $mrec={};
    print "<p>Error getting MX template!\n"
      if (get_mx_template($rec->{mx},$mrec));
    $rec->{mx_rec}=$mrec;
    #print p,$rec->{mx}," rec=",$mrec->{comment};
  }

  return 0;
}


sub update_host($) {
  my($rec) = @_;
  my($r,$id);

  delete $rec->{card_info};
  delete $rec->{wks_rec};
  delete $rec->{mx_rec};

  db_begin();
  $r=update_record('hosts',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("ns_entries",3,"ns,comment,type,ref",
			'ns_l',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -12; }
  $r=update_array_field("wks_entries",4,"proto,services,comment,type,ref",
			'wks_l',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -13; }
  $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			'mx_l',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -14; }
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'txt_l',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -15; }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -16; }
  $r=update_array_field("printer_entries",3,"printer,comment,type,ref",
			'printer_l',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -17; }

  $r=update_array_field("rr_a",4,"ip,reverse,forward,comment,host",
			'ip',$rec,"$id");
  if ($r < 0) { db_rollback(); return -20; }

  return db_commit();
}


############################################################################
# MX template functions

sub get_mx_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("mx_templates","name",$id,$rec,"id"));

  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comment",
		  "type=3 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');
  
  return 0;
}

sub get_mx_template_list($$$) {
  my($zoneid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='None';
  return if ($zoneid < 1);

  db_query("SELECT id,name FROM mx_templates " .
	   "WHERE zone=$zoneid ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

############################################################################
# WKS template functions

sub get_wks_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("wks_templates","name",$id,$rec,"id"));
  
  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comment",
		  "type=2 AND ref=$id ORDER BY proto,services",$rec,'wks_l');
  return 0;
}

sub get_wks_template_list($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='None';
  return if ($serverid < 1);

  db_query("SELECT id,name FROM wks_templates " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}


############################################################################
# user functions

sub get_user($$) {
  my ($uname,$rec) = @_;
  
  return get_record("users",
	       "username,password,name,superuser,server,zone,comment,id",
	       $uname,$rec,"username");
}

sub update_user($) {
  my($rec) = @_;
  return update_record('users',$rec);
}


############################################################################
# nets functions

sub get_net_list($$) {
  my ($serverid,$subnets) = @_;
  my ($res,$list,$i,$id,$net,$rec);

  if ($subnets) {
    $subnets=($subnets==0?'false':'true');
    $subnets=" AND subnet=$subnets ";
  } else {
    $subnets='';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  $res=db_exec("SELECT net,id,comment FROM nets " .
	       "WHERE server=$serverid $subnets " .
	       "ORDER BY net;");

  for($i=0; $i < $res; $i++) {
    $net=db_getvalue($i,0);
    $id=db_getvalue($i,1);
    $rec=[$net,$id];
    push @{$list}, $rec;
  }
  return $list;
}
