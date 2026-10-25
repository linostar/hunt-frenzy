extends SceneTree
## Headless content tests: loads huntfrenzy/data/*.json through Content and checks every
## invariant of huntfrenzy/data/SCHEMA.md (I1..I13) against the real data, then proves
## each one fires on a malformed copy of it (the loader's I1-I4 and I13 with the exact
## error lines; I5-I12 with the exact problems their checks report).
##   "$GODOT" --headless --path huntfrenzy --script "$PWD/tools/test_content.gd"
## Prints "test_content: OK" when every test passes; exits 1 otherwise.
## To add a test: write a `_test_*` func that reports through _check(), and append it to
## the list in _tests(). Every test leaves Content loaded from the real data.

## Real-time limit for the whole run; a test stuck on an await fails instead of hanging.
const WATCHDOG_MSEC := 60000
## I5: the share of a hitbox's sample points (one per base unit) that must lie on opaque
## pixels of each flap frame (the rest is anti-aliasing along the outline).
const HITBOX_ART_MIN := 0.98
## I5: the share of each flap frame's opaque pixels (one sample per base unit) that its
## hitbox must cover. The real art measures 0.60 (splitter fly_1) to 0.80 (goose fly_2):
## the flapping wings, beaks and tails lie outside every hitbox. A box on the body alone
## covers well under a third.
const HITBOX_COVER_MIN := 0.5
## A pixel at least this opaque is part of the bird.
const OPAQUE_ALPHA := 0.5
## I6: the most a decoy's silhouette may overlap any other type's (intersection over
## union of their opaque masks, each sampled on SILHOUETTE_GRID across its own sprite).
## A recoloured copy of a shape overlaps it by 0.9 or more (the armored and golden geese
## overlap the goose by 0.93-0.99); different shapes stay well under 0.85.
const DECOY_OVERLAP_MAX := 0.85
const SILHOUETTE_GRID := Vector2i(48, 36)
## I12: the shortest side a hitbox's bounding box may have, in base units: the game's
## smallest touch target (CLAUDE.md, every interactive Control is at least 44x44).
const HITBOX_SIDE_MIN := 44.0

var _failures: Array[String] = []
var _passed := 0
var _deadline_msec := 0
## Rasterised art by texture path (I5, I6).
var _art: Dictionary[String, Image] = {}


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	if root.get_node_or_null("Game") as GameState == null:
		printerr("test_content: FAILED: Game autoload not found")
		quit(1)
		return
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_msec:
		printerr("test_content: FAILED watchdog: tests did not finish within %d ms" % WATCHDOG_MSEC)
		quit(1)
	return false


func _tests() -> Array[Callable]:
	return [
		_test_real_data_loads_clean,
		_test_lookup_api,
		_test_i1_files_ids_and_keys,
		_test_i2_types_and_ranges,
		_test_i3_references,
		_test_i4_hitbox_geometry,
		_test_i5_hitbox_matches_art,
		_test_i6_decoy,
		_test_i7_split,
		_test_i8_golden_and_mix,
		_test_i9_first_wave_plain,
		_test_i10_roster_and_chapters,
		_test_i11_fits_field,
		_test_i12_hitbox_touch_size,
		_test_i13_cue_ends_before_fleeing,
	]


func _run() -> void:
	await process_frame
	for test in _tests():
		test.call()
		Content.reload()
	for failure in _failures:
		printerr("test_content: FAIL " + failure)
	if _failures.is_empty():
		print("test_content: OK (%d checks)" % _passed)
		quit(0)
	else:
		printerr("test_content: FAILED %d of %d checks" % [_failures.size(), _failures.size() + _passed])
		quit(1)


## I1-I4 and I13 hold for the real data: the loader checks them, so clean real data means
## no loader errors.
func _test_real_data_loads_clean() -> void:
	Content.reload()
	_check(Content.errors().is_empty(), "I1-I4 and I13 the real data loads without errors", "\n".join(Content.errors()))


## The lookups return the typed data: the six types plus the gosling, in data order, and
## the Endless mode with its mix and golden fields.
func _test_lookup_api() -> void:
	var ids := Content.birds().map(func(spec: BirdSpec) -> String: return spec.id)
	_check(ids == ["goose", "armored", "splitter", "gosling", "zigzag", "golden", "decoy"], "birds() lists every type in data order", str(ids))
	var goose := Content.bird("goose")
	_check(goose.points == 100 and goose.hp == 1 and goose.pattern == "rise" and goose.chapter == "dawn" and goose.size == Vector2(96, 72) and goose.escape_counts and goose.penalty == 0 and goose.splits_into == "", "bird() returns the goose's fields",
		"points %d, hp %d, pattern %s, chapter %s, size %s, escape_counts %s, penalty %d, splits_into '%s'" % [goose.points, goose.hp, goose.pattern, goose.chapter, goose.size, goose.escape_counts, goose.penalty, goose.splits_into])
	var splitter := Content.bird("splitter")
	_check(splitter.splits_into == "gosling" and splitter.split_count == 2, "the splitter splits into 2 goslings", "%s x%d" % [splitter.splits_into, splitter.split_count])
	var decoy := Content.bird("decoy")
	_check(decoy.penalty == 200 and not decoy.escape_counts and decoy.points == 0, "the decoy has a penalty and its escape does not count", "%d %s" % [decoy.penalty, decoy.escape_counts])
	_check(Content.bird("armored").hp == 2 and Content.bird("armored").frames().size() == 5, "the armored goose has hp 2 and damaged frames", str(Content.bird("armored").frames()))
	_check(Content.bird("zigzag").pattern == "zigzag", "the zigzag flies the zigzag pattern", Content.bird("zigzag").pattern)
	var endless := Content.mode("endless")
	var mix := endless.birds.map(func(e: ModeSpec.Entry) -> String: return "%s@%d" % [e.bird, e.from_wave])
	_check(mix == ["goose@1", "armored@3", "splitter@5", "decoy@5", "zigzag@7"], "the Endless mix unlocks by wave", str(mix))
	_check(endless.golden_bird == "golden" and endless.golden_from_wave == 2 and is_equal_approx(endless.golden_chance, 0.08), "Endless's golden bird from wave 2", "%s %d %.2f" % [endless.golden_bird, endless.golden_from_wave, endless.golden_chance])
	_check(Content.modes().size() == 1, "modes() lists the modes", str(Content.modes().size()))
	var lingers := Content.birds().map(func(spec: BirdSpec) -> float: return spec.linger_time)
	_check(lingers == [3.5, 4.0, 3.5, 1.5, 3.5, 2.5, 4.0], "every bird has its linger_time", str(lingers))
	_check(endless.rival_steals, "Endless has the rival's steals on", str(endless.rival_steals))
	var rival := Content.rival_lines()
	var counts := RivalLines.CATEGORIES.map(func(category: String) -> int: return rival.lines[category].size() if rival.lines.has(category) else 0)
	_check(is_equal_approx(rival.aim_time, 1.0) and is_equal_approx(rival.cooldown, 4.0) and counts == [5, 4, 4, 5, 4], "rival_lines() returns the aim time, the cooldown and every category's lines", "aim %.2f, cooldown %.2f, %s" % [rival.aim_time, rival.cooldown, counts])


## I1: each file parses, is a non-empty array of objects, ids are snake_case and unique,
## no key is missing or unknown (mix entries included), and a split field comes with its pair.
func _test_i1_files_ids_and_keys() -> void:
	_expect_load_errors("I1 missing key", _mutated("birds.json", func(data: Array) -> void: (data[0] as Dictionary).erase("hp")),
		["data/birds.json [goose] hp: missing key"])
	_expect_load_errors("I1 unknown key", _mutated("birds.json", func(data: Array) -> void: data[0]["colour"] = "grey"),
		["data/birds.json [goose] colour: unknown key"])
	_expect_load_errors("I1 duplicate id", _mutated("birds.json", func(data: Array) -> void: data.append((data[0] as Dictionary).duplicate())),
		["data/birds.json [goose] id: duplicate id 'goose'"])
	_expect_load_errors("I1 id not snake_case", _mutated("birds.json", func(data: Array) -> void: data[3]["id"] = "Gosling"),
		["data/birds.json [Gosling] id: 'Gosling' is not snake_case", "data/birds.json [splitter] splits_into: unknown bird id 'gosling'"])
	_expect_load_errors("I1 split field without its pair", _mutated("birds.json", func(data: Array) -> void: (data[2] as Dictionary).erase("split_count")),
		["data/birds.json [splitter] split_count: missing key (required with splits_into)"])
	_expect_load_errors("I1 mix entry missing key", _mutated("modes.json", func(data: Array) -> void: (data[0]["birds"][1] as Dictionary).erase("weight")),
		["data/modes.json [endless] birds[1].weight: missing key"])
	_expect_load_errors("I1 mix entry unknown key", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["chance"] = 1),
		["data/modes.json [endless] birds[1].chance: unknown key"])
	_expect_load_errors("I1 mix entry not an object", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1] = "armored"),
		["data/modes.json [endless] birds[1]: expected Dictionary, got String"])
	_expect_load_errors("I1 bird twice in a mix", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["bird"] = "goose"),
		["data/modes.json [endless] birds[1].bird: 'goose' is already in the mix (birds[0])"])
	_expect_load_errors("I1 mix with nothing from wave 1", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][0]["from_wave"] = 2),
		["data/modes.json [endless] birds: no bird from wave 1 (wave 1 would have nothing to spawn)"])
	_expect_load_errors("I1 entry not an object", _with_text("modes.json", "[5]"),
		["data/modes.json [#0] (entry): expected Dictionary, got float"])
	_expect_load_errors("I1 empty file", _with_text("modes.json", "[]"), ["data/modes.json [-] (file): has no entries"])
	_expect_load_errors("I1 top level not an array", _with_text("modes.json", "{}"), ["data/modes.json [-] (file): top level must be an array, got Dictionary"])
	_expect_load_errors("I1 bad JSON", _with_text("modes.json", "[{"), ["data/modes.json [-] (file): JSON parse error at line 1: Expected '}'"])
	var texts := _real_texts()
	texts.erase("modes.json")
	_expect_load_errors("I1 missing file", _load_quietly(texts), ["data/modes.json [-] (file): missing"])
	_expect_load_errors("I1 missing linger_time", _mutated("birds.json", func(data: Array) -> void: (data[0] as Dictionary).erase("linger_time")),
		["data/birds.json [goose] linger_time: missing key"])
	_expect_load_errors("I1 missing rival_steals", _mutated("modes.json", func(data: Array) -> void: (data[0] as Dictionary).erase("rival_steals")),
		["data/modes.json [endless] rival_steals: missing key"])
	_expect_load_errors("I1 rival lines missing a category", _mutated("rival_lines.json", func(data: Dictionary) -> void: (data["lines"] as Dictionary).erase("steal")),
		["data/rival_lines.json [steal] lines: missing category"])
	_expect_load_errors("I1 rival lines with an unknown category", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["boast"] = ["Watch this."]),
		["data/rival_lines.json [boast] lines: unknown category (expected one of [\"miss\", \"combo\", \"wave_end\", \"steal\", \"results\"])"])
	_expect_load_errors("I1 rival lines missing a key", _mutated("rival_lines.json", func(data: Dictionary) -> void: data.erase("cooldown")),
		["data/rival_lines.json [-] cooldown: missing key"])
	_expect_load_errors("I1 rival lines with an unknown key", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["volume"] = 1),
		["data/rival_lines.json [-] volume: unknown key"])
	_expect_load_errors("I1 rival lines not an object", _with_text("rival_lines.json", "[]"), ["data/rival_lines.json [-] (file): top level must be an object, got Array"])
	_expect_load_errors("I1 rival lines with no fields", _with_text("rival_lines.json", "{}"), ["data/rival_lines.json [-] (file): has no fields"])
	_expect_load_errors("I1 rival lines bad JSON", _with_text("rival_lines.json", "{"), ["data/rival_lines.json [-] (file): JSON parse error at line 1: Expected '}'"])
	texts = _real_texts()
	texts.erase("rival_lines.json")
	_expect_load_errors("I1 rival lines file missing", _load_quietly(texts), ["data/rival_lines.json [-] (file): missing"])


## I2: every field has its type and lies in its range or enum.
func _test_i2_types_and_ranges() -> void:
	_expect_load_errors("I2 wrong type", _mutated("birds.json", func(data: Array) -> void: data[0]["speed"] = "fast"),
		["data/birds.json [goose] speed: expected float, got String"])
	_expect_load_errors("I2 non-integer int", _mutated("birds.json", func(data: Array) -> void: data[0]["hp"] = 1.5),
		["data/birds.json [goose] hp: expected int, got 1.5"])
	_expect_load_errors("I2 unknown chapter id", _mutated("birds.json", func(data: Array) -> void: data[0]["chapter"] = "dusk"),
		["data/birds.json [goose] chapter: 'dusk' is not one of [\"dawn\", \"noon\", \"sunset\", \"night\"]"])
	_expect_load_errors("I2 chapter as a number", _mutated("birds.json", func(data: Array) -> void: data[0]["chapter"] = 1),
		["data/birds.json [goose] chapter: expected String, got float"])
	_expect_load_errors("I2 unknown pattern", _mutated("birds.json", func(data: Array) -> void: data[0]["pattern"] = "loop"),
		["data/birds.json [goose] pattern: 'loop' is not one of [\"rise\", \"zigzag\"]"])
	_expect_load_errors("I2 hp out of range", _mutated("birds.json", func(data: Array) -> void: data[0]["hp"] = 0),
		["data/birds.json [goose] hp: 0 is outside 1..5"])
	_expect_load_errors("I2 escape_counts not a bool", _mutated("birds.json", func(data: Array) -> void: data[6]["escape_counts"] = "no"),
		["data/birds.json [decoy] escape_counts: expected bool, got String"])
	_expect_load_errors("I2 penalty out of range", _mutated("birds.json", func(data: Array) -> void: data[6]["penalty"] = 0),
		["data/birds.json [decoy] penalty: 0 is outside 1..100000"])
	_expect_load_errors("I2 split_count out of range", _mutated("birds.json", func(data: Array) -> void: data[2]["split_count"] = 9),
		["data/birds.json [splitter] split_count: 9 is outside 1..4"])
	_expect_load_errors("I2 golden_chance out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["golden_chance"] = 1.5),
		["data/modes.json [endless] golden_chance: 1.5 is outside 0.0..1.0"])
	_expect_load_errors("I2 mix weight out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["weight"] = 0),
		["data/modes.json [endless] birds[1].weight: 0 is outside 1..100"])
	_expect_load_errors("I2 mix from_wave not an int", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["from_wave"] = "3"),
		["data/modes.json [endless] birds[1].from_wave: expected int, got String"])
	_expect_load_errors("I2 mix from_wave out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["from_wave"] = 1001),
		["data/modes.json [endless] birds[1].from_wave: 1001 is outside 1..1000"])
	_expect_load_errors("I2 golden_from_wave out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["golden_from_wave"] = 0),
		["data/modes.json [endless] golden_from_wave: 0 is outside 1..1000"])
	_expect_load_errors("I2 linger_time zero", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = 0),
		["data/birds.json [goose] linger_time: 0.0 is outside 0.1..60.0"])
	_expect_load_errors("I2 linger_time negative", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = -2),
		["data/birds.json [goose] linger_time: -2.0 is outside 0.1..60.0"])
	_expect_load_errors("I2 linger_time not a number", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = "soon"),
		["data/birds.json [goose] linger_time: expected float, got String"])
	_expect_load_errors("I2 rival_steals not a bool", _mutated("modes.json", func(data: Array) -> void: data[0]["rival_steals"] = 1),
		["data/modes.json [endless] rival_steals: expected bool, got float"])
	_expect_load_errors("I2 aim_time under 0.5 s", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["aim_time"] = 0.4),
		["data/rival_lines.json [-] aim_time: 0.4 is outside 0.5..10.0"])
	_expect_load_errors("I2 cooldown negative", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["cooldown"] = -1),
		["data/rival_lines.json [-] cooldown: -1.0 is outside 0.0..60.0"])
	_expect_load_errors("I2 rival line too long for the bubble", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["miss"][2] = "That is the worst shot I have ever seen, kid."),
		["data/rival_lines.json [miss] lines[2]: length 45 is outside 1..40 (the speech bubble's two lines)"])
	_expect_load_errors("I2 empty rival line", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["combo"][0] = ""),
		["data/rival_lines.json [combo] lines[0]: length 0 is outside 1..40 (the speech bubble's two lines)"])
	_expect_load_errors("I2 rival line not a string", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["steal"][1] = 7),
		["data/rival_lines.json [steal] lines[1]: expected String, got float"])
	_expect_load_errors("I2 rival category not a list", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["results"] = "Bye."),
		["data/rival_lines.json [results] lines: expected Array, got String"])
	_expect_load_errors("I2 rival category empty", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"]["wave_end"] = []),
		["data/rival_lines.json [wave_end] lines: is empty"])
	_expect_load_errors("I2 rival lines not an object", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["lines"] = ["Hi."]),
		["data/rival_lines.json [-] lines: expected Dictionary, got Array"])


## I3: every reference resolves (mix birds, golden_bird, splits_into) and every sprite has
## its frames (the damaged flap frames too when hp > 1).
func _test_i3_references() -> void:
	_expect_load_errors("I3 unknown mix bird", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["bird"] = "swan"),
		["data/modes.json [endless] birds[1].bird: unknown bird id 'swan'"])
	_expect_load_errors("I3 unknown golden bird", _mutated("modes.json", func(data: Array) -> void: data[0]["golden_bird"] = "phoenix"),
		["data/modes.json [endless] golden_bird: unknown bird id 'phoenix'"])
	_expect_load_errors("I3 unknown split child", _mutated("birds.json", func(data: Array) -> void: data[2]["splits_into"] = "chick"),
		["data/birds.json [splitter] splits_into: unknown bird id 'chick'"])
	_expect_load_errors("I3 unknown sprite", _mutated("birds.json", func(data: Array) -> void: data[0]["sprite"] = "swan"),
		["data/birds.json [goose] sprite: unknown sprite 'swan' (no res://art/swan_fly_1.svg)",
		"data/birds.json [goose] sprite: unknown sprite 'swan' (no res://art/swan_fly_2.svg)",
		"data/birds.json [goose] sprite: unknown sprite 'swan' (no res://art/swan_hit.svg)"])
	_expect_load_errors("I3 hp 2 without damaged frames", _mutated("birds.json", func(data: Array) -> void: data[0]["hp"] = 2),
		["data/birds.json [goose] sprite: unknown sprite 'goose' (no res://art/goose_damaged_fly_1.svg)",
		"data/birds.json [goose] sprite: unknown sprite 'goose' (no res://art/goose_damaged_fly_2.svg)"])


## I4: every hitbox has at least 3 points, all inside the sprite, and is a simple polygon.
func _test_i4_hitbox_geometry() -> void:
	_expect_load_errors("I4 too few points", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[0, 0], [10, 0]]),
		["data/birds.json [goose] hitbox: has 2 points, needs at least 3"])
	_expect_load_errors("I4 point outside the sprite", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"][0] = [-50, 0]),
		["data/birds.json [goose] hitbox[0]: (-50.0, 0.0) is outside the sprite (±(48.0, 36.0))"])
	_expect_load_errors("I4 self-crossing hitbox", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-10, -10], [10, 10], [10, -10], [-10, 10]]),
		["data/birds.json [goose] hitbox: edges 0 and 2 cross (not a simple polygon)"])


## I5: every hitbox matches its art: at least HITBOX_ART_MIN of the points sampled inside
## it lie on opaque pixels of each flap frame (damaged ones included), and it covers at least
## HITBOX_COVER_MIN of each flap frame's opaque pixels.
func _test_i5_hitbox_matches_art() -> void:
	_check(_i5_problems().is_empty(), "I5 every hitbox lies on its art", "\n".join(_i5_problems()))
	# A hitbox in the sprite's empty top-left corner: inside the sprite, simple, off the art.
	_expect_problems("I5 a hitbox off the art", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-46, -34], [-30, -34], [-46, -20]]), _i5_problems,
		["goose fly_1: 0.0% of the hitbox's sample points lie on opaque art (needs 98%)", "goose fly_1: the hitbox covers 0.0% of the opaque art (needs 50%)",
		"goose fly_2: 0.0% of the hitbox's sample points lie on opaque art (needs 98%)", "goose fly_2: the hitbox covers 0.0% of the opaque art (needs 50%)"])
	# The goose's hitbox moved 8 units up: its top now covers sky above the head.
	_expect_problems("I5 a shifted hitbox", _mutated("birds.json", func(data: Array) -> void:
		for point: Array in data[0]["hitbox"]:
			point[1] = point[1] - 8), _i5_problems,
		["goose fly_1: 79.6% of the hitbox's sample points lie on opaque art (needs 98%)", "goose fly_2: 72.5% of the hitbox's sample points lie on opaque art (needs 98%)"])
	# A 20x16 box on the goose's body: all of it on the art, but most of the art outside it.
	_expect_problems("I5 a hitbox covering little of the art", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-10, -2], [10, -2], [10, 14], [-10, 14]]), _i5_problems,
		["goose fly_1: the hitbox covers 12.8% of the opaque art (needs 50%)", "goose fly_2: the hitbox covers 14.0% of the opaque art (needs 50%)"])


## I6: a bird has a penalty exactly when its escape does not count (the decoy); a decoy
## scores no points, has hp 1 and does not split; every other bird scores; the decoy's
## silhouette differs from every other type's by shape.
func _test_i6_decoy() -> void:
	_check(_i6_problems().is_empty(), "I6 the decoy rules hold", "\n".join(_i6_problems()))
	_expect_problems("I6 penalty with a counted escape", _mutated("birds.json", func(data: Array) -> void: (data[6] as Dictionary).erase("escape_counts")), _i6_problems,
		["decoy: penalty 200 with escape_counts true (a decoy has a penalty and an uncounted escape; no other bird has either)"])
	_expect_problems("I6 uncounted escape without a penalty", _mutated("birds.json", func(data: Array) -> void: data[0]["escape_counts"] = false), _i6_problems,
		["goose: penalty 0 with escape_counts false (a decoy has a penalty and an uncounted escape; no other bird has either)"])
	_expect_problems("I6 a decoy that scores", _mutated("birds.json", func(data: Array) -> void: data[6]["points"] = 50), _i6_problems,
		["decoy: a decoy scores no points (points 50)"])
	_expect_problems("I6 a bird that scores nothing", _mutated("birds.json", func(data: Array) -> void: data[0]["points"] = 0), _i6_problems,
		["goose: points 0 (every bird but the decoy scores)"])
	_expect_problems("I6 a decoy shaped like a goose", _mutated("birds.json", func(data: Array) -> void: data[6]["sprite"] = "golden"), _i6_problems,
		["decoy: its silhouette overlaps goose's by 0.99 (at most 0.85: a decoy differs by shape)", "decoy: its silhouette overlaps armored's by 0.93 (at most 0.85: a decoy differs by shape)",
		"decoy: its silhouette overlaps golden's by 1.00 (at most 0.85: a decoy differs by shape)"])


## I7: a splitter has hp 1 (its first hit splits it); its child has hp 1, does not split,
## is not a decoy, is smaller and faster than it, and never spawns from waves.
func _test_i7_split() -> void:
	_check(_i7_problems().is_empty(), "I7 the split rules hold", "\n".join(_i7_problems()))
	_expect_problems("I7 a splitter with hp 2", _mutated("birds.json", func(data: Array) -> void: data[2]["hp"] = 2), _i7_problems,
		["splitter: a splitter has hp 1 (its first hit splits it), got 2"],
		["data/birds.json [splitter] sprite: unknown sprite 'splitter' (no res://art/splitter_damaged_fly_1.svg)",
		"data/birds.json [splitter] sprite: unknown sprite 'splitter' (no res://art/splitter_damaged_fly_2.svg)"])
	_expect_problems("I7 a child with hp 2", _mutated("birds.json", func(data: Array) -> void: data[3]["hp"] = 2), _i7_problems,
		["gosling: a split child has hp 1, got 2"],
		["data/birds.json [gosling] sprite: unknown sprite 'gosling' (no res://art/gosling_damaged_fly_1.svg)",
		"data/birds.json [gosling] sprite: unknown sprite 'gosling' (no res://art/gosling_damaged_fly_2.svg)"])
	_expect_problems("I7 a child slower than its parent", _mutated("birds.json", func(data: Array) -> void: data[3]["speed"] = 100), _i7_problems,
		["gosling: a split child is faster than splitter (speed 100.0 vs 120.0)"])
	_expect_problems("I7 a child no smaller than its parent", _mutated("birds.json", func(data: Array) -> void: data[3]["size"] = [104, 80]), _i7_problems,
		["gosling: a split child is smaller than splitter (size (104.0, 80.0) vs (104.0, 80.0))"])
	_expect_problems("I7 a child in a wave mix", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"].append({"bird": "gosling", "from_wave": 9, "weight": 1})), _i7_problems,
		["gosling: a split child never spawns from waves (endless)"])


## I8: a mode's golden bird is not in its mix, has hp 1, does not split, is not a decoy,
## and is faster and worth more points than every bird of the mix.
func _test_i8_golden_and_mix() -> void:
	_check(_i8_problems().is_empty(), "I8 the golden bird rules hold", "\n".join(_i8_problems()))
	_expect_problems("I8 a slow golden bird", _mutated("birds.json", func(data: Array) -> void: data[5]["speed"] = 150), _i8_problems,
		["endless: golden bird golden (speed 150.0) is not faster than zigzag (speed 175.0)"])
	_expect_problems("I8 a cheap golden bird", _mutated("birds.json", func(data: Array) -> void: data[5]["points"] = 180), _i8_problems,
		["endless: golden bird golden (180 points) is not worth more than zigzag (200 points)"])
	_expect_problems("I8 the golden bird in the mix", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"].append({"bird": "golden", "from_wave": 9, "weight": 1})), _i8_problems,
		["endless: golden bird golden is also in the mix"])
	_expect_problems("I8 a golden decoy", _mutated("birds.json", func(data: Array) -> void:
		data[5]["penalty"] = 10
		data[5]["escape_counts"] = false), _i8_problems,
		["endless: golden bird golden must have hp 1, no split and no penalty"])


## I9: wave 1 is plain geese only (every mix bird from wave 1 rises, has hp 1, does not
## split and is no decoy) and golden birds start at wave 2 or later, so a run's first bird
## is a plain goose.
func _test_i9_first_wave_plain() -> void:
	_check(_i9_problems().is_empty(), "I9 wave 1 holds plain birds only", "\n".join(_i9_problems()))
	_expect_problems("I9 golden in wave 1", _mutated("modes.json", func(data: Array) -> void: data[0]["golden_from_wave"] = 1), _i9_problems,
		["endless: golden_from_wave 1 (golden birds start at wave 2 or later)"])
	_expect_problems("I9 an armored bird in wave 1", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][1]["from_wave"] = 1), _i9_problems,
		["endless: armored is in wave 1 but is not a plain rising bird (rise, hp 1, no split, no penalty)"])
	_expect_problems("I9 a zigzag in wave 1", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"][4]["from_wave"] = 1), _i9_problems,
		["endless: zigzag is in wave 1 but is not a plain rising bird (rise, hp 1, no split, no penalty)"])


## I10: the roster holds every kind (plain, armored, splitter, zigzag, golden, decoy),
## each chapter of Content.CHAPTERS introduces at least one bird, and every bird can appear (in a
## mix, as a golden bird or as a split child).
func _test_i10_roster_and_chapters() -> void:
	_check(_i10_problems().is_empty(), "I10 every kind, chapter and bird is covered", "\n".join(_i10_problems()))
	_expect_problems("I10 no zigzag", _mutated("birds.json", func(data: Array) -> void: data[4]["pattern"] = "rise"), _i10_problems,
		["no zigzag bird (pattern zigzag)"])
	_expect_problems("I10 no armored bird", _mutated("birds.json", func(data: Array) -> void:
		data[1]["hp"] = 1), _i10_problems,
		["no armored bird (hp 2 or more)"])
	_expect_problems("I10 a chapter introducing nothing", _mutated("birds.json", func(data: Array) -> void: data[4]["chapter"] = "sunset"), _i10_problems,
		["chapter night introduces no bird"])
	_expect_problems("I10 a bird that never appears", _mutated("modes.json", func(data: Array) -> void: (data[0]["birds"] as Array).pop_back()), _i10_problems,
		["no zigzag bird (pattern zigzag)", "chapter night introduces no bird", "zigzag never appears (not in a mix, not a golden bird, not a split child)"])


## I11: every bird fits the field it flies in (Play.FIELD): narrower than it, and its
## height plus twice its wobble lower than it.
func _test_i11_fits_field() -> void:
	_check(_i11_problems().is_empty(), "I11 every bird fits the field", "\n".join(_i11_problems()))
	_expect_problems("I11 a bird too tall with its wobble", _mutated("birds.json", func(data: Array) -> void: data[0]["size"] = [96, 360]), _i11_problems,
		["goose: size (96.0, 360.0) with wobble 14.0 does not fit the field (960.0, 384.0)"])


## I12: every hitbox's bounding box is at least HITBOX_SIDE_MIN on each side, so a
## fingertip can hit every bird.
func _test_i12_hitbox_touch_size() -> void:
	_check(_i12_problems().is_empty(), "I12 every hitbox is big enough to touch", "\n".join(_i12_problems()))
	# The step 3 gosling: 56x42 art with a 38x27 hitbox.
	_expect_problems("I12 a hitbox smaller than a fingertip", _mutated("birds.json", func(data: Array) -> void:
		data[3]["size"] = [56, 42]
		data[3]["hitbox"] = [[-18, 6], [-14, -2], [-4, -4], [6, -3], [8, -10], [13, -12], [19, -9], [20, -3], [14, 2], [12, 9], [-4, 15], [-14, 12]]), _i12_problems,
		["gosling: hitbox bounding box (38.0, 27.0) is under 44 base units on a side (the smallest touch target)"])


## I13 (the loader's): every bird but the decoy has linger_time + the rival's aim_time
## under its flee_time, so every aim cue can finish before the bird flees on its own.
func _test_i13_cue_ends_before_fleeing() -> void:
	_expect_load_errors("I13 a goose lingering into its flight off", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = 5.5),
		["data/birds.json [goose] linger_time: 5.5 + aim_time 1.0 is not under flee_time 6.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 a cue ending exactly at flee_time", _mutated("birds.json", func(data: Array) -> void: data[3]["linger_time"] = 2.0),
		["data/birds.json [gosling] linger_time: 2.0 + aim_time 1.0 is not under flee_time 3.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 an aim too long for the fast birds", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["aim_time"] = 1.6),
		["data/birds.json [gosling] linger_time: 1.5 + aim_time 1.6 is not under flee_time 3.0 (I13: the rival's cue must end before the bird flees)",
		"data/birds.json [golden] linger_time: 2.5 + aim_time 1.6 is not under flee_time 4.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 the decoy is exempt (never stolen)", _mutated("birds.json", func(data: Array) -> void: data[6]["linger_time"] = 9.0), [])


func _i5_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		for frame in spec.frames():
			if frame == "hit":
				continue
			var art := _raster(spec.texture_path(frame))
			var scale := Vector2(art.get_size()) / spec.size
			var inside := 0
			var on_art := 0
			var opaque := 0
			for y in int(spec.size.y):
				for x in int(spec.size.x):
					var local := Vector2(x + 0.5, y + 0.5) - spec.size / 2.0
					var in_hitbox := Geometry2D.is_point_in_polygon(local, spec.hitbox)
					var on := art.get_pixelv(Vector2i(((local + spec.size / 2.0) * scale).floor())).a >= OPAQUE_ALPHA
					inside += int(in_hitbox)
					opaque += int(on)
					on_art += int(in_hitbox and on)
			var share := float(on_art) / inside if inside > 0 else 0.0
			if share < HITBOX_ART_MIN:
				problems.append("%s %s: %.1f%% of the hitbox's sample points lie on opaque art (needs %d%%)" % [spec.id, frame, share * 100.0, roundi(HITBOX_ART_MIN * 100.0)])
			var cover := float(on_art) / opaque if opaque > 0 else 0.0
			if cover < HITBOX_COVER_MIN:
				problems.append("%s %s: the hitbox covers %.1f%% of the opaque art (needs %d%%)" % [spec.id, frame, cover * 100.0, roundi(HITBOX_COVER_MIN * 100.0)])
	return problems


func _i6_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		if (spec.penalty > 0) == spec.escape_counts:
			problems.append("%s: penalty %d with escape_counts %s (a decoy has a penalty and an uncounted escape; no other bird has either)" % [spec.id, spec.penalty, spec.escape_counts])
		if spec.penalty > 0:
			if spec.points != 0:
				problems.append("%s: a decoy scores no points (points %d)" % [spec.id, spec.points])
			if spec.hp != 1 or spec.split_count > 0:
				problems.append("%s: a decoy has hp 1 and does not split (hp %d, split_count %d)" % [spec.id, spec.hp, spec.split_count])
			for other in Content.birds():
				if other.penalty > 0:
					continue
				var overlap := _silhouette_overlap(spec, other)
				if overlap > DECOY_OVERLAP_MAX:
					problems.append("%s: its silhouette overlaps %s's by %.2f (at most %.2f: a decoy differs by shape)" % [spec.id, other.id, overlap, DECOY_OVERLAP_MAX])
		elif spec.points < 1:
			problems.append("%s: points %d (every bird but the decoy scores)" % [spec.id, spec.points])
	return problems


func _i7_problems() -> Array[String]:
	var problems: Array[String] = []
	for parent in Content.birds():
		if parent.split_count == 0:
			continue
		if parent.hp != 1:
			problems.append("%s: a splitter has hp 1 (its first hit splits it), got %d" % [parent.id, parent.hp])
		var child := Content.bird(parent.splits_into)
		if child.hp != 1:
			problems.append("%s: a split child has hp 1, got %d" % [child.id, child.hp])
		if child.split_count > 0 or child.penalty > 0:
			problems.append("%s: a split child does not split and is no decoy" % child.id)
		if child.speed <= parent.speed:
			problems.append("%s: a split child is faster than %s (speed %s vs %s)" % [child.id, parent.id, child.speed, parent.speed])
		if child.size.x >= parent.size.x or child.size.y >= parent.size.y:
			problems.append("%s: a split child is smaller than %s (size %s vs %s)" % [child.id, parent.id, child.size, parent.size])
		for mode in Content.modes():
			if mode.golden_bird == child.id or mode.birds.any(func(e: ModeSpec.Entry) -> bool: return e.bird == child.id):
				problems.append("%s: a split child never spawns from waves (%s)" % [child.id, mode.id])
	return problems


func _i8_problems() -> Array[String]:
	var problems: Array[String] = []
	for mode in Content.modes():
		var golden := Content.bird(mode.golden_bird)
		if golden.hp != 1 or golden.split_count > 0 or golden.penalty > 0:
			problems.append("%s: golden bird %s must have hp 1, no split and no penalty" % [mode.id, golden.id])
		for entry in mode.birds:
			var spec := Content.bird(entry.bird)
			if spec == golden:
				problems.append("%s: golden bird %s is also in the mix" % [mode.id, golden.id])
				continue
			if golden.speed <= spec.speed:
				problems.append("%s: golden bird %s (speed %s) is not faster than %s (speed %s)" % [mode.id, golden.id, golden.speed, spec.id, spec.speed])
			if golden.points <= spec.points:
				problems.append("%s: golden bird %s (%d points) is not worth more than %s (%d points)" % [mode.id, golden.id, golden.points, spec.id, spec.points])
	return problems


func _i9_problems() -> Array[String]:
	var problems: Array[String] = []
	for mode in Content.modes():
		if mode.golden_from_wave < 2:
			problems.append("%s: golden_from_wave %d (golden birds start at wave 2 or later)" % [mode.id, mode.golden_from_wave])
		for entry in mode.birds:
			var spec := Content.bird(entry.bird)
			if entry.from_wave == 1 and not _is_plain(spec):
				problems.append("%s: %s is in wave 1 but is not a plain rising bird (rise, hp 1, no split, no penalty)" % [mode.id, spec.id])
	return problems


func _i10_problems() -> Array[String]:
	var problems: Array[String] = []
	var golden_ids := Content.modes().map(func(mode: ModeSpec) -> String: return mode.golden_bird)
	var appears: Dictionary[String, bool] = {}
	for mode in Content.modes():
		appears[mode.golden_bird] = true
		for entry in mode.birds:
			appears[entry.bird] = true
	for spec in Content.birds():
		if spec.split_count > 0:
			appears[spec.splits_into] = true
	var birds := Content.birds()
	var kinds: Dictionary[String, Callable] = {
		"plain bird (rise, hp 1, no split, no penalty)": func(spec: BirdSpec) -> bool: return _is_plain(spec) and not spec.id in golden_ids,
		"armored bird (hp 2 or more)": func(spec: BirdSpec) -> bool: return spec.hp >= 2,
		"splitter (split_count > 0)": func(spec: BirdSpec) -> bool: return spec.split_count > 0,
		"zigzag bird (pattern zigzag)": func(spec: BirdSpec) -> bool: return spec.pattern == "zigzag",
		"golden bird (a mode's golden_bird)": func(spec: BirdSpec) -> bool: return spec.id in golden_ids,
		"decoy (penalty > 0)": func(spec: BirdSpec) -> bool: return spec.penalty > 0,
	}
	for kind: String in kinds:
		if not birds.any(func(spec: BirdSpec) -> bool: return appears.has(spec.id) and kinds[kind].call(spec)):
			problems.append("no %s" % kind)
	for chapter in Content.CHAPTERS:
		if not birds.any(func(spec: BirdSpec) -> bool: return spec.chapter == chapter and appears.has(spec.id)):
			problems.append("chapter %s introduces no bird" % chapter)
	for spec in birds:
		if not appears.has(spec.id):
			problems.append("%s never appears (not in a mix, not a golden bird, not a split child)" % spec.id)
	return problems


func _i11_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		if spec.size.x >= Play.FIELD.size.x or spec.size.y + 2.0 * spec.wobble >= Play.FIELD.size.y:
			problems.append("%s: size %s with wobble %s does not fit the field %s" % [spec.id, spec.size, spec.wobble, Play.FIELD.size])
	return problems


func _i12_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		var box := Rect2(spec.hitbox[0], Vector2.ZERO) if not spec.hitbox.is_empty() else Rect2()
		for point in spec.hitbox:
			box = box.expand(point)
		if box.size.x < HITBOX_SIDE_MIN or box.size.y < HITBOX_SIDE_MIN:
			problems.append("%s: hitbox bounding box %s is under %d base units on a side (the smallest touch target)" % [spec.id, box.size, roundi(HITBOX_SIDE_MIN)])
	return problems


## A plain bird: the rising path, one hit, no split, no penalty.
func _is_plain(spec: BirdSpec) -> bool:
	return spec.pattern == "rise" and spec.hp == 1 and spec.split_count == 0 and spec.penalty == 0


## The intersection over union of the two birds' fly_1 silhouettes, each sampled on
## SILHOUETTE_GRID across its own sprite (so only the shape counts, not the size or colour).
func _silhouette_overlap(a: BirdSpec, b: BirdSpec) -> float:
	var art_a := _raster(a.texture_path("fly_1"))
	var art_b := _raster(b.texture_path("fly_1"))
	var both := 0
	var either := 0
	for y in SILHOUETTE_GRID.y:
		for x in SILHOUETTE_GRID.x:
			var at := (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(SILHOUETTE_GRID)
			var in_a := art_a.get_pixelv(Vector2i((at * Vector2(art_a.get_size())).floor())).a >= OPAQUE_ALPHA
			var in_b := art_b.get_pixelv(Vector2i((at * Vector2(art_b.get_size())).floor())).a >= OPAQUE_ALPHA
			both += int(in_a and in_b)
			either += int(in_a or in_b)
	return float(both) / either if either > 0 else 0.0


## The SVG at `path` rasterised at its own size (1 pixel per SVG unit), cached.
func _raster(path: String) -> Image:
	if not _art.has(path):
		var image := Image.new()
		var error := image.load_svg_from_string(FileAccess.get_file_as_string(path), 1.0)
		if error != OK:
			_check(false, "rasterise " + path, error_string(error))
		_art[path] = image
	return _art[path]


func _real_texts() -> Dictionary[String, String]:
	var texts: Dictionary[String, String] = {}
	for file in Content.FILES:
		texts[file] = FileAccess.get_file_as_string(Content.DATA_DIR + file)
	return texts


## Loads the real data with `file` changed by `mutate` (a Callable on the parsed array, or
## object for rival_lines.json); returns the loader's errors. Content then holds the mutated data.
func _mutated(file: String, mutate: Callable) -> Array[String]:
	var texts := _real_texts()
	var data: Variant = JSON.parse_string(texts[file])
	mutate.call(data)
	texts[file] = JSON.stringify(data)
	return _load_quietly(texts)


## Loads the real data with `file` replaced by `text`; returns the loader's errors.
func _with_text(file: String, text: String) -> Array[String]:
	var texts := _real_texts()
	texts[file] = text
	return _load_quietly(texts)


func _load_quietly(texts: Dictionary[String, String]) -> Array[String]:
	Content.quiet_errors = true
	Content.load_texts(texts)
	Content.quiet_errors = false
	return Content.errors()


## The loader reported exactly `expected` (each the whole error line, in order).
func _expect_load_errors(label: String, errors: Array[String], expected: Array[String]) -> void:
	_check(_matches(errors, expected), label + " is reported", "got:\n%s\nexpected:\n%s" % ["\n".join(errors), "\n".join(expected)])
	Content.reload()


## `check` (an invariant's problem list) on the mutated data now loaded reports exactly
## `expected` (each the whole problem line, in order), and the loader reported exactly
## `load_errors` (none, unless the mutation also breaks a loader rule), so it is the
## invariant's check that catches the mutation.
func _expect_problems(label: String, errors: Array[String], check: Callable, expected: Array[String], load_errors: Array[String] = []) -> void:
	var problems: Array[String] = check.call()
	_check(_matches(problems, expected), label + " fires", "got:\n%s\nexpected:\n%s" % ["\n".join(problems), "\n".join(expected)])
	_check(_matches(errors, load_errors), label + ": the loader reports only what it must", "\n".join(errors))
	Content.reload()


func _matches(found: Array[String], expected: Array[String]) -> bool:
	if found.size() != expected.size():
		return false
	for i in found.size():
		if found[i] != expected[i]:
			return false
	return true


func _check(condition: bool, test_name: String, detail: String) -> void:
	if condition:
		_passed += 1
		print("test_content: pass " + test_name)
	else:
		_failures.append("%s: %s" % [test_name, detail])
