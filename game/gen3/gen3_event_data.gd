class_name Gen3EventData
extends RefCounted

## `event_data.c`'s flags and vars: flag 0 reads clear and ignores writes; `VarGet` returns an id below `VARS_START` itself.

const VARS_START: int = 0x4000
const TEMP_FLAGS_COUNT: int = 0x20
const TEMP_VARS_COUNT: int = 0x10
const STRENGTH_FLAG: Dictionary = {
	&"ruby": 0x829, &"sapphire": 0x829, &"firered": 0x805, &"leafgreen": 0x805, &"emerald": 0x889, &"heart_soul": 0x864,
}
## The system flags `ClearTempFieldEventData` clears after the temporary ones.
## Heart & Soul's row is `pokehns/src/event_data.c`'s list: `FLAG_SYS_ENC_UP_ITEM`
## (0x862), `FLAG_SYS_ENC_DOWN_ITEM` (0x863), `FLAG_SYS_USE_STRENGTH` (0x864),
## `FLAG_SYS_CTRL_OBJ_DELETE` (0x866), `FLAG_NURSE_UNION_ROOM_REMINDER` (0x89E).
const CLEARED_SYSTEM_FLAGS: Dictionary = {
	&"ruby": [0x84D, 0x84E, STRENGTH_FLAG[&"ruby"], 0x861],
	&"sapphire": [0x84D, 0x84E, STRENGTH_FLAG[&"sapphire"], 0x861],
	&"firered": [0x803, 0x804, STRENGTH_FLAG[&"firered"], 0x807, 0x842],
	&"leafgreen": [0x803, 0x804, STRENGTH_FLAG[&"leafgreen"], 0x807, 0x842],
	&"emerald": [0x8AD, 0x8AE, STRENGTH_FLAG[&"emerald"], 0x8C1, 0x880],
	&"heart_soul": [0x862, 0x863, STRENGTH_FLAG[&"heart_soul"], 0x866, 0x89E],
}

var berries: Gen3BerryTrees
## The field's `gRngValue`, which is not saved.
var random := Gen3Random.new()
var game: StringName
## `gSaveBlock1Ptr->weather` and `weatherCycleStage`.
var weather: int = 0
var weather_cycle_stage: int = 0
## `IncrementGameStat`'s counters by `GAME_STAT_*`.
var stats: Dictionary = {}
## `gSaveBlock1Ptr->secretBases[].secretBaseId`, the player's first, and secret_base.c's `sCurSecretBaseId`.
var secret_bases: Array[int] = []
var current_secret_base: int = 0
var bag: Gen3Bag # `gSaveBlock1Ptr`'s items, money and coins; hosts create it, since it reads item pockets.
var party: Array[Dictionary] = [] # `gPlayerParty`: `species`, `nickname`, `moves`, `egg`, `hp`, `personality` and `ot_id`, with no empty rows.
var player_name: String = ""
var player_gender: int = 0 # `gSaveBlock2Ptr->playerGender`: 0 boy, 1 girl, chosen in the intro.
var rival_name: String = "" # FireRed and LeafGreen's `gSaveBlock1Ptr->rivalName`.
var registered_item: int = 0 # `gSaveBlock1Ptr->registeredItem`.
var respawn: int = 0 # `gSaveBlock1Ptr->lastHealLocation`'s `HEAL_LOCATION_*`.
var battle_outcome: int = 0 # `gBattleOutcome`.
var clock_hour: int = 12 # The wall clock's hour, set by `StartWallClock`; the RTC the story flags read.
var clock_minute: int = 0 # The wall clock's minute, set by `StartWallClock`.
var mom_balance: int = 0 # `gSaveBlock1Ptr->momSavings.momsMoney`; no deposit/withdraw input screen exists yet, so nothing changes it.
var mom_saving: bool = false # `gSaveBlock1Ptr->momSavings`' saving toggle, set by Mom's menu.
var controls_locked: bool = false # script.c's `sLockFieldControls`.
var script_delay: int = 0 # scrcmd.c::sPauseCounter is shared by foreground and immediate contexts.
var _flags: Dictionary = {}
var _vars: Dictionary = {}


func _init(game_id: StringName) -> void:
	game = game_id


func flag_get(id: int) -> bool:
	return _flags.has(id & 0xFFFF)


func flag_set(id: int) -> void:
	if id & 0xFFFF != 0:
		_flags[id & 0xFFFF] = true


func flag_clear(id: int) -> void:
	_flags.erase(id & 0xFFFF)


func var_get(id: int) -> int:
	id &= 0xFFFF
	return int(_vars.get(id, 0)) if id >= VARS_START else id


func var_set(id: int, value: int) -> void:
	if id & 0xFFFF >= VARS_START:
		_vars[id & 0xFFFF] = value & 0xFFFF


func clear_temp() -> void: # `ClearTempFieldEventData`, run on every map load.
	for id: int in TEMP_FLAGS_COUNT:
		_flags.erase(id)
	for id: int in TEMP_VARS_COUNT:
		_vars.erase(VARS_START + id)
	for id: int in CLEARED_SYSTEM_FLAGS[game]:
		_flags.erase(id)


func increment_stat(id: int) -> void: # `IncrementGameStat`: counters stop at 0xFFFFFF.
	stats[id] = mini(int(stats.get(id, 0)) + 1, 0xFFFFFF)


func to_dict() -> Dictionary: # `gSaveBlock1Ptr`'s flags, vars, party, bag, names, clock and Mom's savings as JSON. Flags and vars ride as id lists, since JSON keys are strings and the ids are not.
	var flag_list: Array[int] = []
	for id: Variant in _flags:
		flag_list.append(int(id))
	flag_list.sort()
	var var_list: Array = []
	for id: Variant in _vars:
		if int(id) >= 0x8000:
			continue # `gSpecialVar_*` are session EWRAM in the ROM, never saved.
		var_list.append([int(id), int(_vars[id])])
	var stat_list: Array = []
	for id: Variant in stats:
		stat_list.append([int(id), int(stats[id])])
	return {
		"game": String(game),
		"flags": flag_list,
		"vars": var_list,
		"party": party.duplicate(true),
		"bag": bag.to_dict() if bag != null else {},
		"player_name": player_name,
		"player_gender": player_gender,
		"rival_name": rival_name,
		"registered_item": registered_item,
		"respawn": respawn,
		"weather": weather,
		"weather_cycle_stage": weather_cycle_stage,
		"stats": stat_list,
		"secret_bases": secret_bases.duplicate(),
		"current_secret_base": current_secret_base,
		"clock_hour": clock_hour,
		"clock_minute": clock_minute,
		"mom_balance": mom_balance,
		"mom_saving": mom_saving,
		"battle_outcome": battle_outcome,
	}


## Bad data refuses, never crashes: null for a wrong shape, a game that is not
## [param data]'s, an out-of-range clock, Mom's balance, flag or var, a party
## that is not six or fewer real species, or a bag [Gen3Bag.from_dict] rejects.
## Session-only state stays out: the RNG, `controls_locked` and `script_delay`.
static func from_dict(raw: Variant, data: GameData) -> Gen3EventData:
	if not raw is Dictionary or data == null:
		return null
	var source: Dictionary = raw
	if StringName(source.get("game", "")) != data.id:
		return null
	var events := Gen3EventData.new(data.id)
	var flags: Variant = source.get("flags", null)
	if not flags is Array:
		return null
	for id: Variant in flags as Array:
		var flag_id: int = int(id)
		if flag_id <= 0 or flag_id > 0xFFFF:
			return null
		events._flags[flag_id] = true
	var vars: Variant = source.get("vars", null)
	if not vars is Array:
		return null
	for pair: Variant in vars as Array:
		if not pair is Array or (pair as Array).size() != 2:
			return null
		var var_id: int = int((pair as Array)[0])
		var value: int = int((pair as Array)[1])
		if var_id < 0 or var_id > 0xFFFF or value < 0 or value > 0xFFFF:
			return null
		if var_id >= 0x8000:
			continue # Special vars are session-only; an old save's are dropped, not restored.
		events._vars[var_id] = value
	var party: Variant = source.get("party", null)
	if not party is Array or (party as Array).size() > 6:
		return null
	for member: Variant in party as Array:
		if not member is Dictionary or int((member as Dictionary).get("species", 0)) <= 0:
			return null
		events.party.append((member as Dictionary).duplicate(true))
	var bag_raw: Variant = source.get("bag", null)
	if not bag_raw is Dictionary:
		return null
	if not (bag_raw as Dictionary).is_empty():
		var bag := Gen3Bag.new(data, events)
		if not bag.from_dict(bag_raw):
			return null
		events.bag = bag
	var stats: Variant = source.get("stats", null)
	if not stats is Array:
		return null
	for pair: Variant in stats as Array:
		if not pair is Array or (pair as Array).size() != 2:
			return null
		var stat_id: int = int((pair as Array)[0])
		var stat_value: int = int((pair as Array)[1])
		if stat_id < 0 or stat_value < 0 or stat_value > 0xFFFFFF:
			return null
		events.stats[stat_id] = stat_value
	var bases: Variant = source.get("secret_bases", null)
	if not bases is Array or (bases as Array).size() > 64:
		return null
	for base: Variant in bases as Array:
		if int(base) < 0:
			return null
		events.secret_bases.append(int(base))
	events.player_name = String(source.get("player_name", ""))
	events.player_gender = int(source.get("player_gender", 0))
	if events.player_gender < 0 or events.player_gender > 1:
		return null
	events.rival_name = String(source.get("rival_name", ""))
	if events.player_name.length() > 10 or events.rival_name.length() > 10:
		return null
	events.registered_item = int(source.get("registered_item", 0))
	events.respawn = int(source.get("respawn", 0))
	events.weather = int(source.get("weather", 0))
	events.weather_cycle_stage = int(source.get("weather_cycle_stage", 0))
	events.current_secret_base = int(source.get("current_secret_base", 0))
	events.battle_outcome = int(source.get("battle_outcome", 0))
	if events.registered_item < 0 or events.registered_item > 0xFFFF \
			or events.respawn < 0 or events.respawn > 0xFFFF \
			or events.weather < 0 or events.weather > 0xFFFF \
			or events.weather_cycle_stage < 0 or events.weather_cycle_stage > 0xFFFF \
			or events.current_secret_base < 0 or events.battle_outcome < 0 \
			or events.battle_outcome > 0xFFFF:
		return null
	events.clock_hour = int(source.get("clock_hour", -1))
	events.clock_minute = int(source.get("clock_minute", -1))
	if events.clock_hour < 0 or events.clock_hour > 23 \
			or events.clock_minute < 0 or events.clock_minute > 59:
		return null
	events.mom_balance = int(source.get("mom_balance", -1))
	if events.mom_balance < 0 or events.mom_balance > Gen3Bag.MAX_MONEY:
		return null
	events.mom_saving = bool(source.get("mom_saving", false))
	return events
