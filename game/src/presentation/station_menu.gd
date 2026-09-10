extends Control
## Original dock information/tab artwork; navigation is owned by the native game.
signal action_requested(action: String)
const PilotStatistics = preload("res://src/simulation/pilot_statistics.gd")
const Combat = preload("res://src/simulation/combat.gd")
var library
var session
var data: Dictionary
var art := {}
var font: FontFile
var canvas: Control
var tabs: Array[Button] = []
var actions: Array[Button] = []
var overlay: Control
var section := "info"
var factor := 1.0
var origin := Vector2.ZERO


static func valid_data(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("images") is Dictionary
		or not value.get("tabs") is Array
		or value.tabs.size() != 4
	):
		return false
	var seen: Array = []
	for tab in value.tabs:
		if (
			not tab is Dictionary
			or not Combat.integer(tab.get("label"))
			or tab.label < 0
			or not tab.get("action") in ["info", "hangar", "missions", "map"]
			or tab.action in seen
		):
			return false
		seen.append(tab.action)
	for key in [
		"corner",
		"top_corner",
		"tab_middle_idle",
		"tab_single_idle",
		"tab_edge_selected",
		"tab_edge_idle",
		"tab_middle_selected",
		"tab_single_selected",
		"row",
		"credits",
		"preview"
	]:
		var image: Variant = value.images.get(key)
		if (
			not image is Dictionary
			or not Combat.integer(image.get("texture"))
			or not Combat.integer(image.get("region"))
			or image.texture < 0
			or image.region < 0
		):
			return false
	for key in ["box", "list", "fill", "border"]:
		if (
			not value.get(key) is Array
			or value[key].size() != 4
			or not value[key].all(func(v): return Combat.number(v) and v >= 0 and v <= 480)
		):
			return false
	if value.box[2] <= 0 or value.box[3] <= 0 or value.list[2] <= 0 or value.list[3] <= 0:
		return false
	for key in ["fill", "border"]:
		if not value[key].all(func(v): return v <= 255):
			return false
	for key in ["preview_gap", "preview_center", "credits_text"]:
		if (
			not value.get(key) is Array
			or value[key].size() != 2
			or not value[key].all(func(v): return Combat.number(v) and v >= 0 and v <= 480)
		):
			return false
	for key in ["credits_label", "shop_credit_threshold", "credits_gap", "tab_text_y", "row_gap"]:
		if not Combat.integer(value.get(key)) or value[key] < 0:
			return false
	if (
		not value.get("locked_campaign_tabs") is Array
		or value.locked_campaign_tabs.size() != 2
		or not value.locked_campaign_tabs.all(
			func(v): return Combat.integer(v) and v >= 0 and v < 4
		)
	):
		return false
	if not value.get("footer_labels") is Dictionary:
		return false
	for key in ["menu", "continue", "status"]:
		if not Combat.integer(value.footer_labels.get(key)) or value.footer_labels[key] < 0:
			return false
	return valid_status(value.get("status"))


static func valid_status(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("labels") is Dictionary
		or not value.get("images") is Dictionary
	):
		return false
	for key in ["box", "list"]:
		if (
			not value.get(key) is Array
			or value[key].size() != 4
			or not value[key].all(func(v): return Combat.number(v) and v >= 0 and v <= 480)
			or value[key][2] <= 0
			or value[key][3] <= 0
		):
			return false
	for key in [
		"title",
		"back",
		"level",
		"reputation",
		"time",
		"kills",
		"missions",
		"loyalty",
		"left_race",
		"right_race"
	]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	for key in ["gauge", "pointer"]:
		var binding: Variant = value.images.get(key)
		if (
			not binding is Dictionary
			or not Combat.integer(binding.get("texture"))
			or not Combat.integer(binding.get("region"))
			or binding.texture < 0
			or binding.region < 0
		):
			return false
	for key in [
		"protagonist",
		"name_y",
		"right_edge",
		"width_inset",
		"loyalty_lines",
		"pointer_inset",
		"pointer_travel_inset",
		"rating_offset",
		"rating_span",
		"reputation_base",
		"reputation_max"
	]:
		if not Combat.integer(value.get(key)) or value[key] < 0:
			return false
	if (
		value.rating_span <= 0
		or not Combat.number(value.get("line_step"))
		or value.line_step <= 0
		or not Combat.number(value.get("pointer_y"))
	):
		return false
	if (
		not value.get("name") is Array
		or value.name.size() != 2
		or not value.name.all(func(v): return v is String and not v.is_empty())
	):
		return false
	if (
		not value.get("reputation_thresholds") is Array
		or value.reputation_thresholds.is_empty()
		or value.reputation_max >= value.reputation_thresholds.size()
	):
		return false
	var previous := -1
	for threshold in value.reputation_thresholds:
		if not Combat.integer(threshold) or threshold <= previous:
			return false
		previous = int(threshold)
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(layout_canvas)


func configure(source, pilot) -> void:
	library = source
	session = pilot
	data = library.content.station_ui
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in data.images:
		art[key] = library.ui_image(data.images[key])
		art[key].filter_clip = true
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	for index in data.tabs.size():
		var entry: Dictionary = data.tabs[index]
		var edge: bool = index == 0 or index == data.tabs.size() - 1
		var idle: Texture2D = art.tab_edge_idle if edge else art.tab_middle_idle
		var selected: Texture2D = art.tab_edge_selected if edge else art.tab_middle_selected
		var button := make_button(
			library.text(int(entry.label)).to_upper(), str(entry.action), idle, selected
		)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := button.get_theme_stylebox(state) as StyleBoxTexture
			style.content_margin_top = data.tab_text_y
			style.content_margin_bottom = maxf(
				0, idle.get_height() - data.tab_text_y - int(font.get_meta("source_height"))
			)
		button.toggle_mode = true
		button.button_pressed = entry.action == "info"
		button.position = Vector2(data.box[0] + index * (idle.get_width() - 1), data.box[1])
		button.size = idle.get_size()
		button.disabled = not tab_enabled(index)
		if index == data.tabs.size() - 1:
			mirror_button(button)
		tabs.append(button)
	layout_tabs()
	var foot: Dictionary = library.content.briefing_ui.footer
	var left := make_button(
		library.text(int(data.footer_labels.menu)),
		"menu",
		library.ui_image(foot.normal),
		library.ui_image(foot.pressed)
	)
	left.position = Vector2(foot.margin, foot.y)
	left.size = library.ui_image(foot.normal).get_size()
	actions.append(left)
	var middle := make_button(
		library.text(int(data.footer_labels.status)),
		"status",
		library.ui_image(foot.center_normal),
		library.ui_image(foot.center_pressed)
	)
	middle.size = library.ui_image(foot.center_normal).get_size()
	middle.position = Vector2((480 - middle.size.x) * .5, foot.y)
	actions.append(middle)
	var caption: String = (
		library.text(int(data.footer_labels.continue))
		if session.campaign_state == "active"
		else "Launch"
	)
	var right := make_button(
		caption, "launch", library.ui_image(foot.normal), library.ui_image(foot.pressed)
	)
	mirror_button(right)
	right.size = left.size
	right.position = Vector2(480 - foot.margin - right.size.x, foot.y)
	right.disabled = session.campaign_state == "active" and not session.mission_available()
	actions.append(right)
	layout_canvas()
	left.grab_focus()


func tab_enabled(index: int) -> bool:
	if (
		session.campaign_state == "active"
		and data.locked_campaign_tabs.any(func(v): return int(v) == index)
	):
		return false
	if data.tabs[index].action == "hangar" and session.campaign_state != "active":
		return (
			library.station_definition(session.station_id).shop
			or session.credits > data.shop_credit_threshold
		)
	return true


func layout_tabs() -> void:
	if preload("res://src/presentation/bitmap_font.gd").is_mobile() or tabs.is_empty():
		return
	# Native font line height must not add to the original bitmap padding.
	# Divide the panel extent, rather than accumulating sprite widths.
	for index in tabs.size():
		var button := tabs[index]
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			var style := button.get_theme_stylebox(state) as StyleBoxTexture
			style.content_margin_top = 0
			style.content_margin_bottom = 0
		var left := float(data.box[2]) * index / tabs.size()
		var right := float(data.box[2]) * (index + 1) / tabs.size()
		button.position = Vector2(float(data.box[0]) + left, data.box[1])
		button.size = Vector2(right - left, art.tab_edge_idle.get_height())


func make_button(text: String, action: String, idle: Texture2D, selected: Texture2D) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", font)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
	button.add_theme_font_size_override(
		"font_size",
		maxi(
			7,
			mini(
				int(font.get_meta("source_height")), int(int(font.get_meta("source_height")) * (idle.get_width() - 8) / maxf(1, text_width))
			)
		)
	)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var skin := StyleBoxTexture.new()
		skin.texture = idle if state in ["normal", "disabled"] else selected
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			skin.set_content_margin(side, 0)
		button.add_theme_stylebox_override(state, skin)
		button.add_theme_color_override(
			"font_" + state + "_color", Color(.47, .47, .47) if state == "disabled" else Color.WHITE
		)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.pressed.connect(
		func():
			if is_visible_in_tree():
				action_requested.emit(action)
	)
	canvas.add_child(button)
	return button


func layout_canvas() -> void:
	if canvas == null:
		return
	factor = preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	origin = (size - Vector2(480, 320) * factor) * .5
	canvas.position = origin
	canvas.scale = Vector2.ONE * factor
	canvas.size = Vector2(480, 320)
	queue_redraw()


func color(values: Array) -> Color:
	return Color8(values[0], values[1], values[2], values[3])


func write(text: String, rect: Rect2, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
	var font_size := maxi(
		7, mini(int(font.get_meta("source_height")), int(int(font.get_meta("source_height")) * (rect.size.x - 4) / maxf(1, width)))
	)
	draw_string(
		font,
		rect.position + Vector2(2, font_size),
		text,
		align,
		rect.size.x - 4,
		font_size,
		Color.WHITE
	)


func _draw() -> void:
	if canvas == null:
		return
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var layout: Dictionary = data.status if section == "status" else data
	draw_frame(layout)
	var rows: Array = (
		status_rows() if section == "status" else info_rows()
	)
	var row_size: Vector2 = art.row.get_size()
	for index in rows.size():
		var rect := Rect2(
			Vector2(layout.list[0], layout.list[1] + index * (row_size.y + data.row_gap)), row_size
		)
		draw_rect(rect, color(data.fill))
		draw_rect(rect, color(data.border), false)
		var text_rect := Rect2(
			rect.position + Vector2(0, (row_size.y - int(font.get_meta("source_height"))) * .5), rect.size
		)
		var label_text := str(rows[index][0]) + ":"
		var label_width := (
			font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
		)
		write(label_text, text_rect)
		var value_width := maxf(30, rect.size.x - label_width - 10)
		write(
			str(rows[index][1]),
			Rect2(
				text_rect.position + Vector2(rect.size.x - value_width, 0),
				Vector2(value_width, text_rect.size.y)
			),
			HORIZONTAL_ALIGNMENT_RIGHT
		)

	var preview := Vector2(
		layout.list[0] + layout.list[2] + data.preview_gap[0], layout.list[1] + data.preview_gap[1]
	)
	draw_texture(art.preview, preview)
	if section == "status":
		draw_status()
	else:
		var center := Vector2(data.preview_center[0], data.preview_center[1])
		var picture: Texture2D = library.station_preview(preview_station())
		draw_texture(picture, center - picture.get_size() * .5)
		var ring: Texture2D = library.ui_image(library.content.map_ui.images.preview_ring)
		draw_texture(ring, center - ring.get_size() * .5)
	var credits_at := preview + Vector2(0, art.preview.get_height() + data.credits_gap)
	draw_texture(art.credits, credits_at)
	write(
		library.text(int(data.credits_label)),
		Rect2(
			credits_at + Vector2(data.credits_text[0], data.credits_text[1]),
			Vector2(art.credits.get_width() * .6, 20)
		)
	)
	write(
		str(session.credits),
		Rect2(
			credits_at + Vector2(art.credits.get_width() * .6, data.credits_text[1]),
			Vector2(art.credits.get_width() * .4 - data.credits_text[0], 20)
		),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	draw_set_transform(Vector2.ZERO)


func info_rows() -> Array:
	return library.station_info(session.station_id, true)


func preview_station() -> int:
	return session.station_id


func mirror_button(button: Button) -> void:
	# Only the artwork flips; the native label remains readable.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var skin := button.get_theme_stylebox(state) as StyleBoxTexture
		var image := skin.texture.get_image()
		image.flip_x()
		skin.texture = ImageTexture.create_from_image(image)


func show_overlay(kind: String, entries: Array, body: String = "") -> void:
	close_overlay()
	section = kind
	for button in tabs + actions:
		button.disabled = true
	overlay = Panel.new()
	overlay.position = Vector2(80, 35)
	overlay.size = Vector2(320, 250)
	var skin := StyleBoxFlat.new()
	skin.bg_color = color(data.fill)
	skin.bg_color.a = .96
	skin.border_color = color(data.border)
	skin.set_border_width_all(1)
	overlay.add_theme_stylebox_override("panel", skin)
	canvas.add_child(overlay)
	var y := 12.0
	if not body.is_empty():
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(15, 12)
		scroll.size = Vector2(290, 177)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		overlay.add_child(scroll)
		var label := Label.new()
		label.text = body
		label.custom_minimum_size.x = 278
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
		scroll.add_child(label)
		var drag = preload("res://src/input/touch_scroll.gd").new()
		drag.scroll = scroll
		scroll.add_child(drag)
		y = 202
	var idle: Texture2D = library.ui_image(library.content.title_ui.images.idle)
	var selected: Texture2D = library.ui_image(library.content.title_ui.images.selected)
	var first: Button
	for entry in entries:
		var button := make_button(str(entry.text), str(entry.action), idle, selected)
		canvas.remove_child(button)
		overlay.add_child(button)
		button.position = Vector2((overlay.size.x - idle.get_width()) * .5, y)
		button.size = idle.get_size()
		button.disabled = not bool(entry.get("enabled", true))
		y += library.content.title_ui.row_step
		if first == null and not button.disabled:
			first = button
	if first != null:
		first.grab_focus()


func close_overlay() -> void:
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.queue_free()
	overlay = null
	section = "info"
	for index in tabs.size():
		tabs[index].show()
		tabs[index].disabled = not tab_enabled(index)
		tabs[index].set_pressed_no_signal(data.tabs[index].action == "info")
	for button in actions:
		button.show()
		button.disabled = false
	if actions.size() == 3:
		actions[2].disabled = session.campaign_state == "active" and not session.mission_available()
		actions[0].grab_focus()
	queue_redraw()


func status_rows() -> Array:
	var labels: Dictionary = data.status.labels
	var stats: Dictionary = session.statistics
	var suffix := "*" if stats.partial else ""
	var reputation := (
		int(data.status.reputation_base) + PilotStatistics.reputation(stats, data.status)
	)
	return [
		[library.text(int(labels.level)), str(session.rank())],
		[library.text(int(labels.reputation)), library.text(reputation) + suffix],
		[library.text(int(labels.time)), PilotStatistics.duration(stats.play_seconds) + suffix],
		[library.text(int(labels.kills)), str(int(stats.kills)) + suffix],
		[library.text(int(labels.missions)), str(session.chapter + session.contract_rewards.size())]
	]


func show_status() -> void:
	close_overlay()
	section = "status"
	for button in tabs + actions:
		button.hide()
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	var foot: Dictionary = library.content.briefing_ui.footer
	var back := make_button(
		library.text(int(data.status.labels.back)),
		"back",
		library.ui_image(foot.normal),
		library.ui_image(foot.pressed)
	)
	back.reparent(overlay)
	back.position = Vector2(foot.margin, foot.y)
	back.size = library.ui_image(foot.normal).get_size()
	back.grab_focus()
	queue_redraw()


func draw_status() -> void:
	var config: Dictionary = data.status
	var tab: Texture2D = art.tab_single_selected
	var at := Vector2(config.box[0], config.box[1])
	draw_texture(tab, at)
	write(
		library.text(int(config.labels.title)).to_upper(),
		Rect2(at + Vector2(0, data.tab_text_y), tab.get_size()),
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var gauge: Texture2D = library.ui_image(config.images.gauge)
	var pointer: Texture2D = library.ui_image(config.images.pointer)
	var width: float = gauge.get_width() - config.width_inset
	var x: float = config.right_edge - width
	for index in config.name.size():
		write(
			str(config.name[index]),
			Rect2(x, config.name_y + index * int(font.get_meta("source_height")), width, int(font.get_meta("source_height")))
		)
	var portrait: Texture2D = library.ui_image(
		library.content.radio_ui.portraits[int(config.protagonist)]
	)
	draw_texture(portrait, Vector2(config.right_edge - 1 - portrait.get_width(), config.name_y))
	var y: float = config.name_y + config.loyalty_lines * int(font.get_meta("source_height"))
	write(library.text(int(config.labels.loyalty)) + ":", Rect2(x, y, width, int(font.get_meta("source_height"))))
	y += floorf(config.line_step * int(font.get_meta("source_height")))
	write(library.text(int(config.labels.left_race)), Rect2(x, y, width * .5, int(font.get_meta("source_height"))))
	write(
		library.text(int(config.labels.right_race)),
		Rect2(x + width * .5, y, width * .5, int(font.get_meta("source_height"))),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	y += floorf(config.line_step * int(font.get_meta("source_height")))
	draw_texture(gauge, Vector2(x, y))
	var fraction := clampf(float(session.rating + config.rating_offset) / config.rating_span, 0, 1)
	var pointer_x: float = (
		x + config.pointer_inset + floorf((width - config.pointer_travel_inset) * fraction)
	)
	draw_texture(pointer, Vector2(pointer_x - pointer.get_width() * .5, y + config.pointer_y))
	if session.statistics.partial:
		var note_at := Vector2(
			config.list[0], config.list[1] + 6 * (art.row.get_height() + data.row_gap)
		)
		write("* Recorded since save upgrade.", Rect2(note_at, Vector2(art.row.get_width(), 20)))
		write(
			"Earlier time and kills unavailable.",
			Rect2(note_at + Vector2(0, int(font.get_meta("source_height")) + 3), Vector2(art.row.get_width(), 20))
		)


func _process(_delta: float) -> void:
	if section == "status":
		queue_redraw()


func draw_frame(layout: Dictionary) -> void:
	var box := Rect2(
		layout.box[0],
		layout.box[1] + art.tab_edge_idle.get_height(),
		layout.box[2],
		layout.box[3] - art.tab_edge_idle.get_height()
	)
	var corner: Texture2D = art.corner
	var inset := corner.get_size()
	draw_rect(
		Rect2(box.position + Vector2(inset.x, 0), box.size - Vector2(inset.x * 2, 0)),
		color(layout.get("fill",library.content.station_ui.fill))
	)
	for side in 2:
		draw_rect(
			Rect2(
				box.position + Vector2(side * (box.size.x - inset.x), inset.y),
				Vector2(inset.x, box.size.y - inset.y * 2)
			),
			color(layout.get("fill",library.content.station_ui.fill))
		)
	for side in 2:
		for row in 2:
			var texture: Texture2D = art.top_corner if row == 0 and side == 0 else corner
			var at := (
				box.position + Vector2(side * (box.size.x - inset.x), row * (box.size.y - inset.y))
			)
			draw_texture_rect(
				texture, Rect2(at, inset * Vector2(-1 if side else 1, -1 if row else 1)), false
			)
		draw_line(
			box.position + Vector2(inset.x, side * (box.size.y - 1)),
			box.position + Vector2(box.size.x - inset.x, side * (box.size.y - 1)),
			color(layout.get("border",library.content.station_ui.border))
		)
		draw_line(
			box.position + Vector2(side * (box.size.x - 1), inset.y),
			box.position + Vector2(side * (box.size.x - 1), box.size.y - inset.y),
			color(layout.get("border",library.content.station_ui.border))
		)
