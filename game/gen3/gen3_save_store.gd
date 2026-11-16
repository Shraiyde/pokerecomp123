class_name Gen3SaveStore
extends RefCounted

## User-owned Gen 3 save slots, mirroring [Gen2SaveStore]'s file discipline:
## `user://save_slots/<game>_<sha8>/slot_N.json`, primary plus `.bak` backup,
## a `#gen3save` checksum container. The prefix keeps Gen 2 and Gen 3 slots
## from ever mixing; a file without the header is refused, not guessed at.

const ROOT: String = "user://save_slots"
const MAX_SLOTS: int = Gen3SaveData.MAX_SLOTS
const SLOT_PREFIX: String = "slot_"
const SLOT_SUFFIX: String = ".json"
const BACKUP_SUFFIX: String = ".bak"
const CONTAINER_PREFIX: String = "#gen3save"
const CONTAINER_VERSION: int = 1


static func directory_for(game_id: StringName, rom_sha1: String) -> String:
	return "%s/%s_%s" % [ROOT, String(game_id), rom_sha1.substr(0, 8)]


static func path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s/%s%d%s" % [
		directory_for(game_id, rom_sha1), SLOT_PREFIX, slot, SLOT_SUFFIX
	]


static func backup_path_for(game_id: StringName, rom_sha1: String, slot: int) -> String:
	return "%s%s" % [path_for(game_id, rom_sha1, slot), BACKUP_SUFFIX]


static func exists(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	return FileAccess.file_exists(path_for(game_id, rom_sha1, slot)) \
		or FileAccess.file_exists(backup_path_for(game_id, rom_sha1, slot))


## Writes the primary copy, then the backup, in complete-then-copy order, so a
## crash during either write leaves the other one readable. The candidate is
## validated against [param data] before anything is written.
static func save(save_data: Gen3SaveData, data: GameData) -> Dictionary:
	if save_data == null or data == null:
		return _failure("no save data to write")
	if Gen3SaveData.from_dict(save_data.to_dict(), data) == null:
		return _failure("the save data is not valid for this cartridge")
	var path: String = path_for(save_data.game_id, save_data.rom_sha1, save_data.slot)
	var directory: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _failure("could not create the save directory")
	var document: String = _document(save_data.to_dict())
	var primary: Dictionary = _write_file(path, document)
	if not primary["ok"]:
		return primary
	var backup: Dictionary = _write_file(
		backup_path_for(save_data.game_id, save_data.rom_sha1, save_data.slot), document
	)
	if not backup["ok"]:
		return _failure("could not write the backup save")
	return {"ok": true, "message": ""}


## Takes the primary copy and falls back to the backup on any failure. Unlike
## the source this never repairs the weak copy, because a read must not write;
## the next save rewrites both copies.
static func load_result(
	game_id: StringName, rom_sha1: String, slot: int, data: GameData
) -> Dictionary:
	if not _valid_slot(slot):
		return _failure("save slot %d is out of range" % slot)
	if data == null:
		return _failure("no cartridge cache is selected")
	var path: String = path_for(game_id, rom_sha1, slot)
	var backup: String = backup_path_for(game_id, rom_sha1, slot)
	var has_primary: bool = FileAccess.file_exists(path)
	var has_backup: bool = FileAccess.file_exists(backup)
	if not has_primary and not has_backup:
		return _failure("save slot %d is empty" % (slot + 1))

	var primary_result: Dictionary = {}
	if has_primary:
		primary_result = _load_copy(path, slot, data)
		if primary_result["ok"]:
			primary_result["recovered"] = false
			return primary_result
	if has_backup:
		var backup_result: Dictionary = _load_copy(backup, slot, data)
		if backup_result["ok"]:
			backup_result["recovered"] = true
			return backup_result
		if not has_primary:
			return backup_result
	return primary_result


## The slots that exist, in slot order, for the launcher and the world screen.
static func slots_for(game_id: StringName, rom_sha1: String, data: GameData) -> Array:
	var out: Array = []
	for slot: int in occupied_slots(game_id, rom_sha1):
		var row: Dictionary = {
			"slot": slot,
			"exists": true,
			"valid": false,
			"label": "",
			"player_name": "",
			"message": "Empty",
		}
		var result: Dictionary = load_result(game_id, rom_sha1, slot, data)
		row["valid"] = bool(result["ok"])
		row["message"] = "Ready" if result["ok"] else String(result["message"])
		if result["ok"]:
			var loaded: Gen3SaveData = result["save"]
			row["label"] = loaded.label
			row["player_name"] = loaded.player_name
		out.append(row)
	return out


## The same row shape [method slots_for] returns, for a slot number with nothing
## on disk.
static func empty_slot_row(slot: int) -> Dictionary:
	return {
		"slot": slot,
		"exists": false,
		"valid": false,
		"label": "",
		"player_name": "",
		"message": "Empty",
	}


## Slot numbers with a primary or backup copy on disk, ascending.
static func occupied_slots(game_id: StringName, rom_sha1: String) -> Array[int]:
	var found: Array[int] = []
	var directory: String = directory_for(game_id, rom_sha1)
	if not DirAccess.dir_exists_absolute(directory):
		return found
	for file_name: String in DirAccess.get_files_at(directory):
		var slot: int = _slot_from_file_name(file_name)
		if slot >= 0 and not found.has(slot):
			found.append(slot)
	found.sort()
	return found


static func _slot_from_file_name(file_name: String) -> int:
	var name: String = file_name
	if name.ends_with(BACKUP_SUFFIX):
		name = name.substr(0, name.length() - BACKUP_SUFFIX.length())
	if not name.begins_with(SLOT_PREFIX) or not name.ends_with(SLOT_SUFFIX):
		return -1
	var digits: String = name.substr(
		SLOT_PREFIX.length(), name.length() - SLOT_PREFIX.length() - SLOT_SUFFIX.length()
	)
	if not digits.is_valid_int():
		return -1
	var slot: int = int(digits)
	return slot if _valid_slot(slot) else -1


## The lowest unused slot number, or -1 when the ceiling is reached.
static func next_free_slot(game_id: StringName, rom_sha1: String) -> int:
	var used: Array[int] = occupied_slots(game_id, rom_sha1)
	for slot: int in MAX_SLOTS:
		if not used.has(slot):
			return slot
	return -1


static func delete_slot(game_id: StringName, rom_sha1: String, slot: int) -> bool:
	if not exists(game_id, rom_sha1, slot):
		return false
	var removed: bool = false
	for path: String in [
		path_for(game_id, rom_sha1, slot), backup_path_for(game_id, rom_sha1, slot)
	]:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(path) == OK:
			removed = true
	return removed


static func _load_copy(path: String, slot: int, data: GameData) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("save slot %d could not be opened" % (slot + 1))
	var text: String = file.get_as_text()
	file.close()
	var container: Dictionary = _unwrap(text)
	if not container["ok"]:
		return _failure("save slot %d: %s" % [slot + 1, container["message"]])
	var parser := JSON.new()
	var parse_error: Error = parser.parse(String(container["payload"]))
	if parse_error != OK:
		return _failure("save slot %d is not valid JSON data" % (slot + 1))
	var loaded_save: Gen3SaveData = Gen3SaveData.from_dict(parser.data, data)
	if loaded_save == null:
		return _failure("save slot %d is not valid save data" % (slot + 1))
	return {"ok": true, "message": "", "save": loaded_save}


static func _document(body: Dictionary) -> String:
	var payload: String = JSON.stringify(body, "\t", false)
	return "%s %d %d\n%s" % [CONTAINER_PREFIX, CONTAINER_VERSION, _checksum(payload), payload]


## Returns the payload of a slot file. A file without the header line is not a
## Gen 3 save and is refused, so a Gen 2 slot is never read as one.
static func _unwrap(text: String) -> Dictionary:
	if not text.begins_with("%s " % CONTAINER_PREFIX):
		return {"ok": false, "payload": "", "message": "not a Gen 3 save file"}
	var break_index: int = text.find("\n")
	if break_index < 0:
		return {"ok": false, "payload": "", "message": "the save header is incomplete"}
	var header: PackedStringArray = text.substr(0, break_index).split(" ", false)
	var payload: String = text.substr(break_index + 1)
	if header.size() != 3 or not header[2].is_valid_int() or int(header[1]) != CONTAINER_VERSION:
		return {"ok": false, "payload": "", "message": "unsupported save container"}
	if int(header[2]) != _checksum(payload):
		return {"ok": false, "payload": "", "message": "the save data failed its checksum"}
	return {"ok": true, "payload": payload, "message": ""}


## `Checksum` in engine/menus/save.asm: a wrapping 16-bit sum of every byte.
static func _checksum(payload: String) -> int:
	var sum: int = 0
	for byte: int in payload.to_utf8_buffer():
		sum = (sum + byte) & 0xFFFF
	return sum


static func _write_file(target: String, document: String) -> Dictionary:
	var temporary: String = "%s.tmp" % target
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("could not open the save for writing")
	file.store_string(document)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("could not finish writing the save")
	return {"ok": true, "message": ""}


static func _valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < MAX_SLOTS


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
