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
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_model_new dhcp_scope_new dhcp_model_add dhcp_model_find
	     dhcp_model_warn dhcp_scope_add_isc dhcp_scope_add_stmt
	     dhcp_scope_add_kea_options dhcp_scope_add_kea_params
	     dhcp_scope_to_isc dhcp_scope_to_kea);

my %_COLLECTIONS = map { $_ => 1 } qw(vlans nets pools groups classes hosts);

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

# dhcp_model_warn($model,$msg) - record a warning
sub dhcp_model_warn($$) {
  my ($model,$msg) = @_;
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

  if ($st->{kind} eq 'option-def') {
    my $def = dhcp_option_def_from_isc($st);
    if ($def) {
      $def->{family} = $model->{family};
      foreach my $by ('isc','kea','code') {
	$model->{option_defs}{$by}{$def->{$by}} = $def;
      }
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

# dhcp_scope_add_kea_params($model,$scope,\%hash,\@skip) - add scalar
# parameters of a KEA scope (subnet, shared-network, ...) except keys in
# @skip (structural keys handled by the caller)
sub dhcp_scope_add_kea_params($$$$) {
  my ($model,$scope,$hash,$skip) = @_;
  my %skip = map { $_ => 1 } (@$skip, 'option-data');

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

# dhcp_scope_to_kea($model,$scope,$resolve) - KEA representation of scope:
#   { 'option-data' => [..], 'option-def' => [..], params => { k => v },
#     'client-class' => name, test => expr }
# statements without KEA equivalent are reported as warnings
sub dhcp_scope_to_kea($$;$) {
  my ($model,$scope,$resolve) = @_;
  my %res = ('option-data' => [], 'option-def' => [], params => {});

  foreach my $st (@{$scope->{stmts}}) {
    next if ($st->{kind} =~ /^(range|fixed-address|host-id)$/);
    my $r = isc_statement_to_kea($st,$resolve);
    if ($r->{error}) {
      dhcp_model_warn($model,"skipped in KEA output: $r->{error}");
    }
    elsif ($r->{'option-data'}) { push @{$res{'option-data'}}, $r->{'option-data'}; }
    elsif ($r->{'option-def'}) { push @{$res{'option-def'}}, $r->{'option-def'}; }
    elsif ($r->{param}) { $res{params}{$r->{param}[0]} = $r->{param}[1]; }
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
