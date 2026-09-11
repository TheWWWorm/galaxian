extends "res://tests/player_feedback.gd"
const Music = preload("res://src/presentation/flight_music.gd")
const Motion = preload("res://src/input/motion_steering.gd")
const Transfer = preload("res://src/simulation/save_transfer.gd")


func run():
	var args := OS.get_cmdline_user_args()
	if args.has("mobile"):
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open feedback12 content")
	if failures:
		quit(1)
		return
	check_music(lib)
	check_motion()
	check_transfer(lib)
	if args[-1].ends_with(".ipa"):
		var archive := ZIPReader.new()
		archive.open(args[-1])
		await check_player_destruction(
			archive.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire"), lib
		)
		archive.close()
	await check_presentation(lib)
	print("FEEDBACK12 ", checks, " CHECKS; ", failures, " FAILURES")
	call_deferred("finish_feedback")


func check_music(lib):
	var data: Dictionary = lib.content.flight_music
	check(
		(
			int(data.combat[0]) == 1
			and int(data.combat[1]) == 2
			and data.explore == 3
			and data.combat_delay == 1
			and data.explore_delay == 4
		),
		"Imported radar music choices and delays"
	)
	var controller := Music.new()
	controller.reset()
	check(controller.advance(data, false, false, 10) == -1, "No restart while peaceful")
	check(controller.advance(data, true, false, .1) == -2, "Radar contact stops peaceful track")
	check(controller.advance(data, true, false, .9) == -1, "Battle waits source delay")
	check(controller.advance(data, true, false, .2) in [1, 2], "Battle track begins")
	check(controller.advance(data, true, false, 10) == -1, "Battle does not restart each frame")
	check(
		controller.advance(data, false, true, 10) == -1, "Survival keeps battle music between waves"
	)
	check(controller.advance(data, false, false, .1) == -2, "Last enemy clears music")
	check(controller.advance(data, false, false, 3.9) == -1, "Peaceful delay")
	check(controller.advance(data, false, false, .2) == 3, "Explore returns")
	controller.reset()
	controller.advance(data, true, false, .1)
	check(
		controller.advance(data, false, false, .1) == 3,
		"Fleeting contact cannot leave music stopped"
	)
	check(Music.valid(data, lib.content.sound_bank), "Music references real assets")
	var pirate: Dictionary = lib.definition_weapons(
		{
			"groups":
			[
				{
					"count": 1,
					"actor": 4,
					"weapon":
					(
						lib
						. mission_definition(2)
						. groups
						. filter(func(g): return g.has("weapon"))[0]
						. weapon
					)
				}
			]
		},
		1
	)
	check(pirate[-1].projectile_model == 10051, "Pirate uses red Onyx mesh")
	var definition := {"groups": [{"count": 1, "actor": 1, "weapon": pirate[-1].duplicate(true)}]}
	definition.groups[0].weapon.erase("projectile_model")
	check(
		lib.definition_weapons(definition, 1)[-1].projectile_model == 10067, "Vossk uses NGook mesh"
	)
	definition.groups[0].team = "ally"
	check(
		lib.definition_weapons(definition, 1)[-1].projectile_model == 10050,
		"Allies use Mercury mesh"
	)


func check_motion():
	var sensor := Motion.new()
	check(
		sensor.sample(Vector3(0, -9.8, 0), .1, .5) == Vector2.ZERO, "Motion centers on first sample"
	)
	check(sensor.sample(Vector3(-3, -9, 0), 1, .5).x > .5, "Right tilt steers right")
	check(sensor.sample(Vector3(0, -9, -3), 1, .5).y < -.5, "Forward tilt changes pitch")
	check(sensor.sample(Vector3.ZERO, 1, .5) == Vector2.ZERO, "Missing sensor never turns ship")
	check(
		sensor.sample(Vector3(0, -9.8, 0), 1, .5).length() < .001,
		"Neutral returns to rest without drift"
	)


func check_transfer(lib):
	var transfer := Transfer.new()
	var source: String = "user://feedback12-source/" + lib.id
	var destination: String = "user://feedback12-destination/" + lib.id
	DirAccess.make_dir_recursive_absolute(source)
	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.save(source.path_join("campaign.json")), "Save campaign fixture")
	pilot.configure(lib, true)
	check(pilot.save(source.path_join("free.json")), "Save exploration fixture")
	var archive := preload("res://src/simulation/survival_archive.gd").new()
	check(archive.open(lib, lib.content.survival, source), "Open survival fixture")
	check(archive.write_checkpoint(JSON.stringify(archive.capture())), "Save survival profile")
	var bundle := transfer.collect(lib, source)
	check(bundle.get("saves", {}).size() == 3, "Export all three modes")
	check(transfer.write("user://feedback12.gofsave", bundle), "Write portable save")
	check(
		not transfer.read_export(lib, "user://feedback12.gofsave").is_empty(),
		"Read and validate portable save"
	)
	check(transfer.install(lib, destination, bundle), "Install transfer atomically")
	var loaded := Session.new()
	loaded.configure(lib)
	check(loaded.load_save(destination.path_join("campaign.json")), "Imported campaign loads")
	loaded.configure(lib, true)
	check(loaded.load_save(destination.path_join("free.json")), "Imported exploration loads")
	var restored := preload("res://src/simulation/survival_archive.gd").new()
	check(restored.open(lib, lib.content.survival, destination), "Imported survival loads")
	var bytes := FileAccess.get_file_as_bytes(destination.path_join("campaign.json"))
	var corrupt: Dictionary = bundle.duplicate(true)
	corrupt.saves["campaign.json"].credits = -1
	check(not transfer.install(lib, destination, corrupt), "Reject invalid pilot before writing")
	check(
		bytes == FileAccess.get_file_as_bytes(destination.path_join("campaign.json")),
		"Rejected import preserves save bytes"
	)
	corrupt = bundle.duplicate(true)
	corrupt.content_id = "different"
	check(transfer.validate(lib, corrupt).is_empty(), "Reject different IPA identity")
	corrupt = bundle.duplicate(true)
	corrupt.saves["../outside.json"] = {}
	check(transfer.validate(lib, corrupt).is_empty(), "Reject traversal file names")
	check(
		transfer.install(lib, destination, bundle), "Existing directory safely backed up on import"
	)


func check_presentation(lib):
	var app := FeedbackMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib, true)
	app.launch()
	var flight = app.flight
	flight.set_physics_process(false)
	flight.ship.position = Vector3(10000, 10000, 10000)
	for original in [false, true]:
		flight.apply_control_settings({"original_flight_controls": original})
		for input in [Vector2(.03, .02), Vector2(.7, .6), Vector2(-.8, -.6), Vector2.ZERO]:
			for tick in 60:
				flight.advance_turn(input, 1.0 / 60)
				flight.update_camera(1.0 / 60)
				var point: Vector3 = (
					flight.ship.position
					- flight.ship.basis.z * lib.content.flight_ui.radar.aim_distance
				)
				var aim: Vector2 = flight.camera.unproject_position(point)
				check(
					absf(aim.x - root.get_visible_rect().size.x * .5) < .1,
					"Reticle cannot wander sideways during yaw"
				)
				var nose: Vector3 = -(
					(flight.player_hull.global_basis * flight.player_hull_rest.inverse()).z
				)
				check(
					nose.dot(-flight.ship.basis.z) > .9999,
					"Visible nose and projectile direction agree"
				)
				check(
					(
						flight.camera.unproject_position(flight.ship.position).distance_to(
							root.get_visible_rect().size * flight.SHIP_SCREEN_ANCHOR
						)
						< .1
					),
					"Hull stays anchored"
				)
	# Use the maintained mission setup for actual freighter departure and projectiles.
	app.stop_flight()
	app.session = Session.new()
	app.session.configure(lib)
	app.session.chapter = 8
	app.session.progression = Session.Progression.create(8)
	app.session.station_id = lib.chapter_destination(7)
	app.session.briefing_page = -1
	app.launch()
	flight = app.flight
	flight.set_physics_process(false)
	app.session.active_job.stage = app.session.route_length()
	flight.spawn_targets()
	var freighters: Array = flight.actors.filter(
		func(actor):
			return (
				app.session.mission_definition().groups[int(actor.state.group)].get("behavior")
				== "transit"
			)
	)
	check(freighters.size() >= 2, "Outro fixture has moving freighters")
	var wreck
	if not freighters.is_empty():
		var dying: Dictionary = freighters[0]
		dying.state.hp = 0
		dying.state.destruction.phase = "dying"
		flight.actor_destroyed(dying)
		wreck = flight.explosions.back()
		flight.actors.erase(dying)
	var shot := {
		"id": 999, "weapon": 0, "position": [0, 0, 0], "velocity": [0, 0, -100], "remaining": 2.0
	}
	app.session.combat.projectiles.append(shot)
	flight.begin_outro()
	check(
		(flight.outro_camera_position - flight.ship.position).dot(-flight.ship.basis.z) > 0,
		"Victory camera starts ahead of ship"
	)
	var state: Dictionary = app.session.capture()
	var actor_positions := {}
	for actor in flight.actors:
		actor_positions[actor.index] = actor.node.position
	flight.advance_outro(.1)
	check(
		wreck != null and wreck.elapsed_ms >= 100,
		"Freighter explosion advances in victory cutscene"
	)
	check(
		flight.outro_projectiles[0].position[2] == -10 and shot.position == [0, 0, 0],
		"Outro laser moves without modifying saved combat"
	)
	for actor in flight.actors:
		var group: Dictionary = flight.outro_definition.groups[int(actor.state.group)]
		if group.get("behavior") == "transit" and Combat.vector(group.velocity).length() > 0:
			check(
				actor.node.position.distance_to(actor_positions[actor.index]) > 0,
				"Outro freighter continues moving"
			)
	check(
		same_saved_value(state, app.session.capture()),
		"Outro leaves rewards and gameplay state unchanged"
	)
	app.session.active_job = {}
	flight.advance_outro(3)
	check(
		flight.outro_projectiles.is_empty() and not flight.bolts.has(999),
		"Existing laser expires during outro"
	)
	var info := preload("res://src/presentation/ship_slots.gd").describe(lib, 0)
	check(
		info.contains("Weapon slots") and info.contains(": 0"),
		"Ship info distinguishes unavailable weapon categories"
	)
	await capture_review("outro")
	app.stop_flight()
	app.session = Session.new()
	app.session.configure(lib, true)
	app.show_market("ship")
	app.hangar_panel.seen_hints.assign(lib.content.hangar_ui.hints.messages.keys())
	app.hangar_panel.hint_role = ""
	app.hangar_panel.close_transaction()
	app.hangar_panel.details = true
	app.hangar_panel.populate()
	await capture_review("ship-info")
	app.show_title()
	app.show_title_menu("transfer")
	await capture_review("transfer")
	app.show_options()
	app.options_panel.show_section("motion")
	await capture_review("motion")
	app.notify("Motion steering centered. Hold this position when resuming flight.")
	check(app.options_panel.section == "notice", "Motion calibration feedback is visible")
	await capture_review("motion-notice")
	app.queue_free()
	await process_frame


func capture_review(name: String):
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[1] == "mobile" or DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1] + "-" + name + ".png")
