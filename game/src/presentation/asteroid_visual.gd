extends Node3D
const Scenery = preload("res://src/simulation/scenery.gd")
const Combat = preload("res://src/simulation/combat.gd")
var parameters := {}
var body: MeshInstance3D
var fragments: Array[MeshInstance3D] = []
var layers: Array[MeshInstance3D] = []
var materials: Array[Material] = []
var rock_scale := 1.0
var source_library
var sound_due := false
var audio: AudioStreamPlayer


static func valid_audio(value: Variant, sounds: Variant) -> bool:
	if not value is Dictionary or not sounds is Dictionary:
		return false
	var cue = value.get("audio")
	return (
		cue is Dictionary
		and Combat.integer(cue.get("sound"))
		and sounds.has(str(int(cue.sound)))
		and Combat.number(cue.get("delay_ms"))
		and cue.delay_ms >= 0
		and cue.delay_ms <= 1000000
		and value.get("effect") is Dictionary
		and value.effect.get("layers") is Array
		and not value.effect.layers.is_empty()
		and cue.delay_ms == value.effect.layers[0].delay_ms
	)


func configure(library, field: Dictionary, state: Dictionary) -> void:
	source_library = library
	parameters = field.get("destruction", {})
	# Restore future cues, but never replay a stage whose start time has passed.
	sound_due = (
		state.hits > 0
		or (
			not state.destroyed
			and not parameters.is_empty()
			and state.destruction_ms < parameters.audio.delay_ms
		)
	)
	rock_scale = float(state.scale)
	body = model(int(field.model))
	if field.has("rotation_bound"):
		body.rotation_order = EULER_ORDER_XYZ
	body.rotation = Combat.vector(state.rotation)
	body.scale = Vector3.ONE * rock_scale
	add_child(body)
	sync(state)


func model(id: int) -> MeshInstance3D:
	return source_library.model(
		source_library.content.resources[str(id)].path.get_file().get_basename()
	)


func build_effect() -> void:
	# Allocate effects only for a destroyed rock, not six materials per live rock
	# throughout every campaign and exploration asteroid field.
	for id in parameters.fragment_meshes:
		var fragment := model(int(id))
		fragment.scale = Vector3.ONE * rock_scale
		add_child(fragment)
		fragments.append(fragment)
	for layer in parameters.effect.layers:
		var mesh := model(int(layer.mesh))
		mesh.rotation = Combat.vector(layer.rotation)
		add_child(mesh)
		for surface in mesh.mesh.get_surface_count():
			var material: Material = mesh.get_active_material(surface).duplicate()
			materials.append(material)
			mesh.set_surface_override_material(surface, material)
		mesh.material_override = null
		layers.append(mesh)


func sync(state: Dictionary) -> void:
	body.visible = state.hits > 0
	if (
		sound_due
		and state.hits <= 0
		and not parameters.is_empty()
		and (state.destroyed or state.destruction_ms >= parameters.audio.delay_ms)
	):
		sound_due = false
		audio = preload("res://src/presentation/audio_settings.gd").effect_player()
		add_child(audio)
		audio.stream = source_library.sound_clip(int(parameters.audio.sound))
		audio.volume_linear = (
			source_library.content.sound_bank[str(int(parameters.audio.sound))].gain
		)
		if audio.stream != null and DisplayServer.get_name() != "headless":
			audio.play()
	var active: bool = state.hits <= 0 and not state.destroyed and not parameters.is_empty()
	if active and layers.is_empty():
		build_effect()
	for index in fragments.size():
		var fragment := fragments[index]
		fragment.visible = active and state.destruction_ms <= parameters.fragment_duration_ms
		fragment.position = (
			Combat.vector(parameters.fragment_velocity[index])
			* float(state.destruction_ms)
			/ 1000.0
		)
		fragment.rotation = (
			Combat.vector(parameters.fragment_spin) * float(state.destruction_ms) / 1000.0
		)
	for index in layers.size():
		var node := layers[index]
		var layer: Dictionary = parameters.effect.layers[index]
		var brightness := Scenery.Mines.alpha(parameters.effect, layer, float(state.destruction_ms))
		node.visible = (
			active
			and state.destruction_ms >= layer.delay_ms
			and brightness > parameters.effect.alpha_cutoff
		)
		if not node.visible:
			continue
		node.scale = (
			Vector3.ONE
			* maxf(.00001, layer.scale * Scenery.Mines.envelope(layer, state.destruction_ms))
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
	if audio != null:
		audio.stop()
		audio.stream = null
	for layer in layers:
		for surface in layer.mesh.get_surface_count():
			layer.set_surface_override_material(surface, null)
