# Sauron lab: úkoly

V labu běží Sauron s fiktivní organizací `lab.example`. Zóny a sítě
vypadají jako skutečné, adresy jsou z dokumentačních rozsahů
`192.0.2.0/24`, `198.51.100.0/24` a `2001:db8:10::/48`.

| Účet | Heslo | Role |
|---|---|---|
| `user` | `user` | běžný uživatel: RW na zónu `lab.example`, sítě `192.0.2.0/25` (kancelář), `192.0.2.128/25` (serverovna) a `2001:db8:10:1::/64`, příznaky CNAME, DHCP; Dept., Location a MAC nepovinné |
| `admin` | `admin` | superuživatel |

Úkoly **U** a **D** dělejte jako `user`, úkoly **A** jako `admin`. Na
pořadí nezáleží, jen U2, A1 a A2 potřebují host `web1` z U1.

Sauron zapisuje změny do své databáze. Na DNS a DHCP servery se dostanou až
vygenerováním konfigurace (příkaz `sauron`, obvykle z cronu). Do té doby se
změněný záznam zobrazuje jako *PENDING*. Kontrola generuje konfiguraci
stejně, vidí tedy přesně to, co by se nasadilo.

**Jak zkontrolovat postup:** ve webovém rozhraní otevřete *Hosts → Lab
tasks*, nebo v kontejneru spusťte `lab-check` (viz `lab/README.md`). Úkol je
splněný, když vygenerované zóny nebo `dhcpd.conf` obsahují očekávané
záznamy, bez ohledu na to, jakou cestou jste k nim došli.

## U1 Nový server web1

Kolega žádá o DNS záznam pro nový webový server (tiket RT#100001):

- jméno `web1.lab.example`, IPv4 adresa `192.0.2.160`
- *User*: pro koho záznam je, např. `Jan Novák` (pro běžné uživatele je
  v labu povinný)
- číslo tiketu `RT#100001` uveďte do *[Extra] Info*

Použijte *Hosts → Add host*, v poli *Subnet* zvolte `<Manual IP>` a zadejte
adresu. Pak ověřte, že existuje i reverzní (PTR) záznam: Sauron ho generuje
z adresy hostu, ručně se nepřidává.

Běžný uživatel dostane omezený formulář s jedinou IP adresou; IPv6 adresu
doplní admin v úkolu A1.

*Kontroluje se:* A záznam `web1`, PTR záznam `192.0.2.160`, číslo tiketu
v záznamu hostu.

## U2 Alias www pro web1

Přidejte alias `www.lab.example` (CNAME) směřující na `web1.lab.example`.
Tip: otevřete host `web1` a použijte tlačítko *Alias*.

*Kontroluje se:* `www.lab.example. CNAME web1.lab.example.`

## U3 Změna IP adresy db1 na 192.0.2.145

Databázový server `db1` se přestěhoval. Změňte jeho IPv4 adresu
z `192.0.2.140` na `192.0.2.145`.

*Kontroluje se:* `db1` má jen novou adresu, PTR záznam nové adresy ukazuje
na `db1`, stará adresa už na `db1` neukazuje.

## U4 Přejmenování phishingintel na phishingindex

Služba se přejmenovala. Přejmenujte host `phishingintel.lab.example` na
`phishingindex.lab.example`. Stávající alias `pi.lab.example` musí dál
fungovat, tedy ukazovat na nové jméno.

*Kontroluje se:* žádné záznamy pro `phishingintel`, `phishingindex` má
adresu `192.0.2.141` a odpovídající PTR záznam, `pi` ukazuje na
`phishingindex`.

## U5 Zrušení old-graylog včetně aliasu logs

Starý logovací server je vypnutý. Zrušte host `old-graylog.lab.example`
i s jeho aliasem `logs.lab.example`.

Aliasy hostu jsou v jeho detailu v sekci *Aliases*. Vyhledávání hostů
zobrazuje ve výchozím stavu jen hosty; aliasy najdete s *Record type: Any type*
(nebo *Alias*). Smazáním hostu se smažou i jeho CNAME aliasy.

*Kontroluje se:* žádné záznamy pro `old-graylog` a `logs`, žádný PTR záznam
pro `192.0.2.150`.

## U6 Server backup1 s první volnou adresou

Přidejte host `backup1.lab.example` do sítě serverovny `192.0.2.128/25`
a nechte Sauron vybrat první volnou adresu: místo zadání IP adresy vyberte
síť v poli *Subnet*.

*Kontroluje se:* `backup1` má právě jeden A záznam, adresa je ze sítě
`192.0.2.128/25` a má PTR záznam.

## A1 IPv6 adresa pro web1

Přihlaste se jako `admin`. Doplňte hostu `web1.lab.example` z U1 IPv6
adresu `2001:db8:10:1::160` (*Edit*; plný formulář dovolí víc adres).
Porovnejte formulář s omezeným, který dostane `user`.

*Kontroluje se:* AAAA záznam `web1`, jeho PTR záznam v zóně `ip6.arpa`,
A záznam zůstává.

## A2 ACME DNS-01 challenge pro web1

Pro vydání certifikátu pro `web1` potřebuje ACME klient TXT záznam:

- jméno `_acme-challenge.web1.lab.example`
- hodnota `lab-acme-Xy3Fq9`

Jako `admin` použijte *Hosts → Add TXT rec.* Jména s podtržítkem smí
zadávat jen uživatelé s vysokou úrovní oprávnění
(`$SAURON_DNSNAME_CHECK_LEVEL`, ve výchozím nastavení superuživatelé),
`user` to tedy neudělá. (V provozu to obvykle dělá automaticky
nástroj `acme-txt` z certbot hooku.)

*Kontroluje se:* `_acme-challenge.web1.lab.example. TXT "lab-acme-Xy3Fq9"`

## A3 Ověřovací TXT pro Google a CAA pro lab.example

Přihlaste se jako `admin`. V zóně `lab.example` (*Zones → Show current →
Edit*):

- přidejte TXT záznam `google-site-verification=lab-verify-0123456789`,
  stávající SPF záznam `v=spf1 mx -all` ponechte
- povolte vydávání certifikátů jen Let's Encrypt: CAA `0 issue
  "letsencrypt.org"`

*Kontroluje se:* oba TXT záznamy na vrcholu zóny, právě jeden CAA záznam.

## A4 Snížení TTL monitoring na 600 s před migrací

Host `monitoring.lab.example` se bude stěhovat do jiného datacentra. Aby se
přepnutí rychle projevilo, snižte TTL jeho záznamů na 600 sekund (nejnižší TTL, které Sauron ve výchozím nastavení dovolí).

*Kontroluje se:* A a AAAA záznam `monitoring` mají TTL 600.

## A5 Nová zóna shop.lab.example s poštovními záznamy

Vytvořte na serveru `lab` master zónu `shop.lab.example` s:

- NS `ns1.lab.example.` a `ns2.lab.example.`
- MX `10 mail.lab.example.`
- TXT (SPF) `v=spf1 mx -all`
- TXT záznam `_dmarc.shop.lab.example` s hodnotou
  `v=DMARC1; p=none; rua=mailto:dmarc@lab.example`
- TXT záznam `selector1._domainkey.shop.lab.example` (DKIM) s hodnotou
  `v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlabKEY`

Jména hostů jsou v Sauronu relativní k vybrané zóně (ukazuje ji lišta pod
horním menu). Zónu vytvořte, vyberte ji (*Zones*) a TXT záznamy přidejte
přes *Hosts → Add TXT rec.* se jmény `_dmarc` a `selector1._domainkey`;
zadáním `_dmarc.shop` by vzniklo `_dmarc.shop.shop.lab.example`.

*Kontroluje se:* uvedené záznamy ve vygenerované zóně `shop.lab.example`.

## A6 Delegace team.lab.example (NS, glue, DS)

Tým provozuje vlastní DNS server pro `team.lab.example`. Delegujte na něj
subdoménu v zóně `lab.example`. Pokud pokračujete z A5, nejdřív znovu
vyberte zónu `lab.example` (*Zones*), jinak delegace vznikne jako
`team.shop.lab.example`.

- delegace `team` s NS `ns1.team.lab.example.` a DS záznamem
  `12345 13 2 3f1a6c3e9b2d4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f90`
- glue záznam `ns1.team` s adresou `198.51.100.60`

*Kontroluje se:* NS, DS a glue A záznam v zóně `lab.example`.

## A7 Nová síť 198.51.100.128/26 pro uživatele labu

Vytvořte podsíť `198.51.100.128/26` se jménem `vms` (virtuální stroje)
a povolte uživateli `user` spravovat v ní hosty.

Síť vytvořte ve webovém rozhraní (*Nets → Add net*). Oprávnění se spravují
z příkazové řádky: otevřete shell v kontejneru (viz `lab/README.md`) a dejte
oprávnění skupině `lab-users`, jejímž členem `user` je:

    /usr/local/sauron/modgroup lab-users --add="net,lab+198.51.100.128/26"

`/usr/local/sauron/moduser user` vypíše oprávnění uživatele.

*Kontroluje se:* síť existuje a `user` na ni má oprávnění.

## D1 DHCP rezervace pro pc-carol

Nový počítač v kanceláři potřebuje pevnou adresu z DHCP:

- jméno `pc-carol.lab.example`, adresa `192.0.2.22`
- MAC adresa `00:16:3e:00:00:22`

*Kontroluje se:* A záznam `pc-carol` a položka `host` s MAC a adresou ve
vygenerovaném `dhcpd.conf`.

## D2 Výměna síťové karty v pc-bob

V `pc-bob.lab.example` vyměnili síťovou kartu. Změňte jeho MAC adresu na
`00:16:3e:00:00:99`, IP adresa zůstává.

*Kontroluje se:* `dhcpd.conf` obsahuje pro `pc-bob` novou MAC adresu.
