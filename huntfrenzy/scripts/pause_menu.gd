class_name PauseMenu
extends Node
## Play/Pause: the run's pause menu (PauseLayer/PauseMenu). The pause button, Escape
## (CancelKey), the window or app losing focus or visibility (Play's notifications, and
## Game.web.page_hidden for the web page), and the rotate overlay hiding after it showed during
## the run (or while the menu is open) open it with the tree paused; Resume (or Escape on the
## open menu) continues the run unchanged, Restart starts the run again (Play.restart), Quit
## goes to the title (Play.quit). It plays "pause" and "resume" and holds the run's sounds and
## ducks the music while open (Game.audio.sync_audio_pause); its Music and SFX toggles mute
## their bus at once (saved). Its Settings button opens the settings screen over the paused run
## (open_settings: the tree stays paused, the sounds held and the music ducked); its Back (or
## Escape) closes it and focuses Settings again, and the menu's toggles follow whatever it
## changed.

const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
## The pause menu's mute toggles: the bus and whether it is on.
const MUSIC_TOGGLE_TEXT := "Music: %s"
const SFX_TOGGLE_TEXT := "SFX: %s"

## Every cause the pause menu opened for, oldest first (tests read it).
var pause_log: Array[String] = []

## The settings opened over the pause menu (null when closed).
var _settings: Settings
## True while the rotate overlay that showed during the run (or before it, during the
## transition in) has not hidden yet.
var _rotated := false

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _play := get_parent() as Play
@onready var _cancel_key: CancelKey = $"../CancelKey"
@onready var _pause_button: Button = $"../Hud/Bar/PauseButton"
@onready var _pause_layer: CanvasLayer = $"../PauseLayer"
@onready var _pause_menu: Control = $"../PauseLayer/PauseMenu"
@onready var _pause_panel: Control = $"../PauseLayer/PauseMenu/Panel"
@onready var _resume_button: Button = $"../PauseLayer/PauseMenu/Panel/ResumeButton"
@onready var _restart_button: Button = $"../PauseLayer/PauseMenu/Panel/RestartButton"
@onready var _quit_button: Button = $"../PauseLayer/PauseMenu/Panel/QuitButton"
@onready var _music_toggle: Button = $"../PauseLayer/PauseMenu/Panel/MusicToggle"
@onready var _sfx_toggle: Button = $"../PauseLayer/PauseMenu/Panel/SfxToggle"
@onready var _settings_button: Button = $"../PauseLayer/PauseMenu/Panel/SettingsButton"


func _ready() -> void:
	_game.screen.rotate_overlay_changed.connect(_on_rotate_overlay_changed)
	_game.web.page_hidden.connect(open_pause.bind("page hidden"))
	_cancel_key.triggered.connect(_on_cancel)
	_pause_button.pressed.connect(open_pause.bind("pause button"))
	_resume_button.pressed.connect(resume)
	_restart_button.pressed.connect(_play.restart)
	_quit_button.pressed.connect(_play.quit)
	_settings_button.pressed.connect(open_settings)
	_music_toggle.toggled.connect(_on_music_toggled)
	_sfx_toggle.toggled.connect(_on_sfx_toggled)
	_game.audio.audio_settings_changed.connect(_show_audio_settings)
	_show_audio_settings()


## Called once the run has started: the overlay may have shown before the scene existed
## (during the fade into the run); Play.show_crosshair already kept the arrow then.
func note_rotation_at_start() -> void:
	_rotated = not _play.is_over() and _game.screen.is_rotate_overlay_shown()


## Opens the pause menu (focused on Resume) with the tree paused, for `cause`. While it
## is open the tree is kept paused (the rotate overlay may have unpaused it). Ignored
## once the run is over; during the transition into the run it opens once that is done.
func open_pause(cause: String) -> void:
	if _play.is_over():
		return
	if _game.flow.is_transitioning():
		print("[Play] Pause (%s) waits for the transition to finish" % cause)
		_game.flow.transition_finished.connect(open_pause.bind(cause).unbind(1), CONNECT_ONE_SHOT)
		return
	get_tree().paused = true
	# The run's sounds are held before the menu's own sound starts.
	_game.audio.sync_audio_pause()
	if _pause_menu.visible:
		return
	_pause_menu.show()
	_play.show_crosshair(false, "paused")
	_game.audio.play_sfx(&"pause")
	_resume_button.grab_focus(true)
	pause_log.append(cause)
	print("[Play] Paused (%s): wave %d at t %.2f, score %d%s" % [cause, _play.wave.index, _play.wave_clock, _play.scoring.score, _play.clock_note()])


## Closes the pause menu and continues the run where it stopped (`cause`: "Resume" for
## the button, "Escape"). Ignored once the run is over (the menu of a run that could not
## start stays up).
func resume(cause := "Resume") -> void:
	if not _pause_menu.visible or _play.is_over():
		return
	close_settings()
	_pause_menu.hide()
	# On the menu voice, while the audio is still paused, so it never takes a held sound's voice.
	_game.audio.play_sfx(&"resume")
	get_tree().paused = false
	_game.audio.sync_audio_pause()
	_play.show_crosshair(true)
	print("[Play] Resumed (%s): wave %d at t %.2f, score %d%s" % [cause, _play.wave.index, _play.wave_clock, _play.scoring.score, _play.clock_note()])


func is_paused() -> bool:
	return _pause_menu.visible


## A run that cannot start: the menu shows with only the way back to the title.
func show_cannot_start() -> void:
	_resume_button.disabled = true
	_restart_button.disabled = true
	_pause_menu.show()
	_quit_button.grab_focus(true)


## The run is over: the menu goes away (Play._stop unpauses the tree).
func hide_menu() -> void:
	_pause_menu.hide()


## Opens the settings over the open pause menu (the run stays paused); ignored when the
## menu is closed or the settings already show. Logged.
func open_settings() -> void:
	if not _pause_menu.visible or _settings != null or _play.is_over():
		return
	_settings = SETTINGS_SCENE.instantiate() as Settings
	_settings.overlay = true
	_settings.closed.connect(close_settings)
	# The menu's dim stays (it is the pause itself); its panel hides under the settings.
	_pause_panel.hide()
	_pause_layer.add_child(_settings)
	print("[Play] Settings opened over the paused run (wave %d at t %.2f%s)" % [_play.wave.index, _play.wave_clock, _play.clock_note()])


## Closes the settings opened over the pause menu and focuses its Settings button again;
## nothing when they are not open. Logged.
func close_settings() -> void:
	if _settings == null:
		return
	_settings.queue_free()
	_settings = null
	_pause_panel.show()
	_settings_button.grab_focus(true)
	print("[Play] Settings closed; back to the pause menu")


## The settings open over the pause menu, or null.
func settings_overlay() -> Settings:
	return _settings


## Escape (CancelKey, which runs while paused too) opens the pause menu, resumes the run
## when the menu is open, or closes the settings opened over it.
func _on_cancel() -> void:
	if _settings != null:
		close_settings()
	elif is_paused():
		resume("Escape")
	else:
		open_pause("Escape")


## The overlay hiding unpauses the tree when it paused it; a run it covered (or one whose
## pause menu is open) is paused again, so the menu never shows over a running tree.
func _on_rotate_overlay_changed(shown: bool) -> void:
	if shown:
		_rotated = not _play.is_over()
		_play.show_crosshair(false, "rotate overlay")
	elif _rotated or is_paused():
		_rotated = false
		open_pause("rotate overlay")


## The pause menu's Music toggle: on plays the music, off mutes the Music bus (saved).
func _on_music_toggled(on: bool) -> void:
	if on == not _game.save.music_muted:
		return
	print("[Play] Music toggle pressed: music %s" % ("on" if on else "off"))
	_game.audio.set_music_muted(not on)


## The pause menu's SFX toggle: on plays the sound effects, off mutes the SFX bus (saved).
func _on_sfx_toggled(on: bool) -> void:
	if on == not _game.save.sfx_muted:
		return
	print("[Play] SFX toggle pressed: sound effects %s" % ("on" if on else "off"))
	_game.audio.set_sfx_muted(not on)


## Shows the mutes on the pause menu's toggles (pressed = on), whoever changed them.
func _show_audio_settings() -> void:
	_music_toggle.set_pressed_no_signal(not _game.save.music_muted)
	_music_toggle.text = MUSIC_TOGGLE_TEXT % ("on" if not _game.save.music_muted else "off")
	_sfx_toggle.set_pressed_no_signal(not _game.save.sfx_muted)
	_sfx_toggle.text = SFX_TOGGLE_TEXT % ("on" if not _game.save.sfx_muted else "off")
