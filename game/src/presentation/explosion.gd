extends Node3D
## Imported layer timelines; native simulation drives growth, fades and sound cues.
const Destruction = preload("res://src/simulation/actor_destruction.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Mines = preload("res://src/simulation/mines.gd")
var library
var definition := {}
var elapsed_ms := 0.0
var layers: Array[MeshInstance3D] = []
var appearances: Array = []
var played := {}
var sounds: Array[AudioStreamPlayer] = []
var finished := false
var body: Node3D


static func valid(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or not Destruction.valid_motion(value.get("drift"))
		or not value.get("actors") is Array
		or value.actors.size() != library.content.tables.actor_meshes.size()
		or not value.get("effects") is Dictionary
		or not Combat.valid_vector(value.get("player_camera_offset", []))
		or Combat.vector(value.player_camera_offset).length_squared() <= .001
	):
		return false
	for kind in value.actors + [value.get("player")]:
		if not Combat.integer(kind) or not value.effects.has(str(int(kind))):
			return false
	for effect in value.effects.values():
		if (
			not effect is Dictionary
			or not Combat.integer(effect.get("hide_body_ms"))
			or effect.hide_body_ms < 0
			or effect.hide_body_ms > 1000000
		):
			return false
		if (
			not effect is Dictionary
			or not effect.get("layers") is Array
			or effect.layers.is_empty()
			or effect.layers.size() > 64
			or not effect.get("sounds") is Array
			or effect.sounds.size() > 64
		):
			return false
		for key in ["alpha_start", "alpha_end", "alpha_cutoff"]:
			if not Combat.integer(effect.get(key)) or effect[key] < 0 or effect[key] > 255:
				return false
		if effect.alpha_start <= effect.alpha_cutoff or effect.alpha_end > effect.alpha_cutoff:
			return false
		for layer in effect.layers:
			if (
				not layer is Dictionary
				or not Mines.mesh_id(layer.get("mesh"), library.content.resources)
				or not Combat.valid_vector(layer.get("rotation", []))
				or not Combat.valid_vector(layer.get("offset", []))
			):
				return false
			for key in ["delay_ms", "duration_ms", "scale", "fade_delay_ms", "fade_duration_ms"]:
				if not Combat.number(layer.get(key)) or layer[key] < 0 or layer[key] > 1000000:
					return false
			if layer.duration_ms <= 0 or layer.scale <= 0 or layer.fade_duration_ms <= 0:
				return false
			if (
				layer.has("scale_span")
				and (
					not Combat.number(layer.scale_span)
					or layer.scale_span < 0
					or layer.scale_span > 1000
					or not Combat.integer(layer.get("scale_steps"))
					or layer.scale_steps < 1
					or layer.scale_steps > 1000000
				)
			):
				return false
			if (
				layer.has("rotation_span")
				and (
					not Combat.valid_vector(layer.rotation_span)
					or not Combat.integer(layer.get("rotation_steps"))
					or layer.rotation_steps < 1
					or layer.rotation_steps > 1000000
				)
			):
				return false
		for cue in effect.sounds:
			if (
				not cue is Dictionary
				or not Combat.integer(cue.get("layer"))
				or cue.layer < 0
				or cue.layer >= effect.layers.size()
				or not Combat.integer(cue.get("sound"))
				or not library.content.sound_bank.has(str(int(cue.sound)))
				or cue.get("delay_ms") != effect.layers[int(cue.layer)].delay_ms
			):
				return false
	return true


static func brightness(effect: Dictionary, layer: Dictionary, clock_ms: float) -> float:
	return Destruction.brightness(effect, layer, clock_ms)


func configure(
	source_library,
	kind: int,
	pose: Transform3D,
	seed_value: int,
	start_ms: float = 0.0,
	restored: bool = false
) -> void:
	library = source_library
	definition = library.content.actor_destruction.effects[str(kind)]
	elapsed_ms = start_ms
	if restored:
		for index in definition.sounds.size():
			if definition.sounds[index].delay_ms <= start_ms:
				played[index] = true
	global_transform = pose
	var random = RandomNumberGenerator.new()
	random.seed = seed_value
	for layer in definition.layers:
		var mesh: MeshInstance3D = library.model(
			library.content.resources[str(int(layer.mesh))].path.get_file().get_basename()
		)
		var materials: Array = []
		for surface in mesh.mesh.get_surface_count():
			materials.append(mesh.get_active_material(surface).duplicate())
		mesh.material_override = null
		for surface in materials.size():
			mesh.set_surface_override_material(surface, materials[surface])
		mesh.rotation_order = EULER_ORDER_XYZ
		var rotation := Combat.vector(layer.rotation)
		var size: float = layer.scale
		if layer.has("scale_span"):
			size += (
				float(random.randi_range(0, int(layer.scale_steps) - 1))
				/ float(layer.scale_steps)
				* float(layer.scale_span)
			)
		if layer.has("rotation_span"):
			for axis in 3:
				rotation[axis] += (
					float(random.randi_range(0, int(layer.rotation_steps) - 1))
					/ float(layer.rotation_steps)
					* float(layer.rotation_span[axis])
				)
		mesh.rotation = rotation
		# Original translate adds world-space offsets after applying the ship pose.
		mesh.position = pose.basis.inverse() * Combat.vector(layer.offset)
		add_child(mesh)
		layers.append(mesh)
		appearances.append({"scale": size, "materials": materials})
	sync()


func advance(seconds: float) -> void:
	if finished or seconds <= 0 or not is_finite(seconds):
		return
	elapsed_ms += seconds * 1000.0
	sync()


func sync() -> void:
	if body != null:
		body.visible = elapsed_ms <= definition.hide_body_ms
	for index in definition.sounds.size():
		var cue: Dictionary = definition.sounds[index]
		if not played.has(index) and elapsed_ms >= cue.delay_ms:
			played[index] = true
			var player := preload("res://src/presentation/audio_settings.gd").effect_player()
			add_child(player)
			sounds.append(player)
			player.stream = library.sound_clip(int(cue.sound))
			player.volume_linear = library.content.sound_bank[str(int(cue.sound))].gain
			if player.stream != null and DisplayServer.get_name() != "headless":
				player.play()
	finished = true
	for index in layers.size():
		var node := layers[index]
		var layer: Dictionary = definition.layers[index]
		var alpha := brightness(definition, layer, elapsed_ms)
		var ended: bool = elapsed_ms >= layer.delay_ms and alpha <= definition.alpha_cutoff
		finished = finished and ended
		node.visible = elapsed_ms >= layer.delay_ms and not ended
		node.scale = (
			Vector3.ONE
			* maxf(.00001, float(appearances[index].scale) * Mines.envelope(layer, elapsed_ms))
		)
		for material in appearances[index].materials:
			if material is ShaderMaterial:
				material.set_shader_parameter("effect_brightness", alpha / 255.0)
			elif material is StandardMaterial3D:
				material.albedo_color = Color(alpha / 255.0, alpha / 255.0, alpha / 255.0)


func _exit_tree() -> void:
	for player in sounds:
		player.stop()
		player.stream = null
	for mesh in layers:
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, null)


func attach_body(node: Node3D) -> void:
	body = node
	body.reparent(self)
	body.visible = elapsed_ms <= definition.hide_body_ms
