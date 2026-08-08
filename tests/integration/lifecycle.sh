#!/bin/sh
# Process lifecycle: teardown speed, PID-reuse safety, stale lock reaping, and
# the silence rule that keeps the supervisor from spamming the session.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-lifecycle
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

TD=$SELECTA_ROOT/libexec/selecta-teardown
SUP=$SELECTA_ROOT/libexec/selecta-supervisor

# --- teardown is safe when there is nothing to tear down --------------------
rm -f "$SELECTA_PIDFILE"
t_status "teardown with no pidfile exits 0" 0 sh "$TD"

printf 'not-a-pid\n' >"$SELECTA_PIDFILE"
t_status "teardown with a garbage pidfile exits 0" 0 sh "$TD"

printf '\n' >"$SELECTA_PIDFILE"
t_status "teardown with an empty pidfile exits 0" 0 sh "$TD"

# --- PID reuse guard --------------------------------------------------------
# A recycled PID belonging to something else must never be signalled.
sh -c 'while :; do sleep 1; done' &
VICTIM=$!
printf '%s\n' "$VICTIM" >"$SELECTA_PIDFILE"
sh "$TD"
t_eq "an unrelated process with a recycled pid is not killed" "alive" \
	"$(kill -0 "$VICTIM" 2>/dev/null && echo alive || echo killed)"
kill "$VICTIM" 2>/dev/null
wait "$VICTIM" 2>/dev/null || true

# --- teardown is fast enough for the SessionEnd budget ----------------------
# SessionEnd hooks share 1.5s. Measured over 5 runs to smooth out noise.
rm -f "$SELECTA_PIDFILE"
START=$(date +%s)
_i=0
while [ "$_i" -lt 5 ]; do
	_i=$((_i + 1))
	sh "$TD"
done
ELAPSED=$(($(date +%s) - START))
t_eq "5 teardowns complete inside the 1.5s hook budget" "true" \
	"$([ "$ELAPSED" -le 1 ] && echo true || echo false)"

# --- lock behaviour ---------------------------------------------------------
selecta_lock_release
t_eq "lock can be acquired" "0" "$(
	selecta_lock_acquire
	echo $?
)"
t_eq "a held lock cannot be acquired twice" "1" "$(
	selecta_lock_acquire
	echo $?
)"
selecta_lock_release
t_eq "lock is released" "0" "$(
	selecta_lock_acquire
	echo $?
)"

# A lock whose owner is gone must not wedge every future session.
printf '999999\n' >"$SELECTA_LOCKDIR/pid"
selecta_lock_reap_stale
t_eq "a stale lock is reaped" "0" "$(
	selecta_lock_acquire
	echo $?
)"
selecta_lock_release

# --- the silence rule -------------------------------------------------------
# As a plugin monitor, every stdout line the supervisor emits is surfaced to
# the session. Only the guarded fatal path may write, and it writes to stderr.
t_eq "supervisor closes stdout before doing anything" "1" \
	"$(grep -c 'exec >/dev/null' "$SUP")"
t_eq "no bare echo to stdout in the supervisor" "0" \
	"$(grep -v '^[[:space:]]*#' "$SUP" | grep -cE '^[[:space:]]*echo ')"

# --- a second supervisor must lose quietly ----------------------------------
# One player per user. The loser has to exit silently: as a plugin monitor,
# anything it prints becomes a notification in an unrelated session.
#
# The lock must be held by a real supervisor for this to be meaningful. A
# hand-written lock file is correctly treated as stale and reaped, because
# selecta_lock_reap_stale only honours locks whose owner is actually running.
if command -v timeout >/dev/null 2>&1 && command -v mpv >/dev/null 2>&1; then
	selecta_lock_release
	SELECTA_AO=null "$SUP" --detached >/dev/null 2>&1 &
	FIRST=$!
	_w=0
	while [ ! -d "$SELECTA_LOCKDIR" ] && [ "$_w" -lt 100 ]; do
		_w=$((_w + 1))
		sleep 0.05
	done

	if [ -d "$SELECTA_LOCKDIR" ]; then
		OUT=$(SELECTA_HOME=$SELECTA_HOME timeout 10 "$SUP" --monitor 2>&1)
		RC=$?
		t_eq "a losing supervisor exits 0" "0" "$RC"
		t_empty "a losing supervisor prints nothing" "$OUT"
		t_eq "the first supervisor still holds the lock" "yes" \
			"$([ -d "$SELECTA_LOCKDIR" ] && echo yes || echo no)"
	fi

	sh "$TD" 2>/dev/null
	_w=0
	while kill -0 "$FIRST" 2>/dev/null && [ "$_w" -lt 60 ]; do
		_w=$((_w + 1))
		sleep 0.05
	done
	t_eq "teardown stops the supervisor" "gone" \
		"$(kill -0 "$FIRST" 2>/dev/null && echo alive || echo gone)"
	kill "$FIRST" 2>/dev/null
	pkill -f "input-ipc-server=$SELECTA_HOME" 2>/dev/null
fi

rm -rf "$SELECTA_HOME"
