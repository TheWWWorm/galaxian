extends SceneTree
## Existing imported content only; isolated preferences and transient pilots.
const Library = preload("res://src/content/library.gd")
const Controls = preload("res://src/input/controls.gd")
var checks := 0
var failures := 0
class TestMain extends "res://src/main.gd":
	func _ready(): pass
	func _process(_delta): pass
	func settings_path(): return "user://control-regression-settings.cfg"

func _initialize(): call_deferred("run")
func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func run():
	check_fire_timing()
	check_steering()
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass an existing imported content directory after --")
		quit(2); return
	if args.size() > 2 and args[2] == "mobile-layout":
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open existing imported content")
	if failures: quit(1); return
	var app := TestMain.new()
	root.add_child(app)
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true; app.transient_preview = true
	app.show_options()
	var languages := lib.available_languages()
	check(not languages.is_empty(), "Language selector has imported choices")
	var panel = app.options_panel
	check(panel.entries.any(func(e): return e.action == "language"), "Language is visible in top-level Options")
	for language in languages:
		lib.radio_lines_cache["stale"] = ["old text"]
		app.change_option("language", language)
		check(lib.language_code == language and app.settings.language == language, "Select " + language)
		check(lib.radio_lines_cache.is_empty(), "Language change invalidates dialogue layout")
		var expected := lib.reader.language(lib.read(language + ".lang"))
		check(lib.text(int(lib.content.options_ui.labels.controls)) == expected[int(lib.content.options_ui.labels.controls)], "Menu uses imported " + language + " text")
		check(panel.buttons[0].text == expected[int(lib.content.options_ui.labels.controls)], "Visible menu refreshes in " + language)
		for row in panel.buttons:
			check(row.get_rect().end.y < panel.footer.position.y, "Language menu clears footer")
		app.settings.language = "invalid"
		app.load_settings()
		check(app.settings.language == language, "Persist " + language)
	var before := lib.strings
	check(not lib.set_language("../missing") and lib.strings == before, "Invalid language cannot change loaded text")
	var next_language: String = languages[(languages.find(lib.language_code) + 1) % languages.size()]
	await process_frame
	var language_button: Vector2 = panel.buttons[3].get_global_rect().get_center()
	await touch(language_button, 9, true); await touch(language_button, 9, false)
	check(lib.language_code == next_language and app.settings.language == next_language, "Language row cycles imported choices and persists selection")
	check(app.importer.open_cache(args[0]), "Reopen installed manifest")
	check(app.activate_content() and lib.language_code == next_language, "Content activation restores chosen language")
	app.settings.language = "unavailable"
	check(app.activate_content() and lib.language_code == ("gb" if languages.has("gb") else languages[0]), "Content activation falls back when a preferred language is unavailable")
	app.change_option("language", "gb" if languages.has("gb") else languages[0])
	app.settings.touch = true
	app.session = preload("res://src/simulation/session.gd").new()
	app.session.configure(lib, true)
	app.launch()
	app.flight.set_physics_process(false)
	for frame in 3: await process_frame
	await check_touch(app)
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		app.show_options()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[1].path_join("controls-options.png"))
	app.music.stop()
	app.stop_flight()
	app.queue_free()
	await process_frame
	await create_timer(.1).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://control-regression-settings.cfg"))
	print("CONTROL REGRESSIONS ", checks, " CHECKS; ", failures, " FAILURES")
	quit(1 if failures else 0)

func check_fire_timing():
	var controls := Controls.new()
	controls.press_touch_fire(1000); controls.release_touch_fire(1100)
	check(not controls.snapshot().fire, "Single tap does not latch")
	controls.press_touch_fire(1400); controls.release_touch_fire(1450)
	check(controls.snapshot().fire and not controls.touch_fire, "Double tap latches after release")
	controls.press_touch_fire(1500); controls.release_touch_fire(1550)
	check(not controls.snapshot().fire, "Single tap stops autofire")
	controls.press_touch_fire(1600); controls.release_touch_fire(1650)
	check(not controls.snapshot().fire, "Stop tap cannot accidentally rearm autofire")
	controls.clear()
	controls.press_touch_fire(2000); controls.release_touch_fire(2500)
	controls.press_touch_fire(2550); controls.release_touch_fire(2600)
	check(not controls.snapshot().fire, "Long hold then tap does not latch")
	controls.clear()
	controls.press_touch_fire(3000); controls.release_touch_fire(3050)
	controls.press_touch_fire(3600); controls.release_touch_fire(3650)
	check(not controls.snapshot().fire, "Separated taps remain manual")
	for interval in [20, 150, Controls.FIRE_DOUBLE_TAP_MS]:
		controls.clear()
		controls.press_touch_fire(4000); controls.release_touch_fire(4050)
		controls.press_touch_fire(4050 + interval); controls.release_touch_fire(4100 + interval)
		check(controls.snapshot().fire, "Autofire accepts double tap interval " + str(interval))
	controls.clear()
	check(not controls.snapshot().fire and controls.fire_released_ms == -1, "Pause/reset clears autofire and tap history")

func check_steering():
	var flight := preload("res://src/presentation/flight.gd").new()
	# No tree or simulation needed to test the cockpit's turn axes.
	for pitch in [0.0, PI * .49, PI * .51, PI, PI * 1.5, TAU]:
		for roll in [0.0, PI * .5, PI]:
			flight.ship.basis = Basis.from_euler(Vector3(pitch, .6, roll))
			var before := flight.ship.basis
			flight.steer(-.05, 0)
			var local_forward: Vector3 = before.inverse() * -flight.ship.basis.z
			check(local_forward.x > 0 and absf(local_forward.y) < .001, "Right yaw follows cockpit at pitch/roll " + str(Vector2(pitch, roll)))
			flight.ship.basis = before
			flight.steer(0, .05)
			local_forward = before.inverse() * -flight.ship.basis.z
			check(local_forward.y > 0 and absf(local_forward.x) < .001, "Pitch follows cockpit at " + str(Vector2(pitch, roll)))
	for child in [flight.ship, flight.camera, flight.audio, flight.ambience, flight.player_hit]:
		flight.add_child(child)
	flight.player_hit.add_child(flight.player_hit.audio)
	flight.free()

func touch(at: Vector2, finger: int, down: bool, canceled: bool = false):
	var event := InputEventScreenTouch.new()
	event.index = finger; event.position = root.get_final_transform() * at
	event.pressed = down; event.canceled = canceled
	Input.parse_input_event(event)
	await process_frame

func drag(at: Vector2, finger: int):
	var event := InputEventScreenDrag.new()
	event.index = finger; event.position = root.get_final_transform() * at
	Input.parse_input_event(event)
	await process_frame

func check_touch(app):
	var hud = app.hud
	var controls = app.flight.controls
	var center: Vector2 = hud.stick_center * hud.factor
	check(hud.stick_vector == Vector2.ZERO and controls.touch_look == Vector2.ZERO, "Stick starts neutral")
	check(hud.stick_center - hud.stick_origin == measured_ring_center(hud.art.stick_frame.get_image()), "Stick pivot matches the visible ring measured from imported pixels")
	await touch(center, 0, true)
	check(controls.touch_look == Vector2.ZERO, "Touching centered stick does not steer")
	await drag(center + Vector2(20, 0) * hud.factor, 0)
	check(controls.touch_look.x > 0 and is_zero_approx(controls.touch_look.y), "Fixed stick steers right")
	var empty: Vector2 = hud.size * .5
	await touch(empty, 1, true); await drag(empty - Vector2(90, 90), 1)
	check(controls.touch_look.x > 0 and is_zero_approx(controls.touch_look.y), "Second steering finger cannot overwrite stick")
	await touch(empty, 1, false)
	check(controls.touch_look.x > 0, "Unowned release cannot clear active stick")
	var fire: Vector2 = hud.buttons.fire.get_global_rect().get_center()
	await touch(fire, 2, true); await touch(fire, 2, false)
	await touch(fire, 2, true); await touch(fire, 2, false)
	check(controls.touch_autofire and controls.snapshot().fire, "Real multitouch double-tap enables autofire while steering")
	check(controls.touch_look.x > 0, "Fire finger does not disturb steering")
	app.flight._physics_process(.016)
	check(not app.session.combat.projectiles.is_empty(), "Latched autofire emits projectiles without a held fire finger")
	await touch(fire, 2, true); await touch(fire, 2, false)
	check(not controls.snapshot().fire, "Real touch stops autofire")
	await touch(center, 0, false)
	check(controls.touch_look == Vector2.ZERO and hud.stick_vector == Vector2.ZERO, "Release recenters stick")
	await touch(empty, 3, true); await drag(empty + Vector2(40, 0), 3)
	check(controls.touch_look == Vector2.ZERO and hud.stick_finger < 0, "Empty space does not steer")
	await touch(center, 4, true); await drag(center - Vector2(40, 0), 4)
	check(controls.touch_look.x < 0 and hud.stick_finger == 4, "Stick still owns steering while empty space is held")
	await touch(empty, 3, false)
	check(controls.touch_look.x < 0, "Unowned empty release cannot clear the stick")
	await touch(center, 4, false, true)
	check(controls.touch_look == Vector2.ZERO, "Canceled touch clears steering")
	controls.clear()
	await touch(fire, 5, true); await touch(empty, 5, false, true)
	await touch(fire, 5, true); await touch(fire, 5, false)
	check(not controls.snapshot().fire, "Canceled fire tap cannot arm autofire")
	await touch(fire, 5, true); await touch(fire, 5, false)
	check(controls.touch_autofire, "Autofire can be enabled again")
	app.update_tutorial_controls()
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[1].path_join("controls-autofire.png"))
	check(hud.autofire_label.visible and hud.autofire_label.get_index() > hud.buttons.fire.get_index(), "AUTO indicator is visible above the fire artwork")
	await touch(center + Vector2(20, 0), 6, true)
	app.show_pause(); await process_frame
	var pilot_before: Dictionary = app.session.capture().duplicate(true)
	app.show_options()
	app.change_option("language", app.library.available_languages()[0])
	check(app.session.capture() == pilot_before and app.session.library == app.library, "Changing language during a flight preserves the pilot and shared content")
	check(app.controls_help().begins_with("Touch:") and "double-tap Fire" in app.controls_help(), "Touch help leads with autofire instructions")
	app.close_options()
	app.resume_flight(); app.flight.set_physics_process(false); await process_frame
	check(not controls.touch_autofire and controls.touch_look == Vector2.ZERO, "Pause/resume clears held touches and autofire")
	await touch(app.hud.stick_center * app.hud.factor, 7, true)
	check(app.hud.stick_finger == 7, "A fresh touch works after pause without old finger release")
	await touch(app.hud.stick_center * app.hud.factor, 7, false)


func measured_ring_center(image: Image) -> Vector2:
	# Measure the connected, flat-colored center of the frame independently of
	# layout constants. Its bounds exclude the arrows and lower-left extension.
	var seed := image.get_size() / 2
	var color := image.get_pixelv(seed)
	var pending: Array[Vector2i] = [seed]
	var visited := {seed: true}
	var low := seed
	var high := seed
	var index := 0
	while index < pending.size():
		var point := pending[index]
		index += 1
		low = low.min(point)
		high = high.max(point)
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = point + offset
			if visited.has(next) or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(next):
				continue
			visited[next] = true
			if image.get_pixelv(next) == color:
				pending.append(next)
	return (Vector2(low) + Vector2(high) + Vector2.ONE) * .5
