class_name Crosshair
extends Node
## Play/Crosshair: the mouse pointer of the run, the crosshair while the run is live and the
## default arrow otherwise (paused, the run over, the rotate overlay, the scene left). The one
## place the pointer is set.

## Emitted on every pointer change: `shown` ("crosshair" or "arrow (<why>)") and the arguments
## it passed to Input.set_custom_mouse_cursor (a null texture: the default arrow).
signal changed(shown_as: String, texture: Texture2D, shape: Input.CursorShape, hotspot: Vector2)

## The pointer while the run is live (64x64 at most; its hotspot is its centre).
const TEXTURE := preload("res://art/crosshair.svg")

## True while the pointer is the crosshair.
var shown := false

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState


## Leaving the tree puts the arrow back, whatever ends the scene.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		set_shown(false, "left the play scene")


## Makes the pointer the crosshair (`on`, the run is live) or the default arrow again (`why`);
## while the rotate overlay is up it is always the arrow (the run is paused under it, whichever
## came first). A change is logged and emitted (changed), a repeat does nothing.
func set_shown(on: bool, why := "") -> void:
	if on and _game.screen.is_rotate_overlay_shown():
		on = false
		why = "rotate overlay"
	if on == shown:
		return
	shown = on
	var texture: Texture2D = TEXTURE if on else null
	var hotspot := TEXTURE.get_size() / 2.0 if on else Vector2.ZERO
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
	var shown_as := "crosshair" if on else "arrow (%s)" % why
	print("[Play] Cursor: %s" % shown_as)
	changed.emit(shown_as, texture, Input.CURSOR_ARROW, hotspot)
