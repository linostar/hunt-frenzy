class_name ChapterSelect
extends Control
## Chapter select (Title's Campaign): the campaign's chapters (data/chapters.json, in
## order) as one button each with the stars earned in it out of its levels x 3; a chapter
## whose level 1 is still locked shows "Locked" and its button is disabled, so neither a
## touch, a click nor Enter starts it. A chapter opens its level select; Back goes to the
## title. On arrival the chapter just left (Game.flow_args {"chapter": id}, from the level
## select's Back) is focused when it is open, else the last unlocked chapter (ring hidden
## until keyboard navigation). Laid out in the safe area; every refit logs each button's
## rect (base units), which the smoke test taps.

const OPEN_TEXT := "%s\n%d/%d stars"
const LOCKED_TEXT := "%s\nLocked"

var _game: GameState
var _chapters: Array[ChapterSpec] = []

@onready var _safe: Control = $Safe
@onready var _buttons: Array[Button] = [$Safe/Chapter1, $Safe/Chapter2, $Safe/Chapter3, $Safe/Chapter4]
@onready var _back_button: Button = $Safe/BackButton


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_chapters = Content.chapters()
	if _chapters.size() != _buttons.size():
		_game.report_error("Chapter select has %d chapter buttons for %d chapters" % [_buttons.size(), _chapters.size()])
	var focus := _back_button
	var left := str(_game.flow_args.get("chapter", ""))
	var returned: Button = null
	for i in _buttons.size():
		var button := _buttons[i]
		if i >= _chapters.size():
			button.hide()
			continue
		var spec := _chapters[i]
		var open := Campaign.is_chapter_unlocked(spec.id, _game.progress)
		var most := Campaign.chapter_levels(spec.id).size() * Campaign.MAX_STARS
		button.text = OPEN_TEXT % [spec.name, Campaign.chapter_stars(spec.id, _game.progress), most] if open else LOCKED_TEXT % spec.name
		button.disabled = not open
		button.pressed.connect(_on_chapter_pressed.bind(spec.id))
		if open:
			focus = button
			if spec.id == left:
				returned = button
	_back_button.pressed.connect(_on_back_pressed)
	_fit()
	(returned if returned != null else focus).grab_focus(true)


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Anchors settle at the end of the frame; log the buttons' final rects then.
	_log_layout.call_deferred()


func _log_layout() -> void:
	for i in mini(_buttons.size(), _chapters.size()):
		var spec := _chapters[i]
		print("[ChapterSelect] Chapter %s at %s (%s, %d stars)" % [spec.id, _buttons[i].get_global_rect(), "locked" if _buttons[i].disabled else "open", Campaign.chapter_stars(spec.id, _game.progress)])


func _on_chapter_pressed(chapter_id: String) -> void:
	if not Campaign.is_chapter_unlocked(chapter_id, _game.progress):
		print("[ChapterSelect] Chapter %s is locked; nothing starts" % chapter_id)
		return
	print("[ChapterSelect] Chapter %s pressed; opening its levels" % chapter_id)
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": chapter_id})


func _on_back_pressed() -> void:
	print("[ChapterSelect] Back pressed")
	_game.goto(GameState.Flow.TITLE)
