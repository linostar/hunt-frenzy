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
const CHAPTER_SELECT_PATH := "res://scenes/chapter_select.tscn"
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
## A 19.5:9 phone in landscape whose safe area also leaves out the iOS home indicator at
## the bottom, and the smallest safe height the results screen must fit.
const RESULTS_INSET_SAFE_RECT := Rect2(66, 0, 1104, 511)
const RESULTS_MIN_SAFE_HEIGHT := 470
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
## One frame at --fixed-fps 60.
const FRAME := 1.0 / 60.0

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
		_test_title_shows_mode_bests,
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
		_test_wave_time_attack_schedule,
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
		_test_rival_rules,
		_test_rival_cue_and_steal,
		_test_rival_kill_during_cue,
		_test_rival_damage_keeps_cue,
		_test_rival_steal_ends_run,
		_test_rival_decoy_and_fleeing,
		_test_rival_pause_freezes_cue,
		_test_rival_steals_off,
		_test_rival_heckle_cooldown,
		_test_rival_layout_and_pass_through,
		_test_pause_causes_and_resume,
		_test_pause_menu_keyboard,
		_test_pause_touches_are_not_shots,
		_test_pause_escape_toggles,
		_test_pause_after_rotating,
		_test_pause_after_overlay_during_transition_in,
		_test_pause_restart_and_quit,
		_test_run_ends_on_results,
		_test_run_end_save_failure,
		_test_time_attack_start_and_hud,
		_test_time_attack_clock_ends_exactly,
		_test_time_attack_pause_freezes_clock,
		_test_time_attack_waves_on_clear,
		_test_time_attack_lost_wave_starts_next_at_once,
		_test_time_attack_lost_wave_counts_skipped_as_escaped,
		_test_time_attack_leftover_overlaps_next_wave,
		_test_endless_empty_pool_waits_for_the_wave,
		_test_time_attack_no_steals_no_cue,
		_test_time_attack_results,
		_test_time_attack_quit_saves_nothing,
		_test_time_attack_save_failure,
		_test_campaign_wave_schedule,
		_test_campaign_stars_unlocks_and_best,
		_test_campaign_record_level,
		_test_save_v1_migrates_to_v3,
		_test_save_v2_migrates_to_v3,
		_test_save_settings_and_bad_entries,
		_test_campaign_level_plays_all_waves,
		_test_campaign_pass_next_retry_levels,
		_test_campaign_save_failure,
		_test_campaign_unknown_level,
		_test_campaign_rival_linger_scale,
		_test_results_verdict,
		_test_chapter_select,
		_test_level_select,
		_test_save_dropped_backup_failure,
		_test_select_focus_returns,
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


## The title's Campaign, Endless and Time Attack buttons: in a row, at least 44x44, their
## text inside them, inside the safe area, with a visible focus style, at 16:9, 19.5:9 and
## 4:3; Campaign is focused on arrival (no ring), Tab and right move Campaign -> Endless ->
## Time Attack -> Campaign, left goes the other way.
func _test_title_button_layout() -> void:
	await _open_title()
	var title := current_scene as Title
	var buttons := _title_buttons(title)
	var campaign := buttons[0]
	_check(campaign.has_focus(), "title focuses Campaign on arrival", str(root.gui_get_focus_owner()))
	for button: Button in buttons:
		var focus_style := button.get_theme_stylebox(&"focus")
		_check(focus_style != null and not (focus_style is StyleBoxEmpty), "%s has a visible focus style" % button.name, str(focus_style))
		_check(button.focus_mode == Control.FOCUS_ALL, "%s takes keyboard focus" % button.name, str(button.focus_mode))
	var names := buttons.map(func(button: Button) -> String: return button.text.get_slice("\n", 0))
	_check(names == ["Campaign", "Endless", "Time Attack"], "the title offers Campaign, Endless and Time Attack", str(names))
	_check(not campaign.has_focus(true), "the focus ring is hidden on arrival (no stray ring on phones)", "focus visible")
	for key: Key in [KEY_TAB, KEY_RIGHT, KEY_LEFT]:
		var order: Array[Button] = []
		order.assign([buttons[1], buttons[2], buttons[0]] if key != KEY_LEFT else [buttons[2], buttons[1], buttons[0]])
		var reached: Array[String] = []
		for i in order.size():
			await _key(key)
			reached.append(str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else "none")
		_check(reached == order.map(func(button: Button) -> String: return str(button.name)) and campaign.has_focus(true), "%s cycles the focus through the three buttons, the ring shown" % OS.get_keycode_string(key), str(reached))
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		for button: Button in buttons:
			var label := "%dx%d %s" % [window.x, window.y, button.name]
			var rect := button.get_global_rect()
			_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET and button.get_combined_minimum_size().x <= rect.size.x + 0.5 and button.get_combined_minimum_size().y <= rect.size.y + 0.5, label + " size, its text inside", "%s, text needs %s" % [rect.size, button.get_combined_minimum_size()])
			_check(_game.safe_rect().encloses(rect), label + " inside safe area", "%s not in %s" % [rect, _game.safe_rect()])
		var rects := buttons.map(func(button: Button) -> Rect2: return button.get_global_rect())
		_check(is_equal_approx(rects[0].get_center().y, rects[1].get_center().y) and is_equal_approx(rects[1].get_center().y, rects[2].get_center().y) and rects[0].end.x < rects[1].position.x and rects[1].end.x < rects[2].position.x,
			"%dx%d Campaign, Endless and Time Attack sit in a row" % [window.x, window.y], str(rects))
	root.size = BASE_WINDOW
	await process_frame


## The Endless and Time Attack buttons show that mode's best score from the save.
func _test_title_shows_mode_bests() -> void:
	_clear_tool_save()
	_game.bests[GameState.ENDLESS_MODE] = 1234
	_game.bests[GameState.TIME_ATTACK_MODE] = 5678
	var from := _log.size()
	await _open_title()
	var buttons := _title_buttons(current_scene as Title)
	_check(buttons[1].text == "Endless\nBest 1234" and buttons[2].text == "Time Attack\nBest 5678" and buttons[0].text == "Campaign", "the Endless and Time Attack buttons show their mode's best", "%s | %s" % [buttons[1].text, buttons[2].text])
	_check_logged(from, "^\\[Title\\] Bests: Endless 1234, Time Attack 5678$", "the bests the title shows are logged")
	_clear_tool_save()
	await _open_title()
	buttons = _title_buttons(current_scene as Title)
	_check(buttons[1].text == "Endless\nBest 0" and buttons[2].text == "Time Attack\nBest 0", "with no best yet the buttons say Best 0", "%s | %s" % [buttons[1].text, buttons[2].text])


## With a notch narrowing the safe area, the title lays out in the safe rect, not the
## visible rect, and Play stays clear of the notch.
func _test_title_follows_notched_safe_area() -> void:
	await _open_title()
	var title := current_scene as Title
	var safe := title.get_node("Safe") as Control
	var buttons := _title_buttons(title)
	_game.safe_area_override = NOTCHED_SAFE_RECT
	root.size = LANDSCAPE_19_5_9
	await process_frame
	await process_frame
	_check(_game.safe_rect() == NOTCHED_SAFE_RECT and _game.safe_rect() != _game.visible_rect(), "the notch narrows the safe rect", "safe %s, visible %s" % [_game.safe_rect(), _game.visible_rect()])
	_check(safe.get_global_rect().is_equal_approx(NOTCHED_SAFE_RECT), "the title lays out in the safe rect", str(safe.get_global_rect()))
	_check(buttons.all(func(button: Button) -> bool: return NOTCHED_SAFE_RECT.encloses(button.get_global_rect())), "Campaign, Endless and Time Attack are clear of the notch", str(buttons.map(func(button: Button) -> Rect2: return button.get_global_rect())))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## A real touch on Endless starts an Endless run (through goto, with a seed), each with a
## fresh seed; a touch on Time Attack starts a Time Attack run; Enter on the focused
## Campaign opens the chapter select.
func _test_title_button_tap_and_enter() -> void:
	await _open_title()
	var title := current_scene as Title
	await _tap(title.get_node("Safe/EndlessButton") as Control)
	_check(title.endless_presses == 1 and title.campaign_presses == 0, "a tap presses Endless", "%d presses" % title.endless_presses)
	_check(_game.is_transitioning() and _game.transition_log.back().begins_with("TITLE -> PLAY (%s)" % PLAY_PATH), "Endless goes to the play scene through goto", str(_game.transition_log.back()))
	await _game.transition_finished
	_check(_game.state == GameState.Flow.PLAY and current_scene is Play, "Endless starts a run", "%s %s" % [_game.state, current_scene])
	_check(_game.flow_args.get("mode") == GameState.ENDLESS_MODE and _game.flow_args.get("seed") is int, "the run is Endless with a seed", str(_game.flow_args))
	var first_seed: int = _game.flow_args["seed"]
	await _open_title()
	title = current_scene as Title
	await _tap(title.get_node("Safe/EndlessButton") as Control)
	await _game.transition_finished
	_check(current_scene is Play and _game.flow_args.get("seed") != first_seed, "each run gets a fresh seed", "seeds %d and %s" % [first_seed, _game.flow_args.get("seed")])
	await _open_title()
	title = current_scene as Title
	var from := _log.size()
	await _tap(title.get_node("Safe/TimeAttackButton") as Control)
	_check(title.time_attack_presses == 1 and title.endless_presses == 0 and title.campaign_presses == 0, "a tap presses Time Attack", "%d presses" % title.time_attack_presses)
	_check_logged(from, "^\\[Title\\] Time Attack pressed \\(1\\); starting Time Attack$", "the Time Attack press is logged")
	if _game.is_transitioning():
		await _game.transition_finished
	_check(current_scene is Play and (current_scene as Play).is_timed() and _game.flow_args.get("mode") == GameState.TIME_ATTACK_MODE and _game.flow_args.get("seed") is int and _game.flow_args.get("seed") != first_seed, "Time Attack starts a timed run with a fresh seed", str(_game.flow_args))
	await _open_title()
	title = current_scene as Title
	await _key(KEY_ENTER)
	_check(title.campaign_presses == 1 and title.endless_presses == 0, "Enter presses the focused Campaign", "%d presses" % title.campaign_presses)
	_check(_game.transition_log.back().begins_with("TITLE -> CHAPTER_SELECT (%s)" % CHAPTER_SELECT_PATH), "Campaign opens the chapter select through goto", str(_game.transition_log.back()))
	await _game.transition_finished
	_check(_game.state == GameState.Flow.CHAPTER_SELECT and current_scene is ChapterSelect, "Campaign shows the chapter select", "%s %s" % [_game.state, current_scene])


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


## Under the rotate overlay neither a tap where Campaign is nor Enter presses it.
func _test_rotate_overlay_blocks_input() -> void:
	await _open_title()
	var title := current_scene as Title
	var button := title.get_node("Safe/CampaignButton") as Button
	button.grab_focus()
	root.size = PORTRAIT_9_19_5
	await process_frame
	await process_frame
	await _tap(button)
	await _key(KEY_ENTER)
	_check(title.campaign_presses == 0, "the rotate overlay blocks taps and keys", "%d presses" % title.campaign_presses)
	root.size = BASE_WINDOW
	await process_frame
	await _key(KEY_ENTER)
	_check(title.campaign_presses == 1, "Campaign works again after rotating back", "%d presses" % title.campaign_presses)
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


## With content errors the title shows the banner and Campaign and Endless are disabled;
## with clean data the banner is hidden and both work.
func _test_title_content_error_banner() -> void:
	Content.quiet_errors = true
	Content.load_texts({"birds.json": "[]"})
	var problems := Content.errors().size()
	await _open_title()
	var title := current_scene as Title
	var banner := title.get_node("Safe/ContentErrorBanner") as Label
	var buttons := _title_buttons(title)
	_check(banner.visible and banner.text == Title.CONTENT_ERROR_MESSAGE % problems, "content errors show the banner", "%s '%s'" % [banner.visible, banner.text])
	_check(buttons.all(func(button: Button) -> bool: return button.disabled), "content errors disable Campaign, Endless and Time Attack", "enabled")
	for button in buttons:
		await _tap(button)
	_check(title.campaign_presses == 0 and title.endless_presses == 0 and title.time_attack_presses == 0 and not _game.is_transitioning(), "a disabled Campaign, Endless or Time Attack starts nothing", "%d, %d, %d presses" % [title.campaign_presses, title.endless_presses, title.time_attack_presses])
	Content.quiet_errors = false
	Content.reload()
	await _open_title()
	title = current_scene as Title
	_check(not (title.get_node("Safe/ContentErrorBanner") as Label).visible and not _title_buttons(title).any(func(button: Button) -> bool: return button.disabled), "clean content: no banner, Campaign, Endless and Time Attack enabled", "banner or disabled")


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
	var a := Wave.for_mode(endless, 3, 42)
	var b := Wave.for_mode(endless, 3, 42)
	var same := a.shells == b.shells and a.spawns.size() == b.spawns.size() and is_equal_approx(a.speed_scale, b.speed_scale)
	for i in mini(a.spawns.size(), b.spawns.size()):
		same = same and a.spawns[i].bird_id == b.spawns[i].bird_id and a.spawns[i].time == b.spawns[i].time and a.spawns[i].bird_seed == b.spawns[i].bird_seed
	_check(same, "a wave is a pure function of mode, index and run seed", "differs")
	var other := Wave.for_mode(endless, 3, 43)
	_check(other.spawns[0].bird_seed != a.spawns[0].bird_seed, "another run seed gives other bird seeds", str(other.spawns[0].bird_seed))
	var counts := []
	for index: int in [1, 2, 3, 5, 20]:
		counts.append(Wave.for_mode(endless, index, 42).spawns.size())
	_check(counts == [2, 3, 4, 6, 8], "birds start at start_birds and grow by bird_growth up to max_birds", str(counts))
	_check(is_equal_approx(Wave.for_mode(endless, 1, 42).speed_scale, 1.0) and is_equal_approx(Wave.for_mode(endless, 2, 42).speed_scale, 1.0 + endless.speed_growth), "the speed scale grows per wave", "%.2f" % Wave.for_mode(endless, 2, 42).speed_scale)
	_check(is_equal_approx(Wave.for_mode(endless, 50, 42).speed_scale, endless.speed_cap), "the speed scale stops at its cap", "%.2f" % Wave.for_mode(endless, 50, 42).speed_scale)
	var timed := true
	for i in a.spawns.size():
		timed = timed and is_equal_approx(a.spawns[i].time, i * endless.spawn_interval)
	_check(timed, "spawns come every spawn_interval from 0", str(a.spawns.map(func(spawn: Wave.Spawn) -> float: return spawn.time)))


## Time Attack's waves (Wave.for_mode with its own modes.json numbers): a pure function of
## the mode, the wave index and the run seed (every wave a fresh full pool of shells for
## its birds' hits), growing from start_birds by bird_growth up to max_birds, its speed up
## to speed_cap, a spawn every spawn_interval; not Endless's schedule for the same seed.
func _test_wave_time_attack_schedule() -> void:
	var time_attack := Content.mode(GameState.TIME_ATTACK_MODE)
	var same := true
	for index in range(1, 13):
		same = same and _same_plan(Wave.for_mode(time_attack, index, 42), Wave.for_mode(time_attack, index, 42))
	_check(same, "Time Attack: the same mode, wave and seed give the same spawns, shells and speed", "differs")
	_check(Wave.for_mode(time_attack, 3, 43).spawns[0].bird_seed != Wave.for_mode(time_attack, 3, 42).spawns[0].bird_seed, "Time Attack: another run seed gives other bird seeds", "same")
	var counts := []
	for index: int in [1, 2, 3, 6, 20]:
		counts.append(Wave.for_mode(time_attack, index, 42).spawns.size())
	_check(counts == [3, 4, 5, 8, 8], "Time Attack: 3 birds in wave 1, one more per wave up to 8", str(counts))
	var speeds := [1, 2, 50].map(func(index: int) -> float: return Wave.for_mode(time_attack, index, 42).speed_scale)
	_check(is_equal_approx(speeds[0], 1.0) and is_equal_approx(speeds[1], 1.06) and is_equal_approx(speeds[2], 1.5), "Time Attack: speed x1, then +0.06 per wave up to x1.5", str(speeds))
	var plan := Wave.for_mode(time_attack, 5, 42)
	var hits := 0
	var timed := true
	for i in plan.spawns.size():
		hits += Wave.hits_needed(Content.bird(plan.spawns[i].bird_id))
		timed = timed and is_equal_approx(plan.spawns[i].time, i * 0.9)
	_check(plan.shells == Ammo.pool_size(hits, 2) and timed, "Time Attack: a full pool of 2 shells per hit needed, a spawn every 0.9 s", "%d shells for %d hits" % [plan.shells, hits])
	_check(not _same_plan(plan, Wave.for_mode(Content.mode(GameState.ENDLESS_MODE), 5, 42)), "Time Attack's waves are its own, not Endless's", "same plan")


## Whether two wave plans are the same: index, shells, speed and every spawn.
func _same_plan(a: Wave.Plan, b: Wave.Plan) -> bool:
	var same := a.index == b.index and a.shells == b.shells and a.spawns.size() == b.spawns.size() and a.speed_scale == b.speed_scale
	for i in mini(a.spawns.size(), b.spawns.size()):
		same = same and a.spawns[i].bird_id == b.spawns[i].bird_id and a.spawns[i].time == b.spawns[i].time and a.spawns[i].bird_seed == b.spawns[i].bird_seed
	return same


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
	_game.bests[GameState.ENDLESS_MODE] = 1234
	_game.bests[GameState.TIME_ATTACK_MODE] = 5678
	_game.save_game()
	_game.bests[GameState.ENDLESS_MODE] = 0
	_game.bests[GameState.TIME_ATTACK_MODE] = 0
	_game.load_game()
	_check(_game.best(GameState.ENDLESS_MODE) == 1234 and _game.best(GameState.TIME_ATTACK_MODE) == 5678, "each mode's best survives a save and reload", str(_game.bests))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 3.0 and GameState.SAVE_VERSION == 3 and saved.get("bests") == {"endless": 1234.0, "time_attack": 5678.0} and not saved.has("best_endless"), "the save is version 3 with a best per mode", str(saved))
	var endless := Content.mode(GameState.ENDLESS_MODE)
	var time_attack := Content.mode(GameState.TIME_ATTACK_MODE)
	_check(not _game.record_best(endless, 1000) and _game.best(GameState.ENDLESS_MODE) == 1234, "a lower score is not a best", str(_game.bests))
	_check(_game.record_best(endless, 2000) and _game.best(GameState.TIME_ATTACK_MODE) == 5678, "a higher score is a new best of its own mode only", str(_game.bests))
	_check(not _game.record_best(time_attack, 5678) and _game.record_best(time_attack, 6000) and _game.best(GameState.ENDLESS_MODE) == 2000, "Time Attack keeps its own best (a tie is no new best)", str(_game.bests))
	_game.bests[GameState.ENDLESS_MODE] = 0
	_game.bests[GameState.TIME_ATTACK_MODE] = 0
	_game.load_game()
	_check(_game.best(GameState.ENDLESS_MODE) == 2000 and _game.best(GameState.TIME_ATTACK_MODE) == 6000, "a new best is saved at once", str(_game.bests))
	_clear_tool_save()


## A corrupt, unknown-version or malformed save is backed up, reported in the log and on
## the error label, and the game starts fresh with a fresh save.
func _test_save_corrupt_and_unknown_version() -> void:
	var cases := {
		"{not json": "corrupt (line",
		JSON.stringify({"version": 4, "best_endless": 5}): "version 4 is newer than this game's 3",
		JSON.stringify({"version": 0, "best_endless": 5}): "'version' is not a whole number >= 1",
		JSON.stringify({"version": 1, "best_endless": "lots"}): "bests.endless lots is not a whole number 0..999999999",
		JSON.stringify({"version": 1, "best_endless": 5, "coins": 3}): "unknown key 'coins'",
		JSON.stringify({"version": 1}): "missing key 'bests'",
		JSON.stringify({"version": 3, "bests": {"endless": 5}, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "bests must be exactly [\"endless\", \"time_attack\"]",
		JSON.stringify({"version": 3, "bests": {"endless": 5, "time_attack": 0, "campaign": 9}, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "bests must be exactly [\"endless\", \"time_attack\"] (got [\"campaign\", \"endless\", \"time_attack\"])",
		JSON.stringify({"version": 3, "bests": {"endless": 5, "time_attack": -1}, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "bests.time_attack -1 is not a whole number 0..999999999",
		JSON.stringify({"version": 3, "best_endless": 5, "bests": {"endless": 5, "time_attack": 0}, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "unknown key 'best_endless'",
	}
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	for text: String in cases:
		var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		_game.bests[GameState.ENDLESS_MODE] = 77
		_game.bests[GameState.TIME_ATTACK_MODE] = 88
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
		_check(_game.bests == {"endless": 0, "time_attack": 0} and fresh is Dictionary and fresh.get("bests") == {"endless": 0.0, "time_attack": 0.0}, label + ": the game starts fresh", "bests %s, save %s" % [_game.bests, fresh])
	error_label.hide()
	_clear_tool_save()


## The HUD bar: inside the safe area at the top, score, wave, shells as icons, combo,
## escaped and the pause button (icon, "Pause", 48x48, the bar's only interactive Control);
## the "Out of shells!" cue is readable on its own plate; the shot surface is below it.
## The run's start and its first wave are logged (plan AC 15).
func _test_play_hud_layout() -> void:
	var from := _log.size()
	var play := await _start_run(11)
	_check_logged(from, "^\\[Play\\] Run start: mode endless, seed 11 \\(escape limit 10, combo cap 5, 3 shells per hit, rival steals on, aim 1\\.00 s, heckle cooldown 4\\.00 s\\)$", "the run start is logged with its mode, seed and rival settings")
	_check_logged(from, "^\\[Play\\] Wave 1 start: 2 birds \\(goose, goose\\), 6 shells, speed x1\\.00$", "the wave start is logged with its birds and shells")
	var bar := play.get_node("Hud/Bar") as Control
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Button
	var shot_input := play.get_node("ShotInput") as Control
	var texts := [_text(play, "Score"), _text(play, "Wave"), _text(play, "Combo"), _text(play, "Rival"), _text(play, "Escaped")]
	_check(texts == ["Score 0", "Wave 1", "x1", "Rival 0", "Escaped 0/10"], "the HUD shows score, wave, combo, the rival's score and escapes", str(texts))
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
## shells_per_hit (Endless: 8 x 3 (a splitter and its 2 goslings) x 3 = 72). The rival's
## score is at most escape_limit x the most points a bird he can steal is worth (every
## steal counts as an escape; Endless: 10 x 500 = 5000). At that pool
## and at the largest icon row, with the widest texts (a 9-digit score, wave 999, the empty
## cue, the combo cap, the rival's top score, 10/10 escaped), every stat lies inside the safe area and left of the
## pause button, at 16:9, 19.5:9, 4:3 and under a notch.
func _test_play_hud_fits_any_pool() -> void:
	var play := await _start_run(12)
	var max_pool := 0
	for each in Content.modes():
		var most := Wave.hits_needed(Content.bird(each.golden_bird))
		for entry in each.birds:
			most = maxi(most, Wave.hits_needed(Content.bird(entry.bird)))
		max_pool = maxi(max_pool, Ammo.pool_size(each.max_birds * most, each.shells_per_hit))
	_check(max_pool == 72, "the largest pool modes.json can produce is 72 shells", str(max_pool))
	var max_rival := 0
	for each in Content.modes():
		var ids: Array[String] = [each.golden_bird]
		for entry in each.birds:
			ids.append(entry.bird)
			if Content.bird(entry.bird).split_count > 0:
				ids.append(Content.bird(entry.bird).splits_into)
		for id in ids:
			if Content.bird(id).penalty == 0:
				max_rival = maxi(max_rival, each.escape_limit * Content.bird(id).points)
	_check(max_rival == 5000, "the rival's top score modes.json allows is 5000", str(max_rival))
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
		play.rival_score = max_rival
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
	_check_logged(from, "^\\[Play\\] Wave 2 start: 3 birds \\((goose|golden), (goose|golden), (goose|golden)\\), 9 shells, speed x1\\.06$", "the next wave start is logged")


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
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 3, Endless best 100, Time Attack best 0, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the save is logged")
	var stolen: int = stats.get("stolen", -1)
	var rival_score: int = stats.get("rival_score", -1)
	var steal_line := RegEx.create_from_string("^\\[Play\\] Stolen \\w+ #\\d+ by the rival after a [\\d.]+ s cue: (\\d+) points to the rival")
	var steals: Array[int] = []
	for line in _log.since(from):
		var found := steal_line.search(line)
		if found != null:
			steals.append(int(found.get_string(1)))
	var taken := 0
	for points in steals:
		taken += points
	_check(stolen > 0 and stolen == steals.size() and rival_score == taken and Content.rival_lines().lines["results"].has(stats.get("rival_line")), "the results get the birds stolen, the rival's score (the points of every logged steal) and a results line", "%s; logged steals %s" % [stats, steals])
	_check_logged(from, "^\\[Play\\] Run end: mode endless, seed 41, wave \\d+, score 100, 1 shots \\(1 hits, 0 misses, 0 pigeons hit\\), 1 birds killed, 0 refused, 10 escaped \\(%d stolen\\), rival score %d, best 100 \\(new best\\)$" % [stolen, rival_score], "the run end is logged with the run's stats, the birds stolen and the rival's score")
	var shown := ["Score", "Accuracy", "Hits", "Escaped", "Verdict", "Pigeons", "Best"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
	_check(shown == ["Score 100", "Accuracy 100%", "Birds hit 1", "Birds escaped 10 (%d stolen)" % stolen, Results.verdict_text(100, rival_score), "Pigeons hit 0", "Endless best 100"], "the results show score, accuracy, hits, escapes with the birds stolen, the verdict with the rival's score, pigeons hit and best", str(shown))
	_check((results.get_node("Safe/Stats/Verdict") as Label).visible and not (results.get_node("Safe/Stats/Stars") as Label).visible and (results.get_node("Safe/Heading") as Label).text == Results.ENDLESS_HEADING, "Endless results show the verdict, no stars", "verdict or stars")
	var last_stat := (results.get_node("Safe/Stats/Best") as Control).get_global_rect()
	_check(last_stat.end.y <= (results.get_node("Safe/NewBest") as Control).get_global_rect().position.y + 0.5, "the stats (now eight lines) fit above New best!", str(last_stat))
	var rival_line := results.get_node("Safe/RivalLine") as Label
	var line_rect := rival_line.get_global_rect()
	_check(rival_line.visible and rival_line.text == Results.RIVAL_LINE_TEXT % stats.get("rival_line") and _game.safe_rect().encloses(line_rect) and line_rect.position.y >= (results.get_node("Safe/PlayAgainButton") as Control).get_global_rect().end.y and rival_line.get_line_count() == 1, "the results show the rival's line on one line below the buttons, inside the safe area", "%s '%s'" % [line_rect, rival_line.text])
	_check((results.get_node("Safe/NewBest") as Label).visible and not (results.get_node("Safe/SaveError") as Label).visible, "the results say New best! (and no save problem)", "hidden")
	await _check_results_fit(results)
	_check(Results.accuracy_text(0, 0) == Results.NO_VALUE and Results.accuracy_text(3, 4) == "75%", "accuracy is hits / shots, a dash with no shots", Results.accuracy_text(3, 4))
	var again := results.get_node("Safe/PlayAgainButton") as Button
	_check(again.has_focus() and again.get_global_rect().size.y >= MIN_TARGET and _game.safe_rect().encloses(again.get_global_rect()), "Play again is focused, >= 44 high, in the safe area", str(root.gui_get_focus_owner()))
	_game.bests[GameState.ENDLESS_MODE] = 0
	_game.load_game()
	_check(_game.best(GameState.ENDLESS_MODE) == 100, "the new best survives a save and reload", str(_game.bests))
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
	_game.goto(GameState.Flow.RESULTS, {"mode": "endless", "score": 40, "shots": 0, "hits": 0, "kills": 0, "pigeons": 0, "escaped": 10, "stolen": 0, "rival_score": 0, "rival_line": "Not bad.", "rival_steals": true, "best": 100, "new_best": false, "save_error": ""})
	await _game.transition_finished
	_check(not (current_scene.get_node("Safe/NewBest") as Label).visible and (current_scene.get_node("Safe/Stats/Accuracy") as Label).text == "Accuracy " + Results.NO_VALUE, "a run below the best shows no New best!, and a dash for no shots", "shown")
	await _tap(current_scene.get_node("Safe/TitleButton") as Control)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE, "Title goes to the title", str(_game.state))
	_clear_tool_save()


## With every element shown (New best!, a two-line SaveError, the rival line), the results
## screen fits the safe area at 16:9, 4:3, under a notch with the iOS home-indicator inset
## (RESULTS_INSET_SAFE_RECT) and at RESULTS_MIN_SAFE_HEIGHT: each element inside it, its
## text inside its rect, no two overlapping, the buttons >= 44x44.
func _check_results_fit(results: Results) -> void:
	var save_error := results.get_node("Safe/SaveError") as Label
	save_error.text = Results.SAVE_ERROR_TEXT % "the file could not be written because the disk is full, so the new best will be lost when the game is closed"
	save_error.show()
	var names: Array[String] = ["Heading", "Stats/Score", "Stats/Accuracy", "Stats/Hits", "Stats/Escaped", "Stats/Pigeons", "Stats/Best", "NewBest", "SaveError", "RivalLine"]
	# The verdict and the stars show only in some runs (a run with steals, a level); the
	# buttons are the variant's.
	for optional: String in ["Stats/Verdict", "Stats/Stars", "NextButton", "RetryButton", "LevelsButton", "PlayAgainButton", "TitleButton"]:
		if (results.get_node("Safe/" + optional) as Control).visible:
			names.append(optional)
	var cases: Array[String] = ["16:9", "4:3", "19.5:9 notched, home indicator", "16:9, safe height %d" % RESULTS_MIN_SAFE_HEIGHT]
	var windows: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_4_3, LANDSCAPE_19_5_9, LANDSCAPE_16_9]
	var safes: Array[Rect2] = [Rect2(), Rect2(), RESULTS_INSET_SAFE_RECT, Rect2(0, (540 - RESULTS_MIN_SAFE_HEIGHT) / 2.0, 960, RESULTS_MIN_SAFE_HEIGHT)]
	for i in cases.size():
		_game.safe_area_override = safes[i]
		root.size = windows[i]
		await process_frame
		await process_frame
		var safe := _game.safe_rect()
		var problems: Array[String] = []
		var rects: Array[Rect2] = []
		for n in names:
			var item := results.get_node("Safe/" + n) as Control
			var rect := item.get_global_rect()
			rects.append(rect)
			if not item.visible or not safe.grow(0.5).encloses(rect):
				problems.append("%s %s not shown inside the safe area" % [n, rect])
			if item is Label:
				var label := item as Label
				var lines := label.get_visible_line_count()
				var text_height := lines * label.get_line_height() + (lines - 1) * label.get_theme_constant("line_spacing")
				if text_height > rect.size.y + 0.5:
					problems.append("%s text %.1f high in %s" % [n, text_height, rect])
				if label == save_error and lines != 2:
					problems.append("SaveError shows %d lines, not its two" % lines)
			elif rect.size.x < MIN_TARGET or rect.size.y < MIN_TARGET:
				problems.append("%s %s under 44x44" % [n, rect])
		for a in names.size():
			for b in range(a + 1, names.size()):
				if rects[a].intersection(rects[b]).get_area() > 0.25:
					problems.append("%s %s overlaps %s %s" % [names[a], rects[a], names[b], rects[b]])
		_check(problems.is_empty(), "%s: the results screen (every element shown) fits the safe area %s without overlap" % [cases[i], safe], "; ".join(problems))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame
	save_error.hide()


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
	_game.goto(GameState.Flow.RESULTS, {"mode": "endless", "score": 500, "shots": 5, "hits": 5, "kills": 5, "pigeons": 0, "escaped": 10, "stolen": 0, "rival_score": 0, "rival_line": "Not bad.", "rival_steals": true, "best": 500, "new_best": true, "save_error": ""})
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
	_check(_game.best(GameState.ENDLESS_MODE) == 0, "the unsaved best is not in the save", str(_game.bests))
	_game.save_error = ""
	_clear_tool_save()


## Time Attack starts with its mode, seed and time limit logged (no escape limit, steals
## off); the HUD bar shows the time left as text ("Time 60") instead of the rival's tally,
## escapes without a limit, and the pause button is still its only interactive Control;
## the widest Time Attack bar (a 9-digit score, wave 999, the largest pool its data can
## give, the empty cue, its combo cap, 999 escaped, the time) stays inside the safe bar
## and clear of the pause button at 16:9, 19.5:9, 4:3 and under a notch.
func _test_time_attack_start_and_hud() -> void:
	var from := _log.size()
	var play := await _start_run(51, GameState.TIME_ATTACK_MODE)
	_check_logged(from, "^\\[Play\\] Run start: mode time_attack, seed 51 \\(time limit 60\\.00 s, no escape limit, combo cap 8, 2 shells per hit, rival steals off, aim 1\\.00 s, heckle cooldown 4\\.00 s\\)$", "the Time Attack start is logged with its mode, seed and time limit")
	_check_logged(from, "^\\[Play\\] Wave 1 start: 3 birds \\(goose, goose, goose\\), 6 shells, speed x1\\.00, 60\\.00 s left$", "the first wave is logged with the time left")
	var time := play.get_node("Hud/Bar/Stats/Time") as Label
	var rival := play.get_node("Hud/Bar/Stats/Rival") as Label
	_check(play.is_timed() and time.visible and time.text == "Time %d" % ceili(play.time_left()) and play.time_left() < 60.0 and play.time_left() > 59.0, "the HUD shows the seconds left", "%s '%s', %.3f left" % [time.visible, time.text, play.time_left()])
	_check(not rival.visible and _text(play, "Escaped") == "Escaped 0", "no rival tally and no escape limit on the Time Attack HUD", "rival %s, '%s'" % [rival.visible, _text(play, "Escaped")])
	var bar := play.get_node("Hud/Bar") as Control
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Control
	_check(_interactive_controls(bar) == [pause_button], "the pause button is still the HUD bar's only interactive Control", str(_interactive_controls(bar)))
	var most := Wave.hits_needed(Content.bird(play.mode.golden_bird))
	for entry in play.mode.birds:
		most = maxi(most, Wave.hits_needed(Content.bird(entry.bird)))
	var max_pool := Ammo.pool_size(play.mode.max_birds * most, play.mode.shells_per_hit)
	_check(max_pool == 48, "Time Attack's largest pool is 48 shells (8 splitters x 3 hits x 2)", str(max_pool))
	var stats := play.get_node("Hud/Bar/Stats") as Control
	(play.get_node("Hud/Bar/Stats/Empty") as Control).show()
	var cases: Array[String] = ["16:9", "19.5:9", "4:3", "19.5:9 notched"]
	var windows: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_19_5_9, LANDSCAPE_4_3, LANDSCAPE_19_5_9]
	for pool: int in [Play.SHELL_ICONS_MAX, max_pool]:
		play.set_shell_pool(pool)
		play.scoring.score = GameState.SAVE_SCORE_MAX
		play.scoring.multiplier = play.mode.combo_cap
		play.wave.index = 999
		play.escaped = 999
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
			_check(time.visible and stray.is_empty() and stats.get_combined_minimum_size().x <= stats.size.x + 0.5, "%s, pool %d: the widest Time Attack HUD (with the time) stays inside the safe bar, clear of the pause button" % [cases[i], pool], "min width %.1f of %.1f; outside: %s" % [stats.get_combined_minimum_size().x, stats.size.x, stray])
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## A Time Attack run lasts exactly its time limit of play time: the clock runs one frame of
## game time per frame and stops at the limit on the first frame that reaches it (never a
## frame early or late, even when the summed frame times land a hair short of it), the run
## ends there and the results open; the end is logged with the time used.
func _test_time_attack_clock_ends_exactly() -> void:
	var time_attack := Content.mode(GameState.TIME_ATTACK_MODE)
	time_attack.time_limit = 3.0
	var play := await _start_run(52, GameState.TIME_ATTACK_MODE)
	var from := _log.size()
	var clocks: Array[float] = []
	var shown: Array[String] = []
	for i in 400:
		if _game.is_transitioning():
			break
		clocks.append(play.run_clock)
		shown.append(_text(play, "Time"))
		await process_frame
	_check(_game.is_transitioning() and play.run_clock == 3.0 and play.time_left() == 0.0, "the clock stops exactly at the time limit and the run ends", "clock %.6f, transitioning %s" % [play.run_clock, _game.is_transitioning()])
	time_attack.time_limit = 60.0
	# 180 frames of 1/60 s sum to a hair under 3 s in floats: the run must still end on that
	# frame, not one later, and the clock runs at game speed (one frame per frame).
	var steady := clocks.size() > 2
	for i in range(1, clocks.size()):
		steady = steady and is_equal_approx(clocks[i] - clocks[i - 1], FRAME)
	_check(steady, "the Time Attack clock runs one frame of game time per frame", str(clocks.slice(-4)))
	_check(not clocks.is_empty() and is_equal_approx(clocks.back(), 3.0 - FRAME), "the run ends on the first frame that reaches the time limit", "last clock before the end %.15f" % (clocks.back() if not clocks.is_empty() else -1.0))
	_check(shown.has("Time 3") and shown.has("Time 2") and shown.has("Time 1") and _text(play, "Time") == "Time 0", "the HUD counts the seconds down to 0", "%s ... %s" % [shown.slice(0, 2), _text(play, "Time")])
	_check_logged(from, "^\\[Play\\] Run end: mode time_attack, seed 52, wave \\d+, time used 3\\.00 of 3\\.00 s, score 0, ", "the run end is logged with the waves and the time used")
	await _game.transition_finished
	_check(current_scene is Results and (current_scene.get_node("Safe/Heading") as Label).text == Results.TIMED_HEADING, "the results open when the time is up", str(current_scene))
	_clear_tool_save()


## Every pause (the pause button, Escape, the window losing focus, the page hidden, the
## rotate overlay) freezes the Time Attack clock and the HUD time; resuming continues from
## the same time left.
func _test_time_attack_pause_freezes_clock() -> void:
	var play := await _start_run(53, GameState.TIME_ATTACK_MODE)
	for i in 30:
		await process_frame
	for cause: String in ["pause button", "Escape", "window lost focus", "page hidden", "rotate overlay"]:
		var from := _log.size()
		match cause:
			"pause button":
				await _tap(play.get_node("Hud/Bar/PauseButton") as Control)
			"Escape":
				await _key(KEY_ESCAPE)
			"window lost focus":
				play.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"page hidden":
				_game.page_hidden.emit()
			"rotate overlay":
				root.size = PORTRAIT_9_19_5
		await process_frame
		var left := play.time_left()
		var hud := _text(play, "Time")
		for i in 20:
			await process_frame
		_check(paused and play.time_left() == left and _text(play, "Time") == hud and left < 60.0 and left > 50.0, "%s: the Time Attack clock is frozen" % cause, "paused %s, %.4f -> %.4f" % [paused, left, play.time_left()])
		if cause == "rotate overlay":
			root.size = BASE_WINDOW
			await process_frame
			await process_frame
			_check(play.is_paused() and paused and play.time_left() == left, "rotate overlay: back in landscape the menu is open and the clock still frozen", "menu %s, %.4f -> %.4f" % [play.is_paused(), left, play.time_left()])
		_check_logged(from, "^\\[Play\\] Paused \\(%s\\): wave \\d+ at t -?[\\d.]+, score 0, [\\d.]+ s left$" % cause, "%s: the pause is logged with the time left" % cause)
		play.resume()
		await process_frame
		_check(not paused and play.time_left() < left and is_equal_approx(play.time_left(), left - FRAME), "%s: resuming continues from the same time left" % cause, "%.4f -> %.4f" % [left, play.time_left()])


## In Time Attack the next wave starts as soon as the current one is cleared (every bird
## hit) or lost (the shells run out and the birds flee), each with a full pool of its own
## shells; escapes have no limit and cost no points.
func _test_time_attack_waves_on_clear() -> void:
	var play := await _start_run(54, GameState.TIME_ATTACK_MODE)
	for i in 400:
		if play.wave.spawns.size() == play.flying_birds().size():
			break
		await process_frame
	_check(play.wave.index == 1 and play.flying_birds().size() == 3, "wave 1's three geese are up", "%d flying" % play.flying_birds().size())
	for bird in play.flying_birds():
		bird.age = maxf(bird.age, IN_FIELD_AGE)
	await process_frame
	var from := _log.size()
	for bird in play.flying_birds():
		await _touch(_global(play, bird.transform * LOCAL_BODY))
	var frames := 0
	while play.wave.index == 1 and frames < 5:
		await process_frame
		frames += 1
	_check(play.scoring.kills == 3 and play.wave.index == 2 and frames <= 1, "the next wave starts as soon as the last one is cleared", "%d kills, wave %d after %d frames" % [play.scoring.kills, play.wave.index, frames])
	_check(play.ammo.shells == play.wave.shells and play.wave.shells == Wave.for_mode(play.mode, 2, 54).shells and play.wave.shells > 0, "the new wave has a full pool of its own shells", "%d of %d" % [play.ammo.shells, play.wave.shells])
	_check_logged(from, "^\\[Play\\] Wave 2 start: 4 birds \\([a-z, ]+\\), %d shells, speed x1\\.06, [\\d.]+ s left$" % play.wave.shells, "the wave start is logged with its shells and the time left")
	var score := play.scoring.score
	play.escaped = 99
	for i in 200:
		if not play.flying_birds().is_empty():
			break
		await process_frame
	var fled := play.flying_birds()
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in play.wave.shells:
		await _touch(grass)
	# The bird of wave 2 that was up flees; its escape is past any escape limit.
	Engine.time_scale = FAST_TIME_SCALE
	for i in 600:
		if fled.all(func(bird: Variant) -> bool: return not is_instance_valid(bird)) or _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(play.wave.index >= 3 and play.ammo.shells == play.wave.shells and play.wave.shells > 0, "a lost wave is followed by the next with a full pool", "wave %d, %d of %d shells" % [play.wave.index, play.ammo.shells, play.wave.shells])
	_check(not fled.is_empty() and play.escaped > 100 and not _game.is_transitioning() and current_scene == play and play.scoring.score == score, "escapes have no limit and cost no points in Time Attack", "%d escaped, transitioning %s, score %d -> %d" % [play.escaped, _game.is_transitioning(), score, play.scoring.score])


## A Time Attack wave is lost the moment its pool runs out: on the frame of the last shot
## the wave is lost (logged with its skipped birds) and the next one starts, with no dead
## time (the out-of-shells line and the next wave's start carry the same time left) and a
## full pool; the lost wave's birds still to spawn never spawn.
func _test_time_attack_lost_wave_starts_next_at_once() -> void:
	var play := await _start_run(59, GameState.TIME_ATTACK_MODE)
	for i in 200:
		if play.flying_birds().size() == 1:
			break
		await process_frame
	_check(play.wave.index == 1 and play.flying_birds().size() == 1 and play.wave.spawns.size() == 3, "wave 1's first goose is up, two still to spawn", "%d flying" % play.flying_birds().size())
	var from := _log.size()
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in play.wave.shells:
		await _touch(grass)
	_check(play.wave.index == 2 and play.ammo.shells == play.wave.shells and play.wave.shells > 0 and play.wave_clock <= -Play.WAVE_LEAD + 2.0 * FRAME + 0.0001, "the next wave starts with a full pool as soon as the pool runs out", "wave %d, %d of %d shells, wave clock %.4f" % [play.wave.index, play.ammo.shells, play.wave.shells, play.wave_clock])
	var out := RegEx.create_from_string("^\\[Play\\] Out of shells: 1 flying birds flee, 2 still to spawn are skipped \\(wave 1, ([\\d.]+) s left\\)$")
	var lost := RegEx.create_from_string("^\\[Play\\] Wave 1 lost \\(no shells\\): 2 birds still to spawn skipped, 2 of them counted as escaped \\(2 escaped\\), 1 flying flee, ([\\d.]+) s left$")
	var started := RegEx.create_from_string("^\\[Play\\] Wave 2 start: .*, ([\\d.]+) s left$")
	var times: Array[String] = ["", "", ""]
	for line in _log.since(from):
		for k in 3:
			var found := ([out, lost, started][k] as RegEx).search(line)
			if found != null and times[k] == "":
				times[k] = found.get_string(1)
	_check(times[0] != "" and times[0] == times[1] and times[1] == times[2], "the wave is lost and the next starts at the same moment the pool runs out (no dead time)", "out %s, lost %s, next %s" % times)
	_check(_text(play, "Wave") == "Wave 2" and _shell_icons(play) == mini(play.wave.shells, Play.SHELL_ICONS_MAX), "the HUD shows the new wave's number and full pool at once", "%s, %d icons" % [_text(play, "Wave"), _shell_icons(play)])
	_check_logged(from, "^\\[Play\\] Heckle \\(wave_end\\) (#\\d+: |skipped: cooldown)", "the lost wave draws a wave_end heckle (cooldown permitting)")
	# Past every spawn time of wave 1 (0.9 and 1.8 s), only its first goose was ever up.
	var most_wave_1 := 0
	Engine.time_scale = FAST_TIME_SCALE
	for i in 60:
		most_wave_1 = maxi(most_wave_1, play.flying_birds().filter(func(bird: Bird) -> bool: return bird.wave_index == 1).size())
		await process_frame
	Engine.time_scale = 1.0
	var spawned_wave_1 := Array(_log.since(from)).filter(func(line: String) -> bool: return line.begins_with("[Play] Spawned") and line.contains("(wave 1,")).size()
	_check(spawned_wave_1 == 0 and most_wave_1 <= 1, "the lost wave's birds still to spawn never spawn", "%d wave 1 spawns logged after the loss, %d wave 1 birds up at once" % [spawned_wave_1, most_wave_1])


## The lost wave's skipped birds count as escaped at once, except a decoy (its escape never
## counts); its birds in the air are counted when they escape.
func _test_time_attack_lost_wave_counts_skipped_as_escaped() -> void:
	var play := await _start_run(60, GameState.TIME_ATTACK_MODE)
	for i in 200:
		if play.flying_birds().size() == 1:
			break
		await process_frame
	var leftover := play.flying_birds()[0]
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in play.wave.shells:
		await _touch(grass)
	_check(play.wave.index == 2 and play.escaped == 2, "wave 1's two skipped geese count as escaped at once", "wave %d, %d escaped" % [play.wave.index, play.escaped])
	# Wave 2 (still in its lead-in, nothing spawned): its last two birds made decoys, its
	# pool spent at once, so all four are skipped and two count.
	var count := play.wave.spawns.size()
	for i in range(2, count):
		play.wave.spawns[i].bird_id = "decoy"
	var from := _log.size()
	for i in play.wave.shells:
		await _touch(grass)
	_check(count == 4 and play.wave.index == 3 and play.escaped == 4, "skipped decoys do not count as escaped", "%d birds, wave %d, %d escaped" % [count, play.wave.index, play.escaped])
	_check_logged(from, "^\\[Play\\] Wave 2 lost \\(no shells\\): 4 birds still to spawn skipped, 2 of them counted as escaped \\(4 escaped\\), 0 flying flee, [\\d.]+ s left$", "the skipped and counted birds are logged")
	from = _log.size()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 600:
		if not is_instance_valid(leftover):
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(not is_instance_valid(leftover) and play.escaped == 5, "the lost wave's goose in the air is counted when it escapes", "%d escaped" % play.escaped)
	_check_logged(from, "^\\[Play\\] Escaped goose #1 \\(5, wave 3 at t ", "the leftover goose's escape is logged")


## After a lost Time Attack wave its birds still in the air are targets for the next
## wave's shells (a hit scores), and they never hold up the next wave's end: once all of
## its own birds are hit, the wave after starts though a leftover is still flying.
func _test_time_attack_leftover_overlaps_next_wave() -> void:
	var play := await _start_run(61, GameState.TIME_ATTACK_MODE)
	for i in 200:
		if play.flying_birds().size() == 1:
			break
		await process_frame
	var leftover := play.flying_birds()[0]
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in play.wave.shells:
		await _touch(grass)
	_check(play.wave.index == 2 and leftover.is_flying() and leftover.wave_index == 1, "a lost wave's goose is still in the air during the next wave", "wave %d" % play.wave.index)
	leftover.age = IN_FIELD_AGE
	leftover.set_process(false)
	for i in 400:
		if play.flying_birds().size() == play.wave.spawns.size() + 1:
			break
		await process_frame
	for bird in play.flying_birds():
		if bird != leftover:
			bird.age = maxf(bird.age, IN_FIELD_AGE)
	await process_frame
	for bird in play.flying_birds():
		if bird == leftover:
			continue
		for shot in bird.spec.hp:
			if bird.is_flying():
				await _touch(_global(play, bird.transform * LOCAL_BODY))
	var frames := 0
	while play.wave.index == 2 and frames < 5:
		await process_frame
		frames += 1
	_check(play.wave.index == 3 and frames <= 1 and leftover.is_flying(), "a wave ends on its own birds: a lost wave's leftover does not hold up the next", "wave %d after %d frames, leftover flying %s" % [play.wave.index, frames, leftover.is_flying()])
	var score := play.scoring.score
	var from := _log.size()
	leftover.set_process(true)
	leftover.age = IN_FIELD_AGE
	await process_frame
	await _touch(_global(play, leftover.transform * LOCAL_BODY))
	_check(not leftover.is_flying() and play.scoring.score > score, "a leftover hit with the next wave's shells scores", "score %d -> %d" % [score, play.scoring.score])
	_check_logged(from, "^\\[Play\\] Hit goose #1 \\(hit 1/1, killed\\)", "the leftover's hit is logged")
	# A lost wave's splitter (one of wave 2, now that wave 3 runs) killed with wave 3's
	# shells: its goslings belong to wave 2 and flee, so wave 3 does not wait for them.
	var splitter := await _spawn_flying(play, 31, IN_FIELD_AGE, "splitter")
	splitter.wave_index = play.wave.index - 1
	splitter.flee()
	await _touch(_global(play, splitter.transform * LOCAL_BODY))
	var goslings := play.flying_birds().filter(func(bird: Bird) -> bool: return bird.spec.id == "gosling")
	_check(not splitter.is_flying() and goslings.size() == 2 and goslings.all(func(bird: Bird) -> bool: return bird.wave_index == play.wave.index - 1 and bird.is_fleeing()), "a lost wave's splitter launches goslings of its own wave, fleeing", str(goslings.map(func(bird: Bird) -> String: return "wave %d fleeing %s" % [bird.wave_index, bird.is_fleeing()])))


## Endless keeps its rule: when the pool runs out the wave's birds still to spawn spawn
## fleeing, and the next wave starts only once every one of them is gone; no bird counts
## as escaped before it escapes.
func _test_endless_empty_pool_waits_for_the_wave() -> void:
	var play := await _start_run(62)
	for i in 200:
		if play.flying_birds().size() == 1:
			break
		await process_frame
	var from := _log.size()
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in play.wave.shells:
		await _touch(grass)
	_check(play.wave.index == 1 and play.escaped == 0, "Endless: an empty pool does not end the wave or count the birds still to spawn", "wave %d, %d escaped" % [play.wave.index, play.escaped])
	# The frame before wave 2 starts, every bird of wave 1 has spawned and none is flying.
	var done_before := false
	Engine.time_scale = FAST_TIME_SCALE
	for i in 900:
		if play.wave.index == 2 or _game.is_transitioning():
			break
		done_before = play.flying_birds().is_empty() and play.wave_clock >= play.wave.spawns.back().time
		await process_frame
	Engine.time_scale = 1.0
	var waited := done_before
	_check(play.wave.index == 2 and waited and play.escaped == 2, "Endless: the next wave starts only after every bird of the wave has spawned and escaped", "wave %d, waited %s, %d escaped" % [play.wave.index, waited, play.escaped])
	_check_logged(from, "^\\[Play\\] Spawned goose #2 \\(wave 1, .*, fleeing \\(no shells\\)$", "Endless: the bird still to spawn spawns fleeing")
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Wave 1 lost")), "Endless never loses a wave early", "a lost line")


## In Time Attack the rival never aims at or steals a bird left flying past its linger
## time, but he still heckles.
func _test_time_attack_no_steals_no_cue() -> void:
	var play := await _start_run(55, GameState.TIME_ATTACK_MODE)
	var from := _log.size()
	_check(not play.steals_on() and not play.mode.rival_steals, "Time Attack's rival does not steal", str(play.steals_on()))
	var goose := await _spawn_flying(play, 160, Content.bird("goose").linger_time - 0.02)
	var ever_cued := false
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 30:
		ever_cued = ever_cued or goose.is_cued() or play.is_rival_aiming() or (goose.get_node("Reticle") as CanvasItem).visible
		await process_frame
	_check(not ever_cued and goose.is_flying() and play.stolen == 0 and play.rival_score == 0, "no aim cue and no steal in Time Attack", "cued %s, stolen %d" % [ever_cued, play.stolen])
	await _touch(_global(play, Vector2(480, Play.GRASS_Y + 40.0)))
	_check(Content.rival_lines().lines["miss"].has(play.heckle_shown()), "the Time Attack rival still heckles", "'%s'" % play.heckle_shown())
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Aim cue") or line.begins_with("[Play] Stolen")), "nothing about a cue or a steal is logged", "a cue line")


## A Time Attack run that beats the best ends on its results: "Time up", score, accuracy,
## birds hit, birds escaped (no stolen count), pigeons, "Time Attack best", New best!, no
## verdict, Retry (focused) and Title; the best is saved at once (the Endless best left
## alone) and survives a reload; the layout fits down to a safe height of 470; Retry starts
## a new Time Attack run; the title then shows the new best.
func _test_time_attack_results() -> void:
	_clear_tool_save()
	var play := await _start_run(56, GameState.TIME_ATTACK_MODE)
	var bird := await _spawn_flying(play, 12)
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check(play.scoring.score == 100, "the Time Attack run scores one hit", str(play.scoring.score))
	var from := _log.size()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 3000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	_check(results != null, "the time limit ends the run on the results screen", str(current_scene))
	if results == null:
		return
	var stats := _game.flow_args
	_check(stats.get("mode") == GameState.TIME_ATTACK_MODE and stats.get("score") == 100 and stats.get("best") == 100 and stats.get("new_best") == true and stats.get("rival_steals") == false and stats.get("stolen") == 0 and stats.get("save_error") == "", "the results get the Time Attack run's stats", str(stats))
	_check_logged(from, "^\\[Game\\] New Time Attack best: 100 \\(was 0\\)$", "the new Time Attack best is logged")
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 3, Endless best 0, Time Attack best 100, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the new best is saved at once")
	_check_logged(from, "^\\[Play\\] Run end: mode time_attack, seed 56, wave \\d+, time used 60\\.00 of 60\\.00 s, score 100, 1 shots \\(1 hits, 0 misses, 0 pigeons hit\\), 1 birds killed, 0 refused, %d escaped \\(0 stolen\\), rival score 0, best 100 \\(new best\\)$" % stats.get("escaped", -1), "the run end is logged with the waves, the time used and the score")
	_check_logged(from, "^\\[Results\\] Mode time_attack: best 100, new best$", "the results log the mode and its best")
	var shown := ["Score", "Accuracy", "Hits", "Escaped", "Pigeons", "Best"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
	_check(shown == ["Score 100", "Accuracy 100%", "Birds hit 1", "Birds escaped %d" % stats.get("escaped", -1), "Pigeons hit 0", "Time Attack best 100"], "the results show score, accuracy, birds hit, birds escaped (no stolen count), pigeons and the Time Attack best", str(shown))
	_check((results.get_node("Safe/Heading") as Label).text == Results.TIMED_HEADING and not (results.get_node("Safe/Stats/Verdict") as Control).visible and not (results.get_node("Safe/Stats/Stars") as Control).visible and (results.get_node("Safe/NewBest") as Control).visible, "Time up, New best!, no verdict, no stars", "heading or verdict")
	var retry := results.get_node("Safe/RetryButton") as Button
	var title_button := results.get_node("Safe/TitleButton") as Button
	_check(retry.visible and retry.has_focus() and title_button.visible and not (results.get_node("Safe/PlayAgainButton") as Control).visible and not (results.get_node("Safe/NextButton") as Control).visible and not (results.get_node("Safe/LevelsButton") as Control).visible, "Time Attack results offer Retry (focused) and Title", str(root.gui_get_focus_owner()))
	await _check_results_fit(results)
	_game.bests[GameState.TIME_ATTACK_MODE] = 0
	_game.load_game()
	_check(_game.best(GameState.TIME_ATTACK_MODE) == 100 and _game.best(GameState.ENDLESS_MODE) == 0, "the Time Attack best survives a reload, the Endless best untouched", str(_game.bests))
	await _key(KEY_TAB)
	_check(title_button.has_focus(), "Tab reaches Title", str(root.gui_get_focus_owner()))
	await _key(KEY_TAB)
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(current_scene is Play and (current_scene as Play).is_timed() and _game.flow_args.get("mode") == GameState.TIME_ATTACK_MODE and _game.flow_args.get("seed") != 56, "Retry starts a new Time Attack run", str(_game.flow_args))
	await _open_title()
	_check((current_scene.get_node("Safe/TimeAttackButton") as Button).text == "Time Attack\nBest 100", "the title shows the new Time Attack best", (current_scene.get_node("Safe/TimeAttackButton") as Button).text)
	_clear_tool_save()


## Restart starts a new Time Attack run; quitting a Time Attack run to the title records and
## saves nothing (no best, no save written), logged.
func _test_time_attack_quit_saves_nothing() -> void:
	_clear_tool_save()
	var play := await _start_run(57, GameState.TIME_ATTACK_MODE)
	play.open_pause("pause button")
	await _tap(play.get_node("PauseLayer/PauseMenu/Panel/RestartButton") as Control)
	await _game.transition_finished
	await process_frame
	play = current_scene as Play
	_check(play != null and play.is_timed() and _game.flow_args.get("mode") == GameState.TIME_ATTACK_MODE and not paused, "Restart starts a new Time Attack run", str(_game.flow_args))
	var bird := await _spawn_flying(play, 12)
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check(play.scoring.score == 100, "the run has a score to lose", str(play.scoring.score))
	var from := _log.size()
	play.open_pause("pause button")
	await _tap(play.get_node("PauseLayer/PauseMenu/Panel/QuitButton") as Control)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE and _game.best(GameState.TIME_ATTACK_MODE) == 0 and not FileAccess.file_exists(_game.save_path), "quitting to the title records and saves nothing", "%s, bests %s, save %s" % [_game.state, _game.bests, FileAccess.file_exists(_game.save_path)])
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Game] Saved") or line.contains("best:")), "nothing logs a best or a save", "a save line")
	_check_logged(from, "^\\[Play\\] Left the run \\(Quit to title\\): mode time_attack, seed \\d+, wave 1, score 100, 0 escaped, [\\d.]+ s left; nothing recorded$", "leaving the run is logged with the time left")
	_clear_tool_save()


## A new Time Attack best that cannot be saved sets save_error, emits save_failed, and the
## results say New best! and that it could not be saved, with the reason.
func _test_time_attack_save_failure() -> void:
	_clear_tool_save()
	var time_attack := Content.mode(GameState.TIME_ATTACK_MODE)
	time_attack.time_limit = 3.0
	var play := await _start_run(58, GameState.TIME_ATTACK_MODE)
	var bird := await _spawn_flying(play, 12)
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	var failed: Array[String] = []
	var record := func(why: String) -> void: failed.append(why)
	_game.save_failed.connect(record)
	_game.save_path = UNWRITABLE_SAVE_PATH
	_game.quiet_errors = true
	for i in 400:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	_game.quiet_errors = false
	_game.save_path = GameState.TOOL_SAVE_PATH
	_game.save_failed.disconnect(record)
	time_attack.time_limit = 60.0
	var results := current_scene as Results
	var reason: String = _game.flow_args.get("save_error", "")
	_check(results != null and _game.flow_args.get("new_best") == true and reason.begins_with("cannot open the save file") and _game.save_error == reason and failed == [reason], "an unsaved Time Attack best sets save_error and emits save_failed", "%s / %s" % [_game.flow_args, failed])
	if results != null:
		var notice := results.get_node("Safe/SaveError") as Label
		_check((results.get_node("Safe/NewBest") as Label).visible and notice.visible and notice.text == Results.SAVE_ERROR_TEXT % reason, "the Time Attack results say New best! and that it could not be saved", notice.text)
	_game.load_game()
	_check(_game.best(GameState.TIME_ATTACK_MODE) == 0, "the unsaved Time Attack best is not in the save", str(_game.bests))
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
			for spawn in Wave.for_mode(endless, index, run_seed).spawns:
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
			for spawn in Wave.for_mode(endless, index, run_seed).spawns:
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
		for spawn in Wave.for_mode(endless, 1, run_seed).spawns:
			in_wave_1 += int(spawn.bird_id == endless.golden_bird)
		for index in range(2, 9):
			var plan := Wave.for_mode(endless, index, run_seed)
			var again := Wave.for_mode(endless, index, run_seed)
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
			var plan := Wave.for_mode(endless, index, run_seed)
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


## Rival (pure): no steal with steals off, for the decoy, for a fleeing bird or before
## linger_time; from linger_time the rival aims (never firing before a cue has started), and
## fires once the cue has run aim_time from its start. A miss, combo or wave-end heckle waits
## for the cooldown, a steal line never does. A line pick depends only on the run seed and
## the heckle count.
func _test_rival_rules() -> void:
	var none := Rival.NOT_AIMING
	var cases: Array[Array] = [
		[Rival.steal_state(3.4, 3.5, 1.0, none, false, false, true), Rival.Steal.NONE, "nothing before linger_time"],
		[Rival.steal_state(3.5, 3.5, 1.0, none, false, false, true), Rival.Steal.AIMING, "the cue starts at linger_time"],
		[Rival.steal_state(9.0, 3.5, 1.0, none, false, false, true), Rival.Steal.AIMING, "a bird with no cue yet is aimed at first, never shot at once"],
		[Rival.steal_state(4.49, 3.5, 1.0, 3.5, false, false, true), Rival.Steal.AIMING, "the cue runs aim_time"],
		[Rival.steal_state(4.5, 3.5, 1.0, 3.5, false, false, true), Rival.Steal.FIRE, "he fires once the cue has run aim_time"],
		[Rival.steal_state(5.0, 3.5, 1.0, 4.2, false, false, true), Rival.Steal.AIMING, "aim_time counts from the cue's start"],
		[Rival.steal_state(5.0, 3.5, 1.0, 3.5, true, false, true), Rival.Steal.NONE, "never the decoy"],
		[Rival.steal_state(4.0, 3.5, 1.0, 3.5, false, true, true), Rival.Steal.NONE, "a fleeing bird drops the cue"],
		[Rival.steal_state(5.0, 3.5, 1.0, 3.5, false, false, false), Rival.Steal.NONE, "never with steals off"],
	]
	for case in cases:
		_check(case[0] == case[1], "Rival.steal_state: " + str(case[2]), "got %s, expected %s" % [case[0], case[1]])
	_check(not Rival.may_heckle("miss", 3.9, 0.0, 4.0) and Rival.may_heckle("miss", 4.0, 0.0, 4.0) and Rival.may_heckle("wave_end", 0.0, -INF, 4.0), "Rival.may_heckle: a miss or wave-end line waits for the cooldown (none before the first)", "")
	_check(Rival.may_heckle(Rival.STEAL, 0.1, 0.0, 4.0), "Rival.may_heckle: a steal line skips the cooldown", "")
	var lines := Content.rival_lines().lines["miss"]
	var first: Array[String] = []
	var again: Array[String] = []
	var other: Array[String] = []
	for count in 20:
		first.append(Rival.pick_line(lines, 7, count))
		again.append(Rival.pick_line(lines, 7, count))
		other.append(Rival.pick_line(lines, 8, count))
	var distinct: Dictionary[String, bool] = {}
	for line in first:
		distinct[line] = true
	_check(first == again and first != other and distinct.size() > 1 and first.all(func(line: String) -> bool: return lines.has(line)), "Rival.pick_line: seeded by the run seed and the heckle count, varied, from the category's lines", "%d distinct" % distinct.size())


## The aim cue (AC 6): a goose reaching its linger_time shows the reticle and the rival
## raises his gun; after aim_time he fires (AC 8): the goose falls as stolen on its hit
## frame, its points (no combo) go to the rival (HUD "Rival 100"), it counts as an escape,
## the player's x3 combo is left alone, and a steal line shows even inside the cooldown of
## the combo heckle just before. Cue start, steal and heckles are logged (AC 14).
func _test_rival_cue_and_steal() -> void:
	var play := await _start_run(61)
	var aim := Content.rival_lines().aim_time
	for i in 2:
		var goose := await _spawn_flying(play, 110 + i)
		await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.multiplier == 3 and play.heckles == 1, "two kills build x3, which heckles", "x%d, %d heckles" % [play.scoring.multiplier, play.heckles])
	var from := _log.size()
	var bird := await _cued_bird(play, 112, "goose")
	var linger := bird.spec.linger_time
	var reticle := bird.get_node("Reticle") as Sprite2D
	_check(bird.is_cued() and bird.cue_age >= linger and bird.cue_age <= linger + FRAME + 0.001, "the cue starts when the goose reaches its linger_time", "cue_age %.3f, linger %.2f" % [bird.cue_age, linger])
	_check(reticle.visible and play.is_rival_aiming(), "the cue shows a reticle on the goose and the rival raising his gun", "reticle %s, aiming %s" % [reticle.visible, play.is_rival_aiming()])
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d: age [\\d.]+ \\(linger 3\\.50 s\\), the rival fires in 1\\.00 s \\(wave 1 at t -?[\\d.]+, rival score 0, 0 stolen\\)$" % bird.number, "the cue start is logged with the bird, wave, time and tallies")
	var escaped := play.escaped
	var cued_until := 0.0
	for i in roundi(aim * 60.0) + 10:
		if not bird.is_flying():
			break
		cued_until = bird.age - bird.cue_age if bird.is_cued() else cued_until
		await process_frame
	_check(bird.stolen and not bird.is_flying() and not bird.is_cued() and not reticle.visible, "once the cue has run the rival shoots the goose", "stolen %s, state %d" % [bird.stolen, bird.state])
	_check(cued_until >= aim - FRAME - 0.001 and cued_until <= aim + FRAME + 0.001, "the cue lasts aim_time (to the frame)", "cued %.3f s of %.2f" % [cued_until, aim])
	_check((bird.get_node("Sprite") as Sprite2D).texture.resource_path == bird.spec.texture_path("hit"), "the stolen goose falls on its hit frame", (bird.get_node("Sprite") as Sprite2D).texture.resource_path)
	_check(play.stolen == 1 and play.rival_score == 100 and play.escaped == escaped + 1 and play.scoring.score == 300, "its points go to the rival and it counts as an escape", "stolen %d, rival %d, escaped %d -> %d" % [play.stolen, play.rival_score, escaped, play.escaped])
	_check(play.scoring.multiplier == 3, "a steal leaves the player's combo alone", "x%d" % play.scoring.multiplier)
	_check(_text(play, "Rival") == "Rival 100" and _text(play, "Escaped") == "Escaped %d/10" % play.escaped and not play.is_rival_aiming(), "the HUD shows the rival's score and the escape; he lowers his gun", "%s, %s" % [_text(play, "Rival"), _text(play, "Escaped")])
	_check_logged(from, "^\\[Play\\] Stolen goose #%d by the rival after a 1\\.0[0-2] s cue: 100 points to the rival, rival score 100, 1 stolen, %d/10 escaped, combo x3 kept \\(wave 1 at t -?[\\d.]+\\)$" % [bird.number, play.escaped], "the steal is logged with the cue time, the tallies, the escapes and the combo")
	_check(Content.rival_lines().lines["steal"].has(play.heckle_shown()) and play.heckles == 2, "a steal line shows inside the cooldown", "'%s', %d heckles" % [play.heckle_shown(), play.heckles])
	_check_logged(from, "^\\[Play\\] Heckle \\(steal\\) #2: \".+\" \\(wave 1 at t -?[\\d.]+, rival score 100, 1 stolen\\)$", "the steal heckle is logged with its category and line")
	var number := bird.number
	for i in 120:
		if not is_instance_valid(bird):
			break
		await process_frame
	_check(not is_instance_valid(bird) and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Escaped goose #%d " % number)), "the stolen goose falls away and never escapes as well", "valid %s" % is_instance_valid(bird))


## A kill during the cue saves the bird (AC 7): the player scores as usual, the cue goes
## away (logged with its cause) and nothing is stolen.
func _test_rival_kill_during_cue() -> void:
	var play := await _start_run(62)
	var from := _log.size()
	var bird := await _cued_bird(play, 120, "goose")
	_check(bird.is_cued(), "the goose is cued", "no cue")
	await _touch(_global(play, bird.transform * LOCAL_BODY))
	_check(not bird.is_flying() and not bird.stolen and play.scoring.score == 100 and play.scoring.kills == 1, "a kill during the cue scores as usual", "score %d, stolen %s" % [play.scoring.score, bird.stolen])
	_check(not bird.is_cued() and not (bird.get_node("Reticle") as Sprite2D).visible and not play.is_rival_aiming(), "the kill takes the cue away", "cued %s, aiming %s" % [bird.is_cued(), play.is_rival_aiming()])
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d cancelled \\(shot by the player\\) after [\\d.]+ s \\(wave 1 at t -?[\\d.]+, rival score 0, 0 stolen\\)$" % bird.number, "the cancelled cue is logged with its cause")
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 10:
		await process_frame
	_check(play.stolen == 0 and play.rival_score == 0 and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Stolen")), "a bird saved during its cue is never stolen", "%d stolen" % play.stolen)


## A damaging hit (the armored goose's first) keeps the cue running from its start; once
## it has run the rival fires and never misses (AC 7).
func _test_rival_damage_keeps_cue() -> void:
	var play := await _start_run(63)
	var from := _log.size()
	var armored := await _cued_bird(play, 125, "armored")
	var cue_age := armored.cue_age
	await _touch(_global(play, armored.transform * LOCAL_BODY))
	_check(armored.is_flying() and armored.hits_taken == 1 and armored.is_cued() and armored.cue_age == cue_age, "a damaging hit keeps the cue (from its start)", "hits %d, cued %s, cue_age %.3f -> %.3f" % [armored.hits_taken, armored.is_cued(), cue_age, armored.cue_age])
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.contains("cancelled")), "a damaging hit cancels nothing", "a cancel line")
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 10:
		if not armored.is_flying():
			break
		await process_frame
	_check(armored.stolen and play.stolen == 1 and play.rival_score == 150, "the rival steals the damaged armored goose once the cue has run", "stolen %s, rival %d" % [armored.stolen, play.rival_score])
	_check_logged(from, "^\\[Play\\] Stolen armored #%d by the rival after a 1\\.0[0-2] s cue: 150 points to the rival" % armored.number, "the armored steal is logged")


## A stolen splitter launches no goslings; a steal with escape_limit - 1 birds lost ends
## the run (AC 8), and the results show the birds stolen and the rival's score (AC 13).
func _test_rival_steal_ends_run() -> void:
	_clear_tool_save()
	var play := await _start_run(64)
	var splitter := await _cued_bird(play, 130, "splitter")
	play.escaped = play.mode.escape_limit - 1
	var from := _log.size()
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 10:
		if not splitter.is_flying():
			break
		await process_frame
	_check(splitter.stolen and play.flying_birds().all(func(bird: Bird) -> bool: return bird.spec.id != "gosling") and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Split")), "a stolen splitter launches no goslings", "stolen %s" % splitter.stolen)
	for i in 120:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	await process_frame
	var results := current_scene as Results
	var stats := _game.flow_args
	_check(results != null and stats.get("escaped") == 10 and stats.get("stolen") == 1 and stats.get("rival_score") == 120, "a steal at escape_limit - 1 ends the run, and the results get it", str(stats))
	_check_logged(from, "^\\[Play\\] Run end: .*, 10 escaped \\(1 stolen\\), rival score 120, best ", "the run end logs the birds stolen and the rival's score")
	_check_logged(from, "^\\[Play\\] Heckle \\(results\\) #\\d+: \".+\" ", "the results line is logged")
	if results != null:
		var shown := ["Escaped", "Verdict"].map(func(n: String) -> String: return (results.get_node("Safe/Stats/" + n) as Label).text)
		_check(shown == ["Birds escaped 10 (1 stolen)", "You 0 vs rival 120: the rival wins"], "the results show the birds stolen and the rival's score in the verdict", str(shown))
		_check_logged(from, "^\\[Results\\] Score 0, .*, 10 escaped, 1 stolen, rival score 120, 0 pigeons hit, best 0; rival: \".+\"$", "the results log the birds stolen, the rival's score and line")
	_clear_tool_save()


## The decoy is never aimed at or stolen; a cued goose that starts fleeing (the shells ran
## out) drops its cue (logged "fled") and escapes as before, counted once (AC 9).
func _test_rival_decoy_and_fleeing() -> void:
	var play := await _start_run(65)
	var from := _log.size()
	var pigeon := await _spawn_flying(play, 140, Content.bird("decoy").linger_time + 0.2, "decoy")
	var ever_cued := false
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 10:
		ever_cued = ever_cued or pigeon.is_cued()
		await process_frame
	_check(not ever_cued and pigeon.is_flying() and play.stolen == 0, "the decoy is never aimed at or stolen", "cued %s, stolen %d" % [ever_cued, play.stolen])
	var goose := await _cued_bird(play, 141, "goose")
	_check(goose.is_cued(), "the goose is cued", "no cue")
	play.ammo.shells = 1
	var escaped := play.escaped
	var shot_from := _log.size()
	await _touch(_global(play, SKY_POINTS[0]))
	await process_frame
	_check(goose.is_fleeing() and not goose.is_cued() and not (goose.get_node("Reticle") as Sprite2D).visible and not play.is_rival_aiming(), "a cued goose that starts fleeing drops the cue", "fleeing %s, cued %s" % [goose.is_fleeing(), goose.is_cued()])
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d cancelled \\(fled\\) after [\\d.]+ s " % goose.number, "the dropped cue is logged with its cause")
	var number := goose.number
	Engine.time_scale = FAST_TIME_SCALE
	for i in 900:
		if not is_instance_valid(goose):
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(not is_instance_valid(goose) and play.stolen == 0, "the fleeing goose escapes as before, never stolen", "stolen %d" % play.stolen)
	# Counted once: from the count at the shot, every escape or steal line since (wave birds
	# and the fleeing decoy log theirs too) logs a total one up for a counted bird and the
	# same for an uncounted one, the goose's included, so nothing else (the cancelled cue)
	# added to it.
	var total := RegEx.create_from_string("^\\[Play\\] (?:Escaped \\w+ #(\\d+) \\((not counted, )?|Stolen .*, )(\\d+)/\\d+\\b")
	var counted_once := false
	var totals: Array[String] = []
	for line in _log.since(shot_from):
		var found := total.search(line)
		if found == null:
			continue
		if found.get_string(2) == "":
			escaped += 1
		totals.append("%s (expected %d)" % [line, escaped])
		if found.get_string(3).to_int() != escaped:
			break
		if found.get_string(1) == str(number):
			counted_once = true
			break
	_check(counted_once, "the fleeing goose's escape is logged and counted once", "; ".join(totals))


## Pausing freezes the cue, the heckle cooldown and the bubble; resuming continues them
## unchanged: the cue still runs its full aim_time (AC 9).
func _test_rival_pause_freezes_cue() -> void:
	var play := await _start_run(66)
	await _touch(_global(play, SKY_POINTS[0]))
	var heckle := play.heckle_shown()
	var goose := await _cued_bird(play, 150, "goose")
	for i in 20:
		await process_frame
	var age := goose.age
	var clock := play.run_clock
	play.open_pause("test")
	for i in roundi(Play.HECKLE_TIME * 60.0) + 30:
		await process_frame
	_check(goose.is_cued() and goose.is_flying() and goose.age == age and play.run_clock == clock and play.stolen == 0, "a pause freezes the cue and the heckle cooldown clock", "age %.3f -> %.3f, clock %.3f -> %.3f, stolen %d" % [age, goose.age, clock, play.run_clock, play.stolen])
	_check(heckle != "" and play.heckle_shown() == heckle, "a pause keeps the heckle on screen", "'%s'" % play.heckle_shown())
	var from := _log.size()
	play.resume()
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 10:
		if not goose.is_flying():
			break
		await process_frame
	_check(goose.stolen and play.stolen == 1, "after resuming the cue runs on and the rival fires", "stolen %s" % goose.stolen)
	_check_logged(from, "^\\[Play\\] Stolen goose #%d by the rival after a 1\\.0[0-2] s cue: " % goose.number, "the paused cue still lasted aim_time of game time")


## With rival_steals off (a test mode standing in for Time Attack) no bird is aimed at or
## stolen, and the rival still heckles (AC 10).
func _test_rival_steals_off() -> void:
	var play := await _start_run(67)
	play.mode.rival_steals = false
	var from := _log.size()
	var goose := await _spawn_flying(play, 160, Content.bird("goose").linger_time - 0.02)
	var ever_cued := false
	for i in roundi(Content.rival_lines().aim_time * 60.0) + 30:
		ever_cued = ever_cued or goose.is_cued() or play.is_rival_aiming()
		await process_frame
	_check(not ever_cued and goose.is_flying() and play.stolen == 0 and play.rival_score == 0, "with steals off no bird is aimed at or stolen", "cued %s, stolen %d" % [ever_cued, play.stolen])
	await _touch(_global(play, SKY_POINTS[0]))
	_check(Content.rival_lines().lines["miss"].has(play.heckle_shown()), "with steals off the rival still heckles", "'%s'" % play.heckle_shown())
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Aim cue") or line.begins_with("[Play] Stolen")), "nothing about a cue or a steal is logged", "a cue line")
	play.mode.rival_steals = true


## Heckles (AC 12): a wave's end shows a wave_end line; a miss inside the cooldown is
## skipped (logged), the line hides after HECKLE_TIME; once the cooldown has passed a miss
## shows a miss line; a kill to x2 says nothing, one raising the combo to x3 a combo line.
## The rival's steals are off here so no steal line moves the cooldown.
func _test_rival_heckle_cooldown() -> void:
	var play := await _start_run(68)
	var lines := Content.rival_lines()
	play.mode.rival_steals = false
	var from := _log.size()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 3000:
		if play.wave.index == 2:
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(play.wave.index == 2 and lines.lines["wave_end"].has(play.heckle_shown()) and play.heckles == 1, "a wave's end shows a wave_end line", "wave %d, '%s'" % [play.wave.index, play.heckle_shown()])
	_check_logged(from, "^\\[Play\\] Heckle \\(wave_end\\) #1: \".+\" \\(wave 1 at t [\\d.]+, rival score 0, 0 stolen\\)$", "the wave-end heckle is logged")
	var skipped_at := play.run_clock
	await _touch(_global(play, SKY_POINTS[0]))
	_check(play.heckles == 1, "a miss inside the cooldown shows nothing", "%d heckles" % play.heckles)
	_check_logged(from, "^\\[Play\\] Heckle \\(miss\\) skipped: cooldown, [\\d.]+ of 4\\.00 s since the last \\(wave 2 at t -?[\\d.]+, rival score 0, 0 stolen\\)$", "the skipped heckle is logged")
	Engine.time_scale = FAST_TIME_SCALE
	for i in 600:
		if play.run_clock - skipped_at >= lines.cooldown:
			break
		await process_frame
	Engine.time_scale = 1.0
	await _touch(_global(play, SKY_POINTS[1]))
	_check(lines.lines["miss"].has(play.heckle_shown()) and play.heckles == 2, "after the cooldown a miss shows a miss line", "'%s'" % play.heckle_shown())
	var shown_at := play.run_clock
	for i in 600:
		if play.heckle_shown() == "":
			break
		await process_frame
	var lasted := play.run_clock - shown_at
	_check(play.heckle_shown() == "" and absf(lasted - Play.HECKLE_TIME) <= 2.0 * FRAME, "a heckle shows for HECKLE_TIME", "%.3f s" % lasted)
	Engine.time_scale = FAST_TIME_SCALE
	for i in 600:
		if play.run_clock - shown_at >= lines.cooldown:
			break
		await process_frame
	Engine.time_scale = 1.0
	var goose := await _spawn_flying(play, 170)
	await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.multiplier == 2 and play.heckles == 2, "a kill raising the combo to x2 says nothing", "x%d, %d heckles" % [play.scoring.multiplier, play.heckles])
	goose = await _spawn_flying(play, 171)
	await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.multiplier == 3 and lines.lines["combo"].has(play.heckle_shown()) and play.heckles == 3, "a kill raising the combo to x3 shows a combo line", "x%d, '%s'" % [play.scoring.multiplier, play.heckle_shown()])
	_check_logged(from, "^\\[Play\\] Heckle \\(combo\\) #3: \".+\" ", "the combo heckle is logged")
	play.mode.rival_steals = true


## The rival and his bubble sit in the grass band (at or below GRASS_Y) inside the visible
## area at 16:9, 19.5:9 and 4:3, ignore touches, and every rival line fits the bubble's two
## lines; a shot on the rival or on the shown bubble is a shot like any other (AC 11).
func _test_rival_layout_and_pass_through() -> void:
	var play := await _start_run(69)
	var world := play.get_node("World") as Node2D
	var rival := play.get_node("World/Rival") as Control
	var bubble := play.get_node("World/Bubble") as Label
	_check(_interactive_controls(rival).is_empty() and _interactive_controls(bubble).is_empty(), "the rival and his bubble take no touches or focus", "%s %s" % [_interactive_controls(rival), _interactive_controls(bubble)])
	var height := bubble.size.y
	var too_long: Array[String] = []
	bubble.show()
	for category in RivalLines.CATEGORIES:
		for line in Content.rival_lines().lines[category]:
			bubble.text = line
			await process_frame
			if bubble.get_line_count() > 2 or bubble.size.y > height + 0.5:
				too_long.append("%s (%d lines)" % [line, bubble.get_line_count()])
	_check(too_long.is_empty(), "every rival line fits the bubble's two lines", str(too_long))
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		var shown := _game.visible_rect()
		var stray: Array[String] = []
		for part: Control in [rival, bubble]:
			var rect := part.get_global_rect()
			if world.to_local(rect.position).y < Play.GRASS_Y or not shown.encloses(rect):
				stray.append("%s %s" % [part.name, rect])
		_check(stray.is_empty(), "%dx%d: the rival and his bubble sit in the grass band, on screen" % [window.x, window.y], str(stray))
	root.size = BASE_WINDOW
	await process_frame
	var from := _log.size()
	for part: Control in [rival, bubble]:
		var shots := play.scoring.shots()
		var shells := play.ammo.shells
		await _touch(part.get_global_rect().get_center())
		_check(play.scoring.shots() == shots + 1 and play.scoring.misses == shots + 1 and play.ammo.shells == shells - 1, "a shot on the %s is a shot like any other (a miss on the grass)" % part.name, "%d shots, %d shells" % [play.scoring.shots(), play.ammo.shells])
	_check_logged(from, "^\\[Play\\] Miss at ", "the shots on the rival and his bubble are logged as misses")


## Campaign waves (Wave.campaign) are a pure function of the level and the wave index (the
## level's fixed seed): the same level and index give the same spawns, shells and speed,
## another level other seeds. A plain wave holds wave_birds birds every spawn_interval at
## speed_scale, with the shells for every hit; the boss level's last wave (and no other) is
## the boss flock, with more birds, a shorter interval and a higher speed than every other
## wave of its chapter, most of its birds the chapter's own type; golden_chance turns slots golden.
func _test_campaign_wave_schedule() -> void:
	var level := Content.level("noon_3")
	var a := Wave.campaign(level, 2)
	var b := Wave.campaign(level, 2)
	var same := a.shells == b.shells and a.spawns.size() == b.spawns.size() and is_equal_approx(a.speed_scale, b.speed_scale) and a.boss == b.boss
	for i in mini(a.spawns.size(), b.spawns.size()):
		same = same and a.spawns[i].bird_id == b.spawns[i].bird_id and a.spawns[i].time == b.spawns[i].time and a.spawns[i].bird_seed == b.spawns[i].bird_seed
	_check(same, "a campaign wave is a pure function of the level and the wave index", "differs")
	_check(Wave.campaign(Content.level("noon_4"), 2).spawns[0].bird_seed != a.spawns[0].bird_seed and Wave.campaign(level, 3).spawns[0].bird_seed != a.spawns[0].bird_seed, "another level or wave gives other bird seeds", str(a.spawns[0].bird_seed))
	var hits := 0
	var timed := true
	for i in a.spawns.size():
		hits += Wave.hits_needed(Content.bird(a.spawns[i].bird_id))
		timed = timed and is_equal_approx(a.spawns[i].time, i * level.spawn_interval)
	_check(a.spawns.size() == level.wave_birds and timed and is_equal_approx(a.speed_scale, level.speed_scale) and not a.boss, "a plain wave holds wave_birds birds every spawn_interval at the level's speed", "%d birds, x%.2f" % [a.spawns.size(), a.speed_scale])
	_check(a.shells == Ammo.pool_size(hits, level.shells_per_hit), "a campaign wave's shells cover every hit its birds need", "%d shells for %d hits" % [a.shells, hits])
	var problems: Array[String] = []
	for boss_level in Content.levels():
		var last := Wave.campaign(boss_level, boss_level.waves)
		if not boss_level.is_boss():
			if last.boss:
				problems.append("%s's last wave is a boss flock" % boss_level.id)
			continue
		var boss := boss_level.boss
		var counts: Dictionary[String, int] = {}
		var boss_timed := true
		for i in last.spawns.size():
			counts[last.spawns[i].bird_id] = counts.get(last.spawns[i].bird_id, 0) + 1
			boss_timed = boss_timed and is_equal_approx(last.spawns[i].time, i * boss.spawn_interval)
		if not last.boss or last.spawns.size() != boss.birds or not boss_timed or not is_equal_approx(last.speed_scale, boss.speed_scale):
			problems.append("%s's last wave is not its boss flock (%d birds, x%.2f)" % [boss_level.id, last.spawns.size(), last.speed_scale])
		var most: String = counts.keys().reduce(func(x: String, y: String) -> String: return y if counts[y] > counts[x] else x)
		if Content.bird(most).chapter != boss_level.chapter:
			problems.append("%s's boss flock is mostly %s, not the chapter's bird (%s)" % [boss_level.id, most, counts])
		for other in Campaign.chapter_levels(boss_level.chapter):
			for wave_index in range(1, other.waves + 1):
				var plan := Wave.campaign(other, wave_index)
				if plan == last or (other == boss_level and wave_index == boss_level.waves):
					continue
				if plan.boss or plan.spawns.size() >= last.spawns.size() or plan.speed_scale >= last.speed_scale or plan.spawns[1].time <= last.spawns[1].time:
					problems.append("%s wave %d is not smaller, slower and sparser than %s's boss flock" % [other.id, wave_index, boss_level.id])
	_check(problems.is_empty(), "every boss level ends on its boss flock, bigger, faster and denser than every other wave of its chapter and mostly the chapter's bird", "\n".join(problems))
	var dawn_2 := Content.level("dawn_2")
	dawn_2.golden_chance = 1.0
	var golden := Wave.campaign(dawn_2, 1)
	dawn_2.golden_chance = 0.08
	_check(golden.spawns.all(func(spawn: Wave.Spawn) -> bool: return spawn.bird_id == dawn_2.golden_bird), "golden_chance turns a level's spawn slots golden", str(golden.spawns.map(func(spawn: Wave.Spawn) -> String: return spawn.bird_id)))


## Stars: one per threshold the final score reaches (0: not passed). Unlocks: only dawn_1 at
## first; the next level opens when the level before is passed (1 star or more, across
## chapters: dawn_6 opens noon_1); a chapter opens with its level 1. Progress keeps the best
## stars and the best score, each on its own.
func _test_campaign_stars_unlocks_and_best() -> void:
	var dawn_1 := Content.level("dawn_1")
	var earned: Array[int] = []
	for score: int in [0, 849, 850, 1449, 1450, 2049, 2050, 99999]:
		earned.append(Campaign.stars(dawn_1, score))
	_check(earned == [0, 0, 1, 1, 2, 2, 3, 3], "a level's stars count the thresholds its final score reaches", str(earned))
	_check(not Campaign.is_passed(0) and Campaign.is_passed(1) and Campaign.is_passed(3), "0 stars means not passed", "")
	var order := Campaign.levels()
	_check(order.size() == 24 and order[0].id == "dawn_1" and order[5].id == "dawn_6" and order[6].id == "noon_1" and order[23].id == "night_6", "the campaign runs chapter by chapter, level by level", str(order.map(func(level: LevelSpec) -> String: return level.id)))
	var progress: Dictionary[String, Campaign.Record] = {}
	var open := order.map(func(level: LevelSpec) -> bool: return Campaign.is_unlocked(level, progress))
	_check(open.count(true) == 1 and open[0], "at first only dawn_1 is unlocked", str(open))
	var chapters := Content.chapters().map(func(spec: ChapterSpec) -> bool: return Campaign.is_chapter_unlocked(spec.id, progress))
	_check(chapters == [true, false, false, false], "at first only dawn is unlocked", str(chapters))
	progress["dawn_1"] = Campaign.Record.new(0, 500)
	_check(not Campaign.is_unlocked(Content.level("dawn_2"), progress), "a level finished with 0 stars unlocks nothing", "dawn_2 open")
	progress["dawn_1"] = Campaign.Record.new(1, 900)
	_check(Campaign.is_unlocked(Content.level("dawn_2"), progress) and not Campaign.is_unlocked(Content.level("dawn_3"), progress), "1 star on a level unlocks the next one only", "")
	for index in range(1, 7):
		progress["dawn_%d" % index] = Campaign.Record.new(3, 9000)
	_check(Campaign.is_unlocked(Content.level("noon_1"), progress) and Campaign.is_chapter_unlocked("noon", progress) and not Campaign.is_chapter_unlocked("sunset", progress), "passing dawn_6 unlocks noon_1 and the noon chapter", "")
	_check(Campaign.chapter_stars("dawn", progress) == 18 and Campaign.chapter_stars("noon", progress) == 0, "a chapter's stars add up its levels' best stars", str(Campaign.chapter_stars("dawn", progress)))
	_check(Campaign.next_level(Content.level("dawn_6")) == Content.level("noon_1") and Campaign.next_level(dawn_1) == Content.level("dawn_2") and Campaign.next_level(Content.level("night_6")) == null, "the next level follows campaign order, none after night_6", "")
	var first := Campaign.merge(null, 2, 900)
	var kept := Campaign.merge(Campaign.Record.new(3, 100), 1, 900)
	var lower := Campaign.merge(Campaign.Record.new(2, 900), 0, 50)
	_check(first.stars == 2 and first.score == 900 and kept.stars == 3 and kept.score == 900 and lower.stars == 2 and lower.score == 900, "a replay keeps the best stars and the best score, never lowering either", "%d/%d %d/%d %d/%d" % [first.stars, first.score, kept.stars, kept.score, lower.stars, lower.score])


## Game.record_level: the finished level's stars and score are kept as its best, saved at
## once and logged with the level, the stars, the score and the level it unlocks; a lower
## replay changes nothing; the progress survives a reload.
func _test_campaign_record_level() -> void:
	_clear_tool_save()
	var dawn_1 := Content.level("dawn_1")
	var from := _log.size()
	_check(_game.record_level(dawn_1, 1500), "a first finish with points is a new best", "")
	_check(_game.progress.has("dawn_1") and _game.progress["dawn_1"].stars == 2 and _game.progress["dawn_1"].score == 1500, "the level's stars and score are recorded", str(_game.progress.keys()))
	_check_logged(from, "^\\[Game\\] Level dawn_1 finished: score 1500, 2 stars \\(passed\\); best 2 stars, score 1500 \\(was never finished\\); dawn_2 unlocked$", "the finished level is logged with its stars, score and unlock")
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 3, Endless best 0, Time Attack best 0, 1 levels finished \\(2 stars\\), music 70, sfx 80$", "the finished level is saved at once")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("levels") == {"dawn_1": {"stars": 2.0, "score": 1500.0}}, "the save holds the level's best", str(saved))
	from = _log.size()
	_check(not _game.record_level(dawn_1, 900) and _game.progress["dawn_1"].stars == 2 and _game.progress["dawn_1"].score == 1500, "a lower replay keeps the best stars and score", "%d/%d" % [_game.progress["dawn_1"].stars, _game.progress["dawn_1"].score])
	_check_logged(from, "^\\[Game\\] Level dawn_1 finished: score 900, 1 stars \\(passed\\); best 2 stars, score 1500 \\(was 2 stars, score 1500\\)$", "a replay is logged with the best it keeps")
	_check(not _game.record_level(Content.level("dawn_2"), 0) and _game.progress["dawn_2"].stars == 0, "a level finished with 0 stars is recorded, not passed", "")
	_check_logged(from, "^\\[Game\\] Level dawn_2 finished: score 0, 0 stars \\(not passed\\); best 0 stars, score 0 \\(was never finished\\)$", "a level not passed is logged as such, unlocking nothing")
	_check(_game.record_level(dawn_1, 2100) and _game.progress["dawn_1"].stars == 3, "a better replay raises the best", "")
	_game.progress = {}
	_game.load_game()
	_check(_game.progress.size() == 2 and _game.progress["dawn_1"].stars == 3 and _game.progress["dawn_1"].score == 2100 and _game.progress["dawn_2"].stars == 0, "the progress survives a reload", str(_game.progress.keys()))
	_clear_tool_save()


## A version 1 save (the Endless best only) is upgraded through version 2 to version 3: the
## best is kept as the Endless best (Time Attack 0), no level is finished, the settings take
## their defaults, each step is logged, nothing is reported or backed up, and the upgraded
## save is written back at once.
func _test_save_v1_migrates_to_v3() -> void:
	_clear_tool_save()
	var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "best_endless": 777}))
	file.close()
	var errors := _game.reported_errors.size()
	var from := _log.size()
	_game.music_volume = 5
	_game.load_game()
	_check(_game.bests == {"endless": 777, "time_attack": 0} and _game.progress.is_empty() and _game.music_volume == GameState.DEFAULT_MUSIC_VOLUME and _game.sfx_volume == GameState.DEFAULT_SFX_VOLUME and not _game.music_muted and not _game.sfx_muted,
		"a v1 save migrates keeping the Endless best, no levels, default settings", "bests %s, %d levels, music %d" % [_game.bests, _game.progress.size(), _game.music_volume])
	_check(_game.reported_errors.size() == errors and not FileAccess.file_exists(_game.backup_path()), "a migrated save is not reported or backed up", str(_game.reported_errors.slice(errors)))
	_check_logged(from, "^\\[Game\\] Save upgrade 1 -> 2: Endless best 777 kept, no campaign levels finished yet, default settings$", "the migration step is logged")
	_check_logged(from, "^\\[Game\\] Upgraded the save to version 2$", "the step to version 2 is logged")
	_check_logged(from, "^\\[Game\\] Save upgrade 2 -> 3: Endless best 777 kept as bests\\.endless, Time Attack best 0$", "the step 2 -> 3 is logged")
	_check_logged(from, "^\\[Game\\] Upgraded the save to version 3$", "the step to version 3 is logged")
	_check_logged(from, "^\\[Game\\] Loaded save from user://tool_save\\.json: version 3, Endless best 777, Time Attack best 0, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the migrated save's load is logged")
	_check_logged(from, "^\\[Game\\] Writing the save upgraded from version 1 as version 3$", "writing the upgraded save is logged")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 3.0 and saved.get("bests") == {"endless": 777.0, "time_attack": 0.0} and not saved.has("best_endless") and saved.get("levels") == {} and saved.get("settings") == {"music": 70.0, "sfx": 80.0, "music_muted": false, "sfx_muted": false}, "the upgraded save is written as version 3", str(saved))
	_clear_tool_save()


## A version 2 save (the Endless best, campaign progress and settings) is upgraded to
## version 3: its Endless best becomes bests.endless (Time Attack 0), its progress and
## settings are kept, the step is logged, nothing is reported or backed up, and it is
## written back at once.
func _test_save_v2_migrates_to_v3() -> void:
	_clear_tool_save()
	var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 2, "best_endless": 4321, "levels": {"dawn_1": {"stars": 3, "score": 2100}}, "settings": {"music": 30, "sfx": 0, "music_muted": true, "sfx_muted": false}}))
	file.close()
	var errors := _game.reported_errors.size()
	var from := _log.size()
	_game.load_game()
	_check(_game.bests == {"endless": 4321, "time_attack": 0} and _game.progress.keys() == ["dawn_1"] and _game.progress["dawn_1"].stars == 3 and _game.progress["dawn_1"].score == 2100 and _game.music_volume == 30 and _game.sfx_volume == 0 and _game.music_muted and not _game.sfx_muted,
		"a v2 save migrates keeping the Endless best, the campaign progress and the settings", "bests %s, %s, music %d" % [_game.bests, _game.progress.keys(), _game.music_volume])
	_check(_game.reported_errors.size() == errors and not FileAccess.file_exists(_game.backup_path()), "a migrated v2 save is not reported or backed up", str(_game.reported_errors.slice(errors)))
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Game] Save upgrade 1 -> 2")), "a v2 save takes only the step 2 -> 3", "a 1 -> 2 line")
	_check_logged(from, "^\\[Game\\] Save upgrade 2 -> 3: Endless best 4321 kept as bests\\.endless, Time Attack best 0$", "the v2 -> v3 step is logged")
	_check_logged(from, "^\\[Game\\] Writing the save upgraded from version 2 as version 3$", "writing the v2 save as v3 is logged")
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 3, Endless best 4321, Time Attack best 0, 1 levels finished \\(3 stars\\), music 30 muted, sfx 0$", "the upgraded v2 save is written back at once")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 3.0 and saved.get("bests") == {"endless": 4321.0, "time_attack": 0.0} and not saved.has("best_endless") and saved.get("levels") == {"dawn_1": {"stars": 3.0, "score": 2100.0}}, "the upgraded v2 save is written as version 3", str(saved))
	_clear_tool_save()


## The settings (volumes and mutes) round-trip through the save; a save whose settings or
## levels are malformed is corrupt (backed up, reported, fresh); a campaign entry naming an
## unknown level, or with stars or a score out of range (or not an entry), is reported with
## its key and dropped while the rest of the save loads.
func _test_save_settings_and_bad_entries() -> void:
	_clear_tool_save()
	_game.music_volume = 30
	_game.sfx_volume = 0
	_game.music_muted = true
	_game.progress["noon_2"] = Campaign.Record.new(1, 4000)
	_game.save_game()
	_game.music_volume = 70
	_game.sfx_volume = 80
	_game.music_muted = false
	_game.progress = {}
	_game.load_game()
	_check(_game.music_volume == 30 and _game.sfx_volume == 0 and _game.music_muted and not _game.sfx_muted and _game.progress.has("noon_2") and _game.progress["noon_2"].score == 4000, "settings and progress survive a save and reload", "music %d, sfx %d, muted %s" % [_game.music_volume, _game.sfx_volume, _game.music_muted])
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	var levels := {
		"dawn_1": {"stars": 2, "score": 1500}, "dusk_9": {"stars": 1, "score": 10}, "dawn_2": {"stars": 4, "score": 10},
		"dawn_3": {"stars": 1, "score": -5}, "dawn_4": "lots", "dawn_5": {"stars": 1}, "dawn_6": {"stars": 1.5, "score": 3},
	}
	# Each drop names the key, the value stored and the problem.
	var expected := {
		"dusk_9": "{\"stars\":1,\"score\":10}: 'dusk_9' is not a level of levels.json", "dawn_2": "{\"stars\":4,\"score\":10}: stars 4 is not a whole number 0..3",
		"dawn_3": "{\"stars\":1,\"score\":-5}: score -5 is not a whole number 0..999999999", "dawn_4": "\"lots\": not an object",
		"dawn_5": "{\"stars\":1}: must be exactly [\"stars\", \"score\"]", "dawn_6": "{\"stars\":1.5,\"score\":3}: stars 1.5 is not a whole number 0..3",
	}
	var original := JSON.stringify({"version": 2, "best_endless": 42, "levels": levels, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}, "", false)
	var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	# An earlier corrupt-save backup must survive: the dropped entries' backup has its own name.
	file = FileAccess.open(_game.backup_path(), FileAccess.WRITE)
	file.store_string("earlier corrupt save")
	file.close()
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var from := _log.size()
	_game.load_game()
	_game.quiet_errors = false
	var reported := _game.reported_errors.slice(errors)
	var backup := _game.save_path.get_basename() + ".dropped.json"
	_check(_game.progress.keys() == ["dawn_1"] and _game.progress["dawn_1"].stars == 2 and _game.best(GameState.ENDLESS_MODE) == 42, "bad campaign entries are dropped and the rest of the save loads", "%s, bests %s" % [_game.progress.keys(), _game.bests])
	for id: String in expected:
		var line := "dropped the campaign entry levels.%s = %s" % [id, expected[id]]
		_check(reported.any(func(message: String) -> bool: return message.contains(line) and message.contains(_game.save_path)), "a bad entry is reported with its key and stored value: " + id, "\n".join(reported))
	var summary := "Save '%s': 6 campaign entries were dropped (see the log); the original is kept as '%s'" % [_game.save_path, backup]
	_check(reported.size() == expected.size() + 1 and reported.back() == summary and error_label.visible and error_label.text == summary, "the screen says how many entries were dropped and where the original is", "%d reports, label '%s'" % [reported.size(), error_label.text])
	_check(FileAccess.get_file_as_string(backup) == original and FileAccess.get_file_as_string(_game.backup_path()) == "earlier corrupt save", "the original save is backed up byte for byte before the write-back, no other backup replaced", FileAccess.get_file_as_string(backup))
	_check_logged(from, "^\\[Game\\] Backed up the save with 6 dropped campaign entries to user://tool_save\\.dropped\\.json$", "the backup path is logged")
	var rewritten: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(rewritten is Dictionary and rewritten.get("levels") == {"dawn_1": {"stars": 2.0, "score": 1500.0}} and rewritten.get("version") == 3.0 and rewritten.get("bests") == {"endless": 42.0, "time_attack": 0.0}, "the v2 save is written back as v3 without the dropped entries", str(rewritten))
	# A second save with a bad entry: its backup takes the next free name.
	var second := JSON.stringify({"version": 2, "best_endless": 42, "levels": {"old_level": {"stars": 3, "score": 999}}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}})
	file = FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(second)
	file.close()
	_game.quiet_errors = true
	_game.load_game()
	_game.quiet_errors = false
	var next_backup := _game.save_path.get_basename() + ".dropped.2.json"
	_check(FileAccess.get_file_as_string(next_backup) == second and FileAccess.get_file_as_string(backup) == original and error_label.text.contains("1 campaign entry was dropped") and error_label.text.contains(next_backup), "a later drop backs up to the next free name, keeping the first backup", error_label.text)
	_clear_tool_save()
	var corrupt := {
		JSON.stringify({"version": 2, "best_endless": 0, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false}}): "settings must be exactly",
		JSON.stringify({"version": 2, "best_endless": 0, "levels": {}, "settings": {"music": 101, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "settings.music is not a whole number 0..100",
		JSON.stringify({"version": 2, "best_endless": 0, "levels": {}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": "yes"}}): "settings.sfx_muted is not true or false",
		JSON.stringify({"version": 2, "best_endless": 0, "levels": [], "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}}): "'levels' is not an object",
	}
	for text: String in corrupt:
		file = FileAccess.open(_game.save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		_game.quiet_errors = true
		errors = _game.reported_errors.size()
		_game.load_game()
		_game.quiet_errors = false
		var message: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
		_check(message.contains(corrupt[text]) and message.contains(_game.backup_path()) and FileAccess.get_file_as_string(_game.backup_path()) == text and _game.music_volume == GameState.DEFAULT_MUSIC_VOLUME, "save %s: backed up, reported, fresh" % corrupt[text], message)
	error_label.hide()
	_game.music_volume = GameState.DEFAULT_MUSIC_VOLUME
	_game.sfx_volume = GameState.DEFAULT_SFX_VOLUME
	_game.music_muted = false
	_clear_tool_save()


## A campaign level plays all its waves and only then ends on the results screen, however
## many birds get away (no escape limit, no early fail): dawn_2 loses all 12 of its birds
## (more than Endless's limit of 10) and still reaches wave 3. The run start, the waves and
## the end are logged with the level; the HUD shows wave x/N and the escapes without a limit;
## the sky takes the chapter's tint. A run with 0 stars is recorded as not passed: Next is
## hidden, Retry is focused and plays the level again.
func _test_campaign_level_plays_all_waves() -> void:
	_clear_tool_save()
	_game.progress["dawn_1"] = Campaign.Record.new(1, 900)
	var from := _log.size()
	var play := await _start_level("dawn_2")
	_check_logged(from, "^\\[Play\\] Run start: level dawn_2 \\(Dawn 2 of 6\\), seed 102 \\(3 waves, no escape limit, combo cap 3, 3 shells per hit, rival steals on, linger x1\\.00, aim 1\\.00 s, heckle cooldown 4\\.00 s, sky #ffe2c4, weather mist\\)$", "the level's run start is logged with its seed and settings")
	_check_logged(from, "^\\[Play\\] Wave 1 start: 4 birds \\(.+\\), \\d+ shells, speed x1\\.00 \\(wave 1 of 3, level dawn_2\\)$", "a level's wave start is logged with its place in the level")
	_check(_text(play, "Wave") == "Wave 1/3" and _text(play, "Escaped") == "Escaped 0", "the HUD shows wave x/N and the escapes without a limit", "%s, %s" % [_text(play, "Wave"), _text(play, "Escaped")])
	_check((play.get_node("World/Sky") as CanvasItem).modulate == Content.chapter("dawn").sky_tint, "the sky takes the chapter's tint", str((play.get_node("World/Sky") as CanvasItem).modulate))
	var waves_seen: Array[int] = []
	Engine.time_scale = FAST_TIME_SCALE
	for i in 9000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		if current_scene == play and play.wave != null and not play.wave.index in waves_seen:
			waves_seen.append(play.wave.index)
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	var stats := _game.flow_args
	_check(results != null and waves_seen == [1, 2, 3] and stats.get("level") == "dawn_2" and stats.get("escaped") == 12 and stats.get("stars") == 0, "the level plays all 3 waves, losing all 12 birds, and then ends on results", "waves %s, %s" % [waves_seen, stats])
	_check_logged(from, "^\\[Play\\] Run end: level dawn_2, seed 102, wave 3 of 3, score 0, 0 shots .*, 12 escaped \\(\\d+ stolen\\), rival score \\d+, 0 stars, level best 0 \\(0 stars\\)$", "the level's end is logged with its stars and best")
	_check_logged(from, "^\\[Game\\] Level dawn_2 finished: score 0, 0 stars \\(not passed\\); best 0 stars, score 0 \\(was never finished\\)$", "the finished level is recorded as not passed")
	_check(_game.progress.has("dawn_2") and not Campaign.is_unlocked(Content.level("dawn_3"), _game.progress), "0 stars unlocks nothing", "")
	if results == null:
		return
	var shown := ["Heading", "Stats/Stars", "Stats/Verdict", "Stats/Best"].map(func(n: String) -> String: return (results.get_node("Safe/" + n) as Label).text)
	_check(shown == ["Dawn 2: not passed", "0 stars: not passed", Results.verdict_text(0, stats["rival_score"]), "Level best 0 (0 of 3 stars)"], "the results show the level, its stars, the verdict and the level best", str(shown))
	var buttons := ["NextButton", "RetryButton", "LevelsButton", "PlayAgainButton", "TitleButton"].map(func(n: String) -> bool: return (results.get_node("Safe/" + n) as Control).visible)
	_check(buttons == [false, true, true, false, false] and (results.get_node("Safe/RetryButton") as Control).has_focus() and not (results.get_node("Safe/NewBest") as Control).visible, "without an open next level: Retry (focused) and Levels, no New best!", str(buttons))
	if not (results.get_node("Safe/RetryButton") as Control).has_focus():
		# Enter would press something else, which may start nothing to wait for.
		_clear_tool_save()
		return
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(current_scene is Play and _game.flow_args == {"level": "dawn_2"} and (current_scene as Play).level == Content.level("dawn_2"), "Retry plays the level again", str(_game.flow_args))
	_clear_tool_save()


## A level passed with stars: the results show the stars, the level best, New best! and the
## verdict, and Next (focused, the next level now open), Retry and Levels; Tab cycles them,
## Escape does nothing, and the screen fits the safe area. Levels opens the chapter's level
## select with the new best; Retry and the pause menu's Restart play the level again; Next
## plays the next level. The progress survives a reload.
func _test_campaign_pass_next_retry_levels() -> void:
	_clear_tool_save()
	var play := await _start_level("dawn_1")
	play.scoring.score = 1500
	Engine.time_scale = FAST_TIME_SCALE
	for i in 9000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var results := current_scene as Results
	var stats := _game.flow_args.duplicate()
	_check(results != null and stats.get("stars") == 2 and stats.get("best") == 1500 and stats.get("best_stars") == 2 and stats.get("new_best") == true and stats.get("next_level") == "dawn_2" and stats.get("save_error") == "", "a level passed with 2 stars opens dawn_2", str(stats))
	if results == null:
		return
	var shown := ["Heading", "Stats/Stars", "Stats/Verdict", "Stats/Best"].map(func(n: String) -> String: return (results.get_node("Safe/" + n) as Label).text)
	_check(shown == ["Dawn 1: passed", "2 of 3 stars", Results.verdict_text(1500, stats["rival_score"]), "Level best 1500 (2 of 3 stars)"], "the results show the stars earned, the verdict and the level best", str(shown))
	var next := results.get_node("Safe/NextButton") as Button
	var retry := results.get_node("Safe/RetryButton") as Button
	var levels := results.get_node("Safe/LevelsButton") as Button
	_check(next.visible and retry.visible and levels.visible and next.has_focus() and (results.get_node("Safe/NewBest") as Control).visible, "Next (focused), Retry and Levels, and New best!", str(root.gui_get_focus_owner()))
	for button: Button in [next, retry, levels]:
		var focus_style := button.get_theme_stylebox(&"focus")
		_check(button.focus_mode == Control.FOCUS_ALL and focus_style != null and not (focus_style is StyleBoxEmpty), "%s takes focus with a visible focus style" % button.text, str(focus_style))
	await _key(KEY_TAB)
	var after_tab := root.gui_get_focus_owner()
	await _key(KEY_TAB)
	var after_two := root.gui_get_focus_owner()
	await _key(KEY_TAB)
	_check(after_tab == retry and after_two == levels and root.gui_get_focus_owner() == next, "Tab cycles Next, Retry and Levels", "%s %s %s" % [after_tab, after_two, root.gui_get_focus_owner()])
	var gotos := _game.transition_log.size()
	await _key(KEY_ESCAPE)
	await process_frame
	_check(current_scene == results and _game.transition_log.size() == gotos, "Escape on the results screen starts nothing", str(current_scene))
	await _check_results_fit(results)
	await _tap(levels)
	await _game.transition_finished
	var select := current_scene as LevelSelect
	_check(select != null and _game.flow_args == {"chapter": "dawn", "level": "dawn_1"} and (select.get_node("Safe/Level1") as Control).has_focus(), "Levels opens the chapter's level select on the level just played (not the last open one, dawn_2)", "%s, focus %s" % [_game.flow_args, root.gui_get_focus_owner()])
	if select != null:
		var texts := ["Level1", "Level2", "Level3"].map(func(n: String) -> String: return (select.get_node("Safe/" + n) as Button).text)
		_check(texts == ["Level 1\n2/3 stars, best 1500", "Level 2\nNew", "Level 3\nLocked"], "the level select shows the new best and the level it opened", str(texts))
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	await _tap(current_scene.get_node("Safe/RetryButton") as Control)
	await _game.transition_finished
	await process_frame
	var again := current_scene as Play
	_check(again != null and again.level == Content.level("dawn_1"), "Retry plays the level again", str(_game.flow_args))
	again.open_pause("test")
	await _tap(again.get_node("PauseLayer/PauseMenu/Panel/RestartButton") as Control)
	await _game.transition_finished
	await process_frame
	_check(current_scene is Play and current_scene != again and (current_scene as Play).level == Content.level("dawn_1") and not paused, "Restart in a level plays the same level again", str(_game.flow_args))
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(current_scene is Play and (current_scene as Play).level == Content.level("dawn_2"), "Next plays the next level", str(_game.flow_args))
	_game.progress = {}
	_game.load_game()
	_check(_game.progress.has("dawn_1") and _game.progress["dawn_1"].stars == 2 and _game.progress["dawn_1"].score == 1500, "the level's progress survives a reload", str(_game.progress.keys()))
	_clear_tool_save()


## A finished level whose save fails (the save path is unwritable) sets save_error, emits
## save_failed, is reported with the path, and its results say the progress could not be
## saved, with the reason; nothing logs it as saved.
func _test_campaign_save_failure() -> void:
	_clear_tool_save()
	var failed: Array[String] = []
	var record := func(why: String) -> void: failed.append(why)
	_game.save_failed.connect(record)
	var play := await _start_level("dawn_1")
	play.scoring.score = 900
	_game.save_path = UNWRITABLE_SAVE_PATH
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var from := _log.size()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 9000:
		if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	_game.quiet_errors = false
	_game.save_path = GameState.TOOL_SAVE_PATH
	_game.save_failed.disconnect(record)
	var results := current_scene as Results
	var reason: String = _game.flow_args.get("save_error", "")
	_check(results != null and reason.begins_with("cannot open the save file") and failed == [reason] and _game.save_error == reason, "a failed level save sets save_error and emits save_failed", "%s / %s" % [failed, _game.flow_args])
	var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(UNWRITABLE_SAVE_PATH in reported, "the failed level save is reported with the save path", reported)
	if results != null:
		var notice := results.get_node("Safe/SaveError") as Label
		_check(notice.visible and notice.text == Results.PROGRESS_SAVE_ERROR_TEXT % reason, "the results say the progress could not be saved, with the reason", notice.text)
	_check_logged(from, "^\\[Play\\] Run end: level dawn_1, .*, 1 stars, level best 900 \\(1 stars\\) \\(new best\\), not saved: cannot open the save file", "the level's end log says it was not saved")
	_check(not Array(_log.since(from)).any(func(l: String) -> bool: return l.begins_with("[Game] Saved to")), "nothing logs the failed level save as saved", "a Saved line")
	_game.save_error = ""
	(_game.get_node("Fade/ErrorLabel") as Label).hide()
	_clear_tool_save()


## A level that does not exist cannot start: the error is reported (log and error label),
## nothing runs, and the menu offers only Quit to title.
func _test_campaign_unknown_level() -> void:
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	_game.goto(GameState.Flow.PLAY, {"level": "dusk_9"})
	await _game.transition_finished
	await process_frame
	_game.quiet_errors = false
	var play := current_scene as Play
	var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(reported == "Cannot start level 'dusk_9': no such level in levels.json" and (_game.get_node("Fade/ErrorLabel") as Label).visible, "an unknown level is reported", reported)
	_check(play != null and play.wave == null and play.is_paused() and (play.get_node("PauseLayer/PauseMenu/Panel/ResumeButton") as Button).disabled and (play.get_node("PauseLayer/PauseMenu/Panel/RestartButton") as Button).disabled and (play.get_node("PauseLayer/PauseMenu/Panel/QuitButton") as Button).has_focus(), "nothing runs; only Quit to title is offered", str(root.gui_get_focus_owner()))
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE and not paused, "Quit leaves the level that could not start", str(_game.state))
	(_game.get_node("Fade/ErrorLabel") as Label).hide()


## In a level the rival waits linger_time x the chapter's rival_linger_scale (dawn 1.0, noon
## 0.9, night 0.7) before his cue, which still runs the full aim_time (at least 0.5 s).
func _test_campaign_rival_linger_scale() -> void:
	var aim := Content.rival_lines().aim_time
	for level_id: String in ["dawn_1", "noon_1", "night_1"]:
		var play := await _start_level(level_id)
		var scale := Content.chapter(Content.level(level_id).chapter).rival_linger_scale
		var linger := Content.bird("goose").linger_time * scale
		var from := _log.size()
		var bird := await _spawn_flying(play, 180, linger - 0.02)
		for i in 10:
			if bird.is_cued():
				break
			await process_frame
		_check(is_equal_approx(play.linger_scale, scale) and bird.is_cued() and bird.cue_age >= linger and bird.cue_age <= linger + FRAME + 0.001, "%s: the cue starts at linger_time x %.1f" % [level_id, scale], "cue_age %.3f, linger %.3f" % [bird.cue_age, linger])
		_check_logged(from, "^\\[Play\\] Aim cue on goose #%d: age [\\d.]+ \\(linger %.2f s\\), the rival fires in 1\\.00 s " % [bird.number, linger], "%s: the cue logs the scaled linger" % level_id)
		var cued := 0.0
		for i in roundi(aim * 60.0) + 10:
			if not bird.is_flying():
				break
			cued = bird.age - bird.cue_age
			await process_frame
		_check(bird.stolen and cued >= aim - FRAME - 0.001 and aim >= Content.AIM_TIME_MIN, "%s: the cue still runs aim_time before the steal" % level_id, "cued %.3f" % cued)


## The verdict: a win when the score beats the rival's, a loss below it, a tie when equal;
## a run without rival steals shows none. Stars read "N of 3 stars" (0: not passed).
func _test_results_verdict() -> void:
	_check(Results.verdict_text(500, 300) == "You 500 vs rival 300: you win!" and Results.verdict_text(100, 300) == "You 100 vs rival 300: the rival wins" and Results.verdict_text(200, 200) == "You 200 vs rival 200: a tie",
		"the verdict is a win, a loss or a tie", Results.verdict_text(200, 200))
	_check(Results.stars_text(0) == "0 stars: not passed" and Results.stars_text(1) == "1 of 3 stars" and Results.stars_text(3) == "3 of 3 stars", "the stars text", Results.stars_text(0))
	var stats := {"mode": "endless", "score": 40, "shots": 2, "hits": 1, "kills": 1, "pigeons": 0, "escaped": 10, "stolen": 0, "rival_score": 0, "rival_line": "Not bad.", "rival_steals": false, "best": 100, "new_best": false, "save_error": ""}
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	_check(not (current_scene.get_node("Safe/Stats/Verdict") as Control).visible, "a run without rival steals shows no verdict", "shown")
	stats["rival_steals"] = true
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	var verdict := current_scene.get_node("Safe/Stats/Verdict") as Label
	_check(verdict.visible and verdict.text == "You 40 vs rival 0: you win!", "a run with rival steals shows the verdict", verdict.text)
	await _open_title()


## Chapter select: the four chapters with their stars out of 18; a chapter whose level 1 is
## locked says Locked and cannot be started by a touch or Enter; the last open chapter is
## focused; Back goes to the title. Every button is at least 44x44, focusable with a visible
## focus style and inside the safe area at 16:9, 19.5:9, 4:3 and under a notch.
func _test_chapter_select() -> void:
	_clear_tool_save()
	var from := _log.size()
	_game.goto(GameState.Flow.CHAPTER_SELECT)
	await _game.transition_finished
	await process_frame
	var screen := current_scene as ChapterSelect
	var buttons: Array[Button] = []
	for i in 4:
		buttons.append(screen.get_node("Safe/Chapter%d" % (i + 1)) as Button)
	var back := screen.get_node("Safe/BackButton") as Button
	var texts := buttons.map(func(button: Button) -> String: return button.text)
	_check(texts == ["Dawn\n0/18 stars", "Noon\nLocked", "Sunset\nLocked", "Night\nLocked"] and buttons.map(func(button: Button) -> bool: return button.disabled) == [false, true, true, true], "at first only dawn is open, with its stars out of 18", str(texts))
	_check(buttons[0].has_focus() and not buttons[0].has_focus(true), "the last open chapter is focused on arrival, ring hidden", str(root.gui_get_focus_owner()))
	_check_logged(from, "^\\[ChapterSelect\\] Chapter dawn at \\[P: .*\\] \\(open, 0 stars\\)$", "the chapter buttons' rects are logged")
	buttons.append(back)
	await _check_select_layout(screen, buttons)
	buttons.pop_back()
	var gotos := _game.transition_log.size()
	await _tap(buttons[1])
	buttons[3].grab_focus()
	await _key(KEY_ENTER)
	await process_frame
	_check(_game.transition_log.size() == gotos and current_scene == screen, "a locked chapter cannot be started by a touch or Enter", str(_game.transition_log.slice(gotos)))
	back.grab_focus()
	await _key(KEY_ENTER)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE, "Back goes to the title", str(_game.state))
	for index in range(1, 7):
		_game.progress["dawn_%d" % index] = Campaign.Record.new(3, 20000)
	_game.goto(GameState.Flow.CHAPTER_SELECT)
	await _game.transition_finished
	await process_frame
	screen = current_scene as ChapterSelect
	var dawn := screen.get_node("Safe/Chapter1") as Button
	var noon := screen.get_node("Safe/Chapter2") as Button
	_check(dawn.text == "Dawn\n18/18 stars" and noon.text == "Noon\n0/18 stars" and not noon.disabled and noon.has_focus() and (screen.get_node("Safe/Chapter3") as Button).disabled, "passing dawn_6 opens noon, now focused", "%s / %s" % [dawn.text, noon.text])
	await _tap(dawn)
	await _game.transition_finished
	_check(current_scene is LevelSelect and _game.flow_args == {"chapter": "dawn"}, "a chapter opens its level select", str(_game.flow_args))
	_clear_tool_save()


## Level select: the chapter's six levels with their best stars and score (New when never
## finished, the boss level marked); a locked level says Locked and cannot be started by a
## touch or Enter; the last open level is focused; a level starts it; Back goes to the
## chapter select. Layout as for the chapter select.
func _test_level_select() -> void:
	_clear_tool_save()
	_game.progress["dawn_1"] = Campaign.Record.new(2, 1500)
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "dawn"})
	await _game.transition_finished
	await process_frame
	var screen := current_scene as LevelSelect
	var buttons: Array[Button] = []
	for i in 6:
		buttons.append(screen.get_node("Safe/Level%d" % (i + 1)) as Button)
	var back := screen.get_node("Safe/BackButton") as Button
	var texts := buttons.map(func(button: Button) -> String: return button.text)
	_check(texts == ["Level 1\n2/3 stars, best 1500", "Level 2\nNew", "Level 3\nLocked", "Level 4\nLocked", "Level 5\nLocked", "Level 6 (boss)\nLocked"], "each level shows its best stars and score, New, Locked or boss", str(texts))
	_check(buttons.map(func(button: Button) -> bool: return button.disabled) == [false, false, true, true, true, true] and buttons[1].has_focus(), "locked levels are disabled; the last open level is focused", str(root.gui_get_focus_owner()))
	_check((screen.get_node("Safe/Heading") as Label).text == "Dawn: 2/18 stars", "the heading shows the chapter's stars", (screen.get_node("Safe/Heading") as Label).text)
	buttons.append(back)
	await _check_select_layout(screen, buttons)
	buttons.pop_back()
	var gotos := _game.transition_log.size()
	await _tap(buttons[2])
	buttons[5].grab_focus()
	await _key(KEY_ENTER)
	await process_frame
	_check(_game.transition_log.size() == gotos and current_scene == screen, "a locked level cannot be started by a touch or Enter", str(_game.transition_log.slice(gotos)))
	await _tap(back)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.CHAPTER_SELECT, "Back goes to the chapter select", str(_game.state))
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "dawn"})
	await _game.transition_finished
	await process_frame
	var from := _log.size()
	await _tap(current_scene.get_node("Safe/Level1") as Control)
	await _game.transition_finished
	await process_frame
	_check(current_scene is Play and (current_scene as Play).level == Content.level("dawn_1") and _game.flow_args == {"level": "dawn_1"}, "a level starts it", str(_game.flow_args))
	_check_logged(from, "^\\[LevelSelect\\] Level dawn_1 pressed; starting it$", "the level press is logged")
	_clear_tool_save()


## A save whose dropped entries cannot be backed up (every backup name is taken) is not
## written back: the original stays on disk, the failure is reported on screen with the
## count, and nothing claims a write-back.
func _test_save_dropped_backup_failure() -> void:
	_clear_tool_save()
	var original := JSON.stringify({"version": 2, "best_endless": 7, "levels": {"dawn_1": {"stars": 2, "score": 300}, "old_level": {"stars": 3, "score": 999}, "dawn_2": {"stars": 9, "score": 5}}, "settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}})
	var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	for n in range(1, GameState.DROPPED_BACKUPS_MAX + 1):
		var taken := FileAccess.open(_game.save_path.get_basename() + (".dropped.json" if n == 1 else ".dropped.%d.json" % n), FileAccess.WRITE)
		taken.store_string("earlier backup %d" % n)
		taken.close()
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var from := _log.size()
	_game.load_game()
	_game.quiet_errors = false
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	var reported: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(reported.contains("2 campaign entries were dropped") and reported.contains("could not be backed up") and reported.contains("the save is left as it is") and error_label.text == reported, "a failed backup is reported on screen with the count", reported)
	_check(FileAccess.get_file_as_string(_game.save_path.get_basename() + ".dropped.json") == "earlier backup 1", "no earlier backup is replaced", "")
	_check(FileAccess.get_file_as_string(_game.save_path) == original, "a failed backup leaves the original save on disk", FileAccess.get_file_as_string(_game.save_path))
	_check(not Array(_log.since(from)).any(func(l: String) -> bool: return l.begins_with("[Game] Saved to") or l.begins_with("[Game] Writing the save without")), "nothing is written back without a backup", "a write-back line")
	_check(_game.progress.keys() == ["dawn_1"] and _game.best(GameState.ENDLESS_MODE) == 7, "the rest of the save still loads", str(_game.progress.keys()))
	error_label.hide()
	_clear_tool_save()


## Returning to a select screen focuses the entry just left when it is open: the level
## select's Back focuses its chapter on the chapter select, and results' Levels focus the
## level just played (_test_campaign_pass_next_retry_levels). Otherwise (no entry passed,
## a locked one) the last open entry is focused, as on arrival from the title.
func _test_select_focus_returns() -> void:
	_clear_tool_save()
	for index in range(1, 7):
		_game.progress["dawn_%d" % index] = Campaign.Record.new(3, 20000)
	_game.progress["noon_1"] = Campaign.Record.new(1, 3000)
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "dawn"})
	await _game.transition_finished
	await process_frame
	_check((current_scene.get_node("Safe/Level6") as Control).has_focus(), "without a level to return to, the last open level is focused", str(root.gui_get_focus_owner()))
	await _tap(current_scene.get_node("Safe/BackButton") as Control)
	await _game.transition_finished
	await process_frame
	_check(_game.flow_args == {"chapter": "dawn"} and (current_scene.get_node("Safe/Chapter1") as Control).has_focus(), "Back focuses the chapter just left (dawn), not the last open one (noon)", "%s, focus %s" % [_game.flow_args, root.gui_get_focus_owner()])
	await _open_title()
	await _key(KEY_ENTER)
	await _game.transition_finished
	await process_frame
	_check(_game.flow_args == {} and (current_scene.get_node("Safe/Chapter2") as Control).has_focus(), "from the title the last open chapter is focused", str(root.gui_get_focus_owner()))
	_game.goto(GameState.Flow.CHAPTER_SELECT, {"chapter": "sunset"})
	await _game.transition_finished
	await process_frame
	_check((current_scene.get_node("Safe/Chapter2") as Control).has_focus(), "returning to a locked chapter falls back to the last open one", str(root.gui_get_focus_owner()))
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "dawn", "level": "dawn_3"})
	await _game.transition_finished
	await process_frame
	_check((current_scene.get_node("Safe/Level3") as Control).has_focus(), "returning to an open level focuses it", str(root.gui_get_focus_owner()))
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "noon", "level": "noon_4"})
	await _game.transition_finished
	await process_frame
	_check((current_scene.get_node("Safe/Level2") as Control).has_focus(), "returning to a locked level falls back to the last open one", str(root.gui_get_focus_owner()))
	_clear_tool_save()


## Every control of `controls` (a select screen's buttons): at least 44x44, focusable with a
## visible focus style, inside the safe area at 16:9, 19.5:9, 4:3 and under a notch, below
## the top HUD bar and not overlapping another.
func _check_select_layout(screen: Control, controls: Array[Button]) -> void:
	var safes: Array[Rect2] = [Rect2(), Rect2(), Rect2(), NOTCHED_SAFE_RECT, Rect2(0, (540 - RESULTS_MIN_SAFE_HEIGHT) / 2.0, 960, RESULTS_MIN_SAFE_HEIGHT)]
	var windows: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_19_5_9, LANDSCAPE_4_3, LANDSCAPE_19_5_9, LANDSCAPE_16_9]
	for i in windows.size():
		_game.safe_area_override = safes[i]
		root.size = windows[i]
		await process_frame
		await process_frame
		var safe := _game.safe_rect()
		var problems: Array[String] = []
		for control in controls:
			var rect := control.get_global_rect()
			if rect.size.x < MIN_TARGET or rect.size.y < MIN_TARGET or not safe.grow(0.5).encloses(rect) or rect.position.y < safe.position.y + Play.HUD_BAR_HEIGHT:
				problems.append("%s %s" % [control.name, rect])
			for other in controls:
				if other != control and rect.intersection(other.get_global_rect()).get_area() > 0.25:
					problems.append("%s overlaps %s" % [control.name, other.name])
			var style := control.get_theme_stylebox(&"focus")
			if control.focus_mode != Control.FOCUS_ALL or style == null or style is StyleBoxEmpty:
				problems.append("%s has no visible keyboard focus" % control.name)
		_check(problems.is_empty(), "%s %dx%d, safe %s: every button >= 44x44, focusable, inside the safe area, apart" % [screen.name, windows[i].x, windows[i].y, safe], "; ".join(problems))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame


## Starts campaign level `level_id` and waits until it is on screen.
func _start_level(level_id: String) -> Play:
	_game.start_level(level_id)
	await _game.transition_finished
	await process_frame
	return current_scene as Play


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
## The rival's steals are off meanwhile (he would shoot the bird at its linger_time).
func _escape_counts(play: Play, bird: Bird) -> Array[int]:
	var counted: Array[int] = [-1, -1]
	bird.escaped.connect(func(_b: Bird) -> void: counted[1] = play.escaped)
	play.mode.rival_steals = false
	Engine.time_scale = FAST_TIME_SCALE
	for i in 900:
		if not is_instance_valid(bird):
			break
		counted[0] = play.escaped
		await process_frame
	Engine.time_scale = 1.0
	play.mode.rival_steals = true
	return counted


## Spawns a `bird_id` with `bird_seed` just short of its linger_time (inside the field) and
## waits until the rival's aim cue on it has started.
func _cued_bird(play: Play, bird_seed: int, bird_id: String) -> Bird:
	var bird := await _spawn_flying(play, bird_seed, Content.bird(bird_id).linger_time - 0.02, bird_id)
	for i in 10:
		if bird.is_cued():
			break
		await process_frame
	return bird


## Starts a run of `mode_id` (Endless unless it says otherwise) with `run_seed` and waits
## until it is on screen.
func _start_run(run_seed: int, mode_id := GameState.ENDLESS_MODE) -> Play:
	_game.goto(GameState.Flow.PLAY, {"mode": mode_id, "seed": run_seed})
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
	var paths: Array[String] = [GameState.TOOL_SAVE_PATH, GameState.TOOL_SAVE_PATH.get_basename() + ".corrupt.json"]
	for n in range(1, GameState.DROPPED_BACKUPS_MAX + 1):
		paths.append(GameState.TOOL_SAVE_PATH.get_basename() + (".dropped.json" if n == 1 else ".dropped.%d.json" % n))
	for path in paths:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(path)
	for mode_id in GameState.BEST_MODES:
		_game.bests[mode_id] = 0
	_game.progress = {}


## The title's Campaign, Endless and Time Attack buttons, in that order.
func _title_buttons(title: Title) -> Array[Button]:
	var buttons: Array[Button] = []
	for button_name: String in ["CampaignButton", "EndlessButton", "TimeAttackButton"]:
		buttons.append(title.get_node("Safe/" + button_name) as Button)
	return buttons


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
