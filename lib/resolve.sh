#!/bin/sh
# Free text to playable audio.
#
# Tier 0  exact station id, exact title, or a user alias      offline, instant
# Tier 1  mood vocabulary and token scoring over the catalog  offline-capable
# Tier 2+ radio-browser, Jamendo, Archive.org                 lib/resolve-net.sh
#
# The model never builds a stream URL. It calls `selecta resolve --json` and,
# when the answer is ambiguous, rewrites the query into catalog vocabulary and
# calls again. Keeping URL construction here is what makes a hallucinated
# stream structurally impossible.

SELECTA_DATA=${SELECTA_DATA:-$SELECTA_ROOT/data}
SELECTA_CATALOG_TTL=21600
SELECTA_CONFIDENT=0.7

# --- catalog ----------------------------------------------------------------

# Freshest catalog available: cached, else network, else stale cache, else the
# seed baked into the plugin. Tier 1 therefore works with no network at all.
selecta_catalog() {
	_cat=$SELECTA_CACHE/somafm-channels.json

	if selecta_fresh "$_cat" "$SELECTA_CATALOG_TTL"; then
		printf '%s' "$_cat"
		return 0
	fi

	if [ "${SELECTA_OFFLINE:-0}" != 1 ] && selecta_have curl; then
		_tmp=$SELECTA_CACHE/.channels.$$.json
		mkdir -p "$SELECTA_CACHE" 2>/dev/null || true
		if curl -sS --max-time 12 -A "$SELECTA_USER_AGENT" \
			https://somafm.com/channels.json -o "$_tmp" 2>/dev/null &&
			jq -e '.channels|length > 0' "$_tmp" >/dev/null 2>&1; then
			mv -f "$_tmp" "$_cat" 2>/dev/null && {
				printf '%s' "$_cat"
				return 0
			}
		fi
		rm -f "$_tmp" 2>/dev/null || true
		selecta_log warn "somafm catalog refresh failed, using fallback"
	fi

	if [ -s "$_cat" ]; then
		printf '%s' "$_cat"
		return 0
	fi
	printf '%s' "$SELECTA_DATA/somafm-channels.seed.json"
}

# --- query normalization ----------------------------------------------------

# Strips the filler around a request so that "play me something chill please"
# and "chill" reach the same place.
selecta_normalize_query() {
	printf '%s' "$1" |
		tr '[:upper:]' '[:lower:]' |
		sed -e 's/[^a-z0-9 -]/ /g' -e 's/  */ /g' -e 's/^ //' -e 's/ $//' |
		awk '{
			drop = " play me some something a an the with for and to of please on put get gimme give i want need listen listening music track song songs tunes sound sounds stuff like kinda kind bit more thats that ";
			out = "";
			for (i = 1; i <= NF; i++)
				if (index(drop, " " $i " ") == 0) out = out (out == "" ? "" : " ") $i;
			print (out == "" ? $0 : out);
		}'
}

# --- resolution -------------------------------------------------------------

# Emits the resolver JSON contract:
#   {status, confidence, query, hint_tags[], candidates[]}
# status is ok | ambiguous | none. Callers branch on status, never on prose.
selecta_resolve() {
	_rq_raw=$1
	_rq=$(selecta_normalize_query "$_rq_raw")
	_cat_file=$(selecta_catalog)
	_mood_file=$SELECTA_DATA/mood-map.json

	jq -n \
		--arg raw "$_rq_raw" \
		--arg q "$_rq" \
		--argjson confident "$SELECTA_CONFIDENT" \
		--slurpfile cat "$_cat_file" \
		--slurpfile mood "$_mood_file" \
		'
		def chans: $cat[0].channels;
		def moods: ($mood[0].moods // {});
		def toks: ($q | split(" ") | map(select(length > 1)));

		# Text scoring ignores tokens shorter than three characters. "sa" in
		# "Kwiish SA" matched Bossa, bossanova, the id bossa and Samba in the
		# description, hitting every field at once and scoring a station at
		# 0.9 for an artist name it has nothing to do with. Short tokens are
		# almost always initials or particles and carry no signal here; real
		# short terms like "80s" are three characters and still count.
		def textToks: (toks | map(select(length > 2)));

		def card($c; $score; $why):
			{ id: ("somafm:" + $c.id),
			  kind: "station",
			  provider: "somafm",
			  title: $c.title,
			  genre: ($c.genre // ""),
			  description: ($c.description // ""),
			  score: (($score * 100 | round) / 100),
			  why: $why,
			  resolver: { type: "somafm", id: $c.id } };

		# Tier 0: an exact id or title is never ambiguous.
		( [ chans[] | select((.id | ascii_downcase) == $q or (.title | ascii_downcase) == $q) ]
		  | map(card(.; 1.0; "exact match")) ) as $exact

		# Tier 1a: the whole query is a known mood word.
		| ( moods[$q] // null ) as $moodhit
		| ( if $moodhit == null then []
			else [ $moodhit.stations[] as $sid
				   | chans[] | select(.id == $sid)
				   | card(.; 0.97; "mood: " + $q) ]
			end ) as $moodcards

		# Tier 1b: any single token is a known mood word.
		| ( [ toks[] | select(moods[.] != null) ] ) as $moodtoks
		| ( [ $moodtoks[] as $t
			  | moods[$t].stations[] as $sid
			  | chans[] | select(.id == $sid)
			  # Weighted by how much of the query the mood vocabulary actually
			  # explains. A flat score meant one incidental word in a song
			  # title ("Reggae Night", "Around the World") cleared the 0.7
			  # threshold, so the request never reached YouTube and the user
			  # silently got an unrelated station.
			  # Curve chosen so a query that is mostly mood words stays
			  # confident while one stray mood word does not. Straight
			  # proportional scaling pushed "something calm and ambient for
			  # deep focus" below the threshold and out to YouTube, which
			  # would open a window for a background-music request.
			  #   coverage 1.00 -> 0.94   mostly-mood query, radio
			  #   coverage 0.60 -> 0.74   still radio
			  #   coverage 0.50 -> 0.69   falls through to YouTube
			  # Half coverage has to fall through: "Jimmy Cliff Reggae Night"
			  # and "Daft Punk Around the World" each contain two mood words
			  # and are still song titles.
			  | card(.; (0.44 + 0.5 * (($moodtoks | length) / (toks | length))); "mood: " + $t) ] ) as $tokmoodcards

		# Tier 1c: token overlap over title, genre, id and description.
		# Normalised so that matching a title or genre outright scores 1.0 per
		# token; description alone is a weak signal and stays well under the
		# confidence threshold on its own.
		# Whole-word matching, not substring. `contains` made every token a
		# wildcard against the middle of unrelated words.
		| ( [ chans[]
			  | . as $c
			  | ( [ textToks[] as $t
					| ("\\b" + $t + "\\b") as $re
					| ( if ($c.title | ascii_downcase | test($re)) then 3 else 0 end )
					+ ( if (($c.genre // "") | ascii_downcase | test($re)) then 3 else 0 end )
					+ ( if ($c.id | ascii_downcase | test($re)) then 2 else 0 end )
					+ ( if (($c.description // "") | ascii_downcase | test($re)) then 1 else 0 end )
				  ] | add // 0 ) as $raw
			  # Capped below the curated mood scores so that a hand-picked
			  # station outranks an incidental genre-string match.
			  # Divided by the real per-token maximum. The four field weights
			  # sum to 9, so dividing by 3 let a single matching token out of
			  # four reach the cap: "Nirvana Unplugged Live" scored SomaFM
			  # Live at 0.9 on the word "live" alone.
			  | ( if (textToks | length) == 0 then 0
				  else ([ $raw / ((textToks | length) * 9) * 2, 0.9 ] | min) end ) as $norm
			  | select($norm > 0)
			  | card($c; $norm; "text match") ] ) as $textcards

		# Highest score wins per station; earlier tiers naturally outrank later
		# ones because their scores are higher.
		| ( $exact + $moodcards + $tokmoodcards + $textcards
			| group_by(.id)
			| map(max_by(.score))
			| sort_by(-.score)
			| .[0:8] ) as $cands

		| ( $cands | if length > 0 then .[0].score else 0 end ) as $top

		# Tags are the escape hatch: a mood we know about but SomaFM does not
		# cover (amapiano, classical) yields no station and hands the caller
		# vocabulary for the networked tiers instead of a bad match.
		| ( [ ( moods[$q].tags // [] )[], ( $moodtoks[] | moods[.].tags[] ) ] | unique ) as $tags

		| { status: ( if $top >= $confident then "ok"
					  elif ($cands | length) > 0 or ($tags | length) > 0 then "ambiguous"
					  else "none" end ),
			confidence: $top,
			query: $raw,
			normalized: $q,
			hint_tags: $tags,
			candidates: $cands }
		'
}

# Turns a station id into a playable URL plus its mirrors. Called at play time
# only: resolving every candidate up front would cost a network round trip per
# result for candidates the user will never hear.
selecta_somafm_stream() {
	_ss_id=$1
	_cat_file=$(selecta_catalog)
	_ss_pls=$(jq -r --arg id "$_ss_id" '
		.channels[] | select(.id == $id) | .playlists
		| map(select(.format == "mp3"))
		| (map(select(.quality == "highest")) + .)
		| .[0].url // empty' "$_cat_file" 2>/dev/null)

	[ -n "$_ss_pls" ] || return "$EX_NOTFOUND"

	_ss_body=$(curl -sS --max-time 12 -A "$SELECTA_USER_AGENT" "$_ss_pls" 2>/dev/null) || return "$EX_NETWORK"
	printf '%s\n' "$_ss_body" |
		sed -n 's/^File[0-9][0-9]*=//p' |
		tr -d '\r' |
		awk 'NF'
}
