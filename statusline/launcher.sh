#!/bin/sh
# selecta status line.
#
# Copied to ~/.claude/selecta/statusline.sh at install time and referenced from
# the user's settings.json. It lives outside the plugin directory on purpose:
# plugins install under a versioned path, so a status line pointing into the
# plugin would break on every update.
#
# Two hard rules, because this runs every couple of seconds and a failure here
# breaks the user's status line rather than just selecta:
#   1. Every path exits 0. Missing, empty, truncated, corrupt or
#      directory-shaped state all produce no output and a clean exit.
#   2. No forks in the common path. No jq, no git, no subprocesses.

# Drain the session JSON on stdin with the shell builtin. We do not need it,
# but leaving it unread can give the caller a broken pipe.
IFS= read -r _ignored 2>/dev/null
[ -n "${_ignored:-}" ] || true

SELECTA_HOME=${SELECTA_HOME:-$HOME/.claude/selecta}
_seg=$SELECTA_HOME/run/segment
_wrapped=$SELECTA_HOME/run/wrapped_command

# Liveness beacon for the supervisor's watchdog. A redirect, not a fork.
: >"$SELECTA_HOME/run/heartbeat" 2>/dev/null

# Wrap mode: the user already had a status line, so theirs prints first and
# untouched. This is the only branch that forks, and only because it must.
if [ -s "$_wrapped" ]; then
	IFS= read -r _cmd <"$_wrapped" 2>/dev/null
	if [ -n "${_cmd:-}" ]; then
		printf '%s' "${_ignored:-}" | sh -c "$_cmd" 2>/dev/null || true
	fi
fi

[ -s "$_seg" ] || exit 0

{
	IFS= read -r _colored
	IFS= read -r _plain
} <"$_seg" 2>/dev/null || exit 0
[ -n "${_colored:-}" ] || exit 0

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = dumb ]; then
	_line=${_plain:-$_colored}
else
	_line=$_colored
fi

# COLUMNS is set by the host. tput does not work here: output is captured, so
# there is no tty to query.
_cols=${COLUMNS:-80}
case $_cols in
'' | *[!0-9]*) _cols=80 ;;
esac

# Splitting on TAB with globbing disabled, so a track title containing * or ?
# cannot expand into filenames.
set -f
IFS='	'
# shellcheck disable=SC2086
set -- $_line
set +f
unset IFS

if [ "$_cols" -ge 120 ]; then
	_out=${3:-${2:-${1:-}}}
elif [ "$_cols" -ge 80 ]; then
	_out=${2:-${1:-}}
else
	_out=${1:-}
fi

[ -n "${_out:-}" ] && printf '%s\n' "$_out"
exit 0
