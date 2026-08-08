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

# Builds the three plain-text variants from a state document.
selecta_segment_lines() {
	_sg_state=$1

	_sg_status=$(printf '%s' "$_sg_state" | jq -r '.status // "stopped"')
	_sg_artist=$(printf '%s' "$_sg_state" | jq -r '.now.artist // ""')
	_sg_title=$(printf '%s' "$_sg_state" | jq -r '.now.title // ""')
	_sg_station=$(printf '%s' "$_sg_state" | jq -r '.source.title // ""')
	_sg_repo=$(printf '%s' "$_sg_state" | jq -r '.repo.display_name // ""')

	case $_sg_status in
	stopped | '') return 1 ;;
	esac

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
	*) _sg_glyph='♪' ;;
	esac

	_sg_n="$_sg_glyph $_sg_track"
	_sg_m=$_sg_n
	[ -n "$_sg_station" ] && [ "$_sg_track" != "$_sg_station" ] &&
		_sg_m="$_sg_n · $_sg_station"
	_sg_w=$_sg_m
	[ -n "$_sg_repo" ] && _sg_w="$_sg_m · $_sg_repo"

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
	_sw_plain=$(selecta_segment_lines "$_sw_state") || {
		: >"$SELECTA_SEGMENT" 2>/dev/null || true
		return 0
	}
	_sw_status=$(printf '%s' "$_sw_state" | jq -r '.status // "stopped"')

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

	_st_doc=$(jq -n \
		--arg schema 1 \
		--arg status "$_st_status" \
		--arg updated "$(selecta_now_iso)" \
		--argjson source "$_st_source" \
		--argjson now "$_st_now" \
		--argjson extra "$_st_extra" \
		'{schema: 1, status: $status, updated_at: $updated,
		  source: $source, now: $now} * $extra') || return 1

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
