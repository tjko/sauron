#!/usr/bin/perl
# t/18-delete-server.t - delete_server() cleanup of server-level records
#
# Checks that deleting a server also deletes its ACLs (with their entries)
# and TSIG keys, and that a server with slave servers cannot be deleted.
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

sub cleanup {
    db_exec("DELETE FROM cidr_entries WHERE type=0 AND ref=$aclid");
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

cleanup();
db_exec("INSERT INTO servers (id,name) VALUES ($srvid,'delsrv-test')");
db_exec("INSERT INTO servers (id,name,masterserver) " .
        "VALUES ($slaveid,'delsrv-slave',$srvid)");
db_exec("INSERT INTO acls (id,server,name) VALUES ($aclid,$srvid,'delsrv-acl')");
db_exec("INSERT INTO cidr_entries (type,ref,mode,ip) " .
        "VALUES (0,$aclid,0,'192.0.2.0/24')");
db_exec("INSERT INTO keys (id,type,ref,name,protocol,algorithm) " .
        "VALUES ($keyid,1,$srvid,'delsrv-key',3,157)");

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
};

cleanup();
done_testing();
