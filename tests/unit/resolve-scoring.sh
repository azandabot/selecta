#!/bin/sh
# Resolver tiers 0-1. Runs fully offline against the frozen seed catalog so the
# results are deterministic and no upstream is contacted.
set -u

# Must be set before common.sh is sourced: it captures SELECTA_HOME at source
# time, and a test that wrote to the real one would corrupt live state.
SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-resolve
export SELECTA_HOME
SELECTA_OFFLINE=1
export SELECTA_OFFLINE
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/cache"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/resolve.sh
. "$SELECTA_ROOT/lib/resolve.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

r() { selecta_resolve "$1"; }
field() { printf '%s' "$1" | jq -r "$2"; }

# --- catalog fallback -------------------------------------------------------
t_eq "offline catalog falls back to the baked seed" \
	"$SELECTA_ROOT/data/somafm-channels.seed.json" "$(selecta_catalog)"

# --- query normalization ----------------------------------------------------
t_eq "strips filler words" "chill" "$(selecta_normalize_query 'play me some chill music please')"
t_eq "strips punctuation" "deep house" "$(selecta_normalize_query 'deep house!!!')"
t_eq "lowercases" "ambient" "$(selecta_normalize_query 'AMBIENT')"
t_eq "collapses whitespace" "drone zone" "$(selecta_normalize_query '  drone    zone  ')"
t_eq "keeps a multiword phrase intact" "log drum" "$(selecta_normalize_query 'something with a log drum')"
# An all-filler query must not normalize to nothing, or every such request
# would resolve to "no candidates" instead of being handled.
t_ne "all-filler query does not become empty" "" "$(selecta_normalize_query 'play me some music')"

# --- tier 0: exact ----------------------------------------------------------
_x=$(r groovesalad)
t_eq "exact id status" "ok" "$(field "$_x" .status)"
t_eq "exact id confidence" "1" "$(field "$_x" .confidence)"
t_eq "exact id top hit" "somafm:groovesalad" "$(field "$_x" '.candidates[0].id')"

_x=$(r "Drone Zone")
t_eq "exact title status" "ok" "$(field "$_x" .status)"
t_eq "exact title top hit" "somafm:dronezone" "$(field "$_x" '.candidates[0].id')"

_x=$(r "DRONE ZONE")
t_eq "exact title is case insensitive" "somafm:dronezone" "$(field "$_x" '.candidates[0].id')"

# --- tier 1: mood vocabulary ------------------------------------------------
_x=$(r ambient)
t_eq "mood word resolves confidently" "ok" "$(field "$_x" .status)"
t_eq "curated pick outranks incidental text match" "mood: ambient" "$(field "$_x" '.candidates[0].why')"

_x=$(r "deep work")
t_eq "multiword mood status" "ok" "$(field "$_x" .status)"
t_eq "multiword mood is curated" "mood: deep work" "$(field "$_x" '.candidates[0].why')"

_x=$(r "play me something for coding")
t_eq "mood survives filler" "ok" "$(field "$_x" .status)"

_x=$(r "80s")
t_eq "numeric mood word" "somafm:u80s" "$(field "$_x" '.candidates[0].id')"

# --- tier 1: text scoring ---------------------------------------------------
_x=$(r metal)
t_eq "genre text match resolves" "ok" "$(field "$_x" .status)"
t_eq "metal finds Metal Detector" "somafm:metal" "$(field "$_x" '.candidates[0].id')"

# --- the ambiguous path, which is the whole point of hint_tags --------------
_x=$(r "log drum")
t_eq "log drum is ambiguous, not a bad guess" "ambiguous" "$(field "$_x" .status)"
t_eq "log drum yields amapiano tags" "afro house,amapiano" "$(field "$_x" '.hint_tags|join(",")')"

_x=$(r amapiano)
t_eq "amapiano is ambiguous" "ambiguous" "$(field "$_x" .status)"
t_eq "amapiano has no somafm station" "0" "$(field "$_x" '.candidates|length')"
t_ne "amapiano still hands over tags" "" "$(field "$_x" '.hint_tags|join(",")')"

_x=$(r classical)
t_eq "classical is ambiguous" "ambiguous" "$(field "$_x" .status)"
t_eq "classical yields a tag for tier 2" "classical" "$(field "$_x" '.hint_tags|join(",")')"

# --- nothing at all ---------------------------------------------------------
_x=$(r "zzzqqq")
t_eq "nonsense status" "none" "$(field "$_x" .status)"
t_eq "nonsense confidence" "0" "$(field "$_x" .confidence)"
t_eq "nonsense returns no candidates" "0" "$(field "$_x" '.candidates|length')"

# --- contract shape ---------------------------------------------------------
_x=$(r ambient)
t_eq "candidates are capped" "true" "$(field "$_x" '(.candidates|length) <= 8')"
t_eq "no duplicate stations" "true" \
	"$(field "$_x" '(.candidates|map(.id)|unique|length) == (.candidates|length)')"
t_eq "sorted by descending score" "true" \
	"$(field "$_x" '(.candidates|map(.score)) == (.candidates|map(.score)|sort|reverse)')"
t_eq "every candidate carries a replayable resolver" "true" \
	"$(field "$_x" '.candidates|all(.resolver.type == "somafm" and (.resolver.id|length > 0))')"
t_eq "every candidate id is namespaced" "true" \
	"$(field "$_x" '.candidates|all(.id|startswith("somafm:"))')"

# --- seed catalog integrity -------------------------------------------------
_seed=$SELECTA_ROOT/data/somafm-channels.seed.json
t_eq "seed has channels" "true" "$(jq -r '(.channels|length) > 40' "$_seed")"
t_eq "every seed channel has an mp3 stream" "true" \
	"$(jq -r '.channels|all((.playlists|length) > 0)' "$_seed")"
t_eq "every mood references a real station" "true" \
	"$(jq -sr '.[0].moods as $m | .[1].channels|map(.id) as $ids
		| [$m|to_entries[]|.value.stations[]]|unique|all(. as $s | $ids|index($s) != null)' \
		"$SELECTA_ROOT/data/mood-map.json" "$_seed")"

# --- regression: substring matching scored nonsense highly -------------------
# "Kwiish SA Technics" scored the station Bossa Beyond at 0.9, because the
# two-letter token "sa" matched Bossa, bossanova, the id bossa and Samba in the
# description, hitting all four fields at once. Text scoring is now whole-word
# and ignores tokens under three characters.
for _q in "Kwiish SA Technics" "Burna Boy Last Last" "Tyla Water" \
	"Davido Unavailable" "Rottweiler Essdeekid"; do
	_r=$(r "$_q")
	t_eq "artist query \"$_q\" does not score confidently" "false" \
		"$(field "$_r" '.confidence >= 0.7')"
done

_x=$(r "Kwiish SA Technics")
t_eq "the exact reported case no longer matches Bossa Beyond" "none" "$(field "$_x" .status)"

# Short tokens must not match inside longer words.
_x=$(r "sa")
t_eq "a bare two-letter token matches nothing by text" "0" \
	"$(field "$_x" '[.candidates[] | select(.why == "text match")] | length')"

# And the mood vocabulary must be untouched by the change.
for _m in ambient metal jazz reggae "80s" drone lofi "secret agent" "groove salad" "deep work"; do
	t_eq "mood \"$_m\" still resolves confidently" "ok" "$(field "$(r "$_m")" .status)"
done

rm -rf "$SELECTA_HOME"
