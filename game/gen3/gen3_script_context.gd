class_name Gen3ScriptContext
extends RefCounted

enum State { STOPPED, RUNNING, DELAY, WAITING, NATIVE_WAIT, FAULT }

const STACK_LIMIT: int = 19 # script.c::ScriptPush reserves stack[20]'s last slot.
const VAR_RESULT: int = 0x800D # `gSpecialVar_Result`, what givemon reports into.
const PARTY_SIZE: int = 6
const MON_GIVEN_TO_PARTY: int = 0 # pokemon.h's `MON_GIVEN_TO_PARTY`; to the PC is 1, impossible is 2.
const MON_CANT_GIVE: int = 2
const ROM_SIZE: int = 0x02000000 # H&S ROM size; `requests_effects=1` stores the pointer plus this (event.inc's callnative).
const WARP_COMMANDS: Array[String] = ["warp", "warpsilent", "warpdoor", "warphole", "warpteleport",
	"warpmossdeepgym", "warpspinenter", "warpwhitefade"]
const OBJECT_COMMANDS: Array[String] = ["removeobject", "removeobjectat", "removeobject_at",
	"addobject", "addobjectat", "addobject_at", "setobjectxy", "setobjectxyperm", "copyobjectxytoperm",
	"showobjectat", "hideobjectat", "setobjectmovementtype", "setmetatile", "getplayerxy"]
const HOST_COMMANDS: Array[String] = [
	"message", "messageautoscroll", "messageinstant", "pokenavcall",
	"waitmessage", "closemessage", "waitbuttonpress",
	"lock", "lockall", "lockfortrainer", "release", "releaseall", "faceplayer", "turnobject",
	"applymovement", "applymovementat", "applymovement_at",
	"waitmovement", "waitmovementat", "waitmovement_at",
	"setwarp", "setdynamicwarp", "setdivewarp", "setholewarp", "setescapewarp",
	"special", "specialvar", "selectapproachingtrainer", "trainerbattle", "gotopostbattlescript", "gotobeatenscript",
	"yesnobox", "multichoice", "multichoicedefault", "multichoicegrid",
	"braillemessage", "pokemart", "pokemartdecoration", "pokemartdecoration2",
	"dofieldeffect", "setfieldeffectargument", "dotrainerbattle", "trainerbattlebegin",
]
const PRESENTATION: Dictionary = { # Emitted as `{kind: command, operands}`; these operands go through `VarGet`.
	"playse": [], "playfanfare": [], "playbgm": [], "savebgm": [], "fadedefaultbgm": [], "fadenewbgm": [],
	"fadeinbgm": [], "playmoncry": [0, 1], "showmonpic": [0], "opendoor": [0, 1], "closedoor": [0, 1],
	"setdooropen": [0, 1], "setdoorclosed": [0, 1], "setweather": [0], "resetweather": [], "doweather": [],
	"setflashlevel": [0], "setstepcallback": [], "dotimebasedevents": [], "setmaplayoutindex": [0],
	"showmoneybox": [], "hidemoneybox": [], "updatemoneybox": [], "showcoinsbox": [], "hidecoinsbox": [],
	"updatecoinsbox": [], "drawbox": [], "erasebox": [], "drawboxtext": [], "closebraillemessage": [],
	"textcolor": [], "signmsg": [], "normalmsg": [], "unloadhelp": [],
}
const HOST_WAITS: Dictionary = { # Presentation that holds the script until `finish_wait`.
	"waitse": [], "waitfanfare": [], "waitmoncry": [], "fadescreen": [], "fadescreenspeed": [],
	"fadescreenswapbuffers": [], "waitdooranim": [], "fadeoutbgm": [], "hidemonpic": [], "waitfieldeffect": [0],
}
const STOPPING_COMMANDS: Array[String] = ["yesnobox", "multichoice", "multichoicedefault", "multichoicegrid", # `ScriptContext_Stop`.
	"pokemart", "pokemartdecoration", "pokemartdecoration2", "animateflash", "playslotmachine",
	"dotrainerbattle", "trainerbattlebegin"]
const NATIVE_COMMANDS: Array[String] = ["waitmessage", "waitbuttonpress", "lock", "lockall", "lockfortrainer",
	"waitmovement", "waitmovementat", "waitmovement_at"] # scrcmd.c::SetupNativeScript callers.
const CONDITIONS: Array = [[0], [1], [2], [0, 1], [1, 2], [0, 2]]

var state: int = State.STOPPED
var offset: int = -1
var comparison: int = 0
var pending_wild: Dictionary = {} # `setwildbattle`'s staged species/level, consumed by `dowildbattle`.
var locals: Array[int] = [0, 0, 0, 0]
var error: Dictionary = {}
var _data: GameData
var _events: Gen3EventData
var _stack: Array[int] = []
var _output: Array[Dictionary] = []


func _init(data: GameData, events: Gen3EventData) -> void:
	_data = data
	_events = events


func start(at: int) -> void:
	offset = at
	comparison = 0
	locals = [0, 0, 0, 0]
	_stack.clear()
	error = {}
	state = State.RUNNING


func start_map_script(group: int, number: int, type: int) -> bool:
	for row: Dictionary in _data.world_map_script_entries(group, number):
		if int(row.get("type", 0)) != type:
			continue
		if type in [2, 4]:
			for condition: Dictionary in row.get("conditions", []):
				var left: int = _events.var_get(int(condition["variable"]))
				var right: int = _events.var_get(int(condition["value"])) # script.c::MapHeaderCheckScriptTable resolves both.
				if left == right:
					start(int(condition["script_offset"]))
					return true
			return false
		start(int(row["script_offset"]))
		return true
	return false


func resume() -> void:
	if state == State.WAITING:
		state = State.RUNNING


func tick(budget: int = 10000, native_complete: bool = false, command_handler: Callable = Callable()) -> Array[Dictionary]:
	_output = []
	if state == State.NATIVE_WAIT:
		if native_complete:
			state = State.RUNNING
		return []
	if state == State.DELAY:
		_events.script_delay = (_events.script_delay - 1) & 0xFFFF
		if _events.script_delay == 0:
			state = State.RUNNING
		return [] # script.c::RunScriptCommand returns even on the tick a native wait completes.
	if state != State.RUNNING:
		return []
	for count: int in budget:
		if offset < 0:
			state = State.STOPPED
			return _output
		var at: int = offset
		var row: Dictionary = _data.world_script_instruction(at)
		if row.is_empty():
			return fail(at, "missing_instruction")
		offset = int(row["next_offset"])
		if not _execute(row, at, command_handler):
			return fail(at, "unsupported_command", row)
		if state == State.WAITING:
			if row["command"] == "waitstate":
				_output.append({"type": "waitstate", "offset": at})
			return _output
		if state != State.RUNNING or String(row["command"]) in WARP_COMMANDS:
			return _output
	return fail(offset, "instruction_budget")


func fail(at: int, reason: String, row: Dictionary = {}) -> Array[Dictionary]:
	state = State.FAULT
	error = {"type": "script_error", "offset": at, "reason": reason, "instruction": row.duplicate(true)}
	_output.append(error.duplicate(true))
	return _output


func _execute(row: Dictionary, at: int, command_handler: Callable) -> bool:
	var command: String = row["command"]
	var args: Array = row["operands"]
	if _host_owns(command):
		return _host_command(row, at, command_handler)
	if command in ["nop", "nop1"]:
		return true
	if command == "end":
		state = State.STOPPED
		return true
	if command == "return":
		offset = -1 if _stack.is_empty() else _stack.pop_back()
		return true
	if command in ["goto", "call", "goto_if", "call_if", "gotostd", "callstd", "gotostd_if", "callstd_if"]:
		return _branch(command, args)
	if command == "delay":
		_events.script_delay = int(args[0])
		state = State.DELAY
		return true
	if command == "waitstate":
		state = State.WAITING
		return true
	if command in ["setflag", "clearflag", "checkflag", "incrementgamestat", "random"]:
		return _event_command(command, args)
	if command == "callnative":
		return _callnative(args)
	if command in ["givemon", "giveegg", "giveoddegg", "givenamedmon", "setmonmove", "initclock", "gettime",
			"checkrandomizer", "checknuzlocke", "setwildbattle", "dowildbattle",
			"setwildbattleshiny", "setberrytree", "removenamedmon", "remove5mons",
			"removegenericmon", "deleteparty", "hidefollower", "givebp",
			"baobacheckmon", "checkpartymonlevel", "calculatemonstats",
			"getbraillestringwidth", "createvobject", "turnvobject",
			"adddecoration", "removedecoration", "checkdecor", "checkdecorspace",
			"addelevmenuitem", "showelevmenu", "choosecontestmon", "startcontest",
			"showcontestresults", "contestlinktransfer", "dynmultipush", "dynmultichoice"]:
		return _story_command(command, args)
	return _value_command(command, args)


static func _host_owns(command: String) -> bool:
	return command in HOST_COMMANDS or command in WARP_COMMANDS or command in OBJECT_COMMANDS \
		or command in PRESENTATION or command in HOST_WAITS or command in STOPPING_COMMANDS \
		or command in Gen3ScriptServices.COMMANDS


func _host_command(row: Dictionary, at: int, command_handler: Callable) -> bool:
	var command: String = row["command"]
	var operands: Array = row["operands"].duplicate()
	if command in ["message", "messageautoscroll", "messageinstant", "pokenavcall"] and int(operands[0]) == 0:
		operands[0] = locals[0] # scrcmd.c::ScrCmd_message and its printing variants accept NULL for data[0].
	var event: Dictionary = {"type": "script_command", "command": command,
		"operands": operands, "offset": at}
	_output.append(event)
	if command in NATIVE_COMMANDS or command in HOST_WAITS:
		state = State.NATIVE_WAIT
	elif command in STOPPING_COMMANDS:
		state = State.WAITING
	if command_handler.is_valid():
		command_handler.call(event)
	return true


func _branch(command: String, args: Array) -> bool:
	if command.ends_with("_if"):
		var condition: int = int(args[0])
		if condition < 0 or condition >= CONDITIONS.size():
			return false
		if comparison not in CONDITIONS[condition]:
			return true
	var target: int = int(args.back())
	if command.contains("std"):
		target = _data.world_standard_script_offset(target)
		if target < 0:
			return true
	else:
		target = Gen3Layout.rom_offset(target)
	if command.begins_with("call") and _stack.size() < STACK_LIMIT:
		_stack.append(offset)
	offset = target
	return true


func _event_command(command: String, args: Array) -> bool:
	var id: int = int(args[0])
	match command:
		"setflag": _events.flag_set(id)
		"clearflag": _events.flag_clear(id)
		"checkflag": comparison = int(_events.flag_get(id))
		"incrementgamestat": _events.increment_stat(id)
		"random":
			var limit: int = _events.var_get(id)
			if limit == 0:
				return false
			_events.var_set(0x800D, _events.random.next() % limit)
	return true


## Story commands the Johto scripts use that the value-command path cannot
## run: gift mons and eggs, the party move setter, and the clock. The
## randomizer/nuzlocke checks answer "off" while no challenge model is
## enabled, which is the ROM's answer with those settings disabled.
func _story_command(command: String, args: Array) -> bool:
	match command:
		"givemon", "giveegg", "giveoddegg", "givenamedmon":
			if args.is_empty():
				return false
			var species: int = _events.var_get(int(args[0]))
			if _events.randomizer_on("starter"):
				species = Gen3Randomizer.species_for(_events, species, _data.species_count())
			var level: int = 5 if command != "givemon" else _events.var_get(int(args[1])) if args.size() > 1 else 5
			if species <= 0 or _data.species(species).is_empty() or level < 1 or level > 100 \
					or _events.party.size() >= PARTY_SIZE:
				_events.var_set(VAR_RESULT, MON_CANT_GIVE)
				return true
			var mon: Dictionary = _gift_mon(species, level)
			mon["egg"] = command != "givemon" and command != "givenamedmon"
			if command == "givemon" and args.size() > 2:
				var held: int = _events.var_get(int(args[2]))
				if held > 0:
					mon["item"] = held
			_events.party.append(mon)
			_events.var_set(VAR_RESULT, MON_GIVEN_TO_PARTY)
		"setmonmove":
			if args.size() < 3:
				return false
			var slot: int = _events.var_get(int(args[0]))
			var position: int = _events.var_get(int(args[1]))
			var move: int = _events.var_get(int(args[2]))
			if slot < 0 or slot >= _events.party.size() or position < 0 or position > 3:
				return true
			var moves: Array = (_events.party[slot].get("moves", []) as Array).duplicate()
			while moves.size() <= position:
				moves.append(0)
			moves[position] = move
			_events.party[slot]["moves"] = moves
		"initclock":
			pass # The wall clock itself is set by StartWallClock; nothing faults.
		"gettime":
			_events.var_set(0x8000, _events.clock_hour)
			_events.var_set(0x8001, _events.clock_minute)
			_events.var_set(0x8002, 0)
		"checkrandomizer":
			var any_on: int = int(_events.randomizer.values().any(
				func(value: Variant) -> bool: return bool(value)))
			_events.var_set(VAR_RESULT, any_on)
			comparison = any_on
		"checknuzlocke":
			_events.var_set(VAR_RESULT, int(_events.nuzlocke))
			comparison = int(_events.nuzlocke)
		"setwildbattle", "setwildbattleshiny":
			if args.size() >= 2:
				pending_wild = {"species": _events.var_get(int(args[0])),
					"level": _events.var_get(int(args[1])), "shiny": command == "setwildbattleshiny"}
		"dowildbattle":
			pending_wild = {}
		"setberrytree":
			# `ScrCmd_setberrytree`: tree, berry, stage, all literal bytes.
			if args.size() >= 3 and _events.berries != null:
				_events.berries.plant(int(args[0]), int(args[1]), int(args[2]))
		"checkpartymonlevel", "baobacheckmon", "getbraillestringwidth", "dynmultichoice":
			# `dynmultichoice` picks the first row until its menu exists.
			_events.var_set(VAR_RESULT, 0)
			comparison = 0
		_:
			pass # Unmodelled systems (followers, decorations, contests,
			# elevators, party removal, BP): the story continues without
			# them rather than dying on a fault.
	return true


func _callnative(args: Array) -> bool: # `callnative` (0x23): the function pointer plus its macro's trailing argument bytes.
	if args.is_empty():
		return false
	var func_ptr: int = int(args[0])
	if func_ptr >= 0x08000000 + ROM_SIZE: # `requests_effects=1` stores the pointer plus the ROM size; see Gen3Script.instruction.
		func_ptr -= ROM_SIZE
	match func_ptr:
		0x0820CD59: return _createmon(args) # ScrCmd_createmon.
		0x0812DC11: return true # UpdateFollowingPokemon: no follower model yet; the starter script only needs it to pass.
		0x08160895: return true # ShowHelpInfoWindow: no help-window UI; the clock trigger only needs it to pass.
		0x081F1DA5: # ObtainItemRandomize_NativeCall: the item in VAR_0x8000 is swapped for additem.
			if _events.randomizer_on("items"):
				_events.var_set(0x8000, Gen3Randomizer.item_for(_events,
					_events.var_get(0x8000), 900))
			return true
		_: return false


func _createmon(args: Array) -> bool: # `ScrCmd_createmon`: header bytes are operands 1-10; the flag-dependent halfwords follow in the script stream.
	if args.size() < 11:
		return false
	var side: int = int(args[1])
	var slot: int = int(args[2])
	var species: int = _events.var_get(int(args[3]) | (int(args[4]) << 8))
	var level: int = _events.var_get(int(args[5]) | (int(args[6]) << 8))
	var flags: int = int(args[7]) | (int(args[8]) << 8) | (int(args[9]) << 16) | (int(args[10]) << 24)
	# The importer consumes only the 10 header bytes, so `offset` still points at the first flag-dependent halfword; skip one per set flag bit to land on the next instruction.
	offset += 2 * _popcount(flags)
	if side != 0:
		return false # No enemy-party model; fault honestly instead of pretending the mon exists.
	var target: int = _events.party.size() if slot >= PARTY_SIZE else slot
	if species <= 0 or _data.species(species).is_empty() or level < 1 or level > 100 or target >= PARTY_SIZE:
		_events.var_set(VAR_RESULT, MON_CANT_GIVE)
		return true
	var mon: Dictionary = _gift_mon(species, level)
	if target < _events.party.size():
		_events.party[target] = mon
	else:
		_events.party.append(mon)
	_events.var_set(VAR_RESULT, MON_GIVEN_TO_PARTY)
	return true


func _gift_mon(species: int, level: int) -> Dictionary: # A gift mon's defaults: random IVs, no EVs, the level-up moves at or below `level`.
	var info: Dictionary = _data.species(species)
	var hp_iv: int = _events.random.next() % 32
	var base_hp: int = int((info.get("stats", {}) as Dictionary).get("hp", 0))
	var moves: Array[int] = []
	for row: Dictionary in _data.learnset(species):
		var learn_level: int = int(row.get("level", 0))
		if learn_level == 0 or learn_level > level:
			continue
		var move: int = int(row.get("move", 0))
		if move == 0 or move in moves:
			continue
		moves.append(move)
		if moves.size() > 4:
			moves.pop_front()
	return {"species": species, "nickname": String(info.get("name", "")), "level": level,
		"moves": moves, "egg": false, "hp": ((2 * base_hp + hp_iv) * level) / 100 + level + 10,
		"personality": (_events.random.next() << 16) | _events.random.next(), "ot_id": 0,
		"status": 0, "item": 0}


static func _popcount(value: int) -> int:
	var count: int = 0
	while value != 0:
		count += value & 1
		value >>= 1
	return count


func _value_command(command: String, args: Array) -> bool:
	if args.size() != 2:
		return false
	var dest: int = int(args[0])
	var value: int = int(args[1])
	match command:
		"setvar": _events.var_set(dest, value)
		"addvar": _events.var_set(dest, _events.var_get(dest) + value)
		"subvar": _events.var_set(dest, _events.var_get(dest) - _events.var_get(value))
		"copyvar", "setorcopyvar": _events.var_set(dest, _events.var_get(value))
		"compare_var_to_value": comparison = _compare(_events.var_get(dest), value)
		"compare_var_to_var": comparison = _compare(_events.var_get(dest), _events.var_get(value))
		"loadword", "loadbyte", "copylocal", "compare_local_to_local", "compare_local_to_value":
			return _local_command(command, dest, value)
		_: return false
	return true


func _local_command(command: String, dest: int, value: int) -> bool:
	if dest < 0 or dest >= locals.size():
		return false
	if command in ["copylocal", "compare_local_to_local"]:
		if value < 0 or value >= locals.size():
			return false
		value = locals[value]
	match command:
		"loadword", "loadbyte", "copylocal": locals[dest] = value
		"compare_local_to_local", "compare_local_to_value": comparison = _compare(locals[dest] & 0xFF, value & 0xFF)
	return true


static func _compare(left: int, right: int) -> int:
	return 0 if left < right else (1 if left == right else 2)
