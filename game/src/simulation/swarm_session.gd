extends "res://src/simulation/session.gd"
## Swarm arcade session. Campaign inventory, rewards and save slots are
## untouched, exactly as the survival session leaves them.
##
## Enemy archetypes, weapon ballistics, hulls and repair amounts are imported.
## Population, pacing, card policy and enemy veterancy are remake-authored and
## live in swarm_rules.gd.
const Rules = preload("res://src/simulation/swarm_rules.gd")
const Build = preload("res://src/simulation/swarm_build.gd")
const Director = preload("res://src/simulation/swarm_director.gd")
const SwarmLoadout = preload("res://src/simulation/swarm_loadout.gd")
const Survival = preload("res://src/simulation/survival.gd")
const SAVE_SCHEMA := 3
const MAX_COUNTER := 1000000000
var rules := {}
var arena := {}
var build := {}
var director := {}
var slot_guns: Array = []
var slot_scales: Array = []
var player_guns := {}
var unlocked_hulls: Array = []
var hud_feedback := {}
var motion_cache := {}


func configure_swarm(data, parameters: Dictionary, origin: int, ship_id: int, hulls: Array, seed_value: int) -> bool:
	if not valid_declarations(data, parameters):
		error = "Unsupported swarm rules or missing imported arcade content."
		return false
	if origin < 0 or origin >= data.stations.size():
		error = "Unsupported swarm location."
		return false
	if ship_id < 0 or ship_id >= data.ships.size() or not hulls.has(ship_id):
		error = "That hull is not available for a swarm run."
		return false
	error = ""
	rules = parameters.duplicate(true)
	rules.combo_ms = int(data.content.survival.rules.combo_ms)
	unlocked_hulls = hulls.duplicate()
	hud_feedback = {}
	super.configure(data)
	slot = "swarm"
	campaign_state = "arcade"
	station_id = origin
	credits = 0
	visited = [origin]
	build = Build.create(ship_id)
	grant_initial_weapon()
	grant_initial_shield()
	loadout = SwarmLoadout.new()
	loadout.configure_build(data, rules, build)
	self.ship_id = ship_id
	weapon_id = initial_weapon()
	arena = {
		"route": [],
		"groups": [],
		"deadline_ms": 0,
		"success": {"kind": "endless"},
		"radio": [],
		"scenery": []
	}
	var sizes := Director.pool_sizes(rules)
	slot_guns = []
	slot_scales = []
	for index in int(sizes.total):
		arena.groups.append(initial_group(index))
		slot_guns.append(Survival.enemy_guns(survival_rules(), survival_armament()))
		slot_scales.append({"hull": 1.0, "damage": 1.0})
		for gun in slot_guns.back():
			remember_profile(gun, gun)
	active_job = Mission.create(arena, 0, origin, library, seed_value, 0, "swarm")
	active_job.swarm = Director.create(rules, seed_value)
	director = active_job.swarm
	for index in active_job.actors.size():
		var actor: Dictionary = active_job.actors[index]
		actor.archetype = -1
		actor.hp = 0.0
		actor.destruction = Mission.Destruction.create(false)
	rebuild_player_guns()
	hull = max_hull()
	shield = max_shield()
	docked = false
	flight_position = Mission.SPAWN_POSITION
	return true


static func valid_declarations(data, parameters: Variant) -> bool:
	if not Rules.valid(parameters):
		return false
	if not data.content.get("survival") is Dictionary:
		return false
	var survival: Variant = data.content.survival.get("rules")
	if not survival is Dictionary or not survival.get("ships") is Dictionary:
		return false
	var count: int = survival.ships.actor.size()
	for key in ["crowd_archetypes", "elite_archetypes"]:
		for index in parameters[key]:
			if int(index) >= count:
				return false
	if not data.content.get("player_armament") is Dictionary:
		return false
	var ladders := Build.ladders(data)
	if not ladders.has(data.SHIELD_CATEGORY) or ladders[data.SHIELD_CATEGORY].is_empty():
		return false
	var weapons := 0
	for category in ladders:
		if int(category) < data.SHIELD_CATEGORY:
			weapons += 1
	if weapons < 1:
		return false
	var amounts: Variant = survival.get("heal_amounts")
	return amounts is Array and not amounts.is_empty()


func survival_rules() -> Dictionary:
	return library.content.survival.rules


func survival_armament() -> Dictionary:
	return library.content.survival.armament


func arena_hull() -> float:
	return float(library.content.survival.setup.hull)


func repair_amounts() -> Array:
	return library.content.survival.rules.heal_amounts


func grant_initial_weapon() -> void:
	## The run opens on the cheapest weapon the chosen hull can mount, taken
	## straight from the catalogue ladder.
	var available := Build.categories(library, int(build.ship))
	var ladders := Build.ladders(library)
	for category in available:
		if ladders.get(category, []).is_empty():
			continue
		build.tier[category] = 1
		return


func grant_initial_shield() -> void:
	## A run opens with the cheapest shield on the catalogue ladder. Without one
	## every graze is permanent hull, and in a crowd there is no avoiding grazes.
	if not Build.ladders(library).get(library.SHIELD_CATEGORY, []).is_empty():
		build.shield = 1


func initial_weapon() -> int:
	var primary := loadout.primary_weapons()
	if not primary.is_empty():
		return int(primary[0])
	var all := loadout.weapons()
	return int(all[0]) if not all.is_empty() else -1


func initial_group(index: int) -> Dictionary:
	var survival := survival_rules()
	var initial := int(survival.initial_archetype)
	var movement: Dictionary = library.content.survival.motion.duplicate(true)
	movement.speed = float(survival.ships.speed[initial]) * 20.0
	var ids := []
	var pool := int(Director.pool_sizes(rules).total)
	for mount in survival_armament().mounts.size():
		ids.append(-1 - index - mount * pool)
	return {
		"actor": int(survival.ships.actor[initial]),
		"count": 1,
		"center": [0, 0, 0],
		"scatter": [],
		"placement": "player_offset",
		"after_route": false,
		"behavior": "interceptor",
		"team": "enemy",
		"motion": movement,
		"weapon_ids": ids,
		"hull": float(survival.ships.hull[initial])
	}


func max_hull() -> float:
	if library == null or build.is_empty():
		return 0.0
	return Build.max_hull(build, rules, library, arena_hull())


func arcade() -> bool:
	return true


func arcade_hud() -> Dictionary:
	return library.content.survival.get("hud", {}) if library != null else {}


func arcade_state() -> Dictionary:
	## Score and combo drive the imported survival readouts. Level and the
	## experience span beside them are this mode's own, and the HUD draws a bar
	## from them so a kill visibly moves the run forward.
	if director.is_empty():
		return {}
	var thresholds := Rules.level_thresholds(rules)
	var level := clampi(int(director.level), 0, thresholds.size() - 1)
	var floor_xp: int = int(thresholds[level])
	var next_xp: int = int(thresholds[mini(level + 1, thresholds.size() - 1)])
	return {
		"score": int(director.score),
		"combo": int(director.combo),
		"level": level,
		"experience": int(director.xp) - floor_xp,
		"experience_span": maxi(1, next_xp - floor_xp),
		"capped": level >= thresholds.size() - 1
	}


func motion_parameters() -> Dictionary:
	## Three imported movement limits this mode scales: boost recharge, which
	## the cards also touch, and contact damage, which no card touches.
	if library == null or build.is_empty():
		return super.motion_parameters()
	var imported: Dictionary = library.content.player_motion
	if motion_cache.is_empty():
		motion_cache = imported.duplicate(true)
	var recharge := float(imported.recharge_seconds) * float(rules.boost_recharge)
	motion_cache.recharge_seconds = maxf(.5, recharge * Build.boost_scale(build, rules))
	motion_cache.contact.damage = float(imported.contact.damage) * float(rules.contact)
	return motion_cache


func agility_scale() -> float:
	return 1.0 if build.is_empty() else Build.agility_scale(build, rules)


func mission_definition() -> Dictionary:
	return arena


func mission_available() -> bool:
	return not arena.is_empty()


func ready_to_finish() -> bool:
	return false


func finish_mission() -> bool:
	return false


func player_weapon_ids(weapon: int) -> Array[int]:
	var result: Array[int] = []
	if library == null or build.is_empty():
		return result
	for category in Build.owned(build, library):
		if Build.weapon(build, library, category) == weapon:
			return Build.weapon_ids(build, rules, library, category)
	return result


func weapon_enabled(weapon: int) -> bool:
	return weapon >= 0 and weapon < library.items.size()


func rebuild_player_guns() -> void:
	var previous := player_guns
	player_guns = Build.guns(build, rules, library, range(arena.groups.size()))
	for id in player_guns:
		remember_profile(player_guns[id], previous.get(id, player_guns[id]))
	loadout.build = build
	loadout.refresh()
	if not loadout.primary_weapons().has(weapon_id):
		weapon_id = initial_weapon()
	shield = minf(shield, max_shield())
	hull = minf(hull, max_hull())


func actor_weapons() -> Dictionary:
	var result := player_guns.duplicate(true)
	for index in slot_guns.size():
		for mount in slot_guns[index].size():
			result[int(arena.groups[index].weapon_ids[mount])] = slot_guns[index][mount]
	return result


static func remember_profile(current: Dictionary, previous: Dictionary) -> void:
	var speeds: Array = previous.get("launch_speeds", [previous.speed]).duplicate()
	if not speeds.has(current.speed):
		speeds.append(current.speed)
	current.launch_speeds = speeds
	current.cooldown_limit = maxf(
		float(current.interval), float(previous.get("cooldown_limit", previous.interval))
	)


func damage_actor(index: int, amount: float) -> bool:
	if not super.damage_actor(index, amount):
		return false
	var actor: Dictionary = active_job.actors[index]
	if actor.hp > 0 or int(actor.archetype) < 0:
		return true
	var value := int(survival_rules().ships.score[int(actor.archetype)])
	Director.award(director, rules, value, Build.experience_scale(build, rules))
	# Salvage is banked straight off the kill. There is nothing to fly out and
	# collect: the run repairs itself only as far as its recovery cards allow.
	var banked := Build.recovery_hull(build, rules, repair_amounts())
	if banked > 0:
		hull = minf(max_hull(), hull + banked)
	return true


func advance_mission(seconds: float) -> void:
	if docked or active_job.is_empty() or hull <= 0:
		return
	Mission.advance(arena, active_job, seconds, library)
	var slots := []
	for actor in active_job.actors:
		slots.append(
			{"alive": not Mission.actor_dead(actor), "fighting": float(actor.hp) > 0.0}
		)
	if hull < max_hull():
		hull = minf(max_hull(), hull + standing_repair() * seconds)
	var event := Director.advance(director, rules, seconds, flight_position, slots)
	for request in event.spawns:
		spawn_slot(int(request.index), int(request.archetype), Combat.vector(request.position))


func spawn_slot(index: int, archetype: int, position: Vector3) -> void:
	var survival := survival_rules()
	var actor: Dictionary = active_job.actors[index]
	var group: Dictionary = arena.groups[index]
	var scales := Rules.veterancy(rules, float(director.elapsed))
	actor.archetype = archetype
	group.actor = int(survival.ships.actor[archetype])
	group.hull = float(survival.ships.hull[archetype]) * float(scales.hull)
	group.motion.speed = float(survival.ships.speed[archetype]) * 20.0
	slot_scales[index] = {"hull": float(scales.hull), "damage": float(scales.damage)}
	apply_slot_guns(index, archetype)
	actor.hp = group.hull
	actor.impact = Mission.Impact.create()
	actor.targeting = Mission.Targeting.create(int(actor.targeting.decisions))
	actor.destruction = Mission.Destruction.create()
	var decisions := int(actor.fighter_motion.decisions)
	actor.fighter_motion = Mission.FighterMotion.create(library.content.fighter_motion, actor.hp)
	if (
		Mission.FighterMotion.mode(
			library.content.fighter_motion, library.content.fighter_steering, group, active_job
		)
		== "boost"
	):
		actor.fighter_motion.decisions = decisions
	actor.position = Combat.packed(position)
	actor.awake = true
	Mission.Evasion.reset(actor)


func apply_slot_guns(index: int, archetype: int) -> void:
	var updated := Survival.replace_enemy_guns(
		slot_guns[index], survival_rules(), survival_armament(), archetype
	)
	for mount in updated.size():
		updated[mount].damage = maxf(
			1.0, float(updated[mount].damage) * float(slot_scales[index].damage)
		)
		remember_profile(updated[mount], slot_guns[index][mount])
	slot_guns[index] = updated


func standing_repair() -> float:
	## Hull per second, always. The amount is the archive's smallest repair; the
	## span it is spread over is this mode's rule.
	var amounts: Array = repair_amounts()
	if amounts.is_empty():
		return 0.0
	return float(amounts.min()) / maxf(1.0, float(rules.repair_seconds))


func level_pending() -> bool:
	return not director.is_empty() and int(director.pending) > 0


func card_offers() -> Array:
	if not level_pending():
		return []
	var random := RandomNumberGenerator.new()
	random.seed = int(director.seed) ^ (int(director.level) * 40503) ^ int(director.pending)
	return Build.draw(build, rules, library, random, unlocked_hulls)


func choose_card(card: Variant) -> bool:
	if not level_pending():
		return false
	if card is Dictionary and not card.is_empty():
		if not Build.apply(build, rules, library, card):
			return false
		build.level = int(director.level)
		rebuild_player_guns()
	else:
		hull = minf(
			max_hull(),
			hull + max_hull() * float(rules.cards.decline_repair_percent) * .01
		)
	Director.take_level(director)
	return true


func retry_mission() -> void:
	configure_swarm(
		library, rules, station_id, int(build.ship), unlocked_hulls, int(active_job.seed) + 1
	)


func capture() -> Dictionary:
	if active_job.is_empty():
		return {}
	var actors := []
	for actor in active_job.actors:
		var stored := {}
		for key in [
			"hp",
			"awake",
			"position",
			"heading",
			"up",
			"breaking",
			"shots",
			"archetype",
			"destruction",
			"evasion",
			"fighter_motion",
			"impact",
			"targeting"
		]:
			stored[key] = actor[key]
		actors.append(stored.duplicate(true))
	return {
		"schema": SAVE_SCHEMA,
		"slot": "swarm",
		"content_id": content_id,
		"station_id": station_id,
		"ship_id": ship_id,
		"weapon_id": weapon_id,
		"seed": int(active_job.seed),
		"kills": int(active_job.kills),
		"elapsed": elapsed,
		"mission_elapsed_ms": float(active_job.elapsed_ms),
		"hull": hull,
		"shield": shield,
		"position": Combat.packed(flight_position),
		"rotation": Combat.packed(flight_rotation),
		"motion": motion.duplicate(true),
		"combat": combat.duplicate(true),
		"director": director.duplicate(true),
		"build": build.duplicate(true),
		"hulls": unlocked_hulls.duplicate(),
		"scales": slot_scales.duplicate(true),
		"actors": actors
	}


func restore(value: Variant) -> bool:
	error = ""
	if library == null or rules.is_empty() or not valid_snapshot_header(value):
		error = "Invalid swarm save or different game content."
		return false
	var candidate = get_script().new()
	if (
		not candidate.configure_swarm(
			library,
			rules,
			int(value.station_id),
			int(Build.normalize(value.build).ship),
			value.hulls.duplicate(),
			int(value.seed)
		)
		or not candidate.apply_snapshot(value)
	):
		error = "The swarm save contains inconsistent flight or build state."
		return false
	for key in [
		"hud_feedback",
		"arena",
		"slot_guns",
		"slot_scales",
		"player_guns",
		"build",
		"director",
		"unlocked_hulls",
		"loadout",
		"ship_id",
		"weapon_id",
		"station_id",
		"motion",
		"combat",
		"hull",
		"shield",
		"elapsed",
		"flight_position",
		"flight_rotation",
		"active_job",
		"slot",
		"campaign_state",
		"credits",
		"visited",
		"cargo",
		"recovery",
		"contract_rewards",
		"docked"
	]:
		set(key, candidate.get(key))
	director = active_job.swarm
	return true


func valid_snapshot_header(value: Variant) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			[
				"schema",
				"slot",
				"content_id",
				"station_id",
				"ship_id",
				"weapon_id",
				"seed",
				"kills",
				"elapsed",
				"mission_elapsed_ms",
				"hull",
				"shield",
				"position",
				"rotation",
				"motion",
				"combat",
				"director",
				"build",
				"hulls",
				"scales",
				"actors"
			]
		)
	):
		return false
	if value.schema != SAVE_SCHEMA or value.slot != "swarm" or value.content_id != content_id:
		return false
	for key in ["station_id", "ship_id", "weapon_id", "seed", "kills"]:
		if not Combat.integer(value[key]):
			return false
	if (
		int(value.station_id) < 0
		or int(value.station_id) >= library.stations.size()
		or int(value.kills) < 0
		or int(value.kills) > MAX_COUNTER
	):
		return false
	for key in ["elapsed", "mission_elapsed_ms", "hull", "shield"]:
		if not Combat.number(value[key]) or value[key] < 0 or value[key] > 1e12:
			return false
	if (
		absf(float(value.elapsed) * 1000.0 - float(value.mission_elapsed_ms)) > .1
		or not Combat.valid_vector(value.position)
		or not Combat.valid_vector(value.rotation)
		or not Motion.valid(value.motion, motion_parameters())
	):
		return false
	if not value.hulls is Array or value.hulls.is_empty() or value.hulls.size() > 128:
		return false
	for id in value.hulls:
		if not Combat.integer(id) or int(id) < 0 or int(id) >= library.ships.size():
			return false
	if not Build.valid(Build.normalize(value.build), rules, library):
		return false
	if not Director.valid_state(value.director, rules):
		return false
	var sizes := Director.pool_sizes(rules)
	if not value.scales is Array or value.scales.size() != int(sizes.total):
		return false
	for scale in value.scales:
		if not scale is Dictionary:
			return false
		for key in ["hull", "damage"]:
			var span: Array = rules.veterancy[key]
			if (
				not Combat.number(scale.get(key))
				or scale[key] < float(span[0])
				or scale[key] > float(span[1])
			):
				return false
	if not value.actors is Array or value.actors.size() != int(sizes.total):
		return false
	var director_state: Dictionary = value.director
	if int(director_state.seed) != int(value.seed):
		return false
	# The director and the mission clock are both driven by advance_mission, so
	# they are the pair that must agree. Flight advances session elapsed beside
	# them and is checked against the mission clock above.
	if absf(float(director_state.elapsed) * 1000.0 - float(value.mission_elapsed_ms)) > .1:
		return false
	return int(director_state.combo) <= int(value.kills)


func apply_snapshot(value: Dictionary) -> bool:
	build = Build.normalize(value.build)
	rebuild_player_guns()
	if int(value.weapon_id) >= 0 and not loadout.weapons().has(int(value.weapon_id)):
		return false
	if float(value.hull) > max_hull() or float(value.shield) > max_shield():
		return false
	var survival := survival_rules()
	var known: Array = rules.crowd_archetypes + rules.elite_archetypes
	for index in value.actors.size():
		var saved: Variant = value.actors[index]
		if not valid_saved_actor(saved, index, known):
			return false
		var actor: Dictionary = active_job.actors[index]
		var archetype := int(saved.archetype)
		slot_scales[index] = {
			"hull": float(value.scales[index].hull), "damage": float(value.scales[index].damage)
		}
		if archetype >= 0:
			var group: Dictionary = arena.groups[index]
			group.actor = int(survival.ships.actor[archetype])
			group.hull = float(survival.ships.hull[archetype]) * float(slot_scales[index].hull)
			group.motion.speed = float(survival.ships.speed[archetype]) * 20.0
			apply_slot_guns(index, archetype)
			if float(saved.hp) > group.hull:
				return false
		elif float(saved.hp) != 0:
			return false
		if (
			not Mission.Frame.valid(saved)
			or not Mission.Targeting.valid(saved, library.content.fighter_targeting, [-1])
			or not Mission.Impact.valid(saved, library.content.fighter_impact)
			or not Mission.Evasion.valid(saved)
		):
			return false
		if not Mission.FighterMotion.valid_actor(saved, arena.groups[index], active_job, library):
			return false
		for key in [
			"hp",
			"awake",
			"position",
			"heading",
			"up",
			"breaking",
			"shots",
			"archetype",
			"destruction",
			"evasion",
			"fighter_motion",
			"impact",
			"targeting"
		]:
			actor[key] = saved[key] if not saved[key] is Dictionary else saved[key].duplicate(true)
		actor.shots = int(actor.shots)
		actor.archetype = int(actor.archetype)
	var profiles := actor_weapons()
	if not Combat.valid(value.combat, library, profiles):
		return false
	for shot in value.combat.projectiles:
		if not profiles.has(int(shot.weapon)):
			return false
	for key in value.combat.cooldowns:
		if not profiles.has(int(key)):
			return false
	active_job.swarm = value.director.duplicate(true)
	director = active_job.swarm
	for key in ["score", "xp", "combo", "level", "pending", "cycle", "seed"]:
		director[key] = int(director[key])
	active_job.kills = int(value.kills)
	active_job.elapsed_ms = float(value.mission_elapsed_ms)
	unlocked_hulls = value.hulls.duplicate()
	weapon_id = int(value.weapon_id)
	hull = float(value.hull)
	shield = float(value.shield)
	elapsed = float(value.elapsed)
	flight_position = Combat.vector(value.position)
	flight_rotation = Combat.vector(value.rotation)
	motion = value.motion.duplicate(true)
	combat = Combat.normalize(value.combat)
	return true


func valid_saved_actor(value: Variant, index: int, known: Array) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			["hp", "awake", "position", "heading", "breaking", "shots", "archetype"]
		)
	):
		return false
	if (
		not Combat.number(value.hp)
		or float(value.hp) < 0
		or not value.awake is bool
		or not value.breaking is bool
		or not Combat.valid_vector(value.position)
		or not Combat.valid_vector(value.heading)
		or not is_equal_approx(Combat.vector(value.heading).length(), 1.0)
		or not Combat.integer(value.shots)
		or int(value.shots) < 0
		or int(value.shots) > MAX_COUNTER
		or not Combat.integer(value.archetype)
	):
		return false
	var archetype := int(value.archetype)
	if archetype < 0:
		return archetype == -1
	if not known.has(archetype):
		return false
	# Crowd and elite pools are disjoint, so a saved slot cannot hold the other
	# half's archetype and inherit the wrong population budget on resume.
	var crowd := Director.crowd_slot(rules, index)
	return rules.crowd_archetypes.has(archetype) == crowd


func save(path: String) -> bool:
	if library == null or rules.is_empty() or active_job.is_empty():
		error = "No swarm run is available to save."
		return false
	if path.get_file() != "swarm.json" or path.get_base_dir().get_file() != content_id:
		error = "Swarm saves require their own game-content slot."
		return false
	var probe = get_script().new()
	if (
		not probe.configure_swarm(
			library, rules, station_id, int(build.ship), unlocked_hulls, int(active_job.seed)
		)
		or not probe.restore(capture())
	):
		error = "Cannot save inconsistent swarm state."
		return false
	return super.save(path)
