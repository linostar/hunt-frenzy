extends Area2D
## Violation: DisplayServer mouse reads and the CollisionObject mouse callbacks are
## mouse input too (emulate_touch_from_mouse does not turn them into touches).


func _ready() -> void:
	mouse_shape_entered.connect(_on_shape_entered)


func _mouse_enter() -> void:
	print(DisplayServer.mouse_get_position(), DisplayServer.mouse_get_button_state())


func _on_shape_entered(shape: int) -> void:
	print(shape)
