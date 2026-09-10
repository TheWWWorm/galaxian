extends RefCounted
## Native score and reinforcement director. Content supplies every balance rule.
## Flight consumes the returned upgrade/respawn requests; no legacy code is run.
const Combat = preload("res://src/simulation/combat.gd")


static func create(parameters: Dictionary, seed_value: int) -> Dictionary:
	return {
		"score": 0,
		"combo": 0,
		"combo_elapsed_ms": 0.0,
		"timer_ms": 0.0,
		"phase": "upgrade",
		"active_count": int(parameters.initial_active),
		"upgrade_index": 0,
		"cycle": 0,
		"seed": seed_value
	}


static func award(state: Dictionary, parameters: Dictionary, value: int) -> Dictionary:
	var result := {"points": 0, "heal": 0}
	if value <= 0:
		return result
	var heal_index := 0
	for boundary in parameters.heal_limits:
		if value > boundary:
			heal_index += 1
	result.heal = int(parameters.heal_amounts[heal_index])
	if state.combo > 0 and state.combo_elapsed_ms <= parameters.combo_ms:
		state.combo += 1
		result.points = value + (value / 2) * int(state.combo)
	else:
		state.combo = 1
		result.points = value
	state.score += result.points
	state.combo_elapsed_ms = 0.0
	return result


static func advance(
	state: Dictionary, parameters: Dictionary, seconds: float, player_source: Vector3, slots: Array
) -> Dictionary:
	var result := {"upgrade": {}, "respawns": []}
	if seconds <= 0 or not is_finite(seconds):
		return result
	state.combo_elapsed_ms += seconds * 1000.0
	state.timer_ms += seconds * 1000.0
	if state.timer_ms <= parameters.tick_ms:
		return result
	# Each source update performs at most one alternating stage, resetting its
	# timer. A large simulation step must not create a burst of several waves.
	state.timer_ms = 0.0
	if state.phase == "upgrade":
		state.phase = "spawn"
		var index := int(state.upgrade_index)
		if (
			index < parameters.upgrades.score.size()
			and state.score >= parameters.upgrades.score[index]
		):
			for key in parameters.upgrades:
				result.upgrade[key] = parameters.upgrades[key][index]
			state.upgrade_index += 1
		return result
	state.phase = "upgrade"
	if (
		state.active_count < parameters.max_active
		and state.score > parameters.thresholds[int(state.active_count)]
	):
		state.active_count += 1
	var random := RandomNumberGenerator.new()
	# A separate, persisted native stream keeps score/respawn decisions stable
	# through save/load without coupling cosmetic randomness to combat.
	random.seed = int(state.seed) ^ (int(state.cycle) * 7919)
	state.cycle += 1
	for index in mini(int(state.active_count), slots.size()):
		var slot: Dictionary = slots[index]
		if slot.alive:
			continue
		var position := player_source
		var base: int = parameters.spawn_offset + parameters.spawn_factor * int(state.active_count)
		for axis in 3:
			var sign_value := (
				1
				if (
					random.randi_range(0, int(parameters.sign_choices) - 1)
					<= parameters.positive_sign_through
				)
				else -1
			)
			position[axis] += (
				sign_value * (base + random.randi_range(0, int(parameters.spawn_range) - 1))
			)
		var selected := int(slot.archetype)
		if (
			selected < parameters.promotable_count
			and parameters.ships.actor[selected] != parameters.fixed_actor
		):
			selected = random.randi_range(
				0, mini(int(state.active_count) - 1, int(parameters.promotion_cap)) - 1
			)
		result.respawns.append(
			{
				"index": index,
				"archetype": selected,
				"replace": selected != slot.archetype,
				"source_position": [position.x, position.y, position.z]
			}
		)
	return result


static func valid(parameters: Variant) -> bool:
	if not parameters is Dictionary:
		return false
	for key in [
		"type",
		"initial_active",
		"pool_size",
		"initial_archetype",
		"max_active",
		"tick_ms",
		"combo_ms",
		"spawn_range",
		"spawn_factor",
		"promotion_cap",
		"promotable_count",
		"fixed_actor",
		"sign_choices",
		"positive_sign_through"
	]:
		if (
			not Combat.integer(parameters.get(key))
			or parameters[key] < 0
			or parameters[key] > 1000000
		):
			return false
	if not Combat.integer(parameters.get("spawn_offset")):
		return false
	if (
		parameters.initial_active < 2
		or parameters.initial_active > parameters.max_active
		or parameters.max_active > parameters.pool_size
		or parameters.pool_size > 128
	):
		return false
	if (
		parameters.tick_ms <= 0
		or parameters.spawn_range <= 0
		or parameters.sign_choices <= parameters.positive_sign_through
	):
		return false
	if parameters.spawn_offset + parameters.spawn_factor * parameters.initial_active < 0:
		return false
	for name in ["ships", "upgrades"]:
		var data: Variant = parameters.get(name)
		if (
			not data is Dictionary
			or not data.get("score") is Array
			or data.score.is_empty()
			or data.score.size() > 128
		):
			return false
		for key in [
			"sort", "weapon", "damage", "projectile_speed", "reload_ms", "projectile_model", "score"
		]:
			if not data.get(key) is Array or data[key].size() != data.score.size():
				return false
			if not data[key].all(
				func(value): return Combat.integer(value) and value >= 0 and value <= 10000000
			):
				return false
		if not data.reload_ms.all(func(value): return value > 0):
			return false
	var ships: Dictionary = parameters.ships
	for key in ["actor", "hull", "initial_damage", "speed"]:
		if not ships.get(key) is Array or ships[key].size() != ships.score.size():
			return false
		if key == "speed":
			if not ships[key].all(
				func(value):
					return (
						(value is float or value is int)
						and is_finite(value)
						and value > 0
						and value <= 1000000
					)
			):
				return false
		elif not ships[key].all(
			func(value): return Combat.integer(value) and value >= 0 and value <= 10000000
		):
			return false
	if (
		parameters.initial_archetype >= ships.score.size()
		or parameters.promotion_cap < 1
		or parameters.promotion_cap > ships.score.size()
		or parameters.promotable_count > ships.score.size()
	):
		return false
	if (
		not parameters.get("thresholds") is Array
		or parameters.thresholds.size() != parameters.pool_size
	):
		return false
	var previous := -1
	for threshold in parameters.thresholds:
		if not Combat.integer(threshold) or threshold < previous:
			return false
		previous = int(threshold)
	previous = -1
	for threshold in parameters.upgrades.score:
		if threshold <= previous:
			return false
		previous = int(threshold)
	if (
		not parameters.get("heal_limits") is Array
		or not parameters.get("heal_amounts") is Array
		or parameters.heal_limits.size() + 1 != parameters.heal_amounts.size()
		or parameters.heal_limits.size() > 128
	):
		return false
	previous = -1
	for limit in parameters.heal_limits:
		if not Combat.integer(limit) or limit <= previous:
			return false
		previous = int(limit)
	return parameters.heal_amounts.all(
		func(value): return Combat.integer(value) and value >= 0 and value <= 1000000
	)


static func valid_state(state: Variant, parameters: Dictionary) -> bool:
	if not state is Dictionary or state.get("phase") not in ["upgrade", "spawn"]:
		return false
	for key in ["score", "combo", "upgrade_index", "active_count", "cycle", "seed"]:
		if not Combat.integer(state.get(key)) or (key != "seed" and state[key] < 0):
			return false
	for key in ["timer_ms", "combo_elapsed_ms"]:
		var value: Variant = state.get(key)
		if not (value is float or value is int) or not is_finite(value) or value < 0:
			return false
	return (
		state.timer_ms <= parameters.tick_ms
		and state.upgrade_index <= parameters.upgrades.score.size()
		and state.active_count >= parameters.initial_active
		and state.active_count <= parameters.max_active
	)


static func initial_player(setup: Dictionary, cycle: int) -> Dictionary:
	var selected := cycle if cycle >= 0 and cycle < int(setup.ship_count) else 0
	return {
		"ship_index": selected,
		"actor": int(setup.ship_order[selected]),
		"next_cycle": selected + 1,
		"hull": int(setup.hull),
		"shield": int(setup.shield_capacity)
	}


static func valid_setup(setup: Variant, library) -> bool:
	if not setup is Dictionary or setup.get("background") != "random":
		return false
	if (
		not Combat.number(setup.get("reserved_speed"))
		or setup.reserved_speed < 0
		or setup.reserved_speed > 1000000
	):
		return false

	for key in [
		"type",
		"ship_count",
		"hull",
		"shield_capacity",
		"shield_interval_ms",
		"scene_mode",
		"space_object_type",
		"reserved_hull",
		"reserved_actor",
		"reserved_score",
		"missile_score_above"
	]:
		if not Combat.integer(setup.get(key)) or setup[key] < 0 or setup[key] > 10000000:
			return false
	if (
		setup.ship_count < 1
		or setup.ship_count > library.ships.size()
		or setup.hull <= 0
		or setup.reserved_hull <= 0
		or setup.shield_interval_ms <= 0
	):
		return false
	if not setup.get("ship_order") is Array or setup.ship_order.size() != setup.ship_count:
		return false
	for index in setup.ship_order.size():
		if (
			not Combat.integer(setup.ship_order[index])
			or int(setup.ship_order[index]) != int(library.content.tables.buyable_ships[index])
		):
			return false
	if not setup.get("slots") is Array or setup.slots.size() != library.SHIELD_CATEGORY:
		return false
	if not setup.slots.all(func(n): return Combat.integer(n) and n >= 0 and n <= 16):
		return false
	if (
		not setup.get("equipment") is Array
		or setup.equipment.is_empty()
		or setup.equipment.size() > library.SHIELD_CATEGORY + 1
	):
		return false
	var categories := []
	for id in setup.equipment:
		if not Combat.integer(id) or id < 0 or id >= library.items.size():
			return false
		var category := int(library.items[int(id)][1])
		if category > library.SHIELD_CATEGORY or category < 0 or categories.has(category):
			return false
		if category < library.SHIELD_CATEGORY and setup.slots[category] <= 0:
			return false
		categories.append(category)
	if not Combat.valid_vector(setup.get("initial_offset")):
		return false
	if not setup.get("scatter") is Array or setup.scatter.size() != 3:
		return false
	for axis in setup.scatter:
		if (
			not axis is Array
			or axis.size() != 2
			or not axis.all(func(n): return Combat.integer(n) and absf(n) <= 10000000)
		):
			return false
		if axis[0] > axis[1]:
			return false
	return true


static func valid_armament(value: Variant, parameters: Dictionary) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			[
				"mounts",
				"pool_capacity",
				"lifetime",
				"upgrade_excluded_sort",
				"player_preserves_excluded",
				"enemy_preserves_excluded",
				"replacement_models"
			]
		)
	):
		return false
	if not value.mounts is Array or value.mounts.is_empty() or value.mounts.size() > 32:
		return false
	for mount in value.mounts:
		if not Combat.valid_vector(mount):
			return false
	if (
		not Combat.integer(value.pool_capacity)
		or value.pool_capacity < 1
		or value.pool_capacity > 4096
		or not Combat.number(value.lifetime)
		or value.lifetime <= 0
		or value.lifetime > 3600
		or not Combat.integer(value.upgrade_excluded_sort)
		or value.upgrade_excluded_sort < 0
		or not value.player_preserves_excluded is bool
		or not value.enemy_preserves_excluded is bool
	):
		return false
	return (
		value.replacement_models is Array
		and value.replacement_models.size() == parameters.ships.actor.size()
		and value.replacement_models.all(func(id): return Combat.integer(id) and id >= 0)
	)


static func enemy_guns(parameters: Dictionary, armament: Dictionary) -> Array:
	var index := int(parameters.initial_archetype)
	var ships: Dictionary = parameters.ships
	var result := []
	for mount in armament.mounts:
		result.append(
			{
				"team": "enemy",
				"sort": int(ships.sort[index]),
				"source_weapon": int(ships.weapon[index]),
				"damage": float(ships.initial_damage[index]),
				"speed": float(ships.projectile_speed[index]) * 20.0,
				"interval": float(ships.reload_ms[index]) / 1000.0,
				"lifetime": float(armament.lifetime),
				"pool_capacity": int(armament.pool_capacity),
				"mount_offset": mount.duplicate(),
				"projectile_model": int(ships.projectile_model[index])
			}
		)
	return result


static func promote_weapon(
	base: Dictionary, row: Dictionary, armament: Dictionary, player: bool
) -> Dictionary:
	var result := base.duplicate(true)
	var preserve: bool = (
		armament.player_preserves_excluded if player else armament.enemy_preserves_excluded
	)
	if preserve and base.get("sort", -1) == armament.upgrade_excluded_sort:
		return result
	# Keep the Gun's mounts, pool and lifetime. This is a property upgrade,
	# so a different source sort/model does not create guided projectile behavior.
	result.sort = int(row.sort)
	result.source_weapon = int(row.weapon)
	result.damage = float(row.damage)
	result.speed = float(row.projectile_speed) * 20.0
	result.interval = float(row.reload_ms) / 1000.0
	result.projectile_model = int(row.projectile_model)
	return result


static func replace_enemy_guns(
	current: Array, parameters: Dictionary, armament: Dictionary, archetype: int
) -> Array:
	var row := {}
	for key in ["sort", "weapon", "damage", "projectile_speed", "reload_ms"]:
		row[key] = parameters.ships[key][archetype]
	row.projectile_model = armament.replacement_models[archetype]
	var result := []
	for gun in current:
		result.append(promote_weapon(gun, row, armament, false))
	return result
