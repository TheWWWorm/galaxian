extends "res://tests/player_feedback.gd"
const Steering = preload("res://src/simulation/player_steering.gd")

func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open content for both flight modes")
	if failures: quit(1); return
	if args.size() > 1 and args[1] == "mobile":
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var app := FeedbackMain.new()
	root.add_child(app)
	check(not app.settings.original_flight_controls, "Original controls are opt-in on a new installation")
	var old := ConfigFile.new(); old.set_value("options", "invert", true); old.save(app.settings_path())
	app.load_settings()
	check(not app.settings.original_flight_controls, "Existing preferences without the new key retain previous controls")
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true
	app.session = Session.new(); app.session.configure(lib, true)
	app.settings.invert = false
	app.launch(); app.flight.set_physics_process(false)
	var flight = app.flight
	flight.ship.position = Vector3(2000, 0, 2000)
	flight.mouse_flight_enabled = true; flight.web_mouse_input = true
	var start: Basis = flight.ship.basis
	var event := InputEventMouseMotion.new(); event.relative = Vector2(1, 0)
	for tick in 120:
		if tick % 3 == 0: flight._unhandled_input(event)
		flight.step(1.0 / 60)
	var expected := start.rotated(Vector3.UP, -40 * float(app.settings.sensitivity))
	check(flight.ship.basis.is_equal_approx(expected), "Sparse one-pixel mouse moves retain their full angular distance")
	check(app.session.motion.turn == [0.0, 0.0], "Default mode has no residual steering inertia")
	var before: Basis = flight.ship.basis
	for tick in 60: flight.step(1.0 / 60)
	check(flight.ship.basis.is_equal_approx(before), "Default mouse turn stops immediately after motion stops")
	flight.ship.basis = Basis.IDENTITY
	flight.controls.touch_look = Vector2(.1, 0)
	flight.step(.1)
	check(absf(flight.ship.rotation.y + .012) < .000001, "Default small analog turn uses the previous linear 1.2 rad/s response")
	flight.controls.clear()
	flight.camera.position = Vector3.ZERO; flight.ship.position = Vector3(2000, 0, 2000)
	var desired: Vector3 = flight.ship.position
	flight.update_camera(.02)
	check(flight.camera.unproject_position(desired).distance_to(root.get_visible_rect().size * flight.SHIP_SCREEN_ANCHOR) < .1, "Default chase view keeps ship centered")
	app.show_options(); app.options_panel.show_section("controls")
	check(app.options_panel.values.original_flight_controls == false, "Controls menu displays original mode unchecked")
	for row in app.options_panel.buttons:
		check(row.position.y >= app.options_panel.data.logo_y + app.options_panel.art.logo.get_height() and row.get_rect().end.y < app.options_panel.footer.position.y, "Controls rows clear both logo and footer")
	app.options_panel.handle_action("original_flight_controls")
	app.load_settings()
	check(app.settings.original_flight_controls, "Original controls option persists")
	await capture(args[2] if args.size() > 2 else "", "controls-options", app)
	app.close_options(); app.resume_flight(); flight.set_physics_process(false)
	check(flight.original_controls(), "Resuming applies selected original profile")
	flight.mouse_flight_enabled = true; flight.web_mouse_input = true
	var raw: Array[float] = []; var filtered: Array[float] = []
	for tick in 180:
		if tick % 3 == 0: flight._unhandled_input(event)
		flight.step(1.0 / 60)
		raw.append(Steering.bank(app.session.motion.turn, lib.content.player_motion.steering).z)
		filtered.append(flight.displayed_bank.z)
	var raw_jitter := 0.0; var filtered_jitter := 0.0
	for tick in range(30, raw.size() - 1):
		raw_jitter += absf(raw[tick + 1] - 2 * raw[tick] + raw[tick - 1])
		filtered_jitter += absf(filtered[tick + 1] - 2 * filtered[tick] + filtered[tick - 1])
	check(filtered_jitter < raw_jitter * .3, "Small mouse-packet bank jitter reduced by at least 70 percent")
	print("BANK PACKET JITTER raw=", raw_jitter, " filtered=", filtered_jitter)
	for tick in 300: flight.step(1.0 / 60)
	check(flight.displayed_bank.length() < .00001 and app.session.motion.turn == [0.0, 0.0], "Original bank settles after small turns")
	flight.controls.touch_look = Vector2(.5, 0); flight.step(.2)
	before = flight.ship.basis
	app.show_options(); app.options_panel.show_section("controls"); app.options_panel.handle_action("original_flight_controls")
	app.close_options(); app.resume_flight(); flight.set_physics_process(false)
	check(not flight.original_controls() and app.session.motion.turn == [0.0, 0.0] and flight.mouse_motion == Vector2.ZERO, "Switching back clears buffered motion and angular state")
	check(flight.ship.basis.is_equal_approx(before), "Switching profiles preserves physical heading")
	app.music.stop(); app.stop_flight(); app.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://feedback-settings.cfg"))
	print("FLIGHT MODES ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)
