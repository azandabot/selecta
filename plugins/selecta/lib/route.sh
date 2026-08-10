#!/bin/sh
# Which backend serves a request.

# Radio is windowless and stays the default. YouTube opens a visible window, so
# it is reserved for requests that actually name a recording.
#
# The first version treated "song", "track" and "album" as evidence of a named
# recording. It is the opposite: "play me a song", "put a track on", "some
# chill songs for coding" are all how people ask for background music, and all
# three opened a window. Meanwhile "drum and bass" went to YouTube because it
# is three words and no single station matched it confidently.
#
# Order matters here. The keyword test used to run before the resolver was
# consulted at all, so "some chill songs for coding" was routed to YouTube
# while the catalogue was sitting on a confident match for it.
wants_youtube() {
	_wy_q=$1
	_wy_res=$2

	# Naming an artist is the one unambiguous signal, and it is the phrasing
	# people reach for when they mean one specific recording.
	case $_wy_q in
	*" by "*) return 0 ;;
	esac

	_wy_ok=$(printf '%s' "$_wy_res" | jq -r '.status // "none"' 2>/dev/null)

	# A confident station match is radio, whatever words the request contains.
	[ "$_wy_ok" = ok ] && return 1

	# Below that, confidence is useless as a signal: a genre nobody has a
	# station for and a title nobody has heard of both score around 0.1. The
	# vocabulary separates them. If the request IS a genre the catalogue
	# knows, it is a genre, however badly it happened to score.
	_wy_l=$(printf '%s' "$_wy_q" | tr '[:upper:]' '[:lower:]')
	if [ -r "${SELECTA_DATA:-$SELECTA_ROOT/data}/mood-map.json" ] &&
		jq -e --arg q "$_wy_l" '.moods | has($q)' \
			"${SELECTA_DATA:-$SELECTA_ROOT/data}/mood-map.json" >/dev/null 2>&1; then
		return 1
	fi

	# Nothing matched at all. Either a title we have never heard of, or a vibe
	# nobody has a station for. These words separate the two: they describe a
	# kind of listening rather than name a thing.
	case " $_wy_l " in
	*some* | *any* | *" a "* | *" me "* | *music* | *songs* | *tracks* | \
		*beats* | *vibe* | *mood* | *playlist* | *radio* | *station* | \
		*" for "* | *while* | *cause* | *when* | *studying* | \
		*focus* | *coding* | *working* | *chill* | *relax* | *background*)
		return 1
		;;
	esac

	# A title is short and specific, and at least two words: one word is a
	# genre the offline catalogue has not heard of yet, and radio-browser can
	# serve those without a window. A ten-word sentence with no vocabulary
	# match is somebody talking, not somebody naming a track.
	_wy_words=$(printf '%s' "$_wy_q" | wc -w | tr -d ' ')
	[ "$_wy_words" -ge 2 ] && [ "$_wy_words" -le 6 ] && return 0
	return 1
}
