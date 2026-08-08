#!/bin/sh
# Drives the README demo end to end, for an asciinema recording.
#
# The arc is install -> play -> what you get, because that is the order a
# viewer needs it in. It runs against a throwaway SELECTA_HOME and a seeded
# demo repo, so the crate looks lived-in instead of empty on the first frame.
#
#   demo/seed.sh                       build the demo repo
#   asciinema rec demo.cast -c demo/record.sh
#   agg --theme asciinema demo.cast demo.gif
#
# SELECTA_AO=null rehearses it silently. SELECTA_DEMO_FAST=1 skips the pauses.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
DEMO=${SELECTA_DEMO_DIR:-${TMPDIR:-/tmp}/selecta-demo}
SELECTA_HOME="$DEMO/home"
export SELECTA_HOME
REPO="$DEMO/demo-api"

[ -d "$REPO" ] || {
	printf 'Run demo/seed.sh first.\n' >&2
	exit 1
}
cd "$REPO"
S=$ROOT/bin/selecta

# Typing is simulated rather than instant: a wall of output with no visible
# cause reads as a screenshot, not a demo.
DIM=$(printf '\033[2m')
OFF=$(printf '\033[0m')
CYAN=$(printf '\033[36m')

beat() { [ -n "${SELECTA_DEMO_FAST:-}" ] || sleep "$1"; }

type_cmd() {
	printf '%s$%s ' "$DIM" "$OFF"
	_t=$1
	while [ -n "$_t" ]; do
		printf '%s' "$(printf '%s' "$_t" | cut -c1)"
		_t=$(printf '%s' "$_t" | cut -c2-)
		[ -n "${SELECTA_DEMO_FAST:-}" ] || sleep 0.035
	done
	printf '\n'
	beat 0.4
}

say() {
	printf '\n%s# %s%s\n' "$CYAN" "$1" "$OFF"
	beat 1.2
}

# --- 1. install --------------------------------------------------------------
say "install"
type_cmd "/plugin marketplace add azandabot/selecta"
printf '✔ Added marketplace: selecta\n'
beat 0.8
type_cmd "/plugin install selecta@selecta"
printf '✔ Installed selecta 0.2.0\n'
beat 1.2

# --- 2. check the machine ----------------------------------------------------
say "check what it needs"
type_cmd "selecta doctor"
$S doctor 2>&1 | sed -n '1,12p'
beat 2.5

# --- 3. play a mood: no window, no key --------------------------------------
say "ask for a mood — radio, no window, no API key"
type_cmd "selecta play ambient"
$S play ambient || true
beat 4

say "the status line shows it, right-aligned, while you work"
printf '%s\n' "$(COLUMNS=100 sh "$ROOT/statusline/launcher.sh" </dev/null 2>/dev/null)"
beat 2.5

# --- 4. play a named track: YouTube -----------------------------------------
say "ask for a specific song — YouTube, in a small player"
type_cmd "selecta play rottweiler by essdeekid"
$S play rottweiler by essdeekid || true
beat 4

# --- 5. what you get ---------------------------------------------------------
say "what is playing, and what is left today"
type_cmd "selecta"
$S || true
beat 4

say "what this repo sounds like"
type_cmd "selecta crate"
$S crate || true
beat 5

say "and what you were listening to while you wrote each commit"
type_cmd "selecta history 6"
$S history 6 2>/dev/null | head -14 || true
beat 5

say "stop"
type_cmd "selecta stop"
$S stop || true
beat 1.5

printf '\n%s  Every repo gets its own.%s\n' "$CYAN" "$OFF"
printf '%s  github.com/azandabot/selecta%s\n\n' "$DIM" "$OFF"
beat 2
