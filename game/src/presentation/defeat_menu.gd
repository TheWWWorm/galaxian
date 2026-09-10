extends "res://src/presentation/choice_window.gd"
## The source defeat image sits behind the shared acknowledged choice panel.
func _draw() -> void:
	var measured := measure()
	if not measured.is_empty():
		var data: Dictionary = library.content.defeat_ui
		var art: Texture2D = library.ui_image(data.image)
		var factor: float = measured.factor
		draw_set_transform(measured.origin, 0, Vector2.ONE * factor)
		draw_texture(art, Vector2(240 - art.get_width() * .5, measured.panel.position.y + data.image_y))
		draw_set_transform(Vector2.ZERO)
	super._draw()
