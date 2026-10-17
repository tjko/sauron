#!/usr/bin/perl
# t/23-context-bar.t - context bar after changing the server/zone selection
#
# sauron.cgi prints the context bar (Server > Zone) before the menu handler
# saves the new selection, so after a change it shows the previous one.
# The page must end with <span id="s-ctx-update"> carrying the selection the
# handler saved (sauron.js rebuilds the bar from it). Runs cgi/sauron.cgi as
# a CGI subprocess: logs in, selects a server and two zones in turn, then
# switches to another server (issue #138).
#
# Needs the installed config file (the CGI connects with its DB settings);
# skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/23-context-bar.t
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

# Ensure DB.pm symlink (mirrors t/10)
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run context bar CGI tests';
}

use Sauron::DB;
use Sauron::Util;

db_connect2() or plan skip_all => 'Cannot connect to test database';

my $cgi = "$FindBin::Bin/../cgi/sauron.cgi";

my $srvid1  = 960001;
my $srvid2  = 960002;
my $zoneid1 = 960003;
my $zoneid2 = 960004;
my $uid     = 960005;
my $user    = 'ctxbar-test';
my $pwd     = 'ctxbar-test-pwd';

sub cleanup {
    for my $sql ("DELETE FROM utmp WHERE uid=$uid",
                 "DELETE FROM lastlog WHERE uid=$uid",
                 "DELETE FROM users WHERE id=$uid",
                 "DELETE FROM zones WHERE id IN ($zoneid1,$zoneid2)",
                 "DELETE FROM servers WHERE id IN ($srvid1,$srvid2)") {
        db_exec($sql) >= 0 or diag("cleanup failed: $sql: " . db_lasterrormsg());
    }
}

# Also on BAIL_OUT/die: do not leave the test superuser behind.
my $cleanup_needed = 0;
END { local $?; cleanup() if $cleanup_needed; }

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

my $cookie = '';

# Run sauron.cgi as a GET request with the session cookie; returns the output.
sub run_cgi {
    my (%param) = @_;
    my $qs = join('&', map { "$_=$param{$_}" } sort keys %param);
    local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
    local $ENV{REQUEST_METHOD}    = 'GET';
    local $ENV{QUERY_STRING}      = $qs;
    local $ENV{HTTP_COOKIE}       = $cookie;
    local $ENV{REMOTE_ADDR}       = '127.0.0.1';
    local $ENV{SCRIPT_NAME}       = '/cgi-bin/sauron.cgi';
    local $ENV{SERVER_NAME}       = 'localhost';
    local $ENV{SERVER_PORT}       = '80';
    # Load the script with 'do': run directly, its shebang (-I/opt/sauron)
    # would put an installed tree before the one under test in @INC.
    open(my $fh, '-|', $^X, '-e',
         'unshift @INC, shift; $0 = shift; do $0; die $@ if $@;',
         "$FindBin::Bin/..", $cgi) or die "Cannot run $cgi: $!";
    local $/;
    my $out = <$fh>;
    close($fh);
    return $out // '';
}

# Selection carried by the s-ctx-update span: [server, serverid, zone, zoneid]
sub ctx_update {
    my ($out) = @_;
    $out =~ /<span id="s-ctx-update" hidden data-server="([^"]*)" data-serverid="(-?\d+)" data-zone="([^"]*)" data-zoneid="(-?\d+)"><\/span>/
        or return undef;
    return [$1, $2, $3, $4];
}

cleanup();
$cleanup_needed = 1;
setup_ok("INSERT INTO users (id,username,password,superuser) " .
         "VALUES ($uid,'$user','" . pwd_make($pwd, 0) . "',true)");
setup_ok("INSERT INTO servers (id,name) VALUES ($srvid1,'ctxbar-test1')");
setup_ok("INSERT INTO servers (id,name) VALUES ($srvid2,'ctxbar-test2')");
setup_ok("INSERT INTO zones (id,server,type,name,reverse) " .
         "VALUES ($zoneid1,$srvid1,'M','a.ctxbar.example',false)");
setup_ok("INSERT INTO zones (id,server,type,name,reverse) " .
         "VALUES ($zoneid2,$srvid1,'M','b.ctxbar.example',false)");

my $out = run_cgi();
if ($out =~ /^Set-Cookie:\s*(sauron-[^=;\s]+=[0-9A-Fa-f]+)/mi) {
    $cookie = $1;
} else {
    my ($err) = $out =~ /(Error: [^<\n]*|Can't locate \S+)/;
    plan skip_all => 'sauron.cgi did not start a session: ' .
                     ($err // 'no output (config file missing?)');
}

$out = run_cgi(login => 'yes', login_name => $user, login_pwd => $pwd);
like($out, qr/Login ok/, 'superuser login') or BAIL_OUT('cannot log in');

$out = run_cgi(menu => 'servers', server_list => $srvid1);
is_deeply(ctx_update($out), ['ctxbar-test1', $srvid1, '', -1],
          'select server 1');

$out = run_cgi(menu => 'zones', selected_zone => 'a.ctxbar.example');
is_deeply(ctx_update($out), ['ctxbar-test1', $srvid1,
                             'a.ctxbar.example', $zoneid1],
          'select zone A');

$out = run_cgi(menu => 'zones', selected_zone => 'b.ctxbar.example');
is_deeply(ctx_update($out), ['ctxbar-test1', $srvid1,
                             'b.ctxbar.example', $zoneid2],
          'select zone B after zone A');

$out = run_cgi(menu => 'servers', server_list => $srvid2);
is_deeply(ctx_update($out), ['ctxbar-test2', $srvid2, '', -1],
          'switch to server 2 clears the zone');

done_testing();
