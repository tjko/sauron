# tasks.pl - task definitions of the Sauron training lab (loaded by lab-check)
#
# Each task: id, role (user|admin|dhcp), title {en,cs} and a check sub that
# records checked points with the helpers from lab-check (expect_rr,
# expect_ptr, check, ...). Keep ids, titles and values in sync with tasks.en.md and
# tasks.cs.md, and with the reference solution in solve.
#
# Values used by the tasks. Documentation ranges only (RFC 5737, RFC 3849).
use strict;
use warnings;
use utf8;

my $Z     = 'lab.example';
my $ACME  = 'lab-acme-Xy3Fq9';
my $GOOGLE= 'google-site-verification=lab-verify-0123456789';
my $DMARC = 'v=DMARC1; p=none; rua=mailto:dmarc@lab.example';
my $DKIM  = 'v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlabKEY';
my $DS    = '12345 13 2 3f1a6c3e9b2d4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f90';

(
  # ---------------------------------------------------------------- user
  { id => 'U1', role => 'user',
    title => { en => 'New server web1 (A, PTR, ticket number)',
               cs => 'Nový server web1 (A, PTR, číslo tiketu)' },
    check => sub {
      expect_only_rr("web1.$Z", 'A', '192.0.2.160');
      expect_ptr('192.0.2.160', "web1.$Z");
      my $h = host_by_name("web1.$Z");
      check($h && join(' ', grep { defined } @$h{qw(comment info)}) =~ /RT#?\s*100001/i,
            t(en => 'ticket RT#100001 in [Extra] Info or comment of web1',
              cs => 'tiket RT#100001 v [Extra] Info nebo komentáři web1'));
    } },

  { id => 'U2', role => 'user',
    title => { en => 'Alias www for web1', cs => 'Alias www pro web1' },
    check => sub {
      expect_only_rr("www.$Z", 'CNAME', "web1.$Z");
    } },

  { id => 'U3', role => 'user',
    title => { en => 'Move db1 to 192.0.2.145', cs => 'Změna IP adresy db1 na 192.0.2.145' },
    check => sub {
      expect_only_rr("db1.$Z", 'A', '192.0.2.145');
      expect_ptr('192.0.2.145', "db1.$Z");
      # the old address may be reused by another host, just not by db1
      expect_no_rr(ptr_name('192.0.2.140'), 'PTR', "db1.$Z");
    } },

  { id => 'U4', role => 'user',
    title => { en => 'Rename phishingintel to phishingindex',
               cs => 'Přejmenování phishingintel na phishingindex' },
    check => sub {
      expect_no_name("phishingintel.$Z");
      expect_only_rr("phishingindex.$Z", 'A', '192.0.2.141');
      expect_ptr('192.0.2.141', "phishingindex.$Z");
      expect_only_rr("pi.$Z", 'CNAME', "phishingindex.$Z");
    } },

  { id => 'U5', role => 'user',
    title => { en => 'Remove old-graylog and its alias logs',
               cs => 'Zrušení old-graylog včetně aliasu logs' },
    check => sub {
      expect_no_name("old-graylog.$Z");
      expect_no_name("logs.$Z");
      expect_no_ptr('192.0.2.150');
    } },

  { id => 'U6', role => 'user',
    title => { en => 'Server backup1 with the next free address',
               cs => 'Server backup1 s první volnou adresou' },
    check => sub {
      my @a = rrs("backup1.$Z", 'A');
      my $net = Net::IP->new('192.0.2.128/25');
      check(@a == 1, t(en => 'backup1 has exactly one A record (has ' . scalar(@a) . ')',
                       cs => 'backup1 má právě jeden A záznam (má ' . scalar(@a) . ')'))
        or return;
      my $ip = $a[0]->address;
      check($net->overlaps(Net::IP->new($ip)) == $IP_B_IN_A_OVERLAP,
            t(en => "address of backup1 ($ip) is in the server room network 192.0.2.128/25",
              cs => "adresa backup1 ($ip) je ze sítě serverovny 192.0.2.128/25"));
      expect_ptr($ip, "backup1.$Z");
    } },

  # --------------------------------------------------------------- admin
  { id => 'A1', role => 'admin',
    title => { en => 'IPv6 address for web1', cs => 'IPv6 adresa pro web1' },
    check => sub {
      expect_only_rr("web1.$Z", 'AAAA', '2001:db8:10:1::160');
      expect_ptr('2001:db8:10:1::160', "web1.$Z");
      expect_rr("web1.$Z", 'A', '192.0.2.160');
    } },

  { id => 'A2', role => 'admin',
    title => { en => 'ACME DNS-01 challenge for web1', cs => 'ACME DNS-01 challenge pro web1' },
    check => sub {
      expect_only_rr("_acme-challenge.web1.$Z", 'TXT', $ACME);
    } },

  { id => 'A3', role => 'admin',
    title => { en => 'Google verification TXT and CAA for lab.example',
               cs => 'Ověřovací TXT pro Google a CAA pro lab.example' },
    check => sub {
      expect_rr($Z, 'TXT', $GOOGLE);
      expect_rr($Z, 'TXT', 'v=spf1 mx -all');
      expect_only_rr($Z, 'CAA', '0 issue "letsencrypt.org"');
    } },

  { id => 'A4', role => 'admin',
    title => { en => 'Lower TTL of monitoring to 600 s before migration',
               cs => 'Snížení TTL monitoring na 600 s před migrací' },
    check => sub {
      expect_ttl("monitoring.$Z", 'A', 600);
      expect_ttl("monitoring.$Z", 'AAAA', 600);
    } },

  { id => 'A5', role => 'admin',
    title => { en => 'New zone shop.lab.example with mail records',
               cs => 'Nová zóna shop.lab.example s poštovními záznamy' },
    check => sub {
      my $s = "shop.$Z";
      expect_only_rr($s, 'NS', "ns1.$Z", "ns2.$Z");
      expect_only_rr($s, 'MX', "10 mail.$Z");
      expect_only_rr($s, 'TXT', 'v=spf1 mx -all');
      expect_only_rr("_dmarc.$s", 'TXT', $DMARC);
      expect_only_rr("selector1._domainkey.$s", 'TXT', $DKIM);
    } },

  { id => 'A6', role => 'admin',
    title => { en => 'Delegate team.lab.example (NS, glue, DS)',
               cs => 'Delegace team.lab.example (NS, glue, DS)' },
    check => sub {
      expect_only_rr("team.$Z", 'NS', "ns1.team.$Z");
      expect_only_rr("ns1.team.$Z", 'A', '198.51.100.60');
      expect_only_rr("team.$Z", 'DS', $DS);
    } },

  { id => 'A7', role => 'admin',
    title => { en => 'New network 198.51.100.128/26 for the lab user',
               cs => 'Nová síť 198.51.100.128/26 pro uživatele labu' },
    check => sub {
      my $sid = server_id() // 0;
      my $net = db_one("SELECT id FROM nets WHERE server=$sid AND net='198.51.100.128/26'");
      check($net, t(en => 'network 198.51.100.128/26 exists',
                    cs => 'síť 198.51.100.128/26 existuje'))
        or return;
      # every lab user needs the privilege, directly or through a group
      my @users = lab_users();
      check(scalar @users, t(en => "group $main::LAB_GROUP has members",
                             cs => "skupina $main::LAB_GROUP má členy"))
        or return;
      for my $u (@users) {
        my $ok = db_one(
          "SELECT 1 FROM user_rights r, users u WHERE u.username=" . sq($u) . " AND r.rtype=3 " .
          "AND r.rref=$net AND ((r.type=2 AND r.ref=u.id) OR (r.type=1 AND r.ref IN " .
          "(SELECT g.rref FROM user_rights g WHERE g.type=2 AND g.ref=u.id AND g.rtype=0)))");
        check($ok, t(en => "user $u has a privilege for network 198.51.100.128/26",
                     cs => "uživatel $u má oprávnění na síť 198.51.100.128/26"));
      }
    } },

  # ---------------------------------------------------------------- dhcp
  { id => 'D1', role => 'dhcp',
    title => { en => 'DHCP reservation for pc-carol', cs => 'DHCP rezervace pro pc-carol' },
    check => sub {
      expect_only_rr("pc-carol.$Z", 'A', '192.0.2.22');
      my $b = dhcp_host_block('pc-carol');
      check(defined $b, t(en => 'dhcpd.conf has host pc-carol', cs => 'dhcpd.conf obsahuje host pc-carol'))
        or return;
      check($b =~ /hardware\s+ethernet\s+00:16:3e:00:00:22\s*;/i,
            t(en => 'pc-carol: hardware ethernet 00:16:3e:00:00:22',
              cs => 'pc-carol: hardware ethernet 00:16:3e:00:00:22'));
      check($b =~ /fixed-address\s+(?:192\.0\.2\.22|pc-carol\.lab\.example\.?)\s*;/i,
            t(en => 'pc-carol: fixed-address 192.0.2.22', cs => 'pc-carol: fixed-address 192.0.2.22'));
    } },

  { id => 'D2', role => 'dhcp',
    title => { en => 'New network card in pc-bob', cs => 'Výměna síťové karty v pc-bob' },
    check => sub {
      my $b = dhcp_host_block('pc-bob');
      check(defined $b && $b =~ /hardware\s+ethernet\s+00:16:3e:00:00:99\s*;/i,
            t(en => 'pc-bob: hardware ethernet 00:16:3e:00:00:99',
              cs => 'pc-bob: hardware ethernet 00:16:3e:00:00:99'));
      expect_only_rr("pc-bob.$Z", 'A', '192.0.2.21');
    } },
);
