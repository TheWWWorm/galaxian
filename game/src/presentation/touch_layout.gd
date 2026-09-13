extends RefCounted
## Where every touch control sits, in the 480x320 composition the original
## artwork was drawn for. Players can move and resize each one; an adjustment is
## stored as an offset from the imported anchor rather than an absolute place, so
## a different screen keeps the original composition and only moves what the
## player moved.
const MIN_SCALE := .6
const MAX_SCALE := 2.2
const SCALE_STEP := .1
## Ordered so the editor hit-tests the small controls before the large ones they
## sit on top of, and so "next control" walks the screen left to right.
const IDS: Array[String] = [
	"pause",
	"AUTOPILOT",
	"TIME",
	"DOCK",
	"throttle",
	"boost",
	"weapon",
	"missiles",
	"fire",
	"stick",
]
const NAMES := {
	"pause": "Pause",
	"AUTOPILOT": "Autopilot",
	"TIME": "Simulation speed",
	"DOCK": "Dock",
	"throttle": "Throttle",
	"boost": "Boost",
	"weapon": "Weapon",
	"missiles": "Missiles",
	"fire": "Fire",
	"stick": "Steering stick",
}


static func sanitize(stored) -> Dictionary:
	## Settings arrive from a text file a player can edit, and from saves written
	## by older builds. Keep only entries this build still places.
	var clean := {}
	if not stored is Dictionary:
		return clean
	for id in IDS:
		if not stored.get(id) is Dictionary:
			continue
		var entry: Dictionary = stored[id]
		var offset := Vector2(number(entry.get("x")), number(entry.get("y")))
		var scale := clampf(number(entry.get("scale"), 1.0), MIN_SCALE, MAX_SCALE)
		if offset == Vector2.ZERO and is_equal_approx(scale, 1.0):
			continue
		clean[id] = {"x": offset.x, "y": offset.y, "scale": scale}
	return clean


static func number(value, fallback := 0.0) -> float:
	if value is float or value is int:
		var result := float(value)
		# A stored NAN or INF would place a control nowhere and never come back.
		return result if is_finite(result) and absf(result) < 4096 else fallback
	return fallback


static func offset_of(layout: Dictionary, id: String) -> Vector2:
	var entry = layout.get(id)
	if not entry is Dictionary:
		return Vector2.ZERO
	return Vector2(number(entry.get("x")), number(entry.get("y")))


static func scale_of(layout: Dictionary, id: String) -> float:
	var entry = layout.get(id)
	if not entry is Dictionary:
		return 1.0
	return clampf(number(entry.get("scale"), 1.0), MIN_SCALE, MAX_SCALE)


static func adjusted(layout: Dictionary, id: String, offset: Vector2, scale: float) -> Dictionary:
	## Returns the layout with one control's placement replaced, dropping entries
	## that are back at their imported anchor so a reset leaves nothing behind.
	var result := layout.duplicate(true)
	var clamped := clampf(scale, MIN_SCALE, MAX_SCALE)
	if offset.is_zero_approx() and is_equal_approx(clamped, 1.0):
		result.erase(id)
	else:
		result[id] = {"x": offset.x, "y": offset.y, "scale": clamped}
	return result
