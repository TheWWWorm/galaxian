extends Control
## Original flare artwork with native projection. The sun is infinitely distant:
## translating the camera cannot move the flare, while looking away hides it.
var camera: Camera3D
var declaration := {}
var direction := Vector3.ZERO
var tint := Color.WHITE
var images: Array[Texture2D] = []
var sun_screen := Vector2.ZERO
var projected := false


static func valid(value: Variant, library) -> bool:
	var check = preload("res://src/content/survival_content.gd")
	var combat = preload("res://src/simulation/combat.gd")
	if (
		not value is Dictionary
		or not value.get("directions") is Array
		or value.directions.size() != int(library.content.sky.variant_count)
	):
		return false
	if not value.directions.all(
		func(v): return combat.valid_vector(v) and combat.vector(v).length_squared() > 0
	):
		return false
	if (
		not value.get("images") is Array
		or value.images.size() != 3
		or not value.images.all(func(v): return check.image(v, library))
	):
		return false
	if (
		not value.get("elements") is Array
		or value.elements.is_empty()
		or value.elements.size() > 32
	):
		return false
	for element in value.elements:
		if (
			not element is Dictionary
			or not check.integer(element.get("image"), 0, value.images.size() - 1)
		):
			return false
		if (
			not combat.number(element.get("position"))
			or absf(element.position) > 4
			or not combat.number(element.get("size"))
			or element.size <= 0
			or element.size > 8
		):
			return false
		if element.has("minimum_strength") and not combat.number(element.minimum_strength):
			return false
	if (
		not value.get("tints") is Array
		or value.tints.size() != library.content.sky.tints.size()
		or not value.tints.all(func(v): return check.numbers(v, 3, 0, 255))
	):
		return false
	for key in ["strength_base", "strength_scale", "alpha_bias", "large_alpha_bias"]:
		if not combat.number(value.get(key)) or value[key] < 0 or value[key] > 255:
			return false
	return value.strength_scale > 0 and value.get("blend") == "mix" and value.get("wash") == true


func configure(library, view: Camera3D, sky: Dictionary) -> void:
	camera = view
	declaration = library.content.lens_flare
	var v: Array = declaration.directions[int(sky.variant)]
	direction = Vector3(v[0], v[1], v[2]).normalized()
	var color: Array = declaration.tints[int(sky.style)]
	tint = Color(color[0] / 255.0, color[1] / 255.0, color[2] / 255.0)
	for binding in declaration.images:
		images.append(library.ui_image(binding))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)


func _process(_seconds: float) -> void:
	size = get_viewport_rect().size
	var sun := camera.global_position + direction * camera.far * .5
	projected = not camera.is_position_behind(sun)
	if projected:
		sun_screen = camera.unproject_position(sun)
	queue_redraw()


static func layout(data: Dictionary, viewport: Vector2, sun: Vector2) -> Dictionary:
	if viewport.x <= 0 or viewport.y <= 0 or not sun.is_finite():
		return {"sprites": [], "wash": 0.0}
	var center := viewport * .5
	var offset := sun - center
	var strength := (
		(float(data.strength_base) - offset.length() / center.y) * float(data.strength_scale)
	)
	var sprites := []
	for element in data.elements:
		if strength < float(element.get("minimum_strength", -INF)):
			continue
		var alpha := clampf(
			(
				(
					strength
					+ float(
						(
							data.large_alpha_bias
							if element.has("minimum_strength")
							else data.alpha_bias
						)
					)
				)
				/ 255.0
			),
			0,
			1
		)
		if alpha <= 0:
			continue
		sprites.append(
			{
				"image": int(element.image),
				"position": center + offset * float(element.position),
				"scale": float(element.size),
				"alpha": alpha
			}
		)
	return {"sprites": sprites, "wash": clampf(strength / 255.0, 0, 1)}


func _draw() -> void:
	if not projected or declaration.is_empty():
		return
	var frame := layout(declaration, size, sun_screen)
	var unit := minf(size.x / 480.0, size.y / 320.0)
	for sprite in frame.sprites:
		var texture: Texture2D = images[int(sprite.image)]
		var extent := texture.get_size() * unit * float(sprite.scale)
		var color := tint
		color.a = float(sprite.alpha)
		draw_texture_rect(texture, Rect2(sprite.position - extent * .5, extent), false, color)
	if frame.wash > 0:
		var wash := tint
		wash.a = float(frame.wash)
		draw_rect(Rect2(Vector2.ZERO, size), wash)
