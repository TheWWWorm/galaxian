extends RefCounted
## Actual campaign receipts drive earned worth. Legacy baselines explicitly mark
## history that older previews did not record; they never claim invented payouts.


static func create(legacy_through: int = 0) -> Dictionary:
	return {"legacy_through": legacy_through, "rewards": []}


static func valid(value: Variant, chapter: int, library) -> bool:
	if (
		not value is Dictionary
		or not integer(value.get("legacy_through"))
		or value.legacy_through < 0
		or value.legacy_through > chapter
		or not value.get("rewards") is Array
		or value.rewards.size() != chapter - int(value.legacy_through)
		or chapter > library.content.chapters.size()
	):
		return false
	for index in value.rewards.size():
		var amount: Variant = value.rewards[index]
		var source_chapter: int = int(value.legacy_through) + index
		var base := int(library.content.chapters[source_chapter].reward)
		if not integer(amount) or amount < 0:
			return false
		var definition: Dictionary = library.mission_definition(source_chapter)
		if definition.has("reward_rule") and base > 0:
			var maximum := int(definition.reward_rule.offset)
			for group in definition.groups:
				if group.get("team", "enemy") != "enemy":
					maximum += int(group.count)
			if int(amount) % base != 0 or int(amount) > maxi(0, maximum) * base:
				return false
		elif int(amount) != base:
			return false
	return true


static func status(value: Dictionary, library) -> Dictionary:
	var result := {
		"level": int(library.content.initial.level),
		"worth": int(library.content.initial.worth),
		"checkpoint": int(library.content.initial.worth)
	}
	# Reproduce the named old-preview baseline only where receipts are unavailable.
	for index in int(value.legacy_through):
		apply_reward(result, int(library.content.chapters[index].reward), library)
	for amount in value.rewards:
		apply_reward(result, int(amount), library)
	return result


static func apply_reward(state: Dictionary, amount: int, library) -> void:
	state.worth += amount
	if state.worth > state.checkpoint * float(library.content.initial.rank_growth):
		state.level += 1
		state.checkpoint = state.worth


static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value)
