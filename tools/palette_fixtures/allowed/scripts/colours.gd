extends Node

const INK := Color(0.122, 0.102, 0.18)
const ORANGE := Color("#f08a2480")
const CLEAR := Color.TRANSPARENT
const IDENTITY := Color.WHITE
const FADED := Color(1, 1, 1, 0)
const NOT_A_COLOUR := "#12345"
var bytes := Color8(255, 255, 255)
var bytes_alpha := Color.from_rgba8(240, 138, 36, 128)
var hex_int := Color.hex(0x1f1a2eff)
var hex_ctor := Color(0xf08a2480)
var html := Color.html("f08a24")
var bare_hex := Color("ffffff80")
var named_string := Color("white")
var not_a_colour_call := Color.html_is_valid("f08a24")
