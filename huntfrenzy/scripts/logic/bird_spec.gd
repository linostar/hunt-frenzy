class_name BirdSpec
extends Resource
## One bird type from data/birds.json. Built by Content.

var id := ""
var name := ""
## Flight speed in base units per second (before the wave's speed scale).
var speed := 0.0
## Vertical wobble amplitude in base units, and its frequency in Hz.
var wobble := 0.0
var wobble_hz := 0.0
## Seconds of flight before the bird heads off the top of the screen.
var flee_time := 0.0
var points := 0
## Art name: res://art/<sprite>_fly_1.svg, <sprite>_fly_2.svg (flap frames) and <sprite>_hit.svg.
var sprite := ""
## Drawn size in base units; the sprite's centre is the bird's origin.
var size := Vector2.ZERO
## Hitbox polygon in sprite-local base units (origin at the centre, the bird facing right).
var hitbox := PackedVector2Array()


## The texture path of `frame` ("fly_1", "fly_2" or "hit").
func texture_path(frame: String) -> String:
	return "res://art/%s_%s.svg" % [sprite, frame]
