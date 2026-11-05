class_name HitStop
extends Node
## Play/HitStop: stops the world for a moment after a kill (Game.tuning.hit_stop_time,
## hit_stop_heavy_time for an armored or the golden bird): every bird holds still that long
## (Bird.hold) and Play's _process runs only what run() leaves of each frame, so the birds, the
## rival and every clock lose exactly the stop's time. It shifts every later event by the same
## amount and never changes what happens; the HUD, the pop-ups, the feathers and input keep
## running. While a stop runs, another kill starts none. Logged.

## Emitted when a kill starts a stop of `seconds`.
signal started(seconds: float)

## Seconds of stop still to run (0: none).
var _left := 0.0

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _play := get_parent() as Play
@onready var _birds: Node2D = $"../World/Birds"


## Starts a stop after `target`'s kill (`heavy`: the longer one), unless one is running. Logged.
func start(target: Bird, heavy: bool) -> void:
	var time := _game.tuning.hit_stop_heavy_time if heavy else _game.tuning.hit_stop_time
	if _left > 0.0:
		print("[Play] Hit stop for %s skipped: one is running (%.3f s left)" % [Play.bird_name(target), _left])
		return
	_left = time
	started.emit(time)
	for child in _birds.get_children():
		(child as Bird).hold(time)
	print("[Play] Hit stop %.2f s on the kill of %s (%s%s)" % [time, Play.bird_name(target), _play.wave_note(), _play.clock_note()])


## The part of `frame_delta` the world runs this frame: all of it without a stop, -1 while the
## stop holds the whole frame, else what is left once the stop ends inside it (Bird.hold does
## the same).
func run(frame_delta: float) -> float:
	if _left <= 0.0:
		return frame_delta
	_left -= frame_delta
	if _left >= 0.0:
		return -1.0
	var rest := -_left
	_left = 0.0
	return rest


## Seconds of stop still to run (0 when none runs).
func left() -> float:
	return _left
