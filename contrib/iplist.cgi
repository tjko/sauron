#!/usr/bin/perl -I/usr/local/sauron
#
# iplist.cgi -- simple CGI wrapper for export-ip-list command
#
# arguments:  mask  = regexp     # defines which (sub)nets to list
#             verbose = (1|0)    # toggle verbose output
#             optimize = (1|0)   # toggle IP optimization
#             netsonly = (1|0)   # toggle listing only (sub)nets
#
# example: http://your.server/cgi-bin/iplist.cgi?mask=^foo
#
# $Id$
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2004.
# All Rights Reserved.
#
use CGI qw/:standard *table -no_xhtml/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff

$CGI::DISABLE_UPLOADS = 1; # no uploads
$CGI::POST_MAX = 10000; # max 10k posts

my ($PG_DIR,$PG_NAME) = ($0 =~ /^(.*\/)(.*)$/);
$0 = $PG_NAME;


$PROGRAM='/opt/sauron/export-ip-list';
$SERVER='jyu';
$OPTIMIZE=1;
$VERBOSE=1;
$NETSONLY=0;


$mask=param('mask');
$server=(param('server') ? param('server') : $SERVER);
$verbose=(defined(param('verbose')) ? param('verbose') : $VERBOSE);
$optimize=(defined(param('optimize')) ? param('optimize') : $OPTIMIZE);
$netsonly=(defined(param('netsonly')) ? param('netsonly') : $NETSONLY);

exit(-1) unless (-x $PROGRAM);

print header(-charset=>'iso-8859-1',-type=>'text/plain');

push @args, $PROGRAM;
push @args, '--verbose'  if ($verbose);
push @args, '--optimize' if ($optimize);
push @args, '--netsonly' if ($netsonly);
push @args, $server;
push @args, $mask;

$res=system(@args);
print "# error=$res\n" if ($res);

# eof

