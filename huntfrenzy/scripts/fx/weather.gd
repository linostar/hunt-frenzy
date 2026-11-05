class_name Weather
extends Node2D
## The play scene's weather (Content.WEATHERS): one CPUParticles2D child per weather (Mist,
## Wind, Rain, Snow), each with a fixed particle count of at most PARTICLES_MAX, so the
## cost is bounded on the Compatibility renderer. It is purely visual: it reads nothing
## from the run and nothing reads it (no bird's flight, hitbox or timing depends on it),
## and Play draws it behind the birds (after the backdrop's back layers, before the Birds
## node, under the grass's z_index). set_weather() starts one weather (the others stop
## emitting, so their last particles drift out) or none (""); an unknown id is reported.

## The most particles any one weather emits at once.
const PARTICLES_MAX := 120

## The weather emitting ("" for none).
var id := ""

@onready var _emitters: Dictionary[String, CPUParticles2D] = {"mist": $Mist, "wind": $Wind, "rain": $Rain, "snow": $Snow}


## Starts weather `weather_id` ("" stops all). Returns false (reported, nothing changed)
## for an id that is not one of Content.WEATHERS.
func set_weather(weather_id: String) -> bool:
	if weather_id != "" and not _emitters.has(weather_id):
		(get_node(GameState.AUTOLOAD_PATH) as GameState).report_error("Unknown weather '%s' (expected one of %s)" % [weather_id, Content.WEATHERS])
		return false
	for weather_name in _emitters:
		_emitters[weather_name].emitting = weather_name == weather_id
	id = weather_id
	return true


## The emitter of `weather_id` (tests read its particle count and draw order).
func emitter(weather_id: String) -> CPUParticles2D:
	return _emitters.get(weather_id)


## Spreads the emitters across the visible area `shown` (World coordinates): rain and snow
## fall from above its top, the wind blows in from its left edge, the mist drifts low over
## the marsh.
func fit(shown: Rect2) -> void:
	var middle := shown.position.x + shown.size.x / 2.0
	for falling: String in ["rain", "snow"]:
		_emitters[falling].position = Vector2(middle, -20.0)
		_emitters[falling].emission_rect_extents = Vector2(shown.size.x / 2.0 + 60.0, 10.0)
	_emitters["wind"].position = Vector2(shown.position.x - 20.0, 250.0)
	_emitters["mist"].position = Vector2(middle, 360.0)
	_emitters["mist"].emission_rect_extents = Vector2(shown.size.x / 2.0 + 80.0, 50.0)
