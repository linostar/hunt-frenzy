extends Node

const RED := Color(1, 0, 0)
const GREEN := Color("#00ff00")
const NAMED := Color.RED
const SOFT_WHITE := Color(1, 1, 1, 0.5)
var bytes := Color8(0, 255, 0)
var bytes_alpha := Color.from_rgba8(0, 0, 255, 128)
var hex_int := Color.hex(0x00ff00ff)
var hex_ctor := Color(0x0000ffff)
var html := Color.html("ff00ff")
var bare_hex := Color("00ffff")
var named_string := Color("red")
var hsv := Color.from_hsv(0.5, 1.0, 1.0)
var short_hex_int := Color(0xff0000)
var bad_hex_string := Color("#12345")
var too_bright := Color8(300, 0, 0)
