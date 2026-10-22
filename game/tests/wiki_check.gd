extends SceneTree
## Checks the reference against an imported game:
##   godot-4 --headless --path game --script tests/wiki_check.gd -- /private/path/game.ipa
## (or the imported content folder instead of the IPA). Every page of every
## language renders as well-formed HTML, every link leads to a page, story
## pages stop at the chapter limit, and the reader and the web export work.
const Importer = preload("res://src/content/ipa_import.gd")
const Library = preload("res://src/content/library.gd")
const Catalog = preload("res://src/wiki/wiki_catalog.gd")
const WikiHtml = preload("res://src/wiki/wiki_html.gd")
const WikiProse = preload("res://src/wiki/wiki_prose.gd")
const WikiPanel = preload("res://src/wiki/wiki_panel.gd")
const WikiExport = preload("res://src/wiki/wiki_export.gd")
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
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
	if args.is_empty():
		printerr("Supply a private IPA or imported content folder after --")
		quit(2)
		return
	var lib := Library.new()
	var source: String = args[0]
	if source.get_extension().to_lower() == "ipa":
		var importer := Importer.new()
		importer.cache_base = "user://test-content"
		check(await importer.install(source, self), "IPA import: " + importer.error)
		check(lib.open(importer.root, importer.content_id), "Open imported content: " + lib.error)
	else:
		check(lib.open(source, source.get_file()), "Open imported content: " + lib.error)
	if failures:
		quit(1)
		return
	check_prose()
	for code: String in EngineLanguage.codes():
		check_catalog(Catalog.new(lib, -1, code), code)
	check_spoilers(lib)
	await check_panel(lib)
	check_export(lib)
	print("WIKI CHECKS %d | FAILURES %d" % [checks, failures])
	quit(1 if failures else 0)


## Every translation has the English pages' blocks, with the same chapter
## gates and the same link tokens.
func check_prose() -> void:
	var english = WikiProse.source("en")
	check(english != null, "English prose loads")
	for code: String in EngineLanguage.codes():
		var local = WikiProse.source(code)
		if local == null or code == "en":
			continue
		for key: String in local.BLOCKS:
			var theirs: Array = local.BLOCKS[key]
			var ours: Array = english.BLOCKS.get(key, [])
			var same := theirs.size() == ours.size()
			for index in mini(theirs.size(), ours.size()):
				same = (
					same
					and int(theirs[index][0]) == int(ours[index][0])
					and bool(theirs[index][3]) == bool(ours[index][3])
					and token_keys(str(theirs[index][2])) == token_keys(str(ours[index][2]))
				)
			check(same, "%s prose for %s matches the English blocks and links" % [code, key])
		for key: String in local.PAGES:
			check(english.PAGES.has(key), "%s prose page %s exists in English" % [code, key])


func token_keys(value: String) -> Array:
	var keys: Array = WikiProse.tokens(value).map(func(token): return token[1])
	keys.sort()
	return keys


func check_catalog(catalog: Catalog, code: String) -> void:
	var broken: Array = []
	var malformed: Array = []
	var untitled: Array = []
	for key: String in catalog.ordered:
		var html := catalog.page(key)
		var parser := XMLParser.new()
		var ok := parser.open_buffer(("<div>" + html + "</div>").to_utf8_buffer()) == OK
		while ok:
			var result := parser.read()
			if result == ERR_FILE_EOF:
				break
			ok = result == OK
		if not ok:
			malformed.append(key)
		for target in WikiHtml.links(html):
			if not catalog.entries.has(target):
				broken.append("%s -> %s" % [key, target])
		if str(catalog.entries[key].title).strip_edges().is_empty():
			untitled.append(key)
		if WikiHtml.to_bbcode(html, Color.WHITE, Color.GRAY).is_empty():
			malformed.append(key + " (no rich text)")
	check(malformed.is_empty(), "%s pages are well-formed: %s" % [code, str(malformed.slice(0, 8))])
	check(broken.is_empty(), "%s links lead to pages: %s" % [code, str(broken.slice(0, 8))])
	check(untitled.is_empty(), "%s pages have titles: %s" % [code, str(untitled)])
	check(catalog.ordered.size() > 700, "%s reference covers the galaxy (%d pages)" % [code, catalog.ordered.size()])
	for category: String in Catalog.CATEGORIES:
		check(
			catalog.ordered.any(func(key): return catalog.entries[key].category == category),
			"%s section %s has pages" % [code, category]
		)
	for key in ["station/0", "ship/0", "equipment/0", "goods/15", "character/1", "race/0"]:
		check(not catalog.icon(key).is_empty(), "%s %s has an icon" % [code, key])
		check(not catalog.media(key).is_empty(), "%s %s has a picture" % [code, key])


func check_spoilers(lib) -> void:
	var start := Catalog.new(lib, 1, "en")
	check(start.entries.has("chapter/1") and not start.entries.has("chapter/2"), "A new pilot sees only the first chapter")
	check(not start.entries.has("character/2"), "Characters not yet met stay hidden")
	check(not "Outcome" in start.page("chapter/1"), "An unfinished chapter hides its outcome")
	var radio := start.page("dialogue/1")
	check(not lib.text(int(lib.mission_definition(0).radio[0].text)) in radio, "An unfinished chapter hides its radio calls")
	check(start.character_name(4) != start.prose.pages["character/4"].title, "A character is named only once the story names them")
	var second := Catalog.new(lib, 2, "en")
	check("Outcome" in second.page("chapter/1"), "A finished chapter shows its outcome")
	var all := 0
	var full := Catalog.new(lib, -1, "en")
	for key: String in full.ordered:
		if key.begins_with("chapter/"):
			all += 1
	check(all == lib.content.chapters.size() and full.complete(), "A complete campaign shows every chapter")
	for key: String in start.ordered:
		var html := start.page(key)
		for chapter in range(2, lib.content.chapters.size() + 1):
			if "wiki://chapter/%d\"" % chapter in html or "wiki://dialogue/%d\"" % chapter in html:
				check(false, "%s links a hidden chapter %d" % [key, chapter])
				return
	check(true, "No page links a chapter beyond the save")
	var rich := Catalog.new(lib, -1, "en")
	var threshold := Catalog.grouped(int(lib.content.station_ui.shop_credit_threshold) + 1)
	var closed := -1
	for id in lib.stations.size():
		if not lib.station_definition(id).shop:
			closed = id
			break
	check(closed >= 0 and threshold in rich.page("station/%d" % closed), "A place without trade explains the high-credit hangar")


func check_panel(lib) -> void:
	var panel: WikiPanel = WikiPanel.new()
	panel.configure(lib, 3)
	root.add_child(panel)
	panel.size = Vector2(1280, 720)
	await process_frame
	await process_frame
	check(panel.history == ["home"], "The reader opens on the contents")
	check(panel.listed.size() > 650, "The reader lists the pages (%d)" % panel.listed.size())
	panel.open("station/0")
	check(panel.article.text.contains(lib.station_name(0)), "The reader shows a station page")
	panel.open("ship/0")
	await process_frame
	check(panel.media.visible, "A ship page shows its picture")
	panel.step(-1)
	check(panel.history[panel.cursor] == "station/0", "Back returns to the previous page")
	panel.search.text = lib.station_name(1)
	panel.fill_list()
	check(not panel.listed.is_empty() and panel.listed[0] == "station/1", "Search finds a station by name")
	panel.switch_language("de")
	check(panel.catalog.language == "de" and panel.history[panel.cursor] == "station/0", "Switching language keeps the page (%s, %s)" % [panel.catalog.language, panel.history[panel.cursor]])
	WikiPanel.chosen_language = ""
	panel.size = Vector2(600, 900)
	await process_frame
	check(panel.narrow(), "A narrow screen takes the narrow layout")
	panel.queue_free()
	await process_frame


func check_export(lib) -> void:
	var directory := OS.get_user_data_dir().path_join("wiki-check-export")
	var catalog := Catalog.new(lib, -1, "en")
	check(WikiExport.write(catalog, directory, {}, ["en", "de"]) == OK, "The web export writes")
	for name in ["index.html", "wiki.css", "wiki.js", "languages.js", "content-en.js", "content-de.js"]:
		check(FileAccess.file_exists(directory.path_join(name)), "The web export has " + name)
	check(FileAccess.file_exists(directory.path_join("images/ui-%d-%d.png" % [int(lib.content.hangar_ui.pictures.ship_icons[0].texture), int(lib.content.hangar_ui.pictures.ship_icons[0].region)])), "The web export writes imported pictures")
	var content := FileAccess.get_file_as_string(directory.path_join("content-en.js"))
	check(content.contains(JSON.stringify("station/499")), "The web export holds every page")
