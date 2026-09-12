extends "res://tests/player_feedback.gd"
## Player feedback batch 13: hangar view orientation, cinematic HUD visibility,
## stick-only touch steering, speed-linked dust, placed-hull orientation and the
## tilt steering axis. Uses existing imported content and private settings.
const Motion = preload("res://src/input/motion_steering.gd")
const HangarScene = preload("res://src/presentation/hangar_scene.gd")
const FlightEffects = preload("res://src/presentation/flight_effects.gd")


class Feedback13Main:
	extends "res://src/main.gd"

	func _ready():
		pass

	func _process(_delta):
		pass

	func advance_presentation(delta):
		super._process(delta)

	func save_path(slot):
		return "user://feedback13-" + slot + ".json"

	func settings_path():
		return "user://feedback13-settings.cfg"


func run():
	var args := OS.get_cmdline_user_args()
	if args.has("mobile"):
		preload("res://src/presentation/bitmap_font.gd").mobile_cache = 1
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open existing imported content")
	if failures:
		quit(1)
		return
	check_motion_axis()
	check_dust(lib)
	await check_hangar_view(lib)
	await check_cinematic_hud(lib)
	await check_placed_orientation(lib)
	print("FEEDBACK13 ", checks, " CHECKS; ", failures, " FAILURES")
	call_deferred("finish_feedback")


func touch(at: Vector2, finger: int, down: bool, canceled: bool = false):
	var event := InputEventScreenTouch.new()
	event.index = finger
	event.position = root.get_final_transform() * at
	event.pressed = down
	event.canceled = canceled
	Input.parse_input_event(event)
	await process_frame


func drag(at: Vector2, finger: int):
	var event := InputEventScreenDrag.new()
	event.index = finger
	event.position = root.get_final_transform() * at
	Input.parse_input_event(event)
	await process_frame


func check_motion_axis() -> void:
	# Screen-space gravity points down at rest. Rolling the phone's right edge
	# down tips it to +X, which has to steer right like a stick pushed right.
	var sensor := Motion.new()
	check(
		sensor.sample(Vector3(0, -9.8, 0), .1, .5) == Vector2.ZERO, "Level phone is neutral"
	)
	check(sensor.sample(Vector3(3, -9, 0), 1, .5).x > .5, "Right-edge-down roll steers right")
	sensor = Motion.new()
	check(sensor.sample(Vector3(0, -9.8, 0), .1, .5) == Vector2.ZERO, "Recentered")
	check(sensor.sample(Vector3(-3, -9, 0), 1, .5).x < -.5, "Left-edge-down roll steers left")
	sensor = Motion.new()
	check(sensor.sample(Vector3(0, -9.8, 0), .1, .5) == Vector2.ZERO, "Recentered again")
	check(
		sensor.sample(Vector3(0, -9, -3), 1, .5).y < -.5,
		"Vertical tilt keeps its existing direction"
	)
	check(
		absf(Motion.angles(Vector3(0, -9.8, 0)).y) < .0001,
		"Vertical term reads zero for a resting phone"
	)


func check_dust(lib) -> void:
	var effects := FlightEffects.new()
	effects.configure(lib)
	var data: Dictionary = lib.content.flight_effects.stars
	var pose := Transform3D.IDENTITY
	for step in 40:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
	var moving: Array = effects.particles.filter(func(p): return p.node.visible)
	check(not moving.is_empty(), "Cruising spawns the supplied dust field")
	# Kept for the throttle comparison below, before the field is cleared.
	var snapshot := effects.particles.map(
		func(p): return {"position": p.node.position, "life": p.life, "shown": p.node.visible}
	)
	# The supplied lifetime recycles a field the original hull was always flying
	# through. At a standstill it used to retire the field one speck at a time
	# over two seconds; the whole field now goes at once.
	effects.advance(float(data.reference_seconds), pose, false, 0.0, 0.0)
	check(
		effects.particles.all(func(p): return not p.node.visible),
		"A stopped ship clears the whole dust field in one step"
	)
	var before: int = effects.spawned
	for step in 40:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, 0.0)
	check(effects.spawned == before, "Stopped ship spawns no further dust")
	check(
		effects.particles.all(func(p): return not p.node.visible),
		"A stopped ship keeps the field clear"
	)
	# Boost moves the hull whatever the throttle reads, so its dust still runs.
	effects.advance(float(data.reference_seconds), pose, true, 1.0, 0.0)
	check(
		effects.particles.any(func(p): return p.node.visible),
		"Boosting from a standstill still shows dust"
	)
	# Stopping again, then resuming, should start refilling on the first step
	# rather than after another spawn interval spent waiting.
	effects.advance(float(data.reference_seconds), pose, false, 0.0, 0.0)
	var resumed: int = effects.spawned
	effects.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
	check(effects.spawned == resumed + 1, "Throttling up spawns again on the first step")
	var slow_reach: float = stepped(effects, snapshot, data, .25)
	var fast_reach: float = stepped(effects, snapshot, data, 1.0)
	check(slow_reach > 0 and slow_reach < fast_reach * .6, "Dust travel follows the throttle")
	check_dust_pace(lib)
	effects.free()


func check_dust_pace(lib) -> void:
	## These specks run 15 to 30 times faster than the hull, so they are a speed
	## cue, not matter being passed. A speck must reach the camera inside its
	## life or it dies on screen, which is what made a crawling ship look wrong.
	var data: Dictionary = lib.content.flight_effects.stars
	var pose := Transform3D.IDENTITY
	var threshold := FlightEffects.cue_threshold(data)
	var imported_floor: float = (
		float(data.spawn_depth)
		/ (float(data.normal_speed_min) * float(data.normal_lifetime))
	)
	check(
		threshold >= imported_floor and threshold < .95,
		"The cue threshold never drops below the imported floor (%f vs %f)"
		% [threshold, imported_floor]
	)
	check(
		is_equal_approx(threshold, FlightEffects.CUE_MINIMUM),
		"This content is cut at the calibrated minimum, not the imported floor"
	)

	# Above the threshold the cue spawns; below it, it stops.
	for probe in [{"rate": threshold + .05, "spawns": true}, {"rate": threshold - .05, "spawns": false}]:
		var effects := FlightEffects.new()
		effects.configure(lib)
		for step in 60:
			effects.advance(float(data.reference_seconds), pose, false, 0.0, probe.rate)
		check(
			(effects.spawned > 0) == probe.spawns,
			"Throttle %f %s the cue" % [probe.rate, "spawns" if probe.spawns else "stops"]
		)
		effects.free()

	# Below the threshold an already populated field must drain rather than
	# freeze: no replacements, and the survivors keep drifting out.
	var effects := FlightEffects.new()
	effects.configure(lib)
	for step in 200:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
	check(
		effects.particles.any(func(p): return p.node.visible), "Cruising fills the field"
	)
	var tracked: Dictionary = effects.particles.filter(func(p): return p.node.visible)[0]
	var before: Vector3 = tracked.node.position
	effects.advance(float(data.reference_seconds), pose, false, 0.0, .02)
	check(
		tracked.node.position.distance_to(before) > 0.0,
		"A barely moving ship still drifts its remaining specks out"
	)
	var held: int = effects.spawned
	var steps := 0
	while effects.particles.any(func(p): return p.node.visible) and steps < 400:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, .02)
		steps += 1
	check(steps < 400, "The field empties itself below the threshold")
	check(effects.spawned == held, "Nothing is respawned while emptying")
	# The floor keeps that drain brisk instead of leaving specks crawling.
	check(
		float(steps) * float(data.reference_seconds) <= float(data.normal_lifetime) + .1,
		"Emptying takes no longer than one supplied lifetime"
	)
	effects.free()

	# Lifetime is a wall clock again: there is no real path for a speck to cover.
	var timed := FlightEffects.new()
	timed.configure(lib)
	var waited := 0
	while timed.particles.all(func(p): return not p.node.visible) and waited < 400:
		timed.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
		waited += 1
	var speck: Dictionary = timed.particles.filter(func(p): return p.node.visible)[0]
	var alive := 0
	while alive < 400:
		var remaining: float = speck.life
		timed.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
		alive += 1
		if speck.life <= 0 or speck.life > remaining:
			break
	check(
		absf(float(alive) * float(data.reference_seconds) - float(data.normal_lifetime)) < .1,
		"A speck keeps the supplied lifetime"
	)
	timed.free()

	# Length is the speed smear: the supplied boost adds 90 to it and 0 to width.
	var shaped := FlightEffects.new()
	shaped.configure(lib)
	var settle := 0
	while shaped.particles.all(func(p): return not p.node.visible) and settle < 400:
		shaped.advance(float(data.reference_seconds), pose, false, 0.0, 1.0)
		settle += 1
	var shown: Dictionary = shaped.particles.filter(func(p): return p.node.visible)[0]
	check(
		is_equal_approx(shown.node.scale.z, float(data.half_length)),
		"At cruise the streak keeps its supplied length"
	)
	var cruise_width: float = shown.node.scale.x
	shaped.advance(float(data.reference_seconds), pose, false, 0.0, threshold)
	check(
		shown.node.scale.z < float(data.half_length) * .5,
		"A slow ship shortens the streak toward a point"
	)
	check(
		is_equal_approx(shown.node.scale.x, cruise_width),
		"Throttle does not change the speck's width"
	)
	shaped.advance(float(data.reference_seconds), pose, true, 1.0, 0.0)
	check(
		is_equal_approx(shown.node.scale.z, float(data.half_length) + float(data.boost_length)),
		"Boost keeps its supplied stretched streak"
	)
	shaped.free()


func stepped(effects, snapshot: Array, data: Dictionary, rate: float) -> float:
	for index in effects.particles.size():
		var particle: Dictionary = effects.particles[index]
		particle.node.position = snapshot[index].position
		particle.life = snapshot[index].life
		particle.node.visible = snapshot[index].shown
	effects.pending = 0.0
	effects.spawn_elapsed = 0.0
	for step in 4:
		effects.advance(float(data.reference_seconds), Transform3D.IDENTITY, false, 0.0, rate)
	var total := 0.0
	for index in effects.particles.size():
		var particle: Dictionary = effects.particles[index]
		# Ignore any particle that expired and respawned during these steps.
		if not snapshot[index].shown or not particle.node.visible or particle.life > snapshot[index].life:
			continue
		total += particle.node.position.distance_to(snapshot[index].position)
	return total


func check_hangar_view(lib) -> void:
	var app := Feedback13Main.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.transient_preview = true
	app.settings.music = false
	app.settings.music_volume = 0.0
	app.settings.effects_volume = 0.0
	app.apply_audio_settings()
	app.session = preload("res://src/simulation/session.gd").new()
	app.session.configure(lib, true)
	app.show_market("ship")
	var scene = app.menu_scene
	check(scene != null and scene.supported, "Supplied hangar scene is displayed")
	if scene == null or not scene.supported:
		app.queue_free()
		await process_frame
		return
	for frame in 3:
		await process_frame
	var view: Dictionary = lib.content.hangar_ui.scene.camera
	var right: Vector3 = scene.camera.global_transform.basis.x
	# The supplied camera matrix stores right, up and back columns. Its recovered
	# right column must be the on-screen right axis, not its reflection.
	var forward := HangarScene.view_point(view.forward).normalized()
	var up := HangarScene.view_point(view.up).normalized()
	var expected := forward.cross(up).normalized()
	check(right.dot(expected) > .999, "Hangar screen-right matches the supplied camera column")
	check(
		is_equal_approx(scene.stage.scale.z, -1.0) and scene.hulls.get_parent() == scene.stage,
		"Hangar content is presented in supplied axes"
	)
	# The supplied entrance ends looking straight down the parking bay: its stored
	# forward column points at the player hull from the closing camera position.
	scene.elapsed = float(view.entrance_seconds) * .999
	scene.sync_camera()
	for frame in 2:
		await process_frame
	var hull: Node3D = scene.hulls.get_child(0)
	var offset: Vector3 = hull.global_position - scene.camera.global_position
	check(offset.dot(-scene.camera.global_transform.basis.z) > 0, "Player hull is in front of the view")
	check(
		absf(offset.normalized().dot(scene.camera.global_transform.basis.x)) < .05,
		"Closing entrance view is centred on the player hull"
	)
	app.queue_free()
	await process_frame


func check_cinematic_hud(lib) -> void:
	var app := Feedback13Main.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.transient_preview = true
	app.settings.touch = true
	app.settings.music = false
	app.settings.music_volume = 0.0
	app.settings.effects_volume = 0.0
	app.apply_audio_settings()
	app.session = preload("res://src/simulation/session.gd").new()
	app.session.configure(lib, true)
	app.launch()
	app.flight.set_physics_process(false)
	app.show_flight_hud()
	for frame in 3:
		await process_frame
	var hud = app.hud
	check(not app.flight.cinematic_locked() and hud.visible, "Flight HUD is visible during play")
	var centre: Vector2 = hud.stick_center * hud.factor
	await touch(centre, 0, true)
	await drag(centre + Vector2(20, 0) * hud.factor, 0)
	check(app.flight.controls.touch_look.x > 0, "Stick steers before the cinematic")
	app.flight.outro_active = true
	app.advance_presentation(.05)
	for frame in 2:
		await process_frame
	check(app.flight.cinematic_locked(), "Scripted sequence owns the scene")
	check(not hud.visible, "Cinematic hides the flight HUD")
	await capture_review("cinematic-hud-hidden")
	check(
		app.flight.controls.touch_look == Vector2.ZERO and hud.stick_finger < 0,
		"Cinematic releases held touch steering"
	)
	check(
		app.dialogue_panel != null and app.dialogue_panel.get_parent() != hud,
		"Dialogue is not part of the hidden HUD"
	)
	await touch(centre, 1, true)
	await drag(centre + Vector2(20, 0) * hud.factor, 1)
	check(app.flight.controls.touch_look == Vector2.ZERO, "Hidden HUD ignores touch")
	await touch(centre, 1, false)
	app.flight.outro_active = false
	app.advance_presentation(.05)
	for frame in 2:
		await process_frame
	check(hud.visible, "HUD returns when the cinematic ends")
	await capture_review("flight-hud-visible")
	var empty: Vector2 = Vector2(hud.size.x * .5, hud.size.y * .35)
	await touch(empty, 2, true)
	await drag(empty + Vector2(60, 0), 2)
	check(
		app.flight.controls.touch_look == Vector2.ZERO and hud.stick_finger < 0,
		"Empty space no longer steers"
	)
	await touch(empty, 2, false)
	app.stop_flight()
	app.music.stop()
	app.queue_free()
	await process_frame


func capture_review(name: String):
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args[1] == "mobile" or DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[1].path_join(name + ".png"))


func check_placed_orientation(lib) -> void:
	var app := Feedback13Main.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.transient_preview = true
	app.settings.music = false
	app.settings.music_volume = 0.0
	app.settings.effects_volume = 0.0
	app.apply_audio_settings()
	app.session = preload("res://src/simulation/session.gd").new()
	app.session.configure(lib, true)
	app.launch()
	app.flight.set_physics_process(false)
	for frame in 2:
		await process_frame
	var node := Node3D.new()
	app.flight.add_child(node)
	var transit := {"behavior": "transit", "velocity": [0.0, 0.0, -120.0]}
	node.rotate_y(1.0)
	app.flight.orient_placed_actor(node, transit, .5)
	check(
		node.basis.z.normalized().dot(Vector3.BACK) > .999,
		"Transit freighters face their travel direction"
	)
	var sideways := {"behavior": "transit", "velocity": [90.0, 0.0, 0.0]}
	app.flight.orient_placed_actor(node, sideways, .5)
	check(
		node.basis.z.normalized().dot(Vector3.LEFT) > .999,
		"Transit orientation follows the imported velocity"
	)
	var placed := {"behavior": "stationary"}
	var before := node.basis
	for step in 10:
		app.flight.orient_placed_actor(node, placed, .5)
	check(node.basis.is_equal_approx(before), "Stationary hulls hold their placement")
	var scaled := {"behavior": "transit", "velocity": [0.0, 0.0, -120.0], "source_scale": true}
	node.basis = before
	app.flight.orient_placed_actor(node, scaled, .5)
	check(node.basis.is_equal_approx(before), "Source-scaled convoy bodies are left untouched")
	var debris := {}
	for step in 10:
		app.flight.orient_placed_actor(node, debris, .5)
	check(not node.basis.is_equal_approx(before), "Loose scenery debris still tumbles")
	var spinning := 0
	var definition: Dictionary = app.session.mission_definition()
	for group in definition.get("groups", []):
		if group.get("behavior", "") in ["interceptor", "escort", "wingmate", "turret"]:
			continue
		if group.get("source_scale", false) or not group.has("behavior"):
			continue
		spinning += 1
	check(spinning == 0, "No placed mission hull is left to the tumble path")
	node.queue_free()
	app.stop_flight()
	app.music.stop()
	app.queue_free()
	await process_frame
