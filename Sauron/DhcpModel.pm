# Sauron::DhcpModel.pm - neutral in-memory DHCP configuration model
#
# The model sits between configuration readers (ISC dhcpd.conf, KEA JSON,
# Sauron database) and writers (ISC dhcpd.conf, KEA JSON, Sauron database):
#
#   model = {
#     family      => 4 | 6,
#     global      => scope,
#     option_defs => { isc|kea|code => { key => def } }   (user defined)
#     vlans       => [ { name, comment, scope } ],           shared-networks
#     nets        => [ { cidr, name, vlan, scope } ],        subnets
#     pools       => [ { name, net, ranges => [stmt], scope } ],
#     groups      => [ { name, scope } ],
#     classes     => [ { name, scope } ],     test/match is a scope stmt
#     hosts       => [ { name, addresses => [], hw_address, duid,
#                        client_id, group, classes => [], scope } ],
#     warnings    => [ text ],
#   }
#
#   scope = { stmts => [ statement ] }  (see Sauron::DhcpDefs)
#
package Sauron::DhcpModel;
require Exporter;
use Sauron::DhcpDefs;
use NetAddr::IP;
use Net::IP qw(:PROC);
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_model_new dhcp_scope_new dhcp_model_add dhcp_model_find
	     dhcp_model_warn dhcp_scope_add_isc dhcp_scope_add_stmt
	     dhcp_scope_add_kea_options dhcp_scope_add_kea_option_defs
	     dhcp_scope_add_kea_params
	     dhcp_scope_to_isc dhcp_scope_to_kea dhcp_ip_obj dhcp_ip_in);

my %_COLLECTIONS = map { $_ => 1 } qw(vlans nets pools groups classes hosts);

# dhcp_ip_obj($v6,$ip) - address/net object (NetAddr::IP for IPv4,
# Net::IP for IPv6), undef for invalid input
sub dhcp_ip_obj($$) {
  my ($v6,$ip) = @_;
  return ($v6 ? new Net::IP($ip) : new NetAddr::IP($ip));
}

# dhcp_ip_in($v6,$net,$addr) - true if address/net object $addr is within
# net object $net, or equal to it (objects from dhcp_ip_obj)
sub dhcp_ip_in($$$) {
  my ($v6,$net,$addr) = @_;
  return 0 unless ($net && $addr);
  return $net->contains($addr) unless ($v6);
  my $o = $net->overlaps($addr);
  return (defined $o && ($o == $IP_B_IN_A_OVERLAP || $o == $IP_IDENTICAL));
}

# dhcp_model_new($family) - create empty model for address family 4 or 6
sub dhcp_model_new($) {
  my ($family) = @_;

  return { family => ($family && $family == 6 ? 6 : 4),
	   global => dhcp_scope_new(),
	   option_defs => {},
	   (map { $_ => [] } keys %_COLLECTIONS),
	   warnings => [] };
}

# dhcp_scope_new() - create empty scope
sub dhcp_scope_new() {
  return { stmts => [] };
}

# dhcp_model_warn($model,$msg) - record a warning (each message once)
sub dhcp_model_warn($$) {
  my ($model,$msg) = @_;
  return if ($model->{_warned}{$msg}++);
  push @{$model->{warnings}}, $msg;
}

# dhcp_model_add($model,$collection,\%node) - add node to a collection
# (vlans, nets, pools, groups, classes, hosts); a scope is created when
# missing; returns the node
sub dhcp_model_add($$$) {
  my ($model,$coll,$node) = @_;

  die("unknown DHCP model collection: $coll\n") unless ($_COLLECTIONS{$coll});
  $node->{scope} = dhcp_scope_new() unless ($node->{scope});
  if ($coll eq 'hosts') {
    $node->{addresses} = [] unless ($node->{addresses});
    $node->{classes} = [] unless ($node->{classes});
  }
  $node->{ranges} = [] if ($coll eq 'pools' && !$node->{ranges});
  push @{$model->{$coll}}, $node;
  return $node;
}

# dhcp_model_find($model,$collection,$key,$value) - first node whose field
# $key equals $value, undef if not found
sub dhcp_model_find($$$$) {
  my ($model,$coll,$key,$value) = @_;

  foreach my $n (@{$model->{$coll}}) {
    return $n if (defined $n->{$key} && $n->{$key} eq $value);
  }
  return undef;
}

# dhcp_scope_add_stmt($model,$scope,$stmt) - add parsed statement; option
# definitions are registered in the model so that later statements using
# the option get typed
sub dhcp_scope_add_stmt($$$) {
  my ($model,$scope,$st) = @_;

  if ($st->{kind} eq 'option-def' && $st->{fmt} != DHCP_FMT_KEA) {
    my $def = dhcp_option_def_from_isc($st);
    if ($def) {
      $def->{family} = $model->{family};
      dhcp_option_def_register($model->{option_defs},$def);
    }
  }
  push @{$scope->{stmts}}, $st;
  return $st;
}

# dhcp_scope_add_isc($model,$scope,$text) - parse ISC statement and add it
sub dhcp_scope_add_isc($$$) {
  my ($model,$scope,$text) = @_;
  my $st = parse_isc_statement($text,$model->{family},$model->{option_defs});

  return dhcp_scope_add_stmt($model,$scope,$st);
}

# dhcp_scope_add_kea_options($model,$scope,\@option_data) - add KEA
# option-data list
sub dhcp_scope_add_kea_options($$$) {
  my ($model,$scope,$list) = @_;

  return unless ($list && ref($list) eq 'ARRAY');
  foreach my $opt (@$list) {
    next unless ($opt && ref($opt) eq 'HASH');
    my $st = kea_option_to_statement($opt,$model->{family},
				     $model->{option_defs});
    dhcp_model_warn($model,"KEA only option: " .
		    (defined $opt->{name} ? $opt->{name} : "code $opt->{code}"))
      if ($st->{fmt} == DHCP_FMT_KEA);
    dhcp_scope_add_stmt($model,$scope,$st);
  }
}

# dhcp_scope_add_kea_option_defs($model,$scope,\@option_def) - add KEA
# option-def list (must be added before option-data that uses it)
sub dhcp_scope_add_kea_option_defs($$$) {
  my ($model,$scope,$list) = @_;

  return unless ($list && ref($list) eq 'ARRAY');
  foreach my $odef (@$list) {
    next unless ($odef && ref($odef) eq 'HASH');
    my $st = kea_option_def_to_statement($odef,$model->{family});
    dhcp_model_warn($model,"KEA only option definition: $st->{name}")
      if ($st->{fmt} == DHCP_FMT_KEA);
    dhcp_scope_add_stmt($model,$scope,$st);
  }
}

# dhcp_scope_add_kea_params($model,$scope,\%hash,\@skip) - add scalar
# parameters of a KEA scope (subnet, shared-network, ...) except keys in
# @skip (structural keys handled by the caller)
sub dhcp_scope_add_kea_params($$$$) {
  my ($model,$scope,$hash,$skip) = @_;
  my %skip = map { $_ => 1 } (@$skip, 'option-data', 'option-def');

  foreach my $key (sort keys %$hash) {
    next if ($skip{$key});
    my $st = kea_param_to_statement($key,$hash->{$key},$model->{family});
    dhcp_scope_add_stmt($model,$scope,$st);
  }
}

# dhcp_scope_to_isc($model,$scope) - list of ISC statements (without ';')
# for scope; KEA only statements are reported as warnings
sub dhcp_scope_to_isc($$) {
  my ($model,$scope) = @_;
  my @lines;

  foreach my $st (@{$scope->{stmts}}) {
    my $line = format_isc_statement($st);
    if (defined $line) {
      push @lines, $line;
    } else {
      dhcp_model_warn($model,"skipped in ISC output: " . _stmt_desc($st));
    }
  }
  return @lines;
}

# dhcp_scope_to_kea($model,$scope,$resolve,$level) - KEA representation of
# scope:
#   { 'option-data' => [..], 'option-def' => [..], params => { k => v },
#     'client-class' => name, test => expr }
#   $level  scope level ('global', 'shared-network', 'subnet', 'pool',
#           'class', 'host'); ISC permit lists are used in pools only
# statements without KEA equivalent are reported as warnings
sub dhcp_scope_to_kea($$;$$) {
  my ($model,$scope,$resolve,$level) = @_;
  my %res = ('option-data' => [], 'option-def' => [], params => {});

  foreach my $st (@{$scope->{stmts}}) {
    next if ($st->{kind} =~ /^(range|fixed-address|host-id)$/);
    my $r = isc_statement_to_kea($st,$resolve);
    if ($r->{none}) {
      # KEA's default behaviour already matches the statement
    }
    elsif ($r->{error}) {
      dhcp_model_warn($model,"skipped in KEA output: $r->{error}");
    }
    elsif ($r->{'option-data'}) { push @{$res{'option-data'}}, $r->{'option-data'}; }
    elsif ($r->{'option-def'}) { push @{$res{'option-def'}}, $r->{'option-def'}; }
    elsif ($r->{param}) {
      my ($k,$v) = @{$r->{param}};
      $res{params}{$k} = kea_param_merge($k,$res{params}{$k},$v);
    }
    elsif ($r->{'client-class'} && $r->{permit} &&
	   (!defined $level || $level ne 'pool')) {
      dhcp_model_warn($model,"skipped in KEA output: permit list outside " .
		      "of a pool: " . _stmt_desc($st));
    }
    elsif ($r->{'client-class'}) {
      dhcp_model_warn($model,"KEA allows only one client-class per pool, " .
		      "ignoring $r->{'client-class'}")
	if ($res{'client-class'});
      $res{'client-class'} = $r->{'client-class'} unless ($res{'client-class'});
    }
    elsif (defined $r->{test}) { $res{test} = $r->{test}; }
  }
  return \%res;
}

sub _stmt_desc($) {
  my ($st) = @_;

  return $st->{text} if (defined $st->{text});
  return "$st->{key}" if ($st->{kind} eq 'kea');
  return "option $st->{name}" if ($st->{kind} eq 'option');
  return $st->{kind};
}

1;
# eof
