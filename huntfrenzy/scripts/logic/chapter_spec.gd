class_name ChapterSpec
extends Resource
## One campaign chapter from data/chapters.json. Built by Content (data/SCHEMA.md documents
## every field). Chapters are in campaign order (dawn, noon, sunset, night); a bird's
## `chapter` names the one that introduces it.

var id := ""
var name := ""
## The id of the chapter's backdrop: its layers are res://art/backdrops/<id>_<layer>.svg
## (Content.backdrop_path, one per Content.BACKDROP_LAYERS).
var backdrop := ""
## The chapter's weather (one of Content.WEATHERS): drawn over the backdrop, visual only.
var weather := ""
## The music track the chapter's levels play: res://audio/music/<id>.mp3 (Content.music_path).
var music := ""
## The rival steals after a bird's linger_time x this (0 < scale <= 1, never larger than
## the chapter before's): he gets quicker chapter by chapter.
var rival_linger_scale := 1.0
