# Sauron::BackEnd.pm  -- Sauron back-end routines
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2000-2005.
# $Id:$
#
package Sauron::BackEnd;
require Exporter;
# use Net::Netmask;
use NetAddr::IP; # For IPv6;
use Sauron::DB;
use Sauron::Util;
use Sys::Syslog qw(:DEFAULT setlogsock);
Sys::Syslog::setlogsock('unix');
use Net::IP qw (:PROC);

use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

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
	     get_zone_list2
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
	     get_host_types

	     get_mx_template_by_name
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
             get_group_type_by_name
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
             get_user_status

	     get_net_by_cidr
             get_net_cidr_by_ip
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
             get_vlanno
	     get_vlan_by_name

             ip_policy_names
             get_net_ip_policy
             get_free_ip_by_net
	     get_ip_sugg

	     get_vmps_by_name
	     get_vmps
	     update_vmps
	     add_vmps
	     delete_vmps
	     get_vmps_list

	     get_key
	     update_key
	     add_key
	     delete_key
	     get_key_list
	     get_key_by_name

	     get_acl
	     update_acl
	     add_acl
	     delete_acl
	     get_acl_list
	     get_acl_by_name

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

	     save_state
	     load_state
	     remove_state
	    );


my($muser);



sub write2log
{
  #my $priority  = shift;
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", "$msg");
  Sys::Syslog::closelog();
} # End of write2log


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
  return "1.7"; # required db format version for this backend
}

sub set_muser($) {
  my($usr)=@_;
  $muser=$usr;
}


sub get_db_version() {
  my(@q);
  db_query("SELECT value FROM settings WHERE setting='dbversion';",\@q);
  return ($q[0][0] =~ /^\d/ ? $q[0][0] : 'ERROR');
}


sub auto_address($$) {
  my($serverid,$net) = @_;
  my(@q,$s,$e,$i,$j,%h, $family);

  return 'Invalid server id'  unless ($serverid > 0);
  return 'Invalid net'  unless (is_cidr($net));
  return 'Invalid ip ' unless ($family = new Net::IP($net)->version());

  db_query("SELECT net,range_start,range_end FROM nets " .
	   "WHERE server=$serverid AND net = '$net';",\@q);
  return "No auto address range defined for this net: $net ".
         "($q[0][0],$q[0][1],$q[0][2]) "
	   unless (is_cidr($q[0][1]) && is_cidr($q[0][2]));


  my $rangeIP = new Net::IP($q[0][1] . " - " . $q[0][2]) or return 'Invalid auto address range';

  undef @q;
  db_query("SELECT a.ip FROM hosts h, a_entries a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND '$net' >> a.ip ORDER BY a.ip;",\@q);

  my @usedIP;
  push @usedIP, $_ foreach @q;

  #Nasty use ip_compress_address due $ip->short() bug in IPv4
  do{
	#skip IPv4 broadcast address
	{
        	last  if $family == 4 and $rangeIP->ip() eq $rangeIP->last_ip();
	}
	return ip_compress_address($rangeIP->ip(), $family)
	unless ( grep {$_->[0] eq ip_compress_address($rangeIP->ip(), $family)} @usedIP ) ;
  } while (++$rangeIP);


  return "No free addresses left";
}

sub next_free_ip($$)
{
  my($serverid,$ip) = @_;
  my(@q,@ips,%h,$net,$i,$t, $family);

  return '' unless ($serverid > 0);
  return '' unless (is_cidr($ip));
  return '' unless ($family = ip_get_version($ip));

  #First IP is network address
  #my $firstIPshift = 1;
  #UWB Pilsen has first IP ::1:0/112 => + 2^16 hosts
  #Need global config
  #$firstIPshift += 2 ** 16 if $family == 6;

  db_query("SELECT net FROM nets WHERE server=$serverid AND net >> '$ip' " .
	   "ORDER BY masklen(net) DESC LIMIT 1",\@q);
  return '' unless (@q > 0);
  db_query("SELECT a.ip FROM hosts h , a_entries a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND '$q[0][0]' >> a.ip ORDER BY a.ip;",\@ips);

  my $rangeIP = new Net::IP($q[0][0]) or return '';
  my $m_ip = new Net::IP($ip) or return '';

  my @usedIP;
  push @usedIP, $_ foreach @ips;

  #Skip network address + firstIPshift :]
  #$rangeIP += $firstIPshift;
  $rangeIP += ($m_ip->intip() - $rangeIP->intip() + 1);

  #Nasty use ip_compress_address due $ip->short() bug in IPv4
  do{
	#skip IPv4 broadcast address
	{
  		last if $family == 4 and $rangeIP->ip() eq $rangeIP->last_ip();
	}
	return ip_compress_address($rangeIP->ip(), $family)
	unless ( grep {$_->[0] eq ip_compress_address($rangeIP->ip(), $family)} @usedIP ) ;
  } while (++$rangeIP);

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
#	   "WHERE h.zone=$zoneid AND domain ~* '^$domain(\\\\.|\$)';",\@q);
	   "WHERE h.zone=$zoneid AND domain ~* " . db_encode_str("^$domain(\\.|\$)") . ";",\@q);
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
  $rec->{ip}=$ip; # IP

  db_query("SELECT n.id, n.name, n.net, v.vlanno, v.name " .
	   "FROM nets n left join vlans v on v.server = $serverid and n.vlan = v.id " .
	   "WHERE n.server = $serverid AND n.dummy = false AND '$ip' << n.net " .
	   "ORDER BY n.subnet, n.net",\@q);
  return -2 unless (@q > 0);
  return -3 unless ($q[$#q][0] > 0);
  $net = $q[$#q][2];

#  $tmp = new Net::Netmask($net);
#  $rec->{net}=$tmp->desc();
#  $rec->{base}=$tmp->base();
#  $rec->{mask}=$tmp->mask();
#  $rec->{broadcast}=$tmp->broadcast();

  $tmp = new Net::IP($net);
  $rec->{net} = $tmp->short();
  $rec->{base} = ipv6compress($tmp->ip()) . '/' . $tmp->prefixlen(); # Network address
  $rec->{mask} = $tmp->mask();                                       # Netmask
  $rec->{broadcast} = $ip =~ /\./ ? $tmp->last_ip() : '';            # Broadcast address (IPV4 only)

  $rec->{netname} = $q[$#q][1];
  $rec->{vlan} = '';
  $rec->{vlan} = $q[$#q][4] if ($q[$#q][4]);
  $rec->{vlan} .= " ($q[$#q][3])" if ($q[$#q][3]);

  undef @q;
  db_query("SELECT a.ip FROM hosts h, a_entries a " .
	   "WHERE a.host=h.id AND h.router>0 AND a.ip << '$net' " .
	   "ORDER BY 1",\@q);
  if (@q > 0) {
    $rec->{gateway}=$q[0][0]; # Gateway (default)
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

  db_query("SELECT $fields FROM $table WHERE $keyname=".db_encode_str($key),
	   \@q);
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

sub get_aml_field($$$$$) {
    my($serverid,$type,$ref,$rec,$keyname) = @_;
    my(@list,$i,$l);

    db_query("SELECT c.id,c.mode,c.ip,c.acl,c.tkey,c.op,c.comment,".
	     " 0,a.name,k.name ".
	     "FROM cidr_entries c LEFT JOIN acls a ON c.acl=a.id " .
	     "LEFT JOIN keys k ON c.tkey=k.id " .
	     "WHERE c.type=$type AND c.ref=$ref ORDER by c.id",\@list);
    $l=[];
    push @{$l}, [ 'aml', $serverid ];
    for $i (0..$#list) { push @{$l}, $list[$i]; }
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
  return 0 unless (\$list);

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

sub update_aml_field($$$$) {
    my($type,$ref,$rec,$keyname) = @_;
    return update_array_field("cidr_entries",7,
			      "mode,ip,acl,tkey,op,comment,type,ref",
			      $keyname,$rec,"$type,$ref");
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
    next if ($key eq 'zentries_id');
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
  $sqlstr =~ s/hacked_id/id/; # Dirty hack to force an id into the database.

  write2log($sqlstr);

  return $sqlstr;
}

sub add_record($$) {
  my($table,$rec) = @_;
  my($sqlstr,$res,$oid,@q);
  my $flag; # ** 2018-09-25 TVu

  return -130 unless ($table);
  return -131 unless ($rec);

  $sqlstr=add_record_sql($table,$rec);
  return -132 if ($sqlstr eq '');

# If $table has column id, return its value after insert.
  db_query("select column_name from information_schema.columns " . # ** 2018-09-25 TVu
	   "where table_name = '$table' and column_name = 'id'", \@q);
  if (@q) {
      $sqlstr .= ' returning id';
      $flag = 1;
  } else {
      $flag = 0;
  }

  #print "sql '$sqlstr'\n";
  $res=db_exec($sqlstr);
  return -1 if ($res < 0);

# $oid=db_lastoid(); ** Getting rid of OIDs 2018-09-25 TVu
# db_query("SELECT id FROM $table WHERE OID=$oid",\@q);
# return -2 if (@q < 1);
# return $q[0][0];

  return $flag ? db_lastid() : -2; # ** Added 2018-09-25 TVu
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

# This sub inserts / updates / deletes database rows, which were previously
# displayed / edited as indexed text fields, but are now a single textarea.
# Newly inserted / updated text is stored as a single row,
# but old entries still consist of multiple rows.
sub update_textarea_field($$$$$$) { # Textarea 12 Apr 2017 TVu
    my($table, $id, $fields, $keyname, $rec, $vals) = @_;

    my($ind1, $sql, $field, @ids);

    return -128 unless ($table);
    return -1 unless (ref($rec) eq 'HASH');

# Delete old row(s), if any,
    @ids = split(/,/, $id);
    $sql = '';
    for $ind1 (@ids) {
	$sql .= "id = $ind1 or ";
    }
    if ($sql) {
	$sql =~ s/ or $//;
	$sql = "delete from $table where $sql;";
	return -5 if (db_exec($sql) < 0);
    }

# Insert new row unless the textarea is empty. Use first old id, if any.
    my @arr;
    for my $ind1 (1..$#{$$rec{$keyname}}) {
	push(@arr, $$rec{$keyname}->[$ind1]->[1]);
    }
    $field = join("\n", @arr);
    if (!$field) { return 0; }
    $sql = "insert into $table (" . ($ids[0] ? 'id,' : '') .
	" $fields) values (" . ($ids[0] ? "$ids[0]," : '') .
	" " . db_encode_str($field) . ", $vals);";
    return -7 if (db_exec($sql) < 0);

    return 0;
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
		    "cdate,cuser,mdate,muser,lastrun," .
		    "df_port6,df_max_delay6,df_max_uupdates6,df_mclt6,df_split6,".
		    "df_loadbalmax6,dhcp_flags,".
            "listen_on_port_v6,transfer_source_v6,query_src_ip_v6,query_src_port_v6",
		    $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"no_roots,zones_only");

  get_aml_field($id,1,$id,$rec,'allow_transfer');
  get_aml_field($id,7,$id,$rec,'allow_query');
  get_aml_field($id,8,$id,$rec,'allow_recursion');
  get_aml_field($id,9,$id,$rec,'blackhole');
  get_aml_field($id,10,$id,$rec,'listen_on');
  get_aml_field($id,16,$id,$rec,'listen_on_v6');

  #get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
  #		  "type=10 AND ref=$id ORDER BY ip",$rec,'listen_on');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=11 AND ref=$id ORDER BY ip",$rec,'forwarders');
# Local DHCP settings 2020-07-20 TVu
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=7 AND ref=$id ORDER BY id",$rec,'dhcp_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=1 AND ref=$id ORDER BY id",$rec,'dhcp');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=3 AND ref=$id ORDER BY id",$rec,'txt');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=10 AND ref=$id ORDER BY id",$rec,'logging');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=11 AND ref=$id ORDER BY id",$rec,'custom_opts');
  get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		  "type=13 AND ref=$id ORDER BY id",$rec,'bind_globals');
# Local DHCP settings 2020-07-20 TVu
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP6,Comments",
		  "type=17 AND ref=$id ORDER BY id",$rec,'dhcp6_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP6,Comments",
		  "type=11 AND ref=$id ORDER BY id",$rec,'dhcp6');

  get_aml_field($id,14,$id,$rec,'allow_query_cache');
  get_aml_field($id,15,$id,$rec,'allow_notify');

  $rec->{dhcp_flags_ad}=($rec->{dhcp_flags} & 0x01 ? 1 : 0);
  $rec->{dhcp_flags_fo}=($rec->{dhcp_flags} & 0x02 ? 1 : 0);
  $rec->{named_flags_ac}=($rec->{named_flags} & 0x01 ? 1 : 0);
  $rec->{named_flags_isz}=($rec->{named_flags} & 0x02 ? 1 : 0);
  $rec->{named_flags_hinfo}=($rec->{named_flags} & 0x04 ? 1 : 0);
  $rec->{named_flags_wks}=($rec->{named_flags} & 0x08 ? 1 : 0);

  $rec->{dhcp_flags_ad6}=($rec->{dhcp_flags6} & 0x01 ? 1 : 0);
  $rec->{dhcp_flags_fo6}=($rec->{dhcp_flags6} & 0x02 ? 1 : 0);

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
  delete $rec->{dhcp_flags6};
  delete $rec->{server_type};

  $rec->{dhcp_flags}=0;
  $rec->{dhcp_flags}|=0x01 if ($rec->{dhcp_flags_ad});
  $rec->{dhcp_flags}|=0x02 if ($rec->{dhcp_flags_fo});
  delete $rec->{dhcp_flags_ad};
  delete $rec->{dhcp_flags_fo};

  $rec->{dhcp_flags6}=0;
  $rec->{dhcp_flags6}|=0x01 if ($rec->{dhcp_flags_ad6});
  $rec->{dhcp_flags6}|=0x02 if ($rec->{dhcp_flags_fo6});
  delete $rec->{dhcp_flags_ad6};
  delete $rec->{dhcp_flags_fo6};

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
  $r=update_aml_field(1,$id,$rec,'allow_transfer');
  if ($r < 0) { db_rollback(); return -12; }
  # dhcp
# Local DHCP settings 2020-07-20 TVu
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp_l',$rec,
		        "7,$id");
  if ($r < 0) { db_rollback(); return -13; }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp',$rec,
		        "1,$id");
  if ($r < 0) { db_rollback(); return -13; }
  # dhcp6
# Local DHCP settings 2020-07-20 TVu
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp6_l',$rec,
		        "17,$id");
  if ($r < 0) { db_rollback(); return -132; }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp6',$rec,
		        "11,$id");
  if ($r < 0) { db_rollback(); return -132; }
  # txt
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'txt',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -14; }
  # allow_query
  $r=update_aml_field(7,$id,$rec,'allow_query');
  if ($r < 0) { db_rollback(); return -15; }
  # allow_recursion
  $r=update_aml_field(8,$id,$rec,'allow_recursion');
  if ($r < 0) { db_rollback(); return -16; }
  # blackhole
  $r=update_aml_field(9,$id,$rec,'blackhole');
  if ($r < 0) { db_rollback(); return -17; }
  # listen_on
  $r=update_aml_field(10,$id,$rec,'listen_on');
  if ($r < 0) { db_rollback(); return -18; }
  #
  #$r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
  #  		'listen_on',$rec,"10,$id");
  #if ($r < 0) { db_rollback(); return -18; }
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
  # Globals (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'bind_globals',$rec,"13,$id");
  if ($r < 0) { db_rollback(); return -21; }

  # allow_query_cache
  $r=update_aml_field(14,$id,$rec,'allow_query_cache');
  if ($r < 0) { db_rollback(); return -22; }

  # allow_notify
  $r=update_aml_field(15,$id,$rec,'allow_notify');
  if ($r < 0) { db_rollback(); return -23; }

  # listen_on
  $r=update_aml_field(16,$id,$rec,'listen_on_v6');
  if ($r < 0) { db_rollback(); return -24; }


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
  $rec->{id}=$id=$res;

  # allow_transfer
  $res = update_aml_field(1,$id,$rec,'allow_transfer');
  if ($res < 0) { db_rollback(); return -10; }
  # dhcp
# Local DHCP settings 2020-07-20 TVu
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp_l',$rec,
			 'type,ref',"7,$id");
  if ($res < 0) { db_rollback(); return -11; }
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { db_rollback(); return -11; }
  # dhcp6
# Local DHCP settings 2020-07-20 TVu
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6_l',$rec,
			 'type,ref',"17,$id");
  if ($res < 0) { db_rollback(); return -11; }
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { db_rollback(); return -11; }
  # txt
  $res = add_array_field('txt_entries','txt,comment','txt',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -12; }
  # allow_query
  $res = update_aml_field(7,$id,$rec,'allow_query');
  if ($res < 0) { db_rollback(); return -13; }
  # allow_recursion
  $res = update_aml_field(8,$id,$rec,'allow_recursion');
  if ($res < 0) { db_rollback(); return -14; }
  # blackhole
  $res = update_aml_field(9,$id,$rec,'blackhole');
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
  # bind globals
  $res = add_array_field('txt_entries','txt,comment','bind_globals',$rec,
			 'type,ref',"13,$id");
  if ($res < 0) { db_rollback(); return -19; }

  # allow_query_cache
  $res = update_aml_field(14,$id,$rec,'allow_query_cache');
  if ($res < 0) { db_rollback(); return -20; }

  # allow_notify
  $res = update_aml_field(15,$id,$rec,'allow_notify');
  if ($res < 0) { db_rollback(); return -21; }


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
# Local DHCP settings 2020-07-20 TVu
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=7 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -3; }
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

# dhcp_entries6
# Local DHCP settings 2020-07-20 TVu
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=17 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -13; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=11 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -13; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, zones z " .
	        "WHERE z.server=$id AND a.type=12 AND a.ref=z.id);");
  if ($res < 0) { db_rollback(); return -14; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, zones z, hosts h " .
	        "WHERE z.server=$id AND h.zone=z.id AND a.type=13 " .
	        " AND a.ref=h.id);");
  if ($res < 0) { db_rollback(); return -15; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, nets n " .
	        "WHERE n.server=$id AND a.type=14 AND a.ref=n.id);");
  if ($res < 0) { db_rollback(); return -16; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, groups g " .
	        "WHERE g.server=$id AND a.type=15 AND a.ref=g.id);");
  if ($res < 0) { db_rollback(); return -17; }
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
	        "SELECT a.id FROM dhcp_entries a, vlans v " .
	        "WHERE v.server=$id AND a.type=16 AND a.ref=v.id);");
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

#	       "WHERE z.server=$id AND a.type=12 AND a.ref=z.id);");

	       "WHERE z.server=$id AND (a.type=4 OR a.type=12) AND a.ref=z.id);"); # 2020-07-30 TVu

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

  # group_entries
  $res=db_exec("DELETE FROM group_entries WHERE id IN ( " .
	       "SELECT a.id FROM group_entries a, zones z, hosts h " .
	       "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { db_rollback(); return -22; }

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

sub get_zone_list($$$$) {
  my ($serverid,$type,$reverse,$expired) = @_;
  my ($res,$list,$i,$id,$name,$rec);

  $type = ($type ? " AND type='$type' " : '');
  $reverse = ($reverse ? " AND reverse='$reverse' " : '');

  $list=[];
  return $list unless ($serverid >= 0);

  # 2022-08-10 mesrik: added expired skip
  if ($expired == 0) {
      db_query("SELECT name,id,type,reverse,comment,expiration FROM zones " .
	       "WHERE server=$serverid $type $reverse " .
	       "ORDER BY type,reverse,reversenet,name;",$list);
  } else {
      db_query("SELECT name,id,type,reverse,comment,expiration FROM zones " .
	       "WHERE server=$serverid $type $reverse " .
	       " AND (coalesce(expiration, 0) <= 0 OR coalesce(expiration, 0) > " .
	       " extract(epoch from now())) " . # Exclude expired zones
	       "ORDER BY type,reverse,reversenet,name;",$list);
  }

  return $list;
}

sub get_zone_list2($$$) {
  my($serverid,$rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  #push @{$lst},  -1;
  undef %{$rec};
  #$$rec{-1}='--None--';
  return if ($serverid < 1);

  db_query("SELECT id,name FROM zones " .
	   "WHERE server=$serverid AND type='M' AND reverse=false " .
	   "ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

sub get_zone($$) {
  my ($id,$rec) = @_;
  my ($res,@q,$hid,$sid);

  $res = get_record("zones",
	       "server,active,dummy,type,reverse,class,name,nnotify," .
	       "hostmaster,serial,refresh,retry,expire,minimum,ttl," .
	       "chknames,reversenet,comment,cdate,cuser,mdate,muser," .
	       "forward,serial_date,flags,rdate,transfer_source,transfer_source_v6,expiration",
	       $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"active,dummy,reverse,noreverse");
  $sid=$rec->{server};

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

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=2 AND ref=$id ORDER BY id",$rec,'dhcp');
  get_aml_field($sid,2,$id,$rec,'allow_update');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=3 AND ref=$id ORDER BY ip",$rec,'masters');
  get_aml_field($sid,4,$id,$rec,'allow_query');
  get_aml_field($sid,5,$id,$rec,'allow_transfer');
  get_array_field("cidr_entries",3,"id,ip,comment","IP,Comments",
		  "type=6 AND ref=$id ORDER BY ip",$rec,'also_notify');
  get_array_field("cidr_entries",4,"id,ip,port,comment","IP,Port,Comments",
		  "type=12 AND ref=$id ORDER BY ip",$rec,'forwarders');
  get_array_field("txt_entries",2,"id,txt","Zone Entries (current)", # 2020-07-30 TVu
		  "type=4 AND ref=$id ORDER BY id",$rec,'zentries_ta');
  get_array_field("txt_entries",3,"id,txt,comment","Zone Entry (deprecated),Comment",
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

# For reverse zone, change cidr to in-addr.arpa or ip6.arpa format name. TVu
      if (is_cidr($rec->{name}) && $rec->{name} =~ /\/\d{1,3}$/) {
	  $rec->{name} = cidr2arpa($rec->{name});
      }

      $new_net=arpa2cidr($rec->{name});
      if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
	  return -100;
      }
      $rec->{reversenet}=$new_net;
  }

  db_begin();
  $id=$rec->{id};

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
  $r=update_aml_field(2,$id,$rec,'allow_update');
  if ($r < 0) { db_rollback(); return -16; }
  # masters
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'masters',$rec,"3,$id");
  if ($r < 0) { db_rollback(); return -17; }
  # allow_query
  $r=update_aml_field(4,$id,$rec,'allow_query');
  if ($r < 0) { db_rollback(); return -18; }
  # allow_transfer
  $r=update_aml_field(5,$id,$rec,'allow_transfer');
  if ($r < 0) { db_rollback(); return -19; }
  # also_notify
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'also_notify',$rec,"6,$id");
  if ($r < 0) { db_rollback(); return -20; }
  # forwarders
#  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
#			'forwarders',$rec,"12,$id");
  $r=update_array_field("cidr_entries",4,"ip,port,comment,type,ref",
			'forwarders',$rec,"12,$id");
  if ($r < 0) { db_rollback(); return -20; }

  $r=update_array_field("txt_entries",2,"txt,type,ref", # 2020-07-30 TVu
			'zentries_ta',$rec,"4,$id");
  if ($r < 0) { db_rollback(); return -22; }

# -------------------------------------------------------------------------------
# For explanation of these lines, see Zones.pm %zone_form

# Old code, still in use.
# zentries
  $r = update_array_field("txt_entries",3,"txt,comment,type,ref",
			  'zentries',$rec,"12,$id");

# New code, will be activated later.
# zentries
# $r = update_textarea_field("txt_entries", $$rec{'zentries_id'}, # Textarea 12 Apr 2017 TVu
#			  "txt,type,ref", 'zentries', $rec, "12,$id");

# -------------------------------------------------------------------------------

  print "$r<br>\n" if ($r);

# $$rec{'zentries'}[0][0],

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

# $res=db_exec("DELETE FROM txt_entries WHERE type=12 AND ref=$id");

  $res=db_exec("DELETE FROM txt_entries WHERE (type=4 OR type=12) AND ref=$id"); # 2020-07-30 TVu

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

  # arec_entries
  print "<BR>Deleting (sub)group entries...\n";
  $res=db_exec("DELETE FROM group_entries WHERE id IN ( " .
	       "SELECT a.id FROM group_entries a, hosts h " .
	       "WHERE h.zone=$id AND a.host=h.id)");
  if ($res < 0) { db_rollback(); return -16; }

  # hosts
  print "<BR>Deleting Hosts...\n";
  $res=db_exec("DELETE FROM hosts WHERE zone=$id");
  if ($res < 0) { db_rollback(); return -25; }


  print "<BR>Deleting Zone record...\n";
  $res=db_exec("DELETE FROM zones WHERE id=$id");
  if ($res < 0) { db_rollback(); return -50; }


  print "<BR>Deleting User rights records...\n";
  $res=db_exec("DELETE FROM user_rights WHERE (rtype=2 OR rtype=4 " .
	       "OR rtype=9 OR rtype=10 OR rtype=11) AND rref=$id");
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
	  return -200;
      }
      $rec->{reversenet}=$new_net;
  }

  db_begin();
  $res = add_record('zones',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $rec->{id}=$id=$res;


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
  $res = update_aml_field(2,$id,$rec,'allow_update');
  if ($res < 0) { db_rollback(); return -2; }
  # masters
  $res = add_array_field('cidr_entries','ip,comment','masters',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { db_rollback(); return -3; }
  # allow_query
  $res = update_aml_field(4,$id,$rec,'allow_query');
  if ($res < 0) { db_rollback(); return -4; }
  # allow_transfer
  $res = update_aml_field(5,$id,$rec,'allow_transfer');
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
	       "expiration,asset_id,dhcp_info,flags,email,duid,iaid",
	       $id,$rec,"id");
  return -1 if ($res < 0);
  fix_bools($rec,"prn");

  my %fqdnzone;
  if (get_zone($$rec{zone}, \%fqdnzone) == 0) {
      $$rec{fqdn} = $$rec{domain} . '.' . $fqdnzone{name} . '.';
  }

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
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=13 AND ref=$id ORDER BY id",$rec,'dhcp_l6');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=2 AND ref=$id ORDER BY printer",$rec,'printer_l');
  get_array_field("srv_entries",6,"id,pri,weight,port,target,comment",
		  "Priority,Weight,Port,Target",
		  "type=1 AND ref=$id ORDER BY port,pri,weight",$rec,'srv_l');

# Get CNAME aliases.
  get_array_field("hosts",5,"0,id,domain,type,1","Domain,cname",
	          "type=4 AND alias=$id ORDER BY domain",$rec,'alias_l');

  get_array_field("groups b, group_entries a",4,"a.id,a.grp,b.name",
		  "SubGroup",
	          "a.host=$id AND a.grp=b.id ORDER BY b.name",
		  $rec,'subgroups');

# Get AREC aliases.
  get_array_field("hosts h, arec_entries a",5,"a.id,h.id,h.domain,h.type,1",
		  "Domain,cname",
	          "h.type=7 AND a.host=h.id AND a.arec=$id ORDER BY h.domain",
		  $rec,'alias_l2');
  splice(@{$rec->{alias_l2}},0,1);
  push(@{$rec->{alias_l}},@{$rec->{alias_l2}});
  delete $rec->{alias_l2};

# Get Static aliases that point to this host.
  get_array_field("hosts h1, hosts h2, zones z1, zones z2", 5,
		  "0, h2.id, h2.domain || '.' || z2.name, h2.type, -1", "Domain,cname",
	          "h1.id = $id and h1.zone = z1.id and h1.domain || '.' || z1.name || '.' = " .
		  "h2.cname_txt and h2.zone = z2.id and h2.type = 4 and h2.alias = -1 " .
		  "order by h2.domain || '.' || z2.name", $rec, 'alias_l2');
  splice(@{$rec->{alias_l2}},0,1);
  push(@{$rec->{alias_l}},@{$rec->{alias_l2}});
  delete $rec->{alias_l2};

# Get id of host that static alias points to, if possible.
  if ($rec->{alias} == -1) {
      get_array_field("hosts h1, hosts h2, zones z", 1, "h2.id", "Domain,cname",
		      "h1.id = $id and h2.domain || '.' || z.name || '.' = h1.cname_txt " .
		      "and z.id = h2.zone",
		      $rec, 'stat_alias');
      if ($rec->{stat_alias}[1][0]) {
	  $rec->{alias} = $rec->{stat_alias}[1][0];
      }
      delete $rec->{stat_alias};
      $rec->{static_alias} = 1; # Moved 2020-09-01 TVu
  }

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

    $rec->{cname_alias} = 1 if (!$rec->{cname_txt});

#   $rec->{cname_alias} = 1 if ($rec->{alias} != -1); # 2020-09-01 TVu

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
  my($r, $id);

  del_std_fields($rec);
  delete $rec->{card_info};
  delete $rec->{ether_alias_info};
  delete $rec->{wks_rec};
  delete $rec->{mx_rec};
  delete $rec->{grp_rec};
  delete $rec->{alias_l};
  delete $rec->{alias_d};
  delete $rec->{cname_alias};
  delete $rec->{static_alias};
  delete $rec->{dhcp_date};
  delete $rec->{dhcp_info};
  delete $rec->{dhcp_date_str};
  delete $rec->{fqdn};
  $rec->{alias} = -1 if ($rec->{cname_txt});

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

  $r=update_array_field("group_entries",2,"grp,host",
			'subgroups',$rec,"$id");
  if ($r < 0) { db_rollback(); return -22; }

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l6',$rec,"13,$id");
  if ($r < 0) { db_rollback(); return -23; }

  return db_commit();
}

sub delete_host($) {
  my($id) = @_;
  my($res,%host,$sql);
  my($dtime) = time;

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

  # static aliases TVu 15.03.2016
  $sql = "delete from hosts where id in " .
      "(select h2.id from hosts h1, hosts h2, zones z " .
      "where h1.id = $id and h1.zone = z.id and " .
      "h1.domain || '.' || z.name || '.' = h2.cname_txt and " .
      "h2.type = 4 and h2.alias = -1);";
  $res = db_exec($sql);
  if ($res < 0) { db_rollback(); return -13; }

  # arec aliases unless they also point to some other host TVu 15.03.2016
  # this must be done before deleting arec_entries!
  $sql = "delete from hosts where id in (select s1.host from " .
      "(select host, count(arec) as c1 from arec_entries where host in " .
      "(select host from arec_entries where arec = $id) group by host) " .
      "as s1 where s1.c1 = 1) and type = 7 and alias = -1;";
  $res = db_exec($sql);
  if ($res < 0) { db_rollback(); return -14; }

  # arec_entries
  $res=db_exec("DELETE FROM arec_entries WHERE host=$id OR arec=$id;");
  if ($res < 0) { db_rollback(); return -8; }

  # cname aliases
  $res=db_exec("DELETE FROM hosts WHERE type=4 AND alias=$id;");
  if ($res < 0) { db_rollback(); return -9; }

  # ether_aliases
  $res=db_exec("UPDATE hosts SET ether_alias=-1, expiration=$dtime ".
	       "WHERE ether_alias=$id;");
  if ($res < 0) { db_rollback(); return -10; }

  # srv_entries
  $res=db_exec("DELETE FROM srv_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -11; }

  # group_entries
  $res=db_exec("DELETE FROM group_entries WHERE host=$id;");
  if ($res < 0) { db_rollback(); return -12; }

  # Note that -13 and -14 are already in use!

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

  delete $rec->{cname_alias};
  delete $rec->{static_alias};

  return -100 unless ($rec->{zone} > 0);
  db_begin();
  if ($rec->{type}==7) {
    $a_id=$rec->{alias};
    delete $rec->{alias};
  }
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $rec->{domain}=lc($rec->{domain});

# Replace tag with id.
  if ($rec->{domain} =~ /%\{id\}/) {
      my(@q);
      my $sql = 'select nextval((\'hosts_id_seq\'::text)::regclass);';
      db_query($sql, \@q);
      if ($q[0][0]) {
	  $rec->{hacked_id} = $q[0][0];
	  $rec->{domain} =~ s/%\{id\}/$q[0][0]/;
      } else {
	  return -10;
      }
  }

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

  # subgroups
  $res = add_array_field('group_entries','grp',
			 'subgroups',$rec,'host',"$id");
  if ($res < 0) { db_rollback(); return -8; }

  return -10 if (db_commit() < 0);
  return $id;
}

# List moved from browser.cgi so that it can be used also in command line
# tools without need to update multiple lists, should the list change.
# TVu 02.04.2014.
sub get_host_types() {
    return (0 => 'Any type', 1 => 'Host', 2 => 'Delegation', 3 => 'Plain MX',
	    4 => 'Alias', 5 => 'Printer', 6 => 'Glue record', 7 => 'AREC Alias',
	    8 => 'SRV record', 9 => 'DHCP only', 10 => 'Zone',
	    101 => 'Host reservation');
}

############################################################################
# MX template functions

sub get_mx_template_by_name($$) {
  my($zoneid,$name)=@_;
  my(@q);
  return -1 unless ($zoneid > 0);
  $name=db_encode_str($name);
  db_query("SELECT id FROM mx_templates WHERE zone=$zoneid AND name=$name",
	   \@q);
  return -2 unless (@q > 0);
  return ($q[0][0]);
}

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
  $name=db_encode_str($name);
  db_query("SELECT id FROM groups WHERE server=$serverid AND name=$name",\@q);
  return -2 unless (@q > 0);
  return ($q[0][0]);
}

sub get_group_type_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return -1 unless ($serverid > 0);
  $name=db_encode_str($name);
  db_query("SELECT type FROM groups WHERE server=$serverid AND name=$name",\@q);
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

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=15 AND ref=$id ORDER BY id",$rec,'dhcp6');

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

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp6',$rec,"15,$id");
  if ($r < 0) { db_rollback(); return -16; }

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

  # dhcp_entries
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6',$rec,
			 'type,ref',"15,$id");
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
  $res=db_exec("DELETE FROM dhcp_entries WHERE (type=5 OR type=15) AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }
# printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=1 AND ref=$id");
  if ($res < 0) { db_rollback(); return -2; }

# group itself
  $res=db_exec("DELETE FROM groups WHERE id=$id");
  if ($res < 0) { db_rollback(); return -3; }

  return db_commit();
}

sub get_group_list($$$$$) {
  my($serverid,$rec,$lst,$alevel,$gtype) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return unless ($serverid > 0);
  $alevel=0 unless ($alevel > 0);

  my $gtypestr = ($gtype ? "type IN (" . join(",", @$gtype) . ")" : "type < 100");

  db_query("SELECT id,name FROM groups " .
	   "WHERE server=$serverid AND alevel <= $alevel AND $gtypestr " .
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

sub delete_user($$$$$$) {
  my($id, $name, $delete, $expiration, $now, $user) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  # user_rights
  $res=db_exec("DELETE FROM user_rights WHERE type=2 AND ref=$id;");
  if ($res < 0) { db_rollback(); return -1; }
  # utmp
  $res=db_exec("DELETE FROM utmp WHERE uid=$id;");
  if ($res < 0) { db_rollback(); return -2; }

  if ($delete) {
      $res=db_exec("DELETE FROM users WHERE id=$id;");
      if ($res < 0) { db_rollback(); return -3; }
  } else {
      $res=db_exec("update users set (server, zone, superuser, last_pwd, flags, " .
		   "email, last_from, search_opts, comment, " .
		   "name, password, expiration, mdate, muser) = " .
		   "(default, default, default, default, default, " .
		   "null, null, null, null, " .
		   "'Removed User', 'LOCKED:REMOVED', $expiration, $now, '$user') " .
		   "where id = $id;");
      if ($res < 0) { db_rollback(); return -4; }
  }

# User was deleted from all user groups, but that is not recorded in history.
  $res = update_history(-1, -1, 5,      # No UID. No SID. 5 = User changes.
			($delete ? 'DELETE' : 'ANONYMIZE') . ': User', # Action.
			"Username: $name (login: " . getlogin(). ')', # Info
			$id);           # Ref.
  if ($res < 0) { db_rollback(); return -4; }

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

# For Users.pm 2021-04-21 TVu
sub get_user_group_w_members($$) { # Kesken !!!
  my ($id, $rec) = @_;
  my ($res, $t, $wrec, $mrec, %h, @q, $infostr);

  $res = get_record("user_groups", "name, comment",
	       $id, $rec, "id");
  return -1 if ($res < 0);

  get_array_field("users u, user_rights ur", 3, "u.id, u.username, u.name",
		  "Members", "ur.type = 2 AND ur.rtype = 0 AND " .
		  "ur.rref = $id AND ur.ref = u.id ORDER BY u.username",
		  $rec, 'users');

  return 0;
}

# For Users.pm 2021-05-10 TVu
sub get_all_users($$) {
  my($rec,$lst) = @_;
  my(@q,$i);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';

  db_query("SELECT id, username || ' - ' || name FROM users " .
	   "ORDER BY 2;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

sub delete_user_group($$$$$$) {
  my ($id,$newid,$group,$newgroup,$uid,$sid) = @_;
  my ($res,$sql,@q,$ind1);

  db_begin();

# Delete rights given to the group.
  $res = db_exec("DELETE FROM user_rights WHERE type=1 AND ref=$id");
  if ($res < 0) { db_rollback(); return -1; }
# Delete group.
  $res = db_exec("DELETE FROM user_groups WHERE id=$id");
  if ($res < 0) { db_rollback(); return -2; }
# Update group history.
  $res = update_history($uid, $sid, 6,        # 6 = User group changes.
			'DELETE: User group', # Action.
			"Group: $group (login: " . getlogin(). ')', # Info
			$id);                 # Ref.
  if ($res < 0) { db_rollback(); return -5; }

  if ($newid > 0) {
# Get list of users who will be moved.
# Must be done before users are moved!
      $sql = "select ur.ref, u.username " .
	  "from user_rights ur, users u " .
	  "where ur.type = 2 and ur.rtype = 0 and " .
	  "ur.rref = $id and ur.ref = u.id;";
      db_query($sql, \@q);
# Update user history.
      for $ind1 (0..$#q) {
	  $res = update_history($uid, $sid, 5, # 5 = User changes.
				'MOVE: User',  # Action.
				"Username: $q[$ind1][1], Group: $group to $newgroup (login: " . getlogin(). ')', # Info
				$q[$ind1][0]); # Ref.
	  if ($res < 0) { db_rollback(); return -6; }
      }
# Move users to another group.
      $res = db_exec("UPDATE user_rights SET rref=$newid " .
		     "WHERE type=2 AND rtype=0 AND rref=$id");
      if ($res < 0) { db_rollback(); return -3; }
  } else {
# Delete group membership from users.
      $res = db_exec("DELETE FROM user_rights ".
		     "WHERE type=2 AND rtype=0 AND rref=$id");
      if ($res < 0) { db_rollback(); return -4; }
  }

# Moving users may have created duplicates, which have to be deleted. We
# migjht have avoided creating these duplicates by not selecting those
# users who already were members of the new group, but then we would
# have to delete broken references to the old group. It makes more sense
# to delete *all* duplicates here, new and any old ones that may exist.
  $sql = 'delete from user_rights where id in (' .
      'select id from (' .
      'select id, row_number() over (' .
      'partition by ref, rref order by id) as rnum ' .
      'from user_rights ' .
      'where type = 2 and ' .
      'rtype = 0) ur ' .
      'where ur.rnum > 1);';
  $res = db_exec($sql);
  if ($res < 0) { db_rollback(); return -7; }

  return db_commit();
}

# Get user's status and authorization level.
sub get_user_status($) {
    my ($id) = @_;
    my ($sql, @res, $status);

# Get status (other than authorization level).
    $sql = "select coalesce(expiration, 0) <= 0 or coalesce(expiration, 0) > " .
	"extract(epoch from now()), password, superuser " .
	"from users " .
	"where id = $id;";
    db_query($sql, \@res);
    return -1 if (!$res[0][1]);
    $status = '';
    if (lc($res[0][0]) eq 'f') { $status .= 'E'; } # Expired.
    if (lc($res[0][1]) =~ /^locked:/) { $status .= 'L'; } # Locked.
    if (lc($res[0][2]) eq 't') { $status .= 'S'; } # Superuser.

# Get authorization level.
# Given directly to the user.
    $sql = "(select rule from user_rights " .
	"where type = 2 and ref = $id and rtype = 6 " .
	"union " .
# Given to a group whose member the user is.
	"select ur2.rule " .
	"from user_rights ur1, user_rights ur2 " .
	"where ur1.type = 2 and ur1.ref = $id and ur1.rtype = 0 and " .
	"ur2.type = 1 and ur2.ref = ur1.rref and ur2.rtype = 6) " .
# Return highest value if several were found.
	"order by 1 desc limit 1;";
    undef @res;
    db_query($sql, \@res);
    $res[0][0] =~ s/\s//g;
    return $status . ($res[0][0] || 0); # Default to 0.
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

sub get_net_cidr_by_ip($$) {
  my($serverid,$ip) = @_;
  my(@q);

  return '-1' unless ($serverid > 0);
  return '-2' unless (is_ip($ip));
  db_query("SELECT net FROM nets WHERE server=$serverid AND net >> '$ip' order by net desc limit 1",\@q);
  return ($q[0][0] ? $q[0][0] : '');
}

sub get_net_list($$$) {
  my ($serverid,$subnets,$alevel) = @_;
  my (@q,$list,$i);

  if ($subnets) {
    $subnets=($subnets==0?'false':'true');
    $subnets=" AND subnet=$subnets ";
  } else {
    $subnets='';
  }

  if ($alevel > 0) {
    $alevel=" AND alevel <= $alevel ";
  } else {
    $alevel='';
  }

  $list=[];
  return $list unless ($serverid >= 0);

  db_query("SELECT net,id,name FROM nets " .
	   "WHERE server=$serverid $subnets $alevel ORDER BY net",\@q);

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
                      "netname,alevel,type,dummy,ip_policy", $id,$rec,"id"));

  fix_bools($rec,"subnet,no_dhcp,dummy");
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
# $net = new Net::Netmask($rec->{net});
  $net = new NetAddr::IP($rec->{net}); # For IPv6.
  return -101 unless ($net);

# Nets (other than subnets and virtual nets) should never have had a range, and
# some changes to net's CIDR were not possible when they had. 2019-01-03 TVu
  if ($rec->{subnet} =~ /^f/i && $rec->{dummy} =~ /^f/i) {
      $rec->{range_start} = $rec->{range_end} = '';
  }

  if (is_cidr($rec->{range_start})) {
#   return -102 unless ($net->match($rec->{range_start}));
    return -102 unless ($net->contains(new NetAddr::IP($rec->{range_start}))); # For IPv6.
  }
  if (is_cidr($rec->{range_end})) {
#   return -103 unless ($net->match($rec->{range_end}));
    return -102 unless ($net->contains(new NetAddr::IP($rec->{range_end}))); # For IPv6.
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
  $net = new Net::IP($rec->{net});
  return -101 unless ($net);

  # Create ranges for subnets and virtual nets only. 2019-01-03 TVu
  unless ($rec->{subnet} =~ /^f/i && $rec->{dummy} =~ /^f/i) {

    # Dirty hack for /31,/32 & /127, /128 subnets:]
    if ($net->size() <= 2) {
      $rec->{range_start} = ip_compress_address(($net)->ip(), $net->version())
	unless (is_cidr($rec->{range_start}));
      $rec->{range_end}   = ip_compress_address($net->last_ip(), $net->version())
	unless (is_cidr($rec->{range_end}));
    } else {
      #     $rec->{range_start} = ip_compress_address((++$net)->ip(), $net->version())
      #	  unless (is_cidr($rec->{range_start}));
      #     $rec->{range_end} = ($net->version() eq 4 ? new Net::Netmask($rec->{net})->nth(-2) :
      #			   ip_compress_address($net->last_ip(), $net->version()))
      #	  unless (is_cidr($rec->{range_end}));
      # The same without Net::Netmask.
      $rec->{range_start} = ip_compress_address((++$net)->ip(), $net->version())
	unless (is_cidr($rec->{range_start}));
      $rec->{range_end} = ($net->version() eq 4 ? new NetAddr::IP($rec->{net})->last() :
			   ip_compress_address($net->last_ip(), $net->version()))
	unless (is_cidr($rec->{range_end}));
      $rec->{range_end} =~ s=/\d+$==; # new NetAddr::IP(...)->last() returns CIDR not IP TVu 2018-02-07
    }

  }


  $res = add_record('nets',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  # dhcp_entries
  for $i (0..$#{$rec->{dhcp_l}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(4,$id,'$rec->{dhcp_l}[$i][1]')");
    if ($res < 0) { db_rollback(); return -3; }
  }

  for $i (0..$#{$rec->{dhcp_l6}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(4,$id,'$rec->{dhcp_l6}[$i][1]')");
    if ($res < 0) { db_rollback(); return -4; }
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
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=16 AND ref=$id ORDER BY id",$rec,'dhcp_l6');

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

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l6',$rec,"16,$id");
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

# dhcp_entries6
  for $i (0..$#{$rec->{dhcp_l6}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(16,$id,'$rec->{dhcp_l6}[$i][1]')");
    if ($res < 0) { db_rollback(); return -4; }
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

sub get_vlanno($$) {
  my($serverid,$id) = @_;
  my(@q);

  return 0 if ($serverid < 1);

  db_query("SELECT coalesce(vlanno,0) FROM vlans " .
	   "WHERE server=$serverid and id=$id;",\@q);
  return $q[0][0];
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
# IP functions

# Name network's ip policies.
sub ip_policy_names($) {
    my($ip, $m) = ($_[0] =~ /^(.+)\/(.+)$/);
    my %list = ( 0 => 'Lowest free', 10 => 'Highest free' );
    if ($ip =~ /:/) {
	if ($m <= 80) { $list{20} = 'MAC based'; }
	if ($m <= 96) { $list{30} = 'IPv4 based'; }
    }
    return \%list;
}

sub get_net_ip_policy($$) {
    my ($serverid, $cidr) = @_;
    my ($sql, @res);

    $cidr =~ s=^(.*)/.*$=$1=;
    $sql = "select ip_policy from nets where server = $serverid and " .
	"'$cidr' <<= net order by net desc;";
    db_query($sql, \@res);
    return $res[0][0] || 0; # TVu 15.03.2017 Added default just in case ...
}

# Get one free ip based on net's ip address policy etc.
sub get_free_ip_by_net($$$$$) {
    my ($serverid, $cidr, $mac, $old_ip, $ip_policy) = @_;
    my ($tmp1, $mask, $sql, @res);

# Each error message MUST be prepended by  "S:" (subnet level error)
# or "H:" (host level error). This is needed in addipv6.

# Use default policy if old ip and ip policy are incompatible.
# Also if parameters don't support given ip policy. 15.03.2017 TVu
    if (!$mac && $ip_policy == 20 || $ip_policy == 30 && (!$old_ip || cidr6ok($old_ip))) {
	$ip_policy = 0;
    }

    ($mask = $cidr) =~ s=^.*/(.*)$=$1=;
    $mask =~ s/\D//g;
# 0 = Lowest free.
    if ($ip_policy == 0) {
	my ($beg, $end);
	$sql = "SELECT range_start, range_end FROM nets " .
	    "WHERE server = $serverid AND net = '$cidr';";
	db_query($sql, \@res);
	return 'S:No auto address range for this net'
	    unless (is_cidr($res[0][0]) && is_cidr($res[0][1]));
	return 'S:Net has invalid auto address range'
#	    if (ip2int($res[0][0]) >= ip2int($res[0][1]));
	    if (normalize_ip6($res[0][0]) ge normalize_ip6($res[0][1]));
	$beg = $res[0][0];
	$end = $res[0][1];
# Beginning of range must be handled separately.
	return $beg if (!ip_in_use($serverid, $beg));
# Find all used addresses in given range, drop all cases where the next address
# is also in use, and return the smallest of remaining addresses plus one.
	$sql = "select a.ip + 1 from a_entries a, hosts h, zones z " .
	    "where z.server = $serverid and h.zone = z.id and a.host = h.id " .
	    "and a.ip >= '$beg' and a.ip < '$end' and a.ip + 1 not in (" .
	    "select a.ip from a_entries a, hosts h, zones z " .
	    "where z.server = $serverid and h.zone = z.id and a.host = h.id " .
	    "and a.ip >= '$beg' and a.ip <= '$end') " .
	    "order by a.ip asc limit 1;";
	undef @res;
	db_query($sql, \@res);
	return 'S:No free addresses left in this net' if (!@res);
	return $res[0][0];
# 10 = Highest free.
    } elsif ($ip_policy == 10) {
	my ($beg, $end);
	$sql = "SELECT range_start, range_end FROM nets " .
	    "WHERE server = $serverid AND net = '$cidr';";
	db_query($sql, \@res);
	return 'S:No auto address range for this net'
	    unless (is_cidr($res[0][0]) && is_cidr($res[0][1]));
	return 'S:Net has invalid auto address range'
#	    if (ip2int($res[0][0]) >= ip2int($res[0][1]));
	    if (normalize_ip6($res[0][0]) ge normalize_ip6($res[0][1]));
	$beg = $res[0][0];
	$end = $res[0][1];
	return $end if (!ip_in_use($serverid, $end));
# See "Lowest free" above for details.
	$sql = "select a.ip - 1 from a_entries a, hosts h, zones z " .
	    "where z.server = $serverid and h.zone = z.id and a.host = h.id " .
	    "and a.ip > '$beg' and a.ip <= '$end' and a.ip - 1 not in (" .
	    "select a.ip from a_entries a, hosts h, zones z " .
	    "where z.server = $serverid and h.zone = z.id and a.host = h.id " .
	    "and a.ip >= '$beg' and a.ip <= '$end') " .
	    "order by a.ip desc limit 1;";
	undef @res;
	db_query($sql, \@res);
	return 'S:No free addresses left in this net' if (!@res);
	return $res[0][0];
# 20 = MAC based.
    } elsif ($ip_policy == 20) {
	if ($mask <= 80 && $mac =~ /^[\da-f]{12}$/i) {
	    ($tmp1 = $mac) =~ s/(.{4})/:$1/g;
	    $tmp1 = ipv6compress(substr(ipv6decompress($cidr), 0, 24) . $tmp1);
	    $sql = "select ip from a_entries a where ip = '$tmp1';";
	    db_query($sql, \@res);
	    return $res[0][0] ? 'H:MAC based IPv6 already in use' : $tmp1;
	} else {
	    return $mask > 80 ?
		'S:Unable to create MAC based IPv6 address (netmask longer than 80 bits)' :
		'H:Unable to create MAC based IPv6 address (missing or invalid MAC)';
	}
# 30 = IPv4 based.
    } elsif ($ip_policy == 30) {
	if ($mask <= 96 && cidr4ok($old_ip) && is_ip($old_ip) && $old_ip =~ /\./) {
	    $tmp1 = ipv64unmix(ipv6compress(substr(ipv6decompress($cidr), 0, 30) . $old_ip));
	    $sql = "select ip from a_entries a where ip = '$tmp1';";
	    db_query($sql, \@res);
	    return $res[0][0] ? 'H:IPv4 based IPv6 already in use' : $tmp1;
	} else {
	    return $mask > 96 ?
		'S:Unable to create IPv4 based IPv6 address (netmask longer than 96 bits)' :
		'H:Unable to create IPv4 based IPv6 address (missing or invalid IPv4)';
	}
    }
}

# Get a list of free ip addresses, one per net, for each net in the
# same vlan as the given host that fits the user's auth level.
sub get_ip_sugg($$$) {
    my ($hostid, $serverid, $perms) = @_;
    my (@row_n, @row_v, $list, $sql, $old_ip, $new_ip, $netname, $cidr, $mac, $ip_policy, $netid, $alevel_n);
    my $alevel_u = $perms->{alevel};

# Get subnets. Don't care about alevels or permissions.
    $sql = "select distinct on (n2.netname) " .
	"n2.netname, n2.net, h.ether, a.ip, n2.ip_policy, n2.id, n2.alevel ".
	"from a_entries a, vlans v, nets n1, nets n2, hosts h ".
	"where a.host = $hostid and a.ip << n1.net " .
	"and n1.server = $serverid and n1.vlan = v.id " .
	"and v.server = $serverid and v.id = n2.vlan " .
	"and n2.server = $serverid " .
	"and a.host = h.id order by n2.netname, a.ip;";
    db_query($sql, \@row_n);
    $list = '';
    for my $ind1 (0..$#row_n) {
	$mac = $row_n[$ind1][2];
	$old_ip = $row_n[$ind1][3];
	$netid = $row_n[$ind1][5];
	$alevel_n = $row_n[$ind1][6];
# Show net to user only if alevel and permissions allow.
	if ($alevel_u >= 998 || $alevel_u >= $alevel_n && (!%{$perms->{net}} || $perms->{net}->{$netid})) {
	    $netname = $row_n[$ind1][0];
	    $cidr = $row_n[$ind1][1];
	    $ip_policy = $row_n[$ind1][4];
	    $new_ip = get_free_ip_by_net($serverid, $cidr, $mac, $old_ip, $ip_policy);
	    if (is_ip($new_ip)) {
		$list .= "<option value='$new_ip'>$netname - $new_ip</option>\n";
	    }
	}
# Get possible virtual nets in each subnet even if user can't see the subnet.
	$sql = "select netname, net, ip_policy, id, alevel from nets " .
	    "where dummy = 't' and net << '$cidr' order by netname;";
	db_query($sql, \@row_v);
	for my $ind2 (0..$#row_v) {
	    $netid = $row_v[$ind1][3];
	    $alevel_n = $row_v[$ind1][4];
# Show virtual net to user only if alevel and permissions allow.
	    if ($alevel_u >= 998 || $alevel_u >= $alevel_n && (!%{$perms->{net}} || $perms->{net}->{$netid})) {
		$netname = $row_v[$ind2][0];
		$cidr = $row_v[$ind2][1];
		$ip_policy = $row_v[$ind1][2];
		$new_ip = get_free_ip_by_net($serverid, $cidr, $mac, $old_ip, $ip_policy);
		if (is_ip($new_ip)) {
		    $list .= "<option value='$new_ip'>\n$netname - $new_ip</option>\n";
		}
	    }
	}
    }
    if ($list) {
	$list = "\n<select name='subnetlist'>\n<option value='null'>&lt;Select&gt;</option>\n$list</select>\n";
    }
    return $list;
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
# KEY functions

sub get_key($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("keys",
                      "type,ref,name,keytype,nametype,protocol,algorithm,".
                      "mode,keysize,strength,publickey,secretkey,comments,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}


sub update_key($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('keys',$rec);
  if ($r < 0) { db_rollback(); return $r; }

  return db_commit();
}

sub add_key($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('keys',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $id=$res;

  return -10 if (db_commit() < 0);
  return $id;
}

sub delete_key($) {
  my($id) = @_;
  my($res);

  return -100 unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM keys WHERE id=$id");
  if ($res < 0) { db_rollback(); return -1; }


  #$res=db_exec("UPDATE acls SET vlan=-1 WHERE vlan=$id");
  #if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_key_list($$$$) {
  my($serverid,$rec,$lst,$algo) = @_;
  my(@q,$i,$algorule);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return if ($serverid < 1);
  $algorule=" AND algorithm=$algo " if ($algo > 0);

  db_query("SELECT id,name FROM keys " .
	   "WHERE type=1 AND ref=$serverid $algorule ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

sub get_key_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return -100 unless ($serverid > 0);
  return -101 unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM keys " .
	   "WHERE type=1 AND ref=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}


############################################################################
# ACL functions

sub get_acl($$) {
  my ($id,$rec) = @_;

  return -100 if (get_record("acls",
		      "server,name,type,comment,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));
  add_std_fields($rec);
  get_aml_field($rec->{server},0,$id,$rec,'acl');
  return 0;
}


sub update_acl($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('acls',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  $id=$rec->{id};

  $r=update_aml_field(0,$id,$rec,'acl');
  if ($r < 0) { db_rollback(); return -1000+$r; }

  return db_commit();
}

sub add_acl($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser} = $muser if !$rec->{'cuser'};
  $res = add_record('acls',$rec);
  if ($res < 0) { db_rollback(); return -1; }
  $rec->{id}=$id=$res;

  $res=update_aml_field(0,$id,$rec,'acl');
  if ($res < 0) { db_rollback(); return -2; }

  return -10 if (db_commit() < 0);
  return $id;
}

sub delete_acl($$) {
  my($id,$newref) = @_;
  my($res);

  return -100 unless ($id > 0);
  $newref=-1 unless ($newref > 0 && $newref != $id);

  db_begin();

  $res=db_exec("DELETE FROM acls WHERE id=$id");
  if ($res < 0) { db_rollback(); return -1; }

  $res=db_exec("DELETE FROM cidr_entries WHERE type=0 AND ref=$id");
  if ($res < 0) { db_rollback(); return -9; }
  $res=db_exec("UPDATE cidr_entries SET acl=$newref ".
	       "WHERE type>0 AND acl=$id");
  if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

sub get_acl_list($$$$) {
  my($serverid,$rec,$lst,$mask) = @_;
  my(@q,$i,$extrarule);

  undef @{$lst};
  push @{$lst},  -1;
  undef %{$rec};
  $$rec{-1}='--None--';
  return unless ($serverid > 0);
  $extrarule=" AND id < $mask " if($mask > 0);

  db_query("SELECT id,name FROM acls " .
	   "WHERE (server=$serverid $extrarule) OR server=-1 " .
	   "ORDER BY name;",\@q);
  for $i (0..$#q) {
    push @{$lst}, $q[$i][0];
    $$rec{$q[$i][0]}=$q[$i][1];
  }
}

sub get_acl_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return -100 unless ($serverid > 0);
  return -101 unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM acls " .
	   "WHERE server=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
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

#   $j= sprintf("%02d:%02d",$h,$m);
#   $j= sprintf(" %02ds ",$s) if ($m <= 0 && $h <= 0);

    $j = sprintf('%02d:%02d:%02d', $h, $m, $s); # ** 2020-10-06 TVu

    $ip = $q[$i][2];
    $ip =~ s/\/32$//;
    $ip =~ s/\/128$//;
    $login_s=localtime($login);
    next unless ($idle < $timeout);
    push @{$lst},[$q[$i][0],$q[$i][1],$ip,$j,$login_s];
  }

}


sub cgi_disabled() {
  my(@q);
  db_query("SELECT value FROM settings WHERE setting='cgi_disable';",\@q);
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
  $rec->{groups}='';

  undef @q;
  $sql = "SELECT a.rtype,a.rref,a.rule,n.range_start,n.range_end " .
	 "FROM user_rights a, nets n " .
	 "WHERE ((a.type=2 AND a.ref=$uid) OR (a.type=1 AND a.ref IN (SELECT rref FROM user_rights WHERE type=2 AND ref=$uid AND rtype=0))) " .
           "  AND a.rtype=3 AND a.rref=n.id " .
	   "UNION " .
	   "SELECT rtype,rref,rule,NULL,NULL FROM user_rights " .
	   "WHERE ((ref=$uid AND type=2) OR (type=1 AND ref IN (SELECT rref FROM user_rights WHERE type=2 AND ref=$uid AND rtype=0))) " .
	   " AND rtype<>3 ORDER BY 1;";
  $sql = "SELECT ur.rtype, ur.rref, ur.rule, n.range_start, n.range_end " .
      "FROM user_rights ur, nets n " .
      "WHERE ((ur.type = 2 AND ur.ref = $uid) OR (ur.type = 1 AND ur.ref IN " .
      "(SELECT rref FROM user_rights WHERE type = 2 AND ref = $uid AND rtype = 0))) " .
      "AND ur.rtype = 3 AND ur.rref = n.id " .
      "UNION " .
      "SELECT rtype, rref, rule, NULL, NULL " .
      "FROM user_rights " .
      "WHERE ((ref = $uid AND type = 2) OR (type = 1 AND ref IN " .
      "(SELECT rref FROM user_rights WHERE type = 2 AND ref = $uid AND rtype = 0))) " .
      "AND rtype <> 3 ORDER BY 1;";
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
    elsif ($type == 4) { push @{$rec->{hostname}},[$ref,$mode]; }
    elsif ($type == 5) { push @{$rec->{ipmask}}, $mode; }
    elsif ($type == 6) { $rec->{alevel}=$mode if ($rec->{alevel} < $mode); }
    elsif ($type == 7) { $rec->{elimit}=$mode; }
    elsif ($type == 8) { $rec->{defdept}=$mode; }
    elsif ($type == 9) { push @{$rec->{tmplmask}}, $mode; }
    elsif ($type == 10) { push @{$rec->{grpmask}}, $mode; }
    elsif ($type == 11) { push @{$rec->{delmask}},[$ref,$mode]; }
    elsif ($type == 12) { $rec->{rhf}->{$mode}=$ref; }
    elsif ($type == 13) { $rec->{flags}->{$mode}=1; }
    elsif ($type == 14) { $rec->{defhost}=$mode; }
  }

  db_query("SELECT g.name FROM user_groups g, user_rights r " .
	   "WHERE g.id=r.rref AND r.rtype=0 AND r.type=2 " .
	   " AND r.ref=$uid ORDER BY g.id",\@q);
  for $i (0..$#q) {
    $rec->{groups}.="," if ($rec->{groups});
    $rec->{groups}.=$q[$i][0];
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

# uid and sid are -1 in some command line scripts
  return -1 unless ($uid > 0 || $uid == -1);
  return -2 unless ($sid > 0 || $sid == -1);
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
     #$host=substr($q[$j][6],0,15);
     $host=$q[$j][6];
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


sub save_state($$) {
  my($id,$state)=@_;
  my(@q,$res,$s_auth,$s_addr,$other,$s_mode,$s_superuser);

  undef @q;
  db_query("SELECT uid,cookie FROM utmp WHERE cookie='$id';",\@q);
  unless (@q > 0) {
      if (db_exec("INSERT INTO utmp (uid,cookie,auth) " .
		  "VALUES(-1,'$id',false);") < 0) {
	return -1;
      }
  }

  $s_superuser = ($state->{'superuser'} eq 'yes' ? 'true' : 'false');
  $s_auth=($state->{'auth'} eq 'yes' ? 'true' : 'false');
  $s_mode=($state->{'mode'} ? $state->{'mode'} : 0);

  $other='';
  if ($state->{'addr'}) { $other.=", addr='".$state->{'addr'}."' ";  }
  if ($state->{'uid'}) { $other.=", uid=".$state->{'uid'}." ";  }
  if ($state->{'sid'}) { $other.=", sid=".$state->{'sid'}." ";  }
  if ($state->{'serverid'}) {
    $other.=", serverid=".$state->{'serverid'}." ";
    $other.=", server='".$state->{'server'}."' ";
  }
  if ($state->{'zoneid'}) {
    $other.=", zoneid=".$state->{'zoneid'}." ";
    $other.=", zone='".$state->{'zone'}."' ";
  }
  if ($state->{'user'}) { $other.=", uname='".$state->{'user'}."' "; }
  if ($state->{'login'}) { $other.=", login=".$state->{'login'}." "; }
  $other.=", searchopts=". db_encode_str($state->{'searchopts'}) . " ";
  $other.=", searchdomain=". db_encode_str($state->{'searchdomain'}) . " ";
  $other.=", searchpattern=". db_encode_str($state->{'searchpattern'}) . " ";

  $res=db_exec("UPDATE utmp SET auth=$s_auth, mode=$s_mode " .
	       ", superuser=$s_superuser $other " .
	       "WHERE cookie='$id';");

  return ($res < 0 ? -2 : 1);
}


sub load_state($$) {
  my($id,$state)=@_;
  my(@q);

  undef %{$state};
  $state->{'auth'}='no';
  $state->{'cookie'}=$id;


  db_query("SELECT uid,addr,auth,mode,serverid,server,zoneid,zone," .
	   " uname,last,login,searchopts,searchdomain,searchpattern," .
           " superuser,sid " .
           "FROM utmp WHERE cookie='$id'",\@q);

  if (@q > 0) {
    $state->{'uid'}=$q[0][0];
    $state->{'addr'}=$q[0][1];
    $state->{'addr'} =~ s/\/32\s*$//;
    $state->{'addr'} =~ s/\/128\s*$//;
    $state->{'auth'}='yes' if ($q[0][2] eq 't' || $q[0][2] == 1);
    $state->{'mode'}=$q[0][3];
    if ($q[0][4] > 0) {
      $state->{'serverid'}=$q[0][4];
      $state->{'server'}=$q[0][5];
    }
    if ($q[0][6] > 0) {
      $state->{'zoneid'}=$q[0][6];
      $state->{'zone'}=$q[0][7];
    }
    $state->{'user'}=$q[0][8] if ($q[0][8] ne '');
    $state->{'last'}=$q[0][9];
    $state->{'login'}=$q[0][10];
    $state->{'searchopts'}=$q[0][11];
    $state->{'searchdomain'}=$q[0][12];
    $state->{'searchpattern'}=$q[0][13];
    $state->{'superuser'}='yes' if ($q[0][14] eq 't' || $q[0][14] == 1);
    $state->{'sid'}=$q[0][15];

    db_exec("UPDATE utmp SET last=" . time() . " WHERE cookie='$id';");
    return 1;
  }

  return 0;
}


sub remove_state($) {
  my($id) = @_;

  return -1 unless ($id);
  return -2 if (db_exec("DELETE FROM utmp WHERE cookie='$id'") < 0);
  return 1;
}


1;
# eof
