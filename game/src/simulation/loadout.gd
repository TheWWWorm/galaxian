extends RefCounted
## Equipment instances retain their individual resale values. A mounted item
## occupies its catalogue category; the ship table defines available mounts.
var library
var fitted: Array = []
var hold: Array = []
var error := ""


func configure(data, initial_weapon: int = -1) -> void:
	library = data
	fitted.clear()
	hold.clear()
	for index in library.SHIELD_CATEGORY + 1:
		fitted.append({})
	if initial_weapon >= 0:
		var item: Dictionary = library.equipment(initial_weapon)
		fitted[item.category] = {
			"id": initial_weapon,
			"value": int(item.max_price * float(library.content.economy.equipment_resale_factor))
		}


func supports(ship_id: int, item_id: int) -> bool:
	var category := int(library.items[item_id][1])
	if category == library.SHIELD_CATEGORY:
		return true
	var mounts: Array = library.ship_definition(ship_id).mounts
	return category >= 0 and category < mounts.size() and int(mounts[category]) > 0


func fit(index: int, ship_id: int) -> bool:
	error = ""
	if index < 0 or index >= hold.size() or not supports(ship_id, int(hold[index].id)):
		error = "This ship has no compatible mount."
		return false
	var record: Dictionary = hold[index]
	var category := int(library.items[int(record.id)][1])
	var previous: Dictionary = fitted[category]
	fitted[category] = record
	hold.remove_at(index)
	if not previous.is_empty():
		hold.append(previous)
	return true


func unfit(category: int, free_space: int) -> bool:
	error = ""
	if category < 0 or category >= fitted.size() or fitted[category].is_empty():
		return false
	if free_space <= 0:
		error = "The cargo hold is full."
		return false
	hold.append(fitted[category])
	fitted[category] = {}
	return true


func ship_exchange(ship_id: int, cargo_units: int) -> Dictionary:
	error = ""
	var new_hold := hold.duplicate(true)
	var new_fitted := fitted.duplicate(true)
	for category in new_fitted.size():
		var item: Dictionary = new_fitted[category]
		if not item.is_empty() and not supports(ship_id, int(item.id)):
			new_hold.append(item)
			new_fitted[category] = {}
	if cargo_units + new_hold.size() > int(library.ships[ship_id][5]):
		error = "The new ship cannot carry your cargo and unmounted equipment."
		return {}
	return {"hold": new_hold, "fitted": new_fitted}


func weapons() -> Array[int]:
	var result: Array[int] = []
	for category in range(0, library.SHIELD_CATEGORY):
		if not fitted[category].is_empty():
			result.append(int(fitted[category].id))
	return result


func primary_weapons() -> Array[int]:
	return weapons().filter(func(id): return int(library.items[id][1]) != library.MISSILE_CATEGORY)


func shield_capacity() -> float:
	var item: Dictionary = fitted[library.SHIELD_CATEGORY]
	return 0.0 if item.is_empty() else float(library.items[int(item.id)][7])


func shield_interval() -> float:
	var item: Dictionary = fitted[library.SHIELD_CATEGORY]
	return 0.0 if item.is_empty() else float(library.items[int(item.id)][8]) / 1000.0


func capture() -> Dictionary:
	return {"hold": hold.duplicate(true), "fitted": fitted.duplicate(true)}


func restore(value: Variant, ship_id: int, cargo_units: int) -> bool:
	error = "Invalid saved equipment."
	if (
		not value is Dictionary
		or not value.get("hold") is Array
		or not value.get("fitted") is Array
	):
		return false
	if (
		value.fitted.size() != library.SHIELD_CATEGORY + 1
		or value.hold.size() + cargo_units > int(library.ships[ship_id][5])
	):
		return false
	for record in value.hold + value.fitted:
		if not record is Dictionary:
			return false
		if record.is_empty():
			continue
		if (
			not record.has_all(["id", "value"])
			or not integer(record.id)
			or record.id < 0
			or record.id >= library.items.size()
			or not integer(record.value)
			or record.value < 0
		):
			return false
		if (
			int(library.items[int(record.id)][1]) >= library.CARGO_CATEGORY
			or record.value > int(library.items[int(record.id)][6])
		):
			return false
	for record in value.hold:
		if record.is_empty():
			return false
	for category in value.fitted.size():
		var record: Dictionary = value.fitted[category]
		if (
			not record.is_empty()
			and (
				int(library.items[int(record.id)][1]) != category
				or not supports(ship_id, int(record.id))
			)
		):
			return false
	hold = value.hold.duplicate(true)
	fitted = value.fitted.duplicate(true)
	for record in hold + fitted:
		if not record.is_empty():
			record.id = int(record.id)
			record.value = int(record.value)
	error = ""
	return true


static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value)
