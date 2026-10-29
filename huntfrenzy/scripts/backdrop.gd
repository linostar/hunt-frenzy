class_name Backdrop
extends Node2D
## One layered backdrop of the play scene (Content.BACKDROP_LAYERS, art in
## res://art/backdrops/): the sky covers the whole visible area (kept in aspect), the far
## marsh and the near reeds and water are seamless 960-wide tiles across its width at fixed
## heights of the 960x540 base, and the grass, a tile solid from GRASS_TIP below its top,
## runs from the grass line down to the visible bottom. The grass has z_index 1, so it is
## drawn over the birds (z 0) that rise from behind it; everything else lies behind them.
## show_backdrop() loads a backdrop's layers; a layer whose art is missing or is no texture
## is reported (Game.report_error: the log and the error label, with the file named) and
## nothing is shown for it. Two backdrops cross-fade by tweening the newer one's alpha.

## The light each backdrop throws on the rival hunter, set as his modulate wherever he is
## drawn over it (play and the title): neutral at noon, warm at dawn and sunset, cool and
## moonlit at night. Palette colours only (art/palette.hex). Every backdrop the data shows
## has one (SCHEMA.md I26).
const RIVAL_TINTS: Dictionary[String, Color] = {
	"dawn": Color(0.984, 0.929, 0.804),
	"noon": Color(1, 1, 1),
	"sunset": Color(1, 0.824, 0.659),
	"night": Color(0.553, 0.592, 0.839),
}

## Where the far and near layers start (World y, base units).
const FAR_TOP := 250.0
const NEAR_TOP := 330.0

## The backdrop shown ("" before show_backdrop()).
var id := ""

@onready var _layers: Dictionary[String, TextureRect] = {"sky": $Sky, "far": $Far, "near": $Near, "grass": $Grass}


## The rival's tint over backdrop `backdrop_id`; white (none) for a backdrop without one,
## which I26 rules out for every backdrop in the data.
static func rival_tint(backdrop_id: String) -> Color:
	return RIVAL_TINTS.get(backdrop_id, Color(1, 1, 1))


## Shows backdrop `backdrop_id`'s layers. Returns false (each missing layer reported, the
## backdrop left as it was) when any layer's art cannot be loaded.
func show_backdrop(backdrop_id: String) -> bool:
	var textures: Dictionary[String, Texture2D] = {}
	var missing := PackedStringArray()
	for layer in Content.BACKDROP_LAYERS:
		var path := Content.backdrop_path(backdrop_id, layer)
		var texture: Texture2D = null
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		if texture == null:
			missing.append(path)
			continue
		textures[layer] = texture
	if not missing.is_empty():
		(get_node(GameState.AUTOLOAD_PATH) as GameState).report_error("Cannot show backdrop '%s': %s missing or not a texture" % [backdrop_id, ", ".join(missing)])
		return false
	for layer in textures:
		_layers[layer].texture = textures[layer]
	id = backdrop_id
	return true


## Lays the layers out for a visible area `shown` (in World coordinates: its left edge at
## `shown.position.x`) whose grass starts at `grass_top`.
func fit(shown: Rect2, grass_top: float) -> void:
	var sky := _layers["sky"]
	sky.position = shown.position
	sky.size = shown.size
	for layer: String in ["far", "near"]:
		var strip := _layers[layer]
		strip.position = Vector2(shown.position.x, FAR_TOP if layer == "far" else NEAR_TOP)
		strip.size = Vector2(shown.size.x, float(strip.texture.get_height()) if strip.texture != null else 0.0)
	var grass := _layers["grass"]
	grass.position = Vector2(shown.position.x, grass_top)
	var height := float(grass.texture.get_height()) if grass.texture != null else 0.0
	grass.size = Vector2(shown.size.x, maxf(height, shown.end.y - grass_top))
