class_name RivalLinesFile
extends RefCounted
## data/rival_lines.json's validator: fills the ContentSet's RivalLines (data/SCHEMA.md),
## then checks I13 against the birds, modes and chapters already in it.


## {"aim_time", "cooldown", "lines": {<category>: [line, ...]}}, every category of
## RivalLines.CATEGORIES with a non-empty list of 1..RivalLines.LINE_MAX character strings.
## Errors name the category as the entry ("-" for the top-level fields). Then I13 (unless
## aim_time failed).
static func read(r: ContentReader, data: ContentSet, object: Dictionary) -> void:
	if object.is_empty():
		return
	var keys: Array[String] = ["aim_time", "cooldown", "lines"]
	for key in keys:
		if not object.has(key):
			r.error(key, "missing key")
	for key: Variant in object:
		if not str(key) in keys:
			r.error(str(key), "unknown key")
	data.rival_lines.aim_time = r.read_float(object, "aim_time", RivalLines.AIM_TIME_MIN, RivalLines.AIM_TIME_MAX)
	var aim_ok := not r.failed.has("aim_time")
	data.rival_lines.cooldown = r.read_float(object, "cooldown", 0.0, RivalLines.COOLDOWN_MAX)
	if object.has("lines"):
		if typeof(object["lines"]) != TYPE_DICTIONARY:
			r.error("lines", "expected Dictionary, got %s" % type_string(typeof(object["lines"])))
		else:
			var categories: Dictionary = object["lines"]
			for category in RivalLines.CATEGORIES:
				r.entry = category
				if not categories.has(category):
					r.error("lines", "missing category")
					continue
				data.rival_lines.lines[category] = _lines(r, categories[category])
			for category: Variant in categories:
				if not str(category) in RivalLines.CATEGORIES:
					r.entry = str(category)
					r.error("lines", "unknown category (expected one of %s)" % [RivalLines.CATEGORIES])
	if aim_ok:
		check_linger(r, data, data.rival_lines.aim_time)


## A category's lines: a non-empty array of strings of 1..RivalLines.LINE_MAX characters.
static func _lines(r: ContentReader, value: Variant) -> PackedStringArray:
	var result := PackedStringArray()
	if typeof(value) != TYPE_ARRAY:
		r.error("lines", "expected Array, got %s" % type_string(typeof(value)))
		return result
	var list: Array = value
	if list.is_empty():
		r.error("lines", "is empty")
	for i in list.size():
		var field := "lines[%d]" % i
		if typeof(list[i]) != TYPE_STRING:
			r.error(field, "expected String, got %s" % type_string(typeof(list[i])))
			continue
		var line: String = list[i]
		if line.is_empty() or line.length() > RivalLines.LINE_MAX:
			r.error(field, "length %d is outside 1..%d (the speech bubble's two lines)" % [line.length(), RivalLines.LINE_MAX])
		result.append(line)
	return result


## I13: every bird the rival can steal (all but the decoy) has every linger the rival uses
## plus aim_time under its flee_time, so every cue can finish before the bird flees on its
## own. The rival waits linger_time x 1 in a mode with rival_steals and linger_time x the
## chapter's rival_linger_scale in each chapter (the campaign always steals). One line per
## bird (reported under data/birds.json), at the largest failing scale, naming every mode
## and chapter that fails. A bird whose flee_time or linger_time already has an error is
## skipped, and so is a chapter whose scale has one (its fallback value would be blamed instead).
static func check_linger(r: ContentReader, data: ContentSet, aim_time: float) -> void:
	var scales: Dictionary[String, float] = {}
	for mode_spec: ModeSpec in data.modes.values():
		if mode_spec.rival_steals:
			scales[mode_spec.id] = 1.0
	for chapter_spec: ChapterSpec in data.chapters.values():
		if not data.bad_scale.has(chapter_spec.id):
			scales[chapter_spec.id] = chapter_spec.rival_linger_scale
	var file := r.file
	r.file = "data/birds.json"
	for spec: BirdSpec in data.birds.values():
		if spec.penalty > 0 or data.bad_timing.has(spec.id):
			continue
		r.entry = spec.id
		var failing := PackedStringArray()
		var worst := 0.0
		for where in scales:
			if spec.linger_time * scales[where] + aim_time >= spec.flee_time:
				failing.append(where)
				worst = maxf(worst, scales[where])
		if not failing.is_empty():
			r.error("linger_time", "%s x %s (%s) + aim_time %s is not under flee_time %s (I13: the rival's cue must end before the bird flees)" % [spec.linger_time, worst, ", ".join(failing), aim_time, spec.flee_time])
	r.file = file
