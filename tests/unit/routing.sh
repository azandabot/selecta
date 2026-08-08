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

# --- explicit overrides are honoured by the caller, not the heuristic -------
# wants_youtube is advisory; --yt and --radio bypass it in cmd_play. Assert the
# flags are actually parsed, since a silently ignored --radio would open a
# window the user explicitly declined.
t_eq "--radio is a recognised flag" "1" "$(grep -c -- '--radio) _cp_force=radio' "$SELECTA_ROOT/bin/selecta")"
t_eq "--yt is a recognised flag" "1" "$(grep -c -- '--yt | --youtube) _cp_force=yt' "$SELECTA_ROOT/bin/selecta")"

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

rm -rf "$SELECTA_HOME"
