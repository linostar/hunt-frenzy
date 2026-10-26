class_name Play
extends Node2D
## The play scene: one run of a mode (only Endless so far), from Game.flow_args
## ({"mode": id, "seed": run seed}).
## Waves follow one another (Wave.endless): each starts WAVE_LEAD seconds before its
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
## and none is flying. An escape counts toward escape_limit unless the bird's
## escape_counts is false (the decoy). The run ends once escape_limit birds have escaped:
## the score is recorded (a new best is saved at once) and the results screen opens.
## The rival hunter (Rival, data/rival_lines.json) stands in the grass band (at or below
## GRASS_Y, so he never covers the field; he and his speech bubble ignore touches, so a
## shot anywhere hits as before). In a mode with rival_steals, every frame Play asks
## Rival.steal_state about each flying bird: once one has flown its linger_time (never the
## decoy, never a fleeing bird) the aim cue starts (a reticle on the bird, the rival
## raising his gun) and runs aim_time; a kill during it saves the bird (a damaging hit
## does not), a bird that starts fleeing drops it, and once it has run the rival fires
## and never misses: the bird falls as stolen, its points (no combo) go to his tally, it
## counts as an escape (stolen birds can end the run), the player's combo is untouched
## and a stolen splitter launches no goslings. With rival_steals off he only heckles. He
## heckles (a Rival.pick_line line in the bubble for HECKLE_TIME) on a miss, a combo
## rising to COMBO_HECKLE_MIN or more and a wave's end, at most once per cooldown, and on
## every steal; the results screen shows one more line. Cues and the cooldown run on game
## time, so a pause freezes them.
## World holds the 960x540 base playfield, centred horizontally in the visible area;
## the sky and the grass stretch over the whole visible area. The HUD bar (a CanvasLayer)
## sits at the top of the safe area.
## Pause: the pause button, Escape (CancelKey), the window or app losing focus or
## visibility (Godot notifications, and Game.page_hidden for the web page), and the rotate
## overlay hiding after it showed during the run (or while the menu is open) open the
## pause menu with the tree paused; Resume (or Escape on the open menu) continues the run
## unchanged, Restart starts a new Endless run, Quit goes to the title. The grass hides
## what is behind it: a shot on it (at or below GRASS_Y) hits no bird. Everything is logged with enough context
## (the run seed, wave times, shot positions) to replay the run.

const BIRD_SCENE := preload("res://scenes/bird.tscn")
const SHELL_TEXTURE := preload("res://art/shell.svg")
const RIVAL_IDLE := preload("res://art/rival_idle.svg")
const RIVAL_AIM := preload("res://art/rival_aim.svg")
## The 960x540 base the playfield is laid out in.
const BASE_SIZE := Vector2(960, 540)
const HUD_BAR_HEIGHT := 56.0
## The grass line: grass.svg is solid from here down (_fit places it so), birds rise from
## behind it, and a shot at or below it hits no bird (bird_at).
const GRASS_Y := 440.0
## How far grass.svg's blade tips reach above the grass line (the tile's solid part starts
## this far below its top).
const GRASS_TIP := 24.0
## Where birds fly (World coordinates): below the HUD bar, above the grass line.
const FIELD := Rect2(0, HUD_BAR_HEIGHT, 960, GRASS_Y - HUD_BAR_HEIGHT)
## Seconds between a wave's start and its first spawn.
const WAVE_LEAD := 1.0
const POPUP_COLOR := Color(1.0, 0.93, 0.6)
const PENALTY_COLOR := Color(1.0, 0.45, 0.4)
## The pop-up of a hit that only damages a bird.
const DAMAGE_TEXT := "Clank!"
const POPUP_RISE := 48.0
const POPUP_TIME := 0.8
const EMPTY_CUE_TIME := 0.6
const SHELL_ICON_SIZE := Vector2(12, 28)
## The HUD shows a pool of up to this many shells as one icon per shell (hidden as used);
## a bigger pool (Endless reaches 54) shows one icon and the shells left ("x36"), so the
## bar never overflows whatever the pool.
const SHELL_ICONS_MAX := 10
const EMPTY_TINT := Color(1.0, 0.35, 0.3)
## A kill that raises the combo to this multiplier or more draws a heckle.
const COMBO_HECKLE_MIN := 3
## Seconds a heckle stays in the rival's bubble.
const HECKLE_TIME := 2.5

var mode: ModeSpec
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
## Seconds since the run started (game time: frozen while paused); the heckle cooldown runs on it.
var run_clock := 0.0
## Shots refused because the pool was empty.
var refused := 0
## Seconds since the current wave started, from -WAVE_LEAD (its first spawn is at 0).
var wave_clock := 0.0
## Every cause the pause menu opened for, oldest first (tests read it).
var pause_log: Array[String] = []

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
var _bubble_tween: Tween
## The run_clock of the last heckle shown (-INF before any).
var _last_heckle := -INF

@onready var _world: Node2D = $World
@onready var _sky: TextureRect = $World/Sky
@onready var _birds: Node2D = $World/Birds
@onready var _grass: TextureRect = $World/Grass
@onready var _ground: ColorRect = $World/Ground
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
@onready var _rival_label: Label = $Hud/Bar/Stats/Rival
@onready var _escaped_label: Label = $Hud/Bar/Stats/Escaped
@onready var _pause_button: Button = $Hud/Bar/PauseButton
@onready var _pause_menu: Control = $PauseLayer/PauseMenu
@onready var _resume_button: Button = $PauseLayer/PauseMenu/Panel/ResumeButton
@onready var _restart_button: Button = $PauseLayer/PauseMenu/Panel/RestartButton
@onready var _quit_button: Button = $PauseLayer/PauseMenu/Panel/QuitButton


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
	_fit()
	_start_run()
	# The overlay may have shown before this scene existed (during the fade into the run).
	_rotated = not _over and _game.is_rotate_overlay_shown()


## Window and app focus or visibility loss pauses the run (notifications arrive while
## the tree is paused too; open_pause ignores repeats).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			open_pause("window lost focus")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			open_pause("app lost focus")
		NOTIFICATION_APPLICATION_PAUSED:
			open_pause("app paused or hidden")


func _process(delta: float) -> void:
	if _over or wave == null:
		return
	run_clock += delta
	wave_clock += delta
	while _next_spawn < wave.spawns.size() and wave.spawns[_next_spawn].time <= wave_clock:
		var spawn := wave.spawns[_next_spawn]
		_next_spawn += 1
		var bird := spawn_bird(spawn.bird_id, spawn.bird_seed)
		print("[Play] Spawned %s #%d (wave %d, seed %d) at t %.2f%s" % [spawn.bird_id, bird.number, wave.index, spawn.bird_seed, wave_clock, ", fleeing (no shells)" if ammo.is_empty() else ""])
	_update_steals()
	if _over:
		return
	if _next_spawn == wave.spawns.size() and flying_birds().is_empty():
		_heckle("wave_end")
		_start_wave(wave.index + 1)


## Adds a bird of type `bird_id` flying with `bird_seed` at the current wave's speed;
## it flees at once when the shells are out. `from` and `heading` launch it from a point
## (goslings).
func spawn_bird(bird_id: String, bird_seed: int, from := Flight.NOT_LAUNCHED, heading := Vector2.ZERO) -> Bird:
	_spawned += 1
	var bird := BIRD_SCENE.instantiate() as Bird
	bird.setup(Content.bird(bird_id), _spawned, bird_seed, wave.speed_scale, FIELD, ammo.is_empty(), from, heading)
	bird.escaped.connect(_on_bird_escaped)
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
	if _pause_menu.visible:
		return
	_pause_menu.show()
	_resume_button.grab_focus(true)
	pause_log.append(cause)
	print("[Play] Paused (%s): wave %d at t %.2f, score %d" % [cause, wave.index, wave_clock, scoring.score])


## Closes the pause menu and continues the run where it stopped (`cause`: "Resume" for
## the button, "Escape"). Ignored once the run is over (the menu of a run that could not
## start stays up).
func resume(cause := "Resume") -> void:
	if not _pause_menu.visible or _over:
		return
	_pause_menu.hide()
	get_tree().paused = false
	print("[Play] Resumed (%s): wave %d at t %.2f, score %d" % [cause, wave.index, wave_clock, scoring.score])


func is_paused() -> bool:
	return _pause_menu.visible


func is_empty_cue_shown() -> bool:
	return _empty_label.visible


## True while the rival raises his gun (an aim cue is on a flying bird).
func is_rival_aiming() -> bool:
	return _rival.texture == RIVAL_AIM


## The heckle in the rival's bubble, or "" when it is hidden.
func heckle_shown() -> String:
	return _bubble.text if _bubble.visible else ""


func _start_run() -> void:
	var args := _game.flow_args
	if not args.has("mode"):
		# Opened without a goto (the project check, the editor's Run Current Scene).
		args = {"mode": GameState.ENDLESS_MODE, "seed": randi()}
		print("[Play] Opened without run args; starting %s with a fresh seed" % args["mode"])
	mode = Content.mode(str(args["mode"]))
	if mode == null or not Content.errors().is_empty() or not args.get("seed") is int:
		_game.report_error("Cannot start a run of mode '%s' (seed %s): %d content problem(s), see the log" % [args["mode"], args.get("seed"), Content.errors().size()])
		# Nothing runs; the menu offers only the way back to the title.
		_over = true
		_resume_button.disabled = true
		_restart_button.disabled = true
		_pause_menu.show()
		_quit_button.grab_focus(true)
		return
	run_seed = args["seed"]
	scoring = Scoring.new(mode.combo_cap)
	rival_lines = Content.rival_lines()
	print("[Play] Run start: mode %s, seed %d (escape limit %d, combo cap %d, %d shells per hit, rival steals %s, aim %.2f s, heckle cooldown %.2f s)" % [
		mode.id, run_seed, mode.escape_limit, mode.combo_cap, mode.shells_per_hit, "on" if mode.rival_steals else "off", rival_lines.aim_time, rival_lines.cooldown])
	_start_wave(1)


func _start_wave(index: int) -> void:
	wave = Wave.endless(mode, index, run_seed)
	wave_clock = -WAVE_LEAD
	_next_spawn = 0
	var ids := PackedStringArray()
	for spawn in wave.spawns:
		ids.append(spawn.bird_id)
	print("[Play] Wave %d start: %d birds (%s), %d shells, speed x%.2f" % [index, wave.spawns.size(), ", ".join(ids), wave.shells, wave.speed_scale])
	set_shell_pool(wave.shells)


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
		print("[Play] Shot refused at (%.1f, %.1f): no shells left (wave %d at t %.2f, %d refused)" % [at.x, at.y, wave.index, wave_clock, refused])
		_show_empty_cue()
		return
	var target := bird_at(point)
	if target != null and target.spec.penalty > 0:
		_hit_decoy(target, point, at)
	elif target != null:
		_hit_bird(target, point, at)
	else:
		scoring.miss()
		print("[Play] Miss at (%.1f, %.1f): combo reset, score %d (wave %d at t %.2f, %d shells left)" % [at.x, at.y, scoring.score, wave.index, wave_clock, ammo.shells])
		_heckle("miss")
	if ammo.is_empty():
		var fleeing := flying_birds()
		for bird in fleeing:
			bird.flee()
		print("[Play] Out of shells: %d flying birds flee, %d still to spawn will flee (wave %d)" % [fleeing.size(), wave.spawns.size() - _next_spawn, wave.index])
	_update_hud()


## A hit on a bird other than the decoy: damage short of its hp, else a kill that scores
## (and splits a splitter).
func _hit_bird(target: Bird, point: Vector2, at: Vector2) -> void:
	var multiplier := scoring.multiplier
	if not target.hit():
		scoring.damage()
		_popup(point, DAMAGE_TEXT)
		print("[Play] Hit %s #%d (hit %d/%d) at (%.1f, %.1f): no points, combo x%d kept, score %d (wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, multiplier, scoring.score, wave.index, wave_clock, ammo.shells])
		return
	var awarded := scoring.hit(target.spec.points)
	_popup(point, "+%d" % awarded if multiplier == 1 else "+%d x%d" % [awarded, multiplier])
	print("[Play] Hit %s #%d (hit %d/%d, killed) at (%.1f, %.1f): %d points x%d = %d, score %d (wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, target.spec.points, multiplier, awarded, scoring.score, wave.index, wave_clock, ammo.shells])
	if target.is_cued():
		_cancel_cue(target, "shot by the player")
	if scoring.multiplier >= COMBO_HECKLE_MIN and scoring.multiplier > multiplier:
		_heckle("combo")
	if target.spec.split_count > 0:
		_split(target, point)


## Launches the killed splitter's goslings from `point` (World coordinates) on diverging
## headings; each has its own seed derived from the splitter's.
func _split(parent: Bird, point: Vector2) -> void:
	var children := PackedStringArray()
	var headings := Flight.split_headings(parent.spec.split_count)
	for i in headings.size():
		var child_seed := hash([parent.bird_seed, i])
		var child := spawn_bird(parent.spec.splits_into, child_seed, point, headings[i])
		children.append("#%d seed %d heading (%.2f, %.2f)" % [child.number, child_seed, headings[i].x, headings[i].y])
	print("[Play] Split %s #%d at (%.1f, %.1f) into %d %s: %s (wave %d at t %.2f)%s" % [parent.spec.id, parent.number, point.x, point.y, headings.size(), parent.spec.splits_into, ", ".join(children), wave.index, wave_clock, ", fleeing (no shells)" if ammo.is_empty() else ""])


## A hit on the decoy: its penalty comes off the score (never below 0) and the combo resets.
func _hit_decoy(target: Bird, point: Vector2, at: Vector2) -> void:
	target.hit()
	var deducted := scoring.penalty(target.spec.penalty)
	_popup(point, "-%d" % deducted, PENALTY_COLOR)
	print("[Play] Hit %s #%d (hit %d/%d, killed) at (%.1f, %.1f): penalty %d, -%d, combo reset, score %d (%d pigeons hit, wave %d at t %.2f, %d shells left)" % [target.spec.id, target.number, target.hits_taken, target.spec.hp, at.x, at.y, target.spec.penalty, deducted, scoring.score, scoring.penalties, wave.index, wave_clock, ammo.shells])


## Asks Rival about every flying bird: start or keep its aim cue, drop it (the bird
## started fleeing, or steals were turned off), or steal it once the cue has run.
func _update_steals() -> void:
	for bird in flying_birds():
		match Rival.steal_state(bird.age, bird.spec.linger_time, rival_lines.aim_time, bird.cue_age, bird.spec.penalty > 0, bird.is_fleeing(), mode.rival_steals):
			Rival.Steal.NONE:
				if bird.is_cued():
					_cancel_cue(bird, "fled" if bird.is_fleeing() else "rival steals off")
			Rival.Steal.AIMING:
				if not bird.is_cued():
					_start_cue(bird)
			Rival.Steal.FIRE:
				_steal(bird)
				if _over:
					return


func _start_cue(bird: Bird) -> void:
	bird.set_cue(true)
	_update_rival_pose()
	print("[Play] Aim cue on %s #%d: age %.2f (linger %.2f s), the rival fires in %.2f s (wave %d at t %.2f, rival score %d, %d stolen)" % [
		bird.spec.id, bird.number, bird.age, bird.spec.linger_time, rival_lines.aim_time, wave.index, wave_clock, rival_score, stolen])


func _cancel_cue(bird: Bird, cause: String) -> void:
	var held := bird.age - bird.cue_age
	bird.set_cue(false)
	_update_rival_pose()
	print("[Play] Aim cue on %s #%d cancelled (%s) after %.2f s (wave %d at t %.2f, rival score %d, %d stolen)" % [bird.spec.id, bird.number, cause, held, wave.index, wave_clock, rival_score, stolen])


## The rival fires: the bird falls as stolen, its points go to his tally (no combo) and it
## counts as an escape; the player's combo is left alone.
func _steal(bird: Bird) -> void:
	var held := bird.age - bird.cue_age
	bird.steal()
	_update_rival_pose()
	stolen += 1
	rival_score += bird.spec.points
	escaped += 1
	print("[Play] Stolen %s #%d by the rival after a %.2f s cue: %d points to the rival, rival score %d, %d stolen, %d/%d escaped, combo x%d kept (wave %d at t %.2f)" % [
		bird.spec.id, bird.number, held, bird.spec.points, rival_score, stolen, escaped, mode.escape_limit, scoring.multiplier, wave.index, wave_clock])
	_heckle(Rival.STEAL)
	_update_hud()
	if escaped >= mode.escape_limit:
		_end_run()


## The rival raises his gun while any flying bird has an aim cue.
func _update_rival_pose() -> void:
	var aiming := flying_birds().any(func(bird: Bird) -> bool: return bird.is_cued())
	_rival.texture = RIVAL_AIM if aiming else RIVAL_IDLE


## Shows a `category` line (Rival.pick_line) in the rival's bubble for HECKLE_TIME, unless
## the cooldown since the last heckle has not passed yet (Rival.may_heckle; steal lines
## always show). Both are logged.
func _heckle(category: String) -> void:
	if not Rival.may_heckle(category, run_clock, _last_heckle, rival_lines.cooldown):
		print("[Play] Heckle (%s) skipped: cooldown, %.2f of %.2f s since the last (wave %d at t %.2f, rival score %d, %d stolen)" % [
			category, run_clock - _last_heckle, rival_lines.cooldown, wave.index, wave_clock, rival_score, stolen])
		return
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
	print("[Play] Heckle (%s) #%d: \"%s\" (wave %d at t %.2f, rival score %d, %d stolen)" % [category, heckles, line, wave.index, wave_clock, rival_score, stolen])


func _on_bird_escaped(bird: Bird) -> void:
	if _over:
		return
	if not bird.spec.escape_counts:
		print("[Play] Escaped %s #%d (not counted, %d/%d, wave %d at t %.2f)" % [bird.spec.id, bird.number, escaped, mode.escape_limit, wave.index, wave_clock])
		return
	escaped += 1
	print("[Play] Escaped %s #%d (%d/%d, wave %d at t %.2f)" % [bird.spec.id, bird.number, escaped, mode.escape_limit, wave.index, wave_clock])
	_update_hud()
	if escaped >= mode.escape_limit:
		_end_run()


func _end_run() -> void:
	_stop()
	var new_best := _game.record_endless(scoring.score)
	var save_error := _game.save_error if new_best else ""
	var rival_line := Rival.pick_line(rival_lines.lines["results"], run_seed, heckles)
	heckles += 1
	print("[Play] Heckle (results) #%d: \"%s\" (wave %d at t %.2f, rival score %d, %d stolen)" % [heckles, rival_line, wave.index, wave_clock, rival_score, stolen])
	var stats := {
		"mode": mode.id, "seed": run_seed, "score": scoring.score, "shots": scoring.shots(), "hits": scoring.hits, "kills": scoring.kills,
		"pigeons": scoring.penalties, "escaped": escaped, "stolen": stolen, "rival_score": rival_score, "rival_line": rival_line,
		"best": _game.best_endless, "new_best": new_best, "save_error": save_error,
	}
	var best_note := ""
	if new_best:
		best_note = " (new best, not saved: %s)" % save_error if save_error != "" else " (new best)"
	print("[Play] Run end: mode %s, seed %d, wave %d, score %d, %d shots (%d hits, %d misses, %d pigeons hit), %d birds killed, %d refused, %d escaped (%d stolen), rival score %d, best %d%s" % [
		mode.id, run_seed, wave.index, scoring.score, scoring.shots(), scoring.hits, scoring.misses, scoring.penalties, scoring.kills, refused, escaped, stolen, rival_score, _game.best_endless, best_note])
	_game.goto(GameState.Flow.RESULTS, stats)


## Ends the run here: the world freezes, the menu closes and the tree runs again (the
## next scene must not start paused).
func _stop() -> void:
	_over = true
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_pause_menu.hide()
	get_tree().paused = false


func _restart() -> void:
	_leave("Restart")
	_game.start_endless()


func _quit() -> void:
	_leave("Quit to title")
	_game.goto(GameState.Flow.TITLE)


func _leave(cause: String) -> void:
	_stop()
	if wave == null:
		print("[Play] Left (%s): the run never started" % cause)
		return
	print("[Play] Left the run (%s): mode %s, seed %d, wave %d, score %d, %d escaped" % [cause, mode.id, run_seed, wave.index, scoring.score, escaped])


## Escape (CancelKey, which runs while paused too) opens the pause menu, or resumes the
## run when the menu is open.
func _on_cancel() -> void:
	if is_paused():
		resume("Escape")
	else:
		open_pause("Escape")


## The overlay hiding unpauses the tree when it paused it; a run it covered (or one whose
## pause menu is open) is paused again, so the menu never shows over a running tree.
func _on_rotate_overlay_changed(shown: bool) -> void:
	if shown:
		_rotated = not _over
	elif _rotated or is_paused():
		_rotated = false
		open_pause("rotate overlay")


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


func _popup(point: Vector2, text: String, color := POPUP_COLOR) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 26)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.17, 0.15, 0.13))
	label.add_theme_constant_override(&"outline_size", 6)
	_popups.add_child(label)
	label.position = point - label.get_combined_minimum_size() / 2.0
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - POPUP_RISE, POPUP_TIME)
	tween.tween_property(label, "modulate:a", 0.0, POPUP_TIME)
	tween.chain().tween_callback(label.queue_free)


func _update_hud() -> void:
	_score_label.text = "Score %d" % scoring.score
	_wave_label.text = "Wave %d" % wave.index
	if _shell_count.visible:
		_shell_count.text = "x%d" % ammo.shells
	else:
		for icon in _shells.get_children():
			if icon != _shell_count:
				(icon as CanvasItem).visible = icon.get_index() < ammo.shells
	_combo_label.text = "x%d" % scoring.multiplier
	_rival_label.text = "Rival %d" % rival_score
	_escaped_label.text = "Escaped %d/%d" % [escaped, mode.escape_limit]


## Lays the scene out in the visible area: the base playfield centred horizontally, the
## sky and grass across the whole width, the ground down to the bottom, the HUD bar at
## the top of the safe area and the shot surface below it.
func _fit() -> void:
	var shown := _game.visible_rect()
	var safe := _game.safe_rect()
	_world.position = Vector2(shown.position.x + (shown.size.x - BASE_SIZE.x) / 2.0, shown.position.y)
	var left := shown.position.x - _world.position.x
	_sky.position = Vector2(left, 0.0)
	_sky.size = shown.size
	_grass.position = Vector2(left, GRASS_Y - GRASS_TIP)
	_grass.size = Vector2(shown.size.x, _grass.texture.get_height())
	_ground.position = Vector2(left, _grass.position.y + _grass.size.y - 1.0)
	_ground.size = Vector2(shown.size.x, maxf(0.0, shown.end.y - _ground.position.y))
	_bar.position = safe.position
	_bar.size = Vector2(safe.size.x, HUD_BAR_HEIGHT)
	var top := safe.position.y + HUD_BAR_HEIGHT
	_shot_input.position = Vector2(shown.position.x, top)
	_shot_input.size = Vector2(shown.size.x, shown.end.y - top)
