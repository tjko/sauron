# Sauron lab: tasks

The lab runs a Sauron instance with the fictitious organisation
`lab.example`. Its zones and networks look like real ones, with addresses from
the documentation ranges `192.0.2.0/24`, `198.51.100.0/24` and
`2001:db8:10::/48`.

| Account | Password | Role |
|---|---|---|
| `user` | `user` | ordinary user: RW on zone `lab.example`, networks `192.0.2.0/25` (office), `192.0.2.128/25` (server room) and `2001:db8:10:1::/64`, flags CNAME, DHCP; Dept., Location and MAC optional |
| `admin` | `admin` | superuser |

Do the **U** and **D** tasks as `user` and the **A** tasks as `admin`. The
order does not matter, except that U2, A1 and A2 need the host `web1` from U1.

Sauron writes changes into its database. They reach the DNS and DHCP servers
only when the configuration is generated (`sauron` command, normally run
from cron). Until then a changed record shows as *PENDING*. The check
generates the configuration the same way, so it sees exactly what would be
deployed.

**How to check your progress:** open *Hosts → Lab tasks* in the web UI, or
run `lab-check` in the container (see `lab/README.md`). A task is done when
the generated zones or `dhcpd.conf` contain the expected records, however you
got there.

## U1 New server web1

A colleague asks for a DNS record for a new web server (ticket RT#100001):

- name `web1.lab.example`, IPv4 address `192.0.2.160`
- *User*: the person the record is for, e.g. `Jan Novak` (a required field
  for ordinary users in this lab)
- put the ticket number `RT#100001` into *[Extra] Info*

Use *Hosts → Add host*, choose `<Manual IP>` in *Subnet* and type the
address. Then check that the reverse (PTR) record exists as well: Sauron
generates it from the host's address, you do not add it by hand.

Ordinary users get a restricted form with a single IP address; the IPv6
address is added by the admin in task A1.

*Checked:* A record of `web1`, PTR record of `192.0.2.160`, the ticket
number in the host record.

## U2 Alias www for web1

Add the alias `www.lab.example` (CNAME) pointing to `web1.lab.example`.
Hint: open the host `web1` and use the *Alias* button.

*Checked:* `www.lab.example. CNAME web1.lab.example.`

## U3 Move db1 to 192.0.2.145

The database server `db1` moved to a new address. Change its IPv4 address
from `192.0.2.140` to `192.0.2.145`.

*Checked:* `db1` has only the new address, the PTR record of the new
address points to `db1`, the old address no longer points to `db1`.

## U4 Rename phishingintel to phishingindex

The service was renamed. Rename the host `phishingintel.lab.example` to
`phishingindex.lab.example`. The existing alias `pi.lab.example` must keep
working, so it points to the new name.

*Checked:* no records for `phishingintel`, `phishingindex` has address
`192.0.2.141` and a matching PTR record, `pi` points to `phishingindex`.

## U5 Remove old-graylog and its alias logs

The old log server is shut down. Remove the host `old-graylog.lab.example`
together with its alias `logs.lab.example`.

The aliases of a host are listed in its detail under *Aliases*. The host
search shows only hosts by default; choose *Record type: Any type* (or *Alias*)
to find aliases too. Deleting a host deletes its CNAME aliases as well.

*Checked:* no records for `old-graylog` and `logs`, no PTR record for
`192.0.2.150`.

## U6 Server backup1 with the next free address

Add the host `backup1.lab.example` into the server room network
`192.0.2.128/25` and let Sauron pick the first free address: choose the
network in *Subnet* instead of typing the IP address.

*Checked:* `backup1` has exactly one A record, the address is from
`192.0.2.128/25` and has a PTR record.

## A1 IPv6 address for web1

Log in as `admin`. Add the IPv6 address `2001:db8:10:1::160` to the host
`web1.lab.example` from U1 (*Edit*; the full edit form allows several
addresses). Compare the form with the restricted one `user` gets.

*Checked:* AAAA record of `web1`, its PTR record in the `ip6.arpa` zone,
the A record stays.

## A2 ACME DNS-01 challenge for web1

To get a certificate for `web1`, the ACME client needs a TXT record:

- name `_acme-challenge.web1.lab.example`
- value `lab-acme-Xy3Fq9`

As `admin`, use *Hosts → Add TXT rec.* Names with an underscore are
allowed only to users with a high authorization level
(`$SAURON_DNSNAME_CHECK_LEVEL`, superusers by default), so `user` cannot
do this. (In production this is usually done
automatically by the `acme-txt` tool from a certbot hook.)

*Checked:* `_acme-challenge.web1.lab.example. TXT "lab-acme-Xy3Fq9"`

## A3 Google verification TXT and CAA for lab.example

Log in as `admin`. In the zone `lab.example` (*Zones → Show current →
Edit*):

- add the TXT record `google-site-verification=lab-verify-0123456789`,
  keep the existing SPF record `v=spf1 mx -all`
- allow only Let's Encrypt to issue certificates: CAA `0 issue
  "letsencrypt.org"`

*Checked:* both TXT records at the zone apex, exactly one CAA record.

## A4 Lower TTL of monitoring to 600 s before migration

The host `monitoring.lab.example` will move to another data centre. To make
the switch fast, lower the TTL of its records to 600 seconds (the lowest TTL Sauron allows by default).

*Checked:* the A and AAAA records of `monitoring` have TTL 600.

## A5 New zone shop.lab.example with mail records

Create the master zone `shop.lab.example` on the server `lab` with:

- NS `ns1.lab.example.` and `ns2.lab.example.`
- MX `10 mail.lab.example.`
- TXT (SPF) `v=spf1 mx -all`
- TXT record `_dmarc.shop.lab.example` with value
  `v=DMARC1; p=none; rua=mailto:dmarc@lab.example`
- TXT record `selector1._domainkey.shop.lab.example` (DKIM) with value
  `v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlabKEY`

Host names in Sauron are relative to the selected zone (shown in the bar
below the top menu). Create the zone, select it (*Zones*) and add the TXT
records as *Hosts → Add TXT rec.* with the names `_dmarc` and
`selector1._domainkey`; typing `_dmarc.shop` would create
`_dmarc.shop.shop.lab.example`.

*Checked:* the records above in the generated zone `shop.lab.example`.

## A6 Delegate team.lab.example (NS, glue, DS)

The team runs its own DNS server for `team.lab.example`. Delegate the
subdomain to it in the zone `lab.example`. If you come from A5, select
`lab.example` again first (*Zones*), otherwise the delegation ends up as
`team.shop.lab.example`.

- delegation `team` with NS `ns1.team.lab.example.` and DS record
  `12345 13 2 3f1a6c3e9b2d4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f90`
- glue record `ns1.team` with address `198.51.100.60`

*Checked:* NS, DS and glue A record in the zone `lab.example`.

## A7 New network 198.51.100.128/26 for the lab user

Create the subnet `198.51.100.128/26` named `vms` (virtual machines) and
allow the user `user` to manage hosts in it.

Create the network in the web UI (*Nets → Add net*). Privileges are managed
on the command line: open a shell in the container (see `lab/README.md`)
and give the privilege to the group `lab-users`, which `user` is a member of:

    /usr/local/sauron/modgroup lab-users --add="net,lab+198.51.100.128/26"

`/usr/local/sauron/moduser user` lists the user's privileges.

*Checked:* the network exists and `user` has a privilege for it.

## D1 DHCP reservation for pc-carol

A new office computer needs a fixed address from DHCP:

- name `pc-carol.lab.example`, address `192.0.2.22`
- MAC address `00:16:3e:00:00:22`

*Checked:* A record of `pc-carol` and a `host` entry with the MAC and the
address in the generated `dhcpd.conf`.

## D2 New network card in pc-bob

The network card of `pc-bob.lab.example` was replaced. Change its MAC
address to `00:16:3e:00:00:99`; the IP address stays the same.

*Checked:* `dhcpd.conf` has the new MAC address for `pc-bob`.
