extends SceneTree
## Headless gameplay tests. Run with --fixed-fps 60 so one frame = one physics tick:
##   "$GODOT" --headless --path huntfrenzy --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd"
## Prints "test_gameplay: OK" when every test passes; exits 1 otherwise.
## To add a test: write a `_test_*` func (it may await) that reports through _check(),
## and append it to the list in _tests(). Tests run in that order on one SceneTree, so
## each one restores whatever it changes (window size, Game.scene_paths, quiet_errors,
## Content, pause, Engine.time_scale, the tool save).

const TITLE_PATH := "res://scenes/title.tscn"
const PLAY_PATH := "res://scenes/play.tscn"
const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
## Every synthetic touch uses this index: a web build's index is the browser's
## Touch.identifier, which iOS Safari makes large and never 0.
const TOUCH_INDEX := 7
const BASE_WINDOW := Vector2i(960, 540)
## Window sizes in pixels for the screens the game must fit: 16:9, 19.5:9 and 4:3
## landscape, and a 19.5:9 phone held upright.
const LANDSCAPE_16_9 := Vector2i(1920, 1080)
const LANDSCAPE_19_5_9 := Vector2i(2340, 1080)
const LANDSCAPE_4_3 := Vector2i(1440, 1080)
const PORTRAIT_9_19_5 := Vector2i(1080, 2340)
const LANDSCAPE_WINDOWS: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_19_5_9, LANDSCAPE_4_3]
const MIN_TARGET := 44.0
## The CSS html/head_include must set so the browser never pulls to refresh, zooms on a
## double tap, selects text or opens a long-press menu.
const TOUCH_CSS: Array[String] = ["touch-action: none", "overscroll-behavior: none", "user-select: none", "-webkit-user-select: none", "-webkit-touch-callout: none"]
## The GDScript warnings project.godot raises to errors (level 2): with them, any warning
## fails the strict compile in check_project.gd.
const STRICT_WARNINGS: Array[String] = [
	"unassigned_variable", "unassigned_variable_op_assign", "unused_variable", "unused_local_constant",
	"unused_private_class_variable", "unused_parameter", "unused_signal", "shadowed_variable",
	"shadowed_variable_base_class", "shadowed_global_identifier", "unreachable_code", "unreachable_pattern",
	"standalone_expression", "standalone_ternary", "incompatible_ternary", "untyped_declaration",
	"unsafe_void_return", "static_called_on_instance", "missing_tool", "redundant_static_unload",
	"redundant_await", "assert_always_true", "assert_always_false", "integer_division", "narrowing_conversion",
	"int_as_enum_without_cast", "int_as_enum_without_match", "enum_variable_without_default", "empty_file",
	"deprecated_keyword", "confusable_identifier", "confusable_local_declaration", "confusable_local_usage",
	"confusable_capture_reassignment", "confusable_temporary_modification", "property_used_as_function",
	"constant_used_as_function", "function_used_as_property",
]
## A 2340x1080 phone at 2x (visible 1170x540) with a 66-unit notch on the left, in base units.
const NOTCHED_SAFE_RECT := Rect2(66, 0, 1104, 540)
## Real-time limit for the whole run; a test stuck on an await fails instead of hanging.
const WATCHDOG_MSEC := 120000
## A goose's hitbox (data/birds.json) holds LOCAL_INSIDE (1 unit inside its bottom edge)
## and not LOCAL_JUST_OUTSIDE (1 unit outside it) nor LOCAL_BOX_CORNER (inside the 96x72
## sprite's bounding box, outside the polygon).
const LOCAL_INSIDE := Vector2(0, 20)
const LOCAL_JUST_OUTSIDE := Vector2(0, 22)
const LOCAL_BOX_CORNER := Vector2(-40, -28)
## The goose's body centre, deep inside its hitbox.
const LOCAL_BODY := Vector2(0, 5)
## Points in empty sky (World coordinates) while no bird is above the grass yet.
const SKY_POINTS: Array[Vector2] = [Vector2(120, 120), Vector2(840, 120), Vector2(480, 100)]
## How much faster game time runs while the escape test waits for 10 escapes.
const FAST_TIME_SCALE := 8.0

var _failures: Array[String] = []
var _passed := 0
var _deadline_msec := 0
## The "Game" autoload; this script compiles before autoloads exist, so it is fetched at start.
var _game: GameState


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	_game = root.get_node_or_null("Game") as GameState
	if _game == null:
		printerr("test_gameplay: FAILED: Game autoload not found")
		quit(1)
		return
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_msec:
		printerr("test_gameplay: FAILED watchdog: tests did not finish within %d ms" % WATCHDOG_MSEC)
		quit(1)
	return false


func _tests() -> Array[Callable]:
	return [
		_test_project_display_and_input,
		_test_project_strict_warnings,
		_test_web_export_preset,
		_test_goto_logs_transition,
		_test_goto_missing_scene_shows_error,
		_test_goto_ignored_during_transition,
		_test_screen_fit_landscape,
		_test_safe_area_notch,
		_test_fit_window_rect,
		_test_title_button_layout,
		_test_title_follows_notched_safe_area,
		_test_title_button_tap_and_enter,
		_test_rotate_overlay_shows_and_pauses,
		_test_rotate_overlay_blocks_input,
		_test_rotate_overlay_keeps_existing_pause,
		_test_content_real_data,
		_test_content_malformed_data,
		_test_title_content_error_banner,
		_test_flight_determinism,
		_test_flight_stays_in_field_and_turns,
		_test_flight_escapes_after_flee_time,
		_test_flight_hitbox,
		_test_wave_schedule,
		_test_ammo_pool,
		_test_scoring_combo,
		_test_save_and_reload,
		_test_save_corrupt_and_unknown_version,
		_test_play_hud_layout,
		_test_play_touch_hits_goose,
		_test_play_touch_outside_polygon_misses,
		_test_play_overlapping_hit_counts_once,
		_test_play_two_fingers_two_shots,
		_test_play_empty_pool_refuses,
		_test_pause_causes_and_resume,
		_test_pause_menu_keyboard,
		_test_pause_touches_are_not_shots,
		_test_pause_after_rotating,
		_test_pause_restart_and_quit,
		_test_run_ends_on_results,
	]


func _run() -> void:
	root.size = BASE_WINDOW
	_clear_tool_save()
	await process_frame
	for test in _tests():
		await test.call()
	_clear_tool_save()
	for failure in _failures:
		printerr("test_gameplay: FAIL " + failure)
	if _failures.is_empty():
		print("test_gameplay: OK (%d checks)" % _passed)
		quit(0)
	else:
		printerr("test_gameplay: FAILED %d of %d checks" % [_failures.size(), _failures.size() + _passed])
		quit(1)


## project.godot: landscape 960x540 base, canvas_items + expand, linear filtering, the
## Compatibility renderer, the mouse arriving as touch, the title as the main scene.
func _test_project_display_and_input() -> void:
	var settings := {
		"display/window/size/viewport_width": 960,
		"display/window/size/viewport_height": 540,
		"display/window/stretch/mode": "canvas_items",
		"display/window/stretch/aspect": "expand",
		"display/window/handheld/orientation": DisplayServer.SCREEN_SENSOR_LANDSCAPE,
		"rendering/textures/canvas_textures/default_texture_filter": 1,
		"rendering/renderer/rendering_method": "gl_compatibility",
		"rendering/renderer/rendering_method.mobile": "gl_compatibility",
		"input_devices/pointing/emulate_touch_from_mouse": true,
		"input_devices/pointing/emulate_mouse_from_touch": false,
		"application/run/main_scene": TITLE_PATH,
	}
	for key: String in settings:
		var value: Variant = ProjectSettings.get_setting(key)
		_check(value == settings[key], "project setting " + key, "%s, expected %s" % [value, settings[key]])


## project.godot keeps GDScript warnings on and raises every STRICT_WARNINGS entry to an error.
func _test_project_strict_warnings() -> void:
	var enabled: Variant = ProjectSettings.get_setting("debug/gdscript/warnings/enable")
	_check(enabled == true, "GDScript warnings are enabled", str(enabled))
	for warning in STRICT_WARNINGS:
		var level: Variant = ProjectSettings.get_setting("debug/gdscript/warnings/" + warning)
		_check(level == 2, "warning %s is an error" % warning, "level %s, expected 2" % level)


## The web preset exports single-threaded and its head_include carries the touch CSS.
func _test_web_export_preset() -> void:
	var presets := ConfigFile.new()
	var error := presets.load(EXPORT_PRESETS_PATH)
	_check(error == OK, "export presets load", error_string(error))
	if error != OK:
		return
	_check(presets.get_value("preset.0", "platform", "") == "Web", "preset 0 is the web export", str(presets.get_value("preset.0", "platform", "")))
	_check(presets.get_value("preset.0.options", "variant/thread_support", true) == false, "web export is single-threaded", str(presets.get_value("preset.0.options", "variant/thread_support", true)))
	var head: String = presets.get_value("preset.0.options", "html/head_include", "")
	for css in TOUCH_CSS:
		_check(css in head, "head_include sets " + css, head)


func _test_goto_logs_transition() -> void:
	var logged := _game.transition_log.size()
	_game.goto(GameState.Flow.TITLE, {"from": "test"})
	await process_frame
	var cover := _game.get_node("Fade/Cover") as ColorRect
	_check(_game.is_transitioning() and cover.visible and cover.mouse_filter == Control.MOUSE_FILTER_STOP, "goto's cover blocks touches during the transition", "visible %s, filter %d" % [cover.visible, cover.mouse_filter])
	await _game.transition_finished
	_check(_game.transition_log.size() == logged + 1, "goto logs transition", "log grew by %d" % (_game.transition_log.size() - logged))
	_check(_game.transition_log.back().begins_with("TITLE -> TITLE (%s)" % TITLE_PATH), "goto log entry", str(_game.transition_log.back()))
	_check(current_scene != null and current_scene.scene_file_path == TITLE_PATH, "goto swaps scene", str(current_scene))
	_check(_game.state == GameState.Flow.TITLE and _game.flow_args.get("from") == "test", "goto sets state and args", "%s %s" % [_game.state, _game.flow_args])
	_check(is_zero_approx(_game.cover_progress()) and not cover.visible and cover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "goto's cover clears and lets touches through", "progress %.2f, visible %s" % [_game.cover_progress(), cover.visible])
	_check(not _game.is_transitioning(), "goto finished", "still transitioning")


func _test_goto_missing_scene_shows_error() -> void:
	var real_path: String = _game.scene_paths[GameState.Flow.TITLE]
	_game.scene_paths[GameState.Flow.TITLE] = "res://scenes/does_not_exist.tscn"
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var logged := _game.transition_log.size()
	var scene_before := current_scene
	_game.goto(GameState.Flow.TITLE)
	await process_frame
	_game.quiet_errors = false
	_game.scene_paths[GameState.Flow.TITLE] = real_path
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	_check(_game.reported_errors.size() == errors + 1, "missing scene reports error", "%d new errors" % (_game.reported_errors.size() - errors))
	_check(error_label.visible and "does_not_exist" in error_label.text, "missing scene shows error label", error_label.text)
	_check(current_scene == scene_before, "missing scene keeps current scene", str(current_scene))
	_check(_game.transition_log.size() == logged and not _game.is_transitioning(), "missing scene is not a transition", "log %d" % (_game.transition_log.size() - logged))
	error_label.hide()


func _test_goto_ignored_during_transition() -> void:
	var logged := _game.transition_log.size()
	_game.goto(GameState.Flow.TITLE)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_check(_game.transition_log.size() == logged + 1, "goto during transition is ignored", "log grew by %d" % (_game.transition_log.size() - logged))


## On 16:9, 19.5:9 and 4:3 the visible rect holds the whole 960x540 base (never cropped),
## the safe rect is the visible rect (headless reports no safe area), no rotate overlay.
func _test_screen_fit_landscape() -> void:
	var expected: Dictionary[Vector2i, Vector2] = {
		LANDSCAPE_16_9: Vector2(960, 540), LANDSCAPE_19_5_9: Vector2(1170, 540), LANDSCAPE_4_3: Vector2(960, 720),
	}
	for window: Vector2i in expected:
		root.size = window
		await process_frame
		var label := "%dx%d" % [window.x, window.y]
		var visible := _game.visible_rect()
		_check(visible.size.is_equal_approx(expected[window]), label + " visible size", str(visible))
		_check(visible.encloses(Rect2(Vector2.ZERO, GameState.BASE_SIZE)), label + " base playfield is never cropped", str(visible))
		_check(_game.safe_rect() == visible, label + " safe rect is the visible rect", str(_game.safe_rect()))
		_check(not _game.is_rotate_overlay_shown() and not paused, label + " no rotate overlay, not paused", "overlay %s, paused %s" % [_game.is_rotate_overlay_shown(), paused])
	root.size = BASE_WINDOW
	await process_frame


func _test_safe_area_notch() -> void:
	# A 2340x1080 phone at 2x (visible 1170x540) with a 132 px notch on the left.
	var visible := Rect2(0, 0, 1170, 540)
	var safe := GameState.safe_rect_in(visible, Rect2i(132, 0, 2208, 1080), Vector2i.ZERO, Transform2D.IDENTITY.scaled(Vector2(2, 2)))
	_check(safe.is_equal_approx(NOTCHED_SAFE_RECT), "safe area converts to base units", str(safe))
	var empty := GameState.safe_rect_in(visible, Rect2i(), Vector2i.ZERO, Transform2D.IDENTITY)
	_check(empty == visible, "empty safe area means the visible rect", str(empty))
	var outside := GameState.safe_rect_in(visible, Rect2i(5000, 5000, 10, 10), Vector2i.ZERO, Transform2D.IDENTITY)
	_check(outside == visible, "a safe area outside the window means the visible rect", str(outside))


## The 960x540 desktop window is in screen points: scaled by the screen density,
## shrunk to fit the usable screen with its frame, centred.
func _test_fit_window_rect() -> void:
	var base := Vector2i(960, 540)
	# 2x Retina with room to spare (macOS: 64 px title bar, menu bar above y 78).
	var roomy := GameState.fit_window_rect(base, 2.0, Rect2i(0, 78, 3600, 2070), Vector2i(0, 64), Vector2i(0, 64))
	# 2x 1440x900-point laptop: 2880x1800 pixels, too small for 1920x1080 plus frame.
	var small_usable := Rect2i(0, 78, 2880, 1722)
	var small := GameState.fit_window_rect(base, 2.0, small_usable, Vector2i(0, 64), Vector2i(0, 64))
	var small_framed := Rect2i(small.position - Vector2i(0, 64), small.size + Vector2i(0, 64))
	# 1x full-HD screen: unchanged.
	var full_hd := GameState.fit_window_rect(base, 1.0, Rect2i(0, 0, 1920, 1040), Vector2i(16, 39), Vector2i(8, 31))
	_check(roomy == Rect2i(840, 605, 1920, 1080), "fit_window_rect doubles on a roomy 2x screen", str(roomy))
	_check(small_usable.encloses(small_framed) and absf(float(small.size.x) / small.size.y - 16.0 / 9.0) < 0.01,
		"fit_window_rect shrinks to a small 2x screen keeping 16:9", "%s (framed %s)" % [small, small_framed])
	_check(full_hd.size == base, "fit_window_rect leaves a roomy 1x screen unchanged", str(full_hd))


## The title's Play button: at least 44x44, inside the safe area, focused on arrival with
## a visible focus style, at 16:9, 19.5:9 and 4:3.
func _test_title_button_layout() -> void:
	await _open_title()
	var title := current_scene as Title
	var button := title.get_node("Safe/PlayButton") as Button
	_check(button.has_focus(), "title focuses Play on arrival", str(root.gui_get_focus_owner()))
	var focus_style := button.get_theme_stylebox(&"focus")
	_check(focus_style != null and not (focus_style is StyleBoxEmpty), "Play has a visible focus style", str(focus_style))
	_check(button.focus_mode == Control.FOCUS_ALL, "Play takes keyboard focus", str(button.focus_mode))
	_check(not button.has_focus(true), "the focus ring is hidden on arrival (no stray ring on phones)", "focus visible")
	await _key(KEY_TAB)
	_check(button.has_focus(true), "keyboard navigation shows Play's focus ring", "focus still hidden")
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		var label := "%dx%d Play" % [window.x, window.y]
		var rect := button.get_global_rect()
		_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET, label + " size", str(rect.size))
		_check(_game.safe_rect().encloses(rect), label + " inside safe area", "%s not in %s" % [rect, _game.safe_rect()])
	root.size = BASE_WINDOW
	await process_frame


## With a notch narrowing the safe area, the title lays out in the safe rect, not the
## visible rect, and Play stays clear of the notch.
func _test_title_follows_notched_safe_area() -> void:
	await _open_title()
	var title := current_scene as Title
	var safe := title.get_node("Safe") as Control
	var button := title.get_node("Safe/PlayButton") as Button
	_game.safe_area_override = NOTCHED_SAFE_RECT
	root.size = LANDSCAPE_19_5_9
	await process_frame
	await process_frame
	_check(_game.safe_rect() == NOTCHED_SAFE_RECT and _game.safe_rect() != _game.visible_rect(), "the notch narrows the safe rect", "safe %s, visible %s" % [_game.safe_rect(), _game.visible_rect()])
	_check(safe.get_global_rect().is_equal_approx(NOTCHED_SAFE_RECT), "the title lays out in the safe rect", str(safe.get_global_rect()))
	_check(NOTCHED_SAFE_RECT.encloses(button.get_global_rect()), "Play is clear of the notch", str(button.get_global_rect()))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## A real touch on Play starts an Endless run (through goto, with a seed), and so does
## Enter on the focused button.
func _test_title_button_tap_and_enter() -> void:
	await _open_title()
	var title := current_scene as Title
	var button := title.get_node("Safe/PlayButton") as Button
	await _tap(button)
	_check(title.play_presses == 1, "a tap presses Play", "%d presses" % title.play_presses)
	_check(_game.is_transitioning() and _game.transition_log.back().begins_with("TITLE -> PLAY (%s)" % PLAY_PATH), "Play goes to the play scene through goto", str(_game.transition_log.back()))
	await _game.transition_finished
	_check(_game.state == GameState.Flow.PLAY and current_scene is Play, "Play starts a run", "%s %s" % [_game.state, current_scene])
	_check(_game.flow_args.get("mode") == GameState.ENDLESS_MODE and _game.flow_args.get("seed") is int, "the run is Endless with a seed", str(_game.flow_args))
	var first_seed: int = _game.flow_args["seed"]
	await _open_title()
	title = current_scene as Title
	await _key(KEY_ENTER)
	_check(title.play_presses == 1, "Enter presses the focused Play", "%d presses" % title.play_presses)
	await _game.transition_finished
	_check(current_scene is Play and _game.flow_args.get("seed") != first_seed, "each run gets a fresh seed", "seeds %d and %s" % [first_seed, _game.flow_args.get("seed")])


## A portrait window shows the rotate overlay over the whole screen and pauses the tree;
## back to landscape it hides and the tree runs again.
func _test_rotate_overlay_shows_and_pauses() -> void:
	await _open_title()
	var shown: Array[bool] = []
	var record := func(value: bool) -> void: shown.append(value)
	_game.rotate_overlay_changed.connect(record)
	root.size = PORTRAIT_9_19_5
	await process_frame
	var overlay := _game.get_node("RotateLayer/RotateOverlay") as Control
	var message := _game.get_node("RotateLayer/RotateOverlay/Message") as Label
	_check(_game.is_rotate_overlay_shown() and overlay.visible, "portrait shows the rotate overlay", "shown %s" % _game.is_rotate_overlay_shown())
	_check(paused, "portrait pauses the tree", "paused %s" % paused)
	_check(message.text == "Rotate your phone" and message.is_visible_in_tree(), "the overlay says to rotate", message.text)
	_check(overlay.get_global_rect().encloses(_game.visible_rect()), "the overlay covers the visible area", "%s vs %s" % [overlay.get_global_rect(), _game.visible_rect()])
	_check(overlay.mouse_filter == Control.MOUSE_FILTER_STOP, "the overlay stops touches", str(overlay.mouse_filter))
	root.size = LANDSCAPE_16_9
	await process_frame
	_check(not _game.is_rotate_overlay_shown() and not overlay.visible, "landscape hides the rotate overlay", "shown %s" % _game.is_rotate_overlay_shown())
	_check(not paused, "landscape unpauses the tree", "paused %s" % paused)
	_check(shown == [true, false], "rotate_overlay_changed fires on show and hide", str(shown))
	_game.rotate_overlay_changed.disconnect(record)
	root.size = BASE_WINDOW
	await process_frame


## Under the rotate overlay neither a tap where Play is nor Enter presses Play.
func _test_rotate_overlay_blocks_input() -> void:
	await _open_title()
	var title := current_scene as Title
	var button := title.get_node("Safe/PlayButton") as Button
	button.grab_focus()
	root.size = PORTRAIT_9_19_5
	await process_frame
	await process_frame
	await _tap(button)
	await _key(KEY_ENTER)
	_check(title.play_presses == 0, "the rotate overlay blocks taps and keys", "%d presses" % title.play_presses)
	root.size = BASE_WINDOW
	await process_frame
	await _key(KEY_ENTER)
	_check(title.play_presses == 1, "Play works again after rotating back", "%d presses" % title.play_presses)
	await _game.transition_finished


## A tree already paused before the overlay showed stays paused after it hides.
func _test_rotate_overlay_keeps_existing_pause() -> void:
	paused = true
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown() and paused, "overlay over an already paused tree", "shown %s, paused %s" % [_game.is_rotate_overlay_shown(), paused])
	root.size = BASE_WINDOW
	await process_frame
	_check(not _game.is_rotate_overlay_shown() and paused, "rotating back keeps the earlier pause", "shown %s, paused %s" % [_game.is_rotate_overlay_shown(), paused])
	paused = false


## The shipped data loads with no problems and holds the goose and the Endless mode.
func _test_content_real_data() -> void:
	Content.reload()
	_check(Content.errors().is_empty(), "data/*.json loads with no problems", str(Content.errors()))
	var goose := Content.bird("goose")
	_check(goose != null and goose.points == 100 and goose.size == Vector2(96, 72) and goose.hitbox.size() >= 3, "the goose loads", str(goose))
	var endless := Content.mode(GameState.ENDLESS_MODE)
	_check(endless != null and endless.escape_limit == 10 and endless.birds == PackedStringArray(["goose"]), "the Endless mode loads", str(endless))
	var half := goose.size / 2.0
	_check(Array(goose.hitbox).all(func(p: Vector2) -> bool: return absf(p.x) <= half.x and absf(p.y) <= half.y), "the goose hitbox lies inside its sprite", str(goose.hitbox))


## Malformed data: every missing key, wrong type, out-of-range value, unknown key and
## reference, duplicate id and file problem is collected as data/<file> [<id>] <field>: <problem>.
func _test_content_malformed_data() -> void:
	Content.quiet_errors = true
	var birds := JSON.stringify([
		{"id": "goose", "name": "Goose", "speed": "fast", "wobble": -5, "wobble_hz": 0.8, "flee_time": 6, "sprite": "nope",
			"size": [96], "hitbox": [[0, 0], [0, 0]], "colour": "grey"},
		{"id": "heron", "name": "Heron", "speed": 100, "wobble": 0, "wobble_hz": 0, "flee_time": 6, "points": 2.5, "sprite": "goose",
			"size": [96, 72], "hitbox": [[0, 0], [200, 0], [0, 10]]},
		{"id": "goose", "name": "Copy", "speed": 100, "wobble": 0, "wobble_hz": 0, "flee_time": 6, "points": 1, "sprite": "goose",
			"size": [96, 72], "hitbox": [[0, 0], [10, 0], [0, 10]]},
	])
	var modes := JSON.stringify([
		{"id": "endless", "name": "Endless", "birds": ["swan"], "start_birds": 0, "bird_growth": 1, "max_birds": 6, "speed_growth": 0.1,
			"speed_cap": 9, "spawn_interval": 1, "shells_per_bird": 3, "escape_limit": "ten", "speed": 1},
	])
	Content.load_texts({"birds.json": birds, "modes.json": modes})
	var expected: Array[String] = [
		"data/birds.json [goose] points: missing key",
		"data/birds.json [goose] colour: unknown key",
		"data/birds.json [goose] speed: expected float, got String",
		"data/birds.json [goose] wobble: -5",
		"data/birds.json [goose] sprite: unknown sprite 'nope'",
		"data/birds.json [goose] size: expected an array of 2 numbers",
		"data/birds.json [goose] hitbox: has 2 points, needs at least 3",
		"data/birds.json [heron] points: expected int, got 2.5",
		"data/birds.json [heron] hitbox[1]: (200.0, 0.0) is outside the sprite",
		"data/birds.json [goose] id: duplicate id 'goose'",
		"data/modes.json [endless] birds[0]: unknown bird id 'swan'",
		"data/modes.json [endless] start_birds: 0 is outside 1..30",
		"data/modes.json [endless] speed_cap: 9",
		"data/modes.json [endless] escape_limit: expected int, got String",
		"data/modes.json [endless] combo_cap: missing key",
		"data/modes.json [endless] speed: unknown key",
	]
	_check_errors(Content.errors(), expected, "malformed entries")
	Content.load_texts({"birds.json": "[{\"id\": "})
	_check_errors(Content.errors(), ["data/birds.json [-] (file): JSON parse error", "data/modes.json [-] (file): missing"], "malformed files")
	Content.load_texts({"birds.json": "[]", "modes.json": "{}"})
	_check_errors(Content.errors(), ["data/birds.json [-] (file): has no entries", "data/modes.json [-] (file): top level must be an array"], "empty and non-array files")
	Content.quiet_errors = false
	Content.reload()
	_check(Content.errors().is_empty(), "the real data reloads clean", str(Content.errors()))


## With content errors the title shows the banner and Play is disabled; with clean data
## the banner is hidden and Play works.
func _test_title_content_error_banner() -> void:
	Content.quiet_errors = true
	Content.load_texts({"birds.json": "[]"})
	var problems := Content.errors().size()
	await _open_title()
	var title := current_scene as Title
	var banner := title.get_node("Safe/ContentErrorBanner") as Label
	var button := title.get_node("Safe/PlayButton") as Button
	_check(banner.visible and banner.text == Title.CONTENT_ERROR_MESSAGE % problems, "content errors show the banner", "%s '%s'" % [banner.visible, banner.text])
	_check(button.disabled, "content errors disable Play", "enabled")
	await _tap(button)
	_check(title.play_presses == 0 and not _game.is_transitioning(), "a disabled Play starts nothing", "%d presses" % title.play_presses)
	Content.quiet_errors = false
	Content.reload()
	await _open_title()
	title = current_scene as Title
	_check(not (title.get_node("Safe/ContentErrorBanner") as Label).visible and not (title.get_node("Safe/PlayButton") as Button).disabled, "clean content: no banner, Play enabled", "banner or disabled")


func _test_flight_determinism() -> void:
	var goose := Content.bird("goose")
	var same := true
	for age: float in [0.0, 0.7, 2.5, 5.9, 7.3]:
		same = same and Flight.position(goose, 1234, age, Play.FIELD, 1.2) == Flight.position(goose, 1234, age, Play.FIELD, 1.2)
	_check(same, "same spec, seed and age give the same position", "differs")
	var a := Flight.position(goose, 1, 2.0, Play.FIELD)
	var b := Flight.position(goose, 2, 2.0, Play.FIELD)
	_check(a.distance_to(b) > 1.0, "different seeds give different paths", "%s vs %s" % [a, b])
	var start := Flight.position(goose, 1, 0.0, Play.FIELD)
	_check(start.y - goose.size.y / 2.0 >= Play.FIELD.end.y and start.y - goose.size.y / 2.0 >= Play.GRASS_Y, "the goose starts below the grass line", str(start))


## Once a goose is inside the field it stays inside until it flees (20 seeds, every frame),
## it enters well before fleeing, and it turns back at the side edges.
func _test_flight_stays_in_field_and_turns() -> void:
	var goose := Content.bird("goose")
	var half := goose.size / 2.0
	var problems: Array[String] = []
	for bird_seed in 20:
		var entered := -1.0
		var age := 0.0
		while age <= goose.flee_time:
			var at := Flight.position(goose, bird_seed, age, Play.FIELD, 1.4)
			var bounds := Rect2(at - half, goose.size)
			if entered < 0.0 and Play.FIELD.grow(0.01).encloses(bounds):
				entered = age
			elif entered >= 0.0 and not Play.FIELD.grow(0.01).encloses(bounds):
				problems.append("seed %d leaves the field at age %.2f: %s" % [bird_seed, age, bounds])
				break
			age += 1.0 / 60.0
		if entered < 0.0 or entered > goose.flee_time / 2.0:
			problems.append("seed %d enters the field at %.2f" % [bird_seed, entered])
	_check(problems.is_empty(), "the goose stays inside the field until it flees", str(problems))
	# At 3x speed a goose crosses the 960-wide field more than once before fleeing.
	var turns := 0
	var last_x := 0.0
	for step in roundi(goose.flee_time * 60.0):
		var moving := Flight.velocity(goose, 5, step / 60.0, Play.FIELD, 3.0)
		if step > 0 and signf(moving.x) != signf(last_x):
			turns += 1
		last_x = moving.x
	_check(turns >= 1, "the goose turns back at the side edges", "%d turns" % turns)
	var placed := Flight.transform_at(goose, 5, 1.0, Play.FIELD, 3.0)
	var moving_x := Flight.velocity(goose, 5, 1.0, Play.FIELD, 3.0).x
	_check(signf(placed.x.x) == signf(moving_x), "the goose faces the way it flies", "x axis %s, vx %.1f" % [placed.x, moving_x])


## After flee_time the goose climbs off the top and has escaped once fully above it; a
## goose told to flee early (no shells) escapes earlier.
func _test_flight_escapes_after_flee_time() -> void:
	var goose := Content.bird("goose")
	_check(not Flight.has_escaped(goose, 3, goose.flee_time, Play.FIELD), "no escape before flee_time", "escaped")
	var escaped_at := -1.0
	var age := goose.flee_time
	while age < goose.flee_time + 10.0:
		if Flight.has_escaped(goose, 3, age, Play.FIELD):
			escaped_at = age
			break
		age += 1.0 / 60.0
	_check(escaped_at > goose.flee_time, "the goose escapes after flee_time", "escaped at %.2f" % escaped_at)
	var top := Flight.position(goose, 3, escaped_at, Play.FIELD)
	_check(top.y + goose.size.y / 2.0 < Flight.ESCAPE_Y, "it has escaped once fully above the top", str(top))
	var early := -1.0
	age = 1.0
	while age < goose.flee_time:
		if Flight.has_escaped(goose, 3, age, Play.FIELD, 1.0, 1.0):
			early = age
			break
		age += 1.0 / 60.0
	_check(early > 1.0 and early < escaped_at, "a goose fleeing early escapes earlier", "at %.2f" % early)


## The hitbox follows the bird's position, rotation and facing.
func _test_flight_hitbox() -> void:
	var goose := Content.bird("goose")
	for facing: float in [1.0, -1.0]:
		var placed := Transform2D(0.3 * facing, Vector2(facing, 1.0), 0.0, Vector2(500, 300))
		var label := "facing %s" % ("right" if facing > 0.0 else "left")
		_check(Flight.hits(goose, placed, placed * LOCAL_INSIDE), label + ": a point just inside the polygon hits", str(placed * LOCAL_INSIDE))
		_check(not Flight.hits(goose, placed, placed * LOCAL_JUST_OUTSIDE), label + ": a point just outside the polygon misses", str(placed * LOCAL_JUST_OUTSIDE))
		var in_box := absf(LOCAL_BOX_CORNER.x) < goose.size.x / 2.0 and absf(LOCAL_BOX_CORNER.y) < goose.size.y / 2.0
		_check(in_box and not Flight.hits(goose, placed, placed * LOCAL_BOX_CORNER), label + ": inside the sprite box but outside the polygon misses", str(placed * LOCAL_BOX_CORNER))


func _test_wave_schedule() -> void:
	var endless := Content.mode(GameState.ENDLESS_MODE)
	var a := Wave.endless(endless, 3, 42)
	var b := Wave.endless(endless, 3, 42)
	var same := a.shells == b.shells and a.spawns.size() == b.spawns.size() and is_equal_approx(a.speed_scale, b.speed_scale)
	for i in mini(a.spawns.size(), b.spawns.size()):
		same = same and a.spawns[i].bird_id == b.spawns[i].bird_id and a.spawns[i].time == b.spawns[i].time and a.spawns[i].bird_seed == b.spawns[i].bird_seed
	_check(same, "a wave is a pure function of mode, index and run seed", "differs")
	var other := Wave.endless(endless, 3, 43)
	_check(other.spawns[0].bird_seed != a.spawns[0].bird_seed, "another run seed gives other bird seeds", str(other.spawns[0].bird_seed))
	var counts := []
	for index: int in [1, 2, 3, 5, 20]:
		counts.append(Wave.endless(endless, index, 42).spawns.size())
	_check(counts == [2, 3, 4, 6, 6], "birds start at start_birds and grow by bird_growth up to max_birds", str(counts))
	_check(is_equal_approx(Wave.endless(endless, 1, 42).speed_scale, 1.0) and is_equal_approx(Wave.endless(endless, 2, 42).speed_scale, 1.0 + endless.speed_growth), "the speed scale grows per wave", "%.2f" % Wave.endless(endless, 2, 42).speed_scale)
	_check(is_equal_approx(Wave.endless(endless, 50, 42).speed_scale, endless.speed_cap), "the speed scale stops at its cap", "%.2f" % Wave.endless(endless, 50, 42).speed_scale)
	_check(a.shells == a.spawns.size() * endless.shells_per_bird, "a wave's shells are birds x shells_per_bird", "%d for %d birds" % [a.shells, a.spawns.size()])
	var timed := true
	for i in a.spawns.size():
		timed = timed and is_equal_approx(a.spawns[i].time, i * endless.spawn_interval) and a.spawns[i].bird_id == "goose"
	_check(timed, "spawns come every spawn_interval from 0", str(a.spawns.map(func(spawn: Wave.Spawn) -> float: return spawn.time)))


func _test_ammo_pool() -> void:
	_check(Ammo.pool_size(3, 3) == 9, "the pool is birds x shells_per_bird", str(Ammo.pool_size(3, 3)))
	var ammo := Ammo.new(2)
	var used := [ammo.use(), ammo.use()]
	_check(used == [true, true] and ammo.shells == 0 and ammo.is_empty(), "each shot uses one shell", "%s, %d left" % [used, ammo.shells])
	_check(not ammo.use() and ammo.shells == 0 and ammo.is_empty(), "a shot with no shells is refused", "%d left" % ammo.shells)


func _test_scoring_combo() -> void:
	var scoring := Scoring.new(3)
	var awarded := [scoring.hit(100), scoring.hit(100), scoring.hit(100), scoring.hit(100)]
	_check(awarded == [100, 200, 300, 300] and scoring.multiplier == 3, "consecutive hits raise the multiplier up to combo_cap", "%s, x%d" % [awarded, scoring.multiplier])
	scoring.miss()
	_check(scoring.multiplier == 1, "a miss resets the multiplier", "x%d" % scoring.multiplier)
	_check(scoring.hit(50) == 50 and scoring.score == 950 and scoring.hits == 5 and scoring.misses == 1 and scoring.shots() == 6, "score, hits, misses and shots add up", "%d %d %d" % [scoring.score, scoring.hits, scoring.misses])


## A best score is written to the save and survives a reload; a new best saves at once.
func _test_save_and_reload() -> void:
	_check(_game.save_path == GameState.TOOL_SAVE_PATH, "tool runs use the tool save", _game.save_path)
	_game.best_endless = 1234
	_game.save_game()
	_game.best_endless = 0
	_game.load_game()
	_check(_game.best_endless == 1234, "the best score survives a save and reload", str(_game.best_endless))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == GameState.SAVE_VERSION, "the save is versioned", str(saved))
	_check(not _game.record_endless(1000) and _game.best_endless == 1234, "a lower score is not a best", str(_game.best_endless))
	_check(_game.record_endless(2000), "a higher score is a new best", str(_game.best_endless))
	_game.best_endless = 0
	_game.load_game()
	_check(_game.best_endless == 2000, "a new best is saved at once", str(_game.best_endless))
	_clear_tool_save()


## A corrupt, unknown-version or malformed save is backed up, reported in the log and on
## the error label, and the game starts fresh with a fresh save.
func _test_save_corrupt_and_unknown_version() -> void:
	var cases := {
		"{not json": "corrupt (line",
		JSON.stringify({"version": 2, "best_endless": 5}): "version 2 is not this game's version 1",
		JSON.stringify({"version": 1, "best_endless": "lots"}): "'best_endless' is not a whole number",
		JSON.stringify({"version": 1, "best_endless": 5, "coins": 3}): "unknown key 'coins'",
		JSON.stringify({"version": 1}): "missing key 'best_endless'",
	}
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	for text: String in cases:
		var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		_game.best_endless = 77
		_game.quiet_errors = true
		var errors := _game.reported_errors.size()
		_game.load_game()
		_game.quiet_errors = false
		var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
		var label := "save %s" % cases[text]
		_check(reported.contains(cases[text]) and reported.contains(_game.backup_path()), label + " is reported", reported)
		_check(error_label.visible and error_label.text == reported, label + " shows on the error label", error_label.text)
		_check(FileAccess.get_file_as_string(_game.backup_path()) == text, label + " is backed up", FileAccess.get_file_as_string(_game.backup_path()))
		var fresh: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
		_check(_game.best_endless == 0 and fresh is Dictionary and fresh.get("best_endless") == 0.0, label + ": the game starts fresh", "best %d, save %s" % [_game.best_endless, fresh])
	error_label.hide()
	_clear_tool_save()


## The HUD bar: inside the safe area at the top, score, wave, shells as icons, combo,
## escaped and the pause button (icon, "Pause", >= 44x44); the shot surface is below it.
func _test_play_hud_layout() -> void:
	var play := await _start_run(11)
	var bar := play.get_node("Hud/Bar") as Control
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Button
	var shot_input := play.get_node("ShotInput") as Control
	var texts := [_text(play, "Score"), _text(play, "Wave"), _text(play, "Combo"), _text(play, "Escaped")]
	_check(texts == ["Score 0", "Wave 1", "x1", "Escaped 0/10"], "the HUD shows score, wave, combo and escapes", str(texts))
	_check(_shell_icons(play) == play.wave.shells and play.wave.shells == 6, "the HUD shows the shells as icons", "%d icons" % _shell_icons(play))
	_check(pause_button.accessibility_name == "Pause" and pause_button.text.is_empty() and pause_button.icon != null, "the pause button is an icon named Pause", pause_button.accessibility_name)
	_check(pause_button.focus_mode == Control.FOCUS_ALL, "the pause button takes keyboard focus", str(pause_button.focus_mode))
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		var label := "%dx%d HUD" % [window.x, window.y]
		var rect := pause_button.get_global_rect()
		var safe := _game.safe_rect()
		_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET and safe.encloses(rect), label + " pause button >= 44x44 inside the safe area", str(rect))
		_check(bar.get_global_rect().is_equal_approx(Rect2(safe.position, Vector2(safe.size.x, Play.HUD_BAR_HEIGHT))) and rect.end.y <= safe.position.y + Play.HUD_BAR_HEIGHT, label + " bar at the top of the safe area", str(bar.get_global_rect()))
		var surface := shot_input.get_global_rect()
		_check(is_equal_approx(surface.position.y, safe.position.y + Play.HUD_BAR_HEIGHT) and is_equal_approx(surface.end.y, _game.visible_rect().end.y) and is_equal_approx(surface.size.x, _game.visible_rect().size.x), label + " shot surface fills the screen below the bar", str(surface))
	_game.safe_area_override = NOTCHED_SAFE_RECT
	root.size = LANDSCAPE_19_5_9
	await process_frame
	await process_frame
	_check(NOTCHED_SAFE_RECT.encloses(bar.get_global_rect()), "the HUD bar is clear of the notch", str(bar.get_global_rect()))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## A synthetic touch (index 7) on a goose hits it: score, combo, shells, a pop-up; the goose
## shows its hit frame, falls off the bottom and is removed.
func _test_play_touch_hits_goose() -> void:
	var play := await _start_run(21)
	var bird := play.spawn_bird("goose", 99)
	await process_frame
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check(bird.state != Bird.State.FLYING and play.scoring.hits == 1 and play.scoring.score == 100, "a touch on a goose hits it", "state %d, hits %d" % [bird.state, play.scoring.hits])
	_check(play.ammo.shells == play.wave.shells - 1 and _shell_icons(play) == play.ammo.shells, "the hit used one shell", "%d left" % play.ammo.shells)
	_check(_text(play, "Score") == "Score 100" and _text(play, "Combo") == "x2", "the HUD shows the score and combo", "%s %s" % [_text(play, "Score"), _text(play, "Combo")])
	var popups := play.get_node("World/Popups").get_children()
	_check(popups.size() == 1 and (popups[0] as Label).text == "+100", "a score pop-up shows at the hit", str(popups))
	var sprite := bird.get_node("Sprite") as Sprite2D
	_check(sprite.texture.resource_path == bird.spec.texture_path("hit"), "the goose shows its hit frame", sprite.texture.resource_path)
	var fell := [false]
	bird.gone.connect(func(_b: Bird) -> void: fell[0] = true)
	for i in 240:
		if not is_instance_valid(bird):
			break
		await process_frame
	_check(fell[0] and not is_instance_valid(bird), "the hit goose falls off the screen and is removed", "fell %s" % fell[0])
	var second := play.spawn_bird("goose", 99)
	await process_frame
	await _touch(_global(play, second.transform * LOCAL_BODY))
	popups = play.get_node("World/Popups").get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(play.scoring.score == 300 and (popups.back() as Label).text == "+200 x2", "a second hit scores x2 and its pop-up shows it", "%d %s" % [play.scoring.score, popups])


func _test_play_touch_outside_polygon_misses() -> void:
	var play := await _start_run(22)
	var bird := play.spawn_bird("goose", 7)
	await process_frame
	await _touch(_global(play, bird.transform * LOCAL_JUST_OUTSIDE))
	_check(bird.is_flying() and play.scoring.hits == 0 and play.scoring.misses == 1, "a touch just outside the goose polygon misses", "hits %d, misses %d" % [play.scoring.hits, play.scoring.misses])
	_check(play.ammo.shells == play.wave.shells - 1 and play.scoring.multiplier == 1, "a miss uses a shell and resets the combo", "%d left, x%d" % [play.ammo.shells, play.scoring.multiplier])
	await _touch(_global(play, bird.transform * LOCAL_BOX_CORNER))
	_check(bird.is_flying() and play.scoring.misses == 2, "a touch inside the sprite box but outside the polygon misses", "misses %d" % play.scoring.misses)
	await _touch(_global(play, bird.transform * LOCAL_INSIDE))
	_check(not bird.is_flying() and play.scoring.hits == 1, "a touch just inside the goose polygon hits", "hits %d" % play.scoring.hits)


## Two birds on the same spot: one shot hits only the frontmost.
func _test_play_overlapping_hit_counts_once() -> void:
	var play := await _start_run(23)
	var back := play.spawn_bird("goose", 5)
	var front := play.spawn_bird("goose", 5)
	await process_frame
	_check(back.transform.is_equal_approx(front.transform), "the two geese overlap", "%s vs %s" % [back.transform, front.transform])
	await _touch(_global(play, front.transform * LOCAL_BODY))
	_check(play.scoring.hits == 1 and play.scoring.score == 100, "a hit on two overlapping geese counts once", "hits %d, score %d" % [play.scoring.hits, play.scoring.score])
	_check(not front.is_flying() and back.is_flying(), "the frontmost goose is the one hit", "front %d, back %d" % [front.state, back.state])


## Two fingers pressing at once make two shots (indices 7 and 8, never 0).
func _test_play_two_fingers_two_shots() -> void:
	var play := await _start_run(24)
	await _touches([_global(play, SKY_POINTS[0]), _global(play, SKY_POINTS[1])], [TOUCH_INDEX, TOUCH_INDEX + 1])
	_check(play.scoring.shots() == 2 and play.ammo.shells == play.wave.shells - 2, "two fingers make two shots", "%d shots" % play.scoring.shots())


## Once the pool is empty a shot is refused (no shot, no miss) with the empty cue; the
## flying birds flee at once and later spawns flee from the start.
func _test_play_empty_pool_refuses() -> void:
	var play := await _start_run(25)
	var bird := play.spawn_bird("goose", 3)
	await process_frame
	var shells := play.ammo.shells
	for i in shells:
		await _touch(_global(play, SKY_POINTS[i % SKY_POINTS.size()]))
	_check(play.ammo.is_empty() and play.scoring.misses == shells and _shell_icons(play) == 0, "every shell is used", "%d left, %d misses" % [play.ammo.shells, play.scoring.misses])
	_check(bird.flee_at <= bird.age and bird.flee_at < bird.spec.flee_time, "out of shells, the flying goose flees at once", "flee_at %.2f, age %.2f" % [bird.flee_at, bird.age])
	await _touch(_global(play, SKY_POINTS[0]))
	_check(play.refused == 1 and play.scoring.shots() == shells and play.scoring.misses == shells, "a shot with no shells is refused (no shot, no miss)", "refused %d, shots %d" % [play.refused, play.scoring.shots()])
	_check(play.is_empty_cue_shown() and (play.get_node("Hud/Bar/Stats/Shells") as Control).modulate == Play.EMPTY_TINT, "a refused shot shows the empty cue on the HUD shells", "cue %s" % play.is_empty_cue_shown())
	var late := play.spawn_bird("goose", 4)
	_check(late.flee_at == 0.0, "a goose spawned with no shells flees from the start", "flee_at %.2f" % late.flee_at)
	var multiplier := play.scoring.multiplier
	await _touch(_global(play, SKY_POINTS[1]))
	_check(play.refused == 2 and play.scoring.multiplier == multiplier, "a refused shot leaves the combo alone", "x%d" % play.scoring.multiplier)
	for i in roundi(Play.EMPTY_CUE_TIME * 60.0) + 2:
		await process_frame
	_check(not play.is_empty_cue_shown(), "the empty cue fades", "still shown")
	Engine.time_scale = FAST_TIME_SCALE
	for i in 3000:
		if play.wave.index == 2:
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(play.wave.index == 2 and play.ammo.shells == play.wave.shells and play.flying_birds().is_empty(), "the wave ends once its fleeing birds are gone, and the next starts with full shells", "wave %d, %d shells" % [play.wave.index, play.ammo.shells])
	_check(play.escaped == 4 and not is_instance_valid(bird), "every bird of the emptied wave fled and escaped", "%d escaped" % play.escaped)


## Each pause cause opens the menu with the tree paused and Resume focused; the run is
## frozen while paused, and Resume continues it unchanged.
func _test_pause_causes_and_resume() -> void:
	var play := await _start_run(31)
	var bird := play.spawn_bird("goose", 8)
	await process_frame
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Button
	var resume_button := play.get_node("PauseLayer/PauseMenu/Panel/ResumeButton") as Button
	var causes: Dictionary[String, Callable] = {
		"pause button": func() -> void: await _tap(pause_button),
		"Escape": func() -> void: await _key(KEY_ESCAPE),
		"window lost focus": func() -> void: play.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT),
		"app lost focus": func() -> void: play.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT),
		"app paused or hidden": func() -> void: play.notification(Node.NOTIFICATION_APPLICATION_PAUSED),
		"page hidden": func() -> void: _game.page_hidden.emit(),
	}
	for cause: String in causes:
		await causes[cause].call()
		await process_frame
		_check(play.is_paused() and paused and play.pause_log.back() == cause, "%s opens the pause menu with the tree paused" % cause, "menu %s, paused %s, log %s" % [play.is_paused(), paused, play.pause_log])
		_check(resume_button.has_focus(), "%s: Resume is focused" % cause, str(root.gui_get_focus_owner()))
		var age := bird.age
		var clock := play.wave_clock
		for i in 5:
			await process_frame
		_check(bird.age == age and play.wave_clock == clock, "%s: the run is frozen while paused" % cause, "age %.3f -> %.3f" % [age, bird.age])
		await _key(KEY_ENTER)
		_check(not play.is_paused() and not paused, "%s: Resume (Enter) closes the menu and unpauses" % cause, "menu %s, paused %s" % [play.is_paused(), paused])
		await process_frame
		_check(bird.age > age and bird.is_flying(), "%s: the run continues unchanged" % cause, "age %.3f -> %.3f" % [age, bird.age])


## The menu's buttons: >= 44x44, focusable with a visible focus style, the ring shown
## after Tab, Up/Down cycling Resume, Restart and Quit.
func _test_pause_menu_keyboard() -> void:
	var play := await _start_run(32)
	play.open_pause("test")
	await process_frame
	var panel := play.get_node("PauseLayer/PauseMenu/Panel")
	var buttons: Array[Button] = [panel.get_node("ResumeButton"), panel.get_node("RestartButton"), panel.get_node("QuitButton")]
	_check(buttons.map(func(b: Button) -> String: return b.text) == ["Resume", "Restart", "Quit to title"], "the menu holds Resume, Restart and Quit to title", str(buttons.map(func(b: Button) -> String: return b.text)))
	for button in buttons:
		var rect := button.get_global_rect()
		var style := button.get_theme_stylebox(&"focus")
		_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET and button.focus_mode == Control.FOCUS_ALL and style != null and not (style is StyleBoxEmpty), "%s: >= 44x44, focusable, visible focus style" % button.text, str(rect))
	_check(buttons[0].has_focus() and not buttons[0].has_focus(true), "Resume is focused with the ring hidden on opening", "ring shown")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == buttons[1] and buttons[1].has_focus(true), "Tab moves to Restart and shows the ring", str(root.gui_get_focus_owner()))
	var order := []
	for i in 3:
		await _key(KEY_DOWN)
		order.append((root.gui_get_focus_owner() as Button).text)
	_check(order == ["Quit to title", "Resume", "Restart"], "Down cycles through the menu", str(order))
	await _key(KEY_UP)
	_check(root.gui_get_focus_owner() == buttons[0], "Up moves back", str(root.gui_get_focus_owner()))
	play.resume()


## Touches on the pause button, the menu and while paused are never shots.
func _test_pause_touches_are_not_shots() -> void:
	var play := await _start_run(33)
	await _tap(play.get_node("Hud/Bar/PauseButton") as Control)
	_check(play.is_paused() and play.scoring.shots() == 0, "a touch on the pause button is not a shot", "%d shots" % play.scoring.shots())
	await _touch(_global(play, SKY_POINTS[0]))
	_check(play.scoring.shots() == 0 and play.ammo.shells == play.wave.shells, "touches while paused are not shots", "%d shots" % play.scoring.shots())
	await _tap(play.get_node("PauseLayer/PauseMenu/Panel/ResumeButton") as Control)
	_check(not play.is_paused() and play.scoring.shots() == 0, "a touch on Resume resumes and is not a shot", "%d shots" % play.scoring.shots())
	await _touch(_global(play, SKY_POINTS[0]))
	_check(play.scoring.shots() == 1, "after resuming a touch is a shot again", "%d shots" % play.scoring.shots())
	_game.goto(GameState.Flow.TITLE)
	await process_frame
	await _touch(_global(play, SKY_POINTS[1]))
	_check(play.scoring.shots() == 1, "no shots while a transition runs", "%d shots" % play.scoring.shots())
	await _game.transition_finished
	_game.goto(GameState.Flow.PLAY, {"mode": GameState.ENDLESS_MODE, "seed": 36})
	await scene_changed
	var arriving := current_scene as Play
	_check(arriving != null and _game.is_transitioning(), "the run is on screen while the fade still runs", str(current_scene))
	arriving.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not arriving.is_paused() and not paused, "a pause during the transition waits for it", "paused early")
	await _game.transition_finished
	_check(arriving.is_paused() and paused and arriving.pause_log.back() == "window lost focus", "the pause opens once the transition is done", str(arriving.pause_log))
	arriving.resume()


## Rotating to portrait during a run shows the overlay; rotating back leaves the pause
## menu open with the tree paused and the run intact (plan AC 3).
func _test_pause_after_rotating() -> void:
	var play := await _start_run(34)
	var bird := play.spawn_bird("goose", 9)
	await process_frame
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown() and paused, "portrait during a run shows the overlay and pauses", "overlay %s, paused %s" % [_game.is_rotate_overlay_shown(), paused])
	var age := bird.age
	root.size = BASE_WINDOW
	await process_frame
	await process_frame
	_check(not _game.is_rotate_overlay_shown() and play.is_paused() and paused and play.pause_log.back() == "rotate overlay", "rotating back leaves the pause menu open, tree paused", "menu %s, paused %s" % [play.is_paused(), paused])
	_check(bird.age == age and bird.is_flying(), "the run is intact", "age %.3f -> %.3f" % [age, bird.age])
	# Turned upright again with the menu open (Resume focused): keys reach nothing under the overlay.
	root.size = PORTRAIT_9_19_5
	await process_frame
	await _key(KEY_ENTER)
	await _key(KEY_ESCAPE)
	_check(play.is_paused() and paused and bird.age == age, "under the rotate overlay keys press nothing on the pause menu", "menu %s, paused %s" % [play.is_paused(), paused])
	root.size = BASE_WINDOW
	await process_frame
	_check(play.is_paused() and paused, "rotating back again keeps the menu open", "menu %s, paused %s" % [play.is_paused(), paused])
	play.resume()
	await process_frame
	_check(bird.age > age, "Resume continues the run", "age %.3f" % bird.age)


## Restart starts a new Endless run (a fresh scene and seed); Quit goes to the title;
## neither leaves the tree paused.
func _test_pause_restart_and_quit() -> void:
	var play := await _start_run(35)
	play.open_pause("test")
	await _tap(play.get_node("PauseLayer/PauseMenu/Panel/RestartButton") as Control)
	await _game.transition_finished
	await process_frame
	var restarted := current_scene as Play
	_check(restarted != null and restarted != play and _game.state == GameState.Flow.PLAY and not paused, "Restart starts a new run", "%s paused %s" % [current_scene, paused])
	_check(restarted != null and restarted.run_seed == _game.flow_args["seed"] and restarted.run_seed != 35 and _game.flow_args["mode"] == GameState.ENDLESS_MODE, "the new run is Endless with a fresh seed", str(_game.flow_args))
	restarted.open_pause("test")
	await process_frame
	(restarted.get_node("PauseLayer/PauseMenu/Panel/QuitButton") as Button).grab_focus()
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE and current_scene is Title and not paused, "Quit to title goes to the title", "%s paused %s" % [current_scene, paused])


## 10 escapes end the run on the results screen with its stats; the new best is saved and
## survives a reload; Play again starts a new run and Title goes to the title.
func _test_run_ends_on_results() -> void:
	var play := await _start_run(41)
	var bird := play.spawn_bird("goose", 12)
	await process_frame
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check(play.scoring.score == 100, "the run scores one hit first", str(play.scoring.score))
	Engine.time_scale = FAST_TIME_SCALE
	for i in 6000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	_check(results != null and _game.state == GameState.Flow.RESULTS, "10 escapes end the run on the results screen", "%s at %s" % [current_scene, _game.state])
	if results == null:
		return
	var stats := _game.flow_args
	_check(stats.get("escaped") == 10 and stats.get("score") == 100 and stats.get("hits") == 1 and stats.get("shots") == 1 and stats.get("new_best") == true, "the results get the run's stats", str(stats))
	var shown := ["Score", "Accuracy", "Hits", "Escaped", "Best"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
	_check(shown == ["Score 100", "Accuracy 100%", "Birds hit 1", "Birds escaped 10", "Endless best 100"], "the results show score, accuracy, hits, escapes and best", str(shown))
	_check((results.get_node("Safe/NewBest") as Label).visible, "the results say New best!", "hidden")
	_check(Results.accuracy_text(0, 0) == Results.NO_VALUE and Results.accuracy_text(3, 4) == "75%", "accuracy is hits / shots, a dash with no shots", Results.accuracy_text(3, 4))
	var again := results.get_node("Safe/PlayAgainButton") as Button
	_check(again.has_focus() and again.get_global_rect().size.y >= MIN_TARGET and _game.safe_rect().encloses(again.get_global_rect()), "Play again is focused, >= 44 high, in the safe area", str(root.gui_get_focus_owner()))
	_game.best_endless = 0
	_game.load_game()
	_check(_game.best_endless == 100, "the new best survives a save and reload", str(_game.best_endless))
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == results.get_node("Safe/TitleButton"), "Tab reaches Title", str(root.gui_get_focus_owner()))
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.PLAY and current_scene is Play, "Play again starts a new run", str(current_scene))
	_game.goto(GameState.Flow.RESULTS, {"score": 40, "shots": 0, "hits": 0, "escaped": 10, "best": 100, "new_best": false})
	await _game.transition_finished
	_check(not (current_scene.get_node("Safe/NewBest") as Label).visible and (current_scene.get_node("Safe/Stats/Accuracy") as Label).text == "Accuracy " + Results.NO_VALUE, "a run below the best shows no New best!, and a dash for no shots", "shown")
	await _tap(current_scene.get_node("Safe/TitleButton") as Control)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE, "Title goes to the title", str(_game.state))
	_clear_tool_save()


## Starts an Endless run with `run_seed` and waits until it is on screen.
func _start_run(run_seed: int) -> Play:
	_game.goto(GameState.Flow.PLAY, {"mode": GameState.ENDLESS_MODE, "seed": run_seed})
	await _game.transition_finished
	await process_frame
	return current_scene as Play


## The canvas position of `point` in the play scene's World.
func _global(play: Play, point: Vector2) -> Vector2:
	return (play.get_node("World") as Node2D).to_global(point)


func _text(play: Play, stat: String) -> String:
	return (play.get_node("Hud/Bar/Stats/" + stat) as Label).text


func _shell_icons(play: Play) -> int:
	return play.get_node("Hud/Bar/Stats/Shells").get_children().filter(func(icon: Node) -> bool: return (icon as CanvasItem).visible).size()


## A real touch (press and release, index TOUCH_INDEX) at canvas position `at`.
func _touch(at: Vector2) -> void:
	await _touches([at], [TOUCH_INDEX])


## Presses one finger per point at once (indices `indices`), then releases them.
func _touches(points: Array[Vector2], indices: Array[int]) -> void:
	for pressed: bool in [true, false]:
		for i in points.size():
			var touch := InputEventScreenTouch.new()
			touch.index = indices[i]
			touch.position = root.get_final_transform() * points[i]
			touch.pressed = pressed
			Input.parse_input_event(touch)
		await process_frame


## Every expected error is reported (each a prefix of one error), and nothing else.
func _check_errors(errors: Array[String], expected: Array[String], label: String) -> void:
	for prefix in expected:
		_check(errors.any(func(e: String) -> bool: return e.begins_with(prefix)), "%s: reports %s" % [label, prefix], str(errors))
	_check(errors.size() == expected.size(), "%s: reports exactly %d errors" % [label, expected.size()], "%d: %s" % [errors.size(), errors])


func _clear_tool_save() -> void:
	for path: String in [GameState.TOOL_SAVE_PATH, GameState.TOOL_SAVE_PATH.get_basename() + ".corrupt.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_game.best_endless = 0


## Goes to a fresh title screen and waits for the transition to finish.
func _open_title() -> void:
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	await process_frame


## A real touch (press and release) at the centre of `control`.
func _tap(control: Control) -> void:
	var at := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.index = TOUCH_INDEX
		touch.position = at
		touch.pressed = pressed
		Input.parse_input_event(touch)
		await process_frame


## Presses and releases key `keycode`, as a keyboard would.
func _key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame


func _check(condition: bool, test_name: String, detail: String) -> void:
	if condition:
		_passed += 1
		print("test_gameplay: pass " + test_name)
	else:
		_failures.append("%s: %s" % [test_name, detail])
