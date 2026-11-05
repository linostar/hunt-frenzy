class_name LevelsFile
extends RefCounted
## data/levels.json's validator: builds LevelSpecs into a ContentSet (data/SCHEMA.md). Each
## level's chapter and birds must already be in it.


## Each level's fields, then every chapter holds exactly its levels
## 1..Content.LEVELS_PER_CHAPTER, and the last of them (and only it) has the boss flock.
static func read(r: ContentReader, data: ContentSet, entries: Array[Dictionary]) -> void:
	# "<chapter>:<index>" -> the level id that holds it.
	var taken: Dictionary[String, String] = {}
	for entry in entries:
		var item := LevelSpec.new()
		item.id = r.begin_entry(entry, ["id", "chapter", "index", "seed", "waves", "wave_birds", "mix", "golden_bird", "golden_chance", "speed_scale", "spawn_interval", "shells_per_hit", "combo_cap", "stars"], data.levels, ["boss"])
		item.chapter = r.read_reference(entry, "chapter", data.chapters, "chapter")
		item.index = r.read_int(entry, "index", 1, Content.LEVELS_PER_CHAPTER)
		item.level_seed = r.read_int(entry, "seed", 0, LevelSpec.SEED_MAX)
		item.waves = r.read_int(entry, "waves", 1, LevelSpec.WAVES_MAX)
		item.wave_birds = r.read_int(entry, "wave_birds", 1, ModeSpec.WAVE_BIRDS_MAX)
		item.mix = ModesFile.read_mix(r, data, entry, "mix", false)
		item.golden_bird = r.read_reference(entry, "golden_bird", data.birds, "bird")
		item.golden_chance = r.read_float(entry, "golden_chance", 0.0, 1.0)
		item.speed_scale = r.read_float(entry, "speed_scale", LevelSpec.SPEED_MIN, ModeSpec.SPEED_CAP_MAX)
		item.spawn_interval = r.read_float(entry, "spawn_interval", ModeSpec.SPAWN_INTERVAL_MIN, ModeSpec.SPAWN_INTERVAL_MAX)
		item.shells_per_hit = r.read_int(entry, "shells_per_hit", 1, ModeSpec.SHELLS_PER_HIT_MAX)
		item.combo_cap = r.read_int(entry, "combo_cap", 1, ModeSpec.COMBO_CAP_MAX)
		item.stars = _stars(r, entry, "stars")
		if entry.has("boss"):
			item.boss = _boss(r, data, entry["boss"])
		if entry.has("index") and not r.failed.has("index"):
			if item.index == Content.LEVELS_PER_CHAPTER and not entry.has("boss"):
				r.error("boss", "missing key (level %d is its chapter's boss level)" % Content.LEVELS_PER_CHAPTER)
			elif item.index != Content.LEVELS_PER_CHAPTER and entry.has("boss"):
				r.error("boss", "level %d is no boss level (only level %d is)" % [item.index, Content.LEVELS_PER_CHAPTER])
			if item.chapter != "":
				var slot := "%s:%d" % [item.chapter, item.index]
				if taken.has(slot):
					r.error("index", "%d of chapter %s is already level %s" % [item.index, item.chapter, taken[slot]])
				else:
					taken[slot] = r.entry
		if item.id != "":
			data.levels[item.id] = item
	if entries.is_empty():
		return
	r.entry = "-"
	for chapter_id in data.chapters:
		for index in range(1, Content.LEVELS_PER_CHAPTER + 1):
			if not taken.has("%s:%d" % [chapter_id, index]):
				r.error("chapter", "%s has no level %d (each chapter has levels 1..%d)" % [chapter_id, index, Content.LEVELS_PER_CHAPTER])


## A level's boss flock: {"birds", "spawn_interval", "speed_scale", "mix"}.
static func _boss(r: ContentReader, data: ContentSet, value: Variant) -> LevelSpec.Boss:
	var boss := LevelSpec.Boss.new()
	if typeof(value) != TYPE_DICTIONARY:
		r.error("boss", "expected Dictionary, got %s" % type_string(typeof(value)))
		return boss
	var part: Dictionary = value
	r.check_keys(part, ["birds", "spawn_interval", "speed_scale", "mix"], "boss")
	boss.birds = r.read_int(part, "birds", 1, ModeSpec.WAVE_BIRDS_MAX, "boss.")
	boss.spawn_interval = r.read_float(part, "spawn_interval", ModeSpec.SPAWN_INTERVAL_MIN, ModeSpec.SPAWN_INTERVAL_MAX, "boss.")
	boss.speed_scale = r.read_float(part, "speed_scale", LevelSpec.SPEED_MIN, ModeSpec.SPEED_CAP_MAX, "boss.")
	boss.mix = ModesFile.read_mix(r, data, part, "mix", false, "boss.")
	return boss


## A level's star thresholds: LevelSpec.STAR_COUNT whole scores of 1..LevelSpec.STAR_SCORE_MAX,
## each above the one before.
static func _stars(r: ContentReader, object: Dictionary, key: String) -> Array[int]:
	var result: Array[int] = []
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY or (object[key] as Array).size() != LevelSpec.STAR_COUNT:
		r.error(key, "expected an array of %d scores (1, 2 and 3 stars), got %s" % [LevelSpec.STAR_COUNT, object[key]])
		return result
	var list: Array = object[key]
	for i in list.size():
		result.append(r.read_int({key: list[i]}, key, 1, LevelSpec.STAR_SCORE_MAX, "", "%s[%d]" % [key, i]))
	if r.failed.has(key):
		return result
	for i in range(1, result.size()):
		if result[i] <= result[i - 1]:
			r.error("%s[%d]" % [key, i], "%d is not above %s[%d] %d (the thresholds rise strictly)" % [result[i], key, i - 1, result[i - 1]])
	return result
