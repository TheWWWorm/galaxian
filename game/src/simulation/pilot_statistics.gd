extends RefCounted
## Session time is wall time, independent of flight speedup. Kill totals are
## committed with successful mission arrival, alongside its one-time reward.
const Combat = preload("res://src/simulation/combat.gd")


static func create(partial := false) -> Dictionary:
	return {"play_seconds": 0.0, "kills": 0, "partial": partial}


static func valid(value: Variant) -> bool:
	return (
		value is Dictionary
		and Combat.number(value.get("play_seconds"))
		and value.play_seconds >= 0
		and Combat.integer(value.get("kills"))
		and value.kills >= 0
		and value.get("partial") is bool
	)


static func advance(value: Dictionary, seconds: float, active: bool) -> void:
	if active and is_finite(seconds) and seconds > 0:
		value.play_seconds += seconds


static func reputation(value: Dictionary, data: Dictionary) -> int:
	var index := 0
	for threshold in data.reputation_thresholds:
		if value.kills < threshold:
			break
		index += 1
	return mini(index, int(data.reputation_max))


static func duration(seconds: float) -> String:
	var whole := int(seconds)
	return "%d:%02d:%02d" % [whole / 3600, (whole / 60) % 60, whole % 60]
