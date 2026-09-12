extends SceneTree
## Focused touch HUD checks against existing imported content. All pilots are
## transient; preferences, imports and player saves are never written.
const Library = preload("res://src/content/library.gd")
const Session = preload("res://src/simulation/session.gd")
const BitmapFont = preload("res://src/presentation/bitmap_font.gd")
var checks := 0
var failures := 0
var fingers := {}
var mouse_point := Vector2.ZERO
var capture_directory := ""


class TestMain extends "res://src/main.gd":
	func _ready(): pass
	func _process(_delta): pass
	func save_game(_announce: bool = true) -> bool: return true
	func settings_path(): return "user://touch-hud-unused-settings.cfg"
	func refresh_display() -> void: super._process(0)


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass an existing imported content directory, and optional capture directory, after --")
		quit(2)
		return
	if args.size() > 1:
		capture_directory = args[1]
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open supplied imported content without reimporting")
	if failures:
		quit(1)
		return
	BitmapFont.mobile_cache = 1
	await resize_view(Vector2i(1280, 720))
	var app := TestMain.new()
	root.add_child(app)
	check(not app.settings.touch, "Desktop defaults to hidden touch controls")
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.transient_preview = true
	app.settings.touch = true
	app.settings.music = false
	app.session = Session.new()
	app.session.configure(lib, true)
	app.launch()
	app.flight.set_physics_process(false)
	app.music.stop()
	await settle(app)
	check_original_art(app)
	await check_multitouch(app)
	await check_mouse(app)
	await check_floating_pad(app)
	await check_transparency(app)
	await check_navigation(app)
	await check_cancellation(app)
	await check_layouts(app)
	await check_radio(app)
	await check_preferences(app)
	app.music.stop()
	app.stop_flight()
	app.queue_free()
	for frame in 3:
		await process_frame
	print("TOUCH HUD ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)


func touch(at: Vector2, finger: int, down: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = root.get_final_transform() * at
	event.pressed = down
	event.canceled = canceled
	if down:
		fingers[finger] = at
	else:
		fingers.erase(finger)
	Input.parse_input_event(event)
	await process_frame


func drag(at: Vector2, finger: int) -> void:
	var previous: Vector2 = fingers.get(finger, at)
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = root.get_final_transform() * at
	event.relative = root.get_final_transform().basis_xform(at - previous)
	event.screen_relative = event.relative
	fingers[finger] = at
	Input.parse_input_event(event)
	await process_frame


func tap(control: Control, finger: int = 8) -> void:
	var center := control.get_global_rect().get_center()
	await touch(center, finger, true)
	await touch(center, finger, false)


func mouse_button(at: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = 0
	event.position = root.get_final_transform() * at
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	mouse_point = at
	Input.parse_input_event(event)
	await process_frame


func mouse_drag(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = 0
	event.position = root.get_final_transform() * at
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(at - mouse_point)
	event.screen_relative = event.relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse_point = at
	Input.parse_input_event(event)
	await process_frame


func mouse_click(control: Control) -> void:
	var center := control.get_global_rect().get_center()
	await mouse_button(center, true)
	await mouse_button(center, false)


func settle(app) -> void:
	for frame in 3:
		await process_frame
	app.refresh_display()
	app.hud.refresh_navigation_controls()
	app.hud._process(0)
	app.update_tutorial_controls()
	app.flight.update_camera(1.0)


func throttle_track(hud) -> Rect2:
	var control = hud.throttle_control
	return Rect2(control.global_position + control.track_rect.position, control.track_rect.size)


func open_view(hud) -> Vector2:
	return hud.size * Vector2(.53, .38)


func check_original_art(app) -> void:
	var hud = app.hud
	for action in ["boost", "weapon", "missiles", "pause"]:
		var expected: Texture2D = app.library.ui_image(app.library.content.flight_ui.buttons[action].normal)
		check(hud.buttons[action].texture_normal.get_image().get_data() == expected.get_image().get_data(), "Retain imported " + action + " artwork")
	for key in ["stick_frame", "stick_normal", "fire_frame", "bar", "hull", "shield"]:
		var expected: Texture2D = app.library.ui_image(app.library.content.flight_ui.artwork.images[key])
		check(hud.art[key].get_image().get_data() == expected.get_image().get_data(), "Retain imported " + key + " artwork")
	check(not hud.extra_buttons.has("−") and not hud.extra_buttons.has("+"), "Slider replaces separate throttle minus/plus controls")
	check(not hud.extra_buttons.has("CAMERA") and not hud.extra_buttons.has("FREELOOK"), "Looking around needs no dedicated camera control")
	check(not "%" in hud.throttle_control.speed_text and hud.throttle_control.speed_text.ends_with("m/s"), "Throttle shows actual speed without a percentage scale")


func check_multitouch(app) -> void:
	var hud = app.hud
	var flight = app.flight
	var controls = flight.controls
	var stick: Vector2 = hud.stick_center * hud.factor
	var track := throttle_track(hud)
	var lower := Vector2(track.get_center().x, track.end.y - hud.factor)
	var upper := Vector2(track.get_center().x, track.position.y + hud.factor)
	await touch(stick, 0, true)
	await drag(stick + Vector2(18, 0) * hud.factor, 0)
	var steering: Vector2 = controls.touch_look
	check(steering.x > 0 and is_zero_approx(steering.y), "Imported stick retains rightward steering")
	await touch(lower, 1, true)
	check(is_zero_approx(flight.throttle), "Throttle bottom reaches zero")
	await drag(upper, 1)
	check(is_equal_approx(flight.throttle, 1.0), "Throttle top reaches full cruise")
	check(controls.touch_look == steering, "Throttle finger does not change simultaneous steering")
	await touch(lower, 2, true)
	await drag(lower, 2)
	check(is_equal_approx(flight.throttle, 1.0), "Second throttle finger cannot take over the slider")
	await touch(lower, 2, false)
	await drag(track.get_center(), 1)
	check(is_equal_approx(flight.throttle, .5), "Throttle maps track midpoint to half cruise")
	await touch(track.get_center(), 1, false)
	check(is_equal_approx(flight.throttle, .5) and hud.throttle_finger < 0, "Released throttle retains its selected speed")
	var view := open_view(hud)
	var ship_before: Basis = flight.ship.basis
	flight.update_camera(1.0)
	var camera_before: Transform3D = flight.camera.global_transform
	await touch(view, 3, true)
	await drag(view + Vector2(100, -30), 3)
	flight.update_camera(.1)
	check(not flight.camera.global_transform.is_equal_approx(camera_before), "Dragging open space looks around without a camera button")
	check(flight.ship.basis.is_equal_approx(ship_before) and controls.touch_look == steering, "Look-around changes camera without changing ship heading or steering finger")
	check(not flight.paused, "Looking around leaves flight running")
	var camera_held: Transform3D = flight.camera.global_transform
	await touch(view + Vector2(-100, 0), 4, true)
	await drag(view + Vector2(-180, 80), 4)
	flight.update_camera(.1)
	check(flight.camera.global_transform.is_equal_approx(camera_held), "Second look-around finger cannot move an owned camera")
	await touch(view, 4, false)
	check(hud.camera_finger == 3 and hud.stick_finger == 0, "Unrelated release leaves camera and steering owners intact")
	var fire: Vector2 = hud.buttons.fire.get_global_rect().get_center()
	await touch(fire, 5, true)
	check(controls.touch_fire and controls.touch_look == steering and hud.camera_finger == 3, "Fire works while independent steering and camera fingers are held")
	await touch(fire, 5, false)
	await touch(fire, 5, true)
	await touch(fire, 5, false)
	check(controls.touch_autofire and controls.snapshot().fire, "Double-tap Fire still latches autofire during multitouch")
	await touch(stick, 0, false)
	check(controls.touch_look == Vector2.ZERO and hud.camera_finger == 3, "Stick release recenters steering without releasing camera")
	await capture(app, "phone-direct-look")
	await touch(view, 3, false)
	for frame in 120:
		flight.update_camera(1.0 / 60.0)
	check(flight.camera.global_transform.is_equal_approx(camera_before), "Released direct look returns to forward chase view")
	await tap(hud.buttons.fire, 5)
	check(not controls.snapshot().fire, "Tap stops latched autofire")
	await touch(track.get_center(), 6, true)
	await drag(lower + Vector2(0, 100), 6)
	check(is_zero_approx(flight.throttle), "Dragging below track clamps at zero")
	await drag(upper - Vector2(0, 100), 6)
	check(is_equal_approx(flight.throttle, 1.0), "Dragging above track clamps at full cruise")
	await touch(upper, 6, false, true)
	check(hud.throttle_finger < 0 and is_equal_approx(flight.throttle, 1.0), "Canceled throttle contact releases ownership without resetting selected speed")
	flight.controls.clear()
	hud.reset_touch()


func check_mouse(app) -> void:
	var hud = app.hud
	var flight = app.flight
	var controls = flight.controls
	var stick: Vector2 = hud.stick_center * hud.factor
	var track := throttle_track(hud)
	var upper := Vector2(track.get_center().x, track.position.y + hud.factor)
	var lower := Vector2(track.get_center().x, track.end.y - hud.factor)
	var view := open_view(hud)
	await mouse_button(stick, true)
	await mouse_drag(stick + Vector2(20, 0) * hud.factor)
	var steering: Vector2 = controls.touch_look
	check(hud.stick_finger == -2 and steering.x > 0 and is_zero_approx(steering.y), "Non-emulated mouse drag steers the original touch stick")
	await touch(stick - Vector2(20, 0) * hud.factor, 0, true)
	await drag(stick - Vector2(30, 0) * hud.factor, 0)
	check(hud.stick_finger == -2 and controls.touch_look == steering, "Real finger cannot overwrite a mouse-owned stick")
	await touch(stick, 0, false)
	check(hud.stick_finger == -2 and controls.touch_look == steering, "Finger release cannot clear mouse steering")
	await mouse_button(stick, false)
	check(hud.stick_finger == -1 and controls.touch_look == Vector2.ZERO, "Mouse release recenters the touch stick")
	await touch(stick + Vector2(20, 0) * hud.factor, 1, true)
	steering = controls.touch_look
	await mouse_button(stick - Vector2(20, 0) * hud.factor, true)
	await mouse_drag(stick - Vector2(30, 0) * hud.factor)
	check(hud.stick_finger == 1 and controls.touch_look == steering, "Mouse cannot overwrite a finger-owned stick")
	check(hud.camera_finger == -1, "Mouse press inside an occupied stick cannot start look-around")
	await mouse_button(stick, false)
	check(hud.stick_finger == 1 and controls.touch_look == steering, "Mouse release cannot clear finger steering")
	await touch(stick, 1, false)
	hud.reset_touch()
	await mouse_button(track.get_center(), true)
	check(hud.throttle_finger == -2 and is_equal_approx(flight.throttle, .5), "Mouse press selects the throttle midpoint")
	await touch(lower, 2, true)
	await drag(lower, 2)
	check(hud.throttle_finger == -2 and is_equal_approx(flight.throttle, .5), "Real finger cannot overwrite a mouse-owned throttle")
	await touch(lower, 2, false)
	await mouse_drag(upper)
	check(is_equal_approx(flight.throttle, 1.0), "Mouse drag reaches the throttle upper endpoint")
	await mouse_button(upper, false)
	check(hud.throttle_finger == -1 and is_equal_approx(flight.throttle, 1.0), "Mouse throttle release retains the selected speed")
	await touch(lower, 3, true)
	await mouse_button(upper, true)
	await mouse_drag(track.get_center())
	check(hud.throttle_finger == 3 and is_zero_approx(flight.throttle), "Mouse cannot overwrite a finger-owned throttle")
	check(hud.camera_finger == -1, "Mouse press inside an occupied throttle cannot start look-around")
	await mouse_button(upper, false)
	check(hud.throttle_finger == 3, "Mouse release cannot clear finger throttle ownership")
	await touch(lower, 3, false)
	hud.reset_touch()
	flight.update_camera(1.0)
	var ship_before: Basis = flight.ship.basis
	var camera_before: Transform3D = flight.camera.global_transform
	await mouse_button(view, true)
	await mouse_drag(view + Vector2(90, -25))
	flight.update_camera(.1)
	check(hud.camera_finger == -2 and not flight.camera.global_transform.is_equal_approx(camera_before), "Mouse drag in the open view looks around")
	check(flight.ship.basis.is_equal_approx(ship_before) and not controls.snapshot().fire, "Mouse look-around leaves heading and weapons unchanged")
	var held_angles: Vector2 = flight.touch_camera_angles
	await touch(view + Vector2(100, 0), 4, true)
	await drag(view + Vector2(180, 50), 4)
	check(hud.camera_finger == -2 and flight.touch_camera_angles == held_angles, "Real finger cannot overwrite mouse look-around")
	await touch(view, 4, false)
	await touch(stick + Vector2(20, 0) * hud.factor, 5, true)
	check(hud.camera_finger == -2 and hud.stick_finger == 5 and controls.touch_look.x > 0, "Mouse look-around coexists with an independent steering finger")
	await touch(stick, 5, false)
	await mouse_button(view, false)
	for frame in 120:
		flight.update_camera(1.0 / 60.0)
	check(hud.camera_finger == -1 and flight.camera.global_transform.is_equal_approx(camera_before), "Mouse look release returns to the forward camera")
	await touch(view, 6, true)
	await drag(view + Vector2(30, 0), 6)
	held_angles = flight.touch_camera_angles
	await mouse_button(view + Vector2(100, 0), true)
	await mouse_drag(view + Vector2(180, 50))
	check(hud.camera_finger == 6 and flight.touch_camera_angles == held_angles, "Mouse cannot overwrite finger-owned look-around")
	await mouse_button(view, false)
	check(hud.camera_finger == 6, "Mouse release cannot clear the camera finger")
	await touch(view, 6, false, true)
	flight.ship.position = flight.station.position + Vector3(0, 0, flight.dock_radius + 2000)
	flight.auto_pilot = false
	flight.time_factor = 1
	await settle(app)
	await mouse_click(hud.extra_buttons.AUTOPILOT)
	await settle(app)
	check(flight.auto_pilot and hud.extra_buttons.TIME.is_visible_in_tree(), "One real mouse click engages navigation exactly once")
	await mouse_click(hud.extra_buttons.TIME)
	check(flight.time_factor == 2, "One real mouse click advances Time exactly once")
	await mouse_click(hud.extra_buttons.AUTOPILOT)
	check(not flight.auto_pilot and flight.time_factor == 1, "One real mouse click disengages navigation exactly once")
	await mouse_button(stick, true)
	await mouse_drag(stick + Vector2(20, 0) * hud.factor)
	flight.pause(true)
	await process_frame
	check(hud.stick_finger == -1 and controls.touch_look == Vector2.ZERO, "Pause cancels held mouse steering")
	await mouse_button(stick, false)
	flight.pause(false)
	hud.reset_touch()


func floating_point(hud) -> Vector2:
	return (hud.stick_center + Vector2(112, -20)) * hud.factor


func check_floating_pad(app) -> void:
	var hud = app.hud
	var flight = app.flight
	var home: Vector2 = hud.stick_center
	var point := floating_point(hud)
	var fire: Vector2 = hud.buttons.fire.get_global_rect().get_center()
	var original_fire: Rect2 = hud.buttons.fire.get_global_rect()
	var original_nav: Rect2 = hud.extra_buttons.AUTOPILOT.get_global_rect()
	check(hud.floating_stick_region().has_point(point), "Nearby lower-left space accepts a relocated steering pad")
	flight.auto_pilot = true
	flight.time_factor = 4
	await touch(point, 0, true)
	check(hud.floating_stick and hud.stick_finger == 0 and hud.camera_finger == -1, "Nearby touch starts floating steering without grabbing the camera")
	check(flight.controls.touch_look == Vector2.ZERO and (home + hud.stick_offset).is_equal_approx(point / hud.factor), "Relocated pad appears under the new touch and starts neutral")
	check(not flight.auto_pilot and flight.time_factor == 1, "Grabbing the relocated pad returns to manual flight")
	var offset: Vector2 = hud.stick_offset
	await drag(point + Vector2(16, -10) * hud.factor, 0)
	var steering: Vector2 = flight.controls.touch_look
	check(steering.x > 0 and steering.y < 0 and hud.stick_offset == offset, "Floating base stays at touchdown while dragging moves its knob")
	await touch(point + Vector2(-12, 18) * hud.factor, 1, true)
	await drag(point + Vector2(20, 20) * hud.factor, 1)
	check(hud.stick_finger == 0 and hud.stick_offset == offset and flight.controls.touch_look == steering, "Second finger cannot move or steal the floating pad")
	await touch(point, 1, false)
	await touch(fire, 2, true)
	check(flight.controls.touch_fire and flight.controls.touch_look == steering, "Fire remains independent while the pad is relocated")
	await touch(fire, 2, false, true)
	check(hud.buttons.fire.get_global_rect() == original_fire and hud.extra_buttons.AUTOPILOT.get_global_rect() == original_nav, "Moving the pad leaves the other action controls in place")
	await capture(app, "phone-floating-pad")
	await drag(Vector2(hud.size.x + 200, -100), 0)
	check(is_equal_approx(flight.controls.touch_look.length(), 1.0) and hud.stick_offset == offset, "Floating pad keeps ownership outside the screen and clamps full steering")
	await touch(point, 0, false)
	check(not hud.floating_stick and hud.stick_offset == Vector2.ZERO and hud.stick_center == home and flight.controls.touch_look == Vector2.ZERO, "Release returns the pad home and clears steering")
	await touch(Vector2(4, hud.size.y - 4), 3, true)
	var visible_center: Vector2 = (hud.stick_center + hud.stick_offset) * hud.factor
	var visible_ring := Rect2(visible_center - Vector2.ONE * 48 * hud.factor, Vector2.ONE * 96 * hud.factor)
	check(hud.floating_stick and Rect2(Vector2.ZERO, hud.size).encloses(visible_ring) and flight.controls.touch_look == Vector2.ZERO, "Edge touchdown keeps the whole pad visible without a steering jump")
	await touch(point, 3, false, true)
	check(not hud.floating_stick and hud.stick_offset == Vector2.ZERO, "Canceled floating contact restores the pad home")
	await mouse_button(point, true)
	await mouse_drag(point + Vector2(-18, 12) * hud.factor)
	steering = flight.controls.touch_look
	check(hud.floating_stick and hud.stick_finger == -2 and steering.x < 0 and steering.y > 0, "Linux mouse testing can grab and steer a nearby floating pad")
	await touch(point, 4, true)
	await drag(point + Vector2(20, 0) * hud.factor, 4)
	check(hud.stick_finger == -2 and flight.controls.touch_look == steering, "Finger cannot steal a mouse-owned floating pad")
	await touch(point, 4, false)
	await mouse_button(point, false)
	check(hud.stick_offset == Vector2.ZERO and flight.controls.touch_look == Vector2.ZERO, "Mouse release restores the pad home")
	await touch(point, 5, true)
	await mouse_button(point, true)
	await mouse_drag(point + Vector2(20, 0) * hud.factor)
	check(hud.stick_finger == 5 and hud.camera_finger == -1 and flight.controls.touch_look == Vector2.ZERO, "Mouse cannot steal a finger-owned floating pad or start a camera drag there")
	await mouse_button(point, false)
	flight.pause(true)
	await process_frame
	check(not hud.floating_stick and hud.stick_offset == Vector2.ZERO and hud.stick_finger == -1, "Pause cancels and homes the floating pad")
	await touch(point, 5, false, true)
	flight.pause(false)
	await touch(point, 6, true)
	await resize_view(Vector2i(960, 640))
	check(not hud.floating_stick and hud.stick_offset == Vector2.ZERO and flight.controls.touch_look == Vector2.ZERO, "Viewport resize cancels the old steering anchor")
	await touch(point, 6, false, true)
	await resize_view(Vector2i(1280, 720))
	await touch(floating_point(hud), 7, true)
	flight.settings.touch = false
	hud.touch_enabled = false
	await process_frame
	check(not hud.floating_stick and hud.stick_offset == Vector2.ZERO, "Hiding touch controls cancels the floating pad")
	await touch(point, 7, false, true)
	flight.settings.touch = true
	hud.touch_enabled = true
	hud.reset_touch()
	await settle(app)


func check_transparency(app) -> void:
	if DisplayServer.get_name() == "headless": return
	# Render onto transparency so stacked native rings cannot conceal alpha errors.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var button = load("res://src/presentation/touch_flight_button.gd").new()
	button.kind = "boost"
	button.texture_normal = app.library.ui_image(app.library.content.flight_ui.buttons.boost.normal)
	button.texture_pressed = app.library.ui_image(app.library.content.flight_ui.buttons.boost.pressed)
	button.factor = 3
	button.position = Vector2(32, 32)
	button.size = Vector2(189, 189)
	viewport.add_child(button)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var resting: Image = viewport.get_texture().get_image()
	var expected: float = button.texture_normal.get_image().get_pixel(31, 31).a
	check(absf(resting.get_pixel(127, 127).a - expected) < .03, "Composited control center retains the supplied normal-art opacity")
	check(resting.get_pixel(10, 10).a < .01, "Control compositor leaves surrounding view transparent")
	button.set_touch_pressed(true)
	button.queue_redraw()
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var pressed: Image = viewport.get_texture().get_image()
	check(pressed.get_pixel(127, 127).a > .95, "Pressed feedback follows the supplied opaque active artwork")
	viewport.queue_free()
	await process_frame


func check_navigation(app) -> void:
	var hud = app.hud
	var flight = app.flight
	check(flight.station != null, "Exploration fixture supplies an imported station")
	if flight.station == null:
		return
	flight.ship.position = flight.station.position + Vector3(0, 0, flight.dock_radius + 2000)
	flight.ship.basis = Basis.IDENTITY
	flight.auto_pilot = false
	flight.time_factor = 1
	flight.throttle = .6
	flight.speed = float(app.library.content.player_motion.cruise_speed) * .6
	await settle(app)
	check(hud.extra_buttons.AUTOPILOT.is_visible_in_tree(), "Navigation appears above steering in manual flight")
	check(not hud.extra_buttons.TIME.is_visible_in_tree() and not hud.extra_buttons.DOCK.is_visible_in_tree(), "Manual flight hides unavailable speedup and docking")
	var nav_rect: Rect2 = hud.extra_buttons.AUTOPILOT.get_global_rect()
	var fire_rect: Rect2 = hud.buttons.fire.get_global_rect()
	await capture(app, "phone-manual")
	await tap(hud.extra_buttons.AUTOPILOT)
	await settle(app)
	check(flight.auto_pilot and flight.can_accelerate_time() and hud.extra_buttons.TIME.is_visible_in_tree(), "Navigation tap exposes speedup during safe distant autopilot")
	await tap(hud.extra_buttons.TIME)
	check(flight.time_factor == 2, "One speedup touch activates 2x exactly once")
	flight._physics_process(.016)
	await capture(app, "phone-autopilot")
	flight.recent_damage = 1
	hud.refresh_navigation_controls()
	check(not flight.can_accelerate_time() and not hud.extra_buttons.TIME.is_visible_in_tree(), "Threat feedback hides unsafe speedup immediately")
	flight.recent_damage = 0
	var track := throttle_track(hud)
	await touch(track.get_center(), 1, true)
	check(not flight.auto_pilot and flight.time_factor == 1 and is_equal_approx(flight.throttle, .5), "Manual throttle immediately cancels autopilot and acceleration")
	await touch(track.get_center(), 1, false)
	flight.ship.position = flight.station.position + Vector3(0, 0, flight.dock_radius + 1)
	await settle(app)
	check(not flight.can_dock() and not hud.extra_buttons.DOCK.is_visible_in_tree(), "Dock remains hidden outside station access range")
	flight.ship.position = flight.station.position + Vector3(0, 0, flight.dock_radius - 1)
	flight.throttle = 0
	flight.speed = 0
	await settle(app)
	check(flight.can_dock() and hud.extra_buttons.DOCK.is_visible_in_tree(), "Eligible station reveals contextual Dock")
	check(hud.extra_buttons.AUTOPILOT.get_global_rect() == nav_rect and hud.buttons.fire.get_global_rect() == fire_rect, "Conditional controls never move existing navigation or combat controls")
	await capture(app, "phone-dock")
	flight.recent_damage = 1
	hud.refresh_navigation_controls()
	check(not flight.can_dock() and not hud.extra_buttons.DOCK.is_visible_in_tree(), "Threat feedback hides ineligible docking")
	flight.recent_damage = 0
	hud.refresh_navigation_controls()
	var dock_signals := [0]
	flight.dock_requested.disconnect(app.dock)
	flight.dock_requested.connect(func(): dock_signals[0] += 1)
	await tap(hud.extra_buttons.DOCK)
	check(dock_signals[0] == 1, "Dock touch dispatches one docking request")
	flight.ship.position = flight.station.position + Vector3(0, 0, flight.dock_radius + 2000)
	flight.auto_pilot = true
	flight.time_factor = 4
	await settle(app)
	var stick: Vector2 = hud.stick_center * hud.factor
	await touch(stick + Vector2(15, 0) * hud.factor, 0, true)
	flight._physics_process(.016)
	check(not flight.auto_pilot and flight.time_factor == 1, "Manual steering cancels navigation and accelerated time")
	await touch(stick, 0, false)
	flight.controls.clear()


func check_cancellation(app) -> void:
	var hud = app.hud
	var flight = app.flight
	var stick: Vector2 = hud.stick_center * hud.factor
	var track := throttle_track(hud)
	var view := open_view(hud)
	await touch(stick + Vector2(15, 0) * hud.factor, 0, true)
	await touch(track.get_center(), 1, true)
	await touch(view, 2, true)
	await drag(view + Vector2(100, 20), 2)
	await touch(hud.buttons.fire.get_global_rect().get_center(), 3, true)
	var selected_throttle: float = flight.throttle
	flight.pause(true)
	await process_frame
	check(hud.stick_finger < 0 and hud.throttle_finger < 0 and hud.camera_finger < 0 and hud.action_fingers.is_empty(), "Pause cancels every held touch owner")
	check(flight.controls.touch_look == Vector2.ZERO and not flight.controls.snapshot().fire, "Pause clears held steering, firing and autofire")
	check(is_equal_approx(flight.throttle, selected_throttle), "Pause preserves selected throttle")
	flight.pause(false)
	for finger in fingers.keys():
		await touch(fingers[finger], finger, false, true)
	await touch(view, 4, true)
	await drag(view + Vector2(50, 20), 4)
	await touch(track.get_center(), 5, true)
	flight.outro_active = true
	await process_frame
	check(not hud.visible and hud.camera_finger < 0 and hud.throttle_finger < 0, "Scripted cinematic hides HUD and cancels direct-look and throttle owners")
	flight.outro_active = false
	await process_frame
	for finger in fingers.keys():
		await touch(fingers[finger], finger, false, true)
	check(hud.visible and not flight.controls.snapshot().fire, "Leaving cinematic restores clean touch controls")
	await touch(track.get_center(), 6, true)
	check(hud.throttle_finger == 6, "Fresh throttle touch works after canceled pause/cinematic contacts")
	await touch(track.get_center(), 6, false)


func resize_view(dimensions: Vector2i) -> void:
	root.min_size = Vector2i.ZERO
	root.content_scale_size = dimensions
	root.size = dimensions
	for frame in 3:
		await process_frame


func check_layouts(app) -> void:
	var hud = app.hud
	for dimensions in [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1560, 720)]:
		await resize_view(dimensions)
		await settle(app)
		check_layout(hud, "phone " + str(dimensions))
		if dimensions != Vector2i(1280, 720):
			await capture(app, "phone-" + str(dimensions.x) + "x" + str(dimensions.y))
	await resize_view(Vector2i(1280, 720))
	var phone_factor: float = hud.factor
	BitmapFont.mobile_cache = 0
	hud.layout_artwork()
	await settle(app)
	check(is_equal_approx(hud.factor, phone_factor * .5), "Desktop preserves half the original phone composition scale")
	check_layout(hud, "desktop")
	await capture(app, "desktop-touch")
	BitmapFont.mobile_cache = 1
	hud.layout_artwork()


func check_radio(app) -> void:
	# Start the supplied tutorial afresh so the panel, portrait and message are
	# produced by its real event clock, not an invented demonstration string.
	await resize_view(Vector2i(960, 640))
	app.session = Session.new()
	app.session.configure(app.library)
	app.launch()
	app.flight.set_physics_process(false)
	app.music.stop()
	for tick in 270:
		app.flight._physics_process(1.0 / 60.0)
	await settle(app)
	check(not app.session.radio_cue().is_empty() and app.dialogue_panel.visible, "Source tutorial clock displays an actual imported radio cue")
	if DisplayServer.get_name() == "headless":
		# Radio's input rectangle is authored by its draw pass. Exercise its real
		# hit area in the rendered run rather than manufacture one for headless.
		return
	await RenderingServer.frame_post_draw
	var panel: Rect2 = app.dialogue_panel.panel_rect
	var hud = app.hud
	var flight = app.flight
	check(panel.size.x > 0 and panel.size.y > 0, "Rendered imported radio panel has an input rectangle")
	var view := Vector2.ZERO
	var stick_rect := Rect2(hud.stick_origin * hud.factor, hud.art.stick_frame.get_size() * hud.factor)
	for ratio in [Vector2(.5, .5), Vector2(.5, .35), Vector2(.7, .35), Vector2(.25, .35), Vector2(.5, .75)]:
		var point: Vector2 = hud.size * ratio
		if not panel.has_point(point) and not stick_rect.has_point(point) and not hud.floating_stick_region().has_point(point) and not hud.throttle_contains(point):
			view = point
			break
	check(view != Vector2.ZERO, "Radio leaves open view available for looking around")
	var cue: Dictionary = app.session.radio_cue().duplicate(true)
	var ship_before: Basis = flight.ship.basis
	await touch(view, 0, true)
	await drag(view + Vector2(25, 10), 0)
	check(hud.camera_finger == 0 and app.session.radio_cue() == cue, "Looking around outside radio preserves the live message")
	var track := throttle_track(hud)
	await touch(track.get_center(), 1, true)
	check(hud.throttle_finger == 1 and is_equal_approx(flight.throttle, .5), "Right-edge throttle remains usable with radio visible")
	check(hud.camera_finger == 0 and app.session.radio_cue() == cue, "Throttle leaves simultaneous look-around and radio untouched")
	await touch(track.get_center(), 1, false)
	await touch(view, 0, false, true)
	flight.speed = app.session.Motion.speed(app.session.motion, app.library.content.player_motion)
	await capture(app, "phone-radio")
	var radio_touch: Vector2 = panel.get_center()
	var overlap: Rect2 = panel.intersection(hud.floating_stick_region())
	if overlap.has_area(): radio_touch = overlap.get_center()
	await touch(radio_touch, 2, true)
	check(app.session.radio_cue().is_empty() and not app.dialogue_panel.visible, "Tapping imported radio dismisses the real active cue")
	check(hud.camera_finger == -1 and hud.stick_finger == -1 and not flight.controls.snapshot().fire, "Radio dismissal cannot claim camera, steering or fire")
	check(flight.ship.basis.is_equal_approx(ship_before), "Radio interaction preserves ship heading")
	await touch(radio_touch, 2, false)
	await touch(view, 3, true)
	check(hud.camera_finger == 3, "A fresh open-view drag works after radio dismissal")
	await touch(view, 3, false, true)


func check_layout(hud, description: String) -> void:
	var bounds := Rect2(Vector2.ZERO, hud.size)
	var track := throttle_track(hud)
	check(bounds.encloses(hud.throttle_control.get_global_rect()), description + ": throttle and speed caption remain inside viewport")
	check(track.size.y / hud.factor >= 46 and track.size.y / hud.factor <= 52, description + ": throttle track is about 30 percent shorter than the 70-unit mock")
	check(track.size.x / hud.factor >= 8 and track.size.x / hud.factor <= 10, description + ": revised throttle is wider and easy to see")
	check(hud.size.x - track.end.x >= 18 * hud.factor and hud.size.x - track.end.x <= 24 * hud.factor, description + ": throttle has breathing room inside the right border")
	for action in hud.buttons:
		check(bounds.encloses(hud.buttons[action].get_global_rect()), description + ": imported " + action + " control fits screen")
	for action in hud.extra_buttons:
		check(bounds.encloses(hud.extra_buttons[action].get_global_rect()), description + ": " + action + " contextual slot fits screen")
	var stick_rect := Rect2(hud.stick_origin * hud.factor, hud.art.stick_frame.get_size() * hud.factor)
	var nav: Rect2 = hud.extra_buttons.AUTOPILOT.get_global_rect()
	var time: Rect2 = hud.extra_buttons.TIME.get_global_rect()
	var dock: Rect2 = hud.extra_buttons.DOCK.get_global_rect()
	check(nav.end.y <= stick_rect.position.y and not nav.intersects(time) and time.position.x >= nav.end.x, description + ": speedup has its own slot beside navigation above stick")
	check(not hud.throttle_control.get_global_rect().intersects(hud.buttons.pause.get_global_rect()), description + ": throttle hit target clears Pause")
	for action in ["fire", "weapon", "missiles"]:
		check(not dock.intersects(hud.buttons[action].get_global_rect()), description + ": Dock clears " + action + " hit target")
	check(not "%" in visible_text(hud.throttle_control), description + ": throttle has no percentage label")


func check_preferences(app) -> void:
	app.settings.touch = false
	app.flight.settings.touch = false
	app.show_flight_hud()
	await settle(app)
	check(not app.hud.throttle_control.is_visible_in_tree(), "Hidden touch preference hides throttle")
	for action in app.hud.buttons:
		check(not app.hud.buttons[action].is_visible_in_tree(), "Hidden touch preference hides " + action)
	for action in app.hud.extra_buttons:
		check(not app.hud.extra_buttons[action].is_visible_in_tree(), "Hidden touch preference hides " + action)
	var view := open_view(app.hud)
	await touch(view, 0, true)
	await drag(view + Vector2(80, 0), 0)
	check(app.hud.camera_finger < 0 and app.flight.controls.touch_look == Vector2.ZERO, "Hidden touch preference does not capture open-view dragging")
	await touch(view, 0, false)
	app.settings.touch = true
	app.flight.settings.touch = true
	app.settings.extra_flight_buttons = false
	app.flight.settings.extra_flight_buttons = false
	app.show_flight_hud()
	await settle(app)
	check(app.hud.buttons.pause.is_visible_in_tree() and app.hud.buttons.fire.is_visible_in_tree(), "Imported touch actions remain available when extra controls are disabled")
	check(app.hud.extra_buttons.values().all(func(control): return not control.is_visible_in_tree()), "Extra-controls preference hides navigation, speedup and Dock")


func visible_text(node: Node) -> String:
	var text := ""
	if node is Label and node.visible:
		text += node.text
	for child in node.get_children():
		text += visible_text(child)
	return text


func capture(app, filename: String) -> void:
	if capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	# Other assertions freeze time between interactions. Expire their transient
	# notifications before comparing persistent HUD composition to the mock.
	app.notification_time = 0
	await settle(app)
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(capture_directory.path_join(filename + ".png"))
	check(result == OK, "Render screenshot " + filename)
