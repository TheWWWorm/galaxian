extends Control
## Original name-entry composition with native editing, IME and virtual keyboard.
## The owner retains the defeated run until it successfully commits the submitted
## name. Cancelling leaves that pending result intact.
signal submitted(pilot: String)
signal cancelled
const BitmapFont = preload("res://src/presentation/bitmap_font.gd")
const Frame = preload("res://src/presentation/panel.gd")
var library
var declarations := {}
var canvas: Control
var entry: LineEdit
var prompt: Label
var confirm: Button
var controller_down := false
var awaiting_owner := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	build_controls()
	resized.connect(layout_controls)
	visibility_changed.connect(clear_input)
	get_window().focus_exited.connect(clear_input)


func build_controls() -> void:
	if canvas != null:
		return
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	entry = LineEdit.new()
	entry.alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.virtual_keyboard_enabled = true
	entry.expand_to_text_length = false
	entry.text_submitted.connect(func(_value): submit_name())
	entry.text_changed.connect(func(_value): update_confirmation())
	canvas.add_child(entry)
	prompt = Label.new()
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(prompt)
	confirm = Button.new()
	confirm.pressed.connect(submit_name)
	canvas.add_child(confirm)


func present(data, menu: Dictionary, previous: String = "") -> void:
	build_controls()
	library = data
	declarations = menu.name_entry
	awaiting_owner = false
	controller_down = false
	var font := BitmapFont.create(library)
	var height := int(font.get_meta("source_height"))
	for control in [entry, prompt, confirm]:
		control.add_theme_font_override("font", font)
		control.add_theme_font_size_override("font_size", height)
		control.add_theme_color_override("font_color", Color.WHITE)
		control.add_theme_color_override("font_focus_color", Color.WHITE)
		control.add_theme_constant_override("outline_size", 0)
	entry.editable = true
	entry.max_length = int(declarations.limit)
	entry.text = previous.left(entry.max_length)
	entry.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	entry.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	entry.add_theme_color_override("font_uneditable_color", Color.WHITE)
	entry.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	entry.add_theme_color_override("caret_color", Color.WHITE)
	entry.add_theme_color_override("selection_color", Color(.25, .6, .65, .65))
	prompt.text = library.text(int(declarations.prompt))
	# The original uses the iPhone keyboard's return key. Keep the source Next
	# artwork as an additional visible action for desktop, touch and controllers.
	var footer: Dictionary = library.content.briefing_ui.footer
	confirm.text = library.text(int(library.content.briefing_ui.labels.next))
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = library.ui_image(
			footer.center_normal if state in ["normal", "disabled"] else footer.center_pressed
		)
		confirm.add_theme_stylebox_override(state, style)
	confirm.add_theme_color_override("font_disabled_color", Color(.5, .5, .5))
	update_confirmation()
	show()
	layout_controls()
	focus_entry.call_deferred()


func focus_entry() -> void:
	if is_visible_in_tree() and not awaiting_owner:
		entry.grab_focus()
		entry.caret_column = entry.text.length()


func layout_controls() -> void:
	if declarations.is_empty() or size.x <= 0 or size.y <= 0:
		return
	var factor := preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	canvas.position = (size - Vector2(480, 320) * factor) * .5
	canvas.scale = Vector2.ONE * factor
	canvas.size = Vector2(480, 320)
	var height := int(entry.get_theme_font("font").get_meta("source_height"))
	entry.position = Vector2(declarations.input[0], declarations.input[1])
	entry.size = Vector2(declarations.width, height * declarations.height_lines)
	prompt.position = Vector2(0, declarations.prompt_y)
	prompt.size = Vector2(480, height)
	var footer: Dictionary = library.content.briefing_ui.footer
	var texture: Texture2D = library.ui_image(footer.center_normal)
	confirm.position = Vector2((480 - texture.get_width()) * .5, footer.y)
	confirm.size = texture.get_size()
	queue_redraw()


func update_confirmation() -> void:
	confirm.disabled = awaiting_owner or entry.text.strip_edges().is_empty()


func submit_name() -> void:
	if not is_visible_in_tree() or awaiting_owner:
		return
	var pilot := entry.text.strip_edges().left(int(declarations.limit))
	if pilot.is_empty():
		focus_entry()
		return
	awaiting_owner = true
	entry.editable = false
	update_confirmation()
	entry.release_focus()
	submitted.emit(pilot)


func retry_submission() -> void:
	# A failed archive write must permit retry without losing the entered name.
	awaiting_owner = false
	entry.editable = true
	update_confirmation()
	focus_entry()


func clear_input() -> void:
	controller_down = false
	if entry != null and entry.has_focus():
		entry.release_focus()


func _draw() -> void:
	if declarations.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	draw_set_transform(canvas.position, 0, canvas.scale)
	var frame: Array = declarations.frame
	Frame.draw(self, library, Rect2(frame[0], frame[1], frame[2], frame[3]))
	var fill: Array = declarations.fill
	var border: Array = declarations.border
	var rect := Rect2(entry.position, entry.size)
	draw_rect(rect, Color8(fill[0], fill[1], fill[2], fill[3]))
	draw_rect(rect, Color8(border[0], border[1], border[2], border[3]), false)
	draw_set_transform(Vector2.ZERO)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or declarations.is_empty() or awaiting_owner:
		return
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A:
		if event.pressed:
			controller_down = true
		elif controller_down:
			controller_down = false
			submit_name()
	elif (
		(
			event is InputEventKey
			and event.physical_keycode == KEY_ESCAPE
			and event.pressed
			and not event.echo
		)
		or (
			event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed
		)
	):
		hide()
		cancelled.emit()
	else:
		return
	get_viewport().set_input_as_handled()
