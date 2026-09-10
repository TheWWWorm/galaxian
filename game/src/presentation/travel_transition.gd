extends ColorRect
## Native presentation transition; the owning Session settles the trip once.


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	z_index = 100
	grab_focus()


func play(arrive: Callable) -> void:
	# This short fade is a remake UI addition, not imported travel simulation.
	var fade := create_tween()
	fade.tween_property(self, "color:a", 1.0, .25)
	await fade.finished
	arrive.call()
	# Let destination geometry render before uncovering it.
	await get_tree().process_frame
	fade = create_tween()
	fade.tween_property(self, "color:a", 0.0, .35)
	await fade.finished
	hide()
	queue_free()


func _input(_event: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()
