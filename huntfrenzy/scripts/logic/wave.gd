class_name Wave
extends RefCounted
## Wave schedules. Static only: a wave's spawns and shells are a pure function of the
## mode, the wave's index (1 for the first) and the run's seed (Endless and Time Attack:
## for_mode), or of the level and the wave's index (Campaign: the level's fixed seed).
## A mode (Endless, Time Attack; each with its own modes.json numbers): wave n holds min(start_birds + (n - 1) x bird_growth, max_birds) birds, one
## every spawn_interval seconds from 0, each with its own seed. Each spawn slot is the
## mode's golden_bird with chance golden_chance from golden_from_wave on; otherwise it is a
## weighted pick among the mix's birds whose from_wave <= n. A mix bird with a
## guaranteed_wave is then given a slot in that wave if the picks left it out (_guarantee).
## The speed scale is
## min(1 + (n - 1) x speed_growth, speed_cap); the shells are
## Ammo.pool_size(sum of hits_needed over the spawns, shells_per_hit).
## Campaign: a level plays `waves` waves; each holds wave_birds birds from its mix, one every
## spawn_interval at speed_scale, except the boss level's last wave: the boss flock, with
## the boss's birds, mix, spawn interval and speed scale. Every slot of every wave is the
## level's golden_bird with chance golden_chance. Shells as in Endless, with the level's
## shells_per_hit.


## One bird of a wave: its type, when it spawns (seconds from the wave's start) and its
## flight seed.
class Spawn:
	var bird_id := ""
	var time := 0.0
	var bird_seed := 0


## A wave: its index, spawns in time order, shell count and speed scale; `boss` on a boss
## level's last wave (the boss flock).
class Plan:
	var index := 0
	var spawns: Array[Spawn] = []
	var shells := 0
	var speed_scale := 1.0
	var boss := false


## Wave `wave_index` of a run of `mode` (Endless or Time Attack) with `run_seed`: the same
## mode, index and seed always give the same spawns, shells and speed. Every wave has its
## own full shell pool (Play refills it at each wave's start).
static func for_mode(mode: ModeSpec, wave_index: int, run_seed: int) -> Plan:
	var plan := Plan.new()
	plan.index = wave_index
	plan.speed_scale = speed_scale(mode, wave_index)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, wave_index])
	var mix := unlocked(mode, wave_index)
	var total := 0
	for entry in mix:
		total += entry.weight
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
	_guarantee(mode, plan, run_seed)
	var hits := 0
	for spawn in plan.spawns:
		hits += hits_needed(Content.bird(spawn.bird_id))
	plan.shells = Ammo.pool_size(hits, mode.shells_per_hit)
	return plan


## Gives each mix bird whose guaranteed_wave is this wave at least one slot: when the pick
## left it out, one slot (seeded by the run seed, the wave and the bird, from an RNG of its
## own, so no other draw shifts) turns into it, keeping its time and flight seed. The slot
## is one that is neither the golden bird, a decoy nor another guaranteed bird; failing
## that (a wave of goldens and decoys), any slot that is not another guaranteed bird.
static func _guarantee(mode: ModeSpec, plan: Plan, run_seed: int) -> void:
	var guaranteed: Array[String] = []
	for entry in mode.birds:
		if entry.guaranteed_wave == plan.index:
			guaranteed.append(entry.bird)
	for bird_id in guaranteed:
		if plan.spawns.any(func(spawn: Spawn) -> bool: return spawn.bird_id == bird_id):
			continue
		var plain: Array[int] = []
		var other: Array[int] = []
		for i in plan.spawns.size():
			var id := plan.spawns[i].bird_id
			if id in guaranteed:
				continue
			other.append(i)
			if id != mode.golden_bird and Content.bird(id).penalty == 0:
				plain.append(i)
		var slots := plain if not plain.is_empty() else other
		if slots.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, plan.index, "guarantee", bird_id])
		plan.spawns[slots[rng.randi_range(0, slots.size() - 1)]].bird_id = bird_id


## Wave `wave_index` (1..level.waves) of `level`, from the level's fixed seed: the same level
## and index always give the same spawns, shells and speed.
static func campaign(level: LevelSpec, wave_index: int) -> Plan:
	var plan := Plan.new()
	plan.index = wave_index
	plan.boss = level.is_boss() and wave_index == level.waves
	var mix := level.boss.mix if plan.boss else level.mix
	var count := level.boss.birds if plan.boss else level.wave_birds
	var interval := level.boss.spawn_interval if plan.boss else level.spawn_interval
	plan.speed_scale = level.boss.speed_scale if plan.boss else level.speed_scale
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([level.level_seed, wave_index])
	var total := 0
	for entry in mix:
		total += entry.weight
	var hits := 0
	for i in count:
		var spawn := Spawn.new()
		# Every slot rolls for golden first, as in a mode's waves.
		if rng.randf() < level.golden_chance:
			spawn.bird_id = level.golden_bird
		else:
			spawn.bird_id = _pick(mix, rng.randi_range(1, total))
		spawn.time = i * interval
		spawn.bird_seed = rng.randi()
		plan.spawns.append(spawn)
		hits += hits_needed(Content.bird(spawn.bird_id))
	plan.shells = Ammo.pool_size(hits, level.shells_per_hit)
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
