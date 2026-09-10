extends RefCounted
## Only the most recently active controller owns the ship.
var device := -1
var axes := {}
var buttons := {}
var deadzone := .18
var touch_look := Vector2.ZERO
var touch_fire := false
var touch_missiles := false
var touch_boost := false
var touch_throttle := 0.0


func clear() -> void:
	axes.clear()
	buttons.clear()
	touch_look = Vector2.ZERO
	touch_fire = false
	touch_missiles = false
	touch_boost = false
	touch_throttle = 0


func accept(event: InputEvent) -> void:
	if not event is InputEventJoypadMotion and not event is InputEventJoypadButton:
		return
	if event.device != device:
		if event is InputEventJoypadMotion and absf(event.axis_value) < deadzone:
			return
		if event is InputEventJoypadButton and not event.pressed:
			return
		clear()
		device = event.device
	if event is InputEventJoypadMotion:
		axes[event.axis] = event.axis_value
	else:
		buttons[event.button_index] = event.pressed


func axis(index: int) -> float:
	var value := float(axes.get(index, 0.0))
	return signf(value) * maxf(0, absf(value) - deadzone) / (1 - deadzone)


func snapshot() -> Dictionary:
	return {
		"look": Vector2(axis(JOY_AXIS_RIGHT_X), axis(JOY_AXIS_RIGHT_Y)) + touch_look,
		"strafe": axis(JOY_AXIS_LEFT_X),
		"throttle":
		(
			float(buttons.get(JOY_BUTTON_DPAD_UP, false))
			- float(buttons.get(JOY_BUTTON_DPAD_DOWN, false))
			+ touch_throttle
		),
		"fire":
		float(axes.get(JOY_AXIS_TRIGGER_RIGHT, 0.0)) > .25 or buttons.get(JOY_BUTTON_A, false),
		"missiles": float(axes.get(JOY_AXIS_TRIGGER_LEFT, 0.0)) > .25 or touch_missiles,
		"boost": buttons.get(JOY_BUTTON_LEFT_STICK, false)
	}
