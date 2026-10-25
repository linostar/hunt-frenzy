class_name Results
extends Control
## Results screen of a finished run, from Game.flow_args (the stats Play passes: score,
## shots, hits, kills, pigeons, escaped, stolen, rival_score, rival_line, best, new_best):
## score, accuracy (hits / shots, a
## dash with no shots; a hit on the decoy pigeon is a shot but not a hit; an armored bird's
## two hits are two), birds hit (kills: an armored bird counts once), birds
## escaped (stolen ones included), birds stolen by the rival, the rival's score, pigeons hit
## (the decoy) and the Endless best, the rival's parting line at the bottom, with "New best!" when the run
## beat it, and SaveError ("Your best could not be saved: <reason>") when saving that
## best failed (the run's save_error, or a later Game.save_failed: a web save that browser
## storage did not keep). Play again (focused on arrival, ring hidden until keyboard navigation)
## starts a new Endless run; Title goes to the title. Laid out in the safe area.

const NO_VALUE := "—"
const STAT_KEYS: Array[String] = ["score", "shots", "hits", "kills", "pigeons", "escaped", "stolen", "rival_score", "rival_line", "best", "new_best", "save_error"]
const RIVAL_LINE_TEXT := "Rival: \"%s\""
const SAVE_ERROR_TEXT := "Your best could not be saved: %s. See the log for details."

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _score: Label = $Safe/Stats/Score
@onready var _accuracy: Label = $Safe/Stats/Accuracy
@onready var _hits: Label = $Safe/Stats/Hits
@onready var _escaped: Label = $Safe/Stats/Escaped
@onready var _stolen: Label = $Safe/Stats/Stolen
@onready var _rival_score: Label = $Safe/Stats/RivalScore
@onready var _pigeons: Label = $Safe/Stats/Pigeons
@onready var _best: Label = $Safe/Stats/Best
@onready var _new_best: Label = $Safe/NewBest
@onready var _save_error: Label = $Safe/SaveError
@onready var _rival_line: Label = $Safe/RivalLine
@onready var _play_again_button: Button = $Safe/PlayAgainButton
@onready var _title_button: Button = $Safe/TitleButton


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_fit()
	_play_again_button.pressed.connect(_on_play_again_pressed)
	_title_button.pressed.connect(_on_title_pressed)
	_game.save_failed.connect(_show_save_error)
	_show_stats(_game.flow_args)
	_play_again_button.grab_focus(true)


## "75%" for 3 hits in 4 shots; NO_VALUE with no shots.
static func accuracy_text(hits: int, shots: int) -> String:
	if shots <= 0:
		return NO_VALUE
	return "%d%%" % roundi(100.0 * hits / shots)


func _show_stats(stats: Dictionary) -> void:
	for key in STAT_KEYS:
		if not stats.has(key):
			# Opened without a finished run (the project check, the editor's Run Current Scene).
			print("[Results] Opened without run stats (missing '%s')" % key)
			for label: Label in [_score, _accuracy, _hits, _escaped, _stolen, _rival_score, _pigeons]:
				label.text += " " + NO_VALUE
			_best.text += " %d" % _game.best_endless
			_new_best.hide()
			return
	_score.text += " %d" % stats["score"]
	_accuracy.text += " " + accuracy_text(stats["hits"], stats["shots"])
	_hits.text += " %d" % stats["kills"]
	_escaped.text += " %d" % stats["escaped"]
	_stolen.text += " %d" % stats["stolen"]
	_rival_score.text += " %d" % stats["rival_score"]
	_rival_line.text = RIVAL_LINE_TEXT % stats["rival_line"]
	_rival_line.show()
	_pigeons.text += " %d" % stats["pigeons"]
	_best.text += " %d" % stats["best"]
	_new_best.visible = stats["new_best"]
	# A web save can fail during the fade here, before save_failed is connected.
	var save_error: String = stats["save_error"] if stats["save_error"] != "" else (_game.save_error if stats["new_best"] else "")
	if save_error != "":
		_show_save_error(save_error)
	print("[Results] Score %d, accuracy %s (%d of %d shots), %d birds hit, %d escaped, %d stolen, rival score %d, %d pigeons hit, best %d%s; rival: \"%s\"" % [
		stats["score"], accuracy_text(stats["hits"], stats["shots"]), stats["hits"], stats["shots"], stats["kills"], stats["escaped"], stats["stolen"], stats["rival_score"], stats["pigeons"], stats["best"], ", new best" if stats["new_best"] else "", stats["rival_line"]])


func _show_save_error(reason: String) -> void:
	_save_error.text = SAVE_ERROR_TEXT % reason
	_save_error.show()
	print("[Results] Showing that the best was not saved: %s" % reason)


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
