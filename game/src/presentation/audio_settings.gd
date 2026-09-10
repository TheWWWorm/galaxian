extends RefCounted
## Independent mix controls; per-effect source gains stay on their players.
const MUSIC := "GoF Music"
const EFFECTS := "GoF Effects"


static func ensure_buses() -> void:
	for name in [MUSIC, EFFECTS]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		var index := AudioServer.bus_count
		if OS.has_feature("web"):
			# add_bus normalizes append indices to -1, which reorders Web
			# sample buses in Godot 4.7. Growing the count preserves their order.
			AudioServer.bus_count = index + 1
		else:
			AudioServer.add_bus()
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, "Master")


static func effect_player() -> AudioStreamPlayer:
	ensure_buses()
	var player := AudioStreamPlayer.new()
	# Short effects need immediate browser playback; native audio is unchanged.
	player.playback_type = (
		AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web")
		else AudioServer.PLAYBACK_TYPE_STREAM
	)
	player.bus = EFFECTS
	return player


static func music_player() -> AudioStreamPlayer:
	ensure_buses()
	var player := AudioStreamPlayer.new()
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.bus = MUSIC
	return player


static func apply(settings: Dictionary) -> void:
	ensure_buses()
	var levels := {
		MUSIC: float(settings.get("music_volume", 1.0)) if settings.get("music", true) else 0.0,
		EFFECTS: float(settings.get("effects_volume", 1.0))
	}
	for name in levels:
		var index := AudioServer.get_bus_index(name)
		var gain := clampf(levels[name], 0.0, 1.0) if is_finite(levels[name]) else 1.0
		AudioServer.set_bus_mute(index, gain <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(gain) if gain > 0.0 else 0.0)
