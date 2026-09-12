extends RefCounted
## Resolution-independent flight materials, following the supplied UI geometry.
## Original icon silhouettes are recovered from the locally imported artwork.
# The source normal atlas uses 153/255 alpha; pressed controls are opaque.
const IDLE_OPACITY := .6
const PRESSED_OPACITY := 1.0
const CYAN := Color("24bedf")
const DARK := Color("00212c")
const TEAL := Color("216767")
const PALE := Color("b5eef4")
static var orb: GradientTexture2D
static var knob: GradientTexture2D
static var teal_material: GradientTexture2D


static func disk(canvas: CanvasItem, center: Vector2, radius: float, fill: Color, edge: Color, width := .8) -> void:
	canvas.draw_circle(center, radius, fill, true, -1, true)
	if width > 0:
		canvas.draw_arc(center, radius, 0, TAU, 128, edge, width, true)


static func ring(canvas: CanvasItem, center: Vector2, radius: float, color: Color, width := .8) -> void:
	canvas.draw_arc(center, radius, 0, TAU, 128, color, width, true)


static func small_button(canvas: CanvasItem, center: Vector2, radius: float, active: bool, amber: bool = false) -> void:
	var accent := Color("ffd365") if amber else CYAN
	if active:
		# A tight rim highlight, not the source atlas's enlarged diffuse halo.
		for i in range(5, 0, -1):
			ring(canvas, center, radius + i * .55, Color(accent, .035 * (6 - i)), 1.1)
	disk(canvas, center, radius, Color("00121d"), CYAN, .8)
	disk(canvas, center, radius - 3, Color("006464") if active else Color("006262"), accent, 1.05)
	if active:
		ring(canvas, center, radius - .6, Color("c4faff"), .8)


static func gradient(radial: bool) -> GradientTexture2D:
	if radial and orb != null: return orb
	if not radial and knob != null: return knob
	var result := GradientTexture2D.new()
	result.width = 256
	result.height = 256
	result.gradient = Gradient.new()
	if radial:
		result.fill = GradientTexture2D.FILL_RADIAL
		result.fill_from = Vector2(.46, .42)
		result.fill_to = Vector2(.99, .55)
		result.gradient.offsets = PackedFloat32Array([0, .25, .65, .93, 1])
		result.gradient.colors = PackedColorArray([Color("91d4db"), Color("5abac9"), Color("1ba2b6"), Color("00778c"), Color("00687c")])
	else:
		result.fill_from = Vector2(.5, 0)
		result.fill_to = Vector2(.5, 1)
		result.gradient.offsets = PackedFloat32Array([0, .35, .82, 1])
		result.gradient.colors = PackedColorArray([Color("b1ebfd"), Color("89e1fd"), Color("83d5ef"), Color("65b8da")])
	if radial: orb = result
	else: knob = result
	return result


static func luminous_disk(canvas: CanvasItem, center: Vector2, radius: float, radial: bool, active: bool) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 128:
		var direction := Vector2.from_angle(TAU * i / 128.0)
		points.append(center + direction * radius)
		uvs.append(direction * .5 + Vector2.ONE * .5)
	canvas.draw_polygon(points, PackedColorArray([Color("bdffff") if active else Color.WHITE]), uvs, gradient(radial))
	ring(canvas, center, radius, Color("07879e"), 1.2)


static func fire(canvas: CanvasItem, center: Vector2, active: bool) -> void:
	disk(canvas, center, 28, DARK, CYAN, .8)
	disk(canvas, center, 25, TEAL, CYAN, .75)
	disk(canvas, center, 20.3, Color("00141e"), CYAN, .9)
	ring(canvas, center, 17.7, CYAN, .6)
	luminous_disk(canvas, center, 15.4, true, active)


static func steering(canvas: CanvasItem, origin: Vector2, center: Vector2, displacement: Vector2, held: bool, anchored := true) -> void:
	# The source's curved lower-left backing meets its circular steering frame.
	if anchored:
		var backing := PackedVector2Array([Vector2(origin.x + 1, center.y), origin + Vector2(1, 100), origin + Vector2(3, 103), origin + Vector2(7, 104), Vector2(center.x, origin.y + 104)])
		for i in 33:
			backing.append(center + Vector2.from_angle(PI * .5 + PI * .5 * i / 32.0) * 51)
		backing.append(backing[0])
		canvas.draw_colored_polygon(backing, TEAL)
		canvas.draw_polyline(backing, CYAN, .7, true)
	disk(canvas, center, 48, Color("00111b"), CYAN, .8)
	material_disk(canvas, center, 44.5)
	ring(canvas, center, 44.5, CYAN, .8)
	disk(canvas, center, 29.2, Color("00121d"), CYAN, .75)
	for direction: Vector2 in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		var tip := center + direction * 41
		var base := center + direction * 33.5
		var side := direction.orthogonal() * 6
		canvas.draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color("60c7e4"))
	var point := center + displacement
	disk(canvas, point, 25, Color("06495f"), CYAN, 1)
	disk(canvas, point, 22, Color("127c93"), Color("042f45"), 1.1)
	luminous_disk(canvas, point, 19.5, false, held)


static func panel(canvas: CanvasItem, rect: Rect2, radius: float, fill: Color, border: Color, thickness: int = 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_corner_radius_all(roundi(radius))
	style.set_border_width_all(thickness)
	style.anti_aliasing = true
	style.anti_aliasing_size = .6
	canvas.draw_style_box(style, rect)


static func perimeter(canvas: CanvasItem, extent: Vector2, margin: float) -> void:
	panel(canvas, Rect2(Vector2.ONE * margin, extent - Vector2.ONE * margin * 2), 7, Color.TRANSPARENT, Color("24a5bf99"))
	panel(canvas, Rect2(Vector2.ONE * (margin + 2.5), extent - Vector2.ONE * (margin + 2.5) * 2), 6, Color.TRANSPARENT, Color("23788c99"))


static func weapon_plaque(canvas: CanvasItem, extent: Vector2, center: Vector2) -> Rect2:
	var rect := Rect2(Vector2(extent.x - 175, center.y + 11), Vector2(168, 17))
	var outline := PackedVector2Array([Vector2(rect.position.x + 7, rect.position.y), Vector2(center.x - 28, rect.position.y)])
	for i in 25:
		outline.append(center + Vector2.from_angle(PI * .88 - PI * .38 * i / 24.0) * 30)
	outline.append(Vector2(rect.position.x + 7, rect.end.y))
	for i in 17:
		outline.append(Vector2(rect.position.x + 7, rect.position.y + 8.5) + Vector2.from_angle(PI * .5 + PI * i / 16.0) * Vector2(7, 8.5))
	outline.append(outline[0])
	canvas.draw_colored_polygon(outline, TEAL)
	canvas.draw_polyline(outline, CYAN, .7, true)
	var right := PackedVector2Array([Vector2(extent.x - 7, center.y + 7), Vector2(extent.x - 7, rect.end.y - 3), Vector2(extent.x - 10, rect.end.y)])
	for i in 17:
		right.append(center + Vector2.from_angle(asin(28.0 / 32.0) + (asin(7.0 / 32.0) - asin(28.0 / 32.0)) * i / 16.0) * 32)
	right.append(right[0])
	canvas.draw_colored_polygon(right, TEAL)
	canvas.draw_polyline(right, CYAN, .7, true)
	return rect


static func text(canvas: CanvasItem, value: String, at: Vector2, font_size: float, factor: float, color: Color = PALE, centered := false, max_width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	var pixels := maxi(8, roundi(font_size * factor))
	var point := at * factor
	if centered:
		var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels).x
		point.x -= minf(width, max_width * factor if max_width > 0 else width) * .5
	canvas.draw_set_transform(Vector2.ZERO)
	canvas.draw_string(font, point, value, HORIZONTAL_ALIGNMENT_LEFT, max_width * factor if max_width > 0 else -1.0, pixels, color)
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)


static func imported_glyph(texture: Texture2D) -> Texture2D:
	# Isolate the supplied central icon, eliminating the low-resolution circular
	# material. Reconstruct its coverage at high resolution; never cache content.
	var source := texture.get_image()
	var origin := Vector2i(source.get_size() / 2) - Vector2i(11, 11)
	var glyph := source.get_region(Rect2i(origin, Vector2i(23, 23)))
	glyph.resize(184, 184, Image.INTERPOLATE_CUBIC)
	for y in glyph.get_height():
		for x in glyph.get_width():
			var color := glyph.get_pixel(x, y)
			var alpha := smoothstep(.54, .79, color.b)
			if Vector2(x - 91.5, y - 91.5).length() > 83: alpha = 0
			glyph.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(glyph)


static func material_disk(canvas: CanvasItem, center: Vector2, radius: float) -> void:
	if teal_material == null:
		teal_material = GradientTexture2D.new()
		teal_material.width = 256
		teal_material.height = 256
		teal_material.fill_from = Vector2(.3, 0)
		teal_material.fill_to = Vector2(.7, 1)
		teal_material.gradient = Gradient.new()
		teal_material.gradient.colors = PackedColorArray([Color("286d71"), Color("216767")])
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 128:
		var direction := Vector2.from_angle(TAU * i / 128.0)
		points.append(center + direction * radius)
		uvs.append(direction * .5 + Vector2.ONE * .5)
	canvas.draw_polygon(points, PackedColorArray([Color.WHITE]), uvs, teal_material)


static func symbol(texture: Texture2D) -> Texture2D:
	var source := texture.get_image()
	source.resize(source.get_width() * 8, source.get_height() * 8, Image.INTERPOLATE_CUBIC)
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x, y)
			color.a = smoothstep(.2, .7, color.a)
			source.set_pixel(x, y, color)
	return ImageTexture.create_from_image(source)


static func translucent_layer(parent: Node, painter: Callable) -> CanvasGroup:
	# Composite the overlapping rings first, then apply the source opacity once.
	# Per-primitive alpha would make the layered centers unintentionally opaque.
	var group := CanvasGroup.new()
	group.fit_margin = 2
	group.clear_margin = 2
	group.self_modulate.a = IDLE_OPACITY
	var surface := Node2D.new()
	surface.draw.connect(painter.bind(surface))
	group.add_child(surface)
	parent.add_child(group)
	return group


static func redraw_layer(group: CanvasGroup, opacity := IDLE_OPACITY) -> void:
	group.self_modulate.a = opacity
	group.get_child(0).queue_redraw()
