#!/usr/bin/env bash
# e2e-tests.sh — run DB integration and E2E tests inside the Sauron container.
#
# Mirrors the integration-tests job in .github/workflows/ci.yml. Expects to be
# started via docker-entrypoint.sh (DB initialized, PG* variables exported)
# with the repository mounted read-only at /src. Use `make test-e2e`.
set -euo pipefail

SAURON_HOME="${SAURON_HOME:-/usr/local/sauron}"
SRC_RO="${SRC_RO:-/src}"
WORK="${WORK:-/tmp/src}"

log() { printf '%s %s\n' "[sauron-e2e]" "$*"; }

# Tests create Sauron/DB.pm and zone files in the tree, so work on a copy.
log "Copying sources from $SRC_RO to $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"
tar -C "$SRC_RO" --exclude=./.git -cf - . | tar -C "$WORK" -xf -
cd "$WORK"

export PERL5LIB="$SAURON_HOME:$WORK"
export SAURON_INSTALL_DIR="$SAURON_HOME"
export SAURON_TEST_DSN="dbi:Pg:dbname=${PGDATABASE};host=${PGHOST};port=${PGPORT}"
export SAURON_TEST_USER="$PGUSER"
export SAURON_TEST_PASSWORD="$PGPASSWORD"
export POSTGRES_DB="$PGDATABASE"

log "Seeding test servers"
cat > /tmp/e2e-seed.sql <<'EOF'
INSERT INTO servers (name, hostname, hostmaster) VALUES ('example', 'sauron.example.com','hostmaster.example.com.');
INSERT INTO nets (server, net, netname, vlan, subnet)
  SELECT id, INET '10.10.0.0/16', 'net', 1, false FROM servers WHERE name='example';
INSERT INTO nets (server, net, netname, vlan, subnet)
  SELECT id, INET '2001:db8::/32', 'net6', 1, false FROM servers WHERE name='example';
INSERT INTO servers (name, hostname, hostmaster, ttl, refresh, retry, expire, minimum)
  VALUES ('roundtrip-test', 'ns1.roundtrip.example.com.', 'hostmaster.roundtrip.example.com.', 86400, 3600, 900, 604800, 86400);
INSERT INTO nets (server, net, netname, vlan, subnet)
  SELECT id, INET '10.20.0.0/16', 'roundtrip-net', 1, false FROM servers WHERE name='roundtrip-test';
INSERT INTO nets (server, net, netname, vlan, subnet)
  SELECT id, INET '2001:db8:20::/48', 'roundtrip-net6', 1, false FROM servers WHERE name='roundtrip-test';
EOF
"$SAURON_HOME/runsql" /tmp/e2e-seed.sql

log "Running integration and E2E tests"
rc=0
prove ${PROVE_OPTS:--l} t/1*.t || rc=$?

log "Generating config files for server 'example'"
mkdir -p /tmp/gen
"$SAURON_HOME/sauron" --bind example /tmp/gen || rc=$?
"$SAURON_HOME/sauron" --dhcp example /tmp/gen || rc=$?
"$SAURON_HOME/sauron" --dhcp6 example /tmp/gen || rc=$?

if [ "$rc" -eq 0 ]; then
	log "All E2E tests passed"
else
	log "E2E tests FAILED (exit $rc)"
fi
exit "$rc"
