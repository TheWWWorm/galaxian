extends RefCounted
## Native timed impact reaction. The source effect flag is separate from gun art.
const Combat = preload("res://src/simulation/combat.gd")
const Frame = preload("res://src/simulation/fighter_frame.gd")


static func create() -> Dictionary:
	return {"active": false, "elapsed": 0.0, "vector": [0.0, 0.0, 0.0]}


static func valid_parameters(data: Variant, library) -> bool:
	if not data is Dictionary or not data.get("player_flags") is Dictionary:
		return false
	for key in ["duration", "rotation_rate", "travel_scale"]:
		if not Combat.number(data.get(key)) or data[key] <= 0 or data[key] > 100:
			return false
	if (
		not Combat.integer(data.get("no_tumble_actor"))
		or data.no_tumble_actor < 0
		or data.no_tumble_actor >= library.content.tables.actor_meshes.size()
	):
		return false
	if data.player_flags.size() != library.content.player_armament.size():
		return false
	for key in library.content.player_armament:
		if not data.player_flags.get(key) is bool:
			return false
	return true


static func rocket(weapon: int, library, profile: Dictionary) -> bool:
	if weapon < 0:
		return bool(profile.get("rocket_impact", false))
	if profile.get("legacy_projectile", false):
		return false
	return bool(
		library.content.fighter_impact.player_flags.get(str(weapon % library.items.size()), false)
	)


static func receive(actor: Dictionary, velocity: Vector3, data: Dictionary) -> void:
	if actor.hp <= 0 or not actor.has("fighter_motion") or not velocity.is_finite():
		return
	# Source hit vectors are nominal-frame displacements, then used as fixed
	# direction factors. Keep that scale independent of the modern frame rate.
	actor.impact.vector = Combat.packed(velocity * float(data.travel_scale))
	actor.impact.active = true
	# A second rocket replaces drift direction without renewing elapsed time.


static func advance(actor: Dictionary, distance: float, seconds: float, data: Dictionary) -> void:
	if not actor.impact.active or seconds <= 0:
		return
	var frame := Frame.axes(Combat.vector(actor.heading), Combat.vector(actor.up))
	frame = (frame * Basis(Vector3.RIGHT, -float(data.rotation_rate) * seconds)).orthonormalized()
	actor.heading = Combat.packed(-frame.z)
	actor.up = Combat.packed(frame.y)
	var drift := Combat.vector(actor.impact.vector)
	actor.position = Combat.packed(Combat.vector(actor.position) + drift * distance)
	actor.destruction.velocity = Combat.packed(drift * float(actor.fighter_motion.speed))
	actor.impact.elapsed += seconds
	if actor.impact.elapsed + .000000001 >= data.duration:
		actor.impact = create()


static func valid(
	actor: Dictionary, data: Dictionary, can_react: bool = true, no_tumble: bool = false
) -> bool:
	var state: Variant = actor.get("impact")
	if (
		not state is Dictionary
		or not state.get("active") is bool
		or not Combat.number(state.get("elapsed"))
		or not Combat.valid_vector(state.get("vector"))
	):
		return false
	if state.elapsed < 0 or state.elapsed >= data.duration:
		return false
	if not state.active:
		return state.elapsed == 0 and Combat.vector(state.vector) == Vector3.ZERO
	return can_react and (not no_tumble or state.elapsed == 0)


static func migrate(actors: Variant) -> bool:
	if not actors is Array:
		return false
	for actor in actors:
		if not actor is Dictionary:
			return false
		if actor.has("heading"):
			actor.impact = create()
	return true
