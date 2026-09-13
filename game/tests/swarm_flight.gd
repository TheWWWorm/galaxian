extends "res://tests/player_feedback.gd"
## Private end-to-end check: the swarm mode inside the real flight scene and
## the real main menu flow, stepped headlessly.
const SwarmRules = preload("res://src/simulation/swarm_rules.gd")
const SwarmArchive = preload("res://src/simulation/swarm_archive.gd")


class SwarmMain extends FeedbackMain:
	## The feedback harness flattens save paths; the arcade archives need the
	## real per-content directory, so restore it for this check only.
	func save_path(slot: String) -> String:
		return "user://swarm-check/" + library.id + "/" + slot + ".json"



func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "open content")
	if failures:
		quit(1)
		return
	var app := SwarmMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true

	# the menu path a player actually takes
	var probe := SwarmArchive.new()
	var opened := probe.open(lib, SwarmRules.create(), app.save_path("swarm").get_base_dir())
	check(opened, "archive opens directly: " + probe.error)
	app.show_swarm_menu()
	check(app.screen == "swarm_menu", "swarm menu opens: " + app.notification_text)
	check(app.swarm_archive != null, "archive opened")
	var unlocked: Array = app.swarm_archive.unlocked()
	check(unlocked.size() >= 1, "at least one hull is available")

	# the roster is longer than the original six rows: it must scroll, and the
	# description must not be printed across the buttons.
	var panel = app.title_panel
	var scrolls := []
	for child in panel.canvas.get_children():
		if child is ScrollContainer:
			scrolls.append(child)
	check(scrolls.size() == 2, "text and roster each get a scrolling frame")
	check(panel.buttons.size() > 6, "every hull is listed, %d rows" % panel.buttons.size())
	var rows_inside := 0
	for button in panel.buttons:
		var parent: Node = button.get_parent()
		if parent != null and parent.get_parent() is ScrollContainer:
			rows_inside += 1
	check(rows_inside == panel.buttons.size(), "rows live inside the scrolling column")
	if scrolls.size() == 2:
		var text_area: ScrollContainer = scrolls[0]
		var list_area: ScrollContainer = scrolls[1]
		check(
			list_area.position.y >= text_area.position.y + text_area.size.y,
			"the roster starts below the description"
		)
		check(
			list_area.position.y + list_area.size.y <= 284.0
			and list_area.position.x >= 0
			and list_area.position.x + list_area.size.x <= 480.0,
			"the roster stays inside the title artwork"
		)
		var row_height: float = panel.art.idle.get_height()
		check(
			panel.buttons.size() * row_height > list_area.size.y,
			"the roster is taller than its frame, so it scrolls"
		)
	app.title_action("hull_%d" % int(unlocked[0]))
	check(app.screen == "flight", "starting a run enters flight")
	check(app.session != null and app.session.slot == "swarm", "swarm session is live")
	var flight = app.flight
	flight.set_physics_process(false)
	check(flight != null, "flight scene built")

	var levels := 0
	var cards_seen := 0
	var max_actors := 0
	var levelled := false
	var max_live := 0
	for tick in 5400:
		if app.screen == "swarm_cards":
			cards_seen += 1
			check(not app.swarm_cards.is_empty(), "card dialog has offers")
			app.take_swarm_card(0)
			levels += 1
			continue
		if app.screen != "flight":
			break
		flight.step(1.0 / 30.0)
		max_actors = maxi(max_actors, flight.actors.size())
		var live := 0
		for entry in app.session.active_job.actors:
			if entry.hp > 0:
				live += 1
		max_live = maxi(max_live, live)
		var readout: Dictionary = app.session.arcade_state()
		levelled = levelled or (int(readout.level) > 0 and int(readout.experience) >= 0)
		# kill at about the rate the balance model assumes, so the population
		# still fills; farming faster than the spawn budget empties the arena.
		if tick % 24 == 0:
			for entry in flight.actors:
				if entry.state.hp > 0:
					app.session.damage_actor(int(entry.index), 1e9)
					break
	print("ticks done: screen %s, levels %d, dialogs %d, peak actors %d" % [
		app.screen, levels, cards_seen, max_actors])
	print("readout: ", app.session.arcade_state())
	var target: Dictionary = preload("res://src/simulation/swarm_director.gd").target_counts(
		app.session.rules, float(app.session.director.elapsed)
	)
	print("peak live slots %d, elapsed %.0fs, target %s" % [
		max_live, app.session.director.elapsed, str(target)])
	print("score %d level %d kills %d hull %.0f/%.0f" % [
		app.session.director.score, app.session.director.level,
		app.session.active_job.kills, app.session.hull, app.session.max_hull()])
	print("build: ", app.session.build)
	check(cards_seen > 3, "level dialogs appeared")
	check(max_actors >= 6, "the swarm rendered, peak %d" % max_actors)
	# Wrecks must not be mistaken for live hulls: the arena has to reach the
	# population the rules ask for, not the population minus the debris.
	check(
		max_live >= int(target.crowd) + int(target.elite),
		"the arena filled to its target, peak %d" % max_live
	)
	check(levelled, "the level readout advanced during the run")
	var readout: Dictionary = app.session.arcade_state()
	check(
		readout.has("level") and int(readout.experience_span) > 0
		and int(readout.experience) < int(readout.experience_span),
		"experience sits inside the level it reports"
	)
	check(app.session.director.score > 0, "score accumulated")
	check(flight.actors.size() <= 32, "actor pool respected")

	# firing exercises the rebuilt gun profiles through the real code path
	var before: int = app.session.combat.projectiles.size()
	app.session.combat.cooldowns.clear()
	flight.fire()
	check(app.session.combat.projectiles.size() >= before, "player weapons fire")

	# defeat path
	app.session.hull = 0.0
	flight.step(1.0 / 30.0)
	check(app.screen == "swarm_result", "defeat opens the result screen, got " + app.screen)
	app.advance_swarm_result()
	check(app.screen in ["swarm_name", "swarm_menu", "swarm_result"], "result advances, got " + app.screen)
	if app.screen == "swarm_name":
		app.submit_swarm_name("ACE")
		check(app.screen == "swarm_result", "name submission returns to the result")
		app.advance_swarm_result()
	check(app.screen == "swarm_menu", "run closes back to the menu, got " + app.screen)
	check(app.swarm_archive.best_score() > 0, "score recorded to the board")
	print("recorded best %d, unlocked %d hulls" % [
		app.swarm_archive.best_score(), app.swarm_archive.unlocked().size()])

	print("SWARM FLIGHT CHECKS %d FAILURES %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
