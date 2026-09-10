extends "res://src/simulation/session.gd"
## Separate arcade state. Campaign inventory, rewards and save slots are untouched.
const Survival = preload("res://src/simulation/survival.gd")
const SurvivalLoadout = preload("res://src/simulation/survival_loadout.gd")
const SAVE_SCHEMA := 10
const MAX_COUNTER := 1000000000
const MAX_SAFE_INTEGER := 9007199254740991
var declarations := {}
var arena := {}
var next_ship_cycle := 0
var slot_guns: Array = []
var player_guns := {}
# Cosmetic HUD state survives pause/menu recreation, not serialized checkpoints.
var hud_feedback := {}


func configure_survival(
	data, content: Dictionary, origin: int, cycle: int, seed_value: int
) -> bool:
	if not valid_declarations(content, data) or origin < 0 or origin >= data.stations.size():
		error = "Unsupported survival declarations or location."
		return false
	error = ""
	declarations = content.duplicate(true)
	hud_feedback = {}
	super.configure(data)
	slot = "survival"
	campaign_state = "arcade"
	station_id = origin
	credits = 0
	visited = [origin]
	var pilot := Survival.initial_player(declarations.setup, cycle)
	ship_id = int(pilot.ship_index)
	next_ship_cycle = int(pilot.next_cycle)
	loadout = SurvivalLoadout.new()
	loadout.configure_start(data, declarations.setup)
	weapon_id = int(loadout.primary_weapons()[0])
	hull = max_hull()
	shield = max_shield()
	arena = {
		"route": [],
		"groups": [],
		"deadline_ms": 0,
		"success": {"kind": "endless"},
		"radio": [],
		"scenery": []
	}
	slot_guns = []
	player_guns = {}
	for id in loadout.weapons():
		var source_gun: Dictionary = declarations.armament.player[str(id)]
		var ids := player_weapon_ids(id)
		for mount in ids.size():
			var gun: Dictionary = library.weapon_ballistics(id)
			gun.damage = int(
				(
					float(source_gun.get("damage_override", gun.damage))
					/ int(source_gun.damage_divisor)
				)
			)
			gun.sort = int(library.items[id][1])
			gun.team = "ally"
			gun.mount_offset = source_gun.mounts[mount].duplicate()
			gun.pool_capacity = int(source_gun.pool_capacity)
			gun.projectile_model = int(source_gun.projectile_model)
			if source_gun.has("projectile_overlay"):
				gun.projectile_overlay = int(source_gun.projectile_overlay)
			if source_gun.has("trail"):
				gun.trail = source_gun.trail.duplicate(true)
			if source_gun.has("guidance"):
				gun.guidance = source_gun.guidance.duplicate(true)
				gun.guidance_target_ids = range(int(declarations.rules.pool_size))
			remember_profile(gun, gun)
			player_guns[ids[mount]] = gun

	var rules: Dictionary = declarations.rules
	for index in int(rules.pool_size):
		var group := initial_group(index)
		arena.groups.append(group)
		slot_guns.append(Survival.enemy_guns(rules, declarations.armament))
		for gun in slot_guns.back():
			remember_profile(gun, gun)
	active_job = Mission.create(arena, 0, origin, library, seed_value, 0, "survival")
	active_job.survival = Survival.create(rules, seed_value)
	for index in active_job.actors.size():
		var actor: Dictionary = active_job.actors[index]
		actor.archetype = int(rules.initial_archetype)
		actor.promotions = []
		actor.score = (
			int(rules.ships.score[int(rules.initial_archetype)])
			if index < int(rules.initial_active)
			else int(declarations.setup.reserved_score)
		)
		if index >= int(rules.initial_active):
			actor.hp = 0.0
			actor.destruction = Mission.Destruction.create(false)
	docked = false
	flight_position = Mission.SPAWN_POSITION
	return true


static func valid_declarations(value: Dictionary, data) -> bool:
	if not value.has_all(["rules", "setup", "armament", "motion"]):
		return false
	if (
		not Survival.valid(value.rules)
		or not Survival.valid_setup(value.setup, data)
		or not Survival.valid_armament(value.armament, value.rules)
		or not valid_player_armament(value.armament.get("player"), value.setup, data)
		or not value.motion is Dictionary
	):
		return false
	if value.setup.type != value.rules.type:
		return false
	var primary := false
	for id in value.setup.equipment:
		var category := int(data.items[int(id)][1])
		if category < data.SHIELD_CATEGORY:
			if data.weapon_ballistics(int(id)).is_empty():
				return false
			if category != data.MISSILE_CATEGORY:
				primary = true
	if not primary:
		return false
	for key in [
		"speed", "turn_response", "aim_sine", "fire_half_width", "avoid_distance", "wake_half_width"
	]:
		if (
			not Combat.number(value.motion.get(key))
			or value.motion[key] <= 0
			or value.motion[key] > 1000000
		):
			return false
	if value.setup.reserved_actor != value.rules.ships.actor[int(value.rules.initial_archetype)]:
		return false
	if value.motion.aim_sine > 1:
		return false
	for actor in value.rules.ships.actor:
		if int(actor) >= data.content.tables.actor_hull.size():
			return false
	for table in [
		value.rules.ships.projectile_model,
		value.rules.upgrades.projectile_model,
		value.armament.replacement_models
	]:
		for model in table:
			if not data.content.resources.has(str(int(model))):
				return false
	return true


static func valid_player_armament(value: Variant, setup: Dictionary, data) -> bool:
	if not value is Dictionary:
		return false
	var expected := []
	for id in setup.equipment:
		if int(data.items[int(id)][1]) < data.SHIELD_CATEGORY:
			expected.append(str(int(id)))
	if value.size() != expected.size():
		return false
	for key in expected:
		var record: Variant = value.get(key)
		if (
			not record is Dictionary
			or not record.get("mounts") is Array
			or record.mounts.is_empty()
			or record.mounts.size() > 32
		):
			return false
		for mount in record.mounts:
			if not Combat.valid_vector(mount) or Combat.vector(mount).length() > 1000000:
				return false
		for field in ["damage_divisor", "pool_capacity"]:
			if not Combat.integer(record.get(field)) or record[field] <= 0 or record[field] > 4096:
				return false
		if (
			record.has("damage_override")
			and (
				not Combat.integer(record.damage_override)
				or record.damage_override < 0
				or record.damage_override > 1000000000
			)
		):
			return false
		for field in ["projectile_model", "projectile_overlay"]:
			if field == "projectile_overlay" and not record.has(field):
				continue
			if (
				not Combat.integer(record.get(field))
				or not data.content.resources.has(str(int(record[field])))
			):
				return false
		if record.has("guidance") and not Combat.Guidance.valid_parameters(record.guidance):
			return false
	return true


func player_weapon_ids(weapon: int) -> Array[int]:
	var result: Array[int] = []
	if not declarations.armament.player.has(str(weapon)):
		return result
	# Keep the inventory identity for the first muzzle. Additional native muzzle
	# IDs occupy disjoint catalogue-sized ranges, separate from negative NPC IDs.
	for mount in declarations.armament.player[str(weapon)].mounts.size():
		result.append(weapon + mount * library.items.size())
	return result


func initial_group(index: int) -> Dictionary:
	var rules: Dictionary = declarations.rules
	var initial := int(rules.initial_archetype)
	var movement: Dictionary = declarations.motion.duplicate(true)
	movement.speed = (
		(
			float(rules.ships.speed[initial])
			if index < int(rules.initial_active)
			else float(declarations.setup.reserved_speed)
		)
		* 20.0
	)
	var ids := []
	for mount in declarations.armament.mounts.size():
		ids.append(-1 - index - mount * int(rules.pool_size))
	return {
		"actor": int(rules.ships.actor[initial]),
		"count": 1,
		"center": declarations.setup.initial_offset.duplicate(),
		"scatter":
		declarations.setup.scatter.duplicate() if index < int(rules.initial_active) else [],
		"placement": "player_offset",
		"after_route": false,
		"behavior": "interceptor",
		"team": "enemy",
		"motion": movement,
		"weapon_ids": ids,
		"hull":
		(
			float(rules.ships.hull[initial])
			if index < int(rules.initial_active)
			else float(declarations.setup.reserved_hull)
		)
	}


func max_hull() -> float:
	return float(declarations.get("setup", {}).get("hull", 0))


func mission_definition() -> Dictionary:
	return arena


func mission_available() -> bool:
	return not arena.is_empty()


func ready_to_finish() -> bool:
	return false


func finish_mission() -> bool:
	return false


func damage_actor(index: int, amount: float) -> bool:
	if not super.damage_actor(index, amount):
		return false
	var actor: Dictionary = active_job.actors[index]
	if actor.hp <= 0:
		var reward := Survival.award(active_job.survival, declarations.rules, int(actor.score))
		hull = minf(max_hull(), hull + int(reward.heal))
	return true


func advance_mission(seconds: float) -> void:
	if docked or active_job.is_empty() or hull <= 0:
		return
	Mission.advance(arena, active_job, seconds, library)
	var slots := []
	for actor in active_job.actors:
		slots.append({"alive": not Mission.actor_dead(actor), "archetype": int(actor.archetype)})
	var position := Vector3(flight_position.x, flight_position.y, -flight_position.z) / .02
	var event := Survival.advance(active_job.survival, declarations.rules, seconds, position, slots)
	if not event.upgrade.is_empty():
		for id in player_guns:
			var old: Dictionary = player_guns[id]
			var promoted := Survival.promote_weapon(old, event.upgrade, declarations.armament, true)
			remember_profile(promoted, old)
			player_guns[id] = promoted
	for request in event.respawns:
		var index := int(request.index)
		var actor: Dictionary = active_job.actors[index]
		var group: Dictionary = arena.groups[index]
		if request.replace:
			var archetype := int(request.archetype)
			var rules: Dictionary = declarations.rules
			actor.archetype = archetype
			actor.score = int(rules.ships.score[archetype])
			if not actor.promotions.has(archetype):
				actor.promotions.append(archetype)
			group.actor = int(rules.ships.actor[archetype])
			group.hull = float(rules.ships.hull[archetype])
			group.motion.speed = float(rules.ships.speed[archetype]) * 20.0
			var updated := Survival.replace_enemy_guns(
				slot_guns[index], rules, declarations.armament, archetype
			)
			for mount in updated.size():
				remember_profile(updated[mount], slot_guns[index][mount])
			slot_guns[index] = updated
		actor.hp = group.hull
		actor.impact = Mission.Impact.create()
		actor.targeting = Mission.Targeting.create(int(actor.targeting.decisions))
		actor.destruction = Mission.Destruction.create()
		var decisions: int = int(actor.fighter_motion.decisions)
		actor.fighter_motion = Mission.FighterMotion.create(
			library.content.fighter_motion, actor.hp
		)
		if (
			Mission.FighterMotion.mode(
				library.content.fighter_motion, library.content.fighter_steering, group, active_job
			)
			== "boost"
		):
			actor.fighter_motion.decisions = decisions
		actor.position = Combat.packed(Mission.point(request.source_position))
		actor.awake = true
		Mission.Evasion.reset(actor)


static func remember_profile(current: Dictionary, previous: Dictionary) -> void:
	var speeds: Array = previous.get("launch_speeds", [previous.speed]).duplicate()
	if not speeds.has(current.speed):
		speeds.append(current.speed)
	current.launch_speeds = speeds
	current.cooldown_limit = maxf(
		float(current.interval), float(previous.get("cooldown_limit", previous.interval))
	)


func weapon_enabled(weapon: int) -> bool:
	if weapon < 0 or weapon >= library.items.size():
		return false
	return (
		int(library.items[weapon][1]) != library.MISSILE_CATEGORY
		or int(active_job.survival.score) > int(declarations.setup.missile_score_above)
	)


func actor_weapons() -> Dictionary:
	var result := player_guns.duplicate(true)
	for index in slot_guns.size():
		for mount in slot_guns[index].size():
			result[int(arena.groups[index].weapon_ids[mount])] = slot_guns[index][mount]
	return result


func retry_mission() -> void:
	configure_survival(library, declarations, station_id, next_ship_cycle, int(active_job.seed) + 1)


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
			"promotions",
			"destruction",
			"evasion",
			"fighter_motion",
			"impact",
			"targeting"
		]:
			stored[key] = actor[key]
		actors.append(stored.duplicate(true))
	# Store changing state, not derived guns, health limits, rewards or geometry.
	return {
		"schema": SAVE_SCHEMA,
		"slot": "survival",
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
		"director": active_job.survival.duplicate(true),
		"actors": actors
	}


func restore(value: Variant) -> bool:
	error = ""
	if value is Dictionary and value.get("schema") == 2:
		value = value.duplicate(true)
		value.schema = 3
		if not Mission.Destruction.migrate_actors(value.get("actors")):
			error = "Invalid legacy survival actors."
			return false
	if value is Dictionary and value.get("schema") == 3:
		value = value.duplicate(true)
		value.schema = 4
		if not Mission.Destruction.migrate_motion(value.get("actors")):
			error = "Invalid legacy survival momentum."
			return false
	if value is Dictionary and value.get("schema") == 4:
		value = value.duplicate(true)
		value.schema = 5
		if not Mission.Evasion.migrate(value.get("actors")):
			error = "Invalid legacy survival maneuver state."
			return false
	if value is Dictionary and value.get("schema") == 5 and library != null:
		value = value.duplicate(true)
		value.schema = 6
		if not Mission.FighterMotion.migrate(value.get("actors"), library.content.fighter_motion):
			error = "Invalid legacy survival speed state."
			return false

	if value is Dictionary and value.get("schema") == 6:
		value = value.duplicate(true)
		value.schema = 7
		if not Mission.Frame.migrate(value.get("actors")):
			error = "Invalid legacy survival orientation."
			return false

	if value is Dictionary and value.get("schema") == 7:
		value = value.duplicate(true)
		value.schema = 8
		if not Mission.Impact.migrate(value.get("actors")):
			error = "Invalid legacy survival impact state."
			return false

	if value is Dictionary and value.get("schema") == 8:
		value = value.duplicate(true)
		value.schema = 9
		if not Mission.Targeting.migrate(value.get("actors")):
			error = "Invalid legacy survival targeting state."
			return false
	if value is Dictionary and value.get("schema") == 9:
		value = value.duplicate(true)
		value.schema = 10
		if value.get("motion") is Dictionary:
			value.motion.contact_elapsed = 0.0

	if library == null or declarations.is_empty() or not valid_snapshot_header(value):
		error = "Invalid survival save or different game content."
		return false
	# Validate on a separate session. A failed load cannot alter current play.
	var candidate = get_script().new()
	if (
		not candidate.configure_survival(
			library, declarations, int(value.station_id), int(value.ship_id), int(value.seed)
		)
		or not candidate.apply_snapshot(value)
	):
		error = "The survival save contains inconsistent flight or upgrade state."
		return false
	for key in [
		"hud_feedback",
		"arena",
		"slot_guns",
		"player_guns",
		"next_ship_cycle",
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
				"actors"
			]
		)
	):
		return false
	if value.schema != SAVE_SCHEMA or value.slot != "survival" or value.content_id != content_id:
		return false
	for key in ["station_id", "ship_id", "weapon_id", "seed", "kills"]:
		if not Combat.integer(value[key]) or absf(float(value[key])) > MAX_SAFE_INTEGER:
			return false
	if (
		value.station_id < 0
		or value.station_id >= library.stations.size()
		or value.ship_id < 0
		or value.ship_id >= declarations.setup.ship_count
		or value.kills < 0
		or value.kills > MAX_COUNTER
	):
		return false
	for key in ["elapsed", "mission_elapsed_ms", "hull", "shield"]:
		if not Combat.number(value[key]) or value[key] < 0 or value[key] > 1e12:
			return false
	if (
		value.hull > max_hull()
		or value.shield > declarations.setup.shield_capacity
		or absf(float(value.elapsed) * 1000.0 - float(value.mission_elapsed_ms)) > .1
		or not Combat.valid_vector(value.position)
		or not Combat.valid_vector(value.rotation)
		or not Motion.valid(value.motion, library.content.player_motion)
		or not Survival.valid_state(value.director, declarations.rules)
		or not value.actors is Array
		or value.actors.size() != declarations.rules.pool_size
	):
		return false
	var director: Dictionary = value.director
	for key in ["score", "combo", "cycle", "seed"]:
		if absf(float(director[key])) > MAX_SAFE_INTEGER:
			return false
	if (
		director.seed != value.seed
		or director.cycle > MAX_COUNTER
		or director.combo > value.kills
		or (director.score == 0) != (director.combo == 0)
		or (value.kills == 0 and director.score != 0)
	):
		return false
	var stages := int(director.cycle) * 2 + (1 if director.phase == "spawn" else 0)
	if (
		(
			stages * float(declarations.rules.tick_ms) + float(director.timer_ms)
			> value.mission_elapsed_ms + .1
		)
		or director.combo_elapsed_ms > value.mission_elapsed_ms + .1
	):
		return false
	var upgraded := int(director.upgrade_index)
	if upgraded > 0 and director.score < declarations.rules.upgrades.score[upgraded - 1]:
		return false
	if (
		director.active_count > declarations.rules.initial_active
		and director.score <= declarations.rules.thresholds[int(director.active_count) - 1]
	):
		return false
	return true


func apply_snapshot(value: Dictionary) -> bool:
	if not loadout.primary_weapons().has(int(value.weapon_id)):
		return false
	var director: Dictionary = value.director
	var rules: Dictionary = declarations.rules
	for step in int(director.upgrade_index):
		var row := {}
		for key in rules.upgrades:
			row[key] = rules.upgrades[key][step]
		for id in player_guns:
			var old: Dictionary = player_guns[id]
			player_guns[id] = Survival.promote_weapon(old, row, declarations.armament, true)
			remember_profile(player_guns[id], old)
	var actor_shots := 0
	var deaths_visible := 0
	for index in value.actors.size():
		var saved: Variant = value.actors[index]
		if not valid_saved_actor(saved, index, director):
			return false
		var history: Array = saved.promotions.map(func(item): return int(item))
		var actor: Dictionary = active_job.actors[index]
		for archetype in history:
			restore_actor_profile(index, archetype)
		if not history.is_empty():
			restore_actor_profile(index, int(saved.archetype))
		if saved.hp > arena.groups[index].hull:
			return false
		if (
			not Mission.Frame.valid(saved)
			or not Mission.Targeting.valid(saved, library.content.fighter_targeting, [-1])
			or not Mission.Impact.valid(
				saved,
				library.content.fighter_impact,
				true,
				(
					int(arena.groups[index].actor)
					== int(library.content.fighter_impact.no_tumble_actor)
				)
			)
		):
			return false
		if not Mission.FighterMotion.valid_actor(saved, arena.groups[index], active_job, library):
			return false
		if saved.fighter_motion.hull_seen > arena.groups[index].hull:
			return false
		if not Mission.Destruction.valid(
			saved.get("destruction"),
			saved.hp,
			Mission.Destruction.effect(library, int(arena.groups[index].actor)),
			Mission.FighterMotion.speed_limit(
				saved,
				arena.groups[index],
				active_job,
				library,
				Mission.Destruction.speed_limit(arena.groups[index])
			)
		):
			return false
		if (
			index >= int(director.active_count)
			and (
				saved.destruction.phase != "dead"
				or not Mission.Evasion.valid(saved, false)
				or saved.evasion.decisions != 0
				or saved.fighter_motion.phase != "idle"
				or saved.fighter_motion.speed != library.content.fighter_motion.initial_speed
				or saved.fighter_motion.elapsed != 0
				or saved.fighter_motion.decisions != 0
				or saved.fighter_motion.duration != 0
				or saved.fighter_motion.damage != 0
				or saved.fighter_motion.forced
				or not Mission.Targeting.valid(saved, library.content.fighter_targeting, [], false)
				or saved.impact.active
			)
		):
			return false
		var restored_actor: Dictionary = saved.duplicate(true)
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
			actor[key] = restored_actor[key]
		actor.shots = int(actor.shots)
		actor.archetype = int(actor.archetype)
		actor.promotions = history
		actor_shots += actor.shots
		if index < int(rules.initial_active) and actor.hp <= 0:
			deaths_visible += 1
	if (
		value.kills < deaths_visible
		or value.kills > (int(director.cycle) + 1) * int(rules.max_active)
	):
		return false
	var profiles := actor_weapons()
	if not Combat.valid(value.combat, library, profiles) or actor_shots > value.combat.next_id:
		return false
	var pools := {}
	for shot in value.combat.projectiles:
		var id := int(shot.weapon)
		if not profiles.has(id):
			return false
		if id < 0 and (-1 - id) % int(rules.pool_size) >= int(director.active_count):
			return false
		pools[id] = int(pools.get(id, 0)) + 1
		if profiles[id].has("pool_capacity") and pools[id] > profiles[id].pool_capacity:
			return false
	for key in value.combat.cooldowns:
		var id := int(key)
		if not profiles.has(id):
			return false
		if id < 0 and (-1 - id) % int(rules.pool_size) >= int(director.active_count):
			return false
	active_job.survival = director.duplicate(true)
	for key in ["score", "combo", "active_count", "upgrade_index", "cycle", "seed"]:
		active_job.survival[key] = int(active_job.survival[key])
	active_job.kills = int(value.kills)
	active_job.elapsed_ms = float(value.mission_elapsed_ms)
	weapon_id = int(value.weapon_id)
	hull = float(value.hull)
	shield = float(value.shield)
	elapsed = float(value.elapsed)
	flight_position = Combat.vector(value.position)
	flight_rotation = Combat.vector(value.rotation)
	motion = value.motion.duplicate(true)
	combat = Combat.normalize(value.combat)
	return true


func valid_saved_actor(value: Variant, index: int, director: Dictionary) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			["hp", "awake", "position", "heading", "breaking", "shots", "archetype", "promotions"]
		)
	):
		return false
	if (
		not Combat.number(value.hp)
		or value.hp < 0
		or not value.awake is bool
		or not value.breaking is bool
		or not Mission.Evasion.valid(value)
		or not Mission.Impact.valid(value, library.content.fighter_impact)
		or not value.awake
		or not Combat.valid_vector(value.position)
		or not Combat.valid_vector(value.heading)
		or not is_equal_approx(Combat.vector(value.heading).length(), 1.0)
		or not Combat.integer(value.shots)
		or value.shots < 0
		or value.shots > MAX_COUNTER
		or not Combat.integer(value.archetype)
		or not value.promotions is Array
	):
		return false
	var rules: Dictionary = declarations.rules
	var initial := int(rules.initial_archetype)
	var count := mini(int(director.active_count) - 1, int(rules.promotion_cap))
	if value.promotions.size() > count:
		return false
	var seen := []
	for archetype in value.promotions:
		if (
			not Combat.integer(archetype)
			or archetype < 0
			or archetype >= count
			or seen.has(int(archetype))
		):
			return false
		seen.append(int(archetype))
	if seen.is_empty():
		if value.archetype != initial:
			return false
	else:
		if seen[0] == initial or not seen.has(int(value.archetype)):
			return false
		for archetype in seen:
			if (
				(
					archetype >= rules.promotable_count
					or rules.ships.actor[archetype] == rules.fixed_actor
				)
				and (value.archetype != archetype or seen.back() != archetype)
			):
				return false
	if (
		index >= director.active_count
		and (value.hp != 0 or value.shots != 0 or not seen.is_empty() or value.breaking)
	):
		return false
	return true


func restore_actor_profile(index: int, archetype: int) -> void:
	var rules: Dictionary = declarations.rules
	var actor: Dictionary = active_job.actors[index]
	var group: Dictionary = arena.groups[index]
	actor.score = int(rules.ships.score[archetype])
	group.actor = int(rules.ships.actor[archetype])
	group.hull = float(rules.ships.hull[archetype])
	group.motion.speed = float(rules.ships.speed[archetype]) * 20.0
	var updated := Survival.replace_enemy_guns(
		slot_guns[index], rules, declarations.armament, archetype
	)
	for mount in updated.size():
		remember_profile(updated[mount], slot_guns[index][mount])
	slot_guns[index] = updated


func save(path: String) -> bool:
	if library == null or declarations.is_empty() or active_job.is_empty():
		error = "No survival run is available to save."
		return false
	# A mode must never overwrite campaign/free-play slots, even through a caller
	# accidentally retaining the previous slot's path during a menu transition.
	if path.get_file() != "survival.json" or path.get_base_dir().get_file() != content_id:
		error = "Survival saves require their own game-content slot."
		return false
	var probe = get_script().new()
	if (
		not probe.configure_survival(
			library, declarations, station_id, ship_id, int(active_job.seed)
		)
		or not probe.restore(capture())
	):
		error = "Cannot save inconsistent survival state."
		return false
	return super.save(path)
