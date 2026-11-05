class_name ContentReader
extends RefCounted
## One content load's error collector and its typed field readers. Content makes one per
## load and hands it to each file's validator (ChaptersFile, BirdsFile, ModesFile,
## LevelsFile, RivalLinesFile), so no error state outlives a load.
## Every problem is collected in `errors` as "data/<file> [<entry id>] <field>: <problem>"
## and reported with push_error unless the load is quiet. A reader returns a fallback value
## (its low bound, "" or empty) for a bad field and records the field in `failed`, so checks
## that depend on it can be skipped and a fallback value is never blamed.

## Every problem found so far, oldest first.
var errors: Array[String] = []
## The file ("data/<file>") and entry the load is reading, for error messages.
var file := ""
var entry := ""
## The top-level fields of the current entry that already have an error ("size" for
## "size[0]" too). Cleared at each file and each entry.
var failed: Dictionary[String, bool] = {}

var _quiet := false
var _snake_case := RegEx.create_from_string("^[a-z][a-z0-9_]*$")


## `quiet`: collect the errors without push_error (Content.quiet_errors, for tests).
func _init(quiet: bool) -> void:
	_quiet = quiet


## Starts reading data/`name`: its file-level errors name the entry "-".
func begin_file(name: String) -> void:
	file = "data/" + name
	entry = "-"
	failed.clear()


func error(field: String, problem: String) -> void:
	var message := "%s [%s] %s: %s" % [file, entry, field, problem]
	errors.append(message)
	failed[field.get_slice("[", 0)] = true
	if not _quiet:
		push_error("[Content] " + message)


func is_snake_case(id: String) -> bool:
	return _snake_case.search(id) != null


## The entries of an array file; [] after reporting a parse error or another top-level
## type. A non-object entry is reported (as "#<index>") and left out.
func parse_entries(text: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var json := JSON.new()
	if json.parse(text) != OK:
		error("(file)", "JSON parse error at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return entries
	if typeof(json.data) != TYPE_ARRAY:
		error("(file)", "top level must be an array, got %s" % type_string(typeof(json.data)))
		return entries
	var list: Array = json.data
	if list.is_empty():
		error("(file)", "has no entries")
	for i in list.size():
		if typeof(list[i]) == TYPE_DICTIONARY:
			entries.append(list[i])
		else:
			entry = "#%d" % i
			error("(entry)", "expected Dictionary, got %s" % type_string(typeof(list[i])))
	return entries


## The top-level object of a single-object file (rival_lines.json); {} after reporting
## a parse error or another top-level type.
func parse_object(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		error("(file)", "JSON parse error at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		error("(file)", "top level must be an object, got %s" % type_string(typeof(json.data)))
		return {}
	var object: Dictionary = json.data
	if object.is_empty():
		error("(file)", "has no fields")
	return object


## Starts reading `item`: sets the error context and checks its keys and id. Returns the id
## when it is valid and not yet in `seen`, else "" (the entry is then validated but not stored).
## `optional` keys may be absent.
func begin_entry(item: Dictionary, required: Array[String], seen: Dictionary, optional: Array[String] = []) -> String:
	var id := ""
	if typeof(item.get("id")) == TYPE_STRING:
		id = item["id"]
	entry = id if id != "" else "(no id)"
	failed.clear()
	for key in required:
		if not item.has(key):
			error(key, "missing key")
	for key: Variant in item:
		if not str(key) in required and not str(key) in optional:
			error(str(key), "unknown key")
	if not item.has("id"):
		return ""
	if typeof(item["id"]) != TYPE_STRING:
		error("id", "expected String, got %s" % type_string(typeof(item["id"])))
		return ""
	if not is_snake_case(id):
		error("id", "'%s' is not snake_case" % id)
		return ""
	if seen.has(id):
		error("id", "duplicate id '%s'" % id)
		return ""
	return id


## Reports every key of `keys` missing from `part` and every key of `part` not in `keys`,
## each as "<field>.<key>" (`field` names the object inside the entry: "boss", "backdrops[0]").
func check_keys(part: Dictionary, keys: Array[String], field: String) -> void:
	for name in keys:
		if not part.has(name):
			error("%s.%s" % [field, name], "missing key")
	for name: Variant in part:
		if not str(name) in keys:
			error("%s.%s" % [field, name], "unknown key")


func read_string(object: Dictionary, key: String, max_length: int) -> String:
	if not object.has(key):
		return ""
	var value: Variant = object[key]
	if typeof(value) != TYPE_STRING:
		error(key, "expected String, got %s" % type_string(typeof(value)))
		return ""
	var text: String = value
	if text.is_empty() or text.length() > max_length:
		error(key, "length %d is outside 1..%d" % [text.length(), max_length])
	return text


## `prefix` names the object inside the entry ("birds[0].") in error messages; `name`, when
## set, replaces the whole field name ("stars[1]").
func read_int(object: Dictionary, key: String, low: int, high: int, prefix := "", name := "") -> int:
	if not object.has(key):
		return low
	var field := name if name != "" else prefix + key
	var value: Variant = object[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		error(field, "expected int, got %s" % type_string(typeof(value)))
		return low
	var number: float = value
	if number != floorf(number):
		error(field, "expected int, got %s" % value)
		return low
	if number < low or number > high:
		error(field, "%d is outside %d..%d" % [int(number), low, high])
		return low
	return int(number)


## True when `object[key]` is present and an int within low..high (what read_int accepts).
func int_ok(object: Dictionary, key: String, low: int, high: int) -> bool:
	var value: Variant = object.get(key)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	var number: float = value
	return number == floorf(number) and number >= low and number <= high


func read_bool(object: Dictionary, key: String) -> bool:
	if typeof(object[key]) != TYPE_BOOL:
		error(key, "expected bool, got %s" % type_string(typeof(object[key])))
		return false
	return object[key]


## A string that is one of `allowed`. `prefix` names the object inside the entry ("backdrops[0].").
func read_enum(object: Dictionary, key: String, allowed: Array[String], prefix := "") -> String:
	if not object.has(key):
		return ""
	if typeof(object[key]) != TYPE_STRING:
		error(prefix + key, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	if not str(object[key]) in allowed:
		error(prefix + key, "'%s' is not one of %s" % [object[key], allowed])
		return ""
	return object[key]


## A string id that is a key of `known` ("" when it is missing, mistyped or unknown).
func read_reference(object: Dictionary, key: String, known: Dictionary, kind: String, prefix := "") -> String:
	if not object.has(key):
		return ""
	var field := prefix + key
	if typeof(object[key]) != TYPE_STRING:
		error(field, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	if not known.has(object[key]):
		error(field, "unknown %s id '%s'" % [kind, object[key]])
		return ""
	return object[key]


func read_float(object: Dictionary, key: String, low: float, high: float, prefix := "") -> float:
	if not object.has(key):
		return low
	return float_value(object[key], prefix + key, low, high)


func float_value(value: Variant, field: String, low: float, high: float) -> float:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		error(field, "expected float, got %s" % type_string(typeof(value)))
		return low
	var number: float = value
	if number < low or number > high:
		error(field, "%s is outside %s..%s" % [number, low, high])
		return low
	return number


## A [x, y] pair of numbers, each low..high.
func read_vector(object: Dictionary, key: String, low: float, high: float) -> Vector2:
	if not object.has(key):
		return Vector2.ZERO
	return pair(object[key], key, low, high)


func pair(value: Variant, field: String, low: float, high: float) -> Vector2:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		error(field, "expected an array of 2 numbers [x, y], got %s" % [value])
		return Vector2.ZERO
	var list: Array = value
	return Vector2(float_value(list[0], field + "[0]", low, high), float_value(list[1], field + "[1]", low, high))


## A backdrop id (snake_case) whose every layer has its art (Content.backdrop_path); "" when
## it is missing, mistyped or has no art (each missing layer reported).
func read_backdrop(object: Dictionary, key: String, prefix := "") -> String:
	if not object.has(key):
		return ""
	var field := prefix + key
	if typeof(object[key]) != TYPE_STRING:
		error(field, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	var id: String = object[key]
	if not is_snake_case(id):
		error(field, "'%s' is not a snake_case backdrop id" % id)
		return ""
	var missing := false
	for layer in Content.BACKDROP_LAYERS:
		if not ResourceLoader.exists(Content.backdrop_path(id, layer)):
			error(field, "unknown backdrop '%s' (no %s)" % [id, Content.backdrop_path(id, layer)])
			missing = true
	return "" if missing else id


## A music track id (snake_case) whose file exists (Content.music_path, I23); "" when it is
## missing, mistyped or has no file.
func read_music(object: Dictionary, key: String) -> String:
	if not object.has(key):
		return ""
	if typeof(object[key]) != TYPE_STRING:
		error(key, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	var id: String = object[key]
	if not is_snake_case(id):
		error(key, "'%s' is not a snake_case music track id" % id)
		return ""
	if not ResourceLoader.exists(Content.music_path(id)):
		error(key, "unknown music track '%s' (no %s)" % [id, Content.music_path(id)])
		return ""
	return id
