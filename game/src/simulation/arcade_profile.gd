extends RefCounted
## Local arcade records and run identities, independent from campaign progress.
const Combat = preload("res://src/simulation/combat.gd")
const SCHEMA := 2
const MAX_ID := 9007199254740991
var content_id := ""
var rules := {}
var ship_count := 0
var state := {}
var error := ""


func configure(identity: String, parameters: Dictionary, ships: int) -> bool:
	if identity.is_empty() or not valid_rules(parameters) or ships < 1 or ships > 128:
		error = "Unsupported arcade profile declarations."
		return false
	content_id = identity
	rules = parameters.duplicate(true)
	ship_count = ships
	state = {
		"serial": 0,
		"pending": 0,
		"next_ship_cycle": 0,
		"points": int(rules.points_initial),
		"entries": []
	}
	for index in int(rules.count):
		state.entries.append(
			{"name": rules.initial_name, "score": int(rules.initial_score), "run": 0}
		)
	error = ""
	return true


static func valid_rules(value: Variant) -> bool:
	if (
		not value is Dictionary
		or value.get("ties") != "after"
		or value.get("points_qualified_only") != true
	):
		return false
	for key in [
		"type", "count", "initial_score", "initial_wave", "minimum_result_score", "points_initial"
	]:
		if not Combat.integer(value.get(key)) or value[key] < 0 or value[key] > MAX_ID:
			return false
	return (
		value.count > 0
		and value.count <= 128
		and value.minimum_result_score > value.initial_score
		and valid_name(value.get("initial_name"))
	)


static func valid_name(value: Variant) -> bool:
	return (
		value is String
		and not value.is_empty()
		and value.length() <= 128
		and not value.contains("\n")
		and not value.contains("\r")
	)


func begin_run() -> Dictionary:
	if state.is_empty() or state.pending != 0 or state.serial >= MAX_ID:
		return {}
	var ship := int(state.next_ship_cycle)
	if ship >= ship_count:
		ship = 0
	state.serial += 1
	state.pending = state.serial
	state.next_ship_cycle = ship + 1
	return {"run": int(state.pending), "ship_cycle": ship}


func abandon(run: int) -> bool:
	if run <= 0 or state.get("pending", 0) != run:
		return false
	state.pending = 0
	return true


func qualifying_rank(score: int) -> int:
	if state.is_empty() or score < rules.minimum_result_score or score > MAX_ID:
		return -1
	for index in state.entries.size():
		if score > state.entries[index].score:
			return index
	return -1


func finish(run: int, name: String, score: int) -> Dictionary:
	if run <= 0 or state.get("pending", 0) != run or score < 0 or score > MAX_ID:
		return {"accepted": false, "rank": -1}
	var rank := qualifying_rank(score)
	if rank >= 0:
		if not valid_name(name) or score > MAX_ID - int(state.points):
			return {"accepted": false, "rank": -1}
		state.points += score
		state.entries.insert(rank, {"name": name, "score": score, "run": run})
		state.entries.resize(int(rules.count))
	state.pending = 0
	return {"accepted": true, "rank": rank}


func capture() -> Dictionary:
	return (
		{
			"schema": SCHEMA,
			"content_id": content_id,
			"mode": int(rules.type),
			"state": state.duplicate(true)
		}
		if not state.is_empty()
		else {}
	)


func restore(value: Variant) -> bool:
	error = "Invalid arcade profile or different game content."
	if (
		state.is_empty()
		or not value is Dictionary
		or value.get("schema") != SCHEMA
		or value.get("content_id") != content_id
		or value.get("mode") != rules.get("type")
	):
		return false
	var data: Variant = value.get("state")
	if not data is Dictionary:
		return false
	for key in ["serial", "pending", "next_ship_cycle", "points"]:
		if not Combat.integer(data.get(key)) or data[key] < 0 or data[key] > MAX_ID:
			return false
	if (data.pending != 0 and data.pending != data.serial) or data.next_ship_cycle > ship_count:
		return false
	var expected_cycle := 0 if data.serial == 0 else (int(data.serial) - 1) % ship_count + 1
	if data.next_ship_cycle != expected_cycle:
		return false
	if not data.get("entries") is Array or data.entries.size() != rules.count:
		return false
	if data.points < rules.points_initial:
		return false
	var retained_points := int(rules.points_initial)
	var previous := MAX_ID
	var seen := []
	for entry in data.entries:
		if not entry is Dictionary or not valid_name(entry.get("name")):
			return false
		if (
			not Combat.integer(entry.get("score"))
			or entry.score < rules.initial_score
			or entry.score > previous
		):
			return false
		if (
			not Combat.integer(entry.get("run"))
			or entry.run < 0
			or entry.run > data.serial
			or (entry.run > 0 and (seen.has(int(entry.run)) or entry.run == data.pending))
		):
			return false
		if entry.run == 0:
			if entry.score != rules.initial_score or entry.name != rules.initial_name:
				return false
		elif entry.score < rules.minimum_result_score:
			return false
		# Runs are monotonically numbered; equal scores retain the earlier entry.
		if (
			entry.run > 0
			and entry.score == previous
			and not seen.is_empty()
			and entry.run < seen.back()
		):
			return false
		previous = int(entry.score)
		seen.append(int(entry.run))
		if entry.run > 0:
			if entry.score > MAX_ID - retained_points:
				return false
			retained_points += int(entry.score)
	if data.points < retained_points:
		return false
	state = data.duplicate(true)
	for key in ["serial", "pending", "next_ship_cycle", "points"]:
		state[key] = int(state[key])
	for entry in state.entries:
		entry.score = int(entry.score)
		entry.run = int(entry.run)
	error = ""
	return true


func save(path: String) -> bool:
	error = ""
	if path.get_file() != "arcade.json" or path.get_base_dir().get_file() != content_id:
		error = "Arcade records require their own game-content file."
		return false
	var candidate = get_script().new()
	if not candidate.configure(content_id, rules, ship_count) or not candidate.restore(capture()):
		error = "Cannot save inconsistent arcade records."
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Could not write arcade records."
		return false
	file.store_string(JSON.stringify(capture()))
	file.flush()
	file.close()
	if FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		error = "Could not preserve previous arcade records."
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not finish arcade records."
		return false
	return true


func load_file(path: String) -> bool:
	for candidate in [path, path + ".bak"]:
		var json := JSON.new()
		if (
			FileAccess.file_exists(candidate)
			and json.parse(FileAccess.get_file_as_string(candidate)) == OK
			and restore(json.data)
		):
			return true
	error = "No valid arcade records were found."
	return false
