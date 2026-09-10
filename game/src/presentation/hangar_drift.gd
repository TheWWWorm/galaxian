extends RefCounted
## Independent cosmetic camera paths sampled from supplied ranges.
const Combat = preload("res://src/simulation/combat.gd")
var data: Dictionary
var origin := Vector3.ZERO
var position := Vector3.ZERO
var axes: Array = []


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["initial_low", "initial_high", "low_offset", "low_spread", "high_offset", "high_spread", "reversal_margin"]:
		var vector: Variant = value.get(key)
		if not vector is Array or vector.size() != 3:
			return false
		for component in vector:
			if not Combat.integer(component) or absf(component) > 100000:
				return false
	for key in ["seconds", "threshold", "fov_units", "near", "far"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if value.fov_units >= 32768 or value.far <= value.near:
		return false
	for axis in 3:
		if value.initial_low[axis] >= -value.threshold or value.initial_high[axis] <= value.threshold:
			return false
		if value.low_offset[axis] >= -value.threshold or value.high_offset[axis] <= value.threshold:
			return false
		if value.low_spread[axis] <= 0 or value.high_spread[axis] == 0 or value.reversal_margin[axis] < 0:
			return false
		# Signed spread means offset minus a random integer for the X high range.
		if value.high_offset[axis] + mini(0, int(value.high_spread[axis])) <= value.threshold:
			return false
	return true


func configure(parameters: Dictionary, base: Vector3, seed_value: int) -> void:
	data = parameters
	origin = base
	position = base
	axes.clear()
	for index in 3:
		var random := RandomNumberGenerator.new()
		random.seed = hash(str(seed_value) + ":" + str(index))
		# The supplied constructor leaves initial direction flags unspecified.
		# Pick a reproducible allowed direction instead of emulating uninitialized memory.
		var rising := random.randi_range(0, 1) == 1
		var offset: float = data.initial_high[index] if rising else data.initial_low[index]
		var axis := {"random": random, "rising": rising, "legs": 0}
		start_leg(axis, origin[index], origin[index] + offset)
		axes.append(axis)


func start_leg(axis: Dictionary, from: float, to: float) -> void:
	axis.start = from
	axis.end = to
	axis.elapsed = 0.0
	# End at the source proximity threshold, rather than waiting at an endpoint.
	var fraction := clampf(float(data.threshold) / absf(to - from), 0, 1)
	axis.duration = float(data.seconds) * acos(2.0 * fraction - 1.0) / PI


func value(axis: Dictionary) -> float:
	var progress := float(axis.elapsed) / float(data.seconds)
	return lerpf(axis.start, axis.end, (1.0 - cos(PI * progress)) * .5)


func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0:
		return
	for index in 3:
		var axis: Dictionary = axes[index]
		var remaining := seconds
		while remaining > 0:
			var step := minf(remaining, maxf(0, axis.duration - axis.elapsed))
			axis.elapsed += step
			remaining = maxf(0, remaining - step)
			position[index] = value(axis)
			if axis.elapsed + .000000001 < axis.duration:
				break
			axis.rising = not axis.rising
			axis.legs += 1
			var target := next_target(index, axis, position[index])
			start_leg(axis, position[index], target)


func next_target(index: int, axis: Dictionary, current: float) -> float:
	var random: RandomNumberGenerator = axis.random
	var offset: int = data.high_offset[index] if axis.rising else data.low_offset[index]
	var spread: int = data.high_spread[index] if axis.rising else -data.low_spread[index]
	var target := origin[index] + offset + signi(spread) * random.randi_range(0, absi(spread) - 1)
	var margin := float(data.reversal_margin[index])
	if margin > 0:
		if axis.rising and target <= current:
			target = current + margin
		elif not axis.rising and target >= current:
			target = current - margin
	return target
