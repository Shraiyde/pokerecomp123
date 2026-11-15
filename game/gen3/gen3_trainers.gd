class_name Gen3Trainers
extends RefCounted

## `gTrainers` holds individuals; `CreateNPCTrainerParty` picks one of four padded structs; species import as national.
## pokeemerald-expansion's Trainer is 52 bytes (aiFlags u64, party pointer, four item slots, class,
## encounter music/gender, pic, name, battle type, party size, pool fields, override, back pic) and its
## TrainerMon is a fixed 36 bytes, so the party has no per-flag strides.
static func verify(rom: RomFile, layout: Dictionary) -> Dictionary:
	var size: int = int(layout.get("trainer_struct_size", Gen3Layout.TRAINER_SIZE))
	if not rom.in_bounds(int(layout["trainers"]), int(layout["trainer_count"]) * size):
		return _fail("gTrainers leaves the dump.")
	var class_size: int = int(layout.get("trainer_class_struct_size", Gen3Layout.TRAINER_CLASS_NAME_SIZE))
	for number: int in int(layout["trainer_class_count"]):
		var at: int = int(layout["trainer_class_names"]) + number * class_size
		if not Gen3Text.ends_within(rom.id, rom.bytes(), at, Gen3Layout.TRAINER_CLASS_NAME_SIZE):
			return _fail("Trainer class %d has no name end." % number)
	for number: int in range(1, int(layout["trainer_count"])):
		if _is_empty_trainer(rom, layout, number):
			continue
		if _trainer(rom, layout, number).is_empty():
			return _fail("Trainer %d has an invalid header or party." % number)
	var money: Dictionary = _verify_money(rom, layout)
	return _verify_pics(rom, layout) if bool(money["ok"]) else money


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


## An unused slot: every byte zero, so no party size. Heart & Soul leaves slot 330 empty.
static func _is_empty_trainer(rom: RomFile, layout: Dictionary, number: int) -> bool:
	if not bool(layout.get("skip_empty_trainers", false)):
		return false
	var at: int = int(layout["trainers"]) + number * int(layout.get("trainer_struct_size", Gen3Layout.TRAINER_SIZE))
	return rom.u8(at + 43) == 0


static func read(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for number: int in range(1, int(layout["trainer_count"])):
		if _is_empty_trainer(rom, layout, number):
			continue
		var entry: Dictionary = _trainer(rom, layout, number)
		if entry.is_empty():
			return []
		out.append(entry)
	return out


static func _trainer(rom: RomFile, layout: Dictionary, number: int) -> Dictionary:
	if layout.has("trainer_struct_size"):
		return _trainer_expansion(rom, layout, number)
	var at: int = int(layout["trainers"]) + number * Gen3Layout.TRAINER_SIZE
	if not rom.in_bounds(at, Gen3Layout.TRAINER_SIZE):
		return {}
	var flags: int = rom.u8(at)
	var trainer_class: int = rom.u8(at + 1)
	var picture: int = rom.u8(at + 3)
	var count: int = rom.u8(at + 32)
	if flags >= Gen3Layout.PARTY_STRIDES.size() or trainer_class >= int(layout["trainer_class_count"]) \
		or picture >= int(layout["trainer_pic_count"]) or count < 1 or count > Gen3Layout.TRAINER_PARTY_LIMIT \
		or rom.u8(at + 24) > 1 or not Gen3Text.ends_within(rom.id, rom.bytes(), at + 4, Gen3Layout.TRAINER_NAME_SIZE):
		return {}
	var party: Array = _party(rom, layout, Gen3Layout.rom_offset(rom.u32le(at + 36)), count, flags)
	var items: Array[int] = []
	for slot: int in 4:
		var item: int = rom.u16le(at + 16 + slot * 2)
		if item >= int(layout["item_count"]):
			return {}
		items.append(item)
	if party.is_empty():
		return {}
	return {
		"number": number,
		"name": Gen3Text.decode_fixed(rom.id, rom.bytes(), at + 4, Gen3Layout.TRAINER_NAME_SIZE),
		"class": trainer_class,
		"class_name": Gen3Text.decode_fixed(rom.id, rom.bytes(), int(layout["trainer_class_names"])
			+ trainer_class * Gen3Layout.TRAINER_CLASS_NAME_SIZE, Gen3Layout.TRAINER_CLASS_NAME_SIZE),
		"type": flags,
		"female": (rom.u8(at + 2) & 0x80) != 0,
		"encounter_music": rom.u8(at + 2) & 0x7F,
		"picture": picture,
		"palette": _palette(rom, layout, picture),
		"pic_size": rom.u16le(int(layout["trainer_pics"]) + picture * Gen3Layout.PIC_ENTRY_SIZE + 4),
		"pic_coordinates": _coordinates(rom, layout, picture),
		"items": items,
		"double_battle": rom.u8(at + 24) != 0,
		"ai_flags": rom.u32le(at + 28),
		"base_money": _base_money(rom, layout, trainer_class),
		"party": party,
	}


## Heart & Soul's Trainer: aiFlags u64 +0, party +8, items +12, class +28, music/gender +29,
## pic +30, name +31 (11 bytes), battle type +42, party size +43, override +48, back pic +50.
## The party flags byte does not exist; the flags are derived from the party itself.
static func _trainer_expansion(rom: RomFile, layout: Dictionary, number: int) -> Dictionary:
	var at: int = int(layout["trainers"]) + number * int(layout["trainer_struct_size"])
	if not rom.in_bounds(at, int(layout["trainer_struct_size"])):
		return {}
	var trainer_class: int = rom.u8(at + 28)
	var picture: int = rom.u8(at + 30)
	var count: int = rom.u8(at + 43)
	var name_size: int = int(layout.get("trainer_name_size", Gen3Layout.TRAINER_NAME_SIZE))
	if trainer_class >= int(layout["trainer_class_count"]) \
		or picture >= int(layout["trainer_pic_count"]) or count < 1 or count > Gen3Layout.TRAINER_PARTY_LIMIT \
		or (rom.u8(at + 42) & 3) > 1 \
		or not Gen3Text.ends_within(rom.id, rom.bytes(), at + 31, name_size):
		return {}
	var party: Array = _party(rom, layout, Gen3Layout.rom_offset(rom.u32le(at + 8)), count, -1)
	var items: Array[int] = []
	for slot: int in 4:
		var item: int = rom.u16le(at + 12 + slot * 2)
		if item >= int(layout["item_count"]):
			return {}
		items.append(item)
	if party.is_empty():
		return {}
	var flags: int = 0
	for mon: Dictionary in party:
		for move: int in mon["moves"]:
			if move != 0:
				flags |= Gen3Layout.PARTY_CUSTOM_MOVES
				break
		if int(mon["item"]) != 0:
			flags |= Gen3Layout.PARTY_HELD_ITEM
	return {
		"number": number,
		"name": Gen3Text.decode_fixed(rom.id, rom.bytes(), at + 31, name_size),
		"class": trainer_class,
		"class_name": Gen3Text.decode_fixed(rom.id, rom.bytes(), int(layout["trainer_class_names"])
			+ trainer_class * int(layout.get("trainer_class_struct_size", Gen3Layout.TRAINER_CLASS_NAME_SIZE)),
			Gen3Layout.TRAINER_CLASS_NAME_SIZE),
		"type": flags,
		"female": (rom.u8(at + 29) & 0x80) != 0,
		"encounter_music": rom.u8(at + 29) & 0x7F,
		"picture": picture,
		"palette": _palette(rom, layout, picture),
		"pic_size": rom.u16le(_pic_at(rom, layout, picture, 8)),
		"pic_coordinates": _coordinates(rom, layout, picture),
		"items": items,
		"double_battle": (rom.u8(at + 42) & 3) == 1,
		"ai_flags": rom.u32le(at) | (rom.u32le(at + 4) << 32),
		"base_money": _base_money(rom, layout, trainer_class),
		"party": party,
	}


static func _party(rom: RomFile, layout: Dictionary, at: int, count: int, flags: int) -> Array:
	var stride: int = int(layout["trainer_party_size"]) if flags < 0 else Gen3Layout.PARTY_STRIDES[flags]
	if at % 4 != 0 or not rom.in_bounds(at, count * stride):
		return []
	var out: Array = []
	for slot: int in count:
		var mon: Dictionary = _mon(rom, layout, at + slot * stride, flags)
		if mon.is_empty():
			return []
		out.append(mon)
	return out


static func _mon(rom: RomFile, layout: Dictionary, at: int, flags: int) -> Dictionary:
	if flags < 0:
		return _mon_expansion(rom, layout, at)
	var species: int = Gen3Layout.national_number(rom, layout, rom.u16le(at + 4))
	var level: int = rom.u8(at + 2)
	var iv: int = rom.u16le(at)
	var held: bool = (flags & Gen3Layout.PARTY_HELD_ITEM) != 0
	var item: int = rom.u16le(at + 6) if held else 0
	if species < 1 or species > Gen3Layout.national_dex_count(layout) or level < 1 or level > 100 \
		or iv > 255 or item >= int(layout["item_count"]):
		return {}
	var moves: Array[int] = []
	if (flags & Gen3Layout.PARTY_CUSTOM_MOVES) != 0:
		for slot: int in 4:
			var move: int = rom.u16le(at + (8 if held else 6) + slot * 2)
			if move >= Gen3Layout.moves_count(layout):
				return {}
			moves.append(move)
	return {"species": species, "level": level, "iv": iv, "item": item, "moves": moves}


## Heart & Soul's TrainerMon: nickname +0, ev +4, iv u32 +8 (6 bits per stat, 30 bits),
## moves 4x u16 +12, species +20, held item +22, ability +24, level +26.
static func _mon_expansion(rom: RomFile, layout: Dictionary, at: int) -> Dictionary:
	var species: int = Gen3Layout.national_number(rom, layout, rom.u16le(at + 20))
	var level: int = rom.u8(at + 26)
	var iv: int = rom.u32le(at + 8)
	var item: int = rom.u16le(at + 22)
	if species < 1 or species > Gen3Layout.national_dex_count(layout) or level < 1 or level > 100 \
		or iv > 0x3FFFFFFF or item >= int(layout["item_count"]):
		return {}
	var moves: Array[int] = []
	for slot: int in 4:
		var move: int = rom.u16le(at + 12 + slot * 2)
		if move >= Gen3Layout.moves_count(layout):
			return {}
		moves.append(move)
	return {"species": species, "level": level, "iv": iv, "item": item, "moves": moves}


## Money tables end on class 0xff, whose value is the cartridge's fallback.
## Heart & Soul keeps the money in TrainerClass itself, so there is no table to scan.
static func _base_money(rom: RomFile, layout: Dictionary, trainer_class: int) -> int:
	if layout.has("trainer_money_field"):
		var at: int = int(layout["trainer_class_names"]) \
			+ trainer_class * int(layout.get("trainer_class_struct_size", Gen3Layout.TRAINER_CLASS_NAME_SIZE)) \
			+ int(layout["trainer_money_field"])
		return rom.u8(at) if rom.in_bounds(at, 1) else -1
	var money_at: int = int(layout["trainer_money"])
	for row: int in 256:
		if not rom.in_bounds(money_at + row * 2, 2):
			return -1
		var key: int = rom.u8(money_at + row * 2)
		if key == trainer_class or key == 0xFF:
			return rom.u8(money_at + row * 2 + 1)
	return -1


static func _verify_money(rom: RomFile, layout: Dictionary) -> Dictionary:
	if layout.has("trainer_money_field"):
		return {"ok": true}
	var at: int = int(layout["trainer_money"])
	for row: int in 256:
		if not rom.in_bounds(at + row * 2, 2):
			return _fail("Trainer money table leaves the dump.")
		var key: int = rom.u8(at + row * 2)
		if key == 0xFF:
			return {"ok": true}
		if key >= int(layout["trainer_class_count"]):
			return _fail("Trainer money row %d names an invalid class." % row)
	return _fail("Trainer money table has no end.")


static func _coordinates(rom: RomFile, layout: Dictionary, picture: int) -> Dictionary:
	if layout.has("trainer_pic_struct_size"):
		var at: int = int(layout["trainer_pics"]) + picture * int(layout["trainer_pic_struct_size"])
		return {"size": 0, "y_offset": rom.u8(at)}
	var vat: int = int(layout["trainer_coords"]) + picture * 4
	return {"size": rom.u8(vat), "y_offset": rom.u8(vat + 1)}


## Address of a field inside a trainer-pic entry. Vanilla entries are 8-byte
## CompressedSpriteSheet rows; Heart & Soul's are 32-byte TrainerSprite structs.
static func _pic_at(rom: RomFile, layout: Dictionary, picture: int, field: int) -> int:
	if layout.has("trainer_pic_struct_size"):
		return int(layout["trainer_pics"]) + picture * int(layout["trainer_pic_struct_size"]) + field
	return int(layout["trainer_pics"]) + picture * Gen3Layout.PIC_ENTRY_SIZE + field


static func _raw(rom: RomFile, layout: Dictionary, key: String, picture: int) -> PackedByteArray:
	if layout.has("trainer_pic_struct_size"):
		var field: int = 4 if key == "trainer_pics" else 12
		var at: int = Gen3Layout.rom_offset(rom.u32le(_pic_at(rom, layout, picture, field)))
		if at < 0:
			return PackedByteArray()
		# Heart & Soul stores trainer pictures and palettes raw, not LZ-compressed.
		var unit: int = Gen3Layout.PALETTE_BYTES if key == "trainer_palettes" else Gen3Layout.PIC_BYTES
		return rom.slice(at, unit)
	var vat: int = int(layout[key]) + picture * Gen3Layout.PIC_ENTRY_SIZE
	return GbaLz.decompress(rom.bytes(), Gen3Layout.rom_offset(rom.u32le(vat)))


static func _palette(rom: RomFile, layout: Dictionary, picture: int) -> Array[int]:
	var raw: PackedByteArray = _raw(rom, layout, "trainer_palettes", picture)
	var out: Array[int] = []
	if raw.size() != Gen3Layout.PALETTE_BYTES:
		return out
	for at: int in range(0, raw.size(), 2):
		out.append(raw[at] | raw[at + 1] << 8)
	return out


static func palettes(rom: RomFile, layout: Dictionary) -> Array:
	var out: Array = []
	for picture: int in int(layout["trainer_pic_count"]):
		out.append(_palette(rom, layout, picture))
	return out


## Some sheets reserve two canvases but decompress to one (front_pic_tables).
static func _verify_pics(rom: RomFile, layout: Dictionary) -> Dictionary:
	if layout.has("trainer_pic_struct_size"):
		return _verify_pics_expansion(rom, layout)
	var count: int = int(layout["trainer_pic_count"])
	if not rom.in_bounds(int(layout["trainer_coords"]), count * 4):
		return _fail("Trainer coordinates leave the dump.")
	for key: String in ["trainer_pics", "trainer_palettes"]:
		for picture: int in count:
			var at: int = int(layout[key]) + picture * Gen3Layout.PIC_ENTRY_SIZE
			var palette: bool = key == "trainer_palettes"
			var size: int = Gen3Layout.PALETTE_BYTES if palette else Gen3Layout.PIC_BYTES
			if not rom.in_bounds(at, Gen3Layout.PIC_ENTRY_SIZE) or rom.u16le(at + (4 if palette else 6)) != picture:
				return _fail("%s row %d has an invalid tag." % [key, picture])
			if _raw(rom, layout, key, picture).size() != size or not palette and not [size, size * 2].has(rom.u16le(at + 4)):
				return _fail("%s row %d has an invalid size." % [key, picture])
	return {"ok": true, "message": "Trainers verified."}


## Heart & Soul's TrainerSprite: front pic data +4, size +8, tag +10; palette data +12, tag +16.
static func _verify_pics_expansion(rom: RomFile, layout: Dictionary) -> Dictionary:
	var count: int = int(layout["trainer_pic_count"])
	for picture: int in count:
		var base: int = int(layout["trainer_pics"]) + picture * int(layout["trainer_pic_struct_size"])
		if not rom.in_bounds(base, int(layout["trainer_pic_struct_size"])):
			return _fail("Trainer pic %d leaves the dump." % picture)
		if rom.u16le(base + 10) != picture or rom.u16le(base + 16) != picture:
			return _fail("Trainer pic %d has an invalid tag." % picture)
		if rom.u16le(base + 8) != Gen3Layout.PIC_BYTES:
			return _fail("Trainer pic %d has an invalid size." % picture)
		if _raw(rom, layout, "trainer_pics", picture).size() != Gen3Layout.PIC_BYTES \
			or _raw(rom, layout, "trainer_palettes", picture).size() != Gen3Layout.PALETTE_BYTES:
			return _fail("Trainer pic %d decodes to the wrong size." % picture)
	return {"ok": true, "message": "Trainers verified."}


static func import_pics(rom: RomFile, layout: Dictionary, directory: String) -> Dictionary:
	var count: int = int(layout["trainer_pic_count"])
	var atlas: Dictionary = PokeTiles.new_atlas(Gen3Layout.PIC_TILES, count)
	for picture: int in count:
		var pixels: PackedByteArray = GbaTiles.decode(_raw(rom, layout, "trainer_pics", picture), 8, 8)
		PokeTiles.blit_pic(pixels, 8, atlas, picture)
	if not RomCache.write_indices(RomCache.pic_path(directory, "trainers"), atlas["pixels"]):
		return {}
	return PokeTiles.atlas_record(atlas)
