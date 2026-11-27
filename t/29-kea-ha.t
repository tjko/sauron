#!/usr/bin/perl
# t/29-kea-ha.t - KEA High Availability settings from the failover
#                 settings of master/slave servers (dhcp_ha_from_db)
#
# Skipped unless SAURON_TEST_DSN is set.
#
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use Test::More;

my $db_link = "$FindBin::Bin/../Sauron/DB.pm";
unless (-e $db_link) {
    symlink("DB-DBI.pm", $db_link) or die "Cannot create DB.pm symlink: $!";
}

our $SAURON_DNSNAME_CHECK_LEVEL = 0;
our %perms = (alevel => 0);
our $DB_DSN      = $ENV{SAURON_TEST_DSN}      || '';
our $DB_USER     = $ENV{SAURON_TEST_USER}     || '';
our $DB_PASSWORD = $ENV{SAURON_TEST_PASSWORD} || '';

plan skip_all => 'Set SAURON_TEST_DSN to run KEA HA DB tests' unless ($DB_DSN);

use Sauron::DB;
use Sauron::BackEnd;
use Sauron::DhcpDB;

db_connect2() or plan skip_all => 'Cannot connect to test database';
set_muser('kea-ha-test');

my @names = ('ha-s2', 'ha-s1', 'ha-m');
sub id_of {
    my @r;
    db_query("SELECT id FROM servers WHERE name='$_[0]'", \@r);
    return @r ? $r[0][0] : undef;
}
sub cleanup { foreach (@names) { my $id = id_of($_); delete_server($id) if ($id); } }
cleanup();

db_exec("INSERT INTO servers (name,hostname,hostmaster,hostaddr,dhcp_flags,df_split,df_max_delay) " .
        "VALUES ('ha-m','m.ha.test.','h.ha.test.','192.0.2.1',2,0,5)");
my $mid = id_of('ha-m');
db_exec("INSERT INTO servers (name,hostname,hostmaster,hostaddr,masterserver) " .
        "VALUES ('ha-s1','s1.ha.test.','h.ha.test.','2001:db8::2',$mid)");
db_exec("INSERT INTO servers (name,hostname,hostmaster,masterserver) " .
        "VALUES ('ha-s2','s2.ha.test.','h.ha.test.',$mid)");

sub ha {
    my ($name, $family) = @_;
    my (%s, %m, @w);
    get_server(id_of($name), \%s);
    get_server($s{masterserver}, \%m) if ($s{masterserver} > 0);
    my $ha = dhcp_ha_from_db({ server => \%s, masterserver => \%m, family => $family,
                               warn => sub { push @w, $_[0] } });
    return ($ha, \@w);
}

my ($ha, $w) = ha('ha-m', 4);
is($ha->{mode}, 'hot-standby', 'split 0 = hot-standby');
is_deeply([ map { "$_->{name} $_->{role} $_->{url}" } @{$ha->{peers}} ],
          [ 'ha-s1 primary http://[2001:db8::2]:8001/', 'ha-m standby http://192.0.2.1:8001/' ],
          'split 0: the slave is the active server; IPv6 address in brackets');
is($ha->{max_response_delay}, 5000, 'max-response-delay in ms');
ok((grep { /several slaves of ha-m: High Availability partner is ha-s1, not ha-s2/ } @$w),
   'other slaves reported');

($ha, $w) = ha('ha-s1', 4);
is($ha->{this}, 'ha-s1', 'partner slave gets HA');
($ha, $w) = ha('ha-s2', 4);
ok(!$ha, 'other slave gets no HA');
like($w->[0], qr/ha-s2 is not the High Availability partner of ha-m \(that is ha-s1\)/, 'reported');

($ha, $w) = ha('ha-m', 6);
ok(!$ha, 'DHCPv6 failover off: no HA');

db_exec("UPDATE servers SET df_split=100, hostaddr=NULL WHERE id=$mid");
($ha, $w) = ha('ha-s1', 4);
ok(!$ha, 'missing IP address: no HA');
ok((grep { /split 100: KEA load-balancing always splits clients evenly/ } @$w),
   'uneven split reported');
ok((grep { /server ha-m has no IP address/ } @$w), 'missing IP reported');

cleanup();
done_testing();
