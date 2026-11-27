#!/usr/bin/perl
# t/23-alias-txt.t - aliases (type 4, CNAME and Static Alias) and TXT records
#
# No other data may exist at a CNAME owner name (RFC 1034), so:
#   - host_required_data_error()/add_host() reject TXT entries on an alias,
#     while TXT rows stored earlier don't block editing the alias;
#   - the zone generator emits no TXT for aliases (it warns instead).
#
# Skipped unless SAURON_TEST_DSN is set; zone generation also needs
# SAURON_INSTALL_DIR (like t/11):
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/23-alias-txt.t
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);

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
    plan skip_all => 'Set SAURON_TEST_DSN to run alias TXT DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('aliastxt-test');

my $srvid    = 950001;
my $zoneid   = 950002;
my $hostid   = 950003;
my $cnameid  = 950004;
my $staticid = 950005;
my $srvname  = 'aliastxt-test';
my $zonename = 'aliastxt.example';

sub cleanup {
    db_exec("DELETE FROM txt_entries WHERE type=2 AND ref IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM a_entries WHERE host IN " .
            "(SELECT id FROM hosts WHERE zone=$zoneid)");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

cleanup();
setup_ok("INSERT INTO servers (id,name,hostname,hostmaster) VALUES " .
         "($srvid,'$srvname','ns.$zonename.','hostmaster.$zonename.')");
setup_ok("INSERT INTO zones (id,server,name,type,reverse) " .
         "VALUES ($zoneid,$srvid,'$zonename','M',false)");
setup_ok("INSERT INTO hosts (id,zone,type,domain) " .
         "VALUES ($hostid,$zoneid,1,'www')");
setup_ok("INSERT INTO a_entries (host,ip) VALUES ($hostid,'192.0.2.10')");
setup_ok("INSERT INTO hosts (id,zone,type,domain,alias) " .
         "VALUES ($cnameid,$zoneid,4,'cn',$hostid)");
setup_ok("INSERT INTO hosts (id,zone,type,domain,alias,cname_txt) " .
         "VALUES ($staticid,$zoneid,4,'st',-1,'target.example.net.')");
# TXT stored on aliases before it was rejected
setup_ok("INSERT INTO txt_entries (type,ref,txt) VALUES (2,$cnameid,'cn-txt')");
setup_ok("INSERT INTO txt_entries (type,ref,txt) VALUES (2,$staticid,'st-txt')");

subtest 'new alias with TXT is rejected' => sub {
    my %rec = (zone => $zoneid, type => 4, domain => 'new', alias => $hostid,
               txt_l => [['Text','Comments'], [0, 'new-txt', '', 2]]);
    is(Sauron::BackEnd::host_required_data_error(\%rec),
       'Alias (CNAME) record cannot have TXT entries.', 'CNAME alias');
    is(add_host(\%rec), -27, 'add_host refuses it');

    my %st = (zone => $zoneid, type => 4, domain => 'new', alias => -1,
              cname_txt => 'x.example.net.',
              txt_l => [['Text','Comments'], [0, 'new-txt', '']]);
    is(Sauron::BackEnd::host_required_data_error(\%st),
       'Alias (CNAME) record cannot have TXT entries.', 'Static alias');

    delete $rec{txt_l};
    is(Sauron::BackEnd::host_required_data_error(\%rec), '', 'alias without TXT accepted');
};

subtest 'existing alias' => sub {
    for my $id ($cnameid, $staticid) {
        my %h;
        is(get_host($id, \%h), 0, "get_host($id)");
        is(Sauron::BackEnd::host_required_data_error(\%h), '',
           'stored TXT rows do not block editing');
        cmp_ok(update_host(\%h), '>=', 0, 'update_host succeeds');

        my %h2;
        get_host($id, \%h2);
        push @{$h2{txt_l}}, [0, 'added', '', 2];
        is(Sauron::BackEnd::host_required_data_error(\%h2),
           'Alias (CNAME) record cannot have TXT entries.', 'adding TXT rejected');

        my %h3;
        get_host($id, \%h3);
        $h3{txt_l}[1][1] = 'changed';
        $h3{txt_l}[1][3] = 1;
        is(Sauron::BackEnd::host_required_data_error(\%h3),
           'Alias (CNAME) record cannot have TXT entries.', 'changing TXT rejected');

        $h3{txt_l}[1][3] = -1;
        is(Sauron::BackEnd::host_required_data_error(\%h3), '', 'deleting TXT accepted');
    }
};

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
SKIP: {
    skip 'Set SAURON_INSTALL_DIR to test zone generation', 1
        unless ($install_dir && -x "$install_dir/sauron");

    subtest 'zone file has no TXT at alias names' => sub {
        my $dir = tempdir(CLEANUP => 1);
        my $out = `$install_dir/sauron --bind $srvname $dir 2>&1`;
        is($? >> 8, 0, 'sauron --bind exits 0') or diag($out);

        my $zfile = `find $dir -name '$zonename.zone'`;
        chomp($zfile);
        ok(open(my $fh, '<', $zfile), "zone file generated") or return;
        my $zone = do { local $/; <$fh> };
        close($fh);

        like($zone, qr/^cn\s.*CNAME\s+www\b/m, 'CNAME alias emitted');
        like($zone, qr/^st\s.*CNAME\s+target\.example\.net\./m,
             'Static alias emitted');
        unlike($zone, qr/cn-txt|st-txt/, 'no TXT for aliases');
        like($out, qr/TXT on alias ignored .*: cn\b/, 'warning for CNAME alias');
        like($out, qr/TXT on alias ignored .*: st\b/, 'warning for Static alias');
    };
}

cleanup();
done_testing();
