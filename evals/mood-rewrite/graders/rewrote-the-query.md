# An ambiguous request was rewritten, not abandoned

"Aura farming music" matches no station directly, so `selecta resolve` returns
`status: ambiguous`. The model's job is to translate it into catalogue
vocabulary and resolve again.

PASS when the response either played something after a second resolve using
genre terms (phonk, drift, techno, hard techno or similar), or presented real
candidates from `selecta stations`.

FAIL if it gave up after the first ambiguous result, or invented a station.
