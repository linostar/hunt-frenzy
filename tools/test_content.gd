extends SceneTree
## Headless content tests: loads huntfrenzy/data/*.json through Content and checks every
## invariant of huntfrenzy/data/SCHEMA.md (I1..I22) against the real data, then proves
## each one fires on a malformed copy of it (the loader's I1-I4, I13, I14 and I15 with the
## exact error lines; I5-I12 and I16-I22 with the exact problems their checks report).
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
## hitbox must cover. The real art measures 0.63 (armored damaged_fly_1) to 0.74 (splitter fly_2):
## the flapping wings, beaks and tails lie outside every hitbox. A box on the body alone
## covers well under a third.
const HITBOX_COVER_MIN := 0.5
## A pixel at least this opaque is part of the bird.
const OPAQUE_ALPHA := 0.5
## I6: the most a decoy's silhouette may overlap any other type's (intersection over
## union of their opaque masks, each sampled on SILHOUETTE_GRID across its own sprite).
## A recoloured copy of a shape overlaps it by 0.89 or more (the armored and golden geese
## overlap the goose by 0.89-1.00); different shapes stay well under 0.85.
const DECOY_OVERLAP_MAX := 0.85
const SILHOUETTE_GRID := Vector2i(48, 36)
## I12: the shortest side a hitbox's bounding box may have, in base units: the game's
## smallest touch target (CLAUDE.md, every interactive Control is at least 44x44).
const HITBOX_SIDE_MIN := 44.0
## I21: each flap frame's imported texture (as the game draws it): its hitbox covers at
## least HITBOX_BODY_COVER_MIN of the opaque pixels, and the hitbox's area is at most
## HITBOX_BODY_AREA_MAX of their area (it never stands for more than the drawn body).
const HITBOX_BODY_COVER_MIN := 0.6
const HITBOX_BODY_AREA_MAX := 1.0
## I22: the least WCAG contrast a bird's outline has against every colour of every
## backdrop's sky (the WCAG minimum for graphics against their background).
const OUTLINE_CONTRAST_MIN := 3.0
## I20, the simulated fairness check: the run seeds it plays (0..SIM_SEEDS - 1), the Endless
## waves it covers (1..SIM_UNTIMED_WAVES; a timed mode: every wave its time_limit can
## reach), and the perfect player: one shot every SIM_SHOT_GAP seconds, each bird shot the
## moment its whole hitbox is above the grass (found to SIM_FRAME, after a coarse search
## in SIM_COARSE_STEP steps), in the order the birds come into the field.
const SIM_SEEDS := 60
const SIM_UNTIMED_WAVES := 10
const SIM_SHOT_GAP := 0.35
const SIM_FRAME := 1.0 / 60.0
const SIM_COARSE_STEP := 0.1

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
		_test_i14_chapters,
		_test_i15_levels,
		_test_i16_three_stars_reachable,
		_test_i17_shells_fit_hits,
		_test_i18_boss_last_and_shaped,
		_test_i19_chapters_introduce_birds,
		_test_i20_modes_are_fair,
		_test_i21_hitbox_covers_body,
		_test_i22_birds_readable,
		_test_i23_music_tracks_exist,
		_test_i24_speed_spread_top_scale,
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


## I1-I4, I13-I15 and I23 hold for the real data: the loader checks them, so clean real data
## means no loader errors.
func _test_real_data_loads_clean() -> void:
	Content.reload()
	_check(Content.errors().is_empty(), "I1-I4, I13-I15 and I23 the real data loads without errors", "\n".join(Content.errors()))


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
	var mode_ids := Content.modes().map(func(spec: ModeSpec) -> String: return spec.id)
	_check(mode_ids == [GameState.ENDLESS_MODE, GameState.TIME_ATTACK_MODE], "modes() lists Endless and Time Attack in data order", str(mode_ids))
	_check(not endless.is_timed() and endless.escape_limit == 10 and endless.time_limit == 0.0, "Endless ends at its escape limit and has no time limit", "escape limit %d, time limit %.1f" % [endless.escape_limit, endless.time_limit])
	var time_attack := Content.mode(GameState.TIME_ATTACK_MODE)
	var time_attack_mix := time_attack.birds.map(func(e: ModeSpec.Entry) -> String: return "%s@%d" % [e.bird, e.from_wave])
	_check(time_attack.is_timed() and time_attack.time_limit == 60.0 and time_attack.escape_limit == 0 and not time_attack.rival_steals and time_attack.name == "Time Attack", "Time Attack lasts 60 s with no escape limit and no steals",
		"time limit %.1f, escape limit %d, steals %s" % [time_attack.time_limit, time_attack.escape_limit, time_attack.rival_steals])
	_check(time_attack_mix == ["goose@1", "armored@2", "zigzag@3", "decoy@3", "splitter@4"] and time_attack.shells_per_hit == 2 and time_attack.combo_cap == 8 and is_equal_approx(time_attack.spawn_interval, 0.9),
		"Time Attack has its own mix, shells per hit, combo cap and spawn interval", "%s, %d, x%d, %.2f s" % [time_attack_mix, time_attack.shells_per_hit, time_attack.combo_cap, time_attack.spawn_interval])
	var lingers := Content.birds().map(func(spec: BirdSpec) -> float: return spec.linger_time)
	_check(lingers == [3.5, 4.0, 3.5, 1.5, 3.5, 2.5, 4.0], "every bird has its linger_time", str(lingers))
	_check(endless.rival_steals, "Endless has the rival's steals on", str(endless.rival_steals))
	var rival := Content.rival_lines()
	var counts := RivalLines.CATEGORIES.map(func(category: String) -> int: return rival.lines[category].size() if rival.lines.has(category) else 0)
	_check(is_equal_approx(rival.aim_time, 1.0) and is_equal_approx(rival.cooldown, 4.0) and counts == [5, 4, 4, 5, 4], "rival_lines() returns the aim time, the cooldown and every category's lines", "aim %.2f, cooldown %.2f, %s" % [rival.aim_time, rival.cooldown, counts])
	var chapter_ids := Content.chapters().map(func(spec: ChapterSpec) -> String: return spec.id)
	_check(chapter_ids == ["dawn", "noon", "sunset", "night"], "chapters() lists the four chapters in campaign order", str(chapter_ids))
	var scales := Content.chapters().map(func(spec: ChapterSpec) -> float: return spec.rival_linger_scale)
	var weathers := Content.chapters().map(func(spec: ChapterSpec) -> String: return spec.weather)
	_check(scales == [1.0, 0.9, 0.8, 0.7] and weathers == ["mist", "wind", "rain", "snow"], "every chapter has its rival linger scale and weather", "%s %s" % [scales, weathers])
	var dawn := Content.chapter("dawn")
	var backdrops := Content.chapters().map(func(spec: ChapterSpec) -> String: return spec.backdrop)
	_check(dawn.name == "Dawn" and backdrops == ["dawn", "noon", "sunset", "night"], "chapter() returns the chapter's name; each chapter names its backdrop", "%s %s" % [dawn.name, backdrops])
	_check(Content.backdrop_path("dawn", "far") == "res://art/backdrops/dawn_far.svg", "backdrop_path() names a backdrop layer's art", Content.backdrop_path("dawn", "far"))
	var looks := endless.stages.map(func(stage: ModeSpec.Stage) -> String: return "%s/%s" % [stage.backdrop, stage.weather])
	_check(looks == ["dawn/mist", "noon/wind", "sunset/rain", "night/snow"] and endless.backdrop_waves == 3, "Endless walks the four backdrops, 3 waves each", "%s every %d" % [looks, endless.backdrop_waves])
	var by_wave := range(1, 15).map(func(index: int) -> String: return endless.stage_for(index).backdrop)
	_check(by_wave == ["dawn", "dawn", "dawn", "noon", "noon", "noon", "sunset", "sunset", "sunset", "night", "night", "night", "night", "night"], "stage_for() moves on every backdrop_waves waves and holds the last", str(by_wave))
	var timed_looks := range(1, 12).map(func(index: int) -> String: return "%s/%s" % [time_attack.stage_for(index).backdrop, time_attack.stage_for(index).weather])
	_check(timed_looks.all(func(look: String) -> bool: return look == "noon/wind"), "Time Attack stays on the noon backdrop with its wind", str(timed_looks))
	_check(Content.levels().size() == 24 and Content.has_level("night_6") and not Content.has_level("night_7"), "levels() lists the 24 levels; has_level() knows them", str(Content.levels().size()))
	var first := Content.level("dawn_1")
	var first_mix := first.mix.map(func(e: ModeSpec.Entry) -> String: return "%s:%d" % [e.bird, e.weight])
	_check(first.chapter == "dawn" and first.index == 1 and first.level_seed == 101 and first.waves == 3 and first.wave_birds == 3 and first_mix == ["goose:10"] and first.golden_bird == "golden"
		and first.golden_chance == 0.0 and first.speed_scale == 1.0 and is_equal_approx(first.spawn_interval, 1.4) and first.shells_per_hit == 3 and first.combo_cap == 3
		and first.stars == [850, 1450, 2050] and not first.is_boss(), "level() returns dawn_1's fields", "%s %d seed %d, %d x %d, %s, stars %s" % [first.chapter, first.index, first.level_seed, first.waves, first.wave_birds, first_mix, first.stars])
	var boss := Content.level("night_6").boss
	var boss_mix := boss.mix.map(func(e: ModeSpec.Entry) -> String: return "%s:%d" % [e.bird, e.weight]) if boss != null else []
	_check(boss != null and boss.birds == 12 and is_equal_approx(boss.spawn_interval, 0.55) and is_equal_approx(boss.speed_scale, 1.6) and boss_mix == ["zigzag:8", "goose:2", "decoy:2"], "night_6 has its boss flock", str(boss_mix))

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
	_expect_load_errors("I1 a mode with both escape_limit and time_limit", _mutated("modes.json", func(data: Array) -> void: data[1]["escape_limit"] = 10),
		["data/modes.json [time_attack] time_limit: not allowed with escape_limit (a mode's run ends at escape_limit lost birds or after time_limit seconds, not both)"])
	_expect_load_errors("I1 a mode with neither escape_limit nor time_limit", _mutated("modes.json", func(data: Array) -> void: (data[0] as Dictionary).erase("escape_limit")),
		["data/modes.json [endless] escape_limit: missing key (a mode needs escape_limit or time_limit: how its run ends)"])
	_expect_load_errors("I1 a timed mode without its time_limit", _mutated("modes.json", func(data: Array) -> void: (data[1] as Dictionary).erase("time_limit")),
		["data/modes.json [time_attack] escape_limit: missing key (a mode needs escape_limit or time_limit: how its run ends)"])
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
	_expect_load_errors("I1 chapter missing a key", _mutated("chapters.json", func(data: Array) -> void: (data[1] as Dictionary).erase("weather")),
		["data/chapters.json [noon] weather: missing key"])
	_expect_load_errors("I1 chapter with an unknown key", _mutated("chapters.json", func(data: Array) -> void: data[0]["soundtrack"] = "banjo"),
		["data/chapters.json [dawn] soundtrack: unknown key"])
	_expect_load_errors("I1 chapter missing its backdrop", _mutated("chapters.json", func(data: Array) -> void: (data[2] as Dictionary).erase("backdrop")),
		["data/chapters.json [sunset] backdrop: missing key"])
	_expect_load_errors("I1 the retired sky_tint", _mutated("chapters.json", func(data: Array) -> void: data[0]["sky_tint"] = "#ffe2c4"),
		["data/chapters.json [dawn] sky_tint: unknown key"])
	_expect_load_errors("I1 a mode missing its backdrops", _mutated("modes.json", func(data: Array) -> void: (data[0] as Dictionary).erase("backdrops")),
		["data/modes.json [endless] backdrops: missing key"])
	_expect_load_errors("I1 a mode missing backdrop_waves", _mutated("modes.json", func(data: Array) -> void: (data[1] as Dictionary).erase("backdrop_waves")),
		["data/modes.json [time_attack] backdrop_waves: missing key"])
	_expect_load_errors("I1 a mode with no backdrops", _mutated("modes.json", func(data: Array) -> void: data[0]["backdrops"] = []),
		["data/modes.json [endless] backdrops: is empty"])
	_expect_load_errors("I1 a mode stage missing a key", _mutated("modes.json", func(data: Array) -> void: (data[0]["backdrops"][1] as Dictionary).erase("weather")),
		["data/modes.json [endless] backdrops[1].weather: missing key"])
	_expect_load_errors("I1 a mode stage with an unknown key", _mutated("modes.json", func(data: Array) -> void: data[0]["backdrops"][0]["music"] = "banjo"),
		["data/modes.json [endless] backdrops[0].music: unknown key"])
	_expect_load_errors("I1 a mode stage not an object", _mutated("modes.json", func(data: Array) -> void: data[1]["backdrops"][0] = "noon"),
		["data/modes.json [time_attack] backdrops[0]: expected Dictionary, got String"])
	_expect_load_errors("I1 level missing a key", _mutated("levels.json", func(data: Array) -> void: (data[0] as Dictionary).erase("stars")),
		["data/levels.json [dawn_1] stars: missing key"])
	_expect_load_errors("I1 level with an unknown key", _mutated("levels.json", func(data: Array) -> void: data[0]["music"] = "banjo"),
		["data/levels.json [dawn_1] music: unknown key"])
	_expect_load_errors("I1 level mix entry with from_wave", _mutated("levels.json", func(data: Array) -> void: data[0]["mix"][0]["from_wave"] = 1),
		["data/levels.json [dawn_1] mix[0].from_wave: unknown key"])
	_expect_load_errors("I1 level mix empty", _mutated("levels.json", func(data: Array) -> void: data[0]["mix"] = []),
		["data/levels.json [dawn_1] mix: is empty"])
	_expect_load_errors("I1 boss flock missing a key", _mutated("levels.json", func(data: Array) -> void: (data[5]["boss"] as Dictionary).erase("speed_scale")),
		["data/levels.json [dawn_6] boss.speed_scale: missing key"])
	_expect_load_errors("I1 boss flock with an unknown key", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["roar"] = true),
		["data/levels.json [dawn_6] boss.roar: unknown key"])
	_expect_load_errors("I1 boss flock not an object", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"] = 10),
		["data/levels.json [dawn_6] boss: expected Dictionary, got float"])
	_expect_load_errors("I1 duplicate level id", _mutated("levels.json", func(data: Array) -> void: data[1]["id"] = "dawn_1"),
		["data/levels.json [dawn_1] id: duplicate id 'dawn_1'"])
	texts = _real_texts()
	texts.erase("levels.json")
	_expect_load_errors("I1 levels file missing", _load_quietly(texts), ["data/levels.json [-] (file): missing"])
	_expect_load_errors("I1 levels file empty", _with_text("levels.json", "[]"), ["data/levels.json [-] (file): has no entries"])


## I2: every field has its type and lies in its range or enum.
func _test_i2_types_and_ranges() -> void:
	_expect_load_errors("I2 wrong type", _mutated("birds.json", func(data: Array) -> void: data[0]["speed"] = "fast"),
		["data/birds.json [goose] speed: expected float, got String"])
	_expect_load_errors("I2 non-integer int", _mutated("birds.json", func(data: Array) -> void: data[0]["hp"] = 1.5),
		["data/birds.json [goose] hp: expected int, got 1.5"])
	_expect_load_errors("I3 unknown chapter id", _mutated("birds.json", func(data: Array) -> void: data[0]["chapter"] = "dusk"),
		["data/birds.json [goose] chapter: unknown chapter id 'dusk'"])
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
	_expect_load_errors("I2 time_limit under 10 s", _mutated("modes.json", func(data: Array) -> void: data[1]["time_limit"] = 5),
		["data/modes.json [time_attack] time_limit: 5.0 is outside 10.0..600.0"])
	_expect_load_errors("I2 time_limit over 600 s", _mutated("modes.json", func(data: Array) -> void: data[1]["time_limit"] = 601),
		["data/modes.json [time_attack] time_limit: 601.0 is outside 10.0..600.0"])
	_expect_load_errors("I2 time_limit not a number", _mutated("modes.json", func(data: Array) -> void: data[1]["time_limit"] = "a minute"),
		["data/modes.json [time_attack] time_limit: expected float, got String"])
	_expect_load_errors("I2 escape_limit out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["escape_limit"] = 0),
		["data/modes.json [endless] escape_limit: 0 is outside 1..100"])
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
	_expect_load_errors("I2 backdrop not a string", _mutated("chapters.json", func(data: Array) -> void: data[0]["backdrop"] = [1, 1, 1]),
		["data/chapters.json [dawn] backdrop: expected String, got Array"])
	_expect_load_errors("I2 backdrop id not snake_case", _mutated("chapters.json", func(data: Array) -> void: data[0]["backdrop"] = "Dawn"),
		["data/chapters.json [dawn] backdrop: 'Dawn' is not a snake_case backdrop id"])
	_expect_load_errors("I2 a mode's backdrop_waves out of range", _mutated("modes.json", func(data: Array) -> void: data[0]["backdrop_waves"] = 0),
		["data/modes.json [endless] backdrop_waves: 0 is outside 1..1000"])
	_expect_load_errors("I2 a mode stage's unknown weather", _mutated("modes.json", func(data: Array) -> void: data[0]["backdrops"][2]["weather"] = "hail"),
		["data/modes.json [endless] backdrops[2].weather: 'hail' is not one of [\"mist\", \"wind\", \"rain\", \"snow\"]"])
	_expect_load_errors("I2 a mode's backdrops not a list", _mutated("modes.json", func(data: Array) -> void: data[1]["backdrops"] = "noon"),
		["data/modes.json [time_attack] backdrops: expected Array, got String"])
	_expect_load_errors("I2 unknown weather", _mutated("chapters.json", func(data: Array) -> void: data[0]["weather"] = "fog"),
		["data/chapters.json [dawn] weather: 'fog' is not one of [\"mist\", \"wind\", \"rain\", \"snow\"]"])
	_expect_load_errors("I2 chapter name too long", _mutated("chapters.json", func(data: Array) -> void: data[0]["name"] = "The Very Early Morning Dawn"),
		["data/chapters.json [dawn] name: length 27 is outside 1..26"])
	_expect_load_errors("I2 level index out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["index"] = 7),
		["data/levels.json [dawn_1] index: 7 is outside 1..6", "data/levels.json [-] chapter: dawn has no level 1 (each chapter has levels 1..6)"])
	_expect_load_errors("I2 level seed negative", _mutated("levels.json", func(data: Array) -> void: data[0]["seed"] = -1),
		["data/levels.json [dawn_1] seed: -1 is outside 0..2147483647"])
	_expect_load_errors("I2 level seed not an int", _mutated("levels.json", func(data: Array) -> void: data[0]["seed"] = 1.5),
		["data/levels.json [dawn_1] seed: expected int, got 1.5"])
	_expect_load_errors("I2 level with no waves", _mutated("levels.json", func(data: Array) -> void: data[0]["waves"] = 0),
		["data/levels.json [dawn_1] waves: 0 is outside 1..20"])
	_expect_load_errors("I2 level wave_birds out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["wave_birds"] = 31),
		["data/levels.json [dawn_1] wave_birds: 31 is outside 1..30"])
	_expect_load_errors("I2 level golden_chance out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["golden_chance"] = -0.1),
		["data/levels.json [dawn_1] golden_chance: -0.1 is outside 0.0..1.0"])
	_expect_load_errors("I2 level speed_scale out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["speed_scale"] = 0.2),
		["data/levels.json [dawn_1] speed_scale: 0.2 is outside 0.5..5.0"])
	_expect_load_errors("I2 level spawn_interval not a number", _mutated("levels.json", func(data: Array) -> void: data[0]["spawn_interval"] = "slow"),
		["data/levels.json [dawn_1] spawn_interval: expected float, got String"])
	_expect_load_errors("I2 level shells_per_hit out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["shells_per_hit"] = 0),
		["data/levels.json [dawn_1] shells_per_hit: 0 is outside 1..10"])
	_expect_load_errors("I2 level combo_cap out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["combo_cap"] = 21),
		["data/levels.json [dawn_1] combo_cap: 21 is outside 1..20"])
	_expect_load_errors("I2 level mix weight out of range", _mutated("levels.json", func(data: Array) -> void: data[0]["mix"][0]["weight"] = 0),
		["data/levels.json [dawn_1] mix[0].weight: 0 is outside 1..100"])
	_expect_load_errors("I2 boss birds out of range", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["birds"] = 0),
		["data/levels.json [dawn_6] boss.birds: 0 is outside 1..30"])
	_expect_load_errors("I2 boss spawn_interval out of range", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["spawn_interval"] = 0.05),
		["data/levels.json [dawn_6] boss.spawn_interval: 0.05 is outside 0.1..10.0"])
	_expect_load_errors("I2 boss mix weight out of range", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["mix"][0]["weight"] = 101),
		["data/levels.json [dawn_6] boss.mix[0].weight: 101 is outside 1..100"])
	_expect_load_errors("I2 stars not three scores", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [100, 200]),
		["data/levels.json [dawn_1] stars: expected an array of 3 scores (1, 2 and 3 stars), got [100.0, 200.0]"])
	_expect_load_errors("I2 a star threshold of 0", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [0, 200, 300]),
		["data/levels.json [dawn_1] stars[0]: 0 is outside 1..10000000"])
	_expect_load_errors("I2 a star threshold not an int", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [100, 200.5, 300]),
		["data/levels.json [dawn_1] stars[1]: expected int, got 200.5"])


## I23: every music track the data names (a chapter's, a mode's) has its loop file; the real
## data names one per chapter and mode, each a different loop.
func _test_i23_music_tracks_exist() -> void:
	var tracks: Array[String] = []
	for spec in Content.chapters():
		tracks.append(spec.music)
	for spec in Content.modes():
		tracks.append(spec.music)
	_check(tracks == ["campaign_dawn", "campaign_noon", "campaign_sunset", "campaign_night", "endless", "time_attack"], "I23 every chapter and mode names its own track", str(tracks))
	for track in tracks:
		_check(ResourceLoader.exists(Content.music_path(track)), "I23 track %s exists" % track, Content.music_path(track))
	_expect_load_errors("I23 a chapter's track with no file", _mutated("chapters.json", func(data: Array) -> void: data[1]["music"] = "campaign_dusk"),
		["data/chapters.json [noon] music: unknown music track 'campaign_dusk' (no res://audio/music/campaign_dusk.mp3)"])
	_expect_load_errors("I23 a mode's track with no file", _mutated("modes.json", func(data: Array) -> void: data[1]["music"] = "boss_fight"),
		["data/modes.json [time_attack] music: unknown music track 'boss_fight' (no res://audio/music/boss_fight.mp3)"])
	_expect_load_errors("I23 a track id that is not snake_case", _mutated("chapters.json", func(data: Array) -> void: data[0]["music"] = "Campaign Dawn"),
		["data/chapters.json [dawn] music: 'Campaign Dawn' is not a snake_case music track id"])
	_expect_load_errors("I23 a track that is not a string", _mutated("modes.json", func(data: Array) -> void: data[0]["music"] = 3),
		["data/modes.json [endless] music: expected String, got float"])
	_expect_load_errors("I23 a chapter without a track", _mutated("chapters.json", func(data: Array) -> void: (data[2] as Dictionary).erase("music")),
		["data/chapters.json [sunset] music: missing key"])
	_expect_load_errors("I23 a mode without a track", _mutated("modes.json", func(data: Array) -> void: (data[0] as Dictionary).erase("music")),
		["data/modes.json [endless] music: missing key"])


## I3: every reference resolves (mix birds, golden_bird, splits_into), every sprite has
## its frames (the damaged flap frames too when hp > 1) and every backdrop its layers.
func _test_i3_references() -> void:
	var dusk: Array[String] = []
	for layer in Content.BACKDROP_LAYERS:
		dusk.append("data/chapters.json [night] backdrop: unknown backdrop 'dusk' (no res://art/backdrops/dusk_%s.svg)" % layer)
	_expect_load_errors("I3 a chapter's backdrop with no art", _mutated("chapters.json", func(data: Array) -> void: data[3]["backdrop"] = "dusk"), dusk)
	var mode_dusk: Array[String] = []
	for line in dusk:
		mode_dusk.append(line.replace("data/chapters.json [night] backdrop", "data/modes.json [endless] backdrops[3].backdrop"))
	_expect_load_errors("I3 a mode stage's backdrop with no art", _mutated("modes.json", func(data: Array) -> void: data[0]["backdrops"][3]["backdrop"] = "dusk"), mode_dusk)
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
	_expect_load_errors("I3 a level of an unknown chapter", _mutated("levels.json", func(data: Array) -> void: data[0]["chapter"] = "dusk"),
		["data/levels.json [dawn_1] chapter: unknown chapter id 'dusk'", "data/levels.json [-] chapter: dawn has no level 1 (each chapter has levels 1..6)"])
	_expect_load_errors("I3 an unknown level mix bird", _mutated("levels.json", func(data: Array) -> void: data[0]["mix"][0]["bird"] = "swan"),
		["data/levels.json [dawn_1] mix[0].bird: unknown bird id 'swan'"])
	_expect_load_errors("I3 an unknown boss mix bird", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["mix"][0]["bird"] = "swan"),
		["data/levels.json [dawn_6] boss.mix[0].bird: unknown bird id 'swan'"])
	_expect_load_errors("I3 an unknown level golden bird", _mutated("levels.json", func(data: Array) -> void: data[0]["golden_bird"] = "phoenix"),
		["data/levels.json [dawn_1] golden_bird: unknown bird id 'phoenix'"])
	_expect_load_errors("I3 a bird twice in a level mix", _mutated("levels.json", func(data: Array) -> void: data[6]["mix"][1]["bird"] = "goose"),
		["data/levels.json [noon_1] mix[1].bird: 'goose' is already in the mix (mix[0])"])


## I4: every hitbox has at least 3 points, all inside the sprite, and is a simple polygon.
func _test_i4_hitbox_geometry() -> void:
	_expect_load_errors("I4 too few points", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[0, 0], [10, 0]]),
		["data/birds.json [goose] hitbox: has 2 points, needs at least 3"])
	_expect_load_errors("I4 point outside the sprite", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"][0] = [-50, 0]),
		["data/birds.json [goose] hitbox[0]: (-50.0, 0.0) is outside the sprite (±(48.0, 36.0))"])
	# A bad size falls back to (0, 0) or its minimum; the hitbox is not checked against it.
	_expect_load_errors("I4 a missing size does not fail the hitbox", _mutated("birds.json", func(data: Array) -> void: (data[0] as Dictionary).erase("size")),
		["data/birds.json [goose] size: missing key"])
	_expect_load_errors("I4 an out-of-range size does not fail the hitbox", _mutated("birds.json", func(data: Array) -> void: data[0]["size"] = [4, 72]),
		["data/birds.json [goose] size[0]: 4.0 is outside 8.0..400.0"])
	_expect_load_errors("I4 a mistyped size does not fail the hitbox", _mutated("birds.json", func(data: Array) -> void: data[0]["size"] = "big"),
		["data/birds.json [goose] size: expected an array of 2 numbers [x, y], got big"])
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
		["goose fly_1: 81.8% of the hitbox's sample points lie on opaque art (needs 98%)", "goose fly_2: 76.8% of the hitbox's sample points lie on opaque art (needs 98%)"])
	# A 20x16 box on the goose's body: all of it on the art, but most of the art outside it.
	_expect_problems("I5 a hitbox covering little of the art", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-10, -2], [10, -2], [10, 14], [-10, 14]]), _i5_problems,
		["goose fly_1: the hitbox covers 12.6% of the opaque art (needs 50%)", "goose fly_2: the hitbox covers 13.4% of the opaque art (needs 50%)"])


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
		["decoy: its silhouette overlaps goose's by 0.95 (at most 0.85: a decoy differs by shape)", "decoy: its silhouette overlaps armored's by 0.89 (at most 0.85: a decoy differs by shape)",
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
	_expect_problems("I7 a child in a level's mix", _mutated("levels.json", func(data: Array) -> void: data[12]["mix"].append({"bird": "gosling", "weight": 1})), _i7_problems,
		["gosling: a split child never spawns from waves (sunset_1)"])
	_expect_problems("I7 a child in a boss flock", _mutated("levels.json", func(data: Array) -> void: data[17]["boss"]["mix"].append({"bird": "gosling", "weight": 1})), _i7_problems,
		["gosling: a split child never spawns from waves (sunset_6)"])


## I8: a mode's golden bird is not in its mix, has hp 1, does not split, is not a decoy,
## and is faster and worth more points than every bird of the mix.
func _test_i8_golden_and_mix() -> void:
	_check(_i8_problems().is_empty(), "I8 the golden bird rules hold", "\n".join(_i8_problems()))
	# Endless, Time Attack and every night level (the ones with zigzags) share the golden bird.
	_expect_problems("I8 a slow golden bird", _mutated("birds.json", func(data: Array) -> void: data[5]["speed"] = 150), _i8_problems,
		_per_owner(["endless", "time_attack", "night_1", "night_2", "night_3", "night_4", "night_5", "night_6"], "golden bird golden (speed 150.0) is not faster than zigzag (speed 175.0)"))
	_expect_problems("I8 a cheap golden bird", _mutated("birds.json", func(data: Array) -> void: data[5]["points"] = 180), _i8_problems,
		_per_owner(["endless", "time_attack", "night_1", "night_2", "night_3", "night_4", "night_5", "night_6"], "golden bird golden (180 points) is not worth more than zigzag (200 points)"))
	_expect_problems("I8 the golden bird in the mix", _mutated("modes.json", func(data: Array) -> void: data[0]["birds"].append({"bird": "golden", "from_wave": 9, "weight": 1})), _i8_problems,
		["endless: golden bird golden is also in the mix"])
	_expect_problems("I8 a golden decoy", _mutated("birds.json", func(data: Array) -> void:
		data[5]["penalty"] = 10
		data[5]["escape_counts"] = false), _i8_problems,
		_per_owner(["endless", "time_attack"] + Campaign.levels().map(func(level: LevelSpec) -> String: return level.id), "golden bird golden must have hp 1, no split and no penalty"))
	_expect_problems("I8 a level's golden bird in its mix", _mutated("levels.json", func(data: Array) -> void: data[1]["mix"].append({"bird": "golden", "weight": 1})), _i8_problems,
		["dawn_2: golden bird golden is also in the mix"])


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
	# The campaign's first level: its wave 1 (fixed seed) is three plain geese.
	_expect_problems("I9 a golden bird in the campaign's first wave", _mutated("levels.json", func(data: Array) -> void: data[0]["golden_chance"] = 1.0), _i9_problems,
		["dawn_1: wave 1 spawns golden, golden, golden, not plain birds only (the campaign's first wave is plain)"])
	_expect_problems("I9 an armored bird in the campaign's first wave", _mutated("levels.json", func(data: Array) -> void: data[0]["mix"] = [{"bird": "armored", "weight": 1}]), _i9_problems,
		["dawn_1: wave 1 spawns armored, armored, armored, not plain birds only (the campaign's first wave is plain)"])


## I10: the roster holds every kind (plain, armored, splitter, zigzag, golden, decoy),
## each chapter of chapters.json introduces at least one bird, and every bird can appear (in
## a mode's or a level's mix, as a golden bird or as a split child).
func _test_i10_roster_and_chapters() -> void:
	_check(_i10_problems().is_empty(), "I10 every kind, chapter and bird is covered", "\n".join(_i10_problems()))
	_expect_problems("I10 no zigzag", _mutated("birds.json", func(data: Array) -> void: data[4]["pattern"] = "rise"), _i10_problems,
		["no zigzag bird (pattern zigzag)"])
	_expect_problems("I10 no armored bird", _mutated("birds.json", func(data: Array) -> void:
		data[1]["hp"] = 1), _i10_problems,
		["no armored bird (hp 2 or more)"])
	_expect_problems("I10 a chapter introducing nothing", _mutated("birds.json", func(data: Array) -> void: data[4]["chapter"] = "sunset"), _i10_problems,
		["chapter night introduces no bird"])
	# Out of every mode's mix and every level's: the zigzag can no longer appear anywhere.
	_expect_problems("I10 a bird that never appears", _mutated_files({
		"modes.json": func(data: Array) -> void:
			for mode: Dictionary in data:
				mode["birds"] = (mode["birds"] as Array).filter(func(e: Dictionary) -> bool: return e["bird"] != "zigzag"),
		"levels.json": func(data: Array) -> void:
			for level: Dictionary in data:
				level["mix"] = (level["mix"] as Array).filter(func(e: Dictionary) -> bool: return e["bird"] != "zigzag")
				if level.has("boss"):
					level["boss"]["mix"] = (level["boss"]["mix"] as Array).filter(func(e: Dictionary) -> bool: return e["bird"] != "zigzag"),
		}), _i10_problems,
		["no zigzag bird (pattern zigzag)", "chapter night introduces no bird", "zigzag never appears (not in a mix, not a golden bird, not a split child)"])


## I11: every bird fits the field it flies in (Play.FIELD): narrower and lower than it.
## The wobble (title only) takes no part: a tall-wobbling bird that fits passes.
func _test_i11_fits_field() -> void:
	_check(_i11_problems().is_empty(), "I11 every bird fits the field", "\n".join(_i11_problems()))
	_expect_problems("I11 a bird as tall as the field", _mutated("birds.json", func(data: Array) -> void: data[0]["size"] = [96, 384]), _i11_problems,
		["goose: size (96.0, 384.0) does not fit the field (960.0, 384.0)"])
	_expect_problems("I11 a bird that fits, with a wobble its height plus twice would not", _mutated("birds.json", func(data: Array) -> void:
		data[0]["size"] = [96, 300]
		data[0]["wobble"] = 50), _i11_problems, [])


## I12: every hitbox's bounding box is at least HITBOX_SIDE_MIN on each side, so a
## fingertip can hit every bird.
func _test_i12_hitbox_touch_size() -> void:
	_check(_i12_problems().is_empty(), "I12 every hitbox is big enough to touch", "\n".join(_i12_problems()))
	# The step 3 gosling: 56x42 art with a 38x27 hitbox.
	_expect_problems("I12 a hitbox smaller than a fingertip", _mutated("birds.json", func(data: Array) -> void:
		data[3]["size"] = [56, 42]
		data[3]["hitbox"] = [[-18, 6], [-14, -2], [-4, -4], [6, -3], [8, -10], [13, -12], [19, -9], [20, -3], [14, 2], [12, 9], [-4, 15], [-14, 12]]), _i12_problems,
		["gosling: hitbox bounding box (38.0, 27.0) is under 44 base units on a side (the smallest touch target)"])


## I13 (the loader's): every bird but the decoy has every linger the rival uses (linger_time
## in a mode with rival_steals, linger_time x rival_linger_scale in each chapter) + the
## rival's aim_time under its flee_time, so every aim cue can finish before the bird flees
## on its own.
func _test_i13_cue_ends_before_fleeing() -> void:
	_expect_load_errors("I13 a goose lingering into its flight off", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = 5.5),
		["data/birds.json [goose] linger_time: 5.5 x 1.0 (endless, dawn) + aim_time 1.0 is not under flee_time 6.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 a cue ending exactly at flee_time", _mutated("birds.json", func(data: Array) -> void: data[3]["linger_time"] = 2.0),
		["data/birds.json [gosling] linger_time: 2.0 x 1.0 (endless, dawn) + aim_time 1.0 is not under flee_time 3.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 an aim too long for the fast birds", _mutated("rival_lines.json", func(data: Dictionary) -> void: data["aim_time"] = 1.6),
		["data/birds.json [gosling] linger_time: 1.5 x 1.0 (endless, dawn) + aim_time 1.6 is not under flee_time 3.0 (I13: the rival's cue must end before the bird flees)",
		"data/birds.json [golden] linger_time: 2.5 x 1.0 (endless, dawn) + aim_time 1.6 is not under flee_time 4.0 (I13: the rival's cue must end before the bird flees)"])
	# With Endless's steals off only the chapters' scaled lingers count: 5.8 x 0.9 + 1.0
	# fails noon (and dawn's 5.8 x 1.0), 5.8 x 0.8 + 1.0 = 5.64 passes sunset.
	_expect_load_errors("I13 holds with each chapter's scaled linger", _mutated_files({
		"modes.json": func(data: Array) -> void: data[0]["rival_steals"] = false,
		"birds.json": func(data: Array) -> void: data[0]["linger_time"] = 5.8,
		}), ["data/birds.json [goose] linger_time: 5.8 x 1.0 (dawn, noon) + aim_time 1.0 is not under flee_time 6.0 (I13: the rival's cue must end before the bird flees)"])
	_expect_load_errors("I13 the scaled linger of a quicker chapter passes", _mutated_files({
		"modes.json": func(data: Array) -> void: data[0]["rival_steals"] = false,
		"chapters.json": func(data: Array) -> void: data[0]["rival_linger_scale"] = 0.9,
		"birds.json": func(data: Array) -> void: data[0]["linger_time"] = 5.5,
		}), [])
	_expect_load_errors("I13 skips a chapter whose scale failed", _mutated_files({
		"modes.json": func(data: Array) -> void: data[0]["rival_steals"] = false,
		"chapters.json": func(data: Array) -> void: data[0]["rival_linger_scale"] = 0,
		"birds.json": func(data: Array) -> void: data[0]["linger_time"] = 5.5,
		}), ["data/chapters.json [dawn] rival_linger_scale: 0.0 is outside (0.0, 1.0]"])
	_expect_load_errors("I13 the decoy is exempt (never stolen)", _mutated("birds.json", func(data: Array) -> void: data[6]["linger_time"] = 9.0), [])
	# A bad flee_time falls back to its minimum (0.1); I13 must not blame linger_time for it.
	_expect_load_errors("I13 skips a missing flee_time", _mutated("birds.json", func(data: Array) -> void: (data[0] as Dictionary).erase("flee_time")),
		["data/birds.json [goose] flee_time: missing key"])
	_expect_load_errors("I13 skips a zero flee_time", _mutated("birds.json", func(data: Array) -> void: data[0]["flee_time"] = 0),
		["data/birds.json [goose] flee_time: 0.0 is outside 0.1..60.0"])
	_expect_load_errors("I13 skips a flee_time that is not a number", _mutated("birds.json", func(data: Array) -> void: data[0]["flee_time"] = "soon"),
		["data/birds.json [goose] flee_time: expected float, got String"])


## I14 (the loader's): chapters.json holds exactly Content.CHAPTER_COUNT chapters, each
## rival_linger_scale in (0, 1] and at most the chapter before's.
func _test_i14_chapters() -> void:
	var dusk_levels: Array[String] = ["data/chapters.json [-] (file): has 5 chapters, needs exactly 4"]
	for index in range(1, 7):
		dusk_levels.append("data/levels.json [-] chapter: dusk has no level %d (each chapter has levels 1..6)" % index)
	_expect_load_errors("I14 a fifth chapter", _mutated("chapters.json", func(data: Array) -> void:
		data.append({"id": "dusk", "name": "Dusk", "backdrop": "night", "music": "campaign_night", "weather": "rain", "rival_linger_scale": 0.6})), dusk_levels)
	_expect_load_errors("I14 a rival_linger_scale of 0", _mutated("chapters.json", func(data: Array) -> void: data[1]["rival_linger_scale"] = 0),
		["data/chapters.json [noon] rival_linger_scale: 0.0 is outside (0.0, 1.0]"])
	_expect_load_errors("I14 a rival_linger_scale above 1", _mutated("chapters.json", func(data: Array) -> void: data[0]["rival_linger_scale"] = 1.2),
		["data/chapters.json [dawn] rival_linger_scale: 1.2 is outside (0.0, 1.0]"])
	_expect_load_errors("I14 a rival_linger_scale that is not a number", _mutated("chapters.json", func(data: Array) -> void: data[0]["rival_linger_scale"] = "soon"),
		["data/chapters.json [dawn] rival_linger_scale: expected float, got String"])
	_expect_load_errors("I14 a rival who gets slower", _mutated("chapters.json", func(data: Array) -> void: data[2]["rival_linger_scale"] = 0.95),
		["data/chapters.json [sunset] rival_linger_scale: 0.95 is above noon's 0.9 (the rival never gets slower: a chapter's scale is at most the one before's)"])
	_expect_load_errors("I14 a rival as quick as the chapter before", _mutated("chapters.json", func(data: Array) -> void: data[2]["rival_linger_scale"] = 0.9), [])


## I15 (the loader's): every chapter has exactly its levels 1..Content.LEVELS_PER_CHAPTER,
## the last (and only it) with a boss flock, and every level's star thresholds rise strictly.
func _test_i15_levels() -> void:
	_expect_load_errors("I15 two levels at one index", _mutated("levels.json", func(data: Array) -> void: data[7]["index"] = 1),
		["data/levels.json [noon_2] index: 1 of chapter noon is already level noon_1", "data/levels.json [-] chapter: noon has no level 2 (each chapter has levels 1..6)"])
	_expect_load_errors("I15 a missing level", _mutated("levels.json", func(data: Array) -> void: data.remove_at(20)),
		["data/levels.json [-] chapter: night has no level 3 (each chapter has levels 1..6)"])
	_expect_load_errors("I15 a boss before level 6", _mutated("levels.json", func(data: Array) -> void: data[4]["boss"] = (data[5]["boss"] as Dictionary).duplicate(true)),
		["data/levels.json [dawn_5] boss: level 5 is no boss level (only level 6 is)"])
	_expect_load_errors("I15 level 6 without its boss", _mutated("levels.json", func(data: Array) -> void: (data[5] as Dictionary).erase("boss")),
		["data/levels.json [dawn_6] boss: missing key (level 6 is its chapter's boss level)"])
	_expect_load_errors("I15 star thresholds that do not rise", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [100, 100, 300]),
		["data/levels.json [dawn_1] stars[1]: 100 is not above stars[0] 100 (the thresholds rise strictly)"])
	_expect_load_errors("I15 star thresholds that fall", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [100, 300, 200]),
		["data/levels.json [dawn_1] stars[2]: 200 is not above stars[1] 300 (the thresholds rise strictly)"])


## I16: each level's 3-star threshold is at most its highest sure score (Campaign.max_score:
## every bird but the decoy killed with the shells its waves get, the combo rising to
## combo_cap and never broken), so three stars can be reached.
func _test_i16_three_stars_reachable() -> void:
	_check(_i16_problems().is_empty(), "I16 every level's three stars can be reached", "\n".join(_i16_problems()))
	_check(Campaign.max_score(Content.level("dawn_1")) == 2400, "dawn_1's highest score is its 9 geese at x1, x2 and then x3", str(Campaign.max_score(Content.level("dawn_1"))))
	_expect_problems("I16 a 3-star threshold above the highest score", _mutated("levels.json", func(data: Array) -> void: data[0]["stars"] = [850, 1450, 2401]), _i16_problems,
		["dawn_1: 3 stars at 2401 is above the most it can score, 2400 (every bird but the decoy killed, the combo rising to x3)"])
	_expect_problems("I16 a combo cap too low for the thresholds", _mutated("levels.json", func(data: Array) -> void: data[0]["combo_cap"] = 1), _i16_problems,
		["dawn_1: 3 stars at 2050 is above the most it can score, 900 (every bird but the decoy killed, the combo rising to x1)"])


## I17: every wave of every level has the shells for every hit its birds need (Wave.hits_needed).
func _test_i17_shells_fit_hits() -> void:
	_check(_i17_problems(Wave.campaign).is_empty(), "I17 every level's waves have the shells for every hit", "\n".join(_i17_problems(Wave.campaign)))
	# A schedule that hands dawn_1's first wave (3 geese: 3 hits) one shell too few.
	var short := func(level: LevelSpec, wave_index: int) -> Wave.Plan:
		var plan := Wave.campaign(level, wave_index)
		if level.id == "dawn_1" and wave_index == 1:
			plan.shells = 2
		return plan
	var problems := _i17_problems(short)
	_check(_matches(problems, ["dawn_1 wave 1: 2 shells for the 3 hits its birds need"]), "I17 a wave short of shells fires", "\n".join(problems))


## I18: each chapter's last level is its one boss level, and its boss flock has more birds,
## a shorter spawn interval and a higher speed than every other wave of the chapter, and is
## weighted toward a bird the chapter introduces (its heaviest bird, no decoy, no golden bird).
func _test_i18_boss_last_and_shaped() -> void:
	_check(_i18_problems().is_empty(), "I18 every chapter ends on its boss flock", "\n".join(_i18_problems()))
	_expect_problems("I18 a boss flock no bigger than a wave", _mutated("levels.json", func(data: Array) -> void: data[5]["boss"]["birds"] = 5), _i18_problems,
		["dawn_6: the boss flock's 5 birds are not more than dawn_4's 5 per wave"])
	_expect_problems("I18 a boss flock no denser than a wave", _mutated("levels.json", func(data: Array) -> void: data[11]["boss"]["spawn_interval"] = 1.3), _i18_problems,
		["noon_6: the boss flock's spawn interval 1.3 s is not shorter than noon_1's 1.3 s"])
	_expect_problems("I18 a boss flock no faster than a wave", _mutated("levels.json", func(data: Array) -> void: data[17]["boss"]["speed_scale"] = 1.3), _i18_problems,
		["sunset_6: the boss flock's speed x1.3 is not higher than sunset_5's x1.3"])
	_expect_problems("I18 a boss flock weighted toward an older bird", _mutated("levels.json", func(data: Array) -> void: data[11]["boss"]["mix"] = [{"bird": "armored", "weight": 2}, {"bird": "goose", "weight": 8}]), _i18_problems,
		["noon_6: the boss flock is weighted toward goose (introduced in dawn), not a bird noon introduces"])
	_expect_problems("I18 a boss flock weighted toward the decoy", _mutated("levels.json", func(data: Array) -> void: data[17]["boss"]["mix"] = [{"bird": "splitter", "weight": 2}, {"bird": "decoy", "weight": 8}]), _i18_problems,
		["sunset_6: the boss flock is weighted toward decoy (a decoy), not a bird sunset introduces"])
	_expect_problems("I18 the boss on a level before the last", _mutated("levels.json", func(data: Array) -> void:
		data[4]["boss"] = data[5]["boss"]
		(data[5] as Dictionary).erase("boss")), _i18_problems,
		["chapter dawn: its boss level is dawn_5, not its last level dawn_6"],
		["data/levels.json [dawn_5] boss: level 5 is no boss level (only level 6 is)", "data/levels.json [dawn_6] boss: missing key (level 6 is its chapter's boss level)"])


## I19: no level uses a bird a later chapter introduces (in its mixes, as its golden bird or
## as a split child), every bird a chapter introduces spawns in at least one of its levels'
## (fixed-seed) waves, and a golden bird spawns in every chapter.
func _test_i19_chapters_introduce_birds() -> void:
	_check(_i19_problems().is_empty(), "I19 every chapter introduces its birds, golden birds in every chapter", "\n".join(_i19_problems()))
	_expect_problems("I19 a level using a later chapter's bird", _mutated("levels.json", func(data: Array) -> void: data[1]["mix"].append({"bird": "zigzag", "weight": 1})), _i19_problems,
		["dawn_2 uses zigzag (introduced in night, after dawn)"])
	_expect_problems("I19 a later chapter's bird as a split child", _mutated("levels.json", func(data: Array) -> void: data[1]["mix"].append({"bird": "splitter", "weight": 1})), _i19_problems,
		["dawn_2 uses splitter (introduced in sunset, after dawn)", "dawn_2 uses gosling (introduced in sunset, after dawn)"])
	_expect_problems("I19 a chapter whose bird never spawns", _mutated("levels.json", func(data: Array) -> void:
		for level: Dictionary in data:
			if level["chapter"] == "sunset":
				level["mix"] = (level["mix"] as Array).filter(func(e: Dictionary) -> bool: return e["bird"] != "decoy")
				if level.has("boss"):
					level["boss"]["mix"] = (level["boss"]["mix"] as Array).filter(func(e: Dictionary) -> bool: return e["bird"] != "decoy")), _i19_problems,
		["chapter sunset introduces decoy, but none of its levels spawns it"])
	_expect_problems("I19 a chapter without a golden bird", _mutated("levels.json", func(data: Array) -> void:
		for level: Dictionary in data:
			if level["chapter"] == "noon":
				level["golden_chance"] = 0), _i19_problems,
		["chapter noon: none of its levels spawns a golden bird"])


## I20: the modes are fair, by simulation against the real data (Wave.for_mode, Ammo and
## Flight, as in play), over SIM_SEEDS run seeds: Endless's waves 1..SIM_UNTIMED_WAVES and
## every wave a timed mode's time_limit can reach never lose birds or speed from one wave
## to the next, give the shells for every hit their birds need, and let a perfect player
## kill every bird but the decoy before the rival's cue (modes with steals) and before it
## flees. Each part is shown to fire: a stand-in schedule drops birds, speed or a shell; a
## bird whose linger_time is shorter than it takes to come into the field fails Endless; a
## Time Attack flock too dense for one gun fails it.
func _test_i20_modes_are_fair() -> void:
	var sim := _i20_sim(Wave.for_mode)
	_check((sim["problems"] as Array).is_empty(), "I20 Endless and Time Attack are fair to a perfect player", "\n".join(sim["problems"]))
	_check(sim["waves"] == {"endless": SIM_UNTIMED_WAVES, "time_attack": 11}, "I20 covers Endless's waves 1-10 and the 11 waves a 60 s Time Attack can reach", str(sim["waves"]))
	_check(sim["kills"] > 1000, "I20 the perfect player kills every simulated bird", "%d kills" % sim["kills"])
	print("test_content: I20 tightest margins (s before the cue or the flee): %s" % sim["margins"])
	var fewer := func(mode: ModeSpec, wave_index: int, run_seed: int) -> Wave.Plan:
		var plan := Wave.for_mode(mode, wave_index, run_seed)
		if mode.id == "endless" and wave_index == 4:
			plan.spawns.resize(Wave.for_mode(mode, 3, run_seed).spawns.size() - 1)
		return plan
	_check(_matches(_i20_sim(fewer)["problems"], ["endless wave 4: fewer birds than wave 3 in %d of %d seeds" % [SIM_SEEDS, SIM_SEEDS]]), "I20 a wave with fewer birds than the one before fires", "\n".join(_i20_sim(fewer)["problems"]))
	var slower := func(mode: ModeSpec, wave_index: int, run_seed: int) -> Wave.Plan:
		var plan := Wave.for_mode(mode, wave_index, run_seed)
		if mode.id == "time_attack" and wave_index == 6:
			plan.speed_scale = Wave.speed_scale(mode, 5) - 0.01
		return plan
	_check(_matches(_i20_sim(slower)["problems"], ["time_attack wave 6: slower than wave 5 in %d of %d seeds" % [SIM_SEEDS, SIM_SEEDS]]), "I20 a wave slower than the one before fires", "\n".join(_i20_sim(slower)["problems"]))
	var short := func(mode: ModeSpec, wave_index: int, run_seed: int) -> Wave.Plan:
		var plan := Wave.for_mode(mode, wave_index, run_seed)
		if mode.id == "time_attack" and wave_index == 2:
			# One shell fewer than the hits its birds need.
			plan.shells = -1
			for spawn in plan.spawns:
				plan.shells += Wave.hits_needed(Content.bird(spawn.bird_id))
		return plan
	_check(_matches(_i20_sim(short)["problems"], ["time_attack wave 2: fewer shells than the hits its birds need (the perfect player runs out) in %d of %d seeds" % [SIM_SEEDS, SIM_SEEDS]]), "I20 a wave short of shells fires", "\n".join(_i20_sim(short)["problems"]))
	# The goose is in the field only a while after it spawns: a 0.1 s linger lets the rival
	# aim at every goose first (Endless steals; Time Attack does not, so it is unaffected).
	_expect_problems("I20 a bird the rival aims at before it is in the field", _mutated("birds.json", func(data: Array) -> void: data[0]["linger_time"] = 0.1), func() -> Array[String]: return _i20_sim(Wave.for_mode)["problems"],
		["endless: a perfect player kills goose only after the rival's cue (at 0.10 s) in waves 1-10"])
	# 30 geese 0.1 s apart (no other bird): one gun cannot kill them all before they flee.
	_expect_problems("I20 a flock too dense for one gun", _mutated("modes.json", func(data: Array) -> void:
		data[1]["birds"] = [{"bird": "goose", "from_wave": 1, "weight": 1}]
		data[1]["golden_chance"] = 0
		data[1]["start_birds"] = 30
		data[1]["max_birds"] = 30
		data[1]["spawn_interval"] = 0.1), func() -> Array[String]: return _i20_sim(Wave.for_mode)["problems"],
		["time_attack: a perfect player kills goose only after it flees (at 6.00 s) in waves 1-16"])


## I21: every hitbox stands for its drawn body, measured on the imported textures the game
## draws: it covers at least HITBOX_BODY_COVER_MIN of each flap frame's opaque pixels, and
## its area is at most HITBOX_BODY_AREA_MAX of theirs.
func _test_i21_hitbox_covers_body() -> void:
	_check(_i21_problems().is_empty(), "I21 every hitbox covers its bird's body", "\n".join(_i21_problems()))
	# A 20x16 box on the goose's body: on the art, but most of the body outside it.
	_expect_problems("I21 a hitbox covering little of the body", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-10, -2], [10, -2], [10, 14], [-10, 14]]), _i21_problems,
		["goose fly_1: the hitbox covers 12.6% of the imported texture's opaque body (needs 60%)", "goose fly_2: the hitbox covers 13.5% of the imported texture's opaque body (needs 60%)"],
		[])
	# The whole sprite: it covers all of the body, but its area is far larger.
	_expect_problems("I21 a hitbox larger than the body", _mutated("birds.json", func(data: Array) -> void: data[0]["hitbox"] = [[-48, -36], [48, -36], [48, 36], [-48, 36]]), _i21_problems,
		["goose fly_1: the hitbox's area is 272.6% of the imported texture's opaque body (at most 100%)", "goose fly_2: the hitbox's area is 291.4% of the imported texture's opaque body (at most 100%)"],
		[])


## I22: every bird is readable on every backdrop: its outline (the stroke of its fly_1
## silhouette, the first path of the art) has a WCAG contrast of at least
## OUTLINE_CONTRAST_MIN against every colour of every backdrop's sky layer, and the night
## (the last chapter's backdrop) keeps the birds as visible as the day: its weakest outline
## contrast is not under the weakest of the other chapters' backdrops. The main fills'
## contrasts are printed for the record. Each part is shown to fire on stand-in sky colours.
func _test_i22_birds_readable() -> void:
	var problems := _i22_problems(_sky_colours)
	_check(problems.is_empty(), "I22 every bird's outline reads on every backdrop's sky, the night's included", "\n".join(problems))
	for spec in Content.birds():
		var art := _bird_colours(spec)
		var fills := PackedStringArray()
		for backdrop in _backdrop_ids():
			var weakest := INF
			for sky in _sky_colours(backdrop):
				weakest = minf(weakest, _contrast(art[1], sky))
			fills.append("%s %.2f" % [backdrop, weakest])
		print("test_content: I22 %s outline #%s, fill #%s, weakest fill contrast per sky: %s" % [spec.id, art[0].to_html(false), art[1].to_html(false), ", ".join(fills)])
	_check(Content.birds().all(func(spec: BirdSpec) -> bool: return _bird_colours(spec)[0] == Color.html("#1f1a2e")), "I22 every bird is outlined in the palette's ink", str(Content.birds().map(func(spec: BirdSpec) -> String: return _bird_colours(spec)[0].to_html(false))))
	# A plum cloud in the sunset sky: too dark under every bird's ink outline.
	var plum := Color.html("#5e4470")
	var with_plum := func(backdrop: String) -> Array[Color]:
		var colours := _sky_colours(backdrop)
		if backdrop == "sunset":
			colours.append(plum)
		return colours
	var expected: Array[String] = []
	for spec in Content.birds():
		expected.append("%s: its outline #1f1a2e on the sunset sky's #5e4470 is %.2f:1 (needs 3:1)" % [spec.id, _contrast(Color.html("#1f1a2e"), plum)])
	_check(_matches(_i22_problems(with_plum), expected), "I22 a sky colour too dark for the outlines fires", "\n".join(_i22_problems(with_plum)))
	# A night sky darker than the day's weakest, though still readable: the night rule alone.
	var night: String = (Content.chapters().back() as ChapterSpec).backdrop
	var dim := Color.html("#2f7fa8")
	var dim_night := func(backdrop: String) -> Array[Color]:
		if backdrop == night:
			var dimmed: Array[Color] = [dim]
			return dimmed
		return _sky_colours(backdrop)
	var day_weakest := INF
	for backdrop in _backdrop_ids():
		if backdrop != night:
			for sky in _sky_colours(backdrop):
				day_weakest = minf(day_weakest, _contrast(Color.html("#1f1a2e"), sky))
	_check(_matches(_i22_problems(dim_night), ["night: its weakest outline contrast %.2f:1 is under the day backdrops' weakest %.2f:1 (the birds must read as well at night)" % [_contrast(Color.html("#1f1a2e"), dim), day_weakest]]),
		"I22 a night dimmer than the day fires", "\n".join(_i22_problems(dim_night)))


## The I22 problems, with `sky_of` (a backdrop id -> its sky colours) standing in for the art.
func _i22_problems(sky_of: Callable) -> Array[String]:
	var problems: Array[String] = []
	var night: String = (Content.chapters().back() as ChapterSpec).backdrop
	var weakest: Dictionary[String, float] = {}
	for spec in Content.birds():
		var outline: Color = _bird_colours(spec)[0]
		for backdrop in _backdrop_ids():
			var colours: Array[Color] = sky_of.call(backdrop)
			for sky in colours:
				var ratio := _contrast(outline, sky)
				weakest[backdrop] = minf(weakest.get(backdrop, INF), ratio)
				if ratio < OUTLINE_CONTRAST_MIN:
					problems.append("%s: its outline #%s on the %s sky's #%s is %.2f:1 (needs %d:1)" % [spec.id, outline.to_html(false), backdrop, sky.to_html(false), ratio, roundi(OUTLINE_CONTRAST_MIN)])
	var day := INF
	for backdrop in weakest:
		if backdrop != night:
			day = minf(day, weakest[backdrop])
	if weakest.has(night) and weakest[night] < day and weakest[night] >= OUTLINE_CONTRAST_MIN:
		problems.append("%s: its weakest outline contrast %.2f:1 is under the day backdrops' weakest %.2f:1 (the birds must read as well at night)" % [night, weakest[night], day])
	return problems


## Every backdrop a chapter or a mode shows, in chapter order then the modes' new ones.
func _backdrop_ids() -> Array[String]:
	var ids: Array[String] = []
	for chapter_spec in Content.chapters():
		if not chapter_spec.backdrop in ids:
			ids.append(chapter_spec.backdrop)
	for mode in Content.modes():
		for stage in mode.stages:
			if not stage.backdrop in ids:
				ids.append(stage.backdrop)
	return ids


## Every fill and gradient stop colour of backdrop `backdrop`'s sky layer.
func _sky_colours(backdrop: String) -> Array[Color]:
	var colours: Array[Color] = []
	var text := FileAccess.get_file_as_string(Content.backdrop_path(backdrop, "sky"))
	for found in RegEx.create_from_string("(?:fill|stop-color)=\"#([0-9a-f]{6})\"").search_all(text):
		var colour := Color.html(found.get_string(1))
		if not colour in colours:
			colours.append(colour)
	return colours


## [outline, main fill] of the bird: the stroke and fill of the first path of its fly_1 art
## (the silhouette).
func _bird_colours(spec: BirdSpec) -> Array[Color]:
	var text := FileAccess.get_file_as_string(spec.texture_path("fly_1"))
	var found := RegEx.create_from_string("<path [^>]*fill=\"#([0-9a-f]{6})\" stroke=\"#([0-9a-f]{6})\"").search(text)
	if found == null:
		return [Color.TRANSPARENT, Color.TRANSPARENT]
	return [Color.html(found.get_string(2)), Color.html(found.get_string(1))]


## The WCAG contrast ratio of two sRGB colours.
func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The I20 simulation with `plan_of` (Wave.for_mode, or a stand-in) giving each mode's
## waves: {"problems": the problems, one line per mode, wave and part (and per bird type
## for the perfect player, listing the waves), "waves": the waves covered per mode,
## "kills": the birds the perfect player killed, "margins": per mode the least time
## between a kill and its bird's deadline}.
func _i20_sim(plan_of: Callable) -> Dictionary:
	var counted: Dictionary[String, int] = {}
	var late: Dictionary[String, Array] = {}
	var waves: Dictionary[String, int] = {}
	var margins: Dictionary[String, float] = {}
	var kills := 0
	for mode in Content.modes():
		margins[mode.id] = INF
		for run_seed in SIM_SEEDS:
			var previous: Wave.Plan = null
			var start := 0.0
			var index := 1
			while (mode.is_timed() and start < mode.time_limit) or (not mode.is_timed() and index <= SIM_UNTIMED_WAVES):
				var plan: Wave.Plan = plan_of.call(mode, index, run_seed)
				waves[mode.id] = maxi(waves.get(mode.id, 0), index)
				if previous != null and plan.spawns.size() < previous.spawns.size():
					_count(counted, "%s wave %d: fewer birds than wave %d" % [mode.id, index, index - 1])
				if previous != null and plan.speed_scale < previous.speed_scale:
					_count(counted, "%s wave %d: slower than wave %d" % [mode.id, index, index - 1])
				var played := _perfect_player(mode, plan)
				kills += played["kills"]
				margins[mode.id] = minf(margins[mode.id], played["margin"])
				if played["out_of_shells"]:
					_count(counted, "%s wave %d: fewer shells than the hits its birds need (the perfect player runs out)" % [mode.id, index])
				for key: String in played["late"]:
					if not late.has(key):
						late[key] = []
					if not index in late[key]:
						late[key].append(index)
				# No player can end a wave before its last bird spawns, so a timed run
				# reaches at most the waves that start before time_limit at this pace.
				start += Play.WAVE_LEAD + (plan.spawns.back().time if not plan.spawns.is_empty() else 0.0)
				previous = plan
				index += 1
	var problems: Array[String] = []
	for key in counted:
		problems.append("%s in %d of %d seeds" % [key, counted[key], SIM_SEEDS])
	for key in late:
		var found: Array = late[key]
		found.sort()
		problems.append("%s in waves %s" % [key, _ranges(found)])
	return {"problems": problems, "waves": waves, "kills": kills, "margins": margins}


func _count(counted: Dictionary[String, int], key: String) -> void:
	counted[key] = counted.get(key, 0) + 1


## "1-10" for [1, 2, ..., 10]; "3, 5-6" for [3, 5, 6].
func _ranges(values: Array) -> String:
	var parts := PackedStringArray()
	var i := 0
	while i < values.size():
		var j := i
		while j + 1 < values.size() and int(values[j + 1]) == int(values[j]) + 1:
			j += 1
		parts.append(str(values[i]) if i == j else "%d-%d" % [values[i], values[j]])
		i = j + 1
	return ", ".join(parts)


## One wave of `mode` played by the I20 perfect player: one shot every SIM_SHOT_GAP
## seconds from an Ammo of the wave's shells, always at the bird that came into the field
## first among those still alive, the decoy never shot; a splitter's children come into the
## field where it was killed. Returns {"kills", "out_of_shells", "late": the keys of the
## birds killed at or after their deadline (the rival's cue at linger_time x 1 in a mode
## with steals, and flee_time), "margin": the least time left before a deadline}.
func _perfect_player(mode: ModeSpec, plan: Wave.Plan) -> Dictionary:
	var result := {"kills": 0, "out_of_shells": false, "late": [], "margin": INF}
	var ammo := Ammo.new(plan.shells)
	# Each target: [spec, born (s from the wave's first spawn), in the field from, hits left].
	var targets: Array[Array] = []
	for spawn in plan.spawns:
		var spec := Content.bird(spawn.bird_id)
		if spec.penalty == 0:
			var speed_scale := plan.speed_scale * Flight.speed_factor(spawn.bird_seed, plan.speed_scale)
			targets.append([spec, spawn.time, spawn.time + _field_entry_age(spec, spawn.bird_seed, speed_scale), spec.hp])
	var free := -INF
	while not targets.is_empty():
		var next := 0
		for i in targets.size():
			if targets[i][2] < targets[next][2]:
				next = i
		var target := targets[next]
		var shot := maxf(free, target[2])
		free = shot + SIM_SHOT_GAP
		if not ammo.use():
			result["out_of_shells"] = true
			return result
		target[3] -= 1
		if target[3] > 0:
			continue
		targets.remove_at(next)
		var spec: BirdSpec = target[0]
		var age: float = shot - target[1]
		result["kills"] += 1
		var cue := spec.linger_time if mode.rival_steals else INF
		result["margin"] = minf(result["margin"], minf(cue, spec.flee_time) - age)
		if age >= cue:
			result["late"].append("%s: a perfect player kills %s only after the rival's cue (at %.2f s)" % [mode.id, spec.id, cue])
		elif age >= spec.flee_time:
			result["late"].append("%s: a perfect player kills %s only after it flees (at %.2f s)" % [mode.id, spec.id, spec.flee_time])
		for i in spec.split_count:
			var child := Content.bird(spec.splits_into)
			targets.append([child, shot, shot, child.hp])
	return result


## The first age (to SIM_FRAME) at which the bird's whole hitbox is above the grass line
## (Play.GRASS_Y): a shot can hit any part of it from then on. INF if never before it flees.
func _field_entry_age(spec: BirdSpec, bird_seed: int, speed_scale: float) -> float:
	var age := 0.0
	while age <= spec.flee_time:
		if _in_field(spec, bird_seed, age, speed_scale):
			while age - SIM_FRAME >= 0.0 and _in_field(spec, bird_seed, age - SIM_FRAME, speed_scale):
				age -= SIM_FRAME
			return age
		age += SIM_COARSE_STEP
	return INF


func _in_field(spec: BirdSpec, bird_seed: int, age: float, speed_scale: float) -> bool:
	var placed := Flight.transform_at(spec, bird_seed, age, Play.FIELD, speed_scale)
	for point in spec.hitbox:
		if (placed * point).y >= Play.GRASS_Y:
			return false
	return true


func _i16_problems() -> Array[String]:
	var problems: Array[String] = []
	for level in Content.levels():
		var most := Campaign.max_score(level)
		if level.stars.size() == Content.STAR_COUNT and level.stars[2] > most:
			problems.append("%s: 3 stars at %d is above the most it can score, %d (every bird but the decoy killed, the combo rising to x%d)" % [level.id, level.stars[2], most, level.combo_cap])
	return problems


## `plan_of` (Wave.campaign, or a stand-in) gives each level's waves.
func _i17_problems(plan_of: Callable) -> Array[String]:
	var problems: Array[String] = []
	for level in Content.levels():
		for wave_index in range(1, level.waves + 1):
			var plan: Wave.Plan = plan_of.call(level, wave_index)
			var hits := 0
			for spawn in plan.spawns:
				hits += Wave.hits_needed(Content.bird(spawn.bird_id))
			if plan.shells < hits:
				problems.append("%s wave %d: %d shells for the %d hits its birds need" % [level.id, wave_index, plan.shells, hits])
	return problems


func _i18_problems() -> Array[String]:
	var problems: Array[String] = []
	for chapter_spec in Content.chapters():
		var levels := Campaign.chapter_levels(chapter_spec.id)
		if levels.is_empty():
			continue
		var last: LevelSpec = levels.back()
		var bosses := levels.filter(func(level: LevelSpec) -> bool: return level.is_boss())
		if bosses.size() != 1 or bosses[0] != last:
			problems.append("chapter %s: its boss level is %s, not its last level %s" % [chapter_spec.id, ", ".join(bosses.map(func(level: LevelSpec) -> String: return level.id)) if not bosses.is_empty() else "none", last.id])
		for boss_level: LevelSpec in bosses:
			var boss := boss_level.boss
			# Every other wave of the chapter: each level's plain waves (its own too).
			var most_birds: LevelSpec = levels.reduce(func(a: LevelSpec, b: LevelSpec) -> LevelSpec: return b if b.wave_birds > a.wave_birds else a)
			var densest: LevelSpec = levels.reduce(func(a: LevelSpec, b: LevelSpec) -> LevelSpec: return b if b.spawn_interval < a.spawn_interval else a)
			var fastest: LevelSpec = levels.reduce(func(a: LevelSpec, b: LevelSpec) -> LevelSpec: return b if b.speed_scale > a.speed_scale else a)
			if boss.birds <= most_birds.wave_birds:
				problems.append("%s: the boss flock's %d birds are not more than %s's %d per wave" % [boss_level.id, boss.birds, most_birds.id, most_birds.wave_birds])
			if boss.spawn_interval >= densest.spawn_interval:
				problems.append("%s: the boss flock's spawn interval %s s is not shorter than %s's %s s" % [boss_level.id, boss.spawn_interval, densest.id, densest.spawn_interval])
			if boss.speed_scale <= fastest.speed_scale:
				problems.append("%s: the boss flock's speed x%s is not higher than %s's x%s" % [boss_level.id, boss.speed_scale, fastest.id, fastest.speed_scale])
			var heaviest: ModeSpec.Entry = boss.mix.reduce(func(a: ModeSpec.Entry, b: ModeSpec.Entry) -> ModeSpec.Entry: return b if b.weight > a.weight else a)
			var spec := Content.bird(heaviest.bird)
			if spec.penalty > 0 or spec.id == boss_level.golden_bird or spec.chapter != chapter_spec.id:
				var what := "a decoy" if spec.penalty > 0 else ("the golden bird" if spec.id == boss_level.golden_bird else "introduced in %s" % spec.chapter)
				problems.append("%s: the boss flock is weighted toward %s (%s), not a bird %s introduces" % [boss_level.id, spec.id, what, chapter_spec.id])
	return problems


func _i19_problems() -> Array[String]:
	var problems: Array[String] = []
	var place: Dictionary[String, int] = {}
	for chapter_spec in Content.chapters():
		place[chapter_spec.id] = place.size()
	for level in Content.levels():
		var named: Array[String] = [level.golden_bird]
		for owner in _mixes():
			if owner[0] == level.id:
				for entry: ModeSpec.Entry in owner[2]:
					if not entry.bird in named:
						named.append(entry.bird)
		for id: String in named.duplicate():
			var spec := Content.bird(id)
			if spec.split_count > 0 and not spec.splits_into in named:
				named.append(spec.splits_into)
		for id in named:
			var spec := Content.bird(id)
			if place[spec.chapter] > place[level.chapter]:
				problems.append("%s uses %s (introduced in %s, after %s)" % [level.id, id, spec.chapter, level.chapter])
	for chapter_spec in Content.chapters():
		var spawned: Dictionary[String, bool] = {}
		var golden := false
		for level in Campaign.chapter_levels(chapter_spec.id):
			for wave_index in range(1, level.waves + 1):
				for spawn in Wave.campaign(level, wave_index).spawns:
					spawned[spawn.bird_id] = true
					golden = golden or spawn.bird_id == level.golden_bird
					var spec := Content.bird(spawn.bird_id)
					if spec.split_count > 0:
						spawned[spec.splits_into] = true
		for spec in Content.birds():
			if spec.chapter == chapter_spec.id and not spawned.has(spec.id):
				problems.append("chapter %s introduces %s, but none of its levels spawns it" % [chapter_spec.id, spec.id])
		if not golden:
			problems.append("chapter %s: none of its levels spawns a golden bird" % chapter_spec.id)
	return problems


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


func _i21_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		for frame in spec.frames():
			if frame == "hit":
				continue
			var texture := load(spec.texture_path(frame)) as Texture2D
			var image := texture.get_image() if texture != null else null
			if image == null:
				problems.append("%s %s: %s cannot be loaded as a texture" % [spec.id, frame, spec.texture_path(frame)])
				continue
			if image.is_compressed():
				image.decompress()
			var scale := Vector2(image.get_size()) / spec.size
			var opaque := 0
			var covered := 0
			for y in image.get_height():
				for x in image.get_width():
					if image.get_pixel(x, y).a < OPAQUE_ALPHA:
						continue
					opaque += 1
					if Geometry2D.is_point_in_polygon((Vector2(x, y) + Vector2(0.5, 0.5)) / scale - spec.size / 2.0, spec.hitbox):
						covered += 1
			# Opaque pixels in base units squared, against the hitbox polygon's area.
			var body_area := opaque / (scale.x * scale.y)
			var cover := float(covered) / opaque if opaque > 0 else 0.0
			var area := _polygon_area(spec.hitbox) / body_area if body_area > 0.0 else INF
			if cover < HITBOX_BODY_COVER_MIN:
				problems.append("%s %s: the hitbox covers %.1f%% of the imported texture's opaque body (needs %d%%)" % [spec.id, frame, cover * 100.0, roundi(HITBOX_BODY_COVER_MIN * 100.0)])
			if area > HITBOX_BODY_AREA_MAX:
				problems.append("%s %s: the hitbox's area is %.1f%% of the imported texture's opaque body (at most %d%%)" % [spec.id, frame, area * 100.0, roundi(HITBOX_BODY_AREA_MAX * 100.0)])
	return problems


## The area of a simple polygon (the shoelace formula).
func _polygon_area(polygon: PackedVector2Array) -> float:
	var twice := 0.0
	for i in polygon.size():
		twice += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return absf(twice) / 2.0


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
		for owner in _mixes():
			if owner[1] == child.id or (owner[2] as Array).any(func(e: ModeSpec.Entry) -> bool: return e.bird == child.id):
				problems.append("%s: a split child never spawns from waves (%s)" % [child.id, owner[0]])
	return problems


func _i8_problems() -> Array[String]:
	var problems: Array[String] = []
	for owner in _mixes():
		var golden := Content.bird(owner[1])
		if golden.hp != 1 or golden.split_count > 0 or golden.penalty > 0:
			problems.append("%s: golden bird %s must have hp 1, no split and no penalty" % [owner[0], golden.id])
		var seen: Dictionary[String, bool] = {}
		for entry: ModeSpec.Entry in owner[2]:
			var spec := Content.bird(entry.bird)
			if seen.has(spec.id):
				continue
			seen[spec.id] = true
			if spec == golden:
				problems.append("%s: golden bird %s is also in the mix" % [owner[0], golden.id])
				continue
			if golden.speed <= spec.speed:
				problems.append("%s: golden bird %s (speed %s) is not faster than %s (speed %s)" % [owner[0], golden.id, golden.speed, spec.id, spec.speed])
			if golden.points <= spec.points:
				problems.append("%s: golden bird %s (%d points) is not worth more than %s (%d points)" % [owner[0], golden.id, golden.points, spec.id, spec.points])
	return problems


## Every wave mix with its golden bird: [owner id, golden_bird, the mix entries] for each
## mode and each level (a level's mix and its boss flock's mix together).
func _mixes() -> Array[Array]:
	var found: Array[Array] = []
	for mode in Content.modes():
		found.append([mode.id, mode.golden_bird, mode.birds])
	for level in Content.levels():
		var entries: Array[ModeSpec.Entry] = level.mix.duplicate()
		if level.is_boss():
			entries.append_array(level.boss.mix)
		found.append([level.id, level.golden_bird, entries])
	return found


func _i9_problems() -> Array[String]:
	var problems: Array[String] = []
	var order := Campaign.levels()
	if not order.is_empty():
		var first := order[0]
		var odd := PackedStringArray()
		for spawn in Wave.campaign(first, 1).spawns:
			if spawn.bird_id == first.golden_bird or not _is_plain(Content.bird(spawn.bird_id)):
				odd.append(spawn.bird_id)
		if not odd.is_empty():
			problems.append("%s: wave 1 spawns %s, not plain birds only (the campaign's first wave is plain)" % [first.id, ", ".join(odd)])
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
	var golden_ids := _mixes().map(func(owner: Array) -> String: return owner[1])
	var appears: Dictionary[String, bool] = {}
	for owner in _mixes():
		appears[owner[1]] = true
		for entry: ModeSpec.Entry in owner[2]:
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
	for chapter_spec in Content.chapters():
		if not birds.any(func(spec: BirdSpec) -> bool: return spec.chapter == chapter_spec.id and appears.has(spec.id)):
			problems.append("chapter %s introduces no bird" % chapter_spec.id)
	for spec in birds:
		if not appears.has(spec.id):
			problems.append("%s never appears (not in a mix, not a golden bird, not a split child)" % spec.id)
	return problems


func _i11_problems() -> Array[String]:
	var problems: Array[String] = []
	for spec in Content.birds():
		if spec.size.x >= Play.FIELD.size.x or spec.size.y >= Play.FIELD.size.y:
			problems.append("%s: size %s does not fit the field %s" % [spec.id, spec.size, Play.FIELD.size])
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
## "<owner>: <problem>" for each of `owners`, in order.
func _per_owner(owners: Array, problem: String) -> Array[String]:
	var lines: Array[String] = []
	for owner: String in owners:
		lines.append("%s: %s" % [owner, problem])
	return lines


func _mutated(file: String, mutate: Callable) -> Array[String]:
	return _mutated_files({file: mutate})


## _mutated for several files at once: file -> its Callable.
func _mutated_files(mutations: Dictionary) -> Array[String]:
	var texts := _real_texts()
	for file: String in mutations:
		var data: Variant = JSON.parse_string(texts[file])
		(mutations[file] as Callable).call(data)
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


## I24: Flight.SPEED_SPREAD_TOP_SCALE is the highest speed scale in the content (every
## level's and boss flock's speed_scale, every mode's speed_cap); a mutated night boss at
## x1.8 makes it wrong.
func _test_i24_speed_spread_top_scale() -> void:
	_check(_i24_problems().is_empty(), "I24 the speed spread tops out at the content's highest speed scale", str(_i24_problems()))
	var night_6 := Content.level("night_6")
	var was := night_6.boss.speed_scale
	night_6.boss.speed_scale = 1.8
	_check(_i24_problems() == ["Flight.SPEED_SPREAD_TOP_SCALE 1.60 is not the highest speed scale in the content, 1.80"], "I24 a faster boss flock fails", str(_i24_problems()))
	night_6.boss.speed_scale = was


func _i24_problems() -> Array[String]:
	var top := 0.0
	for level in Content.levels():
		top = maxf(top, level.speed_scale)
		if level.is_boss():
			top = maxf(top, level.boss.speed_scale)
	for mode in Content.modes():
		top = maxf(top, mode.speed_cap)
	if is_equal_approx(top, Flight.SPEED_SPREAD_TOP_SCALE):
		return []
	return ["Flight.SPEED_SPREAD_TOP_SCALE %.2f is not the highest speed scale in the content, %.2f" % [Flight.SPEED_SPREAD_TOP_SCALE, top]]
