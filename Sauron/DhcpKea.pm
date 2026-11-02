# Sauron::DhcpKea.pm - read KEA DHCP (kea-dhcp4/kea-dhcp6) JSON
#                      configuration into the DHCP model
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
use Sauron::DhcpDefs;
use Sauron::DhcpModel;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_kea_read_file dhcp_model_from_kea is_kea_conf);

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

# remove // and /* */ comments outside of strings (# is handled by
# JSON::PP relaxed mode)
sub _strip_comments($) {
  my ($text) = @_;
  my $out = '';

  while ($text =~ m{\G( "(?:[^"\\]|\\.)*" | //[^\n]* | /\*.*?\*/ | [^"/]+ | / )}gsx) {
    my $t = $1;
    if ($t =~ m{^//}) { next; }
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

  if (defined $p->{pool} && $p->{pool} =~ /^\s*(\S+)\s*-\s*(\S+)\s*$/) {
    ($start,$end) = ($1,$2);
    $range = ($v6 ? 'range6' : 'range') . " $start $end";
  }
  elsif ($v6 && defined $p->{pool} && $p->{pool} =~ m{^\s*(\S+/\d+)\s*$}) {
    $range = "range6 $1";
    $start = $end = $1;
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
    $host->{duid} = _hex_id($r->{duid});
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

1;
# eof
