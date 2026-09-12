extends BaseButton
## Native flight button material, with supplied glyphs and source touch geometry.
const HudSkin = preload("res://src/presentation/flight_hud_skin.gd")
var kind := "AUTOPILOT"
var factor := 1.0
var active := false
var touch_held := false
var availability := 1.0
var multiplier := 1
var texture_normal: Texture2D
var texture_pressed: Texture2D
var glyph: Texture2D
var art_layer: CanvasGroup


func _ready() -> void:
	art_layer = HudSkin.translucent_layer(self, paint)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	resized.connect(queue_redraw)
	if texture_normal != null and kind in ["boost", "weapon", "missiles"]:
		glyph = HudSkin.imported_glyph(texture_normal)


func set_touch_pressed(held: bool) -> void:
	# Non-toggle BaseButtons do not retain set_pressed_no_signal's value.
	# Track raw-touch feedback explicitly; native mouse presses still use is_pressed.
	touch_held = held
	set_pressed_no_signal(held)
	queue_redraw()


func _draw() -> void:
	if art_layer != null:
		HudSkin.redraw_layer(art_layer, HudSkin.PRESSED_OPACITY if active or touch_held or is_pressed() else HudSkin.IDLE_OPACITY)


func paint(canvas: Node2D) -> void:
	var center := size * .5 / factor
	var selected := active or touch_held or is_pressed()
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	if kind == "fire":
		HudSkin.fire(canvas, center, selected)
		canvas.draw_set_transform(Vector2.ZERO)
		return
	var radius := 17.0 if kind != "DOCK" else 19.0
	HudSkin.small_button(canvas, center, radius, selected, kind == "DOCK")
	var color := Color("ffd365") if kind == "DOCK" else HudSkin.CYAN
	if kind == "AUTOPILOT":
		# A straight navigation arrow aimed at a separate destination dot.
		HudSkin.disk(canvas, center + Vector2(6.5, -6.5), 3.0, Color("61def0"), Color("9beefa"), .55)
		var arrow := PackedVector2Array([
			Vector2(-9, 4.5), Vector2(-4.5, 9), Vector2(.3, 3),
			Vector2(2.5, 5.2), Vector2(3, -3), Vector2(-5.2, -2.5),
			Vector2(-3, -.3), Vector2(-9, 4.5)
		])
		for i in arrow.size(): arrow[i] += center
		canvas.draw_colored_polygon(arrow, Color("001924"))
		canvas.draw_polyline(arrow, Color("60d9ef"), 1.05, true)
	elif kind == "TIME":
		for x in [-7.5, -.5]:
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(x, -9), center + Vector2(x + 7, -3), center + Vector2(x, 3)
			]), color)
		HudSkin.text(canvas, "%dx" % multiplier, center + Vector2(0, 10), 8.5, factor, color, true)
	elif kind == "DOCK":
		for direction in [-1.0, 1.0]:
			canvas.draw_polyline(PackedVector2Array([
				center + Vector2(direction * 3, -9), center + Vector2(direction * 7, -9),
				center + Vector2(direction * 7, 1), center + Vector2(direction * 3, 1)
			]), color, 1.6, true)
		HudSkin.text(canvas, "DOCK", center + Vector2(0, 10), 6.5, factor, color, true)
	elif kind == "pause":
		for x in [-5.5, 1.0]:
			canvas.draw_rect(Rect2(center + Vector2(x, -7), Vector2(4.5, 14)), Color("6bc9e1"))
	elif glyph != null:
		# Readiness dims the glyph, leaving its position and circular rim legible.
		var ink := Color("35d5fd").lerp(Color("87ebf8"), .3 if selected else 0.0)
		ink = Color("38828f").lerp(ink, clampf(availability, 0, 1))
		canvas.draw_texture_rect(glyph, Rect2(center - Vector2(11.5, 11.5), Vector2(23, 23)), false, ink)
	canvas.draw_set_transform(Vector2.ZERO)
