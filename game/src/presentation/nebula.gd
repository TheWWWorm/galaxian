extends Node3D
## Deterministic native cloud composition using supplied texture, volume and colors.
## Cosmetic randomness is isolated from combat and restored from the mission seed.


func configure(library, definition: Dictionary, mission_seed: int, station: int) -> void:
	if not definition.has("fog"):
		return
	var fog: Dictionary = definition.fog
	var point: Array = fog.center if fog.has("center") else definition.route[int(fog.waypoint)]
	position = Vector3(point[0], point[1], -point[2]) * .02
	var texture: Texture2D = library.fog_texture(fog)
	var rng := RandomNumberGenerator.new()
	# Native procedural placement; no original PRNG state or executable is used.
	rng.seed = mission_seed
	var colors := RandomNumberGenerator.new()
	colors.seed = int(library.station_definition(station).system) * int(fog.color_seed)
	var choice := colors.randi_range(0, fog.palette.size() - 1)
	for index in int(fog.count):
		var cloud := Sprite3D.new()
		cloud.texture = texture
		cloud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		cloud.no_depth_test = false
		cloud.shaded = false
		cloud.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		cloud.pixel_size = (
			rng.randi_range(int(fog.size_min), int(fog.size_max)) * .02 / texture.get_width()
		)
		cloud.position = (
			Vector3(
				rng.randi_range(int(fog.scatter[0]), int(fog.scatter[1])),
				rng.randi_range(int(fog.scatter[0]), int(fog.scatter[1])),
				-rng.randi_range(int(fog.scatter[0]), int(fog.scatter[1]))
			)
			* .02
		)
		cloud.flip_h = rng.randi_range(0, 1) == 1
		cloud.flip_v = rng.randi_range(0, 1) == 1
		cloud.modulate = Color.hex(
			int(fog.palette[choice] if index < fog.primary_count else fog.secondary_palette[choice])
		)
		add_child(cloud)
