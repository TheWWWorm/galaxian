extends RefCounted
## Import-only reader for data embedded in the ARM32 iPhone application.
## This is a bounded file-format recognizer, not an ARM interpreter. It reads
## named constant arrays and a few compiler data-initialization patterns. It
## neither follows game control flow nor translates original routines to Godot.
## Only normalized data leaves this object; executable bytes are discarded.

var error := ""
var bytes := PackedByteArray()
var segments: Array[Dictionary] = []
var symbols := {}
var addresses: Array[int] = []
var reporter := Callable()

const TABLES := {
	"dialogue_characters": "__ZL19DIALOGUE_CHARACTERS",
	"dialogue_starts": "__ZL18DIALOGUE_START_IDS",
	"dialogue_ids": "__ZL12DIALOGUE_IDS",
	"dialogue_lengths": "__ZL16DIALOGUE_LENGHTS",
	"campaign_rewards": "__ZL7REWARDS",
	"campaign_destinations": "__ZL15TARGET_STATIONS",
	"campaign_stock_lengths": "__ZL21CAMPAIGN_LIST_LENGHTS",
	"campaign_stock_starts": "__ZL23CAMPAIGN_LIST_START_IDS",
	"campaign_stock": "__ZL13CAMPAIGN_LIST",
	"buyable_ships": "__ZL13BUYABLE_SHIPS",
	"actor_meshes": "__ZL6MESHES",
	"actor_hull": "__ZL2HP",
	"actor_collision": "__ZL4COLL",
	"contract_min_rewards": "__ZL11MIN_REWARDS",
	"contract_max_rewards": "__ZL11MAX_REWARDS",
	"buyable_equipment": "__ZL21BUYABLE_EQUIPMENT_IDS",
	"quadrant_difficulty": "__ZL19QUADRANT_DIFFICULTY",
}


func extract(source: PackedByteArray, report: Callable = Callable()) -> Dictionary:
	error = ""
	reporter = report
	bytes = source
	segments.clear()
	symbols.clear()
	addresses.clear()
	var result := {}
	if checkpoint("Reading application index") and parse_macho():
		result = extract_content()
	bytes = PackedByteArray()
	segments.clear()
	symbols.clear()
	addresses.clear()
	reporter = Callable()
	return result if error.is_empty() else {}


func checkpoint(message: String = "") -> bool:
	if not error.is_empty():
		return false
	if reporter.is_valid() and not reporter.call(message):
		return fail("Import cancelled.")
	return true


func read_phase(message: String, read: Callable) -> Dictionary:
	return read.call() if checkpoint(message) else {}


func fail(message: String) -> bool:
	if error.is_empty():
		error = message
	return false


func valid_range(offset: int, length: int) -> bool:
	return offset >= 0 and length >= 0 and offset <= bytes.size() - length


func parse_macho() -> bool:
	if not valid_range(0, 28) or bytes.decode_u32(0) != 0xfeedface or bytes.decode_u32(4) != 12:
		return fail("Unsupported application layout: expected ARM32 Mach-O content.")
	var count := bytes.decode_u32(16)
	var command_end := 28 + bytes.decode_u32(20)
	if count > 256 or not valid_range(28, command_end - 28):
		return fail("Invalid application command table.")
	var offset := 28
	var symtab := {}
	for index in count:
		if offset + 8 > command_end:
			return fail("Truncated application command.")
		var command := bytes.decode_u32(offset)
		var size := bytes.decode_u32(offset + 4)
		if size < 8 or size % 4 != 0 or offset + size > command_end:
			return fail("Invalid application command size.")
		if command == 1:
			if size < 56:
				return fail("Truncated application segment.")
			var segment := {
				"address": bytes.decode_u32(offset + 24),
				"offset": bytes.decode_u32(offset + 32),
				"size": bytes.decode_u32(offset + 36),
			}
			if not valid_range(segment.offset, segment.size):
				return fail("Application segment lies outside the file.")
			segments.append(segment)
		elif command == 2:
			if size < 24 or not symtab.is_empty():
				return fail("Invalid application symbol table command.")
			symtab = {
				"offset": bytes.decode_u32(offset + 8),
				"count": bytes.decode_u32(offset + 12),
				"strings": bytes.decode_u32(offset + 16),
				"length": bytes.decode_u32(offset + 20),
			}
		elif command == 0x21:
			if size < 20 or bytes.decode_u32(offset + 16) != 0:
				return fail("Application data is encrypted and cannot be read by this importer.")
		offset += size
	if offset != command_end or symtab.is_empty():
		return fail("This build has no supported content symbol table.")
	if (
		symtab.count > 200000
		or not valid_range(symtab.offset, symtab.count * 12)
		or not valid_range(symtab.strings, symtab.length)
	):
		return fail("Application symbol table lies outside the file.")
	for index in int(symtab.count):
		if index % 256 == 0 and not checkpoint():
			return false
		var entry := int(symtab.offset) + index * 12
		var kind := bytes[entry + 4]
		var address := bytes.decode_u32(entry + 8)
		var string_index := bytes.decode_u32(entry)
		if kind & 0xe0 or kind & 0x0e != 0x0e or address == 0:
			continue
		if string_index >= int(symtab.length):
			return fail("Invalid symbol name reference.")
		var name := string_at_file(
			int(symtab.strings) + string_index, int(symtab.strings) + int(symtab.length)
		)
		if not error.is_empty():
			return false
		if not symbols.has(name):
			symbols[name] = []
		symbols[name].append(address)
		addresses.append(address)
	addresses.sort()
	return true


func string_at_file(offset: int, end: int) -> String:
	var cursor := offset
	while cursor < mini(end, offset + 2048):
		if bytes[cursor] == 0:
			return bytes.slice(offset, cursor).get_string_from_utf8()
		cursor += 1
	fail("Unterminated application string.")
	return ""


func file_offset(address: int, length: int) -> int:
	for segment in segments:
		if (
			address >= int(segment.address)
			and address + length <= int(segment.address) + int(segment.size)
		):
			return int(segment.offset) + address - int(segment.address)
	return -1


func u16(address: int) -> int:
	var offset := file_offset(address, 2)
	return bytes.decode_u16(offset) if offset >= 0 else -1


func u32(address: int) -> int:
	var offset := file_offset(address, 4)
	return bytes.decode_u32(offset) if offset >= 0 else -1


func symbol_address(name: String) -> int:
	if not symbols.has(name):
		fail("Unsupported content build: missing " + name)
		return -1
	return int(symbols[name][0])


func symbol_end(address: int) -> int:
	var index := addresses.bsearch(address, false)
	while index < addresses.size() and addresses[index] <= address:
		index += 1
	return addresses[index] if index < addresses.size() else address


func int_array(address: int, count: int) -> Array:
	var offset := file_offset(address, count * 4)
	if count <= 0 or count > 16384 or offset < 0:
		fail("Invalid embedded content array.")
		return []
	var result: Array = []
	for index in count:
		result.append(bytes.decode_s32(offset + index * 4))
	return result


func named_array(name: String) -> Array:
	var address := symbol_address(name)
	if address < 0:
		return []
	var length := symbol_end(address) - address
	if length % 4 != 0:
		fail("Unsupported embedded table boundary: " + name)
		return []
	var result := int_array(address, length / 4)
	for duplicate in symbols[name]:
		if int_array(duplicate, length / 4) != result:
			fail("Conflicting embedded table copies: " + name)
	return result


func call_target(address: int) -> int:
	# ARMv5 Thumb BL uses two halfwords and a signed 23-bit displacement.
	var offset := file_offset(address, 4)
	if offset < 0:
		return -1
	var first := bytes.decode_u16(offset)
	if first & 0xf800 != 0xf000:
		return -1
	var second := bytes.decode_u16(offset + 2)
	if (second & 0xf800) not in [0xf800, 0xe800]:
		return -1
	var displacement := ((first & 0x7ff) << 12) | ((second & 0x7ff) << 1)
	if displacement & 0x400000:
		displacement -= 0x800000
	var target := address + 4 + displacement
	return target & ~3 if second & 0xf800 == 0xe800 else target


func calls_between(start: int, end: int, target_name: String) -> Array[int]:
	var target := symbol_address(target_name)
	var result: Array[int] = []
	if target < 0 or start < 0 or end - start > 131072:
		return result
	for address in range(start, end - 2, 2):
		if (address - start) % 2048 == 0 and not checkpoint():
			return []
		if call_target(address) == target:
			result.append(address)
	return result


func literal(address: int, register: int) -> int:
	var opcode := u16(address)
	if opcode < 0 or opcode & 0xff00 != 0x4800 | (register << 8):
		return -1
	return u32(((address + 4) & ~3) + (opcode & 0xff) * 4)


func extract_content() -> Dictionary:
	if not checkpoint("Reading campaign and catalogue tables"):
		return {}
	var tables := {}
	for key in TABLES:
		tables[key] = named_array(TABLES[key])
	if not error.is_empty():
		return {}
	var count: int = tables.campaign_rewards.size()
	for key in [
		"dialogue_characters",
		"dialogue_starts",
		"dialogue_lengths",
		"campaign_stock_lengths",
		"campaign_stock_starts"
	]:
		if tables[key].size() != count:
			fail("Embedded campaign tables disagree about chapter count.")
	if (
		tables.campaign_destinations.size() != count * 2
		or tables.actor_meshes.size() != tables.actor_hull.size()
		or tables.actor_collision.size() != tables.actor_hull.size()
	):
		fail("Embedded content table dimensions disagree.")
	var chapters: Array = []
	for index in count:
		var start: int = tables.dialogue_starts[index]
		var length: int = tables.dialogue_lengths[index]
		var stock_start: int = tables.campaign_stock_starts[index]
		var stock_length: int = tables.campaign_stock_lengths[index]
		if (
			start < 0
			or length <= 0
			or start + length > tables.dialogue_ids.size()
			or stock_start < 0
			or stock_length < 0
			or stock_start + stock_length > tables.campaign_stock.size()
		):
			fail("Invalid embedded campaign slice.")
			return {}
		(
			chapters
			. append(
				{
					"id": index,
					"dialogue": tables.dialogue_ids.slice(start, start + length),
					"speaker": tables.dialogue_characters[index],
					"reward": tables.campaign_rewards[index],
					"destination": tables.campaign_destinations.slice(index * 2, index * 2 + 2),
					"stock": tables.campaign_stock.slice(stock_start, stock_start + stock_length),
				}
			)
		)
	var resources := read_phase("Reading model and texture associations", resource_bindings)
	if not checkpoint():
		return {}
	var destination_quadrant := campaign_destination_quadrant()
	var names := localization_bindings()
	var opening := read_phase("Reading campaign encounters", opening_definition.bind(count))
	if not checkpoint():
		return {}
	var missions := campaign_definitions(count, opening)
	if not checkpoint("Reading campaign dialogue"):
		return {}
	var radio := radio_definitions(count, missions.size())
	for index in mini(missions.size(), radio.size()):
		missions[index]["radio"] = radio[index]
	var initial := read_phase("Reading initial pilot", initial_pilot)
	var economy := read_phase("Reading market rules", economy_definition)
	return {
		"schema": 1,
		"tables": tables,
		"chapters": chapters,
		"campaign_quadrant": destination_quadrant,
		"resources": resources,
		"materials": read_phase("Reading materials", material_definitions.bind(resources)),
		"lighting": read_phase("Reading lighting", lighting_presentation),
		"station_models":
		read_phase("Reading station models", station_presentation.bind(resources)),
		"ship_exhaust":
		read_phase(
			"Reading ship engines", ship_exhaust.bind(resources, tables.actor_meshes.size())
		),
		"briefing_scene": read_phase("Reading briefing scenes", briefing_scene_presentation),
		"localization": names,
		"opening": opening,
		"missions": missions,
		"initial": initial,
		"economy": economy,
		"radio_ui": read_phase("Reading radio interface", radio_presentation),
		"menu_traffic": read_phase("Reading menu traffic", menu_traffic),
		"title_ui": read_phase("Reading title interface", title_menu_presentation),
		"station_ui": read_phase("Reading station interface", station_menu_presentation),
		"hangar_ui": read_phase("Reading Hangar catalogue artwork", hangar_presentation),
		"options_ui": read_phase("Reading options menu artwork", options_presentation),
		"pause_ui": read_phase("Reading pause menu artwork", pause_presentation),
		"defeat_ui": read_phase("Reading defeat presentation", defeat_presentation),
		"board_ui": read_phase("Reading mission-board presentation", mission_board_presentation),
		"briefing_ui": read_phase("Reading briefing interface", briefing_presentation),
		"flight_ui": read_phase("Reading flight interface", flight_presentation),
		"map_ui": read_phase("Reading map interface", map_presentation),
		"map_icons": read_phase("Reading map symbols", map_icons),
		"travel": read_phase("Reading travel rules", travel_rules),
		"sky": read_phase("Reading space backgrounds", sky_presentation),
		"player_motion": read_phase("Reading ship motion", player_motion),
		"fighter_steering": read_phase("Reading fighter steering", fighter_steering),
		"fighter_evasion": read_phase("Reading fighter maneuvers", fighter_evasion),
		"fighter_motion": read_phase("Reading fighter speed", fighter_motion),
		"fighter_targeting": read_phase("Reading fighter targeting", fighter_targeting),
		"fighter_impact": read_phase("Reading fighter impact response", fighter_impact),
		"npc_exhaust": read_phase("Reading fighter burner effects", npc_exhaust),
		"mine_behavior": read_phase("Reading mine behavior", mine_behavior.bind(resources)),
		"contracts": read_phase("Reading freelance encounters", contract_rules),
		"recovery": read_phase("Reading cargo recovery", loot_rules),
		"survival": read_phase("Reading survival mode", survival_content),
		"player_armament": read_phase("Reading player weapons", player_armament),
		"projectile_trails": read_phase("Reading projectile trails", projectile_trail_presentation),
		"lens_flare": read_phase("Reading sun flares", lens_flare_presentation),
		"sound_bank": read_phase("Reading sound resources", sound_bank),
		"player_hit": read_phase("Reading player hit effects", player_hit_presentation),
		"actor_destruction": read_phase(
			"Reading actor explosions", actor_destruction.bind(resources, tables.actor_meshes.size())
		)
	}


func ship_exhaust(resources: Dictionary, actor_count: int) -> Dictionary:
	var add := symbol_address("__ZN7Booster10addBoosterEhiiijjj")
	var mesh_table := add + 0x3a
	if (
		bytes[file_offset(mesh_table, 1)] != 4
		or (
			call_target(add + 0x14c)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		)
	):
		fail("Unsupported engine exhaust mesh declarations.")
		return {}
	var meshes := []
	for kind in 4:
		var branch := mesh_table + 2 * int(bytes[file_offset(mesh_table + 1 + kind, 1)])
		var mesh_id := literal(branch, 2)
		if not resources.get(str(mesh_id), {}).get("path", "").ends_with(".aem"):
			fail("Missing registered engine exhaust mesh.")
			return {}
		meshes.append(mesh_id)
	var result := {}
	var associations := {
		"player": ["__ZN9PlayerEgo7setShipEi", 0xe6, 0xe8, 0x15a],
		"actors": ["__ZN13PlayerFighter15replaceShipMeshEi", 0xea, 0xe4, 0x12c]
	}
	for key in associations:
		var binding: Array = associations[key]
		var start := symbol_address(binding[0])
		if call_target(start + int(binding[3])) != add:
			fail("Unsupported ship exhaust attachment binding.")
			return {}
		var index_address := literal(start + int(binding[1]), 3 if key == "player" else 2)
		var data_address := literal(start + int(binding[2]), 2 if key == "player" else 1)
		if (
			not symbols.get("__ZL13BOOSTER_INDEX", []).has(index_address)
			or not symbols.get("__ZL12BOOSTER_DATA", []).has(data_address)
		):
			fail("Unknown ship exhaust attachment tables.")
			return {}
		var indices := int_array(index_address, actor_count)
		var actors := []
		for index in indices:
			var entry := data_address + int(index) * 4
			if index < 0 or entry + 4 > symbol_end(data_address):
				fail("Invalid ship exhaust table index.")
				return {}
			var count: int = int_array(entry, 1)[0]
			var nozzles := []
			if (
				count < -1
				or count > 16
				or (count > 0 and entry + count * 32 > symbol_end(data_address))
			):
				fail("Invalid ship exhaust nozzle count.")
				return {}
			if count > 0:
				for nozzle in count:
					var kind: int = int_array(entry + nozzle * 32 + 4, 1)[0]
					if kind < 0 or kind >= meshes.size():
						fail("Unsupported engine exhaust type.")
						return {}
					var values := int_array(entry + nozzle * 32 + 8, 6)
					if values[3] <= 0 or values[3] != values[4] or values[5] <= 0:
						fail("Invalid engine exhaust dimensions.")
						return {}
					nozzles.append(
						{
							"mesh": meshes[kind],
							"position": [values[0], values[1], -values[2]],
							"scale": [values[3] / 100.0, values[4] / 100.0, values[5] / 100.0]
						}
					)
			actors.append(nozzles)
		result[key] = actors
	return result


func campaign_destination_quadrant() -> int:
	var start := symbol_address("__ZN5MGame11finishLevelEv")
	var stations := calls_between(start, symbol_end(start), "__ZN6Galaxy10getStationEiii")
	if (
		stations.size() != 1
		or literal(stations[0] - 18, 1) != symbol_address("__ZL15TARGET_STATIONS")
	):
		fail("Unsupported campaign destination association.")
		return -1
	return immediate_at(stations[0] - 6, 1)


func matched_value(function: String, pattern: Array, field: int) -> int:
	# A signature describes a compiler representation of a constant, not a game
	# routine. Only the requested immediate byte becomes runtime content.
	var start := symbol_address(function)
	var matches: Array[int] = []
	for address in range(start, symbol_end(start) - pattern.size() * 2 + 1, 2):
		var matches_pattern := true
		for index in pattern.size():
			if u16(address + index * 2) & int(pattern[index][0]) != int(pattern[index][1]):
				matches_pattern = false
				break
		if matches_pattern:
			matches.append(u16(address + field * 2) & 255)
	if matches.size() != 1:
		fail("Unsupported embedded rule initialization in " + function)
		return -1
	return matches[0]


func immediate_at(address: int, register: int) -> int:
	if u16(address) & 0xff00 != 0x2000 | (register << 8):
		fail("Unsupported embedded immediate parameter at 0x%x (r%d)." % [address, register])
		return -1
	return u16(address) & 255


func float_constant(function: String) -> float:
	var start := symbol_address(function)
	var values: Array[float] = []
	for address in range(start, symbol_end(start), 2):
		var bits := literal(address, 1)
		if bits < 0:
			continue
		var data := PackedByteArray()
		data.resize(4)
		data.encode_u32(0, bits)
		var value := data.decode_float(0)
		if is_finite(value) and value > 0.001 and value < 10000:
			values.append(value)
	if values.is_empty() or values.any(func(value): return value != values[0]):
		fail("Unsupported embedded price constant in " + function)
		return 0
	return values[0]


func economy_definition() -> Dictionary:
	var equipment_function := "__ZN9Generator10getBuyListEP7Station"
	var ship_function := "__ZN9Generator14getShipBuyListEP7Station"
	var equipment_start := symbol_address(equipment_function)
	var ship_start := symbol_address(ship_function)
	var equipment_rolls := calls_between(
		equipment_start, symbol_end(equipment_start), "__ZN11AbyssEngine8AERandom7nextIntEi"
	)
	var ship_rolls := calls_between(
		ship_start, symbol_end(ship_start), "__ZN11AbyssEngine8AERandom7nextIntEi"
	)
	if equipment_rolls.size() != 3 or ship_rolls.size() != 3:
		fail("Unsupported shop stock initialization.")
		return {}
	var equipment_count := immediate_at(equipment_rolls[0] - 2, 1)
	var ship_count := immediate_at(ship_rolls[0] - 8, 1)
	var occurrence_scale := immediate_at(equipment_rolls[2] - 8, 1)
	if u16(equipment_rolls[0] + 6) & 0xff00 != 0x3000:
		fail("Unsupported equipment stock count.")
		return {}
	var equipment_min := u16(equipment_rolls[0] + 6) & 255
	var exclusive_race := matched_value(
		ship_function, [[0xffff, 0x9b0b], [0xff00, 0x2b00], [0xff00, 0xd100]], 1
	)
	var exclusive_actor := matched_value(
		ship_function, [[0xffff, 0x9307], [0xff00, 0x2b00], [0xff00, 0xd000]], 1
	)
	var restricted_race := matched_value(
		ship_function, [[0xffff, 0x9b0b], [0xff00, 0x2b00], [0xff00, 0xd000]], 1
	)
	var restricted_actor := matched_value(
		ship_function, [[0xffff, 0x9a07], [0xff00, 0x2a00], [0xff00, 0xd000]], 1
	)
	var exclusive_items_race := matched_value(
		equipment_function, [[0xffff, 0x9b0b], [0xff00, 0x2b00], [0xff00, 0xd000]], 1
	)
	var restricted_item_boundary := matched_value(
		equipment_function, [[0xffff, 0x990e], [0xff00, 0x2900], [0xff00, 0xdd00]], 1
	)
	var cargo_function := symbol_address("__ZN6Status15calcCargoPricesEv")
	var tech_calls := calls_between(
		cargo_function, symbol_end(cargo_function), "__ZN7Station11getTecLevelEv"
	)
	if tech_calls.size() != 1 or equipment_count <= 0 or ship_count <= 0 or occurrence_scale <= 0:
		fail("Invalid recovered economy parameters.")
		return {}
	return {
		"equipment_min": equipment_min,
		"equipment_max": equipment_count + equipment_min - 1,
		"ship_max": ship_count - 1,
		"occurrence_scale": occurrence_scale,
		"exclusive_ship_race": exclusive_race,
		"exclusive_ship_actor": exclusive_actor,
		"restricted_ship_race": restricted_race,
		"restricted_ship_actor": restricted_actor,
		"exclusive_equipment_race": exclusive_items_race,
		"exclusive_equipment_after": restricted_item_boundary,
		"equipment_resale_factor": float_constant("__ZN9Equipment12priceDeclineEv"),
		"ship_resale_factor": float_constant("__ZN4Ship12priceDeclineEv"),
		"ship_technology_divisor": float_constant("__ZN4Ship11adjustPriceEi"),
		"cargo_technology_max": immediate_at(tech_calls[0] + 6, 0),
		"cargo_technology_divisor": float_constant("__ZN6Status15calcCargoPricesEv"),
	}


func resource_bindings() -> Dictionary:
	var start := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var end := symbol_end(start)
	var result := {}
	for call in calls_between(start, end, "__ZN11AbyssEngine12ResourceMeshC2EPct"):
		var path := ""
		var material_id := -1
		for address in range(call - 2, call - 34, -2):
			if material_id < 0:
				material_id = literal(address, 2)
			var pointer := literal(address, 1)
			var offset := file_offset(pointer, 1)
			if offset >= 0 and path.is_empty():
				path = string_at_file(offset, bytes.size())
		var resource_id := -1
		var branch := u16(call + 4)
		if branch & 0xf800 != 0xe000:
			fail("Unsupported resource registration boundary.")
			return {}
		var displacement := (branch & 0x7ff) * 2
		if displacement & 0x800:
			displacement -= 0x1000
		var record := call + 8 + displacement
		for address in range(record, mini(record + 64, end), 2):
			# STRH r3,[r0] initializes the resource record identifier.
			if u16(address) == 0x8003:
				for cursor in range(address - 2, address - 18, -2):
					resource_id = literal(cursor, 3)
					if u16(cursor) & 0xff00 == 0x2300:
						resource_id = u16(cursor) & 255
						var shift := u16(cursor + 2)
						if shift & 0xf83f == 0x001b:
							resource_id <<= (shift >> 6) & 31
					if resource_id >= 0:
						break
				break
		if (
			resource_id < 0
			or material_id < 0
			or not path.begins_with("data/meshes/")
			or not path.ends_with(".aem")
			or path.contains("..")
		):
			fail(
				(
					"Unsupported mesh registration at %x (id %d, material %d, path %s)."
					% [call, resource_id, material_id, path]
				)
			)
			return {}
		if result.has(str(resource_id)):
			fail("Duplicate mesh resource identifier.")
		result[str(resource_id)] = {"path": path, "material_id": material_id}
	if result.is_empty():
		fail("No mesh resource associations were recovered.")
	return result


func material_definitions(resources: Dictionary) -> Dictionary:
	var modes := material_modes()
	if modes.is_empty():
		return {}
	var registry := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var end := symbol_end(registry)
	var imports := imported_symbols()
	var result := {}
	var required := {}
	for mesh in resources.values():
		required[int(mesh.material_id)] = true
	# Match each mesh's resource identifier to an eight-byte material declaration,
	# followed by its type-six resource descriptor. Only data fields are retained.
	for address in range(registry, end, 2):
		if u16(address) != 0x8003:
			continue
		var identifier := ui_constant_before(address, 3)
		if not required.has(identifier):
			continue
		var kind := -1
		for at in range(address - 6, address + 8, 2):
			if u16(at) & 0xfff8 == 0x6040:
				kind = ui_constant_before(at, u16(at) & 7)
		if kind != 6:
			continue
		var payload := -1
		for at in range(address - 6, address - 34, -2):
			if u16(at) & 0xfff8 == 0x8000 and u16(at + 2) & 0xfff8 == 0x6040:
				payload = at
				break
		if (
			payload < 0
			or immediate_at(payload - 12, 0) != 8
			or not imports.get("__Znwm", []).has(call_target(payload - 10))
		):
			fail("Unsupported material resource record.")
			return {}
		var texture := ui_constant_before(payload, u16(payload) & 7)
		var flags := ui_constant_before(payload + 2, u16(payload + 2) & 7)
		if texture < 0 or not modes.has(str(flags)) or result.has(str(identifier)):
			fail("Unknown or duplicated material texture/render association.")
			return {}
		var material: Dictionary = modes[str(flags)].duplicate()
		material.texture = texture
		result[str(identifier)] = material
	if result.size() != required.size():
		fail("A mesh material has no supported resource declaration.")
		return {}
	return result


func material_modes() -> Dictionary:
	var end := symbol_address("__ZN11AbyssEngine11PaintCanvas5End3dEv")
	var blend := symbol_address("__ZN11AbyssEngine11PaintCanvas12SetBlendModeENS_9BlendModeE")
	var imports := imported_symbols()
	# Confirm fixed-function state semantics before normalizing material passes.
	for pair in [
		[0x14, "_glEnable"],
		[0x1a, "_glDisable"],
		[0x24, "_glEnable"],
		[0x2c, "_glDisable"],
		[0x32, "_glEnable"],
		[0x50, "_glEnable"],
		[0x56, "_glEnable"],
		[0x5e, "_glBlendFunc"],
		[0x64, "_glDepthMask"]
	]:
		if not imports.get(pair[1], []).has(call_target(blend + pair[0])):
			fail("Unsupported material blend function association.")
			return {}
	if (
		literal(blend + 0x12, 0) != 0xb44
		or literal(blend + 0x18, 0) != 0xbe2
		or immediate_at(blend + 0x36, 0) != 1
		or immediate_at(blend + 0x38, 1) != 1
		or literal(blend + 0x5a, 0) != 0x302
		or literal(blend + 0x5c, 1) != 0x303
	):
		fail("Unsupported material blend factors.")
		return {}
	var targets := contract_choice_targets(blend + 6, blend)
	var choices := {
		blend + 0x12: {"blend": "opaque", "cull": "back"},
		blend + 0x4e: {"blend": "mix", "cull": "back"},
		blend + 0x22: {"blend": "add", "cull": "back"},
		blend + 0x2a: {"blend": "add", "cull": "disabled"}
	}
	if (
		immediate_at(end + 0x3c, 0) != 0xb5
		or u16(end + 0x3e) != 0x0100
		or not imports.get("_glEnable", []).has(call_target(end + 0x40))
		or not imports.get("_glDisable", []).has(call_target(end + 0x104))
	):
		fail("Unsupported material lighting declaration.")
		return {}
	var result := {}
	var passes := [
		[0x1e, 6, 0x26, false],
		[0xe0, 6, 0xe8, true],
		[0x120, 0x10a, 0x128, false],
		[0x150, 0x13a, 0x158, false],
		[0x180, 0x16a, 0x188, false]
	]
	for index in passes.size():
		var row: Array = passes[index]
		var mode := immediate_at(end + row[1], 1)
		if (
			u16(end + row[0]) & 0xff00 != 0x2b00
			or mode < 0
			or mode >= targets.size()
			or not choices.has(targets[mode])
			or call_target(end + row[1] + (4 if index < 2 else 2)) != blend
			or (
				call_target(end + row[2])
				!= symbol_address(
					"__ZN11AbyssEngine12MaterialDrawEPNS_11PaintCanvasEPNS_6EngineEPNS_8MaterialE"
				)
			)
		):
			fail("Unsupported material render pass declaration.")
			return {}
		var flags := u16(end + row[0]) & 255
		if result.has(str(flags)):
			fail("Conflicting material render flags.")
			return {}
		var data: Dictionary = choices[targets[mode]].duplicate()
		data.lit = row[3]
		data.order = index
		result[str(flags)] = data
	return result


func localization_bindings() -> Dictionary:
	var start := symbol_address("__ZN13EquipmentList12drawItemInfoEPvi")
	var end := symbol_end(start)
	var result := {}
	for pair in [["ships", "__ZN4Ship8getIndexEv"], ["items", "__ZN9Equipment8getIndexEv"]]:
		for call in calls_between(start, end, pair[1]):
			var shift := u16(call + 4)
			var add := u16(call + 6)
			# LSL r1,r0,#n; ADD r1,#base; load text service; BL getText.
			if (
				shift & 0xf83f == 1
				and add & 0xff00 == 0x3100
				and call_target(call + 10) == symbol_address("__ZN8GameText7getTextEi")
			):
				var binding := {"stride": 1 << ((shift >> 6) & 31), "base": add & 255}
				if result.has(pair[0]) and result[pair[0]] != binding:
					fail("Conflicting catalogue localization associations.")
				result[pair[0]] = binding
	if result.size() != 2:
		fail("Unsupported catalogue localization layout.")
	return result


func opening_definition(chapter_count: int) -> Dictionary:
	var start := symbol_address("__ZN5Level21createCampaignMissionEv")
	var switches := calls_between(start, start + 128, "___switch32")
	if switches.size() != 1:
		fail("Unsupported campaign dispatch table.")
		return {}
	var table := switches[0] + 4
	if u32(table) != chapter_count:
		fail("Campaign dispatch disagrees with chapter data.")
		return {}
	var first := table + u32(table + 4)
	var end := table + u32(table + 8)
	if first < table or end <= first or end > symbol_end(start):
		fail("Invalid opening mission boundary.")
		return {}
	var route_calls := calls_between(first, end, "__ZN5RouteC1EPii")
	var target_calls := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ship_calls := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	if route_calls.size() != 1 or target_calls.size() != 1 or ship_calls.size() != 2:
		fail("The opening scenario uses an unsupported layout.")
		return {}
	if (
		u16(route_calls[0] - 4) & 0xff00 != 0x2200
		or u16(target_calls[0] - 4) & 0xff00 != 0x2000
		or u16(ship_calls[0] - 6) & 0xff00 != 0x2300
	):
		fail("Unsupported opening parameter initialization.")
		return {}
	var coordinates := int_array(literal(first, 3), u16(route_calls[0] - 4) & 255)
	var target_count := u16(target_calls[0] - 4) & 255
	var actor_type := u16(ship_calls[0] - 6) & 255
	if (
		coordinates.size() % 3 != 0
		or coordinates.size() < 3
		or target_count <= 0
		or target_count > 128
		or actor_type < 0
	):
		fail("Invalid opening scenario data.")
		return {}
	var route: Array = []
	for index in range(0, coordinates.size(), 3):
		route.append(coordinates.slice(index, index + 3))
	var encounter := opening_encounter(first, end, route, target_count, actor_type, ship_calls)
	if encounter.is_empty():
		return {}
	return {
		"route": route,
		"target_count": target_count,
		"actor_type": actor_type,
		"encounter": encounter
	}


func opening_encounter(
	first: int, end: int, route: Array, count: int, actor: int, ships: Array
) -> Dictionary:
	var sleeps := calls_between(first, end, "__ZN8KIPlayer10setToSleepEv")
	var speeds := calls_between(first, end, "__ZN8KIPlayer8setSpeedEf")
	var fields := calls_between(first, end, "__ZN13AsteroidFieldC1EiP8Waypoint")
	var fogs := calls_between(first, end, "__ZN3FogC1EP8Waypoint")
	var positions := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var routes := calls_between(first, end, "__ZN8KIPlayer8setRouteEP5Route")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if [sleeps, speeds, fields, fogs, positions, routes, objectives].any(
		func(calls): return calls.size() != 1
	):
		fail("Unsupported opening encounter associations.")
		return {}
	var target := int(ships[0])
	var friend := int(ships[1])
	var position := int(positions[0])
	var waypoint := immediate_at(target - 42, 1)
	var field_waypoint := immediate_at(fields[0] - 34, 1)
	var fog_waypoint := immediate_at(fogs[0] - 24, 1)
	var variant := immediate_at(fields[0] - 6, 1)
	var speed := literal_float(speeds[0] - 6, 1) * 20.0
	var factory_start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var switches := calls_between(factory_start, factory_start + 1024, "___switch32")
	if switches.size() != 1:
		fail("Unsupported opening ship factory dispatch.")
		return {}
	var table := switches[0] + 4
	var role := immediate_at(target - 12, 2)
	if role < 0 or role >= u32(table):
		fail("Unknown opening target role.")
		return {}
	var branch := table + u32(table + 4 + role * 4)
	# Bind role to the moving fighter constructor, its unarmed catalogue subtype,
	# and the source sleep/speed declarations. Export data, never executable code.
	var assign := symbol_address("__ZN5Level10assignGunsEv")
	var unarmed := calls_between(assign, symbol_end(assign), "__ZN8KIPlayer7getTypeEv").filter(
		func(call): return u16(call + 4) == (0x2800 | actor) and u16(call + 6) & 0xff00 == 0xd000
	)
	if (
		waypoint < 0
		or waypoint >= route.size()
		or field_waypoint < 0
		or field_waypoint >= route.size()
		or fog_waypoint < 0
		or fog_waypoint >= route.size()
		or speed <= 0
		or speed > 1000000
		or call_target(target - 18) != symbol_address("__ZN5Route11getWaypointEi")
		or immediate_at(target - 14, 3) != 1
		or u16(target - 10) != 0x9300
		or u16(target - 4) != 0x9001
		or call_target(target + 14) != symbol_address("__ZN8KIPlayer10setToSleepEv")
		or call_target(branch + 38) != symbol_address("__ZN13PlayerFighterC1EibP6Playeriii")
		or unarmed.size() != 1
		or immediate_at(friend - 22, 3) != 0
		or immediate_at(friend - 10, 2) != 0
		or immediate_at(friend - 8, 1) != 0
		or u16(friend - 6) != 0x9300
		or u16(friend - 4) != 0x9301
		or (
			call_target(position - 40)
			!= symbol_address("__ZN11AbyssEngine6AEMath17MatrixGetPositionERKNS0_6MatrixE")
		)
		or u16(position - 22) != 0x0092
		or u16(position - 20) != 0x1889
		or u16(position - 10) != 0x1912
		or u16(position - 2) != 0x191b
		or call_target(routes[0] - 8) != symbol_address("__ZN5Route5cloneEv")
		or call_target(fields[0] - 22) != symbol_address("__ZN5Route11getWaypointEi")
		or call_target(fogs[0] - 20) != symbol_address("__ZN5Route11getWaypointEi")
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
	):
		fail("Unsupported opening target, companion or scenery declaration.")
		return {}
	var combat := interceptor_combat()
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(0, difficulty)
	if combat.is_empty() or factory.is_empty():
		return {}
	var offset := [
		immediate_at(position - 26, 2) << 2,
		signed_literal(position - 18, 4),
		signed_literal(position - 6, 4)
	]
	var fog := fog_presentation()
	fog.waypoint = fog_waypoint
	return {
		"route": route,
		"groups":
		[
			{
				"count": count,
				"actor": actor,
				"center": route[waypoint],
				"scatter": factory.scatter,
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"unarmed": true,
				"hull_rule": factory.hull_rule,
				"motion": dict_with_speed(combat.motion, speed)
			},
			{
				"count": 1,
				"actor": immediate_at(friend - 22, 3),
				"team": "ally",
				"center": offset,
				"scatter": [],
				"placement": "player_offset",
				"after_route": false,
				"behavior": "escort",
				"route": route,
				"hull_rule": factory.hull_rule,
				"motion": combat.motion,
				"weapon": friendly_weapon(combat.weapon)
			}
		],
		"deadline_ms": 0,
		"success": {"kind": "enemies_destroyed"},
		"scenery": [asteroid_field_definition(variant, field_waypoint)],
		"fog": fog
	}


func campaign_boundaries(chapter_count: int) -> Array[int]:
	var start := symbol_address("__ZN5Level21createCampaignMissionEv")
	var switches := calls_between(start, start + 128, "___switch32")
	if switches.size() != 1 or u32(switches[0] + 4) != chapter_count:
		fail("Unsupported campaign dispatch table.")
		return []
	var table := switches[0] + 4
	var bounds: Array[int] = []
	for index in chapter_count + 1:
		var address := table + u32(table + 4 + index * 4)
		if (
			address < table
			or address > symbol_end(start)
			or (not bounds.is_empty() and address <= bounds.back())
		):
			fail("Invalid campaign data boundary.")
			return []
		bounds.append(address)
	return bounds


func campaign_definitions(chapter_count: int, opening: Dictionary) -> Array:
	var bounds := campaign_boundaries(chapter_count)
	if bounds.size() < 3 or opening.is_empty():
		return []
	var missions: Array = [opening.encounter.duplicate(true)]
	# The next constructor declares a local spawn route which is destroyed at
	# the end of construction. It is not attached as the player's flight route.
	var first := bounds[1]
	var end := bounds[2]
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var objects := calls_between(first, end, "__ZN5Level18createStaticObjectEP8Waypointi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var destroy := calls_between(first, end, "__ZN5RouteD1Ev")
	if (
		routes.size() != 1
		or arrays.size() != 1
		or objects.size() != 1
		or objectives.size() != 1
		or destroy.size() != 1
	):
		fail("Unsupported timed clearance definition.")
		return []
	var center := int_array(literal(first, 3), immediate_at(routes[0] - 6, 2))
	var count := immediate_at(arrays[0] - 6, 0)
	var actor := immediate_at(objects[0] - 8, 2)
	var objective := immediate_at(objectives[0] - 8, 1)
	var parameter := immediate_at(objectives[0] - 6, 2)
	var deadline := literal(objectives[0] + 14, 2)
	var getter := symbol_address("__ZN5Level12getTimeLimitEv")
	if (
		center.size() != 3
		or count <= 0
		or count > 128
		or actor < 0
		or objective != 0
		or parameter != 0
		or deadline <= 0
		or deadline > 86400000
	):
		fail("Invalid timed clearance parameters.")
		return []
	if (
		u16(objectives[0] + 16) != 0x6163
		or u16(objectives[0] + 18) != u16(getter)
		or u16(objectives[0] + 20) != 0x50e2
	):
		fail("Unsupported mission deadline field association.")
		return []
	missions.append(
		{
			"route": [],
			"groups":
			[
				{
					"count": count,
					"actor": actor,
					"center": center,
					"scatter": static_scatter(),
					"after_route": false
				}
			],
			"deadline_ms": deadline,
			"success": {"kind": "enemies_destroyed"}
		}
	)
	if bounds.size() >= 4:
		missions.append(interception_definition(bounds[2], bounds[3]))
	if bounds.size() >= 5:
		missions.append(escort_definition(bounds[3], bounds[4], 3))
	if bounds.size() >= 6:
		missions.append(assault_definition(bounds[4], bounds[5], 4))
	if bounds.size() >= 7:
		missions.append(duel_definition(bounds[5], bounds[6], 5))
	if bounds.size() >= 8:
		missions.append(convoy_definition(bounds[6], bounds[7], 6))
	if bounds.size() >= 9:
		missions.append(cruiser_attack_definition(bounds[7], bounds[8], 7))
	if bounds.size() >= 10:
		missions.append(cargo_rescue_definition(bounds[8], bounds[9], 8))
	if bounds.size() >= 11:
		missions.append(fleet_strike_definition(bounds[9], bounds[10], 9))
	if bounds.size() >= 12:
		missions.append(nebula_ambush_definition(bounds[10], bounds[11], 10))
	if bounds.size() >= 13:
		missions.append(pursuit_definition(bounds[11], bounds[12], 11))
	if bounds.size() >= 14:
		missions.append(finale_definition(bounds[12], bounds[13], 12))
	return missions


func literal_float(address: int, register: int) -> float:
	var bits := literal(address, register)
	if bits < 0:
		fail("Unsupported embedded floating point constant.")
		return 0
	var data := PackedByteArray()
	data.resize(4)
	data.encode_u32(0, bits)
	var value := data.decode_float(0)
	if not is_finite(value):
		fail("Invalid embedded floating point constant.")
		return 0
	return value


func interception_definition(first: int, end: int) -> Dictionary:
	# This layout declares one sleeping interceptor at each route waypoint and
	# a route-completion objective. It must not become a generic kill-all job.
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var waypoints := calls_between(first, end, "__ZN5Route11getWaypointEi")
	var sleeps := calls_between(first, end, "__ZN8KIPlayer10setToSleepEv")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if [routes, arrays, ships, waypoints, sleeps, hulls, objectives].any(
		func(calls): return calls.size() != 1
	):
		fail("Unsupported interceptor mission declaration.")
		return {}
	var coordinates := int_array(literal(first, 3), immediate_at(routes[0] - 4, 2))
	var count := immediate_at(arrays[0] - 2, 0)
	var actor := immediate_at(ships[0] - 10, 3)
	var objective := immediate_at(objectives[0] - 8, 1)
	var parameter := immediate_at(objectives[0] - 6, 2)
	var deadline := literal(objectives[0] + 14, 2)
	# Confirm the same loop index supplies the waypoint, and the returned
	# waypoint is passed to createShip. No native engine code runs this loop.
	if (
		u16(waypoints[0] - 24) & 0xff00 != 0x9900
		or u16(waypoints[0] - 28) & 0xff00 != 0x9b00
		or (u16(waypoints[0] - 24) & 255) != (u16(waypoints[0] - 28) & 255)
		or u16(ships[0] - 4) != 0x9001
		or u16(objectives[0] + 16) != u16(symbol_address("__ZN5Level12getTimeLimitEv"))
		or u16(objectives[0] + 18) != 0x6145
		or u16(objectives[0] + 20) != 0x50c2
	):
		fail("Unsupported interceptor route or deadline association.")
		return {}
	var hull_call := hulls[0]
	var globals := symbol_address("__ZN7GlobalsC2Ev")
	var options := symbol_address("__ZN7Globals7optionsE")
	# The source default difficulty lives in Globals::options at field 0x1c.
	# Decode its declaration and the mission's affine hull adjustment as data.
	if (
		literal(globals + 60, 3) != options
		or u16(globals + 84) != 0x61d8
		or u32(literal(hull_call - 30, 3)) != options
		or u16(hull_call - 26) != 0x69d8
	):
		fail("Unsupported mission hull difficulty association.")
		return {}
	var difficulty := literal_float(globals + 64, 0)
	var offset := literal_float(hull_call - 40, 1)
	var scale := literal_float(hull_call - 20, 1)
	var base := literal_float(hull_call - 14, 1)
	var hull := int(base + scale * (difficulty - offset))
	if (
		count <= 0
		or count > 128
		or coordinates.size() != count * 3
		or actor < 0
		or objective != 2
		or parameter != 0
		or deadline <= 0
		or deadline > 86400000
		or hull <= 0
		or hull > 10000000
	):
		fail("Invalid interceptor mission parameters.")
		return {}
	var route: Array = []
	for index in range(0, coordinates.size(), 3):
		route.append(coordinates.slice(index, index + 3))
	var combat := interceptor_combat()
	return {
		"route": route,
		"groups":
		[
			{
				"count": count,
				"actor": actor,
				"center": route[0],
				"scatter": fighter_factory_data(2, difficulty).get("scatter", []),
				"after_route": false,
				"placement": "waypoints",
				"behavior": "interceptor",
				"sleeping": true,
				"hull": hull,
				"motion": combat.get("motion", {}),
				"weapon": combat.get("weapon", {})
			}
		],
		"deadline_ms": deadline,
		"success": {"kind": "route_finished"}
	}


func route_points(coordinates: Array) -> Array:
	var result: Array = []
	if coordinates.is_empty() or coordinates.size() % 3 != 0:
		fail("Invalid embedded route coordinates.")
		return []
	for index in range(0, coordinates.size(), 3):
		result.append(coordinates.slice(index, index + 3))
	return result


func signed_literal(address: int, register: int) -> int:
	var value := literal(address, register)
	return value - 0x100000000 if value > 0x7fffffff else value


func escort_definition(first: int, end: int, chapter: int) -> Dictionary:
	# Recover a declaration with separate player/escort routes, two enemy spawn
	# ranges, a required friendly actor, and compound success/failure conditions.
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var additions := calls_between(first, end, "__ZN9Objective12addObjectiveEPS_")
	var positions := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var fields := calls_between(first, end, "__ZN13AsteroidFieldC1EiP8Waypoint")
	var texts := calls_between(first, end, "__ZN8GameText7getTextEi")
	var prefixes := calls_between(first, end, "__ZN11AbyssEngine6StringC1EPKc")
	var sleeps := calls_between(first, end, "__ZN8KIPlayer10setToSleepEv")
	if (
		routes.size() != 2
		or ships.size() != 2
		or objectives.size() != 3
		or [arrays, hulls, additions, positions, fields, sleeps, texts, prefixes].any(
			func(calls): return calls.size() != 1
		)
	):
		fail("Unsupported escort mission declaration.")
		return {}
	var route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 4, 2)))
	var escort_route := route_points(
		int_array(literal(routes[1] - 36, 1), immediate_at(routes[1] - 6, 2))
	)
	var count := immediate_at(arrays[0] - 6, 0)
	var split := u16(ships[0] - 32) & 255
	var near_waypoint := immediate_at(ships[0] - 28, 1)
	var far_waypoint := immediate_at(ships[0] - 24, 1)
	# The branch divides actor indexes at the imported comparison boundary.
	# This is a two-range data encoding, not an executable loop in the engine.
	if (
		u16(ships[0] - 32) & 0xff00 != 0x2a00
		or u16(ships[0] - 30) & 0xff00 != 0xd800
		or u16(ships[0] - 4) != 0x9001
		or u16(ships[1] - 10) != 0x9300
		or u16(ships[1] - 8) != 0x9301
	):
		fail("Unsupported escort actor placement association.")
		return {}
	var enemy_actor := immediate_at(ships[0] - 12, 3)
	var friend_actor := immediate_at(ships[1] - 4, 3)
	var offset := [
		signed_literal(positions[0] - 30, 2),
		signed_literal(positions[0] - 20, 4),
		immediate_at(positions[0] - 8, 4) << ((u16(positions[0] - 6) >> 6) & 31)
	]
	if u16(positions[0] - 6) & 0xf83f != 0x0024:
		fail("Unsupported escort position offset.")
		return {}
	var hull_call := hulls[0]
	var globals := symbol_address("__ZN7GlobalsC2Ev")
	var options := symbol_address("__ZN7Globals7optionsE")
	if u32(literal(hull_call - 32, 3)) != options or u16(hull_call - 28) != 0x69d8:
		fail("Unsupported escort hull difficulty association.")
		return {}
	var difficulty := literal_float(globals + 64, 0)
	var hull := int(
		(
			literal_float(hull_call - 14, 0)
			- literal_float(hull_call - 22, 1) * (difficulty - literal_float(hull_call - 42, 1))
		)
	)
	if (
		count <= 0
		or count > 128
		or split >= count - 1
		or near_waypoint < 0
		or far_waypoint < 0
		or near_waypoint >= route.size()
		or far_waypoint >= route.size()
		or enemy_actor < 0
		or friend_actor < 0
		or hull <= 0
	):
		fail("Invalid escort content parameters.")
		return {}
	# Objective tags: route reached, all enemies dead, selected friend dead.
	# The addObjective relation means all attached success predicates must hold.
	if (
		immediate_at(objectives[0] - 8, 1) != 2
		or immediate_at(objectives[1] - 8, 1) != 0
		or immediate_at(objectives[2] - 8, 1) != 5
		or immediate_at(objectives[0] - 6, 2) != 0
		or immediate_at(objectives[1] - 6, 2) != 0
		or u16(objectives[0] + 22) != 0x6148
		or u16(objectives[2] + 18) != 0x619a
		or u16(additions[0] - 6) != u16(objectives[1] - 2) + 0x900
		or u16(additions[0] - 4) != u16(objectives[0] - 2) + 0x800
	):
		fail("Unsupported escort success/failure association.")
		return {}
	var combat := interceptor_combat()
	var factory := fighter_factory_data(chapter, difficulty)
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var speed := literal_float(fighter + 0x27e, 3) * 20.0
	var placements: Array = []
	for index in count:
		placements.append(route[near_waypoint if index <= split else far_waypoint].duplicate())
	return {
		"route": route,
		"groups":
		[
			{
				"count": count,
				"actor": enemy_actor,
				"center": route[near_waypoint],
				"positions": placements,
				"placement": "points",
				"scatter": factory.get("scatter", []),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"motion": combat.get("motion", {}),
				"weapon": combat.get("weapon", {}),
				"hull_rule": factory.get("hull_rule", {})
			},
			{
				"count": 1,
				"actor": friend_actor,
				"center": offset,
				"scatter": [],
				"after_route": false,
				"placement": "player_offset",
				"team": "ally",
				"behavior": "escort",
				"route": escort_route,
				"motion": dict_with_speed(combat.get("motion", {}), speed),
				"weapon": friendly_weapon(combat.get("weapon", {})),
				"hull": hull
			}
		],
		"deadline_ms": 0,
		"success":
		{"kind": "all", "conditions": [{"kind": "route_finished"}, {"kind": "enemies_destroyed"}]},
		"failure": {"kind": "ally_destroyed", "index": immediate_at(objectives[2] - 6, 2)},
		"failure_text": literal(texts[0] - 8, 1),
		"failure_prefix": embedded_string(literal(prefixes[0] - 12, 1)),
		"scenery":
		[asteroid_field_definition(immediate_at(fields[0] - 6, 1), immediate_at(fields[0] - 32, 1))]
	}


func assault_definition(first: int, end: int, chapter: int) -> Dictionary:
	# Separate source array ranges describe fighters, fixed targets and allies.
	# Normalize declarations only; the native encounter system owns their behavior.
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var initial := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var positions := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var moving := calls_between(first, end, "__ZN17PlayerFixedObject9setMovingEb")
	if (
		[routes, hulls, initial, objectives, moving].any(func(calls): return calls.size() != 1)
		or arrays.size() != 2
		or ships.size() != 3
		or positions.size() != 2
		or calls_between(first, end, "__ZN8KIPlayer10setToSleepEv").size() != 2
		or calls_between(first, end, "__ZN8KIPlayer8setRouteEP5Route").size() != 1
		or calls_between(first, end, "__ZN5Level12createTurretEP8KIPlayerbi").size() != 0
	):
		fail("Unsupported assault mission declaration.")
		return {}
	var route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 6, 2)))
	var count := immediate_at(arrays[0] - 10, 0)
	var boundary := u16(ships[0] + 28) & 255
	if (
		route.size() != 1
		or boundary % 4 != 0
		or boundary <= 0
		or boundary / 4 >= count
		or u16(ships[0] + 28) & 0xff00 != 0x2a00
		or immediate_at(ships[0] + 34, 3) != boundary
		or u16(ships[1] + 36) != 0x2c00 + count * 4
		or immediate_at(ships[0] - 10, 2) != 0
		or immediate_at(ships[1] - 8, 2) != 3
		or immediate_at(ships[2] - 30, 2) != 0
		or u16(ships[0] - 6) != 0x9300
		or u16(ships[1] - 12) != 0x9200
		or immediate_at(ships[1] - 14, 2) != 1
		or immediate_at(ships[2] - 14, 3) != 0
		or u16(ships[2] - 12) != 0x9300
		or u16(ships[2] - 10) != 0x9301
		or immediate_at(moving[0] - 12, 1) != 0
		or immediate_at(arrays[1] - 6, 0) != positions.size()
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
		or u16(objectives[0] + 16) != 0x6148
		or u16(initial[0] - 10) != 0x681b
		or u32(literal(hulls[0] - 32, 3)) != symbol_address("__ZN7Globals7optionsE")
		or u16(hulls[0] - 28) != 0x69d8
	):
		fail("Unsupported assault actor/objective associations.")
		return {}
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var hull := int(
		(
			literal_float(hulls[0] - 14, 0)
			- literal_float(hulls[0] - 22, 1) * (difficulty - literal_float(hulls[0] - 48, 1))
		)
	)
	var initial_hp := literal(initial[0] - 12, 1)
	var offset := signed_literal(positions[0] - 18, 4)
	var placements := [
		[offset, offset, shifted_immediate(positions[0] - 8, 5)],
		[
			shifted_immediate(positions[1] - 16, 3),
			immediate_at(positions[1] - 26, 5) << ((u16(positions[1] - 22) >> 6) & 31),
			shifted_immediate(positions[1] - 6, 5)
		]
	]
	if hull <= 0 or initial_hp <= 0 or u16(positions[1] - 22) & 0xf83f != 0x002d:
		fail("Invalid assault friendly hull or position declaration.")
		return {}
	var combat := interceptor_combat()
	var factory := fighter_factory_data(chapter, difficulty)
	var groups: Array = [
		{
			"count": boundary / 4,
			"actor": immediate_at(ships[0] - 12, 3),
			"center": route[0],
			"scatter": factory.get("scatter", []),
			"after_route": false,
			"behavior": "interceptor",
			"sleeping": true,
			"motion": combat.get("motion", {}),
			"weapon": combat.get("weapon", {}),
			"hull_rule": factory.get("hull_rule", {})
		},
		{
			"count": count - boundary / 4,
			"actor": immediate_at(ships[1] - 6, 3),
			"center": route[0],
			"scatter": factory.get("scatter", []),
			"after_route": false,
			"behavior": "stationary",
			"sleeping": true,
			"wake_half_width": fixed_activation(),
			"collision": fixed_collision(immediate_at(ships[1] - 6, 3)),
			"hull_rule": factory.get("hull_rule", {}),
			"source_scale": true
		}
	]
	var speed := (
		literal_float(symbol_address("__ZN13PlayerFighterC2EibP6Playeriii") + 0x27e, 3) * 20.0
	)
	for index in placements.size():
		var ally := {
			"count": 1,
			"actor": immediate_at(ships[2] - 2, 3),
			"center": placements[index],
			"scatter": [],
			"after_route": false,
			"placement": "player_offset",
			"team": "ally",
			"behavior": "escort",
			"route": route,
			"hull": hull,
			"motion": dict_with_speed(combat.get("motion", {}), speed),
			"weapon": friendly_weapon(combat.get("weapon", {}))
		}
		if index == 0:
			ally.initial_hp = initial_hp
		groups.append(ally)
	return {
		"route": [], "groups": groups, "deadline_ms": 0, "success": {"kind": "enemies_destroyed"}
	}


func convoy_definition(first: int, end: int, chapter: int) -> Dictionary:
	var data := convoy_parameters(first, end)
	if data.is_empty():
		return {}
	var bodies := convoy_bodies(int(data.cargo.actor))
	var tracking := turret_tracking()
	var combat := interceptor_combat()
	var factory := fighter_factory_data(
		chapter, literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	)
	if bodies.is_empty() or tracking.is_empty() or combat.is_empty() or factory.is_empty():
		return {}
	var groups: Array = [
		{
			"count": data.fighters.count,
			"actor": data.fighters.actor,
			"placement": "points",
			"positions": data.fighters.positions,
			"center": data.fighters.positions[0],
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"sleeping": true,
			"hull_rule": factory.hull_rule,
			"motion": combat.motion,
			"weapon": combat.weapon
		},
		{
			"count": 1,
			"actor": data.capital.actor,
			"placement": "points",
			"positions": [data.capital.position],
			"center": data.capital.position,
			"scatter": [],
			"after_route": false,
			"behavior": "stationary",
			"combat_active": data.capital.combat_active,
			"wake_half_width": fixed_activation(),
			"hull_rule": factory.hull_rule,
			"source_scale": true,
			"collisions": bodies.capital
		}
	]
	for index in int(data.turrets.count):
		var mount: Array = data.turrets.mounts.positions[index]
		var position: Array = []
		for axis in 3:
			position.append(data.capital.position[axis] + mount[axis])
		groups.append(
			{
				"count": 1,
				"actor": data.turrets.mounts.actor,
				"placement": "points",
				"positions": [position],
				"center": position,
				"scatter": [],
				"after_route": false,
				"behavior": "turret",
				"sleeping": true,
				"hull": data.turrets.hull,
				"source_scale": true,
				"facing": data.turrets.mounts.facing[index],
				"tracking": tracking,
				"weapon": data.turrets.weapon
			}
		)
	for offset in data.cargo.offsets:
		groups.append(
			{
				"count": 1,
				"actor": data.cargo.actor,
				"placement": "player_offset",
				"center": offset,
				"scatter": [],
				"after_route": false,
				"team": "ally",
				"behavior": "transit",
				"hull": data.cargo.hull,
				"source_scale": true,
				"velocity": [0, 0, -bodies.speed],
				"collision": bodies.cargo
			}
		)
	return {
		"route": [],
		"groups": groups,
		"deadline_ms": 0,
		"enemy_goal": data.enemy_goal,
		"success": data.success,
		"failure": data.failure,
		"failure_text": data.failure_text,
		"sequence": convoy_sequence(chapter)
	}


func convoy_sequence(chapter: int) -> Array:
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	if u16(script + 40) & 0xfe00 != 0x1e00 or chapter != base + 1:
		fail("Unsupported convoy event dispatch.")
		return []
	var first := table + u16(table + 4) * 2
	var end := symbol_end(script)
	if u16(table) <= 0 or u16(table) > 128:
		fail("Invalid event dispatch extent.")
		return []
	for index in u16(table):
		var boundary := table + u16(table + 2 + index * 2) * 2
		if boundary > first:
			end = mini(end, boundary)
	var triggers := calls_between(first, end, "__ZN12RadioMessage11isTriggeredEv")
	if triggers.size() != 1 or u16(first + 86) & 0xff00 != 0x2c00:
		fail("Unsupported convoy camera trigger.")
		return []
	var message := indexed_reference(triggers[0] - 2, 0, 3)
	if indexed_reference(end - 4, 0, 3) != message:
		fail("Unsupported convoy camera release.")
		return []
	return [
		{
			"when": {"kind": "message_shown", "message": message},
			"actions":
			[
				{"kind": "lock", "value": true},
				{
					"kind": "focus_active",
					"first": immediate_at(first + 38, 4),
					"count": (u16(first + 86) & 255) / 4,
					"offset":
					[
						signed_literal(first + 112, 1),
						shifted_immediate(first + 116, 2),
						signed_literal(first + 114, 3)
					],
					"target_offset": [0, 0, shifted_immediate(first + 96, 3)]
				}
			]
		},
		{
			"when": {"kind": "message_finished", "message": message},
			"actions":
			[{"kind": "lock", "value": false}, {"kind": "focus", "actor": -1, "offset": [0, 0, 0]}]
		}
	]


func capital_collision() -> Array:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var first := factory + 0x522
	var second := factory + 0x566
	var third := factory + 0x5ac
	var expected := symbol_address("__ZN11BoundingAABC1Eiiiiiiiii")
	if (
		[first, second, third].any(func(call): return call_target(call) != expected)
		or u16(first - 34) != 0x425b
		or u16(third - 26) != 0x425b
	):
		fail("Unsupported capital-ship collision declarations.")
		return []
	var boxes: Array = [
		{
			"offset":
			[
				immediate_at(first - 40, 3),
				-immediate_at(first - 36, 3),
				shifted_immediate(first - 30, 3)
			],
			"size": [literal(first - 24, 3), literal(first - 16, 3), literal(first - 12, 3)]
		},
		{
			"offset":
			[
				immediate_at(second - 38, 3),
				signed_literal(second - 34, 3),
				signed_literal(second - 26, 3)
			],
			"size":
			[literal(second - 22, 3), shifted_immediate(second - 18, 3), literal(second - 12, 3)]
		},
		{
			"offset":
			[
				immediate_at(third - 40, 3),
				signed_literal(third - 36, 3),
				-immediate_at(third - 28, 3)
			],
			"size":
			[literal(third - 22, 3), shifted_immediate(third - 18, 3), literal(third - 12, 3)]
		}
	]
	return boxes


func convoy_bodies(cargo_actor: int) -> Dictionary:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var cargo := factory + 0x700
	var boxes := capital_collision()
	if (
		boxes.is_empty()
		or call_target(cargo) != symbol_address("__ZN11BoundingAABC1Eiiiiiiiii")
		or u16(cargo - 54) != 0x2a00 + cargo_actor
	):
		fail("Unsupported cargo collision declaration.")
		return {}
	var cargo_box := {
		"offset": [immediate_at(cargo - 38, 3), cargo_actor, signed_literal(cargo - 26, 3)],
		"size": [literal(cargo - 22, 3), shifted_immediate(cargo - 18, 3), literal(cargo - 12, 3)]
	}
	# Fixed-object movement uses the model direction, not a waypoint route.
	var update := symbol_address("__ZN17PlayerFixedObject6updateEi")
	var divisor := immediate_at(update + 78, 1)
	var shift := u16(update + 90)
	if divisor <= 0 or shift & 0xf83f != 0:
		fail("Unsupported cargo transit speed.")
		return {}
	return {
		"capital": boxes, "cargo": cargo_box, "speed": (1 << ((shift >> 6) & 31)) * 20.0 / divisor
	}


func turret_tracking() -> Dictionary:
	var start := symbol_address("__ZN12PlayerTurret6updateEi")
	var unit := normalized_vector_unit()
	var turn := u16(start + 718)
	var wake := literal(start + 440, 1)
	var range_limit := literal(start + 578, 0)
	var aim := literal(start + 520, 6)
	# Bounded declaration reader: current opponent position, local X/Y tolerance,
	# forward discharge, then mount rotation. No original AI code is retained.
	if (
		unit <= 0
		or turn & 0xf83f != 0x19
		or wake <= 0
		or range_limit <= 0
		or aim <= 0
		or aim >= unit
		or literal(start + 444, 2) != wake * 2
		or signed_literal(start + 462, 2) != -wake - 1
		or literal(start + 548, 1) != aim * 2
		or signed_literal(start + 568, 3) != -aim - 1
		or literal(start + 582, 2) != range_limit * 2
		or signed_literal(start + 600, 1) != -range_limit - 1
		or call_target(start + 252) != symbol_address("__ZN6Player11getPositionEv")
		or (
			call_target(start + 508)
			!= symbol_address("__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE")
		)
		or (
			call_target(start + 524)
			!= symbol_address("__ZN11AbyssEngine6AEMath16MatrixGetInverseERKNS0_6MatrixE")
		)
		or (
			call_target(start + 534)
			!= symbol_address(
				"__ZN11AbyssEngine6AEMath18MatrixRotateVectorERKNS0_6MatrixERKNS0_6VectorE"
			)
		)
		or u16(start + 564) != 0x429a
		or call_target(start + 642) != symbol_address("__ZN6Player5shootEixb")
		or immediate_at(start + 638, 1) != 0
		or (
			call_target(start + 688)
			!= symbol_address("__ZN11AbyssEngine6AEMath12MatrixGetDirERKNS0_6MatrixE")
		)
	):
		fail("Unsupported turret targeting, firing bounds or steering declarations.")
		return {}
	return {
		"wake_half_width": wake * .02,
		"range_half_width": range_limit * .02,
		"aim_sine": aim / unit,
		"turn_rate": (1 << ((turn >> 6) & 31)) * 1000.0 / unit
	}


func convoy_parameters(first: int, end: int) -> Dictionary:
	# Mission data becomes native role definitions; no original script runs.
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var turrets := calls_between(first, end, "__ZN5Level12createTurretEP8KIPlayerbi")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var positions := calls_between(first, end, "__ZN17PlayerFixedObject11setPositionEiii")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if (
		routes.size() != 1
		or ships.size() != 3
		or arrays.size() != 2
		or turrets.size() != 1
		or hulls.size() != 2
		or positions.size() != 6
		or objectives.size() != 2
	):
		fail("Unsupported convoy declaration.")
		return {}
	var route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 4, 2)))
	var enemy_count := immediate_at(arrays[0] - 14, 0)
	var fighter_count := 0
	# Comparisons are format boundaries, not executable control flow.
	if u16(ships[0] + 28) & 0xff00 != 0x2d00:
		fail("Unsupported convoy fighter range.")
		return {}
	fighter_count = u16(ships[0] + 28) & 255
	var parent := indexed_reference(turrets[0] - 8, 1, 3)
	var turret_first := immediate_at(ships[1] - 28, 5)
	var turret_end := u16(hulls[0] + 10) & 255
	var cargo_count := immediate_at(arrays[1] - 4, 0)
	if (
		route.size() != 2
		or fighter_count < 1
		or fighter_count > 128
		or parent != fighter_count
		or turret_first != parent + 1
		or turret_end != enemy_count
		or turret_end <= turret_first
		or cargo_count != positions.size() - 1
		or u16(routes[0] + 16) != 0x23b0
		or u16(routes[0] + 20) != 0x50c1
		or u16(hulls[0] + 10) & 0xff00 != 0x2800
		or immediate_at(ships[0] - 10, 2) != 0
		or immediate_at(ships[1] - 12, 2) != 1
		or immediate_at(ships[2] - 20, 2) != 3
		or immediate_at(turrets[0] - 12, 2) != 1
		or u16(turrets[0] - 2) != 0x3b00 + turret_first
		or u16(ships[0] - 30) != 0x4251
		or u16(ships[0] - 28) != 0x4311
		or u16(ships[0] - 22) != 0x0fc9
		or call_target(positions[0] + 12) != symbol_address("__ZN8KIPlayer13setInitActiveEb")
		or immediate_at(positions[0] + 6, 1) not in [0, 1]
		or u16(positions[0] + 16) != 0x22d0
		or u16(positions[0] + 24) & 0xff00 != 0x3300
		or u16(positions[0] + 26) != 0x50a3
		or u16(objectives[0] + 20) != 0x6145
		or u16(objectives[1] + 22) != 0x6191
	):
		fail("Unsupported convoy actor or objective associations.")
		return {}
	var duration := literal(objectives[0] - 28, 3)
	if (
		immediate_at(objectives[0] - 12, 1) != 3
		or immediate_at(objectives[1] - 8, 1) != 5
		or immediate_at(objectives[1] - 6, 2) != 0
		or duration <= 0
		or duration > 86400000
	):
		fail("Unsupported convoy survival conditions.")
		return {}
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var turret_hull := int(
		(
			literal_float(hulls[0] - 14, 1)
			+ literal_float(hulls[0] - 20, 1) * (difficulty - literal_float(hulls[0] - 42, 1))
		)
	)
	var cargo_hull := int(
		(
			literal_float(hulls[1] - 14, 0)
			- literal_float(hulls[1] - 22, 1) * (difficulty - literal_float(hulls[1] - 48, 1))
		)
	)
	var offsets: Array = [
		[
			signed_literal(positions[1] - 60, 4),
			signed_literal(positions[1] - 20, 3),
			signed_literal(positions[1] - 6, 5)
		]
	]
	for index in range(2, 5):
		offsets.append(
			[
				signed_literal(positions[index] - 12, 3),
				signed_literal(positions[index] - 20, 5),
				signed_literal(positions[index] - 4, 5)
			]
		)
	offsets.append(
		[
			shifted_immediate(positions[5] - 16, 3),
			signed_literal(positions[5] - 24, 5),
			shifted_immediate(positions[5] - 6, 5)
		]
	)
	var actor := immediate_at(ships[1] - 8, 3)
	var mounts := turret_mounts(actor, turret_end - turret_first)
	var weapon := turret_weapon(int(mounts.get("actor", -1)))
	if not error.is_empty() or mounts.is_empty() or turret_hull <= 0 or cargo_hull <= 0:
		return {}
	var fighter_points: Array = []
	for index in fighter_count:
		fighter_points.append(route[0 if index == 0 else 1])
	return {
		"enemy_route": route,
		"enemy_goal": enemy_count - (u16(positions[0] + 24) & 255),
		"fighters":
		{
			"count": fighter_count,
			"actor": immediate_at(ships[0] - 8, 3),
			"positions": fighter_points
		},
		"capital":
		{
			"actor": actor,
			"index": parent,
			"combat_active": immediate_at(positions[0] + 6, 1) != 0,
			"position":
			[
				immediate_at(positions[0] - 14, 1),
				immediate_at(positions[0] - 16, 2),
				signed_literal(positions[0] - 2, 3)
			]
		},
		"turrets":
		{
			"count": turret_end - turret_first,
			"first": turret_first,
			"hull": turret_hull,
			"mounts": mounts,
			"weapon": weapon
		},
		"cargo":
		{
			"actor": immediate_at(ships[2] - 2, 3),
			"count": cargo_count,
			"hull": cargo_hull,
			"offsets": offsets
		},
		"success": {"kind": "time_survived", "duration_ms": duration},
		"failure": {"kind": "allies_destroyed"},
		"failure_text": shifted_immediate(objectives[1] + 24, 1)
	}


func turret_weapon(actor: int) -> Dictionary:
	var start := symbol_address("__ZN5Level10assignGunsEv")
	var calls := calls_between(start, symbol_end(start), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return u16(call + 16) == 0x2288 and u16(call + 20) == 0x508b
	)
	if calls.size() != 1:
		fail("Unsupported turret weapon declaration.")
		return {}
	var gun := int(calls[0])
	if (
		u16(gun - 122) != 0x2800 + actor
		or u16(gun - 26) != 0x9101
		or u16(gun - 24) != 0x9300
		or u16(gun - 110) & 0xff00 != 0x3000
	):
		fail("Unsupported turret weapon field association.")
		return {}
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var result: Dictionary = combat.weapon.duplicate(true)
	var base := u16(gun - 110) & 255
	var factor := (
		1 + literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0) - literal_float(gun - 102, 1)
	)
	var rank := immediate_at(symbol_address("__ZN6StatusC2Ev") + 16, 4)
	result.damage_rule.base = base
	result.damage_rule.minimum = 0
	result.damage_rule.factor = factor
	result.damage = int((base + rank / int(result.damage_rule.level_divisor)) * factor)
	result.interval = (immediate_at(gun - 34, 3) << ((u16(gun - 28) >> 6) & 31)) / 1000.0
	result.lifetime = result.interval
	result.speed = immediate_at(gun - 30, 1) * 20.0
	result.merge(shared_gun_pool(immediate_at(gun - 8, 2), immediate_at(gun + 16, 2)), true)
	if call_target(gun + 60) != symbol_address("__ZN8KIPlayer6addGunEP3Guni"):
		fail("Unsupported turret weapon ownership.")
		return {}
	result.erase("pool_id")
	return result


func turret_mounts(parent_actor: int, count: int) -> Dictionary:
	var factory := symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	if u16(factory + 70) & 0xff00 != 0x2800 or count <= 0 or count > 32:
		fail("Unsupported turret parent association.")
		return {}
	var special := parent_actor == (u16(factory + 70) & 255)
	var actor := immediate_at(factory + (74 if special else 80), 2 if special else 3)
	var position_table := literal(factory + (250 if special else 290), 2)
	var facing_table := literal(factory + (282 if special else 322), 3)
	if (
		count * 12 > symbol_end(position_table) - position_table
		or count * 12 > symbol_end(facing_table) - facing_table
	):
		fail("Turret mount count exceeds its source table.")
		return {}
	var positions := route_points(int_array(position_table, count * 3))
	var facing := route_points(int_array(facing_table, count * 3))
	return {"actor": actor, "positions": positions, "facing": facing}


func duel_definition(first: int, end: int, chapter: int) -> Dictionary:
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var fields := calls_between(first, end, "__ZN13AsteroidFieldC1EiP8Waypoint")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if (
		routes.size() != 2
		or ships.size() != 2
		or [arrays, hulls, fields, objectives].any(func(calls): return calls.size() != 1)
	):
		fail("Unsupported duel declaration.")
		return {}
	var field_route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 4, 2)))
	var reserve_route := route_points(
		int_array(literal(routes[1] - 32, 3), immediate_at(routes[1] - 6, 2))
	)
	var hull_call := int(hulls[0])
	if (
		field_route.size() != 1
		or reserve_route.size() != 1
		or immediate_at(arrays[0] - 4, 0) != ships.size()
		or u16(routes[0] + 16) != 0x239c
		or u16(routes[0] + 18) != 0x50ca
		or immediate_at(ships[0] - 12, 2) != 0
		or immediate_at(ships[1] - 8, 2) != 0
		or calls_between(first, end, "__ZN8KIPlayer10setToSleepEv").size() != ships.size()
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
		or u16(objectives[0] + 16) != 0x6145
		or u32(literal(hull_call - 30, 3)) != symbol_address("__ZN7Globals7optionsE")
		or u16(hull_call - 26) != 0x69d8
	):
		fail("Unsupported duel actor, field or objective associations.")
		return {}
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var hull := int(
		(
			literal_float(hull_call - 14, 1)
			+ literal_float(hull_call - 20, 1) * (difficulty - literal_float(hull_call - 42, 1))
		)
	)
	var combat := interceptor_combat()
	var factory := fighter_factory_data(chapter, difficulty)
	var field := asteroid_field_definition(
		immediate_at(fields[0] - 6, 1), immediate_at(fields[0] - 28, 1)
	)
	if field.is_empty() or hull <= 0:
		return {}
	field.center = field_route[int(field.waypoint)]
	field.erase("waypoint")
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var speed := literal_float(fighter + 0x27a, 3) * literal_float(fighter + 0x2a0, 1) * 20
	var motion := dict_with_speed(combat.get("motion", {}), speed)
	return {
		"route": [],
		"deadline_ms": 0,
		"scenery": [field],
		"groups":
		[
			{
				"count": 1,
				"actor": immediate_at(ships[0] - 10, 3),
				"center": field_route[0],
				"scatter": factory.get("scatter", []),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull": hull,
				"motion": motion,
				"weapon": combat.get("weapon", {})
			},
			{
				"count": 1,
				"actor": immediate_at(ships[1] - 6, 3),
				"center": reserve_route[0],
				"scatter": factory.get("scatter", []),
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull_rule": factory.get("hull_rule", {}),
				"motion": motion,
				"weapon": scripted_fighter_weapon(chapter, combat.get("weapon", {}))
			}
		],
		"success": {"kind": "enemies_destroyed"},
		"sequence": duel_sequence(chapter, hull)
	}


func scripted_fighter_weapon(chapter: int, base: Dictionary) -> Dictionary:
	var start := symbol_address("__ZN5Level10assignGunsEv")
	var calls := calls_between(start, symbol_end(start), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return u16(call + 14) == 0x208c and u16(call + 18) == 0x5031
	)
	if calls.size() != 1:
		fail("Unsupported scripted fighter weapon.")
		return {}
	var gun := int(calls[0])
	if (
		u16(gun - 132) & 0xff00 != 0x2800
		or u16(gun - 212) != u16(gun - 132)
		or chapter not in [u16(gun - 132) & 255, u16(gun - 200) & 255]
		or u16(gun - 224) & 0xff00 != 0x2800
		or u16(gun - 200) & 0xff00 != 0x2800
		or call_target(gun - 204) != symbol_address("__ZN6Status18getCampaignMissionEv")
		or u16(gun - 36) != 0x9300
		or u16(gun - 32) != 0x9301
	):
		fail("Unsupported scripted weapon chapter association.")
		return {}
	var damage := immediate_at(gun - (128 if chapter == (u16(gun - 132) & 255) else 124), 0)
	var factor := (
		1 + literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0) - literal_float(gun - 116, 1)
	)
	var result := base.duplicate(true)
	result.damage = int(damage * factor)
	result.damage_rule = {
		"base": damage, "level_divisor": 1, "ranked": false, "minimum": 0, "factor": factor
	}
	result.interval = shifted_immediate(gun - 40, 3) / 1000.0
	# The fifth constructor argument is speed; r2 is the projectile pool size.
	result.speed = immediate_at(gun - 34, 3) * 20.0
	result.merge(shared_gun_pool(immediate_at(gun - 26, 2), immediate_at(gun + 14, 0)), true)
	# This constructor is inside the actor assignment loop; each actor retains
	# its newly allocated Gun. The level field is temporary, not a shared pool.
	if call_target(gun + 48) != symbol_address("__ZN8KIPlayer6addGunEP3Guni"):
		fail("Unsupported scripted weapon ownership.")
		return {}
	result.erase("pool_id")
	if result.pool_capacity <= 0:
		fail("Invalid scripted weapon projectile pool.")
		return {}
	result.lifetime = literal(gun - 2, 3) / 1000.0
	return result


func duel_sequence(chapter: int, hull: int) -> Array:
	# Recover the authored encounter milestones as declarative events. The
	# native director owns scheduling, control capture, targeting and cameras.
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	if u16(script + 40) & 0xfe00 != 0x1e00 or chapter != base:
		fail("Unsupported chapter event dispatch.")
		return []
	var first := table + u16(table + 2) * 2
	var end := table + u16(table + 4) * 2
	var health := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var messages := calls_between(first, end, "__ZN12RadioMessage6isOverEv")
	if health.size() != 1 or messages.size() != 2 or u16(first + 58) & 0xf83f != 0x1000:
		fail("Unsupported surrender event declaration.")
		return []
	var victim := indexed_reference(first + 28, 3, 3)
	var visitor := indexed_reference(health[0] + 42, 0, 3)
	var surrender_message := indexed_reference(messages[0] - 2, 0, 3)
	var leave_message := indexed_reference(messages[1] - 2, 0, 3)
	var camera := [
		shifted_immediate(first + 80, 6),
		signed_literal(first + 116, 2),
		immediate_at(first + 118, 3) << ((u16(first + 122) >> 6) & 31)
	]
	var arrival_offset := [0, 0, signed_literal(health[0] + 26, 0)]
	var close_camera := [
		signed_literal(first + 430, 1),
		signed_literal(first + 432, 2),
		signed_literal(first + 434, 3)
	]
	if victim < 0 or visitor < 0 or surrender_message < 0 or leave_message < 0:
		return []
	return [
		{
			"when":
			{
				"kind": "hull_below",
				"actor": victim,
				"value": float(hull) / (1 << ((u16(first + 58) >> 6) & 31))
			},
			"actions":
			[
				{"kind": "lock", "value": true},
				{"kind": "stop", "actor": victim},
				{"kind": "focus", "actor": victim, "offset": camera}
			]
		},
		{
			"when": {"kind": "message_finished", "message": surrender_message},
			"actions":
			[
				{"kind": "health", "actor": victim, "value": immediate_at(health[0] - 8, 1)},
				{
					"kind": "relocate",
					"actor": visitor,
					"relative_to": victim,
					"offset": arrival_offset
				},
				{"kind": "activate", "actor": visitor},
				{"kind": "target", "actor": visitor, "target": victim},
				{"kind": "focus", "actor": visitor, "offset": camera}
			]
		},
		{
			"when": {"kind": "actor_dead", "actor": victim},
			"actions": [{"kind": "focus", "actor": visitor, "offset": close_camera}]
		},
		{
			"when": {"kind": "message_finished", "message": leave_message},
			"actions":
			[
				{"kind": "health", "actor": visitor, "value": immediate_at(script + 0x9de, 1)},
				{"kind": "focus", "actor": -1, "offset": [0, 0, 0]}
			]
		}
	]


func indexed_reference(address: int, destination: int, base: int) -> int:
	var instruction := u16(address)
	if instruction & 0xf83f != 0x6800 | (base << 3) | destination:
		fail("Unsupported indexed event reference.")
		return -1
	return (instruction >> 6) & 31


func shifted_immediate(address: int, register: int) -> int:
	if u16(address + 2) & 0xf83f != register * 9:
		fail("Unsupported shifted content constant.")
		return -1
	return immediate_at(address, register) << ((u16(address + 2) >> 6) & 31)


func fixed_activation() -> float:
	var update := symbol_address("__ZN17PlayerFixedObject6updateEi")
	var calls := calls_between(update, symbol_end(update), "__ZN6Player9setActiveEb").filter(
		func(call): return u16(call - 2) == 0x61b3 and u16(call - 4) == 0x2101
	)
	if calls.size() != 1:
		fail("Unsupported fixed target activation association.")
		return -1
	var wake := int(calls[0])
	var upper := literal(wake - 48, 5)
	if (
		upper <= 0
		or literal(wake - 42, 2) != upper * 2
		or signed_literal(wake - 26, 2) != -upper - 1
	):
		fail("Invalid fixed target activation bounds.")
		return -1
	return upper * .02


func fixed_collision(actor: int) -> Dictionary:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	# Fixed-body subtype branch: center offset followed by full box dimensions.
	var branch := factory + 0x71a
	if u16(branch) & 0xff00 != 0x2a00 or actor != (u16(branch) & 255):
		fail("Unsupported fixed target collision subtype.")
		return {}
	var constructor := branch + 58
	if (
		call_target(constructor) != symbol_address("__ZN11BoundingAABC1Eiiiiiiiii")
		or u16(constructor - 36) != 0x425b
		or u16(constructor - 30) != 0x425b
		or u16(constructor - 40) != 0x9300
		or u16(constructor - 34) != 0x9301
		or u16(constructor - 28) != 0x9302
		or u16(constructor - 20) != 0x9303
		or u16(constructor - 14) != 0x9304
		or u16(constructor - 10) != 0x9305
	):
		fail("Unsupported fixed target collision initializer.")
		return {}
	return {
		"offset":
		[
			immediate_at(constructor - 42, 3),
			-immediate_at(constructor - 38, 3),
			-immediate_at(constructor - 32, 3)
		],
		"size":
		[
			literal(constructor - 26, 3),
			shifted_immediate(constructor - 18, 3),
			literal(constructor - 12, 3)
		]
	}


func embedded_string(address: int) -> String:
	var offset := file_offset(address, 1)
	if offset < 0:
		fail("Invalid embedded content string.")
		return ""
	return string_at_file(offset, mini(offset + 256, bytes.size()))


func asteroid_field_definition(variant: int, waypoint: int) -> Dictionary:
	var field := symbol_address("__ZN13AsteroidFieldC2EiP8Waypoint")
	var asteroid := symbol_address("__ZN8AsteroidC2Ev")
	var collide := symbol_address("__ZN13AsteroidField7collideEN11AbyssEngine6AEMath6VectorEb")
	var update := symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera")
	var contacts := calls_between(update, symbol_end(update), "__ZN9PlayerEgo14levelCollisionEv")
	if (
		variant < 0
		or waypoint < 0
		or contacts.size() != 1
		or u16(field + 0x40) != 0x2b00
		or u16(field + 0x56) != 0x618b
		or u16(asteroid + 24) != 0x6043
	):
		fail("Unsupported asteroid field declaration.")
		return {}
	var contact := int(contacts[0])
	if u16(contact + 10) & 0xff00 != 0x2100 or u16(contact - 12) & 0xf83f != 0x0012:
		fail("Unsupported asteroid contact parameters.")
		return {}
	var width := literal(field + (0x44 if variant == 0 else 0x4c), 3)
	var count := immediate_at(field + (0x46 if variant == 0 else 0x4e), 1 if variant == 0 else 2)
	var radius := literal(collide + 0x8c, 6)
	if literal(collide + 0x92, 2) != radius * 2:
		fail("Unsupported asteroid collision volume.")
		return {}
	var low := literal(asteroid + 0x6a, 3)
	var high := low + literal(asteroid + 0x60, 1) - 1
	return {
		"kind": "asteroid_field",
		"variant": variant,
		"waypoint": waypoint,
		"count": count,
		"width": width,
		"model": literal(asteroid + 0x54, 2),
		"scale_min": low / 65536.0,
		"scale_max": high / 65536.0,
		"radius": radius * .02,
		"hits": immediate_at(asteroid + 0x16, 3) + 1,
		"destruction": asteroid_destruction(),
		"contact_damage": immediate_at(contact + 10, 1),
		"contact_interval":
		(immediate_at(contact - 16, 2) << ((u16(contact - 12) >> 6) & 31)) / 1000.0
	}


func dict_with_speed(motion: Dictionary, speed: float) -> Dictionary:
	var result := motion.duplicate(true)
	result.speed = speed
	return result


func friendly_weapon(enemy: Dictionary) -> Dictionary:
	var assign := symbol_address("__ZN5Level10assignGunsEv")
	var guns := calls_between(assign, symbol_end(assign), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return u16(call + 22) == 0x2080 and u16(call + 26) == 0x5031
	)
	if guns.size() != 1 or enemy.is_empty():
		fail("Unsupported friendly weapon declaration.")
		return {}
	var gun := int(guns[0])
	if (
		u16(gun - 38) & 0xf83f != 0x001b
		or u16(gun - 36) != 0x9300
		or u16(gun - 32) != 0x9301
		or u16(gun - 114) & 0xff00 != 0x3000
	):
		fail("Unsupported friendly weapon parameters.")
		return {}
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factor := 1 - (difficulty - literal_float(gun - 106, 1))
	var base := u16(gun - 114) & 255
	var rank := immediate_at(symbol_address("__ZN6StatusC2Ev") + 16, 4)
	var result := enemy.duplicate(true)
	result.damage_rule.base = base
	result.damage_rule.minimum = 0
	result.damage_rule.factor = factor
	result.damage = int((base + rank / int(result.damage_rule.level_divisor)) * factor)
	result.interval = (immediate_at(gun - 40, 3) << ((u16(gun - 38) >> 6) & 31)) / 1000.0
	result.speed = immediate_at(gun - 34, 3) * 20.0
	result.merge(shared_gun_pool(immediate_at(gun - 26, 2), immediate_at(gun + 22, 0)), true)
	result.lifetime = literal(gun - 2, 3) / 1000.0
	if (
		factor <= 0
		or result.damage <= 0
		or result.interval <= 0
		or result.speed <= 0
		or result.lifetime <= 0
	):
		fail("Invalid friendly weapon parameters.")
		return {}
	return result


func fighter_factory_data(chapter: int, difficulty: float) -> Dictionary:
	var start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	# Common campaign fighter initializer: random spawn cube, catalogue hull,
	# rank multiplier and default-difficulty adjustment. Named source fields
	# and fixed instruction forms bind these values to their data meanings.
	if (
		u16(start + 0x7e) & 0xf83f != 0x0012
		or u16(start + 0x1f4) & 0xf83f != 0
		or u16(start + 0x1f6) != 0x18c0
		or u16(start + 0x1fa) & 0xf83f != 0
	):
		fail("Unsupported fighter factory constants.")
		return {}
	var width := immediate_at(start + 0x7c, 2) << ((u16(start + 0x7e) >> 6) & 31)
	var lower := signed_literal(start + 0x96, 3)
	var offset := literal_float(start + 0x204, 1)
	var scale := (
		(1 + (1 << ((u16(start + 0x1f4) >> 6) & 31))) * (1 << ((u16(start + 0x1fa) >> 6) & 31))
	)
	if width <= 0 or width > 10000000 or lower >= 0 or difficulty - offset <= -1:
		fail("Invalid fighter factory data.")
		return {}
	var divisor := 1
	if chapter == (u16(start + 0x110) & 255):
		if u16(start + 0x110) & 0xff00 != 0x2800:
			fail("Unsupported campaign scatter association.")
			return {}
		divisor = immediate_at(start + 0x136, 1)
		if divisor <= 0:
			fail("Invalid campaign scatter divisor.")
			return {}
	var axis := [lower / divisor, (lower + width - 1) / divisor]
	return {
		"scatter": [axis.duplicate(), axis.duplicate(), axis.duplicate()],
		"hull_rule": {"chapter": chapter, "rank_scale": scale, "factor": 1 + difficulty - offset}
	}


func interceptor_combat() -> Dictionary:
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var initialize := symbol_address("__ZN8KIPlayer10initializeEibP6Playeriiib")
	var update := symbol_address("__ZN13PlayerFighter6updateEi")
	var activation := calls_between(update, symbol_end(update), "__ZN6Player9setActiveEb").filter(
		func(call):
			return (
				u16(call - 2) == 0x61b3
				and u16(call - 8) == 0x2301
				and call_target(call - 68) == symbol_address("__ZN8KIPlayer7isEnemyEv")
			)
	)
	var assign := symbol_address("__ZN5Level10assignGunsEv")
	var guns := calls_between(assign, symbol_end(assign), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return u16(call + 18) == 0x67c8
	)
	var ranks := calls_between(assign, symbol_end(assign), "__ZN6Status8getLevelEv")
	if activation.size() != 1 or guns.size() != 1 or ranks.size() != 1:
		fail(
			(
				"Unsupported interceptor combat declaration (%d activation, %d guns, %d rank references)."
				% [activation.size(), guns.size(), ranks.size()]
			)
		)
		return {}
	var wake := int(activation[0])
	var upper := literal(wake - 56, 1)
	var width := literal(wake - 52, 2)
	var lower := literal(wake - 32, 2)
	if lower & 0x80000000:
		lower -= 0x100000000
	# These stores bind speed, generic rotation metadata and aim error to their
	# declared fields. Fighter steering gains are read separately from its consumer.
	if (
		u16(fighter + 0x288) != 0x61cb
		or u16(initialize + 0x2e0) != 0x6223
		or u16(fighter + 0x182) != 0x0092
		or u16(fighter + 0x184) != 0x50ca
		or upper <= 0
		or upper > 10000000
		or width != upper * 2
		or lower != -upper - 1
	):
		fail("Unsupported interceptor motion or activation fields.")
		return {}
	var speed := literal_float(fighter + 0x27a, 3)
	var turn := immediate_at(initialize + 0x2de, 3)
	var aim_threshold := immediate_at(fighter + 0x180, 2) << 2
	var firing := fighter_firing_bounds()
	if firing.is_empty():
		return {}
	var avoid := immediate_at(fighter + 0x18e, 3) << 4
	var gun := int(guns[0])
	var rank_shift := u16(int(ranks[0]) + 12)
	var pilot := symbol_address("__ZN6StatusC2Ev")
	if (
		u16(gun - 36) != 0x005b
		or u16(gun - 34) != 0x9300
		or rank_shift & 0xf83f != 0x1000
		or u16(pilot + 30) != 0x6184
		or u16(symbol_address("__ZN6Status8getLevelEv")) != 0x6980
	):
		fail("Unsupported enemy gun or initial rank association.")
		return {}
	var rank := immediate_at(pilot + 16, 4)
	var base := immediate_at(call_target(gun - 164), 0)
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var offset := literal_float(gun - 148, 1)
	var minimum := immediate_at(gun - 96, 4)
	var damage := maxi(
		minimum, int((base + (rank >> ((rank_shift >> 6) & 31))) * (1 + difficulty - offset))
	)
	var interval := immediate_at(gun - 38, 3) << 1
	var lifetime := literal(gun - 2, 3)
	var bullet_speed := immediate_at(gun - 30, 2)
	var pool := shared_gun_pool(immediate_at(gun - 4, 2), ((u16(gun + 18) >> 6) & 31) * 4)
	if (
		speed <= 0
		or turn <= 0
		or damage <= 0
		or interval <= 0
		or lifetime <= 0
		or bullet_speed <= 0
	):
		fail("Invalid interceptor combat parameters.")
		return {}
	return {
		"motion":
		{
			"speed": speed * 20,
			"turn_response": turn,
			"aim_sine": float(aim_threshold) / normalized_vector_unit(),
			"fire_half_width": firing.half_width,
			"avoid_distance": avoid * .02,
			"wake_half_width": upper * .02
		},
		"weapon":
		{
			"damage": damage,
			"damage_rule":
			{
				"base": base,
				"level_divisor": 1 << ((rank_shift >> 6) & 31),
				"factor": 1 + difficulty - offset,
				"minimum": minimum
			},
			"interval": interval / 1000.0,
			"lifetime": lifetime / 1000.0,
			"speed": bullet_speed * 20.0,
			"pool_capacity": pool.get("pool_capacity", 0),
			"pool_id": pool.get("pool_id", -1),
			"rocket_impact": pool.get("rocket_impact", false)
		}
	}


func radio_definitions(chapter_count: int, supported: int) -> Array:
	var start := symbol_address("__ZN5Level19createRadioMessagesEi")
	var switches := calls_between(start, start + 256, "___switch32")
	if switches.size() != 1 or u32(switches[0] + 4) != chapter_count:
		fail("Unsupported campaign radio dispatch.")
		return []
	var table := switches[0] + 4
	var chapters: Array = []
	# These are source format tags, not chapter-specific content constants.
	var kinds := {
		0: "waypoint_passed",
		1: "enemy_range_casualty",
		2: "ally_range_casualty",
		3: "enemies_destroyed",
		5: "elapsed",
		6: "message_shown",
		7: "mission_won",
		8: "enemy_range_active",
		9: "enemy_range_destroyed",
		10: "ally_range_active",
		14: "enemy_active_after_message",
		12: "enemy_range_damaged",
		13: "enemies_active"
	}
	for chapter in supported:
		var first := table + u32(table + 4 + chapter * 4)
		var end := table + u32(table + 8 + chapter * 4)
		if first < table or end <= first or end > symbol_end(start):
			fail("Invalid radio content boundary.")
			return []
		var calls := calls_between(first, end, "__ZN12RadioMessageC1Eiiii")
		var ranged_calls := calls_between(first, end, "__ZN12RadioMessageC1Eiiiii")
		var objective_calls := calls_between(first, end, "__ZN12RadioMessageC1EiiP9Objective")
		calls.append_array(ranged_calls)
		calls.append_array(objective_calls)
		calls.sort()
		var sizes := calls_between(first, end, "__Z14ArraySetLengthIP12RadioMessageEvjR5ArrayIT_E")
		if sizes.size() != 1:
			fail("Unsupported radio array count.")
			return []
		var count_load := sizes[0] - (2 if u16(sizes[0] - 2) & 0xff00 == 0x2000 else 4)
		if immediate_at(count_load, 0) != calls.size():
			fail("Unsupported radio message array.")
			return []
		var messages: Array = []
		for call in calls:
			var text_id := -1
			var speaker := -1
			var parameter := -1
			# One initializer reuses its immediate tag for an exception-state store.
			var shared_kind := (
				u16(call - 8) & 0xf83f == 0x0009
				and u16(call - 6) & 0xff00 == 0x9300
				and u16(call - 4) & 0xff00 == 0x2200
				and u16(call - 2) & 0xff00 == 0x9000
			)
			var kind := (
				-1
				if objective_calls.has(call)
				else immediate_at(call - (10 if shared_kind else 4), 3)
			)
			var range_count := -1
			if shared_kind:
				if u16(call - 12) != 0x9300:
					fail("Unsupported shared radio tag declaration.")
					return []
				text_id = immediate_at(call - 14, 1) << ((u16(call - 8) >> 6) & 31)
				parameter = immediate_at(call - 16, 3)
				speaker = immediate_at(call - 4, 2)
			elif objective_calls.has(call):
				if u16(call - 8) != 0x6953:
					fail("Unsupported radio objective association.")
					return []
				text_id = immediate_at(call - 12, 1)
				speaker = immediate_at(call - 2, 2)
				kind = 7
				parameter = 0
			elif ranged_calls.has(call):
				if kind not in [1, 8, 9, 10, 14] or u16(call - 14) != 0x9301:
					fail("Unsupported ranged radio parameter initialization.")
					return []
				speaker = immediate_at(call - 6, 2)
				if u16(call - 20) == 0x9300 and u16(call - 8) & 0xf83f == 0x0009:
					text_id = immediate_at(call - 16, 1) << ((u16(call - 8) >> 6) & 31)
					parameter = immediate_at(call - 22, 3)
					range_count = immediate_at(call - 18, 3)
				elif u16(call - 18) == 0x9300:
					text_id = (
						literal(call - 8, 1)
						if u16(call - 8) & 0xff00 == 0x4900
						else immediate_at(call - 8, 1)
					)
					parameter = immediate_at(call - 20, 3)
					range_count = immediate_at(call - 16, 3)
			elif u16(call - 12) == 0x9300 and u16(call - 8) & 0xf83f == 0x0009:
				text_id = immediate_at(call - 14, 1) << ((u16(call - 8) >> 6) & 31)
				parameter = immediate_at(call - 16, 3)
				speaker = immediate_at(call - 6, 2)
			elif u16(call - 12) == 0x9300 and u16(call - 14) & 0xf83f == 0x0009:
				text_id = shifted_immediate(call - 16, 1)
				parameter = literal(call - 18, 3)
				speaker = immediate_at(call - 6, 2)
			elif u16(call - 10) == 0x9300:
				text_id = (
					literal(call - 14, 1)
					if u16(call - 14) & 0xff00 == 0x4900
					else immediate_at(call - 14, 1)
				)
				speaker = immediate_at(call - 12, 2)
				parameter = literal(call - 16, 3)
			elif u16(call - 16) == 0x9300 and u16(call - 8) & 0xf83f == 0x0009:
				text_id = immediate_at(call - 18, 1) << ((u16(call - 8) >> 6) & 31)
				speaker = immediate_at(call - 6, 2)
				parameter = immediate_at(call - 20, 3)
			elif u16(call - 14) == 0x9300 and u16(call - 8) & 0xf83f == 0x0009:
				text_id = immediate_at(call - 16, 1) << ((u16(call - 8) >> 6) & 31)
				speaker = immediate_at(call - 6, 2)
				parameter = immediate_at(call - 18, 3)
			elif u16(call - 14) == 0x9300:
				text_id = (
					literal(call - 8, 1)
					if u16(call - 8) & 0xff00 == 0x4900
					else immediate_at(call - 8, 1)
				)
				speaker = immediate_at(call - 6, 2)
				if u16(call - 16) & 0xff00 == 0x2300:
					parameter = immediate_at(call - 16, 3)
				elif u16(call - 16) & 0xf83f == 0x001b:
					parameter = shifted_immediate(call - 18, 3)

			if text_id < 0 or speaker < 0 or parameter < 0 or not kinds.has(kind):
				fail(
					(
						"Unsupported embedded radio parameter initialization at %x (tag %d)."
						% [call, kind]
					)
				)
				return []
			messages.append(
				{"text": text_id, "speaker": speaker, "condition": kinds[kind], "value": parameter}
			)
			if kind in [1, 2, 8, 9, 10, 12] and not ranged_calls.has(call):
				range_count = 1
			if kind in [1, 2, 8, 9, 10, 12]:
				if range_count <= 0:
					fail("Invalid radio actor range.")
					return []
				messages.back()["count"] = range_count
			if kind in [2, 9, 10, 14] and not extended_radio_condition(kind):
				return []
			if kind == 14:
				if range_count < 0 or range_count >= calls.size():
					fail("Invalid combined radio message association.")
					return []
				messages.back()["message"] = range_count
			if kind == 12:
				var trigger := symbol_address("__ZN12RadioMessage9triggeredExP9PlayerEgob")
				if u16(trigger + 0xf0) & 0xf83f != 0x1000:
					fail("Unsupported damaged-actor radio threshold.")
					return []
				messages.back()["fraction"] = 1.0 / (1 << ((u16(trigger + 0xf0) >> 6) & 31))
		chapters.append(messages)
	return chapters


func static_scatter() -> Array:
	var start := symbol_address("__ZN5Level18createStaticObjectEP8Waypointi")
	var rolls := calls_between(start, symbol_end(start), "__ZN11AbyssEngine8AERandom7nextIntEi")
	if rolls.size() != 3:
		fail("Unsupported static object placement data.")
		return []
	# Shared random range is initialized once as an immediate shifted left.
	var maximum := immediate_at(rolls[0] - 18, 1)
	var shift := u16(rolls[0] - 16)
	if shift & 0xf83f != 0x0009:
		fail("Unsupported static placement range.")
		return []
	maximum <<= (shift >> 6) & 31
	var offsets := [literal(rolls[0] + 8, 3), literal(rolls[1] + 8, 3), literal(rolls[2] + 6, 3)]
	var scatter: Array = []
	for offset in offsets:
		if offset < 0 or maximum <= 0 or maximum > 10000000:
			fail("Invalid static placement bounds.")
			return []
		var signed_offset: int = offset - 0x100000000 if offset & 0x80000000 else offset
		scatter.append([signed_offset, signed_offset + maximum - 1])
	return scatter


func initial_pilot() -> Dictionary:
	var start := symbol_address("__ZN6StatusC2Ev")
	# Constructor literal and immediate stores are content initialization data.
	# Validate the credit field association with its getter instead of assuming
	# that an arbitrary nearby constant is the starting balance.
	var getter := symbol_address("__ZN6Status10getCreditsEv")
	if u16(getter) != 0x6800 or u16(start) != 0xb510 or u16(start + 10) != 0x6003:
		fail("Unsupported initial pilot data layout.")
		return {}
	var credits := literal(start + 2, 3)
	if credits < 0:
		fail("Missing initial credit balance.")
		return {}
	# resetGame chooses the first entry of each loaded catalogue. Validate the
	# array access at each named constructor call and record its source index.
	var reset := symbol_address("__ZN6Status9resetGameEv")
	var make_ship := calls_between(reset, symbol_end(reset), "__ZN4Ship8makeShipEv")
	var price := calls_between(reset, symbol_end(reset), "__ZN9Equipment11getMaxPriceEv")
	var station := calls_between(reset, symbol_end(reset), "__ZN6Galaxy10getStationEiii")
	if (
		make_ship.size() != 1
		or price.size() != 1
		or station.size() != 1
		or u16(make_ship[0] - 6) != 0x6840
		or u16(make_ship[0] - 4) & 0xf83f != 0x6800
		or u16(price[0] - 10) != 0x685b
		or u16(price[0] - 8) & 0xf83f != 0x681b
	):
		fail("Unsupported initial catalogue selection.")
		return {}
	if u16(station[0] - 4) != 0x2100 or u16(station[0] - 2) & 0xff00 != 0x2200:
		fail("This initial station addressing scheme is not supported yet.")
		return {}
	if u16(start + 8) != 0x6203 or u16(start + 12) != 0x61c3 or u16(start + 30) != 0x6184:
		fail("Unsupported starting worth and rank association.")
		return {}
	return {
		"credits": credits,
		"worth": credits,
		"level": immediate_at(start + 16, 4),
		"rank_growth": float_constant("__ZN6Status15checkForLevelUpEv"),
		"station_index": u16(station[0] - 2) & 255,
		"ship_index": (u16(make_ship[0] - 4) >> 6) & 31,
		"weapon_index": (u16(price[0] - 8) >> 6) & 31
	}


func cruiser_attack_definition(first: int, end: int, chapter: int) -> Dictionary:
	if not empty_campaign_sequence(chapter):
		return {}
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var turrets := calls_between(first, end, "__ZN5Level12createTurretEP8KIPlayerbi")
	var bodies := calls_between(first, end, "__ZN17PlayerFixedObject11setPositionEiii")
	var positions := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var initial := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if (
		arrays.size() != 2
		or ships.size() != 4
		or turrets.size() != 1
		or bodies.size() != 1
		or positions.size() != 2
		or hulls.size() != 2
		or initial.size() != 1
		or objectives.size() != 1
		or not calls_between(first, end, "__ZN5RouteC1EPii").is_empty()
		or not calls_between(first, end, "__ZN8KIPlayer10setToSleepEv").is_empty()
		or not calls_between(first, end, "__ZN17PlayerFixedObject9setMovingEb").is_empty()
	):
		fail("Unsupported cruiser attack declaration.")
		return {}
	var enemies := immediate_at(arrays[0] - 6, 0)
	var turret_first := immediate_at(bodies[0] - 10, 5)
	var turret_end := u16(hulls[0] + 10) & 255
	var actor := immediate_at(ships[0] - 2, 3)
	var fighters := enemies - turret_end
	# Verify source array ranges and the reduction applied to the kill objective.
	var init := symbol_address("__ZN5Level4initEv")
	if (
		u16(hulls[0] + 10) & 0xff00 != 0x2d00
		or turret_first != 1
		or fighters < 1
		or enemies > 128
		or immediate_at(ships[0] - 22, 1) != 0
		or immediate_at(ships[0] - 16, 2) != 1
		or u16(turrets[0] - 10) != 0x6819
		or immediate_at(turrets[0] - 14, 2) != 1
		or u16(turrets[0] - 2) != 0x3b00 + turret_first
		or u16(ships[1] + 12) != (0x6008 | (turret_end << 6))
		or u16(ships[2] + 12) != 0x2d00 + enemies * 4
		or immediate_at(ships[1] - 18, 2) != 0
		or immediate_at(ships[2] - 4, 2) != 0
		or immediate_at(ships[1] - 2, 3) != immediate_at(ships[2] - 6, 3)
		or immediate_at(arrays[1] - 6, 0) != positions.size()
		or immediate_at(ships[3] - 30, 2) != 0
		or immediate_at(ships[3] - 2, 3) != 0
		or u16(ships[3] - 12) != 0x9300
		or u16(ships[3] - 10) != 0x9301
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
		or call_target(bodies[0] + 14) != symbol_address("__ZN8KIPlayer13setInitActiveEb")
		or immediate_at(bodies[0] + 6, 1) not in [0, 1]
		or u16(bodies[0] + 22) != 0x23d0
		or u16(bodies[0] + 28) != 0x50e5
		or u16(init + 0x300) != 0x23d0
		or u16(init + 0x304) != 0x1ad2
	):
		fail("Unsupported cruiser attack actor or kill-count association.")
		return {}
	var offset: Array = [
		signed_literal(bodies[0] - 6, 1),
		signed_literal(bodies[0] - 16, 2),
		signed_literal(bodies[0] - 18, 3)
	]
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var turret_hull := int(
		(
			literal_float(hulls[0] - 14, 1)
			+ literal_float(hulls[0] - 20, 1) * (difficulty - literal_float(hulls[0] - 36, 1))
		)
	)
	var ally_hull := int(
		(
			literal_float(hulls[1] - 14, 0)
			- literal_float(hulls[1] - 22, 1) * (difficulty - literal_float(hulls[1] - 48, 1))
		)
	)
	var mounts := turret_mounts(actor, turret_end - turret_first)
	var combat := interceptor_combat()
	var factory := fighter_factory_data(chapter, difficulty)
	var collisions := capital_collision()
	var tracking := turret_tracking()
	if (
		not error.is_empty()
		or mounts.is_empty()
		or combat.is_empty()
		or factory.is_empty()
		or collisions.is_empty()
		or tracking.is_empty()
	):
		return {}
	var groups: Array = [
		{
			"count": turret_first,
			"actor": actor,
			"center": offset,
			"positions": [offset],
			"placement": "points",
			"scatter": [],
			"after_route": false,
			"behavior": "stationary",
			"combat_active": immediate_at(bodies[0] + 6, 1) != 0,
			"wake_half_width": fixed_activation(),
			"hull_rule": factory.hull_rule,
			"source_scale": true,
			"collisions": collisions
		}
	]
	for index in turret_end - turret_first:
		var mount: Array = mounts.positions[index]
		var position: Array = []
		for axis in 3:
			position.append(offset[axis] + mount[axis])
		groups.append(
			{
				"count": 1,
				"actor": mounts.actor,
				"center": position,
				"positions": [position],
				"placement": "points",
				"scatter": [],
				"after_route": false,
				"behavior": "turret",
				"hull": turret_hull,
				"source_scale": true,
				"facing": mounts.facing[index],
				"tracking": tracking,
				"weapon": turret_weapon(mounts.actor)
			}
		)
	groups.append(
		{
			"count": fighters,
			"actor": immediate_at(ships[1] - 2, 3),
			"center": [0, 0, 0],
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"hull_rule": factory.hull_rule,
			"motion": combat.motion,
			"weapon": combat.weapon
		}
	)
	var shift := u16(positions[1] - 22)
	if shift & 0xf83f != 0x002d:
		fail("Unsupported wingmate placement.")
		return {}
	var relative := signed_literal(initial[0] - 12, 4)
	var placements := [
		[relative, relative, shifted_immediate(positions[0] - 8, 5)],
		[
			shifted_immediate(positions[1] - 16, 3),
			immediate_at(positions[1] - 26, 5) << ((shift >> 6) & 31),
			shifted_immediate(positions[1] - 6, 5)
		]
	]
	var speed := (
		literal_float(symbol_address("__ZN13PlayerFighterC2EibP6Playeriii") + 0x27e, 3) * 20.0
	)
	for index in placements.size():
		var ally := {
			"count": 1,
			"actor": immediate_at(ships[3] - 2, 3),
			"center": placements[index],
			"scatter": [],
			"after_route": false,
			"placement": "player_offset",
			"team": "ally",
			"behavior": "wingmate",
			"hull": ally_hull,
			"motion": dict_with_speed(combat.motion, speed),
			"weapon": friendly_weapon(combat.weapon)
		}
		if index == 0:
			ally.initial_hp = literal(initial[0] - 14, 1)
		groups.append(ally)
	return {
		"route": [],
		"groups": groups,
		"deadline_ms": 0,
		"success": {"kind": "enemies_destroyed"},
		"enemy_goal": enemies - immediate_at(bodies[0] - 10, 5)
	}


func empty_campaign_sequence(chapter: int) -> bool:
	var start := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := start + 48
	var base := (u16(start + 40) >> 6) & 7
	var count := u16(table)
	if (
		u16(start + 40) & 0xfe00 != 0x1e00
		or count <= 0
		or count > 128
		or chapter < base
		or chapter >= base + count
	):
		fail("Unsupported campaign event dispatch.")
		return false
	var destination := table + u16(table + 2 + (chapter - base) * 2) * 2
	var default_destination := table + u16(table + 2 + count * 2) * 2
	if (
		destination != default_destination
		or u16(destination) != 0x7a28
		or u16(destination + 12) != 0xbdf0
	):
		fail("This campaign chapter has unsupported encounter events.")
		return false
	return true


func cargo_rescue_definition(first: int, end: int, chapter: int) -> Dictionary:
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var positions := calls_between(first, end, "__ZN17PlayerFixedObject11setPositionEiii")
	var escorts := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var initial := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var children := calls_between(first, end, "__ZN9Objective12addObjectiveEPS_")
	if (
		routes.size() != 1
		or arrays.size() != 2
		or ships.size() != 3
		or hulls.size() != 2
		or positions.size() != 4
		or escorts.size() != 1
		or initial.size() != 1
		or objectives.size() != 5
		or children.size() != 3
	):
		fail("Unsupported cargo rescue declaration.")
		return {}
	var route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 4, 2)))
	var enemies := immediate_at(arrays[0] - 4, 0)
	var allies := immediate_at(arrays[1] - 8, 0)
	var split := u16(ships[0] - 44) & 255
	var middle := u16(ships[0] - 34) & 255
	var near_point := immediate_at(ships[0] - 40, 1)
	var middle_point := immediate_at(ships[0] - 30, 1)
	var far_point := immediate_at(ships[0] - 26, 1)
	var cargo_count := (u16(hulls[1] + 6) & 255) / 4
	if (
		u16(ships[0] - 44) & 0xff00 != 0x2d00
		or u16(ships[0] - 34) & 0xff00 != 0x2900
		or route.size() != 3
		or enemies <= middle
		or enemies > 128
		or middle != split + 1
		or near_point >= route.size()
		or middle_point >= route.size()
		or far_point >= route.size()
		or cargo_count != positions.size()
		or allies != cargo_count + 1
		or u16(hulls[1] + 6) & 0xff00 != 0x2d00
		or immediate_at(routes[0] + 16, 3) != 0xb0
		or u16(routes[0] + 18) != 0x50e8
		or immediate_at(ships[0] - 14, 3) != 1
		or u16(ships[0] - 10) != 0x9300
		or immediate_at(ships[0] - 8, 2) != 0
		or u16(ships[0] - 4) != 0x9001
		or call_target(ships[0] + 18) != symbol_address("__ZN8KIPlayer10setToSleepEv")
		or call_target(hulls[0] - 58) != symbol_address("__ZN6Player13getCombinedHPEv")
		or u16(hulls[0] - 54) & 0xff00 != 0x3800
		or immediate_at(ships[1] - 4, 2) != 3
		or u16(ships[1] - 18) != 0x9100
		or u16(ships[1] - 16) != 0x9101
		or immediate_at(ships[2] - 18, 2) != 0
		or u16(ships[2] - 8) != 0x9100
		or u16(ships[2] - 6) != 0x9101
		or u16(ships[2] + 8) != (0x6010 | (cargo_count << 6))
		or immediate_at(initial[0] + 12, 3) != 0xb0
		or call_target(initial[0] + 16) != symbol_address("__ZN5Route5cloneEv")
		or call_target(initial[0] + 24) != symbol_address("__ZN8KIPlayer8setRouteEP5Route")
		or immediate_at(objectives[0] - 14, 1) != 0
		or immediate_at(objectives[0] - 12, 2) != 0
	):
		fail("Unsupported cargo rescue actor, route or objective association.")
		return {}
	var failures: Array = []
	for index in range(1, objectives.size()):
		if (
			immediate_at(objectives[index] - 8, 1) != 6
			or immediate_at(objectives[index] - 6, 2) != index - 1
		):
			fail("Unsupported cargo loss objective association.")
			return {}
		failures.append({"kind": "ally_destroyed", "index": immediate_at(objectives[index] - 6, 2)})
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(chapter, difficulty)
	var combat := interceptor_combat()
	var bodies := convoy_bodies(immediate_at(ships[1] - 2, 3))
	if factory.is_empty() or combat.is_empty() or bodies.is_empty():
		return {}
	var enemy_rule: Dictionary = factory.hull_rule.duplicate(true)
	# A second source health initializer applies after the integer factory result.
	# Keep both rounding boundaries in the normalized rule.
	enemy_rule.post_offset = -(u16(hulls[0] - 54) & 255)
	enemy_rule.post_factor = 1 + difficulty - literal_float(hulls[0] - 48, 1)
	var cargo_hull := int(
		(
			literal_float(hulls[1] - 14, 0)
			- literal_float(hulls[1] - 22, 1) * (difficulty - literal_float(hulls[1] - 50, 1))
		)
	)
	var placements: Array = []
	for index in enemies:
		placements.append(
			(
				route[
					near_point
					if index <= split
					else (middle_point if index == middle else far_point)
				]
				. duplicate()
			)
		)
	var groups: Array = [
		{
			"count": enemies,
			"actor": immediate_at(ships[0] - 6, 3),
			"center": route[near_point],
			"positions": placements,
			"placement": "points",
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"sleeping": true,
			"hull_rule": enemy_rule,
			"motion": combat.motion,
			"weapon": combat.weapon
		}
	]
	var offsets: Array = [
		[
			signed_literal(positions[0] - 28, 2),
			signed_literal(positions[0] - 16, 4),
			signed_literal(positions[0] - 6, 4)
		],
		[
			shifted_immediate(positions[1] - 14, 3),
			signed_literal(positions[1] - 20, 5),
			signed_literal(positions[1] - 4, 5)
		],
		[
			signed_literal(positions[2] - 12, 3),
			signed_literal(positions[2] - 20, 5),
			signed_literal(positions[2] - 4, 5)
		],
		[
			shifted_immediate(positions[3] - 14, 3),
			signed_literal(positions[3] - 22, 5),
			signed_literal(positions[3] - 4, 5)
		]
	]
	for offset in offsets:
		groups.append(
			{
				"count": 1,
				"actor": immediate_at(ships[1] - 2, 3),
				"center": offset,
				"placement": "player_offset",
				"scatter": [],
				"after_route": false,
				"team": "ally",
				"behavior": "transit",
				"hull": cargo_hull,
				"source_scale": true,
				"velocity": [0, 0, -bodies.speed],
				"collision": bodies.cargo
			}
		)
	var escort_offset := [
		signed_literal(escorts[0] - 12, 3),
		signed_literal(escorts[0] - 20, 5),
		signed_literal(escorts[0] - 4, 5)
	]
	var speed := (
		literal_float(symbol_address("__ZN13PlayerFighterC2EibP6Playeriii") + 0x27e, 3) * 20.0
	)
	groups.append(
		{
			"count": 1,
			"actor": immediate_at(ships[2] - 2, 3),
			"center": escort_offset,
			"placement": "player_offset",
			"scatter": [],
			"after_route": false,
			"team": "ally",
			"behavior": "escort",
			"route": route,
			"hull_rule": factory.hull_rule,
			"initial_hp": literal(initial[0] - 14, 1),
			"motion": dict_with_speed(combat.motion, speed),
			"weapon": friendly_weapon(combat.weapon)
		}
	)
	var sequence := cargo_rescue_sequence(chapter, enemies, allies)
	var reward := surviving_allies_reward(chapter)
	if not error.is_empty() or cargo_hull <= 0 or enemy_rule.post_factor <= 0:
		return {}
	return {
		"route": [],
		"groups": groups,
		"deadline_ms": 0,
		"success": {"kind": "enemies_destroyed"},
		"failure": {"kind": "all", "conditions": failures},
		"failure_text": shifted_immediate(end - 22, 1),
		"reward_rule": reward,
		"sequence": sequence
	}


func cargo_rescue_sequence(chapter: int, enemies: int, allies: int) -> Array:
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	if u16(script + 40) & 0xfe00 != 0x1e00 or chapter < base or chapter >= base + u16(table):
		fail("Unsupported rescue event dispatch.")
		return []
	var first := table + u16(table + 2 + (chapter - base) * 2) * 2
	var end := symbol_end(script)
	for index in u16(table):
		var boundary := table + u16(table + 2 + index * 2) * 2
		if boundary > first:
			end = mini(end, boundary)
	var shown := calls_between(first, end, "__ZN12RadioMessage11isTriggeredEv")
	var finished := calls_between(first, end, "__ZN12RadioMessage6isOverEv")
	var cameras := calls_between(
		first, end, "__ZN18TargetFollowCamera12setCamOffsetEN11AbyssEngine6AEMath6VectorE"
	)
	var resets := calls_between(first, end, "__ZN11LevelScript11resetCameraEP18TargetFollowCamera")
	if (
		shown.size() != 2
		or finished.size() != 2
		or cameras.size() != 2
		or resets.size() != 2
		or end - first != 0x1ae
		or u16(first + 0x5a) & 0xff00 != 0x2c00
		or u16(first + 0x15c) != 0x4284
		or call_target(first + 0x156) != symbol_address("__ZN5Level10getFriendsEv")
	):
		fail("Unsupported rescue camera milestones.")
		return []
	var entry := indexed_reference(shown[0] - 2, 0, 0)
	var exit_message := indexed_reference(shown[1] - 2, 0, 3)
	if indexed_reference(finished[0] - 2, 0, 0) != entry:
		fail("Conflicting rescue camera release.")
		return []
	var first_count := (u16(first + 0x5a) & 255) / 4
	if first_count <= 0 or first_count > enemies:
		fail("Invalid rescue camera actor range.")
		return []
	var reset := {"kind": "focus", "actor": -1, "offset": [0, 0, 0]}
	return [
		{
			"when": {"kind": "message_shown", "message": entry},
			"actions":
			[
				{"kind": "lock", "value": true},
				{
					"kind": "focus_active",
					"first": immediate_at(first + 42, 4),
					"count": first_count,
					"offset":
					[
						signed_literal(cameras[0] - 16, 1),
						shifted_immediate(cameras[0] - 12, 2),
						signed_literal(cameras[0] - 14, 3)
					],
					"target_offset": [0, 0, immediate_at(first + 0x5e, 3)]
				}
			]
		},
		{
			"when": {"kind": "message_finished", "message": entry},
			"actions": [{"kind": "lock", "value": false}, reset.duplicate(true)]
		},
		{
			"when": {"kind": "message_shown", "message": exit_message},
			"actions":
			[
				{
					"kind": "focus_active",
					"first": enemies + immediate_at(first + 0x120, 4),
					"count": allies,
					"offset":
					[
						signed_literal(cameras[1] - 16, 1),
						shifted_immediate(cameras[1] - 12, 2),
						signed_literal(cameras[1] - 14, 3)
					],
					"target_offset": [0, 0, immediate_at(first + 0x160, 3)]
				}
			]
		},
		{
			"when":
			{"kind": "message_finished", "message": indexed_reference(finished[1] - 2, 0, 3)},
			"actions": [reset.duplicate(true)]
		}
	]


func surviving_allies_reward(chapter: int) -> Dictionary:
	var start := symbol_address("__ZN5MGame11finishLevelEv")
	var rewards := calls_between(start, symbol_end(start), "__ZN7Mission9getRewardEv")
	if rewards.size() != 2:
		fail("Unsupported campaign payout declaration.")
		return {}
	var call := rewards[0]
	if (
		u16(call - 18) != 0x2e00 + chapter
		or call_target(start + 30) != symbol_address("__ZN5Level14getFriendsLeftEv")
		or u16(start + 34) != 0x4682
		or u16(call + 4) != 0x4651
		or u16(call + 6) & 0xff00 != 0x3900
		or u16(call + 8) != 0x4341
		or call_target(call + 52) != symbol_address("__ZN7Mission9setRewardEi")
	):
		fail("Unsupported surviving-allies payout association.")
		return {}
	return {"kind": "surviving_allies", "offset": -(u16(call + 6) & 255)}


func fleet_strike_definition(first: int, end: int, chapter: int) -> Dictionary:
	if not empty_campaign_sequence(chapter):
		return {}
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var turrets := calls_between(first, end, "__ZN5Level12createTurretEP8KIPlayerbi")
	var positions := calls_between(first, end, "__ZN17PlayerFixedObject11setPositionEiii")
	var wings := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var initial := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if (
		arrays.size() != 2
		or ships.size() != 4
		or turrets.size() != 1
		or positions.size() != 2
		or wings.size() != 3
		or hulls.size() != 1
		or initial.size() != 1
		or objectives.size() != 1
		or not calls_between(first, end, "__ZN5RouteC1EPii").is_empty()
		or not calls_between(first, end, "__ZN8KIPlayer10setToSleepEv").is_empty()
	):
		fail("Unsupported fleet strike declaration.")
		return {}
	var enemies := immediate_at(arrays[0] - 2, 0)
	var allies := immediate_at(arrays[1] - 2, 0)
	var turret_first := immediate_at(positions[0] - 14, 5)
	var turret_end := u16(turrets[0] + 16) & 255
	var fighters := (u16(turrets[0] + 26) >> 6) & 7
	var init := symbol_address("__ZN5Level4initEv")
	if (
		turret_first != 1
		or turret_end - turret_first <= 0
		or enemies != turret_end + fighters
		or enemies > 128
		or allies != wings.size() + 1
		or immediate_at(ships[0] - 10, 2) != 1
		or u16(turrets[0] + 16) & 0xff00 != 0x2d00
		or u16(turrets[0] + 26) & 0xfe3f != 0x1e1c
		or u16(positions[0] + 4) != 0x6de0
		or immediate_at(positions[0] + 6, 1) not in [0, 1]
		or call_target(positions[0] + 12) != symbol_address("__ZN8KIPlayer13setInitActiveEb")
		or immediate_at(positions[0] + 16, 2) != 0xd0
		or u16(positions[0] + 26) & 0xff00 != 0x3300
		or u16(positions[0] + 28) != 0x50a3
		or u16(init + 0x300) != 0x23d0
		or u16(init + 0x304) != 0x1ad2
		or immediate_at(turrets[0] - 2, 2) != 1
		or u16(turrets[0] - 12) != 0x6819
		or u16(turrets[0] - 4) != 0x3b00 + turret_first
		or immediate_at(ships[1] - 24, 2) != 0
		or immediate_at(ships[1] - 18, 3) != 1
		or u16(ships[1] - 16) != 0x9300
		or immediate_at(ships[1] - 14, 3) != 0
		or u16(ships[1] - 12) != 0x9301
		or call_target(hulls[0] - 60) != symbol_address("__ZN6Player13getCombinedHPEv")
		or u16(hulls[0] - 56) & 0xff00 != 0x3000
		or immediate_at(ships[2] - 4, 2) != 0
		or immediate_at(ships[2] - 18, 3) != 0
		or u16(ships[2] - 16) != 0x9300
		or u16(ships[2] - 14) != 0x9301
		or immediate_at(ships[3] - 22, 2) != 2
		or immediate_at(ships[3] - 16, 3) != 0
		or u16(ships[3] - 14) != 0x9300
		or u16(ships[3] - 12) != 0x9301
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
	):
		fail("Unsupported fleet strike actor or objective associations.")
		return {}
	var capital_actor := immediate_at(ships[0] - 6, 3)
	var mounts := turret_mounts(capital_actor, turret_end - turret_first)
	var combat := interceptor_combat()
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(chapter, difficulty)
	var capital := capital_collision()
	var frigate := frigate_collision()
	var tracking := turret_tracking()
	if (
		mounts.is_empty()
		or combat.is_empty()
		or factory.is_empty()
		or capital.is_empty()
		or frigate.is_empty()
		or tracking.is_empty()
	):
		return {}
	var center := [
		signed_literal(positions[0] - 16, 1),
		signed_literal(positions[0] - 18, 2),
		signed_literal(positions[0] - 8, 3)
	]
	var groups: Array = [
		{
			"count": turret_first,
			"actor": capital_actor,
			"center": center,
			"positions": [center],
			"placement": "points",
			"scatter": [],
			"after_route": false,
			"behavior": "stationary",
			"combat_active": immediate_at(positions[0] + 6, 1) != 0,
			"hull_rule": factory.hull_rule,
			"source_scale": true,
			"collisions": capital
		}
	]
	for index in turret_end - turret_first:
		var position: Array = []
		for axis in 3:
			position.append(center[axis] + mounts.positions[index][axis])
		groups.append(
			{
				"count": 1,
				"actor": mounts.actor,
				"center": position,
				"positions": [position],
				"placement": "points",
				"scatter": [],
				"after_route": false,
				"behavior": "turret",
				"hull": campaign_turret_hull(mounts.actor),
				"source_scale": true,
				"facing": mounts.facing[index],
				"tracking": tracking,
				"weapon": turret_weapon(mounts.actor)
			}
		)
	var enemy_rule: Dictionary = factory.hull_rule.duplicate(true)
	enemy_rule.post_offset = u16(hulls[0] - 56) & 255
	enemy_rule.post_factor = 1 + difficulty - literal_float(hulls[0] - 48, 1)
	groups.append(
		{
			"count": fighters,
			"actor": immediate_at(ships[1] - 2, 3),
			"center": [0, 0, 0],
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"hull_rule": enemy_rule,
			"motion": combat.motion,
			"weapon": combat.weapon
		}
	)
	var offsets: Array = [
		[
			signed_literal(wings[0] - 20, 4),
			signed_literal(wings[0] - 16, 3),
			shifted_immediate(wings[0] - 8, 5)
		],
		[
			shifted_immediate(wings[1] - 14, 3),
			signed_literal(wings[1] - 22, 5),
			signed_literal(wings[1] - 22, 5) - (u16(wings[1] - 4) & 255)
		],
		[
			signed_literal(wings[2] - 14, 3),
			signed_literal(wings[2] - 22, 5),
			shifted_immediate(wings[2] - 6, 5)
		]
	]
	if u16(wings[1] - 4) & 0xff00 != 0x3d00:
		fail("Unsupported wingmate relative placement.")
		return {}
	var speed := (
		literal_float(symbol_address("__ZN13PlayerFighterC2EibP6Playeriii") + 0x27e, 3) * 20.0
	)
	for index in offsets.size():
		var wingmate := {
			"count": 1,
			"actor": immediate_at(ships[2] - 2, 3),
			"center": offsets[index],
			"placement": "player_offset",
			"scatter": [],
			"after_route": false,
			"team": "ally",
			"behavior": "wingmate",
			"hull_rule": factory.hull_rule,
			"motion": dict_with_speed(combat.motion, speed),
			"weapon": friendly_weapon(combat.weapon)
		}
		if index == 0:
			wingmate.initial_hp = literal(initial[0] - 8, 1)
		groups.append(wingmate)
	var frigate_position := [
		signed_literal(positions[1] - 4, 1),
		signed_literal(positions[1] - 14, 2),
		signed_literal(positions[1] - 2, 3)
	]
	groups.append(
		{
			"count": 1,
			"actor": immediate_at(ships[3] - 2, 3),
			"center": frigate_position,
			"positions": [frigate_position],
			"placement": "points",
			"scatter": [],
			"after_route": false,
			"team": "ally",
			"behavior": "stationary",
			"hull_rule": factory.hull_rule,
			"source_scale": true,
			"collisions": frigate
		}
	)
	if not error.is_empty():
		return {}
	return {
		"route": [],
		"groups": groups,
		"deadline_ms": 0,
		"enemy_goal": enemies - (u16(positions[0] + 26) & 255),
		"success": {"kind": "enemies_destroyed"}
	}


func campaign_turret_hull(actor: int) -> int:
	var start := symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	if (
		u16(start + 108) & 0xff00 != 0x2a00
		or actor not in [u16(start + 108) & 255, immediate_at(start + 80, 3)]
		or u16(start + 144) != 0xd113
		or call_target(start + 138) != symbol_address("__ZN6Status12campaignModeEv")
		or call_target(start + 208) != symbol_address("__ZN6PlayerC1Eiii")
	):
		fail("Unsupported campaign turret health declaration.")
		return -1
	return immediate_at(
		start + (112 if actor == (u16(start + 108) & 255) else 118),
		3 if actor == (u16(start + 108) & 255) else 1
	)


func frigate_collision() -> Array:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var first := factory + 0x412
	var second := factory + 0x454
	var third := factory + 0x498
	for call in [first, second, third]:
		var stores := (
			[-34, -26, -22, -18, -14, -10] if call == second else [-36, -28, -24, -18, -14, -10]
		)
		if call_target(call) != symbol_address("__ZN11BoundingAABC1Eiiiiiiiii"):
			fail("Unsupported allied frigate collision declaration.")
			return []
		for slot in stores.size():
			if u16(call + stores[slot]) != 0x9300 + slot:
				fail("Unsupported allied frigate collision parameters.")
				return []

	return [
		{
			"offset":
			[
				immediate_at(first - 38, 3),
				signed_literal(first - 34, 3),
				signed_literal(first - 26, 3)
			],
			"size":
			[shifted_immediate(first - 22, 3), literal(first - 16, 3), literal(first - 12, 3)]
		},
		{
			"offset":
			[
				immediate_at(second - 36, 3),
				signed_literal(second - 32, 3),
				signed_literal(second - 24, 3)
			],
			"size": [literal(second - 20, 3), literal(second - 16, 3), literal(second - 12, 3)]
		},
		{
			"offset":
			[
				immediate_at(third - 38, 3),
				signed_literal(third - 34, 3),
				signed_literal(third - 26, 3)
			],
			"size":
			[shifted_immediate(third - 22, 3), literal(third - 16, 3), literal(third - 12, 3)]
		}
	]


func ui_constant_before(address: int, register: int, distance: int = 16) -> int:
	# Only literal/immediate fields in the bounded resource record initializer.
	for cursor in range(address - 2, address - distance - 1, -2):
		var value := literal(cursor, register)
		if value >= 0:
			return value
		if u16(cursor) & 0xff00 == 0x2000 | (register << 8):
			value = u16(cursor) & 255
			for shift_at in range(cursor + 2, mini(cursor + 8, address), 2):
				var shift := u16(shift_at)
				if shift & 0xf83f == register * 9:
					value <<= (shift >> 6) & 31
					break
			return value
	return -1


func ui_region_binding(resource: int) -> Dictionary:
	var start := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var found: Array = []
	for address in range(start, symbol_end(start), 2):
		if u16(address) != 0x8003 or ui_constant_before(address, 3) != resource:
			continue
		var region_store := -1
		var texture_store := -1
		for cursor in range(address - 6, address - 52, -2):
			if region_store < 0 and u16(cursor) & 0xffc0 == 0x8040:
				region_store = cursor
			if region_store >= 0 and u16(cursor) & 0xfff8 == 0x8000:
				texture_store = cursor
				break
		if region_store < 0 or texture_store < 0:
			continue
		var texture := ui_constant_before(texture_store, u16(texture_store) & 7)
		var region := ui_constant_before(region_store, u16(region_store) & 7)
		if texture >= 0 and region >= 0:
			found.append({"texture": texture, "region": region})
	# One atlas record straddles a literal pool. Read its guarded declarations
	# on both sides of the branch; pool bytes are not resource instructions.
	if found.is_empty() and shifted_immediate(0x1bb96, 3) == resource:
		for guard in [
			[0x1bb1a, 0x90c5],
			[0x1bb1c, 0x8003],
			[0x1bb1e, 0x99c5],
			[0x1bb22, 0xe035],
			[0x1bb90, 0x804a],
			[0x1bb9e, 0x8003],
			[0x1bba8, 0x9ac5],
			[0x1bbac, 0x60c2]
		]:
			if u16(guard[0]) != guard[1]:
				fail("Unsupported split UI atlas association.")
				return {}
		found.append({"texture": immediate_at(0x1bb16, 3), "region": immediate_at(0x1bb18, 2)})
	if found.size() != 1:
		fail("Unsupported UI atlas association for resource %d." % resource)
		return {}
	return found[0]

func radio_presentation() -> Dictionary:
	var update := symbol_address("__ZN5Radio6updateElP9PlayerEgob")
	var draw := symbol_address("__ZN5Radio4drawExP9PlayerEgob")
	var font := symbol_address("__ZN7Globals8loadFontEv")
	if (
		u16(update + 0x18c) != 0x3301
		or u16(update + 0x18e) != 0x4353
		or u16(draw + 0x2e) != 0x00ed
		or u16(font + 0x1a) != 0x4252
	):
		fail("Unsupported radio presentation constants.")
		return {}
	var font_binding := ui_region_binding(literal(font + 10, 1))
	var portraits: Array = []
	for resource in named_array("__ZL9img_chars"):
		portraits.append(ui_region_binding(resource))
	# Recover the atlas path from its registered texture ID, not a portrait-name list.
	var registry := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	var textures := {}
	for call in calls_between(
		registry, symbol_end(registry), "__ZN11AbyssEngine15ResourceTextureC2EPc"
	):
		var branch := u16(call + 4)
		if branch & 0xf800 != 0xe000:
			continue
		var record := call + 8 + (branch & 0x7ff) * 2
		var identifier := -1
		for address in range(record, record + 64, 2):
			if u16(address) & 0xfff8 == 0x8000:
				identifier = ui_constant_before(address, u16(address) & 7)
				break
		for address in range(call - 2, call - 34, -2):
			var offset := file_offset(literal(address, 1), 1)
			if offset >= 0:
				var path := string_at_file(offset, bytes.size())
				if (
					identifier >= 0
					and path.begins_with("data/textures/")
					and path.ends_with(".aei")
					and not path.contains("..")
				):
					textures[str(identifier)] = path
					break
	var per_line := literal(update + 0x186, 2)
	var lead := immediate_at(draw + 0x2a, 5) << 3
	if per_line <= 0 or per_line > 10000 or lead <= 0 or lead > 10000 or font_binding.is_empty():
		fail("Invalid radio reading-time constants.")
	var layout := radio_layout()
	var panel := panel_presentation()
	if layout.is_empty() or panel.is_empty() or not error.is_empty():
		return {}
	return {
		"portraits": portraits,
		"textures": textures,
		"font": font_binding,
		"font_spacing": -immediate_at(font + 0x14, 2),
		"line_ms": per_line,
		"lead_ms": lead,
		"text_width": immediate_at(update + 0x152, 3) * 2,
		"layout": layout,
		"panel": panel
	}


func radio_layout() -> Dictionary:
	var draw := symbol_address("__ZN5Radio4drawExP9PlayerEgob")
	if (
		call_target(draw + 0x60) != symbol_address("__ZN6Layout16drawRoundEdgeBoxEiiiib")
		or (
			call_target(draw + 0x8c)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiiiihhh")
		)
		or (
			call_target(draw + 0xa8)
			!= symbol_address("__ZN7Globals9drawLinesEjP5ArrayIPN11AbyssEngine6StringEEii")
		)
		or u16(draw + 0x5e) != 0x005b
		or u16(draw + 0x46) != 0x6a63
		or u16(draw + 0x4e) & 0xff00 != 0x3300
		or u16(draw + 0x9c) & 0xff00 != 0x3300
	):
		fail("Unsupported radio panel placement declarations.")
		return {}
	return {
		"origin": [immediate_at(draw + 0x4a, 1), immediate_at(draw + 0x48, 2)],
		"width": immediate_at(draw + 0x5c, 3) * 2,
		"height_padding": u16(draw + 0x4e) & 255,
		"portrait": [immediate_at(draw + 0x7e, 2), immediate_at(draw + 0x88, 3)],
		"text": [u16(draw + 0x9c) & 255, immediate_at(draw + 0xa4, 5)]
	}


func panel_presentation() -> Dictionary:
	var reload := symbol_address("__ZN6Layout6reloadEv")
	var draw := symbol_address("__ZN6Layout16drawRoundEdgeBoxEiiiib")
	if (
		u16(reload + 0x412) != 0x32ac
		or (
			call_target(reload + 0x414)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		)
		or immediate_at(draw + 0x3e, 3) != 0xac
		or (
			call_target(draw + 0xb8)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas8SetColorEhhhh")
		)
		or (
			call_target(draw + 0xf2)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas8SetColorEhhhh")
		)
	):
		fail("Unsupported shared dialogue panel artwork declarations.")
		return {}
	var opacity := immediate_at(draw + 0x34, 3)
	return {
		"corner": ui_region_binding(literal(reload + 0x40e, 1)),
		"fill":
		[
			immediate_at(draw + 0xf0, 1),
			immediate_at(draw + 0xea, 2),
			immediate_at(draw + 0xee, 3),
			opacity
		],
		"border":
		[
			immediate_at(draw + 0xb6, 1),
			immediate_at(draw + 0xb0, 2),
			immediate_at(draw + 0xb4, 3),
			opacity
		]
	}


func nebula_ambush_definition(first: int, end: int, chapter: int) -> Dictionary:
	if not empty_campaign_sequence(chapter):
		return {}
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var fogs := calls_between(first, end, "__ZN3FogC1EP8Waypoint")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var sleeps := calls_between(first, end, "__ZN8KIPlayer10setToSleepEv")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	if (
		[routes, fogs, arrays, hulls, sleeps, objectives].any(func(calls): return calls.size() != 1)
		or ships.size() != 2
	):
		fail("Unsupported nebula ambush declaration.")
		return {}
	var route := route_points(int_array(literal(first, 3), immediate_at(routes[0] - 4, 2)))
	var count := immediate_at(arrays[0] - 4, 0)
	var target := immediate_at(objectives[0] - 6, 2)
	var factory_start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	if (
		route.size() != 1
		or count < 2
		or count > 128
		or target < 0
		or target >= count
		or immediate_at(objectives[0] - 8, 1) != 1
		or call_target(fogs[0] - 20) != symbol_address("__ZN5Route11getWaypointEi")
		or immediate_at(fogs[0] - 26, 1) != 0
		or u16(fogs[0] - 4) != 0x997b
	):
		fail("Unsupported nebula waypoint or target association.")
		return {}
	if (
		immediate_at(ships[0] - 8, 2) != 2
		or immediate_at(ships[0] - 14, 3) != 1
		or u16(ships[0] - 12) != 0x9300
		or u16(ships[0] - 4) != 0x9001
		or immediate_at(ships[1] - 8, 2) != 0
		or immediate_at(ships[1] - 10, 3) != 1
		or u16(ships[1] - 6) != 0x9300
		or u16(ships[1] - 4) != 0x9001
		or call_target(hulls[0] - 58) != symbol_address("__ZN6Player13getCombinedHPEv")
		or u16(hulls[0] - 54) & 0xff00 != 0x3000
		or (
			call_target(factory_start + 0x35e)
			!= symbol_address("__ZN13PlayerFighterC1EibP6Playeriii")
		)
		or (
			call_target(factory_start + 0x376)
			!= symbol_address("__ZN13PlayerFighter13setShootErrorEi")
		)
	):
		fail("Unsupported nebula ambush fighter roles.")
		return {}
	var combat := interceptor_combat()
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(chapter, difficulty)
	var motion: Dictionary = combat.motion.duplicate(true)
	motion.aim_sine = float(literal(factory_start + 0x36a, 1)) / normalized_vector_unit()
	var guards: Dictionary = factory.hull_rule.duplicate(true)
	guards.post_offset = u16(hulls[0] - 54) & 255
	guards.post_factor = 1 + difficulty - literal_float(hulls[0] - 48, 1)
	var groups: Array = []
	for index in 2:
		groups.append(
			{
				"count": 1 if index == 0 else count - 1,
				"actor":
				immediate_at(ships[0] - 6, 3) if index == 0 else immediate_at(ships[1] - 10, 3),
				"center": route[0],
				"scatter": factory.scatter,
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"hull_rule": factory.hull_rule if index == 0 else guards,
				"motion": motion if index == 0 else combat.motion,
				"weapon": combat.weapon
			}
		)
	return {
		"route": route,
		"groups": groups,
		"deadline_ms": 0,
		"success": {"kind": "enemy_destroyed", "index": target},
		"fog": fog_presentation()
	}


func fog_presentation() -> Dictionary:
	var start := symbol_address("__ZN3FogC2EP8Waypoint")
	var color := symbol_address("__ZN7Globals14getNebulaColorEi")
	var tint := symbol_address("__ZN3Fog8setColorEj")
	if (
		(
			call_target(start + 0x30)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas18SpriteSystemCreateEtbRj")
		)
		or (
			call_target(start + 0x138)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13TextureCreateEtRj")
		)
		or (
			call_target(start + 0x122)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas17SpriteSystemSetUvEjtssss")
		)
		or u16(start + 0x12c) & 0xff00 != 0x2a00
		or immediate_at(color + 22, 1) != 4
	):
		fail("Unsupported source nebula presentation.")
		return {}
	var low := signed_literal(start + 0x44, 3)
	var width := literal(start + 0x74, 1)
	var x := immediate_at(start + 0xe8, 1)
	var right := immediate_at(start + 0xec, 3)
	var y := literal(start + 0xf2, 2)
	var bottom := literal(start + 0xf4, 5)
	var palette: Array = []
	var secondary: Array = []
	for offset in [50, 54, 42, 46]:
		var packed := literal(color + offset, 0)
		palette.append(packed)
		secondary.append((packed & ~immediate_at(tint, 3)) | immediate_at(tint + 6, 3))
	if low >= 0 or width <= 0 or right <= x or bottom <= y:
		fail("Invalid nebula sprite volume or texture region.")
		return {}
	return {
		"waypoint": 0,
		"count": u16(start + 0x12c) & 255,
		"primary_count": immediate_at(start + 0x26, 1),
		"texture": immediate_at(start + 0x134, 1),
		"region": [x, y, right - x, bottom - y],
		"scatter": [low, low + width - 1],
		"size_min": literal(start + 0xb6, 2),
		"size_max": literal(start + 0xb6, 2) + literal(start + 0xae, 1) - 1,
		"palette": palette,
		"secondary_palette": secondary,
		"color_seed": shifted_immediate(color + 4, 3)
	}


func extended_radio_condition(kind: int) -> bool:
	var start := symbol_address("__ZN12RadioMessage9triggeredExP9PlayerEgob")
	var switches := calls_between(start, start + 64, "___switch16")
	if switches.size() != 1:
		fail("Unsupported radio condition dispatch.")
		return false
	var table := switches[0] + 4
	if u16(table) <= kind:
		fail("Missing radio condition tag.")
		return false
	var first := table + u16(table + 2 + kind * 2) * 2
	var valid := false
	match kind:
		2, 9, 10:
			var getter := (
				"__ZN6Player10getFriendsEv" if kind in [2, 10] else "__ZN6Player10getEnemiesEv"
			)
			var predicate := "__ZN6Player8isActiveEv" if kind == 10 else "__ZN6Player6isDeadEv"
			valid = (
				call_target(first + 6) == symbol_address(getter)
				and call_target(first + 26) == symbol_address(predicate)
				and u16(first + 32) & 0xff00 == (0xd000 if kind == 2 else 0xd100)
			)
		14:
			valid = (
				call_target(first + 4) == symbol_address("__ZN5Radio10getMessageEi")
				and u16(first + 2) == 0x69b1
				and u16(first + 14) & 0xff00 == 0xd000
				and call_target(first + 20) == symbol_address("__ZN6Player10getEnemiesEv")
				and u16(first + 24) == 0x6973
				and call_target(first + 32) == symbol_address("__ZN6Player8isActiveEv")
			)
	if not valid:
		fail("Unsupported radio condition semantics for tag %d." % kind)
	return valid


func pursuit_encounter_data(first: int, end: int, chapter: int) -> Dictionary:
	# Constructor data only. The encounter is not playable until its separate
	# event director, route changes and confrontation have been implemented.
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var objects := calls_between(first, end, "__ZN5Level18createStaticObjectEP8Waypointi")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var initial := calls_between(first, end, "__ZN6Player12setHitpointsEi")
	var positions := calls_between(first, end, "__ZN13PlayerFighter11setPositionEiii")
	var fields := calls_between(first, end, "__ZN13AsteroidFieldC1EiP8Waypoint")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var rotations := calls_between(first, end, "__ZN8KIPlayer16setRotationSpeedEi")
	if (
		routes.size() != 2
		or arrays.size() != 2
		or ships.size() != 3
		or objects.size() != 2
		or hulls.size() != 2
		or positions.size() != 4
		or [initial, fields, objectives, rotations].any(func(calls): return calls.size() != 1)
	):
		fail("Unsupported pursuit encounter declaration.")
		return {}
	var route := route_points(int_array(literal(first + 2, 1), immediate_at(routes[0] - 4, 2)))
	var escort_route := route_points(
		int_array(literal(first + 0x6e, 3), immediate_at(routes[1] - 6, 2))
	)
	var enemies := immediate_at(arrays[0] - 6, 0)
	var allies := immediate_at(arrays[1] - 6, 0)
	var debris := (u16(objects[1] + 10) & 255) / 4
	var fighters_end := u16(hulls[0] + 10) & 255
	var split := u16(ships[0] - 34) & 255
	var near_point := immediate_at(ships[0] - 30, 1)
	var far_point := immediate_at(ships[0] - 26, 1)
	var debris_point := immediate_at(first + 0xe6, 1)
	var friendly_point := immediate_at(first + 0x2e2, 1)
	var field_point := immediate_at(fields[0] - 28, 1)
	var reserve_point := immediate_at(ships[1] - 34, 1)
	var bridge := call_target(objects[1] + 14)
	if (
		route.size() != 5
		or escort_route.size() != 4
		or enemies != fighters_end + 1
		or debris < 1
		or debris >= split
		or split >= fighters_end
		or enemies > 128
		or allies != positions.size()
		or debris_point < 0
		or debris_point >= route.size()
		or friendly_point < 0
		or friendly_point >= escort_route.size()
		or field_point < 0
		or field_point >= route.size()
		or near_point < 0
		or far_point < 0
		or reserve_point < 0
		or near_point >= escort_route.size()
		or far_point >= escort_route.size()
		or reserve_point >= escort_route.size()
		or u16(objects[1] + 10) & 0xff00 != 0x2d00
		or u16(hulls[0] + 10) & 0xff00 != 0x2d00
		or u16(ships[0] - 34) & 0xff00 != 0x2800
		or u16(ships[0] - 32) & 0xff00 != 0xd100
		or immediate_at(bridge + 4, 5) != debris
		or immediate_at(bridge + 2, 1) != near_point
		or call_target(bridge + 24) != ships[0] - 24
		or immediate_at(objects[0] - 6, 2) != immediate_at(objects[1] - 6, 2)
		or immediate_at(ships[0] - 12, 2) != 0
		or immediate_at(ships[0] - 14, 3) != 1
		or u16(ships[0] - 10) != 0x9300
		or u16(ships[0] - 4) != 0x9001
		or immediate_at(ships[1] - 10, 2) != 0
		or immediate_at(ships[1] - 14, 1) != 1
		or u16(ships[1] - 12) != 0x9100
		or u16(ships[1] - 4) != 0x9001
		or u16(ships[1] + 6) != 0x6010 + (fighters_end << 6)
		or immediate_at(ships[2] - 12, 2) != 0
		or immediate_at(ships[2] - 10, 3) != 0
		or u16(ships[2] - 6) != 0x9300
		or u16(ships[2] - 4) != 0x9001
		or call_target(hulls[0] - 60) != symbol_address("__ZN6Player13getCombinedHPEv")
		or u16(hulls[0] - 56) & 0xff00 != 0x3000
		or u16(positions[1] - 18) & 0xf83f != 0x002d
		or u16(rotations[0] - 2) != 0x6e58
		or u16(first + 0x2aa) != 0x4790
		or immediate_at(objectives[0] - 8, 1) != 0
		or immediate_at(objectives[0] - 6, 2) != 0
	):
		fail("Unsupported pursuit actor ranges or associations.")
		return {}
	var combat := interceptor_combat()
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(chapter, difficulty)
	var hull_rule: Dictionary = factory.hull_rule.duplicate(true)
	hull_rule.post_offset = u16(hulls[0] - 56) & 255
	hull_rule.post_factor = 1 + difficulty - literal_float(hulls[0] - 48, 1)
	var groups: Array = [
		{
			"count": debris,
			"actor": immediate_at(objects[0] - 6, 2),
			"center": route[debris_point],
			"scatter": static_scatter(),
			"after_route": false
		}
	]
	# The first pair shares a waypoint. The remaining range uses the next point.
	for span in [[split - debris + 1, near_point], [fighters_end - split - 1, far_point]]:
		groups.append(
			{
				"count": span[0],
				"actor": immediate_at(ships[0] - 6, 3),
				"center": escort_route[span[1]],
				"scatter": factory.scatter,
				"after_route": false,
				"behavior": "interceptor",
				"sleeping": true,
				"motion": combat.motion,
				"weapon": combat.weapon,
				"hull_rule": hull_rule
			}
		)
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var commander_motion := dict_with_speed(
		combat.motion, literal_float(fighter + 0x27a, 3) * literal_float(fighter + 0x2a0, 1) * 20
	)
	commander_motion.turn_response = immediate_at(rotations[0] - 6, 1)
	# The commander has an absolute position override after factory placement.
	var commander_position := [
		signed_literal(first + 0x29a, 3),
		shifted_immediate(first + 0x29e, 3),
		signed_literal(first + 0x2a4, 3)
	]
	groups.append(
		{
			"count": 1,
			"actor": immediate_at(ships[1] - 6, 3),
			"center": commander_position,
			"placement": "points",
			"positions": [commander_position],
			"scatter": [],
			"after_route": false,
			"behavior": "interceptor",
			"sleeping": true,
			"motion": commander_motion,
			"weapon": combat.weapon,
			"hull": shifted_immediate(hulls[1] - 10, 1)
		}
	)
	var friendly_motion := dict_with_speed(combat.motion, literal_float(fighter + 0x27e, 3) * 20)
	friendly_motion.wake_half_width = friendly_activation()
	var offsets := [
		[
			signed_literal(first + 0x37a, 3),
			signed_literal(initial[0] - 12, 5),
			signed_literal(first + 0x38c, 5)
		],
		[
			signed_literal(positions[1] - 12, 3),
			immediate_at(positions[1] - 22, 5) << ((u16(positions[1] - 18) >> 6) & 31),
			signed_literal(positions[1] - 4, 5)
		],
		[
			signed_literal(positions[2] - 12, 3),
			signed_literal(positions[2] - 20, 5),
			signed_literal(positions[2] - 4, 5)
		],
		[0, 0, signed_literal(positions[3] - 14, 1)]
	]
	for index in allies:
		var center: Array = escort_route[friendly_point].duplicate()
		for axis in 3:
			center[axis] += offsets[index][axis]
		var group := {
			"count": 1,
			"actor": immediate_at(ships[2] - 10, 3),
			"center": center,
			"placement": "points",
			"positions": [center],
			"scatter": [],
			"after_route": false,
			"team": "ally",
			"behavior": "escort",
			"sleeping": true,
			"route": escort_route,
			"motion": friendly_motion,
			"weapon": friendly_weapon(combat.weapon),
			"hull_rule": factory.hull_rule
		}
		if index == 0:
			group.initial_hp = literal(initial[0] - 14, 1)
		groups.append(group)
	var field := asteroid_field_definition(immediate_at(fields[0] - 6, 1), field_point)
	if not error.is_empty() or field.is_empty():
		return {}
	return {
		"route": route,
		"escort_route": escort_route,
		"groups": groups,
		"deadline_ms": 0,
		"success": {"kind": "enemies_destroyed"},
		"scenery": [field]
	}


func friendly_activation() -> float:
	var update := symbol_address("__ZN13PlayerFighter6updateEi")
	var activation := calls_between(update, symbol_end(update), "__ZN6Player9setActiveEb").filter(
		func(call):
			return (
				call_target(call - 76) == symbol_address("__ZN5Level9getPlayerEv")
				and call_target(call - 92) == symbol_address("__ZN8KIPlayer7isEnemyEv")
			)
	)
	if activation.size() != 1:
		fail("Unsupported friendly proximity activation.")
		return -1
	var wake := int(activation[0])
	var upper := literal(wake - 46, 1)
	if (
		upper <= 0
		or upper > 10000000
		or literal(wake - 42, 2) != upper * 2
		or signed_literal(wake - 26, 2) != -upper - 1
		or u16(wake - 2) != 0x61b3
		or immediate_at(wake - 8, 3) != 1
	):
		fail("Unsupported friendly activation bounds.")
		return -1
	return upper * .02


func pursuit_navigation(chapter: int, route_count: int) -> Dictionary:
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	if u16(script + 40) & 0xfe00 != 0x1e00 or chapter < base or chapter >= base + u16(table):
		fail("Unsupported pursuit event dispatch.")
		return {}
	var first := table + u16(table + 2 + (chapter - base) * 2) * 2
	var stages := first + 8
	if call_target(first + 4) != symbol_address("___switch16") or u16(stages) != 10:
		fail("Unsupported pursuit event stages.")
		return {}
	var opening := stages + u16(stages + 2) * 2
	var release := stages + u16(stages + 2 + 2 * 2) * 2
	var extend := stages + u16(stages + 2 + 3 * 2) * 2
	if (
		call_target(opening + 6) != symbol_address("__ZN9PlayerEgo11removeRouteEv")
		or immediate_at(opening + 12, 1) != 0
		or call_target(opening + 14) != symbol_address("__ZN5Level14setPlayerRouteEP5Route")
		or call_target(release + 10) != symbol_address("__ZN12RadioMessage6isOverEv")
		or call_target(release + 50) != symbol_address("__ZN5Level13getEnemyRouteEv")
		or call_target(release + 54) != symbol_address("__ZN5Route5cloneEv")
		or call_target(release + 62) != symbol_address("__ZN5Route13reachWaypointEi")
		or call_target(release + 68) != symbol_address("__ZN5Route15getLastWaypointEv")
		or call_target(release + 72) != symbol_address("__ZN8Waypoint7reachedEv")
		or call_target(release + 84) != symbol_address("__ZN9PlayerEgo8setRouteEP5Route")
		or call_target(extend + 10) != symbol_address("__ZN12RadioMessage11isTriggeredEv")
		or call_target(extend + 66) != symbol_address("__ZN5Route15getLastWaypointEv")
		or u16(extend + 84) != 0x6003
	):
		fail("Unsupported pursuit route transition association.")
		return {}
	var start := immediate_at(release + 58, 1) + 1
	var final := immediate_at(extend + 82, 3)
	if start < 0 or start >= final or final != route_count - 1:
		fail("Invalid pursuit route transition bounds.")
		return {}
	return {
		"initial_end": 0,
		"release":
		{
			"when": {"kind": "message_finished", "message": indexed_reference(release + 8, 0, 3)},
			"action": {"kind": "route", "first": start, "end": final}
		},
		"extend":
		{
			"when": {"kind": "message_shown", "message": indexed_reference(extend + 8, 0, 3)},
			"action": {"kind": "route", "first": final, "end": route_count}
		}
	}


func pursuit_definition(first: int, end: int, chapter: int) -> Dictionary:
	var definition := pursuit_encounter_data(first, end, chapter)
	if definition.is_empty():
		return {}
	var navigation := pursuit_navigation(chapter, definition.route.size())
	if navigation.is_empty():
		return {}
	definition.route_initial_end = navigation.initial_end
	definition.sequence = pursuit_sequence(chapter, definition, navigation)
	definition.erase("escort_route")
	return definition if error.is_empty() else {}


func pursuit_sequence(chapter: int, encounter: Dictionary, navigation: Dictionary) -> Array:
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	var branch := table + u16(table + 2 + (chapter - base) * 2) * 2
	var stages := branch + 8
	if call_target(branch + 4) != symbol_address("___switch16") or u16(stages) != 10:
		fail("Unsupported pursuit confrontation dispatch.")
		return []
	var parts: Array[int] = []
	for index in u16(stages):
		parts.append(stages + u16(stages + 2 + index * 2) * 2)
	# Control capture and the player's movement freeze are separate declarations.
	# The first camera cue captures controls; the following reply freezes flight.
	var freeze: Array[bool] = []
	for part in [1, 2]:
		var call: int = parts[part] + 0x20
		if (
			call_target(call - 6) != symbol_address("__ZN5Level9getPlayerEv")
			or call_target(call) != symbol_address("__ZN9PlayerEgo9setFreezeEb")
		):
			fail("Unsupported pursuit player freeze declaration.")
			return []
		var value := immediate_at(call - 2, 1)
		if value not in [0, 1]:
			fail("Invalid pursuit player freeze flag.")
			return []
		freeze.append(bool(value))
	var conditions: Array = []
	for index in parts.size():
		var end := parts[index + 1] if index + 1 < parts.size() else parts[index] + 40
		var shown := calls_between(parts[index], end, "__ZN12RadioMessage11isTriggeredEv")
		var over := calls_between(parts[index], end, "__ZN12RadioMessage6isOverEv")
		if shown.size() + over.size() != 1:
			fail("Unsupported pursuit dialogue milestone.")
			return []
		var call := int(shown[0] if not shown.is_empty() else over[0])
		conditions.append(
			{
				"kind": "message_shown" if over.is_empty() else "message_finished",
				"message": indexed_reference(call - 2, 0, 0 if index == 0 else 3)
			}
		)
	var enemies := 0
	var allies := 0
	for group in encounter.groups:
		if group.get("team", "enemy") == "enemy":
			enemies += int(group.count)
		else:
			allies += int(group.count)
	var commander := indexed_reference(parts[3] + 0x5e, 4, 0)
	var ally := indexed_reference(parts[1] + 0x2e, 3, 3)
	var detached_first := immediate_at(parts[3] + 0x16, 4)
	if (
		commander < 0
		or commander >= enemies
		or ally < 0
		or ally >= allies
		or detached_first >= allies
	):
		fail("Invalid pursuit actor selectors.")
		return []
	if (
		call_target(parts[3] + 0x2c) != symbol_address("__ZN8KIPlayer8setRouteEP5Route")
		or call_target(parts[4] + 0xc) != symbol_address("__ZN8KIPlayer8setSpeedEf")
		or call_target(parts[4] + 0x3a) != symbol_address("__ZN6Player12setHitpointsEi")
		or call_target(parts[4] + 0x4a) != symbol_address("__ZN6Player16removeAllEnemiesEv")
		or (
			call_target(parts[4] + 0x78)
			!= symbol_address("__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE")
		)
		or call_target(parts[4] + 0x118) != symbol_address("__ZN6Player12setHitpointsEi")
		or call_target(parts[4] + 0x12a) != symbol_address("__ZN6Player15setMaxHitpointsEi")
		or call_target(parts[4] + 0x148) != symbol_address("__ZN6Player8setEnemyEPS_")
		or call_target(parts[5] + 0x32) != symbol_address("__ZN6Player8setEnemyEPS_")
		or (
			call_target(parts[5] + 0x90)
			!= symbol_address(
				"__ZN18TargetFollowCamera11setPositionERN11AbyssEngine6AEMath6VectorE"
			)
		)
		or call_target(parts[7] + 0x24) != symbol_address("__ZN8KIPlayer8setSpeedEf")
		or call_target(parts[8] + 0x24) != symbol_address("__ZN8KIPlayer8setSpeedEf")
		or call_target(parts[9] + 0x22) != symbol_address("__ZN6Player12setHitpointsEi")
	):
		fail("Unsupported pursuit confrontation actions.")
		return []
	if (
		indexed_reference(parts[4] + 0x36, 3, 3) != commander
		or indexed_reference(parts[4] + 0x46, 3, 3) != commander
		or indexed_reference(parts[4] + 0xb6, 0, 3) != commander
		or indexed_reference(parts[4] + 0x156, 3, 3) != commander
		or indexed_reference(parts[5] + 0x20, 0, 3) != commander
		or indexed_reference(parts[5] + 0x52, 1, 3) != commander
		or indexed_reference(parts[7] + 0x22, 0, 3) != commander
		or indexed_reference(parts[7] + 0x32, 3, 3) != commander
		or indexed_reference(parts[8] + 0x22, 0, 3) != commander
		or indexed_reference(parts[9] + 0x1c, 3, 3) != commander
	):
		fail("Conflicting pursuit commander references.")
		return []

	var friend_actor := enemies + ally
	var reset := {"kind": "focus", "actor": -1, "offset": [0, 0, 0]}
	var detach: Array = []
	for index in range(detached_first, allies):
		detach.append({"kind": "detach_route", "actor": enemies + index})
	var normalize := symbol_address("__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE")
	var unit := shifted_immediate(normalize + 0x6a, 3)
	var half_shift := (u16(parts[4] + 0x8e) >> 6) & 31
	if u16(parts[4] + 0x8e) & 0xf83f != 0x101b or half_shift == 0 or unit <= 0:
		fail("Unsupported pursuit relative placement scale.")
		return []
	var ally_health := immediate_at(parts[4] + 0x110, 1)
	if ally_health != immediate_at(parts[4] + 0x122, 1):
		fail("Conflicting pursuit casualty hull declaration.")
		return []
	var midpoint_shift := (u16(parts[5] + 0x6e) >> 6) & 31
	if u16(parts[5] + 0x6e) & 0xf83f != 0x101b or midpoint_shift == 0:
		fail("Unsupported pursuit camera midpoint.")
		return []
	for reference in [[4, 0x114, 3, 3], [4, 0x126, 3, 3], [4, 0x144, 3, 3], [6, 0x22, 3, 3]]:
		if (
			indexed_reference(parts[reference[0]] + reference[1], reference[2], reference[3])
			!= ally
		):
			fail("Conflicting pursuit allied character references.")
			return []
	var sequence: Array = [
		{
			"when": conditions[0],
			"actions":
			[
				{"kind": "lock", "value": true},
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						shifted_at(parts[0] + 0x4e, parts[0] + 0x52, 1),
						shifted_at(parts[0] + 0x50, parts[0] + 0x54, 2),
						signed_literal(parts[0] + 0x4c, 3)
					]
				}
			]
		},
		{
			"when": conditions[1],
			"actions":
			[
				{"kind": "frozen", "value": freeze[0]},
				{
					"kind": "focus",
					"actor": friend_actor,
					"offset":
					[
						signed_literal(parts[1] + 0x48, 1),
						shifted_at(parts[1] + 0x4c, parts[1] + 0x4e, 2),
						signed_literal(parts[1] + 0x4a, 3)
					]
				}
			]
		},
		{
			"when": conditions[2],
			"actions":
			[
				{"kind": "lock", "value": false},
				{"kind": "frozen", "value": freeze[1]},
				reset,
				navigation.release.action
			]
		},
		{
			"when": conditions[3],
			"actions":
			(
				detach
				+ [
					navigation.extend.action,
					{"kind": "place", "actor": commander, "point": encounter.route.back()},
					{
						"kind": "speed",
						"actor": friend_actor,
						"value": literal_float(parts[4] + 0x6, 1) * 20.0
					}
				]
			)
		},
		{
			"when": conditions[4],
			"actions":
			[
				{"kind": "lock", "value": true},
				{"kind": "health", "actor": commander, "value": signed_literal(parts[4] + 0x32, 1)},
				{
					"kind": "relocate_forward",
					"actor": commander,
					"relative_to": friend_actor,
					"distance": unit / (1 << half_shift)
				},
				{"kind": "health", "actor": friend_actor, "value": ally_health},
				{"kind": "target", "actor": commander, "target": friend_actor},
				{
					"kind": "focus",
					"actor": commander,
					"offset":
					[
						signed_literal(parts[4] + 0x170, 1),
						shifted_at(parts[4] + 0x174, parts[4] + 0x176, 2),
						signed_literal(parts[4] + 0x172, 3)
					]
				}
			]
		},
		{
			"when": conditions[5],
			"actions":
			[
				{"kind": "target", "actor": commander, "target": friend_actor},
				{
					"kind": "focus_between",
					"actor": commander,
					"other": friend_actor,
					"fraction": 1.0 / (1 << midpoint_shift)
				}
			]
		},
		{
			"when": conditions[6],
			"actions":
			[
				{
					"kind": "focus",
					"actor": friend_actor,
					"offset":
					[
						signed_literal(parts[6] + 0x3e, 1),
						signed_literal(parts[6] + 0x40, 2),
						signed_literal(parts[6] + 0x42, 3)
					],
					"target_offset":
					[
						shifted_at(parts[6] + 0x2a, parts[6] + 0x2c, 3),
						0,
						shifted_at(parts[6] + 0x2a, parts[6] + 0x2c, 3)
					]
				}
			]
		},
		{
			"when": conditions[7],
			"actions":
			[
				{
					"kind": "speed",
					"actor": commander,
					"value": literal_float(parts[7] + 0x1e, 1) * 20.0
				},
				{
					"kind": "focus",
					"actor": commander,
					"offset":
					[
						signed_literal(parts[7] + 0x4c, 1),
						signed_literal(parts[7] + 0x4e, 2),
						signed_literal(parts[7] + 0x50, 3)
					]
				}
			]
		},
		{
			"when": conditions[8],
			"actions":
			[
				{
					"kind": "speed",
					"actor": commander,
					"value": literal_float(parts[8] + 0x1e, 1) * 20.0
				},
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						signed_literal(parts[8] + 0x58, 1),
						signed_literal(parts[8] + 0x5a, 2),
						signed_literal(parts[8] + 0x5c, 3)
					]
				}
			]
		},
		{
			"when": conditions[9],
			"actions":
			[{"kind": "health", "actor": commander, "value": immediate_at(parts[9] + 0x20, 1)}]
		}
	]
	return sequence if error.is_empty() else []


func shifted_at(load: int, shift: int, register: int) -> int:
	if u16(shift) & 0xf83f != register * 9:
		fail("Unsupported split shifted constant.")
		return -1
	return immediate_at(load, register) << ((u16(shift) >> 6) & 31)


func friendly_capital_collision() -> Array:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	# Friendly fixed-body branch declares three boxes with its own dimensions.
	var constructors := [factory + 0x5ec, factory + 0x62e, factory + 0x672]
	var boxes: Array = []
	for index in constructors.size():
		var call: int = constructors[index]
		var stores: Array = (
			[-28, -32, -24, -18, -14, -10]
			if index == 0
			else ([-34, -26, -22, -18, -14, -10] if index == 1 else [-36, -28, -24, -18, -14, -10])
		)
		if call_target(call) != symbol_address("__ZN11BoundingAABC1Eiiiiiiiii"):
			fail("Unsupported friendly capital collision declaration.")
			return []
		for slot in stores.size():
			var expected := (0x9200 if index == 0 and slot == 0 else 0x9300) + slot
			if u16(call + stores[slot]) != expected:
				fail("Unsupported friendly capital collision field.")
				return []
		boxes.append(
			{
				"offset":
				[
					0 if index == 0 else immediate_at(call - (36 if index == 1 else 38), 3),
					signed_literal(call - (38 if index == 0 else (32 if index == 1 else 34)), 3),
					signed_literal(call - (30 if index == 0 else (24 if index == 1 else 26)), 3)
				],
				"size":
				[
					shifted_immediate(call - 22, 3) if index != 1 else literal(call - 20, 3),
					literal(call - 16, 3),
					literal(call - 12, 3)
				]
			}
		)
	return boxes


func finale_encounter_data(first: int, end: int, chapter: int) -> Dictionary:
	var routes := calls_between(first, end, "__ZN5RouteC1EPii")
	var ships := calls_between(first, end, "__ZN5Level10createShipEiiibP8Waypoint")
	var arrays := calls_between(first, end, "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
	var hulls := calls_between(first, end, "__ZN6Player15setMaxHitpointsEi")
	var positions := calls_between(first, end, "__ZN17PlayerFixedObject11setPositionEiii")
	var turrets := calls_between(first, end, "__ZN5Level12createTurretEP8KIPlayerbi")
	var objectives := calls_between(first, end, "__ZN9ObjectiveC1EiiP5Level")
	var sleeps := calls_between(first, end, "__ZN8KIPlayer10setToSleepEv")
	var boosts := calls_between(first, end, "__ZN13PlayerFighter12setBoostProbEi")
	if (
		routes.size() != 2
		or ships.size() != 7
		or arrays.size() != 2
		or hulls.size() != 2
		or positions.size() != 3
		or turrets.size() != 4
		or objectives.size() != 1
		or sleeps.size() != 1
		or boosts.size() != 1
	):
		fail("Unsupported finale encounter declaration.")
		return {}
	var route := route_points(
		int_array(literal(routes[0] - 34, 3), immediate_at(routes[0] - 10, 2))
	)
	var reserve := route_points(
		int_array(literal(routes[1] - 40, 3), immediate_at(routes[1] - 6, 2))
	)
	var enemies := immediate_at(arrays[0] - 6, 0)
	var allies := immediate_at(arrays[1] - 4, 0)
	var enemy_loop := u16(ships[1] + 14)
	var wing_loop := u16(hulls[1] + 6)
	var fighters := (enemy_loop & 255) / 4
	var wingmates := (wing_loop & 255) / 4
	if (
		route.size() != 1
		or reserve.size() != 1
		or enemies != fighters + 1
		or allies != wingmates + positions.size() + turrets.size()
		or enemies > 128
		or fighters <= 0
		or wingmates <= 0
		or (enemy_loop & 255) % 4 != 0
		or (wing_loop & 255) % 4 != 0
		or enemy_loop & 0xff00 != 0x2c00
		or wing_loop & 0xff00 != 0x2d00
		or u16(routes[0] + 16) != 0x23b0
		or u16(routes[0] + 20) != 0x50c1
		or immediate_at(ships[0] - 18, 2) != 0
		or immediate_at(ships[1] - 2, 2) != 0
		or immediate_at(ships[0] - 44, 5) != 1
		or immediate_at(ships[0] - 20, 0) != 0
		or u16(ships[0] - 14) != 0x9001
		or u16(ships[0] - 2) != 0x9500
		or immediate_at(ships[1] - 18, 3) != 1
		or u16(ships[1] - 16) != 0x9300
		or immediate_at(ships[1] - 14, 3) != 0
		or u16(ships[1] - 12) != 0x9301
		or immediate_at(ships[0] - 6, 3) != immediate_at(ships[1] - 8, 3)
		or immediate_at(ships[2] - 12, 2) != 0
		or immediate_at(ships[2] - 6, 3) < 0
		or u16(ships[2] - 4) != 0x9001
		or u16(ships[2] - 8) != 0x9300
		or indexed_reference(sleeps[0] - 2, 0, 3) != fighters
		or u16(hulls[0] - 26) != 0x69d8
		or u16(hulls[1] - 28) != 0x69d8
		or u32(literal(hulls[0] - 30, 3)) != symbol_address("__ZN7Globals7optionsE")
		or u32(literal(hulls[1] - 32, 3)) != symbol_address("__ZN7Globals7optionsE")
		or immediate_at(ships[3] - 4, 2) != 0
		or immediate_at(ships[3] - 2, 3) != 0
		or u16(ships[3] - 18) != 0x9100
		or u16(ships[3] - 16) != 0x9101
		or immediate_at(ships[3] - 26, 1) != 0
		or immediate_at(ships[4] - 18, 1) != 0
		or immediate_at(ships[4] - 14, 5) != 0
		or u16(ships[4] - 8) != 0x9100
		or u16(ships[4] - 6) != 0x9101
		or u16(ships[5] - 8) != 0x9500
		or u16(ships[5] - 6) != 0x9501
		or u16(ships[6] - 8) != 0x9500
		or u16(ships[6] - 6) != 0x9501
		or immediate_at(ships[4] - 16, 2) != 2
		or immediate_at(ships[5] - 16, 2) != 2
		or immediate_at(ships[4] - 2, 3) != immediate_at(ships[5] - 2, 3)
		or immediate_at(ships[6] - 14, 2) != 1
		or immediate_at(objectives[0] - 12, 1) != 4
	):
		fail("Unsupported finale actor or objective associations.")
		return {}
	# Objective tag four refers to a triggered source radio message.
	var objective := symbol_address("__ZN9Objective8achievedEi")
	var switch_at := calls_between(objective, symbol_end(objective), "___switch8")
	if switch_at.size() != 1:
		fail("Unsupported message objective dispatch.")
		return {}
	var table: int = switch_at[0] + 4
	var tag := immediate_at(objectives[0] - 12, 1)
	var offset := file_offset(table + 1 + tag, 1)
	if offset < 0:
		fail("Invalid message objective tag table.")
		return {}
	var branch: int = table + int(bytes[offset]) * 2
	if (
		call_target(branch + 10) != symbol_address("__ZN5Level11getMessagesEv")
		or call_target(branch + 22) != symbol_address("__ZN12RadioMessage11isTriggeredEv")
	):
		fail("Unsupported finale completion condition.")
		return {}
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(chapter, difficulty)
	var combat := interceptor_combat()
	if factory.is_empty() or combat.is_empty():
		return {}
	var friendly_gun := friendly_weapon(combat.weapon)
	var commander_hp := int(
		(
			literal_float(hulls[0] - 14, 1)
			+ literal_float(hulls[0] - 20, 1) * (difficulty - literal_float(hulls[0] - 40, 1))
		)
	)
	var friendly_hp := int(
		(
			literal_float(hulls[1] - 14, 0)
			- literal_float(hulls[1] - 22, 1) * (difficulty - literal_float(hulls[1] - 50, 1))
		)
	)
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var groups: Array = [
		{
			"count": fighters,
			"actor": immediate_at(ships[0] - 6, 3),
			"center": [0, 0, 0],
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"hull_rule": factory.hull_rule,
			"motion": combat.motion,
			"weapon": combat.weapon
		},
		{
			"count": enemies - fighters,
			"actor": immediate_at(ships[2] - 6, 3),
			"center": reserve[0],
			"scatter": factory.scatter,
			"after_route": false,
			"behavior": "interceptor",
			"sleeping": true,
			"hull": commander_hp,
			"boost_probability": immediate_at(boosts[0] - 6, 1),
			"motion":
			dict_with_speed(
				combat.motion,
				literal_float(fighter + 0x27a, 3) * literal_float(fighter + 0x2a0, 1) * 20
			),
			"weapon": scripted_fighter_weapon(chapter, combat.weapon)
		},
		{
			"count": wingmates,
			"actor": immediate_at(ships[3] - 2, 3),
			"center": [0, 0, 0],
			"scatter": factory.scatter,
			"after_route": false,
			"team": "ally",
			"behavior": "wingmate",
			"hull": friendly_hp,
			"motion": dict_with_speed(combat.motion, literal_float(fighter + 0x27e, 3) * 20),
			"weapon": friendly_gun
		}
	]
	var points: Array = [
		[
			signed_literal(positions[0] - 8, 1),
			signed_literal(positions[0] - 14, 2),
			signed_literal(positions[0] - 2, 3)
		],
		[
			shifted_immediate(positions[1] - 12, 1),
			signed_literal(positions[1] - 8, 2),
			signed_literal(positions[1] - 2, 3)
		],
		[
			signed_literal(positions[2] - 14, 1),
			signed_literal(positions[2] - 8, 2),
			signed_literal(positions[2] - 2, 3)
		]
	]
	for index in points.size():
		groups.append(
			{
				"count": 1,
				"actor": immediate_at(ships[4 + index] - 2, 3),
				"center": points[index],
				"positions": [points[index]],
				"placement": "points",
				"scatter": [],
				"after_route": false,
				"team": "ally",
				"behavior": "stationary",
				"wake_half_width": fixed_activation(),
				"hull_rule": factory.hull_rule,
				"source_scale": true,
				"collisions":
				frigate_collision() if index < points.size() - 1 else friendly_capital_collision()
			}
		)
	groups[2].motion.wake_half_width = friendly_activation()
	var parent_actor: int = groups.back().actor
	var mounts := turret_mounts(parent_actor, turrets.size())
	if mounts.is_empty():
		return {}
	var actor_meshes := named_array(TABLES.actor_meshes)
	var mesh_resources := resource_bindings()
	if mounts.actor < 0 or mounts.actor >= actor_meshes.size() or mesh_resources.is_empty():
		fail("Invalid finale turret presentation association.")
		return {}
	# The Terran turret entry names an unregistered mesh in this content build.
	# Preserve its combat hardpoint without substituting an unrelated model.
	var turret_mesh := mesh_resources.has(str(int(actor_meshes[int(mounts.actor)])))
	for index in turrets.size():
		var call: int = turrets[index]
		if (
			immediate_at(call - 2, 3) != index
			or indexed_reference(call - 4, 1, 3) != wingmates + positions.size() - 1
		):
			fail("Unsupported finale turret mount association.")
			return {}
		var position: Array = []
		for axis in 3:
			position.append(points.back()[axis] + mounts.positions[index][axis])
		groups.append(
			{
				"count": 1,
				"actor": mounts.actor,
				"render_mesh": turret_mesh,
				"center": position,
				"positions": [position],
				"placement": "points",
				"scatter": [],
				"after_route": false,
				"team": "ally",
				"behavior": "turret",
				"hull": campaign_turret_hull(mounts.actor),
				"source_scale": true,
				"facing": mounts.facing[index],
				"tracking": turret_tracking(),
				"weapon": friendly_gun
			}
		)
	var ending := campaign_ending()
	if ending.is_empty() or ending.chapter != chapter:
		fail("Finale does not match the source terminal chapter.")
		return {}
	if not error.is_empty() or commander_hp <= 0 or friendly_hp <= 0:
		return {}
	return {
		"route": route,
		"route_initial_end": 0,
		"ending": ending,
		"groups": groups,
		"deadline_ms": 0,
		"success": {"kind": "message_shown", "message": immediate_at(objectives[0] - 10, 2)}
	}


func finale_definition(first: int, end: int, chapter: int) -> Dictionary:
	var definition := finale_encounter_data(first, end, chapter)
	if definition.is_empty():
		return {}
	definition.sequence = finale_sequence(chapter, definition)
	return definition if error.is_empty() else {}


func finale_sequence(chapter: int, encounter: Dictionary) -> Array:
	var script := symbol_address("__ZN11LevelScript7processEiP18TargetFollowCamera")
	var table := script + 48
	var base := (u16(script + 40) >> 6) & 7
	if u16(script + 40) & 0xfe00 != 0x1e00 or chapter < base or chapter >= base + u16(table):
		fail("Unsupported finale event dispatch.")
		return []
	var branch := table + u16(table + 2 + (chapter - base) * 2) * 2
	var stages := branch + 8
	if call_target(branch + 4) != symbol_address("___switch16") or u16(stages) != 8:
		fail("Unsupported finale dialogue stages.")
		return []
	var parts: Array[int] = []
	for index in u16(stages):
		parts.append(stages + u16(stages + 2 + index * 2) * 2)
	var conditions: Array = []
	for index in parts.size():
		var end := parts[index + 1] if index + 1 < parts.size() else parts[index] + 58
		var shown := calls_between(parts[index], end, "__ZN12RadioMessage11isTriggeredEv")
		var over := calls_between(parts[index], end, "__ZN12RadioMessage6isOverEv")
		if shown.size() + over.size() != 1:
			fail("Unsupported finale dialogue milestone.")
			return []
		var call := int(shown[0] if not shown.is_empty() else over[0])
		conditions.append(
			{
				"kind": "message_shown" if over.is_empty() else "message_finished",
				"message": indexed_reference(call - 2, 0, 3)
			}
		)
	var commander := indexed_reference(parts[0] + 0x62, 0, 3)
	var waypoint := immediate_at(parts[0] + 0x46, 1)
	var enemies := 0
	var allies := 0
	for group in encounter.groups:
		if group.get("team", "enemy") == "enemy":
			enemies += int(group.count)
		else:
			allies += int(group.count)
	if commander < 0 or commander >= enemies or waypoint < 0 or waypoint >= encounter.route.size():
		fail("Invalid finale actor or route selector.")
		return []
	# Recognize the supported source declarations; recover their operands below.
	# This describes milestones for the independent director, not executable code.
	var signatures := [
		[parts[0] + 4, "__ZN5Level14setPlayerRouteEP5Route"],
		[parts[0] + 0x1e, "__ZN5Level13getEnemyRouteEv"],
		[parts[0] + 0x22, "__ZN5Route5cloneEv"],
		[parts[0] + 0x30, "__ZN9PlayerEgo8setRouteEP5Route"],
		[parts[0] + 0x38, "__ZN5Level14setPlayerRouteEP5Route"],
		[parts[0] + 0x48, "__ZN5Route11getWaypointEi"],
		[parts[0] + 0x5a, "__ZN5Level10getEnemiesEv"],
		[parts[1] + 0x28, "__ZN6Player13setVulnerableEb"],
		[parts[1] + 0x34, "__ZN9PlayerEgo9setFreezeEb"],
		[parts[1] + 0x46, "__ZN18TargetFollowCamera9setTargetEj"],
		[parts[1] + 0x54, "__ZN8KIPlayer10setToSleepEv"],
		[
			parts[1] + 0x66,
			"__ZN18TargetFollowCamera15setTargetOffsetEN11AbyssEngine6AEMath6VectorE"
		],
		[parts[1] + 0x7a, "__ZN18TargetFollowCamera12setCamOffsetEN11AbyssEngine6AEMath6VectorE"],
		[parts[1] + 0x82, "__ZN5Level10getFriendsEv"],
		[parts[1] + 0x8e, "__ZN8KIPlayer10setToSleepEv"],
		[parts[1] + 0x94, "__ZN5Level10getFriendsEv"],
		[parts[2] + 0xa, "__ZN8KIPlayer10setToSleepEv"],
		[parts[2] + 0x30, "__ZN18TargetFollowCamera9setTargetEj"],
		[
			parts[2] + 0x42,
			"__ZN18TargetFollowCamera15setTargetOffsetEN11AbyssEngine6AEMath6VectorE"
		],
		[parts[3] + 0xa, "__ZN8KIPlayer10setToSleepEv"],
		[parts[3] + 0x28, "__ZN11LevelScript11resetCameraEP18TargetFollowCamera"],
		[parts[3] + 0x36, "__ZN6Player13setVulnerableEb"],
		[parts[3] + 0x42, "__ZN9PlayerEgo9setFreezeEb"],
		[parts[4] + 0x24, "__ZN18TargetFollowCamera9setTargetEj"],
		[
			parts[4] + 0x36,
			"__ZN18TargetFollowCamera15setTargetOffsetEN11AbyssEngine6AEMath6VectorE"
		],
		[parts[4] + 0x4a, "__ZN18TargetFollowCamera12setCamOffsetEN11AbyssEngine6AEMath6VectorE"],
		[parts[6] + 0x26, "__ZN18TargetFollowCamera12setCamOffsetEN11AbyssEngine6AEMath6VectorE"],
		[parts[7] + 0x26, "__ZN18TargetFollowCamera12setCamOffsetEN11AbyssEngine6AEMath6VectorE"],
		[parts[7] + 0x2e, "__ZN18TargetFollowCamera9setLockedEb"],
		[parts[7] + 0x36, "__ZN18TargetFollowCamera12setLookAtCamEb"]
	]
	for signature in signatures:
		if call_target(signature[0]) != symbol_address(signature[1]):
			fail("Unsupported finale cinematic association.")
			return []
	if (
		indexed_reference(parts[1] + 0x42, 3, 3) != commander
		or indexed_reference(parts[1] + 0x52, 0, 3) != commander
		or indexed_reference(parts[2] + 8, 0, 3) != commander
		or indexed_reference(parts[3] + 8, 0, 3) != commander
		or u16(parts[0] + 0x68) != 0x4798
		or u16(parts[1] + 0x1c) != 0x722b
		or u16(parts[3] + 0x22) != 0x722b
		or u16(parts[4] + 0x1a) != 0x722b
		or immediate_at(parts[1] + 0x24, 4) != 0
		or u16(parts[1] + 0x88) != 0x3401
		or u16(parts[1] + 0x8c) != 0x5898
		or u16(parts[1] + 0x98) != 0x6800
		or u16(parts[1] + 0x9a) != 0x4284
		or u16(parts[4] + 0x52) & 0xf800 != 0xe000
		or parts[4] + 0x56 + (u16(parts[4] + 0x52) & 0x7ff) * 2 != parts[7] + 0x36
		or immediate_at(parts[7] + 0x2c, 1) != 0
	):
		fail("Unsupported finale sleep or camera control declaration.")
		return []
	var lock_intro := immediate_at(parts[1] + 0x1a, 3)
	var unlock := immediate_at(parts[3] + 0x20, 3)
	var lock_ending := immediate_at(parts[4] + 0x18, 3)
	var vulnerability := [immediate_at(parts[1] + 0x22, 1), immediate_at(parts[3] + 0x32, 1)]
	var freeze := [immediate_at(parts[1] + 0x32, 1), immediate_at(parts[3] + 0x40, 1)]
	var hold := [immediate_at(parts[4] + 0x50, 1), immediate_at(parts[7] + 0x34, 1)]
	for flag in [lock_intro, unlock, lock_ending] + vulnerability + freeze + hold:
		if flag not in [0, 1]:
			fail("Invalid finale cinematic flag.")
			return []
	var intro: Array = [
		{"kind": "lock", "value": bool(lock_intro)},
		{"kind": "vulnerable", "value": bool(vulnerability[0])},
		{"kind": "frozen", "value": bool(freeze[0])},
		{"kind": "suspend", "actor": commander, "value": true},
		{
			"kind": "focus",
			"actor": commander,
			"offset":
			[
				signed_literal(parts[1] + 0x6a, 1),
				shifted_at(parts[1] + 0x6e, parts[1] + 0x70, 2),
				signed_literal(parts[1] + 0x6c, 3)
			],
			"target_offset":
			[
				immediate_at(parts[1] + 0x5c, 1),
				immediate_at(parts[1] + 0x5e, 2),
				immediate_at(parts[1] + 0x58, 3)
			]
		}
	]
	for index in allies:
		intro.append({"kind": "sleep", "actor": enemies + index})
	var sequence: Array = [
		{
			"when": conditions[0],
			"actions":
			[
				{"kind": "route", "first": 0, "end": encounter.route.size()},
				{"kind": "place", "actor": commander, "point": encounter.route[waypoint]}
			]
		},
		{"when": conditions[1], "actions": intro},
		{
			"when": conditions[2],
			"actions":
			[
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						signed_literal(parts[2] + 0x46, 1),
						shifted_at(parts[2] + 0x4a, parts[2] + 0x4c, 2),
						signed_literal(parts[2] + 0x48, 3)
					],
					"target_offset":
					[
						immediate_at(parts[2] + 0x36, 1),
						immediate_at(parts[2] + 0x38, 2),
						immediate_at(parts[2] + 0x34, 3)
					]
				}
			]
		},
		{
			"when": conditions[3],
			"actions":
			[
				{"kind": "lock", "value": bool(unlock)},
				{"kind": "vulnerable", "value": bool(vulnerability[1])},
				{"kind": "frozen", "value": bool(freeze[1])},
				{"kind": "suspend", "actor": commander, "value": false},
				{"kind": "focus", "actor": -1, "offset": [0, 0, 0]}
			]
		},
		{
			"when": conditions[4],
			"actions":
			[
				{"kind": "lock", "value": bool(lock_ending)},
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						shifted_at(parts[4] + 0x3e, parts[4] + 0x40, 1),
						signed_literal(parts[4] + 0x3a, 2),
						signed_literal(parts[4] + 0x3c, 3)
					],
					"target_offset":
					[
						immediate_at(parts[4] + 0x2c, 1),
						immediate_at(parts[4] + 0x2e, 2),
						immediate_at(parts[4] + 0x28, 3)
					]
				},
				{"kind": "camera_hold", "value": bool(hold[0])}
			]
		},
		{"when": conditions[5], "actions": []},
		{
			"when": conditions[6],
			"actions":
			[
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						signed_literal(parts[6] + 0x16, 1),
						shifted_at(parts[6] + 0x1a, parts[6] + 0x1c, 2),
						signed_literal(parts[6] + 0x18, 3)
					]
				}
			]
		},
		{
			"when": conditions[7],
			"actions":
			[
				{
					"kind": "focus",
					"actor": -1,
					"offset":
					[
						signed_literal(parts[7] + 0x16, 1),
						shifted_at(parts[7] + 0x1a, parts[7] + 0x1c, 2),
						signed_literal(parts[7] + 0x18, 3)
					]
				},
				{"kind": "camera_hold", "value": bool(hold[1])}
			]
		}
	]
	for event in sequence:
		for action in event.actions:
			if action.kind == "focus":
				action.relative = true
	return sequence if error.is_empty() else []


func campaign_ending() -> Dictionary:
	var finish := symbol_address("__ZN6Status10missionEndEv")
	var mode := symbol_address("__ZN6Status18enterFreelanceModeEv")
	var station := symbol_address("__ZN8MStation12OnInitializeEv")
	var calls := calls_between(station, symbol_end(station), "__ZN6Status18enterFreelanceModeEv")
	if (
		calls.size() != 1
		or u16(finish + 22) & 0xff00 != 0x2800
		or u16(finish + 18) != 0x3001
		or u16(finish + 20) != 0x62e0
		or u16(finish + 24) & 0xff00 != 0xdd00
		or u16(finish + 26) != u16(mode)
		or u16(finish + 28) != u16(mode + 2)
		or u16(finish + 30) != 0x54e2
		or u16(mode + 4) != 0x54c2
	):
		fail("Unsupported campaign terminal transition.")
		return {}
	var call: int = calls[0]
	if (
		call_target(call - 116) != symbol_address("__ZN6Status10getMissionEv")
		or call_target(call - 112) != symbol_address("__ZN7Mission8getLevelEv")
		or u16(call - 108) != u16(finish + 22)
		or call_target(call - 90) != symbol_address("__ZN8GameText7getTextEi")
		or immediate_at(mode + 2, 2) != 0
	):
		fail("Unsupported campaign ending announcement association.")
		return {}
	return {"chapter": u16(finish + 22) & 255, "text": literal(call - 100, 1)}


func contract_rules() -> Dictionary:
	var start := symbol_address("__ZN9Generator14getMissionListEv")
	var constructor := symbol_address("__ZN7MissionC1EiN11AbyssEngine6StringEiiiiii")
	var rng := "__ZN11AbyssEngine8AERandom7nextIntEi"
	var imports := imported_symbols()
	if imports.is_empty():
		return {}
	var signatures := [
		[0x64, rng],
		[0x6c, "__Z14ArraySetLengthIP7MissionEvjR5ArrayIT_E"],
		[0x9c, rng],
		[0xb8, rng],
		[0x12c, rng],
		[0x160, rng],
		[0x178, rng],
		[0x198, "__ZN9Generator18generateProfessionEii"],
		[0x1ac, rng],
		[0x216, "__ZN7Station9getPlanetEv"],
		[0x224, rng],
		[0x244, "___divsf3vfp"],
		[0x25c, "___mulsf3vfp"],
		[0x280, "___mulsf3vfp"],
		[0x2b4, "___mulsf3vfp"],
		[0x2d2, "___mulsf3vfp"],
		[0x2e0, "___modsi3"],
		[0x2f0, "___modsi3"],
		[0x314, rng]
	]
	for pair in signatures:
		if (
			not imports.get(pair[1], []).has(call_target(start + pair[0]))
			if str(pair[1]).begins_with("___") and pair[1] != "___switch8"
			else call_target(start + pair[0]) != symbol_address(pair[1])
		):
			fail("Unsupported freelance offer declaration.")
			return {}
	if (
		call_target(start + 0x364) != constructor
		or u16(start + 0x26c) & 0xff00 != 0x2900
		or u16(start + 0x270) & 0xff00 != 0x2900
		or u16(start + 0x274) & 0xff00 != 0x2900
		or u16(start + 0x28c) & 0xff00 != 0x2a00
		or u16(start + 0x29c) & 0xff00 != 0x3b00
		or u16(start + 0x29e) != 0x2b01
		or u16(start + 0x2a4) & 0xff00 != 0x2b00
		or u16(start + 0x2a8) & 0xff00 != 0x2b00
		or u16(start + 0x2e8) != 0x18c3
		or u16(start + 0x2fc) != 0x1a89
		or u16(start + 0x354) != 0x434b
		or u16(start + 0x6a) & 0xff00 != 0x3000
		or u16(start + 0x23a) & 0xff00 != 0x3000
		or u16(start + 0x318) & 0xff00 != 0x3000
	):
		fail("Unsupported freelance reward policy.")
		return {}
	var types := immediate_at(start + 0x8e, 1)
	var quadrants := named_array(TABLES.quadrant_difficulty).size()
	var title_view := symbol_address("__ZN11MissionList12drawItemInfoEPvijj")
	var description_view := symbol_address("__ZN13MissionWindow3setEP7Mission")
	var title := source_text_index(title_view + 0x10c)
	var description := source_text_index(description_view + 0x1e4)
	if title < 0 or description < 0 or types <= 0 or types > 64:
		return {}
	var definitions: Array = []
	for index in types:
		definitions.append(
			{
				"title": title + index,
				"description": description + index,
				"reward_factor": 1.0,
				"reward_unit": "fixed"
			}
		)
	var groups: Array = [
		[
			[u16(start + 0x26c) & 255, u16(start + 0x270) & 255, u16(start + 0x274) & 255],
			literal_float(start + 0x27e, 1)
		],
		[[u16(start + 0x28c) & 255], literal_float(start + 0x296, 1)],
		[
			[
				u16(start + 0x29c) & 255,
				(u16(start + 0x29c) & 255) + 1,
				u16(start + 0x2a4) & 255,
				u16(start + 0x2a8) & 255
			],
			literal_float(start + 0x2b2, 1)
		]
	]
	var seen: Array[int] = []
	for group in groups:
		for index in group[0]:
			if index < 0 or index >= types or seen.has(index):
				fail("Invalid freelance reward category.")
				return {}
			seen.append(index)
			definitions[index].reward_factor = group[1]
	if u16(start + 0x302) & 0xff00 != 0x2b00:
		fail("Unsupported per-target contract reward.")
		return {}
	var rate_type := u16(start + 0x302) & 255
	if rate_type >= types:
		fail("Invalid per-target contract category.")
		return {}
	definitions[rate_type].reward_unit = "per_target"
	var result := {
		"types": definitions,
		"offer_count": [u16(start + 0x6a) & 255, immediate_at(start + 0x5e, 1)],
		"tier_range": [u16(start + 0x23a) & 255, immediate_at(start + 0x21a, 1)],
		"tier_divisor": literal_float(start + 0x242, 1),
		"quadrant_difficulty": int_array(literal(start + 0x22a, 3), quadrants),
		"minimum_rewards": int_array(literal(start + 0x234, 3), quadrants),
		"maximum_rewards": int_array(literal(start + 0x248, 3), quadrants),
		"reward_step": immediate_at(start + 0x2dc, 1),
		"rounding": "half_step_up_otherwise_down",
		"rate_range": [u16(start + 0x318) & 255, immediate_at(start + 0x30c, 1)],
		"special":
		{
			"chance_count": (u16(start + 0x1b0) & 255) + 1,
			"chance_out_of": immediate_at(start + 0x1a6, 1),
			"limit": immediate_at(start + 0x1f4, 1),
			"portrait": immediate_at(start + 0x1f6, 2),
			"profession": literal(start + 0x1f2, 3),
			"reward_factor": literal_float(start + 0x2d0, 1)
		},
		"client_race_count": immediate_at(start + 0xb2, 1),
		"local_race_attempts": u16(start + 0xda) & 255,
		"male_portraits":
		int_array(
			literal(start + 0x166, 2),
			immediate_at(start + 0xb2, 1) * immediate_at(start + 0x158, 1)
		),
		"female_portraits":
		int_array(
			literal(start + 0x17e, 2),
			immediate_at(start + 0xb2, 1) * immediate_at(start + 0x172, 1)
		),
		"male_choices": immediate_at(start + 0x158, 1),
		"female_choices": immediate_at(start + 0x172, 1)
	}
	# Convert count-based source ranges to explicit inclusive bounds.
	result.offer_count[1] += result.offer_count[0] - 1
	result.tier_range[1] += result.tier_range[0] - 1
	result.rate_range[1] += result.rate_range[0] - 1
	result["clients"] = contract_clients(start, types, result.client_race_count)
	result["hunt"] = contract_hunt()
	result["transport"] = contract_transport()
	result["battles"] = contract_battles()
	result["clearance"] = contract_clearance()
	result["minefield"] = contract_minefield()
	result["asteroids"] = contract_asteroids()
	result["escort"] = contract_escort()
	result["intercept"] = contract_intercept()
	result["capture"] = contract_capture()
	return result if error.is_empty() else {}


func contract_clients(board: int, types: int, races: int) -> Dictionary:
	for pair in [
		[0xf4, 0xd000],
		[0xfc, 0xd000],
		[0x100, 0xe1a4],
		[0x106, 0xd102],
		[0x112, 0xd002],
		[0x116, 0xd000],
		[0x11c, 0x2102],
		[0x132, 0x1e43],
		[0x134, 0x4383],
		[0x136, 0x0fd8],
		[0x42e, 0xd000]
	]:
		if u16(board + pair[0]) != pair[1]:
			fail("Unsupported contract client selection policy.")
			return {}
	var names := symbol_address("__ZN7Globals9loadNamesEibP5ArrayIPN11AbyssEngine6StringEE")
	var constructor := symbol_address("__ZN9GeneratorC2Ev")
	var string_constructor := symbol_address("__ZN11AbyssEngine6StringC1EPKc")
	if (
		races != immediate_at(names + 0x38, 3) + 1
		or races > 128
		or (
			call_target(names + 0x208)
			!= symbol_address("__ZN6AEFile8OpenReadERN11AbyssEngine6StringEPj")
		)
		or call_target(constructor + 0x46) != string_constructor
		or u16(names + 0x11e) != 0x9b02
		or u16(names + 0x120) != 0x2b00
		or u16(names + 0x122) != 0xd001
		or u16(board + 0xf2) & 0xff00 != 0x2800
		or u16(board + 0xfa) & 0xff00 != 0x2a00
		or u16(board + 0x104) & 0xff00 != 0x2b00
		or u16(board + 0x42c) != 0x2800
		or immediate_at(board + 0x108, 1) != 0
		or immediate_at(board + 0x41a, 3) != immediate_at(board + 0x452, 1)
	):
		fail("Unsupported contract client name association.")
		return {}
	# File components and race order are supplied string declarations. The only
	# retained result is a list of content paths, never the original loader.
	var parts := []
	for offset in [0xb6, 0x106, 0x124, 0x128, 0x144]:
		parts.append(embedded_string(literal(names + offset, 1)))
	var paths := []
	for race in races:
		var load_at := names + (0x3e if race == 0 else 0x40 + race * 12)
		var call_at := load_at + (6 if race == 0 else 4)
		if call_target(call_at) != string_constructor:
			fail("Unsupported contract race name declaration.")
			return {}
		var race_name := embedded_string(literal(load_at, 1))
		var pair := {}
		for index in 2:
			var path: String = parts[0] + race_name + parts[1] + parts[index + 2] + parts[4]
			if (
				not path.begins_with("data/txt/")
				or not path.ends_with(".txt")
				or path.contains("..")
				or path.contains("\\")
			):
				fail("Invalid contract client name resource path.")
				return {}
			pair["male" if index == 0 else "female"] = path
		paths.append(pair)
	var genders := [u16(board + 0x110) & 255, u16(board + 0x114) & 255]
	if u16(board + 0x110) & 0xff00 != 0x2a00 or u16(board + 0x114) & 0xff00 != 0x2a00:
		fail("Unsupported client gender selection.")
		return {}
	return {
		"name_files": paths,
		"random_gender_races": genders,
		"race_overrides":
		[
			{
				"station": u16(board + 0xf2) & 255,
				"rolled": u16(board + 0xfa) & 255,
				"race": immediate_at(board + 0x460, 3)
			},
			{
				"station": u16(board + 0x42c) & 255,
				"rolled": u16(board + 0x104) & 255,
				"race": immediate_at(board + 0x108, 1)
			}
		],
		"special_name": embedded_string(literal(constructor + 0x40, 1)),
		"professions": contract_professions(types, races)
	}


func contract_professions(types: int, races: int) -> Array:
	var start := symbol_address("__ZN9Generator18generateProfessionEii")
	for pair in [
		[0x1a, 0xd10b],
		[0x28, 0x2800],
		[0x2a, 0xd101],
		[0x36, 0xd108],
		[0x44, 0x2800],
		[0x46, 0xd03c],
		[0x48, 0xe01e],
		[0x56, 0x2801],
		[0x58, 0xd004],
		[0x5a, 0x2802],
		[0x5c, 0xd004],
		[0x5e, 0x2800],
		[0x60, 0xd046],
		[0x62, 0xe003],
		[0xe2, 0x2800],
		[0xe4, 0xd102]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported contract profession selection policy.")
			return []
	var rng := symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi")
	for offset in [0x24, 0x40, 0x52, 0x74, 0xb0, 0xde]:
		if call_target(start + offset) != rng:
			fail("Unsupported contract profession selector.")
			return []
	var dispatch := contract_choice_targets(start + 6, start)
	var civilian := contract_choice_targets(start + 0x7a, start)
	var escort := contract_choice_targets(start + 0xb6, start)
	if (
		dispatch.size() != types
		or civilian.size() != immediate_at(start + 0x6e, 1)
		or escort.size() != immediate_at(start + 0xaa, 1)
		or immediate_at(start + 0x1e, 1) != 2
		or immediate_at(start + 0x3a, 1) != 2
		or immediate_at(start + 0x4c, 1) != 3
		or immediate_at(start + 0xd8, 1) != 2
		or u16(start + 0x18) & 0xff00 != 0x2a00
		or u16(start + 0x34) & 0xff00 != 0x2a00
		or u16(start + 0xe8) != 0x0040
	):
		fail("Unsupported contract profession choices.")
		return []
	var values := {}
	# Bounded constant return declarations: MOVS followed by the shared shift,
	# or a PC-relative literal followed by the common return. No code is retained.
	for offset in [
		0x2c,
		0x30,
		0x64,
		0x68,
		0x88,
		0x8c,
		0x90,
		0x94,
		0x98,
		0x9c,
		0xa0,
		0xa4,
		0xc2,
		0xc6,
		0xca,
		0xce,
		0xd2,
		0xe6,
		0xec,
		0xf0
	]:
		var address: int = start + offset
		var opcode := u16(address)
		if opcode & 0xff00 == 0x2000:
			if offset != 0xe6 and contract_constant_branch(address + 2) != start + 0xe8:
				fail("Unsupported shifted profession constant.")
				return []
			values[address] = (opcode & 255) * 2
		elif opcode & 0xff00 == 0x4800:
			if offset != 0xf0 and contract_constant_branch(address + 2) != start + 0xf2:
				fail("Unsupported profession literal.")
				return []
			values[address] = literal(address, 0)
		else:
			fail("Unknown profession constant encoding.")
			return []
	var result := []
	for target in dispatch:
		var choices := []
		for race in races:
			var options := []
			if target == start + 0x18:
				if race == (u16(start + 0x18) & 255):
					options = [values[start + 0x2c], values[start + 0x30]]
				elif race == (u16(start + 0x34) & 255):
					options = [values[start + 0xc2], values[start + 0x88]]
				else:
					options = [values[start + 0xf0], values[start + 0x64], values[start + 0x68]]
			elif target == start + 0x6c or target == start + 0xa8:
				for option in civilian if target == start + 0x6c else escort:
					if not values.has(option):
						fail("Invalid contract profession choice target.")
						return []
					options.append(values[option])
			elif target == start + 0xd6:
				options = [values[start + 0xe6], values[start + 0xec]]
			elif target == start + 0xf0:
				options = [values[start + 0xf0]]
			else:
				fail("Unsupported contract profession category.")
				return []
			choices.append(options)
		result.append(choices)
	return result if error.is_empty() else []


func contract_choice_targets(call: int, owner: int) -> Array:
	if call_target(call) != symbol_address("___switch8"):
		fail("Unsupported contract choice table.")
		return []
	var table := call + 4
	var file := file_offset(table, 1)
	if file < 0:
		fail("Missing contract choice table.")
		return []
	var count := int(bytes[file])
	if count <= 0 or count > 64 or file_offset(table, count + 2) < 0:
		fail("Invalid contract choice count.")
		return []
	var result := []
	for index in count:
		var target := table + int(bytes[file + 1 + index]) * 2
		if target < table + count + 2 or target >= symbol_end(owner):
			fail("Invalid contract choice association.")
			return []
		result.append(target)
	return result


func contract_constant_branch(address: int) -> int:
	var opcode := u16(address)
	if opcode & 0xf800 != 0xe000:
		fail("Unsupported contract constant association.")
		return -1
	var distance := (opcode & 0x7ff) * 2
	if distance & 0x800:
		distance -= 0x1000
	return address + 4 + distance


func source_text_index(call: int) -> int:
	if (
		call_target(call) != symbol_address("__ZN7Mission7getTypeEv")
		or call_target(call + 12) != symbol_address("__ZN8GameText7getTextEi")
		or u16(call + 8) != 0x18c1
	):
		fail("Unsupported freelance localization association.")
		return -1
	return shifted_at(call + 4, call + 6, 3)


func imported_symbols() -> Dictionary:
	# Mach-O indirect symbol entries bind small call stubs to arithmetic helpers.
	# Resolve their names as file metadata; never execute or interpret their code.
	var offset := 28
	var sections: Array = []
	var symbol_table := []
	var indirect := []
	for index in bytes.decode_u32(16):
		var command := bytes.decode_u32(offset)
		var size := bytes.decode_u32(offset + 4)
		if command == 1:
			var count := bytes.decode_u32(offset + 48)
			if count > 4096 or size < 56 + count * 68:
				fail("Invalid native section directory.")
				return {}
			for entry in count:
				var field := offset + 56 + entry * 68
				if bytes.decode_u32(field + 56) & 255 == 8:
					sections.append(
						[
							bytes.decode_u32(field + 32),
							bytes.decode_u32(field + 36),
							bytes.decode_u32(field + 60),
							bytes.decode_u32(field + 64)
						]
					)
		elif command == 2:
			symbol_table = [
				bytes.decode_u32(offset + 8),
				bytes.decode_u32(offset + 12),
				bytes.decode_u32(offset + 16),
				bytes.decode_u32(offset + 20)
			]
		elif command == 11:
			if size < 80 or not indirect.is_empty():
				fail("Invalid native indirect symbol directory.")
				return {}
			indirect = [bytes.decode_u32(offset + 56), bytes.decode_u32(offset + 60)]
		offset += size
	if (
		symbol_table.is_empty()
		or indirect.is_empty()
		or indirect[1] > 200000
		or not valid_range(indirect[0], indirect[1] * 4)
	):
		fail("Missing or truncated native import bindings.")
		return {}
	var result := {}
	for section in sections:
		if (
			section[3] <= 0
			or section[1] % section[3] != 0
			or section[1] / section[3] > 200000
			or section[2] + section[1] / section[3] > indirect[1]
			or file_offset(section[0], section[1]) < 0
		):
			fail("Invalid native import stub range.")
			return {}
		for index in int(section[1] / section[3]):
			var symbol := bytes.decode_u32(indirect[0] + (section[2] + index) * 4)
			if symbol & 0xc0000000:
				continue
			if symbol >= symbol_table[1]:
				fail("Invalid indirect symbol reference.")
				return {}
			var name_offset := bytes.decode_u32(symbol_table[0] + symbol * 12)
			if name_offset >= symbol_table[3]:
				fail("Invalid import name reference.")
				return {}
			var name := string_at_file(
				symbol_table[2] + name_offset, symbol_table[2] + symbol_table[3]
			)
			if not result.has(name):
				result[name] = []
			result[name].append(section[0] + index * section[3])
	return result if error.is_empty() else {}


func contract_spawn_divisor(types: Array) -> int:
	var start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	for pair in [
		[0xc2, "__ZN6Status12campaignModeEv"],
		[0xd2, "__ZN6Status10getMissionEv"],
		[0xe2, "__ZN6Status10getMissionEv"],
		[0xe6, "__ZN7Mission7getTypeEv"],
		[0xf2, "__ZN6Status10getMissionEv"],
		[0xf6, "__ZN7Mission7getTypeEv"]
	]:
		if call_target(start + pair[0]) != symbol_address(pair[1]):
			fail("Unsupported freelance spawn classification.")
			return 0
	# The freelance type checks select the shared signed-integer division of
	# all three randomly sampled offsets. Division happens after sampling;
	# narrowing the random bounds would change the source distribution.
	for pair in [
		[0xc6, 0x2800],
		[0xc8, 0xd001],
		[0xd6, 0x2800],
		[0xd8, 0xd101],
		[0xec, 0xd018],
		[0xfc, 0xd010],
		[0xfe, 0xe011],
		[0x120, 0x2201],
		[0x122, 0xe000],
		[0x124, 0x2200],
		[0x130, 0x2a00],
		[0x132, 0xd00e],
		[0x134, 0x9831],
		[0x13e, 0x9031],
		[0x140, 0x9832],
		[0x148, 0x9032],
		[0x14a, 0x9833],
		[0x150, 0x9033]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported freelance spawn division binding.")
			return 0
	for offset in [0xea, 0xfa]:
		if u16(start + offset) & 0xff00 != 0x2800:
			fail("Unsupported freelance spawn type comparison.")
			return 0
	var declared := [u16(start + 0xea) & 255, u16(start + 0xfa) & 255]
	var expected := types.duplicate()
	declared.sort()
	expected.sort()
	if declared != expected:
		fail("Freelance spawn division does not match the hunt families.")
		return 0
	var helpers := imported_symbols()
	for offset in [0x138, 0x142, 0x14c]:
		if not helpers.get("___divsi3", []).has(call_target(start + offset)):
			fail("Unsupported freelance spawn rounding semantics.")
			return 0
	var divisor := immediate_at(start + 0x136, 1)
	if (
		divisor <= 0
		or immediate_at(start + 0x13c, 1) != divisor
		or immediate_at(start + 0x146, 1) != divisor
	):
		fail("Invalid freelance spawn divisor.")
		return 0
	return divisor if error.is_empty() else 0


func contract_hunt() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var dispatches := calls_between(level, level + 1400, "___switch32")
	if dispatches.size() != 1:
		fail("Unsupported freelance encounter dispatch.")
		return {}
	var table: int = dispatches[0] + 4
	var count := u32(table)
	if count <= 0 or count > 64:
		fail("Invalid freelance encounter count.")
		return {}
	var start := table + u32(table + 4)
	var types := []
	for index in count:
		if table + u32(table + 4 + index * 4) == start:
			types.append(index)
	if start < level or start + 0x422 >= symbol_end(level):
		fail("Invalid designated-target encounter boundary.")
		return {}
	var calls := {
		0x2e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x44: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x54: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x7e: "__ZN5RouteC1EPii",
		0xa6: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x158: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0x1c4: "__ZN3FogC1EP8Waypoint",
		0x206: "__ZN7Mission21getRelativeDifficultyEi",
		0x248: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x25a: "__ZN7Globals22getRandomTerranFighterEv",
		0x2b4: "__ZN5Level10createShipEiiibP8Waypoint",
		0x2c8: "__ZN8KIPlayer10setToSleepEv",
		0x2d8: "__ZN7Mission13getDifficultyEv",
		0x2f0: "__ZN6Status8getLevelEv",
		0x334: "__ZN6Player15setMaxHitpointsEi",
		0x378: "__ZN7Globals22getRandomTerranFighterEv",
		0x3b4: "__ZN5Level10createShipEiiibP8Waypoint",
		0x3c6: "__ZN8KIPlayer10setToSleepEv",
		0x3d6: "__ZN13PlayerFighter16changeTrailColorEi",
		0x40e: "__ZN9ObjectiveC1EiiP5Level"
	}
	for offset in calls:
		if call_target(start + offset) != symbol_address(calls[offset]):
			fail("Unsupported designated-target encounter declaration.")
			return {}
	var helpers := imported_symbols()
	for pair in [
		[0x210, "___divsf3vfp"],
		[0x216, "___mulsf3vfp"],
		[0x21a, "___fixsfsivfp"],
		[0x318, "___subsf3vfp"],
		[0x320, "___mulsf3vfp"],
		[0x328, "___addsf3vfp"],
		[0x32c, "___fixsfsivfp"]
	]:
		if not helpers.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported designated-target arithmetic association.")
			return {}
	if (
		u16(start + 0x21e) & 0xff00 != 0x3000
		or u16(start + 0x2f8) != 0x1963
		or u16(start + 0x2fa) != 0x4348
		or u16(start + 0x2fc) != 0x1818
	):
		fail("Unsupported designated-target count or health association.")
		return {}

	if (
		immediate_at(start + 0x76, 2) != 3
		or immediate_at(start + 0x400, 1) != 7
		or immediate_at(start + 0x404, 2) != 1
		or immediate_at(start + 0xa0, 1) != 2
	):
		fail("Unsupported designated-target route or objective.")
		return {}
	var objective := symbol_address("__ZN9Objective8achievedEi")
	var objective_tables := calls_between(objective, symbol_end(objective), "___switch8")
	if objective_tables.size() != 1:
		fail("Unsupported designated-target completion rule.")
		return {}
	var objectives := contract_choice_targets(objective_tables[0], objective)
	if (
		objectives.size() <= 7
		or call_target(objectives[7] + 2) != symbol_address("__ZN5Level10getEnemiesEv")
		or call_target(objectives[7] + 22) != symbol_address("__ZN8KIPlayer6isDeadEv")
		or u16(objectives[7] + 36) != 0x429c
	):
		fail("Unsupported designated-target completion association.")
		return {}
	var chooser := symbol_address("__ZN7Globals22getRandomTerranFighterEv")
	var choices := contract_choice_targets(chooser + 16, chooser)
	if choices.is_empty() or choices.size() + 1 != immediate_at(chooser + 6, 1):
		fail("Unsupported freelance fighter choices.")
		return {}
	var choice_table := chooser + 20
	var file := file_offset(choice_table + choices.size() + 1, 1)
	if file < 0:
		fail("Truncated freelance fighter default choice.")
		return {}
	choices.append(choice_table + int(bytes[file]) * 2)
	var actors := []
	for target in choices:
		if target < chooser or target + 2 >= symbol_end(chooser) or u16(target) & 0xff00 != 0x2000:
			fail("Unsupported freelance fighter constant.")
			return {}
		actors.append(immediate_at(target, 0))
	var factory_start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var difficulty := literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0)
	var factory := fighter_factory_data(-1, difficulty)
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var divisor_address := literal(relative + 4, 3)
	var regions := named_array(TABLES.quadrant_difficulty).size()
	var fields := {
		"types": types,
		"family": "designated_target",
		"route_bounds":
		[
			[
				signed_literal(start + 0x32, 2),
				signed_literal(start + 0x32, 2) + literal(start + 0x2c, 1) - 1
			],
			[
				signed_literal(start + 0x1c, 5),
				signed_literal(start + 0x1c, 5) + literal(start + 0x3a, 1) - 1
			],
			[
				signed_literal(start + 0x58, 2),
				signed_literal(start + 0x58, 2) + literal(start + 0x50, 1) - 1
			]
		],
		"relative_divisors": int_array(divisor_address, regions),
		"count_divisor": literal_float(start + 0x20e, 1),
		"count_factor": literal_float(start + 0x214, 1),
		"count_base": u16(start + 0x21e) & 255,
		"target_actors": actors,
		"escort_terran_race": u16(start + 0x358) & 255,
		"escort_actor": immediate_at(start + 0x35e, 0),
		"target_hull_base": shifted_at(start + 0x2be, start + 0x2c0, 5),
		"difficulty_offset": literal_float(start + 0x304, 1),
		"difficulty": difficulty,
		"factory_divisor": literal_float(factory_start + 0x1c2, 1),
		"factory_minimum": immediate_at(factory_start + 0x1ce, 0),
		"factory_rank_scale": factory.hull_rule.rank_scale,
		"factory_offset": literal_float(factory_start + 0x204, 1),
		"scatter": factory.scatter,
		"scatter_divisor": contract_spawn_divisor(types),
		"combat": interceptor_combat(),
		"freelance_guns": contract_gun_data(),
		"asteroids": asteroid_field_definition(immediate_at(start + 0x14a, 1), 0),
		"fog": fog_presentation(),
		"radio":
		contract_radio_data(
			level, immediate_at(symbol_address("__ZN9Generator14getMissionListEv") + 0x8e, 1)
		)
	}
	return fields if error.is_empty() else {}


func contract_battles() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var tables := calls_between(level, level + 1400, "___switch32")
	if tables.size() != 1:
		fail("Unsupported combat contract dispatch.")
		return {}
	var table: int = tables[0] + 4
	var count := u32(table)
	if count < 1 or count > 64:
		fail("Invalid combat contract dispatch size.")
		return {}
	var variants := []
	var types := []
	for index in count:
		var start := table + u32(table + 4 + index * 4)
		if start < level or start + 0x384 >= symbol_end(level):
			continue
		var pirates := call_target(start + 0x2b4) == symbol_address("__ZN5Level13createWingmanEv")
		var combat := call_target(start + 0x1ec) == symbol_address("__ZN5Level13createWingmanEv")
		if not pirates and not combat:
			continue
		if pirates and combat:
			fail("Ambiguous combat contract family.")
			return {}
		var value := contract_battle_branch(start, pirates)
		if value.is_empty():
			return {}
		value["type"] = index
		variants.append(value)
		types.append(index)
	if variants.size() != 2:
		fail("Missing combat contract family declarations.")
		return {}
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	return (
		{
			"family": "enemy_group",
			"types": types,
			"variants": variants,
			"relative_divisors":
			int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
			"wingman": contract_wingman()
		}
		if error.is_empty()
		else {}
	)


func contract_battle_branch(start: int, pirates: bool) -> Dictionary:
	var calls: Dictionary
	var bindings: Array
	if pirates:
		calls = {
			0x56: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x6a: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x7c: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x8e: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xa4: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xb6: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xc0: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xda: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xee: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x114: "__ZN5RouteC1EPii",
			0x14a: "__ZN5RouteC1EPii",
			0x1c2: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x1f8: "__ZN5Route6lengthEv",
			0x208: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x210: "__ZN5Route11getWaypointEi",
			0x228: "__ZN13AsteroidFieldC1EiP8Waypoint",
			0x260: "__ZN5Route6lengthEv",
			0x272: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x27e: "__ZN5Route11getWaypointEi",
			0x294: "__ZN3FogC1EP8Waypoint",
			0x2b4: "__ZN5Level13createWingmanEv",
			0x2c0: "__ZN6Status10getMissionEv",
			0x2ca: "__ZN6Status10getStationEv",
			0x2ce: "__ZN7Station11getQuadrantEv",
			0x2d6: "__ZN7Mission21getRelativeDifficultyEi",
			0x2e0: "__ZN6Status10getStationEv",
			0x2e4: "__ZN7Station11getQuadrantEv",
			0x332: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
			0x380: "__ZN5Route6lengthEv",
			0x38c: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x394: "__ZN5Route11getWaypointEi",
			0x3a6: "__ZN5Level10createShipEiiibP8Waypoint",
			0x3b8: "__ZN8KIPlayer10setToSleepEv",
			0x3f0: "__ZN9ObjectiveC1EiiP5Level"
		}
		bindings = [
			[0x60, 0x446b],
			[0x62, 0x1880],
			[0x64, 0x6018],
			[0x72, 0x4469],
			[0x74, 0x1940],
			[0x76, 0x6008],
			[0x86, 0x446b],
			[0x88, 0x1880],
			[0x8a, 0x6018],
			[0x96, 0x446c],
			[0x9a, 0x1940],
			[0x9c, 0x6020],
			[0xac, 0x446a],
			[0xae, 0x1840],
			[0xb0, 0x6010],
			[0xc4, 0x9b7b],
			[0xca, 0x446d],
			[0xcc, 0x1818],
			[0xce, 0x1900],
			[0xd0, 0x6028],
			[0x126, 0x239c],
			[0x128, 0x4469],
			[0x12c, 0x2301],
			[0x140, 0x4469],
			[0x1ac, 0x681b],
			[0x1ae, 0x5029],
			[0x1c6, 0x2800],
			[0x1c8, 0xd002],
			[0x1ca, 0x2801],
			[0x1cc, 0xd16c],
			[0x1ce, 0xe036],
			[0x2ea, 0x9025],
			[0x304, 0x1828],
			[0x390, 0x1c01],
			[0x398, 0x2301],
			[0x39c, 0x9300],
			[0x39e, 0x2100],
			[0x3a2, 0x9001],
			[0x400, 0x615a]
		]
	else:
		calls = {
			0x2e: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x44: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x54: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x7e: "__ZN5RouteC1EPii",
			0xa8: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xe6: "__ZN5Route6lengthEv",
			0xf0: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0xf8: "__ZN5Route11getWaypointEi",
			0x114: "__ZN13AsteroidFieldC1EiP8Waypoint",
			0x18c: "__ZN5Route6lengthEv",
			0x198: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x1a0: "__ZN5Route11getWaypointEi",
			0x1ba: "__ZN3FogC1EP8Waypoint",
			0x1e2: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x1ec: "__ZN5Level13createWingmanEv",
			0x200: "__ZN6Status10getMissionEv",
			0x20a: "__ZN6Status10getStationEv",
			0x20e: "__ZN7Station11getQuadrantEv",
			0x216: "__ZN7Mission21getRelativeDifficultyEi",
			0x21e: "__ZN6Status10getStationEv",
			0x222: "__ZN7Station11getQuadrantEv",
			0x272: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
			0x280: "__ZN6Status10getStationEv",
			0x284: "__ZN7Station11getQuadrantEv",
			0x2a8: "__ZN6Status10getMissionEv",
			0x2ac: "__ZN7Mission13getClientRaceEv",
			0x2ba: "__ZN7Globals22getRandomTerranFighterEv",
			0x2d2: "__ZN11AbyssEngine8AERandom7nextIntEi",
			0x316: "__ZN5Route11getWaypointEi",
			0x328: "__ZN5Level10createShipEiiibP8Waypoint",
			0x336: "__ZN8KIPlayer10setToSleepEv",
			0x36e: "__ZN9ObjectiveC1EiiP5Level"
		}
		bindings = [
			[0x34, 0x23a4],
			[0x36, 0x00db],
			[0x38, 0x446b],
			[0x4a, 0x4469],
			[0x4c, 0x1940],
			[0x4e, 0x6008],
			[0x5a, 0x23a5],
			[0x5c, 0x00db],
			[0x5e, 0x446b],
			[0x78, 0x9086],
			[0x96, 0x446c],
			[0x9c, 0x6818],
			[0xac, 0x2800],
			[0xae, 0xd003],
			[0xb0, 0x2801],
			[0xb2, 0xd000],
			[0x1e8, 0xdc02],
			[0x228, 0x9021],
			[0x242, 0x1828],
			[0x288, 0x95b7],
			[0x28a, 0x95d9],
			[0x28c, 0x90d8],
			[0x2b2, 0xd106],
			[0x2be, 0x90b6],
			[0x2c0, 0xe019],
			[0x2d6, 0x2800],
			[0x2d8, 0xd009],
			[0x2e4, 0x3d01],
			[0x2e6, 0x95d8],
			[0x2e8, 0x90b7],
			[0x2ea, 0x91b6],
			[0x2ec, 0xe003],
			[0x2f2, 0x92b7],
			[0x2f4, 0x93b6],
			[0x314, 0x2100],
			[0x31a, 0x2301],
			[0x31c, 0x9300],
			[0x31e, 0x2100],
			[0x320, 0x9ab7],
			[0x322, 0x9bb6],
			[0x324, 0x9001],
			[0x37e, 0x6163]
		]
	for offset in calls:
		if call_target(start + offset) != symbol_address(calls[offset]):
			fail("Unsupported combat contract data consumer.")
			return {}
	for pair in bindings:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported combat contract field binding.")
			return {}
	var count_offset := 0x2e8 if pirates else 0x226
	if u16(start + count_offset) & 0xff00 != 0x3000:
		fail("Unsupported combat contract enemy count.")
		return {}
	var arithmetic := imported_symbols()
	for pair in [[12, "___divsf3vfp"], [18, "___mulsf3vfp"], [22, "___fixsfsivfp"]]:
		if not arithmetic.get(pair[1], []).has(call_target(start + count_offset + pair[0])):
			fail("Unsupported combat contract count arithmetic.")
			return {}
	var objectives_start := symbol_address("__ZN9Objective8achievedEi")
	var tables := calls_between(objectives_start, symbol_end(objectives_start), "___switch8")
	if tables.size() != 1:
		fail("Missing combat contract objective choices.")
		return {}
	var objectives := contract_choice_targets(tables[0], objectives_start)
	var objective := immediate_at(start + (0x3e0 if pirates else 0x36a), 1)
	if (
		objective >= objectives.size()
		or immediate_at(start + (0x3e2 if pirates else 0x360), 2) != 0
		or call_target(objectives[objective] + 6) != symbol_address("__ZN5Level14getEnemiesLeftEv")
	):
		fail("Unsupported combat contract victory rule.")
		return {}
	var value := {
		"selection": "fixed" if pirates else "regional",
		"count_base": u16(start + count_offset) & 255,
		"count_divisor": literal_float(start + count_offset + 10, 1),
		"count_factor": literal_float(start + count_offset + 16, 1),
		"scenery_choices": immediate_at(start + (0x1ba if pirates else 0xa2), 1),
		"asteroids":
		asteroid_field_definition(immediate_at(start + (0x21e if pirates else 0x106), 1), 0),
		"fog": fog_presentation(),
		"success": {"kind": "enemies_destroyed"}
	}
	if pirates:
		# The source replaces its initial three-point route with the first two
		# points. Preserve the live route and the two-roll second Z distribution.
		var origin := literal(start + 0x13a, 1)
		var slots := [
			literal(start + 0x5a, 3),
			shifted_immediate(start + 0x6e, 1),
			literal(start + 0x80, 3),
			shifted_immediate(start + 0x92, 4),
			literal(start + 0xa8, 2),
			shifted_immediate(start + 0xc6, 5)
		]
		if immediate_at(start + 0x148, 2) != slots.size() or literal(start + 0x104, 1) != origin:
			fail("Unsupported pirate route replacement.")
			return {}
		for index in slots.size():
			if slots[index] != origin + index * 4:
				fail("Unsupported pirate coordinate binding.")
				return {}
		value["route_axes"] = [
			{"base": signed_literal(start + 0x5c, 2), "rolls": [literal(start + 0x54, 1)]},
			{"base": signed_literal(start + 0x44, 5), "rolls": [literal(start + 0x5e, 1)]},
			{"base": signed_literal(start + 0x82, 2), "rolls": [literal(start + 0x7a, 1)]},
			{"base": signed_literal(start + 0x44, 5), "rolls": [literal(start + 0x84, 1)]},
			{"base": signed_literal(start + 0xaa, 1), "rolls": [literal(start + 0x98, 1)]},
			{
				"base": signed_literal(start + 0xa0, 4),
				"rolls": [literal(start + 0xb2, 1), literal(start + 0xba, 1)]
			}
		]
		value["actor"] = immediate_at(start + 0x3a0, 3)
		if immediate_at(start + 0x39a, 2) != 0:
			fail("Unsupported pirate ship role.")
			return {}
		value["wingman_chance"] = [1, 1]
	else:
		var origin := shifted_immediate(start + 0x70, 1)
		if (
			shifted_immediate(start + 0x34, 3) != origin
			or literal(start + 0x48, 1) != origin + 4
			or shifted_immediate(start + 0x5a, 3) != origin + 8
			or immediate_at(start + 0x76, 2) != 3
		):
			fail("Unsupported battle coordinate binding.")
			return {}
		value["route_axes"] = [
			{"base": signed_literal(start + 0x32, 2), "rolls": [literal(start + 0x2c, 1)]},
			{"base": signed_literal(start + 0x1c, 5), "rolls": [literal(start + 0x3a, 1)]},
			{"base": signed_literal(start + 0x58, 2), "rolls": [literal(start + 0x50, 1)]}
		]
		if u16(start + 0x1e6) & 0xff00 != 0x2800 or u16(start + 0x2b0) & 0xff00 != 0x2800:
			fail("Unsupported battle selection thresholds.")
			return {}
		value["wingman_chance"] = [(u16(start + 0x1e6) & 255) + 1, immediate_at(start + 0x1e0, 1)]
		value["terran_race"] = u16(start + 0x2b0) & 255
		value["actor_choices"] = immediate_at(start + 0x2c8, 1)
		value["actor"] = immediate_at(start + 0x2f0, 3)
		value["heavy_actor"] = immediate_at(start + 0x2e2, 1)
		var role := immediate_at(start + 0x2e0, 0)
		if immediate_at(start + 0x2ee, 2) != 0:
			fail("Unsupported battle fighter role.")
			return {}
		var quota := call_target(start + 0x2da)
		if (
			u16(quota) != 0x98d8
			or u16(quota + 2) != 0x2800
			or u16(quota + 4) != 0xdd01
			or call_target(quota + 6) != start + 0x2de
			or call_target(quota + 10) != start + 0x2ee
		):
			fail("Unsupported battle regional ship quota.")
			return {}
		value["heavy_combat"] = transport_heavy_combat(int(value.heavy_actor), role)
	return value if error.is_empty() else {}


func contract_wingman() -> Dictionary:
	var start := symbol_address("__ZN5Level13createWingmanEv")
	var calls := {
		0x40: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x56: "__ZN7Mission13getClientRaceEv",
		0x7a: "__ZN7Mission14getClientImageEv",
		0xce: "__ZN12RadioMessageC1Eiiii",
		0xf0: "__ZN7Mission13getClientRaceEv",
		0x108: "__ZN7Globals22getRandomTerranFighterEv",
		0x13a: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x158: "__ZN5Level10createShipEiiibP8Waypoint",
		0x16a: "__ZN6Player11getPositionEv",
		0x17e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x190: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x1b4: "__ZN13PlayerFighter11setPositionEiii",
		0x1ee: "__ZN5Route5cloneEv",
		0x1f6: "__ZN8KIPlayer8setRouteEP5Route",
		0x20e: "__ZN6Player12setHitpointsEi"
	}
	for offset in calls:
		if call_target(start + offset) != symbol_address(calls[offset]):
			fail("Unsupported freelance allied-pilot association.")
			return {}
	# Bind the declarations to their consumers: replace only radio[0], retain
	# special-client messages, spawn beside the player and clone the flight route.
	for pair in [
		[0x56 + 4, 0x2800, 0xff00],
		[0x5c, 0xd102],
		[0x7e, 0x2800, 0xff00],
		[0x80, 0xd02d],
		[0xc0, 0x9300],
		[0xc6, 0x9909],
		[0xc8, 0x9a10],
		[0xca, 0x2305],
		[0xdc, 0x6011],
		[0xf4, 0x2800, 0xff00],
		[0xf6, 0xd102],
		[0x12e, 0x2001],
		[0x142, 0x2000],
		[0x144, 0x2200],
		[0x14a, 0x9000],
		[0x14c, 0x9001],
		[0x152, 0x9b11],
		[0x156, 0x2100],
		[0x170, 0x1c29],
		[0x17c, 0x9505],
		[0x18e, 0x9905],
		[0x1a0, 0x1959],
		[0x1a4, 0x1889],
		[0x1a6, 0x195a],
		[0x1ae, 0x195b],
		[0x1b0, 0x1812],
		[0x1ba, 0x209c],
		[0x1bc, 0x5808],
		[0x1be, 0x2800],
		[0x1c0, 0xd10e],
		[0x1f2, 0x1c01]
	]:
		var mask: int = pair[2] if pair.size() == 3 else 0xffff
		if u16(start + pair[0]) & mask != pair[1] & mask:
			fail("Unsupported freelance allied-pilot field binding.")
			return {}
	if u16(start + 0x5a) != u16(start + 0xf4):
		fail("Inconsistent allied-pilot faction selection.")
		return {}
	var health := symbol_address("__ZN6Player12setHitpointsEi")
	for pair in [[4, 0x6d03], [6, 0x6481], [8, 0x4299], [10, 0xdd00], [12, 0x6501]]:
		if u16(health + pair[0]) != pair[1]:
			fail("Unsupported allied-pilot initial health semantics.")
			return {}
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	return (
		{
			"family": "route_ally",
			"race": u16(start + 0x5a) & 255,
			"actor": immediate_at(start + 0xf8, 5),
			"speaker": immediate_at(start + 0x5e, 1),
			"other_speaker": immediate_at(start + 0x64, 2),
			"preserve_client": u16(start + 0x7e) & 255,
			"opening": int_array(literal(start + 0x44, 3), immediate_at(start + 0x38, 1)),
			"lead_ms": shifted_immediate(start + 0xbc, 3),
			"offset": signed_literal(start + 0x184, 5),
			"spread": shifted_immediate(start + 0x164, 5),
			"ahead": shifted_immediate(start + 0x1aa, 5),
			"initial_hp": shifted_immediate(start + 0x1fc, 1),
			"motion": dict_with_speed(combat.motion, literal_float(fighter + 0x27e, 3) * 20),
			"weapon": friendly_weapon(combat.weapon)
		}
		if error.is_empty()
		else {}
	)


func contract_transport() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var dispatches := calls_between(level, level + 1400, "___switch32")
	if dispatches.size() != 1:
		fail("Unsupported transport encounter dispatch.")
		return {}
	var table: int = dispatches[0] + 4
	var count := u32(table)
	if count <= 0 or count > 64:
		fail("Invalid transport encounter count.")
		return {}
	var start := -1
	var types := []
	for index in count:
		var target := table + u32(table + 4 + index * 4)
		if target < level or target + 0x4ee >= symbol_end(level):
			continue
		if call_target(target + 0x118) == symbol_address("__ZN5RouteC1EPii"):
			if start >= 0 and start != target:
				fail("Ambiguous transport encounter association.")
				return {}
			start = target
			types.append(index)
	if start < 0:
		fail("Missing transport encounter declarations.")
		return {}
	var calls := {
		0x56: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x68: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x7e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x8e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xa6: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xbc: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xca: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xde: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xf2: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x142: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x178: "__ZN5Route6lengthEv",
		0x18a: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x192: "__ZN5Route11getWaypointEi",
		0x1aa: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0x234: "__ZN5Route6lengthEv",
		0x244: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x252: "__ZN5Route11getWaypointEi",
		0x268: "__ZN3FogC1EP8Waypoint",
		0x2a6: "__ZN7Mission21getRelativeDifficultyEi",
		0x2b2: "__ZN7Station11getQuadrantEv",
		0x302: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x314: "__ZN7Station11getQuadrantEv",
		0x342: "__ZN7Mission13getClientRaceEv",
		0x356: "__ZN7Globals22getRandomTerranFighterEv",
		0x36e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x3e4: "__ZN5Route6lengthEv",
		0x3f2: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x3fe: "__ZN5Route11getWaypointEi",
		0x416: "__ZN5Level10createShipEiiibP8Waypoint",
		0x428: "__ZN8KIPlayer10setToSleepEv",
		0x452: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x482: "__ZN9ObjectiveC1EiiP5Level",
		0x4ac: "__ZN8GameText7getTextEi",
		0x4b8: "__ZN9Objective15setAchievedTextEPN11AbyssEngine6StringE",
		0x4de: "__ZN9ObjectiveC1EiiP5Level"
	}
	for offset in calls:
		if call_target(start + offset) != symbol_address(calls[offset]):
			fail("Unsupported transport parameter association.")
			return {}
	# Nine consecutive source integers are three XYZ points, including the
	# unusually high Y coordinate of the last point. Two rolls contribute to
	# the middle Z coordinate; do not flatten their distribution into one roll.
	var route_origin := literal(start + 0x108, 1)
	var slots := [
		literal(start + 0x5a, 1),
		shifted_immediate(start + 0x6c, 3),
		literal(start + 0x82, 1),
		shifted_immediate(start + 0x94, 3),
		literal(start + 0x9c, 5),
		shifted_immediate(start + 0xb4, 5),
		literal(start + 0xe2, 3),
		shifted_immediate(start + 0xf6, 1),
		literal(start + 0x1e, 2)
	]
	if immediate_at(start + 0x116, 2) != slots.size():
		fail("Unsupported transport route dimensions.")
		return {}
	for index in slots.size():
		if slots[index] != route_origin + index * 4:
			fail("Unsupported transport coordinate binding.")
			return {}
	for pair in [
		[0x10, 0x2300],
		[0x3e, 0x6013],
		[0x5e, 0x1940],
		[0x60, 0x6008],
		[0x74, 0x1940],
		[0x76, 0x6018],
		[0x86, 0x1940],
		[0x88, 0x6008],
		[0xa0, 0x1880],
		[0xa2, 0x6018],
		[0xac, 0x1900],
		[0xae, 0x6028],
		[0xc6, 0x908f],
		[0xce, 0x9b8f],
		[0xd0, 0x1818],
		[0xd2, 0x1900],
		[0xd4, 0x6028],
		[0xea, 0x1880],
		[0xec, 0x6018],
		[0xfc, 0x1940],
		[0xfe, 0x6008],
		[0x146, 0x2800],
		[0x148, 0xd003],
		[0x14a, 0x2801],
		[0x14c, 0xd000],
		[0x2d2, 0x1828],
		[0x31a, 0x90db],
		[0x372, 0x2800],
		[0x388, 0x3a01],
		[0x38e, 0x92db],
		[0x392, 0x6005],
		[0x3a6, 0x6011],
		[0x3a8, 0x6023],
		[0x402, 0x2301],
		[0x404, 0x9300],
		[0x40c, 0x2100],
		[0x40e, 0x9001],
		[0x458, 0xdc30],
		[0x45c, 0x22c4],
		[0x460, 0x50a3],
		[0x476, 0x5962],
		[0x4a0, 0x6185],
		[0x4ee, 0x6151]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported transport route, scenery or objective structure.")
			return {}
	if (
		u16(start + 0x2b6) & 0xff00 != 0x3000
		or u16(start + 0x346) & 0xff00 != 0x2800
		or u16(start + 0x456) & 0xff00 != 0x2800
	):
		fail("Unsupported transport count or selection threshold.")
		return {}
	var helpers := imported_symbols()
	for pair in [[0x2c2, "___divsf3vfp"], [0x2c8, "___mulsf3vfp"], [0x2cc, "___fixsfsivfp"]]:
		if not helpers.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported transport count arithmetic.")
			return {}
	var quota := call_target(start + 0x376)
	if (
		quota < level
		or quota + 14 >= symbol_end(level)
		or u16(quota) != 0x99db
		or u16(quota + 2) != 0x2900
		or u16(quota + 4) != 0xdd01
		or call_target(quota + 6) != start + 0x37a
		or call_target(quota + 10) != start + 0x396
	):
		fail("Unsupported regional heavy-ship quota.")
		return {}
	var objective := symbol_address("__ZN9Objective8achievedEi")
	var tables := calls_between(objective, symbol_end(objective), "___switch8")
	if tables.size() != 1:
		fail("Missing transport objective choices.")
		return {}
	var objectives := contract_choice_targets(tables[0], objective)
	var success := immediate_at(start + 0x4d0, 1)
	var deadline := immediate_at(start + 0x480, 1)
	if (
		success >= objectives.size()
		or deadline >= objectives.size()
		or immediate_at(start + 0x4d4, 2) != 0
		or call_target(objectives[success] + 6) != symbol_address("__ZN5Level14getPlayerRouteEv")
		or call_target(objectives[success] + 10) != symbol_address("__ZN5Route15getLastWaypointEv")
		or u16(objectives[success] + 14) != 0x2368
		or u16(objectives[success] + 16) != 0x5cc0
		or u16(objectives[deadline]) != 0x686b
		or u16(objectives[deadline] + 4) != 0x4543
		or u16(objectives[deadline] + 6) & 0xff00 != 0xda00
	):
		fail("Unsupported transport completion semantics.")
		return {}
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var result := {
		"family": "ambushed_route",
		"types": types,
		"route_axes":
		[
			{"base": signed_literal(start + 0x46, 5), "rolls": [literal(start + 0x44, 1)]},
			{"base": signed_literal(start + 0x46, 5), "rolls": [literal(start + 0x64, 1)]},
			{"base": signed_literal(start + 0x7a, 5), "rolls": [literal(start + 0x72, 1)]},
			{"base": signed_literal(start + 0x92, 2), "rolls": [literal(start + 0x8c, 1)]},
			{"base": signed_literal(start + 0xaa, 4), "rolls": [literal(start + 0x9a, 1)]},
			{
				"base": signed_literal(start + 0xb2, 4),
				"rolls": [literal(start + 0xba, 1), literal(start + 0xc2, 1)]
			},
			{"base": signed_literal(start + 0xe4, 2), "rolls": [literal(start + 0xdc, 1)]},
			{"base": signed_literal(start + 0xd8, 5), "rolls": [literal(start + 0xe6, 1)]},
			{"base": immediate_at(start + 0x10, 3), "rolls": []}
		],
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"count_base": u16(start + 0x2b6) & 255,
		"count_divisor": literal_float(start + 0x2c0, 1),
		"count_factor": literal_float(start + 0x2c6, 1),
		"scenery_choices": immediate_at(start + 0x13a, 1),
		"asteroids": asteroid_field_definition(immediate_at(start + 0x1a0, 1), 0),
		"fog": fog_presentation(),
		"terran_race": u16(start + 0x346) & 255,
		"actor_choices": immediate_at(start + 0x36c, 1),
		"default_actor": immediate_at(start + 0x3a4, 3),
		"default_role": immediate_at(start + 0x3a2, 1),
		"heavy_actor": immediate_at(start + 0x38c, 5),
		"heavy_role": immediate_at(start + 0x38a, 3),
		"deadline_choices": immediate_at(start + 0x450, 1),
		"deadline_threshold": u16(start + 0x456) & 255,
		"deadline_ms": literal(start + 0x45a, 3),
		"failure_text": literal(start + 0x4aa, 1),
		"success": {"kind": "route_finished"}
	}
	result["heavy_combat"] = transport_heavy_combat(int(result.heavy_actor), int(result.heavy_role))
	return result if error.is_empty() else {}


func transport_heavy_combat(actor: int, role: int) -> Dictionary:
	var factory := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var tables := calls_between(factory, factory + 700, "___switch32")
	if tables.size() != 1:
		fail("Unsupported transport heavy factory dispatch.")
		return {}
	var table: int = tables[0] + 4
	if role < 0 or role >= u32(table):
		fail("Invalid transport heavy role.")
		return {}
	var branch := table + u32(table + 4 + role * 4)
	var setter := symbol_address("__ZN13PlayerFighter13setShootErrorEi")
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	if (
		call_target(branch + 0x2c) != symbol_address("__ZN13PlayerFighterC1EibP6Playeriii")
		or call_target(branch + 0x44) != setter
		or u16(branch + 0x26) != 0x2201
		or u16(setter) != 0x23d4
		or u16(setter + 2) != 0x50c1
		or u16(fighter + 0x1bc) != 0x2b00 + actor
		or u16(fighter + 0x1c4) != 0x22e0
		or u16(fighter + 0x1cc) != 0x508b
	):
		fail("Unsupported transport heavy movement association.")
		return {}
	var result := interceptor_combat()
	if result.is_empty():
		return {}
	result.motion.aim_sine = float(literal(branch + 0x38, 1)) / normalized_vector_unit()
	result.motion.avoid_distance = literal(fighter + 0x1ca, 3) * .02
	result.weapon = rocket_weapon(actor)
	return result if error.is_empty() else {}


func rocket_weapon(actor: int) -> Dictionary:
	var start := symbol_address("__ZN5Level10assignGunsEv")
	var guns := calls_between(start, symbol_end(start), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_").filter(
		func(call): return u16(call + 16) == 0x2284 and u16(call + 20) == 0x508b
	)
	if guns.size() != 1:
		fail("Unsupported heavy rocket declaration.")
		return {}
	var gun := int(guns[0])
	if (
		u16(gun - 122) != 0x2800 + actor
		or u16(gun - 112) & 0xff00 != 0x3000
		or u16(gun - 32) != 0x9300
		or u16(gun - 28) != 0x9301
		or call_target(gun + 60) != symbol_address("__ZN8KIPlayer6addGunEP3Guni")
		or call_target(gun + 98) != symbol_address("__ZN9RocketGunC1EiP3Guniijib")
		or immediate_at(gun + 88, 3) != 1
		or u16(gun + 90) != 0x9303
		or u16(gun + 86) != 0x9302
	):
		fail("Unsupported heavy rocket ownership or guidance flag.")
		return {}
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var result: Dictionary = combat.weapon.duplicate(true)
	var factor := (
		1 + literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0) - literal_float(gun - 104, 1)
	)
	result.damage_rule.base = u16(gun - 112) & 255
	result.damage_rule.minimum = 0
	result.damage_rule.factor = factor
	var rank := immediate_at(symbol_address("__ZN6StatusC2Ev") + 16, 4)
	result.damage = int(
		(result.damage_rule.base + rank / int(result.damage_rule.level_divisor)) * factor
	)
	result.interval = literal(gun - 38, 3) / 1000.0
	result.speed = immediate_at(gun - 30, 3) * 20.0
	result.lifetime = literal(gun - 2, 3) / 1000.0
	result.merge(shared_gun_pool(immediate_at(gun - 34, 2), immediate_at(gun + 16, 2)), true)
	result.erase("pool_id")
	# ObjectGun owns the body; RocketGun adds an independently registered glow.
	var constructor := symbol_address("__ZN9RocketGunC2EiP3Guniijib")
	if (
		call_target(constructor + 0x52) != symbol_address("__ZN9ObjectGunC2EiP3Gunij")
		or call_target(constructor + 0x94) != symbol_address("__ZN5TrailC1Eii")
		or (
			call_target(constructor + 0xc4)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		)
		or (
			call_target(symbol_address("__ZN9RocketGun6renderEv") + 6)
			!= symbol_address("__ZN9ObjectGun6renderEv")
		)
	):
		fail("Unsupported rocket body or glow association.")
		return {}
	result["projectile_model"] = literal(gun + 96, 3)
	result["projectile_overlay"] = literal(gun + 70, 3)
	result["guidance"] = rocket_guidance(int(result.projectile_overlay))
	result["trail"] = {
		"style": immediate_at(gun + 84, 3), "segments": immediate_at(constructor + 0x92, 2)
	}
	return result if error.is_empty() else {}


func rocket_guidance(model: int) -> Dictionary:
	var acquire := symbol_address("__ZN9RocketGun9seekEnemyEi")
	var update := symbol_address("__ZN9RocketGun6updateEi")
	var constructor := symbol_address("__ZN9RocketGunC2EiP3Guniijib")
	var calls := {
		0x3e: "__ZN6Player8isActiveEv",
		0x4a: "__ZN6Player6isDeadEv",
		0x6a: "__ZN6Player11getPositionEv",
		0x7e: "__ZN11AbyssEngine11PaintCanvas17GetScreenPositionERKNS_6AEMath6VectorERS2_",
		0xf2: "__ZN6Player11getPositionEv",
		0x17c: "__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE"
	}
	for offset in calls:
		if call_target(acquire + offset) != symbol_address(calls[offset]):
			fail("Unsupported guided projectile target association.")
			return {}
	if (
		call_target(update + 0xd4) != acquire
		or u16(update + 0xca) & 0xff00 != 0x3a00
		or u16(update + 0xcc) != 0x4293
		or u16(update + 0xce) != 0xda03
		or u16(acquire + 0x120) != 0x6cb1
		or u16(acquire + 0x126) != 0x434c
		or u16(constructor + 0x80) != 0x6493
		or u16(constructor + 0xf0) != 0x649a
	):
		fail("Unsupported rocket guidance delay or response binding.")
		return {}
	var helpers := imported_symbols()
	for offset in [0x12a, 0x134, 0x13e]:
		if not helpers.get("___divsi3", []).has(call_target(acquire + offset)):
			fail("Unsupported rocket steering arithmetic.")
			return {}
	var upper := signed_literal(acquire + 0x8c, 5)
	if literal(acquire + 0x92, 2) != upper * 2 or signed_literal(acquire + 0xa6, 2) != -upper - 1:
		fail("Unsupported guided projectile acquisition volume.")
		return {}
	var result := {
		"delay": float(u16(update + 0xca) & 255) / 1000.0,
		"response_divisor":
		immediate_at(constructor + (0x7e if model > 0 else 0xec), 3 if model > 0 else 2),
		"acquisition_half_width": upper * .02,
		"distance_squared_limit": literal(acquire + 0x28, 4) * .02 * .02
	}
	if not preload("res://src/simulation/guidance.gd").valid_parameters(result):
		fail("Invalid guided rocket parameters.")
	return result if error.is_empty() else {}


func contract_gun_data() -> Dictionary:
	var start := symbol_address("__ZN5Level10assignGunsEv")
	# Freelance rank contribution adds the station quadrant before the common
	# gun initializer. A separate source Gun pool is assigned to one actor type.
	for pair in [
		[0x62, "__ZN6Status12campaignModeEv"],
		[0x6c, "__ZN6Status10getStationEv"],
		[0x70, "__ZN7Station11getQuadrantEv"],
		[0x75e, "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"],
		[0xbb8, "__ZN8KIPlayer7getTypeEv"],
		[0xbc6, "__ZN8KIPlayer7getTypeEv"],
		[0xbee, "__ZN8KIPlayer6addGunEP3Guni"]
	]:
		if call_target(start + pair[0]) != symbol_address(pair[1]):
			fail("Unsupported freelance gun association.")
			return {}
	for pair in [
		[0x66, 0x2800],
		[0x68, 0xd107],
		[0x74, 0x9e49],
		[0x76, 0x1836],
		[0x78, 0x9649],
		[0x73c, 0x9300],
		[0x740, 0x9301],
		[0x75a, 0x9956],
		[0x774, 0x5031],
		[0xbca, 0x2800, 0xff00],
		[0xbd6, 0x58e1],
		[0xbe8, 0x6fd1]
	]:
		var mask: int = pair[2] if pair.size() == 3 else 0xffff
		if u16(start + pair[0]) & mask != pair[1]:
			fail("Unsupported freelance gun field binding.")
			return {}
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var alternate: Dictionary = combat.weapon.duplicate(true)
	alternate.interval = shifted_immediate(start + 0x736, 3) / 1000.0
	alternate.speed = immediate_at(start + 0x73e, 3) * 20.0
	alternate.lifetime = literal(start + 0x75c, 3) / 1000.0
	alternate.merge(
		shared_gun_pool(immediate_at(start + 0x744, 2), immediate_at(start + 0x770, 0)), true
	)
	return (
		{
			"region_damage": true,
			"alternate_actor": u16(start + 0xbca) & 255,
			"alternate_weapon": alternate
		}
		if error.is_empty()
		else {}
	)


func contract_radio_data(level: int, types: int) -> Dictionary:
	var constructor := symbol_address("__ZN12RadioMessageC1Eiiii")
	for offset in [0x120, 0x1c2, 0x244, 0x2b0, 0x33e, 0x3a6]:
		if call_target(level + offset) != constructor:
			fail("Unsupported freelance radio declarations.")
			return {}
	# Time, mission success and previous-message associations are the same
	# source radio tags already supported by the native message scheduler.
	for pair in [[0x11e, 5], [0x1be, 5], [0x240, 7], [0x2ac, 6], [0x33c, 5], [0x3a2, 7]]:
		if immediate_at(level + pair[0], 3) != pair[1]:
			fail("Unsupported freelance radio condition.")
			return {}
	return {
		"start": int_array(literal(level + 0x30e, 3), immediate_at(level + 0x302, 1)),
		"success": int_array(literal(level + 0x36e, 3), immediate_at(level + 0x368, 1)),
		"lead_ms": shifted_at(level + 0x328, level + 0x32a, 3),
		"special_start": int_array(literal(level + 0xf2, 3), types),
		"special_messages": int_array(literal(level + 0x172, 3), immediate_at(level + 0x15a, 1)),
		"special_success": int_array(literal(level + 0x204, 3), immediate_at(level + 0x1f8, 1)),
		"special_reply": int_array(literal(level + 0x26e, 3), immediate_at(level + 0x268, 1)),
		"special_count": [u16(level + 0xa8) & 255, immediate_at(level + 0x9c, 1)],
		"special_time_base": literal(level + 0x148, 0),
		"special_time_step": literal(level + 0x1d6, 2),
		"special_time_jitter": literal(level + 0x192, 1),
		"reply_speaker": immediate_at(level + 0x2ae, 2)
	}


func flight_image_binding(resource: int) -> Dictionary:
	# Two HUD resource records use compiler layouts outside the ordinary atlas
	# recognizer: a temporary stack slot and a literal pool splitting a record.
	# Recognize those declarations explicitly instead of evaluating instructions.
	var registry := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	# Radar records retain their identifiers in separate temporary stack slots.
	for record in [
		[
			0x22d6,
			2,
			0x22dc,
			0x9281,
			0x2300,
			0xaa81,
			0x2304,
			0x8812,
			0x230a,
			0x8002,
			0x22e8,
			3,
			0x22f2
		],
		[
			0x231a,
			3,
			0x2320,
			0x9380,
			0x2490,
			0xab80,
			0x2494,
			0x881b,
			0x249a,
			0x8003,
			0x2478,
			2,
			0x2482
		]
	]:
		if resource != shifted_immediate(registry + record[0], record[1]):
			continue
		for index in [2, 4, 6, 8]:
			if u16(registry + record[index]) != record[index + 1]:
				fail("Unsupported radar atlas temporary record.")
				return {}
		return {
			"texture": immediate_at(registry + record[10], record[11]),
			"region": immediate_at(registry + record[12], 3)
		}
	var fire_id := shifted_immediate(registry + 0x235e, 2)
	if resource == fire_id:
		if (
			u16(registry + 0x2364) != 0x927f
			or u16(registry + 0x258a) != 0xab7f
			or u16(registry + 0x258e) != 0x881b
			or u16(registry + 0x2594) != 0x8003
		):
			fail("Unsupported fire overlay atlas declaration.")
			return {}
		return {
			"texture": immediate_at(registry + 0x2572, 2),
			"region": immediate_at(registry + 0x257c, 3)
		}
	var stack_id := shifted_immediate(registry + 0x23a0, 2)
	var split_id := shifted_immediate(registry + 0x28fe, 3)
	if resource == stack_id:
		if (
			u16(registry + 0x23a6) != 0x927e
			or u16(registry + 0x2684) != 0xab7e
			or u16(registry + 0x2688) != 0x881b
			or u16(registry + 0x268e) != 0x8003
			or u16(registry + 0x2672) != 0x8002
			or u16(registry + 0x267e) != 0x8053
		):
			fail("Unsupported flight atlas temporary record.")
			return {}
		return {
			"texture": immediate_at(registry + 0x266c, 2),
			"region": immediate_at(registry + 0x2676, 3)
		}
	if resource == split_id:
		if (
			u16(registry + 0x2870) != 0xe042
			or u16(registry + 0x2872) != 0x46c0
			or u16(registry + 0x2864) != 0x8002
			or u16(registry + 0x28f8) != 0x8053
			or u16(registry + 0x2906) != 0x8003
		):
			fail("Unsupported flight atlas split record.")
			return {}
		return {
			"texture": immediate_at(registry + 0x285e, 2),
			"region": immediate_at(registry + 0x2868, 3)
		}
	return ui_region_binding(resource)


func flight_presentation() -> Dictionary:
	# Constructor image associations and draw operands identify normal/pressed
	# controls. Only atlas bindings leave this reader, never executable routines.
	var ctor := symbol_address("__ZN3HudC2Ev")
	var draw := symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	var images := {}
	for record in [
		[0x7c, 0x80, false],
		[0x86, 0x8e, true],
		[0x96, 0x9a, false],
		[0xa0, 0xa8, true],
		[0xb0, 0xb4, false],
		[0xbc, 0xc0, false],
		[0xc8, 0xcc, false],
		[0xd4, 0xd8, false]
	]:
		var address: int = ctor + int(record[0])
		var call: int = ctor + int(record[1])
		var destination := u16(call - 2)
		var field := destination & 255
		if destination & 0xff00 != 0x3200 or call_target(call) != create or images.has(field):
			fail("Unsupported flight control image declarations.")
			return {}
		var resource := literal(address, 1)
		if record[2]:
			if u16(address + 4) != 0x0089:
				fail("Unsupported flight control resource association.")
				return {}
			resource = immediate_at(address, 1) * 4
		if resource < 0:
			fail("Missing flight control resource association.")
			return {}
		images[field] = flight_image_binding(resource)
		if images[field].is_empty() or not error.is_empty():
			return {}
	var controls := {}
	var declarations := {
		"missiles": [0xcfe, 0xcc6],
		"weapon": [0xc2e, 0xbf2],
		"pause": [0xb76, 0xb5e],
		"boost": [0x10a8, 0x1078]
	}
	for name in declarations:
		var bindings := {}
		for index in 2:
			var operand := u16(draw + int(declarations[name][index]))
			var field := ((operand >> 6) & 31) * 4
			if operand & 0xf807 != 0x6801 or not images.has(field):
				fail("Unsupported flight control drawing association.")
				return {}
			bindings["normal" if index == 0 else "pressed"] = images[field]
		controls[name] = bindings
	var tutorial := tutorial_presentation()
	if tutorial.is_empty():
		return {}
	return {
		"buttons": controls,
		"tutorial": tutorial,
		"artwork": flight_artwork(),
		"radar": radar_presentation(),
		"damage": damage_presentation()
	}


func travel_rules() -> Dictionary:
	var update := symbol_address("__ZN4MMap8OnUpdateEv")
	var initialize := symbol_address("__ZN4MMap12OnInitializeEv")
	var distance := symbol_address("__ZN4MMap16quadrantDistanceEii")
	var root := symbol_address("__ZN6Galaxy4sqrtEf")
	var rating := symbol_address("__ZN6Status12changeRatingEi")
	var initial := symbol_address("__ZN6StatusC2Ev")
	var reset := symbol_address("__ZN6Status9resetGameEv")
	var mission := symbol_address("__ZN6Status10missionEndEv")
	var campaign := symbol_address("__ZN7MissionC2Eii")
	var touch := symbol_address("__ZN4MMap10OnTouchEndEii")
	var explored := symbol_address("__ZN6Status11allExploredEv")
	if (
		call_target(update + 0x474) != symbol_address("__ZN4MMap8distanceEffff")
		or call_target(update + 0x49c) != distance
		or call_target(update + 0x4be) != symbol_address("__ZN6Status9getRatingEv")
		or call_target(mission + 0x40) != rating
		or call_target(touch + 0xd2) != rating
	):
		fail("Unsupported travel or faction rule consumers.")
		return {}
	if (
		u16(initial + 0x20) != 0x6041
		or u16(reset + 0x3c) != 0x6053
		or u16(campaign + 0x10) != 0x6103
		or u16(symbol_address("__ZN7Mission13getClientRaceEv")) != 0x6900
		or u16(initialize + 0x2b2) != 0x005b
	):
		fail("Unsupported travel state or map projection declarations.")
		return {}
	var limit := u16(rating + 6)
	var iterations := u16(root + 0x60)
	var diagonal := u16(distance + 2)
	if (
		limit & 0xff00 != 0x2900
		or iterations & 0xff00 != 0x2e00
		or diagonal & 0xff00 != 0x2b00
		or u16(rating + 0x14) != 0x425b
		or u16(mission + 0x2e) != 0x4249
	):
		fail("Unsupported faction limits or travel precision declarations.")
		return {}
	var result := {
		"pixel_extent":
		[immediate_at(initialize + 0x2b0, 3) * 2, immediate_at(initialize + 0x2ba, 2)],
		"coordinate_extent": literal_float(update + 0x3ee, 1),
		"space_extent": literal_float(initialize + 0x56a, 0),
		"distance_rate": literal_float(update + 0x478, 1),
		"quadrant_rate": literal_float(update + 0x4a0, 1),
		"quadrant_weights":
		[
			literal_float(distance + 0x12, 0),
			literal_float(distance + 0xe, 0),
			literal_float(distance + 6, 0)
		],
		"opposite_sum": diagonal & 255,
		"distance_resolution":
		literal_float(root + 0xc, 5) * pow(literal_float(root + 0x1a, 1), iterations & 255),
		"initial_rating": immediate_at(initial + 6, 1),
		"rating_min": -immediate_at(rating + 0x12, 3),
		"rating_max": limit & 255,
		"campaign_race": immediate_at(campaign + 4, 3),
		"bribe_decay": immediate_at(touch + 0xd0, 1),
		"explored_goal": immediate_at(explored + 2, 2) * 2,
		"bribes": {},
		"mission_changes": {}
	}
	if (
		result.initial_rating != immediate_at(reset + 0x36, 3)
		or result.coordinate_extent != literal_float(update + 0x438, 1)
		or result.space_extent != literal_float(initialize + 0x576, 0)
		or u16(explored + 4) != 0x0052
	):
		fail("Inconsistent travel initialization declarations.")
		return {}
	for record in [[0x4b6, 0x4c6], [0x4e4, 0x4f4]]:
		var compare := u16(update + record[0])
		if compare & 0xff00 != 0x2800:
			fail("Unsupported travel bribe association.")
			return {}
		result.bribes[str(compare & 255)] = literal_float(update + record[1], 1)
	for record in [[0x26, 0x2a, -1], [0x38, 0x3e, 1]]:
		var compare := u16(mission + record[0])
		if compare & 0xff00 != 0x2800:
			fail("Unsupported completed-job faction association.")
			return {}
		result.mission_changes[str(compare & 255)] = (
			immediate_at(mission + record[1], 1) * int(record[2])
		)
	return result


func map_icons() -> Dictionary:
	var owner := symbol_address("__ZN4MMap12OnInitializeEv")
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	# Recognize the bounded resource records for the fields consumed by setImgPlanets.
	var declarations := {
		0x180: [0x1a6, 1, 0x1aa, -1],
		0x184: [0x1b2, 1, 0x1be, 0x1b4],
		0x190: [0x1c6, 2, 0x1d4, 0x1c8],
		0x18c: [0x1e2, 1, 0x1e4, -1],
		0x188: [0x1ec, 2, 0x1fa, 0x1ee],
		0x194: [0x208, 1, 0x20a, -1],
		0x198: [0x21c, 1, 0x220, -1],
		0x19c: [0x22c, 1, 0x232, 0x230]
	}
	var fields := {}
	for field in declarations:
		var record: Array = declarations[field]
		if call_target(owner + record[2]) != create:
			fail("Unsupported map icon creation record.")
			return {}
		var resource := literal(owner + record[0], record[1])
		if record[3] >= 0:
			if u16(owner + record[3]) != 0x40 | (int(record[1]) << 3) | int(record[1]):
				fail("Unsupported map icon resource declaration.")
				return {}
			resource = immediate_at(owner + record[0], record[1]) * 2
		fields[field] = ui_region_binding(resource)
	var select := symbol_address("__ZN4MMap13setImgPlanetsEP5ArrayIP7StationE")
	var result := {"planets": [], "races": {}}
	for record in [["primary", 0xac], ["secondary", 0xb6], ["other", 0xdc]]:
		var field := immediate_at(select + record[1], 3) * 2
		if not fields.has(field):
			fail("Unsupported map station icon association.")
			return {}
		result[record[0]] = fields[field]
	for record in [[0xba, 0xc4], [0xc8, 0xd2]]:
		var compare := u16(select + record[0])
		var field := immediate_at(select + record[1], 3) * 2
		if compare & 0xff00 != 0x2800 or not fields.has(field):
			fail("Unsupported map race icon association.")
			return {}
		result.races[str(compare & 255)] = fields[field]
	for offset in [0x80, 0x8a, 0x6c]:
		var field := immediate_at(select + offset, 3) * 2
		if not fields.has(field):
			fail("Unsupported map planet icon cycle.")
			return {}
		result.planets.append(fields[field])
	var cycle_limit := u16(select + 0x58)
	var primary_race := u16(select + 0x9c)
	if (
		cycle_limit & 0xff00 != 0x2b00
		or (cycle_limit & 255) + 1 != result.planets.size()
		or primary_race & 0xff00 != 0x2800
	):
		fail("Unsupported map icon selector declarations.")
		return {}
	result.primary_race = primary_race & 255
	return result


func map_presentation() -> Dictionary:
	# Constant presentation records only; native map navigation never executes the
	# source methods. Associations are resolved through their atlas registry.
	var start := symbol_address("__ZN4MMap12OnInitializeEv")
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	var images := {}
	var declarations := {
		"background_left": [0xc8, 0xdc, 0xcc],
		"background_right": [0xea, 0xec, -1],
		"galaxy": [0xf8, 0xfe, 0xfc],
		"quadrant_highlight": [0x10c, 0x10e, -1],
		"system_highlight": [0x11a, 0x120, 0x11e],
		"selection": [0x12c, 0x132, 0x130],
		"selection_ring": [0x140, 0x142, -1],
		"stars": [0x150, 0x152, -1],
		"nebula": [0x160, 0x162, -1],
		"bracket": [0x16e, 0x174, 0x172],
		"position": [0x180, 0x186, 0x184]
	}
	for key in declarations:
		var entry: Array = declarations[key]
		if call_target(start + entry[1]) != create:
			fail("Unsupported map image declaration.")
			return {}
		var resource := literal(start + entry[0], 1)
		if entry[2] >= 0:
			if u16(start + entry[2]) != 0x0049:
				fail("Unsupported map image scale declaration.")
				return {}
			resource = immediate_at(start + entry[0], 1) * 2
		images[key] = ui_region_binding(resource)
	var info := symbol_address("__ZN16PlanetInfoWindow10initTabboxEv")
	var ctor := symbol_address("__ZN16PlanetInfoWindowC2Eiiii")
	if call_target(ctor + 0x104) != create or u16(ctor + 0xfc) != 0x0049:
		fail("Unsupported destination preview overlay declaration.")
		return {}
	images.preview_ring = ui_region_binding(immediate_at(ctor + 0xfa, 1) * 2)
	var text_call := symbol_address("__ZN8GameText7getTextEi")
	var labels := {}
	for entry in [
		["name", 0x90, 0x98],
		["inhabitants", 0x122, 0x12e],
		["technology", 0x1d6, 0x1e2],
		["trade", 0x29a, 0x2a6],
		["yes", 0x2fa, 0x300],
		["no", 0x31e, 0x326],
		["cost", 0x3c4, 0x3d4],
		["bribe", 0x456, 0x462]
	]:
		if call_target(info + entry[2]) != text_call:
			fail("Unsupported station-info label declaration.")
			return {}
		labels[entry[0]] = (
			literal(info + entry[1], 1) if entry[0] == "bribe" else immediate_at(info + entry[1], 1)
		)
	labels.map = immediate_at(start + 0x344, 3)
	labels.info = literal(ctor + 0x7e, 3)
	labels.back = immediate_at(info + 0x706, 1)
	labels.travel = literal(info + 0x70a, 2)
	labels.quadrant = literal(symbol_address("__ZN4MMap13drawQuadrantsEv") + 0x7a, 1)
	# The switch tables associate source image/race indices with constant records.
	var planet_table := info + 0x5bc
	if call_target(planet_table - 4) != symbol_address("___switch32") or u32(planet_table) > 32:
		fail("Unsupported planet preview table.")
		return {}
	var planets := []
	var image_records := {
		0x5e8: [0x5ea, true],
		0x5f2: [0x5f4, true],
		0x606: [0x60a, false],
		0x61a: [0x61c, true],
		0x624: [0x628, false],
		0x638: [0x63a, true],
		0x642: [0x646, false],
		0x656: [0x658, true],
		0x660: [0x664, false]
	}
	for index in u32(planet_table):
		var target := planet_table + u32(planet_table + 4 + index * 4) - info
		if not image_records.has(target):
			fail("Unsupported planet preview association.")
			return {}
		var entry: Array = image_records[target]
		var resource := (
			immediate_at(info + entry[0], 1) * 2 if entry[1] else literal(info + entry[0], 1)
		)
		planets.append(ui_region_binding(resource))
	if (
		call_target(info + 0x6ea) != create
		or u16(info + 0x6d2) != 0x0049
		or u16(info + 0x68a) & 0xff00 != 0x2800
	):
		fail("Unsupported station preview declaration.")
		return {}
	var stations := {
		"primary_race": u16(info + 0x68a) & 255,
		"primary": ui_region_binding(literal(info + 0x698, 1)),
		"secondary": ui_region_binding(immediate_at(info + 0x6a4, 1) * 2),
		"other": ui_region_binding(literal(info + 0x6de, 1)),
		"races": {}
	}
	for entry in [[0x6ac, 0x6b6, false], [0x6c2, 0x6c8, true]]:
		var comparison := u16(info + entry[0])
		if comparison & 0xff00 != 0x2800:
			fail("Unsupported station preview race selector.")
			return {}
		var resource := (
			immediate_at(info + entry[1], 1) * 2 if entry[2] else literal(info + entry[1], 1)
		)
		stations.races[str(comparison & 255)] = ui_region_binding(resource)
	var race := symbol_address("__ZN7Globals11getRaceNameEi")
	var race_names := []
	for target in contract_choice_targets(race + 8, race):
		var instruction: int = target + 2
		var value := literal(instruction, 1)
		if value < 0:
			value = immediate_at(instruction, 1) * 2
		race_names.append(value)
	var galaxy := symbol_address("__ZN6Galaxy11getPositionEP7StationPfjjjj")
	if u16(galaxy + 0xce) != 0x1040:
		# Signed quadrant row/column decomposition is a two-column layout.
		fail("Unsupported quadrant grid declaration.")
		return {}
	var grid := {
		"system_columns": immediate_at(galaxy + 0x3e, 1),
		"quadrant_columns": immediate_at(galaxy + 0x62, 2) + 1,
		"system_extent": literal_float(galaxy + 0x2e, 2),
		"quadrant_extent": literal_float(galaxy + 0x6c, 3)
	}
	if grid.system_columns != immediate_at(galaxy + 0xac, 1):
		fail("Inconsistent system grid declaration.")
		return {}
	return {
		"images": images,
		"labels": labels,
		"planets": planets,
		"stations": stations,
		"races": race_names,
		"grid": grid,
		"layout": map_layout()
	}


func flight_artwork() -> Dictionary:
	# Bounded constructor records, identified by the HUD's drawing consumers.
	# Native layout uses these source margins and atlas dimensions at any aspect ratio.
	var ctor := symbol_address("__ZN3HudC2Ev")
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	var declarations := {
		"fire_overlay": [0x4e, 0x66, 4],
		"fire_frame": [0x6e, 0x74, 0],
		"stick_pressed": [0xe0, 0xe4, 0],
		"stick_normal": [0xec, 0xf0, 0],
		"stick_frame": [0xf8, 0xfc, 0],
		"bar": [0x102, 0x10a, 4],
		"hull": [0x112, 0x116, 0],
		"shield": [0x11e, 0x122, 0],
		"timer": [0x12a, 0x12e, 0]
	}
	var images := {}
	for key in declarations:
		var record: Array = declarations[key]
		if call_target(ctor + record[1]) != create:
			fail("Unsupported flight HUD image declaration.")
			return {}
		if record[2] > 0 and u16(ctor + record[0] + (2 if record[0] == 0x4e else 4)) != 0x0089:
			fail("Unsupported flight HUD resource scaling.")
			return {}
		var resource: int = (
			literal(ctor + record[0], 1)
			if record[2] == 0
			else immediate_at(ctor + record[0], 1) * int(record[2])
		)
		images[key] = flight_image_binding(resource)
		if images[key].is_empty() or not error.is_empty():
			return {}
	var layout := {}
	var points := {
		"pause_top": [0x298, 2],
		"timer_top": [0x2de, 2],
		"stick_left": [0x2e6, 3],
		"hull_top": [0x3ae, 2]
	}
	for key in points:
		layout[key] = immediate_at(ctor + points[key][0], points[key][1])
	layout.icon_left = immediate_at(symbol_address("__ZN3Hud4drawEixP9PlayerEgob") + 0x430, 2)
	var radius := u16(symbol_address("__ZN3Hud9touchMoveEjjPv") + 0x6c)
	if radius & 0xff00 != 0x2800:
		fail("Unsupported joystick radius declaration.")
		return {}
	layout.stick_radius = radius & 255
	# SUB/ADD-immediate declarations; register and operation are checked too.
	var offsets := {
		"fire_right": [0x1da, 0x3800],
		"fire_bottom": [0x1ca, 0x3800],
		"pause_right": [0x290, 0x3800],
		"stick_bottom": [0x30a, 0x3800],
		"boost_offset": [0x378, 0x3300],
		"boost_bottom": [0x388, 0x3800],
		"bar_left_offset": [0x39a, 0x3000],
		"bar_inset_twice": [0x3ac, 0x3800],
		"shield_top_offset": [0x3c8, 0x3000],
		"weapon_right": [0x260, 0x3800],
		"weapon_bottom": [0x270, 0x3800],
		"missiles_right": [0x230, 0x3800],
		"missiles_bottom": [0x240, 0x3800],
		"fire_frame_right": [0x1a4, 0x3800],
		"timer_right": [0x2ba, 0x3800],
		"weapon_label_right": [0x1ea, 0x3800],
		"weapon_label_bottom": [0x212, 0x3800]
	}
	for key in offsets:
		var record: Array = offsets[key]
		var operand := u16(ctor + record[0])
		if operand & 0xff00 != record[1]:
			fail("Unsupported flight HUD layout declaration: " + key)
			return {}
		layout[key] = operand & 255
	var draw := symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var colors := {"hull": literal(draw + 0x460, 1), "shield": literal(draw + 0x51e, 1)}
	if not error.is_empty() or colors.hull < 0 or colors.shield < 0:
		return {}
	return {"images": images, "layout": layout, "colors": colors}


func radar_presentation() -> Dictionary:
	var ctor := symbol_address("__ZN5RadarC2EP5Level")
	var player := symbol_address("__ZN9PlayerEgoC2EP6Player")
	var draw := symbol_address("__ZN5Radar4drawEi")
	var aim := symbol_address("__ZN9PlayerEgo4drawEbb")
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	var images := {}
	var records := {
		"enemy_near": [ctor, 0x2c, 0x36, 0],
		"enemy_off": [ctor, 0x40, 0x42, 0],
		"enemy_far": [ctor, 0x48, 0x50, 4],
		"ally_near": [ctor, 0x56, 0x5e, 4],
		"ally_off": [ctor, 0x68, 0x6a, 0],
		"ally_far": [ctor, 0x74, 0x76, 0],
		"objective_near": [ctor, 0x80, 0x82, 0],
		"objective_off": [ctor, 0x8c, 0x8e, 0],
		"lead": [ctor, 0xd6, 0xd8, 0],
		"frame_side": [ctor, 0xe2, 0xe4, 0],
		"frame_edge": [ctor, 0xea, 0xf2, 4],
		"aim": [player, 0x124, 0x12c, 0],
		"aim_hit": [player, 0x138, 0x13a, 0]
	}
	for key in records:
		var record: Array = records[key]
		if call_target(record[0] + record[2]) != create:
			fail("Unsupported radar image declaration: " + key)
			return {}
		var resource := (
			literal(record[0] + record[1], 1)
			if record[3] == 0
			else immediate_at(record[0] + record[1], 1) * int(record[3])
		)
		if record[3] != 0:
			var shift_offset: int = 6 if key == "frame_edge" else 4
			if u16(record[0] + record[1] + shift_offset) != 0x0089:
				fail("Unsupported radar resource scaling.")
				return {}
		images[key] = flight_image_binding(resource)
		if images[key].is_empty() or not error.is_empty():
			return {}
	# Drawing consumers establish frame placement, marker classes and bar dimensions.
	var margin := immediate_at(draw + 0x98, 2)
	var height := immediate_at(draw + 0x2fa, 2)
	var gap := u16(draw + 0x2ce)
	if gap & 0xff00 != 0x3300 or u16(aim + 0x64) != 0x0249 or u16(aim + 0x13e) & 0xff00 != 0x2b00:
		fail("Unsupported radar dimensions or aiming distance units.")
		return {}
	var limit := shifted_immediate(draw + 0x1a8, 4)
	var excluded: Array = []
	for offset in [0x202, 0x210]:
		if u16(draw + offset) & 0xff00 != 0x2800:
			fail("Unsupported radar actor exclusions.")
			return {}
		excluded.append(u16(draw + offset) & 255)
	var health_edge := radar_health_edge(draw)
	if health_edge.is_empty():
		return {}
	return {
		"images": images,
		"margin": margin,
		"near_extent": limit * .02,
		"distant_actors": excluded,
		"health_height": height,
		"health_gap": gap & 255,
		"health_edge": health_edge,
		"aim_distance": shifted_at(aim + 0x60, aim + 0x64, 1) * .02,
		"hit_ms": u16(aim + 0x13e) & 255,
		"lead": radar_lead_presentation(draw),
		"colors": {"enemy": literal(draw + 0x2ae, 1), "ally": literal(draw + 0xb16, 1)}
	}


func radar_health_edge(draw: int) -> Dictionary:
	# The lower row is a translucent line over the filled health rectangle.
	# Recover both affiliation consumers; do not infer colors from the brackets.
	var set_color := symbol_address("__ZN11AbyssEngine11PaintCanvas8SetColorEi")
	var line := symbol_address("__ZN11AbyssEngine11PaintCanvas8DrawLineEiiii")
	var result := {}
	for record in [["enemy", 0x30e, 0x310, 0x340, 0x344, 0x374],
		["ally", 0xb76, 0xb78, 0xba8, 0xbac, 0xbdc]]:
		var color := literal(draw + int(record[1]), 1)
		var y := u16(draw + int(record[3]))
		if (
			color < 0 or y & 0xff00 != 0x3300
			or u16(draw + int(record[4])) != 0x3a01
			or call_target(draw + int(record[2])) != set_color
			or call_target(draw + int(record[5])) != line
		):
			fail("Unsupported radar health edge declaration.")
			return {}
		result[record[0]] = {"color": color, "gap": y & 255}
	return result


func radar_lead_presentation(draw: int) -> Dictionary:
	# Read the optional target predictor as data; native vectors handle projection.
	var menu := symbol_address("__ZN10MenuWindow4drawEb")
	var globals := symbol_address("__ZN7GlobalsC2Ev")
	var shift := u16(draw + 0x42e)
	if (
		(
			call_target(draw + 0x3a6)
			!= symbol_address("__ZN11AbyssEngine6AEMath12MatrixGetDirERKNS0_6MatrixE")
		)
		or call_target(draw + 0x3c2) != symbol_address("__ZN9PlayerEgo21getCurrentWeaponSpeedEv")
		or call_target(draw + 0x3fc) != symbol_address("__ZN11AbyssEngine6AEMath3MaxEii")
		or call_target(menu + 0x1f46) != symbol_address("__ZN8GameText7getTextEi")
		or literal(draw + 0x378, 3) != literal(menu + 0x1e2c, 3)
		or immediate_at(draw + 0x37a, 2) != immediate_at(globals + 0x52, 1)
		or u16(globals + 0x60) != 0x5458
		or shift & 0xf83f != 0x101b
		or u16(draw + 0x434) != shift
		or u16(draw + 0x43c) != (shift & 0xffc0)
	):
		fail("Unsupported targeting reticle declaration.")
		return {}
	var direction_shift := (shift >> 6) & 31
	var bucket := literal_float(draw + 0x3ea, 1) * .02
	var scale := literal_float(draw + 0x400, 1) * literal_float(draw + 0x40e, 0)
	var minimum := immediate_at(draw + 0x3fa, 0)
	var enabled := immediate_at(globals + 0x56, 0)
	var label := literal(menu + 0x1f32, 1)
	if direction_shift <= 0 or enabled not in [0, 1] or minimum <= 0 or label < 0:
		fail("Invalid targeting reticle parameters.")
		return {}
	scale *= normalized_vector_unit() / float(1 << direction_shift) * .02
	if not is_finite(bucket) or not is_finite(scale) or bucket <= 0 or scale <= 0:
		fail("Invalid targeting reticle distance or scale.")
		return {}
	return {
		"bucket": bucket,
		"scale": scale,
		"minimum": minimum,
		"enabled": enabled == 1,
		"option_text": label
	}


func tutorial_presentation() -> Dictionary:
	# Recover a bounded presentation declaration: radio selection, action and
	# timing. The native UI schedules this data without running source routines.
	var start := symbol_address("__ZN5MGame10OnRender2DEv")
	if (
		call_target(start + 0xf0) != symbol_address("__ZN6Status18getCampaignMissionEv")
		or u16(start + 0xf4) & 0xff00 != 0x2800
		or call_target(start + 0x204) != symbol_address("__ZN3Hud21enableFireForTutorialEb")
	):
		fail("Unsupported tutorial presentation declarations.")
		return {}
	var messages: Array = []
	for offset in [0x10c, 0x192, 0x298]:
		var operand := u16(start + offset)
		if (
			operand & 0xf83f != 0x6818
			or (
				call_target(start + offset + 2)
				!= symbol_address("__ZN12RadioMessage11isTriggeredEv")
			)
		):
			fail("Unsupported tutorial radio association.")
			return {}
		messages.append((operand >> 6) & 31)
	var actions: Array = []
	var masks := {2: "boost", 4: "weapon", 8: "missiles"}
	for offset in [0x156, 0x25c, 0x2e8]:
		var mask := immediate_at(start + offset, 1)
		if (
			not masks.has(mask)
			or call_target(start + offset + 2) != symbol_address("__ZN3Hud19setBlinkForTutorialEj")
		):
			fail("Unsupported tutorial control association.")
			return {}
		actions.append(masks[mask])
	var duration := literal(start + 0x122, 3)
	var limit := literal(start + 0x130, 2)
	var period := immediate_at(start + 0x13c, 2)
	for record in [[0x1b4, 2, 0x1ca, 0x1d2], [0x224, 3, 0x232, 0x23a], [0x2aa, 1, 0x2be, 0x2c6]]:
		if (
			literal(start + record[0], record[1]) != duration
			or literal(start + record[2], 2) != limit
			or immediate_at(start + record[3], 2) != period
		):
			fail("Unsupported inconsistent tutorial timing declarations.")
			return {}
	if duration <= 0 or duration > 60000 or limit < 0 or limit >= duration or period <= 0:
		fail("Invalid tutorial timing declarations.")
		return {}
	return {
		"chapter": u16(start + 0xf4) & 255,
		"duration_ms": duration,
		"blink_limit_ms": limit,
		"blink_ms": period,
		"steps":
		[
			{"radio": messages[0], "action": actions[0]},
			{"radio": messages[1], "action": "fire"},
			{"radio": -1, "action": actions[1]},
			{"radio": messages[2], "action": actions[2]}
		]
	}


func briefing_presentation() -> Dictionary:
	var draw := symbol_address("__ZN9MBriefing10OnRender2DEv")
	var page := symbol_address("__ZN16BriefingDialogue11loadContentEv")
	var touch := symbol_address("__ZN9MBriefing10OnTouchEndEii")
	var footer := symbol_address("__ZN6Layout9setFooterEjjj")
	var layout := symbol_address("__ZN6Layout6reloadEv")
	if (
		call_target(draw + 0x74) != symbol_address("__ZN6Layout16drawRoundEdgeBoxEiiiib")
		or u16(draw + 0x72) != 0x005b
		or u16(draw + 0xec) & 0xff00 != 0x2800
		or u16(draw + 0xe2) & 0xff00 != 0x2800
		or u16(page + 0xe) != 0x400b
		or u16(page + 0x12) != 0x2b01
		or (
			call_target(page + 0x22)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		)
		or call_target(page + 0x42) != symbol_address("__ZN7Globals12getCharImageEi")
		or call_target(touch + 0x202) != symbol_address("__ZN16BriefingDialogue8nextPageEv")
		or u16(touch + 0x3ac) != 0x005b
		or u16(footer + 0x36) != 0x005b
		or u16(layout + 0x16c) != 0x3254
		or u16(layout + 0x15c) != 0x3258
		or u32(literal(draw + 0x1f0, 1)) != symbol_address("__ZN7Globals4fontE")
	):
		fail("Unsupported briefing page, layout or confirmation declarations.")
		return {}
	var protagonist := named_array("__ZL9img_chars").find(literal(page + 0x1c, 1))
	if protagonist < 0:
		fail("Briefing protagonist portrait is not registered.")
		return {}
	return {
		"audio": briefing_audio(),
		"panel":
		[
			immediate_at(draw + 0x60, 1),
			immediate_at(draw + 0x62, 2),
			immediate_at(draw + 0x70, 3) * 2,
			immediate_at(draw + 0x5e, 3)
		],
		"portrait_left": [immediate_at(draw + 0x122, 2), immediate_at(draw + 0x126, 3)],
		"portrait_right": [literal(draw + 0x16e, 2), immediate_at(draw + 0x172, 3)],
		"text_origin": [immediate_at(draw + 0x20e, 3), u16(draw + 0x1de) & 255],
		"text_width": immediate_at(touch + 0x3aa, 3) * 2,
		"narration_chapter": u16(draw + 0xe2) & 255,
		"narration_pages": (u16(draw + 0xec) & 255) + 1,
		"protagonist": protagonist,
		"labels":
		{
			"first_back": immediate_at(draw + 0x86, 5),
			"back": immediate_at(draw + 0x82, 5),
			"next": immediate_at(draw + 0x96, 2),
			"start": immediate_at(draw + 0x92, 2),
			"skip": immediate_at(draw + 0x9a, 3) * 4,
			"skip_question":
			immediate_at(symbol_address("__ZN9MBriefing12OnInitializeEv") + 0x86, 1) * 4
		},
		"footer":
		{
			"margin": immediate_at(footer + 0x3e, 3),
			"y": immediate_at(footer + 0x34, 3) * 2,
			"normal": ui_region_binding(literal(layout + 0x15e, 1)),
			"pressed": ui_region_binding(literal(layout + 0x166, 1)),
			"center_normal": ui_region_binding(literal(layout + 0x176, 1)),
			"center_pressed": ui_region_binding(literal(layout + 0x188, 1))
		}
	}


func player_motion() -> Dictionary:
	var ctor := symbol_address("__ZN9PlayerEgoC2EP6Player")
	var boost := symbol_address("__ZN9PlayerEgo5boostEv")
	var update := symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera")
	var render := symbol_address("__ZN5MGame10OnRender3DEv")
	if (
		u16(ctor + 0xc0) != 0x674b
		or u16(boost + 0x26) != 0x6763
		or u16(update + 0xa6) != 0x6763
		or u16(update + 0xaa) != 0x5466
		or u16(update + 0xac) != 0x65e3
		or u16(update + 0xea) != 0x4359
		or (
			call_target(render + 0x42)
			!= symbol_address("__ZN11AbyssEngine18ApplicationManager20GetElapsedTimeMillisEv")
		)
		or call_target(render + 0x4e) != update
		or u16(render + 0x4a) != 0x1c29
	):
		fail("Unsupported player movement and clock declarations.")
		return {}
	var normal := immediate_at(ctor + 0xbe, 3)
	if immediate_at(update + 0xa4, 3) != normal:
		fail("Conflicting player cruise declarations.")
		return {}
	# Original translations use units per millisecond; native world coordinates
	# use 0.02 scene units per original unit, and physics time is in seconds.
	var result := {
		"cruise_speed": normal * 20.0,
		"boost_speed": immediate_at(boost + 0x20, 3) * 20.0,
		"boost_seconds": signed_literal(update + 0x9e, 3) / 1000.0,
		"recharge_seconds": -signed_literal(update + 0xa8, 3) / 1000.0,
		"contact": player_body_contact(),
		"steering": player_steering()
	}
	if not preload("res://src/simulation/flight_motion.gd").valid_parameters(result):
		fail("Invalid player movement parameters.")
		return {}
	return result


func player_steering() -> Dictionary:
	# Read declarations and consumer bindings only. Native turning is an analytic
	# rate controller, not a transcription of the original per-frame routines.
	var ctor := symbol_address("__ZN9PlayerEgoC2EP6Player")
	var left := symbol_address("__ZN9PlayerEgo4leftEif")
	var right := symbol_address("__ZN9PlayerEgo5rightEif")
	var up := symbol_address("__ZN9PlayerEgo2upEif")
	var down := symbol_address("__ZN9PlayerEgo4downEif")
	var update := symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera")
	var sine := symbol_address("__ZN11AbyssEngine6AEMath3SinEi")
	var globals := symbol_address("__ZN7Globals4initEPN11AbyssEngine18ApplicationManagerEPNS0_6EngineE")
	var options := symbol_address("__ZN7Globals7optionsE")
	for pair in [
		[ctor + 0x148, "__ZN4Ship7getTypeEv"],
		[update + 0xcc, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii"],
		[update + 0x1da, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii"],
		[0x25594, "__ZN4ShipC1EiiiiiiiP5ArrayIiE"],
		[0x450ca, "__ZN9PlayerEgo4leftEif"], [0x45102, "__ZN9PlayerEgo5rightEif"],
		[0x454f6, "__ZN9PlayerEgo4downEif"], [0x4551c, "__ZN9PlayerEgo2upEif"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported player steering consumer at %x." % pair[0]); return {}
	for pair in [
		[ctor + 0x150, 0x0080], [ctor + 0x152, 0x58c2], [ctor + 0x156, 0x50ca],
		[left + 0x1a, 0x582e], [left + 0x1e, 0x50ee],
		[update + 0xc0, 0x5832], [update + 0xc2, 0x6823],
		[update + 0x1ce, 0x10d2], [update + 0x1d2, 0x011b], [update + 0x1d4, 0x0112],
		# These cleared flags make the subsequent decay pass apply during held input.
		[update + 0xc8, 0x2600], [update + 0x1a8, 0x2384],
		[update + 0x1aa, 0x2588], [update + 0x1ac, 0x50c6], [update + 0x1b0, 0x5146],
		[globals + 0x3a, 0x609a], [globals + 0x3c, 0x60da],
		[0x25578, 0x9a1c], [0x5c000, 0x605a], [0x5bd04, 0x6840]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported player steering declaration at %x." % pair[0]); return {}
	if literal(globals + 0x34, 3) != options or u32(literal(left + 0x56, 3)) != options:
		fail("Unsupported player steering preference binding."); return {}
	var agilities := named_array("__ZL9AGILITIES")
	if agilities.size() != 4 or literal(ctor + 0x14c, 3) != symbol_address("__ZL9AGILITIES"):
		fail("Unsupported player agility table."); return {}
	var helpers := imported_symbols()
	for address in [0x450c0, 0x450f8, 0x454ec, 0x45512]:
		if not helpers.get("___mulsf3vfp", []).has(call_target(address)):
			fail("Unsupported analog steering response."); return {}
	var limit_scale := literal_float(left + 0x2a, 1)
	var divisor := immediate_at(left + 0x44, 1)
	var ceiling := literal_float(left + 0x76, 0)
	var response_divisor := literal_float(left + 0x7c, 1)
	for declaration in [[right, 0x26, -1, 0x42, 0x74, 0x7a], [up, 0x2a, -1, 0x44, 0x7e, 0x84], [down, 0x26, 1, 0x42, 0x7c, 0x82]]:
		var base: int = declaration[0]
		if (literal_float(base + declaration[1], 1) != limit_scale * declaration[2]
			or immediate_at(base + declaration[3], 1) != divisor
			or literal_float(base + declaration[4], 0) != ceiling
			or literal_float(base + declaration[5], 1) != response_divisor):
			fail("Conflicting player turn response declarations."); return {}
	var result := {
		"agilities": agilities,
		"ship_type_column": 1,
		"radians_per_unit": literal_float(sine + 8, 1),
		"reference_seconds": wreck_drift().get("reference_seconds", 0.0),
		"limit_scale": limit_scale / float(divisor),
		"response_ceiling": ceiling, "response_divisor": response_divisor,
		"default_response": literal_float(globals + 0x36, 2),
		"release_divisors": [immediate_at(update + 0x208, 1), immediate_at(update + 0x25e, 1)],
		"bank_scale": float(1 << ((u16(update + 0x1d2) >> 6) & 31)),
		"pitch_bank_divisor": float(1 << ((u16(update + 0x1ce) >> 6) & 31)),
		"look_blend": 1.0 / float(1 << ((u16(0x5f7fa) >> 6) & 31)),
		"position_blend": 1.0 / float(1 << ((u16(0x5f83a) >> 6) & 31))
	}
	if not preload("res://src/simulation/player_steering.gd").valid_parameters(result):
		fail("Invalid supplied player steering declarations."); return {}
	return result


func player_body_contact() -> Dictionary:
	for pair in [
		[0x54bb8, "__ZN5Level10getFriendsEv"], [0x54bc2, "__ZN5Level10getEnemiesEv"],
		[0x54c14, "__ZN11AbyssEngine6AEMath9VectorDotERKNS0_6VectorES3_"],
		[0x54cb8, "__ZN6Player6damageEi"],
		[0x56e4c, "__ZN16ExplosionHandler11hasFinishedEv"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported player body-contact consumer.")
			return {}
	for pair in [
		[0x54774, 0x6eeb], [0x54778, 0x66eb], [0x54be2, 0x6a24], [0x54be4, 0x47a0],
		[0x54bf4, 0x6b1b], [0x54bf6, 0x4798], [0x54c1c, 0x0041],
		[0x54c62, 0x145b], [0x54c7a, 0x145b], [0x54c94, 0x145b],
		[0x54ca6, 0x6eeb], [0x54cae, 0xdd05], [0x54cb6, 0x66eb],
		[0x56af0, 0x2b04], [0x56e54, 0x2304]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported fixed-body contact, clock or response declaration at %x." % pair[0])
			return {}
	for name in ["__ZN13PlayerFighter7collideEiii", "__ZN8KIPlayer7collideEiii", "__ZN10PlayerMine7collideEiii", "__ZN12PlayerTurret7collideEiii"]:
		var address := symbol_address(name)
		if u16(address) != 0x2000 or u16(address + 2) != 0x4770:
			fail("Unsupported non-solid actor contact behavior.")
			return {}
	return {
		"damage": immediate_at(0x54cb4, 1),
		"interval": shifted_at(0x54ca8, 0x54caa, 2) / 1000.0,
		"forward_keep": 1.0 / float(1 << (((u16(0x54c62) >> 6) & 31) - 16))
	}


func shared_gun_pool(capacity: int, identifier: int) -> Dictionary:
	var constructor := symbol_address("__ZN3GunC2EiiiiiN11AbyssEngine6AEMath6VectorES2_")
	var shoot := symbol_address("__ZN3Gun7shootAtEN11AbyssEngine6AEMath6MatrixEiP6Playerb")
	var player := symbol_address("__ZN6Player5shootEixb")
	# r2 allocates a bounded live-projectile pool. Gun.shootAt selects a free
	# entry; Player owns its slot's cooldown, independently of the shared Gun.
	if (
		u16(constructor + 0x16) != 0x9202
		or u16(constructor + 0xb4) != 0x9a02
		or u16(constructor + 0xc2) != 0x9802
		or (
			call_target(constructor + 0xc6)
			!= symbol_address("__Z14ArraySetLengthIN11AbyssEngine6AEMath6VectorEEvjR5ArrayIT_E")
		)
		or u16(shoot + 0x16) != 0x6801
		or u16(shoot + 0x1e) != 0x69a3
		or u16(shoot + 0x24) != 0x2b00
		or u16(shoot + 0x26) != 0xdd00
		or u16(player + 0x3a) != 0x6e63
		or u16(player + 0x44) != 0x6a03
		or u16(player + 0x54) != 0x50c2
		or capacity <= 0
		or capacity > 4096
		or identifier <= 0
		or identifier > 4096
	):
		fail("Unsupported shared projectile pool or per-player cooldown declaration.")
		return {}
	# Shared gun slots bind their effect explicitly; ordinary fighter pools keep
	# the constructor's null impact. Per-actor copies retain this flag even when
	# their pool_id is removed to give each actor an independent projectile pool.
	for binding in [[0x2ee14, 0x2ee0e, 0x2edf8], [0x2ef1c, 0x2ef16, 0x2ef00]]:
		if call_target(binding[0]) != symbol_address("__ZN3Gun9setImpactEP6Sparks") or immediate_at(binding[1], 3) != 0xbc:
			fail("Unsupported NPC rocket impact binding.")
			return {}
	var rocket := identifier == immediate_at(0x2edf8, 2) or identifier == immediate_at(0x2ef00, 2)
	return {"pool_capacity": capacity, "pool_id": identifier, "rocket_impact": rocket}


func normalized_vector_unit() -> float:
	var normalize := symbol_address("__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE")
	# Source normalized vectors and matrix basis use fixed-point components.
	# The degenerate-vector branch explicitly constructs one unit along Y.
	if u16(normalize + 0x70) != 0x6073:
		fail("Unsupported normalized vector representation.")
		return 0
	return float(shifted_immediate(normalize + 0x6a, 3))


func fighter_firing_bounds() -> Dictionary:
	var update := symbol_address("__ZN13PlayerFighter6updateEi")
	var fighter := symbol_address("__ZN13PlayerFighterC2EibP6Playeriii")
	var calls := calls_between(update, symbol_end(update), "__ZN6Player5shootEixb")
	if calls.size() != 1:
		fail("Unsupported fighter discharge association.")
		return {}
	var shoot := int(calls[0])
	var gun := symbol_address("__ZN3Gun5shootEN11AbyssEngine6AEMath6MatrixEib")
	var shoot_at := symbol_address("__ZN3Gun7shootAtEN11AbyssEngine6AEMath6MatrixEiP6Playerb")
	var upper := literal(shoot - 86, 4)
	var unit := normalized_vector_unit()
	if (
		unit <= 0
		or upper <= 0
		or upper > 10000000
		or literal(shoot - 78, 2) != upper * 2
		or signed_literal(shoot - 58, 1) != -upper - 1
		or immediate_at(shoot - 110, 3) != immediate_at(fighter + 0x17e, 3)
		or (
			call_target(shoot - 176)
			!= symbol_address("__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE")
		)
		or (
			call_target(shoot - 166)
			!= symbol_address("__ZN11AbyssEngine6AEMath16MatrixGetInverseERKNS0_6MatrixE")
		)
		or (
			call_target(shoot - 156)
			!= symbol_address(
				"__ZN11AbyssEngine6AEMath18MatrixRotateVectorERKNS0_6MatrixERKNS0_6VectorE"
			)
		)
		or u16(shoot - 108) != 0x58f3
		or u16(shoot - 106) != 0x429a
		or u16(shoot - 96) != 0x4299
		or u16(shoot - 78 + 2) != 0x191b
		or immediate_at(gun + 0x14, 3) != 0
		or u16(gun + 0x16) != 0x930a
		or call_target(gun + 0x32) != shoot_at
		or (
			call_target(shoot_at + 0x9a)
			!= symbol_address("__ZN11AbyssEngine6AEMath12MatrixGetDirERKNS0_6MatrixE")
		)
	):
		fail("Unsupported fighter angular tolerance, firing range or forward discharge.")
		return {}
	return {"half_width": upper * .02}


func briefing_scene_presentation() -> Dictionary:
	var briefing := symbol_address("__ZN9MBriefing12OnInitializeEv")
	var init := symbol_address("__ZN8CutScene4initEv")
	var update := symbol_address("__ZN8CutScene8OnUpdateEi")
	var station := symbol_address("__ZN5Level18createStationSpaceEv")
	var level := symbol_address("__ZN5Level4initEv")
	var scene := symbol_address("__ZN5Level11createSceneEv")
	var field := symbol_address("__ZN13AsteroidFieldC2EiP8Waypoint")
	var choices := calls_between(briefing, symbol_end(briefing), "___switch32")
	if (
		choices.size() != 1
		or call_target(scene + 0x54) != symbol_address("__ZN13AsteroidFieldC1EiP8Waypoint")
	):
		fail("Unsupported briefing scene declarations.")
		return {}
	var table: int = choices[0] + 4
	var count := u32(table)
	if count < 1 or count > 64:
		fail("Invalid briefing scene count.")
		return {}
	var modes: Array = []
	for chapter in count:
		var target := table + u32(table + 4 + chapter * 4)
		if (
			target < table + 4 + count * 4
			or target >= symbol_end(briefing)
			or u16(target) & 0xf800 != 0x2000
		):
			fail("Unsupported briefing scene mode association.")
			return {}
		modes.append(u16(target) & 255)
	var camera_position := symbol_address("__ZN18TargetFollowCamera11setPositionEiii")
	var perspective := symbol_address("__ZN11AbyssEngine11PaintCanvas20CameraSetPerspectiveEjiii")
	if (
		call_target(init + 0xf2) != perspective
		or call_target(init + 0x62c) != symbol_address("__ZN18TargetFollowCamera12setLookAtCamEb")
		or immediate_at(init + 0x626, 1) != 1
		or call_target(init + 0x63a) != camera_position
		or u16(init + 0x632) != 0x4249
		or call_target(init + 0x644) != symbol_address("__ZN5Level19getStationTransformEv")
		or call_target(init + 0x64c) != symbol_address("__ZN18TargetFollowCamera9setTargetEj")
		or u16(init + 0x5fe) & 0xff00 != 0x2800
		or u16(init + 0x5f0) & 0xf83f != 0x101b
		or (
			call_target(init + 0x61c)
			!= symbol_address("__ZN5Level18setStationPositionEN11AbyssEngine6AEMath6VectorE")
		)
		or call_target(station + 0x5c) != symbol_address("__ZN7Station7getRaceEv")
		or u16(station + 0x86) & 0xff00 != 0x2800
		or u16(station + 0x98) & 0xff00 != 0x2800
		or u16(station + 0xa0) & 0xff00 != 0x2800
		or u16(station + 0x8c) != 0x2b00
		or (
			call_target(update + 0x1ce)
			!= symbol_address("__ZN5Level18translateAsteroidsERKN11AbyssEngine6AEMath6VectorE")
		)
	):
		fail("Unsupported briefing camera, station selection or field motion.")
		return {}
	var drift_masks := [immediate_at(update + 0x168, 3) << 11, literal(update + 0x172, 3)]
	if u16(update + 0x15e) & 0xff00 != 0x2a00:
		fail("Unsupported briefing drift selection range.")
		return {}
	var maximum_drift_mode := u16(update + 0x15e) & 255
	var rates: Array = []
	for offset in [0x180, 0x18a, 0x19e, 0x1a2, 0x1b8, 0x1c2]:
		var opcode := u16(update + offset)
		if opcode & 0xf800 != 0x1000:
			fail("Unsupported briefing field drift units.")
			return {}
		rates.append(1.0 / (1 << ((opcode >> 6) & 31)))
	if (
		u16(level + 0x18e) != 0x1eda
		or u16(level + 0x19c) & 0xff00 != 0x3a00
		or u16(level + 0x19e) & 0xff00 != 0x2a00
	):
		fail("Unsupported briefing location initialization range.")
		return {}
	var location_first := 3 + (u16(level + 0x19c) & 255)
	var location_last := location_first + (u16(level + 0x19e) & 255)
	var motion: Array = []
	var init_table := init + 0x210
	var update_table := update + 0x1e0
	for mode in modes:
		if mode == 7:
			motion.append({"mode": mode, "kind": "intro"})
			continue
		if (
			mode < 11
			or mode > 22
			or init_table + u32(init_table + 4 + (mode - 3) * 4) != init + 0x5b8
			or update_table + u32(update_table + 4 + (mode - 3) * 4) != update + 0xa6a
		):
			fail("Unsupported briefing camera scene behavior.")
			return {}
		var velocity: Array
		if mode <= maximum_drift_mode and (1 << mode) & int(drift_masks[0]):
			velocity = [-rates[0], 0, rates[1]]
		elif mode <= maximum_drift_mode and (1 << mode) & int(drift_masks[1]):
			velocity = [rates[2], 0, rates[3]]
		else:
			velocity = [-rates[4], 0, -rates[5]]
		motion.append(
			{
				"mode": mode,
				"kind": "station",
				"location_station": mode >= location_first and mode <= location_last,
				"field_velocity": velocity
			}
		)
	var asteroid := asteroid_field_definition(immediate_at(scene + 0x4e, 1), 0)
	asteroid.erase("waypoint")
	asteroid["center"] = [0, 0, 0]
	asteroid["rotation_bound"] = immediate_at(field + 0x1ce, 2) << 8
	return {
		"chapters": motion,
		"opening": opening_scene_presentation(),
		"camera_position":
		[
			-immediate_at(init + 0x630, 1),
			immediate_at(init + 0x636, 2),
			signed_literal(init + 0x638, 3)
		],
		"fov_units": literal(init + 0xee, 2),
		"near": immediate_at(init + 0xec, 3),
		"far": literal(init + 0xa8, 5),
		"station_z": 65536 >> ((u16(init + 0x5f0) >> 6) & 31),
		"special_type": u16(init + 0x5fe) & 255,
		"special_z": signed_literal(init + 0x602, 3),
		"location_default": immediate_at(station + 0xa4, 1),
		"location_races":
		[
			{
				"race": u16(station + 0x86) & 255,
				"type": immediate_at(station + 0x90, 1),
				"image_zero_type": immediate_at(station + 0x94, 2)
			},
			{"race": u16(station + 0x98) & 255, "type": immediate_at(station + 0x9c, 3)},
			{"race": u16(station + 0xa0) & 255, "type": immediate_at(station + 0x164, 2)}
		],
		"field": asteroid
	}


func station_presentation(resources: Dictionary) -> Dictionary:
	# Recover composite declarations and their scene associations. Runtime receives
	# mesh IDs, placements and animation parameters, never original instructions.
	var create := symbol_address("__ZN12SpaceStation13createStationEi")
	var constructor := symbol_address("__ZN12SpaceStationC2Ei")
	var update := symbol_address("__ZN12SpaceStation6updateEj")
	var space := symbol_address("__ZN5Level11createSpaceEv")
	var add_mesh := symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
	var rotate := symbol_address("__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii")
	if (
		u16(create + 6) & 0xff00 != 0x3900
		or u16(create + 8) != 0x1c08
		or call_target(create + 0x44) != add_mesh
		or call_target(create + 0x4e) != add_mesh
		or u16(create + 0x42) != 0x1c2a
		or u16(create + 0x4c) != 0x1c32
		or call_target(constructor + 0x12) != create
		or call_target(constructor + 0x4e) != symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi")
		or call_target(constructor + 0x58) != symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi")
		or u16(constructor + 0x52) != 0x4651
		or u16(constructor + 0x60) != 0x1b9a
		or u16(constructor + 0x62) != 0x1a1b
		or call_target(constructor + 0x6a) != rotate
		or u16(update + 0xa) != 0x18c9
		or u16(update + 0xc) != 0x2380
		or u16(update + 0xe) != 0x025b
		or u16(update + 0x16) != 0xb289
		or call_target(update + 0x30) != rotate
	):
		fail("Unsupported station composite or rotation declarations.")
		return {}
	var targets := contract_choice_targets(create + 0xa, create)
	if targets.is_empty():
		return {}
	var first := u16(create + 6) & 255
	var table := create + 0xe
	var default_target := table + bytes[file_offset(table + targets.size() + 1, 1)] * 2
	var types := {}
	var branches := {
		create + 0x14: [create + 0x18, create + 0x18],
		create + 0x1a: [create + 0x20, create + 0x1c],
		create + 0x22: [create + 0x26, create + 0x26],
		create + 0x28: [create + 0x2c, create + 0x2c],
		create + 0x2e: [create + 0x32, create + 0x32]
	}
	for index in range(-1, targets.size()):
		var target: int = default_target if index == -1 else targets[index]
		if not branches.has(target):
			fail("Unknown station mesh choice.")
			return {}
		var fields: Array = branches[target]
		var body := ui_constant_before(fields[0], 5, fields[0] - target)
		var lights := ui_constant_before(fields[1], 6, fields[1] - target)
		if not resources.has(str(body)) or not resources.has(str(lights)):
			fail("Station mesh association has no resource declaration.")
			return {}
		types[str(first + index)] = {"body": body, "lights": lights}
	var campaign: Array = []
	var chapter_table := space + 0x7c
	var count := u32(chapter_table)
	if call_target(space + 0x78) != symbol_address("___switch32") or count < 1 or count > 64:
		fail("Unsupported station chapter associations.")
		return {}
	var associations := {
		space + 0xb8: -1,
		space + 0xc2: space + 0xd6,
		space + 0x118: space + 0x12c,
		space + 0x156: -1,
		space + 0x162: space + 0x176,
		space + 0x192: space + 0x1a6,
		space + 0x1be: space + 0x1d2,
		space + 0x1ea: space + 0x1fe,
		space + 0x214: -1
	}
	for chapter in count:
		var branch := chapter_table + u32(chapter_table + 4 + chapter * 4)
		if not associations.has(branch):
			fail("Unknown station chapter declaration.")
			return {}
		var call: int = associations[branch]
		if call < 0:
			campaign.append({})
			continue
		if call_target(call) != symbol_address("__ZN12SpaceStationC1Ei"):
			fail("Unsupported campaign station constructor.")
			return {}
		var kind := immediate_at(call - 4, 1)
		if not types.has(str(kind)):
			fail("Unknown campaign station type.")
			return {}
		var placement := {"type": kind, "position": [0, 0, 0]}
		if branch == space + 0xc2:
			for offset in [0xfc, 0x110]:
				if (
					call_target(space + offset)
					!= symbol_address("__ZN12SpaceStation11setPositionEiii")
				):
					fail("Unsupported opening station placement.")
					return {}
			placement.position = [
				immediate_at(space + 0xf6, 1),
				immediate_at(space + 0xf8, 2),
				signed_literal(space + 0xfa, 3)
			]
			placement["alternate_position"] = [
				immediate_at(space + 0x108, 1),
				immediate_at(space + 0x10c, 2),
				signed_literal(space + 0x10e, 3)
			]
			if u16(space + 0xea) & 0xff00 != 0x2b00:
				fail("Unsupported station placement scene association.")
				return {}
			placement["position_mode"] = u16(space + 0xea) & 255
		campaign.append(placement)
	return {
		"types": types,
		"campaign": campaign,
		"tilt_bound": literal(constructor + 0x40, 3),
		"tilt_center": literal(constructor + 0x5c, 3),
		"turn_ms": immediate_at(update + 0xc, 3) << 9
	}


func sky_presentation() -> Dictionary:
	var sky := symbol_address("__ZN5Level12createSkyboxEib")
	var space := symbol_address("__ZN5Level11createSpaceEv")
	var draw := symbol_address("__ZN5Level8renderBGEj")
	var mesh_create := symbol_address("__ZN11AbyssEngine11PaintCanvas10MeshCreateEtRj")
	var texture_create := symbol_address("__ZN11AbyssEngine11PaintCanvas13TextureCreateEtRj")
	for offset in [0xbe, 0xce, 0xe2, 0x10a]:
		if call_target(sky + offset) != mesh_create:
			fail("Unsupported sky mesh declarations.")
			return {}
	for offset in [0xee, 0xfa, 0x11a]:
		if call_target(sky + offset) != texture_create:
			fail("Unsupported sky texture declarations.")
			return {}
	if (
		call_target(sky + 0x2e2) != symbol_address("__ZN11AbyssEngine8AERandom7setSeedEx")
		or call_target(sky + 0x2d4) != symbol_address("__ZN7Station8getIndexEv")
		or u16(sky + 0x2de) != 0x4359
		or u16(sky + 0x110) & 0xff00 != 0x3100
		or call_target(space + 0x44) != symbol_address("__ZN7Station13getImageIndexEv")
		or call_target(space + 0x40) != symbol_address("__ZN6Status10getStationEv")
	):
		fail("Unsupported station sky association.")
		return {}
	var variants := immediate_at(sky + 0x74, 1)
	var style_count := immediate_at(sky + 0x7e, 1)
	var cloud_count := immediate_at(sky + 0x88, 1)
	if variants <= 0 or variants > 32 or style_count != 4 or cloud_count <= 0 or cloud_count > 32:
		fail("Unsupported sky variant dimensions.")
		return {}
	var clouds: Array = []
	var table := literal(sky + 0xc2, 2)
	for index in cloud_count:
		clouds.append(u16(table + index * 2))
	var overrides: Array = []
	# createSpace selects overrides by its bounded campaign declaration table.
	var chapter_table := space + 0x7c
	if call_target(space + 0x78) != symbol_address("___switch32"):
		fail("Unsupported campaign sky override table.")
		return {}
	var chapters := u32(chapter_table)
	if chapters <= 0 or chapters > 64:
		fail("Invalid campaign sky override count.")
		return {}
	var values := {
		space + 0xc2: -1,
		space + 0x214: -1,
		space + 0x118: immediate_at(space + 0x14c, 3),
		space + 0x156: immediate_at(space + 0x15a, 2),
		space + 0xb8: immediate_at(space + 0xbc, 3),
		space + 0x162: immediate_at(space + 0x18a, 1),
		space + 0x192: -1,
		space + 0x1be: -1,
		space + 0x1ea: -1
	}
	for chapter in chapters:
		var target := chapter_table + u32(chapter_table + 4 + chapter * 4)
		if not values.has(target):
			fail("Unknown campaign sky override declaration.")
			return {}
		overrides.append(values[target])
	# Source style tint is shared by the base sky and planet layer.
	var tints: Array = []
	for record in [[0xb0, 0xb2, 0xae], [0x9e, 0xa0, 0xa8], [0x96, 0x98, 0xa8], [0xba, 0xbc, 0xbe]]:
		tints.append(
			[
				immediate_at(draw + record[0], 1),
				immediate_at(draw + record[1], 2),
				immediate_at(draw + record[2], 3)
			]
		)
	var blends: Array = []
	var modes := {0: "opaque", 1: "mix", 2: "add"}
	for offset in [0xda, 0x102, 0x15a, 0x186]:
		var mode := immediate_at(draw + offset, 1)
		if (
			not modes.has(mode)
			or (
				call_target(draw + offset + (6 if offset == 0x15a else 2))
				!= symbol_address("__ZN11AbyssEngine11PaintCanvas12SetBlendModeENS_9BlendModeE")
			)
		):
			fail("Unsupported sky blend declaration.")
			return {}
		blends.append(modes[mode])
	var random := sky_random_parameters()
	if random.is_empty():
		return {}
	return {
		"blends": blends,
		"base_mesh": literal(sky + 0xbc, 1),
		"cloud_meshes": clouds,
		"planet_base": literal(sky + 0xd4, 2),
		"sun_base": literal(sky + 0xfe, 3),
		"variant_count": variants,
		"base_texture": immediate_at(sky + 0xec, 1),
		"cloud_texture": immediate_at(sky + 0xf8, 1),
		"sun_texture_base": u16(sky + 0x110) & 255,
		"tints": tints,
		"seed_multiplier": literal(sky + 0x2d8, 3),
		"campaign_overrides": overrides,
		"random": random
	}


func sky_random_parameters() -> Dictionary:
	# The archive uses the standard 48-bit linear congruential generator. Import
	# its parameters; native background selection uses an independent small PRNG.
	var next := symbol_address("__ZN11AbyssEngine8AERandom4nextEi")
	var seed := symbol_address("__ZN11AbyssEngine8AERandom7setSeedEx")
	var integer := symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi")
	var multiplier := literal(next + 0xc, 0) | (immediate_at(next + 0xe, 1) << 32)
	var xor_value := literal(seed + 2, 3) | (immediate_at(seed + 4, 4) << 32)
	if (
		u16(next + 0x1e) != 0xb28b
		or u16(seed + 0xa) != 0xb292
		or immediate_at(next + 0x20, 1) != 48
		or immediate_at(integer + 0x14, 1) != 31
		or immediate_at(integer + 0x30, 1) != 31
		or multiplier <= 0
		or xor_value <= 0
	):
		fail("Unsupported background random parameters.")
		return {}
	return {
		"multiplier": multiplier,
		"increment": immediate_at(next + 0x14, 2),
		"seed_xor": xor_value,
		"bits": 48,
		"output_bits": 31
	}


func lighting_vector(start: int, end: int) -> Array:
	# Bounded constant-vector initializer, not executable control flow. Only one
	# scalar temporary, three consecutive stack fields and known address setup.
	var result: Array = []
	var value: Variant = null
	var slot := -1
	for address in range(start, end, 2):
		var word := u16(address)
		if word & 0xff00 == 0x2300:
			value = word & 255
		elif word & 0xff00 == 0x4b00:
			value = signed_literal(address, 3)
		elif word == 0x425b and value != null:
			value = -int(value)
		elif word & 0xf83f == 27 and value != null:
			value = int(value) << ((word >> 6) & 31)
		elif word & 0xff00 == 0x3300 and value != null:
			value = int(value) + (word & 255)
		elif word & 0xff00 == 0x9300 and value != null:
			var current := word & 255
			if slot >= 0 and current != slot + 1:
				fail("Nonconsecutive light direction fields.")
				return []
			slot = current
			result.append(value)
		elif word in [0x1c2c, 0x34e8, 0x1c20] or word & 0xff00 == 0xa900:
			pass  # Fixed stack/object address setup in this declaration layout.
		elif word & 0xf800 == 0xe000 and address + 2 == end:
			pass  # End of the declaration; never follow a branch.
		else:
			fail("Unsupported light direction initializer.")
			return []
	if result.size() != 3:
		fail("Incomplete light direction declaration.")
		return []
	return result


func lighting_rgba(address: int) -> Array:
	var offset := file_offset(address, 16)
	if offset < 0:
		fail("Truncated lighting color.")
		return []
	var result: Array = []
	for index in 4:
		var value := bytes.decode_float(offset + index * 4)
		if not is_finite(value) or value < 0 or value > 1:
			fail("Unsupported lighting color.")
			return []
		result.append(value)
	return result


func lighting_presentation() -> Dictionary:
	var sky := symbol_address("__ZN5Level12createSkyboxEib")
	var initialize := symbol_address("__ZN11AbyssEngine11PaintCanvas10InitializeEv")
	var end := symbol_address("__ZN11AbyssEngine11PaintCanvas5End3dEv")
	var color := symbol_address("__ZN11AbyssEngine11PaintCanvas13SetLightColorEfff")
	var direction := symbol_address("__ZN11AbyssEngine11PaintCanvas17SetLightDirectionEiii")
	var imports := imported_symbols()
	for record in [
		[initialize, 0x106, "_glLightfv"],
		[initialize, 0x116, "_glLightfv"],
		[initialize, 0x120, "_glMaterialfv"],
		[initialize, 0x12a, "_glMaterialfv"],
		[end, 0xce, "_glLightfv"],
		[end, 0x38, "_glShadeModel"],
		[color, 0x18, "_glLightfv"]
	]:
		if not imports.get(record[2], []).has(call_target(record[0] + record[1])):
			fail("Unsupported lighting API association.")
			return {}
	if (
		literal(initialize + 0x10a, 2) != 0x1201
		or literal(end + 0xc2, 1) != 0x1203
		or literal(end + 0xc0, 3) != 0
		or literal(end + 0x36, 0) != 0x1d01
		or literal(color + 0x14, 1) != 0x1201
		or call_target(sky + 0x244) != direction
		or call_target(sky + 0x274) != direction
		or call_target(sky + 0x2b4) != color
		or u16(sky + 0x21e) != 0x425a
	):
		fail("Unsupported directional lighting profile.")
		return {}
	var face := literal(initialize + 0x10c, 5)
	if face not in [0x404, 0x408]:
		fail("Unsupported material face declaration.")
		return {}
	var table := sky + 0x124
	if call_target(table - 4) != symbol_address("___switch8") or u16(table) & 255 != 8:
		fail("Unsupported lighting variant table.")
		return {}
	var starts := [0x12e, 0x148, 0x164, 0x17c, 0x196, 0x1ae, 0x1c6, 0x1e0, 0x1f6, 0x20c]
	var vectors: Array = []
	for index in 9:
		if table + (u16(table + 1 + index) & 255) * 2 != sky + starts[index]:
			fail("Unknown lighting variant association.")
			return {}
		vectors.append(lighting_vector(sky + starts[index], sky + starts[index + 1]))
	var cool := literal_float(sky + 0x29e, 1)
	var warm := literal_float(sky + 0x2a2, 3)
	var green := literal_float(sky + 0x296, 1)
	var full := literal_float(sky + 0x298, 2)
	var red := literal_float(sky + 0x28e, 1)
	var red_other := literal_float(sky + 0x290, 2)
	var white := literal_float(sky + 0x2ae, 1)
	var hangar := literal_float(sky + 0x25c, 1)
	if (
		u16(sky + 0x29a) != 0x1c0b
		or u16(sky + 0x2a4) != 0x1c0a
		or u16(sky + 0x2b0) != 0x1c0a
		or u16(sky + 0x2b2) != 0x1c13
	):
		fail("Unsupported light color field links.")
		return {}
	return {
		"ambient_light": lighting_rgba(literal(initialize + 0xe0, 3)),
		"material_ambient": lighting_rgba(literal(initialize + 0xe0, 3)),
		"material_diffuse": lighting_rgba(literal(initialize + 0xf0, 3)),
		"material_face": face,
		"directions": vectors,
		"diffuse":
		[
			[cool, cool, warm],
			[green, full, green],
			[red, red_other, red_other],
			[white, white, white]
		],
		"hangar_direction":
		[
			immediate_at(sky + 0x23a, 1),
			ui_constant_before(sky + 0x244, 2),
			immediate_at(sky + 0x240, 3)
		],
		"hangar_race": u16(sky + 0x256) & 255,
		"hangar_diffuse": [hangar, full, hangar],
		"hangar_default": [white, white, white]
	}


func contract_clearance() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var tables := calls_between(level, level + 1400, "___switch32")
	if tables.size() != 1:
		fail("Missing clearance contract dispatch.")
		return {}
	var table: int = tables[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid clearance dispatch count.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0x34) == symbol_address("__ZN5RouteC1EPii")
			and (
				call_target(candidate + 0x168)
				== symbol_address("__ZN5Level18createStaticObjectEP8Waypointi")
			)
		):
			if start != 0 and start != candidate:
				fail("Ambiguous clearance contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x42a >= symbol_end(level):
		fail("Unsupported clearance contract boundary.")
		return {}
	var calls := {
		0x34: "__ZN5RouteC1EPii",
		0x86: "__ZN6Status10getMissionEv",
		0x90: "__ZN6Status10getStationEv",
		0x94: "__ZN7Station11getQuadrantEv",
		0x9c: "__ZN7Mission21getRelativeDifficultyEi",
		0xba: "__ZN6Status10getMissionEv",
		0xc2: "__ZN6Status10getStationEv",
		0xc6: "__ZN7Station11getQuadrantEv",
		0xce: "__ZN7Mission21getRelativeDifficultyEi",
		0x126: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x15e: "__ZN5Route11getWaypointEv",
		0x168: "__ZN5Level18createStaticObjectEP8Waypointi",
		0x1aa: "__ZN5Route11getWaypointEv",
		0x1bc: "__ZN5Level10createShipEiiibP8Waypoint",
		0x20a: "__ZN9ObjectiveC1EiiP5Level",
		0x422: "__ZN5RouteD1Ev"
	}
	for offset in calls:
		if call_target(start + offset) != symbol_address(calls[offset]):
			fail("Unsupported clearance contract source binding.")
			return {}
	# Verify the declarations' array copy, count sum, target prefix, actor and
	# deadline associations. Numeric operands below remain supplied-file data.
	var bindings := [
		[0xc, 0xc931],
		[0xe, 0xc231],
		[0x120, 0x1888],
		[0x180, 0x1b1b],
		[0x184, 0x429d],
		[0x186, 0xdbdf],
		[0x1b0, 0x9300],
		[0x1b8, 0x9001],
		[0x204, 0x1a52],
		[0x406, 0x615a],
		[0x40e, 0x50e2]
	]
	for pair in bindings:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported clearance target/count association.")
			return {}
	if (
		immediate_at(start + 0x26, 2) != 3
		or immediate_at(start + 0x1b4, 2) != 0
		or immediate_at(start + 0x1b2, 1) != 0
		or immediate_at(start + 0x1ae, 3) != 1
	):
		fail("Unsupported clearance route or defending ship role.")
		return {}
	var arithmetic := imported_symbols()
	for offset in [0xa6, 0xd8]:
		for pair in [[0, "___divsf3vfp"], [6, "___mulsf3vfp"], [10, "___fixsfsivfp"]]:
			if not arithmetic.get(pair[1], []).has(call_target(start + offset + pair[0])):
				fail("Unsupported clearance count arithmetic.")
				return {}
	var objective_start := symbol_address("__ZN9Objective8achievedEi")
	var switches := calls_between(objective_start, symbol_end(objective_start), "___switch8")
	if switches.size() != 1:
		fail("Missing clearance completion declaration.")
		return {}
	var objectives := contract_choice_targets(switches[0], objective_start)
	var kind := immediate_at(start + 0x208, 1)
	if (
		kind >= objectives.size()
		or call_target(objectives[kind] + 2) != symbol_address("__ZN5Level10getEnemiesEv")
		or call_target(objectives[kind] + 22) != symbol_address("__ZN8KIPlayer6isDeadEv")
		or u16(objectives[kind] + 36) != 0x429c
	):
		fail("Unsupported clearance target-prefix objective.")
		return {}
	if u16(start + 0x122) & 0xff00 != 0x3000:
		fail("Unsupported clearance base count.")
		return {}
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	return {
		"family": "clearance",
		"types": types,
		"center": int_array(literal(start, 3), immediate_at(start + 0x26, 2)),
		"scatter": static_scatter(),
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"debris_base": u16(start + 0x122) & 255,
		"debris_divisor": literal_float(start + 0xd6, 1),
		"debris_factor": literal_float(start + 0xdc, 1),
		"pirate_divisor": literal_float(start + 0xa4, 1),
		"pirate_factor": literal_float(start + 0xaa, 1),
		"debris_actor": immediate_at(start + 0x162, 2),
		"pirate_actor": immediate_at(start + 0x1b6, 3),
		"deadline_ms": literal(start + 0x40a, 2),
		"success_kind": "enemy_prefix_destroyed"
	}


func mine_behavior(resources: Dictionary) -> Dictionary:
	var factory := symbol_address("__ZN5Level18createStaticObjectEP8Waypointi")
	var update := symbol_address("__ZN10PlayerMine6updateEi")
	var constructor := symbol_address("__ZN10PlayerMineC2EibP6Playeriii")
	var awake := symbol_address("__ZN10PlayerMine5awakeEv")
	var actor := immediate_at(factory + 0xfa, 1)
	if call_target(awake + 0xe) != symbol_address("__ZN11AbyssEngine18ApplicationManager9SoundPlayEi"):
		fail("Unsupported mine arming audio consumer.")
		return {}
	if (
		u16(factory + 0xda) != (0x2b00 | actor)
		or call_target(factory + 0x102) != symbol_address("__ZN10PlayerMineC1EibP6Playeriii")
		or (
			call_target(factory + 0x132)
			!= symbol_address("__ZN16ExplosionHandlerC1E19ExplosionObjectType")
		)
		or (
			call_target(factory + 0x146)
			!= symbol_address("__ZN10PlayerMine19setExplosionHandlerEP16ExplosionHandler")
		)
	):
		fail("Unsupported mine actor/effect association.")
		return {}
	var links := {
		0x6c: "__ZN6Player10getEnemiesEv",
		0x84: "__ZN6Player8isActiveEv",
		0xd4: "__ZN10PlayerMine5awakeEv",
		0xde: "__ZN6Player15getMaxHitpointsEv",
		0xe6: "__ZN6Player12setHitpointsEi",
		0xfe: "__ZN6Player8getEnemyEi",
		0x140: "__ZN11AbyssEngine18ApplicationManager9SoundPlayEi",
		0x164: "__ZN16ExplosionHandler5startEN11AbyssEngine6AEMath6MatrixE",
		0x23c: "__ZN16ExplosionHandler5startEN11AbyssEngine6AEMath6MatrixE",
		0x1aa: "__ZN6Player15getMaxHitpointsEv",
		0x210: "__ZN6Player6damageEi",
		0x250: "__ZN5Level9enemyDiedEi",
		0x2f0: "__ZN16ExplosionHandler11hasFinishedEv",
		0x31a: "__ZN16ExplosionHandler11hasFinishedEv"
	}
	for offset in links:
		if call_target(update + offset) != symbol_address(links[offset]):
			fail("Unsupported mine state data consumer.")
			return {}
	# These guards distinguish the source's asymmetric blast test and opponent
	# selection from an ordinary radial explosion. Only semantic data is retained.
	var bindings := [
		[0xae, 0x2b01],
		[0xb0, 0xd01c],
		[0xb8, 0x185b],
		[0xba, 0x4293],
		[0xbc, 0xd816],
		[0xc0, 0x428b],
		[0xc2, 0xdc13],
		[0xc6, 0x4293],
		[0xc8, 0xdd10],
		[0xcc, 0x428b],
		[0xce, 0xdc0d],
		[0xd0, 0x4293],
		[0xd2, 0xdd0b],
		[0xf4, 0x2200],
		[0xf6, 0x4692],
		[0x1f0, 0x00db],
		[0x1f2, 0x4299],
		[0x1f4, 0xdc00],
		[0x1fa, 0x6f2b],
		[0x1fc, 0x4293],
		[0x1fe, 0xdc09],
		[0x200, 0x6f6b],
		[0x202, 0x4293],
		[0x204, 0xdc06],
		[0x206, 0x6fab],
		[0x208, 0x4293],
		[0x20a, 0xdc03]
	]
	for pair in bindings:
		if u16(update + pair[0]) != pair[1]:
			fail("Unsupported mine proximity/fuse declarations.")
			return {}
	for offset in [0xb8, 0xc8]:
		if (
			call_target(constructor + offset)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		):
			fail("Unsupported armed mine geometry consumer.")
			return {}
	var meshes := [literal(constructor + 0xb6, 2), literal(constructor + 0xc6, 2)]
	for mesh_id in meshes:
		if not resources.get(str(mesh_id), {}).get("path", "").ends_with(".aem"):
			fail("Missing armed mine mesh association.")
			return {}
	var result := {
		"actor": actor,
		"arming_half_width": literal(update + 0xb2, 1) * .02,
		"blast_upper_bound": literal(update + 0x1f8, 2) * .02,
		"blast_test": "source_upper_axes",
		"target_selection": "first_opponent_last_active_delta",
		"fuse_ms": immediate_at(update + 0x1ee, 3) << 3,
		"damage": immediate_at(update + 0x20e, 1),
		"armed_meshes": meshes,
		"arm_sound": immediate_at(awake + 8, 1),
		"shot_sound": immediate_at(update + 0x13a, 1),
		"explosion": mine_explosion(immediate_at(factory + 0x12e, 1), resources)
	}
	if not result.explosion.is_empty():
		result.explosion.sounds = actor_explosion_sounds(
			immediate_at(factory + 0x12e, 1), result.explosion.layers
		)
	if (
		literal(update + 0xb6, 2) != literal(update + 0xb2, 1) * 2
		or (signed_literal(update + 0xc4, 2) + 1 != -literal(update + 0xb2, 1))
	):
		fail("Unsupported mine arming bounds.")
		return {}
	return result


func mine_explosion(kind: int, resources: Dictionary) -> Dictionary:
	var handler := symbol_address("__ZN16ExplosionHandlerC2E19ExplosionObjectType")
	var dispatch := calls_between(handler, handler + 0x100, "___switch32")
	if dispatch.size() != 1:
		fail("Missing mine explosion declarations.")
		return {}
	var table := dispatch[0] + 4
	if kind < 0 or kind >= u32(table) or u32(table) > 32:
		fail("Unsupported mine explosion kind.")
		return {}
	var start := table + u32(table + 4 + kind * 4)
	var links := {
		0x16: "__ZN10iExplosionC1E13ExplosionParti",
		0x26: "__Z8ArrayAddIP10iExplosionEvT_R5ArrayIS2_E",
		0x36: "__Z8ArrayAddIjEvT_R5ArrayIS0_E",
		0x4e: "__ZN10iExplosionC1E13ExplosionPart",
		0x5e: "__Z8ArrayAddIP10iExplosionEvT_R5ArrayIS2_E",
		0x6e: "__Z8ArrayAddIjEvT_R5ArrayIS0_E"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported mine explosion layers.")
			return {}
	var initialize := symbol_address("__ZN10iExplosion10initializeE13ExplosionPartijiii")
	var effect_update := symbol_address("__ZN10iExplosion6updateEj")
	var ease := symbol_address("__ZN11AbyssEngine9EaseInOutC2Eii")
	var ease_update := symbol_address("__ZN11AbyssEngine9EaseInOut18UpdateCurrentValueEv")
	var parts := [immediate_at(start + 0x10, 1), immediate_at(start + 0x4a, 1)]
	var part_table := initialize + 0x80
	if call_target(part_table - 4) != symbol_address("___switch32") or u32(part_table) > 32:
		fail("Unsupported explosion layer defaults.")
		return {}
	var span := (immediate_at(ease_update + 8, 3) << 9) - (immediate_at(ease + 4, 3) << 8)
	var rate_numerator := literal_float(initialize + 0x120, 0)
	var rate_divisor := literal_float(initialize + 0x118, 1)
	var arithmetic := imported_symbols()
	if (
		not arithmetic.get("___mulsf3vfp", []).has(call_target(initialize + 0x11a))
		or not arithmetic.get("___divsf3vfp", []).has(call_target(initialize + 0x122))
		or (
			call_target(initialize + 0x206)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		)
		or (
			call_target(effect_update + 0x52)
			!= symbol_address("__ZN11AbyssEngine9EaseInOut8IncreaseEi")
		)
		or u16(effect_update + 0x102) != 0xdc00
	):
		fail("Unsupported explosion timing consumer.")
		return {}
	var layers := []
	for index in parts.size():
		var part: int = parts[index]
		if part < 0 or part >= u32(part_table):
			fail("Unsupported mine explosion part.")
			return {}
		var defaults := part_table + u32(part_table + 4 + part * 4)
		var parameter := (
			immediate_at(start + 0x12, 2) if index == 0 else immediate_at(defaults + 4, 2)
		)
		var scale_percent := immediate_at(
			defaults + (4 if index == 0 else 6), 2 if index == 0 else 1
		)
		var mesh_id := literal(initialize + 0x1fa, 3) + part
		if (
			parameter <= 0
			or span <= 0
			or rate_numerator <= 0
			or rate_divisor <= 0
			or not resources.has(str(mesh_id))
		):
			fail("Invalid mine explosion data.")
			return {}
		layers.append(
			{
				"mesh": mesh_id,
				"delay_ms": immediate_at(start + (0x2e if index == 0 else 0x66), 0),
				"duration_ms": float(span) * parameter * rate_divisor / rate_numerator,
				"scale": float(scale_percent) / immediate_at(initialize + 0x216, 1)
			}
		)
	return {
		"layers": layers,
		"alpha_start": immediate_at(initialize + 0x254, 1),
		"alpha_end": immediate_at(initialize + 0x256, 2),
		"alpha_cutoff": u16(effect_update + 0x100) & 255
	}


func contract_minefield() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var switches := calls_between(level, level + 1400, "___switch32")
	if switches.size() != 1:
		fail("Missing minefield contract dispatch.")
		return {}
	var table: int = switches[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid minefield contract dispatch.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0x6e) == symbol_address("__ZN5RouteC1EPii")
			and (
				call_target(candidate + 0x158)
				== symbol_address("__ZN5Level18createStaticObjectEP8Waypointi")
			)
		):
			if start != 0 and start != candidate:
				fail("Ambiguous minefield contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x1e8 >= symbol_end(level):
		fail("Unsupported minefield contract boundary.")
		return {}
	var links := {
		0x30: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x46: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x6e: "__ZN5RouteC1EPii",
		0xda: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x126: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x14e: "__ZN5Route11getWaypointEv",
		0x158: "__ZN5Level18createStaticObjectEP8Waypointi",
		0x18a: "__ZN5Route11getWaypointEi",
		0x19c: "__ZN5Level10createShipEiiibP8Waypoint",
		0x1c0: "__ZN9ObjectiveC1EiiP5Level",
		0x1e4: "__ZN5RouteD1Ev"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported minefield source binding.")
			return {}
	# The temporary Route owns the spawn center; it is destroyed here rather
	# than installed as the player's route. The last array entry is one defender.
	for pair in [
		[0x3e, 0x1880],
		[0x40, 0x6018],
		[0x4e, 0x1940],
		[0x50, 0x6008],
		[0x16e, 0x3b01],
		[0x170, 0x429d],
		[0x172, 0xdbe1],
		[0x192, 0x9300],
		[0x198, 0x9001],
		[0x1ba, 0x3a01],
		[0x1ce, 0x6148]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported minefield spawn/count association.")
			return {}
	if (
		immediate_at(start + 0x6c, 2) != 3
		or immediate_at(start + 0x18e, 3) != 1
		or immediate_at(start + 0x190, 2) != 0
		or immediate_at(start + 0x194, 1) != 0
		or u16(start + 0xde) & 0xff00 != 0x3000
	):
		fail("Unsupported minefield route or defender role.")
		return {}
	var achieved := symbol_address("__ZN9Objective8achievedEi")
	var choices := calls_between(achieved, symbol_end(achieved), "___switch8")
	if choices.size() != 1:
		fail("Missing minefield objective declaration.")
		return {}
	var branches := contract_choice_targets(choices[0], achieved)
	var kind := immediate_at(start + 0x1ac, 1)
	if (
		kind < 0
		or kind >= branches.size()
		or call_target(branches[kind] + 2) != symbol_address("__ZN5Level10getEnemiesEv")
		or call_target(branches[kind] + 22) != symbol_address("__ZN8KIPlayer6isDeadEv")
		or u16(branches[kind] + 36) != 0x429c
	):
		fail("Unsupported minefield completion prefix.")
		return {}
	var x := signed_literal(start + 0x34, 2)
	var y := signed_literal(start + 0x20, 5)
	var z := literal(start + 0x14, 3)
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	return {
		"family": "minefield",
		"types": types,
		"center_bounds":
		[[x, x + literal(start + 0x2e, 1) - 1], [y, y + literal(start + 0x3c, 1) - 1], [z, z]],
		"total_base": u16(start + 0xde) & 255,
		"total_variation": immediate_at(start + 0xd4, 1),
		"defenders": u16(start + 0x16e) & 255,
		"mine_actor": immediate_at(start + 0x152, 2),
		"defender_actor": immediate_at(start + 0x196, 3),
		"scatter": static_scatter(),
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"success_kind": "enemy_prefix_destroyed"
	}


func contract_asteroids() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var switches := calls_between(level, level + 1400, "___switch32")
	if switches.size() != 1:
		fail("Missing asteroid contract dispatch.")
		return {}
	var table: int = switches[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid asteroid contract dispatch.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0x6e) == symbol_address("__ZN5RouteC1EPii")
			and call_target(candidate + 0xa0) == symbol_address("__ZN13AsteroidFieldC1EiP8Waypoint")
		):
			if start != 0 and start != candidate:
				fail("Ambiguous asteroid contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x1e0 >= symbol_end(level):
		fail("Unsupported asteroid contract boundary.")
		return {}
	var links := {
		0x34: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x46: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x6e: "__ZN5RouteC1EPii",
		0x84: "__ZN5Route11getWaypointEv",
		0xa0: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0xe0: "__ZN7Mission21getRelativeDifficultyEi",
		0x12e: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x150: "__ZN5Route11getWaypointEv",
		0x162: "__ZN5Level10createShipEiiibP8Waypoint",
		0x1a6: "__ZN9ObjectiveC1EiiP5Level",
		0x1da: "__ZN5RouteD1Ev"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported asteroid contract source binding.")
			return {}
	var arithmetic := imported_symbols()
	for pair in [
		[0xe4, "___floatsisfvfp"],
		[0xea, "___divsf3vfp"],
		[0xf0, "___mulsf3vfp"],
		[0xf4, "___fixsfsivfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported asteroid defender count arithmetic.")
			return {}
	# Source center, one field, awake enemy array, timer and survival objective.
	# The temporary Route is released, never installed as the player's route.
	for pair in [
		[0x3c, 0x18c0],
		[0x3e, 0x6020],
		[0x52, 0x1840],
		[0x54, 0x6010],
		[0xb0, 0x2398],
		[0xb4, 0x50e5],
		[0xf8, 0x9014],
		[0x12a, 0x9814],
		[0x154, 0x2301],
		[0x156, 0x9300],
		[0x158, 0x2100],
		[0x15a, 0x2200],
		[0x15e, 0x9001],
		[0x178, 0x429c],
		[0x17a, 0xd3de],
		[0x180, 0x25c4],
		[0x184, 0x5153],
		[0x19c, 0x594a],
		[0x1c4, 0x6148]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported asteroid contract declaration consumer.")
			return {}
	if immediate_at(start + 0x64, 2) != 3:
		fail("Unsupported asteroid spawn point dimensions.")
		return {}
	var achieved := symbol_address("__ZN9Objective8achievedEi")
	var choices := calls_between(achieved, symbol_end(achieved), "___switch8")
	if choices.size() != 1:
		fail("Missing asteroid survival objective.")
		return {}
	var branches := contract_choice_targets(choices[0], achieved)
	var kind := immediate_at(start + 0x1a2, 1)
	var survival := symbol_address("__ZN9Objective19isSurvivalObjectiveEv")
	if kind < 0 or kind >= branches.size() or u16(survival + 4) != (0x2800 | kind):
		fail("Unsupported asteroid survival classification.")
		return {}
	for pair in [[0, 0x686b], [2, 0x2000], [4, 0x4543], [6, 0xda28], [8, 0x2001]]:
		if u16(branches[kind] + pair[0]) != pair[1]:
			fail("Unsupported asteroid survival time comparison.")
			return {}
	var finish := symbol_address("__ZN5MGame11finishLevelEv")
	var count := symbol_address("__ZN13AsteroidField21getDestroyedAsteroidsEv")
	var getter := symbol_address("__ZN5Level21getAsteroidsDestroyedEv")
	if (
		call_target(finish + 0x26) != getter
		or call_target(getter + 0xc) != count
		or u16(getter + 4) != u16(start + 0xb0)
		or u16(finish + 0xc0) != (0x2800 | int(types[0]))
		or call_target(finish + 0xd2) != symbol_address("__ZN7Mission9getRewardEv")
		or u16(finish + 0xd6) != 0x4643
		or u16(finish + 0xd8) != 0x1c01
		or u16(finish + 0xda) != 0x4359
		or call_target(finish + 0xde) != symbol_address("__ZN7Mission9setRewardEi")
	):
		fail("Unsupported asteroid per-target settlement association.")
		return {}
	var render := symbol_address("__ZN8Asteroid6renderEib")
	if (
		types.size() != 1
		or call_target(render + 0x2a) != symbol_address("__ZN16ExplosionHandler11hasFinishedEv")
		or u16(render + 0x30) != 0xd00c
		or u16(render + 0x38) != 0xd00c
		or u16(render + 0x3a) != 0x2100
		or u16(render + 0x40) != 0x7021
	):
		fail("Unsupported asteroid destruction completion association.")
		return {}
	# Counts inactive parent rocks, after their explosion finishes. Fragments
	# are cosmetic, not extra billable targets; collisions are not excluded.
	for pair in [[0x12, 0x781b], [0x14, 0x2b00], [0x16, 0xd100], [0x18, 0x3401]]:
		if u16(count + pair[0]) != pair[1]:
			fail("Unsupported destroyed-asteroid count consumer.")
			return {}
	var x := signed_literal(start + 0x38, 3)
	var y := signed_literal(start + 0x4c, 1)
	var z := literal(start + 0x14, 3)
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var field := asteroid_field_definition(immediate_at(start + 0x9c, 1), 0)
	field.erase("waypoint")
	field["center"] = [0, 0, 0]
	return {
		"family": "asteroids",
		"types": types,
		"center_bounds":
		[[x, x + literal(start + 0x20, 1) - 1], [y, y + literal(start + 0x3a, 1) - 1], [z, z]],
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"pirate_divisor": literal_float(start + 0xe8, 1),
		"pirate_factor": literal_float(start + 0xee, 1),
		"pirate_actor": immediate_at(start + 0x15c, 3),
		"duration_ms": literal(start + 0x17c, 3),
		"success_kind": "time_survived",
		"payout_kind": "finished_asteroids",
		"field": field
	}


func asteroid_destruction() -> Dictionary:
	var field := symbol_address("__ZN13AsteroidFieldC2EiP8Waypoint")
	var asteroid := symbol_address("__ZN8AsteroidC2Ev")
	var render := symbol_address("__ZN8Asteroid6renderEib")
	var handler := symbol_address("__ZN16ExplosionHandlerC2E19ExplosionObjectType")
	var dispatch := calls_between(handler, handler + 0x100, "___switch32")
	if (
		dispatch.size() != 1
		or (
			call_target(field + 0x6a)
			!= symbol_address("__ZN16ExplosionHandlerC1E19ExplosionObjectType")
		)
	):
		fail("Missing asteroid destruction effect binding.")
		return {}
	var table: int = dispatch[0] + 4
	var kind := immediate_at(field + 0x66, 1)
	if kind < 0 or kind >= u32(table) or u32(table) > 32:
		fail("Unsupported asteroid destruction effect kind.")
		return {}
	var start := table + u32(table + 4 + kind * 4)
	var initialize := symbol_address("__ZN10iExplosion10initializeE13ExplosionPartijiii")
	var effect_update := symbol_address("__ZN10iExplosion6updateEj")
	var ease := symbol_address("__ZN11AbyssEngine9EaseInOutC2Eii")
	var ease_update := symbol_address("__ZN11AbyssEngine9EaseInOut18UpdateCurrentValueEv")
	var sine := symbol_address("__ZN11AbyssEngine6AEMath3SinEi")
	var arithmetic := imported_symbols()
	for pair in [
		[initialize + 0x11a, "___mulsf3vfp"],
		[initialize + 0x122, "___divsf3vfp"],
		[sine + 0xa, "___mulsf3vfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(pair[0])):
			fail("Unsupported asteroid effect arithmetic.")
			return {}
	if (
		(
			call_target(initialize + 0x206)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		)
		or (
			call_target(effect_update + 0x52)
			!= symbol_address("__ZN11AbyssEngine9EaseInOut8IncreaseEi")
		)
		or u16(effect_update + 0x102) != 0xdc00
	):
		fail("Unsupported asteroid effect envelope consumer.")
		return {}
	var span := (immediate_at(ease_update + 8, 3) << 9) - (immediate_at(ease + 4, 3) << 8)
	var numerator := literal_float(initialize + 0x120, 0)
	var divisor := literal_float(initialize + 0x118, 1)
	var radians := literal_float(sine + 8, 1)
	var defaults := initialize + 0x80
	if call_target(defaults - 4) != symbol_address("___switch32") or u32(defaults) > 32:
		fail("Unsupported asteroid effect defaults.")
		return {}
	# Layout offsets recognize six declarative constructor records; all effect
	# parts, delays, rates, scales and rotations are read from those records.
	if (
		span <= 0
		or not is_finite(numerator)
		or numerator <= 0
		or not is_finite(divisor)
		or divisor <= 0
		or not is_finite(radians)
		or radians <= 0
	):
		fail("Invalid asteroid effect timing or angle scale.")
		return {}
	if (
		u16(render + 0xc0) & 0xf83f != 0x002a
		or u16(render + 0xc6) & 0xf83f != 0x102b
		or u16(start + 0x52) & 0xf83f != 0x001b
		or u16(start + 2) != 0x425b
		or u16(start + 0x42) != 0x4249
	):
		fail("Unsupported asteroid effect scale or fragment motion.")
		return {}
	var half_rate := 1.0 / float(1 << ((u16(render + 0xc6) >> 6) & 31))
	var spin_rate := float(1 << ((u16(render + 0xc0) >> 6) & 31))
	var records := [
		[0x22, 0x1c, 0x1a, 0x1e, 0, 0x38, 0x32, 0x3c],
		[0x64, 0x5e, 0x60, 0x50, 1, 0x7c, 0x74, 0x84],
		[0x9e, 0x98, 0x9a, -1, 0, 0xb4, 0xae, 0xb8],
		[0xe0, 0xd2, 0xd4, 0xdc, 0, 0xf6, 0xf0, 0xfa],
		[0x122, 0x10c, 0x10e, 0x11e, 0, 0x158, 0x152, 0x15c],
		[0x184, 0x172, 0x174, 0x180, 0, 0x19a, 0x194, 0x19e]
	]
	var layers := []
	for index in records.size():
		var item: Array = records[index]
		var constructor := (
			"__ZN10iExplosionC1E13ExplosionParti"
			if index == 2
			else "__ZN10iExplosionC1E13ExplosionPartijiii"
		)
		if (
			call_target(start + item[0]) != symbol_address(constructor)
			or (
				call_target(start + item[6])
				!= symbol_address("__Z8ArrayAddIP10iExplosionEvT_R5ArrayIS2_E")
			)
			or call_target(start + item[7]) != symbol_address("__Z8ArrayAddIjEvT_R5ArrayIS0_E")
		):
			fail("Unsupported asteroid explosion layer association.")
			return {}
		var part := immediate_at(start + item[1], 1)
		if part < 0 or part >= u32(defaults):
			fail("Unsupported asteroid explosion part.")
			return {}
		var scale_percent := 0
		if item[3] < 0:
			var branch := defaults + u32(defaults + 4 + part * 4)
			if u16(branch + 2) & 0xf800 != 0xe000:
				fail("Unsupported asteroid default scale binding.")
				return {}
			var shared := (
				branch
				+ 6
				+ ((u16(branch + 2) & 0x7ff) - (0x800 if (u16(branch + 2) & 0x400) != 0 else 0)) * 2
			)
			scale_percent = immediate_at(shared + 4, 0)
		else:
			scale_percent = immediate_at(start + item[3], 3)
			if item[4] != 0:
				scale_percent <<= (u16(start + 0x52) >> 6) & 31
		var sentinel := -immediate_at(start, 3)
		var rotation := [sentinel, sentinel, sentinel]
		if index == 3:
			rotation = [
				immediate_at(start + 0xc8, 3),
				immediate_at(start + 0xcc, 3),
				signed_literal(start + 0xd0, 3)
			]
		elif index == 4:
			rotation = [
				signed_literal(start + 0x10a, 3),
				immediate_at(start + 0x112, 3),
				immediate_at(start + 0x116, 3)
			]
		elif index == 5:
			rotation = [
				immediate_at(start + 0x16c, 3),
				signed_literal(start + 0x170, 3),
				signed_literal(start + 0x178, 3)
			]
		layers.append(
			{
				"mesh": literal(initialize + 0x1fa, 3) + part,
				"delay_ms": immediate_at(start + item[5], 0),
				"duration_ms": float(span) * immediate_at(start + item[2], 2) * divisor / numerator,
				"scale": float(scale_percent) / immediate_at(initialize + 0x216, 1),
				"rotation": [-rotation[0] * radians, -rotation[1] * radians, rotation[2] * radians]
			}
		)
	var fragments := []
	for offset in [0x9c, 0xc6, 0xf0]:
		if (
			call_target(asteroid + offset + 2)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt")
		):
			fail("Unsupported asteroid fragment geometry.")
			return {}
		fragments.append(literal(asteroid + offset, 2))
	return {
		"effect":
		{
			"layers": layers,
			"alpha_start": immediate_at(initialize + 0x254, 1),
			"alpha_end": immediate_at(initialize + 0x256, 2),
			"alpha_cutoff": u16(effect_update + 0x100) & 255
		},
		"audio": asteroid_destruction_audio(kind, layers),
		"fragment_meshes": fragments,
		"fragment_duration_ms": literal(render + 0xac, 2),
		"fragment_velocity":
		[[0, .02 * 1000, 0], [.02 * 1000, 0, 0], [0, 0, -.02 * 1000 * half_rate]],
		"fragment_spin": [-radians * 1000, -radians * 1000 * half_rate, radians * 1000 * spin_rate]
	}


func contract_escort() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var switches := calls_between(level, level + 1400, "___switch32")
	if switches.size() != 1:
		fail("Missing escort contract dispatch.")
		return {}
	var table: int = switches[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid escort contract dispatch.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0xa6) == symbol_address("__ZN5RouteC1EPii")
			and call_target(candidate + 0x3f0) == symbol_address("__ZN6Player15setMaxHitpointsEi")
		):
			if start != 0 and start != candidate:
				fail("Ambiguous escort contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x5ac >= symbol_end(level) or types.size() != 1:
		fail("Unsupported escort contract boundary.")
		return {}
	var links := {
		0x56: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x6e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x80: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xa6: "__ZN5RouteC1EPii",
		0xc8: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xec: "__ZN5Route6lengthEv",
		0xfe: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x106: "__ZN5Route11getWaypointEi",
		0x11e: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0x14c: "__ZN5Route6lengthEv",
		0x154: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x15c: "__ZN5Route11getWaypointEi",
		0x176: "__ZN3FogC1EP8Waypoint",
		0x19e: "__ZN6Status10getMissionEv",
		0x1a2: "__ZN7Mission13getClientRaceEv",
		0x1be: "__ZN6Status10getMissionEv",
		0x1c2: "__ZN7Mission13getClientRaceEv",
		0x1f2: "__ZN6Status10getMissionEv",
		0x1fc: "__ZN6Status10getStationEv",
		0x200: "__ZN7Station11getQuadrantEv",
		0x208: "__ZN7Mission21getRelativeDifficultyEi",
		0x212: "__ZN6Status10getStationEv",
		0x216: "__ZN7Station11getQuadrantEv",
		0x260: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x296: "__ZN5Route6lengthEv",
		0x2a4: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x2ac: "__ZN5Route11getWaypointEi",
		0x2be: "__ZN5Level10createShipEiiibP8Waypoint",
		0x2ce: "__ZN8KIPlayer10setToSleepEv",
		0x318: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x388: "__ZN5Level10createShipEiiibP8Waypoint",
		0x398: "__ZN6Status10getStationEv",
		0x39c: "__ZN7Station11getQuadrantEv",
		0x3a6: "__ZN6Status8getLevelEv",
		0x3f0: "__ZN6Player15setMaxHitpointsEi",
		0x422: "__ZN11AbyssEngine6AEMath17MatrixGetPositionERKNS0_6MatrixE",
		0x43c: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x450: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x46a: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x490: "__ZN17PlayerFixedObject11setPositionEiii",
		0x4ae: "__ZN17PlayerFixedObject11setPositionEiii",
		0x4cc: "__ZN17PlayerFixedObject11setPositionEiii",
		0x4ea: "__ZN17PlayerFixedObject11setPositionEiii",
		0x50c: "__ZN17PlayerFixedObject11setPositionEiii",
		0x534: "__ZN9ObjectiveC1EiiP5Level",
		0x568: "__ZN9ObjectiveC1EiiP5Level",
		0x58e: "__ZN8GameText7getTextEi",
		0x596: "__ZN9Objective15setAchievedTextEPN11AbyssEngine6StringE",
		0x5a6: "__ZN5RouteD1Ev"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported escort contract source binding.")
			return {}
	var arithmetic := imported_symbols()
	for pair in [
		[0x220, "___floatsisfvfp"],
		[0x226, "___divsf3vfp"],
		[0x22c, "___addsf3vfp"],
		[0x230, "___fixsfsivfp"],
		[0x3b8, "___floatsisfvfp"],
		[0x3d4, "___subsf3vfp"],
		[0x3dc, "___mulsf3vfp"],
		[0x3e4, "___subsf3vfp"],
		[0x3e8, "___fixsfsivfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported escort count or hull arithmetic.")
			return {}
	# Validate the data consumers: temporary route, faction associations, array
	# roles, shared formation origin, health adjustment and objective bindings.
	for pair in [
		[0x10, 0x2300],
		[0x64, 0x1940],
		[0x66, 0x6008],
		[0x76, 0x18c0],
		[0x78, 0x6020],
		[0x8c, 0x1840],
		[0x8e, 0x6010],
		[0x1a8, 0xd103],
		[0x1ae, 0x92c3],
		[0x1c8, 0xd004],
		[0x1ce, 0x92c3],
		[0x1d0, 0x93c4],
		[0x1d8, 0x94c3],
		[0x1da, 0x95c4],
		[0x22a, 0x1c01],
		[0x236, 0x1820],
		[0x238, 0x90c5],
		[0x25c, 0x98c5],
		[0x2b0, 0x2301],
		[0x2b2, 0x9300],
		[0x2b4, 0x2100],
		[0x2b6, 0x2200],
		[0x2b8, 0x9bc4],
		[0x2ba, 0x9001],
		[0x312, 0x6605],
		[0x366, 0x2100],
		[0x372, 0x2203],
		[0x378, 0x2300],
		[0x37a, 0x9300],
		[0x37c, 0x9301],
		[0x384, 0x9bc3],
		[0x3ac, 0x1c03],
		[0x3b0, 0x18c0],
		[0x3b4, 0x191b],
		[0x3b6, 0x18c0],
		[0x3d2, 0x69d8],
		[0x3d8, 0x1c01],
		[0x3da, 0x9858],
		[0x3e0, 0x1c01],
		[0x3e2, 0x9858],
		[0x3ec, 0x1c01],
		[0x444, 0x1913],
		[0x446, 0x181b],
		[0x456, 0x192b],
		[0x45e, 0x181b],
		[0x474, 0x192b],
		[0x47a, 0x181b],
		[0x484, 0x18d1],
		[0x486, 0x1962],
		[0x48e, 0x1963],
		[0x4a4, 0x18d1],
		[0x4a6, 0x1962],
		[0x4ac, 0x1963],
		[0x4c2, 0x18d1],
		[0x4c4, 0x1962],
		[0x4ca, 0x1963],
		[0x4e0, 0x18d1],
		[0x4e2, 0x1962],
		[0x4e8, 0x1963],
		[0x500, 0x18d1],
		[0x502, 0x1962],
		[0x50a, 0x1963],
		[0x514, 0x21c4],
		[0x518, 0x5043],
		[0x522, 0x24c4],
		[0x52a, 0x591a],
		[0x54e, 0x6151],
		[0x55e, 0x2200],
		[0x57e, 0x6191]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported escort declaration consumer.")
			return {}
	var achieved := symbol_address("__ZN9Objective8achievedEi")
	var choices := calls_between(achieved, symbol_end(achieved), "___switch8")
	if choices.size() != 1:
		fail("Missing escort objective choices.")
		return {}
	var branches := contract_choice_targets(choices[0], achieved)
	var success := immediate_at(start + 0x526, 1)
	var failure := immediate_at(start + 0x55a, 1)
	var survival := symbol_address("__ZN9Objective19isSurvivalObjectiveEv")
	if (
		success < 0
		or success >= branches.size()
		or failure < 0
		or failure >= branches.size()
		or u16(survival + 4) != (0x2800 | success)
	):
		fail("Unsupported escort survival classification.")
		return {}
	for pair in [[0, 0x686b], [2, 0x2000], [4, 0x4543], [6, 0xda28], [8, 0x2001]]:
		if u16(branches[success] + pair[0]) != pair[1]:
			fail("Unsupported escort survival comparison.")
			return {}
	if (
		call_target(branches[failure] + 6) != symbol_address("__ZN5Level14getFriendsLeftEv")
		or u16(branches[failure] + 10) != 0x1e43
		or u16(branches[failure] + 12) != 0x4383
	):
		fail("Unsupported escort convoy-loss objective.")
		return {}
	var set_hp := symbol_address("__ZN6Player15setMaxHitpointsEi")
	if u16(set_hp + 4) != 0x6501 or u16(set_hp + 6) != 0x6481:
		fail("Unsupported escort initial-health assignment.")
		return {}
	var races := [u16(start + 0x1c6) & 255, u16(start + 0x1a6) & 255]
	var actors := [
		immediate_at(start + 0x1d4, 4),
		immediate_at(start + 0x1aa, 2),
		immediate_at(start + 0x1cc, 2)
	]
	var cargo := convoy_bodies(actors[0])
	var second := fixed_collision(actors[1])
	var third := escort_cargo_collision(actors[2])
	if cargo.is_empty() or second.is_empty() or third.is_empty():
		return {}
	var fleets := [
		{
			"race": races[0],
			"cargo_actor": actors[0],
			"attacker_actor": immediate_at(start + 0x1d6, 5),
			"collisions": [cargo.cargo]
		},
		{
			"race": races[1],
			"cargo_actor": actors[1],
			"attacker_actor": immediate_at(start + 0x1ac, 3),
			"collisions": [second]
		},
		{
			"race": -1,
			"cargo_actor": actors[2],
			"attacker_actor": immediate_at(start + 0x1ca, 3),
			"collisions": third
		}
	]
	var bounds := []
	for pair in [[0x46, 5, 0x44], [0x72, 3, 0x6a], [0x86, 1, 0x74]]:
		var low := literal(start + pair[0], pair[1])
		var width := literal(start + pair[2], 1)
		bounds.append([[0, 0], [0, 0], [low, low + width - 1]])
	var formation := [
		[
			signed_literal(start + 0x480, 3),
			signed_literal(start + 0x478, 5),
			literal(start + 0x48a, 5)
		],
		[
			signed_literal(start + 0x4a2, 3),
			signed_literal(start + 0x49a, 5),
			literal(start + 0x4aa, 5)
		],
		[
			signed_literal(start + 0x4c0, 3),
			signed_literal(start + 0x4b8, 5),
			literal(start + 0x4c8, 5)
		],
		[
			signed_literal(start + 0x4de, 3),
			signed_literal(start + 0x4d6, 5),
			literal(start + 0x4e6, 5)
		],
		[
			shifted_immediate(start + 0x4fc, 3),
			signed_literal(start + 0x4f4, 5),
			shifted_immediate(start + 0x506, 5)
		]
	]
	if (
		immediate_at(start + 0x9a, 2) != bounds.size() * 3
		or immediate_at(start + 0x316, 0) != formation.size()
	):
		fail("Unsupported escort route or formation dimensions.")
		return {}
	var jitter := []
	var low := signed_literal(start + 0x412, 4)
	for offset in [0x43a, 0x44a, 0x45c]:
		jitter.append([low, low + literal(start + offset, 1) - 1])
	var field := asteroid_field_definition(immediate_at(start + 0x114, 1), 0)
	field.erase("waypoint")
	field["center"] = [0, 0, 0]
	var fog := fog_presentation()
	fog.erase("waypoint")
	fog["center"] = [0, 0, 0]
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var rank_shift := u16(start + 0x3ae)
	var region_shift := u16(start + 0x3b2)
	if rank_shift & 0xf83f != 0 or region_shift & 0xf83f != 0x23:
		fail("Unsupported escort hull coefficients.")
		return {}
	var result := {
		"family": "escort",
		"types": types,
		"route_bounds": bounds,
		"formation": formation,
		"jitter": jitter,
		"fleets": fleets,
		"speed": cargo.speed,
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"count_base": u16(start + 0x21a) & 255,
		"count_divisor": literal_float(start + 0x224, 1),
		"rank_factor": (1 << ((rank_shift >> 6) & 31)) + 1,
		"region_factor": (1 << ((region_shift >> 6) & 31)) + 1,
		"difficulty_offset": literal_float(start + 0x3be, 1),
		"scenery_choices": immediate_at(start + 0xc6, 1),
		"asteroid_choice": u16(start + 0xcc) & 255,
		"fog_choice": u16(start + 0xd0) & 255,
		"field": field,
		"fog": fog,
		"duration_ms": literal(start + 0x512, 3),
		"success_kind": "time_survived",
		"failure_kind": "allies_destroyed",
		"failure_text": shifted_at(start + 0x582, start + 0x58a, 1)
	}
	return result if error.is_empty() else {}


func escort_cargo_collision(actor: int) -> Array:
	var start := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	if u16(start + 0x764) != (0x2900 | actor):
		fail("Unsupported escort cargo subtype.")
		return []
	for offset in [0x818, 0x860, 0x8a4, 0x8e6, 0x92a]:
		if call_target(start + offset) != symbol_address("__ZN11BoundingAABC1Eiiiiiiiii"):
			fail("Unsupported escort cargo collision constructor.")
			return []
	for pair in [
		[0x7f0, 0x9300],
		[0x7f4, 0x425b],
		[0x7f6, 0x9301],
		[0x7fc, 0x9302],
		[0x802, 0x9303],
		[0x80a, 0x9304],
		[0x80e, 0x9305],
		[0x83c, 0x9300],
		[0x840, 0x425b],
		[0x842, 0x9301],
		[0x848, 0x9302],
		[0x84e, 0x9303],
		[0x852, 0x9304],
		[0x856, 0x9305],
		[0x880, 0x9300],
		[0x888, 0x9301],
		[0x88e, 0x9302],
		[0x892, 0x9303],
		[0x896, 0x9304],
		[0x89a, 0x9305],
		[0x8c4, 0x9300],
		[0x8cc, 0x9301],
		[0x8d0, 0x9302],
		[0x8d4, 0x9303],
		[0x8d8, 0x9304],
		[0x8dc, 0x9305],
		[0x906, 0x9300],
		[0x90a, 0x9301],
		[0x912, 0x9302],
		[0x916, 0x9303],
		[0x91c, 0x9304],
		[0x920, 0x9305]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported escort cargo collision consumer.")
			return []
	if u16(start + 0x8d6) & 0xff00 != 0x3300:
		fail("Unsupported escort cargo box dimension adjustment.")
		return []
	return [
		{
			"offset":
			[
				shifted_immediate(start + 0x7ec, 3),
				-immediate_at(start + 0x7f2, 3),
				shifted_immediate(start + 0x7f8, 3)
			],
			"size":
			[
				shifted_immediate(start + 0x7fe, 3),
				literal(start + 0x804, 3),
				literal(start + 0x80c, 3)
			]
		},
		{
			"offset":
			[
				signed_literal(start + 0x836, 3),
				-immediate_at(start + 0x83e, 3),
				shifted_immediate(start + 0x844, 3)
			],
			"size":
			[
				shifted_immediate(start + 0x84a, 3),
				literal(start + 0x850, 3),
				literal(start + 0x854, 3)
			]
		},
		{
			"offset":
			[
				immediate_at(start + 0x87e, 3),
				signed_literal(start + 0x882, 3),
				shifted_immediate(start + 0x88a, 3)
			],
			"size":
			[literal(start + 0x890, 3), literal(start + 0x894, 3), literal(start + 0x898, 3)]
		},
		{
			"offset":
			[
				immediate_at(start + 0x8c2, 3),
				signed_literal(start + 0x8c6, 3),
				signed_literal(start + 0x8ce, 3)
			],
			"size":
			[
				literal(start + 0x8d2, 3),
				literal(start + 0x8d2, 3) + (u16(start + 0x8d6) & 255),
				literal(start + 0x8da, 3)
			]
		},
		{
			"offset":
			[
				immediate_at(start + 0x904, 3),
				immediate_at(start + 0x908, 3),
				signed_literal(start + 0x90c, 3)
			],
			"size":
			[
				literal(start + 0x914, 3),
				shifted_immediate(start + 0x918, 3),
				literal(start + 0x91e, 3)
			]
		}
	]


func contract_intercept() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var dispatch := calls_between(level, level + 1400, "___switch32")
	if dispatch.size() != 1:
		fail("Missing interception contract dispatch.")
		return {}
	var table: int = dispatch[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid interception contract dispatch.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0x7e) == symbol_address("__ZN5RouteC1EPii")
			and (
				call_target(candidate + 0x2de)
				== symbol_address("__ZN17PlayerFixedObject9setMovingEb")
			)
		):
			if start != 0 and start != candidate:
				fail("Ambiguous interception contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x414 >= symbol_end(level) or types.size() != 1:
		fail("Unsupported interception contract boundary.")
		return {}
	var links := {
		0x2e: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x42: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x56: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x7e: "__ZN5RouteC1EPii",
		0xa8: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xb2: "__ZN5Level13createWingmanEv",
		0xc4: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xe2: "__ZN5Route11getWaypointEi",
		0xfe: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0x124: "__ZN5Route11getWaypointEi",
		0x13e: "__ZN3FogC1EP8Waypoint",
		0x1c8: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x1d6: "__ZN6Status10getMissionEv",
		0x1e0: "__ZN6Status10getStationEv",
		0x1e4: "__ZN7Station11getQuadrantEv",
		0x1ec: "__ZN7Mission21getRelativeDifficultyEi",
		0x1f6: "__ZN6Status10getStationEv",
		0x1fa: "__ZN7Station11getQuadrantEv",
		0x202: "__ZN6Status10getMissionEv",
		0x206: "__ZN7Mission13getClientRaceEv",
		0x27c: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x2aa: "__ZN5Route11getWaypointEi",
		0x2bc: "__ZN5Level10createShipEiiibP8Waypoint",
		0x2ce: "__ZN8KIPlayer10setToSleepEv",
		0x2de: "__ZN17PlayerFixedObject9setMovingEb",
		0x2f4: "__ZN5Route11getWaypointEi",
		0x306: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x312: "__ZN5Route11getWaypointEi",
		0x320: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x32a: "__ZN5Route11getWaypointEi",
		0x338: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x358: "__ZN17PlayerFixedObject11setPositionEiii",
		0x39c: "__ZN5Route11getWaypointEi",
		0x3b4: "__ZN5Level10createShipEiiibP8Waypoint",
		0x3c6: "__ZN8KIPlayer10setToSleepEv",
		0x408: "__ZN9ObjectiveC1EiiP5Level"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported interception contract source binding.")
			return {}
	var arithmetic := imported_symbols()
	for pair in [
		[0x262, "___floatsisfvfp"],
		[0x268, "___divsf3vfp"],
		[0x26e, "___addsf3vfp"],
		[0x272, "___fixsfsivfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported interception defender-count arithmetic.")
			return {}
	# Bind the persisted navigation point, optional wingman, enemy prefix, stopped
	# fixed-body targets and explicit placement. No original control flow is run.
	for pair in [
		[0x38, 0x1940],
		[0x3a, 0x6008],
		[0x4c, 0x1940],
		[0x4e, 0x6018],
		[0x60, 0x1940],
		[0x62, 0x6008],
		[0x90, 0x209c],
		[0x94, 0x5029],
		[0xae, 0xdc02],
		[0xca, 0xd002],
		[0xce, 0xd172],
		[0xd6, 0x239c],
		[0xde, 0x2100],
		[0x11a, 0x219c],
		[0x120, 0x2100],
		[0x20c, 0xd104],
		[0x212, 0x95cc],
		[0x214, 0x90cd],
		[0x216, 0xe003],
		[0x21c, 0x91cc],
		[0x21e, 0x92cd],
		[0x242, 0x9963],
		[0x24a, 0x91cb],
		[0x256, 0x65da],
		[0x258, 0x9b66],
		[0x25e, 0x185b],
		[0x260, 0x932e],
		[0x26c, 0x1c01],
		[0x27a, 0x1820],
		[0x29e, 0x239c],
		[0x2a0, 0x2100],
		[0x2ae, 0x2301],
		[0x2b0, 0x2203],
		[0x2b2, 0x9300],
		[0x2b4, 0x2100],
		[0x2b6, 0x9bcc],
		[0x2b8, 0x9001],
		[0x2d6, 0x2100],
		[0x2fe, 0x6dc0],
		[0x31a, 0x6e00],
		[0x332, 0x6e40],
		[0x344, 0x18d1],
		[0x346, 0x1909],
		[0x348, 0x18ea],
		[0x350, 0x18d2],
		[0x352, 0x1963],
		[0x354, 0x181b],
		[0x364, 0x9acb],
		[0x366, 0x4291],
		[0x368, 0xdb8f],
		[0x376, 0x92cf],
		[0x398, 0x2100],
		[0x3a0, 0x2301],
		[0x3a2, 0x2100],
		[0x3a4, 0x9300],
		[0x3a6, 0x2200],
		[0x3a8, 0x9bcd],
		[0x3b0, 0x9001],
		[0x3e0, 0x6813],
		[0x3e2, 0x429c],
		[0x3e4, 0xd3ca],
		[0x404, 0x9acb]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported interception declaration consumer.")
			return {}
	for pair in [
		[0xac, 0x2800],
		[0xc8, 0x2800],
		[0xcc, 0x2800],
		[0x20a, 0x2800],
		[0x248, 0x3100],
		[0x25c, 0x3300]
	]:
		if u16(start + pair[0]) & 0xff00 != pair[1]:
			fail("Unsupported interception choice/count declaration.")
			return {}
	var achieved := symbol_address("__ZN9Objective8achievedEi")
	var switches := calls_between(achieved, symbol_end(achieved), "___switch8")
	if switches.size() != 1:
		fail("Missing interception completion declaration.")
		return {}
	var branches := contract_choice_targets(switches[0], achieved)
	var kind := immediate_at(start + 0x3f8, 1)
	if (
		kind < 0
		or kind >= branches.size()
		or call_target(branches[kind] + 2) != symbol_address("__ZN5Level10getEnemiesEv")
		or call_target(branches[kind] + 22) != symbol_address("__ZN8KIPlayer6isDeadEv")
		or u16(branches[kind] + 36) != 0x429c
	):
		fail("Unsupported interception target-prefix objective.")
		return {}
	var matching_actor := immediate_at(start + 0x20e, 5)
	var other_actor := immediate_at(start + 0x218, 1)
	var body := convoy_bodies(matching_actor)
	var other := fixed_collision(other_actor)
	if body.is_empty() or other.is_empty():
		return {}
	var xy := signed_literal(start + 0x1e, 5)
	var z := literal(start + 0x52, 5)
	var scatter := []
	var low := signed_literal(start + 0x33e, 3)
	for offset in [0x2fa, 0x318, 0x330]:
		scatter.append([low, low + literal(start + offset, 1) - 1])
	if signed_literal(start + 0x34e, 5) != low or immediate_at(start + 0x7c, 2) != 3:
		fail("Unsupported interception placement dimensions.")
		return {}
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var base_count := u16(start + 0x248) & 255
	if u16(start + 0x374) != (0x3300 | (base_count * 4)):
		fail("Interception guardian array does not follow its target prefix.")
		return {}
	var moving := symbol_address("__ZN17PlayerFixedObject9setMovingEb")
	var update := symbol_address("__ZN17PlayerFixedObject6updateEi")
	if (
		u16(moving) != 0x2370
		or u16(moving + 2) != 0x54c1
		or u16(update + 0x1a) != 0x2370
		or u16(update + 0x1e) != 0x2b00
		or u16(update + 0x20) != 0xd051
	):
		fail("Unsupported interception stopped-body movement flag.")
		return {}
	var result := {
		"family": "intercept",
		"types": types,
		"route_bounds":
		[
			[xy, xy + literal(start + 0x1c, 1) - 1],
			[xy, xy + literal(start + 0x3e, 1) - 1],
			[z, z + literal(start + 0x48, 1) - 1]
		],
		"target_counts": [base_count, base_count + immediate_at(start + 0x1bc, 1) - 1],
		"scatter": scatter,
		"wake_half_width": fixed_activation(),
		"count_base": u16(start + 0x25c) & 255,
		"count_divisor": literal_float(start + 0x266, 1),
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"fleets":
		[
			{
				"race": u16(start + 0x20a) & 255,
				"cargo_actor": matching_actor,
				"attacker_actor": immediate_at(start + 0x210, 0),
				"collisions": [body.cargo]
			},
			{
				"race": -1,
				"cargo_actor": other_actor,
				"attacker_actor": immediate_at(start + 0x21a, 2),
				"collisions": [other]
			}
		],
		"wingman_chance": [(u16(start + 0xac) & 255) + 1, immediate_at(start + 0xa0, 1)],
		"scenery_choices": immediate_at(start + 0xc2, 1),
		"asteroid_choice": u16(start + 0xc8) & 255,
		"fog_choice": u16(start + 0xcc) & 255,
		"field":
		asteroid_field_definition(immediate_at(start + 0xf0, 1), immediate_at(start + 0xde, 1)),
		"fog": fog_presentation(),
		"success_kind": "enemy_prefix_destroyed"
	}
	return result if error.is_empty() else {}


func freelance_turret_data(parent: int, count: int) -> Dictionary:
	var mounts := turret_mounts(parent, count)
	if mounts.is_empty():
		return {}
	var factory := symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
	for pair in [
		[0x96, "__ZN6Status10getStationEv"],
		[0x9a, "__ZN7Station11getQuadrantEv"],
		[0xa4, "__ZN6Status8getLevelEv"]
	]:
		if call_target(factory + pair[0]) != symbol_address(pair[1]):
			fail("Unsupported freelance turret health input.")
			return {}
	for pair in [[0xae, 0x435a], [0xb2, 0x1818], [0xb4, 0x1810], [0xb6, 0x1809], [0xb8, 0x910e]]:
		if u16(factory + pair[0]) != pair[1]:
			fail("Unsupported freelance turret health formula.")
			return {}
	var shift := u16(factory + 0xb0)
	if shift & 0xf83f != 3:
		fail("Unsupported freelance turret rank coefficient.")
		return {}
	var mesh_ids := named_array(TABLES.actor_meshes)
	var resources := resource_bindings()
	if mounts.actor < 0 or mounts.actor >= mesh_ids.size() or resources.is_empty():
		return {}
	var ordinary := immediate_at(factory + 80, 3)
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var gun: Dictionary = (
		combat.weapon if mounts.actor == ordinary else alien_turret_weapon(mounts.actor)
	)
	mounts["hull_base"] = campaign_turret_hull(mounts.actor)
	mounts["rank_factor"] = (1 << ((shift >> 6) & 31)) + 1
	mounts["render_mesh"] = resources.has(str(int(mesh_ids[int(mounts.actor)])))
	mounts["tracking"] = turret_tracking()
	mounts["weapon"] = gun
	return mounts if error.is_empty() and not gun.is_empty() else {}


func alien_turret_weapon(actor: int) -> Dictionary:
	var assign := symbol_address("__ZN5Level10assignGunsEv")
	var gun := 0
	var constructors := calls_between(
		assign, symbol_end(assign), "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"
	)
	for candidate in constructors:
		if u16(candidate + 16) == 0x2288 and u16(candidate + 18) == 0x2588:
			if gun != 0:
				fail("Ambiguous alien turret weapon declaration.")
				return {}
			gun = candidate
	if gun == 0 or u16(gun - 122) != (0x2800 | actor):
		fail("Unsupported alien turret weapon association.")
		return {}
	var arithmetic := imported_symbols()
	for pair in [
		[-108, "___floatsisfvfp"],
		[-90, "___subsf3vfp"],
		[-82, "___mulsf3vfp"],
		[-74, "___addsf3vfp"],
		[-70, "___fixsfsivfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(gun + pair[0])):
			fail("Unsupported alien turret damage formula.")
			return {}
	for pair in [
		[-116, 0x9849],
		[-86, 0x1c01],
		[-78, 0x1c01],
		[-66, 0x2300],
		[-56, 0x937b],
		[-54, 0x937c],
		[-52, 0x937d],
		[-26, 0x9101],
		[-24, 0x9300],
		[-2, 0x9922],
		[16, 0x2288],
		[20, 0x508b],
		[54, 0x2200],
		[70, 0x2300],
		[78, 0x9300]
	]:
		if u16(gun + pair[0]) != pair[1]:
			fail("Unsupported alien turret weapon consumer.")
			return {}
	if (
		u16(gun - 110) & 0xff00 != 0x3000
		or call_target(gun + 60) != symbol_address("__ZN8KIPlayer6addGunEP3Guni")
		or call_target(gun + 86) != symbol_address("__ZN9ObjectGunC1EiP3Gunij")
	):
		fail("Unsupported alien turret gun and projectile binding.")
		return {}
	var combat := interceptor_combat()
	if combat.is_empty():
		return {}
	var result: Dictionary = combat.weapon.duplicate(true)
	var factor := (
		1 + literal_float(symbol_address("__ZN7GlobalsC2Ev") + 64, 0) - literal_float(gun - 102, 1)
	)
	result.damage_rule.base = u16(gun - 110) & 255
	result.damage_rule.minimum = 0
	result.damage_rule.factor = factor
	var rank := immediate_at(symbol_address("__ZN6StatusC2Ev") + 16, 4)
	result.damage = int(
		(result.damage_rule.base + rank / int(result.damage_rule.level_divisor)) * factor
	)
	result.interval = shifted_at(gun - 34, gun - 28, 3) / 1000.0
	result.lifetime = result.interval
	result.speed = immediate_at(gun - 30, 1) * 20.0
	result.merge(shared_gun_pool(immediate_at(gun - 8, 2), immediate_at(gun + 16, 2)), true)
	result.erase("pool_id")
	result["projectile_model"] = literal(gun + 84, 3)
	return result if error.is_empty() else {}


func contract_capture() -> Dictionary:
	var level := symbol_address("__ZN5Level13createMissionEv")
	var switches := calls_between(level, level + 1400, "___switch32")
	if switches.size() != 1:
		fail("Missing capture contract dispatch.")
		return {}
	var table: int = switches[0] + 4
	if u32(table) < 1 or u32(table) > 64:
		fail("Invalid capture contract dispatch.")
		return {}
	var start := 0
	var types := []
	for index in u32(table):
		var candidate := table + u32(table + 4 + index * 4)
		if (
			call_target(candidate + 0xcc) == symbol_address("__ZN5RouteC1EPii")
			and (
				call_target(candidate + 0x322)
				== symbol_address("__ZN5Level12createTurretEP8KIPlayerbi")
			)
		):
			if start != 0 and start != candidate:
				fail("Ambiguous capture contract declarations.")
				return {}
			start = candidate
			types.append(index)
	if start < level or start + 0x408 >= symbol_end(level) or types.size() != 1:
		fail("Unsupported capture contract boundary.")
		return {}
	var links := {
		0x42: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x5c: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x6c: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x82: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x92: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xa4: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0xcc: "__ZN5RouteC1EPii",
		0xf6: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x100: "__ZN5Level13createWingmanEv",
		0x112: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x130: "__ZN5Route11getWaypointEi",
		0x14c: "__ZN13AsteroidFieldC1EiP8Waypoint",
		0x1ac: "__ZN5Route11getWaypointEi",
		0x1c6: "__ZN3FogC1EP8Waypoint",
		0x1ee: "__ZN6Status10getMissionEv",
		0x1fc: "__ZN6Status10getStationEv",
		0x200: "__ZN7Station11getQuadrantEv",
		0x208: "__ZN7Mission21getRelativeDifficultyEi",
		0x212: "__ZN6Status10getStationEv",
		0x216: "__ZN7Station11getQuadrantEv",
		0x268: "__ZN6Status10getMissionEv",
		0x26c: "__ZN7Mission13getClientRaceEv",
		0x292: "__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E",
		0x2be: "__ZN5Route11getWaypointEi",
		0x2d0: "__ZN5Level10createShipEiiibP8Waypoint",
		0x2e8: "__ZN8KIPlayer9setActiveEb",
		0x322: "__ZN5Level12createTurretEP8KIPlayerbi",
		0x332: "__ZN8KIPlayer10setToSleepEv",
		0x382: "__ZN11AbyssEngine8AERandom7nextIntEi",
		0x38e: "__ZN5Route11getWaypointEi",
		0x3a0: "__ZN5Level10createShipEiiibP8Waypoint",
		0x3b0: "__ZN8KIPlayer10setToSleepEv",
		0x3f6: "__ZN9ObjectiveC1EiiP5Level"
	}
	for offset in links:
		if call_target(start + offset) != symbol_address(links[offset]):
			fail("Unsupported capture contract source binding.")
			return {}
	var arithmetic := imported_symbols()
	for pair in [
		[0x220, "___floatsisfvfp"],
		[0x226, "___divsf3vfp"],
		[0x22c, "___addsf3vfp"],
		[0x230, "___fixsfsivfp"]
	]:
		if not arithmetic.get(pair[1], []).has(call_target(start + pair[0])):
			fail("Unsupported capture defender-count arithmetic.")
			return {}
	for pair in [
		[0x52, 0x1840],
		[0x54, 0x6010],
		[0x60, 0x1900],
		[0x62, 0x6028],
		[0x7a, 0x1880],
		[0x7c, 0x6018],
		[0x8a, 0x1940],
		[0x8c, 0x6008],
		[0x9e, 0x1940],
		[0xa0, 0x6010],
		[0xb2, 0x18c0],
		[0xb4, 0x6020],
		[0xdc, 0x229c],
		[0xe0, 0x508b],
		[0xfc, 0xdc02],
		[0x118, 0xd002],
		[0x11c, 0xd15d],
		[0x22a, 0x1c01],
		[0x236, 0x1820],
		[0x238, 0x90d0],
		[0x25a, 0x65d9],
		[0x272, 0x4050],
		[0x274, 0x4243],
		[0x276, 0x4318],
		[0x278, 0x0fc0],
		[0x27a, 0x90d1],
		[0x27c, 0x2800],
		[0x27e, 0xd104],
		[0x28c, 0x98d0],
		[0x29c, 0x3b01],
		[0x2a4, 0x9078],
		[0x2aa, 0x91d2],
		[0x2c2, 0x2301],
		[0x2c4, 0x9300],
		[0x2c6, 0x2100],
		[0x2c8, 0x2201],
		[0x2ca, 0x9b78],
		[0x2cc, 0x9001],
		[0x2d6, 0x2100],
		[0x2e2, 0x3b01],
		[0x2ee, 0x22d0],
		[0x2f2, 0x3301],
		[0x2f4, 0x508b],
		[0x310, 0x3b01],
		[0x31c, 0x9bd3],
		[0x31e, 0x2201],
		[0x33c, 0x98d2],
		[0x340, 0x3801],
		[0x342, 0x90d4],
		[0x344, 0x4281],
		[0x346, 0xdbd9],
		[0x352, 0x6010],
		[0x392, 0x2301],
		[0x394, 0x2100],
		[0x396, 0x9300],
		[0x398, 0x2200],
		[0x39a, 0x9bd1],
		[0x39c, 0x9001],
		[0x3ca, 0x3b01],
		[0x3cc, 0x429c],
		[0x3ce, 0xdbc3],
		[0x3f2, 0x681a],
		[0x406, 0x6145]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported capture declaration consumer.")
			return {}
	var other := call_target(start + 0x280)
	if (
		other < level
		or other + 0x28 >= symbol_end(level)
		or (
			call_target(other + 0xc)
			!= symbol_address("__Z14ArraySetLengthIP8KIPlayerEvjR5ArrayIT_E")
		)
		or call_target(other + 0x24) != start + 0x2ac
	):
		fail("Unsupported capture faction branch.")
		return {}
	var first_total := immediate_at(other + 6, 5)
	var second_total := immediate_at(start + 0x2a2, 1)
	if (
		u16(other + 10) != (0x3000 | first_total)
		or u16(start + 0x290) != (0x3000 | second_total)
		or first_total < 2
		or second_total < 2
	):
		fail("Capture turret arrays do not match their faction totals.")
		return {}
	for pair in [
		[0x10, 0x9b3f],
		[0x12, 0x6dd9],
		[0x14, 0x680b],
		[0x16, 0x3b01],
		[0x18, 0x009a],
		[0x1a, 0x684b],
		[0x1c, 0x9478]
	]:
		if u16(other + pair[0]) != pair[1]:
			fail("Unsupported capture capital array placement.")
			return {}
	if literal(start + 0x348, 2) != literal(start + 0x3ec, 3):
		fail("Capture objective does not use the turret prefix.")
		return {}
	var achieved := symbol_address("__ZN9Objective8achievedEi")
	var choices := calls_between(achieved, symbol_end(achieved), "___switch8")
	if choices.size() != 1:
		return {}
	var branches := contract_choice_targets(choices[0], achieved)
	var kind := immediate_at(start + 0x3e2, 1)
	if (
		kind < 0
		or kind >= branches.size()
		or call_target(branches[kind] + 2) != symbol_address("__ZN5Level10getEnemiesEv")
		or call_target(branches[kind] + 22) != symbol_address("__ZN8KIPlayer6isDeadEv")
		or u16(branches[kind] + 36) != 0x429c
	):
		fail("Unsupported capture turret completion rule.")
		return {}
	var routes := []
	for row in [
		[[0x46, 1, 0x30], [0x32, 4, 0x58], [0x70, 2, 0x6a]],
		[[0x66, 5, 0x78], [0x66, 5, 0x90], [0xaa, 3, 0x9c]]
	]:
		var point := []
		for axis in row:
			var low := signed_literal(start + axis[0], axis[1])
			point.append([low, low + literal(start + axis[2], 1) - 1])
		routes.append(point)
	if (
		immediate_at(start + 0xc4, 2) != routes.size() * 3
		or immediate_at(start + 0x380, 1) != routes.size()
	):
		fail("Unsupported capture route dimensions.")
		return {}
	var parents := [immediate_at(other + 4, 4), immediate_at(start + 0x298, 0)]
	var fleets := []
	var values := [first_total, second_total]
	var matching_race := immediate_at(start + 0x270, 2)
	var bodies := capital_collision()
	for index in parents.size():
		var mounts := freelance_turret_data(parents[index], values[index] - 1)
		if mounts.is_empty() or bodies.is_empty():
			return {}
		fleets.append(
			{
				"race": matching_race if index == 0 else -1,
				"capital_actor": parents[index],
				"attacker_actor": index,
				"turrets": mounts,
				"collisions": bodies.duplicate(true)
			}
		)
	# EOR / nonzero normalization above yields the source fighter type0 or1.
	var relative := symbol_address("__ZN7Mission21getRelativeDifficultyEi")
	var result := {
		"family": "capture",
		"types": types,
		"route_bounds": routes,
		"relative_divisors":
		int_array(literal(relative + 4, 3), named_array(TABLES.quadrant_difficulty).size()),
		"count_base": u16(start + 0x21a) & 255,
		"count_divisor": literal_float(start + 0x224, 1),
		"capital_waypoint": immediate_at(start + 0x2b2, 1),
		"fleets": fleets,
		"wingman_chance": [(u16(start + 0xfa) & 255) + 1, immediate_at(start + 0xec, 1)],
		"scenery_choices": immediate_at(start + 0x10e, 1),
		"asteroid_choice": u16(start + 0x116) & 255,
		"fog_choice": u16(start + 0x11a) & 255,
		"field":
		asteroid_field_definition(immediate_at(start + 0x142, 1), immediate_at(start + 0x12e, 1)),
		"fog": fog_presentation(),
		"success_kind": "enemy_prefix_destroyed"
	}
	return result if error.is_empty() else {}


func loot_rules() -> Dictionary:
	var cargo := symbol_address("__ZN9Generator18getRandomCargoItemEv")
	var generate := symbol_address("__ZN9Generator11getLootListEb")
	var window := symbol_address("__ZN10LootWindow10initializeEi")
	var success := symbol_address("__ZN5MGame12successCheckEv")
	var reset := symbol_address("__ZN5MGame5resetEv")
	var draw := symbol_address("__ZN10LootWindow4drawEb")
	for address in [cargo, generate, window, success, reset, draw]:
		if address == 0:
			fail("Missing recovery declarations.")
			return {}
	for link in [
		[cargo, 0x10, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[cargo, 0x28, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[cargo, 0x34, "__ZN9Equipment11getMaxPriceEv"],
		[cargo, 0x3e, "__ZN9Equipment13makeEquipmentEii"],
		[generate, 0x50, "__ZN4Ship10getMaxLoadEv"],
		[generate, 0x5e, "__ZN4Ship14getCurrentLoadEv"],
		[generate, 0xa8, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[generate, 0xda, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[generate, 0xe8, "__ZN11AbyssEngine6AEMath3MinEii"],
		[generate, 0x128, "__ZN9Generator18getRandomCargoItemEv"],
		[generate, 0x14a, "__ZN9Equipment6equalsEPS_"],
		[generate, 0x19e, "__ZN9Equipment9getAmountEv"],
		[generate, 0x1b0, "__ZN9Equipment12changeAmountEi"],
		[window, 0x9a, "__ZN9Generator11getLootListEb"],
		[window, 0xbc, "__ZN4Ship8addCargoEP5ArrayIP9EquipmentE"],
		[window, 0x10a, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[window, 0x168, "__ZN8GameText7getTextEi"],
		[window, 0x1c4, "__ZN9Generator9cargoFullEv"],
		[window, 0x1d6, "__ZN8GameText7getTextEi"],
		[window, 0x216, "__ZN8GameText7getTextEi"],
		[success, 0x9a, "__ZN5Radio16lastMessageShownEv"],
		[success, 0xbc, "__ZN7Mission22isInstantActionMissionEv"],
		[success, 0xd6, "__ZN7Mission8getLevelEv"],
		[success, 0xe0, "__ZN5Level32getEnemiesKilledInCurrentMissionEv"],
		[success, 0x120, "__ZN10LootWindowC1Ei"],
		[reset, 0x136, "__ZN7Mission7getTypeEv"],
		[draw, 0x86, "__ZN8GameText7getTextEi"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported recovery declaration consumer at %x." % (link[0] + link[1]))
			return {}
	# Equality uses the catalogue index field, not quantity or price.
	var equal := symbol_address("__ZN9Equipment6equalsEPS_")
	var index := symbol_address("__ZN9Equipment8getIndexEv")
	if u16(equal + 8) != 0x6840 or u16(equal + 10) != 0x6849 or u16(index) != 0x6840:
		fail("Unsupported recovery item identity.")
		return {}
	for pair in [
		[cargo, 0x38, 0x1c69],
		[generate, 0x3e, 0x7119],
		[generate, 0x64, 0x1a08],
		[generate, 0x68, 0x2800],
		[generate, 0x6e, 0x2301],
		[generate, 0x70, 0x2100],
		[generate, 0x72, 0x7113],
		[generate, 0xae, 0x1c01],
		[generate, 0xb0, 0x2a00],
		[generate, 0xcc, 0x2800],
		[generate, 0xce, 0xd107],
		[generate, 0xde, 0x1c41],
		[generate, 0x150, 0xd009],
		[generate, 0x164, 0xe7dc],
		[generate, 0x1b6, 0x3b01],
		[generate, 0x1c8, 0x2300],
		[generate, 0x1d0, 0x4291],
		[window, 0x80, 0x2802],
		[reset, 0x13c, 0x4058],
		[reset, 0x13e, 0x1e43],
		[reset, 0x140, 0x4383],
		[reset, 0x142, 0x0fd8],
		[reset, 0x146, 0x54e0],
		[success, 0xe4, 0x17c3],
		[success, 0xe6, 0x1a18],
		[success, 0xe8, 0x0fc0],
		[success, 0xf0, 0x5cc3],
		[success, 0xf2, 0x2b00],
		[success, 0xfa, 0xd802],
		[success, 0xfc, 0x2202],
		[success, 0x108, 0x2001]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported recovery rule at %x." % (pair[0] + pair[1]))
			return {}
	if immediate_at(reset + 0x144, 3) != immediate_at(success + 0xee, 3):
		fail("Recovery exclusion does not use the campaign flag.")
		return {}
	var first := u16(cargo + 0x1c) & 255
	if u16(cargo + 0x1c) & 0xff00 != 0x3000:
		fail("Unsupported recovery catalogue range.")
		return {}
	var items := []
	for item in immediate_at(cargo + 0xa, 1):
		items.append(first + item)
	var icons := {}
	var icon_base := shifted_at(window + 0xfa, window + 0xfc, 2)
	for item in items:
		icons[str(item)] = recovery_image_binding(icon_base + item)
	var result := {
		"items": items,
		"quantities": [u16(cargo + 0x38) & 7, immediate_at(cargo + 0x16, 1)],
		"entry_choices": immediate_at(generate + 0xa6, 1),
		"guaranteed_entries": [u16(generate + 0xde) & 7, immediate_at(generate + 0xd6, 1)],
		"minimum_quantity": u16(generate + 0x1a2) & 255,
		"campaign_type": immediate_at(reset + 0x13a, 3),
		"campaign_excluded_through": u16(success + 0xf8) & 255,
		"campaign_guaranteed": u16(success + 0x104) & 255,
		"images":
		{
			"row_measure": ui_region_binding(shifted_at(window + 0x3a, window + 0x4e, 1)),
			"empty": ui_region_binding(shifted_at(window + 0x1b2, window + 0x1b6, 1)),
			"items": icons
		},
		"layout":
		{
			"row_gap": u16(window + 0x280) & 255,
			"row_height_padding": u16(window + 0x7a) & 255,
			"width_padding": u16(window + 0x288) & 255,
			"title_y": u16(draw + 0xe2) & 255,
			"row_x": u16(draw + 0x1b2) & 255,
			"text_y": u16(draw + 0x276) & 255,
			"icon_right": u16(draw + 0x366) & 255,
			"quantity_column": embedded_string(literal(draw + 0x132, 1)),
			"quantity_suffix": embedded_string(literal(draw + 0x254, 1)),
			"fill":
			[
				immediate_at(draw + 0x18a, 1),
				immediate_at(draw + 0x18c, 2),
				immediate_at(draw + 0x18e, 3),
				immediate_at(draw + 0x182, 3)
			],
			"border":
			[
				immediate_at(draw + 0x1d2, 1),
				immediate_at(draw + 0x1d4, 2),
				immediate_at(draw + 0x1d6, 3),
				immediate_at(draw + 0x1ca, 3)
			]
		},
		"labels":
		{
			"title": shifted_at(draw + 0x7c, draw + 0x7e, 1),
			"recovered": literal(window + 0x166, 1),
			"full": shifted_at(window + 0x1ce, window + 0x1d0, 1),
			"empty": literal(window + 0x20e, 1)
		}
	}
	return result if error.is_empty() else {}


func recovery_image_binding(resource: int) -> Dictionary:
	# One cargo icon record straddles a literal pool. Recover its declared
	# atlas fields on either side of the guarded skip, without executing code.
	var registry := symbol_address("__Z17BuildResourceListPN11AbyssEngine6EngineE")
	if resource != shifted_immediate(registry + 0x1b5a, 3):
		return ui_region_binding(resource)
	for pair in [
		[0x1ac0, 0xe044], [0x1b4c, 0x90f1], [0x1b4e, 0x8002], [0x1b54, 0x804b], [0x1b62, 0x8003]
	]:
		if u16(registry + pair[0]) != pair[1]:
			fail("Unsupported recovery icon split record.")
			return {}
	return {
		"texture": immediate_at(registry + 0x1abc, 2), "region": immediate_at(registry + 0x1abe, 3)
	}


func survival_table(at: int, register: int, name: String) -> Array:
	if literal(at, register) != symbol_address(name):
		fail("Unsupported survival table consumer: " + name)
		return []
	return named_array(name)


func survival_rules() -> Dictionary:
	var update := symbol_address("__ZN5Level6updateEij")
	var spawn := symbol_address("__ZN5Level15spawnNewEnemiesEv")
	var upgrade := symbol_address("__ZN5Level21checkForWeaponUpgradeEv")
	var death := symbol_address("__ZN5Level9enemyDiedEi")
	var factory := symbol_address("__ZN5Level13createMissionEv")
	var guns := symbol_address("__ZN5Level10assignGunsEv")
	var switches := calls_between(factory, factory + 1400, "___switch32")
	if switches.size() != 1:
		fail("Missing survival mission dispatch.")
		return {}
	var kind := u16(update + 0x92) & 255
	var table: int = switches[0] + 4
	if kind < 0 or kind > u32(table) or kind != public_survival_type():
		fail("Invalid survival mission index.")
		return {}
	var start := table + u32(table + 4 + kind * 4)
	# Bounded recognizers of rules and their data consumers, never an interpreter.
	for pair in [
		[update, 0x94, 0xd136],
		[update, 0xce, 0x428a],
		[update, 0xd0, 0xd918],
		[update, 0xec, 0x428a],
		[update, 0xee, 0xd909],
		[spawn, 0x28, 0xdd02],
		[spawn, 0x2c, 0x3301],
		[spawn, 0x74, 0xd300],
		[spawn, 0xe2, 0x4353],
		[spawn, 0xe8, 0x189e],
		[spawn, 0x154, 0x3801],
		[upgrade, 0x28, 0xdb54],
		[upgrade, 0xd0, 0x3301],
		[death, 0x1a, 0xdd34],
		[death, 0x22, 0xdc01],
		[death, 0x2a, 0xdc01],
		[death, 0x3c, 0x2900],
		[death, 0x3e, 0xdc04],
		[death, 0x54, 0xdc0a],
		[death, 0x5a, 0x1c4e],
		[death, 0x5c, 0x1069],
		[death, 0x60, 0x4371],
		[death, 0x62, 0x18eb],
		[death, 0x64, 0x1859],
		[start, 0xbc, 0x4053],
		[start, 0xbe, 0x1e5a],
		[start, 0xc0, 0x439a],
		[start, 0x1d0, 0x50e2],
		[start, 0x222, 0x2200],
		[start, 0x220, 0xd202]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported survival operation at %x." % (pair[0] + pair[1]))
			return {}
	for link in [
		[update, 0xd4, "__ZN5Level21checkForWeaponUpgradeEv"],
		[update, 0xf2, "__ZN5Level15spawnNewEnemiesEv"],
		[spawn, 0x7a, "__ZN13PlayerFighter6reviveEv"],
		[spawn, 0x128, "__ZN13PlayerFighter11setPositionEiii"],
		[spawn, 0x1da, "__ZN6Player11replaceGunsEiiiiib"],
		[upgrade, 0x4c, "__ZN6Player11replaceGunsEiiiiib"],
		[death, 0x32, "__ZN6Player8healHullEi"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival rule consumer.")
			return {}
	var ships := {
		"actor": survival_table(spawn + 0x138, 2, "__ZL15WAVE_SHIPS_TYPE"),
		"speed_bits": survival_table(spawn + 0x19e, 3, "__ZL16WAVE_SHIPS_SPEED"),
		"score": survival_table(spawn + 0x1aa, 3, "__ZL20SURVIVAL_SHIPS_SCORE"),
		"hull": survival_table(spawn + 0x1b2, 3, "__ZL17SURVIVAL_SHIPS_HP"),
		"sort": survival_table(spawn + 0x1ba, 3, "__ZL27SURVIVAL_SHIPS_WEAPON_SORTS"),
		"weapon": survival_table(spawn + 0x1bc, 2, "__ZL22SURVIVAL_SHIPS_WEAPONS"),
		"damage": survival_table(spawn + 0x1c4, 3, "__ZL31WAVE_SHIPS_WEAPON_SINGLE_DAMAGE"),
		"projectile_speed": survival_table(spawn + 0x1ca, 3, "__ZL27SURVIVAL_SHIPS_WEAPON_SPEED"),
		"reload_ms": survival_table(spawn + 0x1d0, 4, "__ZL28SURVIVAL_SHIPS_WEAPON_RELOAD"),
		"initial_damage":
		survival_table(guns + 0x23c, 2, "__ZL35SURVIVAL_SHIPS_WEAPON_SINGLE_DAMAGE"),
		"projectile_model": survival_table(guns + 0x236, 2, "__ZL28SURVIVAL_SHIPS_WEAPON_MESHES")
	}
	var speeds := []
	for bits in ships.speed_bits:
		var buffer := PackedByteArray()
		buffer.resize(4)
		buffer.encode_s32(0, int(bits))
		speeds.append(buffer.decode_float(0))
	ships.erase("speed_bits")
	ships["speed"] = speeds
	var upgrades := {
		"score": survival_table(upgrade + 0x1a, 1, "__ZL26SURVIVAL_UPGRADES_AT_SCORE"),
		"sort": survival_table(upgrade + 0x2a, 3, "__ZL23SURVIVAL_UPGRADES_SORTS"),
		"reload_ms": survival_table(upgrade + 0x2c, 5, "__ZL24SURVIVAL_UPGRADES_RELOAD"),
		"damage": survival_table(upgrade + 0x32, 3, "__ZL24SURVIVAL_UPGRADES_DAMAGE"),
		"projectile_speed": survival_table(upgrade + 0x3c, 3, "__ZL24SURVIVAL_UPGRADES_SPEEDS"),
		"weapon": survival_table(upgrade + 0x3e, 5, "__ZL23SURVIVAL_UPGRADES_TYPES"),
		"projectile_model": survival_table(upgrade + 0x74, 6, "__ZL24SURVIVAL_UPGRADES_MESHES")
	}
	var result := {
		"type": kind,
		"ships": ships,
		"upgrades": upgrades,
		"thresholds": survival_table(spawn + 0x1a, 5, "__ZL29SURVIVAL_ENEMY_SPAWN_AT_SCORE"),
		"initial_active": immediate_at(start + 0x1cc, 2),
		"pool_size": immediate_at(start + 0xe4, 0),
		"max_active": (u16(spawn + 0x16) & 255) + 1,
		"sign_choices": immediate_at(spawn + 0x80, 1),
		"positive_sign_through": u16(spawn + 0x8a) & 255,
		"initial_archetype": immediate_at(start + 0x222, 2),
		"tick_ms": shifted_at(update + 0xca, update + 0xcc, 1),
		"combo_ms": literal(death + 0x50, 3),
		"heal_limits": [u16(death + 0x20) & 255, u16(death + 0x28) & 255],
		"heal_amounts":
		[
			immediate_at(death + 0x24, 1),
			immediate_at(death + 0x2c, 1),
			immediate_at(death + 0x30, 1)
		],
		"spawn_factor": literal(spawn + 0xdc, 3),
		"spawn_offset": int_array(((spawn + 0xe4 + 4) & ~3) + (u16(spawn + 0xe4) & 255) * 4, 1)[0],
		"spawn_range": literal(spawn + 0xde, 1),
		"promotion_cap": immediate_at(spawn + 0x152, 1),
		"promotable_count": (u16(spawn + 0x172) & 255) / 4,
		"fixed_actor": u16(spawn + 0x134) & 255
	}
	return result if error.is_empty() else {}


func survival_setup() -> Dictionary:
	var player := symbol_address("__ZN5Level12createPlayerEv")
	var game := symbol_address("__ZN5MGame12OnInitializeEv")
	var space := symbol_address("__ZN5Level11createSpaceEv")
	var initializer := symbol_address("__ZN5Level4initEv")
	var factory := symbol_address("__ZN5Level13createMissionEv")
	var calls := calls_between(factory, factory + 1400, "___switch32")
	if calls.size() != 1:
		fail("Missing survival setup dispatch.")
		return {}
	var kind := u16(game + 0xe8) & 255
	var table: int = calls[0] + 4
	if kind < 0 or kind > u32(table):
		fail("Invalid survival setup mode.")
		return {}
	var start := table + u32(table + 4 + kind * 4)
	for link in [
		[player, 0x9a, "__ZN4Ship8makeShipEv"],
		[player, 0xa2, "__ZN6Status7setShipEP4Ship"],
		[player, 0xe2, "__Z8ArraySetIiEvPKT_jR5ArrayIS0_E"],
		[player, 0xf4, "__ZN4Ship14setWeaponSlotsEP5ArrayIiE"],
		[player, 0x17a, "__ZN9Equipment13makeEquipmentEii"],
		[player, 0x196, "__ZN9Equipment13makeEquipmentEii"],
		[player, 0x1b2, "__ZN9Equipment13makeEquipmentEii"],
		[player, 0x1ba, "__ZN9Equipment9setValue1Ei"],
		[player, 0x1c4, "__ZN9Equipment9setValue2Ei"],
		[player, 0x1ea, "__ZN4Ship12setEquipmentEP5ArrayIP9EquipmentE"],
		[game, 0x138, "__ZN5LevelC1Ei"],
		[space, 0x230, "__ZN11SpaceObjectC1Eij"],
		[space, 0x40, "__ZN6Status10getStationEv"],
		[space, 0x44, "__ZN7Station13getImageIndexEv"],
		[space, 0x26e, "__ZN5Level12createSkyboxEi"],
		[start, 0x1bc, "__ZN5RouteC1EPii"],
		[start, 0x264, "__ZN5Route11getWaypointEi"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival setup consumer at %x." % (link[0] + link[1]))
			return {}
	for pair in [
		[player, 0x78, 0xd902],
		[player, 0xac, 0x3301],
		[player, 0xae, 0x6023],
		[player, 0x168, 0x681b],
		[player, 0x186, 0x68db],
		[player, 0x1a2, 0x69db],
		[player, 0x17e, 0x9905],
		[player, 0x188, 0x1c18],
		[player, 0x288, 0x4a54],
		[player, 0x28c, 0xe00a],
		[start, 0x262, 0x98be],
		[start, 0x22a, 0x425b],
		[start, 0x2a4, 0xda01],
		[start, 0x2be, 0x60d3],
		[initializer, 0x224, 0x2b08],
		[initializer, 0x24e, 0xd100]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported survival setup operation at %x." % (pair[0] + pair[1]))
			return {}
	var slots := survival_table(player + 0xb0, 3, "__ZZN5Level12createPlayerEvE5C.152")
	if slots.size() != immediate_at(player + 0xde, 1):
		fail("Unsupported arcade mount table size.")
		return {}
	var ship_order := named_array("__ZL13BUYABLE_SHIPS")
	# This symbol has multiple identical copies; bind this player's actual copy.
	if not symbols["__ZL13BUYABLE_SHIPS"].has(literal(player + 0x134, 3)):
		fail("Unsupported arcade visual ship order.")
		return {}
	var fighter := symbol_address("__ZN5Level10createShipEiiibP8Waypoint")
	var width := shifted_at(fighter + 0x7c, fighter + 0x7e, 2)
	var lower := signed_literal(fighter + 0x96, 3)
	# Reserved slots use index -1 at the original speed consumer. Recover the
	# actual preceding data word for this supported image instead of giving the
	# dormant fallback ship an invented cruise speed. It is effectively stationary.
	if literal(start + 0x28c, 3) != symbol_address("__ZL16WAVE_SHIPS_SPEED"):
		fail("Unsupported reserved survival speed association.")
		return {}
	var reserved_at := file_offset(literal(start + 0x28c, 3) - 4, 4)
	if reserved_at < 0:
		fail("Missing reserved survival speed data.")
		return {}
	var reserved_speed := bytes.decode_float(reserved_at)
	if not is_finite(reserved_speed) or reserved_speed < 0:
		fail("Unsupported reserved survival speed.")
		return {}
	var result := {
		"type": kind,
		"ship_count": (u16(player + 0x76) & 255) + 1,
		"ship_order": ship_order,
		"slots": slots,
		"equipment":
		[
			(u16(player + 0x168) >> 6) & 31,
			(u16(player + 0x186) >> 6) & 31,
			(u16(player + 0x1a2) >> 6) & 31
		],
		"missile_score_above": survival_missile_unlock(),
		"shield_capacity": immediate_at(player + 0x1b6, 1),
		"shield_interval_ms": shifted_at(player + 0x1be, player + 0x1c0, 1),
		"hull": literal(player + 0x288, 2),
		"scene_mode": immediate_at(game + 0x134, 1),
		"background": survival_background(kind),
		"space_object_type": immediate_at(space + 0x22a, 1),
		"initial_offset": [0, 0, literal(start + 0x132, 5)],
		"scatter":
		[[lower, lower + width - 1], [lower, lower + width - 1], [lower, lower + width - 1]],
		"reserved_hull": immediate_at(start + 0x310, 1),
		"reserved_actor": immediate_at(start + 0x234, 5),
		"reserved_score": immediate_at(start + 0x2a6, 3),
		"reserved_speed": reserved_speed
	}
	return result if error.is_empty() else {}


func survival_background(kind: int) -> String:
	# createSpace passes the station image, but this consumer replaces it for
	# survival before creating any sky layers. Do not stop at the caller's value.
	var sky := symbol_address("__ZN5Level12createSkyboxEib")
	var wrapper := symbol_address("__ZN5Level12createSkyboxEi")
	if (
		call_target(wrapper + 6) != sky
		or call_target(sky + 0x4e) != symbol_address("__ZN7Mission7getTypeEv")
		or u16(sky + 0x52) != (0x2800 | kind)
		or u16(sky + 0x54) != 0xd000
	):
		fail("Unsupported survival sky selection branch.")
		return ""
	for offset in [0x76, 0x84, 0x8e]:
		if call_target(sky + offset) != symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi"):
			fail("Unsupported survival sky random consumer.")
			return ""
	return "random"


func survival_armament() -> Dictionary:
	var assign := symbol_address("__ZN5Level10assignGunsEv")
	var replace := symbol_address("__ZN6Player11replaceGunsEiiiiib")
	var upgrade := symbol_address("__ZN5Level21checkForWeaponUpgradeEv")
	var spawn := symbol_address("__ZN5Level15spawnNewEnemiesEv")
	# Continuous survival constructs every slot with the same initial ObjectGun.
	# Later promotions edit its properties; they do not allocate another Gun or
	# turn it into a RocketGun. Only this bounded, observed layout is supported.
	for pair in [
		[assign, 0x18a, 0x280e],
		[assign, 0x18c, 0xd102],
		[assign, 0x18e, 0x2300],
		[assign, 0x190, 0x934c],
		[assign, 0x1aa, 0x904e],
		[assign, 0x1fc, 0x9567],
		[assign, 0x204, 0x9e4e],
		[assign, 0x206, 0x2e01],
		[assign, 0x21e, 0x008b],
		[assign, 0x224, 0x4351],
		[assign, 0x272, 0xda00],
		[assign, 0x278, 0xdd03],
		[assign, 0x2a0, 0x93a9],
		[assign, 0x2b0, 0x91a8],
		[assign, 0x2b2, 0x92aa],
		[assign, 0x548, 0x9e50],
		[assign, 0x554, 0x9650],
		[assign, 0x558, 0x9066],
		[replace, 0x56, 0xd002],
		[replace, 0x5c, 0xd00b],
		[replace, 0x60, 0x6322],
		[replace, 0x64, 0x6363],
		[replace, 0x68, 0x63a2],
		[replace, 0x70, 0x62a0],
		[replace, 0x74, 0x6223],
		[upgrade, 0x4a, 0x9402],
		[spawn, 0x1d8, 0x9402]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported survival armament operation at %x." % (pair[0] + pair[1]))
			return {}
	for link in [
		[assign, 0x2e0, "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"],
		[assign, 0x316, "__ZN9ObjectGunC1EiP3Gunij"],
		[upgrade, 0x4c, "__ZN6Player11replaceGunsEiiiiib"],
		[spawn, 0x1da, "__ZN6Player11replaceGunsEiiiiib"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival gun factory or promotion consumer.")
			return {}
	var sorts := survival_table(assign + 0x1a4, 2, "__ZL27SURVIVAL_SHIPS_WEAPON_SORTS")
	var initial := immediate_at(assign + 0x18e, 3)
	if (
		initial >= sorts.size()
		or sorts[initial] < 0
		or sorts[initial] > (u16(assign + 0x276) & 255)
	):
		fail("Unsupported initial survival projectile class.")
		return {}
	var count := immediate_at(assign + 0x1a6, 0)
	var lateral_start := u16(assign + 0x220) & 255
	var lateral_step := (u16(assign + 0x550) & 255) << ((u16(assign + 0x21e) >> 6) & 31)
	var forward := immediate_at(assign + 0x290, 2)
	var vertical := immediate_at(assign + 0x29e, 3)
	var single_lateral := immediate_at(assign + 0x20a, 1)
	var mounts := []
	if count < 1 or count > 32:
		fail("Invalid survival gun count.")
		return {}
	for index in count:
		mounts.append(
			[
				(
					single_lateral
					if count == 1
					else (lateral_start + index * lateral_step) * (1 if index % 2 == 0 else -1)
				),
				vertical,
				forward
			]
		)
	var result := {
		"player": survival_player_armament(),
		"mounts": mounts,
		"pool_capacity": immediate_at(assign + 0x2c6, 2),
		"lifetime": literal(assign + 0x2de, 3) / 1000.0,
		"upgrade_excluded_sort": u16(replace + 0x5a) & 255,
		"player_preserves_excluded": immediate_at(upgrade + 0x48, 4) != 0,
		"enemy_preserves_excluded": immediate_at(spawn + 0x1d6, 4) != 0,
		"replacement_models": survival_table(spawn + 0x1f6, 3, "__ZL28SURVIVAL_SHIPS_WEAPON_MESHES")
	}
	return result if error.is_empty() else {}


func survival_scores() -> Dictionary:
	var refresh := symbol_address("__ZN10MenuWindow21refreshHighscoreTableEi")
	var reset := symbol_address("__ZN13RecordHandler14resetHighscoreEi")
	var menu := symbol_address("__ZN10MenuWindow10switchMenuEj")
	var results := symbol_address("__ZN5MGame13gameOverCheckEv")
	var globals := symbol_address(
		"__ZN7Globals4initEPN11AbyssEngine18ApplicationManagerEPNS0_6EngineE"
	)
	for pair in [
		[refresh, 0x7c, 0x4298],
		[menu, 0x124, 0x4290],
		[menu, 0x126, 0xd23f],
		[menu, 0x130, 0x189b],
		[menu, 0x132, 0x600b],
		[refresh, 0x7e, 0xd205],
		[refresh, 0x94, 0xd1e2],
		[refresh, 0x158, 0xd8ae],
		[reset, 0x110, 0x9b06],
		[reset, 0x112, 0x3304],
		[reset, 0x118, 0xd1c3],
		[results, 0x44, 0xdd00],
		[results, 0x5a, 0xdc00]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported survival score ordering or result gate.")
			return {}
	for link in [
		[refresh, 0x72, "__ZN14HighscoreEntry8getScoreEv"],
		[refresh, 0x174, "__ZN14HighscoreEntry8setScoreEj"],
		[reset, 0x90, "__Z14ArraySetLengthIP14HighscoreEntryEvjR5ArrayIT_E"],
		[reset, 0xce, "__ZN14HighscoreEntryC1EN11AbyssEngine6StringEjj"],
		[menu, 0x10a, "__ZN13RecordHandler14readHighscoresEi"],
		[results, 0x9c, "__ZN8GameText7getTextEi"],
		[results, 0xc6, "__ZN8GameText7getTextEi"],
		[results, 0x14a, "__ZN8GameText7getTextEi"],
		[results, 0x1c0, "__ZN8GameText7getTextEi"],
		[results, 0xaa, "__ZN11AbyssEngine6StringC1EPKc"],
		[results, 0xe0, "__ZN11AbyssEngine6StringC1EPKc"],
		[results, 0xfc, "__ZN11AbyssEngine6StringC1EPKc"],
		[results, 0x4e8, "__ZN11AbyssEngine6StringC1EPKc"],
		[results, 0x7cc, "__ZN8GameText7getTextEi"],
		[results, 0x7e0, "__ZN12ChoiceWindow10setCaptionEN11AbyssEngine6StringE"],
		[results, 0x49a, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringEb"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival score/UI consumer.")
			return {}
	var count := immediate_at(reset + 0x86, 0)
	if (
		count < 1
		or count > 32
		or (u16(refresh + 0x92) & 0xff00) != 0x2b00
		or (u16(reset + 0x116) & 0xff00) != 0x2b00
		or (u16(results + 0x58) & 0xff00) != 0x2800
		or (u16(menu + 0x118) & 0xf83f) != 0x6818
		or count != (u16(refresh + 0x92) & 255)
		or count * 4 != (u16(reset + 0x116) & 255)
		or count - 1 != immediate_at(refresh + 0xa2, 1)
		or count - 1 != ((u16(menu + 0x118) >> 6) & 31)
	):
		fail("Conflicting survival highscore table sizes.")
		return {}
	if (
		u32(literal(menu + 0x128, 3)) != symbol_address("__ZN7Globals19instantActionPointsE")
		or literal(globals + 0x252, 3) != symbol_address("__ZN7Globals19instantActionPointsE")
	):
		fail("Unsupported survival points binding.")
		return {}
	return (
		{
			"type": immediate_at(menu + 0x108, 1),
			"count": count,
			"initial_name": embedded_string(literal(reset + 0xa4, 1)),
			"initial_score": immediate_at(reset + 0xcc, 3),
			"initial_wave": immediate_at(reset + 0xca, 2),
			"points_initial": immediate_at(globals + 0x23c, 2),
			"points_qualified_only": true,
			"ties": "after",
			"minimum_result_score": (u16(results + 0x58) & 255) + 1,
			"format":
			{
				"paragraph": embedded_string(literal(results + 0xa0, 2)),
				"label_suffix": embedded_string(literal(results + 0xd4, 0)),
				"value_break": embedded_string(literal(results + 0xf2, 1)),
				"zero_suffix": embedded_string(literal(results + 0x4e2, 1))
			},
			"labels":
			{
				"defeat": shifted_at(results + 0x92, results + 0x94, 1),
				"kills": immediate_at(results + 0xbe, 1),
				"time": immediate_at(results + 0x142, 1),
				"score": shifted_at(results + 0x1ba, results + 0x1bc, 1),
				"main_menu": literal(results + 0x7c4, 1)
			}
		}
		if error.is_empty()
		else {}
	)


func choice_presentation() -> Dictionary:
	var ctor := symbol_address("__ZN12ChoiceWindowC2Ev")
	var set_body := symbol_address("__ZN12ChoiceWindow3setERKN11AbyssEngine6StringEb")
	var draw := symbol_address("__ZN12ChoiceWindow4drawEj")
	for offset in [0x28, 0x34, 0x40, 0x4c, 0x58, 0x64]:
		if (
			call_target(ctor + offset)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		):
			fail("Unsupported choice window image consumer.")
			return {}
	for link in [
		[set_body, 0xca, "__ZN11AbyssEngine11PaintCanvas15GetImage2DWidthEj"],
		[set_body, 0xde, "__ZN7Globals12getLineArrayEjRKN11AbyssEngine6StringEiP5ArrayIPS1_E"],
		[set_body, 0x118, "__ZN11AbyssEngine11PaintCanvas13GetTextHeightEj"],
		[draw, 0x102, "__ZN7Globals9drawLinesEjP5ArrayIPN11AbyssEngine6StringEEiib"],
		[draw, 0x2ac, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjii"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported choice window layout consumer.")
			return {}
	for pair in [
		[ctor, 0x84, 0x1a30],
		[ctor, 0x86, 0x1040],
		[set_body, 0xf2, 0xd91a],
		[set_body, 0x124, 0x4343],
		[set_body, 0x126, 0x1acb],
		[set_body, 0x154, 0x3301],
		[draw, 0xc6, 0xdae3]
	]:
		# Guard geometry operations; numeric dimensions are read separately.
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported choice window geometry operation at %x." % (pair[0] + pair[1]))
			return {}
	var images := {"cap": ui_region_binding(shifted_at(ctor + 0x1e, ctor + 0x20, 1))}
	var bindings := {"body": 0x32, "middle": 0x3e, "bottom": 0x4a, "selected": 0x56, "idle": 0x62}
	for key in bindings:
		images[key] = ui_region_binding(literal(ctor + bindings[key], 1))
	var base_y := immediate_at(set_body + 0xe4, 2)
	var max_lines := u16(set_body + 0xf0) & 255
	if (
		base_y != immediate_at(set_body + 0x120, 1)
		or max_lines != (u16(set_body + 0x122) & 255)
		or (u16(set_body + 0xda) & 0xff00) != 0x3b00
		or (u16(set_body + 0xf0) & 0xff00) != 0x2b00
		or (u16(set_body + 0x122) & 0xff00) != 0x3b00
		or (u16(draw + 0x292) & 0xff00) != 0x3200
		or (u16(draw + 0x308) & 0xff00) != 0x3200
	):
		fail("Conflicting choice window measurements.")
		return {}
	return (
		{
			"images": images,
			"layout":
			{
				"base_y": base_y,
				"short_lines": max_lines,
				"text_padding": u16(set_body + 0xda) & 255,
				"extra_rows": u16(set_body + 0x154) & 255,
				"button_x": u16(draw + 0x292) & 255,
				"button_text_y": u16(draw + 0x308) & 255
			},
			"default_caption": embedded_string(literal(draw + 0x2ca, 1))
		}
		if error.is_empty()
		else {}
	)


func survival_menu() -> Dictionary:
	var menu := symbol_address("__ZN10MenuWindow10switchMenuEj")
	var draw := symbol_address("__ZN10MenuWindow4drawEb")
	var name_limit := symbol_address(
		"-[AppController textField:shouldChangeCharactersInRange:replacementString:]"
	)
	for link in [
		[menu, 0x26c, "__ZN13EquipmentListC1EiiiiiiiihPiPbb"],
		[menu, 0x2d0, "__ZN8GameText7getTextEi"],
		[menu, 0x318, "__ZN8GameText7getTextEi"],
		[menu, 0x3f8, "__ZN8GameText7getTextEi"],
		[draw, 0xed0, "__ZN11AbyssEngine11PaintCanvas10DrawStringEjRKNS_6StringEiib"],
		[draw, 0x11a8, "__ZN14HighscoreEntry7getNameEv"],
		[draw, 0x11de, "__ZN14HighscoreEntry8getScoreEv"],
		[draw, 0x124a, "__ZN11AbyssEngine11PaintCanvas13GetTextHeightEj"],
		[draw, 0xbee, "__ZN8GameText7getTextEi"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival menu or highscore consumer at %x." % (link[0] + link[1]))
			return {}
	for pair in [
		[menu, 0x1ea, 0x2810],
		[draw, 0xe88, 0x0040],
		[draw, 0xe9c, 0x1a18],
		[draw, 0xf5a, 0x0040],
		[draw, 0xb74, 0x0040],
		[draw, 0xbb2, 0x0040],
		[draw, 0x1268, 0x429c],
		[draw, 0x126a, 0xd200],
		[name_limit, 0xa, 0xd900]
	]:
		if u16(pair[0] + pair[1]) != pair[2]:
			fail("Unsupported survival menu layout operation at %x." % (pair[0] + pair[1]))
			return {}
	if (u16(name_limit + 8) & 0xff00) != 0x2900:
		fail("Unsupported pilot name input bound.")
		return {}
	var info := literal(menu + 0x208, 3)
	var result := {
		"tabs": [info, info + (u16(menu + 0x20e) & 255)],
		"presentation": survival_menu_art(),
		"title": literal(menu + 0x2ca, 1),
		"description": literal(menu + 0x310, 1),
		"strengths": literal(menu + 0x3f0, 1),
		"legend":
		[
			{
				"text": literal(menu + 0x4d6, 1),
				"image": ui_region_binding(literal(menu + 0x4a6, 1))
			},
			{
				"text": shifted_at(menu + 0x534, menu + 0x53e, 1),
				"image": ui_region_binding(literal(menu + 0x4be, 1))
			},
			{"text": literal(menu + 0x592, 1), "image": ui_region_binding(literal(menu + 0x4c6, 1))}
		],
		"picture": ui_region_binding(literal(menu + 0x2c2, 1)),
		"frame":
		[
			immediate_at(menu + 0x23c, 3),
			immediate_at(menu + 0x240, 3),
			shifted_at(menu + 0x244, menu + 0x246, 3),
			shifted_at(menu + 0x24a, menu + 0x24c, 3)
		],
		"content_origin": [immediate_at(menu + 0x258, 1), immediate_at(menu + 0x266, 2)],
		"text_width": immediate_at(menu + 0x416, 3),
		"content_height": immediate_at(menu + 0x238, 3),
		"back": immediate_at(menu + 0x1c2, 1),
		"start": immediate_at(menu + 0x1c4, 2),
		"table":
		{
			"rank": literal(draw + 0xebc, 1),
			"name": immediate_at(draw + 0xee8, 1),
			"score": shifted_at(draw + 0xf26, draw + 0xf28, 1),
			"columns":
			[
				immediate_at(draw + 0xec8, 3),
				immediate_at(draw + 0xefc, 3),
				literal(draw + 0xf3c, 3)
			],
			"line_end": literal(draw + 0xe62, 3),
			"line_base": u16(draw + 0xe64) & 255,
			"header_height_divisor": immediate_at(draw + 0xe84, 1),
			"header_padding": (u16(draw + 0xe9e) >> 6) & 7,
			"row_gap": u16(draw + 0x1252) & 255,
			"rank_zero": embedded_string(literal(draw + 0xfc4, 1)),
			"highlight":
			[
				immediate_at(draw + 0xf88, 1),
				immediate_at(draw + 0xf7c, 2),
				immediate_at(draw + 0xf8a, 3),
				immediate_at(draw + 0xf74, 3)
			]
		},
		"name_entry":
		{
			"prompt": literal(draw + 0xbe6, 1),
			"limit": (u16(name_limit + 8) & 255) + 1,
			"frame":
			[
				immediate_at(draw + 0xb26, 1),
				immediate_at(draw + 0xb30, 2),
				shifted_at(draw + 0xb20, draw + 0xb22, 3),
				immediate_at(draw + 0xb1e, 2)
			],
			"input": [immediate_at(draw + 0xb7a, 1), immediate_at(draw + 0xb6e, 2)],
			"width": immediate_at(draw + 0xb06, 4) * 2,
			"height_lines": 1 << ((u16(draw + 0xb74) >> 6) & 31),
			"prompt_y": immediate_at(draw + 0xc1e, 2),
			"fill":
			[
				immediate_at(draw + 0xb3a, 1),
				immediate_at(draw + 0xb38, 2),
				immediate_at(draw + 0xb3e, 3),
				immediate_at(draw + 0xb06, 4)
			],
			"border":
			[
				immediate_at(draw + 0xb84, 1),
				immediate_at(draw + 0xb88, 2),
				immediate_at(draw + 0xb8c, 3),
				immediate_at(draw + 0xb82, 3)
			]
		}
	}
	return result if error.is_empty() else {}


func survival_menu_art() -> Dictionary:
	var tab := symbol_address("__ZN10ObjectList10initTabboxEhPiPbiijj")
	var box := symbol_address("__ZN10ObjectList10drawTabboxEb")
	var caption := symbol_address("__ZN10ObjectList13drawTabReiterEiiibbbbjb")
	var equipment := symbol_address("__ZN13EquipmentList10initializeEv")
	var right := symbol_address("__ZN13EquipmentList13drawRightInfoEP8ListItembbib")
	var menu := symbol_address("__ZN10MenuWindow10switchMenuEj")
	var draw := symbol_address("__ZN10MenuWindow4drawEb")
	for link in [
		[tab, 0x38, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[tab, 0x84, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[equipment, 0x37e, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[right, 0x9a, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjii"],
		[right, 0x212, "__ZN11AbyssEngine11PaintCanvas10DrawStringEjRKNS_6StringEiib"],
		[draw, 0xdf0, "__ZN11AbyssEngine11PaintCanvas10DrawStringEjRKNS_6StringEiib"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival menu artwork consumer.")
			return {}
	# The table comparison is strict: a title advances only above its threshold.
	if u16(menu + 0x6b0) != 0x429a or u16(menu + 0x6b2) != 0xd203:
		fail("Unsupported survival rank threshold comparison.")
		return {}
	var count := u16(menu + 0x6be) & 255
	if count < 1 or count > 64:
		fail("Unsupported survival rank table length.")
		return {}
	var ranks := []
	var thresholds := literal(menu + 0x6a8, 3)
	if thresholds != symbol_address("__ZL20SURVIVAL_RANK_POINTS"):
		fail("Unsupported survival rank table binding.")
		return {}
	for index in count:
		ranks.append(
			{"points": u32(thresholds + index * 4), "text": literal(draw + 0xd82, 2) + index}
		)
	var alpha := immediate_at(box + 0xb8, 3)
	return (
		{
			"images":
			{
				"tab_selected": ui_region_binding(literal(tab + 0x82, 1)),
				"tab_idle": ui_region_binding(literal(tab + 0x8e, 1)),
				"corner": ui_region_binding(literal(tab + 0x14, 1)),
				"tab_corner": ui_region_binding(literal(tab + 0x42, 1)),
				"preview": ui_region_binding(literal(equipment + 0x37c, 1)),
				"score_bar": ui_region_binding(literal(equipment + 0x36c, 1)),
				"preview_overlay": ui_region_binding(literal(equipment + 0x388, 1))
			},
			"caption_y": u16(caption + 0x1c0) & 255,
			"fill":
			[
				immediate_at(box + 0x18c, 1),
				immediate_at(box + 0x186, 2),
				immediate_at(box + 0x18a, 3),
				alpha
			],
			"border":
			[
				immediate_at(box + 0x14a, 1),
				immediate_at(box + 0x144, 2),
				immediate_at(box + 0x148, 3),
				alpha
			],
			"right_origin":
			[
				(
					immediate_at(menu + 0x258, 1)
					+ immediate_at(menu + 0x268, 3)
					+ (u16(right + 0x4a) & 255)
				),
				immediate_at(menu + 0x266, 2) + (u16(right + 0x52) & 255)
			],
			"score_gap": u16(right + 0x148) & 255,
			"score_text_offset": [u16(right + 0x204) & 255, u16(right + 0x202) & 255],
			"score_right_padding": u16(right + 0x25c) & 255,
			"highscore": literal(right + 0x1c0, 1),
			"rank_origin": [240 + (u16(draw + 0xde8) & 255), immediate_at(draw + 0xdd4, 2)],
			"picture_center": [literal(draw + 0xe08, 2), immediate_at(draw + 0xe0a, 3)],
			"ranks": ranks
		}
		if error.is_empty()
		else {}
	)


func survival_missile_unlock() -> int:
	var draw := symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var setter := symbol_address("__ZN3Hud16setShipHasRocketEb")
	if (
		call_target(draw + 0xae) != symbol_address("__ZN5Level8getScoreEv")
		or u16(draw + 0xb6) != 0xdd04
		or immediate_at(draw + 0xba, 3) != immediate_at(setter, 3)
	):
		fail("Unsupported survival missile availability consumer.")
		return -1
	var boundary := literal(draw + 0xb2, 3)
	if boundary != literal(draw + 0x8da, 3):
		fail("Conflicting survival missile control and notice thresholds.")
		return -1
	return boundary


func survival_hud() -> Dictionary:
	var draw := symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var ctor := symbol_address("__ZN3HudC2Ev")
	for link in [
		[ctor, 0x13c, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[ctor, 0x2ca, "__ZN11AbyssEngine11PaintCanvas15GetImage2DWidthEj"],
		[draw, 0x81c, "__ZN5Level8getScoreEv"],
		[draw, 0x99c, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjii"],
		[draw, 0x9c6, "__ZN5Level25getCurrentComboMultiplierEv"],
		[draw, 0xa38, "__ZN8GameText7getTextEi"],
		[draw, 0x9be, "__ZN11AbyssEngine11PaintCanvas10DrawStringEjRKNS_6StringEiib"],
		[draw, 0xe38, "__ZN6Status14getPlayingTimeEv"]
	]:
		if call_target(link[0] + link[1]) != symbol_address(link[2]):
			fail("Unsupported survival HUD consumer.")
			return {}
	var missiles := survival_missile_unlock()
	var result := {
		"radar": survival_radar(),
		"score_image": ui_region_binding(shifted_at(ctor + 0x134, ctor + 0x138, 1)),
		"score_right": (u16(ctor + 0x290) & 255) + (u16(ctor + 0x2d6) & 255),
		"score_top": immediate_at(ctor + 0x2de, 2),
		"score_text": [u16(draw + 0x9b2) & 255, u16(draw + 0x9b0) & 255],
		"notice_ms": shifted_at(draw + 0x832, draw + 0x834, 2),
		"notice_height_lines": 1 << ((u16(ctor + 0x3fa) >> 6) & 31),
		"notice_y": u16(ctor + 0x3fc) & 255,
		"notices":
		[
			{"above": u16(draw + 0x822) & 255, "text": literal(draw + 0x83e, 1)},
			{"above": literal(draw + 0x854, 3), "text": literal(draw + 0x8a0, 1)},
			{"above": missiles, "text": shifted_at(draw + 0x8fa, draw + 0x8fe, 1)},
			{"above": literal(draw + 0x878, 3), "text": literal(draw + 0x8a0, 1)}
		],
		"combo_ms": shifted_at(draw + 0x9e2, draw + 0x9e4, 3),
		"combo_minimum": (u16(draw + 0x9cc) & 255) + 1,
		"combo_text":
		[
			literal(draw + 0xa18, 1),
			literal(draw + 0xa22, 1),
			literal(draw + 0xa2c, 1),
			shifted_at(draw + 0xa30, draw + 0xa32, 1)
		],
		"combo_separator": embedded_string(literal(draw + 0xa3e, 1)),
		"combo_y_from_center": u16(draw + 0xb08) & 255,
		"elapsed_right": (u16(ctor + 0x1ea) & 255) + (u16(draw + 0xe64) & 255),
		"elapsed_bottom": (u16(ctor + 0x212) & 255) - (u16(draw + 0xe56) & 255)
	}
	return result if error.is_empty() else {}


func survival_radar() -> Dictionary:
	var ctor := symbol_address("__ZN5RadarC2EP5Level")
	var draw := symbol_address("__ZN5Radar4drawEi")
	var spawn := symbol_address("__ZN5Level15spawnNewEnemiesEv")
	# Radar reads the archetype written by reincarnation, not current HP or score.
	if u16(draw + 0x182) != 0x6bdb or u16(spawn + 0x17c) != 0x63d8:
		fail("Unsupported survival radar strength association.")
		return {}
	var bounds := [u16(draw + 0x224) & 255, u16(draw + 0x22e) & 255]
	for record in [
		[0x224, 5, 0, 0xdc01],
		[0x22e, 0, 1, 0xdc01],
		[0x25c, 5, 0, 0xdc0e],
		[0x280, 2, 1, 0xdc01],
		[0x4bc, 3, 0, 0xdc01],
		[0x4c6, 4, 1, 0xdc01]
	]:
		if (
			u16(draw + record[0]) != (0x2800 | (int(record[1]) << 8) | int(bounds[record[2]]))
			or u16(draw + record[0] + 2) != record[3]
		):
			fail("Unsupported survival radar strength comparison.")
			return {}
	if bounds[0] >= bounds[1]:
		fail("Invalid survival radar strength ranges.")
		return {}
	var records := {
		"weak_near": [0xca, 0xcc, 1],
		"weak_far": [0xa4, 0xa6, 1],
		"weak_off": [0x8c, 0x8e, 1],
		"medium_near": [0xbe, 0xc0, 1],
		"medium_far": [0xac, 0xb4, 4],
		"medium_off": [0x98, 0x9a, 1],
		"strong_near": [0x2c, 0x36, 1],
		"strong_far": [0x48, 0x50, 4],
		"strong_off": [0x40, 0x42, 1]
	}
	var images := {}
	for key in records:
		var record: Array = records[key]
		if (
			call_target(ctor + record[1])
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		):
			fail("Unsupported survival radar image consumer.")
			return {}
		var resource := (
			literal(ctor + record[0], 1)
			if record[2] == 1
			else shifted_at(ctor + record[0], ctor + record[0] + 4, 1)
		)
		images[key] = flight_image_binding(resource)
	return {"bounds": bounds, "images": images} if error.is_empty() else {}


func survival_player_armament() -> Dictionary:
	var start := symbol_address("__ZN5Level9createGunEiiiiii")
	var player := symbol_address("__ZN5Level12createPlayerEv")
	var shoot := symbol_address("__ZN6Player5shootEixb")
	var primary := (u16(player + 0x168) >> 6) & 31
	var missile := (u16(player + 0x186) >> 6) & 31
	var table := start + 0x12c
	if (
		call_target(start + 0x128) != symbol_address("___switch32")
		or primary >= u32(table)
		or missile >= u32(table)
		or table + u32(table + 4 + primary * 4) != start + 0x1be
		or table + u32(table + 4 + missile * 4) != start + 0xa54
		or call_target(player + 0x39a) != start
	):
		fail("Unsupported survival player weapon dispatch.")
		return {}
	for link in [
		[0x20a, "__Z14ArraySetLengthIP3GunEvjR5ArrayIT_E"],
		[0x29c, "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"],
		[0x36a, "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"],
		[0x3c0, "__ZN9ObjectGunC1EiP3Gunij"],
		[0x476, "__ZN9ObjectGunC1EiP3Gunij"],
		[0xae8, "__Z14ArraySetLengthIP3GunEvjR5ArrayIT_E"],
		[0xb6c, "__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_"],
		[0xc50, "__ZN9RocketGunC1EiP3Guniijib"],
		[0x44fc, "__ZN3Gun9setImpactEP6Sparks"],
		[0x4506, "__ZN3Gun12setPlayerGunEb"],
		[0x4568, "__ZN9PlayerEgo6addGunEP5ArrayIP3GunEi"]
	]:
		if call_target(start + link[0]) != symbol_address(link[1]):
			fail("Unsupported player gun constructor or ownership consumer.")
			return {}
	# These bind the two position vectors and the supplied equipment values to
	# Gun parameters. This reader recovers data, not a general instruction VM.
	for pair in [
		[0x22a, 0x425b],
		[0x232, 0x005b],
		[0x264, 0x0ff3],
		[0x266, 0x199b],
		[0x268, 0x105b],
		[0x2fc, 0x425b],
		[0x308, 0x425b],
		[0x318, 0x005b],
		[0xaa0, 0x6035],
		[0xa7e, 0x280e],
		[0xa80, 0xd009],
		[0xb02, 0x425b],
		[0xb1e, 0x6025],
		[0xc32, 0x9301],
		[0xc38, 0x2301],
		[0xc3a, 0x9303]
	]:
		if u16(start + pair[0]) != pair[1]:
			fail("Unsupported player gun parameter binding at %x." % (start + pair[0]))
			return {}
	if (
		(
			call_target(shoot + 0x82)
			!= symbol_address("__ZN3Gun5shootEN11AbyssEngine6AEMath6MatrixEib")
		)
		or u16(shoot + 0xa0) != 0x3501
		or u16(shoot + 0xae) != 0xdbd3
	):
		fail("Unsupported simultaneous player muzzle firing.")
		return {}
	var laser_mounts := [
		[
			immediate_at(start + 0x21e, 3),
			-immediate_at(start + 0x228, 3),
			shifted_at(start + 0x230, start + 0x232, 3)
		],
		[
			-immediate_at(start + 0x2fa, 3),
			-immediate_at(start + 0x302, 3),
			shifted_at(start + 0x30e, start + 0x318, 3)
		]
	]
	var model := literal(start + 0x3be, 3)
	if (
		model != literal(start + 0x474, 3)
		or immediate_at(start + 0x260, 2) != immediate_at(start + 0x33c, 2)
	):
		fail("Conflicting starting laser muzzle properties.")
		return {}
	var overlay := literal(start + 0xa98, 5)
	var rocket := symbol_address("__ZN9RocketGunC2EiP3Guniijib")
	if (
		u16(start + 0xc36) != 0x9302
		or call_target(rocket + 0x94) != symbol_address("__ZN5TrailC1Eii")
	):
		fail("Unsupported survival projectile trail consumer.")
		return {}
	var result := {
		str(primary):
		{
			"mounts": laser_mounts,
			"damage_divisor": 1 << ((u16(start + 0x268) >> 6) & 31),
			"pool_capacity": immediate_at(start + 0x260, 2),
			"projectile_model": model
		},
		str(missile):
		{
			"mounts":
			[
				[
					immediate_at(start + 0xb1c, 5),
					-immediate_at(start + 0xafc, 3),
					immediate_at(start + 0xb0a, 3)
				]
			],
			"damage_divisor": 1,
			"damage_override": immediate_at(start + 0xa9a, 4),
			"pool_capacity": immediate_at(start + 0xb40, 2),
			"projectile_model": literal(start + 0xc4e, 3),
			"projectile_overlay": overlay,
			"guidance": rocket_guidance(overlay),
			"trail":
			{"style": immediate_at(start + 0xc34, 3), "segments": immediate_at(rocket + 0x92, 2)}
		}
	}
	if (
		laser_mounts.size() != immediate_at(start + 0x206, 0)
		or result[str(missile)].mounts.size() != immediate_at(start + 0xae6, 0)
	):
		fail("Unsupported starting player mount count.")
	return result if error.is_empty() else {}


func survival_content() -> Dictionary:
	var result := {
		"rules": survival_rules(),
		"setup": survival_setup(),
		"armament": survival_armament(),
		"motion": interceptor_combat().get("motion", {}),
		"scores": survival_scores(),
		"menu": survival_menu(),
		"hud": survival_hud(),
		"choice": choice_presentation()
	}
	return result if error.is_empty() else {}


func paired_player_armament() -> Dictionary:
	# Supported paired ObjectGun constructions. Dispatch indices come from the
	# supplied switch table; no catalogue IDs or balance values are duplicated.
	var start := symbol_address("__ZN5Level9createGunEiiiiii")
	var table := start + 0x12c
	if call_target(start + 0x128) != symbol_address("___switch32") or u32(table) > 256:
		fail("Unsupported player gun dispatch table.")
		return {}
	var layouts: Array = [
		{
			"branch": 446,
			"count": [518, 522],
			"damage": [616, 4123, [[612, 4083], [614, 6555]]],
			"guns": [668, 874],
			"pools": [608, 828],
			"objects": [960, 1142],
			"models": [958, 1140],
			"parameters":
			[
				[[624, 0, 2596], [654, 4, 2600], [604, 1, 2604]],
				[[820, 6, 2596], [860, 4, 2600], [836, 0, 2604]]
			],
			"zeros":
			[
				[580, 1, [[586, 24577], [588, 24593], [590, 24601]]],
				[796, 3, [[802, 24611], [804, 24587], [806, 24595]]]
			],
			"mounts":
			[
				[[542, -1, 550, 24611], [552, 554, 556, 24619], [560, 562, 564, 24627]],
				[[762, 764, 766, 24619], [770, 776, 778, 24627], [782, 792, 794, 24579]]
			]
		},
		{
			"branch": 1178,
			"count": [1246, 1248],
			"damage": [1350, 4120, [[1346, 17513], [1348, 37013]]],
			"guns": [1406, 1620],
			"pools": [1402, 1616],
			"objects": [1714, 1810],
			"models": [1712, 1808],
			"parameters":
			[
				[[1332, 2, 2596], [1390, 4, 2600], [1352, 3, 2604]],
				[[1560, 6, 2596], [1604, 4, 2600], [1580, 0, 2604]]
			],
			"zeros":
			[
				[1306, 1, [[1312, 24577], [1314, 24593], [1316, 24601]]],
				[1536, 3, [[1542, 24611], [1544, 24587], [1546, 24595]]]
			],
			"mounts":
			[
				[[1264, -1, 1274, 24611], [1276, 1278, 1282, 24619], [1286, 1288, 1290, 24627]],
				[[1498, 1500, 1506, 24619], [1510, 1516, 1518, 24627], [1522, 1532, 1534, 24579]]
			]
		},
		{
			"branch": 1988,
			"count": [2054, 2058],
			"damage": [2154, 4121, [[2150, 4035], [2152, 6171]]],
			"guns": [2206, 2416],
			"pools": [2202, 2412],
			"objects": [2502, 2592],
			"models": [2500, 2590],
			"parameters":
			[
				[[2156, 3, 2596], [2190, 4, 2600], [2140, 4, 2604]],
				[[2358, 6, 2596], [2400, 4, 2600], [2376, 0, 2604]]
			],
			"zeros":
			[
				[2114, 2, [[2120, 24586], [2122, 24602], [2124, 24610]]],
				[2334, 3, [[2340, 24611], [2342, 24587], [2344, 24595]]]
			],
			"mounts":
			[
				[[2072, -1, 2082, 24619], [2084, 2086, 2090, 24627], [2094, 2096, 2102, 24579]],
				[[2300, 2302, 2304, 24619], [2308, 2314, 2316, 24627], [2320, 2330, 2332, 24579]]
			]
		},
		{
			"branch": 11668,
			"count": [11740, 11744],
			"damage": [11854, 4121, [[11850, 4035], [11852, 6171]]],
			"guns": [11912, 12158],
			"pools": [11910, 12156],
			"objects": [12338, 12454],
			"models": [12336, 12452],
			"parameters":
			[
				[[11856, 3, 2596], [11890, 4, 2600], [11840, 4, 2604]],
				[[12086, 2, 2596], [12136, 4, 2600], [12088, 3, 2604]]
			],
			"zeros":
			[
				[11806, 1, [[11812, 24577], [11814, 24593], [11816, 24601]]],
				[12064, 3, [[12066, 24611], [12068, 24619], [12070, 24627]]]
			],
			"mounts":
			[
				[
					[11768, 11770, 11774, 24611],
					[11776, 11778, 11782, 24619],
					[11786, 11788, 11790, 24627]
				],
				[
					[12018, -1, 12024, 24579],
					[12026, 12028, 12032, 24587],
					[12036, 12038, 12040, 24595]
				]
			]
		},
		{
			"branch": 12496,
			"count": [12568, 12572],
			"damage": [12680, 4121, [[12676, 4035], [12678, 6171]]],
			"guns": [12736, 12976],
			"pools": [12734, 12974],
			"objects": [13092, 13206],
			"models": [13090, 13204],
			"parameters":
			[
				[[12682, 3, 2596], [12718, 4, 2600], [12664, 4, 2604]],
				[[12910, 2, 2596], [12958, 4, 2600], [12914, 3, 2604]]
			],
			"zeros":
			[
				[12636, 1, [[12642, 24577], [12644, 24593], [12646, 24601]]],
				[12888, 3, [[12890, 24611], [12892, 24619], [12894, 24627]]]
			],
			"mounts":
			[
				[
					[12594, 12596, 12602, 24611],
					[12606, 12608, 12612, 24619],
					[12616, 12618, 12620, 24627]
				],
				[
					[12840, -1, 12848, 24579],
					[12850, 12852, 12856, 24587],
					[12860, 12862, 12864, 24595]
				]
			]
		},
		{
			"branch": 13332,
			"count": [13404, 13408],
			"damage": [13518, 4121, [[13514, 4035], [13516, 6171]]],
			"guns": [13576, 13822],
			"pools": [13574, 13820],
			"objects": [13938, 14054],
			"models": [13936, 14052],
			"parameters":
			[
				[[13520, 3, 2596], [13554, 4, 2600], [13504, 4, 2604]],
				[[13750, 2, 2596], [13800, 4, 2600], [13752, 3, 2604]]
			],
			"zeros":
			[
				[13470, 1, [[13476, 24577], [13478, 24593], [13480, 24601]]],
				[13728, 3, [[13730, 24611], [13732, 24619], [13734, 24627]]]
			],
			"mounts":
			[
				# Supported paired ObjectGun constructions. Dispatch indices come from the
				[
					[13432, 13434, 13438, 24611],
					[13440, 13442, 13446, 24619],
					[13450, 13452, 13454, 24627]
				],
				[
					[13682, -1, 13688, 24579],
					[13690, 13692, 13696, 24587],
					[13700, 13702, 13704, 24595]
				]
			]
		},
		{
			"branch": 14164,
			"count": [14236, 14240],
			"damage": [14348, 4121, [[14344, 4035], [14346, 6171]]],
			"guns": [14404, 14644],
			"pools": [14402, 14642],
			"objects": [14760, 14874],
			"models": [14758, 14872],
			"parameters":
			[
				# supplied switch table; no catalogue IDs or balance values are duplicated.
				[[14350, 3, 2596], [14386, 4, 2600], [14332, 4, 2604]],
				[[14578, 2, 2596], [14626, 4, 2600], [14582, 3, 2604]]
			],
			"zeros":
			[
				[14304, 1, [[14310, 24577], [14312, 24593], [14314, 24601]]],
				[14556, 3, [[14558, 24611], [14560, 24619], [14562, 24627]]]
			],
			"mounts":
			[
				[
					[14262, 14264, 14270, 24611],
					[14274, 14276, 14280, 24619],
					[14284, 14286, 14288, 24627]
				],
				[
					[14508, -1, 14516, 24579],
					[14518, 14520, 14524, 24587],
					[14528, 14530, 14532, 24595]
				]
			]
		},
		{
			"branch": 14992,
			"count": [15064, 15068],
			"damage": [15176, 4121, [[15172, 4035], [15174, 6171]]],
			"guns": [15234, 15482],
			"pools": [15232, 15480],
			"objects": [15598, 15714],
			"models": [15596, 15712],
			"parameters":
			[
				[[15178, 3, 2596], [15212, 4, 2600], [15162, 4, 2604]],
				[[15410, 2, 2596], [15460, 4, 2600], [15412, 3, 2604]]
			],
			"zeros":
			[
				[15128, 1, [[15134, 24577], [15136, 24593], [15138, 24601]]],
				[15388, 3, [[15390, 24611], [15392, 24619], [15394, 24627]]]
			],
			"mounts":
			[
				[
					[15092, -1, 15096, 24611],
					[15098, 15100, 15104, 24619],
					[15108, 15110, 15112, 24627]
				],
				[
					[15340, 15342, 15348, 24579],
					[15350, 15352, 15356, 24587],
					[15360, 15362, 15364, 24595]
				]
			]
		}
	]
	var result := {}
	for layout in layouts:
		var matched := false
		for index in u32(table):
			if table + u32(table + 4 + index * 4) != start + int(layout.branch):
				continue
			matched = true
			var declaration := object_player_gun(start, layout)
			if declaration.is_empty():
				return {}
			result[str(index)] = declaration
		if not matched:
			fail("Missing supported paired weapon construction.")
			return {}
	return result if error.is_empty() else {}


func object_player_gun(start: int, layout: Dictionary) -> Dictionary:
	if (
		call_target(start + int(layout.count[1]))
		!= symbol_address("__Z14ArraySetLengthIP3GunEvjR5ArrayIT_E")
	):
		fail("Unsupported paired weapon count consumer.")
		return {}
	var count := immediate_at(start + int(layout.count[0]), 0)
	if count != layout.mounts.size():
		fail("Conflicting paired weapon mount count.")
		return {}
	var divisor := 1
	if layout.has("damage_direct"):
		if u16(start + int(layout.damage_direct[0])) != int(layout.damage_direct[1]):
			fail("Unsupported direct catalogue weapon damage binding.")
			return {}
	else:
		var damage_at := start + int(layout.damage[0])
		if (u16(damage_at) & 0xf83f) != int(layout.damage[1]):
			fail("Unsupported player weapon damage divisor.")
			return {}
		for guard in layout.damage[2]:
			if u16(start + int(guard[0])) != int(guard[1]):
				fail("Unsupported player weapon damage input.")
				return {}
		divisor = 1 << ((u16(damage_at) >> 6) & 31)
	var result := {
		"mounts": [], "damage_divisor": divisor, "pool_capacity": -1, "projectile_model": -1
	}
	for mount in count:
		if (
			(
				call_target(start + int(layout.guns[mount]))
				!= symbol_address("__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_")
			)
			or (
				call_target(start + int(layout.objects[mount]))
				!= symbol_address(str(layout.get("renderer", "__ZN9ObjectGunC1EiP3Gunij")))
			)
		):
			fail("Unsupported paired weapon constructor.")
			return {}
		for binding in layout.parameters[mount]:
			if literal(start + int(binding[0]), int(binding[1])) != int(binding[2]):
				fail("Unsupported paired weapon catalogue parameter binding.")
				return {}
		var zero: Array = layout.zeros[mount]
		if immediate_at(start + int(zero[0]), int(zero[1])) != 0:
			fail("Unsupported paired weapon angular offset.")
			return {}
		for guard in zero[2]:
			if u16(start + int(guard[0])) != int(guard[1]):
				fail("Unsupported paired weapon angular vector consumer.")
				return {}
		var point := []
		for axis in layout.mounts[mount]:
			var address := start + int(axis[0])
			var register := int(axis[4]) if axis.size() > 4 else 3
			var value := (
				signed_literal(address, register)
				if (u16(address) & 0xf800) == 0x4800
				else immediate_at(address, register)
			)
			if int(axis[1]) >= 0:
				var transform := start + int(axis[1])
				if u16(transform) == (0x4240 | (register * 9)):
					value = -value
				else:
					value = shifted_at(address, transform, register)
			if u16(start + int(axis[2])) != int(axis[3]):
				fail("Unsupported paired weapon position consumer.")
				return {}
			point.append(value)
		result.mounts.append(point)
		var capacity := immediate_at(start + int(layout.pools[mount]), 2)
		var model := literal(start + int(layout.models[mount]), 3)
		if mount > 0 and (capacity != result.pool_capacity or model != result.projectile_model):
			fail("Conflicting paired weapon projectile properties.")
			return {}
		result.pool_capacity = capacity
		result.projectile_model = model
	if layout.has("rocket_effects"):
		var first := []
		for bindings in layout.rocket_effects:
			var values := []
			for binding in bindings:
				var address := start + int(binding[0])
				var value := (
					literal(address, int(binding[1]))
					if (u16(address) & 0xf800) == 0x4800
					else immediate_at(address, int(binding[1]))
				)
				if u16(start + int(binding[2])) != int(binding[3]):
					fail("Unsupported missile effect argument consumer.")
					return {}
				values.append(value)
			if not first.is_empty() and values != first:
				fail("Conflicting missile muzzle effects.")
				return {}
			first = values
		var constructor := symbol_address("__ZN9RocketGunC2EiP3Guniijib")
		var update := symbol_address("__ZN9RocketGun6updateEi")
		if (
			call_target(constructor + 0x94) != symbol_address("__ZN5TrailC1Eii")
			or u16(constructor + 0x72) != 0x54d1
			or u16(update + 0xba) != 0x5ce3
			or u16(update + 0xbe) != 0xd00b
		):
			fail("Unsupported missile trail or homing flag consumer.")
			return {}
		result.projectile_overlay = int(first[0])
		result.projectile_color = int(first[1])
		result.trail = {"style": int(first[2]), "segments": immediate_at(constructor + 0x92, 2)}
		if first[3] == 1:
			result.guidance = rocket_guidance(int(first[0]))
		elif first[3] != 0:
			fail("Invalid missile homing flag.")
	return result if error.is_empty() else {}


func plasma_player_armament() -> Dictionary:
	var start := symbol_address("__ZN5Level9createGunEiiiiii")
	var table := start + 0x12c
	if call_target(start + 0x128) != symbol_address("___switch32") or u32(table) > 256:
		fail("Unsupported plasma weapon dispatch table.")
		return {}
	var layouts: Array = [
		{
			"branch": 4618,
			"count": [4684, 4688],
			"damage": [4782, 4121, [[4778, 4035], [4780, 6171]]],
			"guns": [4834, 5136],
			"pools": [4830, 5132],
			"objects": [5222, 5312],
			"models": [5220, 5310],
			"parameters":
			[
				[[4784, 3, 2596], [4818, 4, 2600], [4768, 4, 2604]],
				[[5076, 6, 2596], [5120, 4, 2600], [5096, 0, 2604]]
			],
			"zeros":
			[
				[4740, 2, [[4746, 24586], [4748, 24602], [4750, 24610]]],
				[5052, 3, [[5058, 24611], [5060, 24587], [5062, 24595]]]
			],
			"mounts":
			[
				[[4708, -1, 4714, 24619], [4716, 4718, 4722, 24627], [4724, -1, 4726, 24579]],
				[[5018, 5020, 5022, 24619], [5026, 5032, 5040, 24627], [5048, -1, 5050, 24579]]
			]
		},
		{
			"branch": 5348,
			"count": [5416, 5418],
			"guns": [5550],
			"pools": [5506],
			"objects": [5670],
			"models": [5668],
			"parameters": [[[5490, 6, 2596], [5536, 4, 2600], [5512, 0, 2604]]],
			"zeros": [[5470, 5, [[5476, 24589], [5478, 24597], [5480, 24605]]]],
			"mounts":
			[[[5470, -1, 5472, 24613, 5], [5440, 5444, 5450, 24627], [5452, 5454, 5456, 24579]]],
			"damage_direct": [5546, 39305]
		},
		{
			"branch": 5714,
			"count": [5786, 5790],
			"damage": [5890, 4120, [[5886, 26642], [5888, 37052]]],
			"guns": [5944, 6240],
			"pools": [5940, 6236],
			"objects": [6326, 6416],
			"models": [6324, 6414],
			"parameters":
			[
				[[5874, 2, 2596], [5928, 4, 2600], [5892, 3, 2604]],
				[[6182, 6, 2596], [6224, 4, 2600], [6200, 0, 2604]]
			],
			"zeros":
			[
				[5848, 1, [[5854, 24577], [5856, 24593], [5858, 24601]]],
				[6158, 3, [[6164, 24611], [6166, 24587], [6168, 24595]]]
			],
			"mounts":
			[
				[[5810, 5812, 5820, 24611], [5822, 5824, 5828, 24619], [5830, -1, 5832, 24627]],
				[[6128, -1, 6136, 24619], [6138, 6140, 6146, 24627], [6154, -1, 6156, 24579]]
			]
		}
	]
	var result := {}
	for layout in layouts:
		var matched := false
		for index in u32(table):
			if table + u32(table + 4 + index * 4) != start + int(layout.branch):
				continue
			matched = true
			var gun := object_player_gun(start, layout)
			if gun.is_empty():
				return {}
			result[str(index)] = gun
		if not matched:
			fail("Missing supported plasma weapon construction.")
			return {}
	return result if error.is_empty() else {}


func missile_player_armament() -> Dictionary:
	var start := symbol_address("__ZN5Level9createGunEiiiiii")
	var table := start + 0x12c
	if call_target(start + 0x128) != symbol_address("___switch32") or u32(table) > 256:
		fail("Unsupported missile weapon dispatch table.")
		return {}
	# Normal campaign branch preserves catalogue damage and chooses its own glow.
	# Survival's separate branch changes both; never apply that override globally.
	if (
		call_target(start + 0xa6e) != start + 0x4544
		or call_target(start + 0xa92) != start + 0x4544
		or call_target(start + 0x454c) != start + 0xaa2
		or literal(start + 0x4544, 4) != literal(start + 0xc18, 6)
		or u16(start + 0x454a) != 0x6023
		or u16(start + 0xa7e) != 0x280e
		or u16(start + 0xa80) != 0xd009
	):
		fail("Unsupported normal/survival missile branch.")
		return {}
	var layouts: Array = [
		{
			"branch": 2644,
			"count": [2790, 2792],
			"guns": [2924],
			"pools": [2880],
			"objects": [3152],
			"models": [3150],
			"parameters": [[[2864, 6, 2596], [2910, 4, 2600], [2886, 0, 2604]]],
			"zeros": [[2844, 5, [[2850, 24589], [2852, 24597], [2854, 24605]]]],
			"mounts":
			[[[2844, -1, 2846, 24613, 5], [2812, 2818, 2824, 24627], [2826, -1, 2828, 24579]]],
			"damage_direct": [2920, 39305],
			"renderer": "__ZN9RocketGunC1EiP3Guniijib",
			"rocket_effects":
			[
				[
					[17734, 3, 3134, 38400],
					[3118, 3, 3122, 37633],
					[3124, 3, 3126, 37634],
					[3128, 3, 3130, 37635]
				]
			]
		},
		{
			"branch": 3190,
			"count": [3256, 3260],
			"damage": [3354, 4120, [[3350, 17513], [3352, 37028]]],
			"guns": [3410, 3622],
			"pools": [3406, 3618],
			"objects": [3720, 3822],
			"models": [3718, 3820],
			"parameters":
			[
				[[3336, 2, 2596], [3394, 4, 2600], [3356, 3, 2604]],
				[[3562, 6, 2596], [3606, 4, 2600], [3582, 0, 2604]]
			],
			"zeros":
			[
				[3310, 1, [[3316, 24577], [3318, 24593], [3320, 24601]]],
				[3538, 3, [[3544, 24611], [3546, 24587], [3548, 24595]]]
			],
			"mounts":
			[
				[[3286, -1, 3298, 24610, 2], [3284, 3288, 3294, 24619], [3286, -1, 3296, 24626, 2]],
				[[3504, 3506, 3508, 24619], [3512, 3518, 3526, 24627], [3534, -1, 3536, 24579]]
			],
			"renderer": "__ZN9RocketGunC1EiP3Guniijib",
			"rocket_effects":
			[
				[
					[3690, 3, 3694, 37632],
					[3696, 3, 3698, 37633],
					[3700, 3, 3702, 37634],
					[3704, 3, 3706, 37635]
				],
				[
					[3788, 3, 3794, 37632],
					[3796, 3, 3798, 37633],
					[3800, 3, 3802, 37634],
					[3806, 3, 3808, 37635]
				]
			]
		},
		{
			"branch": 3956,
			"count": [4024, 4028],
			"damage": [4118, 4121, [[4114, 4035], [4116, 6171]]],
			"guns": [4170, 4382],
			"pools": [4166, 4378],
			"objects": [4480, 4582],
			"models": [4478, 4580],
			"parameters":
			[
				[[4120, 3, 2596], [4154, 4, 2600], [4104, 4, 2604]],
				[[4324, 6, 2596], [4366, 4, 2600], [4342, 0, 2604]]
			],
			"zeros":
			[
				[4080, 2, [[4084, 24586], [4086, 24602], [4088, 24610]]],
				[4300, 3, [[4306, 24611], [4308, 24587], [4310, 24595]]]
			],
			"mounts":
			[
				[[4068, -1, 4076, 24618, 2], [4046, 4050, 4058, 24627], [4068, -1, 4074, 24578, 2]],
				[[4262, 4264, 4272, 24619], [4276, 4280, 4288, 24627], [4296, -1, 4298, 24579]]
			],
			"renderer": "__ZN9RocketGunC1EiP3Guniijib",
			"rocket_effects":
			[
				# Normal campaign branch preserves catalogue damage and chooses its own glow.
				[
					[4450, 3, 4454, 37632],
					[4456, 3, 4458, 37633],
					[4460, 3, 4462, 37634],
					[4464, 3, 4466, 37635]
				],
				[
					[4548, 3, 4554, 37632],
					[4556, 3, 4558, 37633],
					[4560, 3, 4562, 37634],
					[4566, 3, 4568, 37635]
				]
			]
		},
		{
			"branch": 15836,
			"count": [15908, 15912],
			"damage": [16014, 4121, [[16010, 4035], [16012, 6171]]],
			"guns": [16070, 16310],
			"pools": [16068, 16308],
			"objects": [16438, 16562],
			"models": [16436, 16560],
			"parameters":
			[
				# Survival's separate branch changes both; never apply that override globally.
				[[16016, 3, 2596], [16052, 4, 2600], [15998, 4, 2604]],
				[[16244, 2, 2596], [16292, 4, 2600], [16248, 3, 2604]]
			],
			"zeros":
			[
				[15970, 1, [[15976, 24577], [15978, 24593], [15980, 24601]]],
				[16222, 3, [[16224, 24611], [16226, 24619], [16228, 24627]]]
			],
			"mounts":
			[
				[
					[15948, -1, 15958, 24610, 2],
					[15936, 15942, 15950, 24619],
					[15948, -1, 15956, 24626, 2]
				],
				[
					[16174, 16176, 16186, 24579],
					[16188, 16192, 16194, 24587],
					[16196, -1, 16198, 24595]
				]
			],
			"renderer": "__ZN9RocketGunC1EiP3Guniijib",
			"rocket_effects":
			[
				[
					[16402, 3, 16408, 37632],
					[16410, 3, 16412, 37633],
					[16414, 3, 16416, 37634],
					[16418, 3, 16420, 37635]
				],
				[
					[16522, 3, 16532, 37632],
					[16534, 3, 16536, 37633],
					[16538, 3, 16540, 37634],
					[16542, 3, 16544, 37635]
				]
			]
		}
	]
	var result := {}
	for layout in layouts:
		var matched := false
		for index in u32(table):
			if table + u32(table + 4 + index * 4) != start + int(layout.branch):
				continue
			matched = true
			var gun := object_player_gun(start, layout)
			if gun.is_empty():
				return {}
			result[str(index)] = gun
		if not matched:
			fail("Missing supported missile weapon construction.")
			return {}
	return result if error.is_empty() else {}


func multi_projectile_player_armament() -> Dictionary:
	# Per-muzzle constants are distinct from catalogue summary statistics. These
	# bounded references describe supported data layouts, never executable logic.
	var start := symbol_address("__ZN5Level9createGunEiiiiii")
	var table := start + 0x12c
	if call_target(start + 0x128) != symbol_address("___switch32") or u32(table) > 256:
		fail("Unsupported multi-projectile weapon dispatch table.")
		return {}
	var layouts: Array = [
		{
			"branch": 6460,
			"count": [6528, 0, -1, -1, 0],
			"count_call": 6530,
			"muzzles":
			[
				{
					"gun": 6654,
					"renderer": 7378,
					"position":
					[
						[6546, 3, 6552, 6562, 24611],
						[6564, 3, -1, 6566, 24619],
						[6568, 3, -1, 6570, 24627]
					],
					"zero": [6586, 1, [[6592, 24577], [6594, 24593], [6596, 24601]]],
					"parameters":
					{
						"damage": [6624, 1, -1, -1, 0],
						"pool_capacity": [6652, 2, -1, -1, 0],
						"lifetime_ms": [6620, 3, 6622, -1, 0],
						"reload_ms": [6610, 2, -1, 6612, 37376],
						"speed_per_ms": [6614, 2, -1, 6616, 37377]
					},
					"effects":
					{
						"projectile_overlay": [7326, 5, 7328, 7360, 38144],
						"projectile_color": [7346, 3, -1, 7348, 37633],
						"trail_style": [7350, 3, -1, 7352, 37634],
						"homing": [7354, 3, -1, 7356, 37635],
						"projectile_model": [7376, 3, -1, -1, 0]
					}
				},
				{
					"gun": 6848,
					"renderer": 7478,
					"position":
					[
						[6746, 3, -1, 6758, 24587],
						[6760, 3, -1, 6762, 24595],
						[6766, 3, 6774, 6778, 24611]
					],
					"zero": [6780, 3, [[6786, 24619], [6788, 24627], [6790, 24579]]],
					"parameters":
					{
						"damage": [6818, 1, -1, -1, 0],
						"pool_capacity": [6846, 2, -1, -1, 0],
						"lifetime_ms": [6814, 3, 6816, -1, 0],
						"reload_ms": [6804, 2, -1, 6806, 37376],
						"speed_per_ms": [6808, 2, -1, 6810, 37377]
					},
					"effects":
					{
						"projectile_overlay": [7426, 5, 7428, 7460, 38144],
						"projectile_color": [7446, 3, -1, 7448, 37633],
						"trail_style": [7450, 3, -1, 7452, 37634],
						"homing": [7454, 3, -1, 7456, 37635],
						"projectile_model": [7476, 3, -1, -1, 0]
					}
				},
				{
					"gun": 7012,
					"renderer": 7578,
					"position":
					[
						[6908, 3, 6912, 6922, 24619],
						[6926, 3, -1, 6930, 24627],
						[6938, 3, -1, 6940, 24579]
					],
					"zero": [6942, 3, [[6948, 24611], [6950, 24587], [6952, 24595]]],
					"parameters":
					{
						"damage": [6982, 1, -1, -1, 0],
						"pool_capacity": [7010, 2, -1, -1, 0],
						"lifetime_ms": [6978, 3, 6980, -1, 0],
						"reload_ms": [6966, 2, 6968, 6970, 37376],
						"speed_per_ms": [6972, 2, -1, 6974, 37377]
					},
					"effects":
					{
						"projectile_overlay": [7526, 5, 7528, 7560, 38144],
						"projectile_color": [7546, 3, -1, 7548, 37633],
						"trail_style": [7550, 3, -1, 7552, 37634],
						"homing": [7554, 3, -1, 7556, 37635],
						"projectile_model": [7576, 3, -1, -1, 0]
					}
				},
				{
					"gun": 7282,
					"renderer": 7678,
					"position":
					[
						[7174, 3, -1, 7184, 24619],
						[7188, 3, 7192, 7200, 24627],
						[7208, 3, -1, 7210, 24579]
					],
					"zero": [7212, 3, [[7218, 24611], [7220, 24587], [7222, 24595]]],
					"parameters":
					{
						"damage": [7252, 1, -1, -1, 0],
						"pool_capacity": [7280, 2, -1, -1, 0],
						"lifetime_ms": [7248, 3, 7250, -1, 0],
						"reload_ms": [7236, 2, 7238, 7240, 37376],
						"speed_per_ms": [7242, 2, -1, 7244, 37377]
					},
					"effects":
					{
						"projectile_overlay": [7626, 5, 7628, 7660, 38144],
						"projectile_color": [7646, 3, -1, 7648, 37633],
						"trail_style": [7650, 3, -1, 7652, 37634],
						"homing": [7654, 3, -1, 7656, 37635],
						"projectile_model": [7676, 3, -1, -1, 0]
					}
				}
			]
		},
		{
			"branch": 7716,
			"count": [7788, 0, -1, -1, 0],
			"count_call": 7792,
			"muzzles":
			[
				{
					"gun": 7918,
					"renderer": 8936,
					"position":
					[
						[7816, 3, 7818, 7826, 24611],
						[7828, 3, -1, 7830, 24619],
						[7832, 3, -1, 7834, 24627]
					],
					"zero": [7850, 1, [[7856, 24577], [7858, 24593], [7860, 24601]]],
					"parameters":
					{
						"damage": [7888, 1, -1, -1, 0],
						"pool_capacity": [7916, 2, -1, -1, 0],
						"lifetime_ms": [7884, 3, 7886, -1, 0],
						"reload_ms": [7874, 2, -1, 7876, 37376],
						"speed_per_ms": [7878, 2, -1, 7880, 37377]
					},
					"effects":
					{
						"projectile_overlay": [8884, 5, 8886, 8918, 38144],
						"projectile_color": [8904, 3, -1, 8906, 37633],
						"trail_style": [8908, 3, -1, 8910, 37634],
						"homing": [8912, 3, -1, 8914, 37635],
						"projectile_model": [8934, 3, -1, -1, 0]
					}
				},
				{
					"gun": 8114,
					"renderer": 9036,
					"position":
					[
						[8012, 3, -1, 8020, 24587],
						[8024, 3, -1, 8026, 24595],
						[8030, 3, 8040, 8044, 24611]
					],
					"zero": [8046, 3, [[8052, 24619], [8054, 24627], [8056, 24579]]],
					"parameters":
					{
						"damage": [8084, 1, -1, -1, 0],
						"pool_capacity": [8112, 2, -1, -1, 0],
						"lifetime_ms": [8080, 3, 8082, -1, 0],
						"reload_ms": [8070, 2, -1, 8072, 37376],
						"speed_per_ms": [8074, 2, -1, 8076, 37377]
					},
					"effects":
					{
						"projectile_overlay": [8984, 5, 8986, 9018, 38144],
						"projectile_color": [9004, 3, -1, 9006, 37633],
						"trail_style": [9008, 3, -1, 9010, 37634],
						"homing": [9012, 3, -1, 9014, 37635],
						"projectile_model": [9034, 3, -1, -1, 0]
					}
				},
				{
					"gun": 8336,
					"renderer": 9136,
					"position":
					[
						[8236, 3, -1, 8246, 24619],
						[8250, 3, -1, 8254, 24627],
						[8262, 3, -1, 8264, 24579]
					],
					"zero": [8266, 3, [[8272, 24611], [8274, 24587], [8276, 24595]]],
					"parameters":
					{
						"damage": [8306, 1, -1, -1, 0],
						"pool_capacity": [8334, 2, -1, -1, 0],
						"lifetime_ms": [8302, 3, 8304, -1, 0],
						"reload_ms": [8290, 2, 8292, 8294, 37376],
						"speed_per_ms": [8296, 2, -1, 8298, 37377]
					},
					"effects":
					{
						"projectile_overlay": [9084, 5, 9086, 9118, 38144],
						"projectile_color": [9104, 3, -1, 9106, 37633],
						"trail_style": [9108, 3, -1, 9110, 37634],
						"homing": [9112, 3, -1, 9114, 37635],
						"projectile_model": [9134, 3, -1, -1, 0]
					}
				},
				{
					"gun": 8504,
					"renderer": 9292,
					"position":
					[
						[8394, 3, 8396, 8406, 24619],
						[8410, 3, 8414, 8422, 24627],
						[8430, 3, -1, 8432, 24579]
					],
					"zero": [8434, 3, [[8440, 24611], [8442, 24587], [8444, 24595]]],
					"parameters":
					{
						"damage": [8474, 1, -1, -1, 0],
						"pool_capacity": [8502, 2, -1, -1, 0],
						"lifetime_ms": [8470, 3, 8472, -1, 0],
						"reload_ms": [8458, 2, 8460, 8462, 37376],
						"speed_per_ms": [8464, 2, -1, 8466, 37377]
					},
					"effects":
					{
						"projectile_overlay": [9240, 5, 9242, 9274, 38144],
						"projectile_color": [9260, 3, -1, 9262, 37633],
						"trail_style": [9264, 3, -1, 9266, 37634],
						"homing": [9268, 3, -1, 9270, 37635],
						"projectile_model": [9290, 3, -1, -1, 0]
					}
				},
				{
					"gun": 8670,
					"renderer": 9392,
					"position":
					[
						[8580, 2, -1, 8588, 24618],
						[8562, 3, 8566, 8574, 24627],
						[8576, 3, 8578, 8582, 24579]
					],
					"zero": [8580, 2, [[8604, 24602], [8614, 24610], [8616, 24586]]],
					"parameters":
					{
						"damage": [8640, 1, -1, -1, 0],
						"pool_capacity": [8668, 2, -1, -1, 0],
						"lifetime_ms": [8636, 3, 8638, -1, 0],
						"reload_ms": [8624, 2, 8626, 8628, 37376],
						"speed_per_ms": [8630, 2, -1, 8632, 37377]
					},
					"effects":
					{
						"projectile_overlay": [9340, 5, 9342, 9374, 38144],
						"projectile_color": [9360, 3, -1, 9362, 37633],
						"trail_style": [9364, 3, -1, 9366, 37634],
						"homing": [9368, 3, -1, 9370, 37635],
						"projectile_model": [9390, 3, -1, -1, 0]
					}
				},
				{
					"gun": 8840,
					"renderer": 9492,
					"position":
					[
						[8728, 3, 8730, 8732, 24619],
						[8736, 3, 8744, 8750, 24627],
						[8754, 3, 8766, 8768, 24579]
					],
					"zero": [8770, 3, [[8776, 24611], [8778, 24587], [8780, 24595]]],
					"parameters":
					{
						"damage": [8810, 1, -1, -1, 0],
						"pool_capacity": [8838, 2, -1, -1, 0],
						"lifetime_ms": [8806, 3, 8808, -1, 0],
						"reload_ms": [8794, 2, 8796, 8798, 37376],
						"speed_per_ms": [8800, 2, -1, 8802, 37377]
					},
					"effects":
					{
						"projectile_overlay": [9440, 5, 9442, 9474, 38144],
						"projectile_color": [9460, 3, -1, 9462, 37633],
						"trail_style": [9464, 3, -1, 9466, 37634],
						"homing": [9468, 3, -1, 9470, 37635],
						"projectile_model": [9490, 3, -1, -1, 0]
					}
				}
			]
		},
		{
			"branch": 9530,
			"count": [9602, 0, -1, -1, 0],
			"count_call": 9606,
			"muzzles":
			[
				{
					"gun": 9734,
					"renderer": 10910,
					"position":
					[
						[9628, 3, 9632, 9642, 24611],
						[9644, 3, -1, 9646, 24619],
						[9648, 3, -1, 9650, 24627]
					],
					"zero": [9666, 1, [[9672, 24577], [9674, 24593], [9676, 24601]]],
					"parameters":
					{
						"damage": [9704, 1, -1, -1, 0],
						"pool_capacity": [9732, 2, -1, -1, 0],
						"lifetime_ms": [9700, 3, 9702, -1, 0],
						"reload_ms": [9690, 2, -1, 9692, 37376],
						"speed_per_ms": [9694, 2, -1, 9696, 37377]
					},
					"effects":
					{
						"projectile_overlay": [10858, 6, 10860, 10896, 38400],
						"projectile_color": [10880, 3, -1, 10882, 37633],
						"trail_style": [10884, 3, -1, 10886, 37634],
						"homing": [10890, 3, -1, 10892, 37635],
						"projectile_model": [10908, 3, -1, -1, 0]
					}
				},
				{
					"gun": 9932,
					"renderer": 11010,
					"position":
					[
						[9826, 3, -1, 9838, 24587],
						[9842, 3, -1, 9844, 24595],
						[9848, 3, 9858, 9862, 24611]
					],
					"zero": [9864, 3, [[9870, 24619], [9872, 24627], [9874, 24579]]],
					"parameters":
					{
						"damage": [9902, 1, -1, -1, 0],
						"pool_capacity": [9930, 2, -1, -1, 0],
						"lifetime_ms": [9898, 3, 9900, -1, 0],
						"reload_ms": [9888, 2, -1, 9890, 37376],
						"speed_per_ms": [9892, 2, -1, 9894, 37377]
					},
					"effects":
					{
						"projectile_overlay": [10958, 5, 10960, 10992, 38144],
						"projectile_color": [10978, 3, -1, 10980, 37633],
						"trail_style": [10982, 3, -1, 10984, 37634],
						"homing": [10986, 3, -1, 10988, 37635],
						"projectile_model": [11008, 3, -1, -1, 0]
					}
				},
				{
					"gun": 10096,
					"renderer": 11110,
					"position":
					[
						[9996, 3, -1, 10006, 24619],
						[10010, 3, -1, 10014, 24627],
						[10022, 3, -1, 10024, 24579]
					],
					"zero": [10026, 3, [[10032, 24611], [10034, 24587], [10036, 24595]]],
					"parameters":
					{
						"damage": [10066, 1, -1, -1, 0],
						"pool_capacity": [10094, 2, -1, -1, 0],
						"lifetime_ms": [10062, 3, 10064, -1, 0],
						"reload_ms": [10050, 2, 10052, 10054, 37376],
						"speed_per_ms": [10056, 2, -1, 10058, 37377]
					},
					"effects":
					{
						"projectile_overlay": [11058, 5, 11060, 11092, 38144],
						"projectile_color": [11078, 3, -1, 11080, 37633],
						"trail_style": [11082, 3, -1, 11084, 37634],
						"homing": [11086, 3, -1, 11088, 37635],
						"projectile_model": [11108, 3, -1, -1, 0]
					}
				},
				{
					"gun": 10312,
					"renderer": 11276,
					"position":
					[
						[10202, 3, 10204, 10214, 24619],
						[10218, 3, 10222, 10230, 24627],
						[10238, 3, -1, 10240, 24579]
					],
					"zero": [10242, 3, [[10248, 24611], [10250, 24587], [10252, 24595]]],
					"parameters":
					{
						"damage": [10282, 1, -1, -1, 0],
						"pool_capacity": [10310, 2, -1, -1, 0],
						"lifetime_ms": [10278, 3, 10280, -1, 0],
						"reload_ms": [10266, 2, 10268, 10270, 37376],
						"speed_per_ms": [10272, 2, -1, 10274, 37377]
					},
					"effects":
					{
						"projectile_overlay": [11224, 5, 11226, 11258, 38144],
						"projectile_color": [11244, 3, -1, 11246, 37633],
						"trail_style": [11248, 3, -1, 11250, 37634],
						"homing": [11252, 3, -1, 11254, 37635],
						"projectile_model": [11274, 3, -1, -1, 0]
					}
				},
				{
					"gun": 10478,
					"renderer": 11376,
					"position":
					[
						[10388, 2, -1, 10396, 24618],
						[10370, 3, 10374, 10382, 24627],
						[10384, 3, 10386, 10390, 24579]
					],
					"zero": [10388, 2, [[10412, 24602], [10422, 24610], [10424, 24586]]],
					"parameters":
					{
						"damage": [10448, 1, -1, -1, 0],
						"pool_capacity": [10476, 2, -1, -1, 0],
						"lifetime_ms": [10444, 3, 10446, -1, 0],
						"reload_ms": [10432, 2, 10434, 10436, 37376],
						"speed_per_ms": [10438, 2, -1, 10440, 37377]
					},
					"effects":
					{
						# Per-muzzle constants are distinct from catalogue summary statistics. These
						"projectile_overlay": [11324, 5, 11326, 11358, 38144],
						"projectile_color": [11344, 3, -1, 11346, 37633],
						"trail_style": [11348, 3, -1, 11350, 37634],
						"homing": [11352, 3, -1, 11354, 37635],
						"projectile_model": [11374, 3, -1, -1, 0]
					}
				},
				{
					"gun": 10648,
					"renderer": 11492,
					"position":
					[
						# bounded references describe supported data layouts, never executable logic.
						[10536, 3, 10538, 10540, 24619],
						[10544, 3, 10552, 10558, 24627],
						[10562, 3, 10574, 10576, 24579]
					],
					"zero": [10578, 3, [[10584, 24611], [10586, 24587], [10588, 24595]]],
					"parameters":
					{
						"damage": [10618, 1, -1, -1, 0],
						"pool_capacity": [10646, 2, -1, -1, 0],
						"lifetime_ms": [10614, 3, 10616, -1, 0],
						"reload_ms": [10602, 2, 10604, 10606, 37376],
						"speed_per_ms": [10608, 2, -1, 10610, 37377]
					},
					"effects":
					{
						"projectile_overlay": [11434, 6, 11438, 11474, 38400],
						"projectile_color": [11454, 3, -1, 11462, 37633],
						"trail_style": [11464, 3, -1, 11466, 37634],
						"homing": [11468, 3, -1, 11470, 37635],
						"projectile_model": [11490, 3, -1, -1, 0]
					}
				},
				{
					"gun": 10814,
					"renderer": 11616,
					"position":
					[
						[10706, 3, -1, 10712, 24619],
						[10716, 3, 10720, 10726, 24627],
						[10730, 3, 10740, 10744, 24579]
					],
					"zero": [10746, 3, [[10752, 24587], [10754, 24595], [10756, 24611]]],
					"parameters":
					{
						"damage": [10810, 1, -1, -1, 0],
						"pool_capacity": [10784, 2, -1, -1, 0],
						"lifetime_ms": [10812, 3, -1, -1, 0],
						"reload_ms": [10770, 3, 10774, 10776, 37632],
						"speed_per_ms": [10778, 3, -1, 10780, 37633]
					},
					"effects":
					{
						"projectile_overlay": [11558, 6, 11562, 11598, 38400],
						"projectile_color": [11578, 3, -1, 11586, 37633],
						"trail_style": [11588, 3, -1, 11590, 37634],
						"homing": [11592, 3, -1, 11594, 37635],
						"projectile_model": [11614, 3, -1, -1, 0]
					}
				}
			]
		}
	]
	var result := {}
	for layout in layouts:
		var matched := false
		for index in u32(table):
			if table + u32(table + 4 + index * 4) != start + int(layout.branch):
				continue
			matched = true
			if (
				(
					call_target(start + int(layout.count_call))
					!= symbol_address("__Z14ArraySetLengthIP3GunEvjR5ArrayIT_E")
				)
				or player_gun_constant(start, layout.count) != layout.muzzles.size()
			):
				fail("Unsupported multi-projectile muzzle count.")
				return {}
			var declaration := {"mounts": [], "ballistics": []}
			for muzzle in layout.muzzles:
				if (
					(
						call_target(start + int(muzzle.gun))
						!= symbol_address("__ZN3GunC1EiiiiiN11AbyssEngine6AEMath6VectorES2_")
					)
					or (
						call_target(start + int(muzzle.renderer))
						!= symbol_address("__ZN9RocketGunC1EiP3Guniijib")
					)
				):
					fail("Unsupported multi-projectile constructor.")
					return {}
				if immediate_at(start + int(muzzle.zero[0]), int(muzzle.zero[1])) != 0:
					fail("Unsupported nonzero projectile direction offset.")
					return {}
				for guard in muzzle.zero[2]:
					if u16(start + int(guard[0])) != int(guard[1]):
						fail("Unsupported projectile direction vector consumer.")
						return {}
				var point := []
				for axis in muzzle.position:
					point.append(player_gun_constant(start, axis))
				declaration.mounts.append(point)
				var parameters := {}
				for key in muzzle.parameters:
					var value := player_gun_constant(start, muzzle.parameters[key])
					if value <= 0:
						fail("Invalid multi-projectile ballistic constant.")
						return {}
					parameters[key] = value
				declaration.ballistics.append(parameters)
				var effects := {}
				for key in muzzle.effects:
					effects[key] = player_gun_constant(start, muzzle.effects[key])
				if declaration.has("effects") and declaration.effects != effects:
					fail("Conflicting multi-projectile muzzle effects.")
					return {}
				declaration.effects = effects
			var effects: Dictionary = declaration.effects
			declaration.erase("effects")
			var constructor := symbol_address("__ZN9RocketGunC2EiP3Guniijib")
			var update := symbol_address("__ZN9RocketGun6updateEi")
			if (
				call_target(constructor + 0x104) != symbol_address("__ZN5TrailC1Eii")
				or u16(constructor + 0x72) != 0x54d1
				or u16(update + 0xba) != 0x5ce3
				or u16(update + 0xbe) != 0xd00b
			):
				fail("Unsupported multi-projectile trail or homing consumer.")
				return {}
			if (
				int(effects.projectile_overlay) > 0
				or int(effects.projectile_model) <= 0
				or not int(effects.homing) in [0, 1]
			):
				fail("Unsupported multi-projectile visual declaration.")
				return {}
			declaration.projectile_model = int(effects.projectile_model)
			declaration.projectile_overlay = int(effects.projectile_overlay)
			declaration.projectile_color = int(effects.projectile_color)
			declaration.trail = {
				"style": int(effects.trail_style), "segments": immediate_at(constructor + 0x102, 2)
			}
			if effects.homing == 1:
				declaration.guidance = rocket_guidance(int(effects.projectile_overlay))
			result[str(index)] = declaration
		if not matched:
			fail("Missing supported multi-projectile weapon construction.")
			return {}
	return result if error.is_empty() else {}


func player_gun_constant(start: int, binding: Array) -> int:
	# One explicit constructor scalar: load, register, optional sign/shift, store.
	# No scanning, instruction stepping, branching or original-code execution.
	var address := start + int(binding[0])
	var register := int(binding[1])
	var value := (
		signed_literal(address, register)
		if (u16(address) & 0xf800) == 0x4800
		else immediate_at(address, register)
	)
	if int(binding[2]) >= 0:
		var transform := start + int(binding[2])
		if u16(transform) == (0x4240 | register * 9):
			value = -value
		else:
			value = shifted_at(address, transform, register)
	if int(binding[3]) >= 0 and u16(start + int(binding[3])) != int(binding[4]):
		fail("Unsupported player projectile constant consumer.")
	return value


func player_armament() -> Dictionary:
	var firing := symbol_address("__ZN6Player5shootEixb")
	if (
		call_target(firing + 0x40) != symbol_address("__ZN4Slot6getGunEi")
		or call_target(firing + 0x5a) != symbol_address("__ZN4Slot6getGunEi")
		or (
			call_target(firing + 0x82)
			!= symbol_address("__ZN3Gun5shootEN11AbyssEngine6AEMath6MatrixEib")
		)
	):
		fail("Unsupported player trigger association.")
		return {}
	for guard in [
		[0x44, 0x6a03],
		[0x46, 0x429d],
		[0x48, 0xdd33],
		[0x4c, 0x2200],
		[0x54, 0x50c2],
		[0xa0, 0x3501],
		[0xac, 0x429d],
		[0xae, 0xdbd3]
	]:
		if u16(firing + int(guard[0])) != int(guard[1]):
			fail("Unsupported shared player trigger cadence.")
			return {}
	var trigger_muzzle := immediate_at(firing + 0x3e, 1)
	var result := {}
	for family in [
		paired_player_armament(),
		plasma_player_armament(),
		missile_player_armament(),
		multi_projectile_player_armament()
	]:
		if family.is_empty():
			return {}
		for key in family:
			var weapon: Dictionary = family[key]
			if result.has(key) or trigger_muzzle >= weapon.mounts.size():
				fail("Conflicting player weapon or trigger declaration.")
				return {}
			weapon.trigger_muzzle = trigger_muzzle
			result[key] = weapon
	return result if error.is_empty() else {}


func projectile_trail_presentation() -> Dictionary:
	var constructor := symbol_address("__ZN5TrailC2Eii")
	var colors := symbol_address("__ZN5Trail10changeTypeEi")
	var update := symbol_address("__ZN5Trail6updateEiiiiii")
	if (
		(
			call_target(constructor + 0x9a)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas10MeshCreateEttatRj")
		)
		or call_target(constructor + 0x1b0) != colors
		or (
			call_target(colors + 0x72)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas17TransformSetColorEjj")
		)
		or call_target(colors + 0xa) != symbol_address("___switch8")
	):
		fail("Unsupported projectile trail material/color consumers.")
		return {}
	# Source UV rectangles are in the engine's Q12 texture-coordinate format.
	# Groups are selected by the constructor's style comparisons, not weapon IDs.
	for guard in [
		[0x1a, 0x3b04],
		[0x20, 0x2b03],
		[0x22, 0xd80a],
		[0x3c, 0x2e09],
		[0x40, 0x2e0b],
		[0x44, 0x2e0a],
		[0x80, 0x60e3]
	]:
		if u16(constructor + int(guard[0])) != int(guard[1]):
			fail("Unsupported trail style/width declaration.")
			return {}
	for guard in [[0x1a, 0x68f3], [0x20, 0x1aeb], [0x36, 0x68f3], [0x38, 0x18eb]]:
		if u16(update + int(guard[0])) != int(guard[1]):
			fail("Unsupported trail width consumer.")
			return {}
	var common := [
		shifted_at(constructor + 0x24, constructor + 0x2a, 1),
		shifted_at(constructor + 0x26, constructor + 0x2c, 2),
		shifted_at(constructor + 0x28, constructor + 0x2e, 3),
		shifted_at(constructor + 0x30, constructor + 0x58, 4)
	]
	var special := [
		shifted_at(constructor + 0x5e, constructor + 0x66, 6),
		shifted_at(constructor + 0x60, constructor + 0x68, 1),
		shifted_at(constructor + 0x62, constructor + 0x6a, 2),
		shifted_at(constructor + 0x64, constructor + 0x6c, 3)
	]
	var other := [
		literal(constructor + 0x48, 1),
		literal(constructor + 0x4a, 2),
		shifted_at(constructor + 0x4c, constructor + 0x50, 3),
		shifted_at(constructor + 0x4e, constructor + 0x58, 4)
	]
	var table := colors + 0xe
	var count := int(bytes[file_offset(table, 1)])
	var first := int(u16(colors + 4) & 255)
	if (u16(colors + 4) & 0xff00) != 0x3900 or count < 1 or count > 32:
		fail("Unsupported trail color dispatch.")
		return {}
	var styles := {}
	for index in count:
		var branch := table + 2 * int(bytes[file_offset(table + index + 1, 1)])
		var color := 0
		match branch - colors:
			0x34:
				color = -immediate_at(colors + 0x3a, 2)
			0x20, 0x5c:
				color = literal(colors + 0x62, 2)
			0x24:
				color = literal(colors + 0x28, 2)
			0x30, 0x50:
				color = literal(colors + 0x56, 2)
			0x42:
				color = shifted_at(colors + 0x46, colors + 0x48, 2)
			0x68:
				color = literal(colors + 0x6c, 2)
			_:
				fail("Unsupported trail color branch.")
				return {}
		var style := index + first
		var uv: Array = other
		if (
			style >= int(u16(constructor + 0x1a) & 255)
			and style <= int(u16(constructor + 0x1a) & 255) + int(u16(constructor + 0x20) & 255)
		):
			uv = common
		elif (
			style
			in [
				int(u16(constructor + 0x3c) & 255),
				int(u16(constructor + 0x40) & 255),
				int(u16(constructor + 0x44) & 255)
			]
		):
			uv = special
		styles[str(style)] = {
			"color": color & 0xffffffff,
			"uv":
			[
				float(uv[0]) / 4096.0,
				1.0 - float(uv[3]) / 4096.0,
				float(uv[2]) / 4096.0,
				1.0 - float(uv[1]) / 4096.0
			]
		}
	return (
		{
			"material": literal(constructor + 0x82, 3),
			"half_width": float(immediate_at(constructor + 0x7a, 3)) * .02,
			"styles": styles
		}
		if error.is_empty()
		else {}
	)


func lens_flare_presentation() -> Dictionary:
	var begin := symbol_address("__ZN11AbyssEngine11PaintCanvas7Begin2dEv")
	if literal(begin + 0x2e, 1) != 0x303 or literal(begin + 0x30, 0) != 0x302:
		fail("Unsupported flare alpha blend declaration.")
		return {}
	var sky := symbol_address("__ZN5Level12createSkyboxEib")
	var constructor := symbol_address("__ZN9LensFlareC2EPN11AbyssEngine11PaintCanvasE")
	var render := symbol_address("__ZN9LensFlare8render2DEiiii")
	if (
		call_target(sky + 0x120) != symbol_address("___switch8")
		or call_target(sky + 0x20c) != symbol_address("__ZN11AbyssEngine6AEMath6VectoraSERKS1_")
		or (
			call_target(constructor + 0x26)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		)
		or (
			call_target(constructor + 0x36)
			!= symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
		)
	):
		fail("Unsupported sun direction or flare image consumer.")
		return {}
	var bindings: Array = [
		[[302, 3, 304, 306, 37659], [310, 3, -1, 312, 37660], [316, 3, 318, 324, 37661]],
		[[328, 3, 330, 332, 37656], [334, 3, 336, 340, 37657], [344, 3, 346, 352, 37658]],
		[[356, 3, -1, 358, 37653], [360, 3, -1, 366, 37654], [368, 3, 370, 376, 37655]],
		[[380, 3, 382, 384, 37650], [388, 3, -1, 390, 37651], [394, 3, 396, 402, 37652]],
		[[406, 3, -1, 412, 37647], [414, 3, -1, 416, 37648], [418, 3, 420, 426, 37649]],
		[[430, 3, 432, 436, 37644], [440, 3, -1, 442, 37645], [440, 3, 446, 450, 37646]],
		[[454, 3, 456, 458, 37641], [460, 3, 462, 464, 37642], [468, 3, -1, 476, 37643]],
		[[480, 3, -1, 482, 37638], [484, 3, -1, 486, 37639], [490, 3, -1, 498, 37640]],
		[[502, 3, -1, 508, 37635], [510, 3, 512, 518, 37636], [520, 3, -1, 522, 37637]]
	]
	var table := sky + 0x124
	var variants := immediate_at(sky + 0x74, 1)
	if int(bytes[file_offset(table, 1)]) + 1 != variants or variants != bindings.size():
		fail("Unsupported sun direction table size.")
		return {}
	var directions := []
	for index in variants:
		var branch := table + 2 * int(bytes[file_offset(table + index + 1, 1)])
		var row: Array = []
		for candidate in bindings:
			if sky + int(candidate[0][0]) == branch:
				row = candidate
		if row.is_empty():
			fail("Unsupported sun direction table association.")
			return {}
		var point := []
		for axis in row:
			if int(axis[2]) >= 0 and (u16(sky + int(axis[2])) & 0xff00) == 0x3300:
				if u16(sky + int(axis[3])) != int(axis[4]):
					fail("Unsupported sun direction scalar consumer.")
					return {}
				point.append(immediate_at(sky + int(axis[0]), 3) + (u16(sky + int(axis[2])) & 255))
			else:
				point.append(player_gun_constant(sky, axis))
		# The source negates Z after this table; native coordinate conversion
		# negates it again. These vectors align with the supplied sun meshes.
		directions.append(point)
	var images := []
	var count := immediate_at(constructor + 0xc, 0) / 4
	if count != 3 or u16(constructor + 0x3c) != 0x2c0c or u16(constructor + 0x3e) != 0xd1f4:
		fail("Unsupported flare sprite array.")
		return {}
	images.append(flight_image_binding(immediate_at(constructor + 0x14, 1)))
	for index in range(1, count):
		images.append(flight_image_binding(immediate_at(constructor + 0x18, 5) + index - 1))
	for offset in [0x14e, 0x1c2, 0x236, 0x2c4, 0x342, 0x3a4, 0x41a]:
		var expected := (
			"__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh"
			if offset == 0x14e
			else "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiiiihhh"
		)
		if call_target(render + offset) != symbol_address(expected):
			fail("Unsupported flare element draw consumer.")
			return {}
	if (
		call_target(render + 0x452)
		!= symbol_address("__ZN11AbyssEngine11PaintCanvas13FillRectangleEiiii")
	):
		fail("Unsupported lens glare wash consumer.")
		return {}
	var elements := [
		{"image": 0, "position": flare_fraction(render + 0x134, 16), "size": 1.0},
		{
			"image": 0,
			"position": flare_fraction(render + 0x184, 16),
			"size":
			float((1 << ((u16(render + 0x196) >> 6) & 31)) + 1) * flare_fraction(render + 0x1a0, 0)
		},
		{
			"image": 1,
			"position":
			(
				float((1 << ((u16(render + 0x1c8) >> 6) & 31)) + 1)
				* flare_fraction(render + 0x1d2, 16)
			),
			"size": flare_fraction(render + 0x216, 0)
		},
		{
			"image": 0,
			"position": flare_fraction(render + 0x284, 16),
			"size": float(1 << ((u16(render + 0x29e) >> 6) & 31)) / immediate_at(render + 0x298, 1),
			"minimum_strength": immediate_at(render + 0x252, 3) - (u16(render + 0x256) & 255)
		},
		{
			"image": 1,
			"position": 1.0 / immediate_at(render + 0x300, 1),
			"size": flare_fraction(render + 0x32a, 0)
		},
		{
			"image": 2,
			"position":
			(
				-float((1 << ((u16(render + 0x1c8) >> 6) & 31)) + 1)
				* flare_fraction(render + 0x1d2, 16)
			),
			"size": float(1 << ((u16(render + 0x388) >> 6) & 31))
		},
		{
			"image": 2,
			"position": -1.0 / immediate_at(render + 0x3d8, 1),
			"size": flare_fraction(render + 0x3fa, 0)
		}
	]
	var low := immediate_at(render + 0x3a, 3)
	var high := immediate_at(render + 0x38, 2)
	return (
		{
			"blend": "mix",
			"wash": true,
			"directions": directions,
			"images": images,
			"elements": elements,
			"tints": [[low, low, high], [low, high, low], [high, low, low], [high, high, high]],
			"strength_base": literal_float(render + 0xb4, 0),
			"strength_scale": literal_float(render + 0xba, 1),
			"alpha_bias": u16(render + 0x102) & 255,
			"large_alpha_bias": u16(render + 0x240) & 255
		}
		if error.is_empty()
		else {}
	)


func flare_fraction(address: int, fractional_bits: int) -> float:
	if (u16(address) & 0xf800) != 0x1000:
		fail("Unsupported flare scale constant.")
		return 0.0
	return pow(2.0, float(fractional_bits - ((u16(address) >> 6) & 31)))


func damage_presentation() -> Dictionary:
	# Semantic screen regions and original sprite declarations. Runtime uses
	# native camera projection, never the original instruction sequence.
	var hud := symbol_address("__ZN3HudC2Ev")
	var draw := symbol_address("__ZN3Hud4drawEixP9PlayerEgob")
	var update := symbol_address("__ZN9PlayerEgo6updateEiP18TargetFollowCamera")
	if hud != 0x26e6c or draw != 0x2761a or update != 0x5472c:
		fail("Unsupported damage indicator declaration layout.")
		return {}
	for link in [
		[0x26fb4, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x26fc2, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x277de, "__ZN9PlayerEgo12getAttackDirEv"],
		[0x27834, "__ZN11AbyssEngine18ApplicationManager20GetElapsedTimeMillisEv"],
		[0x278b2, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiiiihhh"],
		[0x2791a, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh"],
		[0x27984, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh"],
		[0x27a10, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiiiihhh"],
		[0x54dc4, "__ZN6Player12getHitVectorEv"],
		[0x54dcc, "__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE"],
		[0x54de4, "__ZN11AbyssEngine11PaintCanvas17GetScreenPositionERKNS_6AEMath6VectorERS2_"]
	]:
		if call_target(link[0]) != symbol_address(link[1]):
			fail("Unsupported damage indicator consumer at %x." % link[0])
			return {}
	for pair in [
		[0x26fb2, 0x3274],
		[0x26fc0, 0x3270],
		[0x277e4, 0x4210],
		[0x277f6, 0x4228],
		[0x27808, 0x4210],
		[0x2781a, 0x4218],
		[0x278a8, 0x9204],
		[0x27a0a, 0x9404],
		[0x54ef2, 0x4313],
		[0x54ef6, 0x4313],
		[0x54dfc, 0xda04],
		[0x54e1e, 0xdd04]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported damage indicator binding at %x." % pair[0])
			return {}
	var durations := []
	for address in [0x277ee, 0x27800, 0x27824, 0x27812]:
		durations.append(shifted_at(address, address + 2, 3))
	for index in 4:
		var address: int = [0x2784c, 0x278d4, 0x2793c, 0x279a6][index]
		if durations[index] != shifted_at(address, address + 6, 1):
			fail("Conflicting damage indicator fade duration.")
			return {}
	var center := u16(0x54ea2) & 255
	for address in [0x54eb6, 0x54eca, 0x54ede]:
		if (u16(address) & 255) != center:
			fail("Unsupported asymmetric center-hit region.")
			return {}
	var unit := shifted_at(0xf438, 0xf43a, 3)
	var all_edges := immediate_at(0x54eee, 2) | immediate_at(0x54ef4, 2)
	return (
		{
			"images":
			[
				flight_image_binding(literal(0x26fb0, 1)),
				flight_image_binding(shifted_at(0x26fba, 0x26fbe, 1))
			],
			"durations_ms": durations,
			"insets":
			[
				immediate_at(0x278ac, 2),
				immediate_at(0x27914, 2),
				immediate_at(0x2797e, 3),
				immediate_at(0x27a06, 3)
			],
			"masks":
			[
				immediate_at(0x277e2, 2),
				immediate_at(0x277f4, 5),
				immediate_at(0x27818, 3),
				immediate_at(0x27806, 2)
			],
			"flips": [immediate_at(0x278a2, 2), 0, 0, immediate_at(0x27a08, 4)],
			"front":
			{
				"sides": [signed_literal(0x54df0, 1), shifted_at(0x54e10, 0x54e12, 5)],
				"flags": immediate_at(0x54e3c, 3),
				"center": u16(0x54ea2) & 255,
				"center_flags": all_edges
			},
			"rear":
			{
				"limits":
				[
					signed_literal(0x54e4a, 3) / float(unit),
					signed_literal(0x54e56, 3) / float(unit),
					literal(0x54e72, 3) / float(unit),
					literal(0x54e62, 3) / float(unit)
				],
				"flags":
				[
					immediate_at(0x54e50, 3),
					immediate_at(0x54e5e, 3),
					immediate_at(0x54e44, 3),
					immediate_at(0x54e44, 3) | immediate_at(0x54e7e, 3),
					immediate_at(0x54e6c, 2)
				]
			}
		}
		if error.is_empty()
		else {}
	)



func sound_bank() -> Dictionary:
	var globals := symbol_address(
		"__ZN7Globals4initEPN11AbyssEngine18ApplicationManagerEPNS0_6EngineE"
	)
	var links := calls_between(
		globals,
		symbol_end(globals),
		"__ZN11AbyssEngine18ApplicationManager8SoundSetEPKNS_11AESoundInfoEi"
	)
	if links.size() != 1:
		fail("Unsupported sound resource registration.")
		return {}
	var at := int(links[0])
	var count := immediate_at(at - 4, 2)
	var table := literal(at - 6, 1)
	var lookup := symbol_address(
		"__ZN11AbyssEngine16AESoundRessource12getSoundInfoEiRNS_11AESoundInfoERi"
	)
	var stride := u16(lookup + 0x1c) & 255
	if (
		count < 1
		or count > 256
		or stride != 12
		or u16(lookup + 0x1c) != 0x320c
		or u16(lookup + 0x2e) != 0xc816
	):
		fail("Unsupported sound resource record layout.")
		return {}
	var initializer := symbol_address("__ZN11AbyssEngine16AESoundRessource4initEi")
	if (
		call_target(initializer + 0xa0) != symbol_address("__ZN11AbyssEngine7AESound9loadSoundEPKc")
		or call_target(initializer + 0xb0) != symbol_address("__ZN11AbyssEngine7AESound7setGainEi")
	):
		fail("Unsupported sound filename/gain consumer.")
		return {}
	var divisor := literal_float(symbol_address("__ZN11AbyssEngine7AESound7setGainEi") + 0x18, 1)
	if divisor <= 0:
		return {}
	var result := {}
	for index in count:
		var address := table + index * stride
		var id := u32(address)
		var path := embedded_string(u32(address + 4))
		if (
			result.has(str(id))
			or not path.begins_with("data/sounds/")
			or ".." in path
			or path.get_extension().to_lower() not in ["wav", "mp3"]
		):
			fail("Invalid supplied sound resource path or identity.")
			return {}
		result[str(id)] = {"path": path, "gain": u32(address + 8) / divisor}
	return result if error.is_empty() else {}


func player_hit_presentation() -> Dictionary:
	for address in [0x54d82, 0x54d2c]:
		if u16(address) & 0xff00 != 0x2800:
			fail("Unsupported player hit threshold comparison.")
			return {}
	for address in [0x54d44, 0x54d5c]:
		if u16(address) & 0xff00 != 0x3100:
			fail("Unsupported player hit sound group.")
			return {}
	for link in [
		[0x54318, "__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt"],
		[0x54330, "__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt"],
		[0x54d28, "__ZN6Player11getShieldHPEv"],
		[0x54d7e, "__ZN6Player11getShieldHPEv"],
		[0x54d3e, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x54d56, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x54d60, "__ZN11AbyssEngine18ApplicationManager9SoundPlayEi"],
		[0x54dba, "__ZN11AbyssEngine11PaintCanvas17TransformSetLocalEjRKNS_6AEMath6MatrixE"],
		[0x54120, "__ZN11AbyssEngine11PaintCanvas13DrawTransformEj"]
	]:
		if call_target(link[0]) != symbol_address(link[1]):
			fail("Unsupported player hit presentation consumer.")
			return {}
	for pair in [
		[0x54316, 0x6ce1],
		[0x5432a, 0x6d21],
		[0x54d2e, 0xdd0b],
		[0x54d0e, 0x2200],
		[0x54d10, 0x54ea],
		[0x54d78, 0x2201],
		[0x54d84, 0xdc0e]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported player hit effect selection.")
			return {}
	var sounds := {}
	for record in [["shield", 0x54d32, 0x54d44], ["hull", 0x54d4a, 0x54d5c]]:
		var ids := []
		for index in immediate_at(record[1], 1):
			ids.append((u16(record[2]) & 255) + index)
		sounds[record[0]] = ids
	return (
		{
			"models": {"hull": literal(0x54314, 2), "shield": literal(0x5432e, 2)},
			"visual_shield_above": u16(0x54d82) & 255,
			"sound_shield_above": u16(0x54d2c) & 255,
			"sounds": sounds,
			"lifetime": "simulation_step"
		}
		if error.is_empty()
		else {}
	)


func asteroid_destruction_audio(kind: int, layers: Array) -> Dictionary:
	var owner := symbol_address("__ZN16ExplosionHandler6updateEj")
	var targets := contract_choice_targets(owner + 0x52, owner)
	if kind < 0 or kind >= targets.size() or targets[kind] != owner + 0x66:
		fail("Unsupported asteroid destruction sound association.")
		return {}
	# The first explosion layer starts one sound. Delay and ID are supplied data;
	# native presentation observes that transition without running original code.
	for pair in [[0x66d18, 0x429a], [0x66d1a, 0xd370], [0x66d48, 0x2c00], [0x66d4a, 0xd12c]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported asteroid sound timing consumer.")
			return {}
	if call_target(0x66da0) != symbol_address("__ZN11AbyssEngine18ApplicationManager9SoundPlayEi"):
		fail("Unsupported asteroid sound playback consumer.")
		return {}
	return {"sound": immediate_at(0x66d4e, 1), "delay_ms": layers[0].delay_ms}





func actor_destruction(resources: Dictionary, actor_count: int) -> Dictionary:
	if not valid_destruction_lifecycle():
		return {}
	var owner := symbol_address("__ZN8KIPlayer15enableExplosionEv")
	for link in [0x686d6, 0x686f8, 0x68728, 0x6874e, 0x543f4]:
		if call_target(link) != symbol_address("__ZN16ExplosionHandlerC1E19ExplosionObjectType"):
			fail("Unsupported actor explosion binding.")
			return {}
	for pair in [
		[0x686a6, 0x6a53],
		[0x686aa, 0xd846],
		[0x686ae, 0x409a],
		[0x686b2, 0x421a],
		[0x686b4, 0xd116],
		[0x686b8, 0xd42c],
		[0x686be, 0x421a],
		[0x686c0, 0xd03b]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported actor explosion selection.")
			return {}
	for pair in [
		[0x65b12, 0x6c83],
		[0x65b18, 0xd900],
		[0x65e32, 0x648b],
		[0x662c2, 0x648b],
		[0x66a3a, 0x648b],
		[0x65cbe, 0x648b]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported explosion hull visibility consumer.")
			return {}
	var limit := u16(owner + 0x36) & 255
	var heavy := literal(owner + 0x3e, 3)
	var debris_bit := 31 - ((u16(owner + 0x44) >> 6) & 31)
	var small := shifted_at(owner + 0x48, owner + 0x4a, 3)
	var actors := []
	for index in actor_count:
		var kind := immediate_at(0x6874a, 1)
		if index <= limit:
			if heavy & (1 << index):
				kind = immediate_at(0x686f4, 1)
			elif index == debris_bit:
				kind = immediate_at(0x68724, 1)
			elif small & (1 << index):
				kind = immediate_at(0x686d2, 1)
		actors.append(kind)
	var factory := symbol_address("__ZN16ExplosionHandlerC2E19ExplosionObjectType")
	var table := factory + 0xaa
	if call_target(table - 4) != symbol_address("___switch32") or u32(table) != 5:
		fail("Unsupported actor explosion factory.")
		return {}
	for pair in [[0, 0x65dca], [2, 0x65fe6], [3, 0x662c8], [4, 0x65c8e]]:
		if table + u32(table + 4 + pair[0] * 4) != pair[1]:
			fail("Unsupported actor explosion factory association.")
			return {}
	for address in [0x65a16, 0x65a5a, 0x65a9c, 0x65ae2]:
		if (
			call_target(address)
			!= symbol_address("__ZN10iExplosion10initializeE13ExplosionPartijiii")
		):
			fail("Unsupported explosion constructor arguments.")
			return {}
	var effects := {}
	var mine := mine_explosion(0, resources)
	if mine.is_empty():
		return {}
	for layer in mine.layers:
		layer.rotation = actor_explosion_angles(actor_explosion_default_angles())
		layer.offset = [0, 0, 0]
		layer.fade_delay_ms = 0.0
		layer.fade_duration_ms = layer.duration_ms
	mine.hide_body_ms = immediate_at(0x65e2e, 3)
	mine.sounds = actor_explosion_sounds(0, mine.layers)
	effects["0"] = mine
	for kind in [2, 3]:
		var records := actor_explosion_records(kind)
		var layers := []
		for record in records:
			if (
				(
					call_target(record.call)
					!= symbol_address("__ZN10iExplosionC1E13ExplosionPart" + record.suffix)
				)
				or (
					call_target(record.append)
					!= symbol_address("__Z8ArrayAddIP10iExplosionEvT_R5ArrayIS2_E")
				)
				or (
					call_target(record.delay_call)
					!= symbol_address("__Z8ArrayAddIjEvT_R5ArrayIS0_E")
				)
			):
				fail("Unsupported actor explosion layer association.")
				return {}
			var part := player_gun_constant(0, record.part)
			var defaults := actor_explosion_defaults(part)
			if defaults.is_empty():
				return {}
			var rate := (
				player_gun_constant(0, record.rate) if record.has("rate") else int(defaults.rate)
			)
			var scale := (
				player_gun_constant(0, record.scale) if record.has("scale") else int(defaults.scale)
			)
			var rotation := actor_explosion_default_angles()
			if record.has("rotation"):
				for axis in 3:
					rotation[axis] = player_gun_constant(0, record.rotation[axis])
			var fade := 0
			if record.has("opacity"):
				if (
					call_target(record.opacity_call)
					!= symbol_address("__ZN10iExplosion20setOpacityStartFrameEj")
				):
					fail("Unsupported staged explosion fade.")
					return {}
				fade = player_gun_constant(0, record.opacity)
			layers.append(
				actor_explosion_layer(
					part, rate, scale, rotation, player_gun_constant(0, record.delay), fade
				)
			)
		if kind == 3:
			var offsets := heavy_explosion_offsets(layers.size())
			if offsets.size() != layers.size():
				return {}
			for index in layers.size():
				layers[index].offset = offsets[index]
		effects[str(kind)] = {
			"hide_body_ms": literal(0x662be if kind == 2 else 0x66a36, 3),
			"layers": layers,
			"alpha_start": mine.alpha_start,
			"alpha_end": mine.alpha_end,
			"alpha_cutoff": mine.alpha_cutoff,
			"sounds": actor_explosion_sounds(kind, layers)
		}
	var debris := debris_explosion_layers()
	effects["4"] = {
		"hide_body_ms": immediate_at(0x65cba, 3),
		"layers": debris,
		"alpha_start": mine.alpha_start,
		"alpha_end": mine.alpha_end,
		"alpha_cutoff": mine.alpha_cutoff,
		"sounds": actor_explosion_sounds(4, debris)
	}
	var player_camera := player_death_camera()
	var drift := wreck_drift()
	return (
		{
			"actors": actors,
			"player": immediate_at(0x543f0, 1),
			"player_camera_offset": player_camera,
			"drift": drift,
			"effects": effects
		}
		if error.is_empty()
		else {}
	)


func actor_explosion_defaults(part: int) -> Dictionary:
	var init := symbol_address("__ZN10iExplosion10initializeE13ExplosionPartijiii")
	var table := init + 0x80
	if call_target(table - 4) != symbol_address("___switch32") or part < 0 or part >= u32(table):
		fail("Unsupported explosion defaults.")
		return {}
	var target := table + u32(table + 4 + part * 4)
	match target:
		0x657c4:
			return {"rate": immediate_at(target + 4, 2), "scale": immediate_at(target + 4, 2)}
		0x657ce:
			return {"rate": immediate_at(target + 4, 2), "scale": immediate_at(target + 6, 1)}
		0x657dc, 0x657ee:
			return {"rate": immediate_at(target, 2), "scale": immediate_at(0x657f4, 0)}
		0x657e0:
			return {"rate": immediate_at(target + 4, 2), "scale": literal(target + 8, 2)}
		0x657fa:
			return {
				"rate": immediate_at(target + 4, 2), "scale": shifted_at(target + 8, target + 10, 2)
			}
	fail("Unsupported explosion default branch.")
	return {}


func actor_explosion_angles(value: Array) -> Array:
	var radians := literal_float(symbol_address("__ZN11AbyssEngine6AEMath3SinEi") + 8, 1)
	return [-value[0] * radians, -value[1] * radians, value[2] * radians]


func actor_explosion_layer(
	part: int, rate: int, scale: int, rotation: Array, delay: int, fade: int
) -> Dictionary:
	var init := symbol_address("__ZN10iExplosion10initializeE13ExplosionPartijiii")
	var ease := symbol_address("__ZN11AbyssEngine9EaseInOutC2Eii")
	var update := symbol_address("__ZN11AbyssEngine9EaseInOut18UpdateCurrentValueEv")
	var span := (immediate_at(update + 8, 3) << 9) - (immediate_at(ease + 4, 3) << 8)
	var period := float(span) * literal_float(init + 0x118, 1) / literal_float(init + 0x120, 0)
	var fade_period := float(span) * literal_float(0x652fa, 1) / literal_float(0x65308, 0)
	# The source stores fade rate as numerator / ((rate - frame) * divisor).
	# This duration is independent of the growth envelope for staged bursts.
	var fade_min := literal_float(0x652f2, 4)
	return {
		"mesh": literal(init + 0x1fa, 3) + part,
		"duration_ms": period * rate,
		"scale": float(scale) / immediate_at(init + 0x216, 1),
		"rotation": actor_explosion_angles(rotation),
		"offset": [0, 0, 0],
		"delay_ms": delay,
		"fade_delay_ms": fade * immediate_at(0x6530e, 1),
		"fade_duration_ms":
		period * rate if fade == 0 else fade_period * maxf(fade_min, rate - fade)
	}


func actor_explosion_sounds(kind: int, layers: Array) -> Array:
	var owner := symbol_address("__ZN16ExplosionHandler6updateEj")
	for address in [0x66d74, 0x66d8c, 0x66da0]:
		if (
			call_target(address)
			!= symbol_address("__ZN11AbyssEngine18ApplicationManager9SoundPlayEi")
		):
			fail("Unsupported actor explosion audio consumer.")
			return []
	var targets := contract_choice_targets(owner + 0x52, owner)
	if kind < 0 or kind >= targets.size() or layers.is_empty():
		fail("Missing actor explosion audio binding.")
		return []
	var records := []
	match int(targets[kind]):
		0x66d48:
			records = [[0x66d48, 0x66d4e]]
		0x66d56:
			records = [[0x66d56, 0x66d5c]]
		0x66d40:
			records = [[0x66d40, 0x66d9c]]
		0x66d64:
			records = [
				[0x66d64, 0x66d6e],
				[0x66d68, 0x66d6e],
				[0x66d78, 0x66d86],
				[0x66d7c, 0x66d86],
				[0x66d80, 0x66d86],
				[0x66d90, 0x66d9c],
				[0x66d94, 0x66d9c]
			]
		_:
			fail("Unsupported actor explosion audio choice.")
			return []
	var result := []
	for record in records:
		if u16(record[0]) & 0xff00 != 0x2c00:
			fail("Unsupported explosion audio stage.")
			return []
		var part := u16(record[0]) & 255
		if part >= layers.size():
			fail("Missing explosion audio stage.")
			return []
		result.append(
			{"layer": part, "sound": immediate_at(record[1], 1), "delay_ms": layers[part].delay_ms}
		)
	result.sort_custom(
		func(a, b):
			return a.delay_ms < b.delay_ms or (a.delay_ms == b.delay_ms and a.layer < b.layer)
	)
	return result


func heavy_explosion_offsets(count: int) -> Array:
	if (
		call_target(0x66dee) != symbol_address("__ZN10iExplosion9translateEiii")
		or u16(0x66ac2) != 0xd3f4
	):
		fail("Unsupported heavy explosion translation.")
		return []
	var points := [
		[immediate_at(0x66a42, 1), immediate_at(0x66a4a, 0), shifted_at(0x66a52, 0x66a54, 3)],
		[-immediate_at(0x66a5c, 3), -immediate_at(0x66a66, 3), -immediate_at(0x66a70, 3)],
		[immediate_at(0x66a4a, 0), immediate_at(0x66a7e, 2), signed_literal(0x66a86, 2)],
		[immediate_at(0x66a42, 1), immediate_at(0x66a42, 1), immediate_at(0x66a96, 2)]
	]
	var result := []
	var bindings := [
		0x66ac6, 0x66ac6, 0x66ad0, 0x66ad0, 0x66ad0, 0x66ad0, 0x66ae2, 0x66ae2, 0x66ae2, 0x66ae2
	]
	for index in count:
		var point := immediate_at(
			bindings[index] if index < bindings.size() else 0x66ab0,
			2 if index < bindings.size() else 1
		)
		if point >= points.size():
			fail("Invalid heavy explosion position.")
			return []
		var value: Array = points[point]
		result.append([value[0] * .02, value[1] * .02, -value[2] * .02])
	return result


func debris_explosion_layers() -> Array:
	for link in [0x65cd8, 0x65ce8, 0x65cf4, 0x65d00, 0x65d54, 0x65d66, 0x65d72, 0x65d7e]:
		if call_target(link) != symbol_address("__ZN11AbyssEngine8AERandom7nextIntEi"):
			fail("Unsupported debris variation source.")
			return []
	var first := actor_explosion_layer(
		immediate_at(0x65c9e, 1),
		immediate_at(0x65ca0, 2),
		int(actor_explosion_defaults(immediate_at(0x65c9e, 1)).scale),
		actor_explosion_default_angles(),
		immediate_at(0x65cbc, 0),
		0
	)
	var second := actor_explosion_layer(
		immediate_at(0x65d20, 1),
		immediate_at(0x65d22, 2),
		u16(0x65d1e) & 255,
		[0, 0, 0],
		immediate_at(0x65d3c, 0),
		0
	)
	var third := actor_explosion_layer(
		immediate_at(0x65da8, 1),
		immediate_at(0x65daa, 2),
		shifted_at(0x65d8c, 0x65d8e, 1),
		[0, 0, 0],
		immediate_at(0x65dc4, 0),
		0
	)
	second.scale_steps = literal(0x65cca, 1)
	third.scale_steps = literal(0x65d46, 1)
	second.scale_span = float(literal(0x65cca, 1)) / immediate_at(0x65936, 1)
	third.scale_span = float(literal(0x65d46, 1)) / immediate_at(0x65936, 1)
	var angle := shifted_at(0x65cde, 0x65ce0, 1)
	second.rotation_steps = angle
	second.rotation_span = actor_explosion_angles([angle, angle, angle])
	angle = shifted_at(0x65d5a, 0x65d5c, 2)
	third.rotation_steps = angle
	third.rotation_span = actor_explosion_angles([-angle, -angle, -angle])
	return [first, second, third]


func actor_explosion_records(kind: int) -> Array:
	match kind:
		2:
			return [
				{
					"call": 0x65ffa,
					"suffix": "",
					"append": 0x6600a,
					"delay_call": 0x66014,
					"part": [0x65ff6, 1, -1, -1, 0],
					"delay": [0x66010, 0, -1, -1, 0]
				},
				{
					"call": 0x66030,
					"suffix": "ij",
					"append": 0x66040,
					"delay_call": 0x66050,
					"part": [0x66028, 1, -1, -1, 0],
					"delay": [0x66048, 0, -1, -1, 0],
					"rate": [0x6602a, 2, -1, -1, 0],
					"scale": [0x6602c, 3, -1, -1, 0]
				},
				{
					"call": 0x6606c,
					"suffix": "ij",
					"append": 0x6607c,
					"delay_call": 0x66086,
					"part": [0x66064, 1, -1, -1, 0],
					"delay": [0x66082, 0, -1, -1, 0],
					"rate": [0x66066, 2, -1, -1, 0],
					"scale": [0x66068, 3, -1, -1, 0]
				},
				{
					"call": 0x660a2,
					"suffix": "ij",
					"append": 0x660b2,
					"delay_call": 0x660be,
					"part": [0x6609a, 1, -1, -1, 0],
					"delay": [0x660b8, 0, 0x660ba, -1, 0],
					"rate": [0x6609c, 2, -1, -1, 0],
					"scale": [0x6609e, 3, -1, -1, 0]
				},
				{
					"call": 0x660ea,
					"suffix": "ijiii",
					"append": 0x660fa,
					"delay_call": 0x66106,
					"part": [0x660e2, 1, -1, -1, 0],
					"delay": [0x66100, 0, 0x66102, -1, 0],
					"rate": [0x660e4, 2, -1, -1, 0],
					"scale": [0x660e6, 3, -1, -1, 0],
					"rotation":
					[
						[0x660ce, 3, 0x660d0, 0x660d2, 0x9300],
						[0x660d4, 3, 0x660d6, 0x660d8, 0x9301],
						[0x660da, 3, -1, 0x660dc, 0x9302]
					]
				},
				{
					"call": 0x6612e,
					"suffix": "ijiii",
					"append": 0x6613e,
					"delay_call": 0x66148,
					"part": [0x66118, 1, -1, -1, 0],
					"delay": [0x66144, 0, -1, -1, 0],
					"rate": [0x6611a, 2, -1, -1, 0],
					"scale": [0x6612a, 3, -1, -1, 0],
					"rotation":
					[
						[0x66116, 3, -1, 0x6611c, 0x9300],
						[0x6611e, 3, -1, 0x66120, 0x9301],
						[0x66122, 3, -1, 0x66124, 0x9302]
					]
				},
				{
					"call": 0x66170,
					"suffix": "ijiii",
					"append": 0x66180,
					"delay_call": 0x6618a,
					"part": [0x6615a, 1, -1, -1, 0],
					"delay": [0x66186, 0, -1, -1, 0],
					"rate": [0x6615c, 2, -1, -1, 0],
					"scale": [0x6616c, 3, -1, -1, 0],
					"rotation":
					[
						[0x66158, 3, -1, 0x6615e, 0x9300],
						[0x66160, 3, -1, 0x66162, 0x9301],
						[0x66164, 3, -1, 0x66166, 0x9302]
					]
				},
				{
					"call": 0x661b2,
					"suffix": "ijiii",
					"append": 0x661c2,
					"delay_call": 0x661cc,
					"part": [0x6619c, 1, -1, -1, 0],
					"delay": [0x661c8, 0, -1, -1, 0],
					"rate": [0x6619e, 2, -1, -1, 0],
					"scale": [0x661ae, 3, -1, -1, 0],
					"rotation":
					[
						[0x6619a, 3, -1, 0x661a0, 0x9300],
						[0x661a2, 3, -1, 0x661a4, 0x9301],
						[0x661a6, 3, -1, 0x661a8, 0x9302]
					]
				},
				{
					"call": 0x661f4,
					"suffix": "ijiii",
					"append": 0x66204,
					"delay_call": 0x66210,
					"part": [0x661de, 1, -1, -1, 0],
					"delay": [0x6620a, 0, 0x6620c, -1, 0],
					"rate": [0x661e0, 2, -1, -1, 0],
					"scale": [0x661f0, 3, -1, -1, 0],
					"rotation":
					[
						[0x661dc, 3, -1, 0x661e2, 0x9300],
						[0x661e4, 3, -1, 0x661e6, 0x9301],
						[0x661e8, 3, -1, 0x661ea, 0x9302]
					]
				},
				{
					"call": 0x66238,
					"suffix": "ijiii",
					"append": 0x66248,
					"delay_call": 0x66254,
					"part": [0x66222, 1, -1, -1, 0],
					"delay": [0x6624e, 0, 0x66250, -1, 0],
					"rate": [0x66224, 2, -1, -1, 0],
					"scale": [0x66234, 3, -1, -1, 0],
					"rotation":
					[
						[0x66220, 3, -1, 0x66226, 0x9300],
						[0x66228, 3, -1, 0x6622a, 0x9301],
						[0x6622c, 3, -1, 0x6622e, 0x9302]
					]
				},
				{
					"call": 0x6626c,
					"suffix": "",
					"append": 0x6627c,
					"delay_call": 0x66288,
					"part": [0x66268, 1, -1, -1, 0],
					"delay": [0x66282, 0, 0x66284, -1, 0]
				},
				{
					"call": 0x662a0,
					"suffix": "",
					"append": 0x662b0,
					"delay_call": 0x662ba,
					"part": [0x6629c, 1, -1, -1, 0],
					"delay": [0x662b6, 0, -1, -1, 0]
				},
			]
		3:
			return [
				{
					"call": 0x662ea,
					"suffix": "ijiii",
					"append": 0x662fa,
					"delay_call": 0x6631e,
					"part": [0x662e4, 1, -1, -1, 0],
					"delay": [0x6631a, 0, -1, -1, 0],
					"rate": [0x662e6, 2, -1, -1, 0],
					"scale": [0x662d6, 3, 0x662e2, -1, 0],
					"rotation":
					[
						[0x662d4, 2, -1, 0x662d8, 0x9200],
						[0x662d4, 2, -1, 0x662da, 0x9201],
						[0x662d4, 2, -1, 0x662dc, 0x9202]
					],
					"opacity_call": 0x66314,
					"opacity": [0x66300, 1, -1, -1, 0]
				},
				{
					"call": 0x6633c,
					"suffix": "ijiii",
					"append": 0x6638e,
					"delay_call": 0x663b2,
					"part": [0x66334, 1, -1, -1, 0],
					"delay": [0x663ae, 0, -1, -1, 0],
					"rate": [0x66336, 2, -1, -1, 0],
					"scale": [0x66338, 3, -1, -1, 0],
					"rotation":
					[
						[0x66328, 3, -1, 0x6632a, 0x9300],
						[0x66328, 3, -1, 0x6632c, 0x9301],
						[0x66328, 3, -1, 0x6632e, 0x9302]
					],
					"opacity_call": 0x663a8,
					"opacity": [0x66396, 1, -1, -1, 0]
				},
				{
					"call": 0x663d0,
					"suffix": "ijiii",
					"append": 0x663e0,
					"delay_call": 0x66406,
					"part": [0x663c8, 1, -1, -1, 0],
					"delay": [0x66400, 0, 0x66402, -1, 0],
					"rate": [0x663ca, 2, -1, -1, 0],
					"scale": [0x663cc, 3, -1, -1, 0],
					"rotation":
					[
						[0x663bc, 3, -1, 0x663be, 0x9300],
						[0x663bc, 3, -1, 0x663c0, 0x9301],
						[0x663bc, 3, -1, 0x663c2, 0x9302]
					],
					"opacity_call": 0x663fa,
					"opacity": [0x663e8, 1, -1, -1, 0]
				},
				{
					"call": 0x66424,
					"suffix": "ijiii",
					"append": 0x66434,
					"delay_call": 0x6645a,
					"part": [0x6641c, 1, -1, -1, 0],
					"delay": [0x66454, 0, 0x66456, -1, 0],
					"rate": [0x6641e, 2, -1, -1, 0],
					"scale": [0x66420, 3, -1, -1, 0],
					"rotation":
					[
						[0x66410, 3, -1, 0x66412, 0x9300],
						[0x66410, 3, -1, 0x66414, 0x9301],
						[0x66410, 3, -1, 0x66416, 0x9302]
					],
					"opacity_call": 0x6644e,
					"opacity": [0x6643c, 1, -1, -1, 0]
				},
				{
					"call": 0x6646e,
					"suffix": "i",
					"append": 0x6647e,
					"delay_call": 0x664a2,
					"part": [0x66468, 1, -1, -1, 0],
					"delay": [0x6649e, 0, -1, -1, 0],
					"rate": [0x6646a, 2, -1, -1, 0],
					"opacity_call": 0x66498,
					"opacity": [0x66486, 1, -1, -1, 0]
				},
				{
					"call": 0x664c4,
					"suffix": "ijiii",
					"append": 0x664d6,
					"delay_call": 0x664fa,
					"part": [0x664b6, 1, -1, -1, 0],
					"delay": [0x664f6, 0, -1, -1, 0],
					"rate": [0x664b8, 2, -1, -1, 0],
					"scale": [0x664c0, 3, -1, -1, 0],
					"rotation":
					[
						[0x664ac, 3, -1, 0x664ae, 0x9300],
						[0x664b0, 3, -1, 0x664b2, 0x9301],
						[0x664b4, 3, -1, 0x664ba, 0x9302]
					],
					"opacity_call": 0x664f0,
					"opacity": [0x664de, 1, -1, -1, 0]
				},
				{
					"call": 0x66518,
					"suffix": "ijiii",
					"append": 0x6652a,
					"delay_call": 0x6654e,
					"part": [0x66510, 1, -1, -1, 0],
					"delay": [0x6654a, 0, -1, -1, 0],
					"rate": [0x66512, 2, -1, -1, 0],
					"scale": [0x66514, 3, -1, -1, 0],
					"rotation":
					[
						[0x66504, 3, -1, 0x66506, 0x9300],
						[0x66504, 3, -1, 0x66508, 0x9301],
						[0x66504, 3, -1, 0x6650a, 0x9302]
					],
					"opacity_call": 0x66544,
					"opacity": [0x66532, 1, -1, -1, 0]
				},
				{
					"call": 0x66564,
					"suffix": "ij",
					"append": 0x66576,
					"delay_call": 0x6659a,
					"part": [0x6655c, 1, -1, -1, 0],
					"delay": [0x66596, 0, -1, -1, 0],
					"rate": [0x6655e, 2, -1, -1, 0],
					"scale": [0x66560, 3, -1, -1, 0],
					"opacity_call": 0x66590,
					"opacity": [0x6657e, 1, -1, -1, 0]
				},
				{
					"call": 0x665bc,
					"suffix": "ijiii",
					"append": 0x665ce,
					"delay_call": 0x665da,
					"part": [0x665a6, 1, -1, -1, 0],
					"delay": [0x665d4, 0, 0x665d6, -1, 0],
					"rate": [0x665a8, 2, -1, -1, 0],
					"scale": [0x665b8, 3, -1, -1, 0],
					"rotation":
					[
						[0x665a4, 3, -1, 0x665aa, 0x9300],
						[0x665ac, 3, -1, 0x665ae, 0x9301],
						[0x665b0, 3, -1, 0x665b2, 0x9302]
					]
				},
				{
					"call": 0x66602,
					"suffix": "ijiii",
					"append": 0x66614,
					"delay_call": 0x66620,
					"part": [0x665f0, 1, -1, -1, 0],
					"delay": [0x6661a, 0, 0x6661c, -1, 0],
					"rate": [0x665f2, 2, -1, -1, 0],
					"scale": [0x665fe, 3, -1, -1, 0],
					"rotation":
					[
						[0x665ea, 3, -1, 0x665ec, 0x9300],
						[0x665ee, 3, -1, 0x665f4, 0x9301],
						[0x665f6, 3, -1, 0x665f8, 0x9302]
					]
				},
				{
					"call": 0x6663e,
					"suffix": "ij",
					"append": 0x66650,
					"delay_call": 0x66674,
					"part": [0x66638, 1, -1, -1, 0],
					"delay": [0x66670, 0, -1, -1, 0],
					"rate": [0x6663a, 2, -1, -1, 0],
					"scale": [0x66632, 3, 0x66636, -1, 0],
					"opacity_call": 0x6666a,
					"opacity": [0x66658, 1, -1, -1, 0]
				},
				{
					"call": 0x66698,
					"suffix": "ijiii",
					"append": 0x666aa,
					"delay_call": 0x666ce,
					"part": [0x66692, 1, -1, -1, 0],
					"delay": [0x666ca, 0, -1, -1, 0],
					"rate": [0x66694, 2, -1, -1, 0],
					"scale": [0x66680, 3, 0x66682, -1, 0],
					"rotation":
					[
						[0x6667e, 2, -1, 0x66684, 0x9200],
						[0x66686, 2, -1, 0x66688, 0x9201],
						[0x6668a, 2, -1, 0x6668c, 0x9202]
					],
					"opacity_call": 0x666c4,
					"opacity": [0x666b2, 1, -1, -1, 0]
				},
				{
					"call": 0x666f2,
					"suffix": "ijiii",
					"append": 0x66704,
					"delay_call": 0x66728,
					"part": [0x666ec, 1, -1, -1, 0],
					"delay": [0x66724, 0, -1, -1, 0],
					"rate": [0x666ee, 2, -1, -1, 0],
					"scale": [0x666da, 3, 0x666dc, -1, 0],
					"rotation":
					[
						[0x666d8, 2, -1, 0x666de, 0x9200],
						[0x666e0, 2, -1, 0x666e2, 0x9201],
						[0x666e4, 2, -1, 0x666e6, 0x9202]
					],
					"opacity_call": 0x6671e,
					"opacity": [0x6670c, 1, -1, -1, 0]
				},
				{
					"call": 0x6673e,
					"suffix": "ij",
					"append": 0x66750,
					"delay_call": 0x66774,
					"part": [0x66736, 1, -1, -1, 0],
					"delay": [0x66770, 0, -1, -1, 0],
					"rate": [0x66738, 2, -1, -1, 0],
					"scale": [0x6673a, 3, -1, -1, 0],
					"opacity_call": 0x6676a,
					"opacity": [0x66758, 1, -1, -1, 0]
				},
				{
					"call": 0x66796,
					"suffix": "ijiii",
					"append": 0x667a8,
					"delay_call": 0x667cc,
					"part": [0x66780, 1, -1, -1, 0],
					"delay": [0x667c8, 0, -1, -1, 0],
					"rate": [0x66782, 2, -1, -1, 0],
					"scale": [0x66792, 3, -1, -1, 0],
					"rotation":
					[
						[0x6677e, 3, -1, 0x66784, 0x9300],
						[0x66786, 3, -1, 0x66788, 0x9301],
						[0x6678a, 3, -1, 0x6678c, 0x9302]
					],
					"opacity_call": 0x667c2,
					"opacity": [0x667b0, 1, -1, -1, 0]
				},
				{
					"call": 0x667ee,
					"suffix": "ijiii",
					"append": 0x66800,
					"delay_call": 0x66824,
					"part": [0x667dc, 1, -1, -1, 0],
					"delay": [0x66820, 0, -1, -1, 0],
					"rate": [0x667de, 2, -1, -1, 0],
					"scale": [0x667ea, 3, -1, -1, 0],
					"rotation":
					[
						[0x667d6, 3, -1, 0x667d8, 0x9300],
						[0x667da, 3, -1, 0x667e0, 0x9301],
						[0x667e2, 3, -1, 0x667e4, 0x9302]
					],
					"opacity_call": 0x6681a,
					"opacity": [0x66808, 1, -1, -1, 0]
				},
				{
					"call": 0x6684a,
					"suffix": "ijiii",
					"append": 0x6688e,
					"delay_call": 0x668b2,
					"part": [0x66836, 1, -1, -1, 0],
					"delay": [0x668ae, 0, -1, -1, 0],
					"rate": [0x66838, 2, -1, -1, 0],
					"scale": [0x66846, 3, -1, -1, 0],
					"rotation":
					[
						[0x6682e, 3, 0x66830, 0x66832, 0x9300],
						[0x66834, 3, -1, 0x6683a, 0x9301],
						[0x6683c, 3, 0x6683e, 0x66840, 0x9302]
					],
					"opacity_call": 0x668a8,
					"opacity": [0x66896, 1, -1, -1, 0]
				},
				{
					"call": 0x668d4,
					"suffix": "ijiii",
					"append": 0x66a0a,
					"delay_call": 0x66a30,
					"part": [0x668c2, 1, -1, -1, 0],
					"delay": [0x66a2a, 0, 0x66a2c, -1, 0],
					"rate": [0x668c4, 2, -1, -1, 0],
					"scale": [0x668d0, 3, -1, -1, 0],
					"rotation":
					[
						[0x668bc, 3, -1, 0x668be, 0x9300],
						[0x668c0, 3, -1, 0x668c6, 0x9301],
						[0x668c8, 3, -1, 0x668ca, 0x9302]
					],
					"opacity_call": 0x66a24,
					"opacity": [0x66a10, 1, -1, -1, 0]
				},
			]
	return []


func actor_explosion_default_angles() -> Array:
	for pair in [[0x65a08, 0x4252], [0x65a10, 0x9200], [0x65a12, 0x9201], [0x65a14, 0x9202]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported explosion rotation defaults.")
	var angle := -immediate_at(0x65a06, 2)
	return [angle, angle, angle]


func player_death_camera() -> Array:
	for binding in [
		[0x53fe6, "__ZN16ExplosionHandler5startEN11AbyssEngine6AEMath6MatrixE"],
		[0x53fee, "__ZN6Player9setActiveEb"],
		[0x540fc, "__ZN16ExplosionHandler16isTimeToHideShipEv"],
		[0x4480e, "__ZN18TargetFollowCamera12setLookAtCamEb"],
		[0x44830, "__ZN11AbyssEngine11PaintCanvas14CameraGetLocalEj"],
		[0x4483a, "__ZN11AbyssEngine6AEMath21MatrixTransformVectorERKNS0_6MatrixERKNS0_6VectorE"],
		[0x44850, "__ZN18TargetFollowCamera11setPositionEiii"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported player destruction/camera consumer.")
			return []
	if u16(0x44818) != 0x9326 or u16(0x4481a) != 0x9327 or u16(0x44822) != 0x9328:
		fail("Unsupported player defeat camera vector.")
		return []
	var lateral := shifted_at(0x44814, 0x44816, 3) * .02
	return [lateral, lateral, -signed_literal(0x4481e, 3) * .02]


func valid_destruction_lifecycle() -> bool:
	for binding in [
		[0x566e8, "__ZN16ExplosionHandler11hasFinishedEv"],
		[0x66b9a, "__ZN10iExplosion11hasFinishedEv"],
		[0x50d3c, "__ZN8KIPlayer6isDeadEv"],
		[0x50d94, "__ZN8KIPlayer6isDeadEv"],
		[0x3ab0e, "__ZN8KIPlayer6isDeadEv"],
		[0x29860, "__ZN8KIPlayer6isDeadEv"],
		[0x5979a, "__ZN6Player6isDeadEv"],
		[0x59816, "__ZN6Player6isDeadEv"],
		[0x59844, "__ZN6Player6isDeadEv"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported distinction between casualties and finished wrecks.")
			return false
	if u16(0x684b4) != 0x2b04 or u16(0x566f0) != 0x2304 or u16(0x566ee) != 0xd001:
		fail("Unsupported actor destruction completion state.")
		return false
	return true


func wreck_drift() -> Dictionary:
	# Bind the fighter's speed retention to the app's requested animation timer,
	# not the separate accelerometer interval or the renderer's refresh rate.
	for binding in [
		["-[AppController applicationDidFinishLaunching:]", 0xfc40],
		["-[AppView setAnimationInterval:]", 0x1058c],
		["-[AppView startAnimation]", 0x105f0],
		["-[AppView drawView]", 0x10fcc],
		["__ZN13PlayerFighter6updateEi", 0x55a80]
	]:
		if symbol_address(binding[0]) != binding[1]:
			fail("Unsupported wreck motion or animation timer layout.")
			return {}
	for selector in [
		[0xfed0, 1, "setAnimationInterval:"],
		[0xfee0, 1, "startAnimation"],
		[0x105f8, 1, "scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:"],
		[0x10610, 0, "drawView"]
	]:
		if embedded_string(u32(literal(selector[0], selector[1]))) != selector[2]:
			fail("Unsupported animation timer association.")
			return {}
	var imports := imported_symbols()
	for binding in [
		[0xfeda, "_objc_msgSend"],
		[0xfee6, "_objc_msgSend"],
		[0x10620, "_objc_msgSend"],
		[0x56682, "___mulsf3vfp"],
		[0x5668c, "___floatsisfvfp"],
		[0x56694, "___mulsf3vfp"]
	]:
		if not imports.get(binding[1], []).has(call_target(binding[0])):
			fail("Unsupported wreck damping or timer consumer.")
			return {}
	for pair in [
		[0xfed4, 0x58e8],
		[0xfed6, 0x6809],
		[0xfee2, 0x58e8],
		[0xfee4, 0x6809],
		[0x10594, 0x6809],
		[0x10596, 0x1841],
		[0x10598, 0x600a],
		[0x1059a, 0x604b],
		[0x10606, 0x681a],
		[0x10608, 0x1882],
		[0x1060a, 0x6853],
		[0x1060c, 0x6812],
		[0x1060e, 0x9000],
		[0x10612, 0x6800],
		[0x10614, 0x9001],
		[0x1061a, 0x2001],
		[0x1061c, 0x9003],
		[0x5667a, 0x2482],
		[0x5667c, 0x64],
		[0x56680, 0x5930],
		[0x56686, 0x5130],
		[0x5668a, 0x4650]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported wreck speed or timer argument binding.")
			return {}
	if (
		literal(0x10590, 1) != literal(0x10604, 3)
		or (
			call_target(0x114c4)
			!= symbol_address("__ZN11AbyssEngine18ApplicationManager8OnUpdateEx")
		)
		or (
			call_target(0x566da)
			!= symbol_address(
				"__ZN16ExplosionHandler14setTranslationERKN11AbyssEngine6AEMath6VectorE"
			)
		)
	):
		fail("Unsupported animation interval or moving explosion binding.")
		return {}
	var interval := PackedByteArray()
	interval.resize(8)
	interval.encode_u32(0, literal(0xfed2, 2))
	interval.encode_u32(4, literal(0xfed8, 3))
	var result := {
		"retention": literal_float(0x5667e, 1), "reference_seconds": interval.decode_double(0)
	}
	if not preload("res://src/simulation/actor_destruction.gd").valid_motion(result):
		fail("Invalid supplied wreck damping constants.")
		return {}
	return result


func fighter_steering() -> Dictionary:
	# The fighter update has its own direction-change gains. KIPlayer's generic
	# rotation-speed field is not consumed by this movement path.
	for pair in [
		[0x564a0, 0x23ed],
		[0x564a2, 0x5cf3],
		[0x564a4, 0x2b00],
		[0x564a6, 0xd102],
		[0x564a8, 0x6a73],
		[0x564ac, 0xd122],
		[0x564ae, 0x4652],
		[0x564b2, 0xe023],
		[0x564f4, 0x4653],
		[0x564f8, 0x4451],
		[0x56560, 0x4298],
		[0x56562, 0xdc03],
		[0x5594e, 0xd008],
		[0x55954, 0xd14a],
		[0x55960, 0xd144],
		[0x55964, 0x23ed],
		[0x55966, 0x2201],
		[0x55968, 0x54ca],
		[0x559ee, 0x23ed],
		[0x559f0, 0x2200],
		[0x559f2, 0x54ca]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported fighter steering association.")
			return {}
	for pair in [[0x564aa, 0x2b00], [0x5594c, 0x2800], [0x55952, 0x2a00], [0x5595e, 0x2800]]:
		if u16(pair[0]) & 0xff00 != pair[1]:
			fail("Unsupported enhanced steering selector.")
			return {}
	for pair in [[0x564b0, 0x0011], [0x564f6, 0x0019], [0x564fa, 0x0009]]:
		if u16(pair[0]) & 0xf83f != pair[1]:
			fail("Unsupported fighter direction gain declaration.")
			return {}
	for binding in [
		[0x56570, "__ZN11AbyssEngine6AEMath11MatrixGetUpERKNS0_6MatrixE"],
		[0x5657a, "__ZN11AbyssEngine6AEMath11VectorCrossERKNS0_6VectorES3_"],
		[0x56594, "__ZN11AbyssEngine6AEMath11VectorCrossERKNS0_6VectorES3_"],
		[0x565b2, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixERKNS0_6VectorES5_S5_"],
		[0x56484, "__ZN11AbyssEngine6AEMath12MatrixGetDirERKNS0_6MatrixE"],
		[0x5648c, "__ZN11AbyssEngine6AEMath6VectormIERKS1_"],
		[0x56494, "__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE"],
		[0x564fe, "__ZN11AbyssEngine6AEMath6VectormLEi"],
		[0x56508, "__ZN11AbyssEngine6AEMathplERKNS0_6VectorES3_"],
		[0x56524, "__ZN11AbyssEngine6AEMath15VectorNormalizeERKNS0_6VectorE"],
		[0x56568, "__ZN11AbyssEngine6AEMath6VectoraSERKS1_"],
		[0x55948, "__ZN6Status18getCampaignMissionEv"],
		[0x5595a, "__ZN6Status18getCampaignMissionEv"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported fighter steering consumer.")
			return {}
	# Scalar multiply divides both operands by four before the 64-bit product,
	# then shifts by twelve: the existing normalized vector unit supplies 16 bits.
	if u16(0xf270) != 0x108b or u16(0xf276) != 0x1081 or u16(0xf286) != 0x0b00:
		fail("Unsupported direction gain units.")
		return {}
	var unit := normalized_vector_unit()
	var normal := (1 + (1 << ((u16(0x564f6) >> 6) & 31))) << ((u16(0x564fa) >> 6) & 31)
	var enhanced := 1 << ((u16(0x564b0) >> 6) & 31)
	return (
		{
			"normal_rate": float(normal) * 1000.0 / unit,
			"enhanced_rate": float(enhanced) * 1000.0 / unit,
			"snap_distance": float(literal(0x5655e, 3)) / unit,
			"enhanced_actor": u16(0x564aa) & 255,
			"enhanced_chapter": u16(0x5594c) & 255,
			"special_actor": u16(0x55952) & 255,
			"special_chapter": u16(0x5595e) & 255
		}
		if error.is_empty()
		else {}
	)


func fighter_evasion() -> Dictionary:
	var owner := symbol_address("__ZN13PlayerFighter6updateEi")
	var choices := contract_choice_targets(0x56062, owner)
	if (
		choices != [0x5606c, 0x56080, 0x56098, 0x560ac]
		or immediate_at(0x56056, 1) != choices.size()
	):
		fail("Unsupported fighter avoidance choices.")
		return {}
	for pair in [
		[0x56016, 0x23c4],
		[0x56018, 0x5cf0],
		[0x56024, 0x23e0],
		[0x56026, 0x58f3],
		[0x5602a, 0xda66],
		[0x56030, 0xdd63],
		[0x56038, 0xdd5f],
		[0x5603c, 0xda5d],
		[0x56044, 0xdd59],
		[0x56048, 0xda57],
		[0x5604a, 0x22dc],
		[0x5604c, 0x5cb3],
		[0x56050, 0xd03d],
		[0x56052, 0x54b0],
		[0x56078, 0x3498],
		[0x56088, 0x3498],
		[0x560a4, 0x3498],
		[0x560b4, 0x3498],
		[0x560cc, 0xe001],
		[0x560ce, 0x1c34],
		[0x560d0, 0x3498],
		[0x56192, 0x23dc],
		[0x56194, 0x2201],
		[0x56196, 0x54f2],
		[0x55970, 0x50ca],
		[0x558e4, 0x508b]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported persistent avoidance or axis-box consumer.")
			return {}
	for binding in [
		[0x5605c, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x56074, "__ZN11AbyssEngine6AEMath11MatrixGetUpERKNS0_6MatrixE"],
		[0x5608a, "__ZN11AbyssEngine6AEMath14MatrixGetRightERKNS0_6MatrixE"],
		[0x560a0, "__ZN11AbyssEngine6AEMath11MatrixGetUpERKNS0_6MatrixE"],
		[0x560b6, "__ZN11AbyssEngine6AEMath14MatrixGetRightERKNS0_6MatrixE"],
		[0x560c8, "__ZN11AbyssEngine6AEMath6VectormLEi"],
		[0x560d6, "__ZN11AbyssEngine6AEMath6VectoraSERKS1_"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported source avoidance direction.")
			return {}
	var scale := float(shifted_at(0x560c2, 0x560c6, 1)) / normalized_vector_unit()
	# The last two source choices multiply by positive one, not minus one.
	# Preserve their weighting instead of inventing down/left alternatives.
	var result := {
		"directions": [[0, 1, 0], [1, 0, 0], [0, scale, 0], [scale, 0, 0]],
		"heavy_half_width": float(literal(0x558e2, 3)) * .02,
		"special_half_width": float(literal(0x5596c, 2)) * .02
	}
	if not preload("res://src/simulation/fighter_evasion.gd").valid_data(result):
		fail("Invalid supplied fighter avoidance constants.")
		return {}
	return result if error.is_empty() else {}


func fighter_motion() -> Dictionary:
	# Recover operative current-speed constants, not the generic +1c base field.
	for pair in [
		[0x52ea6, 0x6d03], [0x52ea8, 0x6481], [0x52eaa, 0x4299],
		[0x52eac, 0xdd00], [0x52eae, 0x6501],
		[0x561b0, 0xda25],
		[0x561ea, 0xd008],
		[0x56206, 0xdd26],
		[0x5621c, 0xd107],
		[0x56264, 0xd00f],
		[0x56270, 0xdd09],
		[0x5628e, 0xd01c],
		[0x562a4, 0xd00c],
		[0x562ea, 0xd00b],
		[0x560da, 0x6a73],
		[0x560dc, 0x2b12],
		[0x560de, 0xd003],
		[0x560e0, 0x23ed],
		[0x560e2, 0x5cf3],
		[0x560e6, 0xd057],
		[0x5613a, 0x23ed],
		[0x56142, 0xd01d],
		[0x5610e, 0xda0e],
		[0x56114, 0xdd0b],
		[0x5611c, 0xdd07],
		[0x56120, 0xda05],
		[0x56128, 0xdd01],
		[0x5612c, 0xdb31],
		[0x55a08, 0x2382],
		[0x55a0a, 0x005b],
		[0x55a0e, 0x50ca],
		[0x565c4, 0x2382],
		[0x565c6, 0x005b],
		[0x565c8, 0x58f1],
		[0x68494, 0x61c1],
		[0x557f4, 0xd04e],
		[0x557f8, 0xd04c],
		[0x55800, 0x3b01],
		[0x55808, 0xd044],
		[0x5580c, 0xd042],
		[0x55882, 0x2a00],
		[0x55884, 0xd006],
		[0x5588a, 0xd003],
		[0x5588e, 0x23b4],
		[0x55890, 0x2201],
		[0x55892, 0x54ca],
		[0x55972, 0x23b4],
		[0x55974, 0x2200],
		[0x55976, 0x54ca],
		[0x56198, 0x23b4],
		[0x5619a, 0x5cf3],
		[0x5619e, 0xd100],
		[0x56214, 0xdc1f],
		[0x5622c, 0xdc0a],
		[0x56240, 0x1840],
		[0x56242, 0x50f0],
		[0x56248, 0x50f1],
		[0x5624a, 0x2384],
		[0x5624c, 0x005b],
		[0x5624e, 0x2201],
		[0x56250, 0x54f2]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported fighter current-speed or boost state binding.")
			return {}
	for pair in [
		[0x557f2, 0x2a00],
		[0x557f6, 0x2a00],
		[0x55806, 0x2a00],
		[0x5580a, 0x2a00],
		[0x55888, 0x2b00],
		[0x56212, 0x2800],
		[0x5622a, 0x2800]
	]:
		if u16(pair[0]) & 0xff00 != pair[1]:
			fail("Unsupported fighter boost selector.")
			return {}
	var helpers := imported_symbols()
	for pair in [
		[0x561d8, "___divsf3vfp"],
		[0x561de, "___mulsf3vfp"],
		[0x561e4, "___gtsf2vfp"],
		[0x562ae, "___divsf3vfp"],
		[0x562b6, "___addsf3vfp"],
		[0x562f4, "___divsf3vfp"],
		[0x562fc, "___addsf3vfp"],
		[0x560f2, "___mulsf3vfp"],
		[0x56136, "___mulsf3vfp"],
		[0x565ca, "___mulsf3vfp"]
	]:
		if not helpers.get(pair[1], []).has(call_target(pair[0])):
			fail("Unsupported fighter acceleration arithmetic.")
			return {}
	for pair in [
		[0x56226, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x56236, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x561cc, "__ZN6Player15getMaxHitpointsEv"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported fighter boost decision consumer.")
			return {}
	var drift := wreck_drift()
	if drift.is_empty():
		return {}
	if (
		literal(0x56252, 3) != 0x109
		or literal(0x56280, 3) != 0x109
		or literal(0x562ca, 2) != 0x109
		or literal_float(0x5625a, 1) != literal_float(0x562d8, 0)
	):
		fail("Unsupported fighter braking binding or threshold.")
		return {}
	var result := {
		"initial_speed": literal_float(0x55a06, 2) * 20.0,
		"cruise_speed": literal_float(0x562d8, 0) * 20.0,
		"boost_speed": literal_float(0x56294, 1) * 20.0,
		"decision_speed_below": float((u16(0x56212) & 255) + 1) * 20.0,
		"acceleration": 20000.0 / literal_float(0x562ac, 1),
		"braking": -20000.0 / literal_float(0x562f2, 1),
		"decision_seconds": float(literal(0x56202, 3)) / 1000.0,
		"forced_elapsed": float(literal(0x561f0, 2)) / 1000.0,
		"damage_fraction": literal_float(0x561e2, 1) / literal_float(0x561dc, 1),
		"chance_out_of": immediate_at(0x56220, 1),
		"duration_chance": (u16(0x5622a) & 255) + 1,
		"duration_min_ms": shifted_at(0x5623a, 0x5623c, 1),
		"duration_choices_ms": literal(0x56230, 1),
		"reference_seconds": drift.reference_seconds,
		"excluded_actors":
		[
			u16(0x557f2) & 255,
			u16(0x557f6) & 255,
			literal(0x557fa, 3),
			literal(0x557fa, 3) - 1,
			u16(0x55806) & 255,
			u16(0x5580a) & 255,
			u16(0x55888) & 255
		],
		"heavy":
		{
			"gain": literal_float(0x55930, 2),
			"far_width": float(literal(0x55936, 2)) * .02,
			"floor_speed": literal_float(0x56180, 3) * 20.0
		},
		"special":
		{
			"gain": literal_float(0x55978, 2),
			"far_width": float(literal(0x5597e, 2)) * .02,
			"floor_speed": literal_float(0x56144, 1) * 20.0
		},
		"far_retention": literal_float(0x56132, 1)
	}
	if not preload("res://src/simulation/fighter_motion.gd").valid_data(result):
		fail("Invalid supplied fighter speed or boost constants.")
		return {}
	return result if error.is_empty() else {}


func npc_exhaust() -> Dictionary:
	# Import the NPC two-argument burner consumer; the player-only third mode
	# is not used by fighter update. These declarations describe visual envelopes.
	for pair in [
		[0x566f4, 0x2382],
		[0x566f6, 0x005b],
		[0x56704, 0xd000],
		[0x56706, 0x2401],
		[0x5670c, 0x1c22],
		[0x65030, 0x2300],
		[0x65032, 0xb2d2],
		[0x685e8, 0x6940],
		[0x685ea, 0xb2d2],
		[0x64ec0, 0x2a00],
		[0x64eca, 0xd101],
		[0x64ecc, 0x62e8],
		[0x64ece, 0x62a8],
		[0x64ed0, 0x2024],
		[0x64ed2, 0x542a],
		[0x64eee, 0x2a00],
		[0x64efc, 0xd805],
		[0x64f42, 0xdd01],
		[0x64f72, 0x0862],
		[0x64f78, 0x1058],
		[0x64faa, 0x0843],
		[0xa966, 0x2200],
		[0x65070, 0x2300],
		[0x65078, 0x61cb]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported NPC burner state or dimension binding.")
			return {}
	for pair in [
		[0x64f00, 0x018a],
		[0x64f0c, 0x010a],
		[0x64f1a, 0x0209],
		[0x64f24, 0x00cb],
		[0x64f30, 0x0289]
	]:
		if u16(pair[0]) & ~0x7c0 != int(pair[1]) & ~0x7c0:
			fail("Unsupported NPC burner rate encoding.")
			return {}
	for pair in [
		[0x5670e, "__ZN8KIPlayer13updateBoosterEjb"],
		[0x685f0, "__ZN7Booster6updateEjb"],
		[0x65034, "__ZN7Booster6updateEjbb"],
		[0x64f48, "__ZN11AbyssEngine6AEMath3SinEi"],
		[0x64f9e, "__ZN11AbyssEngine6AEMath3MaxEii"],
		[0x64fd4, "__ZN11AbyssEngine6AEMath3MaxEii"],
		[0x64fe2, "__ZN11AbyssEngine6AEMath16MatrixSetScalingERNS0_6MatrixEiii"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported NPC burner visual consumer.")
			return {}
	var helpers := imported_symbols()
	for pair in [
		[0x566fe, "___gesf2vfp"],
		[0xa95a, "___mulsf3vfp"],
		[0xa962, "_sin"],
		[0xa96a, "___muldf3vfp"],
		[0x64e18, "___mulsf3vfp"],
		[0x64e1e, "___divsf3vfp"],
		[0x64e24, "___mulsf3vfp"],
		[0x64f8a, "___mulsf3vfp"],
		[0x64fc0, "___mulsf3vfp"]
	]:
		if not helpers.get(pair[1], []).has(call_target(pair[0])):
			fail("Unsupported NPC burner pulse arithmetic.")
			return {}
	for pair in [[0x64e16, 0x64e34], [0x64e1c, 0x64e3a], [0x64e22, 0x64e40]]:
		if literal_float(pair[0], 1) != literal_float(pair[1], 1):
			fail("Unsupported asymmetric burner pulse amplitudes.")
			return {}
	var unit := 1.0 / literal_float(0x64e22, 1)
	var amplitude := PackedByteArray()
	amplitude.resize(8)
	amplitude.encode_u32(0, 0)
	amplitude.encode_u32(4, literal(0xa968, 3))
	var phase_extent := shifted_at(0x64f3c, 0x64f3e, 3)
	if (
		signed_literal(0x64f44, 0) != -phase_extent
		or absf(2.0 * phase_extent * literal_float(0xa958, 1) - TAU) > .00001
	):
		fail("Unsupported NPC burner sine period.")
		return {}
	var result := {
		"boost_threshold": literal_float(0x566f8, 1) * 20.0,
		"pulse_fraction":
		(
			literal_float(0x64e16, 1)
			/ literal_float(0x64e1c, 1)
			* literal_float(0x64e22, 1)
			* amplitude.decode_double(0)
		),
		"normal_phase_rate":
		float(1 << ((u16(0x64f30) >> 6) & 31)) * 1000.0 * literal_float(0xa958, 1),
		"boost_phase_rate":
		float(1 << ((u16(0x64f1a) >> 6) & 31)) * 1000.0 * literal_float(0xa958, 1),
		"attack_seconds": float(literal(0x64ef4, 2) + 1) / 1000.0,
		"attack_rate": float(1 << ((u16(0x64f00) >> 6) & 31)) * 1000.0 / unit,
		"sustain_rate": float(1 << ((u16(0x64f0c) >> 6) & 31)) * 1000.0 / unit,
		"release_rate": float(1 << ((u16(0x64f24) >> 6) & 31)) * 1000.0 / unit,
		"attack_limit": float(literal(0x64f04, 2)) / unit,
		"sustain_limit": float(literal(0x64f10, 2)) / unit,
		"width_extension": 1.0 / float(1 << ((u16(0x64f78) >> 6) & 31)),
		"minimum_fraction": 1.0 / float(1 << ((u16(0x64f72) >> 6) & 31))
	}
	if not preload("res://src/presentation/npc_exhaust.gd").valid_data(result):
		fail("Invalid imported NPC burner parameters.")
		return {}
	return result if error.is_empty() else {}


func fighter_impact() -> Dictionary:
	# Constant declarations and verified consumers only; no source instructions run.
	for binding in [
		[0x2664a, "__ZN6Sparks8isRocketEv"],
		[0x26604, "__ZN6Player12setHitVectorEiii"],
		[0x56610, "__ZN6Player12getHitVectorEv"],
		[0x5640c, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii"],
		[0x56414, "__ZN11AbyssEngine6AEMath6MatrixmLERKS1_"],
		[0x267bc, "__ZN11AbyssEngine6AEMath6VectormLEi"],
		[0x5b494, "__ZN11AbyssEngine6AEMath6VectormLEi"],
		[0x33750, "__ZN3Gun9setImpactEP6Sparks"],
		[0x3a3b8, "__ZN6SparksC1Ei"],
		[0x3a3de, "__ZN6SparksC1Ei"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported fighter impact consumer.")
			return {}
	for guard in [
		[0x56336, 0x23ec],
		[0x5633a, 0x5cf3],
		[0x5633e, 0xd141],
		[0x551a8, 0x23e8],
		[0x551aa, 0x50c5],
		[0x551ac, 0x23ec],
		[0x551ae, 0x54c5],
		[0x5d794, 0x6141],
		[0x5d644, 0x6943],
		[0x5d648, 0x2b01],
		[0x3a3b4, 0x2100],
		[0x3a3c6, 0x23c0],
		[0x3a3c8, 0x50c1],
		[0x3a3da, 0x2101],
		[0x3a404, 0x23bc],
		[0x3a406, 0x50e0],
		[0x2f2ae, 0x23c0],
		[0x2f2b2, 0x58cb],
		[0x2f2b8, 0x600b],
		[0x3016a, 0x23bc],
		[0x3016e, 0x58eb],
		[0x30172, 0x6033],
		[0x336da, 0x23bc],
		[0x336e0, 0x58e3],
		[0x336ec, 0x6023],
		[0x264c8, 0x6441],
		[0x26650, 0xd002],
		[0x26652, 0x2339],
		[0x26654, 0x2201],
		[0x26656, 0x54ea],
		[0x563e6, 0x22ec],
		[0x563e8, 0x5cb3],
		[0x563ec, 0xd03f],
		[0x563f2, 0xd03c],
		[0x563fe, 0x00da],
		[0x56402, 0x2300],
		[0x56400, 0x9400],
		[0x56426, 0x005b],
		[0x56428, 0x58f1],
		[0x56436, 0x4343],
		[0x56438, 0x141a],
		[0x56460, 0xdc00],
		[0x56468, 0x5131],
		[0x5646a, 0x54b1],
		[0x56622, 0x4240],
		[0x5662a, 0x425b],
		[0x56632, 0x425b],
		[0x56636, 0x23ec],
		[0x56638, 0x2201],
		[0x5663a, 0x54f2],
		[0x267a8, 0x9832],
		[0x267ae, 0x6aa1],
		[0x5b47e, 0x9800],
		[0x5b484, 0x6aa1],
		[0x5325e, 0x990b],
		[0x5326a, 0x9109]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported fighter impact data binding at %x." % guard[0])
			return {}
	var slot := literal(0x33746, 2)
	if slot != literal(0x2f2b4, 1) or slot != literal(0x30168, 6) or slot != literal(0x336e2, 4):
		fail("Conflicting supplied impact effect slot.")
		return {}
	# Each supported construction branch uses the ordinary default, or reaches
	# one of the two explicit rocket-effect assignments. Renderer class is not
	# an impact category: the multi-projectile RocketGuns keep ordinary Sparks.
	var flags := {
		0x2f412: false,
		0x2f6ee: false,
		0x2fa18: false,
		0x2fca8: true,
		0x2feca: true,
		0x301c8: true,
		0x3045e: false,
		0x30738: false,
		0x308a6: false,
		0x30b90: false,
		0x31078: false,
		0x3178e: false,
		0x31fe8: false,
		0x32324: false,
		0x32668: false,
		0x329a8: false,
		0x32ce4: false,
		0x33030: true
	}
	for edge in [
		[0x2f6ec, 0x2fc96],
		[0x2f9d2, 0x30174],
		[0x2fca4, 0x336ee],
		[0x30736, 0x30b86],
		[0x308a2, 0x32fea],
		[0x30b8c, 0x2fc9c],
		[0x32322, 0x32962],
		[0x32610, 0x32c94],
		[0x32964, 0x32c94],
		[0x32c9e, 0x32fea],
		[0x32ff2, 0x336ee],
		[0x2fec6, 0x336d4],
		[0x3045c, 0x30164],
		[0x3017c, 0x336ee],
		[0x31074, 0x31fde],
		[0x3178a, 0x31fde],
		[0x31fe4, 0x32fea]
	]:
		var target := (
			call_target(edge[0])
			if (u16(edge[0]) & 0xf800) == 0xf000
			else contract_constant_branch(edge[0])
		)
		if target != edge[1]:
			fail("Unsupported player impact dispatch.")
			return {}
	var table := symbol_address("__ZN5Level9createGunEiiiiii") + 0x12c
	if u32(table) > 256 or call_target(table - 4) != symbol_address("___switch32"):
		fail("Unsupported player impact table.")
		return {}
	var weapons := {}
	for index in u32(table):
		var branch := table + u32(table + 4 + index * 4)
		if flags.has(branch):
			weapons[str(index)] = flags[branch]
	if weapons.size() != flags.size():
		fail("Incomplete player impact declarations.")
		return {}
	var drift := wreck_drift()
	if drift.is_empty():
		return {}
	return (
		{
			"duration": literal(0x5645c, 3) / 1000.0,
			"rotation_rate":
			float(1 << ((u16(0x563fe) >> 6) & 31)) * 1000.0 * literal_float(0xa958, 1),
			"travel_scale": float(drift.reference_seconds) / (.02 * normalized_vector_unit()),
			"no_tumble_actor": u16(0x563f0) & 255,
			"player_flags": weapons
		}
		if error.is_empty()
		else {}
	)


func fighter_targeting() -> Dictionary:
	# Bounded constant/association reader; original functions are never executed.
	for binding in [
		[0x55b88, "__ZN6Player10getEnemiesEv"],
		[0x55ede, "__ZN5Level9getPlayerEv"],
		[0x55ee6, "__ZN6Player11getPositionEv"],
		[0x55ef0, "__ZN11AbyssEngine6AEMathmiERKNS0_6VectorES3_"],
		[0x55f2a, "__ZN6Player9setActiveEb"],
		[0x55bba, "__ZN6Player8isActiveEv"],
		[0x55bea, "__ZN7Mission7getTypeEv"],
		[0x55bf8, "__ZN7Mission8getLevelEv"],
		[0x55c0e, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x55c34, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x55d42, "__ZN6Player8isActiveEv"],
		[0x55d52, "__ZN6Player11getPositionEv"],
		[0x55de6, "__ZN5Route11getWaypointEv"],
		[0x29c8c, "__ZN6Player8setEnemyEPS_"],
		[0x29cfe, "__ZN6Player8addEnemyEPS_"],
		[0x29d3c, "__ZN6Player8addEnemyEPS_"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported fighter targeting association at %x." % binding[0])
			return {}
	for guard in [
		[0x55eb0, 0x2305],
		[0x55eb2, 0x61b3],
		[0x55ed4, 0xd12b],
		[0x55ed8, 0x2b05],
		[0x55eda, 0xd128],
		[0x55f06, 0xd812],
		[0x55f0e, 0xdc0e],
		[0x55f14, 0xdd0b],
		[0x55f1c, 0xdc07],
		[0x55f20, 0xdd05],
		[0x55f22, 0x2301],
		[0x55f26, 0x2101],
		[0x55f28, 0x61b3],
		[0x55fc6, 0xd100],
		[0x55fc8, 0xe394],
		[0x685fa, 0x2305],
		[0x685fe, 0x6183],
		[0x55fae, 6],
		[0x55fb2, 0x30],
		[0x55fba, 8],
		[0x55bd0, 0xdc00],
		[0x55c14, 0xdc01],
		[0x55c20, 0xd801],
		[0x55c6e, 0xd812],
		[0x55c78, 0xdc0d],
		[0x55c7e, 0xdd0a],
		[0x55c88, 0xdc05],
		[0x55c8c, 0xdd03],
		[0x55d64, 0xd830],
		[0x55d6e, 0xdc0c],
		[0x55d74, 0xdd0c],
		[0x55d7e, 0xdc0a],
		[0x55d82, 0xdd21],
		[0x55b9a, 0xd104],
		[0x55ba2, 0x50f2],
		[0x55bc2, 0x5530],
		[0x55bd4, 0x5070],
		[0x55c2c, 0x54f2],
		[0x55c92, 0x54f2],
		[0x55d2c, 0xd151],
		[0x55d86, 0x50f5],
		[0x55e52, 0x50f2],
		[0x55aa8, 0x22b8],
		[0x55aac, 0x4453],
		[0x55aae, 0x5083],
		[0x480b4, 0x2300],
		[0x480b8, 0x6093],
		[0x47fe2, 0x6880]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported fighter targeting consumer at %x." % guard[0])
			return {}
	var ally_extent := literal(0x55efc, 1)
	if (
		ally_extent <= 0
		or literal(0x55f00, 2) != ally_extent * 2
		or literal(0x55f10, 2) - 0x100000000 != -ally_extent - 1
	):
		fail("Unsupported ally activation extent.")
		return {}
	var extent := literal(0x55c64, 1)
	if (
		extent <= 0
		or literal(0x55c68, 2) != extent * 2
		or literal(0x55c7a, 0) - 0x100000000 != -extent - 1
		or literal(0x55ce8, 1) != extent
		or literal(0x55cec, 2) != extent * 2
		or literal(0x55d06, 0) != literal(0x55c7a, 0)
		or literal(0x55d5a, 1) != extent
		or literal(0x55d5e, 2) != extent * 2
		or literal(0x55d70, 0) != literal(0x55c7a, 0)
		or u16(0x55bee) & 0xff00 != 0x2800
		or u16(0x55bfc) & 0xff00 != 0x2800
		or u16(0x55c9c) & 0xff00 != 0x2900
	):
		fail("Conflicting fighter acquisition declarations.")
		return {}
	var result := {
		"interval": literal(0x55bc6, 3) / 1000.0,
		"half_width": extent * .02,
		"ally_wake_half_width": ally_extent * .02,
		"normal_chance": immediate_at(0x55c04, 5),
		"enhanced_chance": immediate_at(0x55c00, 5),
		"chance_out_of": immediate_at(0x55c08, 1),
		"attempts": u16(0x55c9c) & 255,
		"enhanced_type": u16(0x55bee) & 255,
		"enhanced_chapter": u16(0x55bfc) & 255
	}
	if not preload("res://src/simulation/fighter_targeting.gd").valid_data(result):
		fail("Invalid fighter targeting declarations.")
		return {}
	return result


func menu_traffic() -> Dictionary:
	# Source declarations only. Runtime traffic uses native presentation sampling.
	for binding in [
		[0x4ef6c, "__ZN7Station8isPlanetEv"],
		[0x4ef82, "__ZN8CutSceneC1Ei"],
		[0x4efa8, "__ZN8CutSceneC1Ei"],
		[0x49ec8, "__ZN8CutSceneC1Ei"],
		[0x13b86, "__ZN5Level18setStationPositionEN11AbyssEngine6AEMath6VectorE"],
		[0x13b9a, "__ZN5Level17setStationScalingEN11AbyssEngine6AEMath6VectorE"],
		[0x5bc4e, "__ZN5RouteC1EPii"],
		[0x55854, "__ZN5TrailC1Eii"],
		[0x55b4a, "__ZN5Trail6updateERKN11AbyssEngine6AEMath6VectorES4_"],
		[0x34042, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x340dc, "__ZN5RouteC1EPii"],
		[0x3415a, "__ZN5RouteC1EPii"],
		[0x3419a, "__ZN5RouteC1EPii"],
		[0x3470a, "__ZN5RouteC1EPii"],
		[0x340f8, "__ZN5Route7setLoopEb"],
		[0x34176, "__ZN5Route7setLoopEb"],
		[0x341b6, "__ZN5Route7setLoopEb"],
		[0x341c4, "__ZN7Station7getRaceEv"],
		[0x341ea, "__ZN7Station7getRaceEv"],
		[0x34212, "__ZN7Station7getRaceEv"],
		[0x343de, "__ZN5Level10createShipEiiibP8Waypoint"],
		[0x34522, "__ZN5Level10createShipEiiibP8Waypoint"],
		[0x345e6, "__ZN5Level10createShipEiiibP8Waypoint"],
		[0x34678, "__ZN5Level10createShipEiiibP8Waypoint"],
		[0x347b6, "__ZN5Level10createShipEiiibP8Waypoint"],
		[0x34534, "__ZN13PlayerFighter11removeTrailEv"],
		[0x3453e, "__ZN13PlayerFighter12lockRotationEv"],
		[0x34602, "__ZN13PlayerFighter12lockRotationEv"],
		[0x34694, "__ZN13PlayerFighter12lockRotationEv"],
		[0x34806, "__ZN13PlayerFighter12lockRotationEv"],
		[0x13af2, "__ZN18TargetFollowCamera12setLookAtCamEb"],
		[0x13b00, "__ZN18TargetFollowCamera11setPositionEiii"],
		[0x13b30, "__ZN18TargetFollowCamera9setTargetEj"],
		[0x347d2, "__ZN13PlayerFighter11setPositionEiii"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported menu traffic association at %x." % binding[0])
			return {}
	# Verify declaration layout and branch meaning; the literal values stay data.
	for guard in [
		[0x4ef72, 0xd010, 0xffff],
		[0x5b9a6, 0x2300, 0xffff],
		[0x5b9a8, 0x6003, 0xffff],
		[0x5bc7e, 0x7213, 0xffff],
		[0x13b72, 0x105b, 0xffff],
		[0x13b80, 0x009b, 0xffff],
		[0x5baf6, 0xdc3f, 0xffff],
		[0x5bafc, 0xdd3c, 0xffff],
		[0x56514, 0x23e4, 0xffff],
		[0x56516, 0x5cf3, 0xffff],
		[0x56518, 0x2b00, 0xffff],
		[0x5651c, 0x2390, 0xffff],
		[0x5651e, 0x50f4, 0xffff],
		[0x55ae4, 0x2b00, 0xff00],
		[0x34056, 0xdc00, 0xffff],
		[0x3406c, 0xdc0e, 0xffff],
		[0x3407a, 0xdd00, 0xffff],
		[0x34082, 0x2001, 0xffff],
		[0x34086, 0x932b, 0xffff],
		[0x34088, 0x902a, 0xffff],
		[0x34090, 0xd10a, 0xffff],
		[0x340a2, 0xdc01, 0xffff],
		[0x340a6, 0x9429, 0xffff],
		[0x340aa, 0x952b, 0xffff],
		[0x340ac, 0x952a, 0xffff],
		[0x340b0, 0xa962, 0xffff],
		[0x340d6, 0xa962, 0xffff],
		[0x340ec, 0x50ca, 0xffff],
		[0x340f4, 0x2101, 0xffff],
		[0x34126, 0xd101, 0xffff],
		[0x34132, 0x9393, 0xffff],
		[0x34138, 0x9292, 0xffff],
		[0x3413a, 0x9394, 0xffff],
		[0x3413e, 0x9295, 0xffff],
		[0x34140, 0x9396, 0xffff],
		[0x34144, 0x9397, 0xffff],
		[0x34154, 0xa992, 0xffff],
		[0x3416a, 0x2101, 0xffff],
		[0x3416c, 0x50e8, 0xffff],
		[0x3417c, 0xa98c, 0xffff],
		[0x34194, 0xa98c, 0xffff],
		[0x341aa, 0x50c1, 0xffff],
		[0x341b2, 0x2101, 0xffff],
		[0x341ca, 0xd102, 0xffff],
		[0x341ce, 0x922d, 0xffff],
		[0x341d4, 0x932d, 0xffff],
		[0x341f0, 0xd109, 0xffff],
		[0x341fa, 0x952e, 0xffff],
		[0x341fc, 0x902c, 0xffff],
		[0x341fe, 0x912f, 0xffff],
		[0x34200, 0x922a, 0xffff],
		[0x34202, 0x922b, 0xffff],
		[0x34218, 0xd106, 0xffff],
		[0x3421e, 0x952e, 0xffff],
		[0x34220, 0x952d, 0xffff],
		[0x34222, 0x902c, 0xffff],
		[0x34224, 0x912f, 0xffff],
		[0x3422e, 0x922e, 0xffff],
		[0x34230, 0x932c, 0xffff],
		[0x34232, 0x942f, 0xffff],
		[0x34308, 0x9912, 0xffff],
		[0x34310, 0x9128, 0xffff],
		[0x3432c, 0xd102, 0xffff],
		[0x3433e, 0x3003, 0xffff],
		[0x34398, 0x25a0, 0xffff],
		[0x343b0, 0x3901, 0xffff],
		[0x343d8, 0x9b2c, 0xffff],
		[0x3448e, 0xf034, 0xffff],
		[0x344b0, 0x23a8, 0xffff],
		[0x344ba, 0xd107, 0xffff],
		[0x344c4, 0xd102, 0xffff],
		[0x344c6, 0x23a4, 0xffff],
		[0x3451c, 0x9b2d, 0xffff],
		[0x34564, 0xf027, 0xffff],
		[0x3458a, 0x23a4, 0xffff],
		[0x345e0, 0x9b2e, 0xffff],
		[0x34628, 0xf027, 0xffff],
		[0x3464c, 0x23a4, 0xffff],
		[0x34672, 0x9b2f, 0xffff],
		[0x346b8, 0x2100, 0xffff],
		[0x346e6, 0xd100, 0xffff],
		[0x34704, 0xa986, 0xffff],
		[0x347a6, 0x4b20, 0xffff],
		[0x347b0, 0x80, 0xffff],
		[0x347b2, 0x58c3, 0xffff],
		[0x347e2, 0x22ac, 0xffff],
		[0x347e6, 0xf033, 0xffff],
		[0x13aea, 0x2101, 0xffff],
		[0x13b26, 0x3801, 0xffff],
		[0x13b2a, 0x58c0, 0xffff],
		[0x34054, 0x2800, 0xff00],
		[0x3406a, 0x2800, 0xff00],
		[0x34078, 0x2800, 0xff00],
		[0x340a0, 0x2800, 0xff00],
		[0x341c8, 0x2800, 0xff00],
		[0x341ee, 0x2800, 0xff00],
		[0x34216, 0x2800, 0xff00],
		[0x3430e, 0x3100, 0xff00]
	]:
		if u16(guard[0]) & guard[2] != guard[1]:
			fail("Unsupported menu traffic declaration at %x." % guard[0])
			return {}
	var local_values := int_array(literal(0x340ae, 3), immediate_at(0x340d8, 2))
	var cross_values := int_array(literal(0x3417a, 3), immediate_at(0x34196, 2))
	var player_values := int_array(literal(0x346ea, 3), immediate_at(0x34706, 2))
	if local_values.size() != 12 or cross_values.size() != 6 or player_values.size() != 6:
		fail("Unsupported menu traffic route dimensions.")
		return {}
	var routes: Array = []
	for values in [local_values, cross_values, player_values]:
		var route: Array = []
		for index in range(0, values.size(), 3):
			route.append(values.slice(index, index + 3))
		routes.append(route)
	var families := [
		{
			"race": -1,
			"local": immediate_at(0x3422a, 3),
			"freighter": immediate_at(0x341d2, 3),
			"escort": immediate_at(0x34228, 2),
			"carrier": immediate_at(0x3422c, 4),
			"optional": true
		},
		{
			"race": u16(0x341c8) & 255,
			"local": immediate_at(0x3422a, 3),
			"freighter": immediate_at(0x341cc, 2),
			"escort": immediate_at(0x34228, 2),
			"carrier": immediate_at(0x3422c, 4),
			"optional": true
		},
		{
			"race": u16(0x34216) & 255,
			"local": u16(0x34216) & 255,
			"freighter": immediate_at(0x3421a, 5),
			"escort": immediate_at(0x3421a, 5),
			"carrier": immediate_at(0x3421c, 1),
			"optional": true
		},
		{
			"race": u16(0x341ee) & 255,
			"local": immediate_at(0x341f6, 0),
			"freighter": immediate_at(0x341d2, 3),
			"escort": immediate_at(0x341f4, 5),
			"carrier": immediate_at(0x341f8, 1),
			"optional": false
		}
	]
	var result := {
		"local_route": routes[0],
		"route_start": immediate_at(0x5b9a6, 3),
		"waypoint_half_width": float(literal(0x5baee, 3)) * .02,
		"local_trail": {"style": immediate_at(0x55846, 1), "segments": immediate_at(0x55852, 2)},
		"trail_seconds": float(u16(0x55ae4) & 255) / 1000.0,
		"orbital_position":
		[0, 0, (65536 >> ((u16(0x13b72) >> 6) & 31)) << ((u16(0x13b80) >> 6) & 31)],
		"orbital_scale": float(shifted_immediate(0x13b8a, 3)) / 65536.0,
		"title_mode": immediate_at(0x49ec4, 1),
		"planet_mode": immediate_at(0x4ef7e, 1),
		"orbital_mode": immediate_at(0x4efa4, 1),
		"crossing_route": routes[1],
		"player_route": routes[2],
		"longitudinal_start": [0, shifted_immediate(0x3412e, 3), signed_literal(0x34134, 3)],
		"longitudinal_end": [0, signed_literal(0x3413c, 3), signed_literal(0x34142, 3)],
		"lane_choices": [signed_literal(0x34128, 2), signed_literal(0x3412c, 2)],
		"families": families,
		"local_min": u16(0x3430e) & 255,
		"local_span": immediate_at(0x34036, 1),
		"chance_out_of": immediate_at(0x34048, 1),
		"freighter_chance": (u16(0x34054) & 255) + 1,
		"escort_chance": (u16(0x3406a) & 255) + 1,
		"carrier_chance": (u16(0x34078) & 255) + 1,
		"double_freighter_chance": (u16(0x340a0) & 255) + 1,
		"player_position":
		[shifted_immediate(0x347bc, 1), signed_literal(0x347ce, 2), signed_literal(0x347d0, 3)],
		"camera_position":
		[immediate_at(0x13af8, 1), immediate_at(0x13afa, 2), signed_literal(0x13afc, 3)],
		"fov_units": literal(0x136d6, 2),
		"near": immediate_at(0x136d4, 3),
		"far": literal(0x13690, 5)
	}
	if not preload("res://src/presentation/menu_traffic.gd").valid_data(
		result, named_array(TABLES.actor_meshes).size()
	):
		fail("Invalid supplied menu traffic data.")
		return {}
	return result


func defeat_presentation() -> Dictionary:
	for pair in [
		[0x443e2, "__ZN8GameText7getTextEi"], [0x445ac, "__ZN8GameText7getTextEi"],
		[0x44660, "__ZN8GameText7getTextEi"], [0x44676, "__ZN8GameText7getTextEi"],
		[0x46042, "__ZN8GameText7getTextEi"],
		[0x44408, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringEb"],
		[0x4468c, "__ZN12ChoiceWindow10setCaptionEN11AbyssEngine6StringES1_"],
		[0x45ff0, "__ZN10GameRecord4loadEv"],
		[0x4463c, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x45c5a, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjii"],
		[0x45c48, "__ZN12ChoiceWindow8getDrawYEv"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported defeat presentation consumer at %x." % pair[0])
			return {}
	if u16(0x45fe8) != 0x69c0 or u16(0x45c54) & 0xff00 != 0x3300:
		fail("Unsupported defeat record or artwork association.")
		return {}
	return {
		"labels": {"lost": shifted_at(0x443d4, 0x443da, 1),
			"timeout": literal(0x445a6, 1), "load": shifted_at(0x4464c, 0x4464e, 1),
			"menu": literal(0x44674, 1), "missing": literal(0x4603a, 1)},
		"image": ui_region_binding(literal(0x44636, 1)),
		"image_y": u16(0x45c54) & 255
	} if error.is_empty() else {}


func pause_presentation() -> Dictionary:
	for pair in [
		[0x460cc, "__ZN10MenuWindow8setPauseEv"],
		[0x45f76, "__ZN11AbyssEngine18ApplicationManager17SoundResumeSoundsEv"],
		[0x41ba4, "__ZN8GameText7getTextEi"], [0x41c0c, "__ZN8GameText7getTextEi"],
		[0x41c7e, "__ZN8GameText7getTextEi"], [0x41ce4, "__ZN8GameText7getTextEi"],
		[0x41b5a, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported pause menu consumer.")
			return {}
	if (u16(0x45f62) & 0xff00) != 0x2800 or immediate_at(0x3cd2a, 3) != (u16(0x45f62) & 255) or u16(0x45f70) != 0xd000:
		fail("Unsupported pause menu resume association.")
		return {}
	var menu := immediate_at(0x3cd2a, 3)
	return {
		"rows": u32(literal(0x41b66, 2) + menu * 4),
		"row_step": immediate_at(0x41b3a, 3),
		"labels": {"resume": immediate_at(0x41b9c, 1), "options": immediate_at(0x41c08, 1),
			"help": immediate_at(0x41c7a, 1), "menu": literal(0x41ce0, 1)}
	} if error.is_empty() else {}


func options_presentation() -> Dictionary:
	for pair in [
		[0x409f4, "__ZN8GameText7getTextEi"], [0x40a5c, "__ZN8GameText7getTextEi"],
		[0x40abe, "__ZN8GameText7getTextEi"], [0x40528, "__ZN8GameText7getTextEi"],
		[0x40560, "__ZN8GameText7getTextEi"], [0x41f64, "__ZN8GameText7getTextEi"],
		[0x42eae, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x42ea0, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x42e92, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x42e5e, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x42e4e, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x3d592, "__ZN11AbyssEngine18ApplicationManager19SoundSetMusicVolumeEi"],
		[0x3d5f2, "__ZN11AbyssEngine18ApplicationManager16SoundSetFXVolumeEi"],
		[0x405ba, "__ZN11AbyssEngine11PaintCanvas8SetColorEhhhh"],
		[0x405fa, "__ZN11AbyssEngine11PaintCanvas8SetColorEhhhh"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported options presentation consumer at %x." % pair[0])
			return {}
	for pair in [
		[0x41e74, 0x791b], [0x41e78, 0xd008], [0x41e7e, 0x6fe1],
		[0x41e90, 0x2380], [0x42e9e, 0x327c], [0x42e90, 0x3280],
		[0x42eac, 0x3284], [0x3d526, 0x4358], [0x3d5c2, 0x4358]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported option checkmark or volume association.")
			return {}
	var maximum := immediate_at(0x3d524, 3)
	if maximum <= 0 or maximum != immediate_at(0x3d5c0, 3):
		fail("Unsupported audio volume range.")
		return {}
	return {
		"labels": {"controls": immediate_at(0x409ec, 1), "audio": literal(0x40a58, 1),
			"display": literal(0x40aba, 1), "music": shifted_at(0x40550, 0x40552, 1),
			"effects": literal(0x4051c, 1), "invert": immediate_at(0x41f42, 1)},
		"images": {"checked": ui_region_binding(shifted_at(0x42e98, 0x42e9c, 1)),
			"unchecked": ui_region_binding(literal(0x42e8e, 1)),
			"grabber": ui_region_binding(shifted_at(0x42ea6, 0x42eaa, 1)),
			"slider_selected": ui_region_binding(literal(0x42e5c, 1)),
			"slider_idle": ui_region_binding(shifted_at(0x42e42, 0x42e44, 1))},
		"rail_fill": [immediate_at(0x405b4, 1), immediate_at(0x405b6, 2), immediate_at(0x405b8, 3), immediate_at(0x405b0, 3)],
		"rail_border": [immediate_at(0x405f6, 1), immediate_at(0x405f4, 2), immediate_at(0x405f8, 3), immediate_at(0x405e2, 3)],
		"volume_max": maximum
	} if error.is_empty() else {}


func title_menu_presentation() -> Dictionary:
	var create_image := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	for address in [
		0x2913c,
		0x29150,
		0x291aa,
		0x291c0,
		0x29204,
		0x29214,
		0x29224,
		0x29232,
		0x292fc,
		0x42e7a,
		0x42e86
	]:
		if call_target(address) != create_image:
			fail("Unsupported title artwork association at %x." % address)
			return {}
	for binding in [
		[0x49f8e, "__ZN10MenuWindow3setEi"],
		[0x3f16c, "__ZN6Layout18drawMenuBackgroundEb"],
		[0x28dae, "__ZN6Layout8drawLogoEjjhh"],
		[0x3f696, "__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh"],
		[0x3f6e4, "__ZN8GameText7getTextEi"],
		[0x3f73c, "__ZN8GameText7getTextEi"],
		[0x3f7a0, "__ZN8GameText7getTextEi"],
		[0x3f7fe, "__ZN8GameText7getTextEi"],
		[0x3f860, "__ZN8GameText7getTextEi"]
	]:
		if call_target(binding[0]) != symbol_address(binding[1]):
			fail("Unsupported title layout association at %x." % binding[0])
			return {}
	for guard in [
		[0x49f8a, 0x2100],
		[0x3f650, 0x6ca1],
		[0x3f66e, 0x6cc1],
		[0x3f67a, 0x4353],
		[0x3f686, 0x2214],
		[0x3f694, 0x2200],
		[0x28da8, 0x2100],
		[0x28daa, 0x2203],
		[0x28dac, 0x9300],
		[0x28d20, 0x0052],
		[0x28d7a, 0x694c],
		[0x29340, 0x3301]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported title alignment declaration at %x." % guard[0])
			return {}
	var starts := named_array("__ZL14button_start_y")
	var counts := named_array("__ZL20num_buttons_per_menu")
	if starts.size() != 6 or counts.size() != 16 or counts[0] < 1 or counts[0] > starts.size():
		fail("Unsupported title button table dimensions.")
		return {}
	var images := {}
	var bindings := {
		"logo": literal(0x29136, 1),
		"pattern": literal(0x2914a, 1),
		"edge": literal(0x291a6, 1),
		"side": shifted_immediate(0x291b8, 1),
		"ring_large": literal(0x291fe, 1),
		"ring_medium": shifted_immediate(0x2920e, 1),
		"ring_small": shifted_immediate(0x2921a, 1),
		"marker": literal(0x2922c, 1),
		"selected": literal(0x42e74, 1),
		"idle": literal(0x42e80, 1),
		"indicator": shifted_immediate(0x292d8, 2),
		"indicator_end": shifted_immediate(0x292d8, 2) + ((u16(0x28d7a) >> 6) & 31)
	}
	for key in bindings:
		images[key] = ui_region_binding(int(bindings[key]))
	var indicators: Array = []
	var indicator_size := immediate_at(0x292b8, 0)
	if indicator_size < 6 or indicator_size > 32:
		fail("Unsupported title decoration atlas size.")
		return {}
	for index in indicator_size:
		indicators.append(ui_region_binding(shifted_immediate(0x292d8, 2) + index))
	var result := {
		"images": images,
		"indicator_frames": indicators,
		"row_starts": starts,
		"title_rows": counts[0],
		"row_step": immediate_at(0x3f676, 3),
		"text_y": u16(0x3f6b8) & 255,
		"logo_y": immediate_at(0x28daa, 2),
		"labels":
		{
			"start": immediate_at(0x3f6d8, 1),
			"load": literal(0x3f738, 1),
			"options": immediate_at(0x3f79c, 1),
			"help": immediate_at(0x3f7fa, 1),
			"more_games": shifted_immediate(0x3f856, 3)
		},
		"side_origin": [immediate_at(0x28cbe, 2), immediate_at(0x28cc4, 3)],
		"ring_origins":
		[
			[immediate_at(0x28cfa, 2), immediate_at(0x28cfc, 3)],
			[immediate_at(0x28d06, 2), immediate_at(0x28d08, 3)],
			[immediate_at(0x28d12, 2), immediate_at(0x28d14, 3)]
		],
		"marker_origin":
		[immediate_at(0x28d1a, 2) << ((u16(0x28d20) >> 6) & 31), literal(0x28d22, 3)],
		"indicator_origin": [immediate_at(0x28d2e, 2), immediate_at(0x28d30, 3)],
		"indicator_column": [shifted_immediate(0x28ce6, 6), u16(0x28d60) & 255],
		"indicator_count": u16(0x28d68) & 255,
		"indicator_end": [shifted_immediate(0x28d84, 2), literal(0x28d8a, 3)],
		"shade_initial": immediate_at(0x29506, 2),
		"shade_floor": immediate_at(0x28864, 3),
		"shade_rate": float(immediate_at(0x2884e, 0)) / float(literal(0x28850, 1)) * 1000.0,
		"pattern_tint":
		[
			immediate_at(0x289de, 1),
			immediate_at(0x289e2, 2),
			immediate_at(0x289e4, 3),
			immediate_at(0x289da, 3)
		]
	}
	if not preload("res://src/presentation/title_menu.gd").valid_data(result):
		fail("Invalid supplied title presentation.")
		return {}
	return result if error.is_empty() else {}


func station_menu_presentation() -> Dictionary:
	var calls := {
		0x4f88a: "__ZN13SelectionListC1EiiiiiiiihPiPbb",
		0x4f962: "__ZN10ObjectList13setCurrentTabEi",
		0x4e3d0: "__ZN16PlanetInfoWindow3setEv",
		0x4e3e0: "__ZN7MHangar17switchToHangarCamEv",
		0x4e3e8: "__ZN8MStation16showMissionBoardEv",
		0x4e3f2: "__ZN11AbyssEngine18ApplicationManager27SetCurrentApplicationModuleEj",
		0x4dc6e: "__ZN6Layout9setFooterEjjj",
		0x4f7d4: "__ZN6Status12campaignModeEv",
		0x4f7e4: "__ZN7Station10offersShopEv",
		0x52d70: "__ZN13EquipmentListC1EiiiiiiiihPiPbb",
		0x52258: "__ZN13EquipmentList13drawRightInfoEP8ListItembbb"
	}
	for address in calls:
		if call_target(address) != symbol_address(calls[address]):
			fail("Unsupported station interface association at %x." % address)
			return {}
	for guard in [
		[0x4f952, 0x50ca],
		[0x4f7b8, 0x600b],
		[0x4f7bc, 0x604b],
		[0x4f7c0, 0x608b],
		[0x4f7c4, 0x60cb],
		[0x4f81a, 0x2300],
		[0x4f81c, 0x7093],
		[0x4f81e, 0x70d3],
		[0x4f848, 0x70a3],
		[0x4f84a, 0x70e3],
		[0x4f7fa, 0xdc00],
		[0x4e3f0, 0x2103],
		[0x515bc, 0x1b02]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported station tab declaration at %x." % guard[0])
			return {}
	var targets := contract_choice_targets(0x4e3c4, symbol_address("__ZN8MStation10OnTouchEndEii"))
	var actions := {0x4e3ce: "info", 0x4e3d6: "hangar", 0x4e3e6: "missions", 0x4e3ee: "map"}
	var labels := [
		literal(0x4f7b2, 3),
		immediate_at(0x4f7ba, 3),
		immediate_at(0x4f7be, 3),
		immediate_at(0x4f7c2, 3)
	]
	var tabs: Array = []
	if targets.size() != immediate_at(0x4f874, 3) or targets.size() != labels.size():
		fail("Unsupported station tab count.")
		return {}
	for index in targets.size():
		if not actions.has(targets[index]):
			fail("Unsupported station tab action.")
			return {}
		tabs.append({"label": labels[index], "action": actions[targets[index]]})
	var image_calls := {
		"corner": [0x5195c, 0x51980],
		"top_corner": [0x5198a, 0x5198c],
		"tab_middle_idle": [0x519a4, 0x519a6],
		"tab_single_idle": [0x519be, 0x519c0],
		"tab_edge_selected": [0x519ca, 0x519cc],
		"tab_edge_idle": [0x519d6, 0x519d8],
		"credits": [0x16f34, 0x16f36],
		"preview": [0x16f44, 0x16f46]
	}
	var images := {}
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	for key in image_calls:
		var record: Array = image_calls[key]
		if call_target(record[1]) != create:
			fail("Unsupported station artwork association.")
			return {}
		images[key] = ui_region_binding(literal(record[0], 1))
	for record in [
		["tab_middle_selected", 0x51992, 0x51996, 0x5199a],
		["tab_single_selected", 0x519ac, 0x519b0, 0x519b4],
		["row", 0x51ce4, 0x51ce6, 0x51ce8]
	]:
		if call_target(record[3]) != create or u16(record[2]) != 0x0089:
			fail("Unsupported station selection artwork.")
			return {}
		images[record[0]] = ui_region_binding(
			immediate_at(record[1], 1) << ((u16(record[2]) >> 6) & 31)
		)
	var result := {
		"tabs": tabs,
		"status": status_presentation(),
		"destination": destination_presentation(),
		"box":
		[
			immediate_at(0x4f85c, 3),
			immediate_at(0x4f860, 3),
			shifted_immediate(0x4f864, 3),
			shifted_immediate(0x4f86a, 3)
		],
		"list":
		[
			immediate_at(0x4f882, 1),
			immediate_at(0x4f884, 2),
			immediate_at(0x4f886, 3),
			immediate_at(0x4f858, 3)
		],
		"images": images,
		"locked_campaign_tabs": [(u16(0x4f81c) >> 6) & 31, (u16(0x4f81e) >> 6) & 31],
		"shop_credit_threshold": literal(0x4f7f6, 3),
		"footer_labels":
		{
			"menu": immediate_at(0x4dc64, 1),
			"continue": immediate_at(0x4dc58, 2),
			"status": immediate_at(0x4dc6c, 3)
		},
		"credits_label": immediate_at(0x1505c, 1),
		"preview_gap": [u16(0x14ed2) & 255, u16(0x14eda) & 255],
		"preview_center":
		[immediate_at(0x52260, 2) << ((u16(0x5226a) >> 6) & 31), immediate_at(0x52270, 3)],
		"credits_gap": u16(0x14fd0) & 255,
		"credits_text": [u16(0x1508c) & 255, u16(0x1508a) & 255],
		"tab_text_y": u16(0x514fc) & 255,
		"row_gap": u16(0x156e2) & 255,
		"fill":
		[
			immediate_at(0x516ee, 1),
			immediate_at(0x516e8, 2),
			immediate_at(0x516ec, 3),
			immediate_at(0x5161a, 3)
		],
		"border":
		[
			immediate_at(0x516ac, 1),
			immediate_at(0x516a6, 2),
			immediate_at(0x516aa, 3),
			immediate_at(0x5161a, 3)
		]
	}
	if not preload("res://src/presentation/station_menu.gd").valid_data(result):
		fail("Invalid supplied station interface.")
		return {}
	return result if error.is_empty() else {}


func status_presentation() -> Dictionary:
	# Import declarations; the native panel and statistics have independent lifecycles.
	for pair in [
		[0x5ed5a, "__ZN7Globals12getCharImageEi"],
		[0x5ed74, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x5ed84, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x5ea08, "__ZN6Status8getLevelEv"],
		[0x5ea62, "__ZN6Status13getReputationEv"],
		[0x5e618, "__ZN6Status14getPlayingTimeEv"],
		[0x5eb7a, "__ZN6Status8getKillsEv"],
		[0x5ebfc, "__ZN6Status15getMissionCountEv"],
		[0x5e8a0, "__ZN6Status9getRatingEv"],
		[0x5ecae, "__ZN6Layout12setOneFooterEjb"],
		[0x5ede0, "__ZN13EquipmentListC1EiiiiiiiihPiPbb"],
		[0x296a8, "__ZN6Status8addKillsEi"],
		[0x448b2, "__ZN5Level10applyKillsEv"],
		[0x3c38e, "__ZN6Status14incPlayingTimeEi"],
		[0x44fa4, "__ZN6Status14incPlayingTimeEi"],
		[0x4671c, "__ZN6Status14incPlayingTimeEi"],
		[0x4cb00, "__ZN6Status14incPlayingTimeEi"],
		[0x4dea6, "__ZN6Status14incPlayingTimeEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported pilot status association at %x." % pair[0])
			return {}
	for guard in [
		[0x5e12e, 0xdb03],
		[0x5e128, 0x0083],
		[0x5e132, 0x2808],
		[0x5e7e0, 0x0043],
		[0x5e7e2, 0x1818],
		[0x5e7ea, 0x1040],
		[0x5e884, 0x1040],
		[0x5ed7e, 0x0089],
		[0x5e736, 0x00c3],
		[0x5e738, 0x1a18],
		[0x5e8c0, 0x4358]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported pilot status layout or reputation rule at %x." % guard[0])
			return {}
	var thresholds: Array = []
	for index in u16(0x5e132) & 255:
		thresholds.append(u32(literal(0x5e122, 2) + index * 4))
	return {
		"box":
		[
			immediate_at(0x5edb0, 3),
			immediate_at(0x5edb4, 3),
			shifted_immediate(0x5edb8, 3),
			shifted_immediate(0x5edbe, 3)
		],
		"list":
		[
			immediate_at(0x5edd8, 1),
			immediate_at(0x5edda, 2),
			immediate_at(0x5eddc, 3),
			immediate_at(0x5edac, 3)
		],
		"labels":
		{
			"title": immediate_at(0x5ed98, 3),
			"back": immediate_at(0x5eca4, 1),
			"level": literal(0x5e9c0, 1),
			"reputation": immediate_at(0x5ea7c, 1),
			"time": immediate_at(0x5eaea, 1),
			"kills": immediate_at(0x5eb3e, 1),
			"missions": immediate_at(0x5ebc0, 1),
			"loyalty": immediate_at(0x5e744, 1) << ((u16(0x5e74c) >> 6) & 31),
			"left_race": literal(0x5e7fa, 1),
			"right_race": shifted_immediate(0x5e81e, 3)
		},
		"images":
		{
			"gauge": ui_region_binding(literal(0x5ed6c, 1)),
			"pointer": ui_region_binding(shifted_immediate(0x5ed7c, 1))
		},
		"protagonist": immediate_at(0x5ed42, 1),
		"name": [embedded_string(literal(0x5e678, 1)), embedded_string(literal(0x5e6ac, 1))],
		"name_y": immediate_at(0x5e688, 2),
		"right_edge": literal(0x5ee26, 3),
		"width_inset": u16(0x5ee28) & 255,
		"loyalty_lines": (1 << ((u16(0x5e736) >> 6) & 31)) - 1,
		"line_step":
		float((1 << ((u16(0x5e7e0) >> 6) & 31)) + 1) / float(1 << ((u16(0x5e7ea) >> 6) & 31)),
		"pointer_inset": u16(0x5e8b2) & 255,
		"pointer_travel_inset": u16(0x5e8be) & 255,
		"pointer_y": -(u16(0x5e8d8) & 255),
		"rating_offset": u16(0x5e8ba) & 255,
		"rating_span": immediate_at(0x5e8bc, 1),
		"reputation_base": shifted_immediate(0x5ea66, 3),
		"reputation_max": immediate_at(0x5e136, 0),
		"reputation_thresholds": thresholds
	}


func hangar_presentation() -> Dictionary:
	for pair in [
		[0x46bde, "__ZN13EquipmentListC1EiiiiiiiihPiPbb"],
		[0x46aa8, "__ZN13EquipmentList10setContentEiP4Ship"],
		[0x46aba, "__ZN13EquipmentList10setContentEiP4Ship"],
		[0x46ae0, "__ZN13EquipmentList10setContentEiP5ArrayIP9EquipmentEPS0_IP4ShipE"],
		[0x183c0, "__ZN8GameText7getTextEi"],
		[0x18550, "__ZN8GameText7getTextEi"],
		[0x17306, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x17346, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x1746a, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x174a8, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported Hangar content association at %x." % pair[0])
			return {}
	for guard in [
		[0x46aa2, 0x2100],
		[0x46ab4, 0x2101],
		[0x46ada, 0x2102],
		[0x46b90, 0x600b],
		[0x46b94, 0x604b],
		[0x46b98, 0x608b],
		[0x183ba, 0x0041],
		[0x1854a, 0x0041]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported Hangar tab or text declaration.")
			return {}
	var pictures := {}
	for record in [
		["ship_icons", 0x172dc, "__ZL9SHIP_LIST"],
		["ship_previews", 0x1731c, "__ZL13SHIP_LIST_BIG"],
		["item_icons", 0x17442, "__ZL9ITEM_LIST"],
		["item_previews", 0x17480, "__ZL13ITEM_LIST_BIG"]
	]:
		var address := symbol_address(record[2])
		var length := symbol_end(address) - address
		if literal(record[1], 3) != address or length <= 0 or length % 2 != 0 or length > 512:
			fail("Unsupported Hangar artwork table.")
			return {}
		var bindings: Array = []
		for index in length / 2:
			bindings.append(hangar_image_binding(u16(address + index * 2)))
		pictures[record[0]] = bindings
	return (
		{
			"tabs":
			[
				{"action": "ship", "label": immediate_at(0x46b8a, 3)},
				{"action": "cargo", "label": immediate_at(0x46b92, 3)},
				{"action": "shop", "label": immediate_at(0x46b96, 3)}
			],
			"box":
			[
				immediate_at(0x46bac, 3),
				immediate_at(0x46bb0, 3),
				shifted_immediate(0x46bb4, 3),
				shifted_immediate(0x46bba, 3)
			],
			"list":
			[
				immediate_at(0x46bc6, 1),
				immediate_at(0x46bc8, 2),
				immediate_at(0x46bd4, 3),
				immediate_at(0x46ba8, 3)
			],
			"pictures": pictures,
			"quantity": hangar_quantity_presentation(),
			"exchange": hangar_exchange_presentation(),
			"scene": hangar_scene_presentation(),
			"hints": hangar_hint_presentation(),
			"description":
			{
				"items": {"base": u16(0x183bc) & 255, "stride": 1 << ((u16(0x183ba) >> 6) & 31)},
				"ships": {"base": u16(0x1854c) & 255, "stride": 1 << ((u16(0x1854a) >> 6) & 31)}
			},
			"labels":
			{
				"back": immediate_at(0x46aec, 1),
				"info": literal(0x46c0a, 3),
				"ships": immediate_at(0x1722c, 1),
				"weapons": immediate_at(0x17376, 1),
				"generators": immediate_at(0x174d8, 1),
				"damage": immediate_at(0x188bc, 1),
				"rate": immediate_at(0x1896a, 1),
				"capacity": immediate_at(0x189cc, 1),
				"recharge": immediate_at(0x18a8e, 1),
				"mounts": immediate_at(0x18bf8, 1),
				"armor": immediate_at(0x18c62, 1),
				"hold": immediate_at(0x18d14, 1),
				"category_base": u16(0x15dbe) & 255
			}
		}
		if error.is_empty()
		else {}
	)


func hangar_hint_presentation() -> Dictionary:
	# Recover message associations and the tab consumers, not the old menu code.
	for pair in [
		[0x46ee0, "__ZN8GameText7getTextEi"],
		[0x46256, "__ZN8GameText7getTextEi"],
		[0x46282, "__ZN8GameText7getTextEi"],
		[0x462b0, "__ZN8GameText7getTextEi"],
		[0x46ee8, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringE"],
		[0x4625e, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringE"],
		[0x4628a, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringE"],
		[0x462b8, "__ZN12ChoiceWindow3setERKN11AbyssEngine6StringE"],
		[0x47e4a, "__ZN10ObjectList13setCurrentTabEi"],
		[0x47e78, "__ZN10ObjectList13setCurrentTabEi"],
		[0x47ea6, "__ZN10ObjectList13setCurrentTabEi"],
		[0x470dc, "__ZN7MHangar16checkHintMessageEv"],
		[0x47088, "__ZN11AbyssEngine18ApplicationManager9SoundPlayEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported Hangar hint consumer at %x." % pair[0])
			return {}
	for pair in [
		[0x4623a, 0x2c01], [0x4626a, 0x2c02], [0x46298, 0x2c03],
		[0x47e46, 0x2100], [0x47e74, 0x2101], [0x47ea2, 0x2102],
		[0x47e50, 0x2301], [0x47e7e, 0x2302], [0x47eac, 0x2303],
		[0x46ecc, 0x781b], [0x46242, 0x7873], [0x46272, 0x78a3], [0x462a0, 0x78e3]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported Hangar first-use hint selection.")
			return {}
	var flags := literal(0x46ec6, 3)
	for address in [0x4623e, 0x4626e, 0x4629c]:
		if literal(address, 3) != flags:
			fail("Unsupported Hangar shared hint history.")
			return {}
	return {
		"messages": {"intro": literal(0x46ed8, 1), "ship": shifted_at(0x4624c, 0x4624e, 1),
			"cargo": literal(0x4627c, 1), "shop": literal(0x462aa, 1)},
		"sound": immediate_at(0x4707e, 1)
	} if error.is_empty() else {}


func hangar_image_binding(resource: int) -> Dictionary:
	# The ship icon descriptor crosses a compiler literal pool.
	if resource != shifted_immediate(0x1c97a, 3):
		return recovery_image_binding(resource)
	for guard in [
		[0x1c8dc, 0xe042],
		[0x1c964, 0x6008],
		[0x1c968, 0x8003],
		[0x1c972, 0x804b],
		[0x1c97c, 0x009b],
		[0x1c982, 0x8003],
		[0x1c992, 0x60c1]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported split Hangar atlas record.")
			return {}
	if literal(0x1c8d6, 1) != literal(0x1c966, 1) or literal(0x1c966, 1) != literal(0x1c978, 1):
		fail("Inconsistent split Hangar atlas record.")
		return {}
	return {"texture": immediate_at(0x1c8d8, 3), "region": immediate_at(0x1c96a, 3)}


func hangar_quantity_presentation() -> Dictionary:
	var create := symbol_address("__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj")
	for at in [0x6839c, 0x683a8, 0x683b4, 0x683c0, 0x683cc, 0x683d8, 0x683e4, 0x683f0]:
		if call_target(at) != create:
			fail("Unsupported cargo sale artwork consumer.")
			return {}
	for pair in [[0x6820e, "__ZN8GameText7getTextEi"], [0x682be, "__ZN8GameText7getTextEi"], [0x47676, "__ZN15SellCargoWindow13getSellAmountEv"]]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported cargo sale presentation consumer.")
			return {}
	# Initial amount equals the supplied stack, with a zero-to-stack stepper.
	for pair in [[0x6836e, 0x6565], [0x68370, 0x6525], [0x67ce8, 0x3b01], [0x67cf0, 0x2300], [0x67cfa, 0x1c5a], [0x67cfc, 0x6d63], [0x67d02, 0xdd00], [0x68426, 0x0080]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported cargo sale quantity declaration at %x." % pair[0])
			return {}
	var images := {"top": hangar_image_binding(shifted_at(0x68392, 0x68396, 1))}
	for pair in [["middle", 0x683a6], ["action_row", 0x683b2], ["bottom", 0x683be], ["button_pressed", 0x683ca], ["button", 0x683d6], ["step", 0x683e2], ["step_pressed", 0x683ee]]:
		images[pair[0]] = hangar_image_binding(literal(pair[1], 1))
	return {
		"images": images,
		"labels": {"sell": immediate_at(0x6820c, 1), "cancel": literal(0x682b0, 1)},
		"minus": embedded_string(literal(0x67fbc, 1)),
		"plus": embedded_string(literal(0x680cc, 1)),
		"suffix": embedded_string(literal(0x67e6c, 3)),
		"y": immediate_at(0x68404, 3),
		"body_rows": 1 << ((u16(0x68426) >> 6) & 31),
		"step_x": u16(0x68448) & 255,
		"step_gap": u16(0x6844e) & 255,
		"step_bottom": u16(0x6845c) & 255,
		"button_x": u16(0x681e2) & 255
	} if error.is_empty() else {}


func hangar_exchange_presentation() -> Dictionary:
	for pair in [
		[0x46590, "__ZN13ShipBuyWindow4drawEv"],
		[0x46e2c, "__ZN13ShipBuyWindowC1Ei"],
		[0x5cac2, "__ZN8GameText7getTextEi"],
		[0x5cd40, "__ZN8GameText7getTextEi"],
		[0x5cece, "__ZN8GameText7getTextEi"],
		[0x5d05e, "__ZN8GameText7getTextEi"],
		[0x5d1b2, "__ZN8GameText7getTextEi"],
		[0x5c964, "__ZN6Layout9getHeightEv"],
		[0x46e14, "__ZN6Layout9getHeightEv"],
		[0x29128, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x5c992, "__ZN6Layout7drawBoxEiiii"],
		[0x5ca5c, "__ZN6Layout7drawBoxEiiii"],
		[0x5ca70, "__ZN6Layout7drawBoxEiiii"],
		[0x5ca84, "__ZN6Layout7drawBoxEiiii"],
		[0x5ca98, "__ZN6Layout7drawBoxEiiii"],
		[0x5caac, "__ZN6Layout7drawBoxEiiii"],
		[0x29076, "__ZN11AbyssEngine11PaintCanvas13FillRectangleEiiii"],
		[0x29086, "__ZN6Layout10drawBorderEiiii"],
		[0x28fee, "__ZN11AbyssEngine11PaintCanvas8SetColorEi"],
		[0x29006, "__ZN11AbyssEngine11PaintCanvas8SetColorEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported ship exchange presentation consumer at %x." % pair[0])
			return {}
	for pair in [[0x29578, 0x614b], [0x29060, 0x6969], [0xc436, 0x0e08], [0x2889c, 0x6919], [0x2911a, 0x3210], [0x46e24, 0x1ad1], [0x5c96c, 0x1a10]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported ship exchange layout association.")
			return {}
	return {
		# The source requests legacy image105, absent from the recovered atlas registry.
		# Preserve the reference; native placement uses the actual imported footer art.
		"layout_measure_resource": immediate_at(0x29116, 1),
		"colors": [literal(0x29576, 3), literal(0x28fe8, 1), literal(0x29004, 1)],
		"labels": {
			"price": immediate_at(0x5cabe, 1),
			"weapons": immediate_at(0x5cd38, 1),
			"cargo": immediate_at(0x5cec6, 1),
			"remaining": immediate_at(0x5d05a, 1),
			"buy": immediate_at(0x5d19e, 1)
		},
		"header": [immediate_at(0x5c990, 1), immediate_at(0x5c98a, 2), u16(0x5c984) & 255, immediate_at(0x5c982, 1)],
		"body_y": immediate_at(0x5ca40, 3),
		"row_x": immediate_at(0x5ca58, 1),
		"row_height": immediate_at(0x5ca50, 3),
		"row_offsets": [-(u16(0x5ca54) & 255), -(u16(0x5ca68) & 255), -(u16(0x5ca7c) & 255), -(u16(0x5ca90) & 255), u16(0x5caa4) & 255]
	} if error.is_empty() else {}


func hangar_scene_presentation() -> Dictionary:
	# Recover constant scene declarations, not the original update implementation.
	for pair in [
		[0x33de6, "__ZN5Level18createHangarObjectEi"],
		[0x33e66, "__ZN5Level18createHangarObjectEi"],
		[0x33ee6, "__ZN5Level18createHangarObjectEi"],
		[0x33e7a, "__ZN12PlayerStatic11setPositionEiii"],
		[0x33f0e, "__ZN12PlayerStatic11setPositionEiii"],
		[0x33e9c, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii"],
		[0x33f32, "__ZN11AbyssEngine6AEMath17MatrixSetRotationERNS0_6MatrixEiii"],
		[0x57b7e, "__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt"],
		[0x57c62, "__ZN11AbyssEngine11PaintCanvas16TransformAddMeshEjt"],
		[0x13cbe, "__ZN11AbyssEngine9EaseInOutC1Eii"],
		[0x136f8, "__ZN11AbyssEngine11PaintCanvas20CameraSetPerspectiveEjiii"],
		[0x13d58, "__ZN11AbyssEngine11PaintCanvas14CameraSetLocalEjRKNS_6AEMath6MatrixE"],
		[0x14806, "__ZN11AbyssEngine9EaseInOut8IncreaseEi"],
		[0x86b2, "__ZN11AbyssEngine6AEMath3SinEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported Hangar scene consumer at %x." % pair[0])
			return {}
	for guard in [
		[0x136e0, 0x2b17], [0x33dd0, 0xd003], [0x14802, 0x00d1],
		[0x33f02, 0x390c], [0x33f04, 0x3a08], [0x33f06, 0x3b04], [0x33f3c, 0x330c],
		[0x57a3e, 0x2b00], [0x57a40, 0xd103],
		[0x57b02, 0xd078], [0x57b0a, 0xd053], [0x57b12, 0xd039],
		[0x57b16, 0xd000], [0x57b1e, 0xd054], [0x57b22, 0xd000]
	]:
		if u16(guard[0]) != guard[1]:
			fail("Unsupported Hangar scene layout at %x." % guard[0])
			return {}
	var race := u16(0x33dce) & 255
	if u16(0x33dce) & 0xff00 != 0x2b00 or u16(0x13cf4) != 0x2800 | race:
		fail("Unsupported Hangar race selection.")
		return {}
	if (
		literal(0x33dd2, 1) != literal(0x68982, 3)
		or literal(0x33dd2, 1) != literal(0x57b3e, 3)
		or shifted_immediate(0x33dda, 1) != shifted_immediate(0x68996, 3)
		or shifted_immediate(0x33dda, 1) != shifted_immediate(0x57b44, 3)
		or not symbols.get("__ZL13BUYABLE_SHIPS", []).has(literal(0x33e5e, 3))
		or literal(0x33ede, 3) != literal(0x33e5e, 3)
		or literal(0x33ef2, 3) != symbol_address("__ZL8SHIP_POS")
	):
		fail("Unsupported Hangar actor/table association.")
		return {}
	var placements := named_array("__ZL8SHIP_POS")
	if placements.is_empty() or placements.size() % 3 != 0:
		fail("Unsupported Hangar parking positions.")
		return {}
	var positions: Array = []
	for index in range(0, placements.size(), 3):
		positions.append(placements.slice(index, index + 3))
	var shadows := {}
	for binding in [
		[0x57b10, 0x57b9a], [0x57b14, 0x57bb0], [0x57b08, 0x57bc6],
		[0x57b1c, 0x57bdc], [0x57b20, 0x57bf2], [0x57b00, 0x57c08],
		[0x57b32, 0x57c1e], [0x57b36, 0x57c34], [0x57b28, 0x57c4a],
		[0x57b4c, 0x57c60]
	]:
		if u16(binding[0]) & 0xff00 != 0x2900:
			fail("Unsupported Hangar shadow actor.")
			return {}
		shadows[str(u16(binding[0]) & 255)] = literal(binding[1], 2)
	var yaw := shifted_immediate(0x33e90, 3)
	if yaw != shifted_at(0x33f26, 0x33f2a, 3):
		fail("Inconsistent Hangar ship orientation.")
		return {}
	var phase_start := shifted_at(0x8722, 0x8726, 3)
	var phase_end := shifted_immediate(0x86f6, 3)
	var result := {
		"race": race,
		"interiors": {
			"default": {"body": literal(0x6898c, 1), "lights": literal(0x57b66, 2)},
			"race": {"body": literal(0x68c22, 4), "lights": literal(0x57b7c, 2)}
		},
		"player_position": [signed_literal(0x33e74, 1), signed_literal(0x33e6c, 2), signed_literal(0x33e6e, 3)],
		"stock_positions": positions,
		"yaw_units": yaw,
		"shadows": shadows,
		"shadow_y": signed_literal(0x57a44, 1),
		"drift": hangar_camera_drift(),
		"camera": {
			"x_default": literal(0x13d00, 2), "x_race": shifted_immediate(0x13cf8, 1),
			"y": shifted_immediate(0x13d36, 3),
			"z_start": signed_literal(0x13cb8, 1), "z_end": signed_literal(0x13cba, 2),
			"forward": [-signed_literal(0x13d24, 3), -shifted_immediate(0x13d28, 3), -signed_literal(0x13d2e, 3)],
			"up": [signed_literal(0x13d18, 3), signed_literal(0x13d1c, 3), signed_literal(0x13d20, 3)],
			"fov_units": literal(0x136f2, 2), "near": immediate_at(0x136f4, 3), "far": literal(0x13690, 5),
			"entrance_seconds": float(phase_end - phase_start) / float((1 << ((u16(0x14802) >> 6) & 31)) * 1000)
		}
	}
	if not preload("res://src/presentation/hangar_scene.gd").valid_data(result):
		fail("Invalid supplied Hangar scene declaration.")
	return result if error.is_empty() else {}


func hangar_camera_drift() -> Dictionary:
	for pair in [
		[0x14710, "__ZN11AbyssEngine9EaseInOut8SetRangeEii"],
		[0x14762, "__ZN11AbyssEngine9EaseInOut8SetRangeEii"],
		[0x147ca, "__ZN11AbyssEngine9EaseInOut8SetRangeEii"],
		[0x14886, "__ZN11AbyssEngine9EaseInOut8IncreaseEi"],
		[0x1493a, "__ZN11AbyssEngine9EaseInOut8IncreaseEi"],
		[0x149e0, "__ZN11AbyssEngine9EaseInOut8IncreaseEi"],
		[0x148aa, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x148f8, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x14960, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x149ac, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x14a08, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x14a52, "__ZN11AbyssEngine8AERandom7nextIntEi"],
		[0x146aa, "__ZN18TargetFollowCamera12setLookAtCamEb"],
		[0x146c0, "__ZN18TargetFollowCamera9setTargetEj"],
		[0x5f714, "__ZN11AbyssEngine6AEMath11MatrixGetUpERKNS0_6MatrixE"],
		[0x5f72a, "__ZN11AbyssEngine6AEMath17MatrixGetPositionERKNS0_6MatrixE"],
		[0x136da, "__ZN11AbyssEngine11PaintCanvas20CameraSetPerspectiveEjiii"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported Hangar drift consumer at %x." % pair[0])
			return {}
	for pair in [
		[0x14884, 0x0051], [0x14936, 0x0051], [0x149dc, 0x0069],
		[0x148ba, 0x1a12], [0x14906, 0x1a12], [0x14972, 0x1a52],
		[0x149ba, 0x1852], [0x14a1c, 0x1a52], [0x14a68, 0x1852],
		[0x148be, 0xdc28], [0x1490c, 0xdb01],
		[0x146a6, 0x2101], [0x146bc, 0x681b], [0x146be, 0x6899]
	]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported Hangar drift range/target at %x." % pair[0])
			return {}
	var threshold := u16(0x1489a) & 255
	for address in [0x1489a, 0x1494e, 0x149f8]:
		if u16(address) != 0x3800 | threshold:
			fail("Unsupported Hangar drift upper threshold.")
			return {}
	for address in [0x148e8, 0x1499e, 0x14a44]:
		if u16(address) != 0x3000 | threshold:
			fail("Unsupported Hangar drift lower threshold.")
			return {}
	for pair in [[0x14904, 0x3200], [0x149b4, 0x3200], [0x148c2, 0x3a00], [0x14910, 0x3200]]:
		if u16(pair[0]) & 0xff00 != pair[1]:
			fail("Unsupported Hangar drift immediate.")
			return {}
	if (u16(0x148c2) & 255) != (u16(0x14910) & 255):
		fail("Inconsistent Hangar X reversal margin.")
		return {}
	var result := {
		"initial_low": [signed_literal(0x14706, 2), signed_literal(0x14758, 2), signed_literal(0x147c0, 2)],
		"initial_high": [shifted_immediate(0x14700, 2), immediate_at(0x14754, 2), shifted_immediate(0x147a6, 2)],
		"low_offset": [signed_literal(0x148b4, 4), signed_literal(0x1496e, 5), signed_literal(0x14a14, 3)],
		"low_spread": [shifted_immediate(0x148a2, 1), shifted_immediate(0x14956, 1), shifted_immediate(0x14a00, 1)],
		"high_offset": [u16(0x14904) & 255, u16(0x149b4) & 255, shifted_immediate(0x14a5e, 3)],
		"high_spread": [-immediate_at(0x148f0, 1), immediate_at(0x149a6, 1), immediate_at(0x14a4c, 1)],
		"reversal_margin": [u16(0x148c2) & 255, 0, 0],
		"seconds": float(shifted_immediate(0x86f6, 3) - shifted_at(0x8722, 0x8726, 3)) / float((1 << ((u16(0x14884) >> 6) & 31)) * 1000),
		"threshold": threshold,
		"fov_units": literal(0x136d6, 2), "near": immediate_at(0x136d4, 3), "far": literal(0x13690, 5)
	}
	if not preload("res://src/presentation/hangar_drift.gd").valid_data(result):
		fail("Invalid supplied Hangar drift declaration.")
	return result if error.is_empty() else {}


func mission_board_presentation() -> Dictionary:
	for pair in [
		[0x48d64, "__ZN11MissionListC1EiiiiiiiihPiPbb"],
		[0x48dd4, "__ZN6Layout12setOneFooterEjb"],
		[0x4903c, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x4904c, "__ZN11AbyssEngine11PaintCanvas13Image2DCreateEtRj"],
		[0x49164, "__ZN7Mission14getClientImageEv"],
		[0x49194, "__ZN7Mission13getClientNameEv"],
		[0x4926e, "__ZN7Mission19getClientProfessionEv"],
		[0x492d8, "__ZN7Mission13getDifficultyEv"],
		[0x49350, "__ZN7Mission9getRewardEv"],
		[0x494d6, "__ZN13MissionWindow3setEP7Mission"],
		[0x49500, "__ZN6Status10setMissionEP7Mission"],
		[0x49758, "__ZN11AbyssEngine11PaintCanvas8SetColorEhhhh"],
		[0x49768, "__ZN11AbyssEngine11PaintCanvas13FillRectangleEiiii"],
		[0x48998, "__ZN8GameText7getTextEi"],
		[0x48a64, "__ZN8GameText7getTextEi"],
		[0x48af6, "__ZN8GameText7getTextEi"],
		[0x48bb8, "__ZN8GameText7getTextEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported mission-board consumer at %x." % pair[0])
			return {}
	for pair in [[0x483bc, 0x281f], [0x49182, 0x231f], [0x49318, 0x2806], [0x482a4, 0x1cd9], [0x49082, 0x3b03]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported mission-board selection/layout.")
			return {}
	var result := {
		"box": [immediate_at(0x48d34, 3), immediate_at(0x48d38, 3), shifted_immediate(0x48d3c, 3), shifted_immediate(0x48d42, 3)],
		"list": [immediate_at(0x48d5c, 1), immediate_at(0x48d5e, 2), immediate_at(0x48d60, 3), immediate_at(0x48d30, 3)],
		"row_height": immediate_at(0x48250, 0), "row_gap": (u16(0x482a4) >> 6) & 7,
		"images": {"button": hangar_image_binding(shifted_immediate(0x4902c, 1)), "pressed": hangar_image_binding(shifted_immediate(0x49042, 1))},
		"labels": {
			"title": shifted_immediate(0x48d1a, 3), "back": immediate_at(0x48dce, 1),
			"info": literal(0x48ae8, 1), "accept": immediate_at(0x48baa, 1),
			"difficulty": immediate_at(0x48990, 1), "reward": immediate_at(0x48a60, 1),
			"empty": shifted_immediate(0x48fb8, 1), "special": literal(0x483c2, 1),
			"special_description": shifted_at(0x4985a, 0x4985e, 1), "description": immediate_at(0x4991a, 1)
		},
		"profile": [shifted_immediate(0x48918, 3), immediate_at(0x48920, 3), shifted_at(0x48902, 0x48906, 2)],
		"profession_width": immediate_at(0x4928c, 3),
		"stat_lines": (1 << ((u16(0x4897a) >> 6) & 31)) + 1 + 2,
		"button_end": [literal(0x49074, 3), literal(0x4907a, 3)], "button_gap": u16(0x49082) & 255,
		"rate_prefix": embedded_string(literal(0x4931e, 1)),
		"special_portrait": u16(0x483bc) & 255
	}
	result.description_box = [immediate_at(0x49764, 1), immediate_at(0x49766, 2), immediate_at(0x4970a, 3), immediate_at(0x4970e, 3)]
	result.description_fill = [immediate_at(0x4974c, 1), immediate_at(0x4974e, 2), immediate_at(0x49756, 3), immediate_at(0x4974a, 3)]
	if not preload("res://src/presentation/mission_board.gd").valid_data(result):
		fail("Invalid supplied mission-board presentation.")
	return result if error.is_empty() else {}


func destination_presentation() -> Dictionary:
	for pair in [
		[0x52d70, "__ZN13EquipmentListC1EiiiiiiiihPiPbb"],
		[0x52258, "__ZN13EquipmentList13drawRightInfoEP8ListItembbb"],
		[0x4cfec, "__ZN16PlanetInfoWindow3setEP7Stationii"],
		[0x4cffc, "__ZN16PlanetInfoWindow11sameStationEv"],
		[0x4d00e, "__ZN6Layout9setFooterEjj"],
		[0x4d022, "__ZN6Layout12setOneFooterEjb"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported destination interface at %x." % pair[0])
			return {}
	var result := {
		"box": [immediate_at(0x52d40, 3), immediate_at(0x52d44, 3), shifted_immediate(0x52d48, 3), shifted_immediate(0x52d4e, 3)],
		"list": [immediate_at(0x52d68, 1), immediate_at(0x52d6a, 2), immediate_at(0x52d6c, 3), immediate_at(0x52d3c, 3)]
	}
	result.scene = destination_scene_presentation()
	if not preload("res://src/presentation/destination_menu.gd").valid_layout(result):
		fail("Invalid destination layout declaration.")
	return result if error.is_empty() else {}


func destination_scene_presentation() -> Dictionary:
	for pair in [
		[0x52bea, "__ZN8CutSceneC1Ei"],
		[0x52c20, "__ZN8CutSceneC1Ei"],
		[0x542c2, "__ZN11AbyssEngine11PaintCanvas15TransformCreateERj"],
		[0x137be, "__ZN18TargetFollowCameraC1EjjN11AbyssEngine6AEMath6VectorES2_"],
		[0x13ade, "__ZN5Level18setStationPositionEN11AbyssEngine6AEMath6VectorE"],
		[0x136da, "__ZN11AbyssEngine11PaintCanvas20CameraSetPerspectiveEjiii"],
		[0x5f7bc, "__ZN11AbyssEngine6AEMath21MatrixTransformVectorERKNS0_6MatrixERKNS0_6VectorE"],
		[0x5f7d6, "__ZN11AbyssEngine6AEMath21MatrixTransformVectorERKNS0_6MatrixERKNS0_6VectorE"],
		[0x5f8d0, "__ZN11AbyssEngine6AEMath15MatrixGetLookAtERKNS0_6VectorES3_S3_"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported destination scene consumer at %x." % pair[0])
			return {}
	var planet := immediate_at(0x52be6, 1)
	var orbital := immediate_at(0x52c1c, 1)
	for mode in [planet, orbital]:
		for entry in [[0x137f8, 0x13a78], [0x142fc, 0x14b86], [0x33c98, 0x3480a]]:
			if mode < 3 or mode >= 3 + u32(entry[0]) or entry[0] + u32(entry[0] + 4 + (mode - 3) * 4) != entry[1]:
				fail("Unsupported destination initialization/update branch.")
				return {}
	for pair in [[0x5f830, 0xa94b], [0x542c0, 0x310c], [0x13782, 0x68c0], [0x5f5ee, 0x54e5], [0x5f5fa, 0x54e5]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported destination camera target/anchor at %x." % pair[0])
			return {}
	var result := {
		"planet_mode": planet, "orbital_mode": orbital,
		"look_offset": [immediate_at(0x1377e, 4), signed_literal(0x1377a, 3), immediate_at(0x1377e, 4)],
		"position_offset": [immediate_at(0x1377e, 4), signed_literal(0x1377a, 3) + (u16(0x13786) & 255), signed_literal(0x1378a, 3)],
		"look_blend": 1.0 / float(1 << ((u16(0x5f7fa) >> 6) & 31)),
		"position_blend": 1.0 / float(1 << ((u16(0x5f83a) >> 6) & 31)),
		"initial_scale": 1.0 / float(1 << ((u16(0x5f8e2) >> 6) & 31)),
		"reference_seconds": wreck_drift().get("reference_seconds", 0),
		"station_z": int(normalized_vector_unit()) >> ((u16(0x13ab2) >> 6) & 31),
		"special_type": u16(0x13ac0) & 255, "special_z": signed_literal(0x13ac4, 3),
		"fov_units": literal(0x136d6, 2), "near": immediate_at(0x136d4, 3), "far": literal(0x13690, 5)
	}
	if not preload("res://src/presentation/destination_scene.gd").valid_data(result):
		fail("Invalid destination scene constants.")
	return result if error.is_empty() else {}


func map_layout() -> Dictionary:
	# Original map bounds and annotations, independent of native input/navigation.
	var image := symbol_address("__ZN11AbyssEngine11PaintCanvas11DrawImage2DEjiihh")
	var text := symbol_address("__ZN8GameText7getTextEi")
	if (
		call_target(0x4b8fa) != image or call_target(0x4bccc) != image
		or call_target(0x4bce6) != image or call_target(0x4a758) != text
		or call_target(0x4b94c) != text
		or call_target(0x4c4ec) != symbol_address("__ZN10ObjectListC1EiiiiiiiihPiPbb")
		or u16(0x4c674) != 0x65a3 or u16(0x4c684) != 0x65e1
	):
		fail("Unsupported map layout or annotation declarations.")
		return {}
	return {
		"box": [immediate_at(0x4c4c0,3), immediate_at(0x4c4c4,3), shifted_immediate(0x4c4c8,3), shifted_immediate(0x4c4ce,3)],
		"board": [immediate_at(0x4c672,3), immediate_at(0x4c666,1), shifted_immediate(0x4c418,3), immediate_at(0x4c422,2)],
		"galaxy_origin": [immediate_at(0x4b8b0,2), immediate_at(0x4b8b2,3)],
		"stars_origin": [immediate_at(0x4b8d0,2), immediate_at(0x4b8d2,3)],
		"nebula_origin": [immediate_at(0x4c47c,2), immediate_at(0x4c48a,2)],
		"position_label": literal(0x4a756,1),
		"exploration_label": shifted_at(0x4b940,0x4b944,1),
		"separator": embedded_string(literal(0x4adb2,1)),
		"percent_prefix": embedded_string(literal(0x4ade6,1)),
		"percent_suffix": embedded_string(literal(0x4ae18,1)),
		"exploration_suffix": embedded_string(literal(0x4b926,1)),
		"distance_suffix": embedded_string(literal(0x4b6fa,1)),
		"grid_color": literal(0x4ad0a,1),
		"cursor_color": literal(0x4b5ea,1),
		"position_color": literal(0x4a742,1)
	}


func opening_scene_presentation() -> Dictionary:
	# Constant cinematic shot declarations; native code owns sequencing and math.
	for pair in [
		[0x3ca80,"__ZN8CutScene4skipEi"], [0x13f28,"__ZN8CutScene14initIntroPage2Ev"],
		[0x14098,"__ZN8CutScene14initIntroPage6Ev"], [0x141a6,"__ZN8CutScene15initHangarSceneEv"],
		[0x33d66,"__ZN5Level10createShipEiiibP8Waypoint"], [0x33d7c,"__ZN17PlayerFixedObject11setPositionEiii"],
		[0x1359e,"__ZN11AbyssEngine11PaintCanvas14CameraSetLocalEjRKNS_6AEMath6MatrixE"],
		[0x135bc,"__ZN5Level18setStationPositionEN11AbyssEngine6AEMath6VectorE"],
		[0x13a18,"__ZN11AbyssEngine9EaseInOut8SetRangeEii"], [0x1351a,"__ZN11AbyssEngine9EaseInOut8SetRangeEii"],
		[0x14024,"__ZN11AbyssEngine9EaseInOut8SetRangeEii"], [0x1404a,"__ZN18TargetFollowCamera11setPositionEiii"],
		[0x134cc,"__ZN11AbyssEngine11PaintCanvas14CameraSetLocalEjRKNS_6AEMath6MatrixE"],
		[0x3c46a,"__ZN8CutScene12getFadeAlphaEv"], [0x86b2,"__ZN11AbyssEngine6AEMath3SinEi"]
	]:
		if call_target(pair[0]) != symbol_address(pair[1]):
			fail("Unsupported opening shot declaration at %x." % pair[0])
			return {}
	for pair in [[0x13ed0,0x1e83],[0x14186,0x2b09],[0x141e0,0x2306],[0x14404,0x011b],[0x14456,0x011b],[0x14430,0x0051],[0x144fa,0x1300],[0x135ac,0x109b],[0x1407c,0x3814],[0x14162,0x10a3],[0x1422a,0x10ab]]:
		if u16(pair[0]) != pair[1]:
			fail("Unsupported opening shot units or transition at %x." % pair[0])
			return {}
	var table := 0x13ed8
	if u32(table) != 8 or table+u32(table+4) != 0x13f00 or table+u32(table+8) != 0x13f2e or table+u32(table+20) != 0x14060 or table+u32(table+32) != 0x1409e:
		fail("Unsupported opening page-to-shot table.")
		return {}
	var range_start := shifted_immediate(0x13a12,1)
	var range_end := literal(0x13a0e,2)
	var yaw := shifted_immediate(0x13568,3) * TAU / 65536.0
	var position := Vector3(immediate_at(0x13552,2),signed_literal(0x13556,3),signed_literal(0x13550,3))
	var unit := normalized_vector_unit()
	position += Vector3(sin(yaw)*unit,0,cos(yaw)*unit*.75)
	var result := {
		"actor": immediate_at(0x33d62,3),
		"station_page": (u16(0x13ed0)>>6)&7,
		"ship_page": ((u16(0x13ed0)>>6)&7)+1,
		"departure_page": immediate_at(0x141e0,3),
		"hangar_page": u16(0x14186)&255,
		"pan_range": [range_start,range_end],
		"station_range": [range_end,shifted_immediate(0x13512,2)],
		"pan_camera": [0,signed_literal(0x13a38,3),0],
		"station_camera": [0,signed_literal(0x13a38,3),0],
		"station_position": [position.x,position.y,position.z],
		"initial_station_z": signed_literal(0x1437c,3),
		"initial_ship_z": signed_literal(0x33d76,3),
		"ship_camera": [signed_literal(0x1402e,1),signed_literal(0x14016,3),signed_literal(0x14044,0)],
		"ship_height": [signed_literal(0x14016,3),signed_literal(0x1401a,3)],
		"ease_seconds": float(shifted_immediate(0x86f6,3)-shifted_at(0x8722,0x8726,3))/1000.0,
		"fade_seconds": float(immediate_at(0x1416c,3)*(1<<((u16(0x14162)>>6)&31)))/1000.0,
		"pan_start_seconds": float(immediate_at(0x13a1e,1)+shifted_immediate(0x143b8,1))/1000.0,
		"yaw_scale": 1<<((u16(0x14404)>>6)&31),
		"station_rate": 1<<((u16(0x14430)>>6)&31),
		"ship_speed": float(1<<((u16(0x144e6)>>6)&31))*1000.0/immediate_at(0x144e0,1),
		"slow_start": signed_literal(0x144d6,2),
		"stop_z": signed_literal(0x144ea,2),
		"slow_seconds": float(1<<((u16(0x144fa)>>6)&31))/1000.0,
		"departure_min_z": signed_literal(0x13460,3),
		"departure_snap_z": signed_literal(0x13468,3),
		"camera_ready_margin": u16(0x1407c)&255,
		"fov_units": literal(0x136a4,2),"near":immediate_at(0x136a8,3),"far":literal(0x1369e,3)
	}
	if not preload("res://src/presentation/opening_choreography.gd").valid_data(result):
		fail("Invalid opening cinematic constants.")
		return {}
	return result if error.is_empty() else {}


func briefing_audio() -> Dictionary:
	var voice := symbol_address("__ZN16BriefingDialogue10getSoundIDEv")
	var touch := symbol_address("__ZN9MBriefing10OnTouchEndEii")
	var initialize := symbol_address("__ZN9MBriefing12OnInitializeEv")
	var title := symbol_address("__ZN9MMainMenu12OnInitializeEv")
	var station := symbol_address("__ZN8MStation12OnInitializeEv")
	var music := symbol_address("__ZN11AbyssEngine18ApplicationManager18SoundPlayMusicLoopEi")
	var play := symbol_address("__ZN11AbyssEngine18ApplicationManager9SoundPlayEi")
	if (
		call_target(title + 0x1a2) != music
		or call_target(station + 0xcf6) != music
		or u16(station + 0xcc2) & 0xff00 != 0x2800
		or literal(voice + 2, 2) != symbol_address(TABLES.dialogue_starts)
		or literal(voice + 4, 1) != symbol_address(TABLES.dialogue_ids)
		or u16(voice + 0x12) & 0xff00 != 0x3800
		or call_target(initialize + 0x356) != voice
		or call_target(initialize + 0x35e) != play
		or call_target(touch + 0x11c) != play
		or call_target(touch + 0x17c) != play
		or call_target(touch + 0x240) != voice
		or call_target(touch + 0x248) != play
	):
		fail("Unsupported briefing audio declarations.")
		return {}
	return {
		"music": {
			"title": immediate_at(title + 0x19a, 1),
			"station": immediate_at(station + 0xccc, 2),
			"alien": immediate_at(station + 0xcc6, 1),
			"alien_race": u16(station + 0xcc2) & 255
		},
		"voice_text_offset": u16(voice + 0x12) & 255,
		"next": immediate_at(touch + 0x174, 1),
		"back": immediate_at(touch + 0x118, 1),
		"skip": immediate_at(touch + 0x258, 1),
		"confirm": immediate_at(touch + 0x42, 1)
	}


func public_survival_type() -> int:
	# Menu Start and its replacement-confirmation both select generated slot 1.
	# The wave record in slot 0 is not a selectable mode in this iPhone menu.
	var touch := symbol_address("__ZN10MenuWindow8touchEndEii")
	var generator := symbol_address("__ZN9Generator24getInstantActionMissionsEv")
	var initialize := symbol_address("__ZN10MenuWindow10initializeEi")
	var menu := symbol_address("__ZN10MenuWindow10switchMenuEj")
	var clone := symbol_address("__ZN7Mission5cloneEv")
	var assign := symbol_address("__ZN6Status10setMissionEP7Mission")
	if (
		call_target(initialize + 0x678) != generator
		or call_target(touch + 0x152) != clone
		or call_target(touch + 0x15a) != assign
		or call_target(touch + 0x40a) != clone
		or call_target(touch + 0x412) != assign
		or call_target(generator + 0x150) != symbol_address("__ZN7MissionC1EiN11AbyssEngine6StringEiiiiii")
		or u16(touch + 0x100) & 0xff00 != 0x2b00
		or u16(menu + 0x1ea) & 0xff00 != 0x2800
		or (u16(touch + 0x100) & 255) != (u16(menu + 0x1ea) & 255)
	):
		fail("Unsupported public survival launch association.")
		return -1
	for guard in [
		[touch,0x14a,0x6a33], [touch,0x14e,0x685b], [touch,0x150,0x6858],
		[touch,0x402,0x6a33], [touch,0x406,0x685b], [touch,0x408,0x6858],
		[generator,0xec,0x6853], [generator,0xee,0x3304], [generator,0x164,0x6013],
		[generator,0x176,0x6858]
	]:
		if u16(guard[0] + guard[1]) != guard[2]:
			fail("Unsupported generated mission selection in public survival.")
			return -1
	return immediate_at(generator + 0x14a, 1)
