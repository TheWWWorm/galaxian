extends RefCounted
## The reference: articles about the player's own imported Galaxy on Fire.
## Nothing is bundled. Every name, description and line of dialogue comes
## from the supplied game's language files, and the figures come from the
## same rules the simulation uses. Keys are language-independent navigation
## tokens ("station/12"); only imported names and engine text reach a page.
##
## The reference's own writing (WikiProse) explains the galaxy, the rules and
## the story around those facts in the reader's language; it names things
## only through link tokens, so a translated game's names appear in it.
##
## Pages are small, well-formed HTML fragments: h1, h2, p, ul, li, table (with
## data-columns), tr, th, td, strong, em, br and wiki:// links. The in-game
## reader turns them into rich text and shows each page's picture beside it;
## the web export shows them as they are. Imported text is always escaped.
##
## Story pages stop at a chapter limit, so a player is not shown what lies
## ahead of their save: chapters not yet offered and characters not yet met
## stay out of every page, and a chapter's radio log and outcome appear once
## it is finished.
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
const WikiProse = preload("res://src/wiki/wiki_prose.gd")
const Market = preload("res://src/simulation/market.gd")

const CATEGORIES := [
	"world", "story", "characters", "races", "galaxy", "stations", "ships", "equipment",
	"goods", "jobs", "progress", "modes", "guide"
]
const TECHNOLOGY_LEVELS := 10

var library
## The imported text in the reference's language when the game has it, in
## the game's current language otherwise.
var strings := PackedStringArray()
var text_language := "en"
var entries := {}
var ordered: Array[String] = []
var chapters := 0
## Chapters offered so far (1 to chapters + 1). A chapter below it is
## finished; chapters + 1 means the campaign is complete.
var limit := 0
var prose: WikiProse
var language := "en"
## Character -> [chapter of first appearance, chapters in which they speak].
var cast := {}


func _init(source, chapter_limit := -1, code := "") -> void:
	library = source
	language = code if code in EngineLanguage.codes() else EngineLanguage.current
	prose = WikiProse.new(language)
	chapters = library.content.chapters.size()
	limit = chapters + 1 if chapter_limit < 0 else clampi(chapter_limit, 1, chapters + 1)
	var file := "gb" if language == "en" else language
	strings = library.strings
	text_language = EngineLanguage.game_code(library.language_code)
	if file != library.language_code and file in library.available_languages():
		var found: PackedStringArray = library.reader.language(library.read(file + ".lang"))
		if found.size() == library.strings.size():
			strings = found
			text_language = language
	gather_cast()
	rebuild()


## Engine text in the reference's language, whatever the interface uses.
func translate(text_: String) -> String:
	return EngineLanguage.text_in(language, text_)


func all_sections() -> String:
	return translate("All sections")


## Whether the imported descriptions and dialogue are in the reader's language.
func game_speaks() -> bool:
	return text_language == language


func complete() -> bool:
	return limit > chapters


func finished(chapter: int) -> bool:
	return chapter < limit


# --- names ----------------------------------------------------------------


func text(id: int) -> String:
	return strings[id] if id >= 0 and id < strings.size() else ""


func bound(binding: Dictionary, index: int) -> String:
	return text(int(binding.base + index * binding.stride))


func ship_name(id: int) -> String:
	return bound(library.content.localization.ships, id)


func item_name(id: int) -> String:
	return bound(library.content.localization.items, id)


func station_name(id: int) -> String:
	return library.station_name(id)


func system_name(id: int) -> String:
	return str(library.systems[id][0])


func quadrant_name(id: int) -> String:
	return str(library.quadrants[id][0])


func race_name(race: int) -> String:
	var races: Array = library.content.map_ui.races
	return text(int(races[race])) if race >= 0 and race < races.size() else "?"


func category_label(category: int) -> String:
	return text(int(library.content.hangar_ui.labels.category_base) + category)


func map_label(key: String) -> String:
	return text(int(library.content.map_ui.labels[key]))


func board_label(key: String) -> String:
	return text(int(library.content.board_ui.labels[key]))


func status_label(key: String) -> String:
	return text(int(library.content.station_ui.status.labels[key]))


func hangar_label(key: String) -> String:
	return text(int(library.content.hangar_ui.labels[key]))


func chapter_title(chapter: int) -> String:
	var info: Dictionary = prose.pages.get("chapter/%d" % chapter, {})
	return str(info.get("title", translate("Chapter %d") % chapter))


## A character's name, or how they are known before the story names them.
func character_name(id: int) -> String:
	var info: Dictionary = prose.pages.get("character/%d" % id, {})
	if info.has("early_title") and limit < int(info.get("named_from", 1)):
		return str(info.early_title)
	return str(info.get("title", translate("Speaker %d") % id))


func contract_name(kind: int) -> String:
	return text(int(library.content.contracts.types[kind].title))


func category_name(category: String) -> String:
	match category:
		"world": return translate("World")
		"story": return translate("Story")
		"characters": return translate("Characters")
		"races": return translate("Races")
		"galaxy": return translate("Galaxy")
		"stations": return translate("Planets and stations")
		"ships": return translate("Ships")
		"equipment": return translate("Equipment")
		"goods": return translate("Goods")
		"jobs": return translate("Jobs")
		"progress": return translate("Progress")
		"modes": return translate("Game modes")
		"guide": return translate("Guide")
	return category


# --- campaign -------------------------------------------------------------


## Who speaks where. A briefing introduces its speakers when the chapter is
## offered; radio calls only once the chapter is flown.
func gather_cast() -> void:
	cast.clear()
	var protagonist := int(library.content.briefing_ui.protagonist)
	for index in chapters:
		var chapter := index + 1
		for page in library.content.chapters[index].dialogue.size():
			var speaker := int(library.briefing_cue(index, page).speaker)
			if speaker >= 0:
				meet(speaker, chapter, chapter)
		for cue in library.mission_definition(index).get("radio", []):
			meet(int(cue.speaker), chapter + 1, chapter)
	if not cast.has(protagonist):
		meet(protagonist, 1, 1)


func meet(speaker: int, from: int, chapter: int) -> void:
	if not cast.has(speaker):
		cast[speaker] = [from, []]
	cast[speaker][0] = mini(int(cast[speaker][0]), from)
	if not chapter in cast[speaker][1]:
		cast[speaker][1].append(chapter)


## The chapters a character speaks in that the save may show.
func appearances(speaker: int) -> Array:
	if not cast.has(speaker) or int(cast[speaker][0]) > limit:
		return []
	var result: Array = []
	for chapter in cast[speaker][1]:
		if chapter < limit or (chapter == limit and speaks_in_briefing(speaker, chapter)):
			result.append(chapter)
	result.sort()
	return result


func speaks_in_briefing(speaker: int, chapter: int) -> bool:
	for page in library.content.chapters[chapter - 1].dialogue.size():
		if int(library.briefing_cue(chapter - 1, page).speaker) == speaker:
			return true
	return false


func chapter_station(chapter: int) -> int:
	return library.chapter_destination(chapter - 1)


# --- registry -------------------------------------------------------------


func add(key: String, title: String, category: String, subtitle := "") -> void:
	entries[key] = {"key": key, "title": title, "category": category, "subtitle": subtitle}
	ordered.append(key)


func rebuild() -> void:
	entries.clear()
	ordered.clear()
	add("home", translate("Reference"), "")
	for chapter in range(1, mini(limit, chapters) + 1):
		add("chapter/%d" % chapter, chapter_title(chapter), "story", translate("Chapter %d") % chapter)
	for chapter in range(1, mini(limit, chapters) + 1):
		add(
			"dialogue/%d" % chapter,
			translate("Dialogue: %s") % chapter_title(chapter),
			"",
			translate("Chapter %d") % chapter
		)
	var speakers: Array = cast.keys()
	speakers.sort()
	for speaker in speakers:
		if not appearances(speaker).is_empty():
			var info: Dictionary = prose.pages.get("character/%d" % speaker, {})
			add(
				"character/%d" % speaker,
				character_name(speaker),
				"characters",
				str(info.get("subtitle", ""))
			)
	for race in library.content.map_ui.races.size():
		add("race/%d" % race, race_name(race), "races", translate("%d planets and stations") % race_places(race).size())
	add("galaxy", translate("Galaxy map"), "galaxy", translate("%d planets and stations") % library.stations.size())
	for quadrant in library.quadrants.size():
		add("quadrant/%d" % quadrant, quadrant_name(quadrant), "galaxy", translate("Quadrant %d") % (quadrant + 1))
	for system in library.systems.size():
		add(
			"system/%d" % system,
			system_name(system),
			"galaxy",
			"%s · %s" % [translate("System"), quadrant_name(system_quadrant(system))]
		)
	for id in library.stations.size():
		var station: Dictionary = library.station_definition(id)
		add(
			"station/%d" % id,
			station_name(id),
			"stations",
			"%s · %s · %s" % [place_kind(id), race_name(station.race), system_name(station.system)]
		)
	for id in library.ships.size():
		var ship: Dictionary = library.ship_definition(id)
		add("ship/%d" % id, ship_name(id), "ships", translate("%d hull · %d cargo") % [ship.hull, ship.capacity])
	for id in library.items.size():
		var item: Dictionary = library.equipment(id)
		if item.category == library.CARGO_CATEGORY:
			add("goods/%d" % id, item_name(id), "goods", category_label(item.category))
		else:
			add("equipment/%d" % id, item_name(id), "equipment", category_label(item.category))
	for kind in library.content.contracts.types.size():
		add("job/%d" % kind, contract_name(kind), "jobs")
	var menu: Dictionary = library.content.survival.menu
	add("mode/survival", text(int(menu.title)), "modes", translate("Game mode"))
	for key: String in prose.pages:
		var info: Dictionary = prose.pages[key]
		if entries.has(key) or not info.has("category") or int(info.get("from", 1)) > limit:
			continue
		add(key, str(info.title), str(info.category), str(info.get("subtitle", "")))
	for category: String in CATEGORIES:
		add("section/" + category, category_name(category), "")


func page(key: String) -> String:
	if not entries.has(key):
		return h1(translate("Not found")) + p(esc(translate("There is no such page in this reference.")))
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	match parts[0]:
		"home": return home_page()
		"chapter": return chapter_page(id)
		"dialogue": return dialogue_page(id)
		"character": return character_page(id)
		"race": return race_page(id)
		"galaxy": return galaxy_page()
		"quadrant": return quadrant_page(id)
		"system": return system_page(id)
		"station": return station_page(id)
		"ship": return ship_page(id)
		"equipment": return equipment_page(id)
		"goods": return goods_page(id)
		"job": return job_page(id)
		"section": return section_page(parts[1])
		"progress":
			if parts[1] == "ranks": return ranks_page()
			if parts[1] == "milestones": return milestones_page()
		"mode":
			return mode_page(parts[1])
		"guide":
			if parts[1] == "tips": return tips_page()
	return h1(entries[key].title, entries[key].subtitle) + prose_html(key)


## A page's own words for search: its title and subtitle.
func search_text(key: String) -> String:
	var entry: Dictionary = entries[key]
	return "%s %s" % [entry.title, entry.subtitle]


# --- pictures -------------------------------------------------------------


## A picture of the imported art: {"name", "texture"}, or {} for none.
func art(binding: Variant) -> Dictionary:
	if not binding is Dictionary or not binding.has_all(["texture", "region"]):
		return {}
	return {
		"name": "ui-%d-%d" % [int(binding.texture), int(binding.region)],
		"texture": library.ui_image(binding)
	}


func portrait(speaker: int) -> Dictionary:
	var portraits: Array = library.content.radio_ui.portraits
	return art(portraits[speaker]) if speaker >= 0 and speaker < portraits.size() else {}


## The small picture beside a page in the list.
func icon(key: String) -> Dictionary:
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	var pictures: Dictionary = library.content.hangar_ui.pictures
	match parts[0]:
		"station": return art(library.station_map_icon_binding(id))
		"ship": return art(pictures.ship_icons[id])
		"equipment", "goods": return art(pictures.item_icons[id])
		"character": return portrait(id)
		"race":
			var place := race_places(id)
			return art(library.station_map_icon_binding(place[0])) if not place.is_empty() else {}
	return {}


## The page's large picture. "picture" is imported art; "model" names a
## ship model shown turning; "chart" marks the galaxy map, with "station"
## and "quadrant" for what it highlights.
func media(key: String) -> Dictionary:
	var parts := key.split("/")
	var id := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else -1
	var pictures: Dictionary = library.content.hangar_ui.pictures
	match parts[0]:
		"station":
			return {"picture": art(library.station_preview_binding(id)), "chart": true, "station": id}
		"system":
			return {"chart": true, "system": id}
		"quadrant":
			return {"chart": true, "quadrant": id}
		"galaxy":
			return {"chart": true}
		"ship":
			return {"picture": art(pictures.ship_previews[id]), "model": library.ship_model(id)}
		"equipment", "goods":
			return {"picture": art(pictures.item_previews[id])}
		"character":
			return {"picture": portrait(id)}
		"race":
			var place := race_places(id)
			return {"picture": art(library.station_preview_binding(place[0]))} if not place.is_empty() else {}
		"chapter":
			var station := chapter_station(id)
			return {"chart": true, "station": station} if station >= 0 else {}
	return {}


## Every place on the galaxy map: [x, y, race, shop] in map units, for the
## chart and the web export's drawing of it.
func chart_points() -> Array:
	var result: Array = []
	for id in library.stations.size():
		var station: Dictionary = library.station_definition(id)
		var at: Vector2 = library.galaxy_position(id)
		result.append([int(at.x), int(at.y), int(station.race), 1 if station.shop else 0])
	return result


func chart_extent() -> Vector2:
	var grid: Dictionary = library.content.map_ui.grid
	var rows := ceili(float(library.quadrants.size()) / float(grid.quadrant_columns))
	return Vector2(float(grid.quadrant_columns), rows) * float(grid.quadrant_extent)


# --- HTML -----------------------------------------------------------------


static func esc(value: String) -> String:
	return (
		value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
		.replace("\"", "&quot;").replace("\n", "<br/>")
	)


func a(key: String, words := "") -> String:
	if not entries.has(key):
		return esc(words)
	return "<a href=\"wiki://%s\">%s</a>" % [key, esc(words if not words.is_empty() else entries[key].title)]


func chapter_link(chapter: int) -> String:
	return a("chapter/%d" % chapter) if chapter <= limit and chapter <= chapters else esc(translate("a later chapter"))


func h1(title: String, subtitle := "") -> String:
	return "<h1>%s</h1>" % esc(title) + (p("<em>%s</em>" % esc(subtitle)) if not subtitle.is_empty() else "")


func h2(title: String) -> String:
	return "<h2>%s</h2>" % esc(title)


func p(html: String) -> String:
	return "<p>%s</p>" % html


func bullets(items: Array) -> String:
	return "<ul><li>" + "</li><li>".join(items) + "</li></ul>" if not items.is_empty() else ""


## Rows of [label, html] as a two-column table.
func facts(rows: Array) -> String:
	var out := "<table data-columns=\"2\">"
	for row: Array in rows:
		out += "<tr><th>%s</th><td>%s</td></tr>" % [esc(row[0]), row[1]]
	return out + "</table>"


## A table with a header row; cells are already HTML.
func grid(header: Array, rows: Array) -> String:
	if rows.is_empty():
		return ""
	var out := "<table data-columns=\"%d\"><tr>" % header.size()
	for cell in header:
		out += "<th>%s</th>" % esc(cell)
	out += "</tr>"
	for row: Array in rows:
		out += "<tr>"
		for cell in row:
			out += "<td>%s</td>" % str(cell)
		out += "</tr>"
	return out + "</table>"


func links(keys: Array) -> String:
	var parts := PackedStringArray()
	for key in keys:
		if entries.has(key):
			parts.append(a(key))
	return ", ".join(parts) if not parts.is_empty() else esc(translate("None"))


func money(value: int) -> String:
	return esc(translate("%s cr") % grouped(value))


static func grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0 else "") + digits + out


## A line of imported text, in italics, with a note when it is not in the
## reader's language.
func quoted(id: int) -> String:
	var value := text(id).strip_edges()
	return p("<em>%s</em>" % esc(value)) if not value.is_empty() else ""


## The page's own prose a save at this chapter may read, as HTML.
func prose_html(key: String) -> String:
	var out := ""
	var items: Array = []
	# Like any wiki, a name is a link where it first appears, plain text after.
	var named := {key: true}
	for block: Array in prose.visible(key, limit):
		var heading := str(block[1])
		if (not block[3] or not heading.is_empty()) and not items.is_empty():
			out += bullets(items)
			items = []
		if not heading.is_empty():
			out += h2(heading)
		if block[3]:
			items.append(linked(str(block[2]), named))
		else:
			out += p(linked(str(block[2]), named))
	return out + bullets(items)


## Prose text with its [[key]] tokens as links. A page the save may not see
## yet keeps the token's own words, or is left unnamed.
func linked(value: String, named := {}) -> String:
	var out := ""
	var at := 0
	for found in WikiProse.TOKEN.search_all(value):
		out += esc(value.substr(at, found.get_start() - at))
		var key := found.get_string(1)
		var words := found.get_string(2)
		if entries.has(key):
			var title := str(entries[key].title)
			if key.begins_with("chapter/"):
				title = translate("Chapter %d") % int(key.get_slice("/", 1))
			var shown := esc(words if not words.is_empty() else title)
			out += shown if named.has(key) else "<a href=\"wiki://%s\">%s</a>" % [key, shown]
			named[key] = true
		elif not words.is_empty():
			out += esc(words)
		elif key.begins_with("chapter/"):
			out += esc(translate("a later chapter"))
		at = found.get_end()
	return out + esc(value.substr(at))


func language_note() -> String:
	if game_speaks():
		return ""
	return p("<em>%s</em>" % esc(translate("The game's own text is shown in %s; the game does not include this language.") % EngineLanguage.native_name(text_language)))


# --- rules ----------------------------------------------------------------


func system_quadrant(system: int) -> int:
	return system / (library.systems.size() / library.quadrants.size())


func system_places(system: int) -> Array:
	var per_system: int = library.stations.size() / library.systems.size()
	return range(system * per_system, (system + 1) * per_system)


func quadrant_systems(quadrant: int) -> Array:
	var per_quadrant: int = library.systems.size() / library.quadrants.size()
	return range(quadrant * per_quadrant, (quadrant + 1) * per_quadrant)


func race_places(race: int) -> Array:
	var result: Array = []
	for id in library.stations.size():
		if int(library.station_definition(id).race) == race:
			result.append(id)
	return result


func place_kind(id: int) -> String:
	return translate("Planet") if library.station_definition(id).planet else translate("Station")


func yes_no(value: bool) -> String:
	return esc(map_label("yes" if value else "no"))


func campaign_chapters_at(station: int) -> Array:
	var result: Array = []
	for chapter in range(1, mini(limit, chapters) + 1):
		if chapter_station(chapter) == station:
			result.append(chapter)
	return result


## Chapters whose campaign shop sells an item, as far as the save reaches.
func stocked_in(item: int) -> Array:
	var result: Array = []
	for chapter in range(1, mini(limit, chapters) + 1):
		if library.content.chapters[chapter - 1].stock.any(func(v): return int(v) == item):
			result.append(chapter)
	return result


## Why a ship is or is not sold at a race's stations (Market.generate).
func ship_sold_by(id: int) -> String:
	var rules: Dictionary = library.content.economy
	var actor := int(library.ship_definition(id).actor)
	if actor == int(rules.exclusive_ship_actor):
		return esc(translate("Only at %s shops.") % race_name(int(rules.exclusive_ship_race)))
	if actor == int(rules.restricted_ship_actor):
		return esc(translate("Only at %s shops.") % race_name(int(rules.restricted_ship_race)))
	return esc(translate("At every shop except %s ones.") % race_name(int(rules.exclusive_ship_race)))


func item_sold_by(id: int) -> String:
	var rules: Dictionary = library.content.economy
	if id > int(rules.exclusive_equipment_after):
		return esc(translate("Only at %s shops.") % race_name(int(rules.exclusive_equipment_race)))
	return esc(translate("At any shop in its quadrant or beyond."))


func quadrant_from(quadrant: int) -> String:
	return a("quadrant/%d" % quadrant)


# --- pages ----------------------------------------------------------------


func home_page() -> String:
	var out := h1(translate("Reference"), translate("Galaxy on Fire"))
	out += prose_html("home")
	var rows: Array = []
	for category: String in CATEGORIES:
		var count := ordered.filter(func(key): return entries[key].category == category).size()
		if count > 0:
			rows.append([a("section/" + category), esc(str(count))])
	out += grid([translate("Section"), translate("Pages")], rows)
	if not complete():
		out += p("<em>%s</em>" % esc(translate("The story stops at chapter %d, where your pilot is; later chapters stay hidden.") % limit))
	return out


func section_page(category: String) -> String:
	var out := h1(category_name(category), translate("Section"))
	out += prose_html("intro/" + category)
	var keys: Array = ordered.filter(func(key): return entries[key].category == category)
	if not category in ["story", "galaxy"]:
		keys.sort_custom(func(x, y): return str(entries[x].title).naturalnocasecmp_to(entries[y].title) < 0)
	return out + grid(
		[translate("Page"), translate("Details")],
		keys.map(func(key): return [a(key), esc(str(entries[key].subtitle))])
	)


func chapter_page(chapter: int) -> String:
	var index := chapter - 1
	var data: Dictionary = library.content.chapters[index]
	var out := h1(chapter_title(chapter), translate("Chapter %d") % chapter)
	var rows: Array = []
	var station := chapter_station(chapter)
	if station >= 0:
		rows.append([translate("Destination"), a("station/%d" % station)])
	var client := int(data.speaker)
	if appearances(client).has(chapter):
		rows.append([translate("Briefing"), a("character/%d" % client)])
	if int(data.reward) > 0:
		rows.append([board_label("reward"), money(int(data.reward))])
	var stock: Array = data.stock.map(func(v): return "%s/%d" % ["equipment" if int(library.equipment(int(v)).category) != library.CARGO_CATEGORY else "goods", int(v)])
	rows.append([translate("Campaign shop"), links(stock)])
	var people: Array = []
	for speaker in cast:
		if appearances(speaker).has(chapter):
			people.append("character/%d" % speaker)
	people.sort()
	rows.append([translate("Characters"), links(people)])
	rows.append([translate("Dialogue"), a("dialogue/%d" % chapter)])
	out += facts(rows)
	out += prose_html("chapter/%d" % chapter)
	if not finished(chapter):
		out += p("<em>%s</em>" % esc(translate("Finish this chapter to read how it ends.")))
	var steps: Array = []
	if chapter > 1:
		steps.append("◀ " + chapter_link(chapter - 1))
	if chapter < chapters and chapter + 1 <= limit:
		steps.append(chapter_link(chapter + 1) + " ▶")
	if not steps.is_empty():
		out += p(" · ".join(steps))
	return out


func dialogue_page(chapter: int) -> String:
	var index := chapter - 1
	var out := h1(translate("Dialogue: %s") % chapter_title(chapter), translate("Chapter %d") % chapter)
	out += p(a("chapter/%d" % chapter, translate("Back to the chapter")))
	out += language_note()
	out += h2(translate("Briefing"))
	var lines: Array = []
	for page_ in library.content.chapters[index].dialogue.size():
		var cue: Dictionary = library.briefing_cue(index, page_)
		var speaker := int(cue.speaker)
		var line := esc(text(int(cue.text)))
		lines.append("<em>%s</em>" % line if speaker < 0 else "<strong>%s</strong>: %s" % [speaker_link(speaker), line])
	out += bullets(lines)
	var radio: Array = library.mission_definition(index).get("radio", [])
	if radio.is_empty():
		return out
	out += h2(translate("Radio"))
	if not finished(chapter):
		return out + p("<em>%s</em>" % esc(translate("The radio calls appear once you have flown this chapter.")))
	lines = []
	for cue in radio:
		lines.append("<strong>%s</strong>: %s" % [speaker_link(int(cue.speaker)), esc(text(int(cue.text)))])
	return out + bullets(lines)


func speaker_link(speaker: int) -> String:
	return a("character/%d" % speaker) if entries.has("character/%d" % speaker) else esc(character_name(speaker))


func character_page(id: int) -> String:
	var info: Dictionary = prose.pages.get("character/%d" % id, {})
	var out := h1(character_name(id), str(info.get("subtitle", "")))
	var seen := appearances(id)
	out += facts([
		[translate("First appearance"), chapter_link(seen[0])],
		[translate("Chapters"), ", ".join(seen.map(func(chapter): return chapter_link(chapter)))]
	])
	out += prose_html("character/%d" % id)
	return out


func race_page(race: int) -> String:
	var out := h1(race_name(race), translate("Race"))
	var places := race_places(race)
	var planets := places.filter(func(id): return library.station_definition(id).planet).size()
	var shops := places.filter(func(id): return library.station_definition(id).shop).size()
	var quadrants := {}
	for id in places:
		quadrants[int(library.station_definition(id).quadrant)] = true
	var travel: Dictionary = library.content.travel
	var rows: Array = [
		[translate("Planets"), esc(str(planets))],
		[translate("Stations"), esc(str(places.size() - planets))],
		[translate("With a shop"), esc(str(shops))],
		[translate("Quadrants"), links(quadrants.keys().map(func(q): return "quadrant/%d" % q))]
	]
	if travel.bribes.has(str(race)):
		rows.append([
			map_label("bribe"),
			esc(translate("Asked when your loyalty leans away from them: %s cr per point.") % grouped(absi(int(travel.bribes[str(race)]))))
		])
	if travel.mission_changes.has(str(race)):
		rows.append([status_label("loyalty"), esc(translate("%+d per mission flown for them") % int(travel.mission_changes[str(race)]))])
	out += facts(rows)
	out += prose_html("race/%d" % race)
	var ships: Array = []
	for ship in library.ships.size():
		if sells_ship(race, ship):
			ships.append("ship/%d" % ship)
	out += h2(translate("Ships in their shops"))
	out += p(links(ships))
	var biggest: Array = places.duplicate()
	biggest.sort_custom(func(x, y): return int(library.station_definition(x).technology) > int(library.station_definition(y).technology))
	out += h2(translate("Places"))
	out += p(links(biggest.slice(0, 40).map(func(id): return "station/%d" % id)))
	if places.size() > 40:
		out += p("<em>%s</em>" % esc(translate("and %d more; search by name, or see their systems.") % (places.size() - 40)))
	return out


func sells_ship(race: int, ship: int) -> bool:
	var rules: Dictionary = library.content.economy
	var actor := int(library.ship_definition(ship).actor)
	if race == int(rules.exclusive_ship_race):
		return actor == int(rules.exclusive_ship_actor)
	if actor == int(rules.exclusive_ship_actor):
		return false
	return actor != int(rules.restricted_ship_actor) or race == int(rules.restricted_ship_race)


func galaxy_page() -> String:
	var out := h1(translate("Galaxy map"), translate("%d planets and stations") % library.stations.size())
	out += prose_html("galaxy")
	var rows: Array = []
	for quadrant in library.quadrants.size():
		var places: Array = []
		for system in quadrant_systems(quadrant):
			places.append_array(system_places(system))
		rows.append([
			a("quadrant/%d" % quadrant),
			esc(str(quadrant_systems(quadrant).size())),
			esc(str(places.size())),
			money(int(library.content.contracts.minimum_rewards[quadrant])) + " – " + money(int(library.content.contracts.maximum_rewards[quadrant]))
		])
	out += grid([map_label("quadrant"), translate("Systems"), translate("Places"), translate("Job rewards")], rows)
	return out


func quadrant_page(quadrant: int) -> String:
	var out := h1(quadrant_name(quadrant), translate("Quadrant %d") % (quadrant + 1))
	var contracts: Dictionary = library.content.contracts
	var races := {}
	for system in quadrant_systems(quadrant):
		for id in system_places(system):
			var race := int(library.station_definition(id).race)
			races[race] = int(races.get(race, 0)) + 1
	var race_keys: Array = races.keys()
	race_keys.sort_custom(func(x, y): return races[x] > races[y])
	out += facts([
		[translate("Difficulty"), esc(str(int(library.content.tables.quadrant_difficulty[quadrant])))],
		[translate("Job rewards"), money(int(contracts.minimum_rewards[quadrant])) + " – " + money(int(contracts.maximum_rewards[quadrant]))],
		[translate("Inhabitants"), ", ".join(race_keys.map(func(race): return "%s (%d)" % [a("race/%d" % race), races[race]]))]
	])
	out += prose_html("quadrant/%d" % quadrant)
	var rows: Array = []
	for system in quadrant_systems(quadrant):
		var shops := system_places(system).filter(func(id): return library.station_definition(id).shop).size()
		rows.append([a("system/%d" % system), esc(str(system_places(system).size())), esc(str(shops))])
	out += h2(translate("Systems"))
	out += grid([translate("System"), translate("Places"), translate("With a shop")], rows)
	var first: Array = []
	for ship in library.ships.size():
		if int(library.ship_definition(ship).quadrant) == quadrant:
			first.append("ship/%d" % ship)
	for item in library.items.size():
		var equipment: Dictionary = library.equipment(item)
		if int(equipment.quadrant) == quadrant and equipment.category != library.CARGO_CATEGORY:
			first.append("equipment/%d" % item)
	out += h2(translate("First sold here"))
	out += p(links(first))
	return out


func system_page(system: int) -> String:
	var quadrant := system_quadrant(system)
	var out := h1(system_name(system), "%s · %s" % [translate("System"), quadrant_name(quadrant)])
	out += facts([[map_label("quadrant"), a("quadrant/%d" % quadrant)]])
	var rows: Array = []
	for id in system_places(system):
		var station: Dictionary = library.station_definition(id)
		rows.append([a("station/%d" % id), esc(place_kind(id)), a("race/%d" % station.race), esc(str(station.technology)), yes_no(station.shop)])
	out += grid([map_label("name"), translate("Kind"), map_label("inhabitants"), map_label("technology"), map_label("trade")], rows)
	return out


func station_page(id: int) -> String:
	var station: Dictionary = library.station_definition(id)
	var out := h1(station_name(id), "%s · %s" % [place_kind(id), system_name(station.system)])
	var threshold := grouped(int(library.content.station_ui.shop_credit_threshold) + 1)
	var rows: Array = [
		[map_label("inhabitants"), a("race/%d" % station.race)],
		[map_label("technology"), esc(str(station.technology))],
		[map_label("trade"), yes_no(station.shop)],
		[translate("Hangar"), esc(translate("Always open") if station.shop else translate("Open with %s credits or more") % threshold)],
		[translate("System"), a("system/%d" % station.system)],
		[map_label("quadrant"), a("quadrant/%d" % station.quadrant)],
		[translate("Position"), esc("%d, %d" % [int(station.position.x), int(station.position.y)])]
	]
	if station.planet:
		rows.append([translate("Population"), esc(grouped(int(station.population)))])
	var here := campaign_chapters_at(id)
	if not here.is_empty():
		rows.append([translate("Story"), ", ".join(here.map(func(chapter): return chapter_link(chapter)))])
	out += facts(rows)
	out += prose_html("station/%d" % id)
	out += h2(translate("Cargo prices here"))
	var prices: Array = []
	for item in library.items.size():
		if library.equipment(item).category == library.CARGO_CATEGORY:
			prices.append([a("goods/%d" % item), money(Market.cargo_price_at(library, item, int(station.technology)))])
	out += grid([translate("Goods"), translate("Price")], prices)
	out += h2(translate("Neighbours"))
	out += p(links(system_places(int(station.system)).filter(func(other): return other != id).map(func(other): return "station/%d" % other)))
	return out


func ship_page(id: int) -> String:
	var ship: Dictionary = library.ship_definition(id)
	var out := h1(ship_name(id), translate("Ship"))
	out += quoted(int(library.content.hangar_ui.description.ships.base + library.content.hangar_ui.description.ships.stride * id))
	var rows: Array = [
		[translate("Price"), money(ship.price)],
		[hangar_label("armor"), esc(str(ship.hull))],
		[hangar_label("hold"), esc(str(ship.capacity))],
		[translate("First sold in"), quadrant_from(int(ship.quadrant))],
		[translate("Sold"), ship_sold_by(id)],
		[translate("Resale"), esc(translate("%d%% of the price paid") % roundi(float(library.content.economy.ship_resale_factor) * 100.0))]
	]
	for category in mini(library.SHIELD_CATEGORY, ship.mounts.size()):
		rows.append([category_label(category), esc(str(int(ship.mounts[category])))])
	if id == int(library.content.initial.ship_index):
		rows.append([translate("Start"), esc(translate("Your first ship"))])
	out += facts(rows)
	out += language_note()
	out += prose_html("ship/%d" % id)
	var prices: Array = []
	for level in TECHNOLOGY_LEVELS:
		prices.append([esc(str(level)), money(Market.ship_price_at(library, id, level))])
	out += h2(translate("Price by technology level"))
	out += grid([map_label("technology"), translate("Price")], prices)
	return out


func equipment_page(id: int) -> String:
	var item: Dictionary = library.equipment(id)
	var shield: bool = item.category == library.SHIELD_CATEGORY
	var out := h1(item_name(id), category_label(item.category))
	out += quoted(int(library.content.hangar_ui.description.items.base + library.content.hangar_ui.description.items.stride * id))
	var rows: Array = [
		[translate("Type"), esc(category_label(item.category))],
		[hangar_label("capacity" if shield else "damage"), esc(str(item.value))]
	]
	if item.interval_ms > 0:
		rows.append([
			hangar_label("recharge" if shield else "rate"),
			esc(translate("%.2f /s") % (1000.0 / float(item.interval_ms)))
		])
	var ballistics: Dictionary = library.weapon_ballistics(id)
	if not ballistics.is_empty():
		rows.append([translate("Damage per second"), esc("%.1f" % (float(ballistics.damage) / float(ballistics.interval)))])
		rows.append([translate("Range"), esc(translate("%d m") % roundi(float(ballistics.lifetime) * float(ballistics.speed)))])
	rows.append([translate("Price"), money(int(item.max_price))])
	rows.append([translate("Resale"), esc(translate("%d%% of the price paid") % roundi(float(library.content.economy.equipment_resale_factor) * 100.0))])
	rows.append([translate("First sold in"), quadrant_from(int(item.quadrant))])
	rows.append([translate("Sold"), item_sold_by(id)])
	var chapters_ := stocked_in(id)
	if not chapters_.is_empty():
		rows.append([translate("Campaign shop"), ", ".join(chapters_.map(func(chapter): return chapter_link(chapter)))])
	out += facts(rows)
	out += language_note()
	out += prose_html("equipment/%d" % id)
	var fits: Array = []
	if not shield:
		for ship in library.ships.size():
			var mounts: Array = library.ship_definition(ship).mounts
			if item.category < mounts.size() and int(mounts[item.category]) > 0:
				fits.append("ship/%d" % ship)
		out += h2(translate("Ships that can mount it"))
		out += p(links(fits))
	return out


func goods_page(id: int) -> String:
	var item: Dictionary = library.equipment(id)
	var out := h1(item_name(id), category_label(item.category))
	out += quoted(int(library.content.hangar_ui.description.items.base + library.content.hangar_ui.description.items.stride * id))
	var trend := translate("The same everywhere")
	if int(item.technology) == 0:
		trend = translate("Higher at stations with a high technology level")
	elif int(item.technology) == 2:
		trend = translate("Higher at stations with a low technology level")
	out += facts([
		[translate("Price"), money(int(item.min_price)) + (" – " + money(int(item.max_price)) if item.max_price != item.min_price else "")],
		[translate("Price trend"), esc(trend)]
	])
	out += language_note()
	out += prose_html("goods/%d" % id)
	var prices: Array = []
	for level in TECHNOLOGY_LEVELS:
		prices.append([esc(str(level)), money(Market.cargo_price_at(library, id, level))])
	out += h2(translate("Price by technology level"))
	out += grid([map_label("technology"), translate("Price")], prices)
	return out


func job_page(kind: int) -> String:
	var definition: Dictionary = library.content.contracts.types[kind]
	var out := h1(contract_name(kind), board_label("title"))
	out += quoted(int(definition.description))
	var contracts: Dictionary = library.content.contracts
	var rewards: Array = []
	for quadrant in library.quadrants.size():
		rewards.append([
			a("quadrant/%d" % quadrant),
			money(roundi(int(contracts.minimum_rewards[quadrant]) * float(definition.reward_factor))) + " – " + money(roundi(int(contracts.maximum_rewards[quadrant]) * float(definition.reward_factor)))
		])
	out += facts([
		[translate("Reward factor"), esc("×%.1f" % float(definition.reward_factor))],
		[translate("Paid"), esc(translate("Per target destroyed") if definition.reward_unit == "per_target" else translate("On completion"))]
	])
	out += language_note()
	out += prose_html("job/%d" % kind)
	out += h2(translate("Typical rewards"))
	out += grid([map_label("quadrant"), board_label("reward")], rewards)
	return out


func ranks_page() -> String:
	var out := h1(entries["progress/ranks"].title, entries["progress/ranks"].subtitle)
	out += prose_html("progress/ranks")
	var status: Dictionary = library.content.station_ui.status
	var rows: Array = [[esc(text(int(status.reputation_base))), esc("0")]]
	var thresholds: Array = status.reputation_thresholds
	for index in mini(thresholds.size(), int(status.reputation_max)):
		rows.append([esc(text(int(status.reputation_base) + index + 1)), esc(str(int(thresholds[index])))])
	out += h2(status_label("reputation"))
	out += grid([status_label("reputation"), status_label("kills")], rows)
	return out


func milestones_page() -> String:
	var out := h1(entries["progress/milestones"].title, entries["progress/milestones"].subtitle)
	out += prose_html("progress/milestones")
	out += language_note()
	var messages: Dictionary = library.content.station_messages
	var rows: Array = []
	var credits: Array = messages.credit_milestones.duplicate()
	credits.sort_custom(func(x, y): return int(x.threshold) < int(y.threshold))
	for record in credits:
		rows.append([money(int(record.threshold) + 1), esc(text(int(record.text)))])
	out += h2(translate("Credits"))
	out += grid([translate("Reached"), translate("Message")], rows)
	rows = []
	var exploration: Array = messages.exploration_milestones.duplicate()
	exploration.sort_custom(func(x, y): return float(x.rate) < float(y.rate))
	for record in exploration:
		rows.append([esc("%d%%" % roundi(float(record.rate))), esc(text(int(record.text)))])
	out += h2(translate("Exploration"))
	out += grid([translate("Reached"), translate("Message")], rows)
	return out


func mode_page(mode: String) -> String:
	var out := h1(entries["mode/" + mode].title, entries["mode/" + mode].subtitle)
	if mode == "survival":
		var menu: Dictionary = library.content.survival.menu
		out += quoted(int(menu.description))
		out += language_note()
		out += prose_html("mode/" + mode)
		var ranks: Array = []
		for record in menu.presentation.ranks:
			ranks.append([esc(text(int(record.text))), esc(grouped(int(record.points)))])
		out += h2(text(int(menu.table.rank)))
		out += grid([text(int(menu.table.rank)), text(int(menu.table.score))], ranks)
		return out
	return out + prose_html("mode/" + mode)


func tips_page() -> String:
	var out := h1(entries["guide/tips"].title, entries["guide/tips"].subtitle)
	out += prose_html("guide/tips")
	out += h2(translate("From the game"))
	out += language_note()
	var tips: Array = []
	var hints: Dictionary = library.content.hangar_ui.hints.messages
	for key in ["intro", "ship", "cargo", "shop"]:
		if hints.has(key):
			tips.append(esc(text(int(hints[key]))))
	return out + bullets(tips)
