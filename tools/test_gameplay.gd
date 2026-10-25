extends SceneTree
## Headless gameplay tests. Run with --fixed-fps 60 so one frame = one physics tick:
##   "$GODOT" --headless --path huntfrenzy --fixed-fps 60 --script "$PWD/tools/test_gameplay.gd"
## Prints "test_gameplay: OK" when every test passes; exits 1 otherwise.
## To add a test: write a `_test_*` func (it may await) that reports through _check(),
## and append it to the list in _tests(). Tests run in that order on one SceneTree, so
## each one restores whatever it changes (window size, Game.scene_paths, quiet_errors, pause).

const TITLE_PATH := "res://scenes/title.tscn"
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
const WATCHDOG_MSEC := 60000

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
	]


func _run() -> void:
	root.size = BASE_WINDOW
	await process_frame
	for test in _tests():
		await test.call()
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


## A real touch on Play presses it, and so does Enter on the focused button.
func _test_title_button_tap_and_enter() -> void:
	await _open_title()
	var title := current_scene as Title
	var button := title.get_node("Safe/PlayButton") as Button
	var notice := title.get_node("Safe/Notice") as Label
	_check(not notice.visible, "the notice starts hidden", notice.text)
	await _tap(button)
	_check(title.play_presses == 1, "a tap presses Play", "%d presses" % title.play_presses)
	_check(notice.visible and notice.text == Title.NOT_YET_TEXT, "Play shows the notice", "%s '%s'" % [notice.visible, notice.text])
	button.grab_focus()
	await _key(KEY_ENTER)
	_check(title.play_presses == 2, "Enter presses the focused Play", "%d presses" % title.play_presses)


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
