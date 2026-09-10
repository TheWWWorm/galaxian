extends Node3D
## Imported sky layers surround the camera at infinite depth. They never collide
## with ships and never consume the encounter random stream.
const SKY_SHADER = preload("res://src/presentation/backdrop.gdshader")
var declaration := {}
var random_state := 0
var random_parameters := {}


func configure(library, station_id: int, chapter: int = -1, arcade_seed: int = -1) -> void:
	declaration = select(library, station_id, chapter, arcade_seed)
	library.set_lighting(int(declaration.variant), int(declaration.style), station_id)
	var data: Dictionary = library.content.sky
	var color: Array = data.tints[int(declaration.style)]
	var tint := Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
	var layers := [
		[data.base_mesh, data.base_texture, data.blends[0], tint],
		[
			data.cloud_meshes[int(declaration.cloud)],
			data.cloud_texture,
			data.blends[1],
			Color.WHITE
		],
		[int(data.planet_base) + int(declaration.variant), data.base_texture, data.blends[2], tint],
		[
			int(data.sun_base) + int(declaration.variant),
			int(data.sun_texture_base) + int(declaration.style),
			data.blends[3],
			Color.WHITE
		]
	]
	for index in layers.size():
		var layer: Array = layers[index]
		var mesh_path: String = library.content.resources[str(int(layer[0]))].path
		var texture_path: String = library.content.radio_ui.textures[str(int(layer[1]))]
		var node := MeshInstance3D.new()
		node.mesh = library.mesh(mesh_path.get_file().get_basename())
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shader := SKY_SHADER
		if layer[2] == "add":
			shader = Shader.new()
			shader.code = SKY_SHADER.code.replace("blend_mix", "blend_add")
		var material := ShaderMaterial.new()
		material.shader = shader
		material.render_priority = -128 + index
		material.set_shader_parameter(
			"atlas", library.texture(texture_path.get_file().get_basename())
		)
		material.set_shader_parameter("tint", layer[3])
		material.set_shader_parameter("opaque", layer[2] != "mix")
		node.material_override = material
		add_child(node)


func select(library, station_id: int, chapter: int = -1, arcade_seed: int = -1) -> Dictionary:
	var data: Dictionary = library.content.sky
	random_parameters = data.random
	var mask := (1 << int(random_parameters.bits)) - 1
	random_state = (station_id * int(data.seed_multiplier) ^ int(random_parameters.seed_xor)) & mask
	if arcade_seed >= 0:
		# The source chooses a fresh sky per arcade run. Native saves retain the
		# run seed, so loading recreates its scenery without touching combat RNG.
		random_state = (arcade_seed ^ int(random_parameters.seed_xor)) & mask
		return {
			"variant": choose(int(data.variant_count)),
			"style": choose(data.tints.size()),
			"cloud": choose(data.cloud_meshes.size())
		}
	var variant: int = library.station_definition(station_id).image
	if chapter >= 0 and data.campaign_overrides[chapter] >= 0:
		variant = int(data.campaign_overrides[chapter])
	return {
		"variant": variant,
		"style": choose(data.tints.size()),
		"cloud": choose(data.cloud_meshes.size())
	}


func choose(count: int) -> int:
	# Standard LCG bounded sampling, implemented independently of the original
	# engine. Parameters come from the supplied declaration; signed overflow is
	# reduced by the mask before any output is used.
	var bits := int(random_parameters.output_bits)
	var mask := (1 << int(random_parameters.bits)) - 1
	while true:
		random_state = (
			(random_state * int(random_parameters.multiplier) + int(random_parameters.increment))
			& mask
		)
		var value := random_state >> (int(random_parameters.bits) - bits)
		if count & (count - 1) == 0:
			return (count * value) >> bits
		var result := value % count
		if value - result + count - 1 < (1 << bits):
			return result
	return 0


func follow(camera: Camera3D) -> void:
	global_position = camera.global_position
