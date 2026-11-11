#!/usr/bin/perl
# t/30-kea-ddns.t - sauron --kea-ddns: kea-dhcp-ddns.conf from the master
#                   zones accepting dynamic updates and their TSIG keys
#
# Requires running PostgreSQL with initialized Sauron DB and installed
# Sauron. Skipped unless SAURON_TEST_DSN and SAURON_INSTALL_DIR are set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);
use MIME::Base64;
use JSON::PP;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
unless ($DB_DSN && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for E2E tests';
}

use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;

# master key next to the configuration file (as Sauron loads it)
my ($config) = grep { -f $_ } ('/etc/sauron/config', '/usr/local/etc/sauron/config',
                               '/opt/sauron/etc/config');
plan skip_all => 'Sauron configuration file not found' unless ($config);
my ($masterkey, $created_keyfile);
if (open(my $kf, '<', "$config.key")) {
    while (<$kf>) { $masterkey = decode_base64($1) if (/^Key:\s*(\S+)/); }
    close($kf);
} else {
    $masterkey = join('', map { chr(int(rand(256))) } 1..16);
    open(my $kf, '>', "$config.key") or plan skip_all => "cannot create $config.key: $!";
    print $kf "Key: " . encode_base64($masterkey, '') . "\n";
    close($kf);
    chmod(0600, "$config.key");
    $created_keyfile = 1;
}

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('kea-ddns-test');

my $server = 'kea-ddns-test';
my $tmp = tempdir(CLEANUP => 1);
sub rows {
    my @r;
    db_query($_[0], \@r);
    die(db_errormsg()) if (db_errormsg());
    return \@r;
}
sub cleanup {
    my $r = rows("SELECT id FROM servers WHERE name='$server'");
    delete_server($r->[0][0]) if (@$r);
}
cleanup();
END {
    cleanup() if (defined $server);   # set only after db_connect2()
    unlink("$config.key") if ($created_keyfile);
}

db_exec("INSERT INTO servers (name,hostname,hostmaster,hostaddr) VALUES " .
        "('$server','ns1.ddns.test.','hostmaster.ddns.test.','192.0.2.53')");
my $sid = rows("SELECT id FROM servers WHERE name='$server'")->[0][0];

my $secret = 'secret-key-12345';
my $enc = encode_base64(tsig_secret_encrypt($masterkey, $secret), '');
db_exec("INSERT INTO keys (type,ref,name,algorithm,keysize,secretkey,protocol,mode) " .
        "VALUES (1,$sid,'ddns-key',157," . (length($secret) * 8) . ",'$enc',3,0)");
my $kid = rows("SELECT id FROM keys WHERE ref=$sid AND name='ddns-key'")->[0][0];

my %zid;
db_exec("INSERT INTO keys (type,ref,name,algorithm,keysize,secretkey,protocol,mode) " .
        "VALUES (1,$sid,'old-key',157," . (length($secret) * 8) . ",'$enc',3,0)");
my $oldkid = rows("SELECT id FROM keys WHERE ref=$sid AND name='old-key'")->[0][0];
db_exec("INSERT INTO acls (server,name) VALUES ($sid,'ddns-updaters')");
my $aclid = rows("SELECT id FROM acls WHERE server=$sid AND name='ddns-updaters'")->[0][0];
db_exec("INSERT INTO cidr_entries (type,ref,mode,tkey) VALUES (0,$aclid,2,$kid)");

foreach my $z ([ 'ddns.test', 'M', 'f' ], [ 'static.test', 'M', 'f' ],
               [ '40.10.in-addr.arpa', 'M', 't' ], [ 'slave.test', 'S', 'f' ],
               [ 'acl.test', 'M', 'f' ], [ 'catalog.test', 'M', 'f' ]) {
    db_exec("INSERT INTO zones (server,name,type,reverse) VALUES ($sid,'$z->[0]','$z->[1]','$z->[2]')");
    $zid{$z->[0]} = rows("SELECT id FROM zones WHERE server=$sid AND name='$z->[0]'")->[0][0];
}
# allow-update: key for the forward zone, address for the reverse zone,
# none for static.test; a slave zone is never updated by this server
# a negated key first: never used to sign updates
db_exec("INSERT INTO cidr_entries (type,ref,mode,tkey,op) VALUES (2,$zid{'ddns.test'},2,$oldkid,1)");
db_exec("INSERT INTO cidr_entries (type,ref,mode,tkey) VALUES (2,$zid{'ddns.test'},2,$kid)");
# key through an ACL
db_exec("INSERT INTO cidr_entries (type,ref,mode,acl) VALUES (2,$zid{'acl.test'},1,$aclid)");
# catalog only zone is not served by BIND
db_exec("UPDATE zones SET catalog_only=true WHERE id=$zid{'catalog.test'}");
db_exec("INSERT INTO cidr_entries (type,ref,mode,tkey) VALUES (2,$zid{'catalog.test'},2,$kid)");
db_exec("INSERT INTO cidr_entries (type,ref,mode,ip) VALUES (2,$zid{'40.10.in-addr.arpa'},0,'127.0.0.1')");
db_exec("INSERT INTO cidr_entries (type,ref,mode,ip) VALUES (2,$zid{'slave.test'},0,'127.0.0.1')");

my $out = `$install_dir/sauron --kea-ddns $server $tmp 2>&1`;
is($? >> 8, 0, 'sauron --kea-ddns') or diag($out);
my $file = "$tmp/kea-dhcp-ddns.conf";
ok(-r $file, 'kea-dhcp-ddns.conf generated') or BAIL_OUT('no output');
is((stat($file))[2] & 07777, 0640, 'not world readable (TSIG secrets)');

SKIP: {
    my ($d2) = grep { -x $_ } ('/usr/sbin/kea-dhcp-ddns', '/usr/local/sbin/kea-dhcp-ddns');
    skip('kea-dhcp-ddns not installed', 1) unless ($d2);
    my $chk = `$d2 -t $file 2>&1`;
    is($? >> 8, 0, 'kea-dhcp-ddns -t accepts it') or diag($chk);
}

open(my $fh, '<', $file) or die $!;
my $text = do { local $/; <$fh> };
close($fh);
$text =~ s{^//[^\n]*\n}{}mg;
my $cfg = JSON::PP->new->decode($text)->{DhcpDdns};
is_deeply($cfg->{'tsig-keys'}, [ { name => 'ddns-key', algorithm => 'HMAC-MD5',
                                    secret => encode_base64($secret, '') } ],
          'TSIG key decrypted');
is_deeply($cfg->{'forward-ddns'}{'ddns-domains'},
          [ { name => 'acl.test.', 'key-name' => 'ddns-key',
              'dns-servers' => [ { 'ip-address' => '192.0.2.53', port => 53 } ] },
            { name => 'ddns.test.', 'key-name' => 'ddns-key',
              'dns-servers' => [ { 'ip-address' => '192.0.2.53', port => 53 } ] } ],
          'forward domains: negated key skipped, key from ACL, catalog only zone left out');
is_deeply([ map { $_->{name} } @{$cfg->{'reverse-ddns'}{'ddns-domains'}} ],
          [ '40.10.in-addr.arpa.' ], 'reverse domain');
ok(!exists $cfg->{'reverse-ddns'}{'ddns-domains'}[0]{'key-name'}, 'address based: no key');

done_testing();
