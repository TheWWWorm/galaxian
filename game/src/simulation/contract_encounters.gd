extends RefCounted
const Contracts = preload("res://src/simulation/contracts.gd")
const Combat = preload("res://src/simulation/combat.gd")
## Independently generated native encounter definitions. Parameters are imported
## declarations; clients and payment terms belong to the selected board offer.


static func hunt(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if not valid_parameters(parameters, library):
		return {}
	if not valid_offer(library, parameters, offer, rank):
		return {}
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var total := (
		int(
			Contracts.f32(
				(
					Contracts.f32(float(tier) / float(parameters.count_divisor))
					* float(parameters.count_factor)
				)
			)
		)
		+ int(parameters.count_base)
	)
	if total < 1 or total > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var center := []
	for axis in parameters.route_bounds:
		center.append(random.randi_range(int(axis[0]), int(axis[1])))
	var definition := {
		"route": [center],
		"groups": [],
		"deadline_ms": 0,
		"success": {"kind": "enemy_destroyed", "index": 0},
		"radio": radio(parameters.radio, offer, random),
		"scenery": []
	}
	if random.randi_range(0, 1) == 0:
		definition.scenery.append(parameters.asteroids.duplicate(true))
	else:
		definition["fog"] = parameters.fog.duplicate(true)
	var primary := choose(parameters.target_actors, random)
	for index in total:
		var actor := primary
		if index > 0:
			actor = (
				choose(parameters.target_actors, random)
				if offer.client.race == parameters.escort_terran_race
				else int(parameters.escort_actor)
			)
		var base: int = parameters.target_hull_base + int(offer.difficulty) + region * rank
		var adjustment: float = parameters.difficulty - parameters.difficulty_offset
		if index > 0:
			var factor := maxi(
				int(parameters.factory_minimum),
				int(Contracts.f32(float(offer.difficulty) / float(parameters.factory_divisor)))
			)
			base = (
				int(library.content.tables.actor_hull[actor]) * factor
				+ rank * int(parameters.factory_rank_scale)
			)
			adjustment = parameters.difficulty - parameters.factory_offset
		var hull := int(
			Contracts.f32(
				Contracts.f32(float(base)) + Contracts.f32(Contracts.f32(float(base)) * adjustment)
			)
		)
		definition.groups.append(
			{
				"actor": actor,
				"count": 1,
				"center": center.duplicate(),
				"scatter": parameters.scatter.duplicate(true),
				"scatter_divisor": int(parameters.scatter_divisor),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": hull,
				"motion": parameters.combat.motion.duplicate(true),
				"weapon": weapon(parameters, actor, region)
			}
		)
	return definition if library.valid_mission(definition) else {}


static func valid_offer(library, parameters: Dictionary, offer: Dictionary, rank: int) -> bool:
	for key in ["type", "tier", "difficulty", "reward", "origin_station"]:
		if not Combat.integer(offer.get(key)):
			return false
	if not offer.get("special") is bool:
		return false
	if (
		not parameters.types.any(func(kind): return kind == offer.get("type"))
		or rank <= 0
		or not offer.get("client") is Dictionary
	):
		return false
	var origin := int(offer.get("origin_station", -1))
	if origin < 0 or origin >= library.stations.size():
		return false
	var station: Dictionary = library.station_definition(origin)
	var region := int(station.quadrant)
	var terms := Contracts.terms(
		library.content.contracts,
		region,
		int(offer.type),
		int(offer.tier),
		offer.special,
		int(offer.reward)
	)
	if terms.is_empty():
		return false
	for key in terms:
		if terms[key] != offer.get(key):
			return false
	if (
		not Combat.integer(offer.client.get("race"))
		or offer.client.race < 0
		or offer.client.race >= library.content.contracts.client_race_count
		or not Combat.integer(offer.client.get("portrait"))
		or offer.client.portrait < 0
		or offer.client.portrait >= library.content.radio_ui.portraits.size()
	):
		return false
	if region >= parameters.relative_divisors.size():
		return false
	return true


static func transport(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_transport_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var total := (
		region
		+ int(parameters.count_base)
		+ int(
			Contracts.f32(
				(
					Contracts.f32(float(tier) / float(parameters.count_divisor))
					* float(parameters.count_factor)
				)
			)
		)
	)
	if total < 1 or total > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var route := []
	for waypoint in int(parameters.route_axes.size() / 3):
		var point := []
		for axis in 3:
			var rule: Dictionary = parameters.route_axes[waypoint * 3 + axis]
			var value := int(rule.base)
			for bound in rule.rolls:
				value += random.randi_range(0, int(bound) - 1)
			point.append(value)
		route.append(point)
	var definition := {
		"route": route,
		"groups": [],
		"deadline_ms": 0,
		"success": parameters.success.duplicate(true),
		"radio": radio(common.radio, offer, random),
		"scenery": []
	}
	var scenery := random.randi_range(0, int(parameters.scenery_choices) - 1)
	if scenery == 0:
		var field: Dictionary = parameters.asteroids.duplicate(true)
		field.waypoint = random.randi_range(0, route.size() - 1)
		definition.scenery.append(field)
	elif scenery == 1:
		definition["fog"] = parameters.fog.duplicate(true)
		definition.fog.waypoint = random.randi_range(0, route.size() - 1)
	var heavy_remaining := region
	for index in total:
		var actor := int(parameters.default_actor)
		var heavy := false
		if offer.client.race == parameters.terran_race:
			actor = choose(common.target_actors, random)
		elif random.randi_range(0, int(parameters.actor_choices) - 1) != 0 and heavy_remaining > 0:
			heavy = true
			heavy_remaining -= 1
			actor = int(parameters.heavy_actor)
		var profile: Dictionary = parameters.heavy_combat if heavy else common.combat
		var gun: Dictionary = (
			profile.weapon.duplicate(true) if heavy else weapon(common, actor, region)
		)
		if heavy and common.freelance_guns.region_damage:
			gun.damage_rule.base = int(gun.damage_rule.base) + region
		definition.groups.append(
			{
				"actor": actor,
				"count": 1,
				"center": route[random.randi_range(0, route.size() - 1)].duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": factory_hull(common, library, actor, int(offer.difficulty), rank),
				"motion": profile.motion.duplicate(true),
				"weapon": gun
			}
		)
	if random.randi_range(0, int(parameters.deadline_choices) - 1) <= parameters.deadline_threshold:
		definition.deadline_ms = int(parameters.deadline_ms)
		definition["failure_text"] = int(parameters.failure_text)
	return definition if library.valid_mission(definition) else {}


static func battle(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_battle_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var rule: Dictionary = parameters.variants.filter(func(value): return value.type == offer.type)[0]
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var total := (
		region
		+ int(rule.count_base)
		+ int(
			Contracts.f32(
				Contracts.f32(float(tier) / float(rule.count_divisor)) * float(rule.count_factor)
			)
		)
	)
	if total < 1 or total > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var route := []
	for waypoint in int(rule.route_axes.size() / 3):
		var point := []
		for axis in 3:
			var coordinate: Dictionary = rule.route_axes[waypoint * 3 + axis]
			var value := int(coordinate.base)
			for bound in coordinate.rolls:
				value += random.randi_range(0, int(bound) - 1)
			point.append(value)
		route.append(point)
	var result := {
		"route": route,
		"groups": [],
		"deadline_ms": 0,
		"success": rule.success.duplicate(true),
		"radio": radio(common.radio, offer, random),
		"scenery": []
	}
	var scenery := random.randi_range(0, int(rule.scenery_choices) - 1)
	if scenery == 0:
		var field: Dictionary = rule.asteroids.duplicate(true)
		field.waypoint = random.randi_range(0, route.size() - 1)
		result.scenery.append(field)
	elif scenery == 1:
		result["fog"] = rule.fog.duplicate(true)
		result.fog.waypoint = random.randi_range(0, route.size() - 1)
	var has_wingman: bool = (
		random.randi_range(0, int(rule.wingman_chance[1]) - 1) < rule.wingman_chance[0]
	)
	var quota := region
	for index in total:
		var actor := int(rule.actor)
		var heavy := false
		if rule.selection == "regional":
			if offer.client.race == rule.terran_race:
				actor = choose(common.target_actors, random)
			elif random.randi_range(0, int(rule.actor_choices) - 1) != 0 and quota > 0:
				heavy = true
				quota -= 1
				actor = int(rule.heavy_actor)
		var profile: Dictionary = rule.heavy_combat if heavy else common.combat
		var gun: Dictionary = (
			profile.weapon.duplicate(true) if heavy else weapon(common, actor, region)
		)
		if heavy and common.freelance_guns.region_damage:
			gun.damage_rule.base = int(gun.damage_rule.base) + region
		result.groups.append(
			{
				"actor": actor,
				"count": 1,
				"center": route[random.randi_range(0, route.size() - 1)].duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": factory_hull(common, library, actor, int(offer.difficulty), rank),
				"motion": profile.motion.duplicate(true),
				"weapon": gun
			}
		)
	if has_wingman:
		result = wingman(library, parameters.wingman, offer, rank, random, result)
	return result if not result.is_empty() and library.valid_mission(result) else {}


static func valid_battle_parameters(value: Variant, library) -> bool:
	if not value is Dictionary or value.get("family") != "enemy_group":
		return false
	if not valid_wingman_parameters(value.get("wingman"), library):
		return false
	for key in ["types", "relative_divisors"]:
		if not value.get(key) is Array or value[key].is_empty() or value[key].size() > 64:
			return false
		if not value[key].all(func(number): return Combat.integer(number) and number >= 0):
			return false
	if (
		value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(number): return number <= 0)
		or not value.get("variants") is Array
		or value.variants.size() != value.types.size()
	):
		return false
	var seen := []
	for rule in value.variants:
		if not rule is Dictionary or rule.get("selection") not in ["fixed", "regional"]:
			return false
		if (
			not Combat.integer(rule.get("type"))
			or rule.type < 0
			or rule.type >= library.content.contracts.types.size()
			or seen.has(int(rule.type))
			or not value.types.any(func(kind): return kind == rule.type)
		):
			return false
		seen.append(int(rule.type))
		if (
			not rule.get("route_axes") is Array
			or rule.route_axes.is_empty()
			or rule.route_axes.size() > 192
			or rule.route_axes.size() % 3 != 0
		):
			return false
		for axis in rule.route_axes:
			if (
				not axis is Dictionary
				or not Combat.integer(axis.get("base"))
				or absf(axis.base) > 1000000
			):
				return false
			if not axis.get("rolls") is Array or axis.rolls.size() > 8:
				return false
			if not axis.rolls.all(
				func(bound): return Combat.integer(bound) and bound > 0 and bound <= 1000000
			):
				return false
		for key in ["count_base", "scenery_choices"]:
			if not Combat.integer(rule.get(key)) or rule[key] < 1 or rule[key] > 128:
				return false
		for key in ["count_divisor", "count_factor"]:
			if not Combat.number(rule.get(key)) or rule[key] <= 0 or rule[key] > 1000000:
				return false
		if (
			not Combat.integer(rule.get("actor"))
			or rule.actor < 0
			or rule.actor >= library.content.tables.actor_hull.size()
		):
			return false
		if not rule.get("wingman_chance") is Array or rule.wingman_chance.size() != 2:
			return false
		if not rule.wingman_chance.all(
			func(number): return Combat.integer(number) and number >= 0 and number <= 1000000
		):
			return false
		if rule.wingman_chance[1] < 1 or rule.wingman_chance[0] > rule.wingman_chance[1]:
			return false
		var count := int(rule.route_axes.size() / 3)
		if (
			not library.valid_field(rule.get("asteroids"), count)
			or not library.valid_fog(rule.get("fog"), count)
		):
			return false
		if rule.get("success") != {"kind": "enemies_destroyed"}:
			return false
		if rule.selection == "regional":
			for key in ["terran_race", "actor_choices", "heavy_actor"]:
				if not Combat.integer(rule.get(key)) or rule[key] < 0:
					return false
			if (
				rule.terran_race >= library.content.contracts.client_race_count
				or rule.actor_choices < 1
				or rule.actor_choices > 128
				or rule.heavy_actor >= library.content.tables.actor_hull.size()
			):
				return false
			if not rule.get("heavy_combat") is Dictionary:
				return false
			var sample := {
				"route": [[0, 0, 0]],
				"radio": [],
				"deadline_ms": 0,
				"success": rule.success,
				"groups":
				[
					{
						"actor": int(rule.heavy_actor),
						"count": 1,
						"center": [0, 0, 0],
						"scatter": [],
						"after_route": false,
						"behavior": "interceptor",
						"hull": 1,
						"motion": rule.heavy_combat.get("motion"),
						"weapon": rule.heavy_combat.get("weapon")
					}
				]
			}
			if not library.valid_mission(sample):
				return false
	return true


static func wingman(
	library,
	parameters: Dictionary,
	offer: Dictionary,
	rank: int,
	random: RandomNumberGenerator,
	definition: Dictionary
) -> Dictionary:
	if not valid_wingman_parameters(parameters, library) or not library.valid_mission(definition):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	if not valid_offer(
		library,
		{"types": [offer.get("type")], "relative_divisors": common.relative_divisors},
		offer,
		rank
	):
		return {}
	var matching: bool = offer.client.race == parameters.race
	var actor := int(parameters.actor) if matching else choose(common.target_actors, random)
	var gun: Dictionary = parameters.weapon.duplicate(true)
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	if common.freelance_guns.region_damage:
		gun.damage_rule.base = int(gun.damage_rule.base) + region
	var health := int(parameters.initial_hp)
	var result := definition.duplicate(true)
	result.groups.append(
		{
			"actor": actor,
			"count": 1,
			"team": "ally",
			"placement": "player_offset",
			"center":
			[
				int(parameters.offset) + random.randi_range(0, int(parameters.spread) - 1),
				int(parameters.offset) + random.randi_range(0, int(parameters.spread) - 1),
				int(parameters.ahead)
			],
			"scatter": [],
			"after_route": false,
			"behavior": "escort",
			"sleeping": false,
			"route": definition.route.duplicate(true),
			"hull": maxi(health, factory_hull(common, library, actor, int(offer.difficulty), rank)),
			"initial_hp": health,
			"motion": parameters.motion.duplicate(true),
			"weapon": gun
		}
	)
	if offer.client.portrait != parameters.preserve_client:
		if result.radio.is_empty():
			return {}
		result.radio[0] = {
			"text": choose(parameters.opening, random),
			"speaker": int(parameters.speaker if matching else parameters.other_speaker),
			"condition": "elapsed",
			"value": int(parameters.lead_ms)
		}
	return result if library.valid_mission(result) else {}


static func valid_wingman_parameters(value: Variant, library) -> bool:
	if not value is Dictionary or value.get("family") != "route_ally":
		return false
	for key in [
		"race",
		"actor",
		"speaker",
		"other_speaker",
		"preserve_client",
		"lead_ms",
		"spread",
		"initial_hp"
	]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 1000000:
			return false
	for key in ["offset", "ahead"]:
		if not Combat.integer(value.get(key)) or absf(value[key]) > 1000000:
			return false
	if (
		value.race >= library.content.contracts.client_race_count
		or value.actor >= library.content.tables.actor_hull.size()
		or value.spread < 1
		or value.initial_hp < 1
	):
		return false
	for key in ["speaker", "other_speaker", "preserve_client"]:
		if value[key] >= library.content.radio_ui.portraits.size():
			return false
	if not value.get("opening") is Array or value.opening.is_empty() or value.opening.size() > 128:
		return false
	if not value.opening.all(
		func(id): return Combat.integer(id) and id >= 0 and id < library.strings.size()
	):
		return false
	return library.valid_mission(
		{
			"route": [[0, 0, 10000]],
			"deadline_ms": 0,
			"radio": [],
			"success": {"kind": "enemies_destroyed"},
			"groups":
			[
				{
					"actor": int(value.actor),
					"count": 1,
					"team": "ally",
					"center": [0, 0, 0],
					"scatter": [],
					"after_route": false,
					"placement": "player_offset",
					"behavior": "escort",
					"route": [[0, 0, 10000]],
					"hull": int(value.initial_hp),
					"initial_hp": int(value.initial_hp),
					"motion": value.get("motion"),
					"weapon": value.get("weapon")
				}
			]
		}
	)


static func factory_hull(
	parameters: Dictionary, library, actor: int, difficulty: int, rank: int
) -> int:
	var factor := maxi(
		int(parameters.factory_minimum),
		int(Contracts.f32(float(difficulty) / float(parameters.factory_divisor)))
	)
	var base := (
		int(library.content.tables.actor_hull[actor]) * factor
		+ rank * int(parameters.factory_rank_scale)
	)
	var adjustment: float = parameters.difficulty - parameters.factory_offset
	return int(
		Contracts.f32(
			Contracts.f32(float(base)) + Contracts.f32(Contracts.f32(float(base)) * adjustment)
		)
	)


static func valid_transport_parameters(value: Variant, library) -> bool:
	if not value is Dictionary or value.get("family") != "ambushed_route":
		return false
	for key in ["types", "relative_divisors"]:
		if not value.get(key) is Array or value[key].is_empty() or value[key].size() > 64:
			return false
		if not value[key].all(func(number): return Combat.integer(number) and number >= 0):
			return false
	if (
		value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(number): return number <= 0)
		or value.types.any(func(kind): return kind >= library.content.contracts.types.size())
	):
		return false
	if (
		not value.get("route_axes") is Array
		or value.route_axes.is_empty()
		or value.route_axes.size() % 3 != 0
		or value.route_axes.size() > 192
	):
		return false
	for axis in value.route_axes:
		if (
			not axis is Dictionary
			or not Combat.integer(axis.get("base"))
			or absf(axis.base) > 1000000
		):
			return false
		if not axis.get("rolls") is Array or axis.rolls.size() > 8:
			return false
		if not axis.rolls.all(
			func(bound): return Combat.integer(bound) and bound > 0 and bound <= 1000000
		):
			return false
	for key in [
		"count_base",
		"terran_race",
		"actor_choices",
		"default_actor",
		"heavy_actor",
		"default_role",
		"heavy_role",
		"deadline_choices",
		"deadline_threshold",
		"deadline_ms",
		"failure_text",
		"scenery_choices"
	]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 86400000:
			return false
	for key in ["count_divisor", "count_factor"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if (
		value.count_base < 1
		or value.count_base > 128
		or value.scenery_choices < 2
		or value.scenery_choices > 128
		or value.actor_choices < 1
		or value.actor_choices > 128
		or value.deadline_choices < 1
		or value.deadline_choices > 1000000
		or value.deadline_threshold >= value.deadline_choices
		or value.deadline_ms < 1
		or value.failure_text >= library.strings.size()
		or value.terran_race >= library.content.contracts.client_race_count
	):
		return false
	for actor in [value.default_actor, value.heavy_actor]:
		if actor >= library.content.tables.actor_hull.size():
			return false
	var count := int(value.route_axes.size() / 3)
	if (
		not library.valid_field(value.get("asteroids"), count)
		or not library.valid_fog(value.get("fog"), count)
	):
		return false
	if (
		not value.get("heavy_combat") is Dictionary
		or not value.heavy_combat.get("weapon") is Dictionary
	):
		return false
	if not Combat.Guidance.valid_parameters(value.heavy_combat.weapon.get("guidance")):
		return false
	var sample := {
		"route": [[0, 0, 0]],
		"groups":
		[
			{
				"actor": int(value.heavy_actor),
				"count": 1,
				"center": [0, 0, 0],
				"scatter": library.content.contracts.hunt.scatter,
				"after_route": false,
				"behavior": "interceptor",
				"hull": 1,
				"sleeping": true,
				"motion": value.heavy_combat.get("motion"),
				"weapon": value.heavy_combat.weapon
			}
		],
		"deadline_ms": value.deadline_ms,
		"success": value.get("success"),
		"radio": []
	}
	return library.valid_mission(sample)


static func weapon(parameters: Dictionary, actor: int, region: int) -> Dictionary:
	var guns: Dictionary = parameters.freelance_guns
	var result: Dictionary = (
		(guns.alternate_weapon if actor == guns.alternate_actor else parameters.combat.weapon)
		. duplicate(true)
	)
	if guns.region_damage:
		result.damage_rule.base = int(result.damage_rule.base) + region
	return result


static func valid_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or not Combat.integer(value.get("scatter_divisor"))
		or value.scatter_divisor < 1
		or value.scatter_divisor > 1000000
	):
		return false
	if not value is Dictionary or value.get("family") != "designated_target":
		return false
	for key in ["types", "target_actors", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(number): return Combat.integer(number) and number >= 0)
		):
			return false
	if (
		value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(number): return number <= 0)
	):
		return false
	for kind in value.types:
		if kind >= library.content.contracts.types.size():
			return false
	for key in ["route_bounds", "scatter"]:
		if not value.get(key) is Array or value[key].size() != 3:
			return false
		for axis in value[key]:
			if (
				not axis is Array
				or axis.size() != 2
				or not axis.all(
					func(number): return Combat.integer(number) and absf(number) <= 10000000
				)
				or axis[1] < axis[0]
			):
				return false
	for key in ["count_divisor", "count_factor", "factory_divisor"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	for key in [
		"count_base",
		"target_hull_base",
		"factory_minimum",
		"factory_rank_scale",
		"escort_actor",
		"escort_terran_race"
	]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > 1000000:
			return false
	if (
		value.count_base < 1
		or value.count_base > 128
		or value.factory_minimum < 1
		or value.escort_terran_race >= library.content.contracts.client_race_count
	):
		return false
	for actor in value.target_actors + [value.escort_actor]:
		if actor >= library.content.tables.actor_hull.size():
			return false
		var resource := str(int(library.content.tables.actor_meshes[int(actor)]))
		if (
			not library.content.resources.has(resource)
			or not FileAccess.file_exists(
				library.root.path_join(library.content.resources[resource].path)
			)
		):
			return false
	for key in ["difficulty", "difficulty_offset", "factory_offset"]:
		if not Combat.number(value.get(key)) or absf(value[key]) > 100:
			return false
	if (
		1 + value.difficulty - value.difficulty_offset <= 0
		or 1 + value.difficulty - value.factory_offset <= 0
	):
		return false
	if (
		not value.get("combat") is Dictionary
		or not value.combat.get("motion") is Dictionary
		or not value.combat.get("weapon") is Dictionary
		or not value.get("asteroids") is Dictionary
		or not value.get("fog") is Dictionary
	):
		return false
	var guns: Variant = value.get("freelance_guns")
	if (
		not guns is Dictionary
		or not guns.get("region_damage") is bool
		or not Combat.integer(guns.get("alternate_actor"))
		or guns.alternate_actor < 0
		or guns.alternate_actor >= library.content.tables.actor_hull.size()
		or not guns.get("alternate_weapon") is Dictionary
	):
		return false
	# Exercise the same combat-profile validation used by campaign definitions.
	for profile in [value.combat.weapon, guns.alternate_weapon]:
		if not library.valid_mission(
			{
				"route": [[0, 0, 0]],
				"deadline_ms": 0,
				"success": {"kind": "route_finished"},
				"radio": [],
				"groups":
				[
					{
						"actor": int(guns.alternate_actor),
						"count": 1,
						"center": [0, 0, 0],
						"scatter": value.scatter,
						"after_route": false,
						"behavior": "interceptor",
						"sleeping": true,
						"hull": 1,
						"motion": value.combat.motion,
						"weapon": profile
					}
				]
			}
		):
			return false
	var messages: Variant = value.get("radio")
	if not library.valid_field(value.asteroids, 1) or not library.valid_fog(value.fog, 1):
		return false
	var text_count: int = library.strings.size()
	if not messages is Dictionary:
		return false
	for key in [
		"start", "success", "special_start", "special_messages", "special_success", "special_reply"
	]:
		if (
			not messages.get(key) is Array
			or messages[key].is_empty()
			or messages[key].size() > 128
			or not messages[key].all(
				func(index): return Combat.integer(index) and index >= 0 and index < text_count
			)
		):
			return false
	if messages.special_start.size() != library.content.contracts.types.size():
		return false
	for key in [
		"lead_ms", "special_time_base", "special_time_step", "special_time_jitter", "reply_speaker"
	]:
		if not Combat.integer(messages.get(key)) or messages[key] < 0 or messages[key] > 86400000:
			return false
	if (
		messages.special_time_jitter < 1
		or messages.reply_speaker >= library.content.radio_ui.portraits.size()
		or not messages.get("special_count") is Array
		or messages.special_count.size() != 2
		or not messages.special_count.all(
			func(number): return Combat.integer(number) and number > 0 and number < 128
		)
		or messages.special_count[0] > messages.special_count[1]
	):
		return false
	return true


static func choose(values: Array, random: RandomNumberGenerator) -> int:
	return int(values[random.randi_range(0, values.size() - 1)])


static func radio(
	parameters: Dictionary, offer: Dictionary, random: RandomNumberGenerator
) -> Array:
	var speaker := int(offer.client.portrait)
	var messages := []
	if offer.special:
		messages.append(
			{
				"text": int(parameters.special_start[int(offer.type)]),
				"speaker": speaker,
				"condition": "elapsed",
				"value": int(parameters.lead_ms)
			}
		)
		var count := random.randi_range(
			int(parameters.special_count[0]), int(parameters.special_count[1])
		)
		for index in count:
			messages.append(
				{
					"text": choose(parameters.special_messages, random),
					"speaker": speaker,
					"condition": "elapsed",
					"value":
					(
						int(parameters.special_time_base)
						+ index * int(parameters.special_time_step)
						+ random.randi_range(0, int(parameters.special_time_jitter) - 1)
					)
				}
			)
		messages.append(
			{
				"text": choose(parameters.special_success, random),
				"speaker": speaker,
				"condition": "mission_won",
				"value": 0
			}
		)
		messages.append(
			{
				"text": choose(parameters.special_reply, random),
				"speaker": int(parameters.reply_speaker),
				"condition": "message_shown",
				"value": messages.size() - 1
			}
		)
	else:
		messages.append(
			{
				"text": choose(parameters.start, random),
				"speaker": speaker,
				"condition": "elapsed",
				"value": int(parameters.lead_ms)
			}
		)
		messages.append(
			{
				"text": choose(parameters.success, random),
				"speaker": speaker,
				"condition": "mission_won",
				"value": 0
			}
		)
	return messages


static func clearance(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_clearance_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var debris := (
		int(parameters.debris_base)
		+ scaled_count(tier, parameters.debris_divisor, parameters.debris_factor)
	)
	var pirates := scaled_count(tier, parameters.pirate_divisor, parameters.pirate_factor)
	if debris < 1 or debris + pirates > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var definition := {
		"route": [],
		"deadline_ms": int(parameters.deadline_ms),
		"success": {"kind": parameters.success_kind, "count": debris},
		"radio": radio(common.radio, offer, random),
		"scenery": [],
		"groups":
		[
			{
				"actor": int(parameters.debris_actor),
				"count": debris,
				"center": parameters.center.duplicate(),
				"scatter": parameters.scatter.duplicate(true),
				"after_route": false
			}
		]
	}
	if pirates > 0:
		var actor := int(parameters.pirate_actor)
		definition.groups.append(
			{
				"actor": actor,
				"count": pirates,
				"center": parameters.center.duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": false,
				"hull": factory_hull(common, library, actor, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, actor, region)
			}
		)
	return definition if library.valid_mission(definition) else {}


static func scaled_count(tier: int, divisor: float, factor: float) -> int:
	return int(Contracts.f32(Contracts.f32(float(tier) / divisor) * factor))


static func valid_clearance_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "clearance"
		or value.get("success_kind") != "enemy_prefix_destroyed"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(v): return Combat.integer(v) and v >= 0)
		):
			return false
	if (
		value.types.any(func(kind): return kind >= library.content.contracts.types.size())
		or value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(v): return v < 1)
	):
		return false
	for key in ["debris_base", "debris_actor", "pirate_actor", "deadline_ms"]:
		if not Combat.integer(value.get(key)) or value[key] < 0:
			return false
	if (
		value.debris_base < 1
		or value.debris_base > 128
		or value.deadline_ms < 1
		or value.deadline_ms > 86400000
		or value.debris_actor >= library.content.tables.actor_hull.size()
		or value.pirate_actor >= library.content.tables.actor_hull.size()
	):
		return false
	for key in ["debris_divisor", "debris_factor", "pirate_divisor", "pirate_factor"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if not library.valid_point(value.get("center")):
		return false
	var sample := {
		"route": [],
		"deadline_ms": value.deadline_ms,
		"success": {"kind": value.success_kind, "count": 1},
		"radio": [],
		"groups":
		[
			{
				"actor": value.debris_actor,
				"count": 1,
				"center": value.center,
				"scatter": value.get("scatter"),
				"after_route": false
			}
		]
	}
	return library.valid_mission(sample)


static func minefield(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_minefield_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var center := []
	for axis in parameters.center_bounds:
		center.append(random.randi_range(int(axis[0]), int(axis[1])))
	var total := (
		int(parameters.total_base) + random.randi_range(0, int(parameters.total_variation) - 1)
	)
	var mines := total - int(parameters.defenders)
	var defender := int(parameters.defender_actor)
	var definition := {
		"route": [],
		"deadline_ms": 0,
		"scenery": [],
		"success": {"kind": parameters.success_kind, "count": mines},
		"radio": radio(common.radio, offer, random),
		"groups":
		[
			{
				"actor": int(parameters.mine_actor),
				"count": mines,
				"center": center,
				"scatter": parameters.scatter.duplicate(true),
				"after_route": false
			},
			{
				"actor": defender,
				"count": int(parameters.defenders),
				"center": center.duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": false,
				"hull": factory_hull(common, library, defender, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, defender, region)
			}
		]
	}
	return definition if library.valid_mission(definition) else {}


static func valid_minefield_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "minefield"
		or value.get("success_kind") != "enemy_prefix_destroyed"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(item): return Combat.integer(item) and item >= 0)
		):
			return false
	if (
		value.types.any(func(kind): return kind >= library.content.contracts.types.size())
		or value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(item): return item < 1)
	):
		return false
	for key in ["total_base", "total_variation", "defenders", "mine_actor", "defender_actor"]:
		if not Combat.integer(value.get(key)) or value[key] < 0:
			return false
	if (
		value.defenders != 1
		or value.total_base <= value.defenders
		or value.total_variation < 1
		or value.total_base + value.total_variation - 1 > 128
		or value.mine_actor != library.content.mine_behavior.actor
		or value.defender_actor >= library.content.tables.actor_hull.size()
	):
		return false
	if not value.get("center_bounds") is Array or value.center_bounds.size() != 3:
		return false
	for axis in value.center_bounds:
		if (
			not axis is Array
			or axis.size() != 2
			or not axis.all(func(item): return Combat.integer(item) and absf(item) <= 10000000)
			or axis[0] > axis[1]
		):
			return false
	return library.valid_mission(
		{
			"route": [],
			"deadline_ms": 0,
			"radio": [],
			"success": {"kind": value.success_kind, "count": 1},
			"groups":
			[
				{
					"actor": value.mine_actor,
					"count": 1,
					"center": [0, 0, 0],
					"scatter": value.get("scatter"),
					"after_route": false
				}
			]
		}
	)


static func asteroids(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_asteroid_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var pirates := int(
		Contracts.f32(
			(
				Contracts.f32(float(tier) / float(parameters.pirate_divisor))
				* float(parameters.pirate_factor)
			)
		)
	)
	if pirates < 0 or pirates > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var center := []
	for axis in parameters.center_bounds:
		center.append(random.randi_range(int(axis[0]), int(axis[1])))
	var field: Dictionary = parameters.field.duplicate(true)
	field.center = center
	var definition := {
		"route": [],
		"groups": [],
		"deadline_ms": 0,
		"scenery": [field],
		"payout_kind": parameters.payout_kind,
		"success": {"kind": parameters.success_kind, "duration_ms": int(parameters.duration_ms)},
		"radio": radio(common.radio, offer, random)
	}
	# An easy offer can have zero pirates. Survival still requires the full timer.
	if pirates > 0:
		var actor := int(parameters.pirate_actor)
		definition.groups.append(
			{
				"actor": actor,
				"count": pirates,
				"center": center.duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": false,
				"hull": factory_hull(common, library, actor, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, actor, region)
			}
		)
	return definition if library.valid_mission(definition) else {}


static func valid_asteroid_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "asteroids"
		or value.get("success_kind") != "time_survived"
		or value.get("payout_kind") != "finished_asteroids"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(item): return Combat.integer(item) and item >= 0)
		):
			return false
	if (
		value.types.any(func(kind): return kind >= library.content.contracts.types.size())
		or value.types.any(
			func(kind): return library.content.contracts.types[kind].reward_unit != "per_target"
		)
		or value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(item): return item < 1)
	):
		return false
	for key in ["pirate_divisor", "pirate_factor"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if (
		not Combat.integer(value.get("pirate_actor"))
		or value.pirate_actor < 0
		or value.pirate_actor >= library.content.tables.actor_hull.size()
		or not Combat.integer(value.get("duration_ms"))
		or value.duration_ms <= 0
		or value.duration_ms > 86400000
	):
		return false
	if not value.get("center_bounds") is Array or value.center_bounds.size() != 3:
		return false
	for axis in value.center_bounds:
		if (
			not axis is Array
			or axis.size() != 2
			or not axis.all(func(item): return Combat.integer(item) and absf(item) <= 10000000)
			or axis[0] > axis[1]
		):
			return false
	return library.valid_field(value.get("field"), 0) and value.field.has("destruction")


static func escort(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_escort_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var fraction := Contracts.f32(float(tier) / float(parameters.count_divisor))
	var count := region + int(parameters.count_base) + int(Contracts.f32(fraction + fraction))
	if count < 1 or count > 128:
		return {}
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var route := []
	for bounds in parameters.route_bounds:
		route.append(sample_bounds(bounds, random))
	var definition := {
		"route": [],
		"groups": [],
		"scenery": [],
		"deadline_ms": 0,
		"success": {"kind": parameters.success_kind, "duration_ms": int(parameters.duration_ms)},
		"failure": {"kind": parameters.failure_kind},
		"failure_text": int(parameters.failure_text)
	}
	var scenery := random.randi_range(0, int(parameters.scenery_choices) - 1)
	if scenery == parameters.asteroid_choice:
		var field: Dictionary = parameters.field.duplicate(true)
		field.center = route[random.randi_range(0, route.size() - 1)].duplicate()
		definition.scenery.append(field)
	elif scenery == parameters.fog_choice:
		definition["fog"] = parameters.fog.duplicate(true)
		definition.fog.center = route[random.randi_range(0, route.size() - 1)].duplicate()
	var fleet: Dictionary = parameters.fleets.filter(func(item): return item.race == -1)[0]
	for candidate in parameters.fleets:
		if candidate.race == offer.client.race:
			fleet = candidate
			break
	var attacker := int(fleet.attacker_actor)
	for index in count:
		definition.groups.append(
			{
				"actor": attacker,
				"count": 1,
				"center": route[random.randi_range(0, route.size() - 1)].duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": factory_hull(common, library, attacker, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, attacker, region)
			}
		)
	# Each transport shares one jittered origin. Its source formation offset is
	# relative to the player; the temporary attack route does not guide the convoy.
	var origin := sample_bounds(parameters.jitter, random)
	var base := Contracts.f32(
		float(rank * int(parameters.rank_factor) + region * int(parameters.region_factor))
	)
	var adjustment := Contracts.f32(float(common.difficulty) - float(parameters.difficulty_offset))
	var hull := int(Contracts.f32(base - Contracts.f32(base * adjustment)))
	for offset in parameters.formation:
		definition.groups.append(
			{
				"actor": int(fleet.cargo_actor),
				"count": 1,
				"team": "ally",
				"placement": "player_offset",
				"center": [origin[0] + offset[0], origin[1] + offset[1], origin[2] + offset[2]],
				"scatter": [],
				"after_route": false,
				"sleeping": false,
				"behavior": "transit",
				"velocity": [0, 0, -float(parameters.speed)],
				"hull": hull,
				"collisions": fleet.collisions.duplicate(true)
			}
		)
	definition["radio"] = radio(common.radio, offer, random)
	return definition if library.valid_mission(definition) else {}


static func sample_bounds(bounds: Array, random: RandomNumberGenerator) -> Array:
	var result := []
	for axis in bounds:
		result.append(random.randi_range(int(axis[0]), int(axis[1])))
	return result


static func valid_spawn_bounds(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for axis in value:
		if (
			not axis is Array
			or axis.size() != 2
			or not axis.all(func(item): return Combat.integer(item) and absf(item) <= 10000000)
			or axis[0] > axis[1]
		):
			return false
	return true


static func valid_escort_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "escort"
		or value.get("success_kind") != "time_survived"
		or value.get("failure_kind") != "allies_destroyed"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(item): return Combat.integer(item) and item >= 0)
		):
			return false
	if (
		value.types.any(func(kind): return kind >= library.content.contracts.types.size())
		or value.types.any(
			func(kind): return library.content.contracts.types[kind].reward_unit != "fixed"
		)
		or value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(item): return item < 1)
	):
		return false
	for key in ["count_base", "rank_factor", "region_factor", "scenery_choices", "duration_ms"]:
		if not Combat.integer(value.get(key)) or value[key] <= 0 or value[key] > 86400000:
			return false
	for key in ["count_divisor", "speed"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	if (
		not Combat.number(value.get("difficulty_offset"))
		or absf(value.difficulty_offset) > 100
		or not Combat.integer(value.get("failure_text"))
		or value.failure_text < 0
		or value.failure_text >= library.strings.size()
	):
		return false
	for key in ["asteroid_choice", "fog_choice"]:
		if (
			not Combat.integer(value.get(key))
			or value[key] < 0
			or value[key] >= value.scenery_choices
		):
			return false
	if (
		value.asteroid_choice == value.fog_choice
		or value.scenery_choices > 128
		or not valid_spawn_bounds(value.get("jitter"))
	):
		return false
	if (
		not value.get("route_bounds") is Array
		or value.route_bounds.is_empty()
		or value.route_bounds.size() > 128
		or not value.route_bounds.all(valid_spawn_bounds)
	):
		return false
	if (
		not value.get("formation") is Array
		or value.formation.is_empty()
		or value.formation.size() > 128
		or not value.formation.all(library.valid_point)
	):
		return false
	if not value.get("fleets") is Array or value.fleets.is_empty() or value.fleets.size() > 64:
		return false
	var races := []
	for fleet in value.fleets:
		if (
			not fleet is Dictionary
			or not Combat.integer(fleet.get("race"))
			or fleet.race < -1
			or fleet.race >= library.content.contracts.client_race_count
			or races.has(fleet.race)
		):
			return false
		races.append(fleet.race)
		for key in ["cargo_actor", "attacker_actor"]:
			if (
				not Combat.integer(fleet.get(key))
				or fleet[key] < 0
				or fleet[key] >= library.content.tables.actor_hull.size()
			):
				return false
		if (
			not fleet.get("collisions") is Array
			or fleet.collisions.is_empty()
			or fleet.collisions.size() > 32
		):
			return false
		for box in fleet.collisions:
			if (
				not box is Dictionary
				or not library.valid_point(box.get("offset"))
				or not library.valid_point(box.get("size"))
				or not box.size.all(func(axis): return axis > 0)
			):
				return false
	return (
		races.any(func(race): return race == -1)
		and library.valid_field(value.get("field"), 0)
		and library.valid_fog(value.get("fog"), 0)
	)


static func intercept(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_intercept_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var center := sample_bounds(parameters.route_bounds, random)
	var count := random.randi_range(
		int(parameters.target_counts[0]), int(parameters.target_counts[1])
	)
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var fraction := Contracts.f32(float(tier) / float(parameters.count_divisor))
	var guards := region + int(parameters.count_base) + int(Contracts.f32(fraction + fraction))
	if count < 1 or count + guards > 128 or guards < 0:
		return {}
	var fleet: Dictionary = parameters.fleets.filter(func(value): return value.race == -1)[0]
	for candidate in parameters.fleets:
		if candidate.race == offer.client.race:
			fleet = candidate
			break
	var cargo := int(fleet.cargo_actor)
	var fighter := int(fleet.attacker_actor)
	var definition := {
		"route": [center],
		"groups": [],
		"scenery": [],
		"deadline_ms": 0,
		"success": {"kind": parameters.success_kind, "count": count},
		"radio": radio(common.radio, offer, random)
	}
	# Only the initial enemy prefix is billable mission work. Guardians and an
	# optional friendly pilot retain their own combat roles outside that prefix.
	definition.groups.append(
		{
			"actor": cargo,
			"count": count,
			"center": center.duplicate(),
			"scatter": parameters.scatter.duplicate(true),
			"after_route": false,
			"behavior": "stationary",
			"sleeping": true,
			"wake_half_width": float(parameters.wake_half_width),
			"collisions": fleet.collisions.duplicate(true),
			"hull": factory_hull(common, library, cargo, int(offer.difficulty), rank)
		}
	)
	if guards > 0:
		definition.groups.append(
			{
				"actor": fighter,
				"count": guards,
				"center": center.duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": factory_hull(common, library, fighter, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, fighter, region)
			}
		)
	var scenery := random.randi_range(0, int(parameters.scenery_choices) - 1)
	if scenery == parameters.asteroid_choice:
		definition.scenery.append(parameters.field.duplicate(true))
	elif scenery == parameters.fog_choice:
		definition["fog"] = parameters.fog.duplicate(true)
	if random.randi_range(0, int(parameters.wingman_chance[1]) - 1) < parameters.wingman_chance[0]:
		definition = wingman(
			library, library.content.contracts.battles.wingman, offer, rank, random, definition
		)
	return definition if not definition.is_empty() and library.valid_mission(definition) else {}


static func valid_intercept_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "intercept"
		or value.get("success_kind") != "enemy_prefix_destroyed"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if (
			not value.get(key) is Array
			or value[key].is_empty()
			or value[key].size() > 64
			or not value[key].all(func(item): return Combat.integer(item) and item >= 0)
		):
			return false
	if (
		value.types.any(func(kind): return kind >= library.content.contracts.types.size())
		or value.types.any(
			func(kind): return library.content.contracts.types[kind].reward_unit != "fixed"
		)
		or value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(item): return item < 1)
	):
		return false
	for key in ["route_bounds", "scatter"]:
		if not valid_spawn_bounds(value.get(key)):
			return false
	for key in ["target_counts", "wingman_chance"]:
		if (
			not value.get(key) is Array
			or value[key].size() != 2
			or not value[key].all(func(item): return Combat.integer(item) and item >= 0)
			or value[key][0] > value[key][1]
		):
			return false
	if (
		value.target_counts[0] < 1
		or value.target_counts[1] > 128
		or value.wingman_chance[1] < 1
		or value.wingman_chance[1] > 1000000
	):
		return false
	for key in ["count_base", "scenery_choices"]:
		if not Combat.integer(value.get(key)) or value[key] < 1 or value[key] > 128:
			return false
	for key in ["count_divisor", "wake_half_width"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	for key in ["asteroid_choice", "fog_choice"]:
		if (
			not Combat.integer(value.get(key))
			or value[key] < 0
			or value[key] >= value.scenery_choices
		):
			return false
	if (
		value.asteroid_choice == value.fog_choice
		or not value.get("fleets") is Array
		or value.fleets.is_empty()
		or value.fleets.size() > 64
	):
		return false
	var races := []
	for fleet in value.fleets:
		if (
			not fleet is Dictionary
			or not Combat.integer(fleet.get("race"))
			or fleet.race < -1
			or fleet.race >= library.content.contracts.client_race_count
			or races.has(fleet.race)
		):
			return false
		races.append(fleet.race)
		for key in ["cargo_actor", "attacker_actor"]:
			if (
				not Combat.integer(fleet.get(key))
				or fleet[key] < 0
				or fleet[key] >= library.content.tables.actor_hull.size()
			):
				return false
		if (
			not fleet.get("collisions") is Array
			or fleet.collisions.is_empty()
			or fleet.collisions.size() > 32
		):
			return false
		for box in fleet.collisions:
			if (
				not box is Dictionary
				or not library.valid_point(box.get("offset"))
				or not library.valid_point(box.get("size"))
				or not box.size.all(func(axis): return axis > 0)
			):
				return false
	return (
		races.any(func(race): return race == -1)
		and library.valid_field(value.get("field"), 1)
		and library.valid_fog(value.get("fog"), 1)
	)


static func capture(
	library, parameters: Dictionary, offer: Dictionary, rank: int, seed_value: int
) -> Dictionary:
	if (
		not valid_capture_parameters(parameters, library)
		or not valid_offer(library, parameters, offer, rank)
	):
		return {}
	var common: Dictionary = library.content.contracts.hunt
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var route := []
	for bounds in parameters.route_bounds:
		route.append(sample_bounds(bounds, random))
	var region := int(library.station_definition(int(offer.origin_station)).quadrant)
	var tier := int(offer.difficulty) / int(parameters.relative_divisors[region])
	var fraction := Contracts.f32(float(tier) / float(parameters.count_divisor))
	var guards := region + int(parameters.count_base) + int(Contracts.f32(fraction + fraction))
	var fleet: Dictionary = parameters.fleets.filter(func(value): return value.race == -1)[0]
	for candidate in parameters.fleets:
		if candidate.race == offer.client.race:
			fleet = candidate
			break
	var mounts: Dictionary = fleet.turrets
	var count: int = mounts.positions.size()
	if guards < 0 or count + guards + 1 > 128:
		return {}
	# Sample the factory displacement once for the parent. Its hardpoints must
	# share that displacement rather than drawing independent ship positions.
	var center: Array = route[int(parameters.capital_waypoint)].duplicate()
	var scatter := sample_bounds(common.scatter, random)
	for axis in 3:
		center[axis] += scatter[axis]
	var definition := {
		"route": route,
		"groups": [],
		"scenery": [],
		"deadline_ms": 0,
		"enemy_goal": count + guards,
		"success": {"kind": parameters.success_kind, "count": count},
		"radio": radio(common.radio, offer, random)
	}
	for index in count:
		var position := []
		for axis in 3:
			position.append(center[axis] + mounts.positions[index][axis])
		var group := capture_turret(mounts, index, position, region, rank)
		if common.freelance_guns.region_damage:
			group.weapon.damage_rule.base = int(group.weapon.damage_rule.base) + region
		definition.groups.append(group)
	# Preserve the source enemy ordering: turret prefix, guards, inactive hull.
	for index in guards:
		var fighter := int(fleet.attacker_actor)
		definition.groups.append(
			{
				"actor": fighter,
				"count": 1,
				"center": route[random.randi_range(0, route.size() - 1)].duplicate(),
				"scatter": common.scatter.duplicate(true),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": factory_hull(common, library, fighter, int(offer.difficulty), rank),
				"motion": common.combat.motion.duplicate(true),
				"weapon": weapon(common, fighter, region)
			}
		)
	definition.groups.append(
		{
			"actor": int(fleet.capital_actor),
			"count": 1,
			"center": center,
			"positions": [center],
			"placement": "points",
			"scatter": [],
			"after_route": false,
			"behavior": "stationary",
			"combat_active": false,
			"source_scale": true,
			"collisions": fleet.collisions.duplicate(true),
			"hull":
			factory_hull(common, library, int(fleet.capital_actor), int(offer.difficulty), rank)
		}
	)
	var scenery := random.randi_range(0, int(parameters.scenery_choices) - 1)
	if scenery == parameters.asteroid_choice:
		definition.scenery.append(parameters.field.duplicate(true))
	elif scenery == parameters.fog_choice:
		definition["fog"] = parameters.fog.duplicate(true)
	if random.randi_range(0, int(parameters.wingman_chance[1]) - 1) < parameters.wingman_chance[0]:
		definition = wingman(
			library, library.content.contracts.battles.wingman, offer, rank, random, definition
		)
	return definition if not definition.is_empty() and library.valid_mission(definition) else {}


static func capture_turret(
	mounts: Dictionary, index: int, position: Array, region: int, rank: int
) -> Dictionary:
	return {
		"actor": int(mounts.actor),
		"count": 1,
		"center": position,
		"positions": [position],
		"placement": "points",
		"scatter": [],
		"after_route": false,
		"behavior": "turret",
		"sleeping": true,
		"source_scale": true,
		"render_mesh": mounts.render_mesh,
		"hull": int(mounts.hull_base) * (1 + region) + int(mounts.rank_factor) * rank,
		"facing": mounts.facing[index].duplicate(),
		"tracking": mounts.tracking.duplicate(true),
		"weapon": mounts.weapon.duplicate(true)
	}


static func valid_capture_parameters(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or value.get("family") != "capture"
		or value.get("success_kind") != "enemy_prefix_destroyed"
	):
		return false
	for key in ["types", "relative_divisors"]:
		if not value.get(key) is Array or value[key].is_empty() or value[key].size() > 64:
			return false
		if not value[key].all(func(item): return Combat.integer(item) and item >= 0):
			return false
	if value.types.any(func(kind): return kind >= library.content.contracts.types.size()):
		return false
	if value.types.any(
		func(kind): return library.content.contracts.types[kind].reward_unit != "fixed"
	):
		return false
	if (
		value.relative_divisors.size() != library.content.contracts.quadrant_difficulty.size()
		or value.relative_divisors.any(func(item): return item < 1)
	):
		return false
	if (
		not value.get("route_bounds") is Array
		or value.route_bounds.is_empty()
		or value.route_bounds.size() > 128
	):
		return false
	for bounds in value.route_bounds:
		if not valid_spawn_bounds(bounds):
			return false
	if (
		not Combat.integer(value.get("capital_waypoint"))
		or value.capital_waypoint < 0
		or value.capital_waypoint >= value.route_bounds.size()
	):
		return false
	for key in ["count_base", "scenery_choices"]:
		if not Combat.integer(value.get(key)) or value[key] < 1 or value[key] > 128:
			return false
	if (
		not Combat.number(value.get("count_divisor"))
		or value.count_divisor <= 0
		or value.count_divisor > 1000000
	):
		return false
	for key in ["asteroid_choice", "fog_choice"]:
		if (
			not Combat.integer(value.get(key))
			or value[key] < 0
			or value[key] >= value.scenery_choices
		):
			return false
	if value.asteroid_choice == value.fog_choice:
		return false
	if not value.get("wingman_chance") is Array or value.wingman_chance.size() != 2:
		return false
	if not value.wingman_chance.all(
		func(item): return Combat.integer(item) and item >= 0 and item <= 1000000
	):
		return false
	if value.wingman_chance[1] < 1 or value.wingman_chance[0] > value.wingman_chance[1]:
		return false
	if not value.get("fleets") is Array or value.fleets.is_empty() or value.fleets.size() > 64:
		return false
	var races := []
	for fleet in value.fleets:
		if not fleet is Dictionary or not Combat.integer(fleet.get("race")):
			return false
		if (
			fleet.race < -1
			or fleet.race >= library.content.contracts.client_race_count
			or races.has(fleet.race)
		):
			return false
		races.append(fleet.race)
		for key in ["capital_actor", "attacker_actor"]:
			if (
				not Combat.integer(fleet.get(key))
				or fleet[key] < 0
				or fleet[key] >= library.content.tables.actor_hull.size()
			):
				return false
		var mounts: Variant = fleet.get("turrets")
		if not mounts is Dictionary:
			return false
		for key in ["positions", "facing"]:
			if not mounts.get(key) is Array or mounts[key].is_empty() or mounts[key].size() > 128:
				return false
			if not mounts[key].all(func(point): return library.valid_point(point)):
				return false
		if (
			mounts.positions.size() != mounts.facing.size()
			or not Combat.integer(mounts.get("actor"))
		):
			return false
		for key in ["hull_base", "rank_factor"]:
			if not Combat.integer(mounts.get(key)) or mounts[key] < 1 or mounts[key] > 1000000:
				return false
		if (
			not mounts.get("render_mesh") is bool
			or not mounts.get("tracking") is Dictionary
			or not mounts.get("weapon") is Dictionary
		):
			return false
		var sample := {
			"route": [],
			"groups": [],
			"radio": [],
			"deadline_ms": 0,
			"success": {"kind": "enemy_prefix_destroyed", "count": mounts.positions.size()}
		}
		for index in mounts.positions.size():
			sample.groups.append(capture_turret(mounts, index, mounts.positions[index], 0, 1))
		sample.groups.append(
			{
				"actor": fleet.capital_actor,
				"count": 1,
				"center": [0, 0, 0],
				"scatter": [],
				"after_route": false,
				"behavior": "stationary",
				"combat_active": false,
				"hull": 1,
				"collisions": fleet.get("collisions")
			}
		)
		if not library.valid_mission(sample):
			return false
	return (
		races.any(func(race): return race == -1)
		and library.valid_field(value.get("field"), value.route_bounds.size())
		and library.valid_fog(value.get("fog"), value.route_bounds.size())
	)
