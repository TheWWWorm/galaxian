extends Control
## Source artwork and layout for an acknowledged one- or two-button dialog.
## The owning screen pauses gameplay and decides what each choice means.
signal chosen(index: int)
var library
var declarations := {}
var message := ""
var captions: Array[String] = []
var buttons: Array[Rect2] = []
var selection := 0
var pressed := -1
var pointer := -2
var keyboard_down := false
var geometry := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)


func present(data, layout: Dictionary, text: String, labels: Array[String] = []) -> void:
	library = data
	declarations = layout
	message = text
	captions.assign(labels if not labels.is_empty() else [str(layout.default_caption)])
	selection = 0
	pressed = -1
	pointer = -2
	keyboard_down = false
	buttons.clear()
	visible = true
	queue_redraw()


func measure() -> Dictionary:
	if library == null or declarations.is_empty() or captions.size() < 1 or captions.size() > 2:
		return {}
	var art := {}
	for key in declarations.images:
		art[key] = library.ui_image(declarations.images[key])
		art[key].filter_clip = true
	var layout: Dictionary = declarations.layout
	var glyph_height: float = library.radio_glyphs().values()[0].size.y
	var lines: PackedStringArray = preload("res://src/presentation/bitmap_font.gd").wrap_lines(library, 
		message, art.cap.get_width() - layout.text_padding
	)
	var panel_y := float(layout.base_y) - maxf(0, lines.size() - layout.short_lines) * glyph_height
	var height: float = (
		art.cap.get_height()
		+ (lines.size() + layout.extra_rows) * art.body.get_height()
		+ art.bottom.get_height()
	)
	if captions.size() == 2:
		height += art.middle.get_height()
	# Preserve native geometry at normal lengths. Fit unusually long localized
	# messages inside the viewport instead of losing their confirmation button.
	var canvas := Vector2(480, maxf(320, height + 16))
	if panel_y < 0 or panel_y + height > canvas.y:
		panel_y = (canvas.y - height) * .5
	var factor := preload("res://src/presentation/bitmap_font.gd").composition_scale(size, canvas)
	return {
		"art": art,
		"lines": lines,
		"glyph_height": glyph_height,
		"factor": factor,
		"origin": (size - canvas * factor) * .5,
		"panel":
		Rect2(
			Vector2((canvas.x - art.cap.get_width()) * .5, panel_y),
			Vector2(art.cap.get_width(), height)
		)
	}


func _draw() -> void:
	buttons.clear()
	geometry = measure()
	if geometry.is_empty():
		return
	var art: Dictionary = geometry.art
	var panel: Rect2 = geometry.panel
	var layout: Dictionary = declarations.layout
	var factor: float = geometry.factor
	draw_set_transform(geometry.origin, 0, Vector2.ONE * factor)
	draw_texture(art.cap, panel.position)
	var y: float = panel.position.y + art.cap.get_height()
	for index in geometry.lines.size() + int(layout.extra_rows):
		draw_texture(art.body, Vector2(panel.position.x, y + index * art.body.get_height()))
	for index in geometry.lines.size():
		var line: String = geometry.lines[index]
		draw_bitmap(
			line,
			Vector2(
				panel.get_center().x - bitmap_width(line) * .5, y + index * geometry.glyph_height
			)
		)
	y += (geometry.lines.size() + layout.extra_rows) * art.body.get_height()
	for index in captions.size():
		var base: Texture2D = art.bottom if index == captions.size() - 1 else art.middle
		var at := Vector2(panel.position.x, y)
		draw_texture(base, at)
		var button: Texture2D = art.selected if selection == index else art.idle
		var button_at := at + Vector2(layout.button_x, 0)
		draw_texture(button, button_at)
		draw_bitmap(
			captions[index],
			Vector2(
				panel.get_center().x - bitmap_width(captions[index]) * .5, y + layout.button_text_y
			)
		)
		buttons.append(Rect2(geometry.origin + button_at * factor, button.get_size() * factor))
		y += base.get_height()
	draw_set_transform(Vector2.ZERO)


func bitmap_width(text: String) -> float:
	return preload("res://src/presentation/bitmap_font.gd").text_width(library, text)

func draw_bitmap(text: String, at: Vector2) -> void:
	preload("res://src/presentation/bitmap_font.gd").draw_text(self, library, text, at)

func accept(index: int) -> void:
	if not visible or index < 0 or index >= captions.size():
		return
	visible = false
	pointer = -2
	pressed = -1
	keyboard_down = false
	chosen.emit(index)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or declarations.is_empty():
		return
	if event is InputEventKey and not event.echo:
		if event.physical_keycode in [KEY_UP, KEY_DOWN, KEY_TAB]:
			if event.pressed and not keyboard_down and pointer == -2:
				selection = (selection + 1) % captions.size()
		elif event.physical_keycode in [KEY_ENTER, KEY_SPACE]:
			confirm_event(event.pressed)
		else:
			return
	elif event is InputEventJoypadButton:
		if event.button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN]:
			if event.pressed and not keyboard_down and pointer == -2:
				selection = (selection + 1) % captions.size()
		elif event.button_index == JOY_BUTTON_A:
			confirm_event(event.pressed)
		else:
			return
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.device != InputEvent.DEVICE_ID_EMULATION
	):
		pointer_event(-1, event.position, event.pressed)
	elif event is InputEventScreenTouch:
		pointer_event(event.index, event.position, event.pressed)
	else:
		return
	queue_redraw()
	get_viewport().set_input_as_handled()


func confirm_event(down: bool) -> void:
	if pointer != -2:
		return
	if down:
		keyboard_down = true
		pressed = selection
	elif keyboard_down:
		accept(pressed)


func pointer_event(id: int, at: Vector2, down: bool) -> void:
	if keyboard_down:
		return
	if down and pointer == -2:
		for index in buttons.size():
			if buttons[index].has_point(at):
				pointer = id
				pressed = index
				selection = index
				break
	elif not down and pointer == id:
		var index := pressed
		pointer = -2
		pressed = -1
		if index >= 0 and buttons[index].has_point(at):
			accept(index)
	queue_redraw()
