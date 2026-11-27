#!/usr/bin/env bash
# lab/seed.sh - load the Sauron training lab data into an empty Sauron DB.
#
# Called by docker/entrypoint.sh on every start when SAURON_SEED=lab; does
# nothing when the lab data is already loaded. Can also be run by hand inside
# the container:
#   docker compose ... exec sauron /usr/local/sauron/lab/seed.sh
#
# The CLI tools commit step by step, so an interrupted seed cannot be rolled
# back; it is detected (no completion marker) and the lab must be reset.
set -euo pipefail

SAURON_HOME="${SAURON_HOME:-/usr/local/sauron}"
LAB_DIR="${LAB_DIR:-$(cd "$(dirname "$0")" && pwd)}"
DATA="$LAB_DIR/data"
LAB_USER="${SAURON_LAB_USER:-user}"
LAB_USER_PASSWORD="${SAURON_LAB_USER_PASSWORD:-user}"
ADMIN_USER="${SAURON_ADMIN_USER:-admin}"
MARKER=lab_seed   # settings row written as the last step

# psql connection: the entrypoint exports PG*, 'docker compose exec' sessions
# only have the SAURON_DB_* variables of the container
export PGHOST="${PGHOST:-${SAURON_DB_HOST:-db}}"
export PGPORT="${PGPORT:-${SAURON_DB_PORT:-5432}}"
export PGDATABASE="${PGDATABASE:-${SAURON_DB_NAME:-sauron}}"
export PGUSER="${PGUSER:-${SAURON_DB_USER:-sauron}}"
export PGPASSWORD="${PGPASSWORD:-${SAURON_DB_PASSWORD:-sauron}}"

log() { printf '%s %s\n' "[sauron-lab]" "$*"; }
# Sauron CLI tools often exit(db_commit()), i.e. 1 on success; check results
# with psql instead of relying on the exit status.
run() { "$@" >/dev/null || true; }
q() { psql -At -v ON_ERROR_STOP=1 -c "$1"; }
die() { log "ERROR: $*"; exit 1; }

[[ "$LAB_USER" =~ ^[a-z0-9_-]+$ ]] || die "invalid SAURON_LAB_USER '$LAB_USER'"
[[ "$ADMIN_USER" =~ ^[a-z0-9_-]+$ ]] || die "invalid SAURON_ADMIN_USER '$ADMIN_USER'"

if [ -n "$(q "SELECT 1 FROM settings WHERE setting='$MARKER'")" ]; then
  log "Lab data already loaded; nothing to do"
  exit 0
fi
if [ -n "$(q "SELECT 1 FROM servers WHERE name='lab'")" ]; then
  die "incomplete lab data from an interrupted seed; reset the lab" \
      "(docker compose ... down -v) and start it again"
fi

log "Creating server 'lab' and networks"
psql -q -v ON_ERROR_STOP=1 -1 -f "$DATA/seed.sql"

log "Importing zone lab.example"
"$SAURON_HOME/import-zone" lab lab.example "$DATA/lab.example.zone"

log "Creating reverse zones"
# zone names instead of CIDRs: addzone stores IPv6 CIDRs as "...ip6.arpa."
for zone in 2.0.192.in-addr.arpa 100.51.198.in-addr.arpa \
            0.1.0.0.8.b.d.0.1.0.0.2.ip6.arpa; do
  "$SAURON_HOME/addzone" lab "$zone" --reverse
done
# addzone does not set nameservers; use the same ones as lab.example
psql -q -v ON_ERROR_STOP=1 -1 <<'SQL'
INSERT INTO ns_entries (type, ref, ns)
  SELECT 2, h.id, n.ns
  FROM zones z JOIN servers s ON s.id = z.server
       JOIN hosts h ON h.zone = z.id AND h.domain = '@',
       (VALUES ('ns1.lab.example.'), ('ns2.lab.example.')) AS n(ns)
  WHERE s.name = 'lab' AND z.reverse;
SQL

log "Setting users and MAC addresses of hosts"
psql -q -v ON_ERROR_STOP=1 -1 <<'SQL'
-- 'User' is required when a restricted user edits a host
UPDATE hosts h SET huser = 'Lab IT'
  FROM zones z, servers s
  WHERE h.zone = z.id AND z.server = s.id AND s.name = 'lab'
    AND z.name = 'lab.example' AND h.type = 1;
UPDATE hosts h SET huser = u.huser
  FROM zones z, servers s,
  (VALUES ('pc-alice', 'Alice'), ('pc-bob', 'Bob'),
          ('printer-1', 'Office')) AS u(domain, huser)
  WHERE h.zone = z.id AND z.server = s.id AND s.name = 'lab'
    AND z.name = 'lab.example' AND h.domain = u.domain;
UPDATE hosts h SET ether = m.ether
  FROM zones z, servers s,
  (VALUES ('pc-alice', '00163E000020'), ('pc-bob', '00163E000021'),
          ('printer-1', '00163E000030')) AS m(domain, ether)
  WHERE h.zone = z.id AND z.server = s.id AND s.name = 'lab'
    AND z.name = 'lab.example' AND h.domain = m.domain;
SQL

log "Creating user group 'lab-users' and user '$LAB_USER'"
run "$SAURON_HOME/addgroup" --group=lab-users --name="Lab users"
run "$SAURON_HOME/modgroup" lab-users --add="server,lab,R"
run "$SAURON_HOME/modgroup" lab-users --add="zone,lab+lab.example,RW"
run "$SAURON_HOME/modgroup" lab-users --add="net,lab+192.0.2.0/25"
run "$SAURON_HOME/modgroup" lab-users --add="net,lab+192.0.2.128/25"
run "$SAURON_HOME/modgroup" lab-users --add="net,lab+2001:db8:10:1::/64"
run "$SAURON_HOME/modgroup" lab-users --add="flag,CNAME"
run "$SAURON_HOME/modgroup" lab-users --add="flag,DHCP"
# host fields required from restricted users (0 = required): keep only
# 'User' (who the record is for), make Dept., Location and MAC optional
for f in dept location ether; do
  run "$SAURON_HOME/modgroup" lab-users --add="rhf,$f=1"
done

run "$SAURON_HOME/adduser" --user="$LAB_USER" --passwd="$LAB_USER_PASSWORD" \
  --name="Lab User" --email="user@lab.example" --comment="lab user"
run "$SAURON_HOME/moduser" "$LAB_USER" --add="group,lab-users"
run "$SAURON_HOME/moduser" "$LAB_USER" --set="zone,lab,lab.example"
run "$SAURON_HOME/moduser" "$ADMIN_USER" --set="zone,lab,lab.example"

# the CLI tools above do not report failures reliably, check the result
rights=$(q "SELECT count(*) FROM user_rights r JOIN user_groups g
            ON r.type=1 AND r.ref=g.id WHERE g.name='lab-users'")
[ "$rights" -eq 10 ] || die "group lab-users has $rights privileges, expected 10"
[ -n "$(q "SELECT 1 FROM users u JOIN user_rights r ON r.type=2 AND r.ref=u.id
           AND r.rtype=0 JOIN user_groups g ON g.id=r.rref
           WHERE u.username='$LAB_USER' AND g.name='lab-users'")" ] \
  || die "user '$LAB_USER' was not created or is not in group lab-users"

q "INSERT INTO settings (setting, value) VALUES ('$MARKER', 'complete')" >/dev/null
log "Lab data loaded"
