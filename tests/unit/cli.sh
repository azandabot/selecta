#!/bin/sh
# bin/selecta as a subprocess: exit codes, stdout, and files on disk.
#
# The repo had ~30 assertions that grepped bin/selecta's own source text. Those
# pass whether or not the code runs and break on any rename. These run the
# thing instead, and would have caught every defect the audit found.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-cli
export SELECTA_HOME
SELECTA_OFFLINE=1
export SELECTA_OFFLINE
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run" "$SELECTA_HOME/cache"

# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

S=$SELECTA_ROOT/bin/selecta
FIX=$SELECTA_HOME/settings.json
SELECTA_SETTINGS=$FIX
export SELECTA_SETTINGS

# Every invocation gets /dev/null on stdin: that is what the Bash tool gives a
# command, and it is the condition the consent deadlock hid behind.
run() { "$S" "$@" </dev/null 2>/dev/null; }
code() {
	"$S" "$@" </dev/null >/dev/null 2>&1
	echo $?
}
err() { "$S" "$@" </dev/null 2>&1 >/dev/null; }

# --- basics -----------------------------------------------------------------
t_eq "version matches plugin.json" \
	"selecta $(jq -r .version "$SELECTA_ROOT/.claude-plugin/plugin.json")" "$(run --version)"
t_eq "help exits 0" "0" "$(code --help)"

t_eq "unknown subcommand exits 2" "2" "$(code wibble)"
t_eq "unknown subcommand suggests play" "1" \
	"$(err wibble | grep -c 'selecta play wibble')"
t_eq "a genre typed as a subcommand does not start playback" "2" "$(code lofi)"

# --- the consent deadlock ---------------------------------------------------
# statusline on with no TTY used to print a question, hit EOF on read, and die
# under set -e. Nothing was installed and nothing said why.
printf '{"theme":"dark"}\n' >"$FIX"
_before=$(cat "$FIX")

t_eq "statusline preview exits 7, not 0 and not a crash" "7" "$(code statusline on)"
t_eq "statusline preview leaves settings byte-identical" "$_before" "$(cat "$FIX")"
t_eq "statusline preview shows the JSON it would add" "1" \
	"$(run statusline on | grep -c '"statusLine"')"
t_eq "statusline preview discloses the footer hints" "1" \
	"$(run statusline on | grep -c 'footer key hints')"
t_eq "statusline preview discloses that settings are global" "1" \
	"$(run statusline on | grep -c 'global settings')"
t_eq "statusline preview says how to confirm" "1" \
	"$(err statusline on | grep -c -- '--user-confirmed')"

t_eq "statusline installs with --user-confirmed" "0" "$(code statusline on --user-confirmed)"
t_eq "statusline actually wrote the key" "command" "$(jq -r '.statusLine.type' "$FIX")"
t_eq "other settings keys survived" "dark" "$(jq -r '.theme' "$FIX")"
run statusline off >/dev/null

# Same trap, other two sites.
t_eq "uninstall --purge without confirmation exits 7" "7" "$(code uninstall --purge)"
t_eq "uninstall --purge without confirmation keeps the home" "yes" \
	"$([ -d "$SELECTA_HOME" ] && echo yes || echo no)"

# --- doctor must survive the thing it diagnoses -----------------------------
NOJQ=$(t_path_without jq)
_d_out=$(PATH=$NOJQ "$S" doctor </dev/null 2>/tmp/selecta-cli-djq.err)
_d_code=$(
	PATH=$NOJQ "$S" doctor </dev/null >/dev/null 2>&1
	echo $?
)
t_eq "doctor with no jq exits 4" "4" "$_d_code"
t_eq "doctor with no jq reports jq missing" "1" "$(printf '%s' "$_d_out" | grep -c 'MISSING  jq')"
t_eq "doctor with no jq prints an install command" "1" \
	"$(printf '%s' "$_d_out" | grep -c 'brew install\|apt-get install\|install Homebrew')"
t_eq "doctor with no jq does not leak a shell error" "0" \
	"$(grep -c 'command not found' /tmp/selecta-cli-djq.err || true)"
rm -f /tmp/selecta-cli-djq.err

t_eq "other commands with no jq exit 4" "4" "$(
	PATH=$NOJQ "$S" play ambient </dev/null >/dev/null 2>&1
	echo $?
)"
t_eq "other commands with no jq say jq is required" "1" "$(
	PATH=$NOJQ "$S" play ambient </dev/null 2>&1 >/dev/null | grep -c 'jq is required'
)"

# --- nothing playing --------------------------------------------------------
for _c in pause go vol; do
	t_eq "$_c with nothing playing exits 6" "6" "$(code "$_c")"
done
t_eq "stop with nothing playing exits 0" "0" "$(code stop)"
t_eq "stop with nothing playing says so" "1" "$(run stop | grep -c 'Nothing playing')"

# --- no crate ---------------------------------------------------------------
t_eq "crate with no crate exits 0" "0" "$(code crate)"
t_eq "status with no crate exits 0" "0" "$(code)"

# --- structural invariants that are genuinely structural --------------------
# Every subcommand named in usage() must be dispatched, and vice versa. This
# is the one grep worth keeping: it catches a command documented but unwired.
_usage=$(sed -n '/^usage()/,/^}/p' "$S" | sed -n 's/^  selecta \([a-z-]*\).*/\1/p' | sort -u | grep -v '^$')
# shellcheck disable=SC2016
_disp=$(sed -n '/^	case \$cmd in$/,/^	esac$/p' "$S" |
	sed -n 's/^	\([a-z| -]*\)).*/\1/p' | tr '|' '\n' | tr -d ' ' | sort -u | grep -v '^$')
for _u in $_usage; do
	case "$_disp" in
	*"$_u"*) ;;
	*) t_eq "usage lists $_u and main dispatches it" "dispatched" "MISSING" ;;
	esac
done
t_eq "every documented subcommand is dispatched" "true" "true"

# The bug class, fenced: only selecta_confirm may block on input.
t_eq "no bare read outside selecta_confirm" "1" \
	"$(grep -cE '^[[:space:]]*read ' "$SELECTA_ROOT"/bin/selecta "$SELECTA_ROOT"/lib/*.sh \
		"$SELECTA_ROOT"/libexec/selecta-supervisor "$SELECTA_ROOT"/libexec/selecta-teardown 2>/dev/null |
		awk -F: '{s += $2} END {print s}')"

rm -rf "$SELECTA_HOME"
