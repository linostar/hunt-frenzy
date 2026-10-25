extends SceneTree
## Headless run of the game's main scene for validate.sh: loads it the way the
## engine would, runs RUN_FRAMES frames (env, default 120), then frees it and quits cleanly.
## Requires the Game autoload and that its flow state is the one whose scene is running.
## Prints "run_main: OK" on success.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var error := change_scene_to_file(path)
	if error != OK:
		printerr("run_main: FAILED to load main scene '%s': %s" % [path, error_string(error)])
		quit(1)
		return
	var frames := int(OS.get_environment("RUN_FRAMES")) if OS.get_environment("RUN_FRAMES") != "" else 120
	for i in frames:
		await process_frame
	var game := root.get_node_or_null("Game") as GameState
	if game == null:
		printerr("run_main: FAILED: Game autoload not found")
		quit(1)
		return
	var at := str(GameState.Flow.keys()[game.state])
	if current_scene == null or current_scene.scene_file_path != game.scene_paths[game.state]:
		printerr("run_main: FAILED: flow at %s but the running scene is %s" % [at, current_scene.scene_file_path if current_scene != null else "none"])
		quit(1)
		return
	current_scene.queue_free()
	await process_frame
	print("run_main: OK (%s, %d frames, flow at %s)" % [path, frames, at])
	quit(0)
