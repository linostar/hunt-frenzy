class_name ShotResolver
extends Node
## Play/Shots: what a shot does. Every pressed touch on Play's ShotInput is a shot (resolve):
## with no shells left it is refused; else it hits the frontmost flying bird whose hitbox holds
## the point (never through the grass, at or below Layout.GRASS_Y), else misses. A hit damages a
## bird short of its hp, else kills it (points x combo, the hit stop, feathers, a shake for an
## armored or the golden bird; a splitter launches its goslings); the decoy costs its penalty.
## It also picks the run's sounds: the seeded pitch of the frequent ones (play_sound) and each
## kill's. Of Play (its parent) it uses the run's state (ammo, scoring, wave, level, mode),
## is_over(), flying_birds(), spawn_bird(), shells_ran_out(), update_hud(), wave_note() and
## clock_note(); it reaches its siblings HitStop, Shaker and RivalController and the World's
## Feathers and Popups directly.

## The pop-up of a hit that only damages a bird.
const DAMAGE_TEXT := "Clank!"
## The run's most frequent sounds, each played at a seeded pitch (Game.tuning.sound_pitch_spread).
const VARIED_SOUNDS: Array[StringName] = [AudioManager.SFX_SHOT, AudioManager.SFX_HIT, AudioManager.SFX_ESCAPE]

## Shots refused because the pool was empty.
var refused := 0

## Draws the pitch of each VARIED_SOUNDS sound (seeded by start).
var _pitch_rng := RandomNumberGenerator.new()

@onready var _game := get_node(GameState.AUTOLOAD_PATH) as GameState
@onready var _play := get_parent() as Play
@onready var _world: Node2D = $"../World"
@onready var _feathers: Feathers = $"../World/Feathers"
@onready var _popups: Node2D = $"../World/Popups"
@onready var _hit_stop: HitStop = $"../HitStop"
@onready var _shaker: ScreenShake = $"../Shaker"
@onready var _rival: RivalController = $"../RivalController"


## Seeds the sound pitches from the run's seed (Play._start_run).
func start(run_seed: int) -> void:
	_pitch_rng.seed = hash([run_seed, "sound pitch"])


## A shot at `at` (canvas): ignored once the run is over, while paused or during a transition.
## Sounds: with a shell "shot", then what it hit (_kill_sound for a kill, "armored_clank" for
## damage, "decoy_penalty", "combo_up" when the combo rose; nothing more for a miss), and
## "out_of_shells" after the last shell (Play.shells_ran_out); with none, only "empty_click".
func resolve(at: Vector2) -> void:
	if _play.is_over() or get_tree().paused or _game.flow.is_transitioning():
		return
	var point := _world.to_local(at)
	if not _play.ammo.use():
		refused += 1
		_game.audio.play_sfx(AudioManager.SFX_EMPTY_CLICK)
		print("[Play] Shot refused at %s: no shells left (%s, %d refused)" % [Play.at_note(at), _play.wave_note(), refused])
		_play.hud.show_empty_cue()
		return
	play_sound(AudioManager.SFX_SHOT)
	var target := bird_at(point)
	if target != null and target.spec.penalty > 0:
		_hit_decoy(target, point, at)
	elif target != null:
		_hit_bird(target, point, at)
	else:
		_play.scoring.miss()
		print("[Play] Miss at %s: combo reset, score %d (%s)" % [Play.at_note(at), _play.scoring.score, _shot_note()])
		if _rival.heckle("miss"):
			_rival.react(RivalController.RIVAL_BRAG, "brags after the miss")
	if _play.ammo.is_empty():
		_play.shells_ran_out()
	_play.update_hud()


## The frontmost (latest spawned, drawn on top) flying bird whose hitbox holds `point`
## (World coordinates), or null. A point on the grass (at or below Layout.GRASS_Y) hits nothing:
## the grass is drawn over the birds behind it.
func bird_at(point: Vector2) -> Bird:
	if point.y >= Layout.GRASS_Y:
		return null
	var flying := _play.flying_birds()
	for i in range(flying.size() - 1, -1, -1):
		if flying[i].contains(point):
			return flying[i]
	return null


## Plays sound `id`, a VARIED_SOUNDS one at its next seeded pitch within Game.tuning.sound_pitch_spread.
func play_sound(id: StringName) -> void:
	var spread := _game.tuning.sound_pitch_spread
	var pitch := _pitch_rng.randf_range(1.0 - spread, 1.0 + spread) if id in VARIED_SOUNDS else 1.0
	_game.audio.play_sfx(id, pitch)


## A hit on a bird other than the decoy: damage short of its hp, else a kill that scores
## (and splits a splitter).
func _hit_bird(target: Bird, point: Vector2, at: Vector2) -> void:
	var scoring := _play.scoring
	var multiplier := scoring.multiplier
	if not target.hit():
		scoring.damage()
		_game.audio.play_sfx(AudioManager.SFX_ARMORED_CLANK)
		_popup(point, DAMAGE_TEXT, HitPopup.Kind.DAMAGE)
		print("[Play] Hit %s: no points, combo x%d kept, score %d (%s)" % [_hit_note(target, at, false), multiplier, scoring.score, _shot_note()])
		return
	var awarded := scoring.hit(target.spec.points)
	play_sound(_kill_sound(target.spec))
	if scoring.multiplier > multiplier:
		_game.audio.play_sfx(AudioManager.SFX_COMBO_UP)
	_hit_stop.start(target, target.spec.hp > 1 or _is_golden(target.spec))
	_feathers.burst(point, target.spec.sprite)
	if target.spec.hp > 1:
		_shaker.shake(ScreenShake.ARMORED_KILL)
	elif _is_golden(target.spec):
		_shaker.shake(ScreenShake.GOLDEN_KILL)
	_popup(point, "+%d" % awarded if multiplier == 1 else "+%d x%d" % [awarded, multiplier], HitPopup.Kind.SCORE if multiplier == 1 else HitPopup.Kind.COMBO, multiplier)
	print("[Play] Hit %s: %d points x%d = %d, score %d (%s)" % [_hit_note(target, at, true), target.spec.points, multiplier, awarded, scoring.score, _shot_note()])
	_rival.react(RivalController.RIVAL_SULK, "sulks at the %d points on %s #%d" % [awarded, target.spec.id, target.number])
	if target.is_cued():
		_rival.cancel_cue(target, "shot by the player")
	if scoring.multiplier >= RivalController.COMBO_HECKLE_MIN and scoring.multiplier > multiplier:
		_rival.heckle("combo")
	if target.spec.split_count > 0:
		_split(target, point)


## The sound of a kill: an armored bird's (hp above 1) last hit, a splitter bursting, the
## run's golden bird, or a plain hit.
func _kill_sound(spec: BirdSpec) -> StringName:
	if spec.hp > 1:
		return AudioManager.SFX_ARMORED_KILL
	if spec.split_count > 0:
		return AudioManager.SFX_SPLIT_POP
	if _is_golden(spec):
		return AudioManager.SFX_GOLDEN_CHIME
	return AudioManager.SFX_HIT


## True for the run's golden bird (its level's or mode's golden_bird).
func _is_golden(spec: BirdSpec) -> bool:
	return spec.id == (_play.level.golden_bird if _play.level != null else _play.mode.golden_bird)


## Launches the killed splitter's goslings from `point` (World coordinates) on diverging
## headings; each has its own seed derived from the splitter's.
func _split(parent: Bird, point: Vector2) -> void:
	var children := PackedStringArray()
	var headings := Flight.split_headings(parent.spec.split_count)
	for i in headings.size():
		var child_seed := hash([parent.bird_seed, i])
		var child := _play.spawn_bird(parent.spec.splits_into, child_seed, point, headings[i])
		# A lost wave's splitter (Time Attack) launches goslings of that wave, fleeing.
		if parent.wave_index != _play.wave.index:
			child.wave_index = parent.wave_index
			child.flee()
		children.append("#%d seed %d heading (%.2f, %.2f)" % [child.number, child_seed, headings[i].x, headings[i].y])
	print("[Play] Split %s at %s into %d %s: %s (%s)%s" % [Play.bird_name(parent), Play.at_note(point), headings.size(), parent.spec.splits_into, ", ".join(children), _play.wave_note(), ", fleeing (no shells)" if _play.ammo.is_empty() else ""])


## A hit on the decoy: its penalty comes off the score (never below 0) and the combo resets.
func _hit_decoy(target: Bird, point: Vector2, at: Vector2) -> void:
	var scoring := _play.scoring
	target.hit()
	var deducted := scoring.penalty(target.spec.penalty)
	_game.audio.play_sfx(AudioManager.SFX_DECOY_PENALTY)
	_feathers.burst(point, target.spec.sprite)
	_shaker.shake(ScreenShake.DECOY_HIT)
	_popup(point, "-%d" % deducted, HitPopup.Kind.PENALTY)
	print("[Play] Hit %s: penalty %d, -%d, combo reset, score %d (%d pigeons hit, %s)" % [_hit_note(target, at, true), target.spec.penalty, deducted, scoring.score, scoring.penalties, _shot_note()])


## A pop-up of `text` of `kind` (HitPopup) centred on `point` (World coordinates), kept
## inside the visible area.
func _popup(point: Vector2, text: String, kind: HitPopup.Kind, multiplier := 1) -> void:
	var visible := _game.screen.visible_rect()
	var shown := Rect2(visible.position - _world.position, visible.size)
	HitPopup.spawn(_popups, point, text, kind, multiplier, shown, _game.save.reduce_motion)


## "<type> #n (hit k/hp[, killed]) at (x, y)": a hit on `target` at `at`, for the log lines.
static func _hit_note(target: Bird, at: Vector2, killed: bool) -> String:
	return "%s (hit %d/%d%s) at %s" % [Play.bird_name(target), target.hits_taken, target.spec.hp, ", killed" if killed else "", Play.at_note(at)]


## "wave n at t T, S shells left" in a shot's log lines.
func _shot_note() -> String:
	return "%s, %d shells left" % [_play.wave_note(), _play.ammo.shells]
