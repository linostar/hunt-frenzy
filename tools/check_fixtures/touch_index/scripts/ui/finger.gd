extends Node
## Violation: filters on touch index 0, which iOS Safari never sends.


func is_first_finger(touch: InputEventScreenTouch) -> bool:
	return touch.index == 0


func is_extra_finger(touch: InputEventScreenTouch) -> bool:
	return 0 != touch.index
