extends Control
## A native photo mode. Only the inspection camera moves; the flight is untouched.
signal closed(resume: bool)
var flight
var music: AudioStreamPlayer
var saved_music_pause := false
var saved_process_mode: int
var saved_camera := Transform3D.IDENTITY
var saved_fov := 0.0
var saved_ship_visible := true
var saved_audio: Array = []
var restored := false
var pivot := Vector3.ZERO
var initial_pivot := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var distance := 43.0
var minimum_distance := 5.0
var toolbar: PanelContainer
var controls_visible := true
var fingers := {}
var pinch_distance := 0.0
var pinch_center := Vector2.ZERO


func configure(source, soundtrack: AudioStreamPlayer) -> void:
	flight = source
	music = soundtrack
	saved_camera = flight.camera.global_transform
	saved_fov = flight.camera.fov
	saved_ship_visible = flight.ship.visible
	saved_process_mode = flight.process_mode
	flight.process_mode = Node.PROCESS_MODE_DISABLED
	pause_audio(flight)
	saved_music_pause = music.stream_paused
	music.stream_paused = true
	flight.ship.show()
	initial_pivot = flight.ship.global_position
	minimum_distance = maxf(
		2,
		(
			flight.library.actor_radius(
				int(flight.library.content.tables.buyable_ships[flight.session.ship_id])
			)
			* 1.5
		)
	)
	reset_camera()
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	build_toolbar()


func pause_audio(node: Node) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer3D:
		saved_audio.append([node, node.stream_paused])
		node.stream_paused = true
	for child in node.get_children():
		pause_audio(child)


func restore_scene() -> void:
	if restored:
		return
	restored = true
	if is_instance_valid(flight):
		flight.camera.global_transform = saved_camera
		flight.camera.fov = saved_fov
		flight.ship.visible = saved_ship_visible
		flight.process_mode = saved_process_mode
		flight.backdrop.follow(flight.camera)
	for record in saved_audio:
		if is_instance_valid(record[0]):
			record[0].stream_paused = record[1]
	if is_instance_valid(music):
		music.stream_paused = saved_music_pause


func _exit_tree() -> void:
	restore_scene()


func build_toolbar() -> void:
	toolbar = PanelContainer.new()
	add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var mobile := preload("res://src/presentation/bitmap_font.gd").is_mobile()
	var factor := preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	toolbar.offset_top = -minf(size.y * .45, 115 * factor)
	var rows := VBoxContainer.new()
	toolbar.add_child(rows)
	var hint := Label.new()
	hint.text = (
		"ACTION FREEZE · Drag to orbit · Two fingers to pan / zoom"
		if mobile
		else "ACTION FREEZE · Drag to orbit · Right-drag to pan · Wheel to zoom"
	)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", roundi(13 * factor))
	rows.add_child(hint)
	var actions := HFlowContainer.new()
	actions.alignment = FlowContainer.ALIGNMENT_CENTER
	rows.add_child(actions)
	for item in [
		["−", zoom.bind(1.15)],
		["+", zoom.bind(1.0 / 1.15)],
		["Reset camera", reset_camera],
		["Hide UI", toggle_ui],
		["Back to pause", func(): closed.emit(false)],
		["Resume", func(): closed.emit(true)]
	]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(52, 38) * factor
		button.add_theme_font_size_override("font_size", roundi(13 * factor))
		button.pressed.connect(item[1])
		actions.add_child(button)
	var footer := Label.new()
	footer.text = (
		"Double-tap to show hidden controls"
		if mobile
		else "H: show controls · P / Esc: back · Controller: right stick orbit, left stick pan, triggers zoom, Y hide, X reset"
	)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_font_size_override("font_size", roundi(11 * factor))
	rows.add_child(footer)


func toggle_ui() -> void:
	controls_visible = not controls_visible
	toolbar.visible = controls_visible


func reset_camera() -> void:
	pivot = initial_pivot
	flight.camera.global_transform = saved_camera
	flight.camera.fov = saved_fov
	var offset: Vector3 = saved_camera.origin - pivot
	if offset.length() < minimum_distance:
		offset = saved_camera.basis.z * maxf(flight.follow_distance, minimum_distance)
		flight.camera.global_position = pivot + offset
	distance = offset.length()
	yaw = atan2(offset.x, offset.z)
	pitch = asin(clampf(offset.y / distance, -.9999, .9999))
	flight.backdrop.follow(flight.camera)


func orbit(movement: Vector2) -> void:
	yaw -= movement.x * .006
	pitch = clampf(pitch + movement.y * .006, -PI * .47, PI * .47)
	apply_camera()


func pan(movement: Vector2) -> void:
	pivot += (
		(flight.camera.global_basis.x * -movement.x + flight.camera.global_basis.y * movement.y)
		* distance
		* .0015
	)
	apply_camera()


func zoom(multiplier: float) -> void:
	distance = clampf(distance * multiplier, minimum_distance, 3000)
	apply_camera()


func apply_camera() -> void:
	flight.camera.global_position = (
		pivot + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	)
	flight.camera.look_at(pivot, Vector3.UP)
	flight.backdrop.follow(flight.camera)
	flight.lens_flare._process(0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			orbit(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			pan(event.relative)
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0 / 1.12)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.12)
	elif event is InputEventScreenTouch:
		if event.pressed:
			if event.double_tap:
				toggle_ui()
			fingers[event.index] = event.position
		else:
			fingers.erase(event.index)
		pinch_distance = 0
	elif event is InputEventScreenDrag and fingers.has(event.index):
		fingers[event.index] = event.position
		if fingers.size() == 1:
			orbit(event.relative)
		elif fingers.size() == 2:
			var positions := fingers.values()
			var span: float = positions[0].distance_to(positions[1])
			var center: Vector2 = (positions[0] + positions[1]) * .5
			if pinch_distance > 0 and span > 0:
				zoom(pinch_distance / span)
				pan(center - pinch_center)
			pinch_distance = span
			pinch_center = center
	accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H:
				toggle_ui()
			KEY_P, KEY_ESCAPE:
				closed.emit(false)
			KEY_R:
				reset_camera()
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_Y:
				toggle_ui()
			JOY_BUTTON_X:
				reset_camera()
			JOY_BUTTON_B, JOY_BUTTON_START:
				closed.emit(false)
			_:
				return
		get_viewport().set_input_as_handled()


func _process(seconds: float) -> void:
	var devices := Input.get_connected_joypads()
	if devices.is_empty():
		return
	var device: int = devices[0]
	var look := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)
	)
	if look.length() > .15:
		orbit(look * seconds * 150)
	var slide := Vector2(
		Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	)
	if slide.length() > .15:
		pan(slide * seconds * 150)
	var zoom_axis := (
		Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
		- Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	)
	if absf(zoom_axis) > .1:
		zoom(exp(zoom_axis * seconds))
