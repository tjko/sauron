#!/usr/bin/perl
# t/19-txt-host-edit.t - editing the TXT value of a TXT host (type 13)
#
# A TXT host keeps its value in hosts.cname_txt; get_host() exposes it as a
# single txt_l row. Runs the web UI edit path (get_host -> form_check_form ->
# update_host) and checks that changing the value/comment in place, and
# deleting the row while adding a new one, are both saved; that the web UI
# rejects more than one TXT row; and that add_host() takes the comment from
# the TXT row too.
#
# Skipped unless SAURON_TEST_DSN is set:
#   SAURON_TEST_DSN="dbi:Pg:dbname=sauron_test" prove -lv t/19-txt-host-edit.t
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
    plan skip_all => 'Set SAURON_TEST_DSN to run TXT host edit DB tests';
}

use CGI qw(param delete_all);
use Sauron::DB;
use Sauron::BackEnd;
use Sauron::CGIutil;
use Sauron::CGI::Hosts;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('txtedit-test');

my $srvid  = 930001;
my $zoneid = 930002;
my $hostid = 930003;

# txt_l field of the TXT host edit form (Sauron/CGI/Hosts.pm)
my %form = (data => [
    {ftype=>1, tag=>'domain', name=>'Hostname', type=>'domain', len=>64},
    {ftype=>2, tag=>'txt_l', name=>'TXT entries', type=>['text','text'],
     whitesp=>['P','P'], fields=>2, maxlen=>[253, 80],
     len=>[50,20], empty=>[0,1], elabels=>['TXT','comment'],
     iff=>['type','13']},
]);

sub cleanup {
    db_exec("DELETE FROM txt_entries WHERE type=2 AND ref=$hostid");
    db_exec("DELETE FROM hosts WHERE zone=$zoneid");
    db_exec("DELETE FROM zones WHERE id=$zoneid");
    db_exec("DELETE FROM servers WHERE id=$srvid");
}

sub setup_ok {
    my ($sql) = @_;
    db_exec($sql) >= 0 or BAIL_OUT("setup failed: $sql: " . db_lasterrormsg());
}

sub db_txt {
    my @q;
    db_query("SELECT cname_txt,comment FROM hosts WHERE id=$hostid", \@q);
    return @{$q[0]};
}

# Fill in the edit form: @rows = ([value, comment, del, existing], ...)
sub check_edit {
    my (@rows) = @_;
    my %host;
    get_host($hostid, \%host) == 0 or BAIL_OUT("get_host($hostid) failed");

    delete_all();
    param('h_type', 13);
    param('h_domain', $host{domain});
    param('h_txt_l_count', scalar(@rows));
    for my $j (1..@rows) {
        my ($val, $comment, $del, $existing) = @{$rows[$j-1]};
        # the existing row carries the id emitted by form_magic()
        param("h_txt_l_${j}_id", $existing ? $host{txt_l}[1][0] : '');
        param("h_txt_l_${j}_1", $val);
        param("h_txt_l_${j}_2", $comment);
        param("h_txt_l_${j}_del", 'on') if ($del);
    }

    is(form_check_form('h', \%host, \%form), 0, 'form_check_form accepts input');
    return \%host;
}

# Submit the edit form, as Sauron/CGI/Hosts.pm does on 'Apply'
sub submit_edit {
    my $host = check_edit(@_);
    is(Sauron::CGI::Hosts::_host_required_data_error($host), '',
       'no required data error');
    cmp_ok(update_host($host), '>=', 0, 'update_host succeeds');
}

cleanup();
setup_ok("INSERT INTO servers (id,name) VALUES ($srvid,'txtedit-test')");
setup_ok("INSERT INTO zones (id,server,name,type,reverse) " .
         "VALUES ($zoneid,$srvid,'txtedit.example','M',false)");
setup_ok("INSERT INTO hosts (id,zone,type,domain,cname_txt,comment,alias) " .
         "VALUES ($hostid,$zoneid,13,'foo','v=old','c-old',-1)");

subtest 'edit value and comment in place' => sub {
    submit_edit(['v=new', 'c-new', 0, 1]);
    is_deeply([db_txt()], ['v=new', 'c-new'], 'cname_txt and comment updated');
};

subtest 'delete row and add a new one' => sub {
    submit_edit(['v=new', 'c-new', 1, 1], ['v=third', 'c-third', 0, 0]);
    is_deeply([db_txt()], ['v=third', 'c-third'], 'replaced by the added row');
};

subtest 'apply without changes' => sub {
    submit_edit(['v=third', 'c-third', 0, 1]);
    is_deeply([db_txt()], ['v=third', 'c-third'], 'value kept');
};

subtest 'edit comment only' => sub {
    submit_edit(['v=third', 'c-fourth', 0, 1]);
    is_deeply([db_txt()], ['v=third', 'c-fourth'], 'comment updated');
    submit_edit(['v=third', '', 0, 1]);
    is_deeply([db_txt()], ['v=third', undef], 'comment cleared (NULL)');
};

subtest 'more than one TXT row is rejected' => sub {
    my $host = check_edit(['v=third', '', 0, 1], ['v=extra', '', 0, 0]);
    is(Sauron::CGI::Hosts::_host_required_data_error($host),
       'TXT record allows only one TXT entry.', 'error reported');
    is_deeply([db_txt()], ['v=third', undef], 'nothing saved');
};

subtest 'add_host takes the comment from the TXT row' => sub {
    my $addid = add_host({zone=>$zoneid, type=>13, domain=>'bar',
                          comment=>'c-host', txt_l=>[[0, 'v=bar', 'c-row']]});
    cmp_ok($addid, '>', 0, 'add_host succeeds');
    my @q;
    db_query("SELECT cname_txt,comment FROM hosts WHERE id=$addid", \@q);
    is_deeply($q[0], ['v=bar', 'c-row'], 'cname_txt and comment from the row');
};

cleanup();
done_testing();
