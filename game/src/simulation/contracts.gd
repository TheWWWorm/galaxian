extends RefCounted
const Combat = preload("res://src/simulation/combat.gd")
## Native board generation from imported terms and client declarations.
## An offer is not a playable encounter; accepting it requires mission support.


static func valid_rules(rules: Variant, text_count: int, portrait_count: int) -> bool:
	if (
		not rules is Dictionary
		or not rules.get("types") is Array
		or rules.types.is_empty()
		or rules.types.size() > 64
	):
		return false
	for key in ["offer_count", "tier_range", "rate_range"]:
		var bounds: Variant = rules.get(key)
		if (
			not bounds is Array
			or bounds.size() != 2
			or not bounds.all(
				func(value): return Combat.integer(value) and value > 0 and value <= 10000
			)
			or bounds[1] < bounds[0]
		):
			return false
	if (
		rules.offer_count[1] > 128
		or not Combat.number(rules.get("tier_divisor"))
		or rules.tier_divisor <= 0
		or rules.tier_range[1] >= rules.tier_divisor
		or not Combat.integer(rules.get("reward_step"))
		or rules.reward_step <= 0
		or rules.reward_step > 10000
		or rules.get("rounding") != "half_step_up_otherwise_down"
	):
		return false
	if (
		not rules.get("quadrant_difficulty") is Array
		or rules.quadrant_difficulty.is_empty()
		or rules.quadrant_difficulty.size() > 64
	):
		return false
	var quadrants: int = rules.quadrant_difficulty.size()
	for key in ["quadrant_difficulty", "minimum_rewards", "maximum_rewards"]:
		var values: Variant = rules.get(key)
		if (
			not values is Array
			or values.size() != quadrants
			or not values.all(
				func(value): return Combat.integer(value) and value > 0 and value <= 1000000
			)
		):
			return false
	for region in quadrants:
		if rules.minimum_rewards[region] > rules.maximum_rewards[region]:
			return false
	for kind in rules.types:
		if (
			not kind is Dictionary
			or not Combat.integer(kind.get("title"))
			or kind.title < 0
			or kind.title >= text_count
			or not Combat.integer(kind.get("description"))
			or kind.description < 0
			or kind.description >= text_count
			or not Combat.number(kind.get("reward_factor"))
			or kind.reward_factor <= 0
			or kind.reward_factor > 100
			or kind.get("reward_unit") not in ["fixed", "per_target"]
		):
			return false
	var special: Variant = rules.get("special")
	if not special is Dictionary:
		return false
	for key in ["chance_count", "chance_out_of", "limit", "portrait", "profession"]:
		if not Combat.integer(special.get(key)) or special[key] < 0:
			return false
	if (
		special.chance_out_of <= 0
		or special.chance_count > special.chance_out_of
		or special.limit > rules.offer_count[1]
		or special.portrait >= portrait_count
		or special.profession >= text_count
		or not Combat.number(special.get("reward_factor"))
		or special.reward_factor <= 0
		or special.reward_factor > 100
	):
		return false
	for key in ["client_race_count", "local_race_attempts", "male_choices", "female_choices"]:
		if not Combat.integer(rules.get(key)) or rules[key] <= 0 or rules[key] > 128:
			return false
	for gender in ["male", "female"]:
		var portraits: Variant = rules.get(gender + "_portraits")
		if (
			not portraits is Array
			or portraits.size() != rules.client_race_count * rules[gender + "_choices"]
			or not portraits.all(
				func(value): return Combat.integer(value) and value >= 0 and value < portrait_count
			)
		):
			return false
	return valid_clients(
		rules.get("clients"), rules.types.size(), int(rules.client_race_count), text_count
	)


static func valid_clients(clients: Variant, types: int, races: int, text_count: int) -> bool:
	if (
		not clients is Dictionary
		or not clients.get("special_name") is String
		or clients.special_name.strip_edges().is_empty()
		or clients.special_name.length() > 255
	):
		return false
	if (
		not clients.get("name_files") is Array
		or clients.name_files.size() != races
		or not clients.get("random_gender_races") is Array
		or clients.random_gender_races.size() > races
	):
		return false
	var seen := []
	for race in clients.random_gender_races:
		if not Combat.integer(race) or race < 0 or race >= races or seen.has(race):
			return false
		seen.append(race)
	for pair in clients.name_files:
		if not pair is Dictionary:
			return false
		for gender in ["male", "female"]:
			var path: Variant = pair.get(gender)
			if (
				not path is String
				or path.length() > 255
				or not path.begins_with("data/txt/")
				or not path.ends_with(".txt")
				or path.contains("..")
				or path.contains("\\")
			):
				return false
	if not clients.get("race_overrides") is Array or clients.race_overrides.size() > races * races:
		return false
	seen.clear()
	for override in clients.race_overrides:
		if not override is Dictionary:
			return false
		for key in ["station", "rolled", "race"]:
			if not Combat.integer(override.get(key)) or override[key] < 0 or override[key] >= races:
				return false
		var key := int(override.station) * races + int(override.rolled)
		if seen.has(key):
			return false
		seen.append(key)
	if not clients.get("professions") is Array or clients.professions.size() != types:
		return false
	for kind in clients.professions:
		if not kind is Array or kind.size() != races:
			return false
		for options in kind:
			if (
				not options is Array
				or options.is_empty()
				or options.size() > 64
				or not options.all(
					func(value): return Combat.integer(value) and value >= 0 and value < text_count
				)
			):
				return false
	return true


static func generate(library, station_id: int, seed_value: int) -> Array:
	if station_id < 0 or station_id >= library.stations.size():
		return []
	var rules: Dictionary = library.content.contracts
	var station: Dictionary = library.station_definition(station_id)
	if station.race < 0 or station.race >= rules.client_race_count:
		return []
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var result := []
	var special_count := 0
	for index in random.randi_range(int(rules.offer_count[0]), int(rules.offer_count[1])):
		var kind := random.randi_range(0, rules.types.size() - 1)
		var race := client_race(rules, int(station.race), random)
		var gender := "male"
		if rules.clients.random_gender_races.has(race) and random.randi_range(0, 1) == 1:
			gender = "female"
		var names: PackedStringArray = library.contract_names[
			rules.clients.name_files[race][gender]
		]
		var portrait_slot := (
			race * int(rules[gender + "_choices"])
			+ random.randi_range(0, int(rules[gender + "_choices"]) - 1)
		)
		var professions: Array = rules.clients.professions[kind][race]
		var client := {
			"name": names[random.randi_range(0, names.size() - 1)],
			"race": race,
			"portrait": int(rules[gender + "_portraits"][portrait_slot]),
			"profession": int(professions[random.randi_range(0, professions.size() - 1)])
		}
		var special := (
			special_count < int(rules.special.limit)
			and (
				random.randi_range(0, int(rules.special.chance_out_of) - 1)
				< int(rules.special.chance_count)
			)
		)
		if special:
			special_count += 1
			client.name = rules.clients.special_name
			client.portrait = int(rules.special.portrait)
			client.profession = int(rules.special.profession)
		var tier := random.randi_range(int(rules.tier_range[0]), int(rules.tier_range[1]))
		var rate := -1
		if rules.types[kind].reward_unit == "per_target":
			rate = random.randi_range(int(rules.rate_range[0]), int(rules.rate_range[1]))
		var offer := terms(rules, int(station.quadrant), kind, tier, special, rate)
		if offer.is_empty():
			return []
		offer["client"] = client
		offer["origin_station"] = station_id
		result.append(offer)
	return result


static func client_race(rules: Dictionary, station_race: int, random: RandomNumberGenerator) -> int:
	# Sample the native distribution directly: after N attempts, the local race
	# has probability 1 - ((R-1)/R)^N. All other races share the remainder.
	var races := int(rules.client_race_count)
	if races == 1:
		return 0
	var other_probability := pow(float(races - 1) / races, int(rules.local_race_attempts))
	var race := station_race
	if random.randf() < other_probability:
		race = random.randi_range(0, races - 2)
		if race >= station_race:
			race += 1
	for override in rules.clients.race_overrides:
		if override.station == station_race and override.rolled == race:
			return int(override.race)
	return race


static func terms(
	rules: Dictionary,
	region: int,
	kind: int,
	tier: int,
	special: bool = false,
	target_rate: int = -1
) -> Dictionary:
	if (
		region < 0
		or region >= rules.quadrant_difficulty.size()
		or kind < 0
		or kind >= rules.types.size()
		or tier < rules.tier_range[0]
		or tier > rules.tier_range[1]
	):
		return {}
	var definition: Dictionary = rules.types[kind]
	var rate: bool = definition.reward_unit == "per_target"
	if rate and (target_rate < rules.rate_range[0] or target_rate > rules.rate_range[1]):
		return {}
	# The supplied calculation rounds each arithmetic stage to binary32 before
	# truncation. Using double precision throughout changes boundary payouts.
	var fraction := f32(float(tier) / float(rules.tier_divisor))
	var amount := (
		int(
			f32(
				fraction * f32(float(rules.maximum_rewards[region] - rules.minimum_rewards[region]))
			)
		)
		+ int(rules.minimum_rewards[region])
	)
	amount = int(f32(f32(float(amount)) * float(definition.reward_factor)))
	if special:
		amount = int(f32(f32(float(amount)) * float(rules.special.reward_factor)))
	var step := int(rules.reward_step)
	var remainder := amount % step
	# This is the source's tie-up/floor policy, not conventional nearest rounding.
	amount = amount - remainder + (step if remainder * 2 == step else 0)
	return {
		"type": kind,
		"tier": tier,
		"difficulty": tier * int(rules.quadrant_difficulty[region]),
		"reward": target_rate if rate else amount,
		"reward_unit": definition.reward_unit,
		"special": special
	}


static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func board_seed(root_seed: int, visit: int, station: int) -> int:
	return (root_seed ^ (visit * 73856093) ^ (station * 19349663)) & 0x7fffffffffffffff


static func reference_offer(library, root_seed: int, reference: Variant) -> Dictionary:
	if not reference is Dictionary:
		return {}
	for key in ["station", "visit", "index"]:
		if (
			not Combat.integer(reference.get(key))
			or reference[key] < 0
			or reference[key] > 10000000
		):
			return {}
	if (
		reference.station >= library.stations.size()
		or reference.index >= library.content.contracts.offer_count[1]
	):
		return {}
	var offers := generate(
		library,
		int(reference.station),
		board_seed(root_seed, int(reference.visit), int(reference.station))
	)
	return offers[int(reference.index)] if reference.index < offers.size() else {}


static func reference_key(reference: Dictionary) -> String:
	return "%d:%d:%d" % [int(reference.station), int(reference.visit), int(reference.index)]


static func encounter_seed(root_seed: int, reference: Dictionary) -> int:
	return (
		board_seed(root_seed, int(reference.visit), int(reference.station))
		^ ((int(reference.index) + 1) * 83492791)
	)


static func supported(library, offer: Dictionary) -> bool:
	return (
		not offer.is_empty()
		and (
			library.content.contracts.capture.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.intercept.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.escort.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.asteroids.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.minefield.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.clearance.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.hunt.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.transport.types.any(
				func(kind): return kind == offer.get("type")
			)
			or library.content.contracts.battles.types.any(
				func(kind): return kind == offer.get("type")
			)
		)
	)


static func valid_receipts(library, root_seed: int, receipts: Variant, visit: int) -> bool:
	if not receipts is Array or receipts.size() > 100000:
		return false
	var previous_visit := -1
	for receipt in receipts:
		if not receipt is Dictionary or not Combat.integer(receipt.get("payment")):
			return false
		var offer := reference_offer(library, root_seed, receipt.get("reference"))
		if (
			not supported(library, offer)
			or receipt.reference.visit >= visit
			or receipt.reference.visit <= previous_visit
		):
			return false
		if offer.reward_unit == "per_target":
			if (
				not library.content.contracts.asteroids.types.any(
					func(kind): return kind == offer.type
				)
				or not Combat.integer(receipt.get("units"))
				or receipt.units < 0
				or receipt.units > library.content.contracts.asteroids.field.count
				or receipt.payment != int(offer.reward) * int(receipt.units)
			):
				return false
		elif receipt.payment != offer.reward:
			return false
		previous_visit = int(receipt.reference.visit)
	return true
