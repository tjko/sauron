# Sauron::DhcpIsc.pm - write ISC dhcpd.conf / dhcpd6.conf from the DHCP
#                      model (see Sauron::DhcpModel, Sauron::DhcpDB)
#
# The layout (indentation, comment placement, section headers) is kept
# identical to the original generator in 'sauron'; test/golden/ holds the
# reference output (t/25-dhcp-export-golden.t).
#
package Sauron::DhcpIsc;
require Exporter;
use NetAddr::IP;
use Net::IP qw(:PROC);
use Sauron::DhcpDefs;
use Sauron::DhcpModel;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(dhcp_isc_write);

# statement text with trailing ';', undef if not expressible in ISC
#   $force  always append ';' (QUIRK of pool entries)
sub _line($$;$) {
  my ($model,$st,$force) = @_;
  my $t;

  # KEA only statements are never written (silently, by design)
  return undef if ($st->{fmt} && $st->{fmt} == DHCP_FMT_KEA);
  $t = (defined $st->{orig} ? $st->{orig} : format_isc_statement($st));

  unless (defined $t) {
    dhcp_model_warn($model,"skipped in ISC output: " .
		    (defined $st->{name} ? $st->{name} :
		     defined $st->{key} ? $st->{key} : $st->{kind}));
    return undef;
  }
  $t .= ';' if ($force || $t !~ /[;\{\}]\s*$/);
  return $t;
}

sub _has_comment($) {
  return (defined $_[0] && $_[0] ne '') ? 1 : 0;
}

# print scope statements: $prefix . line [ . $csep . comment ]
#   $csep   comment separator, undef = comments are not written
#   %opt    always_comment => write $csep even without comment
#           force_semicolon => always append ';'
sub _print_scope($$$$$;%) {
  my ($fh,$model,$scope,$prefix,$csep,%opt) = @_;

  foreach my $st (@{$scope->{stmts}}) {
    my $t = _line($model,$st,$opt{force_semicolon});
    next unless (defined $t);
    $t .= "\t# macro eval" if ($st->{macro});
    print $fh $prefix, $t;
    if (defined $csep && ($opt{always_comment} || _has_comment($st->{comment}))) {
      print $fh $csep, (defined $st->{comment} ? $st->{comment} : '');
    }
    print $fh "\n";
  }
}

# dhcp_isc_write($fh,$model,\%meta) - write the configuration
#   meta: filename, version, user, time
sub dhcp_isc_write($$$) {
  my ($fh,$model,$meta) = @_;
  my $v6 = ($model->{family} == 6);
  my $hddc;

  print $fh "# $meta->{filename} -- automagically generated ",
    "by Sauron v$meta->{version}\n";
  print $fh "#               created by $meta->{user} at $meta->{time}\n#\n",
    "# server: $model->{server}{name} -- $model->{server}{comment}\n#\n\n";

  if ($model->{class_only}) {
    _write_classes($fh,$model);
    return 0;
  }

  _write_failover($fh,$model) if ($model->{failover});

  # local and global entries
  my $csep = ($v6 ? "\t# " : "\t # ");
  if (@{$model->{local}{stmts}}) {
    print $fh "\n# local options\n\n";
    _print_scope($fh,$model,$model->{local},'',$csep);
    print $fh "\n\n";
  }
  print $fh "\n# global options\n\n";
  _print_scope($fh,$model,$model->{global},'',$csep);
  print $fh "\n\n";

  $hddc = _write_classes($fh,$model);
  _write_network_map($fh,$model);
  _write_groups($fh,$model);
  _write_ungrouped($fh,$model);

  print $fh "\n#Host declaration for dynamic classes\n";
  print $fh $hddc if (defined $hddc);
  print $fh "\n# eof\n";
  return 0;
}

sub _write_failover($$) {
  my ($fh,$model) = @_;
  my $fo = $model->{failover};

  print $fh "failover peer \"$fo->{name}\" {\n",
    "\t$fo->{role};\n",
    "\taddress $fo->{address};\n",
    "\tport $fo->{port};\n",
    "\tpeer address $fo->{peer_address};\n",
    "\tpeer port $fo->{peer_port};\n",
    "\tmax-response-delay $fo->{max_response_delay};\n",
    "\tmax-unacked-updates $fo->{max_unacked_updates};\n",
    "\tmclt $fo->{mclt};\n",
    ($fo->{role} eq 'primary' ? "\tsplit $fo->{split};\n" : ''),
    "\tload balance max seconds $fo->{load_balance_max};\n}\n\n";
}

# classes; returns host declarations for class members
sub _write_classes($$) {
  my ($fh,$model) = @_;
  my $v6 = ($model->{family} == 6);
  my $hddc;

  return undef unless ($model->{classes_found});

  print $fh "\n# (dynamic) classes\n\n";
  foreach my $cl (@{$model->{classes}}) {
    next if ($cl->{empty});
    print $fh "\nclass \"$cl->{name}\" {\n";
    print $fh "\tmatch pick-first-value (option dhcp-client-identifier, hardware);\n"
      if (!$v6 && $cl->{type} == 3);
    # QUIRK: DHCPv4 class entries always get the comment separator
    _print_scope($fh,$model,$cl->{scope},"\t","\t #",always_comment => !$v6);
    print $fh "}\n\n";

    next unless ($cl->{type} == 3);
    foreach my $m (@{$cl->{members}}) {
      if ($v6) {
	print $fh "subclass \"$cl->{name}\" $m->{id};  # $m->{name}\n";
	$hddc .= sprintf("host %s-%s { host-identifier option dhcp6.client-id %s; }\n",
			 $m->{name},$cl->{name},$m->{id});
      } else {
	print $fh "subclass \"$cl->{name}\" 1:$m->{id};  # $m->{name}\n";
	$hddc .= sprintf("host %s-%s { hardware ethernet %s; }\n",
			 $m->{name},$cl->{name},$m->{id});
      }
    }
  }
  print $fh "\n";
  return $hddc;
}

sub _write_network_map($$) {
  my ($fh,$model) = @_;
  my $v6 = ($model->{family} == 6);

  print $fh "\n# network map\n\n";
  foreach my $vl (@{$model->{vlans}}) {
    print $fh "shared-network \"$vl->{name}\" {\n";
    # QUIRK: comments of DHCPv6 shared-network entries are not written
    _print_scope($fh,$model,$vl->{scope},"\t",($v6 ? undef : "\t # "));
    foreach my $net (@{$vl->{nets}}) {
      print $fh "\t# $net->{name}\n";
      if ($v6) {
	my $n = new Net::IP($net->{cidr});
	print $fh "\tsubnet6 " . ip_compress_address($n->ip(),6) . "/" .
	  $n->prefixlen() . " {\n";
      } else {
	my $n = new NetAddr::IP($net->{cidr});
	print $fh "\tsubnet " . $n->addr() . " netmask " . $n->mask() . " {\n";
	print $fh "\t\toption routers $net->{router};\n" if (defined $net->{router});
      }
      _print_scope($fh,$model,$net->{scope},"\t\t","\t # ");

      foreach my $pool (@{$net->{pools}}) {
	my $kw = ($v6 ? 'pool6' : 'pool');
	print $fh "\t\t$kw {\n";
	foreach my $r (@{$pool->{ranges}}) {
	  print $fh "\t\t\t" . format_isc_statement($r) . ";\n";
	}
	# DHCPv4 failover: pools are shared with the peer
	print $fh "\t\t\tfailover peer \"$model->{failover}{name}\";\n",
	  "\t\t\tdeny dynamic bootp clients;\n" if ($model->{failover} && !$v6);
	# QUIRK: pool entries are written without comments, ';' always added
	_print_scope($fh,$model,$pool->{scope},"\t\t\t",undef,force_semicolon => 1);
	print $fh "\t\t}\n";
      }
      print $fh "\t}\n";
    }
    print $fh "}\n\n";
  }
}

sub _net_label($$$) {
  my ($model,$idx,$grouped) = @_;
  my $cidr = $model->{netblocks}[$idx]{cidr};

  return (new NetAddr::IP($cidr))->cidr() unless ($model->{family} == 6);
  my $n = new Net::IP($cidr);
  return ($grouped ? ip_compress_address($n->ip(),6) : $n->short());
}

sub _write_host($$$$) {
  my ($fh,$model,$h,$ind) = @_;
  my $v6 = ($model->{family} == 6);

  print $fh "${ind}host $h->{name} {\n";
  if ($v6) {
    print $fh "${ind}\tfixed-address6 $h->{address_text};\n";
    print $fh "${ind}\thost-identifier option dhcp6.client-id $h->{duid_text};\n";
  } else {
    print $fh "${ind}\tfixed-address $h->{address_text};\n";
    print $fh "${ind}\thardware ethernet $h->{hw_address};\n";
  }
  _print_scope($fh,$model,$h->{scope},"${ind}\t",($ind ? "\t#" : "\t #"));
  print $fh "${ind}}\n";
}

sub _write_groups($$) {
  my ($fh,$model) = @_;
  my $nnets = scalar @{$model->{netblocks}};

  print $fh "# groups\n\n";
  foreach my $g (@{$model->{groups}}) {
    print $fh "group {  # $g->{name}\n";
    _print_scope($fh,$model,$g->{scope},"\t","\t #");
    print $fh "\t\n";
    for my $j (0..$nnets-1) {
      print $fh "\t# net: " . _net_label($model,$j,1) . "\n";
      foreach my $h (@{$g->{hosts}}) {
	_write_host($fh,$model,$h,"\t") if ($h->{net} == $j);
      }
    }
    print $fh "}\n\n";
  }
}

sub _write_ungrouped($$) {
  my ($fh,$model) = @_;
  my $nnets = scalar @{$model->{netblocks}};

  print $fh "\n# hosts not in any group\n\n";
  return unless ($model->{ungrouped});
  for my $j (0..$nnets-1) {
    print $fh "# net: " . _net_label($model,$j,0) . "\n";
    foreach my $h (@{$model->{ungrouped_hosts}}) {
      _write_host($fh,$model,$h,'') if ($h->{net} == $j);
    }
  }
}

1;
# eof
