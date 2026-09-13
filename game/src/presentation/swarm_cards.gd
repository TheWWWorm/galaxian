extends RefCounted
## Card wording for the swarm level-up dialog. Weapon, shield and hull names
## come from the imported localisation table; only the modifier phrasing and
## the prompt are remake-authored, because the cards themselves are.
const Build = preload("res://src/simulation/swarm_build.gd")
const MODIFIER_TEXT := {
	"damage": "%s damage %s",
	"reload": "%s reload %s",
	"muzzle": "%s extra muzzle",
	"reach": "%s range %s",
	"velocity": "%s muzzle velocity %s",
	"integrity": "Hull integrity %s",
	"agility": "Agility %s",
	"recovery": "Repair %d hull on every kill",
	"insight": "Combat experience %s",
	"boost": "Boost recharge %s",
	"regeneration": "Shield regeneration %s"
}


static func signed(percent: int) -> String:
	return ("+%d%%" % percent) if percent >= 0 else ("%d%%" % percent)


static func label(
	card: Dictionary, rules: Dictionary, library, build: Dictionary = {}, amounts: Array = []
) -> String:
	match str(card.get("kind")):
		"mount":
			return "Mount " + library.item_name(int(card.item))
		"upgrade":
			return "Refit " + library.item_name(int(card.item))
		"shield":
			return "Fit " + library.item_name(int(card.item))
		"hull":
			return "Transfer to " + library.ship_name(int(card.item))
		"modifier":
			var key := str(card.modifier)
			var rule: Dictionary = rules.cards.modifiers[key]
			var change := signed(int(rule.percent))
			if key == "recovery":
				# The card names the hull it will actually bank, not a percentage
				# of a number the player never sees.
				var taken := int(build.get("recovery", 0)) + 1
				return MODIFIER_TEXT[key] % int(
					round(Build.recovery_hull({"recovery": taken}, rules, amounts))
				)
			if key == "muzzle":
				return MODIFIER_TEXT[key] % library.item_name(int(card.item))
			if int(card.category) >= 0:
				return MODIFIER_TEXT[key] % [library.item_name(int(card.item)), change]
			return MODIFIER_TEXT[key] % change
	return "Continue"


static func detail(card: Dictionary, rules: Dictionary, library, build: Dictionary) -> String:
	## One short line under the name, so a pick is an informed one.
	match str(card.get("kind")):
		"mount", "upgrade":
			var ballistics: Dictionary = library.weapon_ballistics(int(card.item))
			if ballistics.is_empty():
				return ""
			return "%d damage every %.2fs" % [int(ballistics.damage), float(ballistics.interval)]
		"shield":
			var row: Array = library.items[int(card.item)]
			return "%d capacity, one point per %.1fs" % [int(row[7]), float(row[8]) / 1000.0]
		"hull":
			var definition: Dictionary = library.ship_definition(int(card.item))
			var slots := Build.categories(library, int(card.item)).size()
			return "%d hull, %d mounts" % [int(definition.hull), slots]
		"modifier":
			var key := str(card.modifier)
			var taken := (
				Build.stack(build, key, int(card.category))
				if int(card.category) >= 0
				else int(build.get(key, 0))
			)
			return "stack %d of %d" % [taken + 1, int(rules.cards.modifiers[key].stacks)]
	return ""


static func prompt(level: int, pending: int) -> String:
	if pending > 1:
		return "Level %d  (%d more)" % [level, pending - 1]
	return "Level %d" % level


static func captions(
	cards: Array, rules: Dictionary, library, build: Dictionary = {}, amounts: Array = []
) -> Array[String]:
	var result: Array[String] = []
	for card in cards:
		result.append(label(card, rules, library, build, amounts))
	result.append("Decline  (repair %d%%)" % int(rules.cards.decline_repair_percent))
	return result


static func summary(cards: Array, rules: Dictionary, library, build: Dictionary) -> String:
	var lines := PackedStringArray()
	for card in cards:
		var line := detail(card, rules, library, build)
		lines.append(line if not line.is_empty() else " ")
	return "\n".join(lines)
