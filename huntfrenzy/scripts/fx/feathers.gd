class_name Feathers
extends Node2D
## Feather bursts: burst() throws FEATHERS_PER_BURST feathers from a point (a kill), in the
## palette colours of the bird's sprite (COLORS, from art/palette.hex, matching each
## sprite's plumage), which fan out upward, slow down, sway as they drift down, spin and
## fade out over a seeded Game.tuning.feather_life_min..max seconds (the motion: Game.tuning.feather_*). At most FEATHERS_MAX are alive at
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
	"goose": [Palette.TAN, Palette.BROWN, Palette.CREAM],
	"armored": [Palette.STEEL_LIGHT, Palette.STEEL, Palette.STEEL_DARK],
	"splitter": [Palette.MINT, Palette.TEAL, Palette.PEACH],
	"gosling": [Palette.PALE_GOLD, Palette.GOLD, Palette.PEACH],
	"zigzag": [Palette.BROWN_DARK, Palette.CREAM, Palette.TEAL],
	"golden": [Palette.GOLD, Palette.PALE_GOLD, Palette.GOLD_DARK],
	"decoy": [Palette.LILAC, Palette.VIOLET, Palette.WHITE],
}
## A feather's shape: a slim leaf, 18 long and 7.5 wide, pointing along +x.
const SHAPE: Array[Vector2] = [Vector2(-9, 0), Vector2(-4.5, -3.75), Vector2(4.5, -3), Vector2(9, 0), Vector2(4.5, 3), Vector2(-4.5, 3.75)]


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

## Bursts so far (seeds the next one), and where the latest one started (tests read it).
var bursts := 0
var last_burst_at := Vector2.INF

var _feathers: Array[Feather] = []
var _shape := PackedVector2Array(SHAPE)
## Sprites already reported as having no colours.
var _reported: Dictionary[String, bool] = {}

@onready var _tuning := (get_node(GameState.AUTOLOAD_PATH) as GameState).tuning


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
	last_burst_at = point
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([roundi(point.x), roundi(point.y), sprite, bursts])
	var colors: Array = COLORS[sprite]
	var fan := deg_to_rad(_tuning.feather_fan)
	for i in FEATHERS_PER_BURST:
		var feather := Feather.new()
		feather.position = point
		var heading := -PI / 2.0 + rng.randf_range(-fan / 2.0, fan / 2.0)
		feather.velocity = Vector2.from_angle(heading) * rng.randf_range(_tuning.feather_speed_min, _tuning.feather_speed_max)
		feather.color = colors[i % colors.size()] as Color
		feather.angle = rng.randf_range(0.0, TAU)
		feather.spin = rng.randf_range(-_tuning.feather_spin, _tuning.feather_spin)
		feather.life = rng.randf_range(_tuning.feather_life_min, _tuning.feather_life_max)
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
		feather.velocity *= pow(_tuning.feather_drag, delta)
		feather.velocity.y += _tuning.feather_gravity * delta
		feather.position += feather.velocity * delta
		feather.angle += feather.spin * delta
		kept.append(feather)
	_feathers = kept
	queue_redraw()


func _draw() -> void:
	for feather in _feathers:
		var fade := clampf((feather.life - feather.age) / _tuning.feather_fade_time, 0.0, 1.0)
		var sway := Vector2(_tuning.feather_sway * sin(TAU * _tuning.feather_sway_hz * feather.age + feather.phase), 0.0)
		var shape := Transform2D(feather.angle, feather.position + sway) * _shape
		var fill := feather.color
		fill.a = fade
		var outline := Palette.INK
		outline.a = fade
		draw_colored_polygon(shape, fill)
		var closed := shape.duplicate()
		closed.append(shape[0])
		draw_polyline(closed, outline, 1.5)
