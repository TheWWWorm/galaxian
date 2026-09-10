extends RefCounted
## Original mobile glyphs and scalable desktop text share imported layout heights.


static var desktop_fonts := {}


static func create(library) -> FontFile:
	var glyphs: Dictionary = library.radio_glyphs()
	var height: int = glyphs.values()[0].size.y
	if not is_mobile():
		if not desktop_fonts.has(height):
			var vector_font := ThemeDB.fallback_font.duplicate() as FontFile
			vector_font.set_meta("source_height", height)
			desktop_fonts[height] = vector_font
		return desktop_fonts[height]
	var font := FontFile.new()
	font.set_meta("source_height", height)
	font.fixed_size = height
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.set_cache_ascent(0, height, height)
	font.set_cache_descent(0, height, 0)
	var texture: Texture2D = library.radio_texture(int(library.content.radio_ui.font.texture))
	var cache := Vector2i(height, 0)
	font.set_texture_image(0, cache, 0, texture.get_image())
	for code in glyphs:
		var region: Rect2i = glyphs[code]
		font.set_glyph_advance(0, height, code, Vector2(library.radio_glyph_width(code), 0))
		font.set_glyph_offset(0, cache, code, Vector2(0, -height))
		font.set_glyph_size(0, cache, code, region.size)
		font.set_glyph_uv_rect(0, cache, code, region)
		font.set_glyph_texture_idx(0, cache, code, 0)
	return font


static func composition_scale(viewport: Vector2, canvas := Vector2(480, 320)) -> float:
	return fitted_scale(viewport, canvas, is_mobile())


static func fitted_scale(viewport: Vector2, canvas: Vector2, mobile: bool) -> float:
	return minf(viewport.x / canvas.x, viewport.y / canvas.y) * (1.0 if mobile else 0.5)


static func draw_text(
	canvas: CanvasItem, library, text: String, at: Vector2, width: float = INF, tint := Color.WHITE
) -> void:
	var glyphs: Dictionary = library.radio_glyphs()
	var height: int = glyphs.values()[0].size.y
	if not is_mobile():
		var font := ThemeDB.fallback_font
		# Keep authored line breaks, using a vector font at the source text size.
		canvas.draw_string(
			font,
			at + Vector2(0, height),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1 if is_inf(width) else width,
			height,
			tint
		)
		return
	var texture: Texture2D = library.radio_texture(int(library.content.radio_ui.font.texture))
	var end := at.x + width
	for index in text.length():
		var code := text.unicode_at(index)
		if not glyphs.has(code):
			code = 63
		var region: Rect2i = glyphs[code]
		if at.x + region.size.x > end:
			break
		canvas.draw_texture_rect_region(texture, Rect2(at, region.size), region, tint)
		at.x += library.radio_glyph_width(code)


static func text_width(library, text: String) -> float:
	if not is_mobile():
		var height: int = library.radio_glyphs().values()[0].size.y
		return ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, height).x
	var width := 0.0
	for index in text.length():
		width += library.radio_glyph_width(text.unicode_at(index))
	return width


static func wrap_lines(library, text: String, width: float) -> PackedStringArray:
	if is_mobile():
		return library.bitmap_lines(text, width)
	var lines := PackedStringArray()
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if line.is_empty() else line + " " + word
			if not line.is_empty() and text_width(library, candidate) > width:
				lines.append(line)
				line = ""
			if not line.is_empty():
				line += " "
			for character in word:
				if not line.is_empty() and text_width(library, line + character) > width:
					lines.append(line)
					line = ""
				line += character
		lines.append(line)
	return lines


static var mobile_cache := -1

static func is_mobile() -> bool:
	if mobile_cache < 0:
		mobile_cache = int(OS.has_feature("mobile"))
		if OS.has_feature("web"):
			mobile_cache = int(bool(JavaScriptBridge.eval("/Android|iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)")))
	return mobile_cache == 1
