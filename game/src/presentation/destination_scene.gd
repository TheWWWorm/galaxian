extends Node3D
## Cosmetic destination scene. No pilot, encounter, inventory or gameplay clock.
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")
var data: Dictionary
var camera: Camera3D
var station: Node3D
var backdrop: Node3D
var flare_layer: CanvasLayer
var flare: Control
var elapsed := 0.0
var error := ""
var supported := false
var scene_mode := -1


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["look_offset", "position_offset"]:
		if not Combat.valid_vector(value.get(key)):
			return false
	for key in ["planet_mode", "orbital_mode", "station_z", "special_type", "special_z", "fov_units", "near", "far"]:
		if not Combat.integer(value.get(key)) or value[key] < 0:
			return false
	for key in ["look_blend", "position_blend", "initial_scale", "reference_seconds"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] >= 1:
			return false
	return value.fov_units > 0 and value.fov_units < 32768 and value.near > 0 and value.far > value.near


static func pose_at(config: Dictionary, seconds: float) -> Dictionary:
	# Closed form for two coupled relaxations over a fixed, identity target.
	# Interpolate between source timer ticks, so redraw frequency cannot change it.
	var steps := maxf(0, seconds) / float(config.reference_seconds) + 1.0
	var whole := int(floor(steps))
	var first := tick_pose(config, whole)
	var second := tick_pose(config, whole + 1)
	return {
		"position": first.position.lerp(second.position, steps - whole),
		"look": first.look.lerp(second.look, steps - whole)
	}


static func tick_pose(config: Dictionary, tick: int) -> Dictionary:
	var aim := Mission.point(config.look_offset)
	var offset := Mission.point(config.position_offset)
	var retention := 1.0 - float(config.look_blend)
	var coupling := float(config.position_blend)
	var initial_aim := aim * float(config.initial_scale)
	var initial_position := offset * float(config.initial_scale)
	var rest := (aim + coupling * offset) / (1.0 + coupling)
	var aim_decay := pow(retention, tick)
	var position_decay := pow(coupling, tick) * (-1.0 if tick % 2 else 1.0)
	return {
		"look": aim + (initial_aim - aim) * aim_decay,
		"position": rest + (initial_position - rest) * position_decay + (initial_aim - aim) * (aim_decay - position_decay) / (retention + coupling)
	}


func configure(library, station_id: int) -> bool:
	if camera != null:
		error = "Destination scene is already configured."
		return false
	data = library.content.station_ui.destination.scene
	if not valid_data(data):
		error = "Unsupported destination scene declaration."
		return false
	var location: Dictionary = library.station_definition(station_id)
	scene_mode = int(data.planet_mode if location.planet else data.orbital_mode)
	backdrop = preload("res://src/presentation/backdrop.gd").new()
	add_child(backdrop)
	backdrop.configure(library, station_id)
	var kind := int(location.image) if location.planet else int(library.location_station_type(station_id))
	if not location.planet or library.content.station_models.types.has(str(kind)):
		var random := RandomNumberGenerator.new()
		random.seed = hash(library.id + ":destination:" + str(station_id))
		var bound := int(library.content.station_models.tilt_bound)
		station = library.station_model(kind, Vector2i(random.randi_range(0, bound - 1), random.randi_range(0, bound - 1)))
		add_child(station)
		if not station.error.is_empty():
			error = station.error
			return false
		station.position = Mission.point([0, 0, data.special_z if kind == data.special_type else data.station_z])
	camera = Camera3D.new()
	add_child(camera)
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
	sync_pose()
	sync_visibility()
	camera.current = true
	return true


func _process(seconds: float) -> void:
	advance(seconds)


func advance(seconds: float) -> void:
	if not supported or not is_visible_in_tree() or not is_finite(seconds) or seconds <= 0:
		return
	elapsed += seconds
	sync_pose()


func sync_pose() -> void:
	var pose := pose_at(data, elapsed)
	camera.position = pose.position
	camera.look_at(to_global(pose.look), Vector3.UP)
	backdrop.follow(camera)
	if station != null:
		station.set_elapsed(elapsed * 1000.0)


func sync_visibility() -> void:
	if flare_layer != null:
		flare_layer.visible = is_visible_in_tree()
		flare.set_process(flare_layer.visible)
