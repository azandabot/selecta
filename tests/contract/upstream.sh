#!/bin/sh
# Contract tests: does upstream still look the way the resolver assumes?
#
# Scheduled nightly, never on pull requests. A provider outage is not a
# contributor's fault and must not redden their branch.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-contract
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/cache"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/resolve.sh
. "$SELECTA_ROOT/lib/resolve.sh"
# shellcheck source=lib/resolve-net.sh
. "$SELECTA_ROOT/lib/resolve-net.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

# One retry. radio-browser currently resolves to a single host and intermittently
# returns an empty body; a transient blip should not open an issue.
get() {
	_g=$(curl -sS --max-time 20 -A "$SELECTA_USER_AGENT" "$1" 2>/dev/null)
	if [ -z "$_g" ]; then
		sleep 2
		_g=$(curl -sS --max-time 20 -A "$SELECTA_USER_AGENT" "$1" 2>/dev/null)
	fi
	printf '%s' "$_g"
}

# --- somafm -----------------------------------------------------------------
SOMA=$(get https://somafm.com/channels.json)
t_eq "somafm returns channels" "true" "$(printf '%s' "$SOMA" | jq -r '(.channels|length) > 30' 2>/dev/null)"
t_eq "somafm channels keep id, title, genre" "true" \
	"$(printf '%s' "$SOMA" | jq -r '.channels|all(has("id") and has("title") and has("genre"))' 2>/dev/null)"
t_eq "somafm still offers mp3 playlists" "true" \
	"$(printf '%s' "$SOMA" | jq -r '.channels|all([.playlists[]|select(.format=="mp3")]|length > 0)' 2>/dev/null)"

PLS=$(get https://api.somafm.com/groovesalad256.pls)
t_eq "pls still uses FileN entries" "true" \
	"$(printf '%s' "$PLS" | grep -qE '^File1=https?://' && echo true || echo false)"
t_eq "pls still provides mirrors" "true" \
	"$([ "$(printf '%s' "$PLS" | grep -c '^File[0-9]')" -ge 2 ] && echo true || echo false)"

# Every station in the shipped seed must still exist upstream, or the offline
# fallback is quietly serving dead ids.
t_eq "seed station ids all still exist upstream" "true" \
	"$(printf '%s' "$SOMA" | jq -s -r --slurpfile seed "$SELECTA_ROOT/data/somafm-channels.seed.json" '
		(.[0].channels|map(.id)) as $live
		| $seed[0].channels|map(.id)|all(. as $i | $live|index($i) != null)' 2>/dev/null)"

# --- radio-browser ----------------------------------------------------------
RBH=$(selecta_rb_host)
t_ne "radio-browser resolves a host" "" "$RBH"
RB=$(get "https://$RBH/json/stations/search?tag=ambient&hidebroken=true&limit=5")
t_eq "radio-browser returns stations" "true" "$(printf '%s' "$RB" | jq -r 'length > 0' 2>/dev/null)"
t_eq "radio-browser keeps url_resolved and lastcheckok" "true" \
	"$(printf '%s' "$RB" | jq -r 'all(has("url_resolved") and has("lastcheckok") and has("stationuuid"))' 2>/dev/null)"

rm -rf "$SELECTA_HOME"
