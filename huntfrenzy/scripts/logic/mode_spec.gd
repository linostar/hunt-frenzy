class_name ModeSpec
extends Resource
## One game mode from data/modes.json. Built by Content (data/SCHEMA.md documents every field).


## One bird of the mode's wave mix: the type, the first wave it can appear in, its weight
## in the seeded pick among the birds already unlocked and an optional guaranteed wave.
class Entry:
	var bird := ""
	var from_wave := 1
	var weight := 1
	## The one wave that always holds at least one of this bird (Wave.for_mode turns a slot
	## into it when the pick left it out); 0: none (the optional key is absent).
	var guaranteed_wave := 0


## One look of the mode's run: a backdrop id and the weather drawn over it (as a chapter's).
class Stage:
	var backdrop := ""
	var weather := ""


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
## How a run ends: a mode has exactly one of escape_limit and time_limit (Content rejects
## both and neither), and the other stays 0 here, meaning "does not apply".
## Lost birds (counted escapes and stolen birds) that end a run (Endless); 0 in a timed mode.
var escape_limit := 0
## Seconds a run lasts (Time Attack); 0 in a mode that ends at escape_limit.
var time_limit := 0.0
## Whether the rival steals birds left flying past their linger_time (Rival); when false he
## only heckles.
var rival_steals := false
## The run's looks, in order: each lasts backdrop_waves waves, and the last one holds from
## then on (Endless: dawn, noon, sunset, then night; Time Attack: noon throughout).
var stages: Array[Stage] = []
var backdrop_waves := 0
## The music track the mode's runs play: res://audio/music/<id>.mp3 (Content.music_path).
var music := ""


## True for a mode whose run ends after time_limit seconds (Time Attack); false for one
## that ends at escape_limit lost birds (Endless).
func is_timed() -> bool:
	return time_limit > 0.0


## The look of wave `wave_index` (1 = the first): stages[(wave_index - 1) / backdrop_waves],
## the last stage from then on.
func stage_for(wave_index: int) -> Stage:
	return stages[mini(floori((wave_index - 1) / float(backdrop_waves)), stages.size() - 1)]
