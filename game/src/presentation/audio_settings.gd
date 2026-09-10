extends RefCounted
## Independent mix controls; per-effect source gains stay on their players.
const MUSIC := "GoF Music"
const EFFECTS := "GoF Effects"


static func ensure_buses() -> void:
	for name in [MUSIC, EFFECTS]:
		if AudioServer.get_bus_index(name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, name)
		AudioServer.set_bus_send(index, "Master")


static func effect_player() -> AudioStreamPlayer:
	ensure_buses()
	var player := AudioStreamPlayer.new()
	player.bus = EFFECTS
	return player


static func music_player() -> AudioStreamPlayer:
	ensure_buses()
	var player := AudioStreamPlayer.new()
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
