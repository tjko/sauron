# Sauron::Sauron.pm -- configuration file parsing and default settings
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id$
#
package Sauron::Sauron;
require Exporter;

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	     load_config
	    );

use strict;
use Sauron::Util;

sub set_defaults() {
  $main::SAURON_CHARSET='iso-8859-1';
  $main::SAURON_PWD_MODE = 1;
  $main::SAURON_DHCP2_MODE = 0;
  $main::SAURON_MAILER_ARGS = '';
  $main::SAURON_REMOVE_EXPIRED_DELAY = 30;
  $main::SAURON_PING_TIMEOUT = 15;
  $main::SAURON_TRACEROUTE_TIMEOUT = 15;
  $main::SAURON_SECURE_COOKIES = 0;
  $main::SAURON_USER_TIMEOUT = 3600;
  $main::SAURON_ICON_PATH = '/sauron/icons';
  $main::SAURON_BGCOLOR = 'white';
  $main::SAURON_FGCOLOR = 'black';

  $main::SAURON_RHF{huser}    = 0; # User
  $main::SAURON_RHF{dept}     = 0; # Dept.
  $main::SAURON_RHF{location} = 0; # Location
  $main::SAURON_RHF{info}     = 1; # [Extra] Info
  $main::SAURON_RHF{ether}    = 0; # Ether
  $main::SAURON_RHF{asset_id} = 1; # Asset ID
  $main::SAURON_RHF{model}    = 1; # Model
  $main::SAURON_RHF{serial}   = 1; # Serial
  $main::SAURON_RHF{misc}     = 1; # Misc.

  $main::ALEVEL_VLANS = 5;
  $main::ALEVEL_RESERVATIONS = 1;
  $main::ALEVEL_PING = 1;
  $main::ALEVEL_TRACEROUTE = 1;
  $main::ALEVEL_HISTORY = 1;

  $main::LOOPBACK_NET = '127.0.0.0/8';
  $main::LOOPBACK_ZONE = 'loopback.';
}

sub load_config() {
  my($file,$ret);

  set_defaults();

  if (-f "/etc/sauron/config") {
    $file="/etc/sauron/config";
  }
  elsif (-f "/usr/local/etc/sauron/config") {
    $file="/usr/local/etc/sauron/config";
  }
  elsif (-f "/opt/sauron/etc/config") {
    $file="/opt/sauron/etc/config";
  }
  else {
    fatal("cannot find configuration file!");
  }

  fatal("cannot read configuration file: $file") unless (-r $file);

  { package main; $ret = do "$file";
    fatal("parse error in configuration file: $file") if $@;
    fatal("failed to access configuration file: $file") unless defined $ret;
    fatal("failed to run configuration file: $file") unless $ret;
  }

  fatal("DB_CONNECT not set in configuration file") unless ($main::DB_CONNECT);
  fatal("SERVER_ID not set in configuration file") unless ($main::SERVER_ID);
  fatal("PROG_DIR not set in configuration file") unless ($main::PROG_DIR);
  fatal("LOG_DIR not set in configuration file") unless ($main::LOG_DIR);

  return 0;
}


1;
# eof
