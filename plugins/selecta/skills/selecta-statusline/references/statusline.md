# Status line

Read this before running `selecta statusline on`, and before explaining to
anyone what it will do to their settings.

## Why it needs permission

A plugin cannot ship the main status line. Plugin `settings.json` supports only
the `agent` and `subagentStatusLine` keys, so the entry has to go into the
user's own `~/.claude/settings.json`. That is a global file that has nothing to
do with the current project, which is why `selecta` asks before touching it,
backs it up first, and refuses outright in the cases below.

## What gets added

```json
  "statusLine": {"type":"command","command":"~/.claude/selecta/statusline.sh","refreshInterval":2,"padding":0}
```

`refreshInterval` is **seconds**, minimum 1. Two is the default: a track changes
every few minutes, so two seconds reads as live while halving the process
spawns of the minimum.

The command points at `~/.claude/selecta/statusline.sh`, a copy of the launcher,
**not** at a path inside the plugin. Plugins install under a versioned directory
(`.../selecta/0.1.0/`), so anything pointing into the plugin breaks on the next
update. The copy survives updates, uninstalls and marketplace re-adds.

## Disclose these two things

1. **Setting a status line hides most of the built-in footer key hints.** People
   notice, and they blame whatever they installed last.
2. **It edits global settings, not the repository.**

`selecta statusline on` prints both itself. Let it ask its own question rather
than answering for the user.

## The seven cases

| Settings file | What happens |
|---|---|
| missing | created containing only `statusLine` |
| empty | same |
| valid JSON, no status line | merged, other keys untouched |
| already ours | refreshed if the interval drifted |
| **someone else's status line** | **wrap mode**, theirs is kept |
| **JSONC (has comments)** | **refuses**, prints a block to paste |
| unparseable or read-only | refuses, prints a block to paste |

A symlinked settings file is resolved and the target is edited, so the symlink
survives.

### Why JSONC is refused

The host parses JSONC; `jq` does not. Rewriting a comment-bearing file with `jq`
would silently delete the user's comments. Refusing and printing the block is
the correct outcome, not a failure. Relay it as such.

## Wrap mode

When a status line already exists, theirs is preserved verbatim and runs
**first**, with selecta's line underneath:

```
their existing line
♪ Kabza De Small — Sponono · Groove Salad · selecta
```

`selecta statusline off` restores their original object exactly.

## What it renders

Three width buckets, chosen from `$COLUMNS`:

| Width | Shows |
|---|---|
| < 80 | `♪ Artist — Title` |
| 80–119 | `♪ Artist — Title · Station` |
| >= 120 | `♪ Artist — Title · Station · repo` |

Live radio often provides no track metadata, in which case the station name is
shown alone. Paused is `❚❚`, buffering is `♪·`.

When nothing is playing the line disappears.

## Guarantees

The launcher forks nothing in the common path: no `jq`, no `git`, no
subprocesses. It reads one pre-rendered file the supervisor wrote. Every code
path exits 0, including missing, empty, truncated, corrupt and
directory-shaped state, so a selecta fault can never break someone's status
line.

## Removing it

```
selecta statusline off
```

Run this **before** `claude plugin uninstall selecta`. Forgetting is not fatal
— the launcher is self-contained and degrades to silence — but the settings
entry stays until removed.
