class_name CancelKey
extends Node
## Emits `triggered` when ui_cancel (Escape) is pressed and nothing else used it, or when
## Android's Back button is pressed (application/config/quit_on_go_back is off, so Back
## arrives as NOTIFICATION_WM_GO_BACK_REQUEST instead of quitting). Raw input belongs in
## scripts/ui/; the play scene opens its pause menu on it, or resumes when the menu is open,
## so its node processes while the tree is paused (play.tscn sets PROCESS_MODE_ALWAYS). Under
## the rotate overlay the viewport takes no input at all, Back included; a disabled CancelKey
## (the settings screen over the paused run) ignores both.

signal triggered


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		triggered.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and can_process() and not get_viewport().gui_disable_input:
		triggered.emit()
