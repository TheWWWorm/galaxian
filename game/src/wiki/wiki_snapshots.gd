extends Node
## Photographs every ship of the reference for the web export: each model is
## drawn alone in a small transparent world and saved as images/render-ship-N.png.
## Needs a renderer, so a headless export keeps the hangar's own pictures.
signal progressed(done: int, total: int)

const SIZE := Vector2i(640, 440)


static func available() -> bool:
	return DisplayServer.get_name() != "headless"


func render(catalog, directory: String) -> Dictionary:
	var result := {}
	var library = catalog.library
	if library.lighting_profile.is_empty():
		# A fresh import has no scene lit yet; use the hangar's light.
		library.set_lighting(0, 0, 0, true)
	if DirAccess.make_dir_recursive_absolute(directory.path_join("images")) != OK:
		return result
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4.2)
	camera.fov = 40
	viewport.add_child(camera)
	var pivot := Node3D.new()
	viewport.add_child(pivot)
	var keys: Array = catalog.ordered.filter(func(key): return key.begins_with("ship/"))
	for index in keys.size():
		var key: String = keys[index]
		var node: MeshInstance3D = library.model(str(catalog.media(key).get("model", "")), 2.6)
		if node.mesh != null:
			pivot.rotation = Vector3(.35, -.9, 0)
			pivot.add_child(node)
			node.position = -node.mesh.get_aabb().get_center() * node.scale
			for frame in 3:
				await RenderingServer.frame_post_draw
			var path := "images/render-%s.png" % key.replace("/", "-")
			if viewport.get_texture().get_image().save_png(directory.path_join(path)) == OK:
				result[key] = path
			pivot.remove_child(node)
		node.queue_free()
		progressed.emit(index + 1, keys.size())
	viewport.queue_free()
	return result
