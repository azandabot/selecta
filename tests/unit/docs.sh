#!/bin/sh
# The README is the only thing most people will ever read, and it has been
# wrong before: it documented three subcommands that had been deleted, a
# resolver tier that no longer existed, an assertion count that drifted with
# every commit, and a test file that had never been written.
#
# Prose cannot be tested, but every checkable claim in it can be.
set -u

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

REPO=$(cd -- "$SELECTA_ROOT/../.." && pwd -P)
README=$REPO/README.md
CLI=$SELECTA_ROOT/bin/selecta

t_eq "the README exists" "true" "$([ -s "$README" ] && echo true || echo false)"

# --- every documented slash command is a real command file --------------------
# These are the fallback for when the skill router does not fire, so a
# documented command that does not exist fails in the most confusing way.
t_eq "every /plugin:command in the README exists" "" "$(
	grep -o '/selecta[a-z-]*:[a-z-]*' "$README" | sort -u | while read -r ref; do
		_plug=${ref%%:*}
		_plug=${_plug#/}
		_cmd=${ref##*:}
		[ -f "$REPO/plugins/$_plug/commands/$_cmd.toml" ] || printf '%s\n' "$ref"
	done
)"

# --- every documented subcommand is routed ------------------------------------
# Read out of the fenced command table, then checked against the dispatcher
# rather than against usage(), because usage() is prose too.
t_eq "every subcommand in the README is dispatched" "" "$(
	grep -o '`/selecta:selecta [a-z]*' "$README" | awk '{print $2}' | sort -u |
		while read -r sub; do
			[ -n "$sub" ] || continue
			grep -qE "^	($sub|[a-z |]*\| *$sub)\)" "$CLI" || printf '%s\n' "$sub"
		done
)"

# --- claims that drift ---------------------------------------------------------
# An assertion count in prose is stale the moment anyone adds a test, and it
# was: the README said 192 while the suite ran 213.
t_eq "no assertion counts in the README" "" \
	"$(grep -nE '[0-9]{2,} (assertions|tests)' "$README" || true)"

# The station count appears in the README, a skill body and the seed file.
SEED_N=$(jq '.channels|length' "$SELECTA_ROOT/data/somafm-channels.seed.json")
t_eq "the station count matches the seed data" "" "$(
	grep -oE '[0-9]+ (curated|-station)' "$README" | grep -oE '^[0-9]+' | sort -u |
		while read -r n; do
			[ "$n" = "$SEED_N" ] || printf 'README says %s, seed has %s\n' "$n" "$SEED_N"
		done
)"

# --- nothing describes a deleted feature ---------------------------------------
# Each of these shipped in a README that outlived the code by a release.
for gone in ffplay 'selecta export' 'selecta curate' 'selecta pin' 'selecta ban' \
	'selecta history' 'Internet Archive' netlabel; do
	t_eq "the README does not mention $gone" "" \
		"$(grep -Fn "$gone" "$README" || true)"
done

# --- every referenced local file exists ----------------------------------------
# shellcheck disable=SC2016
t_eq "every path the README points at exists" "" "$(
	grep -oE '`(\./)?(tests|plugins|evals|demo)/[A-Za-z0-9_./-]+`' "$README" |
		tr -d '`' | sed 's|^\./||' | sort -u | while read -r p; do
		[ -e "$REPO/$p" ] || printf '%s\n' "$p"
	done
)"

# --- images ------------------------------------------------------------------
# GitHub's markdown sanitiser drops `style`, so an inline width does nothing
# and the image renders at its natural size. It fails silently, which is how a
# 1614px logo shipped. width= and align= survive; style= never does.
t_eq "no inline style attributes in the README" "" \
	"$(grep -n 'style=' "$README" || true)"

# Absolute raw URLs are used so aggregator and marketplace UIs can render this
# README outside the repo, which means a moved file breaks a page nobody here
# will look at. Check the path resolves against the tree.
t_eq "every raw.githubusercontent asset exists in the repo" "" "$(
	grep -o 'https://raw\.githubusercontent\.com/[^)" ]*' "$README" | sort -u |
		while read -r u; do
			_rel=${u#https://raw.githubusercontent.com/}
			_rel=${_rel#*/}
			_rel=${_rel#*/}
			_rel=${_rel#*/}
			[ -e "$REPO/$_rel" ] || printf '%s\n' "$u"
		done
)"
t_eq "every local image the README points at exists" "" "$(
	grep -oE 'src="(assets|docs|demo)/[A-Za-z0-9_./-]+"' "$README" |
		sed 's/^src="//; s/"$//' | sort -u | while read -r p; do
		[ -e "$REPO/$p" ] || printf '%s\n' "$p"
	done
)"
# A README header image is downloaded by everyone who opens the page.
t_eq "no README image is oversized" "" "$(
	find "$REPO/assets" -type f 2>/dev/null | while read -r f; do
		_kb=$(($(wc -c <"$f") / 1024))
		[ "$_kb" -le 600 ] || printf '%s is %sKB\n' "${f##*/}" "$_kb"
	done
)"

# --- the headline claim ---------------------------------------------------------
# "No key, no config, no dependencies, nothing to run." The launcher is what
# makes that true or false, and it is one grep away from becoming false.
LAUNCHER=$SELECTA_ROOT/statusline/launcher.sh
for forbidden in jq git curl python3 awk sed grep; do
	t_eq "the status line launcher does not fork $forbidden" "0" \
		"$(grep -cE "(^|[^-_a-zA-Z])$forbidden " "$LAUNCHER" || true)"
done

# --- the CHANGELOG names the version being shipped ------------------------------
VER=$(jq -r .version "$SELECTA_ROOT/.claude-plugin/plugin.json")
t_eq "the CHANGELOG has an entry for $VER" "true" \
	"$(grep -qF "[$VER]" "$REPO/CHANGELOG.md" && echo true || echo false)"
t_eq "both plugins ship the same version" "$VER" \
	"$(jq -r .version "$REPO/plugins/selecta-youtube/.claude-plugin/plugin.json")"
t_eq "the shell constant agrees with the manifest" "$VER" "$SELECTA_VERSION"
