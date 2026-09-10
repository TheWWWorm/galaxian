extends Control
## Confirmation-driven source pages; no flight simulation or auto-advance timer.
const DialogueFrame = preload("res://src/presentation/panel.gd")
signal next_requested
signal back_requested
signal skip_requested
var library
var scene_fade := 0.0
var cue := {}
var lines := PackedStringArray()
var portrait: Texture2D
var buttons: Array[Rect2] = []
var pressed := -1
var pointer := -2
var key_down := -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	resized.connect(queue_redraw)


func present(chapter: int, page: int) -> void:
	cue = library.briefing_cue(chapter, page)
	portrait = null if int(cue.get("speaker", -1)) < 0 else library.radio_portrait(int(cue.speaker))
	var width: float = library.content.briefing_ui.text_width
	if portrait != null:
		width -= portrait.get_width()
	lines = (
		preload("res://src/presentation/bitmap_font.gd").wrap_lines(library, library.text(int(cue.text)), width)
		if not cue.is_empty()
		else PackedStringArray()
	)
	queue_redraw()


func composition_scale() -> float:
	return preload("res://src/presentation/bitmap_font.gd").composition_scale(size)


func composition_origin() -> Vector2:
	return (size - Vector2(480, 320) * composition_scale()) * .5


func set_scene_fade(value: float) -> void:
	scene_fade = clampf(value,0,1)
	if scene_fade > 0:
		pressed = -1
		pointer = -2
		key_down = -1
		buttons.clear()
	queue_redraw()


func _draw() -> void:
	if scene_fade > 0:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0,0,0,scene_fade))
		return
	if cue.is_empty():
		return
	var layout: Dictionary = library.content.briefing_ui
	var origin := composition_origin()
	var factor := composition_scale()
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var panel := Rect2(layout.panel[0], layout.panel[1], layout.panel[2], layout.panel[3])
	var line_height: float = library.radio_glyphs().values()[0].size.y
	var extra := maxf(0, lines.size() * line_height + 20 - panel.size.y)
	panel.position.y -= extra
	panel.size.y += extra
	DialogueFrame.draw(self, library, panel)
	if portrait != null:
		var point: Array = layout.portrait_left if cue.left else layout.portrait_right
		var position := Vector2(point[0], point[1] - extra)
		if not cue.left:
			position.x -= portrait.get_width()
		draw_texture(portrait, position)
	var pen := Vector2(layout.text_origin[0], layout.text_origin[1] - extra)
	if portrait != null and cue.left:
		pen.x += portrait.get_width()
	if lines.size() > 4:
		pen.y -= line_height * .5
	for line in lines:
		draw_bitmap(line, pen)
		pen.y += line_height
	buttons.clear()
	var footer: Dictionary = layout.footer
	for index in 3:
		var center := index == 2
		var binding: Dictionary = footer[
			("center_" if center else "") + ("pressed" if pressed == index else "normal")
		]
		var texture: Texture2D = library.ui_image(binding)
		var x: float = footer.margin if index == 0 else 480 - footer.margin - texture.get_width()
		if center:
			x = (480 - texture.get_width()) * .5
		var rect := Rect2(Vector2(x, footer.y), texture.get_size())
		buttons.append(Rect2(origin + rect.position * factor, rect.size * factor))
		if index == 1:
			draw_texture_rect(
				texture, Rect2(rect.position, Vector2(-rect.size.x, rect.size.y)), false
			)
		else:
			draw_texture_rect(texture, rect, false)
		var label_id: int = (
			layout.labels.skip
			if center
			else (layout.labels.first_back if cue.page == 0 else layout.labels.back)
		)
		if index == 1:
			label_id = layout.labels.start if cue.page + 1 == cue.count else layout.labels.next
		var text: String = library.text(label_id)
		var offset: float = 0 if center else (4 if index == 0 else -4)
		draw_bitmap(
			text, Vector2(x + (rect.size.x - bitmap_width(text)) * .5 + offset, footer.y + 9)
		)
	draw_set_transform(Vector2.ZERO)


func bitmap_width(text: String) -> float:
	return preload("res://src/presentation/bitmap_font.gd").text_width(library, text)

func draw_bitmap(text: String, position: Vector2) -> void:
	preload("res://src/presentation/bitmap_font.gd").draw_text(self, library, text, position)

func activate(index: int) -> void:
	if scene_fade > 0: return
	match index:
		0:
			back_requested.emit()
		1:
			next_requested.emit()
		2:
			skip_requested.emit()


func _input(event: InputEvent) -> void:
	if scene_fade > 0 and is_visible_in_tree():
		get_viewport().set_input_as_handled()
		return
	if not visible or cue.is_empty() or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if (
		event is InputEventKey
		and event.physical_keycode in [KEY_ENTER, KEY_RIGHT, KEY_LEFT, KEY_ESCAPE]
	):
		if event.echo:
			get_viewport().set_input_as_handled()
			return
		if event.pressed:
			key_down = event.physical_keycode
		elif key_down == event.physical_keycode:
			key_down = -1
			activate(0 if event.physical_keycode in [KEY_LEFT, KEY_ESCAPE] else 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B]:
		if event.pressed:
			key_down = 100000 + event.button_index
		elif key_down == 100000 + event.button_index:
			key_down = -1
			activate(0 if event.button_index == JOY_BUTTON_B else 1)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# Touch is handled directly; ignore its emulated mouse event.
		if event.device != InputEvent.DEVICE_ID_EMULATION:
			pointer_event(-1, event.position, event.pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		pointer_event(event.index, event.position, event.pressed)
		get_viewport().set_input_as_handled()


func pointer_event(id: int, point: Vector2, down: bool) -> void:
	if down and pointer == -2:
		for index in buttons.size():
			if buttons[index].has_point(point):
				pressed = index
				pointer = id
	elif not down and pointer == id:
		var index := pressed
		pressed = -1
		pointer = -2
		if index >= 0 and buttons[index].has_point(point):
			activate(index)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		pressed = -1
		pointer = -2
		key_down = -1
		queue_redraw()
