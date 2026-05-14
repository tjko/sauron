# Sauron::UtilDhcp.pm - ISC DHCPD config file reading/parsing routines
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi> 2002.
# $Id:$
#
package Sauron::UtilDhcp;
require Exporter;
use IO::File;
use JSON::PP;
use Sauron::Util;
use strict;
use vars qw($VERSION @ISA @EXPORT);
use open ':locale';

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(process_dhcpdconf process_kea_dhcpconf is_kea_dhcpconf);


my $debug = 0;

sub _init_data_refs($) {
  my ($data) = @_;

  $$data{GLOBAL} = [] unless (defined $$data{GLOBAL} && ref($$data{GLOBAL}) eq 'ARRAY');
  foreach my $key ('shared-network','subnet','subnet6','group','class','subclass','pool','pool6','host') {
    $$data{$key} = {} unless (defined $$data{$key} && ref($$data{$key}) eq 'HASH');
  }

  return 0;
}

sub _arrayref($) {
  my ($value) = @_;
  return $value if (defined $value && ref($value) eq 'ARRAY');
  return [];
}

sub _normalize_hex_sequence($) {
  my ($value) = @_;

  return '' unless (defined $value);

  if ($value =~ /^[0-9A-Fa-f]+$/ && (length($value) % 2) == 0) {
    my @tmp = ($value =~ /(..)/g);
    return join(':',@tmp);
  }

  return $value;
}

sub _bits_to_netmask($) {
  my ($bits) = @_;
  my @octets;
  my ($full,$rest);

  return '' if (!defined $bits || $bits < 0 || $bits > 32);

  $full = int($bits / 8);
  $rest = $bits % 8;

  for my $i (0..3) {
    my $octet = 0;

    if ($i < $full) {
      $octet = 255;
    }
    elsif ($i == $full && $rest > 0) {
      $octet = (0xFF << (8 - $rest)) & 0xFF;
    }

    push @octets, $octet;
  }

  return join('.',@octets);
}

sub _kea_ipv4_subnet_key($) {
  my ($subnet) = @_;
  my ($ip,$bits,$mask);

  return undef unless (defined $subnet);
  return undef unless ($subnet =~ /^\s*(\d{1,3}(?:\.\d{1,3}){3})\/(\d{1,2})\s*$/);

  ($ip,$bits) = ($1,$2);
  return undef if ($bits < 0 || $bits > 32);

  $mask = _bits_to_netmask($bits);
  return undef unless ($mask);

  return "$ip netmask $mask";
}

sub _kea_option_to_line($) {
  my ($opt) = @_;
  my ($name,$space,$line);

  return undef unless (defined $opt && ref($opt) eq 'HASH');

  $name = $$opt{name};
  return undef unless (defined $name && $name ne '');

  $space = $$opt{space};
  if (defined $space && $space ne '' && $space !~ /^dhcp[46]?$/i) {
    $name = "$space.$name";
  }

  $line = "option $name";
  if (defined $$opt{data} && $$opt{data} ne '') {
    $line .= " $$opt{data}";
  }

  $line .= ';';
  return $line;
}

sub _append_option_data_lines($$) {
  my ($dst,$optdata) = @_;

  return unless (defined $dst && ref($dst) eq 'ARRAY');

  foreach my $opt (@{_arrayref($optdata)}) {
    my $line = _kea_option_to_line($opt);
    push @$dst, $line if (defined $line);
  }
}

sub _kea_pool_bounds($) {
  my ($pool) = @_;
  my ($start,$end,$range);

  return () unless (defined $pool && ref($pool) eq 'HASH');

  if (defined $$pool{start} && defined $$pool{end}) {
    return ($$pool{start},$$pool{end});
  }

  if (defined $$pool{'start-address'} && defined $$pool{'end-address'}) {
    return ($$pool{'start-address'},$$pool{'end-address'});
  }

  $range = $$pool{pool};
  return () unless (defined $range);
  return ($1,$2) if ($range =~ /^\s*(\S+)\s*\-\s*(\S+)\s*$/);

  return ();
}

sub _append_kea_host($$$$$) {
  my ($data,$reservation,$v6,$hostcounter,$seenhosts) = @_;
  my ($name,$ip,$id_line,@host_data);

  return unless (defined $reservation && ref($reservation) eq 'HASH');

  $name = $$reservation{hostname};
  unless (defined $name && $name ne '') {
    $$hostcounter++;
    $name = "host-$$hostcounter";
  }

  if ($$seenhosts{$name}) {
    $$hostcounter++;
    $name .= "-$$hostcounter";
  }
  $$seenhosts{$name}=1;

  if (!$v6) {
    $ip = $$reservation{'ip-address'};
    $id_line = $$reservation{'hw-address'};
    return unless (defined $ip && $ip ne '' && defined $id_line && $id_line ne '');

    push @host_data, "fixed-address $ip;";
    push @host_data, "hardware ethernet $id_line;";
  }
  else {
    $ip = $$reservation{'ip-address'};
    if ((!defined $ip || $ip eq '') && ref($$reservation{'ip-addresses'}) eq 'ARRAY') {
      $ip = $$reservation{'ip-addresses'}->[0];
    }

    $id_line = $$reservation{duid};
    return unless (defined $ip && $ip ne '' && defined $id_line && $id_line ne '');

    $id_line = _normalize_hex_sequence($id_line);
    push @host_data, "fixed-address6 $ip;";
    push @host_data, "host-identifier option dhcp6.client-id $id_line;";
  }

  _append_option_data_lines(\@host_data,$$reservation{'option-data'});
  $$data{host}->{$name} = \@host_data;
}

sub _append_kea_subnet($$$$$$$) {
  my ($data,$subnet,$v6,$shared_name,$poolcounter,$hostcounter,$seenhosts) = @_;
  my ($subnet_key,$pool_key,$key,@subnet_data,$vlan_name);

  return unless (defined $subnet && ref($subnet) eq 'HASH');
  return unless (defined $$subnet{subnet} && $$subnet{subnet} ne '');

  $subnet_key = (!$v6 ? 'subnet' : 'subnet6');
  $pool_key = (!$v6 ? 'pool' : 'pool6');

  if (!$v6) {
    $key = _kea_ipv4_subnet_key($$subnet{subnet});
    return unless ($key);
  }
  else {
    $key = $$subnet{subnet};
  }

  if (defined $shared_name && $shared_name ne '') {
    $vlan_name = ($shared_name =~ /\s/ ? "\"$shared_name\"" : $shared_name);
    push @subnet_data, "VLAN $vlan_name";
  }

  _append_option_data_lines(\@subnet_data,$$subnet{'option-data'});
  $$data{$subnet_key}->{$key} = \@subnet_data;

  foreach my $pool (@{_arrayref($$subnet{pools})}) {
    my ($start,$end) = _kea_pool_bounds($pool);
    my @pool_data;
    my $pool_name;

    next unless ($start && $end);

    $$poolcounter++;
    $pool_name = (!$v6 ? "pool-$$poolcounter" : "pool6-$$poolcounter");

    push @pool_data, (!$v6 ? "range $start $end;" : "range6 $start $end;");
    _append_option_data_lines(\@pool_data,$$pool{'option-data'});

    $$data{$pool_key}->{$pool_name} = \@pool_data;
  }

  foreach my $res (@{_arrayref($$subnet{reservations})}) {
    _append_kea_host($data,$res,$v6,$hostcounter,$seenhosts);
  }
}

sub _append_kea_class($$) {
  my ($data,$class) = @_;
  my ($name,$test,@class_data);

  return unless (defined $class && ref($class) eq 'HASH');

  $name = $$class{name};
  return if (ref($name));
  return unless (defined $name && $name ne '');

  $test = $$class{test};
  if (defined $test && !ref($test)) {
    $test =~ s/(^\s+|\s+$)//g;
    push @class_data, "match if $test;" if ($test ne '');
  }
  _append_option_data_lines(\@class_data,$$class{'option-data'});

  $$data{class}->{$name} = \@class_data;
}


sub is_kea_dhcpconf($) {
  my ($filename) = @_;
  my $fh = IO::File->new();

  return 0 unless (-r $filename);
  open($fh,$filename) || return 0;

  while (<$fh>) {
    s/^\s+//;
    s/\s+$//;

    next if ($_ eq '');
    next if (/^#/ || m{^//} || m{^/\*} || /^\*/);

    close($fh);
    return (/^\{/) ? 1 : 0;
  }

  close($fh);
  return 0;
}

# parse dhcpd.conf file, build hash of all entries in the file
#
sub process_dhcpdconf($$$) {
  my ($filename,$data,$v6)=@_;

  my $fh = IO::File->new();
  my ($i,$c,$tmp,$quote,$lend,$fline,$prev,%state);

  print "process_dhcpdconf($filename,DATA)\n" if ($debug);

  fatal("cannot read conf file: $filename") unless (-r $filename);
  open($fh,$filename) || fatal("cannot open conf file: $filename");

  $tmp='';
  while (<$fh>) {
    chomp;
    next if (/^\s*$/);
    next if (/^\s*#/);

    $quote=0;
#    print "line '$_'\n";
    s/\s+/\ /g; s/\s+$//; # s/^\s+//;

    for $i (0..length($_)-1) {
      $prev=($i > 0 ? substr($_,$i-1,1) : ' ');
      $c=substr($_,$i,1);
      $quote=($quote ? 0 : 1)	if (($c eq '"') && ($prev ne '\\'));
      unless ($quote) {
	last if ($c eq '#');
	$lend = ($c =~ /^[;{}]$/ ? 1 : 0);
      }
      $tmp .= $c;
      if ($lend) {
	process_line($tmp,$data,\%state,$v6);
	$tmp='';
      }
    }

    fatal("$filename($.): unterminated quoted string!\n") if ($quote);
  }
  process_line($tmp,$data,\%state,$v6);

  close($fh);

  _init_data_refs($data);

  return 0;
}


sub process_kea_dhcpconf($$$) {
  my ($filename,$data,$v6)=@_;
  my $fh = IO::File->new();
  my ($json_text,$root,$scope,$cfg,$subnet_key,$poolcounter,$hostcounter,%seenhosts);

  fatal("cannot read conf file: $filename") unless (-r $filename);
  open($fh,$filename) || fatal("cannot open conf file: $filename");

  $json_text = '';
  while (<$fh>) {
    $json_text .= $_;
  }
  close($fh);

  eval {
    my $json = JSON::PP->new();
    $json->relaxed(1);
    $root = $json->decode($json_text);
  };
  fatal("cannot parse KEA conf file: $filename ($@)") if ($@);

  fatal("invalid KEA conf root in $filename")
    unless (defined $root && ref($root) eq 'HASH');

  $scope = (!$v6 ? 'Dhcp4' : 'Dhcp6');
  $cfg = $root->{$scope};
  fatal("KEA conf does not include $scope section")
    unless (defined $cfg && ref($cfg) eq 'HASH');

  _init_data_refs($data);

  _append_option_data_lines($$data{GLOBAL},$$cfg{'option-data'});

  $poolcounter = 0;
  $hostcounter = 0;
  $subnet_key = (!$v6 ? 'subnet4' : 'subnet6');

  foreach my $shared (@{_arrayref($$cfg{'shared-networks'})}) {
    my ($name,@sn_data);

    next unless (defined $shared && ref($shared) eq 'HASH');

    $name = $$shared{name};
    unless (defined $name && $name ne '') {
      $name = "shared-network-" . ((scalar keys %{$$data{'shared-network'}}) + 1);
    }

    _append_option_data_lines(\@sn_data,$$shared{'option-data'});
    $$data{'shared-network'}->{$name} = \@sn_data;

    foreach my $subnet (@{_arrayref($$shared{$subnet_key})}) {
      _append_kea_subnet($data,$subnet,$v6,$name,\$poolcounter,\$hostcounter,\%seenhosts);
    }
  }

  foreach my $subnet (@{_arrayref($$cfg{$subnet_key})}) {
    _append_kea_subnet($data,$subnet,$v6,undef,\$poolcounter,\$hostcounter,\%seenhosts);
  }

  foreach my $class (@{_arrayref($$cfg{'client-classes'})}) {
    _append_kea_class($data,$class);
  }

  return 0;
}

sub process_line($$$$) {
  my($line,$data,$state,$v6) = @_;

  my($tmp,$block,$rest,$ref);

  return if ($line =~ /^\s*$/);
  $line =~ s/(^\s+|\s+$)//g;
  #$line =~ s/\"//g;


  #if ($line =~ /^(\S+)\s+(\S.*)?{$/) {
  if ($line =~ /^(\S+)\s?(\s+\S.*)?{$/) {
    $block=lc($1);
    #print "BLOCK: $block\n";
    ($rest=$2) =~ s/^\s+|\s+$//g;
    $rest =~ s/\"//g;
    #print "REST: $rest\n";
    if ($block =~ /^(group)/) {
      # generate name for groups
      $$state{groupcounter}++;
      my $groupname = (!$v6 ? "group" : "group6");
      $rest="$groupname-" . $$state{groupcounter};
    }
    elsif ($block =~ /^(pool[6]?)/) {
      $$state{poolcounter}++;
      $rest="$1-" . $$state{poolcounter};

#warn("pools not under shared-network aren't currently supported");
    }
    #print "begin '$block:$rest'\n";
    unshift @{$$state{BLOCKS}}, $block;
    unshift @{$$state{$block}}, $rest;
    $$data{$block}->{$rest}=[] if ($rest);
    $$state{rest}=$2;

    if ($block =~ /^host/) {
      push @{$$data{$block}->{$rest}}, "GROUP $$state{group}->[0]" if ($$state{group}->[0]);
    }
    if ($block =~ /^subnet[6]?/) {
      if ($$state{'shared-network'}->[0]) {
         push @{$$data{$block}->{$rest}}, "VLAN $$state{'shared-network'}->[0]";
      }
      $$state{lastsubnet} = $rest;
    }

    return 0;
  }

  $block=$$state{BLOCKS}->[0];
  $rest=$$state{$block}->[0];

  if ($line =~ /^\s*}\s*$/) {
    #print "end '$block:$rest'\n";
    unless (@{$$state{BLOCKS}} > 0) {
      warn("mismatched parenthesis");
      return -1;
    }
    shift @{$$state{BLOCKS}};
    shift @{$$state{$block}};
    return 0;
  }

  $block='GLOBAL' unless ($block);
  #print "line($block:$rest) '$line'\n";

  if ($block eq 'GLOBAL') {
    #if($line =~ /subclass\s+\"(.*)\"\s+(.*)/) {
    if($line =~ /subclass\s+\"(.*)\"\s+(.*)/) {
        push @{$$data{'subclass'}->{$1}}, $2;
    }
    else {
        push @{$$data{GLOBAL}}, $line;
    }
  }
  elsif ($block =~ /^(subnet[6]?|shared-network|group|class)$/) {
    push @{$$data{$block}->{$rest}}, $line;
  }
  elsif ($block =~ /^pool[6]?/) {
    push @{$$data{$block}->{$rest}}, $line;
  }
  elsif ($block =~ /^host/) {
    push @{$$data{$block}->{$rest}}, $line;
  }


  return 0;
}

1;
# eof
