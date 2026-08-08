# Troubleshooting

Read this before speculating about a failure. Start with `selecta doctor`, which
reports dependencies, player state, status line state and crate count in one
pass.

## No sound

| Symptom | Cause | Remedy |
|---|---|---|
| `no player installed` | mpv not present | Show the install command `doctor` prints. **Do not run a package manager for the user.** |
| `player did not start` | mpv present but failed to launch | `selecta doctor`, then check `~/.claude/selecta/log/selecta.log`. |
| Plays, but silent | system output device or volume | `selecta vol 60`, then check the OS mixer. mpv is running if `selecta` reports `playing`. |
| Short ident before music | SomaFM preroll | Not a fault. Some stations play a station ident first. |

## Nothing matches the request

`selecta resolve --json "<words>"` returns `status`:

- `none` — nothing matched. Offer `selecta stations`. Do not guess a URL.
- `ambiguous` — rewrite using `hint_tags` and `references/stations.md`, then
  resolve again with `--tags`. See that file for worked examples.

If the second attempt is also empty, present three real candidates from
`selecta stations`. Never invent a fourth.

## Stream problems

| Symptom | Cause | Remedy |
|---|---|---|
| Playback stops after a few seconds | stream endpoint rotated | selecta retries the mirrors from the playlist automatically, then re-resolves. If it still fails the station may be down; try another. |
| A station keeps failing | dead entry in the directory | After three consecutive failures it is auto-banned and demoted. `selecta ban <id>` does it immediately. |
| `could not reach that stream` | network, or the provider is down | Check connectivity. SomaFM tier 1 works from a baked catalogue offline, but playback itself always needs the network. |
| radio-browser results are empty | their directory currently resolves to a single host, so outages are common | Expected. selecta falls through to the Internet Archive automatically. |

## Status line

| Symptom | Cause | Remedy |
|---|---|---|
| Refuses to install | settings file is `jsonc`, `unparseable` or `readonly` | Correct behaviour, not a bug. It prints a block to paste. |
| Installed but blank | nothing is playing | The line disappears when stopped. Start something. |
| Installed but never updates | `refreshInterval` missing | Should be `2`. Check with `selecta statusline status`. |
| Footer key hints disappeared | any status line does this | Expected and disclosed at install. `selecta statusline off` brings them back. |
| Someone else's status line vanished | should not happen | selecta wraps rather than replaces. `selecta statusline off` restores the original from the backup. |

Backups are written next to the settings file as
`settings.json.selecta.bak.<timestamp>` before every change.

## Process problems

| Symptom | Cause | Remedy |
|---|---|---|
| Music continues after the session ended | `SessionEnd` did not fire (kill -9, closed terminal) | The watchdog stops it within two minutes. `selecta stop` is immediate. |
| Two sessions, two players | should not happen | One player per user, enforced by a lock. The second exits silently. |
| Player will not start after a crash | stale lock or pidfile | Reaped automatically on the next command. The lock is only honoured while its owning process is alive. |

## Data

Everything lives in `~/.claude/selecta/`:

```
config.json            preferences
soundtracks/           one file per repository, plus index.json
run/                   state.json, segment, sockets, pidfile
log/selecta.log        rotated at 1MB
cache/                 catalogues and resolved queries
```

**Nothing is written into the user's repository.**

A file that fails to parse is renamed to `.corrupt.<timestamp>` rather than
discarded, and selecta says where it went. Months of listening history are not
thrown away silently.

## Repository identity

| Situation | Behaviour |
|---|---|
| ssh and https remotes for the same repo | one crate; both normalise to the same key |
| worktrees | share the parent's crate, because a worktree is the same project |
| fork, then remote changed to upstream | the crate follows, via the alias list |
| no remote | keyed on the git directory |
| not a git repo | keyed on the path; `selecta crate` says so, and offers to migrate if the directory later becomes a repo |
| submodule | its own crate |

## Uninstalling

```
selecta statusline off      # first, so the settings entry goes
claude plugin uninstall selecta
selecta uninstall --purge   # only if the crates should go too
```

`--purge` deletes every crate for every repository and asks for typed
confirmation.
