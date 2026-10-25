class_name CancelKey
extends Node
## Emits `triggered` when ui_cancel (Escape) is pressed and nothing else used it. Raw
## input belongs in scripts/ui/; the play scene opens its pause menu on it, or resumes
## when the menu is open, so its node processes while the tree is paused (play.tscn sets
## PROCESS_MODE_ALWAYS). Under the rotate overlay the viewport takes no input at all.

signal triggered


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		triggered.emit()
