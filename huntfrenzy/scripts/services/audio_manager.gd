class_name AudioManager
extends Node
## Game/Audio: every sound goes through play_sfx(id) (audio/sfx/<id>.wav, tools/sfx.py), which
## logs "[Audio] SFX <id>" and plays it on the SFX bus from a pool of SFX_VOICES players;
## every Button's press plays "ui_tap" unless it is in OWN_SOUND_GROUP (it plays its own).
## play_sfx_later plays a sound a moment from now (the rival's laugh after his shot) on the
## sound clock (held while paused). The music is one loop per screen (track_for: the title's for the title, the selects, the settings, the
## credits and the top scores, the chapter's or the mode's in a run, the results' on results)
## on the Music bus: SceneFlow.goto asks for it as the transition starts, a screen with the
## same loop leaves it playing, another crossfades in over CROSSFADE_TIME, and every change is
## logged ("[Audio] Music <track>"). The saved volumes and mutes (SaveStore) set the Music and
## SFX buses at start and on every change. While the tree is paused (the pause menu, the
## rotate overlay) the sounds in flight are held and the music is ducked by PAUSE_DUCK_DB
## (sync_audio_pause); sounds started during the pause (the menu's own) play on a reserved
## menu voice, so a held sound is never taken over, and everything held continues when the
## tree runs again. A missing or unloadable sound or loop is reported with its path (log and
## error label); goto() refuses a screen whose loop is missing, as it does a scene's missing
## file. Browsers start audio only after the player's first touch or key: Godot's web
## platform resumes its AudioContext then, and until then the title loop waits silently.

## Emitted when a volume or mute setting changes (the pause menu's toggles follow it).
signal audio_settings_changed

## The audio buses (default_bus_layout.tres): every music player is on MUSIC_BUS, every
## sound effect on SFX_BUS, both sending to Master.
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## The game's sound effects: audio/sfx/<id>.wav (tools/sfx.py EFFECTS makes one per id).
const SFX_PATH := "res://audio/sfx/%s.wav"
## Each sound effect's id, so a misspelt one fails to compile.
const SFX_SHOT := &"shot"
const SFX_EMPTY_CLICK := &"empty_click"
const SFX_OUT_OF_SHELLS := &"out_of_shells"
const SFX_HIT := &"hit"
const SFX_ARMORED_CLANK := &"armored_clank"
const SFX_ARMORED_KILL := &"armored_kill"
const SFX_SPLIT_POP := &"split_pop"
const SFX_GOLDEN_CHIME := &"golden_chime"
const SFX_DECOY_PENALTY := &"decoy_penalty"
const SFX_ESCAPE := &"escape"
const SFX_WAVE_START := &"wave_start"
const SFX_WAVE_CLEAR := &"wave_clear"
const SFX_WAVE_LOST := &"wave_lost"
const SFX_COMBO_UP := &"combo_up"
const SFX_RIVAL_AIM := &"rival_aim"
const SFX_RIVAL_STEAL := &"rival_steal"
const SFX_RIVAL_LAUGH := &"rival_laugh"
const SFX_COUNTDOWN_TICK := &"countdown_tick"
const SFX_TIME_UP := &"time_up"
const SFX_STAR := &"star"
const SFX_NEW_BEST := &"new_best"
const SFX_UI_TAP := &"ui_tap"
const SFX_PAUSE := &"pause"
const SFX_RESUME := &"resume"
const SFX_CALL_QUACK := &"call_quack"
const SFX_CALL_GOSLING := &"call_gosling"
const SFX_CALL_PIGEON := &"call_pigeon"
const SFX_CALL_SWIFT := &"call_swift"
## Every sound effect id (play_sfx refuses any other).
const SFX_IDS: Array[StringName] = [
	SFX_SHOT, SFX_EMPTY_CLICK, SFX_OUT_OF_SHELLS, SFX_HIT, SFX_ARMORED_CLANK, SFX_ARMORED_KILL,
	SFX_SPLIT_POP, SFX_GOLDEN_CHIME, SFX_DECOY_PENALTY, SFX_ESCAPE, SFX_WAVE_START, SFX_WAVE_CLEAR,
	SFX_WAVE_LOST, SFX_COMBO_UP, SFX_RIVAL_AIM, SFX_RIVAL_STEAL, SFX_RIVAL_LAUGH, SFX_COUNTDOWN_TICK,
	SFX_TIME_UP, SFX_STAR, SFX_NEW_BEST, SFX_UI_TAP, SFX_PAUSE, SFX_RESUME, SFX_CALL_QUACK, SFX_CALL_GOSLING,
	SFX_CALL_PIGEON, SFX_CALL_SWIFT,
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


## A sound play_sfx_later queued: its id and the _clock time it starts at.
class LaterSound:
	var sound: StringName
	var at := 0.0

## Where sound effects are (SFX_PATH) and music loops are (MUSIC_PATH); tests swap them to
## check the missing and unloadable paths.
var sfx_path := SFX_PATH
var music_path := MUSIC_PATH
## The ids of the latest sounds played, oldest first (SFX_LOG_SIZE at most), and the pitch
## each played at; tests read them.
var sfx_log: Array[StringName] = []
var sfx_pitches: Array[float] = []
## The loop asked for ("" before the first) and how often it changed (a crossfade each).
var music_track := ""
var music_changes := 0
## True while the tree is paused and the audio with it (sounds held, music ducked).
var audio_paused := false
## Sounds held by the latest pause (sync_audio_pause), until it ends.
var held_sounds := 0

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
## Sounds play_sfx_later queued, each at its _clock time (in order).
var _later_queue: Array[LaterSound] = []
## Loop file -> its stream, or null when it is missing (reported once).
var _tracks: Dictionary[String, AudioStream] = {}
var _music_players: Array[AudioStreamPlayer] = []
## The index in _music_players of the one playing (or fading in) music_track.
var _music_current := 0
var _music_fade: Tween

@onready var _game := get_parent() as GameState


func _process(delta: float) -> void:
	_clock += delta
	# Pauses that did not call sync_audio_pause themselves (a test pausing the tree).
	sync_audio_pause()
	while not audio_paused and not _later_queue.is_empty() and _later_queue[0].at <= _clock:
		var later: LaterSound = _later_queue.pop_front()
		play_sfx(later.sound)


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
## window's close button quits through _quit_quietly. Called first by GameState._ready.
func setup() -> void:
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
## default_bus_layout.tres, a sound effect file, the title or results loop (the
## chapters' and modes' loops are data, checked by Content: I23). Returns whether all is there.
func check_audio() -> bool:
	var problems: Array[String] = []
	for bus: StringName in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			problems.append("Audio bus '%s' is missing from res://default_bus_layout.tres; its sounds play on Master" % bus)
	for id: StringName in SFX_IDS:
		if not ResourceLoader.exists(sfx_path % id):
			problems.append("Sound effect '%s' is missing: %s (run python3 tools/sfx.py)" % [id, sfx_path % id])
	for track: String in [TITLE_TRACK, RESULTS_TRACK]:
		if not ResourceLoader.exists(music_path % track):
			problems.append("Music track '%s' is missing: %s (run python3 tools/music.py)" % [track, music_path % track])
	for problem in problems:
		_game.report_error(problem)
	if problems.is_empty():
		print("[Audio] %d sound effects, the title and results loops and the %s and %s buses are in place (driver %s%s)" % [
			SFX_IDS.size(), MUSIC_BUS, SFX_BUS, AudioServer.get_driver_name(), ", silent: sounds are only recorded" if audio_silent() else ""])
	return problems.is_empty()


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
	var queued := LaterSound.new()
	queued.sound = id
	queued.at = _clock + delay
	_later_queue.append(queued)
	_later_queue.sort_custom(func(a: LaterSound, b: LaterSound) -> bool: return a.at < b.at)
	print("[Audio] SFX %s in %.2f s" % [id, delay])


## The sounds play_sfx_later queued and not started yet.
func sfx_waiting() -> int:
	return _later_queue.size()


func _log_sound(id: StringName, pitch := 1.0) -> void:
	sfx_log.append(id)
	sfx_pitches.append(pitch)
	while sfx_log.size() > SFX_LOG_SIZE:
		sfx_log.pop_front()
	while sfx_pitches.size() > sfx_log.size():
		sfx_pitches.pop_front()


## The stream of sound `id` (one of SFX_IDS), loaded once; a sound that is unknown,
## missing or unloadable is reported once (with its path) and is null.
func _sound(id: StringName) -> AudioStream:
	var path := sfx_path % id
	if _sounds.has(path):
		return _sounds[path]
	var stream: AudioStream = null
	if not id in SFX_IDS:
		_game.report_error("Unknown sound effect '%s' (not in AudioManager.SFX_IDS)" % id)
	elif not ResourceLoader.exists(path):
		_game.report_error("Sound effect '%s' is missing: %s (run python3 tools/sfx.py)" % [id, path])
	else:
		stream = load(path) as AudioStream
		if stream == null:
			_game.report_error("Sound effect '%s' at %s cannot be loaded as audio" % [id, path])
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


## With an audio device, `player` must be playing right after play(): `what` did not start
## otherwise (reported, never silent).
func _check_started(player: AudioStreamPlayer, what: String) -> void:
	if not player.playing:
		_game.report_error("%s did not start playing on %s (bus %s)" % [what, player.name, player.bus])


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
					_game.report_error("Sound on %s kept playing when the game paused (stream_paused did not hold it)" % _sfx_players[i].name)
		held_sounds = _held.size()
		print("[Audio] Paused: %d sounds held, music ducked by %.0f dB" % [held_sounds, -PAUSE_DUCK_DB])
	else:
		var paused_for := _clock - _held_at
		for player in _held:
			player.stream_paused = false
			_sfx_until[_sfx_players.find(player)] += paused_for
		for later in _later_queue:
			later.at += paused_for
		print("[Audio] Resumed after %.2f s: %d sounds continue, the music is back to full" % [paused_for, _held.size()])
		_held.clear()
		held_sounds = 0
	apply_volumes()


## The loop of flow state `to` entered with `args`: the title's for the title, the
## selects, the settings, the credits and the top scores, the chapter's (a campaign level) or the mode's in a run, the results'; "" for a
## run that cannot start (an unknown level or mode: the music stays as it is).
static func track_for(to: SceneFlow.Flow, args: Dictionary) -> String:
	match to:
		SceneFlow.Flow.PLAY:
			if args.has("level"):
				var level_id := str(args["level"])
				return Content.chapter(Content.level(level_id).chapter).music if Content.has_level(level_id) else ""
			var mode_id := str(args.get("mode", GameState.ENDLESS_MODE))
			for spec in Content.modes():
				if spec.id == mode_id:
					return spec.music
			return ""
		SceneFlow.Flow.RESULTS:
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
			_game.report_error("Music track '%s' is missing: %s (run python3 tools/music.py)" % [track, path])
		else:
			stream = load(path) as AudioStream
			if stream == null:
				_game.report_error("Music track '%s' at %s cannot be loaded as audio" % [track, path])
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
func set_music_volume(value: int, and_save := true) -> void:
	_game.save.music_volume = clampi(value, 0, SaveStore.VOLUME_MAX)
	print("[Audio] Music volume %d%s" % [_game.save.music_volume, "" if and_save else " (saved once the slider is released)"])
	apply_volumes()
	if and_save:
		_game.save.save_game()


## Sets the sound effects volume (0..VOLUME_MAX), applies it to the SFX bus and logs it;
## saves unless `save` is false (as set_music_volume).
func set_sfx_volume(value: int, and_save := true) -> void:
	_game.save.sfx_volume = clampi(value, 0, SaveStore.VOLUME_MAX)
	print("[Audio] SFX volume %d%s" % [_game.save.sfx_volume, "" if and_save else " (saved once the slider is released)"])
	apply_volumes()
	if and_save:
		_game.save.save_game()


## Mutes or unmutes the Music bus at once (keeping music_volume); logs and saves.
func set_music_muted(on: bool) -> void:
	_game.save.music_muted = on
	print("[Audio] Music %s" % ("muted" if on else "unmuted"))
	apply_volumes()
	_game.save.save_game()


## Mutes or unmutes the SFX bus at once (keeping sfx_volume); logs and saves.
func set_sfx_muted(on: bool) -> void:
	_game.save.sfx_muted = on
	print("[Audio] SFX %s" % ("muted" if on else "unmuted"))
	apply_volumes()
	_game.save.save_game()


## The bus volume in dB of setting `volume` (0..VOLUME_MAX): linear in loudness,
## SILENT_VOLUME_DB at 0; `duck_db` (0 or PAUSE_DUCK_DB) is added above 0.
static func bus_volume_db(volume: int, duck_db := 0.0) -> float:
	if volume <= 0:
		return SILENT_VOLUME_DB
	return linear_to_db(volume / float(SaveStore.VOLUME_MAX)) + duck_db


## Sets the Music and SFX buses from the settings: the volume (the music ducked while the
## audio is paused) and the mute (muted, or a volume of 0).
func apply_volumes() -> void:
	var settings: Array[Array] = [[MUSIC_BUS, _game.save.music_volume, _game.save.music_muted, PAUSE_DUCK_DB if audio_paused else 0.0], [SFX_BUS, _game.save.sfx_volume, _game.save.sfx_muted, 0.0]]
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
