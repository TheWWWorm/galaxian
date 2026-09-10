extends RefCounted
## Bounded resource readers for the iPhone AEM v1/v2 and raw RGBA AEI layouts.
## Data only: no original executable or platform framework is loaded.
var error := ""


func aem(data: PackedByteArray) -> Dictionary:
	error = ""
	var version := (
		2
		if (
			data.size() >= 9
			and data.slice(0, 8).get_string_from_ascii() == "V2AEMesh"
			and data[8] == 0
		)
		else 1
	)
	var head := 10 if version == 2 else 8
	if (
		data.size() < head + 4
		or (version == 1 and (data.slice(0, 6).get_string_from_ascii() != "AEMesh" or data[6] != 0))
	):
		return fail("Unrecognized or truncated mesh header")
	var flags := int(data[head - 1])
	if flags not in [19, 23, 31]:
		return fail("Unsupported mesh flags: %d" % flags)
	var count := data.decode_u16(head)
	var pos := head + 2
	if count == 0 or count % 3 != 0 or pos + count * 2 + 2 > data.size():
		return fail("Invalid triangle buffer")
	var indices := PackedInt32Array()
	indices.resize(count)
	for i in count:
		indices[i] = data.decode_u16(pos + i * 2)
	pos += count * 2
	var vertices := data.decode_u16(pos)
	pos += 2
	var stride := (
		(12 if version == 2 else 6)
		+ (4 if flags & 2 else 0)
		+ (6 if flags & 4 else 0)
		+ (4 if flags & 8 else 0)
	)
	if vertices == 0 or pos + vertices * stride + (1 if version == 1 else 0) != data.size():
		return fail("Mesh payload size does not match its header")
	for i in indices:
		if i >= vertices:
			return fail("Mesh index exceeds vertex count")
	var points := PackedVector3Array()
	points.resize(vertices)
	for i in vertices:
		var p := pos + i * (12 if version == 2 else 6)
		if version == 2:
			points[i] = (
				Vector3(data.decode_s32(p), data.decode_s32(p + 4), -data.decode_s32(p + 8)) * .02
			)
		else:
			points[i] = (
				Vector3(data.decode_s16(p), data.decode_s16(p + 2), -data.decode_s16(p + 4)) * .02
			)
	pos += vertices * (12 if version == 2 else 6)
	var uv := PackedVector2Array()
	uv.resize(vertices)
	var unit := 4096.0 if version == 2 else 256.0
	if flags & 2:
		for i in vertices:
			uv[i] = Vector2(
				float(data.decode_s16(pos + i * 4)) / unit,
				1.0 - float(data.decode_s16(pos + i * 4 + 2)) / unit
			)
		pos += vertices * 4
	var lighting_normals := PackedFloat32Array()
	lighting_normals.resize(vertices * 3)
	var normals := PackedVector3Array()
	normals.resize(vertices)
	if flags & 4:
		for i in vertices:
			var n := Vector3(
				data.decode_s16(pos + i * 6),
				data.decode_s16(pos + i * 6 + 2),
				-data.decode_s16(pos + i * 6 + 4)
			)
			normals[i] = n.normalized()
			# GLES short conversion is component-wise; preserve magnitude and reflect Z
			# after conversion. Godot normal storage is reserved for its own shading.
			lighting_normals[i * 3] = (2.0 * n.x + 1.0) / 65535.0
			lighting_normals[i * 3 + 1] = (2.0 * n.y + 1.0) / 65535.0
			lighting_normals[i * 3 + 2] = (2.0 * n.z - 1.0) / 65535.0
		pos += vertices * 6
	else:
		for i in range(0, count, 3):
			var a := indices[i]
			var b := indices[i + 1]
			var c := indices[i + 2]
			var n := (points[c] - points[a]).cross(points[b] - points[a]).normalized()
			normals[a] += n
			normals[b] += n
			normals[c] += n
		for i in vertices:
			normals[i] = normals[i].normalized()
			lighting_normals[i * 3 + 2] = -1.0
	var colors := PackedColorArray()
	if flags & 8:
		colors.resize(vertices)
		for i in vertices:
			var p := pos + i * 4
			colors[i] = Color8(data[p], data[p + 1], data[p + 2], data[p + 3])
	return {
		"vertices": points,
		"indices": indices,
		"uv": uv,
		"normals": normals,
		"lighting_normals": lighting_normals,
		"colors": colors,
		"version": version,
		"flags": flags
	}


func aei(data: PackedByteArray) -> Dictionary:
	error = ""
	if (
		data.size() < 17
		or (data.slice(0, 7).get_string_from_ascii() != "AEimage" or data[7] != 0)
		or data[8] != 1
	):
		return fail("Unsupported texture header or compression")
	var width := data.decode_u16(9)
	var height := data.decode_u16(11)
	var count := data.decode_u16(13)
	var start := 15 + count * 8
	var end := start + width * height * 4
	if width < 1 or height < 1 or width > 4096 or height > 4096 or end + 2 > data.size():
		return fail("Invalid texture dimensions or payload")
	var regions: Array[Rect2i] = []
	for i in count:
		var p := 15 + i * 8
		var rect := Rect2i(
			data.decode_u16(p),
			data.decode_u16(p + 2),
			data.decode_u16(p + 4),
			data.decode_u16(p + 6)
		)
		if rect.end.x > width or rect.end.y > height:
			return fail("Texture region exceeds image bounds")
		regions.append(rect)
	var image := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, data.slice(start, end)
	)
	var fonts: Array = []
	var cursor := end + 2
	var font_count := data.decode_u16(end)
	if font_count > 32:
		return fail("Invalid atlas font count")
	for index in font_count:
		if cursor + 2 > data.size():
			return fail("Truncated atlas font")
		var glyph_count := data.decode_u16(cursor)
		cursor += 2
		if glyph_count == 0 or glyph_count > 4096 or cursor + glyph_count * 10 > data.size():
			return fail("Invalid atlas glyph table")
		var glyphs := {}
		for glyph in glyph_count:
			var code := data.decode_u16(cursor + glyph * 2)
			var offset := cursor + glyph_count * 2 + glyph * 8
			var rect := Rect2i(
				data.decode_u16(offset),
				data.decode_u16(offset + 2),
				data.decode_u16(offset + 4),
				data.decode_u16(offset + 6)
			)
			if (
				glyphs.has(code)
				or rect.size.x <= 0
				or rect.size.y <= 0
				or rect.end.x > width
				or rect.end.y > height
			):
				return fail("Invalid atlas glyph bounds or duplicate codepoint")
			glyphs[code] = rect
		fonts.append(glyphs)
		cursor += glyph_count * 10
	if cursor != data.size():
		return fail("Unsupported atlas font trailer")
	return {"image": image, "regions": regions, "fonts": font_count, "glyphs": fonts}


func language(data: PackedByteArray) -> PackedStringArray:
	error = ""
	var strings := PackedStringArray()
	var p := 0
	while p < data.size():
		if p + 2 > data.size():
			error = "Truncated language record"
			return PackedStringArray()
		var length := int(data[p]) * 256 + int(data[p + 1])
		p += 2
		if p + length > data.size():
			error = "Truncated language string"
			return PackedStringArray()
		strings.append(data.slice(p, p + length).get_string_from_utf8())
		p += length
	return strings


func table(data: PackedByteArray, columns: int) -> Array:
	error = ""
	var rows: Array = []
	for line in data.get_string_from_utf8().replace("\r", "").split("\n", false):
		var clean := line.strip_edges().trim_suffix(";")
		if clean.is_empty():
			continue
		var fields := clean.split(",")
		if fields.size() != columns:
			error = "Invalid table column count"
			return []
		rows.append(Array(fields))
	return rows


func name_list(data: PackedByteArray) -> PackedStringArray:
	error = ""
	if data.is_empty() or data.size() > 1024 * 1024:
		error = "Empty or oversized client name list"
		return PackedStringArray()
	if not valid_utf8(data):
		error = "Unsupported client name encoding"
		return PackedStringArray()
	var source := data.get_string_from_utf8()
	# The source format uses semicolon terminators and ignores TAB, LF and CR.
	source = source.replace("\t", "").replace("\n", "").replace("\r", "")
	var fields := source.split(";", true)
	if fields.size() < 2 or fields.size() > 4097 or not fields[-1].strip_edges().is_empty():
		error = "Invalid or unterminated client name list"
		return PackedStringArray()
	fields.remove_at(fields.size() - 1)
	for value in fields:
		if value.strip_edges().is_empty() or value.length() > 255:
			error = "Empty or oversized client name"
			return PackedStringArray()
		for character in value.length():
			if value.unicode_at(character) < 32 or value.unicode_at(character) == 127:
				error = "Unsupported control character in client name"
				return PackedStringArray()
	return fields


func valid_utf8(data: PackedByteArray) -> bool:
	var cursor := 0
	while cursor < data.size():
		var first := int(data[cursor])
		cursor += 1
		if first < 128:
			continue
		var count := 1 if first < 0xe0 else (2 if first < 0xf0 else 3)
		if first < 0xc2 or first > 0xf4 or cursor + count > data.size():
			return false
		var second := int(data[cursor])
		if (
			(first == 0xe0 and second < 0xa0)
			or (first == 0xed and second >= 0xa0)
			or (first == 0xf0 and second < 0x90)
			or (first == 0xf4 and second >= 0x90)
		):
			return false
		for index in count:
			if data[cursor + index] & 0xc0 != 0x80:
				return false
		cursor += count
	return true


func fail(message: String) -> Dictionary:
	error = message
	return {}
