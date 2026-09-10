extends Node3D
## Source hit flashes survive until a rendered frame has presented them.
## Sound requests within a rendered frame coalesce without touching combat RNG.
var library
var data := {}
var meshes := {}
var audio := preload("res://src/presentation/audio_settings.gd").effect_player()
var random := RandomNumberGenerator.new()
var pending_sound := ""
var last_sound := -1
var voices := {}
var presented := false
var shake_remaining := 0.0
var camera_pose := Transform3D.IDENTITY
var camera_offset_applied := false


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
		or value.get("lifetime") != "render_frame"
		or not value.get("models") is Dictionary
		or not value.get("sounds") is Dictionary
	):
		return false
	var shake = value.get("shake")
	if not shake is Dictionary:
		return false
	for key in ["duration", "units_per_ms"]:
		if not combat.number(shake.get(key)) or shake[key] <= 0 or shake[key] > 10:
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
	RenderingServer.frame_post_draw.connect(mark_presented)
	for kind in data.models:
		var model: String = (
			library.content.resources[str(int(data.models[kind]))].path.get_file().get_basename()
		)
		var node: MeshInstance3D = library.model(model)
		add_child(node)
		node.hide()
		meshes[kind] = node


func mark_presented() -> void:
	if is_visible_in_tree():
		presented = true


func clear_flash() -> void:
	for mesh in meshes.values():
		mesh.hide()
	presented = false


func begin_step() -> void:
	# Several fixed updates can precede a draw. Never erase an unseen impact.
	if presented:
		clear_flash()


func flash(shield_after: float, pose: Transform3D, incoming := Vector3.ZERO) -> void:
	clear_flash()
	global_transform = pose
	if incoming.is_finite() and incoming.length_squared() > .000001:
		var direction := incoming.normalized()
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > .99 else Vector3.UP
		global_basis = Basis.looking_at(direction, up)
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
	# The supplied game owns one voice per sound ID: a different variant can
	# finish its tail, while another hit with the same ID restarts that voice.
	if not voices.has(last_sound):
		var voice = (
			audio
			if voices.is_empty()
			else preload("res://src/presentation/audio_settings.gd").effect_player()
		)
		if voice.get_parent() == null:
			add_child(voice)
		voices[last_sound] = voice
	audio = voices[last_sound]
	audio.stream = library.sound_clip(last_sound)
	audio.volume_linear = float(library.content.sound_bank[str(last_sound)].gain)
	if audio.stream != null and DisplayServer.get_name() != "headless":
		audio.play()


func start_shake() -> void:
	# Further hits do not extend an active shake in the source.
	if shake_remaining <= 0:
		shake_remaining = float(data.shake.duration)


func restore_camera(camera: Camera3D) -> void:
	if camera_offset_applied:
		camera.global_transform = camera_pose
		camera_offset_applied = false


func shake_camera(camera: Camera3D, seconds: float, target_distance: float) -> void:
	if shake_remaining <= 0 or seconds <= 0:
		return
	shake_remaining = maxf(0, shake_remaining - seconds)
	camera_pose = camera.global_transform
	# Source camera coordinates are four times world units. Its random range
	# is half the update milliseconds, converted by the imported scale.
	var half_ms := floori(seconds * 1000.0 * .5)
	if half_ms <= 0:
		return
	var offset := (
		Vector3(
			random.randi_range(-half_ms, half_ms - 1),
			random.randi_range(-half_ms, half_ms - 1),
			random.randi_range(-half_ms, half_ms - 1)
		)
		* float(data.shake.units_per_ms)
	)
	var target := camera_pose.origin - camera_pose.basis.z * maxf(target_distance, 1)
	camera.global_position += offset
	camera.look_at(target, camera_pose.basis.y)
	camera_offset_applied = true


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(mark_presented):
		RenderingServer.frame_post_draw.disconnect(mark_presented)
	for voice in voices.values():
		voice.stop()
		voice.stream = null
	voices.clear()
	audio.stop()
	audio.stream = null
