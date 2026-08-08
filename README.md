<h1 align="center">selecta</h1>
<p align="center"><em>Background music for your coding sessions, in the terminal.<br>Every repository builds its own soundtrack.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Claude%20Code-plugin-blueviolet" alt="Claude Code plugin">
  <img src="https://img.shields.io/badge/radio-no%20key%20needed-brightgreen" alt="Radio needs no key">
</p>

<!-- demo.gif goes here: /selecta play amapiano → status line lights up → /selecta crate -->

```
/selecta play ambient                    # radio, no window
/selecta play sponono by kabza de small  # YouTube, opens a small player

                          ♪ Kabza De Small — Sponono · YouTube · demo-api
```

Selecta runs the set. Every repo gets its own.

## Why

You already play music while you code. What you cannot do is ask a repository
what it sounded like.

Selecta keeps a **crate** per repository: the stations you played, weighted by
how long you listened, and every track stamped with the branch and commit that
were checked out while it played. Come back to a project after a month and
`selecta resume` puts it back on.

```
  demo-api   13h 24m · 902 tracks · since 12 Jun

  Groove Salad         ████████░░  22 plays
  Drone Zone           ███░░░░░░░   9 plays
  Mission Control      ██░░░░░░░░   4 plays

  On repeat        Alex Cortiz — Barista Breaks  (14×)
  First track      Tycho — Awake, on 12 Jun while you wrote a1b2c3d

  selecta resume  →  Groove Salad
```

That last line is the whole idea. Your listening history becomes an index into
your own work.

## Why not `/radio`?

Claude Code ships `/radio`, which opens Anthropic's Claude FM lo-fi stream **in
a browser tab**. It is good, and you should use it.

Selecta is a different shape:

| | `/radio` | selecta |
|---|---|---|
| Where it plays | browser tab | your terminal |
| Over SSH or in tmux | no | yes |
| Genre and mood control | no | 46 stations plus thousands more |
| Volume, pause, skip | browser | `selecta vol 40` |
| Status line | no | yes |
| Remembers per repository | no | **yes** |

## Quick start

```
/plugin marketplace add azandabot/selecta
/plugin install selecta@azandabot-selecta
/selecta play ambient
```

Then, optionally:

```
/selecta statusline on
```

## Install

**Plugin marketplace (recommended)**

```
/plugin marketplace add azandabot/selecta
/plugin install selecta@azandabot-selecta
```

**Manually**

```bash
git clone https://github.com/azandabot/selecta
cp -r selecta/skills/selecta ~/.claude/skills/
```

### Prerequisites

| | Needed for | Install |
|---|---|---|
| `mpv` | playback, volume, pause, track titles | `brew install mpv` / `apt-get install mpv` |
| `jq` | everything | `brew install jq` / `apt-get install jq` |
| `ffplay` | fallback if mpv is absent; limited control | part of ffmpeg |
| `python3` | the YouTube player window only | preinstalled on macOS; `apt-get install python3` |
| YouTube API key | playing a named song. Radio does not need it | free, see below |

`selecta doctor` checks all of this and prints the exact command for your
platform. It will not run a package manager for you.

## Commands

| Command | What it does |
|---|---|
| `/selecta` | What is playing, plus this repo's crate |
| `/selecta play <mood>` | Resolve and play. Routes to radio or YouTube automatically |
| `/selecta play --radio` · `--yt` | Force a backend |
| `/selecta play` | Resume what this repo sounds like |
| `/selecta resume` | This repo's top-ranked source |
| `/selecta pause` · `go` | Pause, unpause |
| `/selecta next` | Next source in the rotation |
| `/selecta stop` | Stop, keep state |
| `/selecta vol 40` | Also `+10`, `-10`, `mute`, `unmute` |
| `/selecta crate` | What this repo sounds like |
| `/selecta history` | Tracks grouped by the commit they scored |
| `/selecta pin \| ban \| forget` | Curate the crate |
| `/selecta stations [query]` | Browse without playing |
| `/selecta statusline on\|off` | Now playing in your status line |
| `/selecta doctor` | Dependency and health check |
| `/selecta export <path>` | Write the crate as `.m3u8` + `.json` |
| `/selecta uninstall [--purge]` | Remove cleanly |

Ask in your own words too. "Play me something with a log drum" resolves to
amapiano and afro house on radio; "play sponono by kabza de small" finds that
exact track on YouTube.

## Status line

```
/selecta statusline on
```

Shows the current track at the bottom of your session:

```
♪ Kabza De Small — Sponono · Groove Salad · demo-api
```

It renders at three widths depending on your terminal, and disappears when
nothing is playing.

Two things it tells you before writing anything:

- A plugin **cannot** ship a status line, so this edits your global
  `~/.claude/settings.json`. It shows the exact JSON, backs the file up, and
  asks first.
- **Setting a status line hides most of the built-in footer key hints.**

If you already have a status line, yours is kept and runs first; selecta adds a
second row. `selecta statusline off` restores everything.

## Where the music comes from

| Source | Key needed | What it gives |
|---|---|---|
| [YouTube](https://www.youtube.com) | free, yours | any specific song by name. Opens a small visible player |
| [SomaFM](https://somafm.com) | no | 46 curated, ad-free, listener-supported stations |
| [radio-browser](https://www.radio-browser.info) | no | thousands of community-indexed stations |
| [Jamendo](https://www.jamendo.com) | free, optional | Creative Commons tracks, real text search |
| [Internet Archive netlabels](https://archive.org/details/netlabels) | no | Creative Commons albums |

**Nothing is downloaded.** Streams are played, never stored. Radio needs no
account and no key at all; only YouTube does.

### About the YouTube window

YouTube's Developer Policies forbid playing from "a player that is not
displayed", so YouTube mode opens a small 480×380 window and keeps it visible.
That is not configurable. If you want music with no window, radio mode is the
windowless option, and it stays the default.

A related limitation worth knowing: **a lot of major-label music disallows
embedded playback.** selecta filters unembeddable results at search time,
validates them again in bulk, and auto-skips any that still fail, so you
usually get the song, sometimes as a re-upload or lyric video rather than the
official upload.

SomaFM is listener-supported. If you use it, [support
them](https://somafm.com/support/).

## How it works

One long-lived supervisor owns `mpv` and is the only writer of durable state.
The CLI is a thin client that talks to mpv's IPC socket. The status line reads a
single pre-rendered file: no JSON parsing, no `git`, no subprocesses, so a two
second refresh stays free.

Resolution is tiered, and the first two tiers work offline:

```
0  exact station id, title or your own alias      offline
1  mood vocabulary and catalogue scoring          offline (46-station seed baked in)
2  radio-browser                                  keyless
3  Jamendo                                        free key, optional
4  Internet Archive netlabels                     keyless
```

Crates live in `~/.claude/selecta/`, keyed by repository. ssh and https remotes
collapse to one key, worktrees share the parent's crate, and a fork whose remote
later points upstream carries its history across.

**Nothing is ever written into your repository.** `selecta export` needs an
explicit path and refuses to write inside the working tree.

## Limitations

- **YouTube mode always shows a window.** Required by YouTube's policies, not
  a design choice.
- **Some official uploads refuse embedded playback.** selecta skips to the next
  candidate automatically, which can mean a re-upload instead of the official
  video.
- **YouTube search is capped at 100 queries a day** on your own key, resetting
  midnight Pacific. Results are cached for 7 days, so repeats are free.
- **Live radio cannot skip a track.** `selecta next` changes station, and says
  so rather than pretending.
- **Track titles depend on the station.** Many streams send them; some send only
  the station name. Selecta shows what it is given, never a guess.
- **Music stops when your session ends.** Deliberate: an orphaned audio process
  you cannot find is worse than pressing resume.
- **One player per machine**, not per session. A second session shows the same
  track.
- **macOS and Linux.** Windows and WSL are not tested yet.
- **Some stations play a short ident** before the music. That is SomaFM, not a
  bug.
- **Amapiano, classical and a few other genres have no SomaFM station** and
  route to radio-browser. Quality varies more there.

## Tests

```
./tests/run.sh unit          # 192 assertions, offline, deterministic
./tests/run.sh integration   # real mpv with --ao=null, no audio device needed
./tests/run.sh contract      # live upstreams; nightly in CI, never on PRs
```

Integration tests do the real network fetch, demux and ICY parse with audio
output disabled, so one test covers URL resolution, stream health, IPC, metadata
events and state writing.

The status line has its own adversarial suite: missing, empty, truncated,
corrupt, directory-shaped state, 4-byte UTF-8, glob characters in track titles
and a non-numeric `$COLUMNS`. Every case must exit 0, because a fault in selecta
must never break your status line.

`evals/` holds seven behavioural cases for the skill itself, led by
`no-autostart`: music must never start unless you asked for it.

## Contributing

Issues and pull requests welcome. `./tests/run.sh` and
`shellcheck -x -s sh` should both be clean.

## License

MIT
