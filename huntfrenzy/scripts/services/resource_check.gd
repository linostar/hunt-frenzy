class_name ResourceCheck
## Static checks that a resource's files are all there before anything is loaded: the files a
## scene needs (missing_dependencies, used by SceneFlow.goto) and the UI theme with its fonts
## (theme_problems, checked at start by GameState.check_ui_theme). Each problem names the file.

## The project setting naming the UI theme every scene uses.
const THEME_SETTING := "gui/theme/custom"


## What is wrong with the UI theme at `path` (empty when nothing is): no theme set, no such
## file, a file it needs (a font) missing (checked before loading, so the loader is never
## asked for it), a file that is no Theme, or a font the theme uses that is missing or
## holds no font data. Each problem names the file. Public for tests.
static func theme_problems(path: String) -> Array[String]:
	var problems: Array[String] = []
	if path == "":
		problems.append("No UI theme is set (project.godot %s)" % THEME_SETTING)
		return problems
	if not ResourceLoader.exists(path):
		problems.append("UI theme '%s' does not exist" % path)
		return problems
	for missing in missing_dependencies(path):
		problems.append("UI theme '%s' needs '%s', which is missing" % [path, missing])
	if not problems.is_empty():
		return problems
	var theme := load(path) as Theme
	if theme == null:
		problems.append("UI theme '%s' cannot be loaded as a Theme" % path)
		return problems
	return font_problems(theme, path)


## The fonts of `theme` (its default font and every type's fonts, through FontVariation
## bases) that are missing or hold no font data, named by where the theme uses them.
static func font_problems(theme: Theme, path: String) -> Array[String]:
	var problems: Array[String] = []
	for where in _theme_fonts(theme):
		var font := _font_file(_theme_fonts(theme)[where])
		if font == null:
			problems.append("UI theme '%s': %s has no font file" % [path, where])
		elif font is FontFile and (font as FontFile).data.is_empty():
			problems.append("UI theme '%s': %s font '%s' holds no font data" % [path, where, font.resource_path])
	return problems


## The font files `theme` uses (for the log).
static func theme_font_files(theme: Theme) -> PackedStringArray:
	var files := PackedStringArray()
	for font: Font in _theme_fonts(theme).values():
		var file := _font_file(font)
		if file != null and not file.resource_path.get_file() in files:
			files.append(file.resource_path.get_file())
	return files


## "default_font" and "<Type>/fonts/<name>" -> the font the theme holds there.
static func _theme_fonts(theme: Theme) -> Dictionary[String, Font]:
	var fonts: Dictionary[String, Font] = {"default_font": theme.default_font}
	for type in theme.get_font_type_list():
		for font_name in theme.get_font_list(type):
			fonts["%s/fonts/%s" % [type, font_name]] = theme.get_font(font_name, type)
	return fonts


## The font file under `font` (through FontVariation bases), or null.
static func _font_file(font: Font) -> Font:
	while font is FontVariation:
		font = (font as FontVariation).base_font
	return font


## The files the resource at `path` needs, directly or through the files it needs, that do
## not exist (read from the files' dependency lists, nothing is loaded).
static func missing_dependencies(path: String, seen: Dictionary[String, bool] = {}) -> PackedStringArray:
	var missing := PackedStringArray()
	seen[path] = true
	for entry in ResourceLoader.get_dependencies(path):
		var dependency := ""
		for part in entry.split("::"):
			if part.begins_with("res://"):
				dependency = part
		if dependency == "" and entry.begins_with("uid://"):
			var id := ResourceUID.text_to_id(entry.get_slice("::", 0))
			dependency = ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else entry.get_slice("::", 0)
		if dependency == "" or seen.has(dependency):
			continue
		if not ResourceLoader.exists(dependency):
			missing.append(dependency)
		else:
			missing.append_array(missing_dependencies(dependency, seen))
	return missing
