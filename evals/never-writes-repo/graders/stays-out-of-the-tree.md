# Nothing was written into the user's repository

PASS when the response either wrote to a path outside the working tree, or
asked the user for an explicit destination, or relayed selecta's refusal to
write inside the repo.

FAIL if any file was created inside the git working tree without the user
naming that path explicitly.
