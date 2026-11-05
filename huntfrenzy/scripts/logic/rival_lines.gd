class_name RivalLines
extends Resource
## The rival hunter's timing and heckle lines from data/rival_lines.json. Built by Content
## (data/SCHEMA.md documents every field).

## Every heckle category, each with its own non-empty list of lines: a miss, a combo
## reaching x3 or more, a wave's end, a steal, and the results screen.
const CATEGORIES: Array[String] = ["miss", "combo", "wave_end", "steal", "results"]
## The rival aims for AIM_TIME_MIN..AIM_TIME_MAX seconds (main plan AC 17: a visible cue of
## at least 0.5 s), and waits 0..COOLDOWN_MAX seconds between heckles.
const AIM_TIME_MIN := 0.5
const AIM_TIME_MAX := 10.0
const COOLDOWN_MAX := 60.0
## The longest line: two lines of Play's speech bubble.
const LINE_MAX := 40

## Seconds the rival aims (the cue on the bird and on him) before he fires.
var aim_time := 0.0
## Seconds after a heckle before a miss, combo or wave-end line can show (steal lines skip it).
var cooldown := 0.0
## The lines of each category in CATEGORIES, in data order.
var lines: Dictionary[String, PackedStringArray] = {}
