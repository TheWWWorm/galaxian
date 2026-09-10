extends Node3D
## A source station is a tilted parent with a rotating body/light composite.
## Scene owners provide placement, random samples and a clock; no flight updates.
var error := ""
var missing_resources: Array[int] = []
var rotor: Node3D
var turn_ms := 0.0


func configure(library, kind: int, tilt_samples: Vector2i) -> bool:
	var data: Dictionary = library.content.station_models
	if rotor != null or not data.types.has(str(kind)):
		error = "Unknown or already configured station model."
		return false
	if (
		tilt_samples.x < 0
		or tilt_samples.y < 0
		or tilt_samples.x >= data.tilt_bound
		or tilt_samples.y >= data.tilt_bound
	):
		error = "Station tilt samples exceed the imported bounds."
		return false
	var tilt := Node3D.new()
	add_child(tilt)
	# The source uses Rx * Ry * Rz. Reflecting mesh Z negates X/Y angles.
	var unit := TAU / 65536.0
	tilt.basis = (
		Basis(Vector3.RIGHT, -(data.tilt_center - tilt_samples.x) * unit)
		* Basis(Vector3.BACK, (data.tilt_center - tilt_samples.y) * unit)
	)
	rotor = Node3D.new()
	tilt.add_child(rotor)
	turn_ms = float(data.turn_ms)
	var definition: Dictionary = data.types[str(kind)]
	for field in ["body", "lights"]:
		var identifier := int(definition[field])
		var path: String = library.content.resources[str(identifier)].path
		if not FileAccess.file_exists(library.root.path_join(path)):
			missing_resources.append(identifier)
			if field == "body":
				error = "Missing source station body: " + path
				return false
			continue
		var node: MeshInstance3D = library.model(path.get_file().get_basename())
		if node.mesh == null:
			node.free()
			error = library.error
			return false
		node.name = field
		rotor.add_child(node)
	return true


func set_elapsed(milliseconds: float) -> void:
	if rotor != null and is_finite(milliseconds) and milliseconds >= 0:
		rotor.basis = Basis(Vector3.UP, -fposmod(milliseconds, turn_ms) / turn_ms * TAU)


func outer_radius() -> float:
	var body: MeshInstance3D = rotor.get_node("body")
	var bounds := body.mesh.get_aabb()
	var radius := 0.0
	for index in 8:
		radius = maxf(radius, bounds.get_endpoint(index).length())
	return radius


func enable_collision() -> void:
	var body: MeshInstance3D = rotor.get_node("body")
	if body.has_node("Collision"):
		return
	var obstacle := StaticBody3D.new()
	obstacle.name = "Collision"
	obstacle.collision_layer = 1
	obstacle.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = body.mesh.create_trimesh_shape()
	obstacle.add_child(shape)
	body.add_child(obstacle)
