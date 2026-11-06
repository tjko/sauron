#!/usr/bin/perl
# t/24-hidden-form-fields.t - is_hidden_form_field() and user groups
#
# Hiding form fields ($SAURON_HIDE_FORM_FIELDS) is driven by the user's
# groups. A user who is not a member of any group (typical for accounts
# provisioned from Perun) made the Add host form die with "Can't use an
# undefined value as an ARRAY reference" at Sauron/CGIutil.pm, because
# db_query() leaves the result array empty and the code dereferenced $q[0].
# Checks that such a user gets every field shown, that nothing is hidden
# (and no group lookup can break the form) when $SAURON_HIDE_FORM_FIELDS is
# not set, empty or not a hash reference, that a member of a matching group
# still gets the configured field hidden, and that superusers and mandatory
# fields are never hidden.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/24-hidden-form-fields.t
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

our %state;
our $SAURON_HIDE_FORM_FIELDS;
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

unless ($DB_DSN) {
    plan skip_all => 'Set SAURON_TEST_DSN to run hidden form field DB tests';
}

use Sauron::DB;
use Sauron::CGIutil;

db_connect2() or plan skip_all => 'Cannot connect to test database';

my $uid     = 970001;
my $groupid = 970002;
my $group   = 'hideform_test_editors';

# is_hidden_form_field() takes the module name from its caller's caller, as
# when display_form() is called from Sauron::CGI::Hosts.
{
    package Sauron::CGIutil;
    sub _t_is_hidden { return is_hidden_form_field($_[0]); }
}
{
    package Sauron::CGI::Hosts;
    sub _t_hidden { return Sauron::CGIutil::_t_is_hidden($_[0]); }
}
sub hidden { return Sauron::CGI::Hosts::_t_hidden({ tag => $_[0], @_[1 .. $#_] }); }

sub cleanup {
    for my $sql ("DELETE FROM user_rights WHERE type=2 AND ref=$uid",
                 "DELETE FROM user_groups WHERE id=$groupid",
                 "DELETE FROM users WHERE id=$uid") {
        db_exec($sql) >= 0 or diag("cleanup failed: $sql: " . db_lasterrormsg());
    }
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

cleanup();
setup_ok("INSERT INTO users (id,username,password,superuser) " .
         "VALUES ($uid,'hideform-test','x',false)");
setup_ok("INSERT INTO user_groups (id,name) VALUES ($groupid,'$group')");

%state = (uid => $uid, superuser => 'no');
my $config = { '.*_editors' => { 'Hosts' => [ 'expiration' ] } };

# group names are cached per uid for one request (one CGI process)
sub reset_cache { %Sauron::CGIutil::hidden_form_groups = (); }

subtest 'user without any group' => sub {
    reset_cache();
    $SAURON_HIDE_FORM_FIELDS = $config;
    my $res = eval { hidden('expiration') };
    is($@, '', 'does not die');
    is($res, 0, 'field shown');
};

setup_ok("INSERT INTO user_rights (type,ref,rtype,rref) " .
         "VALUES (2,$uid,0,$groupid)");
reset_cache();

# The user is in a matching group here, so a 0 comes from the config check,
# not from the missing group membership.
subtest 'nothing configured to hide' => sub {
    $SAURON_HIDE_FORM_FIELDS = undef;
    is(hidden('expiration'), 0, 'undefined config: field shown');
    $SAURON_HIDE_FORM_FIELDS = {};
    is(hidden('expiration'), 0, 'empty config: field shown');
    $SAURON_HIDE_FORM_FIELDS = [ 'expiration' ];
    my $res = eval { hidden('expiration') };
    is($@, '', 'config that is not a hash reference: does not die');
    is($res, 0, 'config that is not a hash reference: field shown');
};

$SAURON_HIDE_FORM_FIELDS = $config;

subtest 'no valid uid in session' => sub {
    local $state{uid} = undef;
    my $res = eval { hidden('expiration') };
    is($@, '', 'does not die');
    is($res, 0, 'field shown');
};

subtest 'member of a matching group' => sub {
    is(hidden('expiration'), 1, 'configured field hidden');
    is(hidden('info'), 0, 'other field shown');
    is(hidden('expiration', empty => 0), 0, 'mandatory field never hidden');
    is(hidden('expiration', hide => 0), 0, 'hide=>0 wins over the config');
};

subtest 'superuser and fields without tag' => sub {
    local $state{superuser} = 'yes';
    is(hidden('expiration'), 0, 'superuser sees every field');
    local $state{superuser} = 'no';
    is(hidden(''), 0, 'empty tag shown');
    is(Sauron::CGI::Hosts::_t_hidden({}), 0, 'missing tag shown');
};

cleanup();
done_testing();
