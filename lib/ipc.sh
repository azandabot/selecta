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

selecta_ipc_up() { [ -S "$SELECTA_MPV_SOCK" ]; }

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
