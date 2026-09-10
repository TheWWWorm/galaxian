extends RefCounted
signal progress(message: String, ratio: float)
const NativeImport = preload("res://src/content/native_import.gd")
const SCHEMA := 80
var error := ""
var root := ""
var content_id := ""
var metadata := {}
var cache_base := "user://content"
var installing := false
var cancelled := false
var native_job: RefCounted


func install(path: String, tree: SceneTree) -> bool:
	if installing:
		return false
	installing = true
	cancelled = false
	var success := await install_archive(path, tree)
	installing = false
	return success


func cancel() -> void:
	if not installing:
		return
	cancelled = true
	if native_job != null:
		native_job.cancel()


func install_archive(path: String, tree: SceneTree) -> bool:
	error = ""
	if not FileAccess.file_exists(path):
		error = "The selected file could not be opened."
		return false
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source.get_length() > 128 * 1024 * 1024:
		error = "Choose a compatible Galaxy on Fire 1 IPA under 128 MiB."
		return false
	source.close()
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		error = "This file is not a readable IPA archive."
		return false
	var names := zip.get_files()
	if names.size() > 4096:
		zip.close()
		error = "The archive contains too many entries."
		return false
	var prefix := ""
	for n in names:
		if n.begins_with("Payload/") and n.ends_with(".app/data/txt/ships.txt"):
			prefix = n.trim_suffix("data/txt/ships.txt")
			break
	if prefix.is_empty():
		zip.close()
		error = "No compatible Galaxy on Fire 1 content was found in this IPA."
		return false
	# The executable is an import-time data source only. Never write it to cache.
	var executable := prefix + prefix.trim_suffix("/").get_file().trim_suffix(".app")
	if not zip.file_exists(executable):
		zip.close()
		error = "The application data source is missing."
		return false
	progress.emit("Reading embedded campaign and catalogue data", 0.0)
	await tree.process_frame
	if cancelled:
		zip.close()
		error = "Import cancelled."
		return false
	native_job = NativeImport.new()
	if native_job.start(zip.read_file(executable)) != OK:
		native_job = null
		zip.close()
		error = "Could not start the content reader."
		return false
	var result := await collect_job(tree)
	var embedded: Dictionary = result.content
	if cancelled:
		zip.close()
		error = "Import cancelled."
		return false
	if embedded.is_empty():
		zip.close()
		error = result.error
		return false
	for required in [
		"data/txt/items.txt",
		"data/txt/stations.txt",
		"data/txt/systems.txt",
		"data/txt/quadrants.txt",
		"data/meshes/protagonist_01.aem",
		"data/meshes/st_terran_station.aem",
		"data/textures/main_texture.aei"
	]:
		if not zip.file_exists(prefix + required):
			zip.close()
			error = "Required game resource is missing: " + required
			return false
	var selected: Array[String] = []
	for name in names:
		if not name.begins_with(prefix) or name.ends_with("/"):
			continue
		var rel := name.trim_prefix(prefix)
		if rel.contains("..") or rel.contains("\\") or rel.is_absolute_path():
			continue
		if (
			(rel.begins_with("data/meshes/") and rel.ends_with(".aem"))
			or (rel.begins_with("data/textures/") and rel.ends_with(".aei"))
			or (
				rel.begins_with("data/sounds/") and rel.get_extension().to_lower() in ["mp3", "wav"]
			)
			or (rel.begins_with("data/txt/") and rel.ends_with(".txt"))
			or (not rel.contains("/") and rel.ends_with(".lang"))
		):
			selected.append(rel)
	if selected.size() < 10:
		zip.close()
		error = "The archive has incomplete game content."
		return false
	var id := FileAccess.get_sha256(path)
	var stage := cache_base.path_join(id + ".partial-" + str(Time.get_ticks_usec()))
	var destination := cache_base.path_join(id)
	if DirAccess.make_dir_recursive_absolute(stage) != OK:
		zip.close()
		error = "Cannot create the local content cache."
		return false
	native_job = NativeImport.new()
	if native_job.start_assets(zip, prefix, selected, stage) != OK:
		native_job = null
		zip.close()
		remove_stage(stage)
		error = "Could not start the asset reader."
		return false
	var assets := await collect_job(tree)
	zip.close()
	if cancelled or not str(assets.error).is_empty():
		error = "Import cancelled." if cancelled else str(assets.error)
		remove_stage(stage)
		return false
	var languages: Array[String] = assets.languages
	var hashes: Dictionary = assets.hashes
	var total: int = assets.bytes
	var embedded_bytes := JSON.stringify(embedded).to_utf8_buffer()
	var embedded_file := FileAccess.open(stage.path_join("content.json"), FileAccess.WRITE)
	if embedded_file == null:
		error = "Could not write imported content definitions."
		remove_stage(stage)
		return false
	embedded_file.store_buffer(embedded_bytes)
	embedded_file.close()
	var embedded_hash := HashingContext.new()
	embedded_hash.start(HashingContext.HASH_SHA256)
	embedded_hash.update(embedded_bytes)
	hashes["content.json"] = embedded_hash.finish().hex_encode()
	# Validate every normalized reference against the actual extracted catalogues.
	progress.emit("Checking imported game data", 0.0)
	await tree.process_frame
	if cancelled:
		error = "Import cancelled."
		remove_stage(stage)
		return false
	var validator = load("res://src/content/library.gd").new()
	if not validator.open(stage, id, "gb" if languages.has("gb") else languages[0]):
		error = validator.error
		remove_stage(stage)
		return false
	var manifest := {
		"schema": SCHEMA,
		"profile": "gof1-ios",
		"sha256": id,
		"files": hashes,
		"languages": languages,
		"bytes": total
	}
	var meta_file := FileAccess.open(stage.path_join("manifest.json"), FileAccess.WRITE)
	if meta_file == null:
		error = "Could not finish the content manifest."
		remove_stage(stage)
		return false
	meta_file.store_string(JSON.stringify(manifest))
	meta_file.close()
	if DirAccess.dir_exists_absolute(destination):
		# A previously installed identical archive is replaced only after validation.
		var old := destination + ".previous"
		remove_stage(old)
		if DirAccess.rename_absolute(destination, old) != OK:
			error = "Could not update the content cache."
			remove_stage(stage)
			return false
		if DirAccess.rename_absolute(stage, destination) != OK:
			DirAccess.rename_absolute(old, destination)
			error = "Could not activate imported content."
			remove_stage(stage)
			return false
		remove_stage(old)
	elif DirAccess.rename_absolute(stage, destination) != OK:
		error = "Could not activate imported content."
		remove_stage(stage)
		return false
	root = destination
	content_id = id
	metadata = manifest
	progress.emit("Content ready", 1.0)
	return true


func collect_job(tree: SceneTree) -> Dictionary:
	var previous := {}
	while native_job.is_alive():
		var current: Dictionary = native_job.status()
		if current != previous:
			progress.emit(current.message, current.ratio)
			previous = current
		await tree.process_frame
	var result: Dictionary = native_job.finish()
	native_job = null
	return result


func open_cache(directory: String) -> bool:
	error = ""
	var file := directory.path_join("manifest.json")
	if not FileAccess.file_exists(file):
		error = "Import your game IPA to begin."
		return false
	var value = JSON.parse_string(FileAccess.get_file_as_string(file))
	if (
		not value is Dictionary
		or value.get("schema") != SCHEMA
		or value.get("profile") != "gof1-ios"
		or not value.get("files") is Dictionary
	):
		error = "The imported content manifest is invalid. Import the IPA again."
		return false
	for rel in value.files:
		if (
			not rel is String
			or rel.contains("..")
			or rel.is_absolute_path()
			or not FileAccess.file_exists(directory.path_join(rel))
			or FileAccess.get_sha256(directory.path_join(rel)) != str(value.files[rel])
		):
			error = "Imported content is missing or damaged. Import the IPA again."
			return false
	root = directory
	content_id = str(value.sha256)
	metadata = value
	return true


func remove_stage(directory: String) -> void:
	# Only installer-owned directories below the configured cache root are removed.
	if not directory.begins_with(cache_base + "/"):
		return
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(directory.path_join(name))
	for name in dir.get_directories():
		remove_stage(directory.path_join(name))
	DirAccess.remove_absolute(directory)
