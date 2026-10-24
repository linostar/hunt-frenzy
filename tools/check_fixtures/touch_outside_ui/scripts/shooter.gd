extends Node
## Violation: game code outside scripts/ui/ reads touches itself.


func is_shot(event: InputEvent) -> bool:
	return event is InputEventScreenTouch and event.is_pressed()
