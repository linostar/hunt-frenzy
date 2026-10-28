class_name BirdSpec
extends Resource
## One bird type from data/birds.json. Built by Content (data/SCHEMA.md documents every field).

## The flap frames a bird with hp > 1 shows once it has taken a hit.
const DAMAGED_FRAMES: Array[String] = ["damaged_fly_1", "damaged_fly_2"]

var id := ""
var name := ""
## The id of the campaign chapter that introduces the type (a ChapterSpec in data/chapters.json).
var chapter := ""
## Flight pattern: "rise" (Flight's climb-and-bounce path) or "zigzag" (the same, with
## sharp heading reversals at seeded intervals).
var pattern := ""
## Flight speed in base units per second (before the wave's speed scale).
var speed := 0.0
## Vertical wobble amplitude in base units, and its frequency in Hz.
var wobble := 0.0
var wobble_hz := 0.0
## Seconds of flight before the bird heads off the top of the screen.
var flee_time := 0.0
## Seconds of flight after which the rival starts aiming at it (in modes with rival_steals;
## never the decoy). linger_time + the rival's aim_time is under flee_time (SCHEMA.md I13).
var linger_time := 0.0
## The sound effect (birds.json "call": one of GameState.SFX_IDS, SCHEMA.md I25) the bird
## gives as it starts flying off, and the pitch it plays at (Game.play_sfx). Not named `call`,
## which would shadow Object.call.
var call_sound := ""
var call_pitch := 1.0
## Points a kill scores (before the combo multiplier); 0 for the decoy.
var points := 0
## Hits it takes to kill; every hit before the last shows the damaged frames.
var hp := 0
## Art name: res://art/<sprite>_fly_1.svg, <sprite>_fly_2.svg (flap frames), <sprite>_hit.svg,
## <sprite>_dive.svg (wings folded, head ahead: the head-first fall), and
## <sprite>_damaged_fly_1.svg / _damaged_fly_2.svg when hp > 1.
var sprite := ""
## Drawn size in base units; the sprite's centre is the bird's origin.
var size := Vector2.ZERO
## Hitbox polygon in sprite-local base units (origin at the centre, the bird facing right).
var hitbox := PackedVector2Array()
## The bird type a kill splits into ("" for none) and how many.
var splits_into := ""
var split_count := 0
## Points a hit deducts from the score (the decoy; 0 for every other bird).
var penalty := 0
## Whether getting away counts toward the mode's escape limit (false only for the decoy).
var escape_counts := true


## The texture path of `frame` ("fly_1", "fly_2", "hit", "dive", or a DAMAGED_FRAMES name).
func texture_path(frame: String) -> String:
	return "res://art/%s_%s.svg" % [sprite, frame]


## Every frame the bird's art must have: the flap, hit and dive frames, plus the damaged
## flap frames when it takes more than one hit.
func frames() -> Array[String]:
	var result: Array[String] = ["fly_1", "fly_2", "hit", "dive"]
	if hp > 1:
		result.append_array(DAMAGED_FRAMES)
	return result
