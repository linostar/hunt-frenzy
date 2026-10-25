extends Node2D
## Violation: mouse input is forbidden even in scripts/ui/ (the mouse arrives as touch).


func is_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton


func aim() -> Vector2:
	return get_global_mouse_position()
