class_name Palette
extends RefCounted
## The palette colours scripts draw with, each once, by name (from art/palette.hex, which
## tools/check_palette.gd holds every literal here to). Scripts use these names, never a
## Color literal of their own. Scenes, the Theme and project.godot cannot reference a
## script, so they keep their literals (the same check covers them).

const WHITE := Color(1, 1, 1)
## The art's ink outline, and the darkest ink (overlay dims).
const INK := Color(0.122, 0.102, 0.18)
const INK_DEEP := Color(0.067, 0.059, 0.094)
const CREAM := Color(0.984, 0.929, 0.804)
const PALE_GOLD := Color(1, 0.929, 0.6)
const GOLD := Color(0.949, 0.714, 0.196)
const GOLD_DARK := Color(0.788, 0.541, 0.118)
const PEACH := Color(1, 0.824, 0.659)
const CORAL := Color(1, 0.451, 0.4)
const LILAC := Color(0.788, 0.714, 0.894)
const VIOLET := Color(0.557, 0.424, 0.722)
const PERIWINKLE := Color(0.553, 0.592, 0.839)
const TEAL := Color(0.247, 0.655, 0.627)
const MINT := Color(0.561, 0.847, 0.784)
const LEAF := Color(0.651, 0.788, 0.431)
## The marsh grass, light to dark.
const GRASS_LIGHT := Color(0.435, 0.624, 0.29)
const GRASS := Color(0.29, 0.478, 0.227)
const GRASS_DARK := Color(0.18, 0.29, 0.227)
## The goose's plumage, light to dark.
const TAN := Color(0.722, 0.647, 0.549)
const BROWN := Color(0.541, 0.459, 0.376)
const BROWN_DARK := Color(0.369, 0.302, 0.243)
## The armored goose's steel, light to dark.
const STEEL_LIGHT := Color(0.722, 0.769, 0.816)
const STEEL := Color(0.435, 0.498, 0.58)
const STEEL_DARK := Color(0.31, 0.365, 0.447)
