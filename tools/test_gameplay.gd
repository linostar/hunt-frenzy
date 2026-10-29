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
## The age a lower stand-in bird starts at: its own path STAND_IN_AGE seconds before its spawn
## point, so its art lies wholly under the grass (_test_bird_calls_on_appearing).
const STAND_IN_AGE := -0.5
## One frame at --fixed-fps 60.
const FRAME := 1.0 / 60.0

var _failures: Array[String] = []
## Each texture's opaque pixel corners, centred (_drawn_art_top), by texture path.
var _opaque_corners: Dictionary[String, PackedVector2Array] = {}
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
		# The checks that failed before the stuck test (it may hang because of one of them).
		for failure in _failures:
			printerr("test_gameplay: FAIL " + failure)
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
		_test_flight_straight_segments_and_turns,
		_test_flight_reflects_at_band_edges,
		_test_flight_crossing_keeps_its_wobble,
		_test_flight_per_bird_speed,
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
		_test_rival_footprint_and_poses,
		_test_rival_lit_per_backdrop,
		_test_rival_poses,
		_test_rival_one_cue_at_a_time,
		_test_rival_aim_gap,
		_test_rival_never_cues_a_short_window,
		_test_rival_cues_always_finish,
		_test_rival_laugh_waits_out_a_pause,
		_test_rival_laugh_before_results_blurt,
		_test_crosshair_cursor,
		_test_crosshair_under_rotate_overlay,
		_test_weather_is_visual_only,
		_test_backdrop_cycle_and_fade,
		_test_missing_backdrop_is_reported,
		_test_ui_theme_and_fonts,
		_test_menu_texts_fit_largest_values,
		_test_load_errors_reach_the_screen,
		_test_grass_draws_over_birds,
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
		_test_save_v1_migrates_to_v4,
		_test_save_v2_migrates_to_v4,
		_test_save_v3_migrates_to_v4,
		_test_save_reduce_motion_strict,
		_test_save_settings_and_bad_entries,
		_test_campaign_level_plays_all_waves,
		_test_campaign_pass_next_retry_levels,
		_test_campaign_save_failure,
		_test_campaign_unknown_level,
		_test_campaign_rival_linger_scale,
		_test_results_verdict,
		_test_results_stars_and_panels,
		_test_chapter_select,
		_test_level_select,
		_test_save_dropped_backup_failure,
		_test_select_focus_returns,
		_test_audio_buses_follow_settings,
		_test_audio_files_match_ids,
		_test_audio_music_per_screen,
		_test_audio_every_event_sound,
		_test_bird_calls_on_appearing,
		_test_title_geese_never_call,
		_test_audio_heckle_blurts,
		_test_time_attack_countdown,
		_test_pause_menu_mutes,
		_test_pause_holds_sounds_and_ducks_music,
		_test_audio_missing_files_reported,
		_test_dropped_taps_are_silent,
		_test_pause_keeps_every_held_sound,
		_test_frequent_sounds_vary_in_pitch,
		_test_audio_unloadable_files_reported,
		_test_settings_screen,
		_test_settings_over_paused_run,
		_test_credits_screen,
		_test_title_scenery_and_geese,
		_test_title_goose_shot,
		_test_transition_wipe_and_fade,
		_test_hit_stop,
		_test_feathers,
		_test_screen_shake,
		_test_popup_motion,
		_test_reduce_motion_everywhere,
		_test_slider_hold_cut_short,
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


## The title's Campaign, Endless and Time Attack buttons in a row and Settings and Credits
## in a row below them: at least 44x44, their text inside them, inside the safe area, with
## a visible focus style, at 16:9, 19.5:9 and 4:3; Campaign is focused on arrival (no ring),
## right moves Campaign -> Endless -> Time Attack -> Campaign, left goes the other way, Tab
## runs Campaign -> Endless -> Time Attack -> Settings -> Credits -> Campaign, Down from the
## first row reaches the second and Up returns.
func _test_title_button_layout() -> void:
	await _open_title()
	var title := current_scene as Title
	var buttons := _title_buttons(title)
	var campaign := buttons[0]
	var second_row: Array[Button] = [title.get_node("Safe/SettingsButton") as Button, title.get_node("Safe/CreditsButton") as Button]
	_check(campaign.has_focus(), "title focuses Campaign on arrival", str(root.gui_get_focus_owner()))
	_check(second_row.map(func(button: Button) -> String: return button.text) == ["Settings", "Credits"], "the title offers Settings and Credits", str(second_row.map(func(button: Button) -> String: return button.text)))
	for button: Button in buttons + second_row:
		var focus_style := button.get_theme_stylebox(&"focus")
		_check(focus_style != null and not (focus_style is StyleBoxEmpty), "%s has a visible focus style" % button.name, str(focus_style))
		_check(button.focus_mode == Control.FOCUS_ALL, "%s takes keyboard focus" % button.name, str(button.focus_mode))
	var names := buttons.map(func(button: Button) -> String: return button.text.get_slice("\n", 0))
	_check(names == ["Campaign", "Endless", "Time Attack"], "the title offers Campaign, Endless and Time Attack", str(names))
	_check(not campaign.has_focus(true), "the focus ring is hidden on arrival (no stray ring on phones)", "focus visible")
	for key: Key in [KEY_TAB, KEY_RIGHT, KEY_LEFT]:
		var order: Array[Button] = []
		match key:
			KEY_TAB:
				order.assign([buttons[1], buttons[2], second_row[0], second_row[1], buttons[0]])
			KEY_RIGHT:
				order.assign([buttons[1], buttons[2], buttons[0]])
			_:
				order.assign([buttons[2], buttons[1], buttons[0]])
		var reached: Array[String] = []
		for i in order.size():
			await _key(key)
			reached.append(str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else "none")
		_check(reached == order.map(func(button: Button) -> String: return str(button.name)) and campaign.has_focus(true), "%s cycles the focus through %d buttons, the ring shown" % [OS.get_keycode_string(key), order.size()], str(reached))
	var vertical: Array[String] = []
	for key: Key in [KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_DOWN]:
		await _key(key)
		vertical.append(str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else "none")
	_check(vertical == ["SettingsButton", "CreditsButton", "TimeAttackButton", "CreditsButton", "TimeAttackButton"], "Down and Up move between the two rows, Right along the second", str(vertical))
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		await process_frame
		for button: Button in buttons + second_row:
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
	buttons.append_array([title.get_node("Safe/SettingsButton") as Button, title.get_node("Safe/CreditsButton") as Button])
	_check(buttons.all(func(button: Button) -> bool: return NOTCHED_SAFE_RECT.encloses(button.get_global_rect())), "Campaign, Endless, Time Attack, Settings and Credits are clear of the notch", str(buttons.map(func(button: Button) -> Rect2: return button.get_global_rect())))
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
	_check(saved is Dictionary and saved.get("version") == 4.0 and GameState.SAVE_VERSION == 4 and saved.get("bests") == {"endless": 1234.0, "time_attack": 5678.0} and not saved.has("best_endless") and saved.get("settings", {}).get("reduce_motion") == false, "the save is version 4 with a best per mode and reduce_motion", str(saved))
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
		JSON.stringify({"version": 5, "best_endless": 5}): "version 5 is newer than this game's 4",
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
	_check_logged(from, "^\\[Play\\] Spawned goose #\\d+ \\(wave 1, seed -?\\d+, speed x[\\d.]+\\) at t [\\d.]+, fleeing \\(no shells\\)$", "a spawn is logged with its wave and seed")
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
## after Tab, Up/Down cycling Resume, Restart, Quit, Settings and the Music toggle.
func _test_pause_menu_keyboard() -> void:
	var play := await _start_run(32)
	play.open_pause("test")
	await process_frame
	var panel := play.get_node("PauseLayer/PauseMenu/Panel")
	var buttons: Array[Button] = [panel.get_node("ResumeButton"), panel.get_node("RestartButton"), panel.get_node("QuitButton"), panel.get_node("SettingsButton")]
	_check(buttons.map(func(b: Button) -> String: return b.text) == ["Resume", "Restart", "Quit to title", "Settings"], "the menu holds Resume, Restart, Quit to title and Settings", str(buttons.map(func(b: Button) -> String: return b.text)))
	for button in buttons:
		var rect := button.get_global_rect()
		var style := button.get_theme_stylebox(&"focus")
		_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET and button.focus_mode == Control.FOCUS_ALL and style != null and not (style is StyleBoxEmpty), "%s: >= 44x44, focusable, visible focus style" % button.text, str(rect))
	_check(buttons[0].has_focus() and not buttons[0].has_focus(true), "Resume is focused with the ring hidden on opening", "ring shown")
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == buttons[1] and buttons[1].has_focus(true), "Tab moves to Restart and shows the ring", str(root.gui_get_focus_owner()))
	var order := []
	for i in 5:
		await _key(KEY_DOWN)
		order.append((root.gui_get_focus_owner() as Button).text)
	_check(order == ["Quit to title", "Settings", "Music: on", "Resume", "Restart"], "Down cycles through the menu, Settings and its Music toggle", str(order))
	await _key(KEY_UP)
	_check(root.gui_get_focus_owner() == buttons[0], "Up moves back", str(root.gui_get_focus_owner()))
	await _key(KEY_UP)
	var music_toggle := panel.get_node("MusicToggle") as Button
	var sfx_toggle := panel.get_node("SfxToggle") as Button
	_check(root.gui_get_focus_owner() == music_toggle, "Up from Resume reaches the Music toggle", str(root.gui_get_focus_owner()))
	await _key(KEY_RIGHT)
	_check(root.gui_get_focus_owner() == sfx_toggle, "Right reaches the SFX toggle", str(root.gui_get_focus_owner()))
	await _key(KEY_UP)
	_check(root.gui_get_focus_owner() == buttons[3], "Up from the SFX toggle reaches Settings", str(root.gui_get_focus_owner()))
	await _key(KEY_DOWN)
	await _key(KEY_RIGHT)
	await _key(KEY_TAB)
	_check(root.gui_get_focus_owner() == buttons[0], "Tab from the SFX toggle wraps to Resume", str(root.gui_get_focus_owner()))
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
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 4, Endless best 100, Time Attack best 0, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the save is logged")
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
	var shown := _results_texts(results, ["Score", "Best", "Accuracy", "Shots", "Hits", "Escaped", "RivalScore", "Steals"])
	_check(shown == ["100", "Best 100", "100%", "1 of 1 shots", "1", "10 escaped (%d stolen)" % stolen, str(rival_score), Results.steals_text(stolen)], "the panels show the score and best, the accuracy and shots, the birds hit and escaped with the stolen ones, the rival's score and steals", str(shown))
	_check((results.get_node("%RivalPanel") as Control).visible and not (results.get_node("%Stars") as Control).visible and (results.get_node("Safe/Heading") as Label).text == Results.ENDLESS_HEADING, "Endless results show the Rival panel, no stars", "rival panel or stars")
	_check_results_hide_dropped_lines(results, str(stats.get("rival_line")))
	_check_logged(from, "^\\[Results\\] Score 100, accuracy 100%% \\(1 of 1 shots\\), 1 birds hit, 10 escaped, %d stolen, rival score %d, 0 pigeons hit, best 100, new best; rival: \"%s\"$" % [stolen, rival_score, stats.get("rival_line")], "the results log keeps the pigeons hit and the rival's line")
	_check_logged(from, "^\\[Results\\] Verdict: %s$" % Results.verdict_text(100, rival_score), "the results log keeps the verdict")
	_check((results.get_node("%NewBest") as Label).visible and not (results.get_node("Safe/SaveError") as Label).visible, "the results show the New best! badge (and no save problem)", "hidden")
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
	_check(not (current_scene.get_node("%NewBest") as Label).visible and _results_texts(current_scene as Results, ["Accuracy", "Shots"]) == [Results.NO_VALUE, "no shots"], "a run below the best shows no New best!, and a dash for no shots", str(_results_texts(current_scene as Results, ["Accuracy", "Shots"])))
	await _tap(current_scene.get_node("Safe/TitleButton") as Control)
	await _game.transition_finished
	_check(_game.state == GameState.Flow.TITLE, "Title goes to the title", str(_game.state))
	_clear_tool_save()


## With every element shown (the stars on a level, the panels, the New best! badge, a
## two-line SaveError), the results screen fits the safe area at 16:9, 4:3, under a notch
## with the iOS home-indicator inset (RESULTS_INSET_SAFE_RECT) and at
## RESULTS_MIN_SAFE_HEIGHT: each element inside it, its text inside its rect (a panel's
## texts inside the panel), no two overlapping (but the badge on the Score panel's
## corner), the buttons >= 44x44.
func _check_results_fit(results: Results) -> void:
	var save_error := results.get_node("Safe/SaveError") as Label
	save_error.text = Results.SAVE_ERROR_TEXT % "the file could not be written because the disk is full, so the new best will be lost when the game is closed"
	save_error.show()
	var new_best := results.get_node("%NewBest") as Label
	var had_new_best := new_best.visible
	new_best.show()
	var names: Array[String] = ["Heading", "Body/Panels/ScorePanel", "Body/Panels/AccuracyPanel", "Body/Panels/BirdsPanel", "Body/Panels/ScorePanel/Corner/NewBest", "SaveError"]
	# The Rival panel and the stars show only in some runs (a run with steals, a level);
	# the buttons are the variant's.
	for optional: String in ["Body/Panels/RivalPanel", "Body/Stars/Star1", "Body/Stars/Star2", "Body/Stars/Star3", "NextButton", "RetryButton", "LevelsButton", "PlayAgainButton", "TitleButton"]:
		if (results.get_node("Safe/" + optional) as Control).is_visible_in_tree():
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
			if not item.is_visible_in_tree() or not safe.grow(0.5).encloses(rect):
				problems.append("%s %s not shown inside the safe area" % [n, rect])
			if item is Label:
				var label := item as Label
				var lines := label.get_visible_line_count()
				var text_height := lines * label.get_line_height() + (lines - 1) * label.get_theme_constant("line_spacing")
				if text_height > rect.size.y + 0.5:
					problems.append("%s text %.1f high in %s" % [n, text_height, rect])
				if label == save_error and lines != 2:
					problems.append("SaveError shows %d lines, not its two" % lines)
			elif item is Button and (rect.size.x < MIN_TARGET or rect.size.y < MIN_TARGET):
				problems.append("%s %s under 44x44" % [n, rect])
			elif item is PanelContainer:
				# A panel grows to fit its texts; each text must still be inside it.
				for text: Label in item.find_children("*", "Label", true, false):
					if text != new_best and not rect.grow(0.5).encloses(text.get_global_rect()):
						problems.append("%s text '%s' %s outside the panel" % [n, text.text, text.get_global_rect()])
		for a in names.size():
			for b in range(a + 1, names.size()):
				# The New best! badge sits on the Score panel's corner by design.
				if names[a] == "Body/Panels/ScorePanel" and names[b].ends_with("NewBest"):
					continue
				if rects[a].intersection(rects[b]).get_area() > 0.25:
					problems.append("%s %s overlaps %s %s" % [names[a], rects[a], names[b], rects[b]])
		_check(problems.is_empty(), "%s: the results screen (every element shown) fits the safe area %s without overlap" % [cases[i], safe], "; ".join(problems))
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame
	save_error.hide()
	new_best.visible = had_new_best


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


## A hit goose stops on its hit frame upright and facing the way it flew (the whole basis,
## not only the rotation: a left-facing transform is rotation + PI with scale (1, -1), so
## zeroing the rotation alone turns it upside down), then dives head-first seen from behind:
## its dive frame (drawn upright, head down, back to the camera), neither turned nor mirrored.
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
		# The kill's hit stop holds it a little past HIT_HOLD: wait for the fall, then 2 frames.
		var waited := 0
		while is_instance_valid(bird) and bird.state != Bird.State.FALLING and waited < 60:
			await process_frame
			waited += 1
		for i in 2:
			await process_frame
		var plain := is_instance_valid(bird) and bird.transform.x.is_equal_approx(Vector2.RIGHT) and bird.transform.y.is_equal_approx(Vector2.DOWN)
		_check(is_instance_valid(bird) and bird.state == Bird.State.FALLING and bird.position.y > hit_y and plain, label + ": it falls on its upright back view, neither turned nor mirrored", "x %s, y %s" % [bird.transform.x, bird.transform.y] if is_instance_valid(bird) else "gone")
		var shown := (bird.get_node("Sprite") as Sprite2D).texture.resource_path if is_instance_valid(bird) else "gone"
		_check(shown == goose.texture_path("dive"), label + ": it shows its dive frame (its back, wings folded, head down) as it falls", shown)


## The grass hides what is behind it: a shot on the grass (at or below the grass line the
## art is solid from) hits no goose, even inside its hitbox; a shot on the part of a rising
## goose above the grass hits it.
func _test_play_grass_hides_geese() -> void:
	var play := await _start_run(27)
	var grass := play.get_node("World/Backdrop/Grass") as Control
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
	_check((results.get_node("%NewBest") as Label).visible and notice.is_visible_in_tree() and notice.text == Results.SAVE_ERROR_TEXT % reason, "the results say New best! and that it could not be saved, with the reason", "%s '%s'" % [notice.visible, notice.text])
	var below := (results.get_node("Safe/PlayAgainButton") as Control).get_global_rect()
	var above := (results.get_node("Safe/Body/Panels") as Control).get_global_rect()
	_check(notice.get_global_rect().end.y <= below.position.y + 0.5 and notice.get_global_rect().position.y >= above.end.y - 0.5 and notice.get_visible_line_count() == notice.get_line_count(), "the notice fits between the panels and Play again, every line shown", "%s, %d of %d lines" % [notice.get_global_rect(), notice.get_visible_line_count(), notice.get_line_count()])
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
	while play.wave.index == 1 and frames < 10:
		await process_frame
		frames += 1
	# The last kill's hit stop holds everything, the wave's end included, for its own time.
	_check(play.scoring.kills == 3 and play.wave.index == 2 and frames <= 1 + ceili(Play.HIT_STOP_TIME / FRAME), "the next wave starts as soon as the last one is cleared (after the last kill's hit stop)", "%d kills, wave %d after %d frames" % [play.scoring.kills, play.wave.index, frames])
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
	# Newest first, each held still while shot: a shot hits the frontmost (newest) bird under
	# it, so no older bird in the way takes it, and the touch (handled a frame later) lands.
	var targets := play.flying_birds()
	targets.reverse()
	for bird in targets:
		if bird == leftover:
			continue
		bird.set_process(false)
		for shot in bird.spec.hp:
			if bird.is_flying():
				await _touch(_global(play, bird.transform * LOCAL_BODY))
		bird.set_process(true)
	var frames := 0
	while play.wave.index == 2 and frames < 10:
		await process_frame
		frames += 1
	_check(play.wave.index == 3 and frames <= 1 + ceili(Play.HIT_STOP_HEAVY_TIME / FRAME) and leftover.is_flying(), "a wave ends on its own birds: a lost wave's leftover does not hold up the next", "wave %d after %d frames, leftover flying %s" % [play.wave.index, frames, leftover.is_flying()])
	var score := play.scoring.score
	var from := _log.size()
	leftover.set_process(true)
	leftover.age = IN_FIELD_AGE
	# It was held by the hit stops while its processing was off; let the hold run out.
	for i in 10:
		if not leftover.is_held():
			break
		await process_frame
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
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 4, Endless best 0, Time Attack best 100, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the new best is saved at once")
	_check_logged(from, "^\\[Play\\] Run end: mode time_attack, seed 56, wave \\d+, time used 60\\.00 of 60\\.00 s, score 100, 1 shots \\(1 hits, 0 misses, 0 pigeons hit\\), 1 birds killed, 0 refused, %d escaped \\(0 stolen\\), rival score 0, best 100 \\(new best\\)$" % stats.get("escaped", -1), "the run end is logged with the waves, the time used and the score")
	_check_logged(from, "^\\[Results\\] Mode time_attack: best 100, new best$", "the results log the mode and its best")
	var shown := _results_texts(results, ["Score", "Best", "Accuracy", "Shots", "Hits", "Escaped"])
	_check(shown == ["100", "Best 100", "100%", "1 of 1 shots", "1", "%d escaped" % stats.get("escaped", -1)], "the panels show the score and the Time Attack best, the accuracy, birds hit and escaped (no stolen count)", str(shown))
	_check((results.get_node("Safe/Heading") as Label).text == Results.TIMED_HEADING and not (results.get_node("%RivalPanel") as Control).visible and not (results.get_node("%Stars") as Control).visible and (results.get_node("%NewBest") as Control).visible, "Time up, New best!, no Rival panel, no stars", "heading, rival panel or stars")
	_check_results_hide_dropped_lines(results, str(stats.get("rival_line")))
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
		_check((results.get_node("%NewBest") as Label).visible and notice.visible and notice.text == Results.SAVE_ERROR_TEXT % reason, "the Time Attack results say New best! and that it could not be saved", notice.text)
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
## Flight.ZIGZAG_INTERVAL_MAX seconds from the start of its cruise until it flees (20
## seeds), and from its first turn on its path differs from the rise path of the same
## seed; a rise bird of the same speed holds its heading through such a window.
func _test_flight_zigzag_reverses() -> void:
	var zigzag := Content.bird("zigzag")
	var step := 1.0 / 120.0
	var problems: Array[String] = []
	for bird_seed in 20:
		var entry := Flight.entry_age(zigzag, bird_seed, Play.FIELD)
		var last_turn := entry
		var last_sign := 0.0
		var age := entry
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
	# The seeded turns alone (Flight.turn_ages; unlike the velocity, they leave out the
	# bounces off the field's edges): every interval from the start of the cruise lies in
	# ZIGZAG_INTERVAL_MIN..MAX, each reverses the horizontal travel, and the first interval
	# differs between seeds.
	var intervals: Array[float] = []
	var unturned: Array[String] = []
	var first_intervals: Dictionary[int, bool] = {}
	for bird_seed in 20:
		var entry := Flight.entry_age(zigzag, bird_seed, Play.FIELD)
		var turns := Flight.turn_ages(zigzag, bird_seed, entry, zigzag.flee_time)
		var previous := entry
		for turn in turns:
			intervals.append(turn - previous)
			previous = turn
			var before := Flight._offset(zigzag, bird_seed, turn - 0.01, entry, Flight._first_heading(zigzag, bird_seed, Play.FIELD, Flight.NOT_LAUNCHED, Vector2.ZERO))
			var at := Flight._offset(zigzag, bird_seed, turn, entry, Flight._first_heading(zigzag, bird_seed, Play.FIELD, Flight.NOT_LAUNCHED, Vector2.ZERO))
			var after := Flight._offset(zigzag, bird_seed, turn + 0.01, entry, Flight._first_heading(zigzag, bird_seed, Play.FIELD, Flight.NOT_LAUNCHED, Vector2.ZERO))
			if signf(at.x - before.x) != -signf(after.x - at.x):
				unturned.append("seed %d at %.2f" % [bird_seed, turn])
		if not turns.is_empty():
			first_intervals[roundi((turns[0] - entry) * 100.0)] = true
	var outside := intervals.filter(func(interval: float) -> bool: return interval < Flight.ZIGZAG_INTERVAL_MIN or interval > Flight.ZIGZAG_INTERVAL_MAX)
	_check(intervals.size() >= 20 * 6 and outside.is_empty(), "every zigzag interval lies in %.2f..%.2f s" % [Flight.ZIGZAG_INTERVAL_MIN, Flight.ZIGZAG_INTERVAL_MAX], "%d intervals, outside: %s" % [intervals.size(), outside])
	_check(unturned.is_empty(), "every zigzag turn reverses its horizontal travel", str(unturned))
	_check(first_intervals.size() >= 10, "the zigzag intervals vary between seeds", "%d distinct first intervals over 20 seeds: %s" % [first_intervals.size(), first_intervals.keys()])
	var entry_3 := Flight.entry_age(zigzag, 3, Play.FIELD)
	var first_turn := Flight.turn_ages(zigzag, 3, entry_3, zigzag.flee_time)[0]
	var start := Flight.position(zigzag, 3, 0.0, Play.FIELD)
	var entered := Flight.position(zigzag, 3, entry_3, Play.FIELD)
	var later := Flight.position(zigzag, 3, first_turn + 0.5, Play.FIELD)
	# The same spec flying the rise pattern (restored below).
	zigzag.pattern = "rise"
	var rise_start := Flight.position(zigzag, 3, 0.0, Play.FIELD)
	var rise_entered := Flight.position(zigzag, 3, entry_3, Play.FIELD)
	var rise_later := Flight.position(zigzag, 3, first_turn + 0.5, Play.FIELD)
	var held := true
	var first_sign := signf(Flight.velocity(zigzag, 3, 0.1, Play.FIELD).x)
	for i in roundi(Flight.ZIGZAG_INTERVAL_MAX * 120.0):
		held = held and signf(Flight.velocity(zigzag, 3, 0.1 + i * step, Play.FIELD).x) == first_sign
	zigzag.pattern = "zigzag"
	_check(start.is_equal_approx(rise_start) and entered.is_equal_approx(rise_entered) and not later.is_equal_approx(rise_later), "the zigzag climbs in like a rise and departs from it after its first turn", "%s %s %s vs %s %s %s" % [start, entered, later, rise_start, rise_entered, rise_later])
	_check(held, "the rise pattern holds its heading through the same window", "turned")


## AC 1, 2 and 4 of the straight flight: between two turns (and away from a bounce) a
## bird's centre moves on a straight line at constant speed, so its tilt holds (20 seeds
## of the goose and of a launched gosling, every 0.25 s stretch inside a segment whose
## velocity never changes sign: no point is 0.5 units off the chord); a rise bird turns at
## seeded TURN_INTERVAL_MIN..MAX intervals from the start of its cruise to a heading
## FLIGHT_ANGLE_MIN..MAX from the horizontal; the same inputs give the same path.
func _test_flight_straight_segments_and_turns() -> void:
	var goose := Content.bird("goose")
	var gosling := Content.bird("gosling")
	var stretches := 0
	var bent: Array[String] = []
	var unsteady: Array[String] = []
	for launched: bool in [false, true]:
		var spec := gosling if launched else goose
		var from := Vector2(480, 250) if launched else Flight.NOT_LAUNCHED
		var heading := Flight.split_headings(2)[0] if launched else Vector2.ZERO
		for bird_seed in 20:
			var entry := Flight.entry_age(spec, bird_seed, Play.FIELD, 1.0, from, heading)
			var bounds := PackedFloat64Array([entry])
			bounds.append_array(Flight.turn_ages(spec, bird_seed, entry, spec.flee_time))
			for i in bounds.size() - 1:
				var t := bounds[i] + 0.02
				while t + 0.25 < bounds[i + 1] - 0.02:
					var points: Array[Vector2] = []
					var signs := {}
					var tilts := {}
					for k in 11:
						var age := t + 0.025 * k
						points.append(Flight.position(spec, bird_seed, age, Play.FIELD, 1.0, INF, from, heading))
						var moving := Flight.velocity(spec, bird_seed, age, Play.FIELD, 1.0, INF, from, heading)
						signs[Vector2(signf(moving.x), signf(moving.y))] = true
						tilts[snappedf(Flight.transform_at(spec, bird_seed, age, Play.FIELD, 1.0, INF, from, heading).get_rotation(), 0.001)] = true
					t += 0.25
					if signs.size() != 1:
						continue
					stretches += 1
					var chord := Geometry2D.get_closest_point_to_segment_uncapped(points[5], points[0], points[10]).distance_to(points[5])
					var worst := 0.0
					for point in points:
						worst = maxf(worst, Geometry2D.get_closest_point_to_segment_uncapped(point, points[0], points[10]).distance_to(point))
					var gaps := points[1].distance_to(points[0]) - points[10].distance_to(points[9])
					if worst >= 0.5 or chord >= 0.5 or absf(gaps) > 0.01:
						bent.append("%s seed %d at %.2f: %.2f off the chord, steps differ by %.3f" % [spec.id, bird_seed, t - 0.25, worst, gaps])
					if tilts.size() != 1:
						unsteady.append("%s seed %d at %.2f: tilts %s" % [spec.id, bird_seed, t - 0.25, tilts.keys()])
	_check(stretches >= 200 and bent.is_empty(), "between turns a bird flies a straight line at constant speed (no wobble)", "%d stretches, bent: %s" % [stretches, bent.slice(0, 5)])
	_check(unsteady.is_empty(), "the facing and tilt hold steady between two turns", str(unsteady.slice(0, 5)))
	# Turns: seeded intervals in TURN_INTERVAL_MIN..MAX from the cruise's start, and the new
	# heading (the velocity just after the turn, away from a bounce) 30-60 degrees off the
	# horizontal; the first turn really changes the velocity.
	var intervals: Array[float] = []
	var angles: Array[String] = []
	var changed := 0
	var first_turns: Dictionary[int, bool] = {}
	for bird_seed in 20:
		var entry := Flight.entry_age(goose, bird_seed, Play.FIELD)
		var turns := Flight.turn_ages(goose, bird_seed, entry, 60.0)
		var previous := entry
		for turn in turns:
			intervals.append(turn - previous)
			previous = turn
		var turn := turns[0]
		first_turns[roundi((turn - entry) * 100.0)] = true
		var before := Flight.velocity(goose, bird_seed, turn - 0.05, Play.FIELD)
		var after := Flight.velocity(goose, bird_seed, turn + 0.05, Play.FIELD)
		if not before.is_equal_approx(after):
			changed += 1
		var angle := rad_to_deg(atan2(absf(after.y), absf(after.x)))
		if angle < rad_to_deg(Flight.FLIGHT_ANGLE_MIN) - 0.01 or angle > rad_to_deg(Flight.FLIGHT_ANGLE_MAX) + 0.01:
			angles.append("seed %d: %.1f degrees" % [bird_seed, angle])
	var outside := intervals.filter(func(interval: float) -> bool: return interval < Flight.TURN_INTERVAL_MIN or interval > Flight.TURN_INTERVAL_MAX)
	_check(intervals.size() >= 20 * 20 and outside.is_empty(), "every rise turn interval lies in %.1f..%.1f s" % [Flight.TURN_INTERVAL_MIN, Flight.TURN_INTERVAL_MAX], "%d intervals, outside: %s" % [intervals.size(), outside])
	_check(first_turns.size() >= 10 and changed >= 18, "the first turn's time varies by seed and changes the heading", "%d distinct first turns, %d of 20 changed" % [first_turns.size(), changed])
	_check(angles.is_empty(), "a new heading is %.0f-%.0f degrees from the horizontal" % [rad_to_deg(Flight.FLIGHT_ANGLE_MIN), rad_to_deg(Flight.FLIGHT_ANGLE_MAX)], str(angles))
	# Seed 7's first turn: before it the climb holds its heading since the cruise started.
	var entry_7 := Flight.entry_age(goose, 7, Play.FIELD)
	var turn_7 := Flight.turn_ages(goose, 7, entry_7, 60.0)[0]
	_check(Flight.turn_ages(goose, 7, entry_7, 60.0) == Flight.turn_ages(goose, 7, entry_7, 60.0) and Flight.position(goose, 7, turn_7 + 0.3, Play.FIELD, 1.3) == Flight.position(goose, 7, turn_7 + 0.3, Play.FIELD, 1.3), "turns and positions are the same for the same inputs", "differ")


## AC 2: a bird reflects off the cruise band's edges. A goose at 3x speed over 20 seeds:
## wherever the horizontal velocity flips away from a turn its centre is at a side edge of
## the band and its vertical velocity is unchanged; wherever the vertical velocity flips
## away from a turn it is at the top or bottom of the band and its horizontal velocity is
## unchanged.
func _test_flight_reflects_at_band_edges() -> void:
	var goose := Content.bird("goose")
	var side := 0
	var top_bottom := 0
	var problems: Array[String] = []
	var step := 1.0 / 240.0
	# One-sided velocities over a short window: away from a bounce each is its segment's.
	var moving := func(bird_seed: int, age: float) -> Vector2:
		return (Flight.position(goose, bird_seed, age + 0.001, Play.FIELD, 3.0) - Flight.position(goose, bird_seed, age, Play.FIELD, 3.0)) / 0.001
	for bird_seed in 20:
		var entry := Flight.entry_age(goose, bird_seed, Play.FIELD, 3.0)
		var turns := Flight.turn_ages(goose, bird_seed, entry, goose.flee_time)
		var age := entry + 0.05
		while age + 3.0 * step < goose.flee_time - 0.05:
			var a: Vector2 = moving.call(bird_seed, age)
			var b: Vector2 = moving.call(bird_seed, age + step)
			var near_turn := Array(turns).any(func(turn: float) -> bool: return absf(turn - age) < 0.05)
			if near_turn or (signf(a.x) != -signf(b.x) and signf(a.y) != -signf(b.y)):
				age += step
				continue
			# The bounce lies within (age, age + step + 0.001): compare the velocities a step
			# before and after it, and look at the position across it.
			var before: Vector2 = moving.call(bird_seed, age - step)
			var after: Vector2 = moving.call(bird_seed, age + 2.0 * step)
			var at := Flight.position(goose, bird_seed, age + step / 2.0, Play.FIELD, 3.0)
			if absf(before.length() - goose.speed * 3.0) > 1.0 or absf(after.length() - goose.speed * 3.0) > 1.0:
				# A corner: a second bounce falls inside the window; the clean ones are counted.
				age += 3.0 * step
				continue
			if signf(a.x) == -signf(b.x):
				side += 1
				var edge := minf(absf(at.x - Flight.path_x_low(goose, Play.FIELD)), absf(at.x - Flight.path_x_high(goose, Play.FIELD)))
				if edge > 4.0 or absf(after.x + before.x) > 1.0 or absf(after.y - before.y) > 1.0:
					problems.append("seed %d side bounce at %.3f: %.1f from the edge, v %s -> %s" % [bird_seed, age, edge, before, after])
			else:
				top_bottom += 1
				var edge := minf(absf(at.y - Flight.path_y_low(goose, Play.FIELD)), absf(at.y - Flight.path_y_high(goose, Play.FIELD)))
				if edge > 4.0 or absf(after.y + before.y) > 1.0 or absf(after.x - before.x) > 1.0:
					problems.append("seed %d top/bottom bounce at %.3f: %.1f from the edge, v %s -> %s" % [bird_seed, age, edge, before, after])
			age += 3.0 * step
	_check(side >= 20 and top_bottom >= 20 and problems.is_empty(), "a bird reflects off the band's side, top and bottom edges", "%d side, %d top/bottom bounces, problems %s" % [side, top_bottom, problems.slice(0, 5)])


## AC 5: the title's geese keep their level, wobbling crossing path: the height swings by
## the wobble (cut to the band) about a level line while x moves at a constant speed.
func _test_flight_crossing_keeps_its_wobble() -> void:
	var goose := Content.bird("goose")
	var band := Rect2(0, 120, 1170, 220)
	var plan := Flight._crossing(goose, 5, band, 1.0)
	var problems: Array[String] = []
	var low := INF
	var high := -INF
	for i in 241:
		var age := i / 60.0
		var at := Flight.crossing_position(goose, 5, age, band)
		var expected := Vector2(plan["start_x"] + plan["direction"] * plan["speed"] * age, plan["y"] + plan["wobble"] * sin(TAU * goose.wobble_hz * age + plan["phase"]))
		if not at.is_equal_approx(expected):
			problems.append("age %.2f: %s, not %s" % [age, at, expected])
		low = minf(low, at.y)
		high = maxf(high, at.y)
	_check(problems.is_empty() and high - low > goose.wobble, "the title's crossing path still wobbles about its level line", "%s, swing %.1f" % [problems.slice(0, 3), high - low])


## AC 6 and 7: each bird's speed factor is seeded (the same seed, the same factor;
## different seeds, different factors), within 1 -/+ 0.05 at speed scale 1 and 1 -/+ 0.20
## at the top scale 1.6 (and filling those ranges), the spread rising linearly between and
## clamped outside; Play multiplies the wave's speed scale by it for every bird it spawns,
## goslings included, in Endless and in a campaign level.
func _test_flight_per_bird_speed() -> void:
	_check(Flight.speed_factor(4242, 1.3) == Flight.speed_factor(4242, 1.3), "a bird's speed factor is the same for the same seed", "differs")
	_check(Flight.speed_factor(1, 1.3) != Flight.speed_factor(2, 1.3), "two seeds give two speed factors", "%f and %f" % [Flight.speed_factor(1, 1.3), Flight.speed_factor(2, 1.3)])
	for case: Array in [[1.0, 0.05], [1.6, 0.2]]:
		var scale: float = case[0]
		var spread: float = case[1]
		var lowest := INF
		var highest := -INF
		for bird_seed in 400:
			var factor := Flight.speed_factor(bird_seed, scale)
			lowest = minf(lowest, factor)
			highest = maxf(highest, factor)
		_check(lowest >= 1.0 - spread - 0.000001 and highest <= 1.0 + spread + 0.000001 and lowest < 1.0 - spread * 0.9 and highest > 1.0 + spread * 0.9, "at speed scale %.1f the factors fill 1 -/+ %.2f" % [scale, spread], "%.4f..%.4f" % [lowest, highest])
	_check(is_equal_approx(Flight.speed_spread(1.3), 0.125) and is_equal_approx(Flight.speed_spread(0.8), 0.05) and is_equal_approx(Flight.speed_spread(2.0), 0.2), "the spread rises linearly from 0.05 at x1 to 0.20 at x1.6, clamped", "%.3f %.3f %.3f" % [Flight.speed_spread(1.3), Flight.speed_spread(0.8), Flight.speed_spread(2.0)])
	var play := await _start_run(31)
	var goose := play.spawn_bird("goose", 555)
	var gosling := play.spawn_bird("gosling", 556, Vector2(480, 250), Flight.split_headings(2)[0])
	_check(is_equal_approx(goose.speed_scale, play.wave.speed_scale * Flight.speed_factor(555, play.wave.speed_scale)) and is_equal_approx(gosling.speed_scale, play.wave.speed_scale * Flight.speed_factor(556, play.wave.speed_scale)), "Endless: a bird and a gosling fly at the wave's speed scale x their own factor", "%f, %f at x%.2f" % [goose.speed_scale, gosling.speed_scale, play.wave.speed_scale])
	play = await _start_level("night_6")
	var swift := play.spawn_bird("zigzag", 557)
	_check(is_equal_approx(swift.speed_scale, play.wave.speed_scale * Flight.speed_factor(557, play.wave.speed_scale)) and swift.speed_scale != play.wave.speed_scale, "a level: a bird flies at the wave's speed scale x its own factor", "%f at x%.2f" % [swift.speed_scale, play.wave.speed_scale])
	var from := _log.size()
	for i in 200:
		await process_frame
		if play.flying_birds().size() > 1:
			break
	_check_logged(from, "^\\[Play\\] Spawned \\w+ #\\d+ \\(wave 1, seed -?\\d+, speed x\\d\\.\\d{3}\\) at t ", "a spawn logs the bird's own speed scale")
	await _open_title()


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
		var shown := _results_texts(results, ["Hits", "Accuracy", "Shots"])
		_check(shown == ["3", "100%", "4 of 4 shots"], "the results count the armored goose once in Birds hit, and both its hits in the accuracy", str(shown))
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
		_check_logged(from, "^\\[Results\\] Score \\d+, accuracy 50% \\(2 of 4 shots\\), .*, 2 pigeons hit, ", "the results log the pigeons hit (no longer on screen)")
		_check(_results_texts(results, ["Accuracy", "Shots"]) == ["50%", "2 of 4 shots"], "pigeon hits are shots but not hits (2 of 4)", str(_results_texts(results, ["Accuracy", "Shots"])))
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
		[Rival.steal_state(3.4, 3.5, 1.0, none, false, 6.0, true), Rival.Steal.NONE, "nothing before linger_time"],
		[Rival.steal_state(3.5, 3.5, 1.0, none, false, 6.0, true), Rival.Steal.AIMING, "the cue starts at linger_time"],
		[Rival.steal_state(9.0, 3.5, 1.0, none, false, 20.0, true), Rival.Steal.AIMING, "a bird with no cue yet is aimed at first, never shot at once"],
		[Rival.steal_state(5.0, 3.5, 1.0, none, false, 6.0, true), Rival.Steal.AIMING, "a bird with exactly aim_time left may be aimed at"],
		[Rival.steal_state(5.01, 3.5, 1.0, none, false, 6.0, true), Rival.Steal.NONE, "a bird with less than aim_time left is never aimed at"],
		[Rival.steal_state(4.49, 3.5, 1.0, 3.5, false, 6.0, true), Rival.Steal.AIMING, "the cue runs aim_time"],
		[Rival.steal_state(4.5, 3.5, 1.0, 3.5, false, 6.0, true), Rival.Steal.FIRE, "he fires once the cue has run aim_time"],
		[Rival.steal_state(6.02, 3.5, 1.0, 5.0, false, 6.0, true), Rival.Steal.FIRE, "a cue that runs out at the flee fires on the frame past it"],
		[Rival.steal_state(5.0, 3.5, 1.0, 4.2, false, 6.0, true), Rival.Steal.AIMING, "aim_time counts from the cue's start"],
		[Rival.steal_state(5.0, 3.5, 1.0, 3.5, true, 6.0, true), Rival.Steal.NONE, "never the decoy"],
		[Rival.steal_state(3.9, 3.5, 1.0, 3.5, false, 4.0, true), Rival.Steal.AIMING, "a cue keeps running until its bird flees (the shells ran out)"],
		[Rival.steal_state(4.0, 3.5, 1.0, 3.5, false, 4.0, true), Rival.Steal.NONE, "a bird fleeing before its cue has run drops the cue"],
		[Rival.steal_state(5.0, 3.5, 1.0, 3.5, false, 6.0, false), Rival.Steal.NONE, "never with steals off"],
	]
	for case in cases:
		_check(case[0] == case[1], "Rival.steal_state: " + str(case[2]), "got %s, expected %s" % [case[0], case[1]])
	_check(not Rival.may_heckle("miss", 3.9, 0.0, 4.0) and Rival.may_heckle("miss", 4.0, 0.0, 4.0) and Rival.may_heckle("wave_end", 0.0, -INF, 4.0), "Rival.may_heckle: a miss or wave-end line waits for the cooldown (none before the first)", "")
	_check(Rival.may_heckle(Rival.STEAL, 0.1, 0.0, 4.0), "Rival.may_heckle: a steal line skips the cooldown", "")
	_check(Rival.may_aim(false, 0.0, -INF, 1.5) and not Rival.may_aim(true, 9.0, -INF, 1.5), "Rival.may_aim: a first cue may start, never a second while one runs", "")
	_check(not Rival.may_aim(false, 11.49, 10.0, 1.5) and Rival.may_aim(false, 11.5, 10.0, 1.5), "Rival.may_aim: after a cue ends the next waits the gap", "")
	_check(Rival.aim_target(PackedFloat64Array([3.6, 4.2, 3.9]), PackedInt32Array([1, 2, 3])) == 1, "Rival.aim_target: the bird that has flown longest", "")
	_check(Rival.aim_target(PackedFloat64Array([4.0, 4.0, 3.0]), PackedInt32Array([7, 5, 2])) == 1, "Rival.aim_target: a tie goes to the lower bird number", "")
	_check(Rival.aim_target(PackedFloat64Array(), PackedInt32Array()) == -1, "Rival.aim_target: none eligible", "")
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
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d: age [\\d.]+ \\(linger 3\\.50 s\\), the rival fires in 1\\.00 s \\(the longest flown of 1 eligible; (no cue before|[\\d.]+ s since the last cue ended), aim gap 1\\.50 s\\) \\(wave 1 at t -?[\\d.]+, rival score 0, 0 stolen\\)$" % bird.number, "the cue start is logged with the bird, the choice, the aim gap, wave, time and tallies")
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
	_check_logged(from, "^\\[Play\\] Stolen goose #%d by the rival after a 1\\.0[0-2] s cue: 100 points to the rival, rival score 100, 1 stolen, %d/10 escaped, combo x3 kept \\(wave 1 at t -?[\\d.]+\\); he laughs in 0\\.30 s, no new cue for the 1\\.50 s aim gap$" % [bird.number, play.escaped], "the steal is logged with the cue time, the tallies, the escapes and the combo")
	_check(Content.rival_lines().lines["steal"].has(play.heckle_shown()) and play.heckles == 2, "a steal line shows inside the cooldown", "'%s', %d heckles" % [play.heckle_shown(), play.heckles])
	_check_logged(from, "^\\[Play\\] Heckle \\(steal\\) #2: \".+\" \\(wave 1 at t -?[\\d.]+, rival score 100, 1 stolen\\), no blurt$", "the steal heckle is logged with its category and line")
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
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d cancelled \\(shot by the player\\) after [\\d.]+ s \\(wave 1 at t -?[\\d.]+, rival score 0, 0 stolen\\); no new cue for the 1\\.50 s aim gap$" % bird.number, "the cancelled cue is logged with its cause and the aim gap")
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
		var shown := _results_texts(results, ["Escaped", "RivalScore", "Steals"])
		_check(shown == ["10 escaped (1 stolen)", "120", "from 1 steal"], "the results show the birds stolen and the rival's score", str(shown))
		_check_logged(from, "^\\[Results\\] Verdict: You 0 vs rival 120: the rival wins$", "the results log the verdict")
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


## The rival (at or below the fringe's top) and his bubble (at or below GRASS_Y) sit in the grass band inside the visible
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
			# The rival's hat may reach the fringe's top; the bubble stays below the grass line.
			var top := Play.GRASS_Y - Play.GRASS_TIP if part == rival else Play.GRASS_Y
			if world.to_local(rect.position).y < top - 0.01 or not shown.encloses(rect):
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



## The rival's footprint (art polish): his rect is Play.RIVAL_RECT (80x120 at the
## bottom-left of the bank), its top at or below the fringe's top (GRASS_Y - GRASS_TIP:
## no art over the field) and inside the visible area; each pose's art has the rect's
## aspect (it fills it, nothing letterboxed off its feet), stands on its bottom edge and
## keeps inside it. The aim pose's highest art is the gun's muzzle in the right third, so
## the aim cue visibly comes from his gun; every other pose's highest art is his hat,
## left of it.
func _test_rival_footprint_and_poses() -> void:
	var play := await _start_run(78)
	var rival := play.get_node("World/Rival") as TextureRect
	var world := play.get_node("World") as Node2D
	var rect := Rect2(world.to_local(rival.get_global_rect().position), rival.size)
	_check(rect.is_equal_approx(Play.RIVAL_RECT) and Play.RIVAL_RECT.size == Vector2(80, 120), "the rival stands in an 80x120 rect at the bottom-left of the bank", str(rect))
	_check(rect.position.y >= Play.GRASS_Y - Play.GRASS_TIP and rect.position.x >= 0.0 and rect.end.y <= 540.0, "none of the rival's rect is above the fringe's top (y 416) or off the screen", str(rect))
	var tops: Dictionary[String, Vector2i] = {}
	for pose: Texture2D in [Play.RIVAL_IDLE, Play.RIVAL_AIM, Play.RIVAL_SULK, Play.RIVAL_BRAG]:
		var image := pose.get_image()
		var size := image.get_size()
		var file := pose.resource_path.get_file()
		_check(is_equal_approx(float(size.x) / size.y, rect.size.x / rect.size.y), "%s has the rival rect's aspect" % file, str(size))
		var used := image.get_used_rect()
		_check(used.end.y >= size.y - 2 and used.position.y >= 0 and used.position.x >= 0 and used.end.x <= size.x, "%s stands on the rect's bottom edge, inside it" % file, str(used))
		var top := Vector2i(-1, -1)
		for y in size.y:
			for x in size.x:
				if image.get_pixel(x, y).a > 0.5:
					top = Vector2i(x, y)
					break
			if top.x >= 0:
				break
		tops[file] = top
	var aim := tops["rival_aim.svg"]
	var width := Play.RIVAL_AIM.get_width()
	_check(aim.x * 3 >= width * 2, "the aim pose's highest art is the gun's muzzle, in the right third", "%s of %d" % [aim, width])
	for file: String in ["rival_idle.svg", "rival_sulk.svg", "rival_brag.svg"]:
		_check(tops[file].x * 3 < width * 2, "%s's highest art is his hat, not a raised gun" % file, str(tops[file]))


## Each backdrop lights the rival (art polish): a level of every chapter starts with his
## modulate at its backdrop's tint (logged), Endless on dawn's, and the title on the
## sunset's; noon is neutral, dawn and sunset warm, night cool.
func _test_rival_lit_per_backdrop() -> void:
	for chapter in Content.chapters():
		var from := _log.size()
		var play := await _start_level(Campaign.chapter_levels(chapter.id)[0].id)
		var tint := (play.get_node("World/Rival") as CanvasItem).modulate
		_check(Backdrop.RIVAL_TINTS.has(chapter.backdrop) and tint.is_equal_approx(Backdrop.rival_tint(chapter.backdrop)), "%s: the rival is lit with the %s backdrop's tint" % [chapter.id, chapter.backdrop], str(tint))
		_check_logged(from, "^\\[Play\\] Rival lit for backdrop %s: tint #%s$" % [chapter.backdrop, tint.to_html(false)], "%s: the rival's light is logged" % chapter.id)
	var noon := Backdrop.rival_tint("noon")
	var dawn := Backdrop.rival_tint("dawn")
	var sunset := Backdrop.rival_tint("sunset")
	var night := Backdrop.rival_tint("night")
	_check(noon.is_equal_approx(Color(1, 1, 1)) and dawn.r > dawn.b and sunset.r > sunset.b and sunset.b < dawn.b and night.b > night.r and night.v < 0.9,
		"noon is neutral, dawn and sunset warm (sunset warmer), night cool and dim", "%s %s %s %s" % [noon, dawn, sunset, night])
	var endless := await _start_run(79)
	_check((endless.get_node("World/Rival") as CanvasItem).modulate.is_equal_approx(Backdrop.rival_tint(endless.backdrop_id())), "Endless lights the rival for its first backdrop", endless.backdrop_id())
	await _open_title()
	var title := current_scene as Title
	_check((title.get_node("Scenery/Rival") as CanvasItem).modulate.is_equal_approx(Backdrop.rival_tint(Title.TITLE_BACKDROP)), "the title lights the rival for its sunset backdrop", str((title.get_node("Scenery/Rival") as CanvasItem).modulate))

## The rival's poses (step 7): idle at the start; a scored kill makes him sulk for
## RIVAL_REACTION_TIME of game time (logged), then idle again; a miss whose heckle shows
## makes him brag (logged), a miss inside the heckle cooldown (no line) does not; an aim
## cue raises his gun over any reaction.
func _test_rival_poses() -> void:
	var play := await _start_run(70)
	play.mode.rival_steals = false
	_check(play.rival_pose() == "idle", "the rival stands idle at the start", play.rival_pose())
	var from := _log.size()
	var goose := await _spawn_flying(play, 180)
	await _touch(_global(play, goose.transform * LOCAL_BODY))
	_check(play.scoring.kills == 1 and play.rival_pose() == "sulk", "a scored kill makes the rival sulk", "%d kills, %s" % [play.scoring.kills, play.rival_pose()])
	_check_logged(from, "^\\[Play\\] Rival sulks at the 100 points on goose #%d \\(wave 1 at t -?[\\d.]+\\)$" % goose.number, "the sulk is logged with the points and the bird")
	var since := play.run_clock
	for i in roundi(Play.RIVAL_REACTION_TIME * 60.0) + 10:
		if play.rival_pose() != "sulk":
			break
		await process_frame
	var lasted := play.run_clock - since
	_check(play.rival_pose() == "idle" and absf(lasted - Play.RIVAL_REACTION_TIME) <= 2.0 * FRAME, "the sulk lasts RIVAL_REACTION_TIME, then he stands idle", "%s after %.3f s" % [play.rival_pose(), lasted])
	await _touch(_global(play, SKY_POINTS[0]))
	_check(Content.rival_lines().lines["miss"].has(play.heckle_shown()) and play.rival_pose() == "brag", "a miss heckle makes the rival brag", "'%s', %s" % [play.heckle_shown(), play.rival_pose()])
	_check_logged(from, "^\\[Play\\] Rival brags after the miss \\(wave 1 at t -?[\\d.]+\\)$", "the brag is logged")
	for i in roundi(Play.RIVAL_REACTION_TIME * 60.0) + 10:
		if play.rival_pose() == "idle":
			break
		await process_frame
	var heckles := play.heckles
	await _touch(_global(play, SKY_POINTS[1]))
	_check(play.heckles == heckles and play.rival_pose() == "idle", "a miss inside the heckle cooldown (no line) draws no brag", "%d heckles, %s" % [play.heckles, play.rival_pose()])
	play.mode.rival_steals = true
	var cued := await _cued_bird(play, 181, "goose")
	var other := await _spawn_flying(play, 182)
	await _touch(_global(play, other.transform * LOCAL_BODY))
	_check(cued.is_cued() and not other.is_flying() and play.rival_pose() == "aim", "an aim cue raises his gun over the sulk", "cued %s, %s" % [cued.is_cued(), play.rival_pose()])


## The weather is visual only (AC 6): the same seeded run gives the same bird positions,
## frame by frame, under each weather and with none; each weather has a fixed particle
## count of at most Weather.PARTICLES_MAX; the weather is drawn behind the birds (before
## them, at their z_index); set_weather starts exactly one emitter, and an unknown id is
## reported and changes nothing.
func _test_weather_is_visual_only() -> void:
	var baseline := await _bird_track(73, "")
	_check(baseline.size() > 100 and baseline.any(func(frame: String) -> bool: return frame.count("#") >= 2), "the tracked run has birds in the air", "%d frames" % baseline.size())
	for weather_id in Content.WEATHERS:
		var track := await _bird_track(73, weather_id)
		var first_diff := -1
		for i in mini(track.size(), baseline.size()):
			if track[i] != baseline[i]:
				first_diff = i
				break
		_check(track.size() == baseline.size() and first_diff == -1, "under %s the birds fly exactly as with no weather" % weather_id, "frame %d: %s vs %s" % [first_diff, track[first_diff] if first_diff >= 0 else "", baseline[first_diff] if first_diff >= 0 else ""])
	var play := current_scene as Play
	var weather := play.weather()
	var birds := play.get_node("World/Birds") as Node2D
	_check(weather.get_index() < birds.get_index() and weather.z_index <= birds.z_index and weather.z_as_relative, "the weather is drawn behind the birds", "weather #%d z %d, birds #%d z %d" % [weather.get_index(), weather.z_index, birds.get_index(), birds.z_index])
	for weather_id in Content.WEATHERS:
		var emitter := weather.emitter(weather_id)
		_check(emitter != null and emitter.amount > 0 and emitter.amount <= Weather.PARTICLES_MAX and emitter.z_index <= birds.z_index and not emitter.top_level, "%s has a fixed count of at most %d particles, behind the birds" % [weather_id, Weather.PARTICLES_MAX], str(emitter.amount) if emitter != null else "no emitter")
		weather.set_weather(weather_id)
		var emitting := Content.WEATHERS.filter(func(other: String) -> bool: return weather.emitter(other).emitting)
		_check(emitting == [weather_id] and weather.id == weather_id, "set_weather(%s) starts exactly its emitter" % weather_id, str(emitting))
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var refused := weather.set_weather("hail")
	_game.quiet_errors = false
	_check(not refused and weather.id == Content.WEATHERS.back() and _game.reported_errors.size() == errors + 1 and "hail" in _game.reported_errors.back(), "an unknown weather is reported and changes nothing", str(_game.reported_errors.slice(errors)))
	(_game.get_node("Fade/ErrorLabel") as Label).hide()


## Where the birds are drawn (canvas coordinates, 3 decimals) frame by frame for 240 frames
## of an Endless run of `run_seed` under weather `weather_id` ("" for none), steals off.
func _bird_track(run_seed: int, weather_id: String) -> Array[String]:
	var play := await _start_run(run_seed)
	play.mode.rival_steals = false
	play.weather().set_weather(weather_id)
	var frames: Array[String] = []
	for i in 240:
		var parts := PackedStringArray()
		for bird in play.flying_birds():
			parts.append("#%d %.3f,%.3f" % [bird.number, bird.global_position.x, bird.global_position.y])
		frames.append(" ".join(parts))
		await process_frame
	play.mode.rival_steals = true
	return frames


## Endless walks its backdrops by wave (AC 7): dawn with mist from wave 1; at wave 4 noon
## (wind) cross-fades in during the lead-in and is done before the first spawn, which comes
## on time (the fade delays nothing); the old backdrop is freed. Time Attack shows noon with
## wind from its first wave and keeps it through later waves, with no cross-fade.
func _test_backdrop_cycle_and_fade() -> void:
	var play := await _start_run(74)
	play.mode.rival_steals = false
	_check(play.backdrop_id() == "dawn" and play.weather().id == "mist" and not play.is_backdrop_fading(), "Endless starts on the dawn backdrop with mist", "%s, %s" % [play.backdrop_id(), play.weather().id])
	var from := _log.size()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 6000:
		if play.wave.index >= 4 or _game.state != GameState.Flow.PLAY:
			break
		await process_frame
	Engine.time_scale = 1.0
	_check(play.wave.index == 4 and play.is_backdrop_fading() and play.backdrop_id() == "noon" and play.weather().id == "wind", "wave 4 cross-fades the noon backdrop in, with wind", "wave %d, fading %s, %s, %s" % [play.wave.index, play.is_backdrop_fading(), play.backdrop_id(), play.weather().id])
	_check_logged(from, "^\\[Play\\] Backdrop dawn -> noon, weather wind, cross-fading over 0\\.80 s from wave 4$", "the cross-fade is logged")
	var rival := play.get_node("World/Rival") as CanvasItem
	# The loop stops on the frame wave 4 started in (_start_wave runs at the end of _process):
	# its clock starts at -WAVE_LEAD and its first bird is due WAVE_LEAD of run time later.
	var started_at := play.run_clock
	var lead_clock := play.wave_clock
	var faded_at := INF
	var first_spawn := INF
	var spawned := play.flying_birds().size()
	var mid := Color(0, 0, 0, 0)
	for i in 120:
		await process_frame
		if i == 0:
			mid = rival.modulate
		if faded_at == INF and not play.is_backdrop_fading():
			faded_at = play.run_clock - started_at
		if play.flying_birds().size() > spawned:
			first_spawn = play.run_clock - started_at
			break
	var backdrops := play.get_node("World").get_children().filter(func(node: Node) -> bool: return node is Backdrop)
	_check(faded_at <= Play.WAVE_LEAD and backdrops.size() == 1 and (backdrops[0] as Backdrop).id == "noon" and is_equal_approx((backdrops[0] as CanvasItem).modulate.a, 1.0), "the cross-fade ends within the lead-in, leaving only the noon backdrop", "faded %.3f s into the wave, %d backdrops" % [faded_at, backdrops.size()])
	_check(mid != Backdrop.rival_tint("dawn") and mid != Backdrop.rival_tint("noon") and mid.r >= Backdrop.rival_tint("dawn").r - 0.001 and mid.b >= Backdrop.rival_tint("dawn").b - 0.001,
		"the rival's light moves from dawn's toward noon's with the cross-fade", "%s" % mid)
	_check(rival.modulate.is_equal_approx(Backdrop.rival_tint("noon")), "once the fade ends the rival is lit for noon", "%s" % rival.modulate)
	_check_logged(from, "^\\[Play\\] Rival lit for backdrop noon: tint #ffffff$", "the rival's new light is logged")
	_check(is_equal_approx(lead_clock, -Play.WAVE_LEAD) and first_spawn >= Play.WAVE_LEAD - 0.001 and first_spawn <= Play.WAVE_LEAD + FRAME + 0.001, "the wave's first bird spawns on time (the fade delays nothing)", "wave clock %.3f at its start, first spawn %.3f s of run time after it" % [lead_clock, first_spawn])
	play.mode.rival_steals = true
	var timed := await _start_run(75, GameState.TIME_ATTACK_MODE)
	_check(timed.backdrop_id() == "noon" and timed.weather().id == "wind", "Time Attack shows the noon backdrop with wind", "%s, %s" % [timed.backdrop_id(), timed.weather().id])
	from = _log.size()
	for i in 3:
		timed.ammo.shells = 1
		await _touch(_global(timed, SKY_POINTS[i]))
	_check(timed.wave.index == 4 and timed.backdrop_id() == "noon" and not timed.is_backdrop_fading(), "Time Attack keeps noon through later waves", "wave %d, %s" % [timed.wave.index, timed.backdrop_id()])
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Backdrop")), "Time Attack never changes its backdrop", "a backdrop line")


## A backdrop whose art is missing is reported (AC 11): the log and the error label name
## the file, show_backdrop() refuses, and the backdrop shown stays as it was.
func _test_missing_backdrop_is_reported() -> void:
	var play := await _start_run(76)
	var backdrop := play.get_node("World/Backdrop") as Backdrop
	var sky := (backdrop.get_node("Sky") as TextureRect).texture
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var shown := backdrop.show_backdrop("dusk")
	_game.quiet_errors = false
	var label := _game.get_node("Fade/ErrorLabel") as Label
	var message: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
	_check(not shown and _game.reported_errors.size() == errors + 1 and "res://art/backdrops/dusk_sky.svg" in message and "res://art/backdrops/dusk_grass.svg" in message, "a backdrop with missing art is reported with its files", message)
	_check(label.visible and label.text == message, "the missing art shows on the error label", label.text)
	_check(backdrop.id == "dawn" and (backdrop.get_node("Sky") as TextureRect).texture == sky, "the backdrop shown stays as it was (no placeholder)", backdrop.id)
	label.hide()


## The UI theme (AC 9): project.godot sets res://ui/theme.tres, which loads with no
## problem; body text uses Nunito (a FontVariation of the bundled variable font), buttons
## and headings Lilita One, both shipped with their OFL licence (exported by the preset);
## buttons have flat styles for every state, their text at least 4.5:1 on each enabled
## state, and a focus ring drawn outside the button that stands out from the menus'
## background; the scenes use it. Missing theme or font files are reported by name (AC 11),
## before anything is loaded: a theme whose font file is gone, no theme file, a theme
## without a default font; a scene's missing art is named too.
func _test_ui_theme_and_fonts() -> void:
	var path: String = ProjectSettings.get_setting(GameState.THEME_SETTING, "")
	_check(path == "res://ui/theme.tres" and GameState.theme_problems(path).is_empty(), "project.godot sets the UI theme, which loads without problems", "%s: %s" % [path, GameState.theme_problems(path)])
	_check(_game.checked_theme == path, "Game checked the project's UI theme at start", _game.checked_theme)
	_check(not _game.reported_errors.any(func(message: String) -> bool: return "UI theme" in message), "nothing about the theme was reported at start", str(_game.reported_errors))
	var theme := load(path) as Theme
	var body := theme.default_font as FontVariation
	var display := theme.get_font(&"font", &"Button")
	_check(body != null and body.base_font.resource_path == "res://ui/fonts/Nunito-wght.ttf" and display.resource_path == "res://ui/fonts/LilitaOne-Regular.ttf" and theme.get_font(&"font", &"HeadingLabel") == display,
		"body text is Nunito, buttons and headings Lilita One", "%s, %s" % [body.base_font.resource_path if body != null else "none", display.resource_path])
	for licence: String in ["res://ui/fonts/LilitaOne-OFL.txt", "res://ui/fonts/Nunito-OFL.txt"]:
		_check("SIL Open Font License" in FileAccess.get_file_as_string(licence), "%s is bundled" % licence.get_file(), "missing")
	var presets := ConfigFile.new()
	presets.load(EXPORT_PRESETS_PATH)
	_check("ui/fonts/*.txt" in str(presets.get_value("preset.0", "include_filter", "")), "the web export ships the fonts' licences", str(presets.get_value("preset.0", "include_filter", "")))
	var ink := theme.get_color(&"font_color", &"Button")
	for state: String in ["normal", "hover", "pressed"]:
		var style := theme.get_stylebox(state, &"Button") as StyleBoxFlat
		var ratio := _contrast(ink, style.bg_color) if style != null else 0.0
		_check(style != null and ratio >= MIN_CONTRAST, "button text reads at %.1f:1 on the %s style" % [ratio, state], str(style))
	var disabled := theme.get_stylebox(&"disabled", &"Button") as StyleBoxFlat
	_check(disabled != null and disabled.bg_color != (theme.get_stylebox(&"normal", &"Button") as StyleBoxFlat).bg_color, "a disabled button looks different", str(disabled))
	var focus := theme.get_stylebox(&"focus", &"Button") as StyleBoxFlat
	var panel := theme.get_stylebox(&"panel", &"Panel") as StyleBoxFlat
	_check(focus != null and not focus.draw_center and focus.border_width_top >= 3 and focus.expand_margin_top > 0.0 and _contrast(focus.border_color, panel.bg_color) >= MIN_CONTRAST,
		"the focus ring is a thick outline around the button that stands out from the menus' background", "%s, %.1f:1" % [focus, _contrast(focus.border_color, panel.bg_color) if focus != null else 0.0])
	await _open_title()
	var campaign := current_scene.get_node("Safe/CampaignButton") as Button
	var heading := current_scene.get_node("Safe/GameName") as Label
	_check(campaign.get_theme_font(&"font") == display and heading.get_theme_font(&"font") == display and (current_scene.get_node("Safe/Tagline") as Label).get_theme_font(&"font") == body, "the title uses the theme's fonts", "%s" % campaign.get_theme_font(&"font"))
	var broken := "user://broken_theme.tres"
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string('[gd_resource type="Theme" load_steps=2 format=3]\n\n[ext_resource type="FontFile" path="res://ui/fonts/Missing.ttf" id="1_font"]\n\n[resource]\ndefault_font = ExtResource("1_font")\n')
	file.close()
	_check(GameState.theme_problems(broken) == ["UI theme 'user://broken_theme.tres' needs 'res://ui/fonts/Missing.ttf', which is missing"], "a theme whose font file is missing is reported with the file", str(GameState.theme_problems(broken)))
	DirAccess.remove_absolute(broken)
	_check(GameState.theme_problems("res://ui/no_theme.tres") == ["UI theme 'res://ui/no_theme.tres' does not exist"], "a missing theme file is reported", str(GameState.theme_problems("res://ui/no_theme.tres")))
	_check(GameState.font_problems(Theme.new(), "test") == ["UI theme 'test': default_font has no font file"], "a theme without a default font is reported", str(GameState.font_problems(Theme.new(), "test")))
	var scene := "user://broken_scene.tscn"
	file = FileAccess.open(scene, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://art/no_such_bird.svg" id="1_art"]\n\n[node name="Broken" type="Sprite2D"]\ntexture = ExtResource("1_art")\n')
	file.close()
	_check(GameState.missing_dependencies(scene) == PackedStringArray(["res://art/no_such_bird.svg"]), "a scene's missing art is named", str(GameState.missing_dependencies(scene)))
	DirAccess.remove_absolute(scene)


## With the theme's fonts, every menu button's text fits inside it at the largest values the
## save holds (AC 10): the title's Endless and Time Attack bests at SAVE_SCORE_MAX, every
## chapter at 18/18 stars and every level at 3/3 stars with a best of SAVE_SCORE_MAX, at
## 16:9 and 4:3 (each button's minimum size, its text included, within the size its scene
## gives it: a Button grows to fit its text, so a grown one would push into its neighbours).
func _test_menu_texts_fit_largest_values() -> void:
	_clear_tool_save()
	for mode_id in GameState.BEST_MODES:
		_game.bests[mode_id] = GameState.SAVE_SCORE_MAX
	for level in Content.levels():
		_game.progress[level.id] = Campaign.Record.new(Campaign.MAX_STARS, GameState.SAVE_SCORE_MAX)
	var screens: Array[Array] = [[GameState.Flow.TITLE, {}, ["Safe/CampaignButton", "Safe/EndlessButton", "Safe/TimeAttackButton"]], [GameState.Flow.CHAPTER_SELECT, {}, ["Safe/Chapter1", "Safe/Chapter2", "Safe/Chapter3", "Safe/Chapter4", "Safe/BackButton"]]]
	for chapter_spec in Content.chapters():
		screens.append([GameState.Flow.LEVEL_SELECT, {"chapter": chapter_spec.id}, ["Safe/Level1", "Safe/Level2", "Safe/Level3", "Safe/Level4", "Safe/Level5", "Safe/Level6", "Safe/BackButton"]])
	for screen: Array in screens:
		_game.goto(screen[0], screen[1])
		await _game.transition_finished
		await process_frame
		for window: Vector2i in [LANDSCAPE_16_9, LANDSCAPE_4_3]:
			root.size = window
			await process_frame
			await process_frame
			var overflow: Array[String] = []
			var texts: Array[String] = []
			for node_path: String in screen[2]:
				var button := current_scene.get_node(node_path) as Button
				texts.append(button.text.replace("\n", " / "))
				# A Button grows to its minimum size, so its text is measured against the size
				# the scene gives it (its offsets; these buttons' anchors are a point).
				var need := button.get_combined_minimum_size()
				var designed := Vector2(button.offset_right - button.offset_left, button.offset_bottom - button.offset_top)
				if need.x > designed.x + 0.5 or need.y > designed.y + 0.5:
					overflow.append("%s needs %s in its %s" % [button.name, need, designed])
			# The chapter buttons show stars only; the title and level select show the best score.
			var shows_max: bool = screen[0] == GameState.Flow.CHAPTER_SELECT or str(GameState.SAVE_SCORE_MAX) in " ".join(texts)
			_check(overflow.is_empty() and shows_max, "%s %dx%d: every button's text fits at the largest values (%s)" % [GameState.Flow.keys()[screen[0]], window.x, window.y, "; ".join(texts)], "; ".join(overflow))
	root.size = BASE_WINDOW
	await process_frame
	_clear_tool_save()


## Missing files reach the player (AC 11), end to end: Game.check_ui_theme (what Game runs
## at start for the project's theme) puts a theme whose font file is missing, and a theme
## that does not exist, in reported_errors and on the error label with the file named,
## and passes the real theme; goto() into a scene that needs a missing file reports it
## (scene and file named, on the label) before loading anything, and nothing changes.
func _test_load_errors_reach_the_screen() -> void:
	var label := _game.get_node("Fade/ErrorLabel") as Label
	var broken := "user://broken_theme.tres"
	var file := FileAccess.open(broken, FileAccess.WRITE)
	file.store_string('[gd_resource type="Theme" load_steps=2 format=3]\n\n[ext_resource type="FontFile" path="res://ui/fonts/Missing.ttf" id="1_font"]\n\n[resource]\ndefault_font = ExtResource("1_font")\n')
	file.close()
	for case: Array in [[broken, "res://ui/fonts/Missing.ttf"], ["res://ui/no_theme.tres", "res://ui/no_theme.tres"]]:
		_game.quiet_errors = true
		var errors := _game.reported_errors.size()
		var passed := _game.check_ui_theme(case[0])
		_game.quiet_errors = false
		var shown: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
		_check(not passed and _game.reported_errors.size() == errors + 1 and case[1] in shown, "a UI theme problem (%s) is reported with the file named" % case[1], str(_game.reported_errors.slice(errors)))
		_check(label.visible and label.text == shown, "the theme problem (%s) shows on the error label" % case[1], label.text)
		label.hide()
	DirAccess.remove_absolute(broken)
	var from := _log.size()
	_check(_game.check_ui_theme(ProjectSettings.get_setting(GameState.THEME_SETTING, "")), "the project's theme passes the check Game runs at start", "")
	_check_logged(from, "^\\[Game\\] UI theme res://ui/theme\\.tres loaded with its fonts: Nunito-wght\\.ttf, LilitaOne-Regular\\.ttf$", "the theme's fonts are logged")
	var scene := "user://broken_scene.tscn"
	file = FileAccess.open(scene, FileAccess.WRITE)
	file.store_string('[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Texture2D" path="res://art/no_such_bird.svg" id="1_art"]\n\n[node name="Broken" type="Sprite2D"]\ntexture = ExtResource("1_art")\n')
	file.close()
	var real_path: String = _game.scene_paths[GameState.Flow.TITLE]
	_game.scene_paths[GameState.Flow.TITLE] = scene
	_game.quiet_errors = true
	var reported := _game.reported_errors.size()
	var logged := _game.transition_log.size()
	var scene_before := current_scene
	_game.goto(GameState.Flow.TITLE)
	await process_frame
	_game.quiet_errors = false
	_game.scene_paths[GameState.Flow.TITLE] = real_path
	var loading := _game.is_transitioning()
	if loading:
		# The broken scene is being loaded (no check stopped it): let that transition end and
		# go back to the real title, so this test fails on its own checks below.
		await _game.transition_finished
		await _open_title()
	var message: String = _game.reported_errors.back() if _game.reported_errors.size() > reported else ""
	_check(_game.reported_errors.size() == reported + 1 and scene in message and "res://art/no_such_bird.svg" in message, "a scene that needs a missing file is reported with the scene and the file named", message)
	_check(label.visible and label.text == message, "the missing scene file shows on the error label", label.text)
	_check(not loading and current_scene == scene_before and _game.transition_log.size() == logged, "nothing is loaded or changed", str(current_scene))
	label.hide()
	DirAccess.remove_absolute(scene)


## The grass hides the birds rising from behind it (the visual half of a shot on the grass
## missing): in one canvas, items draw by effective z_index (summed up the tree while
## z_as_relative) and then in tree order. In the play scene every backdrop's grass draws
## after a flying bird's sprite, and the rival, his speech bubble and the pop-ups after
## the grass.
func _test_grass_draws_over_birds() -> void:
	var play := await _start_run(77)
	var bird := play.spawn_bird("goose", 5)
	await process_frame
	var sprite := bird.get_node("Sprite") as CanvasItem
	var grasses: Array[CanvasItem] = []
	for child in play.get_node("World").get_children():
		if child is Backdrop:
			grasses.append(child.get_node("Grass") as CanvasItem)
	_check(not grasses.is_empty() and grasses.all(func(grass: CanvasItem) -> bool: return grass.get_canvas() == sprite.get_canvas() and _draws_after(grass, sprite) and not _draws_after(sprite, grass)),
		"the grass draws over the birds", "grass z %s, bird z %d" % [grasses.map(_effective_z), _effective_z(sprite)])
	var late: Array[String] = []
	for over: String in ["World/Rival", "World/Bubble", "World/Popups"]:
		var item := play.get_node(over) as CanvasItem
		for grass in grasses:
			if item.get_canvas() != grass.get_canvas() or not _draws_after(item, grass):
				late.append("%s (z %d)" % [over, _effective_z(item)])
	_check(late.is_empty(), "the rival, his bubble and the pop-ups draw over the grass", str(late))


## Whether canvas item `a` draws after (over) `b` in the same canvas: a higher effective
## z_index, or the same one and later in the tree.
func _draws_after(a: CanvasItem, b: CanvasItem) -> bool:
	var za := _effective_z(a)
	var zb := _effective_z(b)
	return za > zb if za != zb else a.is_greater_than(b)


## A canvas item's z_index plus its ancestors' while z_as_relative.
func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += (node as CanvasItem).z_index
		if not (node as CanvasItem).z_as_relative:
			break
		node = node.get_parent()
	return z


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
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 4, Endless best 0, Time Attack best 0, 1 levels finished \\(2 stars\\), music 70, sfx 80$", "the finished level is saved at once")
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


## A version 1 save (the Endless best only) is upgraded through versions 2 and 3 to 4: the
## best is kept as the Endless best (Time Attack 0), no level is finished, the settings take
## their defaults (reduce motion off), each step is logged, nothing is reported or backed up, and the upgraded
## save is written back at once.
func _test_save_v1_migrates_to_v4() -> void:
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
	_check_logged(from, "^\\[Game\\] Save upgrade 3 -> 4: reduce_motion off, the bests, the campaign progress and the other settings kept$", "the step 3 -> 4 is logged")
	_check_logged(from, "^\\[Game\\] Upgraded the save to version 4$", "the step to version 4 is logged")
	_check_logged(from, "^\\[Game\\] Loaded save from user://tool_save\\.json: version 4, Endless best 777, Time Attack best 0, 0 levels finished \\(0 stars\\), music 70, sfx 80$", "the migrated save's load is logged")
	_check_logged(from, "^\\[Game\\] Writing the save upgraded from version 1 as version 4$", "writing the upgraded save is logged")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 4.0 and saved.get("bests") == {"endless": 777.0, "time_attack": 0.0} and not saved.has("best_endless") and saved.get("levels") == {} and saved.get("settings") == {"music": 70.0, "sfx": 80.0, "music_muted": false, "sfx_muted": false, "reduce_motion": false}, "the upgraded save is written as version 4", str(saved))
	_clear_tool_save()


## A version 2 save (the Endless best, campaign progress and settings) is upgraded to
## version 4 (through 3): its Endless best becomes bests.endless (Time Attack 0), its progress and
## settings are kept, the step is logged, nothing is reported or backed up, and it is
## written back at once.
func _test_save_v2_migrates_to_v4() -> void:
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
	_check_logged(from, "^\\[Game\\] Writing the save upgraded from version 2 as version 4$", "writing the v2 save as v4 is logged")
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 4, Endless best 4321, Time Attack best 0, 1 levels finished \\(3 stars\\), music 30 muted, sfx 0$", "the upgraded v2 save is written back at once")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 4.0 and saved.get("bests") == {"endless": 4321.0, "time_attack": 0.0} and not saved.has("best_endless") and saved.get("levels") == {"dawn_1": {"stars": 3.0, "score": 2100.0}}, "the upgraded v2 save is written as version 4", str(saved))
	_clear_tool_save()


## A version 3 save (the step 8 format) is upgraded to version 4: its settings gain
## reduce_motion (off) and everything else is kept; only the step 3 -> 4 runs, it is
## logged, nothing is reported or backed up, and the save is written back at once.
func _test_save_v3_migrates_to_v4() -> void:
	_clear_tool_save()
	var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 3, "bests": {"endless": 900, "time_attack": 450}, "levels": {"noon_1": {"stars": 2, "score": 3100}}, "settings": {"music": 40, "sfx": 60, "music_muted": false, "sfx_muted": true}}))
	file.close()
	_game.reduce_motion = true
	var errors := _game.reported_errors.size()
	var from := _log.size()
	_game.load_game()
	_check(_game.bests == {"endless": 900, "time_attack": 450} and _game.progress.keys() == ["noon_1"] and _game.progress["noon_1"].score == 3100 and _game.music_volume == 40 and _game.sfx_volume == 60 and not _game.music_muted and _game.sfx_muted and not _game.reduce_motion,
		"a v3 save migrates keeping its bests, progress and settings, reduce motion off", "bests %s, %s, music %d, reduce motion %s" % [_game.bests, _game.progress.keys(), _game.music_volume, _game.reduce_motion])
	_check(_game.reported_errors.size() == errors and not FileAccess.file_exists(_game.backup_path()), "a migrated v3 save is not reported or backed up", str(_game.reported_errors.slice(errors)))
	_check(not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Game] Save upgrade 1 -> 2") or line.begins_with("[Game] Save upgrade 2 -> 3")), "a v3 save takes only the step 3 -> 4", "an earlier step logged")
	_check_logged(from, "^\\[Game\\] Save upgrade 3 -> 4: reduce_motion off, the bests, the campaign progress and the other settings kept$", "the v3 -> v4 step is logged")
	_check_logged(from, "^\\[Game\\] Writing the save upgraded from version 3 as version 4$", "writing the v3 save as v4 is logged")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("version") == 4.0 and saved.get("bests") == {"endless": 900.0, "time_attack": 450.0} and saved.get("levels") == {"noon_1": {"stars": 2.0, "score": 3100.0}} and saved.get("settings") == {"music": 40.0, "sfx": 60.0, "music_muted": false, "sfx_muted": true, "reduce_motion": false}, "the upgraded v3 save is written as version 4", str(saved))
	_clear_tool_save()
	_game.load_game()


## reduce_motion round-trips through the save (and shows in the save's log summary); a v4
## save whose settings lack it, carry an unknown key beside it or hold a non-bool is corrupt
## (backed up, reported on the error label with the problem, replaced by a fresh save with
## it off).
func _test_save_reduce_motion_strict() -> void:
	_clear_tool_save()
	var from := _log.size()
	_game.reduce_motion = true
	_game.save_game()
	_check_logged(from, "^\\[Game\\] Saved to user://tool_save\\.json: version 4, Endless best 0, Time Attack best 0, 0 levels finished \\(0 stars\\), music 70, sfx 80, reduce motion$", "a save with reduce motion on says so in its log line")
	_game.reduce_motion = false
	_game.load_game()
	_check(_game.reduce_motion, "reduce motion on survives a save and reload", str(_game.reduce_motion))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and saved.get("settings", {}).get("reduce_motion") == true, "the save holds settings.reduce_motion", str(saved))
	var settings := {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false}
	var missing := JSON.stringify({"version": 4, "bests": {"endless": 0, "time_attack": 0}, "levels": {}, "settings": settings})
	var extra_settings := settings.duplicate()
	extra_settings["reduce_motion"] = false
	extra_settings["shake"] = true
	var extra := JSON.stringify({"version": 4, "bests": {"endless": 0, "time_attack": 0}, "levels": {}, "settings": extra_settings})
	var wrong_settings := settings.duplicate()
	wrong_settings["reduce_motion"] = "yes"
	var wrong := JSON.stringify({"version": 4, "bests": {"endless": 0, "time_attack": 0}, "levels": {}, "settings": wrong_settings})
	var numeric_settings := settings.duplicate()
	numeric_settings["reduce_motion"] = 1
	var numeric := JSON.stringify({"version": 4, "bests": {"endless": 0, "time_attack": 0}, "levels": {}, "settings": numeric_settings})
	var cases := {
		missing: "settings must be exactly [\"music\", \"sfx\", \"music_muted\", \"sfx_muted\", \"reduce_motion\"]",
		extra: "settings must be exactly [\"music\", \"sfx\", \"music_muted\", \"sfx_muted\", \"reduce_motion\"]",
		wrong: "settings.reduce_motion is not true or false",
		numeric: "settings.reduce_motion is not true or false",
	}
	var error_label := _game.get_node("Fade/ErrorLabel") as Label
	for text: String in cases:
		var file := FileAccess.open(_game.save_path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		_game.reduce_motion = true
		_game.quiet_errors = true
		var errors := _game.reported_errors.size()
		_game.load_game()
		_game.quiet_errors = false
		var message: String = _game.reported_errors.back() if _game.reported_errors.size() > errors else ""
		var fresh: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
		_check(message.contains(cases[text]) and message.contains(_game.backup_path()) and error_label.text == message and FileAccess.get_file_as_string(_game.backup_path()) == text and not _game.reduce_motion and fresh is Dictionary and fresh.get("settings", {}).get("reduce_motion") == false,
			"save %s: backed up, reported on the label, fresh with reduce motion off" % cases[text], message)
	error_label.hide()
	_clear_tool_save()
	_game.load_game()


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
	_check(rewritten is Dictionary and rewritten.get("levels") == {"dawn_1": {"stars": 2.0, "score": 1500.0}} and rewritten.get("version") == 4.0 and rewritten.get("bests") == {"endless": 42.0, "time_attack": 0.0}, "the v2 save is written back as v4 without the dropped entries", str(rewritten))
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
## the chapter's backdrop and weather show. A run with 0 stars is recorded as not passed: Next is
## hidden, Retry is focused and plays the level again.
func _test_campaign_level_plays_all_waves() -> void:
	_clear_tool_save()
	_game.progress["dawn_1"] = Campaign.Record.new(1, 900)
	var from := _log.size()
	var play := await _start_level("dawn_2")
	_check_logged(from, "^\\[Play\\] Run start: level dawn_2 \\(Dawn 2 of 6\\), seed 102 \\(3 waves, no escape limit, combo cap 3, 3 shells per hit, rival steals on, linger x1\\.00, aim 1\\.00 s, heckle cooldown 4\\.00 s, backdrop dawn, weather mist\\)$", "the level's run start is logged with its seed and settings")
	_check_logged(from, "^\\[Play\\] Wave 1 start: 4 birds \\(.+\\), \\d+ shells, speed x1\\.00 \\(wave 1 of 3, level dawn_2\\)$", "a level's wave start is logged with its place in the level")
	_check(_text(play, "Wave") == "Wave 1/3" and _text(play, "Escaped") == "Escaped 0", "the HUD shows wave x/N and the escapes without a limit", "%s, %s" % [_text(play, "Wave"), _text(play, "Escaped")])
	_check(play.backdrop_id() == "dawn" and play.weather().id == "mist" and (play.get_node("World/Backdrop/Sky") as TextureRect).texture.resource_path == Content.backdrop_path("dawn", "sky"), "the level shows its chapter's backdrop and weather", "%s, %s" % [play.backdrop_id(), play.weather().id])
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
	var shown := _results_texts(results, ["Heading", "Score", "Best"])
	_check(shown == ["Dawn 2: not passed", "0", "Best 0"] and (results.get_node("%Stars") as Control).visible and results.stars_shown() == 0 and (results.get_node("%RivalPanel") as Control).visible, "the results show the level, three empty stars, the score with the level best and the rival", str(shown))
	_check_logged(from, "^\\[Results\\] Level dawn_2: 0 stars, best 0 \\(0 stars\\), next none open$", "the results log the level's stars")
	_check_logged(from, "^\\[Results\\] Verdict: %s$" % Results.verdict_text(0, stats["rival_score"]), "the results log the verdict")
	var buttons := ["NextButton", "RetryButton", "LevelsButton", "PlayAgainButton", "TitleButton"].map(func(n: String) -> bool: return (results.get_node("Safe/" + n) as Control).visible)
	_check(buttons == [false, true, true, false, false] and (results.get_node("Safe/RetryButton") as Control).has_focus() and not (results.get_node("%NewBest") as Control).visible, "without an open next level: Retry (focused) and Levels, no New best!", str(buttons))
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
	var shown := _results_texts(results, ["Heading", "Score", "Best"])
	for i in 120:
		if results.stars_shown() == 2:
			break
		await process_frame
	_check(shown == ["Dawn 1: passed", "1500", "Best 1500"] and results.stars_shown() == 2, "the results show the two stars earned, the score and the level best", "%s, %d stars" % [shown, results.stars_shown()])
	var next := results.get_node("Safe/NextButton") as Button
	var retry := results.get_node("Safe/RetryButton") as Button
	var levels := results.get_node("Safe/LevelsButton") as Button
	_check(next.visible and retry.visible and levels.visible and next.has_focus() and (results.get_node("%NewBest") as Control).visible, "Next (focused), Retry and Levels, and New best!", str(root.gui_get_focus_owner()))
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


## The verdict (logged, no longer shown): a win when the score beats the rival's, a loss
## below it, a tie when equal; a run without rival steals logs none and shows no Rival
## panel.
func _test_results_verdict() -> void:
	_check(Results.verdict_text(500, 300) == "You 500 vs rival 300: you win!" and Results.verdict_text(100, 300) == "You 100 vs rival 300: the rival wins" and Results.verdict_text(200, 200) == "You 200 vs rival 200: a tie",
		"the verdict is a win, a loss or a tie", Results.verdict_text(200, 200))
	var stats := {"mode": "endless", "score": 40, "shots": 2, "hits": 1, "kills": 1, "pigeons": 0, "escaped": 10, "stolen": 0, "rival_score": 0, "rival_line": "Not bad.", "rival_steals": false, "best": 100, "new_best": false, "save_error": ""}
	var from := _log.size()
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	_check(not (current_scene.get_node("%RivalPanel") as Control).visible and not Array(_log.since(from)).any(func(l: String) -> bool: return l.begins_with("[Results] Verdict")), "a run without rival steals shows no Rival panel and logs no verdict", "shown or logged")
	stats["rival_steals"] = true
	from = _log.size()
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	_check((current_scene.get_node("%RivalPanel") as Control).visible, "a run with rival steals shows the Rival panel", "hidden")
	_check_logged(from, "^\\[Results\\] Verdict: You 40 vs rival 0: you win!$", "a run with rival steals logs the verdict")
	_check_results_hide_dropped_lines(current_scene as Results, "Not bad.")
	await _open_title()


## The results' stars and panels (results-panels AC 1-3, 5, 6): a level shows three stars,
## the earned ones (the first N) filling in one by one on the frame of their star sound,
## STAR_SOUND_GAP apart, with a bounce past full size, or with reduce motion at the same
## moments at full size; 0 stars shows three empty outlines and plays no star sound; the
## New best! badge bounces with its fanfare (not with reduce motion). Opened without run
## stats, the panels show dashes, no Rival panel and no stars.
func _test_results_stars_and_panels() -> void:
	_clear_tool_save()
	var base := {"score": 1200, "shots": 4, "hits": 3, "kills": 3, "pigeons": 1, "escaped": 2, "stolen": 1, "rival_score": 100, "rival_line": "Not bad.", "rival_steals": true, "best": 1200, "new_best": false, "save_error": "", "level": "dawn_1", "best_stars": 3, "next_level": "dawn_2"}
	for reduce_motion: bool in [false, true]:
		_game.set_reduce_motion(reduce_motion)
		for earned in Campaign.MAX_STARS + 1:
			var label := "%d stars%s" % [earned, ", reduce motion" if reduce_motion else ""]
			var stats := base.duplicate()
			stats["stars"] = earned
			stats["new_best"] = earned == Campaign.MAX_STARS
			var from := _log.size()
			_game.goto(GameState.Flow.RESULTS, stats)
			await scene_changed
			var results := current_scene as Results
			var start := _game._clock
			var shown_at: Array[float] = []
			var sound_at: Array[float] = []
			var star_peak := 0.0
			var star_low := INF
			var badge_peak := 0.0
			for i in roundi((Results.STAR_SOUND_GAP * (earned + 2) + Results.STAR_POP_TIME) * 60.0):
				await process_frame
				while shown_at.size() < results.stars_shown():
					shown_at.append(_game._clock)
				var sounds := Array(_log.since(from)).filter(func(l: String) -> bool: return l == "[Audio] SFX star").size()
				while sound_at.size() < sounds:
					sound_at.append(_game._clock)
				for slot: Control in (results.get_node("%Stars") as Control).get_children():
					var full := slot.get_node("Full") as Control
					if full.visible:
						star_peak = maxf(star_peak, full.scale.x)
						star_low = minf(star_low, full.scale.x)
				badge_peak = maxf(badge_peak, (results.get_node("%NewBest") as Control).scale.x)
			while _game.is_transitioning():
				await process_frame
			var slots := (results.get_node("%Stars") as Control).get_children()
			var filled := slots.map(func(slot: Node) -> bool: return (slot.get_node("Full") as CanvasItem).visible)
			var outlined := slots.all(func(slot: Node) -> bool: return (slot.get_node("Empty") as CanvasItem).visible)
			var expected: Array = range(Campaign.MAX_STARS).map(func(i: int) -> bool: return i < earned)
			_check((results.get_node("%Stars") as Control).visible and slots.size() == Campaign.MAX_STARS and filled == expected and outlined, "%s: three stars, the first %d filled, every slot outlined" % [label, earned], str(filled))
			_check(shown_at.size() == earned and sound_at.size() == earned and results.stars_popped == earned, "%s: %d star sounds and %d stars popped in" % [label, earned, earned], "%d shown, %d sounds" % [shown_at.size(), sound_at.size()])
			var timing: Array[String] = []
			for i in mini(shown_at.size(), sound_at.size()):
				if not is_equal_approx(shown_at[i], sound_at[i]):
					timing.append("star %d shown at %.3f, its sound at %.3f" % [i + 1, shown_at[i] - start, sound_at[i] - start])
				var due := Results.STAR_SOUND_GAP * (i + 1)
				if absf(shown_at[i] - start - due) > 2.0 * FRAME + 0.001:
					timing.append("star %d at %.3f s, due at %.2f s" % [i + 1, shown_at[i] - start, due])
			_check(timing.is_empty(), "%s: each star pops in on the frame of its sound, STAR_SOUND_GAP apart" % label, "; ".join(timing))
			if earned > 0 and not reduce_motion:
				_check(star_peak >= Results.STAR_POP_SCALE - 0.1 and star_low < 0.5 and results.last_pop_style == "bounce", "%s: the stars pop in with a bounce past full size" % label, "scale %.2f..%.2f" % [star_low, star_peak])
			elif earned > 0:
				_check(star_peak == 1.0 and star_low == 1.0 and results.last_pop_style == "plain", "%s: the stars appear at full size, no bounce" % label, "scale %.2f..%.2f" % [star_low, star_peak])
			if earned > 0:
				_check_logged(from, "^\\[Results\\] Star %d of %d pops in \\(%s\\)$" % [earned, earned, "no bounce: reduce motion" if reduce_motion else "bounce"], "%s: the last star's pop is logged" % label)
			if stats["new_best"]:
				_check((badge_peak > 1.05) != reduce_motion, "%s: the New best! badge %s with its fanfare" % [label, "stays still" if reduce_motion else "bounces"], "peak scale %.2f" % badge_peak)
	_game.set_reduce_motion(false)
	var opened_from := _log.size()
	_game.goto(GameState.Flow.RESULTS, {})
	await _game.transition_finished
	var empty := current_scene as Results
	_check(_results_texts(empty, ["Score", "Accuracy", "Hits", "Best"]) == [Results.NO_VALUE, Results.NO_VALUE, Results.NO_VALUE, Results.best_text(0)] and not (empty.get_node("%RivalPanel") as Control).visible and not (empty.get_node("%Stars") as Control).visible,
		"opened without run stats, the panels show dashes, no Rival panel, no stars", str(_results_texts(empty, ["Score", "Accuracy", "Hits", "Best"])))
	_check((empty.get_node("Safe/PlayAgainButton") as Control).visible and (empty.get_node("Safe/TitleButton") as Control).visible and (empty.get_node("Safe/PlayAgainButton") as Control).has_focus(), "opened without run stats: Play again (focused) and Title", str(root.gui_get_focus_owner()))
	_check_logged(opened_from, "^\\[Results\\] Opened without run stats \\(missing 'score'\\)$", "opening without stats is logged")
	_clear_tool_save()
	await _open_title()


## The texts of the results' Labels named: a unique name (Score, Best, Accuracy, Shots,
## Hits, Escaped, RivalScore, Steals) or Heading.
func _results_texts(results: Results, names: Array) -> Array:
	return names.map(func(n: String) -> String: return (results.get_node("Safe/Heading" if n == "Heading" else "%" + n) as Label).text)


## No text shown on the results screen is the verdict, the pigeons hit or the rival's
## line, and their labels are gone (results-panels AC 4).
func _check_results_hide_dropped_lines(results: Results, rival_line: String) -> void:
	var shown: Array[String] = []
	for text: Label in results.find_children("*", "Label", true, false):
		if text.is_visible_in_tree():
			shown.append(text.text)
	var dropped := shown.filter(func(text: String) -> bool: return "vs rival" in text or "igeon" in text or (rival_line != "" and rival_line in text))
	var gone := ["Verdict", "Pigeons", "RivalLine"].all(func(n: String) -> bool: return results.find_child(n, true, false) == null)
	_check(dropped.is_empty() and gone, "the results show no verdict, pigeons hit or rival's line", str(dropped))


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


## A screen's `controls` (buttons and sliders) and `labels` at 16:9, 19.5:9, 4:3, under a
## notch and at a safe height of RESULTS_MIN_SAFE_HEIGHT: every control at least 44x44,
## focusable with a visible focus ring (a Button's focus style; a TouchSlider draws the
## Button one), inside the safe area, below the top HUD bar, apart from the others; every
## label inside the safe area with all its text inside its rect (every wrapped line).
func _check_screen_layout(screen: Control, controls: Array[Control], labels: Array[Label]) -> void:
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
			var style := control.get_theme_stylebox(&"focus", &"Button") if control is TouchSlider else control.get_theme_stylebox(&"focus")
			if control.focus_mode != Control.FOCUS_ALL or style == null or style is StyleBoxEmpty:
				problems.append("%s has no visible keyboard focus" % control.name)
			if control is Button and (control as Button).get_combined_minimum_size().x > rect.size.x + 0.5:
				problems.append("%s's text is wider than it" % control.name)
		for label in labels:
			var rect := label.get_global_rect()
			var needed := label.get_line_count() * label.get_line_height() if label.autowrap_mode != TextServer.AUTOWRAP_OFF else int(label.get_combined_minimum_size().y)
			if not safe.grow(0.5).encloses(rect) or needed > rect.size.y + 0.5 or (label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.get_combined_minimum_size().x > rect.size.x + 0.5):
				problems.append("%s %s needs %d high for %d lines" % [label.name, rect, needed, label.get_line_count()])
		_check(problems.is_empty(), "%s %dx%d, safe %s: every control >= 44x44, focusable, inside the safe area, apart; every text inside its label" % [screen.name, windows[i].x, windows[i].y, safe], "; ".join(problems))
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


## The Music and SFX buses exist and send to Master; every sound player is on SFX and every
## music player on Music; the volumes and mutes set the buses at 0, a middle value,
## VOLUME_MAX and muted, and a loaded save applies its settings (plan AC 5).
func _test_audio_buses_follow_settings() -> void:
	var names: Array[String] = []
	for i in AudioServer.bus_count:
		names.append(AudioServer.get_bus_name(i))
	_check(names == ["Master", "Music", "SFX"], "the buses are Master, Music and SFX", str(names))
	var music_bus := AudioServer.get_bus_index(GameState.MUSIC_BUS)
	var sfx_bus := AudioServer.get_bus_index(GameState.SFX_BUS)
	for bus: int in [music_bus, sfx_bus]:
		_check(bus > 0 and AudioServer.get_bus_send(bus) == &"Master", "bus %s sends to Master" % AudioServer.get_bus_name(bus), str(AudioServer.get_bus_send(bus)))
	_check(_game.sfx_players().size() == GameState.SFX_VOICES + 1 and _game.sfx_players().all(func(player: AudioStreamPlayer) -> bool: return player.bus == GameState.SFX_BUS),
		"every sound effect player is on the SFX bus", str(_game.sfx_players().map(func(player: AudioStreamPlayer) -> StringName: return player.bus)))
	_check(_game.music_players().size() == 2 and _game.music_players().all(func(player: AudioStreamPlayer) -> bool: return player.bus == GameState.MUSIC_BUS),
		"every music player is on the Music bus", str(_game.music_players().map(func(player: AudioStreamPlayer) -> StringName: return player.bus)))
	var kept := [_game.music_volume, _game.sfx_volume, _game.music_muted, _game.sfx_muted]
	# Volume -> the bus level it must give: silent at 0, -6.02 dB at half, 0 dB at full.
	var levels := {0: GameState.SILENT_VOLUME_DB, 50: -6.0206, GameState.VOLUME_MAX: 0.0}
	for volume: int in levels:
		_game.set_music_volume(volume)
		_game.set_sfx_volume(volume)
		for bus: int in [music_bus, sfx_bus]:
			_check(absf(AudioServer.get_bus_volume_db(bus) - float(levels[volume])) < 0.01 and AudioServer.is_bus_mute(bus) == (volume == 0),
				"volume %d sets bus %s to %.2f dB%s" % [volume, AudioServer.get_bus_name(bus), levels[volume], ", muted" if volume == 0 else ""],
				"%.3f dB, mute %s" % [AudioServer.get_bus_volume_db(bus), AudioServer.is_bus_mute(bus)])
	_game.set_music_volume(70)
	_game.set_sfx_volume(80)
	_game.set_music_muted(true)
	_game.set_sfx_muted(true)
	for bus: int in [music_bus, sfx_bus]:
		var volume := 70 if bus == music_bus else 80
		_check(AudioServer.is_bus_mute(bus) and absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(volume / 100.0)) < 0.01,
			"muting bus %s mutes it and keeps its volume" % AudioServer.get_bus_name(bus), "mute %s, %.3f dB" % [AudioServer.is_bus_mute(bus), AudioServer.get_bus_volume_db(bus)])
	# A save's settings reach the buses on load (the game's start runs load_game).
	_game.set_music_volume(30)
	_game.set_sfx_muted(false)
	for bus: int in [music_bus, sfx_bus]:
		AudioServer.set_bus_volume_db(bus, 0.0)
		AudioServer.set_bus_mute(bus, false)
	_game.load_game()
	_check(AudioServer.is_bus_mute(music_bus) and absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.3)) < 0.01, "a loaded save's music volume and mute reach the Music bus",
		"mute %s, %.3f dB" % [AudioServer.is_bus_mute(music_bus), AudioServer.get_bus_volume_db(music_bus)])
	_check(not AudioServer.is_bus_mute(sfx_bus) and absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.8)) < 0.01, "a loaded save's sound volume reaches the SFX bus",
		"mute %s, %.3f dB" % [AudioServer.is_bus_mute(sfx_bus), AudioServer.get_bus_volume_db(sfx_bus)])
	_game.music_volume = kept[0]
	_game.sfx_volume = kept[1]
	_game.music_muted = kept[2]
	_game.set_sfx_muted(kept[3])


## Every sound effect id and syllable has its WAV (and no other WAV exists), each loads
## without a loop; every loop the game names (title, results, each chapter's and mode's)
## is an MP3 that loads looping, and no other exists; the crossfade is at most 0.5 s; the
## rival has a voice for every heckle category.
func _test_audio_files_match_ids() -> void:
	var expected: Array[String] = []
	for id: StringName in GameState.SFX_IDS + GameState.blurt_ids():
		expected.append("%s.wav" % id)
	expected.sort()
	var found: Array[String] = []
	for file in DirAccess.get_files_at("res://audio/sfx"):
		if file.ends_with(".wav"):
			found.append(file)
	found.sort()
	_check(found == expected, "every sound effect and syllable has its WAV, and no other WAV exists", "found %s, expected %s" % [found, expected])
	for file in found:
		var stream := load("res://audio/sfx/" + file) as AudioStreamWAV
		_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and stream.get_length() > 0.0, "sound %s loads and does not loop" % file, str(stream))
	var tracks: Array[String] = [GameState.TITLE_TRACK, GameState.RESULTS_TRACK]
	for spec in Content.chapters():
		tracks.append(spec.music)
	for spec in Content.modes():
		tracks.append(spec.music)
	tracks.sort()
	var loops: Array[String] = []
	for file in DirAccess.get_files_at("res://audio/music"):
		if file.ends_with(".mp3"):
			loops.append(file.get_basename())
	loops.sort()
	_check(loops == tracks, "the music loops are exactly the title's, the results', each chapter's and each mode's", "found %s, expected %s" % [loops, tracks])
	for track in loops:
		var stream := load(Content.music_path(track)) as AudioStreamMP3
		_check(stream != null and stream.loop and stream.get_length() > 20.0, "loop %s loads and loops" % track, str(stream))
	_check(GameState.CROSSFADE_TIME > 0.0 and GameState.CROSSFADE_TIME <= 0.5, "the crossfade takes at most 0.5 s", str(GameState.CROSSFADE_TIME))
	var categories: Array[String] = []
	categories.assign(GameState.HECKLE_VOICES.keys())
	_check(categories == RivalLines.CATEGORIES and GameState.HECKLE_VOICES.values().all(func(voice: Array) -> bool: return voice[0] in GameState.BLURT_TIMBRES),
		"the rival has a voice for every heckle category", str(GameState.HECKLE_VOICES))


## The music per screen: the title loop on the title and both selects (left playing, never
## restarted), the chapter's in a level, the mode's in Endless and Time Attack, the
## results' on results; each change crossfades and is logged (plan AC 7).
func _test_audio_music_per_screen() -> void:
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_check(_game.music_track == GameState.TITLE_TRACK and _game.music_player().stream.resource_path == Content.music_path("title"), "the title plays the title loop", _game.music_track)
	var title_player := _game.music_player()
	var changes := _game.music_changes
	_game.goto(GameState.Flow.CHAPTER_SELECT)
	await _game.transition_finished
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": "dawn"})
	await _game.transition_finished
	_check(_game.music_track == GameState.TITLE_TRACK and _game.music_changes == changes and _game.music_player() == title_player and is_equal_approx(title_player.volume_linear, 1.0),
		"the chapter and level selects keep the title loop playing untouched", "%s, %d changes" % [_game.music_track, _game.music_changes - changes])
	var from := _log.size()
	_game.start_level("dawn_1")
	await process_frame
	var fading_in := _game.music_player()
	_check(_game.music_track == "campaign_dawn" and fading_in != title_player and fading_in.volume_linear < 1.0, "a dawn level crossfades to the dawn loop", "%s, %.2f" % [_game.music_track, fading_in.volume_linear])
	_check_logged(from, "^\\[Audio\\] Music campaign_dawn \\(crossfading from title over 0\\.40 s\\)$", "the change of loop is logged")
	for i in ceili(GameState.CROSSFADE_TIME / FRAME) + 2:
		await process_frame
	_check(is_equal_approx(fading_in.volume_linear, 1.0) and is_zero_approx(title_player.volume_linear), "the crossfade is over within CROSSFADE_TIME", "%.2f in, %.2f out" % [fading_in.volume_linear, title_player.volume_linear])
	while _game.is_transitioning():
		await process_frame
	var expected := {"noon_1": "campaign_noon", "sunset_1": "campaign_sunset", "night_1": "campaign_night"}
	for level_id: String in expected:
		_game.start_level(level_id)
		await _game.transition_finished
		_check(_game.music_track == expected[level_id], "level %s plays %s" % [level_id, expected[level_id]], _game.music_track)
	_game.goto(GameState.Flow.RESULTS)
	await _game.transition_finished
	_check(_game.music_track == GameState.RESULTS_TRACK, "results play the results loop", _game.music_track)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_check(_game.music_track == GameState.TITLE_TRACK, "back on the title the title loop plays", _game.music_track)
	await _start_run(83)
	_check(_game.music_track == "endless", "Endless plays its loop", _game.music_track)
	changes = _game.music_changes
	(current_scene as Play).open_pause("test")
	(current_scene.get_node("PauseLayer/PauseMenu/Panel/RestartButton") as Button).pressed.emit()
	await _game.transition_finished
	_check(_game.music_track == "endless" and _game.music_changes == changes, "restarting Endless keeps its loop playing", "%s, %d changes" % [_game.music_track, _game.music_changes - changes])
	await _start_run(84, GameState.TIME_ATTACK_MODE)
	_check(_game.music_track == "time_attack", "Time Attack plays its loop", _game.music_track)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Every game event plays its sound through Game.play_sfx, exactly as listed (plan AC 8):
## the shot and what it did, the empty click alone, the waves, the rival, the pause, the
## buttons, the results.
func _test_audio_every_event_sound() -> void:
	var play := await _start_run(85)
	var cooldown := play.rival_lines.cooldown
	# Only the first heckle shows, so each shot's sounds are exact.
	play.rival_lines.cooldown = 1000.0
	var heard: Array[StringName] = []
	for i in 120:
		_game.sfx_log.clear()
		await process_frame
		if not play.flying_birds().is_empty():
			heard = _game.sfx_log.duplicate()
			break
	_check(heard == [&"wave_start", &"call_quack"], "the wave's first spawn plays wave_start, then the goose's call as its art shows above the grass", str(heard))
	var shot := (play.get_node("ShotInput") as ShotInput).shot
	var from := _log.size()
	_check(_sounds_of(func() -> void: shot.emit(_global(play, SKY_POINTS[0]))) == [&"shot"] + _heckle_sounds("miss"), "a miss plays the shot and the rival's miss heckle (silent while HECKLE_BLURTS is off)", str(_game.sfx_log))
	_check_logged(from, "^\\[Audio\\] SFX shot x[01]\\.\\d{3}$", "every sound is logged by the one entry point, with its varied pitch")
	var cases := [["goose", [&"shot", &"hit", &"combo_up"]], ["armored", [&"shot", &"armored_clank"]], ["armored", [&"shot", &"armored_kill", &"combo_up"]],
		["splitter", [&"shot", &"split_pop", &"combo_up", &"call_gosling", &"call_gosling"]], ["golden", [&"shot", &"golden_chime", &"combo_up"]], ["goose", [&"shot", &"hit"]], ["decoy", [&"shot", &"decoy_penalty"]]]
	var armored: Bird = null
	for entry: Array in cases:
		var bird := armored
		if entry[0] != "armored" or armored == null:
			bird = await _spawn_flying(play, 40 + cases.find(entry), IN_FIELD_AGE, entry[0])
		if entry[0] == "armored":
			armored = bird
		bird.set_process(false)
		play.set_shell_pool(5)
		var at := _global(play, bird.transform * LOCAL_BODY)
		_check(_sounds_of(func() -> void: shot.emit(at)) == entry[1], "a shot at a %s plays %s" % [entry[0], entry[1]], "%s (combo x%d)" % [_game.sfx_log, play.scoring.multiplier])
		bird.set_process(true)
	play.set_shell_pool(0)
	_check(_sounds_of(func() -> void: shot.emit(_global(play, SKY_POINTS[1]))) == [&"empty_click"], "a shot with an empty pool plays the empty click and nothing else", str(_game.sfx_log))
	play.set_shell_pool(5)
	_game.sfx_log.clear()
	var escaping := await _spawn_flying(play, 47, Content.bird("goose").flee_time - 0.5)
	var before := play.escaped
	await _escape_counts(play, escaping)
	_check(_game.sfx_log.count(&"escape") == play.escaped - before and play.escaped > before, "each counted escape plays escape", "%d escape sounds for %d escapes" % [_game.sfx_log.count(&"escape"), play.escaped - before])
	_game.sfx_log.clear()
	var cued := await _cued_bird(play, 48, "goose")
	_check(cued.is_cued() and _game.sfx_log.count(&"rival_aim") >= 1, "the rival's aim cue plays rival_aim", str(_game.sfx_log))
	_game.sfx_log.clear()
	var steal_from := _log.size()
	for i in 120:
		if cued.stolen:
			break
		await process_frame
	var line := play.heckle_shown()
	# The stolen bird falls off the screen and frees itself while the laugh is awaited.
	var was_stolen := cued.stolen
	var waited := 0
	while not &"rival_laugh" in _game.sfx_log and waited < 120:
		await process_frame
		waited += 1
	_check(was_stolen and _game.sfx_log.count(&"rival_steal") == 1 and _game.sfx_log.count(&"rival_laugh") == 1 and _game.sfx_log.find(&"rival_steal") < _game.sfx_log.find(&"rival_laugh"), "the rival's steal plays rival_steal, then rival_laugh", str(_game.sfx_log))
	_check(absi(waited - roundi(Play.RIVAL_LAUGH_DELAY / FRAME)) <= 2, "the laugh starts RIVAL_LAUGH_DELAY after the shot", "%d frames" % waited)
	_check(line != "" and not &"heckle_steal" in _game.sfx_log and not Array(_log.since(steal_from)).any(func(entry: String) -> bool: return entry.begins_with("[Audio] SFX heckle_steal")), "the steal line shows in the bubble with no gibberish blurt", "line \"%s\", %s" % [line, _game.sfx_log])
	_check_logged(steal_from, "^\\[Audio\\] SFX rival_steal$", "the steal shot is logged as an [Audio] SFX line")
	_check_logged(steal_from, "^\\[Audio\\] SFX rival_laugh$", "the laugh is logged as an [Audio] SFX line")
	_check_logged(steal_from, "^\\[Play\\] Heckle \\(steal\\) #\\d+: \".+\" \\(.*\\), no blurt$", "the steal heckle is logged without a blurt")
	var pause_button := play.get_node("Hud/Bar/PauseButton") as Control
	_game.sfx_log.clear()
	await _tap(pause_button)
	_check(_game.sfx_log.count(&"pause") == 1 and not &"ui_tap" in _game.sfx_log, "the pause button plays pause (no tap)", str(_game.sfx_log))
	_game.sfx_log.clear()
	await _tap(play.get_node("PauseLayer/PauseMenu/Panel/ResumeButton") as Control)
	_check(_game.sfx_log.count(&"resume") == 1 and not &"ui_tap" in _game.sfx_log, "Resume plays resume (no tap)", str(_game.sfx_log))
	play.rival_lines.cooldown = cooldown
	# A wave cleared: wave 1 of a new run, both geese shot as soon as they rise.
	play = await _start_run(86)
	var cleared := false
	for i in 400:
		for bird in play.flying_birds():
			if bird.wave_index == 1 and play.ammo.shells > 0:
				bird.age = maxf(bird.age, IN_FIELD_AGE)
		await process_frame
		for bird in play.flying_birds():
			if bird.wave_index == 1 and bird.age >= IN_FIELD_AGE:
				bird.set_process(false)
				shot.emit(_global(play, bird.transform * LOCAL_BODY))
				bird.set_process(true)
		if play.wave.index == 2:
			cleared = true
			break
		_game.sfx_log.clear()
	_check(cleared and _game.sfx_log.count(&"wave_clear") == 1, "a cleared wave plays wave_clear", "%s, wave %d" % [_game.sfx_log, play.wave.index])
	# A Time Attack wave lost to an empty pool.
	play = await _start_run(87, GameState.TIME_ATTACK_MODE)
	play.set_shell_pool(1)
	shot = (play.get_node("ShotInput") as ShotInput).shot
	var last_shot := _sounds_of(func() -> void: shot.emit(_global(play, SKY_POINTS[2])))
	_check(last_shot.slice(0, 1 + _heckle_sounds("miss").size()) == [&"shot"] + _heckle_sounds("miss") and last_shot.count(&"out_of_shells") == 1 and last_shot.find(&"out_of_shells") < last_shot.find(&"wave_lost"),
		"the shot that uses the last shell plays out_of_shells", str(last_shot))
	_check(last_shot.count(&"wave_lost") == 1 and play.wave.index == 2, "a lost Time Attack wave plays wave_lost", str(last_shot))
	# A button press plays the tap; the results play the rival's blurt, a sound per star and the new best.
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	await process_frame
	_game.sfx_log.clear()
	var chapters := (current_scene as Title).get_node("Safe/CampaignButton") as Button
	await _tap(chapters)
	_check(_game.sfx_log == [&"ui_tap"], "a button press plays ui_tap", str(_game.sfx_log))
	await _game.transition_finished
	var level := Content.level("dawn_1")
	var stats := {"seed": 1, "score": level.stars[1], "shots": 4, "hits": 3, "kills": 3, "pigeons": 0, "escaped": 0, "stolen": 0, "rival_score": 0,
		"rival_line": "Beginner's luck, kid.", "rival_steals": true, "best": level.stars[1], "new_best": true, "save_error": "", "level": "dawn_1", "stars": 2,
		"best_stars": 2, "next_level": "dawn_2"}
	_game.sfx_log.clear()
	_game.goto(GameState.Flow.RESULTS, stats)
	await _game.transition_finished
	for i in ceili(4 * Results.STAR_SOUND_GAP / FRAME) + 2:
		await process_frame
	_check(_game.sfx_log == _heckle_sounds("results") + [&"star", &"star", &"new_best"], "the results play the rival's blurt (silent while HECKLE_BLURTS is off), one sound per star and the new best", str(_game.sfx_log))
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## A heckle's blurt: one syllable per word (at most BLURT_SYLLABLES_MAX), the same line
## always the same blurt, the category setting the timbre and pitch; in a run each heckle
## shown plays its blurt, whose syllables start one after another (plan AC 9).
func _test_audio_heckle_blurts() -> void:
	var line := "Nice shot... at the clouds!"
	var plan := GameState.blurt_plan("miss", line)
	var again := GameState.blurt_plan("miss", line)
	_check(plan.size() == 5 and _plan_text(plan) == _plan_text(again), "the same line always gives the same blurt, a syllable per word", _plan_text(plan))
	_check(GameState.blurt_plan("miss", "Hey").size() == 1 and GameState.blurt_plan("miss", "one two three four five six seven eight nine").size() == GameState.BLURT_SYLLABLES_MAX,
		"a blurt has one syllable per word, at most BLURT_SYLLABLES_MAX", "%d, %d" % [GameState.blurt_plan("miss", "Hey").size(), GameState.blurt_plan("miss", "one two three four five six seven eight nine").size()])
	_check(_plan_text(plan) != _plan_text(GameState.blurt_plan("miss", "Nice shot... at the swans!")), "another line gives another blurt", _plan_text(plan))
	var texts: Array[String] = []
	for category in RivalLines.CATEGORIES:
		var voiced := GameState.blurt_plan(category, line)
		var voice: Array = GameState.HECKLE_VOICES[category]
		_check(voiced.size() == plan.size() and voiced.all(func(syllable: GameState.Syllable) -> bool: return String(syllable.sound).begins_with("blurt_%s_" % voice[0]) and syllable.sound in GameState.blurt_ids()),
			"a %s heckle speaks in the %s voice" % [category, voice[0]], _plan_text(voiced))
		for i in voiced.size():
			if not is_equal_approx(voiced[i].pitch / float(voice[1]), plan[i].pitch / float(GameState.HECKLE_VOICES["miss"][1])) or voiced[i].at != plan[i].at:
				_check(false, "a %s heckle keeps the line's rhythm and melody at its own pitch" % category, _plan_text(voiced))
				break
		texts.append(_plan_text(voiced))
	_check(texts.size() == RivalLines.CATEGORIES.size() and texts.all(func(text: String) -> bool: return texts.count(text) == 1), "every category sounds different", str(texts))
	_check(GameState.blurt_plan("whistle", line).is_empty(), "an unknown category has no blurt", "")
	# With HECKLE_BLURTS off (the experiment) a heckle shows its line but makes no sound,
	# and the log says so.
	_game.heckle_blurts = false
	var muted := await _start_run(88)
	var muted_from := _log.size()
	_game.sfx_log.clear()
	(muted.get_node("ShotInput") as ShotInput).shot.emit(_global(muted, SKY_POINTS[0]))
	var muted_line := muted.heckle_shown()
	_check(muted_line != "" and _game.sfx_log == [&"shot"] and _game.blurt_syllables_waiting() == 0, "with blurts off a miss heckle shows its line and plays no blurt", "%s, %d waiting for \"%s\"" % [_game.sfx_log, _game.blurt_syllables_waiting(), muted_line])
	_check_logged(muted_from, "^\\[Audio\\] Heckle blurt muted \\(HECKLE_BLURTS off\\) for heckle_miss: \".+\"$", "the muted blurt is logged")
	_check(not Array(_log.since(muted_from)).any(func(entry: String) -> bool: return entry.begins_with("[Audio] SFX heckle_")), "no heckle sound is logged with blurts off", "")
	# The blurts themselves, switched on.
	_game.heckle_blurts = true
	var play := await _start_run(88)
	var from := _log.size()
	_game.sfx_log.clear()
	(play.get_node("ShotInput") as ShotInput).shot.emit(_global(play, SKY_POINTS[0]))
	var shown := play.heckle_shown()
	var words := mini(shown.split(" ", false).size(), GameState.BLURT_SYLLABLES_MAX)
	_check(shown != "" and &"heckle_miss" in _game.sfx_log and _game.blurt_syllables_waiting() == words, "a miss heckle plays its blurt, one syllable per word", "%s, %d waiting for \"%s\"" % [_game.sfx_log, _game.blurt_syllables_waiting(), shown])
	var blurt_lines := Array(_log.since(from)).filter(func(entry: String) -> bool: return entry.begins_with("[Audio] SFX heckle_miss: %d syllables (nasal_" % words) and entry.ends_with(" for \"%s\"" % shown))
	_check(blurt_lines.size() == 1, "the blurt is logged with its syllables and line", str(blurt_lines))
	play.open_pause("test")
	for i in 30:
		await process_frame
	_check(_game.blurt_syllables_waiting() == words, "the blurt waits while the game is paused", "%d waiting" % _game.blurt_syllables_waiting())
	play.resume()
	for i in ceili(GameState.BLURT_SYLLABLES_MAX * GameState.BLURT_GAP * 1.2 / FRAME) + 2:
		await process_frame
	_check(_game.blurt_syllables_waiting() == 0, "the blurt's syllables all start once resumed", "%d waiting" % _game.blurt_syllables_waiting())
	_game.heckle_blurts = GameState.HECKLE_BLURTS
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Time Attack's last 10 s tick once each and the end sounds the buzzer once; a pause stops
## the countdown (plan AC 10).
func _test_time_attack_countdown() -> void:
	var play := await _start_run(89, GameState.TIME_ATTACK_MODE)
	var limit := play.mode.time_limit
	play.mode.time_limit = 13.0
	_game.sfx_log.clear()
	var ticks: Array[float] = []
	var paused_ticks := -1
	var paused_clock := -1.0
	Engine.time_scale = 4.0
	for i in 600:
		if not is_instance_valid(play) or current_scene != play:
			break
		var count := play.countdown_ticks
		await process_frame
		if not is_instance_valid(play) or current_scene != play:
			break
		if play.countdown_ticks > count:
			ticks.append(play.run_clock)
		if play.countdown_ticks == 4 and paused_ticks < 0:
			play.open_pause("test")
			paused_clock = play.run_clock
			for j in 60:
				await process_frame
			paused_ticks = play.countdown_ticks
			_check(paused_ticks == 4 and play.run_clock == paused_clock, "a pause stops the countdown", "%d ticks, clock %.2f -> %.2f" % [paused_ticks, paused_clock, play.run_clock])
			play.resume()
	Engine.time_scale = 1.0
	Content.mode(GameState.TIME_ATTACK_MODE).time_limit = limit
	_check(ticks.size() == Play.COUNTDOWN_SECONDS and _game.sfx_log.count(&"countdown_tick") == Play.COUNTDOWN_SECONDS, "the last 10 s tick 10 times", "%d ticks at %s, %d sounds" % [ticks.size(), ticks, _game.sfx_log.count(&"countdown_tick")])
	for k in ticks.size():
		var due := 13.0 - (Play.COUNTDOWN_SECONDS - k)
		_check(ticks[k] >= due - 0.001 and ticks[k] < due + 4.0 * FRAME + 0.001, "tick %d sounds as %d s are left" % [k + 1, Play.COUNTDOWN_SECONDS - k], "at run clock %.3f, due %.3f" % [ticks[k], due])
	_check(_game.sfx_log.count(&"time_up") == 1 and _game.sfx_log.find(&"time_up") > _game.sfx_log.rfind(&"countdown_tick"), "time running out sounds the buzzer once, after the last tick", str(_game.sfx_log.count(&"time_up")))
	await _game.transition_finished
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## The pause menu's Music and SFX toggles: focusable, at least 44x44 and inside the safe
## area at three aspects and under a notch, showing their state; a press mutes the bus at
## once, saves, logs and survives a reload (plan AC 11).
func _test_pause_menu_mutes() -> void:
	var play := await _start_run(90)
	play.open_pause("test")
	await process_frame
	var panel := play.get_node("PauseLayer/PauseMenu/Panel")
	var toggles: Array[Button] = [panel.get_node("MusicToggle"), panel.get_node("SfxToggle")]
	for window in LANDSCAPE_WINDOWS:
		root.size = window
		await process_frame
		for toggle in toggles:
			var rect := toggle.get_global_rect()
			_check(rect.size.x >= MIN_TARGET and rect.size.y >= MIN_TARGET and _game.safe_rect().encloses(rect), "%s is >= 44x44 inside the safe area at %s" % [toggle.name, window], "%s in %s" % [rect, _game.safe_rect()])
	_game.safe_area_override = NOTCHED_SAFE_RECT
	root.size = LANDSCAPE_19_5_9
	await process_frame
	for toggle in toggles:
		_check(_game.safe_rect().encloses(toggle.get_global_rect()), "%s is inside a notched safe area" % toggle.name, "%s in %s" % [toggle.get_global_rect(), _game.safe_rect()])
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame
	for toggle in toggles:
		var style := toggle.get_theme_stylebox(&"focus")
		_check(toggle.toggle_mode and toggle.button_pressed and toggle.text.ends_with(": on") and toggle.focus_mode == Control.FOCUS_ALL and style != null and not (style is StyleBoxEmpty),
			"%s shows it is on and is focusable with a visible focus style" % toggle.name, toggle.text)
	var buses := [GameState.MUSIC_BUS, GameState.SFX_BUS]
	for i in toggles.size():
		var toggle := toggles[i]
		var bus := AudioServer.get_bus_index(buses[i])
		var from := _log.size()
		await _tap(toggle)
		var muted := _game.music_muted if i == 0 else _game.sfx_muted
		_check(muted and AudioServer.is_bus_mute(bus) and not toggle.button_pressed and toggle.text.ends_with(": off"), "a press on %s mutes its bus at once and shows it off" % toggle.name, "%s, bus mute %s" % [toggle.text, AudioServer.is_bus_mute(bus)])
		_check_logged(from, "^\\[Audio\\] %s muted$" % ["Music", "SFX"][i], "%s's mute is logged" % toggle.name)
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
		var key := "music_muted" if i == 0 else "sfx_muted"
		_check(saved is Dictionary and (saved as Dictionary)["settings"][key] == true, "%s's mute is saved" % toggle.name, str(saved))
		_game.load_game()
		_check((_game.music_muted if i == 0 else _game.sfx_muted) and AudioServer.is_bus_mute(bus) and toggle.text.ends_with(": off"), "%s's mute survives a reload" % toggle.name, toggle.text)
		await _tap(toggle)
		_check(not (_game.music_muted if i == 0 else _game.sfx_muted) and not AudioServer.is_bus_mute(bus) and toggle.button_pressed and toggle.text.ends_with(": on"), "a second press on %s unmutes it" % toggle.name, toggle.text)
	play.resume()
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Pausing holds the sounds in flight (the pause's own sound plays) and ducks the music;
## resuming restores both; the rotate overlay's pause does the same (plan AC 12).
func _test_pause_holds_sounds_and_ducks_music() -> void:
	var play := await _start_run(91)
	var music_bus := AudioServer.get_bus_index(GameState.MUSIC_BUS)
	var full := AudioServer.get_bus_volume_db(music_bus)
	_game.play_sfx(&"time_up")
	_check(_game.sounds_in_flight() >= 1 and not _game.audio_paused, "a sound is in flight while the run plays", str(_game.sounds_in_flight()))
	var from := _log.size()
	play.open_pause("test")
	var held := _game.held_players()
	var pause_sound := _game.sfx_players().filter(func(player: AudioStreamPlayer) -> bool: return player.stream != null and player.stream.resource_path.ends_with("/pause.wav"))
	_check(_game.audio_paused and _game.held_sounds >= 1 and held.size() == _game.held_sounds and held.any(func(player: AudioStreamPlayer) -> bool: return player.stream.resource_path.ends_with("/time_up.wav")),
		"pausing holds the sound in flight", "held %d: %s" % [_game.held_sounds, held.map(func(player: AudioStreamPlayer) -> String: return player.stream.resource_path)])
	_check(pause_sound.size() == 1 and not pause_sound[0] in held, "the pause's own sound plays", str(pause_sound))
	_check(absf(AudioServer.get_bus_volume_db(music_bus) - (full + GameState.PAUSE_DUCK_DB)) < 0.01 and AudioServer.get_bus_volume_db(music_bus) <= full - 6.0 and _game.music_track == "endless",
		"pausing ducks the music (at least 6 dB quieter), which keeps playing",
		"%.2f dB (full %.2f), %s" % [AudioServer.get_bus_volume_db(music_bus), full, _game.music_track])
	_check_logged(from, "^\\[Audio\\] Paused: \\d+ sounds held, \\d+ blurt syllables waiting, music ducked by 12 dB$", "the audio pause is logged")
	for i in 60:
		await process_frame
	_check(_game.held_players() == held and _game.sounds_in_flight() >= held.size(), "the held sound stays held while paused", str(_game.sounds_in_flight()))
	play.resume()
	_check(not _game.audio_paused and _game.held_players().is_empty() and absf(AudioServer.get_bus_volume_db(music_bus) - full) < 0.01, "resuming continues the sound and the music",
		"%.2f dB" % AudioServer.get_bus_volume_db(music_bus))
	_check_logged(from, "^\\[Audio\\] Resumed after [\\d.]+ s: \\d+ sounds continue, the music is back to full$", "the audio resume is logged")
	_game.play_sfx(&"time_up")
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.audio_paused and _game.held_sounds >= 1 and absf(AudioServer.get_bus_volume_db(music_bus) - (full + GameState.PAUSE_DUCK_DB)) < 0.01, "the rotate overlay holds the sounds and ducks the music",
		"held %d, %.2f dB" % [_game.held_sounds, AudioServer.get_bus_volume_db(music_bus)])
	root.size = BASE_WINDOW
	await process_frame
	_check(play.is_paused() and _game.audio_paused and absf(AudioServer.get_bus_volume_db(music_bus) - (full + GameState.PAUSE_DUCK_DB)) < 0.01, "back in landscape the menu keeps the audio paused", "%.2f dB" % AudioServer.get_bus_volume_db(music_bus))
	play.resume()
	_check(not _game.audio_paused and _game.held_sounds == 0 and absf(AudioServer.get_bus_volume_db(music_bus) - full) < 0.01, "resuming after the overlay restores the audio", "%.2f dB" % AudioServer.get_bus_volume_db(music_bus))
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## A missing or unknown sound, a missing loop and a screen whose loop is missing are each
## reported with the path (log and error label), never skipped quietly (plan AC 13).
func _test_audio_missing_files_reported() -> void:
	var label := _game.get_node("Fade/ErrorLabel") as Label
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	_game.sfx_path = "res://audio/sfx/missing_%s.wav"
	_game.sfx_log.clear()
	_game.play_sfx(&"shot")
	_check(_game.reported_errors.slice(errors) == ["Sound effect 'shot' is missing: res://audio/sfx/missing_shot.wav (run python3 tools/sfx.py)"] and label.visible and label.text.contains("missing_shot.wav") and _game.sfx_log.is_empty(),
		"a missing sound effect is reported with its path, on screen", str(_game.reported_errors.slice(errors)))
	errors = _game.reported_errors.size()
	_check(not _game.check_audio() and _game.reported_errors.size() - errors == GameState.SFX_IDS.size() + GameState.blurt_ids().size(), "the start-up check reports every missing sound", str(_game.reported_errors.size() - errors))
	_game.sfx_path = GameState.SFX_PATH
	errors = _game.reported_errors.size()
	_game.play_sfx(&"trumpet")
	_check(_game.reported_errors.slice(errors) == ["Unknown sound effect 'trumpet' (not in GameState.SFX_IDS)"], "an unknown sound effect is reported", str(_game.reported_errors.slice(errors)))
	errors = _game.reported_errors.size()
	var track := _game.music_track
	_game.play_music("banjo_solo")
	_check(_game.reported_errors.slice(errors) == ["Music track 'banjo_solo' is missing: res://audio/music/banjo_solo.mp3 (run python3 tools/music.py)"] and _game.music_track == track,
		"a missing loop is reported with its path and the music stays", str(_game.reported_errors.slice(errors)))
	var dawn := Content.chapter("dawn")
	var real := dawn.music
	dawn.music = "campaign_dusk"
	errors = _game.reported_errors.size()
	var scene := current_scene
	_game.start_level("dawn_1")
	await process_frame
	dawn.music = real
	_check(_game.reported_errors.slice(errors) == ["Cannot go to PLAY: scene 'res://scenes/play.tscn' needs res://audio/music/campaign_dusk.mp3, which is missing"]
		and current_scene == scene and not _game.is_transitioning() and _game.state == GameState.Flow.TITLE, "goto refuses a screen whose loop is missing and names it", str(_game.reported_errors.slice(errors)))
	_check(_game.check_audio(), "with every file back the audio check passes", "")
	_game.quiet_errors = false
	label.hide()


## Taps the game drops play no shot sound: during a transition, under the pause menu and
## under the rotate overlay, a real touch on the sky and a shot that reaches the play scene
## anyway (ShotInput.shot), with shells and with an empty pool, play neither "shot" nor
## "empty_click" and count no shot (the pause button's tap is _test_audio_every_event_sound's).
func _test_dropped_taps_are_silent() -> void:
	var play := await _start_run(94)
	_game.goto(GameState.Flow.TITLE)
	await process_frame
	_check(_game.is_transitioning(), "a transition is running", "")
	await _check_dropped_taps(play, "during a transition")
	_check(_game.is_transitioning(), "the taps were all made during the transition", "it finished first")
	await _game.transition_finished
	play = await _start_run(95)
	play.open_pause("test")
	await process_frame
	await _check_dropped_taps(play, "under the pause menu")
	play.resume()
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown(), "the rotate overlay shows", "")
	await _check_dropped_taps(play, "under the rotate overlay")
	root.size = BASE_WINDOW
	await process_frame
	play.resume()
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## With all SFX_VOICES pool voices sounding as the pause opens, every one is held and none
## is taken over: the pause sound (and a menu tap) play on the menu voice, and on resuming
## every held sound continues where it was.
func _test_pause_keeps_every_held_sound() -> void:
	var play := await _start_run(96)
	for i in GameState.SFX_VOICES:
		_game.play_sfx(&"time_up")
	var pool := _game.sfx_players().slice(0, GameState.SFX_VOICES)
	_check(_game.sounds_in_flight() == GameState.SFX_VOICES and pool.all(func(player: AudioStreamPlayer) -> bool: return player.stream.resource_path.ends_with("/time_up.wav")),
		"every pool voice is sounding", str(_game.sounds_in_flight()))
	play.open_pause("test")
	_game.play_sfx(&"ui_tap")
	var menu := _game.sfx_players().back() as AudioStreamPlayer
	_check(_game.held_players() == pool and pool.all(func(player: AudioStreamPlayer) -> bool: return player.stream.resource_path.ends_with("/time_up.wav")),
		"all %d held sounds keep their voices while the pause menu's sounds play" % GameState.SFX_VOICES, str(pool.map(func(player: AudioStreamPlayer) -> String: return player.stream.resource_path.get_file())))
	_check(menu.bus == GameState.SFX_BUS and menu.stream != null and menu.stream.resource_path.ends_with("/ui_tap.wav") and _game.sfx_log.slice(-2) == [&"pause", &"ui_tap"],
		"the pause and the tap play on the menu voice", "%s, %s" % [menu.stream, _game.sfx_log.slice(-2)])
	for i in 30:
		await process_frame
	play.resume()
	_check(_game.held_players().is_empty() and _game.sounds_in_flight() == GameState.SFX_VOICES and pool.all(func(player: AudioStreamPlayer) -> bool: return player.stream.resource_path.ends_with("/time_up.wav")),
		"on resuming every held sound continues", "%d in flight" % _game.sounds_in_flight())
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## A sound or loop file that exists but is not audio (a resource of another type) is reported
## with its path, on the error label and in the reported errors (the log), and plays nothing;
## Game's loop files are the data's (MUSIC_PATH matches Content.music_path).
func _test_audio_unloadable_files_reported() -> void:
	_check(GameState.MUSIC_PATH % "title" == Content.music_path("title"), "Game and Content name the same loop files", GameState.MUSIC_PATH)
	var not_audio := "[gd_resource type=\"Gradient\" format=3]\n\n[resource]\n"
	for path: String in ["user://not_audio_shot.tres", "user://not_audio_banjo_jam.tres"]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(not_audio)
		file.close()
	var label := _game.get_node("Fade/ErrorLabel") as Label
	_game.quiet_errors = true
	_game.sfx_path = "user://not_audio_%s.tres"
	_game.music_path = "user://not_audio_%s.tres"
	var errors := _game.reported_errors.size()
	_game.sfx_log.clear()
	_game.play_sfx(&"shot")
	var sfx_message := "Sound effect 'shot' at user://not_audio_shot.tres cannot be loaded as audio"
	_check(_game.reported_errors.slice(errors) == [sfx_message] and label.visible and label.text == sfx_message and _game.sfx_log.is_empty(),
		"a sound effect file that is not audio is reported with its path, on screen, and plays nothing", str(_game.reported_errors.slice(errors)))
	errors = _game.reported_errors.size()
	var track := _game.music_track
	_game.play_music("banjo_jam")
	var music_message := "Music track 'banjo_jam' at user://not_audio_banjo_jam.tres cannot be loaded as audio"
	_check(_game.reported_errors.slice(errors) == [music_message] and label.visible and label.text == music_message and _game.music_track == track,
		"a loop file that is not audio is reported with its path, on screen, and the music stays", str(_game.reported_errors.slice(errors)))
	_game.sfx_path = GameState.SFX_PATH
	_game.music_path = GameState.MUSIC_PATH
	_game.quiet_errors = false
	label.hide()
	for path: String in ["user://not_audio_shot.tres", "user://not_audio_banjo_jam.tres"]:
		DirAccess.remove_absolute(path)


## The shot, the plain hit and the escape each play at a pitch within SOUND_PITCH_SPREAD of
## 1, not all the same, and the same run seed gives the same pitches.
func _test_frequent_sounds_vary_in_pitch() -> void:
	var low := 1.0 - Play.SOUND_PITCH_SPREAD
	var high := 1.0 + Play.SOUND_PITCH_SPREAD
	var runs: Array[Array] = []
	for attempt in 2:
		var play := await _start_run(97)
		var shot := (play.get_node("ShotInput") as ShotInput).shot
		play.set_shell_pool(30)
		_game.sfx_log.clear()
		for i in 12:
			shot.emit(_global(play, SKY_POINTS[i % SKY_POINTS.size()]))
		runs.append(_pitches_of(&"shot"))
		if attempt == 1:
			break
		var shots: Array[float] = runs[0]
		_check(shots.size() == 12 and shots.all(func(pitch: float) -> bool: return pitch >= low and pitch <= high) and shots.any(func(pitch: float) -> bool: return pitch != shots[0]),
			"12 shots play at pitches within %.2f..%.2f, not all the same" % [low, high], str(shots))
		_game.sfx_log.clear()
		for i in 3:
			var bird := await _spawn_flying(play, 60 + i)
			bird.set_process(false)
			shot.emit(_global(play, bird.transform * LOCAL_BODY))
		var hits := _pitches_of(&"hit")
		_check(hits.size() == 3 and hits.all(func(pitch: float) -> bool: return pitch >= low and pitch <= high) and hits.any(func(pitch: float) -> bool: return pitch != hits[0]),
			"3 hits play at pitches within the band, not all the same", str(hits))
		_game.sfx_log.clear()
		await _escape_counts(play, await _spawn_flying(play, 64, Content.bird("goose").flee_time - 0.5))
		var escapes := _pitches_of(&"escape")
		_check(not escapes.is_empty() and escapes.all(func(pitch: float) -> bool: return pitch >= low and pitch <= high and pitch != 1.0), "an escape plays at a varied pitch within the band", str(escapes))
	_check(runs[0] == runs[1], "the same run seed gives the same shot pitches", "%s vs %s" % runs)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Every bird type gives its call (spec.call_sound at spec.call_pitch) exactly once, the
## first frame any of its drawn art shows above the grass line (Play.GRASS_Y). Today a
## rising bird's climb tilt already lifts its art above the line on its spawn frame, so it
## calls as it spawns, with shells and spawned into an empty pool (already fleeing) alike;
## the art is checked with _drawn_art_top, a scan of every opaque pixel the bird's Sprite
## draws (independent of Bird.art_top's hull). The call is the sound Play plays as it
## handles Bird.appeared, logged as a [Play] line. Fleeing makes no sound (the last shell's
## out-of-shells sweep, a second flee()), and the bird never calls again, flying on until
## it escapes. The rule itself: a stand-in of each type placed lower (the same bird
## STAND_IN_AGE seconds before its spawn point, its art wholly under the grass) emits
## nothing until it rises, and emits appeared on the first frame its art shows above the
## line. A splitter's goslings call on their launch frame. Steals are off, so every bird
## flies off on its own.
func _test_bird_calls_on_appearing() -> void:
	var play := await _start_run(88)
	var shot := (play.get_node("ShotInput") as ShotInput).shot
	play.mode.rival_steals = false
	var bird_seed := 300
	for spec in Content.birds():
		var call_id := StringName(spec.call_sound)
		for empty_pool: bool in [false, true]:
			var way := "spawned into an empty pool, fleeing" if empty_pool else "with shells"
			bird_seed += 1
			# Every case's birds escape: keep the run from ending on Endless's escape limit.
			play.escaped = 0
			play.set_shell_pool(0 if empty_pool else 5)
			var from := _log.size()
			var spawned: Array[Bird] = []
			var heard := _sounds_of(func() -> void: spawned.append(play.spawn_bird(spec.id, bird_seed)))
			var bird := spawned[0]
			var pitches := _pitches_of(call_id)
			var top := _drawn_art_top(play, bird)
			_check(heard == [call_id] and pitches.size() == 1 and is_equal_approx(pitches[0], spec.call_pitch),
				"%s calls %s x%.2f once as it spawns (%s)" % [spec.id, call_id, spec.call_pitch, way], "%s at %s" % [heard, pitches])
			_check(top < Play.GRASS_Y, "%s's art shows above the grass line on its spawn frame (%s)" % [spec.id, way], "art top %.2f, grass line %.0f" % [top, Play.GRASS_Y])
			_check_logged(from, "^\\[Play\\] Call of %s #%d as it appears above the grass: %s x%.2f \\(art top \\d+\\.\\d, age 0\\.00, wave \\d+ at t -?\\d+\\.\\d{2}\\)$" % [spec.id, bird.number, call_id, spec.call_pitch],
				"%s's call is logged (%s)" % [spec.id, way])
			var again: Array[int] = [0]
			bird.appeared.connect(func(_caller: Bird) -> void: again[0] += 1)
			if not empty_pool:
				bird.age = IN_FIELD_AGE
				await process_frame
				play.set_shell_pool(1)
				var last_shot := _sounds_of(func() -> void: shot.emit(_global(play, SKY_POINTS[2])))
				_check(bird.is_fleeing() and &"out_of_shells" in last_shot and not last_shot.any(func(id: StringName) -> bool: return String(id).begins_with("call_")),
					"%s: running out of shells makes it flee with no call" % spec.id, str(last_shot))
			_check(_sounds_of(func() -> void: bird.flee()).is_empty(), "%s: being told to flee again makes no sound (%s)" % [spec.id, way], str(_game.sfx_log))
			Engine.time_scale = FAST_TIME_SCALE
			for i in 600:
				if not is_instance_valid(bird):
					break
				await process_frame
			Engine.time_scale = 1.0
			# The frame after a time scale change still runs at the old scale.
			await process_frame
			_check(not is_instance_valid(bird) and again[0] == 0, "%s never calls again, fleeing and flying on until it escapes (%s)" % [spec.id, way], "%d more calls" % again[0])
		# The rule on a stand-in placed lower: wholly under the grass, then rising out of it.
		var stand_in := Play.BIRD_SCENE.instantiate() as Bird
		stand_in.setup(spec, 900, bird_seed, 1.0, Play.FIELD, false)
		stand_in.age = STAND_IN_AGE
		# [times emitted, the drawn art top then]
		var emitted: Array = [0, INF]
		stand_in.appeared.connect(func(caller: Bird) -> void:
			emitted[0] += 1
			emitted[1] = _drawn_art_top(play, caller))
		(play.get_node("World/Birds") as Node2D).add_child(stand_in)
		var hidden := _drawn_art_top(play, stand_in)
		_check(emitted[0] == 0 and hidden >= Play.GRASS_Y, "a %s stand-in wholly under the grass does not appear" % spec.id, "%d emitted, art top %.2f" % [emitted[0], hidden])
		var before := hidden
		var shown_early := -1
		for i in 120:
			await process_frame
			if emitted[0] > 0:
				break
			before = _drawn_art_top(play, stand_in)
			if before < Play.GRASS_Y and shown_early < 0:
				shown_early = i
		for i in 10:
			await process_frame
		_check(emitted[0] == 1 and shown_early < 0 and before >= Play.GRASS_Y and emitted[1] < Play.GRASS_Y,
			"a %s stand-in appears once, on the first frame its art shows above the grass line" % spec.id,
			"%d emitted, art top %.2f the frame before and %.2f then (grass line %.0f), shown without appearing at frame %d" % [emitted[0], before, emitted[1], Play.GRASS_Y, shown_early])
		stand_in.queue_free()
	# A splitter's goslings appear mid-air at the split: each calls on its launch frame.
	play.escaped = 0
	play.set_shell_pool(5)
	var splitter := await _spawn_flying(play, 390, IN_FIELD_AGE, "splitter")
	splitter.set_process(false)
	var at := _global(play, splitter.transform * LOCAL_BODY)
	var split_from := _log.size()
	var split_heard := _sounds_of(func() -> void: shot.emit(at))
	var goslings: Array[Bird] = []
	goslings.assign(play.flying_birds().filter(func(bird: Bird) -> bool: return bird.spec.id == "gosling" and bird.number > splitter.number))
	var gosling_spec := Content.bird("gosling")
	_check(goslings.size() == 2 and split_heard.count(StringName(gosling_spec.call_sound)) == 2 and _pitches_of(StringName(gosling_spec.call_sound)).all(func(pitch: float) -> bool: return is_equal_approx(pitch, gosling_spec.call_pitch)),
		"the split's two goslings each call %s x%.2f on their launch frame" % [gosling_spec.call_sound, gosling_spec.call_pitch], "%d goslings, %s" % [goslings.size(), split_heard])
	for gosling in goslings:
		_check(_drawn_art_top(play, gosling) < Play.GRASS_Y, "gosling #%d shows above the grass as it calls" % gosling.number, "art top %.2f" % _drawn_art_top(play, gosling))
		_check_logged(split_from, "^\\[Play\\] Call of gosling #%d as it appears above the grass: " % gosling.number, "gosling #%d's call is logged" % gosling.number)
	var later: Array[int] = [0]
	for gosling in goslings:
		gosling.appeared.connect(func(_caller: Bird) -> void: later[0] += 1)
		gosling.flee()
	Engine.time_scale = FAST_TIME_SCALE
	for i in 600:
		if _all_freed(goslings):
			break
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	_check(later[0] == 0 and _all_freed(goslings), "the goslings never call again, fleeing until they escape", "%d more calls" % later[0])
	play.mode.rival_steals = true
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## True when every bird of `birds` has been freed (read by index: a freed bird cannot be
## passed to a typed lambda).
func _all_freed(birds: Array[Bird]) -> bool:
	for i in birds.size():
		if is_instance_valid(birds[i]):
			return false
	return true


## The highest point (World y) of the opaque pixels (alpha >= Bird.OPAQUE_ALPHA) `bird`'s
## Sprite draws now: every corner of every opaque pixel of its current texture through the
## Sprite's global transform, brought into World (so a Birds offset or a scale would show).
func _drawn_art_top(play: Play, bird: Bird) -> float:
	var sprite := bird.get_node("Sprite") as Sprite2D
	if not _opaque_corners.has(sprite.texture.resource_path):
		var image := sprite.texture.get_image()
		if image.is_compressed():
			image.decompress()
		var corners: Dictionary[Vector2i, bool] = {}
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a >= Bird.OPAQUE_ALPHA:
					for corner: Vector2i in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]:
						corners[corner] = true
		var centred := PackedVector2Array()
		for corner: Vector2i in corners:
			centred.append(Vector2(corner) - Vector2(image.get_size()) / 2.0)
		_opaque_corners[sprite.texture.resource_path] = centred
	var to_world := (play.get_node("World") as Node2D).get_global_transform().affine_inverse() * sprite.get_global_transform()
	var top := INF
	for point in _opaque_corners[sprite.texture.resource_path]:
		top = minf(top, (to_world * point).y)
	return top


## The title's geese (crossing birds) never call, not even crossing the whole band:
## Bird.appeared never fires for a crossing bird and no call sound plays.
func _test_title_geese_never_call() -> void:
	await _open_title()
	var title := current_scene as Title
	var calls: Array[String] = []
	var watched: Dictionary[Bird, bool] = {}
	_game.sfx_log.clear()
	Engine.time_scale = 4.0
	for i in 450:
		for goose in title.flying_geese():
			if not watched.has(goose):
				watched[goose] = true
				goose.appeared.connect(func(bird: Bird) -> void: calls.append("goose #%d at age %.2f" % [bird.number, bird.age]))
		await process_frame
	Engine.time_scale = 1.0
	await process_frame
	var heard := _game.sfx_log.filter(func(id: StringName) -> bool: return String(id).begins_with("call_"))
	_check(watched.size() >= 4 and calls.is_empty() and heard.is_empty(), "the title's geese never call (%d watched)" % watched.size(), "calls %s, sounds %s" % [calls, heard])
	# A crossing goose watched from before it enters the tree, its band wholly above the grass.
	var crossing := Play.BIRD_SCENE.instantiate() as Bird
	crossing.setup_crossing(Content.bird("goose"), 99, 4242, Rect2(0, 120, 960, 200))
	crossing.appeared.connect(func(bird: Bird) -> void: calls.append("crossing goose at age %.2f" % bird.age))
	title.add_child(crossing)
	for i in 30:
		await process_frame
	_check(calls.is_empty() and crossing.art_top() < Play.GRASS_Y, "a crossing goose shown above the grass from its first frame never emits appeared", str(calls))
	crossing.queue_free()


## The pitches the sounds `id` in sfx_log played at, oldest first.
func _pitches_of(id: StringName) -> Array[float]:
	var pitches: Array[float] = []
	var offset := _game.sfx_pitches.size() - _game.sfx_log.size()
	for i in _game.sfx_log.size():
		if _game.sfx_log[i] == id:
			pitches.append(_game.sfx_pitches[offset + i])
	return pitches


## A real touch on the sky and a shot emitted straight into `play` (with shells, then with
## an empty pool) play no "shot" or "empty_click" and count no shot, `where` the game drops
## taps. The pool is restored after.
func _check_dropped_taps(play: Play, where: String) -> void:
	var shells := play.ammo.shells
	var shots := play.scoring.shots()
	var refused := play.refused
	var shot := (play.get_node("ShotInput") as ShotInput).shot
	var at := _global(play, SKY_POINTS[0])
	for pool: int in [shells, 0]:
		play.set_shell_pool(pool)
		_game.sfx_log.clear()
		await _touch(at)
		shot.emit(at)
		var heard := _game.sfx_log.filter(func(id: StringName) -> bool: return id == &"shot" or id == &"empty_click")
		_check(heard.is_empty() and play.scoring.shots() == shots and play.refused == refused, "a tap %s plays no shot sound (%s)" % [where, "empty pool" if pool == 0 else "%d shells" % pool],
			"%s, %d shots, %d refused" % [_game.sfx_log, play.scoring.shots() - shots, play.refused - refused])
	play.set_shell_pool(shells)


## The sounds `action` plays, at once (it is called with sfx_log cleared).
func _sounds_of(action: Callable) -> Array[StringName]:
	_game.sfx_log.clear()
	action.call()
	return _game.sfx_log.duplicate()



## The sound a heckle of `category` logs: its blurt, or none while blurts are off
## (GameState.HECKLE_BLURTS, the experiment muting the rival's voice).
func _heckle_sounds(category: String) -> Array[StringName]:
	var sounds: Array[StringName] = []
	if _game.heckle_blurts:
		sounds.append(StringName("heckle_" + category))
	return sounds

## "sound xpitch @at, ..." of a blurt, for comparing and failure messages.
func _plan_text(plan: Array[GameState.Syllable]) -> String:
	return ", ".join(plan.map(func(syllable: GameState.Syllable) -> String: return "%s x%.3f @%.3f" % [syllable.sound, syllable.pitch, syllable.at]))


## The settings screen from the title's Settings button: its sliders, toggles and Back fit
## (sizes, focus, safe area at every aspect, a notch and a short safe area), each setting
## shows its state in text, the music slider is focused on arrival; Tab, Up and Down move
## through it and Left/Right step a slider: the bus follows at once, it is logged, saved
## and plays the UI tap; a touch and a drag set a slider live and save once, on release; the
## toggles mute their bus or turn reduce motion on (saved, logged, shown); Back and Escape
## return to the title with Settings focused (plan ACs 10, 11).
func _test_settings_screen() -> void:
	_clear_tool_save()
	_game.load_game()
	_game.save_game()
	await _open_title()
	var title := current_scene as Title
	var from := _log.size()
	await _tap(title.get_node("Safe/SettingsButton") as Control)
	_check(title.settings_presses == 1 and _game.transition_log.back().begins_with("TITLE -> SETTINGS (res://scenes/settings.tscn)"), "a tap on Settings opens the settings through goto", str(_game.transition_log.back()))
	_check_logged(from, "^\\[Title\\] Settings pressed \\(1\\); opening the settings$", "the Settings press is logged")
	await _game.transition_finished
	await process_frame
	var settings := current_scene as Settings
	_check(settings != null and _game.state == GameState.Flow.SETTINGS and not settings.overlay, "the settings screen shows", str(current_scene))
	if settings == null:
		return
	_check_logged(from, "^\\[Settings\\] Opened from the title: music 70, sfx 80, reduce motion off$", "the settings' arrival is logged with every setting")
	var music := settings.get_node("Safe/MusicSlider") as TouchSlider
	var music_toggle := settings.get_node("Safe/MusicToggle") as Button
	var sfx := settings.get_node("Safe/SfxSlider") as TouchSlider
	var sfx_toggle := settings.get_node("Safe/SfxToggle") as Button
	var reduce := settings.get_node("Safe/ReduceMotionToggle") as Button
	var back := settings.get_node("Safe/BackButton") as Button
	var controls: Array[Control] = [music, music_toggle, sfx, sfx_toggle, reduce, back]
	var labels: Array[Label] = [settings.get_node("Safe/Heading") as Label, settings.get_node("Safe/MusicLabel") as Label, settings.get_node("Safe/SfxLabel") as Label, settings.get_node("Safe/ReduceMotionHint") as Label]
	_check(music.has_focus() and not music.has_focus(true), "the music slider is focused on arrival, the ring hidden", str(root.gui_get_focus_owner()))
	_check(_text_of(settings, "MusicLabel") == "Music 70" and _text_of(settings, "SfxLabel") == "SFX 80" and music_toggle.text == "Music: on" and sfx_toggle.text == "SFX: on" and reduce.text == "Reduce motion: off" and is_equal_approx(music.value, 70) and is_equal_approx(sfx.value, 80) and music.max_value == GameState.VOLUME_MAX and music.min_value == 0,
		"every setting shows its state in text, the sliders run 0..VOLUME_MAX", "%s | %s | %s | %s | %s" % [_text_of(settings, "MusicLabel"), _text_of(settings, "SfxLabel"), music_toggle.text, sfx_toggle.text, reduce.text])
	await _check_screen_layout(settings, controls, labels)
	var reached: Array[String] = []
	for i in controls.size():
		await _key(KEY_TAB)
		reached.append(str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else "none")
	_check(reached == ["MusicToggle", "SfxSlider", "SfxToggle", "ReduceMotionToggle", "BackButton", "MusicSlider"] and music.has_focus(true), "Tab cycles through every control, the ring shown", str(reached))
	var vertical: Array[String] = []
	for key: Key in [KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_DOWN, KEY_UP, KEY_UP]:
		await _key(key)
		vertical.append(str(root.gui_get_focus_owner().name) if root.gui_get_focus_owner() != null else "none")
	_check(vertical == ["SfxSlider", "ReduceMotionToggle", "BackButton", "MusicSlider", "BackButton", "ReduceMotionToggle"], "Down and Up move between the rows (wrapping)", str(vertical))
	await _check_slider(settings, music, "Music", GameState.MUSIC_BUS, "music", 70)
	await _check_slider(settings, sfx, "SFX", GameState.SFX_BUS, "sfx", 80)
	# A change outside any hold (HSlider's own mouse wheel on a desktop) saves and taps at once.
	var outside_from := _log.size()
	var outside_sounds := _game.sfx_log.size()
	music.value = 40
	var outside: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(_game.music_volume == 40 and (outside as Dictionary)["settings"]["music"] == 40.0 and _game.sfx_log.slice(outside_sounds) == [&"ui_tap"], "a change outside any hold (the mouse wheel) saves at once and taps", "volume %d, sounds %s" % [_game.music_volume, _game.sfx_log.slice(outside_sounds)])
	_check_logged(outside_from, "^\\[Settings\\] Music slider moved to 40$", "a change outside a hold is logged without (held)")
	var saved: Variant
	var sounds := 0
	var toggles: Array[Button] = [music_toggle, sfx_toggle]
	var buses: Array[StringName] = [GameState.MUSIC_BUS, GameState.SFX_BUS]
	for i in toggles.size():
		from = _log.size()
		await _tap(toggles[i])
		saved = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
		var key := "music_muted" if i == 0 else "sfx_muted"
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index(buses[i])) and toggles[i].text.ends_with(": off") and not toggles[i].button_pressed and (saved as Dictionary)["settings"][key] == true, "a tap on %s mutes its bus, shows off and saves" % toggles[i].name, toggles[i].text)
		_check_logged(from, "^\\[Settings\\] %s toggle pressed: %s off$" % [["Music", "SFX"][i], ["music", "sound effects"][i]], "%s is logged" % toggles[i].name)
		await _tap(toggles[i])
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(buses[i])) and toggles[i].text.ends_with(": on"), "a second tap on %s unmutes it" % toggles[i].name, toggles[i].text)
	from = _log.size()
	sounds = _game.sfx_log.size()
	await _tap(reduce)
	saved = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(_game.reduce_motion and reduce.button_pressed and reduce.text == "Reduce motion: on" and (saved as Dictionary)["settings"]["reduce_motion"] == true and _game.sfx_log.slice(sounds) == [&"ui_tap"], "Reduce motion turns on, shows it, is saved and taps", "%s, %s" % [reduce.text, _game.sfx_log.slice(sounds)])
	_check_logged(from, "^\\[Settings\\] Reduce motion toggle pressed: on$", "the reduce motion press is logged")
	_check_logged(from, "^\\[Game\\] Reduce motion on: no screen shake, plain fades, steady pop-ups and title$", "Game logs reduce motion")
	_game.set_reduce_motion(false)
	_check(reduce.text == "Reduce motion: off" and not reduce.button_pressed, "the screen follows a change made elsewhere", reduce.text)
	back.grab_focus()
	await _key(KEY_ENTER)
	await _game.transition_finished
	await process_frame
	title = current_scene as Title
	_check(title != null and (title.get_node("Safe/SettingsButton") as Button).has_focus(), "Back returns to the title with Settings focused", str(root.gui_get_focus_owner()))
	await _tap(title.get_node("Safe/SettingsButton") as Control)
	await _game.transition_finished
	await process_frame
	from = _log.size()
	await _key(KEY_ESCAPE)
	# Bounded: a dead Escape must fail here, not hang until the watchdog.
	for i in 120:
		if current_scene is Title and not _game.is_transitioning():
			break
		await process_frame
	_check(current_scene is Title and (current_scene.get_node("Safe/SettingsButton") as Button).has_focus(), "Escape on the settings screen returns to the title too", str(current_scene))
	_check_logged(from, "^\\[Settings\\] Back pressed; returning to the title$", "Back is logged")
	_game.set_music_volume(GameState.DEFAULT_MUSIC_VOLUME)
	_game.set_sfx_volume(GameState.DEFAULT_SFX_VOLUME)
	_clear_tool_save()


## The pause menu's Settings opens the settings over the paused run: the tree stays paused,
## the run's clock still, the sounds held and the music ducked; a slider applies at once
## (the duck kept); a mute set there shows on the pause menu's toggle; touches on it are no
## shots; Escape and Back close it (not the run's pause) and focus Settings again; the
## menu's toggles stay in sync both ways (plan AC 11).
func _test_settings_over_paused_run() -> void:
	_clear_tool_save()
	_game.load_game()
	var play := await _start_run(55)
	await _spawn_flying(play, 7)
	_game.play_sfx(&"wave_start")
	play.open_pause("test")
	await process_frame
	var panel := play.get_node("PauseLayer/PauseMenu/Panel")
	var settings_button := panel.get_node("SettingsButton") as Button
	var from := _log.size()
	await _tap(settings_button)
	var settings := play.settings_overlay()
	_check(settings != null and settings.overlay and settings.is_inside_tree() and paused and play.is_paused() and _game.audio_paused, "Settings opens the settings over the paused run", "overlay %s, paused %s" % [settings, paused])
	_check(not (panel as Control).visible and (play.get_node("PauseLayer/PauseMenu") as Control).visible, "the pause menu's panel hides under the settings, its dim stays", "panel %s" % (panel as Control).visible)
	if settings == null:
		play.resume()
		return
	_check_logged(from, "^\\[Play\\] Settings opened over the paused run \\(wave 1 at t ", "opening it is logged")
	_check_logged(from, "^\\[Settings\\] Opened over the paused run: ", "the settings log their arrival over the run")
	var clock := play.run_clock
	var held := _game.held_players().size()
	for i in 30:
		await process_frame
	_check(play.run_clock == clock and paused and _game.held_players().size() == held and held >= 1, "the run stays frozen with its sounds held under the settings", "clock %.3f -> %.3f, held %d" % [clock, play.run_clock, _game.held_players().size()])
	var music := settings.get_node("Safe/MusicSlider") as TouchSlider
	_check(music.has_focus(), "the overlay focuses its music slider", str(root.gui_get_focus_owner()))
	await _key(KEY_LEFT)
	var bus := AudioServer.get_bus_index(GameState.MUSIC_BUS)
	_check(_game.music_volume == 70 - int(TouchSlider.KEY_STEP) and is_equal_approx(AudioServer.get_bus_volume_db(bus), GameState.bus_volume_db(70 - int(TouchSlider.KEY_STEP), GameState.PAUSE_DUCK_DB)), "a slider step applies at once and the music stays ducked", "%.2f dB" % AudioServer.get_bus_volume_db(bus))
	var shots := play.scoring.shots()
	await _tap(settings.get_node("Safe/ReduceMotionHint") as Control)
	_check(play.scoring.shots() == shots and play.refused == 0, "a touch on the overlay is no shot", "%d shots" % play.scoring.shots())
	await _tap(settings.get_node("Safe/MusicToggle") as Control)
	var menu_toggle := panel.get_node("MusicToggle") as Button
	_check(_game.music_muted and menu_toggle.text == "Music: off" and not menu_toggle.button_pressed, "a mute set in the settings shows on the pause menu's toggle", menu_toggle.text)
	from = _log.size()
	await _key(KEY_ESCAPE)
	_check(play.settings_overlay() == null and play.is_paused() and paused and settings_button.has_focus(), "Escape closes the settings, the run stays paused, Settings is focused", "overlay %s, paused %s, focus %s" % [play.settings_overlay(), paused, root.gui_get_focus_owner()])
	_check((panel as Control).visible, "the pause menu's panel shows again", "hidden")
	_check_logged(from, "^\\[Play\\] Settings closed; back to the pause menu$", "closing is logged")
	await _tap(menu_toggle)
	_check(not _game.music_muted and menu_toggle.text == "Music: on", "the pause menu's toggle still works", menu_toggle.text)
	await _tap(settings_button)
	settings = play.settings_overlay()
	_check(settings != null and (settings.get_node("Safe/MusicToggle") as Button).text == "Music: on", "the settings show the mute the pause menu set", str(settings))
	if settings != null:
		await _tap(settings.get_node("Safe/BackButton") as Control)
		await process_frame
	_check(play.settings_overlay() == null and play.is_paused() and settings_button.has_focus(), "Back closes the settings and focuses Settings", str(root.gui_get_focus_owner()))
	await _tap(settings_button)
	play.resume()
	await process_frame
	_check(play.settings_overlay() == null and not paused and not _game.audio_paused, "resuming closes settings left open and runs again", "overlay %s, paused %s" % [play.settings_overlay(), paused])
	_game.set_music_volume(GameState.DEFAULT_MUSIC_VOLUME)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_clear_tool_save()


## The credits screen from the title's Credits button: who made it, the engine and its
## licence, both fonts with the OFL 1.1 and the copyright lines of their shipped OFL files,
## that the art and audio are original and generated as code but for the rival's laugh,
## credited to WeaponGuy under CC0, nothing naming Nintendo or
## Duck Hunt; it fits at every aspect, a notch and a short safe area; Back (focused) and
## Escape return to the title with Credits focused (plan AC 12).
func _test_credits_screen() -> void:
	await _open_title()
	var title := current_scene as Title
	var from := _log.size()
	await _tap(title.get_node("Safe/CreditsButton") as Control)
	_check(title.credits_presses == 1 and _game.transition_log.back().begins_with("TITLE -> CREDITS (res://scenes/credits.tscn)"), "a tap on Credits opens the credits through goto", str(_game.transition_log.back()))
	_check_logged(from, "^\\[Title\\] Credits pressed \\(1\\); opening the credits$", "the Credits press is logged")
	await _game.transition_finished
	await process_frame
	var credits := current_scene as Credits
	_check(credits != null and _game.state == GameState.Flow.CREDITS, "the credits screen shows", str(current_scene))
	if credits == null:
		return
	var text := "%s\n%s" % [_text_of(credits, "MadeBy"), _text_of(credits, "Lines")]
	for needed: String in ["Made by linostar", "Godot Engine (MIT license)", "Lilita One", "Nunito", "SIL Open Font License 1.1", "original", "generated as code", "evil laugh", "WeaponGuy", "OpenGameArt", "CC0",
		"Bird calls", "Bert76", "Oona Räisänen", "U.S. Fish and Wildlife Service", "public domain", "Wikimedia Commons"]:
		_check(needed in text, "the credits say " + needed, text)
	for font: String in ["res://ui/fonts/LilitaOne-OFL.txt", "res://ui/fonts/Nunito-OFL.txt"]:
		var notice := FileAccess.get_file_as_string(font).get_slice("\n\n", 0).replace("\n", " ")
		while "  " in notice:
			notice = notice.replace("  ", " ")
		notice = notice.strip_edges()
		_check(notice.begins_with("Copyright") and notice in text, "the credits carry the copyright line of " + font, notice)
	var scene_text := FileAccess.get_file_as_string("res://scenes/credits.tscn") + FileAccess.get_file_as_string("res://scripts/credits.gd")
	for banned: String in ["nintendo", "duck hunt"]:
		_check(not banned in text.to_lower() and not banned in scene_text.to_lower(), "nothing in the credits names " + banned, text)
	var back := credits.get_node("Safe/BackButton") as Button
	_check(back.has_focus() and not back.has_focus(true), "Back is focused on arrival, the ring hidden", str(root.gui_get_focus_owner()))
	var controls: Array[Control] = [back]
	var labels: Array[Label] = [credits.get_node("Safe/Heading") as Label, credits.get_node("Safe/MadeBy") as Label, credits.get_node("Safe/Lines") as Label]
	await _check_screen_layout(credits, controls, labels)
	from = _log.size()
	await _key(KEY_ENTER)
	await _game.transition_finished
	await process_frame
	_check(current_scene is Title and (current_scene.get_node("Safe/CreditsButton") as Button).has_focus(), "Back returns to the title with Credits focused", str(root.gui_get_focus_owner()))
	_check_logged(from, "^\\[Credits\\] Back pressed; returning to the title$", "Back is logged")
	await _key(KEY_ENTER)
	await _game.transition_finished
	await process_frame
	await _key(KEY_ESCAPE)
	await _game.transition_finished
	await process_frame
	_check(current_scene is Title and (current_scene.get_node("Safe/CreditsButton") as Button).has_focus(), "Escape on the credits returns to the title too", str(current_scene))


## The text of the Label `label_name` under a screen's Safe.
func _text_of(screen: Control, label_name: String) -> String:
	return (screen.get_node("Safe/" + label_name) as Label).text


## The title's scenery: the sunset backdrop with its chapter's weather, the rival idling in
## the grass inside the safe area, and geese crossing on the seeded schedule: over 30 s of
## title time at least one goose is in view in nearly every frame, none ever covers a title
## button (their band ends above the first row at every aspect and under a notch), the
## schedule and paths are the same each time the title opens, and the scenery drifts (plan
## AC 1).
func _test_title_scenery_and_geese() -> void:
	await _open_title()
	var title := current_scene as Title
	var sunset := Content.chapters().filter(func(chapter: ChapterSpec) -> bool: return chapter.backdrop == Title.TITLE_BACKDROP)
	var backdrop := title.get_node("Scenery/Backdrop") as Backdrop
	var weather := title.get_node("Scenery/Weather") as Weather
	_check(backdrop.id == "sunset" and sunset.size() == 1 and weather.id == (sunset[0] as ChapterSpec).weather and weather.id != "", "the title shows the sunset backdrop with its chapter's weather", "%s, %s" % [backdrop.id, weather.id])
	var rival := title.get_node("Scenery/Rival") as TextureRect
	_check(rival.visible and title.rival_pose() == "idle" and _game.safe_rect().encloses(rival.get_global_rect()) and rival.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the rival idles in the grass inside the safe area and ignores touches", str(rival.get_global_rect()))
	var buttons: Array[Control] = []
	for button_name: String in ["CampaignButton", "EndlessButton", "TimeAttackButton", "SettingsButton", "CreditsButton"]:
		buttons.append(title.get_node("Safe/" + button_name) as Control)
	var safes: Array[Rect2] = [Rect2(), Rect2(), Rect2(), NOTCHED_SAFE_RECT]
	var windows: Array[Vector2i] = [LANDSCAPE_16_9, LANDSCAPE_19_5_9, LANDSCAPE_4_3, LANDSCAPE_19_5_9]
	var scenery := title.get_node("Scenery") as Node2D
	for i in windows.size():
		_game.safe_area_override = safes[i]
		root.size = windows[i]
		await process_frame
		await process_frame
		var band := scenery.get_global_transform() * title.goose_band()
		var lowest_reach := band.end.y
		var clear := buttons.all(func(button: Control) -> bool: return button.get_global_rect().position.y >= lowest_reach + Title.BAND_MARGIN - 0.5)
		_check(clear and band.size.y >= Content.bird(Title.TITLE_BIRD).size.y and band.position.y >= _game.safe_rect().position.y + Play.HUD_BAR_HEIGHT - 0.5, "%dx%d: the geese's band lies below the top bar and above every button" % [windows[i].x, windows[i].y], "band %s" % band)
	_game.safe_area_override = Rect2()
	root.size = BASE_WINDOW
	await process_frame
	await _open_title()
	title = current_scene as Title
	scenery = title.get_node("Scenery") as Node2D
	buttons.clear()
	for button_name: String in ["CampaignButton", "EndlessButton", "TimeAttackButton", "SettingsButton", "CreditsButton"]:
		buttons.append(title.get_node("Safe/" + button_name) as Control)
	var frames := 0
	var seen := 0
	var covering: Array[String] = []
	var outside_band: Array[String] = []
	var drift_seen := 0.0
	var first_path: Array[Vector2] = []
	Engine.time_scale = 4.0
	for frame in 450:
		await process_frame
		frames += 1
		drift_seen = maxf(drift_seen, absf(scenery.position.x))
		var visible := _game.visible_rect()
		var any := false
		for goose in title.flying_geese():
			var box := scenery.get_global_transform() * Rect2(goose.position - goose.spec.size / 2.0, goose.spec.size)
			if box.intersects(visible):
				any = true
			for button in buttons:
				if box.intersects(button.get_global_rect()):
					covering.append("goose #%d %s over %s" % [goose.number, box, button.name])
			var band := title.goose_band()
			if goose.position.y - goose.spec.size.y / 2.0 < band.position.y - 0.01 or goose.position.y + goose.spec.size.y / 2.0 > band.end.y + 0.01:
				outside_band.append("goose #%d at %s" % [goose.number, goose.position])
			if goose.number == 1 and first_path.size() < 60:
				first_path.append(goose.position)
		if any:
			seen += 1
	Engine.time_scale = 1.0
	_check(float(seen) / frames >= 0.9, "a goose is in view in at least 90% of the title's frames", "%d of %d frames" % [seen, frames])
	_check(covering.is_empty(), "no goose ever covers a title button", "; ".join(covering.slice(0, 5)))
	_check(outside_band.is_empty(), "every goose stays inside its band", "; ".join(outside_band.slice(0, 5)))
	_check(drift_seen > Title.DRIFT_AMPLITUDE * 0.3 and drift_seen <= Title.DRIFT_AMPLITUDE + 0.01, "the scenery drifts from side to side within its amplitude", "drift %.2f" % drift_seen)
	await _open_title()
	title = current_scene as Title
	var again: Array[Vector2] = []
	Engine.time_scale = 4.0
	for frame in 450:
		await process_frame
		for goose in title.flying_geese():
			if goose.number == 1 and again.size() < 60:
				again.append(goose.position)
	Engine.time_scale = 1.0
	_check(first_path.size() == 60 and again == first_path, "the title's geese fly the same seeded paths each time it opens", "%d and %d points" % [first_path.size(), again.size()])


## A tap on a title goose (its polygon, as in play) shoots it: shot and hit sounds, a
## feather burst, the goose falls, the rival sulks and heckles with a blurt; nothing is
## scored or saved; it is logged. A tap on empty sky plays the shot only; a tap on a button
## only presses it; a second goose inside the heckle cooldown gets the pose but no line
## (plan AC 2).
func _test_title_goose_shot() -> void:
	_clear_tool_save()
	_game.save_game()
	var save_before := FileAccess.get_file_as_string(_game.save_path)
	var bests_before := _game.bests.duplicate()
	await _open_title()
	var title := current_scene as Title
	var scenery := title.get_node("Scenery") as Node2D
	var goose := await _title_goose_in_view(title)
	_check(goose != null, "a goose crosses the title", "none in view")
	if goose == null:
		return
	goose.set_process(false)
	var from := _log.size()
	var shots_from := from
	# Inside the goose's box but outside its polygon: a miss, as in play.
	await _touch(scenery.to_global(goose.transform * LOCAL_BOX_CORNER))
	_check(goose.is_flying() and title.geese_shot == 0, "a tap inside a title goose's box but outside its polygon misses", "shot %d" % title.geese_shot)
	var sounds := _game.sfx_log.size()
	var feathers_before := title.feathers().live_count()
	await _touch(scenery.to_global(goose.transform * LOCAL_BODY))
	goose.set_process(true)
	_check(goose.state != Bird.State.FLYING and title.geese_shot == 1, "a tap on a title goose shoots it", "state %d" % goose.state)
	_check(_game.sfx_log.slice(sounds) == [&"shot", &"hit"] + _heckle_sounds("combo"), "the shot, the hit and the rival's blurt play (silent while HECKLE_BLURTS is off)", str(_game.sfx_log.slice(sounds)))
	_check(title.feathers().live_count() == feathers_before + Feathers.FEATHERS_PER_BURST and Array(title.feathers().live_colors()).all(func(color: Color) -> bool: return color in Feathers.COLORS[goose.spec.sprite]), "the goose bursts into feathers of its colours", "%d feathers" % title.feathers().live_count())
	_check(title.rival_pose() == "sulk" and title.heckle_shown() in Content.rival_lines().lines[Title.HECKLE_CATEGORY], "the rival sulks and heckles", "%s, '%s'" % [title.rival_pose(), title.heckle_shown()])
	_check_logged(from, "^\\[Title\\] Shot goose #%d at \\([\\d.]+, [\\d.]+\\): it falls; no score, nothing saved \\(1 shot on the title\\)$" % goose.number, "the title shot is logged")
	_check_logged(from, "^\\[Title\\] Heckle \\(combo\\) #1: ", "the title heckle is logged")
	var bubble := (title.get_node("Scenery/Bubble") as Label).get_global_rect()
	var clear_of_buttons := ["CampaignButton", "EndlessButton", "TimeAttackButton", "SettingsButton", "CreditsButton"].all(func(button_name: String) -> bool: return not bubble.intersects((title.get_node("Safe/" + button_name) as Control).get_global_rect()))
	_check(_game.safe_rect().grow(0.5).encloses(bubble) and clear_of_buttons and (title.get_node("Scenery/Bubble") as Label).mouse_filter == Control.MOUSE_FILTER_IGNORE, "the title's heckle bubble is inside the safe area, clear of the buttons, ignoring touches", str(bubble))
	var fell := [false]
	goose.gone.connect(func(_b: Bird) -> void: fell[0] = true)
	for i in 240:
		if not is_instance_valid(goose):
			break
		await process_frame
	_check(fell[0], "the shot goose falls off the screen", "still there")
	# Empty sky: a point of the band no goose covers.
	var band := title.goose_band()
	var empty := Vector2.INF
	for x in range(int(band.position.x) + 40, int(band.end.x) - 40, 30):
		var point := Vector2(x, band.get_center().y)
		if title.goose_at(point) == null and title.flying_geese().all(func(other: Bird) -> bool: return other.position.distance_to(point) > 90.0):
			empty = point
			break
	from = _log.size()
	sounds = _game.sfx_log.size()
	var feathers_now := title.feathers().live_count()
	await _touch(scenery.to_global(empty))
	_check(_game.sfx_log.slice(sounds) == [&"shot"] and title.geese_shot == 1 and title.feathers().live_count() <= feathers_now, "a tap on empty sky plays the shot only", str(_game.sfx_log.slice(sounds)))
	_check_logged(from, "^\\[Title\\] Shot at \\([\\d.]+, [\\d.]+\\): missed$", "the empty shot is logged")
	var second := await _title_goose_in_view(title)
	if second != null:
		second.set_process(false)
		from = _log.size()
		await _touch(scenery.to_global(second.transform * LOCAL_BODY))
		second.set_process(true)
		_check(title.geese_shot == 2 and title.rival_pose() == "sulk", "a second goose is shot and the rival sulks again", "%d shot" % title.geese_shot)
		_check_logged(from, "^\\[Title\\] Heckle \\(combo\\) skipped: cooldown, ", "inside the cooldown the rival keeps quiet (logged)")
	_check(FileAccess.get_file_as_string(_game.save_path) == save_before and _game.bests == bests_before, "nothing is saved and no best changes", "save changed")
	_check(not Array(_log.since(shots_from)).any(func(line: String) -> bool: return line.begins_with("[Game] Saved to")), "title shots write no save", "a save line")
	from = _log.size()
	sounds = _game.sfx_log.size()
	await _tap(title.get_node("Safe/CreditsButton") as Control)
	_check(title.credits_presses == 1 and not &"shot" in _game.sfx_log.slice(sounds) and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Title] Shot")), "a tap on a button only presses it", str(_game.sfx_log.slice(sounds)))
	await _game.transition_finished
	_clear_tool_save()


## Waits (at most 6 s) for a title goose wholly inside the visible area and inside the
## shot surface; null if none came.
func _title_goose_in_view(title: Title) -> Bird:
	var scenery := title.get_node("Scenery") as Node2D
	for i in 360:
		for goose in title.flying_geese():
			var box := scenery.get_global_transform() * Rect2(goose.position - goose.spec.size / 2.0, goose.spec.size)
			if _game.visible_rect().grow(-20.0).encloses(box):
				return goose
		await process_frame
	return null


## Screen changes use the marsh-grass wipe: it rises over the screen in WIPE_TIME (at most
## 0.4 s), the scene changes under full cover, it sinks away in WIPE_TIME; the cover's own
## colour stays invisible and it blocks touches throughout; goto still logs both ends.
## With reduce motion a plain fade takes FADE_TIME each way and the wipe never shows
## (plan ACs 3, 8).
func _test_transition_wipe_and_fade() -> void:
	await _open_title()
	var cover := _game.get_node("Fade/Cover") as ColorRect
	var wipe := _game.get_node("Fade/Cover/Wipe") as Wipe
	_check(GameState.WIPE_TIME <= 0.4 and GameState.WIPE_TIME > 0.0, "the wipe takes at most 0.4 s each way", str(GameState.WIPE_TIME))
	for reduce: bool in [false, true]:
		_game.reduce_motion = reduce
		await _open_title()
		var title := current_scene as Title
		var from := _log.size()
		var changed := [false]
		var on_change := func() -> void: changed[0] = true
		scene_changed.connect(on_change, CONNECT_ONE_SHOT)
		_game.goto(GameState.Flow.TITLE)
		var in_frames := 0
		var out_frames := 0
		var coverage: Array[float] = []
		var styles: Array[String] = []
		var blocked := true
		var wipe_shown := false
		var mid_edge := -1.0
		var first_edge := -1.0
		while _game.is_transitioning():
			await process_frame
			if changed[0]:
				out_frames += 1
			else:
				in_frames += 1
			coverage.append(_game.cover_progress())
			styles.append(_game.transition_style())
			blocked = blocked and (not cover.visible or cover.mouse_filter == Control.MOUSE_FILTER_STOP)
			wipe_shown = wipe_shown or wipe.visible
			if not reduce and not changed[0] and wipe.coverage() > 0.3 and wipe.coverage() < 0.7 and mid_edge < 0.0:
				mid_edge = wipe.edge_y()
			if not reduce and in_frames == 1:
				first_edge = wipe.edge_y()
		var time := GameState.FADE_TIME if reduce else GameState.WIPE_TIME
		var label := "reduce motion: plain fade" if reduce else "the wipe"
		var expected_frames := roundi(time / FRAME)
		_check(in_frames >= expected_frames and in_frames <= expected_frames + 3 and out_frames >= expected_frames and out_frames <= expected_frames + 3, "%s covers in %.2f s and clears in %.2f s" % [label, time, time], "%d frames in, %d out (expected %d)" % [in_frames, out_frames, expected_frames])
		_check(coverage.max() >= 0.999 and is_zero_approx(coverage.back()) and is_zero_approx(_game.cover_progress()), "%s covers the screen fully, then clears" % label, str(coverage))
		_check(styles.all(func(style: String) -> bool: return style == ("fade" if reduce else "wipe")), "%s is the transition style throughout" % label, str(styles.slice(0, 3)))
		_check(blocked and not cover.visible and cover.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s blocks touches while it runs and lets them through after" % label, "blocked %s" % blocked)
		_check(wipe_shown != reduce, "the grass wipe shows only without reduce motion", "wipe shown %s" % wipe_shown)
		if reduce:
			_check_logged(from, "^\\[Game\\] Transition: plain fade, 0\\.15 s in and 0\\.15 s out \\(reduce motion\\)$", "the fade is logged")
		else:
			_check_logged(from, "^\\[Game\\] Transition: marsh-grass wipe, 0\\.35 s in and 0\\.35 s out$", "the wipe is logged")
			_check(mid_edge > 0.0 and mid_edge < _game.visible_rect().size.y and first_edge > _game.visible_rect().size.y * 0.5, "half way in, the grass's edge is inside the screen (it rises from the bottom)", "first edge %.1f, mid edge %.1f" % [first_edge, mid_edge])
			_check(is_zero_approx(cover.self_modulate.a), "under the wipe the cover's own colour stays invisible", str(cover.self_modulate))
		_check_logged(from, "^\\[Game\\] goto TITLE -> TITLE ", "goto still logs its start")
		_check_logged(from, "^\\[Game\\] Arrived at TITLE$", "goto still logs its arrival")
		# A tap on a button during the transition presses nothing.
		title = current_scene as Title
		_game.goto(GameState.Flow.TITLE)
		await process_frame
		await process_frame
		await _tap(title.get_node("Safe/CampaignButton") as Control)
		_check(title.campaign_presses == 0, "%s: a tap during the transition presses nothing" % label, "%d presses" % title.campaign_presses)
		await _game.transition_finished
	_game.reduce_motion = false


## Hit stop: a kill freezes the world for HIT_STOP_TIME (HIT_STOP_HEAVY_TIME for an armored
## or golden kill): the other birds, run_clock and wave_clock stand still, then each has
## lost exactly the stop's time (a bird's age keeps its offset from run_clock); a second
## kill during it (a salvo) scores and updates the HUD at once but starts no second stop;
## a timed run's clock loses exactly the stop too (plan AC 4).
func _test_hit_stop() -> void:
	var play := await _start_run(61)
	for i in 120:
		if play.wave_clock > 0.5:
			break
		await process_frame
	var victim := await _spawn_flying(play, 11)
	var watcher := await _spawn_flying(play, 12)
	var second := await _spawn_flying(play, 13)
	await process_frame
	var clock := play.run_clock
	var wave_clock := play.wave_clock
	var offset := watcher.age - play.run_clock
	var where := watcher.position
	var from := _log.size()
	var shot_input := play.get_node("ShotInput") as ShotInput
	shot_input.shot.emit(_global(play, victim.transform * LOCAL_BODY))
	_check(is_equal_approx(play.hit_stop_left(), Play.HIT_STOP_TIME) and Play.HIT_STOP_TIME <= 0.06 and play.hit_stops == 1 and watcher.is_held(), "a goose kill starts a %.2f s hit stop (at most 0.06) that holds the other birds" % Play.HIT_STOP_TIME, "left %.3f, stops %d" % [play.hit_stop_left(), play.hit_stops])
	_check_logged(from, "^\\[Play\\] Hit stop 0\\.05 s on the kill of goose #%d " % victim.number, "the hit stop is logged")
	await process_frame
	shot_input.shot.emit(_global(play, second.transform * LOCAL_BODY))
	_check(not second.is_flying() and _text(play, "Score") == "Score %d" % play.scoring.score and play.scoring.kills == 2, "a kill during the stop scores and the HUD shows it at once", _text(play, "Score"))
	_check(play.hit_stops == 1, "a second kill during the stop starts no second stop", "%d stops" % play.hit_stops)
	_check_logged(from, "^\\[Play\\] Hit stop for goose #%d skipped: one is running " % second.number, "the skipped stop is logged")
	var frames := 1
	var frozen := true
	while play.hit_stop_left() > 0.0 and frames < 20:
		frozen = frozen and play.run_clock == clock and play.wave_clock == wave_clock and watcher.position == where
		await process_frame
		frames += 1
	_check(frozen, "during the stop the clocks and the other birds stand still", "clock %.4f -> %.4f" % [clock, play.run_clock])
	for i in 3:
		await process_frame
		frames += 1
	var lost := frames * FRAME - (play.run_clock - clock)
	_check(absf(lost - Play.HIT_STOP_TIME) < 1e-6 and absf((frames * FRAME - (play.wave_clock - wave_clock)) - Play.HIT_STOP_TIME) < 1e-6, "run_clock and wave_clock lose exactly the stop's time", "lost %.6f s over %d frames" % [lost, frames])
	_check(absf((watcher.age - play.run_clock) - offset) < 1e-6 and watcher.position != where, "a bird loses exactly the same time (its age keeps its offset from run_clock) and flies on", "offset %.6f -> %.6f" % [offset, watcher.age - play.run_clock])
	# A splitter's goslings, launched by the kill that starts a stop, wait it out too.
	while play.hit_stop_left() > 0.0:
		await process_frame
	var splitter := await _spawn_flying(play, 18, IN_FIELD_AGE, "splitter")
	shot_input.shot.emit(_global(play, splitter.transform * LOCAL_BODY))
	var goslings := play.flying_birds().filter(func(bird: Bird) -> bool: return bird.spec.id == "gosling")
	_check(goslings.size() == 2 and goslings.all(func(bird: Bird) -> bool: return bird.is_held()), "the goslings launched by the kill wait out the stop", str(goslings.map(func(bird: Bird) -> bool: return bird.is_held())))
	while play.hit_stop_left() > 0.0:
		await process_frame
	# An armored kill and a golden kill stop longer. 0.09 s is not a whole number of frames,
	# so this also proves the frame that ends a stop runs only its remainder: run_clock and a
	# watching bird lose exactly the stop's time.
	for bird_id: String in ["armored", "golden"]:
		var heavy := await _spawn_flying(play, 21, IN_FIELD_AGE, bird_id)
		heavy.set_process(false)
		var heavy_watcher := await _spawn_flying(play, 25)
		for shot in heavy.spec.hp - 1:
			shot_input.shot.emit(_global(play, heavy.transform * LOCAL_BODY))
		await process_frame
		var heavy_clock := play.run_clock
		var heavy_offset := heavy_watcher.age - play.run_clock
		shot_input.shot.emit(_global(play, heavy.transform * LOCAL_BODY))
		_check(not heavy.is_flying() and is_equal_approx(play.hit_stop_left(), Play.HIT_STOP_HEAVY_TIME) and Play.HIT_STOP_HEAVY_TIME <= 0.1, "a %s kill stops the world longer, %.2f s (at most 0.1)" % [bird_id, Play.HIT_STOP_HEAVY_TIME], "left %.3f" % play.hit_stop_left())
		var heavy_frames := 0
		for i in 12:
			await process_frame
			heavy_frames += 1
		var heavy_lost := heavy_frames * FRAME - (play.run_clock - heavy_clock)
		_check(absf(heavy_lost - Play.HIT_STOP_HEAVY_TIME) < 1e-6, "after a %s kill run_clock loses exactly %.2f s (not whole frames)" % [bird_id, Play.HIT_STOP_HEAVY_TIME], "lost %.6f s over %d frames" % [heavy_lost, heavy_frames])
		_check(is_instance_valid(heavy_watcher) and absf((heavy_watcher.age - play.run_clock) - heavy_offset) < 1e-6, "after a %s kill a watching bird loses exactly the same time" % bird_id, "offset %.6f -> %.6f" % [heavy_offset, heavy_watcher.age - play.run_clock] if is_instance_valid(heavy_watcher) else "gone")
		if is_instance_valid(heavy_watcher):
			heavy_watcher.queue_free()
	# A timed run's clock loses exactly the stop as well.
	play = await _start_run(62, GameState.TIME_ATTACK_MODE)
	for i in 120:
		if play.wave_clock > 0.5:
			break
		await process_frame
	var goose := await _spawn_flying(play, 14)
	var left := play.time_left()
	frames = 0
	(play.get_node("ShotInput") as ShotInput).shot.emit(_global(play, goose.transform * LOCAL_BODY))
	for i in 10:
		await process_frame
		frames += 1
	_check(absf((left - play.time_left()) - (frames * FRAME - Play.HIT_STOP_TIME)) < 1e-6, "the Time Attack clock loses exactly the stop's time", "%.4f -> %.4f over %d frames" % [left, play.time_left(), frames])
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Feathers: a kill bursts FEATHERS_PER_BURST feathers in the bird's own colours at the hit
## point (a goose, the decoy); every bird sprite has colours, each a palette entry; bursts
## past FEATHERS_MAX retire the oldest; they fade out; a sprite without colours is reported
## and bursts nothing (plan AC 5).
func _test_feathers() -> void:
	var palette := FileAccess.get_file_as_string("res://art/palette.hex").split("\n", false)
	var missing: Array[String] = []
	for spec in Content.birds():
		var colors: Array = Feathers.COLORS.get(spec.sprite, [])
		if colors.size() < 2:
			missing.append("%s has %d colours" % [spec.sprite, colors.size()])
		for color: Color in colors:
			if not color.to_html(false) in palette:
				missing.append("%s %s is not in the palette" % [spec.sprite, color.to_html(false)])
	_check(missing.is_empty(), "every bird sprite has feather colours, all from art/palette.hex", "; ".join(missing))
	_check(Feathers.FEATHERS_MAX >= Feathers.FEATHERS_PER_BURST * 3 and Feathers.FEATHERS_MAX <= 64, "the live feather cap holds a few bursts and stays small", str(Feathers.FEATHERS_MAX))
	var play := await _start_run(63)
	var feathers := play.get_node("World/Feathers") as Feathers
	var goose := await _spawn_flying(play, 15)
	var point := goose.transform * LOCAL_BODY
	await _touch(_global(play, point))
	_check(feathers.live_count() == Feathers.FEATHERS_PER_BURST and Array(feathers.live_colors()).all(func(color: Color) -> bool: return color in Feathers.COLORS["goose"]), "a goose kill bursts its feathers in the goose's colours", "%d: %s" % [feathers.live_count(), feathers.live_colors()])
	var colours_used := {}
	for color in feathers.live_colors():
		colours_used[color.to_html(false)] = true
	_check(colours_used.size() == Feathers.COLORS["goose"].size(), "the burst uses every colour of the bird", str(colours_used.keys()))
	_check(feathers.last_burst_at.distance_to(point) < 1.0, "the kill's burst starts at the hit point", "burst at %s, hit at %s" % [feathers.last_burst_at, point])
	var decoy := await _spawn_flying(play, 16, IN_FIELD_AGE, "decoy")
	var decoy_point := decoy.transform * LOCAL_BODY
	await _touch(_global(play, decoy_point))
	_check(feathers.last_burst_at.distance_to(decoy_point) < 1.0, "the decoy's burst starts at the hit point", "burst at %s, hit at %s" % [feathers.last_burst_at, decoy_point])
	var newest := Array(feathers.live_colors()).slice(Feathers.FEATHERS_PER_BURST)
	_check(feathers.live_count() == 2 * Feathers.FEATHERS_PER_BURST and newest.all(func(color: Color) -> bool: return color in Feathers.COLORS["decoy"]), "a decoy hit bursts the pigeon's colours", str(newest))
	# A steal bursts the stolen bird's feathers where it was shot.
	var bursts := feathers.bursts
	var cued := await _cued_bird(play, 17, "goose")
	for i in roundi(Content.rival_lines().aim_time / FRAME) + 5:
		if cued.stolen:
			break
		await process_frame
	_check(cued.stolen and feathers.bursts == bursts + 1 and feathers.last_burst_at.distance_to(cued.position) < 1.0 and Array(feathers.live_colors()).slice(-Feathers.FEATHERS_PER_BURST).all(func(color: Color) -> bool: return color in Feathers.COLORS["goose"]),
		"a steal bursts the goose's feathers where the rival shot it", "stolen %s, %d bursts, at %s, bird at %s" % [cued.stolen, feathers.bursts - bursts, feathers.last_burst_at, cued.position])
	# The cap: more bursts than it holds keep the newest.
	var loose := Feathers.new()
	root.add_child(loose)
	var thrown := 0
	for i in 6:
		thrown += loose.burst(Vector2(100 + i, 100), "golden")
	_check(thrown == 6 * Feathers.FEATHERS_PER_BURST and loose.live_count() == Feathers.FEATHERS_MAX, "bursts past the cap keep at most FEATHERS_MAX feathers alive", "%d thrown, %d alive" % [thrown, loose.live_count()])
	for i in roundi(Feathers.FEATHER_LIFE_MAX / FRAME) + 2:
		await process_frame
	_check(loose.live_count() == 0, "feathers fade out within their lifetime", "%d left" % loose.live_count())
	_game.quiet_errors = true
	var errors := _game.reported_errors.size()
	var none := loose.burst(Vector2(100, 100), "dragon")
	loose.burst(Vector2(100, 100), "dragon")
	_game.quiet_errors = false
	_check(none == 0 and loose.live_count() == 0 and _game.reported_errors.size() == errors + 1 and _game.reported_errors.back().contains("'dragon'"), "a sprite without feather colours is reported once and bursts nothing", str(_game.reported_errors.slice(errors)))
	(_game.get_node("Fade/ErrorLabel") as Label).hide()
	loose.free()
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Screen shake: an armored kill, a golden kill, a decoy hit, a steal and a lost wave each
## shake the world (logged with their cause) by at most their amplitude, ending exactly
## where it was (offset zero) after their time; the HUD never moves; a weaker shake does
## not cut a stronger one short (plan AC 6).
func _test_screen_shake() -> void:
	var play := await _start_run(64)
	var world := play.get_node("World") as Node2D
	var bar := play.get_node("Hud/Bar") as Control
	var bar_at := bar.global_position
	var origin := world.position
	for cause: String in Play.SHAKES:
		var amplitude: float = Play.SHAKES[cause][0]
		var time: float = Play.SHAKES[cause][1]
		play.shake(cause)
		var largest := 0.0
		var moved_bar := false
		var frames := 0
		while frames < roundi(time / FRAME) + 2:
			await process_frame
			frames += 1
			largest = maxf(largest, play.shake_offset().length())
			moved_bar = moved_bar or bar.global_position != bar_at
		_check(largest > amplitude * 0.3 and largest <= amplitude + 0.001, "%s shakes the world by up to %.0f units" % [cause, amplitude], "largest %.2f" % largest)
		_check(world.position == origin and play.shake_offset() == Vector2.ZERO and play.shake_strength() == 0.0, "%s's shake ends with the world exactly where it was" % cause, str(world.position - origin))
		_check(not moved_bar, "%s's shake leaves the HUD where it is" % cause, str(bar.global_position))
	play.shake("lost wave")
	await process_frame
	var from := _log.size()
	play.shake("armored kill")
	_check_logged(from, "^\\[Play\\] Shake \\(armored kill\\) skipped: a stronger one \\(lost wave\\) is running$", "a weaker shake does not cut a stronger one short")
	for i in 30:
		await process_frame
	# Each event shakes: the kills, the decoy, a steal.
	from = _log.size()
	for bird_id: String in ["armored", "golden", "decoy"]:
		var bird := await _spawn_flying(play, 22, IN_FIELD_AGE, bird_id)
		bird.set_process(false)
		for shot in bird.spec.hp:
			while play.hit_stop_left() > 0.0:
				await process_frame
			await _touch(_global(play, bird.transform * LOCAL_BODY))
		for i in 30:
			await process_frame
	_check_logged(from, "^\\[Play\\] Shake \\(armored kill\\): 6 units over 0\\.25 s$", "an armored kill shakes")
	_check_logged(from, "^\\[Play\\] Shake \\(golden kill\\): 8 units over 0\\.30 s$", "a golden kill shakes")
	_check_logged(from, "^\\[Play\\] Shake \\(decoy hit\\): 10 units over 0\\.30 s$", "a decoy hit shakes")
	from = _log.size()
	var cued := await _cued_bird(play, 23, "goose")
	for i in roundi(Content.rival_lines().aim_time / FRAME) + 5:
		if cued.stolen:
			break
		await process_frame
	_check(cued.stolen, "the rival steals the cued goose", "not stolen")
	_check_logged(from, "^\\[Play\\] Shake \\(steal\\): 7 units over 0\\.30 s$", "a steal shakes")
	play = await _start_run(65, GameState.TIME_ATTACK_MODE)
	from = _log.size()
	var grass := _global(play, Vector2(480, Play.GRASS_Y + 40.0))
	for i in 120:
		if play.wave_clock > 0.2:
			break
		await process_frame
	for i in play.wave.shells:
		await _touch(grass)
	_check_logged(from, "^\\[Play\\] Shake \\(lost wave\\): 12 units over 0\\.40 s$", "a lost wave shakes")
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Pop-ups: a score pop-up bounces in past its size and settles; combo pop-ups are larger
## the higher the multiplier; a penalty pop-up shakes from side to side; each keeps its
## text and colour, and stays inside the visible area at its largest, even for a hit at
## the top edge (plan AC 7).
func _test_popup_motion() -> void:
	var play := await _start_run(66)
	var popups := play.get_node("World/Popups")
	var scales: Array[float] = []
	for n in 3:
		var goose := await _spawn_flying(play, 30 + n)
		await _touch(_global(play, goose.transform * LOCAL_BODY))
		var label := popups.get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).back() as Label
		var largest := 0.0
		var outside := false
		for i in roundi(Play.POPUP_BOUNCE_TIME / FRAME) + 6:
			largest = maxf(largest, label.scale.x)
			var box := label.get_global_transform() * Rect2(Vector2.ZERO, label.size)
			outside = outside or not _game.visible_rect().grow(0.5).encloses(box)
			await process_frame
		var rest: float = label.get_meta(&"rest_scale")
		scales.append(rest)
		var color := label.get_theme_color(&"font_color")
		_check(largest > rest * 1.2 and is_equal_approx(label.scale.x, rest) and color == Play.POPUP_COLOR, "pop-up %d '%s' bounces in past its size and settles, in the pop-up colour" % [n + 1, label.text], "largest %.2f, now %.2f, rest %.2f" % [largest, label.scale.x, rest])
		_check(not outside, "pop-up %d stays inside the visible area" % (n + 1), "outside")
		while play.hit_stop_left() > 0.0:
			await process_frame
	_check(scales[0] == 1.0 and scales[1] > scales[0] and scales[2] > scales[1] and is_equal_approx(scales[2], 1.0 + 2 * Play.POPUP_COMBO_GROWTH), "combo pop-ups grow with the multiplier", str(scales))
	var decoy := await _spawn_flying(play, 40, IN_FIELD_AGE, "decoy")
	# Shot synchronously, so the pop-up's resting x is read before it starts shaking.
	(play.get_node("ShotInput") as ShotInput).shot.emit(_global(play, decoy.transform * LOCAL_BODY))
	var penalty := popups.get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).back() as Label
	var x0 := penalty.position.x
	var swing := 0.0
	for i in roundi(Play.POPUP_SHAKE_TIME / FRAME) + 4:
		swing = maxf(swing, absf(penalty.position.x - x0))
		await process_frame
	_check(penalty.text.begins_with("-") and penalty.get_theme_color(&"font_color") == Play.PENALTY_COLOR and swing > Play.POPUP_SHAKE * 0.5 and is_equal_approx(penalty.position.x, x0) and penalty.scale == Vector2.ONE, "the penalty pop-up shakes side to side and comes to rest, in the penalty colour", "swing %.2f, x %.2f -> %.2f" % [swing, x0, penalty.position.x])
	# A hit at the very top of the field: the pop-up is moved in, not cut off.
	var high := play.spawn_bird("goose", 41)
	high.set_process(false)
	# Its body just below the top bar and its tail at the left edge: unclamped, the pop-up
	# would leave the screen on both sides as it bounces and rises.
	high.position = Vector2(12.0, Play.FIELD.position.y + 2.0)
	high.transform = Transform2D(0.0, high.position)
	await _touch(_global(play, high.transform * LOCAL_BODY))
	_check(not high.is_flying(), "the goose at the top left edge is hit", "still flying")
	var top := popups.get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).back() as Label
	var top_outside := false
	for i in roundi(Play.POPUP_TIME / FRAME) - 2:
		var box := top.get_global_transform() * Rect2(Vector2.ZERO, top.size)
		top_outside = top_outside or not _game.visible_rect().grow(0.5).encloses(box)
		await process_frame
	_check(not top_outside, "a pop-up for a hit at the top edge stays inside the visible area as it bounces and rises", "outside")
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished


## Reduce motion (saved) turns off the screen shake, the wipe (a plain fade), the pop-ups'
## bounce and shake and the title's drift, and keeps the hit stop, the feathers and the
## gameplay cues (the empty cue, the aim cue) (plan AC 8).
func _test_reduce_motion_everywhere() -> void:
	_clear_tool_save()
	_game.set_reduce_motion(true)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_game.save_path))
	_check(saved is Dictionary and (saved as Dictionary)["settings"]["reduce_motion"] == true, "reduce motion is saved", str(saved))
	await _open_title()
	_check(_game.transition_style() == "fade", "screens change by the plain fade", _game.transition_style())
	var scenery := current_scene.get_node("Scenery") as Node2D
	var drift := 0.0
	for i in 240:
		drift = maxf(drift, absf(scenery.position.x))
		await process_frame
	_check(drift == 0.0, "the title's scenery stays still", "drift %.3f" % drift)
	var play := await _start_run(67)
	var world := play.get_node("World") as Node2D
	var origin := world.position
	var feathers := play.get_node("World/Feathers") as Feathers
	var armored := await _spawn_flying(play, 24, IN_FIELD_AGE, "armored")
	armored.set_process(false)
	var still := true
	var bounced := false
	for shot in armored.spec.hp:
		await _touch(_global(play, armored.transform * LOCAL_BODY))
	_check(play.hit_stops == 1 and play.hit_stop_left() > 0.0, "the hit stop still runs", "%d stops" % play.hit_stops)
	_check(feathers.live_count() == Feathers.FEATHERS_PER_BURST, "feathers still burst", "%d" % feathers.live_count())
	var label := play.get_node("World/Popups").get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).back() as Label
	for i in 30:
		still = still and world.position == origin
		bounced = bounced or not is_equal_approx(label.scale.x, label.get_meta(&"rest_scale"))
		await process_frame
	_check(still, "an armored kill does not shake the world", str(world.position - origin))
	_check(not bounced, "the score pop-up does not bounce", "scaled")
	var decoy := await _spawn_flying(play, 25, IN_FIELD_AGE, "decoy")
	await _touch(_global(play, decoy.transform * LOCAL_BODY))
	var penalty := play.get_node("World/Popups").get_children().filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).back() as Label
	var x0 := penalty.position.x
	var wiggled := false
	for i in 20:
		wiggled = wiggled or penalty.position.x != x0
		still = still and world.position == origin
		await process_frame
	_check(not wiggled and still, "a decoy hit neither shakes the world nor its pop-up", "wiggled %s" % wiggled)
	var from := _log.size()
	play.shake("lost wave")
	await process_frame
	_check(world.position == origin, "no shake at all, whatever the cause", str(world.position - origin))
	_check_logged(from, "^\\[Play\\] Shake \\(lost wave\\) skipped: reduce motion$", "a skipped shake is logged")
	var cued := await _cued_bird(play, 26, "goose")
	_check(cued.is_cued() and (cued.get_node("Reticle") as CanvasItem).visible and play.is_rival_aiming(), "the aim cue still shows", "cued %s" % cued.is_cued())
	play.set_shell_pool(0)
	await _touch(_global(play, Vector2(480, 200)))
	_check(play.is_empty_cue_shown(), "the empty-pool cue still shows", "hidden")
	_game.set_reduce_motion(false)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_check(_game.transition_style() == "wipe", "with reduce motion off the wipe is back", _game.transition_style())
	_clear_tool_save()


## One settings slider (`what` "Music" or "SFX", bus `bus_name`, save key `key`, starting at
## `start`): a held Right key steps it by TouchSlider.KEY_STEP and each repeat (echo) again,
## live on the bus and label but unsaved and silent; the key's release saves the final value
## once with one UI tap; a Left press and release steps it back and saves; a touch at 25%
## and a drag to 75% apply live, unsaved and silent, and the lift saves once with one tap.
func _check_slider(settings: Settings, slider: TouchSlider, what: String, bus_name: StringName, key: String, start: int) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	var label := "MusicLabel" if key == "music" else "SfxLabel"
	var volume := func() -> int: return _game.music_volume if key == "music" else _game.sfx_volume
	var stored := func() -> float: return (JSON.parse_string(FileAccess.get_file_as_string(_game.save_path)) as Dictionary)["settings"][key]
	slider.grab_focus()
	var from := _log.size()
	var sounds := _game.sfx_log.size()
	await _key_event(KEY_RIGHT, true, false)
	var step := int(TouchSlider.KEY_STEP)
	_check(volume.call() == start + step and step >= 5 and slider.is_held() and is_equal_approx(AudioServer.get_bus_volume_db(bus), GameState.bus_volume_db(start + step)) and _text_of(settings, label) == "%s %d" % [what, start + step],
		"%s: a Right press steps the slider by %d (at least 5), the bus and label follow at once" % [what, step], "volume %d, held %s, label %s" % [volume.call(), slider.is_held(), _text_of(settings, label)])
	for echo in 2:
		await _key_event(KEY_RIGHT, true, true)
	_check(volume.call() == start + 3 * step and stored.call() == float(start) and _game.sfx_log.size() == sounds and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Game] Saved to")),
		"%s: the held key's repeats keep stepping, with no save and no tap per repeat" % what, "volume %d, stored %s, sounds %s" % [volume.call(), stored.call(), _game.sfx_log.slice(sounds)])
	_check_logged(from, "^\\[Settings\\] %s slider moved to %d \\(held\\)$" % [what, start + 3 * step], "%s: each step is logged as held" % what)
	await _key_event(KEY_RIGHT, false, false)
	var saves := Array(_log.since(from)).filter(func(line: String) -> bool: return line.begins_with("[Game] Saved to")).size()
	_check(not slider.is_held() and stored.call() == float(start + 3 * step) and saves == 1 and _game.sfx_log.slice(sounds) == [&"ui_tap"], "%s: releasing the key saves the final value once and taps once" % what, "stored %s, %d saves, sounds %s" % [stored.call(), saves, _game.sfx_log.slice(sounds)])
	_check_logged(from, "^\\[Settings\\] %s slider released at %d \\(keys released\\); saving$" % [what, start + 3 * step], "%s: the key release is logged" % what)
	await _key(KEY_LEFT)
	_check(volume.call() == start + 2 * step and stored.call() == float(start + 2 * step) and slider.has_focus(), "%s: a Left press and release steps back and saves, the focus stays" % what, "volume %d, stored %s" % [volume.call(), stored.call()])
	# A finger: the press sets the value under it, the drag follows, the lift saves once.
	var grabber := float(slider.get_theme_icon(&"grabber").get_width())
	var rect := slider.get_global_rect()
	var at_quarter := Vector2(rect.position.x + grabber / 2.0 + (rect.size.x - grabber) * 0.25, rect.get_center().y)
	var at_three_quarters := Vector2(rect.position.x + grabber / 2.0 + (rect.size.x - grabber) * 0.75, rect.get_center().y)
	var before := stored.call() as float
	from = _log.size()
	sounds = _game.sfx_log.size()
	await _finger(at_quarter, true)
	await _drag(at_three_quarters)
	_check(volume.call() == 75 and slider.is_held() and is_equal_approx(AudioServer.get_bus_volume_db(bus), GameState.bus_volume_db(75)) and stored.call() == before and _game.sfx_log.size() == sounds,
		"%s: a touch and a drag set the volume live (bus and label), unsaved and silent while the finger is down" % what, "volume %d, held %s, stored %s, sounds %s" % [volume.call(), slider.is_held(), stored.call(), _game.sfx_log.slice(sounds)])
	_check_logged(from, "^\\[Settings\\] %s slider moved to 25 \\(held\\)$" % what, "%s: the touch is logged as held" % what)
	await _finger(at_three_quarters, false)
	saves = Array(_log.since(from)).filter(func(line: String) -> bool: return line.begins_with("[Game] Saved to")).size()
	_check(not slider.is_held() and stored.call() == 75.0 and saves == 1 and _game.sfx_log.slice(sounds) == [&"ui_tap"], "%s: lifting the finger saves the volume once and plays the UI tap" % what, "stored %s, %d saves, sounds %s" % [stored.call(), saves, _game.sfx_log.slice(sounds)])
	_check_logged(from, "^\\[Settings\\] %s slider released at 75 \\(finger lifted\\); saving$" % what, "%s: the lift is logged" % what)


## A key event for `keycode`: pressed or released, an echo (auto-repeat) or not.
func _key_event(keycode: Key, pressed: bool, echo: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await process_frame


## A touch of finger `index` (TOUCH_INDEX unless given) pressed or lifted at canvas point `at`.
func _finger(at: Vector2, pressed: bool, index := TOUCH_INDEX) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = root.get_final_transform() * at
	touch.pressed = pressed
	Input.parse_input_event(touch)
	await process_frame


## A drag of finger `index` (TOUCH_INDEX unless given) to canvas point `at`.
func _drag(at: Vector2, index := TOUCH_INDEX) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = root.get_final_transform() * at
	Input.parse_input_event(drag)
	await process_frame


## A slider hold whose end never arrives still ends, saving its value, and the slider
## recovers: the rotate overlay showing while a finger is down (GUI input is disabled, so
## the lift is never delivered) saves the held volume and later touches and keys work; a
## press by another finger while one is down ends the old hold (saved) and takes over;
## closing the settings over the paused run with a finger down (Escape, or resuming) saves
## the held volume (review finding 1).
func _test_slider_hold_cut_short() -> void:
	_clear_tool_save()
	_game.load_game()
	_game.save_game()
	var stored := func() -> float: return (JSON.parse_string(FileAccess.get_file_as_string(_game.save_path)) as Dictionary)["settings"]["music"]
	_game.goto(GameState.Flow.SETTINGS)
	await _game.transition_finished
	await process_frame
	var settings := current_scene as Settings
	var slider := settings.music_slider()
	var points := _slider_points(slider)
	var from := _log.size()
	await _finger(points[0], true)
	_check(slider.is_held() and _game.music_volume == 25 and stored.call() == 70.0, "a finger down on the music slider holds it at 25, unsaved", "held %s, volume %d" % [slider.is_held(), _game.music_volume])
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown() and not slider.is_held() and stored.call() == 25.0, "the rotate overlay showing mid-press ends the hold and saves the held volume", "held %s, stored %s" % [slider.is_held(), stored.call()])
	_check_logged(from, "^\\[Settings\\] Music slider released at 25 \\(rotate overlay\\); saving$", "the cut-short hold is logged with its cause")
	await _finger(points[0], false)
	root.size = BASE_WINDOW
	await process_frame
	await process_frame
	await _finger(points[1], true, TOUCH_INDEX + 1)
	await _finger(points[1], false, TOUCH_INDEX + 1)
	_check(_game.music_volume == 75 and stored.call() == 75.0 and not slider.is_held(), "after the overlay a later touch moves the slider and its lift saves", "volume %d, stored %s" % [_game.music_volume, stored.call()])
	from = _log.size()
	slider.grab_focus()
	await _key(KEY_RIGHT)
	_check(_game.music_volume == 80 and stored.call() == 80.0 and not slider.is_held(), "after the overlay a key step is saved on its release (no stuck hold)", "volume %d, stored %s" % [_game.music_volume, stored.call()])
	# A lift that never comes: the next press (another finger) ends the old hold first.
	from = _log.size()
	await _finger(points[0], true)
	await _finger(points[1], true, TOUCH_INDEX + 1)
	_check(stored.call() == 25.0 and slider.is_held() and _game.music_volume == 75, "a new touch while a finger is down saves the old hold and takes over", "stored %s, volume %d" % [stored.call(), _game.music_volume])
	_check_logged(from, "^\\[Settings\\] Music slider released at 25 \\(a new touch took over\\); saving$", "the take-over is logged")
	await _finger(points[1], false, TOUCH_INDEX + 1)
	await _finger(points[0], false)
	_check(stored.call() == 75.0 and not slider.is_held(), "the new finger's lift saves its value; the stale finger's late lift changes nothing", "stored %s" % stored.call())
	# Over the paused run: Escape (and resuming) close the settings with a finger down.
	var play := await _start_run(68)
	for closer: String in ["Escape", "resume"]:
		play.open_pause("test")
		await process_frame
		play.open_settings()
		await process_frame
		var overlay_slider := play.settings_overlay().music_slider()
		var overlay_points := _slider_points(overlay_slider)
		from = _log.size()
		await _finger(overlay_points[0], true)
		await _drag(overlay_points[1])
		_check(overlay_slider.is_held() and _game.music_volume == 75, "%s: a finger holds the overlay's slider at 75" % closer, "volume %d" % _game.music_volume)
		if closer == "Escape":
			await _key(KEY_ESCAPE)
		else:
			play.resume()
			await process_frame
		_check(play.settings_overlay() == null and stored.call() == 75.0, "%s closes the settings with a finger down and the held volume is saved" % closer, "overlay %s, stored %s" % [play.settings_overlay(), stored.call()])
		_check_logged(from, "^\\[Settings\\] Music slider released at 75 \\(left the screen\\); saving$", "%s: the closed hold is logged" % closer)
		await _finger(overlay_points[1], false)
		_game.set_music_volume(70)
		if play.is_paused():
			play.resume()
	_game.set_music_volume(GameState.DEFAULT_MUSIC_VOLUME)
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_clear_tool_save()


## The canvas points 25% and 75% along `slider` (HSlider's mapping: values 25 and 75 of 100).
func _slider_points(slider: TouchSlider) -> Array[Vector2]:
	var grabber := float(slider.get_theme_icon(&"grabber").get_width())
	var rect := slider.get_global_rect()
	var points: Array[Vector2] = []
	for fraction: float in [0.25, 0.75]:
		points.append(Vector2(rect.position.x + grabber / 2.0 + (rect.size.x - grabber) * fraction, rect.get_center().y))
	return points


## AC 10: the rival aims at one bird at a time. Two geese past their linger_time at once:
## the cue goes to the one that has flown longest (the other is younger and has the lower
## number, so the age decides), and until that one is stolen no frame ever has two cues and
## the younger goose is never aimed at; after the steal the aim gap keeps it uncued too.
func _test_rival_one_cue_at_a_time() -> void:
	var play := await _start_run(71)
	# No wave birds: only the two geese below fly.
	play._next_spawn = play.wave.spawns.size()
	var younger := play.spawn_bird("goose", 301)
	var older := play.spawn_bird("goose", 302)
	younger.age = 3.6
	older.age = 3.7
	var most_cues := 0
	var younger_cued := false
	for i in 200:
		await process_frame
		var cued := play.flying_birds().filter(func(bird: Bird) -> bool: return bird.is_cued()).size()
		most_cues = maxi(most_cues, cued)
		younger_cued = younger_cued or (is_instance_valid(younger) and younger.is_cued())
		if older.stolen:
			break
	_check(older.stolen and most_cues == 1 and not younger_cued, "with two geese eligible the rival aims only at the one flown longest, and steals it", "stolen %s, at most %d cues at once, the younger cued %s" % [older.stolen, most_cues, younger_cued])
	var steal_clock := play.run_clock
	while is_instance_valid(younger) and younger.is_flying() and play.run_clock - steal_clock < Play.RIVAL_AIM_GAP - 2.0 * FRAME:
		younger_cued = younger_cued or younger.is_cued()
		await process_frame
	_check(not younger_cued, "after a steal no new cue starts during the aim gap", "the younger goose was cued %.2f s after the steal" % (play.run_clock - steal_clock))
	await _open_title()


## AC 11: after a cue cancelled by the player's shot, an eligible goose waits RIVAL_AIM_GAP
## seconds of run time; a pause in between does not count (the frames paused add to the
## wait, the run clock does not move); the cue then starts within a frame of the gap's end
## and its log names the gap.
func _test_rival_aim_gap() -> void:
	var play := await _start_run(72)
	play._next_spawn = play.wave.spawns.size()
	play.set_shell_pool(10)
	var first := await _cued_bird(play, 303, "goose")
	var waiting := play.spawn_bird("goose", 304)
	waiting.age = 3.0
	_check(first.is_cued() and not waiting.is_cued(), "a first goose is cued", "cued %s" % first.is_cued())
	first.set_process(false)
	await _touch(_global(play, first.transform * LOCAL_BODY))
	first.set_process(true)
	_check(first.state != Bird.State.FLYING and not first.is_cued(), "the player's shot kills the cued goose and cancels the cue", "state %d" % first.state)
	var cancel_clock := play.run_clock
	var from := _log.size()
	var paused_frames := 0
	var frames := 0
	var early := false
	while not waiting.is_cued() and frames < 400:
		if frames == 30:
			play.open_pause("pause button")
			var clock := play.run_clock
			for i in 60:
				await process_frame
				paused_frames += 1
			_check(play.run_clock == clock and not waiting.is_cued(), "the aim gap stands still while paused", "clock %.3f -> %.3f" % [clock, play.run_clock])
			play.resume()
		await process_frame
		frames += 1
		if waiting.is_cued() and play.run_clock - cancel_clock < Play.RIVAL_AIM_GAP:
			early = true
	var waited := play.run_clock - cancel_clock
	_check(waiting.is_cued() and not early and waited < Play.RIVAL_AIM_GAP + 2.0 * FRAME, "the next cue starts once %.1f s of run time have passed since the cancel" % Play.RIVAL_AIM_GAP, "cued %s after %.3f s of run time" % [waiting.is_cued(), waited])
	_check(frames + paused_frames > roundi(Play.RIVAL_AIM_GAP / FRAME) + 50, "paused time does not count toward the gap", "%d frames running, %d paused" % [frames, paused_frames])
	_check_logged(from, "^\\[Play\\] Aim cue on goose #%d: age [\\d.]+ \\(linger 3\\.50 s\\), the rival fires in 1\\.00 s \\(the longest flown of 1 eligible; 1\\.5\\d s since the last cue ended, aim gap 1\\.50 s\\) " % waiting.number, "the cue after the gap logs the time since the last cue and the gap")
	await _open_title()


## AC 13: the mouse pointer is the crosshair while the run is live (its texture at most
## 64 px a side), the arrow on pause, back to the crosshair on resume, the arrow at the
## run's end (the results) and on leaving Play; each change logged. The calls Play made to
## Input.set_custom_mouse_cursor (Play.cursor_calls, recorded by its one seam) are read:
## the crosshair with CURSOR_ARROW and its hotspot at the texture's centre, the reset with
## a null texture.
func _test_crosshair_cursor() -> void:
	var size := Play.CROSSHAIR.get_size()
	_check(size.x <= 64.0 and size.y <= 64.0 and size.x > 0.0, "the crosshair texture is at most 64 px a side", str(size))
	var crosshair_call := [Play.CROSSHAIR, Input.CURSOR_ARROW, size / 2.0]
	var arrow_call := [null, Input.CURSOR_ARROW, Vector2.ZERO]
	var from := _log.size()
	var play := await _start_run(73)
	_check(play.crosshair_shown and play.cursor_log == ["crosshair"] and play.cursor_calls == [crosshair_call], "a live run sets the crosshair, its hotspot at its centre", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	_check_logged(from, "^\\[Play\\] Cursor: crosshair$", "the crosshair is logged")
	play.open_pause("pause button")
	_check(not play.crosshair_shown and play.cursor_log.back() == "arrow (paused)" and play.cursor_calls.back() == arrow_call, "the pause menu resets the pointer to the arrow", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	play.resume()
	_check(play.crosshair_shown and play.cursor_log.back() == "crosshair" and play.cursor_calls.back() == crosshair_call, "resuming sets the crosshair again", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	await _key(KEY_ESCAPE)
	_check(not play.crosshair_shown and play.cursor_calls.back() == arrow_call, "Escape's pause resets the pointer to the arrow", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	await _key(KEY_ESCAPE)
	_check(play.crosshair_shown and play.cursor_calls.back() == crosshair_call, "Escape's resume sets the crosshair", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	play._end_run()
	_check(not play.crosshair_shown and play.cursor_log.back() == "arrow (the run is over)" and play.cursor_calls.back() == arrow_call, "the run's end (to the results) resets the pointer to the arrow", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	_check(play.cursor_calls.size() == 6, "every change made exactly one Input call", str(play.cursor_calls))
	await _game.transition_finished
	_check(_game.state == GameState.Flow.RESULTS, "the run ended on the results", str(_game.state))
	_check_logged(from, "^\\[Play\\] Cursor: arrow \\(the run is over\\)$", "the arrow is logged with its cause")
	play = await _start_run(74)
	_check(play.crosshair_shown, "a new run shows the crosshair", str(play.cursor_log))
	var calls := play.cursor_calls
	_game.goto(GameState.Flow.TITLE)
	await _game.transition_finished
	_check(calls.back() == arrow_call, "leaving Play resets the pointer to the arrow", str(calls))


## Finding 3 of the PR 10 review: while the rotate overlay is up the pointer is the arrow,
## in both orders. Overlay first (upright during the wipe into the run): the run starts
## under it without ever setting the crosshair; rotating back opens the pause menu (still
## the arrow) and Resume sets the crosshair. Mid-run: turning upright resets the pointer to
## the arrow at once.
func _test_crosshair_under_rotate_overlay() -> void:
	var crosshair_call := [Play.CROSSHAIR, Input.CURSOR_ARROW, Play.CROSSHAIR.get_size() / 2.0]
	var arrow_call := [null, Input.CURSOR_ARROW, Vector2.ZERO]
	await _open_title()
	_game.goto(GameState.Flow.PLAY, {"mode": GameState.ENDLESS_MODE, "seed": 77})
	await process_frame
	root.size = PORTRAIT_9_19_5
	await process_frame
	await _game.transition_finished
	await process_frame
	var play := current_scene as Play
	_check(_game.is_rotate_overlay_shown() and not play.crosshair_shown and not crosshair_call in play.cursor_calls, "overlay first: the run starts under it with the arrow, never the crosshair", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	root.size = BASE_WINDOW
	await process_frame
	await process_frame
	_check(play.is_paused() and not play.crosshair_shown and not crosshair_call in play.cursor_calls, "overlay first: rotating back opens the pause menu, still the arrow", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	play.resume()
	_check(play.crosshair_shown and play.cursor_calls.back() == crosshair_call, "overlay first: Resume sets the crosshair", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	root.size = PORTRAIT_9_19_5
	await process_frame
	_check(_game.is_rotate_overlay_shown() and not play.crosshair_shown and play.cursor_log.back() == "arrow (rotate overlay)" and play.cursor_calls.back() == arrow_call, "mid-run: turning upright resets the pointer to the arrow", "%s, calls %s" % [play.cursor_log, play.cursor_calls])
	root.size = BASE_WINDOW
	await process_frame
	await process_frame
	_check(play.is_paused() and not play.crosshair_shown, "mid-run: rotating back leaves the arrow over the pause menu", str(play.cursor_log))
	play.resume()
	_check(play.crosshair_shown, "mid-run: Resume sets the crosshair", str(play.cursor_log))
	await _open_title()


## Finding 1 of the PR 10 review: the rival never starts a cue that cannot finish. A golden
## goose past its linger_time with less than aim_time left before it flees is never cued:
## it flies off and escapes, and no cue on it is logged.
func _test_rival_never_cues_a_short_window() -> void:
	var play := await _start_run(75)
	play._next_spawn = play.wave.spawns.size()
	var golden := Content.bird("golden")
	var aim := Content.rival_lines().aim_time
	var from := _log.size()
	var late := play.spawn_bird("golden", 305)
	late.age = golden.flee_time - aim + 0.1
	var cued := false
	for i in 300:
		await process_frame
		if not is_instance_valid(late) or not late.is_flying():
			break
		cued = cued or late.is_cued()
	_check(not cued and not Array(_log.since(from)).any(func(line: String) -> bool: return line.begins_with("[Play] Aim cue on golden")), "a bird with less than aim_time left before it flees is never cued", "cued %s" % cued)
	_check_logged(from, "^\\[Play\\] Escaped golden #\\d+ ", "the short-window golden goose escapes un-cued")
	await _open_title()


## Finding 1 of the PR 10 review: in the normal one-cue flow (nobody shoots, so no shells
## run out) every cue the rival starts ends in a steal: over a whole Endless run and the
## whole of night_6 (zigzag swifts, the boss flock), at time scale 8, he steals and no cue
## is ever cancelled as "fled".
func _test_rival_cues_always_finish() -> void:
	for start: Callable in [func() -> Play: return await _start_run(76), func() -> Play: return await _start_level("night_6")]:
		var from := _log.size()
		var play: Play = await start.call()
		var name := play.level.id if play.level != null else play.mode.id
		Engine.time_scale = 8.0
		for i in 3000:
			if _game.state == GameState.Flow.RESULTS and not _game.is_transitioning():
				break
			await process_frame
		Engine.time_scale = 1.0
		var lines := Array(_log.since(from))
		var cues := lines.filter(func(line: String) -> bool: return line.begins_with("[Play] Aim cue on ") and not line.contains(" cancelled ")).size()
		var steals := lines.filter(func(line: String) -> bool: return line.begins_with("[Play] Stolen ")).size()
		var fled := lines.filter(func(line: String) -> bool: return line.contains(" cancelled (fled)"))
		_check(_game.state == GameState.Flow.RESULTS and steals >= 3 and cues == steals and fled.is_empty(), "%s: every cue started ends in a steal, none cancelled as fled" % name, "%d cues, %d steals, fled: %s" % [cues, steals, fled])
	await _open_title()


## Finding 5 of the PR 10 review: the laugh queued by a steal (Game.play_sfx_later) holds
## through a pause: paused a few frames after the steal, it does not play while paused
## (still waiting), and after Resume it plays once the rest of RIVAL_LAUGH_DELAY has run.
func _test_rival_laugh_waits_out_a_pause() -> void:
	var play := await _start_run(78)
	play._next_spawn = play.wave.spawns.size()
	var cued := await _cued_bird(play, 306, "goose")
	for i in 120:
		if cued.stolen:
			break
		await process_frame
	_game.sfx_log.clear()
	var before := 6
	for i in before:
		await process_frame
	play.open_pause("pause button")
	for i in 60:
		await process_frame
	_check(cued.stolen and not &"rival_laugh" in _game.sfx_log and _game.sfx_waiting() == 1, "a laugh queued before a pause waits through it", "stolen %s, %s, %d waiting" % [cued.stolen, _game.sfx_log, _game.sfx_waiting()])
	play.resume()
	var after := 0
	while not &"rival_laugh" in _game.sfx_log and after < 120:
		await process_frame
		after += 1
	var rest := roundi(Play.RIVAL_LAUGH_DELAY / FRAME) - before
	_check(absi(after - rest) <= 2 and _game.sfx_waiting() == 0, "after Resume the laugh keeps the rest of its delay", "%d frames after Resume, expected %d" % [after, rest])
	await _open_title()


## Findings 2 and 5 of the PR 10 review: a steal that ends the run still laughs, the laugh
## outliving the change to the results screen (with reduce motion's short fade it plays
## after the scene has changed), and the results' parting blurt starts only once the laugh
## has finished: its first syllable is at least the laugh's length after the laugh, and its
## [Audio] line says it waits for rival_laugh. The bubble line shows at once.
func _test_rival_laugh_before_results_blurt() -> void:
	var laugh_length := (load("res://audio/sfx/rival_laugh.wav") as AudioStream).get_length()
	# The parting blurt's wait for the laugh, with the blurts switched on.
	_game.heckle_blurts = true
	for reduce_motion: bool in [false, true]:
		var label := "reduce motion" if reduce_motion else "the wipe"
		_game.set_reduce_motion(reduce_motion)
		_clear_tool_save()
		var play := await _start_run(79)
		play._next_spawn = play.wave.spawns.size()
		var cued := await _cued_bird(play, 307, "goose")
		play.escaped = play.mode.escape_limit - 1
		_game.sfx_log.clear()
		var from := _log.size()
		var stolen := false
		var laugh_clock := -1.0
		var laugh_on_results := false
		var blurt_clock := -1.0
		var waiting := -1
		for i in 240:
			await process_frame
			# The stolen goose frees itself once it has fallen off the screen.
			stolen = stolen or (is_instance_valid(cued) and cued.stolen)
			if laugh_clock < 0.0 and &"rival_laugh" in _game.sfx_log:
				laugh_clock = _game._clock
				laugh_on_results = current_scene is Results
			if waiting < 0 and &"heckle_results" in _game.sfx_log:
				waiting = _game.blurt_syllables_waiting()
			elif waiting > 0 and blurt_clock < 0.0 and _game.blurt_syllables_waiting() < waiting:
				blurt_clock = _game._clock
			if laugh_clock >= 0.0 and blurt_clock >= 0.0:
				break
		var order := _game.sfx_log.slice(0, 4)
		_check(stolen and laugh_clock >= 0.0 and order.find(&"rival_steal") < order.find(&"rival_laugh"), "%s: a run-ending steal laughs after its shot" % label, str(_game.sfx_log))
		if reduce_motion:
			_check(laugh_on_results, "%s: the laugh plays after the change to the results screen" % label, "scene %s" % current_scene)
		_check(blurt_clock >= laugh_clock + laugh_length - FRAME, "%s: the results' blurt starts once the laugh has finished" % label, "laugh at %.3f (%.2f s long), first syllable at %.3f" % [laugh_clock, laugh_length, blurt_clock])
		_check_logged(from, "^\\[Audio\\] SFX heckle_results: \\d+ syllables \\(.*\\) for \".+\", starting in [\\d.]+ s once rival_laugh has finished$", "%s: the results blurt logs its wait for the laugh" % label)
		while _game.is_transitioning():
			await process_frame
		var results := current_scene as Results
		_check(results != null and (results.get_node("%RivalPanel") as Control).visible, "%s: the results show at once, the rival's panel with them" % label, "scene %s" % current_scene)
	_game.set_reduce_motion(false)
	_game.heckle_blurts = GameState.HECKLE_BLURTS
	_clear_tool_save()
	await _open_title()
