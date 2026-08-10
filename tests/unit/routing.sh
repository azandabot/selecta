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
. "$SELECTA_TESTS/lib.sh"

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

# --- the phrasings that shipped broken ---------------------------------------
# "song", "track" and "album" used to force YouTube, and the check ran before
# the resolver was consulted at all. So "some chill songs for coding" opened a
# window while the catalogue was sitting on a confident match for it, and
# "play me a song" -- which is how people ask for background music -- did too.
#
# The first line here is verbatim from a real session. It opened a window,
# then spent a minute and eight commands failing to recover.
for _m in "some max aura song cause I am about to lock in" \
	"play me a song" \
	"some chill songs for coding" \
	"put a track on" \
	"aura farming music" \
	"music for staring at a wall" \
	"hard techno for the gym"; do
	t_eq "\"$_m\" is background music, not a title" "radio" "$(route "$_m")"
done

# A genre the offline catalogue knows scores as badly as an unknown title --
# both land around 0.1 -- so confidence cannot separate them and the
# vocabulary has to. One word is always a genre: nobody names a track in one.
for _m in "drum and bass" "log drum" phonk hyperpop; do
	t_eq "\"$_m\" is a genre, so no window" "radio" "$(route "$_m")"
done

# Naming an artist stays the one unambiguous signal.
for _t in "rottweiler by essdeekid" "tyla water" "bohemian rhapsody" \
	"kabza de small sponono"; do
	t_eq "\"$_t\" names a recording" "youtube" "$(route "$_t")"
done

# --- the important negative -------------------------------------------------
# A long ambient request must not trip the word-count heuristic into opening a
# window, because the whole point of radio is that it stays out of the way.
t_eq "a wordy ambient request stays on radio" "radio" \
	"$(route "play me something really calm and ambient for deep focus")"
t_eq "a wordy mood request stays on radio" "radio" \
	"$(route "some chill downtempo beats please")"

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
