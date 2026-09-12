extends "res://tests/integration.gd"
## Player feedback batch 14: sustained fire must not scale the flight threat test
## with the number of live projectiles. Uses existing imported content only.


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
