extends RefCounted
## Persistent native body frame. Heading alone cannot preserve a fighter's bank.
const Combat = preload("res://src/simulation/combat.gd")


static func axes(heading: Vector3, up: Vector3 = Vector3.ZERO) -> Basis:
	if up == Vector3.ZERO:
		up = Vector3.RIGHT if absf(heading.dot(Vector3.UP)) > .99 else Vector3.UP
	return Basis.looking_at(heading, up)


static func turn(actor: Dictionary, heading: Vector3) -> void:
	var previous := Combat.vector(actor.heading)
	var up := Combat.vector(actor.up)
	# A large native step may point directly along the old up axis. Carry the
	# frame through the turn in that singular case instead of choosing world-up.
	if absf(heading.dot(up)) > .999999:
		up = Quaternion(previous, heading) * up
	actor.heading = Combat.packed(heading)
	actor.up = Combat.packed(axes(heading, up).y)


static func valid(actor: Dictionary) -> bool:
	if not Combat.valid_vector(actor.get("heading")) or not Combat.valid_vector(actor.get("up")):
		return false
	var heading := Combat.vector(actor.heading)
	var up := Combat.vector(actor.up)
	return (
		absf(heading.length() - 1.0) < .00001
		and absf(up.length() - 1.0) < .00001
		and absf(heading.dot(up)) < .00001
	)


static func migrate(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary:
			return false
		if not actor.has("heading"):
			continue
		if not Combat.valid_vector(actor.heading):
			return false
		var heading := Combat.vector(actor.heading)
		if absf(heading.length() - 1.0) >= .00001:
			return false
		# Reconstruct exactly the orientation displayed by older heading-only saves.
		actor.up = Combat.packed(axes(heading).y)
	return true
