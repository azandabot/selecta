---
name: selecta
description: Plays and controls background music from internet radio, and shows what is playing in the status line. Use when the user asks in their own words to put music on, play a mood or genre ("play something calm", "amapiano", "lo-fi for focus"), or to pause, unpause, skip, stop or change the volume of music. Also use when they ask what is currently playing. Do NOT use to install the status line (that is selecta-statusline), to report what a repository has been listening to (that is selecta-crate), to diagnose a failure (that is selecta-doctor), or to play one specific named song (that is selecta-youtube). This skill starts audio, so only run it when the user actually asked for music.
argument-hint: "play <mood> | pause | go | next | stop | vol <n> | stations"
license: MIT
compatibility: Radio playback needs mpv and jq. Reading Spotify, Apple Music or an MPRIS player needs neither. macOS and Linux.
---

# selecta

**This skill starts audio.** Run it only when the user asked for music in their
own words. Setting up an environment, starting a long task, or the user saying
"I'm about to focus for two hours" or "this refactor is going to be boring" are
**not** requests for music. Say nothing about music in those cases.

Everything runs through one executable:

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta <subcommand> [args]
```

Run it with Bash and report what it prints. Its output is written to be read
back to the user almost verbatim.

## What this actually is

The status line comes first. selecta shows what is playing **whatever is
playing it** — Spotify, Apple Music, or any MPRIS player on Linux — and needs
nothing installed to do that. Its own radio playback is a bonus for people who
want music without leaving the terminal.

So `selecta` with no arguments is a question, not a command. It never starts
anything.

## The one rule that matters

**Never construct a stream URL, station id or playlist entry yourself.**

Resolution belongs to `selecta resolve`, which owns the catalogues and the
provider APIs. A URL composed from memory will be wrong, dead, or an invention.
If `resolve` returns nothing, say so and offer `selecta stations`.

## Playing

```
selecta play amapiano                    # a genre
selecta play something calm for reading  # a mood, in the user's words
selecta play                             # resume what this repo sounds like
```

Pass the user's words through unchanged. The resolver is better at their phrasing
than a cleaned-up version of it.

Radio opens no window and needs no account. If the user names **one specific
recording** ("play Sponono by Kabza De Small"), radio cannot pick that; selecta
routes to the selecta-youtube plugin if it is installed, and prints the install
line if it is not. Relay that line; do not install anything.

## When a request has no obvious match

This is the case worth handling well.

```
selecta resolve --json "<the user's words>"
```

- `status: "ok"` — `selecta play` will land it. Just play it.
- `status: "none"` — nothing matched. Say so, offer `selecta stations`. Do not
  guess.
- `status: "ambiguous"` — no confident station, but `hint_tags` carries
  vocabulary the networked catalogues understand. **Rewrite the request into
  catalogue vocabulary and resolve again** rather than giving up or settling for
  a poor match.

Rewriting means translating what the user said into terms a music directory
would index. "Something with a log drum" is amapiano and afro house. "Aura
farming music" is closer to phonk, drift or hard techno. "Music for staring at a
wall" is drone or dark ambient. `references/stations.md` has the catalogue's own
vocabulary. Then:

```
selecta resolve --json --tags "amapiano,afro house,deep house" "log drum"
```

Still nothing? Offer three real candidates from `selecta stations`. Never invent
a fourth.

## Control

```
selecta            # what is playing
selecta pause      # and: selecta go
selecta next       # next source in this repo's rotation
selecta stop
selecta vol 40     # also +10, -10, mute, unmute
```

These reach whichever backend is actually playing, including the YouTube window.

`next` changes station, not track. Live radio has no track skip and selecta says
so in its own output; do not describe it as skipping a song.

If the user is playing music in Spotify or Apple Music, `selecta` reports it but
`pause` and `vol` do not control it. Say that plainly rather than pretending the
command worked.

## Should trigger

- "put some music on", "play something", "music please"
- "play amapiano" · "something calm for reading" · "lo-fi"
- "pause the music" · "turn it down" · "next station" · "stop"
- "what's playing?" · "what am I listening to?"

## Should NOT trigger

- "I'm about to focus for two hours" — an observation, not a request
- "this refactor is going to be boring" — still not a request
- "set up my dev environment" — nothing to do with music
- "add the music player to my status line" — that is **selecta-statusline**
- "what has this repo been listening to?" — that is **selecta-crate**
- "the music stopped working" — that is **selecta-doctor**
- "play Sponono by Kabza De Small" — one named recording, **selecta-youtube**

## Side effects

Starts and stops an mpv process owned by the user. Writes only under
`~/.claude/selecta/`. **Never writes into the user's repository** and never
edits `settings.json`.

## Reference

- `references/stations.md` — the SomaFM catalogue, its genres and the mood
  vocabulary. Read this when rewriting an ambiguous request.
