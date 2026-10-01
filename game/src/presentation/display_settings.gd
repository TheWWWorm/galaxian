extends RefCounted
## Match the window by default; optional fixed picture ratios preserve geometry.
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
const RATIOS := {"auto": Vector2i(1440, 900), "4:3": Vector2i(1200, 900),
	"16:9": Vector2i(1600, 900), "16:10": Vector2i(1440, 900), "21:9": Vector2i(2100, 900)}


## Frame-rate limits offered in Options. "auto" follows the panel the window is
## on; "unlimited" leaves the renderer to vertical sync alone.
const FRAME_RATES: Array = ["auto", 30, 60, 90, 120, 144, 240, "unlimited"]


static func frame_rate_value(value: Variant) -> Variant:
	## The stored form of a frame-rate choice, or "auto" for anything unknown.
	if value is String and value in FRAME_RATES:
		return value
	if (value is int or value is float) and is_finite(float(value)) and FRAME_RATES.has(int(value)):
		return int(value)
	return "auto"


static func panel_refresh_rate(window: Window) -> int:
	## The panel's refresh rate in whole frames per second, or 0 when unknown.
	var rate := DisplayServer.screen_get_refresh_rate(window.current_screen)
	return roundi(rate) if is_finite(rate) and rate > 0 else 0


static func apply_frame_rate(window: Window, value: Variant) -> void:
	var choice: Variant = frame_rate_value(value)
	if choice is int:
		Engine.max_fps = choice
	elif choice == "auto":
		Engine.max_fps = panel_refresh_rate(window)
	else:
		Engine.max_fps = 0


static func frame_rate_caption(window: Window, value: Variant) -> String:
	var choice: Variant = frame_rate_value(value)
	if choice is int:
		return str(choice)
	if choice == "unlimited":
		return EngineLanguage.translate("Unlimited")
	var rate := panel_refresh_rate(window)
	return EngineLanguage.translate("Auto (%d)") % rate if rate > 0 else EngineLanguage.translate("Auto")


static func apply_aspect(window: Window, ratio: String) -> void:
	if not RATIOS.has(ratio): ratio = "auto"
	window.content_scale_size = RATIOS[ratio]
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if ratio == "auto" else Window.CONTENT_SCALE_ASPECT_KEEP


static func fullscreen(window: Window) -> bool:
	return window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


static func set_fullscreen(window: Window, enabled: bool) -> void:
	window.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
