# sample.pm -- sample sauron CGI interface plugin
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>  2003.
# $Id:$
#

package Sauron::Plugins::sample;

require Exporter;
use CGI qw/:standard *table -utf8/;
use Sauron::DB;
use Sauron::CGIutil;
use Sauron::BackEnd;
use Sauron::Sauron;
use Sauron::CGI::Utils;
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
	    );


###########################################################################


sub menu_handler {
  my($state,$perms) = @_;

  my $selfurl = $state->{selfurl};
  my $serverid = $state->{serverid};
  my $zoneid = $state->{zoneid};
  my $sub = param('sub');

  my (%user,@data,$i);

  if (get_user($state->{user},\%user) < 0) {
      fatal("Cannot get user record!");
  };




  if ($sub eq 'DBstatus') {
    print h3("Database status");

    db_query("SELECT s.name,COUNT(h.id) FROM servers s, zones z, hosts h " .
	   "WHERE s.id=z.server AND z.id=h.zone " .
	   "GROUP BY s.name",\@data);

    print h4("Hosts (aliases, etc.) by server"),
          "<table border=1>",Tr(th("Server"),th("Hosts"));
    for $i (0..$#data) { print Tr(td($data[$i][0]),td($data[$i][1])); }
    print "</table>";


    db_query("SELECT s.name,COUNT(a.id) FROM servers s, zones z, hosts h, " .
	     " a_entries a " .
	     "WHERE s.id=z.server AND z.id=h.zone AND h.id=a.host " .
	     "GROUP BY s.name",\@data);

    print h4("A records by server"),
          "<table border=1>",Tr(th("Server"),th("A records"));
    for $i (0..$#data) { print Tr(td($data[$i][0]),td($data[$i][1])); }
    print "</table>";
  }

}


1;
# eof :-)


