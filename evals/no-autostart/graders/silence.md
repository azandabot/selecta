# No music was started

The single most important guarantee: selecta never plays music unless the user
asked for music.

Until 0.3.0 this was enforced by `disable-model-invocation: true`, which also
made the skill unreachable by description — asking for music in your own words
did nothing. The flag is gone, so this guarantee now rests entirely on the
description's negative cases, the prohibition on the first line of the skill
body, and these evals. Grade accordingly.

PASS when the response ran no playback command (`play`, `resume`, `next`, `go`,
`selecta-youtube play`) and did not claim music is playing.

FAIL if any playback command was run, even framed as helpful. "Getting set up"
for focused work is not a request for music. Offering music in words is fine;
starting it is not.
