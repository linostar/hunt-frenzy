class_name Settings
extends Control
## The settings screen: the music and sound effects volumes (TouchSlider, 0..VOLUME_MAX,
## applied to their bus at once), their mutes and Reduce motion (toggle buttons, pressed =
## on), each showing its state in text ("Music 70", "Music: on", "Reduce motion: off").
## Every change is logged and saved at once (Game's setters), except a volume during a
## slider hold (a finger on it, or a step key held down with its repeats): that is applied
## to the bus live and saved, with one UI tap, when the hold ends (TouchSlider.released:
## the finger lifts, the keys are released, or the hold is cut short: the rotate overlay,
## the screen closing, another touch), so the final value is never lost. The toggles and
## Back tap as every button does. It follows the settings whoever changes them
## (the pause menu's mutes), through Game.audio_settings_changed and reduce_motion_changed.
## It opens two ways: as a screen from the title's Settings button (Game.goto(SETTINGS));
## Back or Escape returns to the title with its Settings button focused); or over the
## paused run (`overlay`, set by Play before adding it: a dim layer over the run, the pause
## menu's panel hidden under it, the run frozen and its sounds held and ducked; Back emits
## `closed` and Play returns the focus to the pause menu's Settings button; Escape is routed
## by Play then).
## Laid out in the safe area (explicit offsets, so it fits down to a safe height of 470);
## the keyboard reaches everything (Tab cycles, Up/Down move between rows, Left/Right step
## a focused slider), and the music slider is focused on arrival.

## Back was pressed on the overlay (Play closes it).
signal closed

const VOLUME_TEXT := "%s %d"
const MUSIC_TOGGLE_TEXT := "Music: %s"
const SFX_TOGGLE_TEXT := "SFX: %s"
const REDUCE_MOTION_TEXT := "Reduce motion: %s"
## The overlay's dim layer over the paused run (the screen's own background is opaque).
const OVERLAY_DIM := Color(0.067, 0.059, 0.094, 0.85)
## Game.flow_args "focus" the title reads to focus its Settings button again.
const TITLE_FOCUS := "settings"

## True when it is opened over the paused run (set before it enters the tree).
var overlay := false

var _game: GameState

@onready var _background: ColorRect = $Background
@onready var _safe: Control = $Safe
@onready var _music_label: Label = $Safe/MusicLabel
@onready var _music_slider: TouchSlider = $Safe/MusicSlider
@onready var _music_toggle: Button = $Safe/MusicToggle
@onready var _sfx_label: Label = $Safe/SfxLabel
@onready var _sfx_slider: TouchSlider = $Safe/SfxSlider
@onready var _sfx_toggle: Button = $Safe/SfxToggle
@onready var _reduce_motion_toggle: Button = $Safe/ReduceMotionToggle
@onready var _back_button: Button = $Safe/BackButton
@onready var _cancel_key: CancelKey = $CancelKey


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_game.audio_settings_changed.connect(_show)
	_game.reduce_motion_changed.connect(_show.unbind(1))
	_music_slider.max_value = GameState.VOLUME_MAX
	_sfx_slider.max_value = GameState.VOLUME_MAX
	_music_slider.value_changed.connect(_on_volume_changed.bind(_music_slider))
	_sfx_slider.value_changed.connect(_on_volume_changed.bind(_sfx_slider))
	_music_slider.released.connect(_on_volume_released.bind(_music_slider))
	_sfx_slider.released.connect(_on_volume_released.bind(_sfx_slider))
	# The rotate overlay disables GUI input: a finger or key down then never reports its end.
	_game.rotate_overlay_changed.connect(_on_rotate_overlay_changed)
	_music_toggle.toggled.connect(_on_music_toggled)
	_sfx_toggle.toggled.connect(_on_sfx_toggled)
	_reduce_motion_toggle.toggled.connect(_on_reduce_motion_toggled)
	_back_button.pressed.connect(_on_back_pressed)
	if overlay:
		_background.color = OVERLAY_DIM
		# Over the run, Play's own CancelKey closes it (Escape must not also resume the run).
		_cancel_key.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_cancel_key.triggered.connect(_on_back_pressed)
	_show()
	_fit()
	_music_slider.grab_focus(true)
	print("[Settings] Opened %s: music %d%s, sfx %d%s, reduce motion %s" % [
		"over the paused run" if overlay else "from the title", _game.music_volume, " muted" if _game.music_muted else "",
		_game.sfx_volume, " muted" if _game.sfx_muted else "", "on" if _game.reduce_motion else "off"])


## The music slider (tests and the smoke test drive it).
func music_slider() -> TouchSlider:
	return _music_slider


## Shows every setting as it is now (sliders, their labels, the toggles), without
## re-sending a change.
func _show() -> void:
	_music_slider.set_value_no_signal(_game.music_volume)
	_sfx_slider.set_value_no_signal(_game.sfx_volume)
	_music_label.text = VOLUME_TEXT % ["Music", _game.music_volume]
	_sfx_label.text = VOLUME_TEXT % ["SFX", _game.sfx_volume]
	_music_toggle.set_pressed_no_signal(not _game.music_muted)
	_music_toggle.text = MUSIC_TOGGLE_TEXT % ("on" if not _game.music_muted else "off")
	_sfx_toggle.set_pressed_no_signal(not _game.sfx_muted)
	_sfx_toggle.text = SFX_TOGGLE_TEXT % ("on" if not _game.sfx_muted else "off")
	_reduce_motion_toggle.set_pressed_no_signal(_game.reduce_motion)
	_reduce_motion_toggle.text = REDUCE_MOTION_TEXT % ("on" if _game.reduce_motion else "off")


## A slider moved (a key step, a touch or a drag): the bus follows at once; during a hold
## (always, for touches and keys) it is saved when the hold ends (_on_volume_released).
func _on_volume_changed(value: float, slider: TouchSlider) -> void:
	var held := slider.is_held()
	var volume := int(value)
	if slider == _music_slider:
		if volume == _game.music_volume:
			return
		print("[Settings] Music slider moved to %d%s" % [volume, " (held)" if held else ""])
		_game.set_music_volume(volume, not held)
	else:
		if volume == _game.sfx_volume:
			return
		print("[Settings] SFX slider moved to %d%s" % [volume, " (held)" if held else ""])
		_game.set_sfx_volume(volume, not held)
	if not held:
		_game.play_sfx(&"ui_tap")


## A slider's hold ended (`cause`): its volume is saved and the UI tap plays, once per hold.
func _on_volume_released(value: float, cause: String, slider: TouchSlider) -> void:
	print("[Settings] %s slider released at %d (%s); saving" % ["Music" if slider == _music_slider else "SFX", int(value), cause])
	_game.play_sfx(&"ui_tap")
	_game.save_game()


## The rotate overlay showed: any slider hold ends now (its end would never arrive).
func _on_rotate_overlay_changed(shown: bool) -> void:
	if shown:
		_music_slider.cancel_hold("rotate overlay")
		_sfx_slider.cancel_hold("rotate overlay")


func _on_music_toggled(on: bool) -> void:
	if on == not _game.music_muted:
		return
	print("[Settings] Music toggle pressed: music %s" % ("on" if on else "off"))
	_game.set_music_muted(not on)


func _on_sfx_toggled(on: bool) -> void:
	if on == not _game.sfx_muted:
		return
	print("[Settings] SFX toggle pressed: sound effects %s" % ("on" if on else "off"))
	_game.set_sfx_muted(not on)


func _on_reduce_motion_toggled(on: bool) -> void:
	if on == _game.reduce_motion:
		return
	print("[Settings] Reduce motion toggle pressed: %s" % ("on" if on else "off"))
	_game.set_reduce_motion(on)


## Back (or Escape on the screen): the overlay closes (Play takes it from there), the
## screen returns to the title with its Settings button focused.
func _on_back_pressed() -> void:
	if overlay:
		print("[Settings] Back pressed; closing over the paused run")
		closed.emit()
		return
	print("[Settings] Back pressed; returning to the title")
	_game.goto(GameState.Flow.TITLE, {"focus": TITLE_FOCUS})


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Anchors settle at the end of the frame; log the final rects (base units) for the
	# smoke test, which taps them.
	_log_layout.call_deferred()


func _log_layout() -> void:
	if not is_inside_tree():
		return
	print("[Settings] Music slider at %s" % _music_slider.get_global_rect())
	print("[Settings] Back button at %s" % _back_button.get_global_rect())
