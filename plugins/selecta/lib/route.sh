#!/bin/sh
# Which backend serves a request.

# Radio is windowless and stays the default. YouTube opens a visible window, so
# it is reserved for requests that actually need a specific recording.
#
# A request is treated as YouTube-shaped when it names something rather than
# describes a feeling: it resolves poorly against the mood vocabulary and looks
# like a title or artist. Anything that maps confidently to a mood stays on
# radio, so asking for background music never puts a window on screen.
wants_youtube() {
	_wy_q=$1
	case $_wy_q in
	*" by "* | *"song"* | *"track"* | *"album"* | *"official"* | *"video"*) return 0 ;;
	esac
	# Three or more words with no confident mood match reads as a title.
	_wy_words=$(printf '%s' "$_wy_q" | wc -w | tr -d ' ')
	_wy_conf=$(printf '%s' "$2" | jq -r '.confidence')
	_wy_ok=$(printf '%s' "$2" | jq -r '.status')
	[ "$_wy_ok" = ok ] && return 1
	[ "$_wy_words" -ge 3 ] && return 0
	return 1
}
