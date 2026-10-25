extends SceneTree
## Project gate for the touch-first, landscape rules:
## - project.godot defines no input actions besides the built-in ui_* ones,
## - no script (standalone or embedded in .tscn/.tres) reads mouse events at all
##   (emulate_touch_from_mouse turns the mouse into touches), and none outside
##   res://scripts/ui/ handles raw input: touch, drag, gesture, key or joypad events,
##   input callbacks (_input, _gui_input, ...) or gui_input/input_event signal
##   connections, action, key or joypad polling,
## - no script filters on touch index 0 (a web build's index is the browser's
##   Touch.identifier, which iOS Safari makes large and never 0),
## - every interactive Control in a saved scene is at least MIN_TARGET base units on
##   both axes; every BaseButton can take keyboard focus; an icon-only Button (no
##   text) and every TextureButton carry an accessibility_name,
## - in screen scenes (a root Control that fills the screen, or a root that is not a
##   Control: a CanvasLayer HUD, a Node2D game scene), the top HUD bar (the top
##   HUD_BAR_HEIGHT base units of the screen) holds no interactive Control except one
##   named HUD_BAR_NAME (PauseButton).
## Also compiles every script: project.godot raises GDScript warnings to errors,
## so any warning fails here.
## Usage (from repo root): "$GODOT" --headless --path huntfrenzy --script "$PWD/tools/check_project.gd"
## Prints "check_project: OK" on success; exits 1 and prints every violation otherwise
## (SCRIPT ERROR lines above them give compile details).
##
## Limits: this is a text and saved-scene scan. It does not see Controls created at
## runtime (Button.new()), input read through indirection (a variable holding an event
## class name), an index-0 filter written another way (a match on the index, the index
## copied into a variable first; only member `.index` and `*touch_index`/`*finger_index`
## names are matched, so an `index` from find() is fine), or layouts that only exist
## after a script moves nodes. Scenes are measured in a 960x540 window after two frames,
## so a Control sized by its script's _ready() is measured as the script leaves it.
## Control-rooted scenes that do not fill the screen are parts, checked for size only.
## A custom action named ui_something is indistinguishable from a built-in one here.

const UI_INPUT_PATH := "res://scripts/ui/"
## Mouse input: forbidden everywhere, scripts/ui/ included.
## "mouse_position" also covers get_global_mouse_position and get_local_mouse_position;
## the DisplayServer reads and the CollisionObject mouse virtuals and signals are listed
## by name (emulate_touch_from_mouse does not turn them into touches).
const MOUSE_TOKENS: Array[String] = [
	"InputEventMouse", "mouse_position", "get_last_mouse_velocity", "get_last_mouse_screen_velocity",
	"is_mouse_button_pressed", "get_mouse_button_mask", "mouse_entered", "mouse_exited",
	"mouse_get_position", "mouse_get_button_state", "_mouse_enter", "_mouse_exit",
	"_mouse_shape_enter", "_mouse_shape_exit", "mouse_shape_entered", "mouse_shape_exited",
]
## Raw input reads, input callbacks and polling: only scripts/ui/ may use them.
const RAW_INPUT_TOKENS: Array[String] = [
	"InputEventScreenTouch", "InputEventScreenDrag", "InputEventKey", "InputEventJoypad",
	"InputEventGesture", "InputEventMagnifyGesture", "InputEventPanGesture",
	"func _input", "func _unhandled_input", "func _unhandled_key_input", "func _shortcut_input", "func _gui_input",
	"gui_input.connect", "signal=\"gui_input\"", "input_event.connect", "signal=\"input_event\"",
	"is_key_pressed", "is_physical_key_pressed", "is_key_label_pressed", "is_joy_button_pressed", "get_joy_axis",
	"is_action", "get_action_strength", "get_action_raw_strength", "get_axis", "get_vector", "is_anything_pressed",
]
## A touch index (a member `.index`, or a `*touch_index`/`*finger_index` name) compared
## with 0 (either side), or "below 1".
const INDEX_ZERO_PATTERN := "(?:\\.index|\\b\\w*(?:touch|finger)_index)\\s*(==|!=|<=|>=|<|>)\\s*0\\b|\\b0\\s*(==|!=|<=|>=|<|>)\\s*(?:[\\w.]*\\.index|\\w*(?:touch|finger)_index)\\b|(?:\\.index|\\b\\w*(?:touch|finger)_index)\\s*<\\s*1\\b"
const SOURCE_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]
const BASE_SIZE := Vector2i(960, 540)
const MIN_TARGET := 44.0
## Height of the top HUD bar, in base units from the top of the screen.
const HUD_BAR_HEIGHT := 56.0
## The only interactive Control allowed in the top HUD bar.
const HUD_BAR_NAME := &"PauseButton"

var _violations: Array[String] = []
var _index_zero := RegEx.create_from_string(INDEX_ZERO_PATTERN)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = BASE_SIZE
	_check_actions()
	var files: Array[String] = []
	_collect_files("res://", files)
	for path in files:
		if path.ends_with(".gd"):
			_check_compiles(path)
		if path.get_extension() in SOURCE_EXTENSIONS:
			_check_source(path)
	for path in files:
		if path.ends_with(".tscn"):
			await _check_scene(path)
	if _violations.is_empty():
		print("check_project: OK (%d files scanned)" % files.size())
		quit(0)
		return
	for violation in _violations:
		printerr("check_project: " + violation)
	printerr("check_project: FAILED with %d violation(s)" % _violations.size())
	quit(1)


## Only the built-in ui_* actions may exist (overriding their events is allowed).
func _check_actions() -> void:
	for property in ProjectSettings.get_property_list():
		var name: String = property["name"]
		if name.begins_with("input/") and not name.begins_with("input/ui_"):
			_violations.append("project.godot defines input action '%s' (only built-in ui_* actions are allowed)" % name.trim_prefix("input/"))


func _check_compiles(path: String) -> void:
	var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if script == null or not script.can_instantiate():
		_violations.append("%s: fails to compile (warnings count as errors)" % path)


func _check_source(path: String) -> void:
	var source := _read_text(path)
	for token in MOUSE_TOKENS:
		if token in source:
			_violations.append("%s: uses '%s' (mouse input arrives as touch; read InputEventScreenTouch/Drag in scripts/ui/)" % [path, token])
	if not path.begins_with(UI_INPUT_PATH):
		for token in RAW_INPUT_TOKENS:
			if token in source:
				_violations.append("%s: uses '%s' (raw input handling belongs in scripts/ui/)" % [path, token])
	var lines := source.split("\n")
	for i in lines.size():
		if _index_zero.search(lines[i]) != null:
			_violations.append("%s:%d: filters on touch index 0 (iOS Safari touch indices are large, never 0)" % [path, i + 1])


func _read_text(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_violations.append("%s: cannot read file (error %d)" % [path, FileAccess.get_open_error()])
	return text


## Instantiates the scene in the base-size window, lets containers and anchors settle,
## then measures every interactive Control.
func _check_scene(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_violations.append("%s: failed to load scene" % path)
		return
	var scene_root := packed.instantiate()
	if scene_root == null:
		_violations.append("%s: failed to instantiate scene" % path)
		return
	root.add_child(scene_root)
	await process_frame
	await process_frame
	var root_control := scene_root as Control
	var full_screen := root_control == null or root_control.get_global_rect().size.is_equal_approx(root.get_visible_rect().size)
	_check_node(path, scene_root, full_screen)
	scene_root.queue_free()
	await process_frame


func _check_node(path: String, node: Node, full_screen: bool) -> void:
	var control := node as Control
	if control != null and _is_interactive(control):
		var rect := control.get_global_rect()
		var which := "%s: interactive Control '%s'" % [path, _scene_path_of(control)]
		if rect.size.x < MIN_TARGET or rect.size.y < MIN_TARGET:
			_violations.append("%s is %s, smaller than %dx%d" % [which, rect.size, int(MIN_TARGET), int(MIN_TARGET)])
		if full_screen and rect.position.y < HUD_BAR_HEIGHT and control.name != HUD_BAR_NAME:
			_violations.append("%s starts at y=%.0f, inside the top HUD bar (%d units; only %s may be interactive there)" % [which, rect.position.y, int(HUD_BAR_HEIGHT), HUD_BAR_NAME])
		if control is BaseButton and control.focus_mode == Control.FOCUS_NONE:
			_violations.append("%s cannot take keyboard focus (focus_mode none)" % which)
		var icon_only := control is TextureButton or (control is Button and (control as Button).text.strip_edges().is_empty())
		if icon_only and control.accessibility_name.strip_edges().is_empty():
			_violations.append("%s has no text and no accessibility_name" % which)
	for child in node.get_children():
		_check_node(path, child, full_screen)


## Built-in input Controls, and scripted Controls that handle _gui_input and receive
## touches (mouse_filter STOP or PASS; PASS still delivers _gui_input).
func _is_interactive(control: Control) -> bool:
	# Range covers Slider, SpinBox and ScrollBar; the progress bars only display a value.
	var takes_input_range := control is Range and not (control is ProgressBar or control is TextureProgressBar)
	if (takes_input_range or control is BaseButton or control is LineEdit or control is TextEdit or control is ScrollContainer
			or control is ItemList or control is Tree or control is TabBar or control is TabContainer or control is ColorPicker
			or control is GraphEdit):
		return true
	var script := control.get_script() as Script
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE or script == null:
		return false
	return script.get_script_method_list().any(func(method: Dictionary) -> bool: return method["name"] == "_gui_input")


func _scene_path_of(node: Node) -> String:
	var owner_node := node.owner if node.owner != null else node
	return str(owner_node.get_path_to(node))


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_violations.append("%s: cannot open directory (error %d)" % [dir_path, DirAccess.get_open_error()])
		return
	for file in dir.get_files():
		out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		# A .gdignore keeps a directory out of the project, as in Godot's import.
		if not sub.begins_with(".") and not FileAccess.file_exists(dir_path.path_join(sub).path_join(".gdignore")):
			_collect_files(dir_path.path_join(sub), out)
