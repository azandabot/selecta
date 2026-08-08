# Stations and vocabulary

Read this when a request comes back `ambiguous` and needs rewriting into terms
the catalogues index. The goal is to turn what a person said into what a music
directory calls it.

## Rewriting an ambiguous request

`selecta resolve` returns `hint_tags` when it recognises a mood it cannot serve
from SomaFM. Feed those back with `--tags`. When it returns nothing useful,
translate the request yourself using the vocabulary below, then resolve again.

Worked examples:

| The user said | What it means to a catalogue | Command |
|---|---|---|
| something with a log drum | amapiano, afro house | `selecta resolve --json --tags "amapiano,afro house" "log drum"` |
| aura farming music | phonk, drift, hard techno | `selecta resolve --json --tags "phonk,drift,techno" "aura"` |
| music for staring at a wall | drone, dark ambient | `selecta play drone` |
| something to ship to | electronic, breakbeat | `selecta play shipping` |
| rainy sunday music | downtempo, trip hop, jazz | `selecta play mellow` |
| feel like I'm in a heist | lounge, spy jazz | `selecta play secretagent` |
| gym music | workout, metal, bass | `selecta play workout` |
| study music | ambient, chillout | `selecta play focus` |

Two rules. Translate into *genre* terms, not mood adjectives, because tag
indexes are genre-shaped. And if the second attempt also comes back empty, stop
and offer real candidates from `selecta stations` rather than trying a third
guess.

## Mood vocabulary

`data/mood-map.json` maps 117 mood and genre words to stations and tags. Words
with no station are deliberate: SomaFM does not cover them, so they route to
radio-browser and the Internet Archive instead. Those include
`amapiano`, `log drum`, `yanos`, `afrobeats`, `afro house`, `gqom`, `kwaito`,
`soca`, `highlife`, `classical`, `opera`, `piano`, `gospel`, `k-pop` and
`anime`.

Anything in that file resolves confidently, so prefer its words when rewriting.

## SomaFM stations

46 stations, all free and listener-supported, no account required.

| id | Station | Genre | Description |
|---|---|---|---|
| `7soul` | Seven Inch Soul | oldies | Vintage soul tracks from the original 45 RPM vinyl. |
| `beatblender` | Beat Blender | electronic | A late night blend of deep-house and downtempo chill. |
| `bootliquor` | Boot Liquor | americana | Americana Roots music for Cowhands, Cowpokes and Cowtippers |
| `brfm` | Black Rock FM | eclectic | From the Black Rock Desert playa to the world, year round! |
| `cliqhop` | cliqhop idm | electronic | Blips'n'beeps backed mostly w/beats. Intelligent Dance Music. |
| `covers` | Covers | eclectic | Just covers. Songs you know by artists you don't. We've got you covered.  |
| `deepspaceone` | Deep Space One | ambient | Deep ambient electronic, experimental and space music. For inner and outer space exploration. |
| `defcon` | DEF CON Radio | electronic|specials | Music for Hacking. The DEF CON Year-Round Channel. |
| `digitalis` | Digitalis | electronic|alternative | Digitally affected analog rock to calm the agitated heart. |
| `doomed` | Doomed | ambient|industrial | Where every day is Halloween: Dark industrial/ambient music for tortured souls.  |
| `dronezone` | Drone Zone | ambient | Served best chilled, safe with most medications. Atmospheric textures with minimal beats. |
| `dz2` | Drone Zone 2 | ambient | A more eclectic alternative mix of atmospheric textures with minimal beats. |
| `dubstep` | Dub Step Beyond | electronic | Dubstep, Dub and Deep Bass. May damage speakers at high volume. |
| `fluid` | Fluid | electronic|hiphop | Drown in the electronic sound of instrumental hiphop, future soul and liquid trap. |
| `folkfwd` | Folk Forward | folk|alternative | Indie Folk, Alt-folk and the occasional folk classics.  |
| `groovesalad` | Groove Salad | ambient|electronic | A nicely chilled plate of ambient/downtempo beats and grooves. |
| `groovesalad2` | Groove Salad 2 | ambient|electronic | A different mix of  nicely chilled ambient/downtempo beats and grooves. |
| `gsclassic` | Groove Salad Classic | ambient|electronic | The classic (early 2000s) version of a nicely chilled plate of ambient/downtempo beats and grooves. |
| `illstreet` | Illinois Street Lounge | lounge | Classic bachelor pad, playful exotica and vintage music of tomorrow. |
| `indiepop` | Indie Pop Rocks! | alternative|rock | New and classic favorite indie pop tracks. |
| `live` | SomaFM Live | live|specials | Special Live Events and rebroadcasts of past live events |
| `lush` | Lush | electronic | Sensuous and mellow female vocals, many with an electronic influence. |
| `missioncontrol` | Mission Control | ambient|electronic | Celebrating NASA and Space Explorers everywhere. |
| `poptron` | PopTron | alternative | Electropop and indie dance rock with sparkle and pop. |
| `secretagent` | Secret Agent | lounge | The soundtrack for your stylish, mysterious, dangerous life. For Spies and PIs too! |
| `seventies` | Left Coast 70s | 70s|rock | Mellow album rock from the Seventies. Yacht not required. |
| `sf1033` | SF 10-33 | ambient|news | Ambient music mixed with the sounds of San Francisco public safety radio traffic. |
| `sonicuniverse` | Sonic Universe | jazz | Transcending the world of jazz with eclectic, avant-garde takes on tradition. |
| `spacestation` | Space Station Soma | electronic | Tune in, turn on, space out. Spaced-out ambient and mid-tempo electronica. |
| `suburbsofgoa` | Suburbs of Goa | world | Desi-influenced Asian world beats and beyond. |
| `thetrip` | The Trip | electronic | Progressive house / trance. Tip top tunes. |
| `thistle` | ThistleRadio | celtic|world | Exploring music from Celtic roots and branches |
| `u80s` | Underground 80s | alternative|electronic | Early 80s UK Synthpop and a bit of New Wave. |
| `metal` | Metal Detector | metal | From black to doom, prog to sludge, thrash to post, stoner to crossover, punk to industrial. |
| `reggae` | Heavyweight Reggae | reggae | Reggae, Ska, Rocksteady classic and deep tracks. |
| `scanner` | SF Police Scanner | live|news | San Francisco Public Safety Scanner Feed |
| `vaporwaves` | Vaporwaves | electronic | All Vaporwave. All the time. |
| `specials` | SomaFM Specials | specials | Now featuring Afternoon Jazz, Wavepool, DubX, The Surf Report & More! |
| `n5md` | n5MD Radio | specials | Emotional Experiments in Music: Ambient, modern composition, post-rock, & experimental electronic music |
| `synphaera` | Synphaera Radio | ambient|electronic | Featuring the music from an independent record label focused on modern electronic ambient and space music. |
| `darkzone` | The Dark Zone | ambient | The darker side of deep ambient. Music for staring into the Abyss.  |
| `sfinsf` | SF in SF | spoken | Author readings and discussions from the science fiction, fantasy, horror, and genre literary fields. |
| `tikitime` | Tiki Time | tiki|world | Classic Tiki music and Vintage island rhythms to sip cocktails by. |
| `bossa` | Bossa Beyond | bossanova|world | Silky-smooth, laid-back Brazilian-style rhythms of Bossa Nova, Samba and beyond |
| `insound` | The In-Sound | pop|oldies | 60s/70s Hipster Euro Pop where psychedelic melodies meets groovy vibes.  |
| `chillits` | Chillits Radio | chill|live | Celebrating 25 years of music, chilling and camping |

## Beyond SomaFM

When SomaFM has nothing, the resolver falls through automatically:

- **radio-browser** — thousands of community-indexed stations, no key. Only
  entries the directory last verified as working, at 64kbps or better.
- **Internet Archive netlabels** — Creative Commons albums, no key. The deepest
  keyless track-level catalogue, and the slowest, so it goes last.

Nothing is downloaded from any of them. Streams are played, not stored.

## Prerolls

Some SomaFM stations play a short station ident before the music. That is the
station doing it, not a fault.
