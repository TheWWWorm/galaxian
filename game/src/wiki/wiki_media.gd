extends VBoxContainer
## The picture beside a reference page: a ship's model turning in its own
## small world (drag to turn it), the imported art enlarged without blurring,
## and the galaxy map with the page's place, system or quadrant marked.
signal followed(key: String)

const WikiChart = preload("res://src/wiki/wiki_chart.gd")

var frame := PanelContainer.new()
var viewport_box := SubViewportContainer.new()
var viewport := SubViewport.new()
var pivot := Node3D.new()
var camera := Camera3D.new()
var picture := TextureRect.new()
var chart: WikiChart = WikiChart.new()
var turning := true
var dragging := false


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.02, .05, .08, .85)
	style.border_color = Color("29404e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	frame.add_theme_stylebox_override("panel", style)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(frame)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	frame.add_child(stack)
	viewport_box.stretch = true
	viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_box.custom_minimum_size = Vector2(120, 120)
	viewport_box.gui_input.connect(turn_input)
	stack.add_child(viewport_box)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport_box.add_child(viewport)
	camera.position = Vector3(0, 0, 4.7)
	camera.fov = 40
	viewport.add_child(camera)
	# The frame's narrower side keeps the field of view, so a tall frame
	# never cuts off the ship's wings.
	viewport_box.resized.connect(func():
		camera.keep_aspect = Camera3D.KEEP_WIDTH if viewport_box.size.x < viewport_box.size.y else Camera3D.KEEP_HEIGHT
	)
	viewport.add_child(pivot)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.custom_minimum_size = Vector2(96, 96)
	stack.add_child(picture)
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.followed.connect(func(key): followed.emit(key))
	add_child(chart)


## Shows a page's media; false when it has none.
func show_media(shown: Dictionary, catalog) -> bool:
	for child in pivot.get_children():
		pivot.remove_child(child)
		child.queue_free()
	var model := str(shown.get("model", ""))
	viewport_box.visible = not model.is_empty()
	if viewport_box.visible:
		var node: MeshInstance3D = catalog.library.model(model, 2.6)
		if node.mesh == null:
			viewport_box.visible = false
		else:
			# Imported models face down the source's +Z; turn the bow left.
			pivot.rotation = Vector3(.35, -1.2, 0)
			pivot.add_child(node)
			node.position = -node.mesh.get_aabb().get_center() * node.scale
	var art: Dictionary = shown.get("picture", {})
	picture.texture = art.get("texture")
	picture.visible = picture.texture != null
	# Under a model the art is the hangar's own preview of it, shown smaller.
	picture.size_flags_vertical = Control.SIZE_FILL if viewport_box.visible else Control.SIZE_EXPAND_FILL
	picture.custom_minimum_size.y = 72 if viewport_box.visible else 96
	frame.visible = viewport_box.visible or picture.visible
	chart.visible = shown.get("chart", false)
	if chart.visible:
		chart.configure(catalog, shown)
	turning = true
	return frame.visible or chart.visible


func _process(delta: float) -> void:
	if turning and viewport_box.visible and is_visible_in_tree():
		pivot.rotate_y(delta * .45)


func turn_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		turning = false
	elif event is InputEventScreenTouch:
		dragging = event.pressed
		turning = false
	elif dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		pivot.rotate_y(event.relative.x * .01)
		pivot.rotation.x = clampf(pivot.rotation.x + event.relative.y * .01, -1.2, 1.2)
