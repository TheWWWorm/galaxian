extends Node3D
## Original hull/shield flashes last until the next native simulation step.
## Sound requests within a rendered frame coalesce without touching combat RNG.
var library
var data := {}
var meshes := {}
var audio := preload("res://src/presentation/audio_settings.gd").effect_player()
var random := RandomNumberGenerator.new()
var pending_sound := ""
var last_sound := -1


static func valid(library) -> bool:
	var combat = preload("res://src/simulation/combat.gd")
	var mines = preload("res://src/simulation/mines.gd")
	var sounds = library.content.get("sound_bank")
	var value = library.content.get("player_hit")
	if not sounds is Dictionary or sounds.is_empty() or sounds.size() > 256:
		return false
	for key in sounds:
		var sound = sounds[key]
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 0:
			return false
		if not sound is Dictionary or not sound.get("path") is String:
			return false
		if (
			not sound.path.begins_with("data/sounds/")
			or ".." in sound.path
			or sound.path.get_extension().to_lower() not in ["wav", "mp3"]
		):
			return false
		if (
			not combat.number(sound.get("gain"))
			or sound.gain < 0
			or sound.gain > 1
			or not FileAccess.file_exists(library.root.path_join(sound.path))
		):
			return false
	if (
		not value is Dictionary
		or value.get("lifetime") != "simulation_step"
		or not value.get("models") is Dictionary
		or not value.get("sounds") is Dictionary
	):
		return false
	for kind in ["hull", "shield"]:
		if (
			not mines.mesh_id(value.models.get(kind), library.content.resources)
			or not value.sounds.get(kind) is Array
			or value.sounds[kind].is_empty()
			or value.sounds[kind].size() > 32
		):
			return false
		for id in value.sounds[kind]:
			if not combat.integer(id) or not sounds.has(str(int(id))):
				return false
	return (
		combat.integer(value.get("visual_shield_above"))
		and value.visual_shield_above >= 0
		and combat.integer(value.get("sound_shield_above"))
		and value.sound_shield_above >= 0
	)


func configure(source_library) -> void:
	library = source_library
	data = library.content.player_hit
	random.randomize()
	add_child(audio)
	for kind in data.models:
		var model: String = (
			library.content.resources[str(int(data.models[kind]))].path.get_file().get_basename()
		)
		var node: MeshInstance3D = library.model(model)
		add_child(node)
		node.hide()
		meshes[kind] = node


func begin_step() -> void:
	for mesh in meshes.values():
		mesh.hide()


func flash(shield_after: float, pose: Transform3D) -> void:
	begin_step()
	global_transform = pose
	meshes["shield" if shield_after > data.visual_shield_above else "hull"].show()
	pending_sound = "shield" if shield_after > data.sound_shield_above else "hull"


func _process(_delta: float) -> void:
	flush_sound()


func flush_sound() -> void:
	if pending_sound.is_empty():
		return
	var ids: Array = data.sounds[pending_sound]
	pending_sound = ""
	last_sound = int(ids[random.randi_range(0, ids.size() - 1)])
	audio.stream = library.sound_clip(last_sound)
	audio.volume_linear = float(library.content.sound_bank[str(last_sound)].gain)
	if audio.stream != null and DisplayServer.get_name() != "headless":
		audio.play()


func _exit_tree() -> void:
	audio.stop()
	audio.stream = null
