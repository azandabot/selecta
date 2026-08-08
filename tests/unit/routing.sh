#!/bin/sh
# Backend routing. The rule that matters: asking for background music must
# never put a window on screen, because radio is windowless and YouTube is not.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-routing
export SELECTA_HOME
SELECTA_OFFLINE=1
export SELECTA_OFFLINE
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/cache"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/resolve.sh
. "$SELECTA_ROOT/lib/resolve.sh"
# shellcheck source=lib/route.sh
. "$SELECTA_ROOT/lib/route.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

route() {
	_r=$(selecta_resolve "$1")
	if wants_youtube "$1" "$_r"; then printf youtube; else printf radio; fi
}

# --- moods and genres stay on radio, windowless -----------------------------
for _m in ambient "deep work" focus chill drone metal jazz "80s" reggae \
	"something calm for reading" "music for coding" lofi amapiano; do
	t_eq "\"$_m\" stays on radio" "radio" "$(route "$_m")"
done

# --- named recordings go to youtube -----------------------------------------
for _t in "sponono by kabza de small" \
	"play the official video" \
	"that track from interstellar" \
	"asake lonely at the top song"; do
	t_eq "\"$_t\" routes to youtube" "youtube" "$(route "$_t")"
done

# --- the important negative -------------------------------------------------
# A long ambient request must not trip the word-count heuristic into opening a
# window, because the whole point of radio is that it stays out of the way.
t_eq "a wordy ambient request stays on radio" "radio" \
	"$(route "play me something really calm and ambient for deep focus")"
t_eq "a wordy mood request stays on radio" "radio" \
	"$(route "some chill downtempo beats please")"

# --- no key means no window -------------------------------------------------
# With no API key, a YouTube-shaped request must degrade to radio rather than
# opening an empty player.
# shellcheck source=lib/youtube.sh
. "$SELECTA_ROOT/lib/youtube.sh"
unset YOUTUBE_API_KEY
t_eq "no key is detected" "1" "$(
	selecta_yt_have_key
	echo $?
)"
t_eq "no key yields status nokey" "nokey" \
	"$(selecta_yt_resolve "sponono by kabza" | jq -r .status)"
t_eq "nokey returns no candidates" "0" \
	"$(selecta_yt_resolve "sponono by kabza" | jq -r '.candidates|length')"

# --- quota accounting -------------------------------------------------------
t_eq "a fresh day starts at zero searches" "0" "$(selecta_yt_quota_used)"
t_eq "a fresh day has the full budget" "100" "$(selecta_yt_quota_left)"

# --- regression: empty tags crashed the whole resolve -----------------------
# `jq -R 'split(",")'` emits nothing for empty input, and --argjson rejects an
# empty string, so one empty value took the command down with
# "invalid JSON text passed to --argjson". Tags are now split inside jq from a
# --arg string, which cannot produce an empty argument.
# shellcheck source=lib/resolve-net.sh
. "$SELECTA_ROOT/lib/resolve-net.sh"

for _pair in "::" "amapiano:" ":afro house" "x:,,," ":,"; do
	_q=${_pair%%:*}
	_t=${_pair#*:}
	_out=$(selecta_resolve_net "$_q" "$_t" 2>&1)
	t_eq "resolve_net survives q=[$_q] tags=[$_t]" "true" \
		"$(printf '%s' "$_out" | jq -e 'has("status")' >/dev/null 2>&1 && echo true || echo false)"
	t_eq "resolve_net q=[$_q] tags=[$_t] emits no jq error" "0" \
		"$(printf '%s' "$_out" | grep -c 'argjson' || true)"
done

# --- regression: the argjson guard ------------------------------------------
t_eq "json_or passes valid json through" '{"a":1}' "$(selecta_json_or '{"a":1}' '{}')"
t_eq "json_or replaces an empty value" '{}' "$(selecta_json_or '' '{}')"
t_eq "json_or replaces malformed json" '[]' "$(selecta_json_or 'not json' '[]')"
t_eq "json_or output is always valid json" "0" \
	"$(selecta_json_or '' '{}' | jq -e . >/dev/null 2>&1; echo $?)"


rm -rf "$SELECTA_HOME"
