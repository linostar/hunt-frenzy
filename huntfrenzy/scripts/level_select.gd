class_name LevelSelect
extends Control
## Level select of one chapter (Game.flow_args {"chapter": id}): its levels by index as one
## button each with the best stars and best score earned (or "New" for one never finished,
## "Boss" on the boss level); a locked level shows "Locked" and its button is disabled, so
## neither a touch, a click nor Enter starts it. A level starts it (Game.start_level);
## Back goes to the chapter select. The last unlocked level is focused on arrival (ring
## hidden until keyboard navigation). Laid out in the safe area; every refit logs each
## button's rect (base units), which the smoke test taps.

const LEVEL_TEXT := "Level %d%s\n%s"
const BOSS_NOTE := " (boss)"
const NEW_TEXT := "New"
const LOCKED_TEXT := "Locked"
const RECORD_TEXT := "%d/%d stars, best %d"
const HEADING_TEXT := "%s: %d/%d stars"

var chapter: ChapterSpec

var _game: GameState
var _levels: Array[LevelSpec] = []

@onready var _safe: Control = $Safe
@onready var _heading: Label = $Safe/Heading
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
	_heading.text = HEADING_TEXT % [chapter.name, Campaign.chapter_stars(chapter_id, _game.progress), _levels.size() * Campaign.MAX_STARS]
	var focus := _back_button
	for i in _buttons.size():
		var button := _buttons[i]
		if i >= _levels.size():
			button.hide()
			continue
		var level := _levels[i]
		var open := Campaign.is_unlocked(level, _game.progress)
		var record: Campaign.Record = _game.progress.get(level.id)
		var detail := LOCKED_TEXT if not open else (NEW_TEXT if record == null else RECORD_TEXT % [record.stars, Campaign.MAX_STARS, record.score])
		button.text = LEVEL_TEXT % [level.index, BOSS_NOTE if level.is_boss() else "", detail]
		button.disabled = not open
		button.pressed.connect(_on_level_pressed.bind(level.id))
		if open:
			focus = button
	_back_button.pressed.connect(_on_back_pressed)
	_fit()
	focus.grab_focus(true)


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
	_game.goto(GameState.Flow.CHAPTER_SELECT)
