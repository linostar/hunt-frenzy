class_name RunRecord
## The end of a run: records it (a level's stars and best through SaveStore.record_level, a
## mode's best through record_best, each saved at once), logs the run's end and builds the
## stats the results screen reads (Results.STAT_KEYS). Run once, by Play.end_run.


## Records `play`'s finished run in `save`, logs it and returns the results' stats.
static func record(play: Play, save: SaveStore) -> Dictionary:
	var scoring := play.scoring
	var stats := {
		"seed": play.run_seed, "score": scoring.score, "shots": scoring.shots(), "hits": scoring.hits, "kills": scoring.kills,
		"pigeons": scoring.penalties, "escaped": play.escaped, "stolen": play.rival.stolen, "rival_score": play.rival.rival_score,
		"rival_line": play.rival.results_line(), "rival_steals": play.steals_on(),
	}
	if play.level != null:
		stats.merge(_record_level(play, save))
	else:
		stats.merge(_record_mode(play, save))
	return stats


## The level's stars, best and the next level once open; logged.
static func _record_level(play: Play, save: SaveStore) -> Dictionary:
	var level := play.level
	var new_best := save.record_level(level, play.scoring.score)
	var kept: Campaign.Record = save.progress[level.id]
	var next := Campaign.next_level(level)
	var stars := Campaign.stars(level, play.scoring.score)
	print("[Play] Run end: level %s, seed %d, wave %d of %d, %s, %d stars, level best %d (%d stars)%s%s" % [
		level.id, play.run_seed, play.wave.index, level.waves, _summary(play), stars, kept.score, kept.stars,
		" (new best)" if new_best else "", ", not saved: %s" % save.save_error if save.save_error != "" else ""])
	return {"level": level.id, "stars": stars, "best": kept.score, "best_stars": kept.stars, "new_best": new_best,
		"save_error": save.save_error, "next_level": next.id if next != null and Campaign.is_unlocked(next, save.progress) else ""}


## The mode's best (a failed save of a new best named); logged.
static func _record_mode(play: Play, save: SaveStore) -> Dictionary:
	var mode := play.mode
	var new_best := save.record_best(mode, play.scoring.score)
	var save_error := save.save_error if new_best else ""
	var best_note := ""
	if new_best:
		best_note = " (new best, not saved: %s)" % save_error if save_error != "" else " (new best)"
	var time_used := ", time used %.2f of %.2f s" % [play.run_clock, mode.time_limit] if mode.is_timed() else ""
	print("[Play] Run end: mode %s, seed %d, wave %d%s, %s, best %d%s" % [
		mode.id, play.run_seed, play.wave.index, time_used, _summary(play), save.best(mode.id), best_note])
	return {"mode": mode.id, "best": save.best(mode.id), "new_best": new_best, "save_error": save_error}


## The run's score, shots and losses for the run end log.
static func _summary(play: Play) -> String:
	var scoring := play.scoring
	return "score %d, %d shots (%d hits, %d misses, %d pigeons hit), %d birds killed, %d refused, %d escaped (%d stolen), rival score %d" % [
		scoring.score, scoring.shots(), scoring.hits, scoring.misses, scoring.penalties, scoring.kills, play.refused, play.escaped,
		play.rival.stolen, play.rival.rival_score]
