extends RefCounted
## Decorative ship declarations sampled independently of campaign state and RNG.
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")


static func valid_data(data: Variant, actor_count: int) -> bool:
	if not data is Dictionary or not data.get("families") is Array or data.families.size() != 4:
		return false
	for family in data.families:
		if (
			not family is Dictionary
			or not Combat.integer(family.get("race"))
			or family.race < -1
			or family.race > 255
			or not family.get("optional") is bool
		):
			return false
		for role in ["local", "freighter", "escort", "carrier"]:
			if (
				not Combat.integer(family.get(role))
				or family[role] < 0
				or family[role] >= actor_count
			):
				return false
	if int(data.families[0].race) != -1:
		return false
	for key in ["local_route", "crossing_route", "player_route"]:
		if (
			not data.get(key) is Array
			or data[key].size() < 2
			or data[key].size() > 64
			or not data[key].all(func(point): return Combat.valid_vector(point))
		):
			return false
	for key in ["longitudinal_start", "longitudinal_end", "player_position", "camera_position"]:
		if not Combat.valid_vector(data.get(key)):
			return false
	if (
		not data.get("lane_choices") is Array
		or data.lane_choices.size() != 2
		or not data.lane_choices.all(
			func(value): return Combat.number(value) and absf(value) <= 1000000
		)
	):
		return false
	for key in [
		"local_min",
		"local_span",
		"chance_out_of",
		"freighter_chance",
		"escort_chance",
		"carrier_chance",
		"double_freighter_chance"
	]:
		if not Combat.integer(data.get(key)) or data[key] < 0 or data[key] > 10000:
			return false
	if (
		data.local_min < 1
		or data.local_span < 1
		or data.local_min + data.local_span > 64
		or data.chance_out_of < 1
	):
		return false
	for key in ["freighter_chance", "escort_chance", "carrier_chance", "double_freighter_chance"]:
		if data[key] > data.chance_out_of:
			return false
	for key in ["fov_units", "near", "far"]:
		if not Combat.number(data.get(key)) or data[key] <= 0 or data[key] > 100000000:
			return false
	return (
		data.near < data.far
		and data.fov_units < 32768
		and Combat.integer(data.get("route_start"))
		and data.route_start == 0
		and Combat.number(data.get("waypoint_half_width"))
		and data.waypoint_half_width > 0
		and data.waypoint_half_width < 10000
		and Combat.number(data.get("trail_seconds"))
		and data.trail_seconds > 0
		and data.trail_seconds <= 10
		and data.get("local_trail") is Dictionary
		and Combat.integer(data.local_trail.get("style"))
		and data.local_trail.style >= 1
		and Combat.integer(data.local_trail.get("segments"))
		and data.local_trail.segments >= 1
		and data.local_trail.segments <= 4096
		and Combat.valid_vector(data.get("orbital_position"))
		and Combat.number(data.get("orbital_scale"))
		and data.orbital_scale > 0
		and data.orbital_scale <= 64
		and data.get("title_mode") == 4
		and data.get("planet_mode") == 4
		and data.get("orbital_mode") == 3
	)


static func sample(data: Dictionary, race: int, player_actor: int, seed_value: int) -> Array:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var family: Dictionary = data.families[0]
	for candidate in data.families:
		if int(candidate.race) == race:
			family = candidate
	var local_count := int(data.local_min) + random.randi_range(0, int(data.local_span) - 1)
	var freighters := 1 if roll(random, data, "freighter_chance") else 0
	var escorts := 0
	var carriers := 0
	if roll(random, data, "escort_chance"):
		escorts = 1
		carriers = 1 if roll(random, data, "carrier_chance") else 0
	elif freighters == 1 and roll(random, data, "double_freighter_chance"):
		freighters = 2
	if not family.optional:
		escorts = 0
		carriers = 0
	var lane: float = data.lane_choices[random.randi_range(0, data.lane_choices.size() - 1)]
	var start: Array = data.longitudinal_start.duplicate()
	var end: Array = data.longitudinal_end.duplicate()
	start[0] = lane
	end[0] = lane
	var longitudinal: Array = [start, end]
	var result: Array = []
	for index in local_count:
		var point := random.randi_range(0, data.local_route.size() - 2)
		var ship := declaration(int(family.local), data.local_route, point, false, true, "local")
		# Route.clone copies points/loop, but initializes its cursor independently.
		ship.waypoint = int(data.route_start)
		ship.heading = Combat.packed(
			(
				(
					Mission.point(data.local_route[point + 1])
					- Mission.point(data.local_route[point])
				)
				. normalized()
			)
		)
		result.append(ship)
	for index in freighters:
		var route: Array = longitudinal if freighters == 2 and index == 1 else data.crossing_route
		var point := 0 if result.size() % 2 == 1 else random.randi_range(0, route.size() - 1)
		result.append(declaration(int(family.freighter), route, point, true, true, "freighter"))
	for index in escorts:
		var point := 0 if result.size() % 2 == 1 else random.randi_range(0, longitudinal.size() - 1)
		result.append(declaration(int(family.escort), longitudinal, point, true, true, "escort"))
	for index in carriers:
		result.append(declaration(int(family.carrier), longitudinal, 0, true, true, "carrier"))
	if player_actor >= 0:
		var ship := declaration(player_actor, data.player_route, 0, true, false, "player")
		ship.position = Combat.packed(Mission.point(data.player_position))
		result.append(ship)
	return result


static func roll(random: RandomNumberGenerator, data: Dictionary, key: String) -> bool:
	return random.randi_range(0, int(data.chance_out_of) - 1) < int(data[key])


static func declaration(
	actor: int, route: Array, waypoint: int, locked: bool, loop: bool, role: String
) -> Dictionary:
	return {
		"actor": actor,
		"role": role,
		"route": route.duplicate(true),
		"waypoint": waypoint,
		"position": Combat.packed(Mission.point(route[waypoint])),
		"heading": [0.0, 0.0, -1.0],
		"rotation_locked": locked,
		"loop": loop,
		"trail": not locked
	}
