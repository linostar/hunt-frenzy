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
## A point in the goose's head (front, top: non-zero local x, inside the hitbox), and its
## mirror behind the tail (outside it): a hit test that ignores the facing gets these wrong.
const LOCAL_HEAD := Vector2(36, -18)
const LOCAL_HEAD_MIRRORED := Vector2(-36, -18)
## A goose this old is well inside the field, above the grass (it climbs at least
## sin(30 degrees) x speed 140 = 70 units per second from 50 below the grass line).
const IN_FIELD_AGE := 2.0
## The pause button's size (plan AC 8).
const PAUSE_BUTTON_SIZE := Vector2(48, 48)
## WCAG AA contrast for text at the HUD's size.
const MIN_CONTRAST := 4.5
## A save path in a directory that does not exist: opening it for writing fails.
const UNWRITABLE_SAVE_PATH := "user://no_such_dir/save.json"
## Points in empty sky (World coordinates) while no bird is above the grass yet.
const SKY_POINTS: Array[Vector2] = [Vector2(120, 120), Vector2(840, 120), Vector2(480, 100)]
## How much faster game time runs while the escape test waits for 10 escapes.
const FAST_TIME_SCALE := 8.0

var _failures: Array[String] = []
var _passed := 0
var _deadline_msec := 0
## The "Game" autoload; this script compiles before autoloads exist, so it is fetched at start.
var _game: GameState
## Every line printed while the tests run (plan AC 15's log checks read it).
var _log := LogCapture.new()


## Records every printed line (OS.add_logger); the engine may log from other threads.
class LogCapture extends Logger:
	var _lines: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_message(message: String, _error: bool) -> void:
		_mutex.lock()
		_lines.append(message.strip_edges(false, true))
		_mutex.unlock()

	func size() -> int:
		_mutex.lock()
		var count := _lines.size()
		_mutex.unlock()
		return count

	## The lines logged from index `from` on.
	func since(from: int) -> PackedStringArray:
		_mutex.lock()
		var lines := _lines.slice(from)
		_mutex.unlock()
		return lines


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	_game = root.get_node_or_null("Game") as GameState
	if _game == null:
		printerr("test_gameplay: FAILED: Game autoload not found")
		quit(1)
		return
	OS.add_logger(_log)
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
		_test_title_content_error_banner,
		_test_flight_determinism,
		_test_flight_stays_in_field_and_turns,
		_test_flight_escapes_after_flee_time,
		_test_flight_hitbox,
		_test_flight_every_type_deterministic_and_in_field,
		_test_flight_zigzag_reverses,
		_test_flight_launch_and_split_headings,
		_test_wave_schedule,
		_test_wave_unlocks_by_wave,
		_test_wave_mix_follows_weights,
		_test_wave_golden_chance,
		_test_wave_shells_cover_every_hit,
		_test_ammo_pool,
		_test_scoring_combo,
		_test_scoring_damage_and_penalty,
		_test_save_and_reload,
		_test_save_corrupt_and_unknown_version,
		_test_save_web_persist_reporting,
		_test_play_hud_layout,
		_test_play_hud_fits_any_pool,
		_test_play_touch_hits_goose,
		_test_play_hit_frame_keeps_facing,
		_test_play_grass_hides_geese,
		_test_play_touch_outside_polygon_misses,
		_test_play_overlapping_hit_counts_once,
		_test_play_two_fingers_two_shots,
		_test_play_empty_pool_refuses,
		_test_play_armored_takes_two_hits,
		_test_play_splitter_splits_into_goslings,
		_test_play_split_with_last_shell,
		_test_play_golden_scores_and_escapes,
		_test_play_decoy_penalty,
		_test_pause_causes_and_resume,
		_test_pause_menu_keyboard,
		_test_pause_touches_are_not_shots,
		_test_pause_escape_toggles,
		_test_pause_after_rotating,
		_test_pause_after_overlay_during_transition_in,
		_test_pause_restart_and_quit,
		_test_run_ends_on_results,
		_test_run_end_save_failure,
	]


func _run() -> void:
	root.size = BASE_WINDOW
	_clear_tool_save()
	await process_frame
	for test in _tests():
		await test.call()
	_clear_tool_save()
	OS.remove_logger(_log)
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
	# At 3x speed a goose crosses the 960-wide field more than once before fleeing. A turn
	# is a real reversal: the horizontal velocity goes from one sign to the other (a goose
	# pinned at the edge, velocity 0, never turns).
	var turns := 0
	var last_sign := 0.0
	for step in roundi(goose.flee_time * 60.0):
		var moving := Flight.velocity(goose, 5, step / 60.0, Play.FIELD, 3.0)
		if absf(moving.x) < 1.0:
			continue
		if last_sign != 0.0 and signf(moving.x) == -last_sign:
			turns += 1
		last_sign = signf(moving.x)
	_check(turns >= 1, "the goose turns back at the side edges (its velocity reverses)", "%d turns" % turns)
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
		_check(Flight.hits(goose, placed, placed * LOCAL_HEAD), label + ": a point in the head hits", str(placed * LOCAL_HEAD))
		_check(not Flight.hits(goose, placed, placed * LOCAL_HEAD_MIRRORED), label + ": the head's mirror point behind the tail misses", str(placed * LOCAL_HEAD_MIRRORED))


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
	var timed := true
	for i in a.spawns.size():
		timed = timed and is_equal_approx(a.spawns[i].time, i * endless.spawn_interval)
	_check(timed, "spawns come every spawn_interval from 0", str(a.spawns.map(func(spawn: Wave.Spawn) -> float: return spawn.time)))


func _test_ammo_pool() -> void:
	_check(Ammo.pool_size(3, 3) == 9, "the pool is hits needed x shells per hit", str(Ammo.pool_size(3, 3)))
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
## escaped and the pause button (icon, "Pause", 48x48, the bar's only interactive Control);
## the "Out of shells!" cue is readable on its own plate; the shot surface is below it.
## The run's start and its first wave are logged (plan AC 15).
func _test_play_hud_layout() -> void:
	var from := _log.size()
	var play := await _start_run(11)
	_check_logged(from, "^\\[Play\\] Run start: mode endless, seed 11 \\(escape limit 10, combo cap 5, 3 shells per hit\\)$", "the run start is logged with its mode and seed")
	_check_logged(from, "^\\[Play\\] Wave 1 start: 2 birds \\(goose, goose\\), 6 shells, speed x1\\.00$", "the wave start is logged with its birds and shells")
	var bar := play.get_node("Hud/Bar") as Control
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Button
	var shot_input := play.get_node("ShotInput") as Control
	var texts := [_text(play, "Score"), _text(play, "Wave"), _text(play, "Combo"), _text(play, "Escaped")]
	_check(texts == ["Score 0", "Wave 1", "x1", "Escaped 0/10"], "the HUD shows score, wave, combo and escapes", str(texts))
	_check(_shell_icons(play) == play.wave.shells and play.wave.shells == 6, "the HUD shows the shells as icons", "%d icons" % _shell_icons(play))
	_check(pause_button.accessibility_name == "Pause" and pause_button.text.is_empty() and pause_button.icon != null, "the pause button is an icon named Pause", pause_button.accessibility_name)
	_check(pause_button.focus_mode == Control.FOCUS_ALL, "the pause button takes keyboard focus", str(pause_button.focus_mode))
	var interactive := _interactive_controls(bar)
	_check(interactive == [pause_button], "the pause button is the only interactive Control in the HUD bar", str(interactive))
	# "Out of shells!" is text (not a colour change alone) on an opaque plate, so its
	# contrast does not depend on the sky behind the bar.
	var empty := play.get_node("Hud/Bar/Stats/Empty") as Label
	var plate := empty.get_theme_stylebox(&"normal") as StyleBoxFlat
	var ratio := _contrast(empty.get_theme_color(&"font_color"), plate.bg_color) if plate != null else 0.0
	_check(empty.text == "Out of shells!" and plate != null and is_equal_approx(plate.bg_color.a, 1.0) and ratio >= MIN_CONTRAST, "the empty cue is text on an opaque plate at >= 4.5:1 contrast", "plate %s, %.2f:1" % [plate, ratio])
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		var label := "%dx%d HUD" % [window.x, window.y]
		var rect := pause_button.get_global_rect()
		var safe := _game.safe_rect()
		_check(rect.size.is_equal_approx(PAUSE_BUTTON_SIZE) and safe.encloses(rect), label + " pause button 48x48 inside the safe area", str(rect))
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


## The HUD bar never overflows. A pool of up to Play.SHELL_ICONS_MAX shells shows one icon
## per shell; a bigger one shows one icon and the shells left ("x11"). The largest pool
## modes.json can produce is max_birds x the most hits a bird the mode can spawn needs x
## shells_per_hit (Endless: 6 x 3 (a splitter and its 2 goslings) x 3 = 54). At that pool
## and at the largest icon row, with the widest texts (a 9-digit score, wave 999, the empty
## cue, the combo cap, 10/10 escaped), every stat lies inside the safe area and left of the
## pause button, at 16:9, 19.5:9, 4:3 and under a notch.
func _test_play_hud_fits_any_pool() -> void:
	var play := await _start_run(12)
	var max_pool := 0
	for each in Content.modes():
		var most := Wave.hits_needed(Content.bird(each.golden_bird))
		for entry in each.birds:
			most = maxi(most, Wave.hits_needed(Content.bird(entry.bird)))
		max_pool = maxi(max_pool, Ammo.pool_size(each.max_birds * most, each.shells_per_hit))
	_check(max_pool == 54, "the largest pool modes.json can produce is 54 shells", str(max_pool))
	var count := play.get_node("Hud/Bar/Stats/Shells/Count") as Label
	play.set_shell_pool(Play.SHELL_ICONS_MAX)
	_check(_shell_icons(play) == Play.SHELL_ICONS_MAX and not count.visible, "a pool of %d shows one icon per shell" % Play.SHELL_ICONS_MAX, "%d icons, count %s" % [_shell_icons(play), count.visible])
	play.set_shell_pool(Play.SHELL_ICONS_MAX + 1)
	_check(_shell_icons(play) == 1 and count.visible and count.text == "x%d" % (Play.SHELL_ICONS_MAX + 1), "a bigger pool shows one icon and its count", "%d icons, %s" % [_shell_icons(play), count.text])
	await _touch(_global(play, SKY_POINTS[0]))
	_check(count.text == "x%d" % Play.SHELL_ICONS_MAX and _shell_icons(play) == 1, "the count goes down as shells are used", count.text)
	var stats := play.get_node("Hud/Bar/Stats") as Control
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Control
	(play.get_node("Hud/Bar/Stats/Empty") as Control).show()
	var cases: Array[String] = ["16:9", "19.5:9", "4:3", "19.5:9 notched"]
	var windows: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_19_5_9, LANDSCAPE_4_3, LANDSCAPE_19_5_9]
	for pool: int in [Play.SHELL_ICONS_MAX, max_pool]:
		play.scoring.score = GameState.SAVE_SCORE_MAX
		play.scoring.multiplier = play.mode.combo_cap
		play.wave.index = 999
		play.escaped = play.mode.escape_limit
		play.set_shell_pool(pool)
		for i in cases.size():
			_game.safe_area_override = NOTCHED_SAFE_RECT if cases[i].ends_with("notched") else Rect2()
			root.size = windows[i]
			await process_frame
			await process_frame
			var safe := _game.safe_rect()
			var limit := pause_button.get_global_rect().position.x
			var stray: Array[String] = []
			for child in stats.get_children():
				var shown := child as Control
				var rect := shown.get_global_rect()
				if shown.visible and (rect.position.x < safe.position.x - 0.5 or rect.end.x > limit + 0.5 or rect.position.y < safe.position.y - 0.5 or rect.end.y > safe.position.y + Play.HUD_BAR_HEIGHT + 0.5):
					stray.append("%s %s" % [shown.name, rect])
			_check(stray.is_empty() and stats.get_combined_minimum_size().x <= stats.size.x + 0.5, "%s, pool %d: the widest HUD stays inside the safe bar, clear of the pause button" % [cases[i], pool], "min width %.1f of %.1f; outside: %s" % [stats.get_combined_minimum_size().x, stats.size.x, stray])
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## A synthetic touch (index 7) on a goose hits it: score, combo, shells, a pop-up; the goose
## shows its hit frame, falls off the bottom and is removed.
func _test_play_touch_hits_goose() -> void:
	var play := await _start_run(21)
	var bird := await _spawn_flying(play, 99)
	var from := _log.size()
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check_logged(from, "^\\[Play\\] Hit goose #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): 100 points x1 = 100, score 100 \\(wave 1 at t -?[\\d.]+, 5 shells left\\)$" % bird.number, "the hit is logged with the bird, points and multiplier")
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
	var second := await _spawn_flying(play, 99)
	await _touch(_global(play, second.transform * LOCAL_BODY))
	popups = play.get_node("World/Popups").get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check(play.scoring.score == 300 and (popups.back() as Label).text == "+200 x2", "a second hit scores x2 and its pop-up shows it", "%d %s" % [play.scoring.score, popups])


func _test_play_touch_outside_polygon_misses() -> void:
	var play := await _start_run(22)
	var bird := await _spawn_flying(play, 7)
	# Held still: these points are a unit from the polygon's edge, closer than a frame's flight.
	bird.set_process(false)
	var from := _log.size()
	await _touch(_global(play, bird.transform * LOCAL_JUST_OUTSIDE))
	_check_logged(from, "^\\[Play\\] Miss at \\([\\d.]+, [\\d.]+\\): combo reset, score 0 \\(wave 1 at t -?[\\d.]+, 5 shells left\\)$", "the miss is logged with its position")
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
	back.age = IN_FIELD_AGE
	front.age = IN_FIELD_AGE
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
	var from := _log.size()
	var bird := play.spawn_bird("goose", 3)
	await process_frame
	var shells := play.ammo.shells
	for i in shells:
		await _touch(_global(play, SKY_POINTS[i % SKY_POINTS.size()]))
	_check(play.ammo.is_empty() and play.scoring.misses == shells and _shell_icons(play) == 0, "every shell is used", "%d left, %d misses" % [play.ammo.shells, play.scoring.misses])
	_check(bird.flee_at <= bird.age and bird.flee_at < bird.spec.flee_time, "out of shells, the flying goose flees at once", "flee_at %.2f, age %.2f" % [bird.flee_at, bird.age])
	await _touch(_global(play, SKY_POINTS[0]))
	_check(play.refused == 1 and play.scoring.shots() == shells and play.scoring.misses == shells, "a shot with no shells is refused (no shot, no miss)", "refused %d, shots %d" % [play.refused, play.scoring.shots()])
	_check_logged(from, "^\\[Play\\] Out of shells: \\d+ flying birds flee, \\d+ still to spawn will flee \\(wave 1\\)$", "running out of shells is logged")
	_check_logged(from, "^\\[Play\\] Shot refused at \\([\\d.]+, [\\d.]+\\): no shells left \\(wave 1 at t -?[\\d.]+, 1 refused\\)$", "the refused shot is logged")
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
	_check_logged(from, "^\\[Play\\] Spawned goose #\\d+ \\(wave 1, seed -?\\d+\\) at t [\\d.]+, fleeing \\(no shells\\)$", "a spawn is logged with its wave and seed")
	_check_logged(from, "^\\[Play\\] Escaped goose #\\d+ \\(4/10, wave 1 at t [\\d.]+\\)$", "an escape is logged with the escaped total")
	_check_logged(from, "^\\[Play\\] Wave 2 start: 3 birds \\((goose|golden), (goose|golden), (goose|golden)\\), 9 shells, speed x1\\.08$", "the next wave start is logged")


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
		var from := _log.size()
		await causes[cause].call()
		await process_frame
		_check_logged(from, "^\\[Play\\] Paused \\(%s\\): wave 1 at t -?[\\d.]+, score 0$" % cause, "%s: the pause is logged with its cause" % cause)
		_check(play.is_paused() and paused and play.pause_log.back() == cause, "%s opens the pause menu with the tree paused" % cause, "menu %s, paused %s, log %s" % [play.is_paused(), paused, play.pause_log])
		_check(resume_button.has_focus(), "%s: Resume is focused" % cause, str(root.gui_get_focus_owner()))
		var age := bird.age
		var clock := play.wave_clock
		for i in 5:
			await process_frame
		_check(bird.age == age and play.wave_clock == clock, "%s: the run is frozen while paused" % cause, "age %.3f -> %.3f" % [age, bird.age])
		await _key(KEY_ENTER)
		_check(not play.is_paused() and not paused, "%s: Resume (Enter) closes the menu and unpauses" % cause, "menu %s, paused %s" % [play.is_paused(), paused])
		_check_logged(from, "^\\[Play\\] Resumed \\(Resume\\): wave 1 at t -?[\\d.]+, score 0$", "%s: the resume is logged with its cause" % cause)
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
	var bird := await _spawn_flying(play, 12)
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	var from := _log.size()
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
	_check(stats.get("escaped") == 10 and stats.get("score") == 100 and stats.get("hits") == 1 and stats.get("kills") == 1 and stats.get("shots") == 1 and stats.get("pigeons") == 0 and stats.get("new_best") == true and stats.get("save_error") == "", "the results get the run's stats", str(stats))
	_check_logged(from, "^\\[Game\\] New Endless best: 100 \\(was 0\\)$", "the new best is logged")
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 1, Endless best 100$", "the save is logged")
	_check_logged(from, "^\\[Play\\] Run end: mode endless, seed 41, wave \\d+, score 100, 1 shots \\(1 hits, 0 misses, 0 pigeons hit\\), 1 birds killed, 0 refused, 10 escaped, best 100 \\(new best\\)$", "the run end is logged with the run's stats")
	var shown := ["Score", "Accuracy", "Hits", "Escaped", "Pigeons", "Best"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
	_check(shown == ["Score 100", "Accuracy 100%", "Birds hit 1", "Birds escaped 10", "Pigeons hit 0", "Endless best 100"], "the results show score, accuracy, hits, escapes, pigeons hit and best", str(shown))
	var last_stat := (results.get_node("Safe/Stats/Best") as Control).get_global_rect()
	_check(last_stat.end.y <= (results.get_node("Safe/NewBest") as Control).get_global_rect().position.y + 0.5, "the stats (now six lines) fit above New best!", str(last_stat))
	_check((results.get_node("Safe/NewBest") as Label).visible and not (results.get_node("Safe/SaveError") as Label).visible, "the results say New best! (and no save problem)", "hidden")
	_check(Results.accuracy_text(0, 0) == Results.NO_VALUE and Results.accuracy_text(3, 4) == "75%", "accuracy is hits / shots, a dash with no shots", Results.accuracy_text(3, 4))
	var again := results.get_node("Safe/PlayAgainButton") as Button
	_check(again.has_focus() and again.get_global_rect().size.y >= MIN_TARGET and _game.safe_rect().encloses(again.get_global_rect()), "Play again is focused, >= 44 high, in the safe area", str(root.gui_get_focus_owner()))
	_game.best_endless = 0
	_game.load_game()
	_check(_game.best_endless == 100, "the new best survives a save and reload", str(_game.best_endless))
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == results.get_node("Safe/TitleButton"), "Tab reaches Title", str(root.gui_get_focus_owner()))
	var gotos := _game.transition_log.size()
	await _key(KEY_ESCAPE)
	await process_frame
	_check(_game.state == GameState.Flow.RESULTS and current_scene == results and _game.transition_log.size() == gotos and not _game.is_transitioning(), "Escape on the results screen starts nothing", "%s, %d new gotos" % [current_scene, _game.transition_log.size() - gotos])
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.PLAY and current_scene is Play, "Play again starts a new run", str(current_scene))
	_game.goto(GameState.Flow.RESULTS, {"score": 40, "shots": 0, "hits": 0, "kills": 0, "pigeons": 0, "escaped": 10, "best": 100, "new_best": false, "save_error": ""})
	await _game.transition_finished
	_check(not (current_scene.get_node("Safe/NewBest") as Label).visible and (current_scene.get_node("Safe/Stats/Accuracy") as Label).text == "Accuracy " + Results.NO_VALUE, "a run below the best shows no New best!, and a dash for no shots", "shown")
	await _tap(current_scene.get_node("Safe/TitleButton") as Control)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE, "Title goes to the title", str(_game.state))
	_clear_tool_save()


## Web save reporting. Headless has no IndexedDB, so the page's answers are fed in:
## browser storage missing at start is reported at once; a check finding that IndexedDB
## did not keep the save is reported (log, error label, save_error, save_failed, the
## results notice); a confirmed check is logged as persisted; an answer to an older
## check is ignored.
func _test_save_web_persist_reporting() -> void:
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	var failed: Array[String] = []
	var record := func(why: String) -> void: failed.append(why)
	_game.save_failed.connect(record)
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	_game.check_storage(false)
	var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(not _game.storage_persistent and "Browser storage (IndexedDB) is unavailable" in reported and error_label.visible and error_label.text == reported, "browser storage missing at start is reported at once", reported)
	_game.check_storage(true)
	_game.goto(GameState.Flow.RESULTS, {"score": 500, "shots": 5, "hits": 5, "kills": 5, "pigeons": 0, "escaped": 10, "best": 500, "new_best": true, "save_error": ""})
	await _game.transition_finished
	var results := current_scene as Results
	var notice := results.get_node("Safe/SaveError") as Label
	_check(not notice.visible, "no save notice before a save fails", notice.text)
	_game.persist_check += 1
	var check := _game.persist_check
	var from := _log.size()
	errors = _game.reported_errors.size()
	_game.persist_checked(check - 1, false, "stale")
	_check(_game.reported_errors.size() == errors and failed.is_empty(), "an answer to an older save check is ignored", str(failed))
	_game.persist_checked(check, true, "12")
	_check_logged(from, "^\\[Game\\] Save persisted to browser storage: user://tool_save\\.json after 12 ms \\(check %d\\)$" % check, "a web save browser storage kept is logged as persisted")
	_check(_game.reported_errors.size() == errors and failed.is_empty() and not notice.visible, "a kept web save reports nothing", str(failed))
	_game.persist_checked(check, false, "QuotaExceededError: the quota has been exceeded")
	reported = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	var reason := "browser storage did not keep it (QuotaExceededError: the quota has been exceeded)"
	_check(failed == [reason] and _game.save_error == reason, "a web save browser storage did not keep fails with its reason", "%s / %s" % [failed, _game.save_error])
	_check("did not keep it: QuotaExceededError" in reported and _game.save_path in reported and error_label.visible and error_label.text == reported, "it is reported in the log and on the error label with the save path", reported)
	_check(notice.visible and notice.text == Results.SAVE_ERROR_TEXT % reason, "the results screen says the best could not be saved", notice.text)
	_game.quiet_errors = false
	_game.save_failed.disconnect(record)
	_game.save_error = ""
	error_label.hide()


## A hit goose stops on its hit frame upright and facing the way it flew, and falls that
## way: the whole basis, not only the rotation (a left-facing transform is rotation + PI
## with scale (1, -1), so zeroing the rotation alone turns it upside down).
func _test_play_hit_frame_keeps_facing() -> void:
	var play := await _start_run(26)
	var goose := Content.bird("goose")
	var seeds: Dictionary[float, int] = {}
	for bird_seed in 64:
		var vx := Flight.velocity(goose, bird_seed, IN_FIELD_AGE, Play.FIELD).x
		var later := Flight.velocity(goose, bird_seed, IN_FIELD_AGE + 0.2, Play.FIELD).x
		if signf(vx) == signf(later) and not seeds.has(signf(vx)):
			seeds[signf(vx)] = bird_seed
	_check(seeds.size() == 2, "seeds for both facings", str(seeds))
	for facing: float in seeds:
		var label := "facing %s" % ("right" if facing > 0.0 else "left")
		var bird := await _spawn_flying(play, seeds[facing])
		var flying_x := Flight.velocity(goose, bird.bird_seed, bird.age, Play.FIELD).x
		await _touch(_global(play, bird.transform * LOCAL_BODY))
		_check(bird.state == Bird.State.HIT and signf(flying_x) == facing, label + ": the goose is hit", "state %d, vx %.1f" % [bird.state, flying_x])
		var hit_y := bird.position.y
		var upright := Transform2D(Vector2(facing, 0.0), Vector2(0.0, 1.0), Vector2.ZERO)
		_check(bird.transform.basis_xform(Vector2.RIGHT).is_equal_approx(upright.x) and bird.transform.basis_xform(Vector2.DOWN).is_equal_approx(upright.y), label + ": the hit frame is upright and keeps its facing", "x %s, y %s" % [bird.transform.x, bird.transform.y])
		for i in roundi(Bird.HIT_HOLD * 60.0) + 10:
			await process_frame
		_check(is_instance_valid(bird) and bird.state == Bird.State.FALLING and bird.position.y > hit_y and bird.transform.x.is_equal_approx(upright.x) and bird.transform.y.is_equal_approx(upright.y), label + ": it falls upright, facing the same way", "x %s, y %s" % [bird.transform.x, bird.transform.y] if is_instance_valid(bird) else "gone")


## The grass hides what is behind it: a shot on the grass (at or below the grass line the
## art is solid from) hits no goose, even inside its hitbox; a shot on the part of a rising
## goose above the grass hits it.
func _test_play_grass_hides_geese() -> void:
	var play := await _start_run(27)
	var grass := play.get_node("World/Grass") as Control
	_check(is_equal_approx(grass.position.y + Play.GRASS_TIP, Play.GRASS_Y), "the grass is drawn solid from the grass line the hit rule uses", "grass top %.1f" % grass.position.y)
	var bird := play.spawn_bird("goose", 3)
	await process_frame
	var under := bird.transform * LOCAL_BODY
	_check(under.y > Play.GRASS_Y and bird.contains(under), "a just-spawned goose's body is behind the grass", str(under))
	await _touch(_global(play, under))
	_check(bird.is_flying() and play.scoring.hits == 0 and play.scoring.misses == 1, "a shot on the grass hits no goose behind it", "hits %d, misses %d" % [play.scoring.hits, play.scoring.misses])
	if not bird.is_flying():
		return
	for i in 120:
		if (bird.transform * LOCAL_HEAD).y < Play.GRASS_Y - 4.0:
			break
		await process_frame
	var head := bird.transform * LOCAL_HEAD
	var body := bird.transform * LOCAL_BODY
	_check(head.y < Play.GRASS_Y and body.y > Play.GRASS_Y, "a rising goose shows its head above the grass, its body still behind it", "head %s, body %s" % [head, body])
	await _touch(_global(play, head))
	_check(not bird.is_flying() and play.scoring.hits == 1, "a shot on the part of a rising goose above the grass hits it", "hits %d" % play.scoring.hits)


## Escape opens the pause menu and Escape on the open menu resumes the run (both logged
## with their cause).
func _test_pause_escape_toggles() -> void:
	var play := await _start_run(38)
	var from := _log.size()
	await _key(KEY_ESCAPE)
	_check(play.is_paused() and paused and play.pause_log.back() == "Escape", "Escape opens the pause menu", "menu %s, paused %s" % [play.is_paused(), paused])
	var clock := play.wave_clock
	await _key(KEY_ESCAPE)
	await process_frame
	_check(not play.is_paused() and not paused and play.wave_clock > clock, "Escape on the open pause menu resumes the run", "menu %s, paused %s" % [play.is_paused(), paused])
	_check_logged(from, "^\\[Play\\] Resumed \\(Escape\\): wave 1 at t -?[\\d.]+, score 0$", "the resume by Escape is logged with its cause")


## The rotate overlay shows during the fade into a run (before the play scene exists); a
## pause opens while the phone is upright; rotating back leaves the menu open with the
## tree paused, and the run clock does not move behind it.
func _test_pause_after_overlay_during_transition_in() -> void:
	await _open_title()
	_game.goto(GameState.Flow.PLAY, {"mode": GameState.ENDLESS_MODE, "seed": 37})
	await process_frame
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown() and paused and _game.is_transitioning() and not (current_scene is Play), "the overlay shows during the fade into a run", "overlay %s, scene %s" % [_game.is_rotate_overlay_shown(), current_scene])
	await _game.transition_finished
	await process_frame
	var play := current_scene as Play
	play.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await process_frame
	_check(play.is_paused() and paused, "a pause opens while the phone is upright", "menu %s, paused %s" % [play.is_paused(), paused])
	root.size = BASE_WINDOW
	await process_frame
	await process_frame
	_check(not _game.is_rotate_overlay_shown() and play.is_paused() and paused, "rotating back keeps the menu open over a paused tree", "menu %s, paused %s" % [play.is_paused(), paused])
	var clock := play.wave_clock
	for i in 5:
		await process_frame
	_check(play.wave_clock == clock, "the run clock does not advance behind the menu", "%.3f -> %.3f" % [clock, play.wave_clock])
	play.resume()


## A new best that cannot be saved (the save path is unwritable) reaches the player on the
## results screen with the reason ("New best!" plus the could-not-be-saved notice) and the
## log, and nothing claims it was saved.
func _test_run_end_save_failure() -> void:
	_clear_tool_save()
	var play := await _start_run(42)
	var bird := await _spawn_flying(play, 12)
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_game.save_path = UNWRITABLE_SAVE_PATH
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var from := _log.size()
	play.escaped = play.mode.escape_limit - 1
	Engine.time_scale = FAST_TIME_SCALE
	for i in 6000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	_game.quiet_errors = false
	_game.save_path = GameState.TOOL_SAVE_PATH
	var results := current_scene as Results
	_check(results != null, "the run ends on the results screen", str(current_scene))
	if results == null:
		return
	var reason: String = _game.flow_args.get("save_error", "")
	_check(_game.flow_args.get("new_best") == true and reason.begins_with("cannot open the save file"), "the results get the new best and why it was not saved", str(_game.flow_args))
	var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(UNWRITABLE_SAVE_PATH in reported, "the save failure is reported with the save path", reported)
	var notice := results.get_node("Safe/SaveError") as Label
	_check((results.get_node("Safe/NewBest") as Label).visible and notice.is_visible_in_tree() and notice.text == Results.SAVE_ERROR_TEXT % reason, "the results say New best! and that it could not be saved, with the reason", "%s '%s'" % [notice.visible, notice.text])
	var below := (results.get_node("Safe/PlayAgainButton") as Control).get_global_rect()
	var above := (results.get_node("Safe/NewBest") as Control).get_global_rect()
	_check(notice.get_global_rect().end.y <= below.position.y + 0.5 and notice.get_global_rect().position.y >= above.end.y - 0.5 and notice.get_visible_line_count() == notice.get_line_count(), "the notice fits between New best! and Play again, every line shown", "%s, %d of %d lines" % [notice.get_global_rect(), notice.get_visible_line_count(), notice.get_line_count()])
	_check_logged(from, "^\\[Play\\] Run end: .* best 100 \\(new best, not saved: cannot open the save file", "the run end log says the new best was not saved")
	_check(_log.since(from).find("[Game] Saved to %s" % UNWRITABLE_SAVE_PATH) == -1 and not Array(_log.since(from)).any(func(l: String) -> bool: return l.begins_with("[Game] Saved to")), "nothing logs the failed save as saved", "a Saved line")
	_game.load_game()
	_check(_game.best_endless == 0, "the unsaved best is not in the save", str(_game.best_endless))
	_game.save_error = ""
	_clear_tool_save()


## Every bird type flies deterministically (same seed and age, same position), seeds
## differ, and rising from below the grass it stays inside the field from entry until it
## flees (10 seeds, every frame, at speed scale 1 and at the cap 1.6).
func _test_flight_every_type_deterministic_and_in_field() -> void:
	for spec in Content.birds():
		var same := true
		for age: float in [0.0, 0.9, 2.5, 5.0, 7.3]:
			same = same and Flight.position(spec, 77, age, Play.FIELD, 1.3) == Flight.position(spec, 77, age, Play.FIELD, 1.3)
		_check(same, "%s: the same seed and age give the same position" % spec.id, "differs")
		var a := Flight.position(spec, 1, 2.0, Play.FIELD)
		var b := Flight.position(spec, 2, 2.0, Play.FIELD)
		_check(a.distance_to(b) > 1.0, "%s: different seeds give different paths" % spec.id, "%s vs %s" % [a, b])
		var problems: Array[String] = []
		for scale: float in [1.0, 1.6]:
			problems.append_array(_field_problems(spec, scale))
		_check(problems.is_empty(), "%s: stays inside the field from entry until it flees" % spec.id, str(problems))


## A zigzag bird reverses its horizontal heading at least once in every window of
## Flight.ZIGZAG_INTERVAL_MAX seconds until it flees (20 seeds), and from the first
## reversal on its path differs from the rise path of the same seed; a goose of the same
## speed holds its heading through such a window.
func _test_flight_zigzag_reverses() -> void:
	var zigzag := Content.bird("zigzag")
	var step := 1.0 / 120.0
	var problems: Array[String] = []
	for bird_seed in 20:
		var last_turn := 0.0
		var last_sign := 0.0
		var age := 0.0
		while age <= zigzag.flee_time:
			var vx := Flight.velocity(zigzag, bird_seed, age, Play.FIELD).x
			if absf(vx) > 1.0:
				if last_sign != 0.0 and signf(vx) == -last_sign:
					last_turn = age
				last_sign = signf(vx)
			if age - last_turn > Flight.ZIGZAG_INTERVAL_MAX + 2.0 * step:
				problems.append("seed %d holds its heading from %.2f to %.2f" % [bird_seed, last_turn, age])
				break
			age += step
	_check(problems.is_empty(), "a zigzag reverses at least once per %.2f s window until it flees" % Flight.ZIGZAG_INTERVAL_MAX, str(problems))
	# The seeded reversals alone: where Flight's signed horizontal travel turns (unlike the
	# velocity, it leaves out the bounces off the field's edges). Every interval between two
	# (from age 0 on) lies in ZIGZAG_INTERVAL_MIN..MAX (within the sampling step), and the
	# first interval differs between seeds.
	var fine := 1.0 / 480.0
	var intervals: Array[float] = []
	var first_intervals: Dictionary[int, bool] = {}
	for bird_seed in 20:
		var turned := 0.0
		var direction := 1.0
		var last := Flight._travel(zigzag, bird_seed, 0.0)
		var age := fine
		while age <= zigzag.flee_time:
			var now := Flight._travel(zigzag, bird_seed, age)
			if signf(now - last) == -direction:
				direction = -direction
				if turned == 0.0:
					first_intervals[roundi(age * 100.0)] = true
				intervals.append(age - turned)
				turned = age
			last = now
			age += fine
	var outside := intervals.filter(func(interval: float) -> bool: return interval < Flight.ZIGZAG_INTERVAL_MIN - 2.0 * fine or interval > Flight.ZIGZAG_INTERVAL_MAX + 2.0 * fine)
	_check(intervals.size() >= 20 * 6 and outside.is_empty(), "every zigzag interval lies in %.2f..%.2f s" % [Flight.ZIGZAG_INTERVAL_MIN, Flight.ZIGZAG_INTERVAL_MAX], "%d intervals, outside: %s" % [intervals.size(), outside])
	_check(first_intervals.size() >= 10, "the zigzag intervals vary between seeds", "%d distinct first intervals over 20 seeds: %s" % [first_intervals.size(), first_intervals.keys()])
	var start := Flight.position(zigzag, 3, 0.0, Play.FIELD)
	var later := Flight.position(zigzag, 3, 2.0, Play.FIELD)
	# The same spec flying the rise pattern (restored below).
	zigzag.pattern = "rise"
	var rise_start := Flight.position(zigzag, 3, 0.0, Play.FIELD)
	var rise_later := Flight.position(zigzag, 3, 2.0, Play.FIELD)
	var held := true
	var first_sign := signf(Flight.velocity(zigzag, 3, 0.1, Play.FIELD).x)
	for i in roundi(Flight.ZIGZAG_INTERVAL_MAX * 120.0):
		held = held and signf(Flight.velocity(zigzag, 3, 0.1 + i * step, Play.FIELD).x) == first_sign
	zigzag.pattern = "zigzag"
	_check(start.is_equal_approx(rise_start) and not later.is_equal_approx(rise_later), "the zigzag starts like a rise and then departs from it", "%s %s vs %s %s" % [start, later, rise_start, rise_later])
	_check(held, "the rise pattern holds its heading through the same window", "turned")


## A launched bird (a splitter's gosling) starts exactly at its launch point; the two split
## headings go up-left and up-right, so the goslings move apart; a launch point near the
## field's edge starts the bird inside the field; launched flights are deterministic.
func _test_flight_launch_and_split_headings() -> void:
	var gosling := Content.bird("gosling")
	var point := Vector2(480, 250)
	var headings := Flight.split_headings(2)
	_check(headings.size() == 2 and headings[0].x < 0.0 and headings[1].x > 0.0 and headings[0].y < 0.0 and headings[1].y < 0.0, "two split headings: up-left and up-right", str(headings))
	var starts: Array[Vector2] = []
	var apart: Array[float] = []
	for t: float in [0.0, 0.25, 0.5]:
		var first := Flight.position(gosling, 11, t, Play.FIELD, 1.0, INF, point, headings[0])
		var second := Flight.position(gosling, 12, t, Play.FIELD, 1.0, INF, point, headings[1])
		if t == 0.0:
			starts = [first, second]
		apart.append(first.distance_to(second))
	_check(starts[0].is_equal_approx(point) and starts[1].is_equal_approx(point), "the goslings start at the hit point", str(starts))
	_check(apart[1] > apart[0] + 40.0 and apart[2] > apart[1] + 40.0, "the goslings diverge", str(apart))
	_check(Flight.position(gosling, 11, 0.7, Play.FIELD, 1.0, INF, point, headings[0]) == Flight.position(gosling, 11, 0.7, Play.FIELD, 1.0, INF, point, headings[0]), "a launched flight is deterministic", "differs")
	var corner := Flight.position(gosling, 11, 0.0, Play.FIELD, 1.0, INF, Vector2(2, 60), headings[0])
	_check(Play.FIELD.grow(0.01).encloses(Rect2(corner - gosling.size / 2.0, gosling.size)), "a launch point at the field's edge starts the bird inside the field", str(corner))
	var problems: Array[String] = []
	for heading in headings:
		for i in roundi(gosling.flee_time * 60.0):
			var at := Flight.position(gosling, 11, i / 60.0, Play.FIELD, 1.6, INF, point, heading)
			if not Play.FIELD.grow(0.01).encloses(Rect2(at - gosling.size / 2.0, gosling.size)):
				problems.append("heading %s leaves the field at %.2f: %s" % [heading, i / 60.0, at])
				break
	_check(problems.is_empty(), "launched goslings stay inside the field until they flee", str(problems))


## Endless unlocks its birds by wave (modes.json): over 100 run seeds the first wave each
## type spawns in is golden 2, armored 3, splitter and decoy 5, zigzag 7; wave 1 is all
## geese; the gosling never spawns from a wave.
func _test_wave_unlocks_by_wave() -> void:
	var endless := Content.mode(GameState.ENDLESS_MODE)
	var first := {}
	for run_seed in 100:
		for index in range(1, 9):
			for spawn in Wave.endless(endless, index, run_seed).spawns:
				first[spawn.bird_id] = mini(first.get(spawn.bird_id, index), index)
	_check(first == {"goose": 1, "golden": 2, "armored": 3, "splitter": 5, "decoy": 5, "zigzag": 7}, "Endless unlocks golden at wave 2, armored 3, splitter and decoy 5, zigzag 7", str(first))
	var unlocked := Wave.unlocked(endless, 4).map(func(entry: ModeSpec.Entry) -> String: return entry.bird)
	_check(unlocked == ["goose", "armored"], "wave 4 draws from the goose and the armored goose", str(unlocked))


## Every spawn slot that is not golden is a pick weighted by modes.json's `weight`s: over
## 2000 run seeds x waves 7-10 (every mix bird unlocked; about 44,000 picks) each type's
## share of those slots is its weight / the total weight within 5 standard deviations of a
## binomial share, 5 x sqrt(p (1 - p) / n) (0.012 for the goose's 10/22 at n = 44,000). A
## uniform pick (0.2 each) misses the goose by 0.25.
func _test_wave_mix_follows_weights() -> void:
	var endless := Content.mode(GameState.ENDLESS_MODE)
	_check(Wave.unlocked(endless, 7).size() == endless.birds.size(), "every mix bird is unlocked from wave 7", str(Wave.unlocked(endless, 7).size()))
	var counts: Dictionary[String, int] = {}
	var picks := 0
	for run_seed in 2000:
		for index in range(7, 11):
			for spawn in Wave.endless(endless, index, run_seed).spawns:
				if spawn.bird_id == endless.golden_bird:
					continue
				counts[spawn.bird_id] = counts.get(spawn.bird_id, 0) + 1
				picks += 1
	var total := 0
	for entry in endless.birds:
		total += entry.weight
	var shares: Array[String] = []
	var off: Array[String] = []
	for entry in endless.birds:
		var expected := float(entry.weight) / total
		var share := float(counts.get(entry.bird, 0)) / picks
		var tolerance := 5.0 * sqrt(expected * (1.0 - expected) / picks)
		shares.append("%s %.4f (weight %d/%d = %.4f, ±%.4f)" % [entry.bird, share, entry.weight, total, expected, tolerance])
		if absf(share - expected) > tolerance:
			off.append(entry.bird)
	_check(off.is_empty() and counts.size() == endless.birds.size(), "each type's share of the slots tracks its weight (%d picks)" % picks, "off: %s; %s" % [off, ", ".join(shares)])


## The golden chance is seeded: the same run seed and wave give the same golden slots;
## no golden bird in wave 1 over 500 run seeds; from wave 2 about golden_chance of the slots
## are golden.
func _test_wave_golden_chance() -> void:
	var endless := Content.mode(GameState.ENDLESS_MODE)
	var in_wave_1 := 0
	var golden := 0
	var slots := 0
	var same := true
	for run_seed in 500:
		for spawn in Wave.endless(endless, 1, run_seed).spawns:
			in_wave_1 += int(spawn.bird_id == endless.golden_bird)
		for index in range(2, 9):
			var plan := Wave.endless(endless, index, run_seed)
			var again := Wave.endless(endless, index, run_seed)
			for i in plan.spawns.size():
				same = same and plan.spawns[i].bird_id == again.spawns[i].bird_id and plan.spawns[i].bird_seed == again.spawns[i].bird_seed
				golden += int(plan.spawns[i].bird_id == endless.golden_bird)
				slots += 1
	_check(same, "golden slots are a pure function of the run seed and wave", "differs")
	_check(in_wave_1 == 0, "no golden bird in wave 1 (500 run seeds)", "%d golden" % in_wave_1)
	var share := float(golden) / slots
	_check(share > endless.golden_chance * 0.8 and share < endless.golden_chance * 1.2, "from wave 2 about golden_chance of the slots are golden", "%.3f of %d slots" % [share, slots])


## A wave's shells cover every hit it needs: hp plus split_count per bird, nothing for the
## decoy, times shells_per_hit (200 run seeds x waves 1-10); waves with armored geese,
## splitters or decoys get other pools than birds x shells_per_hit.
func _test_wave_shells_cover_every_hit() -> void:
	var needed := {}
	for spec in Content.birds():
		needed[spec.id] = Wave.hits_needed(spec)
	_check(needed == {"goose": 1, "armored": 2, "splitter": 3, "gosling": 1, "zigzag": 1, "golden": 1, "decoy": 0}, "hits needed: 1 per goose, 2 per armored, 1 + 2 goslings per splitter, none per decoy", str(needed))
	var endless := Content.mode(GameState.ENDLESS_MODE)
	var problems: Array[String] = []
	var other_pool := 0
	for run_seed in 200:
		for index in range(1, 11):
			var plan := Wave.endless(endless, index, run_seed)
			var hits := 0
			for spawn in plan.spawns:
				var spec := Content.bird(spawn.bird_id)
				hits += 0 if spec.penalty > 0 else spec.hp + spec.split_count
			if plan.shells != hits * endless.shells_per_hit:
				problems.append("seed %d wave %d: %d shells for %d hits" % [run_seed, index, plan.shells, hits])
			other_pool += int(plan.shells != plan.spawns.size() * endless.shells_per_hit)
	_check(problems.is_empty(), "every wave's shells are (sum of hp + split_count over non-decoys) x shells_per_hit", str(problems.slice(0, 5)))
	_check(other_pool > 0, "special birds change the pool from birds x shells_per_hit", "%d waves differ" % other_pool)


## A damaging hit scores nothing and keeps the combo; a decoy hit deducts its penalty,
## never below 0, and resets the combo; decoy hits are shots but not hits.
func _test_scoring_damage_and_penalty() -> void:
	var scoring := Scoring.new(5)
	scoring.hit(100)
	scoring.hit(100)
	scoring.damage()
	_check(scoring.score == 300 and scoring.multiplier == 3 and scoring.hits == 3, "a damaging hit scores nothing and keeps the multiplier", "%d x%d" % [scoring.score, scoring.multiplier])
	_check(scoring.kills == 2, "a damaging hit is a hit but not a kill", "%d kills, %d hits" % [scoring.kills, scoring.hits])
	var deducted := scoring.penalty(200)
	_check(deducted == 200 and scoring.score == 100 and scoring.multiplier == 1 and scoring.penalties == 1, "a decoy hit deducts its penalty and resets the combo", "%d, %d x%d" % [deducted, scoring.score, scoring.multiplier])
	deducted = scoring.penalty(200)
	_check(deducted == 100 and scoring.score == 0, "the penalty never takes the score below 0", "%d, %d" % [deducted, scoring.score])
	_check(scoring.shots() == 5 and scoring.hits == 3, "decoy hits count as shots, not hits", "%d shots" % scoring.shots())


## The armored goose: a dead-on first hit does not kill it, scores nothing and keeps the
## combo (x3 stays x3), shows its damaged frame and a "Clank!" pop-up; the second hit kills
## it for its points x the multiplier and raises it. Both are logged as hit k/hp.
func _test_play_armored_takes_two_hits() -> void:
	_clear_tool_save()
	var play := await _start_run(51)
	for i in 2:
		var goose := await _spawn_flying(play, 60 + i)
		await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.score == 300 and play.scoring.multiplier == 3, "two geese build a x3 combo", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	var armored := await _spawn_flying(play, 70, IN_FIELD_AGE, "armored")
	var from := _log.size()
	var centre := armored.transform * LOCAL_BODY
	_check(armored.contains(centre), "the shot is dead on the armored goose", str(centre))
	await _touch(_global(play, centre))
	_check(armored.is_flying() and armored.hits_taken == 1 and armored.is_damaged(), "a dead-on first hit does not kill the armored goose", "state %d, hits %d" % [armored.state, armored.hits_taken])
	_check(play.scoring.score == 300 and play.scoring.multiplier == 3 and play.scoring.hits == 3, "the first hit scores nothing and keeps the combo", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	var popups := play.get_node("World/Popups").get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	_check((popups.back() as Label).text == Play.DAMAGE_TEXT, "the first hit pops up Clank!", (popups.back() as Label).text)
	_check_logged(from, "^\\[Play\\] Hit armored #%d \\(hit 1/2\\) at \\([\\d.]+, [\\d.]+\\): no points, combo x3 kept, score 300 \\(wave 1 at t -?[\\d.]+, \\d+ shells left\\)$" % armored.number, "the first hit is logged as hit 1/2")
	for i in 12:
		await process_frame
	var sprite := armored.get_node("Sprite") as Sprite2D
	_check(sprite.texture.resource_path in [armored.spec.texture_path("damaged_fly_1"), armored.spec.texture_path("damaged_fly_2")], "the hit armored goose flies on with its damaged frames", sprite.texture.resource_path)
	await _touch(_global(play, armored.transform * LOCAL_BODY))
	_check(not armored.is_flying() and play.scoring.score == 750 and play.scoring.multiplier == 4, "the second hit kills it for 150 x3 and raises the combo", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	_check_logged(from, "^\\[Play\\] Hit armored #%d \\(hit 2/2, killed\\) at \\([\\d.]+, [\\d.]+\\): 150 points x3 = 450, score 750 " % armored.number, "the second hit is logged as hit 2/2, killed")
	_check(sprite.texture.resource_path == armored.spec.texture_path("hit"), "the killed armored goose shows its hit frame", sprite.texture.resource_path)
	_check(play.scoring.hits == 4 and play.scoring.kills == 3, "two geese and the armored goose: 4 hits, 3 birds killed", "%d hits, %d kills" % [play.scoring.hits, play.scoring.kills])
	# The run's end: the armored goose is one bird hit, its two hits two accurate shots.
	play.escaped = play.mode.escape_limit - 1
	Engine.time_scale = FAST_TIME_SCALE
	for i in 6000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	_check(results != null and _game.flow_args.get("kills") == 3 and _game.flow_args.get("hits") == 4 and _game.flow_args.get("shots") == 4, "the run passes 3 birds killed of 4 hits to the results", str(_game.flow_args))
	if results != null:
		var shown := ["Hits", "Accuracy"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
		_check(shown == ["Birds hit 3", "Accuracy 100%"], "the results count the armored goose once in Birds hit, and both its hits in the accuracy", str(shown))
	_check_logged(from, "^\\[Play\\] Run end: .* 4 shots \\(4 hits, 0 misses, 0 pigeons hit\\), 3 birds killed, ", "the run end logs the birds killed")
	_check_logged(from, "^\\[Results\\] Score 750, accuracy 100% \\(4 of 4 shots\\), 3 birds hit, ", "the results log the birds hit (killed)")
	_clear_tool_save()


## The splitter: a hit scores its points x the multiplier, then 2 goslings fly from the hit
## point on diverging headings while the splitter falls (it never escapes); each gosling
## scores its own points; a gosling that gets away counts as an escape.
func _test_play_splitter_splits_into_goslings() -> void:
	var play := await _start_run(52)
	var splitter := await _spawn_flying(play, 80, IN_FIELD_AGE, "splitter")
	var from := _log.size()
	var point := splitter.transform * LOCAL_BODY
	_check(splitter.contains(point), "the shot is on the splitter", str(point))
	await _touch(_global(play, point))
	_check(play.scoring.score == 120 and play.scoring.multiplier == 2 and not splitter.is_flying(), "a hit on the splitter scores 120 x1", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	var goslings := play.flying_birds().filter(func(bird: Bird) -> bool: return bird.spec.id == "gosling")
	_check(goslings.size() == 2, "the splitter splits into 2 goslings", str(goslings.size()))
	if goslings.size() != 2:
		return
	var first := goslings[0] as Bird
	var second := goslings[1] as Bird
	_check(first.launch_from.distance_to(point) < 4.0 and second.launch_from.distance_to(point) < 4.0 and first.position.distance_to(point) < 12.0 and second.position.distance_to(point) < 12.0, "the goslings start at the hit point", "%s %s from %s" % [first.position, second.position, point])
	_check_logged(from, "^\\[Play\\] Hit splitter #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): 120 points x1 = 120, score 120 " % splitter.number, "the splitter's hit is logged")
	_check_logged(from, "^\\[Play\\] Split splitter #%d at \\([\\d.]+, [\\d.]+\\) into 2 gosling: #%d seed -?\\d+ heading \\(-0\\.77, -0\\.64\\), #%d seed -?\\d+ heading \\(0\\.77, -0\\.64\\) \\(wave 1 at t -?[\\d.]+\\)$" % [splitter.number, first.number, second.number], "the split is logged with the goslings' numbers, seeds and headings")
	var gap := first.position.distance_to(second.position)
	for i in 15:
		await process_frame
	_check(first.position.distance_to(second.position) > gap + 60.0, "the goslings fly apart", "%.1f -> %.1f" % [gap, first.position.distance_to(second.position)])
	first.set_process(false)
	var on_first := first.transform * LOCAL_BODY
	_check(first.contains(on_first), "the shot is on a gosling", str(on_first))
	await _touch(_global(play, on_first))
	_check(not first.is_flying() and play.scoring.score == 240, "a gosling scores its own points (60 x2)", str(play.scoring.score))
	_check_logged(from, "^\\[Play\\] Hit gosling #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): 60 points x2 = 120, score 240 " % first.number, "the gosling's hit is logged")
	var number := second.number
	var counted := await _escape_counts(play, second)
	_check(counted[1] == counted[0] + 1, "a gosling that gets away counts as an escape", "escaped %d before, %d after" % [counted[0], counted[1]])
	_check_logged(from, "^\\[Play\\] Escaped gosling #%d \\(%d/10, wave \\d+ at t [\\d.]+\\)$" % [number, counted[1]], "the gosling's escape is logged with the escaped total")
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Escaped splitter")), "the split splitter never escapes", "an escape line")


## A splitter killed with the wave's last shell: its goslings launch already fleeing (no
## shells are left to shoot them with), and the split log says so. The out-of-shells sweep
## after that shot also makes every flying bird flee, so a gosling launched while the pool
## is already empty is checked on its own: spawn_bird itself must make it flee.
func _test_play_split_with_last_shell() -> void:
	var play := await _start_run(55)
	var splitter := await _spawn_flying(play, 82, IN_FIELD_AGE, "splitter")
	play.ammo.shells = 1
	var from := _log.size()
	await _touch(_global(play, splitter.transform * LOCAL_BODY))
	var goslings := play.flying_birds().filter(func(bird: Bird) -> bool: return bird.spec.id == "gosling")
	_check(play.ammo.is_empty() and not splitter.is_flying() and goslings.size() == 2, "the last shell kills the splitter and launches 2 goslings", "%d shells, %d goslings" % [play.ammo.shells, goslings.size()])
	_check(goslings.size() == 2 and goslings.all(func(bird: Bird) -> bool: return bird.flee_at == 0.0), "goslings launched by the last shell flee at once", str(goslings.map(func(bird: Bird) -> float: return bird.flee_at)))
	_check_logged(from, "^\\[Play\\] Split splitter #%d at \\([\\d.]+, [\\d.]+\\) into 2 gosling: .* \\(wave 1 at t -?[\\d.]+\\), fleeing \\(no shells\\)$" % splitter.number, "the split log says the goslings flee (no shells)")
	var late := play.spawn_bird("gosling", 83, Vector2(480, 250), Flight.split_headings(2)[0])
	_check(late.flee_at == 0.0, "a gosling launched with no shells left flees from the start", "flee_at %.2f" % late.flee_at)


## The golden goose: a hit scores its 500 points x the multiplier; one that gets away
## counts as an escape.
func _test_play_golden_scores_and_escapes() -> void:
	var play := await _start_run(53)
	var golden := await _spawn_flying(play, 90, IN_FIELD_AGE, "golden")
	var from := _log.size()
	await _touch(_global(play, golden.transform * LOCAL_BODY))
	_check(not golden.is_flying() and play.scoring.score == 500, "a hit on the golden goose scores 500 x1", str(play.scoring.score))
	_check_logged(from, "^\\[Play\\] Hit golden #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): 500 points x1 = 500, score 500 " % golden.number, "the golden hit is logged")
	var runaway := play.spawn_bird("golden", 91)
	var number := runaway.number
	var counted := await _escape_counts(play, runaway)
	_check(counted[1] == counted[0] + 1, "a golden goose that gets away counts as an escape", "escaped %d before, %d after" % [counted[0], counted[1]])
	_check_logged(from, "^\\[Play\\] Escaped golden #%d \\(%d/10, wave \\d+ at t [\\d.]+\\)$" % [number, counted[1]], "the golden goose's escape is logged with the escaped total")


## The decoy (the rival's pigeon): a hit deducts its penalty, never below 0, resets the
## combo, pops up a negative score and is logged; its escape never counts; the results
## show "Pigeons hit N".
func _test_play_decoy_penalty() -> void:
	_clear_tool_save()
	var play := await _start_run(54)
	var from := _log.size()
	var pigeon := await _spawn_flying(play, 95, IN_FIELD_AGE, "decoy")
	_check(pigeon.contains(pigeon.transform * LOCAL_BODY), "the shot is on the pigeon", "outside")
	await _touch(_global(play, pigeon.transform * LOCAL_BODY))
	_check(not pigeon.is_flying() and play.scoring.score == 0 and play.scoring.penalties == 1, "a pigeon hit at score 0 leaves the score at 0", "%d, %d pigeons" % [play.scoring.score, play.scoring.penalties])
	_check_logged(from, "^\\[Play\\] Hit decoy #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): penalty 200, -0, combo reset, score 0 \\(1 pigeons hit, wave 1 at t -?[\\d.]+, \\d+ shells left\\)$" % pigeon.number, "the penalty is logged at the floor")
	for i in 2:
		var goose := await _spawn_flying(play, 100 + i)
		await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.score == 300 and play.scoring.multiplier == 3, "two geese score 300 and build x3", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	var second := await _spawn_flying(play, 96, IN_FIELD_AGE, "decoy")
	await _touch(_global(play, second.transform * LOCAL_BODY))
	_check(play.scoring.score == 100 and play.scoring.multiplier == 1 and play.scoring.penalties == 2, "a pigeon hit deducts 200 and resets the combo", "%d x%d" % [play.scoring.score, play.scoring.multiplier])
	var popups := play.get_node("World/Popups").get_children().filter(func(n: Node) -> bool: return not n.is_queued_for_deletion())
	var popup := popups.back() as Label
	_check(popup.text == "-200" and popup.get_theme_color(&"font_color") == Play.PENALTY_COLOR, "the pigeon hit shows a negative pop-up", popup.text)
	_check_logged(from, "^\\[Play\\] Hit decoy #%d \\(hit 1/1, killed\\) at \\([\\d.]+, [\\d.]+\\): penalty 200, -200, combo reset, score 100 \\(2 pigeons hit, " % second.number, "the penalty is logged")
	var runaway := play.spawn_bird("decoy", 97)
	var number := runaway.number
	var counted := await _escape_counts(play, runaway)
	_check(counted[1] >= 0 and counted[1] == counted[0], "a pigeon that gets away is not counted as an escape", "escaped %d before, %d after" % [counted[0], counted[1]])
	_check_logged(from, "^\\[Play\\] Escaped decoy #%d \\(not counted, \\d+/10, wave \\d+ at t [\\d.]+\\)$" % number, "the pigeon's escape is logged as not counted")
	play.escaped = play.mode.escape_limit - 1
	Engine.time_scale = FAST_TIME_SCALE
	for i in 6000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	_check(results != null and _game.flow_args.get("pigeons") == 2, "the run passes the pigeons hit to the results", str(_game.flow_args))
	if results != null:
		_check((results.get_node("Safe/Stats/Pigeons") as Label).text == "Pigeons hit 2", "the results show Pigeons hit 2", (results.get_node("Safe/Stats/Pigeons") as Label).text)
		_check((results.get_node("Safe/Stats/Accuracy") as Label).text == "Accuracy 50%", "pigeon hits are shots but not hits (2 of 4)", (results.get_node("Safe/Stats/Accuracy") as Label).text)
	_check_logged(from, "^\\[Play\\] Run end: .* \\(2 hits, 0 misses, 2 pigeons hit\\)", "the run end logs the pigeons hit")
	_clear_tool_save()


## Problems with `spec`'s rising flight at `speed_scale` for 10 seeds: not entering the
## field by half its flee_time, or leaving it (by a frame) once inside before it flees.
func _field_problems(spec: BirdSpec, speed_scale: float) -> Array[String]:
	var problems: Array[String] = []
	for bird_seed in 10:
		var entered := -1.0
		var age := 0.0
		while age <= spec.flee_time:
			var bounds := Rect2(Flight.position(spec, bird_seed, age, Play.FIELD, speed_scale) - spec.size / 2.0, spec.size)
			var inside := Play.FIELD.grow(0.01).encloses(bounds)
			if entered < 0.0 and inside:
				entered = age
			elif entered >= 0.0 and not inside:
				problems.append("seed %d x%.1f leaves the field at age %.2f: %s" % [bird_seed, speed_scale, age, bounds])
				break
			age += 1.0 / 60.0
		if entered < 0.0 or entered > spec.flee_time / 2.0:
			problems.append("seed %d x%.1f enters the field at %.2f" % [bird_seed, speed_scale, entered])
	return problems


## Lets `bird` fly (at FAST_TIME_SCALE) until it escapes; returns [play.escaped at the start
## of the frame it escaped in, play.escaped once Play has handled its escape] ([x, -1] if
## it never escaped). Play's handler was connected at spawn, so it runs before this one.
func _escape_counts(play: Play, bird: Bird) -> Array[int]:
	var counted: Array[int] = [-1, -1]
	bird.escaped.connect(func(_b: Bird) -> void: counted[1] = play.escaped)
	Engine.time_scale = FAST_TIME_SCALE
	for i in 900:
		if not is_instance_valid(bird):
			break
		counted[0] = play.escaped
		await process_frame
	Engine.time_scale = 1.0
	return counted


## Starts an Endless run with `run_seed` and waits until it is on screen.
func _start_run(run_seed: int) -> Play:
	_game.goto(GameState.Flow.PLAY, {"mode": GameState.ENDLESS_MODE, "seed": run_seed})
	await _game.transition_finished
	await process_frame
	return current_scene as Play


## Spawns a bird (a goose unless `bird_id` says otherwise) with `bird_seed` already `age`
## seconds into its flight (inside the field, above the grass) and waits a frame so it is
## placed there.
func _spawn_flying(play: Play, bird_seed: int, age := IN_FIELD_AGE, bird_id := "goose") -> Bird:
	var bird := play.spawn_bird(bird_id, bird_seed)
	bird.age = age
	await process_frame
	return bird


## Every Control under `control` (itself included) that takes touches or focus.
func _interactive_controls(control: Control) -> Array[Control]:
	var found: Array[Control] = []
	if control is BaseButton or control.mouse_filter != Control.MOUSE_FILTER_IGNORE or control.focus_mode != Control.FOCUS_NONE:
		found.append(control)
	for child in control.get_children():
		if child is Control:
			found.append_array(_interactive_controls(child as Control))
	return found


## The WCAG contrast ratio of two sRGB colours.
func _contrast(a: Color, b: Color) -> float:
	var la := a.srgb_to_linear().get_luminance()
	var lb := b.srgb_to_linear().get_luminance()
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Checks that a line printed since log index `from` matches the RegEx `pattern`.
func _check_logged(from: int, pattern: String, test_name: String) -> void:
	var regex := RegEx.create_from_string(pattern)
	var lines := _log.since(from)
	_check(Array(lines).any(func(line: String) -> bool: return regex.search(line) != null), test_name, "no line matches %s in %d lines logged since" % [pattern, lines.size()])


## The canvas position of `point` in the play scene's World.
func _global(play: Play, point: Vector2) -> Vector2:
	return (play.get_node("World") as Node2D).to_global(point)


func _text(play: Play, stat: String) -> String:
	return (play.get_node("Hud/Bar/Stats/" + stat) as Label).text


## The shell icons shown (the Count label beside them is not one).
func _shell_icons(play: Play) -> int:
	return play.get_node("Hud/Bar/Stats/Shells").get_children().filter(func(icon: Node) -> bool: return icon is TextureRect and (icon as CanvasItem).visible).size()


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
