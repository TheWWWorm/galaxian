extends RefCounted
## Match the window by default; optional fixed picture ratios preserve geometry.
const RATIOS := {"auto": Vector2i(1440, 900), "4:3": Vector2i(1200, 900),
	"16:9": Vector2i(1600, 900), "16:10": Vector2i(1440, 900), "21:9": Vector2i(2100, 900)}


static func apply_aspect(window: Window, ratio: String) -> void:
	if not RATIOS.has(ratio): ratio = "auto"
	window.content_scale_size = RATIOS[ratio]
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if ratio == "auto" else Window.CONTENT_SCALE_ASPECT_KEEP


static func fullscreen(window: Window) -> bool:
	return window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]


static func set_fullscreen(window: Window, enabled: bool) -> void:
	window.mode = Window.MODE_FULLSCREEN if enabled else Window.MODE_WINDOWED
