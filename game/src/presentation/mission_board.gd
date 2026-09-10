extends "res://src/presentation/station_menu.gd"
## Read-only contract browser. Session remains the authority for accepting work.
signal back_requested
signal accept_requested(reference: Dictionary, offer: Dictionary)
const Contracts = preload("res://src/simulation/contracts.gd")
var offers: Array = []
var references: Array = []
var selected := -1
var details := false
var list_scroll: ScrollContainer
var rows: VBoxContainer
var description: Label
var info: Button
var accept: Button
var notice: Label


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary or not value.get("images") is Dictionary or not value.get("labels") is Dictionary:
		return false
	for pair in [["box", 4], ["list", 4], ["profile", 3], ["button_end", 2], ["description_box", 4], ["description_fill", 4]]:
		var vector: Variant = value.get(pair[0])
		if not vector is Array or vector.size() != pair[1] or not vector.all(func(v): return Combat.integer(v) and v >= 0 and v <= 480):
			return false
	for key in ["row_height", "row_gap", "profession_width", "stat_lines", "button_gap", "special_portrait"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 512:
			return false
	if value.row_height <= 0 or value.stat_lines <= 0 or value.list[2] <= 0 or value.list[3] <= 0 or value.profile[2] <= value.profile[0]:
		return false
	if value.description_box[2] <= 0 or value.description_box[3] <= 0 or not value.description_fill.all(func(v): return v <= 255):
		return false
	for key in ["button", "pressed"]:
		var binding: Variant = value.images.get(key)
		if not binding is Dictionary:
			return false
		for field in ["texture", "region"]:
			if not Combat.integer(binding.get(field)) or binding[field] < 0:
				return false
	for key in ["title", "back", "info", "accept", "difficulty", "reward", "empty", "special", "special_description", "description"]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	return value.get("rate_prefix") is String and value.rate_prefix.length() <= 16


func configure(source, pilot) -> void:
	library = source
	session = pilot
	data = library.content.board_ui
	offers = session.contract_offers().duplicate(true)
	for index in offers.size():
		references.append(session.contract_reference(index))
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in library.content.station_ui.images:
		art[key] = library.ui_image(library.content.station_ui.images[key])
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	action_requested.connect(handle_action)
	var foot: Dictionary = library.content.briefing_ui.footer
	var back := make_button(library.text(int(data.labels.back)), "back", library.ui_image(foot.normal), library.ui_image(foot.pressed))
	back.position = Vector2(foot.margin, foot.y)
	back.size = library.ui_image(foot.normal).get_size()
	var idle: Texture2D = library.ui_image(data.images.button)
	var pressed: Texture2D = library.ui_image(data.images.pressed)
	info = make_button(library.text(int(data.labels.info)), "info", idle, pressed)
	accept = make_button(library.text(int(data.labels.accept)), "accept", idle, pressed)
	accept.position = Vector2(data.button_end[0], data.button_end[1]) - idle.get_size()
	info.position = accept.position - Vector2(0, idle.get_height() + data.button_gap)
	info.size = idle.get_size()
	accept.size = idle.get_size()
	actions = [back, info, accept]
	list_scroll = ScrollContainer.new()
	canvas.add_child(list_scroll)
	list_scroll.position = Vector2(data.list[0], data.list[1])
	list_scroll.size = Vector2(data.list[2], data.list[3])
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", data.row_gap)
	list_scroll.add_child(rows)
	var touch = preload("res://src/input/touch_scroll.gd").new()
	touch.scroll = list_scroll
	list_scroll.add_child(touch)
	description = Label.new()
	description.custom_minimum_size.x = data.list[2] - 10
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_override("font", font)
	description.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
	notice = Label.new()
	canvas.add_child(notice)
	notice.position = Vector2(data.profile[0], data.profile[1] + (data.stat_lines + 2) * int(font.get_meta("source_height")))
	notice.size = Vector2(data.profile[2] - data.profile[0], maxf(int(font.get_meta("source_height")), info.position.y - notice.position.y - 3))
	notice.add_theme_font_override("font", font)
	notice.add_theme_font_size_override("font_size", 9)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	populate()
	update_actions()
	layout_canvas()
	back.grab_focus()


func title_for(offer: Dictionary) -> String:
	return library.text(int(data.labels.special if offer.special else library.content.contracts.types[int(offer.type)].title))


func reward_for(offer: Dictionary) -> String:
	return (str(data.rate_prefix) if offer.reward_unit == "per_target" else "") + str(offer.reward)


func populate() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		if child != description:
			child.queue_free()
	list_scroll.scroll_vertical = 0
	if details:
		var offer: Dictionary = offers[selected]
		var text_id := int(data.labels.special_description if offer.special else library.content.contracts.types[int(offer.type)].description)
		description.text = library.text(int(data.labels.description)) + "\n\n" + library.text(text_id)
		rows.add_child(description)
	elif offers.is_empty():
		description.text = library.text(int(data.labels.empty))
		rows.add_child(description)
	else:
		for index in offers.size():
			var offer: Dictionary = offers[index]
			var button := Button.new()
			button.custom_minimum_size = Vector2(data.list[2] - 10, data.row_height)
			button.toggle_mode = true
			button.button_pressed = index == selected
			button.set_meta("offer", index)
			button.tooltip_text = title_for(offer) + " · " + reward_for(offer)
			if offer.reward_unit == "per_target": button.tooltip_text += " per target"
			for state in ["normal", "hover", "pressed", "focus"]:
				var skin := StyleBoxFlat.new()
				skin.bg_color = color(library.content.station_ui.fill) if state == "normal" else Color(.12, .42, .44, .85)
				if state != "normal":
					var texture := StyleBoxTexture.new()
					texture.texture = art.row
					button.add_theme_stylebox_override(state, texture)
				else: button.add_theme_stylebox_override(state, skin)
			var line := HBoxContainer.new()
			button.add_child(line)
			line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.offset_left = 3
			line.offset_right = -3
			for text in [title_for(offer), reward_for(offer)]:
				var label := Label.new()
				label.text = text
				label.add_theme_font_override("font", font)
				label.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				line.add_child(label)
				if line.get_child_count() == 1:
					label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					label.clip_text = true
			button.pressed.connect(select_offer.bind(index))
			button.focus_entered.connect(select_offer.bind(index))
			rows.add_child(button)
	queue_redraw()


func select_offer(index: int) -> void:
	if details or index < 0 or index >= offers.size(): return
	selected = index
	notice.text = ""
	for child in rows.get_children():
		if child is Button: child.set_pressed_no_signal(child.get_meta("offer") == selected)
	update_actions()
	queue_redraw()


func update_actions() -> void:
	info.visible = selected >= 0 and not details
	accept.visible = selected >= 0
	if selected < 0: return
	var paid: bool = session.contract_paid(references[selected])
	accept.disabled = paid or not Contracts.supported(library, offers[selected])
	accept.text = "Completed" if paid else library.text(int(data.labels.accept))
	accept.tooltip_text = "Encounter in development" if not Contracts.supported(library, offers[selected]) else ""


func handle_action(action: String) -> void:
	if action == "back":
		if details:
			details = false
			populate()
			update_actions()
			rows.get_child(selected).grab_focus()
		else: back_requested.emit()
	elif action == "info" and selected >= 0:
		details = true
		populate()
		update_actions()
		actions[0].grab_focus()
	elif action == "accept" and selected >= 0 and not accept.disabled:
		accept_requested.emit(references[selected].duplicate(true), offers[selected].duplicate(true))


func show_notice(text: String) -> void:
	notice.text = text
	notice.tooltip_text = text


func _draw() -> void:
	if canvas == null: return
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var frame := data.duplicate()
	frame.fill = library.content.station_ui.fill
	frame.border = library.content.station_ui.border
	draw_frame(frame)
	if details:
		var box: Array = data.description_box
		draw_rect(Rect2(box[0], box[1], box[2], box[3]), color(data.description_fill))
	var tab: Texture2D = art.tab_single_selected
	draw_texture(tab, Vector2(data.box[0], data.box[1]))
	write(library.text(int(data.labels.title)).to_upper(), Rect2(Vector2(data.box[0], data.box[1]), tab.get_size()), HORIZONTAL_ALIGNMENT_CENTER)
	if selected >= 0:
		var offer: Dictionary = offers[selected]
		var portrait: Texture2D = library.radio_portrait(int(offer.client.portrait))
		var x := float(data.profile[0])
		var y := float(data.profile[1])
		var right := float(data.profile[2])
		draw_texture(portrait, Vector2(right - portrait.get_width(), y))
		var width := right - x - portrait.get_width() - 3
		write(str(offer.client.name), Rect2(x, y, width, int(font.get_meta("source_height"))))
		y += int(font.get_meta("source_height"))
		if not offer.special:
			write(library.text(int(library.content.map_ui.races[int(offer.client.race)])), Rect2(x, y, width, int(font.get_meta("source_height"))))
		y += int(font.get_meta("source_height"))
		var profession: String = library.text(int(offer.client.profession))
		# Native line wrapping keeps localized client descriptions within the profile.
		var lines := font.get_multiline_string_size(profession, HORIZONTAL_ALIGNMENT_LEFT, data.profession_width - portrait.get_width(), int(font.get_meta("source_height")))
		draw_multiline_string(font, Vector2(x + 2, y + int(font.get_meta("source_height"))), profession, HORIZONTAL_ALIGNMENT_LEFT, data.profession_width - portrait.get_width(), int(font.get_meta("source_height")), 5)
		y = maxf(float(data.profile[1]) + data.stat_lines * int(font.get_meta("source_height")), y + minf(lines.y, 5 * int(font.get_meta("source_height"))))
		write(library.text(int(data.labels.difficulty)) + ":", Rect2(x, y, right - x, int(font.get_meta("source_height"))))
		write(library.text(int(data.labels.special)) if offer.special else str(offer.difficulty), Rect2(x, y, right - x, int(font.get_meta("source_height"))), HORIZONTAL_ALIGNMENT_RIGHT)
		y += int(font.get_meta("source_height"))
		write(library.text(int(data.labels.reward)), Rect2(x, y, right - x, int(font.get_meta("source_height"))))
		write(reward_for(offer), Rect2(x, y, right - x, int(font.get_meta("source_height"))), HORIZONTAL_ALIGNMENT_RIGHT)
	draw_set_transform(Vector2.ZERO)


func _exit_tree() -> void:
	if description != null and description.get_parent() == null:
		description.free()
