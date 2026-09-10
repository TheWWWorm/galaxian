extends Node3D
## Ship-owned lifetime, world-space samples: turns never rotate old trail points.
const Ribbon = preload("res://src/presentation/projectile_trail.gd")
var data := {}
var ribbons: Array = []
var offsets: Array[Vector3] = []
var elapsed := 0.0
var previous := Transform3D.IDENTITY
var initialized := false


static func declarations(
	parameters: Dictionary, actor_type: int, enemy: bool, chapter: int, archetype: int = -1
) -> Array:
	if parameters.excluded.any(func(value): return int(value) == actor_type):
		return []
	var style: int = parameters.enemy if enemy else parameters.ally
	if (
		actor_type == int(parameters.double_actor)
		or (
			actor_type == int(parameters.forced_ally_actor)
			and chapter == int(parameters.forced_ally_chapter)
		)
	):
		style = int(parameters.ally)
	var color_style := style
	if archetype >= 0:
		var tier := 0
		for limit in parameters.survival_limits:
			if archetype > limit:
				tier += 1
		color_style = int(parameters.survival_styles[tier])
	var result := [
		{
			"style": style,
			"color_style": color_style,
			"segments": int(parameters.segments),
			"offset": Vector3.ZERO
		}
	]
	if actor_type == int(parameters.double_actor):
		result[0].offset = source_point(parameters.double_offsets[0])
		result.append(
			{
				"style": int(parameters.double_style),
				"segments": int(parameters.double_segments),
				"offset": source_point(parameters.double_offsets[1])
			}
		)
	return result


static func source_point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], -value[2]) * .02


func configure(library, declaration: Array, initial: Transform3D) -> void:
	data = library.content.flight_effects.trails
	set_as_top_level(true)
	global_transform = Transform3D.IDENTITY
	previous = initial
	initialized = true
	for item in declaration:
		var ribbon := Ribbon.new()
		add_child(ribbon)
		ribbon.configure(library, item, initial * item.offset)
		# Source changeTrailColor changes tint without rebuilding the UV region.
		ribbon.tint = Color.hex(
			int(
				(
					library
					. content
					. projectile_trails
					. styles[str(int(item.get("color_style", item.style)))]
					. color
				)
			)
		)
		ribbons.append(ribbon)
		offsets.append(item.offset)


func advance(seconds: float, pose: Transform3D) -> void:
	if seconds <= 0 or not initialized:
		return
	var interval: float = data.interval
	var first := interval - elapsed
	elapsed += seconds
	var offset := first
	while elapsed + .000000001 >= interval:
		elapsed = maxf(0, elapsed - interval)
		var sampled := previous.interpolate_with(pose, clampf(offset / seconds, 0, 1))
		for index in ribbons.size():
			ribbons[index].advance(sampled * offsets[index])
		offset += interval
	previous = pose
