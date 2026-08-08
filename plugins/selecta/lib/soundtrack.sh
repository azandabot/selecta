#!/bin/sh
# Per-repository soundtracks. The reason selecta exists.
#
# Two things accumulate, doing different jobs:
#   sources  stations and saved queries, weighted by listening time. This is
#            what `resume` and `next` walk.
#   tracks   what actually played, when, for how long, and on which branch and
#            commit. This is the memory, and it is what makes the feature more
#            than a log file.
#
# The supervisor writes these. bin/selecta reads them.

SELECTA_TRACK_CAP=500

# Resolves a key to its file, following aliases. A fork-to-upstream remote swap
# changes the primary key, so without the alias sweep the repo would silently
# start a fresh soundtrack and appear to have lost months of history.
selecta_st_file_for() {
	_sf_key=$1
	_sf_direct=$(selecta_repo_soundtrack_file "$_sf_key")
	[ -f "$_sf_direct" ] && {
		printf '%s' "$_sf_direct"
		return 0
	}
	# Aliases are resolved through the index, one jq over one file. This used
	# to loop every crate on disk with a jq each, from seven call sites, so a
	# machine with fifty repos forked fifty times per status line read.
	_sf_idx=$SELECTA_SOUNDTRACKS/index.json
	if [ -s "$_sf_idx" ]; then
		_sf_hit=$(jq -r --arg k "$_sf_key" '
			to_entries[] | select((.value.aliases // []) | index($k)) | .value.file' \
			"$_sf_idx" 2>/dev/null | head -1)
		[ -n "$_sf_hit" ] && [ -f "$SELECTA_SOUNDTRACKS/$_sf_hit" ] && {
			printf '%s' "$SELECTA_SOUNDTRACKS/$_sf_hit"
			return 0
		}
	fi
	printf '%s' "$_sf_direct"
}

selecta_st_load() {
	_sl_file=$(selecta_st_file_for "$1")
	if [ -s "$_sl_file" ]; then
		if jq -e . "$_sl_file" >/dev/null 2>&1; then
			cat "$_sl_file"
			return 0
		fi
		selecta_quarantine "$_sl_file"
	fi
	return 1
}

# Created lazily on first successful playback, never on lookup: an empty file
# for every directory the user has ever opened is noise, not history.
selecta_st_init() {
	jq -n --arg key "$1" --arg name "$2" --arg scope "$3" \
		--argjson aliases "$4" --arg now "$(selecta_now_iso)" \
		'{schema: 1, key: $key, aliases: $aliases, display_name: $name,
		  scope: $scope, created_at: $now, updated_at: $now,
		  totals: {seconds: 0, sessions: 0, tracks: 0},
		  sources: [], tracks: []}'
}

selecta_st_save() {
	_ss_key=$1
	_ss_doc=$2
	_ss_file=$(selecta_st_file_for "$_ss_key")
	printf '%s\n' "$_ss_doc" | selecta_atomic_write "$_ss_file" || return 1
	_ss_idx=$SELECTA_SOUNDTRACKS/index.json
	_ss_cur='{}'
	[ -s "$_ss_idx" ] && jq -e . "$_ss_idx" >/dev/null 2>&1 && _ss_cur=$(cat "$_ss_idx")
	printf '%s' "$_ss_cur" | jq \
		--arg k "$_ss_key" --arg f "$(basename -- "$_ss_file")" \
		--arg n "$(printf '%s' "$_ss_doc" | jq -r .display_name)" \
		--arg u "$(selecta_now_iso)" \
		--argjson s "$(selecta_json_or "$(printf '%s' "$_ss_doc" | jq '.totals.seconds')" 0)" \
		--argjson a "$(selecta_json_or "$(printf '%s' "$_ss_doc" | jq -c '.aliases // []')" '[]')" \
		'.[$k] = {file: $f, display_name: $n, updated_at: $u, seconds: $s, aliases: $a}' |
		selecta_atomic_write "$_ss_idx"
}

# Records that a source was played, creating the soundtrack if this is the
# repo's first ever track.
selecta_st_touch_source() {
	_ts_repo=$1
	_ts_src=$2
	_ts_key=$(printf '%s' "$_ts_repo" | jq -r '.key // ""')
	[ -n "$_ts_key" ] || return 1
	_ts_sid=$(printf '%s' "$_ts_src" | jq -r '.id // ""')
	[ -n "$_ts_sid" ] || return 1

	_ts_doc=$(selecta_st_load "$_ts_key") || _ts_doc=$(selecta_st_init \
		"$_ts_key" \
		"$(printf '%s' "$_ts_repo" | jq -r '.display_name // "unknown"')" \
		"$(printf '%s' "$_ts_repo" | jq -r '.scope // "dir"')" \
		"$(printf '%s' "$_ts_repo" | jq -c '.aliases // []')")

	_ts_new=$(printf '%s' "$_ts_doc" | jq \
		--argjson src "$_ts_src" --arg now "$(selecta_now_iso)" '
		.updated_at = $now
		| if (.sources | map(.id) | index($src.id)) == null then
			.sources += [ $src + {first_played_at: $now, last_played_at: $now,
								  seconds: 0, plays: 1, pinned: false, banned: false} ]
		  else
			.sources |= map(if .id == $src.id
							then . + {last_played_at: $now, plays: (.plays + 1)}
							else . end)
		  end') || return 1
	selecta_st_save "$_ts_key" "$_ts_new"
}

# Appends one track. The branch and commit stamp is what turns listening
# history into an index into your own work.
selecta_st_record_track() {
	_rt_src=$1
	_rt_now=$2
	_rt_repo=$(printf '%s' "$_rt_src" | jq -c '.repo // {}')
	_rt_key=$(printf '%s' "$_rt_repo" | jq -r '.key // ""')
	[ -n "$_rt_key" ] || return 0

	_rt_doc=$(selecta_st_load "$_rt_key") || return 0
	_rt_privacy=$(selecta_cfg_get '.privacy.record_commits' true)
	_rt_new=$(printf '%s' "$_rt_doc" | jq \
		--arg now "$(selecta_now_iso)" \
		--arg sid "$(printf '%s' "$_rt_src" | jq -r '.id // ""')" \
		--argjson track "$_rt_now" \
		--argjson repo "$_rt_repo" \
		--argjson commits "$_rt_privacy" \
		--argjson cap "$SELECTA_TRACK_CAP" '
		.updated_at = $now
		| .totals.tracks += 1
		| .tracks += [ {t: $now, src: $sid,
						artist: ($track.artist // ""), title: ($track.title // ""),
						secs: null,
						branch: (if $commits then ($repo.branch // "") else "" end),
						commit: (if $commits then ($repo.commit // "") else "" end)} ]
		| .tracks |= (if length > $cap then .[length-$cap:] else . end)') || return 0
	selecta_st_save "$_rt_key" "$_rt_new"
}

# Listening time per source. Accumulated by the supervisor when the source
# changes or playback stops, which is what makes the crate card meaningful:
# without it, ranking has only play counts to work with.
selecta_st_add_seconds() {
	_as_key=$1
	_as_sid=$2
	_as_secs=$3
	[ -n "$_as_key" ] && [ -n "$_as_sid" ] || return 0
	[ "$_as_secs" -gt 0 ] 2>/dev/null || return 0
	_as_doc=$(selecta_st_load "$_as_key") || return 0
	_as_new=$(printf '%s' "$_as_doc" | jq \
		--arg sid "$_as_sid" --argjson secs "$_as_secs" --arg now "$(selecta_now_iso)" '
		.updated_at = $now
		| .totals.seconds += $secs
		| .sources |= map(if .id == $sid then .seconds += $secs else . end)') || return 0
	selecta_st_save "$_as_key" "$_as_new"
}

# Two orderings, both of which a user would guess. Decay with a play-count
# fudge produced a score nobody could predict or test, and at three sources it
# was indistinguishable from either of these.
#
# resume and next walk by recency: the thing you had on last is what you want
# when you come back to a project.
selecta_st_rank() {
	printf '%s' "$1" | jq '
		[ .sources[] | select(.banned != true) | select((.failures // 0) < 3) ]
		| sort_by(.last_played_at) | reverse'
}

# The crate card ranks by listening time, because that is what its bars encode.
selecta_st_rank_by_time() {
	printf '%s' "$1" | jq '
		[ .sources[] | select(.banned != true) ]
		| sort_by(.seconds // 0) | reverse'
}

# Three consecutive failures retires a source. troubleshooting.md has promised
# this since the first release and nothing implemented it.
selecta_st_mark_failure() {
	_mf_doc=$(selecta_st_load "$1") || return 0
	selecta_st_save "$1" "$(printf '%s' "$_mf_doc" | jq --arg s "$2" \
		'.sources |= map(if .id == $s then .failures = ((.failures // 0) + 1) else . end)')"
}

selecta_st_clear_failure() {
	_cf_doc=$(selecta_st_load "$1") || return 0
	printf '%s' "$_cf_doc" | jq -e --arg s "$2" \
		'.sources[] | select(.id == $s and (.failures // 0) > 0)' >/dev/null 2>&1 || return 0
	selecta_st_save "$1" "$(printf '%s' "$_cf_doc" | jq --arg s "$2" \
		'.sources |= map(if .id == $s then .failures = 0 else . end)')"
}

