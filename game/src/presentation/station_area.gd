extends Node3D
## Source station-approach geometry shared by briefings and native exploration.
const Combat = preload("res://src/simulation/combat.gd")
var station
var field: Node3D
var error := ""
var kind := -1


func configure(
	library, station_kind: int, random: RandomNumberGenerator, saved: Dictionary = {}
) -> bool:
	kind = station_kind
	var data: Dictionary = library.content.briefing_scene
	var bound := int(library.content.station_models.tilt_bound)
	station = library.station_model(
		kind,
		(
			Vector2i(saved.tilt[0], saved.tilt[1])
			if not saved.is_empty()
			else Vector2i(random.randi_range(0, bound - 1), random.randi_range(0, bound - 1))
		)
	)
	if not station.error.is_empty():
		error = station.error
		station.free()
		station = null
		return false
	add_child(station)
	station.position = (
		Vector3(0, 0, -(data.special_z if kind == data.special_type else data.station_z)) * .02
	)
	field = Node3D.new()
	add_child(field)
	var rocks: Dictionary = data.field
	var state: Dictionary = (
		saved.scenery
		if not saved.is_empty()
		else preload("res://src/simulation/exploration_area.gd").sample(rocks, random)
	)
	for rock in state.rocks:
		var node = preload("res://src/presentation/asteroid_visual.gd").new()
		node.configure(library, rocks, rock)
		if node.body.mesh == null:
			error = library.error
			node.free()
			return false
		node.position = Combat.vector(rock.position)
		field.add_child(node)
	return true
