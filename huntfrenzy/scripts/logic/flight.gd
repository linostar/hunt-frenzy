class_name Flight
extends RefCounted
## Bird flight paths. Static only, no nodes: a bird's position is a pure function of its
## BirdSpec, its seed and its age (seconds since it spawned), plus the `field` it flies in
## (base units: below the HUD bar, above the grass line), its speed scale and the age it
## was told to flee at (INF unless the shells ran out).
## The path: the bird starts fully below the field's bottom (hidden by the grass) at a
## seeded x and climbs at a seeded heading (FLIGHT_ANGLE_MIN..MAX above the horizontal,
## left or right) into the cruise band. From there it flies straight segments at constant
## velocity: it bounces off the band's edges (the matching velocity component reflects:
## the side edges, the top and the bottom), and at seeded intervals it turns to a new
## seeded heading, FLIGHT_ANGLE_MIN..MAX from the horizontal, up or down, left or right.
## No wobble: between two turns (and bounces) its centre moves in a straight line, so its
## facing and tilt hold steady. Once its size is inside the field it stays inside until
## it flees. At min(flee_time, flee_at) it climbs straight up at its speed (its x keeps
## its segments and bounces) and has escaped once it is fully above ESCAPE_Y, the top of
## the screen. The segments are drawn by a seeded loop from the start of the cruise, so
## the path stays a pure function of the age (turn_ages lists the turns).
## Patterns (BirdSpec.pattern): "rise" turns every TURN_INTERVAL_MIN..MAX seconds;
## "zigzag" turns every ZIGZAG_INTERVAL_MIN..MAX seconds and always reverses its
## horizontal heading when it turns, so it is the twitchier bird.
## Launched birds (a splitter's goslings) start at a given point (`from`, kept inside the
## cruise band) on a given heading instead of below the grass, and fly their segments
## inside the band from there at once; split_headings() gives the goslings' diverging
## headings.
## Each bird's speed is its spec's x the wave's speed scale x a seeded per-bird factor
## (speed_factor: within 1 -/+ speed_spread, the spread widening with the speed scale);
## Play folds the factor into the speed scale it passes in.
## Crossing birds (the title's geese) take a different, level path: from just beyond one
## side of a `band` to beyond the other at a seeded height inside it, wobbling up and down,
## never leaving it vertically (crossing_position, crossing_transform, has_crossed).

const FLIGHT_ANGLE_MIN := deg_to_rad(30.0)
const FLIGHT_ANGLE_MAX := deg_to_rad(60.0)
## The screen top: a fleeing bird has escaped once its whole sprite is above it.
const ESCAPE_Y := 0.0
## The bird tilts toward its climb or dive by at most this much.
const TILT_MAX := 0.45
## Step of the central difference that gives the velocity.
const VELOCITY_STEP := 1.0 / 120.0
## Seconds between two turns of a "rise" bird (seeded per bird).
const TURN_INTERVAL_MIN := 1.0
const TURN_INTERVAL_MAX := 2.5
## Seconds between two turns of a zigzag bird (seeded per bird); each reverses its
## horizontal heading.
const ZIGZAG_INTERVAL_MIN := 0.35
const ZIGZAG_INTERVAL_MAX := 0.8
## The per-bird speed spread (speed_spread): SPEED_SPREAD_MIN at speed scale 1, rising
## linearly to SPEED_SPREAD_MAX at SPEED_SPREAD_TOP_SCALE (the highest speed scale in the
## content: the night boss and the Endless cap), clamped at both ends.
const SPEED_SPREAD_MIN := 0.05
const SPEED_SPREAD_MAX := 0.2
const SPEED_SPREAD_TOP_SCALE := 1.6
## The fan of the goslings' headings, centred straight up.
const SPLIT_FAN := deg_to_rad(100.0)
## `from` for a bird that is not launched (it rises from below the grass).
const NOT_LAUNCHED := Vector2.INF
## A crossing bird's speed is its spec's x a seeded factor in this range.
const CROSSING_SPEED_MIN := 0.85
const CROSSING_SPEED_MAX := 1.15


## The bird's centre at `age`. `from` and `heading` launch it from a point (goslings).
static func position(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> Vector2:
	var start := _start(spec, bird_seed, field, from)
	var first := _first_heading(spec, bird_seed, field, from, heading)
	var speed := spec.speed * speed_scale
	var entry := _entry_age(spec, field, start, first, speed)
	var flee := minf(spec.flee_time, flee_at)
	var x := _bounce(start.x + speed * _offset(spec, bird_seed, age, entry, first).x, path_x_low(spec, field), path_x_high(spec, field))
	var cruise_age := minf(age, flee)
	var raw_y := start.y + speed * _offset(spec, bird_seed, cruise_age, entry, first).y
	# Still climbing in from below the grass: not folded into the band yet.
	var y := raw_y if cruise_age < entry else _bounce(raw_y, path_y_low(spec, field), path_y_high(spec, field))
	if age <= flee:
		return Vector2(x, y)
	return Vector2(x, y - speed * (age - flee))


## The bird's velocity at `age` (base units per second), by central difference.
static func velocity(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> Vector2:
	var ahead := position(spec, bird_seed, age + VELOCITY_STEP, field, speed_scale, flee_at, from, heading)
	var behind := position(spec, bird_seed, age - VELOCITY_STEP, field, speed_scale, flee_at, from, heading)
	return (ahead - behind) / (2.0 * VELOCITY_STEP)


## The bird's transform at `age`: its centre, facing (x scale -1 when flying left; the
## sprite faces right) and a tilt toward its climb or dive.
static func transform_at(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> Transform2D:
	var moving := velocity(spec, bird_seed, age, field, speed_scale, flee_at, from, heading)
	var facing := -1.0 if moving.x < 0.0 else 1.0
	var tilt := clampf(atan2(moving.y, absf(moving.x)), -TILT_MAX, TILT_MAX)
	return Transform2D(tilt * facing, Vector2(facing, 1.0), 0.0, position(spec, bird_seed, age, field, speed_scale, flee_at, from, heading))


## True once the bird has fled and is fully above ESCAPE_Y.
static func has_escaped(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> bool:
	if age <= minf(spec.flee_time, flee_at):
		return false
	return position(spec, bird_seed, age, field, speed_scale, flee_at, from, heading).y + spec.size.y / 2.0 < ESCAPE_Y


## Where a bird launched from `from` starts: that point, moved inside the band its centre
## cruises in (so a gosling from a hit near an edge starts fully inside the field).
static func launch_point(spec: BirdSpec, from: Vector2, field: Rect2) -> Vector2:
	return Vector2(clampf(from.x, path_x_low(spec, field), path_x_high(spec, field)), clampf(from.y, path_y_low(spec, field), path_y_high(spec, field)))


## The headings of `count` birds split from one: fanned evenly across SPLIT_FAN, centred
## straight up (two goslings: up-left and up-right), so they diverge.
static func split_headings(count: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in count:
		var share := 0.5 if count == 1 else float(i) / (count - 1)
		result.append(Vector2.from_angle(-PI / 2.0 + lerpf(-SPLIT_FAN / 2.0, SPLIT_FAN / 2.0, share)))
	return result


## True when `point` lies inside the bird's hitbox polygon placed by `transform`.
static func hits(spec: BirdSpec, transform: Transform2D, point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(transform.affine_inverse() * point, spec.hitbox)


## The lowest and highest x of the bird's centre inside `field`.
static func path_x_low(spec: BirdSpec, field: Rect2) -> float:
	return field.position.x + spec.size.x / 2.0


static func path_x_high(spec: BirdSpec, field: Rect2) -> float:
	return field.end.x - spec.size.x / 2.0


## The band the bird's centre cruises in once inside the field (its size kept inside).
static func path_y_low(spec: BirdSpec, field: Rect2) -> float:
	return field.position.y + spec.size.y / 2.0


static func path_y_high(spec: BirdSpec, field: Rect2) -> float:
	return field.end.y - spec.size.y / 2.0


## The y the bird starts at: fully below the field's bottom.
static func start_y(spec: BirdSpec, field: Rect2) -> float:
	return field.end.y + spec.size.y / 2.0


## The spread of the per-bird speed factor at `speed_scale`: SPEED_SPREAD_MIN at 1, rising
## linearly to SPEED_SPREAD_MAX at SPEED_SPREAD_TOP_SCALE, clamped at both ends.
static func speed_spread(speed_scale: float) -> float:
	return clampf(remap(speed_scale, 1.0, SPEED_SPREAD_TOP_SCALE, SPEED_SPREAD_MIN, SPEED_SPREAD_MAX), SPEED_SPREAD_MIN, SPEED_SPREAD_MAX)


## The bird's own speed factor in a wave of `speed_scale`: seeded by the bird, within
## 1 -/+ speed_spread(speed_scale). Play multiplies the wave's speed scale by it.
static func speed_factor(bird_seed: int, speed_scale: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([bird_seed, "speed"])
	var spread := speed_spread(speed_scale)
	return 1.0 + rng.randf_range(-spread, spread)


## The age the bird starts its cruise (its first turn's interval starts there): when a
## rising bird's climb reaches the cruise band, 0 for a launched one.
static func entry_age(spec: BirdSpec, bird_seed: int, field: Rect2, speed_scale := 1.0, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> float:
	var start := _start(spec, bird_seed, field, from)
	return _entry_age(spec, field, start, _first_heading(spec, bird_seed, field, from, heading), spec.speed * speed_scale)


## The ages of the bird's seeded turns before `until`, cruising from `entry` (entry_age).
static func turn_ages(spec: BirdSpec, bird_seed: int, entry: float, until: float) -> PackedFloat64Array:
	var ages := PackedFloat64Array()
	var rng := _turn_rng(spec, bird_seed)
	var next := entry + _interval(spec, rng)
	while next < until:
		ages.append(next)
		_turn(spec, rng, Vector2.RIGHT)
		next += _interval(spec, rng)
	return ages


## Where the bird's path starts (before folding into the band): a seeded x below the
## field's bottom, or the launch point of a launched bird.
static func _start(spec: BirdSpec, bird_seed: int, field: Rect2, from: Vector2) -> Vector2:
	if from.is_finite():
		return launch_point(spec, from, field)
	var rng := _path_rng(bird_seed)
	return Vector2(rng.randf_range(path_x_low(spec, field), path_x_high(spec, field)), start_y(spec, field))


## The heading (a unit vector, y down) of the first segment: a seeded climb
## FLIGHT_ANGLE_MIN..MAX above the horizontal, left or right, or a launched bird's heading.
static func _first_heading(spec: BirdSpec, bird_seed: int, field: Rect2, from: Vector2, heading: Vector2) -> Vector2:
	if from.is_finite():
		return heading.normalized()
	var rng := _path_rng(bird_seed)
	rng.randf_range(path_x_low(spec, field), path_x_high(spec, field))
	var angle := rng.randf_range(FLIGHT_ANGLE_MIN, FLIGHT_ANGLE_MAX)
	var direction := -1.0 if rng.randf() < 0.5 else 1.0
	return Vector2(cos(angle) * direction, -sin(angle))


## The age a climb from `start` on `first` at `speed` reaches the cruise band (0 when it
## starts inside it: a launched bird).
static func _entry_age(spec: BirdSpec, field: Rect2, start: Vector2, first: Vector2, speed: float) -> float:
	var below := start.y - path_y_high(spec, field)
	if below <= 0.0:
		return 0.0
	return below / (-first.y * speed)


## The path's own random stream (start x, climb angle, side).
static func _path_rng(bird_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = bird_seed
	return rng


## The unfolded displacement by `age` per unit of speed: the sum of each segment's heading
## x its seconds. The first segment (`first`) runs from age 0 to `entry` plus the first
## interval; each later one is a seeded turn (_turn) lasting a seeded interval.
static func _offset(spec: BirdSpec, bird_seed: int, age: float, entry: float, first: Vector2) -> Vector2:
	var rng := _turn_rng(spec, bird_seed)
	var heading := first
	var offset := Vector2.ZERO
	var turned_at := 0.0
	var next := entry + _interval(spec, rng)
	while next < age:
		offset += heading * (next - turned_at)
		turned_at = next
		heading = _turn(spec, rng, heading)
		next += _interval(spec, rng)
	return offset + heading * (age - turned_at)


## Seconds to the next turn: TURN_INTERVAL_MIN..MAX for "rise", ZIGZAG_INTERVAL_MIN..MAX
## for "zigzag".
static func _interval(spec: BirdSpec, rng: RandomNumberGenerator) -> float:
	if spec.pattern == "zigzag":
		return rng.randf_range(ZIGZAG_INTERVAL_MIN, ZIGZAG_INTERVAL_MAX)
	return rng.randf_range(TURN_INTERVAL_MIN, TURN_INTERVAL_MAX)


## The heading after a turn from `heading`: FLIGHT_ANGLE_MIN..MAX from the horizontal, up
## or down (seeded); left or right (seeded) for "rise", the other way for "zigzag".
static func _turn(spec: BirdSpec, rng: RandomNumberGenerator, heading: Vector2) -> Vector2:
	var angle := rng.randf_range(FLIGHT_ANGLE_MIN, FLIGHT_ANGLE_MAX)
	var vertical := -1.0 if rng.randf() < 0.5 else 1.0
	var horizontal := -1.0 if rng.randf() < 0.5 else 1.0
	if spec.pattern == "zigzag":
		horizontal = -1.0 if heading.x > 0.0 else 1.0
	return Vector2(cos(angle) * horizontal, sin(angle) * vertical)


## The turns' own random stream, apart from the path's (each pattern its own).
static func _turn_rng(spec: BirdSpec, bird_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([bird_seed, spec.pattern, "turns"])
	return rng


## `value` folded into low..high like a ball bouncing between two walls (a triangle wave).
static func _bounce(value: float, low: float, high: float) -> float:
	var span := high - low
	if span <= 0.0:
		return low
	var folded := fposmod(value - low, 2.0 * span)
	return low + (folded if folded <= span else 2.0 * span - folded)


## A crossing bird's centre at `age`: it enters beyond one side of `band` (a seeded side)
## and flies level to beyond the other at its spec's speed x a seeded CROSSING_SPEED_MIN..MAX
## factor x `speed_scale`, at a seeded height, wobbling (spec.wobble at spec.wobble_hz, a
## seeded phase, the amplitude cut to what the band leaves room for); its whole sprite
## stays inside the band vertically. A band too short for the sprite keeps it centred.
static func crossing_position(spec: BirdSpec, bird_seed: int, age: float, band: Rect2, speed_scale := 1.0) -> Vector2:
	var plan := _crossing(spec, bird_seed, band, speed_scale)
	var x: float = plan["start_x"] + plan["direction"] * plan["speed"] * age
	return Vector2(x, plan["y"] + plan["wobble"] * sin(TAU * spec.wobble_hz * age + plan["phase"]))


## A crossing bird's transform at `age`: its centre and its facing (x scale -1 flying left),
## level (no tilt), so its sprite's box is its spec size around the centre.
static func crossing_transform(spec: BirdSpec, bird_seed: int, age: float, band: Rect2, speed_scale := 1.0) -> Transform2D:
	var facing: float = _crossing(spec, bird_seed, band, speed_scale)["direction"]
	return Transform2D(0.0, Vector2(facing, 1.0), 0.0, crossing_position(spec, bird_seed, age, band, speed_scale))


## True once a crossing bird's whole sprite is past the far side of `band`.
static func has_crossed(spec: BirdSpec, bird_seed: int, age: float, band: Rect2, speed_scale := 1.0) -> bool:
	var plan := _crossing(spec, bird_seed, band, speed_scale)
	var x := crossing_position(spec, bird_seed, age, band, speed_scale).x
	return x - spec.size.x / 2.0 > band.end.x if plan["direction"] > 0.0 else x + spec.size.x / 2.0 < band.position.x


## A crossing bird's seeded plan: direction (1 right, -1 left), start x, speed, the height
## of its centre line, its wobble amplitude and phase.
static func _crossing(spec: BirdSpec, bird_seed: int, band: Rect2, speed_scale: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([bird_seed, "crossing"])
	var direction := 1.0 if rng.randf() < 0.5 else -1.0
	var speed := spec.speed * speed_scale * rng.randf_range(CROSSING_SPEED_MIN, CROSSING_SPEED_MAX)
	var room := maxf(band.size.y - spec.size.y, 0.0)
	var wobble := minf(spec.wobble, room / 2.0)
	var low := band.position.y + spec.size.y / 2.0 + wobble
	var high := band.end.y - spec.size.y / 2.0 - wobble
	var y := lerpf(low, high, rng.randf()) if high >= low else band.get_center().y
	var start_x := band.position.x - spec.size.x / 2.0 if direction > 0.0 else band.end.x + spec.size.x / 2.0
	return {"direction": direction, "start_x": start_x, "speed": speed, "y": y, "wobble": wobble, "phase": rng.randf_range(0.0, TAU)}
