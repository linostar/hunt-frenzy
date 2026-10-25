class_name Ammo
extends RefCounted
## A wave's shell pool: every shot uses one shell; with none left a shot is refused
## (no hit test, no miss).

var shells := 0
var capacity := 0


func _init(count: int) -> void:
	shells = count
	capacity = count


## The pool of a wave whose birds need `hits` hits in all (Wave.hits_needed).
static func pool_size(hits: int, shells_per_hit: int) -> int:
	return hits * shells_per_hit


## Uses one shell; false (and nothing changes) when the pool is empty: the shot is refused.
func use() -> bool:
	if shells <= 0:
		return false
	shells -= 1
	return true


func is_empty() -> bool:
	return shells <= 0
