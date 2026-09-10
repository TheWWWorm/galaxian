extends "res://src/presentation/station_menu.gd"
## Native quantity transaction using the supplied SellCargoWindow art and labels.
signal cancelled
signal confirmed(amount: int)
var entry: Dictionary
var amount := 0
var maximum := 0
var panel_position := Vector2.ZERO
var action_y := 0.0
var body_rows := 0
var confirm_button: Button
var minus_button: Button
var plus_button: Button


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary or not value.get("images") is Dictionary or not value.get("labels") is Dictionary:
		return false
	for key in ["top", "middle", "action_row", "bottom", "button", "button_pressed", "step", "step_pressed"]:
		var binding: Variant = value.images.get(key)
		if not binding is Dictionary or not Combat.integer(binding.get("texture")) or not Combat.integer(binding.get("region")):
			return false
		if binding.texture < 0 or binding.region < 0:
			return false
	for key in ["sell", "cancel"]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	for key in ["y", "body_rows", "step_x", "step_gap", "step_bottom", "button_x"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 320:
			return false
	if value.body_rows < 1 or value.body_rows > 16:
		return false
	for key in ["minus", "plus", "suffix"]:
		if not value.get(key) is String or value[key].is_empty():
			return false
	return true


func configure(source, record: Dictionary) -> void:
	library = source
	entry = record.duplicate(true)
	maximum = int(entry.count)
	amount = maximum
	data = library.content.hangar_ui.quantity
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	for key in data.images:
		art[key] = library.ui_image(data.images[key])
		art[key].filter_clip = true
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	panel_position = Vector2((480 - art.top.get_width()) * .5, data.y)
	# One additional repeat of the supplied middle strip reserves the native price total.
	body_rows = int(data.body_rows) + ceili(float(int(font.get_meta("source_height")) + 4) / art.middle.get_height())
	action_y = panel_position.y + art.top.get_height() + art.middle.get_height() * body_rows
	minus_button = make_button(data.minus, "minus", art.step, art.step_pressed)
	plus_button = make_button(data.plus, "plus", art.step, art.step_pressed)
	for index in 2:
		var button: Button = minus_button if index == 0 else plus_button
		button.size = art.step.get_size()
		button.position = Vector2(panel_position.x + data.step_x + index * (button.size.x + data.step_gap), action_y - button.size.y - data.step_bottom)
	confirm_button = make_button(library.text(int(data.labels.sell)), "sell", art.button, art.button_pressed)
	var cancel := make_button(library.text(int(data.labels.cancel)), "back", art.button, art.button_pressed)
	confirm_button.position = Vector2(panel_position.x + data.button_x, action_y)
	cancel.position = Vector2(confirm_button.position.x, action_y + art.action_row.get_height())
	confirm_button.size = art.button.get_size()
	cancel.size = art.button.get_size()
	actions = [minus_button, plus_button, confirm_button, cancel]
	# Keep keyboard/controller traversal inside the modal, even with hidden parent controls.
	for index in actions.size():
		actions[index].focus_next = actions[index].get_path_to(actions[(index + 1) % actions.size()])
		actions[index].focus_previous = actions[index].get_path_to(actions[posmod(index - 1, actions.size())])
	action_requested.connect(handle_action)
	update_amount()
	layout_canvas()
	confirm_button.grab_focus()


func handle_action(action: String) -> void:
	match action:
		"minus": amount = maxi(0, amount - 1)
		"plus": amount = mini(maximum, amount + 1)
		"back": cancelled.emit()
		"sell":
			if amount > 0 and amount <= maximum:
				confirmed.emit(amount)
	update_amount()


func update_amount() -> void:
	minus_button.disabled = amount == 0
	plus_button.disabled = amount == maximum
	confirm_button.disabled = amount == 0
	queue_redraw()


func _process(_delta: float) -> void:
	pass


func _draw() -> void:
	if canvas == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, .62))
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	draw_texture(art.top, panel_position)
	var y: float = panel_position.y + art.top.get_height()
	for index in body_rows:
		draw_texture(art.middle, Vector2(panel_position.x, y + index * art.middle.get_height()))
	draw_texture(art.action_row, Vector2(panel_position.x, action_y))
	draw_texture(art.bottom, Vector2(panel_position.x, action_y + art.action_row.get_height()))
	var width: float = art.top.get_width()
	write(library.item_name(int(entry.id)), Rect2(panel_position + Vector2(8, 5), Vector2(width - 16, 20)), HORIZONTAL_ALIGNMENT_CENTER)
	var icon: Texture2D = library.ui_image(library.content.hangar_ui.pictures.item_icons[int(entry.id)])
	if icon != null:
		draw_texture(icon, Vector2(panel_position.x + 10, y))
	write(str(amount) + data.suffix, Rect2(Vector2(panel_position.x + width * .5, y), Vector2(width * .5 - 8, 20)), HORIZONTAL_ALIGNMENT_RIGHT)
	# The native total makes a multi-unit sale reviewable before applying it.
	write("%d credits" % (amount * int(entry.price)), Rect2(Vector2(panel_position.x + 8, y + 23), Vector2(width - 16, 20)), HORIZONTAL_ALIGNMENT_CENTER)
	draw_set_transform(Vector2.ZERO)
