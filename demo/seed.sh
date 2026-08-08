#!/bin/sh
# Builds a demo repository whose crate already looks lived-in.
#
# A fresh install shows "0s · 1 track", which reads as fake next to a README
# claiming months of history. This backdates a plausible crate so a recording
# starts with something real to show.
#
#   demo/seed.sh              build it
#   cd "$(cat /tmp/selecta-demo-path)" && claude
#
# Everything it writes lives under a throwaway SELECTA_HOME, so your own crates
# are untouched.
set -eu

ROOT=$(cd -- "$(dirname -- "$0")/../plugins/selecta" && pwd -P)
DEMO=${SELECTA_DEMO_DIR:-${TMPDIR:-/tmp}/selecta-demo}
SELECTA_HOME="$DEMO/home"
export SELECTA_HOME
REPO="$DEMO/demo-api"

rm -rf "$DEMO"
mkdir -p "$SELECTA_HOME/soundtracks" "$SELECTA_HOME/run" "$REPO"

# --- a repository with real history ----------------------------------------
cd "$REPO"
git init -q -b main
git config user.name "Azanda"
git config user.email "azandagp@gmail.com"
git remote add origin git@github.com:azandabot/demo-api.git

i=0
for msg in \
	"initial commit" \
	"add lead capture endpoint" \
	"add session cookie rotation" \
	"extract auth middleware" \
	"fix auth redirect loop"; do
	i=$((i + 1))
	printf '%s\n' "$msg" >>CHANGELOG
	git add -A
	GIT_AUTHOR_DATE="$(($(date +%s) - (57 - i * 11) * 86400))" \
		GIT_COMMITTER_DATE="$(($(date +%s) - (57 - i * 11) * 86400))" \
		git commit -q -m "$msg"
done

KEY="remote:github.com/azandabot/demo-api"
HASH=$(printf '%s' "$KEY" | shasum -a 256 | cut -c1-8)
FILE=$SELECTA_HOME/soundtracks/remote-github.com-azandabot-demo-api-$HASH.json

iso() { date -u -r "$(($(date +%s) - $1 * 86400))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ; }

# Commit shas are read back out of the repo, so `crate` and `history` line up
# with real commits rather than invented ones.
C1=$(git log --format=%h --reverse | sed -n 1p)
C3=$(git log --format=%h --reverse | sed -n 3p)
C5=$(git log --format=%h --reverse | sed -n 5p)

jq -n \
	--arg key "$KEY" \
	--arg created "$(iso 57)" \
	--arg updated "$(iso 0)" \
	--arg d0 "$(iso 0)" --arg d1 "$(iso 1)" --arg d6 "$(iso 6)" --arg d57 "$(iso 57)" \
	--arg c1 "$C1" --arg c3 "$C3" --arg c5 "$C5" \
	'{
	schema: 1, key: $key, aliases: [], display_name: "demo-api", scope: "remote",
	created_at: $created, updated_at: $updated,
	totals: {seconds: 48210, sessions: 31, tracks: 902},
	sources: [
	  {id:"somafm:groovesalad", kind:"station", provider:"somafm", title:"Groove Salad",
	   resolver:{type:"somafm",id:"groovesalad"},
	   first_played_at:$d57, last_played_at:$d0, seconds:30110, plays:22, pinned:false, banned:false},
	  {id:"somafm:dronezone", kind:"station", provider:"somafm", title:"Drone Zone",
	   resolver:{type:"somafm",id:"dronezone"},
	   first_played_at:$d57, last_played_at:$d1, seconds:11400, plays:9, pinned:false, banned:false},
	  {id:"somafm:missioncontrol", kind:"station", provider:"somafm", title:"Mission Control",
	   resolver:{type:"somafm",id:"missioncontrol"},
	   first_played_at:$d57, last_played_at:$d6, seconds:6700, plays:4, pinned:false, banned:false}
	],
	tracks: (
	  [{t:$d57, src:"somafm:groovesalad", artist:"Tycho", title:"Awake", secs:271, branch:"main", commit:$c1}]
	  + [range(0;13) | {t:$d6, src:"somafm:groovesalad", artist:"Alex Cortiz", title:"Barista Breaks",
					   secs:214, branch:"main", commit:$c3}]
	  + [{t:$d1, src:"somafm:dronezone", artist:"Steve Roach", title:"Structures from Silence",
		  secs:1802, branch:"main", commit:$c3},
		 {t:$d0, src:"somafm:groovesalad", artist:"Bonobo", title:"Kong", secs:298, branch:"main", commit:$c5},
		 {t:$d0, src:"somafm:groovesalad", artist:"Alex Cortiz", title:"Barista Breaks",
		  secs:214, branch:"main", commit:$c5},
		 {t:$d0, src:"somafm:missioncontrol", artist:"Boards of Canada", title:"Dayvan Cowboy",
		  secs:301, branch:"main", commit:$c5}]
	)
  }' >"$FILE"

jq -n --arg k "$KEY" --arg f "$(basename "$FILE")" --arg u "$(iso 0)" \
	'{($k): {file:$f, display_name:"demo-api", updated_at:$u, seconds:48210}}' \
	>"$SELECTA_HOME/soundtracks/index.json"

# Borrow the real YouTube key if one is configured, so the demo's YouTube step
# actually plays. Nothing else is copied out of the real home.
_realcfg=$HOME/.claude/selecta/config.json
if [ -s "$_realcfg" ]; then
	_k=$(jq -r '.youtube.api_key // ""' "$_realcfg" 2>/dev/null)
	if [ -n "$_k" ]; then
		jq -n --arg k "$_k" '{youtube: {api_key: $k}}' >"$SELECTA_HOME/config.json"
		printf 'Borrowed your YouTube key so the demo can play a named track.\n'
	fi
fi

printf '%s' "$REPO" >/tmp/selecta-demo-path

cat <<EOF

Demo ready.

  repo          $REPO
  crate         13h 24m · 902 tracks across 3 stations
  SELECTA_HOME  $SELECTA_HOME

Preview it now:

  cd "$REPO" && SELECTA_HOME="$SELECTA_HOME" $ROOT/bin/selecta crate

To record inside a session, export SELECTA_HOME first so it picks up this crate:

  cd "$REPO"
  export SELECTA_HOME="$SELECTA_HOME"
  claude

EOF
