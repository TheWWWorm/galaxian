extends RefCounted
## Records, run identity and hull unlocks for the swarm mode. One checkpoint
## commits the run, the local board and the result acknowledgement together,
## the same discipline the survival archive uses.
const Profile = preload("res://src/simulation/arcade_profile.gd")
const Session = preload("res://src/simulation/swarm_session.gd")
const Rules = preload("res://src/simulation/swarm_rules.gd")
const Build = preload("res://src/simulation/swarm_build.gd")
const Combat = preload("res://src/simulation/combat.gd")
const SCHEMA := 1
const FILE_NAME := "swarm-state.json"
var library
var rules := {}
# The imported arcade presentation block, reused for this mode's result and
# name-entry screens. Scores, choice artwork and rank names all live here.
var declarations := {}
var profile
var session
var receipt := {}
var path := ""
var error := ""
var committed_json := ""
# Set when a checkpoint was opened without its unfinished run, because the rule
# block moved on under it. The board is intact; the run is not resumable.
var recovered := ""


func open(data, parameters: Dictionary, directory: String) -> bool:
	if directory.get_file() != data.id:
		error = "Swarm records require their own game-content directory."
		return false
	if not Session.valid_declarations(data, parameters):
		error = "Unsupported swarm rules for this installation."
		return false
	if not ranks(data).size() > 0:
		error = "This installation has no arcade rank table."
		return false
	var records := Profile.new()
	if not records.configure(data.id, data.content.survival.scores, data.ships.size()):
		error = records.error
		return false
	# Open into a detached coordinator, so a corrupt file can never replace an
	# in-memory run or silently reset the local board.
	var candidate = get_script().new()
	candidate.library = data
	candidate.rules = parameters.duplicate(true)
	candidate.declarations = data.content.survival
	candidate.profile = records
	candidate.path = directory.path_join(FILE_NAME)
	if not candidate.read_checkpoint():
		error = candidate.error
		return false
	library = data
	declarations = candidate.declarations
	rules = candidate.rules
	profile = candidate.profile
	session = candidate.session
	receipt = candidate.receipt
	path = candidate.path
	committed_json = candidate.committed_json
	recovered = candidate.recovered
	error = ""
	return true


static func ranks(data) -> Array:
	var survival: Variant = data.content.get("survival")
	if not survival is Dictionary:
		return []
	return survival.get("menu", {}).get("presentation", {}).get("ranks", [])


static func hull_order(data) -> Array:
	## Hulls ordered by how forgiving they are, from the ship table alone:
	## imported toughness weighted by imported agility. No authored ranking.
	var agilities: Array = data.content.player_motion.steering.agilities
	var column := int(data.content.player_motion.steering.ship_type_column)
	var order := range(data.ships.size())
	var weight := func(index: int) -> float:
		var row: Array = data.ships[index]
		var agility := float(agilities[int(row[column])])
		return float(row[4]) * sqrt(maxf(1.0, agility))
	order.sort_custom(func(a, b): return weight.call(a) < weight.call(b))
	return order


func best_score() -> int:
	if profile == null:
		return 0
	var best := 0
	for row in profile.state.entries:
		best = maxi(best, int(row.score))
	return best


func unlocked() -> Array:
	## The imported rank ladder has one entry per hull, so a rank reached is a
	## hull unlocked. Extra hulls beyond the ladder stay available from the start.
	var order := hull_order(library)
	var table := ranks(library)
	var score := best_score()
	var result := []
	for position in order.size():
		if position >= table.size() or score >= unlock_points(position):
			result.append(int(order[position]))
	if result.is_empty() and not order.is_empty():
		result.append(int(order[0]))
	return result


func unlock_points(position: int) -> int:
	## The imported rank threshold, read at this mode's scale. Rank names stay
	## imported; what a rank costs in swarm points is a rule.
	var table := ranks(library)
	if position < 0 or position >= table.size():
		return 0
	return Rules.unlock_points(rules, int(table[position].points))


func rank_name(index: int) -> String:
	var table := ranks(library)
	if index < 0 or index >= table.size():
		return ""
	return library.text(int(table[index].text))


func read_checkpoint() -> bool:
	var exists := false
	for filename in [path, path + ".bak"]:
		if not FileAccess.file_exists(filename):
			continue
		exists = true
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(filename)) != OK:
			continue
		var candidate := decode(json.data)
		if candidate.is_empty():
			continue
		profile = candidate.profile
		session = candidate.session
		receipt = candidate.receipt
		committed_json = JSON.stringify(capture())
		error = ""
		return true
	if not exists:
		return true
	# The run would not load. Before giving up on the whole file, try to keep
	# the local board and drop only the unfinished run: a rule-block change
	# invalidates a run in progress, and must not cost the player their records.
	for filename in [path, path + ".bak"]:
		if not FileAccess.file_exists(filename):
			continue
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(filename)) != OK:
			continue
		var board := decode_board(json.data)
		if board.is_empty():
			continue
		profile = board.profile
		session = null
		receipt = board.receipt
		committed_json = JSON.stringify(capture())
		recovered = "An unfinished Swarm run could not be continued under the current rules. Your records were kept."
		error = ""
		return true
	error = "No valid swarm checkpoint was found. Existing records were preserved."
	return false


func capture() -> Dictionary:
	if profile == null:
		return {}
	return capture_parts(profile, session, receipt)


func capture_parts(records, flight, result: Dictionary) -> Dictionary:
	return {
		"schema": SCHEMA,
		"content_id": library.id,
		"profile": records.capture(),
		"run":
		{} if flight == null else {"id": int(records.state.pending), "snapshot": flight.capture()},
		"receipt": result.duplicate(true)
	}


func decode(value: Variant) -> Dictionary:
	if (
		not value is Dictionary
		or value.get("schema") != SCHEMA
		or value.get("content_id") != library.id
	):
		return {}
	var records := Profile.new()
	if (
		not records.configure(library.id, library.content.survival.scores, library.ships.size())
		or not records.restore(value.get("profile"))
	):
		return {}
	if not value.get("run") is Dictionary or not value.get("receipt") is Dictionary:
		return {}
	var flight = null
	var run: Dictionary = value.run
	if not run.is_empty():
		if not Combat.integer(run.get("id")) or run.id <= 0 or run.id != records.state.pending:
			return {}
		flight = Session.new()
		flight.library = library
		flight.rules = rules.duplicate(true)
		flight.rules.combo_ms = int(library.content.survival.rules.combo_ms)
		flight.content_id = library.id
		if not flight.restore(run.get("snapshot")):
			return {}
		if not value.receipt.is_empty():
			return {}
	elif records.state.pending != 0:
		return {}
	if not valid_receipt(value.receipt, records):
		return {}
	return {"profile": records, "session": flight, "receipt": value.receipt.duplicate(true)}


func decode_board(value: Variant) -> Dictionary:
	## The board alone, with any unfinished run abandoned. Deliberately not part
	## of decode(): decode() is also the commit self-check, and that check must
	## never be able to "repair" state it should have refused.
	if (
		not value is Dictionary
		or value.get("schema") != SCHEMA
		or value.get("content_id") != library.id
		or not value.get("receipt") is Dictionary
	):
		return {}
	var records := Profile.new()
	if (
		not records.configure(library.id, library.content.survival.scores, library.ships.size())
		or not records.restore(value.get("profile"))
	):
		return {}
	if int(records.state.pending) != 0:
		records.abandon(int(records.state.pending))
	var result: Dictionary = value.receipt.duplicate(true)
	if not valid_receipt(result, records):
		result = {}
	return {"profile": records, "receipt": result}


func valid_receipt(value: Dictionary, records) -> bool:
	if value.is_empty():
		return true
	for key in ["run", "score", "kills", "rank", "level"]:
		if not Combat.integer(value.get(key)) or value[key] > Profile.MAX_ID:
			return false
	if (
		records.state.pending != 0
		or value.run <= 0
		or value.run != records.state.serial
		or value.score < 0
		or value.kills < 0
		or value.level < 0
		or value.rank < -1
		or value.rank >= records.state.entries.size()
		or not Combat.number(value.get("elapsed"))
		or value.elapsed < 0
		or value.elapsed > 1e9
		or not value.get("name") is String
	):
		return false
	if value.rank >= 0:
		var row: Dictionary = records.state.entries[int(value.rank)]
		return row.run == value.run and row.score == value.score and row.name == value.name
	return (
		value.name.is_empty()
		and records.qualifying_rank(int(value.score)) == -1
		and not records.state.entries.any(func(row): return row.run == value.run)
	)


func start(origin: int, ship_id: int, seed_value: int) -> bool:
	if profile == null or session != null or not receipt.is_empty():
		error = "Resume or close the current swarm run before starting another."
		return false
	if not unlocked().has(ship_id):
		error = "That hull has not been unlocked yet."
		return false
	var records := copy_profile()
	var run: Dictionary = records.begin_run()
	if run.is_empty():
		error = "Cannot allocate another swarm run."
		return false
	var flight := Session.new()
	if not flight.configure_swarm(library, rules, origin, ship_id, unlocked(), seed_value):
		error = flight.error
		return false
	return commit(records, flight, {})


func checkpoint() -> bool:
	if profile == null:
		error = "No swarm profile is open."
		return false
	return commit(profile, session, receipt)


func finish(name: String = "") -> bool:
	if session == null or session.hull > 0:
		error = "Only a defeated swarm run can be recorded."
		return false
	var records := copy_profile()
	var run := int(records.state.pending)
	var score := int(session.director.score)
	var outcome: Dictionary = records.finish(run, name, score)
	if not outcome.accepted:
		error = "A qualifying swarm score needs a valid pilot name."
		return false
	var result := {
		"run": run,
		"score": score,
		"kills": int(session.active_job.kills),
		"level": int(session.director.level),
		"elapsed": session.elapsed,
		"rank": int(outcome.rank),
		"name": name if outcome.rank >= 0 else ""
	}
	if decode(capture()).is_empty():
		error = "Cannot record an inconsistent swarm run."
		return false
	return commit(records, null, result)


func result_summary() -> Dictionary:
	if not receipt.is_empty():
		return receipt.duplicate(true)
	if session == null or session.hull > 0:
		return {}
	return {
		"run": int(profile.state.pending),
		"score": int(session.director.score),
		"kills": int(session.active_job.kills),
		"level": int(session.director.level),
		"elapsed": session.elapsed,
		"rank": profile.qualifying_rank(int(session.director.score)),
		"name": ""
	}


func acknowledge_result() -> bool:
	if receipt.is_empty():
		error = "No swarm result awaits acknowledgement."
		return false
	return commit(profile, null, {})


func abandon() -> bool:
	if session == null:
		error = "No active swarm run is available to abandon."
		return false
	var records := copy_profile()
	if not records.abandon(int(records.state.pending)):
		error = "No matching swarm run is pending."
		return false
	return commit(records, null, {})


func copy_profile() -> Profile:
	var records := Profile.new()
	records.configure(library.id, library.content.survival.scores, library.ships.size())
	records.restore(profile.capture())
	return records


func commit(records, flight, result: Dictionary) -> bool:
	var state := capture_parts(records, flight, result)
	if decode(state).is_empty():
		error = "Cannot save inconsistent swarm records."
		return false
	var encoded := JSON.stringify(state)
	if not write_checkpoint(encoded):
		return false
	profile = records
	session = flight
	receipt = result.duplicate(true)
	committed_json = encoded
	error = ""
	return true


func write_checkpoint(encoded: String) -> bool:
	if path.get_file() != FILE_NAME or path.get_base_dir().get_file() != library.id:
		error = "Swarm records require their own game-content file."
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		error = "Could not create the swarm save directory."
		return false
	if not write_file(path + ".tmp", encoded):
		return false
	if not committed_json.is_empty():
		if not write_file(path + ".bak.tmp", committed_json):
			return false
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			error = "Could not preserve the previous swarm checkpoint."
			return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not finish the swarm checkpoint."
		return false
	return true


func write_file(filename: String, contents: String) -> bool:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		error = "Could not write the swarm checkpoint."
		return false
	file.store_string(contents)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK:
		error = "Could not flush the swarm checkpoint."
		return false
	return true
