---
name: selecta-statusline
description: Installs, removes or inspects the selecta status line, which shows the currently playing track under the Claude Code input box. Use when the user asks to show what is playing in their status line, to turn that display on or off, or asks why it is not showing. Editing the user's global settings.json requires their explicit consent in the conversation first, so this skill is a strict two-step - run once to preview, ask, wait, then run again to apply. Do NOT use to play or control music (that is selecta), to report listening history (that is selecta-crate), or to check dependencies (that is selecta-doctor).
argument-hint: "statusline on | off | status"
license: MIT
compatibility: Needs jq to merge settings safely. macOS and Linux.
---

# selecta-statusline

This is the only selecta skill that writes to the user's global
`~/.claude/settings.json`. Treat that as the constraint it is.

**Never edit `settings.json` with Write, Edit, `jq`, `sed` or a shell
redirect.** The CLI backs the file up, merges rather than overwrites, preserves
an existing status line by wrapping it, and can undo itself. A hand-rolled edit
does none of that and can destroy configuration that is not recoverable.

## The protocol

Exactly these five steps, in this order:

1. Run it with **no flag**:
   ```
   "${CLAUDE_PLUGIN_ROOT}"/bin/selecta statusline on
   ```
   This is a dry run. It writes nothing.
2. **Exit code 7 is the expected, correct result.** It means "consent needed,
   nothing changed". It is not an error and must not be reported as one, worked
   around, or retried with a flag.
3. Show the user its output **verbatim** — the exact JSON block that would be
   added, and both disclosures.
4. Ask, in your own message, whether to add it. Then **stop and wait**. Do not
   continue in the same turn.
5. Only after they say yes:
   ```
   "${CLAUDE_PLUGIN_ROOT}"/bin/selecta statusline on --user-confirmed
   ```

Never pass `--user-confirmed` on the first call. Its verbosity is deliberate:
appending it has to be a decision, and it has to be obvious in a transcript that
one was made.

If the user says no, say so and stop. Do not offer a manual edit as a
workaround.

## Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | Installed | Tell them it will appear on the next refresh |
| 7 | Consent needed, nothing written | Step 3 above. Expected on the first call |
| 3 | selecta refused to write | Relay the paste block it printed |

Exit 3 happens when the file has comments (`jsonc`), is unparseable, or is
read-only. selecta will not rewrite a file it cannot round-trip safely, because
that would silently delete the user's comments. In that case it prints a block
for the user to paste themselves. **That is the correct outcome, not a failure.**

## What it shows

The line shows whatever is playing, including Spotify, Apple Music or an MPRIS
player the user is running independently. It needs no music player installed to
be useful, which is worth saying when someone assumes it only works with
selecta's own radio.

It renders right-aligned under the input box, adapts to terminal width, and
prints nothing at all when nothing is playing.

## Turning it off

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta statusline off
```

Removes the key entirely, or restores a pre-existing status line exactly as it
was. `statusline status` reports the current state without changing anything and
needs no consent.

## Should trigger

- "show what's playing in my status line"
- "add selecta to my status line" · "turn the status line on"
- "remove the music from my status line"
- "why isn't the track showing in the status bar?"

## Should NOT trigger

- "play something" · "pause" — that is **selecta**
- "what does this repo sound like?" — that is **selecta-crate**
- "check my setup" · "selecta is broken" — that is **selecta-doctor**

## Side effects

Writes `~/.claude/settings.json`, but **only** after `--user-confirmed`. Copies
a launcher to `~/.claude/selecta/statusline.sh`. Backs the settings file up
before every write.

## Reference

- `references/statusline.md` — the exact block, merge behaviour, wrap mode, and
  how to undo by hand. Read before explaining any of those.
