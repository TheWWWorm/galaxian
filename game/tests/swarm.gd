extends SceneTree
## Private check for the swarm mode simulation core. Not part of the shipped
## suite entry points; run headlessly against imported test content.
const Library = preload("res://src/content/library.gd")
const Rules = preload("res://src/simulation/swarm_rules.gd")
const Build = preload("res://src/simulation/swarm_build.gd")
const Director = preload("res://src/simulation/swarm_director.gd")
const Session = preload("res://src/simulation/swarm_session.gd")
const Archive = preload("res://src/simulation/swarm_archive.gd")
const Cards = preload("res://src/presentation/swarm_cards.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)


func run() -> void:
	var args := OS.get_cmdline_user_args()
	var root: String = args[0] if args.size() > 0 else ""
	var lib := Library.new()
	if not lib.open(root, root.get_file()):
		printerr("library: " + lib.error)
		quit(2)
		return
	var rules := Rules.create()
	check(Rules.valid(rules), "authored rules validate")
	check(not Rules.valid({}), "empty rules rejected")
	var broken := rules.duplicate(true)
	broken.crowd.start = 99.0
	check(not Rules.valid(broken), "crowd start above cap rejected")
	check(not Rules.surging(rules, 0.0), "no surge on the opening frame")
	var green := Rules.veterancy(rules, 0.0)
	var seasoned := Rules.veterancy(rules, float(rules.arc_seconds))
	print("veterancy: opening ", green, " closing ", seasoned)
	check(
		float(green.damage) < 1.0 and float(seasoned.damage) > 1.0,
		"enemies open below their imported damage and end above it"
	)
	check(float(green.hull) <= float(seasoned.hull), "enemy hull only grows")
	check(Rules.surging(rules, float(rules.surge.first) + 1.0), "surges begin after the delay")
	var opening := Director.target_counts(rules, 0.0)
	print("opening population: ", opening)
	check(int(opening.crowd) <= 6 and int(opening.elite) == 0, "the arena opens on a handful")
	check(
		Director.target_counts(rules, 600.0).crowd > int(opening.crowd),
		"population grows with the run"
	)

	var ladders := Build.ladders(lib)
	print("ladders: ", ladders)
	check(ladders.size() >= 2, "catalogue yields weapon ladders")
	for category in ladders:
		var previous := -1
		for id in ladders[category]:
			check(int(lib.items[id][6]) >= previous, "ladder %d ordered by price" % category)
			previous = int(lib.items[id][6])

	check(Session.valid_declarations(lib, rules), "declarations accepted")
	var sizes := Director.pool_sizes(rules)
	print("pool: ", sizes)

	var session = Session.new()
	var hulls := range(lib.ships.size())
	check(session.configure_swarm(lib, rules, 0, 6, hulls, 12345), "configure: " + session.error)
	check(session.active_job.actors.size() == int(sizes.total), "pool populated")
	check(session.max_hull() > 0, "arena hull positive")
	check(int(session.build.shield) > 0, "a run opens with a shield fitted")
	check(session.max_shield() > 0, "the fitted shield has capacity")
	check(session.standing_repair() > 0, "hull repairs on its own")
	var motion: Dictionary = session.motion_parameters()
	check(
		float(motion.contact.damage) < float(lib.content.player_motion.contact.damage)
		and float(motion.recharge_seconds) < float(lib.content.player_motion.recharge_seconds),
		"contact damage and boost recharge are eased for the arcade"
	)
	var wounded = Session.new()
	wounded.configure_swarm(lib, rules, 0, 6, hulls, 5150)
	wounded.hull = 10.0
	wounded.advance_mission(4.0)
	check(
		wounded.hull > 10.0 and wounded.hull <= 10.0 + wounded.standing_repair() * 4.0 + .001,
		"the standing repair ran and did not overshoot"
	)
	print("hull %.0f  weapon %d  guns %d" % [session.max_hull(), session.weapon_id, session.player_guns.size()])

	# a run: advance in fixed steps, take every level-up, kill what spawns
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var levels := 0
	var kills := 0
	var alive_peak := 0
	for step in 2400:
		session.advance_mission(.5)
		session.elapsed += .5
		var alive := 0
		for actor in session.active_job.actors:
			if actor.hp > 0:
				alive += 1
		alive_peak = maxi(alive_peak, alive)
		# One kill a second: below the refill budget, so the arena fills as the
		# rules intend instead of being emptied by the test itself.
		if step % 2 == 0:
			var index := rng.randi_range(0, session.active_job.actors.size() - 1)
			if session.active_job.actors[index].hp > 0:
				session.damage_actor(index, 1e9)
				kills += 1
		while session.level_pending():
			var offers := session.card_offers()
			check(not offers.is_empty(), "level %d offers cards" % session.director.level)
			if offers.is_empty():
				session.choose_card(null)
				break
			check(session.choose_card(offers[rng.randi_range(0, offers.size() - 1)]), "card applied")
			levels += 1
	print("after %.0fs: level %d, kills %d, score %d, xp %d, peak alive %d" % [
		session.director.elapsed, session.director.level, kills,
		session.director.score, session.director.xp, alive_peak])
	print("build: ", session.build)
	print("player dps profiles: %d, hull %.0f, shield %.0f" % [
		session.player_guns.size(), session.max_hull(), session.max_shield()])
	check(levels > 10, "run produced levels")
	check(alive_peak >= 12, "population reached the arena floor")
	check(session.director.score > 0, "score accumulated")

	# save round trip
	var snapshot: Dictionary = session.capture()
	check(not snapshot.is_empty(), "capture produced a snapshot")
	var restored = Session.new()
	restored.library = lib
	restored.rules = rules
	restored.content_id = session.content_id
	check(restored.restore(snapshot), "restore: " + restored.error)
	if restored.error.is_empty():
		check(int(restored.director.level) == int(session.director.level), "restored level")
		check(is_equal_approx(restored.hull, session.hull), "restored hull")
		check(restored.build.ship == session.build.ship, "restored hull choice")
	var tampered: Dictionary = snapshot.duplicate(true)
	tampered.hull = 1e9
	var reject = Session.new()
	reject.library = lib
	reject.rules = rules
	reject.content_id = session.content_id
	check(not reject.restore(tampered), "impossible hull rejected")

	# card wording
	var sample := Build.draw(session.build, rules, lib, rng, hulls)
	for card in sample:
		var text := Cards.label(card, rules, lib, session.build, session.repair_amounts())
		check(not text.is_empty() and not text.contains("%s") and not text.contains("%d"), "card label: " + text)
		print("  card: %-34s %s" % [text, Cards.detail(card, rules, lib, session.build)])
	var wording := Cards.captions(sample, rules, lib, session.build, session.repair_amounts())
	check(wording.size() == sample.size() + 1, "decline option appended")

	# the cards that replaced salvage pickups
	var fresh = Session.new()
	check(fresh.configure_swarm(lib, rules, 0, 0, hulls, 4242), "recovery session: " + fresh.error)
	var amounts: Array = fresh.repair_amounts()
	check(Build.recovery_hull(fresh.build, rules, amounts) == 0.0, "no repair without the card")
	check(
		Build.apply(fresh.build, rules, lib, {"kind": "modifier", "modifier": "recovery", "category": -1}),
		"recovery card applies"
	)
	var banked := Build.recovery_hull(fresh.build, rules, amounts)
	print("recovery per kill: %.1f of %.0f hull" % [banked, fresh.max_hull()])
	check(banked > 0 and banked < fresh.max_hull() * .05, "one kill repairs a little, not a lot")
	fresh.advance_mission(2.0)
	fresh.hull = 1.0
	var before: float = fresh.hull
	var victim := -1
	for index in fresh.active_job.actors.size():
		if fresh.active_job.actors[index].hp > 0:
			victim = index
			break
	check(victim >= 0, "a target spawned to kill")
	if victim >= 0:
		fresh.damage_actor(victim, 1e9)
		check(is_equal_approx(fresh.hull, before + banked), "the kill banked its repair")
	check(
		Build.experience_scale(fresh.build, rules) == 1.0
		and Build.apply(fresh.build, rules, lib, {"kind": "modifier", "modifier": "insight", "category": -1})
		and Build.experience_scale(fresh.build, rules) > 1.0,
		"insight raises experience"
	)
	var straight = Session.new()
	straight.configure_swarm(lib, rules, 0, 0, hulls, 4242)
	var plain := Director.award(straight.director, rules, 100, 1.0)
	var keen := Director.award(straight.director, rules, 100, 1.5)
	check(int(plain.xp) == 100 and int(keen.xp) == 150, "experience follows the kill alone")

	# archive: unlocks, run lifecycle, checkpoint round trip
	var records_root: String = args[1] if args.size() > 1 else ""
	if not records_root.is_empty():
		var directory := records_root.path_join(lib.id)
		var archive := Archive.new()
		check(archive.open(lib, rules, directory), "archive open: " + archive.error)
		var order := Archive.hull_order(lib)
		print("hull order: ", order.map(func(i): return lib.ship_name(i)))
		check(order.size() == lib.ships.size(), "hull order covers the roster")
		var starting := archive.unlocked()
		print("unlocked at zero score: ", starting.map(func(i): return lib.ship_name(i)))
		check(starting.size() == 1, "only the first hull is unlocked initially")
		check(not archive.start(0, order[order.size() - 1], 7), "locked hull refused")
		check(archive.start(0, int(starting[0]), 7), "run started: " + archive.error)
		check(archive.session != null, "archive holds the run")
		archive.session.hull = 0.0

		check(archive.finish("ACE"), "run recorded: " + archive.error)
		check(not archive.result_summary().is_empty(), "result available")
		check(archive.acknowledge_result(), "result acknowledged: " + archive.error)
		var reopened := Archive.new()
		check(reopened.open(lib, rules, directory), "archive reopen: " + reopened.error)
		check(reopened.best_score() == archive.best_score(), "board survives a reopen")
		print("best score %d, unlocked now %d hulls" % [reopened.best_score(), reopened.unlocked().size()])

		# A rule block that moved on under a saved run must cost the run, never
		# the board: the alternative is a player locked out of the mode entirely.
		check(reopened.session == null, "no run is in progress after a result")
		check(reopened.start(0, int(starting[0]), 11), "second run started: " + reopened.error)
		# Without the backup there is nothing older to fall back to, so this
		# exercises the recovery path rather than the previous checkpoint.
		DirAccess.remove_absolute(reopened.path + ".bak")
		var moved := rules.duplicate(true)
		moved.crowd.cap = 20.0
		var after := Archive.new()
		check(after.open(lib, moved, directory), "archive opens under new rules: " + after.error)
		check(after.session == null, "the stale run was dropped")
		check(not after.recovered.is_empty(), "the dropped run is reported")
		check(after.best_score() == reopened.best_score(), "the board survived the rule change")
		check(
			after.start(0, int(after.unlocked()[0]), 13),
			"a fresh run starts after recovery: " + after.error
		)

	print("SWARM CHECKS %d FAILURES %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
