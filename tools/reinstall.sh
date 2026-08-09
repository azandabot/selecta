#!/bin/sh
# Reinstall both plugins from this working tree.
#
# `claude plugin install` copies the plugin into a cache directory keyed by
# version. `claude plugin update` compares versions, so with the version
# unchanged it is a no-op: you edit the repo, run update, it reports success,
# and /selecta keeps running the code from whenever you last bumped. The
# staleness is invisible because everything still works.
#
# So this deletes the cached copy and installs again. It is the only reliable
# way to test an edit without inventing a version number for it.
#
#   tools/reinstall.sh          both plugins
#   tools/reinstall.sh selecta  just the one
#
# Restart your Claude Code session afterwards: skills, commands and hooks are
# read at session start. The `selecta` binaries work immediately either way.
set -eu

MARKET=azandabot-selecta
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
CACHE=$HOME/.claude/plugins/cache/$MARKET

command -v claude >/dev/null 2>&1 || {
	printf 'reinstall: the claude CLI is not on PATH.\n' >&2
	exit 1
}

if [ $# -gt 0 ]; then
	PLUGINS=$*
else
	PLUGINS=$(find "$ROOT/plugins" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; |
		sort | tr '\n' ' ')
fi

printf 'reinstalling from %s\n\n' "$ROOT"

# Refuse to install something that will not load. A broken manifest installs
# fine and then fails silently at session start, which is a slow way to find
# a typo.
for p in $PLUGINS; do
	claude plugin validate "$ROOT/plugins/$p/.claude-plugin/plugin.json" --strict >/dev/null || {
		printf 'reinstall: %s does not validate, refusing to install it.\n' "$p" >&2
		exit 1
	}
done
claude plugin validate "$ROOT" --strict >/dev/null || {
	printf 'reinstall: the marketplace does not validate.\n' >&2
	exit 1
}

for p in $PLUGINS; do
	rm -rf "${CACHE:?}/$p"
	claude plugin uninstall "$p@$MARKET" >/dev/null 2>&1 || true
done

claude plugin marketplace update "$MARKET" >/dev/null

for p in $PLUGINS; do
	claude plugin install "$p@$MARKET" >/dev/null
	printf '  installed %-16s %s\n' "$p" \
		"$(jq -r .version "$ROOT/plugins/$p/.claude-plugin/plugin.json" 2>/dev/null)"
done

# The status line runs a copy outside the plugin so a versioned install path
# cannot break it. Running the CLI once refreshes that copy.
if [ -x "$ROOT/plugins/selecta/bin/selecta" ]; then
	"$ROOT/plugins/selecta/bin/selecta" --version >/dev/null 2>&1 || true
fi

printf '\nverifying the installed copy matches this tree:\n'
_drift=0
for p in $PLUGINS; do
	_v=$(jq -r .version "$ROOT/plugins/$p/.claude-plugin/plugin.json" 2>/dev/null)
	if diff -rq "$ROOT/plugins/$p" "$CACHE/$p/$_v" >/dev/null 2>&1; then
		printf '  %-16s identical\n' "$p"
	else
		printf '  %-16s DIFFERS from the installed copy\n' "$p"
		_drift=1
	fi
done
[ "$_drift" -eq 0 ] || exit 1

printf '\nRestart your Claude Code session to pick up skills, commands and hooks.\n'
