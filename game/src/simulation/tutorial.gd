extends RefCounted
## Visual cues follow selected radio messages, including their lead-in delay.
## This module has no access to player controls or simulation actions.


static func applies(config: Dictionary, job: Dictionary) -> bool:
	return job.get("kind") == "campaign" and job.get("chapter") == config.chapter


static func create(config: Dictionary, shown: Array = [], migrating: bool = false) -> Dictionary:
	var state := {"index": 0, "elapsed_ms": -1.0, "phase_ms": 0.0}
	if migrating:
		# Old saves do not contain hint timers. Preserve gameplay and skip cues
		# whose messages were already selected instead of replaying stale hints.
		while state.index < config.steps.size():
			var trigger := int(config.steps[state.index].radio)
			if trigger >= 0 and not shown.any(func(value): return value == trigger):
				break
			state.index += 1
	return state


static func advance(config: Dictionary, state: Dictionary, shown: Array, seconds: float) -> void:
	if seconds <= 0 or not is_finite(seconds):
		return
	state.phase_ms = fposmod(float(state.phase_ms) + seconds * 1000, float(config.blink_ms) * 2)
	var remaining := seconds * 1000
	while int(state.index) < config.steps.size():
		var step: Dictionary = config.steps[int(state.index)]
		if state.elapsed_ms < 0:
			if step.radio >= 0 and not shown.has(int(step.radio)):
				return
			state.elapsed_ms = 0.0
			# Radio selection happens at the frame boundary. Start its cue here;
			# automatic successor cues retain elapsed time across frame sizes.
			if step.radio >= 0:
				return
		var elapsed := float(state.elapsed_ms) + remaining
		if elapsed <= float(config.duration_ms):
			state.elapsed_ms = elapsed
			return
		remaining = elapsed - float(config.duration_ms)
		state.index += 1
		state.elapsed_ms = -1.0


static func cue(config: Dictionary, state: Dictionary) -> Dictionary:
	if (
		int(state.index) >= config.steps.size()
		or state.elapsed_ms < float(config.duration_ms) - float(config.blink_limit_ms)
	):
		return {}
	return {
		"action": config.steps[int(state.index)].action,
		"lit": float(state.phase_ms) < float(config.blink_ms)
	}


static func valid(config: Dictionary, state: Variant, shown: Array) -> bool:
	if not state is Dictionary:
		return false
	for key in ["index", "elapsed_ms", "phase_ms"]:
		var value: Variant = state.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
	if (
		state.index != int(state.index)
		or state.index < 0
		or state.index > config.steps.size()
		or (state.elapsed_ms != -1 and state.elapsed_ms < 0)
		or state.elapsed_ms > config.duration_ms
		or state.phase_ms < 0
		or state.phase_ms >= float(config.blink_ms) * 2
		or (state.index == config.steps.size() and state.elapsed_ms != -1)
	):
		return false
	var selected := int(state.index) + (1 if state.elapsed_ms >= 0 else 0)
	for index in selected:
		var trigger := int(config.steps[index].radio)
		if trigger >= 0 and not shown.any(func(value): return value == trigger):
			return false
	return true
