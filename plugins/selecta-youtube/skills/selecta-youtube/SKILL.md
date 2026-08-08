---
name: selecta-youtube
description: Plays one specific named recording through YouTube - a particular song by a particular artist - in a small visible player window, and records it in the repository's selecta crate. Use only when the user names an actual track or artist they want to hear, such as "play Sponono by Kabza De Small" or "put on the new Burna Boy". Do NOT use for moods, genres or vibes ("something calm", "amapiano", "lo-fi for focus") - those belong to the selecta skill, play on radio, and open no window. This skill starts audio and opens a browser window, so only run it when the user asked for that specific track.
argument-hint: "play <artist - title>"
license: MIT
compatibility: Needs the selecta plugin, jq, curl, python3, a browser, and a free YouTube Data API key. macOS and Linux.
---

# selecta-youtube

**This skill starts audio and opens a visible browser window.** Run it only when
the user named a specific recording they want to hear.

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta-youtube play "kabza de small - sponono"
```

`selecta play "<a named track>"` routes here on its own once this plugin is
installed, so most of the time the plain `selecta` skill is the right entry
point and this one is for when the user is explicit.

## The window is not optional

YouTube's Developer Policies forbid playing from a player that is not
displayed, and set a minimum viewport size. So a small browser window opens and
stays visible for as long as the track plays. It cannot be hidden, minimised by
selecta, or shrunk, and there is no configuration that changes this.

Say this plainly the first time a user is surprised by it. It is a licensing
constraint, not a bug and not an oversight.

**Never use this skill for an ambient or background request.** A window
appearing when someone asked for something to work to is the worst outcome this
tool has.

## Setup, and the step everyone misses

A free YouTube Data API key is required. Two things must both be true, and only
the first is obvious:

1. An API key exists.
2. **YouTube Data API v3 is enabled on that Google Cloud project.**

A key without step 2 returns 403 on every single search. Check with:

```
"${CLAUDE_PLUGIN_ROOT}"/bin/selecta-youtube doctor
```

It probes the API rather than reporting the contents of the config file, so
`api NOT ENABLED` means exactly that. Relay the URL it prints. **Do not create
projects, keys or cloud resources on the user's behalf.**

The key is set with `selecta config youtube.api_key YOUR_KEY`.

## Quota

100 searches a day, resetting at midnight Pacific. Replays cost nothing: a track
already in the crate plays again from its stored video id with no search. Say
how many searches are left when the user is deciding whether to keep searching;
the command prints the number.

## When nothing will play

A large share of major-label music disallows embedded playback. selecta-youtube
already filters at search time, revalidates in a second call, skips videos that
fail with 100, 101 or 150, and re-searches with phrasings that surface lyric and
audio re-uploads.

When it still fails, it prints a direct YouTube link. **Relay the link.** Do not
suggest a downloader, a proxy, an alternate frontend, or any other way around the
embedding restriction. Offering the artist on radio instead is a fine suggestion;
circumventing the restriction is not.

## Should trigger

- "play Sponono by Kabza De Small"
- "put on the new Burna Boy album"
- "play that Tyla song"
- "can you play Teddy Pendergrass - Love TKO"

## Should NOT trigger

- "play something calm" · "amapiano" · "lo-fi for focus" — **selecta**, radio,
  no window
- "put some music on" — **selecta**
- "I'm about to focus for two hours" — not a request for music at all
- "what have I been listening to?" — **selecta-crate**

## Side effects

Opens a visible browser window under a dedicated profile. Spends one unit of the
daily search quota per new search. Records the track in this repository's crate,
under `~/.claude/selecta/`. Never writes into the user's repository.

## Reference

- `references/youtube.md` — the policy constraints, embeddability failures, the
  key, and the quota in detail. Read before explaining any of them.
