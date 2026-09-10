extends "res://tests/player_feedback.gd"
const Effects = preload("res://src/presentation/flight_effects.gd")
const Trails = preload("res://src/presentation/ship_trails.gd")


func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open flight effects content")
	if failures:
		quit(1)
		return
	var zip := ZIPReader.new()
	zip.open(args[1])
	var source := zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	check_source(source, lib)
	await check_effects(lib)
	await check_survival_trails(lib)
	if args.size() > 2:
		await capture_demo(lib, args[2])
	print("FLIGHT EFFECTS ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)


func check_source(source, lib):
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Parse effect declarations")
	var data: Dictionary = reader.flight_effects()
	check(same_saved_value(data, lib.content.flight_effects), "Cache matches source effects reader")
	check(
		data.ramp_seconds == .833 and data.release_at == 5 and data.end_at == 6,
		"Boost ramp .833 s, release 4.165 s, zero 4.998 s"
	)
	check(
		data.stars.count == 50 and data.stars.boost_length == 90 and data.stars.boost_width == 0,
		"Source boost lengthens stars tenfold without widening them"
	)
	check(
		data.trails.segments == 40 and data.trails.survival_limits == [2, 5],
		"Recover trail history and tier boundaries"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_float(literal_file_offset(reader, 0x44fcc), 150.0)
	check(
		is_equal_approx(reader.flight_effects().fov_boost_degrees, data.fov_boost_degrees / 2),
		"FOV follows supplied constant mutation"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(0x54aaa, 2), 0)
	check(
		reader.flight_effects().is_empty() and not reader.error.is_empty(),
		"Reject broken player particle binding"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(0x29992, 2), 0)
	check(
		reader.flight_effects().is_empty() and not reader.error.is_empty(),
		"Reject unsupported Survival trail binding"
	)
	for elapsed in [0.0, .4165, .833, 2.0, 4.165, 4.5815, 4.998, 5.1]:
		var expected: float = [0.0, .5, 1.0, 1.0, 1.0, .5, 0.0, 0.0][
			[0.0, .4165, .833, 2.0, 4.165, 4.5815, 4.998, 5.1].find(elapsed)
		]
		check(
			is_equal_approx(Effects.percentage(data, elapsed), expected),
			"Independent boost-envelope oracle at %.4f seconds" % elapsed
		)
	check(
		(
			Effects.field_of_view(data, 2.0, true) == 79.1015625
			and Effects.field_of_view(data, 2.0, false) == 52.734375
		),
		"Source angle units give normal and boosted FOV"
	)
	check(
		data.boost_sound == 7 and lib.content.sound_bank["7"].path == "data/sounds/fx_boost_01.wav",
		"Recover the source boost cue and registered asset"
	)
	var invalid := data.duplicate(true)
	invalid.stars.reference_seconds = 0
	check(
		not Effects.valid(invalid, lib.content.materials, lib.content.projectile_trails.styles),
		"Reject zero particle timestep"
	)


func check_effects(lib):
	var data: Dictionary = lib.content.flight_effects
	var stars := Effects.new()
	root.add_child(stars)
	stars.configure(lib)
	stars.random.seed = 42
	for tick in 60:
		stars.advance(1.0 / 60, Transform3D.IDENTITY, false, 0)
	check(stars.spawned == 30, "Normal star spawn cadence follows source clock")
	var alive := stars.particles.filter(func(p): return p.life > 0)
	check(
		alive.size() == 30 and alive[0].node.scale.z == 10, "Normal flight has visible short stars"
	)
	stars.advance(1.0 / 60, Transform3D.IDENTITY, true, 1)
	check(
		(
			stars.spawned == 31
			and stars.particles[0].node.scale.z == 100
			and stars.particles[0].node.scale.x == 1
		),
		"Boost extends the existing star field"
	)
	var position: Vector3 = stars.particles[0].node.position
	stars.advance(0, Transform3D.IDENTITY, true, 1)
	check(stars.particles[0].node.position == position, "Zero elapsed time freezes particles")
	stars.advance(1.0 / 60, Transform3D.IDENTITY, false, 0)
	check(stars.particles[0].node.scale.z == 10, "Star length resets after boost")
	stars.queue_free()
	var enemy: Array = Trails.declarations(data.trails, 0, true, 0)
	var ally: Array = Trails.declarations(data.trails, 0, false, 0)
	check(enemy[0].style == 1 and ally[0].style == 2, "Campaign uses source red and green styles")
	for type in data.trails.excluded:
		check(
			Trails.declarations(data.trails, int(type), true, 0).is_empty(),
			"Honor source no-trail ship type %d" % type
		)
	var dual: Array = Trails.declarations(data.trails, 18, true, 0)
	check(
		dual.size() == 2 and dual[1].segments == 80 and dual[0].offset == Vector3(35.6, -5, 29),
		"Large ship gets the two source mounting offsets/history sizes"
	)
	for tier in 10:
		var declaration: Array = Trails.declarations(data.trails, 0, true, 0, tier)
		var trail := Trails.new()
		root.add_child(trail)
		trail.configure(lib, declaration, Transform3D.IDENTITY)
		var color: Color = [Color.hex(0xffff00ff), Color.hex(0xff4000ff), Color.hex(0xff0000ff)][
			0 if tier <= 2 else (1 if tier <= 5 else 2)
		]
		check(
			trail.ribbons[0].tint == color and declaration[0].style == 1,
			"Survival tier %d changes tint while retaining ship UVs" % tier
		)
		trail.advance(.162, Transform3D(Basis.from_euler(Vector3(0, 1, 0)), Vector3(20, 0, 0)))
		check(
			(
				trail.ribbons[0].points[0].is_equal_approx(Vector3(20, 0, 0))
				and trail.ribbons[0].points[1].is_equal_approx(Vector3(10, 0, 0))
			),
			"Ship trail samples elapsed time and preserves world history"
		)
		trail.queue_free()
	for original in [false, true]:
		var state := Session.new()
		state.configure(lib, true)
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, state, {"original_flight_controls": original}, true)
		flight.set_physics_process(false)
		flight.ship.position = Vector3(2000, 0, 2000)
		state.motion.throttle = 1.0
		var nozzle = flight.player_burner.nozzles[0]
		var base: Vector3 = nozzle.get_meta("exhaust_scale")
		flight.controls.touch_boost = true
		flight.step(1.0 / 60)
		check(
			(
				flight.boost_audio.playing
				and flight.boost_audio.stream == lib.sound_clip(7)
				and flight.boost_audio.bus == "GoF Effects"
			),
			"Accepted boost plays the supplied cue on the effects bus"
		)
		flight.boost_audio.stop()
		for tick in 59:
			flight.step(1.0 / 60)
			flight.update_camera(1.0 / 60)
		check(
			flight.boosting() and flight.camera.fov > 79 and nozzle.scale.z > base.z,
			"Both controls get actual boost FOV and enlarged engine flare"
		)
		check(
			(
				flight.flight_effects.spawned > 0
				and flight.flight_effects.particles.any(
					func(p): return p.node.visible and p.node.scale.z > 90
				)
			),
			"Actual Flight drives boost stars"
		)
		check(not flight.boost_audio.playing, "Holding boost does not restart its sound")
		var phase: float = flight.player_burner.phase
		var spawn_count: int = flight.flight_effects.spawned
		flight.paused = true
		flight._physics_process(.2)
		flight.step(.2)
		check(
			flight.player_burner.phase == phase and flight.flight_effects.spawned == spawn_count,
			"Pause freezes flare and particles"
		)
		flight.paused = false
		var restored := Flight.new()
		root.add_child(restored)
		restored.setup(lib, state, {"original_flight_controls": original}, true)
		restored.set_physics_process(false)
		check(
			restored.camera.fov == flight.camera.fov and restored.player_burner.extension > 0,
			"Loading during boost restores FOV and flare extension"
		)
		check(
			not restored.boost_audio.playing,
			"Restoring an ongoing boost does not replay the activation cue"
		)
		restored.queue_free()
		flight.controls.touch_boost = false
		for tick in 330:
			flight.step(1.0 / 60)
			flight.update_camera(1.0 / 60)
		check(
			(
				not flight.boosting()
				and flight.camera.fov == data.fov_degrees
				and flight.player_burner.extension == 0
			),
			"Boost end restores camera and burner after release"
		)
		flight.controls.touch_boost = true
		flight.step(1.0 / 60)
		check(not flight.boost_audio.playing, "A boost rejected during recharge stays silent")
		flight.controls.touch_boost = false
		flight.step(1.0 / 60)
		state.motion.cooldown = 0
		flight.controls.touch_boost = true
		flight.step(1.0 / 60)
		check(flight.boost_audio.playing, "A fresh accepted boost plays again")
		flight.pause(true)
		check(flight.boost_audio.stream_paused, "Pause holds boost audio playback")
		flight.queue_free()
		await process_frame
	# Real campaign fighters, not only an isolated renderer.
	var session := Session.new()
	session.configure(lib)
	session.chapter = 3
	session.progression = Session.Progression.create(3)
	session.station_id = lib.chapter_destination(2)
	check(session.depart(), "Launch source fighter mission")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, session, {}, true)
	flight.set_physics_process(false)
	var trailed := flight.actors.filter(func(a): return a.node.has_meta("ship_trails"))
	check(not trailed.is_empty(), "Campaign fighter visuals own source trails")
	if not trailed.is_empty():
		var actor: Dictionary = trailed[0]
		var trail = actor.node.get_meta("ship_trails")
		trail.advance(.2, Transform3D(Basis.IDENTITY, actor.node.position + Vector3(30, 0, 0)))
		check(trail.ribbons[0].visible, "Campaign trail renders after movement")
		flight.actor_destroyed(actor)
		check(
			trail.is_queued_for_deletion(),
			"Destroyed actor removes its trail before wreck attachment"
		)
	flight.queue_free()
	await process_frame


func capture_demo(lib, folder):
	var app := FeedbackMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib, true)
	app.settings.original_flight_controls = true
	app.launch()
	app.flight.set_physics_process(false)
	app.flight.ship.position = Vector3(2000, 0, 2000)
	app.flight.camera.position = app.flight.ship.position + Vector3(0, 15, 43)
	app.session.motion.throttle = 1
	for frame in 240:
		app.flight.controls.touch_boost = frame >= 30 and frame < 180
		for tick in 2:
			app.flight.step(1.0 / 60)
			app.flight.update_camera(1.0 / 60)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("frame-%03d.png" % frame))
	app.music.stop()
	app.stop_flight()
	app.queue_free()
	await process_frame


func check_survival_trails(lib):
	var Arcade = preload("res://src/simulation/survival_session.gd")
	var session := Arcade.new()
	check(
		session.configure_survival(lib, lib.content.survival, 0, 0, 47),
		"Create actual Survival trail fixture"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, session, {}, true)
	flight.set_physics_process(false)
	var first = flight.actors[0].node.get_meta("ship_trails")
	check(first.ribbons[0].tint == Color.hex(0xffff00ff), "Initial Survival fighter renders yellow")
	# Exercise the real director/respawn path until it has selected all tiers.
	session.active_job.survival.score = 100000
	session.active_job.survival.active_count = 9
	var seen := {}
	for seed_value in 64:
		session.active_job.survival.phase = "spawn"
		session.active_job.survival.seed = seed_value
		var actor: Dictionary = session.active_job.actors[0]
		actor.hp = 0
		actor.destruction.phase = "dead"
		flight.spawn_targets()
		await process_frame
		session.advance_mission(2.001)
		flight.spawn_targets()
		var visual = flight.actors.filter(func(a): return int(a.index) == 0)[0].node
		check(visual.has_meta("ship_trails"), "Respawn installs a new ship trail")
		var trail = visual.get_meta("ship_trails")
		var kind := 0 if actor.archetype <= 2 else (1 if actor.archetype <= 5 else 2)
		seen[kind] = true
		check(
			(
				trail.ribbons[0].tint
				== [Color.hex(0xffff00ff), Color.hex(0xff4000ff), Color.hex(0xff0000ff)][kind]
			),
			"Survival respawn color follows selected archetype"
		)
		check(
			not trail.ribbons[0].visible,
			"Respawn starts fresh history, without a line from the old death position"
		)
		if seen.size() == 3:
			break
	check(seen.size() == 3, "Actual Survival respawns exercised all three difficulty colors")
	# Restore a real initial save separately; the forced director fixture above
	# deliberately changes score/seed without claiming those values came from play.
	var initial := Arcade.new()
	initial.configure_survival(lib, lib.content.survival, 0, 0, 47)
	var copy := Arcade.new()
	copy.configure_survival(lib, lib.content.survival, 0, 0, 47)
	check(
		copy.restore(initial.capture()),
		"Survival save remains valid with cosmetic trail state omitted"
	)
	var resumed := Flight.new()
	root.add_child(resumed)
	resumed.setup(lib, copy, {}, true)
	resumed.set_physics_process(false)
	var restored = (
		resumed.actors.filter(func(a): return int(a.index) == 0)[0].node.get_meta("ship_trails")
	)
	check(
		restored.ribbons[0].tint == Color.hex(0xffff00ff),
		"Restored Survival ship recreates its difficulty color"
	)
	flight.queue_free()
	resumed.queue_free()
	await process_frame
