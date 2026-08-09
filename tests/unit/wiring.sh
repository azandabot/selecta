#!/bin/sh
# Every function a binary calls has to be defined somewhere it actually sources.
#
# selecta-youtube gained a call to selecta_np_pause_others without gaining the
# source line for the library that defines it. Under `set -eu` that is exit 127
# with "command not found", so `selecta-youtube play` was completely broken —
# and every unit test still passed, because none of them ran the binary far
# enough to reach the call.
#
# Static, deliberately: reaching that line for real needs an API key, a network
# round trip and a browser window. The invariant is genuinely structural.
set -u

# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok wiring suite skipped, no python3\n' >>"$T_RESULTS"
	exit 0
fi

PLUGINS=$(cd -- "$SELECTA_ROOT/.." && pwd -P)

unresolved() {
	python3 - "$PLUGINS" "$1" <<'PY'
import pathlib, re, sys

plugins, target = pathlib.Path(sys.argv[1]), sys.argv[2]
binary = plugins / target
src = binary.read_text()

# Roots a binary can source from: its own plugin, and selecta's libraries for
# the companion plugin, which uses them rather than copying them.
roots = {
    "SELECTA_ROOT": plugins / "selecta",
    "SELECTA_YT_ROOT": plugins / "selecta-youtube",
}
if binary.parts[-3] == "selecta":
    roots["SELECTA_ROOT"] = plugins / "selecta"

text = src
for m in re.finditer(r'^\.\s+"\$(\w+)(/[^"]+)"', src, re.M):
    var, rel = m.group(1), m.group(2).lstrip("/")
    root = roots.get(var)
    if root is None:
        continue
    f = root / rel
    if f.exists():
        text += "\n" + f.read_text()

defined = set(re.findall(r"^([a-zA-Z_][a-zA-Z0-9_]*)\s*\(\)", text, re.M))
# Shell builtins and external commands are not our problem; only our own
# namespace is, and it is the one a missing source line breaks.
called = set(re.findall(r"(?:^|[\s;(`$])((?:selecta_|yt_|repo_|sup_)[a-z0-9_]+)", src))
print("\n".join(sorted(called - defined)))
PY
}

t_eq "every function bin/selecta calls is defined" "" \
	"$(unresolved selecta/bin/selecta)"
t_eq "every function bin/selecta-youtube calls is defined" "" \
	"$(unresolved selecta-youtube/bin/selecta-youtube)"
t_eq "every function the supervisor calls is defined" "" \
	"$(unresolved selecta/libexec/selecta-supervisor)"

# The check is only worth anything if it can fail. A call to a function that
# exists in a library nobody sourced is precisely the bug it exists for.
t_eq "the check notices an unsourced library" "selecta_np_capability
selecta_np_pause_others" "$(
	_tmp=$SELECTA_ROOT/bin/.wiring-probe
	# shellcheck disable=SC2016
	sed 's|^\. "\$SELECTA_ROOT/lib/nowplaying\.sh"$|:|' \
		"$SELECTA_ROOT/bin/selecta" >"$_tmp"
	unresolved selecta/bin/.wiring-probe
	rm -f "$_tmp"
)"
