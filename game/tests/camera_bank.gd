extends "res://tests/player_feedback.gd"

func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open content for camera-relative banking")
	if failures: quit(1); return
	var app := FeedbackMain.new(); root.add_child(app)
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true
	app.session = Session.new(); app.session.configure(lib, true)
	app.settings.original_flight_controls = true
	app.launch(); app.flight.set_physics_process(false)
	var flight = app.flight
	flight.ship.position = Vector3(2000, 0, 2000)
	flight.camera.position = flight.ship.position + Vector3(0, 15, flight.follow_distance)
	var max_old_yaw := 0.0
	var max_new_yaw := 0.0
	for input in [Vector2(.65, 0), Vector2(-.65, 0), Vector2.ZERO, Vector2(.3, .5)]:
		flight.controls.touch_look = input
		for tick in 90:
			flight.step(1.0 / 60)
			var heading: Basis = flight.ship.basis
			var motion: Dictionary = app.session.motion.duplicate(true)
			flight.update_camera(1.0 / 60)
			var relative: Basis = flight.camera.global_basis.inverse() * flight.player_hull.global_basis * flight.player_hull_rest.inverse()
			var nose := -relative.z
			max_new_yaw = maxf(max_new_yaw, absf(atan2(nose.x, -nose.z)))
			var old_relative: Basis = flight.camera.global_basis.inverse() * flight.ship.global_basis * Basis.from_euler(flight.displayed_bank)
			max_old_yaw = maxf(max_old_yaw, absf(atan2(-old_relative.z.x, old_relative.z.z)))
			check(flight.ship.basis.is_equal_approx(heading) and app.session.motion == motion, "Visual frame update leaves heading and inertia intact")
			check((-(flight.player_hull.global_basis * flight.player_hull_rest.inverse()).z).dot(-flight.ship.global_basis.z) > .9999, "Camera sees only cosmetic roll/pitch, including turn reversal")
	check(max_new_yaw < .00001, "Visible nose has no sideways yaw")
	print("RELATIVE YAW old=", rad_to_deg(max_old_yaw), "deg corrected=", rad_to_deg(max_new_yaw), "deg")
	# Check a rolled/near-vertical flight frame without Euler yaw subtraction.
	flight.ship.basis = Basis.from_euler(Vector3(PI * .499, 1.1, 2.0))
	flight.camera.basis = Basis.from_euler(Vector3(1.3, -.7, -.8))
	flight.update_camera(.02)
	var relative: Basis = flight.camera.global_basis.inverse() * flight.player_hull.global_basis * flight.player_hull_rest.inverse()
	check((-(flight.player_hull.global_basis * flight.player_hull_rest.inverse()).z).dot(-flight.ship.global_basis.z) > .9999, "Camera-relative banking stays stable near vertical and upside down")
	var position: Vector3 = flight.player_hull.global_position
	var banked: Basis = Basis.from_euler(flight.displayed_bank) * flight.player_hull_rest
	flight.first_person = true; flight.update_player_hull_frame()
	check(flight.player_hull.basis.is_equal_approx(banked), "Cockpit mode keeps body in its physical frame")
	flight.first_person = false; flight.chase_camera_active = false; flight.update_player_hull_frame()
	check(flight.player_hull.basis.is_equal_approx(banked), "External cinematic views keep body in its physical frame")
	check(flight.player_hull.global_position.is_equal_approx(position), "Orientation correction cannot displace the ship")
	flight.apply_control_settings({"original_flight_controls": false})
	flight.update_camera(.02)
	check(flight.camera.unproject_position(flight.ship.position).distance_to(root.get_visible_rect().size * flight.SHIP_SCREEN_ANCHOR) < .1, "Default controls also use centered chase framing")
	var cinematic := Session.new(); cinematic.configure(lib)
	cinematic.chapter = 12; cinematic.progression = Session.Progression.create(12)
	cinematic.station_id = lib.chapter_destination(11)
	check(cinematic.depart(), "Create actual source-defined cinematic fixture")
	cinematic.active_job.sequence_cursor = 2
	var external := Flight.new(); root.add_child(external)
	external.setup(lib, cinematic, {"original_flight_controls": true}, true)
	external.set_physics_process(false)
	check(not external.chase_camera_active and external.player_hull.basis.is_equal_approx(external.player_hull_rest), "Authored external camera selects physical hull framing")
	cinematic.active_job.sequence_cursor = 0
	external.update_camera(.02)
	check(external.chase_camera_active, "Returning from authored camera restores chase framing")
	external.queue_free(); await process_frame
	flight.camera.current = true
	# Capture a short reproducible left/right turn demonstration when requested.
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		flight.apply_control_settings({"original_flight_controls": true})
		flight.ship.basis = Basis.IDENTITY; flight.ship.position = Vector3(2000, 0, 2000)
		flight.camera.basis = Basis.IDENTITY
		flight.camera.position = flight.ship.position + Vector3(0, 15, flight.follow_distance)
		for frame in 120:
			flight.controls.touch_look = Vector2(.65 if frame < 40 else (-.65 if frame < 80 else 0.0), 0)
			for tick in 2:
				flight.step(1.0 / 60); flight.update_camera(1.0 / 60)
			await process_frame; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[1].path_join("frame-%03d.png" % frame))
	app.music.stop(); app.stop_flight(); app.queue_free()
	await process_frame
	print("CAMERA BANK ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)
