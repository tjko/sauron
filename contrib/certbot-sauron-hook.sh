#!/bin/sh
#
# certbot-sauron-hook.sh - certbot DNS-01 hook using acme-txt over SSH
#
# Use the same script for both hooks:
#
#   certbot certonly --manual --preferred-challenges dns \
#     --manual-auth-hook    "/usr/local/bin/certbot-sauron-hook.sh auth" \
#     --manual-cleanup-hook "/usr/local/bin/certbot-sauron-hook.sh cleanup" \
#     -d example.cz -d '*.example.cz'
#
# The SSH key must be restricted on the Sauron host to a forced command, e.g.
#   restrict,command="/usr/local/sauron/acme-txt --server=S --zone=example.cz --ssh" ssh-ed25519 ...
#
# The Sauron host key must be in root's known_hosts (BatchMode is used):
#   ssh-keyscan sauron.example.net >> /root/.ssh/known_hosts
#
# Settings (environment or /etc/default/certbot-sauron-hook):
#   SAURON_SSH       user@host of the Sauron account          (required)
#   SAURON_SSH_KEY   private key                              (default ~/.ssh/id_ed25519)
#   SAURON_WAIT      max seconds to wait for publication       (default 1800)
#   SAURON_INTERVAL  seconds between DNS checks                (default 30)
#
# The auth hook returns only after every authoritative name server of the
# zone answers with the new value (Sauron publishes changes when its export
# job runs, so this may take until the next run).
#
set -eu

[ -r /etc/default/certbot-sauron-hook ] && . /etc/default/certbot-sauron-hook

: "${SAURON_SSH:?SAURON_SSH (user@host) is not set}"
SAURON_SSH_KEY="${SAURON_SSH_KEY:-$HOME/.ssh/id_ed25519}"
SAURON_WAIT="${SAURON_WAIT:-1800}"
SAURON_INTERVAL="${SAURON_INTERVAL:-30}"
: "${CERTBOT_DOMAIN:?not run from certbot}"
: "${CERTBOT_VALIDATION:?not run from certbot}"

name="_acme-challenge.${CERTBOT_DOMAIN}"

sauron() {
	ssh -i "$SAURON_SSH_KEY" -o BatchMode=yes "$SAURON_SSH" \
		"$1 $name $CERTBOT_VALIDATION"
}

# authoritative name servers: walk up from the name to the zone with NS
auth_servers() {
	d="$CERTBOT_DOMAIN"
	while [ -n "$d" ]; do
		# only NS records owned by $d itself (+short would also print
		# the target of a CNAME at $d and stop the search too early)
		ns=$(dig +noall +answer NS "$d" |
			awk -v n="$d." 'tolower($1) == tolower(n) && $4 == "NS" { print $5 }' ||
			true)
		if [ -n "$ns" ]; then
			echo "$ns"
			return
		fi
		case "$d" in *.*) d="${d#*.}" ;; *) d="" ;; esac
	done
}

published() {
	servers=$(auth_servers)
	[ -n "$servers" ] || return 1
	for ns in $servers; do
		dig +short +norecurse TXT "$name" "@$ns" |
			grep -qF "\"$CERTBOT_VALIDATION\"" || return 1
	done
	return 0
}

case "${1:-}" in
auth)
	sauron add
	waited=0
	until published; do
		if [ "$waited" -ge "$SAURON_WAIT" ]; then
			echo "$name not published after ${SAURON_WAIT}s" >&2
			exit 1
		fi
		sleep "$SAURON_INTERVAL"
		waited=$((waited + SAURON_INTERVAL))
	done
	;;
cleanup)
	sauron del
	;;
*)
	echo "usage: $0 auth|cleanup" >&2
	exit 1
	;;
esac
