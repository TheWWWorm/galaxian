extends RefCounted
## Saved lateral avoidance decisions, independent of visuals and combat RNG.
const Combat = preload("res://src/simulation/combat.gd")
const MAX_DECISIONS := 1000000000


static func create() -> Dictionary:
	return {"direction": [0.0, 0.0, 0.0], "decisions": 0}


static func reset(actor: Dictionary) -> void:
	actor.breaking = false
	if actor.has("evasion"):
		actor.evasion.direction = [0.0, 0.0, 0.0]


static func suspend(actor: Dictionary) -> void:
	# Route following skips avoidance in the source but does not discard its
	# previous direction. A subsequent target outside the box resets the choice.
	actor.breaking = false


static func half_width(
	data: Dictionary, steering: Dictionary, group: Dictionary, state: Dictionary
) -> float:
	if (
		state.get("kind") == "campaign"
		and (
			int(state.chapter) == int(steering.enhanced_chapter)
			or (
				int(state.chapter) == int(steering.special_chapter)
				and int(group.actor) == int(steering.special_actor)
			)
		)
	):
		return float(data.special_half_width)
	if int(group.actor) == int(steering.enhanced_actor):
		return float(data.heavy_half_width)
	return float(group.motion.avoid_distance)


static func desired(
	actor: Dictionary, offset: Vector3, width: float, choices: Array, seed_value: int, index: int
) -> Vector3:
	var extent := offset.abs()
	if extent[extent.max_axis_index()] >= width:
		reset(actor)
		return offset
	if Combat.vector(actor.evasion.direction) == Vector3.ZERO:
		var random := RandomNumberGenerator.new()
		random.seed = seed_value ^ (index * 7919) ^ (int(actor.evasion.decisions) * 104729)
		var local := Combat.vector(choices[random.randi_range(0, choices.size() - 1)])
		var forward := Combat.vector(actor.heading)
		var basis := preload("res://src/simulation/fighter_frame.gd").axes(
			forward, Combat.vector(actor.get("up", [0, 0, 0]))
		)
		actor.evasion.direction = Combat.packed((basis * local).normalized())
		actor.evasion.decisions = (int(actor.evasion.decisions) + 1) % MAX_DECISIONS
	actor.breaking = true
	return Combat.vector(actor.evasion.direction)


static func valid(actor: Dictionary, moving: bool = true) -> bool:
	var value: Variant = actor.get("evasion")
	if not value is Dictionary or not Combat.valid_vector(value.get("direction")):
		return false
	if (
		not Combat.integer(value.get("decisions"))
		or value.decisions < 0
		or value.decisions >= MAX_DECISIONS
	):
		return false
	var direction := Combat.vector(value.direction)
	if actor.get("breaking") == true:
		return moving and is_equal_approx(direction.length(), 1.0)
	return (
		actor.get("breaking") == false
		and (direction == Vector3.ZERO or (moving and is_equal_approx(direction.length(), 1.0)))
	)


static func valid_data(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("directions") is Array
		or value.directions.is_empty()
		or value.directions.size() > 64
	):
		return false
	for direction in value.directions:
		if (
			not Combat.valid_vector(direction)
			or not is_equal_approx(Combat.vector(direction).length(), 1.0)
		):
			return false
	for key in ["heavy_half_width", "special_half_width"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	return true


static func migrate(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary:
			return false
		if not actor.has("heading"):
			continue
		if not actor.get("breaking") is bool:
			return false
		# Old reversal flags contain no lateral choice. Start a fresh decision
		# at the next encounter step, preserving position, heading and momentum.
		actor.evasion = create()
		actor.breaking = false
	return true
