class_name GameState
extends Node
## Autoload "Game" (scenes/game.tscn): a thin facade over the app's services, each a child
## node with its own script:
## - flow (SceneFlow, Game/Flow): the flow state machine and goto()'s screen transitions;
## - save (SaveStore, Game/Save): the versioned save, its migrations and backups, and the
##   bests, campaign progress and settings it holds;
## - audio (AudioManager, Game/Audio): sound effects, the music loops,
##   pause ducking and the bus volumes;
## - screen (ScreenFit, Game/Screen): the visible and safe rects, the window fit and the
##   rotate overlay;
## - web (WebPersist, Game/Web): the web build's browser-storage checks and page visibility.
## It also holds the feel tuning (tuning: data/tuning.tres) every scene reads.
## Game itself starts them in order (_ready), checks the UI theme at start (ResourceCheck)
## and owns the error label every service reports through (report_error).

## Absolute path of this autoload, for nodes inside the tree.
const AUTOLOAD_PATH := ^"/root/Game"
## The Endless and Time Attack modes' ids in data/modes.json.
const ENDLESS_MODE := "endless"
const TIME_ATTACK_MODE := "time_attack"

## The feel tuning (Tuning.PATH): Play, its controllers, the title, the feathers and the wipe read it here.
var tuning: Tuning = load(Tuning.PATH) as Tuning

## Tests set this to keep expected errors out of the log; they are still recorded
## and shown on the error label.
var quiet_errors := false
var reported_errors: Array[String] = []
## The UI theme check_ui_theme last checked ("" before any; at start, the project's).
var checked_theme := ""

@onready var flow: SceneFlow = $Flow
@onready var save: SaveStore = $Save
@onready var audio: AudioManager = $Audio
@onready var screen: ScreenFit = $Screen
@onready var web: WebPersist = $Web
@onready var _error_label: Label = $Fade/ErrorLabel


func _ready() -> void:
	audio.setup()
	# Tool runs (the tests, the project check, the headless main-scene run) drive the
	# tree from a SceneTree script; they must never read or overwrite the player's save.
	if get_tree().get_script() != null:
		save.save_path = SaveStore.TOOL_SAVE_PATH
	if OS.has_feature("web"):
		web.check_storage(OS.is_userfs_persistent())
	save.load_game()
	check_ui_theme(ProjectSettings.get_setting(ResourceCheck.THEME_SETTING, ""))
	audio.check_audio()
	web.watch_page_visibility()
	screen.start()
	flow.announce_main_scene.call_deferred()


## Reports every problem with the UI theme at `path` and its fonts (ResourceCheck.theme_problems:
## the log and the error label), or logs the fonts it uses; returns whether it had none. Run
## at start for the project's theme (ResourceCheck.THEME_SETTING); public for tests.
func check_ui_theme(path: String) -> bool:
	checked_theme = path
	var problems := ResourceCheck.theme_problems(path)
	for problem in problems:
		report_error(problem)
	if problems.is_empty():
		print("[Game] UI theme %s loaded with its fonts: %s" % [path, ", ".join(ResourceCheck.theme_font_files(load(path) as Theme))])
	return problems.is_empty()


## Reports an error the player must see: the log (push_error unless quiet_errors), the
## error label and reported_errors.
func report_error(message: String) -> void:
	reported_errors.append(message)
	_error_label.text = message
	_error_label.show()
	if not quiet_errors:
		push_error("[Game] " + message)


## Clears the error label (a new screen starts without the last one's error).
func hide_error() -> void:
	_error_label.hide()
