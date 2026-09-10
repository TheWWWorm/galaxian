extends RefCounted
## Imported conditions schedule dialogue through a native readable message queue.
## Imported line timing and atlas metrics determine reading time, independent of speedup.


static func create() -> Dictionary:
	return {"shown": [], "current": -1, "remaining": 0.0, "delay": 0.0}


static func finished(definition: Dictionary, state: Dictionary) -> bool:
	if float(state.radio.remaining) > 0 or int(state.radio.current) >= 0:
		return false
	var messages: Array = definition.get("radio", [])
	for index in messages.size():
		if not state.radio.shown.has(index) and triggered(messages[index], definition, state):
			return false
	return true


static func advance(definition: Dictionary, state: Dictionary, seconds: float, library) -> void:
	if state.failed or seconds <= 0 or not is_finite(seconds):
		return
	var radio: Dictionary = state.radio
	var delay := float(radio.get("delay", 0.0))
	radio.delay = maxf(0, delay - seconds)
	if radio.delay > 0:
		return
	seconds = maxf(0, seconds - delay)
	radio.remaining = maxf(0, float(radio.remaining) - seconds)
	if radio.remaining > 0:
		return
	radio.current = -1
	var messages: Array = definition.get("radio", [])
	for index in messages.size():
		if radio.shown.has(index) or not triggered(messages[index], definition, state):
			continue
		radio.shown.append(index)
		radio.current = index
		radio.delay = float(library.content.radio_ui.lead_ms) / 1000.0
		radio.remaining = library.radio_duration(messages[index])
		return


static func triggered(cue: Dictionary, definition: Dictionary, state: Dictionary) -> bool:
	match cue.condition:
		"elapsed":
			return float(state.elapsed_ms) >= float(cue.value)
		"waypoint_passed":
			return int(state.stage) > int(cue.value)
		"message_shown":
			return state.radio.shown.has(int(cue.value))
		"mission_won":
			return state.ready
		"enemies_destroyed":
			return int(state.kills) >= int(state.target)
		"enemy_range_casualty", "enemy_range_damaged", "ally_range_casualty", "enemy_range_destroyed":
			var actors := team_actors(definition, state, cue.condition == "ally_range_casualty")
			var first := int(cue.value)
			var end := first + int(cue.count)
			if first < 0 or end > actors.size() or end <= first:
				return false
			for index in range(first, end):
				if cue.condition == "enemy_range_destroyed":
					if actors[index].hp > 0:
						return false
				elif cue.condition == "enemy_range_damaged":
					var group: Dictionary = definition.groups[int(actors[index].group)]
					if actors[index].hp < float(group.hull) * float(cue.fraction):
						return true
				elif actors[index].hp <= 0:
					return true
			return cue.condition == "enemy_range_destroyed"
		"enemies_active", "enemy_range_active", "ally_range_active", "enemy_active_after_message":
			var actors := team_actors(definition, state, cue.condition == "ally_range_active")
			var first := int(cue.value) if cue.condition != "enemies_active" else 0
			var end := actors.size()
			if cue.condition == "enemy_active_after_message":
				if not state.radio.shown.has(int(cue.message)):
					return false
				end = first + 1
			elif cue.condition != "enemies_active":
				end = first + int(cue.count)
			if first < 0 or end > actors.size() or end <= first:
				return false
			for index in range(first, end):
				var actor: Dictionary = actors[index]
				var group: Dictionary = definition.groups[int(actor.group)]
				if (
					group.get("combat_active", true)
					and actor.hp > 0
					and actor.get("awake", true)
					and (not group.after_route or int(state.stage) == definition.route.size())
				):
					return true
	return false


static func team_actors(definition: Dictionary, state: Dictionary, allies: bool) -> Array:
	return state.actors.filter(
		func(actor):
			return (definition.groups[int(actor.group)].get("team", "enemy") == "ally") == allies
	)


static func valid(value: Variant, count: int) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(["shown", "current", "remaining"])
		or not value.shown is Array
	):
		return false
	if (
		not integer(value.current)
		or value.current < -1
		or value.current >= count
		or not numeric(value.remaining)
		or value.remaining < 0
		or value.remaining > 120
		or not numeric(value.get("delay", 0.0))
		or float(value.get("delay", 0.0)) < 0
		or float(value.get("delay", 0.0)) > 10
	):
		return false
	var seen: Array[int] = []
	for index in value.shown:
		if not integer(index) or index < 0 or index >= count or seen.has(int(index)):
			return false
		seen.append(int(index))
	return (
		(value.current == -1 and value.remaining == 0 and float(value.get("delay", 0.0)) == 0)
		or (seen.has(int(value.current)) and value.remaining > 0)
	)


static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func integer(value: Variant) -> bool:
	return numeric(value) and value == int(value)
