extends SceneTree
## Browser lock-loss and canvas-steering regressions; no content import required.
## A display server is required for the additional native-capture check.
var failures := 0
var checks := 0
var pauses := 0

class TestFlight extends "res://src/presentation/flight.gd":
	var browser_locked := false
	func mouse_is_captured() -> bool: return browser_locked

func _initialize(): call_deferred("run")

func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func motion(flight):
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(12, 0)
	flight._unhandled_input(event)

func tab(flight):
	var event := InputEventKey.new()
	event.physical_keycode = KEY_TAB
	event.pressed = true
	flight._unhandled_input(event)

func run():
	var flight := TestFlight.new()
	root.add_child(flight)
	flight.set_physics_process(false)
	for child in [flight.ship, flight.camera, flight.audio, flight.ambience, flight.player_hit]:
		flight.add_child(child)
	flight.player_hit.add_child(flight.player_hit.audio)
	flight.web_mouse_input = true
	flight.pause_requested.connect(func(): pauses += 1)
	flight.pause(false)
	flight.watch_browser_capture()
	check(not flight.paused and pauses == 0, "Rejected initial capture does not spuriously pause")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	motion(flight)
	check(not flight.ship.rotation.is_zero_approx(), "Canvas motion steers when browser rejects capture")
	flight.browser_locked = true
	flight.watch_browser_capture()
	flight.browser_locked = false
	flight.watch_browser_capture()
	check(flight.paused and pauses == 1, "Browser Escape unlock pauses without a key event")
	flight.watch_browser_capture()
	check(pauses == 1, "Unlocked browser does not repeatedly request the menu")
	var rotation := flight.ship.rotation
	motion(flight)
	check(flight.ship.rotation == rotation, "Menu motion cannot steer the ship")
	flight.pause(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	motion(flight)
	check(flight.ship.rotation != rotation, "Resume restores steering without another click")
	tab(flight)
	rotation = flight.ship.rotation
	motion(flight)
	flight.watch_browser_capture()
	check(flight.ship.rotation == rotation and pauses == 1, "Tab releases fallback steering without opening pause")
	tab(flight)
	motion(flight)
	check(flight.ship.rotation != rotation, "Tab restores fallback steering")
	flight.browser_locked = true
	flight.watch_browser_capture()
	tab(flight)
	flight.browser_locked = false
	flight.watch_browser_capture()
	check(not flight.paused and pauses == 1, "Deliberate release of an actual lock does not pause")
	flight.pause(false)
	flight.browser_locked = true
	flight.watch_browser_capture()
	flight.pause(true)
	flight.browser_locked = false
	flight.watch_browser_capture()
	check(pauses == 1, "Opening a menu deliberately releases lock without a duplicate pause")
	flight.settings.touch = true
	flight.pause(false)
	rotation = flight.ship.rotation
	motion(flight)
	check(flight.ship.rotation == rotation and not flight.mouse_flight_enabled, "Touch mode does not enable mouse fallback")
	flight.settings.touch = false
	flight.web_mouse_input = false
	flight.pause(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	motion(flight)
	check(flight.ship.rotation == rotation, "Native uncaptured mouse does not steer")
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		motion(flight)
		check(flight.ship.rotation != rotation, "Native captured steering is preserved")
	flight.pause(true)
	flight.queue_free()
	await process_frame
	print("WEB MOUSE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
