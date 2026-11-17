class_name Gen3CatchResolver
extends RefCounted

## Throwing a ball (`Cmd_handleballthrow` / `Cmd_trycatchpokemon`):
## the ROM's `ComputeCaptureOdds` on the cartridge's catch rate and the
## ball's multiplier, rolled as the cartridge rolls it. The full party
## and the starter-given mons refuse the ball; a nuzlocke game refuses
## every map except its recorded first encounter. Returns the caught
## party row, or {} when the mon breaks free.


static func try_catch(data: GameData, events: Gen3EventData,
		species: int, level: int, foe_hp: int, ball: int) -> Dictionary:
	if events.party.size() >= 6:
		return {}
	if events.nuzlocke and not bool(events.last_wild.get("nuzlocke_first", false)):
		return {}
	# Starter-given and gift mons are never on the wild side; this guards
	# the call path, not the data.
	events.random.randi()
	var odds: int = _capture_odds(data, events, species, level, foe_hp, ball)
	return _gift_mon(data, events, species, level) if events.random.randi_range(0, 255) < odds else {}


static func _capture_odds(data: GameData, events: Gen3EventData, species: int, level: int, foe_hp: int, ball: int) -> int:
	var info: Dictionary = data.species(species)
	var max_hp: int = ((2 * int((info.get("stats", {}) as Dictionary).get("hp", 50)) + 15) * level) / 100 + level + 10
	foe_hp = clampi(foe_hp, 1, max_hp)
	if ball == 4: # ITEM_MASTER_BALL is always 1..3 before Safari in the H&S item table.
		return 256
	# The ROM's mapping is by ball kind (Great 1.5x, Ultra 2x, the rest
	# situational), keyed here on the H&S item-table ranges the importer
	# exports; unknown balls throw at 1x.
	var multiplier: float = 1.0
	if ball >= 2 and ball <= 3:
		multiplier = 1.5 if ball == 2 else 2.0
	var odds: int = int((max_hp * 3 - foe_hp * 2) * int(info.get("catch_rate", 45)) / (max_hp * 3) * multiplier)
	return clampi(odds, 1, 255)


static func _gift_mon(data: GameData, events: Gen3EventData, species: int, level: int) -> Dictionary:
	var info: Dictionary = data.species(species)
	events.random.randi()
	var hp_iv: int = events.random.next() % 32
	var base_hp: int = int((info.get("stats", {}) as Dictionary).get("hp", 50))
	var moves: Array[int] = []
	for row: Dictionary in data.learnset(species):
		if int(row.get("level", 0)) <= level and int(row.get("move", 0)) > 0:
			moves.append(int(row["move"]))
			if moves.size() > 4:
				moves.pop_front()
	events.random.randi()
	return {"species": species, "nickname": String(info.get("name", "")),
		"level": level, "moves": moves, "egg": false,
		"hp": ((2 * base_hp + hp_iv) * level) / 100 + level + 10,
		"personality": (events.random.next() << 16) | events.random.next(), "ot_id": 0,
		"status": 0, "item": 0}
