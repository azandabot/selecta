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
. "$SELECTA_ROOT/tests/lib.sh"

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

# --- the success banner must not be satisfied by stale state ----------------
# play now writes stopped before issuing the command, so a leftover "playing"
# from a previous session cannot make the wait return immediately.
# Radio play, YouTube play, YouTube replay and stop all clear state first.
# Counted as "at least", so adding a new playback path does not fail the suite
# for the wrong reason; what matters is that none of them skip the clear.
_clears=$(grep -cF 'selecta_state_write stopped 2>/dev/null || true' "$SELECTA_ROOT/bin/selecta")
t_eq "every path that changes playback clears state first" "true" \
	"$([ "$_clears" -ge 3 ] && echo true || echo false)"
t_eq "radio path checks the load reply" "1" \
	"$(grep -cF 'the player did not accept that stream' "$SELECTA_ROOT/bin/selecta")"
t_eq "radio path waits for real playback" "1" \
	"$(grep -cF 'was accepted but never started playing' "$SELECTA_ROOT/bin/selecta")"
t_eq "youtube path waits for the page to report" "1" \
	"$(grep -cF 'no playable upload of' "$SELECTA_ROOT/bin/selecta")"

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

# --- status must probe, not trust the file ----------------------------------
# A state file saying "playing" with no live backend is stale, and reporting it
# as playback is what made selecta look like it was working when it was not.
# Literal source match, so the dollar signs must not expand.
# shellcheck disable=SC2016
t_eq "status probes the backend" "1" \
	"$(grep -cF '_cs_live=$(live_backend)' "$SELECTA_ROOT/bin/selecta")"
t_eq "status names stale state explicitly" "1" \
	"$(grep -cF 'but no player is running, so it was stale' "$SELECTA_ROOT/bin/selecta")"

# --- quota must be visible where it is spent --------------------------------
t_eq "status shows remaining searches" "1" \
	"$(grep -cF 'searches left today · replays and repeats are free' "$SELECTA_ROOT/bin/selecta")"
t_eq "youtube play reports remaining searches" "1" \
	"$(grep -cF 'in the selecta window · via YouTube · %s searches left today' "$SELECTA_ROOT/bin/selecta")"
t_eq "player page shows remaining searches" "1" \
	"$(grep -cF 'searches left today' "$SELECTA_ROOT/player/index.html")"
t_eq "server exposes quota to the page" "1" \
	"$(grep -cF '"quota": _quota()' "$SELECTA_ROOT/libexec/selecta-httpd")"

# --- the repo link, in both surfaces ----------------------------------------
t_eq "status links the repo" "1" \
	"$(grep -cF 'SELECTA_REPO_URL' "$SELECTA_ROOT/bin/selecta")"
t_eq "player page links the repo" "1" \
	"$(grep -cF 'github.com/azandabot/selecta' "$SELECTA_ROOT/player/index.html")"
t_eq "youtube attribution survives alongside it" "1" \
	"$(grep -cF 'Music by YouTube' "$SELECTA_ROOT/player/index.html")"

# --- version must not drift -------------------------------------------------
# plugin.json's version is what gates `claude plugin update`. If the shell
# constant disagrees, doctor reports a different version from the one actually
# installed and a stale copy looks current.
t_eq "shell version matches plugin.json" \
	"$(jq -r .version "$SELECTA_ROOT/.claude-plugin/plugin.json")" \
	"$(sed -n 's/^SELECTA_VERSION=//p' "$SELECTA_ROOT/lib/common.sh")"
