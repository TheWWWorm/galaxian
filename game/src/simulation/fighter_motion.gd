extends RefCounted
## Native speed timelines over imported fighter constants; no original code runs.
const Combat = preload("res://src/simulation/combat.gd")
const MAX_DECISIONS := 1000000000


static func create(data: Dictionary, hull: float = 0.0) -> Dictionary:
	return {
		"speed": float(data.initial_speed),
		"hull_seen": hull,
		"phase": "idle",
		"elapsed": 0.0,
		"duration": 0.0,
		"decisions": 0,
		"damage": 0.0,
		"forced": false
	}


static func damage(state: Dictionary, amount: float, maximum_hull: float, data: Dictionary) -> void:
	if amount <= 0 or maximum_hull <= 0 or not is_finite(amount) or not is_finite(maximum_hull):
		return
	state.damage += amount
	if state.damage / maximum_hull > data.damage_fraction:
		state.damage = 0.0
		state.forced = true
		state.elapsed = maxf(state.elapsed, data.forced_elapsed)


static func begin_boost(state: Dictionary, data: Dictionary, seed_value: int, actor: int) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = seed_value ^ (actor * 7919) ^ (int(state.decisions) * 104729)
	# The source roll refreshes duration. It does not gate acceleration itself;
	# a failed roll retains the previous duration, initially zero.
	if state.forced or random.randi_range(0, int(data.chance_out_of) - 1) < data.duration_chance:
		state.duration = (
			float(data.duration_min_ms + random.randi_range(0, int(data.duration_choices_ms) - 1))
			/ 1000.0
		)
	state.decisions = (int(state.decisions) + 1) % MAX_DECISIONS
	state.phase = "boost"
	state.elapsed = 0.0
	state.forced = false


static func advance(
	state: Dictionary, data: Dictionary, seconds: float, seed_value: int, actor: int
) -> float:
	if seconds <= 0 or not is_finite(seconds):
		return 0.0
	var remaining := seconds
	var distance := 0.0
	while remaining > 0.000000001:
		if state.forced and state.speed >= data.decision_speed_below:
			state.phase = "brake"
			state.elapsed = 0.0
			state.forced = false
		if (
			state.elapsed + .000000001 >= data.decision_seconds
			and state.speed < data.decision_speed_below
		):
			begin_boost(state, data, seed_value, actor)
		if state.phase == "boost":
			# A zero-duration source boost has one update of acceleration before
			# braking. Use its nominal timer interval, not the modern frame length.
			var end := maxf(state.duration, data.reference_seconds)
			if state.elapsed + .000000001 >= end:
				state.phase = "brake"
				state.elapsed = 0.0
				state.forced = false
				continue
			var duration := minf(remaining, end - state.elapsed)
			distance += integrate_linear(state, duration, data.acceleration, data.boost_speed)
			state.elapsed += duration
			remaining -= duration
		elif state.phase == "brake":
			if state.speed <= data.cruise_speed:
				state.speed = float(data.cruise_speed)
				state.phase = "idle"
				continue
			var duration := minf(remaining, (state.speed - data.cruise_speed) / data.braking)
			duration = minf(duration, maxf(0.0, data.decision_seconds - state.elapsed))
			distance += integrate_linear(state, duration, -data.braking, data.cruise_speed)
			state.elapsed += duration
			remaining -= duration
		else:
			var duration := minf(remaining, maxf(0.0, data.decision_seconds - state.elapsed))
			distance += state.speed * duration
			state.elapsed += duration
			remaining -= duration
	return distance


static func integrate_linear(
	state: Dictionary, seconds: float, acceleration: float, limit: float
) -> float:
	var initial := float(state.speed)
	var to_limit := maxf(0.0, (limit - initial) / acceleration)
	var changing := minf(seconds, to_limit)
	state.speed = limit if seconds >= to_limit else initial + acceleration * changing
	return (
		initial * changing
		+ .5 * acceleration * changing * changing
		+ state.speed * (seconds - changing)
	)


static func proximity(
	current: float, data: Dictionary, profile: Dictionary, near: bool, far: bool, seconds: float
) -> Dictionary:
	if not is_finite(current) or current <= 0 or (near and far):
		return {}
	if seconds <= 0 or not is_finite(seconds):
		return {"speed": current, "distance": 0.0}
	if not near and not far:
		var distance := current * seconds
		return {"speed": current, "distance": distance} if is_finite(distance) else {}
	var rate := (
		log(float(profile.gain if near else data.far_retention)) / float(data.reference_seconds)
	)
	var initial := current if near else maxf(current, profile.floor_speed)
	var duration := seconds
	if far and not near:
		duration = minf(seconds, maxf(0.0, log(float(profile.floor_speed) / initial) / rate))
	var speed := initial * exp(rate * duration)
	if far:
		speed = maxf(speed, profile.floor_speed)
	var distance := (speed - initial) / rate + speed * (seconds - duration)
	# No source upper cap is known. Report an unrepresentable result instead of
	# inventing a balance cap or allowing infinity into actor/save coordinates.
	if not is_finite(speed) or not is_finite(distance):
		return {}
	return {"speed": speed, "distance": distance}


static func valid(state: Variant, data: Dictionary) -> bool:
	if not state is Dictionary or state.get("phase") not in ["idle", "boost", "brake"]:
		return false
	for key in ["speed", "elapsed", "duration", "damage"]:
		if not Combat.number(state.get(key)) or state[key] < 0:
			return false
	return (
		state.speed >= data.cruise_speed
		and state.speed <= data.boost_speed
		and (state.phase != "idle" or state.speed == data.cruise_speed)
		and state.elapsed <= 100000000
		and state.damage <= 100000000
		and (
			state.duration == 0
			or (
				state.duration >= data.duration_min_ms / 1000.0
				and state.duration < (data.duration_min_ms + data.duration_choices_ms) / 1000.0
			)
		)
		and Combat.integer(state.get("decisions"))
		and state.decisions >= 0
		and state.decisions < MAX_DECISIONS
		and state.get("forced") is bool
	)


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in [
		"initial_speed",
		"cruise_speed",
		"boost_speed",
		"decision_speed_below",
		"acceleration",
		"braking",
		"decision_seconds",
		"forced_elapsed",
		"damage_fraction",
		"reference_seconds",
		"far_retention"
	]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if (
		value.initial_speed != value.cruise_speed
		or value.boost_speed <= value.cruise_speed
		or value.decision_speed_below != value.boost_speed
		or value.damage_fraction >= 1
		or value.far_retention >= 1
		or value.reference_seconds > 1
	):
		return false
	for key in ["chance_out_of", "duration_chance", "duration_min_ms", "duration_choices_ms"]:
		if not Combat.integer(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if (
		value.duration_chance > value.chance_out_of
		or not value.get("excluded_actors") is Array
		or value.excluded_actors.size() > 64
	):
		return false
	for actor in value.excluded_actors:
		if not Combat.integer(actor) or actor < 0 or actor > 1000000:
			return false
	for key in ["heavy", "special"]:
		var profile: Variant = value.get(key)
		if not profile is Dictionary:
			return false
		for field in ["gain", "far_width", "floor_speed"]:
			if (
				not Combat.number(profile.get(field))
				or profile[field] <= 0
				or profile[field] > 1000000
			):
				return false
		if profile.gain <= 1:
			return false
	return true


static func moving(group: Dictionary) -> bool:
	return group.get("behavior") in ["interceptor", "escort", "wingmate"]


static func mode(
	data: Dictionary, steering: Dictionary, group: Dictionary, job: Dictionary
) -> String:
	if (
		job.get("kind") == "campaign"
		and (
			int(job.chapter) == int(steering.enhanced_chapter)
			or (
				int(job.chapter) == int(steering.special_chapter)
				and int(group.actor) == int(steering.special_actor)
			)
		)
	):
		return "special"
	if int(group.actor) == int(steering.enhanced_actor):
		return "heavy"
	if group.get("team", "enemy") == "enemy":
		# JSON numbers may be floats; Array.has also compares Variant types.
		for excluded in data.excluded_actors:
			if int(excluded) == int(group.actor):
				return "fixed"
		return "boost"
	return "fixed"


static func step_actor(
	actor: Dictionary,
	group: Dictionary,
	job: Dictionary,
	library,
	seconds: float,
	index: int,
	offset: Vector3,
	targeting: bool,
	maximum_hull: float = -1.0
) -> float:
	var data: Dictionary = library.content.fighter_motion
	var state: Dictionary = actor.fighter_motion
	var kind := mode(data, library.content.fighter_steering, group, job)
	if kind == "boost":
		if actor.hp < state.hull_seen:
			damage(
				state,
				state.hull_seen - actor.hp,
				(
					library.group_initial_hull(group, int(job.rank))
					if maximum_hull < 0
					else maximum_hull
				),
				data
			)
			state.hull_seen = float(actor.hp)
		return advance(state, data, seconds, int(job.seed), index)
	if kind == "fixed" or not targeting:
		return state.speed * seconds
	var width: float = preload("res://src/simulation/fighter_evasion.gd").half_width(
		library.content.fighter_evasion, library.content.fighter_steering, group, job
	)
	var extent := maxf(absf(offset.x), maxf(absf(offset.y), absf(offset.z)))
	var result := proximity(
		state.speed, data, data[kind], extent < width, extent >= data[kind].far_width, seconds
	)
	if result.is_empty() or result.speed > 1e8:
		push_error("Fighter proximity motion exceeds the native coordinate range.")
		return 0.0
	state.speed = float(result.speed)
	return float(result.distance)


static func wait_actor(
	actor: Dictionary, group: Dictionary, job: Dictionary, library, seconds: float
) -> void:
	if (
		mode(library.content.fighter_motion, library.content.fighter_steering, group, job)
		== "boost"
	):
		actor.fighter_motion.elapsed += seconds


static func valid_actor(actor: Dictionary, group: Dictionary, job: Dictionary, library) -> bool:
	if not moving(group):
		return not actor.has("fighter_motion")
	var state: Variant = actor.get("fighter_motion")
	if (
		not state is Dictionary
		or not Combat.number(state.get("hull_seen"))
		or state.hull_seen < 0
		or state.hull_seen > 1e8
	):
		return false
	var data: Dictionary = library.content.fighter_motion
	var kind := mode(data, library.content.fighter_steering, group, job)
	if kind == "boost":
		return valid(state, data)
	var normalized: Dictionary = state.duplicate()
	normalized.speed = float(data.cruise_speed)
	if (
		not valid(normalized, data)
		or normalized.phase != "idle"
		or normalized.elapsed != 0
		or normalized.damage != 0
		or normalized.forced
		or normalized.duration != 0
		or normalized.decisions != 0
	):
		return false
	if not Combat.number(state.get("speed")):
		return false
	if kind == "fixed":
		return state.speed == data.initial_speed
	return state.speed >= minf(data.initial_speed, data[kind].floor_speed) and state.speed <= 1e8


static func speed_limit(
	actor: Dictionary, group: Dictionary, job: Dictionary, library, legacy_limit: float
) -> float:
	if not moving(group):
		return legacy_limit
	var data: Dictionary = library.content.fighter_motion
	var kind := mode(data, library.content.fighter_steering, group, job)
	# A dying legacy actor may still carry its pre-migration nominal velocity.
	return maxf(
		legacy_limit,
		(
			float(actor.fighter_motion.speed)
			if kind in ["heavy", "special"]
			else float(data.boost_speed if kind == "boost" else data.initial_speed)
		)
	)


static func migrate(actors: Variant, data: Dictionary, groups: Array = []) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary or not Combat.number(actor.get("hp")) or actor.hp < 0:
			return false
		var applies: bool = actor.has("heading")
		if not groups.is_empty():
			if (
				not Combat.integer(actor.get("group"))
				or actor.group < 0
				or actor.group >= groups.size()
			):
				return false
			applies = moving(groups[int(actor.group)])
		if applies:
			actor.fighter_motion = create(data, float(actor.hp))
		else:
			actor.erase("fighter_motion")
	return true
