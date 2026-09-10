extends "res://src/presentation/station_menu.gd"
## Original full-screen map with a native search drawer and accessible controls.
signal destination_selected(index: int)
signal back_requested
var chart
var search_panel: Panel
var search_field: LineEdit
var search_results: ItemList
var search_ids: Array[int] = []
var search_button: Button


func configure(source, pilot) -> void:
	library = source
	session = pilot
	data = library.content.station_ui
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	chart = preload("res://src/presentation/galaxy_map.gd").new()
	chart.library = library
	chart.session = session
	chart.embedded = true
	chart.size = Vector2(480,320)
	canvas.add_child(chart)
	chart.destination_selected.connect(func(index): destination_selected.emit(index))
	chart.back_requested.connect(func(): back_requested.emit())
	var foot: Dictionary = library.content.briefing_ui.footer
	var idle: Texture2D = library.ui_image(foot.normal)
	var selected: Texture2D = library.ui_image(foot.pressed)
	var back := make_button(library.text(int(library.content.map_ui.labels.back)),"back",idle,selected)
	back.position = Vector2(foot.margin,foot.y)
	back.size = idle.get_size()
	search_button = make_button("Search","search",idle,selected)
	mirror_button(search_button)
	search_button.position = Vector2(480-foot.margin-idle.get_width(),foot.y)
	search_button.size = idle.get_size()
	search_button.tooltip_text = "Search stations (F / controller X)"
	actions = [back,search_button]
	search_panel = Panel.new()
	search_panel.position = chart.BOARD.position
	search_panel.size = chart.BOARD.size
	var skin := StyleBoxFlat.new()
	skin.bg_color = color(data.fill)
	skin.bg_color.a = .97
	skin.border_color = color(data.border)
	skin.set_border_width_all(1)
	search_panel.add_theme_stylebox_override("panel",skin)
	canvas.add_child(search_panel)
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search stations…"
	search_field.position = Vector2(8,8)
	search_field.size = Vector2(search_panel.size.x-16,26)
	search_field.add_theme_font_override("font",font)
	search_field.add_theme_font_size_override("font_size",int(font.get_meta("source_height")))
	search_panel.add_child(search_field)
	search_results = ItemList.new()
	search_results.position = Vector2(8,40)
	search_results.size = search_panel.size-Vector2(16,48)
	search_results.add_theme_font_override("font",font)
	search_results.add_theme_font_size_override("font_size",int(font.get_meta("source_height")))
	search_results.add_theme_constant_override("v_separation",12)
	search_results.fixed_icon_size = Vector2i(20,20)
	search_panel.add_child(search_results)
	search_results.item_activated.connect(select_result)
	# A tap/click selects a destination; keyboard/controller selection remains
	# browsable until confirmation, as on the graphical chart.
	search_results.item_clicked.connect(func(index, _at, button):
		if button == MOUSE_BUTTON_LEFT: select_result(index)
	)
	search_field.text_changed.connect(filter_stations)
	search_field.text_submitted.connect(func(_query):
		if not search_ids.is_empty():
			search_results.select(0)
			search_results.grab_focus()
	)
	action_requested.connect(func(action):
		if action == "back": back()
		elif action == "search": set_search(not search_panel.visible)
	)
	filter_stations("")
	set_search(false)
	layout_canvas()


func _draw() -> void:
	# Letterbox outside the original canvas; the chart supplies its own frame.
	draw_rect(Rect2(Vector2.ZERO,size),Color.BLACK)


func set_search(open: bool) -> void:
	search_panel.visible = open
	chart.mouse_filter = Control.MOUSE_FILTER_IGNORE if open else Control.MOUSE_FILTER_STOP
	chart.focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL
	chart.clear_pointer()
	search_button.text = library.text(int(library.content.map_ui.labels.map)) if open else "Search"
	if open: search_field.grab_focus()
	else: chart.grab_focus()


func back() -> void:
	if search_panel.visible:
		set_search(false)
	else:
		chart.back()


func restore_focus() -> void:
	if search_panel.visible: search_results.grab_focus()
	else: chart.grab_focus()


func filter_stations(query: String) -> void:
	search_results.clear()
	search_ids.clear()
	for index in library.stations.size():
		var station: String = library.station_name(index)
		if not query.is_empty() and not station.to_lower().contains(query.to_lower()):
			continue
		search_ids.append(index)
		search_results.add_item(station,library.station_map_icon(index))


func select_result(index: int) -> void:
	if index >= 0 and index < search_ids.size():
		destination_selected.emit(search_ids[index])


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or search_panel == null:
		return
	var shortcut: bool = (
		(event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X)
		or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F and not search_panel.visible)
	)
	if shortcut:
		set_search(not search_panel.visible)
		get_viewport().set_input_as_handled()
