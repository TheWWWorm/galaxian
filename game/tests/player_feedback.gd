extends "res://tests/integration.gd"
## Focused checks with existing imported content and private save/settings paths.
class FeedbackMain extends "res://src/main.gd":
	func _ready(): pass
	func _process(_delta): pass
	func save_path(slot): return "user://feedback-check-" + slot + ".json"
	func settings_path(): return "user://feedback-settings.cfg"

func run():
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(2); return
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open existing supplied content")
	if failures: quit(1); return
	if args.size() > 1 and args[1] == "mobile":
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var zip := ZIPReader.new()
	zip.open(args[2])
	var source := zip.read_file("Payload/GalaxyOnFire.app/GalaxyOnFire")
	zip.close()
	check_player_motion(source, lib)
	await process_frame
	check_checkpoints(lib)
	await check_ui(lib, args[3] if args.size() > 3 else "")
	await check_defeat_menu(source, lib)
	await check_pause_menu(source, lib)
	await check_options_menu(source, lib)
	await process_frame
	print("PLAYER FEEDBACK ", checks, " CHECKS; ", failures, " FAILURES")
	call_deferred("finish_feedback")

func finish_feedback():
	for frame in 4: await process_frame
	quit(1 if failures else 0)

func check_checkpoints(lib):
	var path := "user://feedback-persistence.json"
	var pilot := Session.new()
	pilot.configure(lib)
	var station := pilot.capture()
	check(pilot.depart(), "Campaign departs")
	var departure := pilot.capture()
	pilot.hull = 1
	pilot.credits += 1000
	for index in 4: check(pilot.save(path), "Near-death autosave writes")
	var loaded := Session.new()
	loaded.configure(lib)
	check(loaded.load_save(path) and loaded.hull == 1, "Resume still offers precise latest autosave")
	var earlier = loaded.checkpoint_candidate("departure")
	check(earlier != null and same_saved_value(earlier.capture(), departure), "Repeated unsafe autosaves preserve complete mission start")
	earlier = loaded.checkpoint_candidate("station")
	check(earlier != null and same_saved_value(earlier.capture(), station), "Station restores original credits, hull and mission state")
	check(earlier.checkpoint_candidate("departure") == null, "Station rollback discards later flight")
	loaded.checkpoints.departure.slot = "free"
	check(loaded.checkpoint_candidate("departure") == null, "Checkpoint cannot cross pilot slot")
	loaded.checkpoints.station.content_id = "different"
	check(loaded.checkpoint_candidate("station") == null, "Checkpoint cannot cross content identity")
	loaded.checkpoints.station = station.duplicate(true)
	loaded.checkpoints.station.hull = 0
	check(loaded.checkpoint_candidate("station") == null, "Dead recovery snapshot is rejected")
	loaded.checkpoints.station = station.duplicate(true)
	loaded.checkpoints.station.combat = {}
	check(loaded.checkpoint_candidate("station") == null, "Malformed recovery state is rejected")
	pilot.configure(lib, true)
	var offers := pilot.contract_offers()
	check(not offers.is_empty() and pilot.begin_contract(0), "Contract departure records snapshots")
	check(pilot.checkpoint_candidate("departure") != null and pilot.checkpoint_candidate("station") != null, "Contract checkpoints restore and validate")
	pilot.configure(lib, true)
	pilot.depart()
	check(pilot.checkpoint_candidate("departure") != null, "Free flight has departure checkpoint")
	check(pilot.restore(station) and pilot.checkpoints.is_empty(), "Legacy simulation save loads without invented history")
	for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func check_ui(lib, captures: String):
	var app := FeedbackMain.new()
	root.add_child(app)
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true
	app.session = Session.new(); app.session.configure(lib, true)
	app.settings.touch = true
	app.settings.original_flight_controls = true
	app.launch()
	app.flight.set_physics_process(false)
	app.flight.ship.position = Vector3(2000, 0, 2000)
	# Exercise the real input paths, not just the shared rotation helper.
	for inverted in [false, true]:
		app.flight.settings.invert = inverted
		var sign_expected := 1.0 if inverted else -1.0
		for mode in ["touch", "controller", "keyboard", "mouse"]:
			app.flight.ship.basis = Basis.IDENTITY
			app.session.motion.turn = [0.0, 0.0]
			app.flight.controls.clear()
			if mode == "mouse":
				app.flight.settings.touch = false
				app.flight.mouse_flight_enabled = true
				app.flight.web_mouse_input = true
				var event := InputEventMouseMotion.new()
				event.relative = Vector2(0, 12)
				app.flight._unhandled_input(event)
				app.flight.step(.02)
			else:
				if mode == "touch": app.flight.controls.touch_look = Vector2(0, 1)
				if mode == "controller": app.flight.controls.axes[JOY_AXIS_RIGHT_Y] = 1.0
				if mode == "keyboard":
					var event := InputEventKey.new(); event.physical_keycode = KEY_UP; event.keycode = KEY_UP; event.pressed = true
					Input.parse_input_event(event)
					Input.flush_buffered_events()
				app.flight.step(.02)
				if mode == "keyboard":
					var event := InputEventKey.new(); event.physical_keycode = KEY_UP; event.keycode = KEY_UP; event.pressed = false
					Input.parse_input_event(event)
					Input.flush_buffered_events()
			check(signf((-app.flight.ship.basis.z).y) == (-1.0 if mode == "keyboard" else sign_expected), "Pitch preference is correct for " + mode + "=" + str(inverted))
		app.flight.controls.clear()
	# Y inversion must never reverse horizontal steering.
	for inverted in [false, true]:
		app.flight.settings.invert = inverted
		app.flight.ship.basis = Basis.IDENTITY
		app.session.motion.turn = [0.0, 0.0]
		app.flight.controls.touch_look = Vector2(.7, 0)
		app.flight.camera.position = app.flight.ship.position + Vector3(0, 15, app.flight.follow_distance)
		app.flight.camera.basis = Basis.IDENTITY
		for tick in 24:
			app.flight.step(1.0 / 60)
			app.flight.update_camera(1.0 / 60)
		check(app.session.motion.turn[0] < 0 and app.session.motion.turn[1] == 0, "Horizontal steering ignores Y inversion")
	await capture(captures, "flight-bank", app)
	app.flight.controls.clear()
	app.show_options()
	app.options_panel.show_section("flight_hud")
	for row in app.options_panel.buttons:
		check(row.get_rect().end.y < app.options_panel.footer.position.y, "Flight display options clear footer")
	app.options_panel.handle_action("flight_overlays")
	app.options_panel.handle_action("extra_flight_buttons")
	app.load_settings()
	check(not app.settings.flight_overlays and not app.settings.extra_flight_buttons, "Overlay settings persist")
	await capture(captures, "flight-display", app)
	app.close_options(); app.resume_flight(); app.flight.set_physics_process(false)
	check(not app.flight_objective.visible and not app.flight_stats.visible and not app.radio.visible, "Optional text overlays are hidden")
	check(app.hud.buttons.pause.visible and app.hud.buttons.fire.visible, "Imported touch actions remain usable")
	for control in app.hud.extra_buttons.values(): check(not control.is_visible_in_tree(), "Extra touch action hidden")
	check(is_instance_valid(app.dialogue_panel), "Authored dialogue remains available")
	await capture(captures, "flight-clean", app)
	app.show_pause(); app.pause_action("load")
	check(app.screen == "load_recovery" and app.flight.paused, "Pause exposes recovery without advancing flight")
	await capture(captures, "load-recovery", app)
	app.load_choice("departure"); app.flight.set_physics_process(false)
	check(app.session.hull == app.session.max_hull(), "UI reloads healthy departure")
	app.session.hull = 0; app.defeat(); app.defeat_choice(0)
	check(app.screen == "load_recovery", "Defeat exposes same recovery choices")
	app.load_choice("station")
	check(app.session.docked and app.screen == "dock", "UI restores last station")
	# Emulate an older build's one-HP flight save, with no recovery metadata.
	app.session.depart()
	var legacy: Dictionary = app.session.capture(); legacy.hull = 1
	var file := FileAccess.open(app.save_path("free"), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	check(app.session.restore(legacy), "Restore actual legacy fixture without checkpoint metadata")
	app.launch(true); app.flight.set_physics_process(false)
	app.show_pause(); app.show_load_menu()
	check(app.pause_panel.buttons.size() == 4, "Older saves offer explicit station recovery")
	app.load_choice("legacy")
	check(app.confirmation.visible, "Legacy repair explains its limits before changing pilot")
	app.confirmation.hide(); app.confirm_action.call()
	check(app.session.docked and app.session.hull == app.session.max_hull() and app.session.credits == legacy.credits, "Legacy recovery breaks death loop without credit reward")
	# A legacy save already dead on disk must be recoverable from Continue too.
	legacy.hull = 0
	file = FileAccess.open(app.save_path("free"), FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(app.save_path("free") + ".bak"))
	app.show_title(); app.continue_game("free")
	check(app.screen == "load_recovery" and app.flight == null, "Continue opens recovery for an old dead primary without backup")
	app.navigate_back()
	check(app.screen == "title", "Recovery opened from title can return to title")
	app.continue_game("free"); app.load_choice("legacy")
	app.confirmation.hide(); app.confirm_action.call()
	check(app.session.docked and app.session.hull > 0, "Old dead primary can be rescued from title")
	app.music.stop(); app.stop_flight(); app.queue_free()
	await process_frame
	for slot in ["free", "campaign"]:
		for suffix in ["", ".bak", ".tmp"]: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://feedback-check-" + slot + ".json" + suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://feedback-settings.cfg"))

func capture(directory: String, filename: String, app):
	await process_frame
	if not directory.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(filename + ".png"))
