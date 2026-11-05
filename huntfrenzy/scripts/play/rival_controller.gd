class_name RivalController
extends Node
## Play/RivalController: the rival hunter (World/Rival, data/rival_lines.json; Layout.RIVAL_RECT) and
## his speech bubble (World/Bubble). He stands on the bank in the grass band (at or below the
## fringe's top, Layout.GRASS_Y - Layout.GRASS_TIP, so he never covers the field; he and his bubble
## ignore touches, so a shot anywhere hits as before), lit by the backdrop's tint
## (Backdrop.rival_tint, cross-fading with it: light, fade_light). In a run with steals
## (Play.steals_on), every frame update_steals asks Rival.steal_state about each flying bird:
## once one has flown its linger_time x Play.linger_scale (never the decoy, never a fleeing
## bird) the aim cue starts (a reticle on the bird, the rival raising his gun) and runs
## aim_time; a kill during it saves the bird (a damaging hit does not), a bird that starts
## fleeing drops it, and once it has run the rival fires and never misses: the bird falls as
## stolen, its points (no combo) go to his tally, it counts as an escape (stolen birds can end
## the run), the player's combo is untouched, a stolen splitter launches no goslings, and he
## laughs ("rival_laugh", Game.tuning.rival_laugh_delay after his shot). He aims at one bird at a time (Rival.may_aim): when several have flown their
## linger_time, the cue goes to the one that has flown longest (the lower number on a tie:
## Rival.aim_target), and after a steal or a cancelled cue he waits Game.tuning.rival_aim_gap seconds of
## run_clock (a pause does not count) before the next cue. With steals off he only heckles. He
## heckles (a Rival.pick_line line in the bubble for Game.tuning.heckle_time) on a miss, a combo rising to
## COMBO_HECKLE_MIN or more and a wave's end, at most once per cooldown, and on every steal;
## the results screen shows one more line (results_line). His pose follows the run: he raises
## his gun while any cue runs, else he sulks for Game.tuning.rival_reaction_time after each scored kill and
## brags for as long after a miss heckle that showed, else he stands idle. Cues, poses and the
## cooldown run on Play.run_clock, so a pause freezes them.
## Of Play (its parent) it uses only run_clock, run_seed, linger_scale, flying_birds(),
## steals_on(), is_over(), the combo (scoring.multiplier, for its log), wave_note(),
## escapes(), count_escape(), update_hud(), escape_limit_reached() and end_run(); it shakes
## the world through its sibling Shaker, bursts feathers through the World's Feathers and
## reads Game.tuning.

const RIVAL_IDLE := preload("res://art/rival_idle.svg")
const RIVAL_AIM := preload("res://art/rival_aim.svg")
const RIVAL_SULK := preload("res://art/rival_sulk.svg")
const RIVAL_BRAG := preload("res://art/rival_brag.svg")
## A kill that raises the combo to this multiplier or more draws a heckle.
const COMBO_HECKLE_MIN := 3

## Birds the rival stole, and the points they took to his tally.
var stolen := 0
var rival_score := 0
## His lines, aim time and cooldown (Play._start_run sets them from Content.rival_lines()).
var rival_lines: RivalLines
## Heckles shown this run (the next line's pick counter).
var heckles := 0

var _bubble_tween: Tween
## The run_clock of the last heckle shown (-INF before any).
var _last_heckle := -INF
## The run_clock the last aim cue ended at, by a steal or a cancel (-INF before any).
var _last_cue_end := -INF
## The rival's reaction (RIVAL_SULK or RIVAL_BRAG, null for none) and the run_clock it
## lasts until; aiming takes precedence over it.
var _reaction: Texture2D
var _reaction_until := -INF

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _play := get_parent() as Play
@onready var _shaker: ScreenShake = $"../Shaker"
@onready var _feathers: Feathers = $"../World/Feathers"
@onready var _rival: TextureRect = $"../World/Rival"
@onready var _bubble: Label = $"../World/Bubble"


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


## The heckle in the rival's bubble, or "" when it is hidden.
func heckle_shown() -> String:
	return _bubble.text if _bubble.visible else ""


## Lights the rival for backdrop `backdrop_id` at once (logged).
func light(backdrop_id: String) -> void:
	_rival.modulate = Backdrop.rival_tint(backdrop_id)
	print("[Play] Rival lit for backdrop %s: tint #%s" % [backdrop_id, _rival.modulate.to_html(false)])


## Adds the rival's light following backdrop `backdrop_id` over `time` to `tween` (in
## parallel with what it runs: the backdrop fading in).
func fade_light(tween: Tween, backdrop_id: String, time: float) -> void:
	tween.parallel().tween_property(_rival, "modulate", Backdrop.rival_tint(backdrop_id), time)


## Asks Rival about every flying bird: keep a running aim cue, drop it (the bird started
## fleeing, or steals were turned off), or steal its bird once the cue has run. With no
## cue running and the aim gap over (Rival.may_aim), a new cue starts on the eligible bird
## (one that has flown its linger_time with at least aim_time left before it flees)
## Rival.aim_target picks: the longest flown.
func update_steals() -> void:
	var cue_running := false
	var eligible: Array[Bird] = []
	var ages := PackedFloat64Array()
	var numbers := PackedInt32Array()
	for bird in _play.flying_birds():
		match Rival.steal_state(bird.age, bird.spec.linger_time * _play.linger_scale, rival_lines.aim_time, bird.cue_age, bird.spec.penalty > 0, minf(bird.spec.flee_time, bird.flee_at), _play.steals_on()):
			Rival.Steal.NONE:
				if bird.is_cued():
					cancel_cue(bird, "fled" if bird.is_fleeing() else "rival steals off")
			Rival.Steal.AIMING:
				if bird.is_cued():
					cue_running = true
				else:
					eligible.append(bird)
					ages.append(bird.age)
					numbers.append(bird.number)
			Rival.Steal.FIRE:
				_steal(bird)
				if _play.is_over():
					return
	if eligible.is_empty() or not Rival.may_aim(cue_running, _play.run_clock, _last_cue_end, _game.tuning.rival_aim_gap):
		return
	_start_cue(eligible[Rival.aim_target(ages, numbers)], eligible.size())


## Starts the rival's aim cue on `bird`, picked among `eligible` birds.
func _start_cue(bird: Bird, eligible: int) -> void:
	bird.set_cue(true)
	update_pose()
	_game.audio.play_sfx(AudioManager.SFX_RIVAL_AIM)
	var since := "no cue before" if _last_cue_end == -INF else "%.2f s since the last cue ended" % (_play.run_clock - _last_cue_end)
	print("[Play] Aim cue on %s #%d: age %.2f (linger %.2f s), the rival fires in %.2f s (the longest flown of %d eligible; %s, aim gap %.2f s) (%s, rival score %d, %d stolen)" % [
		bird.spec.id, bird.number, bird.age, bird.spec.linger_time * _play.linger_scale, rival_lines.aim_time, eligible, since, _game.tuning.rival_aim_gap, _play.wave_note(), rival_score, stolen])


## Drops the aim cue on `bird` for `cause`; no new cue for Game.tuning.rival_aim_gap. Logged.
func cancel_cue(bird: Bird, cause: String) -> void:
	var held := bird.age - bird.cue_age
	bird.set_cue(false)
	_last_cue_end = _play.run_clock
	update_pose()
	print("[Play] Aim cue on %s #%d cancelled (%s) after %.2f s (%s, rival score %d, %d stolen); no new cue for the %.2f s aim gap" % [bird.spec.id, bird.number, cause, held, _play.wave_note(), rival_score, stolen, _game.tuning.rival_aim_gap])


## The rival fires: the bird falls as stolen, its points go to his tally (no combo) and it
## counts as an escape; the player's combo is left alone.
func _steal(bird: Bird) -> void:
	var held := bird.age - bird.cue_age
	bird.steal()
	_last_cue_end = _play.run_clock
	update_pose()
	_game.audio.play_sfx(AudioManager.SFX_RIVAL_STEAL)
	_game.audio.play_sfx_later(AudioManager.SFX_RIVAL_LAUGH, _game.tuning.rival_laugh_delay)
	_feathers.burst(bird.position, bird.spec.sprite)
	_shaker.shake(ScreenShake.STEAL)
	stolen += 1
	rival_score += bird.spec.points
	_play.count_escape()
	print("[Play] Stolen %s #%d by the rival after a %.2f s cue: %d points to the rival, rival score %d, %d stolen, %s escaped, combo x%d kept (%s); he laughs in %.2f s, no new cue for the %.2f s aim gap" % [
		bird.spec.id, bird.number, held, bird.spec.points, rival_score, stolen, _play.escapes(), _play.scoring.multiplier, _play.wave_note(), _game.tuning.rival_laugh_delay, _game.tuning.rival_aim_gap])
	heckle(Rival.STEAL)
	_play.update_hud()
	if _play.escape_limit_reached():
		_play.end_run()


## The rival raises his gun while any flying bird has an aim cue; otherwise he holds his
## reaction (sulk or brag) until it runs out, then stands idle.
func update_pose() -> void:
	var aiming := _play.flying_birds().any(func(bird: Bird) -> bool: return bird.is_cued())
	if aiming:
		_rival.texture = RIVAL_AIM
	elif _reaction != null and _play.run_clock < _reaction_until:
		_rival.texture = _reaction
	else:
		_reaction = null
		_rival.texture = RIVAL_IDLE


## The rival reacts with `pose` (RIVAL_SULK or RIVAL_BRAG) for Game.tuning.rival_reaction_time of game
## time (logged as "[Play] Rival <what>").
func react(pose: Texture2D, what: String) -> void:
	_reaction = pose
	_reaction_until = _play.run_clock + _game.tuning.rival_reaction_time
	update_pose()
	print("[Play] Rival %s (%s)" % [what, _play.wave_note()])


## Shows a `category` line (Rival.pick_line) in the rival's bubble for Game.tuning.heckle_time, unless
## the cooldown since the last heckle has not passed yet (Rival.may_heckle; steal lines
## always show). Both are logged. Returns whether the line showed.
func heckle(category: String) -> bool:
	if not Rival.may_heckle(category, _play.run_clock, _last_heckle, rival_lines.cooldown):
		print("[Play] Heckle (%s) skipped: cooldown, %.2f of %.2f s since the last (%s, rival score %d, %d stolen)" % [
			category, _play.run_clock - _last_heckle, rival_lines.cooldown, _play.wave_note(), rival_score, stolen])
		return false
	var line := Rival.pick_line(rival_lines.lines[category], _play.run_seed, heckles)
	heckles += 1
	_last_heckle = _play.run_clock
	_bubble.text = line
	_bubble.show()
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(_game.tuning.heckle_time)
	_bubble_tween.tween_callback(_bubble.hide)
	print("[Play] Heckle (%s) #%d: \"%s\" (%s, rival score %d, %d stolen)" % [category, heckles, line, _play.wave_note(), rival_score, stolen])
	return true


## His parting line for the results screen (counted and logged as a heckle).
func results_line() -> String:
	var line := Rival.pick_line(rival_lines.lines["results"], _play.run_seed, heckles)
	heckles += 1
	print("[Play] Heckle (results) #%d: \"%s\" (%s, rival score %d, %d stolen)" % [heckles, line, _play.wave_note(), rival_score, stolen])
	return line
