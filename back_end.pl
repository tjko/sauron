#!/usr/bin/perl
#
# back_end.pl  -- Sauron back-end routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000.
# $Id$
#

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



sub update_record($$) {
  my ($table,$rec) = @_;
  my ($key,$sqlstr,$id,$flag,$r);
  
  return -128 unless ($table);
  return -1 unless (ref($rec) eq 'HASH');
  return -2 unless ($$rec{'id'} > 0);

  $id=$$rec{'id'};
  $sqlstr="UPDATE $table SET ";

  foreach $key (keys %{$rec}) {
    next if ($key eq 'id');

    $sqlstr.="," if ($flag);
    if (ref($$rec{$key}) eq 'ARRAY') {
      $sqlstr.="$key=" . db_encode_list_str($$rec{$key});
    } else {
      $sqlstr.="$key=" . db_encode_str($$rec{$key});
    }
   
    $flag=1 if (! $flag);
  }

  $sqlstr.=" WHERE id=$id;";
  #print "sql=$sqlstr\n";

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
  return get_record("servers",
		    "name,directory,named_ca,\@allow_transfer,\@dhcp," .
		    "pzone_path,szone_path,hostname,hostmaster,comment",
		    $id,
		    $rec,"id");
}



sub update_server($) {
  my($rec) = @_;
  return update_record('servers',$rec);
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
  
  return get_record("zones",
	       "server,active,dummy,type,reverse,class,name," .
	       "hostmaster,serial,refresh,retry,expire,minimum,ttl," .
	       "chknames," .
	       "\@ns,\@mx,\@txt,\@dhcp,comment,\@reverses,reversenet," .
	       "\@masters",
	       $id,$rec,"id");
}

sub update_zone($) {
  my($rec) = @_;
  return update_record('zones',$rec);
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
  } else {
    $subnets='false';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  $res=db_exec("SELECT net,id FROM nets " .
	       "WHERE server=$serverid " .
	       "ORDER BY net;");

  for($i=0; $i < $res; $i++) {
    $net=db_getvalue($i,0);
    $id=db_getvalue($i,1);
    $rec=[$net,$id];
    push @{$list}, $rec;
  }
  return $list;
}
