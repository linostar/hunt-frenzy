class_name TouchSlider
extends HSlider
## A horizontal slider that also follows touches and steps by KEY_STEP on the keyboard.
## Godot's HSlider reads only mouse events, and phones send touches (emulate_mouse_from_touch
## is off), so a pressed touch on it (whatever its index: a web build's index is the
## browser's Touch.identifier) sets the value under the finger and a drag of that finger
## moves it, until the finger lifts. ui_left / ui_right (held keys repeat) step it by
## KEY_STEP instead of HSlider's own step of 1, which would take 70 presses to silence a
## volume of 70. A finger on it or a held step key is a "hold": is_held() says so, and
## `released` fires once when the hold ends, with what ended it, so a screen applies the
## value live and saves (and sounds) once per hold. A hold whose end never arrives still
## ends: a touch by another finger takes over (the lost lift ends the old hold first),
## the slider leaving the tree or being hidden ends it, the focus moving away ends a key
## hold, and cancel_hold() ends it for causes this node cannot see (the rotate overlay
## disabling GUI input, so the lift is never delivered). While it has keyboard focus it
## draws the theme's Button focus ring around itself (HSlider has no focus style of its own).

## A hold ended (`cause`: "finger lifted", "keys released" or why it was cut short),
## leaving `value`.
signal released(value: float, cause: String)

## No finger is on the slider.
const NO_FINGER := -1
## How far one key press (or each repeat of a held key) moves the value.
const KEY_STEP := 5.0

var _finger := NO_FINGER
var _keys_down := false


func _gui_input(event: InputEvent) -> void:
	var touch := event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			if _finger != NO_FINGER:
				# A press while a finger is down: that finger's lift was lost (or this is a
				# second finger); its hold ends here and the new press takes over.
				_end_hold("a new touch took over")
			_finger = touch.index
			_follow(touch.position.x)
		elif not touch.pressed and touch.index == _finger:
			_finger = NO_FINGER
			released.emit(value, "finger lifted")
		accept_event()
		return
	var drag := event as InputEventScreenDrag
	if drag != null and drag.index == _finger:
		_follow(drag.position.x)
		accept_event()
		return
	for action: StringName in [&"ui_left", &"ui_right"]:
		if event.is_action_pressed(action, true):
			_keys_down = true
			value += KEY_STEP if action == &"ui_right" else -KEY_STEP
			accept_event()
			return
		if event.is_action_released(action):
			accept_event()
			if _keys_down:
				_keys_down = false
				released.emit(value, "keys released")
			return


## True while a finger is on the slider or a step key is held.
func is_held() -> bool:
	return _finger != NO_FINGER or _keys_down


## Ends the current hold (if any) for `cause`, emitting `released`: for an end the slider
## cannot see itself (the rotate overlay disables GUI input, so the lift never arrives).
func cancel_hold(cause: String) -> void:
	if is_held():
		_end_hold(cause)


func _end_hold(cause: String) -> void:
	_finger = NO_FINGER
	_keys_down = false
	released.emit(value, cause)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_FOCUS_ENTER:
			queue_redraw()
		NOTIFICATION_FOCUS_EXIT:
			queue_redraw()
			if _keys_down:
				_end_hold("the focus moved away")
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				cancel_hold("hidden")
		NOTIFICATION_EXIT_TREE:
			cancel_hold("left the screen")


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
