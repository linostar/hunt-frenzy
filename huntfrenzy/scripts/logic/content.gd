class_name Content
extends RefCounted
## All game content: the JSON in res://data/ parsed into typed resources (BirdSpec,
## ModeSpec). Static only. The data is loaded once, lazily, on the first call of any
## public function (the title screen's errors() call does it at boot); reload() and
## load_texts() replace it (tests).
## Every problem (unreadable file, bad JSON, a file with no entries, missing or unknown key,
## wrong type, non-integer int, out-of-range value, duplicate id, unknown reference) is
## collected in errors() as "data/<file> [<entry id>] <field>: <problem>" and reported with
## push_error, all of them, not just the first. Entries with problems are still loaded as
## far as they parse (bad fields keep their resource defaults), and the title screen
## disables Play while errors() is non-empty, so no default ever reaches a run.

const DATA_DIR := "res://data/"
## Load order: modes reference birds, so birds load first.
const FILES: Array[String] = ["birds.json", "modes.json"]
## The art frames every bird sprite must have (BirdSpec.texture_path).
const BIRD_FRAMES: Array[String] = ["fly_1", "fly_2", "hit"]
const NAME_MAX := 26
const SPEED_MAX := 1000.0
const WOBBLE_MAX := 100.0
const WOBBLE_HZ_MAX := 5.0
const FLEE_TIME_MAX := 60.0
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
const SHELLS_PER_BIRD_MAX := 10
const COMBO_CAP_MAX := 20
const ESCAPE_LIMIT_MAX := 100

## Tests set quiet_errors to assert on expected errors (load errors and unknown-id lookups)
## without failing the log check.
static var quiet_errors := false

static var _loaded := false
static var _errors: Array[String] = []
static var _birds: Dictionary[String, BirdSpec] = {}
static var _modes: Dictionary[String, ModeSpec] = {}
## The file and entry the loader is reading, for error messages.
static var _file := ""
static var _entry := ""
static var _snake_case := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


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


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


static func _reset() -> void:
	_loaded = true
	_errors.clear()
	_birds.clear()
	_modes.clear()


static func _load(texts: Dictionary[String, String]) -> void:
	for file in FILES:
		# A file absent from `texts` was already reported by reload() or load_texts().
		if not texts.has(file):
			continue
		_begin_file(file)
		var entries := _parse_entries(texts[file])
		match file:
			"birds.json":
				_load_birds(entries)
			"modes.json":
				_load_modes(entries)
	print("[Content] Loaded %d birds, %d modes: %d problem(s)" % [_birds.size(), _modes.size(), _errors.size()])


static func _load_birds(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var item := BirdSpec.new()
		item.id = _begin_entry(entry, ["id", "name", "speed", "wobble", "wobble_hz", "flee_time", "points", "sprite", "size", "hitbox"], _birds)
		item.name = _string(entry, "name", NAME_MAX)
		item.speed = _float(entry, "speed", 1.0, SPEED_MAX)
		item.wobble = _float(entry, "wobble", 0.0, WOBBLE_MAX)
		item.wobble_hz = _float(entry, "wobble_hz", 0.0, WOBBLE_HZ_MAX)
		item.flee_time = _float(entry, "flee_time", 0.1, FLEE_TIME_MAX)
		item.points = _int(entry, "points", 1, POINTS_MAX)
		item.sprite = _string(entry, "sprite", NAME_MAX)
		if item.sprite != "":
			for frame in BIRD_FRAMES:
				if not ResourceLoader.exists(item.texture_path(frame)):
					_error("sprite", "unknown sprite '%s' (no %s)" % [item.sprite, item.texture_path(frame)])
					break
		item.size = _vector(entry, "size", SIZE_MIN, SIZE_MAX)
		item.hitbox = _hitbox(entry, item.size)
		if item.id != "":
			_birds[item.id] = item


static func _load_modes(entries: Array[Dictionary]) -> void:
	for entry in entries:
		var item := ModeSpec.new()
		item.id = _begin_entry(entry, ["id", "name", "birds", "start_birds", "bird_growth", "max_birds", "speed_growth", "speed_cap", "spawn_interval", "shells_per_bird", "combo_cap", "escape_limit"], _modes)
		item.name = _string(entry, "name", NAME_MAX)
		item.birds = _references(entry, "birds", _birds, "bird")
		item.start_birds = _int(entry, "start_birds", 1, WAVE_BIRDS_MAX)
		item.bird_growth = _int(entry, "bird_growth", 0, BIRD_GROWTH_MAX)
		item.max_birds = _int(entry, "max_birds", item.start_birds, WAVE_BIRDS_MAX)
		item.speed_growth = _float(entry, "speed_growth", 0.0, SPEED_GROWTH_MAX)
		item.speed_cap = _float(entry, "speed_cap", 1.0, SPEED_CAP_MAX)
		item.spawn_interval = _float(entry, "spawn_interval", SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)
		item.shells_per_bird = _int(entry, "shells_per_bird", 1, SHELLS_PER_BIRD_MAX)
		item.combo_cap = _int(entry, "combo_cap", 1, COMBO_CAP_MAX)
		item.escape_limit = _int(entry, "escape_limit", 1, ESCAPE_LIMIT_MAX)
		if item.id != "":
			_modes[item.id] = item


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
static func _begin_entry(entry: Dictionary, required: Array[String], seen: Dictionary) -> String:
	var id := ""
	if typeof(entry.get("id")) == TYPE_STRING:
		id = entry["id"]
	_entry = id if id != "" else "(no id)"
	for key in required:
		if not entry.has(key):
			_error(key, "missing key")
	for key: Variant in entry:
		if not str(key) in required:
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


static func _int(object: Dictionary, key: String, low: int, high: int) -> int:
	if not object.has(key):
		return low
	var value: Variant = object[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		_error(key, "expected int, got %s" % type_string(typeof(value)))
		return low
	var number: float = value
	if number != floorf(number):
		_error(key, "expected int, got %s" % value)
		return low
	if number < low or number > high:
		_error(key, "%d is outside %d..%d" % [int(number), low, high])
		return low
	return int(number)


static func _float(object: Dictionary, key: String, low: float, high: float) -> float:
	if not object.has(key):
		return low
	return _float_value(object[key], key, low, high)


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
## (within half of `size` of the centre on each axis).
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
		if absf(point.x) > half.x or absf(point.y) > half.y:
			_error(field, "%s is outside the sprite (±%s)" % [point, half])
		polygon.append(point)
	return polygon


## A non-empty array of ids, each a key of `known`; unknown or wrong-typed ids are reported and skipped.
static func _references(object: Dictionary, key: String, known: Dictionary, kind: String) -> PackedStringArray:
	var result := PackedStringArray()
	if not object.has(key):
		return result
	if typeof(object[key]) != TYPE_ARRAY:
		_error(key, "expected Array, got %s" % type_string(typeof(object[key])))
		return result
	var list: Array = object[key]
	if list.is_empty():
		_error(key, "is empty")
	for i in list.size():
		var field := "%s[%d]" % [key, i]
		if typeof(list[i]) != TYPE_STRING:
			_error(field, "expected String, got %s" % type_string(typeof(list[i])))
		elif not known.has(list[i]):
			_error(field, "unknown %s id '%s'" % [kind, list[i]])
		else:
			result.append(list[i])
	return result


static func _lookup(table: Dictionary, id: String, kind: String) -> Resource:
	if not table.has(id):
		if not quiet_errors:
			push_error("[Content] Unknown %s id '%s'" % [kind, id])
		return null
	return table[id]


static func _begin_file(file: String) -> void:
	_file = "data/" + file
	_entry = "-"


static func _error(field: String, problem: String) -> void:
	var message := "%s [%s] %s: %s" % [_file, _entry, field, problem]
	_errors.append(message)
	if not quiet_errors:
		push_error("[Content] " + message)
