class_name GameState
extends Node
## Autoload "Game" (scenes/game.tscn): the app flow state machine and its scene
## transitions, ScreenFit (the visible and safe-area rects in base units) and the
## rotate overlay.
## Every flow change goes through goto(), which fades a cover over the screen
## (touches blocked), swaps the scene, fades the cover away and logs the transition
## ("[Game] goto A -> B ..." when it starts, "[Game] Arrived at B" when it is done).
## A flow state whose scene is missing is reported with push_error and the visible
## error label instead of crashing.
## The game is landscape only: while the visible area is taller than it is wide the
## rotate overlay ("Rotate your phone") covers everything and the tree is paused;
## once it is landscape again the overlay hides and the tree is unpaused, unless it
## was already paused before the overlay showed.

## Emitted when a goto() has finished: the new scene is in place and the cover is gone.
signal transition_finished(state: Flow)
## Emitted when the visible or safe rect changes (window resize, rotation).
signal screen_fit_changed
## Emitted when the rotate overlay shows (true) or hides (false).
signal rotate_overlay_changed(shown: bool)

enum Flow { TITLE }

## Absolute path of this autoload, for nodes inside the tree.
const AUTOLOAD_PATH := ^"/root/Game"
const SCENE_PATHS: Dictionary[Flow, String] = {
	Flow.TITLE: "res://scenes/title.tscn",
}
## The base viewport (project.godot display/window/size): the playfield is laid out
## in it and is never cropped (aspect expand only adds room).
const BASE_SIZE := Vector2(960, 540)
## Seconds the cover takes to fade in, and again to fade out.
const FADE_TIME := 0.15

## Paths per flow state; tests swap one to check the missing-scene path.
var scene_paths: Dictionary[Flow, String] = SCENE_PATHS.duplicate()
## Tests set this to keep expected errors out of the log; they are still recorded
## and shown on the error label.
var quiet_errors := false
var reported_errors: Array[String] = []
## Every goto() started, "FROM -> TO (path) args=..." (tests read it).
var transition_log: Array[String] = []
var state := Flow.TITLE
## The args of the latest goto(); the new scene reads them in its _ready().
var flow_args: Dictionary = {}

var _transitioning := false
var _visible_rect := Rect2()
var _safe_rect := Rect2()
## True while the rotate overlay holds the tree paused (it then unpauses on hiding).
var _paused_by_rotate := false

@onready var _cover: ColorRect = $Fade/Cover
@onready var _error_label: Label = $Fade/ErrorLabel
@onready var _rotate_overlay: Control = $RotateLayer/RotateOverlay


func _ready() -> void:
	_fit_window()
	get_viewport().size_changed.connect(_update_screen_fit)
	_update_screen_fit()
	_announce_main_scene.call_deferred()


## The main scene is loaded by the engine, not by goto(); once it is in the tree,
## record and log the flow state it stands for. Tool runs (tests, the project check)
## start without a current scene and are left alone.
func _announce_main_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var found: Variant = scene_paths.find_key(scene.scene_file_path)
	if found == null:
		_report_error("The main scene '%s' is not a flow state's scene" % scene.scene_file_path)
		return
	state = found as Flow
	print("[Game] Arrived at %s (main scene)" % Flow.keys()[state])


## Desktop windows are sized in physical pixels, so on a high-density screen
## (a 2x Retina display) the project's window size would show at half size,
## and on a small screen it may not fit. Applies `fit_window_rect()`. The web
## build fills its page and a game embedded in the editor is sized by the
## editor, so both are left alone.
func _fit_window() -> void:
	var window := get_window()
	if OS.has_feature("web") or Engine.is_embedded_in_editor() or window.mode != Window.MODE_WINDOWED:
		return
	var density := DisplayServer.screen_get_scale(window.current_screen)
	var fitted := fit_window_rect(window.size, density, DisplayServer.screen_get_usable_rect(window.current_screen),
		window.get_size_with_decorations() - window.size, window.position - window.get_position_with_decorations())
	if fitted.size == window.size:
		return
	window.size = fitted.size
	window.position = fitted.position
	print("[Game] Fitted the window to a %.1fx screen: %s" % [density, fitted])


## The client rect for a window of `base` screen points on a screen of
## `density`: scaled to pixels, shrunk (keeping its aspect) until it fits the
## `usable` screen rect together with its frame (`frame_size` = framed minus
## client size, `client_offset` = client position inside the frame), and placed
## so the framed window is centred in the usable rect.
static func fit_window_rect(base: Vector2i, density: float, usable: Rect2i, frame_size: Vector2i, client_offset: Vector2i) -> Rect2i:
	var room := Vector2(usable.size - frame_size)
	var wanted := Vector2(base) * density
	wanted *= minf(1.0, minf(room.x / wanted.x, room.y / wanted.y))
	var client := Vector2i(wanted)
	var framed_position := usable.position + Vector2i(Vector2(usable.size - client - frame_size) / 2.0)
	return Rect2i(framed_position + client_offset, client)


## Fades to the scene of `new_state`, passing `args` through flow_args: the cover
## fades in (FADE_TIME), the scene changes, then the cover fades out, and
## transition_finished fires. Touches are blocked until then. Ignored (with a log
## line) while a transition is running.
func goto(new_state: Flow, args: Dictionary = {}) -> void:
	var path: String = scene_paths[new_state]
	var from_name: String = Flow.keys()[state]
	var to_name: String = Flow.keys()[new_state]
	if _transitioning:
		print("[Game] Ignored goto %s while a transition is running" % to_name)
		return
	if not ResourceLoader.exists(path):
		_report_error("Cannot go to %s: scene '%s' does not exist" % [to_name, path])
		return
	_transitioning = true
	_log_transition("%s -> %s (%s) args=%s" % [from_name, to_name, path, args])
	_error_label.hide()
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.show()
	await _fade_to(1.0)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_report_error("Failed to load scene '%s' for %s: %s" % [path, to_name, error_string(error)])
		await _fade_to(0.0)
		_end_fade()
		return
	state = new_state
	flow_args = args
	# The new scene enters the tree (and runs its _ready) at the end of this frame.
	await get_tree().scene_changed
	await _fade_to(0.0)
	_end_fade()
	print("[Game] Arrived at %s" % to_name)
	transition_finished.emit(new_state)


func is_transitioning() -> bool:
	return _transitioning


## How far the cover hides the screen: 0 clear, 1 covered (tests read it).
func cover_progress() -> float:
	return _cover.modulate.a


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", alpha, FADE_TIME)
	await tween.finished


func _end_fade() -> void:
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.hide()
	_transitioning = false


## The visible area in base units: 960x540 or larger on one axis (aspect expand).
func visible_rect() -> Rect2:
	return _visible_rect


## The part of the visible area clear of notches and rounded corners, in base units.
func safe_rect() -> Rect2:
	return _safe_rect


## True while the rotate overlay covers the game (the visible area is portrait).
func is_rotate_overlay_shown() -> bool:
	return _rotate_overlay.visible


## Converts the screen-pixel safe area to base units and clips it to `visible`.
## An empty safe area (headless, some web browsers) means the whole visible rect.
static func safe_rect_in(visible: Rect2, safe_pixels: Rect2i, window_position: Vector2i, stretch: Transform2D) -> Rect2:
	if safe_pixels.size.x <= 0 or safe_pixels.size.y <= 0:
		return visible
	var local := Rect2(Vector2(safe_pixels.position - window_position), Vector2(safe_pixels.size))
	var base := stretch.affine_inverse() * local
	var clipped := base.intersection(visible)
	return clipped if clipped.has_area() else visible


## True when a visible area of `area` needs the rotate overlay: taller than wide.
static func is_portrait(area: Vector2) -> bool:
	return area.y > area.x


func _update_screen_fit() -> void:
	var window := get_window()
	var visible := get_viewport().get_visible_rect()
	var safe := safe_rect_in(visible, DisplayServer.get_display_safe_area(), window.position, window.get_final_transform())
	if visible.is_equal_approx(_visible_rect) and safe.is_equal_approx(_safe_rect):
		return
	_visible_rect = visible
	_safe_rect = safe
	print("[Game] ScreenFit: visible %s, safe %s" % [visible, safe])
	_update_rotate_overlay()
	screen_fit_changed.emit()


## Shows the rotate overlay and pauses the tree while the visible area is portrait;
## hides it and restores the pause state when it is landscape again.
func _update_rotate_overlay() -> void:
	var portrait := is_portrait(_visible_rect.size)
	if portrait == _rotate_overlay.visible:
		return
	var tree := get_tree()
	if portrait:
		_paused_by_rotate = not tree.paused
		tree.paused = true
		_rotate_overlay.show()
		print("[Game] Rotate overlay shown (visible %s); tree paused" % _visible_rect.size)
	else:
		_rotate_overlay.hide()
		if _paused_by_rotate:
			tree.paused = false
		print("[Game] Rotate overlay hidden (visible %s); tree %s" % [_visible_rect.size, "unpaused" if _paused_by_rotate else "stays paused"])
		_paused_by_rotate = false
	rotate_overlay_changed.emit(portrait)


func _log_transition(entry: String) -> void:
	transition_log.append(entry)
	print("[Game] goto " + entry)


func _report_error(message: String) -> void:
	reported_errors.append(message)
	_error_label.text = message
	_error_label.show()
	if not quiet_errors:
		push_error("[Game] " + message)
