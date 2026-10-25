class_name Scoring
extends RefCounted
## A run's score and combo: a kill scores the bird's points times the multiplier, then
## raises the multiplier by 1 (up to combo_cap); a damaging hit (an armored bird's first)
## scores nothing and leaves the multiplier alone; a miss resets it to 1; a hit on a decoy
## deducts its penalty (the score never goes below 0) and resets it to 1. Refused shots
## never reach Scoring.

var score := 0
var multiplier := 1
var combo_cap := 1
## Shots that hit a bird other than a decoy (kills and damaging hits).
var hits := 0
var misses := 0
## Shots that hit a decoy.
var penalties := 0


func _init(cap: int) -> void:
	combo_cap = cap


## Scores a hit on a bird worth `points`; returns the points awarded.
func hit(points: int) -> int:
	var awarded := points * multiplier
	score += awarded
	hits += 1
	multiplier = mini(multiplier + 1, combo_cap)
	return awarded


## A hit that does not kill (an armored bird's first): no points, the multiplier unchanged.
func damage() -> void:
	hits += 1


## A hit on a decoy worth `amount` penalty; returns the points actually deducted (the
## score never goes below 0).
func penalty(amount: int) -> int:
	var deducted := mini(amount, score)
	score -= deducted
	penalties += 1
	multiplier = 1
	return deducted


func miss() -> void:
	misses += 1
	multiplier = 1


## Shells fired (hits, misses and decoy hits).
func shots() -> int:
	return hits + misses + penalties
