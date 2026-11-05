class_name BirdsFile
extends RefCounted
## data/birds.json's validator: builds BirdSpecs into a ContentSet (data/SCHEMA.md). Each
## bird's chapter must already be in it.


static func read(r: ContentReader, data: ContentSet, entries: Array[Dictionary]) -> void:
	var splits: Dictionary[String, String] = {}
	for entry in entries:
		var item := BirdSpec.new()
		item.id = r.begin_entry(entry, ["id", "name", "chapter", "pattern", "speed", "wobble", "wobble_hz", "flee_time", "linger_time", "call", "call_pitch", "points", "hp", "sprite", "size", "hitbox"], data.birds,
			["splits_into", "split_count", "penalty", "escape_counts"])
		item.name = r.read_string(entry, "name", Content.NAME_MAX)
		item.chapter = r.read_reference(entry, "chapter", data.chapters, "chapter")
		item.pattern = r.read_enum(entry, "pattern", BirdSpec.PATTERNS)
		item.speed = r.read_float(entry, "speed", 1.0, BirdSpec.SPEED_MAX)
		item.wobble = r.read_float(entry, "wobble", 0.0, BirdSpec.WOBBLE_MAX)
		item.wobble_hz = r.read_float(entry, "wobble_hz", 0.0, BirdSpec.WOBBLE_HZ_MAX)
		item.flee_time = r.read_float(entry, "flee_time", 0.1, BirdSpec.FLEE_TIME_MAX)
		item.linger_time = r.read_float(entry, "linger_time", BirdSpec.LINGER_TIME_MIN, BirdSpec.FLEE_TIME_MAX)
		item.call_sound = _sound(r, entry, "call")
		item.call_pitch = r.read_float(entry, "call_pitch", BirdSpec.CALL_PITCH_MIN, BirdSpec.CALL_PITCH_MAX)
		item.points = r.read_int(entry, "points", 0, BirdSpec.POINTS_MAX)
		item.hp = r.read_int(entry, "hp", 1, BirdSpec.HP_MAX)
		item.sprite = r.read_string(entry, "sprite", Content.NAME_MAX)
		if item.sprite != "":
			for frame in item.frames():
				if not ResourceLoader.exists(item.texture_path(frame)):
					r.error("sprite", "unknown sprite '%s' (no %s)" % [item.sprite, item.texture_path(frame)])
		item.size = r.read_vector(entry, "size", BirdSpec.SIZE_MIN, BirdSpec.SIZE_MAX)
		item.hitbox = _hitbox(r, entry, item.size)
		# splits_into and split_count come together (the splitter); the reference is
		# checked once every bird is loaded.
		if entry.has("splits_into") != entry.has("split_count"):
			var missing := "split_count" if entry.has("splits_into") else "splits_into"
			r.error(missing, "missing key (required with %s)" % ("splits_into" if missing == "split_count" else "split_count"))
		item.splits_into = r.read_string(entry, "splits_into", Content.NAME_MAX)
		if entry.has("split_count"):
			item.split_count = r.read_int(entry, "split_count", 1, BirdSpec.SPLIT_COUNT_MAX)
		if entry.has("penalty"):
			item.penalty = r.read_int(entry, "penalty", 1, BirdSpec.POINTS_MAX)
		if entry.has("escape_counts"):
			item.escape_counts = r.read_bool(entry, "escape_counts")
		if item.splits_into != "":
			splits[r.entry] = item.splits_into
		if item.id != "":
			data.birds[item.id] = item
			if r.failed.has("flee_time") or r.failed.has("linger_time"):
				data.bad_timing[item.id] = true
	for from: String in splits:
		r.entry = from
		if not data.birds.has(splits[from]):
			r.error("splits_into", "unknown bird id '%s'" % splits[from])


## A sound effect id, one of AudioManager.SFX_IDS (I25: tools/sfx.py makes each one's file and
## the game checks they exist at start); "" when it is missing, mistyped or unknown.
static func _sound(r: ContentReader, object: Dictionary, key: String) -> String:
	if not object.has(key):
		return ""
	if typeof(object[key]) != TYPE_STRING:
		r.error(key, "expected String, got %s" % type_string(typeof(object[key])))
		return ""
	var id: String = object[key]
	if not StringName(id) in AudioManager.SFX_IDS:
		r.error(key, "unknown sound effect '%s' (I25: a call must be one of AudioManager.SFX_IDS)" % id)
		return ""
	return id


## The hitbox polygon: at least BirdSpec.HITBOX_MIN_POINTS [x, y] points, each inside the
## sprite (within half of `size` of the centre on each axis; not checked when `size` failed).
static func _hitbox(r: ContentReader, object: Dictionary, size: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	if not object.has("hitbox"):
		return polygon
	if typeof(object["hitbox"]) != TYPE_ARRAY:
		r.error("hitbox", "expected Array, got %s" % type_string(typeof(object["hitbox"])))
		return polygon
	var list: Array = object["hitbox"]
	if list.size() < BirdSpec.HITBOX_MIN_POINTS:
		r.error("hitbox", "has %d points, needs at least %d" % [list.size(), BirdSpec.HITBOX_MIN_POINTS])
	var half := size / 2.0
	for i in list.size():
		var field := "hitbox[%d]" % i
		var point := r.pair(list[i], field, -BirdSpec.SIZE_MAX, BirdSpec.SIZE_MAX)
		# A failed size has no real bounds to check against.
		if not r.failed.has("size") and (absf(point.x) > half.x or absf(point.y) > half.y):
			r.error(field, "%s is outside the sprite (±%s)" % [point, half])
		polygon.append(point)
	# A simple polygon: no two edges that do not share a corner touch or cross.
	var count := polygon.size()
	for i in count:
		for j in range(i + 2, count):
			if i == 0 and j == count - 1:
				continue
			if Geometry2D.segment_intersects_segment(polygon[i], polygon[(i + 1) % count], polygon[j], polygon[(j + 1) % count]) != null:
				r.error("hitbox", "edges %d and %d cross (not a simple polygon)" % [i, j])
	return polygon
