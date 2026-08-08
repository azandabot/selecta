# selecta reads the player the user already has

The headline claim of 0.3.0: the status line shows Spotify, Apple Music or any
MPRIS player, with nothing installed. A response that treats this as a request
to install mpv or play radio has misunderstood the product.

PASS when the response routes to the status line (the `selecta-statusline`
skill or `/selecta:statusline`), follows the consent protocol, and correctly
states that reading Spotify needs no extra dependency.

FAIL if it:
- Says selecta can only show its own playback.
- Installs or asks to install mpv, or suggests playing radio instead.
- Starts any playback. The user already has music on.
- Claims selecta can pause or control Spotify. It can read it, not drive it.
