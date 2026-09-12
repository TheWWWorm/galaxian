extends "res://tests/integration.gd"
## Player feedback batch 14: sustained fire and accelerated time must not scale
## with the number of live projectiles. Covers the flight threat test, the cached
## player weapon profiles and the prepared ballistic sweep. Existing content only.


class CountingSession:
	extends "res://src/simulation/session.gd"
	## Counts weapon-profile rebuilds so the threat test can be measured, not timed.
	var weapon_requests := 0

	func actor_weapons() -> Dictionary:
		weapon_requests += 1
		return super.actor_weapons()


func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open existing imported content")
	if failures:
		quit(1)
		return
	await check_threat_scan(lib)
	await check_profile_cache(lib)
	check_swept_targets(lib)
	print("FEEDBACK14 ", checks, " CHECKS; ", failures, " FAILURES")
	call_deferred("finish")


func finish():
	for frame in 4:
		await process_frame
	quit(1 if failures else 0)


func ally_shots(pilot, count: int) -> void:
	## Live player bolts, the case a pilot produces by firing into empty space.
	var profiles: Dictionary = pilot.actor_weapons()
	var muzzles: Array = []
	for key in profiles:
		if (
			int(key) >= 0
			and profiles[key].get("team") == "ally"
			and not profiles[key].get("legacy_projectile", false)
		):
			muzzles.append(int(key))
	muzzles.sort()
	check(not muzzles.is_empty(), "Imported content fits at least one player muzzle")
	pilot.combat.projectiles.clear()
	for index in count:
		var weapon: int = muzzles[index % muzzles.size()]
		Combat.launch(
			pilot.combat,
			weapon,
			Vector3(0, 0, -index),
			Vector3.FORWARD,
			profiles[weapon],
			lib_used,
			profiles
		)


var lib_used


func check_threat_scan(lib) -> void:
	lib_used = lib
	var pilot := CountingSession.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.depart()
	pilot.advance_mission(.5)
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	await process_frame
	check(not flight.actors.any(flight.hostile), "Debris clearance has no hostile actors")

	pilot.combat.projectiles.clear()
	pilot.weapon_requests = 0
	check(not flight.danger(), "An empty sky is not a threat")
	check(pilot.weapon_requests == 0, "No live shot needs no weapon profiles at all")

	for count in [1, 8, 24]:
		ally_shots(pilot, count)
		var live: int = pilot.combat.projectiles.size()
		pilot.weapon_requests = 0
		check(not flight.danger(), "Own bolts are not a threat (%d live)" % live)
		# The profile table is rebuilt from the mission on every request. Reading
		# it once per test rather than once per shot is the whole fix: time
		# acceleration repeats this test after every substep.
		check(
			pilot.weapon_requests == 1,
			"Threat test rebuilds weapon profiles once, not per shot (%d live)" % live
		)

	# An actor weapon keeps its imported negative identity, and an unknown one
	# still reads as hostile, so a live enemy bolt has to hold the pilot at 1x.
	ally_shots(pilot, 8)
	pilot.combat.projectiles.append(
		{
			"id": int(pilot.combat.next_id),
			"weapon": -1,
			"position": [0.0, 0.0, 0.0],
			"velocity": [0.0, 0.0, -1.0],
			"remaining": 1.0
		}
	)
	pilot.combat.next_id = int(pilot.combat.next_id) + 1
	pilot.weapon_requests = 0
	check(flight.danger(), "A live enemy bolt is still a threat")
	check(pilot.weapon_requests == 1, "Detecting an enemy bolt rebuilds profiles once")

	pilot.combat.projectiles.clear()
	flight.recent_damage = 1.0
	pilot.weapon_requests = 0
	check(flight.danger(), "Recent damage remains a threat")
	check(pilot.weapon_requests == 0, "Cheaper threat evidence skips the profile rebuild")
	flight.recent_damage = 0.0
	flight.queue_free()


func check_profile_cache(lib) -> void:
	## The player half of the weapon table is memoized on the library. It is only
	## sound while every consumer treats it as read-only, so this measures that
	## across a real mission rather than trusting the call sites.
	var Armament = preload("res://src/simulation/player_armament.gd")
	lib.player_profile_cache.clear()
	var fresh: Dictionary = Armament.build(lib, range(6))
	var served: Dictionary = Armament.profiles(lib, range(6))
	check(
		JSON.stringify(normalized(served)) == JSON.stringify(normalized(fresh)),
		"Served profiles match a freshly built table"
	)
	check(Armament.profiles(lib, range(6)) == served, "A repeat request is served from the cache")
	var other: Dictionary = Armament.profiles(lib, range(3))
	check(other != served, "A different target list rebuilds instead of reusing the cache")
	check(
		other[other.keys()[0]].get("team") == "ally", "Rebuilt entries are still player guns"
	)
	for id in served:
		if served[id].has("guidance_target_ids"):
			check(
				Armament.profiles(lib, range(6))[id].guidance_target_ids == range(6),
				"Cached guidance keeps the target list it was built for"
			)
			break

	var pilot := CountingSession.new()
	pilot.configure(lib)
	pilot.chapter = 2
	pilot.depart()
	pilot.advance_mission(.5)
	# Hold the exact table consumers are handed. Dictionaries are references, so
	# comparing this instance afterwards catches a write through any served copy,
	# even if the cache later replaced its entry under a different target list.
	var held: Dictionary = Armament.profiles(lib, range(pilot.active_job.actors.size()))
	var snapshot := JSON.stringify(normalized(held))
	var flight := Flight.new()
	root.add_child(flight)
	flight.setup(lib, pilot, {}, true)
	flight.set_physics_process(false)
	await process_frame
	var profiles: Dictionary = pilot.actor_weapons()
	var muzzles: Array = []
	for key in profiles:
		if (
			int(key) >= 0
			and profiles[key].get("team") == "ally"
			and not profiles[key].get("legacy_projectile", false)
		):
			muzzles.append(int(key))
	muzzles.sort()
	for frame in 240:
		for weapon in pilot.loadout.weapons():
			flight.fire_weapon(int(weapon))
		flight.step(1.0 / 60.0)
		if flight.paused:
			break
	check(pilot.combat.next_id > 0, "The mission actually fired during the immutability run")
	# A finished or failed job changes the target list, and a rebuild under a new
	# key is correct. What must hold is that every table the run left behind still
	# equals a fresh build of itself: nothing wrote through a served reference.
	check(
		JSON.stringify(normalized(held)) == snapshot,
		"Nothing wrote through the player profile table handed to consumers"
	)
	check(not lib.player_profile_cache.is_empty(), "The run left cached tables behind")
	for count in lib.player_profile_cache:
		var entry: Dictionary = lib.player_profile_cache[count]
		check(
			JSON.stringify(normalized(entry.profiles)) == JSON.stringify(
				normalized(Armament.build(lib, entry.targets))
			),
			"A played mission leaves the cached profiles equal to a fresh build (%d targets)" % count
		)
	flight.queue_free()


func normalized(value):
	return JSON.parse_string(JSON.stringify(value))


func shot(id: int, weapon: int, position: Vector3, velocity: Vector3) -> Dictionary:
	return {
		"id": id,
		"weapon": weapon,
		"position": Combat.packed(position),
		"velocity": Combat.packed(velocity),
		"remaining": 10.0
	}


func check_swept_targets(lib) -> void:
	## Target identity, side and swept volume are now read once per advance rather
	## than once per projectile. These pin the parts of that which were inlined:
	## the default side, the box-or-sphere choice and the moving-target sweep.
	var guns := {
		1: {"team": "ally", "damage": 5.0, "speed": 100.0, "lifetime": 10.0, "interval": .1},
		2:
		{
			"team": "ally",
			"damage": 5.0,
			"speed": 100.0,
			"lifetime": 10.0,
			"interval": .1,
			"target_ids": [0]
		},
		-7: {"team": "enemy", "damage": 5.0, "speed": 100.0, "lifetime": 10.0, "interval": .1}
	}
	var boxed := {
		"id": 1, "team": "enemy", "position": [0.0, 0.0, -50.0], "extent": [4.0, 4.0, 4.0]
	}
	var sphere := {"id": 0, "team": "enemy", "position": [30.0, 0.0, 0.0], "radius": 4.0}
	var neutral := {"id": 2, "team": "neutral", "position": [0.0, 30.0, 0.0], "radius": 4.0}
	# No team key and id -1 is the player, which defaults to the ally side.
	var player := {"id": -1, "position": [0.0, -30.0, 0.0], "radius": 4.0}

	var state: Dictionary = Combat.create()
	state.next_id = 1
	state.projectiles = [shot(0, 1, Vector3(0, 0, 0), Vector3(0, 0, -100))]
	var hits: Array = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == 1, "An ally bolt hits the boxed hostile")

	state.projectiles = [shot(1, 1, Vector3(0, 0, 0), Vector3(0, -100, 0))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.is_empty(), "An ally bolt passes through the player it shares a side with")

	state.projectiles = [shot(2, 1, Vector3(0, 0, 0), Vector3(0, 100, 0))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(
		hits.size() == 1 and int(hits[0].target) == 2,
		"Neutral scenery is hit whatever side fired"
	)

	# A hostile bolt may hit the player, whose target entry carries no side key at
	# all and has to fall back to the ally default.
	state.projectiles = [shot(3, -7, Vector3(0, 0, 0), Vector3(0, -100, 0))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == -1, "A hostile bolt hits the player")

	# Directed fire lists characters only; level geometry stays available.
	state.projectiles = [shot(4, 2, Vector3(0, 0, 0), Vector3(0, 0, -100))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.is_empty(), "Directed fire skips a hostile outside its list")
	state.projectiles = [shot(5, 2, Vector3(0, 0, 0), Vector3(100, 0, 0))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == 0, "Directed fire hits its listed target")
	state.projectiles = [shot(6, 2, Vector3(0, 0, 0), Vector3(0, 100, 0))]
	hits = Combat.advance(state, 1.0, [player, boxed, sphere, neutral], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == 2, "Directed fire still meets scenery")

	# A target swept across the bolt's path between frames still registers.
	var crossing := {
		"id": 0,
		"team": "enemy",
		"previous": [0.0, -40.0, -50.0],
		"position": [0.0, 40.0, -50.0],
		"radius": 4.0
	}
	state.projectiles = [shot(7, 1, Vector3(0, 0, 0), Vector3(0, 0, -100))]
	hits = Combat.advance(state, 1.0, [crossing], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == 0, "A crossing target is swept, not missed")

	# The nearest impact along the path wins, whichever order targets arrive in.
	var near := {"id": 0, "team": "enemy", "position": [0.0, 0.0, -20.0], "radius": 4.0}
	var far := {"id": 1, "team": "enemy", "position": [0.0, 0.0, -60.0], "extent": [4.0, 4.0, 4.0]}
	state.projectiles = [shot(8, 1, Vector3(0, 0, 0), Vector3(0, 0, -100))]
	hits = Combat.advance(state, 1.0, [far, near], lib, guns)
	check(hits.size() == 1 and int(hits[0].target) == 0, "The nearest impact wins over a later one")

	state.projectiles = [shot(9, 1, Vector3(0, 0, 0), Vector3(0, 0, -100))]
	hits = Combat.advance(state, 1.0, [], lib, guns)
	check(
		hits.is_empty() and state.projectiles.size() == 1,
		"An empty target list leaves the bolt travelling"
	)
