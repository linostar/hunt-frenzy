class_name StageFader
extends Node
## Play/Stage: the run's backdrop and weather (World/Backdrop, World/Weather). A level shows its
## chapter's stage for the whole run; a mode shows each wave's (ModeSpec.stage_for: Endless
## walks dawn, noon, sunset, night; Time Attack stays on noon). The run's first backdrop shows
## at once; a new one cross-fades in over Play.TUNING.backdrop_fade_time during the wave's
## lead-in, without pausing or delaying anything, the rival's light following it. The weather
## switches at once (the old one's particles drift out); it is drawn behind the birds and
## never touches their flight. Play._fit lays both out through fit.

const BACKDROP_SCENE := preload("res://scenes/backdrop.tscn")

## The backdrop fading in over _backdrop (null when none is), and its tween.
var _next_backdrop: Backdrop
var _backdrop_tween: Tween
## The area the backdrops and the weather cover (World coordinates), from the last fit.
var _cover := Rect2()

@onready var _play := get_parent() as Play
@onready var _world: Node2D = $"../World"
@onready var _backdrop: Backdrop = $"../World/Backdrop"
@onready var _weather: Weather = $"../World/Weather"


## The backdrop shown, or fading in ("" before the run starts).
func backdrop_id() -> String:
	return _next_backdrop.id if _next_backdrop != null else _backdrop.id


## True while a new backdrop fades in over the old one.
func is_fading() -> bool:
	return _next_backdrop != null


func weather() -> Weather:
	return _weather


## Shows backdrop `to_backdrop` with weather `to_weather` from wave `wave_index` on: at once
## for the run's first wave, else (a new backdrop) cross-fading in. Nothing changes when both
## are already showing. Logged.
func show_stage(to_backdrop: String, to_weather: String, wave_index: int) -> void:
	var from := backdrop_id()
	if to_backdrop == from and to_weather == _weather.id:
		return
	if _weather.id != to_weather:
		_weather.set_weather(to_weather)
	if to_backdrop == from:
		print("[Play] Weather %s on backdrop %s from wave %d" % [to_weather, to_backdrop, wave_index])
		return
	if from == "":
		if not _backdrop.show_backdrop(to_backdrop):
			print("[Play] Backdrop %s could not be shown (reported); weather %s from wave %d" % [to_backdrop, to_weather, wave_index])
			return
		_backdrop.fit(_cover, Layout.GRASS_Y - Layout.GRASS_TIP)
		print("[Play] Backdrop %s, weather %s from wave %d" % [to_backdrop, to_weather, wave_index])
		_play.rival.light(to_backdrop)
		return
	if _next_backdrop != null:
		_finish_fade()
	var next := BACKDROP_SCENE.instantiate() as Backdrop
	_world.add_child(next)
	_world.move_child(next, _backdrop.get_index() + 1)
	if not next.show_backdrop(to_backdrop):
		next.free()
		return
	_next_backdrop = next
	next.modulate.a = 0.0
	next.fit(_cover, Layout.GRASS_Y - Layout.GRASS_TIP)
	var fade_time := Play.TUNING.backdrop_fade_time
	_backdrop_tween = next.create_tween()
	_backdrop_tween.tween_property(next, "modulate:a", 1.0, fade_time)
	# The rival's light follows the backdrop fading in.
	_play.rival.fade_light(_backdrop_tween, to_backdrop, fade_time)
	_backdrop_tween.tween_callback(_finish_fade)
	print("[Play] Backdrop %s -> %s, weather %s, cross-fading over %.2f s from wave %d" % [from, to_backdrop, to_weather, fade_time, wave_index])


## Lays the backdrops (the one shown and one fading in) and the weather over `cover` (World
## coordinates), the grass from its tips down.
func fit(cover: Rect2) -> void:
	_cover = cover
	for backdrop: Backdrop in [_backdrop, _next_backdrop]:
		if backdrop != null:
			backdrop.fit(cover, Layout.GRASS_Y - Layout.GRASS_TIP)
	_weather.fit(cover)


## The faded-in backdrop replaces the old one.
func _finish_fade() -> void:
	if _backdrop_tween != null:
		_backdrop_tween.kill()
		_backdrop_tween = null
	_next_backdrop.modulate.a = 1.0
	_play.rival.light(_next_backdrop.id)
	_backdrop.queue_free()
	_backdrop = _next_backdrop
	_next_backdrop = null
