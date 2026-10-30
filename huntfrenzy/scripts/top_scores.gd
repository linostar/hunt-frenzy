class_name TopScores
extends Control
## The top scores screen (the title's Top Scores button): the best score of each mode
## (Endless, Time Attack; Game.best) in a row of panels (the theme's StatPanel, StatCaption
## and StatValue, as on the results), and under them one panel per campaign chapter
## (data/chapters.json, in order) with a tiny star image beside the stars earned in it out
## of its levels x 3 ("12/18"). It fits the safe area at every supported aspect down to a
## safe height of 470. Back (focused on arrival, ring hidden until keyboard navigation) or
## Escape returns to the title with its Top Scores button focused. Logs the values shown and
## Back's rect (base units), which the smoke test taps.

## The stars in a chapter's panel: earned / most.
const STARS_TEXT := "%d/%d"
## A chapter panel's width and its star image's side.
const CHAPTER_PANEL_WIDTH := 200.0
const STAR_SIDE := 34.0
## Game.flow_args "focus" the title reads to focus its Top Scores button again.
const TITLE_FOCUS := "top_scores"

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _endless: Label = %EndlessBest
@onready var _time_attack: Label = %TimeAttackBest
@onready var _chapters: HBoxContainer = %Chapters
@onready var _back_button: Button = $Safe/BackButton
@onready var _cancel_key: CancelKey = $CancelKey


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_endless.text = str(_game.best(GameState.ENDLESS_MODE))
	_time_attack.text = str(_game.best(GameState.TIME_ATTACK_MODE))
	var shown := PackedStringArray()
	for spec in Content.chapters():
		var most := Campaign.chapter_levels(spec.id).size() * Campaign.MAX_STARS
		var stars := STARS_TEXT % [Campaign.chapter_stars(spec.id, _game.progress), most]
		_chapters.add_child(_chapter_panel(spec, stars))
		shown.append("%s %s" % [spec.id, stars])
	_back_button.pressed.connect(_on_back_pressed)
	_cancel_key.triggered.connect(_on_back_pressed)
	_fit()
	_back_button.grab_focus(true)
	print("[TopScores] Opened: Endless best %s, Time Attack best %s; chapter stars %s" % [_endless.text, _time_attack.text, ", ".join(shown)])


## Every chapter's stars as shown, in order ("dawn 2/18"; tests).
func chapter_stars_text() -> Array[String]:
	var texts: Array[String] = []
	for panel in _chapters.get_children():
		texts.append("%s %s" % [panel.name, (panel.get_node("Box/Row/Stars") as Label).text])
	return texts


## A StatPanel captioned with the chapter's name over its star image and `stars`.
func _chapter_panel(spec: ChapterSpec, stars: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = spec.id
	panel.theme_type_variation = &"StatPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(CHAPTER_PANEL_WIDTH, 0)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 0)
	panel.add_child(box)
	var caption := Label.new()
	caption.theme_type_variation = &"StatCaption"
	caption.text = spec.name.to_upper()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 8)
	box.add_child(row)
	row.add_child(ChapterSkin.icon(ChapterSkin.STAR_FULL, STAR_SIDE, "Star"))
	var value := Label.new()
	value.name = "Stars"
	value.theme_type_variation = &"StatValue"
	value.text = stars
	row.add_child(value)
	return panel


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Anchors settle at the end of the frame; log Back's final rect for the smoke test.
	_log_layout.call_deferred()


func _log_layout() -> void:
	if is_inside_tree():
		print("[TopScores] Back button at %s" % _back_button.get_global_rect())


func _on_back_pressed() -> void:
	print("[TopScores] Back pressed; returning to the title")
	_game.goto(GameState.Flow.TITLE, {"focus": TITLE_FOCUS})
