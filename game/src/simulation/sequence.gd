extends RefCounted
const Destruction = preload("res://src/simulation/actor_destruction.gd")
const Combat = preload("res://src/simulation/combat.gd")
## Native encounter director. Imported milestones declare what changes and when;
## an integer cursor commits each transition once across save/load.


static func triggered(condition: Dictionary, state: Dictionary) -> bool:
	match condition.kind:
		"hull_below":
			return float(state.actors[int(condition.actor)].hp) < float(condition.value)
		"actor_dead":
			var actor: Dictionary = state.actors[int(condition.actor)]
			return Destruction.actor_dead(actor)
		"message_shown", "message_finished":
			if (
				condition.kind == "message_finished"
				and int(state.radio.current) == int(condition.message)
			):
				return false
			# JSON stores numeric IDs as floats. Validation runs before the save
			# is normalized, so compare IDs by value rather than Variant type.
			for message in state.radio.shown:
				if int(message) == int(condition.message):
					return true
			return false
	return false


static func directives(definition: Dictionary, state: Dictionary) -> Dictionary:
	var result := {
		"locked": false,
		"vulnerable": true,
		"frozen": false,
		"suspended": [],
		"slept": [],
		"camera_anchor": [],
		"stopped": [],
		"targets": {},
		"speeds": {},
		"detached": [],
		"focus": {},
		"route_end": int(definition.get("route_initial_end", definition.get("route", []).size())),
		"route_first": 0
	}
	var sequence: Array = definition.get("sequence", [])
	for index in mini(int(state.get("sequence_cursor", 0)), sequence.size()):
		for action in sequence[index].actions:
			match action.kind:
				"route":
					result.route_end = int(action.end)
					result.route_first = int(action.first)
				"lock":
					result.locked = action.value
				"vulnerable", "frozen":
					result[action.kind] = action.value
				"camera_hold":
					result.camera_anchor = (
						state.get("sequence_positions", {}).get("camera:" + str(index), [])
						if action.value
						else []
					)
				"sleep":
					if not result.slept.has(int(action.actor)):
						result.slept.append(int(action.actor))
				"suspend":
					if action.value:
						if not result.suspended.has(int(action.actor)):
							result.suspended.append(int(action.actor))
						if not result.slept.has(int(action.actor)):
							result.slept.append(int(action.actor))
					else:
						result.suspended.erase(int(action.actor))
				"stop":
					if not result.stopped.has(int(action.actor)):
						result.stopped.append(int(action.actor))
				"speed":
					result.speeds[int(action.actor)] = float(action.value)
				"detach_route":
					if not result.detached.has(int(action.actor)):
						result.detached.append(int(action.actor))
				"target":
					result.targets[int(action.actor)] = int(action.target)
				"focus_between":
					result.focus = action.duplicate(true)
					result.focus.position = state.get("sequence_positions", {}).get(str(index), [])
				"focus":
					result.focus = action
				"focus_active":
					result.focus = action.duplicate(true)
					result.focus.actor = int(state.get("sequence_choices", {}).get(str(index), -1))
	return result


static func advance(definition: Dictionary, state: Dictionary) -> void:
	var sequence: Array = definition.get("sequence", [])
	var cursor := int(state.get("sequence_cursor", 0))
	if cursor >= sequence.size() or not triggered(sequence[cursor].when, state):
		return
	for action in sequence[cursor].actions:
		match action.kind:
			"route":
				state.stage = int(action.first)
			"health":
				var actor: Dictionary = state.actors[int(action.actor)]
				var was_dead: bool = actor.hp <= 0
				actor.hp = float(action.value)
				if actor.hp > 0 and actor.has("fighter_motion"):
					actor.fighter_motion.hull_seen = actor.hp
					actor.fighter_motion.damage = 0.0
					if was_dead:
						actor.targeting = (
							preload("res://src/simulation/fighter_targeting.gd")
							. create(int(actor.targeting.decisions))
						)
						actor.impact = preload("res://src/simulation/fighter_impact.gd").create()
				if actor.hp > 0 and actor.has("evasion"):
					preload("res://src/simulation/fighter_evasion.gd").reset(actor)
				if actor.has("destruction"):
					if actor.hp > 0:
						actor.destruction.phase = "dead"
						actor.destruction.elapsed_ms = 0.0
						actor.destruction.velocity = [0.0, 0.0, 0.0]
						actor.destruction = Destruction.create()
					else:
						Destruction.begin(actor)
			"focus_active":
				if not state.has("sequence_choices"):
					state.sequence_choices = {}
				var selected := -1
				for index in range(int(action.first), int(action.first + action.count)):
					if state.actors[index].hp > 0 and state.actors[index].awake:
						selected = index
						break
				state.sequence_choices[str(cursor)] = selected
			"camera_hold":
				if action.value:
					if not state.has("sequence_positions"):
						state.sequence_positions = {}
					state.sequence_positions["camera:" + str(cursor)] = (
						state.get("camera_position", [0, 0, 0]).duplicate()
					)
			"sleep", "suspend":
				if action.kind == "sleep" or action.value:
					state.actors[int(action.actor)].awake = false
			"activate":
				state.actors[int(action.actor)].awake = true
			"place":
				state.actors[int(action.actor)].position = Combat.packed(source_point(action.point))
			"relocate_forward":
				var relative: Dictionary = state.actors[int(action.relative_to)]
				state.actors[int(action.actor)].position = Combat.packed(
					(
						Combat.vector(relative.position)
						+ Combat.vector(relative.heading) * float(action.distance) * .02
					)
				)
			"focus_between":
				if not state.has("sequence_positions"):
					state.sequence_positions = {}
				state.sequence_positions[str(cursor)] = Combat.packed(
					Combat.vector(state.actors[int(action.actor)].position).lerp(
						Combat.vector(state.actors[int(action.other)].position),
						float(action.fraction)
					)
				)
			"relocate":
				var relative := Combat.vector(state.actors[int(action.relative_to)].position)
				var offset: Array = action.offset
				state.actors[int(action.actor)].position = Combat.packed(
					relative + Vector3(offset[0], offset[1], -offset[2]) * .02
				)
	state.sequence_cursor = cursor + 1
	# A scripted arrival can restore a previously damaged actor. Recount from
	# authoritative actor state instead of duplicating a death counter event.
	state.kills = 0
	for actor in state.actors:
		if actor.hp <= 0 and definition.groups[int(actor.group)].get("team", "enemy") == "enemy":
			state.kills += 1


static func valid_definition(definition: Dictionary) -> bool:
	var sequence: Variant = definition.get("sequence", [])
	if not sequence is Array or sequence.size() > 128:
		return false
	if (
		not Combat.integer(definition.get("route_initial_end", definition.get("route", []).size()))
		or definition.get("route_initial_end", definition.get("route", []).size()) < 0
		or (
			definition.get("route_initial_end", definition.get("route", []).size())
			> definition.get("route", []).size()
		)
	):
		return false
	var actors := 0
	for group in definition.groups:
		actors += int(group.count)
	for event in sequence:
		if (
			not event is Dictionary
			or not event.get("when") is Dictionary
			or not event.get("actions") is Array
			or event.actions.size() > 32
		):
			return false
		var condition: Dictionary = event.when
		match condition.get("kind"):
			"hull_below", "actor_dead":
				if not actor_index(condition.get("actor"), actors):
					return false
				if (
					condition.kind == "hull_below"
					and (
						not Combat.number(condition.get("value"))
						or condition.value <= 0
						or condition.value > 10000000
					)
				):
					return false
			"message_shown", "message_finished":
				if not actor_index(condition.get("message"), definition.radio.size()):
					return false
			_:
				return false
		var snapshots := 0
		var selectors := 0
		var camera_snapshots := 0
		for action in event.actions:
			if not action is Dictionary:
				return false
			if action.get("kind") == "route":
				if (
					not Combat.integer(action.get("first"))
					or not Combat.integer(action.get("end"))
					or action.first < 0
					or action.end < action.first
					or action.end > definition.get("route", []).size()
				):
					return false
				continue
			if action.get("kind") == "focus_active":
				selectors += 1
				if (
					selectors > 1
					or not actor_index(action.get("first"), actors)
					or not Combat.integer(action.get("count"))
					or action.count <= 0
					or action.first + action.count > actors
					or not Combat.valid_vector(action.get("offset"))
					or not Combat.valid_vector(action.get("target_offset"))
				):
					return false
				continue
			if action.get("kind") in ["lock", "vulnerable", "frozen", "camera_hold"]:
				if not action.get("value") is bool:
					return false
				if action.kind == "camera_hold" and action.value:
					camera_snapshots += 1
					if camera_snapshots > 1:
						return false
				continue
			if (
				not actor_index(action.get("actor"), actors)
				and not (action.get("kind") == "focus" and action.get("actor") == -1)
			):
				return false
			if action.get("kind") in ["sleep", "suspend"]:
				var group := actor_group(definition, int(action.actor))
				if (
					group.get("behavior") == "stationary"
					and (
						not Combat.number(group.get("wake_half_width"))
						or group.wake_half_width <= 0
						or group.wake_half_width > 1000000
					)
				):
					return false
			match action.get("kind"):
				"place":
					if not Combat.valid_vector(action.get("point")):
						return false
				"speed":
					if (
						not Combat.number(action.get("value"))
						or action.value < 0
						or action.value > 1000000
					):
						return false
				"detach_route":
					if actor_behavior(definition, int(action.actor)) != "escort":
						return false
				"relocate_forward":
					if (
						not actor_index(action.get("relative_to"), actors)
						or (
							actor_behavior(definition, int(action.relative_to))
							not in ["escort", "wingmate", "interceptor", "turret"]
						)
						or not Combat.number(action.get("distance"))
						or absf(action.distance) > 10000000
					):
						return false
				"focus_between":
					snapshots += 1
					if (
						snapshots > 1
						or not actor_index(action.get("other"), actors)
						or action.other == action.actor
						or not Combat.number(action.get("fraction"))
						or action.fraction < 0
						or action.fraction > 1
					):
						return false
				"health":
					if (
						not Combat.integer(action.get("value"))
						or action.value < 0
						or action.value > 10000000
					):
						return false
				"relocate":
					if (
						not actor_index(action.get("relative_to"), actors)
						or not Combat.valid_vector(action.get("offset"))
					):
						return false
				"focus":
					if (
						not Combat.valid_vector(action.get("offset"))
						or not action.get("relative", false) is bool
					):
						return false
				"target":
					if (
						not actor_index(action.get("target"), actors)
						or action.actor == action.target
					):
						return false
				"suspend":
					if not action.get("value") is bool:
						return false
				"stop", "activate", "sleep":
					pass
				_:
					return false
	return true


static func valid(definition: Dictionary, state: Dictionary) -> bool:
	var sequence: Array = definition.get("sequence", [])
	if not sequence.is_empty() and not state.has("sequence_cursor"):
		return false
	var cursor: Variant = state.get("sequence_cursor", 0)
	if not Combat.integer(cursor) or cursor < 0 or cursor > sequence.size():
		return false
	for index in int(cursor):
		var condition: Dictionary = sequence[index].when
		if (
			condition.kind in ["message_shown", "message_finished"]
			and not triggered(condition, state)
		):
			return false
	var navigation := directives(definition, state)
	if state.stage < navigation.route_first or state.stage > navigation.route_end:
		return false
	var choices: Variant = state.get("sequence_choices", {})
	if not choices is Dictionary:
		return false
	var expected := 0
	for index in int(cursor):
		for action in sequence[index].actions:
			if action.kind != "focus_active":
				continue
			expected += 1
			var choice: Variant = choices.get(str(index))
			if (
				not Combat.integer(choice)
				or (
					choice != -1
					and (choice < action.first or choice >= action.first + action.count)
				)
			):
				return false
	var positions: Variant = state.get("sequence_positions", {})
	if not positions is Dictionary:
		return false
	if state.has("camera_position") and not Combat.valid_vector(state.camera_position):
		return false
	var expected_positions := 0
	for index in int(cursor):
		var snapshots := 0
		for action in sequence[index].actions:
			if action.kind == "focus_between":
				snapshots += 1
			if action.kind == "camera_hold" and action.value:
				expected_positions += 1
				if not Combat.valid_vector(positions.get("camera:" + str(index))):
					return false
		if snapshots > 0:
			expected_positions += 1
			if snapshots != 1 or not Combat.valid_vector(positions.get(str(index))):
				return false
	return choices.size() == expected and positions.size() == expected_positions


static func actor_index(value: Variant, count: int) -> bool:
	return Combat.integer(value) and value >= 0 and value < count


static func health_limit(
	definition: Dictionary, state: Dictionary, actor: int, initial: float
) -> float:
	var result := initial
	var sequence: Array = definition.get("sequence", [])
	for index in mini(int(state.get("sequence_cursor", 0)), sequence.size()):
		for action in sequence[index].actions:
			if action.kind == "health" and int(action.actor) == actor:
				result = float(action.value)
	return result


static func valid_history(definition: Dictionary, state: Dictionary) -> bool:
	var sequence: Array = definition.get("sequence", [])
	for index in int(state.get("sequence_cursor", 0)):
		var condition: Dictionary = sequence[index].when
		if condition.kind in ["message_shown", "message_finished"]:
			continue
		var replaced := false
		for later in range(index + 1, int(state.sequence_cursor)):
			for action in sequence[later].actions:
				if action.kind == "health" and action.actor == condition.actor:
					replaced = true
		if not replaced and not triggered(condition, state):
			return false
	return true


static func source_point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], -value[2]) * .02


static func actor_behavior(definition: Dictionary, index: int) -> String:
	return str(actor_group(definition, index).get("behavior", "stationary"))


static func actor_group(definition: Dictionary, index: int) -> Dictionary:
	for group in definition.groups:
		if index < int(group.count):
			return group
		index -= int(group.count)
	return {}


static func maximum_hull(
	definition: Dictionary, state: Dictionary, actor: int, initial: float
) -> float:
	# Source setHitpoints raises maximum hull when needed; lowering current hull
	# later does not lower that maximum. This differs from the current health bound.
	var maximum := initial
	var sequence: Array = definition.get("sequence", [])
	for index in mini(int(state.get("sequence_cursor", 0)), sequence.size()):
		for action in sequence[index].actions:
			if action.kind == "health" and int(action.actor) == actor:
				maximum = maxf(maximum, float(action.value))
	return maximum
