extends RefCounted
## Deterministic post-mission cargo recovery using imported distributions.
const Combat = preload("res://src/simulation/combat.gd")


static func mode(
	parameters: Dictionary, campaign: bool, chapter: int, kills: int, instant: bool = false
) -> String:
	if instant or (campaign and chapter <= parameters.campaign_excluded_through):
		return "none"
	if kills > 0 or (campaign and chapter == parameters.campaign_guaranteed):
		return "guaranteed"
	return "optional"


static func generate(
	parameters: Dictionary, capacity: int, selection: String, seed_value: int
) -> Dictionary:
	var result := {"items": [], "full": false}
	if selection == "none":
		return result
	if capacity <= 0:
		result.full = true
		return result
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var count := random.randi_range(0, int(parameters.entry_choices) - 1)
	if count == 0 and selection == "guaranteed":
		count = random.randi_range(
			int(parameters.guaranteed_entries[0]), int(parameters.guaranteed_entries[1])
		)
	count = mini(count, capacity / int(parameters.minimum_quantity))
	var choices: Array = parameters.items.duplicate()
	var total := 0
	for index in count:
		# Sampling without replacement has the same distribution as rejecting
		# duplicate catalogue IDs, with a bounded number of native RNG draws.
		var item := int(choices.pop_at(random.randi_range(0, choices.size() - 1)))
		var amount := random.randi_range(
			int(parameters.quantities[0]), int(parameters.quantities[1])
		)
		result.items.append({"id": item, "amount": amount})
		total += amount
	# Remove full rounds before the final partial round. This preserves the
	# source's ordered, even reduction without looping once per excess unit.
	var excess := total - capacity
	while excess > 0:
		var active: Array = result.items.filter(
			func(item): return item.amount > parameters.minimum_quantity
		)
		var depth := int(active[0].amount) - int(parameters.minimum_quantity)
		for item in active:
			depth = mini(depth, int(item.amount) - int(parameters.minimum_quantity))
		var rounds := mini(depth, excess / active.size())
		for item in active:
			var removed := rounds if rounds > 0 else 1
			item.amount = int(item.amount) - removed
			excess -= removed
			if excess <= 0:
				break
	return result


static func valid_result(value: Variant, parameters: Dictionary) -> bool:
	if not value is Dictionary or not value.get("full") is bool or not value.get("items") is Array:
		return false
	if (
		value.items.size() >= parameters.entry_choices
		or (value.full and not value.items.is_empty())
	):
		return false
	var ids := []
	for item in value.items:
		if (
			not item is Dictionary
			or not Combat.integer(item.get("id"))
			or not Combat.integer(item.get("amount"))
		):
			return false
		if not parameters.items.any(func(id): return id == item.id) or ids.has(int(item.id)):
			return false
		if item.amount < parameters.minimum_quantity or item.amount > parameters.quantities[1]:
			return false
		ids.append(int(item.id))
	return true


static func valid(parameters: Variant, library) -> bool:
	if (
		not parameters is Dictionary
		or not parameters.get("items") is Array
		or parameters.items.is_empty()
		or parameters.items.size() > 128
	):
		return false
	var seen := []
	for item in parameters.items:
		if (
			not Combat.integer(item)
			or item < 0
			or item >= library.items.size()
			or seen.has(int(item))
		):
			return false
		if int(library.items[int(item)][1]) != library.CARGO_CATEGORY:
			return false
		seen.append(int(item))
	for key in ["quantities", "guaranteed_entries"]:
		if not parameters.get(key) is Array or parameters[key].size() != 2:
			return false
		if not parameters[key].all(func(n): return Combat.integer(n) and n > 0 and n <= 1000000):
			return false
		if parameters[key][0] > parameters[key][1]:
			return false
	for key in [
		"entry_choices",
		"minimum_quantity",
		"campaign_type",
		"campaign_excluded_through",
		"campaign_guaranteed"
	]:
		if not Combat.integer(parameters.get(key)) or parameters[key] < 0:
			return false
	if (
		parameters.minimum_quantity < 1
		or parameters.minimum_quantity > parameters.quantities[0]
		or parameters.entry_choices < 2
		or parameters.entry_choices > parameters.items.size() + 1
	):
		return false
	if (
		parameters.guaranteed_entries[1] >= parameters.entry_choices
		or parameters.campaign_excluded_through >= library.content.chapters.size()
		or parameters.campaign_guaranteed >= library.content.chapters.size()
	):
		return false
	if not parameters.get("images") is Dictionary or not parameters.get("labels") is Dictionary:
		return false
	if not parameters.images.get("items") is Dictionary:
		return false
	var bindings := [parameters.images.get("row_measure"), parameters.images.get("empty")]
	for item in parameters.items:
		bindings.append(parameters.images.items.get(str(int(item))))
	for binding in bindings:
		if (
			not binding is Dictionary
			or not Combat.integer(binding.get("texture"))
			or not Combat.integer(binding.get("region"))
		):
			return false
		var atlas: Variant = library.radio_atlases.get(str(int(binding.texture)))
		if not atlas is Dictionary or binding.region < 0 or binding.region >= atlas.regions.size():
			return false
	for key in ["title", "recovered", "full", "empty"]:
		if (
			not Combat.integer(parameters.labels.get(key))
			or parameters.labels[key] < 0
			or parameters.labels[key] >= library.strings.size()
		):
			return false
	if not parameters.get("layout") is Dictionary:
		return false
	for key in [
		"row_gap", "row_height_padding", "width_padding", "title_y", "row_x", "text_y", "icon_right"
	]:
		if (
			not Combat.integer(parameters.layout.get(key))
			or parameters.layout[key] < 0
			or parameters.layout[key] > 480
		):
			return false
	for key in ["fill", "border"]:
		var color: Variant = parameters.layout.get(key)
		if (
			not color is Array
			or color.size() != 4
			or not color.all(func(n): return Combat.integer(n) and n >= 0 and n <= 255)
		):
			return false
	for key in ["quantity_column", "quantity_suffix"]:
		if not parameters.layout.get(key) is String or parameters.layout[key].length() > 32:
			return false
	return true
