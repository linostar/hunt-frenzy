class_name ChaptersFile
extends RefCounted
## data/chapters.json's validator: builds ChapterSpecs into a ContentSet (data/SCHEMA.md).


## Exactly Content.CHAPTER_COUNT chapters in campaign order, each rival_linger_scale in
## (0, 1] and at most the one before's (the rival never gets slower).
static func read(r: ContentReader, data: ContentSet, entries: Array[Dictionary]) -> void:
	var previous: ChapterSpec = null
	for entry in entries:
		var item := ChapterSpec.new()
		item.id = r.begin_entry(entry, ["id", "name", "backdrop", "weather", "music", "rival_linger_scale"], data.chapters)
		item.name = r.read_string(entry, "name", Content.NAME_MAX)
		item.backdrop = r.read_backdrop(entry, "backdrop")
		item.weather = r.read_enum(entry, "weather", Content.WEATHERS)
		item.music = r.read_music(entry, "music")
		item.rival_linger_scale = _scale(r, entry, "rival_linger_scale")
		if r.failed.has("rival_linger_scale"):
			data.bad_scale[r.entry] = true
		else:
			if previous != null and item.rival_linger_scale > previous.rival_linger_scale:
				r.error("rival_linger_scale", "%s is above %s's %s (the rival never gets slower: a chapter's scale is at most the one before's)" % [item.rival_linger_scale, previous.id, previous.rival_linger_scale])
			previous = item
		if item.id != "":
			data.chapters[item.id] = item
	if not entries.is_empty() and data.chapters.size() != Content.CHAPTER_COUNT:
		r.entry = "-"
		r.error("(file)", "has %d chapters, needs exactly %d" % [data.chapters.size(), Content.CHAPTER_COUNT])


## A scale in (0, 1]: more than 0, at most 1.
static func _scale(r: ContentReader, object: Dictionary, key: String) -> float:
	if not object.has(key):
		return 1.0
	var value: Variant = object[key]
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		r.error(key, "expected float, got %s" % type_string(typeof(value)))
		return 1.0
	var number: float = value
	if number <= 0.0 or number > 1.0:
		r.error(key, "%s is outside (0.0, 1.0]" % number)
		return 1.0
	return number
