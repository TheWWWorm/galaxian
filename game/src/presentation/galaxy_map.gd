extends Control
## Native navigation over the imported quadrant/system/station hierarchy.
signal destination_selected(index: int)
signal back_requested
const Travel = preload("res://src/simulation/travel.gd")
var BOARD := Rect2()
var BACK := Rect2()
var embedded := false
var layout := {}
var library
var session
var level := 0
var quadrant := 0
var system := 0
var selected := 0
var pointer := -2
var pressed := -1
var art := {}
var icons := {}


func _ready() -> void:
	layout = library.content.map_ui.layout
	BOARD = Rect2(layout.board[0], layout.board[1], layout.board[2], layout.board[3])
	var foot: Dictionary = library.content.briefing_ui.footer
	var back_art: Texture2D = library.ui_image(foot.normal)
	BACK = Rect2(Vector2(foot.margin,foot.y),back_art.get_size())
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	for key in library.content.map_ui.images:
		art[key] = library.ui_image(library.content.map_ui.images[key])
	art.back = library.ui_image(library.content.briefing_ui.footer.normal)
	art.tab = library.ui_image(library.content.station_ui.images.tab_single_selected)
	for index in library.stations.size():
		icons[index] = library.station_map_icon(index)
	selected = int(library.station_definition(session.station_id).quadrant)
	resized.connect(queue_redraw)
	visibility_changed.connect(clear_pointer)
	get_window().focus_exited.connect(clear_pointer)


func scale_factor() -> float:
	return minf(size.x / 480.0, size.y / 320.0)


func origin() -> Vector2:
	return (size - Vector2(480, 320) * scale_factor()) * .5


func entries() -> Array[int]:
	var result: Array[int] = []
	var count: int = (
		library.quadrants.size()
		if level == 0
		else library.systems.size() / library.quadrants.size()
	)
	var first := 0
	if level == 2:
		count = library.stations.size() / library.systems.size()
		first = system * count
	elif level == 1:
		first = quadrant * count
	for index in count:
		result.append(first + index)
	return result


func columns() -> int:
	return int(
		(
			library.content.map_ui.grid.quadrant_columns
			if level == 0
			else library.content.map_ui.grid.system_columns
		)
	)


func entry_point(index: int) -> Vector2:
	if level == 2:
		return (
			BOARD.position
			+ (
				library.station_definition(index).position
				/ float(library.content.map_ui.grid.system_extent)
				* BOARD.size
			)
		)
	var local: int = (
		index
		if level == 0
		else index - quadrant * int(library.systems.size() / library.quadrants.size())
	)
	var dimensions := Vector2(columns(), entries().size() / columns())
	return (
		BOARD.position
		+ (
			(Vector2(local % columns(), local / columns()) + Vector2.ONE * .5)
			/ dimensions
			* BOARD.size
		)
	)


func entry_name(index: int) -> String:
	if level == 0:
		return str(library.quadrants[index][0])
	if level == 1:
		return str(library.systems[index][0])
	return library.station_name(index)


func player_point() -> Vector2:
	var station: Dictionary = library.station_definition(session.station_id)
	var grid: Dictionary = library.content.map_ui.grid
	if level == 2:
		return entry_point(session.station_id) if int(station.system) == system else Vector2.INF
	if level == 1 and int(station.quadrant) != quadrant:
		return Vector2.INF
	var world: Vector2 = library.galaxy_position(session.station_id)
	var extent := Vector2(
		float(grid.quadrant_extent) * int(grid.quadrant_columns),
		float(grid.quadrant_extent) * int(library.quadrants.size() / grid.quadrant_columns)
	)
	if level == 1:
		world -= (
			Vector2(quadrant % int(grid.quadrant_columns), quadrant / int(grid.quadrant_columns))
			* float(grid.quadrant_extent)
		)
		extent = Vector2.ONE * float(grid.quadrant_extent)
	return BOARD.position + world / extent * BOARD.size


static func valid_layout(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["box", "board", "galaxy_origin", "stars_origin", "nebula_origin"]:
		var count := 4 if key in ["box", "board"] else 2
		if not value.get(key) is Array or value[key].size() != count:
			return false
		if not value[key].all(func(v): return Travel.integer(v) and v >= 0 and v <= 480):
			return false
		if count == 4 and (value[key][2] <= 0 or value[key][3] <= 0 or value[key][0] + value[key][2] > 480 or value[key][1] + value[key][3] > 320):
			return false
	for key in ["position_label", "exploration_label", "grid_color", "cursor_color", "position_color"]:
		if not Travel.integer(value.get(key)) or value[key] < 0 or value[key] > 0xffffffff:
			return false
	for key in ["separator", "percent_prefix", "percent_suffix", "exploration_suffix", "distance_suffix"]:
		if not value.get(key) is String or value[key].is_empty():
			return false
	return true


func selected_caption(id: int) -> String:
	var caption := entry_name(id)
	if level == 0:
		var explored := 0
		for index in session.visited:
			if int(library.station_definition(index).quadrant) == id:
				explored += 1
		caption += str(layout.separator) + library.text(int(library.content.map_ui.labels.quadrant))
		caption += str(layout.percent_prefix) + str(int(100.0 * explored / (library.stations.size() / library.quadrants.size()))) + str(layout.percent_suffix)
	return caption


func selected_distance(id: int) -> String:
	var world: Vector2
	var grid: Dictionary = library.content.map_ui.grid
	if level == 2:
		world = Travel.source_position(library, id, true)
	else:
		var local := (entry_point(id) - BOARD.position) / BOARD.size
		if level == 0:
			world = local * Vector2(int(grid.quadrant_columns), library.quadrants.size() / int(grid.quadrant_columns)) * float(grid.quadrant_extent)
		else:
			world = (local + Vector2(quadrant % int(grid.quadrant_columns), quadrant / int(grid.quadrant_columns))) * float(grid.quadrant_extent)
	var delta: Vector2 = world - Travel.source_position(library, session.station_id, false)
	var distance := Travel.rounded_distance(Travel.single(delta.length_squared()), library.content.travel.distance_resolution)
	return str(int(distance)) + str(layout.distance_suffix)


func _draw() -> void:
	if library == null or art.is_empty():
		return
	draw_set_transform(origin(), 0, Vector2.ONE * scale_factor())
	var background: String = ["galaxy", "stars", "nebula"][level]
	var at: Array = layout[background + "_origin"]
	# Keep original scale/origin, including the few pixels beneath the atlas
	# frame. The opaque surrounding artwork masks the excess star/nebula image.
	draw_texture(art[background], Vector2(at[0],at[1]))
	var choices := entries()
	var selected_id: int = choices[clampi(selected, 0, choices.size() - 1)]
	if level < 2:
		var cells := Vector2(columns(), choices.size() / columns())
		var cell_size := BOARD.size / cells
		var corner := entry_point(selected_id) - cell_size * .5
		draw_texture_rect(art.quadrant_highlight if level == 0 else art.system_highlight, Rect2(corner, cell_size), false)
		for x in int(cells.x) + 1:
			draw_line(BOARD.position + Vector2(x * cell_size.x, 0), BOARD.position + Vector2(x * cell_size.x, BOARD.size.y), Color.hex(int(layout.grid_color)))
		for y in int(cells.y) + 1:
			draw_line(BOARD.position + Vector2(0, y * cell_size.y), BOARD.position + Vector2(BOARD.size.x, y * cell_size.y), Color.hex(int(layout.grid_color)))
	else:
		for id in choices:
			var icon: Texture2D = icons[id]
			draw_texture(icon, entry_point(id) - icon.get_size() * .5)
	var marker := entry_point(selected_id)
	for key in ["selection", "selection_ring"]:
		draw_texture(art[key], marker - art[key].get_size() * .5)
	draw_line(Vector2(marker.x,BOARD.position.y), Vector2(marker.x,BOARD.end.y), Color.hex(int(layout.cursor_color)))
	draw_line(Vector2(BOARD.position.x,marker.y), Vector2(BOARD.end.x,marker.y), Color.hex(int(layout.cursor_color)))
	var caption := selected_caption(selected_id)
	var distance := selected_distance(selected_id)
	var width := maxf(bitmap_width(caption),bitmap_width(distance))
	var caption_gap: float = art.selection.get_width() * .5
	var caption_x := marker.x + caption_gap
	if caption_x + width > BOARD.end.x - 5:
		caption_x = maxf(BOARD.position.x + 5, marker.x - caption_gap - width)
	var caption_y := clampf(marker.y - 14, BOARD.position.y + 5, BOARD.end.y - 30)
	draw_bitmap(caption,Vector2(caption_x,caption_y),BOARD.end.x - caption_x - 5)
	draw_bitmap(distance,Vector2(caption_x,caption_y + 20),BOARD.end.x - caption_x - 5)
	var player := player_point()
	if player.is_finite():
		draw_texture(art.position, player - art.position.get_size() * .5)
		var label: String = library.text(int(layout.position_label))
		var label_x := player.x + 10
		if label_x + bitmap_width(label) > BOARD.end.x:
			label_x = maxf(BOARD.position.x + 5, player.x - 10 - bitmap_width(label))
		draw_bitmap(label, Vector2(label_x,clampf(player.y, BOARD.position.y + 5, BOARD.end.y - 15)),BOARD.end.x - label_x - 5, Color.hex(int(layout.position_color)))
	draw_rect(BOARD,Color.hex(int(layout.cursor_color)),false)
	# The original atlas already contains the surrounding frame and gradients.
	draw_texture(art.background_left,Vector2.ZERO)
	draw_texture(art.background_right,Vector2(480 - art.background_right.get_width(),0))
	var edge: Vector2 = art.background_right.get_size()
	draw_texture_rect(art.background_right,Rect2(Vector2(480,320)-edge,Vector2(edge.x,-edge.y)),false)
	draw_texture_rect(art.background_right,Rect2(Vector2(0,320-edge.y),-edge),false)
	var tab_at := Vector2(layout.box[0],layout.box[1])
	draw_texture(art.tab,tab_at)
	var title: String = library.text(int(library.content.map_ui.labels.map)).to_upper()
	draw_bitmap(title,tab_at + Vector2((art.tab.get_width()-bitmap_width(title))*.5,6),art.tab.get_width())
	var rate := int(100.0 * session.visited.size() / library.stations.size())
	var explored: String = str(rate) + str(layout.exploration_suffix) + library.text(int(layout.exploration_label))
	draw_bitmap(explored, Vector2((480-bitmap_width(explored))*.5,6),460)
	if not embedded:
		draw_texture_rect(art.back,BACK,false)
		draw_bitmap(library.text(int(library.content.map_ui.labels.back)),BACK.position + Vector2(17,6),70)
	draw_set_transform(Vector2.ZERO)


func bitmap_width(value: String) -> float:
	return preload("res://src/presentation/bitmap_font.gd").text_width(library, value)

func draw_bitmap(value: String, point: Vector2, width: float, tint := Color.WHITE) -> void:
	preload("res://src/presentation/bitmap_font.gd").draw_text(self, library, value, point, width, tint)

func clear_pointer() -> void:
	pointer = -2
	pressed = -2


func reveal(index: int) -> void:
	var station: Dictionary = library.station_definition(index)
	quadrant = int(station.quadrant)
	system = int(station.system)
	level = 2
	selected = int(station.orbit)
	queue_redraw()


func back() -> void:
	if level == 0:
		back_requested.emit()
		return
	level -= 1
	selected = (
		quadrant if level == 0 else system % int(library.systems.size() / library.quadrants.size())
	)
	queue_redraw()


func activate(index: int) -> void:
	if index < 0:
		back()
		return
	var choices := entries()
	if index >= choices.size():
		return
	selected = index
	if level == 0:
		quadrant = choices[index]
		level = 1
		selected = 0
	elif level == 1:
		system = choices[index]
		level = 2
		selected = 0
	else:
		destination_selected.emit(choices[index])
	queue_redraw()


func hit(point: Vector2) -> int:
	if not embedded and BACK.has_point(point):
		return -1
	if not BOARD.has_point(point):
		return -2
	var choices := entries()
	if level < 2:
		var cell := (
			(point - BOARD.position) / BOARD.size * Vector2(columns(), choices.size() / columns())
		)
		return int(cell.y) * columns() + int(cell.x)
	var closest := -2
	var distance := 24.0
	for index in choices.size():
		var candidate := point.distance_to(entry_point(choices[index]))
		if candidate < distance:
			closest = index
			distance = candidate
	return closest


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
		return
	if event is InputEventScreenTouch and event.canceled:
		if pointer == event.index:
			clear_pointer()
		accept_event()
		return
	if event is InputEventMouseMotion and pointer == -2:
		var target := hit((event.position - origin()) / scale_factor())
		if target >= 0:
			selected = target
			queue_redraw()
		return
	if (
		event is InputEventScreenTouch
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	):
		var finger: int = event.index if event is InputEventScreenTouch else -1
		var target := hit((event.position - origin()) / scale_factor())
		if event.pressed and pointer == -2:
			grab_focus()
			pointer = finger
			pressed = target
		elif not event.pressed and pointer == finger:
			var activate_target := target == pressed and target >= -1
			clear_pointer()
			accept_event()
			if activate_target:
				activate(target)
			return
		accept_event()
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		back()
		return
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		activate(selected)
		return
	elif event.is_action_pressed("ui_left"):
		selected = posmod(selected - 1, entries().size())
	elif event.is_action_pressed("ui_right"):
		selected = (selected + 1) % entries().size()
	elif event.is_action_pressed("ui_up"):
		selected = posmod(selected - (columns() if level < 2 else 1), entries().size())
	elif event.is_action_pressed("ui_down"):
		selected = (selected + (columns() if level < 2 else 1)) % entries().size()
	else:
		return
	accept_event()
	queue_redraw()
