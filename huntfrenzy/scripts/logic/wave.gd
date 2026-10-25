class_name Wave
extends RefCounted
## Wave schedules. Static only: a wave's spawns and shells are a pure function of the
## mode, the wave's index (1 for the first) and the run's seed.
## Endless: wave n holds min(start_birds + (n - 1) x bird_growth, max_birds) birds, one
## every spawn_interval seconds from 0, each with its own seed. Each spawn slot is the
## mode's golden_bird with chance golden_chance from golden_from_wave on; otherwise it is a
## weighted pick among the mix's birds whose from_wave <= n. The speed scale is
## min(1 + (n - 1) x speed_growth, speed_cap); the shells are
## Ammo.pool_size(sum of hits_needed over the spawns, shells_per_hit).


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
	var mix := unlocked(mode, wave_index)
	var total := 0
	for entry in mix:
		total += entry.weight
	var hits := 0
	for i in bird_count(mode, wave_index):
		var spawn := Spawn.new()
		# Every slot rolls for golden, so the draws (and every later seed) do not depend on
		# whether golden is unlocked yet.
		var golden_roll := rng.randf()
		if wave_index >= mode.golden_from_wave and golden_roll < mode.golden_chance:
			spawn.bird_id = mode.golden_bird
		else:
			spawn.bird_id = _pick(mix, rng.randi_range(1, total))
		spawn.time = i * mode.spawn_interval
		spawn.bird_seed = rng.randi()
		plan.spawns.append(spawn)
		hits += hits_needed(Content.bird(spawn.bird_id))
	plan.shells = Ammo.pool_size(hits, mode.shells_per_hit)
	return plan


## The mix's birds that can appear in wave `wave_index` (from_wave <= wave_index).
static func unlocked(mode: ModeSpec, wave_index: int) -> Array[ModeSpec.Entry]:
	var result: Array[ModeSpec.Entry] = []
	result.assign(mode.birds.filter(func(entry: ModeSpec.Entry) -> bool: return entry.from_wave <= wave_index))
	return result


## The hits a bird needs to clear: its hp, plus one for each bird it splits into (a split
## child has hp 1, data/SCHEMA.md I7); none for a decoy, which is never to be shot.
static func hits_needed(spec: BirdSpec) -> int:
	if spec.penalty > 0:
		return 0
	return spec.hp + spec.split_count


static func bird_count(mode: ModeSpec, wave_index: int) -> int:
	return mini(mode.start_birds + (wave_index - 1) * mode.bird_growth, mode.max_birds)


static func speed_scale(mode: ModeSpec, wave_index: int) -> float:
	return minf(1.0 + (wave_index - 1) * mode.speed_growth, mode.speed_cap)


## The bird whose weight band holds `ticket` (1..the mix's total weight; Content
## guarantees a bird from wave 1, so the mix is never empty).
static func _pick(mix: Array[ModeSpec.Entry], ticket: int) -> String:
	var reached := 0
	for entry in mix:
		reached += entry.weight
		if ticket <= reached:
			return entry.bird
	# Not reached: the ticket is at most the total weight.
	return mix[mix.size() - 1].bird
