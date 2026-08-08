#!/bin/sh
# Assertion helpers. Results are appended to $T_RESULTS so that tests running
# in subshells still report, and tests/run.sh tallies the file at the end.

t_eq() {
	# t_eq <description> <expected> <actual>
	if [ "$2" = "$3" ]; then
		printf 'ok %s\n' "$1" >>"$T_RESULTS"
	else
		printf 'not ok %s\n\texpected: [%s]\n\tactual:   [%s]\n' "$1" "$2" "$3" >>"$T_RESULTS"
	fi
}

t_ne() {
	if [ "$2" != "$3" ]; then
		printf 'ok %s\n' "$1" >>"$T_RESULTS"
	else
		printf 'not ok %s\n\texpected anything but: [%s]\n' "$1" "$2" >>"$T_RESULTS"
	fi
}

t_status() {
	# t_status <description> <expected-status> <command...>
	_ts_desc=$1
	_ts_want=$2
	shift 2
	"$@" >/dev/null 2>&1
	_ts_got=$?
	t_eq "$_ts_desc" "$_ts_want" "$_ts_got"
}

t_empty() {
	if [ -z "$2" ]; then
		printf 'ok %s\n' "$1" >>"$T_RESULTS"
	else
		printf 'not ok %s\n\texpected empty, got: [%s]\n' "$1" "$2" >>"$T_RESULTS"
	fi
}

# Scratch directory for tests that need a real filesystem or git repo.
# Deliberately outside SELECTA_ROOT: a scratch dir nested inside this
# repository would be part of it, so any "not a git repo" case would resolve to
# selecta itself and the test would assert the wrong thing.
t_tmpdir() {
	_tt=${TMPDIR:-/tmp}/selecta-tests/$$-$1
	rm -rf "$_tt"
	mkdir -p "$_tt"
	printf '%s' "$_tt"
}

t_git_init() {
	git -C "$1" init -q -b main
	git -C "$1" config user.name test
	git -C "$1" config user.email test@example.com
	git -C "$1" commit -q --allow-empty -m "initial commit"
}
