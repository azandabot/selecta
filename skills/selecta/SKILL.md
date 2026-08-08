---
name: selecta
description: Plays background music in the terminal during a coding session and gives every git repository its own accumulating soundtrack. Use when the user explicitly asks to play, pause, skip, stop or change music, asks what is playing, asks what a repository sounds like, or asks to see their listening history. Handles requests phrased as a mood, genre, artist or vibe, including ones with no obvious station such as "something with a log drum" or "aura farming music". Never start music unless the user asked for music.
argument-hint: "play <mood> | resume | next | stop | vol <n> | crate | history | stations | doctor"
disable-model-invocation: true
license: MIT
compatibility: Requires mpv (or ffplay) and jq, plus network access. macOS and Linux.
hooks:
  SessionEnd:
    - hooks:
        - type: command
          command: "\"${CLAUDE_PLUGIN_ROOT}\"/libexec/selecta-teardown"
          timeout: 1
---

# selecta

Background music from internet radio and Creative Commons catalogues, controlled
from the terminal, with each repository accumulating its own soundtrack.

Everything runs through one executable:

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta <subcommand> [args]
```

Run it with Bash. Report what it prints. It is designed to be read aloud to the
user almost verbatim.

## The one rule that matters

**Never construct a stream URL, station id, or playlist entry yourself.**

Resolution belongs to `selecta resolve`, which owns the catalogues and the
provider APIs. A URL you compose from memory will be wrong, dead, or an
invention. If `resolve` returns nothing, say so and offer `selecta stations`.

**Never start playback unless the user asked for music.** The skill is
`disable-model-invocation: true` precisely so this cannot happen by accident.
Setting up someone's environment, starting a long task, or being told "I'm about
to focus" are not requests for music.

## Playing something

For a direct request, pass the user's words through unchanged:

```
selecta play amapiano
selecta play something calm for reading
selecta play groovesalad
```

`selecta play` with no argument resumes what this repository already sounds
like, or starts a first station if the repo has no crate yet.

## When a request has no obvious match

This is the case worth handling well, and where you earn your keep.

Run the resolver first and read `status`:

```
selecta resolve --json "<the user's words>"
```

- `status: "ok"` — `selecta play` will land it. Just play it.
- `status: "none"` — nothing matched. Say so, suggest `selecta stations`. Do not
  guess.
- `status: "ambiguous"` — there is no confident station, but `hint_tags` carries
  vocabulary the networked catalogues understand. **Rewrite the request into
  catalogue vocabulary and resolve again**, rather than giving up or picking a
  poor match.

Rewriting means translating what the user said into genre terms a music
directory would index. "Something with a log drum" is amapiano and afro house.
"Aura farming music" is closer to phonk, drift or hard techno. "Music for
staring at a wall" is drone or dark ambient. Use `references/stations.md` for
the catalogue's own vocabulary, then:

```
selecta resolve --json --tags "amapiano,afro house,deep house" "log drum"
```

If that still returns nothing, offer three real candidates from
`selecta stations` and let the user choose. Never invent a fourth.

## Control

```
selecta            # what is playing, plus this repo's crate
selecta pause      # and: selecta go
selecta next       # next source in this repo's rotation
selecta stop
selecta vol 40     # also +10, -10, mute, unmute
```

`next` changes station rather than track. Live radio has no track skip, and
`selecta` says so in its own output. Do not describe it as skipping a song.

## The per-repo crate

This is the point of the tool, not a side feature.

```
selecta crate          # what this repo sounds like
selecta history        # tracks grouped by the commit they scored
selecta resume         # put this repo's soundtrack back on
selecta pin | ban | forget <source>
```

Every track is stamped with the branch and commit that were checked out while
it played, so `history` reads as a record of the work, not a playlist. When a
user asks what they were listening to during some piece of work, that is
`selecta history`.

Crates live in `~/.claude/selecta/`, keyed by repository. **Nothing is ever
written into the user's repository.** `selecta export` requires an explicit
path and refuses to write inside the working tree.

## Status line

`selecta statusline on` shows the current track in the status line. It edits the
user's global `~/.claude/settings.json`, so it prints the exact JSON, discloses
that a status line hides most built-in footer key hints, backs the file up, and
asks before writing.

**Run it only when the user asks for it, and let it ask its own question — do
not answer on their behalf.** If it reports the settings file is `jsonc`,
`unparseable` or `readonly`, it deliberately refuses and prints a block to paste
manually. Relay that; it is the correct outcome, not a failure.

`selecta statusline off` reverses it and restores any pre-existing status line.

## When something is wrong

```
selecta doctor
```

Reports dependencies, whether the player is running, whether the status line is
installed, and how many crates exist. If a player is missing it prints the exact
install command for the platform. **Show the user the command; do not run a
package manager for them.**

Common cases are in `references/troubleshooting.md`. Read it before
speculating about a failure.

## Reference files

- `references/stations.md` — the 46 SomaFM stations, their genres, and the mood
  vocabulary. Read this when rewriting an ambiguous request.
- `references/statusline.md` — the exact settings block, merge behaviour, wrap
  mode and how to undo. Read before touching the status line.
- `references/troubleshooting.md` — every failure mode and its remedy. Read
  before diagnosing.
