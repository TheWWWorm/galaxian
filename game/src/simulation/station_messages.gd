extends RefCounted
## Arrival notices shown when the station screen opens after a mission. The
## source compares the pilot record against the values recorded when the
## station screen was last entered, so a notice describes the change since the
## previous visit rather than the whole career. Credit milestones are recorded
## once per save; rank, reputation and exploration notices are not.
const Combat = preload("res://src/simulation/combat.gd")


static func baseline(credits: int, reputation: int, explored: int, stations: int) -> Dictionary:
	return {
		"credits": credits,
		"reputation": reputation,
		"exploration": int(exploration_rate(explored, stations))
	}


static func exploration_rate(explored: int, stations: int) -> float:
	# Status::getExplorationRate divides the visited count by the station total
	# before scaling, in binary32. Reproduce that order, not a percentage of a
	# rounded ratio.
	if stations <= 0:
		return 0.0
	return f32(f32(f32(float(explored)) / float(stations)) * 100.0)


static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]


static func valid(value: Variant) -> bool:
	return (
		value is Dictionary
		and Combat.integer(value.get("credits"))
		and Combat.integer(value.get("reputation"))
		and Combat.integer(value.get("exploration"))
	)


static func valid_data(value: Variant, text_count: int) -> bool:
	if (
		not value is Dictionary
		or not value.get("separator") is String
		or not value.get("suffix") is String
		or value.separator.is_empty()
		or value.suffix.is_empty()
	):
		return false
	for key in ["level_text", "reputation_text", "rank_base", "exploration_limit"]:
		if (
			not Combat.integer(value.get(key))
			or value[key] < 0
			or value[key] >= (text_count if key != "exploration_limit" else 1000)
		):
			return false
	if (
		not value.get("credit_milestones") is Array
		or value.credit_milestones.is_empty()
		or value.credit_milestones.size() > 16
		or not value.get("exploration_milestones") is Array
		or value.exploration_milestones.is_empty()
		or value.exploration_milestones.size() > 16
	):
		return false
	var flags: Array = []
	for record in value.credit_milestones:
		if (
			not record is Dictionary
			or not Combat.integer(record.get("threshold"))
			or record.threshold <= 0
			or not Combat.integer(record.get("text"))
			or record.text < 0
			or record.text >= text_count
			or not Combat.integer(record.get("flag"))
			or record.flag < 0
			or flags.has(int(record.flag))
		):
			return false
		flags.append(int(record.flag))
	for record in value.exploration_milestones:
		if (
			not record is Dictionary
			or not Combat.number(record.get("rate"))
			or record.rate <= 0
			or record.rate > 100
			or not Combat.integer(record.get("text"))
			or record.text < 0
			or record.text >= text_count
		):
			return false
	return true


## Builds the notices for one station arrival. `shown` holds the credit
## milestone flags already recorded in this save and is updated in place.
static func collect(
	library,
	data: Dictionary,
	previous: Dictionary,
	credits: int,
	rank: int,
	ranked_up: bool,
	reputation: int,
	explored: int,
	shown: Array
) -> Array[String]:
	var result: Array[String] = []
	if ranked_up:
		result.append(
			(
				library.text(int(data.level_text))
				+ str(data.separator)
				+ str(rank)
				+ str(data.suffix)
			)
		)
	if reputation > int(previous.reputation):
		result.append(
			(
				library.text(int(data.reputation_text))
				+ str(data.separator)
				+ library.text(int(data.rank_base) + reputation)
				+ str(data.suffix)
			)
		)
	for record in data.credit_milestones:
		var threshold := int(record.threshold)
		if credits <= threshold or int(previous.credits) > threshold:
			continue
		if not shown.has(int(record.flag)):
			shown.append(int(record.flag))
			result.append(library.text(int(record.text)))
		break
	var rate := exploration_rate(explored, library.stations.size())
	if int(rate) > int(previous.exploration) and int(previous.exploration) <= int(data.exploration_limit):
		for record in data.exploration_milestones:
			if rate < float(record.rate):
				continue
			result.append(library.text(int(record.text)))
			break
	return result
