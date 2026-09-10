extends "res://src/presentation/station_menu.gd"
## Original destination information; the Session alone changes location or credits.
signal back_requested
signal travel_requested
var destination := -1
var departure := -1
var visit := -1
var quote := {}
var travel_button: Button
var notice: Label


static func valid_layout(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["box", "list"]:
		if not value.get(key) is Array or value[key].size() != 4:
			return false
		if not value[key].all(func(v): return Combat.integer(v) and v >= 0 and v <= 480):
			return false
		if value[key][2] <= 0 or value[key][3] <= 0:
			return false
	return preload("res://src/presentation/destination_scene.gd").valid_data(value.get("scene"))


func configure_destination(source, pilot, index: int) -> void:
	library = source
	session = pilot
	destination = index
	departure = session.station_id
	visit = session.market_generation
	quote = session.travel_quote(destination).duplicate(true)
	data = library.content.station_ui.duplicate(true)
	data.box = data.destination.box
	data.list = data.destination.list
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in data.images:
		art[key] = library.ui_image(data.images[key])
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var foot: Dictionary = library.content.briefing_ui.footer
	var labels: Dictionary = library.content.map_ui.labels
	var idle: Texture2D = library.ui_image(foot.normal)
	var pressed: Texture2D = library.ui_image(foot.pressed)
	var back := make_button(library.text(int(labels.back)), "back", idle, pressed)
	back.position = Vector2(foot.margin, foot.y)
	back.size = idle.get_size()
	travel_button = make_button(library.text(int(labels.travel)), "travel", idle, pressed)
	mirror_button(travel_button)
	travel_button.position = Vector2(480 - foot.margin - idle.get_width(), foot.y)
	travel_button.size = idle.get_size()
	travel_button.visible = destination != departure
	travel_button.disabled = quote.is_empty() or not session.docked or not session.exploration_unlocked() or not session.active_job.is_empty() or session.credits < quote.get("total", 0)
	actions = [back, travel_button]
	notice = Label.new()
	canvas.add_child(notice)
	notice.position = Vector2(data.list[0], data.list[1] + 6 * (art.row.get_height() + data.row_gap) + 8)
	notice.size = Vector2(data.list[2], 45)
	notice.add_theme_font_override("font", font)
	notice.add_theme_font_size_override("font_size", 9)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not session.active_job.is_empty():
		show_notice("Complete your active mission before travelling.")
	elif not quote.is_empty() and session.credits < quote.total:
		show_notice("Not enough credits for this journey.")
	action_requested.connect(func(action):
		if action == "back": back_requested.emit()
		elif action == "travel" and not travel_button.disabled: travel_requested.emit()
	)
	layout_canvas()
	back.grab_focus()


func info_rows() -> Array:
	var rows: Array = library.station_info(destination, session.visited.has(destination))
	var labels: Dictionary = library.content.map_ui.labels
	rows.append([library.text(int(labels.cost)), str(quote.get("flight", 0))])
	rows.append([library.text(int(labels.bribe)), str(quote.get("bribe", 0))])
	return rows


func preview_station() -> int:
	return destination


func current_quote() -> bool:
	return departure == session.station_id and visit == session.market_generation and quote == session.travel_quote(destination)


func show_notice(text: String) -> void:
	notice.text = text
	notice.tooltip_text = text


func _draw() -> void:
	super._draw()
	if canvas == null:
		return
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var tab: Texture2D = art.tab_single_selected
	var box := Rect2(Vector2(data.box[0], data.box[1]), tab.get_size())
	draw_texture(tab, box.position)
	write(library.text(int(library.content.map_ui.labels.info)).to_upper(), box, HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO)
