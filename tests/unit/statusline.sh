#!/bin/sh
# The status line launcher must never break the user's status line. Every case
# here, however malformed, has to exit 0.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-statusline
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

L=$SELECTA_ROOT/statusline/launcher.sh
SEG=$SELECTA_HOME/run/segment

# TERM and NO_COLOR are inputs to the launcher, not ambient state. CI runners
# export TERM=dumb, which silently turned every colour assertion into a
# plain-variant assertion. Defaulted here so the two tests below can still
# override them per call.
TERM=${SELECTA_TEST_TERM:-xterm}
export TERM
unset NO_COLOR

run() { COLUMNS=${1:-80} sh "$L" </dev/null 2>/dev/null; }
code() {
	COLUMNS=${1:-80} sh "$L" </dev/null >/dev/null 2>&1
	echo $?
}

# Writes a segment file, deriving the width line the way the supervisor does.
write_seg() {
	_w=''
	for _i in 1 2 3; do
		_p=$(printf '%s' "$2" | cut -f"$_i")
		_w="$_w${_w:+	}$(printf '%s' "$_p" | wc -m | tr -d ' ')"
	done
	printf '%s\n%s\n%s\n%s\n' "$1" "$2" "${3:-playing}" "$_w" >"$SEG"
}

# Most assertions are about which variant is chosen and what it contains, so
# they run left-aligned. Alignment has its own section below.
align_left() { printf 'left\n' >"$SELECTA_HOME/run/align"; }
align_right() { printf 'right\n' >"$SELECTA_HOME/run/align"; }
align_left

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

# --- alignment --------------------------------------------------------------
# Right is the default: the line should sit under the right-hand end of the
# input box, not compete with output on the left.
align_right
write_seg "$NARROW	$MID	$WIDE" "$NARROW	$MID	$WIDE"

_r=$(run 80)
t_eq "right aligned still ends with the text" "$MID" \
	"$(printf '%s' "$_r" | sed 's/^ *//')"
starts_with_space() {
	case $1 in
	' '*) printf true ;;
	*) printf false ;;
	esac
}
t_eq "right aligned is padded on the left" "true" "$(starts_with_space "$_r")"

# The line must land flush to the right edge, one column of slack.
_len=$(printf '%s' "$_r" | wc -m | tr -d ' ')
t_eq "right aligned line reaches the right edge" "79" "$_len"

_r=$(run 200)
t_eq "right alignment scales with terminal width" "199" \
	"$(printf '%s' "$_r" | wc -m | tr -d ' ')"

# A line wider than the terminal must not gain negative padding.
write_seg "$WIDE	$WIDE	$WIDE" "$WIDE	$WIDE	$WIDE"
t_eq "no padding when the text already fills the width" "$WIDE" "$(run 30)"
t_eq "over-wide line still exits 0" "0" "$(code 30)"

# Multi-byte characters must be measured as characters, not bytes, or the line
# gets pushed off the right edge.
MB='♪ Björk — Jóga · Café'
write_seg "$MB	$MB	$MB" "$MB	$MB	$MB"
_r=$(run 80)
t_eq "multi-byte title is measured by character" "79" \
	"$(printf '%s' "$_r" | wc -m | tr -d ' ')"

# A missing width line must degrade to left alignment rather than break.
printf '%s\n%s\n%s\n' "$NARROW" "$NARROW" playing >"$SEG"
t_eq "missing width line falls back to left" "$NARROW" "$(run 80)"
t_eq "missing width line exits 0" "0" "$(code 80)"

# A corrupt width line must not produce a broken printf.
write_seg "$NARROW	$MID	$WIDE" "$NARROW	$MID	$WIDE"
sed '4s/.*/abc\tdef\tghi/' "$SEG" >"$SEG.tmp" && mv "$SEG.tmp" "$SEG"
t_eq "non-numeric widths exit 0" "0" "$(code 80)"
t_eq "non-numeric widths fall back to left" "$MID" "$(run 80)"

align_left
rm -rf "$SELECTA_HOME"
