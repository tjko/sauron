#!/usr/bin/perl
#
# Copyright (c) Timo Kokkonen <tjko@iki.fi>, 2000.
#
# $Id$
#
use CGI qw/:standard *table/;
use CGI::Carp 'fatalsToBrowser'; # debug stuff
$CGI::DISABLE_UPLOADS =1; # no uploads
$CGI::POST_MAX = 100000; # max 100k posts


if (-f "/etc/sauron/config") { 
  $conf_dir='/etc/sauron'; 
} 
elsif (-f "/opt/etc/sauron/config") { 
  $conf_dir='/opt/etc/sauron'; 
} 
elsif (-f "/usr/local/etc/sauron/config") { 
  $conf_dir='/usr/local/etc/sauron'; 
}
else {
  print STDERR "cannot find configuration file!\n";
  exit(-1);
}

do "$conf_dir/config" || error("cannot load configuration!");

do "$PROG_DIR/util.pl";
do "$PROG_DIR/db.pl";
do "$PROG_DIR/back_end.pl";

#####################################################################

$frame_mode=0;
$pathinfo = path_info();
$script_name = script_name();

if ($pathinfo ne '') {
  frame_set() if ($pathinfo eq '/frames');
  frame_1() if ($pathinfo eq '/frame1');
  frame_2() if ($pathinfo eq '/frame2');
  $frame_mode=1 if ($pathinfo eq '/frame3');
}



print header();
print start_html("Sauron $VER");

top_menu() if (! $frame_mode);

print h1("foo");
print "script name: " . script_name() ." $formmode\n";
print "extra path: " . path_info() ." framemode=$frame_mode\n";
print end_html();



#####################################################################

sub top_menu() {
  print '<TABLE bgcolor=WHITE border="0" cellspacing="0" width="100%">' .
        '<TR align="left"><TD>' . 
	'<IMG src="' .$ICON_PATH . '/logo.png" alt="">';

  print "<TD>foo<TD>foo<TD>foo";
  print "</TABLE>";
}

sub frame_set() {
  print header;
  print "<HTML><FRAMESET rows=\"130,*\">\n" .
        "  <FRAME src=\"frame1\" name=\"topmenu\" noresize>\n" .
        "  <FRAMESET cols=\"15%,85%\">\n" .
	"    <FRAME src=\"frame2\" name=\"menu\" noresize>\n" .
        "    <FRAME src=\"frame3\" name=\"main\" noresize>\n" .
        "  </FRAMESET>\n" .
        "  <NOFRAMES>\n" .
        "    Frame free version available \n" .
	"      <A HREF=\"$script_name\">here</A> \n" .
        "  </NOFRAMES>\n" .
        "</FRAMESET></HTML>\n";
  exit 0;
}

sub frame_1() {
  print header,
        start_html(-title=>"sauron: top menu",-BGCOLOR=>'white');

  top_menu();

  print end_html();
  exit 0;
}

sub frame_2() {
  print header,
        start_html("sauron: left menu");

  print h1("Menu");

  print end_html();
  exit 0;
}

#####################################################################
sub error($) {
  my($msg)=@_;
  
  print header,
        start_html("sauron: error"),
        h1("Error: $msg"),
        end_html();
  exit;
}
