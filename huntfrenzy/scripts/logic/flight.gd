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

const FLIGHT_ANGLE_MIN := deg_to_rad(30.0)
const FLIGHT_ANGLE_MAX := deg_to_rad(60.0)
## The screen top: a fleeing bird has escaped once its whole sprite is above it.
const ESCAPE_Y := 0.0
## The bird tilts toward its climb or dive by at most this much.
const TILT_MAX := 0.45
## Step of the central difference that gives the velocity.
const VELOCITY_STEP := 1.0 / 120.0


## The bird's centre at `age`.
static func position(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF) -> Vector2:
	var path := _path(spec, bird_seed, field)
	var speed := spec.speed * speed_scale
	var flee := minf(spec.flee_time, flee_at)
	var x := _bounce(path.x + path.z * speed * age, path_x_low(spec, field), path_x_high(spec, field))
	if age <= flee:
		return Vector2(x, _cruise_y(spec, path, speed, age, field))
	var fled_from := _cruise_y(spec, path, speed, flee, field)
	return Vector2(x, fled_from - speed * (age - flee))


## The bird's velocity at `age` (base units per second), by central difference.
static func velocity(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF) -> Vector2:
	var ahead := position(spec, bird_seed, age + VELOCITY_STEP, field, speed_scale, flee_at)
	var behind := position(spec, bird_seed, age - VELOCITY_STEP, field, speed_scale, flee_at)
	return (ahead - behind) / (2.0 * VELOCITY_STEP)


## The bird's transform at `age`: its centre, facing (x scale -1 when flying left; the
## sprite faces right) and a tilt toward its climb or dive.
static func transform_at(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF) -> Transform2D:
	var moving := velocity(spec, bird_seed, age, field, speed_scale, flee_at)
	var facing := -1.0 if moving.x < 0.0 else 1.0
	var tilt := clampf(atan2(moving.y, absf(moving.x)), -TILT_MAX, TILT_MAX)
	return Transform2D(tilt * facing, Vector2(facing, 1.0), 0.0, position(spec, bird_seed, age, field, speed_scale, flee_at))


## True once the bird has fled and is fully above ESCAPE_Y.
static func has_escaped(spec: BirdSpec, bird_seed: int, age: float, field: Rect2, speed_scale := 1.0, flee_at := INF) -> bool:
	if age <= minf(spec.flee_time, flee_at):
		return false
	return position(spec, bird_seed, age, field, speed_scale, flee_at).y + spec.size.y / 2.0 < ESCAPE_Y


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
## horizontal direction times its share of the speed, wobble phase).
static func _path(spec: BirdSpec, bird_seed: int, field: Rect2) -> Vector4:
	var rng := RandomNumberGenerator.new()
	rng.seed = bird_seed
	var x := rng.randf_range(path_x_low(spec, field), path_x_high(spec, field))
	var angle := rng.randf_range(FLIGHT_ANGLE_MIN, FLIGHT_ANGLE_MAX)
	var direction := -1.0 if rng.randf() < 0.5 else 1.0
	var phase := rng.randf_range(0.0, TAU)
	return Vector4(x, sin(angle), cos(angle) * direction, phase)


## The y before fleeing: climbing from start_y until it reaches the cruise band, then
## bouncing inside it, plus the wobble. start_y and the band leave room for the wobble,
## so the bird starts fully hidden and cruises fully inside the field.
static func _cruise_y(spec: BirdSpec, path: Vector4, speed: float, age: float, field: Rect2) -> float:
	var high := path_y_high(spec, field)
	var climb := path.y * speed
	var raw := start_y(spec, field) - climb * age
	if raw > high:
		# Still climbing in: the wobble holds the offset it has on entering the band, so the
		# climb never dips back out of the field once the sprite is inside it.
		var entry_age := (start_y(spec, field) - high) / climb
		return raw + spec.wobble * sin(TAU * spec.wobble_hz * entry_age + path.w)
	return _bounce(raw, path_y_low(spec, field), high) + spec.wobble * sin(TAU * spec.wobble_hz * age + path.w)


## `value` folded into low..high like a ball bouncing between two walls (a triangle wave).
static func _bounce(value: float, low: float, high: float) -> float:
	var span := high - low
	if span <= 0.0:
		return low
	var folded := fposmod(value - low, 2.0 * span)
	return low + (folded if folded <= span else 2.0 * span - folded)
