class_name ScreenShake
extends Node
## Play/Shaker: shakes the World (never the HUD) for an event (SHAKES: amplitude and time per
## cause, decaying to exactly no offset). A weaker shake never cuts a stronger one short; with
## reduce motion on nothing shakes. Play drives it from its _process (update) and places the
## World through it (set_origin), so the offset is always from where _fit put it.

## Screen shake per event: [amplitude in base units, seconds]. The world's offset decays as
## (1 - t / time)^2 and is exactly zero once the time is over.
const SHAKES: Dictionary[String, Array] = {
	"armored kill": [6.0, 0.25], "golden kill": [8.0, 0.3], "decoy hit": [10.0, 0.3], "steal": [7.0, 0.3], "lost wave": [12.0, 0.4],
}
## How fast the shake swings (per second).
const SHAKE_HZ := 18.0
## The backdrop and weather reach this far past the visible area, so a shake never bares an edge.
const SHAKE_MARGIN := 12.0

## The shake running: its cause, amplitude, time and how far into it (none: time 0).
var _cause := ""
var _amplitude := 0.0
var _time := 0.0
var _age := 0.0
## Where Play._fit puts the World; the shake offsets it from here.
var _origin := Vector2.ZERO

@onready var _world: Node2D = $"../World"


## Places the World at `origin` (its resting place, Play._fit).
func set_origin(origin: Vector2) -> void:
	_origin = origin
	_world.position = origin


## Shakes the world for `cause` (a SHAKES key): its amplitude and time, from now. A weaker
## shake never cuts a stronger one short. With reduce motion on nothing shakes. Logged.
func shake(cause: String) -> void:
	if (get_node(GameState.AUTOLOAD_PATH) as GameState).save.reduce_motion:
		print("[Play] Shake (%s) skipped: reduce motion" % cause)
		return
	var amplitude: float = SHAKES[cause][0]
	var time: float = SHAKES[cause][1]
	if shake_strength() > amplitude:
		print("[Play] Shake (%s) skipped: a stronger one (%s) is running" % [cause, _cause])
		return
	_cause = cause
	_amplitude = amplitude
	_time = time
	_age = 0.0
	print("[Play] Shake (%s): %.0f units over %.2f s" % [cause, amplitude, time])


## The shake's current amplitude (its envelope; 0 when none runs).
func shake_strength() -> float:
	if _time <= 0.0:
		return 0.0
	return _amplitude * pow(1.0 - _age / _time, 2.0)


## The world's shake offset now (zero when none runs).
func shake_offset() -> Vector2:
	return _world.position - _origin


## Moves the world by the shake's offset (bounded by its envelope), or back exactly to its
## place once it is over.
func update(delta: float) -> void:
	if _time <= 0.0:
		return
	_age += delta
	if _age >= _time:
		stop()
		return
	var swing := TAU * SHAKE_HZ * _age
	_world.position = _origin + Vector2(sin(swing), sin(swing * 1.37 + 1.1)).limit_length(1.0) * shake_strength()


## Ends any shake: the world is back exactly at its place.
func stop() -> void:
	_time = 0.0
	_age = 0.0
	_cause = ""
	_world.position = _origin
