#!/bin/sh
# The per-repo crate: the module its own header calls "the reason selecta
# exists", and which had zero test coverage until now.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-crate
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/soundtracks" "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/repo.sh
. "$SELECTA_ROOT/lib/repo.sh"
# shellcheck source=lib/soundtrack.sh
. "$SELECTA_ROOT/lib/soundtrack.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

KEY="remote:github.com/x/y"
REPO='{"key":"remote:github.com/x/y","display_name":"y","scope":"remote","branch":"main","commit":"abc1234","aliases":[]}'
SRC='{"id":"somafm:groovesalad","kind":"station","provider":"somafm","title":"Groove Salad","resolver":{"type":"somafm","id":"groovesalad"}}'
doc() { selecta_st_load "$KEY"; }
q() { doc | jq -r "$1"; }

# --- laziness: no file until something actually plays ------------------------
t_eq "no crate exists before anything plays" "0" \
	"$(find "$SELECTA_SOUNDTRACKS" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
t_eq "loading a missing crate fails cleanly" "1" "$(
	selecta_st_load "$KEY" >/dev/null 2>&1
	echo $?
)"

selecta_st_touch_source "$REPO" "$SRC"
t_eq "one crate file after the first play" "1" \
	"$(find "$SELECTA_SOUNDTRACKS" -name '*.json' ! -name index.json | wc -l | tr -d ' ')"
t_eq "schema is stamped" "1" "$(q .schema)"
t_eq "display name is carried" "y" "$(q .display_name)"
t_eq "first play counts once" "1" "$(q '.sources[0].plays')"

_first=$(q '.sources[0].first_played_at')
selecta_st_touch_source "$REPO" "$SRC"
t_eq "second play increments" "2" "$(q '.sources[0].plays')"
t_eq "second play does not duplicate the source" "1" "$(q '.sources|length')"
t_eq "first_played_at is not rewritten" "$_first" "$(q '.sources[0].first_played_at')"

# --- tracks ------------------------------------------------------------------
SRCR=$(printf '%s' "$SRC" | jq -c --argjson r "$REPO" '. + {repo: $r}')
selecta_st_record_track "$SRCR" '{"artist":"Bonobo","title":"Kong"}'
t_eq "a track is recorded" "1" "$(q '.tracks|length')"
t_eq "totals.tracks increments" "1" "$(q .totals.tracks)"
t_eq "the commit is stamped" "abc1234" "$(q '.tracks[0].commit')"
t_eq "the branch is stamped" "main" "$(q '.tracks[0].branch')"

# Privacy: on a client machine, nobody wants their commits in a music log.
selecta_cfg_set '.privacy.record_commits' false
selecta_st_record_track "$SRCR" '{"artist":"Tycho","title":"Awake"}'
t_eq "privacy off leaves the commit empty" "" "$(q '.tracks[1].commit')"
t_eq "privacy off leaves the branch empty" "" "$(q '.tracks[1].branch')"
t_eq "the track itself is still recorded" "Awake" "$(q '.tracks[1].title')"
selecta_cfg_set '.privacy.record_commits' true

# --- the ring buffer ----------------------------------------------------------
_i=0
while [ "$_i" -lt 505 ]; do
	_i=$((_i + 1))
	selecta_st_record_track "$SRCR" "$(jq -nc --arg t "t$_i" '{artist:"A",title:$t}')"
done
t_eq "the ring buffer caps at 500" "500" "$(q '.tracks|length')"
t_eq "the newest track survives" "t505" "$(q '.tracks[-1].title')"
t_eq "the oldest tracks were dropped" "0" "$(q '[.tracks[]|select(.title=="Kong")]|length')"

# --- listening time -----------------------------------------------------------
selecta_st_add_seconds "$KEY" "somafm:groovesalad" 120
t_eq "seconds are credited to the source" "120" "$(q '.sources[0].seconds')"
t_eq "seconds are credited to the total" "120" "$(q .totals.seconds)"
selecta_st_add_seconds "$KEY" "somafm:groovesalad" 0
t_eq "zero seconds is a no-op" "120" "$(q .totals.seconds)"
selecta_st_add_seconds "$KEY" "somafm:nosuch" 60
t_eq "an unknown source does not invent an entry" "1" "$(q '.sources|length')"

# --- ordering -----------------------------------------------------------------
SRC2='{"id":"somafm:dronezone","kind":"station","provider":"somafm","title":"Drone Zone","resolver":{"type":"somafm","id":"dronezone"}}'
selecta_st_touch_source "$REPO" "$SRC2"
selecta_st_add_seconds "$KEY" "somafm:dronezone" 9999

t_eq "resume takes the most recently played" "somafm:dronezone" \
	"$(selecta_st_rank "$(doc)" | jq -r '.[0].id')"
t_eq "the crate card ranks by listening time" "somafm:dronezone" \
	"$(selecta_st_rank_by_time "$(doc)" | jq -r '.[0].id')"

# --- failure demotion, which troubleshooting.md promised for two releases -----
selecta_st_mark_failure "$KEY" "somafm:dronezone"
selecta_st_mark_failure "$KEY" "somafm:dronezone"
t_eq "two failures do not retire a source" "somafm:dronezone" \
	"$(selecta_st_rank "$(doc)" | jq -r '.[0].id')"
selecta_st_mark_failure "$KEY" "somafm:dronezone"
t_eq "three failures retire it from the rotation" "somafm:groovesalad" \
	"$(selecta_st_rank "$(doc)" | jq -r '.[0].id')"
t_eq "a retired source still shows in the crate card" "2" \
	"$(selecta_st_rank_by_time "$(doc)" | jq -r 'length')"
selecta_st_clear_failure "$KEY" "somafm:dronezone"
t_eq "a success clears the count" "somafm:dronezone" \
	"$(selecta_st_rank "$(doc)" | jq -r '.[0].id')"

# --- awkward text round-trips -------------------------------------------------
selecta_st_record_track "$SRCR" '{"artist":"Sigur Rós","title":"Hoppípolla \"live\" — 𝄞"}'
t_eq "quotes, accents and 4-byte glyphs survive" 'Hoppípolla "live" — 𝄞' "$(q '.tracks[-1].title')"

# --- corruption is preserved, never silently discarded ------------------------
printf 'not json at all\n' >"$(selecta_st_file_for "$KEY")"
t_eq "a corrupt crate fails to load" "1" "$(
	selecta_st_load "$KEY" >/dev/null 2>&1
	echo $?
)"
t_eq "a corrupt crate is quarantined, not deleted" "1" \
	"$(find "$SELECTA_SOUNDTRACKS" -name '*.corrupt.*' | wc -l | tr -d ' ')"

# --- alias resolution, and the performance floor behind it --------------------
rm -rf "$SELECTA_SOUNDTRACKS"
mkdir -p "$SELECTA_SOUNDTRACKS"
FORK='{"key":"remote:github.com/me/proj","display_name":"proj","scope":"remote","aliases":["remote:github.com/upstream/proj"],"branch":"main","commit":"d00d"}'
selecta_st_touch_source "$FORK" "$SRC"
t_eq "a fork resolves through its alias to the same crate" "proj" \
	"$(selecta_st_load 'remote:github.com/upstream/proj' | jq -r .display_name)"

# The alias sweep used to fork one jq per crate file on disk, from seven call
# sites, so fifty repos meant fifty forks per status line read.
_i=0
while [ "$_i" -lt 60 ]; do
	_i=$((_i + 1))
	printf '{"schema":1,"key":"k%s","aliases":[],"display_name":"d%s","sources":[],"tracks":[],"totals":{"seconds":0,"sessions":0,"tracks":0}}\n' \
		"$_i" "$_i" >"$SELECTA_SOUNDTRACKS/filler-$_i.json"
done
SHIM=$SELECTA_HOME/shim
mkdir -p "$SHIM"
COUNT=$SELECTA_HOME/jqcount
: >"$COUNT"
cat >"$SHIM/jq" <<EOF
#!/bin/sh
printf 'x' >>"$COUNT"
exec $(command -v jq) "\$@"
EOF
chmod +x "$SHIM/jq"
PATH="$SHIM:$PATH" selecta_st_load 'remote:github.com/upstream/proj' >/dev/null 2>&1
_forks=$(wc -c <"$COUNT" | tr -d ' ')
t_eq "one load stays under 5 jq forks with 60 crates on disk" "true" \
	"$([ "$_forks" -lt 5 ] && echo true || echo false)"

rm -rf "$SELECTA_HOME"
