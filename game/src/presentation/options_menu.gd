extends "res://src/presentation/title_menu.gd"
## Original menu art and option widgets; native settings belong to the owner.
signal setting_changed(key: String, value: Variant)
signal back_requested
var values := {}
var options := {}
var option_art := {}
var sliders := {}
var entries: Array = []
var help_text := ""


func setup(source, settings: Dictionary, help: String) -> void:
	configure(source)
	options = library.content.options_ui
	values = settings.duplicate(true)
	if values.get("targeting_reticle") == null:
		values.targeting_reticle = bool(library.content.flight_ui.radar.lead.enabled)
	if not values.get("music", true):
		values.music_volume = 0.0
	help_text = help
	for key in options.images:
		option_art[key] = library.ui_image(options.images[key])
		option_art[key].filter_clip = true
	action_requested.connect(handle_action)
	show_section("options")


func label_for(key: String) -> String:
	if options.labels.has(key):
		return library.text(int(options.labels[key]))
	if key == "targeting_reticle":
		return library.text(int(library.content.flight_ui.radar.lead.option_text))
	return {
		"aim_assist": "Aim assistance", "linked_fire": "Fire linked weapons",
		"touch": "Show touch controls", "sensitivity": "Mouse sensitivity",
		"language": "Language", "fullscreen": "Fullscreen", "aspect_ratio": "Aspect ratio",
		"help": library.text(int(data.labels.help))
	}.get(key, key)


func show_section(page: String, focus_key: String = "") -> void:
	entries.clear()
	sliders.clear()
	var keys: Array = {
		"options": ["controls", "audio", "display", "language"],
		"controls": ["invert", "sensitivity", "aim_assist", "linked_fire", "help"],
		"audio": ["effects_volume", "music_volume"],
		"display": ["fullscreen", "aspect_ratio", "targeting_reticle", "touch"], "help": []
	}.get(page, [])
	if preload("res://src/presentation/bitmap_font.gd").is_mobile():
		keys.erase("fullscreen")
	for key in keys:
		var caption_key: String = {"music_volume": "music", "effects_volume": "effects"}.get(key, key)
		var caption := label_for(caption_key)
		if key == "language":
			caption += ": " + library.language_name(library.language_code)
		if key == "aspect_ratio":
			var ratio: String = values.get(key, "auto")
			caption += ": " + ("Auto" if ratio == "auto" else ratio)
		entries.append({"action": key, "text": caption})
	present(page, entries, library.text(int(library.content.briefing_ui.labels.back)), "back", help_text if page == "help" else "")
	# Original sliders are taller than ordinary rows. Native extra settings must
	# fit between the logo and footer without overlapping their neighbours.
	var row_heights: Array[float] = []
	var total_height := 0.0
	for index in entries.size():
		var key: String = entries[index].action
		var height := float(art.idle.get_height())
		if key in ["music_volume", "effects_volume", "sensitivity"]:
			height = float(option_art.slider_idle.get_height())
		elif values.get(key) is bool:
			height = maxf(height, option_art.checked.get_height())
		row_heights.append(height)
		total_height += maxf(data.row_step, height + 2) if index < entries.size() - 1 else height
	var row_y := minf(buttons[0].position.y, footer.position.y - 4 - total_height) if not buttons.is_empty() else 0.0
	var focus_controls: Array[Control] = []
	for index in entries.size():
		var key: String = entries[index].action
		var button: Button = buttons[index]
		button.position.y = row_y
		row_y += maxf(data.row_step, row_heights[index] + 2)
		if key in ["music_volume", "effects_volume", "sensitivity"]:
			var slider := add_slider(button, key, str(entries[index].text))
			focus_controls.append(slider)
		elif values.get(key) is bool:
			button.icon = option_art.checked if values[key] else option_art.unchecked
			button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				var skin := button.get_theme_stylebox(state)
				skin.content_margin_left = 6
				skin.content_margin_right = 6
				skin.content_margin_top = 0
				skin.content_margin_bottom = 0
			button.size.y = row_heights[index]
			var width: float = button.size.x - button.icon.get_width() - 20
			var text_width: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
			button.add_theme_font_size_override("font_size", maxi(7, mini(int(font.get_meta("source_height")), int(int(font.get_meta("source_height")) * width / maxf(1, text_width)))))
			focus_controls.append(button)
		else:
			focus_controls.append(button)
		focus_controls.back().set_meta("option", key)
	focus_controls.append(footer)
	for index in focus_controls.size():
		var control: Control = focus_controls[index]
		control.focus_neighbor_top = control.get_path_to(focus_controls[posmod(index - 1, focus_controls.size())])
		control.focus_neighbor_bottom = control.get_path_to(focus_controls[(index + 1) % focus_controls.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom
	var target: Control = focus_controls[0]
	for control in focus_controls:
		if not focus_key.is_empty() and control.get_meta("option", "") == focus_key:
			target = control
	target.grab_focus()


func add_slider(background: Button, key: String, caption: String) -> HSlider:
	background.text = ""
	background.focus_mode = Control.FOCUS_NONE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.size.y = option_art.slider_idle.get_height()
	for state in ["normal", "hover", "pressed", "focus"]:
		var skin := StyleBoxTexture.new()
		skin.texture = option_art.slider_idle
		background.add_theme_stylebox_override(state, skin)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.position = background.position + Vector2(6, 1)
	title.size = Vector2(background.size.x - 12, int(font.get_meta("source_height")) + 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
	canvas.add_child(title)
	var slider := HSlider.new()
	slider.position = background.position + Vector2(12, int(font.get_meta("source_height")) + 3)
	slider.size = Vector2(background.size.x - 24, background.size.y - int(font.get_meta("source_height")) - 5)
	slider.min_value = .0005 if key == "sensitivity" else 0.0
	slider.max_value = .008 if key == "sensitivity" else float(options.volume_max)
	slider.step = .0001 if key == "sensitivity" else 1.0
	slider.value = float(values[key]) if key == "sensitivity" else float(values[key]) * options.volume_max
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(state, option_art.grabber)
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var rail := StyleBoxFlat.new()
		var fill: Array = options.rail_fill
		var border: Array = options.rail_border
		rail.bg_color = Color8(fill[0], fill[1], fill[2], fill[3])
		rail.border_color = Color8(border[0], border[1], border[2], border[3])
		rail.set_border_width_all(1)
		rail.content_margin_top = 2
		rail.content_margin_bottom = 2
		slider.add_theme_stylebox_override(state, rail)
	canvas.add_child(slider)
	sliders[key] = slider
	update_slider_caption(title, caption, key, slider.value)
	slider.value_changed.connect(func(amount: float):
		values[key] = amount if key == "sensitivity" else amount / float(options.volume_max)
		update_slider_caption(title, caption, key, amount)
		setting_changed.emit(key, values[key])
	)
	slider.focus_entered.connect(func(): set_slider_focus(background, true))
	slider.focus_exited.connect(func(): set_slider_focus(background, false))
	return slider


func set_slider_focus(background: Button, focused: bool) -> void:
	if not is_instance_valid(background): return
	var skin := StyleBoxTexture.new()
	skin.texture = option_art.slider_selected if focused else option_art.slider_idle
	background.add_theme_stylebox_override("normal", skin)


func update_slider_caption(label: Label, caption: String, key: String, amount: float) -> void:
	label.text = "%s  %.1f" % [caption, amount * 1000.0] if key == "sensitivity" else "%s  %d%%" % [caption, roundi(amount / float(options.volume_max) * 100)]
	var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font.get_meta("source_height"))).x
	label.add_theme_font_size_override("font_size", maxi(7, mini(int(font.get_meta("source_height")), int(int(font.get_meta("source_height")) * label.size.x / maxf(1, width)))))


func handle_action(action: String) -> void:
	if action == "back":
		back()
	elif action in ["controls", "audio", "display", "help"]:
		show_section(action)
	elif action == "language":
		var languages: Array[String] = library.available_languages()
		if not languages.is_empty():
			setting_changed.emit("language", languages[(languages.find(library.language_code) + 1) % languages.size()])
	elif action == "aspect_ratio":
		var ratios: Array = preload("res://src/presentation/display_settings.gd").RATIOS.keys()
		values[action] = ratios[(ratios.find(values.get(action, "auto")) + 1) % ratios.size()]
		setting_changed.emit(action, values[action])
		show_section(section, action)
	elif values.get(action) is bool:
		values[action] = not values[action]
		setting_changed.emit(action, values[action])
		show_section(section, action)


func back() -> void:
	if section == "options":
		back_requested.emit()
	elif section == "help":
		show_section("controls", "help")
	else:
		show_section("options", section)
