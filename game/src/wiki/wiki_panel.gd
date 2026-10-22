extends PanelContainer
## Adapted from the Apache-2.0 licensed maintained DEEP remake (Abyssal).
## The in-game reference reader. Down the side: search, sections and the
## pages as rows with their picture. Beside them the page: its article and
## its picture (a turning ship, the imported art or the galaxy map). History
## goes back and forward. On a narrower screen the picture moves above the
## article; on a narrow one the list and the page take turns. Links on a
## page are also offered in a list, so a controller can follow them. Esc
## belongs to the screen that opened the reader; Alt+Left and Alt+Right step
## through history.
signal closed

const Catalog = preload("res://src/wiki/wiki_catalog.gd")
const WikiHtml = preload("res://src/wiki/wiki_html.gd")
const WikiMedia = preload("res://src/wiki/wiki_media.gd")
const WikiExport = preload("res://src/wiki/wiki_export.gd")
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
const TouchScroll = preload("res://src/input/touch_scroll.gd")
const ALL := "all"
## At most this many rows are built at once; a search narrows the rest.
const ROWS := 240
const TEXT := Color("dce9ed")
const DIM := Color("a4bac8")
const FAINT := Color("6f8796")
const ACCENT := Color("f5d5a4")
const LINE := Color("375766")
const FOCUS := Color("ffca79")

var catalog: Catalog
var library
var history: Array[String] = []
var cursor := -1
var category := ALL
var showing_list := false
var search := LineEdit.new()
var sections := OptionButton.new()
var rows := VBoxContainer.new()
var list_scroll := ScrollContainer.new()
var count := Label.new()
var article := RichTextLabel.new()
var article_scroll := ScrollContainer.new()
var media: WikiMedia = WikiMedia.new()
var page_box := BoxContainer.new()
var related := OptionButton.new()
var back := Button.new()
var forward := Button.new()
var home := Button.new()
var browse := Button.new()
var save_button := Button.new()
var language_menu := OptionButton.new()
## The reference's language for the rest of the run, once chosen in its menu.
static var chosen_language := ""
var chapter_limit := -1
var close := Button.new()
var status := Label.new()
var side := VBoxContainer.new()
var reader := VBoxContainer.new()
var listed: Array = []


func configure(source, limit_ := -1) -> void:
	library = source
	chapter_limit = limit_
	catalog = Catalog.new(library, chapter_limit, chosen_language)
	var backdrop := StyleBoxFlat.new()
	backdrop.bg_color = Color(.012, .03, .05, .97)
	backdrop.set_content_margin_all(18)
	add_theme_stylebox_override("panel", backdrop)


func _ready() -> void:
	name = "Reference"
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	add_child(shell)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	shell.add_child(header)
	var title := Label.new()
	title.text = tr("Reference").to_upper()
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	for entry in [
		[back, "◀", tr("Back"), func(): step(-1)],
		[forward, "▶", tr("Forward"), func(): step(1)],
		[home, tr("Contents"), tr("Contents"), func(): open("home")],
		[browse, tr("Browse"), tr("Browse"), func(): show_list(not showing_list)]
	]:
		var node: Button = entry[0]
		node.text = entry[1]
		node.tooltip_text = entry[2]
		node.custom_minimum_size = Vector2(46, 42)
		node.pressed.connect(entry[3])
		header.add_child(node)
		compact(node)
	# The reference's own writing and labels in any interface language; the
	# game's own text follows when the game includes that language.
	for code: String in EngineLanguage.codes():
		language_menu.add_item(EngineLanguage.native_name(code))
		language_menu.set_item_metadata(language_menu.item_count - 1, code)
		if code == catalog.language:
			language_menu.select(language_menu.item_count - 1)
	language_menu.tooltip_text = tr("Language")
	language_menu.custom_minimum_size = Vector2(140, 42)
	# Its width must not follow the longest name, or a narrow window could
	# not fit the header and would keep laying itself out.
	language_menu.fit_to_longest_item = false
	language_menu.clip_text = true
	language_menu.item_selected.connect(
		func(index): switch_language(str(language_menu.get_item_metadata(index)))
	)
	header.add_child(language_menu)
	compact(language_menu)
	save_button.text = tr("Save as web page")
	save_button.tooltip_text = tr("Write this reference as a web page you can open in a browser.")
	save_button.pressed.connect(save_site)
	header.add_child(save_button)
	compact(save_button)
	close.text = tr("Close")
	close.custom_minimum_size = Vector2(96, 42)
	close.pressed.connect(func(): closed.emit())
	header.add_child(close)
	compact(close)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	shell.add_child(body)
	side.custom_minimum_size.x = 320
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	search.placeholder_text = tr("Search the reference")
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 42
	search.text_changed.connect(searched)
	field(search)
	side.add_child(search)
	name_sections()
	sections.item_selected.connect(
		func(index):
			category = sections.get_item_metadata(index)
			fill_list()
	)
	sections.custom_minimum_size.y = 42
	compact(sections)
	side.add_child(sections)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.add_theme_stylebox_override("panel", box(Color(.03, .07, .1, .8), Color("29404e")))
	side.add_child(list_scroll)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	list_scroll.add_child(rows)
	var helper := TouchScroll.new()
	helper.scroll = list_scroll
	list_scroll.add_child(helper)
	count.add_theme_color_override("font_color", FAINT)
	count.add_theme_font_size_override("font_size", 13)
	side.add_child(count)

	reader.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reader.add_theme_constant_override("separation", 8)
	body.add_child(reader)
	var sheet := PanelContainer.new()
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var paper := box(Color(.027, .058, .088, .96), Color("29404e"))
	paper.content_margin_left = 24
	paper.content_margin_right = 18
	paper.content_margin_top = 16
	paper.content_margin_bottom = 12
	sheet.add_theme_stylebox_override("panel", paper)
	reader.add_child(sheet)
	page_box.add_theme_constant_override("separation", 20)
	sheet.add_child(page_box)
	article.bbcode_enabled = true
	# The article grows with its text and its scroller moves it, so touch
	# drags scroll it like the list.
	article.fit_content = true
	article.scroll_active = false
	article.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article.focus_mode = Control.FOCUS_ALL
	article.selection_enabled = not DisplayServer.is_touchscreen_available()
	for kind in ["normal", "bold", "italics", "bold_italics"]:
		article.add_theme_font_size_override(kind + "_font_size", 17)
	article.add_theme_constant_override("line_separation", 5)
	article.add_theme_color_override("default_color", TEXT)
	article.add_theme_color_override("table_border", Color(LINE, .5))
	article.add_theme_color_override("table_odd_row_bg", Color(.11, .22, .29, .3))
	article.add_theme_color_override("table_even_row_bg", Color(0, 0, 0, 0))
	article.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	article.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(FOCUS, .4)))
	article.meta_clicked.connect(followed)
	article.gui_input.connect(article_keys)
	article_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	article_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	article_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	article_scroll.add_child(article)
	page_box.add_child(article_scroll)
	var article_touch := TouchScroll.new()
	article_touch.scroll = article_scroll
	article_scroll.add_child(article_touch)
	media.followed.connect(open)
	page_box.add_child(media)
	related.custom_minimum_size.y = 42
	related.item_selected.connect(chose_related)
	compact(related)
	reader.add_child(related)
	status.add_theme_color_override("font_color", DIM)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.hide()
	reader.add_child(status)
	resized.connect(arrange)
	fill_list()
	open("home")
	arrange()
	# On a touchscreen a focused search raises the keyboard over the page.
	if not DisplayServer.is_touchscreen_available():
		search.grab_focus.call_deferred()


static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	style.anti_aliasing = true
	return style


## Header buttons and menus keep the theme's look with less padding.
func compact(node: Control) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := box(
			Color("10202f") if state in ["normal", "disabled"] else Color("1d3949"),
			FOCUS if state == "focus" else LINE
		)
		style.content_margin_left = 12
		style.content_margin_right = 12
		node.add_theme_stylebox_override(state, style)
	node.add_theme_font_size_override("font_size", 16)
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_disabled_color", Color("566a79"))


func field(node: LineEdit) -> void:
	node.add_theme_stylebox_override("normal", box(Color("10202f"), LINE))
	node.add_theme_stylebox_override("focus", box(Color("10202f"), FOCUS))
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_placeholder_color", FAINT)
	node.add_theme_font_size_override("font_size", 16)


func searched(_text: String) -> void:
	fill_list()
	if narrow():
		show_list(true)


func followed(meta) -> void:
	var key := WikiHtml.key_from_url(str(meta))
	if not key.is_empty():
		open(key)


func chose_related(index: int) -> void:
	if index > 0:
		open(related.get_item_metadata(index))


func can_save() -> bool:
	return not OS.has_feature("web") and not OS.has_feature("android") and not OS.has_feature("ios")


func narrow() -> bool:
	return size.x < 820


## Room for the picture beside the article rather than above it.
func wide() -> bool:
	return size.x >= 1180 or (size.x >= 980 and size.y < 700)


func arrange() -> void:
	browse.visible = narrow()
	save_button.visible = can_save() and not narrow()
	side.visible = not narrow() or showing_list
	reader.visible = not narrow() or not showing_list
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow() else Control.SIZE_FILL
	page_box.vertical = not wide()
	page_box.move_child(media, 0 if page_box.vertical else 1)
	if page_box.vertical:
		media.custom_minimum_size = Vector2(0, clampf(size.y * .3, 150, 260))
		media.size_flags_vertical = Control.SIZE_FILL
	else:
		media.custom_minimum_size = Vector2(minf(400, size.x * .27), 0)
		media.size_flags_vertical = Control.SIZE_EXPAND_FILL


func name_sections() -> void:
	var picked := sections.selected
	sections.clear()
	sections.add_item(catalog.all_sections())
	sections.set_item_metadata(0, ALL)
	for name_ in Catalog.CATEGORIES:
		sections.add_item(catalog.category_name(name_))
		sections.set_item_metadata(sections.item_count - 1, name_)
	if picked >= 0:
		sections.select(picked)


## Rebuilds the reference in another language and stays on the same page.
func switch_language(code: String) -> void:
	if code == catalog.language:
		return
	chosen_language = code
	catalog = Catalog.new(library, chapter_limit, code)
	name_sections()
	fill_list()
	if cursor >= 0 and cursor < history.size():
		open(history[cursor], false)


func show_list(visible_: bool) -> void:
	showing_list = visible_
	arrange()
	if showing_list and rows.get_child_count() > 0:
		(rows.get_child(0) as Control).grab_focus.call_deferred()


## Rank like the exported reader: whole title, title start, inside the title,
## then every word starting a word of the title or subtitle.
static func score(query: String, title: String, words: String) -> int:
	var name_ := title.to_lower()
	if name_ == query:
		return 1000
	if name_.begins_with(query):
		return 800
	if query in name_:
		return 600
	var starts := " " + RegEx.create_from_string("[^\\p{L}\\p{N}]+").sub(words.to_lower(), " ", true)
	for word in query.split(" ", false):
		if not (" " + word) in starts:
			return -1
	return 300


func fill_list() -> void:
	var query := search.text.strip_edges().to_lower().replace("ё", "е")
	var ranked: Array = []
	for key: String in catalog.ordered:
		var entry: Dictionary = catalog.entries[key]
		if entry.category.is_empty():
			continue
		if query.is_empty():
			if category == ALL or entry.category == category:
				ranked.append([0, key])
		else:
			var value := score(query, str(entry.title).replace("ё", "е"), catalog.search_text(key).replace("ё", "е"))
			if value >= 0:
				ranked.append([value, key])
	var order: Array = Catalog.CATEGORIES
	if not query.is_empty():
		ranked.sort_custom(
			func(x, y):
				return x[0] > y[0] or (x[0] == y[0] and str(catalog.entries[x[1]].title).naturalnocasecmp_to(catalog.entries[y[1]].title) < 0)
		)
	else:
		ranked.sort_custom(
			func(x, y):
				var cx: int = order.find(catalog.entries[x[1]].category)
				var cy: int = order.find(catalog.entries[y[1]].category)
				if cx != cy:
					return cx < cy
				if catalog.entries[x[1]].category in ["story", "galaxy"]:
					return catalog.ordered.find(x[1]) < catalog.ordered.find(y[1])
				return str(catalog.entries[x[1]].title).naturalnocasecmp_to(catalog.entries[y[1]].title) < 0
		)
	listed = ranked.map(func(row): return row[1])
	for child in rows.get_children():
		if child is Button or child is Label:
			rows.remove_child(child)
			child.queue_free()
	var shown_category := ""
	for key: String in listed.slice(0, ROWS):
		var entry: Dictionary = catalog.entries[key]
		if query.is_empty() and category == ALL and entry.category != shown_category:
			shown_category = entry.category
			var heading := Label.new()
			heading.text = "  " + catalog.category_name(shown_category).to_upper()
			heading.add_theme_color_override("font_color", ACCENT)
			heading.add_theme_font_size_override("font_size", 12)
			rows.add_child(heading)
		rows.add_child(row(key, entry, not query.is_empty() or category == ALL))
	count.text = (
		tr("%d pages") % listed.size()
		if listed.size() <= ROWS
		else tr("%d of %d pages; search to find the rest") % [ROWS, listed.size()]
	)
	mark_current()


func row(key: String, entry: Dictionary, with_section: bool) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, 46)
	button.set_meta("key", key)
	button.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "focus", "pressed", "hover_pressed"]:
		var lit: bool = state != "normal"
		var look := box(
			Color("1d3949") if state in ["pressed", "hover_pressed"] else (Color(.11, .22, .29, .5) if lit else Color(0, 0, 0, 0)),
			FOCUS if state in ["focus", "pressed", "hover_pressed"] else (LINE if lit else Color(0, 0, 0, 0))
		)
		look.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, look)
	button.pressed.connect(func(): open(key))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 6
	line.offset_right = -6
	button.add_child(line)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(44, 34)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb.texture = catalog.icon(key).get("texture")
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(thumb)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	var name_ := Label.new()
	name_.text = entry.title
	name_.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_.add_theme_color_override("font_color", TEXT)
	name_.add_theme_font_size_override("font_size", 16)
	name_.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(name_)
	var detail := str(entry.subtitle)
	if with_section and detail.is_empty():
		detail = catalog.category_name(entry.category)
	if not detail.is_empty():
		var note := Label.new()
		note.text = detail
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		note.add_theme_color_override("font_color", FAINT)
		note.add_theme_font_size_override("font_size", 12)
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		words.add_child(note)
	return button


func mark_current() -> void:
	var current := history[cursor] if cursor >= 0 and cursor < history.size() else ""
	for child in rows.get_children():
		if child is Button:
			child.set_pressed_no_signal(child.get_meta("key") == current)


func open(key: String, remember := true) -> void:
	if not catalog.entries.has(key):
		return
	if remember:
		history.resize(cursor + 1)
		history.append(key)
		cursor = history.size() - 1
	var html := catalog.page(key)
	article.text = WikiHtml.to_bbcode(html, ACCENT, DIM)
	article_scroll.scroll_vertical = 0
	media.visible = media.show_media(catalog.media(key), catalog)
	related.clear()
	related.add_item(tr("Linked pages"))
	for target in WikiHtml.links(html):
		if target == key or not catalog.entries.has(target):
			continue
		related.add_item(catalog.entries[target].title)
		related.set_item_metadata(related.item_count - 1, target)
	related.select(0)
	related.disabled = related.item_count < 2
	back.disabled = cursor <= 0
	forward.disabled = cursor >= history.size() - 1
	mark_current()
	reveal.call_deferred(key)
	if narrow():
		show_list(false)


## Scrolls the list to the open page's row, once the list is laid out.
func reveal(key: String) -> void:
	for child in rows.get_children():
		if child is Button and child.get_meta("key") == key and list_scroll.is_ancestor_of(child):
			list_scroll.ensure_control_visible(child)


func step(delta: int) -> void:
	var target := cursor + delta
	if target < 0 or target >= history.size():
		return
	cursor = target
	open(history[cursor], false)


func save_site() -> void:
	var directory := OS.get_user_data_dir().path_join("reference").path_join(str(library.id).left(16))
	status.show()
	status.text = tr("Writing the web page…")
	save_button.disabled = true
	await get_tree().process_frame
	var renders := {}
	var camera = preload("res://src/wiki/wiki_snapshots.gd").new()
	if camera.available():
		add_child(camera)
		camera.progressed.connect(func(done, total): status.text = tr("Drawing pictures: %d of %d") % [done, total])
		renders = await camera.render(catalog, directory)
		camera.queue_free()
	var result := WikiExport.write(catalog, directory, renders, EngineLanguage.codes())
	save_button.disabled = false
	if result != OK:
		status.text = tr("Could not write the web page: %s") % error_string(result)
		return
	status.text = tr("Saved to %s") % directory
	OS.shell_open(directory.path_join("index.html"))


## A controller reads with the right stick, whatever has focus, and LB / RB
## go back and forward like Alt+Left / Alt+Right.
const STICK_DEADZONE := 0.2
const STICK_SPEED := 900.0
var stick_tilt := 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_RIGHT_Y:
		stick_tilt = event.axis_value


func _process(delta: float) -> void:
	if not is_visible_in_tree() or absf(stick_tilt) <= STICK_DEADZONE:
		return
	var bar := article_scroll.get_v_scroll_bar()
	bar.value += signf(stick_tilt) * (absf(stick_tilt) - STICK_DEADZONE) / (1.0 - STICK_DEADZONE) * STICK_SPEED * delta


## Up and down scroll a focused article; at its end they move on, so the
## linked pages and the list stay reachable without a pointer.
func article_keys(event: InputEvent) -> void:
	var bar := article_scroll.get_v_scroll_bar()
	if event.is_action_pressed("ui_down"):
		if bar.value >= bar.max_value - bar.page - 1.0 and related.visible:
			related.grab_focus()
		else:
			bar.value += 60
		article.accept_event()
	elif event.is_action_pressed("ui_up") and bar.value > 0.0:
		bar.value -= 60
		article.accept_event()
	elif event.is_action_pressed("ui_up"):
		var previous := article.find_prev_valid_focus()
		if previous != null:
			previous.grab_focus()
			article.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if (
		event is InputEventJoypadButton
		and event.pressed
		and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
	):
		step(-1 if event.button_index == JOY_BUTTON_LEFT_SHOULDER else 1)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.alt_pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		step(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
