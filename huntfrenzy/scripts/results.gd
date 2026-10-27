class_name Results
extends Control
## Results screen of a finished run, from Game.flow_args (the stats Play passes: score,
## shots, hits, kills, pigeons, escaped, stolen, rival_score, rival_line, rival_steals,
## best, new_best, save_error; a mode's run adds mode, a campaign level adds level, stars,
## best_stars and next_level): score, accuracy (hits / shots, a dash with no shots; a hit
## on the decoy pigeon is a shot but not a hit; an armored bird's two hits are two), birds
## hit (kills: an armored bird counts once), birds escaped (stolen ones included, their
## number in brackets in a run with rival steals), the "you vs rival" verdict (score
## against the rival's score: win, lose or tie) in every run with rival steals, pigeons
## hit (the decoy) and the best (the mode's: "Endless best 100", "Time Attack best 900";
## or the level's best score and stars), the rival's parting line at the bottom,
## with "New best!" when the run beat it, and SaveError when saving failed (the run's
## save_error, or a later Game.save_failed: a web save that browser storage did not keep).
## A campaign level also shows the stars earned (0: not passed).
## Endless: Play again (focused on arrival, ring hidden until keyboard navigation) starts
## a new Endless run; Title goes to the title. Time Attack ("Time up", no verdict and no
## stolen count: its rival never steals): Retry (focused, in Play again's place) starts a
## new Time Attack run; Title goes to the title. A campaign level: Next (only when the next
## level exists and is unlocked; focused when shown) starts it, Retry plays the level
## again, Levels opens its chapter's level select with this level focused (Retry is focused
## without Next).
## Laid out in the safe area.
## Sound: the rival's parting line plays his blurt (Game.play_heckle, "results"); a level's
## stars each play "star", STAR_SOUND_GAP seconds apart, and a new best then plays "new_best".

const NO_VALUE := "—"
const STAT_KEYS: Array[String] = ["score", "shots", "hits", "kills", "pigeons", "escaped", "stolen", "rival_score", "rival_line", "rival_steals", "best", "new_best", "save_error"]
## The keys a campaign level's stats add, and the key a mode's run adds.
const LEVEL_KEYS: Array[String] = ["level", "stars", "best_stars", "next_level"]
const MODE_KEYS: Array[String] = ["mode"]
const RIVAL_LINE_TEXT := "Rival: \"%s\""
const SAVE_ERROR_TEXT := "Your best could not be saved: %s. See the log for details."
const PROGRESS_SAVE_ERROR_TEXT := "Your progress could not be saved: %s. See the log for details."
const ENDLESS_HEADING := "Run over"
const TIMED_HEADING := "Time up"
## Seconds between the star sounds (and before the new best's).
const STAR_SOUND_GAP := 0.35

var _game: GameState
## The campaign level of these results, or null (a mode's run).
var _level: LevelSpec
## The mode of these results (Endless, Time Attack), or null (a campaign level).
var _mode: ModeSpec

@onready var _safe: Control = $Safe
@onready var _heading: Label = $Safe/Heading
@onready var _score: Label = $Safe/Stats/Score
@onready var _stars: Label = $Safe/Stats/Stars
@onready var _accuracy: Label = $Safe/Stats/Accuracy
@onready var _hits: Label = $Safe/Stats/Hits
@onready var _escaped: Label = $Safe/Stats/Escaped
@onready var _verdict: Label = $Safe/Stats/Verdict
@onready var _pigeons: Label = $Safe/Stats/Pigeons
@onready var _best: Label = $Safe/Stats/Best
@onready var _new_best: Label = $Safe/NewBest
@onready var _save_error: Label = $Safe/SaveError
@onready var _rival_line: Label = $Safe/RivalLine
@onready var _play_again_button: Button = $Safe/PlayAgainButton
@onready var _title_button: Button = $Safe/TitleButton
@onready var _next_button: Button = $Safe/NextButton
@onready var _retry_button: Button = $Safe/RetryButton
@onready var _levels_button: Button = $Safe/LevelsButton


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_fit()
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_next_button.pressed.connect(_on_next_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_levels_button.pressed.connect(_on_levels_pressed)
	_game.save_failed.connect(_show_save_error)
	_show_stats(_game.flow_args)


## "75%" for 3 hits in 4 shots; NO_VALUE with no shots.
static func accuracy_text(hits: int, shots: int) -> String:
	if shots <= 0:
		return NO_VALUE
	return "%d%%" % roundi(100.0 * hits / shots)


## The "you vs rival" verdict of a run: a win when `score` beats `rival_score`, a loss
## when it is below, a tie when they are equal.
static func verdict_text(score: int, rival_score: int) -> String:
	var outcome := "you win!" if score > rival_score else ("the rival wins" if score < rival_score else "a tie")
	return "You %d vs rival %d: %s" % [score, rival_score, outcome]


## "2 of 3 stars" (or "0 stars: not passed") for a level's results.
static func stars_text(earned: int) -> String:
	if not Campaign.is_passed(earned):
		return "0 stars: not passed"
	return "%d of %d stars" % [earned, Campaign.MAX_STARS]


func _show_stats(stats: Dictionary) -> void:
	var keys: Array[String] = STAT_KEYS.duplicate()
	keys.append_array(LEVEL_KEYS if stats.has("level") else MODE_KEYS)
	for key in keys:
		if not stats.has(key):
			# Opened without a finished run (the project check, the editor's Run Current Scene).
			print("[Results] Opened without run stats (missing '%s')" % key)
			for label: Label in [_score, _accuracy, _hits, _escaped, _pigeons]:
				label.text += " " + NO_VALUE
			_best.text = "Endless best %d" % _game.best(GameState.ENDLESS_MODE)
			_new_best.hide()
			_show_buttons([_play_again_button, _title_button])
			return
	_level = Content.level(str(stats["level"])) if stats.has("level") and Content.has_level(str(stats["level"])) else null
	if stats.has("level") and _level == null:
		_game.report_error("Results of an unknown level '%s'" % stats["level"])
	if stats.has("mode"):
		_mode = Content.mode(str(stats["mode"])) if Content.modes().any(func(spec: ModeSpec) -> bool: return spec.id == str(stats["mode"])) else null
		if _mode == null:
			_game.report_error("Results of an unknown mode '%s'" % stats["mode"])
	_score.text += " %d" % stats["score"]
	_accuracy.text += " " + accuracy_text(stats["hits"], stats["shots"])
	_hits.text += " %d" % stats["kills"]
	_escaped.text += " %d (%d stolen)" % [stats["escaped"], stats["stolen"]] if stats["rival_steals"] else " %d" % stats["escaped"]
	_verdict.visible = stats["rival_steals"]
	_verdict.text = verdict_text(stats["score"], stats["rival_score"])
	_rival_line.text = RIVAL_LINE_TEXT % stats["rival_line"]
	_rival_line.show()
	_pigeons.text += " %d" % stats["pigeons"]
	_new_best.visible = stats["new_best"]
	if _level != null:
		var chapter_spec := Content.chapter(_level.chapter)
		_heading.text = "%s %d: %s" % [chapter_spec.name, _level.index, "passed" if Campaign.is_passed(stats["stars"]) else "not passed"]
		_stars.text = stars_text(stats["stars"])
		_stars.show()
		_best.text = "Level best %d (%d of %d stars)" % [stats["best"], stats["best_stars"], Campaign.MAX_STARS]
		var buttons: Array[Button] = [_retry_button, _levels_button]
		if stats["next_level"] != "":
			buttons.push_front(_next_button)
		_show_buttons(buttons)
	elif _mode != null and _mode.is_timed():
		_heading.text = TIMED_HEADING
		_best.text = "%s best %d" % [_mode.name, stats["best"]]
		# Retry takes Play again's place beside Title.
		_retry_button.offset_left = _play_again_button.offset_left
		_retry_button.offset_right = _play_again_button.offset_right
		_show_buttons([_retry_button, _title_button])
	else:
		_heading.text = ENDLESS_HEADING
		_best.text = "%s best %d" % [_mode.name if _mode != null else str(stats["mode"]), stats["best"]]
		_show_buttons([_play_again_button, _title_button])
	# A web save can fail during the fade here, before save_failed is connected.
	var save_error: String = stats["save_error"] if stats["save_error"] != "" else (_game.save_error if stats["new_best"] or _level != null else "")
	if save_error != "":
		_show_save_error(save_error)
	print("[Results] Score %d, accuracy %s (%d of %d shots), %d birds hit, %d escaped, %d stolen, rival score %d, %d pigeons hit, best %d%s; rival: \"%s\"" % [
		stats["score"], accuracy_text(stats["hits"], stats["shots"]), stats["hits"], stats["shots"], stats["kills"], stats["escaped"], stats["stolen"], stats["rival_score"], stats["pigeons"], stats["best"], ", new best" if stats["new_best"] else "", stats["rival_line"]])
	if stats["rival_steals"]:
		print("[Results] Verdict: %s" % _verdict.text)
	if _mode != null:
		print("[Results] Mode %s: best %d%s" % [_mode.id, stats["best"], ", new best" if stats["new_best"] else ""])
	if _level != null:
		print("[Results] Level %s: %d stars, best %d (%d stars), next %s" % [_level.id, stats["stars"], stats["best"], stats["best_stars"], stats["next_level"] if stats["next_level"] != "" else "none open"])
	_play_sounds(stats["rival_line"], stats["stars"] if _level != null else 0, stats["new_best"])


## The results' sounds: the rival's blurt for `rival_line` at once, then `stars` star sounds
## and the new best's fanfare (when `new_best`), STAR_SOUND_GAP seconds apart.
func _play_sounds(rival_line: String, stars: int, new_best: bool) -> void:
	_game.play_heckle("results", rival_line)
	var sounds: Array[StringName] = []
	for i in stars:
		sounds.append(&"star")
	if new_best:
		sounds.append(&"new_best")
	if sounds.is_empty():
		return
	var tween := create_tween()
	for sound in sounds:
		tween.tween_interval(STAR_SOUND_GAP)
		tween.tween_callback(_game.play_sfx.bind(sound))


## Shows `buttons` (hiding the other mode's), chains their focus (left/right and Tab wrap
## around) and focuses the first without showing its ring.
func _show_buttons(buttons: Array[Button]) -> void:
	for button: Button in [_play_again_button, _title_button, _next_button, _retry_button, _levels_button]:
		button.visible = button in buttons
	for i in buttons.size():
		var after := buttons[(i + 1) % buttons.size()]
		var before := buttons[(i - 1 + buttons.size()) % buttons.size()]
		buttons[i].focus_neighbor_right = buttons[i].get_path_to(after)
		buttons[i].focus_next = buttons[i].get_path_to(after)
		buttons[i].focus_neighbor_left = buttons[i].get_path_to(before)
		buttons[i].focus_previous = buttons[i].get_path_to(before)
	buttons[0].grab_focus(true)


func _show_save_error(reason: String) -> void:
	_save_error.text = (PROGRESS_SAVE_ERROR_TEXT if _level != null else SAVE_ERROR_TEXT) % reason
	_save_error.show()
	print("[Results] Showing that the %s was not saved: %s" % ["progress" if _level != null else "best", reason])


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size


func _on_play_again_pressed() -> void:
	print("[Results] Play again pressed")
	_game.start_endless()


func _on_title_pressed() -> void:
	print("[Results] Title pressed")
	_game.goto(GameState.Flow.TITLE)


func _on_next_pressed() -> void:
	var next := Campaign.next_level(_level)
	if next == null or not Campaign.is_unlocked(next, _game.progress):
		_game.report_error("Next pressed after %s, but no next level is open" % _level.id)
		return
	print("[Results] Next pressed: starting %s" % next.id)
	_game.start_level(next.id)


func _on_retry_pressed() -> void:
	if _level == null:
		print("[Results] Retry pressed: starting %s again" % _mode.id)
		_game.start_mode(_mode.id)
		return
	print("[Results] Retry pressed: starting %s again" % _level.id)
	_game.start_level(_level.id)


func _on_levels_pressed() -> void:
	print("[Results] Levels pressed: opening chapter %s" % _level.chapter)
	_game.goto(GameState.Flow.LEVEL_SELECT, {"chapter": _level.chapter, "level": _level.id})
