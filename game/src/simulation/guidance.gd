extends RefCounted
## Native pursuit guidance. Rendering supplies visibility for acquisition;
## the saved lock and last target position belong to the projectile.


static func valid_parameters(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["delay", "response_divisor", "acquisition_half_width", "distance_squared_limit"]:
		var number: Variant = value.get(key)
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
		if number <= 0 or number > 1e12:
			return false
	return value.delay < 60 and value.response_divisor <= 1000


static func create() -> Dictionary:
	return {"target": -2, "position": [0.0, 0.0, 0.0]}


static func steer(shot: Dictionary, profile: Dictionary, seconds: float, candidates: Array) -> void:
	var parameters: Dictionary = profile.guidance
	if seconds <= 0 or profile.lifetime - float(shot.remaining) <= parameters.delay:
		return
	var lock: Dictionary = shot.guidance
	var position := Vector3(shot.position[0], shot.position[1], shot.position[2])
	if int(lock.target) == -2:
		var nearest: float = parameters.distance_squared_limit
		for candidate in candidates:
			if (
				not profile.get("guidance_target_ids", []).any(func(id): return id == candidate.id)
				or not candidate.get("visible", false)
				or not candidate.get("active", true)
				or not candidate.get("alive", true)
				or candidate.get("team", "enemy") == profile.get("team", "enemy")
				or candidate.get("team", "enemy") == "neutral"
			):
				continue
			var point := Vector3(
				candidate.position[0], candidate.position[1], candidate.position[2]
			)
			var offset := point - position
			var absolute := offset.abs()
			if maxf(absolute.x, maxf(absolute.y, absolute.z)) > parameters.acquisition_half_width:
				continue
			var distance := offset.length_squared()
			if distance < nearest:
				nearest = distance
				lock.target = int(candidate.id)
				lock.position = candidate.position.duplicate()
	if int(lock.target) == -2:
		return
	# Eligibility is checked when acquiring. A committed lock is not replaced
	# just because another ship becomes nearer or the target leaves the screen.
	for candidate in candidates:
		if int(candidate.id) == int(lock.target):
			lock.position = candidate.position.duplicate()
			break
	var destination := Vector3(lock.position[0], lock.position[1], lock.position[2])
	var velocity := Vector3(shot.velocity[0], shot.velocity[1], shot.velocity[2])
	var displacement := velocity * seconds
	var response: float = parameters.response_divisor * seconds * 1000.0
	var direction := displacement.lerp(destination - position, 1.0 / response)
	if direction.length_squared() > .00000001:
		velocity = direction.normalized() * float(profile.speed)
		shot.velocity = [velocity.x, velocity.y, velocity.z]
