extends RefCounted
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")
## Independent steering and attack behavior over imported encounter declarations.
## Positions are sampled before movement; target scans preserve source roster order.


static func advance(
	definition: Dictionary,
	state: Dictionary,
	seconds: float,
	player_position: Vector3,
	player_velocity: Vector3,
	combat: Dictionary,
	library,
	weapons: Dictionary
) -> Dictionary:
	var previous := {}
	var directions := Mission.Sequence.directives(definition, state)
	if state.is_empty() or state.ready or state.failed or seconds <= 0 or not is_finite(seconds):
		return previous
	var roster: Array = [
		{
			"id": -1,
			"team": "ally",
			"position": player_position,
			"velocity": player_velocity,
			"active": true
		}
	]
	for index in state.actors.size():
		var actor: Dictionary = state.actors[index]
		previous[index] = actor.position.duplicate()
		var group: Dictionary = definition.groups[int(actor.group)]
		roster.append(
			{
				"id": index,
				"team": group.get("team", "enemy"),
				"position": Combat.vector(actor.position),
				"velocity": Combat.vector(actor.get("destruction", {}).get("velocity", [0, 0, 0])),
				"active": Mission.actor_active(definition, state, actor)
			}
		)
	var candidates: Array = roster.filter(func(candidate): return candidate.active)
	for index in state.actors.size():
		var actor: Dictionary = state.actors[index]
		var group: Dictionary = definition.groups[int(actor.group)]
		if actor.hp > 0 and actor.has("destruction"):
			actor.destruction.velocity = [0.0, 0.0, 0.0]
		if (
			not group.get("combat_active", true)
			or directions.stopped.has(index)
			or directions.suspended.has(index)
			or not Mission.group_active(definition, state, int(actor.group))
		):
			if actor.hp > 0 and Mission.FighterMotion.moving(group):
				Mission.FighterMotion.wait_actor(actor, group, state, library, seconds)
			continue
		if group.get("behavior") == "transit":
			if Mission.actor_active(definition, state, actor):
				actor.position = Combat.packed(
					Combat.vector(actor.position) + Combat.vector(group.velocity) * seconds
				)
				actor.destruction.velocity = group.velocity.duplicate()
			continue
		if group.get("behavior") == "turret":
			advance_turret(group, actor, index, candidates, seconds, combat, library, weapons)
			continue
		if group.get("behavior") == "stationary" and not actor.awake and actor.hp > 0:
			# Fixed bodies wake near any active opponent, including wingmates.
			var position := Combat.vector(actor.position)
			for candidate in candidates:
				if candidate.team == group.get("team", "enemy"):
					continue
				var separation: Vector3 = (candidate.position - position).abs()
				if separation[separation.max_axis_index()] <= float(group.wake_half_width):
					actor.awake = true
					break
		if group.get("behavior") not in ["interceptor", "escort", "wingmate"] or actor.hp <= 0:
			continue
		var position := Combat.vector(actor.position)
		var motion: Dictionary = group.motion
		var offset := player_position - position
		var has_route: bool = (
			group.get("behavior") == "escort"
			and not directions.detached.has(index)
			and int(actor.route_stage) < group.route.size()
		)
		var target := Mission.Targeting.advance(
			actor.targeting,
			Mission.Targeting.opponents(roster, group.get("team", "enemy")),
			position,
			seconds,
			library.content.fighter_targeting,
			Mission.Targeting.chance(library.content.fighter_targeting, definition, state),
			int(state.seed),
			index,
			has_route
		)
		if not actor.awake:
			Mission.FighterMotion.wait_actor(actor, group, state, library, seconds)
			for candidate in candidates:
				if group.get("team", "enemy") == "ally":
					if candidate.id != -1:
						continue
				elif candidate.team == group.get("team", "enemy"):
					continue
				offset = candidate.position - position
				var separation := offset.abs()
				var wake_extent: float = (
					library.content.fighter_targeting.ally_wake_half_width
					if group.get("team", "enemy") == "ally"
					else motion.wake_half_width
				)
				if separation[separation.max_axis_index()] <= wake_extent:
					actor.awake = true
					Mission.Frame.turn(
						actor,
						offset.normalized() if offset.length_squared() > .001 else Vector3.FORWARD
					)
					break
			continue
		var weapon_ids: Array = group.get("weapon_ids", [-1 - index])
		var weapon: int = int(weapon_ids[0]) if not weapon_ids.is_empty() else -1 - index
		var gun: Dictionary = weapons.get(weapon, {})
		if directions.targets.has(index):
			target = {}
			for candidate in candidates:
				if candidate.id == directions.targets[index]:
					target = candidate
					break
		var step_seconds := seconds
		if (
			actor.impact.active
			and int(group.actor) != int(library.content.fighter_impact.no_tumble_actor)
		):
			var impact_seconds := minf(
				step_seconds,
				float(library.content.fighter_impact.duration) - float(actor.impact.elapsed)
			)
			var distance := Mission.FighterMotion.step_actor(
				actor,
				group,
				state,
				library,
				impact_seconds,
				index,
				offset,
				not target.is_empty(),
				Mission.Sequence.maximum_hull(
					definition, state, index, library.group_initial_hull(group, int(state.rank))
				)
			)
			Mission.Impact.advance(actor, distance, impact_seconds, library.content.fighter_impact)
			step_seconds -= impact_seconds
			if step_seconds <= .000000001:
				continue
			position = Combat.vector(actor.position)
		var desired := Vector3.ZERO
		if not target.is_empty():
			offset = target.position - position
			desired = Mission.Evasion.desired(
				actor,
				offset,
				Mission.Evasion.half_width(
					library.content.fighter_evasion, library.content.fighter_steering, group, state
				),
				library.content.fighter_evasion.directions,
				int(state.seed),
				index
			)
		else:
			Mission.Evasion.suspend(actor)
			if directions.targets.has(index):
				# A directed fly-by keeps its course after the selected target is lost.
				desired = (
					Combat.vector(actor.heading) * float(actor.fighter_motion.speed) * step_seconds
				)
			elif group.get("behavior") == "escort" and not directions.detached.has(index):
				desired = route_direction(group, actor, position, step_seconds)
			elif group.get("behavior") == "wingmate":
				desired = idle_ally_direction(
					position, player_position, library.content.fighter_targeting
				)
		var heading := Combat.vector(actor.heading)
		var travel := Mission.FighterMotion.step_actor(
			actor,
			group,
			state,
			library,
			step_seconds,
			index,
			offset,
			not target.is_empty(),
			Mission.Sequence.maximum_hull(
				definition, state, index, library.group_initial_hull(group, int(state.rank))
			)
		)
		var velocity := Vector3.ZERO
		if desired.length_squared() > .001:
			heading = steer_heading(
				heading,
				desired,
				step_seconds,
				steering_rate(library.content.fighter_steering, group, state),
				float(library.content.fighter_steering.snap_distance)
			)
		# Coincident combat targets still have forward flight; only direction
		# correction is undefined there. Route arrival may intentionally stop.
		if desired.length_squared() > .001 or not target.is_empty():
			if target.is_empty():
				travel = minf(travel, desired.length())
			position += heading * travel
			velocity = (
				heading
				* (
					float(actor.fighter_motion.speed)
					if not target.is_empty() or travel < desired.length()
					else 0.0
				)
			)
		Mission.Frame.turn(actor, heading)
		actor.position = Combat.packed(position)
		actor.destruction.velocity = Combat.packed(velocity)
		if target.is_empty() or gun.is_empty() or actor.impact.active:
			continue
		offset = target.position - position
		if not firing_aligned(
			heading,
			offset,
			motion,
			desired if actor.breaking else Vector3.ZERO,
			Combat.vector(actor.up)
		):
			continue
		# Fighter guns inherit the ship basis. Source shoot tolerance is an angle,
		# not random positional spread or permission to redirect bullets at a target.
		for id in weapon_ids:
			var mounted: Dictionary = weapons.get(int(id), {})
			if mounted.is_empty():
				continue
			var origin := mount_origin(position, heading, mounted, Combat.vector(actor.up))
			if Combat.fire(combat, int(id), origin, heading, library, weapons):
				actor.shots = int(actor.shots) + 1

	return previous


static func idle_ally_direction(
	position: Vector3, player_position: Vector3, data: Dictionary
) -> Vector3:
	# The source's enemy-less, route-less ally branch points directly at the
	# pilot and activates only inside this box. Spawn offsets are not slots.
	var offset := player_position - position
	var extent := offset.abs()
	return (
		offset
		if extent[extent.max_axis_index()] <= float(data.ally_wake_half_width)
		else Vector3.ZERO
	)


static func valid_steering(value: Variant, actor_count: int, chapter_count: int) -> bool:
	if not value is Dictionary:
		return false
	for key in ["normal_rate", "enhanced_rate", "snap_distance"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 100:
			return false
	if value.snap_distance >= 1:
		return false
	for key in ["enhanced_actor", "special_actor"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] >= actor_count:
			return false
	for key in ["enhanced_chapter", "special_chapter"]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] >= chapter_count:
			return false
	return true


static func steering_rate(data: Dictionary, group: Dictionary, state: Dictionary) -> float:
	var enhanced: bool = int(group.actor) == int(data.enhanced_actor)
	if state.get("kind") == "campaign":
		enhanced = enhanced or int(state.chapter) == int(data.enhanced_chapter)
		enhanced = (
			enhanced
			or (
				int(state.chapter) == int(data.special_chapter)
				and int(group.actor) == int(data.special_actor)
			)
		)
	return float(data.enhanced_rate if enhanced else data.normal_rate)


static func steer_heading(
	heading: Vector3, desired: Vector3, seconds: float, rate: float, snap_distance: float
) -> Vector3:
	if seconds <= 0 or not is_finite(seconds) or desired.length_squared() < .000001:
		return heading
	var target := desired.normalized()
	var angle := heading.angle_to(target)
	if angle < .000001:
		return target
	if PI - angle < .000001:
		# Opposite directions alone provide no turning plane. A lateral target
		# direction is needed instead of an arbitrary camera-based turning axis.
		return heading
	# Independent spherical integration of bounded direction correction. The
	# angular rate is gain*cos(error/2), rather than generic exponential pursuit.
	var integral := log(tan(PI * .25 + angle * .25))
	var remaining := 4.0 * atan(exp(maxf(0.0, integral - rate * seconds * .5))) - PI
	var result := heading.slerp(target, clampf(1.0 - remaining / angle, 0, 1)).normalized()
	var error := (result - target).abs()
	return target if error.x + error.y + error.z <= snap_distance else result


static func mount_origin(
	position: Vector3, heading: Vector3, gun: Dictionary, up: Vector3 = Vector3.ZERO
) -> Vector3:
	if not gun.has("mount_offset"):
		return position
	var basis := Mission.Frame.axes(heading, up)
	return position + basis * Mission.point(gun.mount_offset)


static func firing_aligned(
	heading: Vector3,
	offset: Vector3,
	motion: Dictionary,
	aim_direction: Vector3 = Vector3.ZERO,
	up: Vector3 = Vector3.ZERO
) -> bool:
	if offset.length_squared() < .000001:
		return false
	var extent := offset.abs()
	var limit := Vector3.ONE * float(motion.fire_half_width)
	if extent[extent.max_axis_index()] > limit.x:
		return false
	var basis := Mission.Frame.axes(heading, up)
	var direction := offset if aim_direction == Vector3.ZERO else aim_direction
	var local := basis.inverse() * direction.normalized()
	return (
		local.z < 0
		and absf(local.x) < float(motion.aim_sine)
		and absf(local.y) < float(motion.aim_sine)
	)


static func advance_turret(
	group: Dictionary,
	actor: Dictionary,
	index: int,
	candidates: Array,
	seconds: float,
	combat: Dictionary,
	library,
	weapons: Dictionary
) -> void:
	if actor.hp <= 0:
		return
	var position := Combat.vector(actor.position)
	var tracking: Dictionary = group.tracking
	var target := nearest_enemy(candidates, group.get("team", "enemy"), position, INF)
	if target.is_empty():
		return
	var offset: Vector3 = target.position - position
	var extent := offset.abs()
	if not actor.awake:
		actor.awake = extent[extent.max_axis_index()] <= float(tracking.wake_half_width)
		return
	var weapon := -1 - index
	var gun: Dictionary = weapons.get(weapon, {})
	if gun.is_empty() or offset.length_squared() < .001:
		return
	var heading := Combat.vector(actor.heading)
	# Source turrets fire along their existing mount direction, before tracking
	# the opponent's current position. Predictive leading
	# incorrectly compensated for the opponent moving during slow bolt travel.
	if turret_firing_aligned(heading, offset, tracking):
		if Combat.fire(combat, weapon, position, heading, library, weapons):
			actor.shots = int(actor.shots) + 1
	var desired := offset.normalized()
	var angle := heading.angle_to(desired)
	if angle > .000001:
		heading = (
			heading
			. slerp(desired, minf(1, float(tracking.turn_rate) * seconds / angle))
			. normalized()
		)
	actor.heading = Combat.packed(heading)
	actor.up = Combat.packed(Mission.Frame.axes(heading).y)


static func turret_firing_aligned(heading: Vector3, offset: Vector3, tracking: Dictionary) -> bool:
	if offset.length_squared() < .000001:
		return false
	var extent := offset.abs()
	var limit := Vector3.ONE * float(tracking.range_half_width)
	if extent[extent.max_axis_index()] > limit.x:
		return false
	var basis := Basis.looking_at(
		heading, Vector3.RIGHT if absf(heading.dot(Vector3.UP)) > .99 else Vector3.UP
	)
	var local := basis.inverse() * offset.normalized()
	# Turrets have separate inclusive X/Y bounds, with no fighter-style Z gate.
	# A rear-aligned target can spend a shot in the mount's forward direction.
	return absf(local.x) <= float(tracking.aim_sine) and absf(local.y) <= float(tracking.aim_sine)


static func nearest_enemy(
	candidates: Array, team: String, position: Vector3, maximum: float
) -> Dictionary:
	var result := {}
	var nearest := maximum * maximum
	for candidate in candidates:
		if candidate.team == team:
			continue
		var distance: float = position.distance_squared_to(candidate.position)
		if distance < nearest:
			result = candidate
			nearest = distance
	return result


static func route_direction(
	group: Dictionary, actor: Dictionary, position: Vector3, seconds: float
) -> Vector3:
	# Native waypoint capture avoids overshooting or circling a reached point.
	# This threshold is steering policy; route coordinates come from the IPA.
	var capture := maxf(8, float(actor.fighter_motion.speed) * seconds)
	while int(actor.route_stage) < group.route.size():
		var offset := Mission.point(group.route[int(actor.route_stage)]) - position
		if offset.length() > capture:
			return offset
		actor.route_stage = int(actor.route_stage) + 1
	return Vector3.ZERO
