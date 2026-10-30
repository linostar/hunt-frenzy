class_name LevelSelect
extends Control
## Level select of one chapter (Game.flow_args {"chapter": id}): its levels by index as one
## button each, dressed in the chapter's sky like its chapter select button (ChapterSkin),
## captioned "Level X" over three star images, full for each best star earned and empty
## for the rest (three empty for a level never finished); the boss level carries a small
## skull badge in its corner; no score is shown (the results show it). A locked level shows
## a lock icon instead of the stars, its sky dimmed, and its button is disabled, so
## neither a touch, a click nor Enter starts it. The heading is the chapter's name with a
## tiny star image and the stars earned out of the most ("2/18"). A level starts it (Game.start_level);
## Back goes to the chapter select (focusing this chapter there). On arrival the level just
## left (Game.flow_args {"level": id}, from the results' Levels) is focused when it is
## open, else the last unlocked level (ring hidden until keyboard navigation). Laid out in
## the safe area; every refit logs each button's rect (base units), which the smoke test
## taps.

const LEVEL_TEXT := "Level %d"
## The heading's stars beside its star image: earned / most.
const HEADING_STARS_TEXT := "%d/%d"
## The caption's margins (left, top, right, bottom): "Level X" sits above the star row.
const CAPTION_MARGINS := Vector4(10, 6, 10, 48)
## The star row, from DETAIL_TOP to DETAIL_BOTTOM above the button's bottom edge.
const DETAIL_TOP := 52.0
const DETAIL_BOTTOM := 14.0
const STAR_SIDE := 36.0
const LOCK_SIDE := 36.0
## The boss level's skull badge: its side and its inset from the top right corner.
const SKULL_SIDE := 34.0
const SKULL_INSET := 8.0

var chapter: ChapterSpec

var _game: GameState
var _levels: Array[LevelSpec] = []

@onready var _safe: Control = $Safe
@onready var _heading: Label = $Safe/Heading/Name
@onready var _heading_count: Label = $Safe/Heading/Count
@onready var _buttons: Array[Button] = [$Safe/Level1, $Safe/Level2, $Safe/Level3, $Safe/Level4, $Safe/Level5, $Safe/Level6]
@onready var _back_button: Button = $Safe/BackButton


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	var chapter_id := str(_game.flow_args.get("chapter", ""))
	if chapter_id == "":
		# Opened without a goto (the project check, the editor's Run Current Scene).
		chapter_id = Content.chapters()[0].id
		print("[LevelSelect] Opened without a chapter; showing %s" % chapter_id)
	elif Content.chapters().all(func(spec: ChapterSpec) -> bool: return spec.id != chapter_id):
		_game.report_error("Level select opened for an unknown chapter '%s'; showing %s" % [chapter_id, Content.chapters()[0].id])
		chapter_id = Content.chapters()[0].id
	chapter = Content.chapter(chapter_id)
	_levels = Campaign.chapter_levels(chapter_id)
	if _levels.size() != _buttons.size():
		_game.report_error("Level select has %d level buttons for %d levels of %s" % [_buttons.size(), _levels.size(), chapter_id])
	_heading.text = chapter.name
	_heading_count.text = HEADING_STARS_TEXT % [Campaign.chapter_stars(chapter_id, _game.progress), _levels.size() * Campaign.MAX_STARS]
	var focus := _back_button
	var left := str(_game.flow_args.get("level", ""))
	var returned: Button = null
	for i in _buttons.size():
		var button := _buttons[i]
		if i >= _levels.size():
			button.hide()
			continue
		var level := _levels[i]
		var open := Campaign.is_unlocked(level, _game.progress)
		var record: Campaign.Record = _game.progress.get(level.id)
		button.text = LEVEL_TEXT % level.index
		button.disabled = not open
		ChapterSkin.apply(button, chapter.backdrop, CAPTION_MARGINS)
		var row := ChapterSkin.detail_row(button, DETAIL_TOP, DETAIL_BOTTOM)
		if open:
			var earned := record.stars if record != null else 0
			for star in Campaign.MAX_STARS:
				row.add_child(ChapterSkin.icon(ChapterSkin.STAR_FULL if star < earned else ChapterSkin.STAR_EMPTY, STAR_SIDE, "Star%d" % (star + 1)))
		else:
			row.add_child(ChapterSkin.icon(ChapterSkin.LOCK, LOCK_SIDE, "Lock"))
		if level.is_boss():
			var skull := ChapterSkin.icon(ChapterSkin.SKULL, SKULL_SIDE, "Boss")
			skull.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			skull.offset_left = -SKULL_INSET - SKULL_SIDE
			skull.offset_top = SKULL_INSET
			skull.offset_right = -SKULL_INSET
			skull.offset_bottom = SKULL_INSET + SKULL_SIDE
			button.add_child(skull)
		button.pressed.connect(_on_level_pressed.bind(level.id))
		if open:
			focus = button
			if level.id == left:
				returned = button
	_back_button.pressed.connect(_on_back_pressed)
	_fit()
	(returned if returned != null else focus).grab_focus(true)


## The full stars level button `index` shows (0..3), or -1 when it shows the lock (tests).
func stars_shown(index: int) -> int:
	var row := _buttons[index].get_node("Detail")
	if row.has_node("Lock"):
		return -1
	var full := 0
	for star in Campaign.MAX_STARS:
		if (row.get_node("Star%d" % (star + 1)) as TextureRect).texture == ChapterSkin.STAR_FULL:
			full += 1
	return full


## Whether level button `index` carries the boss skull badge (tests).
func has_boss_badge(index: int) -> bool:
	return _buttons[index].has_node("Boss")


## The heading as read: the chapter's name and its stars ("Dawn 2/18"; tests).
func heading_text() -> String:
	return "%s %s" % [_heading.text, _heading_count.text]


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Anchors settle at the end of the frame; log the buttons' final rects then.
	_log_layout.call_deferred()


func _log_layout() -> void:
	for i in mini(_buttons.size(), _levels.size()):
		var level := _levels[i]
		var record: Campaign.Record = _game.progress.get(level.id)
		print("[LevelSelect] Level %s at %s (%s, %d stars, best %d)" % [level.id, _buttons[i].get_global_rect(), "locked" if _buttons[i].disabled else "open",
			record.stars if record != null else 0, record.score if record != null else 0])


func _on_level_pressed(level_id: String) -> void:
	if not Campaign.is_unlocked(Content.level(level_id), _game.progress):
		print("[LevelSelect] Level %s is locked; nothing starts" % level_id)
		return
	print("[LevelSelect] Level %s pressed; starting it" % level_id)
	_game.start_level(level_id)


func _on_back_pressed() -> void:
	print("[LevelSelect] Back pressed")
	_game.goto(GameState.Flow.CHAPTER_SELECT, {"chapter": chapter.id})
