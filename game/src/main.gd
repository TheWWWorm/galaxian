extends Node3D
const Importer = preload("res://src/content/ipa_import.gd")
const Library = preload("res://src/content/library.gd")
const Session = preload("res://src/simulation/session.gd")
const Flight = preload("res://src/presentation/flight.gd")
const Briefing = preload("res://src/presentation/briefing.gd")
const BriefingScene = preload("res://src/presentation/briefing_scene.gd")
const RecoveryPanel = preload("res://src/presentation/recovery.gd")
const Dialogue = preload("res://src/presentation/dialogue.gd")
const HUD = preload("res://src/presentation/hud.gd")
const DisplaySettings = preload("res://src/presentation/display_settings.gd")
const GalaxyMap = preload("res://src/presentation/galaxy_map.gd")
const SurvivalArchive = preload("res://src/simulation/survival_archive.gd")
const SurvivalMenu = preload("res://src/presentation/survival_menu.gd")
const SurvivalName = preload("res://src/presentation/survival_name.gd")
const SurvivalResult = preload("res://src/presentation/survival_result.gd")
const TouchScroll = preload("res://src/input/touch_scroll.gd")
var importer := Importer.new()
var library := Library.new()
var session
var flight
var world := Node3D.new()
var showcase := Node3D.new()
var menu_camera := Camera3D.new()
var sky_material := ShaderMaterial.new()
var canvas := CanvasLayer.new()
var ui := Control.new()
var page := MarginContainer.new()
var top := HBoxContainer.new()
var status := Label.new()
var hud
var flight_stats: Label
var flight_objective: Label
var radio: Label
var dialogue_panel
var briefing_panel
var recovery_panel
var briefing_scene
var menu_scene
var title_panel
var station_panel
var board_panel
var destination_panel
var travel_transition
var hangar_panel
var options_panel
var pause_panel
var defeat_panel
var defeat_notice := false
var defeated_session
var survival_archive
var survival_panel
var survival_name_draft := ""
var flight_buttons := {}
var dialog := FileDialog.new()
var confirmation := ConfirmationDialog.new()
var confirm_action: Callable
var music := preload("res://src/presentation/audio_settings.gd").music_player()
var briefing_audio := preload("res://src/presentation/briefing_audio.gd").new()
var screen := "title"
var options_return_screen := "title"
var ready_content := false
var busy := false
var paused := false
var settings := {
	"sensitivity": .0025,
	"invert": false,
	"aim_assist": true,
	"targeting_reticle": null,
	"music": true,
	"music_volume": 1.0,
	"effects_volume": 1.0,
	"touch": false,
	"linked_fire": false,
	"fullscreen": false,
	"aspect_ratio": "auto"
}
var notification_text := ""
var notification_time := 0.0
var save_timer := 0.0
var star_map_selection := 0
var map_panel
var galaxy_map
var pending_capture := ""
var capture_delay := 0.0
var auto_exit := false
var exiting := false
var transient_preview := false
var web_picker
var touch_finger := -1
var touch_origin := Vector2.ZERO


func _init() -> void:
	add_child(briefing_audio)


func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	settings.touch = preload("res://src/presentation/bitmap_font.gd").is_mobile()
	setup_world()
	setup_ui()
	load_settings()
	DisplaySettings.apply_aspect(get_window(), str(settings.aspect_ratio))
	# Browsers require a fresh gesture to enter fullscreen; restore only native windows.
	if not OS.has_feature("web") and not preload("res://src/presentation/bitmap_font.gd").is_mobile():
		DisplaySettings.set_fullscreen(get_window(), bool(settings.fullscreen))
	settings.fullscreen = DisplaySettings.fullscreen(get_window())
	apply_audio_settings()
	importer.progress.connect(import_progress)
	get_window().files_dropped.connect(files_dropped)
	get_window().focus_exited.connect(focus_lost)
	add_child(music)
	music.volume_db = -17
	var config := ConfigFile.new()
	if config.load("user://install.cfg") == OK:
		var installed := str(config.get_value("content", "directory", ""))
		if importer.open_cache(installed):
			activate_content()
	show_title()
	call_deferred("arguments")


func setup_world() -> void:
	add_child(world)
	world.add_child(showcase)
	world.add_child(menu_camera)
	menu_camera.position = Vector3(100, 45, 120)
	menu_camera.look_at_from_position(menu_camera.position, Vector3(10, 0, 0))
	menu_camera.current = true
	menu_camera.far = 45000
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("8baabe")
	env.ambient_light_energy = .6
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var sky := Sky.new()
	sky_material.shader = preload("res://src/presentation/space.gdshader")
	sky.sky_material = sky_material
	env.sky = sky
	environment.environment = env
	world.add_child(environment)


func setup_ui() -> void:
	setup_menu_input()
	add_child(canvas)
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = make_theme()
	ui.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 48)
	page.add_theme_constant_override("margin_right", 48)
	page.add_theme_constant_override("margin_top", 112)
	page.add_theme_constant_override("margin_bottom", 75)
	var header := MarginContainer.new()
	ui.add_child(header)
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 48
	header.offset_top = 28
	header.offset_right = -48
	header.add_child(top)
	var brand := label("GALAXY ON FIRE", 25, Color("e6edf2"))
	top.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.add_child(label("NATIVE REMAKE  /  1.0.1", 12, Color("91a7b8")))
	ui.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 48
	status.offset_right = -48
	status.offset_top = -44
	status.offset_bottom = -16
	status.add_theme_font_size_override("font_size", 14)
	status.modulate = Color("9daebe")
	ui.add_child(dialog)
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = OS.has_feature("android")
	dialog.filters = PackedStringArray(["*.ipa ; Galaxy on Fire 1 iPhone archive"])
	dialog.size = Vector2i(950, 650)
	dialog.title = "Choose your Galaxy on Fire 1 IPA"
	dialog.file_selected.connect(import_file)
	ui.add_child(confirmation)
	confirmation.canceled.connect(resume_briefing_input)
	confirmation.title = "Start a new pilot"
	confirmation.confirmed.connect(
		func():
			if confirm_action.is_valid():
				confirm_action.call()
	)


func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("10202f") if state in ["normal", "disabled"] else Color("1d3949")
		style.border_color = Color("375766") if state != "focus" else Color("ffca79")
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.content_margin_top = 13
		style.content_margin_bottom = 13
		theme.set_stylebox(state, "Button", style)
		theme.set_color("font_color", "Button", Color("dce9ed"))
		theme.set_color("font_disabled_color", "Button", Color("566a79"))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(.027, .058, .088, .94)
	panel.border_color = Color("29404e")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 25
	panel.content_margin_right = 25
	panel.content_margin_top = 23
	panel.content_margin_bottom = 23
	theme.set_stylebox("panel", "PanelContainer", panel)
	return theme


func label(text: String, size: int = 18, color: Color = Color("dce9ed")) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.modulate = color
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


func paragraph(text: String, parent: Node, color: Color = Color("a4bac8")) -> Label:
	var node := label(text, 17, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node


func button(text: String, callback: Callable, parent: Node, enabled: bool = true) -> Button:
	var node := Button.new()
	node.text = text
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.custom_minimum_size.y = 49
	node.disabled = not enabled
	node.pressed.connect(callback)
	parent.add_child(node)
	return node


func clear_page() -> void:
	if is_instance_valid(defeat_panel):
		defeat_panel.hide()
		defeat_panel.set_process_input(false)
		defeat_panel.queue_free()
	defeat_panel = null
	briefing_audio.stop_voice()
	if is_instance_valid(pause_panel):
		pause_panel.hide()
		pause_panel.set_process(false)
		pause_panel.queue_free()
	pause_panel = null
	if is_instance_valid(options_panel):
		options_panel.hide()
		options_panel.set_process(false)
		options_panel.queue_free()
	options_panel = null
	if is_instance_valid(map_panel):
		map_panel.hide()
		map_panel.queue_free()
	map_panel = null
	if is_instance_valid(destination_panel):
		destination_panel.hide()
		destination_panel.queue_free()
	destination_panel = null
	if is_instance_valid(board_panel):
		board_panel.hide()
		board_panel.queue_free()
	board_panel = null
	if is_instance_valid(hangar_panel):
		hangar_panel.hide()
		hangar_panel.queue_free()
	hangar_panel = null
	if is_instance_valid(station_panel):
		station_panel.hide()
		station_panel.queue_free()
	station_panel = null
	if is_instance_valid(title_panel):
		title_panel.hide()
		title_panel.set_process(false)
		title_panel.queue_free()
	title_panel = null
	if is_instance_valid(menu_scene):
		menu_scene.set_process(false)
		menu_scene.hide()
		menu_scene.queue_free()
		menu_camera.current = true
	menu_scene = null
	if is_instance_valid(survival_panel):
		survival_panel.set_process_input(false)
		survival_panel.hide()
		survival_panel.queue_free()
	survival_panel = null
	if is_instance_valid(recovery_panel):
		recovery_panel.set_process_input(false)
		recovery_panel.hide()
		recovery_panel.queue_free()
	recovery_panel = null
	flight_buttons.clear()
	if is_instance_valid(briefing_scene):
		briefing_scene.set_process(false)
		briefing_scene.hide()
		briefing_scene.queue_free()
	briefing_scene = null
	if briefing_panel != null and is_instance_valid(briefing_panel):
		briefing_panel.set_process_input(false)
		briefing_panel.queue_free()
	briefing_panel = null
	top.show()
	status.show()
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if hud != null and is_instance_valid(hud):
		hud.set_process_input(false)
		hud.hide()
		hud.queue_free()
		hud = null
	flight_stats = null
	flight_objective = null
	radio = null
	if dialogue_panel != null and is_instance_valid(dialogue_panel):
		dialogue_panel.set_process_input(false)
		dialogue_panel.hide()
		dialogue_panel.queue_free()
	dialogue_panel = null
	page.show()
	page.mouse_filter = Control.MOUSE_FILTER_STOP


func column(width: float = 480.0) -> VBoxContainer:
	var box := HBoxContainer.new()
	page.add_child(box)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width - 50, 0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var helper := TouchScroll.new()
	helper.scroll = scroll
	scroll.add_child(helper)
	return content


func caption(title: String, body: String, parent: Node) -> void:
	parent.add_child(label(title, 31, Color("f5d5a4")))
	paragraph(body, parent)


func show_title() -> void:
	if survival_active() and not save_game(false):
		if is_instance_valid(survival_panel) and survival_panel.has_method("retry_action"):
			survival_panel.retry_action()
		return
	screen = "title"
	paused = false
	stop_flight()
	clear_page()
	showcase.show()
	menu_camera.current = true
	if ready_content:
		show_menu_scene(true)
		top.hide()
		status.hide()
		page.hide()
		title_panel = preload("res://src/presentation/title_menu.gd").new()
		ui.add_child(title_panel)
		title_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title_panel.configure(library)
		title_panel.action_requested.connect(title_action)
		show_title_menu("main")
	else:
		var box := column(510)
		caption(
			"Galaxy on Fire", "The original iPhone adventure, running in a new native engine.", box
		)
		paragraph(
			"Choose your Galaxy on Fire 1 IPA. Ships, stations, textures, text and music are imported entirely on your device.",
			box
		)
		paragraph("No original game content is included with this engine.", box)
		button("Choose game IPA…", choose_file, box, not busy)
		button("Options & controls", show_options, box)
		if not OS.has_feature("web"):
			button("Exit", shutdown, box)
		status.text = "Choose an IPA, or drop it onto this window."
	play_menu_music(true)


func show_title_menu(section: String) -> void:
	var entries: Array = []
	var body := ""
	var labels: Dictionary = library.content.title_ui.labels
	match section:
		"main":
			for key in ["start", "load", "options", "help"]:
				entries.append({"text": library.text(int(labels[key])), "action": key})
			entries.append({"text": "Game files", "action": "files"})
		"start":
			entries = [
				{"text": "Start campaign", "action": "campaign"},
				{"text": "Skip campaign · Explore", "action": "explore"},
				{
					"text": library.text(int(library.content.survival.menu.title)),
					"action": "survival"
				}
			]
		"load":
			entries = [
				{
					"text": "Continue campaign",
					"action": "load_campaign",
					"enabled": FileAccess.file_exists(save_path("campaign"))
				},
				{
					"text": "Continue exploration",
					"action": "load_free",
					"enabled": FileAccess.file_exists(save_path("free"))
				},
				{
					"text": "Save current pilot",
					"action": "save",
					"enabled": session != null and not transient_preview
				}
			]
		"files":
			entries = [
				{"text": "Choose game IPA…", "action": "import"},
				{"text": "About this remake", "action": "about"}
			]
		"help":
			body = controls_help()
		"about":
			body = "Galaxy on Fire — native engine remake\n\nUses the artwork, text and game data imported from your supplied iPhone game.\n\nPlay the linear campaign, then explore freely. Skip campaign enters exploration directly without completion rewards.\n\nIndependent native systems recreate the game using your imported content. Exact legacy animation and driver behavior may differ."
	var back := (
		"Exit" if section == "main" else library.text(int(library.content.briefing_ui.labels.back))
	)
	title_panel.present(section, entries, back, "exit" if section == "main" else "main", body)
	if OS.has_feature("web") and section == "main":
		title_panel.footer.hide()


func title_action(action: String) -> void:
	match action:
		"main", "start", "load", "files", "help", "about":
			show_title_menu(action)
		"options":
			show_options()
		"campaign":
			request_start(false)
		"explore":
			request_start(true)
		"survival":
			show_survival_menu()
		"load_campaign":
			continue_game("campaign")
		"load_free":
			continue_game("free")
		"save":
			if session != null and not transient_preview:
				save_game()
		"import":
			choose_file()
		"exit":
			shutdown()


func show_dock() -> void:
	if not session.recovery.is_empty():
		show_recovery()
		return
	stop_flight()
	screen = "dock"
	paused = false
	clear_page()
	showcase.show()
	menu_camera.current = true
	show_menu_scene(false)
	top.hide()
	status.hide()
	page.hide()
	station_panel = preload("res://src/presentation/station_menu.gd").new()
	ui.add_child(station_panel)
	station_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	station_panel.configure(library, session)
	station_panel.action_requested.connect(station_action)
	play_menu_music(false)


func station_action(action: String) -> void:
	match action:
		"info", "back":
			station_panel.close_overlay()
		"hangar":
			show_market()
		"missions":
			show_contracts()
		"map":
			show_map()
		"launch":
			if session.campaign_state == "active":
				if session.mission_available():
					show_briefing()
			else:
				launch()
		"menu":
			show_station_menu()
		"status":
			station_panel.show_status()
		"save":
			save_game()
		"options":
			show_options()
		"skip":
			request_skip()
		"title":
			if save_game():
				show_title()


func show_station_menu() -> void:
	var entries := [
		{"text": library.text(int(library.content.title_ui.labels.options)), "action": "options"},
		{"text": "Save pilot", "action": "save"}
	]
	if session.campaign_state == "active":
		entries.append({"text": "Skip campaign · Explore", "action": "skip"})
	entries.append({"text": "Save & return to title", "action": "title"})
	entries.append(
		{"text": library.text(int(library.content.briefing_ui.labels.back)), "action": "back"}
	)
	station_panel.show_overlay("menu", entries)


func show_contracts() -> void:
	if not session.docked or not session.exploration_unlocked():
		return
	screen = "contracts"
	clear_page()
	show_menu_scene(false)
	top.hide()
	status.hide()
	page.hide()
	board_panel = preload("res://src/presentation/mission_board.gd").new()
	ui.add_child(board_panel)
	board_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_panel.configure(library, session)
	board_panel.back_requested.connect(show_dock)
	board_panel.accept_requested.connect(accept_board_offer)


func accept_board_offer(reference: Dictionary, offer: Dictionary) -> void:
	var index := int(reference.get("index", -1))
	var current: Array = session.contract_offers()
	if (
		index < 0 or index >= current.size()
		or reference != session.contract_reference(index)
		or offer != current[index]
	):
		notify("This mission offer has changed. Reopen the mission board.")
		return
	accept_contract(index)


func accept_contract(index: int) -> void:
	if session.begin_contract(index):
		launch(true)
	else:
		notify(session.error)


func show_briefing() -> void:
	if not session.begin_briefing():
		return
	stop_flight()
	clear_page()
	screen = "briefing"
	briefing_audio.library = library
	showcase.hide()
	menu_camera.current = true
	page.hide()
	var opening: bool = library.content.briefing_scene.chapters[session.chapter].kind == "intro"
	# Original opening enters from the title; later briefings inherit station music.
	# Restore that context when resuming directly into a saved briefing, too.
	play_menu_music(opening)
	briefing_scene = preload("res://src/presentation/opening_scene.gd").new() if opening else BriefingScene.new()
	world.add_child(briefing_scene)
	var scene_ready: bool = (
		briefing_scene.configure(library,session.chapter,session.station_id,session.ship_id,session.market_offers(),session.briefing_page)
		if opening else briefing_scene.configure(library,session.chapter,session.station_id)
	)
	if not scene_ready:
		menu_camera.current = true
		if not briefing_scene.error.is_empty():
			notify(briefing_scene.error)
		briefing_scene.queue_free()
		briefing_scene = null
	top.hide()
	status.hide()
	briefing_panel = Briefing.new()
	briefing_panel.library = library
	ui.add_child(briefing_panel)
	briefing_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	briefing_panel.next_requested.connect(next_briefing)
	briefing_panel.back_requested.connect(back_briefing)
	briefing_panel.skip_requested.connect(request_skip_briefing)
	briefing_panel.present(session.chapter, session.briefing_page)
	briefing_audio.present(session.chapter, session.briefing_page)
	if opening and is_instance_valid(briefing_scene):
		briefing_scene.fade_changed.connect(briefing_panel.set_scene_fade)
		briefing_panel.set_scene_fade(briefing_scene.choreography.alpha)
	save_game()


func next_briefing() -> void:
	briefing_audio.action("next")
	if not session.next_briefing_page():
		show_dock()
		notify(session.error)
		return
	if not session.docked:
		launch(true)
	else:
		briefing_panel.present(session.chapter, session.briefing_page)
		briefing_audio.present(session.chapter, session.briefing_page)
		if is_instance_valid(briefing_scene) and briefing_scene.has_method("present"):
			briefing_scene.present(session.briefing_page)
		save_game(false)


func back_briefing() -> void:
	briefing_audio.action("back")
	session.previous_briefing_page()
	if session.briefing_page < 0:
		show_dock()
	else:
		briefing_panel.present(session.chapter, session.briefing_page)
		briefing_audio.present(session.chapter, session.briefing_page)
	save_game(false)


func request_skip_briefing() -> void:
	briefing_audio.action("skip")
	briefing_panel.set_process_input(false)
	confirm(
		library.text(int(library.content.briefing_ui.labels.skip)),
		library.text(int(library.content.briefing_ui.labels.skip_question)),
		skip_briefing
	)


func skip_briefing() -> void:
	briefing_audio.action("confirm")
	if session.begin_mission():
		launch(true)
	else:
		show_dock()
		notify(session.error)


func resume_briefing_input() -> void:
	if screen == "briefing" and is_instance_valid(briefing_panel):
		briefing_audio.action("confirm")
		briefing_panel.set_process_input(true)


func choose_file() -> void:
	if OS.has_feature("web"):
		if web_picker == null:
			web_picker = preload("res://src/input/web_file_picker.gd").new()
			web_picker.selected.connect(import_web_file)
			web_picker.failed.connect(notify)
		web_picker.choose()
	else:
		dialog.popup_centered(Vector2i(950, 650))


func import_web_file(path: String) -> void:
	await import_file(path)
	web_picker.clear()
	# Cache activation renames directories after extraction; request another
	# browser snapshot after all mutations, including removal of temporary input.
	JavaScriptBridge.force_fs_sync()


func files_dropped(paths: PackedStringArray) -> void:
	if not paths.is_empty() and screen == "title" and not busy:
		import_file(paths[0])


func import_file(path: String) -> void:
	if busy:
		return
	busy = true
	clear_page()
	screen = "import"
	var box := column()
	caption("Importing your galaxy", "Reading the game archive on this device.", box)
	button("Cancel import", cancel_import, box)
	var success := await importer.install(path, get_tree())
	busy = false
	if exiting:
		return
	if not success:
		show_title()
		notify(importer.error)
		return
	if not activate_content():
		show_title()
		notify(library.error)
		return
	var config := ConfigFile.new()
	config.set_value("content", "directory", importer.root)
	config.save("user://install.cfg")
	show_title()
	notify("Game content imported successfully.")


func import_progress(message: String, ratio: float) -> void:
	if importer.cancelled:
		status.text = "Cancelling import…"
		return
	status.text = message if ratio <= 0 else "%d%%  ·  %s" % [int(ratio * 100), message]


func cancel_import() -> void:
	importer.cancel()
	status.text = "Cancelling import…"


func activate_content() -> bool:
	if survival_active():
		if not save_game(false):
			return false
		stop_flight()
		session = null
	survival_archive = null
	survival_name_draft = ""
	var lang := (
		"gb" if importer.metadata.languages.has("gb") else str(importer.metadata.languages[0])
	)
	ready_content = library.open(importer.root, importer.content_id, lang)
	if not ready_content:
		return false
	show_ship(int(library.content.initial.ship_index))
	sky_material.set_shader_parameter("nebula", library.texture("nebulas"))
	sky_material.set_shader_parameter("has_nebula", true)
	return true


func show_menu_scene(title: bool, preview_location: int = -1) -> void:
	if is_instance_valid(menu_scene):
		menu_scene.set_process(false)
		menu_scene.hide()
		menu_scene.queue_free()
	var location := int(
		session.station_id if session != null else library.content.initial.station_index
	)
	if preview_location >= 0:
		location = preview_location
	# A current campaign mission contributes the final decorative pilot ship.
	# Free exploration and a title without a pilot do not invent an active mission.
	var actor := -1
	if session != null and session.campaign_state == "active":
		actor = int(library.ship_definition(session.ship_id).actor)
	menu_scene = preload("res://src/presentation/destination_scene.gd").new() if preview_location >= 0 else preload("res://src/presentation/menu_scene.gd").new()
	world.add_child(menu_scene)
	var seed_value := hash(library.id + ":menu:" + str(location) + ":" + str(actor))
	var configured: bool = menu_scene.configure(library, location) if preview_location >= 0 else menu_scene.configure(library, location, actor, title, seed_value)
	if configured:
		showcase.hide()
	else:
		notify("Unable to display supplied menu scenery: " + menu_scene.error)
		menu_scene.hide()
		menu_scene.queue_free()
		menu_scene = null
		menu_camera.current = true


func show_ship(index: int) -> void:
	library.set_lighting(
		0,
		0,
		session.station_id if session != null else int(library.content.initial.station_index),
		true
	)
	for child in showcase.get_children():
		showcase.remove_child(child)
		child.queue_free()
	var model := library.model(library.ship_model(index), 90)
	showcase.add_child(model)
	showcase.position = Vector3(50, 0, -5)
	model.rotation_degrees.y = -25


func request_start(skip: bool) -> void:
	var slot := "free" if skip else "campaign"
	if FileAccess.file_exists(save_path(slot)):
		confirm(
			"Replace this pilot?",
			"The existing %s pilot will be replaced. The other save slot is kept." % slot,
			func(): start_game(skip)
		)
	else:
		start_game(skip)


func start_game(skip: bool) -> void:
	var candidate := Session.new()
	candidate.configure(library, skip)
	if not candidate.save(save_path(candidate.slot)):
		notify(candidate.error)
		return
	transient_preview = false
	session = candidate
	show_dock()


func continue_game(slot: String) -> void:
	var candidate := Session.new()
	candidate.configure(library, slot == "free")
	if not candidate.load_retry(save_path(slot)):
		notify(candidate.error)
		return
	transient_preview = false
	session = candidate
	if session.docked:
		if session.briefing_page >= 0:
			show_briefing()
		else:
			show_dock()
	else:
		launch(true)


func request_skip() -> void:
	confirm(
		"Skip the campaign?",
		"Your campaign pilot stays saved. A free-exploration pilot will be created from this ship and credits, replacing the free-exploration slot if one exists.",
		skip_current
	)


func skip_current() -> void:
	if not save_game(false):
		return
	var candidate := Session.new()
	candidate.configure(library)
	if not candidate.restore(session.capture()):
		notify(candidate.error)
		return
	candidate.slot = "free"
	candidate.skip_campaign()
	candidate.docked = true
	if not candidate.save(save_path(candidate.slot)):
		notify(candidate.error)
		return
	session = candidate
	show_dock()


func confirm(title: String, body: String, action: Callable) -> void:
	confirmation.title = title
	confirmation.dialog_text = body
	confirm_action = action
	confirmation.popup_centered(Vector2i(650, 200))


func save_path(slot: String) -> String:
	return "user://saves/" + library.id + "/" + slot + ".json"


func survival_active() -> bool:
	return session != null and session.slot == "survival"


func save_game(announce: bool = true) -> bool:
	# Keep the last viable checkpoint even after leaving the defeat screen.
	# Closing/backgrounding the app is allowed; it must not save the lost pilot.
	if session != null and not survival_active() and (session == defeated_session or not session.can_retry()):
		if announce: notify("The last saved game is preserved. Load it to try again.")
		return true
	if transient_preview:
		return true
	var success := true
	var failure := ""
	if survival_active() or screen.begins_with("survival_"):
		if (
			survival_archive == null
			or survival_archive.profile.content_id != library.id
			or (survival_active() and survival_archive.session != session)
		):
			success = false
			failure = "The survival run has no matching archive."
		else:
			success = survival_archive.checkpoint()
			failure = survival_archive.error
	elif session != null:
		success = session.save(save_path(session.slot))
		failure = session.error
	if not success:
		notify(failure)
		if screen != "pause": status.show()
	elif announce:
		notify("Pilot saved.")
	return success


func show_survival_menu(tab: int = 0, recent_run: int = 0) -> void:
	if not library.content.get("survival") is Dictionary:
		notify("Survival data is unavailable in this installation.")
		return
	if survival_archive == null or survival_archive.profile.content_id != library.id:
		var candidate := SurvivalArchive.new()
		if not candidate.open(
			library, library.content.survival, save_path("survival").get_base_dir()
		):
			notify(candidate.error)
			return
		survival_archive = candidate
	if survival_active() and not save_game(false):
		return
	if not survival_archive.result_summary().is_empty():
		show_survival_result()
		return
	stop_flight()
	clear_page()
	screen = "survival_menu"
	paused = true
	showcase.show()
	menu_camera.current = true
	page.hide()
	top.hide()
	status.hide()
	survival_panel = SurvivalMenu.new()
	ui.add_child(survival_panel)
	survival_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	survival_panel.present(
		library, survival_archive.declarations.menu, survival_archive.profile.state, recent_run, tab
	)
	survival_panel.start_requested.connect(start_survival)
	survival_panel.back_requested.connect(show_title)
	if survival_archive.session != null:
		survival_panel.footer[1].tooltip_text = "Resume the saved survival run"


func start_survival() -> void:
	if screen != "survival_menu" or survival_archive == null:
		return
	if survival_archive.session == null:
		if not survival_archive.start(
			int(library.content.initial.station_index), randi_range(0, 2147483647)
		):
			survival_panel.retry_action()
			notify(survival_archive.error)
			status.show()
			return
	stop_flight()
	session = survival_archive.session
	transient_preview = false
	if session.hull <= 0:
		show_survival_result()
	else:
		launch(true)


func show_survival_result() -> void:
	if survival_archive == null or survival_archive.result_summary().is_empty():
		return
	if is_instance_valid(flight):
		flight.pause(true)
	paused = true
	clear_page()
	screen = "survival_result"
	page.hide()
	top.hide()
	status.hide()
	survival_panel = SurvivalResult.new()
	ui.add_child(survival_panel)
	survival_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	survival_panel.present_result(survival_archive, survival_archive.declarations.choice)
	survival_panel.chosen.connect(func(_index): advance_survival_result())


func advance_survival_result() -> void:
	if screen != "survival_result":
		return
	if not survival_archive.receipt.is_empty():
		acknowledge_survival_result()
	elif int(survival_archive.result_summary().rank) >= 0:
		clear_page()
		screen = "survival_name"
		page.hide()
		top.hide()
		status.hide()
		survival_panel = SurvivalName.new()
		ui.add_child(survival_panel)
		survival_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		survival_panel.present(library, survival_archive.declarations.menu, survival_name_draft)
		survival_panel.submitted.connect(submit_survival_name)
		survival_panel.cancelled.connect(cancel_survival_name)
	else:
		submit_survival_name("")


func cancel_survival_name() -> void:
	if screen != "survival_name":
		return
	survival_name_draft = survival_panel.entry.text
	show_survival_result()


func submit_survival_name(pilot: String) -> void:
	if screen not in ["survival_name", "survival_result"]:
		return
	survival_name_draft = pilot
	if not survival_archive.finish(pilot):
		if screen == "survival_name":
			survival_panel.retry_submission()
		else:
			show_survival_result()
		notify(survival_archive.error)
		status.show()
		return
	stop_flight()
	if survival_active():
		session = null
	survival_name_draft = ""
	acknowledge_survival_result()


func acknowledge_survival_result() -> void:
	var recent := int(survival_archive.receipt.get("run", 0))
	if not survival_archive.acknowledge_result():
		show_survival_result()
		notify(survival_archive.error)
		status.show()
		return
	stop_flight()
	if survival_active():
		session = null
	show_survival_menu(1, recent)


func abandon_survival() -> void:
	if not survival_active() or survival_archive.session != session:
		return
	if not survival_archive.abandon():
		notify(survival_archive.error)
		return
	stop_flight()
	session = null
	show_survival_menu()


func launch(resume: bool = false) -> void:
	if not resume and not session.depart():
		notify(session.error)
		return
	stop_flight()
	showcase.hide()
	screen = "flight"
	paused = false
	flight = Flight.new()
	world.add_child(flight)
	flight.setup(library, session, settings, resume)
	flight.dock_requested.connect(dock)
	flight.defeated.connect(defeat)
	flight.mission_failed.connect(func(): defeat(true))
	flight.mission_completed.connect(finish_mission)
	flight.message_changed.connect(notify)
	show_flight_hud()
	flight.pause(false)
	if not save_game():
		var failure := notification_text
		show_pause()
		notify(failure)
	play_music("GalaxyOnFire1_Game")


func stop_flight() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if flight != null and is_instance_valid(flight):
		flight.paused = true
		world.remove_child(flight)
		flight.queue_free()
	flight = null


func dock() -> void:
	if session.arrive(session.station_id):
		show_dock()
		save_game(false)


func finish_mission() -> void:
	if session.finish_mission():
		show_dock()
		save_game(false)


func defeat(timed_out: bool = false) -> void:
	if survival_active():
		flight.pause(true)
		show_survival_result()
		save_game(false)
		return
	flight.pause(true)
	defeated_session = session
	screen = "defeat"
	clear_page()
	page.hide()
	top.hide()
	status.hide()
	defeat_panel = preload("res://src/presentation/defeat_menu.gd").new()
	ui.add_child(defeat_panel)
	defeat_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	defeat_panel.chosen.connect(defeat_choice)
	show_defeat_message(mission_failure_text() if timed_out else library.text(int(library.content.defeat_ui.labels.lost)))


func show_defeat_message(message: String, notice: bool = false) -> void:
	defeat_notice = notice
	var labels: Dictionary = library.content.defeat_ui.labels
	var captions: Array[String] = []
	if not notice:
		captions.assign([library.text(int(labels.load)), library.text(int(labels.menu))])
	defeat_panel.present(library, library.content.survival.choice, message, captions)


func defeat_choice(index: int) -> void:
	if defeat_notice or index == 1:
		show_title()
		return
	var candidate := Session.new()
	candidate.configure(library, session.slot == "free")
	if transient_preview or not candidate.load_retry(save_path(session.slot)):
		show_defeat_message(library.text(int(library.content.defeat_ui.labels.missing)), true)
		return
	if candidate.slot != session.slot:
		show_defeat_message("The saved game belongs to a different pilot slot.", true)
		return
	session = candidate
	defeated_session = null
	if session.docked:
		if session.briefing_page >= 0: show_briefing()
		else: show_dock()
	else:
		launch(true)


func show_flight_hud() -> void:
	clear_page()
	# Removing station scenery restores the menu camera. Flight owns the view
	# after that cleanup, including undock, save reload and pause returns.
	flight.camera.make_current()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.hide()
	status.hide()
	hud = HUD.new()
	hud.flight = flight
	hud.touch_enabled = bool(settings.touch)
	ui.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flight_buttons = hud.buttons.duplicate()
	flight_buttons.boost.button_down.connect(func(): flight.controls.touch_boost = true)
	flight_buttons.boost.button_up.connect(func(): flight.controls.touch_boost = false)
	flight_buttons.fire.button_down.connect(func(): flight.controls.touch_fire = true)
	flight_buttons.fire.button_up.connect(func(): flight.controls.touch_fire = false)
	flight_buttons.weapon.pressed.connect(func(): session.cycle_weapon())
	flight_buttons.missiles.button_down.connect(func(): flight.controls.touch_missiles = true)
	flight_buttons.missiles.button_up.connect(func(): flight.controls.touch_missiles = false)
	flight_buttons.pause.pressed.connect(show_pause)
	flight_objective = label(flight.objective(), 16, Color("ffca79"))
	hud.add_child(flight_objective)
	flight_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	flight_objective.offset_left = -200
	flight_objective.offset_right = 200
	flight_objective.offset_top = 12
	flight_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flight_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flight_objective.visible = not survival_active()
	var extra := VBoxContainer.new()
	hud.add_child(extra)
	extra.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	extra.offset_left = -185
	extra.offset_right = 185
	extra.offset_top = -125
	extra.offset_bottom = -12
	extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio = label("", 14, Color("b5d4de"))
	radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extra.add_child(radio)
	flight_stats = label("", 14)
	flight_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extra.add_child(flight_stats)
	var controls := HBoxContainer.new()
	controls.visible = bool(settings.touch)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	extra.add_child(controls)
	var actions := ["TIME"] if survival_active() else ["TIME", "AUTOPILOT", "DOCK"]
	if settings.touch:
		actions.push_front("−")
		actions.append("+")
	for action in actions:
		var callback: Callable
		if action in ["−", "+"]:
			callback = change_touch_throttle.bind(-.25 if action == "−" else .25)
		else:
			callback = (
				flight.cycle_time
				if action == "TIME"
				else (flight.toggle_autopilot if action == "AUTOPILOT" else flight.try_dock)
			)
		var control := button(action, callback, controls)
		control.custom_minimum_size = Vector2(48 if action in ["−", "+"] else 70, 32)
		control.alignment = HORIZONTAL_ALIGNMENT_CENTER
		control.add_theme_font_size_override("font_size", 12)
		control.tooltip_text = (
			"Decrease speed"
			if action == "−"
			else ("Increase speed" if action == "+" else action.capitalize())
		)
		hud.extra_buttons[action] = control
	dialogue_panel = Dialogue.new()
	dialogue_panel.library = library
	ui.add_child(dialogue_panel)
	dialogue_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_panel.hide()
	dialogue_panel.dismissed.connect(
		func():
			session.dismiss_radio()
			dialogue_panel.present({})
	)
	update_tutorial_controls()


func change_touch_throttle(amount: float) -> void:
	if flight != null and not flight.paused and not flight.cinematic_locked():
		flight.auto_pilot = false
		flight.throttle += amount


func update_tutorial_controls() -> void:
	var cue: Dictionary = session.tutorial_cue()
	for action in flight_buttons:
		var control: TextureButton = flight_buttons[action]
		var highlighted: bool = cue.get("action") == action and cue.get("lit", false)
		if action == "fire":
			control.self_modulate.a = (
				1.0 if control.is_pressed() or flight.controls.touch_fire or highlighted else 0.0
			)
		else:
			control.texture_normal = library.ui_image(
				library.content.flight_ui.buttons[action]["pressed" if highlighted else "normal"]
			)


func show_pause() -> void:
	if survival_active() and session.hull <= 0:
		show_survival_result()
		return
	if flight == null:
		return
	paused = true
	flight.pause(true)
	screen = "pause"
	clear_page()
	top.hide()
	status.hide()
	page.hide()
	pause_panel = preload("res://src/presentation/pause_menu.gd").new()
	ui.add_child(pause_panel)
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.setup(library, controls_help(), survival_active(), not transient_preview)
	pause_panel.selected.connect(pause_action)


func pause_action(action: String) -> void:
	match action:
		"resume": resume_flight()
		"options": show_options()
		"save": save_game()
		"menu":
			if save_game(false): show_title()
		"abandon": abandon_survival()


func resume_flight() -> void:
	if survival_active() and session.hull <= 0:
		show_survival_result()
		return
	screen = "flight"
	paused = false
	show_flight_hud()
	flight.pause(false)


func focus_lost() -> void:
	if screen == "flight" and not transient_preview:
		show_pause()


func navigate_back() -> void:
	if busy:
		cancel_import()
		return
	if confirmation.visible:
		confirmation.hide()
		resume_briefing_input()
	elif dialog.visible:
		dialog.hide()
	elif screen == "title" and is_instance_valid(title_panel) and title_panel.section != "main":
		show_title_menu("main")
	elif screen == "map" and is_instance_valid(destination_panel):
		close_destination()
	elif screen == "contracts" and is_instance_valid(board_panel):
		board_panel.handle_action("back")
	elif screen == "market" and is_instance_valid(hangar_panel):
		hangar_panel.handle_action("back")
	elif screen == "dock" and is_instance_valid(station_panel):
		if station_panel.section == "info":
			show_station_menu()
		else:
			station_panel.close_overlay()
	elif screen == "survival_menu":
		show_title()
	elif screen == "survival_name":
		cancel_survival_name()
	elif screen == "survival_result":
		advance_survival_result()
	elif screen == "defeat":
		show_title()
	elif screen == "flight":
		show_pause()
	elif screen == "pause":
		if is_instance_valid(pause_panel): pause_panel.back()
		else: resume_flight()
	elif screen == "map" and is_instance_valid(map_panel):
		map_panel.back()
	elif screen in ["map", "market", "contracts"]:
		show_dock()
	elif screen == "recovery":
		acknowledge_recovery()
	elif screen == "briefing":
		back_briefing()
	elif screen == "options":
		if is_instance_valid(options_panel):
			options_panel.back()
		else:
			close_options()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F11:
			change_option("fullscreen", not DisplaySettings.fullscreen(get_window()))
		elif event.physical_keycode == KEY_ESCAPE:
			navigate_back()
		elif event.physical_keycode == KEY_F5:
			save_game()
	if (
		event is InputEventJoypadButton
		and event.pressed
		and event.button_index == JOY_BUTTON_B
		and screen in ["title", "dock", "market", "contracts", "map", "options", "pause", "defeat"]
	):
		navigate_back()
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if screen == "flight":
			show_pause()
		elif screen == "pause":
			navigate_back()
	if screen == "flight" and settings.touch and flight != null:
		if event is InputEventScreenTouch:
			if event.pressed and touch_finger < 0:
				touch_finger = event.index
				touch_origin = event.position
			elif event.index == touch_finger:
				touch_finger = -1
				flight.controls.touch_look = Vector2.ZERO
		elif event is InputEventScreenDrag and event.index == touch_finger:
			flight.controls.touch_look = ((event.position - touch_origin) / 90).limit_length()


func show_map() -> void:
	if not session.exploration_unlocked():
		notify("The galaxy opens after the campaign, or through Skip campaign.")
		return
	screen = "map"
	clear_page()
	show_menu_scene(false)
	top.hide()
	status.hide()
	page.hide()
	map_panel = preload("res://src/presentation/map_menu.gd").new()
	ui.add_child(map_panel)
	map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_panel.configure(library,session)
	galaxy_map = map_panel.chart
	map_panel.destination_selected.connect(select_destination)
	map_panel.back_requested.connect(show_dock)


func select_destination(index: int) -> void:
	if index < 0 or index >= library.stations.size() or not session.exploration_unlocked():
		return
	star_map_selection = index
	galaxy_map.reveal(index)
	map_panel.hide()
	if is_instance_valid(destination_panel):
		destination_panel.hide()
		destination_panel.queue_free()
	# Preview the selected location without changing the pilot's actual station.
	show_menu_scene(false, index)
	top.hide()
	status.hide()
	page.hide()
	destination_panel = preload("res://src/presentation/destination_menu.gd").new()
	ui.add_child(destination_panel)
	destination_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	destination_panel.configure_destination(library, session, index)
	destination_panel.back_requested.connect(close_destination)
	destination_panel.travel_requested.connect(travel_selected)


func close_destination() -> void:
	if not is_instance_valid(destination_panel):
		return
	destination_panel.hide()
	destination_panel.queue_free()
	destination_panel = null
	show_menu_scene(false)
	map_panel.show()
	map_panel.restore_focus()


func travel_selected() -> void:
	if is_instance_valid(travel_transition) or not is_instance_valid(destination_panel):
		return
	if not destination_panel.current_quote():
		destination_panel.travel_button.disabled = true
		destination_panel.show_notice("Travel costs have changed. Reopen this destination to review them.")
		return
	travel_transition = preload("res://src/presentation/travel_transition.gd").new()
	ui.add_child(travel_transition)
	await travel_transition.play(commit_travel.bind(session, destination_panel))
	travel_transition = null


func commit_travel(pilot, panel) -> void:
	if exiting or session != pilot or not is_instance_valid(panel) or panel != destination_panel:
		return
	if not panel.current_quote():
		panel.travel_button.disabled = true
		panel.show_notice("Travel costs have changed. Reopen this destination to review them.")
		panel.actions[0].grab_focus()
		return
	if session.travel(panel.destination):
		show_dock()
		# Report storage failures on the destination screen that remains visible.
		save_game(false)
	else:
		panel.show_notice("Travel is unavailable. Check your credits and active mission.")
		panel.actions[0].grab_focus()


func show_market(section: String = "ship") -> void:
	screen = "market"
	clear_page()
	menu_scene = preload("res://src/presentation/hangar_scene.gd").new()
	world.add_child(menu_scene)
	if menu_scene.configure(library, session.station_id, session.ship_id, session.market_offers()):
		showcase.hide()
	else:
		notify("Unable to display supplied Hangar: " + menu_scene.error)
		menu_scene.hide()
		menu_scene.queue_free()
		menu_scene = null
		menu_camera.current = true
	top.hide()
	status.hide()
	page.hide()
	hangar_panel = preload("res://src/presentation/hangar_menu.gd").new()
	ui.add_child(hangar_panel)
	hangar_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hangar_panel.configure(library,session)
	hangar_panel.open_tab(section)
	hangar_panel.back_requested.connect(show_dock)
	hangar_panel.transaction_requested.connect(hangar_transaction)
	hangar_panel.hint_acknowledged.connect(save_hangar_hint)
	hangar_panel.enable_hints(hangar_hint_history())


func hangar_hint_path() -> String:
	return "user://hangar-hints.cfg"


func hangar_hint_history() -> Array:
	var file := ConfigFile.new()
	if file.load(hangar_hint_path()) != OK:
		return []
	var value: Variant = file.get_value(library.id, "acknowledged", [])
	if not value is Array:
		return []
	return value.filter(func(role): return role is String and library.content.hangar_ui.hints.messages.has(role))


func save_hangar_hint(role: String) -> void:
	# First-use guidance belongs to this installation/content, not pilot progress.
	var file := ConfigFile.new()
	file.load(hangar_hint_path())
	var history := hangar_hint_history()
	if not history.has(role):
		history.append(role)
	file.set_value(library.id, "acknowledged", history)
	if file.save(hangar_hint_path()) != OK:
		notify("Unable to remember the acknowledged Hangar hint.")


func hangar_transaction(action: String, entry: Dictionary) -> void:
	var success := false
	match action:
		"exchange": success = session.buy_ship_quote(entry)
		"buy": success = session.buy_offer(int(entry.index))
		"remove": success = session.remove_equipment(int(entry.index))
		"fit": success = session.fit_equipment(int(entry.index))
		"sell": success = session.sell_equipment(int(entry.index))
		"sell_cargo": success = session.sell_cargo(int(entry.id), int(entry.get("amount", 1)))
	if success:
		# Refresh the actual hull/stock without restarting the entrance or tab.
		if is_instance_valid(menu_scene) and not menu_scene.refresh_inventory(session.ship_id, session.market_offers()):
			notify(menu_scene.error)
		hangar_panel.refresh()
		save_game(false)
	else:
		hangar_panel.show_notice(session.error if not session.error.is_empty() else "This action is unavailable.")


func show_options() -> void:
	settings.fullscreen = DisplaySettings.fullscreen(get_window())
	var section: String = options_panel.section if is_instance_valid(options_panel) else "options"
	if screen != "options":
		options_return_screen = screen
	if flight != null:
		flight.pause(true)
	screen = "options"
	clear_page()
	if ready_content and flight == null:
		show_menu_scene(options_return_screen == "title" or session == null)
	if ready_content:
		top.hide()
		status.hide()
		page.hide()
		options_panel = preload("res://src/presentation/options_menu.gd").new()
		ui.add_child(options_panel)
		options_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		options_panel.setup(library, settings, controls_help())
		options_panel.setting_changed.connect(change_option)
		options_panel.back_requested.connect(close_options)
		if section != "options":
			options_panel.show_section(section)
		return
	# Settings before an archive is installed cannot use its artwork or labels.
	var box := column(650)
	caption("Options & controls", "Mouse + keyboard, controller and touch flight.", box)
	var option_keys := ["music", "invert", "aim_assist", "linked_fire", "touch"]
	if ready_content:
		option_keys.insert(3, "targeting_reticle")
	for key in option_keys:
		var check := CheckButton.new()
		check.text = (
			{
				"music": "Music",
				"invert": "Invert mouse pitch",
				"aim_assist": "Aim assistance",
				"linked_fire": "Fire all mounted primary weapons together",
				"touch": "Show touch controls"
			}
			. get(key, "")
		)
		if key == "targeting_reticle":
			check.text = library.text(int(library.content.flight_ui.radar.lead.option_text))
			check.tooltip_text = "Show where to aim ahead of a moving target."
		check.button_pressed = (
			bool(library.content.flight_ui.radar.lead.enabled)
			if key == "targeting_reticle" and settings[key] == null
			else bool(settings[key])
		)
		box.add_child(check)
		check.toggled.connect(
			func(value):
				settings[key] = value
				if key == "music" and value and settings.music_volume <= 0:
					settings.music_volume = 1.0
				save_settings()
				if key == "music":
					music.volume_db = -17 if value else -80
		)
	paragraph("Mouse sensitivity", box)
	var sensitivity := HSlider.new()
	sensitivity.min_value = .0005
	sensitivity.max_value = .008
	sensitivity.step = .0001
	sensitivity.value = settings.sensitivity
	box.add_child(sensitivity)
	sensitivity.value_changed.connect(
		func(value):
			settings.sensitivity = value
			save_settings()
	)
	paragraph(controls_help(), box)
	button("Back", close_options, box)


func close_options() -> void:
	if flight != null:
		flight.settings.merge(settings, true)
		show_pause()
	elif options_return_screen == "dock":
		show_dock()
	else:
		show_title()


func change_option(key: String, value: Variant) -> void:
	if key == "fullscreen" and value is bool:
		DisplaySettings.set_fullscreen(get_window(), value)
		settings.fullscreen = value
	elif key == "aspect_ratio" and value is String and DisplaySettings.RATIOS.has(value):
		settings.aspect_ratio = value
		DisplaySettings.apply_aspect(get_window(), value)
	elif key in ["music_volume", "effects_volume", "sensitivity"]:
		if not value is float and not value is int: return
		if not is_finite(float(value)): return
		settings[key] = clampf(float(value), .0005, .008) if key == "sensitivity" else clampf(float(value), 0, 1)
		if key == "music_volume":
			settings.music = settings.music_volume > 0
	elif key in ["invert", "aim_assist", "linked_fire", "touch", "targeting_reticle"] and value is bool:
		settings[key] = value
	else:
		return
	save_settings()


func apply_audio_settings() -> void:
	preload("res://src/presentation/audio_settings.gd").apply(settings)
	music.volume_db = -17 if settings.music else -80


func settings_path() -> String:
	return "user://settings.cfg"


func save_settings() -> void:
	apply_audio_settings()
	var file := ConfigFile.new()
	for key in settings:
		file.set_value("options", key, settings[key])
	file.save(settings_path())


func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(settings_path()) != OK:
		return
	for key in settings:
		if file.has_section_key("options", key):
			settings[key] = file.get_value("options", key)
	for key in ["music_volume", "effects_volume"]:
		var value: Variant = settings[key]
		settings[key] = clampf(float(value), 0, 1) if (value is float or value is int) and is_finite(float(value)) else 1.0


func play_menu_music(title_context: bool) -> void:
	if not ready_content:
		return
	var tracks: Dictionary = library.content.briefing_ui.audio.music
	var track: int = tracks.title if title_context else (
		tracks.alien if library.station_definition(session.station_id).race == tracks.alien_race else tracks.station
	)
	play_music(library.content.sound_bank[str(track)].path.get_file().get_basename())


func play_music(track: String) -> void:
	if not ready_content:
		return
	if music.get_meta("track", "") == track and music.playing:
		return
	music.stream = library.music(track)
	music.set_meta("track", track)
	music.volume_db = -17 if settings.music else -80
	if music.stream != null:
		music.play()


func notify(message: String) -> void:
	notification_text = message
	notification_time = 8
	if screen == "title" and is_instance_valid(title_panel):
		title_panel.present(
			"notice",
			[],
			library.text(int(library.content.briefing_ui.labels.back)),
			"main",
			message
		)
	elif screen == "defeat" and is_instance_valid(defeat_panel):
		show_defeat_message(message, defeat_notice)
	elif screen == "pause" and is_instance_valid(pause_panel):
		pause_panel.show_notice(message)
	elif screen == "map" and is_instance_valid(destination_panel):
		destination_panel.show_notice(message)
	elif screen == "contracts" and is_instance_valid(board_panel):
		board_panel.show_notice(message)
	elif screen == "market" and is_instance_valid(hangar_panel):
		hangar_panel.show_notice(message)
	elif screen == "dock" and is_instance_valid(station_panel):
		station_panel.show_overlay(
			"notice",
			[
				{
					"text": library.text(int(library.content.briefing_ui.labels.back)),
					"action": "back"
				}
			],
			message
		)
	elif radio != null:
		radio.text = message
	else:
		status.text = message


func _process(delta: float) -> void:
	# Browser Escape and the window manager can exit fullscreen independently.
	if is_instance_valid(options_panel) and screen == "options" and options_panel.section == "display":
		var fullscreen_now := DisplaySettings.fullscreen(get_window())
		if options_panel.values.get("fullscreen", false) != fullscreen_now:
			settings.fullscreen = fullscreen_now
			options_panel.values.fullscreen = fullscreen_now
			options_panel.show_section("display", "fullscreen")
	record_play_time(delta, get_window().has_focus())
	if flight != null and screen in ["defeat", "survival_result", "survival_name"]:
		flight.advance_defeat_presentation(delta)
	if showcase.visible:
		showcase.rotate_y(delta * .08)
	notification_time = maxf(0, notification_time - delta)
	if flight != null and screen == "flight":
		if flight.paused and not paused:
			show_pause()
			return
		flight_objective.text = flight.objective()
		flight_stats.text = (
			"%d m/s    ×%d    %s"
			% [flight.speed, flight.time_factor, "Autopilot" if flight.auto_pilot else "Manual"]
		)
		update_tutorial_controls()
		dialogue_panel.present(session.radio_cue())
		radio.text = notification_text if notification_time > 0 else ""
		save_timer += delta
		if save_timer > 30 and not transient_preview:
			save_timer = 0
			if not save_game(false):
				show_pause()
				notify(notification_text)
	if not pending_capture.is_empty() and not busy:
		capture_delay -= delta
		if capture_delay <= 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(pending_capture)
			pending_capture = ""
			if auto_exit:
				await shutdown()


func arguments() -> void:
	var args := OS.get_cmdline_user_args()
	var ipa := ""
	var mode := ""
	for arg in args:
		if arg.begins_with("--ipa="):
			ipa = arg.trim_prefix("--ipa=")
		elif arg.begins_with("--preview="):
			mode = arg.trim_prefix("--preview=")
		elif arg.begins_with("--capture="):
			pending_capture = arg.trim_prefix("--capture=")
			capture_delay = 8
		elif arg == "--exit-after-capture":
			auto_exit = true
	if not ipa.is_empty():
		await import_file(ipa)
	if ready_content and not mode.is_empty():
		transient_preview = true
		# Preview flags create a transient pilot and never replace an existing save.
		session = Session.new()
		session.configure(
			library,
			(
				mode
				not in [
					"training",
					"campaign",
					"clearance",
					"interception",
					"escort",
					"assault",
					"duel",
					"convoy",
					"cruiser",
					"rescue",
					"strike",
					"ambush",
					"pursuit"
				]
			)
		)
		if mode in ["market", "outfitting"]:
			show_market("stock" if mode == "market" else "fitted")
		elif (
			mode
			in [
				"flight",
				"training",
				"clearance",
				"interception",
				"escort",
				"assault",
				"duel",
				"convoy",
				"cruiser",
				"rescue",
				"strike",
				"ambush",
				"pursuit"
			]
		):
			if mode == "clearance":
				session.chapter = 1
			elif mode == "interception":
				session.chapter = 2
			elif mode == "escort":
				session.chapter = 3
				session.station_id = library.chapter_destination(2)
			elif mode == "assault":
				session.chapter = 4
				session.station_id = library.chapter_destination(3)
			elif mode == "duel":
				session.chapter = 5
				session.station_id = library.chapter_destination(4)
			elif mode == "convoy":
				session.chapter = 6
				session.station_id = library.chapter_destination(5)
			elif mode == "cruiser":
				session.chapter = 7
				session.station_id = library.chapter_destination(6)
			elif mode == "rescue":
				session.chapter = 8
				session.station_id = library.chapter_destination(7)
			elif mode == "strike":
				session.chapter = 9
				session.station_id = library.chapter_destination(8)
			elif mode == "ambush":
				session.chapter = 10
				session.station_id = library.chapter_destination(9)
			elif mode == "pursuit":
				session.chapter = 11
				session.station_id = library.chapter_destination(10)
			session.progression = Session.Progression.create(session.chapter)
			session.depart()
			launch_preview()
		elif mode == "map":
			show_map()
		else:
			show_dock()


func launch_preview() -> void:
	stop_flight()
	showcase.hide()
	screen = "flight"
	paused = false
	flight = Flight.new()
	world.add_child(flight)
	flight.setup(library, session, settings)
	flight.dock_requested.connect(dock)
	flight.defeated.connect(defeat)
	flight.mission_failed.connect(func(): defeat(true))
	flight.mission_completed.connect(finish_mission)
	flight.message_changed.connect(notify)
	show_flight_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	flight.throttle = 0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		navigate_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED and is_node_ready() and not exiting:
		focus_lost()
		save_game()


func shutdown() -> void:
	if exiting:
		return
	exiting = true
	if busy:
		cancel_import()
		while busy:
			await get_tree().process_frame
	if not save_game(false):
		exiting = false
		return
	music.stop()
	music.stream = null
	stop_flight()
	# Let the audio mix thread release its playback reference before teardown.
	await get_tree().create_timer(.15).timeout
	get_tree().quit()


func _exit_tree() -> void:
	music.stop()
	music.stream = null


func mission_failure_text() -> String:
	var definition: Dictionary = session.mission_definition()
	if (
		definition.has("failure")
		and session.Mission.achieved(definition.failure, definition, session.active_job)
	):
		return (
			library.text(int(library.content.defeat_ui.labels.lost)) + "\n"
			+ str(definition.get("failure_prefix", ""))
			+ library.text(int(definition.failure_text))
		)
	return library.text(int(library.content.defeat_ui.labels.lost)) + "\n" + library.text(int(library.content.defeat_ui.labels.timeout))


func show_recovery() -> void:
	if is_instance_valid(flight):
		flight.paused = true
	else:
		showcase.show()
		menu_camera.current = true
		show_ship(session.ship_id)
	screen = "recovery"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_page()
	page.hide()
	top.hide()
	status.hide()
	recovery_panel = RecoveryPanel.new()
	recovery_panel.library = library
	recovery_panel.receipt = session.recovery.duplicate(true)
	recovery_panel.acknowledged.connect(acknowledge_recovery)
	ui.add_child(recovery_panel)
	recovery_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func acknowledge_recovery() -> void:
	session.acknowledge_recovery()
	show_dock()
	save_game(false)


func controls_help() -> String:
	return "W / S · Throttle    A / D · Strafe\nMouse or arrow keys · Steer\nClick or Space · Fire    Shift · Boost\nQ · Next weapon    F · Missiles\nR · Autopilot    T · Time acceleration\nE · Dock    C · Camera    Tab · Release mouse\nEsc · Pause    F5 · Save    F11 · Fullscreen\n\nController: right stick aims, left stick strafes, D-pad sets throttle, RT fires, LT launches missiles, X switches weapons, Y docks, LB autopilot, RB time, Start pauses.\n\nTouch: drag empty space to steer; use the on-screen actions."


func setup_menu_input() -> void:
	# Godot's built-in menu actions supply keyboard bindings only. Keep those,
	# and add the standard controller equivalents for all native controls.
	var bindings := {
		"ui_accept": JOY_BUTTON_A,
		"ui_cancel": JOY_BUTTON_B,
		"ui_up": JOY_BUTTON_DPAD_UP,
		"ui_down": JOY_BUTTON_DPAD_DOWN,
		"ui_left": JOY_BUTTON_DPAD_LEFT,
		"ui_right": JOY_BUTTON_DPAD_RIGHT
	}
	for action in bindings:
		var event := InputEventJoypadButton.new()
		event.button_index = bindings[action]
		event.device = -1
		if not InputMap.action_has_event(action, event):
			InputMap.action_add_event(action, event)
	for binding in [["ui_up", -1.0], ["ui_down", 1.0], ["ui_left", -1.0], ["ui_right", 1.0]]:
		var event := InputEventJoypadMotion.new()
		event.axis = JOY_AXIS_LEFT_Y if binding[0] in ["ui_up", "ui_down"] else JOY_AXIS_LEFT_X
		event.axis_value = binding[1]
		event.device = -1
		if not InputMap.action_has_event(binding[0], event):
			InputMap.action_add_event(binding[0], event)


func record_play_time(delta: float, focused: bool) -> void:
	if session != null and session.slot != "survival" and not transient_preview:
		session.PilotStatistics.advance(
			session.statistics,
			delta,
			screen in ["dock", "market", "contracts", "map", "briefing", "recovery", "flight"]
			and not paused
			and focused
		)
