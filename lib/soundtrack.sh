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
SELECTA_HALFLIFE_DAYS=30

selecta_st_index() { printf '%s/index.json' "$SELECTA_SOUNDTRACKS"; }

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
	if [ -d "$SELECTA_SOUNDTRACKS" ]; then
		for _sf_f in "$SELECTA_SOUNDTRACKS"/*.json; do
			[ -f "$_sf_f" ] || continue
			case $_sf_f in */index.json) continue ;; esac
			if jq -e --arg k "$_sf_key" '(.aliases // []) | index($k)' "$_sf_f" >/dev/null 2>&1; then
				printf '%s' "$_sf_f"
				return 0
			fi
		done
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

selecta_st_exists() { selecta_st_load "$1" >/dev/null 2>&1; }

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
	_ss_idx=$(selecta_st_index)
	_ss_cur='{}'
	[ -s "$_ss_idx" ] && jq -e . "$_ss_idx" >/dev/null 2>&1 && _ss_cur=$(cat "$_ss_idx")
	printf '%s' "$_ss_cur" | jq \
		--arg k "$_ss_key" --arg f "$(basename -- "$_ss_file")" \
		--arg n "$(printf '%s' "$_ss_doc" | jq -r .display_name)" \
		--arg u "$(selecta_now_iso)" \
		--argjson s "$(selecta_json_or "$(printf '%s' "$_ss_doc" | jq '.totals.seconds')" 0)" \
		'.[$k] = {file: $f, display_name: $n, updated_at: $u, seconds: $s}' |
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

# Ranked sources. Half-life decay means a station hammered six months ago does
# not outrank yesterday's, but does not vanish either.
selecta_st_rank() {
	_rk_doc=$1
	printf '%s' "$_rk_doc" | jq --argjson hl "$SELECTA_HALFLIFE_DAYS" --arg now "$(selecta_now_iso)" '
		def age_days($t): (($now | fromdateiso8601) - ($t | fromdateiso8601)) / 86400;
		[ .sources[]
		  | select(.banned != true)
		  | . as $s
		  # A source with no banked listening time yet is weighted by play
		  # count, so a station started moments ago still ranks.
		  | ( if ($s.seconds // 0) == 0 then (($s.plays // 1) * 60) else $s.seconds end ) as $weight
		  | $s + {score: ( $weight * pow(0.5; (age_days($s.last_played_at) / $hl)) )} ]
		| sort_by( (if .pinned then 0 else 1 end), -.score )'
}

