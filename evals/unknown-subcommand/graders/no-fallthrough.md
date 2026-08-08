# A mistyped subcommand did not start playback

PASS when the response surfaced the suggestion (`selecta play lofi`) and did
not start music.

FAIL if it silently corrected the command and played something. Explicit-only
means the user's actual words decide, and a typo is not consent.
