extends Node
## Violation: an unused variable, a warning that project.godot raises to an error.


func total() -> int:
	var unused := 1
	return 2
