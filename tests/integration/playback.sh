#!/bin/sh
# The test the README has claimed existed since the first release: real mpv,
# real demux, real IPC, real state and segment writes. No network needed.
#
# av://lavfi is served by mpv's own ffmpeg link, so this exercises the whole
# chain deterministically and offline. --ao=null means no audio device.
# Conditions are passed to wait_for unexpanded, on purpose.
# shellcheck disable=SC2016
set -u


SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-playback
export SELECTA_HOME
SELECTA_AO=null
export SELECTA_AO
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/ipc.sh
. "$SELECTA_ROOT/lib/ipc.sh"
# shellcheck source=lib/state.sh
. "$SELECTA_ROOT/lib/state.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

if ! command -v mpv >/dev/null 2>&1; then
	printf 'ok playback suite skipped, no mpv\n' >>"$T_RESULTS"
	exit 0
fi
if [ "$(selecta_ipc_transport)" = none ]; then
	printf 'ok playback suite skipped, no unix socket transport\n' >>"$T_RESULTS"
	exit 0
fi

SUP=$SELECTA_ROOT/libexec/selecta-supervisor
TONE='av://lavfi:sine=frequency=440:duration=30'

# Waits for a condition rather than sleeping a fixed time, so a slow machine
# is slow rather than failing.
wait_for() {
	_wf_n=0
	while [ "$_wf_n" -lt "${2:-60}" ]; do
		eval "$1" >/dev/null 2>&1 && return 0
		_wf_n=$((_wf_n + 1))
		sleep 0.25
	done
	return 1
}

: >"$SELECTA_RUN/want-mpv"
"$SUP" --detached </dev/null >/dev/null 2>&1 &
SUP_PID=$!

t_eq "the supervisor brings mpv up" "true" \
	"$(wait_for 'selecta_ipc_up' 80 && echo true || echo false)"

if selecta_ipc_up; then
	printf '{"id":"test:tone","kind":"station","provider":"test","title":"Test Tone","repo":{"key":"remote:github.com/t/t","display_name":"t"}}\n' \
		>"$SELECTA_RUN/source.json"
	selecta_ipc_command "[\"loadfile\",\"$TONE\"]" >/dev/null

	t_eq "playback reaches playing" "true" \
		"$(wait_for '[ "$(jq -r .status "$SELECTA_STATE" 2>/dev/null)" = playing ]' 80 && echo true || echo false)"
	t_eq "state names the source" "Test Tone" \
		"$(jq -r '.source.title // ""' "$SELECTA_STATE" 2>/dev/null)"
	t_eq "the segment has four lines" "4" "$(wc -l <"$SELECTA_SEGMENT" | tr -d ' ')"
	t_eq "the segment status line says playing" "playing" "$(sed -n 3p "$SELECTA_SEGMENT")"
	t_eq "the segment has three width variants" "3" \
		"$(sed -n 2p "$SELECTA_SEGMENT" | awk -F'\t' '{print NF}')"

	# The launcher is what the host actually runs; it must produce one line.
	t_eq "the launcher renders exactly one line" "1" \
		"$(COLUMNS=100 sh "$SELECTA_ROOT/statusline/launcher.sh" </dev/null | grep -c .)"

	selecta_ipc_command '["set_property","volume",30]' >/dev/null
	t_eq "volume is applied" "30" "$(selecta_ipc_get volume | cut -d. -f1)"

	selecta_ipc_command '["set_property","pause",true]' >/dev/null
	t_eq "pause is reflected in state" "true" \
		"$(wait_for '[ "$(jq -r .status "$SELECTA_STATE" 2>/dev/null)" = paused ]' 40 && echo true || echo false)"

	selecta_ipc_command '["set_property","pause",false]' >/dev/null
	t_eq "unpause returns to playing" "true" \
		"$(wait_for '[ "$(jq -r .status "$SELECTA_STATE" 2>/dev/null)" = playing ]' 40 && echo true || echo false)"

	# Stopped must keep the last track rather than blanking the bar.
	selecta_ipc_command '["stop"]' >/dev/null
	wait_for '[ "$(jq -r .status "$SELECTA_STATE" 2>/dev/null)" = stopped ]' 40
	t_eq "the segment survives a stop" "true" \
		"$([ -s "$SELECTA_SEGMENT" ] && echo true || echo false)"
fi

# --- teardown -----------------------------------------------------------------
sh "$SELECTA_ROOT/libexec/selecta-teardown" 2>/dev/null
t_eq "teardown stops the supervisor within 3s" "true" \
	"$(wait_for '! kill -0 '"$SUP_PID"' 2>/dev/null' 12 && echo true || echo false)"
t_eq "teardown takes mpv with it" "true" \
	"$(wait_for '! selecta_ipc_up' 12 && echo true || echo false)"

kill "$SUP_PID" 2>/dev/null
pkill -f "input-ipc-server=$SELECTA_HOME" 2>/dev/null
rm -rf "$SELECTA_HOME"
