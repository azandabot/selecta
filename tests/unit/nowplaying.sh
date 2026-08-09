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

# --- macOS -------------------------------------------------------------------
# uname is stubbed so this runs on Linux too. Without it the whole macOS block
# fell through the case statement and asserted nothing on the CI leg that
# actually runs on every push.
mkstub uname 'printf "Darwin\n"'

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

# --- AppleScript's null --------------------------------------------------------
# `name of current track` returns `missing value` when nothing is loaded, and
# that is not the empty string, so it sailed past every emptiness check and the
# status line displayed the literal words "missing value" as the track title.
# An app left open with nothing playing hits this every time.
mkstub osascript 'printf "playing\t\tmissing value\n"'
t_eq "a missing title is not a track" "1" "$(
	probe >/dev/null
	echo $?
)"
mkstub osascript 'printf "playing\tmissing value\tReal Title\n"'
t_eq "a missing artist never reaches the bar" "0" \
	"$(probe | grep -c 'missing value' || true)"
mkstub osascript 'printf "playing\tReal Artist\tReal Title\n"'
t_eq "a real track still gets through" "Real Title" "$(field "$(probe)" 3)"

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
	"$(PATH="$STUB:$PATH" selecta_np_capability | grep -c 'Automation')"
selecta_cfg_set '.nowplaying.macos_automation' 'null'

# --- the off switch ----------------------------------------------------------
selecta_cfg_set '.nowplaying.disabled' true
mkstub osascript 'printf "playing\tX\tY\n"'
t_eq "the disable flag stops the probe" "1" "$(
	probe >/dev/null
	echo $?
)"
selecta_cfg_set '.nowplaying.disabled' false

# --- selecta's own playback wins over the app you left open ---------------------
# With a YouTube track playing, the probe knew about mpv and nothing else, so
# it fell through to whatever music app was open and the bar named the wrong
# thing while selecta was the one making noise.
mkstub uname 'printf "Darwin\n"'
mkstub pgrep 'exit 0'
mkstub osascript 'printf "playing\tApple Music Artist\tApple Music Track\n"'
printf '{"origin":"http://127.0.0.1:1","url":"x"}\n' >"$SELECTA_RUN/httpd.json"
mkstub curl 'printf "{\"ok\":true,\"page_age\":0.2}\n"'
printf '%s\n' '{"status":"playing","source":{"provider":"youtube","title":"T"},
	"now":{"artist":"Kabza De Small","title":"Sponono"}}' >"$SELECTA_STATE"

_y=$(probe)
t_eq "the youtube window beats the music app" "Kabza De Small" "$(field "$_y" 2)"
t_eq "and is labelled as youtube" "YouTube" "$(field "$_y" 4)"

# Paused in the window is still ours; the app must not take the line back.
printf '%s\n' '{"status":"paused","source":{"provider":"youtube","title":"T"},
	"now":{"artist":"Kabza De Small","title":"Sponono"}}' >"$SELECTA_STATE"
t_eq "a paused youtube track is still ours" "paused" "$(field "$(probe)" 1)"

# Stopped is not ours any more, so the app should come back.
printf '%s\n' '{"status":"stopped","source":{"provider":"youtube","title":"T"},"now":null}' \
	>"$SELECTA_STATE"
t_eq "once stopped the music app takes the line back" "Apple Music Artist" \
	"$(field "$(probe)" 2)"

# A dead window must not hold the line against a live app.
mkstub curl 'exit 1'
printf '%s\n' '{"status":"playing","source":{"provider":"youtube","title":"T"},
	"now":{"artist":"Kabza De Small","title":"Sponono"}}' >"$SELECTA_STATE"
t_eq "a closed window releases the line" "Apple Music Artist" "$(field "$(probe)" 2)"
rm -f "$SELECTA_RUN/httpd.json" "$STUB/curl"
: >"$SELECTA_STATE"

# --- getting out of the way -----------------------------------------------------
# Two players, two streams, one pair of speakers. selecta pauses what is
# already going before it starts.
: >"$CALLS"
mkstub pgrep 'exit 1'
mkstub osascript 'printf ""'
selecta_np_pause_others
t_eq "a closed app is never told to pause, which would launch it" "0" \
	"$(grep -c '^osascript$' "$CALLS" || true)"

: >"$CALLS"
mkstub pgrep 'exit 0'
PATH="$STUB:$PATH" selecta_np_pause_others
t_eq "a running app is asked to pause" "true" \
	"$([ "$(grep -c '^osascript$' "$CALLS" || echo 0)" -gt 0 ] && echo true || echo false)"

: >"$CALLS"
selecta_cfg_set '.playback.pause_others' false
PATH="$STUB:$PATH" selecta_np_pause_others
t_eq "the opt-out is honoured" "0" "$(grep -c '^osascript$' "$CALLS" || true)"
selecta_cfg_set '.playback.pause_others' true

# A refused Automation prompt must not be re-asked on every play.
: >"$CALLS"
selecta_cfg_set '.nowplaying.macos_automation' '"denied"'
PATH="$STUB:$PATH" selecta_np_pause_others
t_eq "a denied prompt is not re-asked when pausing" "0" \
	"$(grep -c '^osascript$' "$CALLS" || true)"
selecta_cfg_set '.nowplaying.macos_automation' 'null'
rm -f "$STUB/uname" "$STUB/pgrep" "$STUB/osascript"

# --- Linux -------------------------------------------------------------------
mkstub uname 'printf "Linux\n"'
rm -f "$STUB/osascript" "$STUB/pgrep"

mkstub playerctl 'printf "Playing\tBonobo\tKong\tspotify\n"'
_l=$(probe)
t_eq "playerctl status is parsed" "playing" "$(field "$_l" 1)"
t_eq "playerctl artist is parsed" "Bonobo" "$(field "$_l" 2)"
t_eq "playerctl title is parsed" "Kong" "$(field "$_l" 3)"
t_eq "the player name becomes the label" "spotify" "$(field "$_l" 4)"

# Several players at once is the normal case on a desktop: a paused Firefox tab
# must not win over music that is actually playing.
mkstub playerctl 'printf "Paused\tA\tB\tfirefox\nPlaying\tC\tD\tvlc\n"'
_l=$(probe)
t_eq "playing beats paused regardless of order" "playing" "$(field "$_l" 1)"
t_eq "the playing player is the one reported" "vlc" "$(field "$_l" 4)"

mkstub playerctl 'printf "Paused\tA\tB\tfirefox\n"'
t_eq "paused is reported when nothing is playing" "paused" "$(field "$(probe)" 1)"

# A title containing an apostrophe is why the dbus-send GVariant parser was
# rejected: any sed for it breaks on exactly this, and it is a lot of songs.
cat >"$STUB/playerctl" <<'PCTL'
#!/bin/sh
printf "playerctl\n" >>"$CALLS"
printf "Playing\tD'Angelo\tDon't Ever Leave\tspotify\n"
PCTL
chmod +x "$STUB/playerctl"
_l=$(probe)
t_eq "an apostrophe in the artist survives" "D'Angelo" "$(field "$_l" 2)"
t_eq "an apostrophe in the title survives" "Don't Ever Leave" "$(field "$_l" 3)"

mkstub playerctl 'printf "Stopped\t\t\tspotify\n"'
t_eq "a stopped player reports nothing" "1" "$(
	probe >/dev/null
	echo $?
)"
mkstub playerctl 'exit 1'
t_eq "no player running reports nothing" "1" "$(
	probe >/dev/null
	echo $?
)"

rm -f "$STUB/uname"

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
nojq_probe() {
	PATH="$STUB:$NOJQ" sh -c '
		. "$1/lib/common.sh"; SELECTA_ROOT=$1
		. "$1/lib/ipc.sh"; . "$1/lib/state.sh"; . "$1/lib/nowplaying.sh"
		selecta_np_probe' _ "$SELECTA_ROOT" 2>/dev/null
}

rm -f "$STUB/playerctl"
mkstub uname 'printf "Darwin\n"'
mkstub pgrep 'exit 0'
mkstub osascript 'printf "playing\tKabza De Small\tSponono\n"'
t_eq "the macOS probe works with no jq" "playing" "$(field "$(nojq_probe)" 1)"
t_eq "the macOS probe keeps the artist with no jq" "Kabza De Small" \
	"$(field "$(nojq_probe)" 2)"

rm -f "$STUB/osascript" "$STUB/pgrep"
mkstub uname 'printf "Linux\n"'
mkstub playerctl 'printf "Playing\tBonobo\tKong\tspotify\n"'
t_eq "the Linux probe works with no jq" "playing" "$(field "$(nojq_probe)" 1)"
t_eq "the Linux probe keeps the title with no jq" "Kong" "$(field "$(nojq_probe)" 3)"
rm -f "$STUB/uname"

_out=$(PATH="$NOJQ" sh -c '
	. "$1/lib/common.sh"; SELECTA_ROOT=$1
	. "$1/lib/state.sh"
	selecta_segment_lines_plain playing Artist Title Spotify repo' _ "$SELECTA_ROOT" 2>/dev/null)
t_eq "rendering works with no jq" "1" "$(printf '%s' "$_out" | grep -c 'Artist — Title')"
t_eq "no-jq rendering omits the quota rather than dying" "0" \
	"$(printf '%s' "$_out" | grep -c 'left')"

rm -rf "$SELECTA_HOME"
