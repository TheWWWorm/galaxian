extends RefCounted
## Native fare calculation over imported positions, prices and numeric precision.


static func valid(rules: Variant, library) -> bool:
	if (
		not rules is Dictionary
		or not rules.get("bribes") is Dictionary
		or not rules.get("mission_changes") is Dictionary
	):
		return false
	for name in [
		"distance_rate", "quadrant_rate", "coordinate_extent", "space_extent", "distance_resolution"
	]:
		if not number(rules.get(name)) or rules[name] <= 0 or rules[name] > 1000000:
			return false
	for name in [
		"rating_min",
		"rating_max",
		"initial_rating",
		"campaign_race",
		"bribe_decay",
		"explored_goal",
		"opposite_sum"
	]:
		if not integer(rules.get(name)) or absf(rules[name]) > 1000000:
			return false
	if (
		rules.rating_min >= 0
		or rules.rating_max <= 0
		or rules.initial_rating < rules.rating_min
		or rules.initial_rating > rules.rating_max
		or rules.bribe_decay <= 0
		or rules.campaign_race < 0
		or rules.campaign_race >= library.content.map_ui.races.size()
		or rules.explored_goal != library.stations.size()
		or library.quadrants.size() != 4
		or rules.opposite_sum != library.quadrants.size() - 1
	):
		return false
	if (
		not rules.get("pixel_extent") is Array
		or rules.pixel_extent.size() != 2
		or not rules.get("quadrant_weights") is Array
		or rules.quadrant_weights.size() != 3
	):
		return false
	for extent in rules.pixel_extent:
		if not integer(extent) or extent <= 0 or extent > 10000:
			return false
	for weight in rules.quadrant_weights:
		if not number(weight) or weight < 0 or weight > 1000:
			return false
	for factors in [rules.bribes, rules.mission_changes]:
		for race in factors:
			if (
				not str(race).is_valid_int()
				or int(race) < 0
				or int(race) >= library.content.map_ui.races.size()
				or not number(factors[race])
				or absf(factors[race]) > 1000000
			):
				return false
	for delta in rules.mission_changes.values():
		if not integer(delta):
			return false
	return true


static func integer(value: Variant) -> bool:
	return number(value) and value == int(value)


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func single(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func source_position(library, index: int, quantized: bool) -> Vector2:
	var station: Dictionary = library.station_definition(index)
	var rules: Dictionary = library.content.travel
	var grid: Dictionary = library.content.map_ui.grid
	var columns := int(grid.system_columns)
	var quadrant_columns := int(grid.quadrant_columns)
	var local_system := int(station.system) % int(library.systems.size() / library.quadrants.size())
	var cell := Vector2i(
		int(station.quadrant) % quadrant_columns * columns + local_system % columns,
		int(station.quadrant) / quadrant_columns * columns + local_system / columns
	)
	var result := Vector2.ZERO
	for axis in 2:
		var local: float = station.position[axis]
		if quantized:
			var pixels := int(rules.pixel_extent[axis])
			var pixel := int(single(single(local / float(rules.coordinate_extent)) * pixels))
			result[axis] = single(
				float(pixel + cell[axis] * pixels) * single(float(rules.space_extent) / pixels)
			)
		else:
			var system_part := cell[axis] % columns
			var quadrant_part := cell[axis] / columns
			local = single(single(local / float(grid.system_extent)) * float(grid.system_extent))
			result[axis] = single(
				(
					single(local + system_part * float(grid.system_extent))
					+ quadrant_part * float(grid.quadrant_extent)
				)
			)
	return result


static func rounded_distance(squared: float, resolution: float) -> float:
	# Source distance precision is a dyadic interval midpoint, except when an
	# earlier grid point has an exactly matching squared value. Resolve the grid
	# analytically rather than reproducing the source iterative square-root code.
	var grid := resolution * 2
	var lower := floorf(sqrt(squared) / grid) * grid
	if single(lower * lower) == squared and lower > 0:
		return lower
	var upper := lower + grid
	if single(upper * upper) == squared:
		return upper
	return lower + resolution


static func quote(library, origin: int, destination: int, rating: int, explored: int) -> Dictionary:
	if (
		origin < 0
		or origin >= library.stations.size()
		or destination < 0
		or destination >= library.stations.size()
	):
		return {}
	if origin == destination:
		return {"flight": 0, "bribe": 0, "total": 0}
	var rules: Dictionary = library.content.travel
	var from: Dictionary = library.station_definition(origin)
	var to: Dictionary = library.station_definition(destination)
	var delta := (
		source_position(library, origin, false) - source_position(library, destination, true)
	)
	var squared := single(single(delta.x * delta.x) + single(delta.y * delta.y))
	var distance := rounded_distance(squared, float(rules.distance_resolution))
	var separation := (
		0
		if from.quadrant == to.quadrant
		else (2 if from.quadrant + to.quadrant == rules.opposite_sum else 1)
	)
	var flight := (
		int(single(distance * float(rules.distance_rate)))
		+ int(single(float(rules.quadrant_weights[separation]) * float(rules.quadrant_rate)))
	)
	if explored == rules.explored_goal:
		flight = 0
	var bribe := maxi(0, int(single(rating * float(rules.bribes.get(str(to.race), 0)))))
	return {"flight": flight, "bribe": bribe, "total": flight + bribe}


static func after_mission(rules: Dictionary, rating: int, race: int) -> int:
	return clampi(
		rating + int(rules.mission_changes.get(str(race), 0)),
		int(rules.rating_min),
		int(rules.rating_max)
	)


static func after_bribe(rules: Dictionary, rating: int) -> int:
	return int(move_toward(rating, 0, int(rules.bribe_decay)))
