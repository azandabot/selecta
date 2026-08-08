#!/bin/sh
# Skill and command manifests.
#
# A skill whose frontmatter fails to parse loads with *empty metadata*: no
# name, no description, so the model can never route to it and nothing says
# why. One unquoted colon in a description did exactly that and the skill still
# looked completely normal on disk. These are structural invariants, so they are
# checked structurally.
set -u

# shellcheck source=tests/lib.sh
. "$SELECTA_TESTS/lib.sh"

if ! command -v python3 >/dev/null 2>&1; then
	printf 'ok skill manifest suite skipped, no python3\n' >>"$T_RESULTS"
	exit 0
fi

PLUGINS=$(cd -- "$SELECTA_ROOT/.." && pwd -P)

report() {
	python3 - "$PLUGINS" "$1" <<'PY'
import pathlib, re, sys

root, want = pathlib.Path(sys.argv[1]), sys.argv[2]
try:
    import yaml
except ImportError:
    yaml = None
out = []
for f in sorted(root.glob("*/skills/*/SKILL.md")):
    rel = f.relative_to(root)
    m = re.match(r"^---\n(.*?)\n---\n", f.read_text(), re.S)
    if not m:
        out.append(f"{rel}\tnofrontmatter\t0")
        continue
    fm, body = m.group(1), f.read_text()[m.end():]
    if yaml is not None:
        try:
            d = yaml.safe_load(fm)
        except Exception:
            out.append(f"{rel}\tunparseable\t0")
            continue
        if not isinstance(d, dict):
            out.append(f"{rel}\tunparseable\t0")
            continue
    else:
        # No pyyaml: catch the failure mode that actually happened, an
        # unquoted scalar containing ": ".
        d, broken = {}, False
        for line in fm.split("\n"):
            k, _, v = line.partition(": ")
            if not k or k.startswith(" ") or k.startswith("#"):
                continue
            d[k.strip()] = v.strip()
            if ": " in v and not (v.startswith('"') or v.startswith("'")):
                broken = True
        if broken:
            out.append(f"{rel}\tunparseable\t0")
            continue
    name = str(d.get("name", ""))
    desc = str(d.get("description", ""))
    if want == "names":
        out.append(name)
    elif want == "bad":
        why = []
        if not name:
            why.append("noname")
        if name and name != f.parent.name:
            why.append("namemismatch")
        if not desc:
            why.append("nodesc")
        if len(desc) > 1024:
            why.append("desctoolong")
        if len(body.split()) > 5000:
            why.append("bodytoolong")
        if "disable-model-invocation" in fm:
            why.append("modeldisabled")
        if why:
            out.append(f"{rel}\t{','.join(why)}")
    elif want == "nocontract":
        # Every skill has to say what it does not do and what it touches, or
        # the model has nothing to route away from.
        if "Should NOT trigger" not in body or "Side effects" not in body:
            out.append(str(rel))
    elif want == "refs":
        for ref in re.findall(r"`(references/[^`]+)`", body):
            if not (f.parent / ref).exists():
                out.append(f"{rel} -> {ref}")
print("\n".join(out))
PY
}

t_eq "every SKILL.md parses and stays within limits" "" "$(report bad)"
t_eq "every skill states its negative cases and side effects" "" "$(report nocontract)"
t_eq "every referenced reference file exists" "" "$(report refs)"

NAMES=$(report names | sort)
t_eq "all five skills are present" \
	"selecta selecta-crate selecta-doctor selecta-statusline selecta-youtube" \
	"$(printf '%s' "$NAMES" | tr '\n' ' ' | sed 's/ $//')"
t_eq "no two skills share a name" "$(printf '%s\n' "$NAMES" | grep -c .)" \
	"$(printf '%s\n' "$NAMES" | sort -u | grep -c .)"

# Exactly one skill may edit global settings, and exactly two may start audio.
# That split is the whole reason the surface was divided this way.
t_eq "only selecta-statusline documents writing settings.json" "selecta-statusline" \
	"$(grep -l 'user-confirmed' "$PLUGINS"/*/skills/*/SKILL.md | while read -r f; do
		basename "$(dirname "$f")"
	done | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "only selecta and selecta-youtube announce that they start audio" \
	"selecta selecta-youtube" \
	"$(grep -l 'This skill starts audio' "$PLUGINS"/*/skills/*/SKILL.md | while read -r f; do
		basename "$(dirname "$f")"
	done | sort | tr '\n' ' ' | sed 's/ $//')"

# Commands are the fallback for when the router does not fire, so a broken one
# is invisible until someone types it.
t_eq "every command file has a description and a prompt" "" \
	"$(python3 - "$PLUGINS" <<'PY'
import pathlib, sys, re
bad = []
for f in sorted(pathlib.Path(sys.argv[1]).glob("*/commands/*.toml")):
    t = f.read_text()
    for key in ("description", "prompt"):
        if not re.search(rf"^{key}\s*=", t, re.M):
            bad.append(f"{f.name}:{key}")
print("\n".join(bad))
PY
	)"
# Evals are graded by reading, not by running, so the only thing that can be
# checked here is that each case is complete. A prompt with no grader states no
# expectation, and a grader with no prompt grades nothing.
t_eq "every eval has a prompt and at least one grader" "" "$(
	for d in "$(dirname "$PLUGINS")"/evals/*/; do
		[ -d "$d" ] || continue
		[ -s "$d/prompt.md" ] || printf '%s: no prompt\n' "$(basename "$d")"
		[ -n "$(find "$d/graders" -name '*.md' 2>/dev/null)" ] ||
			printf '%s: no grader\n' "$(basename "$d")"
	done
)"
t_eq "the eval index lists every case" "" "$(
	_idx="$(dirname "$PLUGINS")"/evals/README.md
	for d in "$(dirname "$PLUGINS")"/evals/*/; do
		[ -d "$d" ] || continue
		grep -q "\`$(basename "$d")\`" "$_idx" || basename "$d"
	done
)"

t_eq "every plugin ships its commands" "2" \
	"$(find "$PLUGINS" -maxdepth 2 -name commands -type d | wc -l | tr -d ' ')"
