#!/bin/sh
# YouTube search, via the Data API v3 with the user's own key.
#
# Three layers keep an unplayable video from reaching the player, because a
# large share of major-label music disallows embedded playback:
#   1. search.list with videoEmbeddable=true filters at the source
#   2. videos.list confirms status.embeddable in one batched call
#   3. the page reports error 100/101/150 and the shell skips to the next hit
#
# Quota: search.list costs 1 unit from a separate 100/day Search Queries
# bucket. videos.list costs 1 unit from the general 10,000/day bucket, so
# validating a whole result set is effectively free and search is the scarce
# resource. Tracked in cache/yt-quota.json and surfaced by `selecta doctor`.

SELECTA_YT_CACHE_TTL=604800 # 7 days, well inside the 30-day storage policy
SELECTA_YT_DAILY_SEARCHES=100

selecta_yt_key() {
	_yk=$(selecta_cfg_get '.youtube.api_key' '""' | tr -d '"')
	[ -n "$_yk" ] || _yk=${YOUTUBE_API_KEY:-}
	[ -n "$_yk" ] || return 1
	printf '%s' "$_yk"
}

selecta_yt_have_key() { selecta_yt_key >/dev/null 2>&1; }

# --- quota ------------------------------------------------------------------

_yt_quota_file() { printf '%s/yt-quota.json' "$SELECTA_CACHE"; }

# Quota resets at midnight Pacific. Tracking the date the API would use avoids
# telling someone they are out when the bucket has already refilled.
_yt_today() { TZ=America/Los_Angeles date +%Y-%m-%d; }

selecta_yt_quota_used() {
	_qf=$(_yt_quota_file)
	[ -s "$_qf" ] || {
		printf '0'
		return 0
	}
	_qd=$(jq -r '.date // ""' "$_qf" 2>/dev/null)
	if [ "$_qd" != "$(_yt_today)" ]; then
		printf '0'
		return 0
	fi
	jq -r '.searches // 0' "$_qf" 2>/dev/null
}

selecta_yt_quota_left() {
	printf '%s' "$((SELECTA_YT_DAILY_SEARCHES - $(selecta_yt_quota_used)))"
}

_yt_quota_bump() {
	mkdir -p "$SELECTA_CACHE" 2>/dev/null || return 0
	jq -n --arg d "$(_yt_today)" --argjson n "$(($(selecta_yt_quota_used) + 1))" \
		'{date: $d, searches: $n}' | selecta_atomic_write "$(_yt_quota_file)"
}

# --- search -----------------------------------------------------------------

_yt_cache_file() { printf '%s/yt/%s.json' "$SELECTA_CACHE" "$(selecta_sha8 "$1")"; }

selecta_yt_search() {
	_ys_q=$1
	_ys_key=$(selecta_yt_key) || return 1

	_ys_cf=$(_yt_cache_file "$_ys_q")
	if selecta_fresh "$_ys_cf" "$SELECTA_YT_CACHE_TTL"; then
		cat "$_ys_cf"
		return 0
	fi

	if [ "$(selecta_yt_quota_left)" -le 0 ]; then
		selecta_log warn "youtube: daily search quota exhausted"
		return 2
	fi

	_ys_enc=$(printf '%s' "$_ys_q" | jq -sRr @uri)
	_ys_raw=$(curl -sS --max-time 15 -A "$SELECTA_USER_AGENT" \
		"https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoEmbeddable=true&videoCategoryId=10&maxResults=12&order=relevance&q=$_ys_enc&key=$_ys_key" 2>/dev/null)
	_yt_quota_bump

	[ -n "$_ys_raw" ] || return 1
	if printf '%s' "$_ys_raw" | jq -e '.error' >/dev/null 2>&1; then
		selecta_log warn "youtube: $(printf '%s' "$_ys_raw" | jq -r '.error.message // "api error"')"
		# The reason code is the difference between "your key is fine, the API
		# is switched off" and "nothing matched", and telling a user the wrong
		# one costs them an afternoon.
		case $(printf '%s' "$_ys_raw" | jq -r '.error.errors[0].reason // ""') in
		accessNotConfigured) return 3 ;;
		quotaExceeded | rateLimitExceeded | dailyLimitExceeded) return 2 ;;
		keyInvalid | badRequest | forbidden) return 4 ;;
		esac
		return 1
	fi

	_ys_ids=$(printf '%s' "$_ys_raw" | jq -r '[.items[]?.id.videoId] | map(select(. != null)) | join(",")')
	[ -n "$_ys_ids" ] || return 1

	# Second pass confirms embeddability and that the video is public. One unit
	# from the general bucket for the whole set.
	_ys_det=$(curl -sS --max-time 15 -A "$SELECTA_USER_AGENT" \
		"https://www.googleapis.com/youtube/v3/videos?part=status,snippet,contentDetails&id=$_ys_ids&key=$_ys_key" 2>/dev/null)

	# Ranked by how likely the upload is to actually play, not just by
	# relevance. status.embeddable can be true while the rights holder still
	# blocks playback with error 150, and that is near-universal for label
	# channels. Lyric and audio re-uploads of the same song almost always work,
	# so they are tried first rather than only after the official one fails.
	_ys_out=$(printf '%s' "$_ys_det" | jq -c --arg q "$_ys_q" '
		[ .items[]?
		  | select(.status.embeddable == true)
		  | select(.status.privacyStatus == "public")
		  | (.snippet.channelTitle // "") as $chan
		  | (.snippet.title // "") as $t
		  # Reactions, reviews and mashups are not the song. They rank below
		  # everything else rather than being excluded, so they remain a last
		  # resort when literally nothing else will play.
		  | (if ($t | test("reaction|review|mashup|explained|breakdown|interview"; "i")) then 0.2
			 elif ($chan | test("VEVO$"; "i")) then 0.55
			 elif ($t | test("lyric|official audio|visuali[sz]er"; "i")) then 0.95
			 elif ($chan | test("- Topic$")) then 0.9
			 else 0.8 end) as $sc
		  | { id: ("youtube:" + .id),
			  kind: "track", provider: "youtube",
			  videoId: .id,
			  title: $t,
			  artist: $chan,
			  genre: "",
			  description: $chan,
			  duration: (.contentDetails.duration // ""),
			  score: $sc,
			  why: ("youtube: " + $q),
			  resolver: {type: "youtube", id: .id, query: $q} } ]
		| sort_by(-.score) | .[0:10]' 2>/dev/null)

	[ -n "$_ys_out" ] && [ "$(printf '%s' "$_ys_out" | jq 'length')" -gt 0 ] || return 1

	mkdir -p "$SELECTA_CACHE/yt" 2>/dev/null || true
	printf '%s\n' "$_ys_out" | selecta_atomic_write "$_ys_cf"
	printf '%s' "$_ys_out"
}

# Same contract as selecta_resolve, so callers branch on status identically.
selecta_yt_resolve() {
	_yr_q=$1
	if ! selecta_yt_have_key; then
		jq -nc --arg q "$_yr_q" \
			'{status:"nokey",confidence:0,query:$q,normalized:$q,hint_tags:[],candidates:[]}'
		return 0
	fi
	# The `|| _yr_rc=$?` is load-bearing. bin/selecta runs under `set -e`, where
	# an assignment whose command substitution exits non-zero terminates the
	# script on the spot: the next line never ran, and a search that simply
	# found nothing killed the whole command with no output at all.
	_yr_rc=0
	_yr_c=$(selecta_yt_search "$_yr_q") || _yr_rc=$?
	case $_yr_rc in
	2) _yr_st=quota ;;
	3) _yr_st=notenabled ;;
	4) _yr_st=badkey ;;
	*) _yr_st='' ;;
	esac
	if [ -n "$_yr_st" ]; then
		jq -nc --arg q "$_yr_q" --arg s "$_yr_st" \
			'{status:$s,confidence:0,query:$q,normalized:$q,hint_tags:[],candidates:[]}'
		return 0
	fi
	if [ "$_yr_rc" -ne 0 ] || [ -z "$_yr_c" ]; then
		jq -nc --arg q "$_yr_q" \
			'{status:"none",confidence:0,query:$q,normalized:$q,hint_tags:[],candidates:[]}'
		return 0
	fi
	printf '%s' "$_yr_c" | jq -c --arg q "$_yr_q" \
		'{status:"ok", confidence:(.[0].score // 0), query:$q, normalized:$q,
		  hint_tags:[], candidates:.}'
}

# Phrasings that surface re-uploads rather than the label's own copy. Tried in
# order when a whole result set comes back embed-locked, which is what happens
# for most major-label releases.
SELECTA_YT_FALLBACKS="lyrics|audio|lyric video"

# selecta_yt_alt_search <query> <attempt-number>
# Returns a fresh candidate array, or non-zero when the phrasings run out.
selecta_yt_alt_search() {
	_ya_q=$1
	_ya_n=${2:-1}
	_ya_mod=$(printf '%s' "$SELECTA_YT_FALLBACKS" | cut -d'|' -f"$_ya_n")
	[ -n "$_ya_mod" ] || return 1
	selecta_yt_search "$_ya_q $_ya_mod"
}

# One cheap, cached-free call that answers "is this key actually usable". Used
# only by doctor, where a wrong answer is the whole problem: reporting "key
# set" for a key that 403s on every request is what sent people looking in the
# wrong place. videos.list, not search.list, so it costs nothing from the
# 100/day search bucket.
selecta_yt_probe() {
	_yp_key=$(selecta_yt_key) || {
		printf 'nokey'
		return 0
	}
	_yp_raw=$(curl -sS --max-time 10 -A "$SELECTA_USER_AGENT" \
		"https://www.googleapis.com/youtube/v3/videos?part=status&id=dQw4w9WgXcQ&key=$_yp_key" 2>/dev/null)
	[ -n "$_yp_raw" ] || {
		printf 'unreachable'
		return 0
	}
	if printf '%s' "$_yp_raw" | jq -e '.error' >/dev/null 2>&1; then
		case $(printf '%s' "$_yp_raw" | jq -r '.error.errors[0].reason // ""') in
		accessNotConfigured) printf 'notenabled' ;;
		quotaExceeded | rateLimitExceeded | dailyLimitExceeded) printf 'quota' ;;
		keyInvalid | badRequest | forbidden) printf 'badkey' ;;
		*) printf 'unreachable' ;;
		esac
		return 0
	fi
	printf 'ok'
}
