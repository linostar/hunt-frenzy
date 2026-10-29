class_name Title
extends Control
## Title screen: the game's name, a tagline, the Campaign, Endless and Time Attack buttons
## side by side (the two modes' buttons show that mode's best score from the save) and
## below them Settings and Credits, laid out in the safe area (Game ScreenFit) and refitted
## whenever it changes. Campaign is focused on arrival (without drawing the focus ring
## until the player navigates by keyboard), so Enter presses it; coming back from Settings
## or Credits (Game.flow_args {"focus": "settings" | "credits"}) focuses that button
## instead. Left/right cycle along a row, up/down move between the rows, Tab runs through
## all five. Campaign opens the chapter select, Endless starts an Endless run
## (Game.start_endless), Time Attack a Time Attack run (Game.start_time_attack), Settings
## the settings screen, Credits the credits screen. When Content reports errors in
## data/*.json, the ContentErrorBanner says so and Campaign, Endless, Time Attack and
## Settings are disabled (the save is left unread then, and saving settings would replace
## it); Credits stays.
## Behind the buttons lies the sunset marsh (TITLE_BACKDROP's layers and the weather of the
## chapter that uses it) with the rival idling in the grass at the bottom left and geese
## crossing the sky (Flight's crossing path) on a seeded schedule (TITLE_SEED: one every
## GOOSE_GAP_MIN..MAX seconds, at most GEESE_MAX at once), in a band from below the top bar
## down to just above the first row of buttons, so a goose never covers a button. A tap on
## a goose (its hitbox polygon, as in play) shoots it: the shot and hit sounds, a feather
## burst, the goose falls, and the rival sulks and grumbles a heckle line with its blurt
## (cooldown permitting, as in play); it scores nothing and saves nothing, and is logged
## ("[Title] Shot goose #n"). A tap on empty sky plays the shot only; a tap on a button only
## presses it (the buttons lie above the shot surface). The scenery drifts slowly from side
## to side (DRIFT_AMPLITUDE over DRIFT_PERIOD) unless reduce motion is on.

const BIRD_SCENE := preload("res://scenes/bird.tscn")
const CONTENT_ERROR_MESSAGE := "Content error: %d problem(s) in data/*.json, see the log. Play is disabled."

## The Endless and Time Attack buttons' text: the mode's name and its best score.
const MODE_BUTTON_TEXT := "%s\nBest %d"
const RIVAL_IDLE := preload("res://art/rival_idle.svg")
const RIVAL_SULK := preload("res://art/rival_sulk.svg")
## The title's backdrop (art/backdrops/<id>_*.svg): the sunset marsh. Its weather is that of
## the chapter whose backdrop it is (data/chapters.json).
const TITLE_BACKDROP := "sunset"
## The bird that crosses the title's sky (data/birds.json).
const TITLE_BIRD := "goose"
## Seeds the geese's schedule and paths, so the title always plays the same.
const TITLE_SEED := 9091
## Seconds between two geese (seeded in this range) and the most crossing at once.
const GOOSE_GAP_MIN := 1.6
const GOOSE_GAP_MAX := 3.0
const GEESE_MAX := 4
## When the first goose sets off (seconds after the title arrives).
const FIRST_GOOSE_AT := 0.1
## The geese's band ends this far above the first row of buttons.
const BAND_MARGIN := 8.0
## The scenery's slow sway (base units either way, seconds per swing), off with reduce motion.
const DRIFT_AMPLITUDE := 10.0
const DRIFT_PERIOD := 24.0
## The rival's lines for a goose shot on the title (a grumble at the player's luck).
const HECKLE_CATEGORY := "combo"
## The rival stands this far in from the safe area's left and above its bottom.
const RIVAL_INSET := Vector2(16, 124)

## Times Campaign, Endless and Time Attack have been pressed on this screen (tests and the
## smoke test read the log).
var campaign_presses := 0
var endless_presses := 0
var time_attack_presses := 0
var settings_presses := 0
var credits_presses := 0
## Geese shot on the title, and heckles shown.
var geese_shot := 0
var heckles := 0

var _game: GameState
## Seconds since the title arrived (its own clock: the geese, the drift, the heckle cooldown).
var _clock := 0.0
var _goose_spec: BirdSpec
var _schedule := RandomNumberGenerator.new()
var _next_goose_at := FIRST_GOOSE_AT
var _geese := 0
## The geese's band, in the scenery's coordinates (_fit).
var _band := Rect2()
var _rival_lines: RivalLines
var _last_heckle := -INF
var _sulk_until := -INF
var _bubble_tween: Tween

@onready var _safe: Control = $Safe
@onready var _campaign_button: Button = $Safe/CampaignButton
@onready var _endless_button: Button = $Safe/EndlessButton
@onready var _time_attack_button: Button = $Safe/TimeAttackButton
@onready var _settings_button: Button = $Safe/SettingsButton
@onready var _credits_button: Button = $Safe/CreditsButton
@onready var _banner: Label = $Safe/ContentErrorBanner
@onready var _scenery: Node2D = $Scenery
@onready var _backdrop: Backdrop = $Scenery/Backdrop
@onready var _weather: Weather = $Scenery/Weather
@onready var _birds: Node2D = $Scenery/Birds
@onready var _feathers: Feathers = $Scenery/Feathers
@onready var _rival: TextureRect = $Scenery/Rival
@onready var _bubble: Label = $Scenery/Bubble
@onready var _shot_input: ShotInput = $ShotInput


func _ready() -> void:
	_game = get_node(GameState.AUTOLOAD_PATH) as GameState
	_game.screen_fit_changed.connect(_fit)
	_shot_input.shot.connect(_on_shot)
	_set_scenery()
	_fit()
	_campaign_button.pressed.connect(_on_campaign_pressed)
	_endless_button.pressed.connect(_on_endless_pressed)
	_time_attack_button.pressed.connect(_on_time_attack_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_endless_button.text = MODE_BUTTON_TEXT % ["Endless", _game.best(GameState.ENDLESS_MODE)]
	_time_attack_button.text = MODE_BUTTON_TEXT % ["Time Attack", _game.best(GameState.TIME_ATTACK_MODE)]
	print("[Title] Bests: Endless %d, Time Attack %d" % [_game.best(GameState.ENDLESS_MODE), _game.best(GameState.TIME_ATTACK_MODE)])
	var content_errors := Content.errors()
	if not content_errors.is_empty():
		print("[Title] Content has %d problem(s); Campaign, Endless, Time Attack and Settings are disabled" % content_errors.size())
		_banner.text = CONTENT_ERROR_MESSAGE % content_errors.size()
		_banner.show()
		_campaign_button.disabled = true
		_endless_button.disabled = true
		_time_attack_button.disabled = true
		_settings_button.disabled = true
	match str(_game.flow_args.get("focus", "")):
		Settings.TITLE_FOCUS:
			_settings_button.grab_focus(true)
		Credits.TITLE_FOCUS:
			_credits_button.grab_focus(true)
		_:
			_campaign_button.grab_focus(true)


## The sunset backdrop and its chapter's weather, and the geese's schedule (none when the
## data has problems: the banner says so). Logged.
func _set_scenery() -> void:
	_schedule.seed = TITLE_SEED
	var problems := Content.errors().size()
	var weather := ""
	if problems == 0:
		_goose_spec = Content.bird(TITLE_BIRD)
		_rival_lines = Content.rival_lines()
		for chapter in Content.chapters():
			if chapter.backdrop == TITLE_BACKDROP:
				weather = chapter.weather
	if _backdrop.show_backdrop(TITLE_BACKDROP) and weather != "":
		_weather.set_weather(weather)
	_rival.modulate = Backdrop.rival_tint(TITLE_BACKDROP)
	if _goose_spec == null:
		print("[Title] Scenery: backdrop %s, no geese and no weather (%d content problem(s))" % [TITLE_BACKDROP, problems])
		return
	print("[Title] Scenery: backdrop %s, weather %s, a %s every %.1f-%.1f s (seed %d, at most %d), %s" % [
		TITLE_BACKDROP, weather if weather != "" else "none", TITLE_BIRD, GOOSE_GAP_MIN, GOOSE_GAP_MAX, TITLE_SEED, GEESE_MAX,
		"still (reduce motion)" if _game.reduce_motion else "drifting %.0f either way over %.0f s" % [DRIFT_AMPLITUDE, DRIFT_PERIOD]])


func _process(delta: float) -> void:
	_clock += delta
	_scenery.position.x = 0.0 if _game.reduce_motion else DRIFT_AMPLITUDE * sin(TAU * _clock / DRIFT_PERIOD)
	while _goose_spec != null and _clock >= _next_goose_at:
		if flying_geese().size() < GEESE_MAX:
			_spawn_goose()
		_next_goose_at += _schedule.randf_range(GOOSE_GAP_MIN, GOOSE_GAP_MAX)
	_rival.texture = RIVAL_SULK if _clock < _sulk_until else RIVAL_IDLE


## The geese still flying, oldest first.
func flying_geese() -> Array[Bird]:
	var geese: Array[Bird] = []
	for child in _birds.get_children():
		var bird := child as Bird
		if bird != null and bird.is_flying():
			geese.append(bird)
	return geese


## The frontmost (latest) flying goose whose hitbox holds `point` (scenery coordinates), or null.
func goose_at(point: Vector2) -> Bird:
	var geese := flying_geese()
	for i in range(geese.size() - 1, -1, -1):
		if geese[i].contains(point):
			return geese[i]
	return null


## The band the geese cross (scenery coordinates; tests check it clears the buttons).
func goose_band() -> Rect2:
	return _band


## The rival's pose: "sulk" after a goose was shot, else "idle".
func rival_pose() -> String:
	return "sulk" if _rival.texture == RIVAL_SULK else "idle"


## The heckle in the rival's bubble, or "" when it is hidden.
func heckle_shown() -> String:
	return _bubble.text if _bubble.visible else ""


## The feather bursts (tests count them).
func feathers() -> Feathers:
	return _feathers


func _spawn_goose() -> void:
	_geese += 1
	var goose := BIRD_SCENE.instantiate() as Bird
	goose.setup_crossing(_goose_spec, _geese, _schedule.randi(), _band)
	_birds.add_child(goose)


## A tap below the top bar that no button took: a shot. A goose under it falls with a
## feather burst and a rival reaction; nothing is scored or saved.
func _on_shot(at: Vector2) -> void:
	if _game.is_transitioning():
		return
	var point := _scenery.to_local(at)
	_game.play_sfx(&"shot")
	var goose := goose_at(point)
	if goose == null:
		print("[Title] Shot at (%.1f, %.1f): missed" % [at.x, at.y])
		return
	goose.hit()
	geese_shot += 1
	_game.play_sfx(&"hit")
	_feathers.burst(point, goose.spec.sprite)
	print("[Title] Shot goose #%d at (%.1f, %.1f): it falls; no score, nothing saved (%d shot on the title)" % [goose.number, at.x, at.y, geese_shot])
	_sulk_until = _clock + Play.RIVAL_REACTION_TIME
	_rival.texture = RIVAL_SULK
	print("[Title] Rival sulks at goose #%d" % goose.number)
	_heckle()


## The rival grumbles a HECKLE_CATEGORY line in his bubble for Play.HECKLE_TIME with its
## blurt, unless the cooldown since his last one has not passed (logged either way).
func _heckle() -> void:
	if _rival_lines == null:
		return
	if not Rival.may_heckle(HECKLE_CATEGORY, _clock, _last_heckle, _rival_lines.cooldown):
		print("[Title] Heckle (%s) skipped: cooldown, %.2f of %.2f s since the last" % [HECKLE_CATEGORY, _clock - _last_heckle, _rival_lines.cooldown])
		return
	var line := Rival.pick_line(_rival_lines.lines[HECKLE_CATEGORY], TITLE_SEED, heckles)
	heckles += 1
	_last_heckle = _clock
	_bubble.text = line
	_bubble.show()
	if _bubble_tween != null:
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	_bubble_tween.tween_interval(Play.HECKLE_TIME)
	_bubble_tween.tween_callback(_bubble.hide)
	_game.play_heckle(HECKLE_CATEGORY, line)
	print("[Title] Heckle (%s) #%d: \"%s\"" % [HECKLE_CATEGORY, heckles, line])


func _fit() -> void:
	var safe := _game.safe_rect()
	var shown := _game.visible_rect()
	_safe.position = safe.position
	_safe.size = safe.size
	# The scenery covers the visible area plus the drift on each side.
	var local := shown.grow_individual(DRIFT_AMPLITUDE, 0.0, DRIFT_AMPLITUDE, 0.0)
	_backdrop.fit(local, Play.GRASS_Y - Play.GRASS_TIP)
	_weather.fit(local)
	_rival.position = Vector2(safe.position.x + RIVAL_INSET.x, safe.end.y - RIVAL_INSET.y)
	_bubble.position = Vector2(_rival.position.x + _rival.size.x + 8.0, safe.end.y - _bubble.size.y - 10.0)
	_shot_input.position = Vector2(shown.position.x, safe.position.y + Play.HUD_BAR_HEIGHT)
	_shot_input.size = Vector2(shown.size.x, shown.end.y - _shot_input.position.y)
	# From below the top bar to BAND_MARGIN above the first row of buttons (their anchored
	# top, known before the containers settle), across the visible width plus the drift.
	var buttons_top := safe.position.y + _campaign_button.anchor_top * safe.size.y + _campaign_button.offset_top
	var top := safe.position.y + Play.HUD_BAR_HEIGHT
	_band = Rect2(local.position.x, top, local.size.x, maxf(buttons_top - BAND_MARGIN - top, 0.0))
	# Geese already up move to the new band (a refit follows a resize or a rotation).
	for goose in flying_geese():
		goose.crossing = _band
	# Containers and anchors settle at the end of the frame; log the buttons' final rects
	# (base units) for the smoke test, which taps them.
	_log_layout.call_deferred()


func _log_layout() -> void:
	print("[Title] Campaign button at %s" % _campaign_button.get_global_rect())
	print("[Title] Endless button at %s" % _endless_button.get_global_rect())
	print("[Title] Time Attack button at %s" % _time_attack_button.get_global_rect())
	print("[Title] Settings button at %s" % _settings_button.get_global_rect())
	print("[Title] Credits button at %s" % _credits_button.get_global_rect())


func _on_campaign_pressed() -> void:
	campaign_presses += 1
	print("[Title] Campaign pressed (%d); opening the chapter select" % campaign_presses)
	_game.goto(GameState.Flow.CHAPTER_SELECT)


func _on_endless_pressed() -> void:
	endless_presses += 1
	print("[Title] Endless pressed (%d); starting Endless" % endless_presses)
	_game.start_endless()


func _on_time_attack_pressed() -> void:
	time_attack_presses += 1
	print("[Title] Time Attack pressed (%d); starting Time Attack" % time_attack_presses)
	_game.start_time_attack()


func _on_settings_pressed() -> void:
	settings_presses += 1
	print("[Title] Settings pressed (%d); opening the settings" % settings_presses)
	_game.goto(GameState.Flow.SETTINGS)


func _on_credits_pressed() -> void:
	credits_presses += 1
	print("[Title] Credits pressed (%d); opening the credits" % credits_presses)
	_game.goto(GameState.Flow.CREDITS)
