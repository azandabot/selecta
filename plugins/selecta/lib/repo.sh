#!/bin/sh
# Repository identity.
#
# Answers "which soundtrack does this directory belong to?" and must answer it
# the same way every time, across clones, worktrees and remote changes, or a
# repo silently loses its accumulated history.
#
# Sets, via selecta_repo_identity:
#   SELECTA_REPO_SCOPE    remote | local | dir
#   SELECTA_REPO_KEY      stable identity, e.g. remote:github.com/azandabot/selecta
#   SELECTA_REPO_NAME     display name
#   SELECTA_REPO_ALIASES  newline-separated alternate keys from other remotes
#   SELECTA_REPO_BRANCH   branch name, or HEAD when detached (never cached)
#   SELECTA_REPO_COMMIT   short sha, empty in an empty repo (never cached)
#
# Those are out-parameters read by callers, which are analysed separately.
# shellcheck disable=SC2034

# Reduces any remote URL form to "host/path", lowercased and suffix-free, so
# that ssh, https and scp-style remotes for the same repository collapse to one
# identity.
selecta_normalize_remote() {
	printf '%s' "$1" | sed -e 's|^[A-Za-z][A-Za-z0-9+.-]*://||' \
		-e 's|^[^@/]*@||' \
		-e 's|:[0-9][0-9]*/|/|' \
		-e 's|:|/|' \
		-e 's|/*$||' \
		-e 's|\.git$||' \
		-e 's|/*$||' \
		-e 's|//*|/|g' |
		tr '[:upper:]' '[:lower:]'
}

_selecta_git() { git -C "$_ri_dir" "$@" 2>/dev/null; }

# Every remote, normalized and deduplicated, origin first. Used to build the
# alias list that lets a fork-to-upstream remote swap carry the soundtrack over
# instead of silently starting a new one.
_selecta_all_remote_keys() {
	_arf_out=$(_selecta_git remote) || return 0
	{
		printf 'origin\nupstream\n'
		printf '%s\n' "$_arf_out"
	} | awk 'NF && !seen[$0]++' | while IFS= read -r _arf_name; do
		_arf_url=$(_selecta_git remote get-url "$_arf_name")
		[ -n "$_arf_url" ] || continue
		printf 'remote:%s\n' "$(selecta_normalize_remote "$_arf_url")"
	done | awk 'NF && !seen[$0]++'
}

selecta_repo_identity() {
	_ri_dir=${1:-$PWD}
	SELECTA_REPO_SCOPE=dir
	SELECTA_REPO_KEY=
	SELECTA_REPO_NAME=
	SELECTA_REPO_ALIASES=
	SELECTA_REPO_BRANCH=
	SELECTA_REPO_COMMIT=

	_ri_top=$(_selecta_git rev-parse --show-toplevel)

	if [ -z "$_ri_top" ]; then
		# Not a git repository. Still fully functional, but bound to a path,
		# which /selecta crate states plainly.
		_ri_real=$(selecta_realpath "$_ri_dir")
		SELECTA_REPO_SCOPE=dir
		SELECTA_REPO_KEY="dir:$(selecta_sha16 "$_ri_real")"
		SELECTA_REPO_NAME=$(basename -- "$_ri_real")
		return 0
	fi

	# Worktrees share one common dir, so every worktree of a repository shares
	# a single soundtrack. A worktree is the same project.
	_ri_common=$(_selecta_git rev-parse --path-format=absolute --git-common-dir)
	[ -n "$_ri_common" ] || _ri_common=$_ri_top/.git
	_ri_common=$(selecta_realpath "$_ri_common")

	SELECTA_REPO_BRANCH=$(_selecta_git rev-parse --abbrev-ref HEAD)
	SELECTA_REPO_COMMIT=$(_selecta_git rev-parse --short HEAD)

	_ri_keys=$(_selecta_all_remote_keys)

	if [ -n "$_ri_keys" ]; then
		SELECTA_REPO_SCOPE=remote
		SELECTA_REPO_KEY=$(printf '%s\n' "$_ri_keys" | head -1)
		SELECTA_REPO_ALIASES=$(printf '%s\n' "$_ri_keys" | tail -n +2)
		SELECTA_REPO_NAME=$(basename -- "$SELECTA_REPO_KEY")
	else
		SELECTA_REPO_SCOPE=local
		SELECTA_REPO_KEY="local:$(selecta_sha16 "$_ri_common")"
		SELECTA_REPO_NAME=$(basename -- "$_ri_top")
	fi
	return 0
}

# Soundtrack filename for a key: readable enough to browse by hand, hashed so
# that two keys differing only in case cannot collide on a case-insensitive
# filesystem.
selecta_repo_soundtrack_file() {
	_sf_key=$1
	_sf_safe=$(printf '%s' "$_sf_key" | tr '[:upper:]' '[:lower:]' |
		sed 's|[^a-z0-9._-]|-|g' | cut -c1-80 | sed 's|-*$||')
	printf '%s/%s-%s.json' "$SELECTA_SOUNDTRACKS" "$_sf_safe" "$(selecta_sha8 "$_sf_key")"
}

# The identity as one JSON object, which is how every consumer wants it.
repo_json() {
	selecta_repo_identity "$PWD"
	jq -n --arg key "$SELECTA_REPO_KEY" --arg name "$SELECTA_REPO_NAME" \
		--arg scope "$SELECTA_REPO_SCOPE" --arg branch "$SELECTA_REPO_BRANCH" \
		--arg commit "$SELECTA_REPO_COMMIT" \
		--arg aliasstr "$SELECTA_REPO_ALIASES" \
		'{key: $key, display_name: $name, scope: $scope, branch: $branch,
		  commit: $commit,
		  aliases: ($aliasstr | split("\n") | map(select(length > 0)))}'
}
