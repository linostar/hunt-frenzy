class_name TouchSlider
extends HSlider
## A horizontal slider that also follows touches: Godot's HSlider reads only mouse events,
## and phones send touches (emulate_mouse_from_touch is off), so a pressed touch on it
## (whatever its index: a web build's index is the browser's Touch.identifier) sets the
## value under the finger and a drag of that finger moves it, until the finger lifts.
## `held` says whether a finger is on it; `released` fires when it lifts, so a screen can
## save once per drag. Keyboard steps (ui_left / ui_right while focused) are HSlider's own.
## While it has keyboard focus it draws the theme's Button focus ring around itself, so
## the focus is as visible as on every button (HSlider has no focus style of its own).

## The finger lifted after setting the value (`value` is the value it left).
signal released(value: float)

## No finger is on the slider.
const NO_FINGER := -1

var _finger := NO_FINGER


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed and _finger == NO_FINGER:
			_finger = touch.index
			_follow(touch.position.x)
		elif not touch.pressed and touch.index == _finger:
			_finger = NO_FINGER
			released.emit(value)
		accept_event()
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		_follow(drag.position.x)
		accept_event()


## True while a finger is on the slider.
func is_held() -> bool:
	return _finger != NO_FINGER


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _draw() -> void:
	if has_focus(true):
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))


## Sets the value at local x `x` the way HSlider maps its own clicks (the grabber's centre
## travels from half its width in from the left edge to as far in from the right), so on a
## desktop, where the mouse also arrives as the touch it is emulated as, both agree.
func _follow(x: float) -> void:
	var grabber := float(get_theme_icon(&"grabber").get_width())
	var travel := size.x - grabber
	if travel <= 0.0:
		return
	value = min_value + clampf((x - grabber / 2.0) / travel, 0.0, 1.0) * (max_value - min_value)
