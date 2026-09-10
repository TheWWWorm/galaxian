extends Node3D
signal sound_requested(id: int)
const Mines = preload("res://src/simulation/mines.gd")
var arm_played := false
var shot_played := false
var played := {}
var parameters: Dictionary
var closed: MeshInstance3D
var armed := Node3D.new()
var layers: Array[MeshInstance3D] = []
var materials: Array[Material] = []


func configure(library, state: Dictionary) -> void:
	parameters = library.content.mine_behavior
	# A restored phase is already underway. Keep future layer cues only.
	arm_played = state.phase != "dormant"
	shot_played = state.phase in ["shot", "burst", "dead"]
	for index in parameters.explosion.sounds.size():
		if (
			state.phase == "dead"
			or (
				state.phase in ["shot", "burst"]
				and state.elapsed_ms >= parameters.explosion.sounds[index].delay_ms
			)
		):
			played[index] = true
	closed = library.model(library.actor_model(int(parameters.actor)))
	add_child(closed)
	add_child(armed)
	for id in parameters.armed_meshes:
		armed.add_child(
			library.model(library.content.resources[str(int(id))].path.get_file().get_basename())
		)
	for layer in parameters.explosion.layers:
		var mesh: MeshInstance3D = library.model(
			library.content.resources[str(int(layer.mesh))].path.get_file().get_basename()
		)
		add_child(mesh)
		for surface in mesh.mesh.get_surface_count():
			# Each fading instance owns its material; shared imported resources
			# remain untouched when several mines explode at different times.
			var material: Material = mesh.get_active_material(surface).duplicate()
			materials.append(material)
			mesh.set_surface_override_material(surface, material)
		mesh.material_override = null
		layers.append(mesh)
	sync(state)


func sync(state: Dictionary, event: Dictionary = {}) -> void:
	# Explicit events preserve dormant -> armed -> burst in one large step.
	if not arm_played and (event.get("armed", false) or state.phase == "armed"):
		arm_played = true
		sound_requested.emit(int(parameters.arm_sound))
	if not shot_played and state.phase == "shot":
		shot_played = true
		sound_requested.emit(int(parameters.shot_sound))
	if state.phase in ["shot", "burst", "dead"]:
		for index in parameters.explosion.sounds.size():
			var cue: Dictionary = parameters.explosion.sounds[index]
			if (
				not played.has(index)
				and (state.phase == "dead" or state.elapsed_ms >= cue.delay_ms)
			):
				played[index] = true
				sound_requested.emit(int(cue.sound))
	closed.visible = state.phase == "dormant"
	armed.visible = state.phase == "armed"
	if armed.visible:
		var progress := float(state.elapsed_ms) / float(parameters.fuse_ms)
		# Native time-based warning spin, independent of display frame rate.
		armed.rotation = Vector3.ONE * TAU * progress * progress
	for index in layers.size():
		var node: MeshInstance3D = layers[index]
		var layer: Dictionary = parameters.explosion.layers[index]
		var brightness := Mines.alpha(parameters.explosion, layer, float(state.elapsed_ms))
		node.visible = (
			state.phase in ["shot", "burst"]
			and float(state.elapsed_ms) >= float(layer.delay_ms)
			and brightness > float(parameters.explosion.alpha_cutoff)
		)
		if not node.visible:
			continue
		node.scale = (
			Vector3.ONE
			* maxf(.00001, float(layer.scale) * Mines.envelope(layer, float(state.elapsed_ms)))
		)
		for surface in node.mesh.get_surface_count():
			var material := node.get_surface_override_material(surface)
			if material is ShaderMaterial:
				material.set_shader_parameter("effect_brightness", brightness / 255.0)
			elif material is StandardMaterial3D:
				material.albedo_color = Color(
					brightness / 255.0, brightness / 255.0, brightness / 255.0
				)


func _exit_tree() -> void:
	# Detach overrides while their material RIDs still exist. This also avoids
	# renderer dependency updates referring to an already-freed last instance.
	for layer in layers:
		for surface in layer.mesh.get_surface_count():
			layer.set_surface_override_material(surface, null)


static func valid_audio(value: Variant, sounds: Variant) -> bool:
	if not value is Dictionary or not sounds is Dictionary:
		return false
	for key in ["arm_sound", "shot_sound"]:
		if not Mines.integer(value.get(key)) or not sounds.has(str(int(value[key]))):
			return false
	var effect = value.get("explosion")
	if (
		not effect is Dictionary
		or not effect.get("layers") is Array
		or not effect.get("sounds") is Array
	):
		return false
	if effect.sounds.is_empty() or effect.sounds.size() > effect.layers.size():
		return false
	var seen := {}
	for cue in effect.sounds:
		if not cue is Dictionary or not Mines.integer(cue.get("layer")):
			return false
		var index := int(cue.layer)
		if index < 0 or index >= effect.layers.size() or seen.has(index):
			return false
		if not Mines.integer(cue.get("sound")) or not sounds.has(str(int(cue.sound))):
			return false
		if not Mines.number(cue.get("delay_ms")) or cue.delay_ms != effect.layers[index].delay_ms:
			return false
		seen[index] = true
	return true
