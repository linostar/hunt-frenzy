class_name Wipe
extends Control
## The screen-change wipe (Game.goto): a wall of marsh grass that rises from below the
## screen until it covers it (progress 0 -> 1), then sinks away again (1 -> 2), revealing
## the new screen from the top down. The grass is a solid body with a row of seeded blade
## tips along its top edge, in two greens over a darker back row, all palette colours.
## Purely drawn: it takes no input (Game's Cover under it blocks the touches).

## The blades' tips reach at most this far above the body's top edge (base units).
const BLADE_MAX := 70.0
## Blade widths at their base (seeded in this range).
const BLADE_WIDTH_MIN := 22.0
const BLADE_WIDTH_MAX := 38.0
## Seeds the blades, so the wipe always looks the same.
const BLADE_SEED := 4401
const BODY := Color(0.18, 0.29, 0.227)
const BACK_BLADES := Color(0.18, 0.29, 0.227)
const FRONT_BLADES := Color(0.29, 0.478, 0.227)
const LIGHT_BLADES := Color(0.435, 0.624, 0.29)
const INK := Color(0.122, 0.102, 0.18)

## 0: below the screen, 1: covering it, 2: gone below it again.
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()


## How much of the screen it covers (0..1): progress on the way in, 2 - progress on the way out.
func coverage() -> float:
	return clampf(progress if progress <= 1.0 else 2.0 - progress, 0.0, 1.0)


## The body's top edge (local y) at the current progress: below the bottom plus BLADE_MAX
## at 0 and 2 (nothing shows), at the top at 1 (all covered). It rises easing out and
## sinks easing in.
func edge_y() -> float:
	var below := size.y + BLADE_MAX
	if progress <= 1.0:
		return lerpf(below, 0.0, ease(clampf(progress, 0.0, 1.0), 0.5))
	return lerpf(0.0, below, ease(clampf(progress - 1.0, 0.0, 1.0), 2.0))


func _draw() -> void:
	var edge := edge_y()
	if edge >= size.y + BLADE_MAX:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = BLADE_SEED
	# Back row (darker, taller), then the front row in alternating greens.
	for row: int in [0, 1]:
		var x := -rng.randf_range(0.0, BLADE_WIDTH_MAX)
		var i := 0
		while x < size.x:
			var width := rng.randf_range(BLADE_WIDTH_MIN, BLADE_WIDTH_MAX)
			var height := rng.randf_range(0.5, 1.0) * BLADE_MAX * (1.0 if row == 0 else 0.8)
			var lean := rng.randf_range(-12.0, 12.0)
			var base := edge + (2.0 if row == 0 else 8.0)
			var blade := PackedVector2Array([Vector2(x, base), Vector2(x + width / 2.0 + lean, base - height), Vector2(x + width, base)])
			var fill := BACK_BLADES if row == 0 else (FRONT_BLADES if i % 2 == 0 else LIGHT_BLADES)
			draw_colored_polygon(blade, fill)
			draw_polyline(PackedVector2Array([blade[0], blade[1], blade[2]]), INK, 2.0)
			x += width * 0.7
			i += 1
	draw_rect(Rect2(0.0, edge + 2.0, size.x, maxf(size.y - edge - 2.0, 0.0)), BODY)
