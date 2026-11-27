# Sauron::DhcpKea.pm - read KEA DHCP (kea-dhcp4/kea-dhcp6) JSON
#                      configuration into the DHCP model, and write the
#                      model as KEA configuration
#
# Everything that has an ISC dhcpd equivalent is converted to ISC syntax
# statements (Sauron::DhcpDefs); the rest is kept as KEA only statements
# (fmt = DHCP_FMT_KEA) so that the import is lossless for KEA export.
#
# Model nodes created (see Sauron::DhcpModel):
#   global scope   global option-def, option-data and parameters
#   vlans          shared-networks { name, nets => [net] }
#   nets           subnets { cidr, vlan, router, scope }
#   pools          { name, net, ranges => [range stmt], scope }
#   classes        client-classes { name, type (3 = membership by
#                  reservation, 103 = test expression), scope }
#   hosts          reservations { name, net, hw_address | duid,
#                  addresses => [], classes => [], scope }
#
package Sauron::DhcpKea;
require Exporter;
use IO::File;
use JSON::PP;
use Net::IP qw(ip_is_ipv4 ip_is_ipv6);
use Sauron::DhcpDefs;
use Sauron::DhcpModel;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_kea_read_file dhcp_model_from_kea is_kea_conf
	     dhcp_model_to_kea dhcp_kea_write dhcp_kea_d2_config);

# keys handled structurally (not stored as scope parameters)
my @_GLOBAL_KEYS = qw(subnet4 subnet6 shared-networks reservations
		      client-classes);
my @_SHARED_KEYS = qw(name subnet4 subnet6);
my @_SUBNET_KEYS = qw(subnet pools reservations);
my @_POOL_KEYS   = qw(pool client-class client-classes);
my @_HOST_KEYS   = qw(hostname hw-address duid client-id circuit-id flex-id
		      ip-address ip-addresses client-classes);
my @_CLASS_KEYS  = qw(name test);

# is_kea_conf($filename) - true if the file looks like KEA JSON (first
# non-comment character is '{')
sub is_kea_conf($) {
  my ($filename) = @_;
  my $fh = IO::File->new();

  return 0 unless (-r $filename && open($fh,$filename));
  while (<$fh>) {
    s/^\s+|\s+$//g;
    next if ($_ eq '' || /^#/ || m{^//} || m{^/\*} || /^\*/);
    close($fh);
    return (/^\{/) ? 1 : 0;
  }
  close($fh);
  return 0;
}

sub _read_with_includes($$$);

# remove #, // and /* */ comments outside of strings
sub _strip_comments($) {
  my ($text) = @_;
  my $out = '';

  while ($text =~ m{\G( "(?:[^"\\]|\\.)*" | //[^\n]* | \#[^\n]* | /\*.*?\*/ |
			 [^"/\#]+ | / )}gsx) {
    my $t = $1;
    next if ($t =~ m{^(//|\#)});
    if ($t =~ m{^/\*}) { $out .= ' '; next; }
    $out .= $t;
  }
  return $out;
}

# dhcp_kea_read_file($filename,$dir) - read KEA configuration, expand
# <?include "file"?> directives (relative names are looked up in $dir,
# default the directory of the including file); returns decoded root hash
# or dies with an error message
sub dhcp_kea_read_file($;$) {
  my ($filename,$dir) = @_;
  my ($text,$root);

  $text = _read_with_includes($filename,$dir,0);
  $root = eval { JSON::PP->new->relaxed(1)->decode(_strip_comments($text)) };
  die("cannot parse KEA configuration $filename: $@") if ($@);
  die("invalid KEA configuration root in $filename\n")
    unless ($root && ref($root) eq 'HASH');
  return $root;
}

sub _read_with_includes($$$) {
  my ($filename,$dir,$depth) = @_;
  my ($fh,$text,$base);

  die("KEA include nesting too deep ($filename)\n") if ($depth > 10);
  open($fh,'<',$filename) || die("cannot read KEA configuration: $filename\n");
  { local $/; $text = <$fh>; }
  close($fh);

  ($base = $filename) =~ s{[^/]*$}{};
  $base = './' if ($base eq '');
  $text =~ s{<\?include\s+"([^"]+)"\s*\?>}{
    my $f = $1;
    $f = ($dir ? "$dir/" : $base) . $f unless ($f =~ m{^/});
    _read_with_includes($f,$dir,$depth+1);
  }ge;
  return $text;
}

# dhcp_model_from_kea($root,$family) - build model from decoded KEA
# configuration (dhcp_kea_read_file)
sub dhcp_model_from_kea($$) {
  my ($root,$family) = @_;
  my $f = ($family && $family == 6 ? 6 : 4);
  my $section = ($f == 6 ? 'Dhcp6' : 'Dhcp4');
  my $cfg = $root->{$section};
  my $model = dhcp_model_new($f);
  my $skey = ($f == 6 ? 'subnet6' : 'subnet4');

  die("KEA configuration does not include $section section\n")
    unless ($cfg && ref($cfg) eq 'HASH');
  $model->{counter} = { pool => 0, host => 0, vlan => 0 };

  # global option-def first, used for typing of option-data
  _scope($model,$model->{global},$cfg,\@_GLOBAL_KEYS);

  foreach my $sn (_list($cfg->{'shared-networks'})) {
    my $name = $sn->{name};
    $name = 'shared-network-' . (++$model->{counter}{vlan})
      unless (defined $name && $name ne '');
    my $vl = dhcp_model_add($model,'vlans',{ name => $name, nets => [] });
    _scope($model,$vl->{scope},$sn,\@_SHARED_KEYS);
    foreach my $s (_list($sn->{$skey})) {
      my $net = _subnet($model,$s);
      next unless ($net);
      $net->{vlan} = $name;
      push @{$vl->{nets}}, $net;
    }
  }
  _subnet($model,$_) foreach (_list($cfg->{$skey}));

  # global reservations
  _host($model,$_,undef) foreach (_list($cfg->{reservations}));

  foreach my $c (_list($cfg->{'client-classes'})) {
    next unless (defined $c->{name} && !ref($c->{name}) && $c->{name} ne '');
    my $cl = dhcp_model_add($model,'classes',
			    { name => $c->{name},
			      type => (defined $c->{test} ? 103 : 3) });
    if (defined $c->{test} && !ref($c->{test})) {
      dhcp_scope_add_stmt($model,$cl->{scope},
			  { kind => 'match', kea_test => $c->{test},
			    fmt => DHCP_FMT_KEA, family => $f });
    }
    _scope($model,$cl->{scope},$c,\@_CLASS_KEYS);
  }

  delete $model->{counter};
  return $model;
}

sub _list($) {
  my ($v) = @_;
  return () unless ($v && ref($v) eq 'ARRAY');
  return grep { $_ && ref($_) eq 'HASH' } @$v;
}

# option-def, option-data and parameters of a KEA scope
sub _scope($$$$) {
  my ($model,$scope,$h,$skip) = @_;

  dhcp_scope_add_kea_option_defs($model,$scope,$h->{'option-def'});
  dhcp_scope_add_kea_options($model,$scope,$h->{'option-data'});
  dhcp_scope_add_kea_params($model,$scope,$h,$skip);
}

sub _subnet($$) {
  my ($model,$s) = @_;
  my $v6 = ($model->{family} == 6);
  my ($net,@keep);

  unless (defined $s->{subnet} && $s->{subnet} =~ m{^\S+/\d+$}) {
    dhcp_model_warn($model,"skipping subnet without valid 'subnet': " .
		    (defined $s->{subnet} ? $s->{subnet} : '(none)'));
    return undef;
  }
  $net = dhcp_model_add($model,'nets',{ cidr => $s->{subnet}, pools => [] });
  _scope($model,$net->{scope},$s,\@_SUBNET_KEYS);

  # a single router is kept as the subnet router (router host in Sauron)
  unless ($v6) {
    foreach my $st (@{$net->{scope}{stmts}}) {
      if (!defined $net->{router} && $st->{kind} eq 'option' && $st->{def} &&
	  $st->{def}{isc} eq 'routers' && $st->{fmt} == DHCP_FMT_BOTH &&
	  @{$st->{values}} == 1) {
	$net->{router} = $st->{values}[0];
	next;
      }
      push @keep, $st;
    }
    $net->{scope}{stmts} = \@keep;
  }

  foreach my $p (_list($s->{pools})) {
    _pool($model,$net,$p);
  }
  _host($model,$_,$net) foreach (_list($s->{reservations}));
  return $net;
}

sub _pool($$$) {
  my ($model,$net,$p) = @_;
  my $v6 = ($model->{family} == 6);
  my ($start,$end,$range,$pool,@classes);

  my $ipok = sub { $v6 ? ip_is_ipv6($_[0]) : ip_is_ipv4($_[0]) };
  if (defined $p->{pool} && $p->{pool} =~ /^\s*(\S+)\s*-\s*(\S+)\s*$/ &&
      $ipok->($1) && $ipok->($2)) {
    ($start,$end) = ($1,$2);
    $range = ($v6 ? 'range6' : 'range') . " $start $end";
  }
  elsif ($v6 && defined $p->{pool} && $p->{pool} =~ m{^\s*(\S+)/(\d+)\s*$} &&
	 ip_is_ipv6($1) && $2 <= 128) {
    $range = "range6 $1/$2";
    $start = $end = "$1/$2";
  }
  else {
    dhcp_model_warn($model,"skipping pool with invalid range: " .
		    (defined $p->{pool} ? $p->{pool} : '(none)'));
    return;
  }

  $pool = dhcp_model_add($model,'pools',
			 { name => ($v6 ? 'pool6-' : 'pool-') .
			     (++$model->{counter}{pool}),
			   net => $net->{cidr}, start => $start, end => $end });
  push @{$pool->{ranges}}, parse_isc_statement($range,$model->{family});

  push @classes, $p->{'client-class'}
    if (defined $p->{'client-class'} && !ref($p->{'client-class'}));
  push @classes, grep { defined $_ && !ref($_) } @{$p->{'client-classes'}}
    if (ref($p->{'client-classes'}) eq 'ARRAY');
  foreach my $c (@classes) {
    my $text = ($c eq 'KNOWN' ? 'deny unknown-clients' :
		$c eq 'UNKNOWN' ? 'deny known-clients' :
		"allow members of \"$c\"");
    dhcp_scope_add_isc($model,$pool->{scope},$text);
  }
  _scope($model,$pool->{scope},$p,\@_POOL_KEYS);
  push @{$net->{pools}}, $pool;
}

sub _hex_id($) {
  my ($v) = @_;
  $v = lc($v);
  $v =~ s/[:\s-]//g;
  return ($v =~ /^[0-9a-f]+$/ && length($v) % 2 == 0) ? $v : undef;
}

sub _host($$$) {
  my ($model,$r,$net) = @_;
  my $v6 = ($model->{family} == 6);
  my ($host,@addr,$name);

  push @addr, $r->{'ip-address'} if (defined $r->{'ip-address'} && !ref($r->{'ip-address'}));
  push @addr, grep { defined $_ && !ref($_) } @{$r->{'ip-addresses'}}
    if (ref($r->{'ip-addresses'}) eq 'ARRAY');

  $name = $r->{hostname};
  $name = 'host-' . (++$model->{counter}{host})
    unless (defined $name && !ref($name) && $name ne '');

  $host = dhcp_model_add($model,'hosts',
			 { name => $name, addresses => \@addr,
			   net => ($net ? $net->{cidr} : undef) });

  # interface identifier
  if (!$v6 && defined $r->{'hw-address'}) {
    my $hw = _hex_id($r->{'hw-address'});
    $host->{hw_address} = join(':',($hw =~ /(..)/g)) if ($hw && length($hw) == 12);
  }
  elsif (!$v6 && defined $r->{'client-id'}) {
    # client-id of hardware type 1 (ethernet) is the MAC address
    my $cid = _hex_id($r->{'client-id'});
    $host->{hw_address} = join(':',(substr($cid,2) =~ /(..)/g))
      if ($cid && length($cid) == 14 && substr($cid,0,2) eq '01');
  }
  elsif ($v6 && defined $r->{duid}) {
    # Sauron stores DUIDs of 12-20 bytes (hosts.duid, DHCPv6 export)
    my $duid = _hex_id($r->{duid});
    if ($duid && length($duid) >= 24 && length($duid) <= 40) {
      $host->{duid} = $duid;
    } else {
      dhcp_model_warn($model,"reservation $name: unsupported DUID length " .
		      "($r->{duid})");
    }
  }
  unless ($host->{hw_address} || $host->{duid}) {
    dhcp_model_warn($model,"reservation $name: no supported identifier " .
		    "(" . ($v6 ? 'duid' : 'hw-address, client-id 01:<mac>') .
		    "), only its options are imported");
    foreach my $k ('hw-address','duid','client-id','circuit-id','flex-id') {
      next unless (defined $r->{$k});
      dhcp_scope_add_stmt($model,$host->{scope},
			  kea_param_to_statement($k,$r->{$k},$model->{family}));
    }
  }
  dhcp_model_warn($model,"reservation $name: no address") unless (@addr);

  $host->{classes} = [ grep { defined $_ && !ref($_) } @{$r->{'client-classes'}} ]
    if (ref($r->{'client-classes'}) eq 'ARRAY');
  _scope($model,$host->{scope},$r,\@_HOST_KEYS);
}


###########################################################################
# KEA writer
#
# Mapping of the model (as loaded by Sauron::DhcpDB):
#   local + global scopes   global parameters, option-def, option-data
#   classes                 client-classes (test from KEA only entries;
#                           ISC 'match' expressions are not converted)
#   vlans                   shared-networks (VLAN 'CHAOS' = no network)
#   nets                    subnets (id: KEA only 'id' entry or Sauron id)
#   pools                   pools of the subnet
#   hosts                   reservations in the subnet of their address;
#                           group statements are merged into them, class
#                           membership (MAC/DUID classes) -> client-classes
# Failover settings become the KEA High Availability hook ($model->{ha},
# see Sauron::DhcpDB::dhcp_ha_from_db), with the lease_cmds hook it needs.

# reservation parameters KEA accepts in a reservation (DHCPv4)
my %_HOST_PARAMS = map { $_ => 1 } qw(next-server server-hostname
				       boot-file-name);

# parameters KEA accepts in a pool (lifetimes etc. are subnet level)
my %_POOL_PARAMS = map { $_ => 1 } qw(client-class require-client-classes
				       evaluate-additional-classes pool-id
				       user-context comment);

# parameters KEA accepts only at the global level
my %_GLOBAL_ONLY = map { $_ => 1 } qw(
  lease-database hosts-database hosts-databases interfaces-config
  control-socket control-sockets dhcp-ddns loggers hooks-libraries
  expired-leases-processing multi-threading sanity-checks
  dhcp-queue-control config-control server-tag decline-probation-period
  dhcp4o6-port host-reservation-identifiers statistic-default-sample-count
  statistic-default-sample-age ip-reservations-unique
  early-global-reservations-lookup parked-packet-limit compatibility
  server-id reservations-lookup-first);

# option key: space and code (names resolved through the definitions)
sub _optkey($$) {
  my ($model,$o) = @_;
  my $space = (defined $o->{space} ? $o->{space} :
	       ($model->{family} == 6 ? 'dhcp6' : 'dhcp4'));
  my $code = $o->{code};

  unless (defined $code) {
    my $def = (defined $o->{name} ?
	       dhcp_option_def($model->{family},'kea',
			       ($space =~ /^dhcp[46]$/ ? $o->{name} : "$space.$o->{name}"),
			       $model->{option_defs}) : undef);
    $code = ($def ? $def->{code} : "name:" . (defined $o->{name} ? $o->{name} : ''));
  }
  return "$space.$code";
}

# context of one dhcp_model_to_kea run (global option-def collection)
our $_ctx;

# merge scope conversion $k (dhcp_scope_to_kea) into KEA element $e of
# level $level (global, shared-network, subnet, pool, class, host);
# options with the same space/code are replaced (later wins); option-def
# is collected at the global level only
sub _merge($$$$$) {
  my ($model,$e,$k,$level,$what) = @_;

  foreach my $o (@{$k->{'option-def'}}) {
    my $key = (defined $o->{space} ? $o->{space} : '') . ".$o->{code}";
    my $list = $_ctx->{'option-def'};
    my ($i) = grep { ((defined $list->[$_]{space} ? $list->[$_]{space} : '') .
		      ".$list->[$_]{code}") eq $key } 0..$#$list;
    if (defined $i) { $list->[$i] = $o; } else { push @$list, $o; }
  }
  foreach my $o (@{$k->{'option-data'}}) {
    my $key = _optkey($model,$o);
    my $list = ($e->{'option-data'} ||= []);
    my ($i) = grep { _optkey($model,$list->[$_]) eq $key } 0..$#$list;
    if (defined $i) { $list->[$i] = $o; } else { push @$list, $o; }
  }
  foreach my $p (sort keys %{$k->{params}}) {
    if ($level ne 'global' && $_GLOBAL_ONLY{$p}) {
      dhcp_model_warn($model,"$what: global parameter $p ignored");
      next;
    }
    if ($level eq 'pool' && !$_POOL_PARAMS{$p}) {
      dhcp_model_warn($model,"$what: parameter $p is not allowed in a KEA " .
		      "pool, ignored");
      next;
    }
    $e->{$p} = kea_param_merge($p,$e->{$p},$k->{params}{$p});
  }
  if (defined $k->{'client-class'}) {
    if ($level eq 'pool') { $e->{'client-class'} = $k->{'client-class'}; }
  }
  if (defined $k->{test}) {
    if ($level eq 'class') { $e->{test} = $k->{test}; }
    else { dhcp_model_warn($model,"$what: class test expression ignored"); }
  }
}

# dhcp_model_to_kea($model,$resolve) - KEA configuration (hashref with
# Dhcp4 or Dhcp6 root) for the model; problems are added to the model
# warnings
sub dhcp_model_to_kea($;$) {
  my ($model,$resolve) = @_;
  my $v6 = ($model->{family} == 6);
  my $skey = ($v6 ? 'subnet6' : 'subnet4');
  my (%cfg,%memberof,%groups,@subnets,%reserved);

  local $_ctx = { 'option-def' => [] };

  # global entries: local entries first, global entries override
  foreach my $scope ($model->{local},$model->{global}) {
    next unless ($scope);
    _merge($model,\%cfg,dhcp_scope_to_kea($model,$scope,$resolve,'global'),
	   'global','global');
  }

  # client classes
  foreach my $cl (@{$model->{classes}}) {
    my %c = (name => $cl->{name});
    _merge($model,\%c,dhcp_scope_to_kea($model,$cl->{scope},$resolve,'class'),
	   'class',"class $cl->{name}");
    if ($cl->{type} == 103 && !defined $c{test}) {
      dhcp_model_warn($model,"class $cl->{name}: no KEA test expression, " .
		      "only reservations can assign it");
    }
    push @{$cfg{'client-classes'}}, \%c;
    if ($cl->{type} == 3) {
      push @{$memberof{$_->{id}}}, $cl->{name} foreach (@{$cl->{members} || []});
    }
  }

  $groups{$_->{name}} = $_ foreach (@{$model->{groups}});

  # subnets (in VLAN order as in dhcpd.conf)
  my %netused;
  foreach my $vl (@{$model->{vlans}}) {
    my $sn;
    unless (!defined $vl->{id} || $vl->{id} < 1 || $vl->{name} eq 'CHAOS') {
      $sn = { name => $vl->{name} };
      _merge($model,$sn,dhcp_scope_to_kea($model,$vl->{scope},$resolve,
					   'shared-network'),
	     'shared-network',"shared-network $vl->{name}");
      push @{$cfg{'shared-networks'}}, $sn;
    }
    foreach my $net (@{$vl->{nets}}) {
      $netused{$net} = 1;
      my $s = _kea_subnet($model,$net,$resolve);
      push @subnets, [ $net, $s ];
      if ($sn) { push @{$sn->{$skey}}, $s; } else { push @{$cfg{$skey}}, $s; }
    }
  }
  foreach my $net (@{$model->{nets}}) {
    next if ($netused{$net});
    my $s = _kea_subnet($model,$net,$resolve);
    push @subnets, [ $net, $s ];
    push @{$cfg{$skey}}, $s;
  }
  _subnet_ids($model,\@subnets);

  # reservations; subnets are looked up within the host's top level net
  my @nb = map { dhcp_ip_obj($v6,$_->{cidr}) } @{$model->{netblocks} || []};
  my (%bynb,@all);
  foreach my $x (@subnets) {
    my $o = dhcp_ip_obj($v6,$x->[0]{cidr});
    my $e = [ $o, $x->[1] ];
    push @all, $e;
    for my $j (0..$#nb) {
      if (dhcp_ip_in($v6,$nb[$j],$o)) { push @{$bynb{$j}}, $e; last; }
    }
  }
  foreach my $h (@{$model->{hosts}}) {
    my (%by,@order);
    my $cand = ((defined $h->{net} && $h->{net} =~ /^\d+$/ && $bynb{$h->{net}})
		? $bynb{$h->{net}} : \@all);
    foreach my $ip (@{$h->{addresses} || []}) {
      my $a = dhcp_ip_obj($v6,$ip);
      my $x;
      foreach my $c (@$cand) {
	if (dhcp_ip_in($v6,$c->[0],$a)) { $x = $c; last; }
      }
      unless ($x) {
	dhcp_model_warn($model,"host $h->{name}: address $ip is not in any subnet");
	next;
      }
      push @order, $x unless ($by{$x->[1]});
      push @{$by{$x->[1]}}, $ip;
    }
    my $id = ($v6 ? $h->{duid_text} : $h->{hw_address});
    foreach my $x (@order) {
      my $ips = $by{$x->[1]};
      my %r = (hostname => $h->{name});
      if ($v6) {
	$r{duid} = $h->{duid_text};
	$r{'ip-addresses'} = [ @$ips ];
      } else {
	$r{'hw-address'} = $h->{hw_address};
	$r{'ip-address'} = $ips->[0];
	dhcp_model_warn($model,"host $h->{name}: KEA allows one address per " .
			"subnet, using $ips->[0]") if (@$ips > 1);
      }
      my $g = (defined $h->{group} ? $groups{$h->{group}} : undef);
      foreach my $scope (($g ? ($g->{scope}) : ()), $h->{scope}) {
	_merge($model,\%r,dhcp_scope_to_kea($model,$scope,$resolve,'host'),
	       'host',"host $h->{name}");
      }
      foreach my $p (keys %r) {
	next if ($p =~ /^(hostname|duid|hw-address|ip-address|ip-addresses|option-data|client-classes)$/);
	next if ($_HOST_PARAMS{$p} && !$v6);
	next if ($p =~ /^(prefixes|flex-id|circuit-id|client-id)$/);
	dhcp_model_warn($model,"host $h->{name}: parameter $p is not allowed " .
			"in a reservation, ignored");
	delete $r{$p};
      }
      $r{'client-classes'} = [ @{$memberof{$id}} ] if ($id && $memberof{$id});
      push @{$x->[1]{reservations}}, \%r;
      $reserved{$id} = 1 if ($id);
    }
  }

  # class members without a subnet reservation (dynamic clients, as the
  # 'subclass' declarations in dhcpd.conf): global reservations that only
  # assign the classes
  foreach my $mid (sort keys %memberof) {
    next if ($reserved{$mid});
    push @{$cfg{reservations}}, { ($v6 ? 'duid' : 'hw-address') => $mid,
				  'client-classes' => [ @{$memberof{$mid}} ] };
  }
  if ($cfg{reservations}) {
    $cfg{'reservations-global'} = JSON::PP::true();
    $cfg{'reservations-in-subnet'} = JSON::PP::true();
  }

  $cfg{'option-def'} = $_ctx->{'option-def'} if (@{$_ctx->{'option-def'}});
  _kea_ha($model,\%cfg) if ($model->{ha});
  return { ($v6 ? 'Dhcp6' : 'Dhcp4') => \%cfg };
}

# High Availability: hooks lease_cmds + ha (library names are found in
# KEA's hooks directory unless $model->{hooks_dir} is set), the dedicated
# HTTP listener when multi-threading is not disabled
sub _kea_ha($$) {
  my ($model,$cfg) = @_;
  my $ha = $model->{ha};
  my $dir = $model->{hooks_dir};
  my $lib = sub { (defined $dir && $dir ne '') ? "$dir/$_[0]" : $_[0] };
  my %rel = (this => 'this-server-name', mode => 'mode', peers => 'peers');

  my %h = map { ($rel{$_} => $ha->{$_}) } keys %rel;
  if (defined $ha->{max_response_delay}) {
    # heartbeats must come more often than the partner is declared dead
    $h{'max-response-delay'} = $ha->{max_response_delay};
    $h{'heartbeat-delay'} = int($ha->{max_response_delay} / 2)
      if ($ha->{max_response_delay} <= 10000);
  }
  my $mt = $cfg->{'multi-threading'};
  if (ref($mt) eq 'HASH' && defined $mt->{'enable-multi-threading'} &&
      !$mt->{'enable-multi-threading'}) {
    dhcp_model_warn($model,"multi-threading is disabled: High Availability " .
		    "goes through kea-ctrl-agent, the peer URLs must use its port " .
		    "(KEA HA listener port setting)");
  } else {
    $h{'multi-threading'} = { 'enable-multi-threading' => JSON::PP::true(),
			      'http-dedicated-listener' => JSON::PP::true(),
			      'http-listener-threads' => 0,
			      'http-client-threads' => 0 };
  }

  # a copy: the list may be the value of a model statement
  my $hooks = [ ref($cfg->{'hooks-libraries'}) eq 'ARRAY' ? @{$cfg->{'hooks-libraries'}} : () ];
  my %have;
  foreach my $e (grep { ref($_) eq 'HASH' && defined $_->{library} } @$hooks) {
    my ($b) = ($e->{library} =~ m{([^/]+)$});
    next unless (defined $b);
    $b =~ s/\.so(?:\.[\d.]+)?$/.so/;
    $have{$b} = $e;
  }
  push @$hooks, { library => $lib->('libdhcp_lease_cmds.so') }
    unless ($have{'libdhcp_lease_cmds.so'});
  if ($have{'libdhcp_ha.so'}) {
    dhcp_model_warn($model,"hooks-libraries already contain libdhcp_ha.so, " .
		    "High Availability from failover settings not added");
  } else {
    push @$hooks, { library => $lib->('libdhcp_ha.so'),
		    parameters => { 'high-availability' => [ \%h ] } };
  }
  $cfg->{'hooks-libraries'} = $hooks;
}

# stable unique subnet ids: a KEA only 'id' entry, else the Sauron net
# id, else the lowest id used by neither of them
sub _subnet_ids($$) {
  my ($model,$subnets) = @_;
  my (%used,%taken,@rest);

  foreach my $x (@$subnets) {
    my ($net,$s) = @$x;
    if (defined $s->{id} && $s->{id} !~ /^\d+$/) {
      dhcp_model_warn($model,"subnet $net->{cidr}: invalid subnet id $s->{id}");
      delete $s->{id};
    }
    $used{$s->{id}} = 1 if (defined $s->{id});
    $used{$net->{id}} = 1 if (defined $net->{id} && $net->{id} =~ /^\d+$/);
  }
  # explicit KEA ids first, then Sauron net ids
  my %done;
  foreach my $pass (1,2) {
    foreach my $x (@$subnets) {
      my ($net,$s) = @$x;
      next if ($done{$x});
      my $id = ($pass == 1 ? $s->{id} : $net->{id});
      next unless (defined $id && $id =~ /^\d+$/ && !$taken{$id});
      $s->{id} = int($id);
      $taken{$id} = $done{$x} = 1;
    }
  }
  @rest = grep { !$done{$_} } @$subnets;
  my $n = 0;
  foreach my $x (@rest) {
    $n++ while (!$n || $used{$n} || $taken{$n});
    dhcp_model_warn($model,"subnet $x->[0]{cidr}: subnet id " .
		    (defined $x->[1]{id} ? $x->[1]{id} : $x->[0]{id}) .
		    " already used, using $n");
    $x->[1]{id} = $n;
    $taken{$n} = 1;
  }
}

sub _kea_subnet($$$) {
  my ($model,$net,$resolve) = @_;
  my $v6 = ($model->{family} == 6);
  my %s = (subnet => $net->{cidr});

  if (!$v6 && defined $net->{router}) {
    $s{'option-data'} = [ { name => 'routers', code => 3, data => $net->{router} } ];
  }
  _merge($model,\%s,dhcp_scope_to_kea($model,$net->{scope},$resolve,'subnet'),
	 'subnet',"subnet $net->{cidr}");

  foreach my $pool (@{$net->{pools} || []}) {
    my $k = dhcp_scope_to_kea($model,$pool->{scope},$resolve,'pool');
    foreach my $r (@{$pool->{ranges} || []}) {
      my $range = (defined $r->{prefix} ? $r->{prefix} :
		   (defined $r->{start} && defined $r->{end}) ? "$r->{start} - $r->{end}" :
		   undef);
      unless (defined $range) {
	dhcp_model_warn($model,"pool $pool->{name}: invalid range " .
			(defined $r->{text} ? $r->{text} : ''));
	next;
      }
      my %p = (pool => $range);
      _merge($model,\%p,$k,'pool',"pool $pool->{name}");
      push @{$s{pools}}, \%p;
    }
  }
  return \%s;
}

# dhcp_kea_d2_config($d2,\%opts) - kea-dhcp-ddns (D2) configuration
#   $d2   dynamic DNS domains (Sauron::DhcpDB::dhcp_d2_from_db)
#   opts  dns_ip     address of the DNS server receiving the updates
#         dns_port   its port (53)
#         secret     coderef($key) -> base64 secret, undef if unavailable
#         algorithm  coderef($key) -> TSIG algorithm name, undef if unknown
#         warn       coderef($msg)
# returns { DhcpDdns => {...} }; domains whose key cannot be used are left
# out (a DNS server would refuse their updates)
sub dhcp_kea_d2_config($$) {
  my ($d2,$o) = @_;
  my $warn = $o->{warn} || sub { };
  my (%cfg,%usedkeys,@fwd,@rev);

  %cfg = ('ip-address' => '127.0.0.1', port => 53001);
  foreach my $d (@{$d2->{domains}}) {
    my %e = (name => $d->{name},
	     'dns-servers' => [ { 'ip-address' => $o->{dns_ip},
				  port => int($o->{dns_port} || 53) } ]);
    if (defined $d->{key_id}) {
      my $k = $d2->{keys}{$d->{key_id}};
      unless ($usedkeys{$k->{id}}) {
	my $alg = $o->{algorithm}->($k);
	my $sec = $o->{secret}->($k);
	unless ($alg && $sec) {
	  $usedkeys{$k->{id}} = ($alg ? -1 : -2);
	} else {
	  push @{$cfg{'tsig-keys'}}, { name => $k->{name}, algorithm => $alg,
				       secret => $sec };
	  $usedkeys{$k->{id}} = 1;
	}
      }
      if ($usedkeys{$k->{id}} < 0) {
	$warn->("key $k->{name}: " . ($usedkeys{$k->{id}} == -1 ?
				      'secret not available' : 'unsupported algorithm') .
		", dynamic DNS for $d->{name} not generated");
	next;
      }
      $e{'key-name'} = $k->{name};
    }
    push @{$d->{reverse} ? \@rev : \@fwd}, \%e;
  }
  $cfg{'forward-ddns'} = { 'ddns-domains' => \@fwd };
  $cfg{'reverse-ddns'} = { 'ddns-domains' => \@rev };
  return { DhcpDdns => \%cfg };
}

# dhcp_kea_write($fh,$model,\%meta) - write KEA configuration
#   meta: filename, version, user, time, resolve (see dhcp_model_to_kea)
sub dhcp_kea_write($$$) {
  my ($fh,$model,$meta) = @_;
  my $cfg = dhcp_model_to_kea($model,$meta->{resolve});

  print $fh "// $meta->{filename} -- automagically generated by Sauron v$meta->{version}\n",
    "//               created by $meta->{user} at $meta->{time}\n//\n",
    "// server: $model->{server}{name} -- " .
    (defined $model->{server}{comment} ? $model->{server}{comment} : '') . "\n//\n";
  print $fh JSON::PP->new->pretty(1)->canonical(1)->encode($cfg);
  return 0;
}

1;
# eof
