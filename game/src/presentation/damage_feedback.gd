extends RefCounted
## Directional damage cues use source regions and artwork with native projection.
var data := {}
var images: Array[Texture2D] = []
var remaining := PackedFloat32Array([0, 0, 0, 0])


static func valid(value: Variant, library) -> bool:
	var check = preload("res://src/content/survival_content.gd")
	var combat = preload("res://src/simulation/combat.gd")
	if not value is Dictionary or not value.get("images") is Array or value.images.size() != 2:
		return false
	if not value.images.all(func(v): return check.image(v, library)):
		return false
	for key in ["durations_ms", "insets", "masks", "flips"]:
		if not check.numbers(value.get(key), 4, 0, 10000):
			return false
	if not value.durations_ms.all(func(v): return v > 0):
		return false
	if (
		not value.masks.all(func(v): return check.integer(v, 1, 255))
		or not value.flips.all(func(v): return check.integer(v, 0, 3))
	):
		return false
	var front = value.get("front")
	var rear = value.get("rear")
	if not front is Dictionary or not rear is Dictionary:
		return false
	if (
		not check.numbers(front.get("sides"), 2, -10000, 10000)
		or front.sides[0] >= 0
		or front.sides[1] <= 0
	):
		return false
	if (
		not check.integer(front.get("center"), 0, 240)
		or not check.integer(front.get("flags"), 1, 255)
		or not check.integer(front.get("center_flags"), 1, 255)
	):
		return false
	if (
		not rear.get("limits") is Array
		or rear.limits.size() != 4
		or not rear.limits.all(func(v): return combat.number(v) and v >= -1 and v <= 1)
		or not check.numbers(rear.get("flags"), 5, 1, 255)
	):
		return false
	for i in range(1, 4):
		if rear.limits[i] <= rear.limits[i - 1]:
			return false
	return rear.flags.all(func(v): return check.integer(v, 1, 255))


func configure(library) -> void:
	data = library.content.flight_ui.damage
	images.clear()
	for binding in data.images:
		images.append(library.ui_image(binding))


func flags(camera: Camera3D, incoming: Vector3) -> int:
	if not incoming.is_finite() or incoming.is_zero_approx():
		# Collisions without a meaningful attacker direction get a general cue.
		return int(data.front.center_flags)
	var direction := incoming.normalized()
	var local := camera.global_basis.inverse() * direction
	if local.z >= 0:
		return rear_flags(local.x)
	var position := camera.unproject_position(camera.global_position + direction * camera.far * .5)
	var viewport := camera.get_viewport().get_visible_rect().size
	if viewport.x <= 0 or viewport.y <= 0:
		return 0
	var offset := (position / viewport - Vector2.ONE * .5) * Vector2(480, 320)
	return front_flags(offset)


func front_flags(offset: Vector2) -> int:
	if absf(offset.x) < data.front.center and absf(offset.y) < data.front.center:
		return int(data.front.center_flags)
	var result := int(data.front.flags)
	if offset.x < data.front.sides[0]:
		result |= int(data.masks[0])
	elif offset.x > data.front.sides[1]:
		result |= int(data.masks[1])
	return result


func rear_flags(x: float) -> int:
	for index in data.rear.limits.size():
		if x < data.rear.limits[index]:
			return int(data.rear.flags[index])
	return int(data.rear.flags[-1])


func hit(camera: Camera3D, incoming: Vector3) -> void:
	var edges := flags(camera, incoming)
	for index in remaining.size():
		if edges & int(data.masks[index]):
			remaining[index] = float(data.durations_ms[index])


func advance(milliseconds: float) -> void:
	if not is_finite(milliseconds) or milliseconds <= 0:
		return
	for index in remaining.size():
		remaining[index] = maxf(0, remaining[index] - milliseconds)


func draw(canvas: Control, extent: Vector2) -> void:
	for index in remaining.size():
		if remaining[index] <= 0:
			continue
		var texture := images[0 if index < 2 else 1]
		var dimensions := texture.get_size()
		var inset: float = data.insets[index]
		var position := Vector2.ZERO
		match index:
			0:
				position = Vector2(inset, (extent.y - dimensions.y) * .5)
			1:
				position = Vector2(extent.x - inset - dimensions.x, (extent.y - dimensions.y) * .5)
			2:
				position = Vector2((extent.x - dimensions.x) * .5, inset)
			3:
				position = Vector2((extent.x - dimensions.x) * .5, extent.y - inset - dimensions.y)
		var flip := int(data.flips[index])
		if flip & 1:
			dimensions.x = -dimensions.x
		if flip & 2:
			dimensions.y = -dimensions.y
		canvas.draw_texture_rect(
			texture,
			Rect2(position, dimensions),
			false,
			Color(1, 1, 1, clampf(remaining[index] / data.durations_ms[index], 0, 1))
		)
