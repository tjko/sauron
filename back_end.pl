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
  return -3 unless ($list);
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
  my ($res,$t);
 
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

  return 0;
}




############################################################################
# user functions

sub get_user($$) {
  my ($uname,$rec) = @_;
  
  return get_record("users",
	       "username,password,name,comment,id",
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
