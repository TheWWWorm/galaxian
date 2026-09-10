extends "res://src/presentation/station_menu.gd"
## Native selection and transactions presented with the supplied Hangar artwork.
signal back_requested
signal transaction_requested(action: String, entry: Dictionary)
signal hint_acknowledged(role: String)
const Catalogue = preload("res://src/presentation/hangar_catalogue.gd")
var records: Array = []
var selected := -1
var details := false
var list_scroll: ScrollContainer
var rows: VBoxContainer
var primary: Button
var secondary: Button
var info: Button
var notice := ""
var hints_enabled := false
var seen_hints: Array[String] = []
var hint_role := ""
var hint_sound := preload("res://src/presentation/audio_settings.gd").effect_player()


func configure(source, pilot) -> void:
	library = source
	session = pilot
	data = library.content.hangar_ui
	add_child(hint_sound)
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in library.content.station_ui.images:
		art[key] = library.ui_image(library.content.station_ui.images[key])
		art[key].filter_clip = true
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	action_requested.connect(handle_action)
	for index in data.tabs.size():
		var entry: Dictionary = data.tabs[index]
		var edge: bool = index == 0 or index == data.tabs.size() - 1
		var button := make_button(
			library.text(int(entry.label)).to_upper(),
			"tab:" + entry.action,
			art.tab_edge_idle if edge else art.tab_middle_idle,
			art.tab_edge_selected if edge else art.tab_middle_selected
		)
		button.position = Vector2(
			data.box[0] + index * (art.tab_edge_idle.get_width() - 1), data.box[1]
		)
		button.size = art.tab_edge_idle.get_size()
		button.toggle_mode = true
		if index == data.tabs.size() - 1:
			mirror_button(button)
		tabs.append(button)
	layout_tabs()
	list_scroll = ScrollContainer.new()
	list_scroll.position = Vector2(data.list[0], data.list[1])
	list_scroll.size = Vector2(data.list[2], data.list[3])
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(list_scroll)
	rows = VBoxContainer.new()
	rows.custom_minimum_size.x = art.row.get_width()
	rows.add_theme_constant_override("separation", library.content.station_ui.row_gap)
	list_scroll.add_child(rows)
	var touch = preload("res://src/input/touch_scroll.gd").new()
	touch.scroll = list_scroll
	list_scroll.add_child(touch)
	var footer: Dictionary = library.content.briefing_ui.footer
	var normal: Texture2D = library.ui_image(footer.normal)
	var pressed: Texture2D = library.ui_image(footer.pressed)
	var back := make_button(library.text(int(data.labels.back)), "back", normal, pressed)
	back.position = Vector2(footer.margin, footer.y)
	back.size = normal.get_size()
	info = make_button(
		library.text(int(data.labels.info)),
		"info",
		library.ui_image(footer.center_normal),
		library.ui_image(footer.center_pressed)
	)
	info.size = library.ui_image(footer.center_normal).get_size()
	info.position = Vector2((480 - info.size.x) * .5, footer.y)
	primary = make_button("", "primary", normal, pressed)
	mirror_button(primary)
	primary.size = normal.get_size()
	primary.position = Vector2(480 - footer.margin - primary.size.x, footer.y)
	secondary = make_button(
		"",
		"secondary",
		library.ui_image(footer.center_normal),
		library.ui_image(footer.center_pressed)
	)
	secondary.size = library.ui_image(footer.center_normal).get_size()
	var preview := preview_origin()
	secondary.position = (
		preview
		+ Vector2(
			(art.preview.get_width() - secondary.size.x) * .5,
			art.preview.get_height() - secondary.size.y - 4
		)
	)
	actions = [back, info, primary, secondary]
	layout_canvas()
	open_tab("ship")


func open_tab(value: String) -> void:
	if not hint_role.is_empty():
		return
	close_transaction()
	section = {"stock": "shop", "ships": "shop", "fitted": "ship", "hold": "cargo"}.get(
		value, value
	)
	if not section in ["ship", "cargo", "shop"]:
		section = "ship"
	details = false
	notice = ""
	records = Catalogue.entries(library, session, section)
	selected = 0 if not records.is_empty() else -1
	for index in tabs.size():
		tabs[index].set_pressed_no_signal(data.tabs[index].action == section)
	populate()
	update_actions()
	show_hint()


func enable_hints(history: Array) -> void:
	seen_hints.clear()
	for role in history:
		if role is String and data.hints.messages.has(role) and not seen_hints.has(role):
			seen_hints.append(role)
	hints_enabled = true
	show_hint()


func show_hint() -> void:
	if not hints_enabled or overlay != null:
		return
	var role := "intro" if not seen_hints.has("intro") else section
	if seen_hints.has(role) or not data.hints.messages.has(role):
		return
	hint_role = role
	canvas.hide()
	var choice := preload("res://src/presentation/choice_window.gd").new()
	overlay = choice
	add_child(choice)
	choice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	choice.present(library, library.content.survival.choice, library.text(int(data.hints.messages[role])))
	choice.chosen.connect(func(_index: int): acknowledge_hint())
	queue_redraw()


func acknowledge_hint() -> void:
	if hint_role.is_empty():
		return
	var role := hint_role
	seen_hints.append(role)
	hint_role = ""
	hint_sound.stream = library.sound_clip(int(data.hints.sound))
	hint_sound.play()
	close_transaction()
	hint_acknowledged.emit(role)
	show_hint()


func current() -> Dictionary:
	return records[selected] if selected >= 0 and selected < records.size() else {}


func populate() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	list_scroll.scroll_vertical = 0
	if details:
		var text := Label.new()
		text.text = Catalogue.information(library, session, current())
		text.custom_minimum_size.x = art.row.get_width()
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_override("font", font)
		text.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
		rows.add_child(text)
	elif records.is_empty():
		var empty := Label.new()
		empty.text = "No stock available." if section == "shop" else "Your cargo hold is empty."
		empty.custom_minimum_size.x = art.row.get_width()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_override("font", font)
		empty.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
		rows.add_child(empty)
	else:
		var last_group := -1
		for index in records.size():
			var entry: Dictionary = records[index]
			if section == "shop":
				var group := Catalogue.group(library, entry)
				if group != last_group:
					last_group = group
					var heading := Label.new()
					heading.text = library.text(
						int(
							[
								data.labels.ships,
								data.labels.weapons,
								data.labels.generators,
								data.labels.category_base + library.CARGO_CATEGORY
							][group]
						)
					)
					heading.add_theme_font_override("font", font)
					heading.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
					rows.add_child(heading)
			var button := Button.new()
			button.set_meta("entry", index)
			button.text = Catalogue.name(library, entry)
			button.icon = Catalogue.image(library, entry)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.clip_text = true
			button.custom_minimum_size = art.row.get_size()
			button.add_theme_font_override("font", font)
			button.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
			button.toggle_mode = true
			button.button_pressed = index == selected
			for state in ["normal", "hover", "pressed", "focus"]:
				var skin: StyleBox
				if state == "normal":
					skin = StyleBoxFlat.new()
					skin.bg_color = color(library.content.station_ui.fill)
				else:
					skin = StyleBoxTexture.new()
					skin.texture = art.row
				skin.content_margin_left = 3
				skin.content_margin_right = 3
				button.add_theme_stylebox_override(state, skin)
			button.pressed.connect(select_entry.bind(index))
			button.focus_entered.connect(select_entry.bind(index))
			rows.add_child(button)
			if index == selected:
				call_deferred("focus_row", weakref(button))
	queue_redraw()


func select_entry(index: int) -> void:
	if index < 0 or index >= records.size() or details or overlay != null:
		return
	selected = index
	notice = ""
	for child in rows.get_children():
		if child is Button:
			child.set_pressed_no_signal(int(child.get_meta("entry")) == index)
	update_actions()
	queue_redraw()


func update_actions() -> void:
	var available: Array = Catalogue.actions(library, session, current())
	for index in 2:
		var button: Button = primary if index == 0 else secondary
		button.visible = index < available.size()
		if button.visible:
			button.text = available[index].text
			button.add_theme_font_size_override("font_size", maxi(7, mini(int(font.get_meta("source_height")), int(int(font.get_meta("source_height")) * (button.size.x - 8) / maxf(1, font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x)))))
			button.disabled = not available[index].enabled
	info.disabled = current().is_empty()
	info.set_pressed_no_signal(details)


func handle_action(action: String) -> void:
	if overlay != null:
		if action == "back":
			if not hint_role.is_empty():
				acknowledge_hint()
			else:
				close_transaction()
		return
	if action.begins_with("tab:"):
		open_tab(action.trim_prefix("tab:"))
	elif action == "back":
		if details:
			details = false
			populate()
		else:
			back_requested.emit()
	elif action == "info" and not current().is_empty():
		details = not details
		populate()
		update_actions()
	elif action in ["primary", "secondary"]:
		var choices: Array = Catalogue.actions(library, session, current())
		var index := 0 if action == "primary" else 1
		if index < choices.size() and choices[index].enabled:
			if choices[index].action == "buy" and current().kind == "ship":
				open_exchange()
			elif choices[index].action == "sell_cargo":
				open_quantity()
			else:
				transaction_requested.emit(choices[index].action, current().duplicate(true))


func refresh() -> void:
	details = false
	notice = ""
	records = Catalogue.entries(library, session, section)
	selected = clampi(selected, 0, records.size() - 1) if not records.is_empty() else -1
	populate()
	update_actions()


func show_notice(text: String) -> void:
	notice = text
	queue_redraw()


func preview_origin() -> Vector2:
	var shared: Dictionary = library.content.station_ui
	return Vector2(
		data.list[0] + data.list[2] + shared.preview_gap[0], data.list[1] + shared.preview_gap[1]
	)


func _draw() -> void:
	if canvas == null or overlay != null:
		return
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var shared: Dictionary = library.content.station_ui
	var frame := data.duplicate()
	frame.fill = shared.fill
	frame.border = shared.border
	draw_frame(frame)
	var preview := preview_origin()
	draw_texture(art.preview, preview)
	var entry := current()
	if not entry.is_empty():
		write(
			Catalogue.name(library, entry),
			Rect2(preview + Vector2(4, 7), Vector2(art.preview.get_width() - 8, 20)),
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var picture: Texture2D = Catalogue.image(library, entry, true)
		if picture != null:
			draw_texture_rect(picture, preview_rect(picture), false)
		var detail: String = "%d credits" % int(entry.price)
		if entry.source == "shop" and entry.kind == "ship":
			detail = "%d cr after trade-in" % (int(entry.price) - session.ship_value)
		elif entry.has("count"):
			detail += " · %d" % int(entry.count)
		write(
			detail,
			Rect2(
				preview + Vector2(4, art.preview.get_height() - 52),
				Vector2(art.preview.get_width() - 8, 20)
			),
			HORIZONTAL_ALIGNMENT_CENTER
		)
	var credits_at := preview + Vector2(0, art.preview.get_height() + shared.credits_gap)
	draw_texture(art.credits, credits_at)
	write(
		library.text(int(shared.credits_label)), Rect2(credits_at + Vector2(3, 9), Vector2(90, 20))
	)
	write(
		str(session.credits),
		Rect2(credits_at + Vector2(90, 9), Vector2(art.credits.get_width() - 94, 20)),
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	if not notice.is_empty():
		var rect := Rect2(30, 276, 420, 12)
		draw_rect(rect, Color(.02, .05, .05, .95))
		write(notice, rect)
	draw_set_transform(Vector2.ZERO)


func _process(_delta: float) -> void:
	pass


func _exit_tree() -> void:
	hint_sound.stop()
	hint_sound.stream = null


func focus_row(reference: WeakRef) -> void:
	# A tab rebuild may free its row before this deferred call is delivered.
	var button = reference.get_ref()
	if is_instance_valid(button) and button.is_inside_tree() and button.is_visible_in_tree() and overlay == null and int(button.get_meta("entry")) == selected:
		button.grab_focus()


func preview_rect(picture: Texture2D) -> Rect2:
	# Reserve the title, price and transaction row; preserve each supplied aspect ratio.
	var bounds := Rect2(preview_origin() + Vector2(8, 32), art.preview.get_size() - Vector2(16, 92))
	var scale := minf(1.0, minf(bounds.size.x / picture.get_width(), bounds.size.y / picture.get_height()))
	var extent := picture.get_size() * scale
	return Rect2(bounds.get_center() - extent * .5, extent)


func open_quantity() -> void:
	canvas.hide()
	queue_redraw()
	overlay = preload("res://src/presentation/cargo_sale.gd").new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.configure(library, current())
	overlay.cancelled.connect(close_transaction)
	overlay.confirmed.connect(func(amount: int):
		var sale: Dictionary = overlay.entry.duplicate(true)
		sale.amount = amount
		close_transaction()
		transaction_requested.emit("sell_cargo", sale)
	)


func close_transaction() -> void:
	if overlay == null:
		return
	overlay.hide()
	overlay.queue_free()
	overlay = null
	canvas.show()
	queue_redraw()
	for button in rows.get_children():
		if button is Button and int(button.get_meta("entry")) == selected:
			call_deferred("focus_row", weakref(button))


func open_exchange() -> void:
	var reviewed: Dictionary = session.ship_offer_quote(int(current().index))
	if reviewed.is_empty():
		show_notice(session.error)
		return
	canvas.hide()
	queue_redraw()
	overlay = preload("res://src/presentation/ship_exchange.gd").new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.configure(library, reviewed)
	overlay.cancelled.connect(close_transaction)
	overlay.confirmed.connect(func(quote: Dictionary):
		close_transaction()
		transaction_requested.emit("exchange", quote)
	)
