# YouTube mode

Read this before playing anything from YouTube, and before explaining the
player window to anyone.

## When YouTube is used

Radio is the default and stays windowless. YouTube is for requests that name a
specific recording rather than describe a feeling.

| Request | Backend | Window |
|---|---|---|
| `play ambient`, `play focus`, `play amapiano` | radio | none |
| `play something calm for reading` | radio | none |
| `play sponono by kabza de small` | YouTube | opens |
| `play --yt <anything>` | YouTube | opens |
| `play --radio <anything>` | radio | none |

**Never route an ambient or mood request to YouTube.** A window appearing when
someone asked for background music is the single worst outcome here.

## The window is mandatory

YouTube's Developer Policies §III.I.9 prohibits playing content "from a
background player, meaning a player that is not displayed", and Required
Minimum Functionality sets a 200×200 floor on the viewport. selecta opens a
480×380 app-mode window and never hides, minimises or shrinks it.

This is not a preference and it cannot be configured away. If someone asks for
YouTube audio with no window, the honest answer is that radio mode is the
windowless option.

Related rules selecta follows, which are worth knowing before you offer to
change any behaviour:

- Nothing is downloaded, cached or stored. Streaming only.
- The player's own controls stay visible and unmodified.
- No ad blocking or interference.
- The product is not described as an audio-only YouTube experience.

## Embeddability, which is the real limitation

A large share of major-label music disallows embedded playback. A verified
example: a Kabza De Small track returns error 150, "embedding disabled by the
owner". This is common for official label uploads and rare for independent
uploads, lyric videos and live sets.

selecta defends against it in three layers:

1. `search.list` runs with `videoEmbeddable=true`, so the API filters first.
2. `videos.list` confirms `status.embeddable` for the whole result set in one
   batched call.
3. The player reports error 100, 101 or 150 and the shell advances to the next
   candidate automatically.

**What this means in practice:** the user usually gets the song, but sometimes
a re-upload, lyric video or live version rather than the official one. Say that
plainly if they ask why the result looks unofficial. Do not imply selecta chose
badly; the official upload was refused by its owner.

If every candidate is unembeddable, selecta says so. Do not fall back to
describing the song, and never construct a video URL yourself.

## The API key

Radio needs no key. YouTube does, and the user brings their own: an API key
cannot be shipped in an open source project.

```
selecta config youtube.api_key YOUR_KEY
```

Free, roughly five clicks: console.cloud.google.com → new project → enable
"YouTube Data API v3" → Credentials → Create credentials → API key.

`selecta doctor` reports whether a key is set and how much quota is left.

### Quota

`search.list` costs 1 unit from a **separate 100 per day** Search Queries
bucket. `videos.list` costs 1 unit from the general 10,000 per day bucket, so
validation is effectively free and **search is the scarce resource**.

selecta caches every resolved query for 7 days, well inside YouTube's 30-day
limit on storing API data, so repeating a request costs nothing.

When the bucket runs out, selecta says so and falls back to radio. The quota
resets at midnight Pacific.

## What the user sees

A small window with the player, the track title, and a pause button. The status
line shows the same track, right-aligned:

```
                                    ♪ Kabza De Small — Sponono · YouTube · demo-api
```

Track titles in YouTube mode are real song names, which is the main difference
from radio: many stations send only a station name.

## Failure modes

| Symptom | Meaning | What to say |
|---|---|---|
| `no key` | none configured | Show the setup steps. Radio still works. |
| `quota` | 100 searches used today | Resets midnight Pacific. Radio still works. |
| every candidate skipped | all unembeddable | Offer radio, or a different search phrasing. |
| window did not open | no browser, or python3 missing | `selecta doctor` prints which. |
| "browser blocked autoplay" | Chrome autoplay policy | The user presses play once in the window. |

The player server binds to 127.0.0.1 on an ephemeral port with a per-session
token, so nothing else on the machine can drive it.
