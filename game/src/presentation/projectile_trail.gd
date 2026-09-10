extends MeshInstance3D
## Native ribbon geometry over simulation samples. Source data supplies the atlas
## region, color, width and history capacity; rendering never advances history.
var points := PackedVector3Array()
var segments := 0
var half_width := 0.0
var uv_bounds := Vector4.ZERO
var tint := Color.WHITE
var ribbon := ArrayMesh.new()


static func valid(value: Variant, library) -> bool:
	if not value is Dictionary or not value.get("styles") is Dictionary:
		return false
	var combat = preload("res://src/simulation/combat.gd")
	if (
		not combat.integer(value.get("material"))
		or not library.content.materials.has(str(int(value.material)))
	):
		return false
	if (
		not combat.number(value.get("half_width"))
		or value.half_width <= 0
		or value.half_width > 10000
	):
		return false
	for key in value.styles:
		var style: Variant = value.styles[key]
		if not key is String or str(int(key)) != key or not style is Dictionary:
			return false
		if not combat.integer(style.get("color")) or style.color < 0 or style.color > 4294967295:
			return false
		if (
			not style.get("uv") is Array
			or style.uv.size() != 4
			or not style.uv.all(func(v): return combat.number(v) and v >= 0 and v <= 1)
		):
			return false
		if style.uv[0] >= style.uv[2] or style.uv[1] >= style.uv[3]:
			return false
	return valid_references(library.content, value.styles)


static func valid_references(value: Variant, styles: Dictionary) -> bool:
	var combat = preload("res://src/simulation/combat.gd")
	if value is Dictionary:
		if value.has("trail"):
			var trail: Variant = value.trail
			if (
				not trail is Dictionary
				or not combat.integer(trail.get("style"))
				or not styles.has(str(int(trail.style)))
				or not combat.integer(trail.get("segments"))
				or trail.segments < 1
				or trail.segments > 4096
			):
				return false
		for child in value.values():
			if not valid_references(child, styles):
				return false
	elif value is Array:
		for child in value:
			if not valid_references(child, styles):
				return false
	return true


func configure(library, declaration: Dictionary, origin: Vector3) -> void:
	var source: Dictionary = library.content.projectile_trails
	var style: Dictionary = source.styles[str(int(declaration.style))]
	segments = int(declaration.segments)
	half_width = float(source.half_width)
	uv_bounds = Vector4(style.uv[0], style.uv[1], style.uv[2], style.uv[3])
	tint = Color.hex(int(style.color))
	material_override = library.material(int(source.material))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh = ribbon
	position = origin
	points.resize(segments + 1)
	points.fill(origin)
	visible = false


func advance(head: Vector3) -> void:
	if not head.is_finite() or segments < 1:
		return
	# World-space history must not rotate with a pursuing projectile or camera.
	for index in range(points.size() - 1, 0, -1):
		points[index] = points[index - 1]
	points[0] = head
	position = head
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for index in points.size():
		var center := points[index] - head
		vertices.append(center - Vector3.RIGHT * half_width)
		vertices.append(center + Vector3.RIGHT * half_width)
		var v := lerpf(uv_bounds.y, uv_bounds.w, float(index) / float(segments + 1))
		uvs.append(Vector2(uv_bounds.x, v))
		uvs.append(Vector2(uv_bounds.z, v))
		colors.append(tint)
		colors.append(tint)
		if index < segments:
			var first := index * 2
			indices.append_array(
				PackedInt32Array([first, first + 1, first + 2, first + 1, first + 3, first + 2])
			)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	ribbon.clear_surfaces()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	visible = not points[0].is_equal_approx(points[points.size() - 1])
