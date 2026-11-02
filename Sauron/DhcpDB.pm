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
# The behaviour reproduces the original generator in 'sauron', including
# its known quirks, which are marked 'QUIRK' below.
#
package Sauron::DhcpDB;
require Exporter;
use NetAddr::IP;
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
@EXPORT = qw(dhcp_model_from_db);

# dhcp_entries.type per address family
my %_ETYPE = (
  4 => { global => 1,  host => 3,  net => 4, group => 5,  vlan => 6,  local => 7 },
  6 => { global => 11, host => 13, net => 4, group => 15, vlan => 16, local => 17 },
);
# QUIRK: DHCPv6 subnets use the IPv4 subnet entries (type 4), type 14 is
# never read

my $_EXPIRED_ZONE = " AND (coalesce(z.expiration, 0) <= 0 OR " .
  "coalesce(z.expiration, 0) > extract(epoch from now())) ";

# add dhcp_entries rows (text, comment) to scope
sub _add_entries($$$;$) {
  my ($model,$scope,$rows,$fixup) = @_;

  foreach my $r (@$rows) {
    my ($text,$comment) = @$r;
    $text = '' unless (defined $text);
    $text = $fixup->($text) if ($fixup);
    my $st = dhcp_scope_add_isc($model,$scope,$text);
    $st->{orig} = $text;
    $st->{comment} = $comment;
  }
}

sub _entries($$) {
  my ($type,$ref) = @_;
  my @q;

  db_query("SELECT dhcp, comment FROM dhcp_entries " .
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

  # QUIRK: historical site specific hack, no DHCPv4 classes for 'ns2'
  return if (!$v6 && $o->{server}{name} eq 'ns2');

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
    # QUIRK: classes without member hosts are not generated (incl. 103)
    next unless (@qq);

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
			    { name => $name, type => $type, members => \@members });
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

  # QUIRK: historical site specific hack, no DHCPv4 pools for 'ns2'
  my $no_pools = (!$v6 && $o->{server}{name} eq 'ns2');

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

  # shared-networks (VLANs); QUIRK: VLAN ids are sorted as strings
  $vlanhash{$_->[3]}++ foreach (@subnets);
  get_vlan_list($sid,\%vlan_names,\@vlan_lst);
  foreach my $vlan (sort keys %vlanhash) {
    my $name = $vlan_names{$vlan};
    $name =~ s/\s//g;
    $name = 'CHAOS' if ($vlan < 1 || $name eq '');
    my $vl = dhcp_model_add($model,'vlans',{ name => $name, id => $vlan, nets => [] });
    my $rows = _entries($et->{vlan},$vlan);
    # QUIRK: comments of DHCPv6 shared-network entries are not generated
    if ($v6) { $_->[1] = undef foreach (@$rows); }
    _add_entries($model,$vl->{scope},$rows);

    error("No router interfaces found for net $nets[-1][0]!")
      if (!$v6 && @routers < 1);
    foreach my $s (grep { $_->[3] eq $vlan } @subnets) {
      my $net = _load_subnet($model,$o,$s,\@routers,($no_pools ? [] : \@dpools),\@dips);
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
  $ssnet = ($v6 ? new Net::IP($s->[0]) : new NetAddr::IP($s->[0]));
  $pri = 999999;
  $router = '';
  foreach my $r (@$routers) {
    my $in = ($v6 ? ($ssnet->overlaps(new Net::IP($r->[0])) == $IP_B_IN_A_OVERLAP)
		  : $ssnet->contains(new NetAddr::IP($r->[0])));
    if ($in && $pri > $r->[1]) {
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
  # QUIRK: the DHCPv6 router is found but not generated
  $net->{router_hidden} = 1 if ($v6);

  _add_entries($model,$net->{scope},_entries($_ETYPE{$model->{family}}{net},$s->[1]));

  # dynamic pools: contiguous address runs of pool member hosts
  foreach my $p (@$dpools) {
    my ($state,$b,$last) = (0,'','');
    my $emit = sub {
      my ($start,$end) = @_;
      my $pool = dhcp_model_add($model,'pools',{ name => $p->[1], net => $s->[0],
						 start => $start, end => $end });
      my $rs = parse_isc_statement(($v6 ? 'range6 ' : 'range ') .
				   ($start eq $end ? $start : "$start $end"),
				   $model->{family});
      push @{$pool->{ranges}}, $rs;
      _add_entries($model,$pool->{scope},$p->[2]);
      push @{$net->{pools}}, $pool;
      print STDERR "dynamic range $start - $end ($p->[1])\n" if ($o->{verbose});
    };

    foreach my $d (@$dips) {
      my $in = ($d->[0] == $p->[0]) &&
	($v6 ? ($ssnet->overlaps(new Net::IP($d->[1])) == $IP_B_IN_A_OVERLAP)
	     : $ssnet->contains(new NetAddr::IP($d->[1])));
      if ($in) {
	if ($state == 0) {
	  $state = 1;
	  $b = $d->[1];
	}
	elsif ($last ne '' && _gap($v6,$last,$d->[1])) {
	  $emit->($b,$last);
	  $b = $d->[1];
	}
	$last = $d->[1];
      } else {
	$emit->($b,$last) if ($state == 1);
	$state = 0;
      }
    }
    $emit->($b,$last) if ($state == 1);
  }

  return $net;
}

# true if there is at least one address between $a and $b
sub _gap($$$) {
  my ($v6,$a,$b) = @_;

  return ((new Net::IP($b))->intip() > (new Net::IP($a))->intip() + 1) if ($v6);
  return ((new NetAddr::IP($b)) - (new NetAddr::IP($a)) > 1);
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
  my (@q,%idhash,%hentries,%seen,@groups,@ghosts,@nets);

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

  # host entries
  undef @q;
  db_query("SELECT h.id,d.dhcp,d.comment FROM hosts h,zones z,dhcp_entries d " .
	   "WHERE z.server=$sid AND h.zone=z.id AND d.type=$et->{host} " .
	   $_EXPIRED_ZONE . " AND d.ref=h.id ORDER BY h.id,d.id",\@q);
  push @{$hentries{$_->[0]}}, [ $_->[1], $_->[2] ] foreach (@q);

  @nets = map { $v6 ? new Net::IP($_->{cidr}) : new NetAddr::IP($_->{cidr}) }
    @{$model->{netblocks}};

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
						macros => \@macros });
	$rows = _entries($et->{group},$gid);
	foreach my $r (@$rows) {
	  (my $t = (defined $r->[0] ? $r->[0] : '')) =~ s/\\"/"/g;
	  my $line = $t;
	  $line .= ';' unless ($line =~ /[;\{\}]\s*$/);
	  # entries with %{macro} are applied per host
	  if ($line =~ /\%\{\w+\}/) {
	    push @macros, $line;
	    next;
	  }
	  _add_entries($model,$grp->{scope},[[ $t, $r->[1] ]]);
	}

	for my $j (0..$#nets) {
	  foreach my $h (@ghosts) {
	    next unless ($h->[0] == $gid);
	    my $host = _host_node($model,$o,$h,$nets[$j],$j,\%idhash,\%seen,1)
	      or next;
	    $host->{group} = $gname;
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
  for my $j (0..$#nets) {
    foreach my $h (@ghosts) {
      my $host = _host_node($model,$o,$h,$nets[$j],$j,\%idhash,\%seen,0)
	or next;
      _host_entries_ungrouped($model,$o,$host,$hentries{$h->[5]});
    }
  }
}

# create host node for host row $h within net $net, undef when the host
# has no address in the net, is expired or its interface was already used
sub _host_node($$$$$$$$) {
  my ($model,$o,$h,$net,$netidx,$idhash,$seen,$report) = @_;
  my $v6 = ($model->{family} == 6);
  my ($ips,$ip,$fqdn,$id);

  return undef if ($h->[6] && $h->[6] > 0 && $h->[6] < $o->{now});

  $ips = $idhash->{$h->[1]} || [];
  @$ips = sort(@$ips) if (@$ips > 1);
  my @in = grep {
    $v6 ? ($net->overlaps(new Net::IP($_)) == $IP_B_IN_A_OVERLAP)
	: $net->contains(new NetAddr::IP($_))
  } @$ips;
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

sub _expand_macros($$) {
  my ($str,$var) = @_;

  foreach my $k (qw(domain ether fqdn host)) {
    $str =~ s/\%\{$k\}/(defined $var->{$k} ? $var->{$k} : '')/ge;
  }
  return $str;
}

sub _add_host_stmt($$$$$) {
  my ($model,$host,$line,$comment,$macro) = @_;

  my $st = dhcp_scope_add_isc($model,$host->{scope},$line);
  $st->{orig} = $line;
  $st->{comment} = $comment;
  $st->{macro} = 1 if ($macro);
  return $st;
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

  # group macros, unless the host has its own filename/root-path
  # QUIRK: then none of the group macros is used
  unless (grep { $_->[0] =~ /(filename|option\s+root-path)\s+/ } @lst) {
    push @lst, [ $_, undef ] foreach (@$macros);
  }

  if ($o->{auto_domainnames}) {
    # QUIRK: DHCPv6 puts the domain into dhcp6.name-servers
    my $opt = ($v6 ? 'option dhcp6.name-servers' : 'option domain-name');
    my $re = ($v6 ? qr/option\s+dhcp6\.name-servers\s+/ : qr/option\s+domain-name\s+/);
    push @lst, [ "$opt \"$adomain\"", undef ]
      unless ((grep { $_->[0] =~ $re } @lst) and $adomain);
  }

  %var = (domain => $adomain, fqdn => $host->{name}, host => $short);
  $var{ether} = $host->{hw_address} unless ($v6);

  foreach my $e (@lst) {
    my $line = $e->[0];
    $line .= ';' unless ($line =~ /[;\{\}]\s*$/);
    my $macro = ($line =~ /\%\{\w+\}/) ? 1 : 0;
    $line = _expand_macros($line,\%var) if ($macro);
    _add_host_stmt($model,$host,$line,$e->[1],$macro);
  }
}

# host not in any group: automatic domain name, own entries
sub _host_entries_ungrouped($$$$) {
  my ($model,$o,$host,$entries) = @_;
  my $v6 = ($model->{family} == 6);
  my $adomain;

  if ($o->{auto_domainnames}) {
    ($adomain = $host->{name}) =~ s/^[^\.]+\.//;
    # QUIRK: added even if the host has its own domain-name entry
    _add_host_stmt($model,$host,
		   ($v6 ? 'option dhcp6.name-servers' : 'option domain-name') .
		   " \"$adomain\";",undef,0) if ($adomain);
  }
  foreach my $e (@{$entries || []}) {
    _add_host_stmt($model,$host,$e->[0],$e->[1],0);
  }
}

1;
# eof
