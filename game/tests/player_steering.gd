extends "res://tests/integration.gd"
const Steering = preload("res://src/simulation/player_steering.gd")

func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open steering content")
	if failures: quit(1); return
	var zip := ZIPReader.new()
	zip.open(args[1])
	var source := zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	check_reader(source, lib)
	check_dynamics(lib)
	await check_flight(lib)
	print("PLAYER STEERING ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)

func check_reader(source, lib):
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index supplied declarations")
	var data: Dictionary = reader.player_steering()
	check(same_saved_value(data, lib.content.player_motion.steering), "Imported steering matches bounded reader")
	check(data.agilities == [44, 55, 37, 28] and data.ship_type_column == 1, "Recover ship-type agility table")
	check(is_equal_approx(data.reference_seconds, 1.0 / 60) and data.default_response == 1.0, "Recover source timer and default response")
	check(data.release_divisors == [189, 126] and data.bank_scale == 16 and data.pitch_bank_divisor == 8, "Recover directional release and bank declarations")
	var table := reader.symbol_address("__ZL9AGILITIES")
	reader.bytes = source.duplicate()
	reader.bytes.encode_s32(reader.file_offset(table, 4), 33)
	var changed: Dictionary = reader.player_steering()
	check(changed.agilities[0] == 33 and is_equal_approx(Steering.maximum_rate(changed, 33), Steering.maximum_rate(data, 44) * .75), "Supplied agility changes actual native turn cap")
	reader.bytes.encode_s32(reader.file_offset(table, 4), 0)
	reader.error = ""
	check(reader.player_steering().is_empty() and not reader.error.is_empty(), "Reject invalid source agility")
	reader.bytes = source.duplicate(); reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(reader.symbol_address("__ZN9PlayerEgoC2EP6Player") + 0x152, 2), 0)
	check(reader.player_steering().is_empty() and not reader.error.is_empty(), "Reject unsupported agility consumer")
	reader.bytes = source.duplicate(); reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(reader.symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera") + 0x1ac, 2), 0)
	check(reader.player_steering().is_empty() and not reader.error.is_empty(), "Reject changed held-input damping semantics")
	reader.bytes = source.duplicate(); reader.error = ""
	var globals := reader.symbol_address("__ZN7Globals4initEPN11AbyssEngine18ApplicationManagerEPNS0_6EngineE")
	reader.bytes.encode_float(literal_file_offset(reader, globals + 0x36), 2.0)
	changed = reader.player_steering()
	check(changed.default_response == 2.0 and Steering.acceleration(changed, 44) > Steering.acceleration(data, 44), "Supplied response preference changes angular acceleration")

func check_dynamics(lib):
	var data: Dictionary = lib.content.player_motion.steering
	var limit := Steering.maximum_rate(data, 44)
	var acceleration := Steering.acceleration(data, 44)
	var net_acceleration := acceleration - Steering.release_rate(data, 44, 0)
	check(absf(limit - 3.013176) < .00001 and absf(acceleration - 4.585269) < .00001, "Convert native units to independent radians/second oracle")
	var state := [0.0, 0.0]
	var angle := Steering.advance(state, data, 44, Vector2(1, 0), .1)
	check(absf(state[0] - net_acceleration * .1) < .000001 and absf(angle.x - .5 * net_acceleration * .01) < .000001, "Held input integrates drive minus continuous damping")
	Steering.advance(state, data, 44, Vector2.ONE, 10)
	check(is_equal_approx(state[0], limit) and is_equal_approx(state[1], limit), "Sustained input reaches ship turn cap")
	Steering.advance(state, data, 44, Vector2.ZERO, .1)
	check(state[0] > state[1] and state[0] < limit, "Source pitch releases faster than yaw")
	Steering.advance(state, data, 44, Vector2.ZERO, 10)
	check(state == [0.0, 0.0] and Steering.bank(state, data) == Vector3.ZERO, "Released controls settle to level without drifting forever")
	Steering.advance(state, data, 44, Vector2(.5, -.5), 10)
	check(is_equal_approx(state[0], limit * .25) and is_equal_approx(state[1], -limit * .25), "Half analog deflection uses source square curve")
	var bank := Steering.bank(state, data)
	check(bank.z > 0 and bank.x < 0 and absf(bank.z / bank.x + 8) < .00001, "Hull bank uses independent source yaw and pitch scales")
	for hz in [30, 60, 120]:
		var whole := [0.0, 0.0]
		var split := [0.0, 0.0]
		var whole_angle := Vector2.ZERO
		var split_angle := Vector2.ZERO
		for input in [Vector2.ONE, Vector2(-.5, .25), Vector2.ZERO]:
			whole_angle += Steering.advance(whole, data, 44, input, 2.0)
			for tick in 2 * hz: split_angle += Steering.advance(split, data, 44, input, 1.0 / hz)
		check(whole_angle.distance_to(split_angle) < .0001 and Vector2(whole[0], whole[1]).distance_to(Vector2(split[0], split[1])) < .00001, "Ramp, reversal and release agree at %d Hz" % hz)
	for invalid in [[], [NAN, 0], [INF, 0], [0, "0"], [1000, 0]]:
		check(not Steering.valid(invalid, data), "Reject malformed angular state")
	var mouse := Steering.mouse_axis(Vector2(.01, -.02), .02, limit)
	state = [0.0, 0.0]
	Steering.advance(state, data, 44, mouse, 10)
	check(is_equal_approx(state[0], .5) and is_equal_approx(state[1], -1.0), "Mouse angular request maps through the analog curve")

func check_flight(lib):
	var pilot := Session.new(); pilot.configure(lib, true); pilot.depart()
	var flight := Flight.new(); root.add_child(flight); flight.setup(lib, pilot, {"original_flight_controls": true})
	flight.set_physics_process(false); flight.ship.position = Vector3(2000, 0, 2000)
	for id in lib.ships.size():
		pilot.ship_id = id
		check(flight.player_agility() == lib.content.player_motion.steering.agilities[int(lib.ships[id][1])], "Playable ship selects own source agility: %d" % id)
	pilot.ship_id = 0
	flight.controls.touch_look = Vector2(1, -.5)
	flight.step(.2)
	check(pilot.motion.turn[0] < 0 and pilot.motion.turn[1] > 0 and not flight.player_hull.basis.is_equal_approx(flight.player_hull_rest), "Actual stick path turns and banks the rendered hull")
	var saved := pilot.capture()
	var copy := Session.new(); copy.configure(lib, true)
	check(copy.restore(JSON.parse_string(JSON.stringify(saved))) and same_saved_value(copy.motion.turn, pilot.motion.turn), "Save and load preserve a live turn")
	flight.pause(true)
	flight._physics_process(1)
	check(same_saved_value(pilot.motion.turn, copy.motion.turn), "Pause freezes angular state")
	var legacy := saved.duplicate(true); legacy.schema = 28; legacy.motion.erase("turn")
	check(copy.restore(legacy) and copy.motion.turn == [0.0, 0.0], "Previous campaign/exploration save migrates to neutral turn")
	var bad := saved.duplicate(true); bad.motion.turn = [NAN, 0]
	check(not copy.restore(bad), "Session rejects non-finite angular state")
	var arcade := preload("res://src/simulation/survival_session.gd").new()
	check(arcade.configure_survival(lib, lib.content.survival, 0, 0, 47), "Configure survival turn migration")
	legacy = arcade.capture(); legacy.schema = 10; legacy.motion.erase("turn")
	check(arcade.restore(legacy) and arcade.motion.turn == [0.0, 0.0], "Previous survival save migrates to neutral turn")
	flight.queue_free()
	await process_frame
