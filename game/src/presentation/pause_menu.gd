extends "res://src/presentation/title_menu.gd"
## Original pause menu with native save and survival actions.
signal selected(action: String)
var help_text := ""
var survival := false
var can_save := true
var overlay
var pending_action := ""
var return_focus: Control


func setup(source, help: String, arcade: bool, saving: bool) -> void:
	configure(source)
	data = data.duplicate(true)
	data.row_step = library.content.pause_ui.row_step
	help_text = help
	survival = arcade
	can_save = saving
	action_requested.connect(handle_action)
	show_root()


func show_root() -> void:
	var labels: Dictionary = library.content.pause_ui.labels
	present("pause", [
		{"text": library.text(int(labels.resume)), "action": "resume"},
		{"text": library.text(int(labels.options)), "action": "options"},
		{"text": library.text(int(labels.help)), "action": "help"},
		{"text": "Save pilot", "action": "save", "enabled": can_save},
		{"text": library.text(int(labels.menu)), "action": "menu",
			"hint": "Save your pilot and return to the main menu." if can_save else "Return to the main menu."}
	], "Abandon run" if survival else "Load / recover", "abandon" if survival else "load")
	footer.visible = survival or can_save
	var focusable: Array[Control] = []
	for button in buttons:
		if not button.disabled: focusable.append(button)
	if footer.visible: focusable.append(footer)
	for index in focusable.size():
		var control: Control = focusable[index]
		control.focus_neighbor_top = control.get_path_to(focusable[posmod(index - 1, focusable.size())])
		control.focus_neighbor_bottom = control.get_path_to(focusable[(index + 1) % focusable.size()])
		control.focus_previous = control.focus_neighbor_top
		control.focus_next = control.focus_neighbor_bottom


func handle_action(action: String) -> void:
	if is_instance_valid(overlay): return
	match action:
		"help": present("help", [], library.text(int(library.content.briefing_ui.labels.back)), "back", help_text)
		"back": back()
		"abandon":
			if survival:
				show_choice("Abandon this run? This ends the run without recording a high score.", ["Abandon", library.text(int(library.content.briefing_ui.labels.back))], "abandon")
		"save":
			if can_save: selected.emit(action)
		"load":
			if can_save and not survival: selected.emit(action)
		"resume", "options", "menu": selected.emit(action)


func back() -> void:
	if is_instance_valid(overlay):
		dismiss_choice()
	elif section == "help":
		show_root()
		buttons[2].grab_focus()
	else:
		selected.emit("resume")


func show_notice(message: String) -> void:
	show_choice(message)


func show_choice(message: String, captions: Array[String] = [], action: String = "") -> void:
	if is_instance_valid(overlay): dismiss_choice()
	return_focus = get_viewport().gui_get_focus_owner()
	canvas.hide()
	pending_action = action
	overlay = preload("res://src/presentation/choice_window.gd").new()
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.present(library, library.content.survival.choice, message, captions)
	overlay.chosen.connect(func(index: int):
		var chosen := pending_action
		dismiss_choice()
		if index == 0 and not chosen.is_empty(): selected.emit(chosen)
	)


func dismiss_choice() -> void:
	if is_instance_valid(overlay):
		overlay.hide()
		overlay.set_process_input(false)
		overlay.queue_free()
	overlay = null
	pending_action = ""
	canvas.show()
	if is_instance_valid(return_focus): return_focus.grab_focus()
