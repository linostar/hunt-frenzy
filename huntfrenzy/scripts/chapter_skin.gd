class_name ChapterSkin
extends RefCounted
## The campaign menus' chapter look, shared by the chapter select and the level select: a
## chapter's buttons wear its sky (art/chapter_<backdrop>_<state>.svg: the vertical sky
## gradient of its backdrop's sky layer, art/backdrops/<id>_sky.svg, inside the theme's
## ink-bordered button shape; hover and pressed add a gold inner ring, pressed sits lower)
## for the normal, hover, pressed and focus states (the theme's focus ring draws over it),
## with a label colour that reads on that sky (ink on the light dawn and noon skies, cream
## with an ink outline on the deeper sunset and night ones). A disabled (locked) button
## keeps its sky dimmed to DISABLED_ALPHA and its text faded. The small images the menus
## draw (stars, the lock, the boss skull) are TextureRects that ignore the pointer, so a
## touch, a click or the focus still reach the button under them. Palette colours only.

const STAR_FULL := preload("res://art/star_full.svg")
const STAR_EMPTY := preload("res://art/star_empty.svg")
const LOCK := preload("res://art/lock.svg")
const SKULL := preload("res://art/skull.svg")
## Where a backdrop's button skins are, by state ("normal", "hover", "pressed").
const SKIN_PATH := "res://art/chapter_%s_%s.svg"
## The skins' nine-patch margins (texture pixels: the corners and the borders stay sharp).
const SKIN_MARGIN := 16.0
## A locked button's sky and text alpha.
const DISABLED_ALPHA := 0.45
const INK := Color(0.122, 0.102, 0.18)
const CREAM := Color(0.984, 0.929, 0.804)
## The label colour per backdrop; cream labels get an ink outline of OUTLINE_SIZE.
const LABEL_COLORS: Dictionary[String, Color] = {
	"dawn": Color(0.122, 0.102, 0.18),
	"noon": Color(0.122, 0.102, 0.18),
	"sunset": Color(0.984, 0.929, 0.804),
	"night": Color(0.984, 0.929, 0.804),
}
const OUTLINE_SIZE := 6


## The label colour on backdrop `backdrop_id`'s sky (ink for one without an entry).
static func label_color(backdrop_id: String) -> Color:
	return LABEL_COLORS.get(backdrop_id, INK)


## Dresses `button` in backdrop `backdrop_id`'s sky with the label colour that reads on it;
## `content` is the text's margins (left, top, right, bottom), so the caption can sit above
## the images drawn under it. Returns false, leaving the theme's look, when a skin is missing
## (reported through Game.report_error with the file named).
static func apply(button: Button, backdrop_id: String, content: Vector4) -> bool:
	var styles: Dictionary[String, StyleBoxTexture] = {}
	for state: String in ["normal", "hover", "pressed"]:
		var path := SKIN_PATH % [backdrop_id, state]
		var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
		if texture == null:
			(button.get_node(GameState.AUTOLOAD_PATH) as GameState).report_error("Cannot dress the %s button: %s is missing or not a texture" % [backdrop_id, path])
			return false
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.set_texture_margin_all(SKIN_MARGIN)
		style.content_margin_left = content.x
		style.content_margin_top = content.y + (3.0 if state == "pressed" else 0.0)
		style.content_margin_right = content.z
		style.content_margin_bottom = content.w - (3.0 if state == "pressed" else 0.0)
		styles[state] = style
	var disabled := styles["normal"].duplicate() as StyleBoxTexture
	disabled.modulate_color = Color(1, 1, 1, DISABLED_ALPHA)
	button.add_theme_stylebox_override(&"normal", styles["normal"])
	button.add_theme_stylebox_override(&"hover", styles["hover"])
	button.add_theme_stylebox_override(&"pressed", styles["pressed"])
	button.add_theme_stylebox_override(&"hover_pressed", styles["pressed"])
	button.add_theme_stylebox_override(&"disabled", disabled)
	var color := label_color(backdrop_id)
	for slot: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_hover_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(slot, color)
	button.add_theme_color_override(&"font_disabled_color", Color(color, 0.7))
	if color == CREAM:
		button.add_theme_color_override(&"font_outline_color", INK)
		button.add_theme_constant_override(&"outline_size", OUTLINE_SIZE)
	return true


## A label in backdrop `backdrop_id`'s button colours (an outline where the caption has one).
static func label(text: String, backdrop_id: String, font_size: int) -> Label:
	var shown := Label.new()
	shown.text = text
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shown.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shown.theme_type_variation = &"HeadingLabel"
	shown.add_theme_font_size_override(&"font_size", font_size)
	var color := label_color(backdrop_id)
	shown.add_theme_color_override(&"font_color", color)
	shown.add_theme_constant_override(&"outline_size", OUTLINE_SIZE if color == CREAM else 0)
	return shown


## A `side`-square image of `texture` that ignores the pointer.
static func icon(texture: Texture2D, side: float, icon_name: String) -> TextureRect:
	var rect := TextureRect.new()
	rect.name = icon_name
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(side, side)
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


## A centred row along `button`'s lower part (from `top` to `bottom` above its bottom edge)
## for its images, ignoring the pointer.
static func detail_row(button: Button, top: float, bottom: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Detail"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 6)
	row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_top = -top
	row.offset_bottom = -bottom
	button.add_child(row)
	return row
