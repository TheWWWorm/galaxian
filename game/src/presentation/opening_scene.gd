extends Node3D
## Opening presentation only. No Session reference, combat, rewards or page timer.
signal fade_changed(alpha: float)
const Choreography = preload("res://src/presentation/opening_choreography.gd")
const Combat = preload("res://src/simulation/combat.gd")
const Mission = preload("res://src/simulation/mission.gd")
var choreography = Choreography.new()
var library
var chapter := 0
var station_id := -1
var ship_id := -1
var offers: Array = []
var outdoor: Node3D
var area: Node3D
var backdrop: Node3D
var ship: MeshInstance3D
var burner
var camera: Camera3D
var hangar: Node3D
var flare_layer: CanvasLayer
var flare: Control
var supported := false
var error := ""


func configure(source, chapter_index: int, location: int, player_ship: int, stock: Array, page := 0) -> bool:
	library = source
	chapter = chapter_index
	station_id = location
	ship_id = player_ship
	offers = stock.duplicate(true)
	choreography.configure(library.content.briefing_scene.opening,page)
	visibility_changed.connect(sync_visibility)
	if choreography.stage != "hangar" and not create_outdoor(): return false
	if not sync_scene(): return false
	supported = true
	return true


func create_outdoor() -> bool:
	outdoor = Node3D.new()
	add_child(outdoor)
	var random := RandomNumberGenerator.new()
	random.seed = hash(library.id+":opening:"+str(station_id))
	area = preload("res://src/presentation/station_area.gd").new()
	outdoor.add_child(area)
	if not area.configure(library,library.briefing_station_type(chapter,station_id),random):
		error = area.error
		return false
	backdrop = preload("res://src/presentation/backdrop.gd").new()
	outdoor.add_child(backdrop)
	backdrop.configure(library,station_id,chapter)
	camera = Camera3D.new()
	outdoor.add_child(camera)
	var data: Dictionary = choreography.data
	camera.fov = float(data.fov_units)*360/65536.0
	camera.near = float(data.near)*.02
	camera.far = float(data.far)*.02
	ship = library.model(library.actor_model(int(data.actor)))
	outdoor.add_child(ship)
	if ship.mesh == null:
		error = library.error
		return false
	library.attach_ship_exhaust(ship,int(data.actor))
	burner = preload("res://src/presentation/npc_exhaust.gd").new()
	ship.add_child(burner)
	burner.configure(library.content.npc_exhaust,ship)
	flare_layer = CanvasLayer.new()
	flare_layer.layer = 0
	add_child(flare_layer)
	flare = preload("res://src/presentation/lens_flare.gd").new()
	flare_layer.add_child(flare)
	flare.configure(library,camera,backdrop.declaration)
	return true


func present(page: int) -> void:
	if not supported: return
	choreography.present(page)
	sync_scene()


func _process(seconds: float) -> void:
	advance(seconds)


func advance(seconds: float) -> void:
	if not supported or not is_visible_in_tree() or not is_finite(seconds) or seconds <= 0: return
	choreography.advance(seconds)
	if not sync_scene():
		supported = false
		push_error(error)
		return
	if hangar != null:
		# The shot clock includes only the portion after the fade's scene switch.
		var delta := maxf(0,choreography.shot_elapsed-hangar.elapsed)
		hangar.advance(delta)
	else:
		area.station.set_elapsed(choreography.elapsed*1000)
		burner.advance(seconds,0.0)
		var strength := clampf((float(choreography.data.stop_z)-choreography.ship_z)/(float(choreography.data.stop_z)-float(choreography.data.slow_start)),0,1)
		for nozzle in burner.nozzles:
			nozzle.visible = strength > .001
			nozzle.scale.z *= strength


func sync_scene() -> bool:
	var pose: Dictionary = choreography.pose()
	if pose.hangar:
		if hangar == null:
			hangar = preload("res://src/presentation/hangar_scene.gd").new()
			add_child(hangar)
			hangar.set_process(false)
			if not hangar.configure(library,station_id,ship_id,offers):
				error = hangar.error
				return false
			if outdoor != null:
				outdoor.hide()
				outdoor.queue_free()
				outdoor = null
		camera = hangar.camera
	else:
		area.station.position = Mission.point(Combat.packed(pose.station))
		ship.position = Mission.point(Combat.packed(pose.ship))
		ship.visible = pose.ship_visible
		camera.position = Mission.point(Combat.packed(pose.camera))
		var direction := Mission.point(Combat.packed(pose.direction)).normalized()
		camera.look_at(camera.global_position+direction)
		backdrop.follow(camera)
	camera.current = true
	sync_visibility()
	fade_changed.emit(pose.fade)
	return true


func sync_visibility() -> void:
	if flare_layer != null:
		flare_layer.visible = is_visible_in_tree() and hangar == null
		flare.set_process(flare_layer.visible)
