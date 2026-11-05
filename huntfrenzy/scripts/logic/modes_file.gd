class_name ModesFile
extends RefCounted
## data/modes.json's validator: builds ModeSpecs into a ContentSet (data/SCHEMA.md). Each
## mode's birds must already be in it. read_mix also reads a level's mix (LevelsFile).


static func read(r: ContentReader, data: ContentSet, entries: Array[Dictionary]) -> void:
	for entry in entries:
		var item := ModeSpec.new()
		item.id = r.begin_entry(entry, ["id", "name", "birds", "golden_bird", "golden_from_wave", "golden_chance", "start_birds", "bird_growth", "max_birds", "speed_growth", "speed_cap", "spawn_interval", "shells_per_hit", "combo_cap", "rival_steals", "backdrops", "backdrop_waves", "music"], data.modes,
			["escape_limit", "time_limit"])
		item.name = r.read_string(entry, "name", Content.NAME_MAX)
		item.birds = read_mix(r, data, entry, "birds")
		item.golden_bird = r.read_reference(entry, "golden_bird", data.birds, "bird")
		item.golden_from_wave = r.read_int(entry, "golden_from_wave", 1, ModeSpec.WAVE_MAX)
		item.golden_chance = r.read_float(entry, "golden_chance", 0.0, 1.0)
		item.start_birds = r.read_int(entry, "start_birds", 1, ModeSpec.WAVE_BIRDS_MAX)
		item.bird_growth = r.read_int(entry, "bird_growth", 0, ModeSpec.BIRD_GROWTH_MAX)
		item.max_birds = r.read_int(entry, "max_birds", item.start_birds, ModeSpec.WAVE_BIRDS_MAX)
		item.speed_growth = r.read_float(entry, "speed_growth", 0.0, ModeSpec.SPEED_GROWTH_MAX)
		item.speed_cap = r.read_float(entry, "speed_cap", 1.0, ModeSpec.SPEED_CAP_MAX)
		item.spawn_interval = r.read_float(entry, "spawn_interval", ModeSpec.SPAWN_INTERVAL_MIN, ModeSpec.SPAWN_INTERVAL_MAX)
		item.shells_per_hit = r.read_int(entry, "shells_per_hit", 1, ModeSpec.SHELLS_PER_HIT_MAX)
		item.combo_cap = r.read_int(entry, "combo_cap", 1, ModeSpec.COMBO_CAP_MAX)
		# How a run ends: exactly one of escape_limit (Endless: at that many lost birds) and
		# time_limit (Time Attack: after that many seconds); the other does not apply.
		if entry.has("escape_limit") and entry.has("time_limit"):
			r.error("time_limit", "not allowed with escape_limit (a mode's run ends at escape_limit lost birds or after time_limit seconds, not both)")
		elif not entry.has("escape_limit") and not entry.has("time_limit"):
			r.error("escape_limit", "missing key (a mode needs escape_limit or time_limit: how its run ends)")
		if entry.has("escape_limit"):
			item.escape_limit = r.read_int(entry, "escape_limit", 1, ModeSpec.ESCAPE_LIMIT_MAX)
		if entry.has("time_limit"):
			item.time_limit = r.read_float(entry, "time_limit", ModeSpec.TIME_LIMIT_MIN, ModeSpec.TIME_LIMIT_MAX)
		if entry.has("rival_steals"):
			item.rival_steals = r.read_bool(entry, "rival_steals")
		item.stages = _stages(r, entry, "backdrops")
		item.backdrop_waves = r.read_int(entry, "backdrop_waves", 1, ModeSpec.WAVE_MAX)
		item.music = r.read_music(entry, "music")
		if item.id != "":
			data.modes[item.id] = item


## A wave mix: a non-empty array of {"bird", "from_wave", "weight"} objects, each with an
## optional "guaranteed_wave" at or after its from_wave (a mode's), or
## of {"bird", "weight"} objects when `with_from_wave` is false (a level's, every bird from
## wave 1), each bird a known id at most once, at least one of them from wave 1 (so every
## wave has a bird to pick). `prefix` names the object it is in ("boss.").
static func read_mix(r: ContentReader, data: ContentSet, object: Dictionary, key: String, with_from_wave := true, prefix := "") -> Array[ModeSpec.Entry]:
	var result: Array[ModeSpec.Entry] = []
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY:
		r.error(prefix + key, "expected Array, got %s" % type_string(typeof(object[key])))
		return result
	var list: Array = object[key]
	if list.is_empty():
		r.error(prefix + key, "is empty")
		return result
	var seen: Dictionary[String, int] = {}
	for i in list.size():
		var field := "%s%s[%d]" % [prefix, key, i]
		if typeof(list[i]) != TYPE_DICTIONARY:
			r.error(field, "expected Dictionary, got %s" % type_string(typeof(list[i])))
			continue
		var part: Dictionary = list[i]
		var keys: Array[String] = ["bird", "weight"]
		if with_from_wave:
			keys.insert(1, "from_wave")
		for name in keys:
			if not part.has(name):
				r.error("%s.%s" % [field, name], "missing key")
		for name: Variant in part:
			if not str(name) in keys and not (with_from_wave and str(name) == "guaranteed_wave"):
				r.error("%s.%s" % [field, name], "unknown key")
		var entry := ModeSpec.Entry.new()
		entry.bird = r.read_reference(part, "bird", data.birds, "bird", field + ".")
		if with_from_wave:
			entry.from_wave = r.read_int(part, "from_wave", 1, ModeSpec.WAVE_MAX, field + ".")
			if part.has("guaranteed_wave"):
				entry.guaranteed_wave = r.read_int(part, "guaranteed_wave", 1, ModeSpec.WAVE_MAX, field + ".")
				# Compared only when both read cleanly, so a fallback value is never blamed.
				if r.int_ok(part, "guaranteed_wave", 1, ModeSpec.WAVE_MAX) and r.int_ok(part, "from_wave", 1, ModeSpec.WAVE_MAX) and entry.guaranteed_wave < entry.from_wave:
					r.error(field + ".guaranteed_wave", "%d is before from_wave %d (the bird is not in the mix yet)" % [entry.guaranteed_wave, entry.from_wave])
		entry.weight = r.read_int(part, "weight", 1, ModeSpec.WEIGHT_MAX, field + ".")
		if entry.bird != "":
			if seen.has(entry.bird):
				r.error(field + ".bird", "'%s' is already in the mix (%s%s[%d])" % [entry.bird, prefix, key, seen[entry.bird]])
				continue
			seen[entry.bird] = i
			result.append(entry)
	if not result.is_empty() and not result.any(func(e: ModeSpec.Entry) -> bool: return e.from_wave == 1):
		r.error(prefix + key, "no bird from wave 1 (wave 1 would have nothing to spawn)")
	return result


## A mode's looks: a non-empty array of {"backdrop", "weather"} objects, each a backdrop
## with its art and a weather of Content.WEATHERS.
static func _stages(r: ContentReader, object: Dictionary, key: String) -> Array[ModeSpec.Stage]:
	var result: Array[ModeSpec.Stage] = []
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY:
		r.error(key, "expected Array, got %s" % type_string(typeof(object[key])))
		return result
	var list: Array = object[key]
	if list.is_empty():
		r.error(key, "is empty")
	for i in list.size():
		var field := "%s[%d]" % [key, i]
		if typeof(list[i]) != TYPE_DICTIONARY:
			r.error(field, "expected Dictionary, got %s" % type_string(typeof(list[i])))
			continue
		var part: Dictionary = list[i]
		r.check_keys(part, ["backdrop", "weather"], field)
		var stage := ModeSpec.Stage.new()
		stage.backdrop = r.read_backdrop(part, "backdrop", field + ".")
		stage.weather = r.read_enum(part, "weather", Content.WEATHERS, field + ".")
		result.append(stage)
	return result
