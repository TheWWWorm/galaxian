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
	var held := moving.map(func(p): return p.node.position)
	for step in 40:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, 0.0)
	var still := true
	for index in moving.size():
		if moving[index].node.position != held[index]:
			still = false
	check(still, "Stopped ship holds the dust in place")
	var before: int = effects.spawned
	for step in 40:
		effects.advance(float(data.reference_seconds), pose, false, 0.0, 0.0)
	check(effects.spawned == before, "Stopped ship spawns no further dust")
	# Compare the same populated field advanced from one state at two throttles.
	var snapshot := effects.particles.map(
		func(p): return {"position": p.node.position, "life": p.life, "shown": p.node.visible}
	)
	var slow_reach: float = stepped(effects, snapshot, data, .25)
	var fast_reach: float = stepped(effects, snapshot, data, 1.0)
	check(slow_reach > 0 and slow_reach < fast_reach * .6, "Dust travel follows the throttle")
	effects.free()


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
