extends RefCounted
## Native continuous-time movement and one-shot boost, using imported limits.
## Throttle and lateral flight are modern controls; source boost is a timed pulse.


static func create() -> Dictionary:
	return {"throttle": 1.0, "boost_remaining": 0.0, "cooldown": 0.0, "contact_elapsed": 0.0}


static func valid_parameters(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["cruise_speed", "boost_speed", "boost_seconds", "recharge_seconds"]:
		if not number(value.get(key)) or value[key] <= 0 or value[key] > 100000:
			return false
	return value.boost_speed >= value.cruise_speed and preload("res://src/simulation/body_contact.gd").valid_parameters(value.get("contact"))


static func valid(state: Variant, parameters: Dictionary) -> bool:
	if not state is Dictionary:
		return false
	for key in ["throttle", "boost_remaining", "cooldown", "contact_elapsed"]:
		if not number(state.get(key)) or state[key] < 0:
			return false
	return (
		state.throttle <= 1
		and state.contact_elapsed <= parameters.contact.interval
		and state.boost_remaining <= parameters.boost_seconds
		and state.cooldown <= parameters.recharge_seconds
		and not (state.boost_remaining > 0 and state.cooldown > 0)
	)


static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func speed(state: Dictionary, parameters: Dictionary) -> float:
	return (
		float(parameters.boost_speed)
		if state.boost_remaining > 0
		else float(parameters.cruise_speed) * float(state.throttle)
	)


static func charge(state: Dictionary, parameters: Dictionary) -> float:
	if state.boost_remaining > 0:
		return float(state.boost_remaining) / float(parameters.boost_seconds)
	return 1.0 - float(state.cooldown) / float(parameters.recharge_seconds)


static func advance(
	state: Dictionary, parameters: Dictionary, seconds: float, request: bool = false
) -> Dictionary:
	if seconds <= 0 or not is_finite(seconds):
		return {"forward": 0.0, "limit": 0.0}
	if request and state.boost_remaining <= 0 and state.cooldown <= 0:
		state.boost_remaining = float(parameters.boost_seconds)
	var boosted := minf(seconds, float(state.boost_remaining))
	if state.boost_remaining > 0:
		state.boost_remaining = maxf(0, float(state.boost_remaining) - seconds)
		if state.boost_remaining <= 0:
			state.cooldown = float(parameters.recharge_seconds)
	var cruising := seconds - boosted
	state.cooldown = maxf(0, float(state.cooldown) - cruising)
	# Integrate both portions when one step crosses the boost boundary. Travel
	# and cooldown are independent of how the native physics divides that step.
	return {
		"forward":
		(
			boosted * float(parameters.boost_speed)
			+ cruising * float(parameters.cruise_speed) * float(state.throttle)
		),
		"limit": boosted * float(parameters.boost_speed) + cruising * float(parameters.cruise_speed)
	}
