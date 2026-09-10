extends Control
## Original title artwork with native, accessible buttons and owner-defined actions.
signal action_requested(action: String)
const Combat = preload("res://src/simulation/combat.gd")
var library
var data: Dictionary
var art := {}
var canvas: Control
var font: FontFile
var buttons: Array[Button] = []
var footer: Button
var section := "main"
var shade := 0.0
var factor := 1.0
var origin := Vector2.ZERO
var indicator_pitch := 0.0


static func valid_data(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("images") is Dictionary
		or not value.get("labels") is Dictionary
	):
		return false
	for key in [
		"logo",
		"pattern",
		"edge",
		"side",
		"ring_large",
		"ring_medium",
		"ring_small",
		"marker",
		"idle",
		"selected",
		"indicator",
		"indicator_end"
	]:
		var binding: Variant = value.images.get(key)
		if (
			not binding is Dictionary
			or not Combat.integer(binding.get("texture"))
			or not Combat.integer(binding.get("region"))
			or binding.texture < 0
			or binding.region < 0
		):
			return false
	if (
		not value.get("indicator_frames") is Array
		or value.indicator_frames.size() < 6
		or value.indicator_frames.size() > 32
	):
		return false
	for binding in value.indicator_frames:
		if (
			not binding is Dictionary
			or not Combat.integer(binding.get("texture"))
			or not Combat.integer(binding.get("region"))
			or binding.texture < 0
			or binding.region < 0
		):
			return false
	for key in ["start", "load", "options", "help", "more_games"]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	if not value.get("row_starts") is Array or value.row_starts.size() != 6:
		return false
	for number in value.row_starts:
		if not Combat.number(number) or number < 0 or number > 320:
			return false
	for key in [
		"row_step",
		"text_y",
		"logo_y",
		"shade_initial",
		"shade_floor",
		"shade_rate",
		"indicator_count",
		"title_rows"
	]:
		if not Combat.number(value.get(key)) or value[key] < 0 or value[key] > 1000:
			return false
	if (
		value.row_step <= 0
		or value.shade_rate <= 0
		or value.shade_initial > 255
		or value.shade_floor > value.shade_initial
		or not Combat.integer(value.indicator_count)
		or value.indicator_count > 64
		or value.title_rows != 5
	):
		return false
	for key in [
		"side_origin", "marker_origin", "indicator_origin", "indicator_column", "indicator_end"
	]:
		if not pair(value.get(key)):
			return false
	if (
		not value.get("ring_origins") is Array
		or value.ring_origins.size() != 3
		or not value.ring_origins.all(pair)
	):
		return false
	return (
		value.get("pattern_tint") is Array
		and value.pattern_tint.size() == 4
		and value.pattern_tint.all(func(v): return Combat.number(v) and v >= 0 and v <= 255)
	)


static func pair(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 2
		and value.all(func(v): return Combat.number(v) and absf(v) <= 1000)
	)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(layout_canvas)


func configure(source) -> void:
	library = source
	data = library.content.title_ui
	shade = float(data.shade_initial)
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in data.images:
		art[key] = library.ui_image(data.images[key])
		art[key].filter_clip = true
	for binding in data.indicator_frames:
		indicator_pitch = maxf(indicator_pitch, library.ui_image(binding).get_height())
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	layout_canvas()


func present(
	page: String, entries: Array, back_caption: String, back_action: String, body: String = ""
) -> void:
	section = page
	for child in canvas.get_children():
		canvas.remove_child(child)
		child.queue_free()
	buttons.clear()
	var start := float(data.row_starts[clampi(entries.size() - 1, 0, data.row_starts.size() - 1)])
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var button := make_button(str(entry.text), str(entry.action), art.idle, art.selected)
		button.position = Vector2((480 - art.idle.get_width()) * .5, start + index * data.row_step)
		button.size = art.idle.get_size()
		button.disabled = not bool(entry.get("enabled", true))
		button.tooltip_text = str(entry.get("hint", ""))
		buttons.append(button)
	var declaration: Dictionary = library.content.briefing_ui.footer
	footer = make_button(
		back_caption,
		back_action,
		library.ui_image(declaration.normal),
		library.ui_image(declaration.pressed)
	)
	footer.position = Vector2(declaration.margin, declaration.y)
	footer.size = library.ui_image(declaration.normal).get_size()
	if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
		# Keep Back/Exit at the left and lift it clear of the original lower rim.
		footer.position.y -= 20
	if not body.is_empty():
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(38, 112)
		scroll.size = Vector2(404, 162)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		canvas.add_child(scroll)
		var label := Label.new()
		label.text = body
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 388
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		scroll.add_child(label)
		var touch = preload("res://src/input/touch_scroll.gd").new()
		touch.scroll = scroll
		scroll.add_child(touch)
	for button in buttons:
		if not button.disabled:
			button.grab_focus()
			break
	if buttons.all(func(button): return button.disabled):
		footer.grab_focus()
	layout_canvas()


func make_button(text: String, action: String, idle: Texture2D, selected: Texture2D) -> Button:
	var result := Button.new()
	result.text = text
	result.add_theme_font_override("font", font)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
	# Long localized/new captions fit their original atlas button, not a new box.
	var text_size := minf(
		int(font.get_meta("source_height")), int(font.get_meta("source_height")) * (idle.get_width() - 12) / maxf(1, text_width)
	)
	result.add_theme_font_size_override("font_size", maxi(7, int(floor(text_size))))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = idle if state in ["normal", "disabled"] else selected
		style.content_margin_left = 0
		style.content_margin_right = 0
		style.content_margin_top = float(data.text_y)
		style.content_margin_bottom = maxf(0, idle.get_height() - data.text_y - int(font.get_meta("source_height")))
		if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
			style.content_margin_top = 0
			style.content_margin_bottom = 0
		result.add_theme_stylebox_override(state, style)
		result.add_theme_color_override(
			"font_" + state + "_color", Color(1, 1, 1, .4) if state == "disabled" else Color.WHITE
		)
	result.add_theme_color_override("font_color", Color.WHITE)
	result.pressed.connect(
		func():
			if is_visible_in_tree():
				action_requested.emit(action)
	)
	canvas.add_child(result)
	return result


func layout_canvas() -> void:
	if canvas == null:
		return
	factor = preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	origin = (size - Vector2(480, 320) * factor) * .5
	canvas.position = origin
	canvas.scale = Vector2.ONE * factor
	canvas.size = Vector2(480, 320)
	queue_redraw()


func _process(seconds: float) -> void:
	if not data.is_empty() and shade > data.shade_floor:
		shade = maxf(data.shade_floor, shade - seconds * data.shade_rate)
		queue_redraw()


func stamp(key: String, at: Vector2, flip := Vector2.ONE) -> void:
	var texture: Texture2D = art[key]
	# Source decorations may extend past its viewport. Clip to that viewport,
	# including when the native canvas is centered in a portrait window.
	var clipped := Rect2(at, texture.get_size()).intersection(Rect2(Vector2.ZERO, canvas.size))
	if not clipped.has_area():
		return
	var source := Rect2(clipped.position - at, clipped.size)
	if flip.x < 0:
		source.position.x = texture.get_width() - source.end.x
	if flip.y < 0:
		source.position.y = texture.get_height() - source.end.y
	var shift := Vector2(clipped.size.x if flip.x < 0 else 0, clipped.size.y if flip.y < 0 else 0)
	draw_set_transform(origin + (clipped.position + shift) * factor, 0, Vector2.ONE * factor * flip)
	draw_texture_rect_region(texture, Rect2(Vector2.ZERO, clipped.size), source)


func _draw() -> void:
	if canvas == null:
		return
	stamp("edge", Vector2.ZERO, Vector2(1, -1))
	stamp("edge", Vector2(0, canvas.size.y - art.edge.get_height()))
	var side := Vector2(data.side_origin[0], data.side_origin[1])
	stamp("side", side, Vector2(-1, 1))
	stamp("side", Vector2(480 - side.x - art.side.get_width(), side.y))
	for index in 3:
		stamp(
			["ring_large", "ring_medium", "ring_small"][index],
			Vector2(data.ring_origins[index][0], data.ring_origins[index][1])
		)
	stamp("marker", Vector2(data.marker_origin[0], data.marker_origin[1]))
	stamp("indicator", Vector2(data.indicator_origin[0], data.indicator_origin[1]))
	for index in int(data.indicator_count):
		stamp(
			"indicator",
			Vector2(data.indicator_column[0], data.indicator_column[1] + index * indicator_pitch)
		)
	stamp(
		"indicator_end",
		Vector2(data.indicator_end[0] - art.indicator_end.get_width(), data.indicator_end[1])
	)
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0, 0, 0, shade / 255.0))
	var tint: Array = data.pattern_tint
	var tile: Texture2D = art.pattern
	for y in range(0, int(canvas.size.y), tile.get_height()):
		for x in range(0, 480, tile.get_width()):
			draw_texture_rect_region(
				tile,
				Rect2(x, y, mini(tile.get_width(), 480 - x), mini(tile.get_height(), int(canvas.size.y) - y)),
				Rect2(0, 0, mini(tile.get_width(), 480 - x), mini(tile.get_height(), int(canvas.size.y) - y)),
				Color8(tint[0], tint[1], tint[2], tint[3])
			)
	stamp("logo", Vector2((480 - art.logo.get_width()) * .5, data.logo_y))
	draw_set_transform(Vector2.ZERO)
