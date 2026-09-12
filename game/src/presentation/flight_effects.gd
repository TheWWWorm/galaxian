extends Node3D
## Native, cosmetic flight feedback from imported declarations. No gameplay RNG.
const Combat = preload("res://src/simulation/combat.gd")
# Below this share of cruise the speed cue stops spawning. It is a judgement
# call, not a recovered constant: the imported geometry only fixes the floor
# below which a speck provably expires before reaching the camera, which is a
# third here, and specks still read as sluggish well above that. Reported as
# looking slow around this figure, so this is where the cue is cut.
const CUE_MINIMUM := .45
var data := {}
var particles: Array = []
var random := RandomNumberGenerator.new()
var pending := 0.0
var spawn_elapsed := 0.0
var spawned := 0


static func valid(value: Variant, materials: Dictionary, styles: Dictionary) -> bool:
	if (
		not value is Dictionary
		or not value.get("stars") is Dictionary
		or not value.get("trails") is Dictionary
	):
		return false
	if (
		not Combat.integer(value.get("boost_sound"))
		or value.boost_sound < 0
		or value.boost_sound > 255
	):
		return false
	for key in [
		"ramp_seconds", "plateau", "release_at", "end_at", "fov_degrees", "fov_boost_degrees"
	]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 120:
			return false
	if (
		value.plateau > value.release_at
		or value.release_at >= value.end_at
		or value.fov_degrees + value.fov_boost_degrees >= 170
	):
		return false
	var outro = value.get("outro")
	if not outro is Dictionary or not Combat.valid_vector(outro.get("camera_offset")) or Combat.vector(outro.camera_offset).length() > 10000:
		return false
	for key in ["settle_seconds", "music_delay"]:
		if not Combat.number(outro.get(key)) or outro[key] <= 0 or outro[key] > 60:
			return false
	if not Combat.integer(outro.get("music")) or outro.music < 0 or outro.music > 255:
		return false
	var opacity = value.get("button_opacity")
	if not opacity is Dictionary:
		return false
	for key in ["boost_active", "boost_base", "boost_gain", "missile_unavailable"]:
		if not Combat.number(opacity.get(key)) or opacity[key] < 0 or opacity[key] > 1:
			return false
	var stars: Dictionary = value.stars
	if not Combat.integer(stars.get("count")) or stars.count < 1 or stars.count > 200:
		return false
	if not Combat.integer(stars.get("material")) or not materials.has(str(int(stars.material))):
		return false
	for key in [
		"reference_seconds",
		"half_width",
		"half_length",
		"boost_width",
		"boost_length",
		"boost_speed",
		"boost_speed_base",
		"normal_speed_min",
		"normal_speed_range",
		"spawn_depth",
		"normal_interval",
		"normal_lifetime",
		"boost_lifetime"
	]:
		if not Combat.number(stars.get(key)) or stars[key] < 0 or stars[key] > 100000:
			return false
	if (
		stars.reference_seconds <= 0
		or stars.normal_interval <= 0
		or stars.normal_lifetime <= 0
		or stars.boost_lifetime <= 0
	):
		return false
	for key in ["spawn_x", "spawn_y"]:
		if (
			not stars.get(key) is Array
			or stars[key].size() != 2
			or not stars[key].all(func(v): return Combat.number(v) and absf(v) < 100000)
			or stars[key][1] <= 0
		):
			return false
	if not stars.get("uv") is Array or stars.uv.is_empty() or stars.uv.size() > 16:
		return false
	for rect in stars.uv:
		if (
			not rect is Array
			or rect.size() != 4
			or not rect.all(func(v): return Combat.number(v) and v >= 0 and v <= 1)
			or rect[0] >= rect[2]
			or rect[1] >= rect[3]
		):
			return false
	var trails: Dictionary = value.trails
	for key in ["enemy", "ally", "double_style", "marked_style"]:
		if not Combat.integer(trails.get(key)) or not styles.has(str(int(trails[key]))):
			return false
	for key in [
		"segments", "double_segments", "double_actor", "forced_ally_actor", "forced_ally_chapter"
	]:
		if not Combat.integer(trails.get(key)) or trails[key] < 0 or trails[key] > 4096:
			return false
	if (
		trails.segments < 1
		or trails.double_segments < 1
		or not Combat.number(trails.get("interval"))
		or trails.interval <= 0
		or trails.interval > 1
	):
		return false
	for key in ["excluded", "survival_limits", "survival_styles"]:
		if (
			not trails.get(key) is Array
			or trails[key].is_empty()
			or trails[key].size() > 32
			or not trails[key].all(func(v): return Combat.integer(v) and v >= 0)
		):
			return false
	if (
		trails.survival_limits.size() != 2
		or trails.survival_styles.size() != 3
		or trails.survival_limits[0] >= trails.survival_limits[1]
	):
		return false
	for style in trails.survival_styles:
		if not styles.has(str(int(style))):
			return false
	if not trails.get("double_offsets") is Array or trails.double_offsets.size() != 2:
		return false
	for offset in trails.double_offsets:
		if (
			not offset is Array
			or offset.size() != 3
			or not offset.all(func(v): return Combat.number(v) and absf(v) < 100000)
		):
			return false
	return true


static func cue_threshold(stars: Dictionary) -> float:
	## These specks run fifteen to thirty times faster than the hull itself, so
	## they are a speed cue, not matter the ship passes. A speck that cannot
	## reach the camera inside its life visibly expires on screen, which the
	## imported spawn depth, slowest speed and lifetime place at a third of
	## cruise. Sluggish motion starts well above that, so the calibrated minimum
	## normally decides; the imported floor only guards unusual content.
	var span: float = float(stars.normal_speed_min) * float(stars.normal_lifetime)
	var floor_ratio: float = (
		clampf(float(stars.spawn_depth) / span, 0.0, 1.0) if span > 0 else 0.0
	)
	return maxf(CUE_MINIMUM, floor_ratio)


static func percentage(parameters: Dictionary, elapsed: float) -> float:
	var phase := maxf(0.0, elapsed) / float(parameters.ramp_seconds)
	if phase <= float(parameters.plateau):
		return phase
	if phase <= float(parameters.release_at):
		return parameters.plateau
	return clampf(float(parameters.end_at) - phase, 0.0, parameters.plateau)


static func field_of_view(parameters: Dictionary, elapsed: float, boosting: bool) -> float:
	return (
		parameters.fov_degrees
		+ parameters.fov_boost_degrees * (percentage(parameters, elapsed) if boosting else 0.0)
	)


func configure(library) -> void:
	data = library.content.flight_effects.stars
	random.randomize()
	var meshes := []
	for uv in data.uv:
		meshes.append(star_mesh(uv))
	for index in int(data.count):
		var node := MeshInstance3D.new()
		node.mesh = meshes[random.randi_range(0, meshes.size() - 1)]
		node.material_override = library.material(int(data.material))
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.hide()
		particles.append({"node": node, "life": 0.0, "speed": 0.0})


static func star_mesh(uv: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var coords := PackedVector2Array()
	var indices := PackedInt32Array()
	# Two crossed streak planes and a cap, using the three supplied atlas sprites.
	for quad in [
		[Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1)],
		[Vector3(0, -1, -1), Vector3(0, -1, 1), Vector3(0, 1, -1), Vector3(0, 1, 1)],
		[Vector3(-1, -1, 0), Vector3(-1, 1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0)]
	]:
		var base := vertices.size()
		vertices.append_array(quad)
		coords.append_array(
			PackedVector2Array(
				[
					Vector2(uv[0], uv[1]),
					Vector2(uv[0], uv[3]),
					Vector2(uv[2], uv[1]),
					Vector2(uv[2], uv[3])
				]
			)
		)
		indices.append_array(
			PackedInt32Array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
		)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = coords
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func advance(
	seconds: float, pose: Transform3D, boosting: bool, amount: float, travel: float = 1.0
) -> void:
	if seconds <= 0 or not is_finite(seconds):
		return
	# The supplied field drifts at a fixed rate because the original hull always
	# cruises. Throttle is a remake control, so the cue follows the actual speed.
	# Boost keeps its imported rate.
	var rate: float = 1.0 if boosting else clampf(travel, 0.0, 1.0)
	var threshold := cue_threshold(data)
	var drift: float = 1.0 if boosting else maxf(rate, threshold)
	var cue: bool = boosting or rate >= threshold
	if rate <= 0:
		# Slowing past the threshold already empties the field on its own. This
		# is the backstop for reaching a standstill before that finishes, so a
		# stopped ship never keeps a speck it can no longer be moving past.
		for particle in particles:
			particle.node.hide()
			particle.life = 0.0
		pending = 0.0
		spawn_elapsed = float(data.normal_interval)
		return
	pending += seconds
	while pending + .000000001 >= float(data.reference_seconds):
		var dt: float = data.reference_seconds
		pending = maxf(0, pending - dt)
		spawn_elapsed += dt
		var can_spawn: bool = boosting or (cue and spawn_elapsed >= float(data.normal_interval))
		for particle in particles:
			particle.life -= dt
			if particle.life <= 0:
				particle.node.hide()
				if not can_spawn:
					continue
				can_spawn = false
				spawn_elapsed = 0.0
				spawned += 1
				particle.node.transform = pose
				particle.node.position = (
					pose
					* Vector3(
						data.spawn_x[0] + random.randf() * data.spawn_x[1],
						data.spawn_y[0] + random.randf() * data.spawn_y[1],
						-data.spawn_depth
					)
				)
				particle.life = data.boost_lifetime if boosting else data.normal_lifetime
				particle.speed = (
					data.boost_speed_base + data.boost_speed * amount
					if boosting
					else data.normal_speed_min + random.randf() * data.normal_speed_range
				)
				particle.node.show()
			else:
				if boosting:
					particle.speed = data.boost_speed_base + data.boost_speed * amount
				particle.node.position += (
					particle.node.basis.z.normalized() * particle.speed * drift * dt
				)
			var width: float = data.half_width + (data.boost_width * amount if boosting else 0.0)
			# The supplied boost stretches length alone and leaves width at zero
			# gain, so length is the speed smear and width is the speck. Throttle
			# scales the smear the same way, at the rate the speck is drifting.
			var length: float = (
				data.half_length + data.boost_length * amount
				if boosting
				else data.half_length * drift
			)
			particle.node.scale = Vector3(width, width, length)
