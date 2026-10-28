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
  then flies straight segments inside it at constant velocity, without wobble: it bounces off the field's edges
  (reflecting the matching velocity component) and turns to a new seeded heading (30-60 degrees from the
  horizontal, up or down, left or right) at seeded intervals: a `rise` bird every `Flight.TURN_INTERVAL_MIN`..`MAX`
  (1.0-2.5 s), a `zigzag` bird every `Flight.ZIGZAG_INTERVAL_MIN`..`MAX` (0.35-0.8 s), always reversing its
  horizontal heading. At `flee_time` (or at once when the wave's shells run out) it climbs straight up, and it has
  escaped once fully above the screen top. A split child is launched from the hit point (kept inside the field) on a
  heading from `Flight.split_headings` (fanned 100 degrees around straight up). Each bird flies at its `speed` x the
  wave's speed scale x its own seeded factor within 1 -/+ s (`Flight.speed_factor`), s rising linearly from 0.05 at
  speed scale 1 to 0.20 at `Flight.SPEED_SPREAD_TOP_SCALE` (1.6, I24), clamped.
- **Hits** (`Play`): a shot hits the frontmost flying bird whose hitbox polygon holds the point (above the grass line).
  A hit short of the bird's `hp` damages it (no points, the combo multiplier unchanged; it flies on with its damaged
  frames); the killing hit scores `points` x the multiplier and raises it (up to the mode's `combo_cap`). Killing a
  bird with `splits_into` launches `split_count` children of that type from the hit point; the killed bird falls and
  can no longer escape. A hit on a bird with a `penalty` (the decoy) deducts the penalty (the score never goes below 0)
  and resets the multiplier to 1.
- **Escapes**: a bird that gets away counts toward the mode's `escape_limit` unless its `escape_counts` is false (a
  timed mode has no escape limit: an escape only loses the bird's points).
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
- **Waves** (`scripts/logic/wave.gd`, `Wave.for_mode`: Endless and Time Attack, each with its own numbers): wave n holds `min(start_birds + (n - 1) x bird_growth, max_birds)`
  birds, one every `spawn_interval` from 0. Each spawn slot is the mode's `golden_bird` with chance `golden_chance`
  from wave `golden_from_wave` on; otherwise it is a pick, weighted by `weight`, among the `birds` entries whose
  `from_wave <= n`. The speed scale is `min(1 + (n - 1) x speed_growth, speed_cap)`.
- **Shells**: a wave's pool is `(sum over its birds of Wave.hits_needed) x shells_per_hit`, where
  `hits_needed = hp + split_count` (each split child takes one hit, I7) and 0 for a decoy (never to be shot).
- **Art**: a bird's sprite is `res://art/<sprite>_fly_1.svg` and `_fly_2.svg` (flap frames), `_hit.svg` (the killed
  frame), plus `_damaged_fly_1.svg` and `_damaged_fly_2.svg` when `hp > 1`. Each is drawn facing right, its centre the
  bird's origin, scaled to `size`. A backdrop is `res://art/backdrops/<id>_sky.svg`, `_far.svg`, `_near.svg` and
  `_grass.svg` (`Content.BACKDROP_LAYERS`, back to front; the grass is drawn in front of the birds). Every colour in
  the art comes from `art/palette.hex` (`tools/check_palette.gd`).

---

## chapters.json
Exactly `Content.CHAPTER_COUNT` (4) chapters, in campaign order.
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | `dawn`, `noon`, `sunset`, `night`. |
| `name` | string | 1..26 chars | Display name. |
| `backdrop` | string | snake_case backdrop id | The chapter's backdrop: its layers (art) must exist (I3). |
| `weather` | string | `"mist" \| "wind" \| "rain" \| "snow"` (`Content.WEATHERS`) | The weather drawn over the backdrop (visual only: it never changes a bird's flight, hitbox or timing). |
| `music` | string | snake_case music track id | The loop the chapter's levels play: `res://audio/music/<id>.mp3` must exist (I23). |
| `rival_linger_scale` | float | (0, 1]: above 0, at most 1 | The rival steals after `linger_time x` this in the chapter's levels; at most the chapter before's (I14). |

## birds.json
| field | type | range / enum | notes |
|---|---|---|---|
| `id` | string | snake_case | |
| `name` | string | 1..26 chars | Display name. |
| `chapter` | string | chapter id (chapters.json) | The campaign chapter that introduces the type (I19). |
| `pattern` | string | `"rise" \| "zigzag"` | Flight pattern (above). |
| `speed` | float | 1..1000 | Base units per second, before the wave's speed scale. |
| `wobble` | float | 0..100 | Vertical wobble amplitude in base units, on the title's crossing path only (a run's flight has none). |
| `wobble_hz` | float | 0..5 | Wobble frequency (title crossing only). |
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
| `id` | string | snake_case | `endless` (`GameState.ENDLESS_MODE`) and `time_attack` (`GameState.TIME_ATTACK_MODE`): the title starts each, and the save keeps a best per mode. |
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
| `escape_limit` | int | 1..100 | *Exactly one of `escape_limit` and `time_limit`* (below). Counted escapes that end a run (stolen birds count). |
| `time_limit` | float | 10..600 | *Exactly one of `escape_limit` and `time_limit`* (below). Seconds a run lasts. |
| `rival_steals` | bool | | Whether the rival steals birds left flying past their `linger_time` (Endless, Campaign); false: he only heckles (Time Attack). No default. |
| `backdrops` | array of object | non-empty | The run's looks in order (`ModeSpec.stages`): each `backdrop_waves` waves long, the last one held from then on. |
| `backdrops[].backdrop` | string | snake_case backdrop id | A backdrop whose layers exist (I3), as a chapter's. |
| `backdrops[].weather` | string | `Content.WEATHERS` | The weather drawn over it. |
| `backdrop_waves` | int | 1..1000 | Waves each backdrop lasts before the next cross-fades in (during that wave's lead-in, without delaying it). |
| `music` | string | snake_case music track id | The loop the mode's runs play: `res://audio/music/<id>.mp3` must exist (I23). |

**How a run ends** (the one per-mode field rule): a mode has exactly one of `escape_limit` and `time_limit`. Both
is an error (`data/modes.json [<id>] time_limit: not allowed with escape_limit (...)`), and so is neither
(`[<id>] escape_limit: missing key (a mode needs escape_limit or time_limit: how its run ends)`). The field the mode
leaves out does not apply to it (`ModeSpec` holds 0 for it; code reads either field only after
`ModeSpec.is_timed()` says which one the mode has):
- **Escape limit** (Endless): the run ends once `escape_limit` birds are lost (counted escapes and stolen birds).
- **Time limit** (Time Attack): there is no escape limit (an escape costs only the bird's lost points) and the run
  ends after `time_limit` seconds of play. The clock is the run's game time from its start: it stops while the
  game is paused (the pause menu, the rotate overlay) and runs through each wave's 1 s lead-in (`Play.WAVE_LEAD`),
  so the lead-ins are part of the time limit (the first lead-in also covers the 0.15 s fade into the run, while
  shots are ignored and no bird has spawned yet). A wave ends when every bird of it has spawned and none of them is
  flying (all hit or escaped), or, in a timed mode only, the moment its pool runs out: the wave is lost (logged), its
  birds still to spawn never spawn and each of them with `escape_counts` is counted as escaped at once, and the next
  wave starts on the same frame (with a `wave_end` heckle, cooldown permitting, and the HUD showing the new wave's
  number and pool). The lost wave's birds already in the air flee and are counted when they escape; until then they
  are still targets for the next wave's shells (a hit scores as any hit; a lost wave's splitter launches goslings of
  that wave, fleeing), and a wave's end waits only for its own birds, never a lost wave's. With an escape limit, an empty pool ends nothing: the birds still to spawn
  spawn fleeing and the wave ends once they have all escaped. Either way the next wave comes with a full pool of its
  own shells, and `rival_steals` decides whether the rival steals.

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
I1-I4, I13-I15 and I23 are the loader's own checks (`Content.errors()`); `test_content.gd` proves each against the real data
(no errors) and each one firing on a malformed copy with the exact error lines. I5-I12 and I16-I22 are checked only by
`test_content.gd`, against the real data and on a malformed copy each (with the loader quiet, so the invariant's own
check is what catches it; I17 and I20's growth and shell parts on a stand-in schedule, since the formulas and
`shells_per_hit >= 1` always hold them). A loader
check that depends on a field that already has an error is skipped (I4's inside the sprite check when `size` failed,
I13 when `flee_time`, `linger_time`, `aim_time` or a chapter's `rival_linger_scale` did, the scale order when the scale
did, the boss and index rules when `index` did), so each problem is reported once, against the field it is in, never
against a fallback value.
- **I1** Every file parses, is a non-empty array of objects, ids are snake_case and unique per file, no entry (and no
  `birds[]`, `mix[]` or `boss` object) has a missing or unknown key, `splits_into` and `split_count` come together, a mix names each bird
  at most once and has a bird from wave 1. `rival_lines.json` is a non-empty object with exactly `aim_time`,
  `cooldown` and `lines`, and `lines` holds exactly the five categories.
- **I2** Every field has its type and lies in its range or enum above (every rival line is a string of 1..40
  characters; a backdrop id is snake_case).
- **I3** Cross-references resolve: a bird's and a level's `chapter`, `birds[].bird`, `mix[].bird`, `boss.mix[].bird`,
  `golden_bird`, `splits_into`; every sprite has its `fly_1`, `fly_2` and `hit` frames, plus `damaged_fly_1` and
  `damaged_fly_2` when `hp > 1`; every backdrop (a chapter's, a mode's `backdrops[].backdrop`) has each of its layers
  (`unknown backdrop '<id>' (no res://art/backdrops/<id>_<layer>.svg)`, one line per missing layer).
- **I4** Every hitbox has at least 3 points, all inside its sprite (`|x| <= size.x / 2`, `|y| <= size.y / 2`), and is a
  simple polygon (no two non-adjacent edges touch or cross).
- **I5** Every hitbox matches its art, sampled once per base unit on each flap frame (damaged ones included), a pixel
  counting as art when its alpha is >= 0.5: at least 98% of the points inside the hitbox lie on the art (the rest is
  anti-aliasing along the outline), and the hitbox covers at least 50% of the art's points (the real art measures
  63-74%: the flapping wings, beaks and tails lie outside every hitbox; a box on the body alone covers well under a
  third).
- **I6** A bird has a `penalty` exactly when its `escape_counts` is false (the decoy). A decoy has `points` 0, `hp` 1
  and no split; every other bird has `points >= 1`. The decoy's silhouette differs from every other type's by shape:
  the intersection over union of their opaque `fly_1` masks (each sampled on a 48x36 grid across its own sprite) is at
  most 0.85 (a recoloured copy of a shape scores about 0.9 or more: the armored and golden geese against the goose
  score 0.89-1.00).
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
- **I20** Endless and Time Attack are fair, by a simulation of the real data that uses `Wave.for_mode`, `Ammo` and
  `Flight` as play does (each bird at its own `Flight.speed_factor`), over 60 run seeds and the waves a run can reach: Endless's waves 1-10, and every wave of a
  timed mode that starts before its `time_limit` even if each wave ended the moment its last bird spawned (each
  wave's lead-in counted: 11 waves for Time Attack). In each: (a) a wave never has fewer birds or a lower speed scale
  than the one before; (b) its shells cover every hit its birds need (an `Ammo` of the wave's shells never refuses
  the perfect player's shots); (c) a perfect player kills every bird but the decoy before its deadline: the rival's
  cue (`linger_time x 1`, in a mode with `rival_steals`) and `flee_time`, both counted from the bird's spawn (a split
  child's from its parent's kill). The perfect player shoots one shot every 0.35 s, each bird the moment its whole
  hitbox is above the grass line (to the frame), in the order the birds come into the field (a split child comes
  in where its parent was killed), every hit a hit, never the decoy.
- **I21** Every hitbox stands for its drawn body, measured on each flap frame's imported texture (the pixels the game
  draws, `svg/scale` 3; a pixel counting as body when its alpha is >= 0.5): the hitbox covers at least 60% of the
  opaque pixels, and its area is at most 100% of theirs (so it never claims more than the body). The real art
  measures 62-74% (the armored goose's helmeted head, the golden goose's sparkles and the flapping wings lie outside).
- **I22** Every bird reads on every backdrop: its outline (the stroke of the first path of its `fly_1` art, the
  silhouette; the palette's ink `#1f1a2e` for every bird) has a WCAG contrast of at least 3:1 against every fill and
  gradient-stop colour of every backdrop's sky layer (each chapter's and each mode stage's), and the night (the last
  chapter's backdrop) keeps the birds as visible as the day: its weakest outline contrast is not under the weakest of
  the other backdrops (real art: sunset's violet 4.00:1 is the day's weakest, the night's sky 4.06:1). The main fills'
  contrasts are printed for the record (a sky-coloured bird such as the golden goose on the sunset sky relies on its
  outline).
- **I24** `Flight.SPEED_SPREAD_TOP_SCALE` (where the per-bird speed spread reaches its 0.20 top) is the highest speed
  scale in the content: the largest of every level's `speed_scale`, every boss flock's `speed_scale` and every
  mode's `speed_cap` (1.6: the night boss and Endless).
- **I23** Every music track the data names (a chapter's `music`, a mode's `music`) is a snake_case id whose loop exists
  as `res://audio/music/<id>.mp3` (made by `tools/music.py`): `unknown music track '<id>' (no
  res://audio/music/<id>.mp3)`, a non-snake_case id `'<id>' is not a snake_case music track id`. The title and results
  loops are the game's own (`GameState.TITLE_TRACK`, `RESULTS_TRACK`), checked when the game starts.

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

Chapters: dawn (backdrop dawn, mist, music campaign_dawn, rival linger x1.0), noon (noon, wind, campaign_noon, x0.9),
sunset (sunset, rain, campaign_sunset, x0.8), night (night, snow, campaign_night, x0.7); dawn introduces
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

Endless: 2 birds in wave 1, one more per wave up to 8 (wave 7), speed +0.06 per wave up to x1.6 (wave 11), a spawn
every 1.2 s, 3 shells per hit needed, combo cap 5, the run ends at 10 counted escapes (stolen birds included), rival
steals on; backdrops dawn (mist), noon (wind), sunset (rain), then night (snow), 3 waves each, night held from wave 10, music endless (retuned in step 6 from 6 birds at most (wave 5), +0.08 speed to x1.6 (wave 9) and a spawn every 1.4 s, so
the ramp keeps growing through wave 11; I20's perfect player still kills every bird at least 0.8 s before its
deadline, the gosling's linger the tightest).

Time Attack: 60 s, 3 birds in wave 1, one more per wave up to 8 (wave 6), speed +0.06 per wave up to x1.5, a spawn
every 0.9 s, 2 shells per hit needed (a full pool every wave), combo cap 8; goose from wave 1, armored from 2, zigzag
and decoy from 3, splitter from 4, golden 10% of slots from wave 2; no escape limit, rival steals off (he heckles); the
noon backdrop with its wind throughout, music time_attack.

Rival: aim 1.0 s (so every cue ends at least 0.5 s before the bird flees: the gosling's 1.5 + 1.0 against its 3.0),
heckle cooldown 4.0 s; 5 miss, 4 combo, 4 wave_end, 5 steal and 4 results lines, the longest 40 characters.
