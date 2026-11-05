class_name ScreenFit
extends Node
## Game/Screen: the visible and safe-area rects in base units, the desktop window fit and the
## rotate overlay. The game is landscape only: while the visible area is taller than it is
## wide the rotate overlay ("Rotate your phone") covers everything and the tree is paused;
## once it is landscape again the overlay hides and the tree is unpaused, unless it was
## already paused before the overlay showed. While it shows, GUI input (touches and keys) is
## disabled.

## Emitted when the visible or safe rect changes (window resize, rotation).
signal screen_fit_changed
## Emitted when the rotate overlay shows (true) or hides (false).
signal rotate_overlay_changed(shown: bool)

## The base viewport (project.godot display/window/size): the playfield is laid out
## in it and is never cropped (aspect expand only adds room).
const BASE_SIZE := Vector2(960, 540)

## Tests set this (base units) to stand in for a notched screen's safe area; it applies
## from the next ScreenFit update. An empty rect means the display's own safe area.
var safe_area_override := Rect2()

var _visible_rect := Rect2()
var _safe_rect := Rect2()
## True while the rotate overlay holds the tree paused (it then unpauses on hiding).
var _paused_by_rotate := false

@onready var _game := get_parent() as GameState
@onready var _rotate_overlay: Control = $"../RotateLayer/RotateOverlay"


## Fits the desktop window, then follows the viewport's size from now on (GameState._ready).
func start() -> void:
	_fit_window()
	get_viewport().size_changed.connect(_update_screen_fit)
	_update_screen_fit()


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
	var safe := safe_area_override if safe_area_override.has_area() else safe_rect_in(visible, DisplayServer.get_display_safe_area(), window.position, window.get_final_transform())
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
		# The overlay stops touches; GUI input is disabled too, so keys cannot press a
		# focused button (an ALWAYS-processing pause menu) hidden behind it.
		get_viewport().gui_disable_input = true
		print("[Game] Rotate overlay shown (visible %s); tree paused" % _visible_rect.size)
	else:
		_rotate_overlay.hide()
		get_viewport().gui_disable_input = false
		if _paused_by_rotate:
			tree.paused = false
		print("[Game] Rotate overlay hidden (visible %s); tree %s" % [_visible_rect.size, "unpaused" if _paused_by_rotate else "stays paused"])
		_paused_by_rotate = false
	rotate_overlay_changed.emit(portrait)
	# After the signal: a run that re-pauses on it keeps its sounds held.
	_game.audio.sync_audio_pause()
