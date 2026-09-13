extends RefCounted
## The player's run-time build: which catalogue weapon occupies each mount
## category, how many remake-authored modifier stacks sit on it, and the gun
## profiles that result. Weapon, shield and hull numbers are read from the
## imported catalogue; the stacks only ever multiply them.
const Combat = preload("res://src/simulation/combat.gd")
const PlayerArmament = preload("res://src/simulation/player_armament.gd")
const Rules = preload("res://src/simulation/swarm_rules.gd")
## Muzzle indices live below PlayerArmament.LEGACY_MOUNT so added muzzles never
## collide with the identity reserved for pre-muzzle saved projectiles.
const MAX_MUZZLES := PlayerArmament.LEGACY_MOUNT
const CATEGORY_KEYS := ["damage", "reload", "muzzle", "reach", "velocity"]
const GLOBAL_KEYS := ["integrity", "agility", "recovery", "insight", "boost", "regeneration"]


static func ladders(library) -> Dictionary:
	## Weapon ladders come from the catalogue itself: the buyable items of each
	## category ordered by price. Nothing about the order is authored here.
	var result := {}
	for id in library.content.tables.buyable_equipment:
		var index := int(id)
		if index < 0 or index >= library.items.size():
			continue
		var category := int(library.items[index][1])
		if category > library.SHIELD_CATEGORY:
			continue
		if category < library.SHIELD_CATEGORY and library.weapon_ballistics(index).is_empty():
			continue
		if not result.has(category):
			result[category] = []
		result[category].append(index)
	for category in result:
		result[category].sort_custom(
			func(a, b): return int(library.items[a][6]) < int(library.items[b][6])
		)
	return result


static func roster_hull(library) -> float:
	var total := 0.0
	for row in library.ships:
		total += float(row[4])
	return total / maxf(1.0, float(library.ships.size()))


static func create(ship_id: int) -> Dictionary:
	var state := {"ship": ship_id, "shield": 0, "tier": {}, "level": 0, "hull_offered": -999}
	for key in CATEGORY_KEYS:
		state[key] = {}
	for key in GLOBAL_KEYS:
		state[key] = 0
	return state


static func categories(library, ship_id: int) -> Array:
	var result := []
	var mounts: Array = library.ship_definition(ship_id).mounts
	for category in mounts.size():
		if int(mounts[category]) > 0:
			result.append(category)
	return result


static func stack(state: Dictionary, key: String, category: int) -> int:
	return int(state.get(key, {}).get(category, 0))


static func tier(state: Dictionary, category: int) -> int:
	return int(state.get("tier", {}).get(category, 0))


static func weapon(state: Dictionary, library, category: int) -> int:
	var step := tier(state, category)
	if step <= 0:
		return -1
	var table: Array = ladders(library).get(category, [])
	return int(table[mini(step, table.size()) - 1])


static func owned(state: Dictionary, library) -> Array:
	var result := []
	for category in categories(library, int(state.get("ship", 0))):
		if tier(state, category) > 0:
			result.append(category)
	return result


static func percent(rules: Dictionary, key: String, stacks: int) -> float:
	var rule: Dictionary = rules.cards.modifiers[key]
	return 1.0 + float(rule.percent) * .01 * float(stacks)


static func compound(rules: Dictionary, key: String, stacks: int) -> float:
	var rule: Dictionary = rules.cards.modifiers[key]
	return pow(1.0 + float(rule.percent) * .01, float(stacks))


static func muzzle_count(state: Dictionary, rules: Dictionary, library, category: int) -> int:
	var id := weapon(state, library, category)
	if id < 0:
		return 0
	var declared: int = library.content.player_armament[str(id)].mounts.size()
	return mini(MAX_MUZZLES - 1, declared + stack(state, "muzzle", category))


static func max_hull(state: Dictionary, rules: Dictionary, library, arena_hull: float) -> float:
	## The arena hull from imported survival setup, scaled by this ship's own
	## imported toughness against the roster mean, then by integrity stacks.
	var ship: float = float(library.ships[int(state.ship)][4])
	var scaled := arena_hull * float(rules.hull_scale) * ship / maxf(1.0, roster_hull(library))
	return scaled * percent(rules, "integrity", int(state.get("integrity", 0)))


static func agility_scale(state: Dictionary, rules: Dictionary) -> float:
	return percent(rules, "agility", int(state.get("agility", 0)))


static func recovery_hull(state: Dictionary, rules: Dictionary, amounts: Array) -> float:
	## Hull banked on every kill, as a share of the archive's smallest repair
	## amount. Nothing is banked until the run takes a recovery card.
	if amounts.is_empty():
		return 0.0
	var smallest: float = float(amounts.min())
	var rule: Dictionary = rules.cards.modifiers["recovery"]
	return smallest * float(rule.percent) * .01 * float(int(state.get("recovery", 0)))


static func experience_scale(state: Dictionary, rules: Dictionary) -> float:
	return percent(rules, "insight", int(state.get("insight", 0)))


static func boost_scale(state: Dictionary, rules: Dictionary) -> float:
	return maxf(.05, compound(rules, "boost", int(state.get("boost", 0))))


static func shield_item(state: Dictionary, library) -> int:
	if int(state.get("shield", 0)) <= 0:
		return -1
	var table: Array = ladders(library).get(library.SHIELD_CATEGORY, [])
	if table.is_empty():
		return -1
	return int(table[mini(int(state.get("shield", 0)), table.size()) - 1])


static func shield_capacity(state: Dictionary, library) -> float:
	var id := shield_item(state, library)
	return 0.0 if id < 0 else float(library.items[id][7])


static func shield_interval(state: Dictionary, rules: Dictionary, library) -> float:
	var id := shield_item(state, library)
	if id < 0:
		return 0.0
	var base := float(library.items[id][8]) / 1000.0
	return maxf(.01, base / maxf(.01, percent(rules, "regeneration", int(state.get("regeneration", 0)))))


static func weapon_ids(state: Dictionary, rules: Dictionary, library, category: int) -> Array[int]:
	var result: Array[int] = []
	var id := weapon(state, library, category)
	if id < 0:
		return result
	for index in muzzle_count(state, rules, library, category):
		result.append(id + index * library.items.size())
	return result


static func guns(state: Dictionary, rules: Dictionary, library, target_ids: Array) -> Dictionary:
	## Rebuilt from the catalogue every time the build changes. Modifier stacks
	## scale damage, interval and lifetime; added muzzles repeat the last
	## declared mount. No property is written that the catalogue did not supply.
	var result := {}
	for category in owned(state, library):
		var id := weapon(state, library, category)
		var declaration: Dictionary = library.content.player_armament[str(id)]
		var catalogue: Dictionary = library.weapon_ballistics(id)
		var damage_scale := percent(rules, "damage", stack(state, "damage", category))
		var reload_scale := compound(rules, "reload", stack(state, "reload", category))
		var reach_scale := percent(rules, "reach", stack(state, "reach", category))
		var velocity_scale := percent(rules, "velocity", stack(state, "velocity", category))
		var mounts: Array = declaration.mounts
		var ballistics: Array = declaration.get("ballistics", [])
		var trigger := int(declaration.trigger_muzzle)
		var total := muzzle_count(state, rules, library, category)
		var interval := float(catalogue.interval)
		if not ballistics.is_empty():
			interval = float(ballistics[trigger].reload_ms) / 1000.0
		interval = maxf(.01, interval * reload_scale)
		var ids := weapon_ids(state, rules, library, category)
		for index in total:
			var source := mini(index, mounts.size() - 1)
			var gun: Dictionary = catalogue.duplicate(true)
			gun.damage = maxf(
				1.0, float(catalogue.damage) / int(declaration.get("damage_divisor", 1))
			)
			gun.pool_capacity = int(declaration.get("pool_capacity", 1))
			if not ballistics.is_empty():
				var parameters: Dictionary = ballistics[mini(index, ballistics.size() - 1)]
				gun.damage = float(parameters.damage)
				gun.pool_capacity = int(parameters.pool_capacity)
				gun.lifetime = float(parameters.lifetime_ms) / 1000.0
				gun.speed = float(parameters.speed_per_ms) * 20.0
			gun.damage = maxf(1.0, gun.damage * damage_scale)
			# Velocity keeps the reach it had: a faster round simply arrives
			# sooner, so muzzle speed and range stay two separate cards.
			gun.speed = float(gun.speed) * velocity_scale
			gun.lifetime = float(gun.lifetime) * reach_scale / velocity_scale
			gun.interval = interval
			gun.cooldown_limit = maxf(interval, float(catalogue.interval))
			gun.launch_speeds = [gun.speed]
			gun.trigger_weapon = ids[mini(trigger, ids.size() - 1)]
			gun.mount_offset = mounts[source].duplicate()
			gun.team = "ally"
			gun.sort = int(library.items[id][1])
			for property in ["projectile_model", "projectile_color", "trail", "guidance"]:
				if declaration.has(property):
					gun[property] = (
						declaration[property].duplicate(true)
						if declaration[property] is Dictionary
						else declaration[property]
					)
			if int(declaration.get("projectile_overlay", -1)) > 0:
				gun.projectile_overlay = int(declaration.projectile_overlay)
			if gun.has("guidance"):
				gun.guidance_target_ids = target_ids.duplicate()
			result[ids[index]] = gun
	return result


static func offers(state: Dictionary, rules: Dictionary, library) -> Array:
	## Every card the build could currently be shown, with its draw weight.
	var result := []
	var weights: Dictionary = rules.cards.weights
	var modifiers: Dictionary = rules.cards.modifiers
	var table := ladders(library)
	for category in categories(library, int(state.ship)):
		var ladder: Array = table.get(category, [])
		if ladder.is_empty():
			continue
		var step := tier(state, category)
		if step == 0:
			result.append(
				{
					"kind": "mount",
					"category": category,
					"item": int(ladder[0]),
					"weight": int(weights.mount)
				}
			)
		elif step < ladder.size():
			result.append(
				{
					"kind": "upgrade",
					"category": category,
					"item": int(ladder[step]),
					"weight": int(weights.upgrade)
				}
			)
		if step == 0:
			continue
		for key in CATEGORY_KEYS:
			var taken := stack(state, key, category)
			if taken >= int(modifiers[key].stacks):
				continue
			if key == "muzzle" and muzzle_count(state, rules, library, category) >= MAX_MUZZLES - 1:
				continue
			result.append(
				{
					"kind": "modifier",
					"modifier": key,
					"category": category,
					"item": weapon(state, library, category),
					"weight": maxi(1, int(weights.weapon_modifier) >> taken)
				}
			)
	var shields: Array = table.get(library.SHIELD_CATEGORY, [])
	if int(state.shield) < shields.size():
		result.append(
			{
				"kind": "shield",
				"category": library.SHIELD_CATEGORY,
				"item": int(shields[int(state.shield)]),
				"weight": int(
					weights.shield_first if int(state.shield) == 0 else weights.shield_next
				)
			}
		)
	for key in GLOBAL_KEYS:
		var taken := int(state[key])
		if taken >= int(modifiers[key].stacks):
			continue
		if key == "regeneration" and int(state.shield) <= 0:
			continue
		result.append(
			{
				"kind": "modifier",
				"modifier": key,
				"category": -1,
				"item": -1,
				"weight": maxi(1, int(weights.global_modifier) >> taken)
			}
		)
	if int(state.level) - int(state.hull_offered) >= int(rules.cards.hull_offer_interval):
		result.append({"kind": "hull", "category": -1, "item": -1, "weight": int(weights.hull)})
	return result


static func draw(state: Dictionary, rules: Dictionary, library, random: RandomNumberGenerator, hulls: Array) -> Array:
	## Weighted selection without replacement. A hull card resolves to one of the
	## unlocked hulls the run is not already flying.
	var pool: Array = offers(state, rules, library).filter(
		func(card): return card.kind != "hull" or not hull_targets(state, hulls).is_empty()
	)
	var chosen := []
	var wanted := mini(int(rules.cards.offers), pool.size())
	while chosen.size() < wanted and not pool.is_empty():
		var total := 0
		for card in pool:
			total += int(card.weight)
		var roll := random.randi_range(0, maxi(0, total - 1))
		var index := 0
		for position in pool.size():
			roll -= int(pool[position].weight)
			index = position
			if roll < 0:
				break
		var card: Dictionary = pool[index].duplicate(true)
		pool.remove_at(index)
		if card.kind == "hull":
			var targets := hull_targets(state, hulls)
			card.item = int(targets[random.randi_range(0, targets.size() - 1)])
			# One hull offer per level at most; the rest of the pool stays open.
			pool = pool.filter(func(other): return other.kind != "hull")
		chosen.append(card)
	return chosen


static func hull_targets(state: Dictionary, hulls: Array) -> Array:
	return hulls.filter(func(id): return int(id) != int(state.ship))


static func apply(state: Dictionary, rules: Dictionary, library, card: Dictionary) -> bool:
	match str(card.get("kind")):
		"mount", "upgrade":
			var category := int(card.category)
			var ladder: Array = ladders(library).get(category, [])
			var step := tier(state, category) + 1
			if step > ladder.size() or int(ladder[step - 1]) != int(card.item):
				return false
			state.tier[category] = step
		"shield":
			var shields: Array = ladders(library).get(library.SHIELD_CATEGORY, [])
			if int(state.shield) >= shields.size():
				return false
			if int(shields[int(state.shield)]) != int(card.item):
				return false
			state.shield = int(state.shield) + 1
		"modifier":
			var key := str(card.modifier)
			if not rules.cards.modifiers.has(key):
				return false
			var limit := int(rules.cards.modifiers[key].stacks)
			if str(rules.cards.modifiers[key].scope) == "global":
				if not GLOBAL_KEYS.has(key) or int(state[key]) >= limit:
					return false
				state[key] = int(state[key]) + 1
			else:
				var category := int(card.category)
				if not CATEGORY_KEYS.has(key) or tier(state, category) <= 0:
					return false
				if stack(state, key, category) >= limit:
					return false
				state[key][category] = stack(state, key, category) + 1
		"hull":
			var target := int(card.item)
			if target < 0 or target >= library.ships.size() or target == int(state.ship):
				return false
			state.ship = target
			state.hull_offered = int(state.level)
			drop_unsupported(state, library)
		_:
			return false
	return true


static func drop_unsupported(state: Dictionary, library) -> void:
	## A transferred hull keeps only the categories it can mount. Modifier stacks
	## stay behind on the category, dormant until that line is mounted again.
	var supported := categories(library, int(state.ship))
	for category in state.tier.keys():
		if not supported.has(int(category)):
			state.tier.erase(category)


static func valid(state: Variant, rules: Dictionary, library) -> bool:
	if not state is Dictionary:
		return false
	for key in ["ship", "shield", "level", "hull_offered"]:
		if not Combat.integer(state.get(key)):
			return false
	if int(state.ship) < 0 or int(state.ship) >= library.ships.size():
		return false
	var table := ladders(library)
	var shields: Array = table.get(library.SHIELD_CATEGORY, [])
	if int(state.shield) < 0 or int(state.shield) > shields.size():
		return false
	if int(state.level) < 0 or int(state.level) > 100000:
		return false
	var supported := categories(library, int(state.ship))
	if not state.get("tier") is Dictionary:
		return false
	for key in state.tier:
		var category := int(key)
		if not supported.has(category):
			return false
		var ladder: Array = table.get(category, [])
		if not Combat.integer(state.tier[key]) or int(state.tier[key]) < 1:
			return false
		if int(state.tier[key]) > ladder.size():
			return false
	for key in CATEGORY_KEYS:
		if not state.get(key) is Dictionary:
			return false
		var limit := int(rules.cards.modifiers[key].stacks)
		for category in state[key]:
			if not Combat.integer(state[key][category]):
				return false
			if int(state[key][category]) < 0 or int(state[key][category]) > limit:
				return false
	for key in GLOBAL_KEYS:
		var limit := int(rules.cards.modifiers[key].stacks)
		if not Combat.integer(state.get(key)) or int(state[key]) < 0 or int(state[key]) > limit:
			return false
	return true


static func normalize(state: Dictionary) -> Dictionary:
	## JSON keys return as strings. Restore integer category keys after a load.
	var result: Dictionary = state.duplicate(true)
	for key in ["ship", "shield", "level", "hull_offered"] + GLOBAL_KEYS:
		result[key] = int(result.get(key, 0))
	for key in ["tier"] + CATEGORY_KEYS:
		var source: Dictionary = result.get(key, {})
		var rebuilt := {}
		for category in source:
			rebuilt[int(category)] = int(source[category])
		result[key] = rebuilt
	return result
