extends "res://src/presentation/station_menu.gd"
## Source exchange labels and rows with a native, reviewable equipment transfer.
signal cancelled
signal confirmed(quote: Dictionary)
var quote: Dictionary
var body: Label
var body_scroll: ScrollContainer
var confirm_button: Button
var summary_y := 0.0


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary or not value.get("labels") is Dictionary:
		return false
	if not value.get("colors") is Array or value.colors.size() != 3:
		return false
	if not value.colors.all(func(v): return Combat.integer(v) and v >= 0 and v <= 0xffffffff):
		return false
	for key in ["price", "weapons", "cargo", "remaining", "buy"]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	for key in ["body_y", "row_x", "row_height", "layout_measure_resource"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 65535:
			return false
	if value.row_height <= 0 or value.row_height > 40 or value.body_y > 320 or value.row_x > 240:
		return false
	if not value.get("header") is Array or value.header.size() != 4:
		return false
	if not value.header.all(func(v): return Combat.integer(v) and v >= 0 and v < 480):
		return false
	if value.header[3] <= 0:
		return false
	return (
		value.get("row_offsets") is Array
		and value.row_offsets.size() == 5
		and value.row_offsets.all(func(v): return Combat.integer(v) and abs(v) <= 320)
	)


func configure(source, reviewed: Dictionary) -> void:
	library = source
	quote = reviewed.duplicate(true)
	data = library.content.hangar_ui.exchange
	font = preload("res://src/presentation/bitmap_font.gd").create(library)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var footer: Dictionary = library.content.briefing_ui.footer
	var normal: Texture2D = library.ui_image(footer.normal)
	var pressed: Texture2D = library.ui_image(footer.pressed)
	# The legacy height resource is unavailable; anchor to the supplied footer buttons.
	summary_y = float(footer.y) - normal.get_height()
	var back := make_button(library.text(int(library.content.hangar_ui.labels.back)), "back", normal, pressed)
	back.size = normal.get_size()
	back.position = Vector2(footer.margin, footer.y)
	confirm_button = make_button(library.text(int(data.labels.buy)), "buy", normal, pressed)
	mirror_button(confirm_button)
	confirm_button.size = normal.get_size()
	confirm_button.position = Vector2(480 - footer.margin - normal.get_width(), footer.y)
	confirm_button.disabled = not quote.allowed
	actions = [back, confirm_button]
	body_scroll = ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.position = Vector2(data.row_x, data.body_y)
	body_scroll.size = Vector2(480 - data.header[2], summary_y + data.row_offsets[0] - data.body_y - 5)
	canvas.add_child(body_scroll)
	body = Label.new()
	body.custom_minimum_size.x = body_scroll.size.x - 12
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("font", font)
	body.add_theme_font_size_override("font_size", int(font.get_meta("source_height")))
	body.text = explanation()
	body_scroll.add_child(body)
	var touch = preload("res://src/input/touch_scroll.gd").new()
	touch.scroll = body_scroll
	body_scroll.add_child(touch)
	action_requested.connect(handle_action)
	layout_canvas()
	back.grab_focus()


func explanation() -> String:
	var binding: Dictionary = library.content.hangar_ui.description.ships
	var text: String = library.text(int(binding.base + binding.stride * int(quote.offer.id)))
	text += "\n\n" + preload("res://src/presentation/ship_slots.gd").describe(library, int(quote.offer.id))
	text += "\n\nYour current ship is traded in. All equipment and cargo are kept. Compatible equipment stays mounted; other equipment moves to the hold."
	if not quote.transfer.is_empty():
		var moved: int = quote.transfer.hold.size() - quote.loadout.hold.size()
		var mounted: int = quote.transfer.fitted.filter(func(v): return not v.is_empty()).size()
		text += "\n\n%d mounted; %d moved to the hold." % [mounted, moved]
	if not quote.reason.is_empty():
		text += "\n\n" + str(quote.reason)
	return text


func summary_rows() -> Array:
	var equipment: int = quote.loadout.hold.size() + quote.loadout.fitted.filter(func(v): return not v.is_empty()).size()
	var cargo := 0
	for amount in quote.cargo.values():
		cargo += int(amount)
	return [
		[library.text(int(data.labels.price)), str(int(quote.offer.price))],
		[library.ship_name(int(quote.current_ship)), "−%d" % int(quote.trade_in)],
		[library.text(int(data.labels.weapons)), "%d kept" % equipment],
		[library.text(int(data.labels.cargo)), "%dt kept" % cargo],
		[library.text(int(data.labels.remaining)), str(int(quote.remaining))]
	]


func handle_action(action: String) -> void:
	if action == "back":
		cancelled.emit()
	elif action == "buy" and quote.allowed:
		confirmed.emit(quote.duplicate(true))


func _draw() -> void:
	if canvas == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, .6))
	draw_set_transform(origin, 0, Vector2.ONE * factor)
	var header := Rect2(data.header[0], data.header[1], 480 - data.header[2], data.header[3])
	draw_box(header)
	write(library.ship_name(int(quote.offer.id)), header, HORIZONTAL_ALIGNMENT_CENTER)
	var rows := summary_rows()
	for index in rows.size():
		var rect := Rect2(data.row_x, summary_y + data.row_offsets[index], 480 - data.header[2], data.row_height)
		draw_box(rect)
		write(rows[index][0], Rect2(rect.position + Vector2(2, 0), Vector2(rect.size.x * .5 - 4, rect.size.y)))
		write(rows[index][1], Rect2(rect.position + Vector2(rect.size.x * .5, 0), Vector2(rect.size.x * .5 - 4, rect.size.y)), HORIZONTAL_ALIGNMENT_RIGHT)
	draw_set_transform(Vector2.ZERO)


func draw_box(rect: Rect2) -> void:
	draw_rect(rect, Color.hex(int(data.colors[0])))
	draw_rect(rect, Color.hex(int(data.colors[1])), false)
	draw_rect(rect.grow(-1), Color.hex(int(data.colors[2])), false)


func _process(_delta: float) -> void:
	pass
