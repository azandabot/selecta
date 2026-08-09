#!/bin/sh
# mpv IPC client.
#
# mpv's --input-ipc-server socket accepts multiple simultaneous clients, so it
# doubles as selecta's control plane: bin/selecta sends commands here and the
# supervisor polls the same socket. A separate control socket would only
# duplicate what mpv already provides.
#
# Protocol is newline-delimited JSON:
#   request  {"command":["set_property","volume",55]}
#   reply    {"error":"success","data":null,"request_id":0}

# Talking to a unix socket from a shell needs a helper, and `nc -U` is not one
# of the things you can assume: busybox nc has no -U at all, and Debian's
# netcat-traditional ships without it. This was a hard dependency checked
# nowhere and documented nowhere, so a container user got "the player did not
# accept that stream" while doctor reported everything healthy.
selecta_ipc_transport() {
	if [ -s "$SELECTA_RUN/ipc-transport" ]; then
		cat "$SELECTA_RUN/ipc-transport"
		return 0
	fi
	_it=none
	if selecta_have nc && nc -h 2>&1 | grep -q -- '-U'; then
		_it=nc
	elif selecta_have ncat; then
		_it=ncat
	elif selecta_have socat; then
		_it=socat
	elif selecta_have python3; then
		_it=python3
	fi
	mkdir -p "$SELECTA_RUN" 2>/dev/null && printf '%s' "$_it" >"$SELECTA_RUN/ipc-transport"
	printf '%s' "$_it"
}

selecta_ipc_have_transport() { [ "$(selecta_ipc_transport)" != none ]; }

# One request, one reply. Every backend is given a bounded life so a wedged
# player degrades to a failed command rather than a hung session.
_selecta_ipc_raw() {
	case $(selecta_ipc_transport) in
	nc) nc -U "$SELECTA_MPV_SOCK" 2>/dev/null ;;
	ncat) ncat -U "$SELECTA_MPV_SOCK" 2>/dev/null ;;
	socat) socat - "UNIX-CONNECT:$SELECTA_MPV_SOCK" 2>/dev/null ;;
	python3)
		python3 -c '
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect(sys.argv[1])
    s.sendall(sys.stdin.buffer.read())
    s.shutdown(socket.SHUT_WR)
    while True:
        b = s.recv(4096)
        if not b:
            break
        sys.stdout.buffer.write(b)
except OSError:
    sys.exit(1)
' "$SELECTA_MPV_SOCK" 2>/dev/null
		;;
	*) return "$EX_MISSING_DEP" ;;
	esac
}

# A socket file outliving its process is the normal case after a crash, so
# existence proves nothing. Everything downstream trusted this, which is how
# `play` came to report success with no player running at all.
selecta_ipc_up() {
	[ -S "$SELECTA_MPV_SOCK" ] || return 1
	printf '{"command":["get_property","mpv-version"]}\n' |
		_selecta_ipc_raw | head -1 | grep -q '"error":"success"'
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

selecta_ipc_send() {
	[ -S "$SELECTA_MPV_SOCK" ] || return "$EX_NOTFOUND"
	printf '%s\n' "$1" | _selecta_ipc_raw | head -1
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

# Starting one backend has to silence the other. selecta_np_pause_others deals
# with other applications; this is selecta arguing with itself, which is worse:
# radio kept playing under a YouTube track, and the radio's state overwrote the
# YouTube one, so the banner and the status line both named the wrong song.
selecta_stop_radio() {
	rm -f "$SELECTA_RUN/want-mpv" 2>/dev/null || true
	selecta_ipc_up 2>/dev/null || return 0
	selecta_ipc_command '["stop"]' >/dev/null 2>&1 || true
	return 0
}
