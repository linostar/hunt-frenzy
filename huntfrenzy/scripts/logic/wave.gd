class_name Wave
extends RefCounted
## Wave schedules. Static only: a wave's spawns and shells are a pure function of the
## mode, the wave's index (1 for the first) and the run's seed.
## Endless: wave n holds min(start_birds + (n - 1) x bird_growth, max_birds) birds, one
## every spawn_interval seconds from 0, each drawn from the mode's birds with its own
## seed; the speed scale is min(1 + (n - 1) x speed_growth, speed_cap); the shells are
## Ammo.pool_size(birds, shells_per_bird).


## One bird of a wave: its type, when it spawns (seconds from the wave's start) and its
## flight seed.
class Spawn:
	var bird_id := ""
	var time := 0.0
	var bird_seed := 0


## A wave: its index, spawns in time order, shell count and speed scale.
class Plan:
	var index := 0
	var spawns: Array[Spawn] = []
	var shells := 0
	var speed_scale := 1.0


static func endless(mode: ModeSpec, wave_index: int, run_seed: int) -> Plan:
	var plan := Plan.new()
	plan.index = wave_index
	plan.speed_scale = speed_scale(mode, wave_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, wave_index])
	var count := bird_count(mode, wave_index)
	for i in count:
		var spawn := Spawn.new()
		spawn.bird_id = mode.birds[rng.randi_range(0, mode.birds.size() - 1)]
		spawn.time = i * mode.spawn_interval
		spawn.bird_seed = rng.randi()
		plan.spawns.append(spawn)
	plan.shells = Ammo.pool_size(count, mode.shells_per_bird)
	return plan


static func bird_count(mode: ModeSpec, wave_index: int) -> int:
	return mini(mode.start_birds + (wave_index - 1) * mode.bird_growth, mode.max_birds)


static func speed_scale(mode: ModeSpec, wave_index: int) -> float:
	return minf(1.0 + (wave_index - 1) * mode.speed_growth, mode.speed_cap)
