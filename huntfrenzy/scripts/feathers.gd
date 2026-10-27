class_name Feathers
extends Node2D
## Feather bursts: burst() throws FEATHERS_PER_BURST feathers from a point (a kill), in the
## palette colours of the bird's sprite (COLORS, from art/palette.hex, matching each
## sprite's plumage), which fan out upward, slow down, sway as they drift down, spin and
## fade out over a seeded FEATHER_LIFE_MIN..MAX seconds. At most FEATHERS_MAX are alive at
## once: a burst that would pass the cap retires the oldest first. That cap bounds the
## per-frame cost (one small polygon each, drawn by this node in one _draw) for the phone
## frame budget. Purely visual: nothing reads it (the hit stop does not freeze it; a paused
## tree does). Each burst draws from an RNG seeded by its point, the sprite and the burst
## count, so the same run bursts the same. A sprite with no colours here is reported (log
## and error label) once and bursts nothing.

## The most feathers alive at once (the step 10 phone budget: one polygon and outline each).
const FEATHERS_MAX := 48
## Feathers per burst (a kill).
const FEATHERS_PER_BURST := 10
## Each sprite's feather colours (palette entries; tests check every bird sprite has some).
const COLORS: Dictionary[String, Array] = {
	"goose": [Color(0.722, 0.647, 0.549), Color(0.541, 0.459, 0.376), Color(0.984, 0.929, 0.804)],
	"armored": [Color(0.722, 0.769, 0.816), Color(0.435, 0.498, 0.58), Color(0.31, 0.365, 0.447)],
	"splitter": [Color(0.561, 0.847, 0.784), Color(0.247, 0.655, 0.627), Color(1.0, 0.824, 0.659)],
	"gosling": [Color(1.0, 0.929, 0.6), Color(0.949, 0.714, 0.196), Color(1.0, 0.824, 0.659)],
	"zigzag": [Color(0.431, 0.765, 0.941), Color(0.184, 0.498, 0.659), Color(1.0, 0.929, 0.6)],
	"golden": [Color(0.949, 0.714, 0.196), Color(1.0, 0.929, 0.6), Color(0.788, 0.541, 0.118)],
	"decoy": [Color(0.788, 0.714, 0.894), Color(0.557, 0.424, 0.722), Color(1.0, 1.0, 1.0)],
}
## The feathers' outline (the art's ink).
const INK := Color(0.122, 0.102, 0.18)
## Launch speed (base units per second), within FAN of straight up.
const SPEED_MIN := 120.0
const SPEED_MAX := 260.0
const FAN := deg_to_rad(150.0)
## Downward pull, and how fast the air slows them (fraction of the speed kept per second).
const GRAVITY := 260.0
const DRAG := 0.12
## Sideways sway while they drift down.
const SWAY := 22.0
const SWAY_HZ := 1.6
const FEATHER_LIFE_MIN := 0.9
const FEATHER_LIFE_MAX := 1.4
## The last seconds of a feather's life fade it out.
const FADE_TIME := 0.35
## A feather's shape: a slim leaf, 12 long and 5 wide, pointing along +x.
const SHAPE: Array[Vector2] = [Vector2(-6, 0), Vector2(-3, -2.5), Vector2(3, -2), Vector2(6, 0), Vector2(3, 2), Vector2(-3, 2.5)]


## One feather in the air.
class Feather:
	var position := Vector2.ZERO
	var velocity := Vector2.ZERO
	var color := Color.WHITE
	var angle := 0.0
	var spin := 0.0
	var age := 0.0
	var life := 1.0
	var phase := 0.0

## Bursts so far (seeds the next one).
var bursts := 0

var _feathers: Array[Feather] = []
var _shape := PackedVector2Array(SHAPE)
## Sprites already reported as having no colours.
var _reported: Dictionary[String, bool] = {}


## Throws FEATHERS_PER_BURST feathers in `sprite`'s colours from `point` (this node's
## coordinates), retiring the oldest beyond FEATHERS_MAX. Returns how many it threw (0 for
## a sprite without colours, which is reported once).
func burst(point: Vector2, sprite: String) -> int:
	if not COLORS.has(sprite):
		if not _reported.has(sprite):
			_reported[sprite] = true
			(get_node(GameState.AUTOLOAD_PATH) as GameState).report_error("No feather colours for the sprite '%s' (Feathers.COLORS); its kills burst no feathers" % sprite)
		return 0
	bursts += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([roundi(point.x), roundi(point.y), sprite, bursts])
	var colors: Array = COLORS[sprite]
	for i in FEATHERS_PER_BURST:
		var feather := Feather.new()
		feather.position = point
		var heading := -PI / 2.0 + rng.randf_range(-FAN / 2.0, FAN / 2.0)
		feather.velocity = Vector2.from_angle(heading) * rng.randf_range(SPEED_MIN, SPEED_MAX)
		feather.color = colors[i % colors.size()] as Color
		feather.angle = rng.randf_range(0.0, TAU)
		feather.spin = rng.randf_range(-6.0, 6.0)
		feather.life = rng.randf_range(FEATHER_LIFE_MIN, FEATHER_LIFE_MAX)
		feather.phase = rng.randf_range(0.0, TAU)
		_feathers.append(feather)
	while _feathers.size() > FEATHERS_MAX:
		_feathers.pop_front()
	queue_redraw()
	return FEATHERS_PER_BURST


## Feathers alive now.
func live_count() -> int:
	return _feathers.size()


## The colours of the feathers alive now, oldest first (tests read them).
func live_colors() -> PackedColorArray:
	var colors := PackedColorArray()
	for feather in _feathers:
		colors.append(feather.color)
	return colors


func _process(delta: float) -> void:
	if _feathers.is_empty():
		return
	var kept: Array[Feather] = []
	for feather in _feathers:
		feather.age += delta
		if feather.age >= feather.life:
			continue
		feather.velocity *= pow(DRAG, delta)
		feather.velocity.y += GRAVITY * delta
		feather.position += feather.velocity * delta
		feather.angle += feather.spin * delta
		kept.append(feather)
	_feathers = kept
	queue_redraw()


func _draw() -> void:
	for feather in _feathers:
		var fade := clampf((feather.life - feather.age) / FADE_TIME, 0.0, 1.0)
		var sway := Vector2(SWAY * sin(TAU * SWAY_HZ * feather.age + feather.phase), 0.0)
		var shape := Transform2D(feather.angle, feather.position + sway) * _shape
		var fill := feather.color
		fill.a = fade
		var outline := INK
		outline.a = fade
		draw_colored_polygon(shape, fill)
		var closed := shape.duplicate()
		closed.append(shape[0])
		draw_polyline(closed, outline, 1.0)
