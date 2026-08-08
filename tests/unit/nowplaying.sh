#!/bin/sh
# The now-playing adapter, against stubbed players.
#
# Text in, text out, so it is fully deterministic. The two assertions that
# matter most are the ones that cannot be checked by reading the code: that a
# probe never launches a music app, and that the whole path works with no jq.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-np
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/ipc.sh
. "$SELECTA_ROOT/lib/ipc.sh"
# shellcheck source=lib/state.sh
. "$SELECTA_ROOT/lib/state.sh"
# shellcheck source=lib/nowplaying.sh
. "$SELECTA_ROOT/lib/nowplaying.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

STUB=$SELECTA_HOME/stub
mkdir -p "$STUB"
CALLS=$SELECTA_HOME/calls
: >"$CALLS"

# A stub that records every invocation, so "was this even called" is testable.
mkstub() {
	cat >"$STUB/$1" <<EOF
#!/bin/sh
printf '%s\n' "$1" >>"$CALLS"
$2
EOF
	chmod +x "$STUB/$1"
}

probe() { PATH="$STUB:$PATH" selecta_np_probe 2>/dev/null; }
field() { printf '%s' "$1" | cut -f"$2"; }

# --- the launch-avoidance guarantee -----------------------------------------
# tell application "Spotify" starts Spotify if it is not running. If the pgrep
# gate ever regresses, merely looking at the status line would open a music app.
mkstub pgrep 'exit 1'
mkstub osascript 'printf "playing\tGhost\tShould Never Run\n"'
: >"$CALLS"
probe >/dev/null 2>&1 || true
t_eq "no running player means osascript is never invoked" "0" \
	"$(grep -c '^osascript$' "$CALLS" || true)"
t_eq "pgrep was consulted" "true" \
	"$([ "$(grep -c '^pgrep$' "$CALLS" || echo 0)" -gt 0 ] && echo true || echo false)"

# --- a playing foreign player ------------------------------------------------
mkstub pgrep 'exit 0'
mkstub osascript 'printf "playing\tKabza De Small\tSponono\n"'
_r=$(probe)
t_eq "status is parsed" "playing" "$(field "$_r" 1)"
t_eq "artist is parsed" "Kabza De Small" "$(field "$_r" 2)"
t_eq "title is parsed" "Sponono" "$(field "$_r" 3)"
t_ne "a source label is attached" "" "$(field "$_r" 4)"

mkstub osascript 'printf "paused\tBonobo\tKong\n"'
t_eq "paused is carried through" "paused" "$(field "$(probe)" 1)"

# Nothing loaded: the app is open but idle, which must not read as playing.
mkstub osascript 'printf ""'
t_eq "an open but idle app reports nothing" "1" "$(
	probe >/dev/null
	echo $?
)"

# --- the TCC refusal ---------------------------------------------------------
# A denied Automation prompt fails identically forever. Left unlatched that is
# a wasted 64ms fork every two seconds for the life of the machine.
mkstub osascript 'printf "execution error: Not authorized to send Apple events. (-1743)\n" >&2; exit 1'
probe >/dev/null 2>&1 || true
t_eq "a denied prompt is remembered" "denied" \
	"$(selecta_cfg_get '.nowplaying.macos_automation' '""' | tr -d '"')"
: >"$CALLS"
probe >/dev/null 2>&1 || true
t_eq "after denial osascript is not called again" "0" \
	"$(grep -c '^osascript$' "$CALLS" || true)"
t_eq "doctor explains how to re-enable" "1" \
	"$(selecta_np_capability | grep -c 'Automation')"
selecta_cfg_set '.nowplaying.macos_automation' 'null'

# --- the off switch ----------------------------------------------------------
selecta_cfg_set '.nowplaying.disabled' true
mkstub osascript 'printf "playing\tX\tY\n"'
t_eq "the disable flag stops the probe" "1" "$(
	probe >/dev/null
	echo $?
)"
selecta_cfg_set '.nowplaying.disabled' false

# --- rendering ---------------------------------------------------------------
_p=$(selecta_segment_lines_plain playing "Kabza De Small" "Sponono" "Spotify" "demo-api")
t_eq "narrow variant leads with the track" "1" \
	"$(printf '%s' "$_p" | cut -f1 | grep -c 'Kabza De Small — Sponono')"
t_eq "wide variant names the source" "1" "$(printf '%s' "$_p" | cut -f3 | grep -c 'Spotify')"
t_eq "wide variant names the repo" "1" "$(printf '%s' "$_p" | cut -f3 | grep -c 'demo-api')"
t_eq "three variants are produced" "3" "$(printf '%s' "$_p" | awk -F'\t' '{print NF}')"

_p=$(selecta_segment_lines_plain paused "" "Groove Salad" "" "")
t_eq "paused renders its own glyph" "1" "$(printf '%s' "$_p" | cut -f1 | grep -c '❚❚')"
_p=$(selecta_segment_lines_plain stopped "" "" "" "")
t_eq "nothing ever played offers the command" "1" \
	"$(printf '%s' "$_p" | cut -f1 | grep -c '/selecta play')"

# A tab inside a title would forge an extra field and shift every variant.
_p=$(selecta_segment_lines_plain playing "A" "$(printf 'B\tC')" "S" "R")
t_eq "a tab in a title does not forge a field" "3" "$(printf '%s' "$_p" | awk -F'\t' '{print NF}')"

# --- the zero-dependency claim ------------------------------------------------
# The whole point: showing what Spotify is playing must work where jq does not.
NOJQ=$(t_path_without jq)
_out=$(PATH="$STUB:$NOJQ" sh -c '
	. "$1/lib/common.sh"; SELECTA_ROOT=$1
	. "$1/lib/ipc.sh"; . "$1/lib/state.sh"; . "$1/lib/nowplaying.sh"
	selecta_np_probe' _ "$SELECTA_ROOT" 2>/dev/null)
t_eq "the probe works with no jq" "playing" "$(field "$_out" 1)"

_out=$(PATH="$NOJQ" sh -c '
	. "$1/lib/common.sh"; SELECTA_ROOT=$1
	. "$1/lib/state.sh"
	selecta_segment_lines_plain playing Artist Title Spotify repo' _ "$SELECTA_ROOT" 2>/dev/null)
t_eq "rendering works with no jq" "1" "$(printf '%s' "$_out" | grep -c 'Artist — Title')"
t_eq "no-jq rendering omits the quota rather than dying" "0" \
	"$(printf '%s' "$_out" | grep -c 'left')"

rm -rf "$SELECTA_HOME"
