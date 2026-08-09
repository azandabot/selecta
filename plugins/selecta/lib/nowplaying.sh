#!/bin/sh
# Reads what is playing, from whatever is playing it.
#
# This is the part of selecta that works on a bare machine. Showing the track
# from Spotify or Apple Music needs nothing that is not already on macOS: no
# mpv, no jq, no key, no network. Everything here is deliberately jq-free.
#
# selecta_np_probe prints one tab-separated line and nothing else:
#     status \t artist \t title \t source-label
# status is playing | paused. No output means nothing is playing.
#
# The supervisor calls this on its poll tick. The status line launcher never
# does: osascript costs about 64ms, and at a two second refresh that would be
# a permanent tax on every session.

# --- macOS -------------------------------------------------------------------

# Three things here are load-bearing:
#
#   pgrep gate  `tell application "Spotify"` LAUNCHES Spotify if it is not
#               running: AppleScript starts the target to deliver the event.
#               The gate is also 3x cheaper than finding out the slow way.
#   long names  `set st to ...` is a SYNTAX ERROR inside a Music tell block.
#               Two-letter identifiers collide with the app's own dictionary.
#   timeout     a busy Music.app answers -1712 instead of replying, which
#               would stall the poll tick.
_np_macos() {
	# _np_macos <process-name> <app-name> <display-label>
	pgrep -x "$1" >/dev/null 2>&1 || return 1

	_np_err=$SELECTA_RUN/osa.err
	_np_out=$(osascript 2>"$_np_err" <<AS
with timeout of 2 seconds
	tell application "$2"
		try
			if player state is playing then
				set theState to "playing"
			else if player state is paused then
				set theState to "paused"
			else
				return ""
			end if
			set theArtist to ""
			set theName to ""
			try
				set theArtist to artist of current track
				set theName to name of current track
			end try
			if theArtist is missing value then set theArtist to ""
			if theName is missing value then set theName to ""
			if theName is "" then
				try
					set theName to current stream title
				end try
			end if
			if theName is missing value then set theName to ""
			if theName is "" then return ""
			return theState & tab & theArtist & tab & theName
		on error
			return ""
		end try
	end tell
end timeout
AS
	) || {
		_np_note_denied
		return 1
	}
	[ -n "$_np_out" ] || return 1
	printf '%s\t%s\n' "$_np_out" "$3"
}

# A denied Automation prompt fails with -1743 every single time. Left
# unhandled that is a wasted 64ms fork every two seconds, forever, so the
# refusal is remembered and the adapter stops asking.
_np_note_denied() {
	grep -q -- '-1743\|Not authorized' "$SELECTA_RUN/osa.err" 2>/dev/null || return 0
	selecta_cfg_set '.nowplaying.macos_automation' '"denied"' 2>/dev/null || true
	selecta_log warn "macOS automation denied; foreign player detection off"
}

_np_darwin() {
	[ "$(selecta_cfg_get '.nowplaying.macos_automation' '""' | tr -d '"')" = denied ] && return 1
	selecta_have osascript || return 1
	selecta_have pgrep || return 1
	_np_macos Spotify Spotify Spotify && return 0
	_np_macos Music Music "Apple Music" && return 0
	return 1
}

# --- Linux -------------------------------------------------------------------

# playerctl covers every MPRIS player in one binary: Spotify, VLC, Firefox,
# Chromium, mpv with the mpris script. A hand-rolled dbus-send parser was
# considered and rejected: its output is GVariant text, and any sed for it
# breaks on a title containing an apostrophe, which is a lot of songs.
_np_linux() {
	selecta_have playerctl || return 1
	_np_l=$(playerctl -a metadata \
		--format '{{status}}	{{artist}}	{{title}}	{{playerName}}' 2>/dev/null |
		awk -F'\t' '
			NF >= 3 && $1 == "Playing" { print "playing\t" $2 "\t" $3 "\t" $4; found = 1; exit }
			NF >= 3 && $1 == "Paused" && !p { p = "paused\t" $2 "\t" $3 "\t" $4 }
			END { if (!found && p) print p }')
	[ -n "$_np_l" ] || return 1
	printf '%s\n' "$_np_l"
}

# --- getting out of the way ----------------------------------------------------
#
# Starting selecta while Spotify or Apple Music is playing used to give you
# both at once. Nothing in the audio stack prevents that: two processes, two
# streams, one pair of speakers.
#
# So selecta pauses what is already playing before it starts. Pause, never
# stop: the user gets their position back with one press in their own app.
# Same pgrep gate as the probe, so this can never launch an app that was
# closed, and same TCC latch, so a refused Automation prompt is not re-asked
# every time.
#
# Set playback.pause_others to false to keep both.
selecta_np_pause_others() {
	[ "$(selecta_cfg_get '.playback.pause_others' true)" = false ] && return 0
	case $(uname -s) in
	Darwin)
		[ "$(selecta_cfg_get '.nowplaying.macos_automation' '""' | tr -d '"')" = denied ] &&
			return 0
		selecta_have osascript || return 0
		selecta_have pgrep || return 0
		for _po in "Spotify:Spotify" "Music:Music"; do
			_po_proc=${_po%%:*}
			_po_app=${_po#*:}
			pgrep -x "$_po_proc" >/dev/null 2>&1 || continue
			osascript >/dev/null 2>&1 <<AS
with timeout of 2 seconds
	tell application "$_po_app"
		try
			if player state is playing then pause
		end try
	end tell
end timeout
AS
		done
		;;
	Linux)
		# -a would also pause the browser tab the user is reading, so this
		# only reaches players that are actually playing audio.
		selecta_have playerctl || return 0
		playerctl -a pause >/dev/null 2>&1 || true
		;;
	esac
	return 0
}

# --- our own player ----------------------------------------------------------
# Ranked first: if the user started radio from this session and also has
# Spotify paused in the background, ours is the one they were controlling.
_np_youtube() {
	selecta_have jq || return 1
	selecta_window_up 2>/dev/null || return 1
	[ -s "$SELECTA_STATE" ] || return 1
	jq -r 'if (.source.provider // "") != "youtube" then empty
		elif (.status // "") == "playing" or (.status // "") == "paused"
		then [.status, (.now.artist // ""), (.now.title // .source.title // ""), "YouTube"]
			| @tsv
		else empty end' "$SELECTA_STATE" 2>/dev/null | grep . || return 1
}

_np_selecta() {
	selecta_ipc_up 2>/dev/null || return 1
	_np_paused=$(selecta_ipc_get pause 2>/dev/null)
	_np_path=$(selecta_ipc_get path 2>/dev/null)
	[ -n "$_np_path" ] && [ "$_np_path" != null ] || return 1
	_np_st=playing
	[ "$_np_paused" = true ] && _np_st=paused

	_np_meta=$(selecta_ipc_get metadata 2>/dev/null)
	_np_title=$(printf '%s' "$_np_meta" | jq -r '.["icy-title"] // ""' 2>/dev/null)
	_np_label=$(selecta_json_or "$(cat "$SELECTA_RUN/source.json" 2>/dev/null)" '{}' |
		jq -r '.title // "selecta"' 2>/dev/null)
	[ -n "$_np_label" ] || _np_label=selecta

	case $_np_title in
	*" - "*)
		printf '%s\t%s\t%s\t%s\n' "$_np_st" "${_np_title%% - *}" "${_np_title#* - }" "$_np_label"
		;;
	"")
		printf '%s\t\t\t%s\n' "$_np_st" "$_np_label"
		;;
	*)
		printf '%s\t\t%s\t%s\n' "$_np_st" "$_np_title" "$_np_label"
		;;
	esac
}

# --- entry point --------------------------------------------------------------

# AppleScript's null coerces to the literal words "missing value" the moment
# anything stringifies it. It has reached the status line once; it does not get
# a second chance from any adapter.
_np_sane() {
	case $1 in
	*"missing value"*) return 1 ;;
	esac
	[ -n "$(printf '%s' "$1" | cut -f3)" ] || return 1
	printf '%s\n' "$1"
}

selecta_np_probe() {
	[ "$(selecta_cfg_get '.nowplaying.disabled' false)" = true ] && return 1
	_np_out=$(_np_selecta) && _np_sane "$_np_out" && return 0
	_np_out=$(_np_youtube) && _np_sane "$_np_out" && return 0
	case $(uname -s) in
	Darwin) _np_out=$(_np_darwin) && _np_sane "$_np_out" && return 0 ;;
	Linux) _np_out=$(_np_linux) && _np_sane "$_np_out" && return 0 ;;
	esac
	return 1
}

# What doctor reports about this machine's ability to see other players.
selecta_np_capability() {
	case $(uname -s) in
	Darwin)
		if [ "$(selecta_cfg_get '.nowplaying.macos_automation' '""' | tr -d '"')" = denied ]; then
			printf 'DENIED. Re-enable in System Settings > Privacy & Security > Automation,\n           then: selecta config nowplaying.macos_automation null'
		elif selecta_have osascript; then
			printf 'Spotify and Apple Music'
		else
			printf 'none (no osascript)'
		fi
		;;
	Linux)
		if selecta_have playerctl; then
			printf 'any MPRIS player'
		else
			printf 'no playerctl. Only selecta radio will show.\n           %s' \
				"$(selecta_install_hint playerctl)"
		fi
		;;
	*) printf 'not supported on this platform' ;;
	esac
}
