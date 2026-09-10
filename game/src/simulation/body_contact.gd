extends RefCounted
## Point-against-body sweeps use the original fixed-object collision volumes.
const Combat = preload("res://src/simulation/combat.gd")
const CLEARANCE := .0001


static func valid_parameters(value: Variant) -> bool:
	return (
		value is Dictionary
		and Combat.integer(value.get("damage")) and value.damage > 0 and value.damage <= 100000
		and Combat.number(value.get("interval")) and value.interval > 0 and value.interval <= 60
		and Combat.number(value.get("forward_keep")) and value.forward_keep >= 0 and value.forward_keep <= 1
	)


static func bodies(definition: Dictionary, state: Dictionary, previous: Dictionary = {}) -> Array:
	var result := []
	for index in state.get("actors", []).size():
		var actor: Dictionary = state.actors[index]
		var group: Dictionary = definition.groups[int(actor.group)]
		if actor.get("destruction", {}).get("phase", "alive") == "dead":
			continue
		if group.get("after_route", false) and int(state.stage) != definition.route.size():
			continue
		# Explicit fixed-body boxes are distinct from fighter projectile extents.
		# Combat activation and sleep do not remove these physical bodies.
		var boxes: Array = group.get("collisions", [group.collision] if group.has("collision") else [])
		for box in boxes:
			var offset := Combat.vector(box.offset) * Vector3(.02, .02, -.02)
			result.append({
				"actor": index,
				"center": Combat.vector(actor.position) + offset,
				"previous": Combat.vector(previous.get(index, actor.position)) + offset,
				"extent": Combat.vector(box.size).abs() * .01
			})
	return result


static func sweep(start: Vector3, end: Vector3, extent: Vector3) -> Dictionary:
	var delta := end - start
	var fraction := Combat.box_intersection(start, end, Vector3.ZERO, extent)
	if fraction < 0:
		return {}
	var point := start.lerp(end, fraction)
	var normal := Vector3.ZERO
	# Closest face also resolves a restored player already inside a body.
	var distance := INF
	for axis in 3:
		var gap := absf(extent[axis] - absf(point[axis]))
		if gap < distance:
			distance = gap
			normal = Vector3.ZERO
			normal[axis] = signf(point[axis]) if point[axis] != 0 else (-signf(delta[axis]) if delta[axis] != 0 else 1.0)
	var inside := start.abs().x < extent.x and start.abs().y < extent.y and start.abs().z < extent.z
	if not inside and fraction <= .000001 and delta.dot(normal) >= 0:
		return {}
	for axis in 3:
		if normal[axis] != 0:
			point[axis] = normal[axis] * (extent[axis] + CLEARANCE)
	return {"fraction": fraction, "normal": normal, "point": point}


static func advance(motion: Dictionary, rules: Dictionary, seconds: float, start: Vector3, end: Vector3, colliders: Array) -> Dictionary:
	var result := {"position": end, "damage": 0, "actor": -1, "normal": Vector3.ZERO}
	if seconds <= 0 or not is_finite(seconds):
		return result
	motion.contact_elapsed = minf(float(rules.interval), float(motion.contact_elapsed) + seconds)
	var cursor := start
	var destination := end
	var elapsed := 0.0
	# Bound pathological overlapping geometry without permitting tunnelling.
	for iteration in 8:
		var nearest := {}
		var selected := {}
		for body in colliders:
			var center: Vector3 = body.previous.lerp(body.center, elapsed)
			var hit := sweep(cursor - center, destination - body.center, body.extent)
			if not hit.is_empty() and (nearest.is_empty() or hit.fraction < nearest.fraction):
				nearest = hit
				selected = body
		if nearest.is_empty():
			result.position = destination
			return result
		var fraction: float = nearest.fraction
		var center: Vector3 = selected.previous.lerp(selected.center, elapsed)
		var displacement: Vector3 = selected.center - center
		var relative_remaining := (destination - cursor - displacement) * (1.0 - fraction)
		cursor = center.lerp(selected.center, fraction) + nearest.point
		destination = cursor + displacement * (1.0 - fraction)
		if relative_remaining.dot(nearest.normal) < 0:
			destination += relative_remaining.bounce(nearest.normal) + relative_remaining * float(rules.forward_keep)
		else:
			destination += relative_remaining
		elapsed += (1.0 - elapsed) * fraction
		result.actor = selected.actor
		result.normal = nearest.normal
		result.position = cursor
		if motion.contact_elapsed >= rules.interval:
			result.damage = int(rules.damage)
			motion.contact_elapsed = 0.0
	return result
