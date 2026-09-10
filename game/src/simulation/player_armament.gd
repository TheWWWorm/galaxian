extends RefCounted
## Imported muzzle declarations become native profiles with stable save identities.
const Combat = preload("res://src/simulation/combat.gd")
const Guidance = preload("res://src/simulation/guidance.gd")
const MAX_MUZZLES := 32
# A separate identity preserves pre-muzzle projectiles until they expire. It is
# never returned as a fitted weapon or offered to the player for firing.
const LEGACY_MOUNT := MAX_MUZZLES


static func valid(value: Variant, library) -> bool:
	if not value is Dictionary or value.is_empty():
		return false
	for id in library.items.size():
		if library.weapon_ballistics(id).is_empty() == value.has(str(id)):
			return false
	for key in value:
		if (
			not key is String
			or str(int(key)) != key
			or library.weapon_ballistics(int(key)).is_empty()
		):
			return false
		var gun: Variant = value[key]
		if (
			not gun is Dictionary
			or not gun.get("mounts") is Array
			or gun.mounts.is_empty()
			or gun.mounts.size() > MAX_MUZZLES
		):
			return false
		if (
			not gun.mounts.all(func(point): return Combat.valid_vector(point))
			or not Combat.integer(gun.get("trigger_muzzle"))
			or gun.trigger_muzzle < 0
			or gun.trigger_muzzle >= gun.mounts.size()
		):
			return false
		if not model(gun.get("projectile_model"), library):
			return false
		if (
			gun.has("projectile_overlay")
			and (
				not Combat.integer(gun.projectile_overlay)
				or (gun.projectile_overlay > 0 and not model(gun.projectile_overlay, library))
			)
		):
			return false
		if (
			gun.has("projectile_color")
			and (
				not Combat.integer(gun.projectile_color)
				or gun.projectile_color < 0
				or gun.projectile_color > 4294967295
			)
		):
			return false
		if gun.has("trail"):
			if (
				not gun.trail is Dictionary
				or not bounded_integer(gun.trail.get("style"), 0, 11)
				or not bounded_integer(gun.trail.get("segments"), 1, 4096)
			):
				return false
		if gun.has("guidance") and not Guidance.valid_parameters(gun.guidance):
			return false
		if gun.has("ballistics"):
			if not gun.ballistics is Array or gun.ballistics.size() != gun.mounts.size():
				return false
			for shot in gun.ballistics:
				if (
					not shot is Dictionary
					or not bounded_integer(shot.get("pool_capacity"), 1, 4096)
				):
					return false
				for field in ["damage", "reload_ms", "lifetime_ms", "speed_per_ms"]:
					if not bounded_integer(shot.get(field), 1, 3600000):
						return false
		else:
			if (
				not bounded_integer(gun.get("damage_divisor"), 1, 65536)
				or not bounded_integer(gun.get("pool_capacity"), 1, 4096)
			):
				return false
	return true


static func bounded_integer(value: Variant, low: int, high: int) -> bool:
	return Combat.integer(value) and value >= low and value <= high


static func model(value: Variant, library) -> bool:
	return (
		Combat.integer(value)
		and library.content.resources.get(str(int(value)), {}).get("path", "").ends_with(".aem")
	)


static func weapon_ids(weapon: int, library) -> Array[int]:
	var result: Array[int] = []
	var declaration: Dictionary = library.content.player_armament.get(str(weapon), {})
	for index in declaration.get("mounts", []).size():
		result.append(weapon + index * library.items.size())
	return result


static func profiles(library, target_ids: Array) -> Dictionary:
	var result := {}
	for key in library.content.player_armament:
		var weapon := int(key)
		var declaration: Dictionary = library.content.player_armament[key]
		var ids := weapon_ids(weapon, library)
		var catalogue: Dictionary = library.weapon_ballistics(weapon)
		var interval := float(catalogue.interval)
		if declaration.has("ballistics"):
			interval = (
				float(declaration.ballistics[int(declaration.trigger_muzzle)].reload_ms) / 1000.0
			)
		for index in ids.size():
			var gun := catalogue.duplicate(true)
			gun.damage = int(float(gun.damage) / int(declaration.get("damage_divisor", 1)))
			gun.pool_capacity = int(declaration.get("pool_capacity", 1))
			if declaration.has("ballistics"):
				var parameters: Dictionary = declaration.ballistics[index]
				gun.damage = int(parameters.damage)
				gun.pool_capacity = int(parameters.pool_capacity)
				gun.lifetime = float(parameters.lifetime_ms) / 1000.0
				gun.speed = float(parameters.speed_per_ms) * 20.0
			gun.interval = interval
			gun.cooldown_limit = maxf(interval, float(catalogue.interval))
			gun.trigger_weapon = ids[int(declaration.trigger_muzzle)]
			gun.mount_offset = declaration.mounts[index].duplicate()
			gun.team = "ally"
			for property in ["projectile_model", "projectile_color", "trail", "guidance"]:
				if declaration.has(property):
					gun[property] = declaration[property]
			if int(declaration.get("projectile_overlay", -1)) > 0:
				gun.projectile_overlay = int(declaration.projectile_overlay)
			if gun.has("guidance"):
				gun.guidance_target_ids = target_ids.duplicate()
			result[ids[index]] = gun
		var legacy := catalogue.duplicate(true)
		legacy.legacy_projectile = true
		legacy.team = "ally"
		result[weapon + LEGACY_MOUNT * library.items.size()] = legacy
	return result


static func migrate_combat(value: Variant, library) -> Variant:
	if (
		not value is Dictionary
		or not value.get("projectiles") is Array
		or not value.get("cooldowns") is Dictionary
	):
		return null
	var result: Dictionary = value.duplicate(true)
	for shot in result.projectiles:
		if not shot is Dictionary or not Combat.integer(shot.get("weapon")):
			return null
		if shot.weapon >= 0:
			if library.weapon_ballistics(int(shot.weapon)).is_empty():
				return null
			shot.weapon = int(shot.weapon) + LEGACY_MOUNT * library.items.size()
	# A saved trigger wait belongs to the complete fitted weapon. Preserve its
	# remaining duration; subsequent volleys use the imported first-muzzle period.
	result.cooldowns = {}
	for key in value.cooldowns:
		if not (key is int or key is String) or str(int(key)) != str(key):
			return null
		var weapon := int(key)
		if weapon >= 0:
			var previous: Dictionary = library.weapon_ballistics(weapon)
			if (
				previous.is_empty()
				or not Combat.number(value.cooldowns[key])
				or value.cooldowns[key] < 0
				or value.cooldowns[key] > previous.interval
			):
				return null
			var ids := weapon_ids(weapon, library)
			if ids.is_empty():
				return null
			weapon = ids[int(library.content.player_armament[str(weapon)].trigger_muzzle)]
		result.cooldowns[weapon] = value.cooldowns[key]
	return result
