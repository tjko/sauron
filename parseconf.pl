#!/usr/bin/perl
#
# $Id$
#

while (<>) {
    # eat extra whitespaces
    s/\s+/\ /g;
    # eat one-line comments
    s/\/\/.*$//g;
    s/#.*$//g;
    s/\/\*.*\*\///g;

    # skip blank lines
    next if /^\s*$/;

    # handle multi-line comments
    if ( /^(.*?)\/\*/ ) {
	$comment=1;
	$line = $1;
	# print "comment begin '$line'\n";
	next;
    }
    if ( $comment==1 ) {
	if ( /^.*?\*\/(.*)$/ ) {
	    # print "comment end '$1'\n";
	    $comment=0;
	    $line = $line .  $1;
	    $line =~ s/\s+/\ /g;
	    print "$line\n";
	}
	next;
    }

    if ( /{\s*\S/ ) { s/{/{\n/o; }
    if ( /;\s*\S/ ) { s/;/;\n/o; }

    print "$_\n";
}
