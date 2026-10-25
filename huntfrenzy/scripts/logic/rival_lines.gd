class_name RivalLines
extends Resource
## The rival hunter's timing and heckle lines from data/rival_lines.json. Built by Content
## (data/SCHEMA.md documents every field).

## Every heckle category, each with its own non-empty list of lines: a miss, a combo
## reaching x3 or more, a wave's end, a steal, and the results screen.
const CATEGORIES: Array[String] = ["miss", "combo", "wave_end", "steal", "results"]

## Seconds the rival aims (the cue on the bird and on him) before he fires.
var aim_time := 0.0
## Seconds after a heckle before a miss, combo or wave-end line can show (steal lines skip it).
var cooldown := 0.0
## The lines of each category in CATEGORIES, in data order.
var lines: Dictionary[String, PackedStringArray] = {}
