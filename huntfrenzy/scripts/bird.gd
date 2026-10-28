class_name Bird
extends Node2D
## One bird of a run, driven by Flight: while flying its transform is
## Flight.transform_at(spec, seed, age, ...) and it flaps between its two fly frames;
## once it has escaped (Flight.has_escaped) it emits `escaped` and frees itself. A hit
## that leaves it hit points (an armored bird's first) only switches it to its damaged
## flap frames; the killing hit stops it on its hit frame for HIT_HOLD seconds, then it
## dives head-first (its dive frame: wings folded, pitching nose-down over FALL_TURN_TIME)
## off the bottom of the screen, emits `gone` and frees itself. A bird launched
## from a point (a splitter's gosling) flies Flight's launched path from there. While the
## rival aims at it (set_cue, driven by Play from Rival.steal_state) it shows the Reticle
## over itself; steal() drops it like a kill (hit frame, then the fall), marked stolen.
## While flying, the run's first bird (TRACKED_NUMBER)
## logs its position and velocity (canvas base units) every TRACK_INTERVAL seconds, with
## where its flight will take it TRACK_AHEAD_STEP, 2 x TRACK_AHEAD_STEP, ... seconds later
## (TRACK_AHEAD_STEPS points); the smoke test aims at it from these lines. Other birds are
## replayable from their logged spawn seeds.
## A crossing bird (setup_crossing: the title's geese) flies Flight's level crossing path
## over a band instead, and emits `escaped` once it is past the band's far side; it never
## logs its track. hold() (Play's hit stop) freezes a bird for a few hundredths of a second:
## it neither ages, moves, flaps nor falls until the time is over, and the frame that ends
## the hold runs only for what is left of that frame, so the bird loses exactly the hold's
## time, as Play's clocks do.
## Configure with setup() or setup_crossing() before adding it to the tree.

signal escaped(bird: Bird)
signal gone(bird: Bird)

enum State { FLYING, HIT, FALLING }

const FLAP_TIME := 0.15
const HIT_HOLD := 0.25
## Fall acceleration after a hit, base units per second squared.
const GRAVITY := 1400.0
## Seconds a falling bird takes to pitch from upright to head straight down.
const FALL_TURN_TIME := 0.12
const TRACK_INTERVAL := 0.25
const TRACK_AHEAD_STEP := 0.1
const TRACK_AHEAD_STEPS := 20
const TRACKED_NUMBER := 1
## The aim reticle's drawn size in base units.
const RETICLE_SIZE := 56.0

var spec: BirdSpec
## The bird's number in its run (1 is the first bird spawned).
var number := 0
var bird_seed := 0
var speed_scale := 1.0
var field := Rect2()
## Seconds since it spawned (only counted while flying).
var age := 0.0
## The age it was told to flee at (INF: it flees at its spec's flee_time).
var flee_at := INF
## The launch point and heading of a launched bird (Flight.NOT_LAUNCHED: it rises from
## below the grass).
var launch_from := Flight.NOT_LAUNCHED
var launch_heading := Vector2.ZERO
## Hits taken so far (a kill at spec.hp).
var hits_taken := 0
var state := State.FLYING
## The age the rival's aim cue on it started at (Rival.NOT_AIMING: he is not aiming at it).
var cue_age := Rival.NOT_AIMING
## True once the rival has shot it.
var stolen := false
## The index of the wave it belongs to (Play sets it; a split child takes the wave it was
## launched in).
var wave_index := 0
## The band a crossing bird flies across (an empty rect: the play path).
var crossing := Rect2()

var _textures: Dictionary[String, Texture2D] = {}
var _hold := 0.0
var _fall_speed := 0.0
var _fall_time := 0.0
## 1 when it was facing right as it was hit, -1 facing left.
var _facing := 1.0
var _track_clock := 0.0
## Seconds of hold (hit stop) still to sit out.
var _held_for := 0.0

@onready var _sprite: Sprite2D = $Sprite
@onready var _reticle: Sprite2D = $Reticle


## Sets the bird up to fly from age 0; `fleeing` makes it flee at once (no shells left);
## `from` and `heading` launch it from a point (goslings).
func setup(bird_spec: BirdSpec, bird_number: int, flight_seed: int, scale_of_speed: float, flight_field: Rect2, fleeing: bool, from := Flight.NOT_LAUNCHED, heading := Vector2.ZERO) -> void:
	spec = bird_spec
	number = bird_number
	bird_seed = flight_seed
	speed_scale = scale_of_speed
	field = flight_field
	launch_from = from
	launch_heading = heading
	if fleeing:
		flee_at = 0.0


## Sets the bird up to cross `band` from age 0 on Flight's crossing path (the title's geese).
func setup_crossing(bird_spec: BirdSpec, bird_number: int, flight_seed: int, band: Rect2) -> void:
	spec = bird_spec
	number = bird_number
	bird_seed = flight_seed
	crossing = band


## Freezes the bird for `seconds` (Play's hit stop); a longer hold already running is kept.
func hold(seconds: float) -> void:
	_held_for = maxf(_held_for, seconds)


## True while a hold (hit stop) freezes it.
func is_held() -> bool:
	return _held_for > 0.0


func _ready() -> void:
	# A bird scene opened on its own (the project check) has no spec and stays still.
	if spec == null:
		set_process(false)
		return
	for frame in spec.frames():
		_textures[frame] = load(spec.texture_path(frame)) as Texture2D
	_sprite.texture = _textures["fly_1"]
	_sprite.scale = spec.size / _sprite.texture.get_size()
	_reticle.scale = Vector2.ONE * RETICLE_SIZE / _reticle.texture.get_size().x
	transform = _flight_transform()
	_track()


func _process(frame_delta: float) -> void:
	var delta := frame_delta
	if _held_for > 0.0:
		_held_for -= frame_delta
		if _held_for >= 0.0:
			return
		# The hold ended inside this frame: only the rest of the frame runs.
		delta = -_held_for
		_held_for = 0.0
	match state:
		State.FLYING:
			age += delta
			if _has_left():
				set_process(false)
				escaped.emit(self)
				queue_free()
				return
			transform = _flight_transform()
			_sprite.texture = _textures[_flap_frame()]
			_track_clock += delta
			if _track_clock >= TRACK_INTERVAL:
				_track_clock -= TRACK_INTERVAL
				_track()
		State.HIT:
			_hold -= delta
			if _hold <= 0.0:
				state = State.FALLING
				_sprite.texture = _textures["dive"]
		State.FALLING:
			_fall_speed += GRAVITY * delta
			_fall_time += delta
			# The sprite faces +x (mirrored when facing left), so turning by facing x PI/2
			# points its head straight down either way.
			var pitch := _facing * PI / 2.0 * minf(_fall_time / FALL_TURN_TIME, 1.0)
			transform = Transform2D(pitch, Vector2(_facing, 1.0), 0.0, position + Vector2(0.0, _fall_speed * delta))
			if global_position.y - spec.size.y > get_viewport_rect().end.y:
				set_process(false)
				gone.emit(self)
				queue_free()


func is_flying() -> bool:
	return state == State.FLYING and not is_queued_for_deletion()


## True when `point` (in the parent's coordinates) is inside the hitbox polygon now.
func contains(point: Vector2) -> bool:
	return Flight.hits(spec, transform, point)


## True from the age its flight turns into the climb off the top (flee_time, or earlier
## when told to flee).
func is_fleeing() -> bool:
	return age >= minf(spec.flee_time, flee_at)


func is_cued() -> bool:
	return cue_age != Rival.NOT_AIMING


## Starts (from its current age) or ends the rival's aim cue: the reticle shows while it lasts.
func set_cue(on: bool) -> void:
	cue_age = age if on else Rival.NOT_AIMING
	_reticle.visible = on


## The rival shot it: no cue any more, and it drops like a kill (hit frame, then the fall).
func steal() -> void:
	stolen = true
	set_cue(false)
	_drop()


func is_damaged() -> bool:
	return hits_taken > 0


## Takes a hit. Short of spec.hp it keeps flying on its damaged flap frames and this
## returns false; the killing hit stops it on its hit frame, upright and facing the way it
## flew (it then falls head-first off the screen), and returns true.
func hit() -> bool:
	hits_taken += 1
	if hits_taken < spec.hp:
		_sprite.texture = _textures[_flap_frame()]
		return false
	_drop()
	return true


## Stops it on its hit frame for HIT_HOLD seconds, after which it falls head-first.
func _drop() -> void:
	state = State.HIT
	_hold = HIT_HOLD
	_sprite.texture = _textures["hit"]
	_facing = signf(transform.determinant())
	# Upright, keeping the facing. Flying left, the transform has a negative determinant
	# (Node2D stores it as rotation + PI with scale (1, -1)), so `rotation = 0` alone would
	# turn a left-facing goose upside down and facing right.
	transform = Transform2D(Vector2(_facing, 0.0), Vector2(0.0, 1.0), position)


## Makes a flying bird flee now (the wave's shells ran out).
func flee() -> void:
	if state == State.FLYING and age < minf(spec.flee_time, flee_at):
		flee_at = age


func _flight_transform() -> Transform2D:
	if crossing.has_area():
		return Flight.crossing_transform(spec, bird_seed, age, crossing)
	return Flight.transform_at(spec, bird_seed, age, field, speed_scale, flee_at, launch_from, launch_heading)


## True once it has escaped (the play path) or crossed its band (a crossing bird).
func _has_left() -> bool:
	if crossing.has_area():
		return Flight.has_crossed(spec, bird_seed, age, crossing)
	return Flight.has_escaped(spec, bird_seed, age, field, speed_scale, flee_at, launch_from, launch_heading)


## The flap frame for the current age: fly_1 / fly_2, or their damaged versions once hit.
func _flap_frame() -> String:
	return ("damaged_" if is_damaged() else "") + ("fly_1" if int(age / FLAP_TIME) % 2 == 0 else "fly_2")


func _track() -> void:
	if number != TRACKED_NUMBER or crossing.has_area():
		return
	var moving := Flight.velocity(spec, bird_seed, age, field, speed_scale, flee_at, launch_from, launch_heading)
	var ahead := PackedStringArray()
	for step in range(1, TRACK_AHEAD_STEPS + 1):
		var at := get_parent().to_global(Flight.position(spec, bird_seed, age + step * TRACK_AHEAD_STEP, field, speed_scale, flee_at, launch_from, launch_heading)) as Vector2
		ahead.append("(%.1f, %.1f)" % [at.x, at.y])
	print("[Bird] %s #%d at (%.1f, %.1f) v (%.1f, %.1f) age %.2f ahead %s" % [spec.id, number, global_position.x, global_position.y, moving.x, moving.y, age, " ".join(ahead)])
