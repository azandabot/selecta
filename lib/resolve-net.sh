#!/bin/sh
# Networked resolver tiers.
#
# Tier 2  radio-browser   keyless, thousands of stations
# Tier 3  Jamendo         needs a free client id, Creative Commons tracks
# Tier 4  Archive.org     keyless, the netlabels collection
#
# Reached only when tiers 0-1 come back short, and every one of them is
# best-effort: an upstream being down drops to the next tier rather than
# failing the request.

SELECTA_RB_FALLBACK=de1.api.radio-browser.info
SELECTA_RESOLVE_TTL=3600

_rn_cache_key() { selecta_sha8 "$1"; }

_rn_cached() {
	_rc_f=$SELECTA_CACHE/resolve/$(_rn_cache_key "$1").json
	selecta_fresh "$_rc_f" "$SELECTA_RESOLVE_TTL" || return 1
	cat "$_rc_f"
}

_rn_cache_put() {
	mkdir -p "$SELECTA_CACHE/resolve" 2>/dev/null || return 0
	printf '%s\n' "$2" | selecta_atomic_write "$SELECTA_CACHE/resolve/$(_rn_cache_key "$1").json"
}

_rn_get() {
	curl -sS --max-time "${2:-12}" -A "$SELECTA_USER_AGENT" "$1" 2>/dev/null
}

# --- tier 2: radio-browser --------------------------------------------------
# Their server list currently resolves to a single host, so an outage is
# expected rather than exceptional. Treated as best-effort throughout.
selecta_rb_host() {
	_rb_c=$SELECTA_CACHE/rb-servers.json
	if ! selecta_fresh "$_rb_c" 86400; then
		_rb_j=$(_rn_get "https://all.api.radio-browser.info/json/servers" 8)
		if [ -n "$_rb_j" ] && printf '%s' "$_rb_j" | jq -e 'length > 0' >/dev/null 2>&1; then
			mkdir -p "$SELECTA_CACHE" 2>/dev/null || true
			printf '%s\n' "$_rb_j" | selecta_atomic_write "$_rb_c"
		fi
	fi
	if [ -s "$_rb_c" ]; then
		_rb_h=$(jq -r '[.[].name] | unique | .[0] // empty' "$_rb_c" 2>/dev/null)
		[ -n "$_rb_h" ] && {
			printf '%s' "$_rb_h"
			return 0
		}
	fi
	printf '%s' "$SELECTA_RB_FALLBACK"
}

# Only stations the directory last checked as working, at a bitrate worth
# listening to. https is ranked above http: plain http streams still play, but
# they trip network prompts and offer no integrity.
selecta_rb_search() {
	_rs_tag=$1
	_rs_host=$(selecta_rb_host)
	_rs_enc=$(printf '%s' "$_rs_tag" | jq -sRr @uri)

	_rs_j=$(_rn_get "https://$_rs_host/json/stations/search?tag=$_rs_enc&hidebroken=true&order=clickcount&reverse=true&limit=25")
	if [ -z "$_rs_j" ] || ! printf '%s' "$_rs_j" | jq -e 'length > 0' >/dev/null 2>&1; then
		_rs_j=$(_rn_get "https://$_rs_host/json/stations/search?name=$_rs_enc&hidebroken=true&order=clickcount&reverse=true&limit=25")
	fi
	[ -n "$_rs_j" ] || return 1
	printf '%s' "$_rs_j" | jq -c --arg tag "$_rs_tag" '
		[ .[]
		  | select(.lastcheckok == 1)
		  | select((.bitrate // 0) >= 64)
		  | select((.url_resolved // "") != "")
		  | select((.codec // "" | ascii_upcase) | test("MP3|AAC|OGG"))
		  | { id: ("rb:" + .stationuuid),
			  kind: "station", provider: "radio-browser",
			  title: (.name | gsub("^\\s+|\\s+$"; "")),
			  genre: (.tags // ""),
			  description: ((.country // "") + (if (.language // "") != "" then " · " + .language else "" end)),
			  score: (if (.url_resolved | startswith("https")) then 0.85 else 0.75 end),
			  why: ("radio-browser: " + $tag),
			  resolver: { type: "radio-browser", id: .stationuuid, url: .url_resolved } } ]
		| sort_by(-.score) | .[0:8]' 2>/dev/null
}

# Re-resolved by uuid at play time rather than trusting a stored URL, because
# stream endpoints rot and the directory tracks the current one.
selecta_rb_stream() {
	_rbs_uuid=$1
	_rbs_host=$(selecta_rb_host)
	_rbs_j=$(_rn_get "https://$_rbs_host/json/stations/byuuid/$_rbs_uuid")
	_rbs_url=$(printf '%s' "$_rbs_j" | jq -r '.[0].url_resolved // .[0].url // empty' 2>/dev/null)
	[ -n "$_rbs_url" ] || return "$EX_NOTFOUND"
	# Best-effort click registration keeps their popularity ranking honest.
	_rn_get "https://$_rbs_host/json/url/$_rbs_uuid" 4 >/dev/null 2>&1 &
	printf '%s\n' "$_rbs_url"
}

# --- tier 3: jamendo --------------------------------------------------------
# Jamendo answers HTTP 200 on an invalid key and reports the failure in the
# body. Branching on the status code would silently ship a broken tier.
selecta_jamendo_search() {
	_js_tags=$1
	_js_key=$(selecta_cfg_get '.jamendo.client_id' '""' | tr -d '"')
	[ -n "$_js_key" ] || _js_key=${JAMENDO_CLIENT_ID:-}
	[ -n "$_js_key" ] || return 1

	_js_enc=$(printf '%s' "$_js_tags" | jq -sRr @uri)
	_js_j=$(_rn_get "https://api.jamendo.com/v3.0/tracks/?client_id=$_js_key&format=json&limit=40&include=musicinfo&audioformat=mp32&fuzzytags=$_js_enc&order=popularity_total")
	[ -n "$_js_j" ] || return 1

	if [ "$(printf '%s' "$_js_j" | jq -r '.headers.status // "failed"')" != success ]; then
		selecta_log warn "jamendo: $(printf '%s' "$_js_j" | jq -r '.headers.error_message // "unknown error"')"
		return 1
	fi
	printf '%s' "$_js_j" | jq -c --arg tags "$_js_tags" '
		[ .results[]? | select((.audio // "") != "")
		  | { id: ("jamendo:" + .id), kind: "track", provider: "jamendo",
			  title: (.artist_name + " — " + .name),
			  genre: ((.musicinfo.tags.genres // []) | join(" ")),
			  description: (.album_name // ""),
			  score: 0.8, why: ("jamendo: " + $tags),
			  resolver: { type: "jamendo", id: .id, url: .audio, query: $tags } } ]
		| .[0:8]' 2>/dev/null
}

# --- tier 4: archive.org netlabels ------------------------------------------
# The deepest keyless track-level catalog available, and the reason zero-config
# text search over real Creative Commons music is possible at all. Two round
# trips, so it goes last.
selecta_archive_search() {
	_as_q=$1
	_as_enc=$(printf 'collection:(netlabels) AND mediatype:(audio) AND (%s)' "$_as_q" | jq -sRr @uri)
	_as_j=$(_rn_get "https://archive.org/advancedsearch.php?q=$_as_enc&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=licenseurl&rows=8&output=json" 15)
	[ -n "$_as_j" ] || return 1
	printf '%s' "$_as_j" | jq -c --arg q "$_as_q" '
		[ .response.docs[]?
		  | select((.licenseurl // "") | test("creativecommons"))
		  | { id: ("archive:" + .identifier), kind: "album", provider: "archive.org",
			  title: ((if (.creator|type) == "array" then .creator[0] else (.creator // "") end
					   | if . == "" then "" else . + " — " end) + (.title // .identifier)),
			  genre: "", description: "Creative Commons, Internet Archive netlabels",
			  score: 0.72, why: ("archive.org: " + $q),
			  resolver: { type: "archive", id: .identifier, license: .licenseurl } } ]
		| .[0:6]' 2>/dev/null
}

# --- combined ---------------------------------------------------------------

# selecta_resolve_net <original query> <comma-separated tags>
# Same contract as selecta_resolve, so callers branch on status either way.
selecta_resolve_net() {
	_rn_q=$1
	_rn_tags=${2:-$1}

	_rn_ck="net:$_rn_q:$_rn_tags"
	if _rn_hit=$(_rn_cached "$_rn_ck"); then
		printf '%s' "$_rn_hit"
		return 0
	fi

	_rn_all='[]'
	_rn_first=$(printf '%s' "$_rn_tags" | cut -d, -f1)

	# Every tag is tried, not just the first. "amapiano" resolves through the
	# amapiano tag even when "afro house" happens to sort ahead of it and
	# returns nothing.
	_rn_rest=$_rn_tags
	while [ -n "$_rn_rest" ]; do
		_rn_tag=${_rn_rest%%,*}
		case $_rn_rest in
		*,*) _rn_rest=${_rn_rest#*,} ;;
		*) _rn_rest='' ;;
		esac
		[ -n "$_rn_tag" ] || continue
		if _rn_rb=$(selecta_rb_search "$_rn_tag"); then
			if [ -n "$_rn_rb" ] && [ "$(printf '%s' "$_rn_rb" | jq 'length')" -gt 0 ]; then
				_rn_all=$(printf '%s\n%s' "$_rn_all" "$_rn_rb" | jq -s 'add')
				break
			fi
		fi
	done
	if [ "$(printf '%s' "$_rn_all" | jq 'length')" -eq 0 ]; then
		if _rn_jm=$(selecta_jamendo_search "$_rn_tags"); then
			[ -n "$_rn_jm" ] && _rn_all=$(printf '%s\n%s' "$_rn_all" "$_rn_jm" | jq -s 'add')
		fi
	fi
	if [ "$(printf '%s' "$_rn_all" | jq 'length')" -eq 0 ]; then
		if _rn_ar=$(selecta_archive_search "$_rn_first"); then
			[ -n "$_rn_ar" ] && _rn_all=$(printf '%s\n%s' "$_rn_all" "$_rn_ar" | jq -s 'add')
		fi
	fi

	_rn_out=$(printf '%s' "$_rn_all" | jq -c \
		--arg q "$_rn_q" \
		--argjson tags "$(printf '%s' "$_rn_tags" | jq -R 'split(",")')" '
		sort_by(-.score) as $c
		| { status: (if ($c|length) > 0 then "ok" else "none" end),
			confidence: (if ($c|length) > 0 then $c[0].score else 0 end),
			query: $q, normalized: $q, hint_tags: $tags, candidates: $c }')

	[ -n "$_rn_out" ] || _rn_out=$(jq -nc --arg q "$_rn_q" \
		'{status:"none",confidence:0,query:$q,normalized:$q,hint_tags:[],candidates:[]}')
	_rn_cache_put "$_rn_ck" "$_rn_out"
	printf '%s' "$_rn_out"
}
