class_name Flight
extends RefCounted
## Bird flight paths. Static only, no nodes: a bird's position is a pure function of its
## BirdSpec, its seed and its age (seconds since it spawned), plus the `field` it flies in
## (base units: below the HUD bar, above the grass line), the wave's speed scale and the
## age it was told to flee at (INF unless the shells ran out).
## The path: the bird starts fully below the field's bottom (hidden by the grass) at a
## seeded x, climbs at a seeded heading (FLIGHT_ANGLE_MIN..MAX above the horizontal,
## left or right) into the field, then bounces between its edges (turning back at the
## side edges, and at the top and bottom) with a seeded-phase vertical wobble. Once its
## size and wobble are inside the field it stays inside until it flees. At
## min(flee_time, flee_at) it climbs straight up at its speed (its x keeps bouncing) and
## has escaped once it is fully above ESCAPE_Y, the top of the screen.
## Patterns (BirdSpec.pattern): "rise" is that path; "zigzag" is the same path whose
## horizontal heading also reverses sharply at seeded intervals
## (ZIGZAG_INTERVAL_MIN..MAX seconds apart), before and after it flees.
## Launched birds (a splitter's goslings) start at a given point (`from`, kept inside the
## cruise band) on a given heading instead of below the grass, and bounce inside the band
## from there; split_headings() gives the goslings' diverging headings.

const FLIGHT_ANGLE_MIN := deg_to_rad(30.0)
const FLIGHT_ANGLE_MAX := deg_to_rad(60.0)
## The screen top: a fleeing bird has escaped once its whole sprite is above it.
const ESCAPE_Y := 0.0
## The bird tilts toward its climb or dive by at most this much.
const TILT_MAX := 0.45
## Step of the central difference that gives the velocity.
const VELOCITY_STEP := 1.0 / 120.0
## Seconds between two heading reversals of a zigzag bird (seeded per bird).
const ZIGZAG_INTERVAL_MIN := 0.35
const ZIGZAG_INTERVAL_MAX := 0.8
## The fan of the goslings' headings, centred straight up.
const SPLIT_FAN := deg_to_rad(100.0)
## `from` for a bird that is not launched (it rises from below the grass).
const NOT_LAUNCHED := Vector2.INF


## The bird's centre at `age`. `from` and `heading` launch it from a point (goslings).
static func position(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF, from := NOT_LAUNCHED, heading := Vector2.ZERO) -> Vector2:
	var path := _path(spec, bird_seed, field, from, heading)
	var launch_y := launch_point(spec, from, field).y if from.is_finite() else INF
	var speed := spec.speed * speed_scale
	var flee := minf(spec.flee_time, flee_at)
	var x := _bounce(path.x + path.z * speed * _travel(spec, bird_seed, age), path_x_low(spec, field), path_x_high(spec, field))
	if age <= flee:
		return Vector2(x, _cruise_y(spec, path, speed, age, field, launch_y))
	var fled_from := _cruise_y(spec, path, speed, flee, field, launch_y)
	return Vector2(x, fled_from - speed * (age - flee))


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


## The band the bird's centre cruises in once inside the field (size and wobble kept inside).
static func path_y_low(spec: BirdSpec, field: Rect2) -> float:
	return field.position.y + spec.size.y / 2.0 + spec.wobble


static func path_y_high(spec: BirdSpec, field: Rect2) -> float:
	return field.end.y - spec.size.y / 2.0 - spec.wobble


## The y the bird starts at: fully below the field's bottom, wobble included.
static func start_y(spec: BirdSpec, field: Rect2) -> float:
	return field.end.y + spec.size.y / 2.0 + spec.wobble


## The seeded part of a path: Vector4(start x, climb rate (share of the speed going up),
## horizontal direction times its share of the speed, wobble phase). A launched bird
## starts at its launch point on `heading`, with phase 0 (so it starts exactly there).
static func _path(spec: BirdSpec, bird_seed: int, field: Rect2, from: Vector2, heading: Vector2) -> Vector4:
	if from.is_finite():
		var launch := heading.normalized()
		return Vector4(launch_point(spec, from, field).x, -launch.y, launch.x, 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = bird_seed
	var x := rng.randf_range(path_x_low(spec, field), path_x_high(spec, field))
	var angle := rng.randf_range(FLIGHT_ANGLE_MIN, FLIGHT_ANGLE_MAX)
	var direction := -1.0 if rng.randf() < 0.5 else 1.0
	var phase := rng.randf_range(0.0, TAU)
	return Vector4(x, sin(angle), cos(angle) * direction, phase)


## The y before fleeing: climbing from start_y until it reaches the cruise band, then
## bouncing inside it, plus the wobble. start_y and the band leave room for the wobble,
## so the bird starts fully hidden and cruises fully inside the field. A launched bird
## (`launch_y` finite) bounces inside the band from launch_y at once.
static func _cruise_y(spec: BirdSpec, path: Vector4, speed: float, age: float, field: Rect2, launch_y: float) -> float:
	var high := path_y_high(spec, field)
	var climb := path.y * speed
	if is_finite(launch_y):
		return _bounce(launch_y - climb * age, path_y_low(spec, field), high) + spec.wobble * sin(TAU * spec.wobble_hz * age + path.w)
	var raw := start_y(spec, field) - climb * age
	if raw > high:
		# Still climbing in: the wobble holds the offset it has on entering the band, so the
		# climb never dips back out of the field once the sprite is inside it.
		var entry_age := (start_y(spec, field) - high) / climb
		return raw + spec.wobble * sin(TAU * spec.wobble_hz * entry_age + path.w)
	return _bounce(raw, path_y_low(spec, field), high) + spec.wobble * sin(TAU * spec.wobble_hz * age + path.w)


## The signed seconds of horizontal travel by `age`: the age itself for "rise"; for
## "zigzag", time flown after an odd number of seeded reversals (ZIGZAG_INTERVAL_MIN..MAX
## seconds apart) counts backwards.
static func _travel(spec: BirdSpec, bird_seed: int, age: float) -> float:
	if spec.pattern != "zigzag":
		return age
	var rng := _zigzag_rng(bird_seed)
	var turned_at := 0.0
	var travelled := 0.0
	var direction := 1.0
	while true:
		var next := turned_at + rng.randf_range(ZIGZAG_INTERVAL_MIN, ZIGZAG_INTERVAL_MAX)
		if next >= age:
			break
		travelled += direction * (next - turned_at)
		turned_at = next
		direction = -direction
	return travelled + direction * (age - turned_at)


## The zigzag's own random stream, apart from the path's.
static func _zigzag_rng(bird_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([bird_seed, "zigzag"])
	return rng


## `value` folded into low..high like a ball bouncing between two walls (a triangle wave).
static func _bounce(value: float, low: float, high: float) -> float:
	var span := high - low
	if span <= 0.0:
		return low
	var folded := fposmod(value - low, 2.0 * span)
	return low + (folded if folded <= span else 2.0 * span - folded)
