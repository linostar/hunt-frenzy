extends SceneTree
## Captures the itch.io page media from the real game: the screenshots (itch/screenshots/) and,
## run under Movie Maker, the session the trailer is cut from (tools/itch_trailer.sh).
## It plays through a stand-in player: a crosshair sprite glides onto a bird, then the shot is
## emitted on the scene's ShotInput at the bird's hitbox centre, as a tap there would be.
## A tool run, so the game saves to SaveStore.TOOL_SAVE_PATH (never the player's save): it
## plants a save with the first three chapters finished, and removes it at the end.
## Each video segment prints "[Capture] mark <name> frame <n>" (Engine.get_frames_drawn()).
## Screenshots are taken at the window's pixel size; scale them to 1920x1080 afterwards
## (magick <png> -resize '1920x1080^' -gravity center -extent 1920x1080). The numbered ones are
## the page's; rival_aims and night_boss are extras (the committed 03 and 04 are session frames,
## see tools/itch_trailer.sh).
## Usage (repo root; windowed, not headless: the screenshots need a renderer). Movie Maker
## records at the project's window size (960x540) unless a temporary huntfrenzy/override.cfg
## sets [display] window/size/window_width_override=1920 and window_height_override=1080
## (delete it afterwards; never commit it):
##   "$GODOT" --path huntfrenzy --fixed-fps 30 --write-movie "$PWD/build/itch/session.avi" \
##     --script "$PWD/tools/itch_capture.gd" -- "$PWD/itch/screenshots"
## The window must keep focus while it records: losing it pauses the run (the pause menu).

## The finished chapters of the planted save (their levels at 1 star, 1000 points) and its bests.
const PLANTED_CHAPTERS: Array[String] = ["dawn", "noon", "sunset"]
const PLANTED_SCORE := 1000
const PLANTED_BESTS := {"endless": 4200, "time_attack": 3100}
## The crosshair's size in base units and how long it glides onto a target.
const CROSSHAIR_SCALE := 0.75
const AIM_TIME := 0.14
## Seconds between the stand-in player's shots (picked in this range, seeded).
const SHOT_GAP_MIN := 0.38
const SHOT_GAP_MAX := 0.55
## A bird is a target once its hitbox centre is this far above the grass line (in open sky,
## where its feathers and pop-up show well).
const ABOVE_GRASS := 130.0
## A screenshot of a hit waits this long after the shot: the pop-up at full size.
const HIT_SHOT_DELAY := 0.12
## Whole run limit, so a stuck step fails instead of hanging.
const WATCHDOG_MSEC := 600000

var _game: GameState
var _out_dir := ""
var _crosshair: Sprite2D
var _rng := RandomNumberGenerator.new()
var _deadline_msec := 0


func _initialize() -> void:
	_deadline_msec = Time.get_ticks_msec() + WATCHDOG_MSEC
	_game = root.get_node_or_null("Game") as GameState
	var args := OS.get_cmdline_user_args()
	if _game == null or args.is_empty():
		printerr("itch_capture: FAILED: needs the Game autoload and an output directory (-- <dir>)")
		quit(1)
		return
	_out_dir = args[0]
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		printerr("itch_capture: FAILED: cannot create %s" % _out_dir)
		quit(1)
		return
	_rng.seed = 2026
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > _deadline_msec:
		printerr("itch_capture: FAILED watchdog: the capture did not finish within %d ms" % WATCHDOG_MSEC)
		quit(1)
	return false


func _run() -> void:
	_plant_save()
	_add_crosshair()
	# The title: geese crossing the sunset marsh, one shot down.
	await _goto(SceneFlow.Flow.TITLE)
	_mark("title")
	await _wait(2.6)
	await _shoot_title_goose()
	await _wait(0.4)
	_screenshot("01_title")
	await _wait(1.6)
	_mark("title_end")
	# The chapter select.
	await _goto(SceneFlow.Flow.CHAPTER_SELECT)
	await _wait(1.0)
	_screenshot("05_chapter_select")
	# Dawn in the mist: a kill's feathers and pop-up.
	var play := await _start_level("dawn_2")
	await _autoplay(play, 3.2, false)
	await _hit_screenshot(play, "02_dawn_hit")
	# Sunset in the rain: armored birds, splitters and the decoy; the youngest bird first, so the
	# rival gets the ones left flying.
	play = await _start_level("sunset_3")
	_mark("sunset")
	await _autoplay(play, 12.0, true)
	_mark("sunset_end")
	# Noon in the wind: the rival takes aim at a lingering bird.
	play = await _start_level("noon_1")
	await _until_rival_aims(play, 9.0)
	_screenshot("rival_aims")
	# Night in the snow: the last level's boss flock.
	play = await _start_level("night_6")
	play.call("_start_wave", play.level.waves)
	_mark("boss")
	await _autoplay(play, 4.5, false)
	await _hit_screenshot(play, "night_boss")
	await _autoplay(play, 4.0, false)
	_mark("boss_end")
	# A whole first level, for its results: three stars and a new best.
	play = await _start_level("dawn_1")
	await _autoplay(play, 120.0, false, 0.32)
	_crosshair.hide()
	await _game.flow.transition_finished
	_mark("results")
	await _wait(2.2)
	_screenshot("06_results")
	await _wait(1.8)
	_mark("results_end")
	await _goto(SceneFlow.Flow.TITLE)
	_mark("end_card")
	await _wait(4.0)
	_mark("end_card_end")
	DirAccess.remove_absolute(SaveStore.TOOL_SAVE_PATH)
	_crosshair.get_parent().queue_free()
	await process_frame
	print("itch_capture: OK")
	quit(0)


## A version-4 save with every level of PLANTED_CHAPTERS finished (so night is open) and
## PLANTED_BESTS, loaded at once.
func _plant_save() -> void:
	var levels := {}
	for level in Campaign.levels():
		if level.chapter in PLANTED_CHAPTERS:
			levels[level.id] = {"stars": 1, "score": PLANTED_SCORE}
	var save := {
		"version": SaveStore.SAVE_VERSION, "bests": PLANTED_BESTS, "levels": levels,
		"settings": {"music": 70, "sfx": 80, "music_muted": false, "sfx_muted": false, "reduce_motion": false},
	}
	var file := FileAccess.open(SaveStore.TOOL_SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(save))
	file.close()
	_game.save.load_game()


## The stand-in player's crosshair, above every scene (hidden off the play and title scenes).
func _add_crosshair() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	_crosshair = Sprite2D.new()
	_crosshair.texture = Crosshair.TEXTURE
	_crosshair.scale = Vector2.ONE * CROSSHAIR_SCALE
	_crosshair.position = Vector2(480, 300)
	_crosshair.hide()
	layer.add_child(_crosshair)
	root.add_child(layer)


func _goto(state: SceneFlow.Flow) -> void:
	_crosshair.hide()
	_game.flow.goto(state)
	await _game.flow.transition_finished
	await process_frame


func _start_level(level_id: String) -> Play:
	_crosshair.hide()
	_game.flow.start_level(level_id)
	await _game.flow.transition_finished
	await process_frame
	return current_scene as Play


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _mark(segment: String) -> void:
	print("[Capture] mark %s frame %d" % [segment, Engine.get_frames_drawn()])


func _screenshot(shot_name: String) -> void:
	var path := _out_dir.path_join(shot_name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		printerr("itch_capture: FAILED to save %s (error %d)" % [path, error])
		quit(1)
		return
	print("[Capture] screenshot %s" % path)


## Where a bird's hitbox centre is on the canvas now.
func _aim_point(bird: Bird) -> Vector2:
	var centre := Vector2.ZERO
	for point in bird.spec.hitbox:
		centre += point
	centre /= bird.spec.hitbox.size()
	return (bird.get_parent() as Node2D).to_global(bird.transform * centre)


## Glides the crosshair onto `bird` over AIM_TIME, following it, then shoots it through
## `shot_input` (as a tap at that point would).
func _shoot(bird: Bird, shot_input: ShotInput) -> void:
	_crosshair.show()
	var start := _crosshair.position
	var elapsed := 0.0
	while elapsed < AIM_TIME and is_instance_valid(bird) and bird.is_flying():
		await process_frame
		elapsed += root.get_process_delta_time()
		_crosshair.position = start.lerp(_aim_point(bird), minf(elapsed / AIM_TIME, 1.0))
	if is_instance_valid(bird) and bird.is_flying():
		_crosshair.position = _aim_point(bird)
		shot_input.shot.emit(_crosshair.position)


func _shoot_title_goose() -> void:
	var title := current_scene as Title
	for _try in 60:
		for goose in title.flying_geese():
			var point := _aim_point(goose)
			if point.x > 120.0 and point.x < 840.0:
				await _shoot(goose, title.get_node("ShotInput") as ShotInput)
				return
		await process_frame


## The birds the stand-in player may shoot, oldest first: never the decoy, never a fleeing
## bird, only in open sky (ABOVE_GRASS).
func _targets(play: Play) -> Array[Bird]:
	var targets: Array[Bird] = []
	targets.assign(play.flying_birds().filter(func(candidate: Bird) -> bool:
		return candidate.spec.penalty == 0 and _aim_point(candidate).y < Layout.GRASS_Y - ABOVE_GRASS and not candidate.is_fleeing()))
	return targets


## Plays `play` for `seconds` (or until the run ends): every SHOT_GAP_MIN..MAX seconds it
## shoots a target (never the decoy): the oldest, or with `youngest_first` the newest.
func _autoplay(play: Play, seconds: float, youngest_first: bool, gap := -1.0) -> void:
	var shot_input := play.get_node("ShotInput") as ShotInput
	# Game time: under Movie Maker the wall clock runs at the render's pace.
	var timer := create_timer(seconds)
	while not play.is_over() and timer.time_left > 0.0:
		var targets := _targets(play)
		if targets.is_empty():
			await process_frame
			continue
		var bird: Bird = targets.back() if youngest_first else targets.front()
		await _shoot(bird, shot_input)
		await _wait(gap if gap > 0.0 else _rng.randf_range(SHOT_GAP_MIN, SHOT_GAP_MAX))


## Shoots the next target and takes screenshot `shot_name` HIT_SHOT_DELAY later (feathers and
## the pop-up at full size).
func _hit_screenshot(play: Play, shot_name: String) -> void:
	var shot_input := play.get_node("ShotInput") as ShotInput
	for _try in 300:
		var targets := _targets(play)
		if not targets.is_empty():
			await _shoot(targets.front(), shot_input)
			await _wait(HIT_SHOT_DELAY)
			_screenshot(shot_name)
			return
		await process_frame
	printerr("itch_capture: FAILED: no target for %s" % shot_name)
	quit(1)


## Waits (shooting nothing) until the rival aims, at most `seconds`.
func _until_rival_aims(play: Play, seconds: float) -> void:
	var timer := create_timer(seconds)
	while not play.rival.is_rival_aiming() and timer.time_left > 0.0:
		await process_frame
	await _wait(0.3)
