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
use Sauron::ErrorCodes qw(:return :database);
use Sauron::Util;
use Sauron::SetupIO;
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

	     is_catalog_zone
	     validate_zone_for_catalog
	     get_zone_catalog_members
	     get_zone_catalogs
	     add_zone_to_catalog
	     remove_zone_from_catalog
	    );

# Catalog zones support (RFC 9432) - six functions exported above
my($muser);



sub write2log
{
  #my $priority  = shift;
  my $msg       = shift;
  my $filename  = File::Basename::basename($0);

  Sys::Syslog::openlog($filename, "cons,pid", "debug");
  Sys::Syslog::syslog("info", encode_str("$msg"));
  Sys::Syslog::closelog();
} # End of write2log


=head1 FUNCTION: fix_bools

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: sauron_db_version

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub sauron_db_version() {
  return "1.8"; # required db format version for this backend
}

=head1 FUNCTION: set_muser

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub set_muser($) {
  my($usr)=@_;
  $muser=$usr;
}


=head1 FUNCTION: get_db_version

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_db_version() {
  my(@q);
  db_query("SELECT value FROM settings WHERE setting='dbversion';",\@q);
  return ($q[0][0] =~ /^\d/ ? $q[0][0] : 'ERROR');
}


=head1 FUNCTION: auto_address

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: next_free_ip

Description:
  Find the next available IP address in the matching network.

Parameters:
  serverid - Server ID
  ip       - Input IP/CIDR

Returns:
  IP string on success, empty string when no suitable address is found.

=cut

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

=head1 FUNCTION: next_free_ip

Description:
  Find the next available IP address inside server network that contains input IP.

Parameters:
  serverid - Server ID
  ip       - Candidate IP/CIDR used to select parent network

Returns:
  IP address string on success, empty string on failure.

=cut

=head1 FUNCTION: ip_in_use

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub ip_in_use($$) {
  my($serverid,$ip)=@_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  return RET_INVALID_ARGUMENT unless (is_cidr($ip));
  db_query("SELECT a.id FROM hosts h, a_entries a, zones z " .
	   "WHERE z.server=$serverid AND h.zone=z.id AND a.host=h.id " .
	   " AND a.ip = '$ip';",\@q);
  return 1 if ($q[0][0] > 0);
  return 0;
}

=head1 FUNCTION: domain_in_use

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub domain_in_use($$) {
  my($zoneid,$domain)=@_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($zoneid > 0);
  db_query("SELECT h.id FROM hosts h ".
	   "WHERE h.zone=$zoneid AND domain='$domain';",\@q);
  return $q[0][0] if ($q[0][0] > 0);
  return 0;
}

=head1 FUNCTION: hostname_in_use

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub hostname_in_use($$) {
  my($zoneid,$hostname)=@_;
  my(@q,$domain);

  return RET_INVALID_ARGUMENT unless ($zoneid > 0);
  return RET_INVALID_ARGUMENT unless ($hostname =~ /^([A-Za-z0-9\-]+)(\.|$)/);
  $domain=$1;
  db_query("SELECT h.id FROM hosts h ".
#	   "WHERE h.zone=$zoneid AND domain ~* '^$domain(\\\\.|\$)';",\@q);
	   "WHERE h.zone=$zoneid AND domain ~* " . db_encode_str("^$domain(\\.|\$)") . ";",\@q);
  return $q[0][0] if ($q[0][0] > 0);
  return 0;
}

=head1 FUNCTION: new_sid

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub new_sid() {
  my(@q);

  db_query("SELECT NEXTVAL('sid_seq')",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

=head1 FUNCTION: get_host_network_settings

Get network configuration for a host IP address.

Parameters:
  serverid - Server ID
  ip       - IP address (CIDR format)
  rec      - Reference to hash for results

Returns:
  0  - Success, network settings retrieved (RET_OK)
 -3  - Invalid parameter (RET_INVALID_ARGUMENT)
 -2  - No network found for IP (RET_NOT_FOUND)
 -2  - Invalid network configuration (RET_NOT_FOUND)

=cut
sub get_host_network_settings($$$) {
  my($serverid,$ip,$rec) = @_;
  my(@q,$tmp,$net);

  return RET_INVALID_ARGUMENT unless (is_cidr($ip) && ($serverid > 0));
  $rec->{ip}=$ip; # IP

  db_query("SELECT n.id, n.name, n.net, v.vlanno, v.name " .
	   "FROM nets n left join vlans v on v.server = $serverid and n.vlan = v.id " .
	   "WHERE n.server = $serverid AND n.dummy = false AND '$ip' << n.net " .
	   "ORDER BY n.subnet, n.net",\@q);
  return RET_NOT_FOUND unless (@q > 0);
  return RET_NOT_FOUND unless ($q[$#q][0] > 0);
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

=head1 FUNCTION: get_record

Retrieve a single record from database table.

Parameters:
  table   - Table name
  fields  - Comma-separated field names
  key     - Key value to look up
  rec     - Hash reference for results
  keyname - Key field name (default: 'id')

Returns:
  0  - Record found and loaded (RET_OK)
 -2  - Record not found (RET_NOT_FOUND)

=cut
sub get_record($$$$$) {
  my ($table,$fields,$key,$rec,$keyname) = @_;
  my (@list,@q,$i,$val);

  $keyname='id' unless ($keyname);
  undef %{$rec};
  @list = split(",",$fields);
  $fields =~ s/\@//g;

  db_query("SELECT $fields FROM $table WHERE $keyname=".db_encode_str($key),
	   \@q);
  return RET_NOT_FOUND if (@q < 1);

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

=head1 FUNCTION: get_array_field

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_aml_field

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_field

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_field($$$$$) {
  my($table,$field,$rule,$tag,$rec)=@_;
  my(@list);

  db_query("SELECT $field FROM $table WHERE $rule",\@list);
  if ($#list >= 0) {
    $rec->{$tag}=$list[0][0];
  }
}

=head1 FUNCTION: update_array_field

Update array field records with insert/update/delete operations.

Parameters:
  table   - Table name
  count   - Field count
  fields  - Comma-separated field names
  keyname - Key field name in array
  rec     - Hash reference with array data
  vals    - Additional values for insert

Returns:
  0  - Success (RET_OK)
 -3  - Invalid table/hash/record (RET_INVALID_ARGUMENT)
 -2  - Database execution error (DB_ERR_EXECUTE)

The array format uses records with last element as operation flag:
  -1 = delete, 0 = unchanged, 1 = update, 2 = add

=cut
sub update_array_field($$$$$$) {
  my($table,$count,$fields,$keyname,$rec,$vals) = @_;
  my($list,$i,$j,$m,$str,$id,$flag,@f);

  return RET_INVALID_ARGUMENT unless ($table);
  return RET_INVALID_ARGUMENT unless (ref($rec) eq 'HASH');
  return RET_INVALID_ARGUMENT unless ($$rec{'id'} > 0);
  $list=$$rec{$keyname};
  return RET_OK unless (\$list);

  @f=split(",",$fields);

   for $i (1..$#{$list}) {
    $m=$$list[$i][$count];
    $id=$$list[$i][0];
    if ($m == -1) { # delete record
      $str="DELETE FROM $table WHERE id=$id";
      #print "<BR>DEBUG: delete record $id $str";
      if (db_exec($str) < 0) {
	  write2log("Delete failed: " . db_lasterrormsg());
	  return DB_ERR_EXECUTE;
      }
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
      if (db_exec($str) < 0) {
	  write2log("Update failed: " . db_lasterrormsg());
	  return DB_ERR_EXECUTE;
      }
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
      if (db_exec($str) < 0) {
	  write2log("Insert failed: " . db_lasterrormsg());
	  return DB_ERR_EXECUTE;
      }
    }
  }

  return RET_OK;
}

=head1 FUNCTION: update_aml_field

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub update_aml_field($$$$) {
    my($type,$ref,$rec,$keyname) = @_;
    return update_array_field("cidr_entries",7,
			      "mode,ip,acl,tkey,op,comment,type,ref",
			      $keyname,$rec,"$type,$ref");
}


=head1 FUNCTION: update_field

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub update_field($$$$$$) {
  my($table,$field,$rfields,$rvals,$tag,$rec) = @_;
  my(@rf,@rv,@q,$sqlstr,$i,$rule);

  return RET_INVALID_ARGUMENT unless (ref($rec) eq 'HASH');
  return RET_INVALID_ARGUMENT unless ($table && $field && $rfields && $rvals && $tag);
  @rf = split(",",$rfields);
  @rv = split(",",$rvals);
  return RET_INVALID_ARGUMENT unless (@rf == @rv);
  for $i (0..$#rf) {
    $rule.=" AND " if ($i > 0);
    $rule.=$rf[$i] . "=" . db_encode_str($rv[$i]);
  }

  $sqlstr = "SELECT $field FROM $table WHERE $rule";
  db_query($sqlstr,\@q);
  if (@q > 0) {
    unless ($rec->{$tag}) {
      $sqlstr = "DELETE FROM $table WHERE $rule";
      if (db_exec($sqlstr) < 0) {
	  write2log("Delete in update_field failed: " . db_lasterrormsg());
	  return DB_ERR_EXECUTE;
      }
    } else {
      if ($q[0][0] ne $rec->{$tag}) {
	$sqlstr = "UPDATE $table SET $field=".db_encode_str($rec->{$tag}).
	          " WHERE $rule";
	if (db_exec($sqlstr) < 0) {
	    write2log("Update in update_field failed: " . db_lasterrormsg());
	    return DB_ERR_EXECUTE;
	}
      }
    }
  } else {
    if ($rec->{$tag}) {
      $sqlstr = "INSERT INTO $table ($field,$rfields) " .
	        "VALUES(".db_encode_str($rec->{$tag}).",$rvals)";
      if (db_exec($sqlstr) < 0) {
	  write2log("Insert in update_field failed: " . db_lasterrormsg());
	  return DB_ERR_EXECUTE;
      }
    }
  }
  return RET_OK;
}

=head1 FUNCTION: add_array_field

Add multiple array field records to database.

Parameters:
  table    - Table name
  fields   - Comma-separated field names
  keyname  - Key field name for array
  rec      - Hash reference with array data
  rfields  - Required fields
  vals     - Required values

Returns:
  0  - Success (RET_OK)
 -3  - Invalid parameters (RET_INVALID_ARGUMENT)
 -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_array_field($$$$$$) {
  my($table,$fields,$keyname,$rec,$rfields,$vals) = @_;

  my($i,$j,$sqlstr,$flag,@f);

  return RET_INVALID_ARGUMENT unless (ref($rec) eq 'HASH');
  return RET_INVALID_ARGUMENT unless ($table && $keyname && $vals && $rfields);
  @f = split(",",$fields);
  return RET_INVALID_ARGUMENT unless (@f > 0);

  for $i (0..$#{$rec->{$keyname}}) {
    next if (@{$rec->{$keyname}->[$i]} <= 1);
    unless (@{$rec->{$keyname}->[$i]} >= (@f + 1)) {
	write2log("Array field size mismatch in add_array_field");
	return RET_INVALID_ARGUMENT;
    }
    $flag = 0;
    $sqlstr = "INSERT INTO $table ($fields,$rfields) VALUES(";
    for $j (1..($#f + 1)) {
      $sqlstr .= "," if ($flag);
      $sqlstr .= db_encode_str($rec->{$keyname}->[$i][$j]);
      $flag = 1;
    }
    $sqlstr .= ",$vals)";
    #print "<BR>DEBUG: add_array_field: insert record '$sqlstr'\n";
    if (db_exec($sqlstr) < 0) {
	write2log("Insert failed in add_array_field: " . db_lasterrormsg());
	return DB_ERR_EXECUTE;
    }
  }

  return RET_OK;
}

=head1 FUNCTION: update_record

Update database record with fields from hash.

Parameters:
  table - Table name
  rec   - Hash reference with 'id' and fields to update

Returns:
  >0  - Success: rows affected
  -3  - Invalid parameters (RET_INVALID_ARGUMENT)
  -2  - Database execution error (DB_ERR_EXECUTE)

=cut
sub update_record($$) {
  my ($table,$rec) = @_;
  my ($key,$sqlstr,$id,$flag,$r);

  return RET_INVALID_ARGUMENT unless ($table);
  return RET_INVALID_ARGUMENT unless (ref($rec) eq 'HASH');
  return RET_INVALID_ARGUMENT unless ($$rec{'id'} > 0);

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

  my $res = db_exec($sqlstr);
  if ($res < 0) {
      write2log("Update record '$id' in '$table' failed: " . db_lasterrormsg());
      return DB_ERR_EXECUTE;
  }
  return $res;
}


=head1 FUNCTION: add_record_sql

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: add_record

Add new record to database table.

Parameters:
  table - Table name
  rec   - Hash reference with record data

Returns:
  >0  - Success: new record ID (if table has 'id' column)
  0   - Success: record inserted (no 'id' column)
  -3  - Invalid parameters (RET_INVALID_ARGUMENT)
  -2  - Database error or no ID returned (DB_ERR_EXECUTE)

=cut
sub add_record($$) {
  my($table,$rec) = @_;
  my($sqlstr,$res,$oid,@q);
  my $flag; # ** 2018-09-25 TVu

  return RET_INVALID_ARGUMENT unless ($table);
  return RET_INVALID_ARGUMENT unless ($rec);

  $sqlstr=add_record_sql($table,$rec);
  if ($sqlstr eq '') {
      write2log("Cannot generate INSERT SQL for table '$table'");
      return RET_INVALID_ARGUMENT;
  }

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
  if ($res < 0) {
      write2log("Cannot insert record into '$table': " . db_lasterrormsg());
      return DB_ERR_EXECUTE;
  }

# $oid=db_lastoid(); ** Getting rid of OIDs 2018-09-25 TVu
# db_query("SELECT id FROM $table WHERE OID=$oid",\@q);
# return -2 if (@q < 1);
# return $q[0][0];

  return $flag ? db_lastid() : RET_OK; # ** Added 2018-09-25 TVu
}

=head1 FUNCTION: copy_records

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
    unless ($newref) {
      write2log("copy_records: Missing reference mapping for source id $data[$i][0]");
      return -1;
    }
    $data[$i][0]=$newref;
  }

  return db_insert($ttable,"$reffield,$fields",\@data);
}

=head1 FUNCTION: add_std_fields

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub add_std_fields($) {
  my($rec) = @_;

  return unless (ref($rec) eq 'HASH');

  $rec->{cdate_str}=($rec->{cdate} > 0 ?
		     localtime($rec->{cdate}).' by '.$rec->{cuser} : 'UNKOWN');
  $rec->{mdate_str}=($rec->{mdate} > 0 ?
		     localtime($rec->{mdate}).' by '.$rec->{muser} : '');
}

=head1 FUNCTION: del_std_fields

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
=head1 FUNCTION: update_textarea_field

Update textarea field with insert/update/delete.

Parameters:
  table   - Table name
  id      - Record ID or comma-separated IDs
  fields  - Field names
  keyname - Key field name
  rec     - Hash reference with record data
  vals    - Additional values

Returns:
  0  - Success (RET_OK)
 -3  - Invalid parameters (RET_INVALID_ARGUMENT)
 -2  - Database error (DB_ERR_EXECUTE)

=cut
sub update_textarea_field($$$$$$) { # Textarea 12 Apr 2017 TVu
    my($table, $id, $fields, $keyname, $rec, $vals) = @_;

    my($ind1, $sql, $field, @ids);

    return RET_INVALID_ARGUMENT unless ($table);
    return RET_INVALID_ARGUMENT unless (ref($rec) eq 'HASH');

# Delete old row(s), if any,
    @ids = split(/,/, $id);
    $sql = '';
    for $ind1 (@ids) {
	$sql .= "id = $ind1 or ";
    }
    if ($sql) {
	$sql =~ s/ or $//;
	$sql = "delete from $table where $sql;";
	if (db_exec($sql) < 0) {
	    write2log("Delete old textarea rows failed: " . db_lasterrormsg());
	    return DB_ERR_EXECUTE;
	}
    }

# Insert new row unless the textarea is empty. Use first old id, if any.
    my @arr;
    for my $ind1 (1..$#{$$rec{$keyname}}) {
	push(@arr, $$rec{$keyname}->[$ind1]->[1]);
    }
    $field = join("\n", @arr);
    if (!$field) { return RET_OK; }
    $sql = "insert into $table (" . ($ids[0] ? 'id,' : '') .
	" $fields) values (" . ($ids[0] ? "$ids[0]," : '') .
	" " . db_encode_str($field) . ", $vals);";
    if (db_exec($sql) < 0) {
	write2log("Insert new textarea row failed: " . db_lasterrormsg());
	return DB_ERR_EXECUTE;
    }

    return RET_OK;
}

############################################################################
# server table functions

=head1 FUNCTION: get_server_id

Get server ID by name.

Parameters:
  server - Server name

Returns:
  >0  - Server ID found
  -2  - Server not found (RET_NOT_FOUND)
  -3  - Invalid parameter (RET_INVALID_ARGUMENT)

=cut
sub get_server_id($) {
  my ($server) = @_;
  my (@q);

  return RET_INVALID_ARGUMENT unless ($server);
  $server=db_encode_str($server);
  db_query("SELECT id FROM servers WHERE name=$server",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}

=head1 FUNCTION: get_server_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_server

Retrieve server record with all associated data.

Parameters:
  id  - Server ID
  rec - Hash reference for results

Returns:
  0  - Success
 -2  - Record not found (RET_NOT_FOUND)

=cut
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
  return $res if ($res < 0);
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



=head1 FUNCTION: update_server

Update server record with all associated data in transaction.

Parameters:
  rec - Hash reference with server data

Returns:
  1   - Success (db_commit result)
  -2  - Database error during transaction (DB_ERR_EXECUTE)
  -3  - Invalid or conflicting data (RET_INVALID_ARGUMENT)

All errors cause automatic db_rollback().

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update servers table");
      return $r;
  }
  $id=$rec->{id};

  # allow_transfer
  $r=update_aml_field(1,$id,$rec,'allow_transfer');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update allow_transfer for server $id");
      return DB_ERR_EXECUTE;
  }
  # dhcp
# Local DHCP settings 2020-07-20 TVu
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp_l',$rec,
		        "7,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update dhcp_l for server $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp',$rec,
		        "1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update dhcp for server $id");
      return DB_ERR_EXECUTE;
  }
  # dhcp6
# Local DHCP settings 2020-07-20 TVu
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp6_l',$rec,
		        "17,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update dhcp6_l for server $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",'dhcp6',$rec,
		        "11,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update dhcp6 for server $id");
      return DB_ERR_EXECUTE;
  }
  # txt
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			'txt',$rec,"3,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update txt entries for server $id");
      return DB_ERR_EXECUTE;
  }
  # allow_query
  $r=update_aml_field(7,$id,$rec,'allow_query');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update allow_query for server $id");
      return DB_ERR_EXECUTE;
  }
  # allow_recursion
  $r=update_aml_field(8,$id,$rec,'allow_recursion');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update allow_recursion for server $id");
      return DB_ERR_EXECUTE;
  }
  # blackhole
  $r=update_aml_field(9,$id,$rec,'blackhole');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update blackhole for server $id");
      return DB_ERR_EXECUTE;
  }
  # listen_on
  $r=update_aml_field(10,$id,$rec,'listen_on');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update listen_on for server $id");
      return DB_ERR_EXECUTE;
  }
  #
  #$r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
  #  		'listen_on',$rec,"10,$id");
  #if ($r < 0) { db_rollback(); return -18; }
  # forwarder
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			 'forwarders',$rec,"11,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update forwarders for server $id");
      return DB_ERR_EXECUTE;
  }
  # logging (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'logging',$rec,"10,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update logging for server $id");
      return DB_ERR_EXECUTE;
  }
  # custom options (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'custom_opts',$rec,"11,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update custom_opts for server $id");
      return DB_ERR_EXECUTE;
  }
  # Globals (BIND)
  $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			 'bind_globals',$rec,"13,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update bind_globals for server $id");
      return DB_ERR_EXECUTE;
  }

  # allow_query_cache
  $r=update_aml_field(14,$id,$rec,'allow_query_cache');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update allow_query_cache for server $id");
      return DB_ERR_EXECUTE;
  }

  # allow_notify
  $r=update_aml_field(15,$id,$rec,'allow_notify');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update allow_notify for server $id");
      return DB_ERR_EXECUTE;
  }

  # listen_on_v6
  $r=update_aml_field(16,$id,$rec,'listen_on_v6');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_server: Failed to update listen_on_v6 for server $id");
      return DB_ERR_EXECUTE;
  }


  return db_commit();
}

=head1 FUNCTION: add_server

Add new server record with all associated data in transaction.

Parameters:
  rec - Hash reference with server data (cdate, cuser auto-set)

Returns:
  server_id - Positive integer on success (new server ID)
  -2         - Database error during transaction (DB_ERR_EXECUTE)
  -3         - Invalid or conflicting data (RET_INVALID_ARGUMENT)

On success, returns new server ID. On error, db_rollback() is called.

=cut
sub add_server($) {
  my($rec) = @_;
  my($res,$id);

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  db_begin();
  $res = add_record('servers',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to insert servers record");
      return DB_ERR_EXECUTE;
  }
  $rec->{id}=$id=$res;

  # allow_transfer
  $res = update_aml_field(1,$id,$rec,'allow_transfer');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set allow_transfer for new server $id");
      return DB_ERR_EXECUTE;
  }
  # dhcp
# Local DHCP settings 2020-07-20 TVu
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp_l',$rec,
			 'type,ref',"7,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add dhcp_l entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add dhcp entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # dhcp6
# Local DHCP settings 2020-07-20 TVu
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6_l',$rec,
			 'type,ref',"17,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add dhcp6_l entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add dhcp6 entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # txt
  $res = add_array_field('txt_entries','txt,comment','txt',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add txt entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # allow_query
  $res = update_aml_field(7,$id,$rec,'allow_query');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set allow_query for new server $id");
      return DB_ERR_EXECUTE;
  }
  # allow_recursion
  $res = update_aml_field(8,$id,$rec,'allow_recursion');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set allow_recursion for new server $id");
      return DB_ERR_EXECUTE;
  }
  # blackhole
  $res = update_aml_field(9,$id,$rec,'blackhole');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set blackhole for new server $id");
      return DB_ERR_EXECUTE;
  }
  # listen_on
  $res = add_array_field('cidr_entries','ip,comment','listen_on',$rec,
			 'type,ref',"10,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add listen_on entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # forwarders
  $res = add_array_field('cidr_entries','ip,comment','forwarders',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add forwarders entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # logging
  $res = add_array_field('txt_entries','txt,comment','logging',$rec,
			 'type,ref',"10,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add logging entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # custom options
  $res = add_array_field('txt_entries','txt,comment','custom_opts',$rec,
			 'type,ref',"11,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add custom_opts entries for new server $id");
      return DB_ERR_EXECUTE;
  }
  # bind globals
  $res = add_array_field('txt_entries','txt,comment','bind_globals',$rec,
			 'type,ref',"13,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to add bind_globals entries for new server $id");
      return DB_ERR_EXECUTE;
  }

  # allow_query_cache
  $res = update_aml_field(14,$id,$rec,'allow_query_cache');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set allow_query_cache for new server $id");
      return DB_ERR_EXECUTE;
  }

  # allow_notify
  $res = update_aml_field(15,$id,$rec,'allow_notify');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_server: Failed to set allow_notify for new server $id");
      return DB_ERR_EXECUTE;
  }


  if (db_commit() < 0) { 
      write2log("add_server: Transaction commit failed for new server $id");
      return DB_ERR_EXECUTE;
  }
  return $id;
}

=head1 FUNCTION: _delete_server_parts

Internal helper: Delete all database entries associated with a server record.

Parameters:
  id - Server ID to delete dependencies for

Returns:
  -2 - Database error during deletion (DB_ERR_EXECUTE)
       see write2log for context on which operation failed

Calls db_rollback() on any error.

=cut
sub _delete_server_parts($) {
  my($id) = @_;
  my($res);

  # cidr_entries
  $res=db_exec("DELETE FROM cidr_entries " .
               "WHERE (type=1 OR type=7 OR type=8 OR type=9 OR type=10 " .
               " OR type=11) AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete cidr_entries (type 1,7,8,9,10,11)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM cidr_entries WHERE id IN ( " .
               "SELECT a.id FROM cidr_entries a, zones z " .
               "WHERE z.server=$id AND " .
               " (a.type=12 OR a.type=6 OR a.type=5 OR a.type=4 OR " .
               "  a.type=3 OR a.type=2) " .
               " AND a.ref=z.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete zone-related cidr_entries");
      return DB_ERR_EXECUTE;
  }

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE (type=7 OR type=1 OR type=17 OR type=11) AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete server dhcp_entries");
      return DB_ERR_EXECUTE;
  }
  
  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
               "SELECT a.id FROM dhcp_entries a, zones z " .
               "WHERE z.server=$id AND a.type=2 AND a.ref=z.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete zone dhcp_entries (type 2)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
               "SELECT a.id FROM dhcp_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.type=3 " .
               " AND a.ref=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete host dhcp_entries (type 3)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
               "SELECT a.id FROM dhcp_entries a, nets n " .
               "WHERE n.server=$id AND a.type=4 AND a.ref=n.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete net dhcp_entries (type 4)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
               "SELECT a.id FROM dhcp_entries a, groups g " .
               "WHERE g.server=$id AND a.type=5 AND a.ref=g.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete group dhcp_entries (type 5)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
               "SELECT a.id FROM dhcp_entries a, vlans v " .
               "WHERE v.server=$id AND a.type=6 AND a.ref=v.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete vlan dhcp_entries (type 6)");
      return DB_ERR_EXECUTE;
  }

  # txt_entries
  $res=db_exec("DELETE FROM txt_entries " .
               "WHERE (type=3 OR type=10 OR type=11) AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete server txt_entries");
      return DB_ERR_EXECUTE;
  }

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
               "SELECT a.id FROM mx_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete host mx_entries (type 2)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
               "SELECT a.id FROM mx_entries a, zones z, mx_templates m " .
               "WHERE z.server=$id AND m.zone=z.id AND a.type=3 AND a.ref=m.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete mx_template mx_entries (type 3)");
      return DB_ERR_EXECUTE;
  }

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
               "SELECT a.id FROM wks_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.type=1 AND a.ref=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete host wks_entries (type 1)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " .
               "SELECT a.id FROM wks_entries a, wks_templates w " .
               "WHERE w.server=$id AND a.type=2 AND a.ref=w.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete wks_template wks_entries (type 2)");
      return DB_ERR_EXECUTE;
  }

  # ns_entries
  $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " .
               "SELECT a.id FROM ns_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete host ns_entries (type 2)");
      return DB_ERR_EXECUTE;
  }

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
               "SELECT a.id FROM printer_entries a, groups g " .
               "WHERE g.server=$id AND a.type=1 AND a.ref=g.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete group printer_entries (type 1)");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
               "SELECT a.id FROM printer_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.type=2 AND a.ref=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete host printer_entries (type 2)");
      return DB_ERR_EXECUTE;
  }

  # a_entries
  $res=db_exec("DELETE FROM a_entries WHERE id IN ( " .
               "SELECT a.id FROM a_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete a_entries");
      return DB_ERR_EXECUTE;
  }

  # arec_entries
  $res=db_exec("DELETE FROM arec_entries WHERE id IN ( " .
               "SELECT a.id FROM arec_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete arec_entries");
      return DB_ERR_EXECUTE;
  }

  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete srv_entries");
      return DB_ERR_EXECUTE;
  }

  # group_entries
  $res=db_exec("DELETE FROM group_entries WHERE id IN ( " .
               "SELECT a.id FROM group_entries a, zones z, hosts h " .
               "WHERE z.server=$id AND h.zone=z.id AND a.host=h.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete group_entries");
      return DB_ERR_EXECUTE;
  }

  # wks_templates
  $res=db_exec("DELETE FROM wks_templates WHERE server=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete wks_templates");
      return DB_ERR_EXECUTE;
  }

  # mx_templates
  $res=db_exec("DELETE FROM mx_templates WHERE id IN ( " .
               "SELECT a.id FROM mx_templates a, zones z " .
               "WHERE z.server=$id AND a.zone=z.id);");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete mx_templates");
      return DB_ERR_EXECUTE;
  }

  # groups
  $res=db_exec("DELETE FROM groups WHERE server=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete groups");
      return DB_ERR_EXECUTE;
  }

  # nets
  $res=db_exec("DELETE FROM nets WHERE server=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete nets");
      return DB_ERR_EXECUTE;
  }

  # vlans
  # Poznámka: VLAN nejsou smazány, pouze zóny a jejich obsah
  # To odpovídá původní logice

  # server itself
  $res=db_exec("DELETE FROM servers WHERE id=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("_delete_server_parts: Failed to delete servers record");
      return DB_ERR_EXECUTE;
  }

  return RET_OK;
}


=head1 FUNCTION: delete_server

Delete server record and all associated data in cascading transaction.

Parameters:
  id - Server ID to delete

Returns:
  0   - Success (db_commit() result)
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -2  - Database error during deletion (DB_ERR_EXECUTE) 
  -4  - Transaction commit failed (RET_PERMISSION_DENIED / DB_ERR_EXECUTE)

On failure, db_rollback() is called. Details logged via write2log().

=cut
sub delete_server($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  write2log("SERVER_DELETE_START: Deleting server ID=$id");
  db_begin();

  # get all zones of server
  my @zone_ids;
  my @q;
  db_query("SELECT id FROM zones WHERE server=$id", \@q);
  for my $i (0..$#q) {
      push @zone_ids, $q[$i][0];
  }

  # Delete all zones of server
  for my $zone_id (@zone_ids) {
      $res = _delete_zone_parts($zone_id);
      if ($res < 0) {
          db_rollback();
          write2log("SERVER_DELETE_FAILED: Server ID=$id was NOT deleted - failure to delete zone ID=$zone_id with error $res");
          return $res;
      }
  }


  # Delete other parts of server
  $res = _delete_server_parts($id);
  if ($res < 0) {
    db_rollback();
    write2log("SERVER_DELETE_FAILED: Server ID=$id was NOT deleted - failure to delete server parts with error $res");
    return $res;
  }
  if (db_commit() < 0) {
    write2log("SERVER_DELETE_FAILED: Server ID=$id was NOT deleted - commit failure");
    return DB_ERR_EXECUTE;
  }

  write2log("SERVER_DELETE_SUCCESS: Server ID=$id successfully deleted");

  return RET_OK;
}

############################################################################
# zone table functions

=head1 FUNCTION: get_zone_id

Get zone database ID by zone name and server.

Parameters:
  zone     - Zone name to look up
  serverid - Server ID containing the zone

Returns:
  zone_id - Positive integer zone ID on success
  -3      - Invalid parameters (RET_INVALID_ARGUMENT)
  -2      - Zone not found (RET_NOT_FOUND)

=cut
sub get_zone_id($$) {
  my ($zone,$serverid) = @_;
  my (@q);

  return RET_INVALID_ARGUMENT unless ($zone && $serverid > 0);
  $zone = db_encode_str($zone);
  db_query("SELECT id FROM zones WHERE server=$serverid AND name=$zone",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}

=head1 FUNCTION: get_zone_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_zone_list2

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_zone

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_zone($$) {
  my ($id,$rec) = @_;
  my ($res,@q,$hid,$sid);

  $res = get_record("zones",
	       "server,active,dummy,type,reverse,class,name,nnotify," .
	       "hostmaster,serial,refresh,retry,expire,minimum,ttl," .
	       "chknames,reversenet,comment,cdate,cuser,mdate,muser," .
	       "forward,serial_date,flags,rdate,transfer_source,transfer_source_v6,expiration",
	       $id,$rec,"id");
  if ($res < 0) {
    write2log("get_zone: Failed to load zone id=$id");
    return -1;
  }
  fix_bools($rec,"active,dummy,reverse,noreverse");
  $sid=$rec->{server};

  if ($rec->{type} eq 'M' || $rec->{type} eq 'C') {
    $hid=get_host_id($id,'@');
    if ($hid > 0) {
      get_array_field("ns_entries",3,"id,ns,comment","NS,Comments",
		      "type=2 AND ref=$hid ORDER BY ns",$rec,'ns');

      # For non-catalog zones, also load MX, TXT, NAPTR and IP records
      if ($rec->{type} eq 'M') {
        get_array_field("mx_entries",4,"id,pri,mx,comment",
		        "Priority,MX,Comments",
		        "type=2 AND ref=$hid ORDER BY pri,mx",$rec,'mx');
        get_array_field("txt_entries",3,"id,txt,comment","TXT,Comments",
		        "type=2 AND ref=$hid ORDER BY id",$rec,'txt');
        get_array_field("naptr_entries",8,"id,order_val,preference,flags,service,regexp,replacement,comment",
		        "Order,Preference,Flags,Service,Regexp,Replacement,Comments",
		        "type=1 AND ref=$hid ORDER BY order_val,preference,flags,service,regexp,replacement",$rec,'naptr');
        get_array_field("a_entries",4,"id,ip,reverse,forward",
		        "IP,reverse,forward","host=$hid ORDER BY ip",$rec,'ip');
      }

      $rec->{zonehostid}=$hid;
    } else {
      # Initialize empty NS array if host record missing (for catalog zones)
      # This ensures the form can still be edited
      $rec->{ns} = [['NS','Comments']];  # Header row
      if ($rec->{type} eq 'M') {
        $rec->{mx} = [['Priority','MX','Comments']];
        $rec->{txt} = [['TXT','Comments']];
        $rec->{naptr} = [['Order','Preference','Flags','Service','Regexp','Replacement','Comments']];
        $rec->{ip} = [['IP','reverse','forward']];
      }
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

  # Catalog zones support (RFC 9432)
  if ($rec->{type} eq 'C') {
    # Zone is a catalog - load its members
    my $rec_catalogs = {};
    get_zone_catalog_members($id, $rec_catalogs);
    $rec->{catalog_members} = $rec_catalogs->{members};
    $rec->{catalog_member_count} = $rec_catalogs->{count};

    # Format member zones list for display
    if ($rec_catalogs->{count} > 0) {
      my @member_list;
      # Type names mapping
      my %zone_type_names = (M=>'Master', S=>'Slave', F=>'Forward', H=>'Hint', C=>'Catalog');
      for my $member (@{$rec_catalogs->{members}}) {
        my $zone_name = $member->[1];    # zone name
        my $zone_type = $member->[2];    # zone type (M, S, F, H, C)
        my $server_name = $member->[4];  # server name
        my $type_label = $zone_type_names{$zone_type} || $zone_type;  # Get readable type name
        #push @member_list, "$zone_name ($type_label at $server_name)";
        push @member_list, "$zone_name ($type_label)";
      }
      $rec->{catalog_members_list} = join(', ', @member_list);
    } else {
      $rec->{catalog_members_list} = 'None';
    }
  } else {
    # Zone is a regular zone - load which catalogs contain it
    my $rec_cats = {};
    get_zone_catalogs($id, $rec_cats);
    $rec->{zone_catalogs} = $rec_cats->{catalogs};
    $rec->{zone_catalog_count} = $rec_cats->{count};

    # Format catalog list for display
    if ($rec_cats->{count} > 0) {
      my @catalog_list;
      for my $cat (@{$rec_cats->{catalogs}}) {
        push @catalog_list, $cat->[1];  # zone name
      }
      $rec->{zone_catalogs_list} = join(', ', sort @catalog_list);
    } else {
      $rec->{zone_catalogs_list} = 'None';
    }

    # For Master zones, load available catalogs for selection
    if ($rec->{type} eq 'M') {
      my $rec_sel = {};
      get_catalog_zones_for_selection($id, $sid, $rec_sel);
      $rec->{available_catalogs} = $rec_sel->{available_catalogs};
      $rec->{catalog_zones_selected} = $rec_sel->{catalog_zones_selected};
    }
  }

  $rec->{txt_auto_generation}=($rec->{flags} & 0x01 ? 1 : 0);

  add_std_fields($rec);
  return 0;
}

=head1 FUNCTION: update_zone

Update zone record with all associated DNS data in transaction.

Parameters:
  rec - Hash reference with zone data

Returns:
  1   - Success (db_commit() result)
  -3  - Invalid zone data (RET_INVALID_ARGUMENT)
  -2  - Database error during transaction (DB_ERR_EXECUTE)

All database errors cause automatic db_rollback(). Details logged via write2log().

=cut
sub update_zone($) {
  my($rec) = @_;
  my($r,$id,$new_net,$hid);
  my(@current_catalogs, @new_catalogs, %new_cat_hash, %current_cat_hash);

  del_std_fields($rec);
  delete $rec->{pending_info};
  delete $rec->{zonehostid};

  # Catalog zones support - save before cleanup
  my $selected_catalogs = $rec->{catalog_zones_selected} || [];

  # Catalog zones support - clean up before update
  delete $rec->{catalog_members};
  delete $rec->{catalog_member_count};
  delete $rec->{catalog_members_list};
  delete $rec->{zone_catalogs};
  delete $rec->{zone_catalog_count};
  delete $rec->{zone_catalogs_list};
  delete $rec->{available_catalogs};
  delete $rec->{catalog_zones_selected};
  delete $rec->{catalog_zones_selected_links};

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
	  write2log("update_zone: Invalid reverse zone CIDR: " . $rec->{name});
	  return RET_INVALID_ARGUMENT;
      }
      $rec->{reversenet}=$new_net;
  }

  db_begin();
  $id=$rec->{id};

  $r=update_record('zones',$rec);
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update zones record for zone $id");
      return $r;
  }

  if (!$rec->{type}) {
      db_rollback();
      write2log("update_zone: Zone type not set for zone $id");
      return RET_INVALID_ARGUMENT;
  }

  if ($rec->{type} eq 'M' || $rec->{type} eq 'C') {
    $hid=get_host_id($id,'@');

    # If host record doesn't exist for catalog or master zone, create it
    if ($hid <= 0) {
      if ($rec->{type} eq 'C') {
        # For catalog zones, create the @ host record if missing
        $hid = add_record('hosts',{zone=>$id,type=>10,domain=>'@',
                                   comment=>'zone record'});
        if ($hid < 0) { db_rollback(); return DB_ERR_EXECUTE; }
      } else {
        # For master zones, this should not happen - it's an error
        db_rollback();
        write2log("update_zone: Master zone missing @ host record for zone $id");
        return DB_ERR_EXECUTE;
      }
    }

    # For catalog zones, only update NS records
    # For master zones, update all record types
    if ($rec->{type} eq 'M') {
      $r=update_array_field("a_entries",4,"ip,reverse,forward,host",
			    'ip',$rec,"$hid");
      if ($r < 0) { 
          db_rollback(); 
          write2log("update_zone: Failed to update a_entries for zone $id");
          return DB_ERR_EXECUTE;
      }

      $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			    'mx',$rec,"2,$hid");
      if ($r < 0) { 
          db_rollback(); 
          write2log("update_zone: Failed to update mx_entries for zone $id");
          return DB_ERR_EXECUTE;
      }
      $r=update_array_field("txt_entries",3,"txt,comment,type,ref",
			    'txt',$rec,"2,$hid");
      if ($r < 0) { 
          db_rollback(); 
          write2log("update_zone: Failed to update txt_entries for zone $id");
          return DB_ERR_EXECUTE;
      }
      $r=update_array_field("naptr_entries",7,"order_val,preference,flags,service,regexp,replacement,comment,type,ref",
			    'naptr',$rec,"1,$hid");
      if ($r < 0) { 
          db_rollback(); 
          write2log("update_zone: Failed to update naptr_entries for zone $id");
          return DB_ERR_EXECUTE;
      }
    }

    # NS records for both Master and Catalog zones
    $r=update_array_field("ns_entries",3,"ns,comment,type,ref",
			  'ns',$rec,"2,$hid");
    if ($r < 0) { 
        db_rollback(); 
        write2log("update_zone: Failed to update ns_entries for zone $id");
        return DB_ERR_EXECUTE;
    }
  }

  # dhcp
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp',$rec,"2,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update dhcp_entries for zone $id");
      return DB_ERR_EXECUTE;
  }

  # allow_update
  $r=update_aml_field(2,$id,$rec,'allow_update');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update allow_update for zone $id");
      return DB_ERR_EXECUTE;
  }
  # masters
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'masters',$rec,"3,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update masters for zone $id");
      return DB_ERR_EXECUTE;
  }
  # allow_query
  $r=update_aml_field(4,$id,$rec,'allow_query');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update allow_query for zone $id");
      return DB_ERR_EXECUTE;
  }
  # allow_transfer
  $r=update_aml_field(5,$id,$rec,'allow_transfer');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update allow_transfer for zone $id");
      return DB_ERR_EXECUTE;
  }
  # also_notify
  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
			'also_notify',$rec,"6,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update also_notify for zone $id");
      return DB_ERR_EXECUTE;
  }
  # forwarders
#  $r=update_array_field("cidr_entries",3,"ip,comment,type,ref",
#			'forwarders',$rec,"12,$id");
  $r=update_array_field("cidr_entries",4,"ip,port,comment,type,ref",
			'forwarders',$rec,"12,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update forwarders for zone $id");
      return DB_ERR_EXECUTE;
  }

  $r=update_array_field("txt_entries",2,"txt,type,ref", # 2020-07-30 TVu
			'zentries_ta',$rec,"4,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update zentries_ta for zone $id");
      return DB_ERR_EXECUTE;
  }

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

  if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to update zentries for zone $id");
      return DB_ERR_EXECUTE;
  }

  # Process catalog zone selection changes
  if ($rec->{type} eq 'M' && $id > 0) {
    # Get current catalogs for this zone
    my @current_catalogs = ();
    my @q;
    $r = db_query("SELECT catalog_zone_id FROM zone_catalogs " .
             "WHERE member_zone_id = $id", \@q);
    if ($r < 0) { 
      db_rollback(); 
      write2log("update_zone: Failed to query current catalogs for zone $id: $r");
      return DB_ERR_EXECUTE;
    }
    for my $row (@q) {
      push @current_catalogs, $row->[0];
    }
    my $curr_debug = join(",", @current_catalogs);

    # Get new catalogs from form submission
    my @new_catalogs = ();
    if (ref($selected_catalogs) eq 'ARRAY') {
      @new_catalogs = @{$selected_catalogs};
      # Ensure they are numeric IDs
      @new_catalogs = map { int($_) } @new_catalogs;
      my $new_debug = join(",", @new_catalogs);
    }

    # Build hashes for comparison
    my %current_hash = map { $_ => 1 } @current_catalogs;
    my %new_hash = map { $_ => 1 } @new_catalogs;

    # Remove catalogs that are no longer selected
    for my $cat_id (@current_catalogs) {
      unless ($new_hash{$cat_id}) {
        $r = remove_zone_from_catalog($id, $cat_id);
        if ($r < 0) { 
            db_rollback(); 
            write2log("update_zone: Failed to remove zone from catalog $cat_id");
            return DB_ERR_EXECUTE;
        }
      }
    }

    # Add catalogs that are newly selected
    for my $cat_id (@new_catalogs) {
      unless ($current_hash{$cat_id}) {
        $r = add_zone_to_catalog($id, $cat_id);
        if ($r < 0 && $r != -10) { 
            db_rollback(); 
            write2log("update_zone: Failed to add zone to catalog $cat_id");
            return DB_ERR_EXECUTE;
        }  # -10 means already exists, which is ok
      }
    }
  }

  return db_commit();
}

# Internal helper function for deleting part of a zone (without transaction)
# Called from delete_zone() and delete_server()
=head1 FUNCTION: _delete_zone_parts

Internal helper: Delete all database entries associated with a zone record.

Parameters:
  id - Zone ID to delete dependencies for

Returns:
  -2 - Database error during deletion (DB_ERR_EXECUTE)
       see write2log for context on which operation failed
  0  - Success (RET_OK)

Does NOT call db_rollback() - called by functions that manage transactions.

=cut
sub _delete_zone_parts($) {
    my($id) = @_;
    my($res);

    # cidr_entries
    $res=db_exec("DELETE FROM cidr_entries WHERE " .
                 "(type=2 OR type=3 OR type=4 OR type=5 OR type=6 OR " .
                 " type=12 OR type=13) " .
                 " AND ref=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete zone cidr_entries");
        return DB_ERR_EXECUTE;
    }

    # dhcp_entries
    $res=db_exec("DELETE FROM dhcp_entries WHERE type=2 AND ref=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete zone dhcp_entries (type 2)");
        return DB_ERR_EXECUTE;
    }
    $res=db_exec("DELETE FROM dhcp_entries WHERE id IN ( " .
                 "SELECT a.id FROM dhcp_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=3 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete host dhcp_entries (type 3)");
        return DB_ERR_EXECUTE;
    }
    
    # mx_entries
    $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
                 "SELECT a.id FROM mx_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete host mx_entries (type 2)");
        return DB_ERR_EXECUTE;
    }
    $res=db_exec("DELETE FROM mx_entries WHERE id IN ( " .
                 "SELECT a.id FROM mx_entries a, mx_templates m " .
                 "WHERE m.zone=$id AND a.type=3 AND a.ref=m.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete mx_template mx_entries (type 3)");
        return DB_ERR_EXECUTE;
    }
    
    # wks_entries
    $res=db_exec("DELETE FROM wks_entries WHERE id IN ( " . 
                 "SELECT a.id FROM wks_entries a, hosts h " . 
                 "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete wks_entries");
        return DB_ERR_EXECUTE;
    }

    # ns_entries
    $res=db_exec("DELETE FROM ns_entries WHERE id IN ( " . 
                 "SELECT a.id FROM ns_entries a, hosts h " . 
                 "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete ns_entries");
        return DB_ERR_EXECUTE;
    }
        
    # printer_entries
    $res=db_exec("DELETE FROM printer_entries WHERE id IN ( " .
                 "SELECT a.id FROM printer_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete printer_entries");
        return DB_ERR_EXECUTE;
    }
    
    # txt_entries
    $res=db_exec("DELETE FROM txt_entries WHERE (type=4 OR type=12) AND ref=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete zone txt_entries (type 4,12)");
        return DB_ERR_EXECUTE;
    }
    $res=db_exec("DELETE FROM txt_entries WHERE id IN ( " .
                 "SELECT a.id FROM txt_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=2 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete host txt_entries (type 2)");
        return DB_ERR_EXECUTE;
    }

    # a_entries
    $res=db_exec("DELETE FROM a_entries WHERE id IN ( " .
                 "SELECT a.id FROM a_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.host=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete a_entries");
        return DB_ERR_EXECUTE;
    }

    # arec_entries
    $res=db_exec("DELETE FROM arec_entries WHERE id IN ( " .
                 "SELECT a.id FROM arec_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.host=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete arec_entries");
        return DB_ERR_EXECUTE;
    }

    # mx_templates
    $res=db_exec("DELETE FROM mx_templates WHERE zone=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete mx_templates");
        return DB_ERR_EXECUTE;
    }

    # srv_entries
    $res=db_exec("DELETE FROM srv_entries WHERE id IN ( " .
                 "SELECT a.id FROM srv_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete srv_entries");
        return DB_ERR_EXECUTE;
    }

    # sshfp_entries
    $res=db_exec("DELETE FROM sshfp_entries WHERE id IN ( " .
                 "SELECT a.id FROM sshfp_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete sshfp_entries");
        return DB_ERR_EXECUTE;
    }

    # tlsa_entries
    $res=db_exec("DELETE FROM tlsa_entries WHERE id IN ( " .
                 "SELECT a.id FROM tlsa_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete tlsa_entries");
        return DB_ERR_EXECUTE;
    }

    # naptr_entries
    $res=db_exec("DELETE FROM naptr_entries WHERE id IN ( " .
                 "SELECT a.id FROM naptr_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.type=1 AND a.ref=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete naptr_entries");
        return DB_ERR_EXECUTE;
    }

    # group_entries
    $res=db_exec("DELETE FROM group_entries WHERE id IN ( " .
                 "SELECT a.id FROM group_entries a, hosts h " .
                 "WHERE h.zone=$id AND a.host=h.id)");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete group_entries");
        return DB_ERR_EXECUTE;
    }

    # hosts
    $res=db_exec("DELETE FROM hosts WHERE zone=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete hosts for zone $id");
        return DB_ERR_EXECUTE;
    }

    # zone record
    $res=db_exec("DELETE FROM zones WHERE id=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete zones record");
        return DB_ERR_EXECUTE;
    }

    # user_rights
    $res=db_exec("DELETE FROM user_rights WHERE (rtype=2 OR rtype=4 " .
                 "OR rtype=9 OR rtype=10 OR rtype=11) AND rref=$id");
    if ($res < 0) { 
        write2log("_delete_zone_parts: Failed to delete user_rights");
        return DB_ERR_EXECUTE;
    }

    return RET_OK;
}

=head1 FUNCTION: delete_zone

Delete zone record and all associated data in cascading transaction.

Parameters:
  id - Zone ID to delete

Returns:
  0   - Success (RET_OK)
  -3  - Invalid zone ID (RET_INVALID_ARGUMENT)
  -2  - Database error during deletion (DB_ERR_EXECUTE)

On failure, db_rollback() is called. Details logged via write2log().

=cut
sub delete_zone($) {
    my($id) = @_;
    my($res);

    return RET_INVALID_ARGUMENT unless ($id > 0);

    write2log("ZONE_DELETE_START: Deleting zone ID=$id");
    db_begin();

    $res = _delete_zone_parts($id);
    if ($res < 0) {
        db_rollback();
        write2log("ZONE_DELETE_FAILED: Zone ID=$id WAS NOT deleted - error $res");
        return $res;
    }

    if (db_commit() < 0) {
        write2log("ZONE_DELETE_FAILED: Zone ID=$id WAS NOT deleted - commit failure");
        return DB_ERR_EXECUTE;
    }

    write2log("ZONE_DELETE_SUCCESS: Zone ID=$id successfully deleted");
    return RET_OK;
}

=head1 FUNCTION: add_zone

Add new zone record with all associated DNS data in transaction.

Parameters:
  rec - Hash reference with zone data (cdate, cuser auto-set)

Returns:
  zone_id - Positive integer on success (new zone ID)
  -3      - Invalid zone data (RET_INVALID_ARGUMENT)
  -2      - Database error during transaction (DB_ERR_EXECUTE)

On success, returns new zone ID. On error, db_rollback() is called.

=cut
sub add_zone($) {
  my($rec) = @_;
  my($new_net,$res,$id,$hid,$transfer_src);

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  if ($rec->{reverse} =~ /^(t|true)$/) {
      $new_net=arpa2cidr($rec->{name});
      if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
	  write2log("add_zone: Invalid reverse zone CIDR: " . $rec->{name});
	  return RET_INVALID_ARGUMENT;
      }
      $rec->{reversenet}=$new_net;
  }

  db_begin();
  $res = add_record('zones',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to insert zones record");
      return DB_ERR_EXECUTE;
  }
  $rec->{id}=$id=$res;


  if ($rec->{type} eq 'M' || $rec->{type} eq 'C') {
    # zone's host record (@)
    $res = add_record('hosts',{zone=>$id,type=>10,domain=>'@',
			       comment=>'zone record'});
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_zone: Failed to add @ host record for new zone $id");
        return DB_ERR_EXECUTE;
    }
    $hid=$res;

    # ns - for both Master and Catalog zones
    $res = add_array_field('ns_entries','ns,comment','ns',$rec,
			   'type,ref',"2,$hid");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_zone: Failed to add ns_entries for new zone $id");
        return DB_ERR_EXECUTE;
    }

    # For Master zones only
    if ($rec->{type} eq 'M') {
      # mx
      $res = add_array_field('mx_entries','pri,mx,comment','mx',$rec,
			     'type,ref',"2,$hid");
      if ($res < 0) { 
          db_rollback(); 
          write2log("add_zone: Failed to add mx_entries for new zone $id");
          return DB_ERR_EXECUTE;
      }
      # txt
      $res = add_array_field('txt_entries','txt,comment','txt',$rec,
			     'type,ref',"2,$hid");
      if ($res < 0) { 
          db_rollback(); 
          write2log("add_zone: Failed to add txt_entries for new zone $id");
          return DB_ERR_EXECUTE;
      }
      # naptr
      $res = add_array_field('naptr_entries','order_val,preference,flags,service,regexp,replacement,comment',
			     'naptr',$rec,'type,ref',"1,$hid");
      if ($res < 0) { 
          db_rollback(); 
          write2log("add_zone: Failed to add naptr_entries for new zone $id");
          return DB_ERR_EXECUTE;
      }
      # ip
      $res = add_array_field('a_entries','ip,reverse,forward','ip',$rec,
			     'host',"$hid");
      if ($res < 0) { 
          db_rollback(); 
          write2log("add_zone: Failed to add a_entries for new zone $id");
          return DB_ERR_EXECUTE;
      }
    }
  }

  # dhcp
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to add dhcp_entries for new zone $id");
      return DB_ERR_EXECUTE;
  }

  # allow_update
  $res = update_aml_field(2,$id,$rec,'allow_update');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to set allow_update for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # masters
  $res = add_array_field('cidr_entries','ip,comment','masters',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to add masters for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # allow_query
  $res = update_aml_field(4,$id,$rec,'allow_query');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to set allow_query for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # allow_transfer
  $res = update_aml_field(5,$id,$rec,'allow_transfer');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to set allow_transfer for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # also_notify
  $res = add_array_field('cidr_entries','ip,comment','also_notify',$rec,
			 'type,ref',"6,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to add also_notify for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # forwarders
  $res = add_array_field('cidr_entries','ip,comment','forwarders',$rec,
			 'type,ref',"12,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to add forwarders for new zone $id");
      return DB_ERR_EXECUTE;
  }
  # zentries
  $res = add_array_field('txt_entries','txt,comment','zentries',$rec,
			 'type,ref',"12,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_zone: Failed to add zentries for new zone $id");
      return DB_ERR_EXECUTE;
  }

  if (db_commit() < 0) {
      write2log("add_zone: Transaction commit failed for new zone $id");
      return DB_ERR_EXECUTE;
  }
  return $id;
}

=head1 FUNCTION: copy_zone

Copy entire zone to new zone with all DNS records and relationships.

Parameters:
  id        - Source zone ID to copy from
  serverid  - Target server ID for new zone
  newname   - Name for new zone
  verbose   - Print progress messages if true

Returns:
  zone_id - Positive integer on success (new zone ID)
  -3      - Invalid source zone (RET_INVALID_ARGUMENT)
  -2      - Database error during copy (DB_ERR_EXECUTE)

On failure, db_rollback() is called. Details logged via write2log().

=cut
sub copy_zone($$$$) {
  my($id,$serverid,$newname,$verbose)=@_;
  my($newid,%z,$res,@q,@ids,@hids,$i,$j,%h,@t,$fields,$fields2,%aids);
  my($timenow,%eaids,%hidh,$new_net);

  return RET_NOT_FOUND if (get_zone($id,\%z) < 0);
  del_std_fields(\%z);
  delete $z{pending_info};
  delete $z{zonehostid};
  delete $z{txt_auto_generation};


  if ($z{reverse} =~ /^(t|true)$/) {
    $new_net=arpa2cidr($newname);
    if (($new_net eq '0.0.0.0/0') or ($new_net eq '')) {
      write2log("copy_zone: Invalid reverse zone CIDR: $newname");
      return RET_INVALID_ARGUMENT;
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
  if ($newid < 1) { 
      db_rollback(); 
      write2log("copy_zone: Failed to insert new zone record");
      return DB_ERR_EXECUTE;
  }


  # Records pointing to the zone record
  print "<BR>Copying records pointing to zone record..." if ($verbose);

  # cidr_entries
  $res=db_exec("INSERT INTO cidr_entries (type,ref,ip,comment) " .
	       "SELECT type,$newid,ip,comment FROM cidr_entries " .
	       "WHERE (type=2 OR type=3 OR type=4 OR type=5 OR type=6 " .
	       " OR type=12) AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy cidr_entries");
      return DB_ERR_EXECUTE;
  }

  # dhcp_entries
  $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp,comment) " .
	       "SELECT type,$newid,dhcp,comment FROM dhcp_entries " .
	       "WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy dhcp_entries");
      return DB_ERR_EXECUTE;
  }

  # mx_templates
  print "<BR>Copying MX templates..." if ($verbose);
  undef @q;
  db_query("SELECT id FROM mx_templates WHERE zone=$id;",\@ids);
  for $i (0..$#ids) {
    undef %h;
    if (get_mx_template($ids[$i][0],\%h) < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to read mx_template $ids[$i][0]");
        return DB_ERR_EXECUTE;
    }
    del_std_fields(\%h);
    $h{zone}=$newid;
    $h{cuser}=$muser;
    $h{cdate}=time;
    $j=add_record('mx_templates',\%h);
    if ($j < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to add mx_template: " . db_errormsg());
        return DB_ERR_EXECUTE;
    }
    $ids[$i][1]=$j;
    $res=db_exec("INSERT INTO mx_entries (type,ref,pri,mx,comment) " .
		 "SELECT type,$j,pri,mx,comment FROM mx_entries " .
		 "WHERE type=3 AND ref=$ids[$i][0];");
    if ($res < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to copy mx_entries");
        return DB_ERR_EXECUTE;
    }
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
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy hosts");
      return DB_ERR_EXECUTE;
  }

  db_query("SELECT a.id,b.id,a.domain FROM hosts a, hosts b " .
	   "WHERE a.zone=$id AND b.zone=$newid AND a.domain=b.domain;",\@hids);
  print "<br>hids = " . $#hids;
  for $i (0..$#hids) { $hidh{$hids[$i][0]}=$hids[$i][1]; }

  # a_entries
  print "<BR>Copying A records..." if ($verbose);
  $res=copy_records('a_entries','a_entries','id','host',\@hids,
     'ip,ipv6,type,reverse,forward,comment',
     "SELECT a.id FROM a_entries a,hosts h WHERE a.host=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy a_entries");
      return DB_ERR_EXECUTE;
  }

  # dhcp_entries
  print "<BR>Copying DHCP records..." if ($verbose);
  $res=copy_records('dhcp_entries','dhcp_entries','id','ref',\@hids,
     'type,dhcp,comment',
     "SELECT a.id FROM dhcp_entries a,hosts h " .
     "WHERE a.type=3 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy dhcp_entries (hosts)");
      return DB_ERR_EXECUTE;
  }

  # mx_entires
  print "<BR>Copying MX records..." if ($verbose);
  $res=copy_records('mx_entries','mx_entries','id','ref',\@hids,
     'type,pri,mx,comment',
     "SELECT a.id FROM mx_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy mx_entries");
      return DB_ERR_EXECUTE;
  }

  # wks_entries
  print "<BR>Copying WKS records..." if ($verbose);
  $res=copy_records('wks_entries','wks_entries','id','ref',\@hids,
     'type,proto,services,comment',
     "SELECT a.id FROM wks_entries a,hosts h " .
     "WHERE a.type=1 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy wks_entries");
      return DB_ERR_EXECUTE;
  }

  # ns_entries
  print "<BR>Copying NS records..." if ($verbose);
  $res=copy_records('ns_entries','ns_entries','id','ref',\@hids,
     'type,ns,comment',
     "SELECT a.id FROM ns_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy ns_entries");
      return DB_ERR_EXECUTE;
  }

  # printer_entries
  print "<BR>Copying PRINTER records..." if ($verbose);
  $res=copy_records('printer_entries','printer_entries','id','ref',\@hids,
     'type,printer,comment',
     "SELECT a.id FROM printer_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy printer_entries");
      return DB_ERR_EXECUTE;
  }

  # txt_entries
  print "<BR>Copying TXT records..." if ($verbose);
  $res=copy_records('txt_entries','txt_entries','id','ref',\@hids,
     'type,txt,comment',
     "SELECT a.id FROM txt_entries a,hosts h " .
     "WHERE a.type=2 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy txt_entries");
      return DB_ERR_EXECUTE;
  }

  # srv_entries
  print "<BR>Copying SRV records..." if ($verbose);
  $res=copy_records('srv_entries','srv_entries','id','ref',\@hids,
     'type,pri,weight,port,target,comment',
     "SELECT a.id FROM srv_entries a,hosts h " .
     "WHERE a.type=1 AND a.ref=h.id AND h.zone=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy srv_entries");
      return DB_ERR_EXECUTE;
  }

  # update mx_template pointers
  print "<BR>Updating MX template pointers..." if ($verbose);
  for $i (0..$#ids) {
    $res=db_exec("UPDATE hosts SET mx=$ids[$i][1] " .
		 "WHERE zone=$newid AND mx=$ids[$i][0];");
    if ($res < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to update mx pointers");
        return DB_ERR_EXECUTE;
    }
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
    if ($res < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to update alias pointers");
        return DB_ERR_EXECUTE;
    }
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
    if ($res < 0) { 
        db_rollback(); 
        write2log("copy_zone: Failed to update ether_alias pointers");
        return DB_ERR_EXECUTE;
    }
  }

  # copy AREC entries
  print "<BR>Copying AREC entries..." if ($verbose);
  undef @q;
  db_query("SELECT a.host,a.arec FROM arec_entries a, hosts h " .
	   "WHERE h.zone=$id AND h.id=a.host",\@q);
  for $i (0..$#q) {
    #print "$i: $q[$i][0] --> $hidh{$q[$i][0]}, $q[$i][1] --> $hidh{$q[$i][1]}<br>";
    unless ($hidh{$q[$i][0]} && $hidh{$q[$i][1]}) {
      db_rollback();
      write2log("copy_zone: Invalid arec mapping for $q[$i][0] or $q[$i][1]");
      return RET_INVALID_ARGUMENT;
    }

    $q[$i][0]=$hidh{$q[$i][0]};
    $q[$i][1]=$hidh{$q[$i][1]};
  }
  $res = db_insert('arec_entries','host,arec',\@q);
  if ($res < 0) { 
      db_rollback(); 
      write2log("copy_zone: Failed to copy arec_entries");
      return DB_ERR_EXECUTE;
  }

  if (db_commit() < 0) {
      write2log("copy_zone: Transaction commit failed");
      return DB_ERR_EXECUTE;
  }
  return $newid;
}

############################################################################
# hosts table functions

=head1 FUNCTION: get_host_id

Get host database ID by host domain name and zone.

Parameters:
  zoneid  - Zone ID containing the host
  domain  - Host domain name to look up

Returns:
  host_id - Positive integer host ID on success
  -2      - Host not found (RET_NOT_FOUND)

=cut
sub get_host_id($$) {
  my($zoneid,$domain)=@_;
  my(@q);

  $domain=db_encode_str($domain);
  db_query("SELECT id FROM hosts WHERE zone=$zoneid AND domain=$domain",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}

=head1 FUNCTION: get_host (forward declaration)

Description:
  Forward declaration for recursive host loading.

Parameters:
  id  - Host ID
  rec - Hash reference for host data

Returns:
  See full get_host implementation below.

=cut
sub get_host($$); # declare it here since get_host uses sometimes recursion

=head1 FUNCTION: get_host

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
  return RET_NOT_FOUND if ($res < 0);
  fix_bools($rec,"prn");

  my %fqdnzone;
  if (get_zone($$rec{zone}, \%fqdnzone) == 0) {
      $$rec{fqdn} = $$rec{domain} . '.' . $fqdnzone{name} . '.';
  }

  get_array_field("a_entries",4,"id,ip,reverse,forward",
		  "IP,reverse,forward","host=$id ORDER BY ip",$rec,'ip');

  get_array_field("ns_entries",3,"id,ns,comment","NS,Comments",
		  "type=2 AND ref=$id ORDER BY ns",$rec,'ns_l');
  get_array_field("ds_entries",6,"id,key_tag,algorithm,digest_type,digest,comment",
                  "Key tag,Algorithm,Digest type,Digest,Comments",
		  "type=2 AND ref=$id ORDER BY key_tag,algorithm,digest_type,digest",
                  $rec,'ds_l');
  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comments",
		  "type=1 AND ref=$id ORDER BY proto,services",$rec,'wks_l');
  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comments",
		  "type=2 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=3 AND ref=$id ORDER BY id",$rec,'dhcp_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comments",
		  "type=13 AND ref=$id ORDER BY id",$rec,'dhcp_l6');
  get_array_field("printer_entries",3,"id,printer,comment","PRINTER,Comments",
		  "type=2 AND ref=$id ORDER BY printer",$rec,'printer_l');
  get_array_field("srv_entries",6,"id,pri,weight,port,target,comment",
		  "Priority,Weight,Port,Target,Comments",
		  "type=1 AND ref=$id ORDER BY port,pri,weight",$rec,'srv_l');
  get_array_field("sshfp_entries",6,"id,algorithm,hashtype,fingerprint,comment",
		  "Algorithm,Type,Fingerprint,Comments",
		  "type=1 AND ref=$id ORDER BY algorithm,hashtype,fingerprint",$rec,'sshfp_l');
  get_array_field("tlsa_entries",6,"id,usage,selector,matching_type,association_data,comment",
		  "Usage,Selector,Matching Type,Asociation Data,Comments",
		  "type=1 AND ref=$id ORDER BY usage,selector,matching_type,association_data",$rec,'tlsa_l');
  get_array_field("naptr_entries",8,"id,order_val,preference,flags,service,regexp,replacement,comment",
		  "Order,Preference,Flags,Service,Regexp,Replacement,Comments",
		  "type=1 AND ref=$id ORDER BY order_val,preference,flags,service,regexp,replacement",$rec,'naptr_l');
  get_array_field("txt_entries",3,"id,txt,comment",
		  "Text,Comments",
		  "type=2 AND ref=$id ORDER BY txt",$rec,'txt_l');
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


=head1 FUNCTION: update_host

Update host record with all associated DNS records in transaction.

Parameters:
  rec - Hash reference with host data

Returns:
  1   - Success (db_commit() result)
  -3  - Invalid data (RET_INVALID_ARGUMENT)
  -2  - Database error during transaction (DB_ERR_EXECUTE)

All database errors cause automatic db_rollback(). Details logged via write2log().

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update ns_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("ds_entries",6,"key_tag,algorithm,digest_type,digest,comment,type,ref",
			'ds_l',$rec,"2,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update ds_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("wks_entries",4,"proto,services,comment,type,ref",
			'wks_l',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update wks_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("mx_entries",4,"pri,mx,comment,type,ref",
			'mx_l',$rec,"2,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update mx_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l',$rec,"3,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update dhcp_entries (dhcp_l) for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("printer_entries",3,"printer,comment,type,ref",
			'printer_l',$rec,"2,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update printer_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("srv_entries",6,
			"pri,weight,port,target,comment,type,ref",
			'srv_l',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update srv_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("sshfp_entries",5,
			"algorithm,hashtype,fingerprint,comment,type,ref",
			'sshfp_l',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update sshfp_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("tlsa_entries",6,
			"usage,selector,matching_type,association_data,comment,type,ref",
			'tlsa_l',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update tlsa_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("naptr_entries",8,
			"order_val,preference,flags,service,regexp,replacement,comment,type,ref",
			'naptr_l',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update naptr_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("txt_entries",3,
			"txt,comment,type,ref",
			'txt_l',$rec,"2,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update txt_entries for host $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("a_entries",4,"ip,reverse,forward,host",
			'ip',$rec,"$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update a_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  if ($rec->{type}==7) {
    $r=update_array_field("arec_entries",2,"arec,host",
			  'alias_a',$rec,"$id");
    if ($r < 0) { 
        db_rollback(); 
        write2log("update_host: Failed to update arec_entries for host $id");
        return DB_ERR_EXECUTE;
    }
  }

  $r=update_array_field("group_entries",2,"grp,host",
			'subgroups',$rec,"$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update group_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l6',$rec,"13,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_host: Failed to update dhcp_entries (dhcp_l6) for host $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: delete_host

Delete host record and all associated DNS records and relationships in transaction.

Parameters:
  id - Host ID

Returns:
  Commit result - Success
  -3  - Invalid data (RET_INVALID_ARGUMENT)
  -2  - Record not found or database error (DB_ERR_EXECUTE)

All database errors cause automatic db_rollback(). Details logged via write2log().

=cut
sub delete_host($) {
  my($id) = @_;
  my($res,%host,$sql);
  my($dtime) = time;

  return RET_INVALID_ARGUMENT unless ($id > 0);
  return RET_NOT_FOUND if (get_host($id,\%host) < 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete dhcp_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete mx_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete wks_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # ns_entries
  $res=db_exec("DELETE FROM ns_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete ns_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete printer_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # txt_entries
  $res=db_exec("DELETE FROM txt_entries WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete txt_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # a_entries
  $res=db_exec("DELETE FROM a_entries WHERE host=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete a_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # static aliases TVu 15.03.2016
  $sql = "delete from hosts where id in " .
      "(select h2.id from hosts h1, hosts h2, zones z " .
      "where h1.id = $id and h1.zone = z.id and " .
      "h1.domain || '.' || z.name || '.' = h2.cname_txt and " .
      "h2.type = 4 and h2.alias = -1);";
  $res = db_exec($sql);
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete static aliases for host $id");
      return DB_ERR_EXECUTE;
  }

  # arec aliases unless they also point to some other host TVu 15.03.2016
  # this must be done before deleting arec_entries!
  $sql = "delete from hosts where id in (select s1.host from " .
      "(select host, count(arec) as c1 from arec_entries where host in " .
      "(select host from arec_entries where arec = $id) group by host) " .
      "as s1 where s1.c1 = 1) and type = 7 and alias = -1;";
  $res = db_exec($sql);
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete arec aliases for host $id");
      return DB_ERR_EXECUTE;
  }

  # arec_entries
  $res=db_exec("DELETE FROM arec_entries WHERE host=$id OR arec=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete arec_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # cname aliases
  $res=db_exec("DELETE FROM hosts WHERE type=4 AND alias=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete cname aliases for host $id");
      return DB_ERR_EXECUTE;
  }

  # ether_aliases
  $res=db_exec("UPDATE hosts SET ether_alias=-1, expiration=$dtime ".
	       "WHERE ether_alias=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to update ether_aliases for host $id");
      return DB_ERR_EXECUTE;
  }

  # srv_entries
  $res=db_exec("DELETE FROM srv_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete srv_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # sshfp_entries
  $res=db_exec("DELETE FROM sshfp_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete sshfp_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # tlsa_entries
  $res=db_exec("DELETE FROM tlsa_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete tlsa_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # naptr_entries
  $res=db_exec("DELETE FROM naptr_entries WHERE type=1 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete naptr_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # group_entries
  $res=db_exec("DELETE FROM group_entries WHERE host=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete group_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM hosts WHERE id=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_host: Failed to delete host record id=$id");
      return DB_ERR_EXECUTE;
  }

  if ($host{zone} > 0) {
    my $t=time();
    $res=db_exec("UPDATE zones SET rdate=$t WHERE id=$host{zone}");
    if ($res < 0) { 
        db_rollback(); 
        write2log("delete_host: Failed to update zone rdate for zone $host{zone}");
        return DB_ERR_EXECUTE;
    }
  }

  return db_commit();
}

=head1 FUNCTION: add_host

Create new host record with all associated DNS records in transaction.

Parameters:
  rec - Hash reference with host data

Returns:
  Host ID - Success
  -3  - Invalid data (RET_INVALID_ARGUMENT)
  -2  - Database error during transaction (DB_ERR_EXECUTE)

Special errors:
  -999 - Cannot add hosts to catalog zones

All database errors cause automatic db_rollback(). Details logged via write2log().

=cut
sub add_host($) {
  my($rec) = @_;
  my($res,$i,$id,$a_id, @q);

  delete $rec->{cname_alias};
  delete $rec->{static_alias};

  return RET_INVALID_ARGUMENT unless ($rec->{zone} > 0);

  # Catalog zones cannot have hosts added (RFC 9432)
  if (is_catalog_zone($rec->{zone})) {
    write2log("add_host: Cannot add host to catalog zone id=$rec->{zone}");
    return -999;  # ERROR: Cannot add hosts to catalog zones
  }

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
	  db_rollback();
	  write2log("add_host: Failed to get next sequence ID");
	  return DB_ERR_EXECUTE;
      }
  }

  $res=add_record('hosts',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add host record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # IPs
  $res = add_array_field('a_entries','ip,reverse,forward','ip',$rec,
			 'host',"$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add a_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # MXs
  $res = add_array_field('mx_entries','pri,mx,comment','mx_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add mx_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # NSs
  $res = add_array_field('ns_entries','ns,comment','ns_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add ns_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # DSs (in Delegation form)
  $res = add_array_field('ds_entries','key_tag,algorithm,digest_type,digest,comment','ds_l',
                         $rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add ds_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # PRINTERs
  $res = add_array_field('printer_entries','printer,comment','printer_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add printer_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # SRVs
  $res = add_array_field('srv_entries','pri,weight,port,target,comment',
			 'srv_l',$rec,'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add srv_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # SSHFPs
  $res = add_array_field('sshfp_entries','algorithm,hashtype,fingerprint,comment',
			 'sshfp_l',$rec,'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add sshfp_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # TLSAs
  $res = add_array_field('tlsa_entries','usage,selector,matching_type,association_data,comment',
			 'tlsa_l',$rec,'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add tlsa_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # NAPTRs
  $res = add_array_field('naptr_entries','order_val,preference,flags,service,regexp,replacement,comment',
			 'naptr_l',$rec,'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add naptr_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # TXTs
  $res = add_array_field('txt_entries','txt,comment',
			 'txt_l',$rec,'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add txt_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  # ARECs
  if ($rec->{type}==7) {
    $res=db_exec("INSERT INTO arec_entries (host,arec) VALUES($id,$a_id);");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_host: Failed to add arec_entries for host $id");
        return DB_ERR_EXECUTE;
    }
  }

  # subgroups
  $res = add_array_field('group_entries','grp',
			 'subgroups',$rec,'host',"$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_host: Failed to add group_entries for host $id");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}

# List moved from browser.cgi so that it can be used also in command line
# tools without need to update multiple lists, should the list change.
# TVu 02.04.2014.
=head1 FUNCTION: get_host_types

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_host_types() {
    return (0 => 'Any type', 1 => 'Host', 2 => 'Delegation', 3 => 'Plain MX',
	    4 => 'Alias', 5 => 'Printer', 6 => 'Glue', 7 => 'AREC Alias',
	    8 => 'SRV', 9 => 'DHCP only', 10 => 'Zone', 11=>'SSHFP only',
	    12 => 'TLSA only', 13 => 'TXT', 14 => 'NAPTR',
	    101 => 'Host reservation');
}

############################################################################
=head1 FUNCTION: get_mx_template_by_name

Lookup MX template ID by zone and name.

Parameters:
  zoneid - Zone ID
  name   - Template name

Returns:
  Template ID - Success
  -3  - Invalid zone ID (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_mx_template_by_name($$) {
  my($zoneid,$name)=@_;
  my(@q);
  return RET_INVALID_ARGUMENT unless ($zoneid > 0);
  $name=db_encode_str($name);
  db_query("SELECT id FROM mx_templates WHERE zone=$zoneid AND name=$name",
	   \@q);
  return RET_NOT_FOUND unless (@q > 0);
  return ($q[0][0]);
}

=head1 FUNCTION: get_mx_template

Get MX template record with all associated MX entries.

Parameters:
  id  - Template ID
  rec - Hash reference to populate

Returns:
  0   - Success
  -2  - Record not found or database error (DB_ERR_EXECUTE)

=cut
sub get_mx_template($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("mx_templates",
			     "name,comment,cdate,cuser,mdate,muser,alevel",
			     $id,$rec,"id"));

  get_array_field("mx_entries",4,"id,pri,mx,comment","Priority,MX,Comment",
		  "type=3 AND ref=$id ORDER BY pri,mx",$rec,'mx_l');

  add_std_fields($rec);
  return 0;
}

=head1 FUNCTION: update_mx_template

Update MX template and all associated MX entries in transaction.

Parameters:
  rec - Hash reference with template data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_mx_template: Failed to update mx_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: add_mx_template

Create new MX template with associated MX entries in transaction.

Parameters:
  rec - Hash reference with template data

Returns:
  Template ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_mx_template($) {
  my($rec) = @_;

  my($res,$id);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('mx_templates',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_mx_template: Failed to add mx_template record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # mx_entries
  $res=add_array_field('mx_entries','pri,mx,comment','mx_l',$rec,
		       'type,ref',"3,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_mx_template: Failed to add mx_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_mx_template

Delete MX template and all associated MX entries in transaction.

Parameters:
  id - Template ID

Returns:
  Commit result - Success
  -3  - Invalid template ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_mx_template($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # mx_entries
  $res=db_exec("DELETE FROM mx_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_mx_template: Failed to delete mx_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM mx_templates WHERE id=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_mx_template: Failed to delete mx_template record id=$id");
      return DB_ERR_EXECUTE;
  }


  $res=db_exec("UPDATE hosts SET mx=-1 WHERE mx=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_mx_template: Failed to update hosts mx references for template $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}


=head1 FUNCTION: get_mx_template_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_wks_template

Get WKS template record with all associated WKS entries.

Parameters:
  id  - Template ID
  rec - Hash reference to populate

Returns:
  0   - Success
  -2  - Record not found or database error (DB_ERR_EXECUTE)

=cut
sub get_wks_template($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("wks_templates",
			     "name,comment,cuser,cdate,muser,mdate,alevel",
			     $id,$rec,"id"));

  get_array_field("wks_entries",4,"id,proto,services,comment",
		  "Proto,Services,Comment",
		  "type=2 AND ref=$id ORDER BY proto,services",$rec,'wks_l');

  add_std_fields($rec);
  return 0;
}

=head1 FUNCTION: update_wks_template

Update WKS template and all associated WKS entries in transaction.

Parameters:
  rec - Hash reference with template data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_wks_template: Failed to update wks_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: add_wks_template

Create new WKS template with associated WKS entries in transaction.

Parameters:
  rec - Hash reference with template data

Returns:
  Template ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_wks_template($) {
  my($rec) = @_;

  my($res,$id,$i);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('wks_templates',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_wks_template: Failed to add wks_template record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # wks entries
  $res = add_array_field('wks_entries','proto,services,comment','wks_l',$rec,
			 'type,ref',"2,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_wks_template: Failed to add wks_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_wks_template

Delete WKS template and all associated WKS entries in transaction.

Parameters:
  id - Template ID

Returns:
  Commit result - Success
  -3  - Invalid template ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_wks_template($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # wks_entries
  $res=db_exec("DELETE FROM wks_entries WHERE type=2 AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_wks_template: Failed to delete wks_entries for template $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM wks_templates WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_wks_template: Failed to delete wks_template record id=$id");
      return DB_ERR_EXECUTE;
  }


  $res=db_exec("UPDATE hosts SET wks=-1 WHERE wks=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_wks_template: Failed to update hosts wks references for template $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_wks_template_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_printer_class

Get printer class record with all associated printer entries.

Parameters:
  id  - Class ID
  rec - Hash reference to populate

Returns:
  0   - Success
  -2  - Record not found or database error (DB_ERR_EXECUTE)

=cut
sub get_printer_class($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("printer_classes",
			     "name,comment,cuser,cdate,muser,mdate",
			     $id,$rec,"id"));

  get_array_field("printer_entries",3,"id,printer,comment",
		  "Printer,Comment",
		  "type=3 AND ref=$id ORDER BY printer",$rec,'printer_l');

  add_std_fields($rec);
  return 0;
}

=head1 FUNCTION: update_printer_class

Update printer class and all associated printer entries in transaction.

Parameters:
  rec - Hash reference with class data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_printer_class: Failed to update printer_entries for class $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: add_printer_class

Create new printer class with associated printer entries in transaction.

Parameters:
  rec - Hash reference with class data

Returns:
  Class ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_printer_class($) {
  my($rec) = @_;

  my($res,$id);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('printer_classes',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_printer_class: Failed to add printer_class record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # printer entries
  $res = add_array_field('printer_entries','printer,comment','printer_l',$rec,
			 'type,ref',"3,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_printer_class: Failed to add printer_entries for class $id");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_printer_class

Delete printer class and all associated printer entries in transaction.

Parameters:
  id - Class ID

Returns:
  Commit result - Success
  -3  - Invalid class ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_printer_class($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=3 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_printer_class: Failed to delete printer_entries for class $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM printer_classes WHERE id=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_printer_class: Failed to delete printer_class record id=$id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

############################################################################
# HINFO template functions

=head1 FUNCTION: get_hinfo_template

Get hinfo template record.

Parameters:
  id  - Template ID
  rec - Hash reference to populate

Returns:
  0   - Success
  -2  - Record not found or database error (DB_ERR_EXECUTE)

=cut
sub get_hinfo_template($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("hinfo_templates",
			     "hinfo,type,pri,cdate,cuser,mdate,muser",
			     $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}

=head1 FUNCTION: update_hinfo_template

Update hinfo template in transaction.

Parameters:
  rec - Hash reference with template data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub update_hinfo_template($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('hinfo_templates',$rec);
  if ($r < 0) { db_rollback(); return $r; }
  return db_commit();
}

=head1 FUNCTION: add_hinfo_template

Create new hinfo template.

Parameters:
  rec - Hash reference with template data

Returns:
  Template ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_hinfo_template($) {
  my($rec) = @_;

  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  my $res = add_record('hinfo_templates',$rec);
  if ($res < 0) { 
      write2log("add_hinfo_template: Failed to add hinfo_template record");
      return DB_ERR_EXECUTE;
  }
  return $res;
}


=head1 FUNCTION: delete_hinfo_template

Delete hinfo template in transaction.

Parameters:
  id - Template ID

Returns:
  Commit result - Success
  -3  - Invalid template ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_hinfo_template($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM hinfo_templates WHERE id=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_hinfo_template: Failed to delete hinfo_template record id=$id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

############################################################################
# group functions

=head1 FUNCTION: get_group_by_name

Lookup group ID by server and name.

Parameters:
  serverid - Server ID
  name     - Group name

Returns:
  Group ID - Success
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_group_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  $name=db_encode_str($name);
  db_query("SELECT id FROM groups WHERE server=$serverid AND name=$name",\@q);
  return RET_NOT_FOUND unless (@q > 0);
  return ($q[0][0]);
}

=head1 FUNCTION: get_group_type_by_name

Lookup group type by server and name.

Parameters:
  serverid - Server ID
  name     - Group name

Returns:
  Group type - Success
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_group_type_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  $name=db_encode_str($name);
  db_query("SELECT type FROM groups WHERE server=$serverid AND name=$name",\@q);
  return RET_NOT_FOUND unless (@q > 0);
  return ($q[0][0]);
}

=head1 FUNCTION: get_group

Get group record with all associated DHCP and printer entries.

Parameters:
  id  - Group ID
  rec - Hash reference to populate

Returns:
  0   - Success
  -2  - Record not found or database error (DB_ERR_EXECUTE)

=cut
sub get_group($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("groups",
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

=head1 FUNCTION: update_group

Update group and all associated DHCP and printer entries in transaction.

Parameters:
  rec - Hash reference with group data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_group: Failed to update dhcp_entries for group $id");
      return DB_ERR_EXECUTE;
  }
  $r=update_array_field("printer_entries",3,"printer,comment,type,ref",
			'printer',$rec,"1,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_group: Failed to update printer_entries for group $id");
      return DB_ERR_EXECUTE;
  }

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp6',$rec,"15,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_group: Failed to update dhcp6_entries for group $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: add_group

Create new group with associated DHCP and printer entries in transaction.

Parameters:
  rec - Hash reference with group data

Returns:
  Group ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_group($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cuser}=$muser;
  $rec->{cdate}=time;
  $res = add_record('groups',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_group: Failed to add group record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # dhcp_entries
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp',$rec,
			 'type,ref',"5,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_group: Failed to add dhcp_entries for group $id");
      return DB_ERR_EXECUTE;
  }

  # dhcp_entries IPv6
  $res = add_array_field('dhcp_entries','dhcp,comment','dhcp6',$rec,
			 'type,ref',"15,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_group: Failed to add dhcp6_entries for group $id");
      return DB_ERR_EXECUTE;
  }

  # printer_entries
  $res = add_array_field('printer_entries','printer,comment','printer',$rec,
			 'type,ref',"1,$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_group: Failed to add printer_entries for group $id");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;

}

=head1 FUNCTION: delete_group

Delete group and all associated DHCP and printer entries in transaction.

Parameters:
  id - Group ID

Returns:
  Commit result - Success
  -3  - Invalid group ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_group($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

# dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE (type=5 OR type=15) AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_group: Failed to delete dhcp_entries for group $id");
      return DB_ERR_EXECUTE;
  }
# printer_entries
  $res=db_exec("DELETE FROM printer_entries WHERE type=1 AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_group: Failed to delete printer_entries for group $id");
      return DB_ERR_EXECUTE;
  }

# group itself
  $res=db_exec("DELETE FROM groups WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_group: Failed to delete group record id=$id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_group_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_user

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: update_user

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub update_user($) {
  my($rec) = @_;

  del_std_fields($rec);

  $rec->{flags}=0;
  $rec->{flags}|=0x01 if ($rec->{email_notify});
  delete $rec->{email_notify};

  return update_record('users',$rec);
}

=head1 FUNCTION: add_user

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub add_user($) {
  my($rec) = @_;

  $rec->{cuser}=$muser;
  $rec->{cdate}=time;

  $rec->{flags}=0;
  $rec->{flags}|=0x01 if ($rec->{email_notify});
  delete $rec->{email_notify};

  return add_record('users',$rec);
}

=head1 FUNCTION: delete_user

Delete a user and all associated records in transaction.

Parameters:
  id         - User ID
  name       - Username
  delete     - 1 to fully delete, 0 to anonymize
  expiration - Expiration timestamp
  now        - Current timestamp
  user       - Current user

Returns:
  Commit result - Success
  -3  - Invalid user ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_user($$$$$$) {
  my($id, $name, $delete, $expiration, $now, $user) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # user_rights
  $res=db_exec("DELETE FROM user_rights WHERE type=2 AND ref=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_user: Failed to delete user_rights for user $id");
      return DB_ERR_EXECUTE;
  }
  # utmp
  $res=db_exec("DELETE FROM utmp WHERE uid=$id;");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_user: Failed to delete utmp entries for user $id");
      return DB_ERR_EXECUTE;
  }

  if ($delete) {
      $res=db_exec("DELETE FROM users WHERE id=$id;");
      if ($res < 0) { 
          db_rollback(); 
          write2log("delete_user: Failed to delete user record id=$id");
          return DB_ERR_EXECUTE;
      }
  } else {
      $res=db_exec("update users set (server, zone, superuser, last_pwd, flags, " .
		   "email, last_from, search_opts, comment, " .
		   "name, password, expiration, mdate, muser) = " .
		   "(default, default, default, default, default, " .
		   "null, null, null, null, " .
		   "'Removed User', 'LOCKED:REMOVED', $expiration, $now, '$user') " .
		   "where id = $id;");
      if ($res < 0) { 
          db_rollback(); 
          write2log("delete_user: Failed to anonymize user record id=$id");
          return DB_ERR_EXECUTE;
      }
  }

# User was deleted from all user groups, but that is not recorded in history.
  $res = update_history(-1, -1, 5,      # No UID. No SID. 5 = User changes.
			($delete ? 'DELETE' : 'ANONYMIZE') . ': User', # Action.
			"Username: $name (login: " . getlogin(). ')', # Info
			$id);           # Ref.
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_user: Failed to update history for user deletion $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_user_group_id

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_user_group_id($) {
  my($group)=@_;
  my(@q);

  db_query("SELECT id FROM user_groups WHERE name='$group'",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : -1);
}

=head1 FUNCTION: get_user_group

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_user_group($$) {
  my ($id,$rec) = @_;
  my ($res);

  $res = get_record("user_groups","name,comment",
		    $id,$rec,"id");

  return $res;
}

# For Users.pm 2021-04-21 TVu
=head1 FUNCTION: get_user_group_w_members

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_user_group_w_members($$) { # Kesken !!!
  my ($id, $rec) = @_;
  my ($res, $t, $wrec, $mrec, %h, @q, $infostr);

  $res = get_record("user_groups", "name, comment",
	       $id, $rec, "id");
  if ($res < 0) {
      write2log("get_user_group_w_members: Failed to load group id=$id");
      return -1;
  }

  get_array_field("users u, user_rights ur", 3, "u.id, u.username, u.name",
		  "Members", "ur.type = 2 AND ur.rtype = 0 AND " .
		  "ur.rref = $id AND ur.ref = u.id ORDER BY u.username",
		  $rec, 'users');

  return 0;
}

# For Users.pm 2021-05-10 TVu
=head1 FUNCTION: get_all_users

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: delete_user_group

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub delete_user_group($$$$$$) {
  my ($id,$newid,$group,$newgroup,$uid,$sid) = @_;
  my ($res,$sql,@q,$ind1);

  db_begin();

# Delete rights given to the group.
  $res = db_exec("DELETE FROM user_rights WHERE type=1 AND ref=$id");
  if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to delete rights for group id=$id"); return -1; }
# Delete group.
  $res = db_exec("DELETE FROM user_groups WHERE id=$id");
  if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to delete group id=$id"); return -2; }
# Update group history.
  $res = update_history($uid, $sid, 6,        # 6 = User group changes.
			'DELETE: User group', # Action.
			"Group: $group (login: " . getlogin(). ')', # Info
			$id);                 # Ref.
  if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to write group delete history for group id=$id"); return -5; }

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
  	  if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to write user move history for user id=$q[$ind1][0]"); return -6; }
      }
# Move users to another group.
      $res = db_exec("UPDATE user_rights SET rref=$newid " .
		     "WHERE type=2 AND rtype=0 AND rref=$id");
    if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to move users from group id=$id to group id=$newid"); return -3; }
  } else {
# Delete group membership from users.
      $res = db_exec("DELETE FROM user_rights ".
		     "WHERE type=2 AND rtype=0 AND rref=$id");
    if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to remove users from group id=$id"); return -4; }
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
  if ($res < 0) { db_rollback(); write2log("delete_user_group: Failed to remove duplicate memberships after deleting group id=$id"); return -7; }

  return db_commit();
}

# Get user's status and authorization level.
=head1 FUNCTION: get_user_status

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_user_status($) {
    my ($id) = @_;
    my ($sql, @res, $status);

=head1 FUNCTION: get_user_status

Get user account status including expiration, locked, superuser flags and authorization level.

Parameters:
  id - User ID

Returns:
  Status string - Success (e.g., 'E', 'L', 'S', combined flags + auth level)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
# Get status (other than authorization level).
    $sql = "select coalesce(expiration, 0) <= 0 or coalesce(expiration, 0) > " .
	"extract(epoch from now()), password, superuser " .
	"from users " .
	"where id = $id;";
    db_query($sql, \@res);
    return DB_ERR_EXECUTE if (!$res[0][1]);
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

=head1 FUNCTION: get_net_by_cidr

Lookup network ID by server and CIDR.

Parameters:
  serverid - Server ID
  cidr     - Network CIDR

Returns:
  Network ID - Success
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -3  - Invalid CIDR (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_net_by_cidr($$) {
  my($serverid,$cidr) = @_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  return RET_INVALID_ARGUMENT unless (is_cidr($cidr));
  db_query("SELECT id FROM nets WHERE server=$serverid AND net='$cidr'",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}

=head1 FUNCTION: get_net_cidr_by_ip

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_net_cidr_by_ip($$) {
  my($serverid,$ip) = @_;
  my(@q);

  return '-1' unless ($serverid > 0);
  return '-2' unless (is_ip($ip));
  db_query("SELECT net FROM nets WHERE server=$serverid AND net >> '$ip' order by net desc limit 1",\@q);
  return ($q[0][0] ? $q[0][0] : '');
}

=head1 FUNCTION: get_net_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_net

Retrieve network record by ID with all associated data.

Parameters:
  id  - Network ID
  rec - Hash reference to populate with network data

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub get_net($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("nets",
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

=head1 FUNCTION: update_net

Update network record and all associated DHCP entries in transaction.

Parameters:
  rec - Hash reference with network data

Returns:
  Commit result - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub update_net($) {
  my($rec) = @_;
  my($r,$id,$net);

  return RET_INVALID_ARGUMENT unless (is_cidr($rec->{net}));
# $net = new Net::Netmask($rec->{net});
  $net = new NetAddr::IP($rec->{net}); # For IPv6.
  return RET_INVALID_ARGUMENT unless ($net);

# Nets (other than subnets and virtual nets) should never have had a range, and
# some changes to net's CIDR were not possible when they had. 2019-01-03 TVu
  if ($rec->{subnet} =~ /^f/i && $rec->{dummy} =~ /^f/i) {
      $rec->{range_start} = $rec->{range_end} = '';
  }

  if (is_cidr($rec->{range_start})) {
#   return -102 unless ($net->match($rec->{range_start}));
    return RET_INVALID_ARGUMENT unless ($net->contains(new NetAddr::IP($rec->{range_start}))); # For IPv6.
  }
  if (is_cidr($rec->{range_end})) {
#   return -103 unless ($net->match($rec->{range_end}));
    return RET_INVALID_ARGUMENT unless ($net->contains(new NetAddr::IP($rec->{range_end}))); # For IPv6.
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
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_net: Failed to update dhcp_entries for network $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}



=head1 FUNCTION: add_net

Create new network with associated DHCP entries in transaction.

Parameters:
  rec - Hash reference with network data

Returns:
  Network ID - Success
  -2  - Database error (DB_ERR_EXECUTE)
  -3  - Invalid parameters (RET_INVALID_ARGUMENT)

=cut
sub add_net($) {
  my($rec) = @_;
  my($res,$id,$i);
  my($net);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;

  return RET_INVALID_ARGUMENT unless (is_cidr($rec->{net}));
  $net = new Net::IP($rec->{net});
  return RET_INVALID_ARGUMENT unless ($net);

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
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_net: Failed to add net record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # dhcp_entries
  for $i (0..$#{$rec->{dhcp_l}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(4,$id,'$rec->{dhcp_l}[$i][1]')");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_net: Failed to add dhcp_entries for network $id");
        return DB_ERR_EXECUTE;
    }
  }

  for $i (0..$#{$rec->{dhcp_l6}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(4,$id,'$rec->{dhcp_l6}[$i][1]')");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_net: Failed to add dhcp_l6_entries for network $id");
        return DB_ERR_EXECUTE;
    }
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_net

Delete network and all associated DHCP entries in transaction.

Parameters:
  id - Network ID

Returns:
  Commit result - Success
  -3  - Invalid network ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_net($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=4 AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_net: Failed to delete dhcp_entries for network $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM nets WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_net: Failed to delete net record id=$id");
      return DB_ERR_EXECUTE;
  }


  $res=db_exec("DELETE FROM user_rights WHERE rtype=3 AND rref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_net: Failed to delete user_rights for network $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

############################################################################
# VLAN functions

=head1 FUNCTION: get_vlan

Retrieve VLAN record by ID with all associated data.

Parameters:
  id  - VLAN ID
  rec - Hash reference to populate with VLAN data

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub get_vlan($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("vlans",
                      "server,name,description,comment,vlanno,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=6 AND ref=$id ORDER BY id",$rec,'dhcp_l');
  get_array_field("dhcp_entries",3,"id,dhcp,comment","DHCP,Comment",
		  "type=16 AND ref=$id ORDER BY id",$rec,'dhcp_l6');

  add_std_fields($rec);
  return 0;
}


=head1 FUNCTION: update_vlan

Update VLAN and its associated DHCP entries in transaction.

Parameters:
  rec - Hash reference with VLAN data including id

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE) or update_record error

=cut
sub update_vlan($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('vlans',$rec);
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_vlan: Failed to update vlan $rec->{id}");
      return $r; 
  }
  $id=$rec->{id};

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l',$rec,"6,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_vlan: Failed to update dhcp_entries for vlan $id");
      return DB_ERR_EXECUTE; 
  }

  $r=update_array_field("dhcp_entries",3,"dhcp,comment,type,ref",
			'dhcp_l6',$rec,"16,$id");
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_vlan: Failed to update dhcp_l6_entries for vlan $id");
      return DB_ERR_EXECUTE; 
  }

  return db_commit();
}

=head1 FUNCTION: add_vlan

Create new VLAN with associated DHCP entries in transaction.

Parameters:
  rec - Hash reference with VLAN data

Returns:
  VLAN ID - Success
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub add_vlan($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('vlans',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_vlan: Failed to add vlan record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  # dhcp_entries
  for $i (0..$#{$rec->{dhcp_l}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(6,$id,'$rec->{dhcp_l}[$i][1]')");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_vlan: Failed to add dhcp_entries for vlan $id");
        return DB_ERR_EXECUTE; 
    }
  }

# dhcp_entries6
  for $i (0..$#{$rec->{dhcp_l6}}) {
    $res=db_exec("INSERT INTO dhcp_entries (type,ref,dhcp) " .
		 "VALUES(16,$id,'$rec->{dhcp_l6}[$i][1]')");
    if ($res < 0) { 
        db_rollback(); 
        write2log("add_vlan: Failed to add dhcp_l6_entries for vlan $id");
        return DB_ERR_EXECUTE;
    }
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}

=head1 FUNCTION: delete_vlan

Delete VLAN and all associated DHCP entries in transaction.

Parameters:
  id - VLAN ID

Returns:
  Commit result - Success
  -3  - Invalid VLAN ID (RET_INVALID_ARGUMENT)
  -2  - Database error (DB_ERR_EXECUTE)

=cut
sub delete_vlan($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  # dhcp_entries
  $res=db_exec("DELETE FROM dhcp_entries WHERE type=6 AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_vlan: Failed to delete dhcp_entries for vlan $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM vlans WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_vlan: Failed to delete vlan record id=$id");
      return DB_ERR_EXECUTE;
  }


  $res=db_exec("UPDATE nets SET vlan=-1 WHERE vlan=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_vlan: Failed to update nets for vlan $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_vlan_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_vlanno

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub get_vlanno($$) {
  my($serverid,$id) = @_;
  my(@q);

  return 0 if ($serverid < 1);

  db_query("SELECT coalesce(vlanno,0) FROM vlans " .
	   "WHERE server=$serverid and id=$id;",\@q);
  return $q[0][0];
}

=head1 FUNCTION: get_vlan_by_name

Lookup VLAN ID by server and name.

Parameters:
  serverid - Server ID
  name     - VLAN name

Returns:
  VLAN ID - Success
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -3  - Missing name (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_vlan_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  return RET_INVALID_ARGUMENT unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM vlans WHERE server=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}

############################################################################
# IP functions

# Name network's ip policies.
=head1 FUNCTION: ip_policy_names

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub ip_policy_names($) {
    my($ip, $m) = ($_[0] =~ /^(.+)\/(.+)$/);
    my %list = ( 0 => 'Lowest free', 10 => 'Highest free' );
    if ($ip =~ /:/) {
	if ($m <= 80) { $list{20} = 'MAC based'; }
	if ($m <= 96) { $list{30} = 'IPv4 based'; }
    }
    return \%list;
}

=head1 FUNCTION: get_net_ip_policy

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
=head1 FUNCTION: get_free_ip_by_net

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
=head1 FUNCTION: get_ip_sugg

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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
	    $netid = $row_v[$ind2][3];
	    $alevel_n = $row_v[$ind2][4];
# Show virtual net to user only if alevel and permissions allow.
	    if ($alevel_u >= 998 || $alevel_u >= $alevel_n && (!%{$perms->{net}} || $perms->{net}->{$netid})) {
		$netname = $row_v[$ind2][0];
		$cidr = $row_v[$ind2][1];
		$ip_policy = $row_v[$ind2][2];
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


=head1 FUNCTION: get_vmps_by_name

Lookup VMPS ID by server and name.

Parameters:
  serverid - Server ID
  name     - VMPS name

Returns:
  VMPS ID - Success
  -3  - Invalid server ID (RET_INVALID_ARGUMENT)
  -2  - Not found (RET_NOT_FOUND)

=cut
sub get_vmps_by_name($$) {
  my($serverid,$name)=@_;
  my(@q);
  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  db_query("SELECT id FROM vmps WHERE server=$serverid AND name='$name'",\@q);
  return RET_NOT_FOUND unless (@q > 0);
  return ($q[0][0]);
}


=head1 FUNCTION: get_vmps

Retrieve VMPS record by ID.

Parameters:
  id  - VMPS ID
  rec - Hash reference to populate with VMPS data

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub get_vmps($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("vmps",
                      "server,name,description,comment,".
		      "mode,nodomainreq,fallback,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}



=head1 FUNCTION: update_vmps

Update VMPS record in transaction.

Parameters:
  rec - Hash reference with VMPS data including id

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE) or update_record error

=cut
sub update_vmps($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('vmps',$rec);
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_vmps: Failed to update vmps $rec->{id}");
      return $r; 
  }

  return db_commit();
}


=head1 FUNCTION: add_vmps

Create new VMPS record in transaction.

Parameters:
  rec - Hash reference with VMPS data

Returns:
  VMPS ID - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub add_vmps($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('vmps',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_vmps: Failed to add vmps record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_vmps

Delete VMPS record and update host references in transaction.

Parameters:
  id - VMPS ID

Returns:
  0  - Success
  -3 - Invalid VMPS ID (RET_INVALID_ARGUMENT)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub delete_vmps($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM vmps WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_vmps: Failed to delete vmps $id");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("UPDATE hosts SET vmps=-1 WHERE vmps=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_vmps: Failed to update host references for vmps $id");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_vmps_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_key

Retrieve KEY (DNSSEC key) record by ID.

Parameters:
  id  - KEY ID
  rec - Hash reference to populate with key data

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub get_key($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("keys",
                      "type,ref,name,keytype,nametype,protocol,algorithm,".
                      "mode,keysize,strength,publickey,secretkey,comment,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));

  add_std_fields($rec);
  return 0;
}



=head1 FUNCTION: update_key

Update KEY record in transaction.

Parameters:
  rec - Hash reference with key data including id

Returns:
  0  - Success
  -2 - Database error (DB_ERR_EXECUTE) or update_record error

=cut
sub update_key($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('keys',$rec);
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_key: Failed to update key $rec->{id}");
      return $r; 
  }

  return db_commit();
}


=head1 FUNCTION: add_key

Create new KEY record in transaction.

Parameters:
  rec - Hash reference with key data

Returns:
  KEY ID - Success
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub add_key($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  $res = add_record('keys',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_key: Failed to add key record");
      return DB_ERR_EXECUTE;
  }
  $id=$res;

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_key

Delete KEY record in transaction.

Parameters:
  id - KEY ID

Returns:
  0  - Success
  -3 - Invalid KEY ID (RET_INVALID_ARGUMENT)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub delete_key($) {
  my($id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);

  db_begin();

  $res=db_exec("DELETE FROM keys WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_key: Failed to delete key $id");
      return DB_ERR_EXECUTE;
  }


  #$res=db_exec("UPDATE acls SET vlan=-1 WHERE vlan=$id");
  #if ($res < 0) { db_rollback(); return -10; }

  return db_commit();
}

=head1 FUNCTION: get_key_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_key_by_name

Lookup KEY ID by server and name.

Parameters:
  serverid - Server ID
  name - KEY name

Returns:
  KEY ID - Success
  -3 - Invalid server ID (RET_INVALID_ARGUMENT)
  -3 - Invalid name (RET_INVALID_ARGUMENT)
  -2 - Not found (RET_NOT_FOUND)

=cut
sub get_key_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  return RET_INVALID_ARGUMENT unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM keys " .
	   "WHERE type=1 AND ref=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}


############################################################################
# ACL functions


=head1 FUNCTION: get_acl

Retrieve ACL record by ID.

Parameters:
  id  - ACL ID
  rec - Hash reference with ACL data

Returns:
  0  - Success
  -2 - Database error

=cut
sub get_acl($$) {
  my ($id,$rec) = @_;

  return DB_ERR_EXECUTE if (get_record("acls",
		      "server,name,type,comment,".
		      "cdate,cuser,mdate,muser", $id,$rec,"id"));
  add_std_fields($rec);
  get_aml_field($rec->{server},0,$id,$rec,'acl');
  return 0;
}



=head1 FUNCTION: update_acl

Update ACL record and AML field in transaction.

Parameters:
  rec - Hash reference with ACL data including id

Returns:
  0  - Success
  -2 - Database error

=cut
sub update_acl($) {
  my($rec) = @_;
  my($r,$id);

  del_std_fields($rec);

  db_begin();
  $r=update_record('acls',$rec);
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_acl: Failed to update acl");
      return $r; 
  }
  $id=$rec->{id};

  $r=update_aml_field(0,$id,$rec,'acl');
  if ($r < 0) { 
      db_rollback(); 
      write2log("update_acl: Failed to update aml_field");
      return DB_ERR_EXECUTE; 
  }

  return db_commit();
}


=head1 FUNCTION: add_acl

Create new ACL record with AML field in transaction.

Parameters:
  rec - Hash reference with ACL data

Returns:
  ACL ID - Success
  -2 - Database error

=cut
sub add_acl($) {
  my($rec) = @_;
  my($res,$id,$i);

  db_begin();
  $rec->{cdate}=time;
  $rec->{cuser} = $muser if !$rec->{'cuser'};
  $res = add_record('acls',$rec);
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_acl: Failed to add acl");
      return DB_ERR_EXECUTE;
  }
  $rec->{id}=$id=$res;

  $res=update_aml_field(0,$id,$rec,'acl');
  if ($res < 0) { 
      db_rollback(); 
      write2log("add_acl: Failed to update aml_field");
      return DB_ERR_EXECUTE;
  }

  return DB_ERR_EXECUTE if (db_commit() < 0);
  return $id;
}


=head1 FUNCTION: delete_acl

Delete ACL record and update CIDR entries in transaction.

Parameters:
  id     - ACL ID
  newref - New ACL reference

Returns:
  0  - Success
  -3 - Invalid ACL ID (RET_INVALID_ARGUMENT)
  -2 - Database error

=cut
sub delete_acl($$) {
  my($id,$newref) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($id > 0);
  $newref=-1 unless ($newref > 0 && $newref != $id);

  db_begin();

  $res=db_exec("DELETE FROM acls WHERE id=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_acl: Failed to delete acl");
      return DB_ERR_EXECUTE;
  }

  $res=db_exec("DELETE FROM cidr_entries WHERE type=0 AND ref=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_acl: Failed to delete cidr_entries");
      return DB_ERR_EXECUTE;
  }
  $res=db_exec("UPDATE cidr_entries SET acl=$newref ".
	       "WHERE type>0 AND acl=$id");
  if ($res < 0) { 
      db_rollback(); 
      write2log("delete_acl: Failed to update cidr_entries");
      return DB_ERR_EXECUTE;
  }

  return db_commit();
}

=head1 FUNCTION: get_acl_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_acl_by_name

Lookup ACL ID by server and name.

Parameters:
  serverid - Server ID
  name - ACL name

Returns:
  ACL ID - Success
  -3 - Invalid server ID (RET_INVALID_ARGUMENT)
  -3 - Invalid name (RET_INVALID_ARGUMENT)
  -2 - Not found (RET_NOT_FOUND)

=cut
sub get_acl_by_name($$) {
  my($serverid,$name) = @_;
  my(@q);

  return RET_INVALID_ARGUMENT unless ($serverid > 0);
  return RET_INVALID_ARGUMENT unless ($name);
  $name=db_encode_str($name);
  db_query("SELECT id FROM acls " .
	   "WHERE server=$serverid AND name=$name",\@q);
  return ($q[0][0] > 0 ? $q[0][0] : RET_NOT_FOUND);
}


############################################################################
# news functions

=head1 FUNCTION: add_news

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub add_news($) {
  my($rec) = @_;

  $rec->{cdate}=time;
  $rec->{cuser}=$muser;
  return add_record('news',$rec);
}

=head1 FUNCTION: get_news_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: get_who_list

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: cgi_disabled

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub cgi_disabled() {
  my(@q);
  db_query("SELECT value FROM settings WHERE setting='cgi_disable';",\@q);
  return ''if ($q[0][0] =~ /^\s*$/);
  return $q[0][0];
}


=head1 FUNCTION: get_permissions

Retrieve user permissions and access rules for all object types.

Parameters:
  uid - User ID
  rec - Hash reference to populate with permission data

Returns:
  0  - Success
  -3 - Invalid user ID (RET_INVALID_ARGUMENT)
  -3 - No record provided (RET_INVALID_ARGUMENT)

=cut
sub get_permissions($$) {
  my($uid,$rec) = @_;
  my(@q,$i,$type,$ref,$mode,$s,$e,$sql);

  return RET_INVALID_ARGUMENT unless ($uid > 0);
  return RET_INVALID_ARGUMENT unless ($rec);

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



=head1 FUNCTION: update_lastlog

Update or insert login/logout record in lastlog table.

Parameters:
  uid   - User ID
  sid   - Session ID
  type  - Event type (1=login)
  ip    - IP address
  host  - Hostname

Returns:
  0  - Success
  -3 - Invalid user/session/type ID (RET_INVALID_ARGUMENT)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub update_lastlog($$$$$) {
  my($uid,$sid,$type,$ip,$host) = @_;
  my($date,$i,$h,$ldate);

  return RET_INVALID_ARGUMENT unless ($uid > 0);
  return RET_INVALID_ARGUMENT unless ($sid > 0);
  return RET_INVALID_ARGUMENT unless ($type > 0);

  if ($type == 1) {
    $date=time;
    $i=db_encode_str($ip);
    $h=db_encode_str($host);
    return DB_ERR_EXECUTE if (db_exec("INSERT INTO lastlog " .
			   "(sid,uid,date,state,ip,host) " .
			   " VALUES($sid,$uid,$date,1,$i,$h);") < 0);
  } else {
    $ldate=time;
    return DB_ERR_EXECUTE if (db_exec("UPDATE lastlog SET ldate=$ldate,state=$type " .
			   "WHERE sid=$sid;") < 0);
  }
  return 0;
}


=head1 FUNCTION: update_history

Insert history log record for user/system actions.

Parameters:
  uid    - User ID (-1 allowed for system)
  sid    - Session ID (-1 allowed for system)
  type   - History type
  action - Action description
  info   - Additional info
  ref    - Reference ID (0 if none)

Returns:
  0  - Success
  -3 - Invalid type (RET_INVALID_ARGUMENT)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub update_history($$$$$$) {
  my($uid,$sid,$type,$action,$info,$ref) = @_;
  my($date,$a,$i,$sql);

# uid and sid are -1 in some command line scripts
  return RET_INVALID_ARGUMENT unless ($uid > 0 || $uid == -1);
  return RET_INVALID_ARGUMENT unless ($sid > 0 || $sid == -1);
  return RET_INVALID_ARGUMENT unless ($type > 0);
  $date=time;
  $a=db_encode_str($action);
  $i=db_encode_str($info);
  $ref='NULL' unless ($ref > 0);

  $sql = "INSERT INTO history (sid,uid,date,type,action,info,ref) " .
         " VALUES($sid,$uid,$date,$type,$a,$i,$ref);";
  return DB_ERR_EXECUTE if (db_exec($sql)<0);

  return 0;
}


=head1 FUNCTION: fix_utmp

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub fix_utmp($$) {
  my($timeout, $check_zero) = @_;
  my($i,$t,@q);

  $t=time - $timeout;
  if ($check_zero) {
    db_query("SELECT cookie,uid,sid FROM utmp WHERE last < $t and last != 0;",\@q);
  } else {
    db_query("SELECT cookie,uid,sid FROM utmp WHERE last < $t;",\@q);
  }

  if (@q > 0) {
    for $i (0..$#q) {
      update_lastlog($q[$i][1],$q[$i][2],3,'','');
      db_exec("DELETE FROM utmp WHERE cookie='$q[$i][0]';");
    }
  }
}


=head1 FUNCTION: get_lastlog

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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

=head1 FUNCTION: get_history_host

Description:
  Load history entries associated with one host and map user IDs to usernames.

Parameters:
  id   - Host ID
  list - Array reference for output rows

Returns:
  0  - Success
  -1 - Invalid host ID

=cut

sub get_history_host($$)
{
  my ($id,$list) = @_;
  my (@q,%users,$i);

  unless ($id > 0) {
    write2log("get_history_host: Invalid host id=$id");
    return -1;
  }
  db_query("SELECT date,action,info,uid FROM history ".
	   "WHERE type=1 AND ref=$id ORDER BY date ",$list);
  db_query("SELECT id,username FROM users",\@q);
  for $i (0..$#q) { $users{$q[$i][0]}=$q[$i][1]; }
  for $i (0..$#{$list}) {
    $$list[$i][3] = $users{$$list[$i][3]} if ($users{$$list[$i][3]});
  }
  return 0;
}

=head1 FUNCTION: get_history_host

Description:
  Load history entries associated with a host and map user IDs to usernames.

Parameters:
  id   - Host ID
  list - Array reference for results

Returns:
  0  - Success
  -1 - Invalid host ID

=cut

=head1 FUNCTION: get_history_session

Description:
  Load history entries associated with one session.

Parameters:
  id   - Session ID
  list - Array reference for output rows

Returns:
  0  - Success
  -1 - Invalid session ID

=cut

sub get_history_session($$)
{
  my ($id,$list) = @_;
  my (@q,%users,$i);

  unless ($id > 0) {
    write2log("get_history_session: Invalid session id=$id");
    return -1;
  }
  db_query("SELECT date,type,ref,action,info FROM history ".
	   "WHERE sid=$id ORDER BY date ",$list);

  return 0;
}

=head1 FUNCTION: get_history_session

Description:
  Load history entries for a given session ID.

Parameters:
  id   - Session ID
  list - Array reference for results

Returns:
  0  - Success
  -1 - Invalid session ID

=cut


=head1 FUNCTION: save_state

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub save_state($$) {
  my($id,$state)=@_;
  my(@q,$res,$s_auth,$s_addr,$other,$s_mode,$s_superuser);

  undef @q;
  db_query("SELECT uid,cookie FROM utmp WHERE cookie='$id';",\@q);
  unless (@q > 0) {
      if (db_exec("INSERT INTO utmp (uid,cookie,auth) " .
		  "VALUES(-1,'$id',false);") < 0) {
	write2log("save_state: Failed to insert utmp state for cookie=$id");
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


=head1 FUNCTION: load_state

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
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


=head1 FUNCTION: remove_state

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub remove_state($) {
  my($id) = @_;

  unless ($id) {
    write2log("remove_state: Missing cookie id");
    return -1;
  }
  if (db_exec("DELETE FROM utmp WHERE cookie='$id'") < 0) {
    write2log("remove_state: Failed to delete utmp state for cookie=$id");
    return -2;
  }
  return 1;
}

###############################################################################
# Catalog zones support (RFC 9432)

=head1 FUNCTION: is_catalog_zone

Description:
  Internal function in BackEnd module.

Parameters:
  See function signature and call sites.

Returns:
  Function-specific value or error code.

=cut
sub is_catalog_zone($) {
  my($zone_id) = @_;
  my(@q);

  unless ($zone_id > 0) {
    write2log("is_catalog_zone: Invalid zone id=$zone_id");
    return -1;
  }

  db_query("SELECT type FROM zones WHERE id=$zone_id", \@q);
  unless (@q > 0) {
    write2log("is_catalog_zone: Zone id=$zone_id not found");
    return -2;
  }

  return ($q[0][0] eq 'C' ? 1 : 0);
}

=head1 FUNCTION: validate_zone_for_catalog

  Validate that zone can be added to catalog (type checking).

  Parameters:
    zone_id         - Zone ID to add
    catalog_zone_id - Catalog zone ID

  Returns:
    0  - Valid
    -3 - Invalid zone IDs (RET_INVALID_ARGUMENT)
    -2 - Self-reference prevented (RET_NOT_FOUND)
    -2 - Catalog is not type C (RET_NOT_FOUND)
    -2 - Zone already type C (RET_NOT_FOUND)

=cut

  sub validate_zone_for_catalog($$) {
  my($zone_id, $catalog_zone_id) = @_;
  my(@q, %zone, %catalog);

  return RET_INVALID_ARGUMENT unless ($zone_id > 0 && $catalog_zone_id > 0);
  return RET_NOT_FOUND if ($zone_id == $catalog_zone_id);

  # Check that catalog zone is actually type 'C'
  db_query("SELECT type FROM zones WHERE id=$catalog_zone_id", \@q);
  return RET_NOT_FOUND unless (@q > 0 && $q[0][0] eq 'C');

  # Check that zone to be added is not type 'C'
  db_query("SELECT type FROM zones WHERE id=$zone_id", \@q);
  return RET_NOT_FOUND unless (@q > 0 && $q[0][0] ne 'C');

  return 0;  # Valid
}


=head1 FUNCTION: get_zone_catalog_members

Get member zones of a catalog zone.

Parameters:
  catalog_zone_id - Catalog zone ID  
  rec - Hash reference to populate with member data

Returns:
  0  - Success
  -3 - Invalid catalog zone ID (RET_INVALID_ARGUMENT)

=cut
sub get_zone_catalog_members($$) {
  my($catalog_zone_id, $rec) = @_;
  my(@q, $i);

  return RET_INVALID_ARGUMENT unless ($catalog_zone_id > 0);

  $rec = {} unless (ref($rec) eq 'HASH');

  db_query("SELECT zc.member_zone_id, z.name, z.type, z.server, s.name, zc.version " .
           "FROM zone_catalogs zc " .
           "JOIN zones z ON zc.member_zone_id = z.id " .
           "JOIN servers s ON z.server = s.id " .
           "WHERE zc.catalog_zone_id = $catalog_zone_id " .
           "ORDER BY z.name", \@q);

  $rec->{count} = @q;
  $rec->{members} = \@q;

  return 0;
}


=head1 FUNCTION: get_zone_catalogs

Get all catalog zones that contain a given zone.

Parameters:
  zone_id - Zone ID
  rec - Hash reference to populate with catalog data

Returns:
  0  - Success
  -3 - Invalid zone ID (RET_INVALID_ARGUMENT)

=cut
sub get_zone_catalogs($$) {
  my($zone_id, $rec) = @_;
  my(@q, $i);

  return RET_INVALID_ARGUMENT unless ($zone_id > 0);

  $rec = {} unless (ref($rec) eq 'HASH');

  db_query("SELECT zc.catalog_zone_id, z.name, z.server, zc.version " .
           "FROM zone_catalogs zc " .
           "JOIN zones z ON zc.catalog_zone_id = z.id " .
           "WHERE zc.member_zone_id = $zone_id " .
           "ORDER BY z.name", \@q);

  $rec->{count} = @q;
  $rec->{catalogs} = \@q;

  return 0;
}


=head1 FUNCTION: get_catalog_zones_for_selection

Get available catalog zones for adding member zones.

Parameters:
  zone_id   - Zone ID  
  server_id - Server ID
  rec - Hash reference to populate

Returns:
  0  - Success
  -3 - Invalid server ID (RET_INVALID_ARGUMENT)

=cut
sub get_catalog_zones_for_selection($$$) {
  my($zone_id, $server_id, $rec) = @_;
  my(@q, @available, @selected, %selected_ids);

  return RET_INVALID_ARGUMENT unless ($server_id > 0);

  $rec = {} unless (ref($rec) eq 'HASH');

  # Get all catalog zones from this server
  db_query("SELECT id, name, comment FROM zones " .
           "WHERE server = $server_id AND type = 'C' " .
           "ORDER BY name", \@available);

  # Build list for form display (ftype 14)
  my @catalog_list;
  for my $zone_row (@available) {
    push @catalog_list, [$zone_row->[0], $zone_row->[1], $zone_row->[2]];
  }
  $rec->{available_catalogs} = \@catalog_list;

  # Get currently selected catalogs for this zone (if zone_id is valid)
  if ($zone_id > 0) {
    db_query("SELECT catalog_zone_id FROM zone_catalogs " .
             "WHERE member_zone_id = $zone_id " .
             "ORDER BY catalog_zone_id", \@selected);

    # Create a hash of selected IDs
    for my $sel_row (@selected) {
      $selected_ids{$sel_row->[0]} = 1;
    }

    # Build selected array for form
    my @selected_cat_ids;
    for my $zone_row (@available) {
      if ($selected_ids{$zone_row->[0]}) {
        push @selected_cat_ids, $zone_row->[0];
      }
    }
    $rec->{catalog_zones_selected} = \@selected_cat_ids;
  } else {
    $rec->{catalog_zones_selected} = [];
  }

  return 0;
}


=head1 FUNCTION: add_zone_to_catalog

Add zone as member of catalog zone.

Parameters:
  zone_id - Zone ID
  catalog_zone_id - Catalog zone ID

Returns:
  1  - Success
  -3 - Invalid IDs (RET_INVALID_ARGUMENT)

=cut
sub add_zone_to_catalog($$) {
  my($zone_id, $catalog_zone_id) = @_;
  my($res, $version);

  return RET_INVALID_ARGUMENT unless ($zone_id > 0 && $catalog_zone_id > 0);

  # Validate relationship
  $res = validate_zone_for_catalog($zone_id, $catalog_zone_id);
  return $res if ($res < 0);

  # Check if zone is already in catalog
  my(@q);
  $res = db_query("SELECT id FROM zone_catalogs " .
           "WHERE catalog_zone_id=$catalog_zone_id AND member_zone_id=$zone_id", \@q);
  return DB_ERR_EXECUTE if ($res < 0);  # Query failed
  return RET_NOT_FOUND if (@q > 0);  # Already exists

  # Insert new relationship
  # BIND 9 catalog zones use version '2' (RFC 9432)
  $version = '2';

  my $insert_sql = "INSERT INTO zone_catalogs (catalog_zone_id, member_zone_id, version) " .
                   "VALUES($catalog_zone_id, $zone_id, '$version')";

  $res = db_exec($insert_sql);

  if ($res < 0) {
    write2log("ERROR: Failed to add zone $zone_id to catalog $catalog_zone_id: $res");
  }

  return $res;
}


=head1 FUNCTION: remove_zone_from_catalog

Remove zone from catalog zone membership.

Parameters:
  zone_id - Zone ID
  catalog_zone_id - Catalog zone ID

Returns:
  0  - Success
  -3 - Invalid IDs (RET_INVALID_ARGUMENT)
  -2 - Database error (DB_ERR_EXECUTE)

=cut
sub remove_zone_from_catalog($$) {
  my($zone_id, $catalog_zone_id) = @_;
  my($res);

  return RET_INVALID_ARGUMENT unless ($zone_id > 0 && $catalog_zone_id > 0);

  $res = db_exec("DELETE FROM zone_catalogs " .
                 "WHERE catalog_zone_id=$catalog_zone_id AND member_zone_id=$zone_id");

  return $res;
}

1;
# eof
