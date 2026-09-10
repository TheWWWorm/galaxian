extends RefCounted
## Campaign completion, skipping, and exploration are distinct saved states.
## Imported scenarios drive the native mission state; unsupported chapters remain
## unavailable until their behavior has been reconstructed and verified.
const SCHEMA := 29
const BodyContact = preload("res://src/simulation/body_contact.gd")
const PilotStatistics = preload("res://src/simulation/pilot_statistics.gd")
const ExplorationArea = preload("res://src/simulation/exploration_area.gd")
const PlayerArmament = preload("res://src/simulation/player_armament.gd")
const Recovery = preload("res://src/simulation/recovery.gd")
const Travel = preload("res://src/simulation/travel.gd")
const Motion = preload("res://src/simulation/flight_motion.gd")
const Progression = preload("res://src/simulation/progression.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Encounters = preload("res://src/simulation/encounters.gd")
const Mission = preload("res://src/simulation/mission.gd")
const Contracts = preload("res://src/simulation/contracts.gd")
const ContractEncounters = preload("res://src/simulation/contract_encounters.gd")
const Market = preload("res://src/simulation/market.gd")
const Loadout = preload("res://src/simulation/loadout.gd")
var loadout := Loadout.new()
var ship_value := 0
var market_seed := 0
var market_generation := 0
var markets := {}
var content_id := ""
var slot := "campaign"
var campaign_state := "active"
var chapter := 0
var briefing_page := -1
var statistics := PilotStatistics.create()
var progression := Progression.create()
var docked := true
var station_id := 0
var credits := 0
var ship_id := 0
var weapon_id := 0
var cargo := {}
var visited: Array = [0]
var rating := 0
var active_job := {}
var exploration := {}
var contract_rewards: Array = []
var recovery := {}
var checkpoints := {}
var _contract_definition := {}
var motion := Motion.create()
var combat := Combat.create()
var hull := 0.0
var shield := 0.0
var elapsed := 0.0
var flight_position := Vector3.ZERO
var flight_rotation := Vector3.ZERO
var error := ""
var library


func configure(data, skip: bool = false) -> void:
	library = data
	content_id = data.id
	slot = "free" if skip else "campaign"
	campaign_state = "skipped" if skip else "active"
	chapter = 0
	briefing_page = -1
	statistics = PilotStatistics.create()
	progression = Progression.create()
	station_id = int(data.content.initial.station_index)
	credits = int(data.content.initial.credits)
	rating = int(data.content.travel.initial_rating)
	ship_id = int(data.content.initial.ship_index)
	weapon_id = int(data.content.initial.weapon_index)
	loadout.configure(data, weapon_id)
	ship_value = int(int(data.ships[ship_id][6]) * float(data.content.economy.ship_resale_factor))
	market_seed = randi() & 0x7fffffff
	market_generation = 0
	markets = {}
	cargo = {}
	visited = [station_id]
	active_job = {}
	exploration = {}
	contract_rewards = []
	recovery = {}
	checkpoints = {}
	_contract_definition = {}
	motion = Motion.create()
	combat = Combat.create()
	docked = true
	hull = max_hull()
	shield = max_shield()
	elapsed = 0
	flight_position = Vector3.ZERO
	flight_rotation = Vector3.ZERO


func exploration_unlocked() -> bool:
	return campaign_state in ["completed", "skipped"]


func skip_campaign() -> void:
	if campaign_state != "active":
		return
	briefing_page = -1
	campaign_state = "skipped"
	slot = "free"
	active_job = {}
	checkpoints = {}
	_contract_definition = {}
	markets.clear()
	# No completion flag, money or equipment rewards are granted for skipping.


func complete_campaign() -> bool:
	if campaign_state != "active" or not terminal_chapter(chapter) or not ready_to_finish():
		error = "Finish the final mission and its closing transmission first."
		return false
	return finish_mission()


func terminal_chapter(index: int) -> bool:
	if library == null or index < 0 or index + 1 != library.content.chapters.size():
		return false
	var definition: Dictionary = library.mission_definition(index)
	return (
		not definition.is_empty() and int(definition.get("ending", {}).get("chapter", -1)) == index
	)


func campaign_ending_text() -> String:
	if campaign_state != "completed" or not terminal_chapter(chapter - 1):
		return ""
	return library.text(int(library.mission_definition(chapter - 1).ending.text))


func max_hull() -> float:
	return float(library.ships[ship_id][4]) if library != null else 0.0


func max_shield() -> float:
	return loadout.shield_capacity() if library != null else 0.0


func cargo_capacity() -> int:
	return int(library.ships[ship_id][5]) if library != null else 0


func cargo_used() -> int:
	var count := loadout.hold.size()
	for value in cargo.values():
		count += int(value)
	return count


func mission_available() -> bool:
	return (
		not _contract_definition.is_empty()
		if active_job.get("kind") == "contract"
		else library.mission_playable(chapter)
	)


func begin_training() -> bool:
	return begin_mission() if chapter == 0 else false


func begin_mission() -> bool:
	if campaign_state != "active" or not docked or not mission_available():
		error = "This campaign mission is not available yet."
		return false
	if loadout.weapons().is_empty():
		error = "Fit a weapon before starting this mission."
		return false
	remember_checkpoint("station")
	active_job = Mission.create(
		mission_definition(),
		chapter,
		station_id,
		library,
		market_seed ^ (chapter * 73856093),
		rank()
	)
	briefing_page = -1
	motion = Motion.create()
	combat = Combat.create()
	docked = false
	flight_position = Vector3.ZERO
	flight_rotation = Vector3.ZERO
	remember_checkpoint("departure")
	return true


func waypoint_reached() -> void:
	if active_job.get("kind") in ["campaign", "contract"]:
		Mission.reach_waypoint(mission_definition(), active_job)


func route_length() -> int:
	return mission_definition().get("route", []).size()


func damage_actor(index: int, amount: float) -> bool:
	return (
		not active_job.is_empty()
		and Mission.damage(mission_definition(), active_job, index, amount)
	)


func advance_mission(seconds: float) -> void:
	if not docked and active_job.get("kind") in ["campaign", "contract"]:
		Mission.advance(mission_definition(), active_job, seconds, library)


func player_weapon_ids(weapon: int) -> Array[int]:
	return PlayerArmament.weapon_ids(weapon, library)


func weapon_enabled(_weapon: int) -> bool:
	return true


func actor_weapons() -> Dictionary:
	var weapons: Dictionary = (
		library.definition_weapons(mission_definition(), int(active_job.rank))
		if not active_job.is_empty()
		else {}
	)
	var directions := Mission.Sequence.directives(mission_definition(), active_job)
	for actor in directions.targets:
		if weapons.has(-1 - int(actor)):
			weapons[-1 - int(actor)].target_ids = [int(directions.targets[actor])]
	weapons.merge(PlayerArmament.profiles(library, range(active_job.get("actors", []).size())))
	return weapons


func advance_radio(seconds: float) -> void:
	if not docked and active_job.get("kind") in ["campaign", "contract"]:
		Mission.Radio.advance(mission_definition(), active_job, seconds, library)
		if active_job.has("tutorial") and not active_job.failed:
			Mission.Tutorial.advance(
				library.content.flight_ui.tutorial,
				active_job.tutorial,
				active_job.radio.shown,
				seconds
			)


func tutorial_cue() -> Dictionary:
	if not active_job.has("tutorial") or active_job.failed:
		return {}
	return Mission.Tutorial.cue(library.content.flight_ui.tutorial, active_job.tutorial)


func radio_text() -> String:
	if active_job.is_empty() or int(active_job.radio.current) < 0:
		return ""
	var message: Dictionary = mission_definition().radio[int(active_job.radio.current)]
	return library.text(int(message.text))


func radio_cue() -> Dictionary:
	if (
		active_job.is_empty()
		or int(active_job.radio.current) < 0
		or float(active_job.radio.get("delay", 0.0)) > 0
	):
		return {}
	return mission_definition().radio[int(active_job.radio.current)]


func dismiss_radio() -> void:
	if radio_cue().is_empty():
		return
	active_job.radio.current = -1
	active_job.radio.remaining = 0.0
	active_job.radio.delay = 0.0


func retry_mission() -> void:
	active_job = {}
	_contract_definition = {}
	motion = Motion.create()
	combat = Combat.create()
	docked = true
	hull = max_hull()
	shield = max_shield()
	flight_position = Vector3.ZERO
	flight_rotation = Vector3.ZERO


func mission_definition() -> Dictionary:
	return (
		_contract_definition
		if active_job.get("kind") == "contract"
		else (library.mission_definition(chapter) if campaign_state == "active" else {})
	)


func mission_route() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for coordinate in mission_definition().get("route", []):
		result.append(Mission.point(coordinate))
	return result


func contract_offers() -> Array:
	if not docked or not exploration_unlocked():
		return []
	return Contracts.generate(
		library, station_id, Contracts.board_seed(market_seed, market_generation, station_id)
	)


func contract_reference(index: int) -> Dictionary:
	return {"station": station_id, "visit": market_generation, "index": index}


func contract_paid(reference: Dictionary) -> bool:
	var key := Contracts.reference_key(reference)
	return contract_rewards.any(
		func(receipt): return Contracts.reference_key(receipt.reference) == key
	)


func build_contract(reference: Variant, level: int, root_seed: int) -> Dictionary:
	var definition := build_contract_encounter(reference, level, root_seed)
	if not definition.is_empty():
		var offer := Contracts.reference_offer(library, root_seed, reference)
		definition.source_mission_type = int(offer.type)
	return definition


func build_contract_encounter(reference: Variant, level: int, root_seed: int) -> Dictionary:
	var offer := Contracts.reference_offer(library, root_seed, reference)
	if not Contracts.supported(library, offer):
		return {}
	if library.content.contracts.capture.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.capture(
			library,
			library.content.contracts.capture,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.intercept.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.intercept(
			library,
			library.content.contracts.intercept,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.escort.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.escort(
			library,
			library.content.contracts.escort,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.asteroids.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.asteroids(
			library,
			library.content.contracts.asteroids,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.minefield.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.minefield(
			library,
			library.content.contracts.minefield,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.clearance.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.clearance(
			library,
			library.content.contracts.clearance,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.battles.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.battle(
			library,
			library.content.contracts.battles,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	if library.content.contracts.transport.types.any(func(kind): return kind == offer.type):
		return ContractEncounters.transport(
			library,
			library.content.contracts.transport,
			offer,
			level,
			Contracts.encounter_seed(root_seed, reference)
		)
	return ContractEncounters.hunt(
		library,
		library.content.contracts.hunt,
		offer,
		level,
		Contracts.encounter_seed(root_seed, reference)
	)


func begin_contract(index: int) -> bool:
	if not docked or not exploration_unlocked() or not active_job.is_empty():
		error = "Contracts are available at stations after completing or skipping the campaign."
		return false
	var reference := contract_reference(index)
	var definition := build_contract(reference, rank(), market_seed)
	if definition.is_empty() or contract_paid(reference):
		error = "This contract is unavailable."
		return false
	if definition.success.kind != "route_finished" and loadout.weapons().is_empty():
		error = "Fit a weapon before accepting this contract."
		return false
	remember_checkpoint("station")
	_contract_definition = definition
	active_job = Mission.create(
		definition,
		chapter,
		station_id,
		library,
		Contracts.encounter_seed(market_seed, reference),
		rank(),
		"contract"
	)
	active_job["contract"] = reference
	briefing_page = -1
	motion = Motion.create()
	combat = Combat.create()
	docked = false
	flight_position = Vector3.ZERO
	flight_rotation = Vector3.ZERO
	remember_checkpoint("departure")
	return true


func begin_patrol() -> bool:
	error = "Choose a contract from the station board."
	return false


func depart() -> bool:
	if not docked:
		return false
	if not exploration_unlocked():
		return begin_mission()
	remember_checkpoint("station")
	motion = Motion.create()
	docked = false
	remember_checkpoint("departure")
	return true


func arrive(destination: int) -> bool:
	if destination < 0 or destination >= library.stations.size():
		return false
	var success := ready_to_finish()
	var terminal: bool = (
		success and active_job.get("kind") == "campaign" and terminal_chapter(chapter)
	)
	var expected: int = (
		(
			int(active_job.origin)
			if active_job.get("kind") == "contract"
			else library.chapter_destination(chapter)
		)
		if success
		else station_id
	)
	if active_job.get("kind") == "contract" and (not success or destination != expected):
		return false
	if (
		not exploration_unlocked()
		and (destination != expected or (not active_job.is_empty() and not success))
	):
		return false
	if not docked or destination != station_id:
		markets.clear()
		market_generation += 1
	station_id = destination
	docked = true
	motion = Motion.create()
	combat = Combat.create()
	hull = max_hull()
	shield = max_shield()
	if not visited.has(destination):
		visited.append(destination)
	if success and destination == expected:
		statistics.kills += int(active_job.kills)
		var client_race := int(library.content.travel.campaign_race)
		if active_job.kind == "contract":
			client_race = int(
				Contracts.reference_offer(library, market_seed, active_job.contract).client.race
			)
		var selection := Recovery.mode(
			library.content.recovery, active_job.kind == "campaign", chapter, int(active_job.kills)
		)
		recovery = Recovery.generate(
			library.content.recovery,
			cargo_capacity() - cargo_used(),
			selection,
			int(active_job.seed) ^ 0x524543
		)
		for item in recovery.items:
			var key := str(int(item.id))
			cargo[key] = int(cargo.get(key, 0)) + int(item.amount)
		rating = Travel.after_mission(library.content.travel, rating, client_race)
		if active_job.kind == "campaign":
			var payment := mission_reward()
			credits += payment
			progression.rewards.append(payment)
			chapter += 1
			if terminal:
				campaign_state = "completed"
		elif active_job.kind == "contract":
			var payment := mission_reward()
			credits += payment
			var receipt := {"reference": active_job.contract.duplicate(true), "payment": payment}
			if mission_definition().get("payout_kind") == "finished_asteroids":
				receipt["units"] = Mission.Scenery.destroyed(active_job.scenery)
			contract_rewards.append(receipt)
		active_job = {}
		_contract_definition = {}
	return true


func mission_reward() -> int:
	if active_job.get("kind") == "contract":
		var rate := int(Contracts.reference_offer(library, market_seed, active_job.contract).reward)
		if mission_definition().get("payout_kind") == "finished_asteroids":
			return rate * Mission.Scenery.destroyed(active_job.scenery)
		return rate
	if active_job.get("kind") != "campaign":
		return 0
	var definition: Dictionary = mission_definition()
	var multiplier := 1
	if definition.has("reward_rule"):
		multiplier = int(definition.reward_rule.offset)
		for actor in active_job.actors:
			if actor.hp > 0 and not Mission.enemy(definition, actor):
				multiplier += 1
	return int(library.content.chapters[chapter].reward) * maxi(0, multiplier)


func finish_mission() -> bool:
	if docked or not mission_available() or not ready_to_finish():
		return false
	return arrive(
		(
			int(active_job.origin)
			if active_job.get("kind") == "contract"
			else library.chapter_destination(chapter)
		)
	)


func ready_to_finish() -> bool:
	return (
		hull > 0
		and active_job.get("ready", false)
		and active_job.get("kind") in ["campaign", "contract"]
		and not active_job.get("failed", false)
		and Mission.Radio.finished(mission_definition(), active_job)
	)


func travel(destination: int) -> bool:
	if (
		not docked
		or not exploration_unlocked()
		or destination == station_id
		or not active_job.is_empty()
	):
		return false
	var fare := travel_quote(destination)
	if fare.is_empty() or credits < fare.total or not arrive(destination):
		return false
	credits -= int(fare.total)
	if fare.bribe > 0:
		rating = Travel.after_bribe(library.content.travel, rating)
	return true


func travel_quote(destination: int) -> Dictionary:
	return Travel.quote(library, station_id, destination, rating, visited.size())


func trade(item: int, buying: bool) -> bool:
	if buying:
		var offers := market_offers()
		for index in offers.size():
			if (
				offers[index].kind != "ship"
				and int(offers[index].id) == item
				and int(offers[index].count) > 0
			):
				return buy_offer(index)
		return false
	return sell_cargo(item)


func market_offers() -> Array:
	if not docked:
		return []
	var key := "%s:%d:%d" % [campaign_state, station_id, chapter]
	if not markets.has(key):
		var seed_value := market_seed ^ (station_id * 73856093) ^ (market_generation * 19349663)
		markets[key] = Market.generate(
			library, station_id, chapter, not exploration_unlocked(), seed_value
		)
	return markets[key]


func ship_offer_quote(index: int) -> Dictionary:
	var offers := market_offers()
	if not docked or index < 0 or index >= offers.size():
		error = "This offer is no longer available."
		return {}
	var offer: Dictionary = offers[index]
	if offer.kind != "ship" or int(offer.count) <= 0:
		error = "This ship is no longer available."
		return {}
	var transfer := loadout.ship_exchange(int(offer.id), cargo_used() - loadout.hold.size())
	var reason := ""
	if int(offer.id) == ship_id:
		reason = "You already fly this ship model."
	elif credits + ship_value < int(offer.price):
		reason = "Not enough credits after trading in your ship."
	elif transfer.is_empty():
		reason = loadout.error
	error = reason
	return {
		"index": index,
		"offer": {"id": int(offer.id), "price": int(offer.price)},
		"current_ship": ship_id,
		"trade_in": ship_value,
		"credits": credits,
		"remaining": credits + ship_value - int(offer.price),
		"cargo": cargo.duplicate(true),
		"loadout": loadout.capture(),
		"transfer": transfer,
		"allowed": reason.is_empty(),
		"reason": reason
	}


func buy_ship_quote(reviewed: Dictionary) -> bool:
	# The quote is a review snapshot, never an authority to set inventory or prices.
	var fresh := ship_offer_quote(int(reviewed.get("index", -1)))
	if fresh.is_empty():
		return false
	if fresh != reviewed:
		error = "The ship offer or your inventory changed. Review the exchange again."
		return false
	return buy_offer(int(fresh.index))


func buy_offer(index: int) -> bool:
	error = ""
	var offers := market_offers()
	if not docked or index < 0 or index >= offers.size() or int(offers[index].count) <= 0:
		error = "This offer is no longer available."
		return false
	var offer: Dictionary = offers[index]
	var price := int(offer.price)
	if offer.kind == "ship":
		var quote := ship_offer_quote(index)
		if quote.is_empty() or not quote.allowed:
			return false
		var transfer: Dictionary = quote.transfer
		credits = int(quote.remaining)
		ship_id = int(offer.id)
		ship_value = int(price * float(library.content.economy.ship_resale_factor))
		loadout.hold = transfer.hold
		loadout.fitted = transfer.fitted
		hull = max_hull()
	else:
		if credits < price:
			error = "Not enough credits."
			return false
		if cargo_used() >= cargo_capacity():
			error = "The cargo hold is full."
			return false
		credits -= price
		if offer.kind == "cargo":
			var key := str(int(offer.id))
			cargo[key] = int(cargo.get(key, 0)) + 1
		else:
			loadout.hold.append(
				{
					"id": int(offer.id),
					"value": int(price * float(library.content.economy.equipment_resale_factor))
				}
			)
	offer.count = int(offer.count) - 1
	refresh_loadout()
	return true


func sell_equipment(index: int) -> bool:
	if (
		not docked
		or not library.station_definition(station_id).shop
		or index < 0
		or index >= loadout.hold.size()
	):
		return false
	var record: Dictionary = loadout.hold[index]
	credits += int(record.value)
	Market.add_offer(market_offers(), "equipment", int(record.id), int(record.value))
	loadout.hold.remove_at(index)
	return true


func sell_cargo(item: int, amount: int = 1) -> bool:
	var key := str(item)
	if not docked or not library.station_definition(station_id).shop or amount <= 0 or amount > int(cargo.get(key, 0)):
		error = "The selected cargo quantity is unavailable."
		return false
	var price := Market.cargo_price(library, item, station_id)
	credits += price * amount
	cargo[key] = int(cargo[key]) - amount
	if cargo[key] == 0:
		cargo.erase(key)
	Market.add_offer(market_offers(), "cargo", item, price, amount)
	error = ""
	return true


func fit_equipment(index: int) -> bool:
	if not docked or not loadout.fit(index, ship_id):
		error = loadout.error
		return false
	refresh_loadout()
	return true


func remove_equipment(category: int) -> bool:
	if not docked or not loadout.unfit(category, cargo_capacity() - cargo_used()):
		error = loadout.error
		return false
	refresh_loadout()
	return true


func refresh_loadout() -> void:
	var weapons := loadout.primary_weapons()
	if not weapons.has(weapon_id):
		weapon_id = -1 if weapons.is_empty() else weapons[0]
	shield = max_shield() if docked else minf(shield, max_shield())


func cycle_weapon() -> void:
	var weapons := loadout.primary_weapons()
	if not weapons.is_empty():
		weapon_id = weapons[(weapons.find(weapon_id) + 1) % weapons.size()]


func capture() -> Dictionary:
	return {
		"schema": SCHEMA,
		"content_id": content_id,
		"slot": slot,
		"campaign_state": campaign_state,
		"chapter": chapter,
		"briefing_page": briefing_page,
		"progression": progression.duplicate(true),
		"statistics": statistics.duplicate(true),
		"contract_rewards": contract_rewards.duplicate(true),
		"recovery": recovery.duplicate(true),
		"docked": docked,
		"station_id": station_id,
		"credits": credits,
		"ship_id": ship_id,
		"weapon_id": weapon_id,
		"loadout": loadout.capture(),
		"ship_value": ship_value,
		"market_seed": market_seed,
		"market_generation": market_generation,
		"markets": markets.duplicate(true),
		"cargo": cargo.duplicate(true),
		"visited": visited.duplicate(),
		"rating": rating,
		"active_job": active_job.duplicate(true),
		"exploration": exploration.duplicate(true),
		"motion": motion.duplicate(true),
		"combat": combat.duplicate(true),
		"hull": hull,
		"shield": shield,
		"elapsed": elapsed,
		"position": [flight_position.x, flight_position.y, flight_position.z],
		"rotation": [flight_rotation.x, flight_rotation.y, flight_rotation.z]
	}


func restore(value: Variant) -> bool:
	error = ""
	var migrate_rating := false
	var migrate_fighter_motion := false
	if value is Dictionary and value.get("schema") == 2:
		value = migrate_preview(value)
	if value is Dictionary and value.get("schema") == 3:
		value = migrate_mission_preview(value)
	if value is Dictionary and value.get("schema") == 4:
		value = value.duplicate(true)
		value.schema = 6
		value.combat = Combat.create()
	if value is Dictionary and value.get("schema") == 5:
		value = migrate_projectile_speed(value)
	if value is Dictionary and value.get("schema") == 6:
		value = migrate_combat_participation(value)
	if value is Dictionary and value.get("schema") == 7:
		value = migrate_progression(value)
	if value is Dictionary and value.get("schema") == 8:
		value = value.duplicate(true)
		value.schema = 9
		value.contract_rewards = []
	if value is Dictionary and value.get("schema") == 9:
		value = value.duplicate(true)
		value.schema = 10
		value.briefing_page = -1
	if value is Dictionary and value.get("schema") == 10:
		value = value.duplicate(true)
		value.schema = 11
		value.motion = Motion.create()
	if value is Dictionary and value.get("schema") == 11:
		value = migrate_opening_encounter(value)
	if value is Dictionary and value.get("schema") == 12:
		value = value.duplicate(true)
		value.schema = 13
		if value.get("active_job") is Dictionary:
			var job: Dictionary = value.active_job
			var config: Dictionary = library.content.flight_ui.tutorial
			if Mission.Tutorial.applies(config, job):
				if not job.get("radio") is Dictionary or not job.radio.get("shown") is Array:
					return false
				job.tutorial = Mission.Tutorial.create(config, job.radio.shown, true)
	if value is Dictionary and value.get("schema") == 13:
		value = value.duplicate(true)
		value.schema = 14
		value.rating = int(library.content.travel.initial_rating)
		migrate_rating = true
	if value is Dictionary and value.get("schema") == 14:
		value = migrate_mines(value)
	if value is Dictionary and value.get("schema") == 15:
		value = migrate_asteroids(value)
	if value is Dictionary and value.get("schema") == 16:
		value = value.duplicate(true)
		value.schema = 17
		value.recovery = {}
	if value is Dictionary and value.get("schema") == 17:
		value = value.duplicate(true)
		value.combat = PlayerArmament.migrate_combat(value.get("combat"), library)
		value.schema = 18

	if value is Dictionary and value.get("schema") == 18:
		value = value.duplicate(true)
		value.schema = 19
		value.exploration = {}

	if value is Dictionary and value.get("schema") == 19:
		value = value.duplicate(true)
		value.schema = 20
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Destruction.migrate_actors(value.active_job.get("actors")):
				error = "Invalid legacy actor destruction state."
				return false

	if value is Dictionary and value.get("schema") == 20:
		value = value.duplicate(true)
		value.schema = 21
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Destruction.migrate_motion(value.active_job.get("actors")):
				error = "Invalid legacy actor momentum."
				return false

	if value is Dictionary and value.get("schema") == 21:
		value = value.duplicate(true)
		value.schema = 22
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Evasion.migrate(value.active_job.get("actors")):
				error = "Invalid legacy fighter maneuver state."
				return false

	if value is Dictionary and value.get("schema") == 22:
		value = value.duplicate(true)
		value.schema = 23
		migrate_fighter_motion = true

	if value is Dictionary and value.get("schema") == 23:
		value = value.duplicate(true)
		value.schema = 24
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Frame.migrate(value.active_job.get("actors")):
				error = "Invalid legacy fighter orientation."
				return false

	if value is Dictionary and value.get("schema") == 24:
		value = value.duplicate(true)
		value.schema = 25
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Impact.migrate(value.active_job.get("actors")):
				error = "Invalid legacy fighter impact state."
				return false

	if value is Dictionary and value.get("schema") == 25:
		value = value.duplicate(true)
		value.schema = 26
		if value.get("active_job") is Dictionary and not value.active_job.is_empty():
			if not Mission.Targeting.migrate(value.active_job.get("actors")):
				error = "Invalid legacy fighter targeting state."
				return false

	if value is Dictionary and value.get("schema") == 26:
		value = value.duplicate(true)
		value.schema = 27
		# Old mission timers are not lifetime play time, and old receipts lack kills.
		value.statistics = PilotStatistics.create(true)
	if value is Dictionary and value.get("schema") == 27:
		value = value.duplicate(true)
		value.schema = 28
		if value.get("motion") is Dictionary:
			value.motion.contact_elapsed = 0.0

	if value is Dictionary and value.get("schema") == 28:
		value = value.duplicate(true)
		value.schema = 29
		if value.get("motion") is Dictionary:
			value.motion.turn = [0.0, 0.0]

	if (
		not value is Dictionary
		or value.get("schema") != SCHEMA
		or value.get("content_id") != content_id
	):
		error = "This save does not match the installed content."
		return false
	if not PilotStatistics.valid(value.get("statistics")):
		error = "Invalid saved pilot statistics."
		return false
	if (
		not Travel.integer(value.get("rating"))
		or value.rating < library.content.travel.rating_min
		or value.rating > library.content.travel.rating_max
	):
		error = "Invalid saved faction rating."
		return false
	if not Motion.valid(value.get("motion"), library.content.player_motion):
		error = "Invalid saved player movement."
		return false
	if not value.has_all(
		[
			"slot",
			"campaign_state",
			"chapter",
			"progression",
			"briefing_page",
			"contract_rewards",
			"docked",
			"station_id",
			"credits",
			"ship_id",
			"weapon_id",
			"cargo",
			"visited",
			"active_job",
			"combat",
			"hull",
			"shield",
			"elapsed",
			"position",
			"rotation",
			"loadout",
			"ship_value",
			"market_seed",
			"market_generation",
			"markets"
		]
	):
		error = "Incomplete save."
		return false
	if (
		not value.get("recovery") is Dictionary
		or (
			not value.recovery.is_empty()
			and not Recovery.valid_result(value.recovery, library.content.recovery)
		)
	):
		error = "Invalid cargo recovery receipt."
		return false
	if not ExplorationArea.valid(library, value.get("exploration")):
		error = "Invalid saved exploration field."
		return false
	if not value.active_job is Dictionary:
		error = "Invalid mission structure."
		return false
	if (
		value.campaign_state not in ["active", "skipped", "completed"]
		or value.slot not in ["campaign", "free"]
	):
		error = "Invalid campaign state."
		return false
	for field in [
		"chapter",
		"station_id",
		"credits",
		"ship_id",
		"ship_value",
		"market_seed",
		"market_generation"
	]:
		if not number(value[field]) or value[field] < 0 or int(value[field]) != value[field]:
			error = "Invalid save field: " + field
			return false
	if not Loadout.integer(value.weapon_id) or value.weapon_id < -1:
		error = "Invalid weapon reference."
		return false
	if value.chapter > library.playable_chapter_count():
		error = "This preview cannot load a later campaign save."
		return false
	if not Progression.valid(value.progression, int(value.chapter), library):
		error = "Invalid earned-worth history."
		return false
	if (
		(
			value.campaign_state == "completed"
			and (
				not terminal_chapter(int(value.chapter) - 1)
				or value.progression.rewards.is_empty()
				or value.slot != "campaign"
				or (not value.active_job.is_empty() and value.active_job.get("kind") != "contract")
			)
		)
		or (
			value.campaign_state != "completed" and value.chapter >= library.content.chapters.size()
		)
		or (value.campaign_state == "skipped" and value.slot != "free")
		or (value.campaign_state == "active" and value.slot != "campaign")
	):
		error = "Campaign state and recorded completion disagree."
		return false
	if not Loadout.integer(value.briefing_page) or value.briefing_page < -1:
		error = "Invalid briefing page."
		return false
	if (
		value.briefing_page >= 0
		and (
			value.campaign_state != "active"
			or not value.docked
			or not value.active_job.is_empty()
			or library.briefing_cue(int(value.chapter), int(value.briefing_page)).is_empty()
		)
	):
		error = "Briefing does not match the docked campaign pilot."
		return false
	if (
		not Contracts.valid_receipts(
			library, int(value.market_seed), value.contract_rewards, int(value.market_generation)
		)
		or (value.campaign_state == "active" and not value.contract_rewards.is_empty())
	):
		error = "Invalid freelance payment history."
		return false
	var expected_status := Progression.status(value.progression, library)
	for receipt in value.contract_rewards:
		Progression.apply_reward(expected_status, int(receipt.payment), library)
	var expected_rank := int(expected_status.level)
	if (
		value.station_id >= library.stations.size()
		or value.ship_id >= library.ships.size()
		or value.weapon_id >= library.items.size()
	):
		error = "Invalid catalogue reference."
		return false
	if (
		not value.docked is bool
		or not value.cargo is Dictionary
		or not value.visited is Array
		or not value.active_job is Dictionary
	):
		error = "Invalid save structure."
		return false
	for key in ["hull", "shield", "elapsed"]:
		if not number(value[key]) or value[key] < 0:
			error = "Invalid flight state."
			return false
	for key in ["position", "rotation"]:
		if not value[key] is Array or value[key].size() != 3:
			error = "Invalid coordinates."
			return false
		for c in value[key]:
			if not number(c) or absf(c) > 1e8:
				error = "Invalid coordinates."
				return false
	var total := 0
	for key in value.cargo:
		if (
			not key is String
			or not key.is_valid_int()
			or int(key) < 0
			or int(key) >= library.items.size()
			or not number(value.cargo[key])
			or value.cargo[key] < 0
			or value.cargo[key] != int(value.cargo[key])
		):
			error = "Invalid cargo."
			return false
		if int(library.items[int(key)][1]) != library.CARGO_CATEGORY:
			error = "Invalid cargo category."
			return false
		total += int(value.cargo[key])
	if total > int(library.ships[int(value.ship_id)][5]):
		error = "Cargo exceeds capacity."
		return false
	var candidate := Loadout.new()
	candidate.configure(library)
	if not candidate.restore(value.loadout, int(value.ship_id), total):
		error = candidate.error
		return false
	var weapons := candidate.primary_weapons()
	if (
		(not weapons.has(int(value.weapon_id)) if not weapons.is_empty() else value.weapon_id != -1)
		or value.hull > int(library.ships[int(value.ship_id)][4])
		or value.shield > candidate.shield_capacity()
	):
		error = "Equipment and ship state disagree."
		return false
	if (
		not valid_markets(value.markets)
		or value.ship_value > int(library.ships[int(value.ship_id)][6])
	):
		error = "Invalid saved market state."
		return false
	var seen_stations := {}
	for sid in value.visited:
		if (
			not number(sid)
			or sid < 0
			or sid >= library.stations.size()
			or sid != int(sid)
			or seen_stations.has(int(sid))
		):
			error = "Invalid visited station."
			return false
		seen_stations[int(sid)] = true
	if value.campaign_state == "active" and not value.exploration.is_empty():
		error = "Exploration fields cannot precede campaign completion or skipping."
		return false
	for key in value.exploration:
		if not seen_stations.has(int(key)):
			error = "Saved exploration field belongs to an unvisited station."
			return false
	var definition: Dictionary = library.mission_definition(int(value.chapter))
	var contract: bool = value.active_job.get("kind") == "contract"
	if contract:
		definition = build_contract(
			value.active_job.get("contract"), expected_rank, int(value.market_seed)
		)
		if (
			value.campaign_state == "active"
			or definition.is_empty()
			or value.active_job.contract.station != value.station_id
			or value.active_job.contract.visit != value.market_generation
		):
			error = "Invalid active contract reference."
			return false
		for receipt in value.contract_rewards:
			if (
				Contracts.reference_key(receipt.reference)
				== Contracts.reference_key(value.active_job.contract)
			):
				error = "This contract was already paid."
				return false
		if (
			value.active_job.get("seed")
			!= Contracts.encounter_seed(int(value.market_seed), value.active_job.contract)
		):
			error = "Contract encounter seed does not match its offer."
			return false
	if not value.active_job.get("actors", []) is Array:
		error = "Invalid saved actor list."
		return false
	if migrate_fighter_motion and not value.active_job.is_empty():
		if (
			definition.is_empty()
			or not Mission.FighterMotion.migrate(
				value.active_job.actors, library.content.fighter_motion, definition.groups
			)
		):
			error = "Invalid legacy fighter speed state."
			return false

	var combat_profiles: Dictionary = (
		library.definition_weapons(definition, expected_rank)
		if not value.active_job.is_empty()
		else {}
	)
	combat_profiles.merge(
		PlayerArmament.profiles(library, range(value.active_job.get("actors", []).size()))
	)
	if (
		not Combat.valid(value.combat, library, combat_profiles)
		or (
			value.docked
			and (not value.combat.projectiles.is_empty() or not value.combat.cooldowns.is_empty())
		)
	):
		error = "Invalid projectile or weapon cooldown state."
		return false
	if not value.active_job.is_empty():
		if (
			definition.is_empty()
			or (
				Mission.Tutorial.applies(library.content.flight_ui.tutorial, value.active_job)
				and not value.active_job.has("tutorial")
			)
			or (
				not contract
				and (
					not library.mission_playable(int(value.chapter))
					or value.campaign_state != "active"
				)
			)
			or value.docked
			or value.active_job.get("rank") != expected_rank
			or not Mission.valid(
				definition,
				value.active_job,
				int(value.chapter),
				int(value.station_id),
				library,
				"contract" if contract else "campaign",
				expected_rank
			)
		):
			error = "Invalid mission state."
			return false

	if migrate_rating:
		# Older previews recorded receipts but had no faction state or paid bribes.
		# Restore only known completed jobs; do not invent unrecorded legacy history.
		for payment in value.progression.rewards:
			value.rating = Travel.after_mission(
				library.content.travel, int(value.rating), int(library.content.travel.campaign_race)
			)
		for receipt in value.contract_rewards:
			var offer := Contracts.reference_offer(
				library, int(value.market_seed), receipt.reference
			)
			value.rating = Travel.after_mission(
				library.content.travel, int(value.rating), int(offer.client.race)
			)

	# Old previews saved a character-count timer. Preserve the displayed cue and
	# elapsed progress, but do not carry an excessive old reading delay forward.
	if not value.active_job.is_empty() and not value.active_job.radio.has("delay"):
		value = value.duplicate(true)
		value.active_job.radio.delay = 0.0
		var current := int(value.active_job.radio.current)
		if current >= 0:
			var cue: Dictionary = definition.radio[current]
			value.active_job.radio.remaining = minf(
				value.active_job.radio.remaining, library.radio_duration(cue)
			)

	for key in [
		"slot",
		"campaign_state",
		"chapter",
		"docked",
		"station_id",
		"credits",
		"ship_id",
		"weapon_id",
		"cargo",
		"visited",
		"active_job",
		"hull",
		"shield",
		"elapsed",
		"ship_value",
		"market_seed",
		"market_generation"
	]:
		set(key, value[key])
	statistics = value.statistics.duplicate(true)
	statistics.kills = int(statistics.kills)
	rating = int(value.rating)
	briefing_page = int(value.briefing_page)
	contract_rewards = value.contract_rewards.duplicate(true)
	recovery = value.recovery.duplicate(true)
	_contract_definition = definition if contract else {}
	progression = value.progression.duplicate(true)
	progression.legacy_through = int(progression.legacy_through)
	progression.rewards = progression.rewards.map(func(amount): return int(amount))
	active_job = value.active_job.duplicate(true)
	exploration = value.exploration.duplicate(true)
	motion = value.motion.duplicate(true)
	combat = Combat.normalize(value.combat)
	if not active_job.is_empty():
		active_job.radio.shown = active_job.radio.shown.map(func(index): return int(index))
	loadout = candidate
	markets = value.markets.duplicate(true)
	for offers in markets.values():
		for offer in offers:
			for field in ["id", "price", "count"]:
				offer[field] = int(offer[field])
	visited = value.visited.map(func(id): return int(id))
	cargo = value.cargo.duplicate(true)
	for key in cargo:
		cargo[key] = int(cargo[key])
	chapter = int(chapter)
	station_id = int(station_id)
	credits = int(credits)
	ship_id = int(ship_id)
	weapon_id = int(weapon_id)
	flight_position = Vector3(value.position[0], value.position[1], value.position[2])
	flight_rotation = Vector3(value.rotation[0], value.rotation[1], value.rotation[2])
	checkpoints = {}
	if value.get("checkpoints") is Dictionary:
		for key in ["station", "departure"]:
			var point: Variant = value.checkpoints.get(key)
			if point is Dictionary and not point.has("checkpoints"):
				checkpoints[key] = point.duplicate(true)
	return true


func valid_markets(value: Variant) -> bool:
	if not value is Dictionary or value.size() > library.stations.size():
		return false
	for key in value:
		if not key is String or not value[key] is Array or value[key].size() > 4096:
			return false
		for offer in value[key]:
			if (
				not offer is Dictionary
				or not offer.has_all(["kind", "id", "price", "count"])
				or offer.kind not in ["ship", "equipment", "cargo"]
			):
				return false
			for field in ["id", "price", "count"]:
				if not Loadout.integer(offer[field]) or offer[field] < 0:
					return false
			var table: Array = library.ships if offer.kind == "ship" else library.items
			if offer.id >= table.size() or offer.price > int(table[int(offer.id)][6]):
				return false
			if (
				offer.kind != "ship"
				and (
					(int(table[int(offer.id)][1]) == library.CARGO_CATEGORY)
					!= (offer.kind == "cargo")
				)
			):
				return false
	return true


func migrate_projectile_speed(value: Dictionary) -> Variant:
	# Preview 0.8 used the scripted gun's projectile-pool count as speed.
	# Correct only that recognized old magnitude, preserving direction, time,
	# cooldowns and mission state. Full validation still rejects other damage.
	if (
		not Combat.integer(value.get("chapter"))
		or value.chapter < 0
		or value.chapter >= library.content.chapters.size()
		or not value.get("combat") is Dictionary
		or not value.combat.get("projectiles") is Array
	):
		return null
	var migrated := value.duplicate(true)
	migrated.schema = 6
	var profiles: Dictionary = library.actor_weapons(int(value.chapter))
	for shot in migrated.combat.projectiles:
		if (
			not shot is Dictionary
			or not Combat.integer(shot.get("weapon"))
			or not Combat.valid_vector(shot.get("velocity"))
		):
			return null
		var profile: Dictionary = profiles.get(int(shot.weapon), {})
		if not profile.has("pool_capacity"):
			continue
		var velocity := Combat.vector(shot.velocity)
		if is_equal_approx(velocity.length(), float(profile.pool_capacity) * 20):
			shot.velocity = Combat.packed(velocity.normalized() * float(profile.speed))
	return migrated


func migrate_preview(value: Dictionary) -> Variant:
	# Older preview saves only had the imported starting weapon. Preserve their
	# earned money and chapter; construct the new inventory without a bonus.
	if (
		not Loadout.integer(value.get("weapon_id"))
		or value.weapon_id < 0
		or value.weapon_id >= library.items.size()
		or not Loadout.integer(value.get("ship_id"))
		or value.ship_id < 0
		or value.ship_id >= library.ships.size()
	):
		return null
	if int(library.items[int(value.weapon_id)][1]) >= library.SHIELD_CATEGORY:
		return null
	var migrated := value.duplicate(true)
	var initial := Loadout.new()
	initial.configure(library, int(value.weapon_id))
	migrated.schema = 3
	migrated.loadout = initial.capture()
	migrated.ship_value = int(
		(
			int(library.ships[int(value.ship_id)][6])
			* float(library.content.economy.ship_resale_factor)
		)
	)
	migrated.market_seed = library.id.hash() & 0x7fffffff
	migrated.market_generation = 0
	migrated.markets = {}
	return migrated


func migrate_mission_preview(value: Dictionary) -> Variant:
	var migrated := value.duplicate(true)
	migrated.schema = 4
	if not value.get("active_job") is Dictionary:
		return null
	if value.active_job.is_empty():
		return migrated
	var old: Dictionary = value.active_job
	if (
		value.get("chapter") != 0
		or old.get("kind") != "training"
		or not old.has_all(["stage", "kills", "target", "ready", "origin"])
	):
		return null
	var definition: Dictionary = library.mission_definition(0)
	var expected := int(definition.groups[0].count)
	if (
		not Mission.integer(old.stage)
		or old.stage < 0
		or old.stage > definition.route.size()
		or not Mission.integer(old.kills)
		or old.kills < 0
		or old.kills > expected
		or old.target != expected
		or old.ready != (old.kills == expected)
	):
		return null
	if old.kills > 0 and old.stage != definition.route.size():
		return null
	if not Mission.integer(old.origin) or old.origin != value.get("station_id"):
		return null
	var job := Mission.create(
		definition, 0, int(old.origin), library, int(value.get("market_seed", 0))
	)
	job.stage = int(old.stage)
	for index in int(old.kills):
		job.actors[index].awake = true
		Mission.damage(definition, job, index, float(job.actors[index].hp))
	migrated.active_job = job
	return migrated


func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func save(path: String) -> bool:
	error = ""
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		error = "Could not write save."
		return false
	if docked and can_retry(): remember_checkpoint("station")
	var payload := capture()
	payload["checkpoints"] = checkpoints.duplicate(true)
	f.store_string(JSON.stringify(payload))
	f.flush()
	f.close()
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		error = "Could not preserve the previous save."
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not finish save."
		return false
	return true


func remember_checkpoint(kind: String) -> void:
	if slot == "survival" or not can_retry(): return
	if kind == "station": checkpoints.erase("departure")
	checkpoints[kind] = capture()


func checkpoint_candidate(kind: String):
	if kind not in ["station", "departure"]: return null
	var value: Variant = checkpoints.get(kind)
	if not value is Dictionary or value.get("slot") != slot or value.has("checkpoints"): return null
	var candidate = get_script().new()
	candidate.configure(library, slot == "free")
	if not candidate.restore(value) or not candidate.can_retry(): return null
	if candidate.docked != (kind == "station"): return null
	# Retain station recovery on a mission restart; discard later flight history.
	for key in ["station", "departure"] if kind == "departure" else ["station"]:
		if checkpoints.has(key): candidate.checkpoints[key] = checkpoints[key].duplicate(true)
	return candidate


func can_retry() -> bool:
	return hull > 0 and not active_job.get("failed", false)


func load_retry(path: String) -> bool:
	# Native saves can resume flight as well as the source game's station state.
	# Older builds could write a defeated pilot; try the preserved backup too.
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(path + suffix) and restore(parse_json(path + suffix)) and can_retry():
			return true
	error = "No usable saved game is available."
	return false


func load_save(path: String) -> bool:
	if not FileAccess.file_exists(path):
		error = "No save exists in this slot."
		return false
	if restore(parse_json(path)):
		return true
	var original := error
	if FileAccess.file_exists(path + ".bak") and restore(parse_json(path + ".bak")):
		return true
	error = original
	return false


func parse_json(path: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return parser.data


func migrate_combat_participation(value: Dictionary) -> Variant:
	var migrated := value.duplicate(true)
	migrated.schema = 7
	if not Mission.integer(value.get("chapter")) or not value.get("active_job") is Dictionary:
		return migrated
	var definition: Dictionary = library.mission_definition(int(value.chapter))
	var job: Dictionary = migrated.active_job
	if definition.is_empty() or not job.get("actors") is Array:
		return migrated
	var expected := 0
	for group in definition.groups:
		expected += int(group.count)
	if job.actors.size() != expected:
		return migrated
	var index := 0
	var old_target := 0
	var kills := 0
	var old_kills := 0
	for group in definition.groups:
		for ordinal in int(group.count):
			var actor: Variant = job.actors[index]
			if (
				not actor is Dictionary
				or not Mission.numeric(actor.get("hp"))
				or actor.hp < 0
				or actor.hp > library.group_initial_hull(group)
				or not actor.get("awake") is bool
			):
				return null
			if group.get("team", "enemy") == "enemy" and actor.hp <= 0:
				old_kills += 1
			if not group.get("combat_active", true):
				# Earlier previews treated a non-participating hull as a sleeping,
				# destructible enemy. Restore its display state without replaying combat.
				actor.hp = library.group_initial_hull(group)
				actor.awake = true
			if group.get("team", "enemy") == "enemy":
				old_target += 1
				if actor.hp <= 0:
					kills += 1
			index += 1
	if job.get("kills") != old_kills or job.get("target") != old_target:
		return null
	if definition.has("enemy_goal"):
		job.target = int(definition.enemy_goal)
	job.kills = kills
	return migrated


func progress_status() -> Dictionary:
	var result := Progression.status(progression, library)
	for receipt in contract_rewards:
		Progression.apply_reward(result, int(receipt.payment), library)
	return result


func rank() -> int:
	return int(progress_status().level)


func earned_worth() -> int:
	return int(progress_status().worth)


func migrate_progression(value: Dictionary) -> Variant:
	if (
		not Progression.integer(value.get("chapter"))
		or value.chapter < 0
		or value.chapter > library.content.chapters.size()
		or not value.get("active_job") is Dictionary
	):
		return null
	var migrated := value.duplicate(true)
	migrated.schema = 8
	migrated.progression = Progression.create(int(value.chapter))
	if not migrated.active_job.is_empty():
		migrated.active_job.rank = int(Progression.status(migrated.progression, library).level)
	return migrated


func begin_briefing() -> bool:
	if (
		not docked
		or campaign_state != "active"
		or not active_job.is_empty()
		or not mission_available()
	):
		return false
	if briefing_page < 0:
		briefing_page = 0
	return true


func next_briefing_page() -> bool:
	if briefing_page < 0 or not docked or campaign_state != "active":
		return false
	if briefing_page + 1 < library.content.chapters[chapter].dialogue.size():
		briefing_page += 1
		return true
	return begin_mission()


func previous_briefing_page() -> void:
	if briefing_page >= 0 and docked:
		briefing_page -= 1


func migrate_opening_encounter(value: Dictionary) -> Variant:
	var migrated := value.duplicate(true)
	migrated.schema = 12
	if (
		value.get("chapter") != 0
		or not value.get("active_job") is Dictionary
		or value.active_job.is_empty()
	):
		return migrated
	var job: Dictionary = migrated.active_job
	var definition: Dictionary = library.mission_definition(0)
	if (
		not job.get("actors") is Array
		or not Mission.integer(job.get("rank"))
		or not Mission.integer(job.get("origin"))
	):
		return null
	# Older schema migrations already construct the current encounter shape.
	if Mission.valid(definition, job, 0, int(job.origin), library):
		return migrated
	var legacy := definition.duplicate(true)
	legacy.groups = [
		{
			"count": definition.groups[0].count,
			"actor": definition.groups[0].actor,
			"center": definition.groups[0].center,
			"scatter": [],
			"after_route": true
		}
	]
	legacy.erase("scenery")
	legacy.erase("fog")
	# This schema predates destruction clocks. Validate a normalized copy rather
	# than requiring fields that its later schema migration has not added yet.
	var validation := job.duplicate(true)
	if not Mission.Destruction.migrate_actors(validation.actors):
		return null
	if not Mission.valid(legacy, validation, 0, int(job.origin), library):
		return null
	var current := Mission.create(
		definition, 0, int(job.origin), library, int(job.seed), int(job.rank)
	)
	var old_max: float = library.group_initial_hull(legacy.groups[0], int(job.rank))
	var new_max: float = library.group_initial_hull(definition.groups[0], int(job.rank))
	for index in job.actors.size():
		var old: Dictionary = job.actors[index]
		var actor: Dictionary = current.actors[index]
		# Keep positions, damage already dealt and destroyed targets. Newly imported
		# rank hull applies only to remaining hull; migration never resurrects kills.
		actor.position = old.position.duplicate()
		actor.hp = 0.0 if old.hp == 0 else maxf(.001, new_max - (old_max - float(old.hp)))
		actor.destruction = Mission.Destruction.create(actor.hp > 0)
		actor.fighter_motion.hull_seen = actor.hp
		actor.awake = int(job.stage) == definition.route.size()
	job.actors = current.actors
	job.scenery = current.scenery
	# The companion did not exist in the preview. Introduce it beside the saved
	# pilot on the same route stage, without changing player motion or radio.
	var companion: Dictionary = job.actors.back()
	if Combat.valid_vector(value.get("position", [])):
		companion.position = Combat.packed(
			Combat.vector(value.position) + Mission.point(definition.groups.back().center)
		)
	companion.route_stage = int(job.stage)
	return migrated


func migrate_mines(value: Dictionary) -> Variant:
	# Existing cleared mines stay cleared. Surviving mines gain their native
	# lifecycle without moving actors, replacing the encounter or granting credit.
	var result := value.duplicate(true)
	result.schema = 15
	var job: Variant = result.get("active_job")
	if not job is Dictionary or job.is_empty():
		return result
	var definition := {}
	if job.get("kind") == "campaign" and Mission.integer(job.get("chapter")):
		definition = library.mission_definition(int(job.chapter))
	if definition.is_empty():
		return result
	if not job.get("actors") is Array:
		return result
	for actor in job.actors:
		if not actor is Dictionary or not Mission.integer(actor.get("group")):
			return result
		var group := int(actor.group)
		if group < 0 or group >= definition.groups.size():
			return result
		if int(definition.groups[group].actor) != int(library.content.mine_behavior.actor):
			continue
		if actor.has("mine") or not Mission.numeric(actor.get("hp")):
			return null
		actor.mine = Mission.Mines.create()
		if actor.hp <= 0:
			actor.mine.phase = "dead"
	return result


func migrate_asteroids(value: Dictionary) -> Variant:
	var result := value.duplicate(true)
	result.schema = 16
	var job: Variant = result.get("active_job")
	if not job is Dictionary or job.is_empty():
		return result
	var scenery: Variant = job.get("scenery")
	if not scenery is Dictionary or not scenery.get("rocks") is Array:
		return result
	for rock in scenery.rocks:
		if not rock is Dictionary or not Combat.integer(rock.get("hits")):
			return null
		# Older migrations may already have created today's native state.
		if rock.has("destruction_ms") or rock.has("destroyed"):
			if not rock.has_all(["destruction_ms", "destroyed"]):
				return null
			continue
		rock.destruction_ms = 0.0
		rock.destroyed = rock.hits == 0
	return result


func acknowledge_recovery() -> void:
	# Cargo was granted atomically with mission settlement. Dismissing or
	# reloading this informational receipt cannot grant it a second time.
	recovery = {}


func exploration_area() -> Dictionary:
	if not exploration_unlocked() or not active_job.is_empty():
		return {}
	var key := str(station_id)
	if not exploration.has(key):
		exploration[key] = ExplorationArea.create(library, station_id)
	return exploration[key]


func field_definition() -> Dictionary:
	return (
		mission_definition() if not active_job.is_empty() else ExplorationArea.definition(library)
	)


func field_state() -> Dictionary:
	if not active_job.is_empty():
		return active_job.get("scenery", {})
	var area := exploration_area()
	return area.get("scenery", {})
