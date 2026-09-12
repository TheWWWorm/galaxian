extends RefCounted
const Guidance = preload("res://src/simulation/guidance.gd")
## Independent ballistic simulation. Projectiles are saveable data; scene nodes
## only visualize them. Swept box tests prevent tunneling at accelerated time.


static func create() -> Dictionary:
	return {"next_id": 0, "projectiles": [], "cooldowns": {}}


static func vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


static func packed(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func fire(
	state: Dictionary,
	weapon: int,
	origin: Vector3,
	direction: Vector3,
	library,
	enemies: Dictionary = {}
) -> bool:
	var definition: Dictionary = profile(weapon, library, enemies)
	if (
		definition.is_empty()
		or definition.get("legacy_projectile", false)
		or not origin.is_finite()
		or not direction.is_finite()
		or direction.length_squared() < .000001
		or state.projectiles.size() >= 4096
		or float(state.cooldowns.get(weapon, 0)) > 0
	):
		return false
	state.cooldowns[weapon] = definition.interval
	return launch(state, weapon, origin, direction, definition, library, enemies)


static func fire_volley(
	state: Dictionary,
	weapons: Array[int],
	origins: Array[Vector3],
	direction: Vector3,
	library,
	profiles: Dictionary
) -> bool:
	if (
		weapons.is_empty()
		or weapons.size() != origins.size()
		or not direction.is_finite()
		or direction.length_squared() < .000001
	):
		return false
	var first := profile(weapons[0], library, profiles)
	if not first.has("trigger_weapon"):
		return false
	var trigger := int(first.trigger_weapon)
	if not weapons.has(trigger) or float(state.cooldowns.get(trigger, 0)) > 0:
		return false
	for index in weapons.size():
		var gun := profile(weapons[index], library, profiles)
		if gun.get("trigger_weapon", -1) != trigger or not origins[index].is_finite():
			return false
	state.cooldowns[trigger] = profile(trigger, library, profiles).interval
	var fired := false
	for index in weapons.size():
		if launch(
			state,
			weapons[index],
			origins[index],
			direction,
			profile(weapons[index], library, profiles),
			library,
			profiles
		):
			fired = true
	return fired


static func launch(
	state: Dictionary,
	weapon: int,
	origin: Vector3,
	direction: Vector3,
	definition: Dictionary,
	library,
	enemies: Dictionary
) -> bool:
	if state.projectiles.size() >= 4096:
		return false
	# The original slot consumes its firing interval even if the shared Gun has
	# no free projectile. Keep cooldowns per shooter while counting the live pool.
	if definition.has("pool_capacity"):
		var count := 0
		for shot in state.projectiles:
			var other: Dictionary = profile(int(shot.weapon), library, enemies)
			if (
				int(shot.weapon) == weapon
				or (definition.has("pool_id") and other.get("pool_id", -1) == definition.pool_id)
			):
				count += 1
		if count >= int(definition.pool_capacity):
			return false
	state.projectiles.append(
		{
			"id": int(state.next_id),
			"weapon": weapon,
			"position": packed(origin),
			"velocity": packed(direction.normalized() * float(definition.speed)),
			"remaining": definition.lifetime
		}
	)
	state.next_id = int(state.next_id) + 1
	if definition.has("guidance"):
		state.projectiles.back()["guidance"] = Guidance.create()
	return true


static func intersection(start: Vector3, end: Vector3, center: Vector3, radius: float) -> float:
	return box_intersection(start, end, center, Vector3.ONE * radius)


static func box_intersection(
	start: Vector3, end: Vector3, center: Vector3, extent: Vector3
) -> float:
	# The imported collision extent is an axis-aligned half-width. A slab
	# intersection preserves that volume while testing the entire movement.
	var offset := start - center
	var segment := end - start
	var entry := 0.0
	var exit_fraction := 1.0
	for axis in 3:
		if absf(segment[axis]) < .00000001:
			if absf(offset[axis]) > extent[axis]:
				return -1.0
			continue
		var first: float = (-extent[axis] - offset[axis]) / segment[axis]
		var last: float = (extent[axis] - offset[axis]) / segment[axis]
		entry = maxf(entry, minf(first, last))
		exit_fraction = minf(exit_fraction, maxf(first, last))
		if entry > exit_fraction:
			return -1.0
	return entry


static func advance(
	state: Dictionary,
	seconds: float,
	targets: Array,
	library,
	enemies: Dictionary = {},
	guidance_targets: Array = []
) -> Array:
	var hits: Array = []
	if seconds <= 0 or not is_finite(seconds):
		return hits
	for weapon in state.cooldowns.keys():
		var remaining := maxf(0, float(state.cooldowns[weapon]) - seconds)
		if remaining == 0:
			state.cooldowns.erase(weapon)
		else:
			state.cooldowns[weapon] = remaining
	# Cooldowns still had to tick. Nothing below concerns an empty sky, and a
	# field's targets are not worth preparing for no projectiles at all.
	if state.projectiles.is_empty():
		return hits
	# A target's identity, side and swept volume are the same for every
	# projectile tested against it, and an asteroid field supplies eighty of them.
	# Reading them once per advance keeps the sweep itself in the inner loop.
	var count := targets.size()
	var ids := PackedInt32Array()
	var teams := PackedStringArray()
	var centers := PackedVector3Array()
	var origins := PackedVector3Array()
	var extents := PackedVector3Array()
	ids.resize(count)
	teams.resize(count)
	centers.resize(count)
	origins.resize(count)
	extents.resize(count)
	for index in count:
		var target: Dictionary = targets[index]
		var id := int(target.id)
		ids[index] = id
		teams[index] = target.get("team", "ally" if id == -1 else "enemy")
		centers[index] = vector(target.position)
		origins[index] = vector(target.get("previous", target.position))
		extents[index] = (
			vector(target.extent)
			if target.has("extent")
			else Vector3.ONE * float(target.radius)
		)
	var survivors: Array = []
	for shot in state.projectiles:
		var dt := minf(seconds, float(shot.remaining))
		var start := vector(shot.position)
		var end := start + vector(shot.velocity) * dt
		var nearest := 2.0
		var target_id := -2
		var definition: Dictionary = profile(int(shot.weapon), library, enemies)
		# The shooter's own side does not vary across the targets either.
		var shooter_team := team(int(shot.weapon), library, enemies)
		var directed: bool = definition.has("target_ids")
		var fraction_of := dt / seconds
		for index in count:
			# Directed fire restricts characters, not level geometry. The source
			# gun checks its asteroid field after character collision as usual.
			var target_team := teams[index]
			if directed and target_team != "neutral":
				if not definition.target_ids.has(ids[index]):
					continue
			elif shooter_team == target_team:
				continue
			# A moving target is swept in relative coordinates over the same
			# interval, so crossing a projectile between frames still counts.
			var previous := origins[index]
			var fraction := box_intersection(
				start - previous,
				end - previous.lerp(centers[index], fraction_of),
				Vector3.ZERO,
				extents[index]
			)
			if fraction >= 0 and fraction < nearest:
				nearest = fraction
				target_id = ids[index]
		if target_id != -2:
			hits.append(
				{
					"target": target_id,
					"weapon": int(shot.weapon),
					"position": packed(start.lerp(end, nearest)),
					"incoming": packed(-vector(shot.velocity).normalized()),
					"velocity": shot.velocity.duplicate(),
					"damage": profile(int(shot.weapon), library, enemies).damage
				}
			)
			continue
		shot.remaining = maxf(0, float(shot.remaining) - seconds)
		if shot.remaining > 0:
			shot.position = packed(end)
			if definition.has("guidance"):
				Guidance.steer(shot, definition, dt, guidance_targets)
			survivors.append(shot)
	state.projectiles = survivors
	return hits


static func valid(state: Variant, library, enemies: Dictionary = {}) -> bool:
	if (
		not state is Dictionary
		or not state.has_all(["next_id", "projectiles", "cooldowns"])
		or not state.projectiles is Array
		or not state.cooldowns is Dictionary
	):
		return false
	if (
		not integer(state.next_id)
		or state.next_id < 0
		or state.next_id > 9007199254740991
		or state.projectiles.size() > 4096
		or state.cooldowns.size() > library.items.size() + enemies.size()
	):
		return false
	for key in state.cooldowns:
		if not (key is int or key is String) or str(int(key)) != str(key):
			return false
		var definition: Dictionary = profile(int(key), library, enemies)
		if (
			definition.is_empty()
			or definition.get("legacy_projectile", false)
			or int(definition.get("trigger_weapon", int(key))) != int(key)
			or not number(state.cooldowns[key])
			or state.cooldowns[key] < 0
			or state.cooldowns[key] > float(definition.get("cooldown_limit", definition.interval))
		):
			return false
	var seen := {}
	for shot in state.projectiles:
		if (
			not shot is Dictionary
			or not shot.has_all(["id", "weapon", "position", "velocity", "remaining"])
		):
			return false
		if (
			not integer(shot.id)
			or shot.id < 0
			or shot.id >= state.next_id
			or seen.has(int(shot.id))
			or not integer(shot.weapon)
			or not valid_vector(shot.position)
			or not valid_vector(shot.velocity)
			or not number(shot.remaining)
			or shot.remaining <= 0
		):
			return false
		var definition: Dictionary = profile(int(shot.weapon), library, enemies)
		if (
			definition.is_empty()
			or shot.remaining > definition.lifetime
			or not valid_launch_speed(vector(shot.velocity).length(), definition)
		):
			return false
		if definition.has("guidance"):
			var lock: Variant = shot.get("guidance")
			if (
				not lock is Dictionary
				or not integer(lock.get("target"))
				or not valid_vector(lock.get("position", []))
			):
				return false
			if lock.target == -2:
				if vector(lock.position) != Vector3.ZERO:
					return false
			elif not definition.get("guidance_target_ids", []).any(
				func(id): return id == lock.target
			):
				return false
		elif shot.has("guidance"):
			return false
		seen[int(shot.id)] = true
	return true


static func valid_launch_speed(speed: float, definition: Dictionary) -> bool:
	# A promoted Gun keeps the velocity of already launched projectiles. The
	# session reconstructs permitted prior speeds from validated upgrade history.
	for allowed in definition.get("launch_speeds", [definition.speed]):
		if is_equal_approx(speed, float(allowed)):
			return true
	return false


static func normalize(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.next_id = int(result.next_id)
	for shot in result.projectiles:
		shot.id = int(shot.id)
		shot.weapon = int(shot.weapon)
		if shot.has("guidance"):
			shot.guidance.target = int(shot.guidance.target)
	result.cooldowns = {}
	for key in state.cooldowns:
		result.cooldowns[int(key)] = float(state.cooldowns[key])
	return result


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func integer(value: Variant) -> bool:
	return number(value) and value == int(value)


static func valid_vector(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 3
		and value.all(func(axis): return number(axis) and absf(axis) <= 1e8)
	)


static func profile(weapon: int, library, enemies: Dictionary) -> Dictionary:
	# A mode may override fitted player weapons as well as actor weapons. Every
	# ballistic consumer uses the same mapping, leaving shared catalogues intact.
	if enemies.has(weapon):
		return enemies[weapon]
	return {} if weapon < 0 else library.weapon_ballistics(weapon)


static func team(weapon: int, library, actors: Dictionary) -> String:
	return str(profile(weapon, library, actors).get("team", "enemy" if weapon < 0 else "ally"))
