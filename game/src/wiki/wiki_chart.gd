extends Control
## The galaxy map of the reference: quadrants, their systems and every planet
## and station, coloured by its people, with places that trade drawn solid.
## A page highlights its own place, system or quadrant. Clicking a place
## opens its page.
signal followed(key: String)

## One colour per people, in the order of the imported race table.
const RACE_COLORS := [
	Color("6fb6ff"), Color("ff6a5c"), Color("c7a6ff"), Color("ffd166"), Color("9be15d"),
	Color("b0bec5"), Color("4dd0c4"), Color("ff9ecd"), Color("ffa94d"), Color("e0e0e0")
]

var points: Array = []
var extent := Vector2.ONE
var system_size := 100.0
var quadrant_columns := 2
var quadrant_size := 500.0
var highlight_station := -1
var highlight_system := -1
var highlight_quadrant := -1
var line := Color("375766")
var accent := Color("ffca79")
var hovered := -1
var catalog


func configure(source, shown: Dictionary) -> void:
	catalog = source
	points = catalog.chart_points()
	extent = catalog.chart_extent()
	var grid: Dictionary = catalog.library.content.map_ui.grid
	system_size = float(grid.system_extent)
	quadrant_size = float(grid.quadrant_extent)
	quadrant_columns = int(grid.quadrant_columns)
	highlight_station = int(shown.get("station", -1))
	highlight_system = int(shown.get("system", -1))
	highlight_quadrant = int(shown.get("quadrant", -1))
	if highlight_station >= 0:
		var station: Dictionary = catalog.library.station_definition(highlight_station)
		highlight_system = int(station.system)
	tooltip_text = ""
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 160)
	queue_redraw()


func area() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size - Vector2(side, side)) * .5, Vector2(side, side))


func to_screen(at: Vector2) -> Vector2:
	var box := area()
	return box.position + at / extent * box.size


func _draw() -> void:
	var box := area()
	draw_rect(box, Color(.02, .05, .08, .9))
	var scale_ := box.size / extent
	var per_row := int(quadrant_size / system_size)
	for quadrant in int(extent.x / quadrant_size * extent.y / quadrant_size):
		var corner := Vector2(quadrant % quadrant_columns, quadrant / quadrant_columns) * quadrant_size
		var rect := Rect2(to_screen(corner), Vector2(quadrant_size, quadrant_size) * scale_)
		if quadrant == highlight_quadrant:
			draw_rect(rect, Color(accent, .1))
		for step in range(1, per_row):
			var offset := step * system_size * scale_.x
			draw_line(rect.position + Vector2(offset, 0), rect.position + Vector2(offset, rect.size.y), Color(line, .35))
			draw_line(rect.position + Vector2(0, offset), rect.position + Vector2(rect.size.x, offset), Color(line, .35))
		draw_rect(rect, Color(accent, .9) if quadrant == highlight_quadrant else line, false, 1.5)
	if highlight_system >= 0:
		var systems_per_quadrant := per_row * per_row
		var quadrant := highlight_system / systems_per_quadrant
		var inner := highlight_system % systems_per_quadrant
		var corner := Vector2(quadrant % quadrant_columns, quadrant / quadrant_columns) * quadrant_size + Vector2(inner % per_row, inner / per_row) * system_size
		var rect := Rect2(to_screen(corner), Vector2(system_size, system_size) * scale_)
		draw_rect(rect, Color(accent, .14))
		draw_rect(rect, accent, false, 1.5)
	var radius := clampf(box.size.x / 260.0, 1.2, 3.0)
	for id in points.size():
		var point: Array = points[id]
		var color: Color = RACE_COLORS[int(point[2]) % RACE_COLORS.size()]
		var at := to_screen(Vector2(point[0], point[1]))
		if int(point[3]) == 1:
			draw_circle(at, radius, color)
		else:
			draw_arc(at, radius, 0, TAU, 8, color, 1.0)
	for id in [highlight_station, hovered]:
		if id >= 0 and id < points.size():
			var at := to_screen(Vector2(points[id][0], points[id][1]))
			draw_arc(at, radius * 3.2, 0, TAU, 20, accent, 2.0)


func nearest(position_: Vector2) -> int:
	var best := -1
	var distance := 14.0 * 14.0
	for id in points.size():
		var gap := to_screen(Vector2(points[id][0], points[id][1])).distance_squared_to(position_)
		if gap < distance:
			distance = gap
			best = id
	return best


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var found := nearest(event.position)
		if found != hovered:
			hovered = found
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var found := nearest(event.position)
		if found >= 0:
			followed.emit("station/%d" % found)
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var found := nearest(at)
	return catalog.station_name(found) if found >= 0 and catalog != null else ""
