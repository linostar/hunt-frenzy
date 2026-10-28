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
## moment from now (the rival's laugh after his shot), on the same clock as the blurts. The music is one loop per
## screen (track_for: the title's for the title, the selects, the settings and the
## credits, the chapter's or the mode's in a run, the results' on results) on the Music
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
## Emitted when the visible or safe rect changes (window resize, rotation).
signal screen_fit_changed
## Emitted when the rotate overlay shows (true) or hides (false).
signal rotate_overlay_changed(shown: bool)
## Emitted when the web page becomes hidden (another tab, the app sent to the background).
## Godot's web build reports window blur but not page visibility, so Game watches the
## document's visibilitychange event itself.
signal page_hidden
## Emitted when a save fails: at once, or on the web when browser storage does not keep
## it. `reason` is save_error.
signal save_failed(reason: String)
## Emitted when a volume or mute setting changes (the pause menu's toggles follow it).
signal audio_settings_changed
## Emitted when the reduce motion setting changes (the settings screen follows it).
signal reduce_motion_changed(on: bool)

enum Flow { TITLE, PLAY, RESULTS, CHAPTER_SELECT, LEVEL_SELECT, SETTINGS, CREDITS }

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
}
## The Endless and Time Attack modes' ids in data/modes.json.
const ENDLESS_MODE := "endless"
const TIME_ATTACK_MODE := "time_attack"
const SAVE_PATH := "user://save.json"
## The save of tool runs (see _ready); tests delete it when they finish.
const TOOL_SAVE_PATH := "user://tool_save.json"
## The save format's version. Every change to the format bumps it and appends one step to
## save_migrations(), so saves of older versions are upgraded, not discarded; a newer
## version is backed up and replaced.
const SAVE_VERSION := 4
## The keys of a save, each with the type its value must have. `bests` maps each of
## BEST_MODES to its best score; `levels` maps a level id to {"stars", "score"} (its
## Campaign.Record); `settings` holds SETTINGS_KEYS.
const SAVE_KEYS: Dictionary[String, Variant.Type] = {"version": TYPE_INT, "bests": TYPE_DICTIONARY, "levels": TYPE_DICTIONARY, "settings": TYPE_DICTIONARY}
## The modes the save keeps a best score for (bests), exactly these.
const BEST_MODES: Array[String] = [ENDLESS_MODE, TIME_ATTACK_MODE]
const SAVE_SCORE_MAX := 999999999
## The most backups of saves with dropped campaign entries (dropped_backup_path).
const DROPPED_BACKUPS_MAX := 20
## The keys of a saved level entry.
const LEVEL_KEYS: Array[String] = ["stars", "score"]
## The saved settings: the music and sound effects volumes (whole 0..VOLUME_MAX), their mutes
## and reduce_motion (true or false). The settings screen changes them; the volumes and mutes
## set the audio buses, reduce_motion turns off the screen shake, the transition wipe (a
## plain fade instead), the pop-ups' bounce and shake and the title's drift.
const SETTINGS_KEYS: Array[String] = ["music", "sfx", "music_muted", "sfx_muted", "reduce_motion"]
const VOLUME_SETTINGS: Array[String] = ["music", "sfx"]
const VOLUME_MAX := 100
const DEFAULT_MUSIC_VOLUME := 70
const DEFAULT_SFX_VOLUME := 80
## The largest whole number a float holds exactly (2^53); see _is_whole.
const SAVE_EXACT_MAX := 9007199254740992.0
## How long browser storage (IndexedDB) is given to hold a web save before it is
## reported as lost.
const WEB_PERSIST_TIMEOUT_MSEC := 5000
## Defines window.huntFrenzyCheckPersisted(dbName, key, expected, timeoutMs, check, done).
## Godot 4.7.1's web template mounts user:// as Emscripten IDBFS (database = the mount
## path, store FILE_DATA, key = the file's full path, value {timestamp, mode, contents})
## and syncs it after a file is written; a failed sync only logs "Failed to save IDB file
## system". This polls that store every 250 ms until `key` holds `expected`, then calls
## done(check, 1, milliseconds taken); on an IndexedDB error or after timeoutMs it calls
## done(check, 0, reason), also when IndexedDB never answers (one overall deadline;
## done is called exactly once). It never creates or changes the database.
const WEB_PERSIST_CHECK_JS := """
window.huntFrenzyCheckPersisted = function (dbName, key, expected, timeoutMs, check, done) {
	const started = Date.now();
	let last = 'nothing stored yet';
	let finished = false;
	const finish = (ok, detail) => { if (!finished) { finished = true; clearTimeout(deadline); done(check, ok, detail); } };
	const deadline = setTimeout(() => finish(0, 'not stored after ' + timeoutMs + ' ms (' + last + ')'), timeoutMs);
	const retry = () => { if (!finished) setTimeout(poll, 250); };
	const poll = () => {
		if (finished) return;
		let request;
		try { request = indexedDB.open(dbName); } catch (e) { finish(0, 'cannot open IndexedDB: ' + e); return; }
		request.onupgradeneeded = (e) => e.target.transaction.abort();
		request.onerror = (e) => { e.preventDefault(); finish(0, 'cannot open IndexedDB ' + dbName + ': ' + (request.error ? request.error.name + ' ' + request.error.message : 'unknown error')); };
		request.onsuccess = () => {
			const db = request.result;
			let get;
			try { get = db.transaction(['FILE_DATA'], 'readonly').objectStore('FILE_DATA').get(key); } catch (e) { db.close(); finish(0, 'cannot read IndexedDB: ' + e); return; }
			get.onerror = (e) => { e.preventDefault(); db.close(); finish(0, 'cannot read ' + key + ': ' + (get.error ? get.error.name + ' ' + get.error.message : 'unknown error')); };
			get.onsuccess = () => {
				db.close();
				const entry = get.result;
				if (finished) return;
				if (entry && entry.contents && new TextDecoder().decode(entry.contents) === expected) { finish(1, String(Date.now() - started)); return; }
				last = entry ? 'an older save is stored' : 'nothing stored yet';
				retry();
			};
		};
	};
	poll();
};
"""
## The base viewport (project.godot display/window/size): the playfield is laid out
## in it and is never cropped (aspect expand only adds room).
const BASE_SIZE := Vector2(960, 540)
## Seconds the plain fade (reduce motion) takes to cover the screen, and again to clear it.
const FADE_TIME := 0.15
## Seconds the marsh-grass wipe (Wipe) takes to rise over the screen, and again to sink
## away (at most 0.4 each: plan AC 3).
const WIPE_TIME := 0.35
## The project setting naming the UI theme every scene uses.
const THEME_SETTING := "gui/theme/custom"
## The audio buses (default_bus_layout.tres): every music player is on MUSIC_BUS, every
## sound effect on SFX_BUS, both sending to Master.
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## The game's sound effects: audio/sfx/<id>.wav (tools/sfx.py EFFECTS makes one per id).
const SFX_PATH := "res://audio/sfx/%s.wav"
const SFX_IDS: Array[StringName] = [
	&"shot", &"empty_click", &"out_of_shells", &"hit", &"armored_clank", &"armored_kill", &"split_pop",
	&"golden_chime", &"decoy_penalty", &"escape", &"wave_start", &"wave_clear", &"wave_lost", &"combo_up",
	&"rival_aim", &"rival_steal", &"rival_laugh", &"countdown_tick", &"time_up", &"star", &"new_best", &"ui_tap", &"pause", &"resume",
]
## Sound effect players: at most this many sounds at once (the oldest gives way). One more
## player, the menu voice, plays every sound started while the audio is paused (the pause
## menu's own), so a sound the pause holds is never taken over.
const SFX_VOICES := 8
## sfx_log keeps the ids of this many latest sounds (tests read it).
const SFX_LOG_SIZE := 256
## Buttons in this group play their own sound when pressed (the pause button and Resume),
## not "ui_tap".
const OWN_SOUND_GROUP := &"own_sound"
## The rival's syllables: audio/sfx/blurt_<timbre>_<vowel>.wav (tools/sfx.py TIMBRES, VOWELS).
const BLURT_PATH := "res://audio/sfx/blurt_%s_%s.wav"
const BLURT_TIMBRES: Array[String] = ["gruff", "nasal", "hoot"]
const BLURT_VOWELS: Array[String] = ["a", "e", "o", "u"]
## A blurt has one syllable per word of its line, at most this many, BLURT_GAP seconds apart
## (varied a little).
const BLURT_SYLLABLES_MAX := 6
const BLURT_GAP := 0.13
## The rival's voice per heckle category (RivalLines.CATEGORIES): the timbre and the base
## pitch of the blurt (a mocking high nasal for a miss and a gloating higher one for a
## steal, a grumble for the player's combo, a hoot at a wave's end, a gruff parting line).
const HECKLE_VOICES: Dictionary[String, Array] = {
	"miss": ["nasal", 1.2], "combo": ["gruff", 0.85], "wave_end": ["hoot", 1.0], "steal": ["nasal", 1.45], "results": ["gruff", 1.05],
}
## The loops of the title (and the chapter and level selects) and of the results screen;
## a run plays its chapter's or mode's (data music, Content.music_path).
const TITLE_TRACK := "title"
## The file of each loop: as Content.music_path, which the data's tracks are checked against.
const MUSIC_PATH := "res://audio/music/%s.mp3"
const RESULTS_TRACK := "results"
## Seconds a new loop takes to fade in over the old one (at most 0.5: plan AC 7).
const CROSSFADE_TIME := 0.4
## How far the music drops while the tree is paused.
const PAUSE_DUCK_DB := -12.0
## The bus volume at setting 0 (the bus is muted then too).
const SILENT_VOLUME_DB := -80.0
## The audio driver of headless runs: no device, it never mixes, so a sound started on it
## would never finish (and leak at exit). There sounds and loops are only recorded.
const SILENT_AUDIO_DRIVER := "Dummy"
## Frames the window-close quit waits after stopping the audio, so the mixer drops the playbacks.
const QUIT_FRAMES := 3


## One syllable of a heckle's blurt: the sound (a BLURT_PATH id), its pitch, and when it
## starts (seconds after the first).
class Syllable:
	var sound: StringName
	var pitch := 1.0
	var at := 0.0

## Paths per flow state; tests swap one to check the missing-scene path.
var scene_paths: Dictionary[Flow, String] = SCENE_PATHS.duplicate()
## Where sound effects are (SFX_PATH) and music loops are (MUSIC_PATH); tests swap them to
## check the missing and unloadable paths.
var sfx_path := SFX_PATH
var music_path := MUSIC_PATH
## Tests set this to keep expected errors out of the log; they are still recorded
## and shown on the error label.
var quiet_errors := false
var reported_errors: Array[String] = []
## Every goto() started, "FROM -> TO (path) args=..." (tests read it).
var transition_log: Array[String] = []
var state := Flow.TITLE
## The args of the latest goto(); the new scene reads them in its _ready().
var flow_args: Dictionary = {}
## Tests set this (base units) to stand in for a notched screen's safe area; it applies
## from the next ScreenFit update. An empty rect means the display's own safe area.
var safe_area_override := Rect2()
## Where the save lives: SAVE_PATH, or TOOL_SAVE_PATH in tool runs.
var save_path := SAVE_PATH
## The best score of each of BEST_MODES (mode id -> score), persisted in the save.
var bests: Dictionary[String, int] = {}
## The campaign progress, persisted in the save: level id -> its best stars and score. A
## level without an entry was never finished.
var progress: Dictionary[String, Campaign.Record] = {}
## Settings, persisted in the save: the music and sound effects volumes (0..VOLUME_MAX)
## and mutes.
var music_volume := DEFAULT_MUSIC_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
var music_muted := false
var sfx_muted := false
## Settings, persisted in the save: true turns off motion that is only decoration (screen
## shake, the transition wipe, the pop-ups' bounce and shake, the title's drift); hit stop,
## feathers and every gameplay cue stay.
var reduce_motion := false
## Why the latest save failed, short enough for the results screen; "" after a save that
## worked (on the web: once written; a later IndexedDB failure sets it again).
var save_error := ""
## False on the web when the browser gave Godot no IndexedDB at start (check_storage).
var storage_persistent := true
## The number of the latest web save check; an answer to an older one is ignored.
var persist_check := 0
## The UI theme check_ui_theme last checked ("" before any; at start, the project's).
var checked_theme := ""
## The ids of the latest sounds played, oldest first (SFX_LOG_SIZE at most; a heckle's blurt
## is "heckle_<category>"), and the pitch each played at (1 for a blurt); tests read them.
var sfx_log: Array[StringName] = []
var sfx_pitches: Array[float] = []
## The loop asked for ("" before the first) and how often it changed (a crossfade each).
var music_track := ""
var music_changes := 0
## True while the tree is paused and the audio with it (sounds held, music ducked).
var audio_paused := false
## Sounds held by the latest pause (sync_audio_pause), until it ends.
var held_sounds := 0

var _transitioning := false
## How the current (or last) screen change covers the screen: "wipe" or "fade".
var _transition_style := ""
## The campaign entries the last load dropped, one log message each (load_game backs the
## original up, then writes the save back without them).
var _dropped_entries: Array[String] = []
var _visible_rect := Rect2()
var _safe_rect := Rect2()
## True while the rotate overlay holds the tree paused (it then unpauses on hiding).
var _paused_by_rotate := false
## The JavaScript visibilitychange listener (web only); kept so it is not freed.
var _visibility_listener: JavaScriptObject
## The JavaScript callback of the web save checks (web only); kept so it is not freed.
var _persist_callback: JavaScriptObject
## Seconds since start (also while paused): the sound clock.
var _clock := 0.0
## Sound file -> its stream, or null when it is missing (reported once).
var _sounds: Dictionary[String, AudioStream] = {}
var _sfx_players: Array[AudioStreamPlayer] = []
## The reserved voice of the sounds started while the audio is paused (never held).
var _menu_voice: AudioStreamPlayer
## Per player: the _clock when its sound started, and when it ends (still in flight before then).
var _sfx_started: Array[float] = []
var _sfx_until: Array[float] = []
## The players the current pause holds, and the _clock it started at.
var _held: Array[AudioStreamPlayer] = []
var _held_at := 0.0
## The syllables of blurts still to start, each at its _clock time (in order).
var _blurt_queue: Array[Syllable] = []
## Sounds play_sfx_later queued, each at its _clock time (in order).
var _later_queue: Array[Syllable] = []
## Loop file -> its stream, or null when it is missing (reported once).
var _tracks: Dictionary[String, AudioStream] = {}
var _music_players: Array[AudioStreamPlayer] = []
## The index in _music_players of the one playing (or fading in) music_track.
var _music_current := 0
var _music_fade: Tween

@onready var _cover: ColorRect = $Fade/Cover
@onready var _wipe: Wipe = $Fade/Cover/Wipe
@onready var _error_label: Label = $Fade/ErrorLabel
@onready var _rotate_overlay: Control = $RotateLayer/RotateOverlay


func _ready() -> void:
	_setup_audio()
	# Tool runs (the tests, the project check, the headless main-scene run) drive the
	# tree from a SceneTree script; they must never read or overwrite the player's save.
	if get_tree().get_script() != null:
		save_path = TOOL_SAVE_PATH
	if OS.has_feature("web"):
		check_storage(OS.is_userfs_persistent())
	load_game()
	check_ui_theme(ProjectSettings.get_setting(THEME_SETTING, ""))
	check_audio()
	_watch_page_visibility()
	_fit_window()
	get_viewport().size_changed.connect(_update_screen_fit)
	_update_screen_fit()
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
	play_music(track_for(state, flow_args))


## On the web, listens for the document's visibilitychange and emits page_hidden when
## the page is hidden.
func _watch_page_visibility() -> void:
	if not OS.has_feature("web"):
		return
	var document := JavaScriptBridge.get_interface("document")
	if document == null:
		report_error("Cannot watch the page's visibility: no document object")
		return
	_visibility_listener = JavaScriptBridge.create_callback(_on_visibility_changed)
	document.addEventListener("visibilitychange", _visibility_listener)


func _on_visibility_changed(_args: Array) -> void:
	# A JavaScript boolean arrives as a number, so ask for one explicitly.
	var hidden := int(JavaScriptBridge.eval("document.hidden ? 1 : 0", true)) == 1
	print("[Game] Page %s" % ("hidden" if hidden else "visible"))
	if hidden:
		page_hidden.emit()


## Desktop windows are sized in physical pixels, so on a high-density screen
## (a 2x Retina display) the project's window size would show at half size,
## and on a small screen it may not fit. Applies `fit_window_rect()`. The web
## build fills its page and a game embedded in the editor is sized by the
## editor, so both are left alone.
func _fit_window() -> void:
	var window := get_window()
	if OS.has_feature("web") or Engine.is_embedded_in_editor() or window.mode != Window.MODE_WINDOWED:
		return
	var density := DisplayServer.screen_get_scale(window.current_screen)
	var fitted := fit_window_rect(window.size, density, DisplayServer.screen_get_usable_rect(window.current_screen),
		window.get_size_with_decorations() - window.size, window.position - window.get_position_with_decorations())
	if fitted.size == window.size:
		return
	window.size = fitted.size
	window.position = fitted.position
	print("[Game] Fitted the window to a %.1fx screen: %s" % [density, fitted])


## The client rect for a window of `base` screen points on a screen of
## `density`: scaled to pixels, shrunk (keeping its aspect) until it fits the
## `usable` screen rect together with its frame (`frame_size` = framed minus
## client size, `client_offset` = client position inside the frame), and placed
## so the framed window is centred in the usable rect.
static func fit_window_rect(base: Vector2i, density: float, usable: Rect2i, frame_size: Vector2i, client_offset: Vector2i) -> Rect2i:
	var room := Vector2(usable.size - frame_size)
	var wanted := Vector2(base) * density
	wanted *= minf(1.0, minf(room.x / wanted.x, room.y / wanted.y))
	var client := Vector2i(wanted)
	var framed_position := usable.position + Vector2i(Vector2(usable.size - client - frame_size) / 2.0)
	return Rect2i(framed_position + client_offset, client)


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
	var missing := missing_dependencies(path)
	var track := track_for(new_state, args)
	if track != "" and not ResourceLoader.exists(music_path % track):
		missing.append(music_path % track)
	if not missing.is_empty():
		report_error("Cannot go to %s: scene '%s' needs %s, which %s missing" % [to_name, path, ", ".join(missing), "is" if missing.size() == 1 else "are"])
		return
	_transitioning = true
	play_music(track)
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
	var problems := theme_problems(path)
	for problem in problems:
		report_error(problem)
	if problems.is_empty():
		print("[Game] UI theme %s loaded with its fonts: %s" % [path, ", ".join(theme_font_files(load(path) as Theme))])
	return problems.is_empty()


## What is wrong with the UI theme at `path` (empty when nothing is): no theme set, no such
## file, a file it needs (a font) missing (checked before loading, so the loader is never
## asked for it), a file that is no Theme, or a font the theme uses that is missing or
## holds no font data. Each problem names the file. Public for tests.
static func theme_problems(path: String) -> Array[String]:
	var problems: Array[String] = []
	if path == "":
		problems.append("No UI theme is set (project.godot %s)" % THEME_SETTING)
		return problems
	if not ResourceLoader.exists(path):
		problems.append("UI theme '%s' does not exist" % path)
		return problems
	for missing in missing_dependencies(path):
		problems.append("UI theme '%s' needs '%s', which is missing" % [path, missing])
	if not problems.is_empty():
		return problems
	var theme := load(path) as Theme
	if theme == null:
		problems.append("UI theme '%s' cannot be loaded as a Theme" % path)
		return problems
	return font_problems(theme, path)


## The fonts of `theme` (its default font and every type's fonts, through FontVariation
## bases) that are missing or hold no font data, named by where the theme uses them.
static func font_problems(theme: Theme, path: String) -> Array[String]:
	var problems: Array[String] = []
	for where in _theme_fonts(theme):
		var font := _font_file(_theme_fonts(theme)[where])
		if font == null:
			problems.append("UI theme '%s': %s has no font file" % [path, where])
		elif font is FontFile and (font as FontFile).data.is_empty():
			problems.append("UI theme '%s': %s font '%s' holds no font data" % [path, where, font.resource_path])
	return problems


## The font files `theme` uses (for the log).
static func theme_font_files(theme: Theme) -> PackedStringArray:
	var files := PackedStringArray()
	for font: Font in _theme_fonts(theme).values():
		var file := _font_file(font)
		if file != null and not file.resource_path.get_file() in files:
			files.append(file.resource_path.get_file())
	return files


## "default_font" and "<Type>/fonts/<name>" -> the font the theme holds there.
static func _theme_fonts(theme: Theme) -> Dictionary[String, Font]:
	var fonts: Dictionary[String, Font] = {"default_font": theme.default_font}
	for type in theme.get_font_type_list():
		for font_name in theme.get_font_list(type):
			fonts["%s/fonts/%s" % [type, font_name]] = theme.get_font(font_name, type)
	return fonts


## The font file under `font` (through FontVariation bases), or null.
static func _font_file(font: Font) -> Font:
	while font is FontVariation:
		font = (font as FontVariation).base_font
	return font


## The files the resource at `path` needs, directly or through the files it needs, that do
## not exist (read from the files' dependency lists, nothing is loaded).
static func missing_dependencies(path: String, seen: Dictionary[String, bool] = {}) -> PackedStringArray:
	var missing := PackedStringArray()
	seen[path] = true
	for entry in ResourceLoader.get_dependencies(path):
		var dependency := ""
		for part in entry.split("::"):
			if part.begins_with("res://"):
				dependency = part
		if dependency == "" and entry.begins_with("uid://"):
			var id := ResourceUID.text_to_id(entry.get_slice("::", 0))
			dependency = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else entry.get_slice("::", 0)
		if dependency == "" or seen.has(dependency):
			continue
		if not ResourceLoader.exists(dependency):
			missing.append(dependency)
		else:
			missing.append_array(missing_dependencies(dependency, seen))
	return missing


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


## Records a finished campaign level: the stars `score` earns, kept with the level's best
## stars and best score (a replay never lowers either), saved at once (save_error says why
## when that failed). Logged with the level, the stars and the score, and the level it
## unlocks. Returns true when `score` beats the level's best score (any score above 0 on
## its first finish).
func record_level(level: LevelSpec, score: int) -> bool:
	var earned := Campaign.stars(level, score)
	var before: Campaign.Record = progress.get(level.id)
	var next := Campaign.next_level(level)
	var was_open := next != null and Campaign.is_unlocked(next, progress)
	var kept := Campaign.merge(before, earned, score)
	progress[level.id] = kept
	var new_best := score > (before.score if before != null else 0)
	var unlocked := ""
	if next != null and not was_open and Campaign.is_unlocked(next, progress):
		unlocked = "; %s unlocked" % next.id
	print("[Game] Level %s finished: score %d, %d stars (%s); best %d stars, score %d (was %s)%s" % [
		level.id, score, earned, "passed" if Campaign.is_passed(earned) else "not passed", kept.stars, kept.score,
		"%d stars, score %d" % [before.stars, before.score] if before != null else "never finished", unlocked])
	save_game()
	return new_best


## The best score of mode `mode_id` (0 before any run of it beat 0).
func best(mode_id: String) -> int:
	return bests.get(mode_id, 0)


## Records the score of a finished run of `mode` (Endless, Time Attack): a new best is saved
## at once (save_error says why when that failed). Returns true when it is a new best. A
## mode the save keeps no best for (not in BEST_MODES) is reported and records nothing.
func record_best(mode: ModeSpec, score: int) -> bool:
	if not mode.id in BEST_MODES:
		report_error("Cannot record a best for mode '%s': the save keeps bests only for %s" % [mode.id, BEST_MODES])
		return false
	var before := best(mode.id)
	if score <= before:
		print("[Game] %s score %d does not beat the best %d" % [mode.name, score, before])
		return false
	print("[Game] New %s best: %d (was %d)" % [mode.name, score, before])
	bests[mode.id] = score
	save_game()
	return true


## Writes the save to save_path and returns whether it worked; a failure sets
## save_error, is reported and emits save_failed, never silent. The data goes to a
## temporary file first, which then replaces the save, so a failed write leaves the last
## good save in place. On the web the write lands in memory: it is logged as written and
## confirmed from IndexedDB later (or reported as lost then); with no browser storage at
## all it fails at once.
func save_game() -> bool:
	save_error = ""
	var levels := {}
	for id in progress:
		levels[id] = {"stars": progress[id].stars, "score": progress[id].score}
	var text := JSON.stringify({
		"version": SAVE_VERSION, "bests": bests.duplicate(), "levels": levels,
		"settings": {"music": music_volume, "sfx": sfx_volume, "music_muted": music_muted, "sfx_muted": sfx_muted, "reduce_motion": reduce_motion},
	}, "  ")
	var temp := save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		var open_error := error_string(FileAccess.get_open_error())
		_save_failed("Could not open '%s' for writing the save: %s; '%s' is unchanged" % [temp, open_error, save_path], "cannot open the save file (%s)" % open_error)
		return false
	var written := file.store_string(text)
	file.close()
	if not written:
		DirAccess.remove_absolute(temp)
		_save_failed("Could not write the save to '%s'; '%s' is unchanged" % [temp, save_path], "cannot write the save file")
		return false
	var replaced := DirAccess.rename_absolute(temp, save_path)
	if replaced != OK:
		DirAccess.remove_absolute(temp)
		_save_failed("Could not replace save '%s' with '%s': %s; the save is unchanged" % [save_path, temp, error_string(replaced)], "cannot replace the save file (%s)" % error_string(replaced))
		return false
	if not OS.has_feature("web"):
		print("[Game] Saved to %s: version %d, %s" % [save_path, SAVE_VERSION, save_summary()])
		return true
	if not storage_persistent:
		_save_failed("Wrote the save (%s) to %s in memory only: browser storage is unavailable, so it is lost when the page closes" % [save_summary(), save_path], "browser storage is unavailable")
		return false
	print("[Game] Saved to %s (written; waiting for browser storage to keep it): version %d, %s" % [save_path, SAVE_VERSION, save_summary()])
	_check_web_persisted(text)
	return true


## On the web, user:// persists only when the browser gave Godot IndexedDB at start;
## without it every save lives in memory until the page closes, which the player is told
## at once. Public for tests.
func check_storage(persistent: bool) -> void:
	storage_persistent = persistent
	if persistent:
		print("[Game] Browser storage (IndexedDB) is available for %s (%s)" % [save_path, ProjectSettings.globalize_path(save_path)])
		return
	report_error("Browser storage (IndexedDB) is unavailable (private browsing or blocked site data): best scores are kept only until the page closes")


## The answer to web save check `check`: `ok` when IndexedDB holds the save, else
## `detail` says why not. An answer to an older check is ignored (a newer save replaced
## what it looked for). Public for tests.
func persist_checked(check: int, ok: bool, detail: String) -> void:
	if check != persist_check:
		print("[Game] Ignored the answer to save check %d (superseded by check %d)" % [check, persist_check])
		return
	if ok:
		print("[Game] Save persisted to browser storage: %s after %s ms (check %d)" % [save_path, detail, check])
		return
	_save_failed("The save (%s) was written to %s but browser storage (IndexedDB) did not keep it: %s (check %d); it is lost when the page closes" % [save_summary(), save_path, detail, check], "browser storage did not keep it (%s)" % detail)


## Asks the page to confirm that IndexedDB holds `text` at save_path (see WEB_PERSIST_CHECK_JS).
func _check_web_persisted(text: String) -> void:
	persist_check += 1
	if _persist_callback == null:
		JavaScriptBridge.eval(WEB_PERSIST_CHECK_JS, true)
		_persist_callback = JavaScriptBridge.create_callback(_on_persist_checked)
	var window := JavaScriptBridge.get_interface("window")
	# A JavaScript boolean arrives as a number, so ask for one explicitly.
	if window == null or int(JavaScriptBridge.eval("typeof window.huntFrenzyCheckPersisted === 'function' ? 1 : 0", true)) != 1:
		persist_checked(persist_check, false, "the page cannot check browser storage")
		return
	# Emscripten's IDBFS names its database after the mount point: the path's first segment (/userfs).
	var key := ProjectSettings.globalize_path(save_path)
	window.huntFrenzyCheckPersisted(key.substr(0, key.find("/", 1)), key, text, WEB_PERSIST_TIMEOUT_MSEC, persist_check, _persist_callback)


func _on_persist_checked(args: Array) -> void:
	persist_checked(int(args[0]), int(args[1]) == 1, str(args[2]))


## A failed save: `message` (with paths and causes) goes to the log and the error label,
## `reason` to save_error for the results screen.
func _save_failed(message: String, reason: String) -> void:
	save_error = reason
	report_error(message)
	save_failed.emit(reason)


## What the save holds, for log lines: the Endless and Time Attack bests, the levels
## finished with their stars, and the settings (", reduce motion" only when it is on).
func save_summary() -> String:
	var earned := 0
	for id in progress:
		earned += progress[id].stars
	return "Endless best %d, Time Attack best %d, %d levels finished (%d stars), music %d%s, sfx %d%s" % [
		best(ENDLESS_MODE), best(TIME_ATTACK_MODE), progress.size(), earned, music_volume, " muted" if music_muted else "", sfx_volume, " muted" if sfx_muted else ""] + (", reduce motion" if reduce_motion else "")


## Loads save_path. A missing save starts fresh (a log line only); an older version is
## upgraded (save_migrations, logged) and written back at once; an unreadable, corrupt or
## unknown-version one is reported (push_error and the error label), moved to backup_path()
## and replaced by a fresh save; a bad campaign entry is reported and dropped (the rest
## loads; the original is copied to dropped_backup_path() and the save is then written back
## without it, so it is reported once, or left as it is when the copy fails). With content
## errors the save is left unread and untouched (its levels are checked against
## levels.json; the title disables play). A JSON instance reports parse errors as return
## values, so each problem is reported once, by us. The loaded (or default) volumes and
## mutes are then applied to the buses.
func load_game() -> void:
	_read_save()
	_apply_volumes()


func _read_save() -> void:
	_reset_save_data()
	if not FileAccess.file_exists(save_path):
		print("[Game] No save at %s; starting fresh" % save_path)
		return
	if not Content.errors().is_empty():
		print("[Game] Content has problems; the save at %s is left unread and untouched" % save_path)
		return
	var text := FileAccess.get_file_as_string(save_path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_discard_save("unreadable (%s)" % error_string(FileAccess.get_open_error()))
		return
	var json := JSON.new()
	if json.parse(text) != OK:
		_discard_save("corrupt (line %d: %s)" % [json.get_error_line(), json.get_error_message()])
		return
	var data: Variant = json.data
	var from_version: Variant = (data as Dictionary).get("version") if data is Dictionary else null
	var problem := _apply_save(data)
	if problem != "":
		_reset_save_data()
		_discard_save("corrupt (%s)" % problem)
		return
	print("[Game] Loaded save from %s: version %d, %s" % [save_path, SAVE_VERSION, save_summary()])
	# Dropped entries come first: the original is backed up before anything is written back.
	if not _dropped_entries.is_empty():
		if int(from_version) != SAVE_VERSION:
			print("[Game] The save upgraded from version %d is written as version %d once its dropped entries are backed up" % [int(from_version), SAVE_VERSION])
		_write_back_without_dropped()
	elif int(from_version) != SAVE_VERSION:
		print("[Game] Writing the save upgraded from version %d as version %d" % [int(from_version), SAVE_VERSION])
		save_game()


## Copies the save as loaded to a free dropped_backup_path(), then writes it back without
## the dropped campaign entries; the player is told how many were dropped and where the
## original is. When the copy fails nothing is written: the original stays on disk.
func _write_back_without_dropped() -> void:
	var count := _dropped_entries.size()
	var dropped := "%d campaign %s" % [count, "entry was" if count == 1 else "entries were"]
	var backup := dropped_backup_path()
	var copied := DirAccess.copy_absolute(save_path, backup) if backup != "" else ERR_ALREADY_EXISTS
	if copied != OK:
		report_error("Save '%s': %s dropped (see the log), but the original could not be backed up to '%s' (%s); the save is left as it is" % [save_path, dropped, backup if backup != "" else save_path.get_basename() + ".dropped*.json", error_string(copied)])
		return
	print("[Game] Backed up the save with %d dropped campaign entries to %s" % [count, backup])
	report_error("Save '%s': %s dropped (see the log); the original is kept as '%s'" % [save_path, dropped, backup])
	print("[Game] Writing the save without its %d dropped campaign entries" % count)
	save_game()


func _reset_save_data() -> void:
	bests = {}
	for mode_id in BEST_MODES:
		bests[mode_id] = 0
	progress = {}
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	music_muted = false
	sfx_muted = false
	reduce_motion = false


## Where a corrupt save is moved: save.json -> save.corrupt.json.
func backup_path() -> String:
	return save_path.get_basename() + ".corrupt.json"


## Where a save with dropped campaign entries is copied before it is written back: the first
## of save.dropped.json, save.dropped.2.json, ... (up to DROPPED_BACKUPS_MAX) that does not
## exist yet, so it never replaces an earlier backup or the corrupt-save backup; "" when
## all are taken.
func dropped_backup_path() -> String:
	for n in range(1, DROPPED_BACKUPS_MAX + 1):
		var path := save_path.get_basename() + (".dropped.json" if n == 1 else ".dropped.%d.json" % n)
		if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
			return path
	return ""


## Applies a parsed save (upgraded to SAVE_VERSION first); returns "" or what is wrong
## with it, and applies nothing then. A bad campaign entry is not a corrupt save: it is
## reported with its key and dropped.
func _apply_save(data: Variant) -> String:
	if not data is Dictionary:
		return "not an object"
	var saved: Dictionary = data
	var outdated := migrate_save(saved, save_migrations(), SAVE_VERSION)
	if outdated != "":
		return outdated
	for key: Variant in saved:
		if not SAVE_KEYS.has(str(key)):
			return "unknown key '%s'" % key
	for key in SAVE_KEYS:
		if not saved.has(key):
			return "missing key '%s'" % key
		var value: Variant = saved[key]
		var ok := _is_whole(value) if SAVE_KEYS[key] == TYPE_INT else typeof(value) == SAVE_KEYS[key]
		if not ok:
			return "'%s' is not %s" % [key, "a whole number" if SAVE_KEYS[key] == TYPE_INT else "an object"]
	var saved_bests: Dictionary = saved["bests"]
	if saved_bests.size() != BEST_MODES.size() or not BEST_MODES.all(func(key: String) -> bool: return saved_bests.has(key)):
		return "bests must be exactly %s (got %s)" % [BEST_MODES, saved_bests.keys()]
	for key in BEST_MODES:
		if not _is_whole(saved_bests[key]) or int(saved_bests[key]) < 0 or int(saved_bests[key]) > SAVE_SCORE_MAX:
			return "bests.%s %s is not a whole number 0..%d" % [key, _number_text(saved_bests[key]), SAVE_SCORE_MAX]
	var settings: Dictionary = saved["settings"]
	if settings.size() != SETTINGS_KEYS.size() or not SETTINGS_KEYS.all(func(key: String) -> bool: return settings.has(key)):
		return "settings must be exactly %s" % [SETTINGS_KEYS]
	for key in SETTINGS_KEYS:
		var setting: Variant = settings[key]
		if key in VOLUME_SETTINGS:
			if not _is_whole(setting) or int(setting) < 0 or int(setting) > VOLUME_MAX:
				return "settings.%s is not a whole number 0..%d" % [key, VOLUME_MAX]
		elif typeof(setting) != TYPE_BOOL:
			return "settings.%s is not true or false" % key
	var loaded: Dictionary[String, Campaign.Record] = {}
	var levels: Dictionary = saved["levels"]
	_dropped_entries.clear()
	for id: Variant in levels:
		var entry_problem := level_entry_problem(str(id), levels[id])
		if entry_problem != "":
			var message := "Save '%s': dropped the campaign entry levels.%s = %s: %s; the rest of the save loaded" % [save_path, id, JSON.stringify(_as_stored(levels[id]), "", false), entry_problem]
			_dropped_entries.append(message)
			# Each drop is reported; the error label then shows their count (load_game).
			report_error(message)
			continue
		var entry: Dictionary = levels[id]
		loaded[str(id)] = Campaign.Record.new(int(entry["stars"]), int(entry["score"]))
	for key in BEST_MODES:
		bests[key] = int(saved_bests[key])
	progress = loaded
	music_volume = int(settings["music"])
	sfx_volume = int(settings["sfx"])
	music_muted = settings["music_muted"]
	sfx_muted = settings["sfx_muted"]
	reduce_motion = settings["reduce_motion"]
	return ""


## What is wrong with the saved campaign entry `id` -> `entry`, or "": the id must be a
## level of levels.json and the entry exactly {"stars": 0..Campaign.MAX_STARS, "score":
## 0..SAVE_SCORE_MAX}, whole numbers.
static func level_entry_problem(id: String, entry: Variant) -> String:
	if not Content.has_level(id):
		return "'%s' is not a level of levels.json" % id
	if not entry is Dictionary:
		return "not an object"
	var fields: Dictionary = entry
	if fields.size() != LEVEL_KEYS.size() or not LEVEL_KEYS.all(func(key: String) -> bool: return fields.has(key)):
		return "must be exactly %s" % [LEVEL_KEYS]
	if not _is_whole(fields["stars"]) or int(fields["stars"]) < 0 or int(fields["stars"]) > Campaign.MAX_STARS:
		return "stars %s is not a whole number 0..%d" % [_number_text(fields["stars"]), Campaign.MAX_STARS]
	if not _is_whole(fields["score"]) or int(fields["score"]) < 0 or int(fields["score"]) > SAVE_SCORE_MAX:
		return "score %s is not a whole number 0..%d" % [_number_text(fields["score"]), SAVE_SCORE_MAX]
	return ""


## A parsed save value as it was stored, for a message: whole numbers (which JSON loads as
## floats) back to ints, inside objects and arrays too.
static func _as_stored(value: Variant) -> Variant:
	if value is Dictionary:
		var copy := {}
		for key: Variant in value:
			copy[key] = _as_stored((value as Dictionary)[key])
		return copy
	if value is Array:
		return (value as Array).map(_as_stored)
	return int(value) if value is float and _is_whole(value) else value


## A saved value for a message: a whole number without its ".0" (JSON numbers load as floats).
static func _number_text(value: Variant) -> String:
	return str(int(value)) if _is_whole(value) else str(value)


## Upgrades `saved` (a parsed save, changed in place) to version `target`:
## migrations[i] turns a version i + 1 save into version i + 2 (each step logged). Returns
## "" or why it cannot (no whole version >= 1, or a version newer than `target`).
static func migrate_save(saved: Dictionary, migrations: Array[Callable], target: int) -> String:
	if not _is_whole(saved.get("version")) or int(saved["version"]) < 1:
		return "'version' is not a whole number >= 1"
	if migrations.size() != target - 1:
		push_error("[Game] %d save upgrade steps for save version %d (expected %d)" % [migrations.size(), target, target - 1])
		return "this game cannot upgrade saves (%d steps for version %d)" % [migrations.size(), target]
	var version := int(saved["version"])
	if version > target:
		return "version %d is newer than this game's %d" % [version, target]
	while version < target:
		migrations[version - 1].call(saved)
		version += 1
		saved["version"] = version
		print("[Game] Upgraded the save to version %d" % version)
	return ""


## The save format's upgrade steps: entry i turns a version i + 1 save into version i + 2.
## Steps run before the save is validated, so they must read keys with get() and leave
## anything malformed for the validation to report.
static func save_migrations() -> Array[Callable]:
	return [_save_v1_to_v2, _save_v2_to_v3, _save_v3_to_v4]


## Version 1 -> 2: the campaign arrives (no level finished yet) and the settings are saved,
## at their defaults; the Endless best is kept as it is.
static func _save_v1_to_v2(saved: Dictionary) -> void:
	saved["levels"] = {}
	saved["settings"] = {"music": DEFAULT_MUSIC_VOLUME, "sfx": DEFAULT_SFX_VOLUME, "music_muted": false, "sfx_muted": false}
	print("[Game] Save upgrade 1 -> 2: Endless best %s kept, no campaign levels finished yet, default settings" % _number_text(saved.get("best_endless")))


## Version 2 -> 3: a best score per mode (bests) replaces best_endless, which becomes the
## Endless best; Time Attack arrives with a best of 0. A save without best_endless gets no
## bests, so the validation reports it missing.
static func _save_v2_to_v3(saved: Dictionary) -> void:
	if not saved.has("best_endless"):
		print("[Game] Save upgrade 2 -> 3: no best_endless to keep")
		return
	saved["bests"] = {ENDLESS_MODE: saved["best_endless"], TIME_ATTACK_MODE: 0}
	saved.erase("best_endless")
	print("[Game] Save upgrade 2 -> 3: Endless best %s kept as bests.%s, Time Attack best 0" % [_number_text(saved["bests"][ENDLESS_MODE]), ENDLESS_MODE])


## Version 3 -> 4: the settings gain reduce_motion, off; everything else is kept. Settings
## that are not an object are left for the validation to report.
static func _save_v3_to_v4(saved: Dictionary) -> void:
	var settings: Variant = saved.get("settings")
	if not settings is Dictionary:
		print("[Game] Save upgrade 3 -> 4: no settings object to add reduce_motion to")
		return
	(settings as Dictionary)["reduce_motion"] = false
	print("[Game] Save upgrade 3 -> 4: reduce_motion off, the bests, the campaign progress and the other settings kept")


func _discard_save(problem: String) -> void:
	var cleared := OK
	if FileAccess.file_exists(backup_path()):
		cleared = DirAccess.remove_absolute(backup_path())
	var moved := DirAccess.rename_absolute(save_path, backup_path()) if cleared == OK else cleared
	if moved != OK:
		report_error("Save '%s' is %s and could not be moved to '%s' (%s); the game starts fresh and the next save replaces it" % [save_path, problem, backup_path(), error_string(moved)])
		return
	report_error("Save '%s' is %s; it was moved to '%s' and replaced with a fresh save" % [save_path, problem, backup_path()])
	save_game()


## JSON numbers load as floats; accept whole numbers only, and only those a float
## holds exactly (|n| <= 2^53): int() of a larger float is CPU dependent (arm64
## saturates, x86-64 gives INT64_MIN), so range checks after it could be fooled.
static func _is_whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value) and absf(value) <= SAVE_EXACT_MAX)


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
	_transition_style = "fade" if reduce_motion else "wipe"
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


## The visible area in base units: 960x540 or larger on one axis (aspect expand).
func visible_rect() -> Rect2:
	return _visible_rect


## The part of the visible area clear of notches and rounded corners, in base units.
func safe_rect() -> Rect2:
	return _safe_rect


## True while the rotate overlay covers the game (the visible area is portrait).
func is_rotate_overlay_shown() -> bool:
	return _rotate_overlay.visible


## Converts the screen-pixel safe area to base units and clips it to `visible`.
## An empty safe area (headless, some web browsers) means the whole visible rect.
static func safe_rect_in(visible: Rect2, safe_pixels: Rect2i, window_position: Vector2i, stretch: Transform2D) -> Rect2:
	if safe_pixels.size.x <= 0 or safe_pixels.size.y <= 0:
		return visible
	var local := Rect2(Vector2(safe_pixels.position - window_position), Vector2(safe_pixels.size))
	var base := stretch.affine_inverse() * local
	var clipped := base.intersection(visible)
	return clipped if clipped.has_area() else visible


## True when a visible area of `area` needs the rotate overlay: taller than wide.
static func is_portrait(area: Vector2) -> bool:
	return area.y > area.x


func _update_screen_fit() -> void:
	var window := get_window()
	var visible := get_viewport().get_visible_rect()
	var safe := safe_area_override if safe_area_override.has_area() else safe_rect_in(visible, DisplayServer.get_display_safe_area(), window.position, window.get_final_transform())
	if visible.is_equal_approx(_visible_rect) and safe.is_equal_approx(_safe_rect):
		return
	_visible_rect = visible
	_safe_rect = safe
	print("[Game] ScreenFit: visible %s, safe %s" % [visible, safe])
	_update_rotate_overlay()
	screen_fit_changed.emit()


## Shows the rotate overlay and pauses the tree while the visible area is portrait;
## hides it and restores the pause state when it is landscape again.
func _update_rotate_overlay() -> void:
	var portrait := is_portrait(_visible_rect.size)
	if portrait == _rotate_overlay.visible:
		return
	var tree := get_tree()
	if portrait:
		_paused_by_rotate = not tree.paused
		tree.paused = true
		_rotate_overlay.show()
		# The overlay stops touches; GUI input is disabled too, so keys cannot press a
		# focused button (an ALWAYS-processing pause menu) hidden behind it.
		get_viewport().gui_disable_input = true
		print("[Game] Rotate overlay shown (visible %s); tree paused" % _visible_rect.size)
	else:
		_rotate_overlay.hide()
		get_viewport().gui_disable_input = false
		if _paused_by_rotate:
			tree.paused = false
		print("[Game] Rotate overlay hidden (visible %s); tree %s" % [_visible_rect.size, "unpaused" if _paused_by_rotate else "stays paused"])
		_paused_by_rotate = false
	rotate_overlay_changed.emit(portrait)
	# After the signal: a run that re-pauses on it keeps its sounds held.
	sync_audio_pause()


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


func _process(delta: float) -> void:
	_clock += delta
	# Pauses that did not call sync_audio_pause themselves (a test pausing the tree).
	sync_audio_pause()
	while not audio_paused and not _blurt_queue.is_empty() and _blurt_queue[0].at <= _clock:
		var syllable: Syllable = _blurt_queue.pop_front()
		_start_voice(_sound(syllable.sound), syllable.pitch)
	while not audio_paused and not _later_queue.is_empty() and _later_queue[0].at <= _clock:
		var later: Syllable = _later_queue.pop_front()
		play_sfx(later.sound, later.pitch)


## Closing the window: a stream still playing at quit keeps its playback (and the stream)
## referenced by the AudioServer, which reports them leaked at exit. stop() only queues the
## playback's removal for the mixer, so the quit waits QUIT_FRAMES.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_quietly()


func _quit_quietly() -> void:
	print("[Audio] Quitting: stopping every sound and the music")
	if _music_fade != null:
		_music_fade.kill()
	for player in _sfx_players:
		player.stop()
	_menu_voice.stop()
	for player in _music_players:
		player.stop()
	for i in QUIT_FRAMES:
		await get_tree().process_frame
	get_tree().quit()


## The SFX pool and the two music players (one fades in while the other fades out); the
## window's close button quits through _quit_quietly.
func _setup_audio() -> void:
	for i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.bus = SFX_BUS
		add_child(player)
		_sfx_players.append(player)
		_sfx_started.append(-INF)
		_sfx_until.append(-INF)
	_menu_voice = AudioStreamPlayer.new()
	_menu_voice.name = "SfxMenu"
	_menu_voice.bus = SFX_BUS
	add_child(_menu_voice)
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.name = "Music%d" % i
		player.bus = MUSIC_BUS
		add_child(player)
		_music_players.append(player)
	get_tree().set_auto_accept_quit(false)
	get_tree().node_added.connect(_on_node_added)


## Reports every missing piece of the audio (log and error label): a bus missing from
## default_bus_layout.tres, a sound effect or syllable file, the title or results loop (the
## chapters' and modes' loops are data, checked by Content: I23). Returns whether all is there.
func check_audio() -> bool:
	var problems: Array[String] = []
	for bus: StringName in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			problems.append("Audio bus '%s' is missing from res://default_bus_layout.tres; its sounds play on Master" % bus)
	var sounds: Array[StringName] = SFX_IDS.duplicate()
	sounds.append_array(blurt_ids())
	for id: StringName in sounds:
		if not ResourceLoader.exists(sfx_path % id):
			problems.append("Sound effect '%s' is missing: %s (run python3 tools/sfx.py)" % [id, sfx_path % id])
	for track: String in [TITLE_TRACK, RESULTS_TRACK]:
		if not ResourceLoader.exists(music_path % track):
			problems.append("Music track '%s' is missing: %s (run python3 tools/music.py)" % [track, music_path % track])
	for problem in problems:
		report_error(problem)
	if problems.is_empty():
		print("[Audio] %d sound effects, the title and results loops and the %s and %s buses are in place (driver %s%s)" % [
			sounds.size(), MUSIC_BUS, SFX_BUS, AudioServer.get_driver_name(), ", silent: sounds are only recorded" if audio_silent() else ""])
	return problems.is_empty()


## The ids of the rival's syllables (blurt_<timbre>_<vowel>), played from SFX_PATH.
static func blurt_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for timbre in BLURT_TIMBRES:
		for vowel in BLURT_VOWELS:
			ids.append(StringName("blurt_%s_%s" % [timbre, vowel]))
	return ids


## True without an audio device (the Dummy driver of headless runs): sounds and loops are
## then only recorded, never started (that driver never mixes, so they would never finish).
static func audio_silent() -> bool:
	return AudioServer.get_driver_name() == SILENT_AUDIO_DRIVER


## Plays sound effect `id` (one of SFX_IDS) on the SFX bus at `pitch` and logs it ("[Audio]
## SFX <id>", with " x<pitch>" when the pitch is not 1). A
## missing or unknown sound is reported (once) and plays nothing.
func play_sfx(id: StringName, pitch := 1.0) -> void:
	var stream := _sound(id)
	if stream == null:
		return
	_log_sound(id, pitch)
	print("[Audio] SFX %s%s" % [id, " x%.3f" % pitch if pitch != 1.0 else ""])
	_start_voice(stream, pitch)


## Plays sound effect `id` (one of SFX_IDS) `delay` seconds from now through play_sfx (logged
## then); the wait runs on the sound clock, so it holds while the audio is paused and
## outlives a scene change. An unknown or missing sound is reported now and never queued.
func play_sfx_later(id: StringName, delay: float) -> void:
	if _sound(id) == null:
		return
	var queued := Syllable.new()
	queued.sound = id
	queued.at = _clock + delay
	_later_queue.append(queued)
	_later_queue.sort_custom(func(a: Syllable, b: Syllable) -> bool: return a.at < b.at)
	print("[Audio] SFX %s in %.2f s" % [id, delay])


## The sounds play_sfx_later queued and not started yet.
func sfx_waiting() -> int:
	return _later_queue.size()


## Plays the rival's blurt for heckle `line` of `category` (blurt_plan) and logs it as
## "[Audio] SFX heckle_<category>"; its syllables start one after another on the sound clock
## (held while paused).
func play_heckle(category: String, line: String) -> void:
	var plan := blurt_plan(category, line)
	if plan.is_empty():
		report_error("No blurt for the heckle category '%s' (GameState.HECKLE_VOICES)" % category)
		return
	var id := StringName("heckle_" + category)
	_log_sound(id)
	var heard := PackedStringArray()
	for syllable in plan:
		heard.append("%s x%.2f" % [syllable.sound.trim_prefix("blurt_"), syllable.pitch])
		var queued := Syllable.new()
		queued.sound = syllable.sound
		queued.pitch = syllable.pitch
		queued.at = _clock + syllable.at
		_blurt_queue.append(queued)
	print("[Audio] SFX %s: %d syllables (%s) for \"%s\"" % [id, plan.size(), ", ".join(heard), line])


## The blurt of heckle `line` in `category`: one syllable per word of the line (at most
## BLURT_SYLLABLES_MAX), the timbre and base pitch from HECKLE_VOICES, each syllable's vowel,
## pitch and gap drawn from an RNG seeded by the line, so the same line always gives the same
## blurt. Empty for an unknown category.
static func blurt_plan(category: String, line: String) -> Array[Syllable]:
	var plan: Array[Syllable] = []
	if not HECKLE_VOICES.has(category):
		return plan
	var timbre: String = HECKLE_VOICES[category][0]
	var base: float = HECKLE_VOICES[category][1]
	var rng := RandomNumberGenerator.new()
	rng.seed = line.hash()
	var at := 0.0
	for i in clampi(line.split(" ", false).size(), 1, BLURT_SYLLABLES_MAX):
		var syllable := Syllable.new()
		syllable.sound = StringName("blurt_%s_%s" % [timbre, BLURT_VOWELS[rng.randi_range(0, BLURT_VOWELS.size() - 1)]])
		syllable.pitch = base * rng.randf_range(0.88, 1.15)
		syllable.at = at
		at += BLURT_GAP * rng.randf_range(0.8, 1.2)
		plan.append(syllable)
	return plan


func _log_sound(id: StringName, pitch := 1.0) -> void:
	sfx_log.append(id)
	sfx_pitches.append(pitch)
	while sfx_log.size() > SFX_LOG_SIZE:
		sfx_log.pop_front()
	while sfx_pitches.size() > sfx_log.size():
		sfx_pitches.pop_front()


## The stream of sound `id` (SFX_IDS or a syllable), loaded once; a sound that is unknown,
## missing or unloadable is reported once (with its path) and is null.
func _sound(id: StringName) -> AudioStream:
	var path := sfx_path % id
	if _sounds.has(path):
		return _sounds[path]
	var stream: AudioStream = null
	if not id in SFX_IDS and not id in blurt_ids():
		report_error("Unknown sound effect '%s' (not in GameState.SFX_IDS)" % id)
	elif not ResourceLoader.exists(path):
		report_error("Sound effect '%s' is missing: %s (run python3 tools/sfx.py)" % [id, path])
	else:
		stream = load(path) as AudioStream
		if stream == null:
			report_error("Sound effect '%s' at %s cannot be loaded as audio" % [id, path])
	_sounds[path] = stream
	return stream


## Starts `stream` at `pitch`: while the audio is paused on the menu voice (the pool's
## players may all be held, and a held sound is never taken over), otherwise on a free pool
## player (else on the one that started first; nothing is held then). Without an audio
## device it is only recorded.
func _start_voice(stream: AudioStream, pitch: float) -> void:
	if stream == null:
		return
	if audio_paused:
		_menu_voice.stream = stream
		_menu_voice.pitch_scale = pitch
		if not audio_silent():
			_menu_voice.play()
			_check_started(_menu_voice, "Sound '%s'" % stream.resource_path.get_file())
		return
	var pick := 0
	for i in _sfx_players.size():
		if _sfx_until[i] <= _clock:
			pick = i
			break
		if _sfx_started[i] < _sfx_started[pick]:
			pick = i
	var player := _sfx_players[pick]
	_sfx_started[pick] = _clock
	_sfx_until[pick] = _clock + stream.get_length() / pitch
	player.stream = stream
	player.pitch_scale = pitch
	player.stream_paused = false
	if not audio_silent():
		player.play()
		_check_started(player, "Sound '%s'" % stream.resource_path.get_file())


## The blurt syllables queued and not started yet.
func blurt_syllables_waiting() -> int:
	return _blurt_queue.size()


## With an audio device, `player` must be playing right after play(): `what` did not start
## otherwise (reported, never silent).
func _check_started(player: AudioStreamPlayer, what: String) -> void:
	if not player.playing:
		report_error("%s did not start playing on %s (bus %s)" % [what, player.name, player.bus])


## The sounds still in flight (started and not over yet, or held by the pause).
func sounds_in_flight() -> int:
	var count := 0
	for i in _sfx_players.size():
		if _sfx_until[i] > _clock or _sfx_players[i] in _held:
			count += 1
	return count


## The players the current pause holds (their stream_paused set; empty when not paused).
## Without an audio device nothing really plays, so tests read the hold from here.
func held_players() -> Array[AudioStreamPlayer]:
	return _held.duplicate()


## The pool players and, last, the menu voice (tests check the bus and the pause hold).
func sfx_players() -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = _sfx_players.duplicate()
	players.append(_menu_voice)
	return players


## The two music players (tests check the bus and the stream).
func music_players() -> Array[AudioStreamPlayer]:
	return _music_players


## Matches the audio to the tree's pause: when it pauses, the sounds in flight are held
## where they are and the music ducks by PAUSE_DUCK_DB; when it runs again they continue
## and the music comes back. Play calls it right after pausing, before its pause sound, so
## that sound (and the menu's taps) play; _process catches any other pause. Logged.
func sync_audio_pause() -> void:
	var paused := get_tree().paused
	if paused == audio_paused:
		return
	audio_paused = paused
	if paused:
		_held.clear()
		_held_at = _clock
		for i in _sfx_players.size():
			if _sfx_until[i] > _clock:
				var was_playing := _sfx_players[i].playing
				_sfx_players[i].stream_paused = true
				_held.append(_sfx_players[i])
				# With an audio device a sound still playing must now be paused, not running on.
				if was_playing and not _sfx_players[i].stream_paused:
					report_error("Sound on %s kept playing when the game paused (stream_paused did not hold it)" % _sfx_players[i].name)
		held_sounds = _held.size()
		print("[Audio] Paused: %d sounds held, %d blurt syllables waiting, music ducked by %.0f dB" % [held_sounds, _blurt_queue.size(), -PAUSE_DUCK_DB])
	else:
		var paused_for := _clock - _held_at
		for player in _held:
			player.stream_paused = false
			_sfx_until[_sfx_players.find(player)] += paused_for
		for syllable in _blurt_queue:
			syllable.at += paused_for
		for later in _later_queue:
			later.at += paused_for
		print("[Audio] Resumed after %.2f s: %d sounds continue, the music is back to full" % [paused_for, _held.size()])
		_held.clear()
		held_sounds = 0
	_apply_volumes()


## The loop of flow state `to` entered with `args`: the title's for the title, the
## selects, the settings and the credits, the chapter's (a campaign level) or the mode's in a run, the results'; "" for a
## run that cannot start (an unknown level or mode: the music stays as it is).
static func track_for(to: Flow, args: Dictionary) -> String:
	match to:
		Flow.PLAY:
			if args.has("level"):
				var level_id := str(args["level"])
				return Content.chapter(Content.level(level_id).chapter).music if Content.has_level(level_id) else ""
			var mode_id := str(args.get("mode", ENDLESS_MODE))
			for spec in Content.modes():
				if spec.id == mode_id:
					return spec.music
			return ""
		Flow.RESULTS:
			return RESULTS_TRACK
	return TITLE_TRACK


## Asks for loop `track`: the same loop keeps playing untouched; another crossfades in over
## CROSSFADE_TIME (logged "[Audio] Music <track>"). A missing loop is reported (once) and the
## music stays as it is. Without an audio device the loop is only recorded.
func play_music(track: String) -> void:
	if track == "" or track == music_track:
		return
	var path := music_path % track
	if not _tracks.has(path):
		var stream: AudioStream = null
		if not ResourceLoader.exists(path):
			report_error("Music track '%s' is missing: %s (run python3 tools/music.py)" % [track, path])
		else:
			stream = load(path) as AudioStream
			if stream == null:
				report_error("Music track '%s' at %s cannot be loaded as audio" % [track, path])
		_tracks[path] = stream
	if _tracks[path] == null:
		return
	var from := music_track
	music_track = track
	music_changes += 1
	print("[Audio] Music %s (%s)" % [track, "crossfading from %s over %.2f s" % [from, CROSSFADE_TIME] if from != "" else "first loop"])
	if _music_fade != null:
		_music_fade.kill()
	var old := _music_players[_music_current]
	_music_current = 1 - _music_current
	var player := _music_players[_music_current]
	player.stream = _tracks[path]
	player.volume_linear = 0.0
	if not audio_silent():
		player.play()
		_check_started(player, "Music track '%s'" % track)
	_music_fade = create_tween().set_parallel()
	_music_fade.tween_property(player, "volume_linear", 1.0, CROSSFADE_TIME)
	if from != "":
		_music_fade.tween_property(old, "volume_linear", 0.0, CROSSFADE_TIME)
		_music_fade.chain().tween_callback(old.stop)


## The player playing (or fading in) the current loop.
func music_player() -> AudioStreamPlayer:
	return _music_players[_music_current]


## Sets the music volume (0..VOLUME_MAX), applies it to the Music bus and logs it; saves
## unless `save` is false (a slider still held: the settings screen saves on its release).
func set_music_volume(value: int, save := true) -> void:
	music_volume = clampi(value, 0, VOLUME_MAX)
	print("[Audio] Music volume %d%s" % [music_volume, "" if save else " (saved once the slider is released)"])
	_apply_volumes()
	if save:
		save_game()


## Sets the sound effects volume (0..VOLUME_MAX), applies it to the SFX bus and logs it;
## saves unless `save` is false (as set_music_volume).
func set_sfx_volume(value: int, save := true) -> void:
	sfx_volume = clampi(value, 0, VOLUME_MAX)
	print("[Audio] SFX volume %d%s" % [sfx_volume, "" if save else " (saved once the slider is released)"])
	_apply_volumes()
	if save:
		save_game()


## Mutes or unmutes the Music bus at once (keeping music_volume); logs and saves.
func set_music_muted(on: bool) -> void:
	music_muted = on
	print("[Audio] Music %s" % ("muted" if on else "unmuted"))
	_apply_volumes()
	save_game()


## Mutes or unmutes the SFX bus at once (keeping sfx_volume); logs and saves.
func set_sfx_muted(on: bool) -> void:
	sfx_muted = on
	print("[Audio] SFX %s" % ("muted" if on else "unmuted"))
	_apply_volumes()
	save_game()


## Turns reduce motion on or off (screen shake, the transition wipe, the pop-ups' bounce and
## shake and the title's drift follow it from their next use); logs, saves and emits
## reduce_motion_changed.
func set_reduce_motion(on: bool) -> void:
	reduce_motion = on
	print("[Game] Reduce motion %s" % ("on: no screen shake, plain fades, steady pop-ups and title" if on else "off"))
	save_game()
	reduce_motion_changed.emit(on)


## The bus volume in dB of setting `volume` (0..VOLUME_MAX): linear in loudness,
## SILENT_VOLUME_DB at 0; `duck_db` (0 or PAUSE_DUCK_DB) is added above 0.
static func bus_volume_db(volume: int, duck_db := 0.0) -> float:
	if volume <= 0:
		return SILENT_VOLUME_DB
	return linear_to_db(volume / float(VOLUME_MAX)) + duck_db


## Sets the Music and SFX buses from the settings: the volume (the music ducked while the
## audio is paused) and the mute (muted, or a volume of 0).
func _apply_volumes() -> void:
	var settings: Array[Array] = [[MUSIC_BUS, music_volume, music_muted, PAUSE_DUCK_DB if audio_paused else 0.0], [SFX_BUS, sfx_volume, sfx_muted, 0.0]]
	for entry: Array in settings:
		var bus := AudioServer.get_bus_index(entry[0])
		if bus < 0:
			continue
		AudioServer.set_bus_volume_db(bus, bus_volume_db(entry[1], entry[3]))
		AudioServer.set_bus_mute(bus, entry[2] or entry[1] == 0)
	audio_settings_changed.emit()


## Every Button entering the tree plays "ui_tap" when pressed, unless it is in
## OWN_SOUND_GROUP (checked at the press, so a group added later still counts).
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	# A bound callable never compares equal to another, so a meta marks the hook (a button
	# re-entering the tree keeps one connection).
	if button != null and not button.has_meta(&"game_ui_tap"):
		button.set_meta(&"game_ui_tap", true)
		button.pressed.connect(_on_button_pressed.bind(button))


func _on_button_pressed(button: BaseButton) -> void:
	if not button.is_in_group(OWN_SOUND_GROUP):
		play_sfx(&"ui_tap")
