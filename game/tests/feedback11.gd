extends "res://tests/player_feedback.gd"


class PresentationMain:
	extends "res://src/main.gd"

	func _ready():
		pass

	func _process(_delta):
		pass

	func advance_presentation(delta):
		super._process(delta)

	func save_path(slot):
		return "user://feedback11-" + slot + ".json"

	func settings_path():
		return "user://feedback11-settings.cfg"


func run():
	var args := OS.get_cmdline_user_args()
	if args.has("mobile"):
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open updated source declarations")
	if failures:
		quit(1)
		return
	var zip := ZIPReader.new()
	zip.open(args[1])
	var source := zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		Combat.vector(lib.content.flight_effects.outro.camera_offset) == Vector3(20, 20, -160),
		"Source success camera offset"
	)
	check(
		lib.content.flight_effects.outro.settle_seconds == 5, "Source closing transition interval"
	)
	check(
		lib.content.menu_traffic.local_trail.style == 2, "Station locals use source friendly branch"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x28600, 2), 0x2040)
	check(
		is_equal_approx(reader.flight_button_opacity().boost_active, 64.0 / 255),
		"Boost opacity follows source data"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x44b4a, 2), 0)
	check(reader.mission_outro_presentation().is_empty(), "Unknown success camera binding rejected")
	var app := FeedbackMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib, true)
	app.settings.touch = true
	app.launch()
	app.flight.set_physics_process(false)
	var flight = app.flight
	flight.ship.position = Vector3(10000, 10000, 10000)
	for original in [false, true]:
		flight.apply_control_settings({"original_flight_controls": original})
		for input in [Vector2(.03, .02), Vector2(-.7, .6), Vector2(.8, -.6), Vector2.ZERO]:
			flight.controls.touch_look = input
			for tick in 30:
				flight.step(1.0 / 60)
				var physical: Basis = flight.ship.basis
				var motion: Dictionary = app.session.motion.duplicate(true)
				flight.update_camera(1.0 / 60)
				var screen_point: Vector2 = flight.camera.unproject_position(
					flight.ship.global_position
				)
				check(
					(
						screen_point.distance_to(
							root.get_visible_rect().size * flight.SHIP_SCREEN_ANCHOR
						)
						< .1
					),
					"Ship remains centered through small turns and reversals"
				)
				check(
					flight.ship.basis == physical and app.session.motion == motion,
					"Centering leaves flight physics unchanged"
				)
	flight.controls.clear()
	app.session.motion.boost_remaining = 1
	app.session.motion.cooldown = 0
	flight.update_camera(.2)
	check(
		(
			flight.camera.unproject_position(flight.ship.global_position).distance_to(
				root.get_visible_rect().size * flight.SHIP_SCREEN_ANCHOR
			)
			< .1
		),
		"Boost FOV preserves ship framing"
	)
	app.hud._process(0)
	check(
		is_equal_approx(app.hud.buttons.boost.self_modulate.a, 55.0 / 255),
		"Active boost dims actual touch button"
	)
	app.session.motion.boost_remaining = 0
	app.session.motion.cooldown = lib.content.player_motion.recharge_seconds * .5
	app.hud._process(0)
	check(
		is_equal_approx(app.hud.buttons.boost.self_modulate.a, (55.0 + 37.5) / 255),
		"Recharge progressively restores source opacity"
	)
	app.session.motion.cooldown = 0
	app.hud._process(0)
	check(app.hud.buttons.boost.self_modulate.a == 1, "Ready boost is fully opaque")
	app.session.loadout.fitted[lib.MISSILE_CATEGORY] = {}
	app.hud._process(0)
	check(
		is_equal_approx(app.hud.buttons.missiles.self_modulate.a, 50.0 / 255),
		"Missing missile is visibly unavailable"
	)
	var missile := -1
	for id in lib.items.size():
		if int(lib.items[id][1]) == lib.MISSILE_CATEGORY:
			missile = id
			break
	app.session.loadout.fitted[lib.MISSILE_CATEGORY] = {"id": missile, "value": 0}
	flight.weapon_timers[missile] = 2
	app.hud._process(0)
	check(
		is_equal_approx(app.hud.buttons.missiles.self_modulate.a, 50.0 / 255),
		"Reloading missile is dim"
	)
	flight.weapon_timers[missile] = 0
	app.hud._process(0)
	check(app.hud.buttons.missiles.self_modulate.a == 1, "Reloaded missile is fully opaque")
	app.session.loadout.fitted[lib.MISSILE_CATEGORY] = {}
	var captured: Dictionary = app.session.capture()
	var camera_pose: Transform3D = flight.camera.global_transform
	app.show_action_freeze()
	check(
		app.screen == "action_freeze" and flight.process_mode == Node.PROCESS_MODE_DISABLED,
		"Photo mode freezes the entire flight scene"
	)
	var photo = app.action_freeze_panel
	photo.orbit(Vector2(100, 30))
	photo.pan(Vector2(20, -10))
	photo.zoom(.7)
	check(
		not flight.camera.global_transform.is_equal_approx(camera_pose),
		"Photo controls move the inspection camera"
	)
	check(
		same_saved_value(app.session.capture(), captured),
		"Orbit/pan/zoom leave all saved gameplay state unchanged"
	)
	await process_frame
	await process_frame
	check(
		same_saved_value(app.session.capture(), captured),
		"Frozen scene does not advance between frames"
	)
	photo.toggle_ui()
	check(not photo.toolbar.visible, "Hide UI removes photo controls")
	photo.toggle_ui()
	if args.size() > 2 and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2] + "-photo.png")
	app.close_action_freeze(true)
	flight.set_physics_process(false)
	check(
		(
			app.screen == "flight"
			and not flight.paused
			and flight.process_mode == Node.PROCESS_MODE_INHERIT
		),
		"Resume restores flight processing"
	)
	check(
		flight.camera.global_transform.is_equal_approx(camera_pose),
		"Photo exit restores exact flight camera"
	)
	check(
		same_saved_value(app.session.capture(), captured), "Resume cannot move or damage the pilot"
	)
	app.show_pause()
	check(
		app.pause_panel.buttons.any(func(button): return button.text == "Action freeze"),
		"Pause exposes action freeze"
	)
	if args.size() > 2 and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[2] + "-pause.png")
	app.music.stop()
	app.stop_flight()
	app.queue_free()
	await process_frame
	await test_outro(lib, args[2] if args.size() > 2 else "")
	await test_application_outro(lib, args[2] if args.size() > 2 else "")
	var menu = preload("res://src/presentation/menu_scene.gd").new()
	root.add_child(menu)
	check(menu.configure(lib, 0, 0, false, 47), "Create station traffic")
	menu.set_process(false)
	menu.advance(2)
	for trail in menu.trails:
		if trail != null:
			check(
				trail.tint == Color.hex(int(lib.content.projectile_trails.styles["2"].color)),
				"Rendered station trail is green"
			)
	menu.queue_free()
	await process_frame
	for frame in 4: await process_frame
	print("FEEDBACK SEPT11 ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)


func test_outro(lib, capture_path):
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.depart()
	# Source objective completion, with closing radio still pending.
	for actor in pilot.active_job.actors:
		actor.hp = 0
	pilot.active_job.kills = pilot.active_job.target
	pilot.active_job.ready = true
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {"original_flight_controls": true}, true)
	flight.set_physics_process(false)
	var completions := [0]
	flight.mission_completed.connect(func(): completions[0] += 1)
	var hull_before: float = pilot.hull
	flight.step(.02)
	check(
		flight.outro_active and not flight.paused,
		"Mission success starts departure instead of a frozen frame"
	)
	var position: Vector3 = flight.ship.position
	var camera_position: Vector3 = flight.camera.position
	var credits: int = pilot.credits
	for tick in 120:
		flight.step(1.0 / 60)
		pilot.advance_radio(1.0 / 60)
		flight.update_camera(1.0 / 60)
	check(
		flight.ship.position.distance_to(position) > 1,
		"Player flies onward during closing dialogue"
	)
	check(
		flight.camera.position.is_equal_approx(camera_position),
		"Departure camera stays at its fixed world position"
	)
	flight.hit(1000, Vector3.LEFT)
	check(
		pilot.hull == hull_before and pilot.credits == credits,
		"Outro cannot damage player or grant rewards early"
	)
	if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_path + "-outro.png")
	for tick in 4000:
		pilot.advance_radio(.02)
		flight.step(.02)
		if completions[0] > 0:
			break
	check(
		completions[0] == 1 and flight.paused and pilot.ready_to_finish(),
		"Closing dialogue and departure finish once"
	)
	check(pilot.finish_mission(), "Normal atomic mission reward settlement succeeds")
	var settled: Dictionary = pilot.capture()
	position = flight.ship.position
	flight.advance_outro(.5)
	check(
		flight.ship.position != position and pilot.capture() == settled,
		"Reward background keeps moving without changing settled save"
	)
	flight.queue_free()
	await process_frame


func test_application_outro(lib, capture_path):
	var app := PresentationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib)
	app.session.depart()
	for actor in app.session.active_job.actors:
		actor.hp = 0
	app.session.active_job.kills = app.session.active_job.target
	app.session.active_job.ready = true
	app.launch(true)
	app.flight.set_physics_process(false)
	app.flight.step(.02)
	app.flight.advance_outro(1.1)
	app.advance_presentation(0)
	check(
		app.flight.outro_music_played and app.music.playing,
		"Application starts imported victory music"
	)
	for tick in 5000:
		app.session.advance_radio(.02)
		app.flight.step(.02)
		if app.screen != "flight":
			break
	check(
		app.screen == "recovery" and not app.session.recovery.is_empty(),
		"Application settles success into reward receipt"
	)
	if app.screen == "recovery":
		var settled: Dictionary = app.session.capture()
		var position: Vector3 = app.flight.ship.position
		app.advance_presentation(.5)
		# The normal receipt screen still accrues play time. Departure itself changes no gameplay.
		settled.statistics = app.session.capture().statistics
		if not capture_path.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(capture_path + "-rewards.png")
		check(
			app.flight.ship.position != position and app.session.capture() == settled,
			"Application animates departure behind rewards without mutating save"
		)
	app.music.stop()
	app.stop_flight()
	app.queue_free()
	await process_frame
