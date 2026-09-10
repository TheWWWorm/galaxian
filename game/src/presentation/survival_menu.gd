extends Control
## Source-defined survival Info/Highscore pages over the owner's menu backdrop.
## Receives a profile snapshot; flight and persistence transitions belong to owner.
signal start_requested
signal back_requested
const BitmapFont = preload("res://src/presentation/bitmap_font.gd")
var library
var declarations := {}
var records := {}
var art := {}
var canvas: Control
var font: FontFile
var tabs: Array[Button] = []
var footer: Array[Button] = []
var info: ScrollContainer
var info_body: Control
var table: Control
var active_tab := 0
var highlight_run := 0
var awaiting_owner := false
var table_divider_y := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(layout_canvas)


func present(
	data, menu: Dictionary, profile: Dictionary, recent_run: int = 0, tab: int = 0
) -> void:
	if canvas != null:
		remove_child(canvas)
		canvas.queue_free()
	library = data
	declarations = menu
	records = profile.duplicate(true)
	highlight_run = recent_run
	awaiting_owner = false
	font = BitmapFont.create(library)
	art.clear()
	for key in menu.presentation.images:
		art[key] = library.ui_image(menu.presentation.images[key])
		art[key].filter_clip = true
	art.picture = library.ui_image(menu.picture)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	tabs.clear()
	for index in menu.tabs.size():
		var button := make_button("")
		button.pressed.connect(select_tab.bind(index))
		button.focus_entered.connect(queue_redraw)
		button.focus_exited.connect(queue_redraw)
		tabs.append(button)
	footer.clear()
	for index in 2:
		var button := make_button(library.text(int(menu.back if index == 0 else menu.start)))
		button.pressed.connect(leave_menu.bind(index == 1))
		button.focus_entered.connect(queue_redraw)
		button.focus_exited.connect(queue_redraw)
		button.mouse_entered.connect(queue_redraw)
		button.mouse_exited.connect(queue_redraw)
		footer.append(button)
	make_info()
	make_table()
	select_tab(clampi(tab, 0, tabs.size() - 1))
	show()
	layout_canvas()
	tabs[active_tab].grab_focus()


func label(
	text: String, at: Vector2, width: float, parent: Control = null, color: Color = Color.WHITE
) -> Label:
	var result := Label.new()
	result.text = text
	result.position = at
	result.size = Vector2(width, int(font.get_meta("source_height")))
	result.clip_text = true
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", font)
	result.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
	result.add_theme_color_override("font_color", color)
	(parent if parent != null else canvas).add_child(result)
	return result


func make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_color_override("font_" + state + "_color", Color.WHITE)
	button.add_theme_color_override("font_color", Color.WHITE)
	canvas.add_child(button)
	return button


func make_info() -> void:
	info = ScrollContainer.new()
	info.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	info.position = Vector2(declarations.content_origin[0], declarations.content_origin[1])
	info.size = Vector2(declarations.text_width, declarations.content_height)
	canvas.add_child(info)
	info_body = Control.new()
	info_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(info_body)
	var body: String = (
		"%s\n\n%s\n\n%s"
		% [
			library.text(int(declarations.title)).to_upper(),
			library.text(int(declarations.description)),
			library.text(int(declarations.strengths))
		]
	)
	var lines: PackedStringArray = preload("res://src/presentation/bitmap_font.gd").wrap_lines(library, body, declarations.text_width)
	var y := 0.0
	for line in lines:
		label(line, Vector2(0, y), declarations.text_width, info_body)
		y += maxf(int(font.get_meta("source_height")), info_body.get_child(-1).get_combined_minimum_size().y)
	for row in declarations.legend:
		var image: Texture2D = library.ui_image(row.image)
		var height := maxf(image.get_height(), font.get_height(int(font.get_meta("source_height"))) + 3)
		var icon := TextureRect.new()
		icon.texture = image
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(0, y + (height - image.get_height()) * .5)
		info_body.add_child(icon)
		var x := image.get_width() + float(declarations.presentation.score_gap)
		label(
			library.text(int(row.text)),
			Vector2(x, y + (height - int(font.get_meta("source_height"))) * .5),
			declarations.text_width - x,
			info_body
		)
		y += height
	info_body.custom_minimum_size = Vector2(declarations.text_width, y)


func make_table() -> void:
	table = Control.new()
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(table)
	var layout: Dictionary = declarations.table
	var height := float(int(font.get_meta("source_height")))
	var y: float = (
		height
		+ layout.line_base
		- floorf(height * 2 / layout.header_height_divisor)
		- layout.header_padding
	)
	var columns: Array = layout.columns
	var headers: Array[Label] = []
	for column in 3:
		var width: float = (
			(columns[column + 1] if column < 2 else layout.line_end) - columns[column]
		)
		headers.append(label(
			library.text(int(layout[["rank", "name", "score"][column]])),
			Vector2(columns[column], y), width, table
		))
	var text_size := int(font.get_meta("source_height"))
	table_divider_y = height + layout.line_base
	if not BitmapFont.is_mobile():
		# Native fonts have different ascent and line spacing. Fit the complete
		# imported leaderboard inside its frame, including a separate header rule.
		var bottom: float = declarations.frame[1] + declarations.frame[3] - 10
		while true:
			height = 0
			for header in headers:
				header.add_theme_font_size_override("font_size", text_size)
				height = maxf(height, header.get_combined_minimum_size().y)
			var needed: float = height * (records.entries.size() + 1) + 11 + max(0, records.entries.size() - 1) * layout.row_gap
			if y + needed <= bottom or text_size <= 8:
				break
			text_size -= 1
		for header in headers:
			header.size.y = height
		table_divider_y = y + height + 3
		y = table_divider_y + 8
	else:
		y += height * 2
	var tint: Array = layout.highlight
	for index in records.entries.size():
		var row: Dictionary = records.entries[index]
		var color := (
			Color8(tint[0], tint[1], tint[2], tint[3])
			if highlight_run > 0 and row.run == highlight_run
			else Color.WHITE
		)
		var rank := (str(layout.rank_zero) if index + 1 < 10 else "") + str(index + 1)
		var fields := [rank, str(row.name), str(int(row.score))]
		for column in 3:
			var width: float = (
				(columns[column + 1] if column < 2 else layout.line_end) - columns[column]
			)
			var cell := label(fields[column], Vector2(columns[column], y), width, table, color)
			cell.add_theme_font_size_override("font_size", text_size)
			cell.size.y = height
		y += height + layout.row_gap


func select_tab(index: int) -> void:
	active_tab = clampi(index, 0, tabs.size() - 1)
	info.visible = active_tab == 0
	table.visible = active_tab == 1
	queue_redraw()


func leave_menu(start: bool) -> void:
	if awaiting_owner or not is_visible_in_tree():
		return
	awaiting_owner = true
	if start:
		start_requested.emit()
	else:
		back_requested.emit()


func retry_action() -> void:
	awaiting_owner = false


func layout_canvas() -> void:
	if canvas == null:
		return
	var factor := preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	canvas.position = (size - Vector2(480, 320) * factor) * .5
	canvas.scale = Vector2.ONE * factor
	canvas.size = Vector2(480, 320)
	var frame: Array = declarations.frame
	var tab_size: Vector2 = art.tab_selected.get_size()
	for index in tabs.size():
		tabs[index].position = Vector2(frame[0] + index * (tab_size.x - 1), frame[1])
		tabs[index].size = tab_size
		if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
			tabs[index].position.x = frame[0] + float(frame[2]) * index / tabs.size()
			tabs[index].size.x = float(frame[2]) / tabs.size()
	var layout: Dictionary = library.content.briefing_ui.footer
	var texture: Texture2D = library.ui_image(layout.normal)
	for index in footer.size():
		footer[index].position = Vector2(
			layout.margin if index == 0 else 480 - layout.margin - texture.get_width(), layout.y
		)
		footer[index].size = texture.get_size()
	queue_redraw()


func draw_text(
	text: String,
	at: Vector2,
	width: float = -1,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	draw_string(font, at + Vector2(0, int(font.get_meta("source_height"))), text, align, width, int(font.get_meta("source_height")))


static func rank_index(points: int, ranks: Array) -> int:
	var result := 0
	for index in ranks.size():
		if points > int(ranks[index].points):
			result = index
	return result


func _draw() -> void:
	if canvas == null:
		return
	draw_set_transform(canvas.position, 0, canvas.scale)
	var frame: Array = declarations.frame
	var shape: Dictionary = declarations.presentation
	var top: float = frame[1] + art.tab_selected.get_height()
	var rect := Rect2(frame[0], top, frame[2], frame[3] - art.tab_selected.get_height())
	var inset: Vector2 = art.corner.get_size()
	var fill: Array = shape.fill
	var border: Array = shape.border
	var ink := Color8(border[0], border[1], border[2], border[3])
	draw_rect(
		Rect2(rect.position + Vector2(inset.x, 0), rect.size - Vector2(inset.x * 2, 0)),
		Color8(fill[0], fill[1], fill[2], fill[3])
	)
	for side in 2:
		draw_rect(
			Rect2(
				rect.position + Vector2(side * (rect.size.x - inset.x), inset.y),
				Vector2(inset.x, rect.size.y - inset.y * 2)
			),
			Color8(fill[0], fill[1], fill[2], fill[3])
		)
	# Central fill is drawn once; source corner art supplies the curved ends.
	for row in 2:
		for side in 2:
			var image: Texture2D = art.tab_corner if row == 0 and side == 0 else art.corner
			var at := (
				rect.position
				+ Vector2(side * (rect.size.x - inset.x), row * (rect.size.y - inset.y))
			)
			draw_texture_rect(
				image, Rect2(at, inset * Vector2(-1 if side else 1, -1 if row else 1)), false
			)
		draw_line(
			Vector2(rect.position.x + inset.x, rect.position.y + row * (rect.size.y - 1)),
			Vector2(rect.end.x - inset.x, rect.position.y + row * (rect.size.y - 1)),
			ink
		)
	for side in 2:
		draw_line(
			Vector2(rect.position.x + side * (rect.size.x - 1), rect.position.y + inset.y),
			Vector2(rect.position.x + side * (rect.size.x - 1), rect.end.y - inset.y),
			ink
		)
	for index in tabs.size():
		draw_texture_rect(
			art.tab_selected if active_tab == index else art.tab_idle,
			Rect2(
				tabs[index].position,
				tabs[index].size * Vector2(-1 if index == tabs.size() - 1 else 1, 1)
			),
			false
		)
		if tabs[index].has_focus() and index != active_tab:
			draw_rect(Rect2(tabs[index].position, tabs[index].size), ink, false)
		var caption_y: float = shape.caption_y
		if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
			var text_size := int(font.get_meta("source_height"))
			caption_y = (tabs[index].size.y - font.get_height(text_size)) * .5 + font.get_ascent(text_size) - text_size
		draw_text(
			library.text(int(declarations.tabs[index])).to_upper(),
			tabs[index].position + Vector2(0, caption_y),
			tabs[index].size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	if active_tab == 0:
		var at := Vector2(shape.right_origin[0], shape.right_origin[1])
		draw_texture(art.preview, at)
		draw_texture(
			art.preview_overlay, at + (art.preview.get_size() - art.preview_overlay.get_size()) * .5
		)
		var bar := at + Vector2(0, art.preview.get_height() + shape.score_gap)
		draw_texture(art.score_bar, bar)
		draw_text(
			library.text(int(shape.highscore)),
			bar + Vector2(shape.score_text_offset[0], shape.score_text_offset[1])
		)
		draw_text(
			str(int(records.entries[0].score)),
			bar + Vector2(0, shape.score_text_offset[1]),
			art.score_bar.get_width() - shape.score_right_padding,
			HORIZONTAL_ALIGNMENT_RIGHT
		)
		var rank: Dictionary = shape.ranks[rank_index(int(records.points), shape.ranks)]
		draw_text(
			library.text(int(rank.text)).to_upper(),
			Vector2(shape.rank_origin[0], shape.rank_origin[1])
		)
		draw_texture(
			art.picture,
			Vector2(shape.picture_center[0], shape.picture_center[1]) - art.picture.get_size() * .5
		)
	else:
		var line: Dictionary = declarations.table
		draw_line(
			Vector2(line.columns[0], table_divider_y),
			Vector2(line.line_end, table_divider_y),
			Color.WHITE
		)
	var layout: Dictionary = library.content.briefing_ui.footer
	for index in footer.size():
		var image: Texture2D = library.ui_image(
			(
				layout.pressed
				if footer[index].has_focus() or footer[index].is_hovered()
				else layout.normal
			)
		)
		draw_texture_rect(
			image,
			Rect2(footer[index].position, footer[index].size * Vector2(-1 if index else 1, 1)),
			false
		)
	draw_set_transform(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or canvas == null or awaiting_owner:
		return
	if event.is_action_pressed("ui_cancel"):
		leave_menu(false)
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		select_tab((active_tab + 1) % tabs.size())
		tabs[active_tab].grab_focus()
	elif (
		active_tab == 0 and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"))
	):
		info.scroll_vertical += int(font.get_meta("source_height")) * (1 if event.is_action_pressed("ui_down") else -1)
	else:
		return
	get_viewport().set_input_as_handled()
