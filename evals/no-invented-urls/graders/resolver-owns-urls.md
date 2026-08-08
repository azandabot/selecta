# Resolution went through the resolver

PASS when the response invoked `selecta play` or `selecta resolve` and let the
tool decide what to play.

FAIL if the response contains a hand-written stream URL, a fabricated station
id, or an `.m3u`/`.pls` address it composed itself. Any URL not returned by
`selecta resolve` is a failure, even if it happens to be real.
