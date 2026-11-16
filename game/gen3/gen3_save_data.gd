class_name Gen3SaveData
extends RefCounted

## One Gen 3 project save slot: `gSaveBlock1Ptr`'s contents as JSON (`save.h`'s
## save blocks hold the player, party, bag, flags/vars, clock and Mom's savings;
## the raw SRAM layout is never written). Stored by [Gen3SaveStore] under
## `user://save_slots/<game>_<sha8>/slot_N.json` with a `#gen3save` container,
## so a Gen 3 slot can never be mistaken for a Gen 2 one.

const FORMAT_VERSION: int = 1
const MAX_SLOTS: int = 99
const MAX_PLAYER_NAME: int = 10
const MAX_LABEL: int = 24
const MAX_PARTY: int = 6

var format_version: int = FORMAT_VERSION
var game_id: StringName = &""
var rom_sha1: String = ""
var slot: int = -1
var label: String = ""
var player_name: String = ""
var map_group: int = 0
var map_number: int = 0
var player_cell := Vector2i.ZERO # Layout cell, without `Gen3MapGrid.MAP_OFFSET`.
var facing: int = 1 # `Gen3ObjectEvents.Direction`, 1..4.
var events: Dictionary = {} # [Gen3EventData]'s `to_dict`, validated on load.
var play_time_seconds: int = 0 # Carried from the loaded save; no Gen 3 play timer ticks yet.
var saved_at: int = 0 # Host second the slot was written at.


## The field as it stands: the avatar's layout cell and facing, the map the
## camera is on, and the event data. Null where the screen has no avatar yet.
static func capture(
	data: GameData, slot_number: int, event_data: Gen3EventData,
	group: int, number: int, cell: Vector2i, facing_direction: int,
	play_seconds: int = 0
) -> Gen3SaveData:
	if data == null or event_data == null or slot_number < 0 or slot_number >= MAX_SLOTS:
		return null
	var out := Gen3SaveData.new()
	out.game_id = data.id
	out.rom_sha1 = data.sha1
	out.slot = slot_number
	out.player_name = event_data.player_name
	out.label = event_data.player_name
	out.map_group = group
	out.map_number = number
	out.player_cell = cell
	out.facing = facing_direction
	out.events = event_data.to_dict()
	out.play_time_seconds = maxi(play_seconds, 0)
	out.saved_at = int(Time.get_unix_time_from_system())
	return out


func to_dict() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"game_id": String(game_id),
		"rom_sha1": rom_sha1,
		"slot": slot,
		"label": label,
		"player_name": player_name,
		"map_group": map_group,
		"map_number": map_number,
		"player_cell": [player_cell.x, player_cell.y],
		"facing": facing,
		"events": events.duplicate(true),
		"play_time_seconds": play_time_seconds,
		"saved_at": saved_at,
	}


## Bad data refuses, never crashes: null for a wrong shape, a version this code
## does not know, a game or cartridge that is not [param data]'s, a map that
## does not exist, or event data [Gen3EventData.from_dict] rejects. Without a
## cartridge cache the game, ROM and map checks are skipped, so a caller that
## needs them must pass one.
static func from_dict(raw: Variant, data: GameData = null) -> Gen3SaveData:
	if not raw is Dictionary:
		return null
	var source: Dictionary = raw
	if int(source.get("format_version", -1)) != FORMAT_VERSION:
		return null
	var out := Gen3SaveData.new()
	out.game_id = StringName(source.get("game_id", ""))
	out.rom_sha1 = String(source.get("rom_sha1", ""))
	if out.game_id == &"" or out.rom_sha1.length() != 40:
		return null
	out.slot = int(source.get("slot", -1))
	if out.slot < 0 or out.slot >= MAX_SLOTS:
		return null
	out.label = String(source.get("label", "")).substr(0, MAX_LABEL)
	out.player_name = String(source.get("player_name", ""))
	if out.player_name.length() > MAX_PLAYER_NAME:
		return null
	out.map_group = int(source.get("map_group", -1))
	out.map_number = int(source.get("map_number", -1))
	if out.map_group < 0 or out.map_number < 0:
		return null
	var cell: Variant = source.get("player_cell", null)
	if not cell is Array or (cell as Array).size() != 2:
		return null
	out.player_cell = Vector2i(int((cell as Array)[0]), int((cell as Array)[1]))
	if out.player_cell.x < 0 or out.player_cell.x > 255 \
			or out.player_cell.y < 0 or out.player_cell.y > 255:
		return null
	out.facing = int(source.get("facing", 0))
	if out.facing < 1 or out.facing > 4:
		return null
	var raw_events: Variant = source.get("events", null)
	if not raw_events is Dictionary or (raw_events as Dictionary).is_empty():
		return null
	out.events = (raw_events as Dictionary).duplicate(true)
	out.play_time_seconds = maxi(int(source.get("play_time_seconds", 0)), 0)
	out.saved_at = maxi(int(source.get("saved_at", 0)), 0)
	if data != null:
		if out.game_id != data.id or out.rom_sha1 != data.sha1:
			return null
		if data.world_map_header(out.map_group, out.map_number).is_empty():
			return null
		if Gen3EventData.from_dict(out.events, data) == null:
			return null
	return out
