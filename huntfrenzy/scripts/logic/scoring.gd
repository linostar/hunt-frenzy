class_name Scoring
extends RefCounted
## A run's score and combo: a hit scores the bird's points times the multiplier, then
## raises the multiplier by 1 (up to combo_cap); a miss resets it to 1. Refused shots
## never reach Scoring.

var score := 0
var multiplier := 1
var combo_cap := 1
var hits := 0
var misses := 0


func _init(cap: int) -> void:
	combo_cap = cap


## Scores a hit on a bird worth `points`; returns the points awarded.
func hit(points: int) -> int:
	var awarded := points * multiplier
	score += awarded
	hits += 1
	multiplier = mini(multiplier + 1, combo_cap)
	return awarded


func miss() -> void:
	misses += 1
	multiplier = 1


## Shells fired (hits and misses).
func shots() -> int:
	return hits + misses
