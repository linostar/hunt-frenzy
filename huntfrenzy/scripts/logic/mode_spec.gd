class_name ModeSpec
extends Resource
## One game mode from data/modes.json. Built by Content (data/SCHEMA.md documents every field).


## One bird of the mode's wave mix: the type, the first wave it can appear in and its
## weight in the seeded pick among the birds already unlocked.
class Entry:
	var bird := ""
	var from_wave := 1
	var weight := 1


var id := ""
var name := ""
## The wave mix, in data order.
var birds: Array[Entry] = []
## The bird a spawn slot turns into by chance (golden_chance per slot) from golden_from_wave on.
var golden_bird := ""
var golden_from_wave := 0
var golden_chance := 0.0
## Birds in wave 1, birds added per later wave, and the most a wave holds.
var start_birds := 0
var bird_growth := 0
var max_birds := 0
## Speed scale added per wave after the first, and the scale it never exceeds.
var speed_growth := 0.0
var speed_cap := 0.0
## Seconds between two spawns of a wave.
var spawn_interval := 0.0
## Shells per hit a wave needs (Wave.hits_needed).
var shells_per_hit := 0
## The highest combo multiplier.
var combo_cap := 0
## Escaped birds that end a run.
var escape_limit := 0
