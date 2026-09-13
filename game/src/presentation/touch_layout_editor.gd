extends Control
## Places the touch controls by hand. The live HUD keeps drawing them, so what a
## player drags is the control itself rather than a stand-in, and the panel sits
## in the empty middle of the screen the flight controls deliberately leave free.
const TouchLayout = preload("res://src/presentation/touch_layout.gd")
const BitmapFont = preload("res://src/presentation/bitmap_font.gd")
signal closed(layout: Dictionary)
var hud
var working := {}
var restore := {}
var defaults := {}
var selected := ""
var finger := -1
var grab := Vector2.ZERO
var dragged := false
var panel: PanelContainer
var caption: Label
var factor := 1.0


func configure(source) -> void:
	hud = source
	restore = TouchLayout.sanitize(hud.flight.settings.get("touch_layout", {}))
	working = restore.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud.layout_preview = true
	hud.refresh_navigation_controls()
	# A phone turned mid-edit gives the HUD a different composition, so the
	# anchors a drag is measured against have to be taken again.
	hud.resized.connect(capture_defaults)
	capture_defaults()
	build_panel()
	select(TouchLayout.IDS[-1])


func capture_defaults() -> void:
	## Measure each control where the imported composition puts it, so a drag is
	## always an offset from that anchor however far the last one wandered.
	hud.flight.settings["touch_layout"] = {}
	hud.layout_artwork()
	for id in TouchLayout.IDS:
		var rect: Rect2 = hud.control_rect(id)
		defaults[id] = (rect.position + rect.size * .5) / hud.factor
	apply()


func apply() -> void:
	hud.flight.settings["touch_layout"] = working
	hud.layout_artwork()
	hud.refresh_navigation_controls()
	factor = hud.factor
	queue_redraw()
	refresh_caption()


func build_panel() -> void:
	factor = hud.factor
	# The controls leave the middle of the screen free, which is where the panel
	# belongs. A center container re-centers it on every layout pass, so it never
	# depends on the panel's size being known before its rows are built.
	var middle := CenterContainer.new()
	add_child(middle)
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	middle.add_child(panel)
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var title := Label.new()
	title.text = "ADJUST CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", roundi(13 * factor))
	rows.add_child(title)
	var hint := Label.new()
	hint.text = (
		"Drag any control to move it. Tap one to select, then resize it."
		if BitmapFont.is_mobile()
		else "Drag any control to move it. Click one to select, then resize it."
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = minf(hud.size.x * .8, 260 * factor)
	hint.add_theme_font_size_override("font_size", roundi(11 * factor))
	rows.add_child(hint)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", roundi(12 * factor))
	rows.add_child(caption)
	var sizing := HFlowContainer.new()
	sizing.alignment = FlowContainer.ALIGNMENT_CENTER
	rows.add_child(sizing)
	for item in [
		["Smaller", resize.bind(-TouchLayout.SCALE_STEP)],
		["Bigger", resize.bind(TouchLayout.SCALE_STEP)],
		["Reset this", reset_selected],
	]:
		sizing.add_child(action_button(item[0], item[1]))
	var finishing := HFlowContainer.new()
	finishing.alignment = FlowContainer.ALIGNMENT_CENTER
	rows.add_child(finishing)
	for item in [
		["Reset all", reset_all],
		["Cancel", func(): closed.emit(restore)],
		["Done", func(): closed.emit(working)],
	]:
		finishing.add_child(action_button(item[0], item[1]))


func action_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(58, 34) * factor
	button.add_theme_font_size_override("font_size", roundi(12 * factor))
	button.pressed.connect(action)
	return button


func refresh_caption() -> void:
	if caption == null:
		return
	caption.text = (
		"%s · %d%%"
		% [
			TouchLayout.NAMES.get(selected, selected),
			roundi(TouchLayout.scale_of(working, selected) * 100)
		]
	)


func select(id: String) -> void:
	selected = id
	refresh_caption()
	queue_redraw()


func resize(step: float) -> void:
	if selected.is_empty():
		return
	var scale := clampf(
		TouchLayout.scale_of(working, selected) + step, TouchLayout.MIN_SCALE, TouchLayout.MAX_SCALE
	)
	working = TouchLayout.adjusted(
		working, selected, TouchLayout.offset_of(working, selected), scale
	)
	apply()


func reset_selected() -> void:
	if selected.is_empty():
		return
	working.erase(selected)
	apply()


func reset_all() -> void:
	working = {}
	apply()


func at(point: Vector2) -> String:
	## IDS runs small controls first so an overlapping pair picks the one whose
	## rectangle a finger is least likely to have meant by accident.
	for id in TouchLayout.IDS:
		if hud.control_rect(id).has_point(point):
			return id
	return ""


func move_to(point: Vector2) -> void:
	if selected.is_empty():
		return
	var home: Vector2 = defaults.get(selected, Vector2.ZERO)
	# Stop at the point where the whole control is still on screen, so the stored
	# offset and the placed control never disagree about where the finger is.
	var half: Vector2 = hud.control_rect(selected).size * .5
	var placed := (point - grab).clamp(half, hud.size - half)
	working = TouchLayout.adjusted(
		working, selected, placed / factor - home, TouchLayout.scale_of(working, selected)
	)
	apply()


func begin(point: Vector2, index: int) -> bool:
	var id := at(point)
	if id.is_empty():
		return false
	select(id)
	var rect: Rect2 = hud.control_rect(id)
	grab = point - (rect.position + rect.size * .5)
	finger = index
	dragged = false
	# The panel would otherwise sit between a player and the place they are
	# dragging a control to; it returns the moment the finger lifts.
	panel.hide()
	return true


func finish() -> void:
	finger = -1
	dragged = false
	panel.show()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			begin(event.position, event.index)
		elif event.index == finger:
			finish()
		accept_event()
	elif event is InputEventScreenDrag and event.index == finger:
		dragged = true
		move_to(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			begin(event.position, -2)
		elif finger == -2:
			finish()
		accept_event()
	elif event is InputEventMouseMotion and finger == -2:
		dragged = true
		move_to(event.position)
		accept_event()


func _exit_tree() -> void:
	if is_instance_valid(hud):
		hud.layout_preview = false
		hud.refresh_navigation_controls()


func _draw() -> void:
	if hud == null or not is_instance_valid(hud):
		return
	for id in TouchLayout.IDS:
		var rect: Rect2 = hud.control_rect(id)
		if rect.size.x <= 0:
			continue
		var chosen := id == selected
		var grown := rect.grow(3 * factor)
		draw_rect(grown, Color(0, .08, .12, .35 if chosen else .18), true)
		draw_rect(
			grown, Color("7defff") if chosen else Color("2f8ea0"), false, maxf(1, factor * .9), true
		)
