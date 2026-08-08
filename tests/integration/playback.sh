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
. "$SELECTA_TESTS/lib.sh"

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
	wait_for '[ "$(sed -n 3p "$SELECTA_SEGMENT" 2>/dev/null)" = playing ]' 40
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

	# A stop holds the last line briefly, so a station change does not blank
	# the bar and bring it back a second later.
	selecta_ipc_command '["stop"]' >/dev/null
	wait_for '[ "$(jq -r .status "$SELECTA_STATE" 2>/dev/null)" = stopped ]' 40
	t_eq "the segment survives a stop" "true" \
		"$([ -s "$SELECTA_SEGMENT" ] && echo true || echo false)"

	# Past the grace it clears. Holding it forever is what "stuck on a track
	# from an hour ago" looked like.
	printf '%s\n' "$(($(date +%s) - 3600))" >/dev/null
	touch -t "$(date -u -r $(($(date +%s) - 3600)) +%Y%m%d%H%M.%S 2>/dev/null ||
		date -u -d @$(($(date +%s) - 3600)) +%Y%m%d%H%M.%S)" \
		"$SELECTA_RUN/idle-since" 2>/dev/null
	t_eq "an idle bar clears itself" "true" \
		"$(wait_for '[ ! -s "$SELECTA_SEGMENT" ]' 40 && echo true || echo false)"
	t_eq "and the launcher then prints nothing" "" \
		"$(COLUMNS=100 sh "$SELECTA_ROOT/statusline/launcher.sh" </dev/null)"
fi

# --- teardown -----------------------------------------------------------------
sh "$SELECTA_ROOT/libexec/selecta-teardown" 2>/dev/null
exited() {
	[ ! -f "$SELECTA_PIDFILE" ] || return 1
	kill -0 "$SUP_PID" 2>/dev/null || return 0
	# Still in the process table: only acceptable as an unreaped zombie.
	case $(ps -o stat= -p "$SUP_PID" 2>/dev/null | tr -d ' ') in
	Z*) return 0 ;;
	*) return 1 ;;
	esac
}
t_eq "teardown stops the supervisor" "true" \
	"$(wait_for exited 40 && echo true || echo false)"
t_eq "teardown takes mpv with it" "true" \
	"$(wait_for '! selecta_ipc_up' 40 && echo true || echo false)"

kill "$SUP_PID" 2>/dev/null
pkill -f "input-ipc-server=$SELECTA_HOME" 2>/dev/null
rm -rf "$SELECTA_HOME"
