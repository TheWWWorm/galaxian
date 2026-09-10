extends RefCounted
## Native persistent target decisions over a stable opponent roster.
const Combat = preload("res://src/simulation/combat.gd")
const NONE := -2
const MAX_DECISIONS := 1000000000


static func create(decisions: int = 0) -> Dictionary:
	return {"selected": NONE, "held": false, "elapsed": 0.0, "decisions": decisions}


static func valid_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	for key in ["interval", "half_width", "ally_wake_half_width"]:
		if not Combat.number(data.get(key)) or data[key] <= 0 or data[key] > 1000000:
			return false
	for key in [
		"normal_chance",
		"enhanced_chance",
		"chance_out_of",
		"attempts",
		"enhanced_type",
		"enhanced_chapter"
	]:
		if not Combat.integer(data.get(key)) or data[key] < 0 or data[key] > 1000000:
			return false
	return (
		data.chance_out_of > 0
		and data.normal_chance <= data.chance_out_of
		and data.enhanced_chance <= data.chance_out_of
		and data.attempts > 0
		and data.attempts <= 64
	)


static func opponents(candidates: Array, team: String) -> Array:
	# Pilot first, then source actor order. Dead/sleeping slots retain membership.
	var other := "enemy" if team == "ally" else "ally"
	return candidates.filter(func(candidate): return candidate.team == other)


static func eligible(candidate: Dictionary, position: Vector3, data: Dictionary) -> bool:
	var offset: Vector3 = (candidate.position - position).abs()
	return candidate.active and offset[offset.max_axis_index()] <= float(data.half_width)


static func chance(data: Dictionary, definition: Dictionary, state: Dictionary) -> int:
	var enhanced: bool = (
		(state.get("kind") == "campaign" and int(state.chapter) == int(data.enhanced_chapter))
		or (
			state.get("kind") == "contract"
			and int(definition.get("source_mission_type", -1)) == int(data.enhanced_type)
		)
	)
	return int(data.enhanced_chance if enhanced else data.normal_chance)


static func advance(
	value: Dictionary,
	roster: Array,
	position: Vector3,
	seconds: float,
	data: Dictionary,
	probability: int,
	seed_value: int,
	index: int,
	has_route: bool
) -> Dictionary:
	if seconds <= 0 or not is_finite(seconds):
		return {}
	var selected := find_selected(roster, int(value.selected))
	if not selected.is_empty() and not selected.active:
		value.held = false
	value.elapsed += seconds
	var decision := false
	# Keep elapsed remainder at modern frame rates instead of discarding each
	# source update's overshoot. RNG belongs to this actor, not the original VM.
	while value.elapsed + .000000001 >= float(data.interval):
		value.elapsed = maxf(0, value.elapsed - float(data.interval))
		decision = true
		var random := RandomNumberGenerator.new()
		random.seed = (
			seed_value ^ (index * 19349663) ^ (int(value.decisions) * 83492791) ^ 0x54415247
		)
		value.decisions = (int(value.decisions) + 1) % MAX_DECISIONS
		value.selected = int(roster[0].id) if not roster.is_empty() else NONE
		if random.randi_range(0, int(data.chance_out_of) - 1) < probability and roster.size() > 1:
			value.held = false
			for attempt in int(data.attempts):
				var candidate: Dictionary = roster[random.randi_range(0, roster.size() - 1)]
				if eligible(candidate, position, data):
					value.selected = int(candidate.id)
					value.held = true
					break
		selected = find_selected(roster, int(value.selected))
		if selected.is_empty() or not eligible(selected, position, data):
			value.selected = NONE
	if not decision and not value.held:
		value.selected = NONE
		for candidate in roster:
			if eligible(candidate, position, data):
				value.selected = int(candidate.id)
				break
	# The source returns to its route when acquisition fails. With no route it
	# pursues roster slot zero, even outside the box; do not substitute nearest.
	if value.selected == NONE and not has_route and not roster.is_empty():
		value.selected = int(roster[0].id)
	return find_selected(roster, int(value.selected))


static func find_selected(roster: Array, selected: int) -> Dictionary:
	for candidate in roster:
		if int(candidate.id) == selected:
			return candidate
	return {}


static func valid(actor: Dictionary, data: Dictionary, allowed: Array, moving: bool = true) -> bool:
	var value: Variant = actor.get("targeting")
	if not value is Dictionary or not value.get("held") is bool:
		return false
	if (
		not Combat.number(value.get("elapsed"))
		or value.elapsed < 0
		or value.elapsed >= data.interval
	):
		return false
	if (
		not Combat.integer(value.get("decisions"))
		or value.decisions < 0
		or value.decisions >= MAX_DECISIONS
	):
		return false
	if not Combat.integer(value.get("selected")):
		return false
	if not moving:
		return (
			value.selected == NONE
			and not value.held
			and value.elapsed == 0
			and value.decisions == 0
		)
	return int(value.selected) == NONE or allowed.has(int(value.selected))


static func allowed_ids(definition: Dictionary, team: String) -> Array:
	var result: Array = [-1] if team == "enemy" else []
	var other := "enemy" if team == "ally" else "ally"
	var index := 0
	for group in definition.groups:
		for slot in int(group.count):
			if group.get("team", "enemy") == other:
				result.append(index)
			index += 1
	return result


static func migrate(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary:
			return false
		if actor.has("heading"):
			actor.targeting = create()
	return true
