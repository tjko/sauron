#!/usr/bin/perl
# t/18-delete-server.t - delete_server() cleanup of server-level records
#
# Checks that deleting a server also deletes its ACLs (with their entries)
# and TSIG keys, its AML entries (allow-transfer, ..., listen-on-v6), and
# that a server with slave servers cannot be deleted.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/18-delete-server.t
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
    plan skip_all => 'Set SAURON_TEST_DSN to run delete_server DB tests';
}

use Sauron::DB;
use Sauron::BackEnd;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('delsrv-test');

my $srvid   = 920001;
my $slaveid = 920002;
my $aclid   = 920003;
my $keyid   = 920004;

my @aml_types = (1, 7, 8, 9, 10, 14, 15, 16);

sub cleanup {
    db_exec("DELETE FROM cidr_entries WHERE type=0 AND ref=$aclid");
    db_exec("DELETE FROM cidr_entries WHERE type IN (" .
            join(',', @aml_types) . ") AND ref IN ($srvid,$slaveid)");
    db_exec("DELETE FROM acls WHERE id=$aclid");
    db_exec("DELETE FROM keys WHERE id=$keyid");
    db_exec("DELETE FROM servers WHERE id IN ($srvid,$slaveid)");
}

sub count {
    my ($sql) = @_;
    my @q;
    db_query($sql, \@q);
    return $q[0][0];
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

cleanup();
setup_ok("INSERT INTO servers (id,name) VALUES ($srvid,'delsrv-test')");
setup_ok("INSERT INTO servers (id,name,masterserver) " .
         "VALUES ($slaveid,'delsrv-slave',$srvid)");
setup_ok("INSERT INTO acls (id,server,name) VALUES ($aclid,$srvid,'delsrv-acl')");
setup_ok("INSERT INTO cidr_entries (type,ref,mode,ip) " .
         "VALUES (0,$aclid,0,'192.0.2.0/24')");
setup_ok("INSERT INTO keys (id,type,ref,name,protocol,algorithm) " .
         "VALUES ($keyid,1,$srvid,'delsrv-key',3,157)");
# server AML fields referencing the ACL and the key
for my $type (@aml_types) {
    setup_ok("INSERT INTO cidr_entries (type,ref,mode,acl) " .
             "VALUES ($type,$srvid,1,$aclid)");
    setup_ok("INSERT INTO cidr_entries (type,ref,mode,tkey) " .
             "VALUES ($type,$srvid,2,$keyid)");
}
is(count("SELECT count(*) FROM cidr_entries WHERE type=0 AND ref=$aclid"), 1,
   "ACL entry created");
is(count("SELECT count(*) FROM cidr_entries WHERE ref=$srvid AND type IN (" .
         join(',', @aml_types) . ")"), 2 * @aml_types,
   "server AML entries created");
is(count("SELECT count(*) FROM keys WHERE type=1 AND ref=$srvid"), 1,
   "key created");

subtest 'server with slave servers is kept' => sub {
    is(delete_server($srvid), -101, "delete_server refuses");
    is(count("SELECT count(*) FROM servers WHERE id=$srvid"), 1,
       "server still exists");
    is(count("SELECT count(*) FROM acls WHERE id=$aclid"), 1,
       "ACL still exists");
};

subtest 'ACLs and keys deleted with the server' => sub {
    is(delete_server($slaveid), 0, "slave server deleted");
    is(delete_server($srvid), 0, "server deleted");
    is(count("SELECT count(*) FROM acls WHERE server=$srvid"), 0,
       "no orphaned ACLs");
    is(count("SELECT count(*) FROM cidr_entries WHERE type=0 AND ref=$aclid"),
       0, "no orphaned ACL entries");
    is(count("SELECT count(*) FROM keys WHERE type=1 AND ref=$srvid"), 0,
       "no orphaned keys");
    is(count("SELECT count(*) FROM cidr_entries WHERE ref=$srvid AND " .
             "type IN (" . join(',', @aml_types) . ")"), 0,
       "no orphaned server AML entries");
    is(count("SELECT count(*) FROM cidr_entries WHERE type>0 AND " .
             "(acl=$aclid OR tkey=$keyid)"), 0,
       "no entries referencing deleted ACL/key");
};

cleanup();
done_testing();
