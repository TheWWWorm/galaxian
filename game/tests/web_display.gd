extends SceneTree
## Focused checks for display settings, briefing metrics and runtime audio routing.
const Library = preload("res://src/content/library.gd")
const Display = preload("res://src/presentation/display_settings.gd")
const Audio = preload("res://src/presentation/audio_settings.gd")
const Briefing = preload("res://src/presentation/briefing.gd")
var failures := 0
var checks := 0

class TestMain extends "res://src/main.gd":
	func _ready(): pass
	func _process(_delta): pass
	func settings_path(): return "user://web-display-test-settings.cfg"

func _initialize(): call_deferred("run")

func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func run():
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass an existing imported content directory after --")
		quit(2); return
	var lib := Library.new()
	check(lib.open(args[0], args[0].get_file()), "Open existing content without reimport")
	if failures: quit(1); return
	var app := TestMain.new()
	root.add_child(app)
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true
	app.show_options(); app.options_panel.show_section("display")
	var options = app.options_panel
	check(options.entries.map(func(e): return e.action) == ["fullscreen", "aspect_ratio", "targeting_reticle", "touch"], "Display exposes window mode and aspect ratios")
	for ratio in ["4:3", "16:9", "16:10", "21:9", "auto"]:
		options.handle_action("aspect_ratio")
		check(app.settings.aspect_ratio == ratio, "Ratio selection reaches " + ratio)
		check(root.content_scale_size == Display.RATIOS[ratio], "Picture proportions follow selection " + ratio)
		check(root.content_scale_aspect == (Window.CONTENT_SCALE_ASPECT_EXPAND if ratio == "auto" else Window.CONTENT_SCALE_ASPECT_KEEP), "Auto fills window; fixed ratio preserves picture")
	app.settings.aspect_ratio = "4:3"; app.save_settings()
	app.settings.aspect_ratio = "auto"; app.load_settings()
	check(app.settings.aspect_ratio == "4:3", "Aspect preference persists")
	Display.apply_aspect(root, "invalid")
	check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Unknown aspect safely uses automatic sizing")
	Display.set_fullscreen(root, true)
	await create_timer(.2).timeout
	check(Display.fullscreen(root), "Enter fullscreen")
	Display.set_fullscreen(root, false)
	await create_timer(.2).timeout
	check(root.mode == Window.MODE_WINDOWED, "Return to a resizable window")
	Display.apply_aspect(root, "auto")
	for viewport in [Vector2i(1280, 960), Vector2i(1600, 900), Vector2i(1440, 900), Vector2i(2100, 900)]:
		root.size = viewport
		await process_frame
		options.layout_canvas()
		var visible_frame := Rect2(options.origin, options.canvas.size * options.factor)
		check(Rect2(Vector2.ZERO, options.size).encloses(visible_frame), "Options fit viewport " + str(viewport))
		for button in options.buttons:
			check(button.get_rect().end.y < options.footer.position.y, "Display rows clear footer")
	var fx := Audio.effect_player(); var music := Audio.music_player()
	var expected_effect := AudioServer.PLAYBACK_TYPE_SAMPLE if OS.has_feature("web") else AudioServer.PLAYBACK_TYPE_STREAM
	check(fx.playback_type == expected_effect and music.playback_type == AudioServer.PLAYBACK_TYPE_STREAM, "Web effects use low-latency samples; native audio and music retain streams")
	check(fx.bus == Audio.EFFECTS and music.bus == Audio.MUSIC, "Independent imported audio volume buses retained")
	fx.free(); music.free()
	var flight := preload("res://src/presentation/flight.gd").new()
	root.add_child(flight)
	for child in [flight.ship, flight.camera, flight.audio, flight.ambience, flight.player_hit]:
		flight.add_child(child)
	flight.player_hit.add_child(flight.player_hit.audio)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(12, 0)
	flight.pause(true)
	flight._unhandled_input(motion)
	check(flight.ship.rotation.is_zero_approx(), "Paused flight ignores mouse steering")
	flight.pause(false)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Resume requests mouse capture")
	flight._unhandled_input(motion)
	check(not flight.ship.rotation.is_zero_approx(), "Resumed flight accepts mouse steering")
	flight.pause(true)
	flight.queue_free(); await process_frame
	app.queue_free(); await process_frame
	var brief := Briefing.new(); brief.library = lib
	root.add_child(brief); brief.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brief.present(0, 0)
	var metrics := brief.text_metrics()
	var height: int = lib.radio_glyphs().values()[0].size.y
	check(is_equal_approx(metrics.x, ThemeDB.fallback_font.get_height(height)), "Briefing line advance uses actual desktop font height")
	check(is_equal_approx(metrics.y + height, ThemeDB.fallback_font.get_ascent(height)), "Briefing baseline uses actual desktop ascent")
	root.size = Vector2i(1600, 1000)
	await process_frame
	if DisplayServer.get_name() != "headless" and args.size() > 1:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(args[1])
	brief.queue_free(); await process_frame
	DirAccess.remove_absolute("user://web-display-test-settings.cfg")
	print("WEB/DISPLAY ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
