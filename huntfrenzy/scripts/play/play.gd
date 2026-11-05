class_name Play
extends Node2D
## The play scene: one run of a mode (Endless or Time Attack: Game.flow.flow_args {"mode": id,
## "seed": run seed}) or of a campaign level ({"level": id}: the level's fixed seed).
## Waves follow one another (Wave.for_mode, Wave.campaign), each with a fresh shell pool
## (Ammo) after a TUNING.wave_lead lead-in. Every pressed touch on the ShotInput is a shot: it
## hits the frontmost flying bird whose hitbox holds the point (never through the grass, at or
## below Layout.GRASS_Y), else misses; with no shells left it is refused. A hit damages a bird
## short of its hp, else kills it (points x combo; a splitter launches its goslings); the decoy
## costs its penalty. Once the shells run out the wave's birds flee. An Endless run ends at
## escape_limit counted escapes, a level after its last wave, a timed mode (Time Attack) when
## run_clock (frozen while paused) reaches time_limit; a timed wave whose pool runs out is lost
## at once (_lose_wave). Each bird flies at the wave's speed x its own seeded factor.
## Play sequences the run: its start, the waves and their spawns, the clocks, the escapes and
## the run's end; it hands the rest to child nodes and helpers:
## - shots (ShotResolver): what a shot does (refused, hit, damage, kill, decoy, split), its
##   sounds and pop-ups;
## - hit_stop (HitStop): the world's stop after a kill;
## - crosshair (Crosshair): the mouse pointer;
## - rival (RivalController): the rival hunter's steals, aim cues, pose, heckles and light;
## - hud (HudController): the HUD bar's chips; Play pushes its values (update_hud);
## - pause (PauseMenu): the pause menu, the settings over it, Escape and the focus, page and
##   rotate-overlay pauses;
## - shaker (ScreenShake): the world's screen shake;
## - stage (StageFader): the backdrop, its cross-fades and the weather;
## - HitPopup: the score, damage, combo and penalty pop-ups;
## - RunRecord: the run's end: its record, save and results stats.
## Everything is logged with enough context (the run seed, wave times, shot positions) to
## replay the run.

const BIRD_SCENE := preload("res://scenes/bird.tscn")
## The run's feel tuning (timings, pop-ups, shake, the rival: Tuning). One shared object for
## the whole process (every reader and both test scripts): a test that changes a value puts
## it back, as _test_tuning_values (run first and last) checks. Play's own alias of Game.tuning
## (preload caches it: the same object); the controllers and every other script read Game.tuning.
const TUNING: Tuning = preload("res://data/tuning.tres")

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
## Seconds since the run started (game time: frozen while paused); the heckle cooldown and
## a timed mode's clock run on it.
var run_clock := 0.0
## Seconds since the current wave started, from -TUNING.wave_lead (its first spawn is at 0).
var wave_clock := 0.0
## Countdown ticks played this run (a timed run's last TUNING.countdown_seconds).
var countdown_ticks := 0

var _game: GameState
var _next_spawn := 0
## Birds spawned this run (a bird's number).
var _spawned := 0
## True once the run has ended or is being left: no more shots, pauses or waves.
var _over := false

@onready var _world: Node2D = $World
@onready var _birds: Node2D = $World/Birds
@onready var _shot_input: ShotInput = $ShotInput
@onready var shaker: ScreenShake = $Shaker
@onready var hud: HudController = $HudController
@onready var pause: PauseMenu = $Pause
@onready var rival: RivalController = $RivalController
@onready var stage: StageFader = $Stage
@onready var shots: ShotResolver = $Shots
@onready var hit_stop: HitStop = $HitStop
@onready var crosshair: Crosshair = $Crosshair


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen.screen_fit_changed.connect(_fit)
	_shot_input.shot.connect(shots.resolve)
	rival.stole.connect(_on_rival_stole)
	rival.steal_done.connect(_on_rival_steal_done)
	_fit()
	_start_run()
	pause.note_rotation_at_start()


## Window and app focus or visibility loss pauses the run (notifications arrive while
## the tree is paused too; open_pause ignores repeats).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			pause.open_pause("window lost focus")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			pause.open_pause("app lost focus")
		NOTIFICATION_APPLICATION_PAUSED:
			pause.open_pause("app paused or hidden")


## One frame of the run, in order: the shake, the hit stop, the clocks, the due spawns, the
## rival, then the wave's end. A step that ends the run stops the frame there.
func _process(frame_delta: float) -> void:
	if _over or wave == null:
		return
	shaker.update(frame_delta)
	var delta := hit_stop.run(frame_delta)
	if delta < 0.0 or _advance_clock(delta):
		return
	_spawn_due()
	rival.update_steals()
	if _over:
		return
	rival.update_pose()
	_check_wave_end()


## Advances run_clock and wave_clock by `delta`; a timed run shows its time, ticks its
## countdown and, on the frame its time runs out, sounds time_up and ends (returns true).
func _advance_clock(delta: float) -> bool:
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
		hud.show_time_left(time_left())
		_tick_countdown(left_before, time_left())
		if time_left() <= 0.0:
			_game.audio.play_sfx(AudioManager.SFX_TIME_UP)
			end_run()
			return true
	return false


## Spawns every bird of the wave whose time has come (the first plays wave_start).
func _spawn_due() -> void:
	while _next_spawn < wave.spawns.size() and wave.spawns[_next_spawn].time <= wave_clock:
		var spawn := wave.spawns[_next_spawn]
		_next_spawn += 1
		if _next_spawn == 1:
			_game.audio.play_sfx(AudioManager.SFX_WAVE_START)
		var bird := spawn_bird(spawn.bird_id, spawn.bird_seed)
		var fleeing := ", fleeing (no shells)" if ammo.is_empty() else ""
		print("[Play] Spawned %s #%d (wave %d, seed %d, speed x%.3f) at t %.2f%s" % [
			spawn.bird_id, bird.number, wave.index, spawn.bird_seed, bird.speed_scale, wave_clock, fleeing])


## Once every bird of the wave has spawned and none of them flies: a level's last wave ends
## the run, any other wave is cleared and the next starts.
func _check_wave_end() -> void:
	if _next_spawn == wave.spawns.size() and _wave_birds_flying().is_empty():
		if level != null and wave.index >= level.waves:
			end_run()
			return
		_game.audio.play_sfx(AudioManager.SFX_WAVE_CLEAR)
		rival.heckle("wave_end")
		_start_wave(wave.index + 1)


## Adds a bird of type `bird_id` flying with `bird_seed` at the current wave's speed;
## it flees at once when the shells are out. `from` and `heading` launch it from a point
## (goslings).
func spawn_bird(bird_id: String, bird_seed: int, from := Flight.NOT_LAUNCHED, heading := Vector2.ZERO) -> Bird:
	_spawned += 1
	var bird := BIRD_SCENE.instantiate() as Bird
	var speed_scale := wave.speed_scale * Flight.speed_factor(bird_seed, wave.speed_scale)
	bird.setup(Content.bird(bird_id), _spawned, bird_seed, speed_scale, Layout.FIELD, ammo.is_empty(), from, heading)
	bird.wave_index = wave.index
	bird.escaped.connect(_on_bird_escaped)
	bird.appeared.connect(_on_bird_appeared)
	# A gosling launched by the kill that started a hit stop waits it out with the others
	# (placed at its launch point first: Bird._ready sets its transform).
	if hit_stop.left() > 0.0 and from.is_finite():
		bird.hold(hit_stop.left())
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


## True once the run has ended or is being left (no more shots, pauses or waves).
func is_over() -> bool:
	return _over


## True in a run of a timed mode (Time Attack), which ends after time_limit seconds.
func is_timed() -> bool:
	return mode != null and mode.is_timed()


## The seconds a timed run has left (0 once its time is up); 0 in any other run.
func time_left() -> float:
	return maxf(mode.time_limit - run_clock, 0.0) if is_timed() else 0.0


## The backdrop shown, or fading in ("" before the run starts).
func backdrop_id() -> String:
	return stage.backdrop_id()


## True while a new backdrop fades in over the old one.
func is_backdrop_fading() -> bool:
	return stage.is_fading()


## The weather emitting ("" for none); tests turn it off with weather().set_weather("").
func weather() -> Weather:
	return stage.weather()


func _start_run() -> void:
	var args := _game.flow.flow_args
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
		stage.show_stage(chapter.backdrop, chapter.weather, 1)
	else:
		mode = Content.mode(str(args["mode"]))
		if mode == null or problems > 0 or not args.get("seed") is int:
			_cannot_start("Cannot start a run of mode '%s' (seed %s): %d content problem(s), see the log" % [args["mode"], args.get("seed"), problems])
			return
		run_seed = args["seed"]
		scoring = Scoring.new(mode.combo_cap)
	rival.rival_lines = Content.rival_lines()
	shots.start(run_seed)
	print("[Play] Run start: %s" % _run_start_note())
	if mode != null:
		hud.show_timer(mode.is_timed())
	_start_wave(1)
	crosshair.set_shown(true)


## The run start log's details: what runs, its seed, how it ends and the rules it plays by.
func _run_start_note() -> String:
	var lines := rival.rival_lines
	if level != null:
		return "level %s (%s %d of %d), seed %d (%d waves%s, no escape limit, combo cap %d, %d shells per hit, rival steals on, linger x%.2f, aim %.2f s, heckle cooldown %.2f s, backdrop %s, weather %s)" % [
			level.id, chapter.name, level.index, Content.LEVELS_PER_CHAPTER, run_seed, level.waves, ", the last a boss flock" if level.is_boss() else "",
			level.combo_cap, level.shells_per_hit, linger_scale, lines.aim_time, lines.cooldown, chapter.backdrop, chapter.weather]
	var ends := "time limit %.2f s, no escape limit" % mode.time_limit if mode.is_timed() else "escape limit %d" % mode.escape_limit
	return "mode %s, seed %d (%s, combo cap %d, %d shells per hit, rival steals %s, aim %.2f s, heckle cooldown %.2f s)" % [
		mode.id, run_seed, ends, mode.combo_cap, mode.shells_per_hit, "on" if mode.rival_steals else "off", lines.aim_time, lines.cooldown]


## A run that cannot start: `message` is reported, nothing runs, and the menu offers only
## the way back to the title.
func _cannot_start(message: String) -> void:
	_game.report_error(message)
	_over = true
	pause.show_cannot_start()


func _start_wave(index: int) -> void:
	wave = Wave.campaign(level, index) if level != null else Wave.for_mode(mode, index, run_seed)
	wave_clock = -TUNING.wave_lead
	_next_spawn = 0
	var ids := PackedStringArray()
	for spawn in wave.spawns:
		ids.append(spawn.bird_id)
	var of_level := " (wave %d of %d%s, level %s)" % [index, level.waves, ", boss flock" if wave.boss else "", level.id] if level != null else clock_note()
	print("[Play] Wave %d start: %d birds (%s), %d shells, speed x%.2f%s" % [index, wave.spawns.size(), ", ".join(ids), wave.shells, wave.speed_scale, of_level])
	set_shell_pool(wave.shells)
	if mode != null:
		var stage_now := mode.stage_for(index)
		stage.show_stage(stage_now.backdrop, stage_now.weather, index)


## Gives the wave a fresh pool of `count` shells and shows it on the HUD (hud.show_pool: one
## icon per shell up to HudController.SHELL_ICONS_MAX, else one icon and the count; public
## for tests).
func set_shell_pool(count: int) -> void:
	ammo = Ammo.new(count)
	hud.show_pool(count)
	update_hud()


## The shot that used the wave's last shell (ShotResolver.resolve): "out_of_shells" plays, the
## flying birds flee and the rest of the wave spawns fleeing; a timed mode's wave is lost at
## once unless that shot cleared it.
func shells_ran_out() -> void:
	_game.audio.play_sfx(AudioManager.SFX_OUT_OF_SHELLS)
	var fleeing := flying_birds()
	for bird in fleeing:
		bird.flee()
	var waiting := wave.spawns.size() - _next_spawn
	print("[Play] Out of shells: %d flying birds flee, %d still to spawn %s (wave %d%s)" % [fleeing.size(), waiting, "are skipped" if is_timed() else "will flee", wave.index, clock_note()])
	if is_timed() and not (waiting == 0 and _wave_birds_flying().is_empty()):
		_lose_wave(waiting)


## A timed mode's wave whose pool ran out is lost at once: its `waiting` birds still to
## spawn are skipped (each that counts as an escape is counted as escaped), and the next
## wave starts now. A wave cleared by its last shell ends as usual (_process).
func _lose_wave(waiting: int) -> void:
	var counted := 0
	for i in range(_next_spawn, wave.spawns.size()):
		if Content.bird(wave.spawns[i].bird_id).escape_counts:
			counted += 1
	escaped += counted
	_game.audio.play_sfx(AudioManager.SFX_WAVE_LOST)
	shaker.shake(ScreenShake.LOST_WAVE)
	print("[Play] Wave %d lost (no shells): %d birds still to spawn skipped, %d of them counted as escaped (%s escaped), %d flying flee%s" % [
		wave.index, waiting, counted, escapes(), _wave_birds_flying().size(), clock_note()])
	rival.heckle("wave_end")
	_start_wave(wave.index + 1)


## Whether the rival steals in this run: always in a campaign level, per mode in Endless.
func steals_on() -> bool:
	return level != null or mode.rival_steals


## The birds lost so far for the logs and the HUD: "E/limit" in Endless, "E" in a level
## and in a timed mode (no limit).
func escapes() -> String:
	return "%d/%d" % [escaped, mode.escape_limit] if mode != null and not mode.is_timed() else str(escaped)


## True once an Endless run has lost escape_limit birds; a level or a timed run never ends
## on escapes.
func escape_limit_reached() -> bool:
	return mode != null and not mode.is_timed() and escaped >= mode.escape_limit


## "(x, y)" of a shot or hit point, for the log lines.
static func at_note(point: Vector2) -> String:
	return "(%.1f, %.1f)" % [point.x, point.y]


## "<type> #n" of `bird`, for the log lines.
static func bird_name(bird: Bird) -> String:
	return "%s #%d" % [bird.spec.id, bird.number]


## "wave 3 at t 4.20" in the log lines of the run and its controllers.
func wave_note() -> String:
	return "wave %d at t %.2f" % [wave.index, wave_clock]


## ", 42.10 s left" in a timed run's log lines, "" in any other.
func clock_note() -> String:
	return ", %.2f s left" % time_left() if is_timed() else ""


## A bird's art first showed above the grass line: it gives its call (its spec's call at its
## call_pitch).
func _on_bird_appeared(bird: Bird) -> void:
	if _over:
		return
	_game.audio.play_sfx(StringName(bird.spec.call_sound), bird.spec.call_pitch)
	print("[Play] Call of %s as it appears above the grass: %s x%.2f (art top %.1f, age %.2f, %s%s)" % [bird_name(bird), bird.spec.call_sound, bird.spec.call_pitch, bird.art_top(), bird.age, wave_note(), clock_note()])


func _on_bird_escaped(bird: Bird) -> void:
	if _over:
		return
	if not bird.spec.escape_counts:
		print("[Play] Escaped %s (not counted, %s, %s)" % [bird_name(bird), escapes(), wave_note()])
		return
	escaped += 1
	shots.play_sound(AudioManager.SFX_ESCAPE)
	print("[Play] Escaped %s (%s, %s)" % [bird_name(bird), escapes(), wave_note()])
	update_hud()
	if escape_limit_reached():
		end_run()


## The rival stole `bird`: it counts as an escape (stolen birds can end the run: _on_rival_steal_done).
func _on_rival_stole(_bird: Bird) -> void:
	escaped += 1
	update_hud()


## The rival's steal is over: one that reached the escape limit ends the run.
func _on_rival_steal_done(_bird: Bird) -> void:
	if escape_limit_reached():
		end_run()


## Ends the run: records it (RunRecord) and opens the results.
func end_run() -> void:
	_stop()
	_game.flow.goto(SceneFlow.Flow.RESULTS, RunRecord.record(self, _game.save))


## Ends the run here: the world freezes, the menu closes and the tree runs again (the
## next scene must not start paused).
func _stop() -> void:
	_over = true
	crosshair.set_shown(false, "the run is over")
	shaker.stop()
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	pause.hide_menu()
	get_tree().paused = false
	_game.audio.sync_audio_pause()


## Pause menu Restart: a new run of the mode, or the same level.
func restart() -> void:
	_leave("Restart")
	if level != null:
		_game.flow.start_level(level.id)
	else:
		_game.flow.start_mode(mode.id)


## Pause menu Quit: back to the title.
func quit() -> void:
	_leave("Quit to title")
	_game.flow.goto(SceneFlow.Flow.TITLE)


func _leave(cause: String) -> void:
	_stop()
	if wave == null:
		print("[Play] Left (%s): the run never started" % cause)
		return
	print("[Play] Left the run (%s): %s, seed %d, wave %d, score %d, %d escaped%s; nothing recorded" % [cause, "level " + level.id if level != null else "mode " + mode.id, run_seed, wave.index, scoring.score, escaped, clock_note()])


## Plays one countdown tick for each of the last TUNING.countdown_seconds whole seconds the clock
## passed this frame (from `before` to `now` seconds left).
func _tick_countdown(before: float, now: float) -> void:
	for second in range(TUNING.countdown_seconds, 0, -1):
		if now <= second and before > second:
			countdown_ticks += 1
			_game.audio.play_sfx(AudioManager.SFX_COUNTDOWN_TICK)
			print("[Play] Countdown tick %d: %d s left (%.2f s, wave %d)" % [countdown_ticks, second, now, wave.index])


## Shows the run's values on the HUD.
func update_hud() -> void:
	hud.show_stats(scoring.score, "%d/%d" % [wave.index, level.waves] if level != null else "%d" % wave.index, ammo.shells, escapes())
	if is_timed():
		hud.show_time_left(time_left())


## Lays the scene out in the visible area: the base playfield centred horizontally, the
## backdrop (and one fading in) and the weather across the whole visible area, the grass
## down to the bottom, the HUD bar at the top of the safe area and the shot surface below it.
func _fit() -> void:
	var shown := _game.screen.visible_rect()
	var safe := _game.screen.safe_rect()
	shaker.set_origin(Vector2(shown.position.x + (shown.size.x - Layout.BASE_SIZE.x) / 2.0, shown.position.y))
	stage.fit(Rect2(shown.position - _world.position, shown.size).grow(ScreenShake.SHAKE_MARGIN))
	hud.fit(safe, Layout.HUD_BAR_HEIGHT)
	var top := safe.position.y + Layout.HUD_BAR_HEIGHT
	_shot_input.position = Vector2(shown.position.x, top)
	_shot_input.size = Vector2(shown.size.x, shown.end.y - top)
