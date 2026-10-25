extends Control
## A custom touch control (mouse_filter PASS still receives _gui_input).


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		accept_event()
