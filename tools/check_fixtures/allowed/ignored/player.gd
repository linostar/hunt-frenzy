extends Node
## Not checked: a directory with a .gdignore is not part of the project, so this
## handler (mouse input outside scripts/ui/, an index-0 filter) is no violation.


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventScreenTouch and event.index == 0):
		get_viewport().set_input_as_handled()
