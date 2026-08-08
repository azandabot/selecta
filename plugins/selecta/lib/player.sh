#!/bin/sh
# Playback engine detection and launch.
#
# mpv only. It is the sole engine with an IPC socket, which is what gives
# volume, pause and live track metadata. ffplay was advertised here for two
# releases and never implemented; the supervisor hard-failed on it, so an
# ffplay-only machine looped between doctor and play forever.

selecta_engine() {
	if selecta_have mpv; then
		printf 'mpv'
	else
		printf 'none'
	fi
}

# The exact command to install what is missing, for the platform in hand. Shown
# to the user; never run without an explicit yes.
selecta_install_hint() {
	_ih_missing=$1
	if [ "$(uname -s)" = Darwin ]; then
		if selecta_have brew; then
			printf 'brew install %s' "$_ih_missing"
		else
			printf 'install Homebrew from https://brew.sh, then: brew install %s' "$_ih_missing"
		fi
	elif selecta_have apt-get; then
		printf 'sudo apt-get install -y %s' "$_ih_missing"
	elif selecta_have dnf; then
		printf 'sudo dnf install -y %s' "$_ih_missing"
	elif selecta_have pacman; then
		printf 'sudo pacman -S --noconfirm %s' "$_ih_missing"
	else
		printf 'install %s with your package manager' "$_ih_missing"
	fi
}

# --ao=null lets CI exercise the whole path (fetch, demux, ICY metadata, IPC)
# with no audio device present.
selecta_mpv_start() {
	_ms_ao=${SELECTA_AO:-}
	rm -f "$SELECTA_MPV_SOCK" 2>/dev/null || true
	# shellcheck disable=SC2086
	mpv --idle=yes \
		--no-video \
		--no-terminal \
		--no-config \
		--quiet \
		--audio-display=no \
		--cache=yes \
		--network-timeout=15 \
		--user-agent="$SELECTA_USER_AGENT" \
		--input-ipc-server="$SELECTA_MPV_SOCK" \
		${_ms_ao:+--ao=$_ms_ao} \
		>/dev/null 2>&1 &
	printf '%s' "$!"
}

# Blocks until mpv's socket appears. Bounded, because a player that never comes
# up must surface as an error rather than a hung session. Polls on an interval
# rather than spinning: this runs for the whole of mpv's startup.
selecta_mpv_wait() {
	_mw_tries=0
	_mw_max=${1:-100}
	while [ ! -S "$SELECTA_MPV_SOCK" ]; do
		_mw_tries=$((_mw_tries + 1))
		[ "$_mw_tries" -lt "$_mw_max" ] || return 1
		sleep 0.05
	done
	return 0
}
