class_name SaveStore
extends Node
## Game/Save: the save (the best score of each mode, the campaign progress and the settings)
## and the data it holds. The save is versioned JSON at save_path, loaded at start: a missing
## save starts fresh, an older version is upgraded step by step (save_migrations, logged), a
## corrupt or unknown-version one is moved to backup_path(), reported (log and error label)
## and replaced by a fresh save. A campaign entry naming a level that is not in levels.json,
## or holding stars or a score out of range, is dropped (each logged with its stored value);
## the rest of the save loads, the original file is first copied to a free
## dropped_backup_path() (never over another backup), and only then is the save written back
## without the dropped entries; the error label says how many were dropped and where the
## original is. If the copy fails, the save is not written back (the original stays).
## A failed save sets save_error (a short reason the results screen shows), is reported and
## emits save_failed. On the web a save is confirmed from IndexedDB by WebPersist.

## Emitted when a save fails: at once, or on the web when browser storage does not keep
## it. `reason` is save_error.
signal save_failed(reason: String)
## Emitted when the reduce motion setting changes (the settings screen follows it).
signal reduce_motion_changed(on: bool)

const SAVE_PATH := "user://save.json"
## The save of tool runs (see GameState._ready); tests delete it when they finish.
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
const BEST_MODES: Array[String] = [GameState.ENDLESS_MODE, GameState.TIME_ATTACK_MODE]
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
## The campaign entries the last load dropped, one log message each (load_game backs the
## original up, then writes the save back without them).
var _dropped_entries: Array[String] = []

@onready var _game := get_parent() as GameState


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
		_game.report_error("Cannot record a best for mode '%s': the save keeps bests only for %s" % [mode.id, BEST_MODES])
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
		fail_save("Could not open '%s' for writing the save: %s; '%s' is unchanged" % [temp, open_error, save_path], "cannot open the save file (%s)" % open_error)
		return false
	var written := file.store_string(text)
	file.close()
	if not written:
		DirAccess.remove_absolute(temp)
		fail_save("Could not write the save to '%s'; '%s' is unchanged" % [temp, save_path], "cannot write the save file")
		return false
	var replaced := DirAccess.rename_absolute(temp, save_path)
	if replaced != OK:
		DirAccess.remove_absolute(temp)
		fail_save("Could not replace save '%s' with '%s': %s; the save is unchanged" % [save_path, temp, error_string(replaced)], "cannot replace the save file (%s)" % error_string(replaced))
		return false
	if not OS.has_feature("web"):
		print("[Game] Saved to %s: version %d, %s" % [save_path, SAVE_VERSION, save_summary()])
		return true
	if not _game.web.storage_persistent:
		fail_save("Wrote the save (%s) to %s in memory only: browser storage is unavailable, so it is lost when the page closes" % [save_summary(), save_path], "browser storage is unavailable")
		return false
	print("[Game] Saved to %s (written; waiting for browser storage to keep it): version %d, %s" % [save_path, SAVE_VERSION, save_summary()])
	_game.web.check_persisted(text)
	return true


## A failed save: `message` (with paths and causes) goes to the log and the error label,
## `reason` to save_error for the results screen.
func fail_save(message: String, reason: String) -> void:
	save_error = reason
	_game.report_error(message)
	save_failed.emit(reason)


## What the save holds, for log lines: the Endless and Time Attack bests, the levels
## finished with their stars, and the settings (", reduce motion" only when it is on).
func save_summary() -> String:
	var earned := 0
	for id in progress:
		earned += progress[id].stars
	return "Endless best %d, Time Attack best %d, %d levels finished (%d stars), music %d%s, sfx %d%s" % [
		best(GameState.ENDLESS_MODE), best(GameState.TIME_ATTACK_MODE), progress.size(), earned, music_volume, " muted" if music_muted else "", sfx_volume, " muted" if sfx_muted else ""] + (", reduce motion" if reduce_motion else "")


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
	_game.audio.apply_volumes()


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
		_game.report_error("Save '%s': %s dropped (see the log), but the original could not be backed up to '%s' (%s); the save is left as it is" % [save_path, dropped, backup if backup != "" else save_path.get_basename() + ".dropped*.json", error_string(copied)])
		return
	print("[Game] Backed up the save with %d dropped campaign entries to %s" % [count, backup])
	_game.report_error("Save '%s': %s dropped (see the log); the original is kept as '%s'" % [save_path, dropped, backup])
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
			_game.report_error(message)
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
	saved["bests"] = {GameState.ENDLESS_MODE: saved["best_endless"], GameState.TIME_ATTACK_MODE: 0}
	saved.erase("best_endless")
	print("[Game] Save upgrade 2 -> 3: Endless best %s kept as bests.%s, Time Attack best 0" % [_number_text(saved["bests"][GameState.ENDLESS_MODE]), GameState.ENDLESS_MODE])


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
		_game.report_error("Save '%s' is %s and could not be moved to '%s' (%s); the game starts fresh and the next save replaces it" % [save_path, problem, backup_path(), error_string(moved)])
		return
	_game.report_error("Save '%s' is %s; it was moved to '%s' and replaced with a fresh save" % [save_path, problem, backup_path()])
	save_game()


## JSON numbers load as floats; accept whole numbers only, and only those a float
## holds exactly (|n| <= 2^53): int() of a larger float is CPU dependent (arm64
## saturates, x86-64 gives INT64_MIN), so range checks after it could be fooled.
static func _is_whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floorf(value) and absf(value) <= SAVE_EXACT_MAX)


## Turns reduce motion on or off (screen shake, the transition wipe, the pop-ups' bounce and
## shake and the title's drift follow it from their next use); logs, saves and emits
## reduce_motion_changed.
func set_reduce_motion(on: bool) -> void:
	reduce_motion = on
	print("[Game] Reduce motion %s" % ("on: no screen shake, plain fades, steady pop-ups and title" if on else "off"))
	save_game()
	reduce_motion_changed.emit(on)
