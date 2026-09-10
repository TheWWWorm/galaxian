extends RefCounted
## Native mine lifecycle. The importer supplies proximity, fuse, damage, meshes
## and effect envelopes; saves contain only phase and elapsed simulation time.


static func create() -> Dictionary:
	return {"phase": "dormant", "elapsed_ms": 0.0, "blast_delta": [0.0, 0.0, 0.0]}


static func active(state: Dictionary) -> bool:
	return state.phase in ["dormant", "armed"]


static func begin_explosion(state: Dictionary, shot: bool) -> void:
	state.phase = "shot" if shot else "burst"
	state.elapsed_ms = 0.0


static func advance(
	state: Dictionary, parameters: Dictionary, seconds: float, position: Vector3, opponents: Array
) -> Dictionary:
	var event := {"armed": false, "detonated": false, "finished": false, "damage_target": -2}
	if seconds <= 0 or not is_finite(seconds) or state.phase == "dead":
		return event
	if state.phase in ["shot", "burst"]:
		state.elapsed_ms += seconds * 1000.0
		if explosion_finished(parameters.explosion, state.elapsed_ms):
			state.phase = "dead"
			state.elapsed_ms = 0.0
			event.finished = true
		return event
	var target := int(opponents[0].id) if not opponents.is_empty() else -2
	for opponent in opponents:
		if not opponent.active:
			continue
		var delta: Vector3 = position - opponent.position
		# Retain source-axis delta across frames, including a save during the fuse.
		state.blast_delta = [delta.x, delta.y, -delta.z]
		if state.phase == "dormant":
			var extent: float = parameters.arming_half_width
			if delta.abs().x <= extent and delta.abs().y <= extent and delta.abs().z <= extent:
				state.phase = "armed"
				target = int(opponent.id)
				event.armed = true
				break
	if state.phase != "armed":
		return event
	state.elapsed_ms += seconds * 1000.0
	if state.elapsed_ms > float(parameters.fuse_ms):
		# Compatibility with the supported source: after the arming frame it
		# selects the first opponent, using the last active opponent's delta.
		# Its detonation check is upper-bounded per source axis, not radial.
		if state.blast_delta.all(func(axis): return axis <= parameters.blast_upper_bound):
			event.damage_target = target
		begin_explosion(state, false)
		event.detonated = true
	return event


static func envelope(layer: Dictionary, elapsed_ms: float) -> float:
	var progress := clampf((elapsed_ms - float(layer.delay_ms)) / float(layer.duration_ms), 0, 1)
	# Continuous easing avoids inheriting the original frame-rate-dependent
	# integer accumulator. The imported period and termination threshold remain.
	return .5 - .5 * cos(PI * progress)


static func alpha(effect: Dictionary, layer: Dictionary, elapsed_ms: float) -> float:
	return lerpf(float(effect.alpha_start), float(effect.alpha_end), envelope(layer, elapsed_ms))


static func explosion_finished(effect: Dictionary, elapsed_ms: float) -> bool:
	return effect.layers.all(
		func(layer):
			return (
				elapsed_ms >= float(layer.delay_ms)
				and alpha(effect, layer, elapsed_ms) <= float(effect.alpha_cutoff)
			)
	)


static func valid_parameters(value: Variant, resources: Dictionary, actor_count: int) -> bool:
	if (
		not value is Dictionary
		or not value.has_all(
			[
				"actor",
				"arming_half_width",
				"blast_upper_bound",
				"blast_test",
				"target_selection",
				"fuse_ms",
				"damage",
				"armed_meshes",
				"arm_sound",
				"shot_sound",
				"explosion"
			]
		)
	):
		return false
	if not integer(value.actor) or value.actor < 0 or value.actor >= actor_count:
		return false
	if (
		value.blast_test != "source_upper_axes"
		or value.target_selection != "first_opponent_last_active_delta"
	):
		return false
	for key in ["arming_half_width", "blast_upper_bound", "fuse_ms", "damage"]:
		if not number(value[key]) or value[key] <= 0 or value[key] > 1000000:
			return false
	for key in ["arm_sound", "shot_sound"]:
		if not integer(value[key]) or value[key] < 0 or value[key] > 65535:
			return false
	if not value.armed_meshes is Array or value.armed_meshes.size() != 2:
		return false
	for id in value.armed_meshes:
		if not mesh_id(id, resources):
			return false
	var effect: Variant = value.explosion
	if (
		not effect is Dictionary
		or not effect.has_all(["alpha_start", "alpha_end", "alpha_cutoff", "layers"])
	):
		return false
	for key in ["alpha_start", "alpha_end", "alpha_cutoff"]:
		if not integer(effect[key]) or effect[key] < 0 or effect[key] > 255:
			return false
	if effect.alpha_start <= effect.alpha_cutoff or effect.alpha_end > effect.alpha_cutoff:
		return false
	if not effect.layers is Array or effect.layers.size() != 2:
		return false
	for layer in effect.layers:
		if (
			not layer is Dictionary
			or not layer.has_all(["mesh", "delay_ms", "duration_ms", "scale"])
		):
			return false
		if not mesh_id(layer.mesh, resources):
			return false
		for key in ["delay_ms", "duration_ms", "scale"]:
			if not number(layer[key]) or layer[key] < 0 or layer[key] > 1000000:
				return false
		if layer.duration_ms <= 0 or layer.scale <= 0:
			return false
	return true


static func valid(state: Variant, hp: float, parameters: Dictionary) -> bool:
	if not state is Dictionary or not state.has_all(["phase", "elapsed_ms", "blast_delta"]):
		return false
	if state.phase not in ["dormant", "armed", "shot", "burst", "dead"]:
		return false
	if not number(state.elapsed_ms) or state.elapsed_ms < 0:
		return false
	if not state.blast_delta is Array or state.blast_delta.size() != 3:
		return false
	if not state.blast_delta.all(func(axis): return number(axis) and absf(axis) <= 2e8):
		return false
	if active(state) != (hp > 0):
		return false
	match state.phase:
		"dormant", "dead":
			return state.elapsed_ms == 0
		"armed":
			return state.elapsed_ms <= parameters.fuse_ms
		_:
			return not explosion_finished(parameters.explosion, state.elapsed_ms)


static func mesh_id(value: Variant, resources: Dictionary) -> bool:
	return integer(value) and resources.get(str(int(value)), {}).get("path", "").ends_with(".aem")


static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func integer(value: Variant) -> bool:
	return number(value) and value == int(value)


static func actor_dead(actor: Dictionary) -> bool:
	return actor.mine.phase == "dead" if actor.has("mine") else actor.hp <= 0
