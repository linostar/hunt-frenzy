class_name Rival
extends RefCounted
## The rival hunter's rules. Static only: Play asks and shows, nothing here keeps state.
## Steals (modes with rival_steals): once a bird has flown its linger_time the rival aims
## at it (the aim cue) for aim_time, measured from the age the cue started at, then fires
## and never misses. The decoy (his own pigeon) is never aimed at, and a bird that has
## started fleeing (its shells ran out) drops the cue and gets away. A kill during the
## cue saves the bird; Play cancels the cue then.
## Heckles: a line of the category, picked from the run seed and the run's heckle count
## (so a replayed run says the same lines). Miss, combo and wave-end lines wait for
## cooldown seconds after the last heckle; steal lines always show.

enum Steal { NONE, AIMING, FIRE }

## The cue_age of a bird the rival is not aiming at.
const NOT_AIMING := INF
## The heckle category that skips the cooldown.
const STEAL := "steal"


## What the rival does about a flying bird now: NONE (not aiming: steals off, the decoy, a
## fleeing bird, or younger than linger_time), AIMING (start or keep the cue) or FIRE (the
## cue has run aim_time: steal it). `cue_age` is the age its cue started at, NOT_AIMING
## before one.
static func steal_state(age: float, linger_time: float, aim_time: float, cue_age: float, is_decoy: bool, fleeing: bool, steals_on: bool) -> Steal:
	if not steals_on or is_decoy or fleeing or age < linger_time:
		return Steal.NONE
	if cue_age != NOT_AIMING and age >= cue_age + aim_time:
		return Steal.FIRE
	return Steal.AIMING


## Whether a `category` heckle may show at `now` (seconds of run time) when the last one
## showed at `last` (-INF before any): steal lines always may, others once `cooldown` has
## passed.
static func may_heckle(category: String, now: float, last: float, cooldown: float) -> bool:
	return category == STEAL or now - last >= cooldown


## The line of `lines` for the run's `count`-th heckle (0 for the first), from `run_seed`.
static func pick_line(lines: PackedStringArray, run_seed: int, count: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, count, "heckle"])
	return lines[rng.randi_range(0, lines.size() - 1)]
