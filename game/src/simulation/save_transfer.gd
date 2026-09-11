extends RefCounted
## Portable data-only saves, isolated to the exact imported content identity.
const Session = preload("res://src/simulation/session.gd")
const Survival = preload("res://src/simulation/survival_archive.gd")
const FILES := ["campaign.json", "free.json", "survival-state.json"]
const MAX_BYTES := 16 * 1024 * 1024
var error := ""


func validate(library, value: Variant) -> Dictionary:
	error = ""
	if (
		not value is Dictionary
		or value.get("format") != "gof-native-save"
		or value.get("version") != 1
	):
		error = "This is not a supported remake save export."
		return {}
	if value.get("content_id") != library.id:
		error = "This save belongs to a different game archive. Import the same IPA on both devices first."
		return {}
	if (
		not value.get("saves") is Dictionary
		or value.saves.is_empty()
		or value.saves.size() > FILES.size()
	):
		error = "The export contains no supported saves."
		return {}
	for filename in value.saves:
		if filename not in FILES:
			error = "The export contains an unsupported save entry."
			return {}
		var snapshot: Variant = value.saves[filename]
		if filename == Survival.FILE_NAME:
			var archive := Survival.new()
			archive.library = library
			archive.declarations = library.content.survival
			if archive.decode(snapshot).is_empty():
				error = "The survival save is invalid or incompatible."
				return {}
		else:
			var slot: String = filename.get_basename()
			var pilot := Session.new()
			pilot.configure(library, slot == "free")
			if not pilot.restore(snapshot) or pilot.slot != slot:
				error = "The %s save is invalid or incompatible." % slot
				return {}
	return value.duplicate(true)


func read_export(library, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		error = "The save export cannot be read or exceeds 16 MiB."
		return {}
	return validate(library, JSON.parse_string(file.get_as_text()))


func collect(library, directory: String) -> Dictionary:
	var saves := {}
	for filename in FILES:
		var path := directory.path_join(filename)
		if not FileAccess.file_exists(path):
			continue
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var record := {
			"format": "gof-native-save",
			"version": 1,
			"content_id": library.id,
			"saves": {filename: value}
		}
		if validate(library, record).is_empty():
			error = "Cannot export %s: %s" % [filename, error]
			return {}
		saves[filename] = value
	return validate(
		library,
		{"format": "gof-native-save", "version": 1, "content_id": library.id, "saves": saves}
	)


func write(path: String, value: Dictionary) -> bool:
	var text := JSON.stringify(value)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		error = "The save export exceeds 16 MiB."
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "Could not write the save export."
		return false
	file.store_string(text)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	if not ok:
		error = "Could not finish writing the save export."
	return ok


func install(library, directory: String, value: Dictionary) -> bool:
	if validate(library, value).is_empty():
		return false
	if directory.get_file() != library.id:
		error = "Save destination does not match the game archive."
		return false
	# Stage a complete sibling directory. Preserve every previous file in a
	# timestamped backup; either all imported slots become visible or none do.
	var suffix := str(Time.get_unix_time_from_system()).replace(".", "-")
	var staging := directory + ".import-" + suffix
	var backup := directory + ".before-import-" + suffix
	if DirAccess.make_dir_recursive_absolute(staging) != OK:
		error = "Could not stage the imported saves."
		return false
	if DirAccess.dir_exists_absolute(directory):
		for filename in DirAccess.get_files_at(directory):
			if (
				DirAccess.copy_absolute(directory.path_join(filename), staging.path_join(filename))
				!= OK
			):
				error = "Could not preserve existing saves."
				remove_staging(staging)
				return false
	for filename in value.saves:
		if not write(staging.path_join(filename), value.saves[filename]):
			remove_staging(staging)
			return false
		# A retry must not resurrect a different device's previous pilot.
		if not write(staging.path_join(filename + ".bak"), value.saves[filename]):
			remove_staging(staging)
			return false
	var had_directory := DirAccess.dir_exists_absolute(directory)
	if had_directory and DirAccess.rename_absolute(directory, backup) != OK:
		error = "Could not back up existing saves."
		remove_staging(staging)
		return false
	if DirAccess.rename_absolute(staging, directory) != OK:
		if had_directory:
			DirAccess.rename_absolute(backup, directory)
		error = "Could not finish importing saves."
		remove_staging(staging)
		return false
	return true


func remove_staging(directory: String) -> void:
	for filename in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
