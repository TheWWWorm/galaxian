extends RefCounted
## Native view model: source catalogues plus the pilot's actual inventory/offers.
const Combat = preload("res://src/simulation/combat.gd")


static func valid_data(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.get("tabs") is Array
		or value.tabs.size() != 3
		or not value.get("pictures") is Dictionary
		or not value.get("labels") is Dictionary
		or not value.get("description") is Dictionary
	):
		return false
	var seen: Array = []
	for tab in value.tabs:
		if (
			not tab is Dictionary
			or not tab.get("action") in ["ship", "cargo", "shop"]
			or tab.action in seen
			or not Combat.integer(tab.get("label"))
			or tab.label < 0
		):
			return false
		seen.append(tab.action)
	for key in ["box", "list"]:
		if (
			not value.get(key) is Array
			or value[key].size() != 4
			or not value[key].all(func(v): return Combat.number(v) and v >= 0 and v <= 480)
			or value[key][2] <= 0
			or value[key][3] <= 0
		):
			return false
	for key in ["ship_icons", "ship_previews", "item_icons", "item_previews"]:
		if not value.pictures.get(key) is Array or value.pictures[key].is_empty():
			return false
		for binding in value.pictures[key]:
			if (
				not binding is Dictionary
				or not Combat.integer(binding.get("texture"))
				or not Combat.integer(binding.get("region"))
				or binding.texture < 0
				or binding.region < 0
			):
				return false
	for key in [
		"back",
		"info",
		"ships",
		"weapons",
		"generators",
		"damage",
		"rate",
		"capacity",
		"recharge",
		"mounts",
		"armor",
		"hold",
		"category_base"
	]:
		if not Combat.integer(value.labels.get(key)) or value.labels[key] < 0:
			return false
	for key in ["items", "ships"]:
		var binding: Variant = value.description.get(key)
		if (
			not binding is Dictionary
			or not Combat.integer(binding.get("base"))
			or binding.base < 0
			or not Combat.integer(binding.get("stride"))
			or binding.stride <= 0
		):
			return false
	return (
		preload("res://src/presentation/cargo_sale.gd").valid_data(value.get("quantity"))
		and preload("res://src/presentation/ship_exchange.gd").valid_data(value.get("exchange"))
	)


static func entries(library, pilot, tab: String) -> Array:
	var result: Array = []
	if tab == "ship":
		result.append(
			{"kind": "ship", "id": pilot.ship_id, "source": "owned", "price": pilot.ship_value}
		)
		var mounts: Array = library.ship_definition(pilot.ship_id).mounts
		for index in pilot.loadout.fitted.size():
			if index != library.SHIELD_CATEGORY and (index >= mounts.size() or int(mounts[index]) == 0):
				continue
			var item: Dictionary = pilot.loadout.fitted[index]
			result.append(
				{
					"kind": "empty" if item.is_empty() else "equipment",
					"id": int(item.get("id", -1)),
					"source": "fitted",
					"index": index,
					"category": index,
					"price": int(item.get("value", 0))
				}
			)
	elif tab == "cargo":
		for index in pilot.loadout.hold.size():
			var item: Dictionary = pilot.loadout.hold[index]
			result.append(
				{
					"kind": "equipment",
					"id": int(item.id),
					"source": "hold",
					"index": index,
					"price": int(item.value)
				}
			)
		for key in pilot.cargo:
			result.append(
				{
					"kind": "cargo",
					"id": int(key),
					"source": "cargo",
					"count": int(pilot.cargo[key]),
					"price": pilot.Market.cargo_price(library, int(key), pilot.station_id)
				}
			)
	elif tab == "shop":
		var offers: Array = pilot.market_offers()
		for index in offers.size():
			var offer: Dictionary = offers[index]
			if offer.count > 0:
				var entry := offer.duplicate()
				entry.source = "shop"
				entry.index = index
				result.append(entry)
		result.sort_custom(func(a, b): return group(library, a) < group(library, b))
	return result


static func name(library, entry: Dictionary) -> String:
	if entry.kind == "empty":
		return (
			library.text(int(library.content.hangar_ui.labels.category_base) + int(entry.category))
			+ " — Empty"
		)
	return (
		library.ship_name(int(entry.id))
		if entry.kind == "ship"
		else library.item_name(int(entry.id))
	)


static func description(library, entry: Dictionary) -> String:
	if entry.is_empty() or entry.kind == "empty":
		return "Select compatible equipment in Cargo to install it."
	var group := "ships" if entry.kind == "ship" else "items"
	var binding: Dictionary = library.content.hangar_ui.description[group]
	return library.text(int(binding.base + binding.stride * entry.id))


static func image(library, entry: Dictionary, large := false) -> Texture2D:
	if entry.is_empty() or entry.kind == "empty":
		return null
	var key := ("ship" if entry.kind == "ship" else "item") + ("_previews" if large else "_icons")
	return library.ui_image(library.content.hangar_ui.pictures[key][int(entry.id)])


static func actions(library, pilot, entry: Dictionary) -> Array:
	if entry.is_empty():
		return []
	var room: bool = pilot.cargo_used() < pilot.cargo_capacity()
	var shop: bool = library.station_definition(pilot.station_id).shop
	match entry.source:
		"shop":
			var allowed: bool = pilot.credits >= entry.price and room
			var caption := "Buy"
			if entry.kind == "ship":
				# Let the review explain affordability and transfer limits before Buy.
				allowed = pilot.ship_id != entry.id
				caption = "Exchange"
			return [{"action": "buy", "text": caption, "enabled": allowed}]
		"fitted":
			return [
				{
					"action": "remove",
					"text": "Move to hold",
					"enabled": entry.kind != "empty" and room
				}
			]
		"hold":
			return [
				{
					"action": "fit",
					"text": "Install",
					"enabled": pilot.loadout.supports(pilot.ship_id, int(entry.id))
				},
				{"action": "sell", "text": "Sell", "enabled": shop}
			]
		"cargo":
			return [{"action": "sell_cargo", "text": library.text(int(library.content.hangar_ui.quantity.labels.sell)), "enabled": shop}]
	return []


static func group(library, entry: Dictionary) -> int:
	if entry.kind == "ship":
		return 0
	if entry.kind == "cargo":
		return 3
	return 2 if library.equipment(int(entry.id)).category == library.SHIELD_CATEGORY else 1


static func information(library, pilot, entry: Dictionary) -> String:
	var result := description(library,entry)
	if entry.is_empty() or entry.kind == "empty": return result
	var labels: Dictionary = library.content.hangar_ui.labels
	var values: Array = []
	if entry.kind == "ship":
		var ship: Dictionary = library.ship_definition(int(entry.id))
		values = [[labels.armor,pilot.max_hull() if entry.source == "owned" else ship.hull],[labels.hold,ship.capacity],[labels.mounts,ship.mounts.filter(func(v):return int(v)>0).size()]]
	elif entry.kind == "equipment":
		var item: Dictionary = library.equipment(int(entry.id))
		values = [[labels.capacity if item.category == library.SHIELD_CATEGORY else labels.damage,item.value]]
		if item.interval_ms > 0:
			values.append([labels.recharge if item.category == library.SHIELD_CATEGORY else labels.rate,"%.2f /s" % (1000.0/item.interval_ms)])
	for pair in values:
		result += "\n\n%s: %s" % [library.text(int(pair[0])),str(pair[1])]
	if entry.source == "shop" and entry.kind == "ship":
		result += "\n\nExchanging ships transfers compatible mounted equipment; the rest goes into the hold."
	return result
