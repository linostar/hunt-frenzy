class_name CancelKey
extends Node
## Emits `triggered` when ui_cancel (Escape) is pressed and nothing else used it. Raw
## input belongs in scripts/ui/; the play scene opens its pause menu on it. Pausable, so
## it is silent while the tree is paused.

signal triggered


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		triggered.emit()
