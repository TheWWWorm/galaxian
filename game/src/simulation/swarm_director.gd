extends RefCounted
## Population, pacing and progression for the swarm mode. The director owns no
## actors: it reports which pool slots should be occupied by which imported
## archetype, and the session applies that to the arena.
##
## Scoring keeps the archive's combo arithmetic exactly. Levels deliberately do
## not: combo inflates superlinearly with chaining, so it drives the leaderboard
## and never the pacing.
const Combat = preload("res://src/simulation/combat.gd")
const Rules = preload("res://src/simulation/swarm_rules.gd")
const MAX_COUNTER := 1000000000


static func pool_sizes(rules: Dictionary) -> Dictionary:
	var multiplier := float(rules.surge.multiplier)
	var crowd := int(ceil(float(rules.crowd.cap) * multiplier))
	var elite := int(ceil(float(rules.elite.cap) * multiplier))
	return {"crowd": crowd, "elite": elite, "total": crowd + elite}


static func create(rules: Dictionary, seed_value: int) -> Dictionary:
	return {
		"elapsed": 0.0,
		"score": 0,
		"xp": 0,
		"combo": 0,
		"combo_elapsed_ms": 0.0,
		"level": 0,
		"pending": 0,
		"spawn_ms": 0.0,
		"cycle": 0,
		"seed": seed_value
	}


static func crowd_slot(rules: Dictionary, index: int) -> bool:
	return index < int(pool_sizes(rules).crowd)


static func archetype_for(rules: Dictionary, elapsed: float, index: int, random: RandomNumberGenerator) -> int:
	var crowd := crowd_slot(rules, index)
	var table: Array = rules.crowd_archetypes if crowd else rules.elite_archetypes
	var reach := Rules.unlocked(rules, table, elapsed)
	# Later entries are commoner, but the cheap hulls never stop appearing.
	var weights := []
	var total := 0.0
	for position in reach:
		var weight: float = pow(1.6, float(position))
		weights.append(weight)
		total += weight
	var roll := random.randf() * total
	for position in reach:
		roll -= float(weights[position])
		if roll <= 0:
			return int(table[position])
	return int(table[reach - 1])


static func target_counts(rules: Dictionary, elapsed: float) -> Dictionary:
	var sizes := pool_sizes(rules)
	return {
		"crowd": clampi(int(round(Rules.crowd_at(rules, elapsed))), 0, int(sizes.crowd)),
		"elite": clampi(int(round(Rules.elite_at(rules, elapsed))), 0, int(sizes.elite))
	}


static func award(state: Dictionary, rules: Dictionary, value: int, experience: float) -> Dictionary:
	## Combo arithmetic is the archive's: value + (value / 2) * combo, inside the
	## archive's window. XP takes the raw value, deliberately without the combo:
	## every kill fills the bar by what that hull is worth, and nothing else does.
	var result := {"points": 0, "xp": 0, "levels": 0}
	if value <= 0:
		return result
	if state.combo > 0 and state.combo_elapsed_ms <= float(rules.get("combo_ms", 7499)):
		state.combo = int(state.combo) + 1
		result.points = value + (value / 2) * int(state.combo)
	else:
		state.combo = 1
		result.points = value
	state.combo_elapsed_ms = 0.0
	state.score = mini(MAX_COUNTER, int(state.score) + int(result.points))
	result.xp = maxi(1, int(round(float(value) * maxf(0.0, experience))))
	state.xp = mini(MAX_COUNTER, int(state.xp) + int(result.xp))
	result.levels = raise_levels(state, rules)
	return result


static func raise_levels(state: Dictionary, rules: Dictionary) -> int:
	var thresholds := Rules.level_thresholds(rules)
	var gained := 0
	while (
		int(state.level) + 1 < thresholds.size()
		and int(state.xp) >= int(thresholds[int(state.level) + 1])
	):
		state.level = int(state.level) + 1
		state.pending = int(state.pending) + 1
		gained += 1
	return gained


static func advance(state: Dictionary, rules: Dictionary, seconds: float, player: Vector3, slots: Array) -> Dictionary:
	## Returns the spawn requests the arena should apply for this step.
	var result := {"spawns": []}
	if seconds <= 0 or not is_finite(seconds):
		return result
	state.elapsed = float(state.elapsed) + seconds
	state.combo_elapsed_ms = float(state.combo_elapsed_ms) + seconds * 1000.0
	if state.combo_elapsed_ms > float(rules.get("combo_ms", 7499)):
		state.combo = 0
	state.spawn_ms = float(state.spawn_ms) + seconds * 1000.0
	if state.spawn_ms < float(rules.spawn.tick_ms):
		return result
	# One refill stage per elapsed tick, never a burst of several. A long
	# simulation step must not empty the whole spawn budget at once.
	state.spawn_ms = 0.0
	var random := RandomNumberGenerator.new()
	random.seed = int(state.seed) ^ (int(state.cycle) * 7919)
	state.cycle = int(state.cycle) + 1
	var targets := target_counts(rules, float(state.elapsed))
	var sizes := pool_sizes(rules)
	# Two different questions about a slot: whether anything is still fighting
	# from it, and whether its wreck has finished and the slot can be reused. A
	# wreck must never count toward the live population, or a small arena sits
	# half empty while the director believes it is full.
	var alive := {"crowd": 0, "elite": 0}
	for index in slots.size():
		if bool(slots[index].get("fighting", slots[index].alive)):
			alive[("crowd" if crowd_slot(rules, index) else "elite")] += 1
	var budget := int(rules.spawn.per_tick)
	for index in mini(slots.size(), int(sizes.total)):
		if budget <= 0:
			break
		if bool(slots[index].alive):
			continue
		var group := "crowd" if crowd_slot(rules, index) else "elite"
		if alive[group] >= int(targets[group]):
			continue
		alive[group] += 1
		budget -= 1
		result.spawns.append(
			{
				"index": index,
				"archetype": archetype_for(rules, float(state.elapsed), index, random),
				"position": Combat.packed(spawn_point(rules, player, random))
			}
		)
	return result


static func spawn_point(rules: Dictionary, player: Vector3, random: RandomNumberGenerator) -> Vector3:
	var spawn: Dictionary = rules.spawn
	var distance := float(spawn.near) + random.randf() * maxf(0.0, float(spawn.far) - float(spawn.near))
	var direction := Vector3(
		random.randfn(0.0, 1.0), random.randfn(0.0, 1.0), random.randfn(0.0, 1.0)
	)
	if direction.length_squared() < .000001:
		direction = Vector3.FORWARD
	return player + direction.normalized() * distance


static func take_level(state: Dictionary) -> bool:
	if int(state.pending) <= 0:
		return false
	state.pending = int(state.pending) - 1
	return true


static func valid_state(value: Variant, rules: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for key in ["score", "xp", "combo", "level", "pending", "cycle", "seed"]:
		if not Combat.integer(value.get(key)):
			return false
		if key != "seed" and int(value[key]) < 0:
			return false
	for key in ["elapsed", "combo_elapsed_ms", "spawn_ms"]:
		var number: Variant = value.get(key)
		if not Combat.number(number) or number < 0:
			return false
	if float(value.spawn_ms) > float(rules.spawn.tick_ms):
		return false
	var thresholds := Rules.level_thresholds(rules)
	if int(value.level) >= thresholds.size() or int(value.pending) > int(value.level):
		return false
	if int(value.level) > 0 and int(value.xp) < int(thresholds[int(value.level)]):
		return false
	if int(value.score) > MAX_COUNTER or int(value.xp) > MAX_COUNTER:
		return false
	return true
