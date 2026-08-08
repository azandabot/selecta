#!/bin/sh
# Shared helpers for selecta.
#
# Sourced by bin/selecta, lib/*.sh and libexec/*. Deliberately NOT sourced by
# statusline/launcher.sh: the launcher runs on every status line refresh and
# must stay fork-free and dependency-free.

# The constants below are consumed by the files that source this one. Those are
# analysed separately, so every one is reported as unused without this.
# shellcheck disable=SC2034

SELECTA_VERSION=0.3.0
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
SELECTA_MPV_SOCK=$SELECTA_RUN/mpv.sock

SELECTA_LOG_MAX_BYTES=1048576

# Exit codes. Anything non-zero must carry meaning; callers branch on these.
EX_USAGE=2
EX_UNWRITABLE=3
EX_MISSING_DEP=4
EX_NETWORK=5
EX_NOTFOUND=6
EX_NEEDS_CONSENT=7

# --- output -----------------------------------------------------------------
# Diagnostics go to stderr so stdout stays parseable. The supervisor redirects
# stdout to /dev/null entirely, because as a plugin monitor every stdout line
# it emits is surfaced to the session as a notification.

selecta_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

# --- consent ---------------------------------------------------------------

# selecta_confirm <expected-answer> <prompt> <how-to-confirm>
#
# The Bash tool has no TTY. `read` there hits EOF immediately and, under
# `set -e`, killed the script mid-command: `statusline on` could never succeed
# through an agent, and printed a question nobody could answer. With no TTY we
# say how to confirm instead and return EX_NEEDS_CONSENT, which is a state, not
# a failure.
selecta_confirm() {
	if [ -t 0 ]; then
		printf '%s' "$2"
		read -r _cf_ans || _cf_ans=''
		[ "$_cf_ans" = "$1" ] && return 0
		printf 'Not confirmed, nothing changed.\n'
		return "$EX_NEEDS_CONSENT"
	fi
	printf '\nNothing has been changed. To do it after the user agrees:\n\n  %s\n' "$3" >&2
	return "$EX_NEEDS_CONSENT"
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
	# Not `// empty`: jq's alternative operator treats false as absent, so
	# `.privacy.record_commits` set to false silently fell back to the default
	# true and kept stamping commits after the user turned it off.
	_cg=$(jq -c "$1" "$SELECTA_CONFIG" 2>/dev/null)
	[ -n "$_cg" ] && [ "$_cg" != null ] || _cg=$2
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

# --- the selecta-youtube boundary --------------------------------------------
#
# YouTube lives in its own plugin, because it needs an API key and a visible
# browser window and most people want neither. The two plugins meet at three
# files under run/ and nowhere else. Readers live here so selecta can see and
# control a YouTube track without depending on the plugin that plays it; the
# starting and searching stay on the other side.
#
#   run/httpd.json   written by the player server, read by both
#   run/yt-cmd.json  a single queued command for the player page
#   run/yt-queue.json the candidate list the player works through

# Commands are queued as a file rather than posted, so the client stays a shell
# script with no HTTP client.
selecta_yt_queue() {
	printf '%s\n' "$1" | selecta_atomic_write "$SELECTA_RUN/yt-cmd.json"
}

# Liveness is measured by whether the page is still polling, not by whether a
# browser process exists. Closing the window leaves the browser running with
# other tabs, so a pid check reports a player that is gone and the next command
# is queued for nobody.
selecta_window_up() {
	[ -s "$SELECTA_RUN/httpd.json" ] || return 1
	selecta_have jq || return 1
	_wu_o=$(jq -r '.origin // empty' "$SELECTA_RUN/httpd.json" 2>/dev/null)
	[ -n "$_wu_o" ] || return 1
	selecta_have curl || return 1
	_wu_age=$(curl -sf --max-time 2 "$_wu_o/health" 2>/dev/null |
		jq -r '.page_age // empty' 2>/dev/null)
	[ -n "$_wu_age" ] || return 1
	# The page polls roughly every second; five seconds of silence means gone.
	awk -v a="$_wu_age" 'BEGIN { exit !(a < 5) }'
}

# The player window is a singleton. Each play used to launch another one:
# when the server restarts it binds a new port, so pages from a previous run
# poll an address that no longer answers, stop reporting, and are treated as
# gone while their windows stay on screen. They accumulate until the machine
# slows down.
#
# Matched on the dedicated profile directory, which no process outside this
# plugin passes, so this can never reach the user's own browser.
selecta_yt_window_close() {
	_wc_prof=$SELECTA_HOME/browser
	selecta_have pkill || return 0
	pkill -f -- "--user-data-dir=$_wc_prof" 2>/dev/null || true
	rm -f "$SELECTA_RUN/yt-cmd.json" 2>/dev/null || true
	return 0
}

# Never globs the versioned plugin cache path. The pointer is written by
# selecta-youtube on every run, exactly as selecta writes its own.
selecta_yt_bin() {
	if [ -n "${SELECTA_YT_BIN:-}" ] && [ -x "${SELECTA_YT_BIN:-}" ]; then
		printf '%s' "$SELECTA_YT_BIN"
		return 0
	fi
	if [ -r "$SELECTA_HOME/yt-bin-path" ]; then
		IFS= read -r _yb <"$SELECTA_HOME/yt-bin-path" 2>/dev/null || _yb=''
		if [ -n "${_yb:-}" ] && [ -x "$_yb" ]; then
			printf '%s' "$_yb"
			return 0
		fi
	fi
	command -v selecta-youtube 2>/dev/null
}

selecta_yt_install_hint() {
	printf 'YouTube lives in a companion plugin:\n\n'
	printf '  /plugin install selecta-youtube@azandabot-selecta\n\n'
	printf 'Radio needs no key and no window. YouTube needs both.\n'
}
