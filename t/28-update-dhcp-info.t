#!/usr/bin/perl
# t/28-update-dhcp-info.t - update-dhcp-info with ISC dhcpd and KEA logs
#
# Hosts get dhcp_date/dhcp_info from DHCPACK lines of dhcpd and from KEA
# DHCP4/DHCP6_LEASE_ALLOC/REUSE lines (KEA log file, classic syslog and
# RFC 3339 syslog time stamps; DHCPv6 hosts matched by DUID).
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
use Time::Local qw(timelocal timegm);

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
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('dhcp-info-test');

my $server = 'dhcp-info-test';
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
END { cleanup() if (defined $server); }   # set only after db_connect2()
db_exec("INSERT INTO servers (name,hostname,hostmaster) VALUES " .
        "('$server','ns1.info.test.','hostmaster.info.test.')");

open(my $zf, '>', "$tmp/info.test.zone") or die $!;
print $zf <<'EOF';
$TTL 3600
@	IN	SOA	ns1.info.test. hostmaster.info.test. ( 1 3600 900 604800 3600 )
	IN	NS	ns1.info.test.
isc	IN	A	10.40.0.5
k4file	IN	A	10.40.0.10
k4sys	IN	A	10.40.0.11
k4ip	IN	A	10.40.0.12
k6	IN	AAAA	2001:db8:40::10
old	IN	A	10.40.0.13
ds	IN	A	10.40.0.15
ds	IN	AAAA	2001:db8:40::15
pri	IN	A	10.40.0.14
roll	IN	A	10.40.0.16
EOF
close($zf);
my $out = `$install_dir/import-zone $server info.test $tmp/info.test.zone 2>&1`;
is($? >> 8, 0, 'import-zone') or diag($out);

sub hid {
    return rows("SELECT h.id FROM hosts h JOIN zones z ON h.zone=z.id " .
                "WHERE z.name='info.test' AND h.domain='$_[0]'")->[0][0];
}
db_exec("UPDATE hosts SET ether='0A0000000005' WHERE id=" . hid('isc'));
db_exec("UPDATE hosts SET ether='0A0000000010' WHERE id=" . hid('k4file'));
db_exec("UPDATE hosts SET ether='0A0000000011' WHERE id=" . hid('k4sys'));
db_exec("UPDATE hosts SET ether='0A00000000FF' WHERE id=" . hid('k4ip'));  # other MAC
db_exec("UPDATE hosts SET duid='000100012A3B4C5D0A0000000010' WHERE id=" . hid('k6'));
db_exec("UPDATE hosts SET ether='0A0000000013' WHERE id=" . hid('old'));
db_exec("UPDATE hosts SET ether='0A0000000015', duid='000100012A3B4C5D0A0000000015' WHERE id=" . hid('ds'));
db_exec("UPDATE hosts SET ether='0A0000000014' WHERE id=" . hid('pri'));
db_exec("UPDATE hosts SET ether='0A0000000016' WHERE id=" . hid('roll'));

my $year = (localtime)[5] + 1900 - 1;   # log of the last year: always in the past
my $newer = timelocal(0, 0, 9, 30, 9, (localtime)[5] + 1900 - 1);
db_exec("UPDATE hosts SET dhcp_date=$newer WHERE id=" . hid('old'));
my %exp = (
    isc    => timelocal(1, 5, 7, 30, 9, $year),
    k4file => timelocal(1, 15, 8, 30, 9, $year),
    k4sys  => timelocal(1, 20, 8, 30, 9, $year),
    k4ip   => timelocal(1, 22, 8, 30, 9, $year),
    k6     => timegm(1, 25, 7, 30, 9, $year),       # 08:25:01+01:00
    ds     => timelocal(1, 40, 8, 30, 9, $year),
    pri    => timelocal(1, 35, 8, 30, 9, $year),
);
open(my $lf, '>', "$tmp/dhcp.log") or die $!;
print $lf <<"EOF";
Feb 29 07:00:01 dhcp1 kea-dhcp4[2345]: INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:99], cid=[no info], tid=0x9: lease 10.40.0.99 has been allocated for 3600 seconds
Oct 30 07:05:01 dhcp1 dhcpd[123]: DHCPACK on 10.40.0.5 to 0a:00:00:00:00:05 via eth0
$year-10-30 08:10:01.123 INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:10], cid=[no info], tid=0x1: lease 10.40.0.99 has been allocated for 3600 seconds
$year-10-30 08:15:01.123 INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:10], cid=[01:0a:00:00:00:00:10], tid=0x2: lease 10.40.0.10 has been allocated for 3600 seconds
Oct 30 08:20:01 dhcp1 kea-dhcp4[2345]: INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_REUSE [hwtype=1 0a:00:00:00:00:11], cid=[no info], tid=0x3: lease 10.40.0.11 has been reused for 3000 seconds
Oct 30 08:22:01 dhcp1 kea-dhcp4[2345]: INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:12], cid=[no info], tid=0x4: lease 10.40.0.12 has been allocated for 3600 seconds
$year-10-30T08:25:01.123456+01:00 dhcp1 kea-dhcp6[2346]: INFO  [kea-dhcp6.leases/2346.1] DHCP6_LEASE_ALLOC duid=[00:01:00:01:2a:3b:4c:5d:0a:00:00:00:00:10], [no hwaddr info], tid=0x5: lease for address 2001:DB8:40:0::10 and iaid=1 has been allocated for 4000 seconds
$year-10-30 08:30:01.000 INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:13], cid=[no info], tid=0x6: lease 10.40.0.13 has been allocated for 3600 seconds
$year-10-30 08:20:01.000 INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:15], cid=[no info], tid=0xa: lease 10.40.0.15 has been allocated for 3600 seconds
<30>Oct 30 08:35:01 dhcp1 kea-dhcp4[2345]: INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:14], cid=[no info], tid=0xb: lease 10.40.0.14 has been allocated for 3600 seconds
$year-10-30 08:40:01.000 INFO  [kea-dhcp6.leases/2346.1] DHCP6_LEASE_ALLOC duid=[00:01:00:01:2a:3b:4c:5d:0a:00:00:00:00:15], [hwtype=1 0a:00:00:00:00:15], tid=0xc: lease for address 2001:db8:40::15 and iaid=1 has been allocated for 4000 seconds
$year-10-30 08:31:01.000 INFO  [kea-dhcp4.dhcp4/2345.1] DHCP4_LEASE_ADVERT [hwtype=1 0a:00:00:00:00:05], cid=[no info], tid=0x7: lease 10.40.0.5 will be advertised
EOF
close($lf);

$out = `$install_dir/update-dhcp-info --verbose --commit --year=$year $server $tmp/dhcp.log 2>&1`;
is($? >> 8, 0, 'update-dhcp-info exits 0') or diag($out);

my %got = map { ($_ => rows("SELECT dhcp_date,dhcp_info FROM hosts WHERE id=" . hid($_))->[0]) }
    (keys %exp, 'old');
is($got{isc}[0], $exp{isc}, 'dhcpd DHCPACK (regression)');
is($got{k4file}[0], $exp{k4file}, 'KEA log file, newest lease of the MAC');
like($got{k4file}[1], qr/^10\.40\.0\.10 for 0a:00:00:00:00:10 via kea-dhcp4$/, 'KEA info');
is($got{k4sys}[0], $exp{k4sys}, 'KEA classic syslog, lease reuse');
like($got{k4sys}[1], qr/via dhcp1 kea-dhcp4$/, 'syslog host in info');
is($got{k4ip}[0], $exp{k4ip}, 'host with another MAC matched by IP');
is($got{k6}[0], $exp{k6}, 'KEA DHCPv6 RFC 3339 time, matched by DUID');
like($got{k6}[1], qr/^2001:db8:40::10 for DUID 00:01:00:01:2a:3b:4c:5d:0a:00:00:00:00:10 via dhcp1 kea-dhcp6$/,
     'DHCPv6 info');
is($got{old}[0], $newer, 'newer dhcp_date not overwritten');
is($got{ds}[0], $exp{ds}, 'dual-stack host: the newer DHCPv6 lease wins over DHCPv4');
like($got{ds}[1], qr/^2001:db8:40::15 for DUID /, 'dual-stack info from DHCPv6');
is($got{pri}[0], $exp{pri}, 'syslog line with <pri> prefix');

# year rollover: a classic December syslog line older than a KEA line
# with an explicit January date belongs to the year before that date
# (not to --year)
open($lf, '>', "$tmp/roll.log") or die $!;
my $ny = $year + 1;
print $lf <<"EOF";
Dec 30 10:00:01 dhcp1 kea-dhcp4[2345]: INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:16], cid=[no info], tid=0xd: lease 10.40.0.16 has been allocated for 3600 seconds
$year-01-02 10:00:01.000 INFO  [kea-dhcp4.leases/2345.1] DHCP4_LEASE_ALLOC [hwtype=1 0a:00:00:00:00:98], cid=[no info], tid=0xe: lease 10.40.0.98 has been allocated for 3600 seconds
EOF
close($lf);
$out = `$install_dir/update-dhcp-info --verbose --commit --year=$ny $server $tmp/roll.log 2>&1`;
is($? >> 8, 0, 'update-dhcp-info (year rollover) exits 0') or diag($out);
is(rows("SELECT dhcp_date FROM hosts WHERE id=" . hid('roll'))->[0][0],
   timelocal(1, 0, 10, 30, 11, $year - 1),
   'classic syslog line before an explicit January date: previous year');

done_testing();
