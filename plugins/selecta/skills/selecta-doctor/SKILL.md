---
name: selecta-doctor
description: Diagnoses selecta - which dependencies are present, which player can be read, whether anything is running, whether the status line is installed, and whether state has gone stale. Use when the user says the music is not playing, the status line is blank or not updating, a command failed, or asks to check their selecta setup. Do NOT use to play or control music (that is selecta), to report listening history (that is selecta-crate), or to install the status line (that is selecta-statusline). This is a read-only check; it never starts audio and installs nothing.
argument-hint: "doctor"
license: MIT
compatibility: Runs everywhere; reports what is missing rather than requiring it.
---

# selecta-doctor

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta doctor
```

Read-only. It never starts audio and never installs anything.

## The rule about installing

When doctor reports a missing dependency it prints the exact install command for
the platform. **Show the user that command. Do not run it.** Never run
`brew`, `apt`, `dnf`, `pacman`, `npm` or any other package manager on the user's
behalf, even if they seem likely to agree. Installing software is their call.

## Reading the output

Each row is one fact. Report the failing rows, not all of them.

| Row | Meaning when it is bad |
|---|---|
| `jq` | Missing. Nearly everything degrades; say so first |
| `mpv` | Missing. Radio cannot play. Reading Spotify or Apple Music still works |
| `ipc` | No unix-socket transport found. Radio playback cannot be controlled |
| `players` | Which external player can be read, or why not |
| `state` | `STALE` means the state file claims playback with nothing running |
| `status` | `foreign`, `jsonc`, `readonly` — see selecta-statusline |
| `youtube` | Not installed is normal and optional |

`players ... denied` on macOS means the Automation permission was refused. It is
re-enabled in System Settings › Privacy & Security › Automation, not by
reinstalling anything. selecta stops probing after a denial rather than
prompting on a loop.

`state STALE` is not damage. It means a player died without cleaning up.
`selecta stop` clears it.

## When doctor itself is the problem

doctor is written to survive its own diagnosis: with `jq` missing it still
reports that `jq` is missing rather than dying on a `jq` call. If it exits
non-zero, exit 4 means a required dependency is absent, and the rows above it
say which.

## Should trigger

- "the music isn't playing"
- "selecta is broken" · "nothing happens when I run it"
- "the status line is blank" · "the track isn't updating"
- "check my selecta setup"

## Should NOT trigger

- "play something" — that is **selecta**
- "turn the status line on" — that is **selecta-statusline**
- "what have I been listening to?" — that is **selecta-crate**

## Side effects

None. Reads dependencies, config and state. Starts nothing, installs nothing,
writes nothing.

## Reference

- `references/troubleshooting.md` — every known failure mode and its remedy.
  Read this before speculating about a cause.
