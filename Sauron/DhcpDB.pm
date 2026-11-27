# Sauron::DhcpDB.pm - build the DHCP model (Sauron::DhcpModel) of a server
#                     from the Sauron database
#
# The loader resolves everything that depends on database contents (dynamic
# pool ranges, subnet routers, host addresses incl. ether aliases, group
# %{macros}, automatic domain names, duplicate interfaces) so that writers
# (ISC dhcpd.conf, KEA JSON) only lay the model out.
#
# Statements loaded from dhcp_entries keep their database text in
# $stmt->{orig} and the entry comment in $stmt->{comment}; the ISC writer
# uses them to reproduce the configuration verbatim.
#
# The behaviour follows the original generator in 'sauron'; its remaining
# peculiarities are marked 'QUIRK' below.
#
package Sauron::DhcpDB;
require Exporter;
use NetAddr::IP;
use Socket ();
use Net::IP qw(:PROC);
use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;
use Sauron::DhcpDefs;
use Sauron::DhcpModel;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_model_from_db dhcp_model_to_db dhcp_db_resolver
	     dhcp_ha_from_db dhcp_d2_from_db);

# dhcp_entries.type per address family
my %_ETYPE = (
  4 => { global => 1,  host => 3,  net => 4, group => 5,  vlan => 6,  local => 7 },
  6 => { global => 11, host => 13, net => 4,  group => 15, vlan => 16, local => 17 },
);
# nets have a single DHCP entry list (type 4) for both families, a net is
# either IPv4 or IPv6

my $_EXPIRED_ZONE = " AND (coalesce(z.expiration, 0) <= 0 OR " .
  "coalesce(z.expiration, 0) > extract(epoch from now())) ";

# statement for a dhcp_entries row (text, comment, fmt)
sub _row_stmt($$$) {
  my ($model,$scope,$row) = @_;
  my ($text,$comment,$fmt) = @$row;
  my $st;

  $text = '' unless (defined $text);
  if ($fmt && $fmt == DHCP_FMT_KEA) {
    $st = kea_json_to_statement($text,$model->{family});
    dhcp_model_warn($model,$st->{error}) if ($st->{error});
    dhcp_scope_add_stmt($model,$scope,$st);
  } else {
    $st = dhcp_scope_add_isc($model,$scope,$text);
    $st->{orig} = $text;
    $st->{fmt} = DHCP_FMT_ISC if ($fmt && $fmt == DHCP_FMT_ISC);
  }
  $st->{comment} = $comment;
  return $st;
}

# add dhcp_entries rows (text, comment, fmt) to scope
sub _add_entries($$$) {
  my ($model,$scope,$rows) = @_;

  _row_stmt($model,$scope,$_) foreach (@$rows);
}

sub _entries($$) {
  my ($type,$ref) = @_;
  my @q;

  db_query("SELECT dhcp, comment, fmt FROM dhcp_entries " .
	   "WHERE type=$type AND ref=$ref ORDER BY id",\@q);
  return \@q;
}

# dhcp_model_from_db(\%opts) - load DHCP model of a server
#   family           4 or 6
#   server           server record (get_server) of the generated server
#   serverid         id of the server whose data is used (master server
#                    for a slave)
#   masterserver     master server record (slave only)
#   auto_domainnames add 'option domain-name' (dhcp_flags_ad)
#   failover_mode    0 = none, 1 = primary, 2 = secondary
#   failover_peer    failover peer name
#   now              current time (epoch) for host expiration
#   class            only load this class (sauron --dhcpclass)
#   verbose          progress messages to STDERR
# returns model
sub dhcp_model_from_db($) {
  my ($o) = @_;
  my $v6 = ($o->{family} && $o->{family} == 6 ? 1 : 0);
  my $f = ($v6 ? 6 : 4);
  my $et = $_ETYPE{$f};
  my $sid = $o->{serverid};
  my $server = $o->{server};
  my $model = dhcp_model_new($f);

  $model->{server} = { name => $server->{name}, comment => $server->{comment} };
  $model->{local} = dhcp_scope_new();
  $model->{netblocks} = [];
  $model->{class_only} = ($o->{class} ? 1 : 0);

  _load_classes($model,$o);
  return $model if ($o->{class});

  _load_failover($model,$o);

  # local (per server, also on slaves) and global entries
  _add_entries($model,$model->{local},_entries($et->{local},$server->{id}));
  _add_entries($model,$model->{global},_entries($et->{global},$sid));

  _load_network_map($model,$o);
  _load_hosts($model,$o);

  return $model;
}


###########################################################################

sub _load_failover($$) {
  my ($model,$o) = @_;
  my ($fo,$srv,$peer,$x,@q);
  my $mode = $o->{failover_mode};
  my $sfx = ($model->{family} == 6 ? '6' : '');

  return unless ($mode);
  # ISC DHCPv6 has no failover protocol (a declared peer without pools
  # referring to it makes dhcpd -6 refuse the configuration)
  return if ($model->{family} == 6);
  $srv = ($mode == 1 ? $o->{server} : $o->{masterserver});
  if ($mode == 1) {
    db_query("SELECT hostname FROM servers " .
	     "WHERE masterserver=$o->{server}{id}",\@q);
    error("cannot find secondary failover peer!") unless ($q[0][0]);
    $peer = $q[0][0];
  } else {
    $peer = $srv->{hostname};
  }
  ($x = $o->{server}{hostname}) =~ s/\.\s*$//;
  $peer =~ s/\.\s*$// if (defined $peer);

  $fo = { name => $o->{failover_peer}, role => ($mode == 1 ? 'primary' : 'secondary'),
	  address => $x, peer_address => $peer,
	  port => $srv->{"df_port$sfx"}, peer_port => $srv->{"df_port$sfx"},
	  max_response_delay => $srv->{"df_max_delay$sfx"},
	  max_unacked_updates => $srv->{"df_max_uupdates$sfx"},
	  mclt => $srv->{"df_mclt$sfx"}, split => $srv->{"df_split$sfx"},
	  load_balance_max => $srv->{"df_loadbalmax$sfx"} };
  $model->{failover} = $fo;
}


# classes: type 3 (subclassed by MAC/DUID), 103 (custom)
sub _load_classes($$) {
  my ($model,$o) = @_;
  my $v6 = ($model->{family} == 6);
  my $sid = $o->{serverid};
  my ($idcol,$idre,@dclasses);

  db_query("SELECT id,name,type FROM groups " .
	   "WHERE server=$sid AND (type=3 OR type=103) " .
	   ($o->{class} ? " AND name=".db_encode_str($o->{class})." " : "") .
	   "ORDER BY name",\@dclasses);
  # the classes section is generated whenever classes exist
  $model->{classes_found} = scalar(@dclasses);

  $idcol = ($v6 ? 'duid' : 'ether');
  foreach my $c (@dclasses) {
    my ($cid,$name,$type) = @$c;
    my (@qq,@members,$last);

    db_query("SELECT h.$idcol,h.domain " .
	     " FROM zones z JOIN hosts h ON z.id=h.zone " .
	     " LEFT JOIN group_entries g ON h.id=g.host " .
	     " WHERE z.server=$sid AND h.$idcol NOTNULL " . $_EXPIRED_ZONE .
	     " AND (h.grp=$cid OR g.grp=$cid) " .
	     " AND (h.expiration > EXTRACT(epoch FROM current_timestamp) " .
	     "  OR h.expiration = 0 OR h.expiration ISNULL) " .
	     " ORDER BY h.$idcol",\@qq);
    # QUIRK: classes without member hosts are not generated in dhcpd.conf
    # (incl. 103), see DhcpIsc

    if ($type == 3) {
      $last = '';
      foreach my $m (@qq) {
	if ($v6) {
	  unless ($m->[0] =~ /^[a-f0-9A-F]{24,40}$/) {
	    error("invalid duid for subclass: $m->[0]");
	    next;
	  }
	} else {
	  next unless ($m->[0] =~ /^[0-9A-F]{12}$/);
	}
	next if ($m->[0] eq $last);
	push @members, { id => ($v6 ? dhcpduid($m->[0]) : dhcpether($m->[0])),
			 name => $m->[1] };
	$last = $m->[0];
      }
    }

    my $cl = dhcp_model_add($model,'classes',
			    { name => $name, type => $type, members => \@members,
			      empty => (@qq ? 0 : 1) });
    _add_entries($model,$cl->{scope},_entries($_ETYPE{$model->{family}}{group},$cid));
  }
}


# shared-networks, subnets, routers, dynamic pools
sub _load_network_map($$) {
  my ($model,$o) = @_;
  my $v6 = ($model->{family} == 6);
  my $f = $model->{family};
  my $et = $_ETYPE{$f};
  my $sid = $o->{serverid};
  my (@dpools,@dips,@nets,@subnets,@routers,%vlanhash,%vlan_names,@vlan_lst);

  # dynamic pools and their member addresses
  db_query("SELECT id,name FROM groups WHERE server=$sid AND type=2 " .
	   "ORDER BY name",\@dpools);
  if (@dpools > 0) {
    print STDERR "Found " . scalar(@dpools) .
      ($v6 ? " dynamic IPv6 pools\n" : " dynamic IP pools\n") if ($o->{verbose});
    if ($v6) {
      # QUIRK: expired and non-host records are not excluded for DHCPv6
      db_query("SELECT g.id,a.ip,h.domain ".
	       "FROM hosts h, a_entries a, groups g ".
	       "WHERE a.host=h.id AND g.id=h.grp AND g.type=2 ".
	       " AND g.server=$sid AND family(a.ip) = 6 ORDER BY a.ip,g.id",\@dips);
    } else {
      db_query("SELECT g.id,a.ip,h.domain ".
	       "FROM hosts h, a_entries a, groups g ".
	       "WHERE a.host=h.id AND g.id=h.grp AND g.type=2 AND h.type=1" .
	       " AND ( COALESCE(h.expiration,0) = 0 OR h.expiration > $o->{now} )".
	       " AND g.server=$sid AND family(a.ip) = 4 ORDER BY a.ip,g.id",\@dips);
    }
    print STDERR "Found " . scalar(@dips) . " dynamic pool IPs\n" if ($o->{verbose});
    $_->[3] = _ipobj($v6,$_->[1]) foreach (@dips);
    foreach my $p (@dpools) {
      $p->[2] = _entries($et->{group},$p->[0]);
    }
  }

  # top level nets and their subnets
  db_query("SELECT net,name,id,vlan " .
	   "FROM nets WHERE server=$sid AND no_dhcp=false " .
	   "AND subnet=false AND dummy=false AND family(net) = $f ORDER BY net",\@nets);
  fatal($v6 ? "No nets, that use DHCP6, defined for this server!"
	    : "No nets, that use DHCP, defined for this server!") if (@nets < 1);

  foreach my $n (@nets) {
    my @q;
    push @{$model->{netblocks}}, { cidr => $n->[0], name => $n->[1] };
    db_query("SELECT net,id,name,vlan FROM nets " .
	     "WHERE server=$sid AND no_dhcp=false AND subnet=true " .
	     "AND dummy=false AND net << '$n->[0]' AND family(net) = $f " .
	     "ORDER BY net;",\@q);
    push @q, [$n->[0],$n->[2],$n->[1],$n->[3]] if (@q < 1);
    push @subnets, @q;
  }

  # router interfaces
  db_query("SELECT ip,router FROM hosts h,zones z,a_entries a " .
	   "WHERE h.zone=z.id AND a.host=h.id " . $_EXPIRED_ZONE .
	   "AND z.server=$sid AND router>0 AND family(ip) = $f " .
	   "ORDER BY ip,router;",\@routers);
  $_->[2] = _ipobj($v6,$_->[0]) foreach (@routers);

  # shared-networks (VLANs); QUIRK: VLAN ids are sorted as strings
  $vlanhash{$_->[3]}++ foreach (@subnets);
  get_vlan_list($sid,\%vlan_names,\@vlan_lst);
  foreach my $vlan (sort keys %vlanhash) {
    my $name = $vlan_names{$vlan};
    $name =~ s/\s//g;
    $name = 'CHAOS' if ($vlan < 1 || $name eq '');
    my $vl = dhcp_model_add($model,'vlans',{ name => $name, id => $vlan, nets => [] });
    _add_entries($model,$vl->{scope},_entries($et->{vlan},$vlan));

    error("No router interfaces found for net $nets[-1][0]!")
      if (!$v6 && @routers < 1);
    foreach my $s (grep { $_->[3] eq $vlan } @subnets) {
      my $net = _load_subnet($model,$o,$s,\@routers,\@dpools,\@dips);
      $net->{vlan} = $vl->{name};
      push @{$vl->{nets}}, $net;
    }
  }
}

sub _load_subnet($$$$$$) {
  my ($model,$o,$s,$routers,$dpools,$dips) = @_;
  my $v6 = ($model->{family} == 6);
  my ($ssnet,$router,$pri,$net);

  $net = dhcp_model_add($model,'nets',{ cidr => $s->[0], name => $s->[2],
					 id => $s->[1], pools => [] });

  # router with the lowest priority value within the subnet
  $ssnet = _ipobj($v6,$s->[0]);
  $pri = 999999;
  $router = '';
  foreach my $r (@$routers) {
    if (_contains($v6,$ssnet,$r->[2]) && $pri > $r->[1]) {
      $pri = $r->[1];
      $router = $r->[0];
    }
  }
  if ($router ne '') {
    $router =~ s/\/\d{1,3}\s*$//g;
    $net->{router} = $router;
  } elsif (!$v6) {
    my $nh = new NetAddr::IP($s->[0]);
    error("no router interface found for subnet: " . $nh->addr() . " " . $nh->mask());
  }
  _add_entries($model,$net->{scope},_entries($_ETYPE{$model->{family}}{net},$s->[1]));

  # dynamic pools: contiguous address runs of pool member hosts
  foreach my $p (@$dpools) {
    my ($state,$b,$last,$lastobj) = (0,'','',undef);
    my $emit = sub {
      my ($start,$end) = @_;
      my $pool = dhcp_model_add($model,'pools',{ name => $p->[1], net => $s->[0],
						 start => $start, end => $end });
      # a single address is 'range X' in ISC, but range6 needs both ends
      my $rs = parse_isc_statement(($v6 ? "range6 $start $end" :
				    'range ' . ($start eq $end ? $start : "$start $end")),
				   $model->{family});
      push @{$pool->{ranges}}, $rs;
      _add_entries($model,$pool->{scope},$p->[2]);
      push @{$net->{pools}}, $pool;
      print STDERR "dynamic range $start - $end ($p->[1])\n" if ($o->{verbose});
    };

    foreach my $d (@$dips) {
      my $in = ($d->[0] == $p->[0]) && _contains($v6,$ssnet,$d->[3]);
      if ($in) {
	if ($state == 0) {
	  $state = 1;
	  $b = $d->[1];
	}
	elsif ($last ne '' && _gap($v6,$lastobj,$d->[3])) {
	  $emit->($b,$last);
	  $b = $d->[1];
	}
	$last = $d->[1];
	$lastobj = $d->[3];
      } else {
	$emit->($b,$last) if ($state == 1);
	$state = 0;
      }
    }
    $emit->($b,$last) if ($state == 1);
  }

  return $net;
}

sub _ipobj($$) { return dhcp_ip_obj($_[0],$_[1]); }
sub _contains($$$) { return dhcp_ip_in($_[0],$_[1],$_[2]); }

# true if there is at least one address between address objects $a and $b
sub _gap($$$) {
  my ($v6,$a,$b) = @_;

  return ($b->intip() > $a->intip() + 1) if ($v6);
  return ($b - $a > 1);
}


###########################################################################
# hosts

sub _load_hosts($$) {
  my ($model,$o) = @_;
  my $v6 = ($model->{family} == 6);
  my $f = $model->{family};
  my $et = $_ETYPE{$f};
  my $sid = $o->{serverid};
  my $idcol = ($v6 ? 'duid' : 'ether');
  my (@q,%idhash,%hentries,%seen,@groups,@ghosts,@nets,%ipobj);

  # addresses per interface id (incl. ether aliases for DHCPv4)
  db_query("SELECT h.$idcol,a.ip FROM hosts h,zones z,a_entries a " .
	   "WHERE z.server=$sid AND h.zone=z.id AND a.host=h.id " .
	   $_EXPIRED_ZONE . " AND h.$idcol NOTNULL AND family(a.ip) = $f;",\@q);
  error(db_errormsg()) if (db_errormsg());
  foreach my $r (@q) {
    if ($v6) {
      unless ($r->[0] =~ /^[0-9A-Fa-f]{24,40}\s*$/) {
	error("Invalid DUID ($r->[0]) skipped");
	next;
      }
    } else {
      unless ($r->[0] =~ /^[0-9A-F]{12}$/) {
	error("Invalid MAC address ($r->[0]) skipped");
	next;
      }
    }
    push @{$idhash{$r->[0]}}, $r->[1];
  }
  unless ($v6) {
    undef @q;
    db_query("SELECT b.ether,c.ip FROM hosts a, hosts b, zones z, a_entries c ".
	     "WHERE z.server=$sid AND a.zone=z.id AND a.ether_alias=b.id ".
	     $_EXPIRED_ZONE . " AND c.host=a.id AND family(c.ip) = 4;",\@q);
    error(db_errormsg()) if (db_errormsg());
    foreach my $r (@q) {
      unless ($r->[0] =~ /^[0-9A-F]{12}$/) {
	error("Invalid MAC address ($r->[0]) skipped (ether_alias)");
	next;
      }
      push @{$idhash{$r->[0]}}, $r->[1];
    }
  }

  # sort address lists once, cache address objects
  foreach my $ips (values %idhash) {
    @$ips = sort(@$ips) if (@$ips > 1);
    $ipobj{$_} = _ipobj($v6,$_) foreach (@$ips);
  }
  $model->{_ipobj} = \%ipobj;

  # host entries
  undef @q;
  db_query("SELECT h.id,d.dhcp,d.comment,d.fmt FROM hosts h,zones z,dhcp_entries d " .
	   "WHERE z.server=$sid AND h.zone=z.id AND d.type=$et->{host} " .
	   $_EXPIRED_ZONE . " AND d.ref=h.id ORDER BY h.id,d.id",\@q);
  push @{$hentries{$_->[0]}}, [ (defined $_->[1] ? $_->[1] : ''), $_->[2], $_->[3] ]
    foreach (@q);

  @nets = map { _ipobj($v6,$_->{cidr}) } @{$model->{netblocks}};

  # grouped hosts
  db_query("SELECT id,name FROM groups WHERE server=$sid AND type=1 " .
	   "ORDER BY name;",\@groups);
  if (@groups < 1) {
    error("no groups found for this server");
  } else {
    db_query("SELECT h.grp,h.$idcol,a.ip,h.domain,z.name,h.id,h.expiration " .
	     "FROM hosts h, zones z, a_entries a " .
	     "WHERE h.zone=z.id AND a.host=h.id AND h.type=1 " . $_EXPIRED_ZONE .
	     "AND h.$idcol NOTNULL AND z.server=$sid " .
	     "AND h.grp>-1 AND family(a.ip) = $f " .
	     "ORDER BY a.ip;",\@ghosts);
    if (@ghosts > 0) {
      foreach my $g (@groups) {
	my ($gid,$gname) = @$g;
	my (@cnt,@macros,$grp,$rows);

	# QUIRK: the member count is not limited to the server/expiration
	db_query("SELECT COUNT(h.id) FROM hosts h, a_entries a " .
		 "WHERE a.host=h.id AND grp = $gid AND family(a.ip) = $f " .
		 "AND $idcol IS NOT NULL",\@cnt);
	next unless ($cnt[0][0]);

	$grp = dhcp_model_add($model,'groups',{ name => $gname, id => $gid,
						macros => \@macros, hosts => [] });
	$rows = _entries($et->{group},$gid);
	foreach my $r (@$rows) {
	  if ($r->[2] && $r->[2] == DHCP_FMT_KEA) {
	    _row_stmt($model,$grp->{scope},$r);
	    next;
	  }
	  (my $t = (defined $r->[0] ? $r->[0] : '')) =~ s/\\"/"/g;
	  my $line = $t;
	  $line .= ';' unless ($line =~ /[;\{\}]\s*$/);
	  # entries with %{macro} are applied per host
	  if ($line =~ /\%\{\w+\}/) {
	    push @macros, [ $line, $r->[2] ];
	    next;
	  }
	  _row_stmt($model,$grp->{scope},[ $t, $r->[1], $r->[2] ]);
	}

	for my $j (0..$#nets) {
	  foreach my $h (@ghosts) {
	    next unless ($h->[0] == $gid);
	    my $host = _host_node($model,$o,$h,$nets[$j],$j,\%idhash,\%seen,1)
	      or next;
	    $host->{group} = $gname;
	    push @{$grp->{hosts}}, $host;
	    _host_entries_grouped($model,$o,$host,$hentries{$h->[5]},\@macros);
	  }
	}
      }
    } else {
      print "no hosts found for any groups!\n";
    }
  }

  # hosts not in any group
  undef @ghosts;
  db_query("SELECT h.grp,h.$idcol,a.ip,h.domain,z.name,h.id,h.expiration " .
	   "FROM hosts h, zones z, a_entries a " .
	   "WHERE h.zone=z.id AND a.host=h.id AND ( h.type=1 OR h.type=9 ) " .
	   $_EXPIRED_ZONE . "AND h.$idcol NOTNULL AND z.server=$sid " .
	   "AND h.grp<0 AND family(a.ip) = $f " .
	   "ORDER BY a.ip;",\@ghosts);
  $model->{ungrouped} = (@ghosts > 0 ? 1 : 0);
  $model->{ungrouped_hosts} = [];
  for my $j (0..$#nets) {
    foreach my $h (@ghosts) {
      my $host = _host_node($model,$o,$h,$nets[$j],$j,\%idhash,\%seen,0)
	or next;
      push @{$model->{ungrouped_hosts}}, $host;
      _host_entries_ungrouped($model,$o,$host,$hentries{$h->[5]});
    }
  }
  delete $model->{_ipobj};
}

# create host node for host row $h within net $net, undef when the host
# has no address in the net, is expired or its interface was already used
sub _host_node($$$$$$$$) {
  my ($model,$o,$h,$net,$netidx,$idhash,$seen,$report) = @_;
  my $v6 = ($model->{family} == 6);
  my ($ips,$ip,$fqdn,$id);

  return undef if ($h->[6] && $h->[6] > 0 && $h->[6] < $o->{now});

  $ips = $idhash->{$h->[1]} || [];
  my @in = grep { _contains($v6,$net,$model->{_ipobj}{$_}) } @$ips;
  return undef unless (@in);
  $ip = join(', ',@in);

  $fqdn = $h->[3];
  $fqdn .= ".$h->[4]" unless ($fqdn =~ /\.$/);
  $fqdn =~ s/\.$//;
  $id = $h->[1];

  if ($seen->{$id}) {
    error("duplicate interface $ip for " . ($v6 ? $id : dhcpether($id)) .
	  " ($fqdn)") if ($report);
    return undef;
  }
  $seen->{$id}++;

  my $node = { name => $fqdn, net => $netidx, hostid => $h->[5],
	       addresses => [ @in ], address_text => $ip };
  if ($v6) { $node->{duid} = $id; $node->{duid_text} = dhcpduid($id); }
  else     { $node->{hw_address} = dhcpether($id); }
  return dhcp_model_add($model,'hosts',$node);
}

# option (and regexp matching it) used for automatic domain names
sub _auto_domain_option($$) {
  my ($o,$v6) = @_;

  return ('option domain-name',qr/option\s+domain-name\s+/) unless ($v6);
  return ('option dhcp6.domain-search',qr/option\s+dhcp6\.domain-search\s+/);
}

sub _expand_macros($$) {
  my ($str,$var) = @_;

  foreach my $k (qw(domain ether fqdn host)) {
    $str =~ s/\%\{$k\}/(defined $var->{$k} ? $var->{$k} : '')/ge;
  }
  return $str;
}

sub _add_host_stmt($$$$$;$) {
  my ($model,$host,$line,$comment,$macro,$fmt) = @_;

  my $st = _row_stmt($model,$host->{scope},[ $line, $comment, $fmt ]);
  $st->{macro} = 1 if ($macro);
  return $st;
}

sub _kea_only($) {
  return ($_[0] && $_[0] == DHCP_FMT_KEA) ? 1 : 0;
}

# host in a group: own entries, group %{macros}, automatic domain name;
# every entry may contain %{macros}
sub _host_entries_grouped($$$$$) {
  my ($model,$o,$host,$entries,$macros) = @_;
  my $v6 = ($model->{family} == 6);
  my (@lst,$adomain,$short,%var);

  @lst = map { [ @$_ ] } @{$entries || []};

  ($adomain = $host->{name}) =~ s/^[^\.]+\.//;
  ($short = $host->{name}) =~ s/\..*//g;

  # group macros are added while the list has no filename/root-path
  # (a host's own filename/root-path, or the first such macro, stops it)
  foreach my $m (@$macros) {
    push @lst, [ $m->[0], undef, $m->[1] ]
      unless (grep { !_kea_only($_->[2]) &&
		     $_->[0] =~ /(filename|option\s+root-path)\s+/ } @lst);
  }

  if ($o->{auto_domainnames}) {
    my ($opt,$re) = _auto_domain_option($o,$v6);
    push @lst, [ "$opt \"$adomain\"", undef ]
      unless ((grep { !_kea_only($_->[2]) && $_->[0] =~ $re } @lst) and $adomain);
  }

  %var = (domain => $adomain, fqdn => $host->{name}, host => $short);
  $var{ether} = $host->{hw_address} unless ($v6);

  foreach my $e (@lst) {
    if (_kea_only($e->[2])) {
      _add_host_stmt($model,$host,$e->[0],$e->[1],0,$e->[2]);
      next;
    }
    my $line = $e->[0];
    $line .= ';' unless ($line =~ /[;\{\}]\s*$/);
    my $macro = ($line =~ /\%\{\w+\}/) ? 1 : 0;
    $line = _expand_macros($line,\%var) if ($macro);
    _add_host_stmt($model,$host,$line,$e->[1],$macro,$e->[2]);
  }
}

# host not in any group: automatic domain name, own entries
sub _host_entries_ungrouped($$$$) {
  my ($model,$o,$host,$entries) = @_;
  my $v6 = ($model->{family} == 6);
  my $adomain;

  if ($o->{auto_domainnames}) {
    my ($opt,$re) = _auto_domain_option($o,$v6);
    ($adomain = $host->{name}) =~ s/^[^\.]+\.//;
    # unless the host has its own domain-name entry
    _add_host_stmt($model,$host,"$opt \"$adomain\";",undef,0)
      if ($adomain && !grep { !_kea_only($_->[2]) && $_->[0] =~ $re }
	  @{$entries || []});
  }
  foreach my $e (@{$entries || []}) {
    _add_host_stmt($model,$host,$e->[0],$e->[1],0,$e->[2]);
  }
}


###########################################################################

# dhcp_db_resolver($serverid,$family) - returns coderef($name) giving an
# address of host $name (FQDN, trailing dot optional): the first address
# of the host in the server's zones, else from DNS (as dhcpd resolves
# names); undef if unknown. Used where KEA needs an address and ISC
# accepted a name.
sub dhcp_db_resolver($$) {
  my ($sid,$family) = @_;
  my $f = ($family == 6 ? 6 : 4);
  my $ip;

  return sub {
    my ($name) = @_;
    return undef unless (defined $name);
    (my $n = lc($name)) =~ s/\.+$//;

    unless ($ip) {
      my @q;
      $ip = {};
      db_query("SELECT h.domain,z.name,a.ip FROM hosts h,zones z,a_entries a " .
	       "WHERE z.server=$sid AND h.zone=z.id AND a.host=h.id " .
	       $_EXPIRED_ZONE . " AND family(a.ip) = $f ORDER BY h.id,a.ip",\@q);
      foreach my $r (@q) {
	my $fqdn = $r->[0];
	$fqdn .= ".$r->[1]" unless ($fqdn =~ /\.$/);
	$fqdn =~ s/\.+$//;
	$ip->{lc($fqdn)} = $r->[2] unless (exists $ip->{lc($fqdn)});
      }
    }
    return $ip->{$n} if (defined $ip->{$n});

    my ($err,@res) = Socket::getaddrinfo($n,undef,
		       { family => ($f == 6 ? Socket::AF_INET6() : Socket::AF_INET()),
			 socktype => Socket::SOCK_STREAM() });
    return undef if ($err || !@res);
    my ($e,$addr) = Socket::getnameinfo($res[0]{addr},Socket::NI_NUMERICHOST());
    return ($e ? undef : ($ip->{$n} = $addr));
  };
}


###########################################################################

# dhcp_ha_from_db(\%opts) - KEA High Availability settings from the
# failover settings of the server pair (master = primary, its slave =
# secondary), undef when failover is off
#   server, masterserver  server records (get_server)
#   family                4 or 6 (DHCPv6 uses the *6 settings)
#   warn                  coderef($msg) for problems
# returns { this, mode, max_response_delay, peers => [ {name,url,role} ] }
sub dhcp_ha_from_db($) {
  my ($o) = @_;
  my $v6 = ($o->{family} && $o->{family} == 6);
  my $sfx = ($v6 ? '6' : '');
  my $server = $o->{server};
  my $warn = $o->{warn} || sub { };
  my ($master,$primary,$secondary,@q);

  $master = ($server->{masterserver} > 0 ? $o->{masterserver} : $server);
  return undef unless ($master && $master->{"dhcp_flags_fo$sfx"});

  # the HA partner of the master is its first slave (by id)
  db_query("SELECT id,name,hostaddr,hostname FROM servers WHERE masterserver=" .
	   int($master->{id}) . " ORDER BY id",\@q);
  unless (@q) {
    $warn->("failover enabled but no secondary server (slave) found, " .
	    "High Availability not generated");
    return undef;
  }
  if ($server->{masterserver} > 0) {
    if ($q[0][0] != $server->{id}) {
      $warn->("server $server->{name} is not the High Availability partner " .
	      "of $master->{name} (that is $q[0][1]), HA not generated");
      return undef;
    }
    ($primary,$secondary) = ($master,$server);
  } else {
    $warn->("several slaves of $server->{name}: High Availability partner is " .
	    "$q[0][1], not " . join(', ',map { $_->[1] } @q[1..$#q])) if (@q > 1);
    $primary = $server;
    $secondary = { name => $q[0][1], hostaddr => $q[0][2], hostname => $q[0][3] };
  }

  my $port = $master->{"kea_ha_port$sfx"} || ($v6 ? 8002 : 8001);
  my $split = $master->{"df_split$sfx"};
  $split = 128 unless (defined $split && $split =~ /^\d+$/);
  my $mode = (($split == 0 || $split >= 255) ? 'hot-standby' : 'load-balancing');
  $warn->("failover split $split: KEA load-balancing always splits clients " .
	  "evenly (use 0 or 255 for hot-standby)")
    if ($mode eq 'load-balancing' && $split != 128);
  # ISC split 0 = the secondary serves all clients: it is the active server
  ($primary,$secondary) = ($secondary,$primary) if ($split == 0);

  my @peers;
  foreach my $p ([$primary,'primary'],
		 [$secondary,($mode eq 'hot-standby' ? 'standby' : 'secondary')]) {
    my ($srv,$role) = @$p;
    my $ip = $srv->{hostaddr};
    $ip =~ s{/\d+$}{} if (defined $ip);
    unless (defined $ip && $ip ne '') {
      $warn->("server $srv->{name} has no IP address, High Availability " .
	      "not generated");
      return undef;
    }
    $ip = "[$ip]" if ($ip =~ /:/);
    push @peers, { name => $srv->{name}, url => "http://$ip:$port/", role => $role };
  }

  my $delay = $master->{"df_max_delay$sfx"};
  return { this => $server->{name}, mode => $mode, peers => \@peers,
	   max_response_delay => ((defined $delay && $delay =~ /^\d+$/ && $delay > 0)
				  ? $delay * 1000 : undef) };
}


###########################################################################

# dhcp_d2_from_db($serverid) - dynamic DNS domains for kea-dhcp-ddns: the
# server's master zones served by its BIND (not expired, not catalog only,
# not dummy) that accept updates (allow-update entries), with the TSIG key
# used there: the first key allowed (not negated) in allow-update,
# directly or through an ACL
# returns { domains => [ { name, reverse, key, key_id } ],
#           keys => { id => key } }
#   key = { id, name, algorithm (number), keysize, secretkey (encrypted) }
sub dhcp_d2_from_db($) {
  my ($sid) = @_;
  my (@z,@e,@a,@k,%upd,%acl,%keys,@domains);

  $sid = int($sid);
  db_query("SELECT z.id,z.name,z.reverse FROM zones z WHERE z.server=$sid " .
	   "AND z.type='M' AND coalesce(z.catalog_only,false)=false " .
	   "AND coalesce(z.dummy,false)=false AND (coalesce(z.expiration, 0) <= 0 OR " .
	   "coalesce(z.expiration, 0) > extract(epoch from now())) " .
	   "ORDER BY z.reverse,z.name",\@z);
  # allow-update entries of the server's zones and all ACL entries
  db_query("SELECT c.ref,c.mode,c.acl,c.tkey,coalesce(c.op,0) FROM cidr_entries c " .
	   "JOIN zones z ON c.ref=z.id WHERE c.type=2 AND z.server=$sid " .
	   "ORDER BY c.ref,c.id",\@e);
  push @{$upd{$_->[0]}}, $_ foreach (@e);
  db_query("SELECT c.ref,c.mode,c.acl,c.tkey,coalesce(c.op,0) FROM cidr_entries c " .
	   "WHERE c.type=0 ORDER BY c.ref,c.id",\@a);
  push @{$acl{$_->[0]}}, $_ foreach (@a);
  db_query("SELECT id,name,algorithm,keysize,secretkey FROM keys",\@k);
  my %allkeys = map { ($_->[0] => { id => $_->[0], name => $_->[1], algorithm => $_->[2],
				   keysize => $_->[3], secretkey => $_->[4] }) } @k;

  # first allowed key of a list of entries (ACLs followed, no loops)
  my $find;
  $find = sub {
    my ($list,$seen) = @_;
    foreach my $c (@$list) {
      my (undef,$mode,$aclid,$tkey,$op) = @$c;
      next if ($op);			# negated entry
      return $tkey if ($mode == 2 && $tkey && $allkeys{$tkey});
      if ($mode == 1 && $aclid && $aclid > 0 && !$seen->{$aclid}++) {
	my $t = $find->($acl{$aclid} || [],$seen);
	return $t if ($t);
      }
    }
    return undef;
  };

  foreach my $r (@z) {
    next unless ($upd{$r->[0]});
    my $kid = $find->($upd{$r->[0]},{});
    $keys{$kid} = $allkeys{$kid} if ($kid);
    (my $name = $r->[1]) =~ s/\.*$/./;
    push @domains, { name => $name,
		     reverse => (($r->[2] && $r->[2] ne 'f') || $name =~ /\.(in-addr|ip6)\.arpa\.$/i) ? 1 : 0,
		     key => ($kid ? $allkeys{$kid}{name} : undef), key_id => $kid };
  }
  undef $find;
  return { domains => \@domains, keys => \%keys };
}


###########################################################################
# import: store a model (e.g. read from a KEA configuration) in the DB

# insert scope statements as dhcp_entries rows of type $type
# KEA option-data attributes that have no ISC form (e.g. always-send)
sub _kea_option_extra($) {
  my ($st) = @_;
  my %plain = map { $_ => 1 } qw(name code data space csv-format);

  return 0 unless ($st->{kind} eq 'option' && $st->{kea});
  return (grep { !$plain{$_} } keys %{$st->{kea}}) ? 1 : 0;
}

# database rows ([text, fmt], ...) for a statement
sub _stmt_rows($$) {
  my ($model,$st) = @_;
  my $text;

  if ($st->{fmt} && $st->{fmt} == DHCP_FMT_KEA) {
    $text = kea_statement_to_json($st);
    return defined $text ? ([ $text, DHCP_FMT_KEA ]) : ();
  }
  $text = format_isc_statement($st);
  return () unless (defined $text);
  if (!$st->{fmt} && _kea_option_extra($st)) {
    # keep the KEA option as it is, the ISC form for ISC only
    my %k = (%$st, fmt => DHCP_FMT_KEA);
    return ([ $text, DHCP_FMT_ISC ], [ kea_statement_to_json(\%k), DHCP_FMT_KEA ]);
  }
  return ([ $text, ($st->{fmt} || DHCP_FMT_BOTH) ]);
}

# number of dhcp_entries rows of type $type for $ref
sub _count_entries($$) {
  my ($type,$ref) = @_;
  my @q;

  db_query("SELECT count(*) FROM dhcp_entries WHERE type=$type AND ref=$ref",\@q);
  return $q[0][0];
}

# insert scope statements as dhcp_entries rows of type $type; with
# $dedupe rows already present (same text and fmt) are skipped
sub _insert_entries($$$$;$) {
  my ($model,$type,$ref,$scope,$dedupe) = @_;
  my (%have,@q);

  if ($dedupe) {
    db_query("SELECT dhcp,fmt FROM dhcp_entries WHERE type=$type AND ref=$ref",\@q);
    $have{(defined $_->[0] ? $_->[0] : '') . "\0" . ($_->[1] || 0)} = 1 foreach (@q);
  }

  foreach my $st (@{$scope->{stmts}}) {
    next if ($st->{kind} eq 'range');
    my @rows = _stmt_rows($model,$st);
    unless (@rows) {
      dhcp_model_warn($model,"cannot store statement: " .
		      (defined $st->{name} ? $st->{name} : $st->{kind}));
      next;
    }
    foreach my $r (@rows) {
      my ($text,$fmt) = @$r;
      next if ($have{"$text\0$fmt"}++);
      fatal("cannot add DHCP entry: " . db_errormsg())
	if (db_exec("INSERT INTO dhcp_entries (type,ref,dhcp,comment,fmt) " .
		    "VALUES($type,$ref," . db_encode_str($text) . "," .
		    db_encode_str($st->{comment}) . ",$fmt)") < 0);
    }
  }
}

# entries of an existing object are added only if it has none of the
# address family yet (VLANs and groups are shared by IPv4 and IPv6)
sub _insert_entries_once($$$$$) {
  my ($model,$what,$type,$ref,$scope) = @_;

  return unless (@{$scope->{stmts}});
  if (_count_entries($type,$ref) > 0) {
    dhcp_model_warn($model,"$what exists with DHCP entries, they are not changed");
    return;
  }
  _insert_entries($model,$type,$ref,$scope);
}

# canonical text form of an address (DB inet output form)
sub _normip($) {
  my ($ip) = @_;

  return $ip unless (defined $ip && $ip =~ /:/);
  my $x = ip_expand_address($ip,6);
  return (defined $x ? ip_compress_address($x,6) : lc($ip));
}

# dhcp_model_to_db($model,$serverid,\%opts) - store imported model
#   global    import global statements (server DHCP entries)
#   chaosnet  name of the shared-network treated as the default VLAN
#   verbose   progress messages
# Existing VLANs, nets and classes of the same name are reused; they get
# the imported entries only if they have none of the address family yet.
# Pools always get new groups. Hosts are matched to existing host records
# by address; entries and class memberships they already have are not
# added again. Returns number of updated hosts; fatal() on database errors.
sub dhcp_model_to_db($$$) {
  my ($model,$sid,$o) = @_;
  my $v6 = ($model->{family} == 6);
  my $f = $model->{family};
  my $et = $_ETYPE{$f};
  my (%vlanid,%netid,%classid,@q,%hostbyip,%routerip,%macs,$count);
  my $chaosnet = (defined $o->{chaosnet} ? $o->{chaosnet} : 'CHAOS');
  my $vc = 0;

  _insert_entries($model,$et->{global},$sid,$model->{global}) if ($o->{global});

  # shared-networks
  foreach my $vl (@{$model->{vlans}}) {
    my $name = $vl->{name};
    if ($name eq $chaosnet) {
      $vlanid{$name} = -1;
      print "Treating shared-network $name as default VLAN\n";
      next;
    }
    my $vname = (valid_texthandle($name) ? $name : 'vlan-' . (++$vc));
    my $id = get_vlan_by_name($sid,$vname);
    if ($id > 0) {
      _insert_entries_once($model,"VLAN $vname",$et->{vlan},$id,$vl->{scope});
    } else {
      $id = add_vlan({ server => $sid, name => $vname, description => $name });
      fatal("cannot add VLAN ($name) " . db_errormsg()) if ($id < 0);
      _insert_entries($model,$et->{vlan},$id,$vl->{scope});
    }
    print "shared-network: $name (id=$id)\n" if ($o->{verbose});
    $vlanid{$name} = $id;
  }

  # subnets
  my $nc = 0;
  foreach my $net (@{$model->{nets}}) {
    my $vlan = (defined $net->{vlan} ? $vlanid{$net->{vlan}} : -1);
    my $id = get_net_by_cidr($sid,$net->{cidr});
    if ($id > 0) {
      _insert_entries_once($model,"net $net->{cidr}",$et->{net},$id,$net->{scope});
    } else {
      my $name = ($v6 ? 'net6-' : 'net-') . (++$nc);
      $id = add_net({ server => $sid, netname => $name, name => $name,
		      net => $net->{cidr}, subnet => 'true', vlan => $vlan });
      fatal("cannot add NET ($net->{cidr}) " . db_errormsg()) if ($id < 0);
      _insert_entries($model,$et->{net},$id,$net->{scope});
    }
    print "net: $net->{cidr} (id=$id, vlan=$vlan)\n" if ($o->{verbose});
    $netid{$net->{cidr}} = $id;
    $routerip{_normip($net->{router})} = 1 if (defined $net->{router});
  }

  # classes and pools are groups; existing classes are reused, pools
  # always get a new group with an unused name
  foreach my $grp ((map { [ $_, $_->{type} ] } @{$model->{classes}}),
		   (map { [ $_, 2 ] } @{$model->{pools}})) {
    my ($node,$type) = @$grp;
    if ($type == 2) {
      my ($base,$n) = ($node->{name} =~ /^(.*-)(\d+)$/ ? ($1,$2) : ("$node->{name}-",0));
      $node->{name} = $base . (++$n) while (get_group_by_name($sid,$node->{name}) > 0);
    }
    my $id = get_group_by_name($sid,$node->{name});
    if ($id > 0) {
      _insert_entries_once($model,"group $node->{name}",$et->{group},$id,$node->{scope});
    } else {
      $id = add_group({ server => $sid, name => $node->{name}, type => $type });
      fatal("cannot add group ($node->{name}) " . db_errormsg()) if ($id < 0);
      _insert_entries($model,$et->{group},$id,$node->{scope});
    }
    print "group: $node->{name} (type=$type, id=$id)\n" if ($o->{verbose});
    $node->{db_id} = $id;
    $classid{$node->{name}} = $id if ($type != 2);
  }

  # existing hosts by address (the first one when shared)
  db_query("SELECT h.id,h.domain,a.ip FROM hosts h,zones z,a_entries a " .
	   "WHERE z.server=$sid AND h.zone=z.id AND h.type=1 " .
	   " AND a.host=h.id AND family(a.ip) = $f ORDER BY a.ip,h.id",\@q);
  foreach my $r (@q) {
    $hostbyip{_normip($r->[2])} = $r unless ($hostbyip{_normip($r->[2])});
  }
  unless ($v6) {
    undef @q;
    db_query("SELECT h.ether,h.id FROM hosts h,zones z " .
	     "WHERE z.server=$sid AND h.zone=z.id AND h.type=1 " .
	     " AND h.ether NOTNULL AND h.ether != ''",\@q);
    $macs{$_->[0]} = $_->[1] foreach (@q);
  }

  $count = 0;
  foreach my $h (@{$model->{hosts}}) {
    my ($dbh) = grep { defined $_ } map { $hostbyip{_normip($_)} } @{$h->{addresses}};
    unless ($dbh) {
      dhcp_model_warn($model,"host $h->{name} (" . join(', ',@{$h->{addresses}}) .
		      ") not found, skipped");
      next;
    }
    my %rec = (id => $dbh->[0]);
    if ($v6 && $h->{duid}) {
      $rec{duid} = uc($h->{duid});
    }
    elsif (!$v6 && $h->{hw_address}) {
      (my $ether = uc($h->{hw_address})) =~ s/://g;
      if ($macs{$ether} && $macs{$ether} != $dbh->[0]) {
	$rec{ether_alias} = $macs{$ether};
      } else {
	$rec{ether} = $ether;
	$macs{$ether} = $dbh->[0];
      }
    }
    foreach my $c (@{$h->{classes} || []}) {
      next if (exists $classid{$c});
      my $gid = get_group_by_name($sid,$c);
      $classid{$c} = ($gid > 0 ? $gid : 0);
    }
    my (@have,%have);
    db_query("SELECT grp FROM group_entries WHERE host=$dbh->[0]",\@have);
    $have{$_->[0]} = 1 foreach (@have);
    my @sub = grep { $_ && !$have{$_}++ } map { $classid{$_} } @{$h->{classes} || []};
    if (@sub) {
      $rec{subgroups} = [ ['SubGroup'], map { [ undef, $_, 2 ] } @sub ];
    }
    dhcp_model_warn($model,"host $h->{name}: unknown client class " . join(', ',
		    grep { !$classid{$_} } @{$h->{classes} || []}))
      if (grep { !$classid{$_} } @{$h->{classes} || []});

    print "host: $dbh->[1] ($dbh->[2]) <-- $h->{name}\n" if ($o->{verbose});
    fatal("cannot update host $dbh->[1] " . db_errormsg())
      if (keys(%rec) > 1 && update_host(\%rec) < 0);
    _insert_entries($model,$et->{host},$dbh->[0],$h->{scope},1);
    $count++;
  }

  # dynamic pool members
  foreach my $p (@{$model->{pools}}) {
    my @m;
    my ($s,$e) = (db_encode_str($p->{start}),db_encode_str($p->{end}));
    if ($p->{start} =~ m{/}) {
      db_query("SELECT h.id FROM hosts h,zones z,a_entries a " .
	       "WHERE z.server=$sid AND h.zone=z.id AND h.type=1 AND a.host=h.id " .
	       " AND a.ip << inet $s",\@m);
    } else {
      db_query("SELECT h.id FROM hosts h,zones z,a_entries a " .
	       "WHERE z.server=$sid AND h.zone=z.id AND h.type=1 AND a.host=h.id " .
	       " AND a.ip >= inet $s AND a.ip <= inet $e",\@m);
    }
    fatal("cannot find pool members: " . db_errormsg()) if (db_errormsg());
    print "pool $p->{name}: " . scalar(@m) . " host(s)\n" if ($o->{verbose});
    foreach my $m (@m) {
      fatal("cannot update pool member " . db_errormsg())
	if (update_host({ id => $m->[0], grp => $p->{db_id} }) < 0);
    }
  }

  # router interfaces
  foreach my $ip (keys %routerip) {
    my $r = $hostbyip{$ip};
    unless ($r) {
      dhcp_model_warn($model,"router $ip not found");
      next;
    }
    print "router interface: $ip $r->[1]\n" if ($o->{verbose});
    fatal("cannot update router info for: $r->[1] ($ip)")
      if (update_host({ id => $r->[0], router => 1 }) < 0);
  }

  return $count;
}

1;
# eof
