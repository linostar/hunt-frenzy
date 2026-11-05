class_name HudController
extends Node
## Play/HudController: the HUD bar (Hud/Bar, a CanvasLayer, so a shake never moves it) at the
## top of the safe area. Hud/Bar/Stats is a row of chips (PanelContainers in the theme's HudChip
## style, each with an accessibility_name naming its stat) left of the pause button: Score (a
## target icon and the score), Wave (a flag and "n/N" in a level, "n" in a mode), Time (a clock
## and the seconds left, timed modes only), Shells (one shell icon per shell up to
## SHELL_ICONS_MAX, else one icon and "xN"), the "Out of shells!" cue on its own plate while the
## empty cue shows, and Escaped (a flying bird and "E/limit", "E" without a limit) pushed to the
## right end. Play pushes the values (show_stats); only they change.

const SHELL_TEXTURE := preload("res://art/shell.svg")
const EMPTY_CUE_TIME := 0.6
const SHELL_ICON_SIZE := Vector2(12, 28)
## The HUD shows a pool of up to this many shells as one icon per shell (hidden as used);
## a bigger pool (Endless reaches 72) shows one icon and the shells left ("x36"), so the
## bar never overflows whatever the pool.
const SHELL_ICONS_MAX := 10
const EMPTY_TINT := Color(1.0, 0.451, 0.4)

var _empty_tween: Tween

@onready var _bar: Control = $"../Hud/Bar"
@onready var _score_label: Label = $"../Hud/Bar/Stats/Score/Row/Value"
@onready var _wave_label: Label = $"../Hud/Bar/Stats/Wave/Row/Value"
@onready var _shells: HBoxContainer = $"../Hud/Bar/Stats/Shells/Icons"
@onready var _shell_count: Label = $"../Hud/Bar/Stats/Shells/Icons/Count"
@onready var _empty_label: Label = $"../Hud/Bar/Stats/Empty"
@onready var _time_chip: Control = $"../Hud/Bar/Stats/Time"
@onready var _time_label: Label = $"../Hud/Bar/Stats/Time/Row/Value"
@onready var _escaped_label: Label = $"../Hud/Bar/Stats/Escaped/Row/Value"


## Lays the bar along the top of the `safe` rect, `height` tall.
func fit(safe: Rect2, height: float) -> void:
	_bar.position = safe.position
	_bar.size = Vector2(safe.size.x, height)


## Shows the Time chip (timed runs only).
func show_timer(on: bool) -> void:
	_time_chip.visible = on


## Shows the seconds a timed run has left, rounded up.
func show_time_left(seconds: float) -> void:
	_time_label.text = "%d" % ceili(seconds)


## Shows a fresh pool of `count` shells: one icon per shell up to SHELL_ICONS_MAX, else one
## icon and the count.
func show_pool(count: int) -> void:
	for icon in _shells.get_children():
		if icon != _shell_count:
			icon.free()
	for i in count if count <= SHELL_ICONS_MAX else 1:
		var icon := TextureRect.new()
		icon.texture = SHELL_TEXTURE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = SHELL_ICON_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shells.add_child(icon)
		_shells.move_child(icon, _shell_count.get_index())
	_shell_count.visible = count > SHELL_ICONS_MAX


## Shows the run's values: the score, the wave ("n/N" or "n"), the shells left and the birds
## lost ("E/limit" or "E").
func show_stats(score: int, wave_text: String, shells: int, escapes: String) -> void:
	_score_label.text = "%d" % score
	_wave_label.text = wave_text
	if _shell_count.visible:
		_shell_count.text = "x%d" % shells
	else:
		for icon in _shells.get_children():
			if icon != _shell_count:
				(icon as CanvasItem).visible = icon.get_index() < shells
	_escaped_label.text = escapes


## Flashes the empty cue ("Out of shells!", the shells tinted) for EMPTY_CUE_TIME.
func show_empty_cue() -> void:
	_empty_label.show()
	_shells.modulate = EMPTY_TINT
	if _empty_tween != null:
		_empty_tween.kill()
	_empty_tween = create_tween()
	_empty_tween.tween_interval(EMPTY_CUE_TIME)
	_empty_tween.tween_callback(_hide_empty_cue)


func is_empty_cue_shown() -> bool:
	return _empty_label.visible


func _hide_empty_cue() -> void:
	_empty_label.hide()
	_shells.modulate = Color.WHITE
