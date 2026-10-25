class_name ShotInput
extends Control
## The playfield's shot surface (below the HUD bar). Every pressed touch, whatever its
## index (a web build's index is the browser's Touch.identifier, which iOS Safari makes
## large and never 0), is one shot at its position in base units: two fingers make two
## shots. Releases and drags are ignored. Touches on Controls above it (the pause button,
## the pause menu) never reach it, and neither does anything while the tree is paused.

## A pressed touch at `at` (canvas base units).
signal shot(at: Vector2)


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch == null or not touch.pressed:
		return
	accept_event()
	shot.emit(get_global_transform() * touch.position)
