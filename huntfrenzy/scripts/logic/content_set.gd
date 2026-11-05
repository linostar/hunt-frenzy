class_name ContentSet
extends RefCounted
## What one content load built: every spec by id, in data order, and the rival's lines.
## The file validators fill it in Content.FILES order, each reading what the earlier ones
## built (a bird's chapter, a mix's birds); Content keeps the last one.

var chapters: Dictionary[String, ChapterSpec] = {}
var birds: Dictionary[String, BirdSpec] = {}
var modes: Dictionary[String, ModeSpec] = {}
var levels: Dictionary[String, LevelSpec] = {}
var rival_lines := RivalLines.new()
## Ids of the birds whose flee_time or linger_time failed, and of the chapters whose
## rival_linger_scale failed, which I13 (RivalLinesFile.check_linger) skips.
var bad_timing: Dictionary[String, bool] = {}
var bad_scale: Dictionary[String, bool] = {}
