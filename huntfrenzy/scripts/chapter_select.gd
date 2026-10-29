class_name ChapterSelect
extends Control
## Chapter select (Title's Campaign): the campaign's chapters (data/chapters.json, in
## order) as one button each, dressed in its sky (ChapterSkin: its backdrop's sky gradient,
## a label colour that reads on it), with the chapter's name over a tiny star image and the
## stars earned in it out of its levels x 3 ("12/18"); a chapter whose level 1 is still
## locked shows its name over a lock icon, its sky dimmed, and its button is disabled, so
## neither a touch, a click nor Enter starts it. A chapter opens its level select; Back goes to the
## title. On arrival the chapter just left (Game.flow_args {"chapter": id}, from the level
## select's Back) is focused when it is open, else the last unlocked chapter (ring hidden
## until keyboard navigation). Laid out in the safe area; every refit logs each button's
## rect (base units), which the smoke test taps.

## The stars under an open chapter's name: earned / most.
const STARS_TEXT := "%d/%d"
## The caption's margins (left, top, right, bottom): the name sits above the star row.
const CAPTION_MARGINS := Vector4(10, 8, 10, 58)
## The star row, from DETAIL_TOP to DETAIL_BOTTOM above the button's bottom edge.
const DETAIL_TOP := 62.0
const DETAIL_BOTTOM := 18.0
const STAR_SIDE := 30.0
const LOCK_SIDE := 38.0
const COUNT_FONT_SIZE := 26

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
		button.text = spec.name
		button.disabled = not open
		ChapterSkin.apply(button, spec.backdrop, CAPTION_MARGINS)
		var row := ChapterSkin.detail_row(button, DETAIL_TOP, DETAIL_BOTTOM)
		if open:
			row.add_child(ChapterSkin.icon(ChapterSkin.STAR_FULL, STAR_SIDE, "Star"))
			var count := ChapterSkin.label(STARS_TEXT % [Campaign.chapter_stars(spec.id, _game.progress), most], spec.backdrop, COUNT_FONT_SIZE)
			count.name = "Count"
			row.add_child(count)
		else:
			row.add_child(ChapterSkin.icon(ChapterSkin.LOCK, LOCK_SIDE, "Lock"))
		button.pressed.connect(_on_chapter_pressed.bind(spec.id))
		if open:
			focus = button
			if spec.id == left:
				returned = button
	_back_button.pressed.connect(_on_back_pressed)
	_fit()
	(returned if returned != null else focus).grab_focus(true)


## What chapter button `index` shows under its name: "12/18" for an open chapter (beside
## its star image), "locked" for one showing the lock (tests).
func detail_text(index: int) -> String:
	var row := _buttons[index].get_node_or_null("Detail")
	if row == null:
		return ""
	if row.has_node("Lock"):
		return "locked"
	return (row.get_node("Count") as Label).text if row.has_node("Star") else ""


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
