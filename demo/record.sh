#!/bin/sh
# Drives the README demo end to end, for an asciinema recording.
#
# The arc is install -> it already knows what you are playing -> and then it
# can play too -> and it remembers. The status line comes first because that is
# the thing that works with nothing installed, and a demo that opens on a
# package manager loses the viewer before the point lands.
#
# It runs against a throwaway SELECTA_HOME and a seeded demo repo, so the crate
# looks lived-in instead of empty on the first frame.
#
#   demo/seed.sh                       build the demo repo
#   asciinema rec demo.cast -c demo/record.sh
#   agg --theme asciinema demo.cast demo.gif
#
# SELECTA_AO=null rehearses it silently. SELECTA_DEMO_FAST=1 skips the pauses.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../plugins/selecta" && pwd -P)
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

# The status line is the product, and it is a Claude Code UI element that no
# terminal recording can capture. So the demo renders the launcher's actual
# output: the same bytes the status bar receives.
show_bar() {
	printf '%s\n' "$(COLUMNS=100 sh "$ROOT/statusline/launcher.sh" </dev/null 2>/dev/null)"
}

# The opening beat claims selecta already knows what your music app is playing.
# The probe is real and needs nothing from SELECTA_HOME, so if a player is
# actually open this reads it. If not, the demo would show an empty bar under a
# line promising the opposite, so it seeds the same renderer with a known track
# and says so on stderr. Record with Spotify playing and this never fires.
# shellcheck source=lib/common.sh
. "$ROOT/lib/common.sh"
# shellcheck source=lib/ipc.sh
. "$ROOT/lib/ipc.sh"
# shellcheck source=lib/state.sh
. "$ROOT/lib/state.sh"
# shellcheck source=lib/nowplaying.sh
. "$ROOT/lib/nowplaying.sh"
foreign_bar() {
	_fb=$(selecta_np_probe 2>/dev/null) || _fb=''
	if [ -z "$_fb" ]; then
		printf 'demo: no music app running, seeding the bar. Open Spotify for a real one.\n' >&2
		_fb=$(printf 'playing\tSault\tWildfires\tSpotify')
	fi
	selecta_segment_lines_plain \
		"$(printf '%s' "$_fb" | cut -f1)" \
		"$(printf '%s' "$_fb" | cut -f2)" \
		"$(printf '%s' "$_fb" | cut -f3)" \
		"$(printf '%s' "$_fb" | cut -f4)" \
		"$(basename "$PWD")" | cut -f3
}

# --- 1. install --------------------------------------------------------------
say "install"
type_cmd "/plugin marketplace add azandabot/selecta"
printf '✔ Added marketplace: azandabot-selecta\n'
beat 0.8
type_cmd "/plugin install selecta@azandabot-selecta"
printf '✔ Installed selecta %s\n' "$($S --version | cut -d' ' -f2)"
beat 1.2

# --- 2. it already knows -----------------------------------------------------
# The whole pitch in one frame: no key, no config, nothing running yet.
say "put something on in Spotify. that is the setup."
type_cmd "selecta statusline on"
beat 0.6
printf '%s\n' "$(foreign_bar)"
beat 3.5

say "no key, no config, nothing installed. it reads the player you have open."
type_cmd "selecta doctor"
$S doctor 2>&1 | sed -n '1,14p'
beat 3

# --- 3. and it can play too --------------------------------------------------
say "it can also be the player — radio, no window, no account"
type_cmd "selecta play ambient"
$S play ambient || true
beat 3.5
show_bar
beat 2.5

say "control whatever is playing"
type_cmd "selecta vol 40"
$S vol 40 || true
beat 1.2

# --- 4. and it remembers -----------------------------------------------------
say "every track is stamped with the commit that was checked out"
type_cmd "selecta crate"
$S crate || true
beat 5

say "so you can ask what you were listening to while you wrote something"
type_cmd "selecta crate --history 6"
$S crate --history 6 2>/dev/null | head -14 || true
beat 5

say "stop"
type_cmd "selecta stop"
$S stop || true
beat 1.5

printf '\n%s  Every repo gets its own.%s\n' "$CYAN" "$OFF"
printf '%s  github.com/azandabot/selecta%s\n\n' "$DIM" "$OFF"
beat 2
