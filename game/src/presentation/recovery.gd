extends Control
## Original recovery text, cargo icons, bitmap font and shared window artwork.
const Frame = preload("res://src/presentation/panel.gd")
signal acknowledged
var library
var receipt := {}
var button_rect := Rect2()
var panel_rect := Rect2()
var pointer := -2
var key_down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)


func bitmap_width(text: String) -> float:
	return preload("res://src/presentation/bitmap_font.gd").text_width(library, text)

func draw_bitmap(text: String, position: Vector2) -> void:
	preload("res://src/presentation/bitmap_font.gd").draw_text(self, library, text, position)

func _draw() -> void:
	if library == null or receipt.is_empty():
		return
	var data: Dictionary = library.content.recovery
	var layout: Dictionary = data.layout
	var factor := preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	var origin := (size - Vector2(480, 320) * factor) * .5
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var measure: Texture2D = library.ui_image(data.images.row_measure)
	var icon: Texture2D = library.ui_image(data.images.empty)
	var stride := icon.get_height() + float(layout.row_gap)
	var height: float = library.radio_glyphs().values()[0].size.y
	var width := float(measure.get_width())
	var quantity_width := bitmap_width(str(layout.quantity_column))
	for item in receipt.items:
		width = maxf(
			width,
			(
				quantity_width
				+ bitmap_width(library.item_name(int(item.id)))
				+ icon.get_width()
				+ float(layout.width_padding) * 3
			)
		)
	var message: String = library.text(
		int(
			(
				data.labels.recovered
				if not receipt.items.is_empty()
				else data.labels.full if receipt.full else data.labels.empty
			)
		)
	)
	var lines: PackedStringArray = preload("res://src/presentation/bitmap_font.gd").wrap_lines(library, message, width)
	var body_height := (lines.size() + 1) * height + 1
	var panel_size := Vector2(
		width + float(layout.width_padding),
		stride * (receipt.items.size() + 1) + body_height + height
	)
	panel_rect = Rect2((Vector2(480, 320) - panel_size) * .5, panel_size)
	Frame.draw(self, library, panel_rect)
	var title: String = library.text(int(data.labels.title)).to_upper()
	draw_bitmap(
		title,
		Vector2(
			panel_rect.position.x + (panel_size.x - bitmap_width(title)) * .5,
			panel_rect.position.y + float(layout.title_y)
		)
	)
	var pen := panel_rect.position + Vector2(float(layout.row_x), stride)
	for line in lines:
		draw_bitmap(line, pen)
		pen.y += height
	var fill: Array = layout.fill
	var border: Array = layout.border
	for index in receipt.items.size():
		var item: Dictionary = receipt.items[index]
		var at := (
			panel_rect.position
			+ Vector2(float(layout.row_x), stride + body_height + stride * index)
		)
		var row := Rect2(
			at, Vector2(width, measure.get_height() + float(layout.row_height_padding))
		)
		draw_rect(row, Color8(fill[0], fill[1], fill[2], fill[3]))
		draw_rect(row, Color8(border[0], border[1], border[2], border[3]), false)
		draw_bitmap(
			str(int(item.amount)) + str(layout.quantity_suffix),
			at + Vector2(float(layout.row_x), float(layout.text_y))
		)
		draw_bitmap(
			library.item_name(int(item.id)), at + Vector2(quantity_width, float(layout.text_y))
		)
		var cargo_icon: Texture2D = library.ui_image(data.images.items[str(int(item.id))])
		draw_texture(
			cargo_icon,
			Vector2(
				row.end.x - float(layout.icon_right) - cargo_icon.get_width(),
				at.y + (row.size.y - cargo_icon.get_height()) * .5
			)
		)
	var footer: Dictionary = library.content.briefing_ui.footer
	var texture: Texture2D = library.ui_image(
		footer.center_pressed if pointer != -2 or key_down else footer.center_normal
	)
	var at := Vector2(
		(480 - texture.get_width()) * .5,
		minf(float(footer.y), panel_rect.end.y + float(layout.row_gap))
	)
	draw_texture(texture, at)
	var text: String = library.text(int(library.content.briefing_ui.labels.next))
	draw_bitmap(
		text,
		(
			at
			+ Vector2(
				(texture.get_width() - bitmap_width(text)) * .5,
				(texture.get_height() - height) * .5
			)
		)
	)
	button_rect = Rect2(origin + at * factor, texture.get_size() * factor)
	draw_set_transform(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not visible or receipt.is_empty():
		return
	if event is InputEventKey and event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
		if not event.echo:
			if event.pressed:
				key_down = true
			elif key_down:
				key_down = false
				acknowledged.emit()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		if event.pressed:
			key_down = true
		elif key_down:
			key_down = false
			acknowledged.emit()
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.device != InputEvent.DEVICE_ID_EMULATION
	):
		pointer_event(-1, event.position, event.pressed)
	elif event is InputEventScreenTouch:
		pointer_event(event.index, event.position, event.pressed)


func pointer_event(id: int, at: Vector2, down: bool) -> void:
	if down and pointer == -2 and button_rect.has_point(at):
		pointer = id
	elif not down and pointer == id:
		pointer = -2
		if button_rect.has_point(at):
			acknowledged.emit()
	queue_redraw()
	get_viewport().set_input_as_handled()
