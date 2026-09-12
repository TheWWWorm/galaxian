extends Control
## Original flight artwork with native projection and input ownership.
const SurvivalFeedback = preload("res://src/presentation/survival_feedback.gd")
const SurvivalResult = preload("res://src/presentation/survival_result.gd")
const FlightButton = preload("res://src/presentation/touch_flight_button.gd")
const HudSkin = preload("res://src/presentation/flight_hud_skin.gd")
const Throttle = preload("res://src/presentation/touch_throttle.gd")
var survival_rules := {}
var survival_score_image: Texture2D
var flight
var touch_enabled := false
var art := {}
var symbols := {}
var buttons := {}
var extra_buttons := {}
var factor := 1.0
var stick_origin := Vector2.ZERO
var stick_center := Vector2.ZERO
var stick_finger := -1
var stick_vector := Vector2.ZERO
var stick_offset := Vector2.ZERO
var stick_anchor := Vector2.ZERO
var floating_stick := false
var steering_layer: CanvasGroup
var plaque_layer: CanvasGroup
var weapon_caption := Node2D.new()
var action_fingers := {}
var throttle_control := Throttle.new()
var throttle_finger := -1
var camera_finger := -1
var camera_last := Vector2.ZERO
var docking_available := false
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
	elif not stick_enabled():
		release_stick()
	# Supplied MGame::OnRender2D skips the ego bars, radar and Hud draw entirely
	# while its level script owns the scene, and ignores touch for that time.
	if cinematic != cinematic_hidden:
		cinematic_hidden = cinematic
		visible = not cinematic
	refresh_navigation_controls()
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
		buttons[action].availability = 1.0 if tutorial.get("action") == action and tutorial.get("lit", false) else flight.button_opacity(action)
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
	steering_layer = HudSkin.translucent_layer(self, paint_steering)
	plaque_layer = HudSkin.translucent_layer(self, paint_plaque)
	weapon_caption.draw.connect(paint_weapon_caption)
	add_child(weapon_caption)
	for key in ["hull", "shield"]:
		symbols[key] = HudSkin.symbol(art[key])
	for action in ["boost", "fire", "weapon", "missiles", "pause"]:
		var control := FlightButton.new()
		control.kind = action
		control.tooltip_text = "Hold to fire. Double-tap for autofire; tap again to stop." if action == "fire" else action.capitalize()
		control.visible = touch_enabled
		if action == "fire":
			# The source overlays the luminous disk beneath the permanent fire frame.
			control.texture_normal = art.fire_overlay
		else:
			control.texture_normal = flight.library.ui_image(
				flight.library.content.flight_ui.buttons[action].normal
			)
			control.texture_pressed = flight.library.ui_image(
				flight.library.content.flight_ui.buttons[action].pressed
			)
		add_child(control)
		buttons[action] = control
	var actions := ["TIME"] if flight.session.slot == "survival" else ["AUTOPILOT", "TIME", "DOCK"]
	for action in actions:
		var control := FlightButton.new()
		control.kind = action
		control.tooltip_text = {"AUTOPILOT": "Autopilot", "TIME": "Simulation speed", "DOCK": "Dock"}[action]
		control.hide()
		add_child(control)
		extra_buttons[action] = control
		match action:
			"AUTOPILOT": control.pressed.connect(flight.toggle_autopilot)
			"TIME": control.pressed.connect(func():
				if flight.can_accelerate_time(): flight.cycle_time())
			"DOCK": control.pressed.connect(flight.try_dock)
	throttle_control.flight = flight
	throttle_control.hide()
	add_child(throttle_control)
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
	refresh_navigation_controls()


func layout_artwork() -> void:
	if art.is_empty() or size.x <= 0 or size.y <= 0:
		return
	release_stick()
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
	stick_anchor = stick_center
	var centers := {
		"pause": Vector2(extent.x - layout.pause_right, layout.pause_top),
		"fire": Vector2(extent.x - layout.fire_right, extent.y - layout.fire_bottom),
		"boost":
		Vector2(art.stick_frame.get_width() + layout.boost_offset, extent.y - layout.boost_bottom),
		"weapon": Vector2(extent.x - layout.weapon_right, extent.y - layout.weapon_bottom),
		"missiles": Vector2(extent.x - layout.missiles_right, extent.y - layout.missiles_bottom)
	}
	for action in buttons:
		var control = buttons[action]
		control.factor = factor
		var dimensions: Vector2 = control.texture_normal.get_size()
		control.position = (centers[action] - dimensions * .5) * factor
		control.size = dimensions * factor
		# Keep the full modern hit rectangle inside safe viewport edges.
		control.position = control.position.clamp(Vector2.ZERO, size - control.size)
	# Preserve the imported action composition; new controls occupy fixed spaces.
	var navigation := Vector2(stick_origin.x, stick_origin.y - 44)
	var extra_origins := {
		"AUTOPILOT": navigation,
		"TIME": navigation + Vector2(46, 0),
		"DOCK": centers.missiles + Vector2(-44, -80)
	}
	for action in extra_buttons:
		var control = extra_buttons[action]
		control.factor = factor
		control.size = Vector2(44, 44) * factor
		control.position = (extra_origins[action] * factor).clamp(Vector2.ZERO, size - control.size)
		control.queue_redraw()
	throttle_control.layout(factor)
	var margin: float = flight.library.content.flight_ui.radar.margin
	# Keep the shortened height; the revised wider track has a deliberate gap
	# from the frame. Its generous touch area still extends inward.
	throttle_control.position = Vector2(
		size.x - (margin + 15) * factor - throttle_control.size.x,
		buttons.pause.position.y + buttons.pause.size.y + 10 * factor
	)
	autofire_label.position = buttons.fire.position
	autofire_label.size = buttons.fire.size
	autofire_label.add_theme_font_size_override("font_size", maxi(8, roundi(12 * factor)))
	queue_redraw()


func refresh_navigation_controls() -> void:
	if flight == null or buttons.is_empty():
		return
	var shown: bool = touch_enabled and not flight.cinematic_locked() and not flight.paused
	for control: FlightButton in buttons.values():
		control.visible = touch_enabled
	var extras: bool = shown and flight.settings.get("extra_flight_buttons", true)
	throttle_control.visible = extras
	throttle_control.refresh()
	docking_available = false
	for action in extra_buttons:
		var control = extra_buttons[action]
		var available: bool = extras
		if action == "TIME": available = available and flight.can_accelerate_time()
		elif action == "DOCK": available = available and flight.can_dock()
		if action == "DOCK": docking_available = available
		control.visible = available
		control.active = action == "AUTOPILOT" and flight.auto_pilot
		control.multiplier = flight.time_factor
		control.queue_redraw()
		if not available:
			for finger in action_fingers.keys():
				if action_fingers[finger] == action:
					action_fingers.erase(finger)
					control.set_touch_pressed(false)
					control.button_up.emit()
	if not extras and throttle_finger != -1:
		throttle_finger = -1


func status_text() -> String:
	if docking_available:
		return "Docking available"
	if flight.auto_pilot:
		return "AUTOPILOT · %dx" % flight.time_factor
	return flight.objective()


func _draw() -> void:
	if art.is_empty() or flight == null:
		return
	var library = flight.library
	var layout: Dictionary = library.content.flight_ui.artwork.layout
	var extent := size / factor
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	flight.damage_feedback.draw(self, extent)
	if touch_enabled:
		HudSkin.perimeter(self, extent, float(flight.library.content.flight_ui.radar.margin))
	else:
		draw_radar_frame(extent)
	var x: float = art.shield.get_width() + layout.bar_left_offset
	var inset: float = layout.bar_inset_twice / 2.0
	for index in 2:
		var y: float = (
			layout.hull_top if index == 0 else art.bar.get_height() + layout.shield_top_offset
		)
		HudSkin.panel(self, Rect2(Vector2(x, y), art.bar.get_size()), 2, Color("14413c66"), Color("91aca966"))
		var key := "hull" if index == 0 else "shield"
		draw_texture_rect(symbols[key], Rect2(Vector2(layout.icon_left, y), art[key].get_size()), false)
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
	steering_layer.visible = stick_enabled()
	plaque_layer.visible = touch_enabled
	weapon_caption.visible = touch_enabled and flight.session.weapon_id >= 0 and survival_rules.is_empty()
	if touch_enabled:
		HudSkin.redraw_layer(steering_layer, .88 if stick_finger != -1 else HudSkin.IDLE_OPACITY)
		HudSkin.redraw_layer(plaque_layer)
		weapon_caption.queue_redraw()
	elif flight.session.weapon_id >= 0 and survival_rules.is_empty():
		bitmap(flight.library.item_name(flight.session.weapon_id), Vector2(extent.x - layout.weapon_label_right, extent.y - layout.weapon_label_bottom - library.radio_glyphs().values()[0].size.y), 90)
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

func accepts_touch() -> bool:
	return flight != null and not flight.paused and is_visible_in_tree() and touch_enabled


func stick_enabled() -> bool:
	return touch_enabled and flight != null and not flight.motion_steering_enabled()


func throttle_contains(point: Vector2) -> bool:
	return throttle_control.is_visible_in_tree() and throttle_control.touch_rect.has_point(
		throttle_control.get_global_transform().affine_inverse() * point
	)


func _input(event: InputEvent) -> void:
	if not accepts_touch():
		return
	var actions: Dictionary = buttons.duplicate()
	actions.merge(extra_buttons)
	# Suppress duplicate emulated clicks even when an owned finger leaves its
	# starting rectangle. Each real finger keeps its original action until up.
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		if throttle_finger >= 0 or camera_finger >= 0 or stick_finger >= 0 or not action_fingers.is_empty() or throttle_contains(event.position):
			get_viewport().set_input_as_handled()
			return
		for control: FlightButton in actions.values():
			if control.is_visible_in_tree() and control.get_global_rect().has_point(event.position):
				get_viewport().set_input_as_handled()
				return
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if throttle_finger == -2:
				throttle_finger = -1
				get_viewport().set_input_as_handled()
			elif camera_finger == -2:
				camera_finger = -1
				flight.end_touch_camera()
				get_viewport().set_input_as_handled()
			elif stick_finger == -2:
				release_stick()
				get_viewport().set_input_as_handled()
		elif throttle_contains(event.position):
			if throttle_finger == -1:
				throttle_finger = -2
				throttle_control.set_throttle_at(event.position)
			get_viewport().set_input_as_handled()
		elif stick_enabled() and Rect2(stick_origin * factor, art.stick_frame.get_size() * factor).has_point(event.position):
			if stick_finger == -1:
				begin_stick(event.position, -2, false)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if throttle_finger == -2:
			throttle_control.set_throttle_at(event.position)
			get_viewport().set_input_as_handled()
		elif camera_finger == -2:
			drag_camera(event.position)
		elif stick_finger == -2:
			steer_touch(event.position)
		return
	if event is InputEventScreenTouch:
		if not event.pressed:
			if action_fingers.has(event.index):
				var action: String = action_fingers[event.index]
				var control: FlightButton = actions[action]
				action_fingers.erase(event.index)
				control.set_touch_pressed(false)
				var completed: bool = not event.canceled and control.is_visible_in_tree() and control.get_global_rect().has_point(event.position)
				if action == "fire" and not completed:
					flight.controls.clear_touch_fire()
				control.button_up.emit()
				get_viewport().set_input_as_handled()
				if completed:
					control.pressed.emit()
				return
			if event.index == throttle_finger:
				throttle_finger = -1
			elif event.index == camera_finger:
				camera_finger = -1
				if event.canceled: flight.reset_touch_camera()
				else: flight.end_touch_camera()
			elif event.index == stick_finger:
				release_stick()
			else:
				return
			get_viewport().set_input_as_handled()
			return
		for action in actions:
			var control: FlightButton = actions[action]
			if control.is_visible_in_tree() and not control.disabled and control.get_global_rect().has_point(event.position):
				if not action_fingers.values().has(action):
					action_fingers[event.index] = action
					if action in ["boost", "fire", "missiles"]:
						flight.cancel_touch_navigation()
					control.set_touch_pressed(true)
					control.button_down.emit()
				get_viewport().set_input_as_handled()
				return
		if flight.cinematic_locked():
			return
		if throttle_contains(event.position):
			if throttle_finger == -1:
				throttle_finger = event.index
				throttle_control.set_throttle_at(event.position)
			get_viewport().set_input_as_handled()
			return
		if stick_enabled() and Rect2(stick_origin * factor, art.stick_frame.get_size() * factor).has_point(event.position):
			if stick_finger == -1:
				begin_stick(event.position, event.index, false)
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventScreenDrag:
		if action_fingers.has(event.index):
			get_viewport().set_input_as_handled()
		elif event.index == throttle_finger:
			throttle_control.set_throttle_at(event.position)
			get_viewport().set_input_as_handled()
		elif event.index == camera_finger:
			drag_camera(event.position)
		elif event.index == stick_finger:
			steer_touch(event.position)


func floating_stick_region() -> Rect2:
	if not stick_enabled(): return Rect2()
	var home := Rect2(stick_origin * factor, art.stick_frame.get_size() * factor)
	var nearby := home.grow_individual(24 * factor, 60 * factor, 100 * factor, 24 * factor)
	return nearby.intersection(Rect2(Vector2(0, size.y * .42), Vector2(size.x * .4, size.y * .58)))


func begin_stick(point: Vector2, finger: int, relocate: bool) -> void:
	if not stick_enabled(): return
	stick_finger = finger
	floating_stick = relocate
	stick_anchor = point / factor if relocate else stick_center
	if relocate:
		# Keep the full circular base on screen. The raw touch remains the neutral
		# input origin, including when the visible center is inset at an edge.
		var extent := size / factor
		var center := stick_anchor.clamp(Vector2(53, 53), Vector2(extent.x * .5 - 48, extent.y - 53))
		stick_offset = center - stick_center
	else:
		stick_offset = Vector2.ZERO
	flight.cancel_touch_navigation()
	steer_touch(point)


func release_stick() -> void:
	stick_finger = -1
	stick_vector = Vector2.ZERO
	stick_offset = Vector2.ZERO
	stick_anchor = stick_center
	floating_stick = false
	if flight != null and is_instance_valid(flight):
		flight.controls.touch_look = Vector2.ZERO
	queue_redraw()


func paint_steering(canvas: Node2D) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	HudSkin.steering(canvas, stick_origin + stick_offset, stick_center + stick_offset, stick_vector * flight.library.content.flight_ui.artwork.layout.stick_radius, stick_finger != -1, not floating_stick)


func paint_plaque(canvas: Node2D) -> void:
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * factor)
	var fire = buttons.fire
	HudSkin.weapon_plaque(canvas, size / factor, (fire.position + fire.size * .5) / factor)


func paint_weapon_caption() -> void:
	var center: Vector2 = (buttons.fire.position + buttons.fire.size * .5) / factor
	HudSkin.text(weapon_caption, flight.library.item_name(flight.session.weapon_id), Vector2(size.x / factor - 114, center.y + 24.5), 13, factor, HudSkin.PALE, true, 90)


func steer_touch(point: Vector2) -> void:
	if not stick_enabled():
		release_stick()
		return
	stick_vector = ((point / factor - stick_anchor) / float(flight.library.content.flight_ui.artwork.layout.stick_radius)).limit_length()
	if stick_vector.length() < .08:
		stick_vector = Vector2.ZERO
	flight.controls.touch_look = stick_vector
	get_viewport().set_input_as_handled()


func drag_camera(point: Vector2) -> void:
	flight.drag_touch_camera(point - camera_last)
	camera_last = point
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Give radio panels and other UI first refusal. Only a gesture that starts
	# in the remaining open view can become a camera gesture.
	if not accepts_touch() or flight.cinematic_locked():
		return
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch and event.pressed:
		if floating_stick_region().has_point(event.position):
			if stick_finger == -1: begin_stick(event.position, event.index, true)
			get_viewport().set_input_as_handled()
			return
		if camera_finger == -1:
			camera_finger = event.index
			camera_last = event.position
			flight.begin_touch_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if floating_stick_region().has_point(event.position):
			if stick_finger == -1: begin_stick(event.position, -2, true)
			get_viewport().set_input_as_handled()
			return
		if camera_finger == -1:
			camera_finger = -2
			camera_last = event.position
			flight.begin_touch_camera()
		get_viewport().set_input_as_handled()


func reset_touch() -> void:
	release_stick()
	throttle_finger = -1
	camera_finger = -1
	for control: FlightButton in buttons.values():
		control.set_touch_pressed(false)
	for control: FlightButton in extra_buttons.values():
		control.set_touch_pressed(false)
	action_fingers.clear()
	if flight == null or not is_instance_valid(flight):
		return
	flight.controls.touch_look = Vector2.ZERO
	flight.controls.clear_touch_fire()
	flight.controls.touch_boost = false
	flight.controls.touch_missiles = false
	flight.controls.touch_throttle = 0.0
	flight.reset_touch_camera()


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
