#!/bin/sh
# Repo identity: remote normalization table, plus real git scenarios.
set -u

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/repo.sh
. "$SELECTA_ROOT/lib/repo.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

EXPECT=github.com/azandabot/selecta

# --- normalization table ---
n() { selecta_normalize_remote "$1"; }

t_eq "scp-style ssh"          "$EXPECT" "$(n 'git@github.com:azandabot/selecta.git')"
t_eq "https with .git"        "$EXPECT" "$(n 'https://github.com/azandabot/selecta.git')"
t_eq "https without .git"     "$EXPECT" "$(n 'https://github.com/azandabot/selecta')"
t_eq "ssh:// scheme"          "$EXPECT" "$(n 'ssh://git@github.com/azandabot/selecta.git')"
t_eq "ssh:// with port"       "$EXPECT" "$(n 'ssh://git@github.com:22/azandabot/selecta.git')"
t_eq "git:// scheme"          "$EXPECT" "$(n 'git://github.com/azandabot/selecta.git')"
t_eq "mixed case"             "$EXPECT" "$(n 'https://GitHub.com/Azandabot/Selecta.git')"
t_eq "embedded credentials"   "$EXPECT" "$(n 'https://user:token@github.com/azandabot/selecta.git')"
t_eq "trailing slash"         "$EXPECT" "$(n 'https://github.com/azandabot/selecta/')"
t_eq "trailing .git + slash"  "$EXPECT" "$(n 'git@github.com:azandabot/selecta.git/')"
t_eq "duplicate slashes"      "$EXPECT" "$(n 'https://github.com//azandabot//selecta.git')"

t_eq "nested gitlab group" "gitlab.com/group/sub/proj" "$(n 'git@gitlab.com:group/sub/proj.git')"
t_eq "bitbucket"           "bitbucket.org/team/repo"   "$(n 'git@bitbucket.org:team/repo.git')"
t_eq "azure devops"        "dev.azure.com/org/proj/_git/repo" \
	"$(n 'https://dev.azure.com/org/proj/_git/repo')"
t_eq "file:// url"         "/home/me/repo"             "$(n 'file:///home/me/repo.git')"
t_eq "bare local path"     "/srv/git/repo"             "$(n '/srv/git/repo.git')"
t_eq "relative path"       "../sibling"                "$(n '../sibling')"

# ssh and https for the same repo must collapse to one identity, or a user who
# switches remote protocol silently loses their soundtrack.
t_eq "ssh and https agree" \
	"$(n 'git@github.com:azandabot/selecta.git')" \
	"$(n 'https://github.com/azandabot/selecta.git')"

# --- real git scenarios ---
TMP=$(t_tmpdir repo)

# non-git directory
mkdir -p "$TMP/plain"
selecta_repo_identity "$TMP/plain"
t_eq "non-git scope" "dir" "$SELECTA_REPO_SCOPE"
t_eq "non-git name" "plain" "$SELECTA_REPO_NAME"
case $SELECTA_REPO_KEY in
dir:*) t_eq "non-git key prefix" "ok" "ok" ;;
*) t_eq "non-git key prefix" "dir:..." "$SELECTA_REPO_KEY" ;;
esac

# git repo with no remote
mkdir -p "$TMP/noremote"
t_git_init "$TMP/noremote"
selecta_repo_identity "$TMP/noremote"
t_eq "no-remote scope" "local" "$SELECTA_REPO_SCOPE"
t_eq "no-remote name" "noremote" "$SELECTA_REPO_NAME"
t_eq "no-remote branch" "main" "$SELECTA_REPO_BRANCH"
t_ne "no-remote commit present" "" "$SELECTA_REPO_COMMIT"

# git repo with origin
mkdir -p "$TMP/withremote"
t_git_init "$TMP/withremote"
git -C "$TMP/withremote" remote add origin git@github.com:azandabot/selecta.git
selecta_repo_identity "$TMP/withremote"
t_eq "remote scope" "remote" "$SELECTA_REPO_SCOPE"
t_eq "remote key" "remote:$EXPECT" "$SELECTA_REPO_KEY"
t_eq "remote name" "selecta" "$SELECTA_REPO_NAME"

# origin wins over other remotes, and the others become aliases
git -C "$TMP/withremote" remote add upstream https://github.com/someone/selecta.git
selecta_repo_identity "$TMP/withremote"
t_eq "origin still wins" "remote:$EXPECT" "$SELECTA_REPO_KEY"
t_eq "upstream recorded as alias" "remote:github.com/someone/selecta" "$SELECTA_REPO_ALIASES"

# a repo whose only remote is not named origin
mkdir -p "$TMP/oddremote"
t_git_init "$TMP/oddremote"
git -C "$TMP/oddremote" remote add heroku git@github.com:azandabot/other.git
selecta_repo_identity "$TMP/oddremote"
t_eq "non-origin remote still used" "remote:github.com/azandabot/other" "$SELECTA_REPO_KEY"

# worktrees share the parent's identity: a worktree is the same project
git -C "$TMP/withremote" worktree add -q -b wt "$TMP/wt" >/dev/null 2>&1
selecta_repo_identity "$TMP/withremote"
_main_key=$SELECTA_REPO_KEY
selecta_repo_identity "$TMP/wt"
t_eq "worktree shares key" "$_main_key" "$SELECTA_REPO_KEY"
t_eq "worktree reports own branch" "wt" "$SELECTA_REPO_BRANCH"

# detached HEAD keeps identity, reports HEAD as the branch
_sha=$(git -C "$TMP/withremote" rev-parse HEAD)
git -C "$TMP/withremote" checkout -q --detach "$_sha"
selecta_repo_identity "$TMP/withremote"
t_eq "detached keeps key" "$_main_key" "$SELECTA_REPO_KEY"
t_eq "detached branch is HEAD" "HEAD" "$SELECTA_REPO_BRANCH"

# a no-remote repo keyed on the common dir is stable across subdirectories
mkdir -p "$TMP/noremote/deep/nested"
selecta_repo_identity "$TMP/noremote"
_root_key=$SELECTA_REPO_KEY
selecta_repo_identity "$TMP/noremote/deep/nested"
t_eq "subdirectory shares key" "$_root_key" "$SELECTA_REPO_KEY"

# --- soundtrack filename ---
_f=$(selecta_repo_soundtrack_file "remote:github.com/azandabot/selecta")
t_eq "soundtrack filename" \
	"remote-github.com-azandabot-selecta-$(selecta_sha8 'remote:github.com/azandabot/selecta').json" \
	"$(basename -- "$_f")"

# keys differing only in case must not collide on a case-insensitive filesystem
_a=$(basename -- "$(selecta_repo_soundtrack_file 'remote:github.com/A/b')")
_b=$(basename -- "$(selecta_repo_soundtrack_file 'remote:github.com/a/B')")
t_ne "case-variant keys do not collide" "$_a" "$_b"

rm -rf "$TMP"
