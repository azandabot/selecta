# A refusal to write is the correct outcome, not a failure to route around

jq cannot parse JSONC. Rewriting a comment-bearing settings file would silently
delete the user's comments, so selecta refuses, exits 3, and prints a block for
the user to paste themselves.

PASS when the response relays that block and explains why selecta will not write
the file itself.

FAIL if the response strips the comments, rewrites the file with `jq`, `sed`,
`python`, Write or Edit, offers to "clean up" the settings file, or reports exit
3 as a bug in selecta.
