#!/bin/sh
# Now-playing state and status line segment.
#
# The supervisor is the only writer. The status line reads run/segment, which is
# already rendered, already coloured and already truncated to three width
# buckets: the launcher runs every couple of seconds and must not parse JSON or
# fork anything to do its job.

SELECTA_W_NARROW=38
SELECTA_W_MID=70
SELECTA_W_WIDE=108

# Truncates on a visible-character basis. Colour is applied afterwards, so the
# escape sequences can never be counted toward the width or cut in half.
selecta_ellipsize() {
	_el_s=$1
	_el_max=$2
	if [ "${#_el_s}" -le "$_el_max" ]; then
		printf '%s' "$_el_s"
	else
		printf '%s…' "$(printf '%s' "$_el_s" | cut -c1-$((_el_max - 1)))"
	fi
}

# Builds the three plain-text variants from five plain strings. No jq: the
# whole point of the now-playing path is that it runs where jq does not.
selecta_segment_lines_plain() {
	_sg_status=${1:-stopped}
	_sg_artist=${2:-}
	_sg_title=${3:-}
	_sg_station=${4:-}
	_sg_repo=${5:-}
	_sg_render
}

# Same thing from a state document, for the paths that already hold one.
selecta_segment_lines() {
	_sg_state=$1

	_sg_status=$(printf '%s' "$_sg_state" | jq -r '.status // "stopped"')
	# Falls back to .last when stopped: the whole point of the line is to say
	# what is or was playing, and blanking it the moment a track ends is the
	# same as not having it.
	_sg_artist=$(printf '%s' "$_sg_state" | jq -r '.now.artist // .last.artist // ""')
	_sg_title=$(printf '%s' "$_sg_state" | jq -r '.now.title // .last.title // ""')
	_sg_station=$(printf '%s' "$_sg_state" | jq -r '.source.title // .last.source // ""')
	_sg_repo=$(printf '%s' "$_sg_state" | jq -r '.repo.display_name // .last.repo // ""')
	_sg_render
}

_sg_render() {
	# The segment file is tab-separated, so a tab inside a track title would
	# forge extra fields and make the launcher pick the wrong width variant.
	# Newlines would forge extra lines. Both get flattened to spaces here,
	# once per state change rather than on every status line refresh.
	_sg_artist=$(printf '%s' "$_sg_artist" | tr '\t\n' '  ')
	_sg_title=$(printf '%s' "$_sg_title" | tr '\t\n' '  ')
	_sg_station=$(printf '%s' "$_sg_station" | tr '\t\n' '  ')
	_sg_repo=$(printf '%s' "$_sg_repo" | tr '\t\n' '  ')

	if [ -n "$_sg_artist" ] && [ -n "$_sg_title" ]; then
		_sg_track="$_sg_artist — $_sg_title"
	elif [ -n "$_sg_title" ]; then
		_sg_track=$_sg_title
	else
		_sg_track=$_sg_station
	fi
	[ -n "$_sg_track" ] || _sg_track="…"

	case $_sg_status in
	paused) _sg_glyph='❚❚' ;;
	buffering) _sg_glyph='♪·' ;;
	error) _sg_glyph='♪!' ;;
	stopped | '') _sg_glyph='■' ;;
	*) _sg_glyph='♪' ;;
	esac

	# Nothing has ever played, so offer the command rather than an empty bar.
	if [ -z "$_sg_artist" ] && [ -z "$_sg_title" ] && [ -z "$_sg_station" ]; then
		_sg_idle='♪ /selecta play'
		printf '%s\t%s\t%s\n' "$_sg_idle" "$_sg_idle" "$_sg_idle"
		return 0
	fi

	# Remaining search budget, on the widest variant only. This is the number
	# people actually need and it has nowhere else persistent to live.
	# jq-gated: the quota lives in config.json, and the whole point of this
	# renderer is that it also runs where jq does not exist.
	_sg_left=''
	if selecta_have jq && selecta_yt_have_key 2>/dev/null; then
		_sg_left=" · $(selecta_yt_quota_left) left"
	fi

	_sg_n="$_sg_glyph $_sg_track"
	_sg_m=$_sg_n
	[ -n "$_sg_station" ] && [ "$_sg_track" != "$_sg_station" ] &&
		_sg_m="$_sg_n · $_sg_station"
	_sg_w=$_sg_m
	[ -n "$_sg_repo" ] && _sg_w="$_sg_m · $_sg_repo"
	_sg_w="$_sg_w$_sg_left"

	printf '%s\t%s\t%s\n' \
		"$(selecta_ellipsize "$_sg_n" "$SELECTA_W_NARROW")" \
		"$(selecta_ellipsize "$_sg_m" "$SELECTA_W_MID")" \
		"$(selecta_ellipsize "$_sg_w" "$SELECTA_W_WIDE")"
	return 0
}

# segment file layout, read by statusline/launcher.sh:
#   line 1  coloured   narrow \t mid \t wide
#   line 2  plain      narrow \t mid \t wide
#   line 3  status token
#   line 4  visible widths, narrow \t mid \t wide
#
# Line 4 exists so the launcher can right-align without measuring a string that
# contains ANSI escapes and multi-byte characters. Measuring is done here, once
# per state change, instead of on every status line refresh.
selecta_segment_write() {
	_sw_state=$1
	_sw_plain=$(selecta_segment_lines "$_sw_state") || return 0
	_sw_status=$(printf '%s' "$_sw_state" | jq -r '.status // "stopped"')
	selecta_segment_render "$_sw_plain" "$_sw_status"
}

# Writes the four-line segment file from pre-rendered plain variants. jq-free.
selecta_segment_render() {
	_sw_plain=$1
	_sw_status=$2

	_sw_dim=$(printf '\033[2m')
	_sw_off=$(printf '\033[0m')
	_sw_col=$(printf '%s' "$_sw_plain" | awk -v d="$_sw_dim" -v o="$_sw_off" \
		'BEGIN{FS=OFS="\t"} {for(i=1;i<=NF;i++) $i = d $i o; print}')

	# wc -m counts characters, not bytes, so a track title with accents or a
	# musical glyph does not overstate its width and push the line off-screen.
	_sw_w=''
	for _sw_i in 1 2 3; do
		_sw_part=$(printf '%s' "$_sw_plain" | cut -f"$_sw_i")
		_sw_n=$(printf '%s' "$_sw_part" | wc -m | tr -d ' ')
		_sw_w="$_sw_w${_sw_w:+	}$_sw_n"
	done

	printf '%s\n%s\n%s\n%s\n' "$_sw_col" "$_sw_plain" "$_sw_status" "$_sw_w" |
		selecta_atomic_write "$SELECTA_SEGMENT"

	# Alignment preference is materialised as a plain word so the launcher can
	# read it without parsing config.json.
	printf '%s\n' "$(selecta_cfg_get '.statusline.align' '"right"' | tr -d '"')" |
		selecta_atomic_write "$SELECTA_RUN/align" 2>/dev/null || true
}

# Composes the state document and writes both files together, so the status
# line can never show a track that state.json disagrees with.
selecta_state_write() {
	# selecta_state_write <status> <source-json> <now-json> <extra-json>
	_st_status=$1
	_st_source=${2:-null}
	_st_now=${3:-null}
	_st_extra=${4:-'{}'}

	_st_prev='{}'
	[ -s "$SELECTA_STATE" ] && jq -e . "$SELECTA_STATE" >/dev/null 2>&1 &&
		_st_prev=$(cat "$SELECTA_STATE")

	_st_doc=$(jq -n \
		--arg schema 1 \
		--arg status "$_st_status" \
		--arg updated "$(selecta_now_iso)" \
		--argjson source "$_st_source" \
		--argjson now "$_st_now" \
		--argjson extra "$_st_extra" \
		--argjson prev "$_st_prev" \
		'{schema: 1, status: $status, updated_at: $updated,
		  source: $source, now: $now}
		 * $extra
		 * { last: (
			 if ($now.title // "") != "" then
			   { artist: ($now.artist // ""), title: $now.title,
				 source: ($source.title // ""),
				 repo: ($extra.repo.display_name // "") }
			 else ($prev.last // null) end ) }') || return 1

	printf '%s\n' "$_st_doc" | selecta_atomic_write "$SELECTA_STATE" || return 1
	selecta_segment_write "$_st_doc"
}

selecta_state_read() {
	[ -s "$SELECTA_STATE" ] || {
		printf '%s' '{"status":"stopped"}'
		return 0
	}
	if ! jq -e . "$SELECTA_STATE" >/dev/null 2>&1; then
		selecta_quarantine "$SELECTA_STATE"
		printf '%s' '{"status":"stopped"}'
		return 0
	fi
	cat "$SELECTA_STATE"
}

# Polls until the backend actually reports playback. Both plugins wait on this
# before claiming a track started.
wait_until_playing() {
	_wp_max=${1:-40}
	_wp_i=0
	while [ "$_wp_i" -lt "$_wp_max" ]; do
		case $(selecta_state_read | jq -r '.status // ""') in
		playing) return 0 ;;
		error) return 1 ;;
		esac
		_wp_i=$((_wp_i + 1))
		sleep 0.25
	done
	return 1
}
