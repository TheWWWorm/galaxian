extends Node3D
## Decorative native simulation. Never owns a Session, rewards, saves or combat RNG.
const Traffic = preload("res://src/presentation/menu_traffic.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")
const Frame = preload("res://src/simulation/fighter_frame.gd")
const Encounters = preload("res://src/simulation/encounters.gd")
const Backdrop = preload("res://src/presentation/backdrop.gd")
const Ribbon = preload("res://src/presentation/projectile_trail.gd")
const Burner = preload("res://src/presentation/npc_exhaust.gd")
# A native presentation tick keeps route arrivals/history independent of redraws.
const STEP := 1.0 / 120.0
var ships: Array = []
var visuals: Array[Node3D] = []
var burners: Array = []
var trails: Array = []
var camera: Camera3D
var backdrop: Node3D
var station: Node3D
var flare_layer: CanvasLayer
var flare: Control
var data: Dictionary
var steering: Dictionary
var speed := 0.0
var pending := 0.0
var elapsed := 0.0
var trail_elapsed := 0.0
var scene_mode := -1
var error := ""
var supported := false


func configure(library, station_id: int, player_actor: int, title: bool, seed_value: int) -> bool:
	if camera != null:
		error = "Menu scene is already configured."
		return false
	data = library.content.menu_traffic
	steering = library.content.fighter_steering
	speed = float(library.content.fighter_motion.initial_speed)
	var location: Dictionary = library.station_definition(station_id)
	scene_mode = int(
		data.title_mode if title else (data.planet_mode if location.planet else data.orbital_mode)
	)
	ships = Traffic.sample(data, int(location.race), player_actor, seed_value)
	backdrop = Backdrop.new()
	add_child(backdrop)
	backdrop.configure(library, station_id)
	# The iPhone renderBG draws imported sky/planet meshes. SpaceObject's legacy
	# sprite is only retained for flare metadata, so do not draw a second planet.
	var kind: int = (
		library.location_station_type(station_id)
		if scene_mode == int(data.orbital_mode)
		else int(location.image)
	)
	if scene_mode == int(data.orbital_mode) or library.content.station_models.types.has(str(kind)):
		var random := RandomNumberGenerator.new()
		random.seed = seed_value ^ hash("station tilt")
		var bound := int(library.content.station_models.tilt_bound)
		station = library.station_model(
			kind, Vector2i(random.randi_range(0, bound - 1), random.randi_range(0, bound - 1))
		)
		add_child(station)
		if not station.error.is_empty():
			error = station.error
			return false
		if scene_mode == int(data.orbital_mode):
			station.position = Mission.point(data.orbital_position)
			station.scale = Vector3.ONE * float(data.orbital_scale)
	for ship in ships:
		ship.up = Combat.packed(Frame.axes(Combat.vector(ship.heading)).y)
		var visual := Node3D.new()
		add_child(visual)
		var hull: MeshInstance3D = library.model(library.actor_model(int(ship.actor)))
		visual.add_child(hull)
		if hull.mesh == null:
			error = library.error
			return false
		library.attach_ship_exhaust(hull, int(ship.actor))
		var burner := Burner.new()
		hull.add_child(burner)
		burner.configure(library.content.npc_exhaust, hull)
		visuals.append(visual)
		burners.append(burner)
		var trail = null
		if ship.trail:
			trail = Ribbon.new()
			add_child(trail)
			trail.configure(library, data.local_trail, Combat.vector(ship.position))
		trails.append(trail)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Mission.point(data.camera_position)
	camera.fov = float(data.fov_units) * 360.0 / 65536.0
	camera.near = float(data.near) * .02
	camera.far = float(data.far) * .02
	flare_layer = CanvasLayer.new()
	flare_layer.layer = 0
	add_child(flare_layer)
	flare = preload("res://src/presentation/lens_flare.gd").new()
	flare_layer.add_child(flare)
	flare.configure(library, camera, backdrop.declaration)
	visibility_changed.connect(sync_visibility)
	supported = true
	sync_visuals()
	sync_visibility()
	camera.current = true
	return true


func _process(seconds: float) -> void:
	advance(seconds)


func advance(seconds: float) -> void:
	if not supported or not is_visible_in_tree() or not is_finite(seconds) or seconds <= 0:
		return
	pending += seconds
	while pending + .000000001 >= STEP:
		pending = maxf(0, pending - STEP)
		elapsed += STEP
		trail_elapsed += STEP
		for ship in ships:
			step_ship(ship, data, steering, speed, STEP)
		if trail_elapsed + .000000001 >= data.trail_seconds:
			trail_elapsed -= data.trail_seconds
			for index in ships.size():
				if trails[index] != null:
					trails[index].advance(Combat.vector(ships[index].position))
	for burner in burners:
		burner.advance(seconds, speed)
	sync_visuals()


static func step_ship(
	ship: Dictionary,
	parameters: Dictionary,
	turn_data: Dictionary,
	current_speed: float,
	seconds: float
) -> void:
	var position := Combat.vector(ship.position)
	var heading := Combat.vector(ship.heading)
	var cursor := int(ship.waypoint)
	if cursor < ship.route.size():
		var offset := Mission.point(ship.route[cursor]) - position
		var extent := offset.abs()
		if maxf(extent.x, maxf(extent.y, extent.z)) <= parameters.waypoint_half_width:
			cursor += 1
			if cursor == ship.route.size() and ship.loop:
				cursor = int(parameters.route_start)
			ship.waypoint = cursor
		if cursor < ship.route.size():
			var desired := Mission.point(ship.route[cursor]) - position
			var rate := float(
				(
					turn_data.enhanced_rate
					if int(ship.actor) == int(turn_data.enhanced_actor)
					else turn_data.normal_rate
				)
			)
			heading = Encounters.steer_heading(
				heading, desired, seconds, rate, float(turn_data.snap_distance)
			)
	# The source lock clears the vertical direction after steering. It does not
	# teleport ships between route ends or disable their horizontal turning.
	if ship.rotation_locked:
		heading.y = 0
		if heading.length_squared() < .000001:
			heading = Combat.vector(ship.heading)
		heading = heading.normalized()
	Frame.turn(ship, heading)
	ship.position = Combat.packed(position + heading * current_speed * seconds)


func sync_visuals() -> void:
	for index in ships.size():
		var ship: Dictionary = ships[index]
		visuals[index].position = Combat.vector(ship.position)
		visuals[index].basis = Frame.axes(Combat.vector(ship.heading), Combat.vector(ship.up))
	if station != null:
		station.set_elapsed(elapsed * 1000.0)
	if not ships.is_empty():
		var target: Node3D = visuals.back()
		var direction := target.global_position - camera.global_position
		if direction.length_squared() > .000001:
			var up := target.global_basis.y
			if absf(direction.normalized().dot(up)) > .999999:
				up = Frame.axes(direction.normalized()).y
			camera.look_at(target.global_position, up)
	backdrop.follow(camera)


func sync_visibility() -> void:
	if flare_layer != null:
		flare_layer.visible = is_visible_in_tree()
		flare.set_process(flare_layer.visible)
