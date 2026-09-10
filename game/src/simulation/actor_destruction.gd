extends RefCounted
## Simulation-owned wreck phases. Combat HP and finished destruction are distinct.
const Combat = preload("res://src/simulation/combat.gd")
const Mines = preload("res://src/simulation/mines.gd")


static func create(alive: bool = true) -> Dictionary:
	return {"phase": "alive" if alive else "dead", "elapsed_ms": 0.0, "velocity": [0.0, 0.0, 0.0]}


static func begin(actor: Dictionary) -> void:
	if actor.has("destruction") and actor.destruction.phase == "alive":
		actor.destruction.phase = "dying"
		actor.destruction.elapsed_ms = 0.0


static func effect(library, actor_type: int) -> Dictionary:
	var data: Dictionary = library.content.actor_destruction
	return data.effects[str(int(data.actors[actor_type]))]


static func brightness(definition: Dictionary, layer: Dictionary, clock_ms: float) -> float:
	return Mines.alpha(
		definition,
		{"delay_ms": layer.delay_ms + layer.fade_delay_ms, "duration_ms": layer.fade_duration_ms},
		clock_ms
	)


static func finished(definition: Dictionary, clock_ms: float) -> bool:
	for layer in definition.layers:
		if (
			clock_ms < layer.delay_ms
			or brightness(definition, layer, clock_ms) > definition.alpha_cutoff
		):
			return false
	return true


static func span(definition: Dictionary) -> float:
	var duration := 0.0
	for layer in definition.layers:
		duration = maxf(duration, layer.delay_ms + layer.fade_delay_ms + layer.fade_duration_ms)
	return duration


static func advance(clock: Dictionary, definition: Dictionary, seconds: float) -> void:
	if clock.phase != "dying" or seconds <= 0 or not is_finite(seconds):
		return
	clock.elapsed_ms += seconds * 1000.0
	if finished(definition, clock.elapsed_ms):
		clock.phase = "dead"
		clock.elapsed_ms = 0.0
		clock.velocity = [0.0, 0.0, 0.0]


static func completion_ms(definition: Dictionary) -> float:
	var fraction := (
		float(definition.alpha_start - definition.alpha_cutoff)
		/ float(definition.alpha_start - definition.alpha_end)
	)
	var progress := acos(clampf(1.0 - 2.0 * fraction, -1.0, 1.0)) / PI
	var end := 0.0
	for layer in definition.layers:
		end = maxf(end, layer.delay_ms + layer.fade_delay_ms + layer.fade_duration_ms * progress)
	return end


static func drift(
	actor: Dictionary, definition: Dictionary, motion: Dictionary, seconds: float
) -> void:
	var clock: Dictionary = actor.destruction
	if clock.phase != "dying" or seconds <= 0 or not is_finite(seconds):
		return
	# Integrate damping analytically; a large step cannot move a finished wreck.
	var duration := minf(
		seconds, maxf(0.0, (completion_ms(definition) - clock.elapsed_ms) / 1000.0)
	)
	var rate := -log(float(motion.retention)) / float(motion.reference_seconds)
	var decay := exp(-rate * duration)
	var velocity := Combat.vector(clock.velocity)
	actor.position = Combat.packed(
		Combat.vector(actor.position) + velocity * ((1.0 - decay) / rate)
	)
	clock.velocity = Combat.packed(velocity * decay)


static func valid_motion(value: Variant) -> bool:
	return (
		value is Dictionary
		and Combat.number(value.get("retention"))
		and value.retention > 0
		and value.retention < 1
		and Combat.number(value.get("reference_seconds"))
		and value.reference_seconds >= .001
		and value.reference_seconds <= 1.0
	)


static func speed_limit(group: Dictionary, sequence: Array = [], actor_index: int = -1) -> float:
	var maximum := 0.0
	if group.get("behavior") == "transit":
		return Combat.vector(group.velocity).length()
	if group.get("behavior") not in ["interceptor", "escort", "wingmate"]:
		return maximum
	maximum = float(group.motion.speed)
	for stage in sequence:
		for action in stage.actions:
			if action.kind == "speed" and int(action.actor) == actor_index:
				maximum = maxf(maximum, float(action.value))
	return maximum


static func valid(
	value: Variant, hp: float, definition: Dictionary, maximum_speed: float = INF
) -> bool:
	if (
		not value is Dictionary
		or not Combat.number(value.get("elapsed_ms"))
		or value.elapsed_ms < 0
		or not Combat.valid_vector(value.get("velocity"))
	):
		return false
	var speed := Combat.vector(value.velocity).length()
	if speed > maximum_speed + .001:
		return false
	match value.get("phase"):
		"alive":
			return hp > 0 and value.elapsed_ms == 0
		"dead":
			return hp == 0 and value.elapsed_ms == 0 and speed == 0
		"dying":
			return hp == 0 and not finished(definition, value.elapsed_ms)
	return false


static func actor_dead(actor: Dictionary) -> bool:
	if actor.has("mine"):
		return Mines.actor_dead(actor)
	return actor.hp <= 0 and actor.get("destruction", {}).get("phase") == "dead"


static func migrate_actors(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary or not Combat.number(actor.get("hp")) or actor.hp < 0:
			return false
		if actor.has("mine"):
			continue
		if actor.has("destruction"):
			# Older preview migrations may already have called today's create().
			continue
		actor.destruction = create(actor.hp > 0)
	return true


static func migrate_motion(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary:
			return false
		if actor.has("mine"):
			continue
		if not actor.get("destruction") is Dictionary:
			return false
		# Old saves recorded no momentum. Preserve their stationary wrecks;
		# living ships acquire their actual velocity on the next movement step.
		if not actor.destruction.has("velocity"):
			actor.destruction.velocity = [0.0, 0.0, 0.0]
	return true
