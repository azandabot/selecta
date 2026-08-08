#!/bin/sh
# mpv IPC client.
#
# mpv's --input-ipc-server socket accepts multiple simultaneous clients, so it
# doubles as selecta's control plane: bin/selecta sends commands here and the
# supervisor holds a second, long-lived connection for property events. A
# separate control socket would only duplicate what mpv already provides.
#
# Protocol is newline-delimited JSON:
#   request  {"command":["set_property","volume",55]}
#   reply    {"error":"success","data":null,"request_id":0}
#   event    {"event":"file-loaded"}

# A socket file outliving its process is the normal case after a crash, so
# existence proves nothing. Everything downstream trusted this, which is how
# `play` came to report success with no player running at all: the stale socket
# made the launcher skip starting mpv, and then nothing consumed the command.
selecta_ipc_up() {
	[ -S "$SELECTA_MPV_SOCK" ] || return 1
	printf '{"command":["get_property","mpv-version"]}\n' |
		nc -U "$SELECTA_MPV_SOCK" 2>/dev/null | head -1 | grep -q '"error":"success"'
}

# Clears a socket whose process is gone, so the next start is not blocked by
# the corpse of the last one.
selecta_ipc_reap() {
	[ -S "$SELECTA_MPV_SOCK" ] || return 0
	selecta_ipc_up && return 0
	selecta_log warn "clearing dead mpv socket"
	rm -f "$SELECTA_MPV_SOCK" 2>/dev/null
	return 0
}

# One request, one reply. nc exits when mpv closes its side or the read times
# out, so a wedged player degrades to a failed command rather than a hang.
selecta_ipc_send() {
	selecta_ipc_up || return "$EX_NOTFOUND"
	printf '%s\n' "$1" | nc -U "$SELECTA_MPV_SOCK" 2>/dev/null | head -1
}

selecta_ipc_command() {
	# selecta_ipc_command <json-array-of-args>
	selecta_ipc_send "{\"command\":$1}"
}

# Returns the property value on stdout, or fails if mpv reports an error.
selecta_ipc_get() {
	_ig_reply=$(selecta_ipc_command "[\"get_property\",\"$1\"]") || return 1
	[ -n "$_ig_reply" ] || return 1
	printf '%s' "$_ig_reply" | jq -e -r 'select(.error == "success") | .data' 2>/dev/null
}

selecta_ipc_set() {
	selecta_ipc_command "[\"set_property\",\"$1\",$2]" >/dev/null
}

selecta_ipc_quit() {
	selecta_ipc_command '["quit"]' >/dev/null 2>&1 || true
}
