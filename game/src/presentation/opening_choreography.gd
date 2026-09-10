extends RefCounted
## Native shot controller. Text pages stay manual and never run mission simulation.
const Combat = preload("res://src/simulation/combat.gd")
var data: Dictionary
var page := 0
var stage := "pan"
var elapsed := 0.0
var shot_elapsed := 0.0
var alpha := 1.0
var fade_direction := -1
var pending_stage := ""
var ship_z := 0.0
var fixed_camera := Vector3.ZERO
var fixed_direction := Vector3.FORWARD


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["pan_range", "station_range", "ship_height"]:
		if not value.get(key) is Array or value[key].size() != 2 or not value[key].all(func(v): return Combat.number(v) and absf(v) <= 1000000):
			return false
		if value[key][0] >= value[key][1]: return false
	for key in ["pan_camera", "station_camera", "station_position", "ship_camera"]:
		if not Combat.valid_vector(value.get(key)): return false
	for key in ["actor", "station_page", "ship_page", "departure_page", "hangar_page", "fov_units", "near", "far"]:
		if not Combat.integer(value.get(key)) or value[key] < 0: return false
	for key in ["ease_seconds", "fade_seconds", "pan_start_seconds", "yaw_scale", "station_rate", "initial_station_z", "initial_ship_z", "ship_speed", "slow_start", "stop_z", "slow_seconds", "departure_min_z", "departure_snap_z", "camera_ready_margin"]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000: return false
	return (
		value.station_page < value.ship_page and value.ship_page < value.departure_page
		and value.departure_page < value.hangar_page and value.hangar_page < 64
		and value.slow_start < value.stop_z and value.departure_min_z < value.departure_snap_z
		and value.fov_units > 0 and value.fov_units < 32768 and value.near > 0 and value.near < value.far
	)


func configure(parameters: Dictionary, initial_page := 0) -> void:
	data = parameters
	page = maxi(0,initial_page)
	stage = stage_for_page(page)
	elapsed = 0
	shot_elapsed = float(data.pan_start_seconds) if stage == "pan" else 0.0
	ship_z = float(data.initial_ship_z) if stage in ["pan","station"] else 0.0
	alpha = 1
	fade_direction = -1
	pending_stage = ""
	# Reload reconstructs a settled shot appropriate to the saved page. It does
	# not replay text, invent elapsed campaign time, or save cosmetic state.
	if stage == "departure":
		ship_z = data.departure_snap_z
		freeze_camera()


func stage_for_page(value: int) -> String:
	if value >= data.hangar_page: return "hangar"
	if value >= data.departure_page: return "departure"
	if value >= data.ship_page: return "ship"
	if value >= data.station_page: return "station"
	return "pan"


func present(value: int) -> void:
	if value <= page: return
	page = value
	var next := stage_for_page(page)
	if next == stage: return
	if not pending_stage.is_empty():
		pending_stage = next
		return
	var must_fade: bool = next == "hangar"
	if next == "station":
		must_fade = shot_elapsed < data.ease_seconds
	elif next == "departure":
		must_fade = current_height() < float(data.ship_height[1]) - float(data.camera_ready_margin)
	if must_fade:
		pending_stage = next
		fade_direction = 1
	else:
		enter(next)


func enter(next: String) -> void:
	stage = next
	shot_elapsed = 0
	if stage == "ship": ship_z = 0
	if stage == "departure":
		if ship_z <= data.departure_min_z: ship_z = data.departure_snap_z
		freeze_camera()


func curve(from: float, to: float, seconds: float, rate := 1.0) -> float:
	var t := clampf(seconds * rate / float(data.ease_seconds),0,1)
	return lerpf(from,to,(1-cos(PI*t))*.5)


func current_height() -> float:
	return curve(data.ship_height[0],data.ship_height[1],shot_elapsed)


func freeze_camera() -> void:
	fixed_camera = Combat.vector(data.ship_camera)
	fixed_camera.y = data.ship_height[1]
	fixed_direction = (Vector3(0,0,ship_z)-fixed_camera).normalized()


func advance(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0: return
	var remaining := seconds
	while remaining > .000000001:
		var step := remaining
		if fade_direction != 0:
			var fraction := 1-alpha if fade_direction > 0 else alpha
			step = minf(step, fraction * float(data.fade_seconds))
		elapsed += step
		shot_elapsed += step
		if stage in ["ship","departure"]:
			advance_ship(step)
		remaining = maxf(0,remaining-step)
		if fade_direction != 0:
			alpha = clampf(alpha + fade_direction * step / float(data.fade_seconds),0,1)
			if fade_direction > 0 and alpha >= 1-.000000001:
				alpha = 1
				enter(pending_stage)
				pending_stage = ""
				fade_direction = -1
			elif fade_direction < 0 and alpha <= .000000001:
				alpha = 0
				fade_direction = 0


func advance_ship(seconds: float) -> void:
	# Constant approach speed followed by exponential braking, solved over time
	# rather than copying the original per-frame integer translation loop.
	var remaining := seconds
	if ship_z < data.slow_start:
		var step := minf(remaining,(float(data.slow_start)-ship_z)/float(data.ship_speed))
		ship_z += step * float(data.ship_speed)
		remaining -= step
	if remaining > 0 and ship_z < data.stop_z:
		ship_z = float(data.stop_z) - (float(data.stop_z)-ship_z)*exp(-remaining/float(data.slow_seconds))


func pose() -> Dictionary:
	var position: Vector3
	var direction: Vector3
	var station := Vector3(0,0,data.initial_station_z)
	if stage in ["pan","station"]:
		var values: Array = data.pan_range if stage == "pan" else data.station_range
		var value := curve(values[0],values[1],shot_elapsed,1.0 if stage == "pan" else float(data.station_rate))
		var yaw := -value * float(data.yaw_scale) * TAU / 65536.0
		position = Combat.vector(data.pan_camera if stage == "pan" else data.station_camera)
		# Source camera looks opposite its stored direction column.
		direction = Vector3(-sin(yaw),0,-cos(yaw))
	else:
		position = Combat.vector(data.ship_camera)
		position.y = current_height()
		direction = (Vector3(0,0,ship_z)-position).normalized()
	if stage != "pan": station = Combat.vector(data.station_position)
	if stage == "departure":
		position = fixed_camera
		direction = fixed_direction
	return {"camera":position,"direction":direction,"station":station,"ship":Vector3(0,0,ship_z),"ship_visible":stage in ["ship","departure"],"hangar":stage=="hangar","fade":alpha}
