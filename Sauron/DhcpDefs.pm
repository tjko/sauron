# Sauron::DhcpDefs.pm - DHCP option/parameter definitions shared by the
#                       ISC dhcpd and KEA readers/writers
#
# Statements are stored in the database as ISC dhcpd syntax (one statement
# per dhcp_entries row, without the trailing ';'). This module parses such a
# statement into a neutral structure and formats it back either as ISC syntax
# or as a KEA JSON fragment, using a single table of option/parameter
# definitions so that both outputs stay consistent.
#
# Statement structure (hashref):
#   kind    'option' | 'option-def' | 'param' | 'permit' | 'range' |
#           'host-id' | 'fixed-address' | 'match' | 'raw' | 'kea'
#   text    original ISC text (when parsed from ISC); the ISC writer prefers
#           it so that existing configurations are reproduced verbatim
#   fmt     target format: 0 = both, 1 = ISC only, 2 = KEA only
#   ...     kind specific fields (see parse_isc_statement)
#
package Sauron::DhcpDefs;
require Exporter;
use JSON::PP;
use Net::IP qw(ip_is_ipv4 ip_is_ipv6);
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter);
@EXPORT = qw(DHCP_FMT_BOTH DHCP_FMT_ISC DHCP_FMT_KEA %DHCP_FMT_NAMES
	     dhcp_entry_check
	     dhcp_option_def dhcp_param_def dhcp_option_def_from_isc
	     dhcp_option_def_register
	     parse_isc_statement format_isc_statement
	     isc_statement_to_kea kea_option_to_statement
	     kea_option_def_to_statement kea_param_to_statement
	     kea_statement_to_json kea_json_to_statement kea_param_merge);

use constant DHCP_FMT_BOTH => 0;
use constant DHCP_FMT_ISC  => 1;
use constant DHCP_FMT_KEA  => 2;

# user visible names of dhcp_entries.fmt values
use vars qw(%DHCP_FMT_NAMES);
%DHCP_FMT_NAMES = (0 => 'ISC + KEA', 1 => 'ISC only', 2 => 'KEA only');

# Value types:
#   ip4, ip6     address (ISC also accepts a hostname for ip4)
#   text         string, quoted in ISC
#   string       ISC "quoted text" or colon separated hex; KEA string
#   fqdn         domain name, quoted in ISC
#   uint8/16/32, int8/16/32, bool
#   binary       ISC "quoted text" or colon separated hex; KEA hex
#
# Option table: [ code, ISC name, KEA name, type, array ]
# ISC names of DHCPv6 options carry the 'dhcp6.' space prefix.
my @_OPTIONS4 = (
  [  1, 'subnet-mask',              undef, 'ip4',    0 ],
  [  2, 'time-offset',              undef, 'int32',  0 ],
  [  3, 'routers',                  undef, 'ip4',    1 ],
  [  4, 'time-servers',             undef, 'ip4',    1 ],
  [  5, 'name-servers',             undef, 'ip4',    1 ],
  [  6, 'domain-name-servers',      undef, 'ip4',    1 ],
  [  7, 'log-servers',              undef, 'ip4',    1 ],
  [  9, 'lpr-servers',              undef, 'ip4',    1 ],
  [ 12, 'host-name',                undef, 'text',   0 ],
  [ 13, 'boot-size',                undef, 'uint16', 0 ],
  [ 14, 'merit-dump',               undef, 'text',   0 ],
  [ 15, 'domain-name',              undef, 'fqdn',   0 ],
  [ 16, 'swap-server',              undef, 'ip4',    0 ],
  [ 17, 'root-path',                undef, 'text',   0 ],
  [ 19, 'ip-forwarding',            undef, 'bool',   0 ],
  [ 23, 'default-ip-ttl',           undef, 'uint8',  0 ],
  [ 26, 'interface-mtu',            undef, 'uint16', 0 ],
  [ 28, 'broadcast-address',        undef, 'ip4',    0 ],
  [ 33, 'static-routes',            undef, 'ip4',    1 ],
  [ 35, 'arp-cache-timeout',        undef, 'uint32', 0 ],
  [ 40, 'nis-domain',               undef, 'text',   0 ],
  [ 41, 'nis-servers',              undef, 'ip4',    1 ],
  [ 42, 'ntp-servers',              undef, 'ip4',    1 ],
  [ 44, 'netbios-name-servers',     undef, 'ip4',    1 ],
  [ 46, 'netbios-node-type',        undef, 'uint8',  0 ],
  [ 47, 'netbios-scope',            undef, 'text',   0 ],
  [ 51, 'dhcp-lease-time',          undef, 'uint32', 0 ],
  [ 58, 'dhcp-renewal-time',        undef, 'uint32', 0 ],
  [ 59, 'dhcp-rebinding-time',      undef, 'uint32', 0 ],
  [ 60, 'vendor-class-identifier',  undef, 'string', 0 ],
  [ 61, 'dhcp-client-identifier',   undef, 'binary', 0 ],
  [ 64, 'nisplus-domain-name',      undef, 'text',   0 ],
  [ 65, 'nisplus-servers',          undef, 'ip4',    1 ],
  [ 66, 'tftp-server-name',         undef, 'text',   0 ],
  [ 67, 'bootfile-name',            undef, 'text',   0 ],
  [ 69, 'smtp-server',              undef, 'ip4',    1 ],
  [ 70, 'pop-server',               undef, 'ip4',    1 ],
  [ 72, 'www-server',               undef, 'ip4',    1 ],
  [119, 'domain-search',            undef, 'fqdn',   1 ],
);

my @_OPTIONS6 = (
  [  7, 'dhcp6.preference',            'preference',               'uint8',  0 ],
  [ 12, 'dhcp6.unicast',               'unicast',                  'ip6',    0 ],
  [ 21, 'dhcp6.sip-servers-names',     'sip-server-dns',           'fqdn',   1 ],
  [ 22, 'dhcp6.sip-servers-addresses', 'sip-server-addr',          'ip6',    1 ],
  [ 23, 'dhcp6.name-servers',          'dns-servers',              'ip6',    1 ],
  [ 24, 'dhcp6.domain-search',         'domain-search',            'fqdn',   1 ],
  [ 27, 'dhcp6.nis-servers',           'nis-servers',              'ip6',    1 ],
  [ 28, 'dhcp6.nisp-servers',          'nisp-servers',             'ip6',    1 ],
  [ 29, 'dhcp6.nis-domain-name',       'nis-domain-name',          'fqdn',   1 ],
  [ 30, 'dhcp6.nisp-domain-name',      'nisp-domain-name',         'fqdn',   1 ],
  [ 31, 'dhcp6.sntp-servers',          'sntp-servers',             'ip6',    1 ],
  [ 32, 'dhcp6.info-refresh-time',     'information-refresh-time', 'uint32', 0 ],
  [ 59, 'dhcp6.bootfile-url',          'bootfile-url',             'text',   0 ],
);

# Parameter table: [ ISC name, KEA name, type, family (4, 6 or 0 = both) ]
my @_PARAMS = (
  [ 'default-lease-time', 'valid-lifetime',     'uint32', 0 ],
  [ 'max-lease-time',     'max-valid-lifetime', 'uint32', 0 ],
  [ 'min-lease-time',     'min-valid-lifetime', 'uint32', 0 ],
  [ 'preferred-lifetime', 'preferred-lifetime', 'uint32', 6 ],
  [ 'next-server',        'next-server',        'ip4',    4 ],
  [ 'filename',           'boot-file-name',     'text',   4 ],
  [ 'server-name',        'server-hostname',    'text',   4 ],
  [ 'authoritative',      'authoritative',      'flag',   4 ],
  # dynamic DNS (KEA sends updates through kea-dhcp-ddns)
  [ 'ddns-updates',       'ddns-send-updates',  'onoff',  0 ],
  [ 'ddns-domainname',    'ddns-qualifying-suffix', 'text', 0 ],
  [ 'client-updates',     'ddns-override-client-update', 'clientupd', 0 ],
  [ 'ddns-update-style',  'dhcp-ddns',          'ddnsstyle', 0 ],
);
# ISC parameters whose KEA form is not converted back (KEA only there)
my %_PARAM_NO_REVERSE = ('dhcp-ddns' => 1);

# ISC option-def type <-> KEA option-def type
my %_ISC2KEA_TYPE = (
  'ip-address'                => 'ip4',
  'ip6-address'               => 'ip6',
  'text'                      => 'text',
  'domain-name'               => 'fqdn',
  'domain-list'               => 'fqdn+',
  'string'                    => 'binary',
  'boolean'                   => 'bool',
  'unsigned integer 8'        => 'uint8',
  'unsigned integer 16'       => 'uint16',
  'unsigned integer 32'       => 'uint32',
  'signed integer 8'          => 'int8',
  'signed integer 16'         => 'int16',
  'signed integer 32'         => 'int32',
  'integer 8'                 => 'int8',
  'integer 16'                => 'int16',
  'integer 32'                => 'int32',
);

my %_TYPE2KEA = (
  ip4 => 'ipv4-address', ip6 => 'ipv6-address', text => 'string',
  string => 'string',
  fqdn => 'fqdn', binary => 'binary', bool => 'boolean',
  uint8 => 'uint8', uint16 => 'uint16', uint32 => 'uint32',
  int8 => 'int8', int16 => 'int16', int32 => 'int32',
);
my %_KEA2TYPE = (
  'ipv4-address' => 'ip4', 'ipv6-address' => 'ip6', string => 'text',
  fqdn => 'fqdn', binary => 'binary', boolean => 'bool',
  uint8 => 'uint8', uint16 => 'uint16', uint32 => 'uint32',
  int8 => 'int8', int16 => 'int16', int32 => 'int32',
);

my %_TYPE2ISC = (
  ip4 => 'ip-address', ip6 => 'ip6-address', text => 'text',
  fqdn => 'domain-name', binary => 'string', bool => 'boolean',
  uint8 => 'unsigned integer 8', uint16 => 'unsigned integer 16',
  uint32 => 'unsigned integer 32', int8 => 'signed integer 8',
  int16 => 'signed integer 16', int32 => 'signed integer 32',
);

# lookup indexes: $_IDX{$family}{isc|kea|code}{$key} = def
my %_IDX;

sub _mkdef($$) {
  my ($family,$r) = @_;
  my ($code,$isc,$kea,$type,$array) = @$r;

  $kea = $isc unless (defined $kea);
  return { code => $code, isc => $isc, kea => $kea, type => $type,
	   array => $array, family => $family,
	   space => ($family == 6 ? 'dhcp6' : 'dhcp4') };
}

sub _std_space($) {
  return (!defined $_[0] || $_[0] =~ /^dhcp[46]$/) ? 1 : 0;
}

foreach my $r (@_OPTIONS4) {
  my $d = _mkdef(4,$r);
  $_IDX{4}{isc}{$d->{isc}} = $_IDX{4}{kea}{$d->{kea}} = $d;
  $_IDX{4}{code}{$d->{code}} = $d;
}
foreach my $r (@_OPTIONS6) {
  my $d = _mkdef(6,$r);
  $_IDX{6}{isc}{$d->{isc}} = $_IDX{6}{kea}{$d->{kea}} = $d;
  $_IDX{6}{code}{$d->{code}} = $d;
}

my (%_PARAM_ISC,%_PARAM_KEA);
foreach my $r (@_PARAMS) {
  my $d = { isc => $r->[0], kea => $r->[1], type => $r->[2],
	    family => $r->[3] };
  $_PARAM_ISC{$d->{isc}} = $d;
  $_PARAM_KEA{$d->{kea}} = $d unless ($_PARAM_NO_REVERSE{$d->{kea}});
}

sub _family($) { return ($_[0] && $_[0] == 6 ? 6 : 4); }

# dhcp_option_def($family,$by,$key,$custom) - look up an option definition
#   $by     'isc' (ISC name), 'kea' (KEA name) or 'code'; options outside
#           the standard dhcp4/dhcp6 space use 'space.name' / 'space.code'
#           keys for 'kea' and 'code' lookups
#   $custom optional hashref of user defined options with the same layout
#           as the internal index ({isc|kea|code}{$key} = def), see
#           dhcp_option_def_register
# returns def hashref or undef
sub dhcp_option_def($$$;$) {
  my ($family,$by,$key,$custom) = @_;

  return undef unless (defined $key);
  $family = _family($family);
  return $custom->{$by}{$key}
    if ($custom && $custom->{$by} && $custom->{$by}{$key});
  return $_IDX{$family}{$by}{$key};
}

# dhcp_option_def_register($custom,$def) - add user defined option to
# $custom index (used by dhcp_option_def); options in non-standard spaces
# are indexed by space qualified keys so they never shadow standard options
sub dhcp_option_def_register($$) {
  my ($custom,$def) = @_;
  my $std = _std_space($def->{space});

  $custom->{isc}{$def->{isc}} = $def;
  $custom->{kea}{$std ? $def->{kea} : "$def->{space}.$def->{kea}"} = $def;
  $custom->{code}{$std ? $def->{code} : "$def->{space}.$def->{code}"} = $def;
  return $def;
}

# dhcp_param_def($by,$key,$family) - look up parameter definition
#   $by 'isc' or 'kea'; returns def hashref or undef when unknown or not
#   valid for given address family
sub dhcp_param_def($$$) {
  my ($by,$key,$family) = @_;
  my $d = ($by eq 'kea' ? $_PARAM_KEA{$key} : $_PARAM_ISC{$key});

  return undef unless ($d);
  return undef if ($d->{family} && $d->{family} != _family($family));
  return $d;
}

# dhcp_option_def_from_isc($stmt) - turn parsed 'option-def' statement into
# an option definition usable as $custom entry; undef if type unsupported
sub dhcp_option_def_from_isc($) {
  my ($stmt) = @_;
  my ($type,$array,$name,$space);

  return undef unless ($stmt && $stmt->{kind} eq 'option-def');
  ($type = $stmt->{isc_type}) =~ s/\s+/ /g;
  $array = ($type =~ s/^array of //) ? 1 : 0;
  $type = $_ISC2KEA_TYPE{$type};
  return undef unless ($type);
  if ($type eq 'fqdn+') { $type = 'fqdn'; $array = 1; }

  $name = $stmt->{name};
  $space = $stmt->{space};
  return { code => int($stmt->{code}), isc => $name,
	   kea => ($name =~ /\.([^.]+)$/ ? $1 : $name),
	   type => $type, array => $array, custom => 1,
	   family => $stmt->{family}, space => $space };
}


###########################################################################
# value helpers

sub _is_ip4($) {
  my ($ip) = @_;
  return (defined $ip && $ip =~ /^\d{1,3}(?:\.\d{1,3}){3}$/ &&
	  ip_is_ipv4($ip)) ? 1 : 0;
}

sub _is_ip6($) {
  my ($ip) = @_;
  return (defined $ip && $ip =~ /:/ && ip_is_ipv6($ip)) ? 1 : 0;
}

# types whose values are kept in ISC literal form ("text" or hex)
sub _isc_literal_type($) {
  return ($_[0] eq 'binary' || $_[0] eq 'string') ? 1 : 0;
}

# ISC on/off (also true/false, 1/0, JSON booleans) -> 1/0, undef if invalid
sub _onoff($) {
  my ($v) = @_;
  return undef unless (defined $v);
  return ($v ? 1 : 0) if (ref($v) eq 'JSON::PP::Boolean');
  return 1 if ($v =~ /^(on|true|1)$/i);
  return 0 if ($v =~ /^(off|false|0)$/i);
  return undef;
}

# ISC boolean literal -> KEA 'true'/'false', undef if invalid
sub _bool_to_kea($) {
  my $b = _onoff($_[0]);
  return (defined $b ? ($b ? 'true' : 'false') : undef);
}

# ISC string literal ("text" or colon hex) -> plain text, undef if the
# hex form does not decode to printable text
sub _string_to_kea($) {
  my ($v) = @_;

  return _unquote($v) if ($v =~ /^".*"$/s);
  return undef unless ($v =~ /^[0-9A-Fa-f]{1,2}(?::[0-9A-Fa-f]{1,2})*$/);
  my $t = join('',map { chr(hex($_)) } split(/:/,$v));
  return ($t =~ /^[\x20-\x7e]*$/) ? $t : undef;
}

sub _unquote($) {
  my ($s) = @_;

  return $s unless ($s =~ /^"(.*)"$/s);
  $s = $1;
  $s =~ s/\\(["\\])/$1/g;
  return $s;
}

sub _quote($) {
  my ($s) = @_;

  $s =~ s/(["\\])/\\$1/g;
  return "\"$s\"";
}

# split string on commas that are not inside double quotes
sub _split_list($) {
  my ($s) = @_;
  my (@items,$cur,$quote,$prev);

  $cur = ''; $quote = 0; $prev = '';
  foreach my $c (split(//,$s)) {
    $quote = !$quote if ($c eq '"' && $prev ne '\\');
    if ($c eq ',' && !$quote) {
      push @items, $cur;
      $cur = '';
    } else {
      $cur .= $c;
    }
    $prev = $c;
  }
  push @items, $cur;
  s/^\s+|\s+$//g foreach (@items);
  return grep { $_ ne '' } @items;
}

# split KEA csv data (commas escaped with backslash)
sub _split_kea_list($) {
  my ($s) = @_;
  my @items = split(/(?<!\\),/,$s);

  foreach (@items) { s/^\s+|\s+$//g; s/\\,/,/g; }
  return grep { $_ ne '' } @items;
}

sub _kea_escape($) {
  my ($s) = @_;
  $s =~ s/,/\\,/g;
  return $s;
}

# decode ISC value text into list of plain values
sub _isc_values($$) {
  my ($def,$text) = @_;
  my @items = ($def->{array} ? _split_list($text) : ($text));

  # binary/string values keep their ISC form ("text" or colon hex)
  return @items if (_isc_literal_type($def->{type}));
  return map { _unquote($_) } @items;
}

sub _isc_value_text($$) {
  my ($type,$v) = @_;

  return _quote($v) if ($type eq 'text' || $type eq 'fqdn');
  return $v;
}

# binary value: ISC "text" or aa:bb:cc  ->  KEA hex
sub _binary_to_kea($) {
  my ($v) = @_;

  if ($v =~ /^"(.*)"$/s) {
    return uc(unpack('H*',_unquote($v)));
  }
  if ($v =~ /^[0-9A-Fa-f]{1,2}(?::[0-9A-Fa-f]{1,2})*$/) {
    return uc(join('',map { sprintf('%02s',$_) } split(/:/,$v)));
  }
  return undef;
}

# KEA hex (optionally 0x prefixed / colon separated) or 'text' -> ISC
sub _binary_to_isc($) {
  my ($v) = @_;

  return _quote($1) if ($v =~ /^'(.*)'$/s);
  $v =~ s/^0x//i;
  $v =~ s/[:\s]//g;
  return undef unless ($v =~ /^[0-9A-Fa-f]+$/ && length($v) % 2 == 0);
  return lc(join(':',($v =~ /(..)/g)));
}


###########################################################################
# ISC statement parser

# parse_isc_statement($text,$family,$custom) - parse one ISC statement
#   $text   statement without the trailing ';' (a trailing ';' is ignored)
#   $family 4 or 6
#   $custom optional user defined options index (see dhcp_option_def)
# returns statement hashref; unknown statements have kind 'raw' and are
# kept for ISC output only (fmt = DHCP_FMT_ISC)
sub parse_isc_statement($$;$) {
  my ($text,$family,$custom) = @_;
  my ($s,$st,$name,$rest,$def);

  $family = _family($family);
  ($s = $text) =~ s/^\s+|\s*;?\s*$//g;
  $st = { text => $s, fmt => DHCP_FMT_BOTH, family => $family };

  # option definition: option [space.]name code N = type
  if ($s =~ /^option\s+(\S+)\s+code\s+(\d+)\s*=\s*(.+)$/i) {
    my ($n,$code,$type) = ($1,$2,$3);
    my $space = ($n =~ /^([^.]+)\.[^.]+$/ ? $1 : ($family == 6 ? 'dhcp6' : 'dhcp4'));
    @$st{qw(kind name code isc_type space)} = ('option-def',$n,$code,$type,$space);
    $st->{fmt} = DHCP_FMT_ISC unless (dhcp_option_def_from_isc($st));
    return $st;
  }

  # option value
  if ($s =~ /^option\s+(\S+)(?:\s+(.*))?$/i) {
    ($name,$rest) = ($1,(defined $2 ? $2 : ''));
    $st->{kind} = 'option';
    $st->{name} = $name;
    $def = dhcp_option_def($family,'isc',$name,$custom);
    if ($def) {
      $st->{def} = $def;
      $st->{values} = [ _isc_values($def,$rest) ];
    } else {
      $st->{raw} = $rest;
      $st->{fmt} = DHCP_FMT_ISC;
    }
    return $st;
  }

  # pool permit lists: allow/deny members of "class", unknown-clients, ...
  if ($s =~ /^(allow|deny|ignore)\s+members\s+of\s+(.+)$/i) {
    @$st{qw(kind action what class)} =
      ('permit',lc($1),'members',_unquote($2));
    return $st;
  }
  if ($s =~ /^(allow|deny)\s+(known-clients|unknown-clients)$/i) {
    @$st{qw(kind action what)} = ('permit',lc($1),lc($2));
    return $st;
  }

  # address ranges
  if ($s =~ /^range\s+(?:(dynamic-bootp)\s+)?(\S+)(?:\s+(\S+))?$/i) {
    @$st{qw(kind start end)} = ('range',$2,(defined $3 ? $3 : $2));
    $st->{fmt} = DHCP_FMT_ISC if ($1);
    return $st;
  }
  if ($s =~ /^range6\s+(\S+)\s+(\S+)$/i) {
    @$st{qw(kind start end)} = ('range',$1,$2);
    return $st;
  }
  if ($s =~ /^range6\s+(\S+\/\d+)$/i) {
    @$st{qw(kind prefix)} = ('range',$1);
    return $st;
  }

  # host identification
  if ($s =~ /^fixed-address6?\s+(.+)$/i) {
    @$st{qw(kind addresses)} = ('fixed-address',[ _split_list($1) ]);
    return $st;
  }
  if ($s =~ /^hardware\s+ethernet\s+(\S+)$/i) {
    @$st{qw(kind type value)} = ('host-id','hw-address',lc($1));
    return $st;
  }
  if ($s =~ /^host-identifier\s+option\s+dhcp6\.client-id\s+(\S+)$/i) {
    @$st{qw(kind type value)} = ('host-id','duid',lc($1));
    return $st;
  }

  # class matching
  if ($s =~ /^match\s+if\s+(.+)$/i) {
    @$st{qw(kind expr)} = ('match',$1);
    return $st;
  }

  # parameters
  if ($s =~ /^(not\s+)?authoritative$/i) {
    @$st{qw(kind name value)} = ('param','authoritative',($1 ? 0 : 1));
    $st->{def} = dhcp_param_def('isc','authoritative',$family);
    $st->{fmt} = DHCP_FMT_ISC unless ($st->{def});
    return $st;
  }
  if ($s =~ /^(allow|deny|ignore)\s+client-updates$/i) {
    @$st{qw(kind name value def)} = ('param','client-updates',lc($1),
				      dhcp_param_def('isc','client-updates',$family));
    return $st;
  }
  if ($s =~ /^(\S+)\s+(.+)$/ && ($def = dhcp_param_def('isc',lc($1),$family))) {
    @$st{qw(kind name value def)} = ('param',$def->{isc},_unquote($2),$def);
    return $st;
  }

  $st->{kind} = 'raw';
  $st->{fmt} = DHCP_FMT_ISC;
  return $st;
}

# format_isc_statement($stmt) - ISC text (without ';') for statement,
# undef if the statement cannot be expressed in ISC syntax
sub format_isc_statement($) {
  my ($st) = @_;
  my ($def,@v);

  return undef unless ($st);
  return undef if ($st->{fmt} && $st->{fmt} == DHCP_FMT_KEA);
  return $st->{text} if (defined $st->{text} && $st->{text} ne '');

  my $k = $st->{kind};
  if ($k eq 'option') {
    $def = $st->{def};
    return "option $st->{name} $st->{raw}" unless ($def);
    @v = map { _isc_value_text($def->{type},$_) } @{$st->{values}};
    return "option $def->{isc} " . join(', ',@v);
  }
  if ($k eq 'option-def') {
    return "option $st->{name} code $st->{code} = $st->{isc_type}";
  }
  if ($k eq 'param') {
    $def = $st->{def};
    if ($def->{type} eq 'flag') {
      return ($st->{value} ? '' : 'not ') . $def->{isc};
    }
    return "$def->{isc} " . (_onoff($st->{value}) ? 'on' : 'off')
      if ($def->{type} eq 'onoff');
    return "$st->{value} client-updates" if ($def->{type} eq 'clientupd');
    return "$def->{isc} " . _isc_value_text($def->{type},$st->{value});
  }
  if ($k eq 'permit') {
    return "$st->{action} members of " . _quote($st->{class})
      if ($st->{what} eq 'members');
    return "$st->{action} $st->{what}";
  }
  if ($k eq 'range') {
    my $kw = ($st->{family} == 6 ? 'range6' : 'range');
    return "$kw $st->{prefix}" if ($st->{prefix});
    return "$kw $st->{start} $st->{end}";
  }
  if ($k eq 'fixed-address') {
    return ($st->{family} == 6 ? 'fixed-address6 ' : 'fixed-address ') .
      join(', ',@{$st->{addresses}});
  }
  if ($k eq 'host-id') {
    return "hardware ethernet $st->{value}" if ($st->{type} eq 'hw-address');
    return "host-identifier option dhcp6.client-id $st->{value}"
      if ($st->{type} eq 'duid');
    return undef;
  }
  if ($k eq 'match') {
    return undef unless (defined $st->{expr});
    return "match if $st->{expr}";
  }
  return undef;
}


###########################################################################
# KEA conversion

# isc_statement_to_kea($stmt,$resolve) - convert statement to KEA form
#   $resolve optional coderef($name) returning IP address for a hostname
#            (ISC accepts hostnames where KEA requires addresses)
# returns hashref with one of:
#   { 'option-data' => {...} }      option-data element
#   { 'option-def'  => {...} }      option-def element
#   { param => [ key, value ] }     scope parameter
#   { 'client-class' => name,       pool client class (from permit list;
#     permit => 1 }                  valid in a pool only)
#   { test => expr }                class test expression (KEA syntax)
#   { error => msg }                not representable in KEA
sub isc_statement_to_kea($;$) {
  my ($st,$resolve) = @_;
  my ($k,$def,@v,$data);

  return { error => 'undefined statement' } unless ($st);
  $k = $st->{kind};

  if ($k eq 'kea') {
    return { param => [ $st->{key}, $st->{value} ] };
  }
  if ($st->{fmt} && $st->{fmt} == DHCP_FMT_ISC) {
    return { error => "ISC only statement: $st->{text}" };
  }

  if ($k eq 'option') {
    $def = $st->{def};
    # KEA only option kept verbatim from KEA configuration
    return { 'option-data' => { %{$st->{kea}} } } if (!$def && $st->{kea});
    return { error => "unknown option: $st->{name}" } unless ($def);
    return { 'option-data' => { %{$st->{kea}} } }
      if ($st->{fmt} && $st->{fmt} == DHCP_FMT_KEA && $st->{kea});
    foreach my $val (@{$st->{values}}) {
      my $x = $val;
      if ($def->{type} eq 'ip4' && !_is_ip4($x)) {
	$x = ($resolve ? $resolve->($val) : undef);
	return { error => "cannot resolve '$val' to an IPv4 address " .
		   "(option $def->{isc})" } unless ($x && _is_ip4($x));
      }
      elsif ($def->{type} eq 'ip6' && !_is_ip6($x)) {
	$x = ($resolve ? $resolve->($val) : undef);
	return { error => "cannot resolve '$val' to an IPv6 address " .
		   "(option $def->{isc})" } unless ($x && _is_ip6($x));
      }
      elsif ($def->{type} eq 'binary') {
	$x = _binary_to_kea($val);
	return { error => "invalid binary value '$val' (option $def->{isc})" }
	  unless (defined $x);
      }
      elsif ($def->{type} eq 'string') {
	$x = _string_to_kea($val);
	return { error => "invalid string value '$val' (option $def->{isc})" }
	  unless (defined $x);
	$x = _kea_escape($x);
      }
      elsif ($def->{type} eq 'bool') {
	$x = _bool_to_kea($val);
	return { error => "invalid boolean value '$val' (option $def->{isc})" }
	  unless (defined $x);
      }
      elsif ($def->{type} eq 'text' || $def->{type} eq 'fqdn') {
	$x = _kea_escape($x);
      }
      push @v, $x;
    }
    $data = { name => $def->{kea}, data => join(', ',@v) };
    $data->{code} = int($def->{code});
    $data->{space} = $def->{space} if ($def->{custom});
    $data->{'always-send'} = JSON::PP::true() if ($st->{'always-send'});
    return { 'option-data' => $data };
  }

  if ($k eq 'option-def') {
    return { 'option-def' => { %{$st->{kea}} } } if ($st->{kea});
    $def = dhcp_option_def_from_isc($st);
    return { error => "unsupported option type: $st->{isc_type}" }
      unless ($def);
    return { 'option-def' => { name => $def->{kea}, code => int($def->{code}),
			       type => $_TYPE2KEA{$def->{type}},
			       array => ($def->{array} ? JSON::PP::true()
					 : JSON::PP::false()),
			       space => $def->{space} } };
  }

  if ($k eq 'param') {
    $def = $st->{def};
    my $val = $st->{value};
    if ($def->{type} =~ /^u?int/) {
      return { error => "invalid number '$val' ($def->{isc})" }
	unless ($val =~ /^-?\d+$/);
      $val = int($val);
    }
    elsif ($def->{type} eq 'flag') {
      $val = ($val ? JSON::PP::true() : JSON::PP::false());
    }
    elsif ($def->{type} eq 'onoff') {
      my $b = _onoff($val);
      return { error => "invalid on/off value '$val' ($def->{isc})" }
	unless (defined $b);
      $val = ($b ? JSON::PP::true() : JSON::PP::false());
    }
    elsif ($def->{type} eq 'clientupd') {
      # allow = honour the client's FQDN flags, deny/ignore = override them
      return { error => "invalid client-updates statement: $st->{text}" }
	unless (lc($val) =~ /^(allow|deny|ignore)$/);
      $val = (lc($val) eq 'allow' ? JSON::PP::false() : JSON::PP::true());
    }
    elsif ($def->{type} eq 'ddnsstyle') {
      # no updates is KEA's default; interim/standard enable updates through
      # kea-dhcp-ddns (connection settings: KEA only 'dhcp-ddns' entry,
      # merged with this one, see kea_param_merge)
      return { none => 1 } if (lc($val) eq 'none');
      return { error => "ddns-update-style $val has no KEA equivalent" }
	unless ($val =~ /^(interim|standard)$/i);
      $val = { 'enable-updates' => JSON::PP::true() };
    }
    elsif ($def->{type} eq 'ip4' && !_is_ip4($val)) {
      my $ip = ($resolve ? $resolve->($val) : undef);
      return { error => "cannot resolve '$val' to an IPv4 address " .
		 "($def->{isc})" } unless ($ip && _is_ip4($ip));
      $val = $ip;
    }
    return { param => [ $def->{kea}, $val ] };
  }

  if ($k eq 'permit') {
    return { error => "deny members of is not supported by KEA" }
      if ($st->{what} eq 'members' && $st->{action} ne 'allow');
    return { 'client-class' => $st->{class}, permit => 1 }
      if ($st->{what} eq 'members');
    # KEA built-in classes KNOWN/UNKNOWN (host reservation exists or not)
    my $known = ($st->{what} eq 'known-clients');
    $known = !$known if ($st->{action} eq 'deny');
    return { 'client-class' => ($known ? 'KNOWN' : 'UNKNOWN'), permit => 1 };
  }

  if ($k eq 'match') {
    # expressions use different syntax in ISC and KEA; only an expression
    # given in KEA syntax can be used
    return { test => $st->{kea_test} } if (defined $st->{kea_test});
    return { error => "class expression needs translation: $st->{expr}" };
  }

  return { error => "no KEA equivalent: " .
	     (defined $st->{text} ? $st->{text} : $k) };
}

# kea_option_to_statement($opt,$family,$custom) - convert KEA option-data
# element into an option statement; options that cannot be expressed in
# ISC syntax are marked fmt = DHCP_FMT_KEA (KEA only)
sub kea_option_to_statement($$;$) {
  my ($opt,$family,$custom) = @_;
  my ($def,$st,$data,@items);

  $family = _family($family);
  $st = { kind => 'option', fmt => DHCP_FMT_BOTH, family => $family,
	  kea => { %$opt } };
  $st->{'always-send'} = 1 if ($opt->{'always-send'});

  if (!_std_space($opt->{space})) {
    $def = dhcp_option_def($family,'kea',"$opt->{space}.$opt->{name}",$custom)
      if (defined $opt->{name});
    $def = dhcp_option_def($family,'code',"$opt->{space}.$opt->{code}",$custom)
      if (!$def && defined $opt->{code});
  }
  else {
    $def = dhcp_option_def($family,'kea',$opt->{name},$custom)
      if (defined $opt->{name});
    $def = dhcp_option_def($family,'code',$opt->{code},$custom)
      if (!$def && defined $opt->{code});
  }

  unless ($def) {
    $st->{name} = (defined $opt->{name} ? $opt->{name} : "code-$opt->{code}");
    $st->{raw} = (defined $opt->{data} ? $opt->{data} : '');
    $st->{fmt} = DHCP_FMT_KEA;
    return $st;
  }

  $st->{def} = $def;
  $st->{name} = $def->{isc};
  $data = (defined $opt->{data} ? $opt->{data} : '');

  my $hex = 0;
  if (defined $opt->{'csv-format'} && !$opt->{'csv-format'}) {
    # raw hex payload; only binary/string options can be expressed in ISC
    if (_isc_literal_type($def->{type})) {
      @items = ($data);
      $hex = 1;
    } else {
      $st->{raw} = $data;
      $st->{fmt} = DHCP_FMT_KEA;
      return $st;
    }
  }
  else {
    if ($def->{array}) {
      @items = _split_kea_list($data);
    } else {
      (my $tmp = $data) =~ s/\\,/,/g;
      @items = ($tmp);
    }
  }

  if ($def->{type} eq 'string' && !$hex) {
    @items = map { _quote($_) } @items;
  }
  elsif (_isc_literal_type($def->{type})) {
    @items = map { _binary_to_isc($_) } @items;
    if (grep { !defined $_ } @items) {
      $st->{raw} = $data;
      $st->{fmt} = DHCP_FMT_KEA;
      return $st;
    }
  }
  $st->{values} = \@items;
  return $st;
}

# kea_param_merge($key,$old,$new) - value of KEA parameter $key set again
# in the same or an inner scope: 'dhcp-ddns' objects are merged member by
# member (enable-updates from ddns-update-style next to the connection
# settings of a KEA only entry), anything else is replaced
sub kea_param_merge($$$) {
  my ($key,$old,$new) = @_;

  return { %$old, %$new }
    if ($key eq 'dhcp-ddns' && ref($old) eq 'HASH' && ref($new) eq 'HASH');
  return $new;
}

# kea_option_def_to_statement($odef,$family) - convert KEA option-def
# element into an 'option-def' statement; definitions that ISC cannot
# express (records, tuples, ...) are kept KEA only
sub kea_option_def_to_statement($$) {
  my ($odef,$family) = @_;
  my ($st,$type,$isc_type,$space,$name);

  $family = _family($family);
  $space = (defined $odef->{space} ? $odef->{space}
				  : ($family == 6 ? 'dhcp6' : 'dhcp4'));
  $name = (_std_space($space) ? $odef->{name} : "$space.$odef->{name}");
  $st = { kind => 'option-def', fmt => DHCP_FMT_BOTH, family => $family,
	  name => $name, code => $odef->{code}, space => $space };

  $type = (defined $odef->{type} ? $_KEA2TYPE{$odef->{type}} : undef);
  if (!$type || (defined $odef->{'record-types'} && $odef->{'record-types'} ne '')
      || (defined $odef->{encapsulate} && $odef->{encapsulate} ne '')) {
    $st->{kea} = { %$odef };
    $st->{fmt} = DHCP_FMT_KEA;
    return $st;
  }

  if ($odef->{array}) {
    $isc_type = ($type eq 'fqdn' ? 'domain-list' : "array of $_TYPE2ISC{$type}");
  } else {
    $isc_type = $_TYPE2ISC{$type};
  }
  $st->{isc_type} = $isc_type;
  return $st;
}

# kea_param_to_statement($key,$value,$family) - convert KEA scope
# parameter; parameters without ISC equivalent become kind 'kea'
# (fmt = DHCP_FMT_KEA) so that they survive the import
sub kea_param_to_statement($$$) {
  my ($key,$value,$family) = @_;
  my $def = dhcp_param_def('kea',$key,$family);
  my $st = { family => _family($family) };

  if ($def && (!ref($value) || ref($value) eq 'JSON::PP::Boolean')) {
    my $v = $value;
    $v = ($value ? 1 : 0) if ($def->{type} =~ /^(flag|onoff)$/);
    $v = ($value ? 'ignore' : 'allow') if ($def->{type} eq 'clientupd');
    @$st{qw(kind name value def fmt)} = ('param',$def->{isc},$v,$def,DHCP_FMT_BOTH);
    return $st;
  }

  @$st{qw(kind key value fmt)} = ('kea',$key,$value,DHCP_FMT_KEA);
  return $st;
}


###########################################################################
# KEA only statements in the database (dhcp_entries.fmt = DHCP_FMT_KEA)
#
# The dhcp column holds a JSON object with one member:
#   {"option-data": {...}}   option-data element
#   {"option-def": {...}}    option-def element
#   {"test": "expr"}         client class test expression
#   {"<param>": value}       any other scope parameter

my $_JSON = JSON::PP->new->canonical(1)->allow_nonref(1);

# kea_statement_to_json($stmt) - database text of a KEA only statement,
# undef for statements that are not KEA only
sub kea_statement_to_json($) {
  my ($st) = @_;
  my $k = $st->{kind};

  return undef unless ($st->{fmt} && $st->{fmt} == DHCP_FMT_KEA);
  return $_JSON->encode({ $st->{key} => $st->{value} }) if ($k eq 'kea');
  return $_JSON->encode({ 'option-data' => $st->{kea} })
    if ($k eq 'option' && $st->{kea});
  return $_JSON->encode({ 'option-def' => $st->{kea} })
    if ($k eq 'option-def' && $st->{kea});
  return $_JSON->encode({ test => $st->{kea_test} })
    if ($k eq 'match' && defined $st->{kea_test});
  return undef;
}

# kea_json_to_statement($text,$family) - KEA only statement from database
# text; invalid text gives a 'raw' statement with 'error' set
sub kea_json_to_statement($$) {
  my ($text,$family) = @_;
  my ($h,$key,$val);
  my $st = { fmt => DHCP_FMT_KEA, family => _family($family), json => $text };

  $h = eval { $_JSON->decode(defined $text ? $text : '') };
  unless ($h && ref($h) eq 'HASH' && keys(%$h) == 1) {
    @$st{qw(kind error)} = ('raw',"invalid KEA entry (expected JSON object " .
			    "with one member): " . (defined $text ? $text : ''));
    return $st;
  }
  ($key) = keys %$h;
  $val = $h->{$key};

  if ($key eq 'option-data' && ref($val) eq 'HASH') {
    @$st{qw(kind kea)} = ('option',$val);
    $st->{name} = (defined $val->{name} ? $val->{name} : "code-" .
		   (defined $val->{code} ? $val->{code} : '?'));
  }
  elsif ($key eq 'option-def' && ref($val) eq 'HASH') {
    @$st{qw(kind kea name)} = ('option-def',$val,$val->{name});
  }
  elsif ($key eq 'test' && !ref($val)) {
    @$st{qw(kind kea_test)} = ('match',$val);
  }
  else {
    @$st{qw(kind key value)} = ('kea',$key,$val);
  }
  return $st;
}


# dhcp_entry_check($text,$fmt,$family) - validate a DHCP entry as stored
# in dhcp_entries (ISC statement or KEA JSON, see fmt)
# returns ($error,$warning): an error rejects the entry, a warning only
# informs (e.g. an ISC statement that has no KEA equivalent)
sub dhcp_entry_check($$$) {
  my ($text,$fmt,$family) = @_;
  my ($st,$r);

  $text = '' unless (defined $text);
  $fmt = 0 unless (defined $fmt && $fmt ne '');
  return ("invalid format '$fmt'",'') unless ($fmt =~ /^[012]$/);

  if ($fmt == DHCP_FMT_KEA) {
    $st = kea_json_to_statement($text,$family);
    return ($st->{error},'') if ($st->{error});
    return ('','');
  }
  return ("looks like a KEA entry (JSON), set the format to KEA only",'')
    if ($text =~ /^\s*\{.*\}\s*$/s);
  return ('','') if ($fmt == DHCP_FMT_ISC);

  # ISC + KEA: report what the KEA export cannot use; names in address
  # options are resolved at export time
  $st = parse_isc_statement($text,$family);
  $r = isc_statement_to_kea($st,sub { $family && $family == 6 ? '2001:db8::1'
						    : '192.0.2.1' });
  return ('','') unless ($r->{error});
  return ('',"no KEA equivalent, used for ISC only " .
	  "(set the format to ISC only to confirm)")
    if ($st->{fmt} && $st->{fmt} == DHCP_FMT_ISC);
  return ('',"not converted to KEA: $r->{error}");
}

1;
# eof
