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

sub auto_address($$) {
  my($serverid,$net) = @_;
  my(@q,$s,$e,$i,$j,%h);

  return 'Invalid server id'  unless ($serverid > 0);
  return 'Invalid net'  unless (is_cidr($net));

  db_query("SELECT net,range_start,range_end FROM nets " .
	   "WHERE server=$serverid AND net = '$net';",\@q);
  return 'No auto address range defined for this new '
    unless (is_cidr($q[0][1]) && is_cidr($q[0][2]));
  $s=ip2int($q[0][1]);
  $e=ip2int($q[0][2]);
  return 'Invalid auto address range' if ($s >= $e);

  undef @q;
  db_query("SELECT a.ip FROM hosts h, rr_a a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND '$net' >> a.ip ORDER BY a.ip;",\@q);
  for $i (0..$#q) {
    $j=ip2int($q[$i][0]);
    next if ($j < 0 || $j < $s || $j > $e);
    $h{$j}=$q[$i][0];
    #print "<br>$q[$i][0]";
  }
  for $i (0..($e-$s)) {
    #print "<br>$i " . int2ip($s+$i);
    return int2ip($s+$i) unless ($h{($s+$i)});
  }

  return "No free addresses left";
}

sub ip_in_use($$) {
  my($serverid,$ip)=@_;
  my(@q);

  return -1 unless ($serverid > 0);
  return -2 unless (is_cidr($ip));
  db_query("SELECT a.id FROM hosts h, rr_a a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND a.ip = '$ip';",\@q);
  return 1 if ($q[0][0] > 0);
  return 0;
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
      print "<BR>DEBUG: delete record $id $str";
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
      print "<BR>DEBUG: update record $id $str";
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
      print "<BR>DEBUG: add record $id $str";
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
    if ($$rec{$key} eq '0') { $sqlstr.="$key='0'"; }  # HACK value :)
    else { $sqlstr.="$key=" . db_encode_str($$rec{$key}); }

    $flag=1 if (! $flag);
  }

  $sqlstr.=" WHERE id=$id;";
  #print "<p>sql=$sqlstr\n";

  return db_exec($sqlstr);
}


sub add_record_sql($$) {
  my($table,$rec) = @_;
  my($sqlstr,@l,$key,$flag);

  return '' unless ($table);
  return '' unless ($rec);

  foreach $key (keys %{$rec}) {
    next if ($key eq 'id');
    next if (ref($$rec{$key}) eq 'ARRAY');
    push @l, $key;
  }
  $sqlstr="INSERT INTO $table (" . join(',',@l) . ") VALUES(";
  foreach $key (@l) {
    $sqlstr .= ',' if ($flag);
    if ($$rec{$key} eq '0') { $sqlstr.="'0'"; }
    else { $sqlstr .= db_encode_str($$rec{$key}); }
    $flag=1 unless ($flag);
  }
  $sqlstr.=");";

  return $sqlstr;
}

sub add_record($$) {
  my($table,$rec) = @_;
  my($sqlstr,$res,$oid,@q);

  return -130 unless ($table);
  return -131 unless ($rec);

  $sqlstr=add_record_sql($table,$rec);
  return -132 if ($sqlstr eq '');

  #print "sql '$sqlstr'\n";
  $res=db_exec($sqlstr);
  return -1 if ($res < 0);
  $oid=db_lastoid();
  db_query("SELECT id FROM $table WHERE OID=$oid;",\@q);
  return -2 if (@q < 1);
  return $q[0][0];
}

sub copy_records($$$$$$$) {
  my($stable,$ttable,$key,$reffield,$ids,$fields,$selectsql)=@_;
  my(@data,%h,$i,$newref,$tmp);

  # make ID hash
  for $i (0..$#{$ids}) { $h{$$ids[$i][0]}=$$ids[$i][1]; }

  # read records into array & fix key fields using hash

  $tmp="SELECT $reffield,$fields FROM $stable WHERE $key IN ($selectsql);";
  #print "$tmp\n";
  db_query($tmp,\@data);
  print "<br>$stable records to copy: " . @data . "\n";
  return 0 if (@data < 1);

  for $i (0..$#data) {
    $newref=$h{$data[$i][0]};
    return -1 unless ($newref);
    $data[$i][0]=$newref;
  }

  return db_insert($ttable,"$reffield,$fields",\@data);
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

sub delete_zone($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # cidr_entries
  print "<BR>Deleting CIDR entries...\n";
  $res=db_exec("DELETE FROM cidr_entries WHERE (type=2 OR type=3) " .
	       " AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }
  
  # dhcp_entries
  print "<BR>Deleting DHCP entries...\n";
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -2; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, hosts h " .
	        "WHERE h.zone=$id AND a.type=3 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -3; }

  # mx_entries
  print "<BR>Deleting MX entries...\n";
  $res=db_exec("DELETE FROM mx_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -4; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -5; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, mx_templates m " .
	       "WHERE m.zone=$id AND a.type=3 AND a.ref=m.id);");
  if ($res < 0) { db_rollback(); return -6; }
  
  # wks_entries
  print "<BR>Deleting WKS entries...\n";
  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
	       "SELECT a.id FROM wks_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -7; }

  # ns_entries
  print "<BR>Deleting NS entries...\n";
  $res=db_exec("DELETE FROM ns_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -8; }
  $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " .
	       "SELECT a.id FROM ns_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -9; }


  # printer_entries
  print "<BR>Deleting PRINTER entries...\n";
  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
	       "SELECT a.id FROM printer_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -10; }

  # txt_entries
  print "<BR>Deleting TXT entries...\n";
  $res=db_exec("DELETE FROM txt_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -11; }
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
	       "SELECT a.id FROM txt_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -12; }

  # rr_a
  print "<BR>Deleting A entries...\n";
  $res=db_exec("DELETE FROM rr_a WHERE id IN ( " .
	       "SELECT a.id FROM rr_a a, hosts h " .
	       "WHERE h.zone=$id AND a.host=h.id);");
  if ($res < 0) { db_rollback(); return -13; }

  # mx_templates
  print "<BR>Deleting MX templates...\n";
  $res=db_exec("DELETE FROM mx_templates WHERE zone=$id;");
  if ($res < 0) { db_rollback(); return -14; }

  # hosts
  print "<BR>Deleting Hosts...\n";
  $res=db_exec("DELETE FROM hosts WHERE zone=$id;");
  if ($res < 0) { db_rollback(); return -15; }


  print "<BR>Deleting Zone record...\n";
  $res=db_exec("DELETE FROM zones WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -50; }

  return db_commit();
  #return db_rollback();
}

sub add_zone($) {
  my($rec) = @_;

  return add_record('zones',$rec);
}

sub copy_zone($$$$) {
  my($id,$serverid,$newname,$trans)=@_;
  my($newid,%z,$res,@q,@ids,@hids,$i,$j,%h,@t,$fields,%aids);

  return -1 if (get_zone($id,\%z) < 0);
  db_begin() if ($trans);

  print "<BR>Copying zone record...";
  delete $z{id};
  $z{server}=$serverid;
  $z{name}=$newname;
  $newid=add_zone(\%z);
  return -2 if ($newid < 1);
  print "<BR>Copying records pointing to zone record...";

  # cidr_entries
  $res=db_exec("INSERT INTO cidr_entries (type,ref,ip,comment) " .
	       "SELECT type,$newid,ip,comment FROM cidr_entries " .
	       "WHERE (type=2 OR type=3) AND ref=$id;");
  if ($res < 0) { db_rollback(); return -3; }
  
  # dhcp_entries
  $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp,comment) " .
	       "SELECT type,$newid,dhcp,comment FROM dhcp_entries " .
	       "WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -4; }

  # mx_entries
  $res=db_exec("INSERT INTO mx_entries (type,ref,pri,mx,comment) " .
	       "SELECT type,$newid,pri,mx,comment FROM mx_entries " .
	       "WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -5; }

  # ns_entries
  $res=db_exec("INSERT INTO ns_entries (type,ref,ns,comment) " .
	       "SELECT type,$newid,ns,comment FROM ns_entries " .
	       "WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -6; }

  # txt_entries
  $res=db_exec("INSERT INTO txt_entries (type,ref,txt,comment) " .
	       "SELECT type,$newid,txt,comment FROM txt_entries " .
	       "WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -7; }
  

  # mx_templates
  print "<BR>Copying MX templates...";
  undef @q;
  db_query("SELECT id FROM mx_templates WHERE zone=$id;",\@ids);
  for $i (0..$#ids) {
    undef %h;
    if (get_mx_template($ids[$i][0],\%h) < 0) { db_rollback(); return -8; }
    $h{zone}=$newid;
    $j=add_record('mx_templates',\%h);
    if ($j < 0) { db_rollback(); return -9; }
    $ids[$i][1]=$j;
    $res=db_exec("INSERT INTO mx_entries (type,ref,pri,mx,comment) " .
		 "SELECT type,$j,pri,mx,comment FROM mx_entries " .
		 "WHERE type=3 AND ref=$ids[$i][0];");
    if ($res < 0) { db_rollback(); return -10; }
  }

  # hosts
  print "<BR>Copying hosts...";
  $fields='type,domain,ttl,class,grp,alias,cname,cname_txt,hinfo_hw,' .
          'hinfo_sw,wks,mx,rp_mbox,rp_txt,router,prn,ether,info,comment';

  $res=db_exec("INSERT INTO hosts (zone,$fields) " .
	       "SELECT $newid,$fields FROM hosts " .
	       "WHERE zone=$id;");
  if ($res < 0) { db_rollback(); return -11; }

  db_query("SELECT a.id,b.id,a.domain FROM hosts a, hosts b " .
	   "WHERE a.zone=$id AND b.zone=$newid AND a.domain=b.domain;",\@hids);
  print "<br>hids = " . $#hids;

  # rr_a
  print "<BR>Copying A records...";
  $res=copy_records('rr_a','rr_a','id','host',\@hids,
     'ip,reverse,forward,comment',
     "SELECT a.id FROM rr_a a,hosts h WHERE a.host=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -12; }

  # dhcp_entries
  print "<BR>Copying DHCP records...";
  $res=copy_records('dhcp_entries','dhcp_entries','id','ref',\@hids,
     'type,dhcp,comment',
     "SELECT a.id FROM dhcp_entries a,hosts h " .
     "WHERE a.type=3 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -13; }

  # mx_entires
  print "<BR>Copying MX records...";
  $res=copy_records('mx_entries','mx_entries','id','ref',\@hids,
     'type,pri,mx,comment',
     "SELECT a.id FROM mx_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -14; }

  # wks_entries
  print "<BR>Copying WKS records...";
  $res=copy_records('wks_entries','wks_entries','id','ref',\@hids,
     'type,proto,services,comment',
     "SELECT a.id FROM wks_entries a,hosts h " .
     "WHERE a.type=1 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -15; }

  # ns_entries
  print "<BR>Copying NS records...";
  $res=copy_records('ns_entries','ns_entries','id','ref',\@hids,
     'type,ns,comment',
     "SELECT a.id FROM ns_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -16; }

  # printer_entries
  print "<BR>Copying PRINTER records...";
  $res=copy_records('printer_entries','printer_entries','id','ref',\@hids,
     'type,printer,comment',
     "SELECT a.id FROM printer_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -17; }

  # txt_entries
  print "<BR>Copying TXT records...";
  $res=copy_records('txt_entries','txt_entries','id','ref',\@hids,
     'type,txt,comment',
     "SELECT a.id FROM txt_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -18; }

  # update mx_template pointers
  print "<BR>Updating MX template pointers...";
  for $i (0..$#ids) {
    $res=db_exec("UPDATE hosts SET mx=$ids[$i][1] " .
		 "WHERE zone=$newid AND mx=$ids[$i][0];");
    if ($res < 0) { db_rollback(); return -19; }
  }

  # update alias pointers
  print "<BR>Updating ALIAS pointers...";
  undef @q;
  db_query("SELECT alias FROM hosts WHERE zone=$newid AND alias > 0;",\@q);
  print " " .@q." alias records to update...";
  for $i (0..$#q) { $aids{$q[$i][0]}=1; }
  for $i (0..$#hids) {
    next unless ($aids{$hids[$i][0]});
    $res=db_exec("UPDATE hosts SET alias=$hids[$i][1] " .
		 "WHERE zone=$newid AND alias=$hids[$i][0];");
    if ($res < 0) { db_rollback(); return -20; }
  }

  if ($trans) { return -100 if (db_commit() < 0);  }
  return $newid;
}

############################################################################
# hosts table functions

sub get_host($$) {
  my ($id,$rec) = @_;
  my ($res,$t,$wrec,$mrec,%h);

  $res = get_record("hosts",
	       "zone,type,domain,ttl,class,grp,alias,cname,cname_txt," .
	       "hinfo_hw,hinfo_sw,wks,mx,rp_mbox,rp_txt,router," .
	       "prn,ether,info,location,dept,huser,model,serial,misc,comment",
		    $id,$rec,"id");

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

  get_array_field("hosts",3,"id,domain,cname","Domain,cname",
		  "type=4 AND alias=$id ORDER BY domain",$rec,'alias_l');


  if ($rec->{ether}) {
    $t=substr($rec->{ether},0,6);
    get_field("ether_info","info","ea='$t'","card_info",$rec);
  }
  $rec->{card_info}='&nbsp;' if ($rec->{card_info} eq '');

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

  if ($rec->{grp} > 0) {
    $mrec={};
    print "<p>Error getting GROUP!\n"
      if (get_group($rec->{grp},$mrec));
    $rec->{grp_rec}=$mrec;
    #print p,$rec->{mx}," rec=",$mrec->{comment};
  }


  if ($rec->{type} == 4) {
    get_host($rec->{alias},\%h);
    $rec->{alias_d}=$h{domain};
  }

  return 0;
}


sub update_host($) {
  my($rec) = @_;
  my($r,$id);

  delete $rec->{card_info};
  delete $rec->{wks_rec};
  delete $rec->{mx_rec};
  delete $rec->{grp_rec};
  delete $rec->{alias_l};
  delete $rec->{alias_d};

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

sub delete_host($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -3; }

  # ns_entries
  $res=db_exec("DELETE FROM ns_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -4; }

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -5; }

  # txt_entries
  $res=db_exec("DELETE FROM txt_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -6; }

  # rr_a
  $res=db_exec("DELETE FROM rr_a WHERE host=$id;");
  if ($res < 0) { db_rollback(); return -7; }

  # aliases
  $res=db_exec("DELETE FROM hosts WHERE type=4 AND alias=$id;");
  if ($res < 0) { db_rollback(); return -8; }

  $res=db_exec("DELETE FROM hosts WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -50; }

  return db_commit();
  #return db_rollback();
}

sub add_host($) {
  my($rec) = @_;

  return -100 unless ($rec->{zone} > 0);
  return add_record('hosts',$rec);
}


############################################################################
# MX template functions

sub get_mx_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("mx_templates","name,comment",$id,$rec,"id"));

  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comment",
		  "type=3 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');
  
  return 0;
}

sub update_mx_template($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('mx_templates',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			'mx_l',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub add_mx_template($) {
  my($rec) = @_;

  return add_record('mx_templates',$rec);
}


sub delete_mx_template($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM mx_templates WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  return db_commit();
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

  return -100 if (get_record("wks_templates","name,comment",$id,$rec,"id"));

  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comment",
		  "type=2 AND ref=$id ORDER BY proto,services",$rec,'wks_l');
  return 0;
}

sub update_wks_template($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('wks_templates',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("wks_entries",4,"proto,services,comment,type,ref",
			'wks_l',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub add_wks_template($) {
  my($rec) = @_;

  return add_record('wks_templates',$rec);
}


sub delete_wks_template($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM wks_templates WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  return db_commit();
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
# PRINTER class functions

sub get_printer_class($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("printer_classes","name,comment",$id,$rec,"id"));

  get_array_field("printer_entries",3,"id,printer,comment",
		  "Printer,Comment",
		  "type=3 AND ref=$id ORDER BY printer",$rec,'printer_l');
  return 0;
}

sub update_printer_class($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('printer_classes',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("printer_entries",3,"printer,comment,type,ref",
			'printer_l',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub add_printer_class($) {
  my($rec) = @_;

  return add_record('printer_classes',$rec);
}


sub delete_printer_class($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM printer_classes WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  return db_commit();
}

############################################################################
# HINFO template functions

sub get_hinfo_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("hinfo_templates","hinfo,type,pri",
			     $id,$rec,"id"));
  return 0;
}

sub update_hinfo_template($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('hinfo_templates',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  return db_commit();
}

sub add_hinfo_template($) {
  my($rec) = @_;

  return add_record('hinfo_templates',$rec);
}


sub delete_hinfo_template($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM hinfo_templates WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  return db_commit();
}

############################################################################
# group functions

sub get_group($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("groups","name,comment",$id,$rec,"id"));

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=5 AND ref=$id ORDER BY dhcp",$rec,'dhcp');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=1 AND ref=$id ORDER BY printer",$rec,'printer');

  return 0;
}

sub update_group($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('groups',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp',$rec,"5,$id");
  if ($r < 0) { db_rollback(); return -16; }
  $r=update_array_field("printer_entries",3,"printer,comment,type,ref",
			'printer',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -17; }

  return db_commit();
}

sub add_group($) {
  my($rec) = @_;

  return add_record('groups',$rec);
}


sub delete_group($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=5 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }
  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  $res=db_exec("DELETE FROM groups WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -3; }

  return db_commit();
}

sub get_group_list($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='None';
  return if ($serverid < 1);

  db_query("SELECT id,name FROM groups " .
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
  my ($res,$list,$i,$id,$net,$rec,$name);

  if ($subnets) {
    $subnets=($subnets==0?'false':'true');
    $subnets=" AND subnet=$subnets ";
  } else {
    $subnets='';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  $res=db_exec("SELECT net,id,name FROM nets " .
	       "WHERE server=$serverid $subnets " .
	       "ORDER BY net;");

  for($i=0; $i < $res; $i++) {
    $net=db_getvalue($i,0);
    $id=db_getvalue($i,1);
    $name=db_getvalue($i,2);
    $rec=[$net,$id,$name];
    push @{$list}, $rec;
  }
  return $list;
}

sub get_net($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("nets",
                      "server,name,net,subnet,rp_mbox,rp_txt,no_dhcp,comment,".
		      "range_start,range_end",$id,$rec,"id"));

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=4 AND ref=$id ORDER BY dhcp",$rec,'dhcp_l');
  
  return 0;
}

sub update_net($) {
  my($rec) = @_;
  my($r,$id);

  db_begin();
  $r=update_record('nets',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l',$rec,"4,$id");
  if ($r < 0) { db_rollback(); return -10; }

  return db_commit();
}



sub add_net($) {
  my($rec) = @_;

  return add_record('nets',$rec);
}


sub delete_net($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=4 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM nets WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  return db_commit();
}


#######################################################


sub get_who_list($$) {
  my($lst,$timeout) = @_;
  my(@q,$i,$j,$login,$last,$idle,$t,$s,$m,$h,$midle,$ip,$login_s);

  $t=time;
  db_query("SELECT u.username,u.name,a.addr,a.login,a.last " .
	   "FROM users u, utmp a " .
	   "WHERE a.uid=u.id;",\@q);

  for $i (0..$#q) {
    $login=$q[$i][3];
    $last=$q[$i][4];
    $idle=$t-$last;
    $s=$idle % 60;
    $midle=($idle-$s) / 60;
    $m=$midle % 60;
    $h=($midle-$m) / 60;
    $j= sprintf("%02d:%02d",$h,$m);
    $j= sprintf(" %02ds ",$s) if ($m <= 0 && $h <= 0);
    $ip = $q[$i][2];
    $ip =~ s/\/32$//;
    $login_s=localtime($login);
    next unless ($idle < $timeout);
    push @{$lst},[$q[$i][0],$q[$i][1],$ip,$j,$login_s];
  }

}


sub cgi_disabled() {
  my(@q);
  db_query("SELECT value FROM settings WHERE key='cgi_disable';",\@q);
  return ''if ($q[0][0] =~ /^\s*$/);
  return $q[0][0];
}
