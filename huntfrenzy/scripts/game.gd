class_name GameState
extends Node
## Autoload "Game" (scenes/game.tscn): the app flow state machine and its scene
## transitions, the save (the Endless best score, the campaign progress and the settings),
## ScreenFit (the visible and safe-area rects in base units) and the rotate overlay.
## Every flow change goes through goto(), which fades a cover over the screen
## (touches blocked), swaps the scene, fades the cover away and logs the transition
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

enum Flow { TITLE, PLAY, RESULTS, CHAPTER_SELECT, LEVEL_SELECT }

## Absolute path of this autoload, for nodes inside the tree.
const AUTOLOAD_PATH := ^"/root/Game"
const SCENE_PATHS: Dictionary[Flow, String] = {
	Flow.TITLE: "res://scenes/title.tscn",
	Flow.PLAY: "res://scenes/play.tscn",
	Flow.RESULTS: "res://scenes/results.tscn",
	Flow.CHAPTER_SELECT: "res://scenes/chapter_select.tscn",
	Flow.LEVEL_SELECT: "res://scenes/level_select.tscn",
}
## The Endless mode's id in data/modes.json.
const ENDLESS_MODE := "endless"
const SAVE_PATH := "user://save.json"
## The save of tool runs (see _ready); tests delete it when they finish.
const TOOL_SAVE_PATH := "user://tool_save.json"
## The save format's version. Every change to the format bumps it and appends one step to
## save_migrations(), so saves of older versions are upgraded, not discarded; a newer
## version is backed up and replaced.
const SAVE_VERSION := 2
## The keys of a save, each with the type its value must have. `levels` maps a level id to
## {"stars", "score"} (its Campaign.Record); `settings` holds SETTINGS_KEYS.
const SAVE_KEYS: Dictionary[String, Variant.Type] = {"version": TYPE_INT, "best_endless": TYPE_INT, "levels": TYPE_DICTIONARY, "settings": TYPE_DICTIONARY}
const SAVE_SCORE_MAX := 999999999
## The most backups of saves with dropped campaign entries (dropped_backup_path).
const DROPPED_BACKUPS_MAX := 20
## The keys of a saved level entry.
const LEVEL_KEYS: Array[String] = ["stars", "score"]
## The saved settings: the music and sound effects volumes (whole 0..VOLUME_MAX) and mutes
## (true or false). There is no settings screen yet; the audio pass applies them to buses.
const SETTINGS_KEYS: Array[String] = ["music", "sfx", "music_muted", "sfx_muted"]
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
## Seconds the cover takes to fade in, and again to fade out.
const FADE_TIME := 0.15

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
## Tests set this (base units) to stand in for a notched screen's safe area; it applies
## from the next ScreenFit update. An empty rect means the display's own safe area.
var safe_area_override := Rect2()
## Where the save lives: SAVE_PATH, or TOOL_SAVE_PATH in tool runs.
var save_path := SAVE_PATH
## The best Endless score, persisted in the save.
var best_endless := 0
## The campaign progress, persisted in the save: level id -> its best stars and score. A
## level without an entry was never finished.
var progress: Dictionary[String, Campaign.Record] = {}
## Settings, persisted in the save: the music and sound effects volumes (0..VOLUME_MAX)
## and mutes.
var music_volume := DEFAULT_MUSIC_VOLUME
var sfx_volume := DEFAULT_SFX_VOLUME
var music_muted := false
var sfx_muted := false
## Why the latest save failed, short enough for the results screen; "" after a save that
## worked (on the web: once written; a later IndexedDB failure sets it again).
var save_error := ""
## False on the web when the browser gave Godot no IndexedDB at start (check_storage).
var storage_persistent := true
## The number of the latest web save check; an answer to an older one is ignored.
var persist_check := 0

var _transitioning := false
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

@onready var _cover: ColorRect = $Fade/Cover
@onready var _error_label: Label = $Fade/ErrorLabel
@onready var _rotate_overlay: Control = $RotateLayer/RotateOverlay


func _ready() -> void:
	# Tool runs (the tests, the project check, the headless main-scene run) drive the
	# tree from a SceneTree script; they must never read or overwrite the player's save.
	if get_tree().get_script() != null:
		save_path = TOOL_SAVE_PATH
	if OS.has_feature("web"):
		check_storage(OS.is_userfs_persistent())
	load_game()
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


## Fades to the scene of `new_state`, passing `args` through flow_args: the cover
## fades in (FADE_TIME), the scene changes, then the cover fades out, and
## transition_finished fires. Touches are blocked until then. Ignored (with a log
## line) while a transition is running.
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
	_transitioning = true
	_log_transition("%s -> %s (%s) args=%s" % [from_name, to_name, path, args])
	_error_label.hide()
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	_cover.show()
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


## Starts a new Endless run with a fresh seed (the title's Endless, Restart, Play again).
func start_endless() -> void:
	goto(Flow.PLAY, {"mode": ENDLESS_MODE, "seed": randi()})


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
	var best := Campaign.merge(before, earned, score)
	progress[level.id] = best
	var new_best := score > (before.score if before != null else 0)
	var unlocked := ""
	if next != null and not was_open and Campaign.is_unlocked(next, progress):
		unlocked = "; %s unlocked" % next.id
	print("[Game] Level %s finished: score %d, %d stars (%s); best %d stars, score %d (was %s)%s" % [
		level.id, score, earned, "passed" if Campaign.is_passed(earned) else "not passed", best.stars, best.score,
		"%d stars, score %d" % [before.stars, before.score] if before != null else "never finished", unlocked])
	save_game()
	return new_best


## Records the score of a finished Endless run: a new best is saved at once (save_error
## says why when that failed). Returns true when it is a new best.
func record_endless(score: int) -> bool:
	if score <= best_endless:
		print("[Game] Endless score %d does not beat the best %d" % [score, best_endless])
		return false
	print("[Game] New Endless best: %d (was %d)" % [score, best_endless])
	best_endless = score
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
		"version": SAVE_VERSION, "best_endless": best_endless, "levels": levels,
		"settings": {"music": music_volume, "sfx": sfx_volume, "music_muted": music_muted, "sfx_muted": sfx_muted},
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
		print("[Game] Browser storage (IndexedDB) is available for %s" % save_path)
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


## What the save holds, for log lines: the Endless best, the levels finished with their
## stars, and the settings.
func save_summary() -> String:
	var earned := 0
	for id in progress:
		earned += progress[id].stars
	return "Endless best %d, %d levels finished (%d stars), music %d%s, sfx %d%s" % [
		best_endless, progress.size(), earned, music_volume, " muted" if music_muted else "", sfx_volume, " muted" if sfx_muted else ""]


## Loads save_path. A missing save starts fresh (a log line only); an older version is
## upgraded (save_migrations, logged) and written back at once; an unreadable, corrupt or
## unknown-version one is reported (push_error and the error label), moved to backup_path()
## and replaced by a fresh save; a bad campaign entry is reported and dropped (the rest
## loads; the original is copied to dropped_backup_path() and the save is then written back
## without it, so it is reported once, or left as it is when the copy fails). With content
## errors the save is left unread and untouched (its levels are checked against
## levels.json; the title disables play). A JSON instance reports parse errors as return
## values, so each problem is reported once, by us.
func load_game() -> void:
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
	best_endless = 0
	progress = {}
	music_volume = DEFAULT_MUSIC_VOLUME
	sfx_volume = DEFAULT_SFX_VOLUME
	music_muted = false
	sfx_muted = false


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
	var best := int(saved["best_endless"])
	if best < 0 or best > SAVE_SCORE_MAX:
		return "best_endless %d is outside 0..%d" % [best, SAVE_SCORE_MAX]
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
	best_endless = best
	progress = loaded
	music_volume = int(settings["music"])
	sfx_volume = int(settings["sfx"])
	music_muted = settings["music_muted"]
	sfx_muted = settings["sfx_muted"]
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
	return [_save_v1_to_v2]


## Version 1 -> 2: the campaign arrives (no level finished yet) and the settings are saved,
## at their defaults; the Endless best is kept as it is.
static func _save_v1_to_v2(saved: Dictionary) -> void:
	saved["levels"] = {}
	saved["settings"] = {"music": DEFAULT_MUSIC_VOLUME, "sfx": DEFAULT_SFX_VOLUME, "music_muted": false, "sfx_muted": false}
	print("[Game] Save upgrade 1 -> 2: Endless best %s kept, no campaign levels finished yet, default settings" % _number_text(saved.get("best_endless")))


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


## How far the cover hides the screen: 0 clear, 1 covered (tests read it).
func cover_progress() -> float:
	return _cover.modulate.a


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_cover, "modulate:a", alpha, FADE_TIME)
	await tween.finished


func _end_fade() -> void:
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.hide()
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
