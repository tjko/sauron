#!/usr/bin/perl
# t/07-utf8-encoding.t - Regression tests for the UTF-8 boundary model.
#
# Background: zone/host "comment" fields with diacritics were getting
# progressively corrupted on every save (e.g. "žluťoučký" -> "Å¾luÅ¥ouÄ\x8dký").
# Root cause: user data could reach the string-concatenation SQL builder
# (db_encode_str + concat) as a Perl *byte* string (raw UTF-8 octets, no
# UTF8 flag). When such a byte string is concatenated with a wide-char
# fragment, Perl reinterprets the octets as Latin-1 and DBD::Pg
# (client_encoding=UTF8) then encodes them to UTF-8 a second time -> mojibake.
#
# The fix keeps everything as Perl wide-character strings end to end:
# decode_cgi_params() decodes request params on input (CGI.pm's own
# -utf8/PARAM_UTF8 proved unreliable on the target server), DBD::Pg
# pg_enable_utf8 decodes DB reads, and a single STDOUT binmode encodes the
# response on output. The fragile fix_param_utf8() heuristic was removed.
# These tests pin down both the input-decode and the write-path invariants.
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use Encode qw(encode decode);

# Ensure DB.pm symlink exists for transitive imports
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

use Sauron::DB;

# "UTF8 TEST žluťoučký TEST" as proper Perl wide characters (what CGI -utf8
# and DBD::Pg pg_enable_utf8 hand to the rest of the code).
my $comment = "UTF8 TEST \x{17e}lu\x{165}ou\x{10d}k\x{fd} TEST";

# Bytes Postgres must end up storing for that value (UTF-8, encoded once).
my $want_bytes = encode('UTF-8', $comment);

# Bytes produced by the historical double-encode bug, for an explicit
# negative assertion ("Å¾..." = each UTF-8 octet re-encoded as Latin-1).
my $mojibake_bytes = encode('UTF-8', decode('ISO-8859-1', $want_bytes));

subtest 'db_encode_str preserves wide characters (no flag downgrade)' => sub {
    my $enc = db_encode_str($comment);
    like($enc, qr/\A'.*'\z/s, 'value is single-quoted');

    # Extract the quoted payload and confirm it is unchanged wide-char text.
    (my $payload = $enc) =~ s/\A'//; $payload =~ s/'\z//;
    is($payload, $comment, 'payload equals original wide-char string');
    ok(utf8::is_utf8($payload) || $comment !~ /[^\x00-\xff]/,
       'wide-char string keeps its UTF8 flag through db_encode_str');
};

subtest 'concatenated SQL encodes to UTF-8 exactly once' => sub {
    # Mimic BackEnd.pm: build an UPDATE by concatenating ASCII fragments with
    # the encoded user value, then let DBD::Pg (client_encoding=UTF8) encode
    # the whole statement to UTF-8.
    my $sql = "UPDATE hosts SET comment=" . db_encode_str($comment)
            . " WHERE id=42;";
    my $wire = encode('UTF-8', $sql);

    ok($wire =~ /comment='([^']*)'/, 'comment payload found on the wire');
    my $stored = $1;

    is($stored, $want_bytes, 'stored bytes are single-encoded UTF-8');
    isnt($stored, $mojibake_bytes, 'stored bytes are NOT double-encoded mojibake');
    is(decode('UTF-8', $stored), $comment, 'value round-trips back to original');
};

subtest 'save/load/save round-trip is stable (no progressive corruption)' => sub {
    # Simulate repeated edits: each cycle writes the value, reads it back the
    # way pg_enable_utf8 does (decode UTF-8 -> wide chars), and writes again.
    my $value = $comment;
    for my $cycle (1 .. 5) {
        my $sql  = "UPDATE x SET c=" . db_encode_str($value) . ";";
        my $wire = encode('UTF-8', $sql);
        ($wire =~ /c='([^']*)'/) or die "cycle $cycle: payload missing";
        my $on_disk = $1;
        $value = decode('UTF-8', $on_disk);   # pg_enable_utf8 read path
        is($value, $comment, "cycle $cycle: value unchanged after round-trip");
    }
};

subtest 'input boundary: decode_cgi_params decodes octets to wide chars' => sub {
    # The real defect: CGI.pm's -utf8/PARAM_UTF8 did NOT decode request params
    # on the target server, so user text reached the code as raw UTF-8 octets.
    # decode_cgi_params() now decodes them deterministically at the boundary.
    require Sauron::CGIutil;
    Sauron::CGIutil->import;

    ok(!Sauron::CGIutil->can('fix_param_utf8'),
       'old fix_param_utf8 heuristic is gone');
    ok(  Sauron::CGIutil->can('decode_cgi_params'),
       'decode_cgi_params is available');

    # Simulate a GET request carrying UTF-8-encoded form data (as a browser on
    # a UTF-8 page sends it), with CGI.pm doing no decoding of its own.
    my $octets = encode('UTF-8', $comment);
    my $qs = 'menu=zones&comment='
           . join('', map { sprintf('%%%02X', ord $_) } split //, $octets);
    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = $qs;
    $CGI::Q = CGI->new();   # fresh parse from %ENV for the functional interface

    isnt(scalar CGI::param('comment'), $comment,
         'raw param is undecoded octets before decode_cgi_params()');

    decode_cgi_params('utf-8');

    is(scalar CGI::param('comment'), $comment,
       'param is proper wide-char text after decode_cgi_params()');
    ok(utf8::is_utf8(scalar CGI::param('comment')),
       'decoded param carries the UTF8 flag');

    # Idempotent: a second pass must not double-decode.
    decode_cgi_params('utf-8');
    is(scalar CGI::param('comment'), $comment, 'second decode pass is a no-op');
};

subtest 'input boundary: repairs UTF8-flagged mojibake (the real defect)' => sub {
    # On the target stack CGI.pm hands back the UTF-8 octets reinterpreted as
    # Latin-1 codepoints AND with the UTF8 flag already set, e.g. "ž" (octets
    # C5 BE) arrives as the codepoints U+00C5 U+00BE ("Å¾"). A flag check would
    # wrongly skip it; decode_cgi_params() must still repair it.
    require Sauron::CGIutil;
    Sauron::CGIutil->import;

    my $mojibake = decode('ISO-8859-1', encode('UTF-8', $comment)); # octets as L1
    ok(utf8::is_utf8($mojibake), 'mojibake test value carries the UTF8 flag');
    isnt($mojibake, $comment, 'mojibake value differs from the original');

    local $ENV{REQUEST_METHOD} = 'GET';
    local $ENV{QUERY_STRING}   = 'menu=zones';
    $CGI::Q = CGI->new();
    CGI::param('comment', $mojibake);   # inject the flagged-mojibake value

    decode_cgi_params('utf-8');
    is(scalar CGI::param('comment'), $comment,
       'flagged mojibake is repaired to the original text');

    # And stable across a further pass (mirrors repeated Apply/Add round trips).
    decode_cgi_params('utf-8');
    is(scalar CGI::param('comment'), $comment, 'repair is stable / idempotent');
};

subtest 'no module re-introduces CGI -utf8 (single-authority model)' => sub {
    # decode_cgi_params() is the sole input-decoder. CGI.pm's -utf8 sets the
    # process-global $CGI::PARAM_UTF8, so a single stray import re-enables it
    # everywhere and makes the boundary model inconsistent again. Guard against
    # that drift.
    my $root = "$FindBin::Bin/..";
    my @files = (glob("$root/Sauron/*.pm"), glob("$root/Sauron/CGI/*.pm"),
                 glob("$root/cgi/*.cgi"));
    my @offenders;
    for my $f (@files) {
        open(my $fh, '<', $f) or next;
        while (my $line = <$fh>) {
            next if $line =~ /^\s*#/;
            push @offenders, $f if $line =~ /\buse\s+CGI\b.*-utf8/;
        }
        close($fh);
    }
    is_deeply(\@offenders, [], 'no use CGI ... -utf8 imports remain')
        or diag("offending files: @offenders");
};

done_testing();
