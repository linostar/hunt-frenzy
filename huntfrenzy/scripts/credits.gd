class_name Credits
extends Control
## The credits screen (the title's Credits button): who made the game, the engine and its
## licence, the two fonts with their licence and the copyright lines of their OFL files
## (ui/fonts/*-OFL.txt, which ship beside them), and that every piece of art and audio is
## original, generated as code for this game, but for the rival's laugh, a CC0 recording
## credited to its author (tools/sfx.py LAUGH_SOURCE). It fits the safe area at every supported
## aspect down to a safe height of 470 (no scrolling). Back (focused on arrival) or Escape
## returns to the title with its Credits button focused.

const MADE_BY := "Made by linostar"
## The credit lines under MADE_BY, in order.
const LINES: Array[String] = [
	"Built with Godot Engine (MIT license)",
	"Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur",
	"Fonts: Lilita One and Nunito, under the SIL Open Font License 1.1",
	"Lilita One: Copyright (c) 2011 Juan Montoreano (juan@remolacha.biz), with Reserved Font Name Lilita",
	"Nunito: Copyright 2014 The Nunito Project Authors (https://github.com/googlefonts/nunito)",
	"All art, music and sound effects are original, generated as code for this game,",
	"except the rival's laugh: \"evil laugh\" by WeaponGuy (OpenGameArt), CC0 public domain.",
]
## Game.flow_args "focus" the title reads to focus its Credits button again.
const TITLE_FOCUS := "credits"

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _made_by: Label = $Safe/MadeBy
@onready var _lines: Label = $Safe/Lines
@onready var _back_button: Button = $Safe/BackButton
@onready var _cancel_key: CancelKey = $CancelKey


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_made_by.text = MADE_BY
	_lines.text = "\n".join(LINES)
	_back_button.pressed.connect(_on_back_pressed)
	_cancel_key.triggered.connect(_on_back_pressed)
	_fit()
	_back_button.grab_focus(true)
	print("[Credits] Opened: %s, %d credit lines" % [MADE_BY, LINES.size()])


func _fit() -> void:
	var safe := _game.safe_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# Anchors settle at the end of the frame; log Back's final rect for the smoke test.
	_log_layout.call_deferred()


func _log_layout() -> void:
	if is_inside_tree():
		print("[Credits] Back button at %s" % _back_button.get_global_rect())


func _on_back_pressed() -> void:
	print("[Credits] Back pressed; returning to the title")
	_game.goto(GameState.Flow.TITLE, {"focus": TITLE_FOCUS})
