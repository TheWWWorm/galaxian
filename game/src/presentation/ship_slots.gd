extends RefCounted


static func describe(library, ship_id: int) -> String:
	var mounts: Array = library.ship_definition(ship_id).mounts
	var rows: Array[String] = []
	for category in mini(library.SHIELD_CATEGORY, mounts.size()):
		rows.append(
			(
				"%s: %d"
				% [
					library.text(int(library.content.hangar_ui.labels.category_base) + category),
					int(mounts[category])
				]
			)
		)
	return "Weapon slots\n" + "\n".join(rows)
