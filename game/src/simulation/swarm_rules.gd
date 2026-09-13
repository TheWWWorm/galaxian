extends RefCounted
## Remake-authored rules for the swarm arcade mode. Nothing in this file is
## recovered from the supplied game: it is pacing, population and card policy
## written for this remake. Every quantity it names is either a plain rule
## number or a multiplier applied to a value that does come from the archive.
##
## Weapon and shield ladders, enemy archetypes, arena hull and every projectile
## property are read from imported content at runtime; see swarm_build.gd and
## swarm_director.gd. This file never invents a damage, hull, price or reload.
const Combat = preload("res://src/simulation/combat.gd")
const VERSION := 3
## Categories below the shield category are weapon mounts on a hull.
const MAX_STACK := 16


static func create() -> Dictionary:
	return {
		"version": VERSION,
		"arc_seconds": 1200.0,
		# The arena opens on a handful of hulls and grows into a crowd. A wall of
		# ships in the first seconds reads as noise, not as pressure.
		"crowd": {"start": 6.0, "cap": 14.0, "ramp": 360.0},
		"elite": {"cap": 5.0, "delay": 150.0, "ramp": 800.0},
		# "first" keeps the opening minutes clear of surges: a surge on the very
		# first frame would multiply the starting crowd before the run begins.
		"surge": {"first": 300.0, "period": 180.0, "length": 20.0, "multiplier": 1.4},
		# Close enough that arrivals are continuous. At the old 450-700 band a
		# small arena spent most of its time in transit: the imported cruise
		# speed is 40 and these hulls fly at 30-60, so a 600 unit ring is ten
		# seconds of empty sky between engagements.
		"spawn": {"near": 240.0, "far": 440.0, "tick_ms": 1000.0, "per_tick": 4},
		# The imported archetype ladder tops out at hull 200 and is exhausted
		# around minute twelve. Past that the run needs enemy growth of its own,
		# the mirror of the player's percentage cards. Both scales ramp across
		# the arc: enemies open below their imported numbers and end above them,
		# so the first minutes are survivable without being free.
		"veterancy": {"hull": [1.0, 2.5], "damage": [0.2, 1.3]},
		"quality": 2.0,
		# The imported arena hull was written for the imported survival mode,
		# which never puts this many guns on the player at once. A denser arena
		# needs a deeper pool; the per-ship differences stay imported.
		"hull_scale": 2.2,
		# Imported contact damage is 5 every half second per touching hull. In a
		# crowd that alone is lethal and unavoidable, so this mode halves it.
		"contact": 0.25,
		# Boost is the disengage. The imported 20 second recharge leaves it
		# available a fifth of the time, which is not enough to break away from
		# a swarm; cards shorten it further from here.
		"boost_recharge": 0.6,
		# The standing repair: the archive's smallest repair amount, restored
		# over this many seconds, always. Not a pickup and not tied to kills, so
		# it cannot spiral the way heal-on-kill does.
		"repair_seconds": 15.0,
		# Hull unlocks read the imported rank ladder at this percentage. The
		# ladder was written for the imported survival scoring; this mode's
		# scores are its own, so the thresholds are a rule like everything else.
		"unlock_percent": 50,
		"levels": {"first": 75, "growth": 1.22, "count": 40},
		# Archetype indices into the imported survival ships table. The crowd is
		# the short-ranged, cheap half; elites are the shooters and stay capped.
		"crowd_archetypes": [0, 1, 2, 3, 6],
		"elite_archetypes": [5, 7, 8, 4, 9],
		"cards": {
			"offers": 3,
			"decline_repair_percent": 25,
			"hull_offer_interval": 5,
			"weights": {
				"mount": 10,
				"upgrade": 8,
				"weapon_modifier": 6,
				"shield_first": 7,
				"shield_next": 4,
				"global_modifier": 4,
				"hull": 2
			},
			"modifiers": {
				"damage": {"scope": "category", "percent": 15, "stacks": 5},
				"reload": {"scope": "category", "percent": -8, "stacks": 5},
				"muzzle": {"scope": "category", "percent": 0, "stacks": 3},
				"reach": {"scope": "category", "percent": 20, "stacks": 3},
				"velocity": {"scope": "category", "percent": 20, "stacks": 3},
				"integrity": {"scope": "global", "percent": 10, "stacks": 5},
				"agility": {"scope": "global", "percent": 8, "stacks": 4},
				# Recovery reads as a share of the archive's smallest repair
				# amount, banked on every kill instead of dropped as salvage.
				"recovery": {"scope": "global", "percent": 20, "stacks": 3},
				"insight": {"scope": "global", "percent": 15, "stacks": 3},
				"boost": {"scope": "global", "percent": -15, "stacks": 3},
				"regeneration": {"scope": "global", "percent": 20, "stacks": 3}
			}
		}
	}


static func number(value: Variant, low: float, high: float) -> bool:
	return Combat.number(value) and value >= low and value <= high


static func integer(value: Variant, low: int, high: int) -> bool:
	return Combat.integer(value) and value >= low and value <= high


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != VERSION:
		return false
	if not number(value.get("arc_seconds"), 60.0, 36000.0):
		return false
	if not number(value.get("quality"), 0.01, 100.0):
		return false
	if (
		not number(value.get("contact"), 0.0, 8.0)
		or not number(value.get("hull_scale"), 0.1, 64.0)
		or not number(value.get("boost_recharge"), 0.05, 8.0)
		or not number(value.get("repair_seconds"), 1.0, 36000.0)
		or not integer(value.get("unlock_percent"), 1, 10000)
	):
		return false
	return (
		valid_population(value)
		and valid_spawn(value.get("spawn"))
		and valid_levels(value.get("levels"))
		and valid_archetypes(value)
		and valid_cards(value.get("cards"))
	)


static func valid_population(value: Dictionary) -> bool:
	var crowd: Variant = value.get("crowd")
	var elite: Variant = value.get("elite")
	var surge: Variant = value.get("surge")
	if not crowd is Dictionary or not elite is Dictionary or not surge is Dictionary:
		return false
	if (
		not number(crowd.get("start"), 1.0, 128.0)
		or not number(crowd.get("cap"), 1.0, 128.0)
		or not number(crowd.get("ramp"), 1.0, 36000.0)
		or crowd.start > crowd.cap
	):
		return false
	if (
		not number(elite.get("cap"), 0.0, 128.0)
		or not number(elite.get("delay"), 0.0, 36000.0)
		or not number(elite.get("ramp"), 1.0, 36000.0)
	):
		return false
	if (
		not number(surge.get("first"), 0.0, 36000.0)
		or not number(surge.get("period"), 1.0, 36000.0)
		or not number(surge.get("length"), 0.0, 36000.0)
		or not number(surge.get("multiplier"), 1.0, 8.0)
		or surge.length >= surge.period
	):
		return false
	var veterancy: Variant = value.get("veterancy")
	if not veterancy is Dictionary:
		return false
	for key in ["hull", "damage"]:
		var span: Variant = veterancy.get(key)
		if (
			not span is Array
			or span.size() != 2
			or not span.all(func(v): return number(v, 0.05, 64.0))
			or span[0] > span[1]
		):
			return false
	return true


static func valid_spawn(value: Variant) -> bool:
	return (
		value is Dictionary
		and number(value.get("near"), 1.0, 100000.0)
		and number(value.get("far"), 1.0, 100000.0)
		and value.near <= value.far
		and number(value.get("tick_ms"), 1.0, 600000.0)
		and integer(value.get("per_tick"), 1, 128)
	)


static func valid_levels(value: Variant) -> bool:
	return (
		value is Dictionary
		and integer(value.get("first"), 1, 1000000)
		and number(value.get("growth"), 1.001, 8.0)
		and integer(value.get("count"), 1, 512)
	)


static func valid_archetypes(value: Dictionary) -> bool:
	var seen := []
	for key in ["crowd_archetypes", "elite_archetypes"]:
		var table: Variant = value.get(key)
		if not table is Array or table.is_empty() or table.size() > 128:
			return false
		for index in table:
			if not integer(index, 0, 127) or seen.has(int(index)):
				return false
			seen.append(int(index))
	return true


static func valid_cards(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not integer(value.get("offers"), 1, 8)
		or not integer(value.get("decline_repair_percent"), 0, 100)
		or not integer(value.get("hull_offer_interval"), 1, 512)
	):
		return false
	var weights: Variant = value.get("weights")
	if not weights is Dictionary:
		return false
	for key in [
		"mount", "upgrade", "weapon_modifier", "shield_first", "shield_next", "global_modifier",
		"hull"
	]:
		if not integer(weights.get(key), 1, 1000):
			return false
	var modifiers: Variant = value.get("modifiers")
	if not modifiers is Dictionary or modifiers.is_empty() or modifiers.size() > 64:
		return false
	for key in modifiers:
		if not key is String or key.is_empty() or key.length() > 64:
			return false
		var rule: Variant = modifiers[key]
		if (
			not rule is Dictionary
			or rule.get("scope") not in ["category", "global"]
			or not integer(rule.get("percent"), -99, 10000)
			or not integer(rule.get("stacks"), 1, MAX_STACK)
		):
			return false
	for key in ["damage", "reload", "muzzle", "reach", "velocity"]:
		if modifiers.get(key, {}).get("scope") != "category":
			return false
	for key in ["integrity", "agility", "recovery", "insight", "boost", "regeneration"]:
		if modifiers.get(key, {}).get("scope") != "global":
			return false
	return true


static func level_thresholds(rules: Dictionary) -> PackedInt64Array:
	var result := PackedInt64Array([0])
	var step := float(rules.levels.first)
	for index in int(rules.levels.count):
		result.append(int(round((result[result.size() - 1] + step) / 10.0) * 10))
		step *= float(rules.levels.growth)
	return result


static func surging(rules: Dictionary, seconds: float) -> bool:
	var surge: Dictionary = rules.surge
	var since := seconds - float(surge.first)
	if since < 0:
		return false
	return fposmod(since, float(surge.period)) < float(surge.length)


static func crowd_at(rules: Dictionary, seconds: float) -> float:
	var crowd: Dictionary = rules.crowd
	var value: float = (
		float(crowd.start)
		+ (float(crowd.cap) - float(crowd.start)) * (1.0 - exp(-seconds / float(crowd.ramp)))
	)
	return value * (float(rules.surge.multiplier) if surging(rules, seconds) else 1.0)


static func elite_at(rules: Dictionary, seconds: float) -> float:
	var elite: Dictionary = rules.elite
	var since := maxf(0.0, seconds - float(elite.delay))
	var value: float = float(elite.cap) * (1.0 - exp(-since / float(elite.ramp)))
	return value * (float(rules.surge.multiplier) if surging(rules, seconds) else 1.0)


static func veterancy(rules: Dictionary, seconds: float) -> Dictionary:
	var fraction := clampf(seconds / float(rules.arc_seconds), 0.0, 1.0)
	var result := {}
	for key in ["hull", "damage"]:
		var span: Array = rules.veterancy[key]
		result[key] = float(span[0]) + (float(span[1]) - float(span[0])) * fraction
	return result


static func unlock_points(rules: Dictionary, imported: int) -> int:
	## An imported rank threshold, read at this mode's own scale.
	return int(round(float(imported) * float(rules.unlock_percent) * .01))


static func unlocked(rules: Dictionary, table: Array, seconds: float) -> int:
	## How far up an archetype ladder the mix has climbed. Always at least one.
	var fraction := minf(1.0, (seconds / float(rules.arc_seconds)) * float(rules.quality))
	return clampi(1 + int(fraction * table.size()), 1, table.size())
