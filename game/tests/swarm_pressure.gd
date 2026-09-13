extends "res://tests/player_feedback.gd"
## Private check: how hard the swarm hits a player who does nothing about it.
## The ship flies its default course and never fires, so the arena fills to its
## target and stays there. That is the floor the opening minutes must clear: if
## a passive pilot cannot last several minutes, an engaged one cannot either.
const SwarmRules = preload("res://src/simulation/swarm_rules.gd")
const SwarmArchive = preload("res://src/simulation/swarm_archive.gd")
const MINUTES := 6


class PressureMain extends FeedbackMain:
	func save_path(slot: String) -> String:
		return "user://swarm-pressure/" + library.id + "/" + slot + ".json"


func run():
	var args := OS.get_cmdline_user_args()
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "open content")
	if failures:
		quit(1)
		return
	var app := PressureMain.new()
	root.add_child(app)
	app.setup_world()
	app.setup_ui()
	app.add_child(app.music)
	app.library = lib
	app.ready_content = true
	app.show_swarm_menu()
	check(app.screen == "swarm_menu", "swarm menu opens: " + app.notification_text)
	var unlocked: Array = app.swarm_archive.unlocked()
	app.title_action("hull_%d" % int(unlocked[0]))
	check(app.screen == "flight", "run started")
	var flight = app.flight
	flight.set_physics_process(false)
	var session = app.session
	var ceiling: float = session.max_hull()
	print("hull %.0f, shield %.0f, standing repair %.2f hull/s" % [
		ceiling, session.max_shield(), session.standing_repair()])
	var previous: float = session.hull
	var survived := 0
	for minute in MINUTES:
		for tick in 1800:
			if app.screen == "swarm_cards":
				# Never spend a level on repair: measure the raw pressure.
				app.take_swarm_card(app.swarm_cards.size())
				continue
			if app.screen != "flight" or session.hull <= 0:
				break
			flight.step(1.0 / 30.0)
		var alive := 0
		for actor in session.active_job.actors:
			if actor.hp > 0:
				alive += 1
		print("  minute %d: hull %6.0f  (%.2f hull/s lost)  enemies %d  level %d" % [
			minute + 1, session.hull, (previous - session.hull) / 60.0, alive,
			int(session.director.level)])
		previous = session.hull
		if session.hull > 0:
			survived = minute + 1
		else:
			break
	print("passive survival: %d of %d minutes, %.0f%% hull left" % [
		survived, MINUTES, 100.0 * maxf(0.0, session.hull) / ceiling])
	check(survived >= 4, "a passive pilot lasts at least four minutes, lasted %d" % survived)
	check(session.hull <= 0 or session.hull < ceiling, "the swarm is a real threat")
	print("SWARM PRESSURE CHECKS %d FAILURES %d" % [checks, failures])
	quit(1 if failures > 0 else 0)
