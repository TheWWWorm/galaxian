extends SceneTree
const Importer = preload("res://src/content/ipa_import.gd")
const Library = preload("res://src/content/library.gd")
const Session = preload("res://src/simulation/session.gd")
const Formats = preload("res://src/content/formats.gd")
const NativeData = preload("res://src/content/native_data.gd")
const Contracts = preload("res://src/simulation/contracts.gd")
const ContractEncounters = preload("res://src/simulation/contract_encounters.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Flight = preload("res://src/presentation/flight.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Supply a private IPA path after --")
		quit(2)
		return
	var importer := Importer.new()
	importer.cache_base = "user://test-content"
	var frames := [0]
	var progress_on_main := [true]
	var observe := func():
		if importer.native_job != null and importer.native_job.is_alive():
			frames[0] += 1
			if frames[0] == 1:
				check(
					not await importer.install(args[0], self),
					"Reject overlapping import without disturbing its worker"
				)
	var observe_progress := func(_message, _ratio):
		progress_on_main[0] = progress_on_main[0] and Thread.is_main_thread()
	process_frame.connect(observe)
	importer.progress.connect(observe_progress)
	check(await importer.install(args[0], self), "IPA import: " + importer.error)
	process_frame.disconnect(observe)
	importer.progress.disconnect(observe_progress)
	check(frames[0] > 1, "Main-loop frames continue while embedded data is read")
	check(progress_on_main[0], "Import progress reaches UI on the main thread")
	check(
		not importer.installing and importer.native_job == null,
		"Completed import joins and releases its worker"
	)
	if failures:
		quit(1)
		return
	var lib := Library.new()
	check(lib.open(importer.root, importer.content_id), "Open imported content")
	check(lib.stations.size() == 500, "All supplied stations imported")
	check(lib.systems.size() == 100, "All supplied systems imported")
	check(lib.ships.size() == 10 and lib.items.size() == 28, "All supplied catalogues imported")
	check(lib.ship_name(0) == "Icarus", "Localized ship name from extracted association")
	check(lib.content.chapters.size() == 13, "Imported campaign chapters")
	check(
		lib.content.opening.target_count == 5 and lib.content.opening.route.size() == 3,
		"Recovered opening scenario"
	)
	check(
		lib.actor_model(int(lib.content.opening.actor_type)) == "drone",
		"Training actor uses source model mapping"
	)
	check(not importer.metadata.files.has("GalaxyOnFire"), "Original executable is not cached")
	await check_import_cancellation(args[0], importer)
	await check_embedded(args[0], lib)
	await check_player_armament_runtime(lib)
	check_player_armament_validation(lib)
	await check_trail_mode_boundaries(lib)
	check_contract_boards(lib)
	check_contract_sessions(lib)
	await check_economy(lib)
	check_radio(lib)
	check_dialogue_modality(lib)
	check_briefing(lib)
	check_radio_presentation(lib)
	check_progression(lib)
	check_interception(lib)
	check_escort(lib)
	check_assault(lib)
	check_duel(lib)
	await check_convoy(lib)
	check_allied_combat(lib)
	check_directed_scenery_collision(lib)
	check_scenery(lib)
	await check_campaign_scene_geometry(lib)
	check_ballistics(lib)
	check(lib.item_name(15) == lib.text(152), "Item names use imported language records")
	var formats := Formats.new()
	var meshes := 0
	var textures := 0
	for file in importer.metadata.files:
		if str(file).ends_with(".aem"):
			check(not formats.aem(lib.read(file)).is_empty(), "Parse " + file)
			meshes += 1
		elif str(file).ends_with(".aei"):
			check(not formats.aei(lib.read(file)).is_empty(), "Parse " + file)
			textures += 1
	check(meshes == 127 and textures == 9, "Complete supplied mesh and texture inventory")
	check(formats.aem(PackedByteArray([1, 2, 3])).is_empty(), "Reject truncated mesh")
	var malformed := lib.read("data/meshes/protagonist_01.aem")
	malformed.resize(malformed.size() - 1)
	check(formats.aem(malformed).is_empty(), "Reject truncated mesh payload")
	check(formats.aei(PackedByteArray()).is_empty(), "Reject truncated texture")
	var old_root := importer.root
	check(not await importer.install(args[0] + ".missing", self), "Reject missing archive")
	check(importer.root == old_root, "Failed import preserves active content")
	var source := Session.new()
	source.configure(lib)
	source.market_seed = 22
	check(not source.exploration_unlocked(), "Campaign starts with exploration locked")
	check(not source.travel(1), "Campaign cannot bypass map gate")
	check(source.depart(), "Start training")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, source, {})
	flight.set_physics_process(false)
	# Follow the imported route and fight when the source proximity cue begins.
	# Christine can engage first; completion is destruction, not a route gate.
	flight.auto_pilot = true
	var instruction_before_kill := false
	for tick in 24000:
		if source.active_job.kills == 0 and source.active_job.radio.shown.has(10):
			instruction_before_kill = true
		var hostiles := flight.actors.filter(flight.hostile)
		if instruction_before_kill and not hostiles.is_empty():
			var target: Node3D = hostiles[0].node
			flight.auto_pilot = false
			flight.ship.look_at(target.position, Vector3.UP)
			flight.throttle = (
				1.0 if flight.ship.position.distance_to(target.position) > 180 else 0.0
			)
			flight.fire()
		flight.step(1.0 / 60.0)
		if source.active_job.ready or source.hull <= 0:
			break
		source.advance_radio(1.0 / 60.0)
	check(
		source.active_job.ready and source.hull > 0,
		"Native flight and weapons complete the source opening encounter"
	)
	check(instruction_before_kill, "Opening shooting instruction precedes target destruction")
	check(source.active_job.actors.back().route_stage > 0, "Christine follows the source route")
	var mid := source.capture()
	var resumed := Session.new()
	resumed.configure(lib)
	check(resumed.restore(mid), "Restore in-flight training")
	check(
		resumed.active_job.stage == source.active_job.stage and not resumed.docked,
		"Keep mission stage on reload"
	)

	check(not source.finish_mission(), "Completion waits for the closing radio transmission")
	drain_radio(source)
	flight.step(1.0 / 60.0)
	check(flight.paused, "Mission simulation stops at objective completion")
	check(
		source.finish_mission() and source.station_id == lib.chapter_destination(0),
		"Training completion transfers to its imported station"
	)
	check(
		source.chapter == 1 and not source.exploration_unlocked(),
		"Tutorial completion does not unlock full-game exploration"
	)
	check(not source.complete_campaign(), "Unimplemented finale cannot grant completion")
	await check_clearance(lib, source)
	await check_enemy_flight(lib, source)
	await check_escort_flight(lib, source)
	for next_chapter in range(4, 13):
		if source == null or source.chapter != next_chapter:
			printerr("SKIP: Remaining continuous campaign depends on the failed chapter replay.")
			break
		match next_chapter:
			4:
				source = await check_assault_flight(lib, source)
			5:
				source = await check_duel_flight(lib, source)
			6:
				source = await check_convoy_flight(lib, source)
			7:
				source = await check_cruiser_flight(lib, source)
			8:
				source = await check_rescue_flight(lib, source)
			9:
				source = await check_strike_flight(lib, source)
			10:
				source = await check_ambush_flight(lib, source)
			11:
				source = await check_pursuit_flight(lib, source)
			12:
				await check_finale_flight(lib, source, args[0])

	flight.queue_free()
	await process_frame
	var sandbox := Session.new()
	sandbox.configure(lib, true)
	check(
		sandbox.exploration_unlocked() and sandbox.campaign_state == "skipped",
		"Skip enters sandbox explicitly"
	)
	check(
		sandbox.credits == int(lib.content.initial.credits) and sandbox.chapter == 0,
		"Skipping grants no campaign rewards"
	)
	sandbox.credits += int(sandbox.travel_quote(499).total)
	check(sandbox.travel(499), "Funded sandbox reaches last imported station")
	check(not sandbox.begin_patrol(), "Do not invent freelance missions")
	check(not sandbox.trade(15, true), "Do not invent stock or price rules")
	check(
		sandbox.credits == int(lib.content.initial.credits),
		"Unsupported actions do not change money"
	)
	var path := "user://test-saves/" + lib.id + "/pilot.json"
	check(sandbox.save(path), "Atomic save")
	sandbox.credits += 10
	check(sandbox.save(path), "Save backup")
	var loaded := Session.new()
	loaded.configure(lib, true)
	check(loaded.load_save(path), "Reload saved pilot")
	check(
		(
			loaded.station_id == 499
			and loaded.cargo_used() == 0
			and loaded.campaign_state == "skipped"
		),
		"Reload preserves location and campaign choice"
	)
	var invalid := loaded.capture().duplicate(true)
	invalid.content_id = "different"
	check(not loaded.restore(invalid), "Reject save from different content")
	invalid = loaded.capture().duplicate(true)
	invalid.hull = "bad"
	check(not loaded.restore(invalid), "Reject malformed health")
	invalid = loaded.capture().duplicate(true)
	invalid.cargo = {"15": 9999}
	check(not loaded.restore(invalid), "Reject over-capacity cargo")
	var damaged := FileAccess.open(path, FileAccess.WRITE)
	damaged.store_string("broken")
	damaged.close()
	check(loaded.load_save(path), "Recover from previous checkpoint when current save is corrupt")
	# Render-library construction is exercised headlessly; visual QA is separate.
	check(lib.mesh("protagonist_01").get_surface_count() == 1, "Native Godot mesh construction")
	check(lib.texture().get_width() == 1024, "Native Godot texture construction")
	print(
		"CHECKS %d | FAILURES %d | MESHES %d | TEXTURES %d" % [checks, failures, meshes, textures]
	)
	quit(1 if failures else 0)


func check_embedded(ipa: String, lib) -> void:
	var zip := ZIPReader.new()
	zip.open(ipa)
	var prefix := ""
	for path in zip.get_files():
		if path.ends_with(".app/data/txt/ships.txt"):
			prefix = path.trim_suffix("data/txt/ships.txt")
	var source := zip.read_file(prefix + prefix.trim_suffix("/").get_file().trim_suffix(".app"))
	zip.close()
	for phase in [
		"Reading application index",
		"Reading campaign encounters",
		"Reading materials",
		"Reading freelance encounters"
	]:
		var cancelled_reader := NativeData.new()
		var result := cancelled_reader.extract(source, func(message): return message != phase)
		check(
			result.is_empty() and cancelled_reader.error == "Import cancelled.",
			"Cancellation stops at an embedded-data checkpoint"
		)
		check(
			cancelled_reader.bytes.is_empty() and not cancelled_reader.reporter.is_valid(),
			"Cancelled reader releases original application bytes and callbacks"
		)
	check_player_motion(source, lib)
	check_opening_encounter(source, lib)
	check_shared_projectile_pools(source, lib)
	check_fighter_aim(source, lib)
	check_turret_aim(source, lib)
	check_assault_mutations(source)
	check_duel_mutations(source)
	check_convoy_parameters(source, lib)
	check_cruiser_data(source, lib)
	check_rescue_data(source, lib)
	check_strike_data(source, lib)
	check_ambush_data(source, lib)
	check_mines(source, lib)
	check_pursuit_foundation(source, lib)
	check_pursuit_director(source, lib)
	check_finale_foundation(source, lib)
	check_finale_director(source, lib)
	check_contract_rules(source, lib)
	check_contract_hunts(source, lib)
	check_hunt_spawn_scatter(source, lib)
	check_clearance_contracts(source, lib)
	check_minefield_contracts(source, lib)
	check_intercept_contracts(source, lib)
	check_capture_contracts(source, lib)
	check_recovery(source, lib)
	check_survival_rules(source)
	check_survival_setup(source, lib)
	check_survival_armament(source, lib)
	check_survival_runtime(source, lib)
	check_survival_session_validation(source, lib)
	check_survival_saves(source, lib)
	check_survival_scores(source, lib)
	check_survival_archive(source, lib)
	await check_survival_result(source, lib)
	await check_survival_name(source, lib)
	await check_survival_tabs(source, lib)
	await check_survival_hud(source, lib)
	await check_survival_main(source, lib)
	await check_survival_backdrop(source, lib)
	await check_survival_radar(source, lib)
	await check_survival_player_guns(source, lib)
	check_paired_player_armament(source, lib)
	check_plasma_player_armament(source, lib)
	check_missile_player_armament(source, lib)
	check_multi_projectile_player_armament(source, lib)
	await check_projectile_trails(source, lib)
	await check_lens_flare(source, lib)
	await check_npc_rocket_trail(source, lib)
	check_survival_content(lib)
	await check_registered_survival_flow(lib)
	await check_choice_presentation(source, lib)
	check_escort_contracts(source, lib)
	check_asteroid_contract_declarations(source, lib)
	check_asteroid_lifecycle(source, lib)
	check_freelance_guns(source, lib)
	check_transport_declarations(source)
	check_rocket_guidance(source, lib)
	check_ship_exhaust(source, lib)
	check_player_exhaust_speed(lib)
	check_hud_artwork(source, lib)
	check_radar_artwork(source, lib)
	check_radar_lead(source, lib)
	check_radar_hit_feedback(lib)
	check_transport_contracts(lib)
	check_battle_contracts(source, lib)
	check_briefing_source(source, lib)
	check_mesh_colors(lib)
	check_materials(source, lib)
	check_lighting(source, lib)
	check_station_models(source, lib)
	check_briefing_scenes(source, lib)
	await check_briefing_flares(lib)
	await check_damage_feedback(source, lib)
	await check_player_hit_effects(source, lib)
	await check_asteroid_audio(source, lib)
	await check_actor_destruction(source, lib)
	await check_actor_destruction_projectile(lib)
	await check_mine_audio(source, lib)
	await check_player_destruction(source, lib)
	await check_destruction_lifecycle(source, lib)
	await check_wreck_boundaries(lib)
	await check_wreck_drift(source, lib)
	check_wreck_convoy_motion(lib)
	await check_fighter_steering_motion(source, lib)
	check_fighter_overlap_motion(lib)
	await check_fighter_frame(source, lib)
	await check_fighter_frame_boundaries(lib)
	await check_fighter_frame_camera(lib)
	check_fighter_maximum_hull(source, lib)
	await check_fighter_impact(source, lib)
	await check_fighter_targeting(source, lib)
	check_fighter_follow(source, lib)
	check_fighter_placement_boundaries(lib)
	check_menu_traffic(source, lib)
	check_menu_scene(source, lib)
	await check_menu_scene_main(lib)
	await check_title_menu(source, lib)
	await check_station_menu(source, lib)
	await check_pilot_status(source, lib)
	await check_pilot_clock(lib)
	await check_hangar(source,lib)
	await check_options_menu(source,lib)
	await check_pause_menu(source, lib)
	await check_defeat_menu(source, lib)
	await check_desktop_flight_view(lib)
	await check_player_body_contact(source, lib)
	check_body_contact_edges(lib)
	await check_ship_exchange(lib, source)
	check_ship_exchange_limits(lib)
	await check_hangar_scene(source, lib)
	await check_hangar_drift(source, lib)
	await check_mission_board(source, lib)
	await check_destination_menu(source, lib)
	await check_slot_transitions(lib)
	await check_checkpoint_visibility(lib)
	await check_destination_scene(source, lib)
	await check_map_menu(source, lib)
	await check_map_search_input(lib)
	await check_briefing_audio(source,lib)
	await check_briefing_music_context(lib)
	await check_opening_scene(source,lib)
	await check_opening_resume_input(lib)
	check_title_atlas_boundary(source)
	await check_fighter_impact_boundaries(lib)
	await check_npc_exhaust(source, lib)
	await check_npc_exhaust_respawn(lib)
	check_fighter_motion(source)
	await check_fighter_motion_runtime(lib)
	check_fighter_motion_boundaries(lib)
	await check_fighter_evasion(source, lib)
	check_fighter_evasion_boundaries(lib)
	check_evasion_legacy_validation()
	await check_exploration_station_areas(lib)
	await check_exploration_interactions(lib)
	check_exploration_save_scope(lib)
	check_radio_ui_data(source)
	check_flight_ui(source, lib)
	check_map_data(source, lib)
	check_graphical_map(lib)
	check_travel_rules(source, lib)
	check_tutorial(source, lib)
	check_sky(source, lib)
	var reader := NativeData.new()
	check(reader.extract(PackedByteArray()).is_empty(), "Reject truncated native content")
	var damaged := source.duplicate()
	damaged.encode_u32(20, 0xffffffff)
	check(reader.extract(damaged).is_empty(), "Reject overflowing Mach-O commands")
	reader.bytes = source
	reader.error = ""
	check(reader.parse_macho(), "Index original native data for independent mutation checks")
	var constructor: int = reader.symbols["__ZN6StatusC2Ev"][0]
	var instruction := reader.u16(constructor + 2)
	var credit_address := ((constructor + 6) & ~3) + (instruction & 255) * 4
	var credits_offset := reader.file_offset(credit_address, 4)
	var reward_offset := reader.file_offset(reader.symbols["__ZL7REWARDS"][0], 4)
	var collision_offset := reader.file_offset(reader.symbols["__ZL4COLL"][0], 4)
	var mission: int = reader.symbols["__ZN5Level21createCampaignMissionEv"][0]
	var dispatch := reader.calls_between(mission, mission + 128, "___switch32")[0] + 4
	var first := dispatch + reader.u32(dispatch + 4)
	var end := dispatch + reader.u32(dispatch + 8)
	var targets := (
		reader.calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")[0]
	)
	var targets_offset := reader.file_offset(targets - 4, 2)
	var route_offset := reader.file_offset(reader.literal(first, 3), 4)
	var store: int = reader.symbols["__ZN9Generator10getBuyListEP7Station"][0]
	var offer_count_call := (
		reader
		. calls_between(store, reader.symbol_end(store), "__ZN11AbyssEngine8AERandom7nextIntEi")[0]
	)
	var count_offset := reader.file_offset(offer_count_call - 2, 2)
	var depreciation: int = reader.symbols["__ZN9Equipment12priceDeclineEv"][0]
	var depreciation_offset: int = -1
	for address in range(depreciation, reader.symbol_end(depreciation), 2):
		if reader.u16(address) & 0xff00 == 0x4900:
			depreciation_offset = reader.file_offset(
				((address + 4) & ~3) + (reader.u16(address) & 255) * 4, 4
			)
	var second := dispatch + reader.u32(dispatch + 8)
	var third := dispatch + reader.u32(dispatch + 12)
	var clearance_arrays := reader.calls_between(
		second, third, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E"
	)
	var clearance_objects := reader.calls_between(
		second, third, "__ZN5Level18createStaticObjectEP8Waypointi"
	)
	var clearance_objectives := reader.calls_between(second, third, "__ZN9ObjectiveC1EiiP5Level")
	var clearance_count_offset := reader.file_offset(clearance_arrays[0] - 6, 2)
	var clearance_actor_offset := reader.file_offset(clearance_objects[0] - 8, 2)
	var clearance_center_offset := reader.file_offset(reader.literal(second, 3), 4)
	var time_instruction: int = clearance_objectives[0] + 14
	var deadline_offset := reader.file_offset(
		((time_instruction + 4) & ~3) + (reader.u16(time_instruction) & 255) * 4, 4
	)
	var radio_function: int = reader.symbols["__ZN5Level19createRadioMessagesEi"][0]
	var radio_switch := (
		reader.calls_between(radio_function, radio_function + 256, "___switch32")[0] + 4
	)
	var radio_first := radio_switch + reader.u32(radio_switch + 8)
	var radio_end := radio_switch + reader.u32(radio_switch + 12)
	var cue := reader.calls_between(radio_first, radio_end, "__ZN12RadioMessageC1Eiiii")[0]
	var cue_text_offset := reader.file_offset(cue - 14, 2)
	var cue_speaker_offset := reader.file_offset(cue - 12, 2)
	var cue_trigger_offset := reader.file_offset(cue - 4, 2)
	var cue_value_offset := reader.file_offset(
		(((cue - 16) + 4) & ~3) + (reader.u16(cue - 16) & 255) * 4, 4
	)
	var fourth := dispatch + reader.u32(dispatch + 16)
	var interceptor_hull := reader.calls_between(third, fourth, "__ZN6Player15setMaxHitpointsEi")[0]
	var interceptor_objective := (
		reader.calls_between(third, fourth, "__ZN9ObjectiveC1EiiP5Level")[0]
	)
	var interceptor_route_offset := reader.file_offset(reader.literal(third, 3), 4)
	var interceptor_hull_offset := literal_file_offset(reader, interceptor_hull - 20)
	var interceptor_deadline_offset := literal_file_offset(reader, interceptor_objective + 14)
	var globals: int = reader.symbols["__ZN7GlobalsC2Ev"][0]
	var difficulty_offset := literal_file_offset(reader, globals + 64)
	var ranged_cue := (
		reader
		. calls_between(
			radio_switch + reader.u32(radio_switch + 12),
			radio_switch + reader.u32(radio_switch + 16),
			"__ZN12RadioMessageC1Eiiiii"
		)[0]
	)
	var ranged_count_offset := reader.file_offset(ranged_cue - 16, 2)
	var hull_association_offset := reader.file_offset(interceptor_hull - 26, 2)
	var fighter: int = reader.symbols["__ZN13PlayerFighterC2EibP6Playeriii"][0]
	var enemy_speed_offset := literal_file_offset(reader, fighter + 0x27a)
	var actor_initialize: int = reader.symbols["__ZN8KIPlayer10initializeEibP6Playeriiib"][0]
	var turn_offset := reader.file_offset(actor_initialize + 0x2de, 2)
	var enemy_assign: int = reader.symbols["__ZN5Level10assignGunsEv"][0]
	var enemy_guns := reader.calls_between(
		enemy_assign,
		reader.symbol_end(enemy_assign),
		"__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"
	)
	var enemy_gun := -1
	for call in enemy_guns:
		if reader.u16(call + 18) == 0x67c8:
			enemy_gun = call
	var enemy_reload_offset := reader.file_offset(enemy_gun - 38, 2)
	var enemy_bullet_offset := reader.file_offset(enemy_gun - 30, 2)
	var enemy_lifetime_offset := literal_file_offset(reader, enemy_gun - 2)
	var rank_offset := reader.file_offset(constructor + 16, 2)
	var finish: int = reader.symbols["__ZN5MGame11finishLevelEv"][0]
	var destination_call := (
		reader.calls_between(finish, reader.symbol_end(finish), "__ZN6Galaxy10getStationEiii")[0]
	)
	var quadrant_offset := reader.file_offset(destination_call - 6, 2)
	var fifth := dispatch + reader.u32(dispatch + 20)
	var escort_routes := reader.calls_between(fourth, fifth, "__ZN5RouteC1EPii")
	var escort_arrays := reader.calls_between(
		fourth, fifth, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E"
	)
	var escort_positions := reader.calls_between(
		fourth, fifth, "__ZN13PlayerFighter11setPositionEiii"
	)
	var escort_hulls := reader.calls_between(fourth, fifth, "__ZN6Player15setMaxHitpointsEi")
	var escort_route_offset := reader.file_offset(reader.literal(escort_routes[1] - 36, 1), 4)
	var escort_count_offset := reader.file_offset(escort_arrays[0] - 6, 2)
	var escort_position_offset := literal_file_offset(reader, escort_positions[0] - 30)
	var escort_hull_offset := literal_file_offset(reader, escort_hulls[0] - 14)
	var escort_speed_offset := literal_file_offset(reader, fighter + 0x27e)
	var escort_radio_calls := reader.calls_between(
		radio_switch + reader.u32(radio_switch + 16),
		radio_switch + reader.u32(radio_switch + 20),
		"__ZN12RadioMessageC1EiiP9Objective"
	)
	var escort_radio_offset := reader.file_offset(escort_radio_calls[0] - 12, 2)
	var escort_association_offset := reader.file_offset(escort_radio_calls[0] - 8, 2)
	var factory: int = reader.symbols["__ZN5Level10createShipEiiibP8Waypoint"][0]
	var factory_width_offset := reader.file_offset(factory + 0x7c, 2)
	var factory_rank_offset := reader.file_offset(factory + 0x1f4, 2)
	var friendly_gun := -1
	for call in enemy_guns:
		if reader.u16(call + 22) == 0x2080 and reader.u16(call + 26) == 0x5031:
			friendly_gun = call
	var friendly_base_offset := reader.file_offset(friendly_gun - 114, 2)
	var friendly_reload_offset := reader.file_offset(friendly_gun - 40, 2)
	var friendly_speed_offset := reader.file_offset(friendly_gun - 34, 2)
	var asteroid: int = reader.symbols["__ZN8AsteroidC2Ev"][0]
	var field: int = reader.symbols["__ZN13AsteroidFieldC2EiP8Waypoint"][0]
	var field_count_offset := reader.file_offset(field + 0x46, 2)
	var field_width_offset := literal_file_offset(reader, field + 0x44)
	var asteroid_hits_offset := reader.file_offset(asteroid + 0x16, 2)
	damaged = source.duplicate()
	damaged.encode_u16(field_count_offset, 0x211e)
	damaged.encode_u32(field_width_offset, 50000)
	damaged.encode_u16(asteroid_hits_offset, 0x2314)
	damaged.encode_u16(friendly_base_offset, 0x3007)
	damaged.encode_u16(friendly_reload_offset, 0x23c8)
	damaged.encode_u16(friendly_speed_offset, 0x2314)
	damaged.encode_u16(factory_width_offset, 0x22c8)
	damaged.encode_u16(factory_rank_offset, 0x00c0)
	damaged.encode_s32(escort_route_offset, 45678)
	damaged.encode_u16(escort_count_offset, 0x2006)
	damaged.encode_s32(escort_position_offset, -900)
	damaged.encode_float(escort_hull_offset, 60)
	damaged.encode_float(escort_speed_offset, 2.4)
	damaged.encode_u16(escort_radio_offset, 0x21fc)
	damaged.encode_s32(interceptor_route_offset, 67890)
	damaged.encode_float(enemy_speed_offset, 3.2)
	damaged.encode_u16(turn_offset, 0x2307)
	damaged.encode_u16(enemy_reload_offset, 0x23c8)
	damaged.encode_u16(enemy_bullet_offset, 0x2214)
	damaged.encode_u32(enemy_lifetime_offset, 3500)
	damaged.encode_u16(rank_offset, 0x2408)
	damaged.encode_u16(quadrant_offset, 0x2101)
	damaged.encode_float(interceptor_hull_offset, 43.0)
	damaged.encode_float(difficulty_offset, .75)
	damaged.encode_u32(interceptor_deadline_offset, 180000)
	damaged.encode_u16(ranged_count_offset, 0x2302)
	damaged.encode_s32(credits_offset, 12345)
	damaged.encode_s32(reward_offset, 777)
	damaged.encode_s32(collision_offset, 1234)
	damaged.encode_u16(targets_offset, 0x2007)
	damaged.encode_s32(route_offset, 4242)
	damaged.encode_u16(count_offset, 0x2102)
	damaged.encode_float(depreciation_offset, .25)
	damaged.encode_u16(clearance_count_offset, 0x200c)
	damaged.encode_u16(clearance_actor_offset, 0x2208)
	damaged.encode_s32(clearance_center_offset, 54321)
	damaged.encode_u32(deadline_offset, 90000)
	damaged.encode_u16(cue_text_offset, 0x21d5)
	damaged.encode_u16(cue_speaker_offset, 0x2201)
	damaged.encode_u32(cue_value_offset, 4500)
	var changed := reader.extract(damaged)
	check(not changed.is_empty(), "Read structurally compatible changed content: " + reader.error)
	if not changed.is_empty():
		check(changed.initial.credits == 12345, "Starting money is read, never hardcoded")
		check(changed.chapters[0].reward == 777, "Mission rewards are read, never hardcoded")
		check(
			changed.tables.actor_collision[0] == 1234,
			"Collision extents are recovered from source data"
		)
		check(changed.opening.target_count == 7, "Target count is read, never hardcoded")
		check(changed.opening.route[0][0] == 4242, "Mission coordinates are read, never hardcoded")
		check(changed.economy.equipment_max == 2, "Shop stock limits are imported")
		check(changed.economy.equipment_resale_factor == .25, "Depreciation is imported")
		check(
			changed.missions[1].groups[0].count == 12 and changed.missions[1].groups[0].actor == 8,
			"Clearance counts and actor types are imported"
		)
		check(
			(
				changed.missions[1].groups[0].center[0] == 54321
				and changed.missions[1].deadline_ms == 90000
			),
			"Clearance coordinates and deadline are imported"
		)
		check(
			(
				changed.missions[1].radio[0].text == 213
				and changed.missions[1].radio[0].speaker == 1
				and changed.missions[1].radio[0].value == 4500
			),
			"Radio text, speaker and trigger parameters come from the supplied game"
		)
		check(changed.missions[2].route[0][0] == 67890, "Interceptor route is imported")
		check(
			changed.missions[2].groups[0].hull == 53,
			"Mission hull derives from imported base and default difficulty"
		)
		check(changed.missions[2].deadline_ms == 180000, "Escape deadline is imported")
		check(changed.missions[2].radio[1].count == 2, "Radio actor range is imported")
		check(
			(
				is_equal_approx(float(changed.missions[2].groups[0].motion.speed), 64)
				and changed.missions[2].groups[0].motion.turn_response == 7
			),
			"Enemy motion follows changed source parameters"
		)
		check(
			(
				changed.missions[2].groups[0].weapon.damage == 5
				and changed.missions[2].groups[0].weapon.interval == .4
				and changed.missions[2].groups[0].weapon.lifetime == 3.5
				and changed.missions[2].groups[0].weapon.speed == 400
			),
			"Enemy firing parameters and initial rank scaling are imported"
		)
		check(
			(
				changed.missions[3].groups[1].route[0][0] == 45678
				and changed.missions[3].groups[0].count == 6
			),
			"Escort route and attacker count respond to source changes"
		)
		check(
			(
				changed.missions[3].groups[1].center[0] == -900
				and changed.missions[3].groups[1].hull == 45
			),
			"Escort offset and difficulty-scaled hull respond to source changes"
		)
		check(
			(
				is_equal_approx(float(changed.missions[3].groups[1].motion.speed), 48)
				and changed.missions[3].radio[5].text == 252
			),
			"Friendly speed and objective-bound dialogue come from source"
		)
		check(
			changed.missions[3].groups[0].hull_rule.factor == 1.25,
			"Fighter hull imports the difficulty adjustment"
		)
		check(
			(
				changed.missions[3].groups[0].hull_rule.rank_scale == 36
				and changed.missions[2].groups[0].scatter[0][1] == 19199
			),
			"Factory rank multiplier and spawn width follow changed source constants"
		)
		check(
			(
				changed.missions[3].groups[1].weapon.damage == 6
				and changed.missions[3].groups[1].weapon.interval == .4
				and changed.missions[3].groups[1].weapon.speed == 400
			),
			"Friendly gun damage/rank/difficulty, reload and speed follow source changes"
		)
		check(
			(
				changed.missions[3].scenery[0].count == 30
				and changed.missions[3].scenery[0].width == 50000
				and changed.missions[3].scenery[0].hits == 21
			),
			"Field density, extent and asteroid durability respond to supplied data changes"
		)
		check(changed.campaign_quadrant == 1, "Campaign destination quadrant is imported")
		check(reader.bytes.is_empty(), "Executable bytes are discarded after import")

	var wrong_objective := damaged.duplicate()
	wrong_objective.encode_u16(escort_association_offset, 0x6993)
	check(
		reader.extract(wrong_objective).is_empty(),
		"Reject radio bound to a different objective field"
	)
	var wrong_association := damaged.duplicate()
	wrong_association.encode_u16(hull_association_offset, 0x6998)
	check(
		reader.extract(wrong_association).is_empty(),
		"Reject changed hull field association instead of guessing"
	)

	damaged.encode_u16(cue_trigger_offset, 0x230f)
	check(
		reader.extract(damaged).is_empty(),
		"Unsupported radio triggers are reported instead of invented"
	)


func literal_file_offset(reader, address: int) -> int:
	return reader.file_offset(((address + 4) & ~3) + (reader.u16(address) & 255) * 4, 4)


func check_escort(lib) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	check(
		definition.route.size() == 4 and definition.groups.size() == 2,
		"Escort declaration has separate combat and friendly groups"
	)
	var enemies: Dictionary = definition.groups[0]
	var ally: Dictionary = definition.groups[1]
	check(
		(
			enemies.count == 4
			and enemies.positions[0] == definition.route[0]
			and enemies.positions[1] == definition.route[0]
			and enemies.positions[2] == definition.route[2]
			and enemies.positions[3] == definition.route[2]
		),
		"Enemy spawn ranges use the imported waypoint selection"
	)
	check(
		enemies.scatter.all(func(axis): return axis[0] == -32000 and axis[1] == 31999),
		"Campaign fighter spawn cube comes from factory data"
	)
	check(
		(
			ally.actor == 16
			and ally.center[0] == -700
			and ally.center[1] == -700
			and ally.center[2] == 2000
			and ally.hull == 40
			and ally.route.size() == 8
		),
		"Escort model, offset, hull and independent route are imported"
	)
	check(is_equal_approx(float(ally.motion.speed), 37.8), "Escort uses imported friendly speed")
	check(
		lib.group_hull(enemies) == 95 and lib.campaign_level(3) == 2,
		"Ordinary fighter hull includes the imported rank multiplier"
	)
	check(
		(
			definition.success.kind == "all"
			and definition.failure.kind == "ally_destroyed"
			and definition.failure.index == 0
		),
		"Both success predicates and selected-escort failure are recovered"
	)
	check(
		(
			definition.failure_text == 401
			and definition.failure_prefix == "Doc "
			and definition.scenery[0].waypoint == 1
		),
		"Escort failure localization and asteroid-field placement are recovered"
	)
	check(
		(
			definition.radio.size() == 7
			and definition.radio[5].condition == "mission_won"
			and definition.radio[6].value == 5
		),
		"Objective-bound radio resolves the compound success declaration"
	)
	check(
		lib.mission_playable(3),
		"Native allied encounters and field geometry enable the fourth mission"
	)
	var state := Session.Mission.create(definition, 3, 1, lib, 123)
	check(
		state.actors.size() == 5 and state.target == 4 and state.kills == 0,
		"Allies are not counted among hostile objectives"
	)
	var ally_position := Session.Mission.SPAWN_POSITION + Session.Mission.point(ally.center)
	check(
		Combat.vector(state.actors[4].position).is_equal_approx(ally_position),
		"Escort begins at imported offset from native player spawn"
	)
	var bounds_ok := true
	for index in 4:
		var delta := (
			Combat.vector(state.actors[index].position)
			- Session.Mission.point(enemies.positions[index])
		)
		bounds_ok = (
			bounds_ok and absf(delta.x) <= 640 and absf(delta.y) <= 640 and absf(delta.z) <= 640
		)
	check(bounds_ok, "Deterministic escort attackers stay within imported spawn bounds")
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 3, 1, lib),
		"Escort data and state survive JSON normalization"
	)
	var active_cue := {"condition": "enemies_active", "value": 0}
	check(
		not Session.Mission.Radio.triggered(active_cue, definition, state),
		"A live escort does not trigger enemy-active radio"
	)
	for index in definition.route.size():
		Session.Mission.reach_waypoint(definition, state)
	check(not state.ready, "Reaching the route end alone cannot win the escort mission")
	var battle := Session.Mission.create(definition, 3, 1, lib, 123)
	for index in 4:
		battle.actors[index].awake = true
		Session.Mission.damage(definition, battle, index, 10000)
	check(
		not battle.ready and battle.kills == 4,
		"Destroying attackers alone cannot win before reaching destination"
	)
	for index in definition.route.size():
		Session.Mission.reach_waypoint(definition, battle)
	check(battle.ready and not battle.failed, "Compound success requires both route and combat")
	check(
		Session.Mission.Radio.triggered(definition.radio[5], definition, battle),
		"Compound victory enables its original closing radio"
	)
	check(Session.Mission.valid(definition, battle, 3, 1, lib), "Completed escort state validates")
	var lost := Session.Mission.create(definition, 3, 1, lib, 123)
	Session.Mission.damage(definition, lost, 4, ally.hull)
	check(not lost.failed, "Escort failure waits for the source destruction boundary")
	finish_wrecks_fixture(definition,lost,lib)
	check(
		lost.failed and not lost.ready and lost.kills == 0,
		"Losing the escort fails without awarding a hostile kill"
	)
	Session.Mission.reach_waypoint(definition, lost)
	check(
		lost.stage == 0 and Session.Mission.valid(definition, lost, 3, 1, lib),
		"Escort failure remains terminal across reload"
	)
	var invalid := lost.duplicate(true)
	invalid.actors[4].route_stage = 999
	check(
		not Session.Mission.valid(definition, invalid, 3, 1, lib),
		"Reject invalid escort route progress"
	)
	var original_index: int = definition.failure.index
	definition.failure.index = 1
	check(not lib.valid_missions(), "Reject failure references beyond friendly actor count")
	definition.failure.index = original_index
	var original_conditions: Array = definition.success.conditions
	definition.success.conditions = []
	check(
		not lib.valid_missions(),
		"Reject empty compound objectives rather than granting free completion"
	)
	definition.success.conditions = original_conditions


func check_player_body_contact(source: PackedByteArray, lib) -> void:
	var Body = Session.BodyContact
	var rules: Dictionary = lib.content.player_motion.contact
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	check(same_saved_value(reader.player_body_contact(), rules), "Body contact declarations match supplied executable data")
	check(rules.damage == 5 and rules.interval == .5 and rules.forward_keep == .5, "Original body contact damage, clock and reflected response are recovered")
	reader.bytes.encode_u16(reader.file_offset(0x54cb4, 2), 0x2107)
	check(reader.player_body_contact().damage == 7, "Changed supplied contact damage propagates")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x5515c, 2), 0x2001)
	check(reader.player_body_contact().is_empty(), "Unsupported solid fighter behavior is rejected")
	var invalid := rules.duplicate(true)
	invalid.interval = -1
	check(not Body.valid_parameters(invalid), "Invalid cached contact timing is rejected")
	var boxes := [{"actor": 0, "center": Vector3.ZERO, "previous": Vector3.ZERO, "extent": Vector3.ONE}]
	var motion := Session.Motion.create()
	var start := Vector3(0, 0, 3)
	var finish := Vector3(0, 0, -3)
	var response: Dictionary = Body.advance(motion, rules, .6, start, finish, boxes)
	check(response.actor == 0 and response.position.z > 1 and response.normal == Vector3.BACK, "Swept body response prevents fast player tunnelling and reflects remaining motion")
	check(response.damage == rules.damage, "First eligible body contact applies imported damage")
	response = Body.advance(motion, rules, .1, start, finish, boxes)
	check(response.damage == 0, "Body contact damage is throttled across consecutive steps")
	response = Body.advance(motion, rules, .4, start, finish, boxes)
	check(response.damage == rules.damage, "Body contact damage returns after imported interval")
	response = Body.advance(motion, rules, .1, Vector3(3, 0, 3), Vector3(3, 0, -3), boxes)
	check(response.actor == -1 and response.position == Vector3(3, 0, -3), "Passing outside a body does not deflect the player")
	response = Body.advance(motion, rules, .1, Vector3(0, 0, 1), Vector3(0, 0, 3), boxes)
	check(response.actor == -1 and response.position.z == 3, "Leaving a body face does not cause a sticky collision")
	response = Body.advance(motion, rules, .1, Vector3.ZERO, Vector3.ZERO, boxes)
	check(response.actor == 0 and response.position.x > 1, "Player restored inside a hull is separated safely")
	var moving := [{"actor": 1, "center": Vector3(3, 0, 0), "previous": Vector3(-3, 0, 0), "extent": Vector3.ONE}]
	response = Body.advance(motion, rules, .6, Vector3.ZERO, Vector3.ZERO, moving)
	check(response.actor == 1 and response.position.x > 4, "Moving body sweeps and pushes a stationary player clear")
	var retained := motion.duplicate(true)
	Body.advance(motion, rules, 0, start, finish, boxes)
	check(motion == retained, "Zero-time contact leaves the saved clock unchanged")

	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 7
	check(pilot.begin_mission(), "Create original cruiser-attack bodies")
	var definition: Dictionary = pilot.mission_definition()
	var actual: Array = Body.bodies(definition, pilot.active_job)
	var fixed_actor := -1
	for collider in actual:
		if not definition.groups[int(pilot.active_job.actors[collider.actor].group)].get("combat_active", true):
			fixed_actor = collider.actor
	check(fixed_actor >= 0, "Disabled cruiser retains physical collision independently of combat participation")
	if fixed_actor >= 0:
		var count := actual.filter(func(box): return box.actor == fixed_actor).size()
		pilot.active_job.actors[fixed_actor].awake = false
		check(Body.bodies(definition, pilot.active_job).filter(func(box): return box.actor == fixed_actor).size() == count, "Sleeping fixed hull retains every compound collision box")
		pilot.active_job.actors[fixed_actor].destruction.phase = "dying"
		check(Body.bodies(definition, pilot.active_job).filter(func(box): return box.actor == fixed_actor).size() == count, "Unfinished fixed wreck remains solid")
		pilot.active_job.actors[fixed_actor].destruction.phase = "dead"
		check(Body.bodies(definition, pilot.active_job).all(func(box): return box.actor != fixed_actor), "Finished fixed wreck releases its body colliders")
	check(Body.bodies(lib.mission_definition(0), Session.Mission.create(lib.mission_definition(0), 0, 0, lib, 1)).is_empty(), "Opening fighters and mines do not gain physical hull collisions")

	var free := Session.new()
	free.configure(lib, true)
	check(free.depart(), "Start free pilot for contact-state persistence")
	free.motion.contact_elapsed = .27
	var saved: Dictionary = JSON.parse_string(JSON.stringify(free.capture()))
	var copy := Session.new()
	copy.configure(lib)
	check(copy.restore(saved) and is_equal_approx(copy.motion.contact_elapsed, .27), "Pilot save retains partial contact clock")
	var legacy := saved.duplicate(true)
	legacy.schema = 27
	legacy.motion.erase("contact_elapsed")
	check(copy.restore(legacy) and copy.motion.contact_elapsed == 0 and copy.credits == free.credits and copy.flight_position == free.flight_position, "Legacy pilot gains a fresh contact clock without changing progress or placement")
	var broken := saved.duplicate(true)
	broken.motion.erase("contact_elapsed")
	check(not copy.restore(broken), "Current pilot requires body contact state")
	broken = saved.duplicate(true)
	broken.motion.contact_elapsed = rules.interval + 1
	check(not copy.restore(broken), "Current pilot rejects an out-of-range contact clock")

	# Actual flight path: place a transient pilot just outside a supplied cruiser
	# box, crossing its face on the next manual step. No campaign saves are written.
	pilot = Session.new()
	pilot.configure(lib)
	pilot.chapter = 7
	pilot.begin_mission()
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {"aim_assist": false})
	flight.set_physics_process(false)
	actual = Body.bodies(pilot.mission_definition(), pilot.active_job)
	var body: Dictionary = actual[0]
	flight.ship.position = body.center + Vector3(0, 0, body.extent.z + .5)
	flight.ship.rotation = Vector3.ZERO
	flight.throttle = 1
	pilot.motion.contact_elapsed = rules.interval
	var hull := pilot.hull
	flight.step(.05)
	check(flight.ship.position.z > body.center.z + body.extent.z and pilot.hull == hull - rules.damage, "Actual flight deflects off a source cruiser and applies contact damage")
	var clock: float = pilot.motion.contact_elapsed
	flight.pause(true)
	flight.step(.2)
	check(pilot.motion.contact_elapsed == clock, "Paused flight preserves body contact clock")
	flight.queue_free()
	await process_frame
	await create_timer(.2).timeout


func check_body_contact_edges(lib) -> void:
	var Body = Session.BodyContact
	var rules: Dictionary = lib.content.player_motion.contact
	var motion := Session.Motion.create()
	var boxes := [
		{"actor": 0, "center": Vector3(-3, 0, 0), "previous": Vector3(-3, 0, 0), "extent": Vector3.ONE},
		{"actor": 0, "center": Vector3(3, 0, 0), "previous": Vector3(3, 0, 0), "extent": Vector3.ONE}
	]
	var response: Dictionary = Body.advance(motion, rules, .6, Vector3(0, 0, 3), Vector3(0, 0, -3), boxes)
	check(response.actor == -1, "Compound hull gaps remain open rather than using a combined bounding box")
	var delta := Vector3(1000, -500, 750)
	for body in boxes:
		body.center += delta
		body.previous += delta
	response = Body.advance(motion, rules, .6, delta + Vector3(3, 0, 3), delta + Vector3(3, 0, -3), boxes)
	check(response.actor == 0 and response.position.z > delta.z + 1, "Collision geometry follows translated world positions")
	var Arcade = preload("res://src/simulation/survival_session.gd")
	var arcade := Arcade.new()
	check(arcade.configure_survival(lib, lib.content.survival, 0, 0, 47), "Configure source survival for shared player contact state")
	arcade.motion.contact_elapsed = .23
	var saved: Dictionary = JSON.parse_string(JSON.stringify(arcade.capture()))
	var copy := Arcade.new()
	copy.configure_survival(lib, lib.content.survival, 0, 0, 47)
	check(copy.restore(saved) and is_equal_approx(copy.motion.contact_elapsed, .23), "Survival preserves shared contact clock in its own snapshot")
	var legacy := saved.duplicate(true)
	legacy.schema = 9
	legacy.motion.erase("contact_elapsed")
	check(copy.restore(legacy) and copy.motion.contact_elapsed == 0 and copy.hull == arcade.hull and copy.active_job.kills == arcade.active_job.kills, "Legacy survival snapshot initializes contact state without changing score or health")
	var broken := saved.duplicate(true)
	broken.motion.contact_elapsed = NAN
	check(not copy.restore(broken), "Survival rejects nonfinite contact state")
	check(Body.bodies(arcade.mission_definition(), arcade.active_job).is_empty(), "Survival fighter pool does not become solid from projectile bounds")


func check_directed_scenery_collision(lib) -> void:
	var profiles: Dictionary = lib.actor_weapons(5).duplicate(true)
	profiles[-2].target_ids = [0]
	var gun: Dictionary = profiles[-2]
	var travel := float(gun.speed) * minf(.5, float(gun.lifetime) * .5)
	var target := {"id": 0, "team": gun.team, "position": [0, 0, -travel * .8], "radius": travel * .02}
	var rock := {"id": 2, "team": "neutral", "position": [0, 0, -travel * .4], "radius": travel * .02}
	var unrelated := {"id": 1, "team": "ally", "position": [0, 0, -travel * .2], "radius": travel * .02}
	for obstruction_first in [false, true]:
		var state := Combat.create()
		check(Combat.fire(state, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles), "Source commander gun launches directed projectile")
		var targets := [rock, target, unrelated] if obstruction_first else [unrelated, target, rock]
		var hits := Combat.advance(state, travel / gun.speed, targets, lib, profiles)
		check(hits.size() == 1 and hits[0].target == 2 and state.projectiles.is_empty(), "Nearest neutral obstruction stops directed fire regardless of target order")
	var behind := rock.duplicate(true)
	behind.position[2] = -travel * .95
	var clear := Combat.create()
	Combat.fire(clear, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles)
	var hits := Combat.advance(clear, travel / gun.speed, [behind, unrelated, target], lib, profiles)
	check(hits.size() == 1 and hits[0].target == 0, "Assigned same-team actor can be hit while unrelated characters and farther scenery cannot intercept")
	var crossing := rock.duplicate(true)
	crossing.previous = [-travel, 0, -travel * .5]
	crossing.position = [travel, 0, -travel * .5]
	var moving := Combat.create()
	Combat.fire(moving, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles)
	hits = Combat.advance(moving, travel / gun.speed, [target, crossing], lib, profiles)
	check(hits.size() == 1 and hits[0].target == 2, "Directed shots sweep moving neutral geometry in relative coordinates")
	var saved := Combat.create()
	Combat.fire(saved, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles)
	Combat.advance(saved, travel / gun.speed * .1, [], lib, profiles)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(saved))
	check(Combat.valid(restored, lib, profiles), "Directed projectile before obstruction survives JSON validation")
	hits = Combat.advance(restored, travel / gun.speed * .9, [target, rock], lib, profiles)
	check(hits.size() == 1 and hits[0].target == 2 and is_equal_approx(hits[0].damage, gun.damage), "Reloaded directed projectile hits scenery with its imported damage")
	var ordinary := profiles.duplicate(true)
	ordinary[-2].erase("target_ids")
	var normal := Combat.create()
	Combat.fire(normal, -2, Vector3.ZERO, Vector3.FORWARD, lib, ordinary)
	hits = Combat.advance(normal, travel / gun.speed, [rock, target], lib, ordinary)
	check(hits.size() == 1 and hits[0].target == 2, "Ordinary gun still filters same-team actors and strikes neutral scenery")


func check_allied_combat(lib) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	var group: Dictionary = definition.groups[1]
	var weapons: Dictionary = lib.actor_weapons(3)
	check(
		weapons[-5].team == "ally" and weapons[-1].team == "enemy",
		"NPC weapon ownership derives from imported actor teams"
	)
	check(
		(
			weapons[-5].damage == 4
			and weapons[-5].interval == .5
			and weapons[-5].lifetime == 3
			and weapons[-5].speed == 320
		),
		"Friendly gun values use the source initializer"
	)
	var state := Session.Mission.create(definition, 3, 1, lib, 471)
	var combat := Combat.create()
	var ally_position := Combat.vector(state.actors[4].position)
	var previous := Session.Encounters.advance(
		definition, state, 1, Vector3(1e6, 0, 0), Vector3.ZERO, combat, lib, weapons
	)
	check(
		(
			Combat.vector(state.actors[4].position).distance_to(ally_position) > 30
			and state.actors[4].route_stage == 0
		),
		"Native escort advances along its own route without hostile contact"
	)
	check(
		Combat.vector(previous[4]).is_equal_approx(ally_position),
		"Encounter snapshots preserve previous allied positions for swept collision"
	)
	state.actors[4].position = Combat.packed(Session.Mission.point(group.route[0]))
	Session.Encounters.advance(
		definition, state, .01, Vector3(1e6, 0, 0), Vector3.ZERO, combat, lib, weapons
	)
	check(state.actors[4].route_stage == 1, "Escort captures a reached imported waypoint")
	state.actors[4].route_stage = group.route.size() - 1
	state.actors[4].position = Combat.packed(Session.Mission.point(group.route.back()))
	Session.Encounters.advance(
		definition, state, .01, Vector3(1e6, 0, 0), Vector3.ZERO, combat, lib, weapons
	)
	check(
		state.actors[4].route_stage == group.route.size() and not state.ready,
		"Escort route completion alone cannot complete the player mission"
	)
	state = Session.Mission.create(definition, 3, 1, lib, 471)
	state.actors[4].position = [0.0, 0.0, 0.0]
	state.actors[0].position = [0.0, 0.0, -300.0]
	state.actors[0].heading = [0.0, 0.0, 1.0]
	state.actors[0].awake = true
	combat = Combat.create()
	for tick in 120:
		previous = Session.Encounters.advance(
			definition, state, 1.0 / 60, Vector3(1e6, 0, 0), Vector3.ZERO, combat, lib, weapons
		)
		var targets: Array = []
		for index in state.actors.size():
			var actor: Dictionary = state.actors[index]
			if Session.Mission.actor_active(definition, state, actor):
				targets.append(
					{
						"id": index,
						"team": "enemy" if Session.Mission.enemy(definition, actor) else "ally",
						"position": actor.position,
						"previous": previous[index],
						"radius": lib.actor_radius(int(definition.groups[int(actor.group)].actor))
					}
				)
		for impact in Combat.advance(combat, 1.0 / 60, targets, lib, weapons):
			Session.Mission.damage(definition, state, int(impact.target), float(impact.damage))
	check(
		state.actors[4].shots > 0 and state.actors[0].shots > 0,
		"Both escort and interceptor can acquire and shoot the opposing ship"
	)
	check(
		(
			state.actors[4].hp < lib.group_hull(group)
			and state.actors[0].hp < lib.group_hull(definition.groups[0])
		),
		"Opposing NPC ballistic shots damage both sides"
	)
	check(
		(
			Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 3, 1, lib)
			and Combat.valid(JSON.parse_string(JSON.stringify(combat)), lib, weapons)
		),
		"Allied steering, shots and cooldowns validate across JSON save/reload"
	)
	var malformed := state.duplicate(true)
	malformed.actors[4].shots = -1
	check(
		not Session.Mission.valid(definition, malformed, 3, 1, lib),
		"Invalid allied attack counters are rejected"
	)
	combat = Combat.create()
	Combat.fire(combat, -5, Vector3.ZERO, Vector3.FORWARD, lib, weapons)
	var hits := Combat.advance(
		combat,
		1,
		[
			{"id": -1, "position": [0, 0, -40], "radius": 10},
			{"id": 4, "team": "ally", "position": [0, 0, -60], "radius": 10},
			{"id": 0, "team": "enemy", "position": [0, 0, -100], "radius": 10}
		],
		lib,
		weapons
	)
	check(
		hits.size() == 1 and hits[0].target == 0,
		"Friendly fire passes the pilot and escort, then hits the hostile"
	)
	combat = Combat.create()
	Combat.fire(combat, -1, Vector3.ZERO, Vector3.FORWARD, lib, weapons)
	hits = Combat.advance(
		combat,
		1,
		[
			{"id": 1, "team": "enemy", "position": [0, 0, -40], "radius": 10},
			{"id": 4, "team": "ally", "position": [0, 0, -60], "radius": 10},
			{"id": -1, "position": [0, 0, -100], "radius": 10}
		],
		lib,
		weapons
	)
	check(
		hits.size() == 1 and hits[0].target == 4,
		"Hostile shot hits the nearer escort instead of passing through to the pilot"
	)
	var snapshot := state.duplicate(true)
	Session.Encounters.advance(
		definition, state, 0, Vector3.ZERO, Vector3.ZERO, combat, lib, weapons
	)
	check(state == snapshot, "Paused simulation preserves allied movement and attack state")


func check_campaign_scene_geometry(lib) -> void:
	for chapter in lib.content.chapters.size():
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.chapter = chapter
		check(pilot.begin_mission(), "Create campaign scene fixture %d" % chapter)
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, pilot, {"aim_assist": false})
		flight.set_physics_process(false)
		check(
			flight.station == null and flight.ambience.get_child_count() == 0,
			"Campaign %d does not inherit the unrelated sector preview" % chapter
		)
		var expected: Array = pilot.active_job.scenery.rocks
		check(
			flight.field_rocks.size() == expected.size(),
			"Campaign %d keeps every imported field object" % chapter
		)
		var positioned := true
		for index in expected.size():
			positioned = (
				positioned
				and flight.field_rocks[index].node.position.is_equal_approx(
					Combat.vector(expected[index].position)
				)
			)
		check(positioned, "Campaign %d keeps imported field positions" % chapter)
		if chapter == 1:
			# This debris mission has no asteroid field near the origin. The old
			# unconditional preview boundary pushed the pilot out and dealt 3 HP.
			flight.ship.position = Vector3(0, 0, 111)
			flight.ship.rotation = Vector3.ZERO
			flight.throttle = 1
			var hull: float = pilot.hull
			flight.step(.05)
			check(
				is_equal_approx(flight.ship.position.z, 109) and pilot.hull == hull,
				"Crossing the campaign origin has no phantom station collision or damage"
			)
		flight.queue_free()
		await process_frame


func check_scenery(lib) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	var field: Dictionary = definition.scenery[0]
	check(
		field.count == 40 and field.width == 40000 and field.model == 10022,
		"Source field count, bounds and mesh resource are imported"
	)
	check(
		(
			field.hits == 11
			and is_equal_approx(float(field.radius), 33.98)
			and field.contact_damage == 50
			and field.contact_interval == 1
		),
		"Original asteroid shot count, collision extent and contact damage are recovered"
	)
	var scenery := Session.Mission.Scenery.create(definition, 901)
	check(
		(
			scenery.rocks.size() == 40
			and Session.Mission.Scenery.valid(
				definition, JSON.parse_string(JSON.stringify(scenery))
			)
		),
		"Field positions, scale, rotation and damage survive JSON normalization"
	)
	var center := Session.Mission.point(definition.route[int(field.waypoint)])
	var inside := true
	for rock in scenery.rocks:
		var offset := (Combat.vector(rock.position) - center).abs()
		inside = inside and offset.x <= 400 and offset.y <= 400 and offset.z <= 400
	check(inside, "All field rocks spawn inside original cube around the declared waypoint")
	for index in 10:
		Session.Mission.Scenery.hit(scenery, 0)
	check(scenery.rocks[0].hits == 1, "Ten normal shots leave the asteroid intact as in the source")
	Session.Mission.Scenery.hit(scenery, 0)
	check(
		(
			scenery.rocks[0].hits == 0
			and Session.Mission.Scenery.targets(definition, scenery, 5).size() == 39
		),
		"The next hit destroys the asteroid and removes its collider"
	)
	Session.Mission.Scenery.hit(scenery, 1, true)
	check(
		scenery.rocks[1].hits == 0,
		"A destructive contact or missile removes an asteroid immediately"
	)
	for rock in scenery.rocks:
		rock.hits = 0
	scenery.rocks[2].hits = field.hits
	scenery.rocks[2].position = [0, 0, -100]
	scenery.rocks[3].hits = field.hits
	scenery.rocks[3].position = [0, 0, -200]
	check(
		(
			(
				Session.Mission.Scenery.contact(
					definition, scenery, Vector3.ZERO, Vector3(0, 0, -150), .1
				)
				== 50
			)
			and scenery.rocks[2].hits == 0
		),
		"Swept player contact catches a field rock between frames"
	)
	check(
		(
			(
				Session.Mission.Scenery.contact(
					definition, scenery, Vector3(0, 0, -150), Vector3(0, 0, -250), .1
				)
				== 0
			)
			and scenery.rocks[3].hits == field.hits
		),
		"Imported contact interval prevents immediate repeated impact damage"
	)
	check(
		(
			Session.Mission.Scenery.contact(
				definition, scenery, Vector3(0, 0, -150), Vector3(0, 0, -250), 1
			)
			== 50
		),
		"Contact damage resumes after the imported interval"
	)
	var invalid := scenery.duplicate(true)
	invalid.rocks[0].scale = -1
	check(
		not Session.Mission.Scenery.valid(definition, invalid),
		"Invalid saved field geometry is rejected"
	)
	var combat := Combat.create()
	Combat.fire(combat, int(lib.content.initial.weapon_index), Vector3.ZERO, Vector3.FORWARD, lib)
	var hits := Combat.advance(
		combat,
		1,
		[
			{"id": 5, "team": "neutral", "position": [0, 0, -100], "radius": field.radius},
			{"id": 0, "team": "enemy", "position": [0, 0, -150], "radius": 10}
		],
		lib
	)
	check(
		hits.size() == 1 and hits[0].target == 5,
		"An asteroid intercepts a shot before it reaches a ship"
	)


func check_interception(lib) -> void:
	var definition: Dictionary = lib.mission_definition(2)
	check(
		definition.route.size() == 3 and definition.groups[0].count == 3,
		"Source interceptor declaration has one enemy per waypoint"
	)
	check(
		definition.groups[0].hull == 27 and definition.deadline_ms == 240000,
		"Mission hull override and escape deadline recovered from source defaults"
	)
	check(
		definition.radio.size() == 9 and definition.radio[1].condition == "enemy_range_active",
		"Third chapter radio includes its ranged enemy condition"
	)
	check(
		lib.mission_playable(2) and lib.playable_chapter_count() == 13,
		"Native interceptor behavior enables the third imported mission"
	)
	var state := Session.Mission.create(definition, 2, 0, lib, 123)
	var correct_positions := true
	for index in state.actors.size():
		var center := Session.Mission.point(definition.route[index])
		var delta := Combat.vector(state.actors[index].position) - center
		correct_positions = (
			correct_positions
			and absf(delta.x) <= 640
			and absf(delta.y) <= 640
			and absf(delta.z) <= 640
		)
	check(correct_positions, "Each interceptor starts within its source waypoint spawn cube")
	check(
		Session.Mission.valid(definition, state, 2, 0, lib), "Dormant interceptor state validates"
	)
	check(
		not Session.Mission.damage(definition, state, 0, 1),
		"Dormant actors cannot take combat damage"
	)
	var cue: Dictionary = definition.radio[1]
	check(
		not Session.Mission.Radio.triggered(cue, definition, state),
		"Sleeping enemies do not trigger interception radio"
	)
	state.actors[1].awake = true
	check(
		Session.Mission.Radio.triggered(cue, definition, state),
		"An active enemy in the imported range triggers radio"
	)
	var narrow := cue.duplicate()
	narrow.value = 2
	narrow.count = 1
	check(
		not Session.Mission.Radio.triggered(narrow, definition, state),
		"Radio excludes active enemies outside its range"
	)
	check(Session.Mission.damage(definition, state, 1, 4), "Awake interceptor accepts damage")
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 2, 0, lib),
		"Mission-specific hull, positions and activation survive JSON round trip"
	)
	var invalid := state.duplicate(true)
	invalid.actors[1].hp = 28
	check(
		not Session.Mission.valid(definition, invalid, 2, 0, lib),
		"Validate against mission hull override, not catalogue hull"
	)
	invalid = state.duplicate(true)
	invalid.actors[0].erase("awake")
	check(
		not Session.Mission.valid(definition, invalid, 2, 0, lib),
		"Reject missing interceptor activation state"
	)
	for index in definition.route.size():
		Session.Mission.reach_waypoint(definition, state)
	check(state.ready and state.kills == 0, "Escape objective allows surviving enemies")
	var timed := Session.Mission.create(definition, 2, 0, lib, 123)
	Session.Mission.advance(definition, timed, float(definition.deadline_ms) / 1000 + .001, lib)
	Session.Mission.reach_waypoint(definition, timed)
	check(
		timed.failed and not timed.ready and timed.stage == 0,
		"Expired escape cannot advance or succeed"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 13
	pilot.progression = Session.Progression.create(13)
	check(
		not pilot.begin_mission() and pilot.docked,
		"Campaign cannot launch a nonexistent chapter after the finale"
	)
	var forged := pilot.capture()
	forged.docked = false
	forged.active_job = state
	check(not pilot.restore(forged), "Save reload cannot bypass the remaining campaign boundary")
	var original_count: int = cue.count
	cue.count = 999
	check(not lib.valid_missions(), "Reject radio ranges beyond imported actors")
	cue.count = original_count


func check_enemy_flight(lib, campaign) -> void:
	var definition: Dictionary = lib.mission_definition(2)
	var group: Dictionary = definition.groups[0]
	check(
		is_equal_approx(float(group.motion.speed), 42) and group.weapon.damage == 2,
		"Interceptor speed and starting campaign damage follow source declarations"
	)
	var original_level := int(lib.content.initial.level)
	var original_reward := int(lib.content.chapters[0].reward)
	lib.content.initial.level = 3
	lib.content.chapters[0].reward = 10000
	check(
		lib.campaign_level(2) == 4 and lib.actor_weapons(2)[-1].damage == 3,
		"Completed source rewards and imported rank rules scale enemy damage"
	)
	lib.content.initial.level = original_level
	lib.content.chapters[0].reward = original_reward
	var state := Session.Mission.create(definition, 2, 0, lib, 456)
	var combat := Combat.create()
	var weapons: Dictionary = lib.actor_weapons(2)
	var position := Combat.vector(state.actors[0].position)
	var width := float(group.motion.wake_half_width)
	Session.Encounters.advance(
		definition,
		state,
		.01,
		position + Vector3(width + 1, 0, 0),
		Vector3.ZERO,
		combat,
		lib,
		weapons
	)
	check(not state.actors[0].awake, "Enemy stays asleep outside the imported activation box")
	Session.Encounters.advance(
		definition,
		state,
		.01,
		position + Vector3(width - 1, width - 1, 0),
		Vector3.ZERO,
		combat,
		lib,
		weapons
	)
	check(
		state.actors[0].awake,
		"Activation uses a box, including corners outside a same-radius sphere"
	)
	var shooter := Session.new()
	shooter.configure(lib)
	shooter.chapter = 2
	shooter.progression = Session.Progression.create(2)
	check(
		shooter.depart() and not shooter.arrive(shooter.station_id),
		"An unfinished campaign cannot dock and leave an invalid active save"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, shooter, {})
	flight.set_physics_process(false)
	check(flight.actors.is_empty(), "Dormant interceptors are not shown as active threats")
	flight.ship.position = Combat.vector(shooter.active_job.actors[0].position) + Vector3(0, 0, 300)
	flight.throttle = 0
	var starting_hull: float = shooter.hull
	for tick in 120:
		flight.step(1.0 / 60)
	check(
		shooter.hull < starting_hull and not flight.paused,
		"Native enemy acquisition, pursuit and ballistic fire damage the player"
	)
	check(
		shooter.active_job.actors[0].shots > 0 and flight.actors.size() > 0,
		"Active interceptor renders and records its attacks"
	)
	shooter.flight_position = flight.ship.position
	shooter.flight_rotation = flight.ship.rotation
	var saved := shooter.capture()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(saved))),
		"Enemy steering, firing counters and projectiles survive an in-flight save"
	)
	check(
		(
			copy.active_job.actors[0].shots == shooter.active_job.actors[0].shots
			and copy.combat.projectiles.size() == shooter.combat.projectiles.size()
		),
		"Enemy reload preserves active encounter progress"
	)
	var defeat_events: Array = []
	var dead_flight := Flight.new()
	root.add_child(dead_flight)
	copy.hull = 0
	dead_flight.setup(lib, copy, {}, true)
	dead_flight.set_physics_process(false)
	dead_flight.defeated.connect(func(): defeat_events.append(true))
	dead_flight.step(.01)
	check(
		dead_flight.paused and defeat_events.size() == 1 and not copy.finish_mission(),
		"Restoring a destroyed ship returns to defeat instead of allowing progression"
	)
	dead_flight.queue_free()
	var invalid := saved.duplicate(true)
	invalid.active_job.actors[0].heading = [0, 0, 0]
	check(not copy.restore(invalid), "Reject invalid saved enemy heading")
	invalid = saved.duplicate(true)
	invalid.active_job.actors[0].shots = -1
	check(not copy.restore(invalid), "Reject invalid saved attack counter")
	combat = Combat.create()
	Combat.fire(combat, -1, Vector3.ZERO, Vector3.FORWARD, lib, weapons)
	var hits := Combat.advance(
		combat,
		1,
		[
			{"id": 0, "position": [0, 0, -50], "radius": 10},
			{"id": -1, "position": [0, 0, -100], "radius": 10}
		],
		lib,
		weapons
	)
	check(
		hits.size() == 1 and hits[0].target == -1,
		"Enemy shots target the player and ignore allied interceptors"
	)
	var before_pause := shooter.capture()
	flight.pause(true)
	flight.step(1)
	check(
		shooter.capture() == before_pause, "Pause freezes enemy movement, attacks and combat timers"
	)
	flight.queue_free()
	await process_frame
	var departed: bool = campaign.chapter == 2 and campaign.depart()
	check(departed, "Continue the real campaign into its third mission")
	if not departed:
		return
	var credits: int = campaign.credits
	flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {})
	flight.set_physics_process(false)
	flight.toggle_autopilot()
	var engaged := false
	for tick in 18000:
		# At source cruise speed the player must defend against interceptors.
		# Use normal weapons for close threats and a fresh boost press on transit.
		flight.controls.touch_boost = (
			flight.auto_pilot
			and campaign.motion.cooldown <= 0
			and campaign.motion.boost_remaining <= 0
		)
		drive_escort_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		engaged = (
			engaged
			or campaign.active_job.actors.any(func(actor): return int(actor.get("shots", 0)) > 0)
		)
		if flight.paused:
			break
	check(
		campaign.active_job.ready and not campaign.active_job.failed and campaign.hull > 0,
		"Native flight, boost and defensive fire complete the escape route before its source deadline"
	)
	check(
		engaged and campaign.active_job.stage == campaign.route_length(),
		"Escape pilot defends against attackers and completes the independent route objective"
	)
	check(
		not campaign.arrive(0) and campaign.finish_mission(),
		"Escape completion accepts only its imported destination"
	)
	check(
		(
			campaign.chapter == 3
			and campaign.station_id == lib.chapter_destination(2)
			and campaign.credits == credits + int(lib.content.chapters[2].reward)
		),
		"Escape arrives at the next station and pays its source reward once"
	)
	check(
		(
			not campaign.finish_mission()
			and not campaign.exploration_unlocked()
			and campaign.mission_available()
		),
		"Third mission cannot duplicate rewards or fake the finale; the escort is available"
	)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(campaign.capture()))),
		"Completed escape checkpoint restores at the new station"
	)
	flight.queue_free()
	await process_frame


func drive_escort_combat(flight) -> void:
	# Test pilot: use only native steering, throttle, weapons and autopilot.
	# No mission damage or waypoint flags are injected by this flight driver.
	var campaign = flight.session
	flight.controls.touch_boost = (
		flight.auto_pilot and campaign.motion.cooldown <= 0 and campaign.motion.boost_remaining <= 0
	)
	var lib = flight.library
	var gun: Dictionary = lib.weapon_ballistics(campaign.weapon_id)
	var nearest := INF
	var target := {}
	for actor in flight.actors:
		if not flight.hostile(actor):
			continue
		var distance: float = flight.ship.position.distance_to(actor.node.position)
		if distance < nearest:
			target = actor
			nearest = distance
	if not target.is_empty() and nearest < float(gun.speed) * float(gun.lifetime) * .8:
		flight.auto_pilot = false
		flight.throttle = .12 if nearest < 150 else .45
		var motion: Dictionary = (
			lib
			. mission_definition(campaign.chapter)
			. groups[int(target.state.group)]
			. get("motion", {})
		)
		var lead := (
			Combat.vector(target.state.get("heading", [0, 0, 0]))
			* float(motion.get("speed", 0))
			* (nearest / float(gun.speed))
		)
		var point: Vector3 = target.node.position + lead
		if not point.is_equal_approx(flight.ship.global_position):
			flight.ship.look_at(point, Vector3.UP)
		flight.fire()
	elif not flight.auto_pilot:
		flight.toggle_autopilot()


func check_escort_flight(lib, campaign) -> void:
	check(
		campaign.chapter == 3 and campaign.depart(),
		"Continuous campaign launches the original escort mission"
	)
	var credits: int = campaign.credits
	var definition: Dictionary = lib.mission_definition(3)
	var checkpoint: Dictionary = campaign.capture()
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {})
	flight.set_physics_process(false)
	check(
		flight.actors.size() == 1 and not flight.hostile(flight.actors[0]) and not flight.danger(),
		"Escort renders as an ally without suppressing peaceful time acceleration"
	)
	check(
		flight.field_rocks.size() == int(definition.scenery[0].count),
		"Flight creates every imported asteroid-field model"
	)
	var saved_in_flight := false
	for tick in 24000:
		drive_escort_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		if tick == 1800:
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			saved_in_flight = restored.restore(
				JSON.parse_string(JSON.stringify(campaign.capture()))
			)
			check(
				(
					saved_in_flight
					and restored.active_job.scenery.rocks.size() == 40
					and restored.active_job.actors[4].shots == campaign.active_job.actors[4].shots
				),
				"In-flight save restores friendly attack state and persistent field damage"
			)
		if flight.paused:
			break
	check(
		(
			saved_in_flight
			and campaign.active_job.ready
			and not campaign.active_job.failed
			and campaign.hull > 0
			and campaign.active_job.actors[4].hp > 0
		),
		"Native flight wins the full escort route and battle with both ships alive"
	)
	check(
		campaign.active_job.kills == 4,
		"Escort success defeats all imported attackers with actual weapons"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 4
			and campaign.station_id == lib.chapter_destination(3)
			and campaign.credits == credits + int(lib.content.chapters[3].reward)
		),
		"Escort closes its radio then reaches the imported station and pays its reward once"
	)
	check(
		(
			not campaign.finish_mission()
			and not campaign.exploration_unlocked()
			and campaign.mission_available()
		),
		"Fourth mission cannot duplicate rewards or bypass the remaining campaign"
	)
	flight.queue_free()
	await process_frame
	await check_escort_loss(lib, checkpoint, credits)


func check_ballistics(lib) -> void:
	var weapon := int(lib.content.initial.weapon_index)
	var parameters: Dictionary = lib.weapon_ballistics(weapon)
	var state := Combat.create()
	check(
		Combat.fire(state, weapon, Vector3.ZERO, Vector3.FORWARD, lib),
		"Fire a source-defined ballistic weapon"
	)
	check(
		not Combat.fire(state, weapon, Vector3.ZERO, Vector3.FORWARD, lib),
		"Weapon reload prevents immediate duplicate fire"
	)
	var targets := [{"id": 1, "position": [0, 0, -100], "radius": 5.0}]
	var hits := Combat.advance(state, .05, targets, lib)
	check(
		hits.is_empty() and state.projectiles.size() == 1,
		"Projectile requires flight time before damage"
	)
	check(
		is_equal_approx(-float(state.projectiles[0].position[2]), float(parameters.speed) * .05),
		"Projectile travel uses imported speed and actual elapsed time"
	)
	hits = Combat.advance(state, .25, targets, lib)
	check(
		(
			hits.size() == 1
			and hits[0].target == 1
			and hits[0].damage == parameters.damage
			and state.projectiles.is_empty()
		),
		"Swept impact applies imported damage once and consumes the projectile"
	)
	state = Combat.create()
	Combat.fire(state, weapon, Vector3.ZERO, Vector3.FORWARD, lib)
	targets = [
		{"id": 4, "position": [0, 0, -200], "radius": 5.0},
		{"id": 2, "position": [0, 0, -100], "radius": 5.0}
	]
	hits = Combat.advance(state, .5, targets, lib)
	check(
		hits.size() == 1 and hits[0].target == 2,
		"Nearest impact wins independently of target array order"
	)
	state = Combat.create()
	Combat.fire(state, weapon, Vector3.ZERO, Vector3.FORWARD, lib)
	var maximum := float(parameters.speed) * float(parameters.lifetime)
	targets = [{"id": 1, "position": [0, 0, -maximum - 100], "radius": 5.0}]
	hits = Combat.advance(state, float(parameters.lifetime) + 10, targets, lib)
	check(
		hits.is_empty() and state.projectiles.is_empty(),
		"Expired projectiles cannot hit beyond source lifetime range"
	)
	var fine := Combat.create()
	var coarse := Combat.create()
	Combat.fire(fine, weapon, Vector3.ZERO, Vector3.FORWARD, lib)
	Combat.fire(coarse, weapon, Vector3.ZERO, Vector3.FORWARD, lib)
	for tick in 30:
		Combat.advance(fine, 1.0 / 60, [], lib)
	Combat.advance(coarse, .5, [], lib)
	check(
		Combat.vector(fine.projectiles[0].position).is_equal_approx(
			Combat.vector(coarse.projectiles[0].position)
		),
		"Ballistic distance is independent of simulation step size"
	)
	check(
		is_equal_approx(
			Combat.intersection(Vector3.ZERO, Vector3(0, 0, -200), Vector3(5, 0, -100), 5), .475
		),
		"Projectile touching source collision box edge is detected"
	)
	check(
		Combat.intersection(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 5) == 0,
		"Projectile starting inside target registers one immediate contact"
	)
	check(
		Combat.intersection(Vector3.ZERO, Vector3.FORWARD, Vector3.BACK * 10, 5) < 0,
		"Target behind travel direction is not hit"
	)
	state = Combat.create()
	Combat.fire(state, weapon, Vector3.ZERO, Vector3.FORWARD, lib)
	targets = [{"id": 1, "previous": [-100, 0, -100], "position": [100, 0, -100], "radius": 10.0}]
	hits = Combat.advance(state, 200 / float(parameters.speed), targets, lib)
	check(hits.size() == 1, "Swept relative motion detects a crossing target")
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.depart()
	Combat.fire(pilot.combat, weapon, Vector3(100, 0, 0), Vector3.FORWARD, lib)
	Combat.advance(pilot.combat, .1, [], lib)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var restored := Session.new()
	restored.configure(lib, true)
	check(restored.restore(saved), "Save and restore a projectile in flight with cooldown")
	check(
		not Combat.fire(restored.combat, weapon, Vector3.ZERO, Vector3.FORWARD, lib),
		"Reloading does not reset the firing interval"
	)
	Combat.advance(pilot.combat, .1, [], lib)
	Combat.advance(restored.combat, .1, [], lib)
	check(
		(
			Combat.vector(pilot.combat.projectiles[0].position).is_equal_approx(
				Combat.vector(restored.combat.projectiles[0].position)
			)
			and is_equal_approx(
				float(pilot.combat.cooldowns[weapon]), float(restored.combat.cooldowns[weapon])
			)
		),
		"Restored projectile travel and firing time agree"
	)
	var invalid: Dictionary = saved.duplicate(true)
	invalid.combat.projectiles[0].velocity = [0, 0, -10000000]
	check(not restored.restore(invalid), "Reject projectile speed inconsistent with source weapon")
	invalid = saved.duplicate(true)
	invalid.combat.projectiles[0].remaining = 9999
	check(
		not restored.restore(invalid), "Reject projectile lifetime inconsistent with source weapon"
	)
	invalid = saved.duplicate(true)
	invalid.combat.projectiles.append(invalid.combat.projectiles[0].duplicate(true))
	check(not restored.restore(invalid), "Reject duplicate projectile identifiers")
	invalid = saved.duplicate(true)
	invalid.combat.cooldowns[str(weapon)] = 9999
	check(not restored.restore(invalid), "Reject forged weapon cooldown")
	var legacy := saved.duplicate(true)
	legacy.schema = 4
	legacy.erase("combat")
	check(
		restored.restore(legacy) and restored.combat.projectiles.is_empty(),
		"Pre-ballistic saves migrate without inventing shots"
	)
	check(
		restored.arrive(restored.station_id) and restored.combat == Combat.create(),
		"Docking clears transient combat state"
	)
	state = Combat.create()
	check(
		not Combat.fire(state, weapon, Vector3.ZERO, Vector3.ZERO, lib),
		"Reject zero-direction shot"
	)
	var original_speed: String = lib.items[weapon][10]
	var original_lifetime: String = lib.items[weapon][9]
	lib.items[weapon][10] = str(int(original_speed) * 2)
	lib.items[weapon][9] = str(int(original_lifetime) * 2)
	check(
		(
			lib.weapon_ballistics(weapon).speed == parameters.speed * 2
			and lib.weapon_ballistics(weapon).lifetime == parameters.lifetime * 2
		),
		"Changing imported weapon speed and lifetime changes ballistics without engine edits"
	)
	lib.items[weapon][10] = original_speed
	lib.items[weapon][9] = original_lifetime


func check_radio(lib) -> void:
	check(
		lib.content.missions[0].radio.size() == 17 and lib.content.missions[1].radio.size() == 2,
		"Radio arrays are recovered for both supported chapters"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 1
	pilot.progression = Session.Progression.create(1)
	pilot.depart()
	pilot.advance_mission(2.9)
	pilot.advance_radio(.01)
	check(pilot.radio_text().is_empty(), "Clearance transmission waits for its imported trigger")
	pilot.advance_mission(.1)
	pilot.advance_radio(.01)
	check(pilot.radio_text() == lib.text(219), "Original clearance instruction triggers in flight")
	var copy := Session.new()
	copy.configure(lib)
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and copy.radio_text() == pilot.radio_text()
		),
		"Radio display and its consumed triggers survive JSON reload"
	)
	copy.advance_radio(15)
	check(
		copy.radio_text().is_empty() and copy.active_job.radio.shown == [0],
		"Radio does not repeat a consumed transmission"
	)
	for index in copy.active_job.actors.size():
		copy.damage_actor(index, float(copy.active_job.actors[index].hp))
	copy.advance_radio(.01)
	check(
		copy.radio_text() == lib.text(220),
		"Imported clearance success transmission follows the actual objective"
	)
	copy.advance_radio(15)
	copy.advance_radio(15)
	check(
		copy.active_job.radio.shown == [0, 1] and copy.radio_text().is_empty(),
		"Success transmission also plays only once"
	)
	var bad := copy.capture()
	bad.active_job.radio.shown.append(999)
	check(not copy.restore(bad), "Reject radio references outside the mission")
	pilot.configure(lib)
	pilot.depart()
	pilot.advance_mission(2)
	pilot.advance_radio(.01)
	check(pilot.radio_text() == lib.text(196), "Tutorial starts with its imported timed radio cue")
	pilot.advance_radio(15)
	check(pilot.radio_text() == lib.text(197), "Radio dependency schedules the next source line")
	pilot.advance_radio(15)
	check(pilot.radio_text() == lib.text(198), "Dependent radio lines remain ordered")


func check_clearance(lib, pilot) -> void:
	var definition: Dictionary = lib.mission_definition(pilot.chapter)
	check(
		(
			definition.route.is_empty()
			and definition.groups[0].count == 20
			and definition.deadline_ms == 120000
		),
		"Clearance imports static targets and a deadline, without a player route"
	)
	check(
		lib.actor_model(int(definition.groups[0].actor)) == "schrott",
		"Clearance uses the original debris model"
	)
	var initial_credits := int(pilot.credits)
	check(pilot.depart(), "Campaign advances into clearance")
	check(not pilot.travel(2), "Clearance keeps exploration locked")
	pilot.advance_mission(37.25)
	check(pilot.damage_actor(0, .25), "Persistent partial target damage")
	pilot.damage_actor(1, float(pilot.active_job.actors[1].hp))
	var before: Dictionary = pilot.capture()
	var restored := Session.new()
	restored.configure(lib)
	check(restored.restore(JSON.parse_string(JSON.stringify(before))), "Restore JSON mission state")
	check(
		(
			restored.active_job.elapsed_ms == 37250
			and restored.active_job.actors[0].hp == .75
			and restored.active_job.kills == 1
		),
		"Save retains elapsed time, partial damage and destroyed targets"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, restored, {}, true)
	flight.set_physics_process(false)
	check(
		flight.actors.size() == 19 and flight.waypoint != Vector3.ZERO,
		"Resume only surviving debris and navigate directly to targets"
	)
	check(flight.actors[0].state.hp == .75, "Rendered actor shares persistent damage state")
	flight.paused = true
	flight.step(10)
	check(restored.active_job.elapsed_ms == 37250, "Pause freezes the mission deadline")
	flight.paused = false
	var failure_events: Array = []
	flight.mission_failed.connect(func(): failure_events.append(true))
	flight.step((float(definition.deadline_ms) - 37250) / 1000.0)
	check(
		not restored.active_job.failed, "Deadline retains the source strict-greater-than comparison"
	)
	flight.step(.001)
	check(
		(
			restored.active_job.failed
			and not restored.active_job.ready
			and flight.paused
			and failure_events.size() == 1
		),
		"Deadline fails once and pauses flight after the deadline"
	)
	check(not restored.damage_actor(0, 9999), "Failed missions reject further objective changes")
	check(
		restored.restore(JSON.parse_string(JSON.stringify(restored.capture()))),
		"Failed mission state survives JSON reload"
	)
	var bad := before.duplicate(true)
	bad.active_job.ready = true
	check(not restored.restore(bad), "Reject forged mission completion")
	bad = before.duplicate(true)
	bad.active_job.actors[0].hp = -1
	check(not restored.restore(bad), "Reject invalid target health")
	bad = before.duplicate(true)
	bad.active_job.elapsed_ms = -1
	check(not restored.restore(bad), "Reject invalid mission time")
	restored.retry_mission()
	check(
		restored.credits == initial_credits and restored.chapter == 1 and restored.docked,
		"Retry preserves chapter and grants no reward"
	)
	check(
		(
			restored.depart()
			and restored.active_job.elapsed_ms == 0
			and restored.active_job.kills == 0
		),
		"Retry resets mission deadline and targets"
	)
	flight.queue_free()
	await process_frame
	flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, restored, {})
	flight.set_physics_process(false)
	for index in 40:
		if flight.actors.is_empty():
			break
		var target: Node3D = flight.actors[0].node
		flight.ship.position = target.position + Vector3(0, 0, 120)
		flight.ship.look_at(target.position)
		flight.weapon_timers.clear()
		flight.fire()
		flight.advance_projectiles(.25)
		flight.step(.1)
	check(
		flight.actors.is_empty() and restored.active_job.ready,
		"Actual weapons complete the clearance objective"
	)
	var victory_time := float(restored.active_job.elapsed_ms)
	restored.advance_mission(1000)
	check(
		(
			restored.active_job.ready
			and not restored.active_job.failed
			and restored.active_job.elapsed_ms == victory_time
		),
		"Winning stops the deadline while the pilot returns to dock"
	)
	drain_radio(restored)
	check(restored.arrive(restored.station_id), "Complete clearance at its configured station")
	check(
		(
			restored.credits == initial_credits + int(lib.content.chapters[1].reward)
			and restored.chapter == 2
			and not restored.exploration_unlocked()
		),
		"Clearance pays its imported reward once and advances the linear campaign"
	)
	restored.arrive(restored.station_id)
	check(
		restored.credits == initial_credits + int(lib.content.chapters[1].reward),
		"Repeated docking cannot claim a duplicate reward"
	)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(restored.capture()))),
		"Save after the second chapter loads"
	)
	check(restored.mission_available(), "The third chapter is available after clearance")
	var completed_checkpoint := restored.capture()
	# Old previews retained kills but not per-actor damage. Migrate their real
	# counters, without pretending lost old data can be reconstructed.
	var legacy: Dictionary = pilot.capture()
	legacy.schema = 3
	legacy.chapter = 0
	legacy.active_job = {
		"kind": "training",
		"stage": lib.content.opening.route.size(),
		"kills": 2,
		"target": lib.content.opening.target_count,
		"ready": false,
		"origin": pilot.station_id
	}
	check(
		pilot.restore(legacy) and pilot.active_job.kills == 2,
		"Migrate old in-flight training progress"
	)
	check(pilot.restore(completed_checkpoint), "Continue from the verified clearance checkpoint")
	flight.queue_free()
	await process_frame


func offer_index(pilot, kind: String, id: int) -> int:
	var offers: Array = pilot.market_offers()
	for index in offers.size():
		if (
			offers[index].kind == kind
			and int(offers[index].id) == id
			and int(offers[index].count) > 0
		):
			return index
	return -1


func check_economy(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.market_seed = 123
	var initial := pilot.market_offers().duplicate(true)
	var equipment_ids: Array = []
	for offer in initial:
		if offer.kind == "equipment":
			equipment_ids.append(int(offer.id))
	check(equipment_ids == [0, 4], "Opening station uses source campaign stock")
	check(initial == pilot.market_offers(), "Opening the market does not reroll stock")
	var funds := pilot.credits
	check(not pilot.buy_offer(offer_index(pilot, "equipment", 4)), "Reject unaffordable equipment")
	check(pilot.credits == funds and pilot.loadout.hold.is_empty(), "Failed purchase is atomic")
	check(pilot.buy_offer(offer_index(pilot, "equipment", 0)), "Buy source equipment")
	check(
		pilot.credits == funds - int(lib.items[0][6]) and pilot.loadout.hold.size() == 1,
		"Purchase consumes credits and creates one item"
	)
	check(pilot.loadout.hold[0].value == 1850, "Use recovered equipment depreciation")
	check(
		pilot.fit_equipment(0) and pilot.loadout.hold.size() == 1,
		"Fitting swaps the existing item into the hold"
	)
	check(pilot.sell_equipment(0) and pilot.loadout.hold.is_empty(), "Sell unmounted equipment")
	funds = pilot.credits
	check(not pilot.sell_equipment(0) and pilot.credits == funds, "Cannot sell an item twice")
	# Supply money and a later chapter as a fixture; this does not bypass the
	# campaign completion gate or claim that those missions have been played.
	pilot.credits = 1000000
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	check(
		pilot.buy_offer(offer_index(pilot, "equipment", 6)),
		"Later imported campaign shop sells a shield"
	)
	check(
		pilot.fit_equipment(0) and pilot.max_shield() == float(lib.items[6][7]),
		"Imported shield capacity affects loadout"
	)
	check(pilot.buy_offer(offer_index(pilot, "equipment", 9)), "Buy another weapon category")
	check(
		not pilot.fit_equipment(0) and pilot.loadout.hold.size() == 1,
		"Reject unsupported weapon mounts without losing equipment"
	)
	pilot.skip_campaign()
	pilot.slot = "free"
	pilot.chapter = 0
	pilot.progression = Session.Progression.create(0)
	var alien_station := -1
	var all_stock_valid := true
	for station_id in lib.stations.size():
		var station: Dictionary = lib.station_definition(station_id)
		var offers: Array = pilot.Market.generate(lib, station_id, 0, false, station_id + 123)
		if not station.shop and not offers.is_empty():
			all_stock_valid = false
		var ship_units := 0
		var item_units := 0
		for offer in offers:
			if offer.kind == "ship":
				ship_units += int(offer.count)
				var actor := int(lib.content.tables.buyable_ships[int(offer.id)])
				if station.race == 1:
					if actor != 1:
						all_stock_valid = false
				else:
					if (
						actor == 1
						or (actor == 4 and station.race != 9)
						or int(lib.ships[int(offer.id)][2]) > station.quadrant
					):
						all_stock_valid = false
			else:
				item_units += int(offer.count)
				if (
					not lib.content.tables.buyable_equipment.has(int(offer.id))
					or (offer.id > 24 and station.race != 1)
					or int(lib.items[int(offer.id)][2]) > station.quadrant
				):
					all_stock_valid = false
		if station.shop:
			if item_units < 1 or item_units > 4 or ship_units > (1 if station.race == 1 else 3):
				all_stock_valid = false
			if station.race == 1 and alien_station < 0:
				alien_station = station_id
	check(
		all_stock_valid,
		"All station markets obey source stock counts, quadrants and faction restrictions"
	)
	check(alien_station >= 0 and pilot.travel(alien_station), "Reach an imported alien shipyard")
	var old_equipment := pilot.loadout.capture()
	check(
		pilot.buy_offer(offer_index(pilot, "ship", 8)),
		"Exchange ship through generated faction stock"
	)
	check(
		pilot.ship_id == 8 and pilot.hull == float(lib.ships[8][4]),
		"New ship uses imported hull and model association"
	)
	check(pilot.loadout.capture() == old_equipment, "Ship exchange preserves equipment")
	check(pilot.ship_value == 65000, "Ship depreciation comes from source data")
	var crowded := pilot.loadout.capture()
	for index in 6:
		crowded.hold.append({"id": 0, "value": 1850})
	var loadout := pilot.Loadout.new()
	loadout.configure(lib)
	check(loadout.restore(crowded, 8, 0), "Construct capacity fixture")
	check(
		loadout.ship_exchange(9, 0).is_empty(), "Reject exchange to a ship whose hold is too small"
	)
	check(
		pilot.Market.cargo_price(lib, 15, 0) == 235,
		"Cargo with inverse technology dependence uses the source formula"
	)
	check(
		pilot.Market.cargo_price(lib, 19, 0) == 536,
		"Cargo with direct technology dependence uses the source formula"
	)
	pilot.cargo = {"15": 2}
	funds = pilot.credits
	var expected: int = pilot.Market.cargo_price(lib, 15, pilot.station_id)
	check(
		pilot.sell_cargo(15) and pilot.credits == funds + expected and pilot.cargo["15"] == 1,
		"Cargo resale updates money, quantity and shop stock"
	)
	var saved := pilot.capture()
	var restored := Session.new()
	restored.configure(lib, true)
	check(
		restored.restore(saved), "Restore equipment, ship value and market state: " + restored.error
	)
	check(
		(
			restored.loadout.capture() == pilot.loadout.capture()
			and restored.market_offers() == pilot.market_offers()
		),
		"Save round trip preserves exact loadout and remaining offers"
	)
	var economy_save: String = "user://test-saves/" + lib.id + "/economy.json"
	check(
		pilot.save(economy_save) and restored.load_save(economy_save),
		"Economy state survives JSON serialization"
	)
	check(
		(
			restored.loadout.capture() == pilot.loadout.capture()
			and restored.market_offers() == pilot.market_offers()
		),
		"Serialized equipment and stock match exactly"
	)
	var visited_count := restored.visited.size()
	restored.arrive(restored.station_id)
	check(
		restored.visited.size() == visited_count,
		"Restored station identities do not duplicate on docking"
	)
	var corrupt := saved.duplicate(true)
	corrupt.loadout.fitted[0] = {"id": 9, "value": 100}
	check(not restored.restore(corrupt), "Reject an incompatible saved mounted item")
	corrupt = saved.duplicate(true)
	corrupt.markets.values()[0][0].price = -1
	check(not restored.restore(corrupt), "Reject invalid saved offer prices")
	var legacy := saved.duplicate(true)
	legacy.schema = 2
	for key in ["loadout", "ship_value", "market_seed", "market_generation", "markets"]:
		legacy.erase(key)
	legacy.shield = 0
	check(
		restored.restore(legacy) and restored.credits == pilot.credits,
		"Migrate previous preview saves without granting credits"
	)
	pilot.loadout.hold.append({"id": 22, "value": 5850})
	check(pilot.fit_equipment(pilot.loadout.hold.size() - 1), "Fit a second primary weapon")
	pilot.loadout.hold.append({"id": 3, "value": 8500})
	check(
		pilot.fit_equipment(pilot.loadout.hold.size() - 1),
		"Fit missiles to a compatible source mount"
	)
	pilot.cycle_weapon()
	check(pilot.weapon_id == 22, "Cycle between fitted primary weapons")
	check(
		restored.restore(pilot.capture()) and restored.weapon_id == 22,
		"Save selected weapon independently of mount order"
	)
	pilot.docked = false
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	flight.fire()
	check(
		(
			flight.weapon_timers.has(22)
			and not flight.weapon_timers.has(0)
			and not flight.weapon_timers.has(3)
		),
		"Primary fire respects selection and reserves missiles"
	)
	flight.fire_missiles()
	check(flight.weapon_timers.has(3), "Secondary fire launches mounted missiles")
	flight.weapon_timers.clear()
	flight.settings.linked_fire = true
	flight.fire()
	check(
		(
			flight.weapon_timers.has(0)
			and flight.weapon_timers.has(22)
			and not flight.weapon_timers.has(3)
		),
		"Optional linked fire fires all primary mounts"
	)
	pilot.shield = pilot.max_shield() - 2
	flight.throttle = 0
	for index in 240:
		flight.step(1.0 / 60.0)
	check(
		pilot.shield == pilot.max_shield(), "Fitted shield regenerates using the imported interval"
	)
	flight.queue_free()
	await process_frame


func drain_radio(pilot) -> void:
	for index in 64:
		if pilot.ready_to_finish():
			break
		pilot.advance_radio(15)


func check_assault_mutations(source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index assault source declarations")
	var bounds := reader.campaign_boundaries(13)
	var first := bounds[4]
	var end := bounds[5]
	var arrays := reader.calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := reader.calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var hp := reader.calls_between(first, end, "__ZN6Player12setHitpointsEi")[0]
	var moving := reader.calls_between(first, end, "__ZN17PlayerFixedObject9setMovingEb")[0]
	var count_offset := reader.file_offset(arrays[0] - 10, 2)
	var boundary_offset := reader.file_offset(ships[1] + 36, 2)
	var moving_offset := reader.file_offset(moving - 12, 2)
	var hp_offset := literal_file_offset(reader, hp - 12)
	var center_offset := reader.file_offset(reader.literal(first, 3), 4)
	var factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var size_offset := literal_file_offset(reader, factory + 0x73a)
	var changed := source.duplicate()
	changed.encode_u16(count_offset, 0x2008)
	changed.encode_u16(boundary_offset, 0x2c20)
	changed.encode_u32(hp_offset, 123456)
	changed.encode_s32(center_offset, 12000)
	changed.encode_u32(size_offset, 2460)
	var imported := reader.extract(changed)
	check(not imported.is_empty(), "Import changed assault declaration: " + reader.error)
	if not imported.is_empty():
		var definition: Dictionary = imported.missions[4]
		check(
			definition.groups[1].count == 4,
			"Fixed target count comes from changed source array range"
		)
		check(
			definition.groups[2].initial_hp == 123456,
			"Scripted ally starting health comes from supplied data"
		)
		check(
			definition.groups[0].center[0] == 12000 and definition.groups[2].route[0][0] == 12000,
			"Spawn target and allied route share the imported local route"
		)
		check(
			definition.groups[1].collision.size[0] == 2460,
			"Fixed body dimensions come from the source initializer"
		)
	changed = source.duplicate()
	changed.encode_u16(moving_offset, 0x2101)
	check(
		reader.extract(changed).is_empty(),
		"Reject moving fixed targets until their motion is supported"
	)


func check_assault(lib) -> void:
	var definition: Dictionary = lib.mission_definition(4)
	check(
		lib.mission_playable(4) and definition.groups.size() == 4 and definition.route.is_empty(),
		"Fifth chapter imports separate fighters, fixed targets and two allied ships"
	)
	check(
		(
			definition.groups[0].count == 4
			and definition.groups[1].count == 3
			and definition.groups[1].actor == 19
			and definition.groups[1].behavior == "stationary"
		),
		"Source assault group identities and counts are preserved"
	)
	check(
		(
			lib.group_hull(definition.groups[1]) == 240
			and lib.group_hull(definition.groups[2]) == 40
			and lib.group_initial_hull(definition.groups[2]) == 9999999
		),
		"Catalog hull and exceptional starting health retain separate meanings"
	)
	check(
		(
			definition.radio.size() == 10
			and definition.radio[7].condition == "enemy_range_casualty"
			and definition.radio[7].value == 4
			and definition.radio[7].count == 3
		),
		"Assault imports all ten radio cues and fixed-target casualty range"
	)
	var state := Session.Mission.create(definition, 4, 2, lib, 22)
	check(
		state.actors.size() == 9 and state.target == 7 and state.actors[7].hp == 9999999,
		"Allied ships do not count toward the destruction objective"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 4, 2, lib),
		"Exceptional ally health survives strict JSON mission validation"
	)
	var malformed := state.duplicate(true)
	malformed.actors[7].hp += 1
	check(
		not Session.Mission.valid(definition, malformed, 4, 2, lib),
		"Reject health beyond imported starting allowance"
	)
	var fixed_position := Combat.vector(state.actors[4].position)
	var original_position: Array = state.actors[4].position.duplicate()
	state.actors[7].position = Combat.packed(fixed_position + Vector3(10, 0, 0))
	Session.Encounters.advance(
		definition,
		state,
		.01,
		Vector3(100000, 100000, 100000),
		Vector3.ZERO,
		Combat.create(),
		lib,
		lib.actor_weapons(4)
	)
	check(
		state.actors[4].awake and state.actors[4].position == original_position,
		"A wingmate activates a fixed target without moving its body or needing the player nearby"
	)
	check(not lib.actor_weapons(4).has(-5), "Unarmed fixed targets cannot create projectiles")
	check(
		not Session.Mission.Radio.triggered(definition.radio[7], definition, state),
		"Casualty radio waits for an actual target death"
	)
	state.actors[0].awake = true
	Session.Mission.damage(definition, state, 0, state.actors[0].hp)
	check(
		not Session.Mission.Radio.triggered(definition.radio[7], definition, state),
		"A fighter casualty cannot trigger fixed-target dialogue"
	)
	Session.Mission.damage(definition, state, 4, state.actors[4].hp)
	check(
		Session.Mission.Radio.triggered(definition.radio[7], definition, state) and not state.ready,
		"The first fixed target casualty triggers its cue before full mission victory"
	)
	var extent := Session.Mission.point(definition.groups[1].collision.size).abs() * .5
	check(
		(
			(
				Combat.box_intersection(Vector3(0, 0, 100), Vector3(0, 0, 80), Vector3.ZERO, extent)
				>= 0
			)
			and (
				Combat.box_intersection(
					Vector3(20, 0, 100), Vector3(20, 0, -100), Vector3.ZERO, extent
				)
				< 0
			)
		),
		"Long fixed hull is hittable along its length without inflating its narrow sides"
	)
	var shot := Combat.create()
	Combat.fire(shot, 0, Vector3(0, 0, 100), Vector3.FORWARD, lib)
	var hits := Combat.advance(
		shot, .1, [{"id": 4, "position": [0, 0, 0], "extent": Combat.packed(extent)}], lib
	)
	check(
		hits.size() == 1 and hits[0].target == 4,
		"Ballistic collision consumes imported rectangular extents"
	)


func drive_assault_combat(flight) -> void:
	# Stay with the wingmates during the approach, then clear armed fighters
	# before fixed targets. This changes pilot inputs, never combat state.
	var campaign = flight.session
	var lib = flight.library
	var gun: Dictionary = lib.weapon_ballistics(campaign.weapon_id)
	var nearest := INF
	var target := {}
	var fighters: Array = flight.actors.filter(
		func(actor): return flight.hostile(actor) and actor.state.has("heading")
	)
	for actor in flight.actors:
		if (
			not flight.hostile(actor)
			or (not fighters.is_empty() and not actor.state.has("heading"))
		):
			continue
		var distance: float = flight.ship.position.distance_to(actor.node.position)
		if distance < nearest:
			target = actor
			nearest = distance
	flight.auto_pilot = false
	if not target.is_empty() and nearest < float(gun.speed) * float(gun.lifetime) * .8:
		flight.throttle = .12 if nearest < 150 else .45
		var motion: Dictionary = (
			lib
			. mission_definition(campaign.chapter)
			. groups[int(target.state.group)]
			. get("motion", {})
		)
		var lead := (
			Combat.vector(target.state.get("heading", [0, 0, 0]))
			* float(motion.get("speed", 0))
			* (nearest / float(gun.speed))
		)
		var point: Vector3 = target.node.position + lead
		if point.distance_to(flight.ship.position) > .001:
			flight.ship.look_at(point, Vector3.UP)
		flight.fire()
	else:
		flight.throttle = 1.0
		var destination: Vector3 = flight.navigation_target()
		if destination.distance_to(flight.ship.position) > .001:
			flight.ship.look_at(destination, Vector3.UP)


func check_assault_flight(lib, campaign):
	check(
		campaign.chapter == 4 and campaign.depart(),
		"Continuous campaign launches fifth mission after escort"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {})
	flight.set_physics_process(false)
	check(
		flight.actors.size() == 2 and flight.waypoint != Vector3.ZERO and not flight.danger(),
		"Dormant assault has an imported target area and two friendly wingmates at departure"
	)
	var saved := false
	var resumed := false
	for tick in 24000:
		drive_assault_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		if (
			not saved
			and (campaign.active_job.kills > 0 or not campaign.combat.projectiles.is_empty())
			and not campaign.active_job.ready
		):
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			saved = restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				saved and restored.active_job.actors[7].hp == campaign.active_job.actors[7].hp,
				"Battle save preserves the scripted wingmate health during live combat"
			)
			if saved:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {}, true)
				flight.set_physics_process(false)
				resumed = true
		if flight.paused:
			break
	check(
		(
			saved
			and resumed
			and campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.kills == 7
		),
		"Native fifth mission survives a mid-battle reload and destroys all seven original targets"
	)
	check(
		campaign.active_job.radio.shown.size() == 10,
		"All imported assault radio cues finish before arrival"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 5
			and campaign.station_id == lib.chapter_destination(4)
			and campaign.credits == credits + int(lib.content.chapters[4].reward)
		),
		"Fifth mission pays its original reward once and arrives at its original destination"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Sixth chapter is available, later campaign progression remains gated without granting campaign completion"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(
		(
			restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			and restored.chapter == 5
			and not restored.exploration_unlocked()
		),
		"Station save preserves the fifth reward and remaining campaign gate"
	)
	flight.queue_free()
	await process_frame
	return campaign


func check_duel_mutations(source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index duel source declarations")
	var bounds := reader.campaign_boundaries(13)
	var hull := reader.calls_between(bounds[5], bounds[6], "__ZN6Player15setMaxHitpointsEi")[0]
	var script := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var first := table + reader.u16(table + 2) * 2
	var end := table + reader.u16(table + 4) * 2
	var health := reader.calls_between(first, end, "__ZN6Player12setHitpointsEi")[0]
	var messages := reader.calls_between(first, end, "__ZN12RadioMessage6isOverEv")
	var message_offset := reader.file_offset(messages[0] - 2, 2)
	var assign := reader.symbol_address("__ZN5Level10assignGunsEv")
	var guns := reader.calls_between(assign, reader.symbol_end(assign), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return reader.u16(call + 14) == 0x208c and reader.u16(call + 18) == 0x5031
	)
	var speed_offset := reader.file_offset(guns[0] - 34, 2)
	var capacity_offset := reader.file_offset(guns[0] - 26, 2)
	var changed := source.duplicate()
	changed.encode_float(literal_file_offset(reader, hull - 14), 800.0)
	changed.encode_s32(literal_file_offset(reader, health + 26), -18000)
	changed.encode_s32(literal_file_offset(reader, first + 430), 21000)
	changed.encode_u16(message_offset, 0x6958)
	changed.encode_u16(speed_offset, 0x2312)
	changed.encode_u16(capacity_offset, 0x221e)
	var imported := reader.extract(changed)
	check(not imported.is_empty(), "Import changed duel content: " + reader.error)
	if not imported.is_empty():
		var definition: Dictionary = imported.missions[5]
		check(
			definition.groups[0].hull == 800 and definition.sequence[0].when.value == 400,
			"Changed source hull determines both combat health and the surrender threshold"
		)
		check(
			definition.sequence[1].when.message == 5,
			"Surrender continuation uses the supplied message reference"
		)
		check(
			definition.sequence[1].actions[1].offset[2] == -18000,
			"Commander arrival offset is read from supplied content"
		)
		check(
			definition.sequence[2].actions[0].offset[0] == 21000,
			"Authored camera focus uses the changed source offset"
		)
		check(
			definition.groups[1].weapon.speed == 360,
			"Commander projectile speed follows its speed argument independently of pool capacity"
		)
	changed = source.duplicate()
	changed.encode_u16(message_offset, 0x2005)
	check(reader.extract(changed).is_empty(), "Reject unsupported event message associations")


func check_duel(lib) -> void:
	var definition: Dictionary = lib.mission_definition(5)
	check(
		(
			definition.groups.size() == 2
			and definition.groups[0].actor == 4
			and definition.groups[1].actor == 10
		),
		"Duel imports Lockwood and the offstage commander from source actor references"
	)
	check(
		(
			definition.route.is_empty()
			and definition.scenery[0].count == 80
			and definition.scenery[0].center[2] == 130000
		),
		"Duel asteroid field has an independent imported center without imposing a player route"
	)
	check(
		definition.groups[0].hull == 650 and definition.groups[0].scatter[0][0] == -3200,
		"Duel hull override and narrower chapter-specific spawn bounds are imported"
	)
	check(
		(
			is_equal_approx(definition.groups[0].motion.speed, 50.4)
			and lib.actor_weapons(5)[-2].damage == 50
			and lib.actor_weapons(5)[-2].speed == 320
		),
		"Duel flight multiplier and commander's rank-independent weapon use source values"
	)
	check(
		(
			definition.sequence.size() == 4
			and definition.sequence[0].when.value == 325
			and definition.sequence[1].when.message == 4
			and definition.sequence[3].when.message == 7
		),
		"Surrender, execution and departure are imported as authored encounter milestones"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 5
	pilot.progression = Session.Progression.create(5)
	pilot.station_id = lib.chapter_destination(4)
	check(pilot.depart(), "Native director enables the staged sixth mission")
	var state: Dictionary = pilot.active_job
	state.actors[0].awake = true
	pilot.damage_actor(0, 325)
	check(
		(
			state.sequence_cursor == 0
			and not Session.Mission.Radio.triggered(definition.radio[4], definition, state)
		),
		"Exactly half hull does not surrender: source condition is strictly below the threshold"
	)
	pilot.damage_actor(0, 1)
	var directives := Session.Mission.Sequence.directives(definition, state)
	check(
		(
			state.sequence_cursor == 1
			and directives.locked
			and directives.stopped.has(0)
			and Session.Mission.Radio.triggered(definition.radio[4], definition, state)
		),
		"Crossing the imported threshold restrains Lockwood, focuses the scene and triggers surrender dialogue"
	)
	var forged := pilot.capture().duplicate(true)
	forged.active_job.sequence_cursor = 2
	check(
		not pilot.restore(forged), "Reject advancing past surrender dialogue that has not finished"
	)
	check(
		Session.Mission.valid(
			definition, JSON.parse_string(JSON.stringify(state)), 5, pilot.station_id, lib
		),
		"Surrendered encounter saves validate without replaying the first transition"
	)
	var original: Array = state.actors[0].position.duplicate()
	Session.Encounters.advance(
		definition, state, .1, Vector3.ZERO, Vector3.ZERO, pilot.combat, lib, pilot.actor_weapons()
	)
	check(
		state.actors[0].position == original and state.actors[0].shots == 0,
		"Restrained ship remains visible and targetable while stopping its flight and guns"
	)
	for tick in 9000:
		pilot.advance_radio(1.0 / 60)
		pilot.advance_mission(1.0 / 60)
		if state.sequence_cursor >= 2:
			break
	check(
		state.sequence_cursor == 2 and state.actors[0].hp == 1 and state.actors[1].awake,
		"Finishing surrender dialogue applies source health and activates the commander"
	)
	check(
		is_equal_approx(
			Combat.vector(state.actors[1].position).distance_to(
				Combat.vector(state.actors[0].position)
			),
			400
		),
		"Commander arrives at the imported relative offset"
	)
	var guns := pilot.actor_weapons()
	check(
		guns[-2].target_ids == [0],
		"The authored target assignment is recovered independently of normal faction targeting"
	)
	var combat := Combat.create()
	Combat.fire(combat, -2, Vector3.ZERO, Vector3.FORWARD, lib, guns)
	var impacts := Combat.advance(
		combat,
		1,
		[
			{"id": -1, "team": "ally", "position": [0, 0, -10], "radius": 5},
			{"id": 0, "team": "enemy", "position": [0, 0, -100], "radius": 5}
		],
		lib,
		guns
	)
	check(
		impacts.size() == 1 and impacts[0].target == 0,
		"Commander shots pass the player and strike their explicit target even within the same faction"
	)
	var scene := Flight.new()
	root.add_child(scene)
	scene.setup(lib, pilot, {})
	scene.set_physics_process(false)
	var position := scene.ship.position
	var rotation := scene.ship.rotation
	var next_id: int = pilot.combat.next_id
	var mouse := InputEventMouseMotion.new()
	mouse.relative = Vector2(50, 30)
	scene._unhandled_input(mouse)
	scene.fire()
	scene.fire_missiles()
	scene.toggle_autopilot()
	scene.controls.touch_fire = true
	scene.step(.01)
	scene.update_camera(1)
	check(
		(
			scene.ship.position.distance_to(position) > 0
			and scene.ship.rotation == rotation
			and not scene.auto_pilot
		),
		"Cinematic control capture blocks steering and autopilot while source cruise continues"
	)
	check(
		pilot.combat.next_id <= next_id + 1,
		"Cinematic input cannot fire player weapons; only the scripted NPC may shoot"
	)
	check(
		scene.camera.position.distance_to(Combat.vector(state.actors[1].position)) < 200,
		"Cinematic camera follows the source-defined commander focus and offset"
	)
	for index in 3:
		var restored := Session.new()
		restored.configure(lib)
		var recovered := restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
		check(
			recovered, "Cinematic save restores actor orders and dialogue without reapplying health"
		)
		if recovered:
			pilot = restored
	var legacy := pilot.capture().duplicate(true)
	legacy.schema = 5
	legacy.combat = Combat.create()
	Combat.fire(legacy.combat, -2, Vector3.ZERO, Vector3.FORWARD, lib, pilot.actor_weapons())
	legacy.combat.projectiles[0].velocity = [0, 0, -400]
	Combat.fire(legacy.combat, pilot.weapon_id, Vector3.ONE, Vector3.RIGHT, lib)
	var migrated := Session.new()
	migrated.configure(lib)
	check(
		migrated.restore(JSON.parse_string(JSON.stringify(legacy))),
		"Migrate the previous preview's commander projectile without losing cinematic progress"
	)
	check(
		(
			migrated.combat.projectiles.size() == 2
			and is_equal_approx(
				Combat.vector(migrated.combat.projectiles[0].velocity).length(), 320
			)
			and migrated.combat.projectiles[1].velocity == legacy.combat.projectiles[1].velocity
			and migrated.active_job.sequence_cursor == pilot.active_job.sequence_cursor
		),
		"Weapon-speed migration changes only the affected NPC velocity"
	)
	legacy.combat.projectiles[0].velocity = [0, 0, -42]
	check(
		not migrated.restore(legacy),
		"Legacy migration still rejects unrecognized projectile velocities"
	)
	legacy.schema = Session.SCHEMA
	legacy.combat.projectiles[0].velocity = [0, 0, -400]
	check(
		not migrated.restore(legacy),
		"Current saves cannot claim the old incorrect projectile speed"
	)
	var invalid := definition.duplicate(true)
	invalid.sequence[1].actions[3].target = 999
	check(
		not Session.Mission.Sequence.valid_definition(invalid),
		"Reject out-of-range authored encounter target"
	)
	scene.queue_free()


func drive_duel_combat(flight) -> void:
	if flight.cinematic_locked():
		return
	var gun: Dictionary = flight.library.weapon_ballistics(flight.session.weapon_id)
	var nearest := INF
	var target := {}
	for actor in flight.actors:
		if not flight.hostile(actor):
			continue
		var distance: float = flight.ship.position.distance_to(actor.node.position)
		if distance < nearest:
			target = actor
			nearest = distance
	flight.auto_pilot = false
	if not target.is_empty() and nearest < float(gun.speed) * float(gun.lifetime) * .8:
		# Hold outside the dense field while engaging the approaching opponent.
		flight.throttle = 0
		var motion: Dictionary = (
			flight
			. library
			. mission_definition(flight.session.chapter)
			. groups[int(target.state.group)]
			. motion
		)
		var aim: Vector3 = (
			target.node.position
			+ (
				Combat.vector(target.state.destruction.velocity)
				* (nearest / float(gun.speed))
			)
		)
		if not aim.is_equal_approx(flight.ship.global_position):
			flight.ship.look_at(aim, Vector3.UP)
		flight.fire()
	else:
		flight.throttle = 1.0
		var destination: Vector3 = flight.navigation_target()
		if not destination.is_equal_approx(flight.ship.global_position):
			flight.ship.look_at(destination, Vector3.UP)


func check_duel_flight(lib, campaign):
	check(
		campaign.chapter == 5 and campaign.depart(),
		"Sixth mission follows the preceding five played chapters"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {})
	flight.set_physics_process(false)
	var saved: Array[int] = []
	for tick in 24000:
		drive_duel_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		var cursor := int(campaign.active_job.sequence_cursor)
		if cursor in [1, 2, 3] and not saved.has(cursor):
			saved.append(cursor)
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			var recovered := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				recovered and restored.active_job.sequence_cursor == cursor,
				"Restore cinematic stage %d during actual sixth-mission combat" % cursor
			)
			if recovered:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	check(
		(
			saved == [1, 2, 3]
			and campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.sequence_cursor == 4
		),
		"Complete the staged duel with real weapons and reload at each cinematic milestone"
	)
	check(
		(
			campaign.active_job.actors[1].shots > 0
			and campaign.active_job.kills == 2
			and campaign.active_job.radio.shown.size() == 9
		),
		"Commander fires, scripted departure clears the encounter and all nine radio cues finish"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 6
			and campaign.station_id == lib.chapter_destination(5)
			and campaign.credits == credits + int(lib.content.chapters[5].reward)
		),
		"Sixth mission pays its supplied reward and arrives at the correct destination after the story sequence"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"The seventh chapter becomes available while exploration stays locked"
	)
	flight.queue_free()
	await process_frame
	return campaign


func check_convoy_parameters(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index convoy declarations")
	var bounds := reader.campaign_boundaries(13)
	var parameters := reader.convoy_parameters(bounds[6], bounds[7])
	check(not parameters.is_empty(), "Recover convoy parameters: " + reader.error)
	if parameters.is_empty():
		return
	check(
		(
			parameters.fighters.count == 3
			and parameters.capital.actor == 20
			and parameters.turrets.count == 6
			and parameters.cargo.count == 5
		),
		"Convoy content declares three fighters, a cruiser, six turrets and five cargo ships"
	)
	check(
		parameters.success.duration_ms == 240000 and parameters.failure.kind == "allies_destroyed",
		"Original convoy success is timed survival and failure requires losing all cargo ships"
	)
	check(
		(
			parameters.turrets.hull == 90
			and parameters.cargo.hull == 65
			and parameters.failure_text == 402
		),
		"Convoy health overrides and failure text come from the supplied declaration"
	)
	check(
		(
			parameters.fighters.positions[0] == [0, 0, 150000]
			and parameters.fighters.positions[1] == [0, 0, 250000]
			and parameters.fighters.positions[2] == parameters.fighters.positions[1]
			and parameters.cargo.offsets[4] == [1000, 7000, 8000]
		),
		"Convoy attacker route associations and individual friendly offsets are preserved"
	)
	check(
		(
			parameters.turrets.mounts.actor == 21
			and parameters.turrets.mounts.positions[0] == [-680, -78, 3602]
			and parameters.turrets.mounts.facing[4] == [0, -65536, 0]
		),
		"Turrets use the cruiser's original mount geometry and facing data"
	)
	check(
		(
			parameters.turrets.weapon.interval == 4
			and parameters.turrets.weapon.lifetime == 4
			and parameters.turrets.weapon.speed == 120
			and parameters.turrets.weapon.damage_rule.base == 10
		),
		"Cruiser turret ballistics use source gun fields rather than projectile pool capacity"
	)
	check_convoy_objectives(parameters, lib)
	var declaration := reader.convoy_definition(bounds[6], bounds[7], 6)
	check(
		(
			declaration.groups[1].collisions[0].size == [2265, 1187, 6308]
			and declaration.groups[8].velocity == [0, 0, -32.0]
			and is_equal_approx(declaration.groups[2].tracking.aim_sine, 299.0 / 65536.0)
		),
		"Cruiser dimensions, cargo speed and turret tracking are recovered from their source declarations"
	)
	var ship_factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var fixed_update := reader.symbol_address("__ZN17PlayerFixedObject6updateEi")
	var turret_update := reader.symbol_address("__ZN12PlayerTurret6updateEi")
	var event_script := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var event_first := event_script + 48 + reader.u16(event_script + 52) * 2
	var roles_changed := source.duplicate()
	roles_changed.encode_u32(literal_file_offset(reader, ship_factory + 0x522 - 24), 2500)
	roles_changed.encode_u16(reader.file_offset(fixed_update + 78, 2), 0x2108)
	roles_changed.encode_u32(literal_file_offset(reader, turret_update + 578), 12000)
	roles_changed.encode_u32(literal_file_offset(reader, turret_update + 582), 24000)
	roles_changed.encode_s32(literal_file_offset(reader, turret_update + 600), -12001)
	roles_changed.encode_s32(literal_file_offset(reader, event_first + 112), 6000)
	reader.bytes = roles_changed
	var roles_altered := reader.convoy_definition(bounds[6], bounds[7], 6)
	check(
		(
			not roles_altered.is_empty()
			and roles_altered.groups[1].collisions[0].size[0] == 2500
			and roles_altered.groups[8].velocity[2] == -40
			and roles_altered.groups[2].tracking.range_half_width == 240
			and roles_altered.sequence[0].actions[1].offset[0] == 6000
		),
		"Changes in supplied body geometry, transit speed, turret range and camera offset flow into native definitions"
	)
	roles_changed.encode_u16(reader.file_offset(ship_factory + 0x522, 2), 0)
	reader.bytes = roles_changed
	reader.error = ""
	check(
		reader.convoy_definition(bounds[6], bounds[7], 6).is_empty(),
		"An unrecognized collision initializer is rejected instead of inventing capital-ship bounds"
	)
	reader.bytes = source
	reader.error = ""
	var objectives := reader.calls_between(bounds[6], bounds[7], "__ZN9ObjectiveC1EiiP5Level")
	var hulls := reader.calls_between(bounds[6], bounds[7], "__ZN6Player15setMaxHitpointsEi")
	var duration_offset := literal_file_offset(reader, objectives[0] - 28)
	var factory := reader.symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	var mount_offset := reader.file_offset(reader.literal(factory + 250, 2), 4)
	var association_offset := reader.file_offset(factory + 70, 2)
	var damage_offset := literal_file_offset(reader, hulls[0] - 14)
	var changed := source.duplicate()
	changed.encode_u32(duration_offset, 210000)
	changed.encode_s32(mount_offset, -900)
	changed.encode_float(damage_offset, 110.0)
	reader.bytes = changed
	reader.error = ""
	var altered := reader.convoy_parameters(bounds[6], bounds[7])
	check(
		(
			not altered.is_empty()
			and altered.success.duration_ms == 210000
			and altered.turrets.hull == 110
			and altered.turrets.mounts.positions[0][0] == -900
		),
		"Changing the supplied duration, turret hull and mount geometry changes recovered content"
	)
	changed.encode_u16(association_offset, 0x2813)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.convoy_parameters(bounds[6], bounds[7]).is_empty(),
		"Reject a turret factory whose parent no longer matches the convoy cruiser"
	)
	reader.bytes = source
	reader.error = ""
	check(
		reader.turret_mounts(20, 32).is_empty(), "Reject turret reads beyond the source mount table"
	)
	check(
		lib.mission_playable(6) and not lib.mission_playable(13),
		"Native convoy roles remain available alongside the complete chapter list"
	)


func check_convoy_objectives(parameters: Dictionary, lib) -> void:
	var definition := {
		"route": [],
		"groups": [],
		"radio": [],
		"deadline_ms": 0,
		"success": parameters.success,
		"failure": parameters.failure
	}
	for offset in parameters.cargo.offsets:
		definition.groups.append(
			{
				"count": 1,
				"actor": parameters.cargo.actor,
				"hull": parameters.cargo.hull,
				"team": "ally",
				"placement": "player_offset",
				"center": offset,
				"scatter": [],
				"after_route": false
			}
		)
	check(
		(
			lib.valid_objective(definition.success, definition)
			and lib.valid_objective(definition.failure, definition)
		),
		"Validate native convoy objective declarations"
	)
	var state := Session.Mission.create(definition, 6, 3, lib, 22)
	Session.Mission.evaluate(definition, state)
	check(
		not state.ready and not state.failed,
		"Survival does not complete because there are no remaining enemy targets"
	)
	for index in range(state.actors.size() - 1):
		Session.Mission.damage(definition, state, index, parameters.cargo.hull)
	check(
		not state.failed, "One surviving cargo ship is sufficient to keep the convoy mission active"
	)
	Session.Mission.advance(definition, state, parameters.success.duration_ms / 1000.0, lib)
	check(
		not state.ready and not state.failed,
		"Original survival predicate is strictly beyond its time boundary"
	)
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(
		Session.Mission.valid(definition, restored, 6, 3, lib),
		"Partial convoy losses and survival time survive strict JSON validation"
	)
	Session.Mission.advance(definition, restored, .001, lib)
	check(
		restored.ready and not restored.failed,
		"Surviving past the supplied duration completes the objective"
	)
	var failed := Session.Mission.create(definition, 6, 3, lib, 22)
	for index in failed.actors.size():
		Session.Mission.damage(definition, failed, index, parameters.cargo.hull)
	check(failed.failed and not failed.ready, "Losing every cargo ship fails the convoy")
	var simultaneous := state.duplicate(true)
	simultaneous.elapsed_ms += 1
	Session.Mission.damage(
		definition, simultaneous, simultaneous.actors.size() - 1, parameters.cargo.hull
	)
	check(
		simultaneous.failed and not simultaneous.ready,
		"Final cargo loss takes precedence over survival at the same update"
	)
	check(
		(
			not lib.valid_objective({"kind": "time_survived", "duration_ms": -1}, definition)
			and not lib.valid_objective({"kind": "allies_destroyed"}, {"groups": []})
		),
		"Reject invalid survival durations and objectives without friendly participants"
	)


func check_convoy(lib) -> void:
	var definition: Dictionary = lib.mission_definition(6)
	check(
		(
			definition.groups.size() == 13
			and definition.groups[1].collisions.size() == 3
			and definition.radio.size() == 6
			and definition.sequence.size() == 2
		),
		"Convoy imports compound cruiser bodies, independent turrets, transit cargo and radio choreography"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 6
	pilot.progression = Session.Progression.create(6)
	pilot.station_id = lib.chapter_destination(5)
	pilot.market_seed = 22
	check(pilot.depart(), "Launch the imported convoy encounter")
	var state: Dictionary = pilot.active_job
	var original: Dictionary = state.duplicate(true)
	var weapons: Dictionary = pilot.actor_weapons()
	var before := Combat.vector(state.actors[10].position)
	Session.Encounters.advance(
		definition, state, 2, Vector3(0, 0, 20000), Vector3.ZERO, pilot.combat, lib, weapons
	)
	check(
		(
			Combat.vector(state.actors[10].position).is_equal_approx(
				before + Combat.vector(definition.groups[8].velocity) * 2
			)
			and state.actors[3].position == original.actors[3].position
			and pilot.combat.projectiles.is_empty()
		),
		"Cargo moves at its imported velocity while cruiser and dormant guns stay fixed"
	)
	var legacy := pilot.capture()
	legacy.schema = 6
	legacy.active_job.target = 10
	legacy.active_job.actors[3].hp = 0
	legacy.active_job.kills = 1
	var upgraded := Session.new()
	upgraded.configure(lib)
	check(
		(
			upgraded.restore(JSON.parse_string(JSON.stringify(legacy)))
			and upgraded.active_job.actors[3].hp == lib.group_initial_hull(definition.groups[1])
			and upgraded.active_job.kills == 0
			and upgraded.active_job.target == 9
			and upgraded.active_job.elapsed_ms == pilot.active_job.elapsed_ms
		),
		"Previous convoy saves restore the non-participating hull without resetting mission time or progress"
	)
	legacy.schema = 5
	legacy.erase("progression")
	legacy.active_job.erase("rank")
	check(
		(
			upgraded.restore(JSON.parse_string(JSON.stringify(legacy)))
			and upgraded.active_job.actors[3].hp == lib.group_initial_hull(definition.groups[1])
			and upgraded.active_job.target == 9
			and upgraded.progression.legacy_through == 6
		),
		"Older projectile-schema saves also receive convoy repair before rank migration"
	)
	legacy.active_job.kills = 8
	check(not upgraded.restore(legacy), "Legacy convoy migration rejects forged casualty counts")
	var turret: Dictionary = state.actors[4]
	var mount := Combat.vector(turret.position)
	var target := mount + Vector3(0, 0, -180)
	# A friendly NPC can wake the gun while the player is far outside activation range.
	state.actors[10].position = Combat.packed(target)
	Session.Encounters.advance(
		definition, state, .01, Vector3(0, 0, 20000), Vector3.ZERO, pilot.combat, lib, weapons
	)
	check(
		(
			turret.awake
			and state.actors[3].awake
			and not Session.Mission.actor_active(definition, state, state.actors[3])
		),
		"Cargo proximity wakes the guns while the cruiser remains a non-participating hull"
	)
	for tick in 180:
		Session.Encounters.advance_turret(
			definition.groups[2],
			turret,
			4,
			[{"id": 10, "team": "ally", "position": target, "velocity": Vector3.ZERO}],
			1.0 / 60,
			pilot.combat,
			lib,
			weapons
		)
		if turret.shots > 0:
			break
	check(
		turret.shots == 1 and Combat.vector(turret.position) == mount,
		"Native turret tracks and fires without translating its mount"
	)
	check(
		Combat.valid(pilot.combat, lib, weapons),
		"Turret projectiles have valid source ballistics and enemy ownership"
	)
	check(
		pilot.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Turret activation, aim, shot count and projectile survive JSON save validation"
	)
	var invalid := pilot.capture()
	invalid.active_job.actors[4].heading = [0, 0, 0]
	check(not pilot.restore(invalid), "Reject a turret save with an invalid aim direction")
	# Camera selection commits the first active fighter, rather than following a changing search result.
	state = original.duplicate(true)
	state.actors[1].awake = true
	state.radio = {"shown": [0, 1], "current": 1, "remaining": 3.0}
	Session.Mission.evaluate(definition, state)
	var directives := Session.Mission.Sequence.directives(definition, state)
	check(
		directives.locked and directives.focus.actor == 1,
		"Enemy announcement captures input and focuses the first active fighter"
	)
	Session.Mission.damage(definition, state, 1, float(state.actors[1].hp))
	state.actors[0].awake = true
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(
		(
			Session.Mission.valid(definition, restored, 6, pilot.station_id, lib)
			and Session.Mission.Sequence.directives(definition, restored).focus.actor == 1
		),
		"Camera choice survives target death and JSON reload without selecting another fighter"
	)
	restored.radio.current = -1
	restored.radio.remaining = 0
	Session.Mission.evaluate(definition, restored)
	check(
		(
			not Session.Mission.Sequence.directives(definition, restored).locked
			and restored.sequence_cursor == 2
		),
		"Finishing the source announcement releases camera and controls"
	)
	var bad_sequence := definition.duplicate(true)
	bad_sequence.sequence[0].actions.append(bad_sequence.sequence[0].actions[1].duplicate(true))
	check(
		not Session.Mission.Sequence.valid_definition(bad_sequence),
		"Reject ambiguous multiple camera selections in one milestone"
	)
	var bad_choice := restored.duplicate(true)
	bad_choice.sequence_choices["0"] = 10
	check(
		not Session.Mission.valid(definition, bad_choice, 6, pilot.station_id, lib),
		"Camera save cannot select a cargo ship outside its imported actor range"
	)
	# The last timed announcement must remain eligible after survival becomes ready.
	restored.radio = {"shown": [0, 1, 2, 3], "current": -1, "remaining": 0.0}
	restored.elapsed_ms = float(definition.success.duration_ms)
	Session.Mission.advance(definition, restored, .001, lib)
	check(
		restored.ready and not Session.Mission.Radio.finished(definition, restored),
		"Timed survival waits for the closing announcement at its completion boundary"
	)
	Session.Mission.Radio.advance(definition, restored, .01, lib)
	check(
		restored.radio.current == 4,
		"Closing timer announcement starts even though the survival objective is ready"
	)
	for tick in 2000:
		Session.Mission.Radio.advance(definition, restored, .02, lib)
		if Session.Mission.Radio.finished(definition, restored):
			break
	check(
		restored.radio.shown.size() == 6 and Session.Mission.Radio.finished(definition, restored),
		"Both final convoy transmissions finish before arrival"
	)
	pilot.active_job = original.duplicate(true)
	pilot.combat = Combat.create()
	var credits: int = pilot.credits
	for index in range(10, 15):
		Session.Mission.damage(
			definition, pilot.active_job, index, pilot.active_job.actors[index].hp
		)
	check(
		(
			pilot.active_job.failed
			and not pilot.finish_mission()
			and not lib.text(definition.failure_text).is_empty()
		),
		"Loss of all cargo fails the real convoy and resolves its imported failure message"
	)
	pilot.retry_mission()
	check(
		pilot.chapter == 6 and pilot.credits == credits and pilot.depart(),
		"Convoy retry preserves chapter and credits and creates a fresh encounter"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {"aim_assist": false})
	flight.set_physics_process(false)
	flight.throttle = 0
	var marker: Vector3 = flight.waypoint
	flight.step(.5)
	check(
		flight.waypoint.is_equal_approx(marker + Combat.vector(definition.groups[8].velocity) * .5),
		"Flight marker follows the moving convoy every simulation step"
	)
	check(
		(
			flight
			. actors
			. filter(func(actor): return actor.index == 10)[0]
			. node
			. position
			. is_equal_approx(Combat.vector(pilot.active_job.actors[10].position))
		),
		"Cargo presentation follows authoritative transit state"
	)
	# Fire through the cruiser's outer upper wing, outside its central body.
	var capital: Dictionary = pilot.active_job.actors[3]
	capital.awake = true
	definition.groups[1].combat_active = true
	flight.spawn_targets()
	var wing: Dictionary = definition.groups[1].collisions[1]
	var aim := Combat.vector(capital.position) + Session.Mission.point(wing.offset)
	aim.x += float(wing.size[0]) * .02 * .4
	flight.ship.position = aim + Vector3(0, 0, 200)
	flight.ship.look_at(aim)
	var hull: float = capital.hp
	flight.fire()
	flight.advance_projectiles(.5)
	check(
		capital.hp == hull - float(lib.weapon_ballistics(pilot.weapon_id).damage),
		"Projectile hits the cruiser's offset wing box and applies damage once"
	)
	definition.groups[1].combat_active = false
	# A gun shot crosses the cargo's old and new transforms in one swept update.
	pilot.combat = Combat.create()
	flight.weapon_timers = pilot.combat.cooldowns
	var cargo: Dictionary = pilot.active_job.actors[13]
	var cargo_hull: float = cargo.hp
	var origin := Combat.vector(cargo.position) + Vector3(0, 0, 100)
	check(
		Combat.fire(pilot.combat, -5, origin, Vector3.FORWARD, lib, weapons),
		"Launch an enemy shot toward moving cargo"
	)
	flight.previous_actors = Session.Encounters.advance(
		definition,
		pilot.active_job,
		1,
		flight.ship.position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		weapons
	)
	for actor in flight.actors:
		actor.node.position = Combat.vector(actor.state.position)
	flight.advance_projectiles(1)
	check(
		cargo.hp == cargo_hull - float(weapons[-5].damage),
		"Enemy projectile collision accounts for cargo movement and imported rectangular bounds"
	)
	flight.queue_free()
	await process_frame


func drive_convoy_combat(flight) -> void:
	if flight.cinematic_locked() or flight.session.active_job.ready:
		return
	var definition: Dictionary = flight.library.mission_definition(flight.session.chapter)
	var gun: Dictionary = flight.library.weapon_ballistics(flight.session.weapon_id)
	var nearest := INF
	var target := {}
	for actor in flight.actors:
		if (
			not flight.hostile(actor)
			or definition.groups[int(actor.state.group)].get("behavior") != "interceptor"
		):
			continue
		var distance: float = flight.ship.position.distance_to(actor.node.position)
		if distance < nearest:
			nearest = distance
			target = actor
	if not target.is_empty() and nearest < float(gun.speed) * float(gun.lifetime) * .8:
		flight.auto_pilot = false
		# Keep source cruise during attack passes. The old fractional throttle
		# was tuned for prototype speed and left the pilot nearly stationary
		# beside the cruiser's guns after movement units were corrected.
		flight.throttle = 1.0
		var aim: Vector3 = (
			target.node.position
			+ (
				Combat.vector(target.state.destruction.velocity)
				* nearest
				/ float(gun.speed)
			)
		)
		if aim.distance_to(flight.ship.position) > 1:
			flight.ship.look_at(aim, Vector3.UP)
		flight.fire()
	else:
		flight.auto_pilot = target.is_empty()
		if not target.is_empty():
			flight.throttle = 1.0
			if target.node.position.distance_to(flight.ship.position) > 1:
				flight.ship.look_at(target.node.position, Vector3.UP)


func check_convoy_flight(lib, campaign):
	check(
		campaign.chapter == 6 and campaign.depart(),
		"Seventh mission follows the six preceding played chapters"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false})
	flight.set_physics_process(false)
	var saved: Array[int] = []
	for tick in 18000:
		drive_convoy_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		var stage := int(campaign.active_job.sequence_cursor)
		if stage == 2 and campaign.active_job.elapsed_ms > 140000:
			stage = 3
		if stage > 0 and not saved.has(stage):
			saved.append(stage)
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var checkpoint: Dictionary = campaign.capture()
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(checkpoint)))
			check(
				success, "Restore convoy at checkpoint %d with moving cargo, guns and radio" % stage
			)
			if success:
				check(
					same_saved_value(restored.active_job, campaign.active_job),
					"Convoy checkpoint %d preserves every actor and committed camera choice" % stage
				)
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	var survivors := 0
	var shots := 0
	for actor in campaign.active_job.actors:
		if not Session.Mission.enemy(lib.mission_definition(6), actor) and actor.hp > 0:
			survivors += 1
		if lib.mission_definition(6).groups[int(actor.group)].get("behavior") == "turret":
			shots += int(actor.shots)
	check(
		(
			saved == [1, 2, 3]
			and campaign.active_job.ready
			and not campaign.active_job.failed
			and survivors > 0
		),
		"Actual convoy combat survives the imported duration through three save/reload checkpoints"
	)
	check(
		shots > 0 and campaign.hull > 0 and campaign.active_job.radio.shown.size() == 6,
		"Cruiser guns fire during real play and the pilot hears every convoy transmission"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 7
			and campaign.station_id == lib.chapter_destination(6)
			and campaign.credits == credits + int(lib.content.chapters[6].reward)
		),
		"Convoy survival arrives at the imported destination and grants its original reward once"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Eighth chapter becomes available without unlocking exploration"
	)
	flight.queue_free()
	await process_frame
	return campaign


func same_saved_value(left: Variant, right: Variant) -> bool:
	if Combat.number(left) and Combat.number(right):
		return absf(float(left) - float(right)) < 0.0000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key in left:
			if not right.has(key) or not same_saved_value(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index in left.size():
			if not same_saved_value(left[index], right[index]):
				return false
		return true
	return left == right


func check_cruiser_data(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index cruiser-attack content")
	var bounds := reader.campaign_boundaries(13)
	var definition: Dictionary = lib.mission_definition(7)
	check(
		(
			lib.mission_playable(7)
			and definition.groups.size() == 10
			and definition.enemy_goal == 9
			and definition.radio.size() == 3
			and definition.route.is_empty()
		),
		"Eighth mission imports its nine-kill objective, twelve actors and three radio messages"
	)
	check(
		(
			definition.groups[0].actor == 20
			and Combat.vector(definition.groups[0].center) == Vector3(-10000, 3000, 30000)
			and definition.groups[1].hull == 120
			and definition.groups[7].count == 3
			and definition.groups[8].initial_hp == 9999999
			and definition.groups[9].hull == 40
		),
		"Disabled cruiser, gun health, fighter group and wingmate health preserve source content"
	)
	var arrays := reader.calls_between(
		bounds[7], bounds[8], "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E"
	)
	var ships := reader.calls_between(bounds[7], bounds[8], "__ZN5Level10createShipEiiibP8Waypoint")
	var bodies := reader.calls_between(
		bounds[7], bounds[8], "__ZN17PlayerFixedObject11setPositionEiii"
	)
	var hulls := reader.calls_between(bounds[7], bounds[8], "__ZN6Player15setMaxHitpointsEi")
	var initial := reader.calls_between(bounds[7], bounds[8], "__ZN6Player12setHitpointsEi")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(arrays[0] - 6, 2), 0x200c)
	changed.encode_u16(reader.file_offset(ships[2] + 12, 2), 0x2d30)
	changed.encode_s32(literal_file_offset(reader, bodies[0] - 6), -12000)
	changed.encode_float(literal_file_offset(reader, hulls[0] - 14), 140.0)
	changed.encode_s32(literal_file_offset(reader, initial[0] - 12), -900)
	reader.bytes = changed
	var altered := reader.cruiser_attack_definition(bounds[7], bounds[8], 7)
	check(
		(
			not altered.is_empty()
			and altered.enemy_goal == 11
			and altered.groups[7].count == 5
			and altered.groups[0].center[0] == -12000
			and altered.groups[1].hull == 140
			and altered.groups[8].center[0] == -900
		),
		"Changed source counts, cruiser location, turret hull and wingmate offset change the native mission"
	)
	changed.encode_u16(reader.file_offset(bodies[0] + 6, 2), 0x2101)
	reader.bytes = changed
	var active_hull := reader.cruiser_attack_definition(bounds[7], bounds[8], 7)
	check(
		not active_hull.is_empty() and active_hull.groups[0].combat_active,
		"Combat participation follows the supplied activation flag instead of a hardcoded cruiser exemption"
	)
	var script := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	changed.encode_u16(reader.file_offset(script + 54, 2), reader.u16(script + 52))
	reader.bytes = changed
	reader.error = ""
	check(
		reader.cruiser_attack_definition(bounds[7], bounds[8], 7).is_empty(),
		"Reject a cruiser declaration redirected to an unimplemented event sequence"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 7
	pilot.progression = Session.Progression.create(7)
	pilot.station_id = lib.chapter_destination(6)
	pilot.market_seed = 22
	check(
		pilot.depart() and pilot.active_job.target == 9 and pilot.active_job.actors.size() == 12,
		"Native enemy goal is distinct from the number of living scene actors"
	)
	var state: Dictionary = pilot.active_job
	for index in range(10):
		state.actors[index].position = [100000, 0, 0]
	Session.Encounters.advance(
		definition, state, 1, Vector3(10000, 0, 0), Vector3.ZERO,
		pilot.combat, lib, pilot.actor_weapons()
	)
	check(
		int(state.actors[11].targeting.selected) == 0 and state.actors[11].shots == 0,
		"Routeless wingmate retains source roster fallback outside acquisition range"
	)
	check(
		pilot.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Route-free wingmate movement and enemy goal survive strict JSON restoration"
	)
	state = pilot.active_job
	var invalid := pilot.capture()
	invalid.active_job.target = 10
	check(not pilot.restore(invalid), "Saved kill target cannot override the imported objective")
	var old_goal: int = definition.enemy_goal
	definition.enemy_goal = 100
	check(not lib.valid_missions(), "Reject kill objectives exceeding the source actor count")
	definition.enemy_goal = old_goal
	for index in range(1, 10):
		state.actors[index].awake = true
		Session.Mission.damage(definition, state, index, float(state.actors[index].hp))
	check(
		state.ready and state.kills == 9 and state.actors[0].hp > 0,
		"Imported objective completes with one surviving enemy instead of demanding an invented extra kill"
	)
	check(not pilot.finish_mission(), "Cruiser victory waits for closing radio")
	drain_radio(pilot)
	check(
		pilot.active_job.radio.shown.has(2) and pilot.finish_mission() and pilot.chapter == 8,
		"Original victory transmission follows the imported kill goal and allows arrival"
	)


func drive_cruiser_combat(flight) -> void:
	if flight.cinematic_locked() or flight.session.active_job.ready:
		return
	var gun: Dictionary = flight.library.weapon_ballistics(flight.session.weapon_id)
	var nearest := INF
	var target := {}
	for actor in flight.actors:
		if not flight.hostile(actor):
			continue
		var distance: float = flight.ship.position.distance_to(actor.node.position)
		if distance < nearest:
			nearest = distance
			target = actor
	flight.auto_pilot = false
	if not target.is_empty() and nearest < float(gun.speed) * float(gun.lifetime) * .8:
		flight.throttle = 1.0 if target.state.get("mine", {}).get("phase") == "dormant" else 0.0
		var motion: Dictionary = (
			flight
			. library
			. mission_definition(flight.session.chapter)
			. groups[int(target.state.group)]
			. get("motion", {})
		)
		var aim: Vector3 = (
			target.node.position
			+ (
				Combat.vector(target.state.get("heading", [0, 0, 0]))
				* float(motion.get("speed", 0))
				* nearest
				/ float(gun.speed)
			)
		)
		if aim.distance_to(flight.ship.position) > 1:
			flight.ship.look_at(aim, Vector3.UP)
		flight.fire()
	else:
		flight.throttle = .6
		var aim: Vector3 = (
			target.node.position if not target.is_empty() else flight.navigation_target()
		)
		if aim.distance_to(flight.ship.position) > 1:
			flight.ship.look_at(aim, Vector3.UP)


func check_cruiser_flight(lib, campaign):
	check(
		campaign.chapter == 7 and campaign.depart(),
		"Cruiser attack follows the seven preceding played missions"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false})
	flight.set_physics_process(false)
	var saved := false
	for tick in 24000:
		drive_cruiser_combat(flight)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		if not saved and campaign.active_job.kills >= 4:
			saved = true
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success and same_saved_value(restored.active_job, campaign.active_job),
				"Reload the actual cruiser battle with wingmates, turret fire and objective progress intact"
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	check(
		(
			saved
			and campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.kills == int(lib.mission_definition(7).enemy_goal)
		),
		"Native flight and weapon simulation wins the eighth mission at its supplied kill target"
	)
	check(
		(
			(
				campaign.active_job.actors[0].hp
				== lib.group_initial_hull(lib.mission_definition(7).groups[0])
			)
			and campaign.active_job.actors.slice(1, 7).all(func(actor): return actor.hp == 0)
		),
		"All six gun turrets are eliminated while the cruiser hull remains intact for boarding"
	)
	check(
		campaign.active_job.actors[10].shots > 0 and campaign.active_job.radio.shown.size() == 3,
		"Wingmates participate in actual combat and all cruiser mission radio finishes"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 8
			and campaign.station_id == lib.chapter_destination(7)
			and campaign.credits == credits + int(lib.content.chapters[7].reward)
		),
		"Eighth mission grants its source reward once at the imported station"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Ninth chapter becomes available without pretending the campaign is complete"
	)
	flight.queue_free()
	await process_frame
	return campaign


func check_rescue_data(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index cargo rescue source")
	var bounds := reader.campaign_boundaries(13)
	var definition: Dictionary = lib.mission_definition(8)
	check(
		(
			definition.route.is_empty()
			and definition.groups.size() == 6
			and definition.groups[0].count == 6
			and definition.groups[0].actor == 4
			and definition.groups[5].actor == 15
			and definition.radio.size() == 5
			and definition.sequence.size() == 4
		),
		"Ninth mission imports attackers, cargo, escort and radio milestones"
	)
	check(
		(
			definition.groups[1].hull == 65
			and definition.groups[5].initial_hp == 9999999
			and definition.groups[5].route.size() == 3
			and definition.failure.conditions.size() == 4
			and definition.failure_text == 402
		),
		"Cargo losses exclude the separately routed escort"
	)
	var enemy: Dictionary = definition.groups[0]
	var ordinary := enemy.duplicate(true)
	ordinary.hull_rule.erase("post_offset")
	ordinary.hull_rule.erase("post_factor")
	check(
		lib.group_hull(enemy) == lib.group_hull(ordinary) - 10,
		"Mission health adjustment follows the rank-scaled factory result"
	)
	var ships := reader.calls_between(bounds[8], bounds[9], "__ZN5Level10createShipEiiibP8Waypoint")
	var hulls := reader.calls_between(bounds[8], bounds[9], "__ZN6Player15setMaxHitpointsEi")
	var positions := reader.calls_between(
		bounds[8], bounds[9], "__ZN17PlayerFixedObject11setPositionEiii"
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(ships[0] - 6, 2), 0x2301)
	changed.encode_u16(reader.file_offset(hulls[0] - 54, 2), 0x3814)
	changed.encode_float(literal_file_offset(reader, hulls[1] - 14), 75.0)
	changed.encode_s32(literal_file_offset(reader, positions[0] - 28), -4500)
	var pointer := reader.literal(bounds[8], 3)
	changed.encode_s32(reader.file_offset(pointer + 8, 4), 110000)
	reader.bytes = changed
	var altered := reader.cargo_rescue_definition(bounds[8], bounds[9], 8)
	check(
		(
			not altered.is_empty()
			and altered.groups[0].actor == 1
			and altered.groups[0].hull_rule.post_offset == -20
			and altered.groups[0].positions[0][2] == 110000
			and altered.groups[1].hull == 75
			and altered.groups[1].center[0] == -4500
			and altered.groups[5].route[0][2] == 110000
		),
		"Supplied actor, route, cargo health, placement and hull adjustment changes reach native content"
	)
	var finish := reader.symbol_address("__ZN5MGame11finishLevelEv")
	var rewards := reader.calls_between(
		finish, reader.symbol_end(finish), "__ZN7Mission9getRewardEv"
	)
	changed.encode_u16(reader.file_offset(rewards[0] + 6, 2), 0x3902)
	reader.bytes = changed
	var changed_reward := reader.cargo_rescue_definition(bounds[8], bounds[9], 8)
	check(
		not changed_reward.is_empty() and changed_reward.reward_rule.offset == -2,
		"Payout multiplier follows the supplied survivor-count adjustment"
	)
	changed.encode_u16(reader.file_offset(ships[0] - 8, 2), 0x2201)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.cargo_rescue_definition(bounds[8], bounds[9], 8).is_empty(),
		"Reject an unsupported rescue actor class"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 8
	pilot.progression = Session.Progression.create(8)
	pilot.station_id = lib.chapter_destination(7)
	check(pilot.depart() and pilot.active_job.actors.size() == 11, "Create ninth native mission")
	var state: Dictionary = pilot.active_job
	for index in range(6, 9):
		Session.Mission.damage(definition, state, index, 10000000)
	check(
		(
			not state.failed
			and state.actors[9].hp > 0
			and pilot.mission_reward() == int(lib.content.chapters[8].reward)
		),
		"One surviving cargo ship prevents total-loss failure"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(
		(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and restored.mission_reward() == pilot.mission_reward()
		),
		"Cargo losses and escort route survive save reload"
	)
	Session.Mission.damage(definition, state, 9, 10000000)
	check(not state.failed, "Last cargo hull loss waits for destruction before failure")
	finish_wrecks_fixture(definition,state,lib)
	check(
		(
			state.failed
			and state.actors[10].hp > 0
			and pilot.chapter == 8
			and not pilot.finish_mission()
		),
		"Losing all four cargo ships fails even while the escort survives"
	)
	var credits: int = pilot.credits
	pilot.retry_mission()
	check(
		(
			pilot.depart()
			and pilot.credits == credits
			and pilot.active_job.actors.slice(6, 10).all(func(actor): return actor.hp == 65)
		),
		"Cargo rescue retry restores cargo without paying or advancing"
	)


func make_campaign_purchase_space(campaign, offer: int) -> int:
	# Recovery fills the hold during earlier missions. Buy only after selling
	# actual recovered cargo through the station market, without changing rank.
	if campaign.cargo_used() < campaign.cargo_capacity():
		return 0
	check(not campaign.buy_offer(offer) and campaign.error == "The cargo hold is full.", "Recovered campaign cargo correctly prevents buying into a full hold")
	var used: int = campaign.cargo_used()
	var credits: int = campaign.credits
	check(not campaign.cargo.is_empty() and campaign.sell_cargo(int(campaign.cargo.keys()[0])) and campaign.cargo_used() == used - 1, "Sell one recovered cargo unit through the station market to make room")
	return campaign.credits - credits


func check_rescue_flight(lib, campaign):
	make_campaign_purchase_space(campaign, offer_index(campaign, "equipment", 22))
	check(
		(
			campaign.buy_offer(offer_index(campaign, "equipment", 22))
			and campaign.fit_equipment(campaign.loadout.hold.size() - 1)
		),
		"Spend earned campaign money on the source station weapon offer: " + campaign.error
	)
	campaign.cycle_weapon()
	check(campaign.chapter == 8 and campaign.depart(), "Rescue follows eight played missions")
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true})
	flight.set_physics_process(false)
	var reloaded: Array = []
	for tick in 48000:
		drive_cruiser_combat(flight)
		# Pursue moving attackers at source cruise. Holding position worked only
		# with the prototype's excessive approach speed and leaves cargo behind.
		if not flight.cinematic_locked() and not campaign.active_job.ready:
			flight.throttle = 1.0
		flight.controls.axes[JOY_AXIS_LEFT_X] = (
			1.0 if fmod(float(campaign.active_job.elapsed_ms), 2200.0) < 1100.0 else -1.0
		)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		var cursor := int(campaign.active_job.sequence_cursor)
		if cursor in [1, 3] and not reloaded.has(cursor):
			reloaded.append(cursor)
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success and same_saved_value(restored.active_job, campaign.active_job),
				"Restore rescue cinematic %d with its selected actor and moving cargo" % cursor
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	if not campaign.active_job.ready:
		printerr(
			"Rescue flight incomplete: hull=",
			campaign.hull,
			" actors=",
			campaign.active_job.actors,
			" radio=",
			campaign.active_job.radio,
			" cursor=",
			campaign.active_job.sequence_cursor,
			" elapsed=",
			campaign.active_job.elapsed_ms,
			" failure=",
			campaign.active_job.failed
		)
	check(
		(
			campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.kills == 6
			and reloaded.size() == 2
		),
		"Native weapons win the ninth mission through both cinematic reloads"
	)
	check(
		(
			campaign.active_job.actors.slice(6, 10).any(func(actor): return actor.hp > 0)
			and campaign.active_job.actors[10].shots > 0
			and campaign.active_job.actors[10].route_stage > 0
			and campaign.active_job.radio.shown.size() == 5
		),
		"Cargo survives, escort fights along its route, and all five radio messages finish"
	)
	var cargo_survivors: int = (
		campaign.active_job.actors.slice(6, 10).filter(func(actor): return actor.hp > 0).size()
	)
	var payout: int = campaign.mission_reward()
	check(
		payout == cargo_survivors * int(lib.content.chapters[8].reward),
		"Actual convoy survivors determine the final payout"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 9
			and campaign.station_id == lib.chapter_destination(8)
			and campaign.credits == credits + payout
		),
		"Ninth mission pays the imported reward at its source destination"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Tenth mission becomes available without granting finale completion"
	)
	flight.queue_free()
	await process_frame
	return campaign


func check_strike_data(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index fleet strike source")
	var bounds := reader.campaign_boundaries(13)
	var definition: Dictionary = lib.mission_definition(9)
	check(
		(
			definition.groups.size() == 12
			and definition.route.is_empty()
			and definition.get("sequence", []).is_empty()
			and definition.enemy_goal == 9
			and definition.radio.size() == 8
		),
		"Tenth mission declares nine combat targets, four allies and eight radio cues"
	)
	check(
		(
			not definition.groups[0].combat_active
			and definition.groups[1].hull == 120
			and definition.groups[7].hull_rule.post_offset == 20
			and definition.groups[8].initial_hp == 9999999
			and definition.groups[11].actor == 2
			and definition.groups[11].collisions.size() == 3
		),
		"Fleet strike keeps the disabled cruiser, standard turret hull, stronger fighters and allied frigate"
	)
	var arrays := reader.calls_between(
		bounds[9], bounds[10], "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E"
	)
	var hulls := reader.calls_between(bounds[9], bounds[10], "__ZN6Player15setMaxHitpointsEi")
	var positions := reader.calls_between(
		bounds[9], bounds[10], "__ZN17PlayerFixedObject11setPositionEiii"
	)
	var turret := reader.symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	var factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var changed := source.duplicate()
	changed.encode_s32(literal_file_offset(reader, positions[0] - 16), 12000)
	changed.encode_u16(reader.file_offset(hulls[0] - 56, 2), 0x301e)
	changed.encode_u16(reader.file_offset(turret + 112, 2), 0x23a0)
	changed.encode_s32(literal_file_offset(reader, factory + 0x412 - 34), 2000)
	reader.bytes = changed
	var altered := reader.fleet_strike_definition(bounds[9], bounds[10], 9)
	check(
		(
			not altered.is_empty()
			and altered.groups[0].center[0] == 12000
			and altered.groups[7].hull_rule.post_offset == 30
			and altered.groups[1].hull == 160
			and altered.groups[11].collisions[0].offset[1] == 2000
		),
		"Changed source placement, health and frigate geometry affect the imported battle"
	)
	changed.encode_u16(reader.file_offset(arrays[0] - 2, 2), 0x200b)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.fleet_strike_definition(bounds[9], bounds[10], 9).is_empty(),
		"Reject inconsistent fleet actor ranges"
	)
	changed = source.duplicate()
	reader.bytes = source
	var script := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	changed.encode_u16(reader.file_offset(script + 58, 2), reader.u16(script + 62))
	reader.bytes = changed
	reader.error = ""
	check(
		reader.fleet_strike_definition(bounds[9], bounds[10], 9).is_empty(),
		"Reject a fleet battle redirected to an unsupported cinematic sequence"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 9
	pilot.progression = Session.Progression.create(9)
	pilot.station_id = lib.chapter_destination(8)
	check(
		pilot.depart() and pilot.active_job.actors.size() == 14,
		"Native battle instantiates three wingmates and a separate frigate"
	)
	var position: Array = pilot.active_job.actors[13].position.duplicate()
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		1.0,
		Session.Mission.SPAWN_POSITION,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		(
			pilot.active_job.actors[13].position == position
			and not pilot.active_job.actors[13].has("shots")
		),
		"Allied frigate stays fixed instead of acquiring invented transit or fighter behavior"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Fleet actor state and compound hull survive reload"
	)


func check_strike_flight(lib, campaign):
	check(
		campaign.chapter == 9 and campaign.depart(),
		"Fleet strike follows nine played missions and retains the purchased weapon"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true})
	flight.set_physics_process(false)
	var restored_battle := false
	for tick in 24000:
		drive_cruiser_combat(flight)
		flight.controls.axes[JOY_AXIS_LEFT_X] = (
			1.0 if fmod(float(campaign.active_job.elapsed_ms), 2200.0) < 1100.0 else -1.0
		)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		if not restored_battle and campaign.active_job.kills >= 4:
			restored_battle = true
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success and same_saved_value(restored.active_job, campaign.active_job),
				"Restore the tenth battle with its actual casualties, weapon shots and wingmates"
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	check(
		(
			restored_battle
			and campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.kills == 9
		),
		"Native combat completes the tenth mission after a battle reload"
	)
	check(
		(
			campaign.active_job.actors.slice(1, 10).all(func(actor): return actor.hp == 0)
			and (
				campaign.active_job.actors[0].hp
				== lib.group_initial_hull(lib.mission_definition(9).groups[0])
			)
			and campaign.active_job.radio.shown.size() == 8
		),
		"All cruiser defenses die, disabled hull remains intact, and eight radio messages finish"
	)
	check(
		campaign.active_job.actors.slice(10, 13).any(func(actor): return actor.shots > 0),
		"Wingmates take part in actual fleet combat"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 10
			and campaign.station_id == lib.chapter_destination(9)
			and campaign.credits == credits + int(lib.content.chapters[9].reward)
		),
		"Fleet strike pays the supplied reward once at the source destination"
	)
	check(
		(
			campaign.progression.legacy_through == 0
			and campaign.progression.rewards.size() == 10
			and campaign.progression.rewards[8] == 16000
			and campaign.earned_worth() == 50900
			and campaign.rank() == 5
		),
		"Ten played missions retain actual cargo payout and reach rank five despite outfitting spending"
	)
	var settled := Session.new()
	settled.configure(lib)
	check(
		(
			settled.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			and settled.rank() == 5
			and settled.earned_worth() == 50900
		),
		"Actual ten-mission earned worth and rank survive save/reload"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Eleventh mission unlocks without duplicate payment or premature exploration"
	)
	flight.queue_free()
	await process_frame

	return campaign


func check_flight_ui(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index flight artwork declarations")
	var ctor := reader.symbol_address("__ZN3HudC2Ev")
	var draw := reader.symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var registry := reader.symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var bindings: Dictionary = lib.content.flight_ui.buttons
	for name in ["missiles", "weapon", "pause", "boost"]:
		for state in ["normal", "pressed"]:
			var texture: Texture2D = lib.ui_image(bindings[name][state])
			check(
				texture != null and texture.get_width() > 0 and texture.get_height() > 0,
				"Supplied flight artwork loads: " + name + " " + state
			)
	check(
		bindings.missiles.normal.region == 103 and bindings.weapon.normal.region == 111,
		"Stack and split resource records recover the source control regions"
	)
	var field := ctor + 0xc8
	var data_address := ((field + 4) & ~3) + (reader.u16(field) & 255) * 4
	reader.bytes.encode_u32(reader.file_offset(data_address, 4), reader.literal(ctor + 0xb0, 1))
	var changed := reader.flight_presentation()
	check(
		(
			reader.error.is_empty()
			and same_saved_value(changed.buttons.boost.pressed, bindings.pause.pressed)
		),
		"Changing the supplied boost image association changes the imported artwork"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(registry + 0x2676, 2), 0x2364)
	reader.bytes.encode_u16(reader.file_offset(registry + 0x2868, 2), 0x236d)
	changed = reader.flight_presentation()
	check(
		(
			changed.buttons.missiles.normal.region == 100
			and changed.buttons.weapon.normal.region == 109
		),
		"Temporary and split record atlas regions are read from the supplied file"
	)
	for address in [ctor + 0xcc, draw + 0x10a8, registry + 0x2688, registry + 0x2870]:
		reader.bytes = source.duplicate()
		reader.error = ""
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0)
		check(
			reader.flight_presentation().is_empty() and not reader.error.is_empty(),
			"Unknown flight artwork declaration is rejected at %x" % address
		)
	var original: Dictionary = lib.content.flight_ui
	var bad_region: Dictionary = original.duplicate(true)
	bad_region.buttons.boost.normal.region = -1
	var missing_texture: Dictionary = original.duplicate(true)
	missing_texture.buttons.pause.pressed.erase("texture")
	for invalid in [{}, {"buttons": {}}, bad_region, missing_texture]:
		lib.content.flight_ui = invalid
		check(not lib.valid_flight_ui(), "Malformed or out-of-range flight artwork is rejected")
	lib.content.flight_ui = original
	lib.error = ""
	check(lib.valid_flight_ui(), "Flight artwork remains valid after mutation checks")


func check_radio_ui_data(source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index radio presentation source")
	var update := reader.symbol_address("__ZN5Radio6updateElP9PlayerEgob")
	var portraits := reader.symbol_address("__ZL9img_chars")
	var field := update + 0x186
	var literal_address := ((field + 4) & ~3) + (reader.u16(field) & 255) * 4
	reader.bytes.encode_u32(reader.file_offset(literal_address, 4), 1200)
	var first := reader.u32(portraits)
	reader.bytes.encode_u32(reader.file_offset(portraits, 4), reader.u32(portraits + 4))
	var changed := reader.radio_presentation()
	check(
		changed.line_ms == 1200 and changed.portraits[0] == changed.portraits[1],
		"Changed IPA reading time and speaker portrait are recovered without native overrides"
	)
	reader.bytes.encode_u32(reader.file_offset(portraits, 4), first)
	reader.bytes.encode_u16(reader.file_offset(update + 0x18e, 2), 0)
	reader.error = ""
	check(
		reader.radio_presentation().is_empty() and not reader.error.is_empty(),
		"Unknown radio timing layout is rejected"
	)

	reader.bytes = source.duplicate()
	reader.error = ""
	var draw := reader.symbol_address("__ZN5Radio4drawExP9PlayerEgob")
	var panel := reader.symbol_address("__ZN6Layout16drawRoundEdgeBoxEiiiib")
	var reload := reader.symbol_address("__ZN6Layout6reloadEv")
	reader.bytes.encode_u16(reader.file_offset(draw + 0x4a, 2), 0x211d)
	reader.bytes.encode_u16(reader.file_offset(panel + 0xf0, 2), 0x2110)
	changed = reader.radio_presentation()
	check(
		changed.layout.origin[0] == 29 and changed.panel.fill[0] == 16,
		"Radio position and panel color follow changed supplied declarations"
	)
	for address in [draw + 0x60, draw + 0x8c, draw + 0xa8, reload + 0x412, panel + 0xb8]:
		reader.bytes = source.duplicate()
		reader.error = ""
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0)
		check(
			reader.radio_presentation().is_empty() and not reader.error.is_empty(),
			"Unknown dialogue panel declaration is rejected at %x" % address
		)


func check_radio_presentation(lib) -> void:
	var ui: Dictionary = lib.content.radio_ui
	check(
		same_saved_value(
			ui.layout,
			{
				"origin": [30, 50],
				"width": 420,
				"height_padding": 10,
				"portrait": [35, 55],
				"text": [37, 57]
			}
		),
		"Original radio panel and portrait/text placement imported"
	)
	check(
		(
			same_saved_value(ui.panel.fill, [15, 60, 57, 120])
			and same_saved_value(ui.panel.border, [205, 209, 208, 120])
		),
		"Shared dialogue colors come from the supplied layout"
	)
	var corner: Texture2D = lib.ui_image(ui.panel.corner)
	check(
		corner != null and corner.get_width() > 0,
		"Shared rounded corner uses supplied atlas artwork"
	)
	for key in ["layout", "panel"]:
		for value in [{}, null]:
			var invalid: Dictionary = ui.duplicate(true)
			invalid[key] = value
			lib.content.radio_ui = invalid
			check(not lib.valid_radio_layout(), "Reject missing dialogue " + key)
	for field in ["origin", "portrait", "text"]:
		var invalid: Dictionary = ui.duplicate(true)
		invalid.layout[field] = [-1, 30]
		lib.content.radio_ui = invalid
		check(not lib.valid_radio_layout(), "Reject invalid dialogue " + field)
	for change in ["color", "corner", "width"]:
		var invalid: Dictionary = ui.duplicate(true)
		match change:
			"color":
				invalid.panel.fill = [15, 60, 57, 256]
			"corner":
				invalid.panel.corner.region = 999999
			"width":
				invalid.layout.width = 479
		lib.content.radio_ui = invalid
		check(not lib.valid_radio_layout(), "Reject malformed dialogue " + change)
	lib.content.radio_ui = ui
	lib.error = ""
	check(
		lib.valid_radio_layout(), "Original dialogue panel still valid after cache mutation checks"
	)
	check(
		ui.lead_ms == 2000 and ui.line_ms == 1500 and ui.font_spacing == -3,
		"Original radio lead-in, line duration and font spacing imported"
	)
	check(
		ui.portraits.size() == 32 and lib.radio_glyphs().size() == 160,
		"All source speaker associations and bitmap glyphs imported"
	)
	var cue: Dictionary = lib.mission_definition(1).radio[0]
	check(
		lib.radio_lines(cue).size() == 1 and lib.radio_duration(cue) == 3,
		"Short clearance message has original three-second visible duration"
	)
	var portrait: Texture2D = lib.radio_portrait(int(cue.speaker))
	check(portrait.get_size() == Vector2(63, 63), "Source portrait region uses original dimensions")
	var longest: Dictionary = cue
	for mission in lib.content.missions:
		for message in mission.radio:
			if lib.radio_lines(message).size() > lib.radio_lines(longest).size():
				longest = message
	var wrapped: PackedStringArray = lib.radio_lines(longest)
	check(
		wrapped.size() > 1 and lib.radio_duration(longest) == (wrapped.size() + 1) * 1.5,
		"Long radio text uses actual wrapped lines for reading duration"
	)
	for line in wrapped:
		var width := 0.0
		for index in line.length():
			width += lib.radio_glyph_width(line.unicode_at(index))
		check(width <= 347, "Localized radio line stays inside portrait text column")
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 1
	pilot.progression = Session.Progression.create(1)
	pilot.depart()
	pilot.advance_mission(3)
	pilot.advance_radio(.01)
	check(pilot.radio_cue().is_empty(), "Triggered radio stays hidden during source lead-in")
	pilot.advance_radio(1)
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Save restores a radio lead-in in progress"
	)
	check(
		copy.radio_cue().is_empty() and copy.active_job.radio.delay == 1,
		"Reload keeps exact remaining lead-in without flashing dialogue"
	)
	copy.advance_radio(1)
	check(
		copy.radio_cue() == cue and copy.active_job.radio.remaining == 3,
		"Visibility starts after lead-in with full reading duration"
	)
	copy.advance_radio(2.99)
	check(not copy.radio_cue().is_empty(), "Radio stays visible until its reading deadline")
	copy.advance_radio(.02)
	check(copy.radio_cue().is_empty(), "Expired radio panel clears immediately")
	pilot.advance_radio(1)
	pilot.dismiss_radio()
	check(
		pilot.radio_cue().is_empty() and pilot.active_job.radio.shown == [0],
		"Dismiss consumes only the current transmission"
	)
	pilot.advance_radio(.01)
	check(
		pilot.radio_cue().is_empty() and not pilot.active_job.ready,
		"Dismiss does not trigger objective-bound closing dialogue or complete the mission"
	)
	var saved := copy.capture()
	saved.active_job.radio.delay = -1
	check(not copy.restore(saved), "Reject invalid saved radio lead-in")
	var legacy := pilot.capture()
	legacy.active_job.radio.erase("delay")
	check(copy.restore(legacy), "Older saves without lead-in metadata still load")
	legacy.active_job.radio.current = 0
	legacy.active_job.radio.remaining = 14.0
	check(
		copy.restore(legacy) and copy.active_job.radio.remaining == 3.0,
		"Older long reading timer is capped to the imported cue duration"
	)
	var formats := Formats.new()
	var bytes: PackedByteArray = lib.read(ui.textures[str(int(ui.font.texture))])
	bytes.resize(bytes.size() - 1)
	check(formats.aei(bytes).is_empty(), "Reject truncated source bitmap font data")


func finish_progression_fixture(pilot) -> void:
	for tick in 300:
		if pilot.ready_to_finish():
			return
		pilot.advance_mission(1)
		pilot.advance_radio(1)


func check_progression(lib) -> void:
	var Progress = Session.Progression
	for survivors in range(1, 5):
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.chapter = 8
		# Unit fixture: prior fixed receipts. The main integration separately plays
		# every earlier mission and checks the resulting complete reward history.
		for chapter in 8:
			pilot.progression.rewards.append(int(lib.content.chapters[chapter].reward))
		pilot.station_id = lib.chapter_destination(7)
		check(
			pilot.rank() == 4 and pilot.earned_worth() == 28900 and pilot.depart(),
			"Reward history starts cargo rescue at the source rank"
		)
		# Trigger the source's first-contact dialogue before destroying its speakers.
		for actor in pilot.active_job.actors:
			actor.awake = true
		for tick in 30:
			pilot.advance_mission(1)
			pilot.advance_radio(1)
		for index in range(6, 10 - survivors):
			pilot.damage_actor(index, 10000000)
		for index in 6:
			pilot.damage_actor(index, 10000000)
		finish_progression_fixture(pilot)
		var before: int = pilot.credits
		check(
			pilot.finish_mission() and pilot.credits == before + 4000 * survivors,
			"Actual surviving cargo count controls settlement"
		)
		check(
			(
				pilot.progression.rewards.back() == 4000 * survivors
				and pilot.earned_worth() == 28900 + 4000 * survivors
				and pilot.rank() == 4
			),
			"Cargo payout is recorded exactly in earned worth"
		)
		var saved := pilot.capture()
		var restored := Session.new()
		restored.configure(lib)
		check(
			(
				restored.restore(JSON.parse_string(JSON.stringify(saved)))
				and restored.depart()
				and restored.active_job.rank == 4
			),
			"Next encounter obtains rank from the restored payout history"
		)
		var mismatch := restored.capture()
		mismatch.active_job.rank += 1
		check(
			not restored.restore(mismatch),
			"Reject encounter rank inconsistent with earned-worth history"
		)
		for index in range(1, 10):
			restored.damage_actor(index, 10000000)
		finish_progression_fixture(restored)
		check(
			(
				restored.finish_mission()
				and restored.rank() == (5 if survivors >= 3 else 4)
				and restored.earned_worth() == 34900 + survivors * 4000
			),
			"Tenth payment advances rank only for the appropriate cargo outcomes"
		)
		var history: Dictionary = restored.progression.duplicate(true)
		check(
			not restored.finish_mission() and restored.progression == history,
			"Repeated settlement cannot duplicate earned-worth receipts"
		)
		var after := restored.capture()
		check(
			(
				pilot.restore(JSON.parse_string(JSON.stringify(after)))
				and pilot.progression == history
			),
			"Each cargo outcome retains its exact progression after ten missions"
		)
		var legacy := after.duplicate(true)
		legacy.schema = 7
		legacy.erase("progression")
		check(
			(
				pilot.restore(legacy)
				and pilot.credits == after.credits
				and pilot.chapter == 10
				and pilot.rank() == lib.campaign_level(10)
				and pilot.progression.legacy_through == 10
				and pilot.progression.rewards.is_empty()
			),
			"Old saves preserve their named preview baseline without inventing historical payouts or cash"
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 9
	for chapter in 9:
		pilot.progression.rewards.append(
			int(lib.content.chapters[chapter].reward) * (4 if chapter == 8 else 1)
		)
	pilot.credits = pilot.earned_worth()
	pilot.station_id = lib.chapter_destination(8)
	var worth := pilot.earned_worth()
	var rank := pilot.rank()
	var bought := false
	for index in pilot.market_offers().size():
		var offer: Dictionary = pilot.market_offers()[index]
		if offer.kind == "equipment" and offer.price > 0 and offer.price < pilot.credits:
			bought = pilot.buy_offer(index)
			break
	check(
		bought and pilot.credits < worth and pilot.earned_worth() == worth and pilot.rank() == rank,
		"A real station purchase reduces cash but preserves earned worth and rank"
	)
	check(pilot.depart(), "Start rank-bound fleet save fixture")
	var saved := pilot.capture()
	var legacy := saved.duplicate(true)
	legacy.schema = 7
	legacy.erase("progression")
	legacy.active_job.erase("rank")
	var before := legacy.duplicate(true)
	var restored := Session.new()
	restored.configure(lib)
	check(
		(
			restored.restore(legacy)
			and restored.active_job.rank == lib.campaign_level(9)
			and restored.credits == pilot.credits
			and same_saved_value(legacy, before)
		),
		"In-flight legacy migration adds the old rank without mutating caller data or resetting flight"
	)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(restored.capture()))),
		"Migrated progression becomes a stable schema-eight save"
	)
	var malformed := saved.duplicate(true)
	malformed.progression.rewards[8] = 5000
	check(not restored.restore(malformed), "Reject non-source cargo payout increments")
	malformed = saved.duplicate(true)
	malformed.progression.rewards.append(6000)
	check(
		not restored.restore(malformed),
		"Reject receipt count that advances beyond campaign progress"
	)
	malformed = saved.duplicate(true)
	malformed.erase("progression")
	check(not restored.restore(malformed), "New saves cannot silently fall back to estimated rank")
	var current: Dictionary = Progress.status(pilot.progression, lib)
	var growth: float = lib.content.initial.rank_growth
	lib.content.initial.rank_growth = 2.0
	current = {"worth": 1000, "checkpoint": 1000, "level": 1}
	Progress.apply_reward(current, 1000, lib)
	check(current.level == 1, "Rank threshold is strict, not inclusive")
	Progress.apply_reward(current, 100000, lib)
	check(
		current.level == 2 and current.checkpoint == 102000,
		"A large payment gives one rank and updates its checkpoint once"
	)
	lib.content.initial.rank_growth = growth
	var group: Dictionary = lib.mission_definition(9).groups[7]
	check(
		lib.group_hull(group, 5) > lib.group_hull(group, 4),
		"Native fighter hull uses supplied runtime rank"
	)
	check(
		lib.actor_weapons(9, 8)[-8].damage > lib.actor_weapons(9, 4)[-8].damage,
		"Native enemy gun damage uses supplied runtime rank"
	)
	# A changed supplied reward makes live rank differ from the old static replay
	# before an already implemented encounter, proving the complete runtime path.
	var reward: int = lib.content.chapters[8].reward
	lib.content.chapters[8].reward = 10000
	pilot.configure(lib)
	pilot.chapter = 9
	for chapter in 9:
		pilot.progression.rewards.append(
			int(lib.content.chapters[chapter].reward) * (4 if chapter == 8 else 1)
		)
	pilot.station_id = lib.chapter_destination(8)
	check(
		(
			pilot.rank() == 5
			and lib.campaign_level(9) == 4
			and pilot.depart()
			and pilot.active_job.rank == 5
			and pilot.active_job.actors[7].hp == lib.group_hull(group, 5)
		),
		"Changed IPA payout drives actual mission rank and enemy hull beyond static replay"
	)
	check(
		(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and restored.rank() == 5
			and restored.active_job.actors[7].hp == pilot.active_job.actors[7].hp
		),
		"Save validation accepts actual higher-rank hull derived from changed source payments"
	)
	lib.content.chapters[8].reward = reward


func check_ambush_data(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index nebula assassination source")
	var bounds := reader.campaign_boundaries(13)
	var definition: Dictionary = lib.mission_definition(10)
	check(
		(
			definition.route.size() == 1
			and Combat.vector(definition.route[0]) == Vector3(-6000, 7000, 111000)
			and definition.success.kind == "enemy_destroyed"
			and definition.success.index == 0
			and definition.groups[0].actor == 18
			and definition.groups[0].motion.aim_sine == 1300.0 / 65536.0
			and definition.groups[1].count == 2
			and definition.groups[1].hull_rule.post_offset == 20
			and definition.radio.size() == 5
			and definition.get("sequence", []).is_empty()
		),
		"Eleventh mission imports commander, escorts, target objective and five radio cues"
	)
	check(
		(
			definition.fog.count == 10
			and same_saved_value(definition.fog.region, [2, 514, 186, 184])
			and lib.fog_texture(definition.fog).get_size() == Vector2(186, 184)
		),
		"Nebula uses its supplied cloud count and actual atlas region"
	)
	var objectives := reader.calls_between(bounds[10], bounds[11], "__ZN9ObjectiveC1EiiP5Level")
	var factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var color := reader.symbol_address("__ZN7Globals14getNebulaColorEi")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(objectives[0] - 6, 2), 0x2201)
	changed.encode_s32(literal_file_offset(reader, factory + 0x36a), 1500)
	changed.encode_u32(literal_file_offset(reader, color + 50), 0xffccbb88)
	reader.bytes = changed
	var altered := reader.nebula_ambush_definition(bounds[10], bounds[11], 10)
	check(
		(
			not altered.is_empty()
			and altered.success.index == 1
			and altered.groups[0].motion.aim_sine == 1500.0 / 65536.0
			and altered.fog.palette[0] == 0xffccbb88
		),
		"Source objective, commander aim and nebula color changes reach native content"
	)
	changed.encode_u16(reader.file_offset(objectives[0] - 6, 2), 0x22ff)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.nebula_ambush_definition(bounds[10], bounds[11], 10).is_empty(),
		"Reject assassination targets outside the supplied enemy array"
	)
	var malformed: Dictionary = definition.fog.duplicate(true)
	malformed.count = 100000
	check(not lib.valid_fog(malformed, 1), "Reject unbounded cloud counts")
	malformed = definition.fog.duplicate(true)
	malformed.waypoint = 1
	check(not lib.valid_fog(malformed, 1), "Reject nebula placement beyond the mission route")
	var state := Session.Mission.create(definition, 10, 6, lib, 123)
	for actor in state.actors:
		actor.awake = true
	Session.Mission.reach_waypoint(definition, state)
	check(not state.ready, "Reaching the ambush alone does not complete an assassination")
	Session.Mission.damage(definition, state, 1, 100000)
	Session.Mission.damage(definition, state, 2, 100000)
	check(not state.ready, "Destroying both escorts does not replace killing the marked commander")
	Session.Mission.damage(definition, state, 0, 100000)
	check(not state.ready, "Assassination waits for marked target destruction")
	finish_wrecks_fixture(definition,state,lib)
	check(state.ready, "Commander death completes the designated target objective")
	state = Session.Mission.create(definition, 10, 6, lib, 123)
	state.actors[0].awake = true
	Session.Mission.damage(definition, state, 0, 100000)
	check(not state.ready, "Assassination waits for marked target destruction")
	finish_wrecks_fixture(definition,state,lib)
	check(
		state.ready and state.kills == 1 and state.stage == 0,
		"Assassination can finish with surviving escorts and no invented route requirement"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 10
	pilot.progression = Session.Progression.create(10)
	pilot.station_id = lib.chapter_destination(9)
	var credits: int = pilot.credits
	check(pilot.depart(), "Nebula mission departs from the previous chapter destination")
	pilot.hull = 0
	var refused: bool = not pilot.finish_mission()
	pilot.retry_mission()
	check(
		refused and pilot.chapter == 10 and pilot.credits == credits,
		"Ambush defeat and retry grant no campaign reward"
	)


func nebula_composition(flight) -> Array:
	var result: Array = [flight.nebula.position]
	for cloud in flight.nebula.get_children():
		result.append(
			[cloud.position, cloud.pixel_size, cloud.flip_h, cloud.flip_v, cloud.modulate]
		)
	return result


func check_ambush_flight(lib, campaign):
	check(
		campaign.chapter == 10 and campaign.depart(),
		"Nebula assassination follows ten played missions with earned rank and outfitting"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true})
	flight.set_physics_process(false)
	var clouds := nebula_composition(flight)
	check(
		clouds.size() == 11 and clouds[0] == Vector3(-120, 140, -2220),
		"Native clouds form at the imported ambush waypoint"
	)
	var restored_battle := false
	for tick in 24000:
		drive_cruiser_combat(flight)
		flight.controls.axes[JOY_AXIS_LEFT_X] = (
			1.0 if fmod(float(campaign.active_job.elapsed_ms), 2200.0) < 1100.0 else -1.0
		)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		if (
			not restored_battle
			and not campaign.combat.projectiles.is_empty()
			and campaign.active_job.actors[0].hp > 0
		):
			# Checkpoint during live combat even when the player's approach keeps
			# the enemy from firing before it is destroyed.
			restored_battle = true
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success
				and same_saved_value(restored.active_job, campaign.active_job)
				and same_saved_value(restored.combat, campaign.combat),
				"Ambush actors, live projectiles, objectives and radio survive battle reload"
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true}, true)
				flight.set_physics_process(false)
				check(
					nebula_composition(flight) == clouds,
					"Nebula placement and colors remain stable across mid-flight reload"
				)
		if flight.paused:
			break
	print("AMBUSH RESULT ", {"reloaded":restored_battle,"ready":campaign.active_job.ready,
		"hull":campaign.hull,"target_hp":campaign.active_job.actors[0].hp,
		"enemy_shots":campaign.active_job.actors.map(func(actor):return actor.get("shots",0)),
		"projectile_count":campaign.combat.next_id,"elapsed_ms":campaign.active_job.elapsed_ms})
	check(
		(
			restored_battle
			and campaign.active_job.ready
			and campaign.hull > 0
			and campaign.active_job.actors[0].hp == 0
		),
		"Native controls and weapon fire complete the eleventh mission after reload"
	)
	check(
		campaign.active_job.radio.shown.size() == 5,
		"Assassination radio delivers all five imported messages before arrival"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 11
			and campaign.station_id == lib.chapter_destination(10)
			and campaign.credits == credits + int(lib.content.chapters[10].reward)
			and campaign.progression.rewards.size() == 11
			and campaign.earned_worth() == 55900
		),
		"Ambush pays its source reward once and preserves the actual eleven-mission ledger"
	)
	check(
		(
			not campaign.finish_mission()
			and campaign.mission_available()
			and not campaign.exploration_unlocked()
		),
		"Twelfth unlocks with no duplicate payment or false campaign completion"
	)
	flight.queue_free()
	await process_frame
	return campaign


func check_pursuit_foundation(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index pursuit encounter and radio source")
	var bounds := reader.campaign_boundaries(13)
	var definition := reader.pursuit_encounter_data(bounds[11], bounds[12], 11)
	var messages := reader.radio_definitions(13, 12)
	check(
		not definition.is_empty() and messages.size() == 12 and reader.error.is_empty(),
		"Recover twelfth encounter data independently from its cinematic milestones"
	)
	if definition.is_empty() or messages.size() != 12:
		return
	definition.radio = messages[11]
	check_pursuit_navigation(reader, definition, lib)
	check(
		(
			definition.route.size() == 5
			and definition.escort_route.size() == 4
			and definition.groups[0].count == 20
			and definition.groups[0].actor == 7
			and definition.groups[1].count == 2
			and definition.groups[2].count == 3
			and definition.groups[3].actor == 10
			and definition.groups[3].hull == 700
		),
		"Source pursuit declares twenty mines, five fighters and a reserved commander"
	)
	check(
		(
			Combat.vector(definition.groups[3].center) == Vector3(-6000, 2000, -580000)
			and definition.groups[3].motion.turn_response == 1
			and definition.groups[4].initial_hp == 9999999
			and is_equal_approx(definition.groups[4].motion.wake_half_width, 499.98)
			and definition.scenery[0].waypoint == 4
		),
		"Commander override, protected escort, friendly activation and distant asteroid field import"
	)
	var existing: Array = lib.content.missions
	lib.content.missions = [definition]
	check(
		lib.valid_missions(), "Recovered pursuit actor data and extended radio conditions validate"
	)
	lib.content.missions = existing
	check(not lib.mission_playable(13), "No campaign scenario exists beyond the source finale")
	check(
		(
			definition.radio.size() == 13
			and definition.radio[0].count == 20
			and definition.radio[3].value == 20
			and definition.radio[3].count == 5
			and definition.radio[6].value == 25
			and definition.radio[6].message == 5
			and definition.radio[9].condition == "ally_range_casualty"
		),
		"All thirteen pursuit radio messages retain their ranges and conjunction"
	)
	var state := Session.Mission.create(definition, 11, 6, lib, 42, 5)
	check(
		Session.Mission.valid(definition, state, 11, 6, lib),
		"Sleeping escorts with exact source positions form valid serializable state"
	)
	var Radio = Session.Mission.Radio
	for index in 19:
		clear_mine_fixture(definition, state, index, lib)
	check(
		not Radio.triggered(definition.radio[0], definition, state),
		"Minefield clearance radio waits for every member of its imported range"
	)
	clear_mine_fixture(definition, state, 19, lib)
	check(
		(
			Radio.triggered(definition.radio[0], definition, state)
			and not Radio.triggered(definition.radio[3], definition, state)
		),
		"Clearing mines announces wingmates without skipping the separate fighter group"
	)
	state.actors[25].awake = true
	check(
		not Radio.triggered(definition.radio[6], definition, state),
		"Active commander alone cannot trigger dialogue before the required message"
	)
	state.actors[25].awake = false
	state.radio.shown = [5]
	check(
		not Radio.triggered(definition.radio[6], definition, state),
		"Earlier dialogue alone cannot reveal the dormant commander"
	)
	state.actors[25].awake = true
	check(
		Radio.triggered(definition.radio[6], definition, state),
		"Commander dialogue requires both source conditions"
	)
	state.actors[25].awake = false
	state.radio = Radio.create()
	var combat := Combat.create()
	Session.Encounters.advance(definition, state, .1, Vector3.ZERO, Vector3.ZERO, combat, lib, {})
	check(not state.actors[26].awake, "Distant player leaves allied escorts asleep")
	var near := Combat.vector(state.actors[26].position)
	Session.Encounters.advance(definition, state, .1, near, Vector3.ZERO, combat, lib, {})
	check(
		state.actors[26].awake and Radio.triggered(definition.radio[2], definition, state),
		"Player proximity wakes the allied flight and triggers its imported radio"
	)
	check(
		not Radio.triggered(definition.radio[9], definition, state),
		"Enemy deaths do not trigger the selected friendly casualty message"
	)
	state.actors[27].awake = true
	Session.Mission.damage(definition, state, 27, 10000000)
	check(
		not Radio.triggered(definition.radio[9], definition, state),
		"Another ally's death does not substitute for the story character"
	)
	Session.Mission.damage(definition, state, 26, 10000000)
	check(
		Radio.triggered(definition.radio[9], definition, state),
		"Story casualty radio selects ally zero independently of preceding enemy entries"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 11, 6, lib),
		"Pursuit combat activation and friendly losses survive JSON validation"
	)
	var invalid: Dictionary = definition.duplicate(true)
	invalid.radio[6].message = invalid.radio.size()
	check(not lib.valid_radio(invalid), "Reject missing prerequisite radio messages")
	invalid = definition.duplicate(true)
	invalid.radio[2].count = 5
	check(
		not lib.valid_radio(invalid), "Validate ally ranges against allies, not total combat actors"
	)
	invalid = definition.duplicate(true)
	invalid.radio[6].value = 26
	check(not lib.valid_radio(invalid), "Reject a commander reference past the enemy array")
	var changed := source.duplicate()
	changed.encode_s32(literal_file_offset(reader, bounds[11] + 0x29a), -12345)
	var routes := reader.calls_between(bounds[11], bounds[12], "__ZN5RouteC1EPii")
	var route_address := reader.literal(bounds[11] + 2, 1)
	changed.encode_s32(reader.file_offset(route_address, 4), -9000)
	var hulls := reader.calls_between(bounds[11], bounds[12], "__ZN6Player15setMaxHitpointsEi")
	changed.encode_u16(reader.file_offset(hulls[1] - 10, 2), 0x21c8)
	reader.bytes = changed
	var altered := reader.pursuit_encounter_data(bounds[11], bounds[12], 11)
	check(
		(
			not altered.is_empty()
			and altered.route[0][0] == -9000
			and altered.groups[3].center[0] == -12345
			and altered.groups[3].hull == 800
		),
		"Changed source route, commander position and health reach encounter data"
	)
	reader.bytes = source
	var radio_start := reader.symbol_address("__ZN12RadioMessage9triggeredExP9PlayerEgob")
	var switches := reader.calls_between(radio_start, radio_start + 64, "___switch16")
	var table := switches[0] + 4
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(table + 2 + 9 * 2, 2), reader.u16(table + 2 + 1 * 2))
	reader.bytes = changed
	reader.error = ""
	check(
		not reader.extended_radio_condition(9) and not reader.error.is_empty(),
		"Reject source that changes all-target radio semantics into a single casualty"
	)
	reader.bytes = source
	reader.error = ""
	var radio_first := reader.symbol_address("__ZN5Level19createRadioMessagesEi")
	switches = reader.calls_between(radio_first, radio_first + 256, "___switch32")
	table = switches[0] + 4
	var first := table + reader.u32(table + 4 + 11 * 4)
	var end := table + reader.u32(table + 8 + 11 * 4)
	var ranged := reader.calls_between(first, end, "__ZN12RadioMessageC1Eiiiii")
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(ranged[3] - 16, 2), 0x2304)
	reader.bytes = changed
	messages = reader.radio_definitions(13, 12)
	check(
		messages.size() == 12 and messages[11][6].message == 4,
		"Combined radio prerequisite is read from the IPA rather than a mission constant"
	)

	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(bounds[11] + 0xe6, 2), 0x21ff)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.pursuit_encounter_data(bounds[11], bounds[12], 11).is_empty(),
		"Reject debris references outside the source route before indexing points"
	)
	reader.bytes = source
	reader.error = ""
	var director := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var dispatch := director + 48
	var chapter_base := (reader.u16(director + 40) >> 6) & 7
	var branch := dispatch + reader.u16(dispatch + 2 + (11 - chapter_base) * 2) * 2
	var stages := branch + 8
	var release := stages + reader.u16(stages + 2 + 2 * 2) * 2
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(release + 58, 2), 0x2101)
	reader.bytes = changed
	var navigation := reader.pursuit_navigation(11, definition.route.size())
	check(
		not navigation.is_empty() and navigation.release.action.first == 2,
		"Source route release index changes the native navigation milestone"
	)
	changed.encode_u16(reader.file_offset(release + 58, 2), 0x21ff)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.pursuit_navigation(11, definition.route.size()).is_empty(),
		"Reject route release past the final encounter waypoint"
	)


func check_pursuit_navigation(reader, encounter: Dictionary, lib) -> void:
	var navigation: Dictionary = reader.pursuit_navigation(11, encounter.route.size())
	check(
		(
			not navigation.is_empty()
			and navigation.initial_end == 0
			and navigation.release.when.message == 1
			and navigation.release.action.first == 1
			and navigation.release.action.end == 4
			and navigation.extend.when.message == 4
			and navigation.extend.action.first == 4
			and navigation.extend.action.end == 5
		),
		"Source director removes the initial route, opens the escort leg, then releases the last waypoint"
	)
	if navigation.is_empty():
		return
	var definition := encounter.duplicate(true)
	definition.route_initial_end = navigation.initial_end
	definition.sequence = []
	for milestone in [navigation.release, navigation.extend]:
		definition.sequence.append({"when": milestone.when, "actions": [milestone.action]})
	check(
		Session.Mission.Sequence.valid_definition(definition),
		"Native route milestones validate independently of chapter-specific code"
	)
	var state := Session.Mission.create(definition, 11, 6, lib, 17, 5)
	Session.Mission.reach_waypoint(definition, state)
	check(
		state.stage == 0 and not Session.Mission.route_pending(definition, state),
		"Disabled opening route cannot be advanced by flying through hidden waypoints"
	)
	state.radio.shown = [0, 1]
	state.radio.current = 1
	Session.Mission.advance(definition, state, .1, lib)
	check(
		state.stage == 0 and state.sequence_cursor == 0,
		"Escort route waits for the source message to finish, not merely begin"
	)
	state.radio.current = -1
	Session.Mission.advance(definition, state, .1, lib)
	check(
		(
			state.stage == 1
			and state.sequence_cursor == 1
			and Session.Mission.route_pending(definition, state)
		),
		"Finishing radio releases navigation at the imported first live waypoint"
	)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(
		Session.Mission.valid(definition, saved, 11, 6, lib),
		"A route transition needs no unsaved flags and survives JSON reload"
	)
	saved.stage = 0
	check(
		not Session.Mission.valid(definition, saved, 11, 6, lib),
		"Reject route progress inconsistent with a completed transition"
	)
	for index in 5:
		Session.Mission.reach_waypoint(definition, state)
	check(
		(
			state.stage == 4
			and not Session.Mission.route_pending(definition, state)
			and not Session.Mission.achieved({"kind": "route_finished"}, definition, state)
		),
		"Reaching the escort leg cannot bypass the withheld final waypoint"
	)
	state.radio.shown.append(4)
	state.radio.current = 4
	state.radio.remaining = 1.0
	Session.Mission.advance(definition, state, .1, lib)
	check(
		(
			state.stage == 4
			and state.sequence_cursor == 2
			and Session.Mission.route_pending(definition, state)
		),
		"The supplied later message activates the final route leg"
	)
	Session.Mission.reach_waypoint(definition, state)
	check(
		(
			state.stage == 5
			and Session.Mission.achieved({"kind": "route_finished"}, definition, state)
			and not state.ready
		),
		"Final route completion preserves the independent combat objective"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 11, 6, lib),
		"Final route phase and its message history survive reload"
	)
	var invalid := definition.duplicate(true)
	invalid.sequence[0].actions[0].end = definition.route.size() + 1
	check(
		not Session.Mission.Sequence.valid_definition(invalid),
		"Reject route directives outside supplied waypoint data"
	)
	invalid = definition.duplicate(true)
	invalid.route_initial_end = -1
	check(
		not Session.Mission.Sequence.valid_definition(invalid),
		"Reject negative initial navigation bounds"
	)
	check(
		Session.Mission.Sequence.directives({}, {}).route_end == 0,
		"Exploration without a campaign definition has no route directive"
	)


func drive_pursuit_combat(flight) -> void:
	if flight.cinematic_locked() or flight.session.active_job.ready:
		return
	var definition: Dictionary = flight.library.mission_definition(flight.session.chapter)
	var in_range := false
	var gun: Dictionary = flight.library.weapon_ballistics(flight.session.weapon_id)
	for actor in flight.actors:
		if (
			flight.hostile(actor)
			and actor.state.awake
			and (
				flight.ship.position.distance_to(actor.node.position)
				< float(gun.speed) * float(gun.lifetime) * .8
			)
		):
			in_range = true
			break
	if (
		flight.ship.position.length() < 350
		or (not in_range and Session.Mission.route_pending(definition, flight.session.active_job))
	):
		flight.auto_pilot = false
		flight.throttle = .65
		var aim: Vector3 = flight.navigation_target()
		if aim.distance_to(flight.ship.position) > 1:
			flight.ship.look_at(aim, Vector3.UP)
	else:
		drive_cruiser_combat(flight)


func check_pursuit_flight(lib, campaign):
	check(
		campaign.chapter == 11 and campaign.depart(),
		"Pursuit follows the preceding campaign with the retained loadout"
	)
	var credits: int = campaign.credits
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true})
	flight.set_physics_process(false)
	check(
		flight.dormant_visuals.size() == 10 and flight.actors.size() == 20,
		"Sleeping pursuit ships render without becoming combat targets"
	)
	var saw_escort := false
	var checkpoints: Array = []
	var commander_shots := -1
	for tick in 72000:
		drive_pursuit_combat(flight)
		flight.controls.axes[JOY_AXIS_LEFT_X] = (
			(1.0 if fmod(float(campaign.active_job.elapsed_ms), 2200.0) < 1100.0 else -1.0)
			if flight.ship.position.length() > 400
			else 0.0
		)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		var cursor := int(campaign.active_job.sequence_cursor)
		if cursor == 2 and not saw_escort:
			saw_escort = flight.dormant_visuals.has(26)
		if cursor == 5 and commander_shots < 0:
			commander_shots = int(campaign.active_job.actors[25].shots)
		if cursor in [3, 5, 6, 9] and not checkpoints.has(cursor):
			checkpoints.append(cursor)
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var saved_job: Dictionary = campaign.active_job.duplicate(true)
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success and same_saved_value(restored.active_job, saved_job),
				"Restore pursuit route, combat and camera checkpoint %d" % cursor
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	print(
		"PURSUIT BATTLE elapsed=",
		campaign.active_job.elapsed_ms,
		" hull=",
		campaign.hull,
		" cursor=",
		campaign.active_job.sequence_cursor,
		" checkpoints=",
		checkpoints
	)
	check(saw_escort, "Intro camera has a visible allied model before its proximity activation")
	check(
		campaign.active_job.ready and campaign.hull > 0 and checkpoints.size() == 4,
		"Native combat completes the pursuit and confrontation across four reloads"
	)
	check(
		(
			commander_shots >= 0
			and campaign.active_job.actors[25].shots > commander_shots
			and campaign.active_job.actors[26].hp == 0
		),
		"The confrontation's directed weapon fire kills the scripted ally"
	)
	check(
		(
			campaign.active_job.sequence_cursor == 10
			and campaign.active_job.radio.shown.size() == 13
			and campaign.active_job.kills == 26
			and campaign.active_job.actors[25].hp == 0
		),
		"All thirteen radio cues finish and the source departure removes the final enemy"
	)
	check(
		(
			campaign.finish_mission()
			and campaign.chapter == 12
			and campaign.station_id == lib.chapter_destination(11)
			and campaign.credits == credits + int(lib.content.chapters[11].reward)
		),
		"Pursuit settles its imported reward once at the source destination"
	)
	check(
		(
			campaign.progression.rewards.size() == 12
			and campaign.earned_worth() == 63400
			and campaign.rank() == 5
		),
		"Twelve played missions preserve actual payout history and earned rank"
	)
	var settled := Session.new()
	settled.configure(lib)
	check(
		(
			settled.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			and settled.chapter == 12
			and settled.earned_worth() == campaign.earned_worth()
			and settled.mission_available()
		),
		"Pursuit arrival and ledger survive reload with the finale available"
	)
	check(
		not campaign.finish_mission() and not campaign.exploration_unlocked(),
		"Pursuit completion grants no duplicate payment or premature exploration"
	)
	flight.queue_free()
	await process_frame
	return campaign


func commit_pursuit_event(definition: Dictionary, state: Dictionary, lib) -> void:
	var condition: Dictionary = definition.sequence[int(state.sequence_cursor)].when
	if not state.radio.shown.has(int(condition.message)):
		state.radio.shown.append(int(condition.message))
	state.radio.current = -1 if condition.kind == "message_finished" else int(condition.message)
	state.radio.remaining = 0.0 if state.radio.current == -1 else 1.0
	Session.Mission.advance(definition, state, .01, lib)


func check_pursuit_director(source: PackedByteArray, lib) -> void:
	var definition: Dictionary = lib.mission_definition(11)
	check(
		definition.sequence.size() == 10 and definition.sequence[4].actions[2].distance == 32768,
		"Pursuit imports ten milestones and the correctly scaled forward placement"
	)
	var state := Session.Mission.create(definition, 11, 6, lib, 912, 5)
	for actor in state.actors:
		actor.awake = true
	for index in 25:
		if state.actors[index].has("mine"):
			clear_mine_fixture(definition,state,index,lib)
		else:
			damage_actor_fixture(definition,state,index,lib)
	finish_wrecks_fixture(definition,state,lib)
	for index in 4:
		commit_pursuit_event(definition, state, lib)
	check(
		Combat.vector(state.actors[25].position) == Session.Mission.point(definition.route.back()),
		"The director brings the reserved commander to the final waypoint"
	)
	var directions := Session.Mission.Sequence.directives(definition, state)
	check(
		directions.detached == [27, 28, 29] and is_equal_approx(directions.speeds[26], 50.4),
		"Other escorts detach while the story character follows the faster approach"
	)
	Session.Mission.Frame.turn(state.actors[26], Vector3.RIGHT)
	var origin := Combat.vector(state.actors[26].position)
	commit_pursuit_event(definition, state, lib)
	check(
		(
			Combat.vector(state.actors[25].position).is_equal_approx(origin + Vector3(655.36, 0, 0))
			and state.actors[26].hp == 1
			and state.actors[25].hp == 9999999
		),
		"Confrontation places the commander ahead of the ally's actual heading and applies source hull limits"
	)
	var expected: Vector3 = Combat.vector(state.actors[25].position).lerp(origin, .5)
	commit_pursuit_event(definition, state, lib)
	directions = Session.Mission.Sequence.directives(definition, state)
	check(
		Combat.vector(directions.focus.position).is_equal_approx(expected),
		"Midpoint camera captures the two ships when its event commits"
	)
	state.actors[25].position[0] += 100
	check(
		(
			Combat
			. vector(Session.Mission.Sequence.directives(definition, state).focus.position)
			. is_equal_approx(expected)
		),
		"Locked camera placement persists while its actors move"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 11, 6, lib),
		"Confrontation hull caps, orders and camera snapshot validate after reload"
	)
	var invalid := state.duplicate(true)
	invalid.erase("sequence_positions")
	check(
		not Session.Mission.valid(definition, invalid, 11, 6, lib),
		"Reject missing committed camera snapshots"
	)
	invalid = state.duplicate(true)
	invalid.sequence_positions["0"] = [0, 0, 0]
	check(
		not Session.Mission.valid(definition, invalid, 11, 6, lib),
		"Reject camera snapshots for events that never recorded one"
	)
	commit_pursuit_event(definition, state, lib)
	damage_actor_fixture(definition,state,26,lib)
	commit_pursuit_event(definition, state, lib)
	var previous := Combat.vector(state.actors[25].position)
	var departure_speed := float(state.actors[25].fighter_motion.speed)
	Session.Encounters.advance(
		definition, state, .5, Vector3.ZERO, Vector3.ZERO, Combat.create(), lib, {}
	)
	check(
		is_equal_approx(previous.distance_to(Combat.vector(state.actors[25].position)), departure_speed*.5),
		"The commander keeps its current fighter speed after losing its target"
	)
	var malformed := definition.duplicate(true)
	malformed.sequence[3].actions[-1].value = NAN
	check(
		not Session.Mission.Sequence.valid_definition(malformed), "Reject non-finite scripted speed"
	)
	malformed = definition.duplicate(true)
	malformed.sequence[5].actions.append(malformed.sequence[5].actions[-1].duplicate(true))
	check(
		not Session.Mission.Sequence.valid_definition(malformed),
		"Reject conflicting camera snapshots in one event"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 11
	pilot.progression = Session.Progression.create(11)
	pilot.station_id = lib.chapter_destination(10)
	var cash: int = pilot.credits
	check(pilot.depart(), "Pursuit retry fixture departs")
	pilot.hull = 0
	check(not pilot.finish_mission(), "Defeat cannot settle the pursuit reward")
	pilot.retry_mission()
	check(
		(
			pilot.chapter == 11
			and pilot.docked
			and pilot.credits == cash
			and pilot.progression.rewards.is_empty()
		),
		"Pursuit defeat retries from its beginning without granting money or progress"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index confrontation source for mutation checks")
	var bounds := reader.campaign_boundaries(13)
	var changed := source.duplicate()
	# A supplied speed literal affects the final departure, not a native mission constant.
	var script := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (reader.u16(script + 40) >> 6) & 7
	var branch := table + reader.u16(table + 2 + (11 - base) * 2) * 2
	var parts: Array[int] = []
	for index in reader.u16(branch + 8):
		parts.append(branch + 8 + reader.u16(branch + 10 + index * 2) * 2)
	changed.encode_u16(reader.file_offset(parts[1] + 0x1e, 2), 0x2100)
	reader.bytes = changed
	var changed_freeze := reader.pursuit_definition(bounds[11], bounds[12], 11)
	check(
		not changed_freeze.is_empty() and not changed_freeze.sequence[1].actions[0].value,
		"Player freeze comes from the supplied flag independently of control capture"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(parts[1] + 0x20, 2), 0)
	reader.bytes = changed
	check(
		reader.pursuit_definition(bounds[11], bounds[12], 11).is_empty(),
		"Unknown player freeze declaration is rejected instead of inferring a pause"
	)
	reader.error = ""
	changed = source.duplicate()
	reader.bytes = source
	changed.encode_float(literal_file_offset(reader, parts[8] + 0x1e), 8.0)
	reader.bytes = changed
	var altered := reader.pursuit_definition(bounds[11], bounds[12], 11)
	check(
		not altered.is_empty() and altered.sequence[8].actions[0].value == 160,
		"Source departure speed changes the native director"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(parts[4] + 0x114, 2), 0x685b)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.pursuit_definition(bounds[11], bounds[12], 11).is_empty(),
		"Reject inconsistent story-character references instead of targeting another ally"
	)


func check_finale_foundation(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index supplied finale data")
	var bounds := reader.campaign_boundaries(13)
	var definition := reader.finale_encounter_data(bounds[12], bounds[13], 12)
	var radio := reader.radio_definitions(13, 13)
	check(
		not definition.is_empty() and radio.size() == 13 and reader.error.is_empty(),
		"Recover finale constructor and all source radio records: " + reader.error
	)
	if definition.is_empty() or radio.size() != 13:
		return
	definition.radio = radio[12]
	check(
		definition.route == [[0, 0, 130000]] and definition.route_initial_end == 0,
		"Finale approach route is withheld until its authored milestone"
	)
	check(
		(
			definition.groups.size() == 10
			and definition.groups[0].count == 6
			and definition.groups[1].actor == 10
			and definition.groups[2].count == 2
		),
		"Finale declares six initial enemies, a commander, two wingmates and seven fleet entries"
	)
	check(
		(
			definition.groups[1].hull == 700
			and definition.groups[1].center == [0, 0, 5000000]
			and definition.groups[1].sleeping
			and definition.groups[1].boost_probability == 35
		),
		"Commander reserve placement, hull and boost setting come from source"
	)
	check(
		(
			definition.groups[1].weapon.damage == 5
			and definition.groups[1].weapon.speed == 320
			and definition.groups[1].weapon.pool_capacity == 20
		),
		"Final commander uses its own weaker source weapon, not the earlier duel damage"
	)
	check(
		reader.scripted_fighter_weapon(5, reader.interceptor_combat().weapon).damage == 50,
		"Extending the weapon reader preserves the earlier scripted duel"
	)
	check(
		(
			definition.groups[2].hull == 65
			and definition.groups[3].actor == 2
			and definition.groups[4].actor == 2
			and definition.groups[5].actor == 6
		),
		"Source distinguishes weak wingmates, two frigates and the allied capital ship"
	)
	check(
		(
			definition.groups[3].center == [-2000, 3000, 15000]
			and definition.groups[4].center == [500, -20000, 5000]
			and definition.groups[5].center == [6000, -1000, 20000]
		),
		"Source fleet positions are preserved"
	)
	check(
		(
			definition.groups[5].collisions.size() == 3
			and definition.groups[5].collisions != reader.capital_collision()
		),
		"Allied capital ship uses its own compound collision geometry"
	)
	check(
		(
			definition.groups[6].actor == 3
			and definition.groups[6].hull == 60
			and definition.groups[6].center == [6000, 700, 26061]
			and definition.groups[7].facing == [0, 0, -65536]
		),
		"Terran turrets use the alternate mount, health and facing declarations"
	)
	check(
		(
			definition.radio.size() == 12
			and definition.radio[0].text == 386
			and definition.radio[0].value == 3000
			and definition.radio[11].text == 397
		),
		"All twelve finale transmissions come from supplied message records"
	)
	check(
		(
			definition.radio[4].condition == "enemy_range_active"
			and definition.radio[4].value == 6
			and definition.radio[6].condition == "enemy_range_casualty"
			and definition.radio[6].value == 6
		),
		"Shared compiler initializer fields preserve activation and death conditions"
	)
	check(
		definition.success == {"kind": "message_shown", "message": 11},
		"Finale objective references the ending cue rather than a kill-all substitute"
	)
	check(
		(
			definition.ending == {"chapter": 12, "text": 399}
			and not lib.text(int(definition.ending.text)).is_empty()
		),
		"Source terminal chapter and localized completion announcement are imported"
	)
	check(
		(
			not definition.groups[6].render_mesh
			and not lib.content.resources.has(str(int(lib.content.tables.actor_meshes[3])))
		),
		"Terran turret remains a combat hardpoint without inventing a missing source mesh"
	)
	var original_finale: Dictionary = lib.content.missions[12]
	lib.content.missions[12] = definition
	check(lib.valid_missions(), "Finale encounter data satisfies native content validation")
	var correct_ending: Dictionary = definition.ending.duplicate()
	definition.ending.chapter = 0
	check(not lib.valid_missions(), "Ending metadata cannot label the opening chapter as terminal")
	definition.ending = correct_ending
	var guns: Dictionary = lib.actor_weapons(12, 5)
	var state := Session.Mission.create(definition, 12, 6, lib, 71, 5)
	check(
		(
			state.actors.size() == 16
			and state.target == 7
			and state.actors[6].hp == 700
			and state.actors[7].hp == 65
			and state.actors[12].hp == 60
		),
		"Native actor creation preserves source order, health and opposing teams"
	)
	check(
		guns[-7].damage == 5 and guns[-13].damage == 5 and guns[-13].team == "ally",
		"Commander and allied turret ballistics are independent native weapon profiles"
	)
	check(
		not Session.Mission.route_pending(definition, state) and not state.ready,
		"Finale foundation does not release its route or grant a victory on entry"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 12, 6, lib),
		"Finale fleet state round trips through JSON validation"
	)
	var battle := state.duplicate(true)
	var turret: Dictionary = battle.actors[12]
	var target: Vector3 = Combat.vector(turret.position) + Combat.vector(turret.heading) * 150
	battle.actors[0].position = Combat.packed(target)
	for index in range(1, 6):
		battle.actors[index].position = [100000, 100000, 100000]
	var ballistics := Combat.create()
	Session.Encounters.advance(
		definition, battle, .02, Vector3(0, 0, 10000), Vector3.ZERO, ballistics, lib, guns
	)
	check(
		battle.actors[12].shots > 0 and not ballistics.projectiles.is_empty(),
		"Allied capital turret fires through native targeting at an actual hostile"
	)
	for index in 7:
		battle.actors[index].awake = true
		Session.Mission.damage(definition, battle, index, 10000000)
	check(
		(
			not battle.ready
			and Session.Mission.Radio.triggered(definition.radio[6], definition, battle)
		),
		"Defeating all enemies starts the closing radio but is not the finale objective"
	)
	battle.radio = {"shown": range(12), "current": 11, "remaining": 3.0, "delay": 0.0}
	Session.Mission.evaluate(definition, battle)
	check(
		battle.ready and not Session.Mission.Radio.finished(definition, battle),
		"Authored ending cue satisfies the objective while its reading time still blocks settlement"
	)
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(battle))
	check(
		Session.Mission.valid(definition, loaded, 12, 6, lib),
		"Message objective remains true after JSON converts message IDs to numbers"
	)
	check(
		not lib.valid_objective({"kind": "message_shown", "message": 12}, definition),
		"Reject a completion cue beyond the imported radio list"
	)
	lib.content.missions[12] = original_finale
	check(not lib.mission_playable(13), "Finale data does not invent a fourteenth mission")
	var routes := reader.calls_between(bounds[12], bounds[13], "__ZN5RouteC1EPii")
	var hulls := reader.calls_between(bounds[12], bounds[13], "__ZN6Player15setMaxHitpointsEi")
	var objectives := reader.calls_between(bounds[12], bounds[13], "__ZN9ObjectiveC1EiiP5Level")
	var turret_factory := reader.symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	var gun_calls := reader.calls_between(
		reader.symbol_address("__ZN5Level10assignGunsEv"),
		reader.symbol_end(reader.symbol_address("__ZN5Level10assignGunsEv")),
		"__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"
	)
	var gun: int = gun_calls.filter(func(call): return reader.u16(call + 14) == 0x208c and reader.u16(call + 18) == 0x5031)[0]
	var changed := source.duplicate()
	changed.encode_s32(reader.file_offset(reader.literal(routes[0] - 34, 3), 4), 1234)
	changed.encode_float(literal_file_offset(reader, hulls[0] - 14), 800.0)
	changed.encode_s32(reader.file_offset(reader.literal(turret_factory + 290, 2), 4), 100)
	changed.encode_u16(reader.file_offset(gun - 124, 2), 0x2007)
	changed.encode_u16(reader.file_offset(objectives[0] - 10, 2), 0x220a)
	reader.bytes = changed
	reader.error = ""
	var altered := reader.finale_encounter_data(bounds[12], bounds[13], 12)
	check(
		(
			not altered.is_empty()
			and altered.route[0][0] == 1234
			and altered.groups[1].hull == 800
			and altered.groups[1].weapon.damage == 7
			and altered.groups[6].center[0] == 6100
			and altered.success.message == 10
		),
		"Changed source route, hull, weapon, mount and completion cue reach native finale data"
	)
	reader.bytes = source
	reader.error = ""
	var ships := reader.calls_between(
		bounds[12], bounds[13], "__ZN5Level10createShipEiiibP8Waypoint"
	)
	for location in [ships[0] - 2, ships[3] - 18, objectives[0] - 12]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(location, 2), 0x46c0)
		reader.bytes = changed
		reader.error = ""
		check(
			(
				reader.finale_encounter_data(bounds[12], bounds[13], 12).is_empty()
				and not reader.error.is_empty()
			),
			"Reject changed finale role/objective association at %x" % location
		)

	reader.bytes = source
	reader.error = ""
	var ending := reader.symbol_address("__ZN6Status10missionEndEv")
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(ending + 22, 2), 0x280b)
	reader.bytes = changed
	check(
		reader.campaign_ending().is_empty() and not reader.error.is_empty(),
		"Reject terminal markers that disagree with the station's ending transition"
	)


func check_finale_director(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index finale cinematic declarations")
	var bounds := reader.campaign_boundaries(13)
	var definition := reader.finale_definition(bounds[12], bounds[13], 12)
	check(not definition.is_empty(), "Recover finale dialogue director: " + reader.error)
	if definition.is_empty():
		return
	definition.radio = reader.radio_definitions(13, 13)[12]
	check(
		definition.sequence.size() == 8 and definition.sequence[5].actions.is_empty(),
		"Finale preserves eight milestones including the wait for a closing line to finish"
	)
	check(
		(
			definition.sequence[1].actions[4].offset == [-3000, 1800, 12000]
			and definition.sequence[7].actions[0].offset == [3000, 1800, -12000]
		),
		"Finale camera coordinates are recovered from supplied declarations"
	)
	var original_finale: Dictionary = lib.content.missions[12]
	lib.content.missions[12] = definition
	check(lib.valid_missions(), "Finale director passes content validation")
	var state := Session.Mission.create(definition, 12, 6, lib, 71, 5)
	state.camera_position = [200.0, 100.0, 300.0]
	# These are isolated transition fixtures; the actual battle is verified separately.
	var invalid := state.duplicate(true)
	invalid.actors[6].hp -= 1
	check(
		not Session.Mission.valid(definition, invalid, 12, 6, lib),
		"Dormant reserve cannot take damage before any authored sleep transition"
	)
	invalid = state.duplicate(true)
	invalid.actors[7].awake = false
	check(
		not Session.Mission.valid(definition, invalid, 12, 6, lib),
		"Allies cannot be saved asleep before their authored transition"
	)
	commit_pursuit_event(definition, state, lib)
	check(
		(
			state.sequence_cursor == 1
			and Session.Mission.route_pending(definition, state)
			and Combat.vector(state.actors[6].position) == Vector3(0, 0, -2600)
		),
		"Initial enemy defeat releases approach and places the commander at the source waypoint"
	)
	state.actors[6].awake = true
	state.actors[6].hp -= 10
	state.actors[7].hp -= 5
	commit_pursuit_event(definition, state, lib)
	var direction := Session.Mission.Sequence.directives(definition, state)
	check(
		(
			direction.locked
			and direction.frozen
			and not direction.vulnerable
			and direction.suspended == [6]
		),
		"Commander introduction locks and protects only the pilot and suspends the commander"
	)
	check(
		state.actors.slice(6).all(func(actor): return not actor.awake),
		"Authored introduction sends the commander and every ally to sleep"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 12, 6, lib),
		"Wounded actors put to sleep by the director remain valid after JSON reload"
	)
	invalid = state.duplicate(true)
	invalid.actors[6].awake = true
	check(
		not Session.Mission.valid(definition, invalid, 12, 6, lib),
		"Reject an awake commander during enforced dialogue sleep"
	)
	var guns: Dictionary = lib.actor_weapons(12, 5)
	var battle := Combat.create()
	var original_position: Array = state.actors[6].position.duplicate()
	state.actors[7].position = original_position.duplicate()
	for tick in 20:
		Session.Encounters.advance(
			definition,
			state,
			.02,
			Combat.vector(original_position),
			Vector3.ZERO,
			battle,
			lib,
			guns
		)
	check(
		(
			not state.actors[6].awake
			and state.actors[6].position == original_position
			and state.actors[6].shots == 0
		),
		"Commander cannot proximity-wake, move or shoot while held asleep"
	)
	check(state.actors[7].awake, "One-shot ally sleep still permits natural proximity activation")
	check(
		not Session.Mission.damage(definition, state, 6, 100),
		"Suspended commander is excluded from combat damage"
	)
	commit_pursuit_event(definition, state, lib)
	check(
		(
			state.sequence_cursor == 3
			and Session.Mission.Sequence.directives(definition, state).focus.actor == -1
		),
		"Player reply changes camera target while keeping protection"
	)
	Session.Mission.advance(definition, state, 100, lib)
	check(
		state.sequence_cursor == 3, "Simulation speedup alone cannot end the real-time player reply"
	)
	commit_pursuit_event(definition, state, lib)
	direction = Session.Mission.Sequence.directives(definition, state)
	check(
		(
			not direction.locked
			and not direction.frozen
			and direction.vulnerable
			and direction.suspended.is_empty()
		),
		"Only the finished reply releases combat and removes player protection"
	)
	Session.Encounters.advance(
		definition, state, .02, Combat.vector(original_position), Vector3.ZERO, battle, lib, guns
	)
	check(
		state.actors[6].awake and Session.Mission.damage(definition, state, 6, 1),
		"Released commander wakes and becomes damageable again"
	)
	commit_pursuit_event(definition, state, lib)
	direction = Session.Mission.Sequence.directives(definition, state)
	check(
		(
			direction.locked
			and direction.vulnerable
			and not direction.frozen
			and Combat.vector(direction.camera_anchor) == Vector3(200, 100, 300)
		),
		"Closing conversation holds the current camera without granting another protected battle phase"
	)
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(
		(
			Session.Mission.valid(definition, loaded, 12, 6, lib)
			and (
				Session.Mission.Sequence.directives(definition, loaded).camera_anchor
				== direction.camera_anchor
			)
		),
		"Closing camera anchor survives JSON reload"
	)
	invalid = loaded.duplicate(true)
	invalid.sequence_positions.erase("camera:4")
	check(
		not Session.Mission.valid(definition, invalid, 12, 6, lib),
		"Reject a saved camera hold without its committed anchor"
	)
	invalid = loaded.duplicate(true)
	invalid.camera_position = [NAN, 0, 0]
	check(
		not Session.Mission.valid(definition, invalid, 12, 6, lib),
		"Reject non-finite saved camera coordinates"
	)
	Session.Mission.advance(definition, state, 100, lib)
	check(state.sequence_cursor == 5, "Closing wait does not end while its line is still current")
	commit_pursuit_event(definition, state, lib)
	commit_pursuit_event(definition, state, lib)
	check(
		(
			Combat.vector(Session.Mission.Sequence.directives(definition, state).camera_anchor)
			== Vector3(200, 100, 300)
		),
		"Later offset declaration does not move a held camera"
	)
	commit_pursuit_event(definition, state, lib)
	direction = Session.Mission.Sequence.directives(definition, state)
	check(
		(
			state.sequence_cursor == 8
			and direction.locked
			and direction.camera_anchor.is_empty()
			and not state.ready
		),
		"Final camera release does not skip the objective's last transmission"
	)
	state.radio.shown.append(11)
	state.radio.current = 11
	state.radio.remaining = 3.0
	Session.Mission.evaluate(definition, state)
	check(
		state.ready and not Session.Mission.Radio.finished(definition, state),
		"Even a finished director waits for the ending transmission before settlement"
	)
	check(
		Session.Mission.valid(definition, JSON.parse_string(JSON.stringify(state)), 12, 6, lib),
		"Completed director and retained camera history validate after reload"
	)
	var malformed := definition.duplicate(true)
	malformed.sequence[1].actions[3].value = 1
	check(
		not Session.Mission.Sequence.valid_definition(malformed),
		"Reject numeric values in a boolean suspension declaration"
	)
	malformed = definition.duplicate(true)
	malformed.sequence[4].actions.append(malformed.sequence[4].actions.back().duplicate(true))
	check(
		not Session.Mission.Sequence.valid_definition(malformed),
		"Reject ambiguous double camera capture at one milestone"
	)
	malformed = definition.duplicate(true)
	malformed.groups[3].erase("wake_half_width")
	check(
		not Session.Mission.Sequence.valid_definition(malformed),
		"Scripted sleep requires a supported wake rule for fixed ships"
	)
	lib.content.missions[12] = original_finale
	var process := reader.symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := process + 48
	var base := (reader.u16(process + 40) >> 6) & 7
	var branch := table + reader.u16(table + 2 + (12 - base) * 2) * 2
	var stages := branch + 8
	var intro := stages + reader.u16(stages + 4) * 2
	var ending := stages + reader.u16(stages + 2 + 7 * 2) * 2
	var changed := source.duplicate()
	changed.encode_s32(literal_file_offset(reader, intro + 0x6a), -4000)
	changed.encode_u16(reader.file_offset(intro + 0x22, 2), 0x2101)
	reader.bytes = changed
	reader.error = ""
	var altered := reader.finale_definition(bounds[12], bounds[13], 12)
	check(
		(
			not altered.is_empty()
			and altered.sequence[1].actions[4].offset[0] == -4000
			and altered.sequence[1].actions[1].value
		),
		"Source mutations alter camera composition and vulnerability without hardcoded mission values"
	)
	# A missing repeated sleep declaration cannot silently become a supported scene.
	changed = source.duplicate()
	var reply := stages + reader.u16(stages + 2 + 2 * 2) * 2
	changed.encode_u16(reader.file_offset(reply + 10, 2), 0xbf00)
	reader.bytes = changed
	reader.error = ""
	check(
		(
			reader.finale_definition(bounds[12], bounds[13], 12).is_empty()
			and not reader.error.is_empty()
		),
		"Reject an unrecognized commander hold declaration"
	)


func check_finale_flight(lib, campaign, ipa: String):
	var zip := ZIPReader.new()
	check(zip.open(ipa) == OK, "Read private finale content for isolated native battle")
	var reader := NativeData.new()
	reader.bytes = zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	check(reader.parse_macho(), "Index finale for native campaign continuation")
	var bounds := reader.campaign_boundaries(lib.content.chapters.size())
	var definition := reader.finale_definition(bounds[12], bounds[13], 12)
	if definition.is_empty():
		check(false, "Decode finale battle: " + reader.error)
		return campaign
	definition.radio = reader.radio_definitions(13, 13)[12]
	var before_shop: int = campaign.credits
	var old_worth: int = campaign.earned_worth()
	var spent := 0
	var cargo_income := 0
	for category in [0, lib.SHIELD_CATEGORY]:
		var offers: Array = campaign.market_offers()
		for index in offers.size():
			var offer: Dictionary = offers[index]
			if offer.kind == "equipment" and int(lib.items[int(offer.id)][1]) == category:
				cargo_income += make_campaign_purchase_space(campaign, index)
				spent += int(offer.price)
				check(
					(
						campaign.buy_offer(index)
						and campaign.fit_equipment(campaign.loadout.hold.size() - 1)
					),
					"Fit the original finale station's weapon/shield offer using earned funds"
				)
				break
	check(
		(
			campaign.credits == before_shop + cargo_income - spent
			and campaign.earned_worth() == old_worth
			and campaign.max_shield() > 0
		),
		"Finale outfitting spends real credits without changing earned rank"
	)
	# Use the public imported mission for the complete campaign playthrough.
	definition = lib.mission_definition(12)
	check(
		campaign.chapter == 12 and campaign.progression.rewards.size() == 12 and campaign.depart(),
		"Finale departs with the actual twelve-mission pilot and earned loadout"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true})
	flight.set_physics_process(false)
	var checkpoints: Array = []
	var commander_fired := false
	var saw_protected := false
	var intro_health := 0.0
	for tick in 72000:
		drive_pursuit_combat(flight)
		flight.controls.axes[JOY_AXIS_LEFT_X] = (
			(1.0 if fmod(float(campaign.active_job.elapsed_ms), 2200.0) < 1100.0 else -1.0)
			if flight.ship.position.length() > 400
			else 0.0
		)
		flight.step(1.0 / 60)
		campaign.advance_radio(1.0 / 60)
		flight.update_camera(1.0 / 60)
		var job: Dictionary = campaign.active_job
		var cursor := int(job.sequence_cursor)
		if cursor == 2 and not saw_protected:
			saw_protected = true
			intro_health = campaign.hull + campaign.shield
		if cursor in [2, 3]:
			check_protected_finale_tick(job, campaign, intro_health)
		commander_fired = commander_fired or job.actors[6].shots > 0
		var phase := ""
		if cursor == 0 and job.kills > 0:
			phase = "fleet battle"
		elif cursor == 2:
			phase = "commander introduction"
		elif cursor == 4 and job.actors[6].hp < definition.groups[1].hull and job.actors[6].hp > 0:
			phase = "commander battle"
		elif cursor == 5:
			phase = "closing conversation"
		if not phase.is_empty() and not checkpoints.has(phase):
			checkpoints.append(phase)
			check(
				not campaign.complete_campaign() and not campaign.exploration_unlocked(),
				"Combat or unfinished closing dialogue cannot grant completion"
			)
			campaign.flight_position = flight.ship.position
			campaign.flight_rotation = flight.ship.rotation
			var old_state: Dictionary = job.duplicate(true)
			var restored := Session.new()
			restored.configure(lib)
			var success := restored.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			check(
				success and same_saved_value(restored.active_job, old_state),
				"Restore full finale state during " + phase + ": " + restored.error
			)
			if success:
				flight.queue_free()
				await process_frame
				campaign = restored
				flight = Flight.new()
				root.add_child(flight)
				flight.setup(lib, campaign, {"aim_assist": false, "linked_fire": true}, true)
				flight.set_physics_process(false)
		if flight.paused:
			break
	check(
		campaign.hull > 0 and campaign.active_job.ready and campaign.ready_to_finish(),
		"Native finale combat and all natural radio timers reach settlement readiness"
	)
	check(
		saw_protected and commander_fired and checkpoints.size() == 4,
		"Finale exercises protection, live commander weapons and four battle/dialogue reloads"
	)
	check(
		(
			campaign.active_job.sequence_cursor == 8
			and campaign.active_job.radio.shown.size() == 12
			and campaign.active_job.kills == 7
		),
		"Actual final battle completes eight milestones, twelve transmissions and seven enemies"
	)
	print(
		"FINALE BATTLE elapsed=",
		campaign.active_job.elapsed_ms,
		" hull=",
		campaign.hull,
		" cursor=",
		campaign.active_job.sequence_cursor,
		" radio=",
		campaign.active_job.radio,
		" kills=",
		campaign.active_job.kills,
		" checkpoints=",
		checkpoints
	)
	var cash: int = campaign.credits
	var worth: int = campaign.earned_worth()
	var payment: int = lib.content.chapters[12].reward
	check(
		(
			campaign.complete_campaign()
			and campaign.campaign_state == "completed"
			and campaign.chapter == 13
			and campaign.exploration_unlocked()
		),
		"Actual final objective and closing transmission unlock exploration"
	)
	check(
		(
			campaign.credits == cash + payment
			and campaign.earned_worth() == worth + payment
			and campaign.progression.rewards.size() == 13
		),
		"Final settlement records and pays the imported reward exactly once"
	)
	check(
		campaign.rating == 10, "All thirteen completed campaign jobs reach the source faction limit"
	)
	check(
		campaign.campaign_ending_text() == lib.text(int(definition.ending.text)),
		"Completed pilot receives the supplied terminal announcement"
	)
	check(
		(
			not campaign.finish_mission()
			and not campaign.complete_campaign()
			and campaign.credits == cash + payment
		),
		"Repeated completion cannot duplicate the final reward"
	)
	var completed := Session.new()
	completed.configure(lib)
	check(
		(
			completed.restore(JSON.parse_string(JSON.stringify(campaign.capture())))
			and completed.exploration_unlocked()
			and completed.campaign_state == "completed"
		),
		"Completed campaign and all thirteen reward receipts survive JSON reload"
	)
	var forged: Dictionary = campaign.capture()
	forged.progression = {"legacy_through": 13, "rewards": []}
	check(
		not completed.restore(forged),
		"A legacy preview baseline cannot invent a completed campaign"
	)
	forged = campaign.capture()
	forged.chapter = 12
	forged.progression.rewards.pop_back()
	check(not completed.restore(forged), "A pre-finale chapter cannot carry a completion flag")
	forged = campaign.capture()
	forged.campaign_state = "active"
	check(
		not completed.restore(forged),
		"Terminal progress cannot masquerade as an unfinished campaign"
	)

	flight.queue_free()
	await process_frame
	return campaign


func check_protected_finale_tick(job: Dictionary, campaign, health: float) -> void:
	# Fail once at the actual offending tick rather than multiplying check counts.
	if campaign.hull + campaign.shield < health or job.actors[6].awake:
		check(
			false, "Finale protection and commander suspension remain active throughout the reply"
		)


func check_contract_rules(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index original freelance board data")
	var rules := reader.contract_rules()
	check(
		not rules.is_empty() and reader.error.is_empty(),
		"Recover freelance terms and client associations: " + reader.error
	)
	if rules.is_empty():
		return
	check_contract_client_source(reader, source, rules, lib)
	check(
		Contracts.valid_rules(rules, lib.strings.size(), lib.content.radio_ui.portraits.size()),
		"Imported board rules pass native content validation"
	)
	check(
		rules.types.size() == 12 and rules.offer_count == [1, 5] and rules.tier_range == [1, 9],
		"Source board declares twelve types, one to five offers and nine difficulty tiers"
	)
	check(
		(
			lib.text(rules.types[0].title) == "Revenge"
			and lib.text(rules.types[11].title) == "Capture"
			and rules.types[0].description == 464
		),
		"Contract names and descriptions resolve through original UI associations"
	)
	check(
		(
			rules.quadrant_difficulty == [1, 3, 7, 15]
			and rules.minimum_rewards == [1000, 3000, 5000, 7000]
			and rules.maximum_rewards == [3000, 5000, 7000, 10000]
		),
		"Board difficulty and reward bounds use the actual referenced region tables"
	)
	check(
		(
			rules.male_portraits.size() == 50
			and rules.female_portraits.size() == 40
			and rules.special.portrait == 31
			and rules.special.limit == 1
		),
		"Original client portrait lists and special-client limit are preserved"
	)
	check(
		(
			rules.special.chance_count == 10
			and rules.special.chance_out_of == 100
			and rules.local_race_attempts == 5
		),
		"Source board keeps its special-client chance and local affiliation attempts"
	)
	var basic := Contracts.terms(rules, 0, 9, 1)
	check(
		basic.reward == 1200 and basic.difficulty == 1 and basic.reward_unit == "fixed",
		"Basic passenger quote uses region bounds and difficulty fraction"
	)
	check(
		(
			Contracts.terms(rules, 0, 0, 1).reward == 1050
			and Contracts.terms(rules, 0, 4, 1).reward == 800
			and Contracts.terms(rules, 0, 1, 1).reward == 1400
		),
		"Revenge, clearing and combat jobs apply their distinct source multipliers"
	)
	check(
		Contracts.terms(rules, 0, 0, 5).reward == 1800,
		"Binary32 stage rounding preserves an exact payout boundary"
	)
	var hard := Contracts.terms(rules, 3, 11, 9, true)
	check(
		hard.reward == 16250 and hard.difficulty == 135,
		"Highest region/tier and special-client premium combine without using pilot rank"
	)
	var rate := Contracts.terms(rules, 3, 6, 9, true, 119)
	check(
		rate.reward == 119 and rate.reward_unit == "per_target" and rate.difficulty == 135,
		"Asteroid work preserves its per-target rate rather than becoming a fixed payout"
	)
	check(
		(
			Contracts.terms(rules, 0, 6, 1).is_empty()
			and Contracts.terms(rules, 0, 6, 1, false, 120).is_empty()
		),
		"Per-target jobs require a rate inside the imported range"
	)
	check(
		(
			Contracts.terms(rules, -1, 0, 1).is_empty()
			and Contracts.terms(rules, 0, 12, 1).is_empty()
			and Contracts.terms(rules, 0, 0, 10).is_empty()
		),
		"Reject out-of-range region, contract type and difficulty tier"
	)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(rules))
	check(
		(
			Contracts.valid_rules(saved, lib.strings.size(), lib.content.radio_ui.portraits.size())
			and Contracts.terms(saved, 3, 11, 9, true) == hard
		),
		"Normalized contract rules preserve exact terms through JSON"
	)
	for mode in ["factor", "portrait", "localization", "range", "rounding", "step"]:
		var invalid := rules.duplicate(true)
		match mode:
			"factor":
				invalid.types[0].reward_factor = NAN
			"portrait":
				invalid.male_portraits[0] = 32
			"localization":
				invalid.types[0].description = lib.strings.size()
			"range":
				invalid.rate_range = [119, 70]
			"rounding":
				invalid.rounding = "nearest"
			"step":
				invalid.reward_step = 0
		check(
			not Contracts.valid_rules(invalid, lib.strings.size(), 32),
			"Reject invalid contract " + mode
		)
	var start := reader.symbol_address("__ZN9Generator14getMissionListEv")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(start + 0x5e, 2), 0x2107)
	changed.encode_float(literal_file_offset(reader, start + 0x27e), .9375)
	changed.encode_s32(reader.file_offset(reader.literal(start + 0x166, 2), 4), 24)
	reader.bytes = changed
	reader.error = ""
	var altered := reader.contract_rules()
	check(
		(
			not altered.is_empty()
			and altered.offer_count == [1, 7]
			and altered.male_portraits[0] == 24
			and Contracts.terms(altered, 0, 0, 1).reward == 1150
		),
		"Source mutations alter offer count, client portrait and the half-step-up quote"
	)
	changed.encode_float(literal_file_offset(reader, start + 0x27e), .939)
	reader.bytes = changed
	reader.error = ""
	altered = reader.contract_rules()
	check(
		not altered.is_empty() and Contracts.terms(altered, 0, 0, 1).reward == 1100,
		"A non-tie remainder follows source floor behavior, not conventional nearest rounding"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(start + 0x2e8, 2), 0x1ac3)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.contract_rules().is_empty() and not reader.error.is_empty(),
		"Reject changed arithmetic association instead of silently assuming the old reward policy"
	)
	changed = source.duplicate()
	var offset := 28
	for index in changed.decode_u32(16):
		if changed.decode_u32(offset) == 11:
			changed.encode_u32(offset + 60, 0xffffffff)
			break
		offset += changed.decode_u32(offset + 4)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.imported_symbols().is_empty() and not reader.error.is_empty(),
		"Reject oversized indirect symbol tables used by imported arithmetic helpers"
	)


func check_contract_client_source(reader, source: PackedByteArray, rules: Dictionary, lib) -> void:
	var clients: Dictionary = rules.clients
	check(
		clients.special_name == "Noid Trillyx" and clients.random_gender_races == [0, 4],
		"Special client name and race/gender policies come from supplied declarations"
	)
	check(
		(
			clients.professions[0][0] == [444, 445]
			and clients.professions[1][0] == [439, 440, 441]
			and clients.professions[1][1] == [442, 443]
			and clients.professions[1][9] == [429, 437]
		),
		"Contract professions preserve category and race-specific choices"
	)
	check(
		(
			clients.professions[7][0] == [426, 427, 428, 429, 430]
			and clients.professions[9][0] == [431, 432, 433, 434, 435, 436, 437, 438]
		),
		"Escort and civilian contracts retain their supplied profession pools"
	)
	var names: int = reader.symbol_address(
		"__ZN7Globals9loadNamesEibP5ArrayIPN11AbyssEngine6StringEE"
	)
	var generator: int = reader.symbol_address("__ZN9GeneratorC2Ev")
	var professions: int = reader.symbol_address("__ZN9Generator18generateProfessionEii")
	var changed := source.duplicate()
	changed.encode_u32(
		literal_file_offset(reader, names + 0x3e), reader.literal(names + 0x40 + 4 * 12, 1)
	)
	changed[reader.file_offset(reader.literal(generator + 0x40, 1), 1)] = 86
	changed.encode_u16(reader.file_offset(professions + 0x2c, 2), 0x20dc)
	reader.bytes = changed
	reader.error = ""
	var altered: Dictionary = reader.contract_rules()
	check(
		(
			not altered.is_empty()
			and altered.clients.name_files[0].male == "data/txt/names_leonid_m.txt"
			and altered.clients.special_name == "Void Trillyx"
			and altered.clients.professions[1][1] == [440, 443]
		),
		"Source changes alter name-file associations, special client name and profession choices"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(professions + 0x1a, 2), 0xd00b)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.contract_rules().is_empty() and not reader.error.is_empty(),
		"Reject changed client profession control association"
	)
	changed = source.duplicate()
	changed[reader.file_offset(professions + 10, 1)] = 255
	reader.bytes = changed
	reader.error = ""
	check(
		reader.contract_rules().is_empty() and not reader.error.is_empty(),
		"Reject oversized contract profession dispatch"
	)
	reader.bytes = source
	reader.error = ""
	for mode in ["profession", "name_path", "gender", "override", "duplicate", "special_name"]:
		var invalid := rules.duplicate(true)
		match mode:
			"profession":
				invalid.clients.professions[0][0] = [lib.strings.size()]
			"name_path":
				invalid.clients.name_files[0].male = "data/txt/../../secret.txt"
			"gender":
				invalid.clients.random_gender_races.append(rules.client_race_count)
			"override":
				invalid.clients.race_overrides[0].race = -1
			"duplicate":
				invalid.clients.race_overrides.append(invalid.clients.race_overrides[0].duplicate())
			"special_name":
				invalid.clients.special_name = ""
		check(
			not Contracts.valid_rules(
				invalid, lib.strings.size(), lib.content.radio_ui.portraits.size()
			),
			"Reject invalid contract client " + mode
		)


func check_contract_boards(lib) -> void:
	var rules: Dictionary = lib.content.contracts
	check(lib.contract_names.size() == 12, "Import all twelve reachable client name files")
	check(
		(
			lib.contract_names[rules.clients.name_files[0].male][0] == "Frank Harmon"
			and lib.contract_names[rules.clients.name_files[4].female][0] == "Apea Pomahna"
		),
		"Original semicolon-delimited names resolve through imported race and gender bindings"
	)
	var parser := Formats.new()
	check(
		(
			parser.name_list("Anna Bell;\r\n\tBao Chen;".to_utf8_buffer())
			== PackedStringArray(["Anna Bell", "Bao Chen"])
		),
		"Name lists ignore source formatting controls and preserve spaces inside names"
	)
	for data in [
		PackedByteArray(),
		"Anna;Bao".to_utf8_buffer(),
		"Anna;;".to_utf8_buffer(),
		PackedByteArray([65, 0, 59]),
		PackedByteArray([0xff, 59]),
		("A".repeat(256) + ";").to_utf8_buffer()
	]:
		check(
			parser.name_list(data).is_empty() and not parser.error.is_empty(),
			"Reject malformed, empty, unbounded or unterminated client names"
		)
	var kinds := {}
	var races := {}
	var special_total := 0
	var female_total := 0
	var consistent := true
	for station_id in lib.stations.size():
		var station: Dictionary = lib.station_definition(station_id)
		var board := Contracts.generate(lib, station_id, 931 + station_id)
		consistent = (
			consistent
			and board.size() >= rules.offer_count[0]
			and board.size() <= rules.offer_count[1]
		)
		var special_count := 0
		for offer in board:
			var client: Dictionary = offer.client
			kinds[offer.type] = true
			races[client.race] = true
			var terms := Contracts.terms(
				rules,
				int(station.quadrant),
				offer.type,
				offer.tier,
				offer.special,
				offer.reward if offer.reward_unit == "per_target" else -1
			)
			for key in terms:
				consistent = consistent and terms[key] == offer[key]
			consistent = consistent and offer.origin_station == station_id
			for override in rules.clients.race_overrides:
				if override.station == station.race:
					consistent = consistent and client.race != override.rolled
			if offer.special:
				special_count += 1
				consistent = (
					consistent
					and client.name == rules.clients.special_name
					and client.portrait == rules.special.portrait
					and client.profession == rules.special.profession
				)
			else:
				var matches := false
				for gender in ["male", "female"]:
					if (
						gender == "female"
						and not rules.clients.random_gender_races.has(client.race)
					):
						continue
					var choices := int(rules[gender + "_choices"])
					var portraits: Array = rules[gender + "_portraits"].slice(
						client.race * choices, (client.race + 1) * choices
					)
					if (
						lib.contract_names[rules.clients.name_files[client.race][gender]].has(
							client.name
						)
						and portraits.has(client.portrait)
					):
						matches = true
						female_total += 1 if gender == "female" else 0
				consistent = (
					consistent
					and matches
					and rules.clients.professions[offer.type][client.race].has(client.profession)
				)
			special_total += 1 if offer.special else 0
		consistent = consistent and special_count <= rules.special.limit
	check(
		(
			consistent
			and kinds.size() == 12
			and races.size() == 10
			and special_total > 0
			and female_total > 0
		),
		"All 500 stations generate consistent source-based clients and terms across all contract categories"
	)
	var first := Contracts.generate(lib, 0, 51)
	check(first == Contracts.generate(lib, 0, 51), "A board is reproducible from its seed")
	check(
		(
			Contracts.generate(lib, -1, 3).is_empty()
			and Contracts.generate(lib, lib.stations.size(), 3).is_empty()
		),
		"Invalid station cannot generate a board"
	)
	var random := RandomNumberGenerator.new()
	random.seed = 735
	var local_count := 0
	for index in 20000:
		local_count += 1 if Contracts.client_race(rules, 2, random) == 2 else 0
	check(
		absf(float(local_count) / 20000 - (1.0 - pow(.9, 5))) < .015,
		"Direct native client sampling preserves the five-attempt local-race distribution"
	)
	var special: Dictionary = rules.special.duplicate(true)
	rules.special.chance_count = rules.special.chance_out_of
	var forced := Contracts.generate(lib, 0, 51)
	check(
		forced[0].special and forced.filter(func(offer): return offer.special).size() == 1,
		"A certain special offer still respects the supplied one-per-board limit"
	)
	rules.special = special.duplicate(true)
	var path: String = rules.clients.name_files[0].male
	var original_names: PackedStringArray = lib.contract_names[path]
	lib.contract_names[path] = PackedStringArray(["Supplied test client"])
	var client_rules: Dictionary = rules.clients.duplicate(true)
	rules.client_race_count = 1
	rules.special.chance_count = 0
	rules.clients.random_gender_races = []
	var changed := Contracts.generate(lib, 0, 51)
	check(
		changed.all(func(offer): return offer.client.name == "Supplied test client"),
		"Changing the supplied name pool changes generated clients without editing simulation code"
	)
	rules.client_race_count = 10
	rules.special = special.duplicate(true)
	rules.clients = client_rules
	lib.contract_names[path] = original_names


func check_contract_hunts(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.hunt
	check(
		ContractEncounters.valid_parameters(parameters, lib),
		"Imported hunt parameters pass native validation"
	)
	check(
		parameters.types == [0, 3] or parameters.types == [0.0, 3.0],
		"Revenge and Wanted resolve to their shared source encounter declaration"
	)
	var offer := Contracts.terms(lib.content.contracts, 3, 0, 9)
	offer.origin_station = 375
	offer.client = {"name": "Test client", "race": 0, "portrait": 11, "profession": 444}
	var definition := ContractEncounters.hunt(lib, parameters, offer, 5, 37)
	check(
		not definition.is_empty() and lib.valid_mission(definition),
		"Generated hunt passes the same definition validation as campaign encounters"
	)
	if definition.is_empty():
		return
	check(
		definition.groups.size() == 3 and definition.groups[0].hull == 750,
		"Highest-tier hunt has a 750-hull designated target and two escorts at rank five in region four"
	)
	check(
		definition.groups[1].actor == 1 and definition.groups[1].hull == 265,
		"Non-Vossk client escorts use source fighter and freelance hull multiplier"
	)
	var original := parameters.duplicate(true)
	check(
		(
			(
				ContractEncounters.hunt(
					lib, JSON.parse_string(JSON.stringify(parameters)), offer, 5, 37
				)
				== definition
			)
			and parameters == original
		),
		"Hunts are reproducible through normalized data JSON without mutating imported parameters"
	)
	var state := Session.Mission.create(definition, 0, 375, lib, 37, 5)
	for actor in state.actors:
		actor.awake = true
	for index in range(1, state.actors.size()):
		Session.Mission.damage(definition, state, index, 100000)
	check(
		not state.ready and state.kills == 2,
		"Destroying both escorts does not satisfy the designated-target objective"
	)
	Session.Mission.damage(definition, state, 0, 100000)
	check(not state.ready, "Hunt waits for target destruction after hull loss")
	finish_wrecks_fixture(definition,state,lib)
	check(state.ready, "Destroying the actual target completes the hunt objective")
	state = Session.Mission.create(definition, 0, 375, lib, 37, 5)
	state.actors[0].awake = true
	Session.Mission.damage(definition, state, 0, 100000)
	finish_wrecks_fixture(definition,state,lib)
	check(
		state.ready and state.kills == 1 and state.actors[1].hp > 0,
		"A target kill succeeds while surviving escorts remain"
	)
	var scenery := {}
	var kinds := {}
	var complete := true
	for seed_value in 64:
		var sample := ContractEncounters.hunt(lib, parameters, offer, 5, seed_value)
		if sample.is_empty():
			complete = false
			continue
		scenery["fog" if sample.has("fog") else "asteroids"] = true
		kinds[sample.groups[0].actor] = true
		for axis in 3:
			complete = (
				complete
				and sample.route[0][axis] >= parameters.route_bounds[axis][0]
				and sample.route[0][axis] <= parameters.route_bounds[axis][1]
			)
	check(
		complete and scenery.size() == 2 and kinds.size() == 9,
		"Native generation covers both source scenery choices and all nine target models within the imported route bounds"
	)
	var vossk := offer.duplicate(true)
	vossk.client.race = 1
	var distinct := false
	for seed_value in 12:
		var sample := ContractEncounters.hunt(lib, parameters, vossk, 5, seed_value)
		distinct = distinct or sample.groups[1].actor != 1
	check(distinct, "Vossk client hunts recruit escorts from the supplied Terran fighter pool")
	var special := Contracts.terms(lib.content.contracts, 3, 3, 9, true)
	special.origin_station = 375
	special.client = {"race": 0, "portrait": 31, "name": "Noid Trillyx", "profession": 497}
	var special_definition := ContractEncounters.hunt(lib, parameters, special, 5, 19)
	check(
		(
			special_definition.radio.size() >= 4
			and special_definition.radio.size() <= 7
			and special_definition.radio[0].text == 502
		),
		"Special client gets the source Wanted introduction and bounded chatter count"
	)
	var radio_state := Session.Mission.create(special_definition, 0, 375, lib, 19, 5)
	Session.Mission.advance(special_definition, radio_state, 2, lib)
	Session.Mission.Radio.advance(special_definition, radio_state, .01, lib)
	check(
		radio_state.radio.current == 0 and radio_state.radio.delay == 2,
		"Freelance opening radio obeys the corrected imported lead-in"
	)
	for actor in radio_state.actors:
		actor.awake = true
	Session.Mission.damage(special_definition, radio_state, 0, 10000)
	for index in 120:
		Session.Mission.advance(special_definition, radio_state, .25, lib)
		Session.Mission.Radio.advance(special_definition, radio_state, .25, lib)
	check(
		(
			radio_state.ready
			and radio_state.radio.shown.has(special_definition.radio.size() - 1)
			and Session.Mission.Radio.finished(special_definition, radio_state)
		),
		"Target completion naturally delivers special-client thanks and the player's reply"
	)
	for mode in ["divisor", "actor", "bounds", "text", "scenery", "combat"]:
		var invalid := parameters.duplicate(true)
		match mode:
			"divisor":
				invalid.factory_divisor = 0
			"actor":
				invalid.target_actors = [10000]
			"bounds":
				invalid.route_bounds[0] = [5, -5]
			"text":
				invalid.radio.special_start[0] = lib.strings.size()
			"scenery":
				invalid.asteroids = {}
			"combat":
				invalid.combat.motion = {}
		var rejected := true
		for seed_value in 4:
			if not ContractEncounters.hunt(lib, invalid, offer, 5, seed_value).is_empty():
				rejected = false

		check(rejected, "Reject invalid hunt " + mode)
	var forged := offer.duplicate(true)
	forged.reward += 500
	check(
		ContractEncounters.hunt(lib, parameters, forged, 5, 37).is_empty(),
		"Encounter construction rejects a changed quote rather than accepting fabricated terms"
	)
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var dispatch: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = dispatch + reader.u32(dispatch + 4)
	var changed := source.duplicate()
	changed.encode_float(literal_file_offset(reader, start + 0x214), 5.0)
	changed.encode_s32(literal_file_offset(reader, start + 0x58), 70000)
	reader.bytes = changed
	reader.error = ""
	var altered := reader.contract_hunt()
	var rebuilt := ContractEncounters.hunt(lib, altered, offer, 5, 37)
	check(
		(
			not rebuilt.is_empty()
			and rebuilt.groups.size() == 5
			and rebuilt.route[0][2] == definition.route[0][2] + 10000
		),
		"Changing supplied escort-count and route constants changes the native encounter"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(start + 0x21e, 2), 0x3801)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.contract_hunt().is_empty() and not reader.error.is_empty(),
		"Unknown encounter count arithmetic is rejected rather than treated as the supported source policy"
	)


func check_freelance_guns(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.hunt
	var guns: Dictionary = parameters.freelance_guns
	check(
		guns.region_damage and guns.alternate_actor == 1,
		"Freelance guns import regional scaling and the alternate actor association"
	)
	check(
		guns.alternate_weapon.pool_id == 144 and parameters.combat.weapon.pool_id == 124,
		"Original fighter families retain separate shared projectile pools"
	)
	for region in 4:
		for actor in [0, 1]:
			var weapon := ContractEncounters.weapon(parameters, actor, region)
			var definition := {"groups": [{"actor": actor, "count": 1, "weapon": weapon}]}
			var profile: Dictionary = lib.definition_weapons(definition, 5)[-1]
			check(
				profile.damage == 3 + region,
				"Freelance rank-five damage includes region %d for actor %d" % [region, actor]
			)
			check(
				profile.pool_id == (144 if actor == 1 else 124),
				"Freelance weapon pool follows the actor, independently of client race"
			)
	var profiles := {
		-1: ContractEncounters.weapon(parameters, 0, 3),
		-2: ContractEncounters.weapon(parameters, 1, 3),
		-3: ContractEncounters.weapon(parameters, 0, 3)
	}
	var combat := Combat.create()
	for index in int(profiles[-1].pool_capacity):
		combat.cooldowns.clear()
		check(
			Combat.fire(combat, -1, Vector3.ZERO, Vector3.FORWARD, lib, profiles),
			"Fill the first family projectile pool"
		)
	check(
		not Combat.fire(combat, -3, Vector3.ZERO, Vector3.FORWARD, lib, profiles),
		"Another fighter of the same family shares its exhausted projectile pool"
	)
	check(
		Combat.fire(combat, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles),
		"The other source fighter family can fire with its independent pool"
	)
	check(
		Combat.valid(JSON.parse_string(JSON.stringify(combat)), lib, profiles),
		"Freelance projectiles in both source pools survive JSON serialization"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index freelance gun source")
	var assign: int = reader.symbols["__ZN5Level10assignGunsEv"][0]
	var actor_offset := reader.file_offset(assign + 0xbca, 2)
	var region_offset := reader.file_offset(assign + 0x76, 2)
	var damaged := source.duplicate()
	damaged.encode_u16(actor_offset, 0x2810)
	reader.bytes = damaged
	var changed := reader.contract_gun_data()
	check(
		not changed.is_empty() and changed.alternate_actor == 16,
		"Changing the source actor association changes imported gun selection"
	)
	damaged = source.duplicate()
	damaged.encode_u16(region_offset, 0x1a36)
	reader.bytes = damaged
	reader.error = ""
	check(
		reader.contract_gun_data().is_empty() and not reader.error.is_empty(),
		"Unknown regional arithmetic is rejected instead of retaining assumed scaling"
	)
	var invalid := parameters.duplicate(true)
	invalid.freelance_guns.alternate_weapon.pool_capacity = 0
	check(
		not ContractEncounters.valid_parameters(invalid, lib),
		"Invalid cached alternate weapon profile is rejected"
	)
	invalid = parameters.duplicate(true)
	invalid.erase("freelance_guns")
	check(
		not ContractEncounters.valid_parameters(invalid, lib),
		"Old imported encounter cache must be regenerated for source gun associations"
	)


func check_transport_declarations(source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index transport route source")
	var parameters := reader.contract_transport()
	check(not parameters.is_empty(), "Read transport declarations: " + reader.error)
	if parameters.is_empty():
		return
	check(
		parameters.types == [9, 10] and parameters.family == "ambushed_route",
		"Passenger and Delivery share the imported route encounter"
	)
	check(
		(
			parameters.route_axes
			== [
				{"base": -2500, "rolls": [5000]},
				{"base": -2500, "rolls": [5000]},
				{"base": 70000, "rolls": [30000]},
				{"base": -2500, "rolls": [5000]},
				{"base": -2500, "rolls": [5000]},
				{"base": 117500, "rolls": [20000, 5000]},
				{"base": -2500, "rolls": [5000]},
				{"base": 170000, "rolls": [20000]},
				{"base": 0, "rolls": []}
			]
		),
		"Route import preserves all axes and the middle waypoint's two-roll distribution"
	)
	check(
		parameters.scenery_choices == 3 and parameters.asteroids.count == 40,
		"Transport scenery includes original field, fog, or no additional scenery"
	)
	check(
		(
			parameters.count_base == 2
			and parameters.count_divisor == 10.0
			and parameters.count_factor == 4.0
			and parameters.relative_divisors == [1, 3, 7, 15]
		),
		"Transport actor count keeps relative difficulty and regional terms"
	)
	check(
		(
			parameters.heavy_actor == 18
			and parameters.heavy_role == 2
			and parameters.default_actor == 1
			and parameters.default_role == 0
		),
		"Transport retains source heavy and ordinary actor/role associations"
	)
	check(
		(
			parameters.deadline_ms == 240000
			and parameters.deadline_choices == 100
			and parameters.deadline_threshold == 49
			and parameters.failure_text == 403
			and parameters.success.kind == "route_finished"
		),
		"Transport has an optional four-minute deadline and route-based success"
	)
	var level: int = reader.symbols["__ZN5Level13createMissionEv"][0]
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = table + reader.u32(table + 4 + int(parameters.types[0]) * 4)
	var base_load := start + 0xd8
	var base_address := ((base_load + 4) & ~3) + (reader.u16(base_load) & 255) * 4
	var base_offset := reader.file_offset(base_address, 4)
	var store_offset := reader.file_offset(start + 0xfe, 2)
	var damaged := source.duplicate()
	damaged.encode_u32(base_offset, 180000)
	reader.bytes = damaged
	var changed := reader.contract_transport()
	check(
		not changed.is_empty() and changed.route_axes[7].base == 180000,
		"Source waypoint literal mutation changes the actual final Y declaration"
	)
	damaged = source.duplicate()
	damaged.encode_u16(store_offset, 0x6048)
	reader.bytes = damaged
	reader.error = ""
	check(
		reader.contract_transport().is_empty() and not reader.error.is_empty(),
		"Changed coordinate write is rejected rather than silently permuting route axes"
	)


func check_contract_sessions(lib) -> void:
	check_transport_sessions(lib)
	var pilot := Session.new()
	pilot.configure(lib)
	check(
		pilot.contract_offers().is_empty() and not pilot.begin_contract(0),
		"Campaign gates the freelance board"
	)
	pilot.skip_campaign()
	check(
		pilot.mission_definition().is_empty(),
		"Free flight does not inherit skipped campaign environment"
	)
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var board := pilot.contract_offers()
		for index in board.size():
			if (
				lib.content.contracts.hunt.types.any(func(kind): return kind == board[index].type)
				and board[index].tier >= 7
			):
				selected = index
				break
		if selected >= 0:
			break
	check(selected >= 0, "Find source-generated hunt with escorts")
	if selected < 0:
		return
	var offers := pilot.contract_offers()
	check(offers == pilot.contract_offers(), "Board remains stable during station visit")
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Skipped pilot and board restore: " + restored.error
	)
	check(restored.contract_offers() == offers, "Board is stable after JSON reload")
	for index in offers.size():
		if not Contracts.supported(lib, offers[index]):
			check(
				not pilot.begin_contract(index) and pilot.docked,
				"Unsupported board encounter cannot launch"
			)
	check(
		not pilot.begin_contract(-1) and not pilot.begin_contract(999),
		"Reject invalid contract selection"
	)
	var cash := pilot.credits
	var chapter := pilot.chapter
	var origin := pilot.station_id
	check(pilot.begin_contract(selected), "Accept imported hunt: " + pilot.error)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	check(
		flight.station == null and flight.ambience.get_child_count() == 0,
		"Freelance missions do not inherit a preview station or arbitrary asteroid obstacles"
	)
	check(
		flight.field_rocks.size() == pilot.active_job.scenery.rocks.size(),
		"Freelance field geometry contains the imported encounter's rocks"
	)
	flight.free()
	check(
		pilot.active_job.kind == "contract" and pilot.mission_available() and not pilot.docked,
		"Contract uses native active mission"
	)
	check(
		(
			not pilot.begin_contract(selected)
			and not pilot.arrive(origin)
			and not pilot.travel(origin + 1)
		),
		"Active contract cannot be replaced or settled early"
	)
	var accepted := pilot.capture()
	var retry := Session.new()
	retry.configure(lib)
	check(retry.restore(accepted), "Restore hunt for defeat/retry")
	retry.retry_mission()
	check(
		(
			retry.docked
			and retry.contract_rewards.is_empty()
			and retry.credits == cash
			and retry.mission_definition().is_empty()
		),
		"Retry clears encounter without paying reward"
	)
	check(retry.begin_contract(selected), "Unpaid contract can be retried")
	check(
		restored.restore(JSON.parse_string(JSON.stringify(accepted))),
		"Restore accepted hunt: " + restored.error
	)
	check(
		restored.mission_definition() == pilot.mission_definition(),
		"Reload regenerates identical encounter definition"
	)
	check(
		restored.actor_weapons() == pilot.actor_weapons(),
		"Reload retains rank-derived contract weapons"
	)
	var forged := accepted.duplicate(true)
	forged.active_job.contract = null
	check(not restored.restore(forged), "Reject malformed contract reference")
	forged = accepted.duplicate(true)
	forged.active_job.contract.visit += 1
	check(not restored.restore(forged), "Reject contract from another visit")
	forged = accepted.duplicate(true)
	forged.active_job.seed += 1
	check(not restored.restore(forged), "Reject modified encounter seed")
	forged = accepted.duplicate(true)
	forged.active_job.rank += 1
	check(not restored.restore(forged), "Reject modified contract rank")
	check(pilot.active_job.actors.size() > 1, "Selected hunt has escorts")
	for actor in pilot.active_job.actors:
		actor.awake = true
	pilot.damage_actor(1, 100000)
	check(
		not pilot.active_job.ready, "Escort casualty does not complete designated-target contract"
	)
	pilot.advance_mission(2.1)
	pilot.advance_radio(.01)
	pilot.damage_actor(0, 100000)
	check(not pilot.active_job.ready, "Session keeps hunt active until target destruction finishes")
	finish_wrecks_fixture(pilot.mission_definition(),pilot.active_job,lib)
	check(
		pilot.active_job.ready and not pilot.ready_to_finish(),
		"Contract success waits for triggered dialogue"
	)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Restore success while closing radio pending: " + restored.error
	)
	for tick in 1200:
		pilot.advance_mission(.1)
		pilot.advance_radio(.1)
		if pilot.ready_to_finish():
			break
	check(pilot.ready_to_finish(), "Imported hunt closing dialogue drains")
	var prior_rating: int = pilot.rating
	var expected_rating: int = Session.Travel.after_mission(
		lib.content.travel, prior_rating, int(offers[selected].client.race)
	)
	check(pilot.finish_mission(), "Settle successful contract at its origin")
	check(pilot.rating == expected_rating, "Contract settlement uses the actual client's faction")
	check(
		pilot.credits == cash + int(offers[selected].reward) and pilot.contract_rewards.size() == 1,
		"Pay source quote exactly once"
	)
	check(
		(
			pilot.chapter == chapter
			and pilot.campaign_state == "skipped"
			and pilot.progression.rewards.is_empty()
		),
		"Contract payment never invents campaign completion"
	)
	check(
		pilot.station_id == origin and pilot.docked and pilot.active_job.is_empty(),
		"Contract returns to originating station"
	)
	check(
		not pilot.finish_mission() and pilot.credits == cash + int(offers[selected].reward),
		"Repeated settlement does not duplicate reward"
	)
	check(pilot.rating == expected_rating, "Repeated settlement cannot duplicate faction progress")
	var paid := pilot.capture()
	check(
		restored.restore(JSON.parse_string(JSON.stringify(paid))),
		"Paid contract history survives reload: " + restored.error
	)
	check(
		restored.rank() == pilot.rank() and restored.earned_worth() == pilot.earned_worth(),
		"Contract earned worth survives reload"
	)
	var legacy_rating := paid.duplicate(true)
	legacy_rating.schema = 13
	legacy_rating.erase("rating")
	check(
		restored.restore(legacy_rating) and restored.rating == expected_rating,
		"Old contract receipts recover the completed client's faction on migration"
	)
	forged = paid.duplicate(true)
	forged.contract_rewards[0].payment += 50
	check(not restored.restore(forged), "Reject altered receipt payment")
	forged = paid.duplicate(true)
	forged.contract_rewards.append(forged.contract_rewards[0].duplicate(true))
	check(not restored.restore(forged), "Reject duplicate contract receipts")
	forged = accepted.duplicate(true)
	forged.contract_rewards = paid.contract_rewards.duplicate(true)
	check(not restored.restore(forged), "Reject restarting a paid contract")
	var legacy := Session.new()
	legacy.configure(lib)
	var old := legacy.capture()
	old.schema = 8
	old.erase("contract_rewards")
	check(
		restored.restore(old) and restored.contract_rewards.is_empty(),
		"Schema eight migrates without invented contract rewards"
	)
	old.schema = 7
	old.erase("progression")
	check(
		restored.restore(old),
		"Schema seven passes through both progression and contract migrations"
	)


func check_transport_sessions(lib) -> void:
	for kind in lib.content.contracts.transport.types:
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.skip_campaign()
		pilot.station_id = 375
		var selected := -1
		var offer := {}
		for seed_value in 1000:
			pilot.market_seed = seed_value
			var board := pilot.contract_offers()
			for index in board.size():
				if board[index].type != kind:
					continue
				var definition := pilot.build_contract(
					pilot.contract_reference(index), pilot.rank(), seed_value
				)
				if (
					definition.deadline_ms > 0
					and definition.groups.any(func(group): return group.actor == 18)
				):
					selected = index
					offer = board[index]
					break
			if selected >= 0:
				break
		check(selected >= 0, "Find timed transport with source heavy ambushers for persistence")
		if selected < 0:
			continue
		for category in pilot.loadout.fitted.size():
			if not pilot.loadout.fitted[category].is_empty():
				check(pilot.remove_equipment(category), "Unmount equipment before transport")
		var cash := pilot.credits
		var origin := pilot.station_id
		check(
			pilot.loadout.weapons().is_empty() and pilot.begin_contract(selected),
			"Route transport permits an unarmed pilot"
		)
		var definition := pilot.mission_definition()
		var accepted := pilot.capture()
		var restored := Session.new()
		restored.configure(lib)
		check(
			restored.restore(JSON.parse_string(JSON.stringify(accepted))),
			"Restore unarmed transport: " + restored.error
		)
		check(
			(
				restored.mission_definition() == definition
				and restored.actor_weapons() == pilot.actor_weapons()
			),
			"Transport reload regenerates route, ambushers and guided weapons"
		)
		check(
			not pilot.finish_mission() and not pilot.arrive(origin),
			"Transport cannot settle before route completion"
		)
		Session.Mission.reach_waypoint(definition, pilot.active_job)
		pilot.advance_mission(1.0)
		check(
			not pilot.ready_to_finish() and pilot.active_job.stage == 1,
			"First transport waypoint is only partial progress"
		)
		check(
			(
				restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
				and restored.active_job.stage == 1
			),
			"Transport reload retains visited waypoint and deadline progress"
		)
		restored.advance_mission(float(definition.deadline_ms) / 1000.0)
		check(
			(
				restored.active_job.failed
				and not restored.finish_mission()
				and restored.credits == cash
			),
			"Expired transport cannot pay its quoted reward"
		)
		restored.retry_mission()
		check(
			(
				restored.docked
				and restored.contract_rewards.is_empty()
				and restored.begin_contract(selected)
			),
			"Failed transport can restart without false payment"
		)
		while Session.Mission.route_pending(definition, pilot.active_job):
			Session.Mission.reach_waypoint(definition, pilot.active_job)
		check(
			(
				pilot.active_job.ready
				and pilot.active_job.actors.all(func(actor): return actor.hp > 0)
			),
			"Delivery succeeds with surviving ambushers; kills are not its objective"
		)
		drain_radio(pilot)
		check(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
			"Save completed transport before settlement: " + restored.error
		)
		check(
			restored.finish_mission() and restored.credits == cash + int(offer.reward),
			"Reloaded transport pays original quote"
		)
		check(
			(
				restored.station_id == origin
				and restored.docked
				and restored.contract_rewards.size() == 1
			),
			"Transport returns to issuing station and records one receipt"
		)
		check(
			(
				restored.campaign_state == "skipped"
				and restored.chapter == 0
				and restored.progression.rewards.is_empty()
			),
			"Transport never fabricates campaign progress"
		)
		check(
			not restored.finish_mission() and restored.credits == cash + int(offer.reward),
			"Transport receipt prevents repeated settlement"
		)
		check(
			(
				pilot.restore(JSON.parse_string(JSON.stringify(restored.capture())))
				and pilot.earned_worth() == restored.earned_worth()
			),
			"Paid transport and rank history survive reload"
		)


func check_briefing(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	check(
		pilot.begin_briefing() and pilot.briefing_page == 0,
		"Campaign opens first imported briefing page"
	)
	var state := pilot.capture()
	for tick in 200:
		pilot.advance_mission(1)
		pilot.advance_radio(1)
	check(pilot.capture() == state, "Briefing does not run mission or radio timers")
	check(
		lib.briefing_cue(0, 0).speaker == -1 and lib.briefing_cue(0, 5).speaker == -1,
		"Opening narration omits portraits"
	)
	check(
		(
			lib.briefing_cue(0, 6).speaker == lib.content.chapters[0].speaker
			and not lib.briefing_cue(0, 6).left
		),
		"First spoken briefing page uses chapter speaker on right"
	)
	check(
		(
			lib.briefing_cue(0, 7).speaker == lib.content.briefing_ui.protagonist
			and lib.briefing_cue(0, 7).left
		),
		"Next briefing page uses source protagonist portrait on left"
	)
	for page in 7:
		check(pilot.next_briefing_page(), "Advance briefing with confirmation")
	var restored := Session.new()
	restored.configure(lib)
	check(
		(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and restored.briefing_page == 7
		),
		"Save and reload exact briefing page"
	)
	restored.previous_briefing_page()
	check(
		restored.briefing_page == 6 and restored.docked, "Back changes dialogue page without flight"
	)
	var forged := pilot.capture()
	forged.briefing_page = lib.content.chapters[0].dialogue.size()
	check(not restored.restore(forged), "Reject out-of-bounds briefing page")
	forged = pilot.capture()
	forged.briefing_page = .5
	check(not restored.restore(forged), "Reject noninteger briefing page")
	forged = pilot.capture()
	forged.docked = false
	check(not restored.restore(forged), "Reject briefing during flight")
	while pilot.briefing_page + 1 < lib.content.chapters[0].dialogue.size():
		pilot.next_briefing_page()
	check(pilot.docked and pilot.active_job.is_empty(), "Last briefing page still awaits Start")
	check(
		(
			pilot.next_briefing_page()
			and not pilot.docked
			and pilot.briefing_page == -1
			and pilot.active_job.kind == "campaign"
		),
		"Start leaves briefing and begins campaign mission"
	)
	forged = pilot.capture()
	forged.briefing_page = 0
	check(not restored.restore(forged), "Reject active mission combined with briefing")
	pilot.retry_mission()
	pilot.begin_briefing()
	pilot.previous_briefing_page()
	check(pilot.briefing_page == -1 and pilot.docked, "Back on first page returns to station")
	pilot.begin_briefing()
	pilot.skip_campaign()
	check(
		pilot.briefing_page == -1 and not pilot.begin_briefing() and pilot.exploration_unlocked(),
		"Campaign skip clears briefing without false completion"
	)
	check(restored.restore(pilot.capture()), "Skipped pilot with cleared briefing remains valid")
	pilot.configure(lib)
	var old := pilot.capture()
	old.schema = 9
	old.erase("briefing_page")
	check(
		restored.restore(old) and restored.briefing_page == -1,
		"Old pilot does not invent unfinished briefing"
	)
	var pages := 0
	for chapter in lib.content.chapters.size():
		for page in lib.content.chapters[chapter].dialogue.size():
			var cue: Dictionary = lib.briefing_cue(chapter, page)
			check(
				not cue.is_empty() and cue.text == lib.content.chapters[chapter].dialogue[page],
				"Briefing uses imported page text"
			)
			pages += 1
	print("BRIEFING PAGES ", pages)
	for key in ["normal", "pressed", "center_normal", "center_pressed"]:
		var texture: Texture2D = lib.ui_image(lib.content.briefing_ui.footer[key])
		check(
			texture != null and texture.get_width() > 0, "Original briefing footer sprite: " + key
		)


func check_briefing_source(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Open source briefing declarations")
	var layout := reader.briefing_presentation()
	check(
		reader.error.is_empty() and layout.panel == [35, 200, 410, 80] and layout.text_width == 370,
		"Read original briefing panel and text width"
	)
	check(
		layout.narration_pages == 6 and layout.labels.next == 112 and layout.labels.start == 113,
		"Read narration and confirmation labels"
	)
	check(
		(
			layout.footer.normal.texture == 3
			and layout.footer.pressed.texture == 3
			and layout.footer.normal.region != layout.footer.pressed.region
		),
		"Both footer bindings resolve texture register correctly"
	)
	var draw := reader.symbol_address("__ZN9MBriefing10OnRender2DEv")
	reader.bytes.encode_u16(reader.file_offset(draw + 0x70, 2), 0x23c8)
	var changed := reader.briefing_presentation()
	check(changed.panel[2] == 400, "Panel width follows source mutation")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(draw + 0xec, 2), 0x2803)
	changed = reader.briefing_presentation()
	check(changed.narration_pages == 4, "Narration count follows source mutation")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(draw + 0x74, 2), 0)
	check(
		reader.briefing_presentation().is_empty() and not reader.error.is_empty(),
		"Reject unsupported briefing drawing association"
	)


func check_dialogue_modality(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.depart(), "Tutorial modality fixture starts the source mission")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	# Exercise the actual flight clock, including time acceleration, rather than
	# advancing the radio in isolation. No confirmation events are sent.
	for tick in 270:
		flight._physics_process(1.0 / 60.0)
	check(not pilot.radio_cue().is_empty(), "Tutorial radio becomes visible during flight")
	var before := pilot.capture()
	var position: Vector3 = flight.ship.position
	var remaining: float = pilot.active_job.radio.remaining
	flight.time_factor = 2
	for tick in 30:
		flight._physics_process(1.0 / 60.0)
	check(
		flight.ship.position.distance_to(position) > 0 and not flight.paused,
		"Tutorial radio does not freeze the ship or require confirmation"
	)
	check(
		(
			flight.time_factor == 2
			and is_equal_approx(pilot.elapsed - float(before.elapsed), 1.0)
			and is_equal_approx(remaining - float(pilot.active_job.radio.remaining), .5)
		),
		"Safe tutorial acceleration advances flight twice as fast while preserving radio reading time"
	)
	flight.pause(true)
	before = pilot.capture()
	position = flight.ship.position
	for tick in 600:
		flight._physics_process(1.0)
	check(
		pilot.capture() == before and flight.ship.position == position,
		"Explicit pause holds mission, ship, combat and visible radio for an arbitrarily long wait"
	)
	var copy := Session.new()
	copy.configure(lib)
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(before)))
			and copy.radio_cue() == pilot.radio_cue()
			and is_equal_approx(copy.active_job.radio.remaining, pilot.active_job.radio.remaining)
		),
		"Paused radio reload preserves the current cue and remaining reading time"
	)
	var cue_index: int = pilot.active_job.radio.current
	flight.pause(false)
	for tick in 900:
		flight._physics_process(1.0 / 60.0)
		if int(pilot.active_job.radio.current) != cue_index:
			break
	check(
		int(pilot.active_job.radio.current) != cue_index and not flight.paused,
		"Resuming lets tutorial radio expire and advance without acknowledgement"
	)
	flight.free()

	pilot = Session.new()
	pilot.configure(lib)
	pilot.chapter = 11
	pilot.progression = Session.Progression.create(11)
	pilot.station_id = lib.chapter_destination(10)
	check(pilot.depart(), "Pursuit modality fixture starts the source mission")
	var definition: Dictionary = pilot.mission_definition()
	# Isolate the imported conversation transitions; full battle replay is separate.
	commit_pursuit_event(definition, pilot.active_job, lib)
	flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	flight.throttle = 1.0
	position = flight.ship.position
	flight._physics_process(.02)
	check(
		flight.cinematic_locked() and flight.ship.position.distance_to(position) > 0,
		"Capturing controls for the first camera cue does not implicitly freeze the pilot"
	)
	commit_pursuit_event(definition, pilot.active_job, lib)
	position = flight.ship.position
	before = pilot.capture()
	flight._physics_process(.02)
	check(
		(
			flight.ship.position == position
			and flight.speed == 40
			and not flight.paused
			and pilot.elapsed > before.elapsed
			and pilot.active_job.radio.remaining < before.active_job.radio.remaining
		),
		"Explicit source freeze holds player motion while mission and timed dialogue continue"
	)
	copy = Session.new()
	copy.configure(lib)
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and (
				Session
				. Mission
				. Sequence
				. directives(copy.mission_definition(), copy.active_job)
				. frozen
			)
		),
		"Saved conversation restores the imported freeze from committed milestones"
	)
	commit_pursuit_event(definition, pilot.active_job, lib)
	flight._physics_process(.02)
	check(
		not flight.cinematic_locked() and flight.ship.position.distance_to(position) > 0,
		"Finished source reply releases player freeze and controls without confirmation"
	)
	flight.free()


func check_player_motion(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.player_motion
	check(
		(
			same_saved_value(parameters, {
				"cruise_speed": 40.0,
				"boost_speed": 100.0,
				"boost_seconds": 5.0,
				"recharge_seconds": 20.0,
				"contact": {"damage": 5, "interval": .5, "forward_keep": .5}
			})
		),
		"Original millisecond-based speed and boost pulse/recharge are imported"
	)
	var reference := Session.Motion.create()
	var whole := Session.Motion.advance(reference, parameters, 7.0, true)
	check(
		(
			is_equal_approx(whole.forward, 580)
			and reference.boost_remaining == 0
			and reference.cooldown == 18
		),
		"A step across boost expiry integrates five boosted and two cruising seconds"
	)
	for hz in [30, 60, 120]:
		var state := Session.Motion.create()
		var distance := 0.0
		for tick in 7 * hz:
			distance += float(
				Session.Motion.advance(state, parameters, 1.0 / hz, tick == 0).forward
			)
		check(
			(
				is_equal_approx(distance, whole.forward)
				and is_equal_approx(state.cooldown, reference.cooldown)
			),
			"Boost travel and recharge agree across %d Hz and a single large step" % hz
		)
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.depart()
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	flight.ship.position = Vector3(2000, 0, 2000)
	var position: Vector3 = flight.ship.position
	flight.step(1)
	check(
		is_equal_approx(position.distance_to(flight.ship.position), 40),
		"Real flight uses source cruise immediately without prototype acceleration"
	)
	flight.controls.axes[JOY_AXIS_LEFT_X] = 1.0
	position = flight.ship.position
	flight.step(1)
	check(
		is_equal_approx(position.distance_to(flight.ship.position), 40),
		"Modern diagonal strafing stays inside the source cruise limit"
	)
	flight.controls.clear()
	flight.throttle = .5
	flight.controls.touch_boost = true
	flight.step(2.5)
	check(
		pilot.motion.boost_remaining == 2.5 and flight.speed == 100,
		"One boost press starts the source pulse even at reduced throttle"
	)
	var copy := Session.new()
	copy.configure(lib, true)
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and copy.motion == pilot.motion
		),
		"Boost phase and modern throttle survive JSON reload"
	)
	var saved := pilot.capture()
	var bad := saved.duplicate(true)
	bad.motion.cooldown = 1
	check(not copy.restore(bad), "A save cannot boost and recharge simultaneously")
	bad = saved.duplicate(true)
	bad.motion.boost_remaining = parameters.boost_seconds + 1
	check(not copy.restore(bad), "Reject saved boost beyond its source duration")
	bad = saved.duplicate(true)
	bad.motion.throttle = NAN
	check(not copy.restore(bad), "Reject non-finite throttle")
	bad = saved.duplicate(true)
	bad.erase("motion")
	check(not copy.restore(bad), "Current save schema requires motion state")
	var legacy := saved.duplicate(true)
	legacy.schema = 10
	legacy.erase("motion")
	check(
		copy.restore(legacy) and copy.motion == Session.Motion.create(),
		"Legacy pilots migrate to source cruise with a ready boost"
	)
	for tick in 1800:
		flight.step(1.0 / 60.0)
	check(
		(
			pilot.motion.boost_remaining == 0
			and pilot.motion.cooldown == 0
			and is_equal_approx(flight.speed, 20)
		),
		"Holding boost through recharge does not repeat the timed pulse"
	)
	flight.controls.touch_boost = false
	flight.step(.1)
	flight.controls.touch_boost = true
	flight.step(.1)
	check(
		is_equal_approx(pilot.motion.boost_remaining, 4.9),
		"Release and press activates the next fully recharged boost"
	)
	flight.pause(true)
	var frozen := pilot.motion.duplicate(true)
	flight._physics_process(30)
	check(pilot.motion == frozen, "Pause does not consume boost or recharge")
	flight.free()

	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index original player motion declarations")
	var ctor := reader.symbol_address("__ZN9PlayerEgoC2EP6Player")
	var boost := reader.symbol_address("__ZN9PlayerEgo5boostEv")
	var update := reader.symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera")
	var render := reader.symbol_address("__ZN5MGame10OnRender3DEv")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(ctor + 0xbe, 2), 0x2303)
	changed.encode_u16(reader.file_offset(update + 0xa4, 2), 0x2303)
	changed.encode_u16(reader.file_offset(boost + 0x20, 2), 0x2307)
	changed.encode_s32(literal_file_offset(reader, update + 0x9e), 4000)
	changed.encode_s32(literal_file_offset(reader, update + 0xa8), -12000)
	reader.bytes = changed
	var recovered := reader.player_motion()
	check(
		(
			same_saved_value(recovered, {
				"cruise_speed": 60.0,
				"boost_speed": 140.0,
				"boost_seconds": 4.0,
				"recharge_seconds": 12.0,
				"contact": {"damage": 5, "interval": .5, "forward_keep": .5}
			})
		),
		"Native motion follows changed IPA speed and timing declarations"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(render + 0x4a, 2), 0)
	reader.error = ""
	check(
		reader.player_motion().is_empty() and not reader.error.is_empty(),
		"Unsupported source clock association fails rather than guessing time units"
	)


func check_opening_encounter(source: PackedByteArray, lib) -> void:
	var definition: Dictionary = lib.mission_definition(0)
	var targets: Dictionary = definition.groups[0]
	var companion: Dictionary = definition.groups[1]
	check(
		targets.count == 5 and targets.actor == 8 and targets.unarmed and not targets.has("weapon"),
		"Source training targets are five unarmed drones"
	)
	check(
		targets.motion.speed == 20 and targets.sleeping and not targets.after_route,
		"Opening drones use source speed and proximity activation"
	)
	check(
		(
			targets.scatter.size() == 3
			and targets.scatter.all(func(axis): return axis[0] == -32000 and axis[1] == 31999)
		),
		"Opening uses the factory scatter cube instead of a presentation formation"
	)
	check(
		(
			companion.actor == 0
			and Combat.vector(companion.center) == Vector3(1000, -1000, 3000)
			and companion.route == definition.route
		),
		"Christine's source hull, relative placement and cloned route are imported"
	)
	check(
		(
			definition.scenery[0].waypoint == 1
			and definition.scenery[0].variant == 0
			and definition.fog.waypoint == 0
		),
		"Opening asteroid field and nebula use distinct source waypoints"
	)
	var state := Session.Mission.create(definition, 0, 0, lib, 22)
	check(
		state.actors.size() == 6 and state.target == 5 and not state.actors[0].awake,
		"Companion participates without adding to enemy objective"
	)
	check(
		Session.Mission.valid(definition, state, 0, 0, lib),
		"New opening encounter passes state validation"
	)
	var target: Dictionary = state.actors[0]
	var center := Combat.vector(target.position)
	var half_width := float(targets.motion.wake_half_width)
	# Isolate one target to test the activation boundary without a nearer ally.
	var isolated := definition.duplicate(true)
	isolated.groups = [targets.duplicate(true)]
	isolated.groups[0].count = 1
	var sample := Session.Mission.create(isolated, 0, 0, lib, 22)
	var projectiles := Combat.create()
	Session.Encounters.advance(
		isolated,
		sample,
		.1,
		center + Vector3(half_width + .01, 0, 0),
		Vector3.ZERO,
		projectiles,
		lib,
		{}
	)
	check(not sample.actors[0].awake, "Sleeping target does not wake outside source proximity cube")
	check(
		not Session.Mission.damage(isolated, sample, 0, 1),
		"Sleeping target cannot be shot before activation"
	)
	Session.Encounters.advance(
		isolated, sample, .1, center + Vector3(half_width, 0, 0), Vector3.ZERO, projectiles, lib, {}
	)
	check(
		sample.actors[0].awake and sample.stage == 0,
		"Proximity wakes target before player finishes route"
	)
	var before := Combat.vector(sample.actors[0].position)
	Session.Encounters.advance(
		isolated,
		sample,
		.25,
		center + Vector3(half_width, 0, 0),
		Vector3.ZERO,
		projectiles,
		lib,
		{}
	)
	check(
		is_equal_approx(before.distance_to(Combat.vector(sample.actors[0].position)), 10),
		"Awake target uses source fighter current speed, not generic KIPlayer speed"
	)
	check(
		sample.actors[0].shots == 0 and projectiles.projectiles.is_empty(),
		"Unarmed target cannot fire native projectiles"
	)
	var reader := NativeData.new()
	check(
		not reader.extract(source).is_empty(),
		"Opening declaration reader recognizes supplied executable"
	)
	reader.bytes = source
	check(reader.parse_macho(), "Opening source mutation fixture parses metadata")
	var bounds := reader.campaign_boundaries(lib.content.chapters.size())
	var speeds := reader.calls_between(bounds[0], bounds[1], "__ZN8KIPlayer8setSpeedEf")
	var ships := reader.calls_between(bounds[0], bounds[1], "__ZN5Level10createShipEiiibP8Waypoint")
	var fields := reader.calls_between(bounds[0], bounds[1], "__ZN13AsteroidFieldC1EiP8Waypoint")
	var changed := source.duplicate()
	changed.encode_float(literal_file_offset(reader, speeds[0] - 6), 1.5)
	changed.encode_u16(reader.file_offset(fields[0] - 34, 2), 0x2102)
	var role_offset := reader.file_offset(ships[0] - 12, 2)
	var imported := reader.extract(changed)
	check(
		not imported.is_empty(),
		"Compatible opening parameter changes remain importable: " + reader.error
	)
	if not imported.is_empty():
		check(
			(
				imported.missions[0].groups[0].motion.speed == 30
				and imported.missions[0].scenery[0].waypoint == 2
			),
			"Opening speed and field location come from supplied bytes"
		)
	changed = source.duplicate()
	changed.encode_u16(role_offset, 0x2204)
	check(reader.extract(changed).is_empty(), "Unknown target role is rejected rather than guessed")
	check_opening_legacy(lib)


func check_opening_legacy(lib) -> void:
	# Schema 11 held a fixed formation without a companion or field. Preserve
	# actual old kills, partial damage, radio, position, motion and currency.
	var definition: Dictionary = lib.mission_definition(0)
	var targets: Dictionary = definition.groups[0]
	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.depart(), "Opening migration fixture departs")
	var legacy_definition := definition.duplicate(true)
	legacy_definition.groups = [
		{
			"count": targets.count,
			"actor": targets.actor,
			"center": targets.center,
			"scatter": [],
			"after_route": true
		}
	]
	legacy_definition.erase("scenery")
	legacy_definition.erase("fog")
	var old := pilot.capture()
	old.schema = 11
	# Encode the old serialized shape directly. Today's constructor correctly
	# rejects the preview's unauthored formation, so it cannot create schema11.
	old.active_job.actors = []
	old.active_job.erase("tutorial")
	old.active_job.scenery = {"rocks":[],"contact_cooldown":0.0}
	var legacy_hull: float = lib.group_initial_hull(legacy_definition.groups[0], pilot.rank())
	for index in int(targets.count):
		old.active_job.actors.append({"group":0,"hp":legacy_hull,"position":[float(index*20),0.0,-100.0]})
	old.active_job.stage = definition.route.size()
	old.active_job.kills = 1
	old.active_job.actors[0].hp = 0.0
	old.active_job.actors[1].hp -= 3
	var old_position: Array = old.active_job.actors[1].position.duplicate()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(old))),
		"Schema 11 opening save migrates: " + copy.error
	)
	if not copy.active_job.is_empty():
		check(
			(
				copy.active_job.kills == 1
				and copy.active_job.actors[0].hp == 0
				and copy.active_job.actors.size() == 6
			),
			"Migration retains destroyed target and introduces companion"
		)
		check(
			(
				same_saved_value(copy.active_job.actors[1].position, old_position)
				and copy.active_job.actors[1].hp == lib.group_initial_hull(targets, copy.rank()) - 3
			),
			"Migration retains target position and damage with imported hull rule"
		)
		check(
			(
				copy.credits == old.credits
				and JSON.stringify(copy.motion) == JSON.stringify(old.motion)
				and (
					JSON.parse_string(JSON.stringify(copy.active_job.radio))
					== JSON.parse_string(JSON.stringify(old.active_job.radio))
				)
			),
			"Migration preserves currency, pilot motion and radio progress"
		)
		check(
			copy.restore(JSON.parse_string(JSON.stringify(copy.capture()))),
			"Migrated opening round-trips current save schema"
		)
	var broken := old.duplicate(true)
	broken.active_job.actors[1].hp = -1
	check(not copy.restore(broken), "Migration rejects corrupt preview damage")


func check_shared_projectile_pools(source: PackedByteArray, lib) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	var weapons: Dictionary = lib.definition_weapons(definition, 2)
	check(
		weapons[-1].pool_capacity == 20 and weapons[-1].pool_id == weapons[-4].pool_id,
		"All four escort attackers share the source twenty-projectile Gun"
	)
	check(
		weapons[-5].pool_capacity == 32 and weapons[-5].pool_id != weapons[-1].pool_id,
		"Companion has a separate source projectile pool"
	)
	var turret: Dictionary = (
		lib
		. mission_definition(9)
		. groups
		. filter(func(g): return g.get("behavior") == "turret")[0]
		. weapon
	)
	check(
		turret.pool_capacity == 1 and not turret.has("pool_id"),
		"Each source turret owns its single-projectile pool"
	)
	var scripted: Dictionary = lib.mission_definition(5).groups[1].weapon
	check(
		scripted.pool_capacity == 20 and not scripted.has("pool_id"),
		"Scripted fighter guns are individually allocated"
	)
	var separate := {-1: turret.duplicate(true), -2: turret.duplicate(true)}
	var isolated := Combat.create()
	check(
		(
			Combat.fire(isolated, -1, Vector3.ZERO, Vector3.FORWARD, lib, separate)
			and Combat.fire(isolated, -2, Vector3.ZERO, Vector3.FORWARD, lib, separate)
		),
		"Turrets with the same parameters can each launch their own projectile"
	)
	var state := Combat.create()
	check(
		Combat.fire(state, -1, Vector3.ZERO, Vector3.FORWARD, lib, weapons),
		"First NPC fires into its shared pool"
	)
	check(
		Combat.fire(state, -2, Vector3.ZERO, Vector3.FORWARD, lib, weapons),
		"Second NPC has its own cooldown despite shared projectiles"
	)
	check(
		not Combat.fire(state, -1, Vector3.ZERO, Vector3.FORWARD, lib, weapons),
		"Same shooter still observes its firing interval"
	)
	# Populate the remaining live slots to exercise saturation deterministically.
	for index in 18:
		state.cooldowns.clear()
		check(
			Combat.fire(state, -1 - (index % 4), Vector3.ZERO, Vector3.FORWARD, lib, weapons),
			"Shared projectile slot is available"
		)
	state.cooldowns.clear()
	var next_id := int(state.next_id)
	check(
		(
			not Combat.fire(state, -3, Vector3.ZERO, Vector3.FORWARD, lib, weapons)
			and state.next_id == next_id
			and state.projectiles.size() == 20
		),
		"Full NPC pool suppresses emission without consuming projectile IDs"
	)
	check(
		state.cooldowns[-3] == weapons[-3].interval,
		"Pool exhaustion still consumes the shooter's source firing interval"
	)
	check(
		Combat.fire(state, -5, Vector3.ZERO, Vector3.FORWARD, lib, weapons),
		"Saturated enemy pool does not suppress the ally"
	)
	var restored := Combat.normalize(JSON.parse_string(JSON.stringify(state)))
	check(
		Combat.valid(restored, lib, weapons),
		"Shared pool projectiles and individual cooldowns survive JSON reload"
	)
	Combat.advance(
		restored, float(weapons[-1].lifetime) + float(weapons[-1].interval), [], lib, weapons
	)
	check(
		Combat.fire(restored, -3, Vector3.ZERO, Vector3.FORWARD, lib, weapons),
		"Expired projectiles release shared capacity"
	)
	# Old previews could exceed the source pool. Keep their live shots on reload,
	# but prevent further emissions until enough of those shots expire or hit.
	var legacy := state.duplicate(true)
	var extra: Dictionary = legacy.projectiles[0].duplicate(true)
	extra.id = int(legacy.next_id)
	legacy.next_id += 1
	legacy.projectiles.append(extra)
	legacy.cooldowns.clear()
	check(
		(
			Combat.valid(legacy, lib, weapons)
			and not Combat.fire(legacy, -2, Vector3.ZERO, Vector3.FORWARD, lib, weapons)
		),
		"Legacy excess projectiles drain without deletion or additional firing"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Shared pool source mutation fixture parses")
	var assign := reader.symbol_address("__ZN5Level10assignGunsEv")
	var guns := reader.calls_between(
		assign, reader.symbol_end(assign), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"
	)
	var common := guns.filter(func(call): return reader.u16(call + 18) == 0x67c8)
	var friendly := guns.filter(
		func(call): return reader.u16(call + 22) == 0x2080 and reader.u16(call + 26) == 0x5031
	)
	var common_offset := reader.file_offset(common[0] - 4, 2)
	var friendly_offset := reader.file_offset(friendly[0] - 26, 2)
	var cooldown_offset := reader.file_offset(
		reader.symbol_address("__ZN6Player5shootEixb") + 0x54, 2
	)
	var changed := source.duplicate()
	changed.encode_u16(common_offset, 0x2207)
	changed.encode_u16(friendly_offset, 0x2209)
	var imported := reader.extract(changed)
	check(not imported.is_empty(), "Compatible shared pool counts import: " + reader.error)
	if not imported.is_empty():
		check(
			(
				imported.missions[3].groups[0].weapon.pool_capacity == 7
				and imported.missions[3].groups[1].weapon.pool_capacity == 9
			),
			"NPC projectile capacities come from supplied executable declarations"
		)
		check(
			(
				imported.missions[3].groups[0].weapon.speed == 320
				and imported.missions[3].groups[1].weapon.speed == 320
			),
			"Changing pool capacity does not change projectile speed"
		)
	changed = source.duplicate()
	changed.encode_u16(cooldown_offset, 0x46c0)
	check(
		reader.extract(changed).is_empty(),
		"Unknown cooldown ownership is rejected instead of assuming shared timing"
	)
	var bad := definition.duplicate(true)
	bad.groups.append(bad.groups[0].duplicate(true))
	bad.groups.back().weapon.pool_capacity += 1
	check(not lib.valid_mission(bad), "Conflicting capacities for one shared pool are rejected")


func check_fighter_aim(source: PackedByteArray, lib) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	var motion: Dictionary = definition.groups[0].motion
	check(
		motion.aim_sine == 800.0 / 65536.0 and is_equal_approx(motion.fire_half_width, 339.98),
		"Fighter tolerance is a normalized angle and firing range is the source cube"
	)
	check(
		Session.Encounters.firing_aligned(Vector3.FORWARD, Vector3(1, 0, -100), motion),
		"Target inside source horizontal tolerance permits firing"
	)
	check(
		not Session.Encounters.firing_aligned(Vector3.FORWARD, Vector3(2, 0, -100), motion),
		"Fighter cannot fire beyond horizontal angular tolerance"
	)
	check(
		not Session.Encounters.firing_aligned(Vector3.FORWARD, Vector3(0, 2, -100), motion),
		"Vertical tolerance is checked independently"
	)
	check(
		not Session.Encounters.firing_aligned(Vector3.FORWARD, Vector3(0, 0, 100), motion),
		"Target behind the ship cannot be fired at"
	)
	check(
		Session.Encounters.firing_aligned(
			Vector3.FORWARD, Vector3(0, 0, -float(motion.fire_half_width)), motion
		),
		"Fighter can fire at the source range boundary"
	)
	check(
		not Session.Encounters.firing_aligned(
			Vector3.FORWARD, Vector3(0, 0, -float(motion.fire_half_width) - .01), motion
		),
		"Long projectile lifetime does not extend fighter firing range"
	)
	var vertical := Vector3.UP
	check(
		Session.Encounters.firing_aligned(vertical, vertical * 100, motion),
		"Vertical ship heading has a stable native firing basis"
	)
	var isolated := definition.duplicate(true)
	isolated.groups = [definition.groups[0].duplicate(true)]
	isolated.groups[0].count = 1
	var state := Session.Mission.create(isolated, 3, 0, lib, 22, 2)
	state.actors[0].position = [0.0, 0.0, 0.0]
	state.actors[0].awake = true
	var combat := Combat.create()
	var weapons: Dictionary = lib.definition_weapons(isolated, 2)
	Session.Encounters.advance(
		isolated, state, .001, Vector3(1, 0, -100), Vector3(200, 0, 0), combat, lib, weapons
	)
	check(combat.projectiles.size() == 1, "Aligned fighter emits through the native encounter loop")
	if not combat.projectiles.is_empty():
		check(
			Combat.vector(combat.projectiles[0].velocity).normalized().is_equal_approx(
				Combat.vector(state.actors[0].heading)
			),
			"Fighter shot follows ship heading without predictive redirection or random spread"
		)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Fighter aim source mutation fixture parses")
	var ctor := reader.symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var update := reader.symbol_address("__ZN13PlayerFighter6updateEi")
	var shoot: int = (
		reader.calls_between(update, reader.symbol_end(update), "__ZN6Player5shootEixb")[0]
	)
	var bypass := reader.file_offset(
		reader.symbol_address("__ZN3Gun5shootEN11AbyssEngine6AEMath6MatrixEib") + 0x14, 2
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(ctor + 0x180, 2), 0x2264)
	changed.encode_s32(literal_file_offset(reader, shoot - 86), 23999)
	changed.encode_s32(literal_file_offset(reader, shoot - 78), 47998)
	changed.encode_s32(literal_file_offset(reader, shoot - 58), -24000)
	var imported := reader.extract(changed)
	check(
		not imported.is_empty(), "Compatible fighter aim and range changes import: " + reader.error
	)
	if not imported.is_empty():
		check(
			(
				imported.missions[3].groups[0].motion.aim_sine == 400.0 / 65536.0
				and is_equal_approx(imported.missions[3].groups[0].motion.fire_half_width, 479.98)
			),
			"Source angular threshold and range are data, not native constants"
		)
	changed = source.duplicate()
	changed.encode_u16(bypass, 0x2301)
	check(
		reader.extract(changed).is_empty(),
		"Unknown targeted discharge path is rejected instead of assumed forward fire"
	)


func check_turret_aim(source: PackedByteArray, lib) -> void:
	var definition: Dictionary = lib.mission_definition(6)
	var group: Dictionary = definition.groups[2]
	var tracking: Dictionary = group.tracking
	check(
		Session.Encounters.turret_firing_aligned(Vector3.FORWARD, Vector3(.4, .4, -100), tracking),
		"Turret accepts source per-axis angular bounds beyond a circular cone"
	)
	check(
		not Session.Encounters.turret_firing_aligned(
			Vector3.FORWARD, Vector3(.5, 0, -100), tracking
		),
		"Turret rejects an opponent beyond its horizontal tolerance"
	)
	check(
		not Session.Encounters.turret_firing_aligned(
			Vector3.FORWARD, Vector3(0, .5, -100), tracking
		),
		"Turret rejects an opponent beyond its vertical tolerance"
	)
	check(
		Session.Encounters.turret_firing_aligned(Vector3.FORWARD, Vector3(0, 0, 100), tracking),
		"Turret source has no fighter forward-hemisphere discharge gate"
	)
	check(
		Session.Encounters.turret_firing_aligned(
			Vector3.UP, Vector3.UP * tracking.range_half_width, tracking
		),
		"Vertical turret can fire at its source range boundary"
	)
	check(
		not Session.Encounters.turret_firing_aligned(
			Vector3.FORWARD, Vector3.FORWARD * (tracking.range_half_width + .01), tracking
		),
		"Turret range is independent of projectile lifetime"
	)
	var actor := {"hp": 90, "awake": true, "position": [0, 0, 0], "heading": [0, 0, -1], "shots": 0}
	var combat := Combat.create()
	var weapons: Dictionary = lib.definition_weapons(definition, 3)
	var target := {
		"position": Vector3(0, 0, -100), "velocity": Vector3(300, 0, 0), "team": "player"
	}
	Session.Encounters.advance_turret(group, actor, 4, [target], .1, combat, lib, weapons)
	check(
		actor.shots == 1,
		"Aligned turret fires at a fast crossing opponent without predictive leading"
	)
	check(
		Combat.vector(actor.heading).is_equal_approx(Vector3.FORWARD),
		"Target velocity cannot pull turret steering ahead of its current position"
	)
	if not combat.projectiles.is_empty():
		check(
			Combat.vector(combat.projectiles[0].velocity).normalized().is_equal_approx(
				Vector3.FORWARD
			),
			"Turret bolt inherits the mount direction"
		)
	actor.shots = 0
	actor.heading = [0, 0, -1]
	combat = Combat.create()
	target.position = Vector3(10, 0, -100)
	Session.Encounters.advance_turret(group, actor, 4, [target], 1, combat, lib, weapons)
	check(
		actor.shots == 0 and combat.projectiles.is_empty(),
		"Turret cannot rotate and discharge retroactively in the same update"
	)
	check(
		Combat.vector(actor.heading).is_equal_approx(target.position.normalized()),
		"Native mount steering acquires the present opponent position"
	)
	Session.Encounters.advance_turret(group, actor, 4, [target], .01, combat, lib, weapons)
	check(actor.shots == 1, "Acquired alignment permits discharge on the next update")
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Turret source mutation fixture parses")
	var start := reader.symbol_address("__ZN12PlayerTurret6updateEi")
	var changed := source.duplicate()
	changed.encode_s32(literal_file_offset(reader, start + 520), 399)
	changed.encode_s32(literal_file_offset(reader, start + 548), 798)
	changed.encode_s32(literal_file_offset(reader, start + 568), -400)
	reader.bytes = changed
	var altered := reader.turret_tracking()
	check(
		not altered.is_empty() and altered.aim_sine == 399.0 / 65536.0,
		"Compatible source angular bounds are imported instead of hardcoded"
	)
	changed.encode_s32(literal_file_offset(reader, start + 548), 700)
	reader.bytes = changed
	check(reader.turret_tracking().is_empty(), "Mismatched turret bound pairs are rejected")
	reader.bytes = source
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(start + 642, 2), 0x46c0)
	reader.bytes = changed
	reader.error = ""
	check(reader.turret_tracking().is_empty(), "Unknown turret discharge association is rejected")


func check_tutorial(source: PackedByteArray, lib) -> void:
	var config: Dictionary = lib.content.flight_ui.tutorial
	var tutorial = Session.Mission.Tutorial
	check(
		(
			config.chapter == 0
			and config.duration_ms == 7000
			and config.blink_limit_ms == 3999
			and config.blink_ms == 250
		),
		"Tutorial timing is recovered from the supplied iPhone build"
	)
	check(
		same_saved_value(
			config.steps,
			[
				{"radio": 6, "action": "weapon"},
				{"radio": 7, "action": "fire"},
				{"radio": -1, "action": "missiles"},
				{"radio": 9, "action": "boost"}
			]
		),
		"Imported tutorial links weapon, fire, missile and boost cues to radio selection"
	)
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index tutorial declarations")
	var start := reader.symbol_address("__ZN5MGame10OnRender2DEv")
	var address := start + 0x122
	var duration_pool := ((address + 4) & ~3) + (reader.u16(address) & 255) * 4
	reader.bytes.encode_u32(reader.file_offset(duration_pool, 4), 8000)
	reader.bytes.encode_u16(reader.file_offset(start + 0x10c, 2), 0x6958)
	for offset in [0x13c, 0x1d2, 0x23a, 0x2c6]:
		reader.bytes.encode_u16(reader.file_offset(start + offset, 2), 0x22c8)
	var changed := reader.tutorial_presentation()
	check(
		(
			reader.error.is_empty()
			and changed.duration_ms == 8000
			and changed.blink_ms == 200
			and changed.steps[0].radio == 5
		),
		"Tutorial message and duration follow changed IPA declarations"
	)
	for offset in [0xf0, 0xf4, 0x10c, 0x10e, 0x158, 0x204, 0x2c6]:
		reader.bytes = source.duplicate()
		reader.error = ""
		reader.bytes.encode_u16(reader.file_offset(start + offset, 2), 0)
		check(
			reader.tutorial_presentation().is_empty() and not reader.error.is_empty(),
			"Unsupported tutorial declaration is rejected at %x" % (start + offset)
		)
	for key in ["chapter", "duration_ms", "blink_limit_ms", "blink_ms", "steps"]:
		var invalid := config.duplicate(true)
		invalid.erase(key)
		check(not lib.valid_tutorial_ui(invalid), "Incomplete tutorial cache is rejected: " + key)
	var invalid := config.duplicate(true)
	invalid.steps[0].radio = 9999
	check(not lib.valid_tutorial_ui(invalid), "Tutorial cannot reference missing radio")
	invalid = config.duplicate(true)
	invalid.steps[0].action = "shoot_automatically"
	check(not lib.valid_tutorial_ui(invalid), "Tutorial actions are bounded presentation names")
	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.depart(), "Tutorial fixture starts campaign")
	var state: Dictionary = pilot.active_job.tutorial
	tutorial.advance(config, state, [], 50)
	check(
		state.index == 0 and state.elapsed_ms == -1 and tutorial.cue(config, state).is_empty(),
		"Elapsed objectives alone do not start queued radio highlights"
	)
	# Isolated selected-radio fixture. A selected message includes its lead-in,
	# while prior queued messages must keep the tutorial waiting.
	pilot.active_job.radio = {
		"shown": [0, 1, 2, 3, 4, 5, 6], "current": 6, "delay": 2.0, "remaining": 12.0
	}
	pilot.advance_radio(.01)
	check(
		state.elapsed_ms == 0 and pilot.radio_cue().is_empty(),
		"Highlight timeline starts during the selected radio lead-in"
	)
	pilot.advance_radio(3.0)
	check(pilot.tutorial_cue().is_empty(), "Tutorial preserves the initial non-blinking interval")
	pilot.advance_radio(.01)
	check(
		pilot.tutorial_cue().get("action") == "weapon",
		"Weapon highlight begins inside imported blink window"
	)
	var copy := Session.new()
	copy.configure(lib)
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and same_saved_value(copy.active_job.tutorial, state)
		),
		"JSON reload preserves active tutorial timer and blink phase"
	)
	var legacy := pilot.capture()
	legacy.schema = 12
	legacy.active_job.erase("tutorial")
	check(
		(
			copy.restore(JSON.parse_string(JSON.stringify(legacy)))
			and copy.active_job.tutorial.index == 1
			and copy.active_job.tutorial.elapsed_ms == -1
		),
		"Old saves skip previously selected tutorial messages without replaying stale highlights"
	)
	check(
		(
			same_saved_value(copy.active_job.radio, pilot.active_job.radio)
			and copy.hull == pilot.hull
			and copy.credits == pilot.credits
		),
		"Tutorial migration preserves radio, damage and rewards"
	)
	for change in [
		{"index": -1}, {"phase_ms": 500}, {"elapsed_ms": NAN}, {"index": 3, "elapsed_ms": 0}
	]:
		var bad := pilot.capture()
		bad.active_job.tutorial.merge(change, true)
		check(not copy.restore(bad), "Malformed or causally impossible tutorial save is rejected")
	var missing := pilot.capture()
	missing.active_job.erase("tutorial")
	check(not copy.restore(missing), "Current saves require applicable tutorial state")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	flight.time_factor = 2
	var previous := float(state.elapsed_ms)
	var elapsed := pilot.elapsed
	flight._physics_process(.02)
	check(
		(
			is_equal_approx(float(state.elapsed_ms) - previous, 20)
			and is_equal_approx(pilot.elapsed - elapsed, .04)
		),
		"Time acceleration preserves readable tutorial highlight timing"
	)
	flight.pause(true)
	var before := pilot.capture()
	for tick in 600:
		flight._physics_process(1)
	check(pilot.capture() == before, "Global pause preserves active tutorial and entire simulation")
	flight.free()
	var shown: Array = [6, 7, 9]
	state = tutorial.create(config)
	tutorial.advance(config, state, shown, .01)
	tutorial.advance(config, state, shown, 7)
	check(state.index == 0 and state.elapsed_ms == 7000, "Cue includes zero remaining time")
	tutorial.advance(config, state, shown, .001)
	check(
		state.index == 1 and state.elapsed_ms == 0,
		"Fire cue follows completed weapon cue and selected fire radio"
	)
	tutorial.advance(config, state, shown, 7.2)
	check(
		state.index == 2 and is_equal_approx(state.elapsed_ms, 200),
		"Automatic missile cue follows fire and carries frame overshoot"
	)
	tutorial.advance(config, state, shown, 7)
	check(
		state.index == 3 and state.elapsed_ms == 0,
		"Boost waits for prior highlights and its selected radio"
	)
	tutorial.advance(config, state, shown, 7.01)
	check(
		state.index == 4 and tutorial.cue(config, state).is_empty(),
		"Completed tutorial clears its highlight"
	)
	check(tutorial.valid(config, state, shown), "Completed tutorial save remains valid")
	check(
		(
			not tutorial.applies(config, {"kind": "campaign", "chapter": 1})
			and not tutorial.applies(config, {"kind": "contract", "chapter": 0})
		),
		"Later campaign missions and free contracts do not run opening tutorial"
	)


func check_sky(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.sky
	check(
		data.variant_count == 9 and data.cloud_meshes.size() == 6 and data.tints.size() == 4,
		"All source planet, nebula and sun variants are imported"
	)
	check(
		(
			lib.content.radio_ui.textures.has("9")
			and lib.content.radio_ui.textures["9"].ends_with("sun_white.aei")
		),
		"Texture registration accepts the source white-sun identifier register"
	)
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index original sky declarations")
	var start := reader.symbol_address("__ZN5Level12createSkyboxEib")
	var space := reader.symbol_address("__ZN5Level11createSpaceEv")
	var draw := reader.symbol_address("__ZN5Level8renderBGEj")
	var address := start + 0x2d8
	var pool := ((address + 4) & ~3) + (reader.u16(address) & 255) * 4
	reader.bytes.encode_u32(reader.file_offset(pool, 4), 4321)
	reader.bytes.encode_u16(reader.file_offset(space + 0x14c, 2), 0x2305)
	reader.bytes.encode_u16(reader.file_offset(draw + 0xb2, 2), 0x22b4)
	var changed := reader.sky_presentation()
	check(
		(
			reader.error.is_empty()
			and changed.seed_multiplier == 4321
			and changed.campaign_overrides[2] == 5
			and changed.tints[0][1] == 180
		),
		"Source mutation changes sky seed, chapter override and tint"
	)
	for fault in [start + 0xbe, start + 0xee, space + 0x78, draw + 0xdc]:
		reader.bytes = source.duplicate()
		reader.error = ""
		reader.bytes.encode_u16(reader.file_offset(fault, 2), 0)
		check(
			reader.sky_presentation().is_empty() and not reader.error.is_empty(),
			"Unknown sky construction or render declaration is rejected"
		)
	var background := Flight.Backdrop.new()
	var duplicate := Flight.Backdrop.new()
	var seen := {}
	for station in lib.stations.size():
		var selection: Dictionary = background.select(lib, station)
		check(
			(
				selection == duplicate.select(lib, station)
				and selection.variant == lib.station_definition(station).image
				and selection.style >= 0
				and selection.style < data.tints.size()
				and selection.cloud >= 0
				and selection.cloud < data.cloud_meshes.size()
			),
			"Station %d selects stable source backdrop variants" % station
		)
		seen[selection.variant] = true
	check(seen.size() == 9, "The supplied station catalogue exercises every planet layout")
	# Independently calculated standard 48-bit LCG reference outputs.
	check(
		background.select(lib, 0).style == 2 and background.select(lib, 0).cloud == 4,
		"Station-zero style and nebula match source seeded selection"
	)
	check(
		background.select(lib, 1).style == 2 and background.select(lib, 1).cloud == 5,
		"Second station matches independent random reference"
	)
	for chapter in lib.content.chapters.size():
		var station: int = (
			int(lib.content.initial.station_index)
			if chapter == 0
			else lib.chapter_destination(chapter - 1)
		)
		var expected: int = int(data.campaign_overrides[chapter])
		if expected < 0:
			expected = int(lib.station_definition(station).image)
		check(
			background.select(lib, station, chapter).variant == expected,
			"Campaign chapter %d uses its source sky override or origin" % chapter
		)
	background.free()
	duplicate.free()
	var original: Dictionary = lib.content.sky
	for key in ["base_mesh", "cloud_meshes", "campaign_overrides", "tints", "blends", "random"]:
		lib.content.sky = original.duplicate(true)
		lib.content.sky.erase(key)
		check(not lib.valid_sky(), "Missing sky cache declaration is rejected: " + key)
	lib.content.sky = original.duplicate(true)
	lib.content.sky.sun_texture_base = 1000
	check(not lib.valid_sky(), "Missing source sun texture is rejected")
	lib.content.sky = original.duplicate(true)
	lib.content.sky.random.output_bits = 49
	check(not lib.valid_sky(), "Unsafe sky random width is rejected")
	lib.content.sky = original
	check(lib.valid_sky(), "Source sky remains valid after mutation checks")


func check_materials(source: PackedByteArray, lib) -> void:
	check(
		lib.content.materials.size() == 7 and lib.model_materials.size() == 115,
		"All source mesh-to-material bindings are imported"
	)
	var data: Dictionary = lib.content.materials
	check(
		data["20003"].lit and data["20003"].blend == "opaque" and data["20003"].cull == "back",
		"Ship and station hulls use source lit opaque culled material"
	)
	check(
		data["20002"].blend == "add" and data["20002"].cull == "disabled",
		"Explosion material adds RGB and draws both faces"
	)
	check(
		data["20004"].texture == 5 and data["20005"].texture == 9 and data["20006"].blend == "mix",
		"Nebula, sun and shadow materials retain source atlas/blend associations"
	)
	var missing := []
	for name in lib.model_materials:
		var node: MeshInstance3D = lib.model(name)
		var identifier: int = lib.model_materials[name]
		if FileAccess.file_exists(lib.root.path_join("data/meshes/" + name + ".aem")):
			check(
				node.mesh != null and node.material_override == lib.material(identifier),
				"Original mesh resolves its registered cached material: " + name
			)
		else:
			missing.append(name)
			check(
				node.mesh == null and lib.error == "Missing model: " + name,
				"Missing original mesh is reported without invented replacement"
			)
		node.free()
	check(
		missing == ["st_alien_station_lights"],
		"Fixture registry references one light overlay absent from the supplied IPA"
	)
	var opaque: ShaderMaterial = lib.material(20003)
	check(
		opaque.shader == lib.LIT_SHADER and opaque.get_shader_parameter("atlas") != null,
		"Native hull material uses imported atlas and vertex lighting"
	)
	var additive: ShaderMaterial = lib.material(20001)
	check(
		additive.shader.code.contains("blend_add") and additive.shader.code.contains("ALPHA = 1.0"),
		"Additive mesh shader preserves source ONE/ONE color contribution"
	)
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index source material declarations")
	var registry := reader.symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var end := reader.symbol_address("__ZN11AbyssEngine11PaintCanvas5End3dEv")
	var blend := reader.symbol_address(
		"__ZN11AbyssEngine11PaintCanvas12SetBlendModeENS_9BlendModeE"
	)
	var meshes := reader.resource_bindings()
	reader.bytes.encode_u16(reader.file_offset(registry + 0x4b6, 2), 0x2205)
	var changed := reader.material_definitions(meshes)
	check(
		not changed.is_empty() and changed["20000"].texture == 5,
		"Material texture comes from changed source payload"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(registry + 0x53e, 2), 0x2300)
	changed = reader.material_definitions(meshes)
	check(
		not changed.is_empty() and not changed["20003"].lit,
		"Changed source hull flags select the declared unlit material pass"
	)
	for address in [registry + 0x4c8, end + 0xe0, blend + 0x38]:
		reader.bytes = source.duplicate()
		reader.error = ""
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xffff)
		check(
			reader.material_definitions(meshes).is_empty() and not reader.error.is_empty(),
			"Unsupported material declaration rejected at %x" % address
		)
	var original: Dictionary = lib.content.materials
	for field in ["texture", "blend", "cull", "lit", "order"]:
		var invalid: Dictionary = original.duplicate(true)
		invalid["20003"][field] = null
		lib.content.materials = invalid
		check(not lib.valid_materials(), "Missing material field rejected: " + field)
	lib.content.materials = original
	var mesh_data: Dictionary = lib.content.resources["10000"]
	var previous: int = mesh_data.material_id
	mesh_data.material_id = -1
	check(not lib.valid_materials(), "Unknown cached mesh material rejected")
	mesh_data.material_id = previous
	check(lib.valid_materials(), "Source material associations recover after invalid-cache checks")


func check_briefing_scenes(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.briefing_scene
	var modes: Array = []
	for chapter in data.chapters:
		modes.append(int(chapter.mode))
	check(
		modes == [7, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22],
		"Briefing scenes follow the supplied chapter mode table"
	)
	check(
		(
			data.chapters[0].kind == "intro"
			and data.chapters[1].location_station
			and not data.chapters[12].location_station
		),
		"Opening, location and final campaign scene ownership remain distinct"
	)
	check(
		(
			Combat.vector(data.camera_position) == Vector3(-250, 0, -500)
			and data.fov_units == 12000
			and data.near == 100
			and data.far == 800000
		),
		"Source camera framing and clip planes"
	)
	check(
		data.station_z == 32768 and data.special_type == 23 and data.special_z == 10000,
		"Source cutscene placement overrides initial Level station position"
	)
	check(
		data.field.count == 40 and data.field.width == 40000 and data.field.rotation_bound == 32768,
		"Source briefing field dimensions and rotation bounds"
	)
	var kinds := {}
	for index in lib.stations.size():
		var location: Dictionary = lib.station_definition(index)
		var expected := 20
		match int(location.race):
			0:
				expected = 21 if location.image == 0 else 22
			1:
				expected = 24
			9:
				expected = 23
		var actual: int = lib.briefing_station_type(1, index)
		check(
			actual == expected,
			"Briefing station matches source race/image rule at destination %d" % index
		)
		kinds[actual] = true
	check(kinds.size() == 5, "Imported destinations exercise all five briefing station types")
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index briefing scene source")
	var init := reader.symbol_address("__ZN8CutScene4initEv")
	var update := reader.symbol_address("__ZN8CutScene8OnUpdateEi")
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader, init + 0xee), 10000)
	reader.bytes = changed
	var result := reader.briefing_scene_presentation()
	check(
		not result.is_empty() and result.fov_units == 10000,
		"Changed source camera field of view is imported"
	)
	reader.bytes = source
	changed = source.duplicate()
	var offset := reader.file_offset(update + 0x180, 2)
	changed.encode_u16(offset, (changed.decode_u16(offset) & ~0x7c0) | (3 << 6))
	reader.bytes = changed
	result = reader.briefing_scene_presentation()
	check(
		not result.is_empty() and result.chapters[1].field_velocity[0] == -.125,
		"Source field drift shift determines native speed"
	)
	reader.bytes = source
	changed = source.duplicate()
	offset = literal_file_offset(reader, update + 0x172)
	changed.encode_u32(offset, changed.decode_u32(offset) | (1 << 22))
	reader.bytes = changed
	result = reader.briefing_scene_presentation()
	check(
		(
			not result.is_empty()
			and Combat.vector(result.chapters[12].field_velocity) == Vector3(-.125, 0, -.25)
		),
		"Final scene keeps its source drift outside the bitmask selection range"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(init + 0x63a, 2), 0x46c0)
	reader.error = ""
	check(
		reader.briefing_scene_presentation().is_empty(),
		"Unknown source briefing camera declaration rejected"
	)
	var Scene = load("res://src/presentation/briefing_scene.gd")
	for chapter in range(1, 13):
		var node = Scene.new()
		root.add_child(node)
		check(
			node.configure(lib, chapter, 0),
			"Native briefing scene chapter %d: %s" % [chapter, node.error]
		)
		if not node.supported:
			node.free()
			continue
		node.set_process(false)
		check(
			node.field.get_child_count() == 40,
			"Briefing field contains source count for chapter %d" % chapter
		)
		check(
			(
				node.camera.position == Vector3(-5, 0, 10)
				and is_equal_approx(node.camera.fov, 65.91796875)
			),
			"Briefing camera uses native units for chapter %d" % chapter
		)
		node.advance(1000)
		check(
			node.field.position.is_equal_approx(
				Combat.vector(data.chapters[chapter].field_velocity) * Vector3(1, 1, -1) * 20
			),
			"Briefing drift uses elapsed milliseconds for chapter %d" % chapter
		)
		var rotation: Basis = node.station.rotor.basis
		node.advance(-1)
		check(
			node.elapsed_ms == 1000 and rotation == node.station.rotor.basis,
			"Invalid scene delta does not rewind presentation"
		)
		node.free()
	var intro = Scene.new()
	root.add_child(intro)
	check(
		not intro.configure(lib, 0, 0) and intro.error.is_empty() and intro.get_child_count() == 0,
		"Unsupported opening flyby does not silently use a later station scene"
	)
	intro.free()
	var old: Variant = data.fov_units
	data.fov_units = -1
	check(not lib.valid_briefing_scene(), "Damaged cached camera rejected")
	data.fov_units = old
	check(lib.valid_briefing_scene(), "Briefing scene validation recovers")


func check_station_models(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.station_models
	var bodies: Array = []
	var lights: Array = []
	for kind in range(20, 25):
		bodies.append(int(data.types[str(kind)].body))
		lights.append(int(data.types[str(kind)].lights))
	check(bodies == [10044, 10045, 10046, 10047, 10048], "All source station body associations")
	check(lights == [10069, 10070, 10071, 10072, 10073], "All source station light associations")
	var chapters: Array = []
	for value in data.campaign:
		chapters.append(-1 if value.is_empty() else int(value.type))
	check(
		chapters == [21, -1, 21, -1, -1, -1, -1, -1, 22, 20, -1, 23, 21],
		"Campaign station presence is imported per chapter"
	)
	check(
		(
			Combat.vector(data.campaign[0].position) == Vector3(0, 0, 30000)
			and Combat.vector(data.campaign[0].alternate_position) == Vector3(0, 0, -30000)
			and data.campaign[0].position_mode == 7
		),
		"Opening station placement distinguishes source scene modes"
	)
	check(
		data.tilt_bound == 10000 and data.tilt_center == 5000 and data.turn_ms == 65536,
		"Source station tilt and rotation clock"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read source station declaration locations")
	var create := reader.symbol_address("__ZN12SpaceStation13createStationEi")
	var constructor := reader.symbol_address("__ZN12SpaceStationC2Ei")
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader, create + 0x28), 10044)
	reader.bytes = changed
	var altered: Dictionary = reader.station_presentation(lib.content.resources)
	check(
		not altered.is_empty() and altered.types["21"].body == 10044,
		"Changing source station body changes imported association"
	)
	changed.encode_u32(literal_file_offset(reader, create + 0x28), 65535)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.station_presentation(lib.content.resources).is_empty(),
		"Unknown station resource association rejected"
	)
	reader.bytes = source
	reader.error = ""
	changed = source.duplicate()
	changed.encode_u32(literal_file_offset(reader, constructor + 0x40), 12000)
	reader.bytes = changed
	altered = reader.station_presentation(lib.content.resources)
	check(
		not altered.is_empty() and altered.tilt_bound == 12000,
		"Source tilt bounds are recovered rather than hardcoded"
	)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(create + 0x44, 2), 0x46c0)
	reader.error = ""
	check(
		reader.station_presentation(lib.content.resources).is_empty(),
		"Unknown station mesh construction rejected"
	)
	for kind in range(20, 25):
		var node = lib.station_model(kind, Vector2i(5000, 5000))
		check(node.error.is_empty(), "Native station composite %d" % kind)
		check(
			node.rotor.get_child_count() == (1 if kind == 24 else 2),
			"Source body/lights count %d" % kind
		)
		check(
			node.missing_resources == ([10073] as Array[int] if kind == 24 else [] as Array[int]),
			"Absent source light is explicit %d" % kind
		)
		for child in node.rotor.get_children():
			check(
				child.transform == Transform3D.IDENTITY,
				"Station parts preserve common raw coordinates %d" % kind
			)
		node.set_elapsed(16384)
		check(
			(node.rotor.basis * Vector3.FORWARD).is_equal_approx(Vector3.RIGHT),
			"Station quarter-turn uses source time and reflected Z %d" % kind
		)
		node.set_elapsed(65536)
		check(
			node.rotor.basis.is_equal_approx(Basis.IDENTITY),
			"Station complete turn is continuous %d" % kind
		)
		node.free()
	var unsupported = lib.station_model(-1)
	check(
		not unsupported.error.is_empty(),
		"Unknown station types never fall back to fabricated geometry"
	)
	unsupported.free()
	var bad_tilt = lib.station_model(20, Vector2i(10000, 0))
	check(not bad_tilt.error.is_empty(), "Out-of-range station tilt rejected")
	bad_tilt.free()
	var original: Dictionary = data.types["20"].duplicate()
	data.types["20"].lights = -1
	check(not lib.valid_station_models(), "Damaged cached station resource rejected")
	data.types["20"] = original
	check(lib.valid_station_models(), "Station validation recovers after damaged-cache check")


func check_mesh_colors(lib) -> void:
	var parser := Formats.new()
	var bytes: PackedByteArray = lib.read("data/meshes/terran_battleship_01.aem")
	var data := parser.aem(bytes)
	check(
		(
			data.flags == 31
			and data.colors.size() == data.vertices.size()
			and data.colors.size() == 1690
		),
		"Battleship retains all source RGBA vertex colors"
	)
	var offset: int = bytes.size() - data.colors.size() * 4
	var matches := true
	for index in data.colors.size():
		var at: int = offset + index * 4
		if not data.colors[index].is_equal_approx(
			Color8(bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])
		):
			matches = false
			break
	check(matches, "All vertex color channels match source RGBA bytes")
	var modified := bytes.duplicate()
	for index in 4:
		modified[offset + index] = [10, 70, 130, 190][index]
	var changed := parser.aem(modified)
	check(
		changed.colors[0].is_equal_approx(Color8(10, 70, 130, 190)),
		"Changed source vertex color preserves all four channels"
	)
	check(
		(
			changed.vertices == data.vertices
			and changed.normals == data.normals
			and changed.uv == data.uv
			and changed.indices == data.indices
		),
		"Color decoding does not shift geometry, normals, UVs or triangles"
	)
	modified.resize(modified.size() - 1)
	check(parser.aem(modified).is_empty(), "Truncated color payload is rejected")
	check(
		parser.aem(lib.read("data/meshes/protagonist_01.aem")).colors.is_empty(),
		"Uncolored source mesh does not invent a color array"
	)
	var mesh: ArrayMesh = lib.mesh("terran_battleship_01")
	var arrays := mesh.surface_get_arrays(0)
	check(
		arrays[Mesh.ARRAY_COLOR].size() == data.colors.size(),
		"Godot mesh receives source vertex colors"
	)
	var material: ShaderMaterial = lib.material(lib.model_materials.terran_battleship_01)
	check(
		not material.shader.code.contains("COLOR"),
		"Source lit battleship keeps fixed material lighting despite its mostly-zero color buffer"
	)
	var unlit: StandardMaterial3D = lib.material(20000)
	check(unlit.vertex_color_use_as_albedo, "Source unlit surface uses supplied vertex color")


func check_lighting(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.lighting
	check(lib.valid_lighting(), "Imported lighting is valid")
	check(
		same_saved_value(
			data.directions,
			[
				[260, 107, -210],
				[-216, -206, -147],
				[217, -266, -29],
				[-206, 187, -228],
				[335, 0, -57],
				[-33, 176, 293],
				[-70, -104, -316],
				[87, 129, -307],
				[283, -78, 172]
			]
		),
		"All nine source sky directions include the default switch entry"
	)
	check(
		data.material_face == 0x404 and is_equal_approx(data.ambient_light[0], .7),
		"Raw source material face and light ambient retained"
	)
	var material: ShaderMaterial = lib.material(20003)
	for variant in data.directions.size():
		for style in data.diffuse.size():
			lib.set_lighting(variant, style, 0)
			check(
				material.get_shader_parameter("light_direction").is_equal_approx(
					Combat.vector(data.directions[variant]).normalized()
				),
				"Cached hull light follows source sky variant %d/style%d" % [variant, style]
			)
			check(
				material.get_shader_parameter("light_diffuse").is_equal_approx(
					Combat.vector(data.diffuse[style]) * .8
				),
				"Invalid source material face retains GLES diffuse default"
			)
	check(
		material.get_shader_parameter("light_ambient").is_equal_approx(Vector3.ONE * .18),
		"GLES material default and source light ambient produce .18 ambient"
	)
	var race_one := -1
	for station in lib.stations.size():
		if lib.station_definition(station).race == data.hangar_race:
			race_one = station
			break
	check(race_one >= 0, "Source galaxy supplies the hangar race")
	lib.set_lighting(0, 0, race_one, true)
	check(
		(
			material.get_shader_parameter("light_direction").is_equal_approx(Vector3.UP)
			and material.get_shader_parameter("light_diffuse").is_equal_approx(
				Vector3(.52, .8, .52)
			)
		),
		"Hangar light uses source vertical direction and faction color"
	)
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	check(reader.parse_macho(), "Index lighting fixture")
	var sky := reader.symbol_address("__ZN5Level12createSkyboxEib")
	var initialize := reader.symbol_address("__ZN11AbyssEngine11PaintCanvas10InitializeEv")
	var direction_offset := reader.file_offset(sky + 0x12e, 2)
	var color_offset := literal_file_offset(reader, sky + 0x29e)
	var face_offset := literal_file_offset(reader, initialize + 0x10c)
	reader.bytes.encode_u16(direction_offset, 0x2383)
	reader.bytes.encode_float(color_offset, .6)
	reader.bytes.encode_u32(face_offset, 0x408)
	var altered: Dictionary = reader.lighting_presentation()
	check(
		(
			reader.error.is_empty()
			and altered.directions[0][0] == 262
			and is_equal_approx(altered.diffuse[0][0], .6)
			and altered.material_face == 0x408
		),
		"Changed source direction/color/face declarations change imported lighting"
	)
	lib.content.lighting = altered
	check(lib.valid_lighting(), "Valid changed lighting accepted")
	lib.set_lighting(0, 0, 0)
	check(
		(
			material.get_shader_parameter("light_ambient").is_equal_approx(Vector3.ONE * .63)
			and is_equal_approx(material.get_shader_parameter("light_diffuse").x, .6)
		),
		"Valid FRONT_AND_BACK source declarations set material reflectance"
	)
	reader.bytes.encode_u16(direction_offset, 0xffff)
	reader.error = ""
	reader.lighting_presentation()
	check(not reader.error.is_empty(), "Unknown light direction initializer rejected")
	lib.content.lighting = data
	for key in data:
		lib.content.lighting = data.duplicate(true)
		lib.content.lighting.erase(key)
		check(not lib.valid_lighting(), "Missing lighting field rejected: " + key)
	lib.content.lighting = data
	check(lib.valid_lighting(), "Restore source lighting")
	lib.set_lighting(0, 0, 0)
	var model: Dictionary = lib.reader.aem(lib.read("data/meshes/protagonist_01.aem"))
	var normals: PackedFloat32Array = model.lighting_normals
	check(
		normals.size() == model.vertices.size() * 3,
		"Every mesh vertex retains raw converted lighting normal"
	)
	check(
		is_equal_approx(normals[0], 1.0 / 65535.0) and is_equal_approx(normals[2], 1.0),
		"Short-normal conversion preserves asymmetric zero and reflects Z afterward"
	)
	var values: PackedFloat32Array = lib.mesh("protagonist_01").surface_get_arrays(0)[
		Mesh.ARRAY_CUSTOM0
	]
	check(values == normals, "Godot custom attribute preserves source normal values exactly")


func check_ship_exhaust(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.ship_exhaust
	check(lib.valid_ship_exhaust(), "Validate supplied ship exhaust resources and attachments")
	check(
		data.player.size() == 22 and data.actors.size() == 22,
		"Recover exhaust declarations for every source actor identity"
	)
	check(
		(
			data.player[0].size() == 3
			and (
				Vector3(
					data.player[0][0].position[0],
					data.player[0][0].position[1],
					data.player[0][0].position[2]
				)
				. is_equal_approx(Vector3(0, 16, -468))
			)
		),
		"Actor zero retains its original three nozzle attachment points"
	)
	check(
		data.actors[6].size() == 4 and data.actors[3].is_empty(),
		"Capital exhaust count and explicit absent exhaust are preserved"
	)
	var flight := Flight.new()
	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.depart(), "Start opening flight to verify ship exhaust composition")
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	var hull: MeshInstance3D = flight.ship.get_child(0)
	check(hull.get_child_count() == 3, "Player exhaust appears on all three original nozzles")
	var nozzle: MeshInstance3D = hull.get_child(0)
	var initial_actor: int = lib.content.tables.buyable_ships[pilot.ship_id]
	var definition: Dictionary = data.player[initial_actor][0]
	check(
		(
			nozzle.position.is_equal_approx(
				(
					Vector3(definition.position[0], definition.position[1], -definition.position[2])
					* .02
				)
			)
			and nozzle.scale.is_equal_approx(
				Vector3(definition.scale[0], definition.scale[1], definition.scale[2])
			)
		),
		"Source coordinate conversion puts exhaust behind the scaled player hull"
	)
	var resource: Dictionary = lib.content.resources[str(int(definition.mesh))]
	var expected: MeshInstance3D = lib.model(resource.path.get_file().get_basename())
	check(
		nozzle.mesh == expected.mesh and nozzle.material_override == expected.material_override,
		"Exhaust reuses the supplied flame mesh and additive material"
	)
	expected.free()
	for actor in flight.actors:
		var body: MeshInstance3D = actor.node.get_child(0)
		var actor_id: int = pilot.mission_definition().groups[int(actor.state.group)].actor
		check(
			body.get_children().filter(func(child): return child.has_meta("exhaust_scale")).size() == data.actors[actor_id].size(),
			"Opening NPC exhaust follows its own actor declaration"
		)
	flight.free()
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index engine exhaust declarations for source mutation")
	var function := reader.symbol_address("__ZN9PlayerEgo7setShipEi")
	var table := reader.literal(function + 0xe8, 2)
	var changed := source.duplicate()
	changed.encode_s32(reader.file_offset(table + 8, 4), 123)
	reader.bytes = changed
	var altered := reader.ship_exhaust(lib.content.resources, data.player.size())
	check(
		(
			not altered.is_empty()
			and altered.player[0][0].position[0] == 123
			and altered.actors[0][0].position[0] == 0
		),
		"Player and NPC attachment tables are independently sourced, not hardcoded copies"
	)
	changed = source.duplicate()
	changed.encode_s32(reader.file_offset(table + 32 + 4, 4), 1)
	reader.bytes = changed
	var mixed := reader.ship_exhaust(lib.content.resources, data.player.size())
	check(
		(
			not mixed.is_empty()
			and mixed.player[0][0].mesh == data.player[0][0].mesh
			and mixed.player[0][1].mesh != mixed.player[0][0].mesh
		),
		"Each nozzle retains its own source flame variant"
	)
	changed = source.duplicate()
	changed.encode_s32(reader.file_offset(table, 4), 1000)
	reader.bytes = changed
	reader.error = ""
	check(
		(
			reader.ship_exhaust(lib.content.resources, data.player.size()).is_empty()
			and not reader.error.is_empty()
		),
		"Reject invalid source nozzle counts before reading beyond the table"
	)
	var saved: Dictionary = data.duplicate(true)
	lib.content.ship_exhaust.player[0][0].scale[2] = 0
	check(not lib.valid_ship_exhaust(), "Reject malformed cached exhaust dimensions")
	lib.content.ship_exhaust = saved
	check(lib.valid_ship_exhaust(), "Restore valid exhaust declarations after rejection test")


func check_rocket_guidance(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.transport
	var weapon: Dictionary = parameters.heavy_combat.weapon
	check(
		(
			weapon.damage_rule.base == 22
			and weapon.interval == 2.5
			and weapon.speed == 80
			and weapon.lifetime == 5
			and weapon.pool_capacity == 1
			and not weapon.has("pool_id")
			and weapon.projectile_model == 10058
			and weapon.projectile_overlay == 10060
		),
		"Imported heavy rocket has its own single-projectile gun and original model"
	)
	check(
		(
			weapon.guidance.delay == .165
			and weapon.guidance.response_divisor == 3
			and is_equal_approx(weapon.guidance.acquisition_half_width, 299.98)
		),
		"Rocket acquisition delay, volume and response come from the source"
	)
	var profiles: Dictionary = lib.definition_weapons(
		{"groups": [{"count": 2, "weapon": weapon}, {"count": 1, "team": "ally"}]}, 5
	)
	check(
		profiles[-1].guidance_target_ids == [-1, 2],
		"Rocket locks refer to opposing actor identities and the player"
	)
	var candidates := [
		{"id": -1, "team": "ally", "position": [2, 0, -60], "visible": false},
		{"id": 1, "team": "enemy", "position": [0, 0, -30], "visible": true},
		{"id": 2, "team": "ally", "position": [20, 0, -100], "visible": true}
	]
	var state := Combat.create()
	check(
		Combat.fire(state, -1, Vector3.ZERO, Vector3.FORWARD, lib, profiles),
		"Launch native guided rocket"
	)
	for tick in 16:
		Combat.advance(state, .01, [], lib, profiles, candidates)
	check(
		state.projectiles[0].guidance.target == -2 and state.projectiles[0].velocity[0] == 0,
		"Rocket flies straight through the source acquisition delay"
	)
	Combat.advance(state, .01, [], lib, profiles, candidates)
	check(
		state.projectiles[0].guidance.target == 2 and state.projectiles[0].velocity[0] > 0,
		"Rocket acquires visible hostile target, ignoring a closer hidden target and friendly ship"
	)
	candidates[0].visible = true
	candidates[2].visible = false
	candidates[2].alive = false
	candidates[2].active = false
	candidates[2].position = [40, 0, -100]
	Combat.advance(state, .01, [], lib, profiles, candidates)
	check(
		(
			state.projectiles[0].guidance.target == 2
			and state.projectiles[0].guidance.position == [40, 0, -100]
		),
		"Committed source lock retains its target through visibility and activity changes"
	)
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(
		Combat.valid(serialized, lib, profiles),
		"Guided projectile lock and velocity survive JSON validation"
	)
	var copy := Combat.normalize(serialized)
	for tick in 30:
		Combat.advance(state, 1.0 / 60, [], lib, profiles, candidates)
		Combat.advance(copy, 1.0 / 60, [], lib, profiles, candidates)
	check(same_saved_value(state, copy), "Guidance trajectory is identical after save/reload")
	var invalid := copy.duplicate(true)
	invalid.projectiles[0].guidance.target = 1
	check(not Combat.valid(invalid, lib, profiles), "Reject a saved lock to a friendly actor")
	invalid = copy.duplicate(true)
	invalid.projectiles[0].guidance.position = [INF, 0, 0]
	check(not Combat.valid(invalid, lib, profiles), "Reject non-finite saved guidance position")
	invalid = copy.duplicate(true)
	invalid.projectiles[0].erase("guidance")
	check(
		not Combat.valid(invalid, lib, profiles),
		"Guided rocket cannot silently lose its saved acquisition state"
	)
	state = Combat.create()
	Combat.fire(state, -1, Vector3.ZERO, Vector3.FORWARD, lib, profiles)
	candidates = [{"id": -1, "team": "ally", "position": [300, 0, -100], "visible": true}]
	for tick in 20:
		Combat.advance(state, .01, [], lib, profiles, candidates)
	check(
		state.projectiles[0].guidance.target == -2,
		"Visible target outside imported acquisition cube is ignored"
	)
	candidates[0].position = [20, 0, -100]
	candidates[0].radius = 3
	var impacts := []
	for tick in 300:
		impacts.append_array(Combat.advance(state, 1.0 / 60, candidates, lib, profiles, candidates))
		if not impacts.is_empty():
			break
	check(
		impacts.size() == 1 and impacts[0].target == -1 and impacts[0].damage == 23,
		"Guided rocket curves toward an off-axis target and applies the imported damage through swept collision"
	)
	check(state.projectiles.is_empty(), "Rocket impact releases its single projectile slot")
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index guided rocket declarations")
	var assignment := reader.symbol_address("__ZN5Level10assignGunsEv")
	var rocket_calls := reader.calls_between(
		assignment, reader.symbol_end(assignment), "__ZN9RocketGunC1EiP3Guniijib"
	)
	# The heavy factory selects its own RocketGun; inspect its two resource operands.
	var heavy_call := 0
	for address in rocket_calls:
		if reader.u16(address - 2) & 0xff00 == 0x4b00 and reader.u16(address - 20) == 0x9300:
			heavy_call = address
	check(heavy_call > 0, "Locate heavy rocket body and glow operands")
	if heavy_call > 0:
		var body_offset := literal_file_offset(reader, heavy_call - 2)
		var glow_offset := literal_file_offset(reader, heavy_call - 28)
		var swapped := source.duplicate()
		swapped.encode_u32(body_offset, 10060)
		swapped.encode_u32(glow_offset, 10058)
		reader.bytes = swapped
		var visual := reader.rocket_weapon(18)
		check(
			(
				not visual.is_empty()
				and visual.projectile_model == 10060
				and visual.projectile_overlay == 10058
			),
			"Rocket body and glow follow distinct imported resource operands"
		)
		reader.bytes = source
		reader.error = ""
	var update: int = reader.symbols["__ZN9RocketGun6updateEi"][0]
	var constructor: int = reader.symbols["__ZN9RocketGunC2EiP3Guniijib"][0]
	var delay_offset := reader.file_offset(update + 0xca, 2)
	var response_offset := reader.file_offset(constructor + 0x7e, 2)
	var binding_offset := reader.file_offset(constructor + 0x80, 2)
	var damaged := source.duplicate()
	damaged.encode_u16(delay_offset, 0x3ac8)
	damaged.encode_u16(response_offset, 0x2304)
	reader.bytes = damaged
	var changed := reader.rocket_guidance(10060)
	check(
		not changed.is_empty() and changed.delay == .2 and changed.response_divisor == 4,
		"Changed source guidance delay and response are imported rather than hardcoded"
	)
	damaged = source.duplicate()
	damaged.encode_u16(binding_offset, 0x6453)
	reader.bytes = damaged
	reader.error = ""
	check(
		reader.rocket_guidance(10060).is_empty() and not reader.error.is_empty(),
		"Unsupported guidance field binding is rejected"
	)
	damaged = source.duplicate()
	damaged.encode_u16(reader.file_offset(constructor + 0x52, 2), 0xbf00)
	reader.bytes = damaged
	reader.error = ""
	check(
		reader.rocket_weapon(18).is_empty() and not reader.error.is_empty(),
		"Unknown rocket body constructor cannot silently become glow-only geometry"
	)


func check_transport_contracts(lib) -> void:
	var parameters: Dictionary = lib.content.contracts.transport
	check(
		ContractEncounters.valid_transport_parameters(parameters, lib),
		"Validate imported transport encounter parameters"
	)
	var variants := {}
	var deadline_variants := {}
	var heavy_seen := false
	for region in 4:
		var station := -1
		for index in lib.stations.size():
			if lib.station_definition(index).quadrant == region:
				station = index
				break
		for kind in parameters.types:
			for race in [0, 1]:
				var offer := Contracts.terms(lib.content.contracts, region, int(kind), 9)
				offer.origin_station = station
				offer.client = {"name": "Client", "race": race, "portrait": 11, "profession": 444}
				for seed_value in 12:
					var definition := ContractEncounters.transport(
						lib, parameters, offer, 5, seed_value
					)
					check(
						not definition.is_empty() and lib.valid_mission(definition),
						"Generate transport across regions, categories, races and seeds"
					)
					if definition.is_empty():
						continue
					check(
						definition.groups.size() == region + 5 and definition.route.size() == 3,
						"Source regional difficulty controls ambusher count"
					)
					var heavy_count := 0
					for group in definition.groups:
						check(
							group.sleeping and definition.route.has(group.center),
							"Ambushers start asleep at imported route waypoints"
						)
						if group.actor == parameters.heavy_actor:
							heavy_count += 1
							heavy_seen = true
							check(
								group.weapon.has("guidance") and group.motion.avoid_distance == 120,
								"Every heavy ambusher has its original guided weapon and avoidance range"
							)
					check(
						heavy_count <= region and (race != 1 or heavy_count == 0),
						"Regional heavy quota and client-race choice respected"
					)
					variants["fog" if definition.has("fog") else ("asteroids" if not definition.scenery.is_empty() else "empty")] = true
					deadline_variants[definition.deadline_ms > 0] = true
					var state := Session.Mission.create(
						definition, 0, station, lib, seed_value, 5, "contract"
					)
					for waypoint in 3:
						Session.Mission.reach_waypoint(definition, state)
					check(
						(
							state.ready
							and state.kills == 0
							and state.actors.all(func(actor): return actor.hp > 0)
						),
						"Transport succeeds by traversing its route while all ambushers survive"
					)
					if definition.deadline_ms > 0:
						state = Session.Mission.create(
							definition, 0, station, lib, seed_value, 5, "contract"
						)
						Session.Mission.advance(
							definition, state, float(definition.deadline_ms) / 1000, lib
						)
						check(
							not state.failed,
							"Transport deadline uses the source strict greater-than boundary"
						)
						Session.Mission.advance(definition, state, .001, lib)
						check(
							state.failed and not state.ready,
							"Late transport fails without granting route success"
						)
	check(
		variants.size() == 3 and deadline_variants.size() == 2 and heavy_seen,
		"Exercise all scenery, timed/untimed transports and heavier regional ships"
	)
	var invalid := parameters.duplicate(true)
	invalid.route_axes[5].rolls = [0]
	check(
		not ContractEncounters.valid_transport_parameters(invalid, lib),
		"Invalid cached transport distribution is rejected"
	)
	invalid = parameters.duplicate(true)
	invalid.heavy_combat.weapon.guidance.response_divisor = 0
	check(
		not ContractEncounters.valid_transport_parameters(invalid, lib),
		"Invalid cached heavy guidance is rejected"
	)


func check_hud_artwork(source: PackedByteArray, lib) -> void:
	check(lib.valid_flight_ui(), "Validate original flight HUD composition")
	var art: Dictionary = lib.content.flight_ui.artwork
	check(
		art.images.fire_frame.region == 98 and art.images.fire_overlay.region == 99,
		"Fire control retains separate source frame and luminous overlay"
	)
	check(
		art.images.stick_frame.region == 100 and art.images.bar.region == 107,
		"Joystick and status bars reuse the supplied artwork"
	)
	check(
		(
			art.layout.pause_right == 30
			and art.layout.stick_radius == 31
			and art.layout.weapon_label_bottom == 19
		),
		"Read HUD margins and joystick radius from the supplied declarations"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index source HUD declarations for mutation")
	var ctor := reader.symbol_address("__ZN3HudC2Ev")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(ctor + 0x298, 2), 0x2218)
	reader.bytes = changed
	var altered := reader.flight_artwork()
	check(
		(
			not altered.is_empty()
			and altered.layout.pause_top == 24
			and altered.layout.pause_right == art.layout.pause_right
		),
		"HUD layout follows changed source margins without changing independent anchors"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(ctor + 0x50, 2), 0x00c9)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.flight_artwork().is_empty() and not reader.error.is_empty(),
		"Reject unsupported fire overlay resource declaration"
	)
	var saved: Dictionary = art.duplicate(true)
	lib.content.flight_ui.artwork.images.bar.region = 100000
	check(not lib.valid_flight_ui(), "Reject cached HUD artwork outside its atlas")
	lib.content.flight_ui.artwork = saved
	check(lib.valid_flight_ui(), "Restore valid flight HUD after cache rejection")


func check_player_exhaust_speed(lib) -> void:
	var pilot = Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	check(pilot.depart(), "Start exploration throttle fixture")
	var flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	var nozzle = flight.player_hull.get_child(0)
	var source_scale = nozzle.get_meta("exhaust_scale")
	var source_position = nozzle.position
	var previous_length = INF
	for throttle in [1.0, .75, .5, .25, 0.0]:
		flight.throttle = throttle
		flight.step(1.0 / 60)
		check(
			is_equal_approx(flight.speed, float(lib.content.player_motion.cruise_speed) * throttle),
			"Fixture actually moves at selected throttle"
		)
		var length = nozzle.scale.z if nozzle.visible else 0.0
		check(length < previous_length, "Exhaust becomes shorter at each slower flight speed")
		previous_length = length
		check(nozzle.position == source_position, "Throttling preserves nozzle attachment point")
		if throttle == 0:
			check(not nozzle.visible, "Stopped ship has no propulsion plume")
		if throttle == .5:
			var saved = pilot.capture()
			var copy = Session.new()
			copy.configure(lib)
			check(copy.restore(saved), "Restore a half-speed pilot")
			var resumed = Flight.new()
			root.add_child(resumed)
			resumed.setup(lib, copy, {}, true)
			resumed.set_physics_process(false)
			check(
				resumed.player_hull.get_child(0).scale.is_equal_approx(nozzle.scale),
				"Resume immediately restores speed-dependent exhaust"
			)
			resumed.free()
	# Use the real controller path and move the ship, rather than directly scaling
	# a nozzle. Rear engines follow forward travel even when total speed is high.
	flight.ship.position = Vector3(2000, 0, 2000)
	for rotation in [Vector3.ZERO, Vector3(.4, 1.2, .2)]:
		flight.ship.rotation = rotation
		for strafe in [-1.0, 1.0]:
			for throttle in [0.0, .25, .5, 1.0]:
				flight.throttle = throttle
				flight.controls.axes[JOY_AXIS_LEFT_X] = strafe
				var before_strafe: Vector3 = flight.ship.position
				flight.step(.25)
				var displacement: Vector3 = flight.ship.position - before_strafe
				check(
					absf(displacement.dot(flight.ship.basis.x)) > 1,
					"Controller actually strafes at the selected throttle"
				)
				if throttle == 0:
					check(
						not nozzle.visible,
						"Pure strafe leaves rear exhaust off in either orientation"
					)
				else:
					check(
						nozzle.visible and nozzle.scale.z < source_scale.z,
						"Diagonal strafe cannot promote reduced forward travel to full exhaust"
					)
					check(
						(
							absf(
								(
									nozzle.scale.z / source_scale.z
									- (
										displacement.dot(-flight.ship.basis.z)
										/ (.25 * float(lib.content.player_motion.cruise_speed))
									)
								)
							)
							< .001
						),
						"Rear plume follows forward displacement rather than total speed"
					)
	flight.controls.clear()

	flight.throttle = 1
	for i in 20:
		flight.throttle = .25
		flight.step(1.0 / 60)
		flight.throttle = 1
		flight.step(1.0 / 60)
	check(
		nozzle.visible and nozzle.scale.is_equal_approx(source_scale),
		"Repeated throttle changes return to original dimensions without drift"
	)
	var stationary = lib.model(lib.ship_model(pilot.ship_id))
	lib.attach_ship_exhaust(stationary, int(lib.content.tables.buyable_ships[pilot.ship_id]), true)
	check(
		stationary.get_child(0).scale == source_scale,
		"One player's speed does not modify shared source geometry"
	)
	stationary.free()
	flight.throttle = .25
	flight.controls.touch_boost = true
	flight.step(1.0 / 60)
	check(
		(
			flight.speed > lib.content.player_motion.cruise_speed
			and nozzle.scale.is_equal_approx(source_scale)
		),
		"Boost uses actual movement rather than low throttle for full exhaust"
	)
	var before = nozzle.scale
	flight.pause(true)
	flight._physics_process(2)
	check(nozzle.scale == before, "Pausing preserves exhaust presentation")
	flight.free()


func check_map_data(source: PackedByteArray, lib) -> void:
	check(
		lib.quadrants == [["Terdan"], ["Baltone"], ["Vilessk"], ["Solecci"]],
		"Quadrant names come from the supplied table"
	)
	check(
		lib.content.map_ui.images.galaxy == {"texture": 4.0, "region": 2.0},
		"Original galaxy image association"
	)
	check(
		lib.content.map_ui.images.nebula.region == 21,
		"Map background follows its constructor association, not atlas order"
	)
	check(
		(
			lib.content.map_ui.races
			== [404.0, 405.0, 406.0, 407.0, 408.0, 409.0, 410.0, 411.0, 412.0, 413.0]
		),
		"All faction names resolve through the supplied localization choices"
	)
	for index in lib.stations.size():
		var station: Dictionary = lib.station_definition(index)
		var expected: Vector2 = (
			station.position
			+ Vector2((index / 5) % 5, (index / 25) % 5) * 100
			+ Vector2((index / 125) % 2, index / 250) * 500
		)
		check(lib.galaxy_position(index) == expected, "Nested galaxy coordinates: " + str(index))
		var unknown: Array = lib.station_info(index, false)
		var known: Array = lib.station_info(index, true)
		check(
			(
				unknown[2][1] == "?"
				and unknown[3][1] == "?"
				and known[2][1] == str(station.technology)
			),
			"Destination discovery masks technology/trade: " + str(index)
		)
		check(
			lib.station_preview(index) != null,
			"Every supplied destination has a source-associated preview: " + str(index)
		)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read map declarations for mutation checks")
	var owner := reader.symbol_address("__ZN6Galaxy11getPositionEP7StationPfjjjj")
	var altered := source.duplicate()
	altered.encode_float(literal_file_offset(reader, owner + 0x2e), 120.0)
	reader.bytes = altered
	var changed: Dictionary = reader.map_presentation()
	check(
		reader.error.is_empty() and changed.grid.system_extent == 120.0,
		"Map scale is imported from the supplied declaration"
	)
	reader.bytes = source
	var info := reader.symbol_address("__ZN16PlanetInfoWindow10initTabboxEv")
	altered = source.duplicate()
	altered.encode_u32(literal_file_offset(reader, info + 0x698), 430)
	reader.bytes = altered
	changed = reader.map_presentation()
	check(
		reader.error.is_empty() and changed.stations.primary.region == 30,
		"Station preview changes with source resource association"
	)
	altered.encode_u16(reader.file_offset(info + 0x6ea, 2), 0)
	reader.bytes = altered
	check(
		reader.map_presentation().is_empty() and not reader.error.is_empty(),
		"Reject unrecognized preview construction instead of guessing"
	)


func check_graphical_map(lib) -> void:
	var chart = load("res://src/presentation/galaxy_map.gd").new()
	chart.library = lib
	chart.session = Session.new()
	chart.session.configure(lib)
	root.add_child(chart)
	check(chart.entries() == [0, 1, 2, 3], "Graphical map exposes all supplied quadrants")
	check(
		lib.content.map_icons.planets.map(func(binding): return int(binding.region)) == [15, 9, 14],
		"Original small planet icon cycle is distinct from preview image indices"
	)
	var destinations := {}
	for quadrant in lib.quadrants.size():
		chart.level = 0
		chart.activate(quadrant)
		check(
			chart.level == 1 and chart.quadrant == quadrant, "Quadrant selection enters its systems"
		)
		var systems: Array = chart.entries()
		for local_system in systems.size():
			chart.level = 1
			chart.activate(local_system)
			check(
				chart.system == systems[local_system],
				"System navigation retains global source addressing"
			)
			for station in chart.entries():
				destinations[station] = true
				check(
					chart.BOARD.has_point(chart.entry_point(station)),
					"Station lies within its source system map"
				)
				check(
					chart.icons[station] != null, "Destination uses its original small map symbol"
				)
			chart.back()
			check(
				chart.level == 1 and chart.selected == local_system,
				"Back restores the selected system"
			)
	check(
		destinations.size() == lib.stations.size(),
		"Every supplied destination is reachable through graphical hierarchy"
	)
	chart.free()


func check_travel_rules(source: PackedByteArray, lib) -> void:
	var travel = load("res://src/simulation/travel.gd")
	check(lib.valid_travel(), "Validate imported travel declarations")
	for change in [{"rating_max": INF}, {"rating_min": -1e20}, {"space_extent": 0}]:
		var invalid_rules: Dictionary = lib.content.travel.duplicate(true)
		invalid_rules.merge(change, true)
		check(not travel.valid(invalid_rules, lib), "Reject invalid travel bounds and projection")
	var fractional: Dictionary = lib.content.travel.duplicate(true)
	fractional.mission_changes["0"] = .5
	check(not travel.valid(fractional, lib), "Faction deltas cannot silently lose fractional data")
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index source travel declarations for mutation")
	var update := reader.symbol_address("__ZN4MMap8OnUpdateEv")
	var price_site := update + 0x478
	var price_data := ((price_site + 4) & ~3) + (reader.u16(price_site) & 255) * 4
	var changed := source.duplicate()
	changed.encode_float(reader.file_offset(price_data, 4), 40.0)
	reader.bytes = changed
	var recovered := reader.travel_rules()
	check(
		not recovered.is_empty() and recovered.distance_rate == 40,
		"Travel rate follows changed supplied data rather than a runtime constant"
	)
	var original_rules: Dictionary = lib.content.travel
	lib.content.travel = recovered
	check(
		travel.quote(lib, 0, 1, 0, 1).flight == 1842,
		"Changed imported price reaches native fare calculation"
	)
	lib.content.travel = original_rules
	var pilot := Session.new()
	pilot.configure(lib, true)
	for entry in [
		[1, 921],
		[2, 703],
		[18, 5038],
		[21, 7046],
		[125, 25238],
		[250, 25751],
		[375, 44081],
		[499, 54743]
	]:
		check(
			pilot.travel_quote(entry[0]).flight == entry[1],
			"Imported fare across source coordinate/quadrant boundaries"
		)
	var initial := pilot.capture()
	check(
		not pilot.travel(499) and pilot.capture() == initial, "Unaffordable travel is fully atomic"
	)
	check(
		(
			not pilot.travel(-1)
			and not pilot.travel(lib.stations.size())
			and pilot.capture() == initial
		),
		"Invalid destinations cannot change pilot state"
	)
	check(
		pilot.travel_quote(pilot.station_id) == {"flight": 0, "bribe": 0, "total": 0},
		"Current destination has no flight cost or bribe"
	)
	pilot.rating = 4
	var fare: Dictionary = pilot.travel_quote(18)
	check(fare.bribe == 600, "Terran reputation requires source bribe at a Vossk destination")
	pilot.credits = int(fare.total)
	check(
		pilot.travel(18) and pilot.credits == 0 and pilot.rating == 3,
		"Successful travel deducts exact total and paid bribe moves reputation toward neutral"
	)
	check(pilot.visited.has(18), "Paid travel records destination discovery")
	check(
		not pilot.travel(18) and pilot.credits == 0 and pilot.rating == 3,
		"Repeated same-station request cannot charge twice"
	)
	pilot.rating = -4
	check(
		pilot.travel_quote(0).bribe == 600,
		"Vossk reputation requires source bribe at a Terran destination"
	)
	check(pilot.travel_quote(2).bribe == 0, "Outlaw destination does not invent a faction bribe")
	check(
		(
			travel.quote(lib, 0, 18, 4, lib.stations.size()).flight == 0
			and travel.quote(lib, 0, 18, 4, lib.stations.size()).bribe == 600
		),
		"Complete exploration waives flight cost but preserves faction bribe"
	)
	check(
		(
			travel.after_mission(lib.content.travel, 10, 0) == 10
			and travel.after_mission(lib.content.travel, -10, 1) == -10
		),
		"Completed-job faction changes respect imported limits"
	)
	check(
		(
			travel.after_mission(lib.content.travel, 0, 0) == 1
			and travel.after_mission(lib.content.travel, 0, 1) == -1
			and travel.after_mission(lib.content.travel, 3, 9) == 3
		),
		"Job client faction controls reputation changes"
	)
	var saved := pilot.capture()
	var restored := Session.new()
	restored.configure(lib, true)
	check(
		restored.restore(saved) and restored.rating == -4,
		"Saved faction score survives a round trip"
	)
	var invalid := saved.duplicate(true)
	invalid.rating = 11
	check(not restored.restore(invalid), "Reject out-of-range faction score")
	invalid = saved.duplicate(true)
	invalid.visited.append(invalid.visited[0])
	check(not restored.restore(invalid), "Duplicate visits cannot grant free exploration travel")
	var old := Session.new()
	old.configure(lib)
	old.chapter = 2
	old.progression.rewards = [lib.content.chapters[0].reward, lib.content.chapters[1].reward]
	var legacy := old.capture()
	legacy.schema = 13
	legacy.erase("rating")
	check(
		restored.restore(legacy) and restored.rating == 2,
		"Old saves recover reputation from recorded completed campaign jobs"
	)
	old.skip_campaign()
	old.progression = Session.Progression.create(2)
	legacy = old.capture()
	legacy.schema = 13
	legacy.erase("rating")
	check(
		restored.restore(legacy) and restored.rating == 0,
		"Migration does not invent unrecorded legacy reputation or skipped rewards"
	)


func check_import_cancellation(path: String, importer) -> void:
	var previous_root: String = importer.root
	var previous_id: String = importer.content_id
	var manifest := FileAccess.get_file_as_bytes(previous_root.path_join("manifest.json"))
	var installed_data := FileAccess.get_sha256(previous_root.path_join("content.json"))
	var directories := DirAccess.get_directories_at(importer.cache_base)
	directories.sort()
	for phase in ["before", "native", "resources", "validation"]:
		var cancelled := [false]
		var cancel_when_ready := func(_message, ratio):
			var ready: bool = (
				phase == "before"
				or (phase == "native" and importer.native_job != null)
				or (phase == "resources" and ratio > 0 and ratio < 1)
				or (phase == "validation" and _message == "Checking imported game data")
			)
			if ready and not cancelled[0]:
				cancelled[0] = true
				importer.cancel()
		importer.progress.connect(cancel_when_ready)
		var success: bool = await importer.install(path, self)
		importer.progress.disconnect(cancel_when_ready)
		check(
			cancelled[0] and not success and importer.error == "Import cancelled.",
			"Cancel import during " + phase
		)
		check(
			not importer.installing and importer.native_job == null,
			"Cancelled import joins and releases its worker"
		)
		check(
			importer.root == previous_root and importer.content_id == previous_id,
			"Cancellation preserves active content identity"
		)
		check(
			(
				FileAccess.get_file_as_bytes(previous_root.path_join("manifest.json")) == manifest
				and FileAccess.get_sha256(previous_root.path_join("content.json")) == installed_data
			),
			"Cancellation leaves installed data byte-identical"
		)
		var remaining := DirAccess.get_directories_at(importer.cache_base)
		remaining.sort()
		check(remaining == directories, "Cancellation removes its partial directory")
	check(
		importer.open_cache(previous_root),
		"Previously installed content remains usable after cancellation"
	)
	check(await importer.install(path, self), "Retry succeeds after cancellation")
	check(
		FileAccess.get_sha256(previous_root.path_join("content.json")) == installed_data,
		"Retry preserves exactly the same recovered definitions"
	)


func check_exploration_station_areas(lib) -> void:
	var locations := {}
	for index in lib.stations.size():
		locations[lib.location_station_type(index)] = index
	check(locations.size() == 5, "Exploration selects all five imported station families")
	for kind in locations:
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.skip_campaign()
		pilot.station_id = locations[kind]
		check(pilot.depart(), "Launch native exploration at a source destination")
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, pilot, {})
		flight.set_physics_process(false)
		var station = flight.station
		var body: MeshInstance3D = station.rotor.get_node("body")
		var expected: String = (
			lib
			. content
			. resources[str(int(lib.content.station_models.types[str(kind)].body))]
			. path
			. get_file()
			. get_basename()
		)
		check(
			body.mesh == lib.mesh(expected),
			"Destination uses the imported family body without rescaling"
		)
		check(body.scale == Vector3.ONE, "Station preserves original model dimensions")
		var source_z: float = (
			lib.content.briefing_scene.special_z
			if kind == lib.content.briefing_scene.special_type
			else lib.content.briefing_scene.station_z
		)
		check(
			station.position.is_equal_approx(Vector3(0, 0, -source_z * .02)),
			"Exploration preserves source station-approach placement"
		)
		check(
			flight.ambience.get_child_count() == int(lib.content.briefing_scene.field.count),
			"Exploration field uses source population"
		)
		check(
			flight.navigation_target() == station.position,
			"Autopilot follows actual station location"
		)
		var docked := [0]
		flight.dock_requested.connect(func(): docked[0] += 1)
		flight.ship.position = station.position + Vector3.BACK * (flight.dock_radius + 1)
		flight.try_dock()
		check(docked[0] == 0, "Docking rejects positions outside the destination envelope")
		flight.ship.position = station.position + Vector3.BACK * (flight.dock_radius - 1)
		flight.try_dock()
		check(docked[0] == 1, "Docking accepts arrival outside the station mesh")
		flight.ship.position = station.position + Vector3.BACK * (flight.dock_radius + 15)
		flight.ship.basis = Basis.IDENTITY
		flight.auto_pilot = true
		for step in 600:
			flight.step(1.0 / 60.0)
			if not flight.auto_pilot:
				break
		check(
			(
				not flight.auto_pilot
				and flight.ship.position.distance_to(station.position) <= flight.dock_radius
			),
			"Autopilot stops within usable docking range"
		)
		flight.throttle = 0
		var clock: Basis = station.rotor.basis
		flight.step(1)
		check(
			not station.rotor.basis.is_equal_approx(clock),
			"Exploration station rotates on the simulation clock"
		)
		var radius: float = lib.actor_radius(int(lib.content.tables.buyable_ships[pilot.ship_id]))
		# Find an actual outward surface on the imported triangle mesh, then sweep
		# the player's collider through it. This exercises physics, not an AABB proxy.
		await physics_frame
		await physics_frame
		var space: PhysicsDirectSpaceState3D = flight.get_world_3d().direct_space_state
		var contact := {}
		for direction in [Vector3.BACK, Vector3.RIGHT, Vector3.UP, Vector3.FORWARD, Vector3.LEFT]:
			var ray := PhysicsRayQueryParameters3D.create(
				station.global_position + direction * 2000, station.global_position, 1
			)
			contact = space.intersect_ray(ray)
			if not contact.is_empty():
				break
		check(not contact.is_empty(), "Imported station mesh provides a physical surface")
		if not contact.is_empty():
			flight.ship.global_position = contact.position + contact.normal * (radius + 30)
			var collision: KinematicCollision3D = flight.ship.move_and_collide(
				-contact.normal * 100
			)
			check(collision != null, "Player sweep collides with source station triangles")
			check(
				(flight.ship.global_position - contact.position).dot(contact.normal) >= radius - .1,
				"Swept player remains outside the station surface"
			)
		flight.free()
	# Source field edits must affect exploration rather than a local count/model table.
	var original: Dictionary = lib.content.briefing_scene.field.duplicate(true)
	lib.content.briefing_scene.field.count = 3
	lib.content.briefing_scene.field.width = 1000
	var area := preload("res://src/presentation/station_area.gd").new()
	var random := RandomNumberGenerator.new()
	random.seed = 3
	check(
		area.configure(lib, int(locations.keys()[0]), random),
		"Build a changed compatible source field"
	)
	check(area.field.get_child_count() == 3, "Changed source asteroid count reaches the renderer")
	for rock in area.field.get_children():
		check(
			rock.position.abs().length() <= sqrt(3) * 10,
			"Changed source field extent reaches the renderer"
		)
	area.free()
	lib.content.briefing_scene.field = original


func check_radar_artwork(source: PackedByteArray, lib) -> void:
	check_radar_health_edge(source, lib)
	var radar: Dictionary = lib.content.flight_ui.radar
	check(lib.valid_radar_ui(radar), "Validate supplied radar composition")
	check(
		radar.images.frame_side.region == 93 and radar.images.frame_edge.region == 95,
		"Recover original flight frame pieces"
	)
	check(
		(
			radar.images.enemy_near.region == 90
			and radar.images.ally_near.region == 191
			and radar.images.aim.region == 89
			and radar.images.aim_hit.region == 112
		),
		"Recover original target brackets and aiming rings"
	)
	check(
		(
			radar.margin == 5
			and radar.near_extent == 640
			and radar.health_height == 3
			and radar.health_gap == 2
			and radar.hit_ms == 200
		),
		"Recover radar layout and hit feedback timing"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index radar declarations")
	var ctor := reader.symbol_address("__ZN5RadarC2EP5Level")
	var draw := reader.symbol_address("__ZN5Radar4drawEi")
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader, ctor + 0x2c), 692)
	reader.bytes = changed
	var result := reader.radar_presentation()
	check(
		not result.is_empty() and result.images.enemy_near.region == 191,
		"Changed source bracket association reaches radar data"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(draw + 0x98, 2), 0x2207)
	reader.bytes = changed
	result = reader.radar_presentation()
	check(
		not result.is_empty() and result.margin == 7,
		"Changed source frame margin reaches radar data"
	)
	var aim := reader.symbol_address("__ZN9PlayerEgo4drawEbb")
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(aim + 0x13e, 2), 0x2b64)
	reader.bytes = changed
	result = reader.radar_presentation()
	check(
		not result.is_empty() and result.hit_ms == 100,
		"Changed source hit duration reaches radar data"
	)
	changed.encode_u16(reader.file_offset(aim + 0x13e, 2), 0x2364)
	reader.bytes = changed
	check(reader.radar_presentation().is_empty(), "Reject an unsupported hit-duration consumer")
	reader.error = ""
	var registry := reader.symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(registry + 0x22f2, 2), 0x235c)
	reader.bytes = changed
	result = reader.radar_presentation()
	check(
		not result.is_empty() and result.images.enemy_far.region == 92,
		"Temporary atlas record follows its source region"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(ctor + 0x36, 2), 0xffff)
	reader.bytes = changed
	reader.error = ""
	check(
		reader.radar_presentation().is_empty() and not reader.error.is_empty(),
		"Reject unsupported radar image creation"
	)
	for key in [
		"margin", "near_extent", "health_height", "aim_distance", "hit_ms", "images", "colors"
	]:
		var bad: Dictionary = radar.duplicate(true)
		bad[key] = null
		check(not lib.valid_radar_ui(bad), "Reject malformed cached radar field " + key)
	var bad: Dictionary = radar.duplicate(true)
	bad.images.frame_side.region = 100000
	check(not lib.valid_radar_ui(bad), "Reject missing cached frame artwork")
	check(lib.valid_radar_ui(radar), "Radar validation recovers after rejection checks")


func check_radar_health_edge(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	var draw := reader.symbol_address("__ZN5Radar4drawEi")
	var edge: Dictionary = reader.radar_health_edge(draw)
	check(same_saved_value(edge, {"enemy": {"color": 0xbbbbbb66, "gap": 4},
		"ally": {"color": 0xaaaaaa66, "gap": 4}}), "Read original translucent health edges")
	for record in [["enemy", 0x30e, 0x340, 0x374], ["ally", 0xb76, 0xba8, 0xbdc]]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u32(literal_file_offset(reader, draw + int(record[1])), 0xabcdef77)
		check(reader.radar_health_edge(draw)[record[0]].color == 0xabcdef77,
			"Health edge color follows supplied " + record[0] + " declaration")
		reader.bytes.encode_u16(reader.file_offset(draw + int(record[2]), 2), 0x3305)
		check(reader.radar_health_edge(draw)[record[0]].gap == 5,
			"Health edge placement follows supplied " + record[0] + " declaration")
		reader.bytes.encode_u16(reader.file_offset(draw + int(record[3]), 2), 0xffff)
		check(reader.radar_health_edge(draw).is_empty() and not reader.error.is_empty(),
			"Reject unsupported " + record[0] + " health edge consumer")
		reader.error = ""
	for value in [null, {}, {"enemy": edge.enemy},
		{"enemy": {"color": -1, "gap": 4}, "ally": edge.ally},
		{"enemy": edge.enemy, "ally": {"color": 1, "gap": -1}}]:
		var bad: Dictionary = lib.content.flight_ui.radar.duplicate(true)
		bad.health_edge = value
		check(not lib.valid_radar_ui(bad), "Reject malformed cached health edge")
	check(lib.valid_radar_ui(lib.content.flight_ui.radar), "Valid health edge recovers after rejection")


func check_radar_lead(source: PackedByteArray, lib) -> void:
	var radar: Dictionary = lib.content.flight_ui.radar
	check(
		(
			is_equal_approx(radar.lead.bucket, 160)
			and is_equal_approx(radar.lead.scale, 307.2)
			and radar.lead.minimum == 1
			and radar.lead.enabled
			and lib.text(radar.lead.option_text) == "Targeting reticle"
		),
		"Import original targeting reticle geometry and saved-option default"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index targeting reticle declarations")
	var draw := reader.symbol_address("__ZN5Radar4drawEi")
	var globals := reader.symbol_address("__ZN7GlobalsC2Ev")
	for item in [[0x3ea, 4000.0, "bucket", 80.0], [0x400, 15.0, "scale", 153.6]]:
		var changed := source.duplicate()
		changed.encode_float(literal_file_offset(reader, draw + item[0]), item[1])
		reader.bytes = changed
		var rule := reader.radar_lead_presentation(draw)
		check(
			not rule.is_empty() and is_equal_approx(rule[item[2]], item[3]),
			"Prediction follows changed source " + item[2]
		)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(globals + 0x56, 2), 0x2000)
	reader.bytes = changed
	var rule := reader.radar_lead_presentation(draw)
	check(
		not rule.is_empty() and not rule.enabled,
		"Reticle default follows original option declaration"
	)
	for offset in [0x3a6, 0x3c2, 0x3fc, 0x42e]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(draw + offset, 2), 0xffff)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.radar_lead_presentation(draw).is_empty() and not reader.error.is_empty(),
			"Reject unsupported targeting association or units"
		)
	for key in ["bucket", "scale", "minimum", "enabled", "option_text"]:
		var bad := radar.duplicate(true)
		bad.lead[key] = null
		check(not lib.valid_radar_ui(bad), "Reject malformed cached targeting field " + key)
	for value in [0, -1, INF, NAN]:
		var bad := radar.duplicate(true)
		bad.lead.bucket = value
		check(not lib.valid_radar_ui(bad), "Reject invalid prediction distance bucket")
	check(lib.valid_radar_ui(radar), "Valid targeting data survives rejection checks")


func check_radar_hit_feedback(lib) -> void:
	var pilot = Session.new()
	pilot.configure(lib)
	check(pilot.depart(), "Start real campaign hit-feedback fixture")
	for actor in pilot.active_job.actors:
		actor.awake = true
	var flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {})
	flight.set_physics_process(false)
	var target: Dictionary = {}
	for actor in flight.actors:
		if flight.hostile(actor):
			target = actor
			break
	check(not target.is_empty(), "Imported training provides a damageable target")
	if target.is_empty():
		flight.free()
		return
	var old_hp: float = target.state.hp
	check(
		Combat.fire(pilot.combat, pilot.weapon_id, target.node.position, Vector3.FORWARD, lib),
		"Emit a real player projectile at the imported target"
	)
	flight.advance_projectiles(1.0 / 60)
	check(target.state.hp < old_hp, "Hit feedback follows a resolved damaging collision")
	check(
		flight.weapon_hit_ms == lib.content.flight_ui.radar.hit_ms,
		"Player impact starts imported hit feedback duration"
	)
	var remaining: float = flight.weapon_hit_ms
	flight.pause(true)
	flight._physics_process(1)
	check(flight.weapon_hit_ms == remaining, "Paused simulation holds the hit feedback clock")
	flight.pause(false)
	flight.step(.05)
	check(
		is_equal_approx(flight.weapon_hit_ms, maxf(0, remaining - 50)),
		"Hit feedback advances in simulation milliseconds"
	)
	flight.step(remaining / 1000)
	check(flight.weapon_hit_ms == 0, "Hit feedback expires after the source interval")
	flight.free()


func check_battle_contracts(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.battles
	check(
		ContractEncounters.valid_battle_parameters(parameters, lib),
		"Validate combat contract declarations"
	)
	check(
		parameters.types.map(func(id): return int(id)) == [1, 2],
		"Read Pirates and Combat mission dispatch associations"
	)
	check(
		parameters.wingman.opening.map(func(id): return int(id)) == [482, 483, 484, 485, 486],
		"Read allied pilot radio pool"
	)
	check(
		parameters.wingman.initial_hp == 600 and parameters.wingman.ahead == 2000,
		"Read allied initial health and placement"
	)
	var alternatives := {}
	var scenery := {}
	var heavy_seen := false
	for region in 4:
		var station := -1
		for index in lib.stations.size():
			if lib.station_definition(index).quadrant == region:
				station = index
				break
		for kind in parameters.types:
			for race in [0, 1]:
				var offer := Contracts.terms(lib.content.contracts, region, int(kind), 9)
				offer.origin_station = station
				offer.client = {"name": "Client", "race": race, "portrait": 11, "profession": 444}
				for seed_value in 10:
					var definition := ContractEncounters.battle(
						lib, parameters, offer, 5, seed_value
					)
					check(
						not definition.is_empty(),
						"Generate combat contract across regions, races and seeds"
					)
					if definition.is_empty():
						continue
					check(
						(
							definition
							== ContractEncounters.battle(lib, parameters, offer, 5, seed_value)
						),
						"Combat contract generation is deterministic"
					)
					var enemies: Array = definition.groups.filter(
						func(group): return group.get("team", "enemy") == "enemy"
					)
					var allies: Array = definition.groups.filter(
						func(group): return group.get("team") == "ally"
					)
					check(
						enemies.size() == region + 5,
						"Original difficulty and region determine the whole enemy group"
					)
					check(
						definition.route.size() == (2 if kind == 1 else 1),
						"Pirates retain two live route points, Combat missions one"
					)
					check(
						definition.route[0][2] >= 70000 and definition.route[0][2] < 100000,
						"Source battle approach range is preserved"
					)
					if kind == 1:
						check(
							(
								allies.size() == 1
								and enemies.all(func(group): return group.actor == 4)
							),
							"Pirate contracts have their fixed enemy model and a guaranteed ally"
						)
						check(
							definition.route[1][2] >= 117500 and definition.route[1][2] <= 142498,
							"Pirate second point keeps both random contributions"
						)
					else:
						alternatives[allies.size()] = true
					var heavy_count := enemies.filter(func(group): return group.actor == 18).size()
					heavy_seen = heavy_seen or heavy_count > 0
					check(
						heavy_count <= region and (race != 1 or heavy_count == 0),
						"Combat heavy ships obey the regional quota and client race"
					)
					check(
						enemies.all(
							func(group): return group.sleeping and group.center in definition.route
						),
						"Enemy groups sleep at their own imported route points"
					)
					scenery["fog" if definition.has("fog") else ("field" if not definition.scenery.is_empty() else "none")] = true
					var state := Session.Mission.create(
						definition, 0, station, lib, seed_value, 5, "contract"
					)
					check(
						state.target == enemies.size(), "Ally is excluded from required enemy count"
					)
					for waypoint in definition.route.size():
						Session.Mission.reach_waypoint(definition, state)
					check(
						not state.ready,
						"Following the route alone never completes a combat contract"
					)
					if not allies.is_empty():
						var ally: Dictionary = allies[0]
						check(
							ally.route == definition.route and ally.behavior == "escort",
							"Allied pilot follows the cloned mission route"
						)
						check(
							ally.initial_hp == 600 and ally.hull >= 600,
							"Allied initial health raises a smaller factory maximum"
						)
						check(
							(
								ally.center[0] >= -700
								and ally.center[0] <= 699
								and ally.center[1] >= -700
								and ally.center[1] <= 699
								and ally.center[2] == 2000
							),
							"Ally appears beside and ahead of the player"
						)
						check(
							(
								definition.radio[0].speaker == (4 if race == 1 else 6)
								and parameters.wingman.opening.any(
									func(id): return id == definition.radio[0].text
								)
							),
							"Ally replaces ordinary opening with the correct faction portrait"
						)
						check(
							(
								definition.radio[0].condition == "elapsed"
								and definition.radio[0].value == 2000
							),
							"Ally radio retains source elapsed trigger"
						)
						check(
							state.actors.back().awake and state.actors.back().hp == 600,
							"Ally starts awake at source initial health"
						)
						check(
							Session.Mission.damage(
								definition, state, state.actors.size() - 1, 100000
							),
							"Allied pilot can be lost"
						)
						check(
							not state.ready and not state.failed and state.kills == 0,
							"Ally loss is neither an enemy kill nor an invented defeat condition"
						)
					for index in enemies.size():
						state.actors[index].awake = true
						check(
							Session.Mission.damage(definition, state, index, 100000),
							"Defeat a combat contract enemy"
						)
						check(
							state.ready == (index == enemies.size() - 1),
							"Victory occurs only after the last enemy"
						)
	check(
		alternatives.size() == 2 and scenery.size() == 3 and heavy_seen,
		"Exercise optional ally, all scenery variants and heavy combat ships"
	)
	# Special clients preserve their complete source radio exchange despite the ally.
	var special := Contracts.terms(lib.content.contracts, 0, 1, 9, true)
	special.origin_station = 0
	for index in lib.stations.size():
		if lib.station_definition(index).quadrant == 0:
			special.origin_station = index
			break
	special.client = {"name": "Client", "race": 1, "portrait": 31, "profession": 444}
	var special_definition := ContractEncounters.battle(lib, parameters, special, 100, 3)
	check(not special_definition.is_empty(), "Build high-rank special-client battle")
	if not special_definition.is_empty():
		check(
			(
				special_definition.radio[0].speaker == 31
				and (
					special_definition.radio[0].text
					== lib.content.contracts.hunt.radio.special_start[1]
				)
			),
			"Special client keeps original opening message"
		)
		check(
			(
				special_definition.groups.back().hull > 600
				and special_definition.groups.back().initial_hp == 600
			),
			"Source initial health does not reduce a larger factory maximum"
		)
	for key in ["spread", "initial_hp"]:
		var invalid := parameters.duplicate(true)
		invalid.wingman[key] = 0
		check(
			not ContractEncounters.valid_battle_parameters(invalid, lib),
			"Reject invalid allied pilot " + key
		)
	for malformed in [null, {}, {"selection": "fixed"}]:
		var invalid := parameters.duplicate(true)
		invalid.variants[0] = malformed
		check(
			not ContractEncounters.valid_battle_parameters(invalid, lib),
			"Reject malformed combat family cache"
		)
	var invalid := parameters.duplicate(true)
	invalid.variants[1].wingman_chance = [101, 100]
	check(
		not ContractEncounters.valid_battle_parameters(invalid, lib),
		"Reject impossible allied pilot probability"
	)
	invalid = parameters.duplicate(true)
	invalid.variants[0].route_axes[5].rolls = [0]
	check(
		not ContractEncounters.valid_battle_parameters(invalid, lib),
		"Reject invalid combat coordinate distribution"
	)
	invalid = parameters.duplicate(true)
	invalid.variants[1].heavy_combat.weapon.guidance.response_divisor = 0
	check(
		not ContractEncounters.valid_battle_parameters(invalid, lib),
		"Reject invalid combat rocket guidance"
	)
	check_battle_source_mutations(source)
	check_battle_sessions(lib)


func check_battle_source_mutations(source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index battle and allied pilot declarations")
	var wing := reader.symbol_address("__ZN5Level13createWingmanEv")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(wing + 0x1fc, 2), 0x21c8)
	reader.bytes = changed
	var result := reader.contract_wingman()
	check(
		not result.is_empty() and result.initial_hp == 800,
		"Allied initial health follows changed source operand"
	)
	changed = source.duplicate()
	changed.encode_u32(literal_file_offset(reader, wing + 0x184), 0xfffffc7c)
	reader.bytes = changed
	result = reader.contract_wingman()
	check(not result.is_empty() and result.offset == -900, "Allied placement follows source offset")
	for offset in [0x80, 0xdc, 0x158, 0x1f6]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(wing + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_wingman().is_empty() and not reader.error.is_empty(),
			"Reject unknown ally radio, factory or route binding"
		)
	reader.bytes = source
	reader.error = ""
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var pirates := table + reader.u32(table + 8)
	var combat := table + reader.u32(table + 12)
	changed = source.duplicate()
	changed.encode_u32(literal_file_offset(reader, pirates + 0x82), 71000)
	reader.bytes = changed
	result = reader.contract_battles()
	check(
		not result.is_empty() and result.variants[0].route_axes[2].base == 71000,
		"Pirate route follows supplied coordinate rather than a runtime constant"
	)
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(combat + 0x1e6, 2), 0x2800)
	reader.bytes = changed
	reader.error = ""
	result = reader.contract_battles()
	check(
		not result.is_empty() and result.variants[1].wingman_chance == [1, 100],
		"Battle ally chance follows source threshold"
	)
	for address in [pirates + 0x1ae, pirates + 0x3f0, combat + 0x2da, combat + 0x1e8]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_battles().is_empty() and not reader.error.is_empty(),
			"Reject unsupported combat route, objective, quota or ally branch"
		)


func check_battle_sessions(lib) -> void:
	for kind in lib.content.contracts.battles.types:
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.skip_campaign()
		var selected := -1
		for seed_value in 1000:
			pilot.market_seed = seed_value
			var board := pilot.contract_offers()
			for index in board.size():
				if board[index].type == kind:
					selected = index
					break
			if selected >= 0:
				break
		check(selected >= 0, "Find source-generated combat offer on actual board")
		if selected < 0:
			continue
		var quote: Dictionary = pilot.contract_offers()[selected]
		var cash := pilot.credits
		check(pilot.begin_contract(selected), "Accept combat mission through normal station flow")
		if pilot.active_job.is_empty():
			continue
		var restored := Session.new()
		restored.configure(lib)
		check(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
			"Restore accepted battle: " + restored.error
		)
		check(
			restored.mission_definition() == pilot.mission_definition(),
			"Reload regenerates battle route, actors, radio and allied pilot"
		)
		var definition := pilot.mission_definition()
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, pilot, {})
		flight.set_physics_process(false)
		check(
			flight.station == null and flight.ambience.get_child_count() == 0,
			"Battle world has no placeholder station or ambient rocks"
		)
		if definition.groups.back().get("team") == "ally":
			var ally_position: Array = pilot.active_job.actors.back().position.duplicate()
			flight.step(1.0 / 60)
			check(
				pilot.active_job.actors.back().position != ally_position,
				"Allied pilot moves along the route in the actual flight simulation"
			)
		flight.free()
		pilot.advance_mission(2.1)
		pilot.advance_radio(.01)
		for index in pilot.active_job.actors.size():
			if (
				definition.groups[int(pilot.active_job.actors[index].group)].get("team", "enemy")
				== "enemy"
			):
				pilot.active_job.actors[index].awake = true
				pilot.damage_actor(index, 100000)
		check(pilot.active_job.ready, "Clearing the enemy group completes the battle")
		check(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
			"Restore victory while closing radio remains"
		)
		for tick in 1200:
			pilot.advance_radio(.1)
			if pilot.ready_to_finish():
				break
		check(
			pilot.ready_to_finish() and pilot.finish_mission(),
			"Finish combat mission after source closing dialogue"
		)
		check(
			pilot.docked and pilot.credits == cash + int(quote.reward),
			"Combat mission returns to station with exact quoted payment"
		)
		check(
			not pilot.finish_mission() and pilot.credits == cash + int(quote.reward),
			"Combat reward cannot be claimed twice"
		)
		check(
			pilot.campaign_state == "skipped" and pilot.progression.rewards.is_empty(),
			"Combat mission does not invent campaign completion"
		)
		check(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
			"Combat payment receipt survives reload"
		)


func check_hunt_spawn_scatter(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.hunt
	check(parameters.scatter_divisor == 10, "Read source freelance hunt spawn divisor")
	var offer := Contracts.terms(lib.content.contracts, 3, 3, 9)
	offer.origin_station = 375
	offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
	for kind in parameters.types:
		offer = Contracts.terms(lib.content.contracts, 3, int(kind), 9)
		offer.origin_station = 375
		offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
		for seed_value in 24:
			var definition := ContractEncounters.hunt(lib, parameters, offer, 5, seed_value)
			var legacy := definition.duplicate(true)
			for group in legacy.groups:
				group.erase("scatter_divisor")
			var state := Session.Mission.create(definition, 0, 375, lib, seed_value, 5, "contract")
			var old_state := Session.Mission.create(legacy, 0, 375, lib, seed_value, 5, "contract")
			for index in state.actors.size():
				var center := Session.Mission.point(
					definition.groups[int(state.actors[index].group)].center
				)
				var offset := Combat.vector(state.actors[index].position) - center
				var old_offset := Combat.vector(old_state.actors[index].position) - center
				check(
					offset.abs()[offset.abs().max_axis_index()] <= 64.001,
					"Hunt target and escorts spawn within the source 64m half-width"
				)
				var scaled := Vector3.ZERO
				for axis in 3:
					scaled[axis] = (roundi(old_offset[axis] * 50) / 10) / 50.0
				check(
					offset.distance_to(scaled) < .001,
					"Same random roll is divided after sampling on every axis"
				)
			check(
				Session.Mission.valid(definition, old_state, 0, 375, lib, "contract", 5),
				"Legacy wide-position active hunt still validates"
			)
	var definition := ContractEncounters.hunt(lib, parameters, offer, 5, 37)
	for pair in [
		[-20, -2],
		[-19, -1],
		[-10, -1],
		[-9, 0],
		[-1, 0],
		[0, 0],
		[1, 0],
		[9, 0],
		[10, 1],
		[19, 1],
		[20, 2]
	]:
		var fixed := definition.duplicate(true)
		fixed.groups[0].scatter = [[pair[0], pair[0]], [pair[0], pair[0]], [pair[0], pair[0]]]
		var state := Session.Mission.create(fixed, 0, 375, lib, 37, 5, "contract")
		var actual := (
			Combat.vector(state.actors[0].position) - Session.Mission.point(fixed.groups[0].center)
		)
		var expected := Session.Mission.point([pair[1], pair[1], pair[1]])
		check(
			actual.distance_to(expected) < .001,
			"Signed spawn division truncates toward zero: " + str(pair)
		)
	for bad in [0, -1, .5, "10", null, 1000001]:
		var invalid := parameters.duplicate(true)
		invalid.scatter_divisor = bad
		check(
			not ContractEncounters.valid_parameters(invalid, lib),
			"Reject invalid cached hunt divisor"
		)
		var invalid_mission := definition.duplicate(true)
		invalid_mission.groups[0].scatter_divisor = bad
		check(not lib.valid_mission(invalid_mission), "Reject invalid native spawn divisor")
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index source spawn classification")
	var factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var changed := source.duplicate()
	for offset in [0x136, 0x13c, 0x146]:
		changed.encode_u16(reader.file_offset(factory + offset, 2), 0x2105)
	reader.bytes = changed
	check(
		reader.contract_spawn_divisor([0, 3]) == 5,
		"All three source division operands control native spacing"
	)
	for offset in [0xea, 0xec, 0xfc, 0x120, 0x138, 0x13c, 0x142, 0x14c]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(factory + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_spawn_divisor([0, 3]) == 0 and not reader.error.is_empty(),
			"Reject unsupported hunt type, divisor or rounding consumer"
		)
	# These legacy positions were created using the previous native policy. Restore
	# retains live coordinates and projectiles rather than respawning from the seed.
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var board := pilot.contract_offers()
		for index in board.size():
			if (
				parameters.types.any(func(kind): return kind == board[index].type)
				and board[index].tier >= 7
			):
				selected = index
				break
		if selected >= 0:
			break
	check(selected >= 0 and pilot.begin_contract(selected), "Start save compatibility hunt")
	if selected < 0:
		return
	var current := pilot.mission_definition()
	var legacy := current.duplicate(true)
	for group in legacy.groups:
		group.erase("scatter_divisor")
	var reference: Dictionary = pilot.active_job.contract.duplicate(true)
	pilot.active_job = Session.Mission.create(
		legacy,
		pilot.chapter,
		pilot.station_id,
		lib,
		int(pilot.active_job.seed),
		pilot.rank(),
		"contract"
	)
	pilot.active_job.contract = reference
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(saved),
		"Restore old-format active hunt without an unnecessary save conversion"
	)
	check(
		JSON.parse_string(JSON.stringify(restored.capture())) == saved,
		"Old hunt preserves complete saved state including positions"
	)
	for actor in restored.active_job.actors:
		actor.awake = true
	restored.advance_mission(2.1)
	restored.advance_radio(.01)
	restored.damage_actor(0, 100000)
	for tick in 1200:
		restored.advance_mission(.1)
		restored.advance_radio(.1)
		if restored.ready_to_finish():
			break
	check(
		restored.ready_to_finish() and restored.finish_mission(),
		"Old-position hunt still completes and pays normally"
	)


func check_clearance_contracts(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.clearance
	check(
		parameters.types == [4.0] and parameters.center == [0.0, 0.0, 25000.0],
		"Recover space-junk category and local center"
	)
	check(
		(
			parameters.debris_base == 28
			and parameters.pirate_factor == 4
			and parameters.deadline_ms == 120000
		),
		"Recover source counts and two-minute deadline"
	)
	for region in 4:
		for tier in range(1, 10):
			var offer := Contracts.terms(lib.content.contracts, region, 4, tier)
			offer.origin_station = region * 125
			offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
			var definition := ContractEncounters.clearance(lib, parameters, offer, 5, 37)
			check(not definition.is_empty(), "Generate valid regional clearance")
			if definition.is_empty():
				continue
			var expected_debris := 28 + int(Contracts.f32(Contracts.f32(float(tier) / 10.0) * 10.0))
			var expected_pirates := int(Contracts.f32(Contracts.f32(float(tier) / 10.0) * 4.0))
			check(
				(
					definition.groups[0].count == expected_debris
					and definition.success.count == expected_debris
				),
				"Source-rounded debris count"
			)
			check(
				definition.groups.size() == (2 if expected_pirates > 0 else 1),
				"Zero pirate count omits defending group"
			)
			if expected_pirates:
				check(
					(
						definition.groups[1].count == expected_pirates
						and definition.groups[1].actor == 4
						and not definition.groups[1].sleeping
					),
					"Source fighter defenders are awake"
				)
			check(
				definition.route.is_empty() and definition.scenery.is_empty(),
				"Temporary spawn route adds no player waypoints or filler scenery"
			)
			var state := Session.Mission.create(
				definition, 0, int(offer.origin_station), lib, 37, 5, "contract"
			)
			for actor in state.actors:
				if actor.group == 0:
					var offset := (
						Combat.vector(actor.position) - Session.Mission.point(parameters.center)
					)
					check(
						offset.abs()[offset.abs().max_axis_index()] <= 160.01,
						"Debris uses static-factory scatter"
					)
			for i in range(expected_debris, state.actors.size()):
				Session.Mission.damage(definition, state, i, 100000)
			check(
				(
					not state.ready
					and Session.Mission.destroyed_prefix(definition, state, expected_debris) == 0
				),
				"Defenders never substitute for debris objectives"
			)
			for i in expected_debris:
				Session.Mission.damage(definition, state, i, 100000)
			check(not state.ready, "Clearance waits for debris destruction after hull loss")
			finish_wrecks_fixture(definition,state,lib)
			check(state.ready, "Debris clearance completes the objective")
			state = Session.Mission.create(
				definition, 0, int(offer.origin_station), lib, 37, 5, "contract"
			)
			for i in expected_debris:
				Session.Mission.damage(definition, state, i, 100000)
			finish_wrecks_fixture(definition,state,lib)
			check(
				state.ready and (expected_pirates == 0 or state.actors.back().hp > 0),
				"Clearance succeeds with surviving pirates"
			)
			state = Session.Mission.create(
				definition, 0, int(offer.origin_station), lib, 37, 5, "contract"
			)
			Session.Mission.advance(definition, state, 120.001, lib)
			check(state.failed and not state.ready, "Source deadline fails incomplete clearance")
	for pair in [
		["debris_base", 0],
		["debris_actor", 999],
		["pirate_factor", 0],
		["deadline_ms", -1],
		["scatter", null],
		["relative_divisors", [0, 3, 7, 15]],
		["success_kind", "enemies_destroyed"]
	]:
		var invalid := parameters.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(
			not ContractEncounters.valid_clearance_parameters(invalid, lib),
			"Reject malformed clearance cache"
		)
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = table + reader.u32(table + 4 + 4 * 4)
	var modified := source.duplicate()
	modified.encode_u16(reader.file_offset(start + 0x122, 2), 0x3020)
	reader.bytes = modified
	reader.error = ""
	check(
		reader.contract_clearance().get("debris_base") == 32 and reader.error.is_empty(),
		"Clearance base count comes from supplied bytes"
	)
	modified = source.duplicate()
	var literal_instruction: int = reader.u16(start + 0x40a)
	var literal_address: int = ((start + 0x40a + 4) & ~3) + (literal_instruction & 255) * 4
	modified.encode_u32(reader.file_offset(literal_address, 4), 90000)
	reader.bytes = modified
	reader.error = ""
	check(
		reader.contract_clearance().get("deadline_ms") == 90000,
		"Clearance deadline comes from supplied bytes"
	)
	for offset in [0x34, 0x120, 0x168, 0x180, 0x1bc, 0x204, 0x20a, 0x40e]:
		modified = source.duplicate()
		modified.encode_u16(reader.file_offset(start + offset, 2), 0xbf00)
		reader.bytes = modified
		reader.error = ""
		check(
			reader.contract_clearance().is_empty() and not reader.error.is_empty(),
			"Reject unsupported clearance data consumer"
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type == 4 and offers[index].tier >= 7:
				selected = index
				break
		if selected >= 0:
			break
	check(
		selected >= 0 and pilot.begin_contract(selected),
		"Accept clearance from live contract board"
	)
	if selected < 0:
		return
	var cash := pilot.credits
	var quote := Contracts.reference_offer(lib, pilot.market_seed, pilot.active_job.contract)
	var count := int(pilot.mission_definition().success.count)
	pilot.damage_actor(0, 100000)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var restored := Session.new()
	restored.configure(lib)
	check(restored.restore(saved), "Restore active clearance: " + restored.error)
	check(
		(
			restored.active_job.actors[0].hp == 0
			and restored.mission_definition() == pilot.mission_definition()
		),
		"Clearance progress and declaration survive load"
	)
	var invalid := pilot.mission_definition().duplicate(true)
	invalid.success.count = 0
	check(not lib.valid_mission(invalid), "Reject empty prefix objective")
	invalid.success.count = 999
	check(not lib.valid_mission(invalid), "Reject oversized prefix objective")
	for i in range(1, count):
		restored.damage_actor(i, 100000)
	for tick in 1800:
		restored.advance_mission(.1)
		restored.advance_radio(.1)
		if restored.ready_to_finish():
			break
	check(
		restored.ready_to_finish() and restored.finish_mission(),
		"Settle clearance after original closing radio"
	)
	check(
		restored.credits == cash + int(quote.reward) and restored.contract_rewards.size() == 1,
		"Clearance pays source quote exactly once"
	)
	check(
		not restored.finish_mission() and restored.credits == cash + int(quote.reward),
		"Repeated settlement cannot pay twice"
	)
	check(pilot.restore(saved), "Restore clearance before timeout")
	pilot.advance_mission(121)
	check(pilot.active_job.failed and not pilot.finish_mission(), "Timed-out job cannot pay")
	pilot.retry_mission()
	check(
		pilot.docked and pilot.credits == cash and pilot.begin_contract(selected),
		"Timed-out job can be retried without payment"
	)


func check_mines(source: PackedByteArray, lib) -> void:
	var Mines = Session.Mission.Mines
	var parameters: Dictionary = lib.content.mine_behavior
	check(
		parameters.actor == 7 and parameters.fuse_ms == 2000 and parameters.damage == 25,
		"Mine actor, fuse and blast damage are read from the supplied source"
	)
	check(
		(
			is_equal_approx(parameters.arming_half_width, 59.98)
			and parameters.armed_meshes.map(func(id): return int(id)) == [10054, 10053]
		),
		"Mine arming extent and opening geometry retain source associations"
	)
	check(
		(
			parameters.explosion.layers[0].duration_ms == 750
			and parameters.explosion.layers[1].delay_ms == 250
			and parameters.explosion.layers[1].duration_ms == 1750
		),
		"Both explosion layers retain independent imported envelopes"
	)
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index mine constants for source mutation checks")
	var update := reader.symbol_address("__ZN10PlayerMine6updateEi")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(update + 0x1ee, 2), 0x237d)
	changed.encode_u16(reader.file_offset(update + 0x20e, 2), 0x210b)
	reader.bytes = changed
	var altered := reader.mine_behavior(lib.content.resources)
	check(
		reader.error.is_empty() and altered.fuse_ms == 1000 and altered.damage == 11,
		"Changing supplied fuse and damage changes native mine parameters"
	)
	for offset in [0xd4, 0xde, 0x210, 0x1fe, 0x2f0]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(update + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.mine_behavior(lib.content.resources).is_empty() and not reader.error.is_empty(),
			"Reject changed mine lifecycle consumer %x" % offset
		)
	for key in ["fuse_ms", "damage", "arming_half_width"]:
		var invalid := parameters.duplicate(true)
		invalid[key] = NAN
		check(
			not Mines.valid_parameters(
				invalid, lib.content.resources, lib.content.tables.actor_hull.size()
			),
			"Reject invalid cached mine parameter: " + key
		)
	var mine := Mines.create()
	var opponents := [{"id": -1, "active": true, "position": Vector3(60, 0, 0)}]
	Mines.advance(mine, parameters, 1.0, Vector3.ZERO, opponents)
	check(mine.phase == "dormant", "Outside the source proximity cube does not arm a mine")
	opponents[0].position = Vector3(59, 59, 59)
	var event := Mines.advance(mine, parameters, .5, Vector3.ZERO, opponents)
	check(
		event.armed and mine.phase == "armed" and mine.elapsed_ms == 500,
		"Corner proximity arms the cube, not an invented sphere"
	)
	Mines.advance(mine, parameters, 1.5, Vector3.ZERO, opponents)
	check(mine.phase == "armed", "A fuse exactly at its source limit has not detonated")
	event = Mines.advance(mine, parameters, .001, Vector3.ZERO, opponents)
	check(
		event.detonated and event.damage_target == -1 and mine.phase == "burst",
		"Crossing the fuse limit applies the imported blast once"
	)
	check(
		not Mines.actor_dead({"hp": 0, "mine": mine}), "Exploding mine is inactive but not yet dead"
	)
	var stored := mine.duplicate(true)
	Mines.advance(mine, parameters, 0, Vector3.ZERO, opponents)
	check(mine == stored, "Zero simulation time preserves the mine explosion")
	event = Mines.advance(mine, parameters, 1.0, Vector3.ZERO, opponents)
	check(
		not event.detonated and not event.finished and mine.phase == "burst",
		"Explosion never reapplies blast damage and waits for both layers"
	)
	event = Mines.advance(mine, parameters, 1.0, Vector3.ZERO, opponents)
	check(
		event.finished and mine.phase == "dead",
		"Mine becomes dead only after its delayed layer fades"
	)
	# Preserve the audited source quirk, including original Z-axis orientation.
	mine = Mines.create()
	Mines.advance(
		mine, parameters, 1, Vector3.ZERO, [{"id": -1, "active": true, "position": Vector3.ZERO}]
	)
	event = Mines.advance(
		mine,
		parameters,
		1.1,
		Vector3.ZERO,
		[{"id": -1, "active": true, "position": Vector3(1000, 1000, -1000)}]
	)
	check(
		event.damage_target == -1,
		"Source upper-axis blast compatibility preserves its asymmetric bounds"
	)
	mine = Mines.create()
	Mines.advance(
		mine, parameters, 1, Vector3.ZERO, [{"id": -1, "active": true, "position": Vector3.ZERO}]
	)
	event = Mines.advance(
		mine,
		parameters,
		1.1,
		Vector3.ZERO,
		[{"id": -1, "active": true, "position": Vector3(-1000, 0, 0)}]
	)
	check(
		event.damage_target == -2 and event.detonated,
		"Leaving on a rejected source axis avoids damage without cancelling the fuse"
	)
	var definition: Dictionary = lib.mission_definition(11)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 11
	pilot.progression = Session.Progression.create(11)
	pilot.station_id = lib.chapter_destination(10)
	check(pilot.depart(), "Start the real campaign minefield for lifecycle and save checks")
	var state: Dictionary = pilot.active_job
	var original_hp: float = state.actors[0].hp
	pilot.damage_actor(0, 100000)
	check(
		state.actors[0].hp == original_hp and state.kills == 0,
		"Remote gunfire cannot clear a dormant campaign mine"
	)
	var position := Combat.vector(state.actors[0].position)
	Session.Mission.advance_mines(definition, state, .1, position, lib)
	check(
		state.actors[0].mine.phase == "armed", "Real campaign mine arms when the pilot approaches"
	)
	check(
		(
			pilot.damage_actor(0, original_hp)
			and state.actors[0].mine.phase == "shot"
			and state.kills == 1
		),
		"Armed mine can be shot down, earning one kill without a fuse blast"
	)
	check(
		not Session.Mission.destroyed_prefix(definition, state, 1),
		"Clearance prefix waits while its last mine is exploding"
	)
	var saved := pilot.capture()
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(saved))),
		"Save and restore an explosion in the actual campaign"
	)
	check(
		same_saved_value(restored.active_job, state),
		"Restoring mines preserves actor positions, radio, damage and timers"
	)
	var events := Session.Mission.advance_mines(definition, state, 2.0, Vector3(1e6, 1e6, 1e6), lib)
	check(
		(
			Session.Mission.destroyed_prefix(definition, state, 1) == 1
			and not events.any(func(item): return item.damage_target != -2)
		),
		"Shooting a mine clears it after the effect with no proximity damage"
	)
	check(
		Session.Mission.valid(definition, state, 11, pilot.station_id, lib),
		"Completed mine effects leave a valid campaign state"
	)
	var old := pilot.capture()
	old.schema = 14
	for actor in old.active_job.actors:
		actor.erase("mine")
	check(restored.restore(old), "Previous-schema campaign saves migrate mine lifecycle data")
	check(
		(
			restored.active_job.actors[0].mine.phase == "dead"
			and restored.active_job.kills == state.kills
		),
		"Migration preserves cleared mines and kill counts without granting rewards"
	)
	var invalid_save := pilot.capture()
	invalid_save.active_job.actors[0].mine.phase = "armed"
	check(not restored.restore(invalid_save), "Reject a saved active mine with zero hull")
	var invalid_state := Mines.create()
	invalid_state.phase = "armed"
	invalid_state.elapsed_ms = parameters.fuse_ms + 1
	check(
		not Mines.valid(invalid_state, original_hp, parameters),
		"Reject a fuse saved beyond detonation without its phase transition"
	)


func clear_mine_fixture(definition: Dictionary, state: Dictionary, index: int, lib) -> void:
	# Isolate one actor for radio/director unit fixtures. Actual pilot movement,
	# projectile hits and collateral arming are exercised by the flight checks.
	var actor: Dictionary = state.actors[index]
	Session.Mission.Mines.advance(
		actor.mine,
		lib.content.mine_behavior,
		.001,
		Combat.vector(actor.position),
		[{"id": -1, "active": true, "position": Combat.vector(actor.position)}]
	)
	Session.Mission.damage(definition, state, index, 100000)
	Session.Mission.Mines.advance(actor.mine, lib.content.mine_behavior, 2.0, Vector3.ZERO, [])
	Session.Mission.evaluate(definition, state)


func check_minefield_contracts(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.minefield
	check(
		(
			parameters.types == [5.0]
			and parameters.total_base == 16
			and parameters.total_variation == 11
			and parameters.defenders == 1
		),
		"Recover minefield category and independent randomized target count"
	)
	check(
		parameters.center_bounds == [[-2500.0, 2499.0], [-2500.0, 2499.0], [40000.0, 40000.0]],
		"Recover source minefield center bounds"
	)
	var observed := {}
	for seed_value in 64:
		for region in 4:
			var tier := 1 + seed_value % 9
			var offer := Contracts.terms(lib.content.contracts, region, 5, tier)
			offer.origin_station = region * 125
			offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
			var definition := ContractEncounters.minefield(lib, parameters, offer, 5, seed_value)
			check(
				not definition.is_empty(),
				"Generate source minefield for every region and offer tier"
			)
			if definition.is_empty():
				continue
			var mines := int(definition.success.count)
			observed[mines] = true
			check(
				(
					mines >= 15
					and mines <= 25
					and definition.groups[0].count == mines
					and definition.groups[0].actor == 7
				),
				"Minefield objective selects exactly its leading mine actors"
			)
			check(
				(
					definition.groups[1].count == 1
					and definition.groups[1].actor == 4
					and not definition.groups[1].sleeping
				),
				"Minefield has one active source pirate defender"
			)
			check(
				(
					definition.route.is_empty()
					and definition.scenery.is_empty()
					and not definition.has("fog")
					and definition.deadline_ms == 0
				),
				"Temporary spawn center adds no route, timer or invented scenery"
			)
			var center: Array = definition.groups[0].center
			check(
				(
					center[0] >= -2500
					and center[0] < 2500
					and center[1] >= -2500
					and center[1] < 2500
					and center[2] == 40000
				),
				"Generated minefield stays inside imported center bounds"
			)
			if seed_value != 0:
				continue
			var state := Session.Mission.create(
				definition, 0, int(offer.origin_station), lib, seed_value, 5, "contract"
			)
			for index in mines:
				var actor: Dictionary = state.actors[index]
				var offset := (Combat.vector(actor.position) - Session.Mission.point(center)).abs()
				check(
					actor.mine.phase == "dormant" and offset[offset.max_axis_index()] <= 160.01,
					"Mine actor uses imported static placement and lifecycle"
				)
			Session.Mission.damage(definition, state, mines, 100000)
			check(
				not state.ready and Session.Mission.destroyed_prefix(definition, state, mines) == 0,
				"Killing the defender does not count as clearing a mine"
			)
			Session.Mission.advance(definition, state, 180, lib)
			check(not state.failed, "Minefield is not given the debris mission's timer")
	check(
		observed.has(15) and observed.has(25),
		"Source random count reaches both ends of the mine range"
	)
	for pair in [
		["total_base", 1],
		["total_variation", 0],
		["defenders", 2],
		["mine_actor", 9],
		["defender_actor", 999],
		["center_bounds", [[0, 1]]],
		["scatter", null],
		["success_kind", "enemies_destroyed"]
	]:
		var invalid := parameters.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(
			not ContractEncounters.valid_minefield_parameters(invalid, lib),
			"Reject malformed cached minefield declaration"
		)
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = table + reader.u32(table + 4 + 5 * 4)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(start + 0xde, 2), 0x3014)
	changed.encode_u16(reader.file_offset(start + 0xd4, 2), 0x2105)
	changed.encode_u32(literal_file_offset(reader, start + 0x14), 90000)
	reader.bytes = changed
	var altered := reader.contract_minefield()
	check(
		(
			reader.error.is_empty()
			and altered.total_base == 20
			and altered.total_variation == 5
			and altered.center_bounds[2] == [90000, 90000]
		),
		"Minefield count and location changes come from supplied bytes"
	)
	for offset in [0x30, 0x6e, 0x126, 0x158, 0x16e, 0x19c, 0x1ba, 0x1c0, 0x1e4]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(start + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_minefield().is_empty() and not reader.error.is_empty(),
			"Reject changed minefield factory/objective consumer"
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type == 5:
				selected = index
				break
		if selected >= 0:
			break
	check(
		selected >= 0 and pilot.begin_contract(selected),
		"Accept minefield from the actual station board"
	)
	if selected < 0:
		return
	var definition: Dictionary = pilot.mission_definition()
	var count := int(definition.success.count)
	var quote := Contracts.reference_offer(lib, pilot.market_seed, pilot.active_job.contract)
	var credits := pilot.credits
	clear_mine_fixture(definition, pilot.active_job, 0, lib)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(saved) and same_saved_value(restored.active_job, pilot.active_job),
		"Reload active minefield with cleared mines and exact remaining encounter"
	)
	for index in range(1, count):
		clear_mine_fixture(definition, restored.active_job, index, lib)
	check(
		restored.active_job.ready and restored.active_job.actors.back().hp > 0,
		"Clearing every mine wins while its pirate defender can survive"
	)
	for tick in 1800:
		restored.advance_radio(.1)
		if restored.ready_to_finish():
			break
	check(
		restored.ready_to_finish() and restored.finish_mission(),
		"Settle minefield after its original closing radio"
	)
	check(
		(
			restored.credits == credits + int(quote.reward)
			and restored.contract_rewards.size() == 1
			and restored.campaign_state == "skipped"
		),
		"Minefield pays exactly the board quote without altering campaign completion"
	)
	check(
		not restored.finish_mission() and restored.credits == credits + int(quote.reward),
		"Minefield cannot pay twice"
	)
	check(pilot.restore(saved), "Restore partial minefield before retry")
	pilot.hull = 0
	check(not pilot.finish_mission(), "Defeat never grants the minefield reward")
	pilot.retry_mission()
	check(
		pilot.docked and pilot.credits == credits and pilot.begin_contract(selected),
		"Retry starts the same minefield without granting money"
	)
	check(
		pilot.active_job.actors.all(
			func(actor): return not actor.has("mine") or actor.mine.phase == "dormant"
		),
		"Retry resets mine phases through normal encounter creation"
	)


func check_asteroid_contract_declarations(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read source index for asteroid contracts")
	var parameters := reader.contract_asteroids()
	check(
		not parameters.is_empty() and reader.error.is_empty(),
		"Read asteroid contract declarations: " + reader.error
	)
	if parameters.is_empty():
		return
	check(
		(
			parameters.types == [6]
			and parameters.duration_ms == 120000
			and parameters.pirate_divisor == 10
			and parameters.pirate_factor == 6
			and parameters.pirate_actor == 4
		),
		"Import survival duration and difficulty-based pirate counts"
	)
	check(
		(
			parameters.field.count == 40
			and parameters.field.width == 40000
			and parameters.field.hits == 11
			and parameters.payout_kind == "finished_asteroids"
		),
		"Import parent asteroid field, hit count and finished-effect payout basis"
	)
	check(
		parameters.center_bounds == [[-2500, 2499], [-2500, 2499], [40000, 40000]],
		"Import asteroid contract center bounds"
	)
	var counts := {}
	for region in 4:
		for tier in range(1, 10):
			for seed_value in 4:
				var rate := int(lib.content.contracts.rate_range[seed_value % 2])
				var offer := Contracts.terms(
					lib.content.contracts, region, 6, tier, seed_value % 2 == 1, rate
				)
				offer.origin_station = region * 125
				offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
				var definition := ContractEncounters.asteroids(
					lib, parameters, offer, 5, seed_value
				)
				check(
					not definition.is_empty(),
					"Generate asteroid survival contract for region/tier/rate"
				)
				if definition.is_empty():
					continue
				var count := 0
				for group in definition.groups:
					count += int(group.count)
					check(
						(
							group.actor == 4
							and not group.sleeping
							and group.center == definition.scenery[0].center
						),
						"Source pirates start awake at the field center"
					)
				counts[count] = true
				check(
					count == int(Contracts.f32(Contracts.f32(tier / 10.0) * 6.0)),
					"Pirate count follows relative difficulty with binary32 rounding"
				)
				check(
					(
						definition.route.is_empty()
						and definition.deadline_ms == 0
						and not definition.has("fog")
						and definition.success == {"kind": "time_survived", "duration_ms": 120000}
					),
					"Asteroid contract survives the timer instead of failing it or requiring a route"
				)
				var center: Array = definition.scenery[0].center
				check(
					(
						center[0] >= -2500
						and center[0] <= 2499
						and center[1] >= -2500
						and center[1] <= 2499
						and center[2] == 40000
					),
					"Generated field uses the source center bounds"
				)
				check(
					(
						definition
						== ContractEncounters.asteroids(lib, parameters, offer, 5, seed_value)
					),
					"Asteroid declarations regenerate deterministically"
				)
				var state := Session.Mission.create(
					definition, 0, int(offer.origin_station), lib, seed_value, 5, "contract"
				)
				Session.Mission.advance(definition, state, 120, lib)
				check(
					not state.ready and not state.failed,
					"Survival boundary is strictly after the source duration"
				)
				Session.Mission.advance(definition, state, .001, lib)
				check(
					(
						state.ready
						and not state.failed
						and state.scenery.rocks.all(func(rock): return rock.hits == 11)
					),
					"Survival completes with every asteroid and pirate still intact"
				)
				var wrong := offer.duplicate(true)
				wrong.reward = rate + 1000000
				check(
					ContractEncounters.asteroids(lib, parameters, wrong, 5, seed_value).is_empty(),
					"Reject per-target quotes outside the imported rate range"
				)
	check(
		counts.has(0) and counts.has(5), "Easy offers have no pirates; hardest normal tier has five"
	)
	for pair in [
		["pirate_divisor", 0],
		["pirate_factor", -1],
		["pirate_actor", 999],
		["duration_ms", 0],
		["types", [5]],
		["relative_divisors", [0]],
		["center_bounds", [[0, 1]]],
		["field", null],
		["success_kind", "enemies_destroyed"],
		["payout_kind", "hits"]
	]:
		var invalid := parameters.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(
			not ContractEncounters.valid_asteroid_parameters(invalid, lib),
			"Reject malformed asteroid declaration"
		)
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = table + reader.u32(table + 4 + 6 * 4)
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader, start + 0x17c), 180000)
	changed.encode_u32(literal_file_offset(reader, start + 0x14), 90000)
	changed.encode_float(literal_file_offset(reader, start + 0xee), 8)
	reader.bytes = changed
	var altered := reader.contract_asteroids()
	check(
		(
			reader.error.is_empty()
			and altered.duration_ms == 180000
			and altered.pirate_factor == 8
			and altered.center_bounds[2] == [90000, 90000]
		),
		"Changed source timer, location and pirate factor remain data driven"
	)
	var offer := Contracts.terms(
		lib.content.contracts, 0, 6, 9, false, int(lib.content.contracts.rate_range[0])
	)
	offer.origin_station = 0
	offer.client = {"race": 0, "portrait": 11, "name": "Client", "profession": 444}
	var updated := ContractEncounters.asteroids(lib, altered, offer, 5, 99)
	check(
		(
			not updated.is_empty()
			and updated.groups[0].count == 7
			and updated.success.duration_ms == 180000
			and updated.scenery[0].center[2] == 90000
		),
		"Native generator consumes altered source declarations"
	)
	for offset in [
		0x34, 0x6e, 0xa0, 0xe0, 0xea, 0xf0, 0x12a, 0x12e, 0x156, 0x162, 0x184, 0x19c, 0x1a6, 0x1da
	]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(start + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_asteroids().is_empty() and not reader.error.is_empty(),
			"Reject altered asteroid field, pirate, time or temporary-route consumers"
		)
	for pair in [
		["__ZN5MGame11finishLevelEv", 0xda],
		["__ZN13AsteroidField21getDestroyedAsteroidsEv", 0x18],
		["__ZN9Objective19isSurvivalObjectiveEv", 4],
		["__ZN8Asteroid6renderEib", 0x40]
	]:
		changed = source.duplicate()
		changed.encode_u16(
			reader.file_offset(reader.symbol_address(pair[0]) + int(pair[1]), 2), 0xbf00
		)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_asteroids().is_empty() and not reader.error.is_empty(),
			"Reject changed source payout or survival semantics"
		)
	# Shared quote validation changed to accept a per-target rate. Fixed offers
	# must still validate their original price and reject a modified quote.
	var fixed := Contracts.terms(lib.content.contracts, 0, 5, 1)
	fixed.origin_station = 0
	fixed.client = offer.client.duplicate(true)
	check(
		ContractEncounters.valid_offer(lib, lib.content.contracts.minefield, fixed, 5),
		"Fixed contract quote still validates"
	)
	fixed.reward += 1
	check(
		not ContractEncounters.valid_offer(lib, lib.content.contracts.minefield, fixed, 5),
		"Fixed quote cannot be changed"
	)


func check_asteroid_lifecycle(source: PackedByteArray, lib) -> void:
	var parameters: Dictionary = lib.content.contracts.asteroids
	var rules: Dictionary = parameters.field.destruction
	var Scenery = Session.Mission.Scenery
	check(
		rules.effect.layers.size() == 6 and rules.fragment_meshes == [10035.0, 10036.0, 10037.0],
		"Import all six asteroid effect layers and three original fragments"
	)
	check(
		(
			rules.effect.layers.map(func(layer): return layer.delay_ms)
			== [150.0, 0.0, 0.0, 0.0, 100.0, 150.0]
		),
		"Preserve source layer delays"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type == 6:
				selected = index
				break
		if selected >= 0:
			break
	check(
		selected >= 0 and pilot.begin_contract(selected),
		"Accept asteroid contract from the real mission board"
	)
	if selected < 0:
		return
	var definition: Dictionary = pilot.mission_definition()
	var rate := int(
		Contracts.reference_offer(lib, pilot.market_seed, pilot.active_job.contract).reward
	)
	var credits := pilot.credits
	var rocks: Dictionary = pilot.active_job.scenery
	for index in 10:
		Scenery.hit(rocks, 0)
	check(
		rocks.rocks[0].hits == 1 and pilot.mission_reward() == 0,
		"Ten nonlethal hits do not earn asteroid payment"
	)
	Scenery.hit(rocks, 0)
	check(
		rocks.rocks[0].hits == 0 and not rocks.rocks[0].destroyed and pilot.mission_reward() == 0,
		"Eleventh hit starts destruction without premature credit"
	)
	pilot.advance_mission(.5)
	check(
		not rocks.rocks[0].destroyed and Scenery.valid(definition, rocks),
		"Pending asteroid explosion remains valid"
	)
	var stored: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(stored) and same_saved_value(restored.active_job, pilot.active_job),
		"Restore pending asteroid destruction and exact quoted rate"
	)
	var snapshot: Dictionary = restored.active_job.scenery.duplicate(true)
	Scenery.advance(definition, restored.active_job.scenery, 0)
	Scenery.advance(definition, restored.active_job.scenery, NAN)
	check(
		restored.active_job.scenery == snapshot, "Paused or invalid time does not advance an effect"
	)
	Scenery.hit(restored.active_job.scenery, 0, true)
	check(
		restored.active_job.scenery == snapshot,
		"Repeated damage cannot restart a pending destruction"
	)
	# Simultaneous rocks have independent native clocks, not source render-loop coupling.
	Scenery.hit(restored.active_job.scenery, 1, true)
	restored.advance_mission(1.25)
	check(
		(
			restored.active_job.scenery.rocks[0].destroyed
			and not restored.active_job.scenery.rocks[1].destroyed
			and restored.mission_reward() == rate
		),
		"Only completed parent effects contribute to payment"
	)
	restored.advance_mission(.6)
	check(
		restored.mission_reward() == rate * 2 and not restored.active_job.ready,
		"Both completed effects count once without finishing survival early"
	)
	var point: Vector3 = Combat.vector(restored.active_job.scenery.rocks[2].position)
	var collision := Scenery.contact(definition, restored.active_job.scenery, point, point, .1)
	check(
		collision == parameters.field.contact_damage and restored.mission_reward() == rate * 2,
		"Collision starts a third destruction with imported damage and no immediate reward"
	)
	restored.advance_mission(2)
	check(
		restored.mission_reward() == rate * 3,
		"Completed collision destruction is billable like source parent count"
	)
	var before_end: float = (
		float(definition.success.duration_ms) / 1000.0
		- float(restored.active_job.elapsed_ms) / 1000.0
	)
	restored.advance_mission(before_end - .1)
	Scenery.hit(restored.active_job.scenery, 3, true)
	restored.advance_mission(.101)
	check(
		(
			restored.active_job.ready
			and not restored.active_job.failed
			and restored.mission_reward() == rate * 3
			and not restored.active_job.scenery.rocks[3].destroyed
		),
		"Timer freezes payment with last-second unfinished rock excluded"
	)
	for tick in 1800:
		restored.advance_radio(.1)
		if restored.ready_to_finish():
			break
	check(
		restored.ready_to_finish() and restored.finish_mission(),
		"Finish asteroid contract after original closing radio"
	)
	check(
		(
			restored.credits == credits + rate * 3
			and restored.contract_rewards.size() == 1
			and restored.contract_rewards[0].units == 3
		),
		"Pay exact quoted rate times destroyed parents and persist receipt units"
	)
	check(
		not restored.finish_mission() and restored.credits == credits + rate * 3,
		"Asteroid contract cannot pay twice"
	)
	var paid: Dictionary = JSON.parse_string(JSON.stringify(restored.capture()))
	var reload := Session.new()
	reload.configure(lib)
	check(reload.restore(paid), "Reload completed per-target receipt")
	for pair in [
		["units", -1], ["units", parameters.field.count + 1], ["units", 2], ["payment", 1]
	]:
		var invalid := paid.duplicate(true)
		invalid.contract_rewards[0][pair[0]] = pair[1]
		check(not reload.restore(invalid), "Reject malformed or inconsistent per-target receipt")
	check(pilot.restore(stored), "Restore asteroid contract before defeat/retry")
	pilot.hull = 0
	check(
		not pilot.finish_mission() and pilot.credits == credits,
		"Defeated pilot receives no asteroid payment"
	)
	pilot.retry_mission()
	check(
		(
			pilot.docked
			and pilot.begin_contract(selected)
			and pilot.mission_reward() == 0
			and pilot.active_job.scenery.rocks.all(
				func(rock): return rock.hits > 0 and not rock.destroyed
			)
		),
		"Retry recreates the same contract without retaining payout or damage"
	)
	var empty := Session.new()
	empty.configure(lib)
	check(
		empty.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Restore untouched asteroid contract"
	)
	empty.advance_mission(float(definition.success.duration_ms) / 1000.0 + .001)
	for tick in 1800:
		empty.advance_radio(.1)
		if empty.ready_to_finish():
			break
	check(
		(
			empty.finish_mission()
			and empty.credits == credits
			and empty.contract_rewards[0].units == 0
		),
		"Surviving without clearing asteroids finishes with zero payment"
	)
	check(
		reload.restore(JSON.parse_string(JSON.stringify(empty.capture()))),
		"Zero-unit receipt survives save/load"
	)
	# Existing field damage survives the schema upgrade without resurrection or replay.
	var legacy := pilot.capture().duplicate(true)
	legacy.schema = 15
	legacy.active_job.scenery.rocks[0].hits = 0
	legacy.active_job.scenery.rocks[1].hits = 4
	for rock in legacy.active_job.scenery.rocks:
		rock.erase("destruction_ms")
		rock.erase("destroyed")
	check(
		(
			reload.restore(JSON.parse_string(JSON.stringify(legacy)))
			and reload.active_job.scenery.rocks[0].destroyed
			and reload.active_job.scenery.rocks[1].hits == 4
		),
		"Schema15 migration preserves existing cleared and damaged rocks"
	)
	for pair in [["destruction_ms", -1], ["destroyed", true], ["destruction_ms", 30000]]:
		var invalid := stored.duplicate(true)
		invalid.active_job.scenery.rocks[1][pair[0]] = pair[1]
		check(not reload.restore(invalid), "Reject impossible asteroid destruction save state")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var field := reader.symbol_address("__ZN13AsteroidFieldC2EiP8Waypoint")
	var handler := reader.symbol_address("__ZN16ExplosionHandlerC2E19ExplosionObjectType")
	var table: int = reader.calls_between(handler, handler + 0x100, "___switch32")[0] + 4
	var branch: int = table + reader.u32(table + 4 + reader.immediate_at(field + 0x66, 1) * 4)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(branch + 0x174, 2), 0x2264)
	reader.bytes = changed
	var altered := reader.asteroid_destruction()
	check(
		reader.error.is_empty() and altered.effect.layers[5].duration_ms == 2500,
		"Changing source layer duration changes the native destruction clock"
	)
	for offset in [0x22, 0x74, 0x9e, 0x15c, 0x184]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(branch + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.asteroid_destruction().is_empty() and not reader.error.is_empty(),
			"Reject altered effect geometry/timing consumers"
		)
	var invalid := rules.duplicate(true)
	invalid.effect.layers[0].mesh = 999999
	check(
		not Scenery.valid_destruction(invalid, lib.content.resources),
		"Reject missing asteroid effect resource"
	)


func check_escort_contracts(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read escort source index")
	var parameters := reader.contract_escort()
	check(
		not parameters.is_empty() and reader.error.is_empty(),
		"Read escort declarations: " + reader.error
	)
	if parameters.is_empty():
		return
	check(
		(
			parameters.types == [7]
			and parameters.duration_ms == 240000
			and parameters.failure_text == 402
		),
		"Escort source declares timed survival and convoy-loss text"
	)
	check(
		(
			(
				parameters.formation
				== [
					[-4500, -300, 20000],
					[4500, 3000, 17000],
					[-6000, -2000, 12000],
					[7000, -6000, 10000],
					[1000, 7000, 8000]
				]
			)
			and parameters.jitter == [[-3000, 2999], [-3000, 2999], [-3000, 2999]]
		),
		"Import formation and shared jitter"
	)
	check(
		(
			parameters.fleets.map(func(fleet): return fleet.cargo_actor) == [5, 19, 17]
			and parameters.fleets.map(func(fleet): return fleet.collisions.size()) == [1, 1, 5]
		),
		"All client factions retain original transport models and compound hulls"
	)
	check(
		parameters.rank_factor == 3 and parameters.region_factor == 65 and parameters.speed == 32,
		"Import convoy hull coefficients and fixed-body speed"
	)
	var scenery_seen := {}
	for region in 4:
		for tier in range(1, 10):
			for race in 3:
				var rank := 1 if tier == 1 else 30
				var seed_value := region * 100 + tier * 3 + race
				var offer := Contracts.terms(lib.content.contracts, region, 7, tier)
				offer.origin_station = region * 125
				offer.client = {"race": race, "portrait": 11, "name": "Client", "profession": 444}
				var definition := ContractEncounters.escort(
					lib, parameters, offer, rank, seed_value
				)
				check(
					not definition.is_empty(),
					"Generate escort for every region, tier and client race"
				)
				if definition.is_empty():
					continue
				var enemies: Array = definition.groups.filter(
					func(group): return group.get("team", "enemy") == "enemy"
				)
				var allies: Array = definition.groups.filter(
					func(group): return group.get("team") == "ally"
				)
				check(
					enemies.size() == region + 2 + int(tier / 5) and allies.size() == 5,
					"Escort scales attackers and preserves five transports"
				)
				check(
					allies.all(
						func(group): return group.actor == [5, 19, 17][race] and group.hull == rank * 3 + region * 65 and group.velocity == [0, 0, -32.0]
					),
					"Faction, hull and velocity use supplied declarations"
				)
				check(
					enemies.all(
						func(group): return group.actor == [1, 0, 1][race] and group.sleeping and group.count == 1
					),
					"Source attackers sleep at independent route points"
				)
				var jitter := []
				for axis in 3:
					jitter.append(allies[0].center[axis] - parameters.formation[0][axis])
				check(
					jitter.all(func(axis): return axis >= -3000 and axis <= 2999),
					"Convoy origin remains inside imported jitter"
				)
				for index in allies.size():
					var actual := []
					for axis in 3:
						actual.append(
							allies[index].center[axis] - parameters.formation[index][axis]
						)
					check(
						(
							actual == jitter
							and allies[index].placement == "player_offset"
							and allies[index].scatter.is_empty()
						),
						"Every convoy member shares one origin without extra formation scatter"
					)
				check(
					(
						definition.route.is_empty()
						and definition.deadline_ms == 0
						and definition.success.kind == "time_survived"
						and definition.failure.kind == "allies_destroyed"
					),
					"Temporary attack route cannot become player objectives"
				)
				scenery_seen["fog" if definition.has("fog") else "field" if not definition.scenery.is_empty() else "empty"] = true
				var center: Array = (
					definition.fog.center
					if definition.has("fog")
					else (
						definition.scenery[0].center
						if not definition.scenery.is_empty()
						else enemies[0].center
					)
				)
				check(
					(
						center[0] == 0
						and center[1] == 0
						and parameters.route_bounds.any(
							func(bounds): return center[2] >= bounds[2][0] and center[2] <= bounds[2][1]
						)
					),
					"Attacks and scenery use supplied route-point bounds"
				)
				check(
					(
						definition
						== ContractEncounters.escort(lib, parameters, offer, rank, seed_value)
					),
					"Escort regenerates deterministically"
				)
				var state := Session.Mission.create(
					definition, 0, int(offer.origin_station), lib, seed_value, rank, "contract"
				)
				var friends: Array = state.actors.filter(
					func(actor): return not Session.Mission.enemy(definition, actor)
				)
				for index in range(1, friends.size()):
					friends[index].hp = 0
				Session.Mission.advance(definition, state, 240, lib)
				check(
					not state.ready and not state.failed,
					"One surviving transport waits for strict timer boundary"
				)
				Session.Mission.advance(definition, state, .001, lib)
				check(
					state.ready and not state.failed,
					"One surviving transport completes escort with attackers still alive"
				)
				state = Session.Mission.create(
					definition, 0, int(offer.origin_station), lib, seed_value, rank, "contract"
				)
				for actor in state.actors:
					if not Session.Mission.enemy(definition, actor):
						actor.hp = 0
				Session.Mission.advance(definition, state, .1, lib)
				check(
					state.failed and not state.ready, "Losing the entire convoy fails immediately"
				)
	check(
		scenery_seen.size() == 3, "Escort generation includes field, fog and empty-space variants"
	)
	for pair in [
		["duration_ms", 0],
		["speed", 0],
		["count_divisor", 0],
		["fleets", []],
		["formation", []],
		["jitter", [[0, 1]]],
		["failure_text", 999999],
		["route_bounds", []],
		["types", [6]],
		["failure_kind", "enemy_destroyed"]
	]:
		var invalid := parameters.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(
			not ContractEncounters.valid_escort_parameters(invalid, lib),
			"Reject malformed escort parameters"
		)
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level, level + 1400, "___switch32")[0] + 4
	var start: int = table + reader.u32(table + 4 + 7 * 4)
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader, start + 0x512), 300000)
	changed.encode_u32(literal_file_offset(reader, start + 0x480), -4200 & 0xffffffff)
	reader.bytes = changed
	var altered := reader.contract_escort()
	check(
		(
			not altered.is_empty()
			and altered.duration_ms == 300000
			and altered.formation[0][0] == -4200
		),
		"Native declarations follow source timer and formation edits"
	)
	for offset in [
		0xa6,
		0x11e,
		0x176,
		0x226,
		0x230,
		0x2be,
		0x2ce,
		0x318,
		0x388,
		0x3b2,
		0x3d4,
		0x3f0,
		0x484,
		0x534,
		0x568,
		0x57e,
		0x5a6
	]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(start + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.contract_escort().is_empty() and not reader.error.is_empty(),
			"Reject altered escort source consumers at %x" % offset
		)
	reader.bytes = source
	reader.error = ""
	var factory := reader.symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	changed = source.duplicate()
	changed.encode_u32(literal_file_offset(reader, factory + 0x804), 1700)
	reader.bytes = changed
	var boxes := reader.escort_cargo_collision(17)
	check(
		not boxes.is_empty() and boxes[0].size[1] == 1700,
		"Compound convoy hull dimensions are source driven"
	)
	for offset in [0x818, 0x860, 0x8a4, 0x8e6, 0x92a, 0x8d6]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(factory + offset, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.escort_cargo_collision(17).is_empty() and not reader.error.is_empty(),
			"Reject changed compound-hull consumers"
		)
	# Explicit cloud centers are needed when the source disposes its temporary route.
	var fog: Dictionary = parameters.fog.duplicate(true)
	check(lib.valid_fog(fog, 0), "Accept explicit nebula center without player route")
	fog.waypoint = 0
	check(not lib.valid_fog(fog, 1), "Reject ambiguous nebula center and waypoint")
	fog.erase("center")
	check(
		lib.valid_fog(fog, 1) and not lib.valid_fog(fog, 0),
		"Existing campaign nebula waypoints still validate against route"
	)
	check_escort_settlement(lib)


func check_escort_settlement(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type == 7:
				selected = index
				break
		if selected >= 0:
			break
	check(
		selected >= 0 and pilot.begin_contract(selected), "Accept escort from actual mission board"
	)
	if selected < 0:
		return
	var definition: Dictionary = pilot.mission_definition()
	var quoted := int(
		Contracts.reference_offer(lib, pilot.market_seed, pilot.active_job.contract).reward
	)
	var credits := pilot.credits
	var snapshot := pilot.capture()
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {"aim_assist": false})
	flight.set_physics_process(false)
	flight.auto_pilot = false
	var initial: Array = pilot.active_job.actors.duplicate(true)
	for tick in 60:
		flight._physics_process(1.0 / 60)
	var moving := true
	for index in initial.size():
		if Session.Mission.enemy(definition, initial[index]):
			continue
		var distance := Combat.vector(initial[index].position).distance_to(
			Combat.vector(pilot.active_job.actors[index].position)
		)
		moving = moving and absf(distance - 32) < .01
	check(
		moving and flight.objective().begins_with("Protect convoy"),
		"Actual flight moves transports at imported speed and displays convoy objective"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(
		(
			restored.restore(JSON.parse_string(JSON.stringify(pilot.capture())))
			and same_saved_value(restored.active_job, pilot.active_job)
		),
		"Save/load preserves moving convoy, source formation and damage"
	)
	flight.free()
	var friends: Array = restored.active_job.actors.filter(
		func(actor): return not Session.Mission.enemy(definition, actor)
	)
	for index in range(1, friends.size()):
		friends[index].hp = 0
	restored.advance_mission(240)
	for tick in 1800:
		restored.advance_radio(.1)
		if restored.ready_to_finish():
			break
	check(
		(
			restored.ready_to_finish()
			and restored.mission_reward() == quoted
			and restored.finish_mission()
		),
		"One survivor receives full quoted escort reward after closing radio"
	)
	check(
		(
			restored.credits == credits + quoted
			and restored.contract_rewards.size() == 1
			and not restored.finish_mission()
		),
		"Fixed escort reward pays exactly once"
	)
	var reload := Session.new()
	reload.configure(lib)
	check(
		reload.restore(JSON.parse_string(JSON.stringify(restored.capture()))),
		"Completed escort receipt reloads"
	)
	check(
		pilot.restore(JSON.parse_string(JSON.stringify(snapshot))),
		"Restore preflight escort snapshot"
	)
	for actor in pilot.active_job.actors:
		if not Session.Mission.enemy(definition, actor):
			actor.hp = 0
	pilot.advance_mission(.1)
	check(
		pilot.active_job.failed and not pilot.finish_mission() and pilot.credits == credits,
		"Convoy defeat cannot claim fixed payout"
	)
	pilot.retry_mission()
	check(
		(
			pilot.docked
			and pilot.begin_contract(selected)
			and pilot.active_job.actors.all(func(actor): return actor.hp > 0)
		),
		"Retry recreates lost convoy without paying or retaining damage"
	)


func check_intercept_contracts(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read interception source index")
	var parameters := reader.contract_intercept()
	check(not parameters.is_empty() and reader.error.is_empty(), "Read interception declarations: " + reader.error)
	if parameters.is_empty(): return
	check(parameters.types == [8] and parameters.target_counts == [2,3] and parameters.wingman_chance == [50,100], "Source cargo count and optional wingman chance")
	check(parameters.route_bounds == [[-2500,2499],[-2500,2499],[35000,64999]] and parameters.scatter == [[-10000,9999],[-10000,9999],[-10000,9999]], "Source navigation and independent stationary cargo placement")
	var counts := {};var helpers := {};var scenery_seen := {}
	for region in 4:
		for tier in [1,9]:
			for race in [0,1,7]:
				for seed_index in 6:
					var seed_value: int = seed_index * 7919 + region * 131 + tier * 17 + race * 5
					var offer := Contracts.terms(lib.content.contracts,region,8,tier)
					offer.origin_station = region * 125
					offer.client = {"race":race,"portrait":11,"name":"Client","profession":444}
					var definition := ContractEncounters.intercept(lib,parameters,offer,5,seed_value)
					check(not definition.is_empty(), "Generate interception across regions, difficulties and client factions")
					if definition.is_empty(): continue
					var target: Dictionary = definition.groups[0]
					var guards: Dictionary = definition.groups[1]
					var allies: Array = definition.groups.filter(func(group): return group.get("team") == "ally")
					counts[int(target.count)] = true;helpers[not allies.is_empty()] = true
					scenery_seen["fog" if definition.has("fog") else "field" if not definition.scenery.is_empty() else "empty"] = true
					check(target.count in [2,3] and guards.count == region + 2 + int(tier/5), "Cargo prefix and guardian counts match source formulas")
					check(target.actor == (5 if race==1 else 19) and guards.actor == (0 if race==1 else 1), "Client faction selects the opposing cargo and guard models")
					check(target.behavior == "stationary" and target.sleeping and not target.has("velocity") and target.collisions.size()==1, "Cargo is stopped with original collision shape and activation radius")
					check(definition.route.size()==1 and definition.deadline_ms==0 and definition.success=={"kind":"enemy_prefix_destroyed","count":target.count}, "Only destruction of cargo prefix completes interception")
					check(definition == ContractEncounters.intercept(lib,parameters,offer,5,seed_value), "Interception regenerates deterministically")
					var state := Session.Mission.create(definition,0,int(offer.origin_station),lib,seed_value,5,"contract")
					for index in range(int(target.count),state.actors.size()): damage_actor_fixture(definition,state,index,lib)
					Session.Mission.advance(definition,state,500, lib)
					check(not state.ready and not state.failed, "Guard and wingman losses neither complete nor fail the cargo objective")
					state = Session.Mission.create(definition,0,int(offer.origin_station),lib,seed_value,5,"contract")
					for index in int(target.count): damage_actor_fixture(definition,state,index,lib)
					check(not state.ready, "Interception waits for cargo destruction after hull loss")
					finish_wrecks_fixture(definition,state,lib)
					check(state.ready and not state.failed and state.stage==0, "Cargo destruction completes with guardians alive and navigation point unvisited")
	check(counts.size()==2 and helpers.size()==2 and scenery_seen.size()==3, "Both cargo counts, wingman branches and all scenery variants generate")
	for pair in [["target_counts",[0,3]],["count_divisor",0],["wingman_chance",[50,0]],["wake_half_width",0],["fleets",[]],["route_bounds",[]],["scatter",[[0,1]]],["types",[6]],["success_kind","enemies_destroyed"]]:
		var invalid := parameters.duplicate(true);invalid[pair[0]] = pair[1]
		check(not ContractEncounters.valid_intercept_parameters(invalid,lib), "Reject malformed interception parameters")
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level,level+1400,"___switch32")[0]+4
	var start: int = table+reader.u32(table+4+8*4)
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader,start+0x52),45000)
	changed.encode_float(literal_file_offset(reader,start+0x266),5)
	reader.bytes = changed
	var altered := reader.contract_intercept()
	check(not altered.is_empty() and altered.route_bounds[2]==[45000,74999] and altered.count_divisor==5, "Changed source location and guardian difficulty affect imported declarations")
	var changed_offer := Contracts.terms(lib.content.contracts,0,8,9)
	changed_offer.origin_station = 0
	changed_offer.client = {"race":1,"portrait":11,"name":"Client","profession":444}
	var altered_mission := ContractEncounters.intercept(lib,altered,changed_offer,5,2)
	check(not altered_mission.is_empty() and altered_mission.groups[1].count==5 and altered_mission.route[0][2]>=45000, "Native interception consumes altered source declarations")
	for offset in [0x7e,0x94,0xb2,0xfe,0x13e,0x26e,0x27c,0x2b0,0x2bc,0x2ce,0x2d6,0x2de,0x358,0x374,0x3b4,0x3c6,0x404,0x408]:
		changed = source.duplicate();changed.encode_u16(reader.file_offset(start+offset,2),0xbf00)
		reader.bytes = changed;reader.error = ""
		check(reader.contract_intercept().is_empty() and not reader.error.is_empty(), "Reject unsupported interception source consumer at %x" % offset)
	check_intercept_settlement(lib)


func check_intercept_settlement(lib) -> void:
	var pilot := Session.new();pilot.configure(lib);pilot.skip_campaign()
	var selected := -1
	for seed_value in 1000:
		pilot.market_seed = seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type==8: selected=index;break
		if selected>=0:break
	check(selected>=0 and pilot.begin_contract(selected), "Accept interception from actual mission board")
	if selected<0:return
	var definition: Dictionary = pilot.mission_definition()
	var count := int(definition.success.count)
	var quoted := int(Contracts.reference_offer(lib,pilot.market_seed,pilot.active_job.contract).reward)
	var credits := pilot.credits
	var flight := Flight.new();root.add_child(flight);flight.setup(lib,pilot,{"aim_assist":false});flight.set_physics_process(false);flight.auto_pilot=false
	flight.ship.position = Combat.vector(pilot.active_job.actors[0].position)+Vector3(0,0,100)
	flight.throttle = 0
	var original: Array = pilot.active_job.actors.duplicate(true)
	for tick in 60:flight._physics_process(1.0/60)
	var stopped := true
	for index in count:stopped = stopped and pilot.active_job.actors[index].position==original[index].position
	check(stopped and pilot.active_job.actors[0].awake, "Native cargo wakes near player and stays at source position")
	pilot.active_job.stage = 0
	check(flight.objective().begins_with("Clear targets") and not pilot.active_job.ready, "HUD tracks cargo prefix without premature completion")
	check(pilot.damage_actor(0,1), "Apply partial cargo damage")
	var stored := JSON.parse_string(JSON.stringify(pilot.capture())) as Dictionary
	var restored := Session.new();restored.configure(lib)
	check(restored.restore(stored) and same_saved_value(restored.active_job,pilot.active_job), "Interception save/load preserves partial cargo damage and stationary placement")
	flight.free()
	for index in range(count,restored.active_job.actors.size()):
		var actor: Dictionary = restored.active_job.actors[index]
		if Session.Mission.enemy(definition,actor):
			actor.awake=true;restored.damage_actor(index,float(actor.hp))
	check(not restored.active_job.ready, "Destroying every guardian does not complete the contract")
	for index in count:
		restored.active_job.actors[index].awake=true
		restored.damage_actor(index,float(restored.active_job.actors[index].hp))
	for tick in 1800:
		restored.advance_mission(.1)
		restored.advance_radio(.1)
		if restored.ready_to_finish():break
	check(restored.ready_to_finish() and restored.mission_reward()==quoted and restored.finish_mission(), "Finish cargo interception after original closing radio")
	check(restored.credits==credits+quoted and restored.contract_rewards.size()==1 and not restored.finish_mission(), "Fixed interception payment occurs exactly once")
	var reload := Session.new();reload.configure(lib)
	check(reload.restore(JSON.parse_string(JSON.stringify(restored.capture()))), "Completed interception receipt reloads")
	check(pilot.restore(stored), "Restore interception before defeat/retry")
	pilot.hull=0
	check(not pilot.finish_mission() and pilot.credits==credits, "Player defeat cannot pay interception reward")
	pilot.retry_mission()
	check(pilot.docked and pilot.begin_contract(selected) and pilot.active_job.actors[0].hp==original[0].hp, "Retry restores cargo health without payout")


func check_capture_contracts(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Read Capture source index")
	var parameters := reader.contract_capture()
	check(not parameters.is_empty() and reader.error.is_empty(), "Read Capture declarations: " + reader.error)
	if parameters.is_empty(): return
	check(parameters.types == [11] and parameters.capital_waypoint == 1 and parameters.wingman_chance == [50,100], "Source Capture family, capital waypoint and wingman chance")
	check(parameters.route_bounds == [[[-2500,2499],[-2500,2499],[70000,99999]],[[-2500,2499],[-2500,2499],[150000,169999]]], "Both original Capture route volumes imported")
	var helpers := {};var scenery_seen := {};var waypoint_seen := {}
	for region in 4:
		for tier in [1,9]:
			for race in [0,1,7]:
				for seed_index in 4:
					var seed_value: int = seed_index * 7919 + region * 131 + tier * 17 + race * 5
					var offer := Contracts.terms(lib.content.contracts,region,11,tier)
					offer.origin_station = region * 125
					offer.client = {"race":race,"portrait":11,"name":"Client","profession":444}
					var definition := ContractEncounters.capture(lib,parameters,offer,5,seed_value)
					check(not definition.is_empty(), "Generate Capture across regions, difficulties and factions")
					if definition.is_empty(): continue
					var count := 4 if race==1 else 6
					var guards := region+2+int(tier/5)
					var parent_index := count + guards
					var parent: Dictionary = definition.groups[parent_index]
					var fleet: Dictionary = parameters.fleets[0 if race==1 else 1]
					check(parent.actor==(6 if race==1 else 20) and parent.source_scale and not parent.combat_active and parent.collisions.size()==3, "Source capital faction, full scale, compound body and invulnerability")
					check(definition.route.size()==2 and definition.deadline_ms==0 and definition.enemy_goal==parent_index and definition.success=={"kind":"enemy_prefix_destroyed","count":count}, "Capture counts only turrets for completion and excludes the inactive capital from kills")
					var state := Session.Mission.create(definition,0,int(offer.origin_station),lib,seed_value,5,"contract")
					var center := Combat.vector(state.actors[parent_index].position)
					check(center.is_equal_approx(Session.Mission.point(parent.center)), "Capital has exactly one sampled placement without legacy formation drift")
					var delta := []
					for axis in 3:delta.append(parent.center[axis]-definition.route[1][axis])
					check(delta.all(func(axis): return axis>=-32000 and axis<=31999), "Capital uses original full factory scatter around second route point")
					for index in count:
						var turret: Dictionary = definition.groups[index]
						check((Combat.vector(state.actors[index].position)-center).distance_to(Session.Mission.point(fleet.turrets.positions[index])) < .001, "Turret hardpoint remains aligned with sampled capital")
						check(turret.actor==(3 if race==1 else 21) and turret.hull==(60 if race==1 else 120)*(1+region)+25 and turret.sleeping and turret.render_mesh==(race!=1), "Freelance turret model availability, regional/rank hull and sleep state")
						check(turret.weapon.damage_rule.base==fleet.turrets.weapon.damage_rule.base+region and turret.facing==fleet.turrets.facing[index], "Source turret facing and regional gun damage consumed")
						if race!=1:check(turret.weapon.projectile_model==10064 and turret.weapon.interval==4 and turret.weapon.lifetime==4 and turret.weapon.speed==120 and turret.weapon.pool_capacity==1, "Alien turret fires original single-slot object projectile")
					for index in range(count,parent_index):
						var guard: Dictionary = definition.groups[index]
						check(guard.actor==(0 if race==1 else 1) and guard.sleeping and guard.behavior=="interceptor", "Capture guards use source faction and sleeping fighter behavior")
						waypoint_seen[definition.route.find(guard.center)] = true
					check(not Session.Mission.damage(definition,state,parent_index,10000000) and state.actors[parent_index].hp>0, "Inactive capital cannot be destroyed instead of its turrets")
					for index in range(count,state.actors.size()):
						if index!=parent_index:damage_actor_fixture(definition,state,index,lib)
					Session.Mission.advance(definition,state,500, lib)
					check(not state.ready and not state.failed, "Guard and wingman losses neither capture the ship nor fail the job; no invented deadline")
					state = Session.Mission.create(definition,0,int(offer.origin_station),lib,seed_value,5,"contract")
					for index in count:damage_actor_fixture(definition,state,index,lib)
					check(not state.ready, "Capture waits for turret destruction after hull loss")
					finish_wrecks_fixture(definition,state,lib)
					check(state.ready and not state.failed and state.stage==0 and state.actors[parent_index].hp>0 and state.actors[count].hp>0, "Destroying turret prefix captures intact ship while guards survive and route remains unvisited")
					helpers[definition.groups.any(func(group): return group.get("team")=="ally")] = true
					scenery_seen["fog" if definition.has("fog") else "field" if not definition.scenery.is_empty() else "empty"] = true
					check(definition==ContractEncounters.capture(lib,parameters,offer,5,seed_value), "Capture reconstruction is deterministic")
	check(helpers.size()==2 and scenery_seen.size()==3 and waypoint_seen.size()==2 and not waypoint_seen.has(-1), "Optional wingman, all scenery choices and both guard waypoints exercised")
	for pair in [["count_divisor",0],["capital_waypoint",2],["wingman_chance",[50,0]],["fleets",[]],["route_bounds",[]],["types",[6]],["success_kind","enemies_destroyed"]]:
		var invalid := parameters.duplicate(true);invalid[pair[0]]=pair[1]
		check(not ContractEncounters.valid_capture_parameters(invalid,lib), "Reject malformed Capture parameters")
	for pair in [["facing",[[0,0,0]]],["positions",[]],["hull_base",0],["rank_factor",-1],["weapon",{}],["render_mesh",0],["actor",1000],["tracking",{}]]:
		var invalid := parameters.duplicate(true);invalid.fleets[0].turrets[pair[0]]=pair[1]
		check(not ContractEncounters.valid_capture_parameters(invalid,lib), "Reject invalid Capture turret data")
	var level := reader.symbol_address("__ZN5Level13createMissionEv")
	var table: int = reader.calls_between(level,level+1400,"___switch32")[0]+4
	var start: int = table+reader.u32(table+4+11*4)
	var changed := source.duplicate()
	changed.encode_u32(literal_file_offset(reader,start+0xaa),180000)
	reader.bytes=changed
	var altered := reader.contract_capture()
	check(not altered.is_empty() and altered.route_bounds[1][2]==[180000,199999], "Changed source destination changes imported Capture location")
	var offer := Contracts.terms(lib.content.contracts,0,11,1)
	offer.origin_station=0;offer.client={"race":1,"portrait":11,"name":"Client","profession":444}
	var moved := ContractEncounters.capture(lib,altered,offer,1,5)
	check(not moved.is_empty() and moved.route[1][2]>=180000 and moved.groups[0].hull==65, "Native Capture consumes changed location and starting-rank turret hull")
	for offset in [0xcc,0x100,0x14c,0x1c6,0x26c,0x2d0,0x2e8,0x322,0x332,0x3a0,0x3b0,0x3f6]:
		changed=source.duplicate();changed.encode_u16(reader.file_offset(start+offset,2),0xbf00)
		reader.bytes=changed;reader.error=""
		check(reader.contract_capture().is_empty() and not reader.error.is_empty(), "Reject changed Capture constructor or objective consumer at %x" % offset)
	var turret_factory := reader.symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(turret_factory+0xb0,2),3 | (3 << 6))
	reader.bytes=changed;reader.error=""
	var adjusted := reader.contract_capture()
	check(not adjusted.is_empty() and adjusted.fleets[0].turrets.rank_factor==9, "Source rank coefficient changes freelance turret health")
	var tougher := ContractEncounters.capture(lib,adjusted,offer,5,5)
	check(not tougher.is_empty() and tougher.groups[0].hull==105, "Native turret hull consumes altered rank coefficient")
	check_capture_settlement(lib)


func check_capture_settlement(lib) -> void:
	for race_match in [true,false]:
		var pilot := Session.new();pilot.configure(lib);pilot.skip_campaign()
		if race_match:
			for station in lib.stations.size():
				if lib.station_definition(station).race==1:
					pilot.arrive(station);break
		var selected := -1
		for seed_value in 1000:
			pilot.market_seed=seed_value
			var offers := pilot.contract_offers()
			for index in offers.size():
				if offers[index].type==11 and (offers[index].client.race==1)==race_match:selected=index;break
			if selected>=0:break
		check(selected>=0 and pilot.begin_contract(selected), "Accept Capture faction from actual board")
		if selected<0:continue
		var definition: Dictionary = pilot.mission_definition()
		var count := int(definition.success.count)
		var quoted := int(Contracts.reference_offer(lib,pilot.market_seed,pilot.active_job.contract).reward)
		var credits := pilot.credits
		pilot.active_job.actors[0].awake=true
		check(pilot.damage_actor(0,1), "Damage active Capture hardpoint")
		var stored: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
		var restored := Session.new();restored.configure(lib)
		check(restored.restore(stored) and same_saved_value(restored.active_job,pilot.active_job), "Capture save/load preserves partial turret damage and all relative placements")
		for index in count:
			restored.active_job.actors[index].awake=true
			restored.damage_actor(index,float(restored.active_job.actors[index].hp))
		for tick in 1800:
			restored.advance_mission(.1)
			restored.advance_radio(.1)
			if restored.ready_to_finish():break
		check(restored.ready_to_finish() and restored.mission_reward()==quoted and restored.finish_mission(), "Capture pays source quote after original closing radio")
		check(restored.credits==credits+quoted and restored.contract_rewards.size()==1 and not restored.finish_mission(), "Capture payment occurs once")
		var reload := Session.new();reload.configure(lib)
		check(reload.restore(JSON.parse_string(JSON.stringify(restored.capture()))), "Completed Capture receipt reloads")
		pilot.hull=0
		check(not pilot.finish_mission() and pilot.credits==credits, "Defeated pilot cannot claim capture reward")
		pilot.retry_mission()
		check(pilot.docked and pilot.begin_contract(selected) and pilot.active_job.actors[0].hp==stored.active_job.actors[0].hp+1, "Retry regenerates intact turrets without payout")


func check_recovery(source: PackedByteArray, lib) -> void:
	var Recovery = Session.Recovery
	var reader := NativeData.new()
	reader.bytes = source
	check(reader.parse_macho(), "Index recovery source")
	var rules := reader.loot_rules()
	check(not rules.is_empty() and Recovery.valid(rules, lib), "Validate imported recovery declarations")
	if rules.is_empty(): return
	check(rules.items == [15,16,17,18,19,20,21] and rules.quantities == [1,3], "Source recovery catalogue and quantities")
	for sample in [[true,0,5,false,"none"],[true,1,5,false,"none"],[true,2,0,false,"guaranteed"],[true,3,0,false,"optional"],[false,0,1,false,"guaranteed"],[false,0,0,false,"optional"],[false,2,10,true,"none"]]:
		check(Recovery.mode(rules,sample[0],sample[1],sample[2],sample[3])==sample[4], "Campaign exclusions, kills and instant-action recovery policy")
	var counts := {};var items_seen := {};var fits := true;var ordering := true
	for seed_value in 80:
		var unlimited := Recovery.generate(rules,100,"guaranteed",seed_value)
		counts[unlimited.items.size()] = true
		for item in unlimited.items: items_seen[int(item.id)] = true
		for capacity in [0,1,2,3,4,8]:
			var result := Recovery.generate(rules,capacity,"guaranteed",seed_value)
			var total := 0
			for item in result.items: total += int(item.amount)
			fits = fits and Recovery.valid_result(result,rules) and total<=capacity and result.full==(capacity==0)
			if capacity >= unlimited.items.size():
				var reference := unlimited.duplicate(true)
				var extra := 0
				for item in reference.items: extra += int(item.amount)
				while extra > capacity:
					for item in reference.items:
						if extra>capacity and item.amount>rules.minimum_quantity: item.amount-=1;extra-=1
				ordering = ordering and result == reference
	check(fits and ordering, "Capacity boundaries preserve unique items and ordered round-robin quantity reduction")
	check(counts.size()==3 and items_seen.size()==7, "Generated recovery covers all entry counts and source cargo types")
	check(Recovery.generate(rules,0,"none",3)=={"items":[],"full":false}, "Excluded mission does not claim hold full")
	for invalid in [{"items":[{"id":15,"amount":0}],"full":false},{"items":[{"id":15,"amount":1},{"id":15,"amount":1}],"full":false},{"items":[{"id":1,"amount":1}],"full":false},{"items":[],"full":1}]:
		check(not Recovery.valid_result(invalid,rules), "Reject malformed recovery receipt")
	var cargo := reader.symbol_address("__ZN9Generator18getRandomCargoItemEv")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(cargo+0x16,2),0x2102)
	reader.bytes=changed
	var altered := reader.loot_rules()
	check(not altered.is_empty() and altered.quantities==[1,2], "Source quantity mutation reaches imported recovery rules")
	if not altered.is_empty():
		var consumed := true
		for seed_value in 20:
			for item in Recovery.generate(altered,100,"guaranteed",seed_value).items: consumed = consumed and item.amount<=2
		check(consumed, "Native loot consumes changed source quantity bound")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(cargo+0x38,2),0xbf00)
	reader.bytes=changed;reader.error=""
	check(reader.loot_rules().is_empty() and not reader.error.is_empty(), "Unsupported source quantity operation is rejected")
	check_recovery_settlement(lib)


func recovery_contract_fixture(lib):
	var pilot := Session.new();pilot.configure(lib);pilot.skip_campaign()
	for seed_value in 1000:
		pilot.market_seed=seed_value
		var offers := pilot.contract_offers()
		for index in offers.size():
			if offers[index].type==8 and pilot.begin_contract(index): return pilot
	return null


func complete_recovery_fixture(pilot) -> void:
	var count := int(pilot.mission_definition().success.count)
	for index in count:
		pilot.active_job.actors[index].awake=true
		pilot.damage_actor(index,float(pilot.active_job.actors[index].hp))
	for tick in 1800:
		pilot.advance_mission(.1)
		pilot.advance_radio(.1)
		if pilot.ready_to_finish(): break


func check_recovery_settlement(lib) -> void:
	var pilot = recovery_contract_fixture(lib)
	check(pilot != null, "Accept actual board contract for recovery settlement")
	if pilot == null:return
	check(pilot.recovery.is_empty(), "Skipping campaign never awards loot")
	# Keep equipment in the hold: recovery must share its capacity with cargo.
	pilot.loadout.hold.append({"id":0,"value":0})
	pilot.cargo={"15":pilot.cargo_capacity()-3}
	var before: Dictionary = pilot.cargo.duplicate(true)
	complete_recovery_fixture(pilot)
	check(pilot.ready_to_finish() and pilot.finish_mission(), "Recovery settlement waits for final source radio")
	var added := 0
	for item in pilot.recovery.items:
		added += int(item.amount)
		check(pilot.cargo[str(int(item.id))]==int(before.get(str(int(item.id)),0))+int(item.amount), "Recovery is added atomically to existing cargo")
	check(added>0 and added<=2 and pilot.cargo_used()<=pilot.cargo_capacity(), "Loot respects cargo plus unmounted equipment capacity")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var copy := Session.new();copy.configure(lib)
	check(copy.restore(saved), "Restore pending recovery: " + copy.error)
	check(same_saved_value(copy.cargo,pilot.cargo) and same_saved_value(copy.recovery,pilot.recovery), "Reload retains display receipt without granting cargo twice")
	check(not copy.finish_mission(), "Repeated settlement cannot grant loot twice")
	copy.acknowledge_recovery();copy.acknowledge_recovery()
	check(copy.recovery.is_empty() and same_saved_value(copy.cargo,pilot.cargo), "Acknowledgement only clears receipt")
	var legacy := saved.duplicate(true);legacy.schema=16;legacy.erase("recovery")
	check(copy.restore(legacy) and copy.recovery.is_empty() and same_saved_value(copy.cargo,pilot.cargo), "Previous save migrates without retroactive loot")
	var invalid := saved.duplicate(true);invalid.recovery.items[0].amount=1000000
	check(not copy.restore(invalid), "Reject invalid persisted recovery quantity")
	for full in [true,false]:
		var next = recovery_contract_fixture(lib)
		if full:next.cargo={"15":next.cargo_capacity()}
		complete_recovery_fixture(next)
		if full:
			check(next.finish_mission() and next.recovery.full and next.recovery.items.is_empty(), "Full hold settlement preserves cargo and shows source full message")
		else:
			next.hull=0
			check(not next.finish_mission() and next.cargo.is_empty() and next.recovery.is_empty(), "Defeat cannot grant recovered cargo")


func check_survival_rules(source: PackedByteArray) -> void:
	var entry_reader := NativeData.new()
	entry_reader.bytes = source
	entry_reader.parse_macho()
	check(entry_reader.public_survival_type() == 14 and entry_reader.error.is_empty(),
		"Both public arcade launch paths select generated continuous Survival")
	for address in [0x43292,0x4354a,0x2311a]:
		entry_reader.bytes = source.duplicate()
		entry_reader.error = ""
		entry_reader.bytes.encode_u16(entry_reader.file_offset(address,2),0x6818)
		check(entry_reader.public_survival_type() == -1 and not entry_reader.error.is_empty(),
			"Reject changed public generated-mission selection")
	var Survival = preload("res://src/simulation/survival.gd")
	var reader := NativeData.new();reader.bytes=source
	check(reader.parse_macho(), "Read survival data index")
	var rules := reader.survival_rules()
	check(not rules.is_empty() and Survival.valid(rules), "Validate source survival declarations: " + reader.error)
	if rules.is_empty():return
	check(rules.type==14 and rules.pool_size==15 and rules.initial_active==2 and rules.max_active==14, "Source survival mode, reserved pool and active bounds")
	check(rules.upgrades.score==[200,1000,5000,10000] and rules.ships.actor.size()==10, "Source upgrade thresholds and fighter catalogue")
	var state := Survival.create(rules,47)
	check(Survival.valid_state(state,rules), "Initial survival director state is valid")
	check(Survival.award(state,rules,8)=={"points":8,"heal":25}, "First kill awards base score and hull healing")
	check(Survival.award(state,rules,8)=={"points":16,"heal":25}, "Second rapid kill uses next combo value")
	check(Survival.award(state,rules,25)=={"points":61,"heal":25} and state.score==85, "Odd kill score halves before multiplication")
	for pair in [[59,25],[60,50],[99,50],[100,100]]:
		var fresh := Survival.create(rules,0)
		check(Survival.award(fresh,rules,pair[0]).heal==pair[1], "Heal thresholds use unmultiplied kill value")
	var unchanged := state.duplicate(true)
	check(Survival.award(state,rules,0)=={"points":0,"heal":0} and state==unchanged, "Non-scoring destruction does not heal or reset combo")
	state.combo_elapsed_ms=7499
	check(Survival.award(state,rules,8).points==24, "Combo includes original 7499ms boundary")
	state.combo_elapsed_ms=7500
	check(Survival.award(state,rules,8).points==8 and state.combo==1, "Combo expires beyond original boundary")
	state=Survival.create(rules,47);state.score=200
	check(Survival.advance(state,rules,2,Vector3.ZERO,[]).upgrade.is_empty(), "Upgrade timer is strictly past 2000ms")
	check(Survival.advance(state,rules,.001,Vector3.ZERO,[]).upgrade.weapon==rules.upgrades.weapon[0], "Exact score threshold upgrades at next eligible stage")
	check(state.phase=="spawn" and state.upgrade_index==1 and state.timer_ms==0, "Upgrade and spawn stages alternate")
	state=Survival.create(rules,47);state.score=199
	check(Survival.advance(state,rules,2.001,Vector3.ZERO,[]).upgrade.is_empty(), "Score below upgrade threshold retains current weapon")
	state=Survival.create(rules,47);state.score=10000
	check(Survival.advance(state,rules,30,Vector3.ZERO,[]).upgrade.weapon==rules.upgrades.weapon[0] and state.upgrade_index==1, "Large delta performs one stage, not all upgrades at once")
	var slots := []
	for index in int(rules.pool_size):slots.append({"alive":false,"archetype":0})
	state=Survival.create(rules,47);state.phase="spawn";state.score=100
	var at := Vector3(200,300,400)
	var event := Survival.advance(state,rules,2.001,at,slots)
	check(state.active_count==2 and event.respawns.size()==2, "Reinforcement count does not increase at equal threshold")
	state.phase="spawn";state.score=101;slots[0].alive=true
	event=Survival.advance(state,rules,2.001,at,slots)
	check(state.active_count==3 and event.respawns.size()==2 and event.respawns[0].index==1, "Score past threshold enables one additional slot and preserves living ships")
	var placement := true
	for request in event.respawns:
		var distance := (Combat.vector(request.source_position)-at).abs()
		placement=placement and distance.x>=10000 and distance.x<30000 and distance.y>=10000 and distance.y<30000 and distance.z>=10000 and distance.z<30000
	check(placement, "Respawns use imported signed per-axis source-coordinate offsets around player")
	var stored: Dictionary=JSON.parse_string(JSON.stringify(state))
	check(Survival.valid_state(stored,rules), "Survival director state survives JSON")
	check(Survival.advance(stored,rules,2.001,at,slots)==Survival.advance(state,rules,2.001,at,slots), "Reload preserves the next stage")
	check(Survival.advance(stored,rules,2.001,at,slots)==Survival.advance(state,rules,2.001,at,slots), "Reload preserves deterministic respawn randomness")
	state.phase="spawn";state.active_count=int(rules.max_active);state.score=1000000
	event=Survival.advance(state,rules,2.001,at,slots)
	check(state.active_count==14 and event.respawns.size()==13 and not event.respawns.any(func(item): return item.index==14), "Original last pool slot stays reserved at maximum population")
	slots[1].archetype=8;slots[2].archetype=9;state.phase="spawn"
	event=Survival.advance(state,rules,2.001,at,slots)
	check(event.respawns[0].archetype==8 and event.respawns[1].archetype==9 and not event.respawns[0].replace, "Source fixed and unsearched archetypes retain their profile")
	for pair in [["tick_ms",0],["pool_size",0],["max_active",100],["heal_amounts",[]],["thresholds",[]],["promotion_cap",0]]:
		var bad := rules.duplicate(true);bad[pair[0]]=pair[1]
		check(not Survival.valid(bad), "Reject malformed survival policy")
	for pair in [["phase","unknown"],["active_count",100],["upgrade_index",100],["timer_ms",-1],["score",-1]]:
		var bad := state.duplicate(true);bad[pair[0]]=pair[1]
		check(not Survival.valid_state(bad,rules), "Reject malformed survival state")
	var changed := source.duplicate()
	changed.encode_s32(reader.file_offset(reader.symbol_address("__ZL26SURVIVAL_UPGRADES_AT_SCORE"),4),150)
	reader.bytes=changed
	var altered := reader.survival_rules()
	check(not altered.is_empty() and altered.upgrades.score[0]==150, "Source upgrade score mutation changes recovered table")
	if not altered.is_empty():
		state=Survival.create(altered,47);state.score=150
		check(not Survival.advance(state,altered,2.001,at,slots).upgrade.is_empty(), "Native director consumes changed source threshold")
	var death := reader.symbol_address("__ZN5Level9enemyDiedEi")
	changed=source.duplicate();changed.encode_s32(literal_file_offset(reader,death+0x50),2000)
	reader.bytes=changed;altered=reader.survival_rules()
	check(not altered.is_empty() and altered.combo_ms==2000, "Combo expiry comes from supplied content")
	for symbol_and_offset in [["__ZN5Level6updateEij",0xce],["__ZN5Level15spawnNewEnemiesEv",0x28],["__ZN5Level9enemyDiedEi",0x60],["__ZN5Level21checkForWeaponUpgradeEv",0x28]]:
		changed=source.duplicate();changed.encode_u16(reader.file_offset(reader.symbol_address(symbol_and_offset[0])+int(symbol_and_offset[1]),2),0xbf00)
		reader.bytes=changed;reader.error=""
		check(reader.survival_rules().is_empty() and not reader.error.is_empty(), "Reject unsupported survival arithmetic or comparison")


func check_survival_setup(source: PackedByteArray, lib) -> void:
	var Survival = preload("res://src/simulation/survival.gd")
	var Gear = preload("res://src/simulation/survival_loadout.gd")
	var reader := NativeData.new();reader.bytes=source
	check(reader.parse_macho(), "Read survival setup index")
	var setup := reader.survival_setup()
	check(not setup.is_empty() and Survival.valid_setup(setup,lib), "Validate source starting player: " + reader.error)
	if setup.is_empty():return
	check(setup.equipment==[0,3,7] and setup.slots==[1,1,1,1,1], "Original arcade equipment and weapon slots")
	check(setup.hull==1367 and setup.shield_capacity==0 and setup.shield_interval_ms==500, "Original arcade hull and shield overrides")
	check(setup.scene_mode==8 and setup.background=="random" and setup.initial_offset==[0,0,40000] and setup.scatter==[[-32000,31999],[-32000,31999],[-32000,31999]], "Source survival background and opening enemy placement")
	var all_ships := true
	for cycle in int(setup.ship_count):
		var pilot: Dictionary=Survival.initial_player(setup,cycle)
		all_ships=all_ships and pilot.ship_index==cycle and pilot.next_cycle==cycle+1 and pilot.actor==lib.content.tables.buyable_ships[cycle] and pilot.hull==1367
	check(all_ships and Survival.initial_player(setup,10).ship_index==0, "Arcade cycles all source ships before returning to first")
	var original_ships: Array=lib.ships.duplicate(true)
	var original_items: Array=lib.items.duplicate(true)
	var campaign := Session.new();campaign.configure(lib)
	var gear=Gear.new();gear.configure_start(lib,setup)
	check(gear.weapons()==[0,3] and gear.primary_weapons()==[0], "Native survival starts with the original primary and missile")
	check(gear.supports(0,3) and not campaign.loadout.supports(0,3), "Survival mount override is isolated from campaign ship")
	check(gear.shield_capacity()==0 and gear.shield_interval()==.5 and int(lib.items[7][7])==105, "Survival shield override leaves catalogue shield unchanged")
	var stored: Dictionary=JSON.parse_string(JSON.stringify(gear.capture()))
	var restored=Gear.new();restored.configure_start(lib,setup)
	check(restored.restore(stored,0,0) and restored.weapons()==[0,3] and restored.shield_capacity()==0, "Source-configured survival gear survives inventory serialization")
	check(lib.ships==original_ships and lib.items==original_items and campaign.max_hull()==150 and campaign.loadout.weapons()==[0], "Arcade setup does not mutate campaign inventory, hull or shared catalogues")
	var player := reader.symbol_address("__ZN5Level12createPlayerEv")
	var changed := source.duplicate();changed.encode_s32(literal_file_offset(reader,player+0x288),2000)
	reader.bytes=changed
	var altered := reader.survival_setup()
	check(not altered.is_empty() and altered.hull==2000 and Survival.initial_player(altered,0).hull==2000, "Changed source hull reaches the native starting pilot")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(player+0x1b6,2),0x2132)
	reader.bytes=changed;altered=reader.survival_setup()
	check(not altered.is_empty() and altered.shield_capacity==50, "Read changed source shield override")
	if not altered.is_empty():
		gear.configure_start(lib,altered)
		check(gear.shield_capacity()==50 and lib.items==original_items, "Native inventory consumes shield override without changing catalogue")
	for pair in [["equipment",[0,0,7]],["slots",[1]],["hull",0],["ship_order",[]],["initial_offset",[]],["scatter",[[1,0],[0,1],[0,1]]]]:
		var invalid := setup.duplicate(true);invalid[pair[0]]=pair[1]
		check(not Survival.valid_setup(invalid,lib), "Reject malformed starting survival setup")
	for offset in [0x78,0xae,0x168,0x186,0x1a2,0x188]:
		changed=source.duplicate();changed.encode_u16(reader.file_offset(player+offset,2),0xbf00)
		reader.bytes=changed;reader.error=""
		check(reader.survival_setup().is_empty() and not reader.error.is_empty(), "Reject changed setup loop or equipment association")


func check_survival_armament(source: PackedByteArray, lib) -> void:
	var Survival = preload("res://src/simulation/survival.gd")
	var reader := NativeData.new();reader.bytes = source
	check(reader.parse_macho(), "Read survival armament index")
	var rules := reader.survival_rules()
	var armament := reader.survival_armament()
	check(not armament.is_empty() and Survival.valid_armament(armament, rules), "Validate survival gun data: " + reader.error)
	if armament.is_empty(): return
	check(armament.mounts == [[200,0,100],[-400,0,100]], "Original survival mounts retain asymmetric offsets")
	check(armament.pool_capacity == 10 and armament.lifetime == 3.0, "Source gun constructor supplies per-mount pool and lifetime")
	var initial := Survival.enemy_guns(rules, armament)
	check(initial.size() == 2 and initial[0].damage == 1 and initial[0].interval == .5 and initial[0].speed == 320, "Initial survival guns use initial damage and unit conversion")
	check(not initial[0].has("pool_id") and not initial[0].has("guidance"), "Each initial gun has an independent pool and ballistic behavior")
	for index in rules.ships.actor.size():
		var promoted := Survival.replace_enemy_guns(initial, rules, armament, index)
		check(promoted[0].damage == rules.ships.damage[index] and promoted[0].projectile_model == armament.replacement_models[index], "Promotions consume replacement damage and mesh tables")
		check(promoted.size() == 2 and promoted[1].mount_offset == initial[1].mount_offset and promoted[0].lifetime == initial[0].lifetime and promoted[0].pool_capacity == 10 and not promoted[0].has("guidance"), "Promotion preserves original guns instead of allocating a different projectile class")
	var row := {}
	for key in rules.upgrades: row[key] = rules.upgrades[key][0]
	var player: Dictionary = lib.weapon_ballistics(0);player.sort = 0
	var upgraded := Survival.promote_weapon(player, row, armament, true)
	check(upgraded.damage == 3 and upgraded.speed == 580 and upgraded.interval == .49 and upgraded.lifetime == player.lifetime, "Player primary upgrade preserves original lifetime")
	var missile: Dictionary = lib.weapon_ballistics(3);missile.sort = 3
	check(Survival.promote_weapon(missile, row, armament, true) == missile, "Player promotion leaves missile equipment untouched")
	check(player.damage == lib.weapon_ballistics(0).damage and initial[0].damage == 1, "Promotion does not mutate base profiles or catalogue")
	var profiles := {0: upgraded, -1: initial[0], -2: initial[1]}
	var state := Combat.create()
	check(Combat.fire(state, 0, Vector3.ZERO, Vector3.FORWARD, lib, profiles), "Mode-specific fitted player profile fires")
	check(Combat.valid(state, lib, profiles) and state.projectiles[0].velocity[2] == -580 and state.cooldowns[0] == .49, "Shot speed, cooldown and save validation share player override")
	check(Combat.profile(0, lib, profiles).projectile_model == row.projectile_model and Combat.team(0, lib, profiles) == "ally", "Rendering profile and team resolve the same upgraded weapon")
	var hits := Combat.advance(state, .1, [{"id":0,"position":[0,0,-30],"radius":2}], lib, profiles)
	check(hits.size() == 1 and hits[0].damage == 3, "Collision damage uses the upgraded player profile")
	check(Combat.profile(0, lib, {}) == lib.weapon_ballistics(0) and Combat.profile(-99, lib, {}).is_empty(), "Campaign fallback and unknown actor rejection remain intact")
	state = Combat.create()
	var fired := 0
	for index in 11:
		state.cooldowns.clear()
		if Combat.fire(state, -1, Vector3.ZERO, Vector3.FORWARD, lib, profiles): fired += 1
	check(fired == 10 and Combat.fire(state, -2, Vector3.ZERO, Vector3.FORWARD, lib, profiles), "One saturated survival mount does not consume its neighbor's pool")
	var assign := reader.symbol_address("__ZN5Level10assignGunsEv")
	var changed := source.duplicate();changed.encode_s32(literal_file_offset(reader, assign + 0x2de), 4200)
	reader.bytes = changed
	var altered := reader.survival_armament()
	check(not altered.is_empty() and Survival.enemy_guns(rules, altered)[0].lifetime == 4.2, "Native gun lifetime follows supplied source constant")
	changed = source.duplicate();changed.encode_u16(reader.file_offset(assign + 0x2c6, 2), 0x2207)
	reader.bytes = changed;altered = reader.survival_armament()
	check(not altered.is_empty() and Survival.enemy_guns(rules, altered)[0].pool_capacity == 7, "Native projectile capacity follows changed source constructor")
	changed = source.duplicate();changed.encode_u16(reader.file_offset(assign + 0x29e, 2), 0x230f)
	reader.bytes = changed;altered = reader.survival_armament()
	check(not altered.is_empty() and altered.mounts[0][1] == 15, "Mount geometry follows source coordinates")
	for pair in [["pool_capacity",0],["mounts",[]],["lifetime",0],["replacement_models",[]],["player_preserves_excluded",1]]:
		var invalid := armament.duplicate(true);invalid[pair[0]] = pair[1]
		check(not Survival.valid_armament(invalid, rules), "Reject malformed survival armament")
	for offset in [0x18c,0x21e,0x2e0]:
		changed = source.duplicate();changed.encode_u16(reader.file_offset(assign + offset, 2), 0xbf00)
		reader.bytes = changed;reader.error = ""
		check(reader.survival_armament().is_empty() and not reader.error.is_empty(), "Reject changed survival factory branch or mount operation")


func check_survival_runtime(source: PackedByteArray, lib) -> void:
	var Mission = preload("res://src/simulation/mission.gd")
	var Encounters = preload("res://src/simulation/encounters.gd")
	var Arcade = preload("res://src/simulation/survival_session.gd")
	var Flight = preload("res://src/presentation/flight.gd")
	var reader := NativeData.new(); reader.bytes = source
	check(reader.parse_macho(), "Read survival runtime declarations")
	var decl := {"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{})}
	check(reader.error.is_empty() and Arcade.valid_declarations(decl,lib), "Validate source survival session: " + reader.error)
	if not reader.error.is_empty(): return
	var campaign := Session.new(); campaign.configure(lib)
	var campaign_before := campaign.capture()
	var runtime := Arcade.new()
	check(runtime.configure_survival(lib,decl,0,0,47), "Start dedicated survival session")
	check(runtime.slot == "survival" and runtime.active_job.kind == "survival" and runtime.hull == 1367 and not runtime.docked, "Survival uses its own session and hull")
	check(runtime.active_job.actors.size() == 15 and runtime.active_job.actors.filter(func(a): return a.hp>0).size()==2, "Only source initial enemy pair is alive")
	check(runtime.active_job.kills == 0 and not runtime.active_job.ready and not runtime.ready_to_finish(), "Reserved slots are not kills or a completed mission")
	check(runtime.actor_weapons().size() == 33 and runtime.arena.groups[0].weapon_ids == [-1,-16], "Each enemy has two distinct mounted weapon IDs")
	check(runtime.arena.groups[2].hull==1 and runtime.active_job.actors[2].score==0 and runtime.arena.groups[2].motion.speed < .000001, "Reserved slot keeps imported hull, score and near-zero motion")
	var positioned := true
	for index in 2:
		var delta: Vector3 = Combat.vector(runtime.active_job.actors[index].position) - Mission.SPAWN_POSITION - Mission.point(decl.setup.initial_offset)
		positioned = positioned and delta.abs().x <= 640 and delta.abs().y <= 640 and delta.abs().z <= 640
	check(positioned, "Starting enemy placement is relative to the actual player spawn")
	runtime.hull = 100
	check(runtime.damage_actor(0,1000) and runtime.active_job.kills==1 and runtime.active_job.survival.score==8 and runtime.hull==125, "Death awards source score and heals hull once")
	check(not runtime.damage_actor(0,1000) and runtime.active_job.survival.score==8 and runtime.hull==125, "Repeated damage cannot award a dead actor twice")
	runtime.damage_actor(1,1000)
	check(not runtime.active_job.ready and runtime.active_job.kills==2, "Clearing the current pair does not end continuous survival")
	runtime.flight_position = Vector3(2000,3000,4000)
	var wreck_seconds := 0.0
	for index in 2:
		var effect: Dictionary = Mission.Destruction.effect(lib,int(runtime.arena.groups[index].actor))
		wreck_seconds = maxf(wreck_seconds,Mission.Destruction.span(effect)/1000.0)
	var budget := wreck_seconds + 4*float(decl.rules.tick_ms)/1000.0 + .1
	for tick in int(ceil(budget/.05)):
		runtime.advance_mission(.05)
		if runtime.active_job.actors[0].hp>0 and runtime.active_job.actors[1].hp>0:break
	check(runtime.active_job.actors[0].hp==8 and runtime.active_job.actors[1].hp==8 and runtime.active_job.kills==2, "Director revives the pair without counting another kill")
	check(Combat.vector(runtime.active_job.actors[0].position).distance_to(runtime.flight_position)<700, "Respawns convert current player coordinates once")
	var fixed_decl := decl.duplicate(true);fixed_decl.rules.promotion_cap=1
	runtime.configure_survival(lib,fixed_decl,0,0,47)
	runtime.active_job.survival.score=101;runtime.active_job.survival.phase="spawn"
	runtime.advance_mission(2.001)
	check(runtime.active_job.survival.active_count==3 and runtime.active_job.actors[2].hp==1 and runtime.active_job.actors[2].score==0, "Unchanged-archetype reserved activation preserves its initial profile")
	runtime.hull=100;runtime.damage_actor(2,1)
	check(runtime.active_job.kills==1 and runtime.active_job.survival.score==101 and runtime.hull==100, "Zero-score reserved actor counts a kill but grants no score or healing")
	runtime.configure_survival(lib,decl,0,0,47)
	runtime.active_job.survival.score=101
	var promoted := false
	for seed_value in 64:
		runtime.active_job.survival.phase="spawn";runtime.active_job.survival.seed=seed_value
		runtime.active_job.actors[2].hp=0
		runtime.advance_mission(2.001)
		if runtime.active_job.actors[2].archetype == 1:
			promoted=true;break
	check(promoted and runtime.arena.groups[2].actor==decl.rules.ships.actor[1] and runtime.active_job.actors[2].hp==15 and runtime.active_job.actors[2].score==25, "A changed archetype replaces mesh, hull and score")
	check(runtime.actor_weapons()[-3].damage==4 and runtime.actor_weapons()[-18].damage==4 and runtime.actor_weapons()[-3].lifetime==3, "Both promoted enemy mounts use replacement damage while keeping lifetime")
	runtime.configure_survival(lib,decl,0,0,47)
	var original: Dictionary = runtime.actor_weapons()[0].duplicate(true)
	check(Combat.fire(runtime.combat,0,Vector3.ZERO,Vector3.FORWARD,lib,runtime.actor_weapons()), "Launch player shot before survival upgrade")
	var velocity: Array = runtime.combat.projectiles[0].velocity.duplicate()
	runtime.active_job.survival.score=200;runtime.advance_mission(2.001)
	check(runtime.actor_weapons()[0].damage==3 and runtime.combat.projectiles[0].velocity==velocity, "Upgrade changes gun properties without rewriting live-shot velocity")
	check(Combat.valid(runtime.combat,lib,runtime.actor_weapons()), "Prior launch speed and unexpired old cooldown remain valid after promotion")
	var bad_shot := runtime.combat.duplicate(true);bad_shot.projectiles[0].velocity=[0,0,-12345]
	check(not Combat.valid(bad_shot,lib,runtime.actor_weapons()), "Upgrade history does not admit an arbitrary projectile speed")
	var targets := [{"id":0,"position":[0,0,-10],"radius":2}]
	var hits := Combat.advance(runtime.combat,.1,targets,lib,runtime.actor_weapons())
	check(hits.size()==1 and hits[0].damage==3, "Existing shot uses promoted damage at impact")
	runtime.configure_survival(lib,decl,0,0,47)
	for index in range(1,runtime.active_job.actors.size()):runtime.active_job.actors[index].hp=0
	var actor: Dictionary=runtime.active_job.actors[0]
	actor.position=[0,0,0];actor.heading=[0,0,-1]
	var target := Vector3(0,0,-minf(decl.motion.fire_half_width*.5,decl.motion.avoid_distance*3))
	Encounters.advance(runtime.arena,runtime.active_job,.001,target,Vector3.ZERO,runtime.combat,lib,runtime.actor_weapons())
	check(runtime.combat.projectiles.size()==2 and actor.shots==2, "Encounter steering fires both survival mounts")
	if runtime.combat.projectiles.size()==2:
		check(runtime.combat.projectiles[0].position[0]==4 and runtime.combat.projectiles[1].position[0]==-8, "Mounted projectiles use converted source offsets")
	runtime.combat=Combat.create();runtime.combat.cooldowns[-1]=.5
	Encounters.advance(runtime.arena,runtime.active_job,.001,target,Vector3.ZERO,runtime.combat,lib,runtime.actor_weapons())
	check(runtime.combat.projectiles.size()==1 and runtime.combat.projectiles[0].weapon==-16, "Cooling down one mount does not block its neighbor")
	var flight := Flight.new();root.add_child(flight);flight.set_process(false)
	flight.setup(lib,runtime,{"aim_assist":false})
	check(flight.actors.size()==1 and flight.station==null and flight.ambience.get_child_count()==0, "Actual survival Flight creates source actors without exploration obstacles")
	var node_id: int=flight.actors[0].node.get_instance_id()
	runtime.arena.groups[0].actor=int(decl.rules.ships.actor[1]);flight.spawn_targets()
	check(flight.actors[0].node.get_instance_id()!=node_id and flight.actors[0].actor_type==decl.rules.ships.actor[1], "Flight replaces an actor visual when its model changes")
	runtime.combat=Combat.create();flight.weapon_timers=runtime.combat.cooldowns
	flight.fire_weapon(0)
	var shot_id := int(runtime.combat.projectiles.back().id)
	var bolt_id: int=flight.bolts[shot_id].get_instance_id()
	var before_velocity: Array=runtime.combat.projectiles.back().velocity.duplicate()
	runtime.active_job.survival.score=200;runtime.advance_mission(2.001);flight.sync_projectiles()
	check(flight.bolts[shot_id].get_instance_id()!=bolt_id and flight.bolts[shot_id].get_meta("projectile_key")[0]==decl.rules.upgrades.projectile_model[0], "Flight refreshes live projectile appearance after promotion")
	check(runtime.combat.projectiles.back().velocity==before_velocity, "Visual refresh preserves live projectile simulation")
	flight.free()
	runtime.retry_mission()
	check(runtime.ship_id==1 and runtime.hull==1367 and runtime.active_job.survival.score==0, "Retry rotates to next source ship and starts a fresh run")
	check(campaign.capture()==campaign_before and runtime.credits==0 and runtime.recovery.is_empty(), "Survival leaves campaign save, rewards and recovery untouched")
	check(runtime.capture().slot == "survival" and not campaign.restore(runtime.capture()) and not runtime.restore(campaign_before), "Arcade and campaign saves cannot use each other's serializer")


func check_survival_session_validation(source: PackedByteArray, lib) -> void:
	var Arcade = preload("res://src/simulation/survival_session.gd")
	var reader := NativeData.new();reader.bytes=source;reader.parse_macho()
	var decl := {"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{})}
	check(reader.error.is_empty() and Arcade.valid_declarations(decl,lib), "Validated survival data remains accepted")
	var runtime := Arcade.new();runtime.configure_survival(lib,decl,0,0,47)
	var job := runtime.active_job.duplicate(true)
	for path_and_value in [["setup","equipment",[3,7]],["setup","type",13],["setup","reserved_actor",18],["motion","aim_sine",2],["motion","speed",0]]:
		var bad := decl.duplicate(true);bad[path_and_value[0]][path_and_value[1]]=path_and_value[2]
		check(not runtime.configure_survival(lib,bad,0,0,47) and runtime.active_job==job, "Invalid arcade declarations cannot partially replace a running session")
	check(not runtime.configure_survival(lib,decl,-1,0,47) and runtime.active_job==job, "Invalid arcade location leaves current run intact")


func survival_save_clock(runtime, seconds: float) -> void:
	runtime.advance_mission(seconds)
	runtime.elapsed += seconds
	Combat.advance(runtime.combat,seconds,[],runtime.library,runtime.actor_weapons())


func check_survival_saves(source: PackedByteArray, lib) -> void:
	var Arcade = preload("res://src/simulation/survival_session.gd")
	var reader := NativeData.new();reader.bytes=source;reader.parse_macho()
	var decl := {"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{})}
	check(reader.error.is_empty(), "Read survival save declarations")
	var runtime := Arcade.new();runtime.configure_survival(lib,decl,0,0,47)
	var initial: Dictionary = JSON.parse_string(JSON.stringify(runtime.capture()))
	check(runtime.restore(initial), "Initial source survival session survives JSON: " + runtime.error)
	check(runtime.active_job.kills==0 and runtime.active_job.actors[14].hp==0 and runtime.active_job.actors[14].score==0, "Initial reload does not count or reward reserved slots")
	# Earn an upgrade through native damage/scoring and the normal alternating
	# director. A projectile launched just before the upgrade must remain usable.
	for cycle in 12:
		for index in runtime.active_job.actors.size():
			if runtime.active_job.actors[index].hp>0: runtime.damage_actor(index,100000)
		if runtime.active_job.survival.score >= decl.rules.upgrades.score[0]: break
		survival_save_clock(runtime,2.001);survival_save_clock(runtime,2.001)
	survival_save_clock(runtime,1.999)
	var old_speed: float=runtime.actor_weapons()[0].speed
	check(Combat.fire(runtime.combat,0,Vector3.ZERO,Vector3.FORWARD,lib,runtime.actor_weapons()), "Launch projectile immediately before earned upgrade")
	survival_save_clock(runtime,.002)
	check(runtime.active_job.survival.upgrade_index==1 and runtime.actor_weapons()[0].speed!=old_speed, "Fixture reaches first earned upgrade with live older projectile")
	runtime.motion.throttle=.37;runtime.flight_rotation=Vector3(.1,.2,.3)
	var snapshot: Dictionary=JSON.parse_string(JSON.stringify(runtime.capture()))
	var restored := Arcade.new();restored.configure_survival(lib,decl,1,3,18)
	check(restored.restore(snapshot), "Restore upgraded survival with old launch speed: " + restored.error)
	check(JSON.parse_string(JSON.stringify(restored.capture()))==snapshot, "Round trip retains all serialized changing state")
	check(restored.actor_weapons()==runtime.actor_weapons() and restored.arena==runtime.arena, "Restore reconstructs weapon history and actor definitions from supplied data")
	check(restored.combat.projectiles[0].velocity[2]==-old_speed and restored.motion.throttle==.37 and restored.flight_rotation==runtime.flight_rotation, "Reload preserves projectile velocity, throttle and orientation")
	var untouched := restored.capture()
	snapshot.actors[0].position[0]+=500
	check(restored.capture()==untouched, "Restored actor vectors do not alias caller-owned JSON")
	snapshot=JSON.parse_string(JSON.stringify(runtime.capture()))
	survival_save_clock(restored,2.001);survival_save_clock(runtime,2.001)
	if restored.capture()!=runtime.capture():
		print("REINFORCEMENT equality after numeric normalization: ",same_saved_value(restored.capture(),runtime.capture()))
	check(same_saved_value(restored.capture(),runtime.capture()), "Reload preserves the next reinforcement draw and clock stage")
	# Reach multiple archetypes and all player upgrades, using real score history.
	for cycle in 20:
		for index in runtime.active_job.actors.size():
			if runtime.active_job.actors[index].hp>0: runtime.damage_actor(index,100000)
		survival_save_clock(runtime,2.001);survival_save_clock(runtime,2.001)
	check(runtime.active_job.survival.upgrade_index==decl.rules.upgrades.score.size() and runtime.active_job.actors.any(func(a): return a.promotions.size()>1), "Longer fixture reaches all player upgrades and revisited enemy profiles")
	var advanced: Dictionary=JSON.parse_string(JSON.stringify(runtime.capture()))
	check(restored.restore(advanced) and restored.actor_weapons()==runtime.actor_weapons() and restored.arena==runtime.arena, "Restore reconstructs later promotions, cooldown bounds and reserved-slot distinctions")
	var before := restored.capture()
	for pair in [["schema",17],["slot","campaign"],["content_id","different"],["ship_id",99],["weapon_id",3],["hull",99999],["seed",null],["kills",-1],["mission_elapsed_ms",0],["actors",[]],["combat",{}]]:
		var bad := advanced.duplicate(true);bad[pair[0]]=pair[1]
		check(not restored.restore(bad) and restored.capture()==before, "Reject invalid survival header/state without mutating current run")
	for pair in [["upgrade_index",99],["active_count",100],["score",0],["combo",1000000000],["cycle",1000000000],["seed",48]]:
		var bad := advanced.duplicate(true);bad.director[pair[0]]=pair[1]
		check(not restored.restore(bad) and restored.capture()==before, "Reject impossible saved director progress")
	for pair in [["hp",99999],["heading",[0,0,0]],["position",[INF,0,0]],["shots",-1],["archetype",99],["promotions",[1,1]],["awake",false]]:
		var bad := advanced.duplicate(true);bad.actors[0][pair[0]]=pair[1]
		check(not restored.restore(bad) and restored.capture()==before, "Reject malformed actor state or forged promotion history")
	var bad := advanced.duplicate(true);bad.actors[14].hp=1
	check(not restored.restore(bad), "Reserved last slot cannot become alive through a save")
	bad=initial.duplicate(true);bad.actors[0].promotions=[1];bad.actors[0].archetype=1
	check(not restored.restore(bad), "Initial population cannot claim an unavailable enemy archetype")
	bad=snapshot.duplicate(true);bad.combat.projectiles[0].velocity=[0,0,-12345]
	check(not restored.restore(bad), "Saved projectile cannot invent a speed outside earned profile history")
	# A valid catalogue weapon that is absent from the survival loadout must
	# not fall through the shared combat resolver during save validation.
	var unfitted := -1
	for id in lib.items.size():
		if not runtime.loadout.weapons().has(id) and not lib.weapon_ballistics(id).is_empty(): unfitted=id;break
	bad=snapshot.duplicate(true);bad.combat=Combat.create()
	Combat.fire(bad.combat,unfitted,Vector3.ZERO,Vector3.FORWARD,lib)
	check(not restored.restore(bad), "Reject unfitted catalogue projectile without touching current session")
	bad=advanced.duplicate(true);bad.combat=Combat.create()
	for index in 11:
		Combat.fire(bad.combat,-1,Vector3.ZERO,Vector3.FORWARD,lib,runtime.actor_weapons())
		bad.combat.cooldowns.clear()
	var extra: Dictionary=bad.combat.projectiles.back().duplicate(true);extra.id=bad.combat.next_id;bad.combat.next_id+=1;bad.combat.projectiles.append(extra)
	# Keep existing shot history consistent so rejection exercises the pool cap.
	for actor in bad.actors:actor.shots=0
	check(not restored.restore(bad), "Reject overfilled independent enemy projectile pool")
	bad=advanced.duplicate(true);bad.combat=Combat.create()
	Combat.fire(bad.combat,-15,Vector3.ZERO,Vector3.FORWARD,lib,runtime.actor_weapons())
	for actor in bad.actors:actor.shots=0
	check(not restored.restore(bad), "Reserved never-active slot cannot own a live projectile")
	runtime.hull=0
	check(restored.restore(JSON.parse_string(JSON.stringify(runtime.capture()))) and restored.hull==0, "Defeated run can be restored without reviving the pilot")
	var next_ship := int(restored.next_ship_cycle);restored.retry_mission()
	check(restored.ship_id==next_ship and restored.active_job.survival.score==0, "Save reload retains next ship choice for retry")
	# Native save I/O uses its own content identity directory and atomic backup.
	var directory := "user://survival-save-tests/%d/%s" % [Time.get_ticks_usec(),lib.id]
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("survival.json")
	var campaign_path := directory.path_join("campaign.json")
	var campaign := Session.new();campaign.configure(lib);campaign.save(campaign_path)
	var campaign_bytes := FileAccess.get_file_as_bytes(campaign_path)
	check(not restored.save(campaign_path) and FileAccess.get_file_as_bytes(campaign_path)==campaign_bytes, "Survival cannot overwrite campaign slot through an incorrect path")
	check(restored.save(path), "Write dedicated survival slot: " + restored.error)
	var first := restored.capture()
	restored.hull-=5
	check(restored.save(path) and FileAccess.file_exists(path+".bak"), "Subsequent save preserves the previous survival run")
	var broken := FileAccess.open(path,FileAccess.WRITE);broken.store_string("{broken");broken.close()
	var loaded := restored.load_save(path)
	check(loaded and JSON.parse_string(JSON.stringify(restored.capture()))==JSON.parse_string(JSON.stringify(first)), "Corrupt main survival save falls back to its valid backup: " + restored.error)
	check(not campaign.restore(restored.capture()) and not restored.restore(campaign.capture()), "Campaign and survival serializers reject each other's state")
	check(FileAccess.get_file_as_bytes(campaign_path)==campaign_bytes, "Survival save/load operations leave campaign file byte-for-byte intact")
	for name in [path,path+".bak",path+".tmp",campaign_path,campaign_path+".bak"]:
		if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
	DirAccess.remove_absolute(directory);DirAccess.remove_absolute(directory.get_base_dir())


func check_survival_scores(source: PackedByteArray, lib) -> void:
	var Profile = preload("res://src/simulation/arcade_profile.gd")
	var reader := NativeData.new();reader.bytes=source;reader.parse_macho()
	var rules := reader.survival_scores()
	check(not rules.is_empty() and reader.error.is_empty(), "Recover survival local records and result labels")
	if rules.is_empty():return
	check(rules.count==10 and rules.initial_name==" ---" and rules.initial_score==0 and rules.initial_wave==0 and rules.type==14, "Source survival table defaults")
	check(rules.labels=={"defeat":398,"kills":107,"time":106,"score":636,"main_menu":573} and rules.minimum_result_score==1, "Result fields and positive-score gate are source defined")
	for id in rules.labels.values():check(not lib.text(int(id)).is_empty(), "Result label resolves against imported text")
	var refresh := reader.symbol_address("__ZN10MenuWindow21refreshHighscoreTableEi")
	var reset := reader.symbol_address("__ZN13RecordHandler14resetHighscoreEi")
	var menu := reader.symbol_address("__ZN10MenuWindow10switchMenuEj")
	var results := reader.symbol_address("__ZN5MGame13gameOverCheckEv")
	var changed := source.duplicate()
	for pair in [[reset+0x86,0x2007],[refresh+0x92,0x2b07],[reset+0x116,0x2b1c],[refresh+0xa2,0x2106],[menu+0x118,0x6998]]:
		changed.encode_u16(reader.file_offset(pair[0],2),pair[1])
	reader.bytes=changed
	var altered := reader.survival_scores()
	var profile := Profile.new()
	check(not altered.is_empty() and altered.count==7 and profile.configure(lib.id,altered,10) and profile.state.entries.size()==7, "Native board capacity follows matching changed source consumers")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(results+0xbe,2),0x216c)
	reader.bytes=changed;altered=reader.survival_scores()
	check(not altered.is_empty() and altered.labels.kills==108, "Result label is read from its original association")
	for at in [refresh+0x7e,refresh+0x92,reset+0x116,results+0x58,menu+0x118]:
		changed=source.duplicate();changed.encode_u16(reader.file_offset(at,2),0xbf00)
		reader.bytes=changed;reader.error=""
		check(reader.survival_scores().is_empty(), "Unsupported ordering, size or result consumer is rejected")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(reset+0x86,2),0x2007)
	reader.bytes=changed;reader.error=""
	check(reader.survival_scores().is_empty(), "Conflicting table capacity is rejected")
	check(profile.configure(lib.id,rules,10), "Configure isolated local arcade profile")
	var empty := profile.capture()
	check(profile.qualifying_rank(0)==-1 and profile.qualifying_rank(1)==0, "Zero score never enters blank table")
	var run := profile.begin_run()
	check(run=={"run":1,"ship_cycle":0} and profile.begin_run().is_empty(), "Starting a run allocates one identity without skipping an in-progress ship")
	var loaded := Profile.new();loaded.configure(lib.id,rules,10)
	check(loaded.restore(JSON.parse_string(JSON.stringify(profile.capture()))) and loaded.begin_run().is_empty(), "Reload keeps pending identity for resume")
	check(loaded.finish(run.run,"First",100)=={"accepted":true,"rank":0}, "First qualifying score is inserted")
	var first := loaded.capture()
	check(not loaded.finish(run.run,"Replay",999).accepted and loaded.capture()==first, "Acknowledging the same result twice cannot replace its score")
	check(profile.restore(first), "Load completed local record")
	run=profile.begin_run()
	check(run.ship_cycle==1 and profile.finish(run.run,"Second",100).rank==1, "Tied score stays after earlier score")
	run=profile.begin_run();profile.finish(run.run,"Higher",200)
	check(profile.state.entries.slice(0,3).map(func(e):return e.name)==["Higher","First","Second"], "Higher result shifts existing equal-score rows without reordering ties")
	run=profile.begin_run();var pending := profile.capture()
	check(not profile.finish(run.run,"",150).accepted and profile.capture()==pending, "Qualifying result requires a valid name without consuming pending run")
	check(not profile.finish(run.run,"Bad\nName",150).accepted, "Name cannot inject another rendered row")
	check(profile.abandon(run.run) and not profile.abandon(run.run), "Abandon consumes no leaderboard entry and is idempotently rejected")
	for index in 8:
		run=profile.begin_run();profile.finish(run.run,"Pilot %d"%index,50+index)
	check(profile.state.entries.size()==10 and profile.state.entries.back().score==51, "Full board retains only highest source-count scores")
	run=profile.begin_run()
	check(profile.qualifying_rank(51)==-1 and profile.finish(run.run,"",51)=={"accepted":true,"rank":-1}, "Tie with last place does not qualify or require a name")
	run=profile.begin_run()
	check(profile.finish(run.run,"",0).accepted, "Zero-score result can be acknowledged without name entry")
	check(profile.state.serial==14 and profile.state.next_ship_cycle==4, "Ship rotation wraps across completed, abandoned and unranked runs")
	var valid: Dictionary=JSON.parse_string(JSON.stringify(profile.capture()))
	check(loaded.restore(valid), "Ranked profile survives JSON round trip")
	valid.state.entries[0].name="Caller mutation"
	check(loaded.state.entries[0].name=="Higher", "Restored profile does not alias caller data")
	valid=JSON.parse_string(JSON.stringify(profile.capture()))
	var before := loaded.capture()
	for pair in [["serial",-1],["pending",2],["next_ship_cycle",0],["entries",[]]]:
		var bad:=valid.duplicate(true);bad.state[pair[0]]=pair[1]
		check(not loaded.restore(bad) and loaded.capture()==before, "Reject malformed profile progress without partial mutation")
	for pair in [["schema",99],["content_id","other"],["mode",13]]:
		var bad:=valid.duplicate(true);bad[pair[0]]=pair[1]
		check(not loaded.restore(bad) and loaded.capture()==before, "Reject unrelated content/mode/schema")
	for pair in [["score",0],["run",0],["run",15],["name",""]]:
		var bad:=valid.duplicate(true);bad.state.entries[0][pair[0]]=pair[1]
		check(not loaded.restore(bad) and loaded.capture()==before, "Reject impossible ranked row")
	var bad:=valid.duplicate(true);bad.state.entries[2].run=bad.state.entries[1].run
	check(not loaded.restore(bad), "Duplicate run cannot occupy two rows")
	bad=valid.duplicate(true);var swap:Dictionary=bad.state.entries[1];bad.state.entries[1]=bad.state.entries[2];bad.state.entries[2]=swap
	check(not loaded.restore(bad), "Loaded tied rows preserve original arrival order")
	check(loaded.restore(empty), "Source placeholder entries can be restored")
	var directory := "user://arcade-profile-tests/%d/%s" % [Time.get_ticks_usec(),lib.id]
	var path := directory.path_join("arcade.json")
	check(loaded.save(path), "Create separate content-specific local record file: "+loaded.error)
	run=loaded.begin_run();loaded.finish(run.run,"Saved",42)
	check(loaded.save(path), "Atomically save completed record and preserve backup")
	var disk := FileAccess.get_file_as_bytes(path)
	check(not loaded.save(directory.path_join("campaign.json")) and not loaded.save(directory.get_base_dir().path_join("arcade.json")), "Reject campaign slot and wrong content directory")
	check(FileAccess.get_file_as_bytes(path)==disk, "Rejected writes preserve arcade file")
	check(profile.load_file(path) and profile.state.entries[0].name=="Saved", "Read persisted highscore")
	var broken:=FileAccess.open(path,FileAccess.WRITE);broken.store_string("{broken");broken.close()
	check(profile.load_file(path) and profile.capture()==empty, "Corrupt main record file falls back to original backup")
	for name in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
	DirAccess.remove_absolute(directory);DirAccess.remove_absolute(directory.get_base_dir())


func check_choice_presentation(source: PackedByteArray, lib) -> void:
	var Dialog = preload("res://src/presentation/choice_window.gd")
	var reader := NativeData.new();reader.bytes=source;reader.parse_macho()
	var data := reader.choice_presentation()
	check(not data.is_empty() and reader.error.is_empty(), "Recover original choice window artwork and layout")
	if data.is_empty():return
	check(data.images.size()==6 and data.default_caption=="OK" and data.layout=={"base_y":108,"short_lines":4,"text_padding":10,"extra_rows":1,"button_x":17,"button_text_y":9}, "Source cap, body and button measurements")
	for binding in data.images.values():check(lib.ui_image(binding).get_width()>0, "Original dialog atlas resolves")
	var body := reader.symbol_address("__ZN12ChoiceWindow3setERKN11AbyssEngine6StringEb")
	var changed:=source.duplicate()
	changed.encode_u16(reader.file_offset(body+0xe4,2),0x225a)
	changed.encode_u16(reader.file_offset(body+0x120,2),0x215a)
	reader.bytes=changed;var altered := reader.choice_presentation()
	check(not altered.is_empty() and altered.layout.base_y==90, "Dialog vertical position comes from supplied layout")
	changed=source.duplicate();changed.encode_u16(reader.file_offset(body+0x126,2),0xbf00)
	reader.bytes=changed;reader.error=""
	check(reader.choice_presentation().is_empty(), "Unsupported text height arithmetic is rejected")
	var view := Dialog.new();root.add_child(view);view.size=Vector2(480,320)
	var choices:=[];view.chosen.connect(func(index):choices.append(index))
	view.present(lib,data,"Game Over")
	var geometry:=view.measure()
	check(geometry.panel.position==Vector2(140.5,108) and geometry.panel.size==Vector2(199,90), "Short acknowledged panel uses original measured strips")
	view.confirm_event(false)
	check(choices.is_empty() and view.visible, "Unmatched release cannot dismiss new dialog")
	view.confirm_event(true);view.confirm_event(false);view.accept(0)
	check(choices==[0] and not view.visible, "Keyboard acknowledgement closes and emits once")
	view.present(lib,data,"one\ntwo\nthree\nfour\nfive")
	geometry=view.measure()
	check(geometry.panel.position.y==94 and geometry.panel.size.y==150, "Additional original text line shifts panel upward by imported font height")
	view.present(lib,altered,"short")
	check(view.measure().panel.position.y==90, "Native dialog consumes changed source geometry")
	view.present(lib,data,"Long ".repeat(180),["Confirm","Cancel"])
	geometry=view.measure()
	var screen:Rect2=Rect2(geometry.origin+geometry.panel.position*geometry.factor,geometry.panel.size*geometry.factor)
	check(Rect2(Vector2.ZERO,view.size).encloses(screen), "Long localized message keeps both buttons within viewport")
	view.present(lib,data,"Choose",["Confirm","Cancel"])
	# Supply hit areas for input-only checks; the rendered test checks these
	# against measured artwork separately, without requiring a GPU in this suite.
	view.buttons.assign([Rect2(10,10,100,30),Rect2(10,50,100,30)])
	view.pointer_event(3,Vector2(20,60),true);view.pointer_event(4,Vector2(20,60),false)
	check(choices==[0] and view.visible, "Other finger cannot release owned dialog button")
	view.pointer_event(3,Vector2(200,60),false)
	check(choices==[0] and view.visible, "Release outside the owned button cancels click")
	view.pointer_event(-1,Vector2(20,60),true);view.pointer_event(-1,Vector2(20,60),false)
	check(choices==[0,1], "Pointer confirmation selects the second source button")
	view.present(lib,data,"Choose",["Confirm","Cancel"])
	var down:=InputEventJoypadButton.new();down.button_index=JOY_BUTTON_DPAD_DOWN;down.pressed=true;view._input(down)
	var confirm:=InputEventJoypadButton.new();confirm.button_index=JOY_BUTTON_A;confirm.pressed=true;view._input(confirm);confirm.pressed=false;view._input(confirm)
	check(choices==[0,1,1], "Controller navigation and release confirm selected dialog action")
	view.queue_free();await process_frame


class SurvivalWriteFault:
	extends "res://src/simulation/survival_archive.gd"
	var fail_suffix := ""
	func write_file(filename: String, contents: String) -> bool:
		if not fail_suffix.is_empty() and filename.ends_with(fail_suffix):
			error="Injected storage interruption"
			return false
		return super.write_file(filename,contents)


func check_survival_archive(source: PackedByteArray, lib) -> void:
	var Archive = preload("res://src/simulation/survival_archive.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var decl:={"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{}),"scores":reader.survival_scores()}
	check(reader.error.is_empty(),"Read coordinated survival declarations")
	var directory:="user://survival-archive-tests/%d/%s"%[Time.get_ticks_usec(),lib.id]
	var path:=directory.path_join(Archive.FILE_NAME)
	var archive:=Archive.new()
	check(archive.open(lib,decl,directory) and archive.session==null and archive.profile.state.serial==0,"Open new survival archive without starting a run")
	check(not FileAccess.file_exists(path),"Opening empty profile does not create a gameplay checkpoint")
	var initial:=archive.capture()
	check(not archive.open(lib,decl,directory.get_base_dir()) and archive.capture()==initial,"Wrong content directory cannot replace an open profile")
	check(archive.start(0,47),"Commit first survival run and its identity together: "+archive.error)
	check(archive.session.ship_id==0 and archive.profile.state.pending==1 and FileAccess.file_exists(path),"Starting run persists matching first ship and pending identity")
	var running:=archive.capture();var disk:=FileAccess.get_file_as_bytes(path)
	check(not archive.start(0,48) and not archive.finish("Premature") and archive.capture()==running,"Active flight cannot start another run or submit a live score")
	check(FileAccess.get_file_as_bytes(path)==disk,"Rejected menu operations do not rewrite checkpoint")
	archive.session.motion.throttle=.4
	survival_save_clock(archive.session,1.25)
	archive.session.damage_actor(0,100000)
	check(archive.session.active_job.kills==1 and archive.session.active_job.survival.score==decl.rules.ships.score[0],"Result fixture earns score through native enemy destruction")
	check(archive.checkpoint(),"Checkpoint active combat and local profile in one file")
	var resumed:=Archive.new()
	check(resumed.open(lib,decl,directory),"Resume coordinated active run: "+resumed.error)
	check(JSON.parse_string(JSON.stringify(resumed.capture()))==JSON.parse_string(JSON.stringify(archive.capture())),"Reload retains profile, live combat, clocks and throttle together")
	var id:=int(resumed.profile.state.pending)
	check(id==1 and resumed.session.motion.throttle==.4,"Resume does not allocate another identity or rotate ship")
	resumed.session.hull=0
	check(resumed.checkpoint(),"Defeated run is saved before name entry")
	var defeated:=resumed.capture()
	check(not resumed.finish("") and resumed.capture()==defeated,"Missing qualifying name leaves defeated run available")
	# Interrupt a result commit after the candidate main document has been written,
	# but before its valid backup and atomic rename. Restart must ignore that .tmp.
	var interrupted:=SurvivalWriteFault.new()
	check(interrupted.open(lib,decl,directory),"Open fault-injected writer on real defeated checkpoint")
	interrupted.fail_suffix=".bak.tmp"
	check(not interrupted.finish("Mira") and interrupted.capture()==defeated,"Storage interruption cannot consume the in-memory result")
	check(FileAccess.file_exists(path+".tmp"),"Interrupted commit leaves only an uncommitted result candidate")
	var restart:=Archive.new()
	check(restart.open(lib,decl,directory) and restart.session!=null and restart.session.hull==0 and restart.profile.state.pending==id,"Restart ignores result candidate and restores last committed defeated run")
	check(restart.finish("Mira"),"Retry records defeated run atomically: "+restart.error)
	check(restart.session==null and restart.profile.state.pending==0 and restart.receipt.run==id and restart.receipt.rank==0,"Result commit removes pending flight and stores ranked receipt together")
	check(restart.profile.state.points==restart.receipt.score,"Atomic result commit includes newly accumulated pilot rank points")
	var result:=restart.capture();disk=FileAccess.get_file_as_bytes(path)
	check(not restart.finish("Again") and not restart.start(0,48) and restart.capture()==result,"Result replay and new run wait for acknowledgement")
	check(resumed.open(lib,decl,directory) and resumed.session==null and resumed.receipt.name=="Mira","Restart restores result receipt without resurrecting finished run")
	check(resumed.profile.state.points==resumed.receipt.score,"Archive reload restores rank points with the same result receipt")
	check(resumed.profile.state.entries.filter(func(row):return row.run==id).size()==1,"Completed run occupies exactly one leaderboard row")
	for pair in [["run",99],["score",999],["rank",1],["name","Changed"],["elapsed",-1]]:
		var bad:=result.duplicate(true);bad.receipt[pair[0]]=pair[1]
		check(resumed.decode(bad).is_empty(),"Reject receipt inconsistent with committed profile or result bounds")
	var bad:=result.duplicate(true);bad.run=defeated.run
	check(resumed.decode(bad).is_empty(),"Committed result cannot also retain a pending flight")
	bad=defeated.duplicate(true);bad.run.id=2
	check(resumed.decode(bad).is_empty(),"Run identity must match profile pending identity")
	bad=defeated.duplicate(true);bad.run={}
	check(resumed.decode(bad).is_empty(),"Pending identity requires its matching gameplay snapshot")
	bad=defeated.duplicate(true);bad.run.snapshot.content_id="other"
	check(resumed.decode(bad).is_empty(),"Snapshot cannot switch game content inside archive")
	bad=defeated.duplicate(true);bad.profile.state.serial=2;bad.profile.state.pending=2;bad.profile.state.next_ship_cycle=2;bad.run.id=2
	check(resumed.decode(bad).is_empty(),"Matching IDs cannot pair with another cycle's starting ship")
	check(resumed.acknowledge_result() and resumed.receipt.is_empty(),"Result acknowledgement clears receipt and retains board")
	check(not resumed.acknowledge_result(),"Second acknowledgement has no effect")
	check(resumed.start(0,48) and resumed.session.ship_id==1 and resumed.profile.state.pending==2,"Next run uses persisted source ship rotation")
	var board:Array=resumed.profile.state.entries.duplicate(true)
	check(resumed.abandon() and resumed.session==null and resumed.profile.state.entries==board,"Abandon clears current flight without recording score or changing board")
	check(resumed.start(0,49) and resumed.session.ship_id==2,"Abandon consumes exactly one ship rotation")
	resumed.session.hull=0
	check(resumed.finish() and resumed.receipt.rank==-1 and resumed.receipt.score==0,"Zero-score defeat commits without name entry")
	check(resumed.profile.state.entries==board and resumed.acknowledge_result(),"Unranked result does not change local board")
	check(resumed.start(0,50),"Start next run for backup recovery checks")
	var saved:=resumed.capture()
	resumed.session.motion.throttle=.2
	check(resumed.checkpoint(),"Create checkpoint with valid predecessor backup")
	var broken:=FileAccess.open(path,FileAccess.WRITE);broken.store_string("{broken");broken.close()
	check(restart.open(lib,decl,directory) and JSON.parse_string(JSON.stringify(restart.capture()))==JSON.parse_string(JSON.stringify(saved)),"Corrupt main checkpoint restores matching run/profile from backup")
	check(restart.checkpoint(),"Saving after recovery preserves validated checkpoint rather than corrupt main")
	broken=FileAccess.open(path,FileAccess.WRITE);broken.store_string("{broken again");broken.close()
	check(restart.open(lib,decl,directory),"Valid backup remains recoverable after a second main-file failure")
	var before:=restart.capture()
	broken=FileAccess.open(path+".bak",FileAccess.WRITE);broken.store_string("{also broken");broken.close()
	check(not restart.open(lib,decl,directory) and restart.capture()==before,"Two corrupt documents report failure without resetting current scores/run")
	# The controller path is distinct from campaign/free and standalone developer
	# snapshots. A mistaken slot must not overwrite any of them.
	var campaign:=directory.path_join("campaign.json")
	var file:=FileAccess.open(campaign,FileAccess.WRITE);file.store_string("campaign sentinel");file.close()
	var real_path:String=resumed.path;resumed.path=campaign
	check(not resumed.checkpoint() and FileAccess.get_file_as_string(campaign)=="campaign sentinel","Coordinator cannot overwrite a campaign file")
	resumed.path=real_path
	for name in [path,path+".bak",path+".tmp",path+".bak.tmp",campaign]:
		if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
	# Failed first write leaves profile serial and ship rotation unchanged.
	interrupted=SurvivalWriteFault.new();interrupted.open(lib,decl,directory);interrupted.fail_suffix=".tmp"
	check(not interrupted.start(0,47) and interrupted.profile.state.serial==0 and interrupted.session==null,"Failed first checkpoint does not consume run identity")
	check(not FileAccess.file_exists(path),"Failed first checkpoint leaves no committed run")
	DirAccess.remove_absolute(directory);DirAccess.remove_absolute(directory.get_base_dir())


func check_survival_result(source: PackedByteArray, lib) -> void:
	var Archive=preload("res://src/simulation/survival_archive.gd")
	var Result=preload("res://src/presentation/survival_result.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var rules:=reader.survival_scores();var appearance:=reader.choice_presentation()
	check(not rules.is_empty() and not appearance.is_empty() and reader.error.is_empty(),"Read result text and original dialog declarations")
	if rules.is_empty() or appearance.is_empty():return
	check(rules.format=={"paragraph":"\n\n","label_suffix":": ","value_break":"\n","zero_suffix":"\n\n"},"Result separators are recovered from original text construction")
	check(Result.duration(0)=="00:00" and Result.duration(59.99)=="00:59" and Result.duration(60)=="01:00" and Result.duration(3599)=="59:59" and Result.duration(3600)=="01:00:00" and Result.duration(86400)=="24:00:00", "Run-time formatting handles seconds, hour boundaries and total days")
	var summary:={"score":729,"kills":16,"elapsed":66.45}
	var text:=Result.result_text(lib,rules,summary)
	check(text=="Game Over\n\nKills: \n16\n\nTime playing: \n01:06\n\nScore: \n729","Result text follows original labels, ordering and line breaks")
	var results:=reader.symbol_address("__ZN5MGame13gameOverCheckEv")
	var changed:=source.duplicate()
	changed.encode_u32(literal_file_offset(reader,results+0xd4),reader.literal(results+0xa0,2))
	reader.bytes=changed;var altered:=reader.survival_scores()
	check(not altered.is_empty() and Result.result_text(lib,altered,summary).contains("Kills\n\n\n16"),"Native result consumes changed source formatting")
	reader.bytes=source;reader.error=""
	var decl:={"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{}),"scores":rules}
	var directory:="user://survival-result-tests/%d/%s"%[Time.get_ticks_usec(),lib.id]
	var archive:=Archive.new();check(archive.open(lib,decl,directory) and archive.start(0,47),"Start coordinated result fixture")
	var view:=Result.new();root.add_child(view);view.size=Vector2(480,320)
	check(archive.result_summary().is_empty() and not view.present_result(archive,appearance) and not view.visible,"Living run cannot show a defeat result")
	archive.session.damage_actor(0,100000);survival_save_clock(archive.session,1.25);archive.session.hull=0
	check(view.present_result(archive,appearance) and view.visible,"Defeated native session supplies result dialog")
	check(view.message.contains("Kills: \n1") and view.message.contains("Score: \n"+str(int(decl.rules.ships.score[0]))) and view.captions==[lib.text(rules.labels.main_menu)],"Window uses actual earned score and supplied menu caption")
	var pending:=archive.capture();var choices:=[];view.chosen.connect(func(index):choices.append(index))
	view.confirm_event(true);view.confirm_event(false)
	check(choices==[0] and archive.capture()==pending,"Result button requests menu/name flow without submitting score implicitly")
	check(archive.finish("Pilot"),"Record score after explicit native name flow")
	var recorded:=archive.result_summary();recorded.score+=1
	check(archive.receipt.score!=recorded.score,"Result display receives an independent receipt copy")
	check(view.present_result(archive,appearance),"Committed receipt remains displayable without an active flight")
	var expected:=view.message
	var resumed:=Archive.new();check(resumed.open(lib,decl,directory) and view.present_result(resumed,appearance) and view.message==expected,"Restart restores identical result text from persisted receipt")
	check(resumed.acknowledge_result() and resumed.start(0,48),"Acknowledge prior receipt and start next result fixture")
	resumed.session.hull=0
	check(view.present_result(resumed,appearance) and view.message=="Game Over\n\n","Zero-score defeat uses original short message")
	check(resumed.finish() and view.present_result(resumed,appearance) and view.message=="Game Over\n\n","Unranked saved receipt retains short zero-score result")
	view.queue_free();await process_frame
	var path:=directory.path_join(Archive.FILE_NAME)
	for name in [path,path+".bak",path+".tmp",path+".bak.tmp"]:
		if FileAccess.file_exists(name):DirAccess.remove_absolute(name)
	DirAccess.remove_absolute(directory);DirAccess.remove_absolute(directory.get_base_dir())


func check_survival_name(source: PackedByteArray, lib) -> void:
	var NameEntry=preload("res://src/presentation/survival_name.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var menu:=reader.survival_menu()
	check(not menu.is_empty(),"Read source survival menu/name form: "+reader.error)
	if menu.is_empty():return
	check(menu.tabs==[493,650] and menu.table.columns==[45,195,355] and menu.table.row_gap==3,"Read source survival tabs and leaderboard geometry")
	check(menu.name_entry.limit==9 and menu.name_entry.height_lines==2 and menu.name_entry.frame==[70,40,340,90],"Read nine-character input limit and original name-frame dimensions")
	var bound:=reader.symbol_address("-[AppController textField:shouldChangeCharactersInRange:replacementString:]")+8
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(bound,2),0x2904)
	reader.bytes=changed;var altered:=reader.survival_menu()
	check(not altered.is_empty() and altered.name_entry.limit==5,"Name input limit follows supplied declaration rather than runtime constant")
	reader.bytes=source
	var view:=NameEntry.new();root.add_child(view);view.size=Vector2(960,640)
	view.present(lib,menu,"Pilot")
	await process_frame
	var font:FontFile=view.entry.get_theme_font("font")
	var expected:=0.0
	for code in "Pilot".length():expected+=lib.radio_glyph_width("Pilot".unicode_at(code))
	if OS.has_feature("mobile"):
		check(font.get_string_size("Pilot",HORIZONTAL_ALIGNMENT_LEFT,-1,font.fixed_size).x==expected,"Mobile editable font keeps imported glyph advances")
		check(font.get_height(font.fixed_size)==14 and font.has_char(80),"Mobile editable font retains imported glyph atlas")
	else:
		check(font.fixed_size==0 and not font.data.is_empty(),"Desktop editor uses scalable font outlines")
		check(int(font.get_meta("source_height"))==14 and font.has_char(80),"Desktop editor keeps imported layout height")
	check(view.entry.has_focus() and view.entry.max_length==9 and view.entry.virtual_keyboard_enabled,"Name form focuses real input with source bound and virtual keyboard enabled")
	check(view.entry.position==Vector2(90,80) and view.entry.size==Vector2(300,28) and view.canvas.scale==Vector2.ONE*preload("res://src/presentation/bitmap_font.gd").composition_scale(view.size),"Input follows original field coordinates under viewport scaling")
	check(view.prompt.text==lib.text(menu.name_entry.prompt),"Prompt comes from supplied localization")
	view.entry.text="";view.entry.insert_text_at_caret("ABCDEFGHIJKLM")
	check(view.entry.text=="ABCDEFGHI","Paste cannot bypass source name limit")
	view.entry.text="Pilot";view.entry.select(0,5)
	for letter in "Mira":
		var typed:=InputEventKey.new();typed.unicode=letter.unicode_at(0);typed.pressed=true
		root.push_input(typed)
	await process_frame
	check(view.entry.text=="Mira","Native selection replacement edits bitmap text")
	var names:=[];view.submitted.connect(func(pilot):names.append(pilot))
	view.entry.text="   ";view.update_confirmation();view.submit_name()
	check(names.is_empty() and view.confirm.disabled and not view.awaiting_owner,"Empty names cannot consume a qualifying result")
	view.entry.text=" Mira ";view.submit_name();view.submit_name()
	check(names==["Mira"] and view.awaiting_owner and view.confirm.disabled,"Explicit submission trims edges and emits once while owner commits score")
	view.retry_submission()
	check(view.entry.text==" Mira " and not view.awaiting_owner and view.entry.has_focus(),"Failed score commit permits retry without losing typed name")
	view.entry.text_submitted.emit(view.entry.text)
	check(names==["Mira","Mira"],"Keyboard return uses same guarded submission path")
	view.present(lib,altered,"LongerName")
	check(view.entry.text=="Longe" and view.entry.max_length==5,"Reopened form follows changed source name bound")
	var cancellations:=[];view.cancelled.connect(func():cancellations.append(true))
	var cancel:=InputEventKey.new();cancel.physical_keycode=KEY_ESCAPE;cancel.pressed=true
	view._input(cancel);view.submit_name()
	check(not view.visible and cancellations.size()==1 and names.size()==2,"Cancel hides input without submitting pending score")
	view.present(lib,menu,"Mira")
	var accept:=InputEventJoypadButton.new();accept.button_index=JOY_BUTTON_A;accept.pressed=false
	view._input(accept)
	check(names.size()==2,"Stray controller release cannot confirm a name")
	accept.pressed=true;view._input(accept);view.clear_input();accept.pressed=false;view._input(accept)
	check(names.size()==2,"Losing focus clears a held controller confirmation")
	accept.pressed=true;view._input(accept);accept.pressed=false;view._input(accept)
	check(names.size()==3 and names.back()=="Mira","Controller press and release submits entered name")
	view.size=Vector2(640,960);view.layout_controls()
	check(view.canvas.position.y>0 and view.canvas.scale.x==view.canvas.scale.y,"Portrait composition retains original proportions")
	view.queue_free();await process_frame


func check_survival_tabs(source: PackedByteArray, lib) -> void:
	var Menu=preload("res://src/presentation/survival_menu.gd")
	var Profile=preload("res://src/simulation/arcade_profile.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var menu:=reader.survival_menu();var rules:=reader.survival_scores()
	check(not menu.is_empty() and not rules.is_empty(),"Read survival menu artwork, rank and profile declarations: "+reader.error)
	if menu.is_empty() or rules.is_empty():return
	check(menu.presentation.right_origin==[263,60] and menu.presentation.picture_center==[345,150] and menu.presentation.score_right_padding==5,"Source preview and score-bar positions are recovered")
	check(menu.presentation.ranks.map(func(row):return row.points)==[0,10000,20000,40000,80000,160000,320000,640000,1280000,2560000],"Source rank thresholds retained as data")
	check(Menu.rank_index(10000,menu.presentation.ranks)==0 and Menu.rank_index(10001,menu.presentation.ranks)==1 and Menu.rank_index(2560001,menu.presentation.ranks)==9,"Rank titles use original strict threshold comparison")
	var changed:=source.duplicate();var threshold:=reader.symbol_address("__ZL20SURVIVAL_RANK_POINTS")
	changed.encode_u32(reader.file_offset(threshold+4,4),123)
	reader.bytes=changed;var altered:=reader.survival_menu()
	check(not altered.is_empty() and Menu.rank_index(124,altered.presentation.ranks)==1,"Rank UI follows changed supplied threshold")
	reader.bytes=source
	var profile:=Profile.new();check(profile.configure(lib.id,rules,3),"Configure local rank profile")
	check(profile.state.points==rules.points_initial,"Native accumulated points begin at source initial value")
	var first:=profile.begin_run();profile.finish(first.run,"Mira",10001)
	check(profile.state.points==10001,"Qualified finish adds score to accumulated pilot points")
	check(not profile.finish(first.run,"Repeat",10001).accepted and profile.state.points==10001,"Repeated result cannot add pilot points twice")
	for index in rules.count:
		var run:=profile.begin_run();profile.finish(run.run,"Pilot",20000)
	var points:int=profile.state.points
	check(points==10001+rules.count*20000 and not profile.state.entries.any(func(row):return row.run==first.run),"Discarded leaderboard row still contributes to accumulated rank")
	var run:=profile.begin_run();profile.finish(run.run,"",20000)
	check(profile.state.points==points,"Score tied with last entry is unqualified and adds no rank points")
	run=profile.begin_run();profile.abandon(run.run)
	check(profile.state.points==points,"Abandon does not add rank points")
	var restored:=Profile.new();restored.configure(lib.id,rules,3)
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.capture()))) and restored.state.points==points,"Rank points persist independently of retained leaderboard entries")
	var bad:=profile.capture();bad.state.points=0
	check(not restored.restore(bad),"Reject accumulated points smaller than committed board scores")
	bad=profile.capture();bad.schema=1;bad.state.erase("points")
	check(not restored.restore(bad),"Old private profile cannot silently invent missing accumulated points")
	var view:=Menu.new();root.add_child(view);view.size=Vector2(960,640)
	view.present(lib,menu,profile.state,profile.state.entries[0].run,0)
	await process_frame
	check(view.info.visible and not view.table.visible and view.tabs.size()==2,"Info and Highscore are two pages of one native screen")
	check(view.info_body.custom_minimum_size.y>0 and view.info.size.y==menu.content_height,"Description and all legend rows are laid out in source-height scroll region")
	check(view.table.get_child_count()==3*(rules.count+1),"Highscore table presents original headings and all local rows")
	if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
		check(is_equal_approx(view.tabs[-1].get_rect().end.x, menu.frame[0]+menu.frame[2]), "Survival tabs end at panel edge")
		for index in 3:
			check(view.table_divider_y > view.table.get_child(index).get_rect().end.y, "Leaderboard divider clears native text")
		check(view.table.get_child(-1).get_rect().end.y <= menu.frame[1]+menu.frame[3]-10, "All leaderboard rows fit above bottom padding")
	view.select_tab(1)
	check(view.table.visible and not view.info.visible,"Tab switch replaces description with highscore table")
	var calls:=[];view.start_requested.connect(func():calls.append("start"));view.back_requested.connect(func():calls.append("back"))
	view.leave_menu(true);view.leave_menu(true)
	check(calls==["start"],"Start requests owner transition only once")
	view.retry_action();view.leave_menu(false)
	check(calls==["start","back"] and profile.state.points==points,"Failed start may retry/back without changing profile")
	view.queue_free();await process_frame


func check_survival_hud(source: PackedByteArray, lib) -> void:
	var Feedback=preload("res://src/presentation/survival_feedback.gd")
	var Arcade=preload("res://src/simulation/survival_session.gd")
	var Hud=preload("res://src/presentation/hud.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var rules:=reader.survival_hud();var setup:=reader.survival_setup()
	check(not rules.is_empty() and not setup.is_empty(),"Read source survival HUD and missile unlock: "+reader.error)
	if rules.is_empty() or setup.is_empty():return
	check(rules.score_top==12 and rules.score_right==36 and rules.score_text==[7,5] and rules.elapsed_right==165 and rules.elapsed_bottom==17,"Source score panel and elapsed-time placement recovered")
	check(rules.notices.map(func(row):return row.above)==[199,999,1499,4999] and rules.notice_ms==2000 and rules.combo_ms==2000,"Source unlock notice thresholds and durations recovered")
	check(rules.combo_separator=="  x" and rules.combo_text==[629,630,631,632],"Source combo labels and multiplier format recovered")
	var state:=Feedback.initialize(0,0,0,rules)
	Feedback.advance(state,rules,200,1,100)
	check(Feedback.notice_text(state,lib)=="Weapon upgrade!" and Feedback.combo_text(state,rules,lib).is_empty(),"First threshold produces source upgrade announcement without a combo")
	Feedback.advance(state,rules,240,2,200)
	check(Feedback.combo_text(state,rules,lib)=="GOOD!  X2","Second kill shows original uppercase combo text")
	var paused_state:=state.duplicate(true)
	Feedback.advance(state,rules,240,2,200)
	check(state==paused_state,"Repeated paused frames do not advance notice clocks")
	Feedback.advance(state,rules,240,2,2200)
	check(Feedback.notice_text(state,lib).is_empty() and Feedback.combo_text(state,rules,lib).is_empty(),"Notices expire after source simulation duration")
	Feedback.advance(state,rules,5000,6,2201)
	check(Feedback.combo_text(state,rules,lib)=="UNBELIEVABLE!  X6" and state.queue.size()==2,"Large score change preserves crossed notices and source final combo caption")
	Feedback.advance(state,rules,5000,6,4201)
	check(Feedback.notice_text(state,lib)=="Missile available!","Queued missile notice remains visible after preceding upgrade")
	var resumed:=Feedback.initialize(5000,6,7000,rules)
	Feedback.advance(resumed,rules,5000,6,7000)
	check(Feedback.notice_text(resumed,lib).is_empty() and Feedback.combo_text(resumed,rules,lib).is_empty(),"Loading a run does not replay previously crossed cosmetic milestones")
	var changed:=source.duplicate();var draw:=reader.symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	changed.encode_u32(literal_file_offset(reader,draw+0xb2),1999)
	changed.encode_u32(literal_file_offset(reader,draw+0x8da),1999)
	reader.bytes=changed;var other:=reader.survival_setup();var changed_hud:=reader.survival_hud()
	check(not other.is_empty() and other.missile_score_above==1999 and changed_hud.notices[2].above==1999,"HUD announcement and gameplay missile threshold follow changed source data")
	reader.bytes=source;reader.error=""
	var content:={"rules":reader.survival_rules(),"setup":setup,"armament":reader.survival_armament(),"motion":reader.interceptor_combat().motion,"hud":rules}
	var pilot:=Arcade.new();check(pilot.configure_survival(lib,content,0,0,47),"Configure actual session with survival HUD declarations")
	var missile:int=pilot.loadout.weapons().filter(func(id):return int(lib.items[id][1])==lib.MISSILE_CATEGORY)[0]
	check(not pilot.weapon_enabled(missile) and pilot.weapon_enabled(pilot.weapon_id),"Starting survival allows the primary gun and locks missiles")
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,pilot,{"aim_assist":false});flight.set_physics_process(false);flight.paused=false
	var before:int=pilot.combat.projectiles.size()
	flight.fire_weapon(missile)
	check(pilot.combat.projectiles.size()==before and float(flight.weapon_timers.get(missile,0))==0,"Direct firing path cannot bypass locked survival missiles or consume cooldown")
	pilot.active_job.survival.score=setup.missile_score_above
	check(not pilot.weapon_enabled(missile),"Exact boundary keeps missile locked")
	pilot.active_job.survival.score+=1
	flight.fire_weapon(missile)
	check(pilot.weapon_enabled(missile) and pilot.combat.projectiles.size()>before,"Crossing source threshold permits actual missile projectile creation")
	var hud:=Hud.new();hud.flight=flight;hud.touch_enabled=true;root.add_child(hud);hud.size=Vector2(960,640)
	hud._process(0)
	check(hud.buttons.missiles.visible and not hud.objective.node.visible,"Survival shows unlocked touch missile control and hides campaign objective marker")
	pilot.active_job.survival.score=0;hud._process(0)
	check(not hud.buttons.missiles.visible,"Touch missile control follows same availability rule")
	pilot.active_job.survival.score=200;pilot.elapsed=.1;hud._process(0)
	var feedback:Dictionary=pilot.hud_feedback.duplicate(true)
	hud.free();hud=Hud.new();hud.flight=flight;root.add_child(hud);hud.size=Vector2(960,640);hud._process(0)
	check(pilot.hud_feedback==feedback and not hud.buttons.missiles.visible,"Pause HUD recreation keeps transient feedback without enabling desktop touch controls")
	hud.queue_free();flight.queue_free();await process_frame


class SurvivalMainHarness:
	extends "res://src/main.gd"
	var test_directory := ""
	func _ready() -> void:
		setup_world()
		setup_ui()
		add_child(music)
		set_process(false)
	func save_path(slot: String) -> String:
		return test_directory.path_join(slot + ".json")
	func play_music(_track: String) -> void:
		pass


func check_survival_main(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var decl:={"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{}),"scores":reader.survival_scores(),"menu":reader.survival_menu(),"choice":reader.choice_presentation(),"hud":reader.survival_hud()}
	check(reader.error.is_empty(),"Read main-flow survival declarations: "+reader.error)
	if not reader.error.is_empty():return
	var had_survival:bool=lib.content.has("survival");var previous=lib.content.get("survival")
	lib.content.survival=decl
	var directory:="user://survival-main-tests/%d/%s"%[Time.get_ticks_usec(),lib.id]
	DirAccess.make_dir_recursive_absolute(directory)
	var sentinel:=FileAccess.open(directory.path_join("campaign.json"),FileAccess.WRITE);sentinel.store_string("campaign sentinel");sentinel.close()
	var app:=SurvivalMainHarness.new();app.library=lib;app.ready_content=true;app.test_directory=directory;root.add_child(app)
	var archive:=SurvivalWriteFault.new();check(archive.open(lib,decl,directory),"Open isolated main-flow archive")
	app.survival_archive=archive;app.show_survival_menu()
	check(app.screen=="survival_menu" and app.survival_panel.active_tab==0,"Main presents source survival Info tab")
	archive.fail_suffix=".tmp";app.survival_panel.leave_menu(true)
	check(app.screen=="survival_menu" and not app.survival_panel.awaiting_owner and archive.session==null,"Failed start unlocks source Start without allocating a run")
	archive.fail_suffix="";app.survival_panel.leave_menu(true);app.flight.set_physics_process(false)
	check(app.screen=="flight" and app.session==archive.session and archive.profile.state.pending==1,"Start enters actual Flight with archive-owned session")
	check(not app.flight_objective.visible and not app.hud.extra_buttons.has("DOCK") and not app.hud.extra_buttons.has("AUTOPILOT"),"Survival hides campaign objective and station actions")
	app.flight.toggle_autopilot();var docks:=[];app.flight.dock_requested.connect(func():docks.append(true));app.flight.try_dock()
	check(not app.flight.auto_pilot and docks.is_empty(),"Keyboard station actions cannot enable autopilot or dock in survival")
	app.show_pause();check(app.screen=="pause" and app.flight.paused,"Pause freezes actual survival Flight")
	var old_flight=app.flight;var live=app.session
	archive.fail_suffix=".tmp";app.show_title()
	check(app.screen=="pause" and app.flight==old_flight and app.session==live,"Failed save prevents leaving an unfinished run")
	await app.shutdown()
	check(not app.exiting and app.flight==old_flight,"Failed shutdown save preserves live run and permits retry")
	archive.fail_suffix="";app.show_title()
	check(app.screen=="title" and app.flight==null,"Successful main-menu exit checkpoints then removes Flight")
	var reloaded:=SurvivalWriteFault.new();check(reloaded.open(lib,decl,directory),"Reopen controller checkpoint after exit")
	app.session=null;app.survival_archive=reloaded;archive=reloaded;app.show_survival_menu();app.start_survival();app.flight.set_physics_process(false)
	check(app.session==archive.session and archive.profile.state.pending==1 and app.session.ship_id==0,"Resume uses same pending run and ship after reopening archive")
	app.session.motion.throttle=.25;app.save_timer=31;app._process(0)
	var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(archive.path))
	check(disk.run.snapshot.motion.throttle==.25 and not FileAccess.file_exists(directory.path_join("survival.json")),"Autosave writes coordinated archive, never standalone survival save")
	app.session.damage_actor(0,100000);app.session.hull=0;app.defeat()
	check(app.screen=="survival_result" and app.flight.paused and archive.session.hull==0,"Defeat shows original result and retains defeated run")
	disk=JSON.parse_string(FileAccess.get_file_as_string(archive.path));check(disk.run.snapshot.hull==0,"Defeat checkpoints before name entry")
	app.resume_flight();check(app.screen=="survival_result" and app.flight.paused,"Defeated run cannot resume from pause")
	app.survival_panel.accept(0);check(app.screen=="survival_name","Qualifying result opens source name entry")
	app.survival_panel.entry.text="Mira";app.survival_panel.cancelled.emit();check(app.screen=="survival_result" and archive.profile.state.pending==1,"Cancelling name entry preserves pending result")
	app.advance_survival_result();check(app.survival_panel.entry.text=="Mira","Cancelling name entry preserves typed draft in current run");archive.fail_suffix=".tmp";app.survival_panel.submit_name()
	check(app.screen=="survival_name" and app.survival_panel.entry.text=="Mira" and app.survival_panel.entry.editable and archive.profile.state.pending==1,"Failed score write preserves name and enables retry")
	archive.fail_suffix="";app.survival_panel.submit_name()
	check(app.screen=="survival_menu" and app.survival_panel.active_tab==1 and app.flight==null and app.session==null,"Successful submission returns to Highscore and detaches old Flight")
	check(archive.profile.state.entries[0].name=="Mira" and archive.profile.state.entries[0].run==1 and archive.profile.state.pending==0 and archive.receipt.is_empty(),"Controller records and acknowledges exactly one result")
	var recorded:=archive.capture();app.submit_survival_name("Again");check(archive.capture()==recorded,"Late submission cannot duplicate a completed score")
	app.start_survival();app.flight.set_physics_process(false);check(app.session.ship_id==1 and archive.profile.state.pending==2,"Next Start rotates ship once")
	app.show_pause();archive.fail_suffix=".tmp";app.abandon_survival();check(app.screen=="pause" and app.session==archive.session,"Failed abandonment preserves paused run")
	archive.fail_suffix="";app.abandon_survival();check(app.screen=="survival_menu" and app.session==null and archive.profile.state.pending==0,"Explicit abandonment ends run without posting a score")
	check(archive.profile.state.entries[0].run==1,"Abandonment preserves prior highscore")
	app.start_survival();app.flight.set_physics_process(false)
	archive.fail_suffix=".tmp";app.save_timer=31;app._process(0)
	check(app.screen=="pause" and app.flight.paused,"Autosave failure pauses survival instead of silently continuing")
	archive.fail_suffix="";app.resume_flight();app.session.damage_actor(0,100000);app.session.hull=0;app.defeat()
	check(archive.finish("Receipt"),"Persist controller result before simulated acknowledgement interruption")
	app.stop_flight();app.session=null
	var receipt_archive:=SurvivalWriteFault.new();check(receipt_archive.open(lib,decl,directory),"Reopen committed result receipt after interrupted UI flow")
	app.survival_archive=receipt_archive;archive=receipt_archive;app.show_survival_menu()
	check(app.screen=="survival_result" and app.flight==null,"Returning to survival restores pending receipt before allowing Start")
	var score_count:int=archive.profile.state.entries.filter(func(row):return row.run>0).size()
	archive.fail_suffix=".tmp";app.survival_panel.accept(0)
	check(app.screen=="survival_result" and app.survival_panel.visible and not archive.receipt.is_empty(),"Failed acknowledgement reopens result and retains receipt")
	archive.fail_suffix="";app.survival_panel.accept(0)
	check(app.screen=="survival_menu" and app.survival_panel.active_tab==1 and archive.profile.state.entries.filter(func(row):return row.run>0).size()==score_count,"Retry acknowledgement returns Highscore without adding score again")
	app.start_survival();app.flight.set_physics_process(false);app.session.hull=0;app.defeat();app.survival_panel.accept(0)
	check(app.screen=="survival_menu" and app.survival_panel.active_tab==1 and archive.profile.state.pending==0,"Zero-score defeat returns directly to Highscore without name entry")
	check(FileAccess.get_file_as_string(directory.path_join("campaign.json"))=="campaign sentinel","Entire survival controller flow preserves campaign file")
	app.queue_free();await process_frame
	if had_survival:lib.content.survival=previous
	else:lib.content.erase("survival")
	for filename in DirAccess.get_files_at(directory):DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory);DirAccess.remove_absolute(directory.get_base_dir())


func check_survival_backdrop(source: PackedByteArray, lib) -> void:
	var Backdrop=preload("res://src/presentation/backdrop.gd")
	var Arcade=preload("res://src/simulation/survival_session.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var setup:=reader.survival_setup();var sky:=reader.sky_presentation()
	check(not setup.is_empty() and setup.background=="random","Survival resolves random sky consumer beyond station-image caller: "+reader.error)
	if setup.is_empty():return
	check(sky.variant_count==9 and sky.tints.size()==4 and sky.cloud_meshes.size()==6,"Read survival's nine sky variants, four styles and six cloud layers")
	var address:=reader.symbol_address("__ZN5Level12createSkyboxEib")
	for offset in [0x52,0x54,0x76,0x84,0x8e]:
		var corrupt:=source.duplicate();corrupt.encode_u16(reader.file_offset(address+offset,2),0xbf00);reader.bytes=corrupt;reader.error=""
		check(reader.survival_setup().is_empty(),"Changed survival sky branch or random consumer is rejected: %x"%offset)
	reader.bytes=source;reader.error=""
	var bg:=Backdrop.new();var first:=bg.select(lib,0,-1,47)
	check(first==bg.select(lib,1,-1,47),"Survival sky choice comes from run seed, independent of station")
	var variants:=[]
	for seed_value in range(47,147):
		var selected:=bg.select(lib,0,-1,seed_value)
		if not variants.has(selected.variant):variants.append(selected.variant)
	check(variants.size()>1,"New run seeds select different sky variants")
	check(first==bg.select(lib,0,-1,47),"Rebuilding survival backdrop retains run sky")
	check(bg.select(lib,0).variant==lib.station_definition(0).image,"Ordinary flight retains station-selected backdrop")
	var original:Dictionary=lib.content.sky;var changed:=original.duplicate(true);changed.variant_count=1;changed.cloud_meshes=[original.cloud_meshes[0]];changed.tints=[original.tints[0]];lib.content.sky=changed
	check(bg.select(lib,0,-1,47)=={"variant":0,"cloud":0,"style":0},"Survival selection obeys imported resource dimensions")
	lib.content.sky=original;bg.free()
	var decl:={"rules":reader.survival_rules(),"setup":setup,"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{})}
	var state:=Arcade.new();check(state.configure_survival(lib,decl,0,0,47),"Configure random-sky survival fixture")
	var before:=state.capture();var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{},true);flight.set_physics_process(false)
	check(flight.backdrop.declaration==first and flight.backdrop.get_child_count()==4,"Actual survival Flight uses run sky and all four source layers")
	check(state.capture()==before,"Backdrop creation leaves director/combat/save state unchanged")
	var selected:Dictionary=flight.backdrop.declaration.duplicate(true)
	flight.queue_free();await process_frame
	var resumed:=Arcade.new();check(resumed.configure_survival(lib,decl,0,0,0) and resumed.restore(before),"Restore run without adding cosmetic state to snapshot")
	var second:=Flight.new();root.add_child(second);second.setup(lib,resumed,{},true);second.set_physics_process(false)
	check(second.backdrop.declaration==selected,"Resumed actual Flight recreates original run's sky")
	second.queue_free();await process_frame


func check_survival_radar(source: PackedByteArray, lib) -> void:
	var Hud=preload("res://src/presentation/hud.gd")
	var Arcade=preload("res://src/simulation/survival_session.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var data:=reader.survival_radar()
	check(not data.is_empty() and data.bounds==[2,5],"Read source radar archetype boundaries: "+reader.error)
	if data.is_empty():return
	check(JSON.parse_string(JSON.stringify(data.images.strong_near))==lib.content.flight_ui.radar.images.enemy_near and JSON.parse_string(JSON.stringify(data.images.strong_off))==lib.content.flight_ui.radar.images.enemy_off,"Strong survival enemies reuse source red hostile markers")
	check(data.images.weak_near!=data.images.medium_near and data.images.medium_near!=data.images.strong_near,"Weak and medium source marker artwork is distinct")
	var draw:=reader.symbol_address("__ZN5Radar4drawEi")
	var mutation:=source.duplicate()
	for offset in [0x224,0x25c,0x4bc]:
		var at:=reader.file_offset(draw+offset,2);mutation.encode_u16(at,(mutation.decode_u16(at)&0xff00)|1)
	reader.bytes=mutation;var changed:=reader.survival_radar()
	check(not changed.is_empty() and changed.bounds==[1,5],"Strength boundaries follow coordinated supplied comparisons")
	mutation.encode_u16(reader.file_offset(draw+0x224,2),0x2d03);reader.bytes=mutation
	check(reader.survival_radar().is_empty(),"Conflicting near/far/off strength thresholds are rejected")
	reader.bytes=source;reader.error=""
	var hud_rules:=reader.survival_hud()
	var decl:={"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{}),"hud":hud_rules}
	var state:=Arcade.new();check(state.configure_survival(lib,decl,0,0,47),"Configure survival radar fixture")
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{},true);flight.set_physics_process(false)
	var hud:=Hud.new();hud.flight=flight;root.add_child(hud);hud.size=Vector2(960,640);hud.set_process(false)
	for pair in [[0,"weak"],[2,"weak"],[3,"medium"],[5,"medium"],[6,"strong"],[8,"strong"]]:
		check(hud.marker_kind("enemy",{"archetype":pair[0]})==pair[1],"HUD strength boundary %d selects %s artwork"%pair)
	check(hud.marker_kind("ally",{"archetype":0})=="ally","Friendly target retains friendly marker regardless of survival strength")
	var point:Vector3=flight.camera.global_position-flight.camera.global_basis.z*100
	var marker:Dictionary=hud.create_marker(Color.WHITE,false)
	for kind in ["weak","medium","strong"]:
		hud.place(marker,point,kind,true);check(marker.outline.texture==hud.radar_art[kind+"_near"] and marker.health.visible,"Near "+kind+" target uses source strength marker with health bar")
		hud.place(marker,point,kind,false);check(marker.outline.texture==hud.radar_art[kind+"_far"] and not marker.health.visible,"Distant "+kind+" target uses source strength dot")
		hud.place(marker,flight.camera.global_position+flight.camera.global_basis.z*100,kind,true);check(marker.outline.texture==hud.radar_art[kind+"_off"] and not marker.health.visible,"Behind-camera "+kind+" target uses source strength edge marker")
	hud.survival_rules={};check(hud.marker_kind("enemy",{"archetype":0})=="enemy","Campaign HUD retains ordinary hostile marker")
	hud.queue_free();flight.queue_free();await process_frame


func check_survival_player_guns(source: PackedByteArray, lib) -> void:
	var Arcade=preload("res://src/simulation/survival_session.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var data:=reader.survival_player_armament()
	check(not data.is_empty(),"Read actual player gun construction, distinct from enemy assignGuns: "+reader.error)
	if data.is_empty():return
	check(data["0"].mounts==[[200,-100,300],[-200,-100,300]] and data["0"].damage_divisor==2 and data["0"].pool_capacity==10,"Source starting laser has two offset muzzles, half damage and ten shots per muzzle")
	check(data["3"].mounts==[[0,-100,200]] and data["3"].damage_override==19 and data["3"].pool_capacity==1,"Source survival missile has one muzzle, one live slot and damage override")
	check(data["0"].projectile_model==10050 and data["3"].projectile_model==10058 and data["3"].projectile_overlay==10062,"Read original starting laser, missile and missile glow model IDs")
	var start:=reader.symbol_address("__ZN5Level9createGunEiiiiii")
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(start+0x21e,2),0x2396);changed.encode_u16(reader.file_offset(start+0xa9a,2),0x2417)
	reader.bytes=changed;var altered:=reader.survival_player_armament()
	check(not altered.is_empty() and altered["0"].mounts[0][0]==150 and altered["3"].damage_override==23,"Player muzzle position and survival missile override follow supplied constants")
	for offset in [0x128,0x29c,0x268,0xb6c,0xc50]:
		changed=source.duplicate();changed.encode_u16(reader.file_offset(start+offset,2),0xbf00);reader.bytes=changed;reader.error=""
		check(reader.survival_player_armament().is_empty(),"Reject unsupported player weapon data consumer %x"%offset)
	reader.bytes=source;reader.error=""
	var decl:={"rules":reader.survival_rules(),"setup":reader.survival_setup(),"armament":reader.survival_armament(),"motion":reader.interceptor_combat().get("motion",{})}
	var state:=Arcade.new();check(state.configure_survival(lib,decl,0,0,47),"Configure mounted player session: "+state.error)
	if not state.error.is_empty():return
	var laser:int=state.weapon_id;var ids:Array[int]=state.player_weapon_ids(laser)
	check(ids==[laser,laser+lib.items.size()] and state.player_weapon_ids(3)==[3],"Native muzzle identities are separate from inventory and enemy IDs")
	check(state.actor_weapons()[ids[0]].damage==int(lib.weapon_ballistics(laser).damage/2) and state.actor_weapons()[ids[1]].damage==state.actor_weapons()[ids[0]].damage,"Both mounted laser profiles use source split damage")
	check(state.actor_weapons()[3].damage==19 and state.actor_weapons()[3].has("guidance") and state.actor_weapons()[3].guidance_target_ids==range(int(decl.rules.pool_size)),"Missile profile preserves survival override and actual enemy guidance pool")
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{"aim_assist":false},true);flight.set_physics_process(false)
	flight.ship.rotation=Vector3(.2,.7,-.1);flight.fire_weapon(laser)
	check(state.combat.projectiles.size()==2 and flight.bolts.size()==2,"One primary trigger creates two native projectiles and original visuals")
	if state.combat.projectiles.size()!=2:flight.queue_free();await process_frame;return
	for index in 2:
		var shot:Dictionary=state.combat.projectiles[index]
		var expected:Vector3=flight.ship.position+flight.ship.basis*state.Mission.point(data["0"].mounts[index])
		check(shot.weapon==ids[index] and Combat.vector(shot.position).is_equal_approx(expected),"Muzzle %d follows ship rotation and source offset"%index)
		check(flight.bolts[int(shot.id)].get_meta("projectile_key")[0]==data["0"].projectile_model,"Muzzle %d uses original bolt mesh"%index)
	flight.fire_weapon(laser);check(state.combat.projectiles.size()==2,"Immediate repeated trigger respects both muzzle cooldowns")
	var before:Dictionary=JSON.parse_string(JSON.stringify(state.capture()))
	var restored:=Arcade.new();restored.configure_survival(lib,decl,0,0,0)
	check(restored.restore(before) and restored.actor_weapons()==state.actor_weapons(),"Snapshot restores both muzzle identities, cooldowns and derived profiles")
	var legacy:=before.duplicate(true);legacy.schema=1
	check(not restored.restore(legacy),"Pre-mount private survival snapshots cannot silently change projectile meaning")
	var pool:=Combat.create();var profiles:Dictionary=state.actor_weapons()
	for index in int(data["0"].pool_capacity):
		pool.cooldowns.clear();Combat.fire(pool,ids[0],Vector3.ZERO,Vector3.FORWARD,lib,profiles)
	pool.cooldowns.clear()
	check(not Combat.fire(pool,ids[0],Vector3.ZERO,Vector3.FORWARD,lib,profiles) and Combat.fire(pool,ids[1],Vector3.ZERO,Vector3.FORWARD,lib,profiles),"Full first muzzle pool does not consume the second muzzle's slots")
	var invalid:=before.duplicate(true);invalid.combat=pool.duplicate(true);invalid.combat.cooldowns.clear()
	var shot:Dictionary=invalid.combat.projectiles[0].duplicate(true);shot.id=invalid.combat.next_id;invalid.combat.next_id+=1;invalid.combat.projectiles.append(shot)
	check(not restored.restore(invalid),"Snapshot rejects more live shots than an individual imported muzzle pool")
	state.combat=Combat.create();flight.weapon_timers=state.combat.cooldowns
	flight.fire_weapon(3);check(state.combat.projectiles.is_empty(),"Mounted missile still obeys source score gate")
	# Earn upgrades through the native director, keeping clocks coherent for save checks.
	for cycle in 64:
		for index in state.active_job.actors.size():
			if state.active_job.actors[index].hp>0:state.damage_actor(index,100000)
		survival_save_clock(state,2.001);survival_save_clock(state,2.001)
		if state.weapon_enabled(3):break
	check(state.weapon_enabled(3),"Earn source missile unlock through survival scoring")
	check(state.actor_weapons()[ids[0]].damage==state.actor_weapons()[ids[1]].damage and state.actor_weapons()[ids[0]].mount_offset==data["0"].mounts[0] and state.actor_weapons()[ids[1]].pool_capacity==10,"Upgrades update both primary muzzles while preserving mounts and pools")
	check(state.actor_weapons()[3].damage==19 and state.actor_weapons()[3].projectile_model==10058,"Excluded missile category retains its original profile through primary upgrades")
	flight.fire_weapon(3)
	check(state.combat.projectiles.size()==1 and state.combat.projectiles[0].has("guidance"),"Unlocked missile creates guided native projectile")
	var missile:Dictionary=state.combat.projectiles[0]
	check(flight.bolts[int(missile.id)].get_child_count()==1 and flight.bolts[int(missile.id)].get_meta("projectile_key")==[10058,10062],"Actual missile visual includes source body and glow")
	var point:=Combat.vector(missile.position)+Combat.vector(missile.velocity).normalized()*100+Vector3(10,5,0)
	var target:={"id":0,"position":Combat.packed(point),"visible":true,"active":true,"alive":true,"team":"enemy"}
	Combat.advance(state.combat,.2,[],lib,state.actor_weapons(),[target]);state.elapsed+=.2;state.active_job.elapsed_ms+=200
	check(state.combat.projectiles[0].guidance.target==0,"Player missile acquires an eligible enemy after source guidance delay")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(state.capture()))
	check(restored.restore(saved) and restored.combat.projectiles[0].guidance.target==0,"Upgraded save restores mounted profiles and guided missile lock")
	var bad:=decl.duplicate(true);bad.armament.player["0"].mounts=[]
	check(not Arcade.valid_declarations(bad,lib),"Missing player muzzle declaration is rejected")
	bad=decl.duplicate(true);bad.armament.player["3"].projectile_model=999999
	check(not Arcade.valid_declarations(bad,lib),"Missing player projectile resource is rejected")
	var campaign:=Session.new();campaign.configure(lib)
	check(campaign.player_weapon_ids(campaign.weapon_id)==[campaign.weapon_id,campaign.weapon_id+lib.items.size()],"Campaign starter retains both imported muzzle identities independently of survival")
	flight.queue_free();await process_frame


func check_survival_content(lib) -> void:
	var Validator=preload("res://src/content/survival_content.gd")
	var original:Dictionary=lib.content.survival.duplicate(true)
	check(Validator.valid(original,lib),"Complete imported survival declaration validates")
	check(lib.valid_survival(),"Library accepts registered survival mode")
	for key in ["rules","setup","armament","motion","scores","menu","hud","choice"]:
		var missing:=original.duplicate(true);missing.erase(key)
		check(not Validator.valid(missing,lib),"Missing survival component is rejected: "+key)
	# Corrupt the actual JSON-shaped boundary, including values that could otherwise
	# crash a view, divide by zero, index an atlas, or silently lose gameplay data.
	for mutation in [
		[["menu","picture","region"],9999],
		[["menu","legend"], [null,null,null]],
		[["menu","presentation","images","tab_idle"],{}],
		[["menu","presentation","ranks"],[{"points":0,"text":99999}]],
		[["menu","table","header_height_divisor"],0],
		[["menu","table","columns"],[0,30,20]],
		[["menu","name_entry","limit"],0],
		[["menu","name_entry","input"],[0]],
		[["menu","tabs"],[0,99999]],
		[["menu","frame"],[0,0,0,1]],
		[["menu","presentation","fill"],[0,0,0,999]],
		[["hud","notices"],[{"above":2,"text":0},{"above":1,"text":0}]],
		[["hud","radar","bounds"],[5,2]],
		[["hud","radar","images","weak_far","texture"],999],
		[["hud","combo_ms"],0],
		[["hud","combo_text"],[]],
		[["scores","labels","defeat"],null],
		[["scores","format","paragraph"],[]],
		[["choice","images","body","region"],-1],
		[["choice","layout","text_padding"],4096],
		[["choice","layout","extra_rows"],-1],
		[["armament","player"],{}]
	]:
		var changed:=original.duplicate(true);var at:Dictionary=changed;var path:Array=mutation[0]
		for index in path.size()-1:at=at[path[index]]
		at[path[-1]]=mutation[1]
		check(not Validator.valid(changed,lib),"Damaged survival declaration rejected: "+str(path))
	lib.content.erase("survival")
	check(not lib.valid_survival() and lib.error.contains("Import the IPA again"),"Old cache requests reimport instead of hiding unfinished mode")
	lib.content.survival=original;lib.error=""


func check_registered_survival_flow(lib, capture: String = "") -> void:
	# Use only the installed composite declaration; no source-reader injection.
	var directory:="user://survival-installed-tests/%d/%s"%[Time.get_ticks_usec(),lib.id]
	var app:=SurvivalMainHarness.new();app.library=lib;app.ready_content=true;app.test_directory=directory;root.add_child(app)
	app.show_title();await process_frame
	app.title_panel.buttons[0].pressed.emit()
	check(app.title_panel.section=="start", "Original Start button opens game-mode choices")
	var title_button:Button
	for node in app.title_panel.buttons:
		if node.text==lib.text(int(lib.content.survival.menu.title)):title_button=node;break
	check(title_button!=null,"Registered content exposes original survival title entry")
	if title_button==null:app.free();return
	title_button.pressed.emit();await process_frame
	check(app.screen=="survival_menu" and app.survival_archive!=null,"Title action loads coordinated archive and imported Info view")
	app.survival_panel.footer[1].pressed.emit();await process_frame
	check(app.screen=="flight" and app.survival_active(),"Original Start action launches registered survival Flight")
	if app.flight==null:app.free();return
	app.flight.set_physics_process(false);app.flight.auto_pilot=true
	for tick in 1800:
		app.flight.fire_weapon(app.session.weapon_id)
		app.flight.step(1.0/60.0);app.flight.update_camera(1.0/60.0)
		if tick%30==0:await process_frame
		if app.session.active_job.kills>0 or app.flight.paused:break
	check(app.session.active_job.kills>0 and app.session.active_job.survival.score>0,"Imported mounted weapons earn a real kill and survival score")
	check(app.flight.backdrop.declaration.has("variant") and app.session.combat.next_id>0,"Registered flight builds source backdrop and fires projectiles")
	if not capture.is_empty():
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	app.show_pause();check(app.save_game(false),"Pause saves installed survival run")
	var snapshot:Dictionary=JSON.parse_string(JSON.stringify(app.session.capture()));var sky:Dictionary=app.flight.backdrop.declaration.duplicate(true)
	app.free();await process_frame
	app=SurvivalMainHarness.new();app.library=lib;app.ready_content=true;app.test_directory=directory;root.add_child(app)
	app.show_survival_menu();await process_frame
	var restored:Dictionary=JSON.parse_string(JSON.stringify(app.survival_archive.session.capture()))
	check(restored==snapshot,"Fresh controller restores archive without declaration injection")
	app.survival_panel.footer[1].pressed.emit();app.flight.set_physics_process(false);await process_frame
	check(JSON.parse_string(JSON.stringify(app.session.capture()))==snapshot and app.flight.backdrop.declaration==sky,"Start resumes same score, weapons and random sky")
	# Deterministic defeat boundary; damage mechanics are covered by Flight checks.
	app.session.hull=0;app.defeat();await process_frame
	check(app.screen=="survival_result" and app.survival_panel.declarations==lib.content.survival.choice,"Defeat opens imported result presentation")
	app.survival_panel.accept(0);await process_frame
	check(app.screen=="survival_name","Qualifying earned result requests original pilot name form")
	if app.screen=="survival_name":
		app.survival_panel.entry.text="Pilot"
		app.survival_panel.submit_name();await process_frame
		check(app.screen=="survival_menu" and app.survival_panel.active_tab==1,"Name confirmation returns to original Highscore tab")
		var rows:Array=app.survival_archive.profile.state.entries.filter(func(row):return row.run>0)
		check(rows.size()==1 and rows[0].name=="Pilot" and rows[0].score==snapshot.director.score,"Registered flow commits earned score exactly once")
	app.free();await process_frame


func check_paired_player_armament(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var guns:=reader.paired_player_armament()
	check(reader.error.is_empty() and guns.size()==8,"Read all eight paired ObjectGun constructions: "+reader.error)
	if guns.is_empty():return
	var expected:={"0":[200,10050],"1":[200,10051],"2":[200,10049],"22":[320,10064],"23":[270,10066],"24":[270,10065],"25":[320,10068],"26":[200,10067]}
	for id in expected:
		var gun:Dictionary=guns[id];var x:int=expected[id][0]
		check(gun.mounts==[[x,-100,300],[-x,-100,300]] and gun.projectile_model==expected[id][1],"Read actual paired muzzle spacing and original model for catalogue weapon "+id)
		check(gun.damage_divisor==2 and gun.pool_capacity==10,"Paired weapon uses source damage split and independent projectile capacity: "+id)
		check(lib.content.resources.has(str(int(gun.projectile_model))) and lib.mesh(lib.content.resources[str(int(gun.projectile_model))].path.get_file().get_basename()) != null,"Original paired projectile model resolves in supplied resources: "+id)
	var factory:=reader.symbol_address("__ZN5Level9createGunEiiiiii");var table:=factory+0x12c
	var changed:=source.duplicate();var first:=reader.u32(table+8);var second:=reader.u32(table+12)
	changed.encode_u32(reader.file_offset(table+8,4),second);changed.encode_u32(reader.file_offset(table+12,4),first)
	reader.bytes=changed;var swapped:=reader.paired_player_armament()
	check(swapped["1"].projectile_model==guns["2"].projectile_model and swapped["2"].projectile_model==guns["1"].projectile_model,"Catalogue associations follow supplied dispatch indices")
	# Every family is checked at its own construction site, including signed
	# literal mounts and split shifts, not only the previously supported starter.
	for record in [
		["0",0x2f472,0x2f45a,0x2f4f0,0x2f49e,0x2f47a],
		["1",0x2f744,0x2f732,0x2f7d2,0x2f774,0x2f74e],
		["2",0x2fa6c,0x2fa5a,0x2faf2,0x2fa9c,0x2fa76],
		["22",0x3204c,0x32030,0x320dc,0x32078,0x32052],
		["23",0x32386,0x3236c,0x32414,0x323b6,0x3238e],
		["24",0x326cc,0x326b0,0x3275c,0x326f8,0x326d2],
		["25",0x32a0a,0x329f0,0x32a98,0x32a3a,0x32a12],
		["26",0x32d48,0x32d2c,0x32dd6,0x32d72,0x32d4c]
	]:
		reader.bytes=source;reader.error=""
		changed=source.duplicate();var offset:=reader.file_offset(record[1],2)
		changed.encode_u16(offset,reader.u16(record[1])+1)
		reader.bytes=changed;var moved:=reader.paired_player_armament()
		check(not moved.is_empty() and moved[record[0]].mounts[0][0]>guns[record[0]].mounts[0][0],"Paired muzzle position comes from source constant: "+record[0])
		for address in record.slice(2):
			reader.bytes=source;reader.error="";changed=source.duplicate()
			changed.encode_u16(reader.file_offset(address,2),0xbf00)
			reader.bytes=changed
			check(reader.paired_player_armament().is_empty() and not reader.error.is_empty(),"Reject unsupported paired constructor/count/vector binding at %x"%address)
	reader.bytes=source;reader.error=""
	var original:=reader.survival_player_armament()
	check(original["0"]==guns["0"],"General paired reader agrees with the already implemented survival starter")


func check_plasma_player_armament(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var guns:=reader.plasma_player_armament()
	check(reader.error.is_empty() and guns.size()==3,"Read all three plasma gun constructions: "+reader.error)
	if guns.is_empty():return
	var expected:={"9":[[[200,-100,100],[-200,-100,100]],2,10025],"10":[[[0,-100,300]],1,10026],"11":[[[300,-100,200],[-300,-100,200]],2,10027]}
	for id in expected:
		var gun:Dictionary=guns[id]
		check(gun.mounts==expected[id][0] and gun.damage_divisor==expected[id][1],"Read distinct plasma muzzle geometry and damage treatment: "+id)
		check(gun.pool_capacity==10 and gun.projectile_model==expected[id][2],"Read original plasma pool and model: "+id)
		check(lib.mesh(lib.content.resources[str(int(gun.projectile_model))].path.get_file().get_basename())!=null,"Original plasma mesh is available: "+id)
	for record in [["9",0x304b8,0x304a0,0x30536,0x304de],["10",0x30794,0x3077c,0x30802,0x307fe],["11",0x30906,0x308ee,0x3098c,0x30932]]:
		reader.bytes=source;reader.error="";var changed:=source.duplicate()
		changed.encode_u16(reader.file_offset(record[1],2),reader.u16(record[1])+1)
		reader.bytes=changed;var shifted:=reader.plasma_player_armament()
		check(not shifted.is_empty() and shifted[record[0]].mounts!=guns[record[0]].mounts,"Plasma geometry follows supplied constants: "+record[0])
		for address in record.slice(2):
			reader.bytes=source;reader.error="";changed=source.duplicate()
			changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
			check(reader.plasma_player_armament().is_empty() and not reader.error.is_empty(),"Reject unsupported plasma data consumer at %x"%address)
	reader.bytes=source;reader.error=""
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(0x307b2,2),0x2501);reader.bytes=changed
	check(reader.plasma_player_armament().is_empty(),"Shared center/angle constant cannot silently introduce unsupported aim offsets")


func check_missile_player_armament(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var guns:=reader.missile_player_armament()
	check(reader.error.is_empty() and guns.size()==4,"Read all four normal missile weapon constructions: "+reader.error)
	if guns.is_empty():return
	var overlays:={"3":10060,"4":10062,"5":10063,"27":10061}
	for id in overlays:
		var gun:Dictionary=guns[id];var single:bool=id=="3"
		check(gun.mounts==([[0,-100,200]] if single else [[200,-100,200],[-200,-100,200]]) and gun.damage_divisor==(1 if single else 2),"Read missile geometry and damage division: "+id)
		check(not gun.has("damage_override") and gun.pool_capacity==1,"Normal missiles retain catalogue damage and independent one-shot pools: "+id)
		check(gun.projectile_model==10058 and gun.projectile_overlay==overlays[id] and gun.projectile_color==0,"Read missile body, original glow and color parameter: "+id)
		check(gun.trail=={"style":4,"segments":100} and gun.guidance.delay==.165 and gun.guidance.response_divisor==3,"Read missile trail and explicitly enabled guidance: "+id)
		check(lib.mesh(lib.content.resources[str(int(gun.projectile_overlay))].path.get_file().get_basename())!=null,"Original missile glow mesh resolves: "+id)
	var survival:=reader.survival_player_armament()
	check(survival["3"].damage_override==19 and survival["3"].projectile_overlay==10062 and guns["3"].projectile_overlay!=survival["3"].projectile_overlay,"Normal and survival starter missiles retain distinct source damage/glow branches")
	var changed:=source.duplicate()
	changed.encode_u16(reader.file_offset(0x300cc,2),0x2300);changed.encode_u16(reader.file_offset(0x30132,2),0x2300)
	reader.bytes=changed;var unhomed:=reader.missile_player_armament()
	check(not unhomed.is_empty() and not unhomed["4"].has("guidance") and unhomed["3"].has("guidance"),"Homing follows supplied flags, not the RocketGun class name")
	reader.bytes=source;reader.error="";changed=source.duplicate()
	changed.encode_u16(reader.file_offset(0x300c8,2),0x2306);changed.encode_u16(reader.file_offset(0x3012c,2),0x2306)
	reader.bytes=changed;var restyled:=reader.missile_player_armament()
	check(not restyled.is_empty() and restyled["4"].trail.style==6 and restyled["3"].trail.style==4,"Each missile trail style comes from its constructor arguments")
	reader.bytes=source;reader.error="";changed=source.duplicate()
	changed.encode_u16(reader.file_offset(0x5b6dc,2),0x2232);reader.bytes=changed
	var shorter:=reader.missile_player_armament()
	check(not shorter.is_empty() and shorter.values().all(func(gun):return gun.trail.segments==50),"Trail segment count comes from source trail construction")
	for address in [0x2fcc2,0x2fce6,0x3379e,0x337a0,0x2fd3a,0x2fdc0,0x2fea4,0x2fe92,0x2ff0c,0x2ffa6,0x300dc,0x300ce,0x3020c,0x3029e,0x303d4,0x3042c,0x33078,0x3311a,0x3328a,0x332f4,0x5b6de,0x5b89c]:
		reader.bytes=source;reader.error="";changed=source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
		check(reader.missile_player_armament().is_empty() and not reader.error.is_empty(),"Reject unsupported missile mode/count/constructor/effect consumer at %x"%address)
	reader.bytes=source;reader.error=""
	check(reader.paired_player_armament().size()==8 and reader.plasma_player_armament().size()==3,"Extended projectile helper retains standard and plasma declarations")


func check_multi_projectile_player_armament(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var guns:=reader.multi_projectile_player_armament()
	check(reader.error.is_empty() and guns.size()==3,"Read all multi-projectile weapon constructions: "+reader.error)
	if guns.is_empty():return
	var positions:={"12":[[300,30,200],[-300,10,300],[260,50,250],[-260,-40,200]],"13":[[300,30,200],[-310,10,300],[60,50,250],[-230,-40,200],[0,-50,300],[350,-20,280]],"14":[[300,30,200],[-310,10,300],[60,50,250],[-230,-40,200],[0,-50,300],[350,-20,280],[-330,-80,260]]}
	var damages:={"12":[2,2,2,2],"13":[2,3,2,3,2,3],"14":[2,2,2,3,2,2,2]}
	for id in positions:
		var gun:Dictionary=guns[id]
		check(gun.mounts==positions[id],"Read every asymmetric muzzle position: "+id)
		check(gun.projectile_model==10043+int(id) and gun.projectile_overlay==-1 and gun.projectile_color==0,"Read original multi-projectile body without glow: "+id)
		check(gun.trail=={"style":int(id)-7,"segments":20} and gun.guidance.response_divisor==1 and gun.guidance.delay==.165,"Read shorter trail and enabled fast homing: "+id)
		check(lib.mesh(lib.content.resources[str(int(gun.projectile_model))].path.get_file().get_basename())!=null,"Original multi-projectile mesh resolves: "+id)
		for index in gun.ballistics.size():
			var value:Dictionary=gun.ballistics[index]
			check(value.damage==damages[id][index] and value.pool_capacity==1 and value.lifetime_ms==1000+200*index and value.reload_ms==100+100*index and value.speed_per_ms==[32,30,28,26,24,26,28][index],"Read distinct ballistic tuple for weapon %s muzzle %s"%[id,index])
	var all_guns:=reader.player_armament()
	check(all_guns.size()==18 and all_guns.values().all(func(gun):return gun.trigger_muzzle==0),"Composite covers all 18 weapons with first-muzzle trigger cadence")
	var changed:=source.duplicate()
	changed.encode_u16(reader.file_offset(0x31c6e,2),0x231d);reader.bytes=changed
	var faster:=reader.multi_projectile_player_armament()
	check(not faster.is_empty() and faster["14"].ballistics[6].speed_per_ms==29 and faster["14"].ballistics[5].speed_per_ms==26,"Per-muzzle speed is recovered from supplied data")
	reader.bytes=source;reader.error="";changed=source.duplicate()
	var literal_at:=(0x31c90+4)&~3;literal_at+=(reader.u16(0x31c90)&255)*4
	changed.encode_u32(reader.file_offset(literal_at,4),2400);reader.bytes=changed
	var longer:=reader.multi_projectile_player_armament()
	check(not longer.is_empty() and longer["14"].ballistics[6].lifetime_ms==2400,"Read literal-backed final projectile lifetime")
	reader.bytes=source;reader.error="";changed=source.duplicate()
	for address in [0x30f0e,0x30f72,0x30fd6,0x3103a]:changed.encode_u16(reader.file_offset(address,2),0x2300)
	reader.bytes=changed;var unguided:=reader.multi_projectile_player_armament()
	check(not unguided.is_empty() and not unguided["12"].has("guidance") and unguided["13"].has("guidance"),"Multi-projectile homing follows actual supplied flags")
	reader.bytes=source;reader.error="";changed=source.duplicate()
	changed.encode_u16(reader.file_offset(0x5b74c,2),0x2219);reader.bytes=changed
	var trail:=reader.multi_projectile_player_armament()
	check(not trail.is_empty() and trail.values().all(func(gun):return gun.trail.segments==25),"No-overlay trail segment count is source data")
	for address in [0x30bd4,0x310c0,0x317d6,0x30c52,0x30d14,0x30db8,0x30ec6,0x31142,0x31206,0x312e4,0x3138c,0x31432,0x314dc,0x3185a,0x31920,0x319c4,0x31a9c,0x31b42,0x31bec,0x31c92,0x30f26,0x3153c,0x31fb4,0x30bf6,0x313e0,0x31c4c,0x30c28,0x31c70,0x30f14,0x5b74e]:
		reader.bytes=source;reader.error="";changed=source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
		check(reader.multi_projectile_player_armament().is_empty() and not reader.error.is_empty(),"Reject unsupported multi-projectile count/constructor/scalar/effect consumer %x"%address)
	for address in [0x30c0e,0x30cd0,0x30d72,0x30e80,0x310fe,0x311c2,0x3129e,0x31346,0x313d8,0x31496,0x31816,0x318dc,0x3197e,0x31a56,0x31ae8,0x31ba6,0x31c4e]:
		reader.bytes=source;reader.error="";changed=source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),reader.u16(address)|1);reader.bytes=changed
		check(reader.multi_projectile_player_armament().is_empty() and not reader.error.is_empty(),"Reject unsupported nonzero source direction offset %x"%address)
	for address in [0x53240,0x53244,0x53248,0x53254,0x5325a,0x53282,0x532ae]:
		reader.bytes=source;reader.error="";changed=source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
		check(reader.player_armament().is_empty() and not reader.error.is_empty(),"Reject changed player trigger consumer %x"%address)
	reader.bytes=source;reader.error="";changed=source.duplicate()
	var first:=0x2f380+4+12*4;var second:=first+4
	changed.encode_u32(reader.file_offset(first,4),reader.u32(second));changed.encode_u32(reader.file_offset(second,4),reader.u32(first));reader.bytes=changed
	var reordered:=reader.player_armament()
	check(reordered.size()==18 and reordered["12"].mounts.size()==6 and reordered["13"].mounts.size()==4,"Multi-projectile identities follow supplied dispatch associations")


func check_player_armament_runtime(lib) -> void:
	var Armament=preload("res://src/simulation/player_armament.gd")
	check(Armament.valid(lib.content.get("player_armament"),lib),"Validate complete imported player weapon declarations")
	var state:=Session.new();state.configure(lib)
	check(state.begin_mission(),"Start campaign for mounted weapon runtime")
	var profiles:Dictionary=state.actor_weapons()
	for key in lib.content.player_armament:
		var id:=int(key);var ids:Array[int]=state.player_weapon_ids(id)
		var declaration:Dictionary=lib.content.player_armament[key]
		check(ids.size()==declaration.mounts.size(),"Campaign exposes source muzzle count: "+key)
		var origins:Array[Vector3]=[]
		for muzzle in ids:origins.append(state.Mission.point(profiles[muzzle].mount_offset))
		var pool:=Combat.create()
		check(Combat.fire_volley(pool,ids,origins,Vector3.FORWARD,lib,profiles) and pool.projectiles.size()==ids.size(),"One trigger fires all available source muzzles: "+key)
		check(pool.cooldowns.size()==1 and Combat.valid(pool,lib,profiles),"Shared trigger and per-muzzle projectiles produce a valid snapshot: "+key)
		check(not Combat.fire_volley(pool,ids,origins,Vector3.FORWARD,lib,profiles),"Immediate repeat cannot bypass shared trigger: "+key)
	var ids:Array[int]=state.player_weapon_ids(14)
	var origins:Array[Vector3]=[]
	for id in ids:origins.append(state.Mission.point(profiles[id].mount_offset))
	var pool:=Combat.create()
	Combat.fire_volley(pool,ids,origins,Vector3.FORWARD,lib,profiles)
	# Leave the trigger muzzle occupied but release only the last projectile pool.
	pool.projectiles.pop_back();Combat.advance(pool,.11,[],lib,profiles)
	check(Combat.fire_volley(pool,ids,origins,Vector3.FORWARD,lib,profiles) and pool.projectiles.size()==7 and pool.projectiles.back().weapon==ids.back(),"Occupied first muzzle cannot block another free pool at shared trigger cadence")
	check(is_equal_approx(pool.projectiles.back().remaining,2.2) and is_equal_approx(Combat.vector(pool.projectiles.back().velocity).length(),560),"Last muzzle preserves distinct lifetime and speed")
	Combat.advance(pool,.11,[],lib,profiles)
	check(not Combat.fire_volley(pool,ids,origins,Vector3.FORWARD,lib,profiles) and is_equal_approx(pool.cooldowns[14],.1),"Full pools still consume the source trigger interval")
	state.combat=pool
	var saved:Dictionary=JSON.parse_string(JSON.stringify(state.capture()))
	var restored:=Session.new();restored.configure(lib)
	check(restored.restore(saved),"Campaign restores every source muzzle and guided projectile: "+restored.error)
	check(same_saved_value(restored.combat,Combat.normalize(saved.combat)),"Campaign reload preserves shared cooldown and active projectile state")
	var broken:=saved.duplicate(true);broken.combat.projectiles[0].weapon=lib.items.size()*31
	check(not restored.restore(broken),"Reject nonexistent muzzle identity without changing live state")
	check(same_saved_value(restored.combat,Combat.normalize(saved.combat)),"Rejected muzzle snapshot is atomic")
	var old:=state.capture();old.schema=17;old.combat=Combat.create()
	Combat.fire(old.combat,0,Vector3(1,2,3),Vector3.FORWARD,lib)
	var prior:Dictionary=old.combat.projectiles[0].duplicate(true)
	check(restored.restore(JSON.parse_string(JSON.stringify(old))),"Migrate old campaign ballistic snapshot without discarding shots: "+restored.error)
	var legacy:Dictionary=restored.combat.projectiles[0]
	var migrated_profiles:Dictionary=restored.actor_weapons()
	check(legacy.weapon==lib.items.size()*Armament.LEGACY_MOUNT and legacy.position==prior.position and legacy.velocity==prior.velocity and legacy.remaining==prior.remaining,"Legacy in-flight projectile preserves position, velocity and lifetime")
	check(migrated_profiles[int(legacy.weapon)].damage==lib.weapon_ballistics(0).damage and restored.combat.cooldowns[0]==old.combat.cooldowns[0],"Legacy damage and remaining trigger wait survive migration")
	check(not Combat.fire(restored.combat,int(legacy.weapon),Vector3.ZERO,Vector3.FORWARD,lib,migrated_profiles),"Legacy identities cannot launch new projectiles")
	var migrated_save:=restored.capture();var twice:=Session.new();twice.configure(lib)
	check(twice.restore(JSON.parse_string(JSON.stringify(migrated_save))) and same_saved_value(twice.combat,restored.combat),"Migrated legacy projectile survives another current-schema save/load")
	var malformed:=old.duplicate(true);malformed.combat.projectiles[0].velocity=[0,0,-1]
	check(not twice.restore(malformed),"Migration does not sanitize invalid old projectile speed")
	var free:=Session.new();free.configure(lib,true)
	check(free.player_weapon_ids(14).size()==7 and free.actor_weapons()[14].damage==2,"Exploration uses the same source player profiles")
	# Exercise real Flight geometry without replaying the campaign or unrelated UI.
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{"aim_assist":false},true);flight.set_physics_process(false)
	state.combat=Combat.create();state.active_job.radio={"shown":[],"pending":[],"current":{},"clock":0.0}
	flight.ship.rotation=Vector3(.2,.7,-.1)
	flight.fire_weapon(14)
	check(state.combat.projectiles.size()==7 and flight.bolts.size()==7,"Actual campaign Flight creates all seven original projectile visuals")
	for index in state.combat.projectiles.size():
		var shot:Dictionary=state.combat.projectiles[index]
		var expected:Vector3=flight.ship.position+flight.ship.basis*state.Mission.point(profiles[ids[index]].mount_offset)
		check(Combat.vector(shot.position).is_equal_approx(expected),"Campaign muzzle follows ship rotation: %s"%index)
	flight.queue_free();await process_frame


func check_player_armament_validation(lib) -> void:
	var Armament=preload("res://src/simulation/player_armament.gd")
	var value:Dictionary=lib.content.player_armament
	for change in [
		["0","mounts",[]],["0","trigger_muzzle",99],["0","pool_capacity",0],
		["0","damage_divisor",0],["0","projectile_model",-1],
		["3","guidance",{}],["3","trail",{"style":4,"segments":0}],
		["3","projectile_overlay",999999],["14","ballistics",[]],
		["14","ballistics",[null,null,null,null,null,null,null]]
	]:
		var bad:=value.duplicate(true);bad[change[0]][change[1]]=change[2]
		check(not Armament.valid(bad,lib),"Reject malformed imported player weapon field %s %s"%[change[0],change[1]])
	var missing:=value.duplicate(true);missing.erase("0")
	check(not Armament.valid(missing,lib),"Missing source weapon cannot fall back silently to generic ballistics")
	var legacy:=Combat.create();legacy.cooldowns[0]=lib.weapon_ballistics(0).interval+1
	check(Armament.migrate_combat(legacy,lib)==null,"Migration rejects impossible old trigger cooldown")
	legacy.cooldowns={};legacy.projectiles=[{"weapon":lib.items.size()*32}]
	check(Armament.migrate_combat(legacy,lib)==null,"Old schema cannot smuggle in a mounted or legacy projectile identity")
	var session:=Session.new();session.configure(lib);session.begin_mission()
	var invalid_actors:=session.capture();invalid_actors.active_job.actors=123
	check(not session.restore(invalid_actors),"Reject malformed actors before deriving player guidance targets")
	var invalid_cooldown:=session.capture();invalid_cooldown.schema=17
	invalid_cooldown.combat.cooldowns[0]=lib.weapon_ballistics(0).interval+1
	check(not session.restore(invalid_cooldown),"Full restore rejects impossible pre-muzzle cooldown")


func check_projectile_trails(source: PackedByteArray, lib) -> void:
	var Trail=preload("res://src/presentation/projectile_trail.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var appearance:=reader.projectile_trail_presentation()
	check(reader.error.is_empty() and appearance.styles.size()==11,"Read source projectile trail styles: "+reader.error)
	if appearance.is_empty():return
	check(appearance.material==20002 and is_equal_approx(appearance.half_width,1.2),"Trail uses original additive atlas material and source half-width")
	check(appearance.styles["4"].uv==[.34375,.28125,.375,.3125],"Original trail atlas strip and Q12 UV orientation")
	check(appearance.styles["4"].color==0xffffffff and appearance.styles["5"].color==0x00ff0000 and appearance.styles["6"].color==0xffff00ff and appearance.styles["7"].color==0xff0000ff,"White, green, yellow and red trail colors come from source style table")
	check(Trail.valid(lib.content.projectile_trails,lib),"Validate trail declarations against imported materials and player weapon styles")
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(0x5fd6a,2),0x231e);reader.bytes=changed
	check(is_equal_approx(reader.projectile_trail_presentation().half_width,.6),"Supplied width changes the native ribbon declaration")
	for address in [0x5fd8a,0x5fea0,0x5fca8,0x5fd10,0x5fd70,0x5fa82,0x5faa0]:
		reader.bytes=source;reader.error="";changed=source.duplicate();changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
		check(reader.projectile_trail_presentation().is_empty() and not reader.error.is_empty(),"Reject unsupported source trail consumer %x"%address)
	var trail:=Trail.new();root.add_child(trail)
	trail.configure(lib,{"style":5,"segments":20},Vector3.ZERO)
	check(not trail.visible and trail.points.size()==21,"Fresh trail resets its bounded history at the launch position")
	for index in 25:trail.advance(Vector3(sin(index*.2)*10,0,-index*2))
	check(trail.visible and trail.ribbon.get_surface_count()==1,"Moving projectile produces a native trail surface")
	var arrays:Array=trail.ribbon.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size()==42 and arrays[Mesh.ARRAY_INDEX].size()==120,"Source segment count controls ribbon geometry")
	check(trail.points[20].is_equal_approx(Vector3(sin(.8)*10,0,-8)),"History is bounded and retains curved world positions")
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	check(vertices[0].is_equal_approx(Vector3(-1.2,0,0)) and vertices[1].is_equal_approx(Vector3(1.2,0,0)),"World-X ribbon width matches source transform semantics")
	check(trail.material_override==lib.material(20002) and trail.tint==Color.hex(0x00ff0000),"Renderer reuses original material without losing zero-alpha additive green")
	var malformed:Dictionary=lib.content.projectile_trails.duplicate(true);malformed.styles.erase("4")
	check(not Trail.valid(malformed,lib),"Missing used trail style is rejected")
	malformed=lib.content.projectile_trails.duplicate(true);malformed.styles["4"].uv=[0,0,-1,1]
	check(not Trail.valid(malformed,lib),"Invalid trail atlas bounds are rejected")
	trail.queue_free();await process_frame
	var state:=Session.new();state.configure(lib,true);state.docked=false
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{"aim_assist":false},true);flight.set_physics_process(false)
	flight.fire_weapon(14)
	check(flight.projectile_trails.size()==7,"Actual Flight creates source trail for every multi-projectile muzzle")
	var snapshots:=[]
	for node in flight.projectile_trails.values():snapshots.append(node.points.duplicate())
	flight.sync_projectiles()
	check(flight.projectile_trails.values()[0].points==snapshots[0],"Rendering sync cannot advance simulation trail history")
	Combat.advance(state.combat,.02,[],lib,state.actor_weapons());flight.sync_projectiles(true)
	check(flight.projectile_trails.values().all(func(node):return node.visible),"Flight trail history advances with live simulated projectiles")
	flight.paused=true;var paused_points:PackedVector3Array=flight.projectile_trails.values()[0].points.duplicate();flight._physics_process(.1)
	check(flight.projectile_trails.values()[0].points==paused_points,"Pause freezes projectile trails along with simulation")
	state.combat=Combat.create();flight.sync_projectiles()
	check(flight.projectile_trails.is_empty(),"Removed projectiles release their trails")
	flight.queue_free();await process_frame


func check_trail_mode_boundaries(lib) -> void:
	var Arcade=preload("res://src/simulation/survival_session.gd")
	var arcade:=Arcade.new()
	check(arcade.configure_survival(lib,lib.content.survival,0,0,47),"Configure survival with registered trail declarations")
	check(arcade.actor_weapons()[3].trail.style==4 and arcade.actor_weapons()[3].trail.segments==100,"Survival missile retains source white trail and long history")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(arcade.capture()))
	var resumed:=Arcade.new();resumed.configure_survival(lib,lib.content.survival,0,0,1)
	check(resumed.restore(saved) and resumed.actor_weapons()[3].trail==arcade.actor_weapons()[3].trail,"Existing survival schema rebuilds derived trail profiles on restore")
	var state:=Session.new();state.configure(lib);state.market_seed=47;state.chapter=3
	check(state.begin_mission(),"Start source asteroid mission for additional-muzzle collision regression")
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{"aim_assist":false},true);flight.set_physics_process(false)
	var rock:Dictionary=state.active_job.scenery.rocks[0]
	var target:=Combat.vector(rock.position)
	# A real second missile muzzle hits the original field through Flight's swept
	# collision path. Inventory and native muzzle identities have different ranges.
	var weapon:int=state.player_weapon_ids(4)[1]
	var profile:Dictionary=state.actor_weapons()[weapon]
	state.combat={"next_id":1,"cooldowns":{},"projectiles":[{"id":0,"weapon":weapon,"position":Combat.packed(target+Vector3(0,0,1)),"velocity":[0,0,-float(profile.speed)],"remaining":profile.lifetime,"guidance":Combat.Guidance.create()}]}
	flight.advance_projectiles(1.0/float(profile.speed))
	check(rock.hits==0 and state.combat.projectiles.is_empty(),"Additional missile muzzle resolves catalogue category and destroys source asteroid without out-of-range indexing")
	flight.queue_free();await process_frame


func check_lens_flare(source: PackedByteArray, lib) -> void:
	var Flare=preload("res://src/presentation/lens_flare.gd")
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var data:=reader.lens_flare_presentation()
	check(reader.error.is_empty() and data.directions.size()==9 and data.images.size()==3 and data.elements.size()==7,"Read source sun directions and complete lens flare sprite declarations: "+reader.error)
	if data.is_empty():return
	check(data.strength_scale==64 and data.alpha_bias==70 and data.large_alpha_bias==40 and data.blend=="mix" and data.wash,"Read original glare strengths, wash and alpha blend")
	check(data.tints==[[200,200,255],[200,255,200],[255,200,200],[255,255,255]],"Read four source flare color themes")
	for index in data.directions.size():
		var model:String=lib.content.resources[str(int(lib.content.sky.sun_base)+index)].path.get_file().get_basename()
		var direction:=Combat.vector(data.directions[index]).normalized()
		check(direction.dot(lib.mesh(model).get_aabb().get_center().normalized())>.999,"Source flare direction aligns with supplied sun mesh: %d"%index)
	var factors:=[.5,.25,.75,.125,1.0/11.0,-.75,-.2]
	var scales:=[1.0,.75,.5,4.0/3.0,.5,2.0,.5]
	for index in data.elements.size():
		check(is_equal_approx(data.elements[index].position,factors[index]) and is_equal_approx(data.elements[index].size,scales[index]),"Read flare element position and relative sprite size: %d"%index)
	check(Flare.valid(lib.content.lens_flare,lib),"Validate imported flare sprite and sky associations")
	var center:=Flare.layout(data,Vector2(960,640),Vector2(480,320))
	check(center.sprites.size()==7 and is_equal_approx(center.wash,64.0/255.0),"Centered sun produces source glare wash and complete lens chain")
	var offset:=Flare.layout(data,Vector2(960,640),Vector2(720,320))
	check(offset.sprites[0].position==Vector2(600,320) and offset.sprites[5].position==Vector2(300,320),"Flare elements lie on opposite sides of viewport center with source factors")
	check(offset.wash<center.wash,"Glare diminishes as the sun moves away from the center")
	check(Flare.layout(data,Vector2(960,640),Vector2(10000,0)).sprites.is_empty(),"Distant offscreen sun cannot wrap negative brightness into bright artifacts")
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(0x2af92,2),0x2378);reader.bytes=changed
	check(reader.lens_flare_presentation().directions[0][1]==120,"Sun direction component is read from supplied constants")
	for address in [0x2af7c,0x2af94,0x2b068,0x6734e,0x67366,0x66fde,0x67052,0x670c6,0x67154,0x671d2,0x67234,0x672aa,0x672e2]:
		reader.bytes=source;reader.error="";changed=source.duplicate();changed.encode_u16(reader.file_offset(address,2),0xbf00);reader.bytes=changed
		check(reader.lens_flare_presentation().is_empty() and not reader.error.is_empty(),"Reject unsupported flare source consumer %x"%address)
	var invalid:Dictionary=lib.content.lens_flare.duplicate(true);invalid.images[0]={"texture":0,"region":99999}
	check(not Flare.valid(invalid,lib),"Missing original flare sprite is rejected")
	var world:=Node3D.new();root.add_child(world);var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var flare:=Flare.new();root.add_child(flare);flare.configure(lib,camera,{"variant":0,"style":0})
	camera.look_at(flare.direction);flare._process(0)
	check(flare.projected,"Sun ahead of camera is projected")
	var projected:=flare.sun_screen;camera.position=Vector3(200,-70,360);flare._process(0)
	check(flare.sun_screen.is_equal_approx(projected),"Camera translation cannot introduce sun parallax")
	camera.look_at(camera.position-flare.direction);flare._process(0)
	check(not flare.projected,"Sun behind camera cannot produce a lens flare")
	flare.queue_free();world.queue_free();await process_frame


func check_npc_rocket_trail(source: PackedByteArray, lib) -> void:
	var reader:=NativeData.new();reader.bytes=source;reader.parse_macho()
	var weapon:=reader.rocket_weapon(18)
	check(reader.error.is_empty() and weapon.get("trail",{})=={"style":3,"segments":100},"Heavy NPC rocket reads its own yellow trail style and long history: "+reader.error)
	if weapon.is_empty():return
	var definition:={"groups":[{"count":1,"team":"enemy","weapon":weapon}]}
	var profiles:Dictionary=lib.definition_weapons(definition,0)
	check(profiles[-1].trail==weapon.trail and profiles[-1].guidance_target_ids==[-1],"Encounter profiles preserve NPC trail without changing guidance targets")
	var changed:=source.duplicate();changed.encode_u16(reader.file_offset(0x2ee3c,2),0x2302);reader.bytes=changed
	check(reader.rocket_weapon(18).trail.style==2,"NPC trail style follows its source argument rather than player missile defaults")
	reader.bytes=source;reader.error="";changed=source.duplicate();changed.encode_u16(reader.file_offset(0x2ee3e,2),0xbf00);reader.bytes=changed
	check(reader.rocket_weapon(18).is_empty() and not reader.error.is_empty(),"Reject unsupported NPC trail argument consumer")
	var state:=Session.new();state.configure(lib,true);state.docked=false
	var flight:=Flight.new();root.add_child(flight);flight.setup(lib,state,{"aim_assist":false},true);flight.set_physics_process(false)
	# The same source weapon path is consumed by contract definitions in play.
	state._contract_definition=definition;state.active_job={"kind":"contract","rank":0,"actors":[{}]}
	Combat.fire(state.combat,-1,Vector3.ZERO,Vector3.FORWARD,lib,profiles);flight.sync_projectiles()
	check(flight.projectile_trails.size()==1 and flight.projectile_trails[0].tint==Color.hex(0xffff00ff),"Actual NPC projectile creates yellow original trail")
	flight.queue_free();await process_frame


func check_briefing_flares(lib) -> void:
	var Scene = preload("res://src/presentation/briefing_scene.gd")
	for chapter in range(1, lib.content.briefing_scene.chapters.size()):
		var node = Scene.new()
		root.add_child(node)
		check(node.configure(lib, chapter, 0), "Briefing flare scene configures %d" % chapter)
		if not node.supported:
			node.free()
			continue
		node.set_process(false)
		var flare = node.lens_flare
		check(flare.camera == node.camera and flare.images.size() == 3 and node.flare_layer.layer == 0,
			"Briefing owns source flare sprites below dialogue %d" % chapter)
		var sky: Dictionary = node.backdrop.declaration
		check(flare.direction.is_equal_approx(Combat.vector(lib.content.lens_flare.directions[int(sky.variant)]).normalized()),
			"Briefing sun direction follows its selected chapter/location sky %d" % chapter)
		node.camera.look_at(node.camera.global_position + flare.direction)
		flare._process(0)
		check(flare.projected and flare.sun_screen.distance_to(flare.size * .5) < 1,
			"Briefing sun projects through its own camera %d" % chapter)
		node.camera.position += Vector3(40, 20, 10)
		node._process(0)
		flare._process(0)
		check(node.backdrop.global_position.is_equal_approx(node.camera.global_position) and flare.sun_screen.distance_to(flare.size * .5) < 1,
			"Briefing backdrop and flare stay distant when camera moves %d" % chapter)
		node.hide()
		check(not node.flare_layer.visible and not flare.is_processing(), "Closing briefing hides its independent canvas %d" % chapter)
		node.show()
		check(node.flare_layer.visible and flare.is_processing(), "Showing briefing restores its flare %d" % chapter)
		var weak: WeakRef = weakref(flare)
		node.queue_free()
		await process_frame
		check(weak.get_ref() == null, "Briefing exit releases flare resources %d" % chapter)


func check_damage_feedback(source: PackedByteArray, lib) -> void:
	var Feedback = preload("res://src/presentation/damage_feedback.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.damage_presentation()
	check(
		data.durations_ms == [300, 300, 300, 300] and data.insets == [30, 30, 30, 30],
		"Original damage fade and edge margins"
	)
	check(
		data.masks == [1, 2, 24, 36] and data.front.center_flags == 51,
		"Original directional and center hit masks"
	)
	check(
		data.rear.limits == [-50000.0 / 65536, -15000.0 / 65536, 15000.0 / 65536, 50000.0 / 65536],
		"Rear direction thresholds use original normalized vector units"
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x278ac, 2), 0x2228)
	reader.bytes = changed
	check(
		reader.damage_presentation().insets[0] == 40,
		"Damage edge offset is read from supplied data"
	)
	for address in [0x26fb4, 0x277e4, 0x278b2, 0x54de4]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.damage_presentation().is_empty(),
			"Unknown damage source consumer rejected %x" % address
		)
	var invalid: Dictionary = data.duplicate(true)
	invalid.images[0].region = 99999
	check(not Feedback.valid(invalid, lib), "Missing original damage sprite rejected")
	invalid = data.duplicate(true)
	invalid.durations_ms[0] = 0
	check(not Feedback.valid(invalid, lib), "Invalid fade duration rejected")
	var feedback = Feedback.new()
	feedback.configure(lib)
	check(feedback.front_flags(Vector2.ZERO) == 51, "Centered incoming shot lights every edge")
	check(
		(
			feedback.front_flags(Vector2(-500, 0)) == 17
			and feedback.front_flags(Vector2(500, 0)) == 18
		),
		"Far lateral incoming shots include the correct side"
	)
	check(feedback.front_flags(Vector2(100, 0)) == 16, "Off-center forward shot retains front cue")
	var rear := [1, 33, 32, 34, 2]
	for index in 5:
		check(
			feedback.rear_flags([-1, -.5, 0, .5, 1][index]) == rear[index],
			"Rear attack sector %d" % index
		)
	var state := Session.new()
	state.configure(lib, true)
	state.docked = false
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, state, {"aim_assist": false}, true)
	flight.set_physics_process(false)
	flight.camera.rotation = Vector3.ZERO
	check(
		flight.damage_feedback.flags(flight.camera, Vector3.FORWARD) == 51,
		"Actual camera projects a center hit"
	)
	flight.camera.position += Vector3(150, 70, 90)
	check(
		flight.damage_feedback.flags(flight.camera, Vector3.FORWARD) == 51,
		"Camera position cannot change attack direction"
	)
	flight.camera.rotation.y = PI
	check(
		flight.damage_feedback.flags(flight.camera, Vector3.FORWARD) == 32,
		"Turning the camera changes front to rear feedback"
	)
	flight.camera.rotation = Vector3.ZERO
	var hull: float = state.hull
	var shield: float = state.shield
	flight.hit(1, Vector3.BACK)
	check(
		(
			is_equal_approx(hull + shield - state.hull - state.shield, 1)
			and flight.damage_feedback.remaining == PackedFloat32Array([0, 0, 0, 300])
		),
		"Actual damage triggers only the rear edge without changing damage accounting"
	)
	flight.damage_feedback.advance(150)
	flight.hit(1, Vector3.LEFT)
	check(
		flight.damage_feedback.remaining == PackedFloat32Array([300, 0, 0, 150]),
		"Different hit edges retain independent fade timers"
	)
	var remaining: PackedFloat32Array = flight.damage_feedback.remaining.duplicate()
	flight.paused = true
	flight.step(.05)
	check(
		flight.damage_feedback.remaining == remaining, "Pause freezes damage cues with simulation"
	)
	flight.hit(0)
	flight.hit(-1)
	check(
		flight.damage_feedback.remaining == remaining,
		"Zero/negative damage cannot trigger false cues"
	)
	flight.damage_feedback.advance(300)
	check(
		flight.damage_feedback.remaining == PackedFloat32Array([0, 0, 0, 0]),
		"Damage cues expire without alpha underflow"
	)
	var combat := Combat.create()
	var profile := {
		"damage": 3,
		"interval": .1,
		"speed": 100.0,
		"lifetime": 1.0,
		"team": "enemy",
		"pool_capacity": 1
	}
	check(
		Combat.fire(combat, -1, Vector3(0, 0, -10), Vector3.BACK, lib, {-1: profile}),
		"Incoming shot created"
	)
	var hits := Combat.advance(
		combat,
		.2,
		[{"id": -1, "team": "ally", "position": [0, 0, 0], "radius": 1}],
		lib,
		{-1: profile}
	)
	check(
		hits.size() == 1 and Combat.vector(hits[0].incoming) == Vector3.FORWARD,
		"Swept projectile impact retains direction toward attacker"
	)
	flight.queue_free()
	await process_frame


func check_exploration_interactions(lib) -> void:
	var Area = preload("res://src/simulation/exploration_area.gd")
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.depart()
	var initial := pilot.exploration_area()
	var definition := pilot.field_definition()
	var field: Dictionary = definition.scenery[0]
	check(
		initial.scenery.rocks.size() == field.count and pilot.active_job.is_empty(),
		"Exploration uses original field population without creating a campaign job"
	)
	check(
		Area.valid(lib, pilot.exploration),
		"Fresh persistent area validates against source geometry"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	check(
		(
			flight.field_rocks.size() == field.count
			and flight.ambience.get_child_count() == field.count
		),
		"Existing approach field is bound to live asteroid visuals"
	)
	var index := 0
	for candidate in range(1, initial.scenery.rocks.size()):
		if initial.scenery.rocks[candidate].position[0] < initial.scenery.rocks[index].position[0]:
			index = candidate
	var rock: Dictionary = initial.scenery.rocks[index]
	var point := Combat.vector(rock.position)
	var origin := point + Vector3.LEFT * (float(field.radius) + 1)
	var profile: Dictionary = pilot.actor_weapons().get(
		pilot.weapon_id, lib.weapon_ballistics(pilot.weapon_id)
	)
	for count in int(field.hits):
		pilot.combat.cooldowns.clear()
		check(
			Combat.fire(
				pilot.combat, pilot.weapon_id, origin, Vector3.RIGHT, lib, pilot.actor_weapons()
			),
			"Fire at original exploration rock %d" % count
		)
		flight.advance_projectiles((float(field.radius) + 2) / float(profile.speed))
	check(
		rock.hits == 0 and not flight.field_rocks[index].node.body.visible,
		"Actual flight shots destroy the selected source rock"
	)
	check(
		not flight.field_rocks[index].node.layers.is_empty(),
		"Original fragment/explosion models replace the destroyed body"
	)
	var hp: float = pilot.hull
	var sh: float = pilot.shield
	flight.ship.position = point
	flight.throttle = 0
	pilot.motion.speed = 0
	flight.step(.01)
	check(pilot.hull == hp and pilot.shield == sh, "Destroyed rock cannot deal contact damage")
	var alive_index := 0 if index != 0 else 1
	var alive: Dictionary = initial.scenery.rocks[alive_index]
	flight.ship.position = Combat.vector(alive.position)
	flight.throttle = 0
	initial.scenery.contact_cooldown = 0
	hp = pilot.hull + pilot.shield
	flight.step(.01)
	check(
		(
			alive.hits == 0
			and is_equal_approx(hp - pilot.hull - pilot.shield, float(field.contact_damage))
		),
		"Actual exploration contact destroys rock and applies imported damage"
	)
	check(initial.scenery.contact_cooldown > 0, "Exploration contact shares the imported cooldown")
	var saved := pilot.capture()
	var restored := Session.new()
	restored.configure(lib, true)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(saved))),
		"Damaged exploration area survives save/load: " + restored.error
	)
	check(
		(
			restored.field_state().rocks[index].hits == 0
			and restored.field_state().rocks[alive_index].hits == 0
		),
		"Both destroyed rocks remain gone after loading"
	)
	var second := Flight.new()
	root.add_child(second)
	second.setup(lib, restored, {}, true)
	second.set_physics_process(false)
	check(
		not second.field_rocks[index].node.body.visible,
		"Recreated Flight does not resurrect a destroyed mesh"
	)
	check(
		second.field_rocks[index].node.position.is_equal_approx(point),
		"Recreated field keeps original rock placement"
	)
	var ms: float = restored.field_state().rocks[index].destruction_ms
	second.paused = true
	second.step(.1)
	check(
		restored.field_state().rocks[index].destruction_ms == ms,
		"Pause freezes exploration destruction effects"
	)
	second.queue_free()
	flight.queue_free()
	await process_frame
	check(
		restored.arrive(restored.station_id) and restored.depart(),
		"Docking and departing keep exploration available"
	)
	check(restored.field_state().rocks[index].hits == 0, "Docking cannot reset destroyed asteroids")
	var sid := restored.station_id
	var next: int = (sid + 1) % lib.stations.size()
	check(restored.arrive(next) and restored.depart(), "Visit another source station")
	check(
		restored.field_state().rocks.all(func(v): return v.hits == field.hits),
		"A different station owns an independent field"
	)
	check(
		(
			restored.arrive(sid)
			and restored.depart()
			and restored.field_state().rocks[index].hits == 0
		),
		"Returning to a station restores its own cleared rocks"
	)
	var migrated := Session.new()
	migrated.configure(lib, true)
	var legacy := saved.duplicate(true)
	legacy.schema = 18
	legacy.erase("exploration")
	check(
		migrated.restore(legacy) and migrated.exploration.is_empty(),
		"Schema18 migrates without inventing previous asteroid damage"
	)
	check(
		migrated.field_state().rocks.size() == field.count,
		"Legacy free flight initializes source geometry lazily"
	)
	var before := restored.capture()
	var malformed := before.duplicate(true)
	malformed.exploration[str(sid)].scenery.rocks[0].position[0] += 10
	check(not restored.restore(malformed), "Moved source geometry is rejected on restore")
	check(same_saved_value(restored.capture(), before), "Failed field restore is atomic")
	malformed = before.duplicate(true)
	malformed.exploration[str(sid)].scenery.rocks[0].hits = -1
	check(not restored.restore(malformed), "Invalid saved rock durability is rejected")
	var campaign := Session.new()
	campaign.configure(lib)
	check(
		campaign.exploration_area().is_empty(),
		"Linear campaign cannot initialize exploration fields early"
	)


func check_exploration_save_scope(lib) -> void:
	var arcade = preload("res://src/simulation/survival_session.gd").new()
	check(arcade.configure_survival(lib, lib.content.survival, 0, 0, 9), "Configure survival field scope")
	check(arcade.field_state().get("rocks", []).is_empty() and arcade.exploration.is_empty(), "Survival owns no exploration rocks")
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.depart()
	pilot.exploration_area()
	var snapshot := pilot.capture()
	var restored := Session.new()
	restored.configure(lib, true)
	check(restored.restore(snapshot), "Schema19 accepts visited exploration state")
	var other: int = (pilot.station_id + 1) % lib.stations.size()
	snapshot.exploration[str(other)] = pilot.ExplorationArea.create(lib, other)
	check(not restored.restore(snapshot), "Unvisited exploration area is rejected")
	var locked := Session.new()
	locked.configure(lib)
	var invalid := locked.capture()
	invalid.exploration = pilot.exploration
	check(not locked.restore(invalid), "Active campaign cannot claim exploration state")


func check_player_hit_effects(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data: Dictionary = lib.content.player_hit
	check(
		data.models.hull == 10028 and data.models.shield == 10029,
		"Original hull and shield flash mesh associations"
	)
	check(
		data.visual_shield_above == 10 and data.sound_shield_above == 0,
		"Visual and audio shield thresholds are distinct"
	)
	check(
		same_saved_value(data.sounds.hull, [11, 12]) and same_saved_value(data.sounds.shield, [28, 29]),
		"Original randomized hit sound groups"
	)
	check(
		(
			lib.content.sound_bank.size() == 32
			and is_equal_approx(lib.content.sound_bank["11"].gain, .18)
			and is_equal_approx(lib.content.sound_bank["28"].gain, .4)
		),
		"Original sound registry and relative gains"
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x54d82, 2), 0x2809)
	reader.bytes = changed
	check(
		reader.player_hit_presentation().visual_shield_above == 9,
		"Visual threshold follows source data"
	)
	for address in [0x54318, 0x54d60, 0x54120]:
		reader.bytes = source
		reader.error = ""
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		check(
			reader.player_hit_presentation().is_empty(),
			"Unknown hit consumer rejected %x" % address
		)
	reader.bytes = source
	reader.error = ""
	var table := reader.literal(0x25acc, 1)
	changed = source.duplicate()
	changed.encode_u32(reader.file_offset(table + 11 * 12 + 8, 4), 25)
	reader.bytes = changed
	check(
		is_equal_approx(reader.sound_bank()["11"].gain, .25),
		"Supplied sound gain controls native volume"
	)
	var Hit = preload("res://src/presentation/player_hit.gd")
	var node = Hit.new()
	root.add_child(node)
	node.configure(lib)
	node.set_process(false)
	var pose := Transform3D(Basis.from_euler(Vector3(.1, .2, .3)), Vector3(40, 20, 10))
	node.flash(11, pose)
	check(
		(
			node.meshes.shield.visible
			and not node.meshes.hull.visible
			and node.global_transform.is_equal_approx(pose)
		),
		"Shield hit uses the original mesh at the ship pose"
	)
	node.flush_sound()
	check(
		(
			node.last_sound in [28, 29]
			and node.audio.stream != null
			and is_equal_approx(node.audio.volume_linear, .4)
		),
		"Shield hit resolves original audio and gain"
	)
	node.flash(10, pose)
	node.flush_sound()
	check(
		node.meshes.hull.visible and node.last_sound in [28, 29],
		"Low shield uses hull flash while retaining shield sound"
	)
	node.flash(0, pose)
	node.flush_sound()
	check(
		(
			node.meshes.hull.visible
			and not node.meshes.shield.visible
			and node.last_sound in [11, 12]
			and is_equal_approx(node.audio.volume_linear, .18)
		),
		"Depleted shield selects hull impact sound"
	)
	var clip: AudioStream = node.audio.stream
	var selected: int = node.last_sound
	node.flush_sound()
	check(
		node.last_sound == selected and node.audio.stream == clip,
		"Rendering without another hit cannot replay impact audio"
	)
	check(
		lib.sound_clip(selected) == clip and lib.sound_clip(-1) == null,
		"Sound stream cache reuses valid IDs and rejects absent ones"
	)
	node.begin_step()
	check(
		not node.meshes.hull.visible and not node.meshes.shield.visible,
		"Hit mesh clears on next simulation step"
	)
	var state := Session.new()
	state.configure(lib, true)
	state.depart()
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, state, {}, true)
	flight.set_physics_process(false)
	flight.ship.hide()
	flight.hit(1)
	check(
		flight.player_hit.meshes.hull.is_visible_in_tree(),
		"Actual hull damage flashes even when first-person hides the ship"
	)
	flight.player_hit.flush_sound()
	check(
		flight.player_hit.last_sound in [11, 12], "Actual Flight damage triggers source hull audio"
	)
	flight.paused = true
	flight.step(.02)
	check(flight.player_hit.meshes.hull.visible, "Paused simulation retains current impact frame")
	flight.paused = false
	flight.ship.position = Vector3(10000, 10000, 10000)
	flight.throttle = 0
	flight.step(.01)
	check(not flight.player_hit.meshes.hull.visible, "Actual flight clears impact at next update")
	node.queue_free()
	flight.queue_free()
	await process_frame


func check_asteroid_audio(source: PackedByteArray, lib) -> void:
	var Visual = preload("res://src/presentation/asteroid_visual.gd")
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var field: Dictionary = lib.content.briefing_scene.field
	var data: Dictionary = field.destruction
	check(
		data.audio.sound == 10 and data.audio.delay_ms == data.effect.layers[0].delay_ms,
		"Asteroid sound is bound to its source first explosion layer"
	)
	var changed = source.duplicate()
	changed.encode_u16(reader.file_offset(0x66d4e, 2), 0x2109)
	reader.bytes = changed
	check(
		reader.asteroid_destruction().audio.sound == 9, "Asteroid audio ID comes from supplied data"
	)
	for address in [0x66d1a, 0x66d48, 0x66da0, 0x54d82, 0x54d44]:
		reader.bytes = source
		reader.error = ""
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		var result = (
			reader.asteroid_destruction() if address > 0x60000 else reader.player_hit_presentation()
		)
		check(
			not reader.error.is_empty(),
			"Unsupported audio/threshold consumer is rejected %x" % address
		)
	check(
		Visual.valid_audio(data, lib.content.sound_bank),
		"Installed asteroid sound reference validates"
	)
	var invalid = data.duplicate(true)
	invalid.audio.sound = -1
	check(
		not Visual.valid_audio(invalid, lib.content.sound_bank),
		"Unknown destruction sound is rejected"
	)
	invalid = data.duplicate(true)
	invalid.audio.delay_ms += 1
	check(
		not Visual.valid_audio(invalid, lib.content.sound_bank),
		"Destruction cue must stay bound to its layer delay"
	)
	var state = {
		"hits": 1, "scale": 1.0, "rotation": [0, 0, 0], "destruction_ms": 0.0, "destroyed": false
	}
	var visual = Visual.new()
	root.add_child(visual)
	visual.configure(lib, field, state)
	check(visual.audio == null, "Intact rocks allocate no sound player")
	state.hits = 0
	state.destruction_ms = data.audio.delay_ms - 1
	visual.sync(state)
	check(visual.audio == null, "Asteroid sound waits for the imported stage delay")
	var future = Visual.new()
	root.add_child(future)
	future.configure(lib, field, state)
	check(future.audio == null and future.sound_due, "Loading before the cue preserves its future playback")
	state.destruction_ms = data.audio.delay_ms
	future.sync(state)
	check(future.audio != null, "Restored future cue starts at the layer boundary")
	visual.sync(state)
	var player: AudioStreamPlayer = visual.audio
	check(
		(
			player != null
			and player.stream == lib.sound_clip(int(data.audio.sound))
			and is_equal_approx(
				player.volume_linear, lib.content.sound_bank[str(int(data.audio.sound))].gain
			)
		),
		"Asteroid breakup uses original audio stream and source gain"
	)
	visual.sync(state)
	check(
		visual.audio == player and not visual.sound_due,
		"Repeated sync does not replay asteroid sound"
	)
	var restored = Visual.new()
	root.add_child(restored)
	restored.configure(lib, field, state)
	check(
		restored.audio == null and not restored.sound_due,
		"Loading an active breakup does not replay old destruction audio"
	)
	var skipped = Visual.new()
	root.add_child(skipped)
	state.hits = 1
	skipped.configure(lib, field, state)
	state.hits = 0
	state.destroyed = true
	state.destruction_ms = 0
	skipped.sync(state)
	check(
		skipped.audio != null,
		"A simulation step beyond the complete effect still emits its one cue"
	)
	var pilot = Session.new()
	pilot.configure(lib, true)
	pilot.depart()
	var flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	var scenery = pilot.field_state()
	pilot.Mission.Scenery.hit(scenery, 0, true)
	pilot.Mission.Scenery.advance(
		pilot.field_definition(), scenery, (float(data.audio.delay_ms) + 1) / 1000.0
	)
	flight.sync_fields()
	check(
		flight.field_rocks[0].node.audio != null,
		"Actual exploration destruction reaches source audio presentation"
	)
	for node in [visual, restored, skipped, future, flight]:
		node.queue_free()
	await process_frame


func check_actor_destruction(source: PackedByteArray, lib) -> void:
	var Visual = preload("res://src/presentation/explosion.gd")
	var data: Dictionary = lib.content.actor_destruction
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		(
			data.effects["2"].layers.size() == 12
			and data.effects["3"].layers.size() == 18
			and data.effects["4"].layers.size() == 3
		),
		"Small, large and debris explosions use all source layers"
	)
	check(
		(
			data.actors[0] == 2
			and data.actors[2] == 3
			and data.actors[7] == 0
			and data.actors[8] == 0
			and data.actors[9] == 4
		),
		"Actor families select distinct source explosion types"
	)
	check(
		data.effects["2"].hide_body_ms == 750 and data.effects["3"].hide_body_ms == 3500,
		"Source ship hull visibility timing"
	)
	check(
		same_saved_value(data.effects["3"].sounds.map(func(c): return c.layer), [0, 3, 6, 8, 10, 12, 14]),
		"Large ship sounds retain source stage associations in timeline order"
	)
	for address in [0x686f8, 0x65b18, 0x66314, 0x66d74]:
		reader.bytes = source
		reader.error = ""
		var changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.actor_destruction(lib.content.resources, data.actors.size())
		check(not reader.error.is_empty(), "Reject unsupported destruction consumer %x" % address)
	reader.bytes = source
	reader.error = ""
	var changed = source.duplicate()
	changed.encode_u16(reader.file_offset(0x6602a, 2), 0x223c)
	reader.bytes = changed
	var variant = reader.actor_destruction(lib.content.resources, data.actors.size())
	check(
		is_equal_approx(variant.effects["2"].layers[1].duration_ms, 1500),
		"Layer duration changes with supplied constructor rate"
	)
	reader.bytes = source
	reader.error = ""
	changed = source.duplicate()
	changed.encode_u16(reader.file_offset(0x66d86, 2), 0x2109)
	reader.bytes = changed
	variant = reader.actor_destruction(lib.content.resources, data.actors.size())
	check(
		(
			variant
			. effects["3"]
			. sounds
			. filter(func(c): return c.layer in [3, 8, 14])
			. all(func(c): return c.sound == 9)
		),
		"Staged audio follows original sound ID binding"
	)
	reader.bytes = source
	reader.error = ""
	changed = source.duplicate()
	var mask_address = ((0x686b0 + 4) & ~3) + (reader.u16(0x686b0) & 255) * 4
	var mask = reader.literal(0x686b0, 3)
	changed.encode_u32(reader.file_offset(mask_address, 4), mask & ~4)
	reader.bytes = changed
	variant = reader.actor_destruction(lib.content.resources, data.actors.size())
	check(variant.actors[2] == 2, "Actor selection follows supplied family mask")
	check(Visual.valid(data, lib), "All imported destruction definitions validate")
	for key in ["hide_body_ms", "fade_duration_ms", "sound", "rotation_steps"]:
		var invalid = data.duplicate(true)
		match key:
			"hide_body_ms":
				invalid.effects["2"][key] = -1
			"fade_duration_ms":
				invalid.effects["3"].layers[0][key] = 0
			"sound":
				invalid.effects["2"].sounds[0][key] = 9999
			"rotation_steps":
				invalid.effects["4"].layers[1][key] = 0
		check(not Visual.valid(invalid, lib), "Invalid destruction declaration is rejected: " + key)
	var pose = Transform3D(Basis.from_euler(Vector3(.1, .7, 0)), Vector3(50, 60, 70))
	for kind in [0, 2, 3, 4]:
		var node = Visual.new()
		root.add_child(node)
		node.configure(lib, kind, pose, 42)
		var body = Node3D.new()
		root.add_child(body)
		body.global_transform = pose
		node.attach_body(body)
		check(
			(
				node.layers.size() == data.effects[str(kind)].layers.size()
				and body.global_transform.is_equal_approx(pose)
			),
			"Attach all layers and retain the actual hull pose " + str(kind)
		)
		var own_materials := true
		for mesh in node.layers:
			own_materials = own_materials and mesh.material_override == null and mesh.get_active_material(0) == mesh.get_surface_override_material(0)
		check(own_materials, "Per-instance fade material takes precedence " + str(kind))
		var first = node.layers[0]
		check(
			first.global_position.is_equal_approx(
				pose.origin + Combat.vector(node.definition.layers[0].offset)
			),
			"Explosion offsets stay in source world axes " + str(kind)
		)
		node.advance(float(node.definition.hide_body_ms) / 1000.0)
		check(body.visible, "Hull remains through its source hide boundary " + str(kind))
		node.advance(.001)
		check(not body.visible, "Hull hides after its source boundary " + str(kind))
		node.advance(12)
		check(
			node.finished and node.played.size() == node.definition.sounds.size(),
			"All layers and cues finish once " + str(kind)
		)
		var count = node.sounds.size()
		node.advance(1)
		node.sync()
		check(node.sounds.size() == count, "Finished effect cannot replay audio " + str(kind))
		node.queue_free()
	var heavy = Visual.new()
	root.add_child(heavy)
	heavy.configure(lib, 3, Transform3D.IDENTITY, 42)
	heavy.advance(.5)
	check(
		is_equal_approx(
			heavy.layers[0].get_active_material(0).get_shader_parameter("effect_brightness"), 1.0
		),
		"Heavy burst grows before its imported fade starts"
	)
	heavy.advance(.75)
	check(
		heavy.layers[0].get_active_material(0).get_shader_parameter("effect_brightness") < 1,
		"Heavy burst fades on its separate timeline"
	)
	var a = Visual.new()
	root.add_child(a)
	a.configure(lib, 4, Transform3D.IDENTITY, 42)
	var b = Visual.new()
	root.add_child(b)
	b.configure(lib, 4, Transform3D.IDENTITY, 42)
	check(
		(
			a.layers[1].rotation.is_equal_approx(b.layers[1].rotation)
			and is_equal_approx(a.appearances[1].scale, b.appearances[1].scale)
		),
		"Debris variation is reproducible without combat RNG"
	)
	check(
		(
			a.appearances[1].scale >= data.effects["4"].layers[1].scale
			and (
				a.appearances[1].scale
				< data.effects["4"].layers[1].scale + data.effects["4"].layers[1].scale_span
			)
		),
		"Debris sizes stay in supplied random range"
	)
	# Actual mission actor removal owns the wreck; repeated sync must not duplicate it.
	var pilot = Session.new()
	pilot.configure(lib)
	pilot.depart()
	var flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	var victim: Dictionary = flight.actors[0]
	var victim_node: Node3D = victim.node
	victim.state.awake = true
	check(pilot.damage_actor(int(victim.index),float(victim.state.hp)),"Visual fixture starts native actor destruction")
	flight.spawn_targets()
	check(
		flight.explosions.size() == 1 and victim_node.get_parent() == flight.explosions[0],
		"Actual campaign death transfers the existing hull to its source explosion"
	)
	flight.spawn_targets()
	check(flight.explosions.size() == 1, "Actor synchronization does not replay a destruction")
	flight.paused = true
	flight.step(.1)
	check(flight.explosions[0].elapsed_ms == 0, "Pause freezes the actor destruction timeline")
	flight.paused = false
	pilot.advance_mission(12)
	flight.advance_explosions(12)
	# Source sound tails outlive an accelerated simulation frame. Retirement must
	# wait for actual audio completion as well as the simulation-owned clock.
	var sound_tail := 0.0
	for effect in flight.explosions:
		for player in effect.sounds:
			if player.playing: sound_tail = maxf(sound_tail,player.stream.get_length())
	if sound_tail>0:await create_timer(sound_tail+.05).timeout
	flight.advance_explosions(0)
	check(flight.explosions.is_empty(), "Finished actor destruction releases its scene")
	# Shared older effect renderers also need active per-instance materials.
	var Mine = preload("res://src/presentation/mine_visual.gd")
	var mine = Mine.new()
	root.add_child(mine)
	mine.configure(lib, {"phase": "shot", "elapsed_ms": 500.0})
	check(
		(
			mine.layers[0].material_override == null
			and (
				mine.layers[0].get_active_material(0)
				== mine.layers[0].get_surface_override_material(0)
			)
		),
		"Mine fade is not masked by a global material override"
	)
	var Rock = preload("res://src/presentation/asteroid_visual.gd")
	var rock = Rock.new()
	root.add_child(rock)
	rock.configure(
		lib,
		lib.content.briefing_scene.field,
		{
			"hits": 0,
			"destroyed": false,
			"destruction_ms": 500.0,
			"scale": 1.0,
			"rotation": [0, 0, 0]
		}
	)
	check(
		(
			rock.layers[0].material_override == null
			and (
				rock.layers[0].get_active_material(0)
				== rock.layers[0].get_surface_override_material(0)
			)
		),
		"Asteroid fade is not masked by a global material override"
	)
	for node in [heavy, a, b, flight, mine, rock]:
		node.queue_free()
	await process_frame


func check_actor_destruction_projectile(lib) -> void:
	var pilot = Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.depart()
	var flight = Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	flight.ship.position = Combat.vector(pilot.active_job.actors[0].position) + Vector3(0, 0, 300)
	flight.throttle = 0
	flight.step(.05)
	var target: Dictionary = {}
	for candidate in flight.actors:
		if pilot.Mission.enemy(pilot.mission_definition(), candidate.state) and pilot.Mission.actor_active(pilot.mission_definition(), pilot.active_job, candidate.state):
			target = candidate
			break
	check(not target.is_empty(), "Choose an active enemy for the projectile integration check")
	if target.is_empty():
		flight.queue_free()
		await process_frame
		return
	target.state.hp = 1
	var profile: Dictionary = pilot.Combat.profile(pilot.weapon_id, lib, pilot.actor_weapons())
	check(
		pilot.Combat.launch(
			pilot.combat,
			pilot.weapon_id,
			target.node.position,
			Vector3.FORWARD,
			profile,
			lib,
			pilot.actor_weapons()
		),
		"Launch native projectile for destruction integration"
	)
	flight.advance_projectiles(.01, flight.ship.position)
	check(
		flight.explosions.size() == 1 and not flight.actors.has(target),
		"Real projectile kill starts imported explosion and removes combat target"
	)
	check(
		(
			not flight.explosions.is_empty()
			and flight.explosions[0].body == target.node
			and not target.node.is_queued_for_deletion()
		),
		"Projectile kill transfers hull ownership without prematurely freeing it"
	)
	flight.queue_free()
	await process_frame


func check_mine_audio(source: PackedByteArray, lib) -> void:
	var Visual = preload("res://src/presentation/mine_visual.gd")
	var Mines = Session.Mission.Mines
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var parameters: Dictionary = lib.content.mine_behavior
	check(
		parameters.arm_sound == 31 and parameters.shot_sound == 8,
		"Mine lifecycle uses original arming and shot sounds"
	)
	check(
		same_saved_value(parameters.explosion.sounds, [{"layer": 0, "sound": 10, "delay_ms": 0}]),
		"Mine factory handler supplies its own explosion cue"
	)
	for pair in [[0x573b0, 0x210a, "arm_sound"], [0x577de, 0x2109, "shot_sound"]]:
		var changed = source.duplicate()
		changed.encode_u16(reader.file_offset(pair[0], 2), pair[1])
		reader.bytes = changed
		reader.error = ""
		check(
			reader.mine_behavior(lib.content.resources).get(pair[2]) == (pair[1] & 255),
			"Mine audio follows supplied constant " + str(pair[2])
		)
	for address in [0x573b6, 0x57808, 0x578e0]:
		var changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		reader.mine_behavior(lib.content.resources)
		check(
			not reader.error.is_empty(), "Unsupported mine audio lifecycle is rejected %x" % address
		)
	check(
		Visual.valid_audio(parameters, lib.content.sound_bank), "Mine audio declarations validate"
	)
	for key in ["arm_sound", "shot_sound"]:
		var invalid = parameters.duplicate(true)
		invalid[key] = 9999
		check(
			not Visual.valid_audio(invalid, lib.content.sound_bank),
			"Reject absent mine sound " + key
		)
	var invalid = parameters.duplicate(true)
	invalid.explosion.sounds[0].delay_ms += 1
	check(
		not Visual.valid_audio(invalid, lib.content.sound_bank),
		"Reject mine cue detached from its explosion layer"
	)
	invalid = parameters.duplicate(true)
	invalid.explosion.sounds.append(invalid.explosion.sounds[0].duplicate())
	check(
		not Visual.valid_audio(invalid, lib.content.sound_bank), "Reject duplicate mine layer cues"
	)
	var heard := []
	var mine: Dictionary = Mines.create()
	var visual = Visual.new()
	root.add_child(visual)
	visual.sound_requested.connect(func(id): heard.append(id))
	visual.configure(lib, mine)
	check(heard.is_empty(), "Dormant mines stay silent")
	var event: Dictionary = Mines.advance(
		mine, parameters, .1, Vector3.ZERO, [{"id": -1, "position": Vector3.ZERO, "active": true}]
	)
	visual.sync(mine, event)
	visual.sync(mine, event)
	check(heard == [31], "Arming beep plays once even if the event is synchronized again")
	Mines.begin_explosion(mine, true)
	visual.sync(mine)
	visual.sync(mine)
	check(heard == [31, 8, 10], "Shooting an armed mine emits direct hit and handler sounds once")
	var restored = Visual.new()
	root.add_child(restored)
	var resumed := []
	restored.sound_requested.connect(func(id): resumed.append(id))
	restored.configure(lib, mine)
	check(
		resumed.is_empty(), "Restoring an explosion at zero time does not replay its start sounds"
	)
	Mines.advance(mine, parameters, 100, Vector3.ZERO, [])
	visual.sync(mine)
	restored.sync(mine)
	check(
		heard == [31, 8, 10] and resumed.is_empty(), "Finishing a mine cannot replay an elapsed cue"
	)
	visual.queue_free()
	restored.queue_free()
	await process_frame
	mine = Mines.create()
	visual = Visual.new()
	root.add_child(visual)
	heard.clear()
	visual.sound_requested.connect(func(id): heard.append(id))
	visual.configure(lib, mine)
	event = Mines.advance(
		mine,
		parameters,
		parameters.fuse_ms / 1000.0 + .01,
		Vector3.ZERO,
		[{"id": -1, "position": Vector3.ZERO, "active": true}]
	)
	visual.sync(mine, event)
	check(
		heard == [31, 10],
		"A large step retains both arm and proximity-burst cues, without the shot sound"
	)
	visual.queue_free()
	await process_frame
	# A compatible source may put the handler sound on a later layer.
	var original: Dictionary = lib.content.mine_behavior
	lib.content.mine_behavior = parameters.duplicate(true)
	lib.content.mine_behavior.explosion.layers[0].delay_ms = 100
	lib.content.mine_behavior.explosion.sounds[0].delay_ms = 100
	mine = {"phase": "shot", "elapsed_ms": 50.0, "blast_delta": [0, 0, 0]}
	visual = Visual.new()
	root.add_child(visual)
	heard.clear()
	visual.sound_requested.connect(func(id): heard.append(id))
	visual.configure(lib, mine)
	check(heard.is_empty(), "Restoring before a future cue is silent")
	mine.phase = "dead"
	mine.elapsed_ms = 0
	visual.sync(mine)
	check(heard == [10], "Crossing the whole effect still emits a restored future cue")
	visual.queue_free()
	await process_frame
	lib.content.mine_behavior = original
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 11
	pilot.progression = Session.Progression.create(11)
	pilot.station_id = lib.chapter_destination(10)
	check(pilot.depart(), "Start campaign minefield for live audio dispatch")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	flight.throttle = 0
	flight.ship.position = Combat.vector(pilot.active_job.actors[0].position)
	var mine_node: Node3D
	for actor in flight.actors:
		if actor.index == 0:
			mine_node = actor.node
	var live := []
	mine_node.get_child(0).sound_requested.connect(func(id): live.append(id))
	flight.step(.01)
	check(live == [31], "Actual Flight forwards the mine arming event")
	flight.paused = true
	flight.step(5)
	check(live == [31], "Paused Flight emits no mine lifecycle sounds")
	flight.paused = false
	pilot.damage_actor(0, pilot.active_job.actors[0].hp)
	flight.step(.01)
	check(live == [31, 8, 10], "Actual Flight synchronizes a mine shot by another simulation actor")
	var tails := []
	for node in flight.get_children():
		if node is AudioStreamPlayer and node.stream in [lib.sound_clip(31), lib.sound_clip(8), lib.sound_clip(10)]:
			tails.append(node)
	check(tails.size() >= 3, "Flight owns mine sound tails, including any neighboring mines armed by source proximity")
	for player in tails:
		check(
			player.stream != null and player.get_parent() == flight,
			"Mine sound uses a decoded supplied stream owned by Flight"
		)
	mine_node.queue_free()
	await process_frame
	flight.queue_free()
	await process_frame


func check_player_destruction(source: PackedByteArray, lib) -> void:
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		reader.player_death_camera() == [20.0, 20.0, 160.0],
		"Death camera offset is read in native coordinates"
	)
	var changed = source.duplicate()
	changed.encode_u16(reader.file_offset(0x44814, 2), 0x23c8)
	reader.bytes = changed
	check(
		reader.player_death_camera() == [16.0, 16.0, 160.0],
		"Death camera follows supplied offset rather than a baked pose"
	)
	for address in [0x53fe6, 0x53fee, 0x4483a, 0x44850, 0x44818]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			reader.player_death_camera().is_empty() and not reader.error.is_empty(),
			"Reject unsupported player death consumer %x" % address
		)
	var invalid = lib.content.actor_destruction.duplicate(true)
	invalid.player_camera_offset = [0, 0, 0]
	check(
		not preload("res://src/presentation/explosion.gd").valid(invalid, lib),
		"Reject degenerate death camera"
	)
	for survival in [false, true]:
		var pilot
		if survival:
			pilot = preload("res://src/simulation/survival_session.gd").new()
			check(
				pilot.configure_survival(lib, lib.content.survival, 0, 0, 451),
				"Configure survival death fixture"
			)
		else:
			pilot = Session.new()
			pilot.configure(lib, true)
			check(pilot.depart(), "Enter exploration for player death fixture")
		var flight := Flight.new()
		root.add_child(flight)
		flight.setup(lib, pilot, {}, true)
		flight.set_physics_process(false)
		flight.first_person = true
		flight.ship.hide()
		flight.ship.rotation = Vector3(.2, .5, .1)
		var pose := flight.player_hull.global_transform
		var death_camera: Vector3 = (
			flight.camera.global_transform
			* Combat.vector(lib.content.actor_destruction.player_camera_offset)
		)
		var defeats := []
		flight.defeated.connect(func(): defeats.append(true))
		flight.hit(pilot.hull + pilot.shield + 1)
		check(
			defeats.size() == 1 and flight.paused and pilot.hull == 0,
			"Defeat notification stays immediate and stops combat"
		)
		check(
			flight.explosions.size() == 1 and flight.player_destroyed,
			"Player destruction starts once"
		)
		var effect = flight.explosions[0]
		check(
			(
				effect.definition
				== lib.content.actor_destruction.effects[str(
					int(lib.content.actor_destruction.player)
				)]
			),
			"Player uses its own supplied effect binding"
		)
		check(
			(
				effect.body == flight.player_hull
				and effect.body.is_visible_in_tree()
				and effect.body.global_transform.is_equal_approx(pose)
			),
			"First-person death retains the actual visible hull and world pose"
		)
		check(
			flight.camera.global_position.is_equal_approx(death_camera),
			"Death camera offset follows the actual camera basis"
		)
		var before: Dictionary = pilot.capture().duplicate(true)
		flight.hit(100)
		flight.step(.1)
		check(
			defeats.size() == 1 and effect.elapsed_ms == 0,
			"Repeated damage and paused combat cannot restart or advance death"
		)
		flight.advance_defeat_presentation(float(effect.definition.hide_body_ms) / 1000.0)
		check(effect.body.visible, "Player hull remains through the imported hide threshold")
		flight.advance_defeat_presentation(.001)
		check(not effect.body.visible, "Player hull disappears after the imported threshold")
		check(
			same_saved_value(before, pilot.capture()),
			"Defeat animation does not advance gameplay, survival score or save state"
		)
		check(
			not flight.player_hit.meshes.hull.visible,
			"Lethal hit flash ends while the explosion continues"
		)
		flight.advance_defeat_presentation(100)
		check(
			flight.explosions.is_empty(),
			"Finished headless death effect releases its hull and sound nodes"
		)
		flight.queue_free()
		await process_frame
	# Exercise the actual result-screen update owner without starting an import.
	var directory := "user://player-death-main/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(directory)
	var app := SurvivalMainHarness.new()
	app.library = lib
	app.ready_content = true
	app.test_directory = directory
	root.add_child(app)
	app.session = Session.new()
	app.session.configure(lib, true)
	app.session.depart()
	app.launch(true)
	app.flight.set_physics_process(false)
	app.flight.hit(app.session.hull + app.session.shield + 1)
	check(app.screen == "defeat", "Lethal hit opens the actual defeat panel immediately")
	var active_effect = app.flight.explosions[0]
	app._process(.1)
	check(
		active_effect.elapsed_ms == 100,
		"Defeat screen advances its background explosion despite paused combat"
	)
	app.screen = "pause"
	app._process(.1)
	check(active_effect.elapsed_ms == 100, "An ordinary pause does not advance death presentation")
	app.screen = "defeat"
	app.stop_flight()
	app.queue_free()
	await process_frame


func check_destruction_lifecycle(source: PackedByteArray, lib) -> void:
	var Life = Session.Mission.Destruction
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		reader.valid_destruction_lifecycle(),
		"Source distinguishes radio HP from completed wreck consumers"
	)
	for address in [0x50d3c, 0x3ab0e, 0x29860, 0x59816, 0x684b4]:
		var changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.bytes = changed
		reader.error = ""
		check(
			not reader.valid_destruction_lifecycle() and not reader.error.is_empty(),
			"Reject changed death semantics %x" % address
		)
	for kind in ["0", "2", "3", "4"]:
		var data: Dictionary = lib.content.actor_destruction.effects[kind]
		var actor := {"hp": 1.0, "destruction": Life.create()}
		actor.hp = 0.0
		Life.begin(actor)
		check(
			not Life.actor_dead(actor) and Life.valid(actor.destruction, 0, data),
			"HP zero begins a valid unfinished family " + kind
		)
		Life.advance(actor.destruction, data, .1)
		check(actor.destruction.phase == "dying", "Short step preserves unfinished family " + kind)
		var before: Dictionary = actor.destruction.duplicate(true)
		Life.advance(actor.destruction, data, 0)
		Life.advance(actor.destruction, data, -1)
		Life.advance(actor.destruction, data, NAN)
		check(actor.destruction == before, "Invalid time cannot change wreck phase " + kind)
		Life.advance(actor.destruction, data, Life.span(data) / 1000.0)
		check(
			Life.actor_dead(actor) and Life.valid(actor.destruction, 0, data),
			"All source layers must finish family " + kind
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Enter actual campaign encounter for saved wreck test")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	flight.throttle = 0
	flight.ship.position = Combat.vector(pilot.active_job.actors[0].position) + Vector3(0, 0, 300)
	flight.step(.05)
	var target := {}
	for actor in flight.actors:
		if flight.hostile(actor):
			target = actor
			break
	check(not target.is_empty(), "Source proximity activates a real enemy")
	if target.is_empty():
		flight.queue_free()
		await process_frame
		return
	var index := int(target.index)
	var definition: Dictionary = pilot.mission_definition()
	var enemy_index := 0
	for number in index:
		if Session.Mission.enemy(definition, pilot.active_job.actors[number]):
			enemy_index += 1
	var hull: Node3D = target.node
	var kills: int = pilot.active_job.kills
	target.state.hp = 1.0
	var profile: Dictionary = Combat.profile(pilot.weapon_id, lib, pilot.actor_weapons())
	Combat.launch(
		pilot.combat,
		pilot.weapon_id,
		target.node.position,
		Vector3.FORWARD,
		profile,
		lib,
		pilot.actor_weapons()
	)
	flight.advance_projectiles(.001)
	check(
		pilot.active_job.kills == kills + 1 and target.state.hp == 0,
		"Native projectile awards the kill at HP zero"
	)
	check(
		(
			not flight.actors.has(target)
			and not Session.Mission.actor_active(definition, pilot.active_job, target.state)
		),
		"Dying wreck is excluded from combat immediately"
	)
	check(
		not Session.Mission.achieved(
			{"kind": "enemy_destroyed", "index": enemy_index}, definition, pilot.active_job
		),
		"Specific-target objective waits for its wreck"
	)
	check(
		Session.Mission.Radio.triggered(
			{"condition": "enemy_range_destroyed", "value": enemy_index, "count": 1},
			definition,
			pilot.active_job
		),
		"Radio casualty condition responds immediately to HP zero"
	)
	check(
		not Session.Mission.Sequence.triggered(
			{"kind": "actor_dead", "actor": index}, pilot.active_job
		),
		"Director actor-dead condition waits for destruction"
	)
	var effect = flight.wrecks[index]
	check(effect.body == hull, "Wreck owns the original combat hull")
	flight.step(.05)
	check(
		effect.elapsed_ms == target.state.destruction.elapsed_ms and effect.elapsed_ms > 0,
		"Renderer follows the simulation-owned clock exactly"
	)
	flight.paused = true
	var elapsed: float = effect.elapsed_ms
	flight.step(.5)
	check(effect.elapsed_ms == elapsed, "Paused combat freezes the wreck clock")
	var saved: Dictionary = pilot.capture()
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(saved))),
		"Restore actual campaign during destruction: " + restored.error
	)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, restored, {}, true)
	view.set_physics_process(false)
	check(
		view.wrecks.has(index) and view.wrecks[index].elapsed_ms == elapsed,
		"Loaded Flight reconstructs a partially finished wreck"
	)
	check(
		view.wrecks[index].sounds.is_empty() and not view.wrecks[index].played.is_empty(),
		"Loaded wreck suppresses elapsed start sounds"
	)
	check(
		view.wrecks[index].appearances[0].scale == effect.appearances[0].scale,
		"Restored appearance uses a stable cosmetic seed"
	)
	var preserved: Dictionary = restored.capture().duplicate(true)
	for broken in [
		{"phase": "alive", "elapsed_ms": 0},
		{"phase": "dying", "elapsed_ms": -1},
		{"phase": "dying", "elapsed_ms": 1e9},
		{"phase": "dead", "elapsed_ms": 1}
	]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid.active_job.actors[index].destruction = broken
		check(
			not restored.restore(invalid) and same_saved_value(preserved, restored.capture()),
			"Malformed wreck state is rejected atomically"
		)
	var legacy: Dictionary = saved.duplicate(true)
	legacy.schema = 19
	for actor in legacy.active_job.actors:
		actor.erase("destruction")
	var old := Session.new()
	old.configure(lib)
	check(
		old.restore(legacy) and old.active_job.actors[index].destruction.phase == "dead",
		"Save19 migration keeps existing casualties completed without replay"
	)
	check(
		old.active_job.kills == pilot.active_job.kills and old.credits == pilot.credits,
		"Migration does not grant kills or rewards"
	)
	var future: Dictionary = restored.active_job.actors[index].destruction
	Life.advance(future, effect.definition, Life.span(effect.definition) / 1000.0)
	check(
		Session.Mission.achieved(
			{"kind": "enemy_destroyed", "index": enemy_index}, definition, restored.active_job
		),
		"Specific-target objective releases at completed destruction"
	)
	view.advance_explosions(0)
	check(not view.wrecks.has(index), "Completed restored wreck releases its visual")
	flight.queue_free()
	view.queue_free()
	await process_frame
	# Survival retains immediate awards while a dead slot's wreck is unfinished.
	var survival = preload("res://src/simulation/survival_session.gd").new()
	check(
		survival.configure_survival(lib, lib.content.survival, 0, 0, 452),
		"Create native survival lifecycle fixture"
	)
	var tick: float = survival.declarations.rules.tick_ms / 1000.0
	survival.advance_mission(tick + .001)
	survival.elapsed += tick + .001
	survival.advance_mission(tick - .01)
	survival.elapsed += tick - .01
	var actor: Dictionary = survival.active_job.actors[0]
	var score: int = survival.active_job.survival.score
	check(
		survival.damage_actor(0, actor.hp) and survival.active_job.survival.score > score,
		"Survival reward is immediate on the kill"
	)
	survival.advance_mission(.02)
	survival.elapsed += .02
	check(
		actor.hp == 0 and actor.destruction.phase == "dying",
		"Due reinforcement stage cannot reuse an unfinished wreck"
	)
	var snapshot: Dictionary = survival.capture()
	var resumed = preload("res://src/simulation/survival_session.gd").new()
	resumed.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		resumed.restore(snapshot),
		"Survival snapshot3 restores a partially finished wreck: " + resumed.error
	)
	var old_snapshot: Dictionary = snapshot.duplicate(true)
	old_snapshot.schema = 2
	for item in old_snapshot.actors:
		item.erase("destruction")
	check(
		resumed.restore(old_snapshot) and resumed.active_job.actors[0].destruction.phase == "dead",
		"Survival snapshot2 preserves previously completed casualties"
	)
	var old_clock: Dictionary = actor.destruction
	Life.advance(old_clock, Life.effect(lib, int(survival.arena.groups[0].actor)), 100)
	survival.active_job.survival.phase = "spawn"
	survival.active_job.survival.timer_ms = survival.declarations.rules.tick_ms
	survival.advance_mission(.001)
	check(
		actor.hp > 0 and actor.destruction.phase == "alive" and old_clock.phase == "dead",
		"Completed wreck permits a fresh survival life without mutating its old clock"
	)


func check_wreck_boundaries(lib) -> void:
	var Life = Session.Mission.Destruction
	var mine := {"hp": 0.0, "group": 0, "mine": {"phase": "shot", "elapsed_ms": 0.0}}
	var definition := {"groups": [{"team": "enemy"}], "route": []}
	var state := {"actors": [mine], "kills": 1, "target": 1}
	check(
		Session.Mission.Radio.triggered(
			{"condition": "enemy_range_destroyed", "value": 0, "count": 1}, definition, state
		),
		"Mine radio uses source HP predicate during explosion"
	)
	check(
		Session.Mission.achieved({"kind": "enemies_destroyed"}, definition, state),
		"Aggregate counter objective remains immediate"
	)
	check(
		not Session.Mission.achieved(
			{"kind": "enemy_prefix_destroyed", "count": 1}, definition, state
		),
		"Mine prefix objective still waits for its existing lifecycle"
	)
	var revived := {"hp": 0.0, "group": 0, "destruction": {"phase": "dying", "elapsed_ms": 10.0}}
	var previous: Dictionary = revived.destruction
	state = {"actors": [revived], "sequence_cursor": 0, "radio": {"shown": [0]}, "kills": 1}
	definition.sequence = [
		{
			"when": {"kind": "message_shown", "message": 0},
			"actions": [{"kind": "health", "actor": 0, "value": 10}]
		}
	]
	Session.Mission.Sequence.advance(definition, state)
	check(
		revived.hp == 10 and revived.destruction.phase == "alive" and previous.phase == "dead",
		"Scripted health restoration closes the old wreck clock and creates a new life"
	)
	var pilot = preload("res://src/simulation/survival_session.gd").new()
	check(
		pilot.configure_survival(lib, lib.content.survival, 0, 0, 455),
		"Start survival for slot visual ownership"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	var target := {}
	for item in flight.actors:
		if item.index == 0:
			target = item
	check(not target.is_empty(), "Initial active survival slot has an actual hull")
	if target.is_empty():
		flight.queue_free()
		await process_frame
		return
	pilot.damage_actor(0, target.state.hp)
	flight.spawn_targets()
	var effect = flight.wrecks[0]
	var old_body: Node3D = effect.body
	var old_clock: Dictionary = target.state.destruction
	flight.spawn_targets()
	check(
		flight.explosions.size() == 1 and not flight.actors.has(target),
		"Repeated target sync neither recreates the corpse nor duplicates its effect"
	)
	Life.advance(old_clock, effect.definition, Life.span(effect.definition) / 1000.0)
	pilot.active_job.survival.phase = "spawn"
	pilot.active_job.survival.timer_ms = pilot.declarations.rules.tick_ms
	pilot.advance_mission(.001)
	flight.spawn_targets()
	var new_body: Node3D
	for item in flight.actors:
		if item.index == 0:
			new_body = item.node
	check(
		new_body != null and new_body != old_body and effect.body == old_body,
		"Respawn creates a fresh hull while the previous effect retains its own body"
	)
	check(
		not flight.wrecks.has(0) and old_clock.phase == "dead",
		"Live slot no longer owns its previous wreck mapping"
	)
	flight.advance_explosions(0)
	check(
		flight.explosions.is_empty() and not new_body.is_queued_for_deletion(),
		"Old effect cleanup cannot delete the respawned ship"
	)
	# Test malformed clock rejection against a naturally constructed clean session.
	var fresh = preload("res://src/simulation/survival_session.gd").new()
	fresh.configure_survival(lib, lib.content.survival, 0, 0, 458)
	var clean: Dictionary = fresh.capture()
	var invalid: Dictionary = clean.duplicate(true)
	invalid.actors[0].destruction = {"phase": "dying", "elapsed_ms": 0}
	check(
		not fresh.restore(invalid) and same_saved_value(clean, fresh.capture()),
		"Survival rejects a living ship with a dying clock atomically"
	)
	invalid = clean.duplicate(true)
	invalid.actors[int(fresh.declarations.rules.initial_active)].destruction.phase = "dying"
	check(
		not fresh.restore(invalid),
		"An unused survival reserve slot cannot contain an unfinished wreck"
	)
	flight.queue_free()
	await process_frame


func check_escort_loss(lib, checkpoint: Dictionary, credits: int) -> void:
	var definition: Dictionary = lib.mission_definition(3)
	var failed := Session.new()
	failed.configure(lib)
	check(failed.restore(checkpoint), "Escort launch checkpoint is restorable")
	failed.damage_actor(4, lib.group_hull(definition.groups[1]))
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(failed.capture()))),
		"Destroyed escort restores with its unfinished wreck"
	)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, restored, {}, true)
	flight.set_physics_process(false)
	var failures_seen: Array = []
	flight.mission_failed.connect(func(): failures_seen.append(true))
	flight.step(.01)
	check(failures_seen.is_empty(), "Reloaded escort loss waits for its source destruction timeline")
	var wreck = flight.wrecks[4]
	flight.step(Session.Mission.Destruction.span(wreck.definition) / 1000.0 + .001)
	check(not wreck.body.visible, "Escort wreck reaches its hidden final frame before the failure screen freezes combat")
	check(
		failures_seen.size() == 1 and flight.paused and not restored.finish_mission(),
		"Reloaded escort loss shows mission failure rather than campaign success"
	)
	restored.retry_mission()
	check(
		(
			restored.chapter == 3
			and restored.credits == credits
			and restored.depart()
			and restored.active_job.actors[4].hp == lib.group_hull(definition.groups[1])
		),
		"Retry restores the escort without granting rewards or changing chapter"
	)
	flight.queue_free()
	await process_frame



func check_wreck_drift(source: PackedByteArray, lib) -> void:
	var Life = Session.Mission.Destruction
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var motion: Dictionary = reader.wreck_drift()
	check(
		not motion.is_empty() and reader.error.is_empty(),
		"Read source timer and fighter damping: " + reader.error
	)
	if motion.is_empty():
		return
	check(
		(
			is_equal_approx(motion.retention, .97)
			and is_equal_approx(motion.reference_seconds, 1.0 / 60.0)
		),
		"Source requests 60 Hz and retains 97 percent speed"
	)
	for address in [
		0xfed0,
		0xfeda,
		0x10598,
		0x1060a,
		0x10610,
		0x1061a,
		0x56680,
		0x56682,
		0x56686,
		0x566da,
		0x114c4
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.wreck_drift().is_empty() and not reader.error.is_empty(),
			"Reject changed wreck/timer binding %x" % address
		)
	reader.bytes = source.duplicate()
	reader.error = ""
	var literal_address: int = ((0x5667e + 4) & ~3) + (reader.u16(0x5667e) & 255) * 4
	reader.bytes.encode_float(reader.file_offset(literal_address, 4), .9)
	check(
		is_equal_approx(reader.wreck_drift().get("retention", 0), .9),
		"Damping is read from supplied constants"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	var interval_bytes := PackedByteArray()
	interval_bytes.resize(8)
	interval_bytes.encode_double(0, 1.0 / 30.0)
	for pair in [[0xfed2, 0], [0xfed8, 4]]:
		literal_address = ((int(pair[0]) + 4) & ~3) + (reader.u16(pair[0]) & 255) * 4
		reader.bytes.encode_u32(
			reader.file_offset(literal_address, 4), interval_bytes.decode_u32(pair[1])
		)
	check(
		is_equal_approx(reader.wreck_drift().get("reference_seconds", 0), 1.0 / 30.0),
		"Nominal interval is decoded from supplied double"
	)
	for bad in [
		{},
		{"retention": 1, "reference_seconds": .02},
		{"retention": 0, "reference_seconds": .02},
		{"retention": .9, "reference_seconds": 0},
		{"retention": NAN, "reference_seconds": .02}
	]:
		check(not Life.valid_motion(bad), "Reject invalid damping declaration")
	var effect: Dictionary = lib.content.actor_destruction.effects["3"]
	var origin := Vector3(10, 20, 30)
	var velocity := Vector3(32, -8, 56)
	var sample := {"hp": 0.0, "position": Combat.packed(origin), "destruction": Life.create()}
	sample.destruction.velocity = Combat.packed(velocity)
	Life.begin(sample)
	var single: Dictionary = sample.duplicate(true)
	Life.drift(single, effect, motion, motion.reference_seconds)
	check(
		Combat.vector(single.destruction.velocity).is_equal_approx(velocity * motion.retention),
		"One nominal update has imported retention"
	)
	var once: Dictionary = sample.duplicate(true)
	Life.drift(once, effect, motion, .5)
	Life.advance(once.destruction, effect, .5)
	for hz in [30, 60, 144]:
		var divided: Dictionary = sample.duplicate(true)
		for tick in hz / 2:
			Life.drift(divided, effect, motion, 1.0 / hz)
			Life.advance(divided.destruction, effect, 1.0 / hz)
		check(
			(
				Combat.vector(divided.position).distance_to(Combat.vector(once.position)) < .0001
				and (
					Combat.vector(divided.destruction.velocity).distance_to(
						Combat.vector(once.destruction.velocity)
					)
					< .0001
				)
			),
			"Equal drift at %d Hz" % hz
		)
	var unchanged: Dictionary = sample.duplicate(true)
	for invalid_time in [0.0, -1.0, NAN, INF]:
		Life.drift(unchanged, effect, motion, invalid_time)
	check(unchanged == sample, "Paused and invalid time preserves momentum and position")
	var stopped: Dictionary = sample.duplicate(true)
	stopped.destruction.velocity = [0.0, 0.0, 0.0]
	Life.drift(stopped, effect, motion, .5)
	check(stopped.position == sample.position, "Stationary wreck gets no invented cruise velocity")
	var short: Dictionary = lib.content.actor_destruction.effects["0"]
	var end_seconds: float = Life.completion_ms(short) / 1000.0
	var whole: Dictionary = sample.duplicate(true)
	Life.drift(whole, short, motion, 100)
	Life.advance(whole.destruction, short, 100)
	var boundary: Dictionary = sample.duplicate(true)
	Life.drift(boundary, short, motion, end_seconds)
	check(
		(
			whole.position == boundary.position
			and whole.destruction.phase == "dead"
			and Combat.vector(whole.destruction.velocity) == Vector3.ZERO
		),
		"Large step stops drift at final source fade"
	)
	var final_position: Array = whole.position.duplicate()
	Life.drift(whole, short, motion, 1)
	check(whole.position == final_position, "Finished wreck cannot keep drifting")
	# Use real encounter movement, projectiles, Flight and campaign saves.
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Start campaign momentum fixture")
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	flight.throttle = 0
	flight.ship.position = Combat.vector(pilot.active_job.actors[0].position) + Vector3(0, 0, 300)
	flight.step(.05)
	var positions := {}
	for actor in pilot.active_job.actors.size():
		positions[actor] = Combat.vector(pilot.active_job.actors[actor].position)
	flight.step(.05)
	var target := {}
	for actor in flight.actors:
		if flight.hostile(actor) and Combat.vector(actor.state.destruction.velocity).length() > 1:
			target = actor
			break
	check(not target.is_empty(), "Real encounter provides a moving hostile")
	if target.is_empty():
		flight.queue_free()
		await process_frame
		return
	var index := int(target.index)
	var actual := Combat.vector(target.state.position) - Vector3(positions[index])
	check(
		actual.distance_to(Combat.vector(target.state.destruction.velocity) * .05) < .001,
		"Recorded momentum matches actual encounter displacement"
	)
	var definition: Dictionary = pilot.mission_definition()
	var scripted: Dictionary = definition.duplicate(true)
	scripted.sequence = [
		{"when": {"kind": "elapsed", "ms": 0}, "actions": [{"kind": "stop", "actor": index}]}
	]
	var stopped_state: Dictionary = pilot.active_job.duplicate(true)
	stopped_state.sequence_cursor = 1
	Session.Encounters.advance(
		scripted,
		stopped_state,
		.05,
		flight.ship.position,
		Vector3.ZERO,
		Combat.create(),
		lib,
		pilot.actor_weapons()
	)
	check(
		Combat.vector(stopped_state.actors[index].destruction.velocity) == Vector3.ZERO,
		"Stopped director actor clears stale momentum"
	)
	target.state.hp = 1.0
	var before_velocity := Combat.vector(target.state.destruction.velocity)
	Combat.launch(
		pilot.combat,
		pilot.weapon_id,
		target.node.position,
		Vector3.FORWARD,
		Combat.profile(pilot.weapon_id, lib, pilot.actor_weapons()),
		lib,
		pilot.actor_weapons()
	)
	flight.advance_projectiles(.001)
	check(
		(
			target.state.hp == 0
			and Combat.vector(target.state.destruction.velocity) == before_velocity
		),
		"Native projectile kill retains last moving velocity"
	)
	var view_effect = flight.wrecks[index]
	var before_position := Combat.vector(target.state.position)
	flight.step(.05)
	check(
		(
			Combat.vector(target.state.position).distance_to(before_position) > .01
			and view_effect.global_position.is_equal_approx(Combat.vector(target.state.position))
		),
		"Original wreck hull and explosion follow simulated drift"
	)
	var saved: Dictionary = pilot.capture()
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(saved))),
		"Campaign21 restores moving wreck: " + restored.error
	)
	var saved_state := JSON.stringify(saved)
	var resumed_view := Flight.new()
	root.add_child(resumed_view)
	resumed_view.setup(lib, restored, {}, true)
	resumed_view.set_physics_process(false)
	check(
		resumed_view.wrecks[index].global_position.is_equal_approx(view_effect.global_position),
		"Loaded renderer starts at saved drift position"
	)
	pilot.advance_mission(.05)
	restored.advance_mission(.05)
	check(
		Combat.vector(pilot.active_job.actors[index].position).is_equal_approx(
			Combat.vector(restored.active_job.actors[index].position)
		),
		"Uninterrupted and restored drift stay aligned"
	)
	check(
		JSON.stringify(saved) == saved_state,
		"Restore and continued movement do not mutate save input"
	)
	flight.paused = true
	var paused_position: Array = target.state.position.duplicate()
	flight.step(.3)
	check(target.state.position == paused_position, "Flight pause freezes wreck translation")
	var prior: Dictionary = restored.capture()
	for malformed in [[], [0, INF, 0], [0, 0, 1e7], "velocity"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.active_job.actors[index].destruction.velocity = malformed
		check(
			not restored.restore(bad) and same_saved_value(prior, restored.capture()),
			"Malformed momentum rejected atomically"
		)
	var legacy: Dictionary = saved.duplicate(true)
	legacy.schema = 20
	for actor in legacy.active_job.actors:
		if actor.has("destruction"):
			actor.destruction.erase("velocity")
	check(
		(
			restored.restore(legacy)
			and (
				Combat.vector(restored.active_job.actors[index].destruction.velocity)
				== Vector3.ZERO
			)
		),
		"Save20 has safe zero momentum migration"
	)
	check(
		(
			restored.active_job.actors[index].destruction.phase == "dying"
			and (
				restored.active_job.actors[index].position
				== saved.active_job.actors[index].position
			)
			and restored.credits == saved.credits
		),
		"Legacy migration preserves wreck position, phase and rewards"
	)
	check(
		not legacy.active_job.actors[index].destruction.has("velocity"),
		"Legacy migration is nonmutating"
	)
	flight.queue_free()
	resumed_view.queue_free()
	await process_frame
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var survivor: Dictionary = survival.active_job.actors[0]
	var speed: float = Life.speed_limit(survival.arena.groups[0])
	survivor.destruction.velocity = [speed, 0.0, 0.0]
	survival.damage_actor(0, survivor.hp)
	survival.advance_mission(.05)
	survival.elapsed += .05
	var snapshot: Dictionary = survival.capture()
	var resumed = preload("res://src/simulation/survival_session.gd").new()
	resumed.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		(
			resumed.restore(snapshot)
			and Combat.vector(resumed.active_job.actors[0].destruction.velocity).length() > 0
		),
		"Survival4 restores moving wreck: " + resumed.error
	)
	var arena_view := Flight.new()
	root.add_child(arena_view)
	arena_view.setup(lib, survival, {}, true)
	arena_view.set_physics_process(false)
	var old_effect = arena_view.wrecks[0]
	var old_position: Vector3 = old_effect.global_position
	Life.advance(survivor.destruction, Life.effect(lib, int(survival.arena.groups[0].actor)), 100)
	survival.active_job.survival.phase = "spawn"
	survival.active_job.survival.timer_ms = survival.declarations.rules.tick_ms
	survival.advance_mission(.001)
	check(
		survivor.hp > 0 and Combat.vector(survivor.destruction.velocity) == Vector3.ZERO,
		"Respawn starts a new life with zero stale momentum"
	)
	arena_view.advance_explosions(0)
	check(
		old_effect.global_position == old_position, "Old wreck cannot teleport to respawn position"
	)
	var legacy_snapshot: Dictionary = snapshot.duplicate(true)
	legacy_snapshot.schema = 3
	for actor in legacy_snapshot.actors:
		actor.destruction.erase("velocity")
	check(
		(
			resumed.restore(legacy_snapshot)
			and Combat.vector(resumed.active_job.actors[0].destruction.velocity) == Vector3.ZERO
		),
		"Survival3 migrates without inventing momentum"
	)
	var preserved: Dictionary = resumed.capture()
	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	bad_snapshot.actors[0].destruction.velocity = [1e7, 0, 0]
	check(
		not resumed.restore(bad_snapshot) and same_saved_value(preserved, resumed.capture()),
		"Survival rejects impossible velocity atomically"
	)
	arena_view.queue_free()
	await process_frame


func check_wreck_convoy_motion(lib) -> void:
	var Life = Session.Mission.Destruction
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 6
	pilot.progression = Session.Progression.create(6)
	pilot.station_id = lib.chapter_destination(5)
	check(pilot.depart(), "Create real convoy drift boundary fixture")
	var definition: Dictionary = pilot.mission_definition()
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.1,
		Vector3(0, 0, 20000),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	var cargo: Dictionary = pilot.active_job.actors[10]
	var stationary: Dictionary = pilot.active_job.actors[3]
	var group: Dictionary = definition.groups[int(cargo.group)]
	check(
		(
			group.behavior == "transit"
			and Combat.vector(cargo.destruction.velocity).is_equal_approx(
				Combat.vector(group.velocity)
			)
		),
		"Transit cargo records its imported velocity"
	)
	check(
		Combat.vector(stationary.destruction.velocity) == Vector3.ZERO,
		"Fixed cruiser mount retains zero momentum"
	)
	check(
		Session.Mission.valid(definition, pilot.active_job, 6, pilot.station_id, lib),
		"Moving convoy remains a valid campaign state"
	)
	var changed: Dictionary = pilot.active_job.duplicate(true)
	changed.actors[3].destruction.velocity = [10, 0, 0]
	check(
		not Session.Mission.valid(definition, changed, 6, pilot.station_id, lib),
		"Stationary mount cannot restore invented motion"
	)
	var pos := Combat.vector(cargo.position)
	pilot.damage_actor(10, cargo.hp)
	pilot.advance_mission(.1)
	check(
		(
			Combat.vector(cargo.position).distance_to(pos) > 0
			and (
				Combat.vector(cargo.destruction.velocity).length()
				< Combat.vector(group.velocity).length()
			)
		),
		"Destroyed cargo continues with decaying momentum"
	)
	var saved: Dictionary = pilot.capture()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(saved), "Moving convoy wreck saves with source velocity bound: " + copy.error
	)
	var bad: Dictionary = saved.duplicate(true)
	bad.active_job.actors[10].destruction.erase("velocity")
	check(not copy.restore(bad), "Current saves require momentum instead of silent fallback")
	var effect: Dictionary = Life.effect(lib, int(group.actor))
	var clock: Dictionary = cargo.destruction
	var sequence := {
		"sequence":
		[
			{
				"when": {"kind": "hull_below", "actor": 10, "value": 1},
				"actions": [{"kind": "health", "actor": 10, "value": group.hull}]
			}
		],
		"groups": definition.groups
	}
	pilot.active_job.sequence_cursor = 0
	Session.Mission.Sequence.advance(sequence, pilot.active_job)
	check(
		(
			cargo.hp > 0
			and clock.phase == "dead"
			and Combat.vector(clock.velocity) == Vector3.ZERO
			and Life.valid(cargo.destruction, cargo.hp, effect)
		),
		"Scripted new life retires old momentum"
	)
	var moving := {"behavior": "interceptor", "motion": {"speed": 10.0}}
	var overrides := [
		{
			"actions":
			[
				{"kind": "speed", "actor": 0, "value": 40.0},
				{"kind": "speed", "actor": 1, "value": 90.0}
			]
		}
	]
	check(
		(
			Life.speed_limit(moving, overrides, 0) == 40
			and Life.speed_limit(moving, overrides, 1) == 90
		),
		"Save velocity bounds account for actor-specific source speed changes"
	)


func check_fighter_steering_motion(source: PackedByteArray, lib) -> void:
	var Motion = Session.Encounters
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data: Dictionary = reader.fighter_steering()
	check(
		not data.is_empty() and reader.error.is_empty(),
		"Read source fighter direction limits: " + reader.error
	)
	if data.is_empty():
		return
	check(
		(
			is_equal_approx(data.normal_rate, 48000.0 / 65536.0)
			and is_equal_approx(data.enhanced_rate, 64000.0 / 65536.0)
		),
		"Direction gains use elapsed milliseconds and fixed-point vector units"
	)
	check(
		(
			data.enhanced_actor == 18
			and data.enhanced_chapter == 5
			and data.special_actor == 10
			and data.special_chapter == 12
		),
		"Import actor and campaign-specific handling"
	)
	for address in [
		0x564a2,
		0x564a6,
		0x564ac,
		0x564b0,
		0x564f8,
		0x564fe,
		0x56508,
		0x56562,
		0x5594e,
		0x5595a,
		0x55968,
		0xf276
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_steering().is_empty() and not reader.error.is_empty(),
			"Reject changed steering consumer %x" % address
		)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(
		reader.file_offset(0x564f6, 2), (reader.u16(0x564f6) & ~0x7c0) | (2 << 6)
	)
	check(
		is_equal_approx(reader.fighter_steering().get("normal_rate", 0), 80000.0 / 65536.0),
		"Normal direction limit changes with supplied shift data"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(reader.file_offset(0x55952, 2), 0x2a0b)
	check(
		reader.fighter_steering().get("special_actor") == 11,
		"Enhanced handling association comes from supplied actor selector"
	)
	var actor_count: int = lib.content.tables.actor_meshes.size()
	var chapter_count: int = lib.content.chapters.size()
	for mutation in [
		{"normal_rate": 0},
		{"enhanced_rate": INF},
		{"snap_distance": 1},
		{"enhanced_actor": actor_count},
		{"special_chapter": chapter_count}
	]:
		var bad: Dictionary = data.duplicate(true)
		bad.merge(mutation, true)
		check(
			not Motion.valid_steering(bad, actor_count, chapter_count),
			"Reject malformed fighter steering declaration"
		)
	check(lib.valid_fighter_steering(), "Installed resources accept staged source steering")
	var original: Dictionary = lib.content.fighter_steering
	lib.content.fighter_steering = {}
	check(
		not lib.valid_fighter_steering(),
		"Library reports unsupported missing steering instead of inventing it"
	)
	lib.content.fighter_steering = original
	lib.error = ""
	var direction := Vector3.FORWARD
	var target := Vector3.RIGHT
	var single: Vector3 = Motion.steer_heading(
		direction, target, .5, data.normal_rate, data.snap_distance
	)
	var turned := rad_to_deg(direction.angle_to(single))
	check(
		turned > 12 and turned < 18,
		"Fighter takes a gradual source-limited turn instead of generic fast pursuit"
	)
	check(is_equal_approx(single.length(), 1), "Turning preserves unit heading")
	for hz in [30, 60, 144]:
		var divided := direction
		for tick in hz / 2:
			divided = Motion.steer_heading(
				divided, target, 1.0 / hz, data.normal_rate, data.snap_distance
			)
		check(
			divided.distance_to(single) < .0001,
			"Steering direction independent of %d Hz subdivision" % hz
		)
	var enhanced: Vector3 = Motion.steer_heading(
		direction, target, .5, data.enhanced_rate, data.snap_distance
	)
	check(
		direction.angle_to(enhanced) > direction.angle_to(single),
		"Enhanced source gain turns faster"
	)
	check(
		(
			Motion
			. steer_heading(direction, target, 100, data.normal_rate, data.snap_distance)
			. is_equal_approx(target)
		),
		"Large turn step reaches target without overshoot"
	)
	for seconds in [0, -1, NAN, INF]:
		check(
			(
				Motion.steer_heading(
					direction, target, seconds, data.normal_rate, data.snap_distance
				)
				== direction
			),
			"Invalid or paused time cannot change heading"
		)
	check(
		(
			Motion.steer_heading(direction, -direction, .05, data.normal_rate, data.snap_distance)
			== direction
		),
		"Exactly opposed vectors do not invent an arbitrary rotation plane"
	)
	check(
		(
			Motion.steer_heading(direction, Vector3.ZERO, .05, data.normal_rate, data.snap_distance)
			== direction
		),
		"Absent desired direction keeps heading"
	)
	var close := direction.rotated(Vector3.UP, .02)
	check(
		(
			Motion
			. steer_heading(direction, close, .001, data.normal_rate, data.snap_distance)
			. is_equal_approx(close)
		),
		"Imported near-alignment threshold finishes small corrections"
	)
	for chapter in chapter_count:
		var state := {"kind": "campaign", "chapter": chapter}
		for actor in [0, 10, 18]:
			var expected: float = (
				data.enhanced_rate
				if actor == 18 or chapter == 5 or (chapter == 12 and actor == 10)
				else data.normal_rate
			)
			check(
				Motion.steering_rate(data, {"actor": actor}, state) == expected,
				"Source steering selection chapter %d actor %d" % [chapter, actor]
			)
	for kind in ["contract", "survival"]:
		check(
			(
				(
					Motion.steering_rate(data, {"actor": 10}, {"kind": kind, "chapter": 12})
					== data.normal_rate
				)
				and (
					Motion.steering_rate(data, {"actor": 18}, {"kind": kind, "chapter": 12})
					== data.enhanced_rate
				)
			),
			"Noncampaign handling uses its actor class"
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Create actual encounter steering fixture")
	var definition: Dictionary = pilot.mission_definition()
	var actor: Dictionary = pilot.active_job.actors[0]
	actor.awake = true
	Session.Mission.Frame.turn(actor, direction)
	var before := Combat.vector(actor.position)
	var player_position := before + Vector3(1000, 0, 0)
	Motion.advance(
		definition,
		pilot.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	var heading := Combat.vector(actor.heading)
	var group: Dictionary = definition.groups[int(actor.group)]
	check(
		heading.is_equal_approx(
			Motion.steer_heading(
				direction, Vector3.RIGHT, .05, data.normal_rate, data.snap_distance
			)
		),
		"Actual encounter consumes source steering declaration"
	)
	check(
		(
			(Combat.vector(actor.position) - before).distance_to(
				heading * float(actor.fighter_motion.speed) * .05
			)
			< .001
		),
		"Steering correction preserves source forward travel speed"
	)
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Source-steered campaign saves existing heading/momentum: " + copy.error
	)
	Motion.advance(
		definition,
		pilot.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	Motion.advance(
		copy.mission_definition(),
		copy.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		copy.combat,
		lib,
		copy.actor_weapons()
	)
	check(
		(
			Combat.vector(copy.active_job.actors[0].heading).is_equal_approx(
				Combat.vector(actor.heading)
			)
			and Combat.vector(copy.active_job.actors[0].position).is_equal_approx(
				Combat.vector(actor.position)
			)
		),
		"Restored steering continues without a heading jump"
	)
	# A legacy generic rotation field must no longer drive fighter movement.
	var altered: Dictionary = definition.duplicate(true)
	for item in altered.groups:
		if item.has("motion"):
			item.motion.turn_response = 1000.0
	var alternate: Dictionary = copy.active_job.duplicate(true)
	Motion.advance(
		altered,
		alternate,
		.05,
		player_position,
		Vector3.ZERO,
		Combat.create(),
		lib,
		pilot.actor_weapons()
	)
	Motion.advance(
		definition,
		copy.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		copy.combat,
		lib,
		copy.actor_weapons()
	)
	check(
		Combat.vector(alternate.actors[0].heading).is_equal_approx(
			Combat.vector(copy.active_job.actors[0].heading)
		),
		"Generic rotation-speed metadata no longer changes fighter turning"
	)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.throttle = 0
	view.ship.position = player_position
	view.step(.05)
	var shown := false
	for target_actor in view.actors:
		if int(target_actor.index) == 0:
			shown = (-target_actor.node.basis.z).is_equal_approx(Combat.vector(actor.heading))
	check(shown, "Original ship presentation follows native source-steered heading")
	view.queue_free()
	await process_frame


func check_fighter_overlap_motion(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Create overlapping-target movement fixture")
	var definition: Dictionary = pilot.mission_definition()
	var snapshot: Dictionary = pilot.active_job.duplicate(true)
	for offset in [Vector3.ZERO, Vector3(.01, 0, 0)]:
		var state: Dictionary = snapshot.duplicate(true)
		var actor: Dictionary = state.actors[0]
		actor.awake = true
		actor.heading = [0.0, 0.0, -1.0]
		var position := Combat.vector(actor.position)
		Session.Encounters.advance(
			definition,
			state,
			.05,
			position + offset,
			Vector3.ZERO,
			Combat.create(),
			lib,
			pilot.actor_weapons()
		)
		var speed: float = actor.fighter_motion.speed
		check(
			(
				(Combat.vector(actor.position) - position).distance_to(
					Combat.vector(actor.heading) * speed * .05
				)
				< .001
			),
			"Coincident or near-coincident combat target cannot stop forward travel"
		)
		check(
			Combat.vector(actor.destruction.velocity).is_equal_approx(Combat.vector(actor.heading) * speed),
			"Close pass keeps authoritative forward momentum"
		)


func check_fighter_evasion(source: PackedByteArray, lib) -> void:
	var Evasion = Session.Mission.Evasion
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data: Dictionary = reader.fighter_evasion()
	check(
		not data.is_empty() and reader.error.is_empty(),
		"Read source lateral maneuvers: " + reader.error
	)
	if data.is_empty():
		return
	check(
		data.directions == [[0, 1, 0], [1, 0, 0], [0, 1.0, 0], [1.0, 0, 0]],
		"Preserve the source's four weighted positive up/right choices"
	)
	check(
		data.heavy_half_width == 120 and data.special_half_width == 120,
		"Source heavy and special avoidance boxes"
	)
	for address in [
		0x5602a,
		0x56048,
		0x56050,
		0x5605c,
		0x56062,
		0x56074,
		0x560b6,
		0x560c8,
		0x560d0,
		0x56194,
		0x55970
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_evasion().is_empty() and not reader.error.is_empty(),
			"Reject changed maneuver semantics %x" % address
		)
	reader.bytes = source.duplicate()
	reader.error = ""
	var literal_address: int = ((0x5596c + 4) & ~3) + (reader.u16(0x5596c) & 255) * 4
	reader.bytes.encode_u32(reader.file_offset(literal_address, 4), 8000)
	check(
		reader.fighter_evasion().get("special_half_width") == 160,
		"Avoidance extent is supplied data"
	)
	var actor := {"heading": [0.0, 0.0, -1.0], "breaking": false, "evasion": Evasion.create()}
	var direction: Vector3 = Evasion.desired(
		actor, Vector3(79, 79, 79), 80, data.directions, 452, 0
	)
	check(
		actor.breaking and direction in [Vector3.UP, Vector3.RIGHT],
		"Avoidance uses an axis box and lateral source direction, not a reverse-away sphere"
	)
	check(Evasion.valid(actor), "Chosen maneuver is valid saved state")
	var chosen: Dictionary = actor.duplicate(true)
	for tick in 10:
		Evasion.desired(actor, Vector3(1, 2, 3), 80, data.directions, 452, 0)
	check(actor == chosen, "Maneuver is held rather than rerolled while inside the box")
	var outside := Vector3(80, 0, 0)
	check(
		(
			Evasion.desired(actor, outside, 80, data.directions, 452, 0) == outside
			and not actor.breaking
		),
		"Exact source boundary releases avoidance immediately"
	)
	check(
		actor.evasion.decisions == 1 and Evasion.valid(actor),
		"Leaving the box preserves decision sequence"
	)
	var duplicate: Dictionary = actor.duplicate(true)
	check(
		(
			(
				Evasion.desired(actor, Vector3.ZERO, 80, data.directions, 452, 0)
				== Evasion.desired(duplicate, Vector3.ZERO, 80, data.directions, 452, 0)
			)
			and actor.evasion.decisions == 2
		),
		"Reentry and saved continuation choose deterministically"
	)
	var heading := Vector3(.4, .3, -.8660254).normalized()
	var rotated := {
		"heading": Combat.packed(heading), "breaking": false, "evasion": Evasion.create()
	}
	var lateral: Vector3 = Evasion.desired(rotated, Vector3.ZERO, 80, data.directions, 452, 0)
	check(
		absf(lateral.dot(heading)) < .00001 and is_equal_approx(lateral.length(), 1),
		"Escape direction is relative to the ship's orientation"
	)
	for broken in [
		{"direction": [0, 0, 0], "decisions": 1},
		{"direction": [1, 1, 0], "decisions": 1},
		{"direction": [1, 0, 0], "decisions": -1},
		{"direction": [1, 0, 0], "decisions": 1.5}
	]:
		check(
			not Evasion.valid({"evasion": broken, "breaking": true}),
			"Malformed saved maneuver rejected"
		)
	check(not Evasion.valid(chosen, false), "Stationary turrets cannot acquire fighter evasion")
	for broken in [
		{},
		{"directions": [], "heavy_half_width": 120, "special_half_width": 120},
		{"directions": [[1, 0, 0]], "heavy_half_width": 0, "special_half_width": 120}
	]:
		check(not Evasion.valid_data(broken), "Malformed imported maneuvers rejected")
	var group := {"actor": 0, "motion": {"avoid_distance": 80}}
	var steering: Dictionary = lib.content.fighter_steering
	check(
		Evasion.half_width(data, steering, group, {"kind": "campaign", "chapter": 0}) == 80,
		"Ordinary actors keep their imported factory box"
	)
	check(
		Evasion.half_width(data, steering, group, {"kind": "campaign", "chapter": 5}) == 120,
		"Duel specialization uses its constructor box"
	)
	group.actor = 18
	check(
		Evasion.half_width(data, steering, group, {"kind": "contract", "chapter": 13}) == 120,
		"Heavy actors use their source avoidance box outside campaigns"
	)
	var aim := {"fire_half_width": 1000, "aim_sine": .02}
	check(
		not Session.Encounters.firing_aligned(
			Vector3.FORWARD, Vector3(0, 0, -10), aim, Vector3.RIGHT
		),
		"Initial lateral maneuver must align before shooting"
	)
	check(
		Session.Encounters.firing_aligned(Vector3.RIGHT, Vector3(0, 0, -10), aim, Vector3.RIGHT),
		"Aligned maneuver can fire along the ship's heading"
	)
	# Actual campaign state, renderer and JSON restore during a maneuver.
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Create real evasion encounter")
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	var player_position := Combat.vector(target.position) + Vector3(20, 0, 0)
	var definition: Dictionary = pilot.mission_definition()
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		target.breaking and target.evasion.decisions == 1 and Evasion.valid(target),
		"Native encounter selects a saved lateral maneuver"
	)
	var saved: Dictionary = pilot.capture()
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(saved))),
		"Campaign22 restores active maneuver: " + restored.error
	)
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	Session.Encounters.advance(
		restored.mission_definition(),
		restored.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		restored.combat,
		lib,
		restored.actor_weapons()
	)
	check(
		(
			same_saved_value(target.evasion, restored.active_job.actors[0].evasion)
			and Combat.vector(target.position).is_equal_approx(
				Combat.vector(restored.active_job.actors[0].position)
			)
		),
		"Loaded maneuver continues with identical position and choice"
	)
	var preserved: Dictionary = restored.capture()
	var malformed: Dictionary = saved.duplicate(true)
	malformed.active_job.actors[0].evasion.direction = [0, 0, 0]
	check(
		not restored.restore(malformed) and same_saved_value(preserved, restored.capture()),
		"Campaign rejects inconsistent active maneuver atomically"
	)
	malformed = saved.duplicate(true)
	malformed.active_job.actors[0].erase("evasion")
	check(not restored.restore(malformed), "Current saves require maneuver state")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.schema = 21
	for item in legacy.active_job.actors:
		item.erase("evasion")
	check(
		(
			restored.restore(legacy)
			and not restored.active_job.actors[0].breaking
			and restored.active_job.actors[0].evasion.decisions == 0
		),
		"Save21 resets obsolete reversal without inventing lateral history"
	)
	check(
		(
			restored.active_job.actors[0].position == saved.active_job.actors[0].position
			and restored.active_job.actors[0].heading == saved.active_job.actors[0].heading
			and restored.credits == saved.credits
		),
		"Migration preserves pose and rewards"
	)
	check(not legacy.active_job.actors[0].has("evasion"), "Legacy migration does not mutate input")
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.ship.position = player_position
	view.throttle = 0
	view.step(.05)
	check(
		Evasion.valid(target) and target.evasion.decisions == 1,
		"Actual Flight retains the chosen evasion across ticks"
	)
	view.paused = true
	var paused: Dictionary = target.duplicate(true)
	view.step(1)
	check(target == paused, "Pause freezes maneuver state and position")
	view.queue_free()
	await process_frame
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var fighter: Dictionary = survival.active_job.actors[0]
	Evasion.desired(fighter, Vector3.ZERO, 80, data.directions, 452, 0)
	var snapshot: Dictionary = survival.capture()
	var resumed = preload("res://src/simulation/survival_session.gd").new()
	resumed.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		(
			resumed.restore(snapshot)
			and same_saved_value(fighter.evasion, resumed.active_job.actors[0].evasion)
		),
		"Survival5 restores active maneuver: " + resumed.error
	)
	var old: Dictionary = snapshot.duplicate(true)
	old.schema = 4
	for item in old.actors:
		item.erase("evasion")
	check(
		resumed.restore(old) and not resumed.active_job.actors[0].breaking,
		"Survival4 migrates old breakaway state"
	)
	preserved = resumed.capture()
	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	bad_snapshot.actors[0].evasion.direction = [NAN, 0, 0]
	check(
		not resumed.restore(bad_snapshot) and same_saved_value(preserved, resumed.capture()),
		"Survival rejects malformed maneuver atomically"
	)
	survival.damage_actor(0, fighter.hp)
	Session.Mission.Destruction.advance(
		fighter.destruction,
		Session.Mission.Destruction.effect(lib, int(survival.arena.groups[0].actor)),
		100
	)
	survival.active_job.survival.phase = "spawn"
	survival.active_job.survival.timer_ms = survival.declarations.rules.tick_ms
	survival.advance_mission(.001)
	check(
		(
			fighter.hp > 0
			and not fighter.breaking
			and fighter.evasion.decisions == 1
			and Evasion.valid(fighter)
		),
		"Respawn clears old direction while preserving decision sequence"
	)


func check_fighter_evasion_boundaries(lib) -> void:
	var Evasion = Session.Mission.Evasion
	var data: Dictionary = lib.content.fighter_evasion
	var actor := {"heading": [0.0, 0.0, -1.0], "breaking": false, "evasion": Evasion.create()}
	var direction: Vector3 = Evasion.desired(actor, Vector3.ZERO, 80, data.directions, 452, 0)
	Evasion.suspend(actor)
	check(
		(
			not actor.breaking
			and Evasion.valid(actor)
			and Combat.vector(actor.evasion.direction) == direction
		),
		"Route following suspends steering without discarding the previous source choice"
	)
	check(
		(
			Evasion.desired(actor, Vector3.ZERO, 80, data.directions, 452, 0) == direction
			and actor.evasion.decisions == 1
		),
		"Returning target inside the box resumes the held direction"
	)
	Evasion.suspend(actor)
	Evasion.desired(actor, Vector3(80, 0, 0), 80, data.directions, 452, 0)
	check(
		Combat.vector(actor.evasion.direction) == Vector3.ZERO and not actor.breaking,
		"Returning target outside the box resets the held choice"
	)
	Evasion.desired(actor, Vector3.ZERO, 80, data.directions, 452, 0)
	var definition := {
		"sequence":
		[
			{
				"when": {"kind": "hull_below", "actor": 0, "value": 1},
				"actions": [{"kind": "health", "actor": 0, "value": 5}]
			}
		],
		"groups": [{"team": "ally"}]
	}
	actor.hp = 0.0
	actor.group = 0
	actor.destruction = Session.Mission.Destruction.create(false)
	var state := {"actors": [actor], "sequence_cursor": 0, "kills": 0}
	Session.Mission.Sequence.advance(definition, state)
	check(
		(
			actor.hp == 5
			and not actor.breaking
			and Evasion.valid(actor)
			and actor.evasion.direction == [0.0, 0.0, 0.0]
			and actor.evasion.decisions == 2
		),
		"Scripted new life clears old direction and retains independent decision sequence"
	)
	var legacy := [{"heading": [0, 0, -1], "breaking": true, "evasion": Evasion.create()}]
	check(
		Evasion.migrate(legacy) and not legacy[0].breaking and Evasion.valid(legacy[0]),
		"Older migration-created defaults cannot preserve an obsolete reversal flag"
	)
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var snapshot: Dictionary = survival.capture()
	var index: int = snapshot.director.active_count
	check(index < snapshot.actors.size(), "Source survival fixture includes unused reserves")
	for mutation in [
		{"direction": [1, 0, 0], "decisions": 0}, {"direction": [0, 0, 0], "decisions": 1}
	]:
		var bad: Dictionary = snapshot.duplicate(true)
		bad.actors[index].evasion = mutation
		check(
			not survival.restore(bad) and same_saved_value(snapshot, survival.capture()),
			"Unused reserve cannot invent a held maneuver or history"
		)
	var fighter: Dictionary = survival.active_job.actors[0]
	Evasion.desired(fighter, Vector3.ZERO, 80, data.directions, 452, 0)
	Evasion.suspend(fighter)
	var saved: Dictionary = survival.capture()
	check(
		(
			survival.restore(JSON.parse_string(JSON.stringify(saved)))
			and not survival.active_job.actors[0].breaking
			and survival.active_job.actors[0].evasion.decisions == 1
		),
		"Held inactive maneuver survives actual survival JSON restore"
	)
	Evasion.desired(survival.active_job.actors[0], Vector3.ZERO, 80, data.directions, 452, 0)
	check(
		survival.active_job.actors[0].evasion.decisions == 1,
		"Restored held maneuver does not consume another random choice"
	)


func check_evasion_legacy_validation() -> void:
	var Evasion = Session.Mission.Evasion
	check(
		not Evasion.migrate([{"heading": [0, 0, -1], "breaking": "invalid"}]),
		"Legacy migration rejects malformed reversal flags"
	)
	var actor := {"heading": [0, 0, -1], "breaking": true}
	check(
		Evasion.migrate([actor]) and Evasion.valid(actor),
		"Valid old reversal initializes a fresh source maneuver"
	)


func check_fighter_motion(source: PackedByteArray) -> void:
	var Motion = preload("res://src/simulation/fighter_motion.gd")
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data: Dictionary = reader.fighter_motion()
	check(
		not data.is_empty() and reader.error.is_empty(),
		"Read operative fighter speed and boost constants: " + reader.error
	)
	if data.is_empty():
		return
	check(
		data.initial_speed == 40 and data.cruise_speed == 40 and data.boost_speed == 100,
		"Movement uses current speed, not generic base speed"
	)
	check(
		data.acceleration == 40 and data.braking == 40 and data.decision_seconds == 5,
		"Source acceleration, braking and decision time units"
	)
	check(
		(
			data.duration_chance == 20
			and data.chance_out_of == 100
			and data.duration_min_ms == 4000
			and data.duration_choices_ms == 3000
		),
		"Source duration-refresh distribution"
	)
	check(data.excluded_actors == [20, 6, 10015, 10014, 2, 17, 18], "Source actor boost exclusions")
	check(
		(
			data.heavy.far_width == 800
			and data.special.far_width == 440
			and is_equal_approx(data.special.floor_speed, 42)
		),
		"Source proximity ranges and speed floors"
	)
	for address in [
		0x55a0e,
		0x565c8,
		0x68494,
		0x55892,
		0x55976,
		0x561b0,
		0x561ea,
		0x56206,
		0x5621c,
		0x56264,
		0x56270,
		0x5628e,
		0x562a4,
		0x562ea,
		0x56226,
		0x56236,
		0x562ae,
		0x562f4,
		0x56252,
		0x560e6,
		0x56114
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_motion().is_empty() and not reader.error.is_empty(),
			"Reject altered fighter speed semantics %x" % address
		)
	reader.bytes = source.duplicate()
	reader.error = ""
	var address: int = ((0x562ac + 4) & ~3) + (reader.u16(0x562ac) & 255) * 4
	reader.bytes.encode_float(reader.file_offset(address, 4), 250.0)
	check(
		reader.fighter_motion().get("acceleration") == 80,
		"Acceleration is recovered from supplied constants"
	)
	for broken in [
		{"acceleration": 0},
		{"reference_seconds": 0},
		{"cruise_speed": 101},
		{"duration_chance": 101},
		{"far_retention": 1},
		{"excluded_actors": [-1]},
		{"heavy": {}},
		{"initial_speed": NAN}
	]:
		var invalid: Dictionary = data.duplicate(true)
		invalid.merge(broken, true)
		check(not Motion.valid_data(invalid), "Reject invalid motion data " + str(broken))
	var state: Dictionary = Motion.create(data)
	check(Motion.valid(state, data), "Initial boost component is valid")
	check(
		(
			Motion.advance(state, data, 4.9, 20, 0) == 196
			and state.speed == 40
			and state.decisions == 0
		),
		"Cruise before the first boost decision"
	)
	var before: Dictionary = state.duplicate(true)
	for seconds in [0.0, -1.0, NAN, INF]:
		check(
			Motion.advance(state, data, seconds, 20, 0) == 0 and state == before,
			"Pause and invalid delta leave motion unchanged"
		)
	state = Motion.create(data)
	Motion.damage(state, 40, 100, data)
	check(not state.forced and state.damage == 40, "Damage threshold is strict")
	Motion.damage(state, 1, 100, data)
	check(
		state.forced and state.damage == 0 and state.elapsed == 10,
		"Accumulated damage requests boost immediately"
	)
	var distance: float = Motion.advance(state, data, .5, 20, 0)
	check(
		(
			is_equal_approx(distance, 25)
			and state.speed == 60
			and state.phase == "boost"
			and state.decisions == 1
		),
		"Forced boost integrates acceleration and distance"
	)
	check(
		state.duration >= 4 and state.duration < 7 and not state.forced,
		"Forced boost receives a source duration"
	)
	distance = Motion.advance(state, data, 1.5, 20, 0)
	check(
		is_equal_approx(distance, 130) and state.speed == 100 and state.phase == "boost",
		"Boost integrates through cap and coasts without overshooting"
	)
	var until_braking: float = state.duration - state.elapsed
	Motion.advance(state, data, until_braking, 20, 0)
	distance = Motion.advance(state, data, .5, 20, 0)
	check(
		is_equal_approx(distance, 45) and state.speed == 80 and state.phase == "brake",
		"Boost duration hands off to braking"
	)
	Motion.advance(state, data, 1.5, 20, 0)
	check(
		state.speed == 40 and state.phase == "idle" and Motion.valid(state, data),
		"Braking reaches cruise without undershoot"
	)
	# The private seed is selected here only to exercise the failed refresh branch.
	var failed_seed := -1
	for seed_value in 100:
		var probe: Dictionary = Motion.create(data)
		Motion.begin_boost(probe, data, seed_value, 0)
		if probe.duration == 0:
			failed_seed = seed_value
			break
	check(failed_seed >= 0, "A failed duration refresh is reachable")
	state = Motion.create(data)
	Motion.begin_boost(state, data, failed_seed, 0)
	Motion.advance(state, data, data.reference_seconds * .5, failed_seed, 0)
	check(
		state.phase == "boost" and state.speed > 40 and state.duration == 0,
		"Failed first duration roll still accelerates"
	)
	Motion.advance(state, data, data.reference_seconds * 3, failed_seed, 0)
	check(
		state.speed == 40 and state.phase == "idle",
		"Zero-duration pulse ends after nominal source interval, independent of frame length"
	)
	state = Motion.create(data)
	state.duration = 4.5
	Motion.begin_boost(state, data, failed_seed, 0)
	check(state.duration == 4.5, "Failed roll retains previous duration")
	state.speed = 100.0
	Motion.damage(state, 41, 100, data)
	Motion.advance(state, data, .5, failed_seed, 0)
	check(
		state.speed == 80 and state.phase == "brake" and state.decisions == 1,
		"Damage at boost cap starts braking rather than another acceleration"
	)
	# Compare a complete multi-cycle timeline, not implementation-shaped frames.
	var reference: Dictionary = Motion.create(data)
	Motion.damage(reference, 41, 100, data)
	var reference_distance: float = Motion.advance(reference, data, 75.25, 374, 2)
	for frequency in [30, 60, 144]:
		var sampled: Dictionary = Motion.create(data)
		Motion.damage(sampled, 41, 100, data)
		var sampled_distance := 0.0
		var remaining := 75.25
		while remaining > .000000001:
			var step := minf(remaining, 1.0 / frequency)
			sampled_distance += Motion.advance(sampled, data, step, 374, 2)
			remaining -= step
		check(
			(
				absf(sampled_distance - reference_distance) < .00001
				and absf(sampled.speed - reference.speed) < .00001
				and absf(sampled.elapsed - reference.elapsed) < .00001
				and sampled.phase == reference.phase
				and sampled.decisions == reference.decisions
			),
			"Boost cycles and distance are independent of %d Hz stepping" % frequency
		)
		check(Motion.valid(sampled, data), "Sampled timeline remains valid")
	state = Motion.create(data)
	Motion.damage(state, 41, 100, data)
	Motion.advance(state, data, .4, 8, 3)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(Motion.valid(saved, data), "Boost component survives JSON round trip")
	var first: float = Motion.advance(state, data, 14, 8, 3)
	var second: float = Motion.advance(saved, data, 14, 8, 3)
	check(
		absf(first - second) < .00001 and same_saved_value(state, saved),
		"Saved acceleration and decisions continue identically"
	)
	for broken in [
		{"phase": "unknown"},
		{"speed": 101},
		{"speed": -1},
		{"elapsed": NAN},
		{"duration": 3},
		{"decisions": .5},
		{"damage": -1},
		{"forced": 1}
	]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.merge(broken, true)
		check(not Motion.valid(invalid, data), "Reject invalid saved boost state " + str(broken))
	for profile in [data.heavy, data.special]:
		var whole: Dictionary = Motion.proximity(40, data, profile, true, false, 1)
		var speed := 40.0
		var travel := 0.0
		for step in 144:
			var part: Dictionary = Motion.proximity(speed, data, profile, true, false, 1.0 / 144)
			speed = part.speed
			travel += part.distance
		check(
			absf(speed - whole.speed) < .00001 and absf(travel - whole.distance) < .00001,
			"Proximity gain and travel use nominal source rate across frame sizes"
		)
		var coast: Dictionary = Motion.proximity(speed, data, profile, false, false, 2)
		check(
			coast.speed == speed and coast.distance == 2 * speed,
			"Middle proximity band retains current speed"
		)
		var far: Dictionary = Motion.proximity(speed, data, profile, false, true, 20)
		check(
			(
				is_equal_approx(far.speed, profile.floor_speed)
				and far.distance > 20 * profile.floor_speed
			),
			"Distant fighters brake to the source floor and coast"
		)
		var below: Dictionary = Motion.proximity(
			profile.floor_speed * .5, data, profile, false, true, 1
		)
		check(
			(
				is_equal_approx(below.speed, profile.floor_speed)
				and is_equal_approx(below.distance, profile.floor_speed)
			),
			"Far speed below floor is raised to the source floor"
		)
	check(
		Motion.proximity(40, data, data.heavy, true, false, 10000).is_empty(),
		"Unrepresentable proximity growth is reported without inventing a speed cap"
	)


func check_fighter_motion_runtime(lib) -> void:
	var Motion = Session.Mission.FighterMotion
	var data: Dictionary = lib.content.fighter_motion
	var steering: Dictionary = lib.content.fighter_steering
	var group := {"actor": 0, "team": "enemy", "behavior": "interceptor"}
	check(
		Motion.mode(data, steering, group, {"kind": "campaign", "chapter": 2}) == "boost",
		"Ordinary enemies use timed boost"
	)
	group.team = "ally"
	check(
		Motion.mode(data, steering, group, {"kind": "campaign", "chapter": 2}) == "fixed",
		"Allies do not acquire enemy boost behavior"
	)
	group.team = "enemy"
	for actor_type in data.excluded_actors:
		group.actor = actor_type
		check(
			(
				Motion.mode(data, steering, group, {"kind": "contract", "chapter": 13})
				== ("heavy" if actor_type == steering.enhanced_actor else "fixed")
			),
			"Source excluded actor chooses correct motion mode"
		)
	var installed_data: Dictionary = JSON.parse_string(JSON.stringify(data))
	for excluded in installed_data.excluded_actors:
		group.actor = int(excluded)
		check(Motion.mode(installed_data, steering, group, {"kind":"contract", "chapter":13}) == ("heavy" if int(excluded) == int(steering.enhanced_actor) else "fixed"), "JSON numeric actor exclusion remains operative")
	group.actor = steering.special_actor
	check(
		(
			Motion.mode(
				data, steering, group, {"kind": "campaign", "chapter": steering.special_chapter}
			)
			== "special"
		),
		"Final special fighter uses proximity acceleration"
	)
	check(
		(
			Motion.mode(
				data, steering, group, {"kind": "survival", "chapter": steering.special_chapter}
			)
			== "boost"
		),
		"Survival does not inherit campaign specialization"
	)
	for chapter in lib.content.chapters.size():
		var definition: Dictionary = lib.mission_definition(chapter)
		var state: Dictionary = Session.Mission.create(definition, chapter, 0, lib, 452)
		var valid := true
		for item in state.actors:
			valid = (
				valid and Motion.valid_actor(item, definition.groups[int(item.group)], state, lib)
			)
		check(valid, "All initial actor speed states valid in chapter %d" % chapter)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Start actual motion encounter")
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	var definition: Dictionary = pilot.mission_definition()
	var position := Combat.vector(target.position)
	var player_position := position + Vector3(0, 0, -800)
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.05,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		(
			is_equal_approx(Combat.vector(target.position).distance_to(position), 2.0)
			and target.fighter_motion.speed == 40
		),
		"Live movement uses 40 units/s current speed, not 42 nominal"
	)
	check(
		is_equal_approx(Combat.vector(target.destruction.velocity).length(), 40),
		"Actual endpoint velocity recorded for wrecks and targeting"
	)
	var maximum: float = target.hp
	check(pilot.damage_actor(0, maximum * .41), "Apply real nonlethal damage")
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.5,
		player_position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		(
			target.fighter_motion.phase == "boost"
			and target.fighter_motion.speed == 60
			and target.fighter_motion.decisions == 1
		),
		"Live damage triggers source-derived boost"
	)
	check(
		is_equal_approx(Combat.vector(target.destruction.velocity).length(), 60),
		"Accelerating fighter records instantaneous velocity rather than average travel"
	)
	var saved: Dictionary = pilot.capture()
	var immutable := JSON.stringify(saved)
	var resumed := Session.new()
	resumed.configure(lib)
	check(
		resumed.restore(JSON.parse_string(immutable)),
		"Campaign23 restores active boost: " + resumed.error
	)
	if not resumed.active_job.is_empty():
		Session.Encounters.advance(
			definition,
			pilot.active_job,
			.1,
			player_position,
			Vector3.ZERO,
			pilot.combat,
			lib,
			pilot.actor_weapons()
		)
		Session.Encounters.advance(
			resumed.mission_definition(),
			resumed.active_job,
			.1,
			player_position,
			Vector3.ZERO,
			resumed.combat,
			lib,
			resumed.actor_weapons()
		)
		check(
			same_saved_value(target, resumed.active_job.actors[0]),
			"Campaign save continues identical position, speed and boost history"
		)
	check(JSON.stringify(saved) == immutable, "Motion restoration does not mutate save input")
	var before: Dictionary = resumed.capture()
	for mutation in [{"speed": 101}, {"phase": "bogus"}, {"elapsed": NAN}, {"hull_seen": -1}]:
		var bad: Dictionary = saved.duplicate(true)
		bad.active_job.actors[0].fighter_motion.merge(mutation, true)
		check(
			not resumed.restore(bad) and same_saved_value(before, resumed.capture()),
			"Malformed motion rejected atomically"
		)
	var old: Dictionary = saved.duplicate(true)
	old.schema = 22
	for item in old.active_job.actors:
		item.erase("fighter_motion")
	check(
		(
			resumed.restore(old)
			and resumed.active_job.actors[0].fighter_motion.speed == 40
			and resumed.active_job.actors[0].fighter_motion.decisions == 0
		),
		"Legacy save gains initial current speed without inventing prior boosts"
	)
	check(
		(
			resumed.active_job.actors[0].position == saved.active_job.actors[0].position
			and resumed.active_job.actors[0].hp == saved.active_job.actors[0].hp
			and resumed.credits == saved.credits
		),
		"Legacy migration preserves position, damage and rewards"
	)
	check(not old.active_job.actors[0].has("fighter_motion"), "Legacy migration is nonmutating")
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.ship.position = player_position
	view.throttle = 0
	var speed: float = target.fighter_motion.speed
	view.step(.05)
	check(target.fighter_motion.speed > speed, "Actual Flight advances dynamic fighter speed")
	view.paused = true
	var paused: Dictionary = target.duplicate(true)
	view.step(2)
	check(target == paused, "Modal pause freezes boost timers, current speed and movement")
	view.queue_free()
	await process_frame
	var momentum: Array = target.destruction.velocity.duplicate()
	check(pilot.damage_actor(0, target.hp), "Kill a boosted fighter")
	check(
		target.destruction.velocity == momentum and Combat.vector(momentum).length() > 40,
		"Boosted wreck retains actual death velocity"
	)
	check(
		resumed.restore(pilot.capture()),
		"Save validation accepts boosted wreck momentum: " + resumed.error
	)
	# Proximity profiles are exercised on actual chapter actors.
	for chapter in [5, 12]:
		var job_definition: Dictionary = lib.mission_definition(chapter)
		var job: Dictionary = Session.Mission.create(job_definition, chapter, 0, lib, 452)
		for index in job.actors.size():
			var actor: Dictionary = job.actors[index]
			var declaration: Dictionary = job_definition.groups[int(actor.group)]
			if (
				Motion.moving(declaration)
				and Motion.mode(data, steering, declaration, job) == "special"
			):
				Motion.step_actor(actor, declaration, job, lib, .25, index, Vector3.ZERO, true)
				check(
					(
						actor.fighter_motion.speed > 40
						and Motion.valid_actor(actor, declaration, job, lib)
					),
					"Campaign proximity acceleration produces valid current speed"
				)
				Motion.step_actor(actor, declaration, job, lib, 5, index, Vector3(2000, 0, 0), true)
				check(
					is_equal_approx(actor.fighter_motion.speed, data.special.floor_speed),
					"Campaign distant fighter reaches imported speed floor"
				)
				break
	var survival = preload("res://src/simulation/survival_session.gd").new()
	check(
		survival.configure_survival(lib, lib.content.survival, 0, 0, 452),
		"Create actual survival motion fixture"
	)
	var fighter: Dictionary = survival.active_job.actors[0]
	fighter.awake = true
	survival.damage_actor(0, fighter.hp * .41)
	Motion.step_actor(
		fighter,
		survival.arena.groups[0],
		survival.active_job,
		lib,
		.5,
		0,
		Vector3(0, 0, -800),
		true
	)
	var snapshot: Dictionary = survival.capture()
	var copy = preload("res://src/simulation/survival_session.gd").new()
	copy.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(snapshot))),
		"Survival6 restores boost component: " + copy.error
	)
	check(
		same_saved_value(fighter.fighter_motion, copy.active_job.actors[0].fighter_motion),
		"Survival preserves partial acceleration"
	)
	old = snapshot.duplicate(true)
	old.schema = 5
	for item in old.actors:
		item.erase("fighter_motion")
	check(
		copy.restore(old) and copy.active_job.actors[0].fighter_motion.speed == 40,
		"Survival5 migrates current speed"
	)
	before = copy.capture()
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.actors[int(snapshot.director.active_count)].fighter_motion.elapsed = 1
	check(
		not copy.restore(invalid) and same_saved_value(before, copy.capture()),
		"Unused survival reserve cannot invent boost history"
	)
	survival.damage_actor(0, fighter.hp)
	Session.Mission.Destruction.advance(
		fighter.destruction,
		Session.Mission.Destruction.effect(lib, int(survival.arena.groups[0].actor)),
		100
	)
	for tick in 2:
		var seconds: float = survival.declarations.rules.tick_ms / 1000.0 + .001
		survival.elapsed += seconds
		survival.advance_mission(seconds)
	check(
		(
			fighter.hp > 0
			and fighter.fighter_motion.speed == 40
			and fighter.fighter_motion.phase == "idle"
			and fighter.fighter_motion.hull_seen == fighter.hp
		),
		"Survival respawn starts a fresh speed and hull observation"
	)
	check(
		copy.restore(survival.capture()),
		"Respawn motion and promotion remain saveable: " + copy.error
	)


func check_fighter_motion_boundaries(lib, only_respawn: bool = false) -> void:
	var Motion = Session.Mission.FighterMotion
	var survival = preload("res://src/simulation/survival_session.gd").new()
	check(
		survival.configure_survival(lib, lib.content.survival, 0, 0, 452),
		"Create survival respawn fixture"
	)
	var fighter: Dictionary = survival.active_job.actors[0]
	fighter.awake = true
	survival.damage_actor(0, fighter.hp * .41)
	Motion.step_actor(
		fighter,
		survival.arena.groups[0],
		survival.active_job,
		lib,
		.5,
		0,
		Vector3(0, 0, -800),
		true
	)
	var prior_decisions: int = fighter.fighter_motion.decisions
	survival.damage_actor(0, fighter.hp)
	for tick in 200:
		survival.elapsed += .1
		survival.advance_mission(.1)
		if fighter.hp > 0:
			break
	check(
		(
			fighter.hp > 0
			and fighter.fighter_motion.speed == 40
			and fighter.fighter_motion.hull_seen == fighter.hp
		),
		"Elapsed source director stages produce fresh motion on respawn"
	)
	check(
		fighter.fighter_motion.decisions == prior_decisions,
		"Respawn preserves boost decision stream instead of repeating the first roll"
	)
	var copy = preload("res://src/simulation/survival_session.gd").new()
	copy.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		copy.restore(survival.capture()), "Completed respawn and speed are saveable: " + copy.error
	)
	var before: Dictionary = copy.capture()
	var bad: Dictionary = survival.capture()
	bad.actors[0].fighter_motion.hull_seen = survival.arena.groups[0].hull + 1
	check(
		not copy.restore(bad) and same_saved_value(before, copy.capture()),
		"Survival rejects invented observed hull atomically"
	)
	if only_respawn:
		return
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	pilot.depart()
	var actor: Dictionary = pilot.active_job.actors[0]
	var definition: Dictionary = pilot.mission_definition()
	var group: Dictionary = definition.groups[int(actor.group)]
	actor.awake = false
	var location: Array = actor.position.duplicate()
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		6,
		Vector3(1e7, 0, 0),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		(
			actor.position == location
			and actor.fighter_motion.speed == 40
			and actor.fighter_motion.elapsed == 6
			and actor.fighter_motion.decisions == 0
		),
		"Sleeping fighters age decision timer without moving or deciding"
	)
	actor.awake = true
	Session.Encounters.advance(
		definition,
		pilot.active_job,
		.01,
		Combat.vector(actor.position) + Vector3(0, 0, -500),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		actor.fighter_motion.decisions == 1 and actor.fighter_motion.speed > 40,
		"Awakened fighter consumes elapsed decision opportunity"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(
		restored.restore(pilot.capture()),
		"Sleeping timer continuation remains saveable: " + restored.error
	)
	bad = pilot.capture()
	bad.active_job.actors[0].fighter_motion.hull_seen = (
		lib.group_initial_hull(group, int(pilot.active_job.rank)) + 1
	)
	check(not restored.restore(bad), "Campaign rejects invented observed hull")
	var declarations: Dictionary = definition.duplicate(true)
	declarations.sequence = [
		{
			"when": {"kind": "hull_below", "actor": 0, "value": 1e8},
			"actions": [{"kind": "speed", "actor": 0, "value": 1e6}]
		}
	]
	var state: Dictionary = pilot.active_job.duplicate(true)
	state.sequence_cursor = 1
	state.actors[0].fighter_motion = Motion.create(lib.content.fighter_motion, float(actor.hp))
	location = state.actors[0].position.duplicate()
	Session.Encounters.advance(
		declarations,
		state,
		.05,
		Combat.vector(location) + Vector3(0, 0, -500),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		is_equal_approx(
			Combat.vector(state.actors[0].position).distance_to(Combat.vector(location)), 2
		),
		"Generic source speed setter metadata cannot override fighter current speed"
	)
	# Migration resolves actual group types, including static turrets.
	var legacy_actors: Array = [
		{"group": 0, "hp": 10, "heading": [0, 0, -1]}, {"group": 1, "hp": 10, "heading": [0, 0, -1]}
	]
	check(
		(
			Motion.migrate(
				legacy_actors,
				lib.content.fighter_motion,
				[{"behavior": "interceptor"}, {"behavior": "turret"}]
			)
			and legacy_actors[0].has("fighter_motion")
			and not legacy_actors[1].has("fighter_motion")
		),
		"Migration attaches speed only to moving fighter groups"
	)


func check_npc_exhaust(source: PackedByteArray, lib) -> void:
	var Burner = preload("res://src/presentation/npc_exhaust.gd")
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data: Dictionary = reader.npc_exhaust()
	check(
		not data.is_empty() and reader.error.is_empty(), "Read NPC burner envelope: " + reader.error
	)
	if data.is_empty():
		return
	check(
		data.boost_threshold == 100 and data.pulse_fraction == .05,
		"Source boost threshold and pulse amplitude"
	)
	check(
		(
			data.attack_seconds == .3
			and data.attack_limit == 6000.0 / 65536
			and data.sustain_limit == 9000.0 / 65536
		),
		"Source two-stage burner expansion"
	)
	check(
		(
			is_equal_approx(data.normal_phase_rate / TAU, 15.625)
			and is_equal_approx(data.boost_phase_rate / TAU, 3.90625)
		),
		"Source sine period and mode frequencies"
	)
	for address in [
		0x566f6,
		0x56704,
		0x5670e,
		0x65030,
		0x685f0,
		0x64ecc,
		0x64ece,
		0x64efc,
		0x64f00,
		0x64f48,
		0x64f72,
		0x64f78,
		0x64f9e,
		0x64fe2,
		0xa962
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.npc_exhaust().is_empty() and not reader.error.is_empty(),
			"Reject altered burner semantics %x" % address
		)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_float(literal_file_offset(reader, 0x64e16), 10.0)
	check(
		reader.npc_exhaust().get("pulse_fraction") == .1, "Pulse amplitude comes from source data"
	)
	reader.bytes = source.duplicate()
	reader.error = ""
	reader.bytes.encode_u16(
		reader.file_offset(0x64f00, 2), (reader.u16(0x64f00) & ~0x7c0) | (5 << 6)
	)
	check(
		reader.npc_exhaust().get("attack_rate") == data.attack_rate * .5,
		"Source rate change is converted to native time"
	)
	for mutation in [
		{"boost_threshold": 0},
		{"pulse_fraction": 1},
		{"release_rate": NAN},
		{"sustain_limit": 0},
		{"minimum_fraction": 2}
	]:
		var bad: Dictionary = data.duplicate(true)
		bad.merge(mutation, true)
		check(not Burner.valid_data(bad), "Reject malformed burner declaration")
	var kind := 0
	for index in lib.content.ship_exhaust.actors.size():
		if lib.content.ship_exhaust.actors[index].size() >= 3:
			kind = index
			break
	var hull: MeshInstance3D = lib.model(lib.actor_model(kind))
	root.add_child(hull)
	lib.attach_ship_exhaust(hull, kind)
	var burner = Burner.new()
	hull.add_child(burner)
	burner.configure(data, hull)
	check(
		burner.nozzles.size() == lib.content.ship_exhaust.actors[kind].size(),
		"Controller discovers all original nozzles"
	)
	var positions: Array = []
	for nozzle in burner.nozzles:
		positions.append(nozzle.position)
		check(
			nozzle.mesh != null and nozzle.scale == nozzle.get_meta("exhaust_scale"),
			"Original mesh starts at its imported dimensions"
		)
	burner.advance(.016, 40)
	check(
		not burner.boosting and burner.extension == 0 and burner.phase > 0,
		"Cruise pulses without boost expansion"
	)
	var phase: float = burner.phase
	var scale_before: Vector3 = burner.nozzles[0].scale
	for seconds in [0, -1, NAN, INF]:
		burner.advance(seconds, 100)
	check(
		burner.phase == phase and burner.nozzles[0].scale == scale_before,
		"Zero or invalid steps cannot animate paused effects"
	)
	burner.advance(.1, 99.99)
	check(
		not burner.boosting and burner.extension == 0,
		"Acceleration below threshold does not activate burner expansion"
	)
	burner.advance(.1, 100)
	check(
		burner.boosting and is_equal_approx(burner.extension, data.attack_limit),
		"Threshold starts source attack envelope"
	)
	burner.advance(.5, 100)
	check(
		is_equal_approx(burner.extension, data.sustain_limit),
		"Sustained boost reaches original expansion limit"
	)
	var extension: float = burner.extension
	burner.advance(.25, 40)
	check(
		(
			not burner.boosting
			and is_equal_approx(burner.extension, extension - data.release_rate * .25)
		),
		"Leaving boost eases expansion away"
	)
	burner.advance(2, 40)
	check(burner.extension == 0, "Release returns to pulsing cruise dimensions")
	for index in burner.nozzles.size():
		check(
			burner.nozzles[index].position == positions[index],
			"Envelope never moves source nozzle mounts"
		)
	var reference = Burner.new()
	reference.data = data
	# This parameter-only fixture isolates envelope timing from geometry.
	reference.advance(.7, 100)
	reference.advance(.2, 40)
	for frequency in [30, 60, 144]:
		var sampled = Burner.new()
		sampled.data = data
		for segment in [[.7, 100.0], [.2, 40.0]]:
			var remaining: float = segment[0]
			while remaining > .000000001:
				var dt := minf(remaining, 1.0 / frequency)
				sampled.advance(dt, segment[1])
				remaining -= dt
		check(
			(
				absf(sampled.extension - reference.extension) < .0000001
				and absf(sampled.phase - reference.phase) < .0000001
			),
			"Burner envelope and pulse independent of %d Hz" % frequency
		)
		sampled.free()
	reference.free()
	hull.queue_free()
	await process_frame
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Launch actual NPC burner encounter")
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	Session.Mission.FighterMotion.damage(
		target.fighter_motion, target.hp * .41, target.hp, lib.content.fighter_motion
	)
	Session.Mission.FighterMotion.advance(
		target.fighter_motion, lib.content.fighter_motion, 2, 452, 0
	)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.ship.position = Combat.vector(target.position) + Vector3(0, 0, -800)
	view.throttle = 0
	var visual: Dictionary = {}
	for actor in view.actors:
		if int(actor.index) == 0:
			visual = actor
	check(
		not visual.is_empty() and visual.node.has_meta("npc_exhaust"),
		"Actual original hull owns NPC burner controller"
	)
	var active = visual.node.get_meta("npc_exhaust")
	view.step(.1)
	check(
		active.boosting and active.extension > 0, "Flight current speed activates nozzle expansion"
	)
	view.paused = true
	phase = active.phase
	extension = active.extension
	view.step(2)
	check(
		active.phase == phase and active.extension == extension,
		"Actual pause freezes NPC burner state"
	)
	view.paused = false
	var saved: Dictionary = pilot.capture()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(saved),
		"Burner presentation does not change gameplay save shape: " + copy.error
	)
	var restored_view := Flight.new()
	root.add_child(restored_view)
	restored_view.setup(lib, copy, {}, true)
	restored_view.set_physics_process(false)
	var restored_burner = null
	for actor in restored_view.actors:
		if int(actor.index) == 0:
			restored_burner = actor.node.get_meta("npc_exhaust")
	check(
		restored_burner != null and restored_burner.extension == 0,
		"Reload rebuilds cosmetic pulse without inventing saved visual history"
	)
	# Use the production destruction path so the same hull owns its fading burner.
	pilot.damage_actor(0, target.hp)
	view.spawn_targets()
	var wreck = view.wrecks[0]
	check(
		wreck.body == visual.node, "Destroyed fighter transfers original hull and burner to wreck"
	)
	phase = active.phase
	view.step(.1)
	check(
		active.phase != phase and not active.boosting and active.extension < extension,
		"Slowing wreck releases the burner envelope"
	)
	check(wreck.body.get_meta("npc_exhaust") == active, "Wreck retains its own controller")
	var weak: WeakRef = weakref(active)
	view.queue_free()
	restored_view.queue_free()
	await process_frame
	check(weak.get_ref() == null, "Freeing Flight releases nozzle controllers with their hulls")


func check_npc_exhaust_respawn(lib) -> void:
	var survival = preload("res://src/simulation/survival_session.gd").new()
	check(
		survival.configure_survival(lib, lib.content.survival, 0, 0, 452),
		"Create survival burner lifecycle"
	)
	var fighter: Dictionary = survival.active_job.actors[0]
	Session.Mission.FighterMotion.damage(
		fighter.fighter_motion, fighter.hp * .41, fighter.hp, lib.content.fighter_motion
	)
	Session.Mission.FighterMotion.advance(
		fighter.fighter_motion, lib.content.fighter_motion, 2, 452, 0
	)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, survival, {}, true)
	view.set_physics_process(false)
	view.ship.position = Vector3(10000, 0, 10000)
	view.throttle = 0
	view.step(.1)
	var body: Node3D = null
	for actor in view.actors:
		if int(actor.index) == 0:
			body = actor.node
	var burner = body.get_meta("npc_exhaust")
	check(
		burner.boosting and burner.extension > 0, "Survival current speed expands original nozzles"
	)
	var previous: WeakRef = weakref(burner)
	survival.damage_actor(0, fighter.hp)
	view.spawn_targets()
	check(
		view.wrecks[0].body == body,
		"Survival death keeps the same burner attached to its original wreck"
	)
	for tick in 200:
		view.step(.1)
		if fighter.hp > 0:
			break
	var replacement: Node3D = null
	for actor in view.actors:
		if int(actor.index) == 0:
			replacement = actor.node
	check(
		fighter.hp > 0 and replacement != null and replacement != body,
		"Actual survival director creates a distinct replacement hull"
	)
	if replacement != null:
		var fresh = replacement.get_meta("npc_exhaust")
		check(
			fresh != previous.get_ref() and fresh.extension == 0 and not fresh.boosting,
			"Replacement never inherits an older wreck's boost envelope"
		)
		view.step(.1)
		check(fresh.phase > 0, "New survival hull advances its own pulse")
	view.queue_free()
	await process_frame
	check(previous.get_ref() == null, "Completed survival wreck releases its old burner")


func check_fighter_frame(source: PackedByteArray, lib) -> void:
	var Frame = Session.Mission.Frame
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(
		not reader.fighter_steering().is_empty(),
		"Verify source carried-up frame consumer: " + reader.error
	)
	for address in [0x56570, 0x5657a, 0x56594, 0x565b2]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_steering().is_empty(),
			"Reject changed source frame consumer %x" % address
		)
	var actor: Dictionary = {"heading": [0, 0, -1], "up": [1, 0, 0]}
	Frame.turn(actor, Vector3.FORWARD)
	check(
		actor.up == [1.0, 0.0, 0.0],
		"Bank survives a straight flight step instead of resetting to world-up"
	)
	Frame.turn(actor, Vector3(0, .3, -1).normalized())
	check(
		Combat.vector(actor.up).is_equal_approx(Vector3.RIGHT) and Frame.valid(actor),
		"Carried bank stays perpendicular through a turn"
	)
	Frame.turn(actor, Vector3.RIGHT)
	check(Frame.valid(actor), "Large turn along old up produces a finite body frame")
	var hull_pose := Frame.axes(Combat.vector(actor.heading), Combat.vector(actor.up))
	check(
		is_equal_approx(hull_pose.determinant(), 1),
		"Native frame stays orthonormal and right-handed"
	)
	var history: Dictionary = {"heading": [0, 0, -1], "up": [0, 1, 0]}
	for direction in [
		Vector3(1, 1, -1).normalized(),
		Vector3(1, 1, 1).normalized(),
		Vector3(0, 1, 1).normalized(),
		Vector3.FORWARD
	]:
		Frame.turn(history, direction)
	check(
		Frame.valid(history) and not Combat.vector(history.up).is_equal_approx(Vector3.UP),
		"Three-dimensional turn history retains orientation rather than horizon-locking"
	)
	for bad_up in [[0, 0, 0], [0, 0, -1], [0, 2, 0], [NAN, 0, 0]]:
		check(
			not Frame.valid({"heading": [0, 0, -1], "up": bad_up}),
			"Invalid saved up vector rejected"
		)
	var banked: Dictionary = {
		"heading": [0, 0, -1],
		"up": [1, 0, 0],
		"evasion": Session.Mission.Evasion.create(),
		"breaking": false
	}
	var lateral: Vector3 = Session.Mission.Evasion.desired(
		banked, Vector3.ZERO, 100, [[0, 1, 0]], 452, 0
	)
	check(lateral.is_equal_approx(Vector3.RIGHT), "Imported up maneuver uses ship-up when banked")
	var muzzle := Session.Encounters.mount_origin(
		Vector3.ZERO, Vector3.FORWARD, {"mount_offset": [0, 100, 0]}, Vector3.RIGHT
	)
	check(
		muzzle.is_equal_approx(Vector3(2, 0, 0)), "Weapon mount follows the same bank as the mesh"
	)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Launch carried-frame encounter")
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	target.up = [1, 0, 0]
	var position := Combat.vector(target.position) + Vector3(0, 0, -500)
	Session.Encounters.advance(
		pilot.mission_definition(),
		pilot.active_job,
		.05,
		position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(Combat.vector(target.up).is_equal_approx(Vector3.RIGHT), "Live encounter preserves bank")
	var saved: Dictionary = pilot.capture()
	var immutable := JSON.stringify(saved)
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(immutable)),
		"Campaign24 restores full fighter frame: " + copy.error
	)
	check(same_saved_value(target.up, copy.active_job.actors[0].up), "Bank remains saved")
	var previous: Dictionary = copy.capture()
	var bad: Dictionary = saved.duplicate(true)
	bad.active_job.actors[0].up = bad.active_job.actors[0].heading.duplicate()
	check(
		not copy.restore(bad) and same_saved_value(previous, copy.capture()),
		"Nonorthogonal orientation rejected atomically"
	)
	var old: Dictionary = saved.duplicate(true)
	old.schema = 23
	for item in old.active_job.actors:
		item.erase("up")
	check(copy.restore(old), "Campaign23 migration reconstructs previous displayed orientation")
	check(
		Combat.vector(copy.active_job.actors[0].up).is_equal_approx(
			Frame.axes(Combat.vector(target.heading)).y
		),
		"Legacy migration reproduces prior world-up pose"
	)
	check(
		not old.active_job.actors[0].has("up") and JSON.stringify(saved) == immutable,
		"Frame migration does not mutate input"
	)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.ship.position = position
	view.throttle = 0
	var node: Node3D = null
	for item in view.actors:
		if int(item.index) == 0:
			node = item.node
	check(
		node.basis.y.is_equal_approx(Vector3.RIGHT),
		"Loaded original hull and nozzles render saved bank"
	)
	view.step(.05)
	check(
		node.basis.y.is_equal_approx(Combat.vector(target.up)),
		"Flight renderer follows updated body frame"
	)
	view.paused = true
	var paused: Dictionary = target.duplicate(true)
	view.step(1)
	check(target == paused, "Pause preserves body frame")
	pilot.damage_actor(0, target.hp)
	view.spawn_targets()
	check(
		view.wrecks[0].body.global_basis.y.is_equal_approx(Combat.vector(target.up)),
		"Wreck inherits bank at destruction"
	)
	view.queue_free()
	await process_frame
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	survival.active_job.actors[0].up = [1, 0, 0]
	var snapshot: Dictionary = survival.capture()
	var restored = preload("res://src/simulation/survival_session.gd").new()
	restored.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(snapshot))),
		"Survival7 restores full frame: " + restored.error
	)
	check(
		Combat.vector(restored.active_job.actors[0].up).is_equal_approx(Vector3.RIGHT),
		"Survival bank survives restore"
	)
	old = snapshot.duplicate(true)
	old.schema = 6
	for item in old.actors:
		item.erase("up")
	check(restored.restore(old), "Survival6 gains legacy orientation")
	previous = restored.capture()
	bad = snapshot.duplicate(true)
	bad.actors[0].up = [0, 0, 0]
	check(
		not restored.restore(bad) and same_saved_value(previous, restored.capture()),
		"Survival rejects invalid frame atomically"
	)


func check_fighter_frame_boundaries(lib) -> void:
	var Frame = Session.Mission.Frame
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	pilot.depart()
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	target.up = [1, 0, 0]
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	pilot.damage_actor(0, target.hp)
	view.spawn_targets()
	check(
		view.wrecks[0].body.global_basis.y.is_equal_approx(Vector3.RIGHT),
		"Wreck preserves world bank after reparenting below explosion"
	)
	view.step(.05)
	check(
		view.wrecks[0].body.global_basis.y.is_equal_approx(Vector3.RIGHT),
		"Wreck drift does not reset inherited bank"
	)
	var restored := Session.new()
	restored.configure(lib)
	check(restored.restore(pilot.capture()), "Banked wreck remains saveable")
	view.queue_free()
	await process_frame
	for chapter in lib.content.chapters.size():
		var definition: Dictionary = lib.mission_definition(chapter)
		var state: Dictionary = Session.Mission.create(definition, chapter, 0, lib, 452)
		var valid := true
		for actor in state.actors:
			if actor.has("heading"):
				valid = valid and Frame.valid(actor)
		check(valid, "All initial body frames valid in chapter %d" % chapter)
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var fighter: Dictionary = survival.active_job.actors[0]
	fighter.up = [1, 0, 0]
	survival.damage_actor(0, fighter.hp)
	for tick in 200:
		survival.elapsed += .1
		survival.advance_mission(.1)
		if fighter.hp > 0:
			break
	check(
		fighter.hp > 0 and Frame.valid(fighter) and fighter.up == [1, 0, 0],
		"Survival revive preserves the actor's carried orientation"
	)
	var resumed = preload("res://src/simulation/survival_session.gd").new()
	resumed.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(resumed.restore(survival.capture()), "Respawned banked fighter restores successfully")
	var bad_legacy: Array = [{"heading": [0, 0, 0]}]
	check(not Frame.migrate(bad_legacy), "Legacy invalid heading cannot manufacture a valid frame")


func check_fighter_maximum_hull(source: PackedByteArray, lib) -> void:
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	check(not reader.fighter_motion().is_empty(), "Source maximum-hull setter semantics supported")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x52eae, 2), 0xbf00)
	reader.error = ""
	check(reader.fighter_motion().is_empty(), "Changed maximum-hull consumer rejected")
	var definition: Dictionary = lib.mission_definition(11)
	var job: Dictionary = Session.Mission.create(definition, 11, 0, lib, 452)
	var index := 25
	var actor: Dictionary = job.actors[index]
	var group: Dictionary = definition.groups[int(actor.group)]
	var initial: float = lib.group_initial_hull(group, int(job.rank))
	var applied := -1
	var raised := initial
	for cursor in definition.sequence.size():
		for action in definition.sequence[cursor].actions:
			if action.kind == "health" and int(action.actor) == index and action.value > raised:
				applied = cursor + 1
				raised = action.value
	check(applied >= 0 and raised > initial, "Source chapter has the larger scripted hull")
	job.sequence_cursor = applied
	actor.awake = true
	actor.hp = raised
	actor.fighter_motion = Session.Mission.FighterMotion.create(lib.content.fighter_motion, raised)
	actor.hp -= initial * .5
	var maximum: float = Session.Mission.Sequence.maximum_hull(definition, job, index, initial)
	check(maximum == raised, "Boost damage denominator follows actual increased maximum hull")
	Session.Encounters.advance(
		definition,
		job,
		.01,
		Combat.vector(actor.position) + Vector3(0, 0, -600),
		Vector3.ZERO,
		Combat.create(),
		lib,
		lib.definition_weapons(definition, int(job.rank))
	)
	check(
		actor.fighter_motion.decisions == 0 and not actor.fighter_motion.forced,
		"Small damage to scripted high-hull fighter cannot request a boost against its old hull"
	)
	job.sequence_cursor = definition.sequence.size()
	check(
		Session.Mission.Sequence.maximum_hull(definition, job, index, initial) == raised,
		"Later current-health reductions do not reduce maximum hull"
	)


func check_fighter_frame_camera(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 12
	pilot.progression = Session.Progression.create(12)
	pilot.station_id = lib.chapter_destination(11)
	check(pilot.depart(), "Create source final-chapter relative camera scene")
	pilot.active_job.sequence_cursor = 2
	var focus: Dictionary = (
		Session.Mission.Sequence.directives(pilot.mission_definition(), pilot.active_job).focus
	)
	check(
		focus.get("relative", false) and int(focus.actor) >= 0,
		"Source camera uses an actor-relative transform"
	)
	var actor: Dictionary = pilot.active_job.actors[int(focus.actor)]
	actor.up = [1, 0, 0]
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.update_camera(1)
	var expected: Vector3 = (
		Combat.vector(actor.position)
		+ (
			Session.Mission.Frame.axes(Combat.vector(actor.heading), Combat.vector(actor.up))
			* Session.Mission.point(focus.offset)
		)
	)
	check(
		view.camera.position.distance_to(expected) < .001,
		"Relative cinematic camera offset follows the saved body bank"
	)
	view.queue_free()
	await process_frame


func check_fighter_impact(source: PackedByteArray, lib) -> void:
	var Impact = Session.Mission.Impact
	var data: Dictionary = lib.content.fighter_impact
	check(Impact.valid_parameters(data, lib), "Imported impact declarations validate")
	check(
		data.duration == 3 and is_equal_approx(data.rotation_rate, TAU * 8000 / 65536),
		"Source impact duration and local pitch rate"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [
		0x2f6ec, 0x2f9d2, 0x30736, 0x308a2, 0x32322, 0x32ff2, 0x5633e, 0x551ae,
		0x2664a,
		0x26604,
		0x5640c,
		0x267bc,
		0x5b494,
		0x33750,
		0x3a3da,
		0x30172,
		0x336ec,
		0x5663a,
		0x563f2
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(reader.fighter_impact().is_empty(), "Reject changed impact source %x" % address)
	reader.bytes = source
	reader.error = ""
	var ordinary: Dictionary = reader.interceptor_combat().weapon
	var heavy: Dictionary = reader.rocket_weapon(18)
	check(
		not ordinary.get("rocket_impact", true) and heavy.get("rocket_impact", false),
		"Source NPC gun effects distinguish ordinary and rocket impact: " + reader.error
	)
	for key in data.player_flags:
		var expected: bool = int(key) in [3, 4, 5, 27]
		check(
			data.player_flags[key] == expected, "Source impact association for player weapon " + key
		)
	check(
		not Impact.rocket(12, lib, {}) and Impact.rocket(4 + lib.items.size(), lib, {}),
		"Rocket art does not grant impact; extra missile muzzle retains it"
	)
	check(
		not Impact.rocket(3, lib, {"legacy_projectile": true}),
		"Old projectile keeps pre-impact behavior"
	)
	check(
		Impact.rocket(-1, lib, heavy) and not Impact.rocket(-1, lib, ordinary),
		"NPC impact uses imported gun flag"
	)
	var base: Dictionary = {
		"hp": 100,
		"heading": [0, 0, -1],
		"up": [0, 1, 0],
		"position": [0, 0, 0],
		"fighter_motion": {"speed": 40},
		"destruction": Session.Mission.Destruction.create(),
		"impact": Impact.create()
	}
	var reference: Dictionary = {}
	for frequency in [30, 60, 144]:
		var actor: Dictionary = base.duplicate(true)
		Impact.receive(actor, Vector3.RIGHT * 360, data)
		for tick in frequency:
			Impact.advance(actor, 40.0 / frequency, 1.0 / frequency, data)
		check(
			is_equal_approx(Combat.vector(actor.position).x, 360.0 * data.travel_scale * 40),
			"Frame-independent modest drift at %d Hz" % frequency
		)
		check(
			Session.Mission.Frame.valid(actor) and Impact.valid(actor, data),
			"Tumbled body frame and impact validate at %d Hz" % frequency
		)
		if reference.is_empty():
			reference = actor
		else:
			check(
				Combat.vector(actor.heading).distance_to(Combat.vector(reference.heading)) < .00001,
				"Pitch independent of rendering frequency"
			)
	var actor: Dictionary = reference.duplicate(true)
	Impact.receive(actor, Vector3.UP * 360, data)
	check(
		is_equal_approx(actor.impact.elapsed, 1.0) and Combat.vector(actor.impact.vector).y > 0,
		"Second hit redirects drift without resetting recovery"
	)
	Impact.advance(actor, 80, 2, data)
	check(
		not actor.impact.active and Impact.valid(actor, data),
		"Reaction clears at native continuous three-second boundary"
	)
	for bad in [
		null,
		{},
		{"active": true, "elapsed": -1, "vector": [0, 0, 0]},
		{"active": false, "elapsed": 1, "vector": [0, 0, 0]},
		{"active": true, "elapsed": 0, "vector": [NAN, 0, 0]}
	]:
		actor.impact = bad
		check(not Impact.valid(actor, data), "Malformed saved impact is rejected")
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.progression = Session.Progression.create(2)
	pilot.station_id = lib.chapter_destination(1)
	check(pilot.depart(), "Launch impact encounter")
	var target: Dictionary = pilot.active_job.actors[0]
	target.awake = true
	var position := Combat.vector(target.position) + Vector3(0, 0, -500)
	Impact.receive(target, Vector3.RIGHT * 360, data)
	Session.Encounters.advance(
		pilot.mission_definition(),
		pilot.active_job,
		.5,
		position,
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		target.impact.active and target.shots == 0 and Combat.vector(target.heading).y < 0,
		"Actual fighter tumbles and suppresses fire"
	)
	check(
		Combat.vector(target.destruction.velocity).length() < target.fighter_motion.speed,
		"Saved actual velocity uses source displacement factor"
	)
	var saved: Dictionary = pilot.capture()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(saved))),
		"Campaign25 restores ongoing reaction: " + copy.error
	)
	check(
		same_saved_value(copy.active_job.actors[0].impact, target.impact),
		"Campaign preserves drift and recovery time"
	)
	var before: Dictionary = copy.capture()
	var bad: Dictionary = saved.duplicate(true)
	bad.active_job.actors[0].impact.elapsed = data.duration
	check(
		not copy.restore(bad) and same_saved_value(copy.capture(), before),
		"Invalid impact load is atomic"
	)
	var old: Dictionary = saved.duplicate(true)
	old.schema = 24
	for item in old.active_job.actors:
		item.erase("impact")
	check(
		copy.restore(old) and not copy.active_job.actors[0].impact.active,
		"Old save gains idle reaction without replaying a hit"
	)
	check(not old.active_job.actors[0].has("impact"), "Impact migration leaves input untouched")
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.ship.position = position
	view.throttle = 0
	var snapshot: Dictionary = target.duplicate(true)
	view.paused = true
	view.step(1)
	check(same_saved_value(target, snapshot), "Modal pause freezes impact, motion and firing")
	view.paused = false
	view.step(.1)
	var rendered := false
	for item in view.actors:
		if int(item.index) == 0:
			rendered = item.node.basis.y.is_equal_approx(Combat.vector(target.up))
	check(rendered, "Original ship and nozzles follow impact frame")
	view.queue_free()
	await process_frame
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	Impact.receive(survival.active_job.actors[0], Vector3.RIGHT * 360, data)
	var survival_save: Dictionary = survival.capture()
	var restored = preload("res://src/simulation/survival_session.gd").new()
	restored.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(survival_save))),
		"Survival8 restores impact: " + restored.error
	)
	check(restored.active_job.actors[0].impact.active, "Survival preserves active response")
	old = survival_save.duplicate(true)
	old.schema = 7
	for item in old.actors:
		item.erase("impact")
	check(
		restored.restore(old) and not restored.active_job.actors[0].impact.active,
		"Survival7 migration does not invent past impacts"
	)
	before = restored.capture()
	bad = survival_save.duplicate(true)
	bad.actors[0].impact.vector = [INF, 0, 0]
	check(
		not restored.restore(bad) and same_saved_value(before, restored.capture()),
		"Survival rejects malformed impact atomically"
	)


func check_fighter_impact_boundaries(
	lib, weapons: Array = [], respawn: bool = true, heavy: bool = true
) -> void:
	var Impact = Session.Mission.Impact
	var data: Dictionary = lib.content.fighter_impact
	# Use actual ballistic collision, damage dispatch and original rendered actors.
	if weapons.is_empty():
		weapons = [0, 3, 4 + lib.items.size(), 12]
	for weapon in weapons:
		var pilot := Session.new()
		pilot.configure(lib)
		pilot.chapter = 5
		pilot.progression = Session.Progression.create(5)
		pilot.station_id = lib.chapter_destination(4)
		check(pilot.depart(), "Launch native impact collision")
		var target: Dictionary = pilot.active_job.actors[0]
		target.awake = true
		var before: float = target.hp
		var view := Flight.new()
		root.add_child(view)
		view.setup(lib, pilot, {}, true)
		view.set_physics_process(false)
		view.ship.position = Combat.vector(target.position) + Vector3(0, 0, 300)
		view.throttle = 0
		var weapons_for_slot: Array[int] = pilot.player_weapon_ids(weapon % lib.items.size())
		var origins: Array[Vector3] = []
		for muzzle in weapons_for_slot:
			origins.append(Combat.vector(target.position))
		check(
			Combat.fire_volley(
				pilot.combat, weapons_for_slot, origins, Vector3.FORWARD, lib, pilot.actor_weapons()
			),
			"Launch imported volley containing projectile " + str(weapon)
		)

		view.step(.01)
		check(
			target.hp < before and target.hp > 0,
			"Native projectile applies nonfatal hit " + str(weapon)
		)
		check(
			target.impact.active == Impact.rocket(weapon, lib, {}),
			"Flight dispatch retains original impact class " + str(weapon)
		)
		if target.impact.active:
			view.step(.1)
			pilot.damage_actor(0, target.hp)
			view.spawn_targets()
			check(
				(
					not view.wrecks.is_empty()
					and view.wrecks[0].body.global_basis.y.is_equal_approx(Combat.vector(target.up))
				),
				"Death preserves tumbled hull pose"
			)
			var restored := Session.new()
			restored.configure(lib)
			check(
				restored.restore(pilot.capture()),
				"Unfinished wreck retains impact and drift through save: " + restored.error
			)
		view.queue_free()
		await process_frame
	if not heavy:
		return
	# Actor18 explicitly bypasses the rotation/timer branch, retaining the source
	# firing latch. A timeout must not be fabricated for this separate source path.
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 10
	pilot.progression = Session.Progression.create(10)
	pilot.station_id = lib.chapter_destination(9)
	check(pilot.depart(), "Launch heavy reaction source scenario")
	var selected := -1
	for index in pilot.active_job.actors.size():
		var group: Dictionary = pilot.mission_definition().groups[int(
			pilot.active_job.actors[index].group
		)]
		if (
			int(group.actor) == int(data.no_tumble_actor)
			and pilot.active_job.actors[index].has("fighter_motion")
		):
			selected = index
			break
	if selected >= 0:
		var target: Dictionary = pilot.active_job.actors[selected]
		target.awake = true
		Impact.receive(target, Vector3.RIGHT * 360, data)
		var shots: int = target.shots
		var position := Combat.vector(target.position) + Vector3(0, 0, -500)
		Session.Encounters.advance(
			pilot.mission_definition(),
			pilot.active_job,
			4,
			position,
			Vector3.ZERO,
			pilot.combat,
			lib,
			pilot.actor_weapons()
		)
		check(
			target.impact.active and target.impact.elapsed == 0 and target.shots == shots,
			"Heavy bypass does not acquire a fabricated three-second timer"
		)
	else:
		check(false, "Find imported heavy actor for response boundary")
	if not respawn:
		return
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var fighter: Dictionary = survival.active_job.actors[0]
	Impact.receive(fighter, Vector3.RIGHT * 360, data)
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, survival, {}, true)
	view.set_physics_process(false)
	view.ship.position = Vector3(10000, 0, 10000)
	view.throttle = 0
	survival.damage_actor(0, fighter.hp)
	view.spawn_targets()
	for tick in 200:
		view.step(.1)
		if fighter.hp > 0:
			break
	check(
		fighter.hp > 0 and not fighter.impact.active and fighter.impact.elapsed == 0,
		"Actual survival revival clears prior reaction"
	)
	check(
		survival.restore(survival.capture()),
		"Revived actor saves with idle reaction: " + survival.error
	)
	view.queue_free()
	await process_frame


func check_fighter_targeting(source: PackedByteArray, lib) -> void:
	var Targeting = Session.Mission.Targeting
	var data: Dictionary = lib.content.fighter_targeting
	check(
		(
			Targeting.valid_data(data)
			and data.interval == 5
			and data.attempts == 5
			and is_equal_approx(data.half_width, 999.98)
		),
		"Source targeting interval, retries and acquisition extent"
	)
	check(
		data.normal_chance == 30 and data.enhanced_chance == 60 and data.chance_out_of == 100,
		"Source ordinary and special selection probabilities"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [
		0x55b88, 0x55bd0, 0x55c0e, 0x55d2c, 0x55d86, 0x55d64, 0x55c9c, 0x29cfe, 0x480b8
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_targeting().is_empty(),
			"Reject unsupported target policy at %x" % address
		)
	var roster: Array = [
		{"id": -1, "team": "ally", "position": Vector3(900, 0, 0), "active": true},
		{"id": 3, "team": "ally", "position": Vector3(100, 0, 0), "active": true},
		{"id": 4, "team": "enemy", "position": Vector3.ZERO, "active": true},
		{"id": 5, "team": "neutral", "position": Vector3.ZERO, "active": true}
	]
	var enemies := Targeting.opponents(roster, "enemy")
	check(
		enemies.size() == 2 and enemies[0].id == -1 and enemies[1].id == 3,
		"Opponent roster preserves pilot-first order and excludes friendly/neutral objects"
	)
	var value: Dictionary = Targeting.create()
	var target: Dictionary = Targeting.advance(
		value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, false
	)
	check(target.id == -1, "Ordinary scan chooses original first opponent, not nearer wingmate")
	roster[0].active = false
	target = Targeting.advance(value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, false)
	check(
		target.id == 3 and enemies.size() == 2,
		"Inactive slot retains roster membership while ordinary scan skips it"
	)
	roster[0].active = true
	value.selected = 3
	value.held = true
	roster[1].position = Vector3(2000, 0, 0)
	target = Targeting.advance(value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, true)
	check(
		target.id == 3 and value.held,
		"Held live target stays selected after leaving acquisition box"
	)
	roster[1].active = false
	target = Targeting.advance(value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, true)
	check(
		target.id == -1 and not value.held,
		"Target death releases random hold on the next simulation step"
	)
	roster[0].position = Vector3(2000, 0, 0)
	value = Targeting.create()
	target = Targeting.advance(value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, true)
	check(target.is_empty(), "Escort returns to route when no opponent can be acquired")
	target = Targeting.advance(value, enemies, Vector3.ZERO, .1, data, 0, 452, 0, false)
	check(target.id == -1, "Routeless fighter pursues original first opponent outside box")
	value = Targeting.create()
	target = Targeting.advance(value, enemies, Vector3.ZERO, 5, data, 100, 452, 0, true)
	check(
		target.is_empty() and not value.held and value.decisions == 1,
		"Exhausted random attempts fall back to route with one timed decision"
	)
	roster[0].position = Vector3(900, 0, 0)
	roster[1].position = Vector3(100, 0, 0)
	roster[1].active = true
	var expected := {}
	for hz in [30, 60, 144]:
		value = Targeting.create()
		for tick in hz * 20:
			Targeting.advance(value, enemies, Vector3.ZERO, 1.0 / hz, data, 100, 452, 0, false)
		check(
			value.decisions == 4 and value.held,
			"Timed random choices hold consistently at %d Hz" % hz
		)
		if expected.is_empty():
			expected = value.duplicate(true)
		else:
			check(
				value.selected == expected.selected and is_zero_approx(value.elapsed),
				"Frame rate preserves target RNG decisions at %d Hz" % hz
			)
	value = Targeting.create()
	Targeting.advance(value, enemies, Vector3.ZERO, 4.9, data, 100, 452, 0, false)
	check(
		value.decisions == 0 and not value.held, "No early random decision before source interval"
	)
	Targeting.advance(value, enemies, Vector3.ZERO, .2, data, 100, 452, 0, false)
	check(
		value.decisions == 1 and is_equal_approx(value.elapsed, .1),
		"Native timer preserves fractional overshoot"
	)
	for context in [
		[{"kind": "campaign", "chapter": 8}, {}, 60],
		[{"kind": "campaign", "chapter": 7}, {}, 30],
		[{"kind": "contract", "chapter": 8}, {"source_mission_type": 0}, 30],
		[{"kind": "contract", "chapter": 13}, {"source_mission_type": 7}, 60],
		[{"kind": "survival", "chapter": 8}, {}, 30]
	]:
		check(
			Targeting.chance(data, context[1], context[0]) == context[2],
			"Selection probability distinguishes campaign level from freelance type"
		)
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 3
	pilot.progression = Session.Progression.create(3)
	pilot.station_id = lib.chapter_destination(2)
	check(pilot.depart(), "Launch source escort for target persistence")
	var actor: Dictionary = pilot.active_job.actors[0]
	Session.Encounters.advance(
		pilot.mission_definition(),
		pilot.active_job,
		.5,
		Vector3(10000, 0, 10000),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		actor.targeting.elapsed == .5 and not actor.awake,
		"Sleeping fighter advances its target clock without waking at distance"
	)
	var saved: Dictionary = pilot.capture()
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(JSON.parse_string(JSON.stringify(saved))),
		"Campaign26 restores target state: " + copy.error
	)
	check(
		same_saved_value(copy.active_job.actors[0].targeting, actor.targeting),
		"Campaign restore preserves target timer"
	)
	var before: Dictionary = copy.capture()
	for invalid in [
		{"selected": 0}, {"elapsed": 5}, {"held": 1}, {"decisions": -1}, {"selected": 99999}
	]:
		var bad: Dictionary = saved.duplicate(true)
		bad.active_job.actors[0].targeting.merge(invalid, true)
		check(
			not copy.restore(bad) and same_saved_value(before, copy.capture()),
			"Reject malformed/friendly target state atomically " + str(invalid)
		)
	var old: Dictionary = saved.duplicate(true)
	old.schema = 25
	for item in old.active_job.actors:
		item.erase("targeting")
	check(
		copy.restore(old) and copy.active_job.actors[0].targeting == Targeting.create(),
		"Campaign25 migration starts fresh decisions without moving actors"
	)
	check(not old.active_job.actors[0].has("targeting"), "Legacy migration leaves input unchanged")
	var view := Flight.new()
	root.add_child(view)
	view.setup(lib, pilot, {}, true)
	view.set_physics_process(false)
	view.paused = true
	var frozen: Dictionary = actor.targeting.duplicate(true)
	view.step(1)
	check(
		same_saved_value(frozen, actor.targeting),
		"Modal pause freezes target timing and random choices"
	)
	view.queue_free()
	await process_frame
	await check_fighter_targeting_survival(lib)


func check_fighter_targeting_survival(lib) -> void:
	var Targeting = Session.Mission.Targeting
	var data: Dictionary = lib.content.fighter_targeting
	var view: Flight
	var before: Dictionary
	var old: Dictionary
	var roster: Array = [{"id": -1, "team": "ally", "position": Vector3(900, 0, 0), "active": true}]
	var survival = preload("res://src/simulation/survival_session.gd").new()
	survival.configure_survival(lib, lib.content.survival, 0, 0, 452)
	var fighter: Dictionary = survival.active_job.actors[0]
	Targeting.advance(fighter.targeting, [roster[0]], Vector3.ZERO, 5.25, data, 100, 452, 0, false)
	var survival_save: Dictionary = survival.capture()
	var restored = preload("res://src/simulation/survival_session.gd").new()
	restored.configure_survival(lib, lib.content.survival, 0, 0, 452)
	check(
		restored.restore(JSON.parse_string(JSON.stringify(survival_save))),
		"Survival9 restores target state: " + restored.error
	)
	check(
		same_saved_value(restored.active_job.actors[0].targeting, fighter.targeting),
		"Survival keeps decision counter and target"
	)
	before = restored.capture()
	var bad: Dictionary = survival_save.duplicate(true)
	bad.actors[0].targeting.selected = 1
	check(
		not restored.restore(bad) and same_saved_value(before, restored.capture()),
		"Survival rejects friendly target atomically"
	)
	old = survival_save.duplicate(true)
	old.schema = 8
	for item in old.actors:
		item.erase("targeting")
	check(
		restored.restore(old) and restored.active_job.actors[0].targeting == Targeting.create(),
		"Survival8 migration starts fresh decisions"
	)
	view = Flight.new()
	root.add_child(view)
	view.setup(lib, survival, {}, true)
	view.set_physics_process(false)
	view.ship.position = Vector3(10000, 0, 10000)
	view.throttle = 0
	var decisions: int = fighter.targeting.decisions
	survival.damage_actor(0, fighter.hp)
	view.spawn_targets()
	for tick in 200:
		view.step(.1)
		if fighter.hp > 0:
			break
	check(
		fighter.hp > 0 and not fighter.targeting.held and fighter.targeting.decisions == decisions,
		"Survival revival clears selected target and preserves independent RNG counter"
	)
	check(survival.restore(survival.capture()), "Revived targeting state saves: " + survival.error)
	view.queue_free()
	await process_frame


func check_fighter_follow(source: PackedByteArray, lib) -> void:
	var data: Dictionary = lib.content.fighter_targeting
	check(
		is_equal_approx(data.ally_wake_half_width, 499.98),
		"Read ally activation extent from the supplied fighter update"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [
		0x55ede, 0x55ee6, 0x55ef0, 0x55f06, 0x55f20, 0x55f2a, 0x55fba, 0x55fc8, 0x685fa
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.fighter_targeting().is_empty(), "Reject changed ally follow binding %x" % address
		)
	reader.bytes = source.duplicate()
	for declaration in [[0x55efc, 29999], [0x55f00, 59998], [0x55f10, -30000]]:
		reader.bytes.encode_s32(literal_file_offset(reader, declaration[0]), declaration[1])
	reader.error = ""
	var changed: Dictionary = reader.fighter_targeting()
	check(
		not changed.is_empty() and is_equal_approx(changed.ally_wake_half_width, 599.98),
		"Supplied extent mutation reaches native ally behavior: " + reader.error
	)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		check(
			Session.Encounters.idle_ally_direction(Vector3.ZERO, axis * 490, data).is_equal_approx(
				axis * 490
			),
			"Pilot is followed directly inside source box"
		)
		check(
			Session.Encounters.idle_ally_direction(Vector3.ZERO, axis * 510, data) == Vector3.ZERO,
			"Route-less ally remains still outside source activation box"
		)
	check(
		(
			Session.Encounters.idle_ally_direction(Vector3.ZERO, Vector3(510, 0, 0), changed)
			!= Vector3.ZERO
		),
		"Changed source extent changes activation without a native threshold constant"
	)
	var original: Dictionary = lib.mission_definition(7)
	var definition: Dictionary = original.duplicate(true)
	definition.groups = [original.groups[9].duplicate(true)]
	definition.success = {"kind": "endless"}
	definition.erase("enemy_goal")
	definition.radio = []
	var state: Dictionary = Session.Mission.create(
		definition, 7, lib.chapter_destination(6), lib, 22
	)
	var actor: Dictionary = state.actors[0]
	var expected := (
		Session.Mission.SPAWN_POSITION + Session.Mission.point(original.groups[9].center)
	)
	check(
		Combat.vector(actor.position).is_equal_approx(expected),
		"Original wingmate offset still controls spawn position"
	)
	actor.position = [0, 0, 0]
	Session.Encounters.advance(definition, state, 1, Vector3(0, 0, -100), Vector3.ZERO, {}, lib, {})
	check(
		(
			actor.position[2] < 0
			and is_zero_approx(actor.position[0])
			and is_zero_approx(actor.position[1])
			and actor.shots == 0
		),
		"Enemy-less wingmate flies directly toward pilot without reusing its spawn offset or firing"
	)
	actor.position = [0, 0, 0]
	Session.Encounters.advance(definition, state, 1, Vector3(0, 0, -600), Vector3.ZERO, {}, lib, {})
	check(
		Combat.vector(actor.position) == Vector3.ZERO,
		"Enemy-less wingmate remains in place beyond source activation box"
	)
	actor.awake = false
	Session.Encounters.advance(
		definition, state, .1, Vector3(0, 0, -600), Vector3.ZERO, {}, lib, {}
	)
	check(
		not actor.awake,
		"Sleeping ally uses its own activation extent instead of enemy acquisition width"
	)
	Session.Encounters.advance(
		definition, state, .1, Vector3(0, 0, -400), Vector3.ZERO, {}, lib, {}
	)
	check(actor.awake, "Sleeping ally activates near the pilot")
	# An explicit singleton center is sufficient data. Several distinct positions
	# cannot be inferred from one center without a supplied scatter/placement rule.
	definition.groups[0].erase("placement")
	definition.groups[0].behavior = "interceptor"
	definition.groups[0].team = "enemy"
	state = Session.Mission.create(definition, 7, 0, lib, 22)
	check(
		Combat.vector(state.actors[0].position).is_equal_approx(
			Session.Mission.point(definition.groups[0].center)
		),
		"Singleton center has no invented vertical or rear offset"
	)
	definition.groups[0].count = 2
	check(
		Session.Mission.create(definition, 7, 0, lib, 22).is_empty(),
		"Multiple ships without supplied placement are not given fabricated spacing"
	)
	var invalid: Dictionary = lib.mission_definition(2).duplicate(true)
	invalid.groups[0].scatter = []
	invalid.groups[0].erase("placement")
	invalid.groups[0].count = 2
	check(
		not lib.valid_mission(invalid),
		"Unsupported missing multi-ship placement is rejected at the content boundary"
	)
	# This replaces the old test that incorrectly expected a formation slot when
	# all opponents were outside gun range. Keep the original roster fallback.
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.chapter = 7
	pilot.progression = Session.Progression.create(7)
	pilot.station_id = lib.chapter_destination(6)
	pilot.market_seed = 22
	check(pilot.depart(), "Launch original cruiser attack")
	state = pilot.active_job
	for index in range(10):
		state.actors[index].position = [100000, 0, 0]
	Session.Encounters.advance(
		original,
		state,
		1,
		Vector3(10000, 0, 0),
		Vector3.ZERO,
		pilot.combat,
		lib,
		pilot.actor_weapons()
	)
	check(
		int(state.actors[11].targeting.selected) == 0 and state.actors[11].shots == 0,
		"Distant cruiser scenario follows source target roster rather than an invented formation offset"
	)
	check(
		pilot.restore(JSON.parse_string(JSON.stringify(pilot.capture()))),
		"Changed wingmate behavior preserves valid campaign JSON: " + pilot.error
	)


func check_fighter_placement_boundaries(lib) -> void:
	var cases := 0
	for chapter in lib.content.chapters.size():
		var definition: Dictionary = lib.mission_definition(chapter)
		var state := Session.Mission.create(
			definition, chapter, lib.chapter_destination(maxi(0, chapter - 1)), lib, 22
		)
		check(not state.is_empty(), "Campaign source placement remains supported " + str(chapter))
		cases += 1
	var pilot := Session.new()
	pilot.configure(lib)
	var kinds := {}
	var missing := {}
	for region in lib.content.contracts.quadrant_difficulty.size():
		for visit in 16:
			var station: int = (
				region * (lib.stations.size() / lib.content.contracts.quadrant_difficulty.size())
			)
			var offers := Contracts.generate(lib, station, Contracts.board_seed(22, visit, station))
			for index in offers.size():
				var offer: Dictionary = offers[index]
				if not Contracts.supported(lib, offer):
					continue
				var key := "%s:%s" % [region, int(offer.type)]
				if kinds.has(key):
					continue
				var definition := pilot.build_contract(
					{"station": station, "visit": visit, "index": index}, lib.campaign_level(13), 22
				)
				check(
					not definition.is_empty() and lib.valid_mission(definition),
					"Generated contract placement validates " + key
				)
				if definition.is_empty():
					missing[key] = true
					continue
				var state := Session.Mission.create(
					definition, 13, station, lib, 22, lib.campaign_level(13), "contract"
				)
				check(
					not state.is_empty(),
					"Generated contract requires no fabricated formation " + key
				)
				check(
					int(definition.source_mission_type) == int(offer.type),
					"Generated source type reaches encounter targeting " + key
				)
				kinds[key] = true
				cases += 1
	print(
		"PLACEMENT DECLARATIONS ",
		cases,
		" CONTRACT REGION/TYPES ",
		kinds.keys(),
		" MISSING ",
		missing.keys()
	)


func check_menu_traffic(source: PackedByteArray, lib) -> void:
	var Traffic = preload("res://src/presentation/menu_traffic.gd")
	var data: Dictionary = lib.content.menu_traffic
	check(
		Traffic.valid_data(data, lib.content.tables.actor_meshes.size()),
		"Imported menu traffic declarations validate"
	)
	check(
		(
			data.local_route.size() == 4
			and data.player_route.size() == 2
			and data.local_min == 2
			and data.local_span == 3
		),
		"Source route lengths and ambient ship count"
	)
	check(
		(
			data.freighter_chance == 70
			and data.escort_chance == 35
			and data.carrier_chance == 35
			and data.double_freighter_chance == 50
		),
		"Source conditional traffic density"
	)
	check(
		(
			same_saved_value(data.camera_position, [0, 0, 10000])
			and same_saved_value(data.player_position, [300, -500, 7000])
			and data.fov_units == 12000
		),
		"Source player placement and initial camera"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [
		0x340dc, 0x3415a, 0x341ea, 0x343d8, 0x34522, 0x3453e, 0x34672, 0x347b2, 0x13b00, 0x13b30
	]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.menu_traffic().is_empty(),
			"Reject unsupported traffic source binding %x" % address
		)
	reader.bytes = source.duplicate()
	var pointer: int = reader.literal(0x340ae, 3)
	reader.bytes.encode_s32(reader.file_offset(pointer, 4), 1500)
	reader.bytes.encode_u16(reader.file_offset(0x341cc, 2), 0x2204)
	reader.bytes.encode_u16(reader.file_offset(0x34054, 2), 0x2831)
	reader.error = ""
	var altered: Dictionary = reader.menu_traffic()
	check(
		(
			not altered.is_empty()
			and altered.local_route[0][0] == 1500
			and altered.families[1].freighter == 4
			and altered.freighter_chance == 50
		),
		"Route, hull choice and chance are read from changed source data: " + reader.error
	)
	var snapshot := JSON.stringify(data)
	var combinations := {}
	var samples := 0
	var all_valid := true
	var seen_counts := {}
	for race in [0, 1, 9, 2]:
		var family: Dictionary = data.families[0]
		for item in data.families:
			if int(item.race) == race:
				family = item
		for seed_value in 128:
			var ships: Array = Traffic.sample(
				data, race, int(lib.content.tables.buyable_ships[0]), seed_value
			)
			var counts := {"local": 0, "freighter": 0, "escort": 0, "carrier": 0, "player": 0}
			for ship in ships:
				counts[ship.role] += 1
				all_valid = (
					all_valid
					and ship.actor >= 0
					and ship.actor < lib.content.tables.actor_meshes.size()
				)
				all_valid = (
					all_valid
					and Combat.valid_vector(ship.position)
					and is_equal_approx(Combat.vector(ship.heading).length(), 1)
				)
				all_valid = all_valid and ship.waypoint >= 0 and ship.waypoint < ship.route.size()
				if ship.role != "player":
					all_valid = (
						all_valid and int(ship.actor) == int(family[ship.role]) and ship.loop
					)
					all_valid = all_valid and ship.rotation_locked == (ship.role != "local")
					if ship.role == "local":
						all_valid = all_valid and ship.waypoint < data.local_route.size() - 1
				else:
					all_valid = (
						all_valid and not ship.loop and not ship.trail and ship.rotation_locked
					)
					all_valid = (
						all_valid
						and Combat.vector(ship.position).is_equal_approx(
							Session.Mission.point(data.player_position)
						)
					)
			all_valid = (
				all_valid
				and counts.local >= 2
				and counts.local <= 4
				and counts.freighter <= 2
				and counts.escort <= 1
				and counts.carrier <= 1
				and counts.player == 1
			)
			all_valid = (
				all_valid
				and (counts.carrier == 0 or counts.escort == 1)
				and (counts.freighter != 2 or counts.escort == 0)
			)
			if race == 9:
				all_valid = all_valid and counts.escort == 0 and counts.carrier == 0
			seen_counts[counts.local] = true
			combinations["%s:%s:%s" % [counts.freighter, counts.escort, counts.carrier]] = true
			all_valid = all_valid and ships.back().role == "player"
			samples += 1
	check(
		all_valid and seen_counts.size() == 3 and combinations.size() >= 5,
		"512 native samples preserve source family, route, count and conditional optional-ship rules"
	)
	check(snapshot == JSON.stringify(data), "Scene sampling does not mutate imported declarations")
	var first := Traffic.sample(data, 0, -1, 1234)
	var second := Traffic.sample(data, 0, -1, 1234)
	check(
		same_saved_value(first, second) and first.all(func(ship): return ship.role != "player"),
		"Stable menu sampling omits player ship when no mission is active"
	)
	var family_changed := Traffic.sample(altered, 0, -1, 1234)
	var local_changed := false
	for ship in family_changed:
		if ship.role == "local":
			local_changed = ship.route[0][0] == 1500
	check(local_changed, "Changed supplied route reaches native scene declarations")
	var ships := Traffic.sample(data, 0, 0, 1234)
	ships[0].route[0][0] = 999
	check(
		JSON.stringify(data) == snapshot and second[0].route[0][0] != 999,
		"Each generated ship owns its mutable route"
	)
	for invalid in [null, {}, {"families": []}]:
		check(
			not Traffic.valid_data(invalid, lib.content.tables.actor_meshes.size()),
			"Malformed traffic content is unsupported"
		)
	var bad: Dictionary = data.duplicate(true)
	bad.families[0].local = 9999
	check(
		not Traffic.valid_data(bad, lib.content.tables.actor_meshes.size()),
		"Unknown traffic actor cannot bypass content validation"
	)
	bad = data.duplicate(true)
	bad.player_route[0][0] = NAN
	check(
		not Traffic.valid_data(bad, lib.content.tables.actor_meshes.size()),
		"Invalid route coordinate is rejected"
	)
	print("MENU TRAFFIC NATIVE SAMPLES ", samples, " DENSITY COMBINATIONS ", combinations.keys())


func check_menu_scene(source: PackedByteArray, lib) -> void:
	var Scene = preload("res://src/presentation/menu_scene.gd")
	var Traffic = preload("res://src/presentation/menu_traffic.gd")
	var data: Dictionary = lib.content.menu_traffic
	var actor := int(lib.content.tables.buyable_ships[0])
	check(
		(
			data.local_trail.style == 1
			and data.local_trail.segments == 40
			and is_equal_approx(data.trail_seconds, .08)
		),
		"Imported friendly trail style, history and cadence"
	)
	check(
		Combat.vector(data.orbital_position) == Vector3(0, 0, 131072) and data.orbital_scale == 4,
		"Imported orbital station placement/scale from initial identity camera"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [0x4ef6c, 0x13b86, 0x5bc4e, 0x55b4a, 0x5651e]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(reader.menu_traffic().is_empty(), "Unknown scene association rejected %x" % address)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x55852, 2), 0x2220)
	reader.bytes.encode_u16(reader.file_offset(0x55ae4, 2), 0x2b64)
	reader.bytes.encode_u32(
		reader.file_offset(((0x5baee + 4) & ~3) + (reader.u16(0x5baee) & 255) * 4, 4), 1499
	)
	reader.error = ""
	var changed: Dictionary = reader.menu_traffic()
	check(
		(
			not changed.is_empty()
			and changed.local_trail.segments == 32
			and changed.trail_seconds == .1
			and is_equal_approx(changed.waypoint_half_width, 29.98)
		),
		"Changed source trail cadence/history/arrival extent propagate: " + reader.error
	)
	var declarations := Traffic.sample(data, 0, actor, 2)
	check(
		(
			declarations
			. filter(func(ship): return ship.role == "local")
			. all(func(ship): return ship.waypoint == data.route_start)
		),
		"Cloned local route cursor is independent of random spawn position"
	)
	var ship: Dictionary = declarations.back().duplicate(true)
	ship.up = [0.0, 1.0, 0.0]
	var start := Combat.vector(ship.position)
	Scene.step_ship(ship, data, lib.content.fighter_steering, 40, .1)
	check(
		(
			is_equal_approx(Combat.vector(ship.position).distance_to(start), 4)
			and is_equal_approx(Combat.vector(ship.position).y, start.y)
		),
		"Locked traffic moves at source current speed while retaining altitude"
	)
	ship.position = Combat.packed(Session.Mission.point(ship.route[1]))
	ship.waypoint = 1
	ship.loop = true
	start = Combat.vector(ship.position)
	Scene.step_ship(ship, data, lib.content.fighter_steering, 40, .1)
	check(
		ship.waypoint == 0 and is_equal_approx(Combat.vector(ship.position).distance_to(start), 4),
		"Loop resets only cursor, without teleport"
	)
	ship.waypoint = 1
	ship.position = Combat.packed(Session.Mission.point(ship.route[1]))
	ship.loop = false
	Scene.step_ship(ship, data, lib.content.fighter_steering, 40, .1)
	check(ship.waypoint == ship.route.size(), "Non-loop player route remains exhausted")
	var location := int(lib.content.initial.station_index)
	var scenes: Array = []
	var serialized := JSON.stringify(lib.content.menu_traffic)
	for hz in [30, 144]:
		var scene = Scene.new()
		root.add_child(scene)
		scene.set_process(false)
		check(
			scene.configure(lib, location, actor, true, 2),
			"Configure original title traffic: " + scene.error
		)
		if not scene.supported:
			scene.free()
			return
		for frame in hz * 8:
			scene.advance(1.0 / hz)
		scenes.append(scene)
	check(
		same_saved_value(scenes[0].ships, scenes[1].ships),
		"30/144 Hz produce identical traffic routes and poses"
	)
	check(
		scenes[0].trails[0].points == scenes[1].trails[0].points,
		"Trail history cadence is independent of redraw rate"
	)
	var scene = scenes[0]
	check(
		(
			is_equal_approx(scene.elapsed, 8)
			and scene.camera.position == Session.Mission.point(data.camera_position)
		),
		"Fixed camera position and native elapsed clock"
	)
	var aim: Vector3 = (
		(scene.visuals.back().global_position - scene.camera.global_position).normalized()
	)
	check(
		(-scene.camera.global_basis.z).dot(aim) > .99999, "Camera aims at final moving source ship"
	)
	check(
		(
			scene.visuals.size() == scene.ships.size()
			and scene.burners.all(func(burner): return not burner.nozzles.is_empty())
		),
		"Scene hulls own original nozzle attachments"
	)
	check(
		scene.trails[0].visible and scene.trails.back() == null,
		"Local source trail renders; removed player trail stays absent"
	)
	var before := JSON.stringify(scene.ships)
	scene.hide()
	scene.advance(1)
	check(
		JSON.stringify(scene.ships) == before and not scene.flare_layer.visible,
		"Hidden scene freezes and hides independent flare layer"
	)
	check(
		serialized == JSON.stringify(lib.content.menu_traffic),
		"Presentation never mutates supplied route data"
	)
	for item in scenes:
		item.free()
	var station_ids := {}
	for index in lib.stations.size():
		var row: Dictionary = lib.station_definition(index)
		var key := "planet" if row.planet else str(lib.location_station_type(index))
		if not station_ids.has(key):
			station_ids[key] = index
	for key in station_ids:
		var dock = Scene.new()
		root.add_child(dock)
		dock.set_process(false)
		check(
			dock.configure(lib, station_ids[key], -1, false, 3),
			"Configure dock scene family " + key + ": " + dock.error
		)
		if key == "planet":
			check(
				dock.scene_mode == 4 and dock.station == null,
				"Planet location uses sky geometry without invented station"
			)
		else:
			check(
				(
					dock.scene_mode == 3
					and dock.station != null
					and dock.station.position == Session.Mission.point(data.orbital_position)
				),
				"Orbital location uses source station family/placement " + key
			)
		dock.free()


class MenuSceneMain extends "res://src/main.gd":
	func hangar_hint_history() -> Array:
		# Menu/transaction fixtures represent a player who has read the hints.
		return ["intro", "ship", "cargo", "shop"]
	func _ready() -> void:
		pass
	func _process(_seconds: float) -> void:
		pass
	func play_music(_track: String) -> void:
		pass

func check_menu_scene_main(lib) -> void:
	var app := MenuSceneMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.show_title()
	check(
		app.menu_scene != null and app.menu_scene.camera.current and not app.showcase.visible,
		"Title selects traffic camera and hides old rotating showcase"
	)
	var previous = app.menu_scene
	previous.set_process(false)
	previous.advance(4)
	app.show_options()
	check(
		(
			previous.is_queued_for_deletion()
			and not previous.visible
			and not previous.flare_layer.visible
		),
		"Leaving title stops old scene and flare layer immediately"
	)
	check(
		app.menu_scene != null and app.menu_scene.scene_mode == 4,
		"Title options retain original background"
	)
	var pilot = Session.new()
	pilot.configure(lib, false)
	app.session = pilot
	var progress_before := JSON.stringify(pilot.progression)
	var credits_before: int = pilot.credits
	for index in lib.stations.size():
		if not lib.station_definition(index).planet:
			pilot.station_id = index
			break
	app.show_dock()
	check(
		(
			app.menu_scene != null
			and app.menu_scene.scene_mode == 3
			and app.menu_scene.ships.back().role == "player"
		),
		"Campaign dock selects orbital scene and current pilot hull"
	)
	app.menu_scene.set_process(false)
	app.menu_scene.advance(2)
	app.show_market()
	check(
		app.menu_scene != null and app.menu_scene.camera.current,
		"Market retains native station scenery"
	)
	for index in lib.stations.size():
		if lib.station_definition(index).planet:
			pilot.station_id = index
			break
	app.show_dock()
	check(
		(
			app.menu_scene != null
			and app.menu_scene.scene_mode == 4
			and app.menu_scene.station == null
		),
		"Planet dock replaces orbital model with imported planet background"
	)
	app.menu_scene.set_process(false)
	app.menu_scene.advance(1)
	check(
		pilot.credits == credits_before and JSON.stringify(pilot.progression) == progress_before,
		"Decorative time and navigation leave campaign progression/rewards untouched"
	)
	app.clear_page()
	var flight_camera := Camera3D.new()
	app.world.add_child(flight_camera)
	flight_camera.current = true
	app.clear_page()
	check(flight_camera.current, "Clearing UI without a menu scene preserves active flight camera")
	app.free()
	await process_frame

class TitleMenuMain:
	extends MenuSceneMain
	var actions: Array = []

	func request_start(skip: bool) -> void:
		actions.append("explore" if skip else "campaign")

	func continue_game(slot: String) -> void:
		actions.append("load_" + slot)

	func show_survival_menu(_page_index: int = 0, _selection: int = 0) -> void:
		actions.append("survival")

	func choose_file() -> void:
		actions.append("import")

	func shutdown() -> void:
		actions.append("exit")

	func save_path(slot: String) -> String:
		return "user://title-menu-unavailable-" + slot


func check_title_menu(source: PackedByteArray, lib) -> void:
	var Widget = preload("res://src/presentation/title_menu.gd")
	var data: Dictionary = lib.content.title_ui
	check(
		(
			same_saved_value(data.row_starts, [180, 142, 142, 104, 104, 104])
			and data.row_step == 38
			and data.text_y == 9
		),
		"Title button placement comes from source tables"
	)
	check(
		data.labels.start == 0 and data.labels.load == 610 and data.labels.help == 4,
		"Title localization associations recovered"
	)
	check(
		(
			lib.ui_image(data.images.logo).get_size() == Vector2(298, 106)
			and lib.ui_image(data.images.idle).get_size() == Vector2(164, 29)
		),
		"Original logo and menu button regions"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [0x49f8e, 0x2913c, 0x3f696, 0x3f73c, 0x28d7a]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.title_menu_presentation().is_empty() and not reader.error.is_empty(),
			"Unsupported title association rejected %x" % address
		)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x3f676, 2), 0x2324)
	reader.bytes.encode_u16(reader.file_offset(0x3f6b8, 2), 0x3307)
	reader.error = ""
	var changed: Dictionary = reader.title_menu_presentation()
	check(
		not changed.is_empty() and changed.row_step == 36 and changed.text_y == 7,
		"Changed source spacing and text offset propagate"
	)
	var invalid := data.duplicate(true)
	invalid.indicator_count = 1.5
	check(not Widget.valid_data(invalid), "Fractional decoration count rejected")
	var original: int = data.images.logo.region
	data.images.logo.region = 999999
	check(not lib.valid_title_ui(), "Unavailable atlas region rejected before rendering")
	data.images.logo.region = original
	check(lib.valid_title_ui(), "Restored title atlas binding validates")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	root.add_child(viewport)
	var app := TitleMenuMain.new()
	viewport.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.show_title()
	await process_frame
	var panel = app.title_panel
	check(
		panel.buttons.size() == 5 and not app.page.visible and not app.top.visible,
		"Original title replaces placeholder panels"
	)
	check(panel.buttons[0].has_focus(), "First enabled action receives keyboard/controller focus")
	if not OS.has_feature("mobile"):
		for index in range(1, panel.buttons.size()):
			check(not panel.buttons[index - 1].get_rect().intersects(panel.buttons[index].get_rect()), "Desktop title rows do not overlap")
		check(panel.footer.position.x == lib.content.briefing_ui.footer.margin and panel.footer.position.y == lib.content.briefing_ui.footer.y - 20 and panel.canvas.size == Vector2(480, 320), "Desktop Exit stays left, lifted within the original frame")
		check(panel.canvas.get_global_rect().encloses(panel.footer.get_global_rect()), "Desktop Exit stays inside the centered composition")
	var previous_scene = app.menu_scene
	panel.buttons[0].pressed.emit()
	check(
		panel.section == "start" and panel.buttons.size() == 3 and app.menu_scene == previous_scene,
		"Start submenu preserves ambient scene"
	)
	for index in 3:
		panel.buttons[index].pressed.emit()
	check(
		app.actions == ["campaign", "explore", "survival"],
		"Start choices dispatch separate native campaign, skip and survival actions"
	)
	app.navigate_back()
	check(panel.section == "main", "Back returns to title root")
	panel.buttons[1].pressed.emit()
	check(
		panel.buttons.all(func(button): return button.disabled) and panel.footer.has_focus(),
		"Missing save slots are disabled and Back retains focus"
	)
	app.show_title_menu("files")
	panel.buttons[0].pressed.emit()
	check(app.actions.back() == "import", "Choose IPA routes to native file dialog")
	app.notify("This pilot could not be loaded.")
	check(
		panel.section == "notice" and panel.canvas.get_child_count() == 2,
		"Title errors remain visible with a Back action"
	)
	app.navigate_back()
	panel.footer.pressed.emit()
	check(app.actions.back() == "exit", "Exit footer dispatches shutdown")
	for extent in [Vector2i(1440, 960), Vector2i(1920, 1080), Vector2i(720, 1280)]:
		viewport.size = extent
		await process_frame
		panel.layout_canvas()
		var bounds := Rect2(Vector2.ZERO, Vector2(extent))
		check(
			(
				panel.buttons.all(func(button): return bounds.encloses(button.get_global_rect()))
				and bounds.encloses(panel.footer.get_global_rect())
			),
			"Menu actions fit viewport %s" % extent
		)
	var shade_before: float = panel.shade
	panel.set_process(false)
	panel._process(100)
	check(
		panel.shade == data.shade_floor and shade_before >= panel.shade,
		"Title fade stops at imported floor"
	)
	app.show_title_menu("help")
	var help: ScrollContainer = panel.canvas.get_child(1)
	await process_frame
	check(
		help.get_child(0).text == app.controls_help() and help.get_child(0).size.y > help.size.y,
		"Shared remake controls remain scrollable in original frame"
	)
	panel.footer.pressed.emit()
	panel.buttons[2].pressed.emit()
	check(
		app.screen == "options" and app.title_panel == null and not panel.visible,
		"Options removes title input immediately"
	)
	app.close_options()
	check(
		app.screen == "title" and app.title_panel.section == "main",
		"Options returns to original title"
	)
	app.free()
	viewport.free()
	await process_frame


func check_title_atlas_boundary(source: PackedByteArray) -> void:
	var reader = NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	var binding: Dictionary = reader.ui_region_binding(516)
	check(
		binding.get("texture") == 3 and binding.get("region") == 16,
		"Split atlas record uses source fields across literal pool"
	)
	reader.bytes.encode_u16(reader.file_offset(0x1bb18, 2), 0x2215)
	binding = reader.ui_region_binding(516)
	check(binding.get("region") == 21, "Changed split atlas region propagates")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x1bb22, 2), 0xbf00)
	check(
		reader.ui_region_binding(516).is_empty() and reader.error.contains("split UI"),
		"Unsupported split-record branch rejected"
	)


class StationMenuMain:
	extends MenuSceneMain
	var actions: Array = []

	func show_market(_section: String = "stock") -> void:
		actions.append("hangar")

	func show_contracts() -> void:
		actions.append("missions")

	func show_map() -> void:
		actions.append("map")

	func show_briefing() -> void:
		actions.append("briefing")

	func launch(_resume: bool = false) -> void:
		actions.append("launch")

	func save_game(_announce: bool = true) -> bool:
		actions.append("save")
		return true

	func request_skip() -> void:
		actions.append("skip")


func check_station_menu(source: PackedByteArray, lib) -> void:
	var Widget = preload("res://src/presentation/station_menu.gd")
	var data: Dictionary = lib.content.station_ui
	check(
		same_saved_value(data.tabs.map(func(tab): return tab.label), [493, 95, 66, 108]),
		"Source station tab labels"
	)
	check(
		same_saved_value(data.box, [30, 25, 420, 260]) and same_saved_value(data.list, [45, 55, 208, 220]),
		"Source station layout declarations"
	)
	check(
		same_saved_value(data.locked_campaign_tabs, [2, 3]) and data.shop_credit_threshold == 999999,
		"Source campaign and shop availability rules"
	)
	var reader = NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	for address in [0x4f88a, 0x4e3e8, 0x4dc6e, 0x4f81c, 0x51980]:
		reader.bytes = source.duplicate()
		reader.bytes.encode_u16(reader.file_offset(address, 2), 0xbf00)
		reader.error = ""
		check(
			reader.station_menu_presentation().is_empty(),
			"Unsupported station UI association rejected %x" % address
		)
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x4f882, 2), 0x212f)
	reader.error = ""
	var changed: Dictionary = reader.station_menu_presentation()
	check(
		not changed.is_empty() and changed.list[0] == 47, "Changed source station origin propagates"
	)
	var malformed := data.duplicate(true)
	malformed.tabs[0].action = "invented"
	check(not Widget.valid_data(malformed), "Unknown station role rejected")
	var saved_region: int = data.images.preview.region
	data.images.preview.region = 99999
	check(not lib.valid_station_ui(), "Missing station preview artwork rejected before display")
	data.images.preview.region = saved_region
	check(lib.valid_station_ui(), "Restored station artwork validates")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 960)
	root.add_child(viewport)
	var app := StationMenuMain.new()
	viewport.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	var pilot := Session.new()
	pilot.configure(lib, false)
	app.session = pilot
	var progress := JSON.stringify(pilot.progression)
	var credits: int = pilot.credits
	app.show_dock()
	await process_frame
	var panel = app.station_panel
	check_desktop_tab_layout(panel)
	check(
		not app.top.visible and not app.page.visible and panel.tabs.size() == 4,
		"Station home replaces placeholder panel"
	)
	check(
		(
			not panel.tabs[0].disabled
			and not panel.tabs[1].disabled
			and panel.tabs[2].disabled
			and panel.tabs[3].disabled
		),
		"Campaign shows Info/Hangar and locks Missions/Map"
	)
	panel.actions[2].pressed.emit()
	check(app.actions == ["briefing"], "Campaign Go on routes to briefing")
	panel.tabs[1].pressed.emit()
	check(app.actions.back() == "hangar", "Hangar connects existing market/outfitting")
	app.show_station_menu()
	check(
		panel.section == "menu" and panel.tabs.all(func(tab): return tab.disabled),
		"Engine options overlay prevents background tab clicks"
	)
	var choices: Array = panel.overlay.get_children().filter(func(node): return node is Button)
	choices[2].pressed.emit()
	check(app.actions.back() == "skip", "Skip retains existing confirmation workflow")
	app.navigate_back()
	check(
		panel.section == "info" and not panel.tabs[1].disabled and panel.tabs[2].disabled,
		"Back restores campaign tab availability"
	)
	panel.actions[1].pressed.emit()
	check(panel.section == "status", "Status footer opens pilot summary")
	app.navigate_back()
	app.notify("Pilot could not be saved.")
	check(panel.section == "notice", "Dock errors are readable over original interface")
	app.navigate_back()
	check(
		pilot.credits == credits and JSON.stringify(pilot.progression) == progress,
		"Station navigation never mutates campaign progress/rewards"
	)
	app.show_options()
	check(
		app.station_panel == null and not panel.visible,
		"Leaving dock immediately removes old widget input"
	)
	app.close_options()
	check(
		app.screen == "dock" and app.station_panel.section == "info",
		"Options returns to original station home"
	)
	pilot = Session.new()
	pilot.configure(lib, true)
	app.session = pilot
	app.show_dock()
	panel = app.station_panel
	check(
		not panel.tabs[2].disabled and not panel.tabs[3].disabled,
		"Explicit skip unlocks exploration tabs"
	)
	panel.tabs[2].pressed.emit()
	panel.tabs[3].pressed.emit()
	panel.actions[2].pressed.emit()
	check(
		app.actions.slice(-3) == ["missions", "map", "launch"],
		"Exploration choices route to native contracts, map and flight"
	)
	for station_index in lib.stations.size():
		if not lib.station_definition(station_index).shop:
			pilot.station_id = station_index
			break
	pilot.credits = int(data.shop_credit_threshold)
	check(not panel.tab_enabled(1), "No-shop hangar stays unavailable at source credit threshold")
	pilot.credits += 1
	check(panel.tab_enabled(1), "Source high-credit exception enables hangar above threshold")
	for extent in [Vector2i(1920, 1080), Vector2i(720, 1280)]:
		viewport.size = extent
		await process_frame
		panel.layout_canvas()
		var bounds := Rect2(Vector2.ZERO, Vector2(extent))
		check(
			(panel.tabs + panel.actions).all(
				func(button): return bounds.encloses(button.get_global_rect())
			),
			"Station controls fit viewport %s" % extent
		)
	app.free()
	viewport.free()
	await process_frame


func check_pilot_status(source: PackedByteArray, lib) -> void:
	var Stats = Session.PilotStatistics
	var Panel = preload("res://src/presentation/station_menu.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.status_presentation()
	check(Panel.valid_status(data), "Source status declarations validate: " + reader.error)
	check(
		(
			data.labels.level == 415
			and data.labels.missions == 66
			and data.name == ["Keith T.", "Maxwell"]
		),
		"Original status rows and pilot name are extracted"
	)
	check(
		(
			data.reputation_thresholds == [30, 80, 160, 300, 500, 900, 1500, 2200]
			and data.reputation_max == 7
		),
		"Original reputation thresholds and source saturation"
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x5ed98, 2), 0x2361)
	var alternative := NativeData.new()
	alternative.bytes = changed
	alternative.parse_macho()
	check(
		alternative.status_presentation().labels.title == 97,
		"Changed source status title propagates"
	)
	for address in [0x5ea08, 0x5ed84, 0x5e132]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0)
		alternative = NativeData.new()
		alternative.bytes = changed
		alternative.parse_macho()
		check(
			alternative.status_presentation().is_empty(),
			"Reject unsupported status association %x" % address
		)
	var invalid := data.duplicate(true)
	invalid.reputation_thresholds[1] = 0
	check(not Panel.valid_status(invalid), "Reject non-increasing reputation thresholds")
	var original: Dictionary = lib.content.station_ui.status.duplicate(true)
	lib.content.station_ui.status.images.pointer.region = 100000
	check(not lib.valid_station_ui(), "Reject invalid status atlas reference")
	lib.content.station_ui.status = original
	check(lib.valid_station_ui(), "Status atlas declaration restored")

	var pilot := Session.new()
	pilot.configure(lib)
	check(pilot.statistics == Stats.create(), "New pilots have complete zero statistics")
	Stats.advance(pilot.statistics, 3661.25, true)
	Stats.advance(pilot.statistics, 10, false)
	Stats.advance(pilot.statistics, -10, true)
	Stats.advance(pilot.statistics, NAN, true)
	check(
		(
			pilot.statistics.play_seconds == 3661.25
			and Stats.duration(pilot.statistics.play_seconds) == "1:01:01"
		),
		"Active wall time preserves fractions; paused/invalid time does not accumulate"
	)
	for kills in [0, 29, 30, 79, 80, 1499, 1500, 2200, 10000]:
		pilot.statistics.kills = kills
		var expected: int = {0: 0, 29: 0, 30: 1, 79: 1, 80: 2, 1499: 6, 1500: 7, 2200: 7, 10000: 7}[kills]
		check(
			Stats.reputation(pilot.statistics, data) == expected,
			"Reputation boundary at %d kills" % kills
		)
	pilot.statistics.kills = 30
	var saved: Dictionary = JSON.parse_string(JSON.stringify(pilot.capture()))
	var copy := Session.new()
	copy.configure(lib)
	check(
		copy.restore(saved) and copy.statistics == pilot.statistics,
		"Statistics survive JSON save restore"
	)
	for field in ["kills", "play_seconds", "partial"]:
		var bad := saved.duplicate(true)
		bad.statistics[field] = -1
		check(
			not copy.restore(bad) and copy.statistics == pilot.statistics,
			"Reject invalid statistic without mutating pilot: " + field
		)
	var bad := saved.duplicate(true)
	bad.erase("statistics")
	check(not copy.restore(bad), "Current saves require pilot statistics")
	var legacy := saved.duplicate(true)
	legacy.schema = 26
	legacy.erase("statistics")
	legacy.elapsed = 999
	check(
		(
			copy.restore(legacy)
			and copy.statistics.partial
			and copy.statistics.play_seconds == 0
			and copy.statistics.kills == 0
		),
		"Legacy mission timer is not invented lifetime history"
	)
	check(not legacy.has("statistics"), "Migration does not mutate caller save")
	var preserved := copy.statistics.duplicate(true)
	copy.skip_campaign()
	check(
		copy.statistics == preserved and copy.chapter == 0,
		"Skip neither awards statistics nor clears recorded history"
	)

	var mission = recovery_contract_fixture(lib)
	check(mission != null, "Actual imported contract supplies statistics settlement fixture")
	if mission != null:
		var count := int(mission.mission_definition().success.count)
		for index in count:
			mission.active_job.actors[index].awake = true
			mission.damage_actor(index, float(mission.active_job.actors[index].hp))
		check(mission.statistics.kills == 0, "Pending mission kills are not yet committed")
		for tick in 300:
			mission.advance_mission(1)
			mission.advance_radio(1)
			if mission.ready_to_finish():
				break
		var kills := int(mission.active_job.kills)
		check(
			mission.finish_mission() and mission.statistics.kills == kills and kills > 0,
			"Successful mission commits source enemy kill count"
		)
		check(
			not mission.finish_mission() and mission.statistics.kills == kills,
			"Repeated settlement does not duplicate kill statistics"
		)
		copy.configure(lib)
		check(
			(
				copy.restore(JSON.parse_string(JSON.stringify(mission.capture())))
				and copy.statistics.kills == kills
			),
			"Committed statistics and reward receipt restore together"
		)

	var app := StationMenuMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_dock()
	app.station_action("status")
	var panel = app.station_panel
	check(
		(
			panel.section == "status"
			and panel.tabs.all(func(b): return not b.visible)
			and panel.actions.all(func(b): return not b.visible)
		),
		"Original Status replaces home controls"
	)
	var rows: Array = panel.status_rows()
	check(
		(
			rows.size() == 5
			and rows[1][1] == lib.text(417)
			and rows[2][1] == "1:01:01"
			and rows[3][1] == "30"
			and rows[4][1] == "0"
		),
		"Source rows show native statistics without fake completed missions"
	)
	pilot.statistics.partial = true
	check(panel.status_rows()[3][1] == "30*", "Incomplete legacy statistics are visibly marked")
	app.navigate_back()
	check(
		(
			panel.section == "info"
			and panel.actions[0].visible
			and not panel.tabs[1].disabled
			and panel.tabs[2].disabled
		),
		"Status Back restores campaign controls"
	)
	app.free()
	await process_frame


func check_pilot_clock(lib) -> void:
	var app = StationMenuMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.session = Session.new()
	app.session.configure(lib)
	for location in ["dock", "market", "contracts", "map", "briefing", "recovery", "flight"]:
		app.screen = location
		app.record_play_time(1,true)
	check(app.session.statistics.play_seconds == 7, "All pilot screens contribute wall time")
	for location in ["title", "import", "options", "pause", "defeat", "survival_result"]:
		app.screen = location
		app.record_play_time(100,true)
	app.screen = "dock"
	app.record_play_time(100,false)
	app.paused = true
	app.record_play_time(100,true)
	app.paused = false
	app.transient_preview = true
	app.record_play_time(100,true)
	app.transient_preview = false
	app.session.slot = "survival"
	app.record_play_time(100,true)
	check(app.session.statistics.play_seconds == 7, "Title, pause, focus loss, transient preview and survival do not count pilot time")
	app.session.slot = "campaign"
	app.screen = "flight"
	app.flight = {"time_factor": 8}
	app.record_play_time(.25,true)
	check(app.session.statistics.play_seconds == 7.25, "Flight speedup does not multiply play time")
	app.flight = null
	app.free()
	await process_frame


class HangarMain:
	extends MenuSceneMain
	var saves := 0

	func save_game(_announce: bool = true) -> bool:
		saves += 1
		return true


func check_hangar(source: PackedByteArray, lib) -> void:
	var Catalogue = preload("res://src/presentation/hangar_catalogue.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.hangar_presentation()
	check(Catalogue.valid_data(data), "Imported Hangar declarations validate: " + reader.error)
	check(
		data.tabs.map(func(t): return t.label) == [114, 115, 116],
		"Original Ship/Cargo/Shop tab associations"
	)
	check(
		data.pictures.ship_icons.size() == 10 and data.pictures.item_icons.size() == 28,
		"Read complete source catalogue art tables"
	)
	var icons: Array = []
	for key in data.pictures:
		icons.append_array(data.pictures[key])
	check(
		icons.all(func(v): return lib.ui_image(v).get_size().x > 0),
		"Every supplied catalogue image resolves"
	)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x1c96a, 2), 0x2351)
	var alternate := NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(
		alternate.hangar_image_binding(580).region == 81,
		"Changed split ship icon declaration propagates"
	)
	changed.encode_u16(reader.file_offset(0x1c8dc, 2), 0)
	alternate = NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(
		alternate.hangar_image_binding(580).is_empty(), "Reject unsupported split ship icon record"
	)
	await check_hangar_runtime(lib)
	await check_hangar_hints(source, lib)
	check_hangar_quantity_source(source)
	await check_hangar_quantity(lib)


func check_hangar_runtime(lib) -> void:
	var Catalogue = preload("res://src/presentation/hangar_catalogue.gd")
	var data: Dictionary = lib.content.hangar_ui
	var pilot := Session.new()
	pilot.configure(lib)
	var entries := Catalogue.entries(lib, pilot, "ship")
	check(
		entries[0].id == pilot.ship_id and entries[0].kind == "ship",
		"Ship tab displays actual pilot ship"
	)
	check(
		(
			Catalogue.description(lib, entries[0])
			== lib.text(
				int(data.description.ships.base + data.description.ships.stride * pilot.ship_id)
			)
		),
		"Ship description comes from supplied localization association"
	)
	check(Catalogue.entries(lib, pilot, "cargo").is_empty(), "Empty cargo stays empty")
	var app := HangarMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_market()
	var panel = app.hangar_panel
	await process_frame
	check_desktop_tab_layout(panel)
	check(
		panel.section == "ship" and panel.tabs.size() == 3 and not app.page.visible,
		"Hangar replaces generic market with original three-tab panel"
	)
	panel.handle_action("info")
	check(
		(
			panel.details
			and panel.rows.get_child(0).text == Catalogue.information(lib, pilot, panel.current())
		),
		"Info displays original description"
	)
	app.navigate_back()
	check(not panel.details and app.screen == "market", "Back first leaves item Info")
	panel.open_tab("shop")
	var purchase := -1
	for index in panel.records.size():
		var entry: Dictionary = panel.records[index]
		if entry.kind == "equipment" and pilot.credits >= entry.price:
			purchase = index
			break
	check(purchase >= 0, "Source opening shop offers an affordable item")
	if purchase >= 0:
		panel.select_entry(purchase)
		var offer: Dictionary = panel.current().duplicate()
		var old_credits := pilot.credits
		panel.handle_action("primary")
		await process_frame
		check(
			(
				pilot.credits == old_credits - offer.price
				and pilot.loadout.hold.size() == 1
				and app.saves == 1
			),
			"Buy uses original offer price and persists transaction"
		)
		check(
			panel.section == "shop" and panel.selected == mini(purchase, panel.records.size() - 1),
			"Transaction keeps shop and stable selection"
		)
		panel.open_tab("cargo")
		check(
			panel.current().id == offer.id and panel.primary.text == "Install",
			"Purchased equipment appears in Cargo with installation action"
		)
		if panel.primary.disabled == false:
			panel.handle_action("primary")
			check(
				pilot.loadout.fitted.any(func(v): return v.get("id") == offer.id),
				"Install delegates to native fitting rules"
			)
		panel.open_tab("ship")
		for index in panel.records.size():
			if panel.records[index].source == "fitted" and panel.records[index].kind == "equipment":
				panel.select_entry(index)
				break
		panel.handle_action("primary")
		check(not pilot.loadout.hold.is_empty(), "Ship tab moves equipped item back to hold")
		panel.open_tab("cargo")
		var count := pilot.loadout.hold.size()
		panel.handle_action("secondary")
		check(
			pilot.loadout.hold.size() == count - 1, "Cargo Sell uses native inventory transaction"
		)
	app.notify("Test market notice")
	check(
		panel.notice == "Test market notice",
		"Market errors remain visible when generic footer is hidden"
	)
	app.navigate_back()
	check(
		app.screen == "dock" and app.hangar_panel == null and not panel.visible,
		"Back disposes market controls and restores station home"
	)
	app.free()
	await process_frame


func check_hangar_quantity(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib)
	var item := int(lib.content.recovery.items[0])
	var key := str(item)
	pilot.cargo[key] = 3
	var initial := pilot.credits
	var offers: Array = pilot.market_offers().duplicate(true)
	for amount in [-1, 0, 4]:
		check(not pilot.sell_cargo(item, amount), "Reject unavailable sale amount %d" % amount)
	check(pilot.credits == initial and pilot.cargo[key] == 3 and pilot.market_offers() == offers, "Invalid batch sale leaves credits, cargo and stock unchanged")
	var app := HangarMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_market("cargo")
	var panel = app.hangar_panel
	panel.handle_action("primary")
	var dialog = panel.overlay
	check(dialog != null and dialog.amount == 3 and not panel.canvas.visible, "Cargo sale opens modal with source whole-stack default")
	check(dialog.confirm_button.text == lib.text(int(lib.content.hangar_ui.quantity.labels.sell)), "Sale uses imported action label")
	dialog.handle_action("plus")
	check(dialog.amount == 3 and dialog.plus_button.disabled, "Quantity cannot exceed the stack")
	for step in 4: dialog.handle_action("minus")
	check(dialog.amount == 0 and dialog.confirm_button.disabled and dialog.minus_button.disabled, "Zero amount disables sale and subtraction")
	dialog.handle_action("sell")
	check(pilot.cargo[key] == 3 and app.saves == 0, "Zero amount cannot submit a transaction")
	app.navigate_back()
	check(panel.overlay == null and app.screen == "market" and pilot.cargo[key] == 3 and app.saves == 0, "Back cancels the sale without changing inventory or leaving Hangar")
	panel.handle_action("primary")
	dialog = panel.overlay
	dialog.handle_action("minus")
	var price := pilot.Market.cargo_price(lib, item, pilot.station_id)
	var stock_before := 0
	for offer in pilot.market_offers():
		if offer.kind == "cargo" and int(offer.id) == item and int(offer.price) == price:
			stock_before += int(offer.count)
	dialog.handle_action("sell")
	var stock_after := 0
	for offer in pilot.market_offers():
		if offer.kind == "cargo" and int(offer.id) == item and int(offer.price) == price:
			stock_after += int(offer.count)
	check(pilot.cargo[key] == 1 and pilot.credits == initial + price * 2 and stock_after == stock_before + 2 and app.saves == 1, "Selected quantity settles once into credits, hold and shop stock")
	check(panel.overlay == null and panel.current().count == 1 and panel.canvas.visible, "Sale closes modal and refreshes remaining stack")
	panel.handle_action("primary")
	# A stale selection must fail atomically rather than oversell changed cargo.
	pilot.cargo.erase(key)
	var settled := pilot.credits
	panel.overlay.handle_action("sell")
	check(pilot.credits == settled and app.saves == 1 and not panel.notice.is_empty(), "Stale sale is rejected visibly without duplicate settlement")
	for group in ["ship_previews", "item_previews"]:
		for binding in lib.content.hangar_ui.pictures[group]:
			var texture: Texture2D = lib.ui_image(binding)
			var rect: Rect2 = panel.preview_rect(texture)
			var bounds := Rect2(panel.preview_origin() + Vector2(8, 32), panel.art.preview.get_size() - Vector2(16, 92))
			check(bounds.grow(.001).encloses(rect) and is_equal_approx(rect.size.aspect(), texture.get_size().aspect()), "Original catalogue preview fits without distortion")
	await process_frame
	app.queue_free()
	for frame in 4:
		await process_frame


func check_hangar_quantity_source(source: PackedByteArray) -> void:
	var Sale = preload("res://src/presentation/cargo_sale.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var original := reader.hangar_quantity_presentation()
	check(Sale.valid_data(original) and reader.error.is_empty(), "Cargo sale source declaration validates")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x68404, 2), 0x235b)
	var alternate := NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(alternate.hangar_quantity_presentation().y == original.y + 1, "Changed source sale position propagates")
	changed.encode_u16(reader.file_offset(0x68370, 2), 0)
	alternate = NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(alternate.hangar_quantity_presentation().is_empty() and not alternate.error.is_empty(), "Unsupported initial amount association is rejected")
	var invalid := original.duplicate(true)
	invalid.images.step.region = -1
	check(not Sale.valid_data(invalid), "Invalid stepper art is rejected")
	invalid = original.duplicate(true)
	invalid.labels.erase("cancel")
	check(not Sale.valid_data(invalid), "Missing cancellation label is rejected")


func check_ship_exchange(lib, source: PackedByteArray) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.hangar_exchange_presentation()
	var Exchange = preload("res://src/presentation/ship_exchange.gd")
	check(Exchange.valid_data(data) and reader.error.is_empty(), "Exchange source declaration validates")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x5cabe, 2), 0x214c)
	var alternate := NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(alternate.hangar_exchange_presentation().labels.price == data.labels.price + 1, "Changed exchange label association propagates")
	changed.encode_u16(reader.file_offset(0x46e24, 2), 0)
	alternate = NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(alternate.hangar_exchange_presentation().is_empty(), "Unsupported exchange footer association is rejected")
	var pilot := Session.new()
	pilot.configure(lib)
	pilot.campaign_state = "skipped"
	pilot.credits = 1000000
	var index := -1
	for station in lib.stations.size():
		pilot.station_id = station
		var offers := pilot.market_offers()
		for cursor in offers.size():
			if offers[cursor].kind == "ship" and int(offers[cursor].id) != pilot.ship_id:
				index = cursor
				break
		if index >= 0:
			break
	check(index >= 0, "Native generated station market supplies a different ship")
	if index < 0:
		return
	var item := int(lib.content.recovery.items[0])
	pilot.cargo[str(item)] = 1
	var quote := pilot.ship_offer_quote(index)
	check(not quote.is_empty() and quote.allowed, "Available ship produces a valid exchange quote")
	check(quote.remaining == pilot.credits + pilot.ship_value - int(pilot.market_offers()[index].price), "Quote derives remaining credits from actual offer and trade-in")
	var inventory := pilot.loadout.capture()
	var funds := pilot.credits
	var hull := pilot.ship_id
	var stock: int = pilot.market_offers()[index].count
	check(pilot.loadout.capture() == inventory and pilot.credits == funds and pilot.ship_id == hull, "Review does not change the pilot")
	var tampered := quote.duplicate(true)
	tampered.remaining += 1
	check(not pilot.buy_ship_quote(tampered) and pilot.credits == funds and pilot.market_offers()[index].count == stock, "Tampered quote cannot change transaction value")
	pilot.credits -= 1
	check(not pilot.buy_ship_quote(quote) and pilot.ship_id == hull, "Changed pilot balance invalidates reviewed quote")
	pilot.credits = funds
	var price: int = pilot.market_offers()[index].price
	pilot.market_offers()[index].price += 1
	check(not pilot.buy_ship_quote(quote) and pilot.ship_id == hull, "Changed offer price invalidates reviewed quote")
	pilot.market_offers()[index].price = price
	var app := HangarMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_market("shop")
	var panel = app.hangar_panel
	for cursor in panel.records.size():
		if panel.records[cursor].index == index:
			panel.select_entry(cursor)
			break
	panel.handle_action("primary")
	var dialog = panel.overlay
	check(dialog != null and app.saves == 0 and pilot.ship_id == hull, "Exchange opens review without immediately buying")
	check(dialog.summary_rows().size() == 5 and dialog.body.text.contains("All equipment and cargo are kept"), "Review shows original rows and actual transfer policy")
	app.navigate_back()
	check(panel.overlay == null and panel.canvas.visible and app.screen == "market" and app.saves == 0, "Back cancels exchange without leaving Shop")
	panel.handle_action("primary")
	panel.overlay.handle_action("buy")
	check(pilot.ship_id == quote.offer.id and pilot.credits == quote.remaining and app.saves == 1, "Confirmed exchange applies reviewed hull and credit balance once")
	check(pilot.cargo[str(item)] == 1 and pilot.loadout.capture() == quote.transfer and pilot.market_offers()[index].count == stock - 1, "Exchange retains cargo, transfers equipment and consumes one stock hull")
	check(not pilot.buy_ship_quote(quote) and app.saves == 1, "Previously settled quote cannot be replayed")
	check(panel.overlay == null and panel.section == "shop", "Completed exchange restores Shop")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	app.queue_free()
	for frame in 4:
		await process_frame


func check_ship_exchange_limits(lib) -> void:
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.market_seed = 7
	pilot.credits = 1000000
	var index := -1
	for station in lib.stations.size():
		pilot.station_id = station
		for cursor in pilot.market_offers().size():
			var offer: Dictionary = pilot.market_offers()[cursor]
			if offer.kind == "ship" and int(offer.id) != pilot.ship_id:
				index = cursor
				break
		if index >= 0:
			break
	check(index >= 0, "Source market supplies limit-test hull")
	if index < 0:
		return
	var quote := pilot.ship_offer_quote(index)
	pilot.credits = 0
	pilot.ship_value = 0
	var limited := pilot.ship_offer_quote(index)
	check(not limited.allowed and limited.remaining < 0 and not pilot.buy_ship_quote(limited), "Unaffordable reviewed exchange cannot settle")
	pilot.credits = 1000000
	pilot.ship_value = int(quote.trade_in)
	var item := int(lib.content.recovery.items[0])
	var target := int(pilot.market_offers()[index].id)
	var capacity := int(lib.ship_definition(target).capacity)
	pilot.cargo[str(item)] = capacity + 1
	limited = pilot.ship_offer_quote(index)
	check(not limited.allowed and limited.transfer.is_empty() and not pilot.buy_ship_quote(limited), "Cargo overflow blocks exchange without selling or discarding inventory")
	check(pilot.cargo[str(item)] == capacity + 1 and pilot.ship_id == quote.current_ship, "Rejected capacity quote preserves cargo and hull")
	pilot.cargo.clear()
	quote = pilot.ship_offer_quote(index)
	pilot.loadout.hold.append({"id": pilot.weapon_id, "value": 1})
	check(not pilot.buy_ship_quote(quote), "Inventory changed since review invalidates quote")
	pilot.loadout.hold.clear()
	var moved_item := -1
	for candidate in lib.items.size():
		var category := int(lib.items[candidate][1])
		if category < 0 or category >= lib.SHIELD_CATEGORY or pilot.loadout.supports(target, candidate):
			continue
		for old_ship in lib.ships.size():
			if old_ship != target and pilot.loadout.supports(old_ship, candidate):
				pilot.ship_id = old_ship
				moved_item = candidate
				break
		if moved_item >= 0:
			break
	check(moved_item >= 0, "Supplied mounts provide an incompatible equipment transfer case")
	if moved_item >= 0:
		var category := int(lib.items[moved_item][1])
		var record := {"id": moved_item, "value": 7}
		pilot.loadout.fitted[category] = record
		quote = pilot.ship_offer_quote(index)
		check(quote.allowed and quote.transfer.hold.has(record) and quote.transfer.fitted[category].is_empty(), "Quote predicts moving incompatible mounted gear into hold")
		check(pilot.buy_ship_quote(quote) and pilot.loadout.hold.has(record), "Confirmed exchange performs the predicted equipment transfer")


func check_hangar_scene(source: PackedByteArray, lib) -> void:
	var Scene = preload("res://src/presentation/hangar_scene.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.hangar_scene_presentation()
	check(Scene.valid_data(data), "Hangar source scene declaration: " + reader.error)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x13d36, 2), 0x2397)
	var alternate := NativeData.new()
	alternate.bytes = changed
	alternate.parse_macho()
	check(alternate.hangar_scene_presentation().camera.y == 604, "Hangar camera follows changed source constant")
	for address in [0x33e66, 0x33f0e, 0x33ef2, 0x57b7e, 0x14802, 0x136f8]:
		changed = source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0)
		alternate = NativeData.new()
		alternate.bytes = changed
		alternate.parse_macho()
		check(alternate.hangar_scene_presentation().is_empty(), "Reject unsupported Hangar consumer %x" % address)
	for field in ["near", "entrance_seconds"]:
		var invalid := data.duplicate(true)
		invalid.camera[field] = 0
		check(not Scene.valid_data(invalid), "Reject invalid Hangar " + field)
	var invalid := data.duplicate(true)
	invalid.stock_positions[0] = [0, NAN, 0]
	check(not Scene.valid_data(invalid), "Reject nonfinite parking position")
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.market_seed = 7
	pilot.credits = 1000000
	var selected_offer := -1
	for location in lib.stations.size():
		pilot.station_id = location
		for index in pilot.market_offers().size():
			var offer: Dictionary = pilot.market_offers()[index]
			if offer.kind == "ship" and offer.id != pilot.ship_id:
				selected_offer = index
				break
		if selected_offer >= 0:
			break
	check(selected_offer >= 0, "Actual stock supplies Hangar exchange display")
	if selected_offer < 0:
		return
	var app := HangarMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_market()
	var scene = app.menu_scene
	check(scene != null and scene.get_script() == Scene and scene.supported, "Main opens supplied indoor Hangar")
	if scene == null or scene.get_script() != Scene:
		app.queue_free()
		await process_frame
		return
	scene.set_process(false)
	var offers := pilot.market_offers().duplicate(true)
	var count := 0
	for offer in offers:
		if offer.kind == "ship": count += int(offer.count)
	check(scene.inventory.size() == count and scene.hulls.get_child_count() == count + 1, "Display includes actual stock quantities and player ship")
	check(scene.hulls.get_child(0).position == preload("res://src/simulation/mission.gd").point(data.player_position), "Player occupies source parking position")
	check(is_equal_approx(scene.hulls.get_child(0).get_child(1).position.y, data.shadow_y * .02), "Imported shadow uses source floor offset")
	var before := JSON.stringify(pilot.capture())
	scene.advance(1.0)
	check(JSON.stringify(pilot.capture()) == before, "Presentation clock does not mutate pilot or stock")
	var time: float = scene.elapsed
	scene.hide()
	scene.advance(10)
	check(scene.elapsed == time, "Hidden Hangar pauses its entrance")
	scene.show()
	scene.advance(NAN)
	scene.advance(-1)
	check(scene.elapsed == time, "Invalid presentation deltas do not move camera")
	var camera_position: Vector3 = scene.camera.position
	var same_hulls = scene.hulls
	check(scene.refresh_inventory(pilot.ship_id, offers) and scene.hulls == same_hulls, "Unchanged equipment/stock does not rebuild hulls")
	var excessive := offers.duplicate(true)
	excessive[selected_offer].count = data.stock_positions.size() + 1
	check(not scene.refresh_inventory(pilot.ship_id, excessive) and scene.hulls == same_hulls, "Unsupported stock count leaves previous display intact")
	var quote := pilot.ship_offer_quote(selected_offer)
	app.hangar_transaction("exchange", quote)
	check(app.saves == 1 and scene.player_ship == pilot.ship_id and scene.hulls != same_hulls, "Successful purchase refreshes owned hull and saves once")
	check(scene.inventory.size() == count - 1, "Purchase removes precisely one displayed stock hull")
	check(scene.camera.position == camera_position and scene.elapsed == time, "Purchase preserves entrance camera progress")
	check(app.menu_scene == scene and app.hangar_panel.section == "ship", "Purchase keeps Hangar scene and tab alive")
	scene.advance(10)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_HANGAR_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_HANGAR_CAPTURE_DIR").path_join("hangar-interior-ui.png"))
	app.show_dock()
	check(not scene.visible and not scene.is_processing(), "Leaving Hangar retires camera scene before next draw")
	await process_frame
	check(not is_instance_valid(scene), "Retired Hangar resources leave scene tree")
	app.queue_free()
	await process_frame
	for race_scene in [false, true]:
		var location := -1
		for index in lib.stations.size():
			if (int(lib.station_definition(index).race) == int(data.race)) == race_scene:
				location = index
				break
		check(location >= 0, "Supplied location selects Hangar race variant")
		if location < 0:
			continue
		var room = Scene.new()
		root.add_child(room)
		check(room.configure(lib, location, pilot.ship_id, []), "Race-specific interior and lights load: " + room.error)
		room.set_process(false)
		room.advance(10)
		var room_data: Dictionary = data.interiors.race if race_scene else data.interiors.default
		check(room.interior.get_child(0).mesh == lib.mesh(str(lib.content.resources[str(int(room_data.body))].path).get_file().trim_suffix(".aem")), "Race chooses actual imported interior mesh")
		check(room.inventory.is_empty() and room.hulls.get_child_count() == 1, "Empty market creates no invented display stock")
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			if not OS.get_environment("GOF_HANGAR_CAPTURE_DIR").is_empty():
				root.get_texture().get_image().save_png(OS.get_environment("GOF_HANGAR_CAPTURE_DIR").path_join("hangar-interior-%s.png" % ("alien" if race_scene else "terran")))
		room.queue_free()
		await process_frame


func check_hangar_drift(source: PackedByteArray, lib) -> void:
	var Drift = preload("res://src/presentation/hangar_drift.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.hangar_camera_drift()
	check(Drift.valid_data(data), "Source Hangar drift ranges: " + reader.error)
	check(data.initial_low == [-300, -300, -300] and data.initial_high == [300, 150, 300], "Source initial camera ranges retain asymmetric Y movement")
	check(is_equal_approx(data.seconds, 16.384) and data.threshold == 10, "Source drift phase and endpoint threshold")
	for address in [0x14710, 0x148aa, 0x149ac, 0x14a68, 0x146c0, 0x5f714]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0)
		var other := NativeData.new()
		other.bytes = changed
		other.parse_macho()
		check(other.hangar_camera_drift().is_empty(), "Reject unsupported drift consumer %x" % address)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x148f0, 2), 0x2163)
	var other := NativeData.new()
	other.bytes = changed
	other.parse_macho()
	check(other.hangar_camera_drift().high_spread[0] == -99, "Source random extent changes propagate")
	for field in ["seconds", "threshold", "far"]:
		var invalid := data.duplicate(true)
		invalid[field] = 0
		check(not Drift.valid_data(invalid), "Reject invalid drift " + field)
	var invalid := data.duplicate(true)
	invalid.initial_low[1] = 0
	check(not Drift.valid_data(invalid), "Reject zero-length initial drift range")
	var base := Vector3(2500, 600, -5550)
	var reference = Drift.new()
	reference.configure(data, base, 7)
	reference.advance(300)
	for rate in [30, 60, 144]:
		var sampled = Drift.new()
		sampled.configure(data, base, 7)
		var bounded := true
		for frame in rate * 300:
			sampled.advance(1.0 / rate)
			var offset: Vector3 = sampled.position - base
			bounded = bounded and offset.x >= -1200 and offset.x <= 300 and offset.y >= -900 and offset.y <= 150 and offset.z >= -900 and offset.z <= 375
		check(sampled.position.distance_to(reference.position) < .00001, "Drift independent of redraw rate %d" % rate)
		check(bounded, "All native drift samples stay inside supplied ranges %d" % rate)
		for index in 3:
			check(sampled.axes[index].legs == reference.axes[index].legs, "Drift leg choices stable across redraws")
	var boundary = Drift.new()
	boundary.configure(data, base, 17)
	var first: Dictionary = boundary.axes[0].duplicate()
	boundary.advance(float(first.duration))
	check(boundary.axes[0].legs == 1 and is_equal_approx(absf(boundary.position.x - float(first.end)), data.threshold), "Drift reverses continuously at the supplied proximity threshold")
	var position: Vector3 = boundary.position
	boundary.advance(NAN)
	boundary.advance(-1)
	check(boundary.position == position, "Invalid cosmetic time leaves drift unchanged")
	var Scene = preload("res://src/presentation/hangar_scene.gd")
	var pilot := Session.new()
	pilot.configure(lib)
	var scene = Scene.new()
	root.add_child(scene)
	check(scene.configure(lib, pilot.station_id, pilot.ship_id, pilot.market_offers()), "Hangar with native idle camera loads")
	scene.set_process(false)
	scene.advance(float(scene.data.camera.entrance_seconds) + 30)
	check(scene.drift.axes[0].legs > 0, "Entrance overflow advances idle camera in the same frame")
	var target: Vector3 = scene.hulls.get_child(0).global_position
	check((-scene.camera.global_basis.z).dot((target - scene.camera.global_position).normalized()) > .999999, "Idle camera looks at actual parked player hull")
	check(scene.camera.global_basis.y.dot(Vector3.UP) > .9, "Idle camera uses parked ship up axis")
	var view: Transform3D = scene.camera.transform
	scene.hide()
	scene.advance(100)
	check(scene.camera.transform == view, "Hidden idle camera stays paused")
	scene.show()
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_HANGAR_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_HANGAR_CAPTURE_DIR").path_join("hangar-idle-camera.png"))
	scene.queue_free()
	await process_frame


class BoardMain extends MenuSceneMain:
	var launches := 0
	func launch(_reuse: bool = false) -> void:
		launches += 1
		clear_page()


func check_mission_board(source: PackedByteArray, lib) -> void:
	var Board = preload("res://src/presentation/mission_board.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.mission_board_presentation()
	check(Board.valid_data(data), "Source mission-board declarations: " + reader.error)
	check(data.labels.title == 612 and data.images.button.region == 40, "Source Job Board title/button associations")
	for address in [0x48d64, 0x4903c, 0x49164, 0x492d8, 0x494d6, 0x49500]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0)
		var other := NativeData.new()
		other.bytes = changed
		other.parse_macho()
		check(other.mission_board_presentation().is_empty(), "Reject unsupported board consumer %x" % address)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x48d5c, 2), 0x212e)
	var other := NativeData.new()
	other.bytes = changed
	other.parse_macho()
	check(other.mission_board_presentation().list[0] == 46, "Board layout follows changed source value")
	var invalid := data.duplicate(true)
	invalid.row_height = 0
	check(not Board.valid_data(invalid), "Reject zero-height board rows")
	var pilot := Session.new()
	pilot.configure(lib, true)
	pilot.market_seed = 7
	var app := BoardMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	var snapshot := JSON.stringify(pilot.capture())
	app.show_contracts()
	var board = app.board_panel
	check(board != null and not app.page.visible and board.offers == pilot.contract_offers(), "Original board replaces generic contracts page with actual offers")
	check(board.selected == -1 and not board.accept.visible, "Board waits for selection before offering acceptance")
	check(board.rows.get_child_count() == board.offers.size(), "Every generated offer has a selectable row")
	if board.offers.is_empty():
		app.queue_free()
		await process_frame
		return
	board.rows.get_child(0).grab_focus()
	check(board.selected == 0 and board.accept.visible, "Keyboard/controller focus selects a contract")
	check(JSON.stringify(pilot.capture()) == snapshot, "Browsing board leaves pilot and generated offer terms unchanged")
	board.handle_action("info")
	check(board.details and board.description.text.contains(lib.text(int(lib.content.contracts.types[int(board.offers[0].type)].description))) if not board.offers[0].special else board.description.text.contains(lib.text(int(data.labels.special_description))), "Info shows supplied mission briefing")
	check(not board.info.visible and board.accept.visible, "Info retains Accept and gives Back ownership of the description")
	app.navigate_back()
	check(app.board_panel == board and not board.details and board.selected == 0, "Back returns from Info to the same selected offer")
	var reference: Dictionary = board.references[0].duplicate()
	var offer: Dictionary = board.offers[0].duplicate(true)
	var altered := offer.duplicate(true)
	altered.reward += 1
	app.accept_board_offer(reference, altered)
	check(app.launches == 0 and pilot.docked and not board.notice.text.is_empty(), "Modified displayed terms cannot launch a different contract")
	pilot.market_generation += 1
	app.accept_board_offer(reference, offer)
	check(app.launches == 0 and pilot.active_job.is_empty(), "Outdated station visit cannot accept a board index")
	pilot.market_generation -= 1
	board.show_notice("")
	var original: Dictionary = board.offers[0].duplicate(true)
	board.offers[0].special = true
	board.offers[0].client.portrait = data.special_portrait
	check(board.title_for(board.offers[0]) == lib.text(int(data.labels.special)), "Special client does not expose the hidden mission type")
	board.handle_action("info")
	check(board.description.text.ends_with(lib.text(int(data.labels.special_description))), "Special client uses original mystery briefing")
	board.offers[0] = original
	board.handle_action("back")
	var rate := offer.duplicate(true)
	rate.reward_unit = "per_target"
	check(board.reward_for(rate) == str(data.rate_prefix) + str(rate.reward), "Per-target reward retains supplied multiplier notation")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_BOARD_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_BOARD_CAPTURE_DIR").path_join("mission-board-native.png"))
	board.handle_action("info")
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_BOARD_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_BOARD_CAPTURE_DIR").path_join("mission-board-info.png"))
	board.handle_action("accept")
	check(app.launches == 1 and not pilot.docked and pilot.active_job.get("contract") == reference, "Accept starts selected native encounter using the displayed reference")
	check(app.board_panel == null and not board.visible, "Launching retires board controls immediately")
	await process_frame
	check(not is_instance_valid(board), "Board and detached description are released")
	app.queue_free()
	await process_frame


class DestinationMain extends MenuSceneMain:
	var saves := 0
	var arrival_opacity := -1.0
	func save_game(_announce: bool = true) -> bool:
		saves += 1
		return true
	func commit_travel(pilot, panel) -> void:
		arrival_opacity = travel_transition.color.a
		super.commit_travel(pilot, panel)


func check_destination_menu(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var layout := reader.destination_presentation()
	check(not layout.is_empty() and lib.valid_station_ui(), "Imported destination layout validates")
	for address in [0x52d70, 0x4cfec, 0x4d00e]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address, 2), 0)
		var other := NativeData.new()
		other.bytes = changed
		other.parse_macho()
		check(other.destination_presentation().is_empty(), "Reject unsupported destination consumer %x" % address)
	var invalid := layout.duplicate(true)
	invalid.list[2] = 0
	check(not preload("res://src/presentation/destination_menu.gd").valid_layout(invalid), "Reject unusable destination layout")
	var pilot := Session.new()
	pilot.configure(lib, true)
	var target := -1
	for index in lib.stations.size():
		var fare: Dictionary = pilot.travel_quote(index)
		if index != pilot.station_id and fare.total <= pilot.credits and fare.total > 0:
			target = index
			break
	check(target >= 0, "Initial pilot can afford a supplied destination")
	if target < 0: return
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_map()
	var chart = app.galaxy_map
	var original := JSON.stringify(pilot.capture())
	app.select_destination(target)
	var panel = app.destination_panel
	check(panel != null and not app.page.visible, "Destination Info owns the full menu canvas")
	check(panel.info_rows().size() == 6 and panel.info_rows()[2][1] == "?", "Unvisited Info masks technology and adds actual fare rows")
	check(panel.preview_station() == target and JSON.stringify(pilot.capture()) == original, "Preview uses selected location without moving pilot or changing state")
	var quote: Dictionary = pilot.travel_quote(target)
	check(panel.info_rows()[4][1] == str(quote.flight) and panel.info_rows()[5][1] == str(quote.bribe), "Destination displays the native flight/bribe quote")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").path_join("destination-info-native.png"))
	app.navigate_back()
	check(app.destination_panel == null and app.map_panel.visible and app.galaxy_map == chart and chart.level == 2, "Back preserves map object, system and selection")
	app.select_destination(pilot.station_id)
	check(not app.destination_panel.travel_button.visible, "Current station only offers Back")
	app.close_destination()
	app.select_destination(target)
	panel = app.destination_panel
	panel.quote.total += 1
	app.travel_selected()
	check(pilot.station_id != target and app.saves == 0 and panel.travel_button.disabled and not panel.notice.text.is_empty(), "Changed displayed fare is rejected without travel/save")
	app.close_destination()
	var credits := pilot.credits
	pilot.credits = 0
	app.select_destination(target)
	check(app.destination_panel.travel_button.disabled and not app.destination_panel.notice.text.is_empty(), "Unaffordable destination remains reviewable with an explanation")
	app.close_destination()
	pilot.credits = credits
	app.select_destination(target)
	app.travel_selected()
	var transition = app.travel_transition
	check(is_instance_valid(transition) and pilot.station_id != target and app.saves == 0, "Travel fades out before changing station or charging")
	app.travel_selected()
	check(app.travel_transition == transition, "Repeated Travel cannot start another transition")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	check(app.destination_panel != null and app.screen == "map", "Travel transition blocks background Back input")
	await transition.tree_exited
	check(is_equal_approx(app.arrival_opacity, 1.0), "Destination switches only while the fade is fully opaque")
	check(pilot.station_id == target and pilot.credits == credits - quote.total and pilot.visited.has(target), "Travel applies actual native fare and discovers destination")
	check(app.saves == 1 and app.destination_panel == null and app.screen == "dock", "Travel saves once and retires destination interface")
	check(app.station_panel.info_rows() == lib.station_info(target,true) and app.station_panel.preview_station() == target, "Shared station rendering still uses current station information")
	app.queue_free()
	await process_frame


func check_desktop_tab_layout(panel) -> void:
	if OS.has_feature("mobile"):
		return
	var box: Array = panel.data.box
	var first: Rect2 = panel.tabs[0].get_rect()
	var last: Rect2 = panel.tabs[-1].get_rect()
	check(is_equal_approx(first.position.x, box[0]) and is_equal_approx(last.end.x, box[0] + box[2]), "Desktop tabs span the panel width")
	for index in panel.tabs.size():
		var rect: Rect2 = panel.tabs[index].get_rect()
		check(rect.end.y <= box[1] + panel.art.tab_edge_idle.get_height(), "Desktop tab cannot overlap panel content")
		if index > 0:
			check(is_equal_approx(panel.tabs[index - 1].get_rect().end.x, rect.position.x), "Desktop tabs meet without gaps or overlap")


func check_destination_scene(source: PackedByteArray, lib) -> void:
	var Scene = preload("res://src/presentation/destination_scene.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.destination_scene_presentation()
	check(Scene.valid_data(data), "Source destination scene: " + reader.error)
	if data.is_empty(): return
	check(data.planet_mode == 10 and data.orbital_mode == 9 and data.station_z == 32768 and data.special_z == 10000, "Original destination scene selectors and station depths")
	check(Combat.vector(data.look_offset) == Vector3(0,650,0) and Combat.vector(data.position_offset) == Vector3(0,850,-8500), "Original identity-target camera offsets")
	for address in [0x13ade, 0x5f7bc, 0x5f830, 0x13782]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0)
		var other := NativeData.new()
		other.bytes = changed
		other.parse_macho()
		check(other.destination_scene_presentation().is_empty(), "Reject unsupported destination scene binding %x" % address)
	var look: Vector3 = Session.Mission.point(data.look_offset) * data.initial_scale
	var camera: Vector3 = Session.Mission.point(data.position_offset) * data.initial_scale
	var aim := Session.Mission.point(data.look_offset)
	var offset := Session.Mission.point(data.position_offset)
	for tick in 180:
		var next_camera: Vector3 = look + (offset - camera) * data.position_blend
		look = look.lerp(aim,data.look_blend)
		camera = next_camera
		var pose: Dictionary = Scene.tick_pose(data,tick + 1)
		if tick in [0,1,7,59,179]:
			check(camera.distance_to(pose.position) < .0001 and look.distance_to(pose.look) < .0001, "Analytic camera retains coupled source recurrence at tick %d" % tick)
	var invalid := data.duplicate(true)
	invalid.reference_seconds = 0
	check(not Scene.valid_data(invalid), "Reject unusable destination camera clock")
	var pilot := Session.new()
	pilot.configure(lib,true)
	var before := JSON.stringify(pilot.capture())
	var chosen: Array[int] = []
	for planet in [false,true]:
		for index in lib.stations.size():
			if lib.station_definition(index).planet == planet:
				chosen.append(index)
				break
	for index in lib.stations.size():
		if not lib.station_definition(index).planet and lib.location_station_type(index) == data.special_type:
			chosen.append(index)
			break
	for index in chosen:
		var scene = Scene.new()
		root.add_child(scene)
		scene.set_process(false)
		check(scene.configure(lib,index), "Configure actual destination scene %d: %s" % [index,scene.error])
		var kind: int = lib.station_definition(index).image if lib.station_definition(index).planet else lib.location_station_type(index)
		check(scene.get("ships") == null and scene.scene_mode == (10 if lib.station_definition(index).planet else 9), "Destination uses source preview mode without dock traffic")
		if scene.station != null:
			check(scene.station.position == Session.Mission.point([0,0,data.special_z if kind == data.special_type else data.station_z]) and scene.station.scale == Vector3.ONE, "Preview station uses unscaled source depth")
		for frame in 60: scene.advance(1.0/60.0)
		var pose: Dictionary = Scene.pose_at(data,1)
		check(scene.camera.position.distance_to(pose.position) < .0001, "Scene camera uses elapsed native pose")
		scene.hide()
		var elapsed: float = scene.elapsed
		scene.advance(2)
		check(scene.elapsed == elapsed and not scene.flare_layer.visible, "Hidden destination freezes camera/station and flare")
		scene.queue_free()
		await process_frame
	check(JSON.stringify(pilot.capture()) == before, "Destination scenery cannot mutate pilot")
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_map()
	app.select_destination(chosen[0])
	check(app.menu_scene.get_script() == Scene, "Main selects original destination scene owner")
	app.menu_scene.set_process(false)
	app.menu_scene.advance(1)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").path_join("destination-scene-orbital.png"))
	var previous = app.menu_scene
	app.close_destination()
	check(not previous.visible and app.menu_scene.get_script() == preload("res://src/presentation/menu_scene.gd"), "Back disposes destination scenery and restores dock map background")
	app.select_destination(chosen[1])
	app.menu_scene.set_process(false)
	app.menu_scene.advance(1)
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		if not OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").is_empty():
			root.get_texture().get_image().save_png(OS.get_environment("GOF_DESTINATION_CAPTURE_DIR").path_join("destination-scene-planet.png"))
	app.queue_free()
	await process_frame


func check_map_menu(source: PackedByteArray, lib) -> void:
	var previous_scale_mode := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var Chart = preload("res://src/presentation/galaxy_map.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var layout := reader.map_layout()
	check(Chart.valid_layout(layout), "Original map layout: " + reader.error)
	if layout.is_empty():
		root.content_scale_mode = previous_scale_mode
		return
	check(layout.board == [33,52,414,216] and layout.galaxy_origin == [24,35], "Map uses source chart bounds and unscaled background origin")
	check(layout.distance_suffix == "Lm" and lib.text(layout.position_label) == "Your position", "Map annotations use supplied units and localization")
	for address in [0x4c674,0x4c4ec,0x4a758]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0)
		var other := NativeData.new()
		other.bytes = changed
		other.parse_macho()
		check(other.map_layout().is_empty(), "Reject unsupported map layout binding %x" % address)
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x4c672,2),0x2322)
	var other := NativeData.new()
	other.bytes = changed
	other.parse_macho()
	check(other.map_layout().get("board",[])[0] == 34, "Chart origin follows supplied constant")
	var invalid := layout.duplicate(true)
	invalid.board[2] = 0
	check(not Chart.valid_layout(invalid), "Reject empty chart bounds")
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib,true)
	var before := JSON.stringify(app.session.capture())
	app.show_map()
	await process_frame
	var panel = app.map_panel
	var chart = panel.chart
	check(not app.page.visible and not app.top.visible and not app.status.visible and panel.visible, "Original full-screen map replaces placeholder tabs and status bars")
	check(chart.BOARD == Rect2(33,52,414,216) and chart.embedded, "Chart adopts imported bounds inside shared responsive canvas")
	check(chart.art.galaxy.get_size() == Vector2(450,260) and chart.art.selection.get_size() == Vector2(90,90), "Original background and selection artwork remain unmodified")
	check(chart.selected_caption(chart.entries()[chart.selected]).contains(lib.text(lib.content.map_ui.labels.quadrant)), "Selected quadrant includes its localized category")
	await capture_map_menu("galaxy-map-native.png")
	await map_menu_touch(panel.search_button.get_global_rect().get_center())
	check(panel.search_panel.visible and not chart.has_focus(), "Touch Search opens native drawer without leaking to chart")
	panel.search_field.text = lib.station_name(app.session.station_id)
	panel.filter_stations(panel.search_field.text)
	check(panel.search_ids.has(app.session.station_id), "Search resolves supplied station names")
	await capture_map_menu("galaxy-map-search.png")
	await map_menu_joy(JOY_BUTTON_B)
	check(not panel.search_panel.visible and chart.level == 0 and chart.has_focus(), "Controller Back closes search before leaving map")
	await map_menu_joy(JOY_BUTTON_A)
	check(chart.level == 1, "Controller confirms quadrant on original canvas")
	await map_menu_joy(JOY_BUTTON_A)
	check(chart.level == 2, "Controller confirms system on original canvas")
	await capture_map_menu("galaxy-map-system.png")
	var target: int = chart.entries()[chart.selected]
	var point: Vector2 = chart.get_global_transform() * (chart.origin() + chart.entry_point(target) * chart.scale_factor())
	await map_menu_touch(point)
	check(is_instance_valid(app.destination_panel) and not panel.visible, "Touch destination hides map input while Info is open")
	if is_instance_valid(app.destination_panel):
		await map_menu_joy(JOY_BUTTON_B)
		check(app.destination_panel == null and panel.visible and chart.level == 2 and chart.has_focus(), "Info Back restores chart selection and focus")
	panel.set_search(true)
	panel.select_result(panel.search_ids.find(app.session.station_id))
	check(is_instance_valid(app.destination_panel) and app.destination_panel.destination == app.session.station_id, "Search result opens exact supplied destination")
	app.close_destination()
	check(panel.search_panel.visible and panel.search_results.has_focus(), "Info Back restores search query and result focus")
	check(JSON.stringify(app.session.capture()) == before and app.saves == 0, "Map navigation and searching never mutate pilot or save")
	panel.set_search(false)
	await map_menu_touch(panel.actions[0].get_global_rect().get_center())
	check(chart.level == 1, "Original footer Back leaves system")
	app.show_dock()
	check(app.map_panel == null and not panel.visible, "Leaving map retires its input immediately")
	await process_frame
	check(not is_instance_valid(panel), "Map and search controls are released together")
	app.queue_free()
	await process_frame
	root.content_scale_mode = previous_scale_mode


func capture_map_menu(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("GOF_MAP_CAPTURE_DIR")
	if not directory.is_empty():
		root.get_texture().get_image().save_png(directory.path_join(filename))


func map_menu_touch(point: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.index = 0
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func map_menu_joy(button: int) -> void:
	for down in [true,false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = down
		Input.parse_input_event(event)
		await process_frame


func check_map_search_input(lib) -> void:
	var previous_scale_mode := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib,true)
	app.show_map()
	await process_frame
	var panel = app.map_panel
	await map_menu_joy(JOY_BUTTON_X)
	check(panel.search_panel.visible and panel.search_field.has_focus(), "Controller can reach Search directly from focused map")
	panel.search_field.text = lib.station_name(app.session.station_id)
	panel.filter_stations(panel.search_field.text)
	await process_frame
	var rect: Rect2 = panel.search_results.get_item_rect(0)
	await map_menu_touch(panel.search_results.get_global_transform() * rect.get_center())
	check(is_instance_valid(app.destination_panel) and app.destination_panel.destination == app.session.station_id, "Touch search result opens supplied destination")
	app.close_destination()
	await map_menu_joy(JOY_BUTTON_X)
	check(not panel.search_panel.visible and panel.chart.has_focus(), "Controller closes search and returns to chart")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	check(panel.search_panel.visible and panel.search_field.has_focus(), "Keyboard search shortcut restores editable query")
	app.queue_free()
	await process_frame
	root.content_scale_mode = previous_scale_mode


func check_opening_scene(source: PackedByteArray, lib) -> void:
	var Shots = preload("res://src/presentation/opening_choreography.gd")
	var Scene = preload("res://src/presentation/opening_scene.gd")
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var data := reader.opening_scene_presentation()
	check(Shots.valid_data(data),"Opening shot declarations: "+reader.error)
	if data.is_empty(): return
	check([data.station_page,data.ship_page,data.departure_page,data.hangar_page] == [2,3,6,9],"Source pages select station pan, ship approach, departure and hangar")
	check(data.actor == 2 and data.initial_ship_z == 40000 and data.initial_station_z == 30000,"Source opening actor and initial placements")
	check(is_equal_approx(data.ease_seconds,32.768) and is_equal_approx(data.fade_seconds,1.02),"Source cinematic timing units")
	for address in [0x3ca80,0x141a6,0x13ed0,0x1359e]:
		var changed := source.duplicate()
		changed.encode_u16(reader.file_offset(address,2),0)
		var altered := NativeData.new()
		altered.bytes = changed
		altered.parse_macho()
		check(altered.opening_scene_presentation().is_empty(),"Reject unsupported opening binding %x" % address)
	var invalid := data.duplicate(true)
	invalid.stop_z = invalid.slow_start
	check(not Shots.valid_data(invalid),"Reject invalid cinematic braking range")
	var changed := source.duplicate()
	changed.encode_u16(reader.file_offset(0x33d62,2),0x2301)
	var altered := NativeData.new()
	altered.bytes = changed
	altered.parse_macho()
	check(altered.opening_scene_presentation().get("actor") == 1,"Opening actor follows supplied declaration")
	var clock = Shots.new()
	clock.configure(data)
	clock.advance(2)
	check(clock.page == 0 and clock.stage == "pan" and clock.alpha == 0,"Opening fade ends without advancing dialogue")
	clock.present(data.station_page)
	check(clock.fade_direction == 1 and clock.stage == "pan","Early page advance fades unfinished pan")
	clock.advance(data.fade_seconds*2+.25)
	check(clock.stage == "station" and clock.alpha == 0,"Fade switches to next shot and returns to manual text")
	clock.present(data.ship_page)
	clock.advance(15)
	check(clock.stage == "ship" and clock.ship_z > data.slow_start and clock.ship_z < data.stop_z,"Source approach enters braking region")
	var age: float = clock.shot_elapsed
	clock.present(1)
	check(clock.stage == "ship" and clock.shot_elapsed == age and clock.page == data.ship_page,"Reading earlier text does not rewind cinematic")
	var second = Shots.new()
	second.configure(data,data.ship_page)
	for frame in 900: second.advance(1.0/60.0)
	check(absf(second.ship_z-clock.ship_z) < .001,"Analytic approach and braking are redraw independent")
	clock.present(data.departure_page)
	clock.advance(data.fade_seconds*2)
	var frozen: Vector3 = clock.pose().camera
	var direction: Vector3 = clock.pose().direction
	clock.advance(10)
	check(clock.pose().camera == frozen and clock.pose().direction == direction,"Departure freezes source camera snapshot")
	clock.present(data.hangar_page)
	clock.advance(data.fade_seconds*2)
	check(clock.stage == "hangar" and clock.alpha == 0,"Source hangar page completes scenic transition")
	var elapsed: float = clock.elapsed
	for delta in [0.0,-1.0,INF,NAN]: clock.advance(delta)
	check(clock.elapsed == elapsed,"Invalid cosmetic deltas do not advance scene")
	var pilot := Session.new()
	pilot.configure(lib)
	var stock: Array = pilot.market_offers().duplicate(true)
	var before := JSON.stringify(pilot.capture())
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_briefing()
	var scene = app.briefing_scene
	check(scene != null and scene.get_script() == Scene and scene.supported,"Main opening briefing uses supplied scene")
	if scene == null:
		app.queue_free()
		return
	scene.set_process(false)
	check(scene.area.field.get_child_count() == lib.content.briefing_scene.field.count,"Opening contains source asteroid field")
	check(app.briefing_panel.scene_fade == 1,"Initial source fade is presented over scene")
	app.briefing_panel.activate(1)
	check(pilot.briefing_page == 0,"Fade blocks Next confirmation")
	scene.advance(20)
	check(pilot.briefing_page == 0 and app.briefing_panel.scene_fade == 0,"Cosmetic camera does not auto-dismiss briefing")
	await capture_opening_scene("opening-pan.png")
	app.next_briefing()
	app.next_briefing()
	scene.advance(data.fade_seconds*2+10)
	check(scene.choreography.stage == "station","Native page ownership triggers station shot")
	await capture_opening_scene("opening-station.png")
	app.next_briefing()
	scene.advance(8)
	check(scene.ship.visible and scene.ship.position.distance_to(Session.Mission.point([0,0,12800])) < .001,"Opening ship moves using source approach units")
	await capture_opening_scene("opening-ship.png")
	for page in range(data.ship_page+1,data.departure_page+1): app.next_briefing()
	scene.advance(data.fade_seconds*2)
	await capture_opening_scene("opening-departure.png")
	for page in range(data.departure_page+1,data.hangar_page+1): app.next_briefing()
	scene.advance(data.fade_seconds*2+6)
	check(scene.hangar != null and scene.outdoor == null and not scene.flare_layer.visible,"Hangar transition retires exterior and lens flare")
	check(scene.hangar.player_ship == pilot.ship_id and scene.hangar.inventory == opening_stock(stock),"Opening hangar uses actual pilot and supplied stock")
	await capture_opening_scene("opening-hangar.png")
	app.back_briefing()
	check(scene.choreography.stage == "hangar" and pilot.briefing_page == data.hangar_page-1,"Back rereads text without rewinding hangar")
	var settled := JSON.stringify(pilot.capture())
	scene.advance(100)
	check(JSON.stringify(pilot.capture()) == settled,"Opening visuals do not mutate mission, pilot or inventory")
	scene.hide()
	elapsed = scene.choreography.elapsed
	scene.advance(10)
	check(scene.choreography.elapsed == elapsed,"Hidden opening stops visual clock")
	app.show_dock()
	check(app.briefing_scene == null and not scene.visible,"Leaving briefing retires opening scene immediately")
	await process_frame
	check(not is_instance_valid(scene),"Opening scene, indoor meshes and flare are disposed")
	app.queue_free()
	await process_frame


func capture_opening_scene(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("GOF_OPENING_CAPTURE_DIR")
	if not directory.is_empty(): root.get_texture().get_image().save_png(directory.path_join(filename))


func opening_stock(offers: Array) -> Array:
	var result := []
	for offer in offers:
		if offer.kind == "ship":
			for index in int(offer.count): result.append(int(offer.id))
	return result


func check_opening_resume_input(lib) -> void:
	var Scene = preload("res://src/presentation/opening_scene.gd")
	var pilot := Session.new()
	pilot.configure(lib)
	var offers: Array = pilot.market_offers().duplicate(true)
	var snapshot := JSON.stringify(pilot.capture())
	var resumed = Scene.new()
	root.add_child(resumed)
	resumed.set_process(false)
	var page := int(lib.content.briefing_scene.opening.hangar_page)
	check(resumed.configure(lib,0,pilot.station_id,pilot.ship_id,offers,page),"Configure opening directly at saved hangar page")
	check(resumed.outdoor == null and resumed.hangar != null,"Resumed hangar does not replay exterior or build unused scenery")
	check(resumed.hangar.player_ship == pilot.ship_id and resumed.hangar.inventory == opening_stock(offers),"Opening hangar displays only available supplied stock, respecting quantities")
	resumed.advance(8)
	check(JSON.stringify(pilot.capture()) == snapshot,"Resumed cinematic preserves exact pilot state")
	resumed.queue_free()
	await process_frame
	var app := DestinationMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_briefing()
	app.briefing_scene.set_process(false)
	await process_frame
	var down := InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_A
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	app.briefing_scene.advance(2)
	var up := InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_A
	up.pressed = false
	Input.parse_input_event(up)
	await process_frame
	check(pilot.briefing_page == 0,"Controller held during fade cannot acknowledge newly shown text on release")
	await map_menu_joy(JOY_BUTTON_A)
	check(pilot.briefing_page == 1,"Fresh controller confirmation advances exactly one page after fade")
	app.queue_free()
	await process_frame


class BriefingAudioMain extends DestinationMain:
	var selected_music := ""
	var launches := 0
	func play_music(track: String) -> void:
		selected_music = track
	func launch(_resume: bool = false) -> void:
		launches += 1
		clear_page()


func check_briefing_audio(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source
	reader.parse_macho()
	var declaration := reader.briefing_audio()
	check(reader.error.is_empty() and same_saved_value(declaration, lib.content.briefing_ui.audio),
		"Briefing audio is freshly recovered from supplied declarations")
	check(declaration.get("voice_text_offset") == 146 and declaration.get("next") == 13
		and declaration.get("back") == 27 and declaration.get("confirm") == 13,
		"Reference IPA briefing voice offset and navigation IDs")
	check(declaration.music == {"title":4,"station":5,"alien":0,"alien_race":1},
		"Source title and station music selection")
	var silent := 0
	for chapter in lib.content.chapters.size():
		for page in lib.content.chapters[chapter].dialogue.size():
			var cue: Dictionary = lib.briefing_cue(chapter,page)
			if not lib.content.sound_bank.has(str(cue.sound)): silent += 1
	check(silent == lib.content.tables.dialogue_ids.size(),
		"All reference briefing speech IDs are unregistered; no invented voice files")
	var voice_address := reader.symbol_address("__ZN16BriefingDialogue10getSoundIDEv")
	reader.bytes = source.duplicate()
	reader.bytes[reader.file_offset(voice_address + 0x13, 1)] = 0
	check(reader.briefing_audio().is_empty() and not reader.error.is_empty(),
		"Unsupported voice conversion is rejected by importer")
	var audio = preload("res://src/presentation/briefing_audio.gd").new()
	audio.library = lib
	root.add_child(audio)
	audio.present(0,0)
	check(audio.voice.stream == null and not audio.voice.playing,
		"Unregistered briefing speech stays silent")
	audio.action("back")
	check(audio.effect.playing and audio.effect.stream == lib.sound_clip(int(declaration.back))
		and is_equal_approx(audio.effect.volume_linear,.3),"Back uses supplied effect and gain")
	# An explicit fixture registers real supplied sound at a speech ID to exercise
	# ownership for compatible archives that supply speech. It is never imported.
	var speech_id := str(lib.briefing_cue(0,1).sound)
	var next_id := str(lib.briefing_cue(0,2).sound)
	lib.content.sound_bank[speech_id] = lib.content.sound_bank[str(int(declaration.back))].duplicate(true)
	lib.content.sound_bank[next_id] = lib.content.sound_bank[str(int(declaration.next))].duplicate(true)
	audio.present(0,1)
	check(audio.voice.playing,"Registered page sound starts on page entry")
	audio.voice.seek(.05)
	var position: float = audio.voice.get_playback_position()
	audio.present(0,1)
	check(audio.voice.get_playback_position() >= position,"Redrawing a page does not restart speech")
	var previous: AudioStream = audio.voice.stream
	audio.present(0,2)
	check(audio.voice.playing and audio.voice.stream != previous,"Next replaces previous page speech")
	audio.notification(NOTIFICATION_APPLICATION_PAUSED)
	check(audio.voice.stream_paused and not audio.effect.playing,"Application suspension pauses speech and stops transient cue")
	audio.notification(NOTIFICATION_APPLICATION_RESUMED)
	check(not audio.voice.stream_paused,"Application resume continues owned speech")
	audio.present(0,0)
	check(audio.voice.stream == null and not audio.voice.playing,"Returning to silent page stops old speech")
	audio.queue_free()
	await process_frame
	var pilot := Session.new()
	pilot.configure(lib)
	var app := BriefingAudioMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_briefing()
	app.briefing_scene.set_process(false)
	check(app.selected_music == "GalaxyOnFire1_Theme","Opening restores title music context")
	app.next_briefing()
	check(app.briefing_audio.voice.playing and app.briefing_audio.current_page == Vector2i(0,1)
		and pilot.briefing_page == 1,"Main Next owns sound for exactly the new page")
	app.back_briefing()
	check(not app.briefing_audio.voice.playing and pilot.briefing_page == 0,"Main Back stops departed page speech")
	app.next_briefing()
	app.request_skip_briefing()
	check(app.briefing_audio.current_page == Vector2i(0,1) and pilot.briefing_page == 1,
		"Skip question does not advance or replace page speech")
	app.confirmation.hide()
	app.skip_briefing()
	check(app.launches == 1 and app.briefing_audio.voice.stream == null
		and app.briefing_audio.effect.playing,"Confirmed Start retires speech while navigation cue may finish")
	app.queue_free()
	await process_frame
	lib.content.sound_bank.erase(speech_id)
	lib.content.sound_bank.erase(next_id)
	lib.sound_cache.erase(int(speech_id))
	lib.sound_cache.erase(int(next_id))


func check_briefing_music_context(lib) -> void:
	var app := BriefingAudioMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.setup_menu_input()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib)
	app.play_menu_music(true)
	check(app.selected_music == "GalaxyOnFire1_Theme", "Title context resolves source music path")
	var race := int(lib.content.briefing_ui.audio.music.alien_race)
	for alien in [false,true]:
		for station in lib.stations.size():
			if (lib.station_definition(station).race == race) == alien:
				app.session.station_id = station
				break
		app.play_menu_music(false)
		check(app.selected_music == ("GalaxyOnFire1_Alien" if alien else "GalaxyOnFire1_Station"),
			"Station and resumed briefing use source race music: " + str(alien))
	var audio: Dictionary = lib.content.briefing_ui.audio
	var original := int(audio.next)
	audio.next = -1
	check(not lib.valid_briefing_ui(),"Reject missing mandatory briefing effect binding")
	audio.next = original
	var original_music := int(audio.music.title)
	audio.music.title = original
	check(not lib.valid_briefing_ui(),"Reject nonmusic clip as briefing background")
	audio.music.title = original_music
	check(lib.valid_briefing_ui(),"Restored briefing audio declarations validate")
	app.queue_free()
	await process_frame


func damage_actor_fixture(definition: Dictionary, state: Dictionary, index: int, lib) -> void:
	# Objective fixtures explicitly activate their selected target, then use the
	# same damage path as combat. Never fake death by overwriting HP alone.
	state.actors[index].awake = true
	check(Session.Mission.damage(definition,state,index,float(state.actors[index].hp)),
		"Objective fixture applies damage through native actor lifecycle")


func finish_wrecks_fixture(definition: Dictionary, state: Dictionary, lib) -> void:
	var duration := 0.0
	for actor in state.actors:
		if actor.get("destruction",{}).get("phase") == "dying":
			var effect := Session.Mission.Destruction.effect(lib,int(definition.groups[int(actor.group)].actor))
			duration = maxf(duration,Session.Mission.Destruction.span(effect)/1000.0)
	if duration > 0:
		Session.Mission.advance(definition,state,duration+.001,lib)


class HangarHintMain extends "res://src/main.gd":
	var history_path := ""
	func _ready() -> void:
		pass
	func _process(_seconds: float) -> void:
		pass
	func hangar_hint_path() -> String:
		return history_path


func check_hangar_hints(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	var hints := reader.hangar_hint_presentation()
	check(same_saved_value(hints, lib.content.hangar_ui.hints), "Installed Hangar hint bindings match supplied source")
	check(hints.messages == {"intro": 531, "ship": 532, "cargo": 533, "shop": 534} and hints.sound == 13, "Source introduction and tab hints use supplied text and sound")
	reader.bytes.encode_u16(reader.file_offset(0x4624c, 2), 0x2186)
	check(reader.hangar_hint_presentation().messages.ship == 536, "Changed source hint label is recovered")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x47e46, 2), 0x2102)
	reader.error = ""
	check(reader.hangar_hint_presentation().is_empty(), "Reject changed hint-to-tab consumer")
	var original: Variant = lib.content.hangar_ui.hints.messages.ship
	lib.content.hangar_ui.hints.messages.ship = lib.strings.size()
	check(not lib.valid_hangar_ui(), "Reject hint text outside supplied localization")
	lib.content.hangar_ui.hints.messages.ship = original
	check(lib.valid_hangar_ui(), "Valid hint localization restored")

	var pilot := Session.new()
	pilot.configure(lib)
	var app := HangarHintMain.new()
	app.history_path = "user://hangar-hints-test-%d.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = pilot
	app.show_market()
	# Opening the market lazily samples this visit's stock; hints must preserve
	# the initialized market as well as the pilot's mission and inventory.
	var saved := pilot.capture()
	var panel = app.hangar_panel
	check(panel.hint_role == "intro" and panel.overlay.message == lib.text(int(hints.messages.intro)) and not panel.canvas.visible, "First Hangar visit displays original modal introduction")
	var selected: int = panel.selected
	panel.handle_action("primary")
	panel.handle_action("tab:shop")
	panel.select_entry(selected + 1)
	panel._process(120)
	check(panel.hint_role == "intro" and panel.section == "ship" and panel.selected == selected and same_saved_value(pilot.capture(), saved), "Unacknowledged hint blocks transactions and selection and never times out")
	var first = panel.overlay
	first.confirm_event(true)
	check(panel.hint_role == "intro", "Hint confirmation waits for release")
	first.confirm_event(false)
	check(panel.hint_role == "ship" and panel.overlay.message == lib.text(int(hints.messages.ship)) and app.hangar_hint_history() == ["intro"], "Acknowledged introduction chains to current tab and records only read hint")
	panel.overlay.confirm_event(false)
	check(panel.hint_role == "ship", "Held confirmation release cannot skip the next hint")
	app.navigate_back()
	check(panel.overlay == null and panel.canvas.visible and app.screen == "market", "Back acknowledges a hint without leaving Hangar")
	panel.open_tab("cargo")
	check(panel.hint_role == "cargo" and panel.overlay.message == lib.text(int(hints.messages.cargo)), "First Cargo visit displays supplied trade explanation")
	app.navigate_back()
	panel.open_tab("shop")
	check(panel.hint_role == "shop" and panel.overlay.message == lib.text(int(hints.messages.shop)), "First Shop visit displays supplied equipment explanation")
	app.navigate_back()
	var before: Array = app.hangar_hint_history()
	app.show_market()
	check(app.hangar_panel.overlay == null and before == ["intro", "ship", "cargo", "shop"], "Returning to Hangar does not replay acknowledged hints")
	check(same_saved_value(pilot.capture(), saved), "Hint acknowledgements do not change pilot progress or inventory")
	var fresh := HangarHintMain.new()
	root.add_child(fresh)
	fresh.setup_world()
	fresh.setup_ui()
	fresh.add_child(fresh.music)
	fresh.history_path = app.history_path
	fresh.library = lib
	check(fresh.hangar_hint_history() == before, "Fresh controller reads persisted hint acknowledgements")
	var original_id: String = lib.id
	lib.id = original_id + "-different"
	check(fresh.hangar_hint_history().is_empty(), "Different content identity has its own first-use guidance")
	lib.id = original_id
	var config := ConfigFile.new()
	config.set_value(lib.id, "acknowledged", ["intro", 999, "invalid"])
	config.save(app.history_path)
	check(fresh.hangar_hint_history() == ["intro"], "Malformed preference entries cannot invent read hints")
	fresh.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.history_path))
	app.queue_free()
	await process_frame
	await create_timer(.15).timeout


class PauseMain extends MenuSceneMain:
	var test_save := ""
	func save_path(_slot: String) -> String:
		return test_save


func check_pause_menu(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	check(same_saved_value(reader.pause_presentation(), lib.content.pause_ui), "Pause presentation matches supplied declarations")
	check(same_saved_value(lib.content.pause_ui.labels, {"resume": 20, "options": 3, "help": 4, "menu": 573}) and lib.content.pause_ui.rows == 4, "Original pause labels and four source actions are imported")
	reader.bytes.encode_u16(reader.file_offset(0x41b9c, 2), 0x2115)
	check(reader.pause_presentation().labels.resume == 21, "Supplied pause label changes propagate")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x45f70, 2), 0xd001)
	check(reader.pause_presentation().is_empty(), "Unsupported resume action consumer is rejected")
	var caption: Variant = lib.content.pause_ui.labels.resume
	lib.content.pause_ui.labels.resume = lib.strings.size()
	check(not lib.valid_pause_ui(), "Missing pause localization is rejected")
	lib.content.pause_ui.labels.resume = caption
	check(lib.valid_pause_ui(), "Pause validation recovers with supplied labels")
	var app := PauseMain.new()
	app.test_save = "user://pause-test-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib, true)
	check(app.session.depart(), "Create temporary flight for pause presentation")
	app.launch(true)
	app.flight.set_physics_process(false)
	var captured: Dictionary = app.session.capture()
	app.show_pause()
	var panel = app.pause_panel
	check(panel != null and app.flight.paused and not app.page.visible and panel.buttons.size() == 5, "Original pause artwork replaces generic controls without advancing flight")
	check(panel.buttons[0].text == lib.text(20) and root.gui_get_focus_owner() == panel.buttons[0] and not panel.footer.visible, "Continue Game is initially focused and campaign hides Survival action")
	panel.handle_action("help")
	check(panel.section == "help" and app.flight.paused, "Pause help stays within the paused original-art screen")
	app.navigate_back()
	check(panel.section == "pause" and root.gui_get_focus_owner() == panel.buttons[2], "Back from help restores its pause-menu focus")
	panel.handle_action("save")
	check(FileAccess.file_exists(app.test_save) and is_instance_valid(panel.overlay) and not panel.canvas.visible, "Save pilot writes a checkpoint and shows original acknowledged notice")
	var restored := Session.new()
	restored.configure(lib)
	check(restored.load_save(app.test_save) and same_saved_value(restored.capture(), captured), "Pause checkpoint restores unchanged pilot state")
	panel.handle_action("resume")
	check(app.screen == "pause", "Notice blocks underlying Continue Game action")
	app.navigate_back()
	check(app.screen == "pause" and panel.canvas.visible and not is_instance_valid(panel.overlay), "Back dismisses notice without unpausing")
	panel.handle_action("options")
	check(app.screen == "options" and app.flight.paused, "Pause opens original Options while keeping simulation paused")
	app.navigate_back()
	check(app.screen == "pause" and is_instance_valid(app.pause_panel), "Leaving Options restores the original pause menu")
	app.pause_panel.handle_action("menu")
	check(app.screen == "title" and app.flight == null and FileAccess.file_exists(app.test_save), "Main menu saves successfully before leaving flight")
	app.session = restored
	app.launch(true)
	app.flight.set_physics_process(false)
	app.show_pause()
	var saved_path := app.test_save
	app.test_save = saved_path.path_join("blocked.json")
	app.pause_panel.handle_action("menu")
	check(app.screen == "pause" and app.flight.paused and is_instance_valid(app.pause_panel.overlay), "Failed save keeps player in paused flight with an original-art error")
	app.test_save = saved_path
	app.navigate_back()
	app.navigate_back()
	check(app.screen == "flight" and not app.flight.paused, "Back at pause root resumes flight")
	app.flight.set_physics_process(false)
	app.transient_preview = true
	app.show_pause()
	check(app.pause_panel.buttons[3].disabled and not app.pause_panel.buttons[4].disabled, "Transient preview cannot save but can leave through Main menu")
	app.pause_panel.handle_action("menu")
	check(app.screen == "title", "Transient preview leaves pause without creating a pilot save")
	var arcade_panel = preload("res://src/presentation/pause_menu.gd").new()
	root.add_child(arcade_panel)
	arcade_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arcade_panel.setup(lib, "Controls", true, true)
	var actions: Array = []
	arcade_panel.selected.connect(func(action): actions.append(action))
	check(arcade_panel.footer.visible, "Survival exposes Abandon run beside original pause actions")
	arcade_panel.handle_action("abandon")
	check(actions.is_empty() and is_instance_valid(arcade_panel.overlay), "Survival abandonment requires confirmation")
	arcade_panel.back()
	check(actions.is_empty() and not is_instance_valid(arcade_panel.overlay), "Back cancels abandonment without emitting its action")
	arcade_panel.handle_action("abandon")
	arcade_panel.overlay.accept(0)
	check(actions == ["abandon"], "Confirmed abandonment emits exactly one owner action")
	arcade_panel.queue_free()
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path + suffix))


class OptionsMain extends MenuSceneMain:
	var preference_path := ""
	func settings_path() -> String:
		return preference_path


func check_options_menu(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	var data := reader.options_presentation()
	check(same_saved_value(data, lib.content.options_ui), "Options presentation matches imported source")
	check(data.labels == {"controls": 21, "audio": 577, "display": 659, "music": 564, "effects": 565, "invert": 10} and data.volume_max == 100, "Options uses original category, audio and control labels")
	reader.bytes.encode_u16(reader.file_offset(0x409ec, 2), 0x2116)
	check(reader.options_presentation().labels.controls == 22, "Changed supplied option text propagates")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x41e7e, 2), 0x6fe2)
	reader.error = ""
	check(reader.options_presentation().is_empty(), "Changed checkmark consumer is rejected")
	var original: Variant = lib.content.options_ui.images.grabber.region
	lib.content.options_ui.images.grabber.region = 999999
	check(not lib.valid_options_ui(), "Missing option slider artwork is rejected")
	lib.content.options_ui.images.grabber.region = original
	check(lib.valid_options_ui(), "Options validation recovers with supplied artwork")

	var Audio = preload("res://src/presentation/audio_settings.gd")
	var app := OptionsMain.new()
	app.preference_path = "user://options-test-%d.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.show_options()
	check(app.options_panel == null and app.page.visible, "Before import, options remain usable with native controls")
	app.settings.music = false
	app.settings.music_volume = 0.0
	app.show_options()
	var music_toggle: CheckButton = app.page.find_children("*", "CheckButton", true, false)[0]
	music_toggle.button_pressed = true
	check(app.settings.music and app.settings.music_volume > 0, "Pre-import music toggle restores audible gain after zero volume")
	app.close_options()
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib)
	app.show_options()
	var panel = app.options_panel
	check(root.gui_get_focus_owner() == panel.buttons[0], "Options initially focuses its first category rather than Back")
	check(panel != null and not app.page.visible and panel.entries.map(func(row): return row.action) == ["controls", "audio", "display"], "Installed content replaces generic Options with original menu categories")
	panel.handle_action("audio")
	check(panel.sliders.size() == 2 and panel.buttons.all(func(button): return button.focus_mode == Control.FOCUS_NONE), "Audio rows expose keyboard-focusable sliders without duplicate buttons")
	panel.sliders.music_volume.value = 35
	panel.sliders.effects_volume.value = 0
	var music_bus := AudioServer.get_bus_index(Audio.MUSIC)
	var effects_bus := AudioServer.get_bus_index(Audio.EFFECTS)
	check(app.settings.music and is_equal_approx(app.settings.music_volume, .35) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(music_bus)), .35), "Music slider applies independent gain immediately")
	check(AudioServer.is_bus_mute(effects_bus) and not AudioServer.is_bus_mute(music_bus), "Muting sound effects does not mute music")
	panel.sliders.effects_volume.value = 70
	panel.sliders.music_volume.value = 0
	check(not app.settings.music and AudioServer.is_bus_mute(music_bus) and not AudioServer.is_bus_mute(effects_bus), "Muting music leaves effects audible")
	check(app.music.bus == Audio.MUSIC and app.briefing_audio.effect.bus == Audio.EFFECTS and app.briefing_audio.voice.bus == Audio.EFFECTS, "Music, navigation and speech players route to their respective mix buses")
	panel.sliders.music_volume.value = 50
	app.show_options()
	check(app.options_panel.section == "audio" and is_equal_approx(app.options_panel.sliders.music_volume.value, 50), "Rebuilding options retains subpage and volume")
	app.navigate_back()
	check(app.screen == "options" and app.options_panel.section == "options", "Back first returns from audio to option categories")
	app.options_panel.handle_action("controls")
	app.options_panel.handle_action("invert")
	app.options_panel.handle_action("linked_fire")
	app.options_panel.sliders.sensitivity.value = .004
	check(app.settings.invert and app.settings.linked_fire and is_equal_approx(app.settings.sensitivity, .004), "Original control row and native extensions update real settings")
	for index in range(1, app.options_panel.buttons.size()):
		check(app.options_panel.buttons[index - 1].get_rect().end.y <= app.options_panel.buttons[index].position.y, "Original option widgets leave room for the taller slider")
	app.options_panel.handle_action("help")
	app.navigate_back()
	check(app.options_panel.section == "controls", "Control help returns to Controls")
	app.navigate_back()
	app.options_panel.handle_action("display")
	var previous: bool = app.options_panel.values.targeting_reticle
	app.options_panel.handle_action("targeting_reticle")
	app.options_panel.handle_action("touch")
	check(app.settings.targeting_reticle == not previous and app.settings.touch, "Display settings preserve native targeting and touch visibility controls")
	var restored := OptionsMain.new()
	root.add_child(restored)
	restored.setup_world()
	restored.setup_ui()
	restored.add_child(restored.music)
	restored.preference_path = app.preference_path
	restored.load_settings()
	check(restored.settings == app.settings, "New and existing settings survive a fresh controller")
	var before := app.settings.duplicate(true)
	app.change_option("credits", 999999)
	app.change_option("effects_volume", NAN)
	check(app.settings == before, "Unexpected option keys and nonfinite values are ignored")

	app.close_options()
	app.session.skip_campaign()
	app.show_dock()
	app.show_options()
	app.show_options()
	app.navigate_back()
	check(app.screen == "dock", "Station options retain return destination after rebuilding")
	check(app.session.depart(), "Transient flight is available for paused option navigation")
	app.transient_preview = true
	app.launch_preview()
	app.flight.set_physics_process(false)
	app.show_pause()
	var saved: Dictionary = app.session.capture()
	app.show_options()
	app.options_panel.handle_action("display")
	app.options_panel.handle_action("touch")
	app.navigate_back()
	app.navigate_back()
	check(app.screen == "pause" and app.flight.paused and not app.flight.settings.touch, "Leaving flight options applies settings and retains pause")
	check(same_saved_value(app.session.capture(), saved), "Options leave campaign, inventory, projectiles and clocks unchanged")
	check(app.flight.audio.bus == Audio.EFFECTS and app.flight.player_hit.audio.bus == Audio.EFFECTS, "Flight weapon and damage audio use the effects bus")
	app.resume_flight()
	app.flight.set_physics_process(false)
	check(app.screen == "flight" and not app.hud.touch_enabled, "Resuming uses the changed touch display preference")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.preference_path))
	app.queue_free()
	restored.queue_free()
	await process_frame
	await create_timer(.2).timeout
	Audio.apply({})


func check_defeat_menu(source: PackedByteArray, lib) -> void:
	var reader := NativeData.new()
	reader.bytes = source.duplicate()
	reader.parse_macho()
	check(same_saved_value(reader.defeat_presentation(), lib.content.defeat_ui), "Defeat presentation comes from supplied consumers")
	check(same_saved_value(lib.content.defeat_ui.labels, {"lost": 398, "timeout": 403, "load": 620, "menu": 573, "missing": 621}), "Defeat imports source result and retry labels")
	reader.bytes.encode_u16(reader.file_offset(0x4464c, 2), 0x219c)
	check(reader.defeat_presentation().labels.load == 624, "Changed supplied retry caption propagates")
	reader.bytes = source.duplicate()
	reader.bytes.encode_u16(reader.file_offset(0x45fe8, 2), 0x6980)
	check(reader.defeat_presentation().is_empty(), "Unsupported original retry record association is rejected")
	var original: Variant = lib.content.defeat_ui.labels.load
	lib.content.defeat_ui.labels.load = lib.strings.size()
	check(not lib.valid_defeat_ui(), "Invalid defeat localization is rejected")
	lib.content.defeat_ui.labels.load = original
	check(lib.valid_defeat_ui(), "Restored defeat declarations validate")
	var app := PauseMain.new()
	app.test_save = "user://defeat-test-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.session = Session.new()
	app.session.configure(lib, true)
	var station: Dictionary = app.session.capture()
	check(app.session.depart(), "Start private retry flight")
	app.launch(true)
	app.flight.set_physics_process(false)
	var checkpoint: Dictionary = app.session.capture()
	var saved := FileAccess.get_file_as_bytes(app.test_save)
	app.session.credits += 750
	app.session.hull = 0
	app.defeat()
	await process_frame
	check(app.screen == "defeat" and app.flight.paused and not app.page.visible and not app.top.visible, "Defeat replaces preview controls with original modal over paused flight")
	check(app.defeat_panel.captions == [lib.text(620), lib.text(573)] and app.defeat_panel.message == lib.text(398), "Defeat presents original load/menu choices and ship-loss text")
	check(not app.defeat_panel.geometry.is_empty() and app.defeat_panel.buttons.size() == 2, "Defeat original artwork produces usable button geometry")
	check(app.save_game(false) and FileAccess.get_file_as_bytes(app.test_save) == saved, "Defeat autosave/quit preserves viable checkpoint bytes")
	app.defeat_panel.accept(0)
	app.flight.set_physics_process(false)
	check(app.screen == "flight" and same_saved_value(app.session.capture(), checkpoint), "Retry restores complete in-flight checkpoint and rolls back failed-flight credits")
	saved = FileAccess.get_file_as_bytes(app.test_save)
	app.session.active_job["failed"] = true
	app.defeat(true)
	check(app.defeat_panel.message == lib.text(398) + "\n" + lib.text(403), "Deadline defeat uses original result and time-limit message")
	check(app.save_game(false) and FileAccess.get_file_as_bytes(app.test_save) == saved, "Mission failure with surviving hull cannot overwrite checkpoint")
	app.navigate_back()
	check(app.screen == "title" and app.flight == null, "Back leaves defeat safely for main menu")
	check(app.save_game(false) and FileAccess.get_file_as_bytes(app.test_save) == saved, "Leaving defeat does not remove save protection")
	app.continue_game("free")
	app.flight.set_physics_process(false)
	check(app.screen == "flight" and same_saved_value(app.session.capture(), checkpoint), "Continue after defeat restores viable pilot")
	var restored := Session.new()
	restored.configure(lib)
	check(restored.restore(station) and restored.save(app.test_save), "Create original-style station checkpoint")
	app.session.hull = 0
	app.defeat()
	app.defeat_panel.accept(0)
	check(app.screen == "dock" and same_saved_value(app.session.capture(), station), "Station checkpoint retries at original saved station without rewards or inventory changes")
	check(app.session.depart(), "Start missing-save retry case")
	app.launch(true)
	app.flight.set_physics_process(false)
	app.session.hull = 0
	app.defeat()
	for suffix in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(app.test_save + suffix))
	app.defeat_panel.accept(0)
	check(app.screen == "defeat" and app.session.hull == 0 and app.defeat_panel.visible and app.defeat_panel.message == lib.text(621), "Missing checkpoint reports original message without fabricating a repaired pilot")
	check(restored.save(app.test_save), "Write valid backup candidate")
	var healthy := FileAccess.get_file_as_bytes(app.test_save)
	restored.hull = 0
	check(restored.save(app.test_save), "Reproduce legacy dead-save primary")
	var recovered := Session.new()
	recovered.configure(lib)
	check(recovered.load_retry(app.test_save) and same_saved_value(recovered.capture(), station), "Legacy defeated primary falls back to viable backup")
	check(FileAccess.get_file_as_bytes(app.test_save + ".bak") == healthy, "Retry reader leaves preserved backup untouched")
	app.defeat_panel.accept(0)
	check(app.screen == "title", "Missing-save acknowledgement returns to main menu")
	app.continue_game("free")
	check(app.screen == "dock" and app.session.hull > 0, "Continue also recovers a viable backup from a legacy dead save")
	app.launch()
	app.flight.set_physics_process(false)
	app.session.hull = 0
	app.defeat()
	app.transient_preview = true
	app.defeat_panel.accept(0)
	check(app.screen == "defeat" and app.session.hull == 0, "Transient scene preview cannot load a real pilot checkpoint")
	app.transient_preview = false
	app.defeat_panel.accept(0)
	check(app.screen == "title", "Original Main menu choice leaves defeat")
	app.session = Session.new()
	app.session.configure(lib)
	app.session.chapter = 3
	var escort: Dictionary = app.session.mission_definition()
	app.session.active_job = app.session.Mission.create(escort, 3, app.session.station_id, lib, 42)
	for index in app.session.active_job.actors.size():
		var actor: Dictionary = app.session.active_job.actors[index]
		if escort.groups[int(actor.group)].get("team") == "ally": app.session.damage_actor(index, 100000)
	finish_wrecks_fixture(escort, app.session.active_job, lib)
	check(app.mission_failure_text() == lib.text(398) + "\n" + escort.failure_prefix + lib.text(int(escort.failure_text)), "Lost escort uses original Game Over prefix and supplied objective failure text")
	var saved_path := app.test_save
	app.queue_free()
	await process_frame
	await create_timer(.2).timeout
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path + suffix))


func check_desktop_flight_view(lib) -> void:
	var app := PauseMain.new()
	app.test_save = "user://desktop-view-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.settings.touch = false
	app.start_game(true)
	check(is_instance_valid(app.menu_scene), "Skip campaign creates station scenery before undock")
	app.launch()
	app.flight.set_physics_process(false)
	check(root.get_camera_3d() == app.flight.camera, "Station cleanup cannot steal the exploration camera")
	check(not app.flight_buttons.pause.is_visible_in_tree(), "Hidden touch setting hides pause icon")
	check(app.hud.extra_buttons.values().all(func(control): return not control.is_visible_in_tree()), "Hidden touch setting hides Time, Autopilot and Dock")
	var start: Vector3 = app.flight.ship.position
	for step in 120:
		app.flight._physics_process(1.0 / 60.0)
	check(app.flight.ship.position.distance_to(start) > 1, "Exploration ship moves after skipping campaign")
	check(app.flight.camera.position.distance_to(app.flight.ship.position) < 150, "Exploration camera follows the ship")
	app.show_pause()
	app.resume_flight()
	app.flight.set_physics_process(false)
	check(root.get_camera_3d() == app.flight.camera, "Pause return retains flight camera")
	app.settings.touch = true
	app.show_flight_hud()
	check(app.flight_buttons.pause.is_visible_in_tree(), "Touch controls retain pause action")
	app.flight_buttons.pause.pressed.emit()
	check(app.screen == "pause", "Visible pause action opens menu")
	var path := app.test_save
	app.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	var font_adapter = preload("res://src/presentation/bitmap_font.gd")
	check(font_adapter.fitted_scale(Vector2(1920, 1080), Vector2(480, 320), false) == 1.6875, "Desktop UI is half the original scale")
	check(font_adapter.fitted_scale(Vector2(1920, 1080), Vector2(480, 320), true) == 3.375, "Mobile UI retains original scale")
	for value in [lib.text(int(lib.content.recovery.labels.recovered)), "Long localized message with WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"]:
		for line in font_adapter.wrap_lines(lib, value, 150):
			check(font_adapter.text_width(lib, line) <= 150, "Displayed font metrics keep wrapped text inside its panel")


class SlotTransitionMain:
	extends MenuSceneMain
	var directory: String

	func save_path(slot: String) -> String:
		return directory.path_join(slot + ".json")


func check_slot_transitions(lib) -> void:
	var app = SlotTransitionMain.new()
	app.directory = "user://slot-transition-tests/" + str(Time.get_ticks_usec()) + "/" + lib.id
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	var campaign = Session.new()
	campaign.configure(lib)
	var previous_free = Session.new()
	previous_free.configure(lib, true)
	previous_free.credits += 13
	check(
		campaign.save(app.save_path("campaign")) and previous_free.save(app.save_path("free")),
		"Prepare separate actual save slots"
	)
	var original_free = FileAccess.get_file_as_bytes(app.save_path("free"))
	campaign.credits -= 1
	app.session = campaign
	app.show_dock()
	var campaign_block = app.save_path("campaign") + ".tmp"
	DirAccess.make_dir_absolute(campaign_block)
	app.skip_current()
	check(
		app.session == campaign and campaign.campaign_state == "active",
		"Failed campaign save keeps the active campaign pilot"
	)
	check(
		FileAccess.get_file_as_bytes(app.save_path("free")) == original_free,
		"Failed campaign save cannot replace an existing exploration slot"
	)
	check(
		app.station_panel.section == "notice" and app.notification_text.contains("Could not write"),
		"Skip save failure remains visible"
	)
	DirAccess.remove_absolute(campaign_block)
	app.session = campaign
	previous_free.save(app.save_path("free"))
	var free_block = app.save_path("free") + ".tmp"
	DirAccess.make_dir_absolute(free_block)
	app.show_dock()
	app.skip_current()
	check(
		app.session == campaign and campaign.campaign_state == "active",
		"Failed exploration save leaves campaign active"
	)
	check(
		FileAccess.get_file_as_bytes(app.save_path("free")) == original_free,
		"Failed exploration save preserves previous exploration file"
	)
	check(app.station_panel.section == "notice", "Exploration creation failure remains visible")
	DirAccess.remove_absolute(free_block)
	app.session = campaign
	app.show_dock()
	app.skip_current()
	check(
		(
			app.session != campaign
			and app.session.slot == "free"
			and app.session.campaign_state == "skipped"
		),
		"Successful skip selects a distinct exploration pilot"
	)
	check(
		(
			app.session.credits == campaign.credits
			and app.session.earned_worth() == campaign.earned_worth()
		),
		"Skip grants no completion payout or earned worth"
	)
	var campaign_bytes = FileAccess.get_file_as_bytes(app.save_path("campaign"))
	var reload = Session.new()
	reload.configure(lib)
	check(
		(
			reload.load_save(app.save_path("campaign"))
			and same_saved_value(reload.capture(), campaign.capture())
		),
		"Original campaign saved with current progress before skipping"
	)
	var pilot = app.session
	reload = Session.new()
	reload.configure(lib, true)
	check(
		(
			reload.load_save(app.save_path("free"))
			and same_saved_value(reload.capture(), pilot.capture())
		),
		"Exploration pilot is durable before becoming active"
	)
	for fail_save in [false, true]:
		var target = -1
		for index in lib.stations.size():
			var fare = pilot.travel_quote(index)
			if index != pilot.station_id and fare.total > 0 and fare.total <= pilot.credits:
				target = index
				break
		check(target >= 0, "Affordable destination exists for transfer test")
		if target < 0:
			break
		var old_file = FileAccess.get_file_as_bytes(app.save_path("free"))
		var credits = pilot.credits
		var fare = pilot.travel_quote(target).total
		app.show_map()
		app.select_destination(target)
		if fail_save:
			DirAccess.make_dir_absolute(free_block)
		await app.travel_selected()
		check(
			pilot.station_id == target and pilot.credits == credits - fare,
			"Travel settles imported fare once"
		)
		if fail_save:
			check(
				(
					app.station_panel.section == "notice"
					and app.notification_text.contains("Could not write")
				),
				"Travel save error remains visible after destination panel is retired"
			)
			check(
				FileAccess.get_file_as_bytes(app.save_path("free")) == old_file,
				"Failed travel save preserves durable departure checkpoint"
			)
			DirAccess.remove_absolute(free_block)
			check(app.save_game(false), "Save can be retried after storage is available")
		reload = Session.new()
		reload.configure(lib, true)
		check(
			(
				reload.load_save(app.save_path("free"))
				and same_saved_value(reload.capture(), pilot.capture())
			),
			"Reload restores exact settled destination, credits, visits and progression"
		)
		check(
			FileAccess.get_file_as_bytes(app.save_path("campaign")) == campaign_bytes,
			"Exploration transfer never overwrites campaign save"
		)
	var directory = app.directory
	app.queue_free()
	await process_frame
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(directory.get_base_dir())


func check_checkpoint_visibility(lib) -> void:
	var app = SlotTransitionMain.new()
	app.directory = "user://checkpoint-visibility/" + str(Time.get_ticks_usec()) + "/" + lib.id
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	for skip in [false, true]:
		var prior = Session.new()
		prior.configure(lib, skip)
		prior.credits -= 1
		app.session = prior
		app.show_title()
		var path = app.save_path(prior.slot)
		check(prior.save(path), "Create checkpoint before new-pilot replacement")
		var before = FileAccess.get_file_as_bytes(path)
		DirAccess.make_dir_absolute(path + ".tmp")
		app.start_game(skip)
		check(app.session == prior, "Failed new pilot save preserves current pilot")
		check(
			FileAccess.get_file_as_bytes(path) == before,
			"Failed new pilot save preserves previous slot bytes"
		)
		check(
			app.screen == "title" and app.title_panel.section == "notice",
			"Failed new game explains failure on title screen"
		)
		DirAccess.remove_absolute(path + ".tmp")
	var pilot = Session.new()
	pilot.configure(lib, true)
	app.session = pilot
	var path = app.save_path("free")
	check(pilot.depart() and pilot.save(path), "Create departure checkpoint")
	DirAccess.make_dir_absolute(path + ".tmp")
	app.dock()
	check(
		pilot.docked and app.station_panel.section == "notice",
		"Docking preserves visible save failure"
	)
	DirAccess.remove_absolute(path + ".tmp")
	pilot = recovery_contract_fixture(lib)
	check(pilot != null, "Create imported recoverable contract")
	complete_recovery_fixture(pilot)
	app.session = pilot
	app.screen = "flight"
	check(
		pilot.ready_to_finish() and pilot.save(path),
		"Completed contract checkpoint awaits settlement"
	)
	var credits = pilot.credits
	var reward = pilot.mission_reward()
	DirAccess.make_dir_absolute(path + ".tmp")
	app.finish_mission()
	check(
		app.screen == "recovery" and not pilot.recovery.is_empty(),
		"Mission completion opens original recovery receipt"
	)
	check(
		app.status.is_visible_in_tree() and app.status.text.contains("Could not write"),
		"Mission save error remains visible on recovery screen"
	)
	check(
		pilot.credits == credits + reward and pilot.contract_rewards.size() == 1,
		"Settlement still awards exactly once"
	)
	app.acknowledge_recovery()
	check(
		app.screen == "dock" and app.station_panel.section == "notice",
		"Acknowledging loot keeps save failure visible at dock"
	)
	DirAccess.remove_absolute(path + ".tmp")
	check(app.save_game(false), "Settled mission can be saved after storage recovery")
	var restored = Session.new()
	restored.configure(lib, true)
	check(
		restored.load_save(path) and same_saved_value(restored.capture(), pilot.capture()),
		"Recovered checkpoint restores reward/cargo without duplication"
	)
	pilot = Session.new()
	pilot.configure(lib, true)
	app.session = pilot
	DirAccess.make_dir_absolute(path + ".tmp")
	app.launch()
	app.flight.set_physics_process(false)
	check(
		app.paused and app.flight.paused and is_instance_valid(app.pause_panel.overlay),
		"Launch save failure pauses with a visible reason"
	)
	app.stop_flight()
	DirAccess.remove_absolute(path + ".tmp")
	pilot = Session.new()
	pilot.configure(lib)
	app.session = pilot
	app.show_briefing()
	var campaign_path = app.save_path("campaign")
	DirAccess.make_dir_absolute(campaign_path + ".tmp")
	app.back_briefing()
	check(
		app.screen == "dock" and app.station_panel.section == "notice",
		"Returning from briefing keeps the failed checkpoint visible"
	)
	DirAccess.remove_absolute(campaign_path + ".tmp")
	var directory = app.directory
	app.queue_free()
	await process_frame
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(directory.get_base_dir())
