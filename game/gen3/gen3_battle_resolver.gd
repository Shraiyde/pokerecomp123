class_name Gen3BattleResolver
extends RefCounted

## Battle resolution without a battle screen: the cartridge's damage
## math (`CalculateMoveDamage`) run head-to-head until one side is out
## of usable mons. Stats come from the imported species/move/trainer
## tables, HP loss is written back to the player's party, and the
## outcome is the ROM's — so a stronger wild mon or trainer can now
## actually white the player out, which is what the nuzlocke death rule
## and the script's beaten/white-out branches have always waited on.
## Experience and level-ups are not awarded yet.

const MAX_ROUNDS: int = 500


static func resolve_wild(data: GameData, events: Gen3EventData, species: int, level: int) -> int:
	return resolve(data, events, [{"species": species, "level": level}])


static func resolve(data: GameData, events: Gen3EventData, enemies: Array) -> int:
	var foes: Array = []
	for enemy: Variant in enemies:
		if enemy is Dictionary:
			var built: Dictionary = _combatant(data, enemy as Dictionary)
			if not built.is_empty():
				foes.append(built)
	if foes.is_empty() or events.party.is_empty():
		return Gen3TrainerBattle.Outcome.WON
	var allies: Array = []
	for mon: Dictionary in events.party:
		if bool(mon.get("egg", false)):
			continue
		if events.nuzlocke and bool(mon.get("dead", false)):
			continue # The dead do not battle again.
		var built: Dictionary = _combatant(data, mon)
		if not built.is_empty():
			built["party_ref"] = mon
			built["nuzlocke"] = events.nuzlocke
			allies.append(built)
	if allies.is_empty():
		return Gen3TrainerBattle.Outcome.LOST
	var ally_index: int = 0
	var foe_index: int = 0
	var rounds: int = 0
	while ally_index < allies.size() and foe_index < foes.size() and rounds < MAX_ROUNDS:
		rounds += 1
		var ally: Dictionary = allies[ally_index]
		var foe: Dictionary = foes[foe_index]
		if int(ally["speed"]) >= int(foe["speed"]):
			_hit(data, events, ally, foe)
			if int(foe["hp"]) > 0:
				_hit(data, events, foe, ally)
		else:
			_hit(data, events, foe, ally)
			if int(ally["hp"]) > 0:
				_hit(data, events, ally, foe)
		if int(foe["hp"]) <= 0:
			foe_index += 1
		if int(ally["hp"]) <= 0:
			_write_back(ally)
			ally_index += 1
	for built: Dictionary in allies:
		_write_back(built)
	if foe_index < foes.size():
		return Gen3TrainerBattle.Outcome.LOST
	_grant_exp(data, events, allies, foes)
	return Gen3TrainerBattle.Outcome.WON


## EXP like the ROM awards it: every fainted foe's base EXP at its
## level, split across the party that fought, then level-ups on the six
## ROM growth curves with level-up moves learned as they come.
static func _grant_exp(data: GameData, events: Gen3EventData, allies: Array, foes: Array) -> void:
	var fought: Array = []
	for built: Dictionary in allies:
		if built.has("party_ref"):
			fought.append(built["party_ref"])
	if fought.is_empty():
		return
	for foe: Dictionary in foes:
		var total: int = int(data.species(int(foe["species"])).get("base_exp", 0)) * int(foe["level"]) / 7
		for mon: Dictionary in fought:
			var share: int = total / fought.size()
			var curve: int = int(data.species(int(mon["species"])).get("growth_rate", 0))
			var exp: int = int(mon.get("exp", _curve_exp(curve, int(mon["level"]))))
			exp += share
			var level: int = int(mon["level"])
			while level < 100 and exp >= _curve_exp(curve, level + 1):
				level += 1
				_learn_level_moves(data, mon, level)
			mon["level"] = level
			mon["exp"] = exp


## Cumulative EXP for [param level] on a growth curve, exactly the ROM's
## six formulas (0 medium-fast through 5 slow).
static func _curve_exp(curve: int, level: int) -> int:
	var n: int = maxi(level, 1)
	match curve:
		1: # Erratic.
			if n <= 50:
				return n * n * n * (100 - n) / 50
			if n <= 68:
				return n * n * n * (150 - n) / 100
			if n <= 98:
				return n * n * n * ((1911 - 10 * n) / 3) / 500
			return n * n * n * (160 - n) / 100
		2: # Fluctuating.
			if n <= 15:
				return n * n * n * ((n + 73) / 24) / 50
			if n <= 36:
				return n * n * n * (n + 14) / 50
			return n * n * n * (n / 2 + 32) / 50
		3: # Medium-slow.
			return n * n * n * 6 / 5 - 15 * n * n + 100 * n - 140
		4: # Fast.
			return n * n * n * 4 / 5
		5: # Slow.
			return n * n * n * 5 / 4
	return n * n * n # Medium-fast.


static func _learn_level_moves(data: GameData, mon: Dictionary, level: int) -> void:
	var moves: Array = (mon.get("moves", []) as Array).duplicate()
	for learned: Dictionary in data.learnset(int(mon["species"])):
		if int(learned.get("level", 0)) != level or int(learned.get("move", 0)) <= 0:
			continue
		if int(learned["move"]) in moves:
			continue
		moves.append(int(learned["move"]))
		while moves.size() > 4:
			moves.pop_front()
	mon["moves"] = moves


## A party row's full HP at its level, for heals.
static func max_hp(data: GameData, row: Dictionary) -> int:
	var built: Dictionary = _combatant(data, row)
	return int(built.get("max_hp", 0))


static func _write_back(built: Dictionary) -> void:
	if not built.has("party_ref"):
		return
	var mon: Dictionary = built["party_ref"]
	mon["hp"] = maxi(int(built["hp"]), 0)
	if int(built["hp"]) <= 0 and bool(built.get("nuzlocke", false)):
		mon["dead"] = true # Fainted is dead only under nuzlocke rules.


## One battler from a party/wild/trainer row: computed stats at its
## level (IV 15 where the row carries none), its current HP, and the
## best damaging move it knows.
static func _combatant(data: GameData, row: Dictionary) -> Dictionary:
	var species: int = int(row.get("species", 0))
	var level: int = clampi(int(row.get("level", 5)), 1, 100)
	var info: Dictionary = data.species(species)
	if info.is_empty():
		return {}
	var base: Dictionary = info.get("stats", {})
	var iv: int = int(row.get("iv", 15)) & 31
	var max_hp: int = ((2 * int(base.get("hp", 50)) + iv) * level) / 100 + level + 10
	var hp: int = int(row.get("hp", max_hp)) if row.has("hp") else max_hp
	var moves: Array = row.get("moves", [])
	if moves.is_empty():
		for learned: Dictionary in data.learnset(species):
			if int(learned.get("level", 0)) <= level and int(learned.get("move", 0)) > 0:
				moves.append(int(learned["move"]))
				if moves.size() > 4:
					moves.pop_front()
	return {
		"species": species, "level": level, "hp": hp, "max_hp": max_hp,
		"attack": ((2 * int(base.get("attack", 50)) + iv) * level) / 100 + 5,
		"defense": ((2 * int(base.get("defense", 50)) + iv) * level) / 100 + 5,
		"sp_attack": ((2 * int(base.get("sp_attack", 50)) + iv) * level) / 100 + 5,
		"sp_defense": ((2 * int(base.get("sp_defense", 50)) + iv) * level) / 100 + 5,
		"speed": ((2 * int(base.get("speed", 50)) + iv) * level) / 100 + 5,
		"types": info.get("types", [0, 0]), "moves": moves,
	}


## One attack with a chosen move: the player-facing half of a round.
## The battle screen drives rounds through this; the auto path uses
## [_hit] (best move) for both sides.
static func strike(data: GameData, events: Gen3EventData, attacker: Dictionary, defender: Dictionary, move: Dictionary) -> void:
	if move.is_empty():
		return
	_apply_hit(data, attacker, defender, move, events.random.randi_range(85, 100))


## The link-battle strike: the ROM's math with the damage roll fixed,
## so both phones compute the same round from the same exchanged
## choices without sharing RNG state.
static func strike_fixed(data: GameData, attacker: Dictionary, defender: Dictionary, move: Dictionary) -> void:
	if move.is_empty():
		return
	_apply_hit(data, attacker, defender, move, 92)


static func _apply_hit(data: GameData, attacker: Dictionary, defender: Dictionary, move: Dictionary, roll: int) -> void:
	var physical: bool = int(move.get("category", 0)) != 1
	var atk: int = int(attacker["attack"] if physical else attacker["sp_attack"])
	var def: int = maxi(int(defender["defense"] if physical else defender["sp_defense"]), 1)
	var damage: int = ((2 * int(attacker["level"]) / 5 + 2) * int(move["power"]) * atk / def) / 50 + 2
	if int(move.get("type", 0)) in (attacker["types"] as Array):
		damage = damage * 3 / 2 # STAB.
	for defending_type: Variant in defender["types"]:
		damage = damage * data.type_matchup(int(move.get("type", 0)), int(defending_type)) / 10
	damage = damage * roll / 100
	defender["hp"] = int(defender["hp"]) - maxi(damage, 0)


static func _hit(data: GameData, events: Gen3EventData, attacker: Dictionary, defender: Dictionary) -> void:
	var move: Dictionary = _best_move(data, attacker, defender)
	if move.is_empty():
		return
	strike(data, events, attacker, defender, move)


static func _best_move(data: GameData, attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -1
	for move_id: Variant in attacker["moves"]:
		var move: Dictionary = data.move(int(move_id))
		if move.is_empty() or int(move.get("power", 0)) <= 0:
			continue
		var score: int = int(move["power"])
		for defending_type: Variant in defender["types"]:
			score = score * data.type_matchup(int(move.get("type", 0)), int(defending_type)) / 10
		if int(move.get("type", 0)) in (attacker["types"] as Array):
			score = score * 3 / 2
		if score > best_score:
			best_score = score
			best = move
	if best.is_empty():
		return {"power": 40, "type": 0, "category": 0} # Struggle, when nothing damaging is known.
	return best
