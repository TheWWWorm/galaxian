extends "res://src/simulation/loadout.gd"
## The swarm build owns which catalogue weapon sits in each mount category.
## This adapter presents it through the loadout interface flight already uses,
## without touching the shared campaign inventory.
const Build = preload("res://src/simulation/swarm_build.gd")
var rules := {}
var build := {}


func configure_build(data, parameters: Dictionary, state: Dictionary) -> void:
	library = data
	rules = parameters
	build = state
	super.configure(data)
	refresh()


func refresh() -> void:
	for index in fitted.size():
		fitted[index] = {}
	if library == null or build.is_empty():
		return
	for category in Build.owned(build, library):
		var id := Build.weapon(build, library, category)
		if id >= 0 and category < fitted.size():
			fitted[category] = {"id": id, "value": int(library.items[id][6])}
	var shield := Build.shield_item(build, library)
	if shield >= 0:
		fitted[library.SHIELD_CATEGORY] = {"id": shield, "value": int(library.items[shield][6])}


func supports(_ship_id: int, item_id: int) -> bool:
	if library == null or item_id < 0 or item_id >= library.items.size():
		return false
	var category := int(library.items[item_id][1])
	if category == library.SHIELD_CATEGORY:
		return true
	return Build.categories(library, int(build.get("ship", 0))).has(category)


func shield_capacity() -> float:
	return 0.0 if library == null else Build.shield_capacity(build, library)


func shield_interval() -> float:
	return 0.0 if library == null else Build.shield_interval(build, rules, library)
