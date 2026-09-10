extends RefCounted
## One data-only worker. No scene, GPU resource or installed cache is shared.
const Formats = preload("res://src/content/formats.gd")
const NativeData = preload("res://src/content/native_data.gd")
var thread := Thread.new()
var mutex := Mutex.new()
var message := "Reading embedded game data"
var cancelled := false
var ratio := 0.0


func start(source: PackedByteArray) -> Error:
	return thread.start(read.bind(source))


func read(source: PackedByteArray) -> Dictionary:
	var reader := NativeData.new()
	var content := reader.extract(source, report)
	return {"content": content, "error": reader.error}


func report(phase: String, fraction: float = 0.0) -> bool:
	mutex.lock()
	if not phase.is_empty():
		message = phase
		ratio = fraction
	var proceed := not cancelled
	mutex.unlock()
	return proceed


func status() -> Dictionary:
	mutex.lock()
	var current := {"message": message, "ratio": ratio}
	mutex.unlock()
	return current


func cancel() -> void:
	mutex.lock()
	cancelled = true
	mutex.unlock()


func is_alive() -> bool:
	return thread.is_alive()


func finish() -> Dictionary:
	var result: Variant = thread.wait_to_finish()
	if not result is Dictionary:
		return {"content": {}, "error": "Could not read embedded game data."}
	return result


func start_assets(zip: ZIPReader, prefix: String, selected: Array[String], stage: String) -> Error:
	return thread.start(read_assets.bind(zip, prefix, selected, stage))


func read_assets(
	zip: ZIPReader, prefix: String, selected: Array[String], stage: String
) -> Dictionary:
	var reader := Formats.new()
	var error := ""
	var total := 0
	var languages: Array[String] = []
	var hashes := {}
	for i in selected.size():
		if not report("Importing " + selected[i].get_file(), float(i + 1) / selected.size()):
			error = "Import cancelled."
			break
		var rel := selected[i]
		var bytes := zip.read_file(prefix + rel)
		total += bytes.size()
		if bytes.is_empty() or bytes.size() > 32 * 1024 * 1024 or total > 128 * 1024 * 1024:
			error = "Invalid or oversized resource: " + rel
			break
		if rel.ends_with(".aem"):
			if reader.aem(bytes).is_empty():
				error = rel + ": " + reader.error
				break
		elif rel.ends_with(".aei"):
			if reader.aei(bytes).is_empty():
				error = rel + ": " + reader.error
				break
		elif rel.ends_with(".lang"):
			if reader.language(bytes).size() < 200:
				error = "Incomplete language file: " + rel
				break
			languages.append(rel.trim_suffix(".lang"))
		elif rel.get_file() in ["ships.txt", "items.txt", "stations.txt", "systems.txt"]:
			var cols: int = {"ships.txt": 12, "items.txt": 11, "stations.txt": 9, "systems.txt": 1}[
				rel.get_file()
			]
			var rows := reader.table(bytes, cols)
			if rows.is_empty():
				error = rel + ": " + reader.error
				break
			for row in rows:
				for column in range(0 if rel.get_file() in ["ships.txt", "items.txt"] else 1, cols):
					if not str(row[column]).is_valid_int():
						error = "Non-numeric game data: " + rel
						break
			if not error.is_empty():
				break
		var output := stage.path_join(rel)
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			error = "Could not write imported resource: " + rel
			break
		file.store_buffer(bytes)
		file.close()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		hashes[rel] = hash.finish().hex_encode()
	if languages.is_empty() and error.is_empty():
		error = "No supported language data was found."
	return {"error": error, "languages": languages, "hashes": hashes, "bytes": total}
