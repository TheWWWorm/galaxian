extends Control
## Small visible track, generous independent touch region, and actual speed only.
const HudSkin = preload("res://src/presentation/flight_hud_skin.gd")
const MOCK_TRACK_SIZE := Vector2(8, 70)
const TRACK_SIZE := Vector2(9, MOCK_TRACK_SIZE.y * .7)
const HIT_WIDTH := 28.0
const CAPTION_SCALE := .7
var flight
var factor := 1.0
var track_rect := Rect2()
var touch_rect := Rect2()
var speed_text := "0 m/s"
var track_style := StyleBoxFlat.new()
var handle_style := StyleBoxFlat.new()


func _ready() -> void:
	# HUD owns fingers; an invisible Control must never eat a camera drag.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_style.bg_color = Color("14413c66")
	track_style.border_color = Color("509aa599")
	track_style.anti_aliasing = true
	handle_style.bg_color = Color(.12, .44, .48, .65)
	handle_style.border_color = Color(.22, .75, .84, .7)
	handle_style.anti_aliasing = true


func layout(scale: float) -> void:
	factor = scale
	var height: float = flight.library.radio_glyphs().values()[0].size.y
	size = Vector2(HIT_WIDTH, TRACK_SIZE.y + 5 + height * CAPTION_SCALE) * factor
	track_rect = Rect2(Vector2(size.x - TRACK_SIZE.x * factor, 0), TRACK_SIZE * factor)
	touch_rect = Rect2(Vector2.ZERO, Vector2(size.x, track_rect.size.y))
	for style in [track_style, handle_style]:
		style.set_border_width_all(maxi(1, roundi(factor * .65)))
		style.set_corner_radius_all(maxi(1, roundi(factor * 1.7)))
	queue_redraw()


func value_at(local_point: Vector2) -> float:
	var inset := 2.5 * factor
	return clampf(1.0 - (local_point.y - track_rect.position.y - inset) / maxf(track_rect.size.y - inset * 2, 1), 0, 1)


func set_throttle_at(global_point: Vector2) -> void:
	flight.set_touch_throttle(value_at(get_global_transform().affine_inverse() * global_point))
	refresh()


func refresh() -> void:
	speed_text = "%d m/s" % roundi(flight.speed)
	queue_redraw()


func _draw() -> void:
	if flight == null or track_rect.size.y <= 0:
		return
	draw_style_box(track_style, track_rect)
	var inset := 2.5 * factor
	var y := track_rect.position.y + inset + (1.0 - float(flight.throttle)) * (track_rect.size.y - inset * 2)
	var handle := Rect2(Vector2(track_rect.position.x - factor, y - inset), Vector2(track_rect.size.x + factor * 2, inset * 2))
	draw_style_box(handle_style, handle)
	draw_line(handle.position + Vector2(2, 2.5) * factor, handle.end - Vector2(2, 2.5) * factor, Color(0, .25, .3), maxf(1, factor), true)
	if not flight.settings.get("flight_overlays", true):
		return
	var pixels := maxi(8, roundi(7.5 * factor))
	var width := ThemeDB.fallback_font.get_string_size(speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
	var text_at := Vector2(size.x - width, (TRACK_SIZE.y + 12) * factor)
	draw_string(ThemeDB.fallback_font, text_at, speed_text, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, HudSkin.PALE)
