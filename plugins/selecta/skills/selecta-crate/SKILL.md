---
name: selecta-crate
description: Reports what a git repository has been listening to - its stations, its total listening time, and its tracks grouped by the commit that was checked out while each one played. Use when the user asks what this repo sounds like, what they were listening to while working on something, for their listening history, or where the crate file lives. Do NOT use to start, stop or change music (that is selecta), to install the status line (that is selecta-statusline), or to diagnose a failure (that is selecta-doctor). This is a read-only report; it never starts audio and changes nothing.
argument-hint: "crate | crate --history [n] | crate --path"
license: MIT
compatibility: Needs jq. Reads only; no network, no player.
---

# selecta-crate

A read-only report. **It never starts music and writes nothing.** If the user
wanted music playing, that is the `selecta` skill instead.

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta crate              # what this repo sounds like
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta crate --history 20 # tracks, by commit
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta crate --path       # where the file lives
```

Run it in the user's current directory. The repository is detected from there,
so `cd` matters and a different repo is a different crate.

## What a crate is

Every track selecta plays is stamped with the branch and the commit that were
checked out at the time. So `--history` is a record of the work, not a playlist.
"What was I listening to while I wrote the auth migration?" is answerable, and
that is the whole idea.

Crates are keyed by the repository's remote, so a clone on another machine and a
fork of the same upstream share one crate. Repos with no remote are keyed by
path.

## Output grammar

The command formats itself. **Relay it unmodified** — do not re-rank, re-word,
summarise the bars into prose, or convert the durations. It emits, in order:

1. A heading line naming the repository.
2. One line per source: title, a bar, listening time. Ordered by time listened,
   longest first.
3. A totals line: sources, tracks, total time.
4. A `selecta resume →` line naming what would play next.
5. A link to the project.

`--history` instead emits commit headers (`abc1234 on main`) with the tracks
that played under each, newest first.

An empty crate prints one line saying so. Relay that too; do not offer to
populate it by playing something unless the user asks.

## Should trigger

- "what does this repo sound like?"
- "what have I been listening to on this project?"
- "what was playing while I worked on the parser?"
- "show me my listening history"
- "where is the crate file?"

## Should NOT trigger

- "play something" · "put music on" — that is **selecta**
- "resume the music" — that starts audio, so it is **selecta**
- "add it to my status line" — that is **selecta-statusline**
- "why isn't the music playing?" — that is **selecta-doctor**

## Side effects

None. Reads `~/.claude/selecta/soundtracks/`. Never touches the user's
repository, never starts a process, never edits settings.
