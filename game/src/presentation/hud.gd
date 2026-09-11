extends Control
## Original flight artwork with native projection and input ownership.
const SurvivalFeedback = preload("res://src/presentation/survival_feedback.gd")
const SurvivalResult = preload("res://src/presentation/survival_result.gd")
var survival_rules := {}
var survival_score_image: Texture2D
var flight
var touch_enabled := false
var art := {}
var buttons := {}
var extra_buttons := {}
var factor := 1.0
var stick_origin := Vector2.ZERO
var stick_center := Vector2.ZERO
var stick_finger := -1
var stick_vector := Vector2.ZERO
var action_fingers := {}
var cinematic_hidden := false
var reticle := TextureRect.new()
var autofire_label := Label.new()
var radar_art := {}
var objective: Dictionary
var targets: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reticle.stretch_mode = TextureRect.STRETCH_SCALE
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle)
	objective = create_marker(Color("ffca79"), true)
	setup_artwork()
	if flight.session.slot == "survival":
		survival_rules = flight.session.declarations.get("hud", {})
		if not survival_rules.is_empty():
			for key in survival_rules.get("radar", {}).get("images", {}):
				radar_art[key] = flight.library.ui_image(survival_rules.radar.images[key])
			survival_score_image = flight.library.ui_image(survival_rules.score_image)
			if flight.session.hud_feedback.is_empty():
				var state: Dictionary = flight.session.active_job.survival
				flight.session.hud_feedback = SurvivalFeedback.initialize(
					int(state.score),
					int(state.combo),
					flight.session.elapsed * 1000.0,
					survival_rules
				)
	for key in flight.library.content.flight_ui.radar.images:
		radar_art[key] = flight.library.ui_image(flight.library.content.flight_ui.radar.images[key])


func create_marker(color: Color, navigation: bool) -> Dictionary:
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var outline := TextureRect.new()
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	outline.stretch_mode = TextureRect.STRETCH_SCALE
	container.add_child(outline)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	label.position = Vector2(20, -10)
	container.add_child(label)
	label.visible = navigation
	var health := ColorRect.new()
	health.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health.color = color
	health.position = Vector2(-12, 16)
	container.add_child(health)
	health.visible = not navigation
	var health_edge := ColorRect.new()
	health_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health.add_child(health_edge)
	var lead := TextureRect.new()
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lead.stretch_mode = TextureRect.STRETCH_SCALE
	lead.hide()
	container.add_child(lead)
	return {"node": container, "outline": outline, "label": label, "health": health,
		"health_edge": health_edge, "lead": lead}


func _process(_delta: float) -> void:
	if flight == null or not is_instance_valid(flight):
		return
	var cinematic: bool = flight.cinematic_locked()
	if flight.paused or cinematic or not touch_enabled:
		reset_touch()
	# Supplied MGame::OnRender2D skips the ego bars, radar and Hud draw entirely
	# while its level script owns the scene, and ignores touch for that time.
	if cinematic != cinematic_hidden:
		cinematic_hidden = cinematic
		visible = not cinematic
	if cinematic:
		return
	if not survival_rules.is_empty():
		var director: Dictionary = flight.session.active_job.survival
		SurvivalFeedback.advance(
			flight.session.hud_feedback,
			survival_rules,
			int(director.score),
			int(director.combo),
			flight.session.elapsed * 1000.0
		)
		buttons.missiles.visible = touch_enabled
	var tutorial: Dictionary = flight.session.tutorial_cue()
	for action in ["boost", "missiles"]:
		buttons[action].self_modulate.a = 1.0 if tutorial.get("action") == action and tutorial.get("lit", false) else flight.button_opacity(action)
	autofire_label.visible = touch_enabled and flight.controls.touch_autofire
	queue_redraw()
	var active: bool = not flight.paused and not flight.outro_active and not flight.session.active_job.get("ready", false)
	reticle.visible = active
	objective.node.visible = active
	for marker in targets:
		marker.node.hide()
		marker.lead.hide()
	if not active:
		return
	var radar: Dictionary = flight.library.content.flight_ui.radar
	var aim_point: Vector3 = flight.ship.position - flight.ship.basis.z * radar.aim_distance
	reticle.texture = radar_art.aim_hit if flight.weapon_hit_ms > 0 else radar_art.aim
	reticle.size = reticle.texture.get_size() * factor
	reticle.visible = not flight.camera.is_position_behind(aim_point)
	reticle.position = flight.camera.unproject_position(aim_point) - reticle.size * .5
	if flight.session.slot == "survival":
		objective.node.hide()
	else:
		place(objective, flight.waypoint, "objective", true)
	var title := (
		"DOCK" if flight.station != null and flight.session.active_job.is_empty() else "OBJECTIVE"
	)
	var distance: float = flight.ship.position.distance_to(flight.waypoint)
	objective.label.text = title + "  %d m" % int(distance)
	while targets.size() < flight.actors.size():
		targets.append(create_marker(Color("ff8070"), false))
	var directions: Dictionary = flight.session.Mission.Sequence.directives(
		flight.session.mission_definition(), flight.session.active_job
	)
	for index in flight.actors.size():
		var actor: Dictionary = flight.actors[index]
		if (
			not is_instance_valid(actor.node)
			or not flight.session.Mission.actor_active(
				flight.session.mission_definition(), flight.session.active_job, actor.state
			)
		):
			continue
		var marker: Dictionary = targets[index]
		marker.node.show()
		var group: Dictionary = flight.session.mission_definition().groups[int(actor.state.group)]
		var team := "ally" if group.get("team", "enemy") == "ally" else "enemy"
		var separation: Vector3 = (actor.node.position - flight.ship.position).abs()
		var near: bool = (
			separation[separation.max_axis_index()] <= radar.near_extent
			and not radar.distant_actors.any(
				func(identifier): return int(identifier) == int(group.actor)
			)
		)
		place(marker, actor.node.position, marker_kind(team, actor.state), near)
		marker.label.hide()
		marker.health.color = Color.hex(int(radar.colors[team]))
		var maximum: float = flight.library.group_hull(group, int(flight.session.active_job.rank))
		var width: float = radar_art.enemy_near.get_width() * factor
		marker.health.position = Vector2(-width * .5, width * .5 + radar.health_gap * factor)
		marker.health.size = Vector2(
			width * clampf(float(actor.state.hp) / maximum, 0, 1), radar.health_height * factor
		)
		var edge: Dictionary = radar.health_edge[team]
		marker.health_edge.color = Color.hex(int(edge.color))
		marker.health_edge.position = Vector2(0, (edge.gap - radar.health_gap) * factor)
		marker.health_edge.size = Vector2(marker.health.size.x, factor)
		if team == "enemy" and marker.health.visible:
			place_lead(marker, actor, group, directions)


func place_lead(
	marker: Dictionary, actor: Dictionary, group: Dictionary, directions: Dictionary
) -> void:
	var rule: Dictionary = flight.library.content.flight_ui.radar.lead
	var preference: Variant = flight.settings.get("targeting_reticle")
	if not (rule.enabled if preference == null else bool(preference)):
		return
	var index := int(actor.index)
	if (
		not group.get("combat_active", true)
		or directions.stopped.has(index)
		or directions.suspended.has(index)
	):
		return
	var velocity := Vector3.ZERO
	if group.get("behavior") == "transit":
		velocity = flight.session.Combat.vector(group.velocity)
	elif (
		group.get("behavior") in ["interceptor", "escort", "wingmate"]
		and actor.state.get("awake", false)
	):
		velocity = flight.session.Combat.vector(actor.state.destruction.velocity)
	var gun: Dictionary = flight.library.weapon_ballistics(flight.session.weapon_id)
	var projectile_speed := float(gun.get("speed", 0))
	if not velocity.is_finite() or velocity.is_zero_approx() or projectile_speed <= 0:
		return
	var distance: float = flight.ship.position.distance_to(actor.node.position)
	# Preserve the imported stepped estimate. Floating-point world vectors avoid
	# reproducing the original fixed-point arithmetic implementation.
	var steps := maxi(int(rule.minimum), int(distance / float(rule.bucket)))
	var point: Vector3 = (
		actor.node.position + velocity / projectile_speed * float(rule.scale) * steps
	)
	if not point.is_finite() or flight.camera.is_position_behind(point):
		return
	var screen: Vector2 = flight.camera.unproject_position(point)
	if not Rect2(Vector2.ZERO, size).has_point(screen):
		return
	marker.lead.texture = radar_art.lead
	marker.lead.size = radar_art.lead.get_size() * factor
	marker.lead.position = screen - marker.node.position - marker.lead.size * .5
	marker.lead.show()


func marker_kind(team: String, state: Dictionary) -> String:
	if team != "enemy" or not survival_rules.has("radar"):
		return team
	var archetype := int(state.get("archetype", 0))
	var bounds: Array = survival_rules.radar.bounds
	return "weak" if archetype <= bounds[0] else ("medium" if archetype <= bounds[1] else "strong")


func place(marker: Dictionary, point: Vector3, kind: String, near: bool) -> void:
	var camera: Camera3D = flight.camera
	var screen := camera.unproject_position(point)
	var behind := camera.is_position_behind(point)
	if behind:
		screen = size - screen
	# Native viewport adaptation keeps the source off-screen markers within reach.
	var inset: float = radar_art.enemy_off.get_width() * factor * .5
	var safe := Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2)
	var outside := not safe.has_point(screen) or behind
	if outside:
		var direction := screen - size * .5
		if direction.length_squared() < .001:
			direction = Vector2.DOWN
		var edge := safe.size * .5
		var reach := minf(
			edge.x / maxf(absf(direction.x), .001), edge.y / maxf(absf(direction.y), .001)
		)
		screen = size * .5 + direction * reach
	marker.node.position = screen
	var suffix := "off" if outside else ("near" if near else "far")
	marker.outline.texture = radar_art[kind + "_" + suffix]
	marker.outline.size = marker.outline.texture.get_size() * factor
	marker.outline.position = -marker.outline.size * .5
	var label_width: float = marker.label.get_minimum_size().x
	var gap: float = marker.outline.size.x * .5 + 4 * factor
	marker.label.position.x = (
		-label_width - gap if screen.x + label_width + gap > size.x - inset else gap
	)
	marker.health.visible = kind != "objective" and not outside and near


func setup_artwork() -> void:
	for key in flight.library.content.flight_ui.artwork.images:
		art[key] = flight.library.ui_image(flight.library.content.flight_ui.artwork.images[key])
	for action in ["boost", "fire", "weapon", "missiles", "pause"]:
		var control := TextureButton.new()
		control.ignore_texture_size = true
		control.stretch_mode = TextureButton.STRETCH_SCALE
		control.tooltip_text = "Hold to fire. Double-tap for autofire; tap again to stop." if action == "fire" else action.capitalize()
		control.visible = touch_enabled
		if action == "fire":
			# The source overlays the luminous disk beneath the permanent fire frame.
			control.texture_normal = art.fire_overlay
			control.self_modulate.a = 0
		else:
			control.texture_normal = flight.library.ui_image(
				flight.library.content.flight_ui.buttons[action].normal
			)
			control.texture_pressed = flight.library.ui_image(
				flight.library.content.flight_ui.buttons[action].pressed
			)
		add_child(control)
		buttons[action] = control
	autofire_label.text = "AUTO"
	autofire_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	autofire_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	autofire_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	autofire_label.add_theme_font_override("font", preload("res://src/presentation/bitmap_font.gd").create(flight.library))
	autofire_label.add_theme_color_override("font_color", Color.WHITE)
	autofire_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	autofire_label.add_theme_constant_override("shadow_offset_x", 1)
	autofire_label.add_theme_constant_override("shadow_offset_y", 1)
	autofire_label.hide()
	add_child(autofire_label)
	resized.connect(layout_artwork)
	layout_artwork()


func layout_artwork() -> void:
	if art.is_empty() or size.x <= 0 or size.y <= 0:
		return
	factor = preload("res://src/presentation/bitmap_font.gd").composition_scale(size)
	var extent := size / factor
	var layout: Dictionary = flight.library.content.flight_ui.artwork.layout
	stick_origin = Vector2(
		layout.stick_left, extent.y - art.stick_frame.get_height() - layout.stick_bottom
	)
	# The frame's ring is asymmetric within its atlas rectangle. The original
	# draw places the frame three texels below its constructor's touch origin.
	# Account for that offset and the half-texel center of the ring's pixels.
	var pivot: float = (art.stick_frame.get_width() - art.stick_normal.get_width()) * 2.0
	stick_center = stick_origin + Vector2(pivot + .5, pivot - 3.5)
	var centers := {
		"pause": Vector2(extent.x - layout.pause_right, layout.pause_top),
		"fire": Vector2(extent.x - layout.fire_right, extent.y - layout.fire_bottom),
		"boost":
		Vector2(art.stick_frame.get_width() + layout.boost_offset, extent.y - layout.boost_bottom),
		"weapon": Vector2(extent.x - layout.weapon_right, extent.y - layout.weapon_bottom),
		"missiles": Vector2(extent.x - layout.missiles_right, extent.y - layout.missiles_bottom)
	}
	for action in buttons:
		var control: TextureButton = buttons[action]
		var dimensions: Vector2 = control.texture_normal.get_size()
		control.position = (centers[action] - dimensions * .5) * factor
		control.size = dimensions * factor
		# Keep the full modern hit rectangle inside safe viewport edges.
		control.position = control.position.clamp(Vector2.ZERO, size - control.size)
	autofire_label.position = buttons.fire.position
	autofire_label.size = buttons.fire.size
	autofire_label.add_theme_font_size_override("font_size", maxi(8, roundi(12 * factor)))
	queue_redraw()


func _draw() -> void:
	if art.is_empty() or flight == null:
		return
	var library = flight.library
	var layout: Dictionary = library.content.flight_ui.artwork.layout
	var extent := size / factor
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	flight.damage_feedback.draw(self, extent)
	draw_radar_frame(extent)
	var x: float = art.shield.get_width() + layout.bar_left_offset
	var inset: float = layout.bar_inset_twice / 2.0
	for index in 2:
		var y: float = (
			layout.hull_top if index == 0 else art.bar.get_height() + layout.shield_top_offset
		)
		draw_texture(art.bar, Vector2(x, y))
		draw_texture(art.hull if index == 0 else art.shield, Vector2(layout.icon_left, y))
		var maximum: float = (
			flight.session.max_hull() if index == 0 else flight.session.max_shield()
		)
		var value: float = flight.session.hull if index == 0 else flight.session.shield
		var ratio := clampf(value / maximum, 0, 1) if maximum > 0 else 0.0
		draw_rect(
			Rect2(
				Vector2(x + inset, y + inset),
				Vector2((art.bar.get_width() - inset * 2) * ratio, art.bar.get_height() - inset * 2)
			),
			Color.hex(
				int(library.content.flight_ui.artwork.colors["hull" if index == 0 else "shield"])
			)
		)
	if touch_enabled:
		draw_texture(art.stick_frame, stick_origin)
		var knob: Texture2D = art.stick_pressed if stick_finger >= 0 else art.stick_normal
		draw_texture(knob, stick_center + stick_vector * layout.stick_radius - knob.get_size() * .5)
		var fire: TextureButton = buttons.fire
		var fire_center := (fire.position + fire.size * .5) / factor
		draw_texture(
			art.fire_frame,
			Vector2(
				extent.x - art.fire_frame.get_width() - layout.fire_frame_right,
				fire_center.y - art.fire_frame.get_height() * .5
			)
		)
	if flight.session.weapon_id >= 0 and survival_rules.is_empty():
		bitmap(
			flight.library.item_name(flight.session.weapon_id),
			Vector2(
				extent.x - layout.weapon_label_right,
				extent.y - layout.weapon_label_bottom - library.radio_glyphs().values()[0].size.y
			),
			90
		)
	if not survival_rules.is_empty():
		draw_survival(extent)
	var definition: Dictionary = flight.session.mission_definition()
	var duration := float(definition.get("deadline_ms", 0))
	if definition.get("success", {}).get("kind") == "time_survived":
		duration = float(definition.success.duration_ms)
	if duration > 0:
		var point := Vector2(
			extent.x - art.timer.get_width() - layout.timer_right, layout.timer_top
		)
		draw_texture(art.timer, point)
		var seconds := ceili(
			maxf(0, duration - float(flight.session.active_job.elapsed_ms)) / 1000.0
		)
		# Match the raised digit baseline used by the survival score frame.
		bitmap("%02d:%02d" % [seconds / 60, seconds % 60], point + Vector2(9, 2))
	draw_set_transform(Vector2.ZERO)


func bitmap(value: String, point: Vector2, width: float = INF) -> void:
	preload("res://src/presentation/bitmap_font.gd").draw_text(self, flight.library, value, point, width)

func _input(event: InputEvent) -> void:
	if flight == null or flight.paused or not visible or not touch_enabled:
		return
	var actions: Dictionary = buttons.duplicate()
	actions.merge(extra_buttons)
	# Touch actions already have independent finger ownership below. Suppress the
	# accompanying emulated mouse click so one tap cannot trigger an action twice.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		for control: BaseButton in actions.values():
			if control.is_visible_in_tree() and control.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				return
	if event is InputEventScreenTouch:
		if not event.pressed and action_fingers.has(event.index):
			var action: String = action_fingers[event.index]
			var control: BaseButton = actions[action]
			action_fingers.erase(event.index)
			control.set_pressed_no_signal(false)
			var completed: bool = not event.canceled and control.is_visible_in_tree() and control.get_global_rect().has_point(event.position)
			if action == "fire" and not completed:
				flight.controls.clear_touch_fire()
			control.button_up.emit()
			get_viewport().set_input_as_handled()
			if completed:
				control.pressed.emit()
			return
		if event.pressed:
			for action in actions:
				var control: BaseButton = actions[action]
				if (
					control.is_visible_in_tree()
					and control.get_global_rect().has_point(event.position)
				):
					if not action_fingers.values().has(action):
						action_fingers[event.index] = action
						control.set_pressed_no_signal(true)
						control.button_down.emit()
					get_viewport().set_input_as_handled()
					return
		if flight.cinematic_locked():
			return
		if (
			touch_enabled
			and event.pressed
			and stick_finger < 0
			and Rect2(stick_origin * factor, art.stick_frame.get_size() * factor).has_point(
				event.position
			)
		):
			stick_finger = event.index
		elif not event.pressed and event.index == stick_finger:
			stick_finger = -1
			stick_vector = Vector2.ZERO
			flight.controls.touch_look = Vector2.ZERO
			get_viewport().set_input_as_handled()
			return
		else:
			return
	elif event is InputEventScreenDrag and action_fingers.has(event.index):
		get_viewport().set_input_as_handled()
		return
	elif not event is InputEventScreenDrag or event.index != stick_finger:
		return
	stick_vector = (
		(
			(event.position / factor - stick_center)
			/ float(flight.library.content.flight_ui.artwork.layout.stick_radius)
		)
		. limit_length()
	)
	if stick_vector.length() < .08:
		stick_vector = Vector2.ZERO
	flight.controls.touch_look = stick_vector
	get_viewport().set_input_as_handled()


func reset_touch() -> void:
	stick_finger = -1
	stick_vector = Vector2.ZERO
	for control: BaseButton in buttons.values():
		control.set_pressed_no_signal(false)
	for control: BaseButton in extra_buttons.values():
		control.set_pressed_no_signal(false)
	action_fingers.clear()
	flight.controls.touch_look = Vector2.ZERO
	flight.controls.clear_touch_fire()
	flight.controls.touch_boost = false
	flight.controls.touch_missiles = false
	flight.controls.touch_throttle = 0.0


func draw_radar_frame(extent: Vector2) -> void:
	if radar_art.is_empty():
		return
	var margin: float = flight.library.content.flight_ui.radar.margin
	var side: Texture2D = radar_art.frame_side
	var edge: Texture2D = radar_art.frame_edge
	var width := float(side.get_width())
	var height := extent.y - margin * 2
	# Preserve the original corner bands; only the plain middle span stretches.
	for right in [false, true]:
		var x: float = extent.x - margin - width if right else margin
		for part in 3:
			var source_y := (
				0.0 if part == 0 else (width if part == 1 else side.get_height() - width)
			)
			var source_h := width if part != 1 else side.get_height() - width * 2
			var y := (
				margin
				if part == 0
				else (margin + width if part == 1 else extent.y - margin - width)
			)
			var h := width if part != 1 else height - width * 2
			draw_texture_rect_region(
				side,
				Rect2(Vector2(x, y), Vector2(width if right else -width, h)),
				Rect2(0, source_y, width, source_h)
			)
	var span := extent.x - (margin + width) * 2
	draw_texture_rect(edge, Rect2(margin + width, margin, span, edge.get_height()), false)
	draw_texture_rect(
		edge,
		Rect2(margin + width, extent.y - margin - edge.get_height(), span, -edge.get_height()),
		false
	)


func draw_survival(extent: Vector2) -> void:
	var state: Dictionary = flight.session.hud_feedback
	var height: float = flight.library.radio_glyphs().values()[0].size.y
	var at := Vector2(
		extent.x - survival_score_image.get_width() - survival_rules.score_right,
		survival_rules.score_top
	)
	draw_texture(survival_score_image, at)
	var text_at := at + Vector2(survival_rules.score_text[0], survival_rules.score_text[1])
	# Raise the visible digits within the narrow score frame on both layouts.
	text_at.y -= 3.0
	bitmap(str(int(flight.session.active_job.survival.score)), text_at)
	bitmap(
		SurvivalResult.duration(flight.session.elapsed),
		Vector2(
			extent.x - survival_rules.elapsed_right,
			extent.y - height - survival_rules.elapsed_bottom
		)
	)
	centered_bitmap(
		SurvivalFeedback.notice_text(state, flight.library),
		extent.x,
		height * survival_rules.notice_height_lines + survival_rules.notice_y
	)
	centered_bitmap(
		SurvivalFeedback.combo_text(state, survival_rules, flight.library),
		extent.x,
		extent.y * .5 - survival_rules.combo_y_from_center
	)


func centered_bitmap(text: String, width: float, y: float) -> void:
	var measured := 0.0
	for index in text.length():
		measured += flight.library.radio_glyph_width(text.unicode_at(index))
	bitmap(text, Vector2((width - measured) * .5, y))
