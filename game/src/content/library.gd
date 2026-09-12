extends RefCounted
const Scenery = preload("res://src/simulation/scenery.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Contracts = preload("res://src/simulation/contracts.gd")
const ContractEncounters = preload("res://src/simulation/contract_encounters.gd")
const Sequence = preload("res://src/simulation/sequence.gd")
const Formats = preload("res://src/content/formats.gd")
const LIT_SHADER = preload("res://src/presentation/lit.gdshader")
const ADDITIVE_SHADER = preload("res://src/presentation/additive.gdshader")
const StationModel = preload("res://src/presentation/station.gd")
const SHIELD_CATEGORY := 5
const CARGO_CATEGORY := 6
const MISSILE_CATEGORY := 3
var root := ""
var id := ""
var language_code := "gb"
var strings := PackedStringArray()
var ships: Array = []
var items: Array = []
var stations: Array = []
var systems: Array = []
var quadrants: Array = []
var content := {}
var mesh_cache := {}
var texture_cache := {}
var material_cache := {}
var lighting_profile := {}
var model_materials := {}
var reader := Formats.new()
var error := ""
var radio_atlases := {}
var radio_lines_cache := {}
var contract_names := {}
var sound_cache := {}
var player_profile_cache := {}


func open(directory: String, content_id: String, language: String = "gb") -> bool:
	root = directory
	id = content_id
	language_code = language
	error = ""
	mesh_cache.clear()
	texture_cache.clear()
	material_cache.clear()
	lighting_profile.clear()
	model_materials.clear()
	radio_atlases.clear()
	radio_lines_cache.clear()
	contract_names.clear()
	sound_cache.clear()
	player_profile_cache.clear()
	strings = reader.language(read(language + ".lang"))
	if strings.is_empty():
		error = reader.error
		return false
	ships = reader.table(read("data/txt/ships.txt"), 12)
	items = reader.table(read("data/txt/items.txt"), 11)
	stations = reader.table(read("data/txt/stations.txt"), 9)
	systems = reader.table(read("data/txt/systems.txt"), 1)
	quadrants = reader.table(read("data/txt/quadrants.txt"), 1)
	if ships.is_empty() or items.is_empty() or stations.is_empty() or systems.is_empty():
		error = "Required game tables are incomplete."
		return false
	var parser := JSON.new()
	if (
		parser.parse(read("content.json").get_string_from_utf8()) != OK
		or not parser.data is Dictionary
	):
		error = "Imported content definitions are missing or damaged. Import the IPA again."
		return false
	content = parser.data
	if content.get("tables") is Dictionary:
		for key in content.tables:
			if content.tables[key] is Array:
				content.tables[key] = content.tables[key].map(func(value): return int(value))
	return (
		validate_content()
		and load_radio_atlases()
		and valid_materials()
		and load_contract_data()
		and valid_recovery()
		and valid_briefing_ui()
		and valid_title_ui()
		and valid_station_ui()
		and valid_hangar_ui()
		and valid_options_ui()
		and valid_pause_ui()
		and valid_defeat_ui()
		and valid_board_ui()
		and valid_flight_ui()
		and valid_combat_presentation()
		and valid_map_ui()
		and valid_travel()
		and valid_sky()
		and valid_lighting()
		and valid_station_models()
		and valid_ship_exhaust()
		and valid_briefing_scene()
		and valid_survival()
		and valid_player_armament()
		and valid_projectile_trails()
		and valid_menu_traffic()
		and valid_lens_flare()
		and valid_player_hit()
		and valid_actor_destruction()
		and valid_fighter_steering()
		and valid_fighter_evasion()
		and valid_fighter_motion()
		and valid_npc_exhaust()
		and preload("res://src/simulation/fighter_targeting.gd").valid_data(
			content.get("fighter_targeting")
		)
		and preload("res://src/simulation/fighter_impact.gd").valid_parameters(
			content.get("fighter_impact"), self
		)
	)


func available_languages() -> Array[String]:
	var result: Array[String] = []
	for filename in DirAccess.get_files_at(root):
		if filename.ends_with(".lang"):
			result.append(filename.trim_suffix(".lang"))
	result.sort()
	return result


static func language_name(code: String) -> String:
	return {"gb": "English", "de": "Deutsch", "es": "Español",
		"fr": "Français", "it": "Italiano"}.get(code, code.to_upper())


func set_language(code: String) -> bool:
	if not available_languages().has(code):
		error = "This language is not included in the imported game."
		return false
	var localized := reader.language(read(code + ".lang"))
	if localized.size() != strings.size():
		error = "The selected language data is incomplete. Import the IPA again."
		return false
	strings = localized
	language_code = code
	radio_lines_cache.clear()
	error = ""
	return true


func valid_menu_traffic() -> bool:
	if not preload("res://src/presentation/menu_traffic.gd").valid_data(
		content.get("menu_traffic"), content.tables.actor_meshes.size()
	):
		error = "Invalid imported menu scenery declarations. Import the IPA again."
		return false
	if not content.projectile_trails.styles.has(str(int(content.menu_traffic.local_trail.style))):
		error = "Unsupported imported menu ship trail style. Import the IPA again."
		return false
	return true


func valid_fighter_steering() -> bool:
	if not preload("res://src/simulation/encounters.gd").valid_steering(
		content.get("fighter_steering"), content.tables.actor_meshes.size(), content.chapters.size()
	):
		error = "Invalid imported fighter steering. Import the IPA again."
		return false
	return true


func valid_fighter_evasion() -> bool:
	if not preload("res://src/simulation/fighter_evasion.gd").valid_data(
		content.get("fighter_evasion")
	):
		error = "Invalid imported fighter maneuvers. Import the IPA again."
		return false
	return true


func load_contract_data() -> bool:
	if not Contracts.valid_rules(
		content.get("contracts"), strings.size(), content.radio_ui.portraits.size()
	):
		error = "Invalid imported contract rules. Import the IPA again."
		return false
	var rules: Dictionary = content.contracts
	if not ContractEncounters.valid_parameters(rules.get("hunt"), self):
		error = "Invalid imported freelance encounter parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_transport_parameters(rules.get("transport"), self):
		error = "Invalid imported transport encounter parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_battle_parameters(rules.get("battles"), self):
		error = "Invalid imported combat contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_capture_parameters(rules.get("capture"), self):
		error = "Invalid imported capture contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_intercept_parameters(rules.get("intercept"), self):
		error = "Invalid imported interception contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_escort_parameters(rules.get("escort"), self):
		error = "Invalid imported escort contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_asteroid_parameters(rules.get("asteroids"), self):
		error = "Invalid imported asteroid contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_minefield_parameters(rules.get("minefield"), self):
		error = "Invalid imported minefield contract parameters. Import the IPA again."
		return false
	if not ContractEncounters.valid_clearance_parameters(rules.get("clearance"), self):
		error = "Invalid imported clearance contract parameters. Import the IPA again."
		return false
	# JSON numbers arrive as floats. Godot array membership is type-sensitive;
	# normalize declared integer arrays before name or portrait selection.
	for key in [
		"offer_count",
		"tier_range",
		"rate_range",
		"quadrant_difficulty",
		"minimum_rewards",
		"maximum_rewards",
		"male_portraits",
		"female_portraits"
	]:
		rules[key] = rules[key].map(func(value): return int(value))
	rules.clients.random_gender_races = rules.clients.random_gender_races.map(
		func(value): return int(value)
	)
	for choices in rules.clients.professions:
		for race in choices.size():
			choices[race] = choices[race].map(func(value): return int(value))
	if rules.quadrant_difficulty.size() != content.tables.quadrant_difficulty.size():
		error = "Contract region tables disagree with the galaxy."
		return false
	for race in int(rules.client_race_count):
		for gender in ["male", "female"]:
			if gender == "female" and not rules.clients.random_gender_races.has(race):
				continue
			var path: String = rules.clients.name_files[race][gender]
			if contract_names.has(path):
				continue
			var names := reader.name_list(read(path))
			if names.is_empty():
				error = path + ": " + reader.error
				contract_names.clear()
				return false
			contract_names[path] = names
	return true


func validate_content() -> bool:
	if not preload("res://src/presentation/flight_effects.gd").valid(content.get("flight_effects"), content.get("materials", {}), content.get("projectile_trails", {}).get("styles", {})):
		error = "Invalid imported flight effects. Import the IPA again."
		return false
	if not content.get("sound_bank", {}).has(str(int(content.flight_effects.boost_sound))):
		error = "Missing imported boost sound. Import the IPA again."
		return false
	if not content.get("sound_bank", {}).has(str(int(content.flight_effects.outro.music))):
		error = "Missing imported mission completion music. Import the IPA again."
		return false
	if not preload("res://src/simulation/mines.gd").valid_parameters(
		content.get("mine_behavior"),
		content.get("resources", {}),
		content.get("tables", {}).get("actor_hull", []).size()
	):
		error = "Invalid imported mine behavior. Import the IPA again."
		return false
	if not preload("res://src/presentation/mine_visual.gd").valid_audio(
		content.mine_behavior, content.get("sound_bank")
	):
		error = "Invalid imported mine sounds. Import the IPA again."
		return false
	if not preload("res://src/simulation/flight_motion.gd").valid_parameters(
		content.get("player_motion")
	):
		error = "Invalid imported player movement. Import the IPA again."
		return false
	for ship in ships:
		var raw_type: String = str(ship[int(content.player_motion.steering.ship_type_column)])
		var kind := int(raw_type)
		if not raw_type.is_valid_int() or kind < 0 or kind >= content.player_motion.steering.agilities.size():
			error = "Unsupported player ship agility type. Import the IPA again."
			return false

	if (
		content.get("schema") != 1
		or not content.has_all(
			[
				"chapters",
				"tables",
				"resources",
				"initial",
				"opening",
				"localization",
				"economy",
				"missions"
			]
		)
	):
		error = "Unsupported imported content schema."
		return false
	if (
		not content_integer(content.initial.get("level"))
		or content.initial.level <= 0
		or not content_integer(content.initial.get("worth"))
		or content.initial.worth < 0
		or not content_number(content.initial.get("rank_growth"))
		or content.initial.rank_growth <= 1
	):
		error = "Invalid imported pilot progression parameters."
		return false
	var tables: Dictionary = content.tables
	if (
		not tables.get("actor_collision") is Array
		or tables.actor_collision.size() != tables.actor_hull.size()
		or tables.actor_collision.any(func(radius): return radius <= 0 or radius > 10000000)
	):
		error = "Invalid imported collision data. Import the IPA again."
		return false
	if (
		tables.quadrant_difficulty.is_empty()
		or stations.size() % systems.size() != 0
		or systems.size() % tables.quadrant_difficulty.size() != 0
	):
		error = "Unsupported galaxy table dimensions."
		return false
	if tables.buyable_ships.size() != ships.size():
		error = "Ship catalogue and model associations disagree."
		return false
	if not content_integer(content.get("campaign_quadrant")):
		error = "Missing imported campaign destination addressing."
		return false
	for chapter in content.chapters.size():
		if chapter_destination(chapter) < 0:
			error = "Invalid imported campaign destination."
			return false
	if not valid_missions():
		error = "Invalid imported mission or radio definition. Import the IPA again."
		return false
	var required_actors: Array = tables.buyable_ships.duplicate()
	for mission in content.missions:
		for group in mission.groups:
			if group.get("render_mesh", true):
				required_actors.append(group.actor)
	for actor in required_actors:
		if (
			actor < 0
			or actor >= tables.actor_meshes.size()
			or not content.resources.has(str(int(tables.actor_meshes[int(actor)])))
		):
			error = "Unresolved ship model association."
			return false
		var path: String = content.resources[str(int(tables.actor_meshes[int(actor)]))].path
		if not FileAccess.file_exists(root.path_join(path)):
			error = "Missing required actor model."
			return false
	for resource in content.resources.values():
		var path: String = resource.path
		if not path.begins_with("data/meshes/") or path.contains(".."):
			error = "Invalid registered model path."
			return false
	for pair in [["ships", ships], ["items", items]]:
		var binding: Dictionary = content.localization[pair[0]]
		for index in pair[1].size():
			if (
				int(pair[1][index][0]) != index
				or binding.base + index * binding.stride < 0
				or binding.base + index * binding.stride >= strings.size()
			):
				error = "Unresolved catalogue localization reference."
				return false
	for chapter in content.chapters:
		for item_id in chapter.stock:
			if item_id < 0 or item_id >= items.size():
				error = "Invalid campaign shop reference."
				return false
		for text_id in chapter.dialogue:
			if text_id < 0 or text_id >= strings.size():
				error = "Invalid campaign dialogue reference."
				return false
		if chapter.reward < 0:
			error = "Invalid campaign reward."
			return false
	if (
		content.initial.ship_index < 0
		or content.initial.ship_index >= ships.size()
		or content.initial.weapon_index < 0
		or content.initial.weapon_index >= items.size()
		or content.initial.station_index < 0
		or content.initial.station_index >= stations.size()
	):
		error = "Invalid initial pilot catalogue reference."
		return false
	if int(items[int(content.initial.weapon_index)][1]) >= SHIELD_CATEGORY:
		error = "The initial weapon has an unsupported equipment category."
		return false
	for item_id in tables.buyable_equipment:
		if item_id < 0 or item_id >= items.size() or int(items[item_id][1]) >= CARGO_CATEGORY:
			error = "Invalid shop catalogue reference."
			return false
	for row in items:
		if (
			int(row[1]) < 0
			or int(row[1]) > CARGO_CATEGORY
			or int(row[3]) < 0
			or int(row[5]) < 0
			or int(row[6]) < int(row[5])
		):
			error = "Invalid equipment definition."
			return false
	for row in ships:
		if int(row[4]) <= 0 or int(row[5]) < 0 or int(row[6]) < 0:
			error = "Invalid ship definition."
			return false
	for row in stations:
		if (
			int(row[5]) < 0
			or int(row[5]) > int(content.economy.cargo_technology_max)
			or int(row[8]) not in [0, 1]
		):
			error = "Unsupported station services or technology level."
			return false
	return true


func equipment(index: int) -> Dictionary:
	var row: Array = items[index]
	return {
		"id": index,
		"category": int(row[1]),
		"quadrant": int(row[2]),
		"occurrence": int(row[3]),
		"technology": int(row[4]),
		"min_price": int(row[5]),
		"max_price": int(row[6]),
		"value": int(row[7]),
		"interval_ms": int(row[8]),
		"effect_parameters": row.slice(9)
	}


func ship_definition(index: int) -> Dictionary:
	var row: Array = ships[index]
	return {
		"id": index,
		"actor": int(content.tables.buyable_ships[index]),
		"quadrant": int(row[2]),
		"occurrence": int(row[3]),
		"hull": int(row[4]),
		"capacity": int(row[5]),
		"price": int(row[6]),
		"mounts": row.slice(7)
	}


func station_definition(index: int) -> Dictionary:
	var row: Array = stations[index]
	var quadrants: int = content.tables.quadrant_difficulty.size()
	var per_system: int = stations.size() / systems.size()
	var per_quadrant: int = stations.size() / quadrants
	return {
		"id": index,
		"name": str(row[0]),
		"planet": int(row[1]) == 1,
		"image": int(row[2]),
		"population": int(row[3]),
		"race": int(row[4]),
		"technology": int(row[5]),
		"position": Vector2(int(row[6]), int(row[7])),
		"shop": int(row[8]) == 1,
		"quadrant": index / per_quadrant,
		"system": index / per_system,
		"orbit": index % per_system
	}


func actor_model(actor: int) -> String:
	var resource_id := str(int(content.tables.actor_meshes[actor]))
	return str(content.resources[resource_id].path).get_file().trim_suffix(".aem")


func ship_model(index: int) -> String:
	return actor_model(int(content.tables.buyable_ships[index]))


func valid_missions() -> bool:
	if (
		not content.missions is Array
		or content.missions.is_empty()
		or content.missions.size() > content.chapters.size()
	):
		return false
	for mission in content.missions:
		if not valid_mission(mission):
			return false
	return true


func valid_mission(mission: Variant) -> bool:
	if (
		not mission is Dictionary
		or not mission.has_all(["route", "groups", "deadline_ms", "success", "radio"])
	):
		return false
	if (
		not mission.route is Array
		or not mission.groups is Array
		or not mission.radio is Array
		or not mission.success is Dictionary
	):
		return false
	if (
		not content_integer(mission.deadline_ms)
		or mission.deadline_ms < 0
		or mission.deadline_ms > 86400000
		or not valid_objective(mission.success, mission)
	):
		return false
	if mission.has("ending"):
		var ending: Variant = mission.ending
		if (
			not ending is Dictionary
			or not content_integer(ending.get("chapter"))
			or ending.chapter != content.chapters.size() - 1
			or not content_integer(ending.get("text"))
			or ending.text < 0
			or ending.text >= strings.size()
		):
			return false
	if mission.has("failure") and not valid_objective(mission.failure, mission):
		return false
	if (
		mission.has("failure_text")
		and (
			not content_integer(mission.failure_text)
			or mission.failure_text < 0
			or mission.failure_text >= strings.size()
		)
	):
		return false
	if (
		mission.has("failure_prefix")
		and (
			not mission.get("failure_prefix") is String
			or mission.failure_prefix.is_empty()
			or mission.failure_prefix.length() > 255
		)
	):
		return false
	if mission.has("reward_rule"):
		var rule: Variant = mission.reward_rule
		if (
			not rule is Dictionary
			or rule.get("kind") != "surviving_allies"
			or not content_integer(rule.get("offset"))
			or rule.offset > 0
			or rule.offset < -128
		):
			return false
	if not mission.get("scenery", []) is Array:
		return false
	for field in mission.get("scenery", []):
		if not valid_field(field, mission.route.size()):
			return false
	if (
		mission.has("payout_kind")
		and (
			mission.payout_kind != "finished_asteroids"
			or mission.success.kind != "time_survived"
			or mission.get("scenery", []).size() != 1
			or not mission.scenery[0].has("destruction")
		)
	):
		return false
	if mission.has("fog") and not valid_fog(mission.fog, mission.route.size()):
		return false
	for coordinate in mission.route:
		if not valid_point(coordinate):
			return false
	var projectile_pools := {}
	for group in mission.groups:
		if (
			not group is Dictionary
			or not group.has_all(["actor", "count", "center", "scatter", "after_route"])
		):
			return false
		if (
			not content_integer(group.actor)
			or group.actor < 0
			or group.actor >= content.tables.actor_hull.size()
			or not content_integer(group.count)
			or group.count <= 0
			or group.count > 128
		):
			return false
		if (
			not valid_point(group.center)
			or not group.after_route is bool
			or not group.scatter is Array
			or group.scatter.size() not in [0, 3]
		):
			return false
		for axis in group.scatter:
			if (
				not axis is Array
				or axis.size() != 2
				or not content_integer(axis[0])
				or not content_integer(axis[1])
				or axis[0] > axis[1]
				or absf(axis[0]) > 1e8
				or absf(axis[1]) > 1e8
			):
				return false
		if (
			group.has("scatter_divisor")
			and (
				not content_integer(group.scatter_divisor)
				or group.scatter_divisor < 1
				or group.scatter_divisor > 1000000
				or group.scatter.size() != 3
			)
		):
			return false
		if (
			(
				group.get("behavior", "stationary")
				not in ["stationary", "interceptor", "escort", "wingmate", "transit", "turret"]
			)
			or (
				group.get("placement", "formation")
				not in ["formation", "waypoints", "points", "player_offset"]
			)
			or group.get("team", "enemy") not in ["enemy", "ally"]
			or not group.get("sleeping", false) is bool
			or not group.get("combat_active", true) is bool
		):
			return false
		if group.get("placement", "formation") == "formation" and group.scatter.is_empty() and group.count > 1:
			return false
		if group.get("placement") == "waypoints" and group.count != mission.route.size():
			return false
		if group.get("placement") == "points":
			if (
				not group.get("positions") is Array
				or group.positions.size() != group.count
				or not group.positions.all(func(position): return valid_point(position))
			):
				return false
		if (
			group.has("initial_hp")
			and (
				not content_integer(group.initial_hp)
				or group.initial_hp <= 0
				or group.initial_hp > 10000000
			)
		):
			return false
		if (
			not group.get("render_mesh", true) is bool
			or (not group.get("render_mesh", true) and group.get("behavior") != "turret")
		):
			return false
		if not group.get("source_scale", false) is bool:
			return false
		if group.has("collision"):
			if (
				not group.collision is Dictionary
				or not valid_point(group.collision.get("offset"))
				or not valid_point(group.collision.get("size"))
				or not group.collision.size.all(func(axis): return axis > 0)
			):
				return false
		if group.get("sleeping", false) and group.get("behavior") == "stationary":
			if (
				not content_number(group.get("wake_half_width"))
				or group.wake_half_width <= 0
				or group.wake_half_width > 1000000
			):
				return false
		if group.has("collisions"):
			if (
				not group.collisions is Array
				or group.collisions.is_empty()
				or group.collisions.size() > 32
			):
				return false
			for box in group.collisions:
				if (
					not box is Dictionary
					or not valid_point(box.get("offset"))
					or not valid_point(box.get("size"))
					or not box.size.all(func(axis): return axis > 0)
				):
					return false
		if group.get("behavior") == "transit":
			if (
				not Combat.valid_vector(group.get("velocity"))
				or not group.velocity.all(func(axis): return absf(axis) <= 1000000)
				or group.get("sleeping", false)
			):
				return false
		if group.get("behavior") == "turret":
			if (
				not valid_point(group.get("facing"))
				or (Vector3(group.facing[0], group.facing[1], group.facing[2]).length_squared() < 1)
				or not group.get("tracking") is Dictionary
			):
				return false
			for key in ["wake_half_width", "range_half_width", "aim_sine", "turn_rate"]:
				if (
					not content_number(group.tracking.get(key))
					or group.tracking[key] <= 0
					or group.tracking[key] > 1000000
				):
					return false
			if group.tracking.aim_sine >= 1:
				return false
		if group.has("hull_rule"):
			var rule: Variant = group.hull_rule
			if (
				not rule is Dictionary
				or not content_integer(rule.get("chapter"))
				or rule.chapter < 0
				or rule.chapter >= content.chapters.size()
				or not content_integer(rule.get("rank_scale"))
				or rule.rank_scale < 0
				or not content_number(rule.get("factor"))
				or rule.factor <= 0
			):
				return false
			if (
				not content_integer(rule.get("post_offset", 0))
				or absf(float(rule.get("post_offset", 0))) > 10000000
				or not content_number(rule.get("post_factor", 1))
				or rule.get("post_factor", 1) <= 0
				or rule.get("post_factor", 1) > 1000000
				or group_hull(group) <= 0
				or group_hull(group) > 10000000
			):
				return false
		if group.get("behavior") == "wingmate":
			if (
				group.get("team") != "ally"
				or (
					group.get("placement", "formation")
					not in ["player_offset", "points", "formation"]
				)
				or group.get("sleeping", false)
			):
				return false
		if group.get("behavior") == "escort":
			if (
				group.get("team") != "ally"
				or group.get("placement") not in ["player_offset", "points"]
				or not group.get("route") is Array
				or group.route.is_empty()
				or not group.route.all(func(position): return valid_point(position))
				or not group.get("motion") is Dictionary
			):
				return false
			for key in ["speed", "turn_response"]:
				if (
					not content_number(group.motion.get(key))
					or group.motion[key] <= 0
					or group.motion[key] > 1000000
				):
					return false
		if (
			group.has("hull")
			and (not content_integer(group.hull) or group.hull <= 0 or group.hull > 10000000)
		):
			return false
		if group.get("behavior") in ["interceptor", "escort", "wingmate"]:
			if not group.get("motion") is Dictionary:
				return false
			for key in [
				"speed",
				"turn_response",
				"wake_half_width",
				"aim_sine",
				"fire_half_width",
				"avoid_distance"
			]:
				var value: Variant = group.motion.get(key)
				if not content_number(value) or value <= 0 or value > 1000000:
					return false
			if group.motion.aim_sine > 1:
				return false
		if not group.get("unarmed", false) is bool:
			return false
		if (
			group.get("unarmed", false)
			and (group.get("behavior") != "interceptor" or group.has("weapon"))
		):
			return false
		if (
			group.get("behavior") in ["interceptor", "escort", "wingmate", "turret"]
			and not group.get("unarmed", false)
		):
			if not group.get("weapon") is Dictionary:
				return false
			if not group.weapon.get("damage_rule") is Dictionary:
				return false
			if (
				group.weapon.has("guidance")
				and not Combat.Guidance.valid_parameters(group.weapon.guidance)
			):
				return false
			if group.weapon.has("rocket_impact") and not group.weapon.rocket_impact is bool:
				return false
			if group.weapon.has("projectile_overlay") and not group.weapon.has("projectile_model"):
				return false
			for field in ["projectile_model", "projectile_overlay"]:
				if not group.weapon.has(field):
					continue
				if not content_integer(group.weapon[field]):
					return false
				var resource: Variant = content.resources.get(str(int(group.weapon[field])))
				if not resource is Dictionary or not resource.get("path", "").ends_with(".aem"):
					return false
				if not FileAccess.file_exists(root.path_join(resource.path)):
					return false
			if (
				group.weapon.has("pool_capacity")
				and (
					not content_integer(group.weapon.pool_capacity)
					or group.weapon.pool_capacity <= 0
					or group.weapon.pool_capacity > 4096
				)
			):
				return false
			if (
				group.weapon.has("pool_id")
				and (
					not content_integer(group.weapon.pool_id)
					or group.weapon.pool_id <= 0
					or group.weapon.pool_id > 4096
					or not group.weapon.has("pool_capacity")
				)
			):
				return false
			if group.weapon.has("pool_id"):
				var pool := int(group.weapon.pool_id)
				if (
					projectile_pools.has(pool)
					and projectile_pools[pool] != group.weapon.pool_capacity
				):
					return false
				projectile_pools[pool] = group.weapon.pool_capacity
			var rule: Dictionary = group.weapon.damage_rule
			for key in ["base", "minimum", "level_divisor"]:
				if (
					not content_integer(rule.get(key))
					or rule[key] < (1 if key == "level_divisor" else 0)
				):
					return false
			if (
				not rule.get("ranked", true) is bool
				or not content_number(rule.get("factor"))
				or rule.factor <= 0
			):
				return false
			for key in ["damage", "interval", "lifetime", "speed"]:
				var value: Variant = group.weapon.get(key)
				if not content_number(value) or value <= 0 or value > 1000000:
					return false
	if mission.has("enemy_goal"):
		var enemies := 0
		for group in mission.groups:
			if group.get("team", "enemy") == "enemy":
				enemies += int(group.count)
		if (
			not content_integer(mission.enemy_goal)
			or mission.enemy_goal < 1
			or mission.enemy_goal > enemies
		):
			return false
	if not Sequence.valid_definition(mission):
		return false
	if not valid_radio(mission):
		return false

	return true


func valid_radio(mission: Dictionary) -> bool:
	for cue in mission.radio:
		if not cue is Dictionary or not cue.has_all(["text", "speaker", "condition", "value"]):
			return false
		if (
			not content_integer(cue.text)
			or cue.text < 0
			or cue.text >= strings.size()
			or not content_integer(cue.speaker)
			or cue.speaker < 0
			or not content_integer(cue.value)
			or cue.value < 0
		):
			return false
		if (
			cue.condition
			not in [
				"waypoint_passed",
				"enemies_destroyed",
				"elapsed",
				"message_shown",
				"mission_won",
				"enemy_range_active",
				"enemy_range_casualty",
				"ally_range_casualty",
				"enemy_range_destroyed",
				"ally_range_active",
				"enemy_active_after_message",
				"enemy_range_damaged",
				"enemies_active"
			]
		):
			return false
		if cue.condition == "message_shown" and cue.value >= mission.radio.size():
			return false
		if cue.condition == "waypoint_passed" and cue.value >= mission.route.size():
			return false
		if (
			cue.condition
			in [
				"enemy_range_active",
				"enemy_range_casualty",
				"enemy_range_damaged",
				"enemy_range_destroyed",
				"ally_range_active",
				"ally_range_casualty"
			]
		):
			var actor_count := 0
			for group in mission.groups:
				if (
					(group.get("team", "enemy") == "ally")
					== str(cue.condition).begins_with("ally_")
				):
					actor_count += int(group.count)
			if (
				not content_integer(cue.get("count"))
				or cue.count <= 0
				or cue.value + cue.count > actor_count
			):
				return false
		if cue.condition == "enemy_active_after_message":
			var enemies := 0
			for group in mission.groups:
				if group.get("team", "enemy") == "enemy":
					enemies += int(group.count)
			if (
				cue.value >= enemies
				or not content_integer(cue.get("message"))
				or cue.message < 0
				or cue.message >= mission.radio.size()
			):
				return false
		if cue.condition == "enemy_range_damaged":
			if not content_number(cue.get("fraction")) or cue.fraction <= 0 or cue.fraction >= 1:
				return false
			var index := 0
			for group in mission.groups:
				if group.get("team", "enemy") != "enemy":
					continue
				if (
					index < cue.value + cue.count
					and index + group.count > cue.value
					and not group.has("hull")
				):
					return false
				index += int(group.count)
	return true


func valid_field(field: Variant, route_length: int) -> bool:
	if not field is Dictionary or field.get("kind") != "asteroid_field":
		return false
	for key in ["variant", "count", "width", "model", "hits", "contact_damage"]:
		if not content_integer(field.get(key)) or field[key] < 0:
			return false
	if (
		(
			not field.has("center")
			and (
				not content_integer(field.get("waypoint"))
				or field.waypoint < 0
				or field.waypoint >= route_length
			)
		)
		or (field.has("center") and (field.has("waypoint") or not valid_point(field.center)))
		or field.count < 1
		or field.count > 10000
		or field.width < 1
		or field.width > 10000000
		or field.hits < 1
		or not content.resources.has(str(int(field.model)))
	):
		return false
	var resource: Dictionary = content.resources[str(int(field.model))]
	if (
		not str(resource.path).ends_with(".aem")
		or not FileAccess.file_exists(root.path_join(resource.path))
	):
		return false
	for key in ["scale_min", "scale_max", "radius", "contact_interval"]:
		if not content_number(field.get(key)) or field[key] <= 0 or field[key] > 1000000:
			return false
	return (
		field.scale_min <= field.scale_max
		and (
			not field.has("destruction")
			or (
				Scenery.valid_destruction(field.destruction, content.resources)
				and preload("res://src/presentation/asteroid_visual.gd").valid_audio(
					field.destruction, content.get("sound_bank")
				)
			)
		)
	)


func valid_objective(value: Variant, mission: Dictionary, depth: int = 0) -> bool:
	if depth > 8 or not value is Dictionary:
		return false
	match value.get("kind"):
		"message_shown":
			return (
				content_integer(value.get("message"))
				and value.message >= 0
				and value.message < mission.radio.size()
			)
		"enemy_prefix_destroyed":
			var enemies := 0
			for group in mission.groups:
				if (
					group is Dictionary
					and group.get("team", "enemy") == "enemy"
					and content_integer(group.get("count"))
				):
					enemies += int(group.count)
			return (
				content_integer(value.get("count")) and value.count > 0 and value.count <= enemies
			)
		"enemies_destroyed":
			return true
		"route_finished":
			return not mission.route.is_empty()
		"time_survived":
			return (
				content_integer(value.get("duration_ms"))
				and value.duration_ms > 0
				and value.duration_ms <= 86400000
			)
		"allies_destroyed":
			return mission.groups.any(
				func(group): return group is Dictionary and group.get("team") == "ally"
			)
		"all":
			return (
				value.get("conditions") is Array
				and not value.conditions.is_empty()
				and value.conditions.size() <= 32
				and value.conditions.all(
					func(condition): return valid_objective(condition, mission, depth + 1)
				)
			)
		"ally_destroyed", "enemy_destroyed":
			var count := 0
			for group in mission.groups:
				if (
					group is Dictionary
					and (group.get("team", "enemy") == "enemy") == (value.kind == "enemy_destroyed")
					and content_integer(group.get("count"))
				):
					count += int(group.count)
			return content_integer(value.get("index")) and value.index >= 0 and value.index < count
	return false


func content_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value)


func valid_point(value: Variant) -> bool:
	return (
		value is Array
		and value.size() == 3
		and value.all(func(axis): return content_integer(axis) and absf(axis) <= 1e8)
	)


func mission_definition(chapter: int) -> Dictionary:
	return content.missions[chapter] if chapter >= 0 and chapter < content.missions.size() else {}


func mission_playable(chapter: int) -> bool:
	var definition := mission_definition(chapter)
	if definition.is_empty():
		return false
	# Importing a declaration does not make its encounter mechanics playable.
	# Keep the campaign gated until the native implementation supports every role.
	for group in definition.groups:
		if (
			group.get("behavior", "stationary")
			not in ["stationary", "interceptor", "escort", "wingmate", "transit", "turret"]
		):
			return false
		if (
			group.get("sleeping", false)
			and group.get("behavior") not in ["interceptor", "stationary", "turret", "escort"]
		):
			return false
	return true


func chapter_destination(chapter: int) -> int:
	if chapter < 0 or chapter >= content.chapters.size():
		return -1
	var pair: Variant = content.chapters[chapter].get("destination")
	var quadrant := int(content.get("campaign_quadrant", -1))
	var quadrants: int = content.tables.quadrant_difficulty.size()
	var per_system: int = stations.size() / systems.size()
	var per_quadrant: int = systems.size() / quadrants
	if (
		not pair is Array
		or pair.size() != 2
		or not pair.all(func(index): return content_integer(index))
	):
		return -1
	if (
		quadrant < 0
		or quadrant >= quadrants
		or pair[0] < 0
		or pair[0] >= per_quadrant
		or pair[1] < 0
		or pair[1] >= per_system
	):
		return -1
	return (quadrant * per_quadrant + int(pair[0])) * per_system + int(pair[1])


func playable_chapter_count() -> int:
	for chapter in content.missions.size():
		if not mission_playable(chapter):
			return chapter
	return content.missions.size()


func group_hull(group: Dictionary, rank: int = -1) -> float:
	if group.has("hull"):
		return float(group.hull)
	var base := float(content.tables.actor_hull[int(group.actor)])
	if group.has("hull_rule"):
		var rule: Dictionary = group.hull_rule
		var scaled := int(
			(
				(
					base
					+ (
						(rank if rank >= 0 else campaign_level(int(rule.chapter)))
						* int(rule.rank_scale)
					)
				)
				* float(rule.factor)
			)
		)
		return float(
			int((scaled + float(rule.get("post_offset", 0))) * float(rule.get("post_factor", 1)))
		)
	return base


func group_initial_hull(group: Dictionary, rank: int = -1) -> float:
	return float(group.get("initial_hp", group_hull(group, rank)))


func weapon_ballistics(id: int) -> Dictionary:
	if id < 0 or id >= items.size() or int(items[id][1]) >= SHIELD_CATEGORY:
		return {}
	var item: Array = items[id]
	if float(item[7]) <= 0 or float(item[8]) <= 0 or float(item[9]) <= 0 or float(item[10]) <= 0:
		return {}
	# Value1 damage, Value2 reload ms, Value3 lifetime ms, Value4 source units/ms.
	# The same spatial conversion is used for imported mission geometry.
	return {
		"damage": float(item[7]),
		"interval": float(item[8]) / 1000.0,
		"lifetime": float(item[9]) / 1000.0,
		"speed": float(item[10]) * 20.0
	}


func actor_radius(actor: int) -> float:
	return float(content.tables.actor_collision[actor]) * .02


func mission_route(chapter: int) -> Array[Vector3]:
	var route: Array[Vector3] = []
	for coordinate in mission_definition(chapter).get("route", []):
		route.append(Vector3(coordinate[0], coordinate[1], -coordinate[2]) * .02)
	return route


func opening_route() -> Array[Vector3]:
	var route: Array[Vector3] = []
	for point in content.opening.route:
		route.append(Vector3(point[0], point[1], -point[2]) * .02)
	return route


func briefing(chapter: int) -> String:
	var lines := PackedStringArray()
	for text_id in content.chapters[chapter].dialogue:
		lines.append(text(int(text_id)))
	return "\n\n".join(lines)


func read(relative: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(root.path_join(relative))


func text(index: int, fallback: String = "") -> String:
	return strings[index] if index >= 0 and index < strings.size() else fallback


func station_name(index: int) -> String:
	return str(stations[clampi(index, 0, stations.size() - 1)][0])


func ship_name(index: int) -> String:
	var binding: Dictionary = content.localization.ships
	return text(int(binding.base + index * binding.stride))


func item_name(index: int) -> String:
	var binding: Dictionary = content.localization.items
	return text(int(binding.base + index * binding.stride))


func texture(name: String = "main_texture") -> Texture2D:
	if texture_cache.has(name):
		return texture_cache[name]
	var file := "data/textures/" + name + ".aei"
	if not FileAccess.file_exists(root.path_join(file)):
		return null
	var result := reader.aei(read(file))
	if result.is_empty():
		error = reader.error
		return null
	var img: Image = result.image
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	texture_cache[name] = tex
	return tex


func valid_materials() -> bool:
	error = "Invalid imported mesh materials. Import the IPA again."
	var definitions: Variant = content.get("materials")
	if not definitions is Dictionary or definitions.is_empty() or definitions.size() > 256:
		return false
	for key in definitions:
		var data: Variant = definitions[key]
		if (
			not data is Dictionary
			or not content_integer(data.get("texture"))
			or not content_integer(data.get("order"))
			or data.order < 0
			or data.order > 127
			or not data.get("lit") is bool
			or data.get("blend") not in ["opaque", "mix", "add"]
			or data.get("cull") not in ["back", "disabled"]
			or not content.radio_ui.textures.has(str(int(data.texture)))
		):
			return false
		if data.lit and data.blend != "opaque":
			return false
	var associations := {}
	for mesh in content.resources.values():
		if (
			not mesh is Dictionary
			or not content_integer(mesh.get("material_id"))
			or not definitions.has(str(int(mesh.material_id)))
		):
			return false
		var name: String = mesh.path.get_file().get_basename()
		if associations.has(name):
			return false
		associations[name] = int(mesh.material_id)
	model_materials = associations
	error = ""
	return true


func valid_briefing_scene() -> bool:
	if not preload("res://src/presentation/opening_choreography.gd").valid_data(content.get("briefing_scene",{}).get("opening")):
		error = "Opening cinematic declarations are missing or invalid. Import the IPA again."
		return false
	error = "Invalid imported briefing scene. Import the IPA again."
	var data: Variant = content.get("briefing_scene")
	if data.opening.actor >= content.tables.actor_meshes.size(): return false
	if (
		not data is Dictionary
		or not data.get("chapters") is Array
		or data.chapters.size() != content.chapters.size()
	):
		return false
	for field in [
		"fov_units", "near", "far", "station_z", "special_type", "special_z", "location_default"
	]:
		if not content_integer(data.get(field)):
			return false
	if (
		data.fov_units <= 0
		or data.fov_units >= 32768
		or data.near <= 0
		or data.far <= data.near
		or not Combat.valid_vector(data.get("camera_position", []))
	):
		return false
	if (
		not content.station_models.types.has(str(int(data.location_default)))
		or not content.station_models.types.has(str(int(data.special_type)))
		or not data.get("location_races") is Array
	):
		return false
	var races := {}
	for rule in data.location_races:
		if not rule is Dictionary or not content_integer(rule.get("race")) or races.has(rule.race):
			return false
		races[rule.race] = true
		for key in ["type", "image_zero_type"]:
			if key == "image_zero_type" and not rule.has(key):
				continue
			if (
				not content_integer(rule.get(key))
				or not content.station_models.types.has(str(int(rule[key])))
			):
				return false
	for chapter in data.chapters:
		if (
			not chapter is Dictionary
			or not content_integer(chapter.get("mode"))
			or chapter.get("kind") not in ["intro", "station"]
		):
			return false
		if (
			chapter.kind == "station"
			and (
				not chapter.get("location_station") is bool
				or not Combat.valid_vector(chapter.get("field_velocity", []))
			)
		):
			return false
	var field: Variant = data.get("field")
	if not field is Dictionary or not Combat.valid_vector(field.get("center", [])):
		return false
	if not preload("res://src/presentation/asteroid_visual.gd").valid_audio(
		field.get("destruction"), content.get("sound_bank")
	):
		return false
	for key in ["count", "width", "model", "rotation_bound"]:
		if not content_integer(field.get(key)) or field[key] <= 0:
			return false
	if (
		field.count > 1024
		or not content.resources.has(str(int(field.model)))
		or field.rotation_bound > 65536
	):
		return false
	if (
		not content_number(field.get("scale_min"))
		or not content_number(field.get("scale_max"))
		or field.scale_min <= 0
		or field.scale_max < field.scale_min
	):
		return false
	error = ""
	return true


func briefing_station_type(chapter: int, station_id: int) -> int:
	var data: Dictionary = content.briefing_scene
	if not data.chapters[chapter].get("location_station", false):
		return int(content.station_models.campaign[chapter].get("type", -1))
	return location_station_type(station_id)


func location_station_type(station_id: int) -> int:
	var data: Dictionary = content.briefing_scene
	var location := station_definition(station_id)
	for rule in data.location_races:
		if rule.race == location.race:
			return int(
				(
					rule.image_zero_type
					if location.image == 0 and rule.has("image_zero_type")
					else rule.type
				)
			)
	return int(data.location_default)


func valid_station_models() -> bool:
	error = "Invalid imported station geometry. Import the IPA again."
	var data: Variant = content.get("station_models")
	if (
		not data is Dictionary
		or not data.get("types") is Dictionary
		or data.types.is_empty()
		or data.types.size() > 64
		or not data.get("campaign") is Array
		or data.campaign.size() != content.chapters.size()
		or not content_integer(data.get("tilt_bound"))
		or data.tilt_bound <= 0
		or data.tilt_bound > 65536
		or not content_integer(data.get("tilt_center"))
		or data.tilt_center < 0
		or data.tilt_center >= data.tilt_bound
		or not content_integer(data.get("turn_ms"))
		or data.turn_ms <= 0
		or data.turn_ms > 1000000
	):
		return false
	for key in data.types:
		if not str(key).is_valid_int() or not data.types[key] is Dictionary:
			return false
		for field in ["body", "lights"]:
			var value: Variant = data.types[key].get(field)
			if not content_integer(value) or not content.resources.has(str(int(value))):
				return false
	for value in data.campaign:
		if not value is Dictionary:
			return false
		if value.is_empty():
			continue
		if not content_integer(value.get("type")) or not data.types.has(str(int(value.type))):
			return false
		if not Combat.valid_vector(value.get("position", [])):
			return false
		if value.has("alternate_position"):
			if (
				not Combat.valid_vector(value.alternate_position)
				or not content_integer(value.get("position_mode"))
			):
				return false
	error = ""
	return true


func station_model(kind: int, tilt_samples: Vector2i = Vector2i.ZERO):
	var node := StationModel.new()
	if not node.configure(self, kind, tilt_samples):
		error = node.error
	return node


func material(identifier: int) -> Material:
	if material_cache.has(identifier):
		return material_cache[identifier]
	var data: Dictionary = content.materials[str(identifier)]
	var path: String = content.radio_ui.textures[str(int(data.texture))]
	var atlas := texture(path.get_file().get_basename())
	var result: Material
	if data.lit:
		var lit := ShaderMaterial.new()
		lit.shader = LIT_SHADER
		if data.cull == "disabled":
			var shader := Shader.new()
			shader.code = LIT_SHADER.code.replace("cull_back", "cull_disabled")
			lit.shader = shader
		lit.set_shader_parameter("atlas", atlas)
		apply_lighting(lit)
		result = lit
	elif data.blend == "add":
		var shader := ADDITIVE_SHADER
		if data.cull == "disabled":
			shader = Shader.new()
			shader.code = ADDITIVE_SHADER.code.replace("cull_back", "cull_disabled")
		var additive := ShaderMaterial.new()
		additive.shader = shader
		additive.set_shader_parameter("atlas", atlas)
		result = additive
	else:
		var surface := StandardMaterial3D.new()
		surface.albedo_texture = atlas
		surface.roughness = 1.0
		surface.metallic_specular = 0.0
		surface.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
		# The supported source profile leaves GL_COLOR_MATERIAL disabled:
		# lit hulls use material lighting; unlit surfaces use their color arrays.
		surface.vertex_color_use_as_albedo = not data.lit
		surface.vertex_color_is_srgb = true
		surface.cull_mode = (
			BaseMaterial3D.CULL_BACK if data.cull == "back" else BaseMaterial3D.CULL_DISABLED
		)
		surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if not data.lit:
			surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if data.blend == "mix":
			surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		result = surface
	result.render_priority = int(data.order)
	material_cache[identifier] = result
	return result


func mesh(name: String) -> ArrayMesh:
	if mesh_cache.has(name):
		return mesh_cache[name]
	var path := "data/meshes/" + name + ".aem"
	if not FileAccess.file_exists(root.path_join(path)):
		error = "Missing model: " + name
		return null
	var result := reader.aem(read(path))
	if result.is_empty():
		error = reader.error
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = result.vertices
	arrays[Mesh.ARRAY_NORMAL] = result.normals
	arrays[Mesh.ARRAY_TEX_UV] = result.uv
	arrays[Mesh.ARRAY_INDEX] = result.indices
	arrays[Mesh.ARRAY_CUSTOM0] = result.lighting_normals
	if not result.colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = result.colors
	var resource := ArrayMesh.new()
	resource.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES,
		arrays,
		[],
		{},
		Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	)
	mesh_cache[name] = resource
	return resource


func model(name: String, desired_size: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if not model_materials.has(name):
		error = "Missing source material for model: " + name
		return node
	node.mesh = mesh(name)
	if node.mesh == null:
		return node
	node.material_override = material(model_materials[name])
	if desired_size > 0:
		var box := node.mesh.get_aabb()
		var factor := desired_size / maxf(box.size.x, maxf(box.size.y, box.size.z))
		node.scale = Vector3.ONE * factor
	return node


func valid_ship_exhaust() -> bool:
	error = "Invalid ship exhaust definitions. Import the IPA again."
	var definitions: Variant = content.get("ship_exhaust")
	if not definitions is Dictionary:
		error = "Missing ship exhaust definitions. Import the IPA again."
		return false
	for key in ["player", "actors"]:
		var actors: Variant = definitions.get(key)
		if not actors is Array or actors.size() != content.tables.actor_meshes.size():
			return false
		for nozzles in actors:
			if not nozzles is Array or nozzles.size() > 16:
				return false
			for nozzle in nozzles:
				if not nozzle is Dictionary or not content_integer(nozzle.get("mesh")):
					return false
				var resource: Variant = content.resources.get(str(int(nozzle.mesh)))
				if (
					not resource is Dictionary
					or not resource.get("path", "").ends_with(".aem")
					or not FileAccess.file_exists(root.path_join(resource.path))
				):
					return false
				for field in ["position", "scale"]:
					if not nozzle.get(field) is Array or nozzle[field].size() != 3:
						return false
					for value in nozzle[field]:
						if (
							not (value is int or value is float)
							or not is_finite(float(value))
							or absf(float(value)) > 100000
						):
							return false
				if nozzle.scale.any(func(value): return value <= 0):
					return false
	error = ""
	return true


func attach_ship_exhaust(hull: MeshInstance3D, actor: int, player: bool = false) -> void:
	# Attach below the hull so any display scaling applies equally to its nozzles.
	var definitions: Array = content.ship_exhaust["player" if player else "actors"]
	if actor < 0 or actor >= definitions.size():
		return
	for nozzle in definitions[actor]:
		var resource: Dictionary = content.resources[str(int(nozzle.mesh))]
		var glow := model(resource.path.get_file().get_basename())
		glow.position = Vector3(nozzle.position[0], nozzle.position[1], -nozzle.position[2]) * .02
		glow.scale = Vector3(nozzle.scale[0], nozzle.scale[1], nozzle.scale[2])
		glow.set_meta("exhaust_scale", glow.scale)
		hull.add_child(glow)


func music(name: String) -> AudioStreamMP3:
	var path := "data/sounds/" + name + ".mp3"
	if not FileAccess.file_exists(root.path_join(path)):
		return null
	var stream := AudioStreamMP3.new()
	stream.data = read(path)
	stream.loop = true
	return stream


func content_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func actor_weapons(chapter: int, rank: int = -1) -> Dictionary:
	return definition_weapons(
		mission_definition(chapter), rank if rank >= 0 else campaign_level(chapter)
	)


func definition_weapons(definition: Dictionary, rank: int) -> Dictionary:
	var result := {}
	var teams := []
	for group in definition.get("groups", []):
		for actor in int(group.count):
			teams.append(group.get("team", "enemy"))
	var index := 0
	for group in definition.get("groups", []):
		for actor in int(group.count):
			if group.has("weapon"):
				var profile: Dictionary = group.weapon.duplicate(true)
				profile.team = group.get("team", "enemy")
				if not profile.has("projectile_model"):
					var pool := int(profile.get("pool_id", -1))
					if profile.team == "ally": pool = 128
					elif int(group.actor) == int(content.npc_projectiles.alien_actor): pool = 144
					elif int(group.actor) == int(content.npc_projectiles.turret_actor): pool = 136
					elif pool < 0: pool = 140
					var model: int = content.npc_projectiles.get(str(pool), -1)
					if model > 0: profile.projectile_model = model
				if profile.has("guidance"):
					profile["guidance_target_ids"] = []
					if profile.team == "enemy":
						profile.guidance_target_ids.append(-1)
					for target in teams.size():
						if teams[target] != profile.team and teams[target] != "neutral":
							profile.guidance_target_ids.append(target)
				var rule: Dictionary = profile.damage_rule
				profile.damage = maxi(
					int(rule.minimum),
					int(
						(
							(
								int(rule.base)
								+ (
									(rank / int(rule.level_divisor))
									if rule.get("ranked", true)
									else 0
								)
							)
							* float(rule.factor)
						)
					)
				)
				result[-1 - index] = profile
			index += 1
	return result


func campaign_level(chapter: int) -> int:
	# Compatibility baseline for old previews and isolated content inspection.
	# Active missions always supply their rank from the Session reward history.
	var level := int(content.initial.level)
	var worth := int(content.initial.worth)
	var previous := worth
	for index in mini(chapter, content.chapters.size()):
		worth += int(content.chapters[index].reward)
		if worth > previous * float(content.initial.rank_growth):
			level += 1
			previous = worth
	return level


func load_radio_atlases() -> bool:
	var ui: Variant = content.get("radio_ui")
	if (
		not ui is Dictionary
		or not ui.has_all(
			[
				"portraits",
				"textures",
				"font",
				"font_spacing",
				"line_ms",
				"lead_ms",
				"text_width",
				"layout",
				"panel"
			]
		)
	):
		error = "Radio presentation data is missing. Import the IPA again."
		return false
	if (
		not ui.portraits is Array
		or ui.portraits.is_empty()
		or ui.portraits.size() > 256
		or not ui.textures is Dictionary
		or not content_integer(ui.font_spacing)
		or abs(ui.font_spacing) > 16
	):
		error = "Invalid radio atlas definitions."
		return false
	for field in ["line_ms", "lead_ms", "text_width"]:
		if not content_integer(ui[field]) or ui[field] <= 0 or ui[field] > 10000:
			error = "Invalid radio layout or timing."
			return false
	for key in ui.textures:
		var path: Variant = ui.textures[key]
		if (
			not path is String
			or not path.begins_with("data/textures/")
			or not path.ends_with(".aei")
			or path.contains("..")
		):
			error = "Invalid UI texture path."
			return false
		var atlas := reader.aei(read(path))
		if atlas.is_empty():
			error = reader.error
			return false
		radio_atlases[key] = atlas
	if not valid_radio_layout():
		return false
	for binding in ui.portraits + [ui.font, ui.panel.corner]:
		if (
			not binding is Dictionary
			or not content_integer(binding.get("texture"))
			or not content_integer(binding.get("region"))
			or binding.region < 0
			or not radio_atlases.has(str(int(binding.texture)))
		):
			error = "Invalid radio image association."
			return false
		var atlas: Dictionary = radio_atlases[str(int(binding.texture))]
		var entries: Array = atlas.glyphs if binding == ui.font else atlas.regions
		if int(binding.region) >= entries.size():
			error = "Radio image or font lies outside its atlas."
			return false
	var glyphs := radio_glyphs()
	if not glyphs.has(32) or not glyphs.has(63):
		error = "Radio font is missing spacing or fallback glyphs."
		return false
	for binding in ui.portraits:
		var region: Rect2i = radio_atlases[str(int(binding.texture))].regions[int(binding.region)]
		var corner: Rect2i = radio_atlases[str(int(ui.panel.corner.texture))].regions[int(
			ui.panel.corner.region
		)]
		if corner.size.y * 2 > region.size.y + ui.layout.height_padding:
			error = "Dialogue corner exceeds the portrait-height panel."
			return false
		if region.size.x <= 0 or region.size.y <= 0 or region.size.x >= ui.text_width:
			error = "Radio portrait leaves no readable text column."
			return false
	for mission in content.missions:
		if mission.has("fog"):
			if (
				not radio_atlases.has(str(int(mission.fog.texture)))
				or fog_texture(mission.fog) == null
			):
				error = "Nebula texture lies outside the supplied atlas."
				return false
		for cue in mission.radio:
			if int(cue.speaker) < 0 or int(cue.speaker) >= ui.portraits.size():
				error = "Radio speaker lies outside the portrait table."
				return false
	return true


func valid_radio_layout() -> bool:
	var ui: Dictionary = content.radio_ui
	var layout: Variant = ui.get("layout")
	var panel: Variant = ui.get("panel")
	if not layout is Dictionary or not panel is Dictionary or not panel.get("corner") is Dictionary:
		error = "Missing supplied dialogue panel artwork or layout. Import the IPA again."
		return false
	for key in ["origin", "portrait", "text"]:
		var point: Variant = layout.get(key)
		if (
			not point is Array
			or point.size() != 2
			or not point.all(func(n): return content_integer(n) and n >= 0 and n < 480)
		):
			error = "Invalid radio panel coordinates."
			return false
	for key in ["width", "height_padding"]:
		if not content_integer(layout.get(key)) or layout[key] <= 0 or layout[key] > 480:
			error = "Invalid radio panel dimensions."
			return false
	if (
		layout.origin[0] + layout.width > 480
		or layout.width < ui.text_width
		or layout.origin[1] >= 320
		or layout.text[0] + ui.text_width > layout.origin[0] + layout.width
		or layout.text[1] < layout.origin[1]
		or layout.text[1] >= 320
		or layout.portrait[0] < layout.origin[0]
		or layout.portrait[1] < layout.origin[1]
		or layout.portrait[1] >= 320
	):
		error = "Radio panel falls outside the source composition."
		return false
	var binding: Dictionary = panel.corner
	if (
		not content_integer(binding.get("texture"))
		or not content_integer(binding.get("region"))
		or binding.region < 0
		or not radio_atlases.has(str(int(binding.texture)))
	):
		error = "Invalid dialogue corner association."
		return false
	var regions: Array = radio_atlases[str(int(binding.texture))].regions
	if binding.region >= regions.size():
		error = "Dialogue corner falls outside its atlas."
		return false
	var corner: Rect2i = regions[int(binding.region)]
	if (
		corner.size.x <= 0
		or corner.size.y <= 0
		or corner.size.x * 2 > layout.width
		or corner.size.y * 2 > 320 - layout.origin[1]
	):
		error = "Dialogue corner does not fit its panel."
		return false
	for key in ["fill", "border"]:
		var color: Variant = panel.get(key)
		if (
			not color is Array
			or color.size() != 4
			or not color.all(func(n): return content_integer(n) and n >= 0 and n <= 255)
		):
			error = "Invalid supplied panel color."
			return false
	return true


func radio_portrait(speaker: int) -> Texture2D:
	return ui_image(content.radio_ui.portraits[speaker])


func ui_image(binding: Dictionary) -> Texture2D:
	var atlas: Dictionary = radio_atlases[str(int(binding.texture))]
	var result := AtlasTexture.new()
	result.atlas = radio_texture(int(binding.texture))
	result.region = atlas.regions[int(binding.region)]
	return result


func radio_texture(identifier: int) -> Texture2D:
	var key := "radio-" + str(identifier)
	if not texture_cache.has(key):
		texture_cache[key] = ImageTexture.create_from_image(radio_atlases[str(identifier)].image)
	return texture_cache[key]


func radio_glyphs() -> Dictionary:
	var binding: Dictionary = content.radio_ui.font
	return radio_atlases[str(int(binding.texture))].glyphs[int(binding.region)]


func radio_glyph_width(code: int) -> float:
	var glyphs := radio_glyphs()
	if not glyphs.has(code):
		code = 63  # Visible fallback for unsupported glyphs.
	return maxf(1, glyphs[code].size.x + int(content.radio_ui.font_spacing))


func radio_lines(cue: Dictionary) -> PackedStringArray:
	var key := str(int(cue.text)) + ":" + str(int(cue.speaker))
	if radio_lines_cache.has(key):
		return radio_lines_cache[key]
	var binding: Dictionary = content.radio_ui.portraits[int(cue.speaker)]
	var atlas: Dictionary = radio_atlases[str(int(binding.texture))]
	var width: float = content.radio_ui.text_width - atlas.regions[int(binding.region)].size.x
	var lines := bitmap_lines(text(int(cue.text)), width)
	radio_lines_cache[key] = lines
	return lines


func bitmap_lines(value: String, width: float) -> PackedStringArray:
	var lines := PackedStringArray()
	# Native word wrapping uses the imported glyph advances and portrait width.
	for paragraph in value.split("\n"):
		var line := ""
		var line_width := 0.0
		for word in paragraph.split(" ", false):
			var word_width := 0.0
			for index in word.length():
				word_width += radio_glyph_width(word.unicode_at(index))
			var gap := radio_glyph_width(32) if not line.is_empty() else 0.0
			if not line.is_empty() and line_width + gap + word_width > width:
				lines.append(line)
				line = ""
				line_width = 0
			if not line.is_empty():
				line += " "
				line_width += gap
			for index in word.length():
				var advance := radio_glyph_width(word.unicode_at(index))
				if not line.is_empty() and line_width + advance > width:
					lines.append(line)
					line = ""
					line_width = 0
				line += word[index]
				line_width += advance
		lines.append(line)
	return lines


func radio_duration(cue: Dictionary) -> float:
	return (radio_lines(cue).size() + 1) * float(content.radio_ui.line_ms) / 1000.0


func valid_fog(value: Variant, route_count: int) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			[
				"count",
				"primary_count",
				"texture",
				"region",
				"scatter",
				"size_min",
				"size_max",
				"palette",
				"secondary_palette",
				"color_seed"
			]
		)
	):
		return false
	if value.has("center") == value.has("waypoint"):
		return false
	if value.has("center"):
		if not valid_point(value.center):
			return false
	elif not content_integer(value.waypoint) or value.waypoint < 0 or value.waypoint >= route_count:
		return false

	for key in ["count", "primary_count", "texture", "size_min", "size_max", "color_seed"]:
		if not content_integer(value[key]) or value[key] < 0 or value[key] > 10000000:
			return false
	if (
		value.count < 1
		or value.count > 128
		or value.primary_count > value.count
		or value.size_min <= 0
		or value.size_max < value.size_min
	):
		return false
	if (
		not value.scatter is Array
		or value.scatter.size() != 2
		or not value.scatter.all(func(n): return content_integer(n) and absf(n) <= 10000000)
		or value.scatter[0] > value.scatter[1]
	):
		return false
	if (
		not value.region is Array
		or value.region.size() != 4
		or not value.region.all(func(n): return content_integer(n) and n >= 0 and n <= 4096)
		or value.region[2] <= 0
		or value.region[3] <= 0
	):
		return false
	for key in ["palette", "secondary_palette"]:
		if (
			not value[key] is Array
			or value[key].is_empty()
			or value[key].size() > 256
			or not value[key].all(func(n): return content_integer(n) and n >= 0 and n <= 0xffffffff)
		):
			return false
	return value.palette.size() == value.secondary_palette.size()


func fog_texture(value: Dictionary) -> Texture2D:
	var atlas: Dictionary = radio_atlases[str(int(value.texture))]
	var region := Rect2(value.region[0], value.region[1], value.region[2], value.region[3])
	if not Rect2(Vector2.ZERO, atlas.image.get_size()).encloses(region):
		return null
	var result := AtlasTexture.new()
	result.atlas = radio_texture(int(value.texture))
	result.region = region
	return result


func valid_travel() -> bool:
	if not preload("res://src/simulation/travel.gd").valid(content.get("travel"), self):
		error = "Travel and faction rules are missing or invalid. Import the IPA again."
		return false
	return true


func valid_map_ui() -> bool:
	var data: Variant = content.get("map_ui")
	if not data is Dictionary or not preload("res://src/presentation/galaxy_map.gd").valid_layout(data.get("layout")):
		error = "Map layout declarations are missing or invalid. Import the IPA again."
		return false
	if (
		not data is Dictionary
		or not data.has_all(["images", "labels", "planets", "stations", "races", "grid"])
	):
		error = "Map artwork and destination data are missing. Import the IPA again."
		return false
	if (
		not data.images is Dictionary
		or not data.labels is Dictionary
		or not data.planets is Array
		or not data.stations is Dictionary
		or not data.races is Array
		or not data.grid is Dictionary
	):
		error = "Invalid map presentation definitions."
		return false
	if (
		not data.images.has_all(
			[
				"background_left",
				"background_right",
				"galaxy",
				"stars",
				"nebula",
				"selection",
				"selection_ring",
				"position",
				"preview_ring",
				"bracket",
				"quadrant_highlight",
				"system_highlight"
			]
		)
		or not data.labels.has_all(
			[
				"map",
				"info",
				"name",
				"inhabitants",
				"technology",
				"trade",
				"cost",
				"bribe",
				"back",
				"travel",
				"yes",
				"no",
				"quadrant"
			]
		)
		or not data.stations.has_all(["primary_race", "primary", "secondary", "other", "races"])
		or not data.stations.races is Dictionary
	):
		error = "Incomplete map presentation definitions."
		return false
	var icons: Variant = content.get("map_icons")
	if (
		not icons is Dictionary
		or not icons.has_all(["primary_race", "primary", "secondary", "other", "races", "planets"])
		or not icons.races is Dictionary
		or not icons.planets is Array
		or icons.planets.is_empty()
		or not content_integer(icons.primary_race)
		or icons.primary_race < 0
		or icons.primary_race >= data.races.size()
	):
		error = "Map destination symbols are missing or invalid. Import the IPA again."
		return false
	var bindings: Array = (
		icons.planets
		+ [icons.primary, icons.secondary, icons.other]
		+ icons.races.values()
		+ data.images.values()
		+ data.planets
		+ [data.stations.primary, data.stations.secondary, data.stations.other]
		+ data.stations.races.values()
	)
	for binding in bindings:
		if (
			not binding is Dictionary
			or not content_integer(binding.get("texture"))
			or not content_integer(binding.get("region"))
			or not radio_atlases.has(str(int(binding.texture)))
		):
			error = "Invalid map atlas association."
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if (
			binding.region < 0
			or binding.region >= regions.size()
			or regions[int(binding.region)].size.x <= 0
			or regions[int(binding.region)].size.y <= 0
		):
			error = "Map image lies outside its atlas."
			return false
	for label_id in data.labels.values() + data.races:
		if not content_integer(label_id) or label_id < 0 or label_id >= strings.size():
			error = "Invalid map localization reference."
			return false
	for key in ["system_columns", "quadrant_columns", "system_extent", "quadrant_extent"]:
		if not content_number(data.grid.get(key)) or data.grid[key] <= 0 or data.grid[key] > 10000:
			error = "Invalid galaxy coordinate definitions."
			return false
	if (
		not content_integer(data.grid.system_columns)
		or not content_integer(data.grid.quadrant_columns)
		or quadrants.size() != content.tables.quadrant_difficulty.size()
		or systems.size() / quadrants.size() != data.grid.system_columns * data.grid.system_columns
		or quadrants.size() % int(data.grid.quadrant_columns) != 0
		or not content_integer(data.stations.primary_race)
		or data.stations.primary_race < 0
		or data.stations.primary_race >= data.races.size()
	):
		error = "Galaxy tables disagree with the imported map layout."
		return false
	for index in stations.size():
		var station := station_definition(index)
		if (
			station.race < 0
			or station.race >= data.races.size()
			or (station.planet and (station.image < 0 or station.image >= data.planets.size()))
		):
			error = "Invalid destination preview association."
			return false
	return true


func galaxy_position(index: int) -> Vector2:
	var station := station_definition(index)
	var grid: Dictionary = content.map_ui.grid
	var columns := int(grid.system_columns)
	var quadrant_columns := int(grid.quadrant_columns)
	var system := int(station.system) % int(systems.size() / quadrants.size())
	return (
		station.position
		+ Vector2(system % columns, system / columns) * float(grid.system_extent)
		+ (
			Vector2(
				int(station.quadrant) % quadrant_columns, int(station.quadrant) / quadrant_columns
			)
			* float(grid.quadrant_extent)
		)
	)


func station_preview(index: int) -> Texture2D:
	var station := station_definition(index)
	var data: Dictionary = content.map_ui
	if station.planet:
		return ui_image(data.planets[station.image])
	if station.race == data.stations.primary_race:
		return ui_image(data.stations.primary if station.image == 0 else data.stations.secondary)
	return ui_image(data.stations.races.get(str(station.race), data.stations.other))


func station_map_icon(index: int) -> Texture2D:
	var station := station_definition(index)
	var icons: Dictionary = content.map_icons
	if station.planet:
		var per_system: int = stations.size() / systems.size()
		var ordinal := 0
		for previous in range(int(station.system) * per_system, index):
			if int(stations[previous][1]) == 1:
				ordinal += 1
		return ui_image(icons.planets[ordinal % icons.planets.size()])
	if station.race == icons.primary_race:
		return ui_image(icons.primary if station.image == 0 else icons.secondary)
	return ui_image(icons.races.get(str(station.race), icons.other))


func station_info(index: int, discovered: bool) -> Array:
	var station := station_definition(index)
	var data: Dictionary = content.map_ui
	return [
		[text(int(data.labels.name)), station.name],
		[text(int(data.labels.inhabitants)), text(int(data.races[station.race]))],
		[text(int(data.labels.technology)), str(station.technology) if discovered else "?"],
		[
			text(int(data.labels.trade)),
			text(int(data.labels.yes if station.shop else data.labels.no)) if discovered else "?"
		]
	]


func valid_flight_ui() -> bool:
	var ui: Variant = content.get("flight_ui")
	if not ui is Dictionary or not ui.get("buttons") is Dictionary:
		error = "Flight control artwork is missing. Import the IPA again."
		return false
	if not valid_tutorial_ui(ui.get("tutorial")):
		error = "Invalid tutorial presentation. Import the IPA again."
		return false
	for name in ["missiles", "weapon", "pause", "boost"]:
		var button: Variant = ui.buttons.get(name)
		if not button is Dictionary:
			error = "Missing flight control artwork."
			return false
		for state in ["normal", "pressed"]:
			var binding: Variant = button.get(state)
			if (
				not binding is Dictionary
				or not content_integer(binding.get("texture"))
				or not content_integer(binding.get("region"))
				or not radio_atlases.has(str(int(binding.texture)))
			):
				error = "Invalid flight control atlas association."
				return false
			var atlas: Dictionary = radio_atlases[str(int(binding.texture))]
			if binding.region < 0 or binding.region >= atlas.regions.size():
				error = "Flight control image lies outside its atlas."
				return false
			var region: Rect2i = atlas.regions[int(binding.region)]
			if region.size.x <= 0 or region.size.y <= 0:
				error = "Flight control image is empty."
				return false
	var artwork: Variant = ui.get("artwork")
	if (
		not artwork is Dictionary
		or not artwork.get("images") is Dictionary
		or not artwork.get("layout") is Dictionary
	):
		error = "Missing flight HUD composition. Import the IPA again."
		return false
	for key in [
		"fire_overlay",
		"fire_frame",
		"stick_pressed",
		"stick_normal",
		"stick_frame",
		"bar",
		"hull",
		"shield",
		"timer"
	]:
		var binding: Variant = artwork.images.get(key)
		if (
			not binding is Dictionary
			or not content_integer(binding.get("texture"))
			or not content_integer(binding.get("region"))
			or not radio_atlases.has(str(int(binding.texture)))
		):
			error = "Invalid HUD artwork association."
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if (
			binding.region < 0
			or binding.region >= regions.size()
			or regions[int(binding.region)].size.x <= 0
			or regions[int(binding.region)].size.y <= 0
		):
			error = "Missing HUD image in the supplied atlas."
			return false
	for key in [
		"pause_top",
		"timer_top",
		"stick_left",
		"hull_top",
		"icon_left",
		"stick_radius",
		"fire_right",
		"fire_bottom",
		"pause_right",
		"stick_bottom",
		"boost_offset",
		"boost_bottom",
		"bar_left_offset",
		"bar_inset_twice",
		"shield_top_offset",
		"weapon_right",
		"weapon_bottom",
		"missiles_right",
		"missiles_bottom",
		"fire_frame_right",
		"timer_right",
		"weapon_label_right",
		"weapon_label_bottom"
	]:
		if (
			not content_integer(artwork.layout.get(key))
			or artwork.layout[key] <= 0
			or artwork.layout[key] >= 320
		):
			error = "Invalid flight HUD margin."
			return false
	if not artwork.get("colors") is Dictionary:
		error = "Missing HUD colors."
		return false
	for key in ["hull", "shield"]:
		if (
			not content_integer(artwork.colors.get(key))
			or artwork.colors[key] < 0
			or artwork.colors[key] > 0xffffffff
		):
			error = "Invalid HUD color."
			return false
	if not valid_radar_ui(ui.get("radar")):
		return false
	if not preload("res://src/presentation/damage_feedback.gd").valid(ui.get("damage"), self):
		error = "Invalid damage indicator artwork or timing. Import the IPA again."
		return false
	return true


func valid_radar_ui(value: Variant) -> bool:
	error = "Invalid flight radar artwork. Import the IPA again."
	if not value is Dictionary or not value.get("images") is Dictionary:
		return false
	for key in [
		"enemy_near",
		"enemy_far",
		"enemy_off",
		"ally_near",
		"ally_far",
		"ally_off",
		"objective_near",
		"objective_off",
		"lead",
		"frame_side",
		"frame_edge",
		"aim",
		"aim_hit"
	]:
		var binding: Variant = value.images.get(key)
		if (
			not binding is Dictionary
			or not content_integer(binding.get("texture"))
			or not content_integer(binding.get("region"))
			or not radio_atlases.has(str(int(binding.texture)))
		):
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if (
			binding.region < 0
			or binding.region >= regions.size()
			or regions[int(binding.region)].size.x <= 0
			or regions[int(binding.region)].size.y <= 0
		):
			return false
	for key in ["margin", "health_height", "health_gap", "hit_ms"]:
		if not content_integer(value.get(key)) or value[key] <= 0 or value[key] > 1000:
			return false
	for key in ["near_extent", "aim_distance"]:
		if not content_number(value.get(key)) or value[key] <= 0 or value[key] > 100000:
			return false
	if not value.get("health_edge") is Dictionary:
		return false
	for team in ["enemy", "ally"]:
		var edge: Variant = value.health_edge.get(team)
		if (
			not edge is Dictionary
			or not content_integer(edge.get("color"))
			or edge.color < 0 or edge.color > 0xffffffff
			or not content_integer(edge.get("gap"))
			or edge.gap < 0 or edge.gap > 1000
		):
			return false
	var lead: Variant = value.get("lead")
	if not lead is Dictionary or not lead.get("enabled") is bool:
		return false
	for key in ["bucket", "scale"]:
		if not content_number(lead.get(key)) or lead[key] <= 0 or lead[key] > 100000:
			return false
	if (
		not content_integer(lead.get("minimum"))
		or lead.minimum <= 0
		or lead.minimum > 1000
		or not content_integer(lead.get("option_text"))
		or lead.option_text < 0
		or lead.option_text >= strings.size()
	):
		return false
	if not value.get("distant_actors") is Array or value.distant_actors.size() > 64:
		return false
	for actor in value.distant_actors:
		if (
			not content_integer(actor)
			or actor < 0
			or actor >= content.tables.actor_collision.size()
		):
			return false
	if not value.get("colors") is Dictionary:
		return false
	for key in ["enemy", "ally"]:
		if (
			not content_integer(value.colors.get(key))
			or value.colors[key] < 0
			or value.colors[key] > 0xffffffff
		):
			return false
	var side: Texture2D = ui_image(value.images.frame_side)
	if side.get_height() <= side.get_width() * 2:
		return false
	error = ""
	return true


func valid_tutorial_ui(config: Variant) -> bool:
	if not config is Dictionary:
		return false
	for key in ["chapter", "duration_ms", "blink_limit_ms", "blink_ms"]:
		if not content_integer(config.get(key)) or config[key] < 0:
			return false
	if (
		config.chapter >= content.chapters.size()
		or config.duration_ms <= 0
		or config.duration_ms > 60000
		or config.blink_limit_ms >= config.duration_ms
		or config.blink_ms <= 0
		or config.blink_ms > 60000
		or not config.get("steps") is Array
		or config.steps.is_empty()
		or config.steps.size() > 32
	):
		return false
	var messages: Array = content.missions[int(config.chapter)].get("radio", [])
	for index in config.steps.size():
		var step: Variant = config.steps[index]
		if (
			not step is Dictionary
			or not content_integer(step.get("radio"))
			or step.radio < -1
			or step.radio >= messages.size()
			or (index == 0 and step.radio < 0)
			or step.get("action") not in ["weapon", "fire", "missiles", "boost"]
		):
			return false
	return true


func valid_briefing_ui() -> bool:
	error = "Invalid imported briefing presentation. Import the IPA again."
	var ui: Variant = content.get("briefing_ui")
	if not ui is Dictionary:
		error = "Briefing presentation data is missing. Import the IPA again."
		return false
	var audio: Variant = ui.get("audio")
	if not audio is Dictionary or not content_integer(audio.get("voice_text_offset")):
		return false
	if audio.voice_text_offset < 0:
		return false
	if not audio.get("music") is Dictionary or not content_integer(audio.music.get("alien_race")):
		return false
	for key in ["title", "station", "alien"]:
		if not content_integer(audio.music.get(key)):
			return false
		var record: Dictionary = content.sound_bank.get(str(int(audio.music[key])), {})
		if record.is_empty() or record.path.get_extension().to_lower() != "mp3":
			return false
	for action in ["next", "back", "skip", "confirm"]:
		if not content_integer(audio.get(action)) or not content.sound_bank.has(str(int(audio[action]))):
			return false
	for key in ["panel", "portrait_left", "portrait_right", "text_origin"]:
		var values: Variant = ui.get(key)
		if not values is Array or values.size() != (4 if key == "panel" else 2):
			return false
		if not values.all(
			func(value): return content_integer(value) and value >= 0 and value <= 480
		):
			return false
	for key in ["text_width", "narration_chapter", "narration_pages", "protagonist"]:
		if not content_integer(ui.get(key)) or ui[key] < 0:
			return false
	if (
		ui.panel[2] <= 0
		or ui.panel[3] <= 0
		or ui.text_width <= 0
		or ui.text_width > ui.panel[2]
		or ui.narration_chapter >= content.chapters.size()
		or ui.narration_pages > content.chapters[int(ui.narration_chapter)].dialogue.size()
		or ui.protagonist >= content.radio_ui.portraits.size()
	):
		return false
	if not ui.get("labels") is Dictionary or not ui.get("footer") is Dictionary:
		return false
	for key in ["first_back", "back", "next", "start", "skip", "skip_question"]:
		if (
			not content_integer(ui.labels.get(key))
			or ui.labels[key] < 0
			or ui.labels[key] >= strings.size()
		):
			return false
	for key in ["y", "margin"]:
		if not content_integer(ui.footer.get(key)) or ui.footer[key] < 0 or ui.footer[key] >= 320:
			return false
	for key in ["normal", "pressed", "center_normal", "center_pressed"]:
		var binding: Variant = ui.footer.get(key)
		if (
			not binding is Dictionary
			or not content_integer(binding.get("texture"))
			or not content_integer(binding.get("region"))
			or not radio_atlases.has(str(int(binding.texture)))
		):
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if binding.region < 0 or binding.region >= regions.size():
			return false
	for chapter in content.chapters:
		if (
			not content_integer(chapter.speaker)
			or chapter.speaker < 0
			or chapter.speaker >= content.radio_ui.portraits.size()
		):
			return false
	error = ""
	return true


func briefing_cue(chapter: int, page: int) -> Dictionary:
	if (
		chapter < 0
		or chapter >= content.chapters.size()
		or page < 0
		or page >= content.chapters[chapter].dialogue.size()
	):
		return {}
	var ui: Dictionary = content.briefing_ui
	var narration: bool = chapter == ui.narration_chapter and page < ui.narration_pages
	var left := page % 2 == 1
	return {
		"text": int(content.chapters[chapter].dialogue[page]),
		"sound": int(content.chapters[chapter].dialogue[page]) - int(ui.audio.voice_text_offset),
		"speaker":
		(
			-1
			if narration
			else (int(ui.protagonist) if left else int(content.chapters[chapter].speaker))
		),
		"left": left,
		"page": page,
		"count": content.chapters[chapter].dialogue.size()
	}


func valid_sky() -> bool:
	error = "Invalid imported sky declarations. Import the IPA again."
	var data: Variant = content.get("sky")
	if not data is Dictionary:
		return false
	if (
		not data.get("blends") is Array
		or data.blends.size() != 4
		or not data.blends.all(func(mode): return mode in ["opaque", "mix", "add"])
	):
		return false
	for key in [
		"base_mesh",
		"planet_base",
		"sun_base",
		"variant_count",
		"base_texture",
		"cloud_texture",
		"sun_texture_base",
		"seed_multiplier"
	]:
		if not content_integer(data.get(key)) or data[key] < 0:
			return false
	if data.variant_count <= 0 or data.variant_count > 32 or data.seed_multiplier <= 0:
		return false
	if (
		not data.get("cloud_meshes") is Array
		or data.cloud_meshes.is_empty()
		or data.cloud_meshes.size() > 32
	):
		return false
	var meshes: Array = data.cloud_meshes.duplicate()
	meshes.append(data.base_mesh)
	for index in int(data.variant_count):
		meshes.append(int(data.planet_base) + index)
		meshes.append(int(data.sun_base) + index)
	for identifier in meshes:
		if not content_integer(identifier) or not content.resources.has(str(int(identifier))):
			return false
	if not data.get("tints") is Array or data.tints.is_empty() or data.tints.size() > 32:
		return false
	var textures := [data.base_texture, data.cloud_texture]
	for index in data.tints.size():
		var tint: Variant = data.tints[index]
		if (
			not tint is Array
			or tint.size() != 3
			or not tint.all(
				func(value): return content_integer(value) and value >= 0 and value <= 255
			)
		):
			return false
		textures.append(int(data.sun_texture_base) + index)
	for identifier in textures:
		if not radio_atlases.has(str(int(identifier))):
			return false
	if (
		not data.get("campaign_overrides") is Array
		or data.campaign_overrides.size() != content.chapters.size()
	):
		return false
	for index in data.campaign_overrides:
		if not content_integer(index) or index < -1 or index >= data.variant_count:
			return false
	for station in stations:
		if int(station[2]) < 0 or int(station[2]) >= data.variant_count:
			return false
	var random: Variant = data.get("random")
	if not random is Dictionary:
		return false
	for key in ["multiplier", "increment", "seed_xor", "bits", "output_bits"]:
		if not content_integer(random.get(key)) or random[key] <= 0:
			return false
	if random.bits > 48 or random.output_bits > 31 or random.output_bits >= random.bits:
		return false
	var mask := (1 << int(random.bits)) - 1
	if random.multiplier > mask or random.increment > mask or random.seed_xor > mask:
		return false
	error = ""
	return true


func valid_lighting() -> bool:
	error = "Invalid imported scene lighting. Import the IPA again."
	var data: Variant = content.get("lighting")
	if (
		not data is Dictionary
		or not content_integer(data.get("material_face"))
		or int(data.material_face) not in [0x404, 0x408]
	):
		return false
	for key in ["ambient_light", "material_ambient", "material_diffuse"]:
		if not lighting_color(data.get(key), 4):
			return false
	if (
		not data.get("directions") is Array
		or data.directions.size() != int(content.sky.variant_count)
	):
		return false
	for direction in data.directions:
		if not Combat.valid_vector(direction) or Combat.vector(direction).length_squared() < 1:
			return false
	if not data.get("diffuse") is Array or data.diffuse.size() != content.sky.tints.size():
		return false
	for color in data.diffuse:
		if not lighting_color(color, 3):
			return false
	if (
		not Combat.valid_vector(data.get("hangar_direction"))
		or Combat.vector(data.hangar_direction).length_squared() < 1
		or not content_integer(data.get("hangar_race"))
		or not lighting_color(data.get("hangar_diffuse"), 3)
		or not lighting_color(data.get("hangar_default"), 3)
	):
		return false
	error = ""
	return true


func lighting_color(value: Variant, size: int) -> bool:
	return (
		value is Array
		and value.size() == size
		and value.all(
			func(component): return content_number(component) and component >= 0 and component <= 1
		)
	)


func set_lighting(variant: int, style: int, station_id: int, hangar: bool = false) -> void:
	var data: Dictionary = content.lighting
	var ambient := Vector3.ONE * .2
	var diffuse := Vector3.ONE * .8
	# GLES ignores an invalid material face. The supported file submits FRONT;
	# use standard defaults, preserving its raw declaration for compatibility research.
	if int(data.material_face) == 0x408:
		ambient = Vector3(
			data.material_ambient[0], data.material_ambient[1], data.material_ambient[2]
		)
		diffuse = Vector3(
			data.material_diffuse[0], data.material_diffuse[1], data.material_diffuse[2]
		)
	var light_color: Array = data.diffuse[style]
	if hangar:
		light_color = (
			data.hangar_diffuse
			if station_definition(station_id).race == data.hangar_race
			else data.hangar_default
		)
	lighting_profile = {
		"direction":
		Combat.vector(data.hangar_direction if hangar else data.directions[variant]).normalized(),
		"ambient":
		(
			ambient
			* (
				Vector3(data.ambient_light[0], data.ambient_light[1], data.ambient_light[2])
				+ Vector3.ONE * .2
			)
		),
		"diffuse": diffuse * Combat.vector(light_color)
	}
	for identifier in material_cache:
		if content.materials[str(identifier)].lit:
			apply_lighting(material_cache[identifier])


func apply_lighting(material: ShaderMaterial) -> void:
	for key in lighting_profile:
		material.set_shader_parameter("light_" + key, lighting_profile[key])


func valid_recovery() -> bool:
	if not preload("res://src/simulation/recovery.gd").valid(content.get("recovery"), self):
		error = "Cargo recovery data is missing or invalid. Import the IPA again."
		return false
	return true


func valid_survival() -> bool:
	if not preload("res://src/content/survival_content.gd").valid(content.get("survival"), self):
		error = "Survival data or artwork is missing or invalid. Import the IPA again."
		return false
	return true


func valid_player_armament() -> bool:
	if not preload("res://src/simulation/player_armament.gd").valid(
		content.get("player_armament"), self
	):
		error = "Invalid imported player weapon declarations. Import the IPA again."
		return false
	return true


func valid_projectile_trails() -> bool:
	if not preload("res://src/presentation/projectile_trail.gd").valid(
		content.get("projectile_trails"), self
	):
		error = "Invalid imported projectile trail presentation. Import the IPA again."
		return false
	return true


func valid_lens_flare() -> bool:
	if not preload("res://src/presentation/lens_flare.gd").valid(content.get("lens_flare"), self):
		error = "Invalid imported lens flare presentation. Import the IPA again."
		return false
	return true


func valid_player_hit() -> bool:
	if not preload("res://src/presentation/player_hit.gd").valid(self):
		error = "Invalid player hit effects or sound resources. Import the IPA again."
		return false
	return true


func sound_clip(id: int) -> AudioStream:
	if sound_cache.has(id):
		return sound_cache[id]
	var record: Dictionary = content.sound_bank.get(str(id), {})
	if record.is_empty():
		return null
	var stream: AudioStream
	if record.path.get_extension().to_lower() == "wav":
		stream = AudioStreamWAV.load_from_file(root.path_join(record.path))
	else:
		var mp3 := AudioStreamMP3.new()
		mp3.data = read(record.path)
		stream = mp3
	if stream != null:
		sound_cache[id] = stream
	return stream


func valid_actor_destruction() -> bool:
	if not preload("res://src/presentation/explosion.gd").valid(
		content.get("actor_destruction"), self
	):
		error = "Invalid imported actor destruction effects. Import the IPA again."
		return false
	return true


func valid_fighter_motion() -> bool:
	if not preload("res://src/simulation/fighter_motion.gd").valid_data(
		content.get("fighter_motion")
	):
		error = "Unsupported fighter current-speed declarations."
		return false
	return true


func valid_npc_exhaust() -> bool:
	if not preload("res://src/presentation/npc_exhaust.gd").valid_data(content.get("npc_exhaust")):
		error = "Unsupported NPC burner declarations. Import the IPA again."
		return false
	return true


func valid_title_ui() -> bool:
	error = "Invalid imported title presentation. Import the IPA again."
	var data: Variant = content.get("title_ui")
	if not preload("res://src/presentation/title_menu.gd").valid_data(data):
		return false
	for binding in data.images.values() + data.indicator_frames:
		if not radio_atlases.has(str(int(binding.texture))):
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if binding.region >= regions.size():
			return false
		var region: Rect2 = regions[int(binding.region)]
		if region.size.x <= 0 or region.size.y <= 0:
			return false
	for identifier in data.labels.values():
		if identifier >= strings.size():
			return false
	error = ""
	return true


func valid_station_ui() -> bool:
	error = "Invalid imported station presentation. Import the IPA again."
	var data: Variant = content.get("station_ui")
	if not preload("res://src/presentation/station_menu.gd").valid_data(data):
		return false
	for binding in data.images.values() + data.status.images.values():
		if not radio_atlases.has(str(int(binding.texture))):
			return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if binding.region >= regions.size() or not regions[int(binding.region)].has_area():
			return false
	var identifiers: Array = data.tabs.map(func(tab): return tab.label)
	identifiers.append_array(data.footer_labels.values())
	identifiers.append(data.credits_label)
	identifiers.append_array(data.status.labels.values())
	identifiers.append(data.status.reputation_base + data.status.reputation_max)
	if data.status.protagonist >= content.radio_ui.portraits.size():
		return false
	if identifiers.any(func(identifier): return identifier >= strings.size()):
		return false
	if not preload("res://src/presentation/destination_menu.gd").valid_layout(data.get("destination")):
		return false
	error = ""
	return true


func valid_hangar_ui() -> bool:
	error = "Invalid imported Hangar presentation. Import the IPA again."
	var data: Variant = content.get("hangar_ui")
	if not preload("res://src/presentation/hangar_catalogue.gd").valid_data(data): return false
	var hints: Variant = data.get("hints")
	if not hints is Dictionary or not hints.get("messages") is Dictionary or hints.messages.size() != 4:
		return false
	for role in ["intro", "ship", "cargo", "shop"]:
		var identifier: Variant = hints.messages.get(role)
		if not content_integer(identifier) or identifier < 0 or identifier >= strings.size():
			return false
	if not content_integer(hints.get("sound")) or not content.sound_bank.has(str(int(hints.sound))):
		return false
	if not preload("res://src/presentation/hangar_scene.gd").valid_data(data.get("scene")):
		return false
	var meshes: Array = data.scene.shadows.values()
	for room in data.scene.interiors.values():
		meshes.append_array([room.body, room.lights])
	for identifier in meshes:
		var resource: Variant = content.resources.get(str(int(identifier)))
		if not resource is Dictionary or not str(resource.get("path", "")).ends_with(".aem"):
			return false
		if not FileAccess.file_exists(root.path_join(resource.path)):
			return false
	for actor in content.tables.buyable_ships:
		if not data.scene.shadows.has(str(int(actor))):
			return false
	for key in data.pictures:
		var count: int = ships.size() if key.begins_with("ship") else items.size()
		if data.pictures[key].size() < count: return false
		for binding in data.pictures[key]:
			if not radio_atlases.has(str(int(binding.texture))): return false
			var regions: Array = radio_atlases[str(int(binding.texture))].regions
			if binding.region >= regions.size() or not regions[int(binding.region)].has_area(): return false
	for binding in data.quantity.images.values():
		if not radio_atlases.has(str(int(binding.texture))): return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if binding.region >= regions.size() or not regions[int(binding.region)].has_area(): return false
	for identifier in data.labels.values() + data.quantity.labels.values() + data.exchange.labels.values() + data.tabs.map(func(tab): return tab.label):
		if identifier >= strings.size(): return false
	for key in data.description:
		var binding: Dictionary = data.description[key]
		var count: int = ships.size() if key == "ships" else items.size()
		if binding.base + binding.stride * (count - 1) >= strings.size(): return false
	error = ""
	return true


func valid_defeat_ui() -> bool:
	error = "Invalid imported defeat presentation. Import the IPA again."
	var data: Variant = content.get("defeat_ui")
	if not data is Dictionary or not data.get("labels") is Dictionary:
		return false
	for key in ["lost", "timeout", "load", "menu", "missing"]:
		var value: Variant = data.labels.get(key)
		if not content_integer(value) or value < 0 or value >= strings.size(): return false
	var image: Variant = data.get("image")
	if not image is Dictionary or not content_integer(image.get("texture")) or not content_integer(image.get("region")):
		return false
	if not radio_atlases.has(str(int(image.texture))): return false
	var regions: Array = radio_atlases[str(int(image.texture))].regions
	if image.region < 0 or image.region >= regions.size() or not regions[int(image.region)].has_area(): return false
	if not content_integer(data.get("image_y")) or data.image_y < 0 or data.image_y > 320: return false
	error = ""
	return true


func valid_pause_ui() -> bool:
	error = "Invalid imported pause presentation. Import the IPA again."
	var data: Variant = content.get("pause_ui")
	if not data is Dictionary or not data.get("labels") is Dictionary or data.get("rows") != 4:
		return false
	if not content_number(data.get("row_step")) or data.row_step <= 0 or data.row_step > 60:
		return false
	for key in ["resume", "options", "help", "menu"]:
		var label: Variant = data.labels.get(key)
		if not content_integer(label) or label < 0 or label >= strings.size(): return false
	error = ""
	return true


func valid_options_ui() -> bool:
	error = "Invalid imported options presentation. Import the IPA again."
	var data: Variant = content.get("options_ui")
	if not data is Dictionary or not data.get("labels") is Dictionary or not data.get("images") is Dictionary:
		return false
	for key in ["controls", "audio", "display", "music", "effects", "invert"]:
		var label: Variant = data.labels.get(key)
		if not content_integer(label) or label < 0 or label >= strings.size(): return false
	for key in ["checked", "unchecked", "grabber", "slider_selected", "slider_idle"]:
		var image: Variant = data.images.get(key)
		if not image is Dictionary or not content_integer(image.get("texture")) or not content_integer(image.get("region")):
			return false
		if not radio_atlases.has(str(int(image.texture))): return false
		var regions: Array = radio_atlases[str(int(image.texture))].regions
		if image.region < 0 or image.region >= regions.size() or not regions[int(image.region)].has_area(): return false
	for key in ["rail_fill", "rail_border"]:
		if not data.get(key) is Array or data[key].size() != 4 or not data[key].all(func(v): return content_integer(v) and v >= 0 and v <= 255):
			return false
	if not content_integer(data.get("volume_max")) or data.volume_max <= 0 or data.volume_max > 10000:
		return false
	error = ""
	return true


func valid_board_ui() -> bool:
	error = "Invalid imported mission-board presentation. Import the IPA again."
	var data: Variant = content.get("board_ui")
	if not preload("res://src/presentation/mission_board.gd").valid_data(data):
		return false
	for binding in data.images.values():
		if not radio_atlases.has(str(int(binding.texture))): return false
		var regions: Array = radio_atlases[str(int(binding.texture))].regions
		if binding.region >= regions.size() or not regions[int(binding.region)].has_area(): return false
	for identifier in data.labels.values():
		if identifier >= strings.size(): return false
	if data.special_portrait >= content.radio_ui.portraits.size(): return false
	error = ""
	return true


func valid_combat_presentation() -> bool:
	if not preload("res://src/presentation/flight_music.gd").valid(content.get("flight_music"), content.sound_bank):
		error = "Invalid radar music definitions. Import the IPA again."
		return false
	error = "Invalid NPC projectile definitions. Import the IPA again."
	var models: Variant = content.get("npc_projectiles")
	if not models is Dictionary: return false
	for key in ["124", "128", "136", "140", "144"]:
		if not content_integer(models.get(key)) or not content.resources.has(str(int(models[key]))): return false
	for key in ["alien_actor", "turret_actor"]:
		if not content_integer(models.get(key)) or models[key] < 0 or models[key] >= content.tables.actor_meshes.size(): return false
	error = ""
	return true
