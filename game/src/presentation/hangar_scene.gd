extends Node3D
## Supplied indoor scenery. Inventory is a read-only snapshot owned by Session.
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")
var data: Dictionary
var camera: Camera3D
var stage: Node3D
var hulls: Node3D
var interior: Node3D
var library
var station_id := -1
var elapsed := 0.0
var supported := false
var error := ""
var inventory: Array = []
var player_ship := -1
var camera_x := 0.0
var drift = preload("res://src/presentation/hangar_drift.gd").new()


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["interiors", "shadows", "camera"]:
		if not value.get(key) is Dictionary:
			return false
	for key in ["race", "yaw_units"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 65535:
			return false
	if not Combat.number(value.get("shadow_y")) or absf(value.shadow_y) > 100000:
		return false
	if not point_valid(value.get("player_position")):
		return false
	if not value.get("stock_positions") is Array or value.stock_positions.is_empty() or value.stock_positions.size() > 64:
		return false
	for position in value.stock_positions:
		if not point_valid(position):
			return false
	for key in ["default", "race"]:
		var record: Variant = value.interiors.get(key)
		if not record is Dictionary:
			return false
		for field in ["body", "lights"]:
			if not Combat.integer(record.get(field)) or record[field] <= 0:
				return false
	if value.shadows.is_empty():
		return false
	for actor in value.shadows:
		if not str(actor).is_valid_int() or int(actor) < 0 or not Combat.integer(value.shadows[actor]) or value.shadows[actor] <= 0:
			return false
	var view: Dictionary = value.camera
	for key in ["x_default", "x_race", "y", "z_start", "z_end", "fov_units", "near", "far", "entrance_seconds"]:
		if not Combat.number(view.get(key)) or absf(view[key]) > 1000000:
			return false
	if view.fov_units <= 0 or view.fov_units >= 32768 or view.near <= 0 or view.far <= view.near or view.entrance_seconds <= 0:
		return false
	if not point_valid(view.get("forward")) or not point_valid(view.get("up")):
		return false
	return (
		Combat.vector(view.forward).cross(Combat.vector(view.up)).length_squared() > .000001
		and preload("res://src/presentation/hangar_drift.gd").valid_data(value.get("drift"))
	)


static func point_valid(value: Variant) -> bool:
	return value is Array and value.size() == 3 and value.all(func(v): return Combat.number(v) and absf(v) <= 1000000)


func configure(source, location: int, ship: int, offers: Array) -> bool:
	if camera != null:
		error = "Hangar scene is already configured."
		return false
	library = source
	data = library.content.hangar_ui.scene
	station_id = location
	var alternate: bool = int(library.station_definition(location).race) == int(data.race)
	library.set_lighting(0, 0, location, true)
	var definition: Dictionary = data.interiors.race if alternate else data.interiors.default
	# Supplied meshes and placements are stored with reflected Z. That reflection
	# is invisible while a camera only tracks a target, but this scene imports the
	# original camera basis, whose screen-right axis a reflected stage reverses.
	# Presenting the stage back in source coordinates keeps the imported view.
	stage = Node3D.new()
	stage.scale = Vector3(1, 1, -1)
	add_child(stage)
	interior = Node3D.new()
	stage.add_child(interior)
	for key in ["body", "lights"]:
		if not add_resource(interior, int(definition[key])):
			return false
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = float(data.camera.fov_units) * 360.0 / 65536.0
	camera.near = float(data.camera.near) * .02
	camera.far = float(data.camera.far) * .02
	# An indoor camera must not inherit the station's outdoor sky.
	camera.environment = Environment.new()
	camera.environment.background_mode = Environment.BG_COLOR
	camera.environment.background_color = Color.BLACK
	camera_x = float(data.camera.x_race if alternate else data.camera.x_default)
	if not refresh_inventory(ship, offers):
		return false
	drift.configure(data.drift, Vector3(camera_x, data.camera.y, data.camera.z_end), hash(library.id + ":hangar:" + str(location)))
	supported = true
	sync_camera()
	camera.current = true
	return true


func refresh_inventory(ship: int, offers: Array) -> bool:
	var stock: Array = []
	for offer in offers:
		if offer.kind != "ship" or int(offer.count) <= 0:
			continue
		if int(offer.count) > data.stock_positions.size() - stock.size():
			error = "Supplied Hangar has no positions for this many ships in stock."
			return false
		for index in int(offer.count):
			stock.append(int(offer.id))
	if player_ship == ship and inventory == stock:
		return true
	var replacement := Node3D.new()
	# Build atomically: a failed mesh never leaves a partially refreshed display.
	if not add_ship(replacement, ship, data.player_position):
		replacement.free()
		return false
	for index in stock.size():
		if not add_ship(replacement, stock[index], data.stock_positions[index]):
			replacement.free()
			return false
	if is_instance_valid(hulls):
		hulls.hide()
		hulls.queue_free()
	hulls = replacement
	stage.add_child(hulls)
	player_ship = ship
	inventory = stock
	error = ""
	return true


func add_resource(parent: Node3D, identifier: int) -> bool:
	var resource: Dictionary = library.content.resources.get(str(identifier), {})
	if resource.is_empty():
		error = "Missing supplied Hangar mesh %d." % identifier
		return false
	var model: MeshInstance3D = library.model(str(resource.path).get_file().trim_suffix(".aem"))
	parent.add_child(model)
	if model.mesh == null:
		error = library.error
		return false
	return true


func add_ship(parent: Node3D, ship: int, position_data: Array) -> bool:
	if ship < 0 or ship >= library.ships.size():
		error = "Unsupported Hangar ship index."
		return false
	var actor := int(library.content.tables.buyable_ships[ship])
	if not data.shadows.has(str(actor)):
		error = "Missing supplied Hangar shadow for actor %d." % actor
		return false
	var display := Node3D.new()
	parent.add_child(display)
	display.set_meta("ship_id", ship)
	display.position = Mission.point(position_data)
	display.rotation.y = -float(data.yaw_units) * TAU / 65536.0
	if not add_resource(display, int(library.content.tables.actor_meshes[actor])):
		return false
	var shadow := Node3D.new()
	display.add_child(shadow)
	shadow.position.y = float(data.shadow_y) * .02
	return add_resource(shadow, int(data.shadows[str(actor)]))


static func view_point(value: Array) -> Vector3:
	## Camera coordinates stay in supplied axes; the stage carries the reflection.
	return Vector3(value[0], value[1], value[2]) * .02


func _process(seconds: float) -> void:
	advance(seconds)


func advance(seconds: float) -> void:
	if not supported or not is_visible_in_tree() or not is_finite(seconds) or seconds <= 0:
		return
	var entrance_left := maxf(0, float(data.camera.entrance_seconds) - elapsed)
	elapsed += seconds
	if seconds > entrance_left:
		drift.advance(seconds - entrance_left)
	sync_camera()


func sync_camera() -> void:
	if elapsed >= float(data.camera.entrance_seconds):
		camera.position = view_point(Combat.packed(drift.position))
		camera.fov = float(data.drift.fov_units) * 360.0 / 65536.0
		camera.near = float(data.drift.near) * .02
		camera.far = float(data.drift.far) * .02
		camera.look_at(hulls.get_child(0).global_position, hulls.get_child(0).global_basis.y)
		return
	var progress := clampf(elapsed / float(data.camera.entrance_seconds), 0, 1)
	var eased := (1.0 - cos(PI * progress)) * .5
	camera.position = view_point([
		camera_x, data.camera.y, lerpf(data.camera.z_start, data.camera.z_end, eased)
	])
	# Source view matrices face opposite their third column, already reflected by
	# the reader. Godot then derives screen-right from these two view vectors, and
	# the supplied basis is right-handed, so no further axis reflection applies.
	var forward := view_point(data.camera.forward).normalized()
	var up := view_point(data.camera.up).normalized()
	camera.look_at(camera.global_position + forward, up)
