class_name HitPopup
extends Label
## A pop-up over a hit (World/Popups): its text in the theme's PopupLabel (PenaltyPopupLabel
## for a penalty), centred on the hit and moved in so it stays inside the visible area at its
## largest, the rise included. SCORE and DAMAGE bounce in, COMBO bounces in larger by the
## multiplier, PENALTY shakes; all rise Play.TUNING.popup_rise and fade over
## Play.TUNING.popup_time, then free themselves. With reduce motion they only rise and fade (a
## combo one keeps its size).

enum Kind { SCORE, DAMAGE, COMBO, PENALTY }

var kind := Kind.SCORE
## The scale it settles at (1, or larger for a combo).
var rest_scale := 1.0


## Adds a pop-up of `label_text` to `parent` at `point` (`parent`'s coordinates), kept inside `shown`
## (the visible area in the same coordinates), and starts its motion (`still`: reduce motion).
static func spawn(parent: Node2D, point: Vector2, label_text: String, popup_kind: Kind, multiplier: int, shown: Rect2, still: bool) -> HitPopup:
	var popup := HitPopup.new()
	popup.text = label_text
	popup.kind = popup_kind
	popup.theme_type_variation = &"PenaltyPopupLabel" if popup_kind == Kind.PENALTY else &"PopupLabel"
	var tuning := Play.TUNING
	popup.rest_scale = minf(1.0 + tuning.popup_combo_growth * (multiplier - 1), tuning.popup_combo_scale_max) if popup_kind == Kind.COMBO else 1.0
	parent.add_child(popup)
	popup._place(point, shown, still)
	popup._animate(still)
	return popup


## Centres it on `point`, moved in so its largest size (and the shake) stays inside `shown`,
## the rise included.
func _place(point: Vector2, shown: Rect2, still: bool) -> void:
	var tuning := Play.TUNING
	var text_size := get_combined_minimum_size()
	var largest := rest_scale * (tuning.popup_bounce_scale if not still and kind != Kind.PENALTY else 1.0)
	var half := text_size * largest / 2.0 + Vector2(tuning.popup_shake, 0.0)
	var centre := Vector2(clampf(point.x, shown.position.x + half.x, shown.end.x - half.x), clampf(point.y, shown.position.y + half.y + tuning.popup_rise, shown.end.y - half.y))
	pivot_offset = text_size / 2.0
	position = centre - text_size / 2.0
	scale = Vector2.ONE * rest_scale


## Rises and fades, then frees itself; unless `still`, a penalty shakes and the others bounce in.
func _animate(still: bool) -> void:
	var tuning := Play.TUNING
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "position:y", position.y - tuning.popup_rise, tuning.popup_time)
	tween.tween_property(self, "modulate:a", 0.0, tuning.popup_time)
	if not still:
		if kind == Kind.PENALTY:
			_shake()
		else:
			_bounce()
	tween.chain().tween_callback(queue_free)


## Swings side to side popup_shakes times over popup_shake_time, back to where it started.
func _shake() -> void:
	var tuning := Play.TUNING
	var wiggle := create_tween()
	var x := position.x
	var step := tuning.popup_shake_time / (tuning.popup_shakes + 1)
	for i in tuning.popup_shakes:
		wiggle.tween_property(self, "position:x", x + (tuning.popup_shake if i % 2 == 0 else -tuning.popup_shake), step)
	wiggle.tween_property(self, "position:x", x, step)


## Grows from half its size past it to popup_bounce_scale and settles over popup_bounce_time.
func _bounce() -> void:
	var tuning := Play.TUNING
	scale = Vector2.ONE * rest_scale * 0.5
	var bounce := create_tween()
	bounce.tween_property(self, "scale", Vector2.ONE * rest_scale * tuning.popup_bounce_scale, tuning.popup_bounce_time / 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bounce.tween_property(self, "scale", Vector2.ONE * rest_scale, tuning.popup_bounce_time / 2.0).set_trans(Tween.TRANS_SINE)
