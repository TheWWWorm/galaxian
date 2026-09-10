extends Node
## Cosmetic native envelope over the supplied nozzle meshes; Flight owns time.
const Combat = preload("res://src/simulation/combat.gd")
var data: Dictionary
var nozzles: Array[MeshInstance3D] = []
var phase := 0.0
var extension := 0.0
var boost_elapsed := 0.0
var boosting := false


static func valid_data(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in [
		"boost_threshold",
		"pulse_fraction",
		"normal_phase_rate",
		"boost_phase_rate",
		"attack_seconds",
		"attack_rate",
		"sustain_rate",
		"release_rate",
		"attack_limit",
		"sustain_limit",
		"width_extension",
		"minimum_fraction"
	]:
		if not Combat.number(value.get(key)) or value[key] <= 0 or value[key] > 1000000:
			return false
	return (
		value.pulse_fraction < 1
		and value.minimum_fraction <= 1
		and value.width_extension <= 1
		and value.attack_limit <= value.sustain_limit
	)


func configure(parameters: Dictionary, hull: MeshInstance3D) -> void:
	data = parameters
	for child in hull.get_children():
		if child is MeshInstance3D and child.has_meta("exhaust_scale"):
			nozzles.append(child)
	sync()


func advance(seconds: float, current_speed: float) -> void:
	if seconds <= 0 or not is_finite(seconds) or not is_finite(current_speed):
		return
	var active: bool = current_speed >= data.boost_threshold
	if active and not boosting:
		extension = 0.0
		boost_elapsed = 0.0
	boosting = active
	if boosting:
		# Split at the envelope boundary so large and small simulation steps agree.
		var attack := minf(seconds, maxf(0.0, data.attack_seconds - boost_elapsed))
		if attack > 0:
			extension = minf(data.attack_limit, extension + data.attack_rate * attack)
		if seconds > attack:
			extension = minf(data.sustain_limit, extension + data.sustain_rate * (seconds - attack))
		boost_elapsed += seconds
	else:
		extension = maxf(0.0, extension - data.release_rate * seconds)
	phase = fposmod(
		phase + seconds * float(data.boost_phase_rate if boosting else data.normal_phase_rate), TAU
	)
	sync()


func sync() -> void:
	var pulse: float = sin(phase) * data.pulse_fraction
	for nozzle in nozzles:
		if not is_instance_valid(nozzle):
			continue
		var base: Vector3 = nozzle.get_meta("exhaust_scale")
		nozzle.scale = Vector3(
			maxf(
				base.x * data.minimum_fraction,
				base.x * (1.0 + pulse) + extension * data.width_extension
			),
			maxf(
				base.y * data.minimum_fraction,
				base.y * (1.0 + pulse) + extension * data.width_extension
			),
			maxf(base.z * data.minimum_fraction, base.z * (1.0 + pulse) + extension)
		)
