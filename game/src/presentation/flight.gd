extends Node3D
signal dock_requested
signal pause_requested
signal defeated
signal mission_failed
signal mission_completed
signal message_changed(text: String)
signal objective_changed
const Backdrop = preload("res://src/presentation/backdrop.gd")
const Nebula = preload("res://src/presentation/nebula.gd")
const Controls = preload("res://src/input/controls.gd")
var library
var session
var controls := Controls.new()
var ship := CharacterBody3D.new()
var player_hull: MeshInstance3D
var camera := Camera3D.new()
var station
var dock_radius := 0.0
var waypoint := Vector3.ZERO
var dormant_visuals: Dictionary = {}
var actors: Array = []
var field_rocks: Array = []
var nebula: Node3D
var backdrop: Node3D
var lens_flare: Control
var explosions: Array[Node3D] = []
var player_destroyed := false
var wrecks := {}
var effect_random := RandomNumberGenerator.new()
var bolts := {}
var projectile_trails := {}
var bolt_mesh: CylinderMesh
var bolt_material: StandardMaterial3D
var enemy_bolt_material: StandardMaterial3D
var previous_actors := {}
var throttle: float:
	get:
		return float(session.motion.throttle) if session != null else 1.0
	set(value):
		if session != null:
			session.motion.throttle = clampf(value, 0, 1)
var speed := 0.0
var auto_pilot := false
var time_factor := 1
var paused := false
var weapon_timers := {}
var shield_timer := 0.0
var boost_held := false
var boost: float:
	get:
		return (
			session.Motion.charge(session.motion, library.content.player_motion)
			if session != null
			else 1.0
		)
var follow_distance := 43.0
var simulation_time := 0.0
var recent_damage := 0.0
var player_hit = preload("res://src/presentation/player_hit.gd").new()
var damage_feedback = preload("res://src/presentation/damage_feedback.gd").new()
var weapon_hit_ms := 0.0
var intro_stage := -1
var rng := RandomNumberGenerator.new()
var settings := {"sensitivity": .0025, "invert": false, "aim_assist": true}
var audio := preload("res://src/presentation/audio_settings.gd").effect_player()
var capture_button_held := false
var web_mouse_input := OS.has_feature("web")
var mouse_flight_enabled := false
var web_lock_observed := false
var laser_sound: AudioStreamWAV
var ambience := Node3D.new()
var checkpoint_elapsed := 0.0
var first_person := false


func setup(data, state, options: Dictionary, resume: bool = false) -> void:
	library = data
	session = state
	speed = session.Motion.speed(session.motion, library.content.player_motion)
	weapon_timers = session.combat.cooldowns
	settings.merge(options, true)
	rng.seed = state.station_id * 7381 + 271
	effect_random.randomize()
	ship.collision_layer = 0
	ship.collision_mask = 0
	add_child(ship)
	var hull: MeshInstance3D = library.model(library.ship_model(session.ship_id))
	ship.add_child(hull)
	player_hull = hull
	library.attach_ship_exhaust(
		hull, int(library.content.tables.buyable_ships[session.ship_id]), true
	)
	update_player_exhaust(speed)
	ship.position = session.Mission.SPAWN_POSITION
	if resume and session.flight_position != Vector3.ZERO:
		ship.position = session.flight_position
		ship.rotation = session.flight_rotation
	add_child(camera)
	camera.current = true
	camera.fov = 70
	camera.far = 45000
	# Mission geometry comes from its imported actors, fields and fog. The
	# exploration area must not inject scenery or obstacles into a mission.
	backdrop = Backdrop.new()
	add_child(backdrop)
	backdrop.configure(
		library,
		session.station_id,
		int(session.active_job.chapter) if session.active_job.get("kind") == "campaign" else -1,
		int(session.active_job.seed) if session.slot == "survival" else -1
	)
	var flare_layer := CanvasLayer.new()
	flare_layer.layer = 0
	add_child(flare_layer)
	lens_flare = preload("res://src/presentation/lens_flare.gd").new()
	flare_layer.add_child(lens_flare)
	lens_flare.configure(library, camera, backdrop.declaration)
	damage_feedback.configure(library)
	add_child(player_hit)
	player_hit.configure(library)
	add_child(ambience)
	if session.active_job.is_empty():
		build_station_area()
	add_child(audio)
	var sound_path: String = library.root.path_join("data/sounds/wpn_laser_01.wav")
	if FileAccess.file_exists(sound_path):
		laser_sound = AudioStreamWAV.load_from_file(sound_path)
	audio.volume_db = -12
	audio.stream = laser_sound
	spawn_targets(true)
	build_fields()
	nebula = Nebula.new()
	add_child(nebula)
	nebula.configure(
		library,
		session.mission_definition(),
		int(session.active_job.get("seed", 0)),
		session.station_id
	)
	update_objective()
	update_camera(1.0)
	sync_projectiles()


func update_player_exhaust(forward_speed: float) -> void:
	if not is_instance_valid(player_hull):
		return
	# Modern variable throttle: preserve imported nozzle geometry at cruise, then
	# shorten/narrow it with forward travel. Sideways motion does not power rear
	# engines, and time acceleration does not add thrust.
	var cruise: float = library.content.player_motion.cruise_speed
	var ratio := clampf(forward_speed / cruise, 0.0, 1.0)
	for nozzle in player_hull.get_children():
		if not nozzle.has_meta("exhaust_scale"):
			continue
		nozzle.visible = ratio > 0.0
		if ratio > 0.0:
			var base: Vector3 = nozzle.get_meta("exhaust_scale")
			nozzle.scale = base * Vector3(sqrt(ratio), sqrt(ratio), ratio)


func build_station_area() -> void:
	var area := preload("res://src/presentation/station_area.gd").new()
	add_child(area)
	if not area.configure(
		library, library.location_station_type(session.station_id), rng, session.exploration_area()
	):
		message_changed.emit(area.error)
		return
	station = area.station
	# Keep the existing ambience handle for mission isolation and scene ownership.
	ambience.free()
	ambience = area.field
	var scenery: Dictionary = session.field_state()
	for index in scenery.get("rocks", []).size():
		field_rocks.append({"node": ambience.get_child(index), "state": scenery.rocks[index]})
	station.set_elapsed(session.elapsed * 1000.0)
	station.enable_collision()
	var player_radius: float = library.actor_radius(
		int(library.content.tables.buyable_ships[session.ship_id])
	)
	var shape := SphereShape3D.new()
	shape.radius = player_radius
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ship.add_child(collider)
	ship.collision_mask = 1
	# Native docking access outside the whole rotating mesh, including player clearance.
	dock_radius = station.outer_radius() + player_radius * 2.0


func _ready() -> void:
	Input.joy_connection_changed.connect(controller_connection)


func controller_connection(device: int, connected: bool) -> void:
	if not connected and controls.device == device:
		controls.clear()
		paused = true
		message_changed.emit("Controller disconnected. Open the pause menu to resume.")


func _unhandled_input(event: InputEvent) -> void:
	controls.accept(event)
	if paused or cinematic_locked():
		return
	if (
		OS.has_feature("web") and event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
		and event.device != InputEvent.DEVICE_ID_EMULATION
		and not settings.get("touch", false)
		and not mouse_is_captured()
	):
		# Escape can release browser pointer lock independently of the game.
		# A fresh click in flight must always be able to acquire it again.
		capture_mouse()
		get_viewport().set_input_as_handled()
		return
	if (
		event is InputEventMouseMotion and mouse_steering_enabled()
		and event.device != InputEvent.DEVICE_ID_EMULATION
	):
		ship.rotate_y(-event.relative.x * float(settings.sensitivity))
		ship.rotate_object_local(
			Vector3.RIGHT,
			-event.relative.y * float(settings.sensitivity) * (-1 if settings.invert else 1)
		)
		ship.transform.basis = ship.transform.basis.orthonormalized()
		if event.relative.length() > 2:
			auto_pilot = false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_Q:
				session.cycle_weapon()
				if session.weapon_id >= 0:
					message_changed.emit(library.item_name(session.weapon_id))
			KEY_R:
				toggle_autopilot()
			KEY_T:
				cycle_time()
			KEY_E:
				try_dock()
			KEY_C:
				first_person = not first_person
				ship.visible = not first_person
			KEY_TAB:
				if mouse_flight_enabled or mouse_is_captured(): release_mouse()
				else: capture_mouse()
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_X:
				session.cycle_weapon()
			JOY_BUTTON_Y:
				try_dock()
			JOY_BUTTON_LEFT_SHOULDER:
				toggle_autopilot()
			JOY_BUTTON_RIGHT_SHOULDER:
				cycle_time()


func cinematic_locked() -> bool:
	if library == null or session == null or session.active_job.is_empty():
		return false
	return (
		session.Mission.Sequence.directives(session.mission_definition(), session.active_job).locked
	)


func toggle_autopilot() -> void:
	if cinematic_locked() or session.slot == "survival":
		return
	auto_pilot = not auto_pilot
	if auto_pilot:
		throttle = 1.0
	message_changed.emit("Autopilot engaged" if auto_pilot else "Manual flight")


func cycle_time() -> void:
	var speeds := [1, 2, 4, 8, 16]
	time_factor = speeds[(speeds.find(time_factor) + 1) % speeds.size()]
	if not auto_pilot:
		time_factor = mini(time_factor, 2)
	if danger():
		time_factor = 1
	message_changed.emit("Simulation speed ×%d" % time_factor)


func danger() -> bool:
	return (
		cinematic_locked()
		or actors.any(hostile)
		or recent_damage > 0
		or session.combat.projectiles.any(hostile_shot)
	)


func hostile_shot(shot: Dictionary) -> bool:
	return session.Combat.team(int(shot.weapon), library, session.actor_weapons()) == "enemy"


func try_dock() -> void:
	if session.slot == "survival":
		return
	if not session.active_job.is_empty():
		message_changed.emit("Complete the mission objectives to reach the destination station.")
		return
	if station == null:
		message_changed.emit("Station geometry is unavailable.")
		return
	if ship.position.distance_to(station.position) > dock_radius:
		message_changed.emit("Approach within %d m of the station to dock." % ceili(dock_radius))
		return
	if danger():
		message_changed.emit("Clear nearby hostiles before docking.")
		return
	dock_requested.emit()


func _physics_process(delta: float) -> void:
	watch_browser_capture()
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): capture_button_held = false
	if library == null or paused:
		return
	if danger():
		time_factor = 1
	elif not auto_pilot:
		time_factor = mini(time_factor, 2)
	elif ship.position.distance_to(waypoint) < 320:
		time_factor = 1
	for substep in time_factor:
		step(minf(delta, .05))
		if paused:
			break
		if danger():
			time_factor = 1
			break
	if paused:
		return
	session.advance_radio(delta)
	update_camera(delta)
	session.flight_position = ship.position
	session.flight_rotation = ship.rotation
	checkpoint_elapsed += delta


func step(dt: float) -> void:
	if paused:
		return
	if session.hull <= 0:
		lose_ship()
		return
	if finish_if_ready():
		return
	if not session.active_job.is_empty():
		session.active_job.camera_position = session.Combat.packed(camera.position)
	session.flight_position = ship.position
	session.advance_mission(dt)
	# Commit the final wreck frame before a target objective opens results.
	advance_explosions(dt)
	if session.active_job.is_empty():
		session.Mission.Scenery.advance(session.field_definition(), session.field_state(), dt)
	sync_fields()
	if finish_if_ready():
		return
	if session.active_job.get("failed", false):
		paused = true
		mission_failed.emit()
		return
	var previous_player := ship.position
	var forward_travel := 0.0
	player_hit.begin_step()
	simulation_time += dt
	session.elapsed += dt
	if station != null:
		station.set_elapsed(session.elapsed * 1000.0)
	recent_damage = maxf(0, recent_damage - dt)
	damage_feedback.advance(dt * 1000.0)
	weapon_hit_ms = maxf(0, weapon_hit_ms - dt * 1000.0)
	var shield_interval: float = session.loadout.shield_interval()
	if shield_interval > 0 and session.shield < session.max_shield():
		shield_timer += dt
		if shield_timer >= shield_interval:
			session.shield = minf(
				session.max_shield(), session.shield + floorf(shield_timer / shield_interval)
			)
			shield_timer = fmod(shield_timer, shield_interval)
	else:
		shield_timer = 0
	var directions: Dictionary = session.Mission.Sequence.directives(
		session.mission_definition(), session.active_job
	)
	var frozen: bool = directions.frozen
	if not directions.locked and not frozen:
		var pad := controls.snapshot()
		var up := (
			float(Input.is_physical_key_pressed(KEY_W))
			- float(Input.is_physical_key_pressed(KEY_S))
			+ float(pad.throttle)
		)
		var strafe := (
			float(Input.is_physical_key_pressed(KEY_D))
			- float(Input.is_physical_key_pressed(KEY_A))
			+ float(pad.strafe)
		)
		var yaw: float = (
			float(Input.is_physical_key_pressed(KEY_LEFT))
			- float(Input.is_physical_key_pressed(KEY_RIGHT))
			- pad.look.x
		)
		var pitch: float = (
			float(Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_UP))
			- pad.look.y
		)
		throttle = clampf(throttle + up * dt * .55, 0, 1)
		if absf(strafe) + absf(up) + absf(yaw) + absf(pitch) > .01:
			auto_pilot = false
		if auto_pilot:
			var direction: Vector3 = navigation_target() - ship.position
			var arrival_radius: float = (
				dock_radius - ship.safe_margin * 2.0
				if station != null and session.active_job.is_empty()
				else (180.0 if waypoint == Vector3.ZERO else 100.0)
			)
			if direction.length() > arrival_radius:
				var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
				ship.basis = ship.basis.slerp(target_basis, minf(dt * 2.2, 1)).orthonormalized()
				throttle = clampf((direction.length() - arrival_radius) / 100.0, .12, 1.0)
			else:
				throttle = 0
				if session.active_job.is_empty() or session.active_job.get("ready", false):
					auto_pilot = false
		else:
			ship.rotate_y(yaw * dt * 1.2)
			ship.rotate_object_local(Vector3.RIGHT, pitch * dt * 1.2)
			ship.basis = ship.basis.orthonormalized()
		var boost_down: bool = (
			Input.is_physical_key_pressed(KEY_SHIFT) or pad.boost or controls.touch_boost
		)
		var movement: Dictionary = session.Motion.advance(
			session.motion, library.content.player_motion, dt, boost_down and not boost_held
		)
		boost_held = boost_down
		var travel := (
			Vector3(
				strafe * float(library.content.player_motion.cruise_speed) * dt,
				0,
				-float(movement.forward)
			)
			. limit_length(float(movement.limit))
		)
		forward_travel = -travel.z
		speed = travel.length() / dt
		if station != null:
			var collision := ship.move_and_collide(ship.basis * travel)
			if collision != null:
				forward_travel = minf(
					forward_travel, maxf(0, collision.get_travel().dot(-ship.basis.z))
				)
				speed = ship.position.distance_to(previous_player) / dt
		else:
			ship.position += ship.basis * travel

		if (
			(
				Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
				and mouse_steering_enabled()
				and not capture_button_held
			)
			or Input.is_physical_key_pressed(KEY_SPACE)
			or pad.fire
			or controls.touch_fire
		):
			fire()
		if Input.is_physical_key_pressed(KEY_F) or pad.missiles:
			fire_missiles()
		if not session.field_state().is_empty():
			var contact_damage: float = session.Mission.Scenery.contact(
				session.field_definition(),
				session.field_state(),
				previous_player,
				ship.position,
				dt
			)
			if contact_damage > 0:
				hit(contact_damage)
				sync_fields()
				if paused:
					return
	else:
		controls.clear()
		boost_held = false
		auto_pilot = false
		if not frozen:
			# Captured controls still allow flight; explicit freeze preserves
			# velocity for the moment the authored conversation releases it.
			var movement: Dictionary = session.Motion.advance(
				session.motion, library.content.player_motion, dt
			)
			forward_travel = float(movement.forward)
			ship.position -= ship.basis.z * forward_travel
			speed = session.Motion.speed(session.motion, library.content.player_motion)
		time_factor = 1
	for event in session.Mission.advance_mines(
		session.mission_definition(), session.active_job, dt, ship.position, library
	):
		for actor in actors:
			if int(actor.index) == int(event.actor):
				actor.node.get_child(0).sync(actor.state.mine, event)
		if int(event.damage_target) == -1:
			hit(float(library.content.mine_behavior.damage))
			if paused:
				return
	previous_actors = session.Encounters.advance(
		session.mission_definition(),
		session.active_job,
		dt,
		ship.position,
		(ship.position - previous_player) / dt,
		session.combat,
		library,
		session.actor_weapons()
	)
	if not frozen:
		var contact: Dictionary = session.BodyContact.advance(
			session.motion, library.content.player_motion.contact, dt, previous_player, ship.position,
			session.BodyContact.bodies(session.mission_definition(), session.active_job, previous_actors)
		)
		if int(contact.actor) >= 0:
			ship.position = contact.position
			forward_travel = minf(forward_travel, maxf(0, (ship.position - previous_player).dot(-ship.basis.z)))
			auto_pilot = false
			time_factor = 1
			speed = ship.position.distance_to(previous_player) / dt
			if int(contact.damage) > 0:
				hit(float(contact.damage), contact.normal)
				if paused:
					return
	update_player_exhaust(forward_travel / dt)
	spawn_targets()
	for actor in actors:
		if not is_instance_valid(actor.node):
			continue
		var node: Node3D = actor.node
		node.position = session.Combat.vector(actor.state.position)
		if actor.state.has("fighter_motion"):
			advance_actor_exhaust(node, dt, float(actor.state.fighter_motion.speed))
		if actor.state.has("mine"):
			node.get_child(0).sync(actor.state.mine)
		elif actor.state.has("heading"):
			var heading: Vector3 = session.Combat.vector(actor.state.heading)
			node.basis = session.Mission.Frame.axes(heading, session.Combat.vector(actor.state.up))
		elif not session.mission_definition().groups[int(actor.state.group)].get(
			"source_scale", false
		):
			node.rotate_y(dt * .16)
	advance_projectiles(dt, previous_player)
	if paused:
		return
	if (
		session.active_job.get("kind") in ["campaign", "contract"]
		and session.Mission.route_pending(session.mission_definition(), session.active_job)
	):
		if ship.position.distance_to(waypoint) < 115:
			session.waypoint_reached()
			if int(session.active_job.stage) == session.route_length():
				spawn_targets()
			update_objective()
	update_objective(false)
	finish_if_ready()


func finish_if_ready() -> bool:
	if session.active_job.get("ready", false):
		time_factor = 1
		if session.ready_to_finish():
			paused = true
			mission_completed.emit()
		return true
	return false


func navigation_target() -> Vector3:
	return waypoint


func hit(amount: float, incoming: Vector3 = Vector3.ZERO) -> void:
	if session.hull <= 0 or not is_finite(amount) or amount <= 0:
		return
	if not (
		session
		. Mission
		. Sequence
		. directives(session.mission_definition(), session.active_job)
		. vulnerable
	):
		return
	damage_feedback.hit(camera, incoming)
	recent_damage = 4
	time_factor = 1
	var absorbed := minf(session.shield, amount)
	session.shield -= absorbed
	session.hull -= amount - absorbed
	player_hit.flash(session.shield, ship.global_transform)
	if session.hull <= 0:
		lose_ship()


func fire() -> void:
	var weapons: Array[int] = []
	if settings.get("linked_fire", false):
		weapons.assign(session.loadout.primary_weapons())
	if not settings.get("linked_fire", false) and session.weapon_id >= 0:
		weapons.append(session.weapon_id)
	for id in weapons:
		if float(weapon_timers.get(id, 0)) > 0:
			continue
		fire_weapon(id)


func fire_missiles() -> void:
	for id in session.loadout.weapons():
		if (
			int(library.items[id][1]) != library.MISSILE_CATEGORY
			or float(weapon_timers.get(id, 0)) > 0
		):
			continue
		fire_weapon(id)


func fire_weapon(weapon_id: int) -> void:
	if cinematic_locked() or not session.weapon_enabled(weapon_id):
		return
	if paused or session.docked:
		return
	var profiles: Dictionary = session.actor_weapons()
	var definition: Dictionary = session.Combat.profile(weapon_id, library, profiles)
	if definition.is_empty():
		return
	var forward := -ship.basis.z
	var direction := forward
	# Aim assistance chooses an initial firing direction. Bullets then travel
	# independently; turning the ship cannot bend a shot already in flight.
	if settings.aim_assist:
		var best := float(definition.speed) * float(definition.lifetime)
		for actor in actors:
			if not hostile(actor):
				continue
			var offset: Vector3 = actor.node.position - ship.position
			var distance := offset.length()
			if (
				distance > .001
				and distance < best
				and offset.normalized().dot(forward) > cos(deg_to_rad(3))
			):
				direction = offset.normalized()
				best = distance
	var fired := false
	var muzzles: Array[int] = session.player_weapon_ids(weapon_id)
	var origins: Array[Vector3] = []
	for muzzle in muzzles:
		var gun: Dictionary = session.Combat.profile(muzzle, library, profiles)
		var origin := ship.position
		if gun.has("mount_offset"):
			origin += ship.basis * session.Mission.point(gun.mount_offset)
		origins.append(origin)
	if definition.has("trigger_weapon"):
		fired = session.Combat.fire_volley(
			session.combat, muzzles, origins, direction, library, profiles
		)
	else:
		for index in muzzles.size():
			if session.Combat.fire(
				session.combat, muzzles[index], origins[index], direction, library, profiles
			):
				fired = true
	if not fired:
		return
	sync_projectiles()
	if laser_sound != null and DisplayServer.get_name() != "headless":
		audio.play()


func advance_projectiles(dt: float, previous_player: Vector3 = Vector3.INF) -> void:
	var targets: Array = [
		{
			"id": -1,
			"position": session.Combat.packed(ship.position),
			"previous":
			session.Combat.packed(
				previous_player if previous_player.is_finite() else ship.position
			),
			"radius":
			library.actor_radius(int(library.content.tables.buyable_ships[session.ship_id]))
		}
	]
	for actor in actors:
		if (
			is_instance_valid(actor.node)
			and actor.state.hp > 0
			and session.Mission.actor_active(
				session.mission_definition(), session.active_job, actor.state
			)
		):
			targets.append(
				{
					"id": int(actor.index),
					"team": "enemy" if hostile(actor) else "ally",
					"position": session.Combat.packed(actor.node.position),
					"radius": library.actor_radius(int(actor.actor_type)),
					"previous":
					previous_actors.get(
						int(actor.index), session.Combat.packed(actor.node.position)
					)
				}
			)
			var group: Dictionary = session.mission_definition().groups[int(actor.state.group)]
			var boxes: Array = group.get(
				"collisions", [group.collision] if group.has("collision") else []
			)
			if not boxes.is_empty():
				var body: Dictionary = targets.pop_back()
				for box in boxes:
					var target := body.duplicate(true)
					var offset: Vector3 = session.Mission.point(box.offset)
					target.position = session.Combat.packed(
						session.Combat.vector(body.position) + offset
					)
					target.previous = session.Combat.packed(
						session.Combat.vector(body.previous) + offset
					)
					target.extent = session.Combat.packed(
						session.Mission.point(box.size).abs() * .5
					)
					targets.append(target)

	var scenery: Dictionary = session.field_state()
	var actor_count: int = session.active_job.get("actors", []).size()
	if not scenery.is_empty():
		targets.append_array(
			session.Mission.Scenery.targets(session.field_definition(), scenery, actor_count)
		)
	for impact in session.Combat.advance(
		session.combat, dt, targets, library, session.actor_weapons(), guidance_candidates()
	):
		if int(impact.target) == -1:
			hit(float(impact.damage), session.Combat.vector(impact.incoming))
			if paused:
				break
			continue
		if int(impact.weapon) >= 0:
			weapon_hit_ms = float(library.content.flight_ui.radar.hit_ms)
		if int(impact.target) >= actor_count and not scenery.is_empty():
			var missile: bool = (
				int(impact.weapon) >= 0
				and (
					int(library.items[int(impact.weapon) % library.items.size()][1])
					== library.MISSILE_CATEGORY
				)
			)
			session.Mission.Scenery.hit(scenery, int(impact.target) - actor_count, missile)
			sync_fields()
			continue
		if not session.damage_actor(int(impact.target), float(impact.damage)):
			continue
		var profile: Dictionary = session.Combat.profile(
			int(impact.weapon), library, session.actor_weapons()
		)
		if session.Mission.Impact.rocket(int(impact.weapon), library, profile):
			session.Mission.Impact.receive(
				session.active_job.actors[int(impact.target)],
				session.Combat.vector(impact.velocity),
				library.content.fighter_impact
			)
		for actor in actors.duplicate():
			if int(actor.index) != int(impact.target) or actor.state.hp > 0:
				continue
			if actor.state.has("mine"):
				actor.node.get_child(0).sync(actor.state.mine)
				continue
			actor_destroyed(actor)
			actors.erase(actor)
			update_objective()
	sync_projectiles(true)


func guidance_candidates() -> Array:
	# Collision geometry omits dead/inactive actors. A rocket's existing lock
	# still tracks their retained position, so guidance needs the full actor list.
	if not session.combat.projectiles.any(func(shot): return shot.has("guidance")):
		return []
	var candidates := [
		{
			"id": -1,
			"team": "ally",
			"position": session.Combat.packed(ship.position),
			"alive": session.hull > 0,
			"active": true,
			"visible": guidance_visible(ship.position)
		}
	]
	var definition: Dictionary = session.mission_definition()
	for index in session.active_job.get("actors", []).size():
		var actor: Dictionary = session.active_job.actors[index]
		var group: Dictionary = definition.groups[int(actor.group)]
		var point: Vector3 = session.Combat.vector(actor.position)
		candidates.append(
			{
				"id": index,
				"team": group.get("team", "enemy"),
				"position": actor.position,
				"alive": actor.hp > 0,
				"active":
				(
					session.Mission.actor_active(definition, session.active_job, actor)
					and actor.get("awake", true)
				),
				"visible": guidance_visible(point)
			}
		)
	return candidates


func guidance_visible(point: Vector3) -> bool:
	return (
		camera.to_local(point).z <= -camera.near
		and get_viewport().get_visible_rect().has_point(camera.unproject_position(point))
	)


func sync_projectiles(advance_trails: bool = false) -> void:
	var alive := {}
	var profiles: Dictionary = session.actor_weapons()
	for shot in session.combat.projectiles:
		var id := int(shot.id)
		var profile: Dictionary = session.Combat.profile(int(shot.weapon), library, profiles)
		alive[id] = true
		if profile.has("trail"):
			if not projectile_trails.has(id):
				var trail = preload("res://src/presentation/projectile_trail.gd").new()
				add_child(trail)
				trail.configure(library, profile.trail, session.Combat.vector(shot.position))
				projectile_trails[id] = trail
			elif advance_trails:
				projectile_trails[id].advance(session.Combat.vector(shot.position))
		var visual_key := [
			profile.get("projectile_model", -1), profile.get("projectile_overlay", -1)
		]
		if bolts.has(id) and bolts[id].get_meta("projectile_key", []) != visual_key:
			bolts[id].queue_free()
			bolts.erase(id)
		if not bolts.has(id):
			var node: MeshInstance3D
			if profile.has("projectile_model"):
				var resource: Dictionary = library.content.resources[str(
					int(profile.projectile_model)
				)]
				node = library.model(resource.path.get_file().get_basename())
				if profile.has("projectile_overlay"):
					var overlay: Dictionary = library.content.resources[str(
						int(profile.projectile_overlay)
					)]
					node.add_child(library.model(overlay.path.get_file().get_basename()))
			else:
				if bolt_mesh == null:
					bolt_mesh = CylinderMesh.new()
					bolt_mesh.top_radius = .45
					bolt_mesh.bottom_radius = .45
					bolt_mesh.height = 10
					bolt_mesh.radial_segments = 5
					bolt_material = StandardMaterial3D.new()
					bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					bolt_material.albedo_color = Color("74e8ff")
					enemy_bolt_material = bolt_material.duplicate()
					enemy_bolt_material.albedo_color = Color("ff8060")
				node = MeshInstance3D.new()
				node.mesh = bolt_mesh
				node.material_override = (
					enemy_bolt_material
					if (
						session.Combat.team(int(shot.weapon), library, session.actor_weapons())
						== "enemy"
					)
					else bolt_material
				)
			add_child(node)
			node.set_meta("projectile_key", visual_key)
			bolts[id] = node
		var node: Node3D = bolts[id]
		node.position = session.Combat.vector(shot.position)
		var direction: Vector3 = session.Combat.vector(shot.velocity).normalized()
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > .99 else Vector3.UP
		node.basis = Basis.looking_at(direction, up)
		if not profile.has("projectile_model"):
			node.basis *= Basis(Vector3.RIGHT, PI / 2)
	for id in projectile_trails.keys():
		if not alive.has(id):
			projectile_trails[id].queue_free()
			projectile_trails.erase(id)
	for id in bolts.keys():
		if not alive.has(id):
			bolts[id].queue_free()
			bolts.erase(id)


func actor_visual(definition: Dictionary, state: Dictionary) -> Node3D:
	var group: Dictionary = definition.groups[int(state.group)]
	var node := Node3D.new()
	node.set_meta("actor_type", int(group.actor))
	add_child(node)
	if state.has("mine"):
		var visual = preload("res://src/presentation/mine_visual.gd").new()
		node.add_child(visual)
		visual.sound_requested.connect(play_mine_sound)
		visual.configure(library, state.mine)
	elif group.get("render_mesh", true):
		# AEM vertices already use the simulation's world-unit conversion. Preserve
		# each source hull's dimensions, including its attached nozzle transforms.
		var hull: MeshInstance3D = library.model(library.actor_model(int(group.actor)))
		node.add_child(hull)
		library.attach_ship_exhaust(hull, int(group.actor))
		if state.has("fighter_motion"):
			var burner = preload("res://src/presentation/npc_exhaust.gd").new()
			hull.add_child(burner)
			burner.configure(library.content.npc_exhaust, hull)
			node.set_meta("npc_exhaust", burner)
	node.position = session.Combat.vector(state.position)
	if state.has("heading"):
		var heading: Vector3 = session.Combat.vector(state.heading)
		node.basis = session.Mission.Frame.axes(heading, session.Combat.vector(state.up))
	return node


func spawn_targets(restoring: bool = false) -> void:
	if (
		session.active_job.is_empty()
		or session.active_job.get("ready", false)
		or session.active_job.get("failed", false)
	):
		return
	var definition: Dictionary = session.mission_definition()
	for index in session.active_job.actors.size():
		var state: Dictionary = session.active_job.actors[index]
		var present: bool = (
			(state.hp > 0 or (state.has("mine") and not session.Mission.actor_dead(state)))
			and session.Mission.group_active(definition, session.active_job, int(state.group))
		)
		if state.hp > 0:
			wrecks.erase(index)
		var current_type := int(definition.groups[int(state.group)].actor)
		for existing in actors.duplicate():
			if int(existing.index) == index and int(existing.actor_type) != current_type:
				existing.node.queue_free()
				actors.erase(existing)
		if (
			dormant_visuals.has(index)
			and dormant_visuals[index].get_meta("actor_type", -1) != current_type
		):
			dormant_visuals[index].queue_free()
			dormant_visuals.erase(index)
		# Source sleep disables combat, not the already-created model. Keeping a
		# separate visual avoids creating aim-assist or damage targets prematurely.
		if present and not state.get("awake", true):
			if not dormant_visuals.has(index):
				dormant_visuals[index] = actor_visual(definition, state)
			dormant_visuals[index].position = session.Combat.vector(state.position)
			continue
		if dormant_visuals.has(index):
			dormant_visuals[index].queue_free()
			dormant_visuals.erase(index)
		if not present:
			for existing in actors.duplicate():
				if int(existing.index) == index:
					if state.hp <= 0 and not state.has("mine"):
						actor_destroyed(existing)
					else:
						existing.node.queue_free()
					actors.erase(existing)
		if (
			not present
			and state.get("destruction", {}).get("phase") == "dying"
			and not wrecks.has(index)
		):
			actor_destroyed(
				{
					"node": actor_visual(definition, state),
					"state": state,
					"index": index,
					"actor_type": current_type
				},
				restoring
			)
		if not present or actors.any(func(actor): return int(actor.index) == index):
			continue
		var actor_type := int(definition.groups[int(state.group)].actor)
		actors.append(
			{
				"node": actor_visual(definition, state),
				"state": state,
				"index": index,
				"actor_type": actor_type
			}
		)


func update_objective(notify: bool = true) -> void:
	var job: Dictionary = session.active_job
	if job.is_empty() or job.get("ready", false):
		waypoint = station.position if station != null else Vector3.ZERO
	else:
		var mission: Dictionary = session.mission_definition()
		if mission.get("payout_kind") == "finished_asteroids":
			waypoint = ship.position
			var nearest := INF
			for rock in job.scenery.rocks:
				if rock.hits <= 0:
					continue
				var position: Vector3 = session.Combat.vector(rock.position)
				var distance := ship.position.distance_squared_to(position)
				if distance < nearest:
					nearest = distance
					waypoint = position
			if notify:
				objective_changed.emit()
			return
		if mission.success.kind == "time_survived":
			var center := Vector3.ZERO
			var count := 0
			for actor in job.actors:
				if actor.hp > 0 and not session.Mission.enemy(mission, actor):
					center += session.Combat.vector(actor.position)
					count += 1
			waypoint = center / count if count > 0 else ship.position
			if notify:
				objective_changed.emit()
			return
		if mission.success.kind == "enemy_prefix_destroyed":
			var seen := 0
			var nearest := INF
			for actor in job.actors:
				if not session.Mission.enemy(mission, actor):
					continue
				if seen >= int(mission.success.count):
					break
				seen += 1
				if actor.hp <= 0:
					continue
				var point: Vector3 = session.Combat.vector(actor.position)
				var distance := ship.position.distance_squared_to(point)
				if distance < nearest:
					nearest = distance
					waypoint = point
			if notify:
				objective_changed.emit()
			return
		var stage := int(job.stage)
		var route: Array[Vector3] = session.mission_route()
		if session.Mission.route_pending(mission, job):
			waypoint = route[stage]
		else:
			if mission.success.kind == "enemy_destroyed":
				var selected := 0
				for actor in job.actors:
					if session.Mission.enemy(mission, actor):
						if selected == int(mission.success.index):
							waypoint = session.Combat.vector(actor.position)
							if notify:
								objective_changed.emit()
							return
						selected += 1
			var enemies := actors.filter(func(actor): return hostile(actor))
			if enemies.is_empty():
				# A dormant encounter still has an imported target area to fly to.
				var definition: Dictionary = session.mission_definition()
				var closest := INF
				for actor in job.actors:
					if (
						actor.hp <= 0
						or not session.Mission.enemy(definition, actor)
						or not definition.groups[int(actor.group)].get("combat_active", true)
					):
						continue
					var center: Vector3 = session.Combat.vector(actor.position)
					var distance := ship.position.distance_squared_to(center)
					if distance < closest:
						closest = distance
						waypoint = center
				if notify:
					objective_changed.emit()
				return
			var nearest: Dictionary = enemies[0]
			for actor in enemies:
				if (
					actor.node.position.distance_squared_to(ship.position)
					< nearest.node.position.distance_squared_to(ship.position)
				):
					nearest = actor
			waypoint = nearest.node.position
	if notify:
		objective_changed.emit()


func objective() -> String:
	var job: Dictionary = session.active_job
	if job.is_empty():
		return "Free flight · Explore the station sector"
	if job.get("ready", false):
		return (
			"Objectives complete · Receiving transmission"
			if not session.ready_to_finish()
			else "Objectives complete · Arriving at the destination station"
		)
	if cinematic_locked():
		return "Mission · Stand by"
	var mission: Dictionary = session.mission_definition()
	if mission.get("payout_kind") == "finished_asteroids":
		var seconds := ceili(
			maxf(0, float(mission.success.duration_ms) - float(job.elapsed_ms)) / 1000.0
		)
		return (
			"Asteroids cleared  %d · %d credits · %d:%02d remaining"
			% [
				session.Mission.Scenery.destroyed(job.scenery),
				session.mission_reward(),
				seconds / 60,
				seconds % 60
			]
		)
	if mission.success.kind == "time_survived":
		var alive := 0
		var total := 0
		for actor in job.actors:
			if not session.Mission.enemy(mission, actor):
				total += 1
				alive += 1 if actor.hp > 0 else 0
		var seconds := ceili(
			maxf(0, float(mission.success.duration_ms) - float(job.elapsed_ms)) / 1000.0
		)
		return (
			"Protect convoy  %d / %d ships · %d:%02d remaining"
			% [alive, total, seconds / 60, seconds % 60]
		)
	if (
		session.Mission.route_pending(mission, job)
		and mission.success.kind != "enemy_prefix_destroyed"
	):
		return "Mission · Reach waypoint %d / %d" % [int(job.stage) + 1, session.route_length()]
	if mission.success.kind == "message_shown" and job.kills >= job.target:
		return "Mission · Receiving closing transmission"
	if mission.success.kind == "enemy_destroyed":
		return "Mission · Destroy the marked target"
	var remaining := ""
	var limit := float(session.mission_definition().deadline_ms)
	if limit > 0:
		var seconds := ceili(maxf(0, limit - float(job.elapsed_ms)) / 1000.0)
		remaining = " · %d:%02d remaining" % [seconds / 60, seconds % 60]
	if mission.success.kind == "enemy_prefix_destroyed":
		return (
			(
				"Clear targets  %d / %d"
				% [
					session.Mission.destroyed_prefix(mission, job, int(mission.success.count)),
					int(mission.success.count)
				]
			)
			+ remaining
		)
	return "Clear targets  %d / %d" % [int(job.kills), int(job.target)] + remaining


func update_camera(dt: float) -> void:
	var direction: Dictionary = session.Mission.Sequence.directives(
		session.mission_definition(), session.active_job
	)
	var focus: Dictionary = direction.focus
	if (
		not focus.is_empty()
		and (
			int(focus.actor) >= 0
			or session.Mission.point(focus.get("offset", [0, 0, 0])).length_squared() > 0
		)
	):
		var position: Vector3 = (
			session.Combat.vector(session.active_job.actors[int(focus.actor)].position)
			if int(focus.actor) >= 0
			else ship.position
		)
		var orientation := Basis.IDENTITY
		if focus.get("relative", false):
			orientation = ship.basis
			if int(focus.actor) >= 0:
				var heading: Vector3 = session.Combat.vector(
					session.active_job.actors[int(focus.actor)].get("heading", [0, 0, -1])
				)
				orientation = session.Mission.Frame.axes(
					heading,
					session.Combat.vector(
						session.active_job.actors[int(focus.actor)].get("up", [0, 0, 0])
					)
				)
		var desired: Vector3 = (
			session.Combat.vector(focus.position)
			if focus.kind == "focus_between"
			else position + orientation * session.Mission.point(focus.offset)
		)
		position += orientation * session.Mission.point(focus.get("target_offset", [0, 0, 0]))
		if not direction.camera_anchor.is_empty():
			desired = session.Combat.vector(direction.camera_anchor)
		camera.position = camera.position.lerp(desired, minf(dt * 8, 1))
		if camera.position.distance_squared_to(position) > .001:
			camera.look_at(
				position,
				(
					Vector3.RIGHT
					if absf((position - camera.position).normalized().dot(Vector3.UP)) > .99
					else Vector3.UP
				)
			)
		if backdrop != null:
			backdrop.follow(camera)
		return
	var desired := (
		ship.position
		if first_person
		else ship.position + ship.basis.z * follow_distance + ship.basis.y * 15
	)
	camera.position = camera.position.lerp(desired, minf(dt * 8, 1))
	camera.basis = camera.basis.slerp(ship.basis, minf(dt * 10, 1)).orthonormalized()

	if backdrop != null:
		backdrop.follow(camera)


func pause(value: bool) -> void:
	paused = value
	controls.clear()
	time_factor = 1
	if value or settings.get("touch", false):
		release_mouse()
	else:
		capture_mouse()


func mouse_is_captured() -> bool:
	if OS.has_feature("web"):
		# The browser may revoke/reject lock while Godot still remembers Captured.
		return bool(JavaScriptBridge.eval("document.pointerLockElement !== null"))
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func mouse_steering_enabled() -> bool:
	if settings.get("touch", false):
		return false
	# Some browsers reject recapture after Escape, even from Resume. Keep
	# canvas motion usable while waiting for a fresh capture gesture.
	return mouse_flight_enabled if web_mouse_input else Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func watch_browser_capture() -> void:
	if not web_mouse_input or paused or not mouse_flight_enabled:
		return
	var captured := mouse_is_captured()
	if web_lock_observed and not captured:
		# Escape's default browser action can swallow the key event. An actual
		# locked -> unlocked transition must still pause, once. Failed initial
		# requests and deliberate releases (Tab/menus/touch) do not enter here.
		pause(true)
		pause_requested.emit()
		return
	web_lock_observed = captured


func release_mouse() -> void:
	mouse_flight_enabled = false
	web_lock_observed = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func capture_mouse() -> void:
	mouse_flight_enabled = true
	web_lock_observed = false
	if OS.has_feature("web"):
		capture_button_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	audio.stop()
	audio.stream = null


func hostile(actor: Dictionary) -> bool:
	var definition: Dictionary = session.mission_definition()
	return (
		session.Mission.enemy(definition, actor.state)
		and session.Mission.actor_active(definition, session.active_job, actor.state)
	)


func build_fields() -> void:
	var definition: Dictionary = session.mission_definition()
	for rock in session.active_job.get("scenery", {}).get("rocks", []):
		var field: Dictionary = definition.scenery[int(rock.field)]
		var node = preload("res://src/presentation/asteroid_visual.gd").new()
		node.configure(library, field, rock)
		node.position = session.Combat.vector(rock.position)
		add_child(node)
		field_rocks.append({"node": node, "state": rock})
	sync_fields()


func sync_fields() -> void:
	for rock in field_rocks:
		rock.node.sync(rock.state)


func actor_destroyed(actor: Dictionary, restored: bool = false) -> void:
	var effect = preload("res://src/presentation/explosion.gd").new()
	add_child(effect)
	var clock: Dictionary = actor.get("state", {}).get("destruction", {})
	var seed_value := effect_random.randi()
	if not clock.is_empty():
		# A stable cosmetic seed restores debris without consuming combat RNG.
		seed_value = int(session.active_job.seed) ^ (int(actor.index) * 7919)
		effect.set_meta("destruction_clock", clock)
		effect.set_meta("actor_index", int(actor.index))
		wrecks[int(actor.index)] = effect
	effect.configure(
		library,
		int(library.content.actor_destruction.actors[int(actor.actor_type)]),
		actor.node.global_transform,
		seed_value,
		float(clock.get("elapsed_ms", 0.0)),
		restored
	)
	effect.attach_body(actor.node)
	explosions.append(effect)


func advance_actor_exhaust(node: Node3D, seconds: float, current_speed: float) -> void:
	if not is_instance_valid(node) or not node.has_meta("npc_exhaust"):
		return
	var burner = node.get_meta("npc_exhaust")
	if is_instance_valid(burner):
		burner.advance(seconds, current_speed)


func advance_explosions(seconds: float) -> void:
	for effect in explosions.duplicate():
		if effect.has_meta("destruction_clock"):
			var clock: Dictionary = effect.get_meta("destruction_clock")
			var index: int = effect.get_meta("actor_index")
			var states: Array = session.active_job.get("actors", [])
			if index < states.size() and is_same(states[index].get("destruction"), clock):
				# A reused survival slot owns a different clock; its old effect stays put.
				effect.global_position = session.Combat.vector(states[index].position)
			effect.elapsed_ms = (
				session.Mission.Destruction.span(effect.definition)
				if clock.phase == "dead"
				else float(clock.elapsed_ms)
			)
			effect.sync()
			# A wreck's current motion decays; its nozzle envelope releases too.
			# The body owns the controller, independently of a reused survival slot.
			advance_actor_exhaust(
				effect.body, seconds, session.Combat.vector(clock.velocity).length()
			)
		else:
			effect.advance(seconds)
		if effect.finished and effect.sounds.all(func(player): return not player.playing):
			var index: int = effect.get_meta("actor_index", -1)
			if wrecks.get(index) == effect:
				wrecks.erase(index)
			effect.queue_free()
			explosions.erase(effect)


func play_mine_sound(id: int) -> void:
	# Flight owns the sound so removing a finished mine cannot cut off its tail.
	var player := preload("res://src/presentation/audio_settings.gd").effect_player()
	player.name = "MineSound"
	add_child(player)
	player.stream = library.sound_clip(id)
	player.volume_linear = library.content.sound_bank[str(id)].gain
	player.finished.connect(player.queue_free)
	if player.stream != null and DisplayServer.get_name() != "headless":
		player.play()
	else:
		player.queue_free()


func lose_ship() -> void:
	if player_destroyed:
		return
	player_destroyed = true
	session.hull = 0
	paused = true
	controls.clear()
	boost_held = false
	auto_pilot = false
	time_factor = 1
	update_player_exhaust(0)
	var effect = preload("res://src/presentation/explosion.gd").new()
	add_child(effect)
	effect.configure(
		library,
		int(library.content.actor_destruction.player),
		ship.global_transform,
		effect_random.randi()
	)
	effect.attach_body(player_hull)
	explosions.append(effect)
	# The source frames death from an offset in the current camera's coordinates.
	# Reparenting the hull also makes the wreck visible after first-person flight.
	camera.global_position = (
		camera.global_transform
		* session.Combat.vector(library.content.actor_destruction.player_camera_offset)
	)
	if camera.global_position.distance_squared_to(ship.global_position) > .001:
		camera.look_at(ship.global_position, ship.basis.y)
	if backdrop != null:
		backdrop.follow(camera)
	defeated.emit()


func advance_defeat_presentation(seconds: float) -> void:
	# Results remain immediately usable. Their background destruction timeline
	# runs independently of frozen combat, deadlines, radio and survival scoring.
	if not player_destroyed or seconds <= 0 or not is_finite(seconds):
		return
	player_hit.begin_step()
	advance_explosions(seconds)
