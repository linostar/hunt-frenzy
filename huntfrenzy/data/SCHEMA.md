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
- `Content.FILES` loads `birds.json` first, then `modes.json` (modes reference birds), then `rival_lines.json` (I13
  needs the birds and the rival's `aim_time`).
- **Chapter ids**: `dawn`, `noon`, `sunset`, `night`, in campaign order (`Content.CHAPTERS`, the one list in code). A
  bird's `chapter` names one of them. Step 5's `chapters.json` takes this list over (each chapter an entry with that
  id), and `chapter` then becomes a reference into it.

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

## birds.json
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | |
| `name` | string | 1..26 chars | Display name. |
| `chapter` | string | chapter id | The campaign chapter that introduces the type (step 5's campaign reads it). |
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

## rival_lines.json
A single object (not an array):
| field | type | range / enum | notes |
|---|---|---|---|
| `aim_time` | float | 0.5..10 | Seconds the rival aims (the cue on the bird and on him) before he fires. |
| `cooldown` | float | 0..60 | Seconds after a heckle before a miss, combo or wave-end line can show; steal lines skip it. |
| `lines` | object | keys exactly `miss`, `combo`, `wave_end`, `steal`, `results` (`RivalLines.CATEGORIES`) | Each a non-empty array of strings of 1..40 characters (`Content.RIVAL_LINE_MAX`: two lines of the speech bubble). An error names the category: `data/rival_lines.json [steal] lines: missing category`, `[miss] lines[2]: length 45 is outside 1..40 ...`. |

---

## Invariants (`tools/test_content.gd` must check all of these)
I1-I4 and I13 are the loader's own checks (`Content.errors()`); `test_content.gd` proves each against the real data
(no errors) and each one firing on a malformed copy with the exact error lines. I5-I12 are checked only by
`test_content.gd`, against the real data and on a malformed copy each (with the loader quiet, so the invariant's own
check is what catches it). A loader check that depends on a field that already has an error is skipped (I4's inside
the sprite check when `size` failed, I13 when `flee_time`, `linger_time` or `aim_time` did), so each problem is reported
once, against the field it is in, never against a fallback value.
- **I1** Every file parses, is a non-empty array of objects, ids are snake_case and unique per file, no entry (and no
  `birds[]` object) has a missing or unknown key, `splits_into` and `split_count` come together, a mix names each bird
  at most once and has a bird from wave 1. `rival_lines.json` is a non-empty object with exactly `aim_time`,
  `cooldown` and `lines`, and `lines` holds exactly the five categories.
- **I2** Every field has its type and lies in its range or enum above (`chapter` is a chapter id; every rival line is
  a string of 1..40 characters).
- **I3** Cross-references resolve: `birds[].bird`, `golden_bird`, `splits_into`; every sprite has its `fly_1`, `fly_2`
  and `hit` frames, plus `damaged_fly_1` and `damaged_fly_2` when `hp > 1`.
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
  decoy, is smaller on both axes and faster than it, and is in no mode's mix and no mode's `golden_bird` (it only comes
  from splits).
- **I8** A mode's `golden_bird` is not in its mix, has `hp` 1, no split and no penalty, and is faster and worth more
  points than every bird of its mix.
- **I9** Wave 1 is plain: every mix bird with `from_wave` 1 has `pattern` `rise`, `hp` 1, no split and no penalty, and
  `golden_from_wave >= 2`; so a run's first bird is a plain goose (the web smoke test shoots it).
- **I10** The roster has every kind of bird, each able to appear: a plain bird (not golden), an armored one
  (`hp >= 2`), a splitter, a `zigzag` flier, a golden bird and a decoy. Each chapter id introduces at least one bird
  that can appear, and every bird can appear (in a mix, as a `golden_bird` or as a split child).
- **I11** Every bird fits the field (`Play.FIELD`, 960x384): `size.x < 960` and `size.y + 2 x wobble < 384`.
- **I12** Every hitbox's bounding box is at least 44 base units on each side (the game's smallest touch target), so a
  fingertip can hit every bird, the splitter's goslings included.
- **I13** For every bird but the decoy (never stolen), `linger_time + aim_time < flee_time`, so every aim cue can
  finish before the bird flees on its own. Reported as `data/birds.json [<id>] linger_time: <linger> + aim_time <aim>
  is not under flee_time <flee> (I13: ...)`.

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

Endless: 2 birds in wave 1, one more per wave up to 6, speed x1.08 per wave up to x1.6, a spawn every 1.4 s,
3 shells per hit needed, combo cap 5, the run ends at 10 counted escapes (stolen birds included), rival steals on.

Rival: aim 1.0 s (so every cue ends at least 0.5 s before the bird flees: the gosling's 1.5 + 1.0 against its 3.0),
heckle cooldown 4.0 s; 5 miss, 4 combo, 4 wave_end, 5 steal and 4 results lines, the longest 40 characters.
