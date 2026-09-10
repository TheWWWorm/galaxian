extends RefCounted
## Persistent native visits use the imported station-approach field declaration.
const Combat = preload("res://src/simulation/combat.gd")
const Scenery = preload("res://src/simulation/scenery.gd")


static func definition(library) -> Dictionary:
	return {"scenery": [library.content.briefing_scene.field]}


static func create(library, station_id: int) -> Dictionary:
	var random := RandomNumberGenerator.new()
	# Retain the existing exploration layout without sharing a combat RNG stream.
	random.seed = station_id * 7381 + 271
	var bound := int(library.content.station_models.tilt_bound)
	var tilt := [random.randi_range(0, bound - 1), random.randi_range(0, bound - 1)]
	return {"tilt": tilt, "scenery": sample(library.content.briefing_scene.field, random)}


static func sample(field: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var rocks := []
	var lower := -int(field.width) / 2
	for index in int(field.count):
		var position := (
			(
				Combat.vector(field.center)
				+ Vector3(
					random.randi_range(lower, lower + int(field.width) - 1),
					random.randi_range(lower, lower + int(field.width) - 1),
					random.randi_range(lower, lower + int(field.width) - 1)
				)
			)
			* Vector3(1, 1, -1)
			* .02
		)
		var angles := (
			Vector3(
				random.randi_range(0, int(field.rotation_bound) - 1),
				random.randi_range(0, int(field.rotation_bound) - 1),
				random.randi_range(0, int(field.rotation_bound) - 1)
			)
			* Vector3(-1, -1, 1)
			* TAU
			/ 65536.0
		)
		rocks.append(
			{
				"field": 0,
				"position": Combat.packed(position),
				"rotation": Combat.packed(angles),
				"scale": random.randf_range(float(field.scale_min), float(field.scale_max)),
				"hits": int(field.hits),
				"destruction_ms": 0.0,
				"destroyed": false
			}
		)
	return {"rocks": rocks, "contact_cooldown": 0.0}


static func valid(library, value: Variant) -> bool:
	if not value is Dictionary or value.size() > library.stations.size():
		return false
	for key in value:
		if (
			not key is String
			or not key.is_valid_int()
			or str(int(key)) != key
			or int(key) < 0
			or int(key) >= library.stations.size()
		):
			return false
		var area = value[key]
		if not area is Dictionary or not area.get("tilt") is Array or area.tilt.size() != 2:
			return false
		if not Scenery.valid(definition(library), area.get("scenery")):
			return false
		var expected := create(library, int(key))
		for index in 2:
			if not Combat.integer(area.tilt[index]) or area.tilt[index] != expected.tilt[index]:
				return false
		for index in expected.scenery.rocks.size():
			var saved: Dictionary = area.scenery.rocks[index]
			var original: Dictionary = expected.scenery.rocks[index]
			if (
				not Combat.vector(saved.position).is_equal_approx(Combat.vector(original.position))
				or not Combat.vector(saved.rotation).is_equal_approx(
					Combat.vector(original.rotation)
				)
				or not is_equal_approx(saved.scale, original.scale)
			):
				return false
	return true
