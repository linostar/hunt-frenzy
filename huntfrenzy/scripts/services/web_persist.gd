class_name WebPersist
extends Node
## Game/Web: what only the web build needs from the page. On the web, user:// is an in-memory
## filesystem (Emscripten IDBFS) that Godot 4.7.1 copies to IndexedDB asynchronously,
## ignoring a failed copy; so a web save is logged as written by SaveStore, then confirmed (or
## reported as lost) here by reading it back from IndexedDB (WEB_PERSIST_CHECK_JS), and
## storage that is unavailable at start (OS.is_userfs_persistent() false) is reported at once.
## It also watches the document's visibilitychange (page_hidden), which Godot does not report.

## Emitted when the web page becomes hidden (another tab, the app sent to the background).
## Godot's web build reports window blur but not page visibility, so this watches the
## document's visibilitychange event itself.
signal page_hidden

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

## False on the web when the browser gave Godot no IndexedDB at start (check_storage).
var storage_persistent := true
## The number of the latest web save check; an answer to an older one is ignored.
var persist_check := 0

## The JavaScript visibilitychange listener (web only); kept so it is not freed.
var _visibility_listener: JavaScriptObject
## The JavaScript callback of the web save checks (web only); kept so it is not freed.
var _persist_callback: JavaScriptObject

@onready var _game := get_parent() as GameState


## On the web, listens for the document's visibilitychange and emits page_hidden when
## the page is hidden.
func watch_page_visibility() -> void:
	if not OS.has_feature("web"):
		return
	var document := JavaScriptBridge.get_interface("document")
	if document == null:
		_game.report_error("Cannot watch the page's visibility: no document object")
		return
	_visibility_listener = JavaScriptBridge.create_callback(_on_visibility_changed)
	document.addEventListener("visibilitychange", _visibility_listener)


func _on_visibility_changed(_args: Array) -> void:
	# A JavaScript boolean arrives as a number, so ask for one explicitly.
	var hidden := int(JavaScriptBridge.eval("document.hidden ? 1 : 0", true)) == 1
	print("[Game] Page %s" % ("hidden" if hidden else "visible"))
	if hidden:
		page_hidden.emit()


## On the web, user:// persists only when the browser gave Godot IndexedDB at start;
## without it every save lives in memory until the page closes, which the player is told
## at once. Public for tests.
func check_storage(persistent: bool) -> void:
	storage_persistent = persistent
	if persistent:
		print("[Game] Browser storage (IndexedDB) is available for %s (%s)" % [_game.save.save_path, ProjectSettings.globalize_path(_game.save.save_path)])
		return
	_game.report_error("Browser storage (IndexedDB) is unavailable (private browsing or blocked site data): best scores are kept only until the page closes")


## The answer to web save check `check`: `ok` when IndexedDB holds the save, else
## `detail` says why not. An answer to an older check is ignored (a newer save replaced
## what it looked for). Public for tests.
func persist_checked(check: int, ok: bool, detail: String) -> void:
	if check != persist_check:
		print("[Game] Ignored the answer to save check %d (superseded by check %d)" % [check, persist_check])
		return
	if ok:
		print("[Game] Save persisted to browser storage: %s after %s ms (check %d)" % [_game.save.save_path, detail, check])
		return
	_game.save.fail_save("The save (%s) was written to %s but browser storage (IndexedDB) did not keep it: %s (check %d); it is lost when the page closes" % [_game.save.save_summary(), _game.save.save_path, detail, check], "browser storage did not keep it (%s)" % detail)


## Asks the page to confirm that IndexedDB holds `text` at the save path (see WEB_PERSIST_CHECK_JS).
func check_persisted(text: String) -> void:
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
	var key := ProjectSettings.globalize_path(_game.save.save_path)
	window.huntFrenzyCheckPersisted(key.substr(0, key.find("/", 1)), key, text, WEB_PERSIST_TIMEOUT_MSEC, persist_check, _persist_callback)


func _on_persist_checked(args: Array) -> void:
	persist_checked(int(args[0]), int(args[1]) == 1, str(args[2]))
