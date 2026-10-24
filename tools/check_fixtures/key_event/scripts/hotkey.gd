extends Node
## Violation: game code outside scripts/ui/ reads a key event.


func is_hotkey(event: InputEvent) -> bool:
	return event is InputEventKey
