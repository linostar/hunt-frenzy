class_name Layout
## The base-unit layout tied to the art, shared by the play scene, the title and the tools:
## the base viewport, the HUD bar, the grass line, the birds' field and the rival's place on
## the bank. Constants, so the content checks (test_content's I11, I20) read them statically.
## play.tscn and title.tscn place the rival at RIVAL_RECT (test_gameplay checks both).

## The base viewport (project.godot display/window/size, which test_gameplay checks against
## it): the playfield is laid out in it and is never cropped (aspect expand only adds room).
const BASE_SIZE := Vector2(960, 540)
## The top bar of every screen (the HUD in play; the title's geese stay below it).
const HUD_BAR_HEIGHT := 56.0
## The grass line: the backdrop's grass is solid from here down (Play._fit places it so),
## birds rise from behind it, and a shot at or below it hits no bird (Play.bird_at).
const GRASS_Y := 440.0
## How far the grass tile's blade tips reach above the grass line (the tile's solid part
## starts this far below its top).
const GRASS_TIP := 24.0
## Where birds fly (World coordinates): below the HUD bar, above the grass line.
const FIELD := Rect2(0, HUD_BAR_HEIGHT, BASE_SIZE.x, GRASS_Y - HUD_BAR_HEIGHT)
## The rival's rect in World (the bottom-left of the bank, on the visible bottom at 16:9);
## his art fills it (80x120, svg scale 3).
const RIVAL_RECT := Rect2(16, 416, 80, 120)
## The gap between the rival's right edge and his speech bubble.
const BUBBLE_GAP := 8.0
