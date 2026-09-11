extends RefCounted
## Radar presence selects music independently of HUD visibility and simulation RNG.
const Combat = preload("res://src/simulation/combat.gd")
var track := -1
var combat := false
var pending := false
var desired := false
var elapsed := 0.0
var random := RandomNumberGenerator.new()


static func valid(data: Variant, sounds: Dictionary) -> bool:
	if not data is Dictionary or not data.get("combat") is Array or data.combat.size() != 2:
		return false
	for id in data.combat + [data.get("explore")]:
		if not Combat.integer(id) or not sounds.has(str(int(id))):
			return false
	for key in ["combat_delay", "explore_delay"]:
		if not Combat.number(data.get(key)) or data[key] <= 0 or data[key] > 60:
			return false
	return true


func reset() -> void:
	track = -1
	combat = false
	pending = false
	elapsed = 0
	random.randomize()


func advance(data: Dictionary, enemy_present: bool, survival: bool, seconds: float) -> int:
	# Survival never transitions back to exploration between waves.
	var target := enemy_present or (survival and combat)
	if target == combat:
		var interrupted := pending
		pending = false
		elapsed = 0
		return (track if track >= 0 else int(data.explore)) if interrupted else -1
	if not pending or desired != target:
		pending = true
		desired = target
		elapsed = 0
		return -2  # Stop the previous track during the source transition gap.
	elapsed += seconds
	if elapsed <= float(data.combat_delay if desired else data.explore_delay):
		return -1
	combat = desired
	pending = false
	track = int(
		data.combat[random.randi_range(0, data.combat.size() - 1)] if combat else data.explore
	)
	return track
