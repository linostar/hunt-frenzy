class_name Results
extends Control
## Results screen of a finished run, from Game.flow_args (the stats Play passes: score,
## shots, hits, kills, pigeons, escaped, stolen, rival_score, rival_line, rival_steals,
## best, new_best, save_error; a mode's run adds mode, a campaign level adds level, stars,
## best_stars and next_level).
## Under the heading (a level's "<Chapter> i: passed|not passed", "Run over", "Time up"),
## a campaign level shows three big stars (the earned ones filled, the rest empty
## outlines), and every run shows a row of small matching panels (the theme's StatPanel):
## Score (the best beneath it: the level's or the mode's, and a "New best!" badge when
## the run beat it), Accuracy (hits / shots as a percent, a dash with no shots; a hit on
## the decoy pigeon is a shot but not a hit; an armored bird's two hits are two, with
## "H of S shots" beneath), Birds hit (kills: an armored bird counts once, with the
## escaped beneath, stolen ones included and their number in brackets in a run with
## rival steals) and Rival (his score, from his steals), shown only in a run with rival
## steals. The verdict ("you vs rival"), the pigeons hit and the rival's parting line are
## not shown; the [Results] log lines keep them. SaveError shows when saving failed (the
## run's save_error, or a later Game.save_failed: a web save that browser storage did not
## keep). Opened without run stats, the panels show dashes.
## Endless: Play again (focused on arrival, ring hidden until keyboard navigation) starts
## a new Endless run; Title goes to the title. Time Attack ("Time up", no Rival panel and
## no stolen count: its rival never steals): Retry (focused, in Play again's place) starts a
## new Time Attack run; Title goes to the title. A campaign level: Next (only when the next
## level exists and is unlocked; focused when shown) starts it, Retry plays the level
## again, Levels opens its chapter's level select with this level focused (Retry is focused
## without Next).
## Laid out in the safe area: the stars and panels are centred between the heading and
## the save error's slot above the buttons.
## Sound: the rival's parting line plays his blurt (silent while Game.HECKLE_BLURTS is off)
## (Game.play_heckle, "results"; after a run ended by his steal it waits for his laugh to
## finish); a level's earned stars each play "star", STAR_SOUND_GAP seconds apart, and a
## new best then plays "new_best". Each earned star pops in with its sound (a scale bounce,
## STAR_POP_TIME; with Game.reduce_motion it just appears at the same moment), and the
## New best badge bounces with its fanfare (not with reduce motion).

const NO_VALUE := "—"
const STAT_KEYS: Array[String] = ["score", "shots", "hits", "kills", "pigeons", "escaped", "stolen", "rival_score", "rival_line", "rival_steals", "best", "new_best", "save_error"]
## The keys a campaign level's stats add, and the key a mode's run adds.
const LEVEL_KEYS: Array[String] = ["level", "stars", "best_stars", "next_level"]
const MODE_KEYS: Array[String] = ["mode"]
const SAVE_ERROR_TEXT := "Your best could not be saved: %s. See the log for details."
const PROGRESS_SAVE_ERROR_TEXT := "Your progress could not be saved: %s. See the log for details."
const ENDLESS_HEADING := "Run over"
const TIMED_HEADING := "Time up"
## Seconds between the star sounds (and before the new best's).
const STAR_SOUND_GAP := 0.35
## A star's pop: from STAR_POP_FROM up past full size to STAR_POP_SCALE and back to 1
## over STAR_POP_TIME seconds (the badge's bounce is the same, from full size, to BADGE_POP_SCALE).
const STAR_POP_TIME := 0.3
const STAR_POP_FROM := 0.3
const STAR_POP_SCALE := 1.3
## The New best! badge's bounce peak (it sits by the next panel, so it swells less).
const BADGE_POP_SCALE := 1.15

## Earned stars popped in so far (tests), and the last pop's style ("bounce" or "plain").
var stars_popped := 0
var last_pop_style := ""

var _game: GameState
## The campaign level of these results, or null (a mode's run).
var _level: LevelSpec
## The mode of these results (Endless, Time Attack), or null (a campaign level).
var _mode: ModeSpec

@onready var _safe: Control = $Safe
@onready var _heading: Label = $Safe/Heading
@onready var _stars: Control = %Stars
@onready var _score: Label = %Score
@onready var _best: Label = %Best
@onready var _new_best: Label = %NewBest
@onready var _accuracy: Label = %Accuracy
@onready var _shots: Label = %Shots
@onready var _hits: Label = %Hits
@onready var _escaped: Label = %Escaped
@onready var _rival_panel: Control = %RivalPanel
@onready var _rival_score: Label = %RivalScore
@onready var _steals: Label = %Steals
@onready var _save_error: Label = $Safe/SaveError
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


## "Best 1500": the note under the score (the level's best, or the mode's).
static func best_text(best: int) -> String:
	return "Best %d" % best


## "3 of 4 shots" under the accuracy; "no shots" without any.
static func shots_text(hits: int, shots: int) -> String:
	return "%d of %d shots" % [hits, shots] if shots > 0 else "no shots"


## "5 escaped (2 stolen)" under the birds hit in a run with rival steals, else "5 escaped".
static func escaped_text(escaped: int, stolen: int, rival_steals: bool) -> String:
	return "%d escaped (%d stolen)" % [escaped, stolen] if rival_steals else "%d escaped" % escaped


## "from 2 steals" (or "from 1 steal") under the rival's score.
static func steals_text(stolen: int) -> String:
	return "from %d steal%s" % [stolen, "" if stolen == 1 else "s"]


## The number of filled stars showing (popped in so far).
func stars_shown() -> int:
	return _star_slots().filter(func(slot: Control) -> bool: return (slot.get_node("Full") as CanvasItem).visible).size()


func _star_slots() -> Array[Control]:
	var slots: Array[Control] = []
	for child in _stars.get_children():
		slots.append(child as Control)
	return slots


func _show_stats(stats: Dictionary) -> void:
	var keys: Array[String] = STAT_KEYS.duplicate()
	keys.append_array(LEVEL_KEYS if stats.has("level") else MODE_KEYS)
	for key in keys:
		if not stats.has(key):
			# Opened without a finished run (the project check, the editor's Run Current Scene).
			print("[Results] Opened without run stats (missing '%s')" % key)
			for label: Label in [_score, _accuracy, _hits]:
				label.text = NO_VALUE
			for label: Label in [_shots, _escaped]:
				label.text = ""
			_best.text = best_text(_game.best(GameState.ENDLESS_MODE))
			_new_best.hide()
			_rival_panel.hide()
			_show_buttons([_play_again_button, _title_button])
			return
	_level = Content.level(str(stats["level"])) if stats.has("level") and Content.has_level(str(stats["level"])) else null
	if stats.has("level") and _level == null:
		_game.report_error("Results of an unknown level '%s'" % stats["level"])
	if stats.has("mode"):
		_mode = Content.mode(str(stats["mode"])) if Content.modes().any(func(spec: ModeSpec) -> bool: return spec.id == str(stats["mode"])) else null
		if _mode == null:
			_game.report_error("Results of an unknown mode '%s'" % stats["mode"])
	_score.text = str(stats["score"])
	_best.text = best_text(stats["best"])
	_accuracy.text = accuracy_text(stats["hits"], stats["shots"])
	_shots.text = shots_text(stats["hits"], stats["shots"])
	_hits.text = str(stats["kills"])
	_escaped.text = escaped_text(stats["escaped"], stats["stolen"], stats["rival_steals"])
	_rival_panel.visible = stats["rival_steals"]
	_rival_score.text = str(stats["rival_score"])
	_steals.text = steals_text(stats["stolen"])
	_new_best.visible = stats["new_best"]
	if _level != null:
		var chapter_spec := Content.chapter(_level.chapter)
		_heading.text = "%s %d: %s" % [chapter_spec.name, _level.index, "passed" if Campaign.is_passed(stats["stars"]) else "not passed"]
		_stars.show()
		var buttons: Array[Button] = [_retry_button, _levels_button]
		if stats["next_level"] != "":
			buttons.push_front(_next_button)
		_show_buttons(buttons)
	elif _mode != null and _mode.is_timed():
		_heading.text = TIMED_HEADING
		# Retry takes Play again's place beside Title.
		_retry_button.offset_left = _play_again_button.offset_left
		_retry_button.offset_right = _play_again_button.offset_right
		_show_buttons([_retry_button, _title_button])
	else:
		_heading.text = ENDLESS_HEADING
		_show_buttons([_play_again_button, _title_button])
	# A web save can fail during the fade here, before save_failed is connected.
	var save_error: String = stats["save_error"] if stats["save_error"] != "" else (_game.save_error if stats["new_best"] or _level != null else "")
	if save_error != "":
		_show_save_error(save_error)
	print("[Results] Score %d, accuracy %s (%d of %d shots), %d birds hit, %d escaped, %d stolen, rival score %d, %d pigeons hit, best %d%s; rival: \"%s\"" % [
		stats["score"], accuracy_text(stats["hits"], stats["shots"]), stats["hits"], stats["shots"], stats["kills"], stats["escaped"], stats["stolen"], stats["rival_score"], stats["pigeons"], stats["best"], ", new best" if stats["new_best"] else "", stats["rival_line"]])
	if stats["rival_steals"]:
		print("[Results] Verdict: %s" % verdict_text(stats["score"], stats["rival_score"]))
	if _mode != null:
		print("[Results] Mode %s: best %d%s" % [_mode.id, stats["best"], ", new best" if stats["new_best"] else ""])
	if _level != null:
		print("[Results] Level %s: %d stars, best %d (%d stars), next %s" % [_level.id, stats["stars"], stats["best"], stats["best_stars"], stats["next_level"] if stats["next_level"] != "" else "none open"])
	_play_sounds(stats["rival_line"], stats["stars"] if _level != null else 0, stats["new_best"])


## The results' sounds: the rival's blurt for `rival_line` at once, then `stars` star sounds
## and the new best's fanfare (when `new_best`), STAR_SOUND_GAP seconds apart.
func _play_sounds(rival_line: String, stars: int, new_best: bool) -> void:
	_game.play_heckle("results", rival_line)
	if stars == 0 and not new_best:
		return
	var tween := create_tween()
	for i in stars:
		tween.tween_interval(STAR_SOUND_GAP)
		tween.tween_callback(_game.play_sfx.bind(&"star"))
		tween.tween_callback(_pop_star.bind(i, stars))
	if new_best:
		tween.tween_interval(STAR_SOUND_GAP)
		tween.tween_callback(_game.play_sfx.bind(&"new_best"))
		tween.tween_callback(_bounce_badge)


## Shows earned star `index` (0-based) of `earned`, with a bounce unless reduce motion is on.
func _pop_star(index: int, earned: int) -> void:
	var full := _star_slots()[index].get_node("Full") as Control
	full.show()
	stars_popped += 1
	last_pop_style = "plain" if _game.reduce_motion else "bounce"
	print("[Results] Star %d of %d pops in (%s)" % [index + 1, earned, "no bounce: reduce motion" if _game.reduce_motion else "bounce"])
	if _game.reduce_motion:
		full.scale = Vector2.ONE
		return
	full.scale = Vector2.ONE * STAR_POP_FROM
	_bounce(full, STAR_POP_FROM, STAR_POP_SCALE)


## The New best badge's bounce with its fanfare (none with reduce motion).
func _bounce_badge() -> void:
	if not _game.reduce_motion and _new_best.visible:
		_bounce(_new_best, 1.0, BADGE_POP_SCALE)


func _bounce(item: Control, from: float, peak: float) -> void:
	item.pivot_offset = item.size / 2.0
	item.scale = Vector2.ONE * from
	var tween := create_tween()
	tween.tween_property(item, "scale", Vector2.ONE * peak, STAR_POP_TIME * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", Vector2.ONE, STAR_POP_TIME * 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
