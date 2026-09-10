extends Node3D
## Native presentation clock only; briefing pages and pilot state remain manual.
const Backdrop = preload("res://src/presentation/backdrop.gd")
const Combat = preload("res://src/simulation/combat.gd")
var camera: Camera3D
var station
var field: Node3D
var backdrop: Node3D
var flare_layer: CanvasLayer
var lens_flare: Control
var elapsed_ms := 0.0
var drift := Vector3.ZERO
var error := ""
var supported := false


func configure(library, chapter: int, station_id: int) -> bool:
	var data: Dictionary = library.content.briefing_scene
	var definition: Dictionary = data.chapters[chapter]
	if definition.kind != "station":
		return false
	var random := RandomNumberGenerator.new()
	# Stable native presentation sampling; no campaign encounter random stream.
	random.seed = hash(library.id + ":briefing:" + str(chapter) + ":" + str(station_id))
	var area := preload("res://src/presentation/station_area.gd").new()
	add_child(area)
	if not area.configure(library, library.briefing_station_type(chapter, station_id), random):
		error = area.error
		return false
	station = area.station
	field = area.field
	backdrop = Backdrop.new()
	add_child(backdrop)
	backdrop.configure(library, station_id, -1 if definition.location_station else chapter)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Combat.vector(data.camera_position) * Vector3(1, 1, -1) * .02
	camera.fov = float(data.fov_units) * 360.0 / 65536.0
	camera.near = float(data.near) * .02
	camera.far = float(data.far) * .02
	camera.look_at(station.position)
	camera.current = true
	backdrop.follow(camera)
	flare_layer = CanvasLayer.new()
	flare_layer.layer = 0
	add_child(flare_layer)
	lens_flare = preload("res://src/presentation/lens_flare.gd").new()
	flare_layer.add_child(lens_flare)
	lens_flare.configure(library, camera, backdrop.declaration)
	visibility_changed.connect(sync_flare_visibility)
	sync_flare_visibility()
	drift = Combat.vector(definition.field_velocity) * Vector3(1, 1, -1) * .02
	supported = true
	return true


func _process(delta: float) -> void:
	if supported:
		backdrop.follow(camera)
	advance(delta * 1000.0)


func sync_flare_visibility() -> void:
	# CanvasLayer visibility is independent of the owning 3D scene.
	flare_layer.visible = is_visible_in_tree()
	lens_flare.set_process(flare_layer.visible)


func advance(milliseconds: float) -> void:
	if not supported or not is_finite(milliseconds) or milliseconds <= 0:
		return
	elapsed_ms += milliseconds
	station.set_elapsed(elapsed_ms)
	field.position = drift * elapsed_ms
