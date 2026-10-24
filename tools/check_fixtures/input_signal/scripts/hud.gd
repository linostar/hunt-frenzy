extends Control
## Violation: handles raw input outside scripts/ui/ by connecting gui_input in code.


func _ready() -> void:
	gui_input.connect(_on_area)


func _on_area(_event: InputEvent) -> void:
	accept_event()
