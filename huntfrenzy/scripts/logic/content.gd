class_name Content
extends RefCounted
## All game content: the JSON in res://data/ parsed into typed resources (ChapterSpec,
## BirdSpec, ModeSpec, LevelSpec, RivalLines). Static only. The data is loaded once, lazily, on the first call of any
## public function (the title screen's errors() call does it at boot); reload() and
## load_texts() replace it (tests).
## Every problem (unreadable file, bad JSON, a file with no entries, missing or unknown key,
## wrong type, non-integer int, out-of-range value, unknown enum value, duplicate id,
## unknown reference, a sprite missing a frame, a hitbox outside its sprite or crossing
## itself, a split field without its pair, a wave mix with nothing from wave 1, a mode with
## both or neither of escape_limit and time_limit, a missing,
## unknown or empty rival line category, a rival line too long for the bubble, not exactly
## CHAPTER_COUNT chapters, a chapter whose rival_linger_scale rises above the one before's,
## a chapter without exactly its levels 1..LEVELS_PER_CHAPTER, a boss on any level but the
## last of its chapter, star thresholds that do not rise, and I13: a bird whose scaled
## linger_time + the rival's aim_time does not end before it flees) is
## collected in errors() as "data/<file> [<entry id>] <field>: <problem>" (rival_lines.json,
## a single object, names the line category as the entry, "-" for its top-level fields) and reported with
## push_error, all of them, not just the first. Entries with problems are still loaded as
## far as they parse (bad fields keep their resource defaults or a fallback). A check that
## depends on a field that already failed is skipped (the hitbox against a bad size, I13
## against a bad flee_time, linger_time, aim_time or rival_linger_scale, the scale order
## against a bad scale, the boss rule against a bad index), so a fallback value is never blamed.
## The title screen disables Play while errors() is non-empty, so no default ever reaches a run.

const DATA_DIR := "res://data/"
## Load order: birds reference chapters, modes and levels reference birds (levels also
## chapters); I13 needs the birds, the modes, the chapters and the rival's aim_time, so it is
## checked once rival_lines.json is loaded.
const FILES: Array[String] = ["chapters.json", "birds.json", "modes.json", "levels.json", "rival_lines.json"]
const NAME_MAX := 26
## Flight patterns (Flight).
const PATTERNS: Array[String] = ["rise", "zigzag"]
## The campaign: exactly CHAPTER_COUNT chapters (dawn, noon, sunset, night) of exactly
## LEVELS_PER_CHAPTER levels each, the last one the chapter's boss level.
const CHAPTER_COUNT := 4
const LEVELS_PER_CHAPTER := 6
## A chapter's weather ids (placeholder until the art pass draws them).
const WEATHERS: Array[String] = ["mist", "wind", "rain", "snow"]
## A chapter's sky tint: "#rrggbb".
const COLOR_PATTERN := "^#[0-9a-f]{6}$"
## A level's star thresholds: STAR_COUNT final scores, each 1..STAR_SCORE_MAX.
const STAR_COUNT := 3
const STAR_SCORE_MAX := 10000000
## A level's fixed seed lies in 0..SEED_MAX, its waves in 1..LEVEL_WAVES_MAX, its speed
## scales in LEVEL_SPEED_MIN..SPEED_CAP_MAX.
const SEED_MAX := 2147483647
const LEVEL_WAVES_MAX := 20
const LEVEL_SPEED_MIN := 0.5
const HP_MAX := 5
const SPLIT_COUNT_MAX := 4
const SPEED_MAX := 1000.0
const WOBBLE_MAX := 100.0
const WOBBLE_HZ_MAX := 5.0
const FLEE_TIME_MAX := 60.0
## A bird's linger_time lies in LINGER_TIME_MIN..FLEE_TIME_MAX seconds (always > 0).
const LINGER_TIME_MIN := 0.1
## The rival aims for AIM_TIME_MIN..AIM_TIME_MAX seconds (main plan AC 17: a visible cue of
## at least 0.5 s), and waits 0..COOLDOWN_MAX seconds between heckles.
const AIM_TIME_MIN := 0.5
const AIM_TIME_MAX := 10.0
const COOLDOWN_MAX := 60.0
## The longest rival line: two lines of Play's speech bubble.
const RIVAL_LINE_MAX := 40
const POINTS_MAX := 100000
## A bird's drawn size lies in SIZE_MIN..SIZE_MAX base units on each axis.
const SIZE_MIN := 8.0
const SIZE_MAX := 400.0
const HITBOX_MIN_POINTS := 3
const WAVE_BIRDS_MAX := 30
const BIRD_GROWTH_MAX := 10
const SPEED_GROWTH_MAX := 1.0
const SPEED_CAP_MAX := 5.0
const SPAWN_INTERVAL_MIN := 0.1
const SPAWN_INTERVAL_MAX := 10.0
const SHELLS_PER_HIT_MAX := 10
const COMBO_CAP_MAX := 20
const ESCAPE_LIMIT_MAX := 100
## A timed mode's run lasts TIME_LIMIT_MIN..TIME_LIMIT_MAX seconds.
const TIME_LIMIT_MIN := 10.0
const TIME_LIMIT_MAX := 600.0
## The latest wave a mode's bird or golden bird can unlock in, and the largest mix weight.
const WAVE_MAX := 1000
const WEIGHT_MAX := 100

## Tests set quiet_errors to assert on expected errors (load errors and unknown-id lookups)
## without failing the log check.
static var quiet_errors := false

static var _loaded := false
static var _errors: Array[String] = []
static var _chapters: Dictionary[String, ChapterSpec] = {}
static var _birds: Dictionary[String, BirdSpec] = {}
static var _modes: Dictionary[String, ModeSpec] = {}
static var _levels: Dictionary[String, LevelSpec] = {}
static var _rival_lines := RivalLines.new()
## The top-level fields of the current entry that already have an error ("size" for
## "size[0]" too); checks that depend on one of them are skipped, so a field's fallback
## value is never blamed. Cleared at each bird and mode entry and at each file.
static var _failed: Dictionary[String, bool] = {}
## Ids of the birds whose flee_time or linger_time failed, and of the chapters whose
## rival_linger_scale failed, which I13 skips.
static var _bad_timing: Dictionary[String, bool] = {}
static var _bad_scale: Dictionary[String, bool] = {}
## The file and entry the loader is reading, for error messages.
static var _file := ""
static var _entry := ""
static var _snake_case := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
static var _color_pattern := RegEx.create_from_string(COLOR_PATTERN)


## Every content problem found by the last load, oldest first. Empty means the data is valid.
static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors.duplicate()


## Reads every file in FILES from DATA_DIR and replaces the loaded content.
static func reload() -> void:
	_reset()
	var texts: Dictionary[String, String] = {}
	for file in FILES:
		var text := FileAccess.get_file_as_string(DATA_DIR + file)
		var open_error := FileAccess.get_open_error()
		if open_error != OK:
			_begin_file(file)
			_error("(file)", "cannot be read: %s" % error_string(open_error))
			continue
		texts[file] = text
	_load(texts)


## Replaces the loaded content with `texts` (file name in FILES -> JSON text). Tests use it
## to feed malformed data; a file missing from `texts` is reported as missing.
static func load_texts(texts: Dictionary[String, String]) -> void:
	_reset()
	for file in FILES:
		if not texts.has(file):
			_begin_file(file)
			_error("(file)", "missing")
	_load(texts)


## The bird type `id`, or null (with push_error) if there is none.
static func bird(id: String) -> BirdSpec:
	_ensure_loaded()
	return _lookup(_birds, id, "bird") as BirdSpec


## The mode `id`, or null (with push_error) if there is none.
static func mode(id: String) -> ModeSpec:
	_ensure_loaded()
	return _lookup(_modes, id, "mode") as ModeSpec


## The chapter `id`, or null (with push_error) if there is none.
static func chapter(id: String) -> ChapterSpec:
	_ensure_loaded()
	return _lookup(_chapters, id, "chapter") as ChapterSpec


## The level `id`, or null (with push_error) if there is none.
static func level(id: String) -> LevelSpec:
	_ensure_loaded()
	return _lookup(_levels, id, "level") as LevelSpec


## Whether `id` is a level of levels.json (no error when it is not).
static func has_level(id: String) -> bool:
	_ensure_loaded()
	return _levels.has(id)


## Every chapter, in data (campaign) order.
static func chapters() -> Array[ChapterSpec]:
	_ensure_loaded()
	var result: Array[ChapterSpec] = []
	result.assign(_chapters.values())
	return result


## Every level, in data order (Campaign.levels() gives campaign order).
static func levels() -> Array[LevelSpec]:
	_ensure_loaded()
	var result: Array[LevelSpec] = []
	result.assign(_levels.values())
	return result


## Every bird type, in data order.
static func birds() -> Array[BirdSpec]:
	_ensure_loaded()
	var result: Array[BirdSpec] = []
	result.assign(_birds.values())
	return result


## The rival's timing and heckle lines.
static func rival_lines() -> RivalLines:
	_ensure_loaded()
	return _rival_lines


## Every mode, in data order.
static func modes() -> Array[ModeSpec]:
	_ensure_loaded()
	var result: Array[ModeSpec] = []
	result.assign(_modes.values())
	return result


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


static func _reset() -> void:
	_loaded = true
	_errors.clear()
	_chapters.clear()
	_birds.clear()
	_modes.clear()
	_levels.clear()
	_rival_lines = RivalLines.new()
	_bad_timing.clear()
	_bad_scale.clear()


static func _load(texts: Dictionary[String, String]) -> void:
	for file in FILES:
		# A file absent from `texts` was already reported by reload() or load_texts().
		if not texts.has(file):
			continue
		_begin_file(file)
		match file:
			"chapters.json":
				_load_chapters(_parse_entries(texts[file]))
			"birds.json":
				_load_birds(_parse_entries(texts[file]))
			"modes.json":
				_load_modes(_parse_entries(texts[file]))
			"levels.json":
				_load_levels(_parse_entries(texts[file]))
			"rival_lines.json":
				_load_rival_lines(_parse_object(texts[file]))
	var line_count := 0
	for category in _rival_lines.lines:
		line_count += _rival_lines.lines[category].size()
	print("[Content] Loaded %d chapters, %d birds, %d modes, %d levels, %d rival lines: %d problem(s)" % [_chapters.size(), _birds.size(), _modes.size(), _levels.size(), line_count, _errors.size()])


## chapters.json: exactly CHAPTER_COUNT chapters in campaign order, each rival_linger_scale
## in (0, 1] and at most the one before's (the rival never gets slower).
static func _load_chapters(entries: Array[Dictionary]) -> void:
	var previous: ChapterSpec = null
	for entry in entries:
		var item := ChapterSpec.new()
		item.id = _begin_entry(entry, ["id", "name", "sky_tint", "weather", "rival_linger_scale"], _chapters)
		item.name = _string(entry, "name", NAME_MAX)
		item.sky_tint = _color(entry, "sky_tint")
		item.weather = _enum(entry, "weather", WEATHERS)
		item.rival_linger_scale = _scale(entry, "rival_linger_scale")
		if _failed.has("rival_linger_scale"):
			_bad_scale[_entry] = true
		else:
			if previous != null and item.rival_linger_scale > previous.rival_linger_scale:
				_error("rival_linger_scale", "%s is above %s's %s (the rival never gets slower: a chapter's scale is at most the one before's)" % [item.rival_linger_scale, previous.id, previous.rival_linger_scale])
			previous = item
		if item.id != "":
			_chapters[item.id] = item
	if not entries.is_empty() and _chapters.size() != CHAPTER_COUNT:
		_entry = "-"
		_error("(file)", "has %d chapters, needs exactly %d" % [_chapters.size(), CHAPTER_COUNT])


## levels.json: each level's fields, then every chapter holds exactly its levels
## 1..LEVELS_PER_CHAPTER, and the last of them (and only it) has the boss flock.
static func _load_levels(entries: Array[Dictionary]) -> void:
	# "<chapter>:<index>" -> the level id that holds it.
	var taken: Dictionary[String, String] = {}
	for entry in entries:
		var item := LevelSpec.new()
		item.id = _begin_entry(entry, ["id", "chapter", "index", "seed", "waves", "wave_birds", "mix", "golden_bird", "golden_chance", "speed_scale", "spawn_interval", "shells_per_hit", "combo_cap", "stars"], _levels, ["boss"])
		item.chapter = _reference(entry, "chapter", _chapters, "chapter")
		item.index = _int(entry, "index", 1, LEVELS_PER_CHAPTER)
		item.level_seed = _int(entry, "seed", 0, SEED_MAX)
		item.waves = _int(entry, "waves", 1, LEVEL_WAVES_MAX)
		item.wave_birds = _int(entry, "wave_birds", 1, WAVE_BIRDS_MAX)
		item.mix = _mix(entry, "mix", false)
		item.golden_bird = _reference(entry, "golden_bird", _birds, "bird")
		item.golden_chance = _float(entry, "golden_chance", 0.0, 1.0)
		item.speed_scale = _float(entry, "speed_scale", LEVEL_SPEED_MIN, SPEED_CAP_MAX)
		item.spawn_interval = _float(entry, "spawn_interval", SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		item.shells_per_hit = _int(entry, "shells_per_hit", 1, SHELLS_PER_HIT_MAX)
		item.combo_cap = _int(entry, "combo_cap", 1, COMBO_CAP_MAX)
		item.stars = _stars(entry, "stars")
		if entry.has("boss"):
			item.boss = _boss(entry["boss"])
		if entry.has("index") and not _failed.has("index"):
			if item.index == LEVELS_PER_CHAPTER and not entry.has("boss"):
				_error("boss", "missing key (level %d is its chapter's boss level)" % LEVELS_PER_CHAPTER)
			elif item.index != LEVELS_PER_CHAPTER and entry.has("boss"):
				_error("boss", "level %d is no boss level (only level %d is)" % [item.index, LEVELS_PER_CHAPTER])
			if item.chapter != "":
				var slot := "%s:%d" % [item.chapter, item.index]
				if taken.has(slot):
					_error("index", "%d of chapter %s is already level %s" % [item.index, item.chapter, taken[slot]])
				else:
					taken[slot] = _entry
		if item.id != "":
			_levels[item.id] = item
	if entries.is_empty():
		return
	_entry = "-"
	for chapter_id in _chapters:
		for index in range(1, LEVELS_PER_CHAPTER + 1):
			if not taken.has("%s:%d" % [chapter_id, index]):
				_error("chapter", "%s has no level %d (each chapter has levels 1..%d)" % [chapter_id, index, LEVELS_PER_CHAPTER])


## A level's boss flock: {"birds", "spawn_interval", "speed_scale", "mix"}.
static func _boss(value: Variant) -> LevelSpec.Boss:
	var boss := LevelSpec.Boss.new()
	if typeof(value) != TYPE_DICTIONARY:
		_error("boss", "expected Dictionary, got %s" % type_string(typeof(value)))
		return boss
	var part: Dictionary = value
	var keys: Array[String] = ["birds", "spawn_interval", "speed_scale", "mix"]
	for name in keys:
		if not part.has(name):
			_error("boss." + name, "missing key")
	for name: Variant in part:
		if not str(name) in keys:
			_error("boss.%s" % name, "unknown key")
	boss.birds = _int(part, "birds", 1, WAVE_BIRDS_MAX, "boss.")
	boss.spawn_interval = _float(part, "spawn_interval", SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX, "boss.")
	boss.speed_scale = _float(part, "speed_scale", LEVEL_SPEED_MIN, SPEED_CAP_MAX, "boss.")
	boss.mix = _mix(part, "mix", false, "boss.")
	return boss


## A level's star thresholds: STAR_COUNT whole scores of 1..STAR_SCORE_MAX, each above the one before.
static func _stars(object: Dictionary, key: String) -> Array[int]:
	var result: Array[int] = []
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY or (object[key] as Array).size() != STAR_COUNT:
		_error(key, "expected an array of %d scores (1, 2 and 3 stars), got %s" % [STAR_COUNT, object[key]])
		return result
	var list: Array = object[key]
	for i in list.size():
		result.append(_int({key: list[i]}, key, 1, STAR_SCORE_MAX, "", "%s[%d]" % [key, i]))
	if _failed.has(key):
		return result
	for i in range(1, result.size()):
		if result[i] <= result[i - 1]:
			_error("%s[%d]" % [key, i], "%d is not above %s[%d] %d (the thresholds rise strictly)" % [result[i], key, i - 1, result[i - 1]])
	return result


## A "#rrggbb" colour.
static func _color(object: Dictionary, key: String) -> Color:
	if not object.has(key):
		return Color.WHITE
	if typeof(object[key]) != TYPE_STRING:
		_error(key, "expected String, got %s" % type_string(typeof(object[key])))
		return Color.WHITE
	if _color_pattern.search(object[key]) == null:
		_error(key, "'%s' is not a colour \"#rrggbb\" (lowercase hex)" % object[key])
		return Color.WHITE
	return Color.html(object[key])


## A scale in (0, 1]: more than 0, at most 1.
static func _scale(object: Dictionary, key: String) -> float:
	if not object.has(key):
		return 1.0
	var value: Variant = object[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_error(key, "expected float, got %s" % type_string(typeof(value)))
		return 1.0
	var number: float = value
	if number <= 0.0 or number > 1.0:
		_error(key, "%s is outside (0.0, 1.0]" % number)
		return 1.0
	return number


static func _load_birds(entries: Array[Dictionary]) -> void:
	var splits: Dictionary[String, String] = {}
	for entry in entries:
		var item := BirdSpec.new()
		item.id = _begin_entry(entry, ["id", "name", "chapter", "pattern", "speed", "wobble", "wobble_hz", "flee_time", "linger_time", "points", "hp", "sprite", "size", "hitbox"], _birds,
			["splits_into", "split_count", "penalty", "escape_counts"])
		item.name = _string(entry, "name", NAME_MAX)
		item.chapter = _reference(entry, "chapter", _chapters, "chapter")
		item.pattern = _enum(entry, "pattern", PATTERNS)
		item.speed = _float(entry, "speed", 1.0, SPEED_MAX)
		item.wobble = _float(entry, "wobble", 0.0, WOBBLE_MAX)
		item.wobble_hz = _float(entry, "wobble_hz", 0.0, WOBBLE_HZ_MAX)
		item.flee_time = _float(entry, "flee_time", 0.1, FLEE_TIME_MAX)
		item.linger_time = _float(entry, "linger_time", LINGER_TIME_MIN, FLEE_TIME_MAX)
		item.points = _int(entry, "points", 0, POINTS_MAX)
		item.hp = _int(entry, "hp", 1, HP_MAX)
		item.sprite = _string(entry, "sprite", NAME_MAX)
		if item.sprite != "":
			for frame in item.frames():
				if not ResourceLoader.exists(item.texture_path(frame)):
					_error("sprite", "unknown sprite '%s' (no %s)" % [item.sprite, item.texture_path(frame)])
		item.size = _vector(entry, "size", SIZE_MIN, SIZE_MAX)
		item.hitbox = _hitbox(entry, item.size)
		# splits_into and split_count come together (the splitter); the reference is
		# checked once every bird is loaded.
		if entry.has("splits_into") != entry.has("split_count"):
			var missing := "split_count" if entry.has("splits_into") else "splits_into"
			_error(missing, "missing key (required with %s)" % ("splits_into" if missing == "split_count" else "split_count"))
		item.splits_into = _string(entry, "splits_into", NAME_MAX)
		if entry.has("split_count"):
			item.split_count = _int(entry, "split_count", 1, SPLIT_COUNT_MAX)
		if entry.has("penalty"):
			item.penalty = _int(entry, "penalty", 1, POINTS_MAX)
		if entry.has("escape_counts"):
			item.escape_counts = _bool(entry, "escape_counts")
		if item.splits_into != "":
			splits[_entry] = item.splits_into
		if item.id != "":
			_birds[item.id] = item
			if _failed.has("flee_time") or _failed.has("linger_time"):
				_bad_timing[item.id] = true
	for from: String in splits:
		_entry = from
		if not _birds.has(splits[from]):
			_error("splits_into", "unknown bird id '%s'" % splits[from])


static func _load_modes(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var item := ModeSpec.new()
		item.id = _begin_entry(entry, ["id", "name", "birds", "golden_bird", "golden_from_wave", "golden_chance", "start_birds", "bird_growth", "max_birds", "speed_growth", "speed_cap", "spawn_interval", "shells_per_hit", "combo_cap", "rival_steals"], _modes,
			["escape_limit", "time_limit"])
		item.name = _string(entry, "name", NAME_MAX)
		item.birds = _mix(entry, "birds")
		item.golden_bird = _reference(entry, "golden_bird", _birds, "bird")
		item.golden_from_wave = _int(entry, "golden_from_wave", 1, WAVE_MAX)
		item.golden_chance = _float(entry, "golden_chance", 0.0, 1.0)
		item.start_birds = _int(entry, "start_birds", 1, WAVE_BIRDS_MAX)
		item.bird_growth = _int(entry, "bird_growth", 0, BIRD_GROWTH_MAX)
		item.max_birds = _int(entry, "max_birds", item.start_birds, WAVE_BIRDS_MAX)
		item.speed_growth = _float(entry, "speed_growth", 0.0, SPEED_GROWTH_MAX)
		item.speed_cap = _float(entry, "speed_cap", 1.0, SPEED_CAP_MAX)
		item.spawn_interval = _float(entry, "spawn_interval", SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		item.shells_per_hit = _int(entry, "shells_per_hit", 1, SHELLS_PER_HIT_MAX)
		item.combo_cap = _int(entry, "combo_cap", 1, COMBO_CAP_MAX)
		# How a run ends: exactly one of escape_limit (Endless: at that many lost birds) and
		# time_limit (Time Attack: after that many seconds); the other does not apply.
		if entry.has("escape_limit") and entry.has("time_limit"):
			_error("time_limit", "not allowed with escape_limit (a mode's run ends at escape_limit lost birds or after time_limit seconds, not both)")
		elif not entry.has("escape_limit") and not entry.has("time_limit"):
			_error("escape_limit", "missing key (a mode needs escape_limit or time_limit: how its run ends)")
		if entry.has("escape_limit"):
			item.escape_limit = _int(entry, "escape_limit", 1, ESCAPE_LIMIT_MAX)
		if entry.has("time_limit"):
			item.time_limit = _float(entry, "time_limit", TIME_LIMIT_MIN, TIME_LIMIT_MAX)
		if entry.has("rival_steals"):
			item.rival_steals = _bool(entry, "rival_steals")
		if item.id != "":
			_modes[item.id] = item


## rival_lines.json: {"aim_time", "cooldown", "lines": {<category>: [line, ...]}}, every
## category of RivalLines.CATEGORIES with a non-empty list of 1..RIVAL_LINE_MAX character
## strings. Errors name the category as the entry ("-" for the top-level fields). Then I13:
## every bird but the decoy (never stolen) ends the rival's cue before it flees.
static func _load_rival_lines(object: Dictionary) -> void:
	if object.is_empty():
		return
	var keys: Array[String] = ["aim_time", "cooldown", "lines"]
	for key in keys:
		if not object.has(key):
			_error(key, "missing key")
	for key: Variant in object:
		if not str(key) in keys:
			_error(str(key), "unknown key")
	_rival_lines.aim_time = _float(object, "aim_time", AIM_TIME_MIN, AIM_TIME_MAX)
	var aim_ok := not _failed.has("aim_time")
	_rival_lines.cooldown = _float(object, "cooldown", 0.0, COOLDOWN_MAX)
	if object.has("lines"):
		if typeof(object["lines"]) != TYPE_DICTIONARY:
			_error("lines", "expected Dictionary, got %s" % type_string(typeof(object["lines"])))
		else:
			var categories: Dictionary = object["lines"]
			for category in RivalLines.CATEGORIES:
				_entry = category
				if not categories.has(category):
					_error("lines", "missing category")
					continue
				_rival_lines.lines[category] = _lines(categories[category])
			for category: Variant in categories:
				if not str(category) in RivalLines.CATEGORIES:
					_entry = str(category)
					_error("lines", "unknown category (expected one of %s)" % [RivalLines.CATEGORIES])
	if aim_ok:
		_check_linger(_rival_lines.aim_time)


## A category's lines: a non-empty array of strings of 1..RIVAL_LINE_MAX characters.
static func _lines(value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if typeof(value) != TYPE_ARRAY:
		_error("lines", "expected Array, got %s" % type_string(typeof(value)))
		return result
	var list: Array = value
	if list.is_empty():
		_error("lines", "is empty")
	for i in list.size():
		var field := "lines[%d]" % i
		if typeof(list[i]) != TYPE_STRING:
			_error(field, "expected String, got %s" % type_string(typeof(list[i])))
			continue
		var line: String = list[i]
		if line.is_empty() or line.length() > RIVAL_LINE_MAX:
			_error(field, "length %d is outside 1..%d (the speech bubble's two lines)" % [line.length(), RIVAL_LINE_MAX])
		result.append(line)
	return result


## I13: every bird the rival can steal (all but the decoy) has every linger the rival uses
## plus aim_time under its flee_time, so every cue can finish before the bird flees on its
## own. The rival waits linger_time x 1 in a mode with rival_steals and linger_time x the
## chapter's rival_linger_scale in each chapter (the campaign always steals). One line per
## bird, at the largest failing scale, naming every mode and chapter that fails. A bird
## whose flee_time or linger_time already has an error is skipped, and so is a chapter whose
## scale has one (its fallback value would be blamed instead).
static func _check_linger(aim_time: float) -> void:
	var scales: Dictionary[String, float] = {}
	for mode_spec: ModeSpec in _modes.values():
		if mode_spec.rival_steals:
			scales[mode_spec.id] = 1.0
	for chapter_spec: ChapterSpec in _chapters.values():
		if not _bad_scale.has(chapter_spec.id):
			scales[chapter_spec.id] = chapter_spec.rival_linger_scale
	_file = "data/birds.json"
	for spec: BirdSpec in _birds.values():
		if spec.penalty > 0 or _bad_timing.has(spec.id):
			continue
		_entry = spec.id
		var failing := PackedStringArray()
		var worst := 0.0
		for where in scales:
			if spec.linger_time * scales[where] + aim_time >= spec.flee_time:
				failing.append(where)
				worst = maxf(worst, scales[where])
		if not failing.is_empty():
			_error("linger_time", "%s x %s (%s) + aim_time %s is not under flee_time %s (I13: the rival's cue must end before the bird flees)" % [spec.linger_time, worst, ", ".join(failing), aim_time, spec.flee_time])
	_file = "data/rival_lines.json"


## A wave mix: a non-empty array of {"bird", "from_wave", "weight"} objects (a mode's), or
## of {"bird", "weight"} objects when `with_from_wave` is false (a level's, every bird from
## wave 1), each bird a known id at most once, at least one of them from wave 1 (so every
## wave has a bird to pick). `prefix` names the object it is in ("boss.").
static func _mix(object: Dictionary, key: String, with_from_wave := true, prefix := "") -> Array[ModeSpec.Entry]:
	var result: Array[ModeSpec.Entry] = []
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY:
		_error(prefix + key, "expected Array, got %s" % type_string(typeof(object[key])))
		return result
	var list: Array = object[key]
	if list.is_empty():
		_error(prefix + key, "is empty")
		return result
	var seen: Dictionary[String, int] = {}
	for i in list.size():
		var field := "%s%s[%d]" % [prefix, key, i]
		if typeof(list[i]) != TYPE_DICTIONARY:
			_error(field, "expected Dictionary, got %s" % type_string(typeof(list[i])))
			continue
		var part: Dictionary = list[i]
		var keys: Array[String] = ["bird", "weight"]
		if with_from_wave:
			keys.insert(1, "from_wave")
		for name in keys:
			if not part.has(name):
				_error("%s.%s" % [field, name], "missing key")
		for name: Variant in part:
			if not str(name) in keys:
				_error("%s.%s" % [field, name], "unknown key")
		var entry := ModeSpec.Entry.new()
		entry.bird = _reference(part, "bird", _birds, "bird", field + ".")
		if with_from_wave:
			entry.from_wave = _int(part, "from_wave", 1, WAVE_MAX, field + ".")
		entry.weight = _int(part, "weight", 1, WEIGHT_MAX, field + ".")
		if entry.bird != "":
			if seen.has(entry.bird):
				_error(field + ".bird", "'%s' is already in the mix (%s%s[%d])" % [entry.bird, prefix, key, seen[entry.bird]])
				continue
			seen[entry.bird] = i
			result.append(entry)
	if not result.is_empty() and not result.any(func(e: ModeSpec.Entry) -> bool: return e.from_wave == 1):
		_error(prefix + key, "no bird from wave 1 (wave 1 would have nothing to spawn)")
	return result


static func _parse_entries(text: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var json := JSON.new()
	if json.parse(text) != OK:
		_error("(file)", "JSON parse error at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return entries
	if typeof(json.data) != TYPE_ARRAY:
		_error("(file)", "top level must be an array, got %s" % type_string(typeof(json.data)))
		return entries
	var list: Array = json.data
	if list.is_empty():
		_error("(file)", "has no entries")
	for i in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY:
			entries.append(list[i])
		else:
			_entry = "#%d" % i
			_error("(entry)", "expected Dictionary, got %s" % type_string(typeof(list[i])))
	return entries


## Starts reading `entry`: sets the error context and checks its keys and id. Returns the id
## when it is valid and not yet in `seen`, else "" (the entry is then validated but not stored).
## `optional` keys may be absent.
static func _begin_entry(entry: Dictionary, required: Array[String], seen: Dictionary, optional: Array[String] = []) -> String:
	var id := ""
	if typeof(entry.get("id")) == TYPE_STRING:
		id = entry["id"]
	_entry = id if id != "" else "(no id)"
	_failed.clear()
	for key in required:
		if not entry.has(key):
			_error(key, "missing key")
	for key: Variant in entry:
		if not str(key) in required and not str(key) in optional:
			_error(str(key), "unknown key")
	if not entry.has("id"):
		return ""
	if typeof(entry["id"]) != TYPE_STRING:
		_error("id", "expected String, got %s" % type_string(typeof(entry["id"])))
		return ""
	if _snake_case.search(id) == null:
		_error("id", "'%s' is not snake_case" % id)
		return ""
	if seen.has(id):
		_error("id", "duplicate id '%s'" % id)
		return ""
	return id


## The top-level object of a single-object file (rival_lines.json); {} after reporting
## a parse error or another top-level type.
static func _parse_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		_error("(file)", "JSON parse error at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_error("(file)", "top level must be an object, got %s" % type_string(typeof(json.data)))
		return {}
	var object: Dictionary = json.data
	if object.is_empty():
		_error("(file)", "has no fields")
	return object


static func _string(object: Dictionary, key: String, max_length: int) -> String:
	if not object.has(key):
		return ""
	var value: Variant = object[key]
	if typeof(value) != TYPE_STRING:
		_error(key, "expected String, got %s" % type_string(typeof(value)))
		return ""
	var text: String = value
	if text.is_empty() or text.length() > max_length:
		_error(key, "length %d is outside 1..%d" % [text.length(), max_length])
	return text


## `prefix` names the object inside the entry ("birds[0].") in error messages; `name`, when
## set, replaces the whole field name ("stars[1]").
static func _int(object: Dictionary, key: String, low: int, high: int, prefix := "", name := "") -> int:
	if not object.has(key):
		return low
	var field := name if name != "" else prefix + key
	var value: Variant = object[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_error(field, "expected int, got %s" % type_string(typeof(value)))
		return low
	var number: float = value
	if number != floorf(number):
		_error(field, "expected int, got %s" % value)
		return low
	if number < low or number > high:
		_error(field, "%d is outside %d..%d" % [int(number), low, high])
		return low
	return int(number)


static func _bool(object: Dictionary, key: String) -> bool:
	if typeof(object[key]) != TYPE_BOOL:
		_error(key, "expected bool, got %s" % type_string(typeof(object[key])))
		return false
	return object[key]


## A string that is one of `allowed`.
static func _enum(object: Dictionary, key: String, allowed: Array[String]) -> String:
	if not object.has(key):
		return ""
	if typeof(object[key]) != TYPE_STRING:
		_error(key, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	if not str(object[key]) in allowed:
		_error(key, "'%s' is not one of %s" % [object[key], allowed])
		return ""
	return object[key]


## A string id that is a key of `known` ("" when it is missing, mistyped or unknown).
static func _reference(object: Dictionary, key: String, known: Dictionary, kind: String, prefix := "") -> String:
	if not object.has(key):
		return ""
	var field := prefix + key
	if typeof(object[key]) != TYPE_STRING:
		_error(field, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	if not known.has(object[key]):
		_error(field, "unknown %s id '%s'" % [kind, object[key]])
		return ""
	return object[key]


static func _float(object: Dictionary, key: String, low: float, high: float, prefix := "") -> float:
	if not object.has(key):
		return low
	return _float_value(object[key], prefix + key, low, high)


static func _float_value(value: Variant, field: String, low: float, high: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_error(field, "expected float, got %s" % type_string(typeof(value)))
		return low
	var number: float = value
	if number < low or number > high:
		_error(field, "%s is outside %s..%s" % [number, low, high])
		return low
	return number


## A [x, y] pair of numbers, each low..high.
static func _vector(object: Dictionary, key: String, low: float, high: float) -> Vector2:
	if not object.has(key):
		return Vector2.ZERO
	return _pair(object[key], key, low, high)


static func _pair(value: Variant, field: String, low: float, high: float) -> Vector2:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		_error(field, "expected an array of 2 numbers [x, y], got %s" % [value])
		return Vector2.ZERO
	var list: Array = value
	return Vector2(_float_value(list[0], field + "[0]", low, high), _float_value(list[1], field + "[1]", low, high))


## The hitbox polygon: at least HITBOX_MIN_POINTS [x, y] points, each inside the sprite
## (within half of `size` of the centre on each axis; not checked when `size` failed).
static func _hitbox(object: Dictionary, size: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if not object.has("hitbox"):
		return polygon
	if typeof(object["hitbox"]) != TYPE_ARRAY:
		_error("hitbox", "expected Array, got %s" % type_string(typeof(object["hitbox"])))
		return polygon
	var list: Array = object["hitbox"]
	if list.size() < HITBOX_MIN_POINTS:
		_error("hitbox", "has %d points, needs at least %d" % [list.size(), HITBOX_MIN_POINTS])
	var half := size / 2.0
	for i in list.size():
		var field := "hitbox[%d]" % i
		var point := _pair(list[i], field, -SIZE_MAX, SIZE_MAX)
		# A failed size has no real bounds to check against.
		if not _failed.has("size") and (absf(point.x) > half.x or absf(point.y) > half.y):
			_error(field, "%s is outside the sprite (±%s)" % [point, half])
		polygon.append(point)
	# A simple polygon: no two edges that do not share a corner touch or cross.
	var count := polygon.size()
	for i in count:
		for j in range(i + 2, count):
			if i == 0 and j == count - 1:
				continue
			if Geometry2D.segment_intersects_segment(polygon[i], polygon[(i + 1) % count], polygon[j], polygon[(j + 1) % count]) != null:
				_error("hitbox", "edges %d and %d cross (not a simple polygon)" % [i, j])
	return polygon


static func _lookup(table: Dictionary, id: String, kind: String) -> Resource:
	if not table.has(id):
		if not quiet_errors:
			push_error("[Content] Unknown %s id '%s'" % [kind, id])
		return null
	return table[id]


static func _begin_file(file: String) -> void:
	_file = "data/" + file
	_entry = "-"
	_failed.clear()


static func _error(field: String, problem: String) -> void:
	var message := "%s [%s] %s: %s" % [_file, _entry, field, problem]
	_errors.append(message)
	_failed[field.get_slice("[", 0)] = true
	if not quiet_errors:
		push_error("[Content] " + message)
