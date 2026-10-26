class_name Title
extends Control
## Title screen (placeholder until the art pass): the game's name, a tagline and the
## Campaign and Endless buttons side by side, laid out in the safe area (Game ScreenFit)
## and refitted whenever it changes. Campaign is focused on arrival (without drawing the
## focus ring until the player navigates by keyboard), so Enter presses it; it opens the
## chapter select, Endless starts an Endless run (Game.start_endless). When Content reports
## errors in data/*.json, the ContentErrorBanner says so and both buttons are disabled.

const CONTENT_ERROR_MESSAGE := "Content error: %d problem(s) in data/*.json, see the log. Play is disabled."

## Times Campaign and Endless have been pressed on this screen (tests and the smoke test
## read the log).
var campaign_presses := 0
var endless_presses := 0

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _campaign_button: Button = $Safe/CampaignButton
@onready var _endless_button: Button = $Safe/EndlessButton
@onready var _banner: Label = $Safe/ContentErrorBanner


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_fit()
	_campaign_button.pressed.connect(_on_campaign_pressed)
	_endless_button.pressed.connect(_on_endless_pressed)
	var content_errors := Content.errors()
	if not content_errors.is_empty():
		print("[Title] Content has %d problem(s); Campaign and Endless are disabled" % content_errors.size())
		_banner.text = CONTENT_ERROR_MESSAGE % content_errors.size()
		_banner.show()
		_campaign_button.disabled = true
		_endless_button.disabled = true
	_campaign_button.grab_focus(true)


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Containers and anchors settle at the end of the frame; log the buttons' final rects
	# (base units) for the smoke test, which taps them.
	_log_layout.call_deferred()


func _log_layout() -> void:
	print("[Title] Campaign button at %s" % _campaign_button.get_global_rect())
	print("[Title] Endless button at %s" % _endless_button.get_global_rect())


func _on_campaign_pressed() -> void:
	campaign_presses += 1
	print("[Title] Campaign pressed (%d); opening the chapter select" % campaign_presses)
	_game.goto(GameState.Flow.CHAPTER_SELECT)


func _on_endless_pressed() -> void:
	endless_presses += 1
	print("[Title] Endless pressed (%d); starting Endless" % endless_presses)
	_game.start_endless()
