# Sauron::BackEnd.pm  -- Sauron back-end routines
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000-2003.
# $Id$
#
package Sauron::BackEnd;
require Exporter;
use Net::Netmask;
use Sauron::DB;
use Sauron::Util;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     sauron_db_version
	     get_db_version
	     set_muser
	     auto_address
	     next_free_ip
	     ip_in_use
	     domain_in_use
	     hostname_in_use
	     new_sid
	     get_host_network_settings

	     get_record
	     get_array_field
	     get_field
	     update_field
	     update_array_field
	     update_record
	     add_record_sql
	     add_record
	     copy_records

	     get_server_id
	     get_server_list
	     get_server
	     update_server
	     add_server
	     delete_server

	     get_zone_id
	     get_zone_list
	     get_zone
	     update_zone
	     add_zone
	     delete_zone
	     copy_zone

	     get_host_id
	     get_host
	     update_host
	     delete_host
	     add_host

	     get_mx_template
	     update_mx_template
	     add_mx_template
	     delete_mx_template
	     get_mx_template_list

	     get_wks_template
	     update_wks_template
	     add_wks_template
	     delete_wks_template
	     get_wks_template_list

	     get_printer_class
	     update_printer_class
	     add_printer_class
	     delete_printer_class

	     get_hinfo_template
	     update_hinfo_template
	     add_hinfo_template
	     delete_hinfo_template

	     get_group_by_name
	     get_group
	     update_group
	     add_group
	     delete_group
	     get_group_list

	     get_user
	     update_user
	     add_user
	     delete_user
	     get_user_group_id
             get_user_group
             delete_user_group

	     get_net_by_cidr
	     get_net_list
	     get_net
	     update_net
	     add_net
	     delete_net

	     get_vlan
	     update_vlan
	     add_vlan
	     delete_vlan
	     get_vlan_list
	     get_vlan_by_name

	     get_vmps_by_name
	     get_vmps
	     update_vmps
	     add_vmps
	     delete_vmps
	     get_vmps_list

	     add_news
	     get_news_list

	     get_who_list
	     cgi_disabled
	     get_permissions
	     update_lastlog
	     update_history
	     fix_utmp
	     get_lastlog

	     get_history_host
	     get_history_session
	    );


my($muser);

sub fix_bools($$) {
  my($rec,$names) = @_;
  my(@l,$name,$val);

  @l=split(/,/,$names);
  foreach $name (@l) {
    $val=$rec->{$name};
    $val=(($val eq 't' || $val == 1) ? 't' : 'f');
    $rec->{$name}=$val;
  }
}

sub sauron_db_version() {
  return "1.1"; # required db format version for this backend
}

sub set_muser($) {
  my($usr)=@_;
  $muser=$usr;
}


sub get_db_version() {
  my(@q);
  db_query("SELECT value FROM settings WHERE key='dbversion';",\@q);
  return ($q[0][0] =~ /^\d/ ? $q[0][0] : 'ERROR');
}


sub auto_address($$) {
  my($serverid,$net) = @_;
  my(@q,$s,$e,$i,$j,%h);

  return 'Invalid server id'  unless ($serverid > 0);
  return 'Invalid net'  unless (is_cidr($net));

  db_query("SELECT net,range_start,range_end FROM nets " .
	   "WHERE server=$serverid AND net = '$net';",\@q);
  return "No auto address range defined for this net: $net ".
         "($q[0][0],$q[0][1],$q[0][2]) "
	   unless (is_cidr($q[0][1]) && is_cidr($q[0][2]));
  $s=ip2int($q[0][1]);
  $e=ip2int($q[0][2]);
  return 'Invalid auto address range' if ($s >= $e);

  undef @q;
  db_query("SELECT a.ip FROM hosts h, a_entries a, zones z " .
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

sub next_free_ip($$)
{
  my($serverid,$ip) = @_;
  my(@q,@ips,%h,$net,$i,$t);

  return '' unless ($serverid > 0);
  return '' unless (is_cidr($ip));

  db_query("SELECT net FROM nets WHERE server=$serverid AND net >> '$ip' " .
	   "ORDER BY net DESC",\@q);
  return '' unless (@q > 0);
  db_query("SELECT a.ip FROM hosts h , a_entries a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND '$q[0][0]' >> a.ip ORDER BY a.ip;",\@ips);
  for $i (0..$#ips) { $h{$ips[$i][0]} = 1; }
  $net = new Net::Netmask($q[0][0]);
  $i = ip2int($ip) + 1;
  while ($net->match(($t=int2ip($i)))) {
    return $t unless ($h{$t});
    $i++;
  }
  return '';
}

sub ip_in_use($$) {
  my($serverid,$ip)=@_;
  my(@q);

  return -1 unless ($serverid > 0);
  return -2 unless (is_cidr($ip));
  db_query("SELECT a.id FROM hosts h, a_entries a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND a.ip = '$ip';",\@q);
  return 1 if ($q[0][0] > 0);
  return 0;
}

sub domain_in_use($$) {
  my($zoneid,$domain)=@_;
  my(@q);

  return -1 unless ($zoneid > 0);
  db_query("SELECT h.id FROM hosts h ".
	   "WHERE h.zone=$zoneid AND domain='$domain';",\@q);
  return $q[0][0] if ($q[0][0] > 0);
  return 0;
}

sub hostname_in_use($$) {
  my($zoneid,$hostname)=@_;
  my(@q,$domain);

  return -1 unless ($zoneid > 0);
  return -2 unless ($hostname =~ /^([A-Za-z0-9\-]+)(\.|$)/);
  $domain=$1;
  db_query("SELECT h.id FROM hosts h ".
	   "WHERE h.zone=$zoneid AND domain ~* '^$domain(\\\\.|\$)';",\@q);
  return $q[0][0] if ($q[0][0] > 0);
  return 0;
}

sub new_sid() {
  my(@q);

  db_query("SELECT NEXTVAL('sid_seq')",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

sub get_host_network_settings($$$) {
  my($serverid,$ip,$rec) = @_;
  my(@q,$tmp,$net);

  return -1 unless (is_cidr($ip) && ($serverid > 0));
  $rec->{ip}=$ip;

  db_query("SELECT id,name,net FROM nets " .
	   "WHERE server=$serverid AND no_dhcp=false AND '$ip' << net " .
	   "ORDER BY subnet,net",\@q);
  return -2 unless (@q > 0);
  return -3 unless ($q[$#q][0] > 0);
  $net = $q[$#q][2];
  $tmp = new Net::Netmask($net);
  $rec->{net}=$tmp->desc();
  $rec->{base}=$tmp->base();
  $rec->{mask}=$tmp->mask();
  $rec->{broadcast}=$tmp->broadcast();

  undef @q;
  db_query("SELECT a.ip FROM hosts h, a_entries a " .
	   "WHERE a.host=h.id AND h.router>0 AND a.ip << '$net' " .
	   "ORDER BY 1",\@q);
  if (@q > 0) {
    $rec->{gateway}=$q[0][0];
  } else {
    $rec->{gateway}='';
  }

  return 0;
}

#####################################################################

sub get_record($$$$$) {
  my ($table,$fields,$key,$rec,$keyname) = @_;
  my (@list,@q,$i,$val);

  $keyname='id' unless ($keyname);
  undef %{$rec};
  @list = split(",",$fields);
  $fields =~ s/\@//g;
  db_query("SELECT $fields FROM $table WHERE $keyname='$key'",\@q);
  return -1 if (@q < 1);

  $$rec{$keyname}=$key;
  for($i=0; $i < @list; $i++) {
    $val=$q[0][$i];
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

  db_query("SELECT $fields FROM $table WHERE $rule",\@list);
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

  db_query("SELECT $field FROM $table WHERE $rule",\@list);
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
      $str="DELETE FROM $table WHERE id=$id";
      #print "<BR>DEBUG: delete record $id $str";
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
      $str.=" WHERE id=$id";
      #print "<BR>DEBUG: update record $id $str";
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
      $str.=",$vals)";
      #print "<BR>DEBUG: add record $id $str";
      return -7 if (db_exec($str) < 0);
    }
  }

  return 0;
}

sub update_field($$$$$$) {
  my($table,$field,$rfields,$rvals,$tag,$rec) = @_;
  my(@rf,@rv,@q,$sqlstr,$i,$rule);

  return -1 unless (ref($rec) eq 'HASH');
  return -2 unless ($table && $field && $rfields && $rvals && $tag);
  @rf = split(",",$rfields);
  @rv = split(",",$rvals);
  return -3 unless (@rf == @rv);
  for $i (0..$#rf) {
    $rule.=" AND " if ($i > 0);
    $rule.=$rf[$i] . "=" . db_encode_str($rv[$i]);
  }

  $sqlstr = "SELECT $field FROM $table WHERE $rule";
  db_query($sqlstr,\@q);
  if (@q > 0) {
    unless ($rec->{$tag}) {
      $sqlstr = "DELETE FROM $table WHERE $rule";
      return -9 if (db_exec($sqlstr) < 0);
    } else {
      if ($q[0][0] ne $rec->{$tag}) {
	$sqlstr = "UPDATE $table SET $field=".db_encode_str($rec->{$tag}).
	          " WHERE $rule";
	return -10 if (db_exec($sqlstr) < 0);
      }
    }
  } else {
    if ($rec->{$tag}) {
      $sqlstr = "INSERT INTO $table ($field,$rfields) " .
	        "VALUES(".db_encode_str($rec->{$tag}).",$rvals)";
      return -11 if (db_exec($sqlstr) < 0);
    }
  }
  return 0;
}

sub add_array_field($$$$$$) {
  my($table,$fields,$keyname,$rec,$rfields,$vals) = @_;

  my($i,$j,$sqlstr,$flag,@f);

  return -1 unless (ref($rec) eq 'HASH');
  return -2 unless ($table && $keyname && $vals && $rfields);
  @f = split(",",$fields);
  return -3 unless (@f > 0);

  for $i (0..$#{$rec->{$keyname}}) {
    next if (@{$rec->{$keyname}->[$i]} <= 1);
    return -10 unless (@{$rec->{$keyname}->[$i]} >= (@f + 1));
    $flag = 0;
    $sqlstr = "INSERT INTO $table ($fields,$rfields) VALUES(";
    for $j (1..($#f + 1)) {
      $sqlstr .= "," if ($flag);
      $sqlstr .= db_encode_str($rec->{$keyname}->[$i][$j]);
      $flag = 1;
    }
    $sqlstr .= ",$vals)";
    #print "<BR>DEBUG: add_array_field: insert record '$sqlstr'\n";
    return -20 if (db_exec($sqlstr) < 0);
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

  $sqlstr.=" WHERE id=$id";
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
  $sqlstr.=")";

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
  db_query("SELECT id FROM $table WHERE OID=$oid",\@q);
  return -2 if (@q < 1);
  return $q[0][0];
}

sub copy_records($$$$$$$) {
  my($stable,$ttable,$key,$reffield,$ids,$fields,$selectsql)=@_;
  my(@data,%h,$i,$newref,$tmp);

  # make ID hash
  for $i (0..$#{$ids}) { $h{$$ids[$i][0]}=$$ids[$i][1]; }

  # read records into array & fix key fields using hash

  $tmp="SELECT $reffield,$fields FROM $stable WHERE $key IN ($selectsql)";
  #print "$tmp\n";
  db_query($tmp,\@data);
  #print "<br>$stable records to copy: " . @data . "\n";
  return 0 if (@data < 1);

  for $i (0..$#data) {
    $newref=$h{$data[$i][0]};
    return -1 unless ($newref);
    $data[$i][0]=$newref;
  }

  return db_insert($ttable,"$reffield,$fields",\@data);
}

sub add_std_fields($) {
  my($rec) = @_;

  return unless (ref($rec) eq 'HASH');

  $rec->{cdate_str}=($rec->{cdate} > 0 ?
		     localtime($rec->{cdate}).' by '.$rec->{cuser} : 'UNKOWN');
  $rec->{mdate_str}=($rec->{mdate} > 0 ?
		     localtime($rec->{mdate}).' by '.$rec->{muser} : '');
}

sub del_std_fields($) {
  my($rec) = @_;

  return unless (ref($rec) eq 'HASH');

  delete $rec->{cdate_str};
  delete $rec->{mdate_str};
  delete $rec->{cdate};
  delete $rec->{cuser};

  $rec->{mdate}=time;
  $rec->{muser}=$muser;
}

############################################################################
# server table functions

sub get_server_id($) {
  my ($server) = @_;
  my (@q);

  return -1 unless ($server);
  $server=db_encode_str($server);
  db_query("SELECT id FROM servers WHERE name=$server",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -2);
}

sub get_server_list($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';

  db_query("SELECT id,name,comment FROM servers ORDER BY name",\@q);
  for $i (0..$#q) {
    next if ($q[$i][0] == $serverid);
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}="$q[$i][1] -- $q[$i][2]";
  }
}


sub get_server($$) {
  my ($id,$rec) = @_;
  my ($res,@q);

  $res = get_record("servers",
            "name,directory,no_roots,named_ca,zones_only,pid_file,dump_file," .
		    "named_xfer,stats_file,query_src_ip,query_src_port," .
		    "listen_on_port,checknames_m,checknames_s,checknames_r," .
		    "nnotify,recursion,ttl,refresh,retry,expire,minimum," .
		    "pzone_path,szone_path,hostname,hostmaster,comment," .
		    "dhcp_flags,named_flags,masterserver,version," .
		    "memstats_file,transfer_source,forward,dialup," .
		    "multiple_cnames,rfc2308_type1,authnxdomain," .
		    "df_port,df_max_delay,df_max_uupdates,df_mclt,df_split,".
		    "df_loadbalmax,hostaddr,".
		    "cdate,cuser,mdate,muser",
		    $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"no_roots,zones_only");

  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=1 AND ref=$id ORDER BY ip",$rec,'allow_transfer');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=7 AND ref=$id ORDER BY ip",$rec,'allow_query');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=8 AND ref=$id ORDER BY ip",$rec,'allow_recursion');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=9 AND ref=$id ORDER BY ip",$rec,'blackhole');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=10 AND ref=$id ORDER BY ip",$rec,'listen_on');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=11 AND ref=$id ORDER BY ip",$rec,'forwarders');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=1 AND ref=$id ORDER BY id",$rec,'dhcp');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=3 AND ref=$id ORDER BY id",$rec,'txt');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=10 AND ref=$id ORDER BY id",$rec,'logging');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=11 AND ref=$id ORDER BY id",$rec,'custom_opts');

  $rec->{dhcp_flags_ad}=($rec->{dhcp_flags} & 0x01 ? 1 : 0);
  $rec->{dhcp_flags_fo}=($rec->{dhcp_flags} & 0x02 ? 1 : 0);
  $rec->{named_flags_ac}=($rec->{named_flags} & 0x01 ? 1 : 0);
  $rec->{named_flags_isz}=($rec->{named_flags} & 0x02 ? 1 : 0);
  $rec->{named_flags_hinfo}=($rec->{named_flags} & 0x04 ? 1 : 0);
  $rec->{named_flags_wks}=($rec->{named_flags} & 0x08 ? 1 : 0);

  if ($rec->{masterserver} > 0) {
    db_query("SELECT name FROM servers WHERE id=$rec->{masterserver}",\@q);
    $rec->{server_type}="Slave for $q[0][0] (id=$rec->{masterserver})";
  } else {
    $rec->{server_type}='Master';
  }

  add_std_fields($rec);
  return 0;
}



sub update_server($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);
  delete $rec->{dhcp_flags};
  delete $rec->{server_type};

  $rec->{dhcp_flags}=0;
  $rec->{dhcp_flags}|=0x01 if ($rec->{dhcp_flags_ad});
  $rec->{dhcp_flags}|=0x02 if ($rec->{dhcp_flags_fo});
  delete $rec->{dhcp_flags_ad};
  delete $rec->{dhcp_flags_fo};
  $rec->{named_flags}=0;
  $rec->{named_flags}|=0x01 if ($rec->{named_flags_ac});
  $rec->{named_flags}|=0x02 if ($rec->{named_flags_isz});
  $rec->{named_flags}|=0x04 if ($rec->{named_flags_hinfo});
  $rec->{named_flags}|=0x08 if ($rec->{named_flags_wks});
  delete $rec->{named_flags_ac};
  delete $rec->{named_flags_isz};
  delete $rec->{named_flags_hinfo};
  delete $rec->{named_flags_wks};

  db_begin();
  $r=update_record('servers',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  # allow_transfer
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'allow_transfer',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -12; }
  # dhcp
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp',$rec,
		        "1,$id");
  if ($r < 0) { db_rollback(); return -13; }
  # txt
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'txt',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -14; }
  # allow_query
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'allow_query',$rec,"7,$id");
  if ($r < 0) { db_rollback(); return -15; }
  # allow_recursion
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'allow_recursion',$rec,"8,$id");
  if ($r < 0) { db_rollback(); return -16; }
  # blackhole
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'blackhole',$rec,"9,$id");
  if ($r < 0) { db_rollback(); return -17; }
  # listen_on
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'listen_on',$rec,"10,$id");
  if ($r < 0) { db_rollback(); return -18; }
  # forwarder
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'forwarders',$rec,"11,$id");
  if ($r < 0) { db_rollback(); return -19; }
  # logging (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'logging',$rec,"10,$id");
  if ($r < 0) { db_rollback(); return -20; }
  # custom options (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'custom_opts',$rec,"11,$id");
  if ($r < 0) { db_rollback(); return -21; }

  return db_commit();
}

sub add_server($) {
  my($rec) = @_;
  my($res,$id);

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  db_begin();
  $res = add_record('servers',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # allow_transfer
  $res = add_array_field('cidr_entries','ip,comment','allow_transfer',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { db_rollback(); return -10; }
  # dhcp
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { db_rollback(); return -11; }
  # txt
  $res = add_array_field('txt_entries','txt,comment','txt',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -12; }
  # allow_query
  $res = add_array_field('cidr_entries','ip,comment','allow_query',$rec,
			 'type,ref',"7,$id");
  if ($res < 0) { db_rollback(); return -13; }
  # allow_recursion
  $res = add_array_field('cidr_entries','ip,comment','allow_recursion',$rec,
			 'type,ref',"8,$id");
  if ($res < 0) { db_rollback(); return -14; }
  # blackhole
  $res = add_array_field('cidr_entries','ip,comment','blackhole',$rec,
			 'type,ref',"9,$id");
  if ($res < 0) { db_rollback(); return -15; }
  # listen_on
  $res = add_array_field('cidr_entries','ip,comment','listen_on',$rec,
			 'type,ref',"10,$id");
  if ($res < 0) { db_rollback(); return -16; }
  # forwarders
  $res = add_array_field('cidr_entries','ip,comment','forwarders',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { db_rollback(); return -17; }
  # logging
  $res = add_array_field('txt_entries','txt,comment','logging',$rec,
			 'type,ref',"10,$id");
  if ($res < 0) { db_rollback(); return -18; }
  # custom options
  $res = add_array_field('txt_entries','txt,comment','custom_opts',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { db_rollback(); return -19; }


  return -100 if (db_commit() < 0);
  return $id;
}

sub delete_server($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # cidr_entries 
  $res=db_exec("DELETE FROM cidr_entries " .
	       "WHERE (type=1 OR type=7 OR type=8 OR type=9 OR type=10 " .
	       " OR type=11) AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM cidr_entries WHERE id IN ( " .
	        "SELECT a.id FROM cidr_entries a, zones z " .
	        "WHERE z.server=$id AND " .
                " (a.type=12 OR a.type=6 OR a.type=5 OR a.type=4 OR " .
	        "  a.type=3 OR a.type=2) " .
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
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, vlans v " .
	        "WHERE v.server=$id AND a.type=6 AND a.ref=v.id);");
  if ($res < 0) { db_rollback(); return -8; }

  # host_info
  # FIXME

  # mx_entries
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
  $res=db_exec("DELETE FROM txt_entries " .
	       "WHERE (type=3 OR type=10 OR type=11) AND ref=$id;");
  if ($res < 0) { db_rollback(); return -17; }
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " . 
	       "SELECT a.id FROM txt_entries a, zones z " .
	       "WHERE z.server=$id AND a.type=12 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -180; }
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
	       "SELECT a.id FROM txt_entries a, zones z, hosts h " .
	  "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -18; }


  # a_entries
  $res=db_exec("DELETE FROM a_entries WHERE id IN ( " .
	       "SELECT a.id FROM a_entries a, zones z, hosts h " .
	       "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { db_rollback(); return -19; }

  # arec_entries
  $res=db_exec("DELETE FROM arec_entries WHERE id IN ( " .
	       "SELECT a.id FROM arec_entries a, zones z, hosts h " .
	       "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { db_rollback(); return -20; }

  # srv_entries
  $res=db_exec("DELETE FROM srv_entries WHERE id IN ( " .
	       "SELECT a.id FROM srv_entries a, zones z, hosts h " .
            "WHERE z.server=$id AND h.zone=z.id AND a.type=1 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -21; }

  # wks_templates
  $res=db_exec("DELETE FROM wks_templates WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -25; }

  # mx_templates
  $res=db_exec("DELETE FROM mx_templates WHERE id IN ( " .
	       "SELECT a.id FROM mx_templates a, zones z " .
	       "WHERE z.server=$id AND a.zone=z.id);");
  if ($res < 0) { db_rollback(); return -26; }

  # groups
  $res=db_exec("DELETE FROM groups WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -27; }

  # nets
  $res=db_exec("DELETE FROM nets WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -28; }

  # hosts
  $res=db_exec("DELETE FROM hosts WHERE id IN ( " .
	       "SELECT a.id FROM hosts a, zones z " .
	       "WHERE z.server=$id AND a.zone=z.id);");
  if ($res < 0) { db_rollback(); return -29; }

  # zones
  $res=db_exec("DELETE FROM zones WHERE server=$id;");
  if ($res < 0) { db_rollback(); return -30; }

  $res=db_exec("DELETE FROM servers WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -31; }

  return db_commit();
  #return db_rollback();
}

############################################################################
# zone table functions

sub get_zone_id($$) {
  my ($zone,$serverid) = @_;
  my (@q);

  return -1 unless ($zone && $serverid > 0);
  $zone = db_encode_str($zone);
  db_query("SELECT id FROM zones WHERE server=$serverid AND name=$zone",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -2);
}

sub get_zone_list($$$) {
  my ($serverid,$type,$reverse) = @_;
  my ($res,$list,$i,$id,$name,$rec);

  $type = ($type ? " AND type='$type' " : '');
  $reverse = ($reverse ? " AND reverse='$reverse' " : '');

  $list=[];
  return $list unless ($serverid >= 0);

  db_query("SELECT name,id,type,reverse,comment FROM zones " .
	   "WHERE server=$serverid $type $reverse " .
	   "ORDER BY type,reverse,reversenet,name;",$list);
  return $list;
}

sub get_zone($$) {
  my ($id,$rec) = @_;
  my ($res,@q,$hid);

  $res = get_record("zones",
	       "server,active,dummy,type,reverse,class,name,nnotify," .
	       "hostmaster,serial,refresh,retry,expire,minimum,ttl," .
	       "chknames,reversenet,comment,cdate,cuser,mdate,muser," .
	       "forward,serial_date,flags,rdate",
	       $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"active,dummy,reverse,noreverse");

  if ($rec->{type} eq 'M') {
    $hid=get_host_id($id,'@');
    if ($hid > 0) {
      get_array_field("ns_entries",3,"id,ns,comment","NS,Comments",
		      "type=2 AND ref=$hid ORDER BY ns",$rec,'ns');
      get_array_field("mx_entries",4,"id,pri,mx,comment",
		      "Priority,MX,Comments",
		      "type=2 AND ref=$hid ORDER BY pri,mx",$rec,'mx');
      get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		      "type=2 AND ref=$hid ORDER BY id",$rec,'txt');
      get_array_field("a_entries",4,"id,ip,reverse,forward",
		      "IP,reverse,forward","host=$hid ORDER BY ip",$rec,'ip');

      $rec->{zonehostid}=$hid;
    }
  }
  elsif ($rec->{type} eq 'S') {
    get_field("cidr_entries","ip","type=13 AND ref=$id",'transfer_src',$rec);
  }

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=2 AND ref=$id ORDER BY id",$rec,'dhcp');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=2 AND ref=$id ORDER BY ip",$rec,'allow_update');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=3 AND ref=$id ORDER BY ip",$rec,'masters');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=4 AND ref=$id ORDER BY ip",$rec,'allow_query');
  get_array_field("cidr_entries",3,"id,ip,comment","CIDR,Comments",
		  "type=5 AND ref=$id ORDER BY ip",$rec,'allow_transfer');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=6 AND ref=$id ORDER BY ip",$rec,'also_notify');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=12 AND ref=$id ORDER BY ip",$rec,'forwarders');
  get_array_field("txt_entries",3,"id,txt,comment","ZoneEntry,Comments",
		  "type=12 AND ref=$id ORDER BY id",$rec,'zentries');


  db_query("SELECT COUNT(h.id) FROM hosts h, zones z " .
	   "WHERE z.id=$id AND h.zone=$id " .
	   " AND (h.mdate > z.serial_date OR h.cdate > z.serial_date);",\@q);
  $rec->{pending_info}=($q[0][0] > 0 ? 
			"<FONT color=\"#ff0000\">$q[0][0]</FONT>" : 'None');


  $rec->{txt_auto_generation}=($rec->{flags} & 0x01 ? 1 : 0);

  add_std_fields($rec);
  return 0;
}

sub update_zone($) {
  my($rec) = @_;
  my($r,$id,$new_net,$hid);

  del_std_fields($rec);
  delete $rec->{pending_info};
  delete $rec->{zonehostid};

  $rec->{flags}=0;
  $rec->{flags}|=0x01 if ($rec->{txt_auto_generation});
  delete $rec->{txt_auto_generation};

  if ($rec->{reverse} eq 't' || $rec->{reverse} == 1) {
      $new_net=arpa2cidr($rec->{name});
      if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
	  return -100;
      }
      $rec->{reversenet}=$new_net;
  }

  db_begin();
  $id=$rec->{id};

  if ($rec->{type} eq 'S') {
    $rec->{transfer_src} .= '/32' if ($rec->{transfer_src} &&
				      $rec->{transfer_src} !~ /\/32$/);
    $r=update_field("cidr_entries","ip","type,ref","13,$id",
		    'transfer_src',$rec);
    if ($r < 0) { db_rollback(); return -1000+$r; }
    delete $rec->{transfer_src};
  }

  $r=update_record('zones',$rec);
  if ($r < 0) { db_rollback(); return $r; }

  return -199 unless ($rec->{type});
  if ($rec->{type} eq 'M') {
    $hid=get_host_id($id,'@');
    return -200 unless ($hid > 0);

    $r=update_array_field("a_entries",4,"ip,reverse,forward,host",
			  'ip',$rec,"$hid");
    if ($r < 0) { db_rollback(); return -10; }

    $r=update_array_field("ns_entries",3,"ns,comment,type,ref",
			  'ns',$rec,"2,$hid");
    if ($r < 0) { db_rollback(); return -12; }
    $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			  'mx',$rec,"2,$hid");
    if ($r < 0) { db_rollback(); return -13; }
    $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			  'txt',$rec,"2,$hid");
    if ($r < 0) { db_rollback(); return -14; }
  }

  # dhcp
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -15; }

  # allow_update
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'allow_update',$rec,"2,$id");
  if ($r < 0) { db_rollback(); return -16; }
  # masters
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'masters',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -17; }
  # allow_query
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'allow_query',$rec,"4,$id");
  if ($r < 0) { db_rollback(); return -18; }
  # allow_transfer
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'allow_transfer',$rec,"5,$id");
  if ($r < 0) { db_rollback(); return -19; }
  # also_notify
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'also_notify',$rec,"6,$id");
  if ($r < 0) { db_rollback(); return -20; }
  # forwarders
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'forwarders',$rec,"12,$id");
  if ($r < 0) { db_rollback(); return -20; }
  # zentries
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'zentries',$rec,"12,$id");
  if ($r < 0) { db_rollback(); return -21; }

  return db_commit();
}

sub delete_zone($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # cidr_entries
  print "<BR>Deleting CIDR entries...\n";
  $res=db_exec("DELETE FROM cidr_entries WHERE " .
	       "(type=2 OR type=3 OR type=4 OR type=5 OR type=6 OR " .
	       " type=12 OR type=13) " .
	       " AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }

  # dhcp_entries
  print "<BR>Deleting DHCP entries...\n";
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=2 AND ref=$id");
  if ($res < 0) { db_rollback(); return -2; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, hosts h " .
	        "WHERE h.zone=$id AND a.type=3 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -3; }

  # mx_entries
  print "<BR>Deleting MX entries...\n";
  #$res=db_exec("DELETE FROM mx_entries WHERE type=1 AND ref=$id");
  #if ($res < 0) { db_rollback(); return -4; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -5; }
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
	       "SELECT a.id FROM mx_entries a, mx_templates m " .
	       "WHERE m.zone=$id AND a.type=3 AND a.ref=m.id)");
  if ($res < 0) { db_rollback(); return -6; }

  # wks_entries
  print "<BR>Deleting WKS entries...\n";
  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
	       "SELECT a.id FROM wks_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -7; }

  # ns_entries
  print "<BR>Deleting NS entries...\n";
  #$res=db_exec("DELETE FROM ns_entries WHERE type=1 AND ref=$id");
  #if ($res < 0) { db_rollback(); return -8; }
  $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " .
	       "SELECT a.id FROM ns_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -9; }


  # printer_entries
  print "<BR>Deleting PRINTER entries...\n";
  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
	       "SELECT a.id FROM printer_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -10; }

  # txt_entries
  print "<BR>Deleting TXT entries...\n";
  $res=db_exec("DELETE FROM txt_entries WHERE type=12 AND ref=$id");
  if ($res < 0) { db_rollback(); return -11; }
  $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
	       "SELECT a.id FROM txt_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -12; }

  # a_entries
  print "<BR>Deleting A entries...\n";
  $res=db_exec("DELETE FROM a_entries WHERE id IN ( " .
	       "SELECT a.id FROM a_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.host=h.id)");
  if ($res < 0) { db_rollback(); return -13; }

  # arec_entries
  print "<BR>Deleting AREC entries...\n";
  $res=db_exec("DELETE FROM arec_entries WHERE id IN ( " .
	       "SELECT a.id FROM arec_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.host=h.id)");
  if ($res < 0) { db_rollback(); return -14; }

  # mx_templates
  print "<BR>Deleting MX templates...\n";
  $res=db_exec("DELETE FROM mx_templates WHERE zone=$id");
  if ($res < 0) { db_rollback(); return -15; }

  # srv_entries
  print "<BR>Deleting SRV entries...\n";
  $res=db_exec("DELETE FROM srv_entries WHERE id IN ( " .
	       "SELECT a.id FROM srv_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
  if ($res < 0) { db_rollback(); return -15; }

  # hosts
  print "<BR>Deleting Hosts...\n";
  $res=db_exec("DELETE FROM hosts WHERE zone=$id");
  if ($res < 0) { db_rollback(); return -25; }


  print "<BR>Deleting Zone record...\n";
  $res=db_exec("DELETE FROM zones WHERE id=$id");
  if ($res < 0) { db_rollback(); return -50; }


  $res=db_exec("DELETE FROM user_rights WHERE rtype=2 AND rref=$id");
  if ($res < 0) { db_rollback(); return -100; }

  return db_commit();
}

sub add_zone($) {
  my($rec) = @_;
  my($new_net,$res,$id,$hid,$transfer_src);

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  if ($rec->{reverse} =~ /^(t|true)$/) {
      $new_net=arpa2cidr($rec->{name});
      if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
	  return -100;
      }
      $rec->{reversenet}=$new_net;
  }

  if ($rec->{type} eq 'S') {
    $transfer_src=$rec->{transfer_src};
    delete $rec->{transfer_src}
  }

  db_begin();
  $res = add_record('zones',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  if ($transfer_src) {
    $res=update_field("cidr_entries","ip","type,ref","13,$id",
		      'transfer_src',{transfer_src=>$transfer_src});
    if ($res < 0) { db_rollback(); return -1000+$res; }
  }

  if ($rec->{type} eq 'M') {
    # zone's host record (@)
    $res = add_record('hosts',{zone=>$id,type=>10,domain=>'@',
			       comment=>'zone record'});
    if ($res < 0) { db_rollback(); return -101; }
    $hid=$res;

    # ns
    $res = add_array_field('ns_entries','ns,comment','ns',$rec,
			   'type,ref',"2,$hid");
    if ($res < 0) { db_rollback(); return -102; }
    # mx
    $res = add_array_field('mx_entries','pri,mx,comment','mx',$rec,
			   'type,ref',"2,$hid");
    if ($res < 0) { db_rollback(); return -103; }
    # txt
    $res = add_array_field('txt_entries','txt,comment','txt',$rec,
			   'type,ref',"2,$hid");
    if ($res < 0) { db_rollback(); return -104; }
    # ip
    $res = add_array_field('a_entries','ip,reverse,forward','ip',$rec,
			   'host',"$hid");
    if ($res < 0) { db_rollback(); return -105; }
  }

  # dhcp
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -111; }

  # allow_update
  $res = add_array_field('cidr_entries','ip,comment','allow_update',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -2; }
  # masters
  $res = add_array_field('cidr_entries','ip,comment','masters',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -3; }
  # allow_query
  $res = add_array_field('cidr_entries','ip,comment','allow_query',$rec,
			 'type,ref',"4,$id");
  if ($res < 0) { db_rollback(); return -4; }
  # allow_transfer
  $res = add_array_field('cidr_entries','ip,comment','allow_transfer',$rec,
			 'type,ref',"5,$id");
  if ($res < 0) { db_rollback(); return -5; }
  # also_notify
  $res = add_array_field('cidr_entries','ip,comment','also_notify',$rec,
			 'type,ref',"6,$id");
  if ($res < 0) { db_rollback(); return -6; }
  # forwarders
  $res = add_array_field('cidr_entries','ip,comment','forwarders',$rec,
			 'type,ref',"12,$id");
  if ($res < 0) { db_rollback(); return -7; }
  # zentries
  $res = add_array_field('txt_entries','txt,comment','zentries',$rec,
			 'type,ref',"12,$id");
  if ($res < 0) { db_rollback(); return -8; }


  return -100 if (db_commit() < 0);
  return $id;
}

sub copy_zone($$$$) {
  my($id,$serverid,$newname,$verbose)=@_;
  my($newid,%z,$res,@q,@ids,@hids,$i,$j,%h,@t,$fields,$fields2,%aids);
  my($timenow,%eaids,%hidh,$new_net);

  return -1 if (get_zone($id,\%z) < 0);
  del_std_fields(\%z);
  delete $z{pending_info};
  delete $z{zonehostid};
  delete $z{txt_auto_generation};


  if ($z{reverse} =~ /^(t|true)$/) {
    $new_net=arpa2cidr($newname);
    if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
      return -100;
    }
    $z{reversenet}=$new_net;
  }

  print "<BR>Copying zone record..." if ($verbose);
  delete $z{id};
  $z{server}=$serverid;
  $z{name}=$newname;
  $z{cuser}=$muser;
  $z{cdate}=time;

  db_begin();
  $newid=add_record('zones',\%z);
  if ($newid < 1) { db_rollback(); return -2; }


  # Records pointing to the zone record
  print "<BR>Copying records pointing to zone record..." if ($verbose);

  # cidr_entries
  $res=db_exec("INSERT INTO cidr_entries (type,ref,ip,comment) " .
	       "SELECT type,$newid,ip,comment FROM cidr_entries " .
	       "WHERE (type=2 OR type=3 OR type=4 OR type=5 OR type=6 " .
	       " OR type=12) AND ref=$id;");
  if ($res < 0) { db_rollback(); return -3; }

  # dhcp_entries
  $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp,comment) " .
	       "SELECT type,$newid,dhcp,comment FROM dhcp_entries " .
	       "WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -4; }

  # mx_templates
  print "<BR>Copying MX templates..." if ($verbose);
  undef @q;
  db_query("SELECT id FROM mx_templates WHERE zone=$id;",\@ids);
  for $i (0..$#ids) {
    undef %h;
    if (get_mx_template($ids[$i][0],\%h) < 0) { db_rollback(); return -8; }
    del_std_fields(\%h);
    $h{zone}=$newid;
    $h{cuser}=$muser;
    $h{cdate}=time;
    $j=add_record('mx_templates',\%h);
    if ($j < 0) { db_rollback(); print db_errormsg(); return -9; }
    $ids[$i][1]=$j;
    $res=db_exec("INSERT INTO mx_entries (type,ref,pri,mx,comment) " .
		 "SELECT type,$j,pri,mx,comment FROM mx_entries " .
		 "WHERE type=3 AND ref=$ids[$i][0];");
    if ($res < 0) { db_rollback(); return -10; }
  }

  # hosts
  print "<BR>Copying hosts..." if ($verbose);
  $fields='type,domain,ttl,class,grp,alias,cname_txt,hinfo_hw,' .
          'hinfo_sw,loc,wks,mx,rp_mbox,rp_txt,router,prn,flags,ether,' .
	  'ether_alias,info,location,dept,huser,model,serial,misc,asset_id,' .
	  'comment,expiration';
  $fields2 = 'cdate,cuser,mdate,muser';
  $timenow = time;

  $res=db_exec("INSERT INTO hosts (zone,$fields,$fields2) " .
	  "SELECT $newid,$fields,$timenow,'$muser',NULL,'$muser' FROM hosts " .
	       "WHERE zone=$id;");
  if ($res < 0) { db_rollback(); return -11; }

  db_query("SELECT a.id,b.id,a.domain FROM hosts a, hosts b " .
	   "WHERE a.zone=$id AND b.zone=$newid AND a.domain=b.domain;",\@hids);
  print "<br>hids = " . $#hids;
  for $i (0..$#hids) { $hidh{$hids[$i][0]}=$hids[$i][1]; }

  # a_entries
  print "<BR>Copying A records..." if ($verbose);
  $res=copy_records('a_entries','a_entries','id','host',\@hids,
     'ip,ipv6,type,reverse,forward,comment',
     "SELECT a.id FROM a_entries a,hosts h WHERE a.host=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -12; }

  # dhcp_entries
  print "<BR>Copying DHCP records..." if ($verbose);
  $res=copy_records('dhcp_entries','dhcp_entries','id','ref',\@hids,
     'type,dhcp,comment',
     "SELECT a.id FROM dhcp_entries a,hosts h " .
     "WHERE a.type=3 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -13; }

  # mx_entires
  print "<BR>Copying MX records..." if ($verbose);
  $res=copy_records('mx_entries','mx_entries','id','ref',\@hids,
     'type,pri,mx,comment',
     "SELECT a.id FROM mx_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -14; }

  # wks_entries
  print "<BR>Copying WKS records..." if ($verbose);
  $res=copy_records('wks_entries','wks_entries','id','ref',\@hids,
     'type,proto,services,comment',
     "SELECT a.id FROM wks_entries a,hosts h " .
     "WHERE a.type=1 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -15; }

  # ns_entries
  print "<BR>Copying NS records..." if ($verbose);
  $res=copy_records('ns_entries','ns_entries','id','ref',\@hids,
     'type,ns,comment',
     "SELECT a.id FROM ns_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -16; }

  # printer_entries
  print "<BR>Copying PRINTER records..." if ($verbose);
  $res=copy_records('printer_entries','printer_entries','id','ref',\@hids,
     'type,printer,comment',
     "SELECT a.id FROM printer_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -17; }

  # txt_entries
  print "<BR>Copying TXT records..." if ($verbose);
  $res=copy_records('txt_entries','txt_entries','id','ref',\@hids,
     'type,txt,comment',
     "SELECT a.id FROM txt_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -18; }

  # srv_entries
  print "<BR>Copying SRV records..." if ($verbose);
  $res=copy_records('srv_entries','srv_entries','id','ref',\@hids,
     'type,pri,weight,port,target,comment',
     "SELECT a.id FROM srv_entries a,hosts h " .
     "WHERE a.type=1 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { db_rollback(); return -19; }

  # update mx_template pointers
  print "<BR>Updating MX template pointers..." if ($verbose);
  for $i (0..$#ids) {
    $res=db_exec("UPDATE hosts SET mx=$ids[$i][1] " .
		 "WHERE zone=$newid AND mx=$ids[$i][0];");
    if ($res < 0) { db_rollback(); return -20; }
  }

  # update alias pointers
  print "<BR>Updating ALIAS pointers..." if ($verbose);
  undef @q;
  db_query("SELECT alias FROM hosts WHERE zone=$newid AND alias > 0;",\@q);
  print " " .@q." alias records to update..." if ($verbose);
  for $i (0..$#q) { $aids{$q[$i][0]}=1; }
  for $i (0..$#hids) {
    next unless ($aids{$hids[$i][0]});
    $res=db_exec("UPDATE hosts SET alias=$hids[$i][1] " .
		 "WHERE zone=$newid AND alias=$hids[$i][0];");
    if ($res < 0) { db_rollback(); return -21; }
  }

  # update ether_alias pointers
  print "<BR>Updating ETHERALIAS pointers..." if ($verbose);
  undef @q;
  db_query("SELECT ether_alias FROM hosts " .
	   "WHERE zone=$newid AND ether_alias > 0;",\@q);
  print " " .@q." ether_alias records to update..." if ($verbose);
  for $i (0..$#q) { $eaids{$q[$i][0]}=1; }
  for $i (0..$#hids) {
    next unless ($eaids{$hids[$i][0]});
    $res=db_exec("UPDATE hosts SET ether_alias=$hids[$i][1] " .
		 "WHERE zone=$newid AND ether_alias=$hids[$i][0];");
    if ($res < 0) { db_rollback(); return -22; }
  }

  # copy AREC entries
  print "<BR>Copying AREC entries..." if ($verbose);
  undef @q;
  db_query("SELECT a.host,a.arec FROM arec_entries a, hosts h " .
	   "WHERE h.zone=$id AND h.id=a.host",\@q);
  for $i (0..$#q) {
    #print "$i: $q[$i][0] --> $hidh{$q[$i][0]}, $q[$i][1] --> $hidh{$q[$i][1]}<br>";
    return -23 unless ($hidh{$q[$i][0]} && $hidh{$q[$i][1]});
    $q[$i][0]=$hidh{$q[$i][0]};
    $q[$i][1]=$hidh{$q[$i][1]};
  }
  $res = db_insert('arec_entries','host,arec',\@q);
  if ($res < 0) { db_rollback(); return -24; }

  return -100 if (db_commit() < 0);
  return $newid;
}

############################################################################
# hosts table functions

sub get_host_id($$) {
  my($zoneid,$domain)=@_;
  my(@q);

  $domain=db_encode_str($domain);
  db_query("SELECT id FROM hosts WHERE zone=$zoneid AND domain=$domain",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

sub get_host($$); # declare it here since get_host uses sometimes recursion

sub get_host($$) {
  my ($id,$rec) = @_;
  my ($res,$t,$wrec,$mrec,%h,@q,$infostr);

  $res = get_record("hosts",
	       "zone,type,domain,ttl,class,grp,alias,cname_txt," .
	       "hinfo_hw,hinfo_sw,wks,mx,rp_mbox,rp_txt,router," .
	       "prn,ether,ether_alias,info,location,dept,huser,model," .
	       "serial,misc,cdate,cuser,muser,mdate,comment,dhcp_date," .
	       "expiration,asset_id,dhcp_info,flags",
	       $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"prn");

  get_array_field("a_entries",4,"id,ip,reverse,forward",
		  "IP,reverse,forward","host=$id ORDER BY ip",$rec,'ip');

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
		  "type=3 AND ref=$id ORDER BY id",$rec,'dhcp_l');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=2 AND ref=$id ORDER BY printer",$rec,'printer_l');
  get_array_field("srv_entries",6,"id,pri,weight,port,target,comment",
		  "Priority,Weight,Port,Target",
		  "type=1 AND ref=$id ORDER BY port,pri,weight",$rec,'srv_l');

  get_array_field("hosts",4,"0,id,domain,type","Domain,cname",
	          "type=4  AND alias=$id ORDER BY domain",$rec,'alias_l');

  get_array_field("hosts h, arec_entries a",4,"a.id,h.id,h.domain,h.type",
		  "Domain,cname",
	          "h.type=7 AND a.host=h.id AND a.arec=$id ORDER BY h.domain",
		  $rec,'alias_l2');
  splice(@{$rec->{alias_l2}},0,1);
  push(@{$rec->{alias_l}},@{$rec->{alias_l2}});
  delete $rec->{alias_l2};

  if ($rec->{ether}) {
    $t=substr($rec->{ether},0,6);
    get_field("ether_info","info","ea='$t'","card_info",$rec);
  }
  $rec->{card_info}='&nbsp;' if ($rec->{card_info} eq '');

  if ($rec->{ether_alias} > 0) {
    get_field("hosts","domain","id=$rec->{ether_alias}",
	      'ether_alias_info',$rec);
  }
  #$rec->{ether_alias_info}='' unless ($rec->{ether_alias_info});

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
  } elsif ($rec->{type} == 7) {
    get_array_field("hosts h, arec_entries a ",4,"a.id,h.id,h.domain,h.type",
		    "Domain",
	          "a.host=$id AND a.arec=h.id ORDER BY h.domain",
		    $rec,'alias_a');
  }


  db_query("SELECT z.serial_date FROM hosts h, zones z " .
	   "WHERE h.zone=z.id AND h.id=$id;",\@q);

  if ($rec->{cdate} > 0) {
    $rec->{cdate_str}=localtime($rec->{cdate}).' by '.$rec->{cuser};
    $rec->{cdate_str} .= "<FONT color=\"#ff0000\"> (PENDING)</FONT>"
      if ($q[0][0] < $rec->{cdate});
  } else {
    $rec->{mdate_str}='UNKNOWN';
  }

  if ($rec->{mdate} > 0) {
    $rec->{mdate_str}=localtime($rec->{mdate}).' by '.$rec->{muser};
    $rec->{mdate_str} .= "<FONT color=\"#ff0000\"> (PENDING)</FONT>"
      if ($q[0][0] < $rec->{mdate});
  } else {
    $rec->{mdate_str}='';
  }

  if ($rec->{dhcp_info}) {
    $infostr=' (' . $rec->{dhcp_info} . ')';
  }
  $rec->{dhcp_date_str}=($rec->{dhcp_date} > 0 ?
			 localtime($rec->{dhcp_date}) . $infostr : '');

  return 0;
}


sub update_host($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);
  delete $rec->{card_info};
  delete $rec->{ether_alias_info};
  delete $rec->{wks_rec};
  delete $rec->{mx_rec};
  delete $rec->{grp_rec};
  delete $rec->{alias_l};
  delete $rec->{alias_d};
  delete $rec->{dhcp_date};
  delete $rec->{dhcp_info};
  delete $rec->{dhcp_date_str};

  $rec->{domain}=lc($rec->{domain}) if (defined $rec->{domain});

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
  $r=update_array_field("srv_entries",6,
			"pri,weight,port,target,comment,type,ref",
			'srv_l',$rec,"1,$id");
  if ($r < 0) { db_rollback(); return -18; }

  $r=update_array_field("a_entries",4,"ip,reverse,forward,host",
			'ip',$rec,"$id");
  if ($r < 0) { db_rollback(); return -20; }

  if ($rec->{type}==7) {
    $r=update_array_field("arec_entries",2,"arec,host",
			  'alias_a',$rec,"$id");
    if ($r < 0) { db_rollback(); return -21; }
  }

  return db_commit();
}

sub delete_host($) {
  my($id) = @_;
  my($res,%host);

  return -100 unless ($id > 0);
  return -101 if (get_host($id,\%host) < 0);

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

  # a_entries
  $res=db_exec("DELETE FROM a_entries WHERE host=$id;");
  if ($res < 0) { db_rollback(); return -7; }

  # arec_entries
  $res=db_exec("DELETE FROM arec_entries WHERE host=$id OR arec=$id;");
  if ($res < 0) { db_rollback(); return -8; }

  # aliases
  $res=db_exec("DELETE FROM hosts WHERE type=4 AND alias=$id;");
  if ($res < 0) { db_rollback(); return -9; }

  # ether_aliases
  $res=db_exec("UPDATE hosts SET ether_alias=-1 WHERE ether_alias=$id;");
  if ($res < 0) { db_rollback(); return -10; }

  # srv_entries
  $res=db_exec("DELETE FROM srv_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -11; }

  $res=db_exec("DELETE FROM hosts WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -50; }


  if ($host{zone} > 0) {
    my $t=time();
    $res=db_exec("UPDATE zones SET rdate=$t WHERE id=$host{zone}");
    if ($res < 0) { db_rollback(); return -99; }
  }

  return db_commit();
}

sub add_host($) {
  my($rec) = @_;
  my($res,$i,$id,$a_id);

  return -100 unless ($rec->{zone} > 0);
  db_begin();
  if ($rec->{type}==7) {
    $a_id=$rec->{alias};
    delete $rec->{alias};
  }
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $rec->{domain}=lc($rec->{domain});
  $res=add_record('hosts',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # IPs
  $res = add_array_field('a_entries','ip,reverse,forward','ip',$rec,
			 'host',"$id");
  if ($res < 0) { db_rollback(); return -2; }

  # MXs
  $res = add_array_field('mx_entries','pri,mx,comment','mx_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -3; }

  # NSs
  $res = add_array_field('ns_entries','ns,comment','ns_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -4; }

  # PRINTERs
  $res = add_array_field('printer_entries','printer,comment','printer_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -5; }

  # SRVs
  $res = add_array_field('srv_entries','pri,weight,port,target,comment',
			 'srv_l',$rec,'type,ref',"1,$id");
  if ($res < 0) { db_rollback(); return -6; }

  # ARECs
  if ($rec->{type}==7) {
    $res=db_exec("INSERT INTO arec_entries (host,arec) VALUES($id,$a_id);");
    if ($res < 0) { db_rollback(); return -7; }
  }

  return -10 if (db_commit() < 0);
  return $id;
}


############################################################################
# MX template functions

sub get_mx_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("mx_templates",
			     "name,comment,cdate,cuser,mdate,muser,alevel",
			     $id,$rec,"id"));

  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comment",
		  "type=3 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');

  add_std_fields($rec);
  return 0;
}

sub update_mx_template($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

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

  my($res,$id);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('mx_templates',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # mx_entries
  $res=add_array_field('mx_entries','pri,mx,comment','mx_l',$rec,
		       'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -3; }

  return -10 if (db_commit() < 0);
  return $id;
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


  $res=db_exec("UPDATE hosts SET mx=-1 WHERE mx=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}


sub get_mx_template_list($$$$) {
  my($zoneid,$rec,$lst,$alevel) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($zoneid < 1);
  $alevel=0 unless ($alevel>0);

  db_query("SELECT id,name FROM mx_templates " .
	   "WHERE zone=$zoneid AND alevel <= $alevel ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

############################################################################
# WKS template functions

sub get_wks_template($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("wks_templates",
			     "name,comment,cuser,cdate,muser,mdate,alevel",
			     $id,$rec,"id"));

  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comment",
		  "type=2 AND ref=$id ORDER BY proto,services",$rec,'wks_l');

  add_std_fields($rec);
  return 0;
}

sub update_wks_template($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

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

  my($res,$id,$i);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('wks_templates',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # wks entries
  $res = add_array_field('wks_entries','proto,services,comment','wks_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { db_rollback(); return -3; }

  return -10 if (db_commit() < 0);
  return $id;
}


sub delete_wks_template($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE type=2 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM wks_templates WHERE id=$id");
  if ($res < 0) { db_rollback(); return -2; }


  $res=db_exec("UPDATE hosts SET wks=-1 WHERE wks=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_wks_template_list($$$$) {
  my($serverid,$rec,$lst,$alevel) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($serverid < 1);
  $alevel=0 unless ($alevel > 0);

  db_query("SELECT id,name FROM wks_templates " .
	   "WHERE server=$serverid AND alevel <= $alevel ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

############################################################################
# PRINTER class functions

sub get_printer_class($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("printer_classes",
			     "name,comment,cuser,cdate,muser,mdate",
			     $id,$rec,"id"));

  get_array_field("printer_entries",3,"id,printer,comment",
		  "Printer,Comment",
		  "type=3 AND ref=$id ORDER BY printer",$rec,'printer_l');

  add_std_fields($rec);
  return 0;
}

sub update_printer_class($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

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

  my($res,$id);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('printer_classes',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # printer entries
  $res = add_array_field('printer_entries','printer,comment','printer_l',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -2; }

  return -10 if (db_commit() < 0);
  return $id;
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

  return -100 if (get_record("hinfo_templates",
			     "hinfo,type,pri,cdate,cuser,mdate,muser",
			     $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}

sub update_hinfo_template($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('hinfo_templates',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  return db_commit();
}

sub add_hinfo_template($) {
  my($rec) = @_;

  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
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

sub get_group_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return -1 unless ($serverid > 0);
  db_query("SELECT id FROM groups WHERE server=$serverid AND name='$name'",
	   \@q);
  return -2 unless (@q > 0);
  return ($q[0][0]);
}

sub get_group($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("groups",
			     "name,comment,cdate,cuser,mdate,muser," .
			     "type,alevel,vmps",
			     $id,$rec,"id"));

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=5 AND ref=$id ORDER BY id",$rec,'dhcp');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=1 AND ref=$id ORDER BY printer",$rec,'printer');

  add_std_fields($rec);
  return 0;
}

sub update_group($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

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
  my($res,$id,$i);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('groups',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # dhcp_entries
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"5,$id");
  if ($res < 0) { db_rollback(); return -3; }

  # printer_entries
  $res = add_array_field('printer_entries','printer,comment','printer',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { db_rollback(); return -4; }

  return -10 if (db_commit() < 0);
  return $id;

}


sub delete_group($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=5 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }
  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=1 AND ref=$id");
  if ($res < 0) { db_rollback(); return -2; }

  $res=db_exec("DELETE FROM groups WHERE id=$id");
  if ($res < 0) { db_rollback(); return -3; }


  $res=db_exec("UPDATE hosts SET grp=-1 WHERE grp=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_group_list($$$$) {
  my($serverid,$rec,$lst,$alevel) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($serverid < 1);
  $alevel=0 unless ($alevel > 0);

  db_query("SELECT id,name FROM groups " .
	   "WHERE server=$serverid AND alevel <= $alevel AND type < 100 " .
	   "ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}


############################################################################
# user functions

sub get_user($$) {
  my ($uname,$rec) = @_;
  my ($res);

  $res = get_record("users",
	       "username,password,name,superuser,server,zone,comment,".
	       "email,flags,expiration,last,last_pwd,id,cdate,cuser,".
	       "mdate,muser",
	       $uname,$rec,"username");

  fix_bools($rec,"superuser");
  $rec->{email_notify} = ($rec->{flags} & 0x01 ? 1 : 0);

  add_std_fields($rec);
  return $res;
}

sub update_user($) {
  my($rec) = @_;

  del_std_fields($rec);

  $rec->{flags}=0;
  $rec->{flags}|=0x01 if ($rec->{email_notify});
  delete $rec->{email_notify};

  return update_record('users',$rec);
}

sub add_user($) {
  my($rec) = @_;

  $rec->{cuser}=$muser;
  $rec->{cdate}=time;

  $rec->{flags}=0;
  $rec->{flags}|=0x01 if ($rec->{email_notify});
  delete $rec->{email_notify};

  return add_record('users',$rec);
}

sub delete_user($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # user_rights
  $res=db_exec("DELETE FROM user_rights WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }
  # utmp
  $res=db_exec("DELETE FROM utmp WHERE uid=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  $res=db_exec("DELETE FROM users WHERE id=$id;");
  if ($res < 0) { db_rollback(); return -3; }

  return db_commit();
}

sub get_user_group_id($) {
  my($group)=@_;
  my(@q);

  db_query("SELECT id FROM user_groups WHERE name='$group'",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

sub get_user_group($$) {
  my ($id,$rec) = @_;
  my ($res);

  $res = get_record("user_groups","name,comment",
		    $id,$rec,"id");

  return $res;
}

sub delete_user_group($$) {
  my ($id,$newid) = @_;
  my ($res);

  db_begin();

  $res = db_exec("DELETE FROM user_rights WHERE type=1 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }
  $res = db_exec("DELETE FROM user_groups WHERE id=$id");
  if ($res < 0) { db_rollback(); return -2; }

  if ($newid > 0) {
    $res = db_exec("UPDATE user_rights SET rref=$newid " .
		   "WHERE type=2 AND rtype=0 AND rref=$id");
    if ($res < 0) { db_rollback(); return -3; }
  } else {
    $res = db_exec("DELETE FROM user_rights ".
		   "WHERE type=2 AND rtype=0 AND rref=$id");
    if ($res < 0) { db_rollback(); return -4; }
  }

  return db_commit();
}

############################################################################
# nets functions

sub get_net_by_cidr($$) {
  my($serverid,$cidr) = @_;
  my(@q);

  return -100 unless ($serverid > 0);
  return -101 unless (is_cidr($cidr));
  db_query("SELECT id FROM nets WHERE server=$serverid AND net='$cidr'",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}


sub get_net_list($$) {
  my ($serverid,$subnets) = @_;
  my (@q,$list,$i);

  if ($subnets) {
    $subnets=($subnets==0?'false':'true');
    $subnets=" AND subnet=$subnets ";
  } else {
    $subnets='';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  db_query("SELECT net,id,name FROM nets " .
	   "WHERE server=$serverid $subnets ORDER BY net",\@q);

  for $i (0..$#q) {
    push @{$list}, [ $q[$i][0], $q[$i][1], $q[$i][2] ];
  }
  return $list;
}

sub get_net($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("nets",
                      "server,name,net,subnet,rp_mbox,rp_txt,no_dhcp,comment,".
		      "range_start,range_end,vlan,cdate,cuser,mdate,muser,".
                      "netname,alevel,type", $id,$rec,"id"));

  fix_bools($rec,"subnet,no_dhcp");
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=4 AND ref=$id ORDER BY id",$rec,'dhcp_l');

  $rec->{private_flag} = ($rec->{type} & 0x01 ? 1 : 0);
  add_std_fields($rec);
  return 0;
}

sub update_net($) {
  my($rec) = @_;
  my($r,$id,$net);

  return -100 unless (is_cidr($rec->{net}));
  $net = new Net::Netmask($rec->{net});
  return -101 unless ($net);
  if (is_cidr($rec->{range_start})) {
    return -102 unless ($net->match($rec->{range_start}));
  }
  if (is_cidr($rec->{range_end})) {
    return -102 unless ($net->match($rec->{range_end}));
  }

  del_std_fields($rec);
  $rec->{type}=0;
  $rec->{type}|=0x01 if ($rec->{private_flag});
  delete $rec->{private_flag};

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
  my($res,$id,$i);
  my($net);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  return -100 unless (is_cidr($rec->{net}));
  $net = new Net::Netmask($rec->{net});
  return -101 unless ($net);
  $rec->{range_start}=$net->nth(1)
    unless (is_cidr($rec->{range_start}));
  $rec->{range_end}=$net->nth(-2)
    unless (is_cidr($rec->{range_end}));

  $res = add_record('nets',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # dhcp_entries
  for $i (0..$#{$rec->{dhcp_l}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(4,$id,'$rec->{dhcp_l}[$i][1]')");
    if ($res < 0) { db_rollback(); return -3; }
  }

  return -10 if (db_commit() < 0);
  return $id;
}


sub delete_net($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=4 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM nets WHERE id=$id");
  if ($res < 0) { db_rollback(); return -2; }


  $res=db_exec("DELETE FROM user_rights WHERE rtype=3 AND rref=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

############################################################################
# VLAN functions

sub get_vlan($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("vlans",
                      "server,name,description,comment,vlanno,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=6 AND ref=$id ORDER BY id",$rec,'dhcp_l');

  add_std_fields($rec);
  return 0;
}


sub update_vlan($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('vlans',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l',$rec,"6,$id");
  if ($r < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub add_vlan($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('vlans',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # dhcp_entries
  for $i (0..$#{$rec->{dhcp_l}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(6,$id,'$rec->{dhcp_l}[$i][1]')");
    if ($res < 0) { db_rollback(); return -3; }
  }

  return -10 if (db_commit() < 0);
  return $id;
}

sub delete_vlan($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=6 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM vlans WHERE id=$id");
  if ($res < 0) { db_rollback(); return -2; }


  $res=db_exec("UPDATE nets SET vlan=-1 WHERE vlan=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_vlan_list($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($serverid < 1);

  db_query("SELECT id,name FROM vlans " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

sub get_vlan_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return -100 unless ($serverid > 0);
  return -101 unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM vlans WHERE server=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

############################################################################
# VMPS functions

sub get_vmps_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return -1 unless ($serverid > 0);
  db_query("SELECT id FROM vmps WHERE server=$serverid AND name='$name'",\@q);
  return -2 unless (@q > 0);
  return ($q[0][0]);
}

sub get_vmps($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("vmps",
                      "server,name,description,comment,".
		      "mode,nodomainreq,fallback,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}


sub update_vmps($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('vmps',$rec);
  if ($r < 0) { db_rollback(); return $r; }

  return db_commit();
}

sub add_vmps($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('vmps',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  return -10 if (db_commit() < 0);
  return $id;
}

sub delete_vmps($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM vmps WHERE id=$id");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("UPDATE hosts SET vmps=-1 WHERE vmps=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_vmps_list($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($serverid < 1);

  db_query("SELECT id,name FROM vmps " .
	   "WHERE server=$serverid ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}


############################################################################
# news functions

sub add_news($) {
  my($rec) = @_;

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  return add_record('news',$rec);
}

sub get_news_list($$$) {
  my($serverid,$count,$list) = @_;
  my(@q);

  $count=5 unless ($count > 0);
  db_query("SELECT cdate,cuser,server,info FROM news " .
	   "WHERE (server=-1 OR server=$serverid) " .
	   "ORDER BY -cdate LIMIT $count;",$list);
  return 0;
}


#######################################################


sub get_who_list($$) {
  my($lst,$timeout) = @_;
  my(@q,$i,$j,$login,$last,$idle,$t,$s,$m,$h,$midle,$ip,$login_s);

  $t=time;
  db_query("SELECT u.username,u.name,a.addr,a.login,a.last " .
	   "FROM users u, utmp a " .
	   "WHERE a.uid=u.id ORDER BY u.username",\@q);

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

sub get_permissions($$) {
  my($uid,$rec) = @_;
  my(@q,$i,$type,$ref,$mode,$s,$e,$sql);

  return -1 unless ($uid > 0);
  return -2 unless ($rec);

  $rec->{server}={};
  $rec->{zone}={};
  $rec->{net}={};
  $rec->{hostname}=[];
  $rec->{ipmask}=[];
  $rec->{tmplmask}=[];
  $rec->{grpmask}=[];
  $rec->{delmask}=[];
  $rec->{rhf}={};
  $rec->{flags}={};
  $rec->{alevel}=0;

  undef @q;
  $sql = "SELECT a.rtype,a.rref,a.rule,n.range_start,n.range_end " .
	 "FROM user_rights a, nets n " .
	 "WHERE ((a.type=2 AND a.ref=$uid) OR (a.type=1 AND a.ref IN (SELECT rref FROM user_rights WHERE type=2 AND ref=$uid AND rtype=0))) " .
           "  AND a.rtype=3 AND a.rref=n.id " .
	   "UNION " .
	   "SELECT rtype,rref,rule,NULL,NULL FROM user_rights " .
	   "WHERE ((ref=$uid AND type=2) OR (type=1 AND ref IN (SELECT rref FROM user_rights WHERE type=2 AND ref=$uid AND rtype=0))) " .
	   " AND rtype<>3 ORDER BY 1;";
  db_query($sql,\@q);
  #print "<p>$sql\n";

  for $i (0..$#q) {
    $type=$q[$i][0];
    $ref=$q[$i][1];
    $mode=$q[$i][2];
    $s=$q[$i][3];
    $e=$q[$i][4];
    $mode =~ s/\s+$//;
    #print "<p> type=$type ref=$ref rule=$mode [$s,$e]\n";

    if ($type == 1) { $rec->{server}->{$ref}=$mode; }
    elsif ($type == 2) { $rec->{zone}->{$ref}=$mode; }
    elsif ($type == 3) { $rec->{net}->{$ref}=[$s,$e]; }
    elsif ($type == 4) { push @{$rec->{hostname}}, $mode; }
    elsif ($type == 5) { push @{$rec->{ipmask}}, $mode; }
    elsif ($type == 6) { $rec->{alevel}=$mode if ($rec->{alevel} < $mode); }
    elsif ($type == 7) { $rec->{elimit}=$mode; }
    elsif ($type == 8) { $rec->{defdept}=$mode; }
    elsif ($type == 9) { push @{$rec->{tmplmask}}, $mode; }
    elsif ($type == 10) { push @{$rec->{grpmask}}, $mode; }
    elsif ($type == 11) { push @{$rec->{delmask}}, $mode; }
    elsif ($type == 12) { $rec->{rhf}->{$mode}=$ref; }
    elsif ($type == 13) { $rec->{flags}->{$mode}=1; }
  }

  return 0;
}


sub update_lastlog($$$$$) {
  my($uid,$sid,$type,$ip,$host) = @_;
  my($date,$i,$h,$ldate);

  return -1 unless ($uid > 0);
  return -2 unless ($sid > 0);
  return -3 unless ($type > 0);

  if ($type == 1) {
    $date=time;
    $i=db_encode_str($ip);
    $h=db_encode_str($host);
    return -10 if (db_exec("INSERT INTO lastlog " .
			   "(sid,uid,date,state,ip,host) " .
			   " VALUES($sid,$uid,$date,1,$i,$h);") < 0);
  } else {
    $ldate=time;
    return -10 if (db_exec("UPDATE lastlog SET ldate=$ldate,state=$type " .
			   "WHERE sid=$sid;") < 0);
  }
  return 0;
}

sub update_history($$$$$$) {
  my($uid,$sid,$type,$action,$info,$ref) = @_;
  my($date,$a,$i,$sql);

  return -1 unless ($uid > 0);
  return -2 unless ($sid > 0);
  return -3 unless ($type > 0);
  $date=time;
  $a=db_encode_str($action);
  $i=db_encode_str($info);
  $ref='NULL' unless ($ref > 0);

  $sql = "INSERT INTO history (sid,uid,date,type,action,info,ref) " .
         " VALUES($sid,$uid,$date,$type,$a,$i,$ref);";
  return -10 if (db_exec($sql)<0);

  return 0;
}


sub fix_utmp($) {
  my($timeout) = @_;
  my($i,$t,@q);

  $t=time - $timeout;
  db_query("SELECT cookie,uid,sid FROM utmp WHERE last < $t;",\@q);
  if (@q > 0) {
    for $i (0..$#q) {
      update_lastlog($q[$i][1],$q[$i][2],3,'','');
      db_exec("DELETE FROM utmp WHERE cookie='$q[$i][0]';");
    }
  }
}


sub get_lastlog($$$) {
  my($n,$user,$list) = @_;
  my(@q,$count_rule,$user_rule,$count,$i,$t,$j,$l,$state,$host,$info,$hr,$mn,
     $sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);

  $count_rule = ($n>0 ? " LIMIT $n " : "");
  $user_rule=($user ? " AND u.username='$user' " : "");

  db_query("SELECT l.sid,l.uid,l.date,l.state,l.ldate,l.ip,l.host,u.username ".
           "FROM lastlog l, users u " .
           "WHERE u.id=l.uid " .$user_rule .
           "ORDER BY -l.sid " . $count_rule . ";",\@q);
  $count=@q;

  for $i (0..($count-1)) {
     $j=$count-$i-1;
     ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
       = localtime($q[$j][2]);
     $t=sprintf("%02d/%02d/%02d %02d:%02d",$mday,$mon+1,$year%100,$hour,$min);
     $host=substr($q[$j][6],0,15);
     $state=$q[$j][3];
     if ($state < 2) {
       $info="still logged in";
     } else {
       ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
	 localtime($q[$j][4]);
       $l=($q[$j][4] - $q[$j][2]) / 60;
       $hr=$l / 60;
       $mn=$l % 60;
       $info=sprintf("%02d:%02d (%d:%02d)",$hour,$min,$hr,$mn);
       $info.=" (reconnect) " if ($state == 4);
       $info.=" (autologout)" if ($state == 3);
     }
     push @{$list}, [$q[$j][7],$q[$j][0],$host,$t,$info];
  }

  return $count;
}

sub get_history_host($$)
{
  my ($id,$list) = @_;
  my (@q,%users,$i);

  return -1 unless ($id > 0);
  db_query("SELECT date,action,info,uid FROM history ".
	   "WHERE type=1 AND ref=$id ORDER BY date ",$list);
  db_query("SELECT id,username FROM users",\@q);
  for $i (0..$#q) { $users{$q[$i][0]}=$q[$i][1]; }
  for $i (0..$#{$list}) {
    $$list[$i][3] = $users{$$list[$i][3]} if ($users{$$list[$i][3]});
  }
  return 0;
}

sub get_history_session($$)
{
  my ($id,$list) = @_;
  my (@q,%users,$i);

  return -1 unless ($id > 0);
  db_query("SELECT date,type,ref,action,info FROM history ".
	   "WHERE sid=$id ORDER BY date ",$list);

  return 0;
}

1;
# eof

