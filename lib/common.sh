#!/bin/sh
# Shared helpers for selecta.
#
# Sourced by bin/selecta, lib/*.sh and libexec/*. Deliberately NOT sourced by
# statusline/launcher.sh: the launcher runs on every status line refresh and
# must stay fork-free and dependency-free.

# The constants below are consumed by the files that source this one. Those are
# analysed separately, so every one is reported as unused without this.
# shellcheck disable=SC2034

SELECTA_VERSION=0.2.0
SELECTA_REPO_URL="https://github.com/azandabot/selecta"
SELECTA_USER_AGENT="selecta/$SELECTA_VERSION (+$SELECTA_REPO_URL)"

SELECTA_HOME=${SELECTA_HOME:-$HOME/.claude/selecta}
SELECTA_RUN=$SELECTA_HOME/run
SELECTA_CACHE=$SELECTA_HOME/cache
SELECTA_SOUNDTRACKS=$SELECTA_HOME/soundtracks
SELECTA_LOGDIR=$SELECTA_HOME/log

SELECTA_CONFIG=$SELECTA_HOME/config.json
SELECTA_LOGFILE=$SELECTA_LOGDIR/selecta.log
SELECTA_STATE=$SELECTA_RUN/state.json
SELECTA_SEGMENT=$SELECTA_RUN/segment
SELECTA_HEARTBEAT=$SELECTA_RUN/heartbeat
SELECTA_PIDFILE=$SELECTA_RUN/supervisor.pid
SELECTA_LOCKDIR=$SELECTA_RUN/supervisor.lock
SELECTA_CONTROL_SOCK=$SELECTA_RUN/control.sock
SELECTA_MPV_SOCK=$SELECTA_RUN/mpv.sock

SELECTA_LOG_MAX_BYTES=1048576

# Exit codes. Anything non-zero must carry meaning; callers branch on these.
EX_OK=0
EX_USAGE=2
EX_UNWRITABLE=3
EX_MISSING_DEP=4
EX_NETWORK=5
EX_NOTFOUND=6

# --- output -----------------------------------------------------------------
# Diagnostics go to stderr so stdout stays parseable. The supervisor redirects
# stdout to /dev/null entirely, because as a plugin monitor every stdout line
# it emits is surfaced to the session as a notification.

selecta_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

selecta_info() { printf '%s\n' "$*"; }
selecta_warn() { printf 'selecta: %s\n' "$*" >&2; }

selecta_die() {
	code=$1
	shift
	printf 'selecta: %s\n' "$*" >&2
	selecta_log error "$*"
	exit "$code"
}

selecta_log() {
	level=$1
	shift
	[ -d "$SELECTA_LOGDIR" ] || mkdir -p "$SELECTA_LOGDIR" 2>/dev/null || return 0
	selecta_rotate_log
	printf '%s [%s] %s\n' "$(selecta_now_iso)" "$level" "$*" >>"$SELECTA_LOGFILE" 2>/dev/null || true
}

selecta_rotate_log() {
	[ -f "$SELECTA_LOGFILE" ] || return 0
	size=$(selecta_file_size "$SELECTA_LOGFILE")
	[ "$size" -gt "$SELECTA_LOG_MAX_BYTES" ] 2>/dev/null || return 0
	mv -f "$SELECTA_LOGFILE" "$SELECTA_LOGFILE.1" 2>/dev/null || true
}

# --- portability ------------------------------------------------------------
# BSD and GNU coreutils disagree on stat and sha; resolve once, here.

selecta_file_size() {
	stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0
}

selecta_file_mtime() {
	stat -f%m "$1" 2>/dev/null || stat -c%Y "$1" 2>/dev/null || echo 0
}

# True when $1 exists and is newer than $2 seconds.
selecta_fresh() {
	[ -s "$1" ] || return 1
	_fr_age=$(($(date +%s) - $(selecta_file_mtime "$1")))
	[ "$_fr_age" -lt "$2" ]
}

selecta_sha() {
	if command -v shasum >/dev/null 2>&1; then
		printf '%s' "$1" | shasum -a 256 2>/dev/null | cut -d' ' -f1
	else
		printf '%s' "$1" | sha256sum 2>/dev/null | cut -d' ' -f1
	fi
}

selecta_sha8() { selecta_sha "$1" | cut -c1-8; }
selecta_sha16() { selecta_sha "$1" | cut -c1-16; }

# realpath(1) is absent on older macOS; this works everywhere and does not
# require the target's basename to exist.
selecta_realpath() {
	_rp_dir=$(dirname -- "$1")
	_rp_base=$(basename -- "$1")
	if [ -d "$1" ]; then
		(cd -- "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"
	elif [ -d "$_rp_dir" ]; then
		printf '%s/%s' "$(cd -- "$_rp_dir" && pwd -P)" "$_rp_base"
	else
		printf '%s' "$1"
	fi
}

selecta_have() { command -v "$1" >/dev/null 2>&1; }

selecta_require() {
	selecta_have "$1" && return 0
	selecta_die "$EX_MISSING_DEP" "$1 is required but not installed. Run: /selecta doctor"
}

# --- filesystem -------------------------------------------------------------

selecta_ensure_dirs() {
	mkdir -p "$SELECTA_HOME" "$SELECTA_CACHE" "$SELECTA_SOUNDTRACKS" "$SELECTA_LOGDIR" 2>/dev/null ||
		return "$EX_UNWRITABLE"
	mkdir -p "$SELECTA_RUN" 2>/dev/null || return "$EX_UNWRITABLE"
	chmod 700 "$SELECTA_RUN" 2>/dev/null || true
	return 0
}

# Writes stdin to $1 atomically. The temp file is created in the destination
# directory so the rename cannot cross a filesystem boundary.
selecta_atomic_write() {
	_aw_dest=$1
	_aw_dir=$(dirname -- "$_aw_dest")
	mkdir -p "$_aw_dir" 2>/dev/null || return "$EX_UNWRITABLE"
	_aw_tmp=$_aw_dir/.selecta.$$.tmp
	cat >"$_aw_tmp" 2>/dev/null || {
		rm -f "$_aw_tmp"
		return "$EX_UNWRITABLE"
	}
	mv -f "$_aw_tmp" "$_aw_dest" 2>/dev/null || {
		rm -f "$_aw_tmp"
		return "$EX_UNWRITABLE"
	}
	return 0
}

# --- locking ----------------------------------------------------------------
# mkdir is atomic on every POSIX filesystem, and unlike flock(1) it exists on
# both macOS and Linux without a package.

selecta_lock_acquire() {
	mkdir "$SELECTA_LOCKDIR" 2>/dev/null || return 1
	printf '%s\n' "$$" >"$SELECTA_LOCKDIR/pid" 2>/dev/null || true
	return 0
}

selecta_lock_release() {
	rm -rf "$SELECTA_LOCKDIR" 2>/dev/null || true
}

# A lock whose owning process is gone is stale; clear it so a crashed
# supervisor cannot wedge every future session.
selecta_lock_reap_stale() {
	[ -d "$SELECTA_LOCKDIR" ] || return 0
	_lk_pid=$(cat "$SELECTA_LOCKDIR/pid" 2>/dev/null)
	case $_lk_pid in
	'' | *[!0-9]*)
		selecta_lock_release
		return 0
		;;
	esac
	if selecta_pid_is_supervisor "$_lk_pid"; then
		return 1
	fi
	selecta_log warn "clearing stale lock from pid $_lk_pid"
	selecta_lock_release
	return 0
}

# PIDs are recycled. Confirming the command name before signalling keeps us
# from killing an unrelated process that inherited the number.
selecta_pid_is_supervisor() {
	_ps_pid=$1
	case $_ps_pid in
	'' | *[!0-9]*) return 1 ;;
	esac
	kill -0 "$_ps_pid" 2>/dev/null || return 1
	ps -o command= -p "$_ps_pid" 2>/dev/null | grep -q 'selecta-supervisor'
}

# --- json -------------------------------------------------------------------

selecta_json_get() {
	# selecta_json_get <file> <jq-filter> [default]
	_jg_file=$1
	_jg_filter=$2
	_jg_default=${3:-}
	[ -f "$_jg_file" ] || {
		printf '%s' "$_jg_default"
		return 0
	}
	_jg_out=$(jq -r "$_jg_filter // empty" "$_jg_file" 2>/dev/null)
	[ -n "$_jg_out" ] || _jg_out=$_jg_default
	printf '%s' "$_jg_out"
}

# --- config -----------------------------------------------------------------

# jq's --argjson rejects an empty string, so any value built by a command
# substitution has to be defended: one upstream hiccup otherwise takes down the
# whole command with "invalid JSON text passed to --argjson".
selecta_json_or() {
	# selecta_json_or <value> <fallback>
	if [ -n "${1:-}" ] && printf '%s' "$1" | jq -e . >/dev/null 2>&1; then
		printf '%s' "$1"
	else
		printf '%s' "$2"
	fi
}

selecta_cfg_get() {
	# selecta_cfg_get <jq-path> <default>
	[ -s "$SELECTA_CONFIG" ] || {
		printf '%s' "$2"
		return 0
	}
	_cg=$(jq -c "$1 // empty" "$SELECTA_CONFIG" 2>/dev/null)
	[ -n "$_cg" ] || _cg=$2
	printf '%s' "$_cg"
}

selecta_cfg_set() {
	# selecta_cfg_set <jq-path> <json-value>
	_cs_cur='{}'
	[ -s "$SELECTA_CONFIG" ] && jq -e . "$SELECTA_CONFIG" >/dev/null 2>&1 &&
		_cs_cur=$(cat "$SELECTA_CONFIG")
	printf '%s' "$_cs_cur" | jq --argjson v "$2" "$1 = \$v" |
		selecta_atomic_write "$SELECTA_CONFIG"
}

# A corrupt state or soundtrack file is preserved rather than discarded: these
# accumulate months of listening history and silently losing one is worse than
# any error message.
selecta_quarantine() {
	_q_file=$1
	[ -f "$_q_file" ] || return 0
	_q_dest="$_q_file.corrupt.$(date -u +%Y%m%dT%H%M%SZ)"
	mv -f "$_q_file" "$_q_dest" 2>/dev/null || return 1
	selecta_warn "unreadable file preserved at $_q_dest"
	selecta_log error "quarantined $_q_file -> $_q_dest"
	return 0
}
