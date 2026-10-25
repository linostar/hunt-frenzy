class_name ModeSpec
extends Resource
## One game mode from data/modes.json. Built by Content.

var id := ""
var name := ""
## Bird ids the waves draw from.
var birds := PackedStringArray()
## Birds in wave 1, birds added per later wave, and the most a wave holds.
var start_birds := 0
var bird_growth := 0
var max_birds := 0
## Speed scale added per wave after the first, and the scale it never exceeds.
var speed_growth := 0.0
var speed_cap := 0.0
## Seconds between two spawns of a wave.
var spawn_interval := 0.0
var shells_per_bird := 0
## The highest combo multiplier.
var combo_cap := 0
## Escaped birds that end a run.
var escape_limit := 0
