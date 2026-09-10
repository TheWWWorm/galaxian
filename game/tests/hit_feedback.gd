extends "res://tests/integration.gd"


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open hit feedback content")
	if failures:
		quit(1)
		return
	var zip := ZIPReader.new()
	zip.open(args[1])
	var source := zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	await check_player_hit_effects(source, lib)
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		lib.content.player_hit.shake == {"duration": 1.0, "units_per_ms": .005},
		"Source camera shake duration and quarter-scale amplitude"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x5f872, 2), 0x237d)
	check(
		reader.player_hit_presentation().shake.duration == .5,
		"Shake duration follows supplied timer constant"
	)
	for address in [0x54d70, 0x54f30, 0x5f4d8, 0x5f882, 0x5f8e2]:
		reader.error = ""
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0)
		check(
			reader.player_hit_presentation().is_empty(),
			"Reject unsupported hit binding %x" % address
		)
	for original in [false, true]:
		var pilot := Session.new()
		pilot.configure(lib, true)
		pilot.depart()
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, pilot, {"original_flight_controls": original}, true)
		flight.set_physics_process(false)
		flight.ship.position = Vector3(10000, 10000, 10000)
		flight.update_camera(1)
		var hit = flight.player_hit
		hit.set_process(false)
		pilot.shield = 0
		for incoming in [Vector3.LEFT, Vector3.FORWARD, Vector3.UP, Vector3.DOWN]:
			flight.hit(1, incoming)
			check(
				(-hit.global_basis.z).is_equal_approx(incoming),
				"Hit flash faces incoming weapon, including vertical hits"
			)
			check(
				hit.global_position.is_equal_approx(flight.ship.global_position),
				"Directional flash stays at player position"
			)
		hit.begin_step()
		hit.begin_step()
		check(hit.meshes.hull.visible, "Multiple updates cannot erase unseen hit")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			check(
				hit.presented and hit.meshes.hull.visible,
				"Real rendered frame presents hit before clearing"
			)
		else:
			hit.mark_presented()
		hit.begin_step()
		check(not hit.meshes.hull.visible, "Presented flash clears")
		var heading: Basis = flight.ship.basis
		var motion: Dictionary = pilot.motion.duplicate(true)
		flight.update_camera(.016)
		check(
			(
				hit.camera_offset_applied
				and not flight.camera.global_transform.is_equal_approx(hit.camera_pose)
			),
			"Damage shakes camera in both control modes"
		)
		check(
			flight.ship.basis == heading and pilot.motion == motion,
			"Shake leaves steering and inertia intact"
		)
		check(
			(
				(flight.camera.global_position - hit.camera_pose.origin).length()
				<= sqrt(3.0) * .04 + .0001
			),
			"Shake follows source amplitude"
		)
		var remaining: float = hit.shake_remaining
		flight.hit(1, Vector3.RIGHT)
		check(hit.shake_remaining == remaining, "Repeated hits do not extend active shake")
		flight.pause(true)
		flight._physics_process(.1)
		check(hit.shake_remaining == remaining, "Pause freezes shake")
		flight.pause(false)
		for tick in 65:
			flight.update_camera(.016)
		check(
			hit.shake_remaining == 0 and not hit.camera_offset_applied,
			"Shake expires and restores unshaken camera"
		)
		flight.first_person = true
		flight.hit(1, Vector3.LEFT)
		flight.update_camera(.016)
		check(hit.camera_offset_applied, "First-person damage also shakes camera")
		hit.data = hit.data.duplicate(true)
		hit.data.sounds.hull = [11]
		hit.flash(0, flight.ship.global_transform)
		hit.flush_sound()
		var first: AudioStreamPlayer = hit.audio
		if DisplayServer.get_name() != "headless":
			await create_timer(.12).timeout
		hit.data.sounds.hull = [12]
		hit.flash(0, flight.ship.global_transform)
		hit.flush_sound()
		check(
			hit.audio != first and hit.voices[11] == first,
			"Different impact variants own independent voices"
		)
		if DisplayServer.get_name() != "headless":
			check(
				first.playing and hit.audio.playing,
				"Different impact tails really overlap in audio mixer"
			)
		hit.data.sounds.hull = [11]
		hit.flash(0, flight.ship.global_transform)
		hit.flush_sound()
		check(
			hit.audio == first and hit.voices.size() == 2, "Repeated variant reuses its own voice"
		)
		pilot.hull = 1
		flight.hit(2, Vector3.FORWARD)
		check(
			hit.shake_remaining == 0 and not hit.meshes.hull.visible,
			"Fatal damage clears hit effects for destruction presentation"
		)
		flight.queue_free()
		await process_frame
	print("HIT FEEDBACK ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)
