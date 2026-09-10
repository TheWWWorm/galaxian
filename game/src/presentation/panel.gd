extends RefCounted
## Shared scalable panel built from the supplied corner artwork and colors.


static func draw(canvas: CanvasItem, library, rect: Rect2) -> void:
	var data: Dictionary = library.content.radio_ui.panel
	var corner: Texture2D = library.ui_image(data.corner)
	if corner is AtlasTexture:
		corner.filter_clip = true
	var inset := corner.get_size()
	var fill := Color8(data.fill[0], data.fill[1], data.fill[2], data.fill[3])
	var border := Color8(data.border[0], data.border[1], data.border[2], data.border[3])
	if not preload("res://src/presentation/bitmap_font.gd").is_mobile():
		# A single antialiased fill avoids seams where the translucent source
		# corner sprites meet the independently filled rectangle on large screens.
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(1)
		style.set_corner_radius_all(int(minf(inset.x, inset.y)))
		style.anti_aliasing = true
		canvas.draw_style_box(style, rect)
		return
	var middle := rect.size - inset * 2
	canvas.draw_rect(
		Rect2(rect.position + Vector2(inset.x, 0), Vector2(middle.x, rect.size.y)), fill
	)
	for side in [0, 1]:
		var x: float = rect.position.x + side * (rect.size.x - inset.x)
		canvas.draw_rect(
			Rect2(Vector2(x, rect.position.y + inset.y), Vector2(inset.x, middle.y)), fill
		)
		var edge_x: float = rect.position.x + side * (rect.size.x - 1)
		canvas.draw_line(
			Vector2(edge_x, rect.position.y + inset.y),
			Vector2(edge_x, rect.end.y - inset.y),
			border
		)
		var edge_y: float = rect.position.y + side * (rect.size.y - 1)
		canvas.draw_line(
			Vector2(rect.position.x + inset.x, edge_y),
			Vector2(rect.end.x - inset.x, edge_y),
			border
		)
		for row in [0, 1]:
			var at := Vector2(x, rect.position.y + row * (rect.size.y - inset.y))
			var size := inset * Vector2(-1 if side else 1, -1 if row else 1)
			canvas.draw_texture_rect(corner, Rect2(at, size), false)
