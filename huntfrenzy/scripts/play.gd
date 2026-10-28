class_name Play
extends Node2D
## The play scene: one run of a mode (Endless or Time Attack: Game.flow_args {"mode": id,
## "seed": run seed}) or of a campaign level ({"level": id}: the level's fixed seed).
## Waves follow one another (Wave.for_mode, Wave.campaign): each starts WAVE_LEAD seconds before its
## first spawn with a fresh shell pool (Ammo). Every pressed touch on the ShotInput
## (below the HUD bar) is a shot: it uses a shell and hits the frontmost flying bird
## whose hitbox polygon holds the point, else it is a miss (combo reset); with no shells
## left it is refused (no hit test, no miss) with the empty cue on the HUD shells.
## A hit by bird type (BirdSpec): a hit short of the bird's hp (an armored bird's first)
## damages it (no points, combo kept, a "Clank!" pop-up); a kill scores points x combo;
## killing a splitter also launches split_count goslings from the hit point on diverging
## headings (the splitter falls; it can no longer escape); a hit on the decoy (penalty > 0)
## deducts its penalty (never below 0), resets the combo and shows a negative pop-up.
## When the shells run out, the wave's flying birds (and any still to spawn, goslings
## included) flee at once; the next wave starts when every bird of the wave has spawned
## and none is flying (a timed mode loses the wave at once instead: below). An escape counts toward escape_limit unless the bird's
## escape_counts is false (the decoy). An Endless run ends once escape_limit birds have
## escaped: the score is recorded (a new best is saved at once) and the results screen
## opens. A campaign level has no escape limit: it plays all its waves (the boss level's
## last one is the boss flock) and then ends on the results screen, the level's stars and
## best recorded and saved at once (Game.record_level). In a level the chapter's backdrop
## and weather show, and the rival waits linger_time x the chapter's rival_linger_scale. In
## a mode each wave shows its stage (ModeSpec.stage_for: Endless walks dawn, noon, sunset,
## night; Time Attack stays on noon); a new backdrop cross-fades in over BACKDROP_FADE_TIME
## during the wave's lead-in, without pausing or delaying anything. The weather (Weather)
## is drawn behind the birds and never touches their flight.
## A timed mode (Time Attack: ModeSpec.is_timed) has no escape limit (an escape only loses
## the bird's points) and ends after time_limit seconds of run_clock: game time from the
## run's start, frozen while the tree is paused (the pause menu, the rotate overlay), each
## wave's WAVE_LEAD lead-in included. The HUD shows the seconds left ("Time 42", rounded
## up); the frame that reaches time_limit stops the clock exactly there and ends the run
## (the score recorded, a new best saved at once, then the results screen). Its next wave
## starts as soon as the current one is cleared (every bird of it spawned and none of them
## flying) or lost: the moment its pool runs out, the wave is lost (logged) and the next
## starts at once (its WAVE_LEAD lead-in, a full pool of its own shells). The lost wave's
## birds still to spawn never spawn; each of them that counts as an escape (escape_counts)
## is counted as escaped, as it would have fled and escaped in Endless. The loss draws a
## wave_end heckle (cooldown permitting, as any wave's end) and the HUD shows the new
## wave's number and pool at once. The lost wave's birds already in the air flee as usual
## and are counted when they escape; until then they are still targets (a hit with the new
## wave's shells scores as any hit; a leftover splitter's goslings belong to the lost wave
## and flee at once), and they never hold up a later wave's end (a wave ends on its own
## birds: Bird.wave_index). Its rival never steals
## (rival_steals false), so his tally is not on the HUD; he still heckles.
## The rival hunter (Rival, data/rival_lines.json) stands in the grass band (at or below
## GRASS_Y, so he never covers the field; he and his speech bubble ignore touches, so a
## shot anywhere hits as before). In a mode with rival_steals, every frame Play asks
## Rival.steal_state about each flying bird: once one has flown its linger_time (never the
## decoy, never a fleeing bird) the aim cue starts (a reticle on the bird, the rival
## raising his gun) and runs aim_time; a kill during it saves the bird (a damaging hit
## does not), a bird that starts fleeing drops it, and once it has run the rival fires
## and never misses: the bird falls as stolen, its points (no combo) go to his tally, it
## counts as an escape (stolen birds can end the run), the player's combo is untouched,
## a stolen splitter launches no goslings, and he laughs ("rival_laugh",
## RIVAL_LAUGH_DELAY after his shot; his steal line shows without its blurt). He aims at
## one bird at a time (Rival.may_aim): when several have flown their linger_time, the cue
## goes to the one that has flown longest (the lower number on a tie: Rival.aim_target),
## and after a steal or a cancelled cue he waits RIVAL_AIM_GAP seconds of run_clock (a
## pause does not count) before the next cue. With rival_steals off he only heckles. He
## heckles (a Rival.pick_line line in the bubble for HECKLE_TIME) on a miss, a combo
## rising to COMBO_HECKLE_MIN or more and a wave's end, at most once per cooldown, and on
## every steal; the results screen shows one more line. His pose follows the run: he
## raises his gun while any cue runs, else he sulks for RIVAL_REACTION_TIME after each
## scored kill and brags for as long after a miss heckle that showed, else he stands idle.
## Cues, poses and the cooldown run on game time, so a pause freezes them.
## World holds the 960x540 base playfield, centred horizontally in the visible area;
## the sky and the grass stretch over the whole visible area. The HUD bar (a CanvasLayer)
## sits at the top of the safe area.
## Pause: the pause button, Escape (CancelKey), the window or app losing focus or
## visibility (Godot notifications, and Game.page_hidden for the web page), and the rotate
## overlay hiding after it showed during the run (or while the menu is open) open the
## pause menu with the tree paused; Resume (or Escape on the open menu) continues the run
## unchanged, Restart starts the run again (a new run of the mode, or the same level), Quit
## goes to the title. The grass hides
## what is behind it: a shot on it (at or below GRASS_Y) hits no bird. Everything is logged with enough context
## (the run seed, wave times, shot positions) to replay the run.
## Sound (Game.play_sfx): a shot with a shell plays "shot", then what it did ("hit", or for a
## kill of an armored bird "armored_kill", a splitter "split_pop", the run's golden bird
## "golden_chime"; "armored_clank" for a hit short of the bird's hp, "decoy_penalty" for the
## decoy, "combo_up" when the combo rises; nothing more for a miss; the shot, the plain hit
## and the escape each at a pitch varied by up to SOUND_PITCH_SPREAD, seeded by the run), and the shot that uses
## the last shell then "out_of_shells" (the pool is dry: the birds flee); a shot with no
## shells plays only "empty_click". A wave's first spawn plays "wave_start", a cleared wave
## "wave_clear", a lost Time Attack wave "wave_lost"; a counted escape "escape"; each bird,
## the first frame its art shows above the grass line (Bird.appeared, once per bird: today
## every rising bird on its spawn frame, a gosling at its launch; fleeing makes no sound), its call (its spec's call
## at its call_pitch); the rival's
## aim cue "rival_aim" and his steal "rival_steal"; each heckle shown his blurt
## (Game.play_heckle). A timed run ticks ("countdown_tick") once at each of the last
## COUNTDOWN_SECONDS whole seconds left and sounds "time_up" when the time runs out; the
## countdown runs on run_clock, so a pause stops it. The pause menu plays "pause" and
## "resume" and holds the run's sounds and ducks the music while open (Game.sync_audio_pause);
## its Music and SFX toggles mute their bus at once (saved). Its Settings button opens the
## settings screen over the paused run (open_settings: the tree stays paused, the sounds
## held and the music ducked); its Back (or Escape) closes it and focuses Settings again,
## and the menu's toggles follow whatever it changed.
## Juice: a kill stops the world for a moment (hit stop: HIT_STOP_TIME, HIT_STOP_HEAVY_TIME
## for an armored bird or the golden bird): the birds, the rival, run_clock, wave_clock and
## a timed run's clock all stand still and each loses exactly the stop's time, so the stop
## shifts every later event by the same amount and never changes what happens; the HUD,
## the pop-ups, the feathers and input keep running, and a kill during a stop starts no
## second one (a salvo stops once). Every kill (the decoy and the rival's steals too)
## bursts feathers in the bird's colours (Feathers). An armored or golden kill, a decoy hit,
## a steal and a lost wave shake the world (SHAKES: amplitude and time per event, decaying
## to exactly no offset; the HUD stays put). Pop-ups bounce in (score and damage), grow with
## the multiplier (combo) and shake (penalty), then rise and fade. With reduce motion on,
## there is no shake and the pop-ups only rise and fade (the combo ones still larger); the
## hit stop and the feathers stay.
## Each bird flies at the wave's speed scale x its own seeded factor (Flight.speed_factor,
## also for goslings), so a flock never moves in lockstep.
## Cursor: while the run is live (started, not paused, not over) the mouse pointer is the
## crosshair (CROSSHAIR, its hotspot at its centre); pausing, the run's end (the results)
## and leaving Play put the default arrow back (logged "[Play] Cursor: ...").

const BIRD_SCENE := preload("res://scenes/bird.tscn")
const BACKDROP_SCENE := preload("res://scenes/backdrop.tscn")
const SETTINGS_SCENE := preload("res://scenes/settings.tscn")
## Seconds a kill stops the world (hit stop), and for an armored or golden kill.
const HIT_STOP_TIME := 0.05
const HIT_STOP_HEAVY_TIME := 0.09
## Screen shake per event: [amplitude in base units, seconds]. The world's offset decays as
## (1 - t / time)^2 and is exactly zero once the time is over.
const SHAKES: Dictionary[String, Array] = {
	"armored kill": [6.0, 0.25], "golden kill": [8.0, 0.3], "decoy hit": [10.0, 0.3], "steal": [7.0, 0.3], "lost wave": [12.0, 0.4],
}
## How fast the shake swings (per second).
const SHAKE_HZ := 18.0
## The backdrop and weather reach this far past the visible area, so a shake never bares an edge.
const SHAKE_MARGIN := 12.0
## Pop-ups: a bounce in to POPUP_BOUNCE_SCALE (over POPUP_BOUNCE_TIME, then back to their
## size), a combo pop-up's size grows by POPUP_COMBO_GROWTH per multiplier step (at most
## POPUP_COMBO_SCALE_MAX), a penalty pop-up shakes POPUP_SHAKE either way POPUP_SHAKES times.
const POPUP_BOUNCE_SCALE := 1.35
const POPUP_BOUNCE_TIME := 0.18
const POPUP_COMBO_GROWTH := 0.12
const POPUP_COMBO_SCALE_MAX := 1.6
const POPUP_SHAKE := 6.0
const POPUP_SHAKES := 4
const POPUP_SHAKE_TIME := 0.32
const SHELL_TEXTURE := preload("res://art/shell.svg")
const RIVAL_IDLE := preload("res://art/rival_idle.svg")
const RIVAL_AIM := preload("res://art/rival_aim.svg")
const RIVAL_SULK := preload("res://art/rival_sulk.svg")
const RIVAL_BRAG := preload("res://art/rival_brag.svg")
## The mouse pointer while the run is live (64x64 at most; its hotspot is its centre).
const CROSSHAIR := preload("res://art/crosshair.svg")
## The 960x540 base the playfield is laid out in.
const BASE_SIZE := Vector2(960, 540)
const HUD_BAR_HEIGHT := 56.0
## The grass line: the backdrop's grass is solid from here down (_fit places it so), birds rise from
## behind it, and a shot at or below it hits no bird (bird_at).
const GRASS_Y := 440.0
## How far the grass tile's blade tips reach above the grass line (the tile's solid part starts
## this far below its top).
const GRASS_TIP := 24.0
## Where birds fly (World coordinates): below the HUD bar, above the grass line.
const FIELD := Rect2(0, HUD_BAR_HEIGHT, 960, GRASS_Y - HUD_BAR_HEIGHT)
## Seconds between a wave's start and its first spawn.
const WAVE_LEAD := 1.0
## Seconds a new backdrop takes to fade in over the old one (within a wave's lead-in).
const BACKDROP_FADE_TIME := 0.8
const POPUP_COLOR := Color(1.0, 0.93, 0.6)
const PENALTY_COLOR := Color(1.0, 0.45, 0.4)
## The pop-up of a hit that only damages a bird.
const DAMAGE_TEXT := "Clank!"
const POPUP_RISE := 48.0
const POPUP_TIME := 0.8
const EMPTY_CUE_TIME := 0.6
const SHELL_ICON_SIZE := Vector2(12, 28)
## The HUD shows a pool of up to this many shells as one icon per shell (hidden as used);
## a bigger pool (Endless reaches 72) shows one icon and the shells left ("x36"), so the
## bar never overflows whatever the pool.
const SHELL_ICONS_MAX := 10
const EMPTY_TINT := Color(1.0, 0.451, 0.4)
## A kill that raises the combo to this multiplier or more draws a heckle.
const COMBO_HECKLE_MIN := 3
## Seconds a heckle stays in the rival's bubble.
const HECKLE_TIME := 2.5
## Seconds (run_clock) the rival sulks after a scored hit, or brags after a miss heckle.
const RIVAL_REACTION_TIME := 1.2
## Seconds of run_clock after a steal or a cancelled cue before the rival aims again.
const RIVAL_AIM_GAP := 1.5
## Seconds after the rival's shot (rival_steal) that his laugh (rival_laugh) starts.
const RIVAL_LAUGH_DELAY := 0.3
## The run's most frequent sounds (VARIED_SOUNDS) play each time at a pitch up to this much
## (a fraction) off 1, drawn from an RNG seeded by the run seed (the same run sounds the same).
const SOUND_PITCH_SPREAD := 0.04
const VARIED_SOUNDS: Array[StringName] = [&"shot", &"hit", &"escape"]
## A timed run ticks at each of its last this many whole seconds.
const COUNTDOWN_SECONDS := 10
## The pause menu's mute toggles: the bus and whether it is on.
const MUSIC_TOGGLE_TEXT := "Music: %s"
const SFX_TOGGLE_TEXT := "SFX: %s"

## The mode (Endless, Time Attack), or null in a campaign level.
var mode: ModeSpec
## The campaign level and its chapter, or null in Endless.
var level: LevelSpec
var chapter: ChapterSpec
## The rival waits linger_time x this before aiming (the chapter's rival_linger_scale; 1 in Endless).
var linger_scale := 1.0
var run_seed := 0
var wave: Wave.Plan
var ammo: Ammo
var scoring: Scoring
## Birds lost: counted escapes plus stolen birds (escape_limit of them end the run).
var escaped := 0
## Birds the rival stole, and the points they took to his tally.
var stolen := 0
var rival_score := 0
var rival_lines: RivalLines
## Heckles shown this run (the next line's pick counter).
var heckles := 0
## Seconds since the run started (game time: frozen while paused); the heckle cooldown and
## a timed mode's clock run on it.
var run_clock := 0.0
## Shots refused because the pool was empty.
var refused := 0
## Seconds since the current wave started, from -WAVE_LEAD (its first spawn is at 0).
var wave_clock := 0.0
## Every cause the pause menu opened for, oldest first (tests read it).
var pause_log: Array[String] = []
## Countdown ticks played this run (a timed run's last COUNTDOWN_SECONDS).
var countdown_ticks := 0
## True while the mouse pointer is the crosshair; every change, oldest first, as
## "crosshair" or "arrow (<why>)"; and every call made to Input.set_custom_mouse_cursor
## as [texture (null: the arrow), shape, hotspot] (tests read them).
var crosshair_shown := false
var cursor_log: Array[String] = []
var cursor_calls: Array[Array] = []

var _game: GameState
var _next_spawn := 0
## Birds spawned this run (a bird's number).
var _spawned := 0
## True once the run has ended or is being left: no more shots, pauses or waves.
var _over := false
## True while the rotate overlay that showed during the run (or before it, during the
## transition in) has not hidden yet.
var _rotated := false
var _empty_tween: Tween
## Draws the pitch of each VARIED_SOUNDS sound (seeded in _start_run).
var _pitch_rng := RandomNumberGenerator.new()
var _bubble_tween: Tween
## The backdrop fading in over _backdrop (null when none is), and its tween.
var _next_backdrop: Backdrop
var _backdrop_tween: Tween
## The run_clock of the last heckle shown (-INF before any).
var _last_heckle := -INF
## The run_clock the last aim cue ended at, by a steal or a cancel (-INF before any).
var _last_cue_end := -INF
## The rival's reaction (RIVAL_SULK or RIVAL_BRAG, null for none) and the run_clock it
## lasts until; aiming takes precedence over it.
var _reaction: Texture2D
var _reaction_until := -INF
## The settings opened over the pause menu (null when closed).
var _settings: Settings
## Seconds of hit stop still to run (0: none), and the stops so far (tests read them).
var hit_stops := 0
var _hit_stop_left := 0.0
## The shake running: its cause, amplitude, time and how far into it (none: time 0).
var _shake_cause := ""
var _shake_amplitude := 0.0
var _shake_time := 0.0
var _shake_age := 0.0
## Where _fit puts the World; the shake offsets it from here.
var _world_origin := Vector2.ZERO

@onready var _world: Node2D = $World
@onready var _backdrop: Backdrop = $World/Backdrop
@onready var _weather: Weather = $World/Weather
@onready var _birds: Node2D = $World/Birds
@onready var _feathers: Feathers = $World/Feathers
@onready var _popups: Node2D = $World/Popups
@onready var _rival: TextureRect = $World/Rival
@onready var _bubble: Label = $World/Bubble
@onready var _shot_input: ShotInput = $ShotInput
@onready var _cancel_key: CancelKey = $CancelKey
@onready var _bar: Control = $Hud/Bar
@onready var _score_label: Label = $Hud/Bar/Stats/Score
@onready var _wave_label: Label = $Hud/Bar/Stats/Wave
@onready var _shells: HBoxContainer = $Hud/Bar/Stats/Shells
@onready var _shell_count: Label = $Hud/Bar/Stats/Shells/Count
@onready var _empty_label: Label = $Hud/Bar/Stats/Empty
@onready var _combo_label: Label = $Hud/Bar/Stats/Combo
@onready var _time_label: Label = $Hud/Bar/Stats/Time
@onready var _rival_label: Label = $Hud/Bar/Stats/Rival
@onready var _escaped_label: Label = $Hud/Bar/Stats/Escaped
@onready var _pause_button: Button = $Hud/Bar/PauseButton
@onready var _pause_menu: Control = $PauseLayer/PauseMenu
@onready var _resume_button: Button = $PauseLayer/PauseMenu/Panel/ResumeButton
@onready var _restart_button: Button = $PauseLayer/PauseMenu/Panel/RestartButton
@onready var _quit_button: Button = $PauseLayer/PauseMenu/Panel/QuitButton
@onready var _music_toggle: Button = $PauseLayer/PauseMenu/Panel/MusicToggle
@onready var _sfx_toggle: Button = $PauseLayer/PauseMenu/Panel/SfxToggle
@onready var _settings_button: Button = $PauseLayer/PauseMenu/Panel/SettingsButton
@onready var _pause_layer: CanvasLayer = $PauseLayer
@onready var _pause_panel: Control = $PauseLayer/PauseMenu/Panel


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_game.rotate_overlay_changed.connect(_on_rotate_overlay_changed)
	_game.page_hidden.connect(open_pause.bind("page hidden"))
	_shot_input.shot.connect(_on_shot)
	_cancel_key.triggered.connect(_on_cancel)
	_pause_button.pressed.connect(open_pause.bind("pause button"))
	_resume_button.pressed.connect(resume)
	_restart_button.pressed.connect(_restart)
	_quit_button.pressed.connect(_quit)
	_settings_button.pressed.connect(open_settings)
	_music_toggle.toggled.connect(_on_music_toggled)
	_sfx_toggle.toggled.connect(_on_sfx_toggled)
	_game.audio_settings_changed.connect(_show_audio_settings)
	_show_audio_settings()
	_fit()
	_start_run()
	# The overlay may have shown before this scene existed (during the fade into the run);
	# _show_crosshair already kept the arrow then.
	_rotated = not _over and _game.is_rotate_overlay_shown()


## Window and app focus or visibility loss pauses the run (notifications arrive while
## the tree is paused too; open_pause ignores repeats); leaving the tree puts the arrow back.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			open_pause("window lost focus")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			open_pause("app lost focus")
		NOTIFICATION_APPLICATION_PAUSED:
			open_pause("app paused or hidden")
		NOTIFICATION_EXIT_TREE:
			# Whatever ends the scene, the arrow comes back.
			_show_crosshair(false, "left the play scene")


func _process(frame_delta: float) -> void:
	if _over or wave == null:
		return
	_update_shake(frame_delta)
	var delta := frame_delta
	if _hit_stop_left > 0.0:
		_hit_stop_left -= frame_delta
		if _hit_stop_left >= 0.0:
			return
		# The stop ended inside this frame: only the rest of the frame runs (Bird.hold does the same).
		delta = -_hit_stop_left
		_hit_stop_left = 0.0
	var left_before := time_left()
	var step := delta
	var next := run_clock + delta
	if is_timed() and (next >= mode.time_limit or is_equal_approx(next, mode.time_limit)):
		# The clock stops exactly at the time limit, on the first frame that reaches it
		# (frame times summed in floats may land a hair short of it): the run ends here.
		step = mode.time_limit - run_clock
		run_clock = mode.time_limit
	else:
		run_clock = next
	wave_clock += step
	if is_timed():
		_time_label.text = "Time %d" % ceili(time_left())
		_tick_countdown(left_before, time_left())
		if time_left() <= 0.0:
			_game.play_sfx(&"time_up")
			_end_run()
			return
	while _next_spawn < wave.spawns.size() and wave.spawns[_next_spawn].time <= wave_clock:
		var spawn := wave.spawns[_next_spawn]
		_next_spawn += 1
		if _next_spawn == 1:
			_game.play_sfx(&"wave_start")
		var bird := spawn_bird(spawn.bird_id, spawn.bird_seed)
		print("[Play] Spawned %s #%d (wave %d, seed %d, speed x%.3f) at t %.2f%s" % [spawn.bird_id, bird.number, wave.index, spawn.bird_seed, bird.speed_scale, wave_clock, ", fleeing (no shells)" if ammo.is_empty() else ""])
	_update_steals()
	if _over:
		return
	_update_rival_pose()
	if _next_spawn == wave.spawns.size() and _wave_birds_flying().is_empty():
		if level != null and wave.index >= level.waves:
			_end_run()
			return
		_game.play_sfx(&"wave_clear")
		_heckle("wave_end")
		_start_wave(wave.index + 1)


## Adds a bird of type `bird_id` flying with `bird_seed` at the current wave's speed;
## it flees at once when the shells are out. `from` and `heading` launch it from a point
## (goslings).
func spawn_bird(bird_id: String, bird_seed: int, from := Flight.NOT_LAUNCHED, heading := Vector2.ZERO) -> Bird:
	_spawned += 1
	var bird := BIRD_SCENE.instantiate() as Bird
	var speed_scale := wave.speed_scale * Flight.speed_factor(bird_seed, wave.speed_scale)
	bird.setup(Content.bird(bird_id), _spawned, bird_seed, speed_scale, FIELD, ammo.is_empty(), from, heading)
	bird.wave_index = wave.index
	bird.escaped.connect(_on_bird_escaped)
	bird.appeared.connect(_on_bird_appeared)
	# A gosling launched by the kill that started a hit stop waits it out with the others
	# (placed at its launch point first: Bird._ready sets its transform).
	if _hit_stop_left > 0.0 and from.is_finite():
		bird.hold(_hit_stop_left)
	_birds.add_child(bird)
	return bird


## The birds still flying, oldest first.
func flying_birds() -> Array[Bird]:
	var result: Array[Bird] = []
	for child in _birds.get_children():
		var bird := child as Bird
		if bird != null and bird.is_flying():
			result.append(bird)
	return result


## The current wave's birds still flying (a lost Time Attack wave's fleeing birds are
## not; outside Time Attack no other wave's bird is ever in the air).
func _wave_birds_flying() -> Array[Bird]:
	var result: Array[Bird] = []
	result.assign(flying_birds().filter(func(bird: Bird) -> bool: return bird.wave_index == wave.index))
	return result


## The frontmost (latest spawned, drawn on top) flying bird whose hitbox holds `point`
## (World coordinates), or null. A point on the grass (at or below GRASS_Y) hits nothing:
## the grass is drawn over the birds behind it.
func bird_at(point: Vector2) -> Bird:
	if point.y >= GRASS_Y:
		return null
	var flying := flying_birds()
	for i in range(flying.size() - 1, -1, -1):
		if flying[i].contains(point):
			return flying[i]
	return null


## True in a run of a timed mode (Time Attack), which ends after time_limit seconds.
func is_timed() -> bool:
	return mode != null and mode.is_timed()


## The seconds a timed run has left (0 once its time is up); 0 in any other run.
func time_left() -> float:
	return maxf(mode.time_limit - run_clock, 0.0) if is_timed() else 0.0


## Opens the pause menu (focused on Resume) with the tree paused, for `cause`. While it
## is open the tree is kept paused (the rotate overlay may have unpaused it). Ignored
## once the run is over; during the transition into the run it opens once that is done.
func open_pause(cause: String) -> void:
	if _over:
		return
	if _game.is_transitioning():
		print("[Play] Pause (%s) waits for the transition to finish" % cause)
		_game.transition_finished.connect(open_pause.bind(cause).unbind(1), CONNECT_ONE_SHOT)
		return
	get_tree().paused = true
	# The run's sounds are held before the menu's own sound starts.
	_game.sync_audio_pause()
	if _pause_menu.visible:
		return
	_pause_menu.show()
	_show_crosshair(false, "paused")
	_game.play_sfx(&"pause")
	_resume_button.grab_focus(true)
	pause_log.append(cause)
	print("[Play] Paused (%s): wave %d at t %.2f, score %d%s" % [cause, wave.index, wave_clock, scoring.score, _clock_note()])


## Closes the pause menu and continues the run where it stopped (`cause`: "Resume" for
## the button, "Escape"). Ignored once the run is over (the menu of a run that could not
## start stays up).
func resume(cause := "Resume") -> void:
	if not _pause_menu.visible or _over:
		return
	close_settings()
	_pause_menu.hide()
	# On the menu voice, while the audio is still paused, so it never takes a held sound's voice.
	_game.play_sfx(&"resume")
	get_tree().paused = false
	_game.sync_audio_pause()
	_show_crosshair(true)
	print("[Play] Resumed (%s): wave %d at t %.2f, score %d%s" % [cause, wave.index, wave_clock, scoring.score, _clock_note()])


func is_paused() -> bool:
	return _pause_menu.visible


## Opens the settings over the open pause menu (the run stays paused); ignored when the
## menu is closed or the settings already show. Logged.
func open_settings() -> void:
	if not _pause_menu.visible or _settings != null or _over:
		return
	_settings = SETTINGS_SCENE.instantiate() as Settings
	_settings.overlay = true
	_settings.closed.connect(close_settings)
	# The menu's dim stays (it is the pause itself); its panel hides under the settings.
	_pause_panel.hide()
	_pause_layer.add_child(_settings)
	print("[Play] Settings opened over the paused run (wave %d at t %.2f%s)" % [wave.index, wave_clock, _clock_note()])


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


func is_empty_cue_shown() -> bool:
	return _empty_label.visible


## True while the rival raises his gun (an aim cue is on a flying bird).
func is_rival_aiming() -> bool:
	return _rival.texture == RIVAL_AIM


## The rival's pose: "aim", "sulk" (after a scored hit), "brag" (after a miss heckle) or "idle".
func rival_pose() -> String:
	match _rival.texture:
		RIVAL_AIM:
			return "aim"
		RIVAL_SULK:
			return "sulk"
		RIVAL_BRAG:
			return "brag"
	return "idle"


## The backdrop shown, or fading in ("" before the run starts).
func backdrop_id() -> String:
	return _next_backdrop.id if _next_backdrop != null else _backdrop.id


## True while a new backdrop fades in over the old one.
func is_backdrop_fading() -> bool:
	return _next_backdrop != null


## The weather emitting ("" for none); tests turn it off with weather().set_weather("").
func weather() -> Weather:
	return _weather


## The heckle in the rival's bubble, or "" when it is hidden.
func heckle_shown() -> String:
	return _bubble.text if _bubble.visible else ""


func _start_run() -> void:
	var args := _game.flow_args
	if not args.has("mode") and not args.has("level"):
		# Opened without a goto (the project check, the editor's Run Current Scene).
		args = {"mode": GameState.ENDLESS_MODE, "seed": randi()}
		print("[Play] Opened without run args; starting %s with a fresh seed" % args["mode"])
	var problems := Content.errors().size()
	if args.has("level"):
		level = Content.level(str(args["level"])) if problems == 0 and Content.has_level(str(args["level"])) else null
		if level == null:
			_cannot_start("Cannot start level '%s': %s" % [args["level"], "%d content problem(s), see the log" % problems if problems > 0 else "no such level in levels.json"])
			return
		chapter = Content.chapter(level.chapter)
		linger_scale = chapter.rival_linger_scale
		run_seed = level.level_seed
		scoring = Scoring.new(level.combo_cap)
		_show_stage(chapter.backdrop, chapter.weather, 1)
	else:
		mode = Content.mode(str(args["mode"]))
		if mode == null or problems > 0 or not args.get("seed") is int:
			_cannot_start("Cannot start a run of mode '%s' (seed %s): %d content problem(s), see the log" % [args["mode"], args.get("seed"), problems])
			return
		run_seed = args["seed"]
		scoring = Scoring.new(mode.combo_cap)
	rival_lines = Content.rival_lines()
	_pitch_rng.seed = hash([run_seed, "sound pitch"])
	if level != null:
		print("[Play] Run start: level %s (%s %d of %d), seed %d (%d waves%s, no escape limit, combo cap %d, %d shells per hit, rival steals on, linger x%.2f, aim %.2f s, heckle cooldown %.2f s, backdrop %s, weather %s)" % [
			level.id, chapter.name, level.index, Content.LEVELS_PER_CHAPTER, run_seed, level.waves, ", the last a boss flock" if level.is_boss() else "", level.combo_cap, level.shells_per_hit,
			linger_scale, rival_lines.aim_time, rival_lines.cooldown, chapter.backdrop, chapter.weather])
	else:
		var ends := "time limit %.2f s, no escape limit" % mode.time_limit if mode.is_timed() else "escape limit %d" % mode.escape_limit
		print("[Play] Run start: mode %s, seed %d (%s, combo cap %d, %d shells per hit, rival steals %s, aim %.2f s, heckle cooldown %.2f s)" % [
			mode.id, run_seed, ends, mode.combo_cap, mode.shells_per_hit, "on" if mode.rival_steals else "off", rival_lines.aim_time, rival_lines.cooldown])
		_time_label.visible = mode.is_timed()
		_rival_label.visible = mode.rival_steals
	_start_wave(1)
	_show_crosshair(true)


## A run that cannot start: `message` is reported, nothing runs, and the menu offers only
## the way back to the title.
func _cannot_start(message: String) -> void:
	_game.report_error(message)
	_over = true
	_resume_button.disabled = true
	_restart_button.disabled = true
	_pause_menu.show()
	_quit_button.grab_focus(true)


func _start_wave(index: int) -> void:
	wave = Wave.campaign(level, index) if level != null else Wave.for_mode(mode, index, run_seed)
	wave_clock = -WAVE_LEAD
	_next_spawn = 0
	var ids := PackedStringArray()
	for spawn in wave.spawns:
		ids.append(spawn.bird_id)
	var of_level := " (wave %d of %d%s, level %s)" % [index, level.waves, ", boss flock" if wave.boss else "", level.id] if level != null else _clock_note()
	print("[Play] Wave %d start: %d birds (%s), %d shells, speed x%.2f%s" % [index, wave.spawns.size(), ", ".join(ids), wave.shells, wave.speed_scale, of_level])
	set_shell_pool(wave.shells)
	if mode != null:
		var stage := mode.stage_for(index)
		_show_stage(stage.backdrop, stage.weather, index)


## Shows backdrop `to_backdrop` with weather `to_weather` from wave `wave_index` on: at once
## for the run's first wave, else (a new backdrop) cross-fading in over BACKDROP_FADE_TIME
## while the wave runs on. The weather switches at once (the old one's particles drift
## out). Nothing changes when both are already showing. Logged.
func _show_stage(to_backdrop: String, to_weather: String, wave_index: int) -> void:
	var from := backdrop_id()
	if to_backdrop == from and to_weather == _weather.id:
		return
	if _weather.id != to_weather:
		_weather.set_weather(to_weather)
	if to_backdrop == from:
		print("[Play] Weather %s on backdrop %s from wave %d" % [to_weather, to_backdrop, wave_index])
		return
	if from == "":
		if not _backdrop.show_backdrop(to_backdrop):
			print("[Play] Backdrop %s could not be shown (reported); weather %s from wave %d" % [to_backdrop, to_weather, wave_index])
			return
		_fit()
		print("[Play] Backdrop %s, weather %s from wave %d" % [to_backdrop, to_weather, wave_index])
		return
	if _next_backdrop != null:
		_finish_backdrop_fade()
	var next := BACKDROP_SCENE.instantiate() as Backdrop
	_world.add_child(next)
	_world.move_child(next, _backdrop.get_index() + 1)
	if not next.show_backdrop(to_backdrop):
		next.free()
		return
	_next_backdrop = next
	next.modulate.a = 0.0
	_fit()
	_backdrop_tween = next.create_tween()
	_backdrop_tween.tween_property(next, "modulate:a", 1.0, BACKDROP_FADE_TIME)
	_backdrop_tween.tween_callback(_finish_backdrop_fade)
	print("[Play] Backdrop %s -> %s, weather %s, cross-fading over %.2f s from wave %d" % [from, to_backdrop, to_weather, BACKDROP_FADE_TIME, wave_index])


## The faded-in backdrop replaces the old one.
func _finish_backdrop_fade() -> void:
	if _backdrop_tween != null:
		_backdrop_tween.kill()
		_backdrop_tween = null
	_next_backdrop.modulate.a = 1.0
	_backdrop.queue_free()
	_backdrop = _next_backdrop
	_next_backdrop = null


## Gives the wave a fresh pool of `count` shells and shows it on the HUD: one icon per
## shell up to SHELL_ICONS_MAX, else one icon and the count (public for tests).
func set_shell_pool(count: int) -> void:
	ammo = Ammo.new(count)
	for icon in _shells.get_children():
		if icon != _shell_count:
			icon.free()
	for i in count if count <= SHELL_ICONS_MAX else 1:
		var icon := TextureRect.new()
		icon.texture = SHELL_TEXTURE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = SHELL_ICON_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shells.add_child(icon)
		_shells.move_child(icon, _shell_count.get_index())
	_shell_count.visible = count > SHELL_ICONS_MAX
	_update_hud()


func _on_shot(at: Vector2) -> void:
	if _over or get_tree().paused or _game.is_transitioning():
		return
	var point := _world.to_local(at)
	if not ammo.use():
		refused += 1
		_game.play_sfx(&"empty_click")
		print("[Play] Shot refused at (%.1f, %.1f): no shells left (wave %d at t %.2f, %d refused)" % [at.x, at.y, wave.index, wave_clock, refused])
		_show_empty_cue()
		return
	_play_sound(&"shot")
	var target := bird_at(point)
	if target != null and target.spec.penalty > 0:
		_hit_decoy(target, point, at)
	elif target != null:
		_hit_bird(target, point, at)
	else:
		scoring.miss()
		print("[Play] Miss at (%.1f, %.1f): combo reset, score %d (wave %d at t %.2f, %d shells left)" % [at.x, at.y, scoring.score, wave.index, wave_clock, ammo.shells])
		if _heckle("miss"):
			_react(RIVAL_BRAG, "brags after the miss")
	if ammo.is_empty():
		_game.play_sfx(&"out_of_shells")
		var fleeing := flying_birds()
		for bird in fleeing:
			bird.flee()
		var waiting := wave.spawns.size() - _next_spawn
		print("[Play] Out of shells: %d flying birds flee, %d still to spawn %s (wave %d%s)" % [fleeing.size(), waiting, "are skipped" if is_timed() else "will flee", wave.index, _clock_note()])
		if is_timed() and not (waiting == 0 and _wave_birds_flying().is_empty()):
			_lose_wave(waiting)
	_update_hud()


## A timed mode's wave whose pool ran out is lost at once: its `waiting` birds still to
## spawn are skipped (each that counts as an escape is counted as escaped), and the next
## wave starts now. A wave cleared by its last shell ends as usual (_process).
func _lose_wave(waiting: int) -> void:
	var counted := 0
	for i in range(_next_spawn, wave.spawns.size()):
		if Content.bird(wave.spawns[i].bird_id).escape_counts:
			counted += 1
	escaped += counted
	_game.play_sfx(&"wave_lost")
	shake("lost wave")
	print("[Play] Wave %d lost (no shells): %d birds still to spawn skipped, %d of them counted as escaped (%s escaped), %d flying flee%s" % [
		wave.index, waiting, counted, _escapes(), _wave_birds_flying().size(), _clock_note()])
	_heckle("wave_end")
	_start_wave(wave.index + 1)


## A hit on a bird other than the decoy: damage short of its hp, else a kill that scores
## (and splits a splitter).
func _hit_bird(target: Bird, point: Vector2, at: Vector2) -> void:
	var multiplier := scoring.multiplier
	if not target.hit():
		scoring.damage()
		_game.play_sfx(&"armored_clank")
		_popup(point, DAMAGE_TEXT, POPUP_COLOR, "damage")
		print("[Play] Hit %s #%d (hit %d/%d) at (%.1f, %.1f): no points, combo x%d kept, score %d (wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, multiplier, scoring.score, wave.index, wave_clock, ammo.shells])
		return
	var awarded := scoring.hit(target.spec.points)
	_play_sound(_kill_sound(target.spec))
	if scoring.multiplier > multiplier:
		_game.play_sfx(&"combo_up")
	_start_hit_stop(target)
	_feathers.burst(point, target.spec.sprite)
	if target.spec.hp > 1:
		shake("armored kill")
	elif _is_golden(target.spec):
		shake("golden kill")
	_popup(point, "+%d" % awarded if multiplier == 1 else "+%d x%d" % [awarded, multiplier], POPUP_COLOR, "score" if multiplier == 1 else "combo", multiplier)
	print("[Play] Hit %s #%d (hit %d/%d, killed) at (%.1f, %.1f): %d points x%d = %d, score %d (wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, target.spec.points, multiplier, awarded, scoring.score, wave.index, wave_clock, ammo.shells])
	_react(RIVAL_SULK, "sulks at the %d points on %s #%d" % [awarded, target.spec.id, target.number])
	if target.is_cued():
		_cancel_cue(target, "shot by the player")
	if scoring.multiplier >= COMBO_HECKLE_MIN and scoring.multiplier > multiplier:
		_heckle("combo")
	if target.spec.split_count > 0:
		_split(target, point)


## Plays sound `id`, a VARIED_SOUNDS one at its next seeded pitch within SOUND_PITCH_SPREAD.
func _play_sound(id: StringName) -> void:
	var pitch := _pitch_rng.randf_range(1.0 - SOUND_PITCH_SPREAD, 1.0 + SOUND_PITCH_SPREAD) if id in VARIED_SOUNDS else 1.0
	_game.play_sfx(id, pitch)


## The sound of a kill: an armored bird's (hp above 1) last hit, a splitter bursting, the
## run's golden bird, or a plain hit.
func _kill_sound(spec: BirdSpec) -> StringName:
	if spec.hp > 1:
		return &"armored_kill"
	if spec.split_count > 0:
		return &"split_pop"
	if _is_golden(spec):
		return &"golden_chime"
	return &"hit"


## True for the run's golden bird (its level's or mode's golden_bird).
func _is_golden(spec: BirdSpec) -> bool:
	return spec.id == (level.golden_bird if level != null else mode.golden_bird)


## Stops the world for HIT_STOP_TIME (HIT_STOP_HEAVY_TIME for an armored or the golden
## bird) after `target`'s kill: every bird holds still that long (Bird.hold) and _process
## stops the clocks; while a stop runs, another kill starts none. Logged.
func _start_hit_stop(target: Bird) -> void:
	var heavy := target.spec.hp > 1 or _is_golden(target.spec)
	var time := HIT_STOP_HEAVY_TIME if heavy else HIT_STOP_TIME
	if _hit_stop_left > 0.0:
		print("[Play] Hit stop for %s #%d skipped: one is running (%.3f s left)" % [target.spec.id, target.number, _hit_stop_left])
		return
	_hit_stop_left = time
	hit_stops += 1
	for child in _birds.get_children():
		(child as Bird).hold(time)
	print("[Play] Hit stop %.2f s on the kill of %s #%d (wave %d at t %.2f%s)" % [time, target.spec.id, target.number, wave.index, wave_clock, _clock_note()])


## Seconds of hit stop still to run (0 when none runs).
func hit_stop_left() -> float:
	return _hit_stop_left


## Shakes the world for `cause` (a SHAKES key): its amplitude and time, from now. A weaker
## shake never cuts a stronger one short. With reduce motion on nothing shakes. Logged.
func shake(cause: String) -> void:
	if _game.reduce_motion:
		print("[Play] Shake (%s) skipped: reduce motion" % cause)
		return
	var amplitude: float = SHAKES[cause][0]
	var time: float = SHAKES[cause][1]
	if shake_strength() > amplitude:
		print("[Play] Shake (%s) skipped: a stronger one (%s) is running" % [cause, _shake_cause])
		return
	_shake_cause = cause
	_shake_amplitude = amplitude
	_shake_time = time
	_shake_age = 0.0
	print("[Play] Shake (%s): %.0f units over %.2f s" % [cause, amplitude, time])


## The shake's current amplitude (its envelope; 0 when none runs).
func shake_strength() -> float:
	if _shake_time <= 0.0:
		return 0.0
	return _shake_amplitude * pow(1.0 - _shake_age / _shake_time, 2.0)


## The world's shake offset now (zero when none runs).
func shake_offset() -> Vector2:
	return _world.position - _world_origin


## Moves the world by the shake's offset (bounded by its envelope), or back exactly to its
## place once it is over.
func _update_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		return
	_shake_age += delta
	if _shake_age >= _shake_time:
		_end_shake()
		return
	var swing := TAU * SHAKE_HZ * _shake_age
	_world.position = _world_origin + Vector2(sin(swing), sin(swing * 1.37 + 1.1)).limit_length(1.0) * shake_strength()


func _end_shake() -> void:
	_shake_time = 0.0
	_shake_age = 0.0
	_shake_cause = ""
	_world.position = _world_origin


## Launches the killed splitter's goslings from `point` (World coordinates) on diverging
## headings; each has its own seed derived from the splitter's.
func _split(parent: Bird, point: Vector2) -> void:
	var children := PackedStringArray()
	var headings := Flight.split_headings(parent.spec.split_count)
	for i in headings.size():
		var child_seed := hash([parent.bird_seed, i])
		var child := spawn_bird(parent.spec.splits_into, child_seed, point, headings[i])
		# A lost wave's splitter (Time Attack) launches goslings of that wave, fleeing.
		if parent.wave_index != wave.index:
			child.wave_index = parent.wave_index
			child.flee()
		children.append("#%d seed %d heading (%.2f, %.2f)" % [child.number, child_seed, headings[i].x, headings[i].y])
	print("[Play] Split %s #%d at (%.1f, %.1f) into %d %s: %s (wave %d at t %.2f)%s" % [parent.spec.id, parent.number, point.x, point.y, headings.size(), parent.spec.splits_into, ", ".join(children), wave.index, wave_clock, ", fleeing (no shells)" if ammo.is_empty() else ""])


## A hit on the decoy: its penalty comes off the score (never below 0) and the combo resets.
func _hit_decoy(target: Bird, point: Vector2, at: Vector2) -> void:
	target.hit()
	var deducted := scoring.penalty(target.spec.penalty)
	_game.play_sfx(&"decoy_penalty")
	_feathers.burst(point, target.spec.sprite)
	shake("decoy hit")
	_popup(point, "-%d" % deducted, PENALTY_COLOR, "penalty")
	print("[Play] Hit %s #%d (hit %d/%d, killed) at (%.1f, %.1f): penalty %d, -%d, combo reset, score %d (%d pigeons hit, wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, target.spec.penalty, deducted, scoring.score, scoring.penalties, wave.index, wave_clock, ammo.shells])


## Asks Rival about every flying bird: keep a running aim cue, drop it (the bird started
## fleeing, or steals were turned off), or steal its bird once the cue has run. With no
## cue running and the aim gap over (Rival.may_aim), a new cue starts on the eligible bird
## (one that has flown its linger_time with at least aim_time left before it flees)
## Rival.aim_target picks: the longest flown.
func _update_steals() -> void:
	var cue_running := false
	var eligible: Array[Bird] = []
	var ages := PackedFloat64Array()
	var numbers := PackedInt32Array()
	for bird in flying_birds():
		match Rival.steal_state(bird.age, bird.spec.linger_time * linger_scale, rival_lines.aim_time, bird.cue_age, bird.spec.penalty > 0, minf(bird.spec.flee_time, bird.flee_at), steals_on()):
			Rival.Steal.NONE:
				if bird.is_cued():
					_cancel_cue(bird, "fled" if bird.is_fleeing() else "rival steals off")
			Rival.Steal.AIMING:
				if bird.is_cued():
					cue_running = true
				else:
					eligible.append(bird)
					ages.append(bird.age)
					numbers.append(bird.number)
			Rival.Steal.FIRE:
				_steal(bird)
				if _over:
					return
	if eligible.is_empty() or not Rival.may_aim(cue_running, run_clock, _last_cue_end, RIVAL_AIM_GAP):
		return
	_start_cue(eligible[Rival.aim_target(ages, numbers)], eligible.size())


## Starts the rival's aim cue on `bird`, picked among `eligible` birds.
func _start_cue(bird: Bird, eligible: int) -> void:
	bird.set_cue(true)
	_update_rival_pose()
	_game.play_sfx(&"rival_aim")
	var since := "no cue before" if _last_cue_end == -INF else "%.2f s since the last cue ended" % (run_clock - _last_cue_end)
	print("[Play] Aim cue on %s #%d: age %.2f (linger %.2f s), the rival fires in %.2f s (the longest flown of %d eligible; %s, aim gap %.2f s) (wave %d at t %.2f, rival score %d, %d stolen)" % [
		bird.spec.id, bird.number, bird.age, bird.spec.linger_time * linger_scale, rival_lines.aim_time, eligible, since, RIVAL_AIM_GAP, wave.index, wave_clock, rival_score, stolen])


func _cancel_cue(bird: Bird, cause: String) -> void:
	var held := bird.age - bird.cue_age
	bird.set_cue(false)
	_last_cue_end = run_clock
	_update_rival_pose()
	print("[Play] Aim cue on %s #%d cancelled (%s) after %.2f s (wave %d at t %.2f, rival score %d, %d stolen); no new cue for the %.2f s aim gap" % [bird.spec.id, bird.number, cause, held, wave.index, wave_clock, rival_score, stolen, RIVAL_AIM_GAP])


## The rival fires: the bird falls as stolen, its points go to his tally (no combo) and it
## counts as an escape; the player's combo is left alone.
func _steal(bird: Bird) -> void:
	var held := bird.age - bird.cue_age
	bird.steal()
	_last_cue_end = run_clock
	_update_rival_pose()
	_game.play_sfx(&"rival_steal")
	_game.play_sfx_later(&"rival_laugh", RIVAL_LAUGH_DELAY)
	_feathers.burst(bird.position, bird.spec.sprite)
	shake("steal")
	stolen += 1
	rival_score += bird.spec.points
	escaped += 1
	print("[Play] Stolen %s #%d by the rival after a %.2f s cue: %d points to the rival, rival score %d, %d stolen, %s escaped, combo x%d kept (wave %d at t %.2f); he laughs in %.2f s, no new cue for the %.2f s aim gap" % [
		bird.spec.id, bird.number, held, bird.spec.points, rival_score, stolen, _escapes(), scoring.multiplier, wave.index, wave_clock, RIVAL_LAUGH_DELAY, RIVAL_AIM_GAP])
	# He laughs instead of blurting his steal line.
	_heckle(Rival.STEAL, false)
	_update_hud()
	if _escape_limit_reached():
		_end_run()


## Whether the rival steals in this run: always in a campaign level, per mode in Endless.
func steals_on() -> bool:
	return level != null or mode.rival_steals


## The birds lost so far for the logs and the HUD: "E/limit" in Endless, "E" in a level
## and in a timed mode (no limit).
func _escapes() -> String:
	return "%d/%d" % [escaped, mode.escape_limit] if mode != null and not mode.is_timed() else str(escaped)


## True once an Endless run has lost escape_limit birds; a level or a timed run never ends
## on escapes.
func _escape_limit_reached() -> bool:
	return mode != null and not mode.is_timed() and escaped >= mode.escape_limit


## ", 42.10 s left" in a timed run's log lines, "" in any other.
func _clock_note() -> String:
	return ", %.2f s left" % time_left() if is_timed() else ""


## The rival raises his gun while any flying bird has an aim cue; otherwise he holds his
## reaction (sulk or brag) until it runs out, then stands idle.
func _update_rival_pose() -> void:
	var aiming := flying_birds().any(func(bird: Bird) -> bool: return bird.is_cued())
	if aiming:
		_rival.texture = RIVAL_AIM
	elif _reaction != null and run_clock < _reaction_until:
		_rival.texture = _reaction
	else:
		_reaction = null
		_rival.texture = RIVAL_IDLE


## The rival reacts with `pose` (RIVAL_SULK or RIVAL_BRAG) for RIVAL_REACTION_TIME of game
## time (logged as "[Play] Rival <what>").
func _react(pose: Texture2D, what: String) -> void:
	_reaction = pose
	_reaction_until = run_clock + RIVAL_REACTION_TIME
	_update_rival_pose()
	print("[Play] Rival %s (wave %d at t %.2f)" % [what, wave.index, wave_clock])


## Makes the mouse pointer the crosshair (`on`, the run is live) or the default arrow
## again (`why`: paused, the run is over, the rotate overlay, left the scene); while the
## rotate overlay is up it is always the arrow (the run is paused under it, whichever came
## first). A change is logged and kept in cursor_log, a repeat does nothing.
func _show_crosshair(on: bool, why := "") -> void:
	if on and _game.is_rotate_overlay_shown():
		on = false
		why = "rotate overlay"
	if on == crosshair_shown:
		return
	crosshair_shown = on
	if on:
		_set_cursor(CROSSHAIR, CROSSHAIR.get_size() / 2.0)
	else:
		_set_cursor(null, Vector2.ZERO)
	var shown := "crosshair" if on else "arrow (%s)" % why
	cursor_log.append(shown)
	print("[Play] Cursor: %s" % shown)


## The one place the pointer is set: Input.set_custom_mouse_cursor(texture, CURSOR_ARROW,
## hotspot) (null: the default arrow), recorded in cursor_calls exactly as passed.
func _set_cursor(texture: Texture2D, hotspot: Vector2) -> void:
	Input.set_custom_mouse_cursor(texture, Input.CURSOR_ARROW, hotspot)
	cursor_calls.append([texture, Input.CURSOR_ARROW, hotspot])


## Shows a `category` line (Rival.pick_line) in the rival's bubble for HECKLE_TIME, unless
## the cooldown since the last heckle has not passed yet (Rival.may_heckle; steal lines
## always show), with his gibberish blurt unless `blurt` is false (a steal: he laughs).
## Both are logged. Returns whether the line showed.
func _heckle(category: String, blurt := true) -> bool:
	if not Rival.may_heckle(category, run_clock, _last_heckle, rival_lines.cooldown):
		print("[Play] Heckle (%s) skipped: cooldown, %.2f of %.2f s since the last (wave %d at t %.2f, rival score %d, %d stolen)" % [
			category, run_clock - _last_heckle, rival_lines.cooldown, wave.index, wave_clock, rival_score, stolen])
		return false
	var line := Rival.pick_line(rival_lines.lines[category], run_seed, heckles)
	heckles += 1
	_last_heckle = run_clock
	_bubble.text = line
	_bubble.show()
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(HECKLE_TIME)
	_bubble_tween.tween_callback(_bubble.hide)
	if blurt:
		_game.play_heckle(category, line)
	print("[Play] Heckle (%s) #%d: \"%s\" (wave %d at t %.2f, rival score %d, %d stolen)%s" % [category, heckles, line, wave.index, wave_clock, rival_score, stolen, "" if blurt else ", no blurt"])
	return true


## A bird's art first showed above the grass line: it gives its call (its spec's call at its
## call_pitch).
func _on_bird_appeared(bird: Bird) -> void:
	if _over:
		return
	_game.play_sfx(StringName(bird.spec.call_sound), bird.spec.call_pitch)
	print("[Play] Call of %s #%d as it appears above the grass: %s x%.2f (art top %.1f, age %.2f, wave %d at t %.2f%s)" % [bird.spec.id, bird.number, bird.spec.call_sound, bird.spec.call_pitch, bird.art_top(), bird.age, wave.index, wave_clock, _clock_note()])


func _on_bird_escaped(bird: Bird) -> void:
	if _over:
		return
	if not bird.spec.escape_counts:
		print("[Play] Escaped %s #%d (not counted, %s, wave %d at t %.2f)" % [bird.spec.id, bird.number, _escapes(), wave.index, wave_clock])
		return
	escaped += 1
	_play_sound(&"escape")
	print("[Play] Escaped %s #%d (%s, wave %d at t %.2f)" % [bird.spec.id, bird.number, _escapes(), wave.index, wave_clock])
	_update_hud()
	if _escape_limit_reached():
		_end_run()


func _end_run() -> void:
	_stop()
	var rival_line := Rival.pick_line(rival_lines.lines["results"], run_seed, heckles)
	heckles += 1
	print("[Play] Heckle (results) #%d: \"%s\" (wave %d at t %.2f, rival score %d, %d stolen)" % [heckles, rival_line, wave.index, wave_clock, rival_score, stolen])
	var stats := {
		"seed": run_seed, "score": scoring.score, "shots": scoring.shots(), "hits": scoring.hits, "kills": scoring.kills,
		"pigeons": scoring.penalties, "escaped": escaped, "stolen": stolen, "rival_score": rival_score, "rival_line": rival_line,
		"rival_steals": steals_on(),
	}
	var shots := "score %d, %d shots (%d hits, %d misses, %d pigeons hit), %d birds killed, %d refused, %d escaped (%d stolen), rival score %d" % [
		scoring.score, scoring.shots(), scoring.hits, scoring.misses, scoring.penalties, scoring.kills, refused, escaped, stolen, rival_score]
	if level != null:
		var new_best := _game.record_level(level, scoring.score)
		var record: Campaign.Record = _game.progress[level.id]
		var next := Campaign.next_level(level)
		var open_next := next.id if next != null and Campaign.is_unlocked(next, _game.progress) else ""
		stats.merge({"level": level.id, "stars": Campaign.stars(level, scoring.score), "best": record.score, "best_stars": record.stars,
			"new_best": new_best, "save_error": _game.save_error, "next_level": open_next})
		print("[Play] Run end: level %s, seed %d, wave %d of %d, %s, %d stars, level best %d (%d stars)%s%s" % [
			level.id, run_seed, wave.index, level.waves, shots, stats["stars"], record.score, record.stars, " (new best)" if new_best else "",
			", not saved: %s" % _game.save_error if _game.save_error != "" else ""])
	else:
		var new_best := _game.record_best(mode, scoring.score)
		var save_error := _game.save_error if new_best else ""
		stats.merge({"mode": mode.id, "best": _game.best(mode.id), "new_best": new_best, "save_error": save_error})
		var best_note := ""
		if new_best:
			best_note = " (new best, not saved: %s)" % save_error if save_error != "" else " (new best)"
		var time_used := ", time used %.2f of %.2f s" % [run_clock, mode.time_limit] if mode.is_timed() else ""
		print("[Play] Run end: mode %s, seed %d, wave %d%s, %s, best %d%s" % [mode.id, run_seed, wave.index, time_used, shots, _game.best(mode.id), best_note])
	_game.goto(GameState.Flow.RESULTS, stats)


## Ends the run here: the world freezes, the menu closes and the tree runs again (the
## next scene must not start paused).
func _stop() -> void:
	_over = true
	_show_crosshair(false, "the run is over")
	_end_shake()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_pause_menu.hide()
	get_tree().paused = false
	_game.sync_audio_pause()


func _restart() -> void:
	_leave("Restart")
	if level != null:
		_game.start_level(level.id)
	else:
		_game.start_mode(mode.id)


func _quit() -> void:
	_leave("Quit to title")
	_game.goto(GameState.Flow.TITLE)


func _leave(cause: String) -> void:
	_stop()
	if wave == null:
		print("[Play] Left (%s): the run never started" % cause)
		return
	print("[Play] Left the run (%s): %s, seed %d, wave %d, score %d, %d escaped%s; nothing recorded" % [cause, "level " + level.id if level != null else "mode " + mode.id, run_seed, wave.index, scoring.score, escaped, _clock_note()])


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
		_rotated = not _over
		_show_crosshair(false, "rotate overlay")
	elif _rotated or is_paused():
		_rotated = false
		open_pause("rotate overlay")


## Plays one countdown tick for each of the last COUNTDOWN_SECONDS whole seconds the clock
## passed this frame (from `before` to `now` seconds left).
func _tick_countdown(before: float, now: float) -> void:
	for second in range(COUNTDOWN_SECONDS, 0, -1):
		if now <= second and before > second:
			countdown_ticks += 1
			_game.play_sfx(&"countdown_tick")
			print("[Play] Countdown tick %d: %d s left (%.2f s, wave %d)" % [countdown_ticks, second, now, wave.index])


## The pause menu's Music toggle: on plays the music, off mutes the Music bus (saved).
func _on_music_toggled(on: bool) -> void:
	if on == not _game.music_muted:
		return
	print("[Play] Music toggle pressed: music %s" % ("on" if on else "off"))
	_game.set_music_muted(not on)


## The pause menu's SFX toggle: on plays the sound effects, off mutes the SFX bus (saved).
func _on_sfx_toggled(on: bool) -> void:
	if on == not _game.sfx_muted:
		return
	print("[Play] SFX toggle pressed: sound effects %s" % ("on" if on else "off"))
	_game.set_sfx_muted(not on)


## Shows the mutes on the pause menu's toggles (pressed = on), whoever changed them.
func _show_audio_settings() -> void:
	_music_toggle.set_pressed_no_signal(not _game.music_muted)
	_music_toggle.text = MUSIC_TOGGLE_TEXT % ("on" if not _game.music_muted else "off")
	_sfx_toggle.set_pressed_no_signal(not _game.sfx_muted)
	_sfx_toggle.text = SFX_TOGGLE_TEXT % ("on" if not _game.sfx_muted else "off")


func _show_empty_cue() -> void:
	_empty_label.show()
	_shells.modulate = EMPTY_TINT
	if _empty_tween != null:
		_empty_tween.kill()
	_empty_tween = create_tween()
	_empty_tween.tween_interval(EMPTY_CUE_TIME)
	_empty_tween.tween_callback(_hide_empty_cue)


func _hide_empty_cue() -> void:
	_empty_label.hide()
	_shells.modulate = Color.WHITE


## A pop-up of `text` in `color` centred on `point` (World coordinates), kept inside the
## visible area at its largest: `kind` "score" and "damage" bounce in, "combo" bounces in
## larger by the `multiplier`, "penalty" shakes; all rise POPUP_RISE and fade over
## POPUP_TIME. With reduce motion they only rise and fade (a combo one keeps its size).
## Each label carries its kind and its resting scale as metadata (tests read them).
func _popup(point: Vector2, text: String, color: Color, kind: String, multiplier := 1) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeadingLabel"
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_constant_override(&"outline_size", 6)
	_popups.add_child(label)
	var size := label.get_combined_minimum_size()
	var rest := minf(1.0 + POPUP_COMBO_GROWTH * (multiplier - 1), POPUP_COMBO_SCALE_MAX) if kind == "combo" else 1.0
	var still := _game.reduce_motion
	var largest := rest * (POPUP_BOUNCE_SCALE if not still and kind != "penalty" else 1.0)
	# Centred on the hit, moved in so its largest size (and the shake) stays on screen,
	# the rise included.
	var shown := Rect2(_game.visible_rect().position - _world.position, _game.visible_rect().size)
	var half := size * largest / 2.0 + Vector2(POPUP_SHAKE, 0.0)
	var centre := Vector2(clampf(point.x, shown.position.x + half.x, shown.end.x - half.x), clampf(point.y, shown.position.y + half.y + POPUP_RISE, shown.end.y - half.y))
	label.pivot_offset = size / 2.0
	label.position = centre - size / 2.0
	label.scale = Vector2.ONE * rest
	label.set_meta(&"kind", kind)
	label.set_meta(&"rest_scale", rest)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_TIME)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_TIME)
	if not still:
		if kind == "penalty":
			var wiggle := label.create_tween()
			var x := label.position.x
			for i in POPUP_SHAKES:
				wiggle.tween_property(label, "position:x", x + (POPUP_SHAKE if i % 2 == 0 else -POPUP_SHAKE), POPUP_SHAKE_TIME / (POPUP_SHAKES + 1))
			wiggle.tween_property(label, "position:x", x, POPUP_SHAKE_TIME / (POPUP_SHAKES + 1))
		else:
			label.scale = Vector2.ONE * rest * 0.5
			var bounce := label.create_tween()
			bounce.tween_property(label, "scale", Vector2.ONE * rest * POPUP_BOUNCE_SCALE, POPUP_BOUNCE_TIME / 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			bounce.tween_property(label, "scale", Vector2.ONE * rest, POPUP_BOUNCE_TIME / 2.0).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_callback(label.queue_free)


func _update_hud() -> void:
	_score_label.text = "Score %d" % scoring.score
	_wave_label.text = "Wave %d/%d" % [wave.index, level.waves] if level != null else "Wave %d" % wave.index
	if _shell_count.visible:
		_shell_count.text = "x%d" % ammo.shells
	else:
		for icon in _shells.get_children():
			if icon != _shell_count:
				(icon as CanvasItem).visible = icon.get_index() < ammo.shells
	_combo_label.text = "x%d" % scoring.multiplier
	_rival_label.text = "Rival %d" % rival_score
	if is_timed():
		_time_label.text = "Time %d" % ceili(time_left())
	_escaped_label.text = "Escaped " + _escapes()


## Lays the scene out in the visible area: the base playfield centred horizontally, the
## backdrop (and one fading in) and the weather across the whole visible area, the grass
## down to the bottom, the HUD bar at the top of the safe area and the shot surface below it.
func _fit() -> void:
	var shown := _game.visible_rect()
	var safe := _game.safe_rect()
	_world_origin = Vector2(shown.position.x + (shown.size.x - BASE_SIZE.x) / 2.0, shown.position.y)
	_world.position = _world_origin
	var local := Rect2(shown.position - _world.position, shown.size).grow(SHAKE_MARGIN)
	for backdrop: Backdrop in [_backdrop, _next_backdrop]:
		if backdrop != null:
			backdrop.fit(local, GRASS_Y - GRASS_TIP)
	_weather.fit(local)
	_bar.position = safe.position
	_bar.size = Vector2(safe.size.x, HUD_BAR_HEIGHT)
	var top := safe.position.y + HUD_BAR_HEIGHT
	_shot_input.position = Vector2(shown.position.x, top)
	_shot_input.size = Vector2(shown.size.x, shown.end.y - top)
