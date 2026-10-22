extends RefCounted
## Native stock generation uses imported eligibility rules and catalogue weights.
## Weighted sampling avoids the original rejection loops while preserving their
## accepted distribution. Stock belongs to the save, never to a presentation node.
## Like the source, every station has stock; the station menu alone decides
## whether its hangar opens (shop, campaign or the high-credit exception).


static func generate(
	library, station_id: int, chapter: int, campaign: bool, seed_value: int
) -> Array:
	var station: Dictionary = library.station_definition(station_id)
	var rules: Dictionary = library.content.economy
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var offers: Array = []
	if campaign:
		var chapter_index := clampi(chapter - 1, 0, library.content.chapters.size() - 1)
		for id in library.content.chapters[chapter_index].stock:
			add_offer(offers, "equipment", int(id), int(library.items[int(id)][6]))
	else:
		var candidates: Array = []
		for id in library.content.tables.buyable_equipment:
			var item: Dictionary = library.equipment(int(id))
			if item.quadrant > station.quadrant:
				continue
			if (
				int(id) > rules.exclusive_equipment_after
				and station.race != rules.exclusive_equipment_race
			):
				continue
			candidates.append(
				{"id": int(id), "weight": mini(item.occurrence + 1, int(rules.occurrence_scale))}
			)
		var count := mini(
			random.randi_range(int(rules.equipment_min), int(rules.equipment_max)),
			candidates.size()
		)
		for index in count:
			var choice := weighted_index(candidates, random)
			if choice < 0:
				break
			var id: int = candidates[choice].id
			add_offer(offers, "equipment", id, int(library.items[id][6]))
			candidates.remove_at(choice)
	var ships: Array = []
	for id in library.ships.size():
		var definition: Dictionary = library.ship_definition(id)
		if station.race == rules.exclusive_ship_race:
			if definition.actor == rules.exclusive_ship_actor:
				add_offer(offers, "ship", id, definition.price)
			continue
		if definition.quadrant > station.quadrant or definition.actor == rules.exclusive_ship_actor:
			continue
		if (
			definition.actor == rules.restricted_ship_actor
			and station.race != rules.restricted_ship_race
		):
			continue
		ships.append(
			{"id": id, "weight": mini(definition.occurrence + 1, int(rules.occurrence_scale))}
		)
	if station.race != rules.exclusive_ship_race:
		for index in random.randi_range(0, int(rules.ship_max)):
			var choice := weighted_index(ships, random)
			if choice < 0:
				break
			var id: int = ships[choice].id
			add_offer(offers, "ship", id, ship_price_at(library, id, int(station.technology)))
	return offers


static func add_offer(offers: Array, kind: String, id: int, price: int, count: int = 1) -> void:
	for offer in offers:
		if offer.kind == kind and int(offer.id) == id and int(offer.price) == price:
			offer.count = int(offer.count) + count
			return
	offers.append({"kind": kind, "id": id, "price": price, "count": count})


static func weighted_index(candidates: Array, random: RandomNumberGenerator) -> int:
	var total := 0
	for candidate in candidates:
		total += maxi(0, int(candidate.weight))
	if total <= 0:
		return -1
	var value := random.randi_range(0, total - 1)
	for index in candidates.size():
		value -= maxi(0, int(candidates[index].weight))
		if value < 0:
			return index
	return -1


static func cargo_price(library, item_id: int, station_id: int) -> int:
	return cargo_price_at(library, item_id, int(library.station_definition(station_id).technology))


## The price of a cargo unit at a station of the given technology level.
static func cargo_price_at(library, item_id: int, technology: int) -> int:
	var item: Dictionary = library.equipment(item_id)
	var rules: Dictionary = library.content.economy
	var fraction := .5
	if item.technology == 0:
		fraction = float(technology) / float(rules.cargo_technology_divisor)
	elif item.technology == 2:
		fraction = (
			(float(rules.cargo_technology_max) - float(technology))
			/ float(rules.cargo_technology_divisor)
		)
	return int(item.min_price) + int((int(item.max_price) - int(item.min_price)) * fraction)


## A ship's shop price at a station of the given technology level.
static func ship_price_at(library, ship_id: int, technology: int) -> int:
	var base := int(library.ships[ship_id][6])
	return base - int(base * float(technology) / float(library.content.economy.ship_technology_divisor))
