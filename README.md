<h1 align="center">selecta</h1>
<p align="center"><em>What you're playing, in your Claude Code status line.<br>Whatever you're playing it with.</em></p>

<p align="center">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue" alt="Platform">
  <img src="https://img.shields.io/badge/Claude%20Code-plugin-blueviolet" alt="Claude Code plugin">
  <img src="https://img.shields.io/badge/setup-none-brightgreen" alt="No setup required">
</p>

<!-- demo.gif goes here: Spotify playing → /selecta statusline on → the line appears -->

```
                                       ♪ Sault — Wildfires · Spotify · selecta
```

Put Spotify on. Install selecta. That line appears under your input box and
stays current.

No key, no config, no dependencies, nothing to run. It reads the music app you
already have open — Spotify, Apple Music, or anything speaking MPRIS on Linux.

Then, if you want music without leaving the terminal, it can play that too.

## Why

You already play music while you code. Two things you can't do: see what's on
without leaving the keyboard, and ask a repository what it sounded like.

selecta does the first with nothing installed. For the second it keeps a
**crate** per repository — the stations you played, weighted by how long you
listened, every track stamped with the branch and commit that were checked out
while it played.

```
  demo-api   13h 24m · 902 tracks · since 12 Jun

  Groove Salad         ████████░░  6h 12m
  Drone Zone           ███░░░░░░░  2h 30m
  Mission Control      ██░░░░░░░░  1h 04m

  On repeat        Alex Cortiz — Barista Breaks  (14×)
  First track      Tycho — Awake, on 12 Jun while you wrote a1b2c3d

  selecta resume  →  Groove Salad
```

Come back to a project after a month and `selecta resume` puts it back on.

## Quick start

```
/plugin marketplace add azandabot/selecta
/plugin install selecta@azandabot-selecta
/selecta:statusline on
```

That's the whole thing. It asks before touching your settings, and it shows you
the exact JSON first.

Want it to play music too? `brew install mpv jq`, then:

```
/selecta:selecta play ambient
```

## What works with what

The point of the split: the status line costs you nothing, and everything below
it is opt-in.

| You want | You need | Opens a window |
|---|---|---|
| See what Spotify / Apple Music is playing | nothing | no |
| Same, on Linux | `playerctl` | no |
| Play radio from the terminal | `mpv`, `jq` | no |
| Per-repo crates and history | `jq` | no |
| Play one specific named song | the `selecta-youtube` plugin, a free API key | **yes** |

`selecta doctor` checks every row and prints the exact install command for your
platform. It will not run a package manager for you.

## Two plugins

**`selecta`** is the status line, radio, and the crate. No key, no window.

**`selecta-youtube`** adds "play this exact song by this exact artist". It needs
a free Google API key and opens a small visible browser window, because
YouTube's Developer Policies forbid playing from a player that isn't displayed.
Most people don't want that, so it's a separate install:

```
/plugin install selecta-youtube@azandabot-selecta
```

Once it's installed, `selecta play "kabza de small - sponono"` routes to it on
its own. Without it, selecta says so and plays radio instead.

## Commands

Ask in your own words — "put something calm on", "what's playing?", "what has
this repo been listening to?" — or type them:

| Command | What it does |
|---|---|
| `/selecta:selecta` | What's playing |
| `/selecta:selecta play <mood>` | Resolve and play on radio |
| `/selecta:selecta play` | Resume what this repo sounds like |
| `/selecta:selecta pause` · `go` · `next` · `stop` | Control whatever is playing |
| `/selecta:selecta vol 40` | Also `+10`, `-10`, `mute`, `unmute` |
| `/selecta:crate` | What this repo sounds like |
| `/selecta:crate --history [n]` | Tracks grouped by the commit they scored |
| `/selecta:statusline on\|off\|status` | The status line |
| `/selecta:doctor` | Dependency and health check |
| `/selecta-youtube:youtube <track>` | One named song, in a window |

`selecta uninstall [--purge]` removes it cleanly.

## The status line

```
/selecta:statusline on
```

Renders right-aligned under your input box, at three widths depending on your
terminal, and disappears when nothing is playing.

Two things it tells you before writing anything:

- A plugin **cannot** ship a status line, so this edits your global
  `~/.claude/settings.json`. It shows the exact JSON, backs the file up, and
  asks first. Nothing is written until you say yes.
- **Setting a status line hides most of the built-in footer key hints.**

If you already have a status line, yours is kept and runs first; selecta adds a
second row. `statusline off` restores everything exactly as it was.

It forks nothing on the common path: no `jq`, no `git`, no subprocesses. It
reads one pre-rendered file, so a two-second refresh stays free. Every failure
path exits 0 — a fault in selecta must never break your status line.

### Reading other players

| Platform | Reads | How |
|---|---|---|
| macOS | Spotify, Apple Music | AppleScript, only when the app is already running |
| Linux | anything MPRIS | `playerctl` |

On macOS the first probe triggers an Automation permission prompt. Deny it and
selecta stops asking, permanently, and `doctor` tells you how to re-enable it.
It never launches a music app that wasn't already open.

## Where the music comes from

| Source | Key | What it gives |
|---|---|---|
| [SomaFM](https://somafm.com) | no | 46 curated, ad-free, listener-supported stations |
| [radio-browser](https://www.radio-browser.info) | no | thousands of community-indexed stations |
| [YouTube](https://www.youtube.com) | free, yours | any specific song by name, via `selecta-youtube` |

**Nothing is downloaded.** Streams are played, never stored.

SomaFM is listener-supported. If you use it, [support
them](https://somafm.com/support/).

### The YouTube key

Only needed for `selecta-youtube`. Radio needs nothing.

**The order matters**, and getting it wrong is the single most common mistake: a
key created before the API is enabled will exist and return 403 on every search.

1. <https://console.cloud.google.com> → create or pick a project.
2. **Enable the API first.**
   <https://console.cloud.google.com/apis/library/youtube.googleapis.com> →
   check the project is right → **Enable** → wait for it to finish.
3. *Now* create the key. **APIs & Services → Credentials → Create credentials →
   API key**.
4. Optional: **Edit API key → API restrictions → YouTube Data API v3**.
5. `/selecta:selecta config youtube.api_key YOUR_KEY`

Then `selecta-youtube doctor`, which asks Google rather than reading your config
file:

```
  key      set, 100 of 100 searches left today
  api      YouTube Data API v3 reachable and enabled
```

If step 2 was skipped it says `api NOT ENABLED` instead of pretending the key is
fine.

### What costs quota

| Action | Cost |
|---|---|
| Playing, pausing, skipping, volume | **free** — playback uses no API |
| Replaying something already in your crate | **free** |
| Repeating a search from the last 7 days | **free** — cached |
| Radio, in any amount | **free** — no key involved |
| A **new** search phrase | 1 of 100 |

100 *distinct new searches* a day, not 100 plays. Resets midnight Pacific.

## How it works

One long-lived supervisor polls every two seconds: it owns `mpv` when radio is
playing, reads whatever external player is running when it isn't, and is the
only writer of durable state. The CLI is a thin client over mpv's IPC socket.

Resolution is tiered, and the first two work offline:

```
0  exact station id, title or your own alias      offline
1  mood vocabulary and catalogue scoring          offline (46-station seed baked in)
2  radio-browser                                  keyless
```

Crates live in `~/.claude/selecta/`, keyed by repository. ssh and https remotes
collapse to one key, worktrees share the parent's crate, and a fork whose remote
later points upstream carries its history across.

**Nothing is ever written into your repository.**

## Limitations

Stated plainly, because finding these out yourself is worse.

- **Over SSH, only the status line is useful.** `mpv` would play on the remote
  host, which has no speakers, and there's no local music app to read.
- **selecta can see Spotify and Apple Music, but not control them.** `pause` and
  `vol` reach selecta's own playback and the YouTube window. It says so rather
  than silently doing nothing.
- **YouTube mode always shows a window.** Required by YouTube's policies, not a
  design choice.
- **Some official uploads refuse embedded playback.** selecta skips to the next
  candidate, which can mean a re-upload or lyric video instead of the official
  one. When everything is blocked it hands you the direct link.
- **Live radio cannot skip a track.** `selecta next` changes station, and says
  so rather than pretending.
- **Track titles depend on the station.** Many streams send them; some send only
  the station name. selecta shows what it's given, never a guess.
- **Music stops when your session ends.** Deliberate: an orphaned audio process
  you can't find is worse than pressing resume.
- **One player per machine**, not per session. A second session shows the same
  track.
- **macOS and Linux.** Windows and WSL are not tested.
- **Some stations play a short ident** before the music. That's SomaFM, not a
  bug.
- **Amapiano, classical and some other genres have no SomaFM station** and route
  to radio-browser, where quality varies more.

## Tests

```
./tests/run.sh              # everything; prints the total
./tests/run.sh unit         # offline, deterministic
./tests/run.sh integration  # real mpv with --ao=null, no audio device needed
./tests/run.sh contract     # live upstreams; nightly in CI, never on PRs
```

`integration/playback.sh` runs real `mpv` against an `av://lavfi` tone and
asserts the whole chain: supervisor start, state, segment, launcher render,
volume, pause, stop, teardown. No network, no audio device, deterministic.

The status line has its own adversarial suite: missing, empty, truncated,
corrupt and directory-shaped state, 4-byte UTF-8, glob characters and tabs in
track titles, and a non-numeric `$COLUMNS`. Every case must exit 0.

`evals/` holds behavioural cases for the skills, led by the three
`no-autostart*` ones: music must never start unless you asked for it. They are
graded by reading, not by running — there is no eval runner here, and
`tests/run.sh` does not execute them. See `evals/README.md`.

## Developing

The repo root is the marketplace; each plugin lives under `plugins/`. `tests/`,
`evals/` and `demo/` sit at the root and are not part of either install payload.

`claude plugin install` from a directory source **copies** the plugin into
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. It does not
reference your working tree, and the staleness is invisible: the command works,
it's just running old code.

While developing, run the repo directly:

```bash
./plugins/selecta/bin/selecta play ambient
./tests/run.sh
```

To refresh an installed copy you must bump the version, or the update is a
no-op:

```bash
# bump "version" in plugins/<name>/.claude-plugin/plugin.json
claude plugin marketplace update azandabot-selecta
claude plugin update selecta@azandabot-selecta
# then restart the session
```

`selecta doctor` prints the directory it's running from, so you can always tell
which copy answered.

## Contributing

Issues and pull requests welcome. `./tests/run.sh` and `shellcheck -x -s sh`
should both be clean, and `claude plugin validate --strict` should pass for both
plugins and the marketplace.

---

<p align="center">
If selecta earned a place in your status line, a ⭐ helps other people find it.
</p>

## License

MIT
