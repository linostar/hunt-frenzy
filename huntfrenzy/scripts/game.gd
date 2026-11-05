class_name GameState
extends Node
## Autoload "Game" (scenes/game.tscn): the app flow state machine and its scene
## transitions, the save (the best score of each mode, the campaign progress and the settings),
## ScreenFit (the visible and safe-area rects in base units) and the rotate overlay.
## Every flow change goes through goto(), which covers the screen (the marsh-grass wipe, or
## a plain fade with reduce motion; touches blocked), swaps the scene, uncovers it and logs
## the transition
## ("[Game] goto A -> B ..." when it starts, "[Game] Arrived at B" when it is done).
## A flow state whose scene is missing is reported with push_error and the visible
## error label instead of crashing.
## The game is landscape only: while the visible area is taller than it is wide the
## rotate overlay ("Rotate your phone") covers everything and the tree is paused;
## once it is landscape again the overlay hides and the tree is unpaused, unless it
## was already paused before the overlay showed. While it shows, GUI input (touches and
## keys) is disabled.
## The save is versioned JSON at save_path, loaded at start: a missing save starts fresh,
## an older version is upgraded step by step (save_migrations, logged), a corrupt or
## unknown-version one is moved to backup_path(), reported (log and error label) and
## replaced by a fresh save. A campaign entry naming a level that is not in levels.json, or
## holding stars or a score out of range, is dropped (each logged with its stored value);
## the rest of the save loads, the original file is first copied to a free
## dropped_backup_path() (never over another backup), and only then is the save written
## back without the dropped entries; the error label says how many were dropped and where
## the original is. If the copy fails, the save is not written back (the original stays).
## A failed save sets save_error (a short reason the results screen shows), is reported
## and emits save_failed. On the web, user:// is an
## in-memory filesystem that Godot copies to IndexedDB asynchronously, ignoring a failed
## copy; so a web save is logged as written, then confirmed (or reported as lost) by
## reading it back from IndexedDB (WEB_PERSIST_CHECK_JS), and storage that is unavailable
## at start (OS.is_userfs_persistent() false) is reported at once.
## At start the UI theme (project.godot gui/theme/custom) and its fonts are checked: a theme
## or font file that is missing or cannot be loaded is reported (log and error label) with
## the file named (theme_problems), never left to a silent fallback; goto() reports a scene
## that needs a missing file by name before loading it (missing_dependencies).
## Audio: every sound goes through play_sfx(id) (audio/sfx/<id>.wav, tools/sfx.py), which
## logs "[Audio] SFX <id>" and plays it on the SFX bus from a pool of SFX_VOICES players;
## every Button's press plays "ui_tap" unless it is in OWN_SOUND_GROUP (it plays its own).
## A heckle plays a gibberish blurt (play_heckle: blurt_plan strings the rival's syllables,
## seeded by the line, pitched and voiced by the category). play_sfx_later plays a sound a
## moment from now (the rival's laugh after his shot), on the same clock as the blurts; a
## blurt asked for while such a sound is queued or playing waits until it has finished (the
## rival never talks over his own laugh, the results' parting line included). The music is one loop per
## screen (track_for: the title's for the title, the selects, the settings, the
## credits and the top scores, the chapter's or the mode's in a run, the results' on results) on the Music
## bus: goto() asks for it as the
## transition starts, a screen with the same loop leaves it playing, another crossfades in
## over CROSSFADE_TIME, and every change is logged ("[Audio] Music <track>"). The saved
## volumes and mutes set the Music and SFX buses at start and on every change. While the
## tree is paused (the pause menu, the rotate overlay) the sounds in flight are held and the
## music is ducked by PAUSE_DUCK_DB (sync_audio_pause); sounds started during the pause (the
## menu's own) play on a reserved menu voice, so a held sound is never taken over, and
## everything held continues when the tree runs again. A missing or
## unloadable sound or loop is reported with its path (log and error label); goto() refuses
## a screen whose loop is missing, as it does a scene's missing file. Browsers start audio
## only after the player's first touch or key: Godot's web platform resumes its
## AudioContext then, and until then the title loop waits silently.

## Emitted when a goto() has finished: the new scene is in place and the cover is gone.
signal transition_finished(state: Flow)

enum Flow { TITLE, PLAY, RESULTS, CHAPTER_SELECT, LEVEL_SELECT, SETTINGS, CREDITS, TOP_SCORES }

## Absolute path of this autoload, for nodes inside the tree.
const AUTOLOAD_PATH := ^"/root/Game"
const SCENE_PATHS: Dictionary[Flow, String] = {
	Flow.TITLE: "res://scenes/title.tscn",
	Flow.PLAY: "res://scenes/play.tscn",
	Flow.RESULTS: "res://scenes/results.tscn",
	Flow.CHAPTER_SELECT: "res://scenes/chapter_select.tscn",
	Flow.LEVEL_SELECT: "res://scenes/level_select.tscn",
	Flow.SETTINGS: "res://scenes/settings.tscn",
	Flow.CREDITS: "res://scenes/credits.tscn",
	Flow.TOP_SCORES: "res://scenes/top_scores.tscn",
}
## The Endless and Time Attack modes' ids in data/modes.json.
const ENDLESS_MODE := "endless"
const TIME_ATTACK_MODE := "time_attack"
## Seconds the plain fade (reduce motion) takes to cover the screen, and again to clear it.
const FADE_TIME := 0.15
## Seconds the marsh-grass wipe (Wipe) takes to rise over the screen, and again to sink
## away (at most 0.4 each: plan AC 3).
const WIPE_TIME := 0.35
## Paths per flow state; tests swap one to check the missing-scene path.
var scene_paths: Dictionary[Flow, String] = SCENE_PATHS.duplicate()
## Tests set this to keep expected errors out of the log; they are still recorded
## and shown on the error label.
var quiet_errors := false
var reported_errors: Array[String] = []
## Every goto() started, "FROM -> TO (path) args=..." (tests read it).
var transition_log: Array[String] = []
var state := Flow.TITLE
## The args of the latest goto(); the new scene reads them in its _ready().
var flow_args: Dictionary = {}
## The UI theme check_ui_theme last checked ("" before any; at start, the project's).
var checked_theme := ""

var _transitioning := false
## How the current (or last) screen change covers the screen: "wipe" or "fade".
var _transition_style := ""

@onready var _cover: ColorRect = $Fade/Cover
@onready var _wipe: Wipe = $Fade/Cover/Wipe
@onready var _error_label: Label = $Fade/ErrorLabel
@onready var screen: ScreenFit = $Screen
@onready var web: WebPersist = $Web
@onready var save: SaveStore = $Save
@onready var audio: AudioManager = $Audio


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
	_announce_main_scene.call_deferred()


## The main scene is loaded by the engine, not by goto(); once it is in the tree,
## record and log the flow state it stands for. Tool runs (tests, the project check)
## start without a current scene and are left alone.
func _announce_main_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var found: Variant = scene_paths.find_key(scene.scene_file_path)
	if found == null:
		report_error("The main scene '%s' is not a flow state's scene" % scene.scene_file_path)
		return
	state = found as Flow
	print("[Game] Arrived at %s (main scene)" % Flow.keys()[state])
	audio.play_music(AudioManager.track_for(state, flow_args))


## Changes to the scene of `new_state`, passing `args` through flow_args: the marsh-grass
## wipe rises over the screen (WIPE_TIME), the scene changes, then it sinks away
## (WIPE_TIME), and transition_finished fires; with reduce motion on a plain fade does the
## same (FADE_TIME each way). Logged with the style. Touches are blocked until then. Ignored (with a log
## line) while a transition is running. A scene that does not exist, or that needs a file
## that does not exist (missing_dependencies: checked before anything is loaded), is
## reported with the file named and nothing changes.
func goto(new_state: Flow, args: Dictionary = {}) -> void:
	var path: String = scene_paths[new_state]
	var from_name: String = Flow.keys()[state]
	var to_name: String = Flow.keys()[new_state]
	if _transitioning:
		print("[Game] Ignored goto %s while a transition is running" % to_name)
		return
	if not ResourceLoader.exists(path):
		report_error("Cannot go to %s: scene '%s' does not exist" % [to_name, path])
		return
	var missing := ResourceCheck.missing_dependencies(path)
	var track := AudioManager.track_for(new_state, args)
	if track != "" and not ResourceLoader.exists(audio.music_path % track):
		missing.append(audio.music_path % track)
	if not missing.is_empty():
		report_error("Cannot go to %s: scene '%s' needs %s, which %s missing" % [to_name, path, ", ".join(missing), "is" if missing.size() == 1 else "are"])
		return
	_transitioning = true
	audio.play_music(track)
	_log_transition("%s -> %s (%s) args=%s" % [from_name, to_name, path, args])
	_error_label.hide()
	_start_cover()
	await _fade_to(1.0)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		report_error("Failed to load scene '%s' for %s: %s" % [path, to_name, error_string(error)])
		await _fade_to(0.0)
		_end_fade()
		return
	state = new_state
	flow_args = args
	# The new scene enters the tree (and runs its _ready) at the end of this frame.
	await get_tree().scene_changed
	await _fade_to(0.0)
	_end_fade()
	print("[Game] Arrived at %s" % to_name)
	transition_finished.emit(new_state)


## Reports every problem with the UI theme at `path` and its fonts (theme_problems: the log
## and the error label), or logs the fonts it uses; returns whether it had none. Run at
## start for the project's theme (THEME_SETTING); public for tests.
func check_ui_theme(path: String) -> bool:
	checked_theme = path
	var problems := ResourceCheck.theme_problems(path)
	for problem in problems:
		report_error(problem)
	if problems.is_empty():
		print("[Game] UI theme %s loaded with its fonts: %s" % [path, ", ".join(ResourceCheck.theme_font_files(load(path) as Theme))])
	return problems.is_empty()


## Starts a new Endless run with a fresh seed (the title's Endless, Restart, Play again).
func start_endless() -> void:
	start_mode(ENDLESS_MODE)


## Starts a new Time Attack run with a fresh seed (the title's Time Attack, Restart, Retry).
func start_time_attack() -> void:
	start_mode(TIME_ATTACK_MODE)


## Starts a new run of mode `mode_id` (modes.json) with a fresh seed.
func start_mode(mode_id: String) -> void:
	goto(Flow.PLAY, {"mode": mode_id, "seed": randi()})


## Starts campaign level `level_id` (level select, Restart, Next and Retry); the level's
## own fixed seed drives it.
func start_level(level_id: String) -> void:
	goto(Flow.PLAY, {"level": level_id})


func is_transitioning() -> bool:
	return _transitioning


## How far the cover hides the screen: 0 clear, 1 covered (tests read it): the wipe's
## coverage, or the fade's alpha.
func cover_progress() -> float:
	if not _cover.visible:
		return 0.0
	return _wipe.coverage() if _transition_style == "wipe" else _cover.modulate.a


## The style of the current (or last) screen change: "wipe", or "fade" with reduce motion.
func transition_style() -> String:
	return _transition_style


## Shows the cover (it stops touches) for a screen change in the style reduce_motion asks
## for: the wipe draws the grass over an invisible cover, the fade fades the cover's colour.
func _start_cover() -> void:
	_transition_style = "fade" if save.reduce_motion else "wipe"
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.show()
	if _transition_style == "wipe":
		_cover.modulate.a = 1.0
		_cover.self_modulate.a = 0.0
		_wipe.progress = 0.0
		_wipe.show()
		print("[Game] Transition: marsh-grass wipe, %.2f s in and %.2f s out" % [WIPE_TIME, WIPE_TIME])
	else:
		_cover.modulate.a = 0.0
		_cover.self_modulate.a = 1.0
		_wipe.hide()
		print("[Game] Transition: plain fade, %.2f s in and %.2f s out (reduce motion)" % [FADE_TIME, FADE_TIME])


## Covers the screen (`amount` 1) or clears it (0): the wipe rises or sinks away, the fade
## fades in or out.
func _fade_to(amount: float) -> void:
	var tween := create_tween()
	if _transition_style == "wipe":
		tween.tween_property(_wipe, "progress", 1.0 if amount > 0.0 else 2.0, WIPE_TIME)
	else:
		tween.tween_property(_cover, "modulate:a", amount, FADE_TIME)
	await tween.finished


func _end_fade() -> void:
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.hide()
	_cover.modulate.a = 0.0
	_wipe.hide()
	_wipe.progress = 0.0
	_transitioning = false


func _log_transition(entry: String) -> void:
	transition_log.append(entry)
	print("[Game] goto " + entry)


## Reports an error the player must see: the log (push_error unless quiet_errors), the
## error label and reported_errors.
func report_error(message: String) -> void:
	reported_errors.append(message)
	_error_label.text = message
	_error_label.show()
	if not quiet_errors:
		push_error("[Game] " + message)
