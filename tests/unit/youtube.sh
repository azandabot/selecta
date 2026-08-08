#!/bin/sh
# The selecta-youtube plugin: key detection, quota accounting, and the error
# classification that decides whether a user is told "no results" or "you never
# switched the API on".
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-youtube
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run" "$SELECTA_HOME/cache"

SELECTA_YT_ROOT=$(cd -- "$SELECTA_ROOT/../selecta-youtube" && pwd -P)
export SELECTA_YT_ROOT

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=lib/youtube.sh
. "$SELECTA_YT_ROOT/lib/youtube.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

# --- no key means no window ---------------------------------------------------
# With no API key, a YouTube-shaped request must degrade rather than opening an
# empty player.
unset YOUTUBE_API_KEY
t_eq "no key is detected" "1" "$(
	selecta_yt_have_key
	echo $?
)"
t_eq "no key yields status nokey" "nokey" \
	"$(selecta_yt_resolve "sponono by kabza" | jq -r .status)"
t_eq "nokey returns no candidates" "0" \
	"$(selecta_yt_resolve "sponono by kabza" | jq -r '.candidates|length')"

# --- quota accounting ---------------------------------------------------------
t_eq "a fresh day starts at zero searches" "0" "$(selecta_yt_quota_used)"
t_eq "a fresh day has the full budget" "100" "$(selecta_yt_quota_left)"

# --- error classification -----------------------------------------------------
# The bug this replaces: a 403 from a project that never enabled YouTube Data
# API v3 was indistinguishable from "nothing matched". selecta played radio and
# doctor reported "key set", so the one thing the user had to fix was the one
# thing nothing mentioned.
#
# curl is stubbed rather than mocked at the function level, so the real parsing
# runs against real API error bodies.
STUB=$SELECTA_HOME/stub
mkdir -p "$STUB"
cat >"$STUB/curl" <<'EOF'
#!/bin/sh
cat "$SELECTA_HOME/stub/response.json"
EOF
chmod +x "$STUB/curl"

# Classification only happens once there is a key to reject.
selecta_cfg_set '.youtube.api_key' '"testkey"'

api_error() {
	printf '{"error":{"code":%s,"message":"m","errors":[{"reason":"%s"}]}}\n' "$1" "$2" \
		>"$STUB/response.json"
}

reason_status() {
	rm -rf "${SELECTA_CACHE:?}/yt"
	PATH="$STUB:$PATH" selecta_yt_resolve "some track" | jq -r .status
}

api_error 403 accessNotConfigured
t_eq "an unenabled API is not reported as no-results" "notenabled" "$(reason_status)"
api_error 403 quotaExceeded
t_eq "an exhausted quota is its own status" "quota" "$(reason_status)"
api_error 400 keyInvalid
t_eq "a rejected key is its own status" "badkey" "$(reason_status)"
api_error 500 backendError
t_eq "an unrecognised error is still just none" "none" "$(reason_status)"

# doctor asks the same question directly, and must never claim a broken key is
# fine. videos.list, so the probe costs nothing from the search bucket.
probe() {
	PATH="$STUB:$PATH" selecta_yt_probe
}
api_error 403 accessNotConfigured
t_eq "probe names an unenabled API" "notenabled" "$(probe)"
api_error 403 keyInvalid
t_eq "probe names a bad key" "badkey" "$(probe)"
printf '{"items":[{"status":{"embeddable":true}}]}\n' >"$STUB/response.json"
t_eq "probe passes a working key" "ok" "$(probe)"
: >"$STUB/response.json"
t_eq "probe reports offline rather than guessing" "unreachable" "$(probe)"
selecta_cfg_set '.youtube.api_key' '""'
t_eq "probe with no key says so" "nokey" "$(probe)"

# --- the cross-plugin boundary ------------------------------------------------
# selecta must be able to see and control a YouTube track without the plugin
# that plays it being loaded. These three files are the entire contract.
t_eq "a queued command lands where the page reads it" '{"action":"pause"}' \
	"$(
		selecta_yt_queue '{"action":"pause"}'
		cat "$SELECTA_RUN/yt-cmd.json"
	)"
t_eq "no httpd.json means no window" "1" "$(
	rm -f "$SELECTA_RUN/httpd.json"
	selecta_window_up
	echo $?
)"
t_eq "an httpd.json with no origin means no window" "1" "$(
	printf '{}\n' >"$SELECTA_RUN/httpd.json"
	selecta_window_up
	echo $?
)"

# The pointer, not a glob of the versioned plugin cache path.
t_eq "an absent plugin is reported as absent" "absent" "$(
	rm -f "$SELECTA_HOME/yt-bin-path"
	PATH=$STUB selecta_yt_bin >/dev/null 2>&1 && echo found || echo absent
)"
printf '%s\n' "$SELECTA_YT_ROOT/bin/selecta-youtube" >"$SELECTA_HOME/yt-bin-path"
t_eq "the pointer file locates the plugin" "$SELECTA_YT_ROOT/bin/selecta-youtube" \
	"$(PATH=$STUB selecta_yt_bin)"
printf '%s\n' "$SELECTA_HOME/gone" >"$SELECTA_HOME/yt-bin-path"
t_eq "a stale pointer is not trusted" "absent" "$(
	PATH=$STUB selecta_yt_bin >/dev/null 2>&1 && echo found || echo absent
)"

# A pointer written from a relative $0 only resolves from the directory the
# command happened to be run in, which is not the one the status line uses.
is_abs() { _a=$(cat "$1" 2>/dev/null); [ -n "$_a" ] && [ "${_a#/}" != "$_a" ]; }
t_eq "the pointer selecta-youtube writes is absolute" "0" "$(
	cd / && "$SELECTA_YT_ROOT/bin/selecta-youtube" --version >/dev/null 2>&1
	is_abs "$SELECTA_HOME/yt-bin-path"
	echo $?
)"
t_eq "the pointer selecta writes is absolute" "0" "$(
	cd / && "$SELECTA_ROOT/bin/selecta" doctor >/dev/null 2>&1
	is_abs "$SELECTA_HOME/bin-path"
	echo $?
)"

rm -rf "$SELECTA_HOME"
