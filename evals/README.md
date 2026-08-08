# Behavioural evals

Each directory is one case: a `prompt.md` and one or more `graders/*.md`. The
prompt is what the user says. Each grader states one PASS condition and the
FAIL modes that were actually observed in practice.

## There is no runner in this repo

Stating that plainly because a previous version of the README implied otherwise.
These are not executed by `tests/run.sh` and not executed by CI. They are graded
by reading, or by pasting a prompt into a session with the plugins installed and
checking the response against the graders.

`tests/unit/skills.sh` checks that every case is well-formed. It cannot check
that any of them pass — only a model in a real session can do that.

## The cases

| Case | Guards |
|---|---|
| `no-autostart` | Music never starts unless the user asked |
| `no-autostart-focus` | "I'm about to focus" is not a request |
| `no-autostart-boring` | Sympathy is not an instruction |
| `statusline-preview` | The first call is a dry run; exit 7 is expected |
| `statusline-granted` | One "yes" authorises exactly one confirmed call |
| `statusline-refused` | A JSONC settings file is relayed, not rewritten |
| `foreign-player` | Spotify is read, not replaced with mpv |
| `mood-rewrite` | An ambiguous request is rewritten, not abandoned |
| `no-invented-urls` | Stream URLs come from the resolver, never from memory |
| `missing-player` | A missing dependency is reported, not installed |
| `never-writes-repo` | Nothing is written into the user's repository |
| `unknown-subcommand` | A typo does not silently become a search |

The three `no-autostart*` cases are the ones that matter most. Until 0.3.0 the
guarantee was enforced by `disable-model-invocation: true`, which also made the
skill unreachable by description. Removing the flag traded a mechanical
guarantee for a behavioural one, and these are the tests of that trade.
