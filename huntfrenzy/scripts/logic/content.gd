class_name Content
extends RefCounted
## All game content: the JSON in res://data/ parsed into typed resources (ChapterSpec,
## BirdSpec, ModeSpec, LevelSpec, RivalLines). Static only: the loader and the lookups.
## Each file has its own validator (ChaptersFile, BirdsFile, ModesFile, LevelsFile,
## RivalLinesFile) that builds its specs into a ContentSet through one load's ContentReader
## (the error collector and typed field readers); each spec keeps its field limits.
## The data is loaded once, lazily, on the first call of any public function (the title
## screen's errors() call does it at boot); reload() and load_texts() replace it (tests).
## Every problem (unreadable file, bad JSON, a file with no entries, missing or unknown key,
## wrong type, non-integer int, out-of-range value, unknown enum value, duplicate id,
## unknown reference, a sprite or backdrop missing a frame or layer (its art file), a music
## track with no file (I23), a hitbox outside its sprite or crossing
## itself, a split field without its pair, a wave mix with nothing from wave 1, a mode with
## both or neither of escape_limit and time_limit, a missing,
## unknown or empty rival line category, a rival line too long for the bubble, not exactly
## CHAPTER_COUNT chapters, a chapter whose rival_linger_scale rises above the one before's,
## a chapter without exactly its levels 1..LEVELS_PER_CHAPTER, a boss on any level but the
## last of its chapter, star thresholds that do not rise, a bird's call that is not one of
## the game's sound effects (I25), and I13: a bird whose scaled
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
## The campaign: exactly CHAPTER_COUNT chapters (dawn, noon, sunset, night) of exactly
## LEVELS_PER_CHAPTER levels each, the last one the chapter's boss level.
const CHAPTER_COUNT := 4
const LEVELS_PER_CHAPTER := 6
## The weather ids a chapter or a mode's stage draws over its backdrop (Weather, visual only).
const WEATHERS: Array[String] = ["mist", "wind", "rain", "snow"]
## A backdrop's art: one SVG per layer, BACKDROP_DIR<id>_<layer>.svg, drawn back to front
## (the sky, the far marsh, the near reeds and water, then the grass in front of the birds).
const BACKDROP_DIR := "res://art/backdrops/"
const BACKDROP_LAYERS: Array[String] = ["sky", "far", "near", "grass"]
## A music track: MUSIC_DIR<id>.mp3 (tools/music.py makes them); a chapter's levels and a
## mode's runs each play the one their entry names.
const MUSIC_DIR := "res://audio/music/"

## Tests set quiet_errors to assert on expected errors (load errors and unknown-id lookups)
## without failing the log check.
static var quiet_errors := false

static var _loaded := false
static var _errors: Array[String] = []
static var _data := ContentSet.new()


## Every content problem found by the last load, oldest first. Empty means the data is valid.
static func errors() -> Array[String]:
	_ensure_loaded()
	return _errors.duplicate()


## Reads every file in FILES from DATA_DIR and replaces the loaded content.
static func reload() -> void:
	var reader := ContentReader.new(quiet_errors)
	var texts: Dictionary[String, String] = {}
	for file in FILES:
		var text := FileAccess.get_file_as_string(DATA_DIR + file)
		var open_error := FileAccess.get_open_error()
		if open_error != OK:
			reader.begin_file(file)
			reader.error("(file)", "cannot be read: %s" % error_string(open_error))
			continue
		texts[file] = text
	_load(reader, texts)


## Replaces the loaded content with `texts` (file name in FILES -> JSON text). Tests use it
## to feed malformed data; a file missing from `texts` is reported as missing.
static func load_texts(texts: Dictionary[String, String]) -> void:
	var reader := ContentReader.new(quiet_errors)
	for file in FILES:
		if not texts.has(file):
			reader.begin_file(file)
			reader.error("(file)", "missing")
	_load(reader, texts)


## The bird type `id`, or null (with push_error) if there is none.
static func bird(id: String) -> BirdSpec:
	_ensure_loaded()
	return _lookup(_data.birds, id, "bird") as BirdSpec


## The mode `id`, or null (with push_error) if there is none.
static func mode(id: String) -> ModeSpec:
	_ensure_loaded()
	return _lookup(_data.modes, id, "mode") as ModeSpec


## The chapter `id`, or null (with push_error) if there is none.
static func chapter(id: String) -> ChapterSpec:
	_ensure_loaded()
	return _lookup(_data.chapters, id, "chapter") as ChapterSpec


## The level `id`, or null (with push_error) if there is none.
static func level(id: String) -> LevelSpec:
	_ensure_loaded()
	return _lookup(_data.levels, id, "level") as LevelSpec


## Whether `id` is a level of levels.json (no error when it is not).
static func has_level(id: String) -> bool:
	_ensure_loaded()
	return _data.levels.has(id)


## Every chapter, in data (campaign) order.
static func chapters() -> Array[ChapterSpec]:
	_ensure_loaded()
	var result: Array[ChapterSpec] = []
	result.assign(_data.chapters.values())
	return result


## Every level, in data order (Campaign.levels() gives campaign order).
static func levels() -> Array[LevelSpec]:
	_ensure_loaded()
	var result: Array[LevelSpec] = []
	result.assign(_data.levels.values())
	return result


## Every bird type, in data order.
static func birds() -> Array[BirdSpec]:
	_ensure_loaded()
	var result: Array[BirdSpec] = []
	result.assign(_data.birds.values())
	return result


## The art of backdrop `id`'s `layer` (one of BACKDROP_LAYERS).
static func backdrop_path(id: String, layer: String) -> String:
	return "%s%s_%s.svg" % [BACKDROP_DIR, id, layer]


## The file of music track `id`.
static func music_path(id: String) -> String:
	return "%s%s.mp3" % [MUSIC_DIR, id]


## The rival's timing and heckle lines.
static func rival_lines() -> RivalLines:
	_ensure_loaded()
	return _data.rival_lines


## Every mode, in data order.
static func modes() -> Array[ModeSpec]:
	_ensure_loaded()
	var result: Array[ModeSpec] = []
	result.assign(_data.modes.values())
	return result


static func _ensure_loaded() -> void:
	if not _loaded:
		reload()


## Reads every file of `texts` with its validator, in FILES order, into a fresh ContentSet,
## then keeps it and the reader's errors. A file absent from `texts` was already reported
## by reload() or load_texts() on `reader`.
static func _load(reader: ContentReader, texts: Dictionary[String, String]) -> void:
	_loaded = true
	var data := ContentSet.new()
	for file in FILES:
		if not texts.has(file):
			continue
		reader.begin_file(file)
		match file:
			"chapters.json":
				ChaptersFile.read(reader, data, reader.parse_entries(texts[file]))
			"birds.json":
				BirdsFile.read(reader, data, reader.parse_entries(texts[file]))
			"modes.json":
				ModesFile.read(reader, data, reader.parse_entries(texts[file]))
			"levels.json":
				LevelsFile.read(reader, data, reader.parse_entries(texts[file]))
			"rival_lines.json":
				RivalLinesFile.read(reader, data, reader.parse_object(texts[file]))
	_data = data
	_errors = reader.errors
	var line_count := 0
	for category in data.rival_lines.lines:
		line_count += data.rival_lines.lines[category].size()
	print("[Content] Loaded %d chapters, %d birds, %d modes, %d levels, %d rival lines: %d problem(s)" % [data.chapters.size(), data.birds.size(), data.modes.size(), data.levels.size(), line_count, _errors.size()])


static func _lookup(table: Dictionary, id: String, kind: String) -> Resource:
	if not table.has(id):
		if not quiet_errors:
			push_error("[Content] Unknown %s id '%s'" % [kind, id])
		return null
	return table[id]
