# Sauron::Sauron.pm -- configuration file parsing and default settings
#
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003-2007.
# $Id:$
#
package Sauron::Sauron;
require Exporter;
use Sauron::Util;
use MIME::Base64 qw(decode_base64);
use strict;
use vars qw($VERSION $CONF_FILE_PATH @ISA @EXPORT);

$VERSION = '$Id:$ ';
$CONF_FILE_PATH = '__CONF_FILE_PATH__';


@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     load_config
	     load_browser_config
	     logmsg
	     sauron_version
	     print_config
	     print_browser_config
	    );

# A hack adapted from following page, mesrik - 2024
# - https://stackoverflow.com/questions/627661/how-can-i-output-utf-8-from-perl
binmode(STDOUT, ":utf8");          #treat as if it is UTF-8
binmode(STDIN, ":encoding(utf8)"); #actually check if it is UTF-8

sub sauron_version() {
  return "0.8.5"; # current Sauron version
}


sub set_defaults() {
  undef $main::CONFIG_FILE;

  undef $main::PROG_DIR;
  undef $main::LOG_DIR;
  undef $main::DB_DSN;
  undef $main::DB_USER;
  undef $main::DB_PASSWORD;
  undef $main::SERVER_ID;

  $main::SAURON_DEBUG_MODE = 0;
  $main::SAURON_PRIVILEGE_MODE = 0;
  $main::SAURON_CHARSET='iso-8859-1';
  $main::SAURON_PWD_MODE = 1;
  $main::SAURON_DHCP2_MODE = 0;
  $main::SAURON_MAIL_FROM = '';
  undef $main::SAURON_MAILER;
  $main::SAURON_MAILER_ARGS = '';
  $main::SAURON_REMOVE_EXPIRED_DELAY = 30;
  undef $main::SAURON_PING_PROG;
  $main::SAURON_PING_ARGS = '';
  $main::SAURON_PING_TIMEOUT = 15;
  undef $main::SAURON_TRACEROUTE_PROG;
  $main::SAURON_TRACEROUTE_ARGS = '';
  $main::SAURON_TRACEROUTE_TIMEOUT = 15;
  undef $main::SAURON_NMAP_PROG;
  $main::SAURON_NMAP_ARGS = '';
  $main::SAURON_NMAP_TIMEOUT = 30;
  $main::SAURON_SECURE_COOKIES = 0;
  $main::SAURON_USER_TIMEOUT = 3600;
  $main::SAURON_DTD_HACK = 0;
  $main::SAURON_ICON_PATH = '/sauron/icons';
  $main::SAURON_BGCOLOR = 'white';
  $main::SAURON_FGCOLOR = 'black';
  $main::SAURON_AUTH_MODE = 0;
  $main::SAURON_AUTH_PROG = '';
  $main::SAURON_DHCP_CHK_PROG = '';
  $main::SAURON_DHCP_CHK_ARGS  = '-4 -q -t -cf';
  $main::SAURON_DHCP6_CHK_ARGS = '-6 -q -t -cf';
  $main::SAURON_NAMED_CHK_PROG = '';
  $main::SAURON_NAMED_CHK_ARGS = '';
  $main::SAURON_ZONE_CHK_PROG = '';
  $main::SAURON_ZONE_CHK_ARGS = '-q';
  $main::SAURON_NO_REMOTE_ADDR_AUTH = 0;
  $main::SAURON_HINFO_MODE = 1;
  $main::SAURON_PLUGINS = '';
  $main::SAURON_KEY = '';
  $main::SAURON_DNSSEC_KEYGEN_PROG = '';
  $main::SAURON_DNSSEC_KEYGEN_ARGS = '';
# $main::SAURON_DNSNAME_CHECK_MODE = 0;    # Replaced 2020-10-12 TVu
  $main::SAURON_DNSNAME_CHECK_LEVEL = 999; # 2020-10-12 TVu
  $main::SAURON_TEMP_LOCK = 0;             # 2020-10-13 TVu
  $main::SAURON_REMOVE_WHITESPACE = 0;     # 2020-10-13 TVu
  $main::TTL_MIN_SEC = 600;                # 2021-02-11 TVu
  $main::TTL_MAX_SEC = 86400;              # 2021-02-11 TVu

  $main::SAURON_RHF{huser}    = 0; # User
  $main::SAURON_RHF{dept}     = 0; # Dept.
  $main::SAURON_RHF{location} = 0; # Location
  $main::SAURON_RHF{info}     = 1; # [Extra] Info
  $main::SAURON_RHF{ether}    = 0; # Ether
  $main::SAURON_RHF{asset_id} = 1; # Asset ID
  $main::SAURON_RHF{model}    = 1; # Model
  $main::SAURON_RHF{serial}   = 1; # Serial
  $main::SAURON_RHF{misc}     = 1; # Misc.
  $main::SAURON_RHF{email}    = 1; # User Email

  $main::ALEVEL_VLANS = 5;
  $main::ALEVEL_ACLS = 5;
  $main::ALEVEL_RESERVATIONS = 1;
  $main::ALEVEL_PING = 1;
  $main::ALEVEL_TRACEROUTE = 1;
  $main::ALEVEL_HISTORY = 1;
  $main::ALEVEL_HISTORY_SEARCH = 3;         # 2020-10-13 TVu
  $main::ALEVEL_SHOW_UNALLOCATED_CIDRS = 3; # 2020-10-13 TVu

  $main::LOOPBACK_NET = '127.0.0.0/8';
  $main::LOOPBACK_ZONE = 'loopback.';
}


sub print_config() {
  print "PROG_DIR=",$main::PROG_DIR,"\n";
  print "LOG_DIR=",$main::LOG_DIR,"\n";
  print "DB_DSN=",$main::DB_DSN,"\n";
  print "DB_USER=",$main::DB_USER,"\n";
  print "DB_PASSWORD=",$main::DB_PASSWORD,"\n";
  print "SERVER_ID=",$main::SERVER_ID,"\n";

  print "SAURON_KEY=".($main::SAURON_KEY ?
		       "<".(length($main::SAURON_KEY)*8)." bit key defined>" :
		       "<undefined>")."\n";
  print "SAURON_DEBUG_MODE=",$main::SAURON_DEBUG_MODE,"\n";
  print "SAURON_PRIVILEGE_MODE=",$main::SAURON_PRIVILEGE_MODE,"\n";
  print "SAURON_CHARSET=",$main::SAURON_CHARSET,"\n";
  print "SAURON_PWD_MODE=",$main::SAURON_PWD_MODE,"\n";
  print "SAURON_DHCP2_MODE=",$main::SAURON_DHCP2_MODE,"\n";
  print "SAURON_MAIL_FROM=",$main::SAURON_MAIL_FROM,"\n";
  print "SAURON_MAILER=",$main::SAURON_MAILER,"\n";
  print "SAURON_MAILER_ARGS=",$main::SAURON_MAILER_ARGS,"\n";
  print "SAURON_REMOVE_EXPIRE_DELAY=",$main::SAURON_REMOVE_EXPIRED_DELAY,"\n";
  print "SAURON_PING_PROG=",$main::SAURON_PING_PROG,"\n";
  print "SAURON_PING_ARGS=",$main::SAURON_PING_ARGS,"\n";
  print "SAURON_PING_TIMEOUT=",$main::SAURON_PING_TIMEOUT,"\n";
  print "SAURON_TRACEROUTE_PROG=",$main::SAURON_TRACEROUTE_PROG,"\n";
  print "SAURON_TRACEROUTE_ARGS=",$main::SAURON_TRACEROUTE_ARGS,"\n";
  print "SAURON_TRACEROUTE_TIMEOUT=",$main::SAURON_TRACEROUTE_TIMEOUT,"\n";
  print "SAURON_NMAP_PROG=",$main::SAURON_NMAP_PROG,"\n";
  print "SAURON_NMAP_ARGS=",$main::SAURON_NMAP_ARGS,"\n";
  print "SAURON_NMAP_TIMEOUT=",$main::SAURON_NMAP_TIMEOUT,"\n";
  print "SAURON_SECURE_COOKIES=",$main::SAURON_SECURE_COOKIES,"\n";
  print "SAURON_USER_TIMEOUT=",$main::SAURON_USER_TIMEOUT,"\n";
  print "SAURON_DTD_HACK=",$main::SAURON_DTD_HACK,"\n";
  print "SAURON_ICON_PATH=",$main::SAURON_ICON_PATH,"\n";
  print "SAURON_BGCOLOR=",$main::SAURON_BGCOLOR,"\n";
  print "SAURON_FGCOLOR=",$main::SAURON_FGCOLOR,"\n";
  print "SAURON_AUTH_MODE=",$main::SAURON_AUTH_MODE,"\n";
  print "SAURON_AUTH_PROG=",$main::SAURON_AUTH_PROG,"\n";
  print "SAURON_DHCP_CHK_PROG=",$main::SAURON_DHCP_CHK_PROG,"\n";
  print "SAURON_DHCP_CHK_ARGS=",$main::SAURON_DHCP_CHK_ARGS,"\n";
  print "SAURON_DHCP6_CHK_PROG=",$main::SAURON_DHCP6_CHK_PROG,"\n";
  print "SAURON_DHCP6_CHK_ARGS=",$main::SAURON_DHCP6_CHK_ARGS,"\n";
  print "SAURON_NAMED_CHK_PROG=",$main::SAURON_NAMED_CHK_PROG,"\n";
  print "SAURON_NAMED_CHK_ARGS=",$main::SAURON_NAMED_CHK_ARGS,"\n";
  print "SAURON_ZONE_CHK_PROG=",$main::SAURON_ZONE_CHK_PROG,"\n";
  print "SAURON_ZONE_CHK_ARGS=",$main::SAURON_ZONE_CHK_ARGS,"\n";
  print "SAURON_DNSSEC_KEYGEN_PROG=",$main::SAURON_DNSSEC_KEYGEN_PROG,"\n";
  print "SAURON_DNSSEC_KEYGEN_ARGS=",$main::SAURON_DNSSEC_KEYGEN_ARGS,"\n";
  print "SAURON_NO_REMOTE_ADDR_AUTH=",$main::SAURON_NO_REMOTE_ADDR_AUTH,"\n";
  print "SAURON_HINFO_MODE=",$main::SAURON_HINFO_MODE,"\n";
  print "SAURON_DNSNAME_CHECK_MODE=",$main::SAURON_DNSNAME_CHECK_MODE,"\n";
  print "SAURON_PLUGINS='",$main::SAURON_PLUGINS,"'\n";

  print "ALEVEL_VLANS=",$main::ALEVEL_VLANS,"\n";
  print "ALEVEL_ACLS=",$main::ALEVEL_ACLS,"\n";
  print "ALEVEL_RESERVATIONS=",$main::ALEVEL_RESERVATIONS,"\n";
  print "ALEVEL_PING=",$main::ALEVEL_PING,"\n";
  print "ALEVEL_TRACEROUTE=",$main::ALEVEL_TRACEROUTE,"\n";
  print "ALEVEL_HISTORY=",$main::ALEVEL_HISTORY,"\n";

  print "LOOPBACK_NET=",$main::LOOPBACK_NET,"\n";
  print "LOOPBACK_ZONE=",$main::LOOPBACK_ZONE,"\n";
}


sub load_config_file($$) {
  my($cfile,$modemask)=@_;
  my($file,$ret);

  fatal("internal error in load_config_file(): file not specified")
      unless ($cfile);
  $modemask=0 unless ($modemask);

  if ( ($cfile =~ /^\//) && -f $cfile ) {
      $file=$cfile;
  }
  elsif ( ($CONF_FILE_PATH !~ /^__CONF_FILE_PATH/) &&
       -f "$CONF_FILE_PATH/$cfile" ) {
      $file="$CONF_FILE_PATH/$cfile";
  }
  elsif (-f "/etc/sauron/$cfile") {
      $file="/etc/sauron/$cfile";
  }
  elsif (-f "/usr/local/etc/sauron/$cfile") {
      $file="/usr/local/etc/sauron/$cfile";
  }
  elsif (-f "/opt/sauron/etc/$cfile") {
      $file="/opt/sauron/etc/$cfile";
  }
  else {
      fatal("cannot find configuration file: $cfile");
  }

  fatal("cannot read configuration file: $file") unless (-r $file);

  my $filemode = (stat($file))[2];
  fatal("unsafe file permissions for: $file") if ($filemode & $modemask);

  # evaluate configuration file in 'main' name space...
  {
    package main;
    $ret = do "$file";
    fatal("parse error in configuration file: $file") if $@;
    fatal("failed to access configuration file: $file") unless defined $ret;
    fatal("failed to run configuration file: $file") unless $ret;
  }

  $main::CONFIG_FILE=$file;
}

# load sauron config file
sub load_config() {
  my($file,$ret,$keyfile);

  set_defaults();
  load_config_file("config",0022);

  fatal("DB_DSN not set in configuration file") unless ($main::DB_DSN);
  fatal("SERVER_ID not set in configuration file") unless ($main::SERVER_ID);
  fatal("PROG_DIR not set in configuration file") unless ($main::PROG_DIR);
  fatal("LOG_DIR not set in configuration file") unless ($main::LOG_DIR);

  $keyfile=$main::CONFIG_FILE . ".key";
  if ( -f $keyfile ) {
      my $filemode = (stat($keyfile))[2];
      fatal("unsafe file permissions for :$keyfile") if ($filemode & 0027);
      if (-r $keyfile) {
	  open(KEYFILE,"$keyfile") || fatal("failed to open: $keyfile");
	  while(<KEYFILE>) {
	      if (/^Key:\s*(\S+)\s*$/) {
		  $main::SAURON_KEY=decode_base64($1);
	      }
	  }
	  close(KEYFILE);
      }
  }

  return 0;
}


sub print_browser_config()  {
  print "BROWSER_MAX=",$main::BROWSER_MAX,"\n";
  print "BROWSER_CHARSET=",$main::BROWSER_CHARSET,"\n";
  print "BROWSER_SHOW_FIELDS=",$main::BROWSER_SHOW_FIELDS,"\n";
  print "BROWSER_HIDE_PRIVATE=",$main::BROWSER_HIDE_PRIVATE,"\n";
  print "BROWSER_HIDE_FIELDS=",$main::BROWSER_HIDE_FIELDS,"\n";
}

# load (sauron) browser config file
sub load_browser_config() {

  # set defaults
  $main::BROWSER_MAX = 100;
  $main::BROWSER_CHARSET = 'iso-8859-1';
  $main::BROWSER_SHOW_FIELDS = 'huser,location,info,dept';
  $main::BROWSER_HIDE_PRIVATE = 1;
  $main::BROWSER_HIDE_FIELDS = 'huser,location';

  load_config_file("config-browser",0022);

  fatal("DB_DSN not set in configuration file") unless ($main::DB_DSN);
  fatal("PROG_DIR not set in configuration file") unless ($main::PROG_DIR);

  return 0;
}

# add message to log file
sub logmsg($$) {
  my($type,$msg)=@_;
  my $logdir = $main::LOG_DIR;
  my $prog = $0;

  $prog = $2 if ($prog =~ /^(.*\/)(.*)$/);
  return -1 unless ($logdir);
  if ($type eq 'test') {
    return -2 unless (-d $logdir);
    return -3 unless (-w $logdir or -w "$logdir/sauron.log");
    return 0;
  }

  open(LOGFILE,">>$logdir/sauron.log") || return -4;
  print LOGFILE localtime(time) . " " . $prog . "[$$]: [".lc($type)."] $msg\n";
  close(LOGFILE);
  return 0;
}


1;
# eof
