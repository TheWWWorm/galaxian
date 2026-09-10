extends RefCounted
## A single checkpoint commits the run, local scores and result acknowledgement.
## Individual session/profile serializers remain independent of this coordinator.
const Profile = preload("res://src/simulation/arcade_profile.gd")
const Session = preload("res://src/simulation/survival_session.gd")
const Combat = preload("res://src/simulation/combat.gd")
const SCHEMA := 1
const FILE_NAME := "survival-state.json"
var library
var declarations := {}
var profile
var session
var receipt := {}
var path := ""
var error := ""
var committed_json := ""


func open(data, content: Dictionary, directory: String) -> bool:
	if directory.get_file() != data.id or not content.get("scores") is Dictionary:
		error = "Survival records require their own game-content directory."
		return false
	if (
		not Session.valid_declarations(content, data)
		or content.scores.get("type") != content.setup.type
	):
		error = "Unsupported survival archive declarations."
		return false
	var candidate_profile := Profile.new()
	if not candidate_profile.configure(data.id, content.scores, int(content.setup.ship_count)):
		error = candidate_profile.error
		return false
	# Open into a detached coordinator; a corrupt file cannot replace an existing
	# in-memory run or silently reset a player's local high scores.
	var candidate = get_script().new()
	candidate.library = data
	candidate.declarations = content.duplicate(true)
	candidate.profile = candidate_profile
	candidate.path = directory.path_join(FILE_NAME)
	if not candidate.read_checkpoint():
		error = candidate.error
		return false
	library = data
	declarations = candidate.declarations
	profile = candidate.profile
	session = candidate.session
	receipt = candidate.receipt
	path = candidate.path
	committed_json = candidate.committed_json
	error = ""
	return true


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
	if exists:
		error = "No valid survival checkpoint was found. Existing records were preserved."
		return false
	# A .tmp file without a committed main/backup is an interrupted first write.
	# It does not constitute a completed new run or a saved high score.
	return true


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
		not records.configure(library.id, declarations.scores, int(declarations.setup.ship_count))
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
		if (
			not flight.configure_survival(library, declarations, 0, 0, 0)
			or not flight.restore(run.get("snapshot"))
		):
			return {}
		if (
			flight.ship_id != (int(run.id) - 1) % int(declarations.setup.ship_count)
			or not value.receipt.is_empty()
		):
			return {}
	elif records.state.pending != 0:
		return {}
	if not valid_receipt(value.receipt, records):
		return {}
	return {"profile": records, "session": flight, "receipt": value.receipt.duplicate(true)}


func valid_receipt(value: Dictionary, records) -> bool:
	if value.is_empty():
		return true
	for key in ["run", "score", "kills", "rank"]:
		if not Combat.integer(value.get(key)) or value[key] > Profile.MAX_ID:
			return false
	if (
		records.state.pending != 0
		or value.run <= 0
		or value.run != records.state.serial
		or value.score < 0
		or value.kills < 0
		or value.kills > Session.MAX_COUNTER
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


func start(origin: int, seed_value: int) -> bool:
	if profile == null or session != null or not receipt.is_empty():
		error = "Resume or close the current survival run before starting another."
		return false
	var records := copy_profile()
	var run: Dictionary = records.begin_run()
	if run.is_empty():
		error = "Cannot allocate another survival run."
		return false
	var flight := Session.new()
	if not flight.configure_survival(
		library, declarations, origin, int(run.ship_cycle), seed_value
	):
		error = flight.error
		return false
	return commit(records, flight, {})


func checkpoint() -> bool:
	if profile == null:
		error = "No survival profile is open."
		return false
	return commit(profile, session, receipt)


func finish(name: String = "") -> bool:
	if session == null or session.hull > 0:
		error = "Only a defeated survival run can be recorded."
		return false
	var records := copy_profile()
	var run := int(records.state.pending)
	var score := int(session.active_job.survival.score)
	var outcome: Dictionary = records.finish(run, name, score)
	if not outcome.accepted:
		error = "A qualifying survival score needs a valid pilot name."
		return false
	var result := {
		"run": run,
		"score": score,
		"kills": int(session.active_job.kills),
		"elapsed": session.elapsed,
		"rank": int(outcome.rank),
		"name": name if outcome.rank >= 0 else ""
	}
	# Validate the live run before removing its snapshot from the checkpoint.
	if decode(capture()).is_empty():
		error = "Cannot record an inconsistent survival run."
		return false
	return commit(records, null, result)


func result_summary() -> Dictionary:
	if not receipt.is_empty():
		return receipt.duplicate(true)
	if session == null or session.hull > 0:
		return {}
	return {
		"run": int(profile.state.pending),
		"score": int(session.active_job.survival.score),
		"kills": int(session.active_job.kills),
		"elapsed": session.elapsed,
		"rank": profile.qualifying_rank(int(session.active_job.survival.score)),
		"name": ""
	}


func acknowledge_result() -> bool:
	if receipt.is_empty():
		error = "No survival result awaits acknowledgement."
		return false
	return commit(profile, null, {})


func abandon() -> bool:
	if session == null:
		error = "No active survival run is available to abandon."
		return false
	var records := copy_profile()
	if not records.abandon(int(records.state.pending)):
		error = "No matching survival run is pending."
		return false
	return commit(records, null, {})


func copy_profile() -> Profile:
	var records := Profile.new()
	records.configure(library.id, declarations.scores, int(declarations.setup.ship_count))
	records.restore(profile.capture())
	return records


func commit(records, flight, result: Dictionary) -> bool:
	var state := capture_parts(records, flight, result)
	if decode(state).is_empty():
		error = "Cannot save inconsistent survival records."
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
		error = "Survival records require their own game-content file."
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		error = "Could not create the survival save directory."
		return false
	if not write_file(path + ".tmp", encoded):
		return false
	# After recovery, preserve the last validated document, not a corrupt main
	# file. Interrupted writes never turn a valid backup into malformed JSON.
	if not committed_json.is_empty():
		if not write_file(path + ".bak.tmp", committed_json):
			return false
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK:
			error = "Could not preserve the previous survival checkpoint."
			return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not finish the survival checkpoint."
		return false
	return true


func write_file(filename: String, contents: String) -> bool:
	var file := FileAccess.open(filename, FileAccess.WRITE)
	if file == null:
		error = "Could not write the survival checkpoint."
		return false
	file.store_string(contents)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK:
		error = "Could not flush the survival checkpoint."
		return false
	return true
