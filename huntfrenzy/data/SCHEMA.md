# Hunt Frenzy content schema

Source of truth for every file in `huntfrenzy/data/`. `Content` (`scripts/logic/content.gd`) loads against this
document and `tools/test_content.gd` checks the invariants at the end. If the code and this file disagree, fix one of
them so they match. Do not leave the code working around the difference.

## Conventions (all files)
- UTF-8 JSON. Every file's top level is a **non-empty array of objects**; every object has a unique `"id"`. The one
  exception is `rival_lines.json`, a single non-empty object (below): its errors name the line category as the entry
  (`data/rival_lines.json [miss] lines[2]: ...`), and `-` for its top-level fields.
- Ids are snake_case: `^[a-z][a-z0-9_]*$`, unique within their file.
- Every field listed below is **required** unless marked *optional*. The loader reports a missing key, a wrong type,
  an out-of-range value, an unknown enum value, an unknown id **and an unknown key** as
  `data/<file> [<entry id>] <field>: <problem>` (a field inside an object is named `birds[0].weight`), collects all of
  them, and the title then disables Play. An optional field that is absent takes the default stated here; nothing
  else has a default.
- `int` means a JSON integer. Godot parses all JSON numbers as `float`, so the loader checks that
  `value == floor(value)` and then casts. `float` accepts integers too.
- Units: lengths in base units (the 960x540 landscape base viewport), speeds in base units per second, times in
  seconds, frequencies in Hz.
- `Content.FILES` loads `chapters.json` first, then `birds.json` (a bird's `chapter` references a chapter), then
  `modes.json` and `levels.json` (they reference birds; levels also chapters), then `rival_lines.json` (I13 needs the
  birds, the modes, the chapters and the rival's `aim_time`).
- **Chapters**: `chapters.json` is the one list of chapters, in campaign order (dawn, noon, sunset, night); no chapter
  id is written in code. A bird's or a level's `chapter` is a reference into it.

## Game rules the data relies on
- **Flight** (`scripts/logic/flight.gd`): a bird rises from fully below the grass line at a seeded x and heading (30-60
  degrees above the horizontal) into the field (`Play.FIELD`, x 0-960, y 56-440: below the HUD bar, above the grass),
  then bounces inside it with a seeded-phase vertical wobble. At `flee_time` (or at once when the wave's shells run out)
  it climbs straight up, and it has escaped once fully above the screen top. A `zigzag` bird also reverses its
  horizontal heading at seeded intervals (`Flight.ZIGZAG_INTERVAL_MIN`..`MAX`, 0.35-0.8 s). A split child is launched
  from the hit point (kept inside the field) on a heading from `Flight.split_headings` (fanned 100 degrees around
  straight up).
- **Hits** (`Play`): a shot hits the frontmost flying bird whose hitbox polygon holds the point (above the grass line).
  A hit short of the bird's `hp` damages it (no points, the combo multiplier unchanged; it flies on with its damaged
  frames); the killing hit scores `points` x the multiplier and raises it (up to the mode's `combo_cap`). Killing a
  bird with `splits_into` launches `split_count` children of that type from the hit point; the killed bird falls and
  can no longer escape. A hit on a bird with a `penalty` (the decoy) deducts the penalty (the score never goes below 0)
  and resets the multiplier to 1.
- **Escapes**: a bird that gets away counts toward the mode's `escape_limit` unless its `escape_counts` is false.
- **Rival** (`scripts/logic/rival.gd`, Play): in a mode with `rival_steals`, once a bird other than the decoy has flown
  its `linger_time` (and has not started fleeing) the rival aims at it (a visible cue) for `aim_time`, counted from the
  cue's start, then shoots it and never misses: it falls as stolen, its `points` (no combo multiplier) go to the
  rival's tally, and it counts as an escape (toward `escape_limit`); a stolen splitter launches no children, and the
  player's combo is untouched. Killing it during the cue saves it (a damaging hit does not); a bird that starts fleeing
  drops its cue. With `rival_steals` false he only heckles. Heckles: a line of the category, picked from the run seed
  and the run's heckle count, on a miss, a combo rising to x3 or more and a wave's end (each at most once per
  `cooldown` after the last heckle) and on every steal (no cooldown); the results screen shows a `results` line.
- **Campaign** (`scripts/logic/campaign.gd`, `Wave.campaign`): a level plays all its `waves` (no escape limit, no
  early fail) and then ends on the results screen. Every wave holds `wave_birds` birds from its `mix`, one every
  `spawn_interval` at `speed_scale`, except the boss level's last wave: the boss flock (`boss`: its own `birds`,
  `spawn_interval`, `speed_scale` and `mix`). Every slot of every wave is the level's `golden_bird` with chance
  `golden_chance`, else a pick weighted by `weight`; all of it from the level's fixed `seed` (wave n's RNG is
  `hash([seed, n])`), so every play of a level meets the same birds. Shells as below, with the level's
  `shells_per_hit`; the combo is capped by its `combo_cap`. The rival always steals in a level, after the bird's
  `linger_time x` the chapter's `rival_linger_scale`. Stars: the final score earns one per `stars` threshold it
  reaches (0 stars: not passed). Order: the chapters in data order, each chapter's levels by `index`; the first level
  is always open, every other opens once the one before it is passed (a chapter's level 1 after the previous
  chapter's level 6); a chapter opens with its level 1. The save keeps each level's best stars and best score.
- **Waves** (`scripts/logic/wave.gd`, Endless): wave n holds `min(start_birds + (n - 1) x bird_growth, max_birds)`
  birds, one every `spawn_interval` from 0. Each spawn slot is the mode's `golden_bird` with chance `golden_chance`
  from wave `golden_from_wave` on; otherwise it is a pick, weighted by `weight`, among the `birds` entries whose
  `from_wave <= n`. The speed scale is `min(1 + (n - 1) x speed_growth, speed_cap)`.
- **Shells**: a wave's pool is `(sum over its birds of Wave.hits_needed) x shells_per_hit`, where
  `hits_needed = hp + split_count` (each split child takes one hit, I7) and 0 for a decoy (never to be shot).
- **Art**: a bird's sprite is `res://art/<sprite>_fly_1.svg` and `_fly_2.svg` (flap frames), `_hit.svg` (the killed
  frame), plus `_damaged_fly_1.svg` and `_damaged_fly_2.svg` when `hp > 1`. Each is drawn facing right, its centre the
  bird's origin, scaled to `size`.

---

## chapters.json
Exactly `Content.CHAPTER_COUNT` (4) chapters, in campaign order.
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | `dawn`, `noon`, `sunset`, `night`. |
| `name` | string | 1..26 chars | Display name. |
| `sky_tint` | string | `"#rrggbb"`, lowercase hex | The play scene's placeholder sky tint (the art pass draws real backdrops). |
| `weather` | string | `"mist" \| "wind" \| "rain" \| "snow"` (`Content.WEATHERS`) | The chapter's weather (logged; the art pass draws it). |
| `rival_linger_scale` | float | (0, 1]: above 0, at most 1 | The rival steals after `linger_time x` this in the chapter's levels; at most the chapter before's (I14). |

## birds.json
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | |
| `name` | string | 1..26 chars | Display name. |
| `chapter` | string | chapter id (chapters.json) | The campaign chapter that introduces the type (I19). |
| `pattern` | string | `"rise" \| "zigzag"` | Flight pattern (above). |
| `speed` | float | 1..1000 | Base units per second, before the wave's speed scale. |
| `wobble` | float | 0..100 | Vertical wobble amplitude in base units. |
| `wobble_hz` | float | 0..5 | Wobble frequency. |
| `flee_time` | float | 0.1..60 | Seconds of flight before it climbs off the top. |
| `linger_time` | float | 0.1..60 | Seconds of flight after which the rival starts aiming at it (modes with `rival_steals`). Required for every bird, the decoy too (never used for it); `linger_time + aim_time < flee_time` (I13). |
| `points` | int | 0..100000 | Points of a kill, before the multiplier. 0 only for a decoy (I6). |
| `hp` | int | 1..5 | Hits to kill. `hp > 1` needs the damaged frames (I3). |
| `sprite` | string | 1..26 chars | Art name (above); every frame must exist (I3). |
| `size` | [float, float] | each 8..400 | Drawn width and height in base units. |
| `hitbox` | array of [float, float] | at least 3 points | Polygon in sprite-local base units (origin at the centre, facing right, y down); every point within `size / 2` of the centre on each axis, a simple polygon (I4), matching the art (I5), at least 44 units on each side of its bounding box (I12). |
| `splits_into` | string | bird id | *Optional* (default none). The type a kill splits into. Comes with `split_count`. |
| `split_count` | int | 1..4 | *Optional* (default 0). How many children a kill launches. Comes with `splits_into`. |
| `penalty` | int | 1..100000 | *Optional* (default 0). Points a hit deducts: the bird is a decoy (I6). |
| `escape_counts` | bool | | *Optional* (default `true`). Whether its escape counts toward `escape_limit`; `false` only for a decoy (I6). |

## modes.json
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | `endless` is the only mode so far (`GameState.ENDLESS_MODE`). |
| `name` | string | 1..26 chars | Display name. |
| `birds` | array of object | non-empty | The wave mix, each bird at most once, at least one with `from_wave` 1. |
| `birds[].bird` | string | bird id | |
| `birds[].from_wave` | int | 1..1000 | The first wave it can appear in. |
| `birds[].weight` | int | 1..100 | Its weight in the seeded pick among the unlocked birds. |
| `golden_bird` | string | bird id | The bird a spawn slot turns into by chance. |
| `golden_from_wave` | int | 1..1000 | The first wave a slot can turn golden (2 or later: I9). |
| `golden_chance` | float | 0..1 | The chance per spawn slot. |
| `start_birds` | int | 1..30 | Birds in wave 1. |
| `bird_growth` | int | 0..10 | Birds added per later wave. |
| `max_birds` | int | `start_birds`..30 | The most a wave holds. |
| `speed_growth` | float | 0..1 | Speed scale added per wave after the first. |
| `speed_cap` | float | 1..5 | The highest speed scale. |
| `spawn_interval` | float | 0.1..10 | Seconds between two spawns of a wave. |
| `shells_per_hit` | int | 1..10 | Shells per hit the wave needs (the shell rule above). |
| `combo_cap` | int | 1..20 | The highest combo multiplier. |
| `escape_limit` | int | 1..100 | Counted escapes that end a run (stolen birds count). |
| `rival_steals` | bool | | Whether the rival steals birds left flying past their `linger_time` (Endless, Campaign); false: he only heckles (Time Attack). No default. |

## levels.json
Exactly `Content.LEVELS_PER_CHAPTER` (6) levels per chapter, indexes 1..6, the last one the boss level (I15).
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | `<chapter>_<index>` by convention. |
| `chapter` | string | chapter id | |
| `index` | int | 1..6 | The level's place in its chapter. |
| `seed` | int | 0..2147483647 | The fixed seed of every wave's schedule and of the rival's line picks. |
| `waves` | int | 1..20 | Waves played; on the boss level the last one is the boss flock. |
| `wave_birds` | int | 1..30 | Birds per (non-boss) wave. |
| `mix` | array of object | non-empty | The wave mix, each bird at most once. |
| `mix[].bird` | string | bird id | |
| `mix[].weight` | int | 1..100 | Its weight in the seeded pick. |
| `golden_bird` | string | bird id | The bird a spawn slot turns into by chance (I8). |
| `golden_chance` | float | 0..1 | The chance per spawn slot, every wave (the boss flock too). |
| `speed_scale` | float | 0.5..5 | Speed scale of every non-boss wave. |
| `spawn_interval` | float | 0.1..10 | Seconds between two spawns of a non-boss wave. |
| `shells_per_hit` | int | 1..10 | Shells per hit a wave needs (the shell rule). |
| `combo_cap` | int | 1..20 | The highest combo multiplier. |
| `stars` | [int, int, int] | each 1..10000000, strictly ascending | The final scores that earn 1, 2 and 3 stars; the third at most the level's highest sure score (I16). |
| `boss` | object | | Required on level 6, forbidden on any other (I15): the boss flock. |
| `boss.birds` | int | 1..30 | Its birds (more than any wave of the chapter: I18). |
| `boss.spawn_interval` | float | 0.1..10 | Shorter than any wave of the chapter's (I18). |
| `boss.speed_scale` | float | 0.5..5 | Higher than any wave of the chapter's (I18). |
| `boss.mix` | array of object | non-empty, as `mix` | Weighted toward a bird the chapter introduces (I18). |

## rival_lines.json
A single object (not an array):
| field | type | range / enum | notes |
|---|---|---|---|
| `aim_time` | float | 0.5..10 | Seconds the rival aims (the cue on the bird and on him) before he fires. |
| `cooldown` | float | 0..60 | Seconds after a heckle before a miss, combo or wave-end line can show; steal lines skip it. |
| `lines` | object | keys exactly `miss`, `combo`, `wave_end`, `steal`, `results` (`RivalLines.CATEGORIES`) | Each a non-empty array of strings of 1..40 characters (`Content.RIVAL_LINE_MAX`: two lines of the speech bubble). An error names the category: `data/rival_lines.json [steal] lines: missing category`, `[miss] lines[2]: length 45 is outside 1..40 ...`. |

---

## Invariants (`tools/test_content.gd` must check all of these)
I1-I4 and I13-I15 are the loader's own checks (`Content.errors()`); `test_content.gd` proves each against the real data
(no errors) and each one firing on a malformed copy with the exact error lines. I5-I12 and I16-I19 are checked only by
`test_content.gd`, against the real data and on a malformed copy each (with the loader quiet, so the invariant's own
check is what catches it; I17 on a stand-in schedule, since `shells_per_hit >= 1` always covers the hits). A loader
check that depends on a field that already has an error is skipped (I4's inside the sprite check when `size` failed,
I13 when `flee_time`, `linger_time`, `aim_time` or a chapter's `rival_linger_scale` did, the scale order when the scale
did, the boss and index rules when `index` did), so each problem is reported once, against the field it is in, never
against a fallback value.
- **I1** Every file parses, is a non-empty array of objects, ids are snake_case and unique per file, no entry (and no
  `birds[]`, `mix[]` or `boss` object) has a missing or unknown key, `splits_into` and `split_count` come together, a mix names each bird
  at most once and has a bird from wave 1. `rival_lines.json` is a non-empty object with exactly `aim_time`,
  `cooldown` and `lines`, and `lines` holds exactly the five categories.
- **I2** Every field has its type and lies in its range or enum above (every rival line is a string of 1..40
  characters; `sky_tint` is `#rrggbb`).
- **I3** Cross-references resolve: a bird's and a level's `chapter`, `birds[].bird`, `mix[].bird`, `boss.mix[].bird`,
  `golden_bird`, `splits_into`; every sprite has its `fly_1`, `fly_2` and `hit` frames, plus `damaged_fly_1` and
  `damaged_fly_2` when `hp > 1`.
- **I4** Every hitbox has at least 3 points, all inside its sprite (`|x| <= size.x / 2`, `|y| <= size.y / 2`), and is a
  simple polygon (no two non-adjacent edges touch or cross).
- **I5** Every hitbox matches its art, sampled once per base unit on each flap frame (damaged ones included), a pixel
  counting as art when its alpha is >= 0.5: at least 98% of the points inside the hitbox lie on the art (the rest is
  anti-aliasing along the outline), and the hitbox covers at least 50% of the art's points (the real art measures
  60-80%: the flapping wings, beaks and tails lie outside every hitbox; a box on the body alone covers well under a
  third).
- **I6** A bird has a `penalty` exactly when its `escape_counts` is false (the decoy). A decoy has `points` 0, `hp` 1
  and no split; every other bird has `points >= 1`. The decoy's silhouette differs from every other type's by shape:
  the intersection over union of their opaque `fly_1` masks (each sampled on a 48x36 grid across its own sprite) is at
  most 0.85 (a recoloured copy of a shape scores 0.9 or more).
- **I7** A bird with `splits_into` has `hp` 1 (its first hit splits it). Its child has `hp` 1, does not split, is no
  decoy, is smaller on both axes and faster than it, and is in no mode's or level's mix (the boss flock's included)
  and no `golden_bird` (it only comes from splits).
- **I8** A mode's or level's `golden_bird` is not in its mix (a level's boss flock included), has `hp` 1, no split and
  no penalty, and is faster and worth more points than every bird of its mix.
- **I9** Wave 1 is plain: every mode mix bird with `from_wave` 1 has `pattern` `rise`, `hp` 1, no split and no
  penalty, and `golden_from_wave >= 2`; and the campaign's first level's wave 1 (its fixed-seed schedule) spawns only
  such birds, none golden; so a run's first bird is a plain goose (the web smoke test shoots it in Endless's tests and
  in dawn_1).
- **I10** The roster has every kind of bird, each able to appear: a plain bird (not golden), an armored one
  (`hp >= 2`), a splitter, a `zigzag` flier, a golden bird and a decoy. Each chapter introduces at least one bird
  that can appear, and every bird can appear (in a mode's or level's mix, as a `golden_bird` or as a split child).
- **I11** Every bird fits the field (`Play.FIELD`, 960x384): `size.x < 960` and `size.y + 2 x wobble < 384`.
- **I12** Every hitbox's bounding box is at least 44 base units on each side (the game's smallest touch target), so a
  fingertip can hit every bird, the splitter's goslings included.
- **I13** For every bird but the decoy (never stolen), every linger the rival uses plus `aim_time` is under
  `flee_time`: `linger_time x 1` in each mode with `rival_steals`, and `linger_time x rival_linger_scale` in each chapter
  (the campaign always steals); so every aim cue (at least 0.5 s: `aim_time`'s range) can finish before the bird flees
  on its own. Reported once per bird at the largest failing scale, naming every mode and chapter that fails:
  `data/birds.json [<id>] linger_time: <linger> x <scale> (<modes and chapters>) + aim_time <aim> is not under flee_time
  <flee> (I13: ...)`.
- **I14** `chapters.json` holds exactly 4 chapters; each `rival_linger_scale` is in (0, 1] and at most the previous
  chapter's (the rival never gets slower).
- **I15** Every chapter has exactly the levels 1..6, each index once; level 6, and only level 6, has a `boss`; each
  level's `stars` rise strictly.
- **I16** Each level's 3-star threshold is at most its highest sure score (`Campaign.max_score`): every bird but the
  decoy killed (a splitter's children right after it) in spawn order, the combo rising from x1 on every kill to
  `combo_cap` and never broken, with the shells each wave gets; so three stars can be reached.
- **I17** Every wave of every level has the shells for every hit its birds need (`Wave.hits_needed`).
- **I18** Each chapter's last level is its one boss level, and its boss flock has more birds, a shorter spawn interval
  and a higher speed scale than every other wave of the chapter, and its heaviest mix bird is one the chapter
  introduces (not a decoy, not the golden bird).
- **I19** No level uses a bird a later chapter introduces (in its mixes, as its golden bird or as a split child of
  one); every bird a chapter introduces spawns in at least one of its levels' fixed-seed waves (a split child counts
  when its parent spawns); a golden bird spawns in every chapter.

## Current content
| bird | chapter | pattern | speed | flee | linger | points | hp | special | Endless |
|---|---|---|---|---|---|---|---|---|---|
| goose | dawn | rise | 140 | 6.0 | 3.5 | 100 | 1 | | wave 1+, weight 10 |
| armored | noon | rise | 115 | 7.0 | 4.0 | 150 | 2 | damaged frames | wave 3+, weight 4 |
| splitter | sunset | rise | 120 | 6.5 | 3.5 | 120 | 1 | splits into 2 goslings | wave 5+, weight 3 |
| gosling | sunset | rise | 230 | 3.0 | 1.5 | 60 | 1 | splitter's child | never from waves |
| zigzag | night | zigzag | 175 | 6.0 | 3.5 | 200 | 1 | | wave 7+, weight 3 |
| golden | dawn | rise | 240 | 4.0 | 2.5 | 500 | 1 | | 8% of slots from wave 2 |
| decoy | sunset | rise | 120 | 7.0 | 4.0 | 0 | 1 | penalty 200, escape not counted, never stolen (the rival's pigeon in a top hat) | wave 5+, weight 2 |

Chapters: dawn (mist, rival linger x1.0), noon (wind, x0.9), sunset (rain, x0.8), night (snow, x0.7); dawn introduces
the goose and the golden goose, noon the armored goose, sunset the splitter (and its gosling) and the decoy, night the
zigzag swift.

| chapter | levels 1-6: waves x birds | speed | spawn every | shells per hit | combo cap | boss flock (level 6's last wave) |
|---|---|---|---|---|---|---|
| dawn | 3x3, 3x4, 4x4, 4x5, 5x5, 5x5 | x1.0-1.1 | 1.4 s | 3 | 3-5 | 10 birds, 0.7 s, x1.25, geese |
| noon | 3x4, 4x4, 4x5, 4x5, 5x5, 5x5 | x1.1-1.2 | 1.3 s | 3 | 4-5 | 11 birds, 0.65 s, x1.35, armored 8 : goose 3 |
| sunset | 3x4, 4x5, 4x5, 4x5, 5x5, 5x5 | x1.2-1.3 | 1.2 s | 3 | 4-5 | 12 birds, 0.6 s, x1.45, splitter 8 : goose 2 : decoy 2 |
| night | 3x4, 4x5, 4x5, 4x6, 5x6, 5x6 | x1.3-1.4 | 1.1 s | 2 | 4-6 | 12 birds, 0.55 s, x1.6, zigzag 8 : goose 2 : decoy 2 |

Golden chance 0.08 per slot everywhere but dawn_1 (0: its first wave is three plain geese). Star thresholds are about
35%, 60% and 85% of each level's highest sure score (rounded to 50).

Endless: 2 birds in wave 1, one more per wave up to 6, speed x1.08 per wave up to x1.6, a spawn every 1.4 s,
3 shells per hit needed, combo cap 5, the run ends at 10 counted escapes (stolen birds included), rival steals on.

Rival: aim 1.0 s (so every cue ends at least 0.5 s before the bird flees: the gosling's 1.5 + 1.0 against its 3.0),
heckle cooldown 4.0 s; 5 miss, 4 combo, 4 wave_end, 5 steal and 4 results lines, the longest 40 characters.
