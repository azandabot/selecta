# Changelog

All notable changes to selecta are documented here. Versions follow [semver](https://semver.org).

## [0.3.0] - 2026-08-08

selecta is now a status line first. It shows what you are playing whatever you
are playing it with, and needs nothing installed to do that. Its own radio
playback, the crate, and YouTube are what you add on top.

### Migration

The status line survives untouched: it points at a copy at
`~/.claude/selecta/statusline.sh`, outside the plugin directory, so the move
does not break it. Crates and `config.json` are unchanged.

Two things need action:

- **YouTube moved to its own plugin.** `/plugin install
  selecta-youtube@azandabot-selecta`. Named tracks already in your crates keep
  playing once it is installed; without it selecta says so and plays radio.
- **The marketplace source path changed** from `./` to `./plugins/selecta`. If
  `claude plugin update` does not pick up 0.3.0, remove and re-add the
  marketplace.

`selecta play --yt` still works and now routes to the plugin.

### Added
- Reads Spotify and Apple Music on macOS, and any MPRIS player on Linux. No
  dependency, no key, no configuration. On macOS every probe is gated behind
  `pgrep`, so a music app that was not already running is never launched.
- `selecta-youtube`, a companion plugin in the same marketplace. It uses
  selecta's own libraries rather than copying them, so the crate schema, state
  file and status line segment keep one implementation between the two.
- Five skills split by what they change: exactly one can edit global settings,
  exactly two can start audio, three change nothing and say so. Each carries
  literal user phrasings, an explicit "do NOT use for", and a side-effect
  contract. Command mirrors for all six.
- A `SessionStart` hook that refreshes the plugin-root pointer after an update
  and mentions the status line exactly once per machine, gated so it can never
  ask twice.
- `crate --history` and `crate --path`, replacing the separate `history` command.
- `tests/integration/playback.sh`: real mpv against an `av://lavfi` tone,
  asserting the whole chain offline and deterministically. The README had
  claimed this test since the first release.
- `tests/unit/{crate,cli,nowplaying,youtube,skills,docs}.sh`. The crate module,
  which its own header calls the reason selecta exists, had no coverage at all.

### Fixed
- **`statusline on` could never succeed through an agent.** It called `read`
  with no TTY, which under `set -e` killed the script mid-command. The no-flag
  invocation is now a dry run that writes nothing and exits 7; `--user-confirmed`
  applies it. A test asserts `settings.json` is byte-identical after the first
  call.
- **A 403 from a project without YouTube Data API v3 enabled was reported as
  "no results"**, so selecta played radio and doctor said "key set". The reason
  code is now read, and `selecta-youtube doctor` probes the API rather than
  reporting the contents of a config file.
- `doctor` died on its own `jq` call after reporting that `jq` was missing.
- `nc -U` was an unchecked hard dependency. The transport now resolves through
  `nc` → `ncat` → `socat` → `python3` and is reported by doctor.
- `privacy.record_commits: false` was ignored, because the config reader used
  jq's `//` operator and `false // default` yields the default.
- A tab in a track title forged an extra segment field and made the status line
  render the wrong width variant.
- Crate loading forked one `jq` per crate file on disk, from seven call sites.
  Aliases moved into the index; a load with 60 crates now forks fewer than five,
  and a test holds that floor.
- `lifecycle.sh` gated eight assertions on `command -v timeout`, which stock
  macOS does not ship, so the macOS CI leg silently ran seven of fifteen.
- Both plugin-root pointers were written from `$0` and only resolved from the
  directory the command happened to run in.

### Changed
- The repo root is now the marketplace and each plugin lives under `plugins/`,
  which removes `tests/`, `evals/` and `demo/` from the install payload.
- The supervisor polls on a two-second tick instead of a fifo plus a persistent
  `nc`, and starts mpv lazily. It no longer exits when mpv is absent, because
  mpv is required for radio, not for reading a player you already have open.
- Ranking is by recency for `resume` and by listening time for the crate card,
  replacing a half-life decay nobody could predict. Three consecutive failures
  retire a source from the rotation; a success clears the count.
- `start_source` tries the next mirror before giving up.
- `disable-model-invocation` removed. It made every description inert: asking
  for music in your own words did nothing, because the only way in was typing
  the command.

### Removed
- `userConfig` from the manifest. No code read it, and shipping a field the code
  cannot read is how the 403 bug shipped.
- `cmd_export`, which emitted playlists with empty URLs, and `cmd_curate`.
- The Internet Archive tier, which emitted cards nothing could play, and every
  `ffplay` reference, which was advertised in four places and implemented in
  none.
- 32 test assertions that grepped `bin/selecta` for its own source text. They
  passed whether or not the code ran, and broke on any refactor that touched a
  string.

## [0.2.0] - 2026-08-08

Added YouTube playback in a visible player window, a right-aligned status line,
and the fixes found by using it: honest playback reporting, stop and pause
reaching the YouTube backend, resume replaying a YouTube track, and a retry that
finds a playable version when the official upload is embed-locked.

Superseded by 0.3.0 nine hours later; see the migration note above.

## [0.1.0] - 2026-08-08

First release.

### Added
- Per-repository crates: stations weighted by listening time, and every track
  stamped with the branch and commit that were checked out while it played.
- `selecta crate` and `selecta history`, which group listening by the commits
  it accompanied.
- Tiered resolution from free text to playable audio: exact match and mood
  vocabulary offline, then radio-browser, Jamendo and the Internet Archive
  netlabels collection. Works with no API key.
- A 46-station SomaFM seed catalogue baked in, so mood resolution works with no
  network.
- 117-entry mood vocabulary, including genres SomaFM does not cover, which route
  to the networked catalogues rather than forcing a poor match.
- Now-playing status line with three width buckets, installed only with explicit
  consent, backed up first, and wrapping any existing status line rather than
  replacing it.
- Background supervisor owning mpv over its IPC socket, with a watchdog, a
  singleton lock, and teardown inside the SessionEnd budget.
- `selecta doctor`, which reports dependencies and prints the exact install
  command for the platform without running it.
- 155 assertions across unit, integration and contract suites, including an
  adversarial status line suite where every case must exit 0.

### Notes
- Playback is streaming only. Nothing is downloaded or stored.
- Music stops when the session ends, by design.
- macOS and Linux. Windows and WSL are untested.
