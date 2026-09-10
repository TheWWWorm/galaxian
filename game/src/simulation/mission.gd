extends RefCounted
const Destruction = preload("res://src/simulation/actor_destruction.gd")
const Frame = preload("res://src/simulation/fighter_frame.gd")
const Targeting = preload("res://src/simulation/fighter_targeting.gd")
const Impact = preload("res://src/simulation/fighter_impact.gd")
const FighterMotion = preload("res://src/simulation/fighter_motion.gd")
const Evasion = preload("res://src/simulation/fighter_evasion.gd")
const Mines = preload("res://src/simulation/mines.gd")
const Radio = preload("res://src/simulation/radio.gd")
const Tutorial = preload("res://src/simulation/tutorial.gd")
const Sequence = preload("res://src/simulation/sequence.gd")
const Scenery = preload("res://src/simulation/scenery.gd")
const SPAWN_POSITION := Vector3(0, 12, 380)
## Native, deterministic mission state. Content declares objectives and encounters;
## this module owns progression, deadlines and persistent damage independently of UI.


static func point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], -value[2]) * .02


static func create(
	definition: Dictionary,
	chapter: int,
	origin: int,
	library,
	seed_value: int,
	rank: int = -1,
	kind: String = "campaign"
) -> Dictionary:
	if rank < 0:
		rank = library.campaign_level(chapter)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var actors: Array = []
	for group_index in definition.groups.size():
		var group: Dictionary = definition.groups[group_index]
		for index in int(group.count):
			var position := point(group.center)
			if group.get("placement") == "waypoints":
				position = point(definition.route[index])
			elif group.get("placement") == "points":
				position = point(group.positions[index])
			elif group.get("placement") == "player_offset":
				position += SPAWN_POSITION
			if not group.scatter.is_empty():
				var displacement: Array = []
				for axis in group.scatter:
					var sampled := rng.randi_range(int(axis[0]), int(axis[1]))
					# Source spawn division truncates toward zero after each roll.
					displacement.append(sampled / int(group.get("scatter_divisor", 1)))
				position += point(displacement)
			elif group.get("placement", "formation") == "formation" and int(group.count) > 1:
				# No invented spacing when a multi-ship declaration lacks positions.
				return {}
			actors.append(
				{
					"group": group_index,
					"hp": library.group_initial_hull(group, rank),
					"awake": not group.get("sleeping", false),
					"position": [position.x, position.y, position.z]
				}
			)
			if int(group.actor) == int(library.content.mine_behavior.actor):
				actors.back().mine = Mines.create()
			else:
				actors.back().destruction = Destruction.create()
			if group.get("behavior") in ["interceptor", "escort", "wingmate", "turret"]:
				actors.back().merge({"heading": [0.0, 0.0, -1.0], "breaking": false, "shots": 0})
				actors.back().evasion = Evasion.create()
				actors.back().impact = Impact.create()
				actors.back().targeting = Targeting.create()
			if FighterMotion.moving(group):
				actors.back().fighter_motion = FighterMotion.create(
					library.content.fighter_motion, float(actors.back().hp)
				)
			if group.get("behavior") == "turret":
				var direction := point(group.facing).normalized()
				actors.back().heading = [direction.x, direction.y, direction.z]
			if actors.back().has("heading"):
				actors.back().up = [0.0, 1.0, 0.0]
				Frame.migrate([actors.back()])
			if group.get("behavior") == "escort":
				actors.back().route_stage = 0
	var target_count := 0
	for actor in actors:
		if enemy(definition, actor):
			target_count += 1
	var state := {
		"kind": kind,
		"seed": seed_value,
		"sequence_cursor": 0,
		"radio": Radio.create(),
		"scenery": Scenery.create(definition, seed_value),
		"chapter": chapter,
		"rank": rank,
		"origin": origin,
		"stage": 0,
		"elapsed_ms": 0.0,
		"actors": actors,
		"kills": 0,
		"target": int(definition.get("enemy_goal", target_count)),
		"ready": false,
		"failed": false
	}
	var tutorial: Dictionary = library.content.flight_ui.tutorial
	if Tutorial.applies(tutorial, state):
		state.tutorial = Tutorial.create(tutorial)
	return state


static func group_active(definition: Dictionary, state: Dictionary, group: int) -> bool:
	return not definition.groups[group].after_route or int(state.stage) == definition.route.size()


static func actor_active(definition: Dictionary, state: Dictionary, actor: Dictionary) -> bool:
	return (
		actor.hp > 0
		and (not actor.has("mine") or Mines.active(actor.mine))
		and definition.groups[int(actor.group)].get("combat_active", true)
		and actor.get("awake", true)
		and group_active(definition, state, int(actor.group))
	)


static func evaluate(
	definition: Dictionary, state: Dictionary, direct_sequence: bool = true
) -> void:
	if state.ready or state.failed:
		return
	if direct_sequence:
		Sequence.advance(definition, state)
	var limit := float(definition.deadline_ms)
	# Deadline has priority when a hit arrives after the time limit.
	if limit > 0 and float(state.elapsed_ms) > limit:
		state.failed = true
		return
	if definition.has("failure") and achieved(definition.failure, definition, state):
		state.failed = true
		return
	state.ready = (
		int(state.get("sequence_cursor", 0)) == definition.get("sequence", []).size()
		and achieved(definition.success, definition, state)
	)


static func enemy(definition: Dictionary, actor: Dictionary) -> bool:
	return definition.groups[int(actor.group)].get("team", "enemy") == "enemy"


static func achieved(condition: Dictionary, definition: Dictionary, state: Dictionary) -> bool:
	match condition.kind:
		"endless":
			return false
		"all":
			return condition.conditions.all(func(item): return achieved(item, definition, state))
		"enemy_prefix_destroyed":
			return destroyed_prefix(definition, state, int(condition.count)) == int(condition.count)
		"enemies_destroyed":
			return int(state.kills) >= int(state.target)
		"message_shown":
			return Sequence.triggered(
				{"kind": "message_shown", "message": condition.message}, state
			)
		"route_finished":
			return int(state.stage) == definition.route.size()
		"time_survived":
			return float(state.elapsed_ms) > float(condition.duration_ms)
		"allies_destroyed":
			var count := 0
			for actor in state.actors:
				if not enemy(definition, actor):
					count += 1
					if float(actor.hp) > 0:
						return false
			return count > 0
		"ally_destroyed", "enemy_destroyed":
			var index := 0
			for actor in state.actors:
				if enemy(definition, actor) == (condition.kind == "enemy_destroyed"):
					if index == int(condition.index):
						return actor_dead(actor)
					index += 1
	return false


static func advance(definition: Dictionary, state: Dictionary, seconds: float, library) -> void:
	if state.ready or state.failed or seconds <= 0 or not is_finite(seconds):
		return
	state.elapsed_ms = float(state.elapsed_ms) + seconds * 1000.0
	Scenery.advance(definition, state.scenery, seconds)
	for actor in state.actors:
		if actor.has("destruction"):
			var effect := Destruction.effect(
				library, int(definition.groups[int(actor.group)].actor)
			)
			Destruction.drift(actor, effect, library.content.actor_destruction.drift, seconds)
			Destruction.advance(actor.destruction, effect, seconds)
	evaluate(definition, state)


static func reach_waypoint(definition: Dictionary, state: Dictionary) -> void:
	if state.ready or state.failed or not route_pending(definition, state):
		return
	state.stage = mini(int(state.stage) + 1, definition.route.size())
	evaluate(definition, state)


static func damage(
	definition: Dictionary, state: Dictionary, actor_index: int, amount: float
) -> bool:
	if (
		state.ready
		or state.failed
		or actor_index < 0
		or actor_index >= state.actors.size()
		or amount <= 0
		or not is_finite(amount)
	):
		return false
	var actor: Dictionary = state.actors[actor_index]
	if not actor_active(definition, state, actor):
		return false
	if actor.has("mine") and actor.mine.phase == "dormant":
		return true
	actor.hp = maxf(0, float(actor.hp) - amount)
	if actor.hp == 0:
		if actor.has("mine"):
			Mines.begin_explosion(actor.mine, true)
		else:
			Destruction.begin(actor)
	if actor.hp == 0 and enemy(definition, actor):
		state.kills = int(state.kills) + 1
	evaluate(definition, state)
	return true


static func integer(value: Variant) -> bool:
	return numeric(value) and value == int(value)


static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func valid(
	definition: Dictionary,
	state: Dictionary,
	chapter: int,
	origin: int,
	library,
	expected_kind: String = "campaign",
	expected_rank: int = -1
) -> bool:
	if not state.has_all(
		[
			"kind",
			"chapter",
			"origin",
			"stage",
			"elapsed_ms",
			"actors",
			"kills",
			"target",
			"ready",
			"failed"
		]
	):
		return false
	if (
		not integer(state.get("rank"))
		or state.rank <= 0
		or (
			state.rank != expected_rank
			if expected_rank >= 0
			else state.rank > int(library.content.initial.level) + chapter
		)
		or state.kind != expected_kind
		or state.chapter != chapter
		or state.origin != origin
		or not state.ready is bool
		or not state.failed is bool
		or not state.actors is Array
	):
		return false
	if (
		not integer(state.stage)
		or state.stage < 0
		or state.stage > definition.route.size()
		or not numeric(state.elapsed_ms)
		or state.elapsed_ms < 0
	):
		return false
	if not Scenery.valid(definition, state.get("scenery", {"rocks": [], "contact_cooldown": 0.0})):
		return false
	if not Radio.valid(state.get("radio"), definition.get("radio", []).size()):
		return false
	if (
		state.has("tutorial")
		and (
			not Tutorial.applies(library.content.flight_ui.tutorial, state)
			or not Tutorial.valid(
				library.content.flight_ui.tutorial, state.tutorial, state.radio.shown
			)
		)
	):
		return false
	if not Sequence.valid(definition, state):
		return false
	var directions := Sequence.directives(definition, state)
	var count := 0
	var kills := 0
	var target_count := 0
	for group_index in definition.groups.size():
		var group: Dictionary = definition.groups[group_index]
		for index in int(group.count):
			if count >= state.actors.size():
				return false
			var actor: Variant = state.actors[count]
			count += 1
			if not actor is Dictionary or not actor.has_all(["group", "hp", "position"]):
				return false
			var maximum: float = Sequence.health_limit(
				definition, state, count - 1, library.group_initial_hull(group, int(state.rank))
			)
			if (
				actor.group != group_index
				or not numeric(actor.hp)
				or actor.hp < 0
				or actor.hp > maximum
				or not actor.position is Array
				or actor.position.size() != 3
				or not actor.get("awake", true) is bool
				or (group.get("sleeping", false) and not actor.has("awake"))
				or (
					not group.get("sleeping", false)
					and not actor.get("awake", true)
					and not directions.slept.has(count - 1)
				)
				or (directions.suspended.has(count - 1) and actor.get("awake", true))
			):
				return false
			if int(group.actor) == int(library.content.mine_behavior.actor):
				if not Mines.valid(
					actor.get("mine"), float(actor.hp), library.content.mine_behavior
				):
					return false
			elif actor.has("mine"):
				return false
			elif not FighterMotion.valid_actor(actor, group, state, library):
				return false
			elif FighterMotion.moving(group) and actor.fighter_motion.hull_seen > maximum:
				return false
			elif not Destruction.valid(
				actor.get("destruction"),
				float(actor.hp),
				Destruction.effect(library, int(group.actor)),
				FighterMotion.speed_limit(
					actor,
					group,
					state,
					library,
					Destruction.speed_limit(group, definition.get("sequence", []), count - 1)
				)
			):
				return false
			for coordinate in actor.position:
				if not numeric(coordinate) or absf(coordinate) > 1e8:
					return false
			if not group_active(definition, state, group_index) and actor.hp != maximum:
				return false
			if (
				(
					(not actor.get("awake", true) and not directions.slept.has(count - 1))
					or not group.get("combat_active", true)
				)
				and actor.hp != maximum
			):
				return false
			if group.get("behavior") in ["interceptor", "escort", "wingmate", "turret"]:
				if (
					not integer(state.get("seed"))
					or state.seed < 0
					or not actor.has_all(["heading", "breaking", "shots"])
					or not actor.breaking is bool
					or not Evasion.valid(actor, group.get("behavior") != "turret")
					or not Frame.valid(actor)
					or not Targeting.valid(
						actor,
						library.content.fighter_targeting,
						Targeting.allowed_ids(definition, group.get("team", "enemy")),
						FighterMotion.moving(group)
					)
					or not Impact.valid(
						actor,
						library.content.fighter_impact,
						FighterMotion.moving(group),
						int(group.actor) == int(library.content.fighter_impact.no_tumble_actor)
					)
					or not integer(actor.shots)
					or actor.shots < 0
					or actor.shots > 1000000000
					or not actor.heading is Array
					or actor.heading.size() != 3
					or not actor.heading.all(func(axis): return numeric(axis))
				):
					return false
				var heading := Vector3(actor.heading[0], actor.heading[1], actor.heading[2])
				if not is_equal_approx(heading.length(), 1.0):
					return false
			if group.get("behavior") == "escort":
				if (
					not integer(actor.get("route_stage"))
					or actor.route_stage < 0
					or actor.route_stage > group.route.size()
					or not actor.get("heading") is Array
					or actor.heading.size() != 3
					or not actor.heading.all(func(axis): return numeric(axis))
				):
					return false
				var heading := Vector3(actor.heading[0], actor.heading[1], actor.heading[2])
				if not is_equal_approx(heading.length(), 1.0):
					return false
			if enemy(definition, actor):
				target_count += 1
				if actor.hp == 0:
					kills += 1
	if (
		count != state.actors.size()
		or state.target != int(definition.get("enemy_goal", target_count))
		or state.kills != kills
	):
		return false
	if not Sequence.valid_history(definition, state):
		return false
	var expected := state.duplicate(true)
	expected.ready = false
	expected.failed = false
	evaluate(definition, expected, false)
	return state.ready == expected.ready and state.failed == expected.failed


static func route_pending(definition: Dictionary, state: Dictionary) -> bool:
	return int(state.stage) < int(Sequence.directives(definition, state).route_end)


static func destroyed_prefix(definition: Dictionary, state: Dictionary, count: int) -> int:
	var seen := 0
	var destroyed := 0
	for actor in state.actors:
		if enemy(definition, actor):
			if seen >= count:
				break
			seen += 1
			if actor_dead(actor):
				destroyed += 1
	return destroyed


static func actor_dead(actor: Dictionary) -> bool:
	return Destruction.actor_dead(actor)


static func advance_mines(
	definition: Dictionary, state: Dictionary, seconds: float, player_position: Vector3, library
) -> Array:
	var events := []
	if state.is_empty() or state.ready or state.failed or seconds <= 0 or not is_finite(seconds):
		return events
	var directions := Sequence.directives(definition, state)
	var parameters: Dictionary = library.content.mine_behavior
	for index in state.actors.size():
		var actor: Dictionary = state.actors[index]
		if not actor.has("mine") or actor.mine.phase == "dead":
			continue
		if (
			not group_active(definition, state, int(actor.group))
			or directions.suspended.has(index)
			or directions.stopped.has(index)
		):
			continue
		var opponents := [{"id": -1, "position": player_position, "active": true}]
		for other_index in state.actors.size():
			var other: Dictionary = state.actors[other_index]
			if not enemy(definition, other):
				opponents.append(
					{
						"id": other_index,
						"position":
						Vector3(other.position[0], other.position[1], other.position[2]),
						"active": actor_active(definition, state, other)
					}
				)
		var event := Mines.advance(
			actor.mine,
			parameters,
			seconds,
			Vector3(actor.position[0], actor.position[1], actor.position[2]),
			opponents
		)
		if actor.mine.phase == "dormant" or event.armed:
			actor.hp = library.group_initial_hull(
				definition.groups[int(actor.group)], int(state.rank)
			)
		if event.detonated:
			actor.hp = 0.0
			if enemy(definition, actor):
				state.kills += 1
		if event.armed or event.detonated or event.finished:
			event.actor = index
			events.append(event)
		if int(event.damage_target) >= 0:
			damage(definition, state, int(event.damage_target), float(parameters.damage))
	evaluate(definition, state, false)
	return events
