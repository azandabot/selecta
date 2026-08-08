#!/bin/sh
# The status line launcher must never break the user's status line. Every case
# here, however malformed, has to exit 0.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-statusline
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

L=$SELECTA_ROOT/statusline/launcher.sh
SEG=$SELECTA_HOME/run/segment

run() { COLUMNS=${1:-80} sh "$L" </dev/null 2>/dev/null; }
code() {
	COLUMNS=${1:-80} sh "$L" </dev/null >/dev/null 2>&1
	echo $?
}

write_seg() { printf '%s\n%s\n%s\n' "$1" "$2" "${3:-playing}" >"$SEG"; }

NARROW='♪ Kabza De Small'
MID='♪ Kabza De Small — Sponono · Groove Salad'
WIDE='♪ Kabza De Small — Sponono · Groove Salad · selecta'
write_seg "$NARROW	$MID	$WIDE" "$NARROW	$MID	$WIDE"

# --- width buckets ---
t_eq "narrow terminal picks variant 1" "$NARROW" "$(run 40)"
t_eq "standard terminal picks variant 2" "$MID" "$(run 80)"
t_eq "wide terminal picks variant 3" "$WIDE" "$(run 200)"
t_eq "boundary at 80" "$MID" "$(run 80)"
t_eq "boundary at 79 falls to narrow" "$NARROW" "$(run 79)"
t_eq "boundary at 120" "$WIDE" "$(run 120)"
t_eq "boundary at 119 falls to mid" "$MID" "$(run 119)"

# --- NO_COLOR ---
write_seg "$(printf '\033[2mCOLORED\033[0m')	x	y" "PLAIN	x	y"
t_eq "colored by default" "$(printf '\033[2mCOLORED\033[0m')" "$(run 40)"
t_eq "NO_COLOR uses the plain variant" "PLAIN" "$(NO_COLOR=1 run 40)"
t_eq "TERM=dumb uses the plain variant" "PLAIN" "$(TERM=dumb run 40)"

# --- adversarial: every one must exit 0 and print nothing harmful ---
rm -f "$SEG"
t_eq "missing segment exits 0" "0" "$(code 80)"
t_empty "missing segment prints nothing" "$(run 80)"

: >"$SEG"
t_eq "empty segment exits 0" "0" "$(code 80)"
t_empty "empty segment prints nothing" "$(run 80)"

printf 'only one line' >"$SEG"
t_eq "truncated segment exits 0" "0" "$(code 80)"

printf '\n\n\n' >"$SEG"
t_eq "blank lines exit 0" "0" "$(code 80)"
t_empty "blank lines print nothing" "$(run 80)"

rm -f "$SEG"
mkdir -p "$SEG"
t_eq "segment as a directory exits 0" "0" "$(code 80)"
rmdir "$SEG"

# A title containing shell glob characters must not expand into filenames.
write_seg '♪ * ? [a-z]	♪ * ? [a-z]	♪ * ? [a-z]' '♪ * ? [a-z]	♪ * ? [a-z]	♪ * ? [a-z]'
t_eq "glob characters in a title are literal" '♪ * ? [a-z]' "$(run 40)"

# 4-byte UTF-8 must survive.
write_seg '♪ 𝄞 𝕊ponono	m	w' '♪ 𝄞 𝕊ponono	m	w'
t_eq "4-byte utf-8 survives" '♪ 𝄞 𝕊ponono' "$(run 40)"

# A non-numeric COLUMNS must not crash the arithmetic.
write_seg "$NARROW	$MID	$WIDE" "$NARROW	$MID	$WIDE"
t_eq "non-numeric COLUMNS exits 0" "0" "$(code abc)"
t_eq "non-numeric COLUMNS defaults to 80" "$MID" "$(run abc)"
t_eq "empty COLUMNS defaults to 80" "$MID" "$(COLUMNS='' sh "$L" </dev/null 2>/dev/null)"

# --- heartbeat ---
rm -f "$SELECTA_HOME/run/heartbeat"
run 80 >/dev/null
t_eq "launcher touches the heartbeat" "yes" \
	"$([ -f "$SELECTA_HOME/run/heartbeat" ] && echo yes || echo no)"

# --- no forks in the common path ---
# The launcher must not shell out. Anything spawning jq, git or awk on every
# refresh would make a 2 second interval expensive. Comments are stripped
# first, since the file documents the very binaries it must not call.
code_only() { grep -v '^[[:space:]]*#' "$L"; }
t_eq "no jq in the launcher" "0" "$(code_only | grep -c '\bjq\b')"
t_eq "no git in the launcher" "0" "$(code_only | grep -c '\bgit\b')"
t_eq "no awk or sed in the launcher" "0" "$(code_only | grep -cE '\b(awk|sed|cut|tr)\b')"
t_eq "every exit is status 0" "0" "$(grep -cE '^exit [1-9]' "$L")"

# --- wrap mode ---
printf 'printf "THEIRS\\n"\n' >"$SELECTA_HOME/run/wrapped_command"
_out=$(run 40)
t_eq "wrapped line comes first" "THEIRS" "$(printf '%s' "$_out" | sed -n 1p)"
t_eq "our line comes second" "$NARROW" "$(printf '%s' "$_out" | sed -n 2p)"

printf 'exit 7\n' >"$SELECTA_HOME/run/wrapped_command"
t_eq "a failing wrapped command still exits 0" "0" "$(code 40)"
t_eq "a failing wrapped command still shows our line" "$NARROW" "$(run 40)"

rm -f "$SELECTA_HOME/run/wrapped_command"
rm -rf "$SELECTA_HOME"
