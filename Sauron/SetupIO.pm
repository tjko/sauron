# Sauron::SetupIO.pm - Setup input/output charset
#
# Copyright (c) Michal Svamberg <svamberg@cesnet.cz> 2025.
# Copyright (c) Michal Kostenec <kostenec@civ.zcu.cz> 2013-2014.
# Copyright (c) Timo Kokkonen <tjko@iki.fi> 2002.
# $Id:$
#
# About handling with charset in perl see 
# https://dev.to/drhyde/a-brief-guide-to-perl-character-encoding-if7
#
package Sauron::SetupIO;
require Exporter;
use Encode qw(decode encode);
use Encode::Locale qw($ENCODING_LOCALE); # set encoding by locale (argv, stdin/out/err)
use strict;
use vars qw($VERSION @ISA @EXPORT);

$VERSION = '$Id:$ ';

@ISA = qw(Exporter); # Inherit from Exporter
@EXPORT = qw(
             set_encoding
             encode_str
            );

# reset to actual encoding
sub set_encoding {
    # set encoding for standard filehanders
    binmode(STDIN,  ":encoding(locale)");
    binmode(STDOUT, ":encoding(locale)");
    binmode(STDERR, ":encoding(locale)");

    # decode @ARGV to perl internal representation
    @ARGV = map { decode('locale', $_) } @ARGV;

    return $ENCODING_LOCALE; # return actual LOCALE string
}

# encode to bytes (not wide chars)
sub encode_str {
    return encode('locale', shift @_);
}

1;
# eof
