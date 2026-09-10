extends RefCounted
## Continuous native angular dynamics derived from imported source limits.
## State is angular velocity (yaw, pitch), in radians/second. No source frame code.

static func valid_parameters(value: Variant) -> bool:
	if not value is Dictionary or not value.get("agilities") is Array or value.agilities.size() != 4:
		return false
	for agility in value.agilities:
		if not number(agility) or agility <= 0 or agility > 1000: return false
	for key in ["radians_per_unit", "reference_seconds", "limit_scale", "response_ceiling", "response_divisor", "default_response", "bank_scale", "pitch_bank_divisor", "look_blend", "position_blend"]:
		if not number(value.get(key)) or value[key] <= 0 or value[key] > 100000: return false
	if value.get("ship_type_column") != 1 or value.radians_per_unit > .01 or value.reference_seconds > 1:
		return false
	if value.default_response >= value.response_ceiling or value.look_blend >= 1 or value.position_blend >= 1:
		return false
	return value.get("release_divisors") is Array and value.release_divisors.size() == 2 and value.release_divisors.all(func(n): return number(n) and n > 0 and n <= 100000)

static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func valid(state: Variant, data: Dictionary) -> bool:
	if not state is Array or state.size() != 2: return false
	var limit := maximum_rate(data, float(data.agilities.max()))
	return state.all(func(n): return number(n) and absf(n) <= limit + .00001)

static func maximum_rate(data: Dictionary, agility: float) -> float:
	return agility * float(data.limit_scale) * float(data.radians_per_unit) / float(data.reference_seconds)

static func acceleration(data: Dictionary, agility: float) -> float:
	# Source angle increments contain elapsed_ms squared. Converting to angular
	# velocity/second cancels the two reference-time factors.
	return agility * 1000000.0 * float(data.radians_per_unit) / ((float(data.response_ceiling) - float(data.default_response)) * float(data.response_divisor))

static func release_rate(data: Dictionary, agility: float, axis: int) -> float:
	return agility * 1000.0 * float(data.radians_per_unit) / (float(data.release_divisors[axis]) * float(data.reference_seconds))

static func advance(state: Array, data: Dictionary, agility: float, input: Vector2, seconds: float) -> Vector2:
	if seconds <= 0 or not is_finite(seconds): return Vector2.ZERO
	var angles := Vector2.ZERO
	var limit := maximum_rate(data, agility)
	for axis in 2:
		var strength := clampf(input[axis], -1.0, 1.0)
		# Source analog consumers square strength before applying the signed limit.
		var target := signf(strength) * strength * strength * limit
		var before := clampf(float(state[axis]), -limit, limit)
		var drag := release_rate(data, agility, axis)
		var drive := acceleration(data, agility)
		var remaining := seconds
		# The source clears the directional flags before its decay pass, so
		# damping also acts during held input. Integrate drive minus drag on
		# acceleration, drag when easing off, and drive plus drag on reversal.
		for segment in 2:
			var reversing := before * target < 0
			var goal := 0.0 if reversing else target
			var rate := drive + drag if reversing else (maxf(0, drive - drag) if absf(target) > absf(before) else drag)
			if rate <= 0:
				angles[axis] += before * remaining
				break
			var reach_seconds := absf(goal - before) / rate
			var ramp_seconds := minf(remaining, reach_seconds)
			var after := goal if remaining >= reach_seconds else move_toward(before, goal, rate * ramp_seconds)
			angles[axis] += (before + after) * .5 * ramp_seconds
			remaining -= ramp_seconds
			before = after
			if not reversing or remaining <= 0:
				angles[axis] += after * remaining
				break
		state[axis] = before
	return angles

static func bank(state: Array, data: Dictionary) -> Vector3:
	var scale := float(data.reference_seconds) * float(data.bank_scale)
	return Vector3(float(state[1]) * scale / float(data.pitch_bank_divisor), 0, float(state[0]) * scale)

static func mouse_axis(displacement: Vector2, seconds: float, maximum: float) -> Vector2:
	if seconds <= 0: return Vector2.ZERO
	var request := displacement / (seconds * maximum)
	# Mouse sensitivity stays an angular-distance preference. Undo the stick curve
	# before combining input, then all devices share the ship's actual rate limit.
	return Vector2(signf(request.x) * sqrt(minf(absf(request.x), 1)), signf(request.y) * sqrt(minf(absf(request.y), 1)))
