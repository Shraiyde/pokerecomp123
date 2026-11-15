class_name Gen3Script
extends RefCounted

## scrcmd.c and script_cmd_table.inc, no-op handlers' consumed operands too; digits are `ScriptRead*` widths.
const FORMAT_COUNTS: Dictionary = {
	RomRegistry.RUBY: [198, 9], RomRegistry.SAPPHIRE: [198, 9],
	RomRegistry.FIRERED: [213, 10], RomRegistry.LEAFGREEN: [213, 10],
	RomRegistry.EMERALD: [227, 13],
	RomRegistry.HEARTSOUL: [247, 13], # expansion adds 20 commands (0xE3-0xF6)
}
const COMMANDS: Array[String] = [
	"nop:",
	"nop1:",
	"end:",
	"return:",
	"call:4",
	"goto:4",
	"goto_if:14",
	"call_if:14",
	"gotostd:1",
	"callstd:1",
	"gotostd_if:11",
	"callstd_if:11",
	"returnram:",
	"endram:",
	"setmysteryeventstatus:1",
	"loadword:14",
	"loadbyte:11",
	"setptr:14",
	"loadbytefromptr:14",
	"setptrbyte:14",
	"copylocal:11",
	"copybyte:44",
	"setvar:22",
	"addvar:22",
	"subvar:22",
	"copyvar:22",
	"setorcopyvar:22",
	"compare_local_to_local:11",
	"compare_local_to_value:11",
	"compare_local_to_ptr:14",
	"compare_ptr_to_local:41",
	"compare_ptr_to_value:41",
	"compare_ptr_to_ptr:44",
	"compare_var_to_value:22",
	"compare_var_to_var:22",
	"callnative:4",
	"gotonative:4",
	"special:2",
	"specialvar:22",
	"waitstate:",
	"delay:2",
	"setflag:2",
	"clearflag:2",
	"checkflag:2",
	"initclock:22",
	"dotimebasedevents:",
	"gettime:",
	"playse:2",
	"waitse:",
	"playfanfare:2",
	"waitfanfare:",
	"playbgm:21",
	"savebgm:2",
	"fadedefaultbgm:",
	"fadenewbgm:2",
	"fadeoutbgm:1",
	"fadeinbgm:1",
	"warp:11122",
	"warpsilent:11122",
	"warpdoor:11122",
	"warphole:11",
	"warpteleport:11122",
	"setwarp:11122",
	"setdynamicwarp:11122",
	"setdivewarp:11122",
	"setholewarp:11122",
	"getplayerxy:22",
	"getpartysize:",
	"additem:22",
	"removeitem:22",
	"checkitemspace:22",
	"checkitem:22",
	"checkitemtype:2",
	"addpcitem:22",
	"checkpcitem:22",
	"adddecoration:2",
	"removedecoration:2",
	"checkdecor:2",
	"checkdecorspace:2",
	"applymovement:24",
	"applymovementat:2411",
	"waitmovement:2",
	"waitmovementat:211",
	"removeobject:2",
	"removeobjectat:211",
	"addobject:2",
	"addobjectat:211",
	"setobjectxy:222",
	"showobjectat:211",
	"hideobjectat:211",
	"faceplayer:",
	"turnobject:21",
	"trainerbattle:",
	"dotrainerbattle:",
	"gotopostbattlescript:",
	"gotobeatenscript:",
	"checktrainerflag:2",
	"settrainerflag:2",
	"cleartrainerflag:2",
	"setobjectxyperm:222",
	"copyobjectxytoperm:2",
	"setobjectmovementtype:21",
	"waitmessage:",
	"message:4",
	"closemessage:",
	"lockall:",
	"lock:",
	"releaseall:",
	"release:",
	"waitbuttonpress:",
	"yesnobox:11",
	"multichoice:1111",
	"multichoicedefault:11111",
	"multichoicegrid:11111",
	"drawbox:",
	"erasebox:1111",
	"drawboxtext:1111",
	"showmonpic:211",
	"hidemonpic:",
	"showcontestpainting:1",
	"braillemessage:4",
	"givemon:212441",
	"giveegg:2",
	"setmonmove:112",
	"checkpartymove:2",
	"bufferspeciesname:12",
	"bufferleadmonspeciesname:1",
	"bufferpartymonnick:12",
	"bufferitemname:12",
	"bufferdecorationname:12",
	"buffermovename:12",
	"buffernumberstring:12",
	"bufferstdstring:12",
	"bufferstring:14",
	"pokemart:4",
	"pokemartdecoration:4",
	"pokemartdecoration2:4",
	"playslotmachine:2",
	"setberrytree:111",
	"choosecontestmon:",
	"startcontest:",
	"showcontestresults:",
	"contestlinktransfer:",
	"random:2",
	"addmoney:41",
	"removemoney:41",
	"checkmoney:41",
	"showmoneybox:111",
	"hidemoneybox:",
	"updatemoneybox:111",
	"getpokenewsactive:2",
	"fadescreen:1",
	"fadescreenspeed:11",
	"setflashlevel:2",
	"animateflash:1",
	"messageautoscroll:4",
	"dofieldeffect:2",
	"setfieldeffectargument:12",
	"waitfieldeffect:2",
	"setrespawn:2",
	"checkplayergender:",
	"playmoncry:22",
	"setmetatile:2222",
	"resetweather:",
	"setweather:2",
	"doweather:",
	"setstepcallback:1",
	"setmaplayoutindex:2",
	"setobjectsubpriority:2111",
	"resetobjectsubpriority:211",
	"createvobject:112211",
	"turnvobject:11",
	"opendoor:22",
	"closedoor:22",
	"waitdooranim:",
	"setdooropen:22",
	"setdoorclosed:22",
	"addelevmenuitem:1222",
	"showelevmenu:",
	"checkcoins:2",
	"addcoins:2",
	"removecoins:2",
	"setwildbattle:212",
	"dowildbattle:",
	"setvaddress:4",
	"vgoto:4",
	"vcall:4",
	"vgoto_if:14",
	"vcall_if:14",
	"vmessage:4",
	"vbuffermessage:4",
	"vbufferstring:14",
	"showcoinsbox:11",
	"hidecoinsbox:11",
	"updatecoinsbox:11",
	"incrementgamestat:1",
	"setescapewarp:11122",
	"waitmoncry:",
	"bufferboxname:12",
	"nop1:",
	"nop1:",
	"nop1:",
	"nop1:",
	"nop1:",
	"nop1:",
	"setmodernfatefulencounter:2",
	"checkmodernfatefulencounter:2",
	"trywondercardscript:",
	"nop1:",
	"warpspinenter:11122",
	"setmonmetlocation:21",
	"moverotatingtileobjects:2",
	"turnrotatingtileobjects:",
	"initrotatingtilepuzzle:2",
	"freerotatingtilepuzzle:",
	"warpmossdeepgym:11122",
	"selectapproachingtrainer:",
	"lockfortrainer:",
	"closebraillemessage:",
	"messageinstant:4",
	"fadescreenswapbuffers:1",
	"buffertrainerclassname:12",
	"buffertrainername:12",
	"pokenavcall:4",
	"warpwhitefade:11122",
	"buffercontestname:12",
	"bufferitemnameplural:122",
]

const RS_COMMANDS: Dictionary = {
	0x0C: "gotoram:",
	0x0D: "killscript:",
	0x11: "writebytetoaddr:14",
	0x12: "loadbytefromaddr:14",
	0x1D: "compare_local_to_addr:14",
	0x1E: "compare_addr_to_local:41",
	0x1F: "compare_addr_to_value:41",
	0x20: "compare_addr_to_addr:44",
	0x50: "applymovement_at:2411",
	0x52: "waitmovement_at:211",
	0x54: "removeobject_at:211",
	0x56: "addobject_at:211",
	0x5D: "trainerbattlebegin:",
	0x64: "moveobjectoffscreen:2",
	0x72: "drawbox:1111",
	0x77: "showcontestwinner:1",
	0x94: "hidemoneybox:11",
	0x96: "getpricereduction:2",
	0x99: "setflashradius:2",
	0xA8: "setobjectpriority:2111",
	0xA9: "resetobjectpriority:211",
	0xBE: "vloadptr:4",
}

const FRLG_COMMANDS: Dictionary = {
	0x2C: "initclock:",
	0x74: "drawboxtext:",
	0x8A: "setberrytree:",
	0x96: "getpokenewsactive:",
	0xB1: "addelevmenuitem:",
	0xC7: "textcolor:1",
	0xC8: "loadhelp:4",
	0xC9: "unloadhelp:",
	0xCA: "signmsg:",
	0xCB: "normalmsg:",
	0xCC: "comparestat:14",
	0xCD: "setmonmodernfatefulencounter:2",
	0xCE: "checkmonmodernfatefulencounter:2",
	0xD0: "setworldmapflag:2",
	0xD3: "getbraillestringwidth:4",
	0xD4: "bufferitemnameplural:122",
}

## Heart & Soul's extra commands (0xE3-0xF6), formats from the ScrCmd_ handlers in src/scrcmd.c.
## dynmultichoice is variable-length (fixed header + argc + argc word pointers); instruction() reads the vararg.
## These vanilla opcodes also differ in H&S (operand widths read from src/scrcmd.c):
## createvobject takes graphicsId as a halfword (548 graphics, not 255);
## setwildbattle takes a second species/level/item for double wild battles;
## fadescreenswapbuffers takes a nowait byte.
const HNS_COMMANDS: Dictionary = {
	0xAA: "createvobject:212211",
	0xB6: "setwildbattle:212212",
	0xDC: "fadescreenswapbuffers:11",
	0xE3: "dynmultichoice:2211121",
	0xE4: "dynmultipush:42",
	0xE5: "hidefollower:2",
	0xE6: "getbraillestringwidth:4",
	0xE7: "applymovementnofollower:24",
	0xE8: "givenamedmon:2",
	0xE9: "removenamedmon:2",
	0xEA: "remove5mons:",
	0xEB: "baobacheckmon:2",
	0xEC: "givebp:2",
	0xED: "setwildbattleshiny:212",
	0xEE: "removegenericmon:2",
	0xEF: "giveoddegg:2",
	0xF0: "buffermoncategory:12",
	0xF1: "checknuzlocke:",
	0xF2: "checkrandomizer:",
	0xF3: "checkpartymonlevel:2",
	0xF4: "calculatemonstats:",
	0xF5: "deleteparty:",
	0xF6: "checkpartymove:2",
}

## `TrainerBattleLoadArgs` consumes texts and optional scripts; FRLG's mode 9 stores texts, not facility arguments.
const TRAINER_WIDTHS: Array[String] = [
	"12244", "122444", "122444", "1224", "122444", "12244",
	"1224444", "122444", "1224444", "12244", "12244", "12244", "12244",
]
## Heart & Soul always writes the full trainerbattle parameter block (flags byte,
## localIdA, trainerA, introA, defeatA, retA, localIdB, trainerB, introB, defeatB,
## retB, victory, cannot-battle, rival flags); 40 bytes after the opcode.
const HNS_TRAINER_WIDTHS: String = "11244412444441"
const CONTINUATION_MODES: Array[int] = [1, 2, 6, 8]
const TERMINATORS: Array[int] = [2, 3, 5, 12, 13, 0x5E, 0x5F, 0xB9]
## DoWarp's map load replaces the context; these scripts often have no end.
const WARPS: Array[int] = [0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0xD1, 0xD7, 0xE0]

## Operands naming data a handler reads, by index and table; `loadword 0` and trainerbattle words but a continuation are texts.
const DATA_OPERANDS: Dictionary = {
	"message": [0, "texts"], "messageautoscroll": [0, "texts"],
	"messageinstant": [0, "texts"], "pokenavcall": [0, "texts"],
	"loadhelp": [0, "texts"], "bufferstring": [1, "texts"],
	"braillemessage": [0, "braille"], "getbraillestringwidth": [0, "braille"],
	"applymovement": [1, "movements"], "applymovementat": [1, "movements"],
	"applymovement_at": [1, "movements"], "pokemart": [0, "marts"],
	"pokemartdecoration": [0, "decoration_marts"], "pokemartdecoration2": [0, "decoration_marts"],
}
const DATA_TABLES: Array[String] = ["texts", "braille", "movements", "marts", "decoration_marts"]
## A null operand reads ctx->data[0]; EWRAM and IWRAM pointers name run-time buffers.
const RAM_START: int = 0x02000000
const RAM_END: int = 0x04000000
## gMovementActionFuncs' rows; MOVEMENT_ACTION_STEP_END ends a list.
const MOVEMENT_ACTIONS: Dictionary = {
	RomRegistry.RUBY: 138, RomRegistry.SAPPHIRE: 138,
	RomRegistry.FIRERED: 170, RomRegistry.LEAFGREEN: 170, RomRegistry.EMERALD: 158,
	RomRegistry.HEARTSOUL: 182, # gMovementActionFuncs has 182 entries (max SPIN_RIGHT 0xB5)
}
const MOVEMENT_STEP_END: int = 0xFE
const HELP_TEXT_LIMIT: int = 96
const MENU_TEXT_LIMIT: int = 64
## brailleformat's window bytes precede the six-dot cells except on FireRed and LeafGreen.
const BRAILLE_FORMAT_SIZE: int = 6
const BRAILLE_CELLS: int = 0x40
## gDecorations runs from DECOR_NONE to DECOR_REGISTEEL_DOLL.
const DECORATION_COUNT: int = 121


static func instruction(rom: RomFile, at: int, layout: Dictionary = {}) -> Dictionary:
	if not rom.in_bounds(at, 1):
		return {}
	var opcode: int = rom.u8(at)
	var definition: PackedStringArray = _definition(rom.id, opcode)
	if definition.is_empty():
		return {}
	var widths: String = definition[1]
	if opcode == 0x5C:
		if not rom.in_bounds(at + 1, 1):
			return {}
		var mode_byte: int = rom.u8(at + 1)
		# Heart & Soul packs the trainerbattle mode in the high nibble of the
		# first byte (flags in the low nibble) and always writes the full
		# 40-byte parameter block; vanilla stores a plain mode byte with a
		# mode-dependent layout.
		if rom.id == RomRegistry.HEARTSOUL:
			var hns_mode: int = mode_byte >> 4
			if hns_mode >= int(FORMAT_COUNTS[rom.id][1]):
				return {}
			widths = HNS_TRAINER_WIDTHS
			var hns_end: int = at + 1
			var hns_operands: Array[int] = []
			for digit: String in widths:
				var w: int = int(digit)
				if not rom.in_bounds(hns_end, w):
					return {}
				hns_operands.append(_operand(rom, hns_end, w))
				hns_end += w
			hns_operands[0] = hns_mode
			return {"opcode": opcode, "command": definition[0], "operands": hns_operands,
				"next_offset": hns_end, "bytes": Array(rom.slice(at, hns_end - at))}
		var mode: int = mode_byte
		var limit: int = int(FORMAT_COUNTS[rom.id][1])
		if mode >= limit:
			return {}
		widths = TRAINER_WIDTHS[mode]
	var end: int = at + 1
	var operands: Array[int] = []
	for digit: String in widths:
		var width: int = int(digit)
		if not rom.in_bounds(end, width):
			return {}
		operands.append(_operand(rom, end, width))
		end += width
	# Heart & Soul dynmultichoice (0xE3) is variable-length: fixed header, an argc
	# byte, then argc word pointers to the item texts (stack form: argc 1, one NULL).
	if rom.id == RomRegistry.HEARTSOUL and opcode == 0xE3:
		if not rom.in_bounds(end, 1):
			return {}
		var argc: int = rom.u8(end)
		operands.append(argc)
		end += 1
		for item: int in argc:
			if not rom.in_bounds(end, 4):
				return {}
			operands.append(_operand(rom, end, 4))
			end += 4
	# Heart & Soul callnative macros (facilitytrainerbattle / dofacilitytrainerbattle)
	# append argument bytes after the function pointer; consume them so the next
	# instruction starts at the right offset. The operand is the native function
	# pointer, normalized: requests_effects=1 stores func + ROM_SIZE.
	if opcode == 0x23 and layout.has("native_call_args"):
		var func_ptr: int = int(operands[0])
		if func_ptr >= 0x08000000 + rom.size():
			func_ptr -= rom.size()
		var extra: int = int((layout["native_call_args"] as Dictionary).get(func_ptr, 0))
		for i: int in extra:
			if not rom.in_bounds(end, 1):
				return {}
			operands.append(rom.u8(end))
			end += 1
	return {"opcode": opcode, "command": definition[0], "operands": operands,
		"next_offset": end, "bytes": Array(rom.slice(at, end - at))}


static func _frlg(id: StringName) -> bool:
	return id in [RomRegistry.FIRERED, RomRegistry.LEAFGREEN]


static func _definition(id: StringName, opcode: int) -> PackedStringArray:
	if not FORMAT_COUNTS.has(id) or opcode >= int(FORMAT_COUNTS[id][0]):
		return PackedStringArray()
	var overrides: Dictionary = {}
	if _frlg(id):
		overrides = FRLG_COMMANDS
	elif id in [RomRegistry.RUBY, RomRegistry.SAPPHIRE]:
		overrides = RS_COMMANDS
	elif id == RomRegistry.HEARTSOUL:
		overrides = HNS_COMMANDS
	# Do not evaluate COMMANDS[opcode] as a .get() default: it is out of range for
	# Heart & Soul's extra opcodes (COMMANDS holds only the 227 vanilla entries).
	if overrides.has(opcode):
		return String(overrides[opcode]).split(":")
	return String(COMMANDS[opcode]).split(":")


static func _operand(rom: RomFile, at: int, width: int) -> int:
	match width:
		1: return rom.u8(at)
		2: return rom.u16le(at)
		4: return rom.u32le(at)
	return 0


static func read(rom: RomFile, layout: Dictionary, headers: Dictionary) -> Dictionary:
	var standard: Array[int] = _standard(rom, layout)
	var trainers: Array = layout.get("trainer_battle_scripts", [])
	if standard.is_empty() or trainers.size() != 5:
		return {}
	var native: Dictionary = layout.get("native_scripts", {})
	var pending: Array = standard.duplicate()
	pending.append_array(trainers)
	pending.append_array(native.values())
	_roots(headers, pending)
	var instructions: Dictionary = {}
	while not pending.is_empty():
		var at: int = int(pending.pop_back())
		var key: String = str(at)
		if instructions.has(key):
			continue
		var row: Dictionary = instruction(rom, at, layout)
		if row.is_empty() or not _flow(rom, row, standard, trainers):
			return {}
		instructions[key] = row
		pending.append_array(row["script_offsets"])
		if bool(row["fallthrough"]):
			pending.append(row["next_offset"])
	var data: Dictionary = _data(rom, layout, instructions)
	if data.is_empty() or not _valid_boundaries(instructions, data):
		return {}
	var out: Dictionary = {"instructions": instructions, "standard": standard, "trainer_battle": trainers,
		"native": native}
	out.merge(data)
	return out if _read_menu_text(rom, layout, out) else {}


static func _read_menu_text(rom: RomFile, layout: Dictionary, out: Dictionary) -> bool: # `gStdStrings` (FireRed's `gStdStringPtrs`) and `sMultichoiceLists`, whose `MenuAction` rows pair a text and a callback.
	if not layout.has("std_strings"):
		return true
	var strings: Array = []
	var table: Array = layout["std_strings"]
	for index: int in int(table[1]):
		if not _append_text(rom, int(table[0]) + index * 4, strings):
			return false
	var lists: Array = []
	table = layout["multichoice_lists"]
	for index: int in int(table[1]):
		var at: int = int(table[0]) + index * 8
		var rows: Array = []
		for row: int in rom.u8(at + 4):
			if not _append_text(rom, Gen3Layout.rom_offset(rom.u32le(at)) + row * 8, rows):
				return false
		lists.append(rows)
	out["std_strings"] = strings
	out["multichoice"] = lists
	var labels: Array = []
	table = layout["start_menu"]
	for index: int in int(table[1]):
		if not _append_text(rom, int(table[0]) + index * 8, labels):
			return false
	var help: Array = []
	for index: int in Gen3FieldStartMenu.HELP_ROWS if layout.has("start_menu_help") else 0:
		if not _append_text(rom, int(layout["start_menu_help"]) + index * 4, help, HELP_TEXT_LIMIT):
			return false
	out["start_menu"] = {"labels": labels, "help": help}
	return true


static func _append_text(rom: RomFile, at: int, rows: Array, limit: int = MENU_TEXT_LIMIT) -> bool: # FireRed and Emerald keep a few empty labels, so an empty string is a row, not a failure.
	if not rom.in_bounds(at, 4):
		return false
	var text: int = Gen3Layout.rom_offset(rom.u32le(at))
	if not rom.in_bounds(text, limit):
		return false
	var bytes: PackedByteArray = rom.slice(text, limit)
	if Gen3Text.EOS not in bytes:
		return false
	rows.append(Gen3Text.decode_fixed(rom.id, bytes, 0, bytes.size()))
	return true


## Instructions share no byte with each other or data; a movement label inside another list ends with it.
static func _valid_boundaries(instructions: Dictionary, data: Dictionary) -> bool:
	var runs: Array = []
	for key: String in instructions:
		runs.append([int(key), int(instructions[key]["next_offset"]), 1, ""])
	for table: String in DATA_TABLES:
		for key: String in data[table]:
			runs.append([int(key), int(key) + data_size(data[table][key]), 0, table])
	runs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var last: Array = [-1, -1, 0, ""]
	for run: Array in runs:
		if run[0] < last[1] and (run[1] != last[1] or run[2] == 1 or last[2] == 1):
			# Heart & Soul embeds movement scripts in script regions; a dead
			# fallthrough path can decode the same bytes as instructions.
			# Movement/data overlap is not a decode error there.
			if str(run[3]) == "movements" or str(last[3]) == "movements":
				last = run
				continue
			return false
		last = run
	return true


static func data_size(record: Dictionary) -> int:
	if record.has("entries"):
		return ((record["entries"] as Array).size() + 1) * 2
	return (record["bytes"] as Array).size() + (record.get("format", []) as Array).size()


static func _data(rom: RomFile, layout: Dictionary, instructions: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for table: String in DATA_TABLES:
		out[table] = {}
	for row: Dictionary in instructions.values():
		for pointer: Array in _data_pointers(row, rom.id):
			var value: int = int(pointer[1])
			if value == 0 or (value >= RAM_START and value < RAM_END):
				continue
			var at: int = Gen3Layout.rom_offset(value)
			var records: Dictionary = out[pointer[0]]
			if records.has(str(at)):
				continue
			var record: Dictionary = _data_record(rom, layout, pointer[0], at)
			if record.is_empty():
				return {}
			records[str(at)] = record
	return out


static func _data_pointers(row: Dictionary, id: StringName = &"") -> Array:
	var operands: Array = row["operands"]
	var command: String = row["command"]
	if command == "loadword":
		return [["texts", operands[1]]] if int(operands[0]) == 0 else []
	if command == "trainerbattle":
		# Heart & Soul writes the full parameter block; the text pointers are
		# introA, defeatA, introB, defeatB, victory, cannot-battle.
		if id == RomRegistry.HEARTSOUL:
			return [3, 4, 8, 9, 11, 12].map(func(i: int) -> Array: return ["texts", operands[i]])
		var words: Array = operands.slice(3)
		if int(operands[0]) in CONTINUATION_MODES:
			words.pop_back()
		return words.map(func(word: int) -> Array: return ["texts", word])
	if command == "dynmultichoice":
		# Operands 0-6 are the fixed header, 7 is argc, 8+ are the item text pointers.
		return operands.slice(8).map(func(word: int) -> Array: return ["texts", word])
	if not DATA_OPERANDS.has(command):
		return []
	var role: Array = DATA_OPERANDS[command]
	return [[role[1], operands[int(role[0])]]]


static func _data_record(rom: RomFile, layout: Dictionary, table: String, at: int) -> Dictionary:
	if not rom.in_bounds(at, 1):
		return {}
	match table:
		"texts":
			var length: int = Gen3Text.span(rom.id, rom.bytes(), at, Gen3Layout.TEXT_LIMIT)
			return {} if length < 0 else {"bytes": Array(rom.slice(at, length))}
		"braille":
			return _braille(rom, at)
		"movements":
			return _movement(rom, at)
		"marts":
			return _mart(rom, at, int(layout["item_count"]))
		"decoration_marts":
			return _mart(rom, at, DECORATION_COUNT)
	return {}


static func _braille(rom: RomFile, at: int) -> Dictionary:
	var header: int = 0 if _frlg(rom.id) else BRAILLE_FORMAT_SIZE
	var cells: int = at + header
	while rom.in_bounds(cells, 1) and cells - at < Gen3Layout.TEXT_LIMIT:
		var cell: int = rom.u8(cells)
		cells += 1
		if cell == Gen3Text.EOS:
			var out: Dictionary = {"bytes": Array(rom.slice(at + header, cells - at - header))}
			if header > 0:
				out["format"] = Array(rom.slice(at, header))
			return out
		if cell >= BRAILLE_CELLS and cell != Gen3Text.NEWLINE:
			return {}
	return {}


static func _movement(rom: RomFile, at: int) -> Dictionary:
	var end: int = at
	while rom.in_bounds(end, 1) and rom.u8(end) != MOVEMENT_STEP_END:
		if rom.u8(end) >= int(MOVEMENT_ACTIONS[rom.id]):
			return {}
		end += 1
	return {"bytes": Array(rom.slice(at, end + 1 - at))} if rom.in_bounds(end, 1) else {}


## SetShopItemsForSale counts halfwords up to ITEM_NONE or DECOR_NONE.
static func _mart(rom: RomFile, at: int, count: int) -> Dictionary:
	var entries: Array[int] = []
	var row: int = at
	while at % 2 == 0 and rom.in_bounds(row, 2):
		var entry: int = rom.u16le(row)
		if entry == 0:
			return {"entries": entries}
		if entry >= count:
			return {}
		entries.append(entry)
		row += 2
	return {}


static func _standard(rom: RomFile, layout: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var at: int = int(layout.get("standard_scripts", -1))
	var count: int = int(layout.get("standard_script_count", 0))
	if count < 1 or not rom.in_bounds(at, count * 4):
		return out
	for slot: int in count:
		var offset: int = Gen3Layout.read_pointer(rom, at + slot * 4, 1, 1)
		if offset < 0:
			return []
		out.append(offset)
	return out


static func _roots(value: Variant, pending: Array) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if key == "script_offset" and int(value[key]) != 0:
				pending.append(int(value[key]))
			else:
				_roots(value[key], pending)
	elif value is Array:
		for row: Variant in value:
			_roots(row, pending)


static func _flow(rom: RomFile, row: Dictionary, standard: Array[int], trainers: Array) -> bool:
	var opcode: int = int(row["opcode"])
	var operands: Array = row["operands"]
	var targets: Array[int] = []
	var fallthrough: bool = opcode not in TERMINATORS and opcode not in WARPS
	if opcode in [4, 5, 6, 7]:
		var target: int = Gen3Layout.rom_offset(int(operands.back()))
		if not rom.in_bounds(target, 1):
			return false
		targets.append(target)
	if opcode in [8, 9, 10, 11]:
		if int(operands.back()) < standard.size():
			targets.append(standard[int(operands.back())])
			if opcode == 8:
				fallthrough = false
		elif rom.id == RomRegistry.HEARTSOUL:
			# Heart & Soul has gotostd/callstd with indices past its 13-entry
			# standard table; the engine treats those as no-ops, and the bytes
			# after them are not script code on any live path. Do not follow.
			fallthrough = false
	if opcode == 0x5C:
		targets = _trainer_targets(rom, row, trainers)
		if targets == [-1]:
			return false
		fallthrough = false
	if opcode == 0x23 and rom.id == RomRegistry.HEARTSOUL:
		# 0x0820CD59 reads a variable number of script bytes in branches, so
		# its fallthrough offset is not modelable; its scripts never continue
		# linearly past it (the bytes after are padding/data). Do not follow.
		var func_ptr: int = int(operands[0])
		if func_ptr >= 0x08000000 + rom.size():
			func_ptr -= rom.size()
		if func_ptr == 0x0820CD59:
			fallthrough = false
	row.merge({"script_offsets": targets, "fallthrough": fallthrough})
	return true


static func trainer_script_index(mode: int, frlg: bool) -> int: # A mode's `trainer_battle_scripts` entry: normal, double, no-intro, rematch, double rematch.
	if mode == 3 or (mode == 9 and frlg):
		return 2
	if mode in [4, 6, 8]:
		return 1
	if mode == 5:
		return 3
	return 4 if mode == 7 else 0


static func _trainer_targets(rom: RomFile, row: Dictionary, trainers: Array) -> Array[int]:
	var operands: Array = row["operands"]
	var mode: int = int(operands[0])
	if rom.id == RomRegistry.EMERALD and mode in [10, 11]:
		return []
	var helper: int = trainer_script_index(mode, _frlg(rom.id))
	var out: Array[int] = [int(trainers[helper]), int(row["next_offset"])]
	if mode in CONTINUATION_MODES:
		# Heart & Soul keeps the post-battle script at operand 5 (event_script_a);
		# vanilla stores it as the last operand.
		var cont_operand: int = int(operands[5]) if rom.id == RomRegistry.HEARTSOUL else int(operands.back())
		var continuation: int = Gen3Layout.rom_offset(cont_operand)
		if not rom.in_bounds(continuation, 1):
			return [-1]
		out.append(continuation)
	return out
