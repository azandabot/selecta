#!/bin/sh
# Regressions for the "it said it was playing but nothing was" class of bug.
#
# All three shipped together and reinforced each other: a dead socket looked
# alive, a stale state file satisfied the success check, and the status line
# recursed until it produced nothing.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-liveness
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/ipc.sh
. "$SELECTA_ROOT/lib/ipc.sh"
# shellcheck source=lib/statusline.sh
. "$SELECTA_ROOT/lib/statusline.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

# --- a socket file is not a live player -------------------------------------
# The original selecta_ipc_up was `[ -S socket ]`. A crashed mpv leaves its
# socket behind, so every caller believed a player was running, skipped
# starting one, and `play` printed success into the void.
t_eq "no socket means down" "1" "$(
	selecta_ipc_up
	echo $?
)"

python3 - "$SELECTA_MPV_SOCK" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sys.argv[1])
s.close()
PY
t_eq "orphaned socket file exists" "yes" \
	"$([ -S "$SELECTA_MPV_SOCK" ] && echo yes || echo no)"
t_eq "a dead socket is reported as down, not up" "1" "$(
	selecta_ipc_up
	echo $?
)"
selecta_ipc_reap
t_eq "reaping removes the dead socket" "no" \
	"$([ -S "$SELECTA_MPV_SOCK" ] && echo yes || echo no)"
t_eq "reaping is safe when there is nothing to reap" "0" "$(
	selecta_ipc_reap
	echo $?
)"

# --- status line wrap must not recurse --------------------------------------
# A wrapped command resolving back to a selecta launcher re-read the same
# wrapped_command and called itself. The child does not inherit SELECTA_HOME,
# so every level landed on the same file and the output grew without bound.
L=$SELECTA_ROOT/statusline/launcher.sh
SEG=$SELECTA_HOME/run/segment
printf '♪ X\t♪ X\t♪ X\nplain\tplain\tplain\nplaying\n3\t5\t5\n' >"$SEG"

printf '%s\n' "$SELECTA_HOME/statusline.sh" >"$SELECTA_HOME/run/wrapped_command"
cp "$L" "$SELECTA_HOME/statusline.sh"
chmod 755 "$SELECTA_HOME/statusline.sh"

_out=$(COLUMNS=80 sh "$L" </dev/null 2>/dev/null)
_lines=$(printf '%s\n' "$_out" | grep -c . || true)
t_eq "a self-referential wrap produces one line, not thousands" "1" "$_lines"
t_eq "a self-referential wrap stays small" "true" \
	"$([ "${#_out}" -lt 200 ] && echo true || echo false)"
t_eq "a self-referential wrap still exits 0" "0" "$(
	COLUMNS=80 sh "$L" </dev/null >/dev/null 2>&1
	echo $?
)"

# The nesting guard must stop a second level even if the command is disguised.
printf 'sh %s\n' "$SELECTA_HOME/statusline.sh" >"$SELECTA_HOME/run/wrapped_command"
_out=$(COLUMNS=80 sh "$L" </dev/null 2>/dev/null)
t_eq "an indirect self-wrap is also bounded" "true" \
	"$([ "${#_out}" -lt 200 ] && echo true || echo false)"

# A genuinely foreign command must still run, exactly once.
printf 'printf "THEIRS\\n"\n' >"$SELECTA_HOME/run/wrapped_command"
_out=$(COLUMNS=80 sh "$L" </dev/null 2>/dev/null)
t_eq "a real foreign status line still runs" "1" \
	"$(printf '%s\n' "$_out" | grep -c THEIRS || true)"

# --- installing over another selecta launcher must replace, not wrap --------
FIX=$SELECTA_HOME/settings.json
SELECTA_SETTINGS=$FIX
export SELECTA_SETTINGS
# A launcher belonging to a *different* selecta home. Wrapping this is what
# caused the recursion, so it must be recognised and replaced instead.
OTHER=$SELECTA_HOME/other-home
mkdir -p "$OTHER"
cp "$L" "$OTHER/statusline.sh"
printf '{"statusLine":{"type":"command","command":"%s"}}\n' "$OTHER/statusline.sh" >"$FIX"
t_eq "a launcher from another selecta home is not a stranger" "ours-elsewhere" "$(selecta_sl_detect)"

printf '{"statusLine":{"type":"command","command":"/opt/somebody/bar.sh"}}\n' >"$FIX"
t_eq "a genuinely foreign status line is still foreign" "foreign" "$(selecta_sl_detect)"

rm -rf "$SELECTA_HOME"

# --- version must not drift -------------------------------------------------
# plugin.json's version is what gates `claude plugin update`. If the shell
# constant disagrees, doctor reports a different version from the one actually
# installed and a stale copy looks current.
t_eq "shell version matches plugin.json" \
	"$(jq -r .version "$SELECTA_ROOT/.claude-plugin/plugin.json")" \
	"$(sed -n 's/^SELECTA_VERSION=//p' "$SELECTA_ROOT/lib/common.sh")"
