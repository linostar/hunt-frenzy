class_name ChapterSpec
extends Resource
## One campaign chapter from data/chapters.json. Built by Content (data/SCHEMA.md documents
## every field). Chapters are in campaign order (dawn, noon, sunset, night); a bird's
## `chapter` names the one that introduces it.

var id := ""
var name := ""
## The placeholder tint of the play scene's sky (the art pass replaces it with a backdrop).
var sky_tint := Color.WHITE
## The chapter's weather (one of Content.WEATHERS); logged until the art pass draws it.
var weather := ""
## The rival steals after a bird's linger_time x this (0 < scale <= 1, never larger than
## the chapter before's): he gets quicker chapter by chapter.
var rival_linger_scale := 1.0
