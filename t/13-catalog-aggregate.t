#!/usr/bin/perl
# t/13-catalog-aggregate.t - Integration tests for catalog zone import,
#                            aggregate zones, groups, and priority/conflict resolution
#
# Requires running PostgreSQL with initialized Sauron DB.
# Skipped unless SAURON_TEST_DSN and SAURON_INSTALL_DIR are set.
#
# Test plan:
#   1. Import external catalog zone from file (import-catalog-zone)
#   2. Verify shadow catalog zone created with catalog_only flag
#   3. Verify member zones parsed and added
#   4. Verify RFC 9432 group assignments propagated
#   5. Import second catalog zone (overlapping member)
#   6. Create aggregate zone (type A) and compose from both sources
#   7. Verify priority-based conflict resolution
#   8. Generate aggregate zone file, verify merged output
#   9. Verify sync mode (--sync) removes stale members
#  10. BackEnd API unit tests for composition functions
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;
use File::Temp qw(tempdir);

my $install_dir = $ENV{SAURON_INSTALL_DIR} || '';
my $dsn         = $ENV{SAURON_TEST_DSN}    || '';

unless ($dsn && $install_dir && -d $install_dir) {
    plan skip_all => 'Set SAURON_TEST_DSN and SAURON_INSTALL_DIR for catalog aggregate tests';
}

# Ensure DB.pm symlink
my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

# Globals needed by Sauron modules
our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

use Sauron::DB;
use Sauron::Util;
use Sauron::BackEnd;

my $testdata = "$FindBin::Bin/../test";
my $server   = 'catalog-test';

# =========================================================================
# Setup: connect to DB and create test server
# =========================================================================
subtest 'setup: database connection' => sub {
    my $ret = db_connect2();
    is($ret, 1, 'db_connect2 succeeds') or BAIL_OUT('Cannot connect to database');
};

# Check if test server exists, create if not
my $serverid;
subtest 'setup: create test server' => sub {
    $serverid = get_server_id($server);
    if ($serverid > 0) {
        pass("test server '$server' already exists (id=$serverid)");
        return;
    }

    # Create minimal server for testing
    my $res = db_exec("INSERT INTO servers (name, hostname, hostmaster, " .
                      "refresh, retry, expire, minimum, ttl) " .
                      "VALUES ('$server', 'ns1.catalog-test.example.com.', " .
                      "'admin.catalog-test.example.com.', " .
                      "3600, 900, 604800, 3600, 3600)");
    ok($res >= 0, 'inserted test server') or BAIL_OUT("Cannot create test server: $res");

    $serverid = get_server_id($server);
    ok($serverid > 0, "test server created (id=$serverid)")
        or BAIL_OUT("Cannot find test server after insert");
};


# =========================================================================
# Test 1: Import catalog zone #1 from file
# =========================================================================
subtest 'import catalog zone #1' => sub {
    my $zonefile = "$testdata/catalog1.example.com.zone";
    plan skip_all => "Zone file not found: $zonefile" unless (-r $zonefile);

    my $cmd = "$install_dir/import-catalog-zone --verbose --catalog-only " .
              "--file=$zonefile $server catalog1.example.com 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'import-catalog-zone exits 0') or diag($out);
    like($out, qr/Found 3 member zones/, 'found 3 members in catalog1');
};


# =========================================================================
# Test 2: Verify shadow catalog zone created with correct properties
# =========================================================================
my $cat1_id;
subtest 'verify shadow catalog zone #1' => sub {
    $cat1_id = get_zone_id('catalog1.example.com', $serverid);
    ok($cat1_id > 0, 'catalog1 zone exists in DB') or return;

    my %zone;
    my $res = get_zone($cat1_id, \%zone);
    is($res, 0, 'get_zone succeeds');
    is($zone{type}, 'C', 'zone type is C (catalog)');
    is($zone{catalog_only}, 't', 'catalog_only flag is set');
    like($zone{comment}, qr/shadow/i, 'comment indicates shadow/imported zone');
};


# =========================================================================
# Test 3: Verify member zones created and added to catalog
# =========================================================================
subtest 'verify catalog #1 members' => sub {
    plan skip_all => 'catalog1 not created' unless ($cat1_id && $cat1_id > 0);

    my $rec = {};
    my $res = get_zone_catalog_members($cat1_id, $rec);
    is($res, 0, 'get_zone_catalog_members succeeds');
    is($rec->{count}, 3, 'catalog has 3 members');

    # Build name lookup
    my %members;
    for my $m (@{$rec->{members}}) {
        $members{lc($m->[1])} = $m;
    }

    ok(exists $members{'alpha.example.com'}, 'alpha.example.com is member');
    ok(exists $members{'beta.example.com'}, 'beta.example.com is member');
    ok(exists $members{'shared.example.com'}, 'shared.example.com is member');
};


# =========================================================================
# Test 4: Verify RFC 9432 group assignments propagated
# =========================================================================
subtest 'verify catalog #1 group assignments' => sub {
    plan skip_all => 'catalog1 not created' unless ($cat1_id && $cat1_id > 0);

    my $rec = {};
    get_zone_catalog_members($cat1_id, $rec);

    my %member_groups;
    for my $m (@{$rec->{members}}) {
        $member_groups{lc($m->[1])} = $m->[7];  # groups arrayref at index 7
    }

    is_deeply($member_groups{'alpha.example.com'}, ['frontend'],
              'alpha has group "frontend"');
    is_deeply($member_groups{'beta.example.com'}, ['backend'],
              'beta has group "backend"');
    is_deeply($member_groups{'shared.example.com'}, ['shared-group'],
              'shared has group "shared-group"');
};


# =========================================================================
# Test 5: Verify group definitions were created
# =========================================================================
subtest 'verify catalog #1 group definitions' => sub {
    plan skip_all => 'catalog1 not created' unless ($cat1_id && $cat1_id > 0);

    my $grp_rec = {};
    my $res = get_catalog_group_defs($cat1_id, $grp_rec);
    is($res, 0, 'get_catalog_group_defs succeeds');
    ok($grp_rec->{count} >= 3, 'at least 3 group definitions exist');

    my %names = map { $_->[1] => 1 } @{$grp_rec->{groups}};
    ok($names{'frontend'}, 'group "frontend" defined');
    ok($names{'backend'}, 'group "backend" defined');
    ok($names{'shared-group'}, 'group "shared-group" defined');
};


# =========================================================================
# Test 6: Import catalog zone #2 (with overlapping member)
# =========================================================================
my $cat2_id;
subtest 'import catalog zone #2' => sub {
    my $zonefile = "$testdata/catalog2.example.com.zone";
    plan skip_all => "Zone file not found: $zonefile" unless (-r $zonefile);

    my $cmd = "$install_dir/import-catalog-zone --verbose --catalog-only " .
              "--file=$zonefile $server catalog2.example.com 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'import-catalog-zone exits 0') or diag($out);
    like($out, qr/Found 3 member zones/, 'found 3 members in catalog2');

    $cat2_id = get_zone_id('catalog2.example.com', $serverid);
    ok($cat2_id > 0, 'catalog2 zone exists in DB');
};


# =========================================================================
# Test 7: Verify catalog #2 members and overlapping zone handling
# =========================================================================
subtest 'verify catalog #2 members and overlap' => sub {
    plan skip_all => 'catalog2 not created' unless ($cat2_id && $cat2_id > 0);

    my $rec = {};
    get_zone_catalog_members($cat2_id, $rec);

    my %members;
    for my $m (@{$rec->{members}}) {
        $members{lc($m->[1])} = $m;
    }

    ok(exists $members{'gamma.example.com'}, 'gamma.example.com is member');
    ok(exists $members{'delta.example.com'}, 'delta.example.com is member');

    # shared.example.com was already in catalog1, should also be in catalog2
    # (zone can belong to multiple catalogs)
    ok(exists $members{'shared.example.com'}, 'shared.example.com is also in catalog2');

    # Verify shared has different group in catalog2
    my $shared_groups = $members{'shared.example.com'}[7];
    is_deeply($shared_groups, ['overlap-group'],
              'shared has group "overlap-group" in catalog2');
};


# =========================================================================
# Test 8: BackEnd API - create aggregate zone (type A)
# =========================================================================
my $agg_id;
subtest 'create aggregate zone (type A)' => sub {
    plan skip_all => 'catalogs not created' unless ($cat1_id > 0 && $cat2_id > 0);

    my %zonehash = (
        server   => $serverid,
        type     => 'A',
        reverse  => 'false',
        name     => 'aggregate.example.com',
        serial   => '2024010101',
        refresh  => 3600,
        retry    => 900,
        expire   => 604800,
        minimum  => 0,
        ttl      => 0,
        comment  => 'Test aggregate catalog zone',
        ns       => [[0, 'invalid.', '']],
        mx       => [],
        txt      => [],
        ip       => [],
        naptr    => [],
    );

    $agg_id = add_zone(\%zonehash);
    ok($agg_id > 0, "aggregate zone created (id=$agg_id)") or return;

    my %zone;
    get_zone($agg_id, \%zone);
    is($zone{type}, 'A', 'zone type is A (aggregate)');
};


# =========================================================================
# Test 9: BackEnd API - add compositions with priorities
# =========================================================================
subtest 'add catalog compositions with priorities' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    # Add catalog1 with priority 10 (higher precedence)
    my $res = add_catalog_composition($agg_id, $cat1_id, 10);
    ok($res >= 0, 'added catalog1 with priority=10') or diag("error=$res");

    # Add catalog2 with priority 20 (lower precedence)
    $res = add_catalog_composition($agg_id, $cat2_id, 20);
    ok($res >= 0, 'added catalog2 with priority=20') or diag("error=$res");

    # Verify compositions stored correctly
    my $comp_rec = {};
    $res = get_catalog_compositions($agg_id, $comp_rec);
    is($res, 0, 'get_catalog_compositions succeeds');
    is($comp_rec->{count}, 2, 'aggregate has 2 source compositions');

    # Verify ordering by priority ASC
    # Columns: [id, source_zone_id, source_name, priority]
    my @comps = @{$comp_rec->{compositions}};
    is($comps[0][1], $cat1_id, 'first composition is catalog1 (priority 10)');
    is($comps[0][3], 10, 'catalog1 priority is 10');
    is($comps[1][1], $cat2_id, 'second composition is catalog2 (priority 20)');
    is($comps[1][3], 20, 'catalog2 priority is 20');
};


# =========================================================================
# Test 10: BackEnd API - duplicate composition rejected
# =========================================================================
subtest 'duplicate composition rejected' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    my $res = add_catalog_composition($agg_id, $cat1_id, 50);
    is($res, -10, 'duplicate composition returns -10');
};


# =========================================================================
# Test 11: BackEnd API - validate composition type checks
# =========================================================================
subtest 'composition type validation' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    # Cannot add non-C zone as source
    my $alpha_id = get_zone_id('alpha.example.com', $serverid);
    if ($alpha_id > 0) {
        my $res = add_catalog_composition($agg_id, $alpha_id, 50);
        ok($res < 0, 'non-catalog zone rejected as source') or diag("error=$res");
    }

    # Cannot add to non-A zone as composite
    my $res = add_catalog_composition($cat1_id, $cat2_id, 50);
    ok($res < 0, 'non-aggregate zone rejected as composite') or diag("error=$res");

    # Self-reference rejected
    $res = add_catalog_composition($agg_id, $agg_id, 50);
    is($res, -2, 'self-reference rejected');
};


# =========================================================================
# Test 12: Generate aggregate zone file and verify merged output
# =========================================================================
subtest 'generate aggregate zone file' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    my $gendir = tempdir(CLEANUP => 1);
    my $cmd = "$install_dir/sauron --verbose --bind $server $gendir 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'sauron --bind exits 0') or do { diag($out); return; };

    # Find the aggregate zone file
    my $aggfile = find_zone_file($gendir, 'aggregate.example.com');
    ok($aggfile && -r $aggfile, 'aggregate zone file generated') or do {
        diag("Generated files: " . `find $gendir -type f`);
        return;
    };

    # Read zone file content
    open(my $fh, '<', $aggfile) or do { fail("cannot read $aggfile"); return; };
    my $content = do { local $/; <$fh> };
    close($fh);

    # Verify version record
    like($content, qr/version\.catalog\s+.*\s+IN\s+TXT\s+"2"/,
         'contains version.catalog TXT "2"');

    # Verify members from catalog1
    like($content, qr/PTR\s+alpha\.example\.com\./,
         'contains alpha.example.com PTR');
    like($content, qr/PTR\s+beta\.example\.com\./,
         'contains beta.example.com PTR');

    # Verify members from catalog2
    like($content, qr/PTR\s+gamma\.example\.com\./,
         'contains gamma.example.com PTR');
    like($content, qr/PTR\s+delta\.example\.com\./,
         'contains delta.example.com PTR');

    # Verify group TXT records present
    like($content, qr/TXT\s+"frontend"/,
         'contains group "frontend"');
    like($content, qr/TXT\s+"backend"/,
         'contains group "backend"');
    like($content, qr/TXT\s+"monitoring"/,
         'contains group "monitoring"');

    # shared.example.com should appear only once (from catalog1, priority 10)
    my @shared_ptrs = ($content =~ /PTR\s+shared\.example\.com\./g);
    is(scalar @shared_ptrs, 1,
       'shared.example.com appears exactly once (conflict resolved by priority)');

    # The group for shared should be from catalog1 (priority 10 wins)
    # Find the uuid for shared's PTR line and check its group
    my $shared_zone_id = get_zone_id('shared.example.com', $serverid);
    if ($shared_zone_id > 0) {
        like($content, qr/uuid-$shared_zone_id\.zones\.catalog\s+.*\s+PTR\s+shared\.example\.com\./,
             'shared uses correct uuid in aggregate');
        like($content, qr/group\.uuid-$shared_zone_id\.zones\.catalog\s+.*\s+TXT\s+"shared-group"/,
             'shared group from catalog1 (priority 10) wins');
    }

    # Verify priority source comments
    like($content, qr/Source:.*catalog1.*priority=10/,
         'catalog1 source comment with priority=10');
    like($content, qr/Source:.*catalog2.*priority=20/,
         'catalog2 source comment with priority=20');

    # Verify conflict output on stdout
    like($out, qr/CONFLICT/i,
         'generator reports conflict for shared.example.com')
        if ($out =~ /shared/i);
};


# =========================================================================
# Test 13: Verify catalog_only zones are NOT generated
# =========================================================================
subtest 'catalog_only zones skipped in generation' => sub {
    plan skip_all => 'catalogs not created' unless ($cat1_id > 0);

    my $gendir = tempdir(CLEANUP => 1);
    my $cmd = "$install_dir/sauron --verbose --bind $server $gendir 2>&1";
    my $out = `$cmd`;

    # catalog1.example.com should be skipped (catalog_only=true)
    my $cat1file = find_zone_file($gendir, 'catalog1.example.com');
    ok(!$cat1file, 'catalog_only zone file not generated for catalog1');

    my $cat2file = find_zone_file($gendir, 'catalog2.example.com');
    ok(!$cat2file, 'catalog_only zone file not generated for catalog2');

    # named.conf should not contain catalog_only zones
    my $namedconf = find_named_conf($gendir);
    if ($namedconf) {
        open(my $fh, '<', $namedconf) or do { fail("cannot read $namedconf"); return; };
        my $conf = do { local $/; <$fh> };
        close($fh);
        unlike($conf, qr/catalog1\.example\.com/,
               'catalog_only zone not in named.conf');
        unlike($conf, qr/catalog2\.example\.com/,
               'catalog_only zone not in named.conf');
    }
};


# =========================================================================
# Test 14: Sync mode - remove stale members
# =========================================================================
subtest 'sync mode removes stale members' => sub {
    plan skip_all => 'catalog1 not created' unless ($cat1_id && $cat1_id > 0);

    # Create a temporary catalog zone file with only 2 members (alpha removed)
    my $tmpdir = tempdir(CLEANUP => 1);
    my $syncfile = "$tmpdir/catalog1-sync.zone";
    open(my $fh, '>', $syncfile) or do { fail("cannot write $syncfile"); return; };
    print $fh <<'ZONE';
$TTL 0
$ORIGIN catalog1.example.com.
@	IN	SOA	ns1.example.com. admin.example.com. (
		2024020101 3600 900 604800 0 )
	IN	NS	invalid.
version.catalog		IN	TXT	"2"
uuid-002.zones.catalog	IN	PTR	beta.example.com.
uuid-003.zones.catalog	IN	PTR	shared.example.com.
group.uuid-002.zones.catalog	IN	TXT	"backend"
group.uuid-003.zones.catalog	IN	TXT	"shared-group"
ZONE
    close($fh);

    my $cmd = "$install_dir/import-catalog-zone --verbose --sync " .
              "--file=$syncfile $server catalog1.example.com 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'import-catalog-zone --sync exits 0') or diag($out);
    like($out, qr/[Rr]emov.*alpha/i, 'alpha.example.com removed during sync');

    # Verify alpha is no longer in catalog1
    my $rec = {};
    get_zone_catalog_members($cat1_id, $rec);
    my %members;
    for my $m (@{$rec->{members}}) {
        $members{lc($m->[1])} = 1;
    }
    ok(!exists $members{'alpha.example.com'},
       'alpha.example.com removed from catalog1');
    ok(exists $members{'beta.example.com'},
       'beta.example.com still in catalog1');
    ok(exists $members{'shared.example.com'},
       'shared.example.com still in catalog1');
    is($rec->{count}, 2, 'catalog1 now has 2 members after sync');
};


# =========================================================================
# Test 15: Dry-run mode makes no changes
# =========================================================================
subtest 'dry-run mode makes no changes' => sub {
    plan skip_all => 'catalog1 not created' unless ($cat1_id && $cat1_id > 0);

    # Get current member count
    my $before = {};
    get_zone_catalog_members($cat1_id, $before);
    my $count_before = $before->{count};

    # Create zone file with extra member
    my $tmpdir = tempdir(CLEANUP => 1);
    my $dryfile = "$tmpdir/catalog1-dry.zone";
    open(my $fh, '>', $dryfile) or do { fail("cannot write $dryfile"); return; };
    print $fh <<'ZONE';
$TTL 0
$ORIGIN catalog1.example.com.
@	IN	SOA	ns1.example.com. admin.example.com. (
		2024030101 3600 900 604800 0 )
	IN	NS	invalid.
version.catalog		IN	TXT	"2"
uuid-002.zones.catalog	IN	PTR	beta.example.com.
uuid-003.zones.catalog	IN	PTR	shared.example.com.
uuid-004.zones.catalog	IN	PTR	newzone.example.com.
ZONE
    close($fh);

    my $cmd = "$install_dir/import-catalog-zone --dryrun --verbose " .
              "--file=$dryfile $server catalog1.example.com 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'import-catalog-zone --dryrun exits 0') or diag($out);
    like($out, qr/dry-run/i, 'output mentions dry-run');

    # Member count should not change
    my $after = {};
    get_zone_catalog_members($cat1_id, $after);
    is($after->{count}, $count_before,
       'member count unchanged after dry-run');
};


# =========================================================================
# Test 16: BackEnd API - remove and update compositions
# =========================================================================
subtest 'remove and update compositions' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    # Remove catalog2 from aggregate
    my $res = remove_catalog_composition($agg_id, $cat2_id);
    ok($res >= 0, 'removed catalog2 from aggregate');

    my $comp_rec = {};
    get_catalog_compositions($agg_id, $comp_rec);
    is($comp_rec->{count}, 1, 'aggregate has 1 source after removal');

    # Re-add with different priority
    $res = add_catalog_composition($agg_id, $cat2_id, 5);
    ok($res >= 0, 'added catalog2 back with priority=5');

    $comp_rec = {};
    get_catalog_compositions($agg_id, $comp_rec);
    is($comp_rec->{count}, 2, 'aggregate has 2 sources again');

    # Now catalog2 (priority=5) should be first
    # Columns: [id, source_zone_id, source_name, priority]
    my @comps = @{$comp_rec->{compositions}};
    is($comps[0][1], $cat2_id, 'catalog2 is now first (priority=5)');
    is($comps[1][1], $cat1_id, 'catalog1 is now second (priority=10)');

    # update_catalog_compositions - change priorities
    $res = update_catalog_compositions($agg_id,
                                       [$cat1_id, $cat2_id],
                                       {$cat1_id => 1, $cat2_id => 99});
    ok($res >= 0, 'update_catalog_compositions succeeds');

    $comp_rec = {};
    get_catalog_compositions($agg_id, $comp_rec);
    @comps = @{$comp_rec->{compositions}};
    is($comps[0][1], $cat1_id, 'catalog1 now first after priority update (1)');
    is($comps[0][3], 1, 'catalog1 priority updated to 1');
    is($comps[1][1], $cat2_id, 'catalog2 now second (priority 99)');
    is($comps[1][3], 99, 'catalog2 priority updated to 99');
};


# =========================================================================
# Test 17: Generate after priority swap - verify different conflict winner
# =========================================================================
subtest 'generate after priority swap - conflict winner changes' => sub {
    plan skip_all => 'aggregate zone not created' unless ($agg_id && $agg_id > 0);

    my $gendir = tempdir(CLEANUP => 1);
    my $cmd = "$install_dir/sauron --verbose --bind $server $gendir 2>&1";
    my $out = `$cmd`;
    my $rc = $? >> 8;
    is($rc, 0, 'sauron --bind exits 0') or do { diag($out); return; };

    my $aggfile = find_zone_file($gendir, 'aggregate.example.com');
    ok($aggfile && -r $aggfile, 'aggregate zone file generated') or return;

    open(my $fh, '<', $aggfile) or do { fail("cannot read $aggfile"); return; };
    my $content = do { local $/; <$fh> };
    close($fh);

    # shared.example.com should still appear only once
    my @shared_ptrs = ($content =~ /PTR\s+shared\.example\.com\./g);
    is(scalar @shared_ptrs, 1,
       'shared.example.com still appears exactly once');

    # With catalog1 at priority=1 (wins), shared's group should be from catalog1
    my $shared_zid = get_zone_id('shared.example.com', $serverid);
    if ($shared_zid > 0) {
        like($content, qr/group\.uuid-$shared_zid\.zones\.catalog\s+.*\s+TXT\s+"shared-group"/,
             'shared group from catalog1 (now priority=1) wins');
    }
};


# =========================================================================
# Cleanup: remove test zones (in correct dependency order)
# =========================================================================
subtest 'cleanup: remove test zones' => sub {
    # Remove aggregate zone first (has FK references to catalog compositions)
    if ($agg_id && $agg_id > 0) {
        my $res = delete_zone($agg_id);
        ok($res >= 0, "deleted aggregate zone (id=$agg_id)") or diag("error=$res");
    }

    # Remove member zones (must remove from catalogs first via cascade)
    for my $zname ('alpha.example.com', 'beta.example.com',
                   'gamma.example.com', 'delta.example.com',
                   'shared.example.com') {
        my $zid = get_zone_id($zname, $serverid);
        if ($zid > 0) {
            my $res = delete_zone($zid);
            ok($res >= 0, "deleted $zname") or diag("error=$res");
        }
    }

    # Remove catalog zones
    for my $catname ('catalog1.example.com', 'catalog2.example.com') {
        my $zid = get_zone_id($catname, $serverid);
        if ($zid > 0) {
            my $res = delete_zone($zid);
            ok($res >= 0, "deleted $catname") or diag("error=$res");
        }
    }

    # Cleanup test server
    if ($serverid > 0) {
        db_exec("DELETE FROM servers WHERE id=$serverid");
        pass("cleaned up test server");
    }
};

done_testing();


# =========================================================================
# Helper functions
# =========================================================================

sub find_zone_file {
    my ($gendir, $zonename) = @_;
    # Sauron generates zone files in subdirectories or flat
    my @candidates;
    require File::Find;
    File::Find::find(sub {
        push @candidates, $File::Find::name
            if (-f $_ && $File::Find::name =~ /\Q$zonename\E/);
    }, $gendir);
    return $candidates[0] if @candidates;
    return undef;
}

sub find_named_conf {
    my ($gendir) = @_;
    my @candidates;
    require File::Find;
    File::Find::find(sub {
        push @candidates, $File::Find::name
            if (-f $_ && /named.*\.conf$/);
    }, $gendir);
    return $candidates[0] if @candidates;
    return undef;
}
