extends RefCounted
const Mines = preload("res://src/simulation/mines.gd")
const Combat = preload("res://src/simulation/combat.gd")
## Destructible imported field geometry; no scene nodes or original code in state.


static func create(definition: Dictionary, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value ^ 83492791
	var rocks: Array = []
	for index in definition.get("scenery", []).size():
		var field: Dictionary = definition.scenery[index]
		var point: Array = (
			field.center if field.has("center") else definition.route[int(field.waypoint)]
		)
		var center := Vector3(point[0], point[1], -point[2]) * .02
		var lower := -int(field.width) / 2
		var upper := lower + int(field.width) - 1
		for item in int(field.count):
			rocks.append(
				{
					"field": index,
					"position":
					Combat.packed(
						(
							center
							+ (
								Vector3(
									rng.randi_range(lower, upper),
									rng.randi_range(lower, upper),
									-rng.randi_range(lower, upper)
								)
								* .02
							)
						)
					),
					"rotation": [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU],
					"scale": rng.randf_range(float(field.scale_min), float(field.scale_max)),
					"hits": int(field.hits),
					"destruction_ms": 0.0,
					"destroyed": false
				}
			)
	return {"rocks": rocks, "contact_cooldown": 0.0}


static func valid(definition: Dictionary, value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("rocks") is Array
		or not Combat.number(value.get("contact_cooldown"))
		or value.contact_cooldown < 0
	):
		return false
	var count := 0
	var maximum_cooldown := 0.0
	for index in definition.get("scenery", []).size():
		var field: Dictionary = definition.scenery[index]
		maximum_cooldown = maxf(maximum_cooldown, float(field.contact_interval))
		for item in int(field.count):
			if count >= value.rocks.size():
				return false
			var rock: Variant = value.rocks[count]
			count += 1
			if (
				not rock is Dictionary
				or rock.get("field") != index
				or not Combat.valid_vector(rock.get("position", []))
				or not Combat.valid_vector(rock.get("rotation", []))
				or not Combat.number(rock.get("scale"))
				or rock.scale < field.scale_min
				or rock.scale > field.scale_max
				or not Combat.integer(rock.get("hits"))
				or rock.hits < 0
				or rock.hits > field.hits
				or not valid_destruction_state(rock, field)
			):
				return false
	return count == value.rocks.size() and value.contact_cooldown <= maximum_cooldown


static func targets(definition: Dictionary, value: Dictionary, first_id: int) -> Array:
	var result: Array = []
	for index in value.rocks.size():
		var rock: Dictionary = value.rocks[index]
		if rock.hits > 0:
			result.append(
				{
					"id": first_id + index,
					"team": "neutral",
					"position": rock.position,
					"radius": definition.scenery[int(rock.field)].radius
				}
			)
	return result


static func hit(value: Dictionary, index: int, destroy: bool = false) -> void:
	if index < 0 or index >= value.rocks.size():
		return
	var rock: Dictionary = value.rocks[index]
	if rock.hits <= 0:
		return
	rock.hits = 0 if destroy else maxi(0, int(rock.hits) - 1)


static func contact(
	definition: Dictionary, value: Dictionary, start: Vector3, end: Vector3, seconds: float
) -> float:
	if seconds <= 0 or not is_finite(seconds):
		return 0
	value.contact_cooldown = maxf(0, float(value.contact_cooldown) - seconds)
	if value.contact_cooldown > 0:
		return 0
	var nearest := 2.0
	var selected := -1
	for index in value.rocks.size():
		var rock: Dictionary = value.rocks[index]
		if rock.hits <= 0:
			continue
		var fraction := Combat.intersection(
			start,
			end,
			Combat.vector(rock.position),
			float(definition.scenery[int(rock.field)].radius)
		)
		if fraction >= 0 and fraction < nearest:
			selected = index
			nearest = fraction
	if selected < 0:
		return 0
	var field: Dictionary = definition.scenery[int(value.rocks[selected].field)]
	hit(value, selected, true)
	value.contact_cooldown = float(field.contact_interval)
	return float(field.contact_damage)


static func advance(definition: Dictionary, value: Dictionary, seconds: float) -> void:
	if seconds <= 0 or not is_finite(seconds):
		return
	for rock in value.get("rocks", []):
		if rock.hits > 0 or rock.destroyed:
			continue
		rock.destruction_ms += seconds * 1000.0
		var parameters: Dictionary = definition.scenery[int(rock.field)].get("destruction", {})
		if (
			parameters.is_empty()
			or Mines.explosion_finished(parameters.effect, rock.destruction_ms)
		):
			rock.destroyed = true
			rock.destruction_ms = 0.0


static func destroyed(value: Dictionary) -> int:
	return value.get("rocks", []).filter(func(rock): return rock.get("destroyed", false)).size()


static func valid_destruction_state(rock: Dictionary, field: Dictionary) -> bool:
	if (
		not Combat.number(rock.get("destruction_ms"))
		or rock.destruction_ms < 0
		or not rock.get("destroyed") is bool
	):
		return false
	if rock.hits > 0:
		return rock.destruction_ms == 0 and not rock.destroyed
	if rock.destroyed:
		return rock.destruction_ms == 0
	return (
		rock.destruction_ms == 0
		or (
			field.has("destruction")
			and not Mines.explosion_finished(field.destruction.effect, rock.destruction_ms)
		)
	)


static func valid_destruction(value: Variant, resources: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	var effect: Variant = value.get("effect")
	if not effect is Dictionary:
		return false
	for key in ["alpha_start", "alpha_end", "alpha_cutoff"]:
		if not Combat.integer(effect.get(key)) or effect[key] < 0 or effect[key] > 255:
			return false
	if effect.alpha_start <= effect.alpha_cutoff or effect.alpha_end > effect.alpha_cutoff:
		return false
	if not effect.get("layers") is Array or effect.layers.is_empty() or effect.layers.size() > 32:
		return false
	for layer in effect.layers:
		if not layer is Dictionary or not Mines.mesh_id(layer.get("mesh"), resources):
			return false
		for key in ["delay_ms", "duration_ms", "scale"]:
			if not Combat.number(layer.get(key)) or layer[key] < 0 or layer[key] > 1000000:
				return false
		if (
			layer.duration_ms <= 0
			or layer.scale <= 0
			or not Combat.valid_vector(layer.get("rotation", []))
		):
			return false
	if (
		not value.get("fragment_meshes") is Array
		or value.fragment_meshes.size() != 3
		or not value.fragment_meshes.all(func(id): return Mines.mesh_id(id, resources))
		or not Combat.integer(value.get("fragment_duration_ms"))
		or value.fragment_duration_ms <= 0
		or value.fragment_duration_ms > 1000000
		or not value.get("fragment_velocity") is Array
		or value.fragment_velocity.size() != 3
		or not value.fragment_velocity.all(func(velocity): return Combat.valid_vector(velocity))
		or not Combat.valid_vector(value.get("fragment_spin", []))
	):
		return false
	return true
