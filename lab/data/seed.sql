-- Sauron lab: server and networks (loaded by lab/seed.sh before the zones)
INSERT INTO servers (name, hostname, hostmaster, comment)
  VALUES ('lab', 'ns1.lab.example.', 'hostmaster.lab.example.', 'Sauron training lab');

-- top-level blocks (subnet=false) and their subnets
-- range_start/range_end: pool for "next free address" in the web UI
INSERT INTO nets (server, netname, name, net, subnet, no_dhcp, range_start, range_end, comment)
  SELECT id, n.netname, n.name, n.net::cidr, n.subnet, n.no_dhcp,
         n.range_start::inet, n.range_end::inet, n.comment
  FROM servers,
  (VALUES
    ('lab-v4',   'Lab internal block',  '192.0.2.0/24',       false, false, NULL, NULL, 'RFC 5737 documentation range'),
    ('office',   'Office workstations', '192.0.2.0/25',       true,  false, '192.0.2.20', '192.0.2.120', 'DHCP reservations'),
    ('servers',  'Server room',         '192.0.2.128/25',     true,  true,  '192.0.2.140', '192.0.2.250', 'static addresses only'),
    ('lab-pub',  'Lab public block',    '198.51.100.0/24',    false, true,  NULL, NULL, 'RFC 5737 documentation range'),
    ('dmz',      'DMZ',                 '198.51.100.0/25',    true,  true,  '198.51.100.10', '198.51.100.120', 'public services'),
    ('lab-v6',   'Lab IPv6 block',      '2001:db8:10::/48',   false, true,  NULL, NULL, 'RFC 3849 documentation range'),
    ('servers6', 'Server room (IPv6)',  '2001:db8:10:1::/64', true,  true,  '2001:db8:10:1::100', '2001:db8:10:1::1ff', NULL)
  ) AS n(netname, name, net, subnet, no_dhcp, range_start, range_end, comment)
  WHERE servers.name = 'lab';
