#!/bin/sh
# Status line installation against every shape of settings.json.
# Runs entirely against fixtures; the real ~/.claude/settings.json is untouched.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-settings
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/statusline.sh
. "$SELECTA_ROOT/lib/statusline.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_ROOT/tests/lib.sh"

FIX=$SELECTA_HOME/fixtures
mkdir -p "$FIX"

use() {
	SELECTA_SETTINGS=$FIX/$1.json
	export SELECTA_SETTINGS
}

# --- detection --------------------------------------------------------------
rm -f "$FIX/missing.json"
use missing
t_eq "missing file detected" "missing" "$(selecta_sl_detect)"

: >"$FIX/empty.json"
use empty
t_eq "empty file detected" "empty" "$(selecta_sl_detect)"

printf '{"theme":"dark"}\n' >"$FIX/clean.json"
use clean
t_eq "no statusLine detected" "absent" "$(selecta_sl_detect)"

printf '{"statusLine":{"type":"command","command":"/other/bar.sh"}}\n' >"$FIX/foreign.json"
use foreign
t_eq "foreign statusLine detected" "foreign" "$(selecta_sl_detect)"

printf '{"statusLine":{"type":"command","command":"%s"}}\n' "$SELECTA_SL_SCRIPT" >"$FIX/ours.json"
use ours
t_eq "our own statusLine detected" "ours" "$(selecta_sl_detect)"

printf '{\n  // a comment\n  "theme":"dark"\n}\n' >"$FIX/jsonc.json"
use jsonc
t_eq "jsonc detected, not mistaken for garbage" "jsonc" "$(selecta_sl_detect)"

printf '{"theme":\n' >"$FIX/broken.json"
use broken
t_eq "unparseable detected" "unparseable" "$(selecta_sl_detect)"

printf '{"theme":"dark"}\n' >"$FIX/ro.json"
chmod 444 "$FIX/ro.json"
use ro
t_eq "read-only detected" "readonly" "$(selecta_sl_detect)"
chmod 644 "$FIX/ro.json"

# A URL inside a valid JSON string must not be mistaken for a comment.
printf '{"homepage":"https://example.com/x"}\n' >"$FIX/url.json"
use url
t_eq "// inside a string is not jsonc" "absent" "$(selecta_sl_detect)"

# symlinks resolve to their target
printf '{"theme":"dark"}\n' >"$FIX/target.json"
ln -sf "$FIX/target.json" "$FIX/link.json"
use link
t_eq "symlink resolves to target" "$FIX/target.json" "$(selecta_sl_settings_path)"

# --- refusals ---------------------------------------------------------------
# These must decline rather than damage the file.
for _case in jsonc broken; do
	use "$_case"
	_before=$(cat "$FIX/$_case.json")
	selecta_sl_install >/dev/null 2>&1
	t_eq "install refuses on $_case" "$_before" "$(cat "$FIX/$_case.json")"
done

# --- clean merge ------------------------------------------------------------
use clean
_mode=$(selecta_sl_install)
t_eq "clean merge reports own mode" "own" "$_mode"
t_eq "statusLine added" "command" "$(jq -r '.statusLine.type' "$FIX/clean.json")"
t_eq "existing keys preserved" "dark" "$(jq -r '.theme' "$FIX/clean.json")"
t_eq "refreshInterval is seconds, not milliseconds" "2" \
	"$(jq -r '.statusLine.refreshInterval' "$FIX/clean.json")"
t_eq "points at the stable copy, not the plugin dir" "$SELECTA_HOME/statusline.sh" \
	"$(jq -r '.statusLine.command' "$FIX/clean.json")"
t_eq "launcher copied into place" "yes" \
	"$([ -x "$SELECTA_HOME/statusline.sh" ] && echo yes || echo no)"
t_eq "a backup was taken" "1" "$(find "$FIX" -name 'clean.json.selecta.bak.*' | wc -l | tr -d ' ')"
t_eq "now detected as ours" "ours" "$(selecta_sl_detect)"

# --- uninstall restores the original ---------------------------------------
selecta_sl_uninstall
t_eq "statusLine key removed entirely" "null" "$(jq -r '.statusLine // "null"' "$FIX/clean.json")"
t_eq "other keys survive uninstall" "dark" "$(jq -r '.theme' "$FIX/clean.json")"
t_eq "launcher copy removed" "no" \
	"$([ -f "$SELECTA_HOME/statusline.sh" ] && echo yes || echo no)"

# --- wrap mode --------------------------------------------------------------
use foreign
_mode=$(selecta_sl_install)
t_eq "foreign statusLine triggers wrap mode" "wrap" "$_mode"
t_eq "their command is preserved for the launcher" "/other/bar.sh" \
	"$(cat "$SELECTA_HOME/run/wrapped_command")"
t_eq "settings now point at us" "$SELECTA_HOME/statusline.sh" \
	"$(jq -r '.statusLine.command' "$FIX/foreign.json")"

selecta_sl_uninstall
t_eq "uninstall restores their command exactly" "/other/bar.sh" \
	"$(jq -r '.statusLine.command' "$FIX/foreign.json")"
t_eq "uninstall clears the wrapped command" "no" \
	"$([ -f "$SELECTA_HOME/run/wrapped_command" ] && echo yes || echo no)"

# --- missing file -----------------------------------------------------------
use missing
selecta_sl_install >/dev/null
t_eq "missing settings file is created" "command" "$(jq -r '.statusLine.type' "$FIX/missing.json")"
t_eq "created file is valid json" "0" "$(jq -e . "$FIX/missing.json" >/dev/null 2>&1; echo $?)"

# --- preview is honest ------------------------------------------------------
t_eq "preview is valid json" "0" \
	"$(selecta_sl_preview | sed 's/^  "statusLine": //' | jq -e . >/dev/null 2>&1; echo $?)"

rm -rf "$SELECTA_HOME"
