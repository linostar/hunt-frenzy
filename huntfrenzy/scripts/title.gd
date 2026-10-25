class_name Title
extends Control
## Title screen (placeholder until the art pass): the game's name, a tagline and the
## Play button, laid out in the safe area (Game ScreenFit) and refitted whenever it
## changes. Play is focused on arrival (without drawing the focus ring until the
## player navigates by keyboard), so Enter presses it; pressing it starts an Endless
## run (Game.start_endless). When Content reports errors in data/*.json, the
## ContentErrorBanner says so and Play is disabled.

const CONTENT_ERROR_MESSAGE := "Content error: %d problem(s) in data/*.json, see the log. Play is disabled."

## Times Play has been pressed on this screen (tests and the smoke test read the log).
var play_presses := 0

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _play_button: Button = $Safe/PlayButton
@onready var _banner: Label = $Safe/ContentErrorBanner


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_fit()
	_play_button.pressed.connect(_on_play_pressed)
	var content_errors := Content.errors()
	if not content_errors.is_empty():
		print("[Title] Content has %d problem(s); Play is disabled" % content_errors.size())
		_banner.text = CONTENT_ERROR_MESSAGE % content_errors.size()
		_banner.show()
		_play_button.disabled = true
	_play_button.grab_focus(true)


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Containers and anchors settle at the end of the frame; log the button's final rect
	# (base units) for the smoke test, which taps it.
	_log_layout.call_deferred()


func _log_layout() -> void:
	print("[Title] Play button at %s" % _play_button.get_global_rect())


func _on_play_pressed() -> void:
	play_presses += 1
	print("[Title] Play pressed (%d); starting Endless" % play_presses)
	_game.start_endless()
