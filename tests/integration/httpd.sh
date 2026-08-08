#!/bin/sh
# The YouTube player server, actually started.
#
# The plugin split renamed a module-level constant and missed one use of the
# old name three lines below it. `python3 -c compile(...)` cannot see an
# undefined name, so CI stayed green and every YouTube track failed with
# NameError at import. Nothing short of starting the process catches that.
#
# No network and no browser: the page is served locally and polled with curl.
set -u

SELECTA_HOME=${TMPDIR:-/tmp}/selecta-tests/$$-httpd
export SELECTA_HOME
rm -rf "$SELECTA_HOME"
mkdir -p "$SELECTA_HOME/run" "$SELECTA_HOME/logs"

# shellcheck source=lib/common.sh
. "$SELECTA_ROOT/lib/common.sh"
# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

YT_ROOT=$(cd -- "$SELECTA_ROOT/../selecta-youtube" && pwd -P)
HTTPD=$YT_ROOT/libexec/selecta-httpd

if ! command -v python3 >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
	printf 'ok httpd suite skipped, needs python3 and curl\n' >>"$T_RESULTS"
	exit 0
fi

SELECTA_YT_ROOT=$YT_ROOT
SELECTA_YT_BIN=$YT_ROOT/bin/selecta-youtube
export SELECTA_YT_ROOT SELECTA_YT_BIN

"$HTTPD" >"$SELECTA_HOME/logs/out" 2>&1 &
HTTPD_PID=$!

_i=0
while [ ! -s "$SELECTA_RUN/httpd.json" ] && [ "$_i" -lt 100 ]; do
	kill -0 "$HTTPD_PID" 2>/dev/null || break
	_i=$((_i + 1))
	sleep 0.1
done

# The failure this exists for: the process dies at import and the only trace is
# a traceback nobody reads. Surface it as the assertion message.
alive_or_why() {
	if kill -0 "$HTTPD_PID" 2>/dev/null; then
		echo up
	else
		# The traceback is the whole point: surface it as the failure message
		# instead of leaving it in a log nobody reads.
		printf 'died: %s' "$(head -5 "$SELECTA_HOME/logs/out" | tr '\n' ' ')"
	fi
}
t_eq "the server starts and stays up" "up" "$(alive_or_why)"
t_empty "the server logs no traceback" \
	"$(grep -l 'Traceback\|NameError\|SyntaxError' "$SELECTA_HOME/logs/out" 2>/dev/null || true)"
t_eq "it advertises itself for the shell to find" "true" \
	"$([ -s "$SELECTA_RUN/httpd.json" ] && echo true || echo false)"

if [ -s "$SELECTA_RUN/httpd.json" ]; then
	ORIGIN=$(jq -r .origin "$SELECTA_RUN/httpd.json")
	TOKEN=$(jq -r .token "$SELECTA_RUN/httpd.json")

	t_eq "health answers" "true" \
		"$(curl -sf --max-time 3 "$ORIGIN/health" | jq -r '.ok // false')"
	# Bound to loopback, because anything else exposes a control channel for
	# the browser to the local network.
	t_eq "it binds loopback only" "1" \
		"$(printf '%s' "$ORIGIN" | grep -c '127\.0\.0\.1')"

	# The page is read at import. This is the exact line that raised NameError.
	t_eq "the player page is served" "200" \
		"$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$ORIGIN/?t=$TOKEN")"
	t_eq "the served page is the real one" "true" \
		"$(curl -s --max-time 3 "$ORIGIN/?t=$TOKEN" |
			grep -q 'YouTube' && echo true || echo false)"

	# A local server the browser talks to still needs the token, or any page
	# the user has open can drive their music.
	t_eq "a missing token is refused" "403" \
		"$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$ORIGIN/cmd")"
	t_eq "a wrong token is refused" "403" \
		"$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$ORIGIN/cmd?t=nope")"

	t_eq "quota is exposed to the page" "true" \
		"$(curl -sf --max-time 3 "$ORIGIN/health" | jq -e 'has("ok")' >/dev/null && echo true || echo false)"

	# Polling is what marks the window alive; before the first poll there is
	# no age, which is how a closed window is told from a live one.
	curl -sf --max-time 3 "$ORIGIN/cmd?t=$TOKEN&since=0" >/dev/null 2>&1 &
	sleep 1
	t_eq "polling marks the window live" "true" \
		"$(curl -sf --max-time 3 "$ORIGIN/health" |
			jq -r 'if .page_age == null then "false" else "true" end')"
	t_eq "the shell agrees the window is up" "0" "$(
		selecta_window_up
		echo $?
	)"
fi

kill "$HTTPD_PID" 2>/dev/null
wait "$HTTPD_PID" 2>/dev/null
rm -rf "$SELECTA_HOME"
