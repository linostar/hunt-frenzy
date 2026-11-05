class_name SceneFlow
extends Node
## Game/Flow: the app flow state machine and its scene transitions. Every flow change goes
## through goto(), which covers the screen (the marsh-grass wipe, or a plain fade with reduce
## motion; touches blocked), swaps the scene, uncovers it and logs the transition
## ("[Game] goto A -> B ..." when it starts, "[Game] Arrived at B" when it is done).
## A flow state whose scene is missing, or needs a missing file, is reported with push_error
## and the visible error label instead of crashing.

## Emitted when a goto() has finished: the new scene is in place and the cover is gone.
signal transition_finished(state: Flow)

enum Flow { TITLE, PLAY, RESULTS, CHAPTER_SELECT, LEVEL_SELECT, SETTINGS, CREDITS, TOP_SCORES }

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
## Seconds the plain fade (reduce motion) takes to cover the screen, and again to clear it.
const FADE_TIME := 0.15
## Seconds the marsh-grass wipe (Wipe) takes to rise over the screen, and again to sink
## away (at most 0.4 each: plan AC 3).
const WIPE_TIME := 0.35

## Paths per flow state; tests swap one to check the missing-scene path.
var scene_paths: Dictionary[Flow, String] = SCENE_PATHS.duplicate()
## Every goto() started, "FROM -> TO (path) args=..." (tests read it).
var transition_log: Array[String] = []
var state := Flow.TITLE
## The args of the latest goto(); the new scene reads them in its _ready().
var flow_args: Dictionary = {}

var _transitioning := false
## How the current (or last) screen change covers the screen: "wipe" or "fade".
var _transition_style := ""

@onready var _game := get_parent() as GameState
@onready var _cover: ColorRect = $"../Fade/Cover"
@onready var _wipe: Wipe = $"../Fade/Cover/Wipe"


## The main scene is loaded by the engine, not by goto(); once it is in the tree,
## record and log the flow state it stands for. Tool runs (tests, the project check)
## start without a current scene and are left alone.
func announce_main_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var found: Variant = scene_paths.find_key(scene.scene_file_path)
	if found == null:
		_game.report_error("The main scene '%s' is not a flow state's scene" % scene.scene_file_path)
		return
	state = found as Flow
	print("[Game] Arrived at %s (main scene)" % Flow.keys()[state])
	_game.audio.play_music(AudioManager.track_for(state, flow_args))


## Changes to the scene of `new_state`, passing `args` through flow_args: the marsh-grass
## wipe rises over the screen (WIPE_TIME), the scene changes, then it sinks away
## (WIPE_TIME), and transition_finished fires; with reduce motion on a plain fade does the
## same (FADE_TIME each way). Logged with the style. Touches are blocked until then. Ignored (with a log
## line) while a transition is running. A scene that does not exist, or that needs a file
## that does not exist (ResourceCheck.missing_dependencies: checked before anything is
## loaded), is reported with the file named and nothing changes.
func goto(new_state: Flow, args: Dictionary = {}) -> void:
	var path: String = scene_paths[new_state]
	var from_name: String = Flow.keys()[state]
	var to_name: String = Flow.keys()[new_state]
	if _transitioning:
		print("[Game] Ignored goto %s while a transition is running" % to_name)
		return
	if not ResourceLoader.exists(path):
		_game.report_error("Cannot go to %s: scene '%s' does not exist" % [to_name, path])
		return
	var missing := ResourceCheck.missing_dependencies(path)
	var track := AudioManager.track_for(new_state, args)
	if track != "" and not ResourceLoader.exists(_game.audio.music_path % track):
		missing.append(_game.audio.music_path % track)
	if not missing.is_empty():
		_game.report_error("Cannot go to %s: scene '%s' needs %s, which %s missing" % [to_name, path, ", ".join(missing), "is" if missing.size() == 1 else "are"])
		return
	_transitioning = true
	_game.audio.play_music(track)
	_log_transition("%s -> %s (%s) args=%s" % [from_name, to_name, path, args])
	_game.hide_error()
	_start_cover()
	await _fade_to(1.0)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_game.report_error("Failed to load scene '%s' for %s: %s" % [path, to_name, error_string(error)])
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


## Starts a new Endless run with a fresh seed (the title's Endless, Restart, Play again).
func start_endless() -> void:
	start_mode(GameState.ENDLESS_MODE)


## Starts a new Time Attack run with a fresh seed (the title's Time Attack, Restart, Retry).
func start_time_attack() -> void:
	start_mode(GameState.TIME_ATTACK_MODE)


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
	_transition_style = "fade" if _game.save.reduce_motion else "wipe"
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
