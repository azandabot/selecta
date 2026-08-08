#!/bin/sh
# tests/run.sh [suite|path] [filter]
#
#   tests/run.sh              all suites
#   tests/run.sh unit         one suite
#   tests/run.sh unit/repo    one file (prefix match)
set -eu

TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
SELECTA_ROOT=$(cd -- "$TESTS_DIR/.." && pwd -P)
export SELECTA_ROOT

TARGET=${1:-all}
FILTER=${2:-}

# Built with printf because BSD sed does not interpret \033 escapes.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_GREEN=$(printf '\033[32m')
	C_RED=$(printf '\033[31m')
	C_BOLD=$(printf '\033[1m')
	C_OFF=$(printf '\033[0m')
else
	C_GREEN='' C_RED='' C_BOLD='' C_OFF=''
fi

T_RESULTS=$TESTS_DIR/.tmp/results.$$
export T_RESULTS
mkdir -p "$TESTS_DIR/.tmp"
: >"$T_RESULTS"

case $TARGET in
all) _pattern="$TESTS_DIR/unit $TESTS_DIR/integration" ;;
unit | integration | contract) _pattern="$TESTS_DIR/$TARGET" ;;
*) _pattern="$TESTS_DIR/$TARGET" ;;
esac

_files=''
for _p in $_pattern; do
	if [ -d "$_p" ]; then
		_found=$(find "$_p" -name '*.sh' -type f 2>/dev/null | sort)
	else
		_found=$(find "$(dirname -- "$_p")" -name "$(basename -- "$_p")*.sh" -type f 2>/dev/null | sort)
	fi
	_files="$_files
$_found"
done

_ran=0
for _f in $_files; do
	[ -n "$_f" ] || continue
	if [ -n "$FILTER" ]; then
		case $_f in
		*"$FILTER"*) ;;
		*) continue ;;
		esac
	fi
	printf '\n%s%s%s\n' "$C_BOLD" "${_f#"$TESTS_DIR"/}" "$C_OFF"
	_before=$(wc -l <"$T_RESULTS")
	# A test file that dies partway must not abort the whole run.
	sh "$_f" || printf 'not ok %s (test file exited non-zero)\n' "$_f" >>"$T_RESULTS"
	_after=$(wc -l <"$T_RESULTS")
	[ "$_after" -gt "$_before" ] || printf '  (no assertions)\n'
	_ran=$((_ran + 1))
	sed -n "$((_before + 1)),${_after}p" "$T_RESULTS" |
		sed "s/^ok /  ${C_GREEN}ok${C_OFF} /; s/^not ok /  ${C_RED}NOT OK${C_OFF} /"
done

# grep -c always prints a count, but exits 1 when that count is zero, so the
# exit status is swallowed rather than substituted for.
_pass=$(grep -c '^ok ' "$T_RESULTS" 2>/dev/null || true)
_fail=$(grep -c '^not ok ' "$T_RESULTS" 2>/dev/null || true)
rm -f "$T_RESULTS"
rm -rf "${TMPDIR:-/tmp}/selecta-tests/$$-"* 2>/dev/null || true

printf '\n%s files, %s%s passed%s, ' "$_ran" "$C_GREEN" "$_pass" "$C_OFF"
if [ "$_fail" -gt 0 ]; then
	printf '%s%s failed%s\n' "$C_RED" "$_fail" "$C_OFF"
	exit 1
fi
printf '0 failed\n'
