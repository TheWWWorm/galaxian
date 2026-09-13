extends RefCounted
## Calibrated phone tilt. Absolute gravity prevents accumulated sensor drift.
var neutral := Vector2.ZERO
var filtered := Vector2.ZERO
var calibrated := false
var last_sample := Vector3.ZERO
var callback: JavaScriptObject
var permission := ""
signal notice(message: String)


func enable() -> void:
	calibrated = false
	filtered = Vector2.ZERO
	if not OS.has_feature("web"):
		return
	if callback == null:
		callback = JavaScriptBridge.create_callback(permission_result)
	(
		JavaScriptBridge
		. eval(
			"""
window.gofMotion = window.gofMotion || {x:0,y:0,z:0,time:0};
window.gofEnableMotion = async function(done) {
 try {
  if (!window.DeviceMotionEvent) { done('Motion sensors are unavailable in this browser.'); return; }
  if (typeof DeviceMotionEvent.requestPermission === 'function' && await DeviceMotionEvent.requestPermission() !== 'granted') {
   done('Motion sensor permission was denied.'); return;
  }
  if (!window.gofMotionListening) {
   // WebKit reports accelerationIncludingGravity as the gravity vector, every
   // other browser as the equal and opposite reaction, so one of the two always
   // steered backwards. Normalising to gravity pointing down leaves pitch alone:
   // flipping a whole vector only shifts the pitch term by PI, and that cancels
   // against the neutral, which is why only left and right ever read reversed.
   const webkit = /iP(hone|ad|od)/.test(navigator.userAgent)
    || (navigator.maxTouchPoints > 1 && /Mac/.test(navigator.platform || ''));
   const down = webkit ? 1 : -1;
   window.addEventListener('devicemotion', e => {
    const g = e.accelerationIncludingGravity;
    if (!g || g.x === null || g.y === null || g.z === null) return;
    // The screen's up axis is the device's +Y at angle 0 and its +X at 90, so
    // rotating by the reported angle reads the same way held any way up.
    const o = screen.orientation;
    const a = (o ? o.angle : (window.orientation || 0)) * Math.PI / 180;
    const cos = Math.cos(a), sin = Math.sin(a);
    window.gofMotion = {
     x: down * (g.x * cos - g.y * sin),
     y: down * (g.x * sin + g.y * cos),
     // Pitch keeps the sign the sensor reported, the direction players fly now.
     z: -down * g.z,
     time: performance.now()
    };
   });
   window.gofMotionListening = true;
  }
  done('');
 } catch (_) { done('Motion sensors could not be enabled.'); }
};
""",
			true
		)
	)
	JavaScriptBridge.get_interface("window").gofEnableMotion(callback)


func permission_result(args: Array) -> void:
	permission = str(args[0])
	if not permission.is_empty():
		notice.emit(permission)


func reading() -> Vector3:
	if OS.has_feature("web"):
		var raw: Variant = (
			JavaScriptBridge
			. eval(
				"window.gofMotion && performance.now()-window.gofMotion.time < 1000 ? JSON.stringify([window.gofMotion.x,window.gofMotion.y,window.gofMotion.z]) : null"
			)
		)
		if raw is String:
			var values: Variant = JSON.parse_string(raw)
			if values is Array and values.size() == 3:
				return Vector3(values[0], values[1], values[2])
		return Vector3.ZERO
	if OS.has_feature("android") or OS.has_feature("ios"):
		var gravity := Input.get_gravity()
		return gravity if gravity.length_squared() > 1 else Input.get_accelerometer()
	return Vector3.ZERO


static func angles(gravity: Vector3) -> Vector2:
	## Screen-space gravity points down at rest, so the vertical term reads zero
	## there. Rolling the phone left tips screen-down toward -X, which has to read
	## as steering left, matching a stick pushed left.
	var unit := gravity.normalized()
	return Vector2(atan2(unit.x, sqrt(unit.y * unit.y + unit.z * unit.z)), atan2(unit.z, -unit.y))


func calibrate() -> bool:
	var gravity := reading()
	if gravity.length_squared() < 1 or not gravity.is_finite():
		(
			notice
			. emit(
				"No motion sensor reading. Use a phone with motion sensors and allow sensor access in your browser."
			)
		)
		return false
	neutral = angles(gravity)
	calibrated = true
	filtered = Vector2.ZERO
	return true


func sample(gravity: Vector3, seconds: float, sensitivity: float) -> Vector2:
	if not gravity.is_finite() or gravity.length_squared() < 1:
		filtered = Vector2.ZERO
		return filtered
	var current := angles(gravity)
	if not calibrated:
		neutral = current
		calibrated = true
	var offset := Vector2(
		wrapf(current.x - neutral.x, -PI, PI), wrapf(current.y - neutral.y, -PI, PI)
	)
	var full_scale := deg_to_rad(lerpf(40, 10, clampf(sensitivity, 0, 1)))
	var target := Vector2.ZERO
	for axis in 2:
		target[axis] = (
			signf(offset[axis]) * clampf((absf(offset[axis]) - deg_to_rad(1.5)) / full_scale, 0, 1)
		)
	filtered = filtered.lerp(target, 1.0 - exp(-maxf(0, seconds) / .07))
	return filtered


func look(seconds: float, sensitivity: float) -> Vector2:
	return sample(reading(), seconds, sensitivity)
