extends SceneTree
## Focused checks for the mobile text font: automatic scalable text for
## languages the imported glyph atlas cannot write, and matching layout metrics.
const Importer = preload("res://src/content/ipa_import.gd")
const Library = preload("res://src/content/library.gd")
const BitmapFont = preload("res://src/presentation/bitmap_font.gd")
var failures := 0
var checks := 0

class TestMain extends "res://src/main.gd":
	func _ready(): pass
	func _process(_delta): pass
	func settings_path(): return "user://text-font-test-settings.cfg"

func _initialize(): call_deferred("run")

func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func run():
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Pass an IPA that includes ru.lang after --")
		quit(2); return
	var importer := Importer.new()
	importer.cache_base = "user://test-content"
	check(await importer.install(args[0], self), "IPA import: " + importer.error)
	var lib := Library.new()
	check(lib.open(importer.root, importer.content_id), "Open imported content")
	if failures: quit(1); return
	check(lib.available_languages().has("ru"), "Supplied Russian language is offered")
	check(Library.language_name("ru") == "Русский", "Russian language is named natively")
	for code in lib.available_languages():
		check(lib.set_language(code), "Select language " + code)
		check(lib.needs_scalable_text() == (code == "ru"), "Only Russian needs letters missing from the atlas: " + code)

	BitmapFont.mobile_cache = 1
	lib.set_language("gb")
	BitmapFont.text_font = "auto"
	check(not BitmapFont.scalable_text(lib), "Mobile English keeps the imported glyphs")
	check(BitmapFont.create(lib) == lib.bitmap_fonts.values()[0], "Mobile English builds the bitmap font")
	lib.set_language("ru")
	check(BitmapFont.scalable_text(lib), "Mobile Russian switches to scalable text automatically")
	var vector_font := BitmapFont.create(lib)
	check(not lib.bitmap_fonts.values().has(vector_font), "Mobile Russian menus use the scalable font")
	# Wrapping and measurement must use the same font that draws the text.
	var width := float(lib.content.radio_ui.text_width) - 60.0
	var longest := ""
	for value in lib.strings:
		if value.length() > longest.length(): longest = value
	var lines := BitmapFont.wrap_lines(lib, longest, width)
	check(lines.size() > 1, "Long Russian text wraps")
	var fits := true
	for line in lines:
		fits = fits and BitmapFont.text_width(lib, line) <= width + .5
	check(fits, "Every wrapped Russian line fits its measured width")
	check(
		is_equal_approx(BitmapFont.text_width(lib, "Меркурий"), ThemeDB.fallback_font.get_string_size(
			"Меркурий", HORIZONTAL_ALIGNMENT_LEFT, -1, lib.radio_glyphs().values()[0].size.y).x),
		"Russian widths come from the scalable font"
	)
	BitmapFont.text_font = "original"
	check(not BitmapFont.scalable_text(lib), "Original keeps the imported glyphs for any language")
	BitmapFont.text_font = "scalable"
	lib.set_language("gb")
	check(BitmapFont.scalable_text(lib), "Scalable applies to English on request")
	BitmapFont.text_font = "auto"

	var app := TestMain.new()
	root.add_child(app)
	app.setup_world(); app.setup_ui(); app.add_child(app.music)
	app.library = lib; app.ready_content = true
	app.show_options(); app.options_panel.show_section("display")
	var actions: Array = app.options_panel.entries.map(func(e): return e.action)
	check(actions == ["aspect_ratio", "frame_rate", "text_font", "flight_hud"], "Mobile display lists the text font")
	check(app.options_panel.entries[2].text == "Text font: Auto", "Text font starts on Auto")
	var bitmap_font = app.options_panel.font
	app.options_panel.handle_action("text_font")
	check(app.settings.text_font == "original", "Auto cycles to Original")
	check(app.options_panel.font == bitmap_font, "Original keeps the English menu font")
	app.options_panel.handle_action("text_font")
	await process_frame
	check(app.settings.text_font == "scalable" and BitmapFont.text_font == "scalable", "Original cycles to Scalable")
	check(app.options_panel.font != bitmap_font, "The open menu is rebuilt with the scalable font")
	check(app.options_panel.section == "display", "The rebuilt menu stays on the display page")
	check(app.options_panel.entries[2].text == "Text font: Scalable", "The rebuilt menu shows the new choice")
	app.options_panel.handle_action("text_font")
	await process_frame
	check(app.settings.text_font == "auto" and app.options_panel.font == bitmap_font, "Scalable cycles back to Auto")
	app.change_option("language", "ru")
	await process_frame
	check(app.options_panel.font != bitmap_font, "Choosing Russian rebuilds the menu with scalable text")
	app.change_option("language", "gb")
	await process_frame
	check(app.options_panel.font == bitmap_font, "Choosing English restores the imported glyphs")
	app.save_settings()
	app.settings.text_font = "invalid"
	app.load_settings()
	check(app.settings.text_font == "auto", "Saved text font reloads")

	BitmapFont.mobile_cache = 0
	app.options_panel.show_section("display")
	check(not app.options_panel.entries.map(func(e): return e.action).has("text_font"), "Desktop always uses scalable text and hides the choice")
	check(BitmapFont.scalable_text(lib), "Desktop text is scalable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://text-font-test-settings.cfg"))
	print("text_font %d/%d" % [checks, failures])
	quit(1 if failures else 0)
