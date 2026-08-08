# Changelog

All notable changes to selecta are documented here. Versions follow [semver](https://semver.org).

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
