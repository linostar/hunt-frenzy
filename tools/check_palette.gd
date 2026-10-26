extends SceneTree
## Palette gate: every colour the game draws comes from art/palette.hex.
## - art/palette.hex holds at most PALETTE_MAX colours, one lowercase "rrggbb" per line,
##   no duplicates,
## - every colour in an SVG (fill, stroke, stop-color, flood-color, lighting-color and
##   color, as attributes or in style/CSS text, gradient stops included; written as
##   #rgb, #rgba, #rrggbb, #rrggbbaa, rgb(), rgba() or a CSS colour name),
## - every Color literal in a script, scene, resource (the UI Theme) or project.godot:
##   Color(r, g, b[, a]), a PackedColorArray, a Color.NAMED constant and every "#hex"
##   string,
## is one of the palette's colours; only the alpha may differ. "none", "transparent",
## "currentColor", "inherit" and url(#...) references are not colours.
## Usage (from repo root): "$GODOT" --headless --path huntfrenzy --script "$PWD/tools/check_palette.gd"
## Prints "check_palette: OK" on success; exits 1 and prints every violation otherwise,
## each naming the file, the line and the colour as written.
##
## Limits: this is a text scan, line by line. It does not see colours built at runtime
## (Color.from_hsv, a colour computed from numbers, a Color("name") string, a modulate
## multiplying two palette colours) or a literal split across lines.

const PALETTE_PATH := "res://art/palette.hex"
const PALETTE_MAX := 40
const SCANNED_EXTENSIONS: Array[String] = ["svg", "gd", "tscn", "tres"]
const PROJECT_FILE := "res://project.godot"
## SVG colour properties, as an attribute (fill="#fff") or in CSS text (fill: #fff).
const SVG_ATTRIBUTE_PATTERN := "\\b(fill|stroke|stop-color|flood-color|lighting-color|color)\\s*=\\s*[\"']([^\"']*)[\"']"
const SVG_CSS_PATTERN := "\\b(fill|stroke|stop-color|flood-color|lighting-color|color)\\s*:\\s*([^;\"'}]+)"
const COLOR_LITERAL_PATTERN := "\\bColor\\(\\s*([-+0-9.eE]+)\\s*,\\s*([-+0-9.eE]+)\\s*,\\s*([-+0-9.eE]+)\\s*(?:,\\s*([-+0-9.eE]+)\\s*)?\\)"
const PACKED_COLORS_PATTERN := "\\bPackedColorArray\\(([^)]*)\\)"
const COLOR_CONSTANT_PATTERN := "\\bColor\\.([A-Z][A-Z0-9_]*)\\b"
const HEX_STRING_PATTERN := "[\"']#([0-9a-fA-F]+)[\"']"
const RGB_PATTERN := "^rgba?\\(([^)]*)\\)$"
## Values that are not colours.
const NOT_COLOURS: Array[String] = ["none", "transparent", "currentcolor", "inherit"]
## The CSS colour names (CSS Color Module Level 4), which SVG renderers use.
const CSS_NAMES := "aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 black 000000 blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b darkmagenta 8b008b darkolivegreen 556b2f darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 floralwhite fffaf0 forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f grey 808080 honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd lightblue add8e6 lightcoral f08080 lightcyan e0ffff lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585 midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 navajowhite ffdead navy 000080 oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa palegreen 98fb98 paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 red ff0000 rosybrown bc8f8f royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee sienna a0522d silver c0c0c0 skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 turquoise 40e0d0 violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32"

var _violations: Array[String] = []
## The palette: "rrggbb" -> its line in palette.hex.
var _palette: Dictionary[String, int] = {}
var _css_names: Dictionary[String, String] = {}
var _colours_checked := 0
var _svg_attribute := RegEx.create_from_string(SVG_ATTRIBUTE_PATTERN)
var _svg_css := RegEx.create_from_string(SVG_CSS_PATTERN)
var _color_literal := RegEx.create_from_string(COLOR_LITERAL_PATTERN)
var _packed_colors := RegEx.create_from_string(PACKED_COLORS_PATTERN)
var _color_constant := RegEx.create_from_string(COLOR_CONSTANT_PATTERN)
var _hex_string := RegEx.create_from_string(HEX_STRING_PATTERN)
var _rgb := RegEx.create_from_string(RGB_PATTERN)
var _palette_line := RegEx.create_from_string("^[0-9a-f]{6}$")


func _initialize() -> void:
	var words := CSS_NAMES.split(" ")
	for i in range(0, words.size(), 2):
		_css_names[words[i]] = words[i + 1]
	_load_palette()
	var files: Array[String] = []
	_collect_files("res://", files)
	if FileAccess.file_exists(PROJECT_FILE):
		files.append(PROJECT_FILE)
	for path in files:
		_check_file(path)
	if _violations.is_empty():
		print("check_palette: OK (%d colours in the palette, %d colours checked in %d files)" % [_palette.size(), _colours_checked, files.size()])
		quit(0)
		return
	for violation in _violations:
		printerr("check_palette: " + violation)
	printerr("check_palette: FAILED with %d violation(s)" % _violations.size())
	quit(1)


## Reads palette.hex: one lowercase rrggbb per line, no duplicates, at most PALETTE_MAX.
func _load_palette() -> void:
	var text := FileAccess.get_file_as_string(PALETTE_PATH)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_violations.append("%s: cannot be read (%s)" % [_short(PALETTE_PATH), error_string(FileAccess.get_open_error())])
		return
	var lines := text.split("\n")
	# A final newline leaves one empty last line; any other empty line is a problem.
	if lines.size() > 1 and lines[lines.size() - 1] == "":
		lines.resize(lines.size() - 1)
	for i in lines.size():
		var line := lines[i]
		if _palette_line.search(line) == null:
			_violations.append("%s:%d: '%s' is not a colour (one lowercase rrggbb per line)" % [_short(PALETTE_PATH), i + 1, line])
			continue
		if _palette.has(line):
			_violations.append("%s:%d: %s is already on line %d" % [_short(PALETTE_PATH), i + 1, line, _palette[line]])
			continue
		_palette[line] = i + 1
	if _palette.size() > PALETTE_MAX:
		_violations.append("%s: %d colours, at most %d" % [_short(PALETTE_PATH), _palette.size(), PALETTE_MAX])


func _check_file(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		_violations.append("%s: cannot be read (%s)" % [_short(path), error_string(FileAccess.get_open_error())])
		return
	var lines := text.split("\n")
	for i in lines.size():
		if path.get_extension() == "svg":
			_check_svg_line(path, i + 1, lines[i])
		else:
			_check_code_line(path, i + 1, lines[i])


func _check_svg_line(path: String, line_number: int, line: String) -> void:
	for regex: RegEx in [_svg_attribute, _svg_css]:
		for found in regex.search_all(line):
			var value := found.get_string(2).strip_edges()
			# url(#gradient) may carry a fallback colour after it.
			if value.begins_with("url("):
				value = value.substr(value.find(")") + 1).strip_edges()
				if value.is_empty():
					continue
			if value.to_lower() in NOT_COLOURS:
				continue
			_check_colour(path, line_number, "%s '%s'" % [found.get_string(1), value], _svg_colour(value))


## The "rrggbb" of an SVG colour value, or "" when it is not one this check reads.
func _svg_colour(value: String) -> String:
	var lower := value.to_lower()
	if lower.begins_with("#"):
		return _hex_rgb(lower.substr(1))
	if _css_names.has(lower):
		return _css_names[lower]
	var rgb := _rgb.search(lower)
	if rgb == null:
		return ""
	var parts := rgb.get_string(1).split(",")
	if parts.size() < 3 or parts.size() > 4:
		return ""
	var channels: Array[int] = []
	for i in 3:
		var part := parts[i].strip_edges()
		var number := part.trim_suffix("%")
		if not number.is_valid_float():
			return ""
		channels.append(roundi(number.to_float() * 2.55) if part.ends_with("%") else roundi(number.to_float()))
	return _channels_hex(channels)


func _check_code_line(path: String, line_number: int, line: String) -> void:
	for found in _color_literal.search_all(line):
		var channels: Array[int] = []
		for i in range(1, 4):
			channels.append(roundi(found.get_string(i).to_float() * 255.0))
		_check_colour(path, line_number, "'%s'" % found.get_string(), _channels_hex(channels))
	for found in _packed_colors.search_all(line):
		var numbers := PackedStringArray()
		for number in found.get_string(1).split(",", false):
			numbers.append(number.strip_edges())
		# Four numbers per colour (r, g, b, a).
		for colour_index in floori(numbers.size() / 4.0):
			var start := colour_index * 4
			var channels: Array[int] = []
			for i in 3:
				channels.append(roundi(numbers[start + i].to_float() * 255.0))
			_check_colour(path, line_number, "PackedColorArray colour %d '%s'" % [colour_index + 1, ", ".join(numbers.slice(start, start + 4))], _channels_hex(channels))
	for found in _color_constant.search_all(line):
		var colour := Color.from_string(found.get_string(1), Color(-1, -1, -1, -1))
		if colour.r < 0.0:
			continue
		_check_colour(path, line_number, "'%s'" % found.get_string(), colour.to_html(false))
	for found in _hex_string.search_all(line):
		var digits := found.get_string(1)
		if not digits.length() in [3, 4, 6, 8]:
			continue
		_check_colour(path, line_number, "'#%s'" % digits, _hex_rgb(digits.to_lower()))


## "rrggbb" from 3, 4, 6 or 8 lowercase hex digits (the alpha is dropped), or "".
func _hex_rgb(digits: String) -> String:
	if not digits.is_valid_hex_number():
		return ""
	match digits.length():
		3, 4:
			return "%s%s%s%s%s%s" % [digits[0], digits[0], digits[1], digits[1], digits[2], digits[2]]
		6, 8:
			return digits.substr(0, 6)
	return ""


func _channels_hex(channels: Array[int]) -> String:
	for channel in channels:
		if channel < 0 or channel > 255:
			return "out of range"
	return "%02x%02x%02x" % [channels[0], channels[1], channels[2]]


func _check_colour(path: String, line_number: int, what: String, rgb: String) -> void:
	_colours_checked += 1
	if rgb == "":
		_violations.append("%s:%d: %s is not a colour this check reads (use #rrggbb from %s)" % [_short(path), line_number, what, _short(PALETTE_PATH)])
	elif not _palette.has(rgb):
		_violations.append("%s:%d: %s (#%s) is not in %s" % [_short(path), line_number, what, rgb, _short(PALETTE_PATH)])


## "art/goose.svg" for "res://art/goose.svg".
func _short(path: String) -> String:
	return path.trim_prefix("res://")


func _collect_files(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_violations.append("%s: cannot open directory (%s)" % [dir_path, error_string(DirAccess.get_open_error())])
		return
	for file in dir.get_files():
		if file.get_extension() in SCANNED_EXTENSIONS:
			out.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		# A .gdignore keeps a directory out of the project, as in Godot's import.
		if not sub.begins_with(".") and not FileAccess.file_exists(dir_path.path_join(sub).path_join(".gdignore")):
			_collect_files(dir_path.path_join(sub), out)
