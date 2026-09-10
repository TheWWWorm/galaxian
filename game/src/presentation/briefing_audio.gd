extends Node
## Page speech is optional: unknown source sound IDs are silent, as in the IPA.
## Effects live across page exits; speech belongs strictly to the displayed page.
var library
var voice := preload("res://src/presentation/audio_settings.gd").effect_player()
var effect := preload("res://src/presentation/audio_settings.gd").effect_player()
var current_page := Vector2i(-1, -1)


func _init() -> void:
	add_child(voice)
	add_child(effect)


func present(chapter: int, page: int) -> void:
	var identity := Vector2i(chapter, page)
	if current_page == identity:
		return
	stop_voice()
	current_page = identity
	var cue: Dictionary = library.briefing_cue(chapter, page)
	if not cue.is_empty():
		play_clip(voice, int(cue.sound))


func action(name: String) -> void:
	if library != null:
		play_clip(effect, int(library.content.briefing_ui.audio[name]))


func play_clip(player: AudioStreamPlayer, id: int) -> void:
	player.stop()
	player.stream = library.sound_clip(id)
	if player.stream != null:
		player.volume_linear = float(library.content.sound_bank[str(id)].gain)
		player.play()


func stop_voice() -> void:
	voice.stop()
	voice.stream = null
	current_page = Vector2i(-1, -1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		voice.stream_paused = true
		effect.stop()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		voice.stream_paused = false
