class_name Gen3Importer
extends RefCounted

const TMHM_COUNT: int = 58 # `sTMHMMoves`' TMs and HMs.

## The `GAME_CODE` and `GAME_REVISION` each pret Makefile hands `gbafix`.
const HEADERS: Dictionary = {
	RomRegistry.RUBY: ["AXVE", 2],
	RomRegistry.SAPPHIRE: ["AXPE", 2],
	RomRegistry.FIRERED: ["BPRE", 1],
	RomRegistry.LEAFGREEN: ["BPGE", 1],
	RomRegistry.EMERALD: ["BPEE", 0],
	RomRegistry.HEARTSOUL: ["BPEE", 0],
}

## Endpoints from pret's data files, the same on all five.
const FIRST_SPECIES_NAME: String = "BULBASAUR"
const LAST_SPECIES_NAME: String = "CHIMECHO"
const LAST_SPECIES: int = 411
const DEX_NUMBERS: Dictionary = {1: [1, 203], 277: [252, 1], 411: [358, 151]}
const FIRST_INFO: Array[int] = [45, 49, 49, 45, 65, 65, 12, 3, 45, 64]
const FIRST_MOVE_NAME: String = "POUND"
const LAST_MOVE_NAME: String = "PSYCHO BOOST"
const FIRST_MOVE: Array[int] = [0, 40, 0, 100, 35]
const LAST_MOVE: Array[int] = [140, 14, 90, 5]
const FIRST_TYPE_NAME: String = "NORMAL"
const MYSTERY_TYPE_NAME: String = "???"
const LAST_TYPE_NAME: String = "DARK"
const FIRST_LEARNSET_WORD: int = (1 << Gen3Layout.LEARNSET_LEVEL_SHIFT) | 33
const FIRST_EVOLUTION: Array[int] = [4, 16, 2]
const UNUSED_ITEM_NAME: String = "????????"
const FIRST_ITEM_NAME: String = "MASTER BALL"
const FIRST_ABILITY_NAME: String = "STENCH"
const LAST_ABILITY_NAME: String = "AIR LOCK"
const DEX_ENDPOINTS: Dictionary = {1: ["SEED", 7, 69], 386: ["DNA", 17, 608]}

static var LAYOUT_CHECKS: Array[Callable] = [
	_verify_header,
	_verify_species_names,
	_verify_species_info,
	_verify_dex_numbers,
	_verify_moves,
	_verify_type_names,
	_verify_matchups,
	_verify_learnsets,
	_verify_evolutions,
	_verify_items,
	_verify_abilities,
	_verify_dex_entries,
	Gen3Pics.verify,
	Gen3Trainers.verify,
	Gen3World.verify,
]


static func verify_layout(rom: RomFile) -> Dictionary:
	var layout: Dictionary = Gen3Layout.for_id(rom.id)
	if layout.is_empty() or not HEADERS.has(rom.id):
		return _fail("No Generation 3 layout for %s." % rom.id)
	for check: Callable in LAYOUT_CHECKS:
		var result: Dictionary = check.call(rom, layout)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true, "message": "Layout verified."}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


static func _ok() -> Dictionary:
	return {"ok": true, "message": ""}


static func _verify_header(rom: RomFile, _layout: Dictionary) -> Dictionary:
	var header: GbaHeader = GbaHeader.parse(rom)
	var wanted: Array = HEADERS[rom.id]
	if header.game_code != String(wanted[0]) or header.version != int(wanted[1]):
		return _fail("%s claims to be %s revision %d, not %s revision %d." % [
			RomRegistry.title_for(rom.id), header.game_code, header.version,
			wanted[0], wanted[1],
		])
	return _ok()


static func _species_name(rom: RomFile, layout: Dictionary, species: int) -> String:
	return Gen3Text.decode_fixed(
		rom.id, rom.bytes(), Gen3Layout.species_name_offset(layout, species), Gen3Layout.species_name_size(layout)
	)


static func _verify_species_names(rom: RomFile, layout: Dictionary) -> Dictionary:
	var first: String = _species_name(rom, layout, 1)
	var last_index: int = int(layout.get("verify_last_species", Gen3Layout.species_count(layout) - 1))
	var last: String = _species_name(rom, layout, last_index)
	var last_name: String = String(layout.get("verify_last_species_name", LAST_SPECIES_NAME))
	if first != FIRST_SPECIES_NAME or last != last_name:
		return _fail("gSpeciesNames reads '%s' and '%s'." % [first, last])
	return _ok()


static func _verify_species_info(rom: RomFile, layout: Dictionary) -> Dictionary:
	var at: int = Gen3Layout.species_info_offset(layout, 1)
	var read: Array[int] = []
	for field: int in Gen3Layout.INFO_EXP_YIELD + 1:
		read.append(rom.u8(at + field))
	var wanted: Array = layout.get("verify_first_info", FIRST_INFO)
	if read != wanted:
		return _fail("Bulbasaur's species info reads %s." % str(read))
	return _ok()


static func _verify_dex_numbers(rom: RomFile, layout: Dictionary) -> Dictionary:
	var wanted: Dictionary = layout.get("verify_dex_numbers", DEX_NUMBERS)
	for species: int in wanted:
		var read: Array = [
			Gen3Layout.national_number(rom, layout, species),
			Gen3Layout.hoenn_number(rom, layout, species),
		]
		if read != wanted[species]:
			return _fail("Species %d has dex numbers %s." % [species, str(read)])
	if Gen3Layout.species_by_national(rom, layout).size() != Gen3Layout.national_dex_count(layout):
		return _fail("The national dex table does not name %d species once each."
			% Gen3Layout.national_dex_count(layout))
	return _ok()


static func _move_name(rom: RomFile, layout: Dictionary, move: int) -> String:
	if layout.has("move_name_pointer"):
		var text: Variant = _pointed_text(rom, Gen3Layout.move_offset(layout, move))
		return String(text) if text != null else ""
	return Gen3Text.decode_fixed(
		rom.id, rom.bytes(), Gen3Layout.move_name_offset(layout, move), Gen3Layout.MOVE_NAME_SIZE
	)


## One move's battle data, decoded from the cartridge's move struct. Vanilla packs the
## fields as single bytes; pokeemerald-expansion packs them as bitfields in a 68-byte struct.
static func _move_record(rom: RomFile, layout: Dictionary, move: int) -> Dictionary:
	var at: int = Gen3Layout.move_offset(layout, move)
	if layout.has("move_name_pointer"):
		var type_power: int = rom.u16le(at + 10)
		var acc_target: int = rom.u16le(at + 12)
		var priority: int = rom.u32le(at + 16) & 0xF
		if priority >= 8:
			priority -= 16
		return {
			"effect": rom.u16le(at + 8),
			"power": (type_power >> 7) & 0x1FF,
			"type": type_power & 31,
			"category": (type_power >> 5) & 3,
			"accuracy": acc_target & 0x7F,
			"pp": rom.u8(at + 14),
			"effect_chance": 0,  # lives in the move's AdditionalEffect list, not MoveInfo
			"target": (acc_target >> 7) & 0x1FF,
			"priority": priority,
			"flags": 0,  # MoveInfo flags are spread across bitfield words; not mapped yet
		}
	return {
		"effect": rom.u8(at + Gen3Layout.MOVE_EFFECT),
		"power": rom.u8(at + Gen3Layout.MOVE_POWER),
		"type": rom.u8(at + Gen3Layout.MOVE_TYPE),
		"accuracy": rom.u8(at + Gen3Layout.MOVE_ACCURACY),
		"pp": rom.u8(at + Gen3Layout.MOVE_PP),
		"effect_chance": rom.u8(at + Gen3Layout.MOVE_EFFECT_CHANCE),
		"target": rom.u8(at + Gen3Layout.MOVE_TARGET),
		"priority": rom.s8(at + Gen3Layout.MOVE_PRIORITY),
		"flags": rom.u8(at + Gen3Layout.MOVE_FLAGS),
	}


static func _move_matches(record: Dictionary, wanted: Dictionary) -> bool:
	for key: String in wanted:
		if record.get(key) != wanted[key]:
			return false
	return true


static func _verify_moves(rom: RomFile, layout: Dictionary) -> Dictionary:
	var last_move: int = Gen3Layout.moves_count(layout) - 1
	var first_name: String = _move_name(rom, layout, 1)
	var last_name: String = _move_name(rom, layout, last_move)
	var last_name_wanted: String = String(layout.get("verify_last_move_name", LAST_MOVE_NAME))
	if first_name != FIRST_MOVE_NAME or last_name != last_name_wanted:
		return _fail("gMoveNames reads '%s' and '%s'." % [first_name, last_name])
	var first_wanted: Dictionary = layout.get("verify_first_move", {
		"effect": FIRST_MOVE[0], "power": FIRST_MOVE[1], "type": FIRST_MOVE[2],
		"accuracy": FIRST_MOVE[3], "pp": FIRST_MOVE[4],
	})
	var last_wanted: Dictionary = layout.get("verify_last_move", {
		"power": LAST_MOVE[0], "type": LAST_MOVE[1], "accuracy": LAST_MOVE[2], "pp": LAST_MOVE[3],
	})
	if not _move_matches(_move_record(rom, layout, 1), first_wanted) \
		or not _move_matches(_move_record(rom, layout, last_move), last_wanted):
		return _fail("gBattleMoves reads %s and %s." % [
			str(_move_record(rom, layout, 1)), str(_move_record(rom, layout, last_move)),
		])
	return _ok()


static func _type_name(rom: RomFile, layout: Dictionary, type: int) -> String:
	return Gen3Text.decode_fixed(
		rom.id, rom.bytes(), Gen3Layout.type_name_offset(layout, type), Gen3Layout.type_name_size(layout)
	)


static func _verify_type_names(rom: RomFile, layout: Dictionary) -> Dictionary:
	var read: Array = [
		_type_name(rom, layout, 0),
		_type_name(rom, layout, Gen3Layout.type_mystery(layout)),
		_type_name(rom, layout, Gen3Layout.type_count(layout) - 1),
	]
	var wanted: Array = [
		String(layout.get("verify_first_type_name", FIRST_TYPE_NAME)),
		MYSTERY_TYPE_NAME,
		String(layout.get("verify_last_type_name", LAST_TYPE_NAME)),
	]
	if read != wanted:
		return _fail("gTypeNames reads %s." % str(read))
	return _ok()


static func _verify_matchups(rom: RomFile, layout: Dictionary) -> Dictionary:
	if _read_matchups(rom, layout).is_empty():
		return _fail("gTypeEffectiveness has a row that is not a matchup, or no end.")
	return _ok()


## Empty when a row is not a matchup, which is a wrong offset.
static func _read_matchups(rom: RomFile, layout: Dictionary) -> Array:
	if bool(layout.get("type_effectiveness_matrix", false)):
		return _read_matchups_matrix(rom, layout)
	var out: Array = []
	var after_foresight: bool = false
	var at: int = int(layout["type_effectiveness"])
	while rom.in_bounds(at, Gen3Layout.MATCHUP_SIZE):
		var attacker: int = rom.u8(at)
		var defender: int = rom.u8(at + 1)
		var multiplier: int = rom.u8(at + 2)
		at += Gen3Layout.MATCHUP_SIZE
		if attacker == Gen3Layout.MATCHUP_END:
			return out
		if attacker == Gen3Layout.MATCHUP_FORESIGHT:
			after_foresight = true
			continue
		if attacker >= Gen3Layout.type_count(layout) or defender >= Gen3Layout.type_count(layout) \
			or not Gen3Layout.MATCHUP_MULTIPLIERS.has(multiplier):
			return []
		out.append({
			"attacker": attacker,
			"defender": defender,
			"multiplier": multiplier,
			"negated_by_foresight": after_foresight,
		})
	return []


## pokeemerald-expansion keeps effectiveness as a dense type_count x type_count matrix of
## u32 fixed-point values (0x1000 neutral, 0x0800 half, 0x2000 double, 0 immune). The row
## format only lists non-neutral matchups, so neutral entries are dropped here. Foresight
## negates the Normal/Fighting immunity to Ghost, which the matrix cannot mark.
static func _read_matchups_matrix(rom: RomFile, layout: Dictionary) -> Array:
	var count: int = Gen3Layout.type_count(layout)
	var at: int = int(layout["type_effectiveness"])
	if not rom.in_bounds(at, count * count * 4):
		return []
	var names: Dictionary = {}
	for type: int in count:
		names[_type_name(rom, layout, type)] = type
	var ghost: int = int(names.get("GHOST", -1))
	var sight: Array[int] = [int(names.get("NORMAL", -1)), int(names.get("FIGHTING", -1))]
	var out: Array = []
	for attacker: int in count:
		for defender: int in count:
			var value: int = rom.u32le(at + (attacker * count + defender) * 4)
			if value == 0x1000:
				continue
			var multiplier: int = 0
			if value == 0x0800:
				multiplier = 5
			elif value == 0x2000:
				multiplier = 20
			elif value != 0:
				return []
			out.append({
				"attacker": attacker,
				"defender": defender,
				"multiplier": multiplier,
				"negated_by_foresight": value == 0 and defender == ghost and sight.has(attacker),
			})
	return out


static func _verify_learnsets(rom: RomFile, layout: Dictionary) -> Dictionary:
	var first: Array = _read_learnset(rom, layout, 1)
	var wanted_first: Dictionary = {
		"level": FIRST_LEARNSET_WORD >> Gen3Layout.LEARNSET_LEVEL_SHIFT,
		"move": FIRST_LEARNSET_WORD & Gen3Layout.LEARNSET_MOVE_MASK,
	}
	if first.is_empty() or first[0] != wanted_first:
		return _fail("gLevelUpLearnsets does not open Bulbasaur's list on Tackle.")
	for species: int in Gen3Layout.verify_species_list(rom, layout):
		if _read_learnset(rom, layout, species).is_empty():
			return _fail("Species %d's level-up list is empty or has no end." % species)
	return _ok()


static func _read_learnset(rom: RomFile, layout: Dictionary, species: int) -> Array:
	var at: int = Gen3Layout.learnset_offset(rom, layout, species)
	if at < 0:
		return []
	var out: Array = []
	if bool(layout.get("learnset_pairs", false)):
		for row: int in Gen3Layout.LEARNSET_MAX:
			var move: int = rom.u16le(at + row * 4)
			if move == Gen3Layout.LEARNSET_END:
				return out
			out.append({"level": rom.u16le(at + row * 4 + 2), "move": move})
		return []
	for row: int in Gen3Layout.LEARNSET_MAX:
		var word: int = rom.u16le(at + row * 2)
		if word == Gen3Layout.LEARNSET_END:
			return out
		out.append({
			"level": word >> Gen3Layout.LEARNSET_LEVEL_SHIFT,
			"move": word & Gen3Layout.LEARNSET_MOVE_MASK,
		})
	return []


static func _verify_evolutions(rom: RomFile, layout: Dictionary) -> Dictionary:
	var first: Array = _read_evolutions(rom, layout, 1)
	var wanted: Array = layout.get("verify_first_evolution", FIRST_EVOLUTION)
	if first.is_empty() \
		or [first[0].get("method"), first[0].get("parameter"), first[0].get("target")] != wanted:
		return _fail("Bulbasaur's evolution reads %s." % str(first))
	for species: int in Gen3Layout.verify_species_list(rom, layout):
		for entry: Dictionary in _read_evolutions(rom, layout, species):
			if int(entry["method"]) > Gen3Layout.evolution_method_last(layout):
				return _fail("Species %d's evolution has method %d." % [species, int(entry["method"])])
	return _ok()


## Null when the pointer at [param at] leaves the cartridge or its string has no end.
static func _pointed_text(rom: RomFile, at: int) -> Variant:
	var offset: int = Gen3Layout.rom_offset(rom.u32le(at))
	var length: int = Gen3Text.span(rom.id, rom.bytes(), offset, Gen3Layout.TEXT_LIMIT)
	if length < 0:
		return null
	return Gen3Text.decode_fixed(rom.id, rom.bytes(), offset, length)


static func _item_name(rom: RomFile, layout: Dictionary, item: int) -> String:
	if layout.has("item_name_field"):
		var text: Variant = _pointed_text(rom, Gen3Layout.item_offset(layout, item) + int(layout["item_name_field"]))
		return String(text) if text != null else ""
	return Gen3Text.decode_fixed(
		rom.id, rom.bytes(), Gen3Layout.item_offset(layout, item), Gen3Layout.ITEM_NAME_SIZE
	)


## Each row's `itemId` is its index or `ITEM_NONE`, which no other stride gives.
static func _verify_items(rom: RomFile, layout: Dictionary) -> Dictionary:
	var first: Array = [_item_name(rom, layout, 0), _item_name(rom, layout, 1)]
	var first_item_wanted: String = String(layout.get("verify_first_item_name", FIRST_ITEM_NAME))
	if first != [UNUSED_ITEM_NAME, first_item_wanted]:
		return _fail("gItems opens on %s." % str(first))
	var id_field: int = int(layout.get("item_id_field", Gen3Layout.ITEM_ID))
	var desc_field: int = int(layout.get("item_description_field", Gen3Layout.ITEM_DESCRIPTION))
	for item: int in int(layout["item_count"]):
		var at: int = Gen3Layout.item_offset(layout, item)
		if id_field >= 0:
			var id: int = rom.u16le(at + id_field)
			if id != 0 and id != item:
				return _fail("Item %d's row names item %d." % [item, id])
		if _pointed_text(rom, at + desc_field) == null:
			return _fail("Item %d's description has no end." % item)
	return _ok()


static func _ability_name(rom: RomFile, layout: Dictionary, ability: int) -> String:
	return Gen3Text.decode_fixed(
		rom.id, rom.bytes(), Gen3Layout.ability_name_offset(layout, ability), Gen3Layout.ability_name_size(layout)
	)


static func _verify_abilities(rom: RomFile, layout: Dictionary) -> Dictionary:
	var read: Array = [
		_ability_name(rom, layout, 1), _ability_name(rom, layout, Gen3Layout.ability_count(layout) - 1),
	]
	var last_name: String = String(layout.get("verify_last_ability_name", LAST_ABILITY_NAME))
	if read != [FIRST_ABILITY_NAME, last_name]:
		return _fail("gAbilityNames reads %s." % str(read))
	for ability: int in Gen3Layout.ability_count(layout):
		if _pointed_text(rom, Gen3Layout.ability_description_pointer(layout, ability)) == null:
			return _fail("Ability %d's description has no end." % ability)
	return _ok()


static func _verify_dex_entries(rom: RomFile, layout: Dictionary) -> Dictionary:
	var wanted: Dictionary = layout.get("verify_dex_endpoints", DEX_ENDPOINTS)
	var by_national: Dictionary = Gen3Layout.species_by_national(rom, layout)
	for number: int in wanted:
		var entry: Dictionary = _read_dex_entry(rom, layout, number, by_national)
		var read: Array = [entry.get("category"), entry.get("height"), entry.get("weight")]
		if read != wanted[number]:
			return _fail("Dex entry %d reads %s." % [number, str(read)])
	for number: int in range(1, Gen3Layout.national_dex_count(layout) + 1):
		if _read_dex_entry(rom, layout, number, by_national).is_empty():
			return _fail("Dex entry %d has a page with no end." % number)
	return _ok()


static func _read_dex_entry(rom: RomFile, layout: Dictionary, number: int, by_national: Dictionary = {}) -> Dictionary:
	if bool(layout.get("dex_entry_from_species", false)):
		if by_national.is_empty():
			by_national = Gen3Layout.species_by_national(rom, layout)
		if not by_national.has(number):
			return {}
		var species: int = int(by_national[number])
		var at: int = Gen3Layout.species_info_offset(layout, species)
		var desc: Variant = _pointed_text(rom, at + int(layout["species_dex_description_field"]))
		if desc == null:
			return {}
		var scales: Array = layout["species_dex_scale_fields"]
		return {
			"category": Gen3Text.decode_fixed(
				rom.id, rom.bytes(), at + int(layout["species_dex_category_field"]),
				int(layout["species_dex_category_size"])
			),
			"height": rom.u16le(at + int(layout["species_dex_height_field"])),
			"weight": rom.u16le(at + int(layout["species_dex_weight_field"])),
			"pages": [desc],
			"pokemon_scale": rom.u16le(at + int(scales[0])),
			"pokemon_offset": rom.s16le(at + int(scales[1])),
			"trainer_scale": rom.u16le(at + int(scales[2])),
			"trainer_offset": rom.s16le(at + int(scales[3])),
		}
	var entry_at: int = Gen3Layout.dex_entry_offset(layout, number)
	var pages: Array = []
	for page: int in int(layout["dex_pages"]):
		var text: Variant = _pointed_text(
			rom, entry_at + Gen3Layout.DEX_ENTRY_DESCRIPTION + page * Gen3Layout.POINTER_SIZE
		)
		if text == null:
			return {}
		pages.append(text)
	var scales_at: int = entry_at + int(layout["dex_entry_size"]) - Gen3Layout.DEX_ENTRY_SCALES_FROM_END
	return {
		"category": Gen3Text.decode_fixed(rom.id, rom.bytes(), entry_at, Gen3Layout.DEX_ENTRY_CATEGORY_SIZE),
		"height": rom.u16le(entry_at + Gen3Layout.DEX_ENTRY_HEIGHT),
		"weight": rom.u16le(entry_at + Gen3Layout.DEX_ENTRY_WEIGHT),
		"pages": pages,
		"pokemon_scale": rom.u16le(scales_at),
		"pokemon_offset": rom.s16le(scales_at + 2),
		"trainer_scale": rom.u16le(scales_at + 4),
		"trainer_offset": rom.s16le(scales_at + 6),
	}


static func import_rom(rom: RomFile, on_progress: Callable = Callable()) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var directory: String = RomCache.directory_for(rom.id, rom.sha1)
	var result: Dictionary = {"ok": false, "message": "", "directory": directory}
	var layout: Dictionary = Gen3Layout.for_id(rom.id)
	var check: Dictionary = verify_layout(rom)
	if not bool(check["ok"]):
		result["message"] = String(check["message"])
		return result
	RomCache.clear(directory)
	if not RomCache.prepare(directory):
		result["message"] = "Could not create %s." % directory
		return result

	var species: Array = _import_species(rom, layout, on_progress)
	var pics: Dictionary = Gen3Pics.import_pics(rom, layout, directory, species, on_progress)
	if pics.is_empty():
		result["message"] = "Could not write picture atlases."
		return result
	var trainers: Array = Gen3Trainers.read(rom, layout)
	var trainer_pics: Dictionary = Gen3Trainers.import_pics(rom, layout, directory)
	if trainer_pics.is_empty():
		result["message"] = "Could not write trainer atlas."
		return result
	pics["trainers"] = trainer_pics
	var moves: Array = _import_moves(rom, layout, on_progress)
	var types: Array = _import_types(rom, layout)
	var matchups: Array = _read_matchups(rom, layout)
	var items: Array = _import_items(rom, layout)
	var abilities: Array = _import_abilities(rom, layout)
	var world: Dictionary = Gen3World.read(rom, layout)
	var tmhm_moves: Array = []
	var tmhm_count: int = int(layout.get("tmhm_count", TMHM_COUNT))
	var tmhm_stride: int = int(layout.get("tmhm_stride", 2))
	var tmhm_move_field: int = int(layout.get("tmhm_move_field", 0))
	for index: int in tmhm_count:
		tmhm_moves.append(rom.u16le(int(layout["tmhm_moves"]) + index * tmhm_stride + tmhm_move_field))
	var sections: Dictionary = {
		RomCache.tmhm_moves_path(directory): tmhm_moves,
		RomCache.species_path(directory): species,
		RomCache.moves_path(directory): moves,
		RomCache.types_path(directory): types,
		RomCache.matchups_path(directory): matchups,
		RomCache.items_path(directory): items,
		RomCache.abilities_path(directory): abilities,
		RomCache.trainers_path(directory): trainers,
		RomCache.world_maps_path(directory): world["headers"],
		RomCache.world_encounters_path(directory): world["encounters"],
	}
	for path: String in sections:
		if not RomCache.write_json(path, sections[path]):
			result["message"] = "Could not write %s." % path.get_file()
			return result
	var graphics_path: String = RomCache.world_tilesets_path(directory)
	if not RomCache.write_section(graphics_path, RomCache.blob_path(graphics_path), world["graphics"]):
		result["message"] = "Could not write map graphics."
		return result
	var scripts_path: String = RomCache.world_scripts_path(directory)
	if not RomCache.write_section(scripts_path, RomCache.blob_path(scripts_path), world["scripts"]):
		result["message"] = "Could not write script bytecode."
		return result
	var manifest: Dictionary = {
		"format_version": RomCache.FORMAT_VERSION,
		"game_id": String(rom.id),
		"sha1": rom.sha1,
		"generation": RomRegistry.GEN3,
		"species_count": species.size(),
		"move_count": moves.size(),
		"type_count": types.size(),
		"matchup_count": matchups.size(),
		"item_count": items.size(),
		"ability_count": abilities.size(),
		"trainer_count": trainers.size(),
		"map_count": world["headers"].size(),
		"script_instruction_count": world["scripts"]["instructions"].size(),
		"script_text_count": world["scripts"]["texts"].size(),
		"trainer_palettes": Gen3Trainers.palettes(rom, layout),
		"atlases": pics,
		"complete": true,
	}
	if not RomCache.write_json(RomCache.manifest_path(directory), manifest):
		result["message"] = "Could not write manifest."
		return result

	var evolutions: int = _count_of(species, "evolutions")
	var learnset_moves: int = _count_of(species, "learnset")
	result.merge({
		"ok": true,
		"species": species.size(),
		"moves": moves.size(),
		"types": types.size(),
		"matchups": matchups.size(),
		"items": items.size(),
		"abilities": abilities.size(),
		"trainers": trainers.size(),
		"maps": world["headers"].size(),
		"script_instructions": world["scripts"]["instructions"].size(),
		"script_texts": world["scripts"]["texts"].size(),
		"evolutions": evolutions,
		"learnset_moves": learnset_moves,
		"elapsed_ms": Time.get_ticks_msec() - started,
	}, true)
	result["message"] = ("%d species, %d moves, %d type matchups, %d items, %d abilities, "
		+ "%d trainers, %d map headers, %d script instructions, %d script texts, %d evolutions "
		+ "and %d level-up moves in %d ms.") % [
		species.size(), moves.size(), matchups.size(), items.size(), abilities.size(),
		trainers.size(), world["headers"].size(), world["scripts"]["instructions"].size(),
		world["scripts"]["texts"].size(),
		evolutions, learnset_moves, int(result["elapsed_ms"]),
	]
	return result


static func _count_of(species: Array, key: String) -> int:
	var total: int = 0
	for entry: Dictionary in species:
		total += (entry[key] as Array).size()
	return total


## By national dex number; `index` is the internal species.
static func _import_species(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var by_national: Dictionary = Gen3Layout.species_by_national(rom, layout)
	var out: Array = []
	for number: int in range(1, Gen3Layout.national_dex_count(layout) + 1):
		var species: int = int(by_national[number])
		var record: Dictionary = _species_info(rom, layout, Gen3Layout.species_info_offset(layout, species))
		record.merge({
			"number": number,
			"index": species,
			"hoenn_number": Gen3Layout.hoenn_number(rom, layout, species),
			"name": _species_name(rom, layout, species),
			"learnset": _read_learnset(rom, layout, species),
			"evolutions": _read_evolutions(rom, layout, species),
			"dex": _read_dex_entry(rom, layout, number, by_national),
			"palette": Gen3Pics.palette(rom, layout, species),
			"front_tiles": [Gen3Layout.PIC_TILES, Gen3Layout.PIC_TILES],
			"pic_coordinates": Gen3Pics.coordinates(rom, layout, species),
		})
		out.append(record)
		if on_progress.is_valid():
			on_progress.call("species", number, Gen3Layout.national_dex_count(layout))
	return out


## Abilities, items, egg groups and growth rate keep cartridge numbers; Generation 3 reorders Generation 2's growth rates.
## pokeemerald-expansion widens the struct: expYield/evYield are u16, abilities are three u16s,
## and the color byte moves to +80; the first eight bytes keep the vanilla layout.
static func _species_info(rom: RomFile, layout: Dictionary, at: int) -> Dictionary:
	if layout.has("species_natdex_field"):
		var ev_word: int = rom.u16le(at + 12)
		var ev_yield: Dictionary = {}
		for stat: int in Gen3Layout.EV_YIELD_STATS.size():
			ev_yield[Gen3Layout.EV_YIELD_STATS[stat]] = (ev_word >> (stat * 2)) & 0x3
		var color: int = rom.u8(at + 80)
		return {
			"stats": {
				"hp": rom.u8(at + Gen3Layout.INFO_HP),
				"attack": rom.u8(at + Gen3Layout.INFO_ATTACK),
				"defense": rom.u8(at + Gen3Layout.INFO_DEFENSE),
				"speed": rom.u8(at + Gen3Layout.INFO_SPEED),
				"sp_attack": rom.u8(at + Gen3Layout.INFO_SP_ATTACK),
				"sp_defense": rom.u8(at + Gen3Layout.INFO_SP_DEFENSE),
			},
			"types": [rom.u8(at + Gen3Layout.INFO_TYPES), rom.u8(at + Gen3Layout.INFO_TYPES + 1)],
			"catch_rate": rom.u8(at + Gen3Layout.INFO_CATCH_RATE),
			"base_exp": rom.u16le(at + 10),
			"ev_yield": ev_yield,
			"items": [rom.u16le(at + 14), rom.u16le(at + 16)],
			"gender_ratio": rom.u8(at + 18),
			"egg_cycles": rom.u8(at + 19),
			"friendship": rom.u8(at + 20),
			"growth_rate": rom.u8(at + 21),
			"egg_groups": [rom.u8(at + 22), rom.u8(at + 23)],
			"abilities": [rom.u16le(at + 24), rom.u16le(at + 26), rom.u16le(at + 28)],
			"safari_flee_rate": rom.u8(at + 30),
			"body_color": color & ~Gen3Layout.NO_FLIP_BIT,
			"no_flip": (color & Gen3Layout.NO_FLIP_BIT) != 0,
		}
	var ev_word: int = rom.u16le(at + Gen3Layout.INFO_EV_YIELD)
	var ev_yield: Dictionary = {}
	for stat: int in Gen3Layout.EV_YIELD_STATS.size():
		ev_yield[Gen3Layout.EV_YIELD_STATS[stat]] = (ev_word >> (stat * 2)) & 0x3
	var color: int = rom.u8(at + Gen3Layout.INFO_COLOR)
	return {
		"stats": {
			"hp": rom.u8(at + Gen3Layout.INFO_HP),
			"attack": rom.u8(at + Gen3Layout.INFO_ATTACK),
			"defense": rom.u8(at + Gen3Layout.INFO_DEFENSE),
			"speed": rom.u8(at + Gen3Layout.INFO_SPEED),
			"sp_attack": rom.u8(at + Gen3Layout.INFO_SP_ATTACK),
			"sp_defense": rom.u8(at + Gen3Layout.INFO_SP_DEFENSE),
		},
		"types": [rom.u8(at + Gen3Layout.INFO_TYPES), rom.u8(at + Gen3Layout.INFO_TYPES + 1)],
		"catch_rate": rom.u8(at + Gen3Layout.INFO_CATCH_RATE),
		"base_exp": rom.u8(at + Gen3Layout.INFO_EXP_YIELD),
		"ev_yield": ev_yield,
		"items": [rom.u16le(at + Gen3Layout.INFO_ITEMS), rom.u16le(at + Gen3Layout.INFO_ITEMS + 2)],
		"gender_ratio": rom.u8(at + Gen3Layout.INFO_GENDER_RATIO),
		"egg_cycles": rom.u8(at + Gen3Layout.INFO_EGG_CYCLES),
		"friendship": rom.u8(at + Gen3Layout.INFO_FRIENDSHIP),
		"growth_rate": rom.u8(at + Gen3Layout.INFO_GROWTH_RATE),
		"egg_groups": [
			rom.u8(at + Gen3Layout.INFO_EGG_GROUPS), rom.u8(at + Gen3Layout.INFO_EGG_GROUPS + 1),
		],
		"abilities": [
			rom.u8(at + Gen3Layout.INFO_ABILITIES), rom.u8(at + Gen3Layout.INFO_ABILITIES + 1),
		],
		"safari_flee_rate": rom.u8(at + Gen3Layout.INFO_SAFARI_FLEE_RATE),
		"body_color": color & ~Gen3Layout.NO_FLIP_BIT,
		"no_flip": (color & Gen3Layout.NO_FLIP_BIT) != 0,
	}


static func _read_evolutions(rom: RomFile, layout: Dictionary, species: int) -> Array:
	var out: Array = []
	var at: int = Gen3Layout.evolution_table_offset(rom, layout, species)
	if at < 0:
		return out
	var size: int = Gen3Layout.evolution_size(layout)
	if layout.has("evolution_end"):
		var end: int = int(layout["evolution_end"])
		for slot: int in 64:
			var method: int = rom.u16le(at + slot * size)
			if method == end:
				return out
			out.append({
				"method": method,
				"parameter": rom.u16le(at + slot * size + Gen3Layout.EVOLUTION_PARAMETER),
				"target": Gen3Layout.national_number(
					rom, layout, rom.u16le(at + slot * size + Gen3Layout.EVOLUTION_TARGET)
				),
			})
		return []
	for slot: int in Gen3Layout.EVOS_PER_MON:
		var sat: int = at + slot * size
		var method: int = rom.u16le(sat)
		if method == 0:
			continue
		out.append({
			"method": method,
			"parameter": rom.u16le(sat + Gen3Layout.EVOLUTION_PARAMETER),
			"target": Gen3Layout.national_number(
				rom, layout, rom.u16le(sat + Gen3Layout.EVOLUTION_TARGET)
			),
		})
	return out


static func _import_moves(rom: RomFile, layout: Dictionary, on_progress: Callable) -> Array:
	var out: Array = []
	for move: int in range(1, Gen3Layout.moves_count(layout)):
		var record: Dictionary = _move_record(rom, layout, move)
		record["number"] = move
		record["name"] = _move_name(rom, layout, move)
		out.append(record)
		if on_progress.is_valid():
			on_progress.call("moves", move, Gen3Layout.moves_count(layout) - 1)
	return out


static func _import_types(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for type: int in Gen3Layout.type_count(layout):
		out.append({
			"number": type,
			"name": _type_name(rom, layout, type),
			"special": Gen3Layout.is_special_type(type, layout),
		})
	return out


## Cartridge numbers, like [method _species_info]'s; pockets differ between games.
## pokeemerald-expansion's ItemInfo keeps the price as u32, the name/description as
## pointers, and importance/not-consumed/pocket as one bitfield byte at +30.
static func _item_record(rom: RomFile, layout: Dictionary, item: int) -> Dictionary:
	var at: int = Gen3Layout.item_offset(layout, item)
	if layout.has("item_name_field"):
		var bits: int = rom.u8(at + 30)
		return {
			"unused": false,
			"price": rom.u32le(at),
			"hold_effect": rom.u8(at + 28),
			"hold_effect_parameter": rom.u8(at + 29),
			"description": _pointed_text(rom, at + int(layout["item_description_field"])),
			"importance": bits & 3,
			"registrability": 0,  # no registrability field in ItemInfo
			"pocket": (bits >> 3) & 31,
			"type": rom.u8(at + 32),
			"battle_usage": rom.u8(at + 33),
			"secondary_id": rom.u16le(at + 4),
		}
	return {
		"unused": rom.u16le(at + Gen3Layout.ITEM_ID) == 0,
		"price": rom.u16le(at + Gen3Layout.ITEM_PRICE),
		"hold_effect": rom.u8(at + Gen3Layout.ITEM_HOLD_EFFECT),
		"hold_effect_parameter": rom.u8(at + Gen3Layout.ITEM_HOLD_EFFECT_PARAM),
		"description": _pointed_text(rom, at + Gen3Layout.ITEM_DESCRIPTION),
		"importance": rom.u8(at + Gen3Layout.ITEM_IMPORTANCE),
		"registrability": rom.u8(at + Gen3Layout.ITEM_REGISTRABILITY),
		"pocket": rom.u8(at + Gen3Layout.ITEM_POCKET),
		"type": rom.u8(at + Gen3Layout.ITEM_TYPE),
		"battle_usage": rom.u8(at + Gen3Layout.ITEM_BATTLE_USAGE),
		"secondary_id": rom.u8(at + Gen3Layout.ITEM_SECONDARY_ID),
	}


static func _import_items(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for item: int in range(1, int(layout["item_count"])):
		var record: Dictionary = _item_record(rom, layout, item)
		record["number"] = item
		record["name"] = _item_name(rom, layout, item)
		out.append(record)
	return out


static func _import_abilities(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for ability: int in Gen3Layout.ability_count(layout):
		out.append({
			"number": ability,
			"name": _ability_name(rom, layout, ability),
			"description": _pointed_text(
				rom, Gen3Layout.ability_description_pointer(layout, ability)
			),
		})
	return out
