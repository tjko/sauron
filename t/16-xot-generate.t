#!/usr/bin/perl
# t/16-xot-generate.t - DNS Zone Transfer over TLS (XoT, RFC 9103) support
#
# Exercises the XoT data layer end-to-end against a live PostgreSQL DB:
#   - tls_profiles CRUD (add/get/update/delete + list)
#   - new XoT columns on servers/zones load through get_server/get_zone
#   - per-master port/TLS-profile columns used by the named.conf generator
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/16-xot-generate.t
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

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run XoT DB integration tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('xot-test');

# Throwaway server + slave zone for an isolated test.
my $srvid = 900001;
my $zoneid = 900002;
db_exec("DELETE FROM cidr_entries WHERE ref IN ($srvid,$zoneid)");
db_exec("DELETE FROM zones WHERE id=$zoneid");
db_exec("DELETE FROM servers WHERE id=$srvid");
db_exec("DELETE FROM tls_profiles WHERE ref=$srvid");
db_exec("INSERT INTO servers (id,name,tls_listen_profile,tls_listen_port,".
        "tls_default_profile) VALUES ($srvid,'xot-test-srv','xfr','853','xfr')");
db_exec("INSERT INTO zones (id,server,type,name,xot_transfer,tls_profile) ".
        "VALUES ($zoneid,$srvid,'S','xot.example.','Y','xfr')");

# ---------------------------------------------------------------------------
subtest 'tls_profiles CRUD' => sub {
    my %p = (
      ref=>$srvid, type=>1, name=>'xfr',
      cert_file=>'/etc/bind/tls/xfr.pem', key_file=>'/etc/bind/tls/xfr.key',
      ca_file=>'/etc/bind/tls/ca.pem', protocols=>'TLSv1.2 TLSv1.3',
      ciphers=>'HIGH:!aNULL', prefer_server_ciphers=>'Y',
      session_tickets=>'N', remote_hostname=>'primary.example.',
      comment=>'xot test',
    );
    my $id = add_tls_profile(\%p);
    ok($id > 0, "add_tls_profile returns id");

    my %g;
    is(get_tls_profile($id,\%g), 0, "get_tls_profile ok");
    is($g{name}, 'xfr', "name round-trips");
    is($g{cert_file}, '/etc/bind/tls/xfr.pem', "cert_file round-trips");
    is($g{protocols}, 'TLSv1.2 TLSv1.3', "protocols round-trips");
    is($g{prefer_server_ciphers}, 'Y', "prefer_server_ciphers round-trips");

    $g{ciphers} = 'HIGH:!aNULL:!MD5';
    ok(update_tls_profile(\%g) >= 0, "update_tls_profile ok");
    my %g2; get_tls_profile($id,\%g2);
    is($g2{ciphers}, 'HIGH:!aNULL:!MD5', "updated ciphers persisted");

    my (@lst,%lh); get_tls_profile_list($srvid,\%lh,\@lst);
    ok((grep { $_ eq 'xfr' } @lst) > 0, "get_tls_profile_list contains profile");

    ok(delete_tls_profile($id) >= 0, "delete_tls_profile ok");
    my %gone;
    isnt(get_tls_profile($id,\%gone), 0, "profile gone after delete");
};

# ---------------------------------------------------------------------------
subtest 'server XoT fields load' => sub {
    my %srv;
    is(get_server($srvid,\%srv), 0, "get_server ok");
    is($srv{tls_listen_profile}, 'xfr', "tls_listen_profile loaded");
    is($srv{tls_listen_port}, '853', "tls_listen_port loaded");
    is($srv{tls_default_profile}, 'xfr', "tls_default_profile loaded");
};

# ---------------------------------------------------------------------------
subtest 'zone XoT fields + masters with port/TLS' => sub {
    # add a master (primaries) entry over TLS through the BackEnd
    my %zone;
    is(get_zone($zoneid,\%zone), 0, "get_zone ok");
    is($zone{xot_transfer}, 'Y', "xot_transfer loaded");
    is($zone{tls_profile}, 'xfr', "zone tls_profile loaded");

    # masters array: [header, [id,ip,port,tls,comment,flag(add=2)]]
    $zone{masters} = [
        ['IP','Port','TLS profile','Comments'],
        [0,'192.0.2.53',853,'xfr','primary',2],
    ];
    ok(update_zone(\%zone) >= 0, "update_zone with XoT master ok");

    # the exact query the generator uses for the masters{} block
    my @m;
    db_query("SELECT ip,port,tls FROM cidr_entries WHERE type=3 AND ".
             "ref=$zoneid ORDER BY ip",\@m);
    is(scalar(@m), 1, "one master row stored");
    is($m[0][1], 853, "master port stored");
    is($m[0][2], 'xfr', "master TLS profile stored");

    # reload through get_zone (count index 5: id,ip,port,tls,comment + flag)
    my %z2; get_zone($zoneid,\%z2);
    my $row = $z2{masters}[1];
    # ip is a CIDR column, so it comes back as 192.0.2.53/32 (the generator
    # strips the /32); accept either form.
    like($row->[1], qr{^192\.0\.2\.53(/32)?$}, "get_zone master ip");
    is($row->[2], 853, "get_zone master port");
    is($row->[3], 'xfr', "get_zone master TLS profile");
};

# cleanup
db_exec("DELETE FROM cidr_entries WHERE ref IN ($srvid,$zoneid)");
db_exec("DELETE FROM zones WHERE id=$zoneid");
db_exec("DELETE FROM servers WHERE id=$srvid");
db_exec("DELETE FROM tls_profiles WHERE ref=$srvid");

done_testing();
