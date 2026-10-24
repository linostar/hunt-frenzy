extends Control
## Allowed: scripts/ui/ may handle raw touch and key input (focus navigation, the
## finger that pressed), without filtering on touch index 0.

var _finger := -1


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null and touch.pressed:
		_finger = touch.index
		accept_event()
	elif event is InputEventKey or event.is_action_pressed("ui_accept"):
		accept_event()
