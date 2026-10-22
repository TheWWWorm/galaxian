extends RefCounted
## Adapted from the Apache-2.0 licensed maintained DEEP remake (Abyssal).
## The reference's own writing: overviews, guides, story synopses and
## biographies, kept per language in src/wiki/prose/<code>.gd. Imported text
## never appears in it; a [[key]] token stands for the page's title in the
## player's game, and [[key|words]] links the given words instead.
##
## Every block names the chapter a player must have reached to read it, so a
## synopsis or biography grows with the save and never runs ahead of it. A
## chapter is reached when it is offered; its outcome is written for the
## chapter after it. A language without its own text for a page falls back to
## English.

## Pages of their own: key -> {title, subtitle, category, from}.
var pages := {}
## Key -> blocks; a block is [from, heading, text, list item].
var blocks := {}


static func path(code: String) -> String:
	return "res://src/wiki/prose/%s.gd" % code


static func source(code: String):
	if not code.is_valid_identifier() or not ResourceLoader.exists(path(code)):
		return null
	return load(path(code))


func _init(code := "en") -> void:
	var english = source("en")
	if english != null:
		pages = english.PAGES.duplicate(true)
		blocks = english.BLOCKS.duplicate(true)
	if code == "en":
		return
	var local = source(code)
	if local == null:
		return
	for key: String in local.PAGES:
		if pages.has(key):
			for field in ["title", "subtitle", "early_title"]:
				if not str(local.PAGES[key].get(field, "")).is_empty():
					pages[key][field] = local.PAGES[key][field]
	for key: String in local.BLOCKS:
		blocks[key] = local.BLOCKS[key]


## The blocks of a page a save at the given chapter may read.
func visible(key: String, limit: int) -> Array:
	return blocks.get(key, []).filter(func(block: Array): return int(block[0]) <= limit)


## Every [[key]] or [[key|words]] token in a text: [whole, key, words].
static func tokens(text: String) -> Array:
	var result: Array = []
	for found in TOKEN.search_all(text):
		result.append([found.get_string(0), found.get_string(1), found.get_string(2)])
	return result


static var TOKEN := RegEx.create_from_string(
	"\\[\\[([a-z]+(?:/[a-z0-9]+)?)(?:\\|([^\\]]*))?\\]\\]"
)
