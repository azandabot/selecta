#!/bin/sh
# The YouTube mini player window.
#
# YouTube's Developer Policies forbid playing from "a player that is not
# displayed", and Required Minimum Functionality sets a 200x200 floor on the
# viewport. So this opens a real, visible window and never hides, minimises or
# shrinks it below that. The window is the price of the catalogue.
#
# App mode is preferred because it gives a chromeless window at a size we can
# set, which is the least intrusive shape that still satisfies "displayed".

SELECTA_WIN_W=480
SELECTA_WIN_H=380

selecta_httpd_url() {
	[ -s "$SELECTA_RUN/httpd.json" ] || return 1
	jq -r '.url // empty' "$SELECTA_RUN/httpd.json" 2>/dev/null
}

selecta_httpd_up() {
	_hu=$(selecta_httpd_url) || return 1
	[ -n "$_hu" ] || return 1
	_ho=$(jq -r '.origin' "$SELECTA_RUN/httpd.json" 2>/dev/null)
	curl -sf --max-time 2 "$_ho/health" >/dev/null 2>&1
}

selecta_httpd_start() {
	selecta_httpd_up && return 0
	selecta_have python3 || return "$EX_MISSING_DEP"
	rm -f "$SELECTA_RUN/httpd.json" 2>/dev/null
	# nohup rather than setsid: setsid does not exist on macOS.
	export SELECTA_HOME SELECTA_ROOT
	nohup "$SELECTA_ROOT/libexec/selecta-httpd" </dev/null >>"$SELECTA_LOGDIR/httpd.log" 2>&1 &
	_hs=0
	while [ "$_hs" -lt 100 ]; do
		selecta_httpd_up && return 0
		_hs=$((_hs + 1))
		sleep 0.05
	done
	return "$EX_NETWORK"
}

_selecta_chrome_bin() {
	for _cb in \
		"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
		"/Applications/Chromium.app/Contents/MacOS/Chromium" \
		"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
		"/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
		[ -x "$_cb" ] && {
			printf '%s' "$_cb"
			return 0
		}
	done
	for _cb in google-chrome chromium chromium-browser microsoft-edge brave-browser; do
		selecta_have "$_cb" && {
			command -v "$_cb"
			return 0
		}
	done
	return 1
}

selecta_window_open() {
	_wo_url=$1
	# A dedicated profile directory keeps the mini player out of the user's
	# session, tabs and history.
	_wo_prof=$SELECTA_HOME/browser
	mkdir -p "$_wo_prof" 2>/dev/null || true

	if _wo_bin=$(_selecta_chrome_bin); then
		nohup "$_wo_bin" \
			--app="$_wo_url" \
			--user-data-dir="$_wo_prof" \
			--window-size=$SELECTA_WIN_W,$SELECTA_WIN_H \
			--no-first-run \
			--no-default-browser-check \
			--autoplay-policy=no-user-gesture-required \
			</dev/null >/dev/null 2>&1 &
		return 0
	fi

	# No Chromium-family browser. The default browser still satisfies the
	# visibility requirement, it just cannot be sized.
	if [ "$(uname -s)" = Darwin ]; then
		open "$_wo_url" >/dev/null 2>&1 && return 0
	elif selecta_have xdg-open; then
		xdg-open "$_wo_url" >/dev/null 2>&1 && return 0
	fi
	return "$EX_MISSING_DEP"
}

# Liveness is measured by whether the page is still polling, not by whether a
# browser process exists. Closing the window leaves the browser running with
# other tabs, so a pid check reports a player that is gone and the next play
# queues a command nobody will ever read.
selecta_window_up() {
	[ -s "$SELECTA_RUN/httpd.json" ] || return 1
	_wu_o=$(jq -r '.origin // empty' "$SELECTA_RUN/httpd.json" 2>/dev/null)
	[ -n "$_wu_o" ] || return 1
	_wu_age=$(curl -sf --max-time 2 "$_wu_o/health" 2>/dev/null |
		jq -r '.page_age // empty' 2>/dev/null)
	[ -n "$_wu_age" ] || return 1
	# Page polls roughly every second; five seconds of silence means gone.
	awk -v a="$_wu_age" 'BEGIN { exit !(a < 5) }'
}

yt_ensure_window() {
	if ! selecta_httpd_start; then
		if ! selecta_have python3; then
			printf 'selecta: the YouTube player needs python3.\n\n  %s\n' \
				"$(selecta_install_hint python3)" >&2
		else
			printf 'selecta: the player server would not start. See %s\n' \
				"$SELECTA_LOGDIR/httpd.log" >&2
		fi
		return 1
	fi
	selecta_window_up && return 0
	_yw_url=$(selecta_httpd_url) || return 1
	selecta_window_open "$_yw_url" || {
		printf 'selecta: could not open a browser window for the player.\n' >&2
		printf 'Open this yourself and leave it visible:\n  %s\n' "$_yw_url" >&2
		return 1
	}
	# Wait for the page to start polling before returning, so the caller does
	# not queue a command into a window that has not loaded yet.
	_yw_i=0
	while [ "$_yw_i" -lt 100 ]; do
		selecta_window_up && return 0
		_yw_i=$((_yw_i + 1))
		sleep 0.1
	done
	printf 'selecta: the player window did not come up.\n' >&2
	printf 'Open this and leave it visible:\n  %s\n' "$_yw_url" >&2
	return 1
}
