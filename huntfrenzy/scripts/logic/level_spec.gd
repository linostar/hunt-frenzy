class_name LevelSpec
extends Resource
## One campaign level from data/levels.json. Built by Content (data/SCHEMA.md documents
## every field). A level's waves are a pure function of its fields (Wave.campaign): its
## fixed seed makes every play of it meet the same birds.


## The boss flock that is the last wave of a chapter's last level (index 6): more birds,
## a shorter spawn interval and a higher speed than every other wave of the chapter.
class Boss:
	var birds := 0
	var spawn_interval := 0.0
	var speed_scale := 1.0
	## The flock's mix (ModeSpec.Entry with from_wave 1), weighted toward the chapter's bird.
	var mix: Array[ModeSpec.Entry] = []


var id := ""
## The chapter's id (a ChapterSpec) and the level's place in it, 1..Content.LEVELS_PER_CHAPTER.
var chapter := ""
var index := 0
## The fixed seed (levels.json `seed`) of every wave's schedule and of the rival's line picks.
var level_seed := 0
## Waves played, the last one the boss flock on a boss level; birds per (non-boss) wave.
var waves := 0
var wave_birds := 0
## The wave mix (ModeSpec.Entry: bird and weight; from_wave is always 1).
var mix: Array[ModeSpec.Entry] = []
## The bird a spawn slot turns into with golden_chance (every wave, the boss flock too).
var golden_bird := ""
var golden_chance := 0.0
## Speed scale and seconds between spawns of every non-boss wave.
var speed_scale := 1.0
var spawn_interval := 0.0
## Shells per hit a wave needs (Wave.hits_needed), and the highest combo multiplier.
var shells_per_hit := 0
var combo_cap := 0
## The final scores that earn 1, 2 and 3 stars, strictly ascending.
var stars: Array[int] = []
## The boss flock (index 6 only), else null.
var boss: Boss = null


## True on the chapter's boss level.
func is_boss() -> bool:
	return boss != null
