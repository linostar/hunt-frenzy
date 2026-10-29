class_name Credits
extends Control
## The credits screen (the title's Credits button): who made the game, the engine and its
## licence, the two fonts with their licence and the copyright lines of their OFL files
## (ui/fonts/*-OFL.txt, which ship beside them) as a bulleted list, and the recordings
## (tools/sfx.py RECORDINGS), each credited to its author: the rival's laugh (CC0,
## OpenGameArt) and the bird calls (CC0 and public domain, Wikimedia Commons). The heading,
## MADE_BY and Back are centred; the credit lines are a left-aligned block (Lines, one
## Label per line, a bulleted line an HBox of its bullet and its text, so a wrapped line
## indents under the text, not the bullet). It fits the safe area at every supported aspect
## down to a safe height of 470 (no scrolling). Back (focused on arrival) or Escape returns
## to the title with its Credits button focused.

const MADE_BY := "Made by linostar"
## The credit lines under MADE_BY, in order; a line starting with BULLET is a list item.
const LINES: Array[String] = [
	"Built with Godot Engine (MIT license)",
	"Copyright (c) 2014-present Godot Engine contributors; (c) 2007-2014 Juan Linietsky, Ariel Manzur",
	"Fonts, under the SIL Open Font License 1.1:",
	"• Lilita One: Copyright (c) 2011 Juan Montoreano (juan@remolacha.biz), with Reserved Font Name Lilita",
	"• Nunito: Copyright 2014 The Nunito Project Authors (https://github.com/googlefonts/nunito)",
	"The rival's laugh: \"evil laugh\" by WeaponGuy (OpenGameArt), CC0.",
	"Bird calls via Wikimedia Commons: Bert76 (CC0),",
	"Oona Räisänen and the U.S. Fish and Wildlife Service (public domain).",
]
const BULLET := "• "
## The credit lines' font size, and the gap between a bullet and its text.
const LINE_FONT_SIZE := 18
const BULLET_GAP := 6
## A bulleted line's indent under the line that introduces the list.
const BULLET_INDENT := 18
## Game.flow_args "focus" the title reads to focus its Credits button again.
const TITLE_FOCUS := "credits"

var _game: GameState

@onready var _safe: Control = $Safe
@onready var _made_by: Label = $Safe/MadeBy
@onready var _lines: VBoxContainer = $Safe/Lines
@onready var _back_button: Button = $Safe/BackButton
@onready var _cancel_key: CancelKey = $CancelKey


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_made_by.text = MADE_BY
	for line in LINES:
		_lines.add_child(_line_node(line))
	_back_button.pressed.connect(_on_back_pressed)
	_cancel_key.triggered.connect(_on_back_pressed)
	_fit()
	_back_button.grab_focus(true)
	print("[Credits] Opened: %s, %d credit lines" % [MADE_BY, LINES.size()])


## The text of every credit line shown, one per line (tests).
func lines_text() -> String:
	var texts: PackedStringArray = []
	for label: Label in line_labels():
		texts.append(label.text)
	return "\n".join(texts)


## The Labels of the credit lines (a bulleted line's text, not its bullet).
func line_labels() -> Array[Label]:
	var labels: Array[Label] = []
	for label: Node in _lines.find_children("*", "Label", true, false):
		if not label.is_in_group(&"credits_bullet"):
			labels.append(label as Label)
	return labels


## A left-aligned, wrapping Label for `line`; a BULLET line becomes its bullet beside it,
## indented by BULLET_INDENT, so wrapped text hangs under the text.
func _line_node(line: String) -> Control:
	var text := _line_label(line.trim_prefix(BULLET))
	if not line.begins_with(BULLET):
		return text
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", BULLET_GAP)
	var bullet := _line_label(BULLET.strip_edges())
	bullet.autowrap_mode = TextServer.AUTOWRAP_OFF
	bullet.add_to_group(&"credits_bullet")
	row.add_child(bullet)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var indent := MarginContainer.new()
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_theme_constant_override(&"margin_left", BULLET_INDENT)
	indent.add_child(row)
	return indent


func _line_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", LINE_FONT_SIZE)
	return label


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
