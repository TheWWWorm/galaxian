extends "res://src/simulation/loadout.gd"
## Survival has its own mount and shield overrides from the supplied content.
## Never mutate the shared campaign ship/equipment catalogue for this mode.
var setup := {}


func configure_start(data, parameters: Dictionary) -> void:
	setup = parameters.duplicate(true)
	super.configure(data)
	for item_id in setup.equipment:
		var item: Dictionary = library.equipment(int(item_id))
		fitted[int(item.category)] = {"id": int(item_id), "value": int(item.max_price)}


func supports(_ship_id: int, item_id: int) -> bool:
	if item_id < 0 or item_id >= library.items.size():
		return false
	var category := int(library.items[item_id][1])
	if category == library.SHIELD_CATEGORY:
		return true
	return category >= 0 and category < setup.slots.size() and int(setup.slots[category]) > 0


func shield_capacity() -> float:
	return float(setup.shield_capacity) if not fitted[library.SHIELD_CATEGORY].is_empty() else 0.0


func shield_interval() -> float:
	return float(setup.shield_interval_ms) / 1000.0
