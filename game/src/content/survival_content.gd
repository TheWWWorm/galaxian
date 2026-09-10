extends RefCounted
## Validate the complete imported mode before any menu or runtime consumes it.
const Session = preload("res://src/simulation/survival_session.gd")
const Profile = preload("res://src/simulation/arcade_profile.gd")
const Combat = preload("res://src/simulation/combat.gd")


static func valid(value: Variant, library) -> bool:
	if not value is Dictionary:
		return false
	for key in ["rules", "setup", "armament", "motion", "scores", "menu", "hud", "choice"]:
		if not value.get(key) is Dictionary:
			return false
	return (
		Session.valid_declarations(value, library)
		and Profile.valid_rules(value.scores)
		and score_text(value.scores, library)
		and menu(value.menu, library)
		and hud(value.hud, library)
		and choice(value.choice, library)
	)


static func integer(value: Variant, low: int = 0, high: int = 4096) -> bool:
	return Combat.integer(value) and value >= low and value <= high


static func numbers(value: Variant, count: int, low: int = 0, high: int = 4096) -> bool:
	return (
		value is Array
		and value.size() == count
		and value.all(func(part): return integer(part, low, high))
	)


static func fields(value: Dictionary, keys: Array, low: int = 0, high: int = 4096) -> bool:
	return keys.all(func(key): return integer(value.get(key), low, high))


static func text(value: Variant, library) -> bool:
	return integer(value, 0, library.strings.size() - 1)


static func texts(value: Variant, keys: Array, library) -> bool:
	return value is Dictionary and keys.all(func(key): return text(value.get(key), library))


static func string(value: Variant, maximum: int = 128) -> bool:
	return value is String and value.length() <= maximum


static func image(value: Variant, library) -> bool:
	if (
		not value is Dictionary
		or not integer(value.get("texture"))
		or not integer(value.get("region"))
	):
		return false
	var atlas: Dictionary = library.radio_atlases.get(str(int(value.texture)), {})
	if atlas.is_empty() or value.region >= atlas.regions.size():
		return false
	var region: Rect2i = atlas.regions[int(value.region)]
	return region.size.x > 0 and region.size.y > 0


static func images(value: Variant, keys: Array, library) -> bool:
	return value is Dictionary and keys.all(func(key): return image(value.get(key), library))


static func frame(value: Variant) -> bool:
	return numbers(value, 4) and value[2] > 0 and value[3] > 0


static func score_text(value: Dictionary, library) -> bool:
	if not texts(value.get("labels"), ["defeat", "kills", "time", "score", "main_menu"], library):
		return false
	var format: Variant = value.get("format")
	return (
		format is Dictionary
		and ["paragraph", "label_suffix", "value_break", "zero_suffix"].all(
			func(key): return string(format.get(key))
		)
	)


static func menu(value: Dictionary, library) -> bool:
	if (
		not texts(value, ["title", "description", "strengths", "back", "start"], library)
		or not numbers(value.get("tabs"), 2, 0, library.strings.size() - 1)
		or not image(value.get("picture"), library)
		or not frame(value.get("frame"))
		or not numbers(value.get("content_origin"), 2)
		or not fields(value, ["text_width", "content_height"], 1)
		or not value.get("legend") is Array
		or value.legend.size() != 3
	):
		return false
	for row in value.legend:
		if (
			not row is Dictionary
			or not text(row.get("text"), library)
			or not image(row.get("image"), library)
		):
			return false
	var art: Variant = value.get("presentation")
	if (
		not art is Dictionary
		or not images(
			art.get("images"),
			[
				"tab_selected",
				"tab_idle",
				"corner",
				"tab_corner",
				"preview",
				"score_bar",
				"preview_overlay"
			],
			library
		)
		or not fields(art, ["caption_y", "score_gap", "score_right_padding"])
		or not numbers(art.get("fill"), 4, 0, 255)
		or not numbers(art.get("border"), 4, 0, 255)
		or not text(art.get("highscore"), library)
		or not art.get("ranks") is Array
		or art.ranks.is_empty()
		or art.ranks.size() > 64
	):
		return false
	for key in ["right_origin", "score_text_offset", "rank_origin", "picture_center"]:
		if not numbers(art.get(key), 2):
			return false
	var previous := -1
	for rank in art.ranks:
		if (
			not rank is Dictionary
			or not integer(rank.get("points"), 0, Profile.MAX_ID)
			or not text(rank.get("text"), library)
			or rank.points <= previous
		):
			return false
		previous = int(rank.points)
	var table: Variant = value.get("table")
	if (
		not table is Dictionary
		or not texts(table, ["rank", "name", "score"], library)
		or not numbers(table.get("columns"), 3)
		or not fields(table, ["line_end", "line_base", "header_padding", "row_gap"])
		or not integer(table.get("header_height_divisor"), 1)
		or not numbers(table.get("highlight"), 4, 0, 255)
		or not string(table.get("rank_zero"))
	):
		return false
	if (
		table.columns[0] >= table.columns[1]
		or table.columns[1] >= table.columns[2]
		or table.columns[2] >= table.line_end
	):
		return false
	var entry: Variant = value.get("name_entry")
	return (
		entry is Dictionary
		and text(entry.get("prompt"), library)
		and integer(entry.get("limit"), 1, 128)
		and frame(entry.get("frame"))
		and numbers(entry.get("input"), 2)
		and fields(entry, ["width", "height_lines"], 1)
		and integer(entry.get("prompt_y"))
		and numbers(entry.get("fill"), 4, 0, 255)
		and numbers(entry.get("border"), 4, 0, 255)
	)


static func hud(value: Dictionary, library) -> bool:
	if (
		not image(value.get("score_image"), library)
		or not numbers(value.get("score_text"), 2)
		or not fields(
			value,
			[
				"score_right",
				"score_top",
				"notice_y",
				"combo_y_from_center",
				"elapsed_right",
				"elapsed_bottom"
			]
		)
		or not fields(value, ["notice_ms", "combo_ms"], 1, 60000)
		or not fields(value, ["notice_height_lines", "combo_minimum"], 1, 128)
		or not string(value.get("combo_separator"))
		or not value.get("combo_text") is Array
		or value.combo_text.is_empty()
		or value.combo_text.size() > 32
		or not value.combo_text.all(func(id): return text(id, library))
		or not value.get("notices") is Array
		or value.notices.is_empty()
		or value.notices.size() > 64
	):
		return false
	var previous := -1
	for notice in value.notices:
		if (
			not notice is Dictionary
			or not integer(notice.get("above"), 0, Profile.MAX_ID)
			or not text(notice.get("text"), library)
			or notice.above <= previous
		):
			return false
		previous = int(notice.above)
	var radar: Variant = value.get("radar")
	return (
		radar is Dictionary
		and numbers(radar.get("bounds"), 2)
		and radar.bounds[0] < radar.bounds[1]
		and images(
			radar.get("images"),
			[
				"weak_near",
				"weak_far",
				"weak_off",
				"medium_near",
				"medium_far",
				"medium_off",
				"strong_near",
				"strong_far",
				"strong_off"
			],
			library
		)
	)


static func choice(value: Dictionary, library) -> bool:
	if (
		not images(
			value.get("images"), ["cap", "body", "middle", "bottom", "selected", "idle"], library
		)
		or not string(value.get("default_caption"))
	):
		return false
	var layout: Variant = value.get("layout")
	if (
		not layout is Dictionary
		or not fields(
			layout,
			["base_y", "short_lines", "text_padding", "extra_rows", "button_x", "button_text_y"]
		)
	):
		return false
	var cap: Dictionary = value.images.cap
	var region: Rect2i = library.radio_atlases[str(int(cap.texture))].regions[int(cap.region)]
	return layout.text_padding < region.size.x
