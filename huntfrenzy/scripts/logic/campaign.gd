class_name Campaign
extends RefCounted
## The campaign's rules. Static only: Game keeps the progress, the screens show it.
## Order: the chapters of data/chapters.json in data order, each chapter's levels by index
## (1..Content.LEVELS_PER_CHAPTER). Stars: a level's final score earns one star for each of
## its three thresholds it reaches; 0 stars means the level is not passed. Unlocks: the
## campaign's first level is always open; every other level opens once the level before it
## in campaign order (across chapters too: a chapter's level 1 follows the previous
## chapter's level 6) is passed. A chapter is open when its level 1 is. Progress keeps, per
## level, the best stars and the best score ever reached (separately; a replay never lowers
## either).

## Stars a level can earn (Content.STAR_COUNT thresholds).
const MAX_STARS := 3


## A level's best result: the most stars and the highest score ever reached in it.
class Record:
	var stars := 0
	var score := 0


	func _init(best_stars := 0, best_score := 0) -> void:
		stars = best_stars
		score = best_score


## Every level in campaign order.
static func levels() -> Array[LevelSpec]:
	var order: Array[LevelSpec] = []
	for chapter_spec in Content.chapters():
		order.append_array(chapter_levels(chapter_spec.id))
	return order


## The levels of chapter `chapter_id`, by index.
static func chapter_levels(chapter_id: String) -> Array[LevelSpec]:
	var found: Array[LevelSpec] = []
	found.assign(Content.levels().filter(func(level: LevelSpec) -> bool: return level.chapter == chapter_id))
	found.sort_custom(func(a: LevelSpec, b: LevelSpec) -> bool: return a.index < b.index)
	return found


## The stars a final `score` earns in `level`: how many of its thresholds it reaches.
static func stars(level: LevelSpec, score: int) -> int:
	var earned := 0
	for threshold in level.stars:
		if score >= threshold:
			earned += 1
	return earned


## Whether a level with `earned` stars is passed (at least one star).
static func is_passed(earned: int) -> bool:
	return earned >= 1


## The level after `level` in campaign order, or null after the last one.
static func next_level(level: LevelSpec) -> LevelSpec:
	var order := levels()
	var at := order.find(level)
	return order[at + 1] if at >= 0 and at + 1 < order.size() else null


## Whether `level` can be played with `progress` (level id -> Record): the first level
## always, any other once the level before it is passed.
static func is_unlocked(level: LevelSpec, progress: Dictionary[String, Record]) -> bool:
	var order := levels()
	var at := order.find(level)
	if at <= 0:
		return at == 0
	var before := order[at - 1]
	return progress.has(before.id) and is_passed(progress[before.id].stars)


## Whether chapter `chapter_id` is open: its level 1 is unlocked.
static func is_chapter_unlocked(chapter_id: String, progress: Dictionary[String, Record]) -> bool:
	var found := chapter_levels(chapter_id)
	return not found.is_empty() and is_unlocked(found[0], progress)


## The stars earned in chapter `chapter_id` (out of its levels x MAX_STARS).
static func chapter_stars(chapter_id: String, progress: Dictionary[String, Record]) -> int:
	var total := 0
	for level in chapter_levels(chapter_id):
		if progress.has(level.id):
			total += progress[level.id].stars
	return total


## `record` (null when the level was never finished) after a finish with `earned` stars and
## `score`: the best of each, so a replay never lowers either.
static func merge(record: Record, earned: int, score: int) -> Record:
	if record == null:
		return Record.new(earned, score)
	return Record.new(maxi(record.stars, earned), maxi(record.score, score))


## The highest score of `level` a player is sure to be able to reach: every bird but the
## decoy killed (a splitter's children too, right after it), in spawn order, the combo
## rising from x1 on every kill up to combo_cap and never broken (an armored bird's
## damaging hits score nothing and keep it), the decoy left alone. Every kill fits the
## wave's shells (Wave.hits_needed x shells_per_hit).
static func max_score(level: LevelSpec) -> int:
	var scoring := Scoring.new(level.combo_cap)
	for wave_index in range(1, level.waves + 1):
		for spawn in Wave.campaign(level, wave_index).spawns:
			var spec := Content.bird(spawn.bird_id)
			if spec.penalty > 0:
				continue
			scoring.hit(spec.points)
			for i in spec.split_count:
				scoring.hit(Content.bird(spec.splits_into).points)
	return scoring.score
