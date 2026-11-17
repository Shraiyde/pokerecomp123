class_name Gen3BattleScreen
extends Control

## A battle the player fights: the ROM's opening (foe steps out, "Go!"),
## FIGHT with the lead mon's four moves, BAG with balls and usable
## medicine, POKéMON to switch (the switch costs the turn), RUN where the
## ROM allows it. Rounds run the resolver's damage math with the player's
## chosen move against the foe's best, HP bars track both sides, and the
## end (win, loss, catch, run) reports back through `finished`, carrying
## the outcome the script host's finish_* expects. Nuzlocke dead never
## enter, and a caught mon joins the party (or the PC when full).

signal finished(outcome: int)

const MENU: Array[String] = ["FIGHT", "BAG", "POKéMON", "RUN"]

var _data: GameData = null
var _events: Gen3EventData = null
var _foes: Array = []
var _foe_index: int = 0
var _foe: Dictionary = {}
var _allies: Array = []
var _ally_index: int = 0
var _ally: Dictionary = {}
var _trainer_name: String = ""
var _state: String = "intro"
var _menu_cursor: int = 0
var _move_cursor: int = 0
var _lines: Array[String] = []
var _text: Label = null
var _foe_bar: ProgressBar = null
var _ally_bar: ProgressBar = null
var _foe_label: Label = null
var _ally_label: Label = null
var _menu_label: Label = null
var _party_screen: Gen3PartyScreen = null
var _bag_screen: Gen3BagScreen = null
var _done: bool = false
var _link: Gen3CoopTransport = null
var _link_sent: Dictionary = {}
var _link_remote: Dictionary = {}
var _link_foe_hp: Dictionary = {}
var _safari: bool = false


static func open_wild(parent: Node, data: GameData, events: Gen3EventData, species: int, level: int, safari: bool = false) -> Gen3BattleScreen:
	var screen := Gen3BattleScreen.new()
	screen._data = data
	screen._events = events
	screen._foes = [{"species": species, "level": level}]
	screen._safari = safari
	if safari and events.safari_balls <= 0:
		events.safari_balls = 30 # A fresh visit's balls, as the ROM hands them out.
	parent.add_child(screen)
	return screen


static func open_link(parent: Node, data: GameData, events: Gen3EventData,
		transport: Gen3CoopTransport, peer_name: String, foes: Array) -> Gen3BattleScreen:
	var screen := Gen3BattleScreen.new()
	screen._data = data
	screen._events = events
	screen._trainer_name = peer_name
	screen._foes = foes
	screen._link = transport
	parent.add_child(screen)
	return screen


func _is_safari() -> bool:
	return _safari


static func open_trainer(parent: Node, data: GameData, events: Gen3EventData,
		trainer_name: String, foes: Array) -> Gen3BattleScreen:
	var screen := Gen3BattleScreen.new()
	screen._data = data
	screen._events = events
	screen._trainer_name = trainer_name
	screen._foes = foes
	parent.add_child(screen)
	return screen


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.06, 0.04, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	_foe_label = _label(body, 22)
	_foe_bar = _bar(body)
	_ally_label = _label(body, 22)
	_ally_bar = _bar(body)
	_text = _label(body, 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0, 120)
	_menu_label = _label(body, 22)
	if not _is_link():
		events.dex_mark(int(_foes[0].get("species", 0)), false)
	_next_foe()
	_push_ally(0)
	if _ally.is_empty():
		_finish(Gen3TrainerBattle.Outcome.LOST)
		return
	if _trainer_name.is_empty():
		_say("Wild %s appeared!" % _foe_name())
	else:
		_say("%s wants to battle!" % _trainer_name)
		_say("Go! %s!" % _ally_name())
	_state = "menu"
	_draw()


func _label(parent: Control, size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label


func _bar(parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 22)
	bar.show_percentage = false
	parent.add_child(bar)
	return bar


func _foe_name() -> String:
	return String(_data.species(int(_foe.get("species", 0))).get("name", "?"))


func _ally_name() -> String:
	return String(_ally.get("nickname", "?"))


func _say(line: String) -> void:
	_lines.append(line)
	while _lines.size() > 4:
		_lines.pop_front()


func _draw() -> void:
	_foe_label.text = "Foe %s  Lv%d" % [_foe_name(), int(_foe.get("level", 5))]
	_foe_bar.max_value = maxi(int(_foe.get("max_hp", 1)), 1)
	_foe_bar.value = maxi(int(_foe.get("hp", 0)), 0)
	_ally_label.text = "%s  Lv%d" % [_ally_name(), int(_ally.get("level", 5))]
	_ally_bar.max_value = maxi(int(_ally.get("max_hp", 1)), 1)
	_ally_bar.value = maxi(int(_ally.get("hp", 0)), 0)
	_text.text = "\n".join(_lines)
	if _state == "menu":
		_menu_label.text = "  ".join(_menu_items().map(
			func(item: String) -> String: return "[%s]" % item if _menu_items()[_menu_cursor] == item else item))
	elif _state == "moves":
		var moves: Array = _ally.get("moves", [])
		var rows: Array[String] = []
		for index: int in moves.size():
			var prefix: String = "> " if index == _move_cursor else "  "
			rows.append("%s%s" % [prefix, String(_data.move(int(moves[index])).get("name", "???"))])
		_menu_label.text = "\n".join(rows)
	else:
		_menu_label.text = ""


var _a_held: bool = false
var _b_held: bool = false


func _process(_delta: float) -> void:
	if _done:
		return
	if _is_link():
		_link.poll(_events)
		_drain_link_rounds()
		if not _link.connected():
			_say("%s disconnected." % _trainer_name)
			_finish(Gen3TrainerBattle.Outcome.WON)
			return
		if _party_screen != null or _bag_screen != null:
			return
		if not _link_sent.is_empty() and not _link_remote.is_empty() and _state == "link_wait":
			_resolve_link_round()
			return
	if _party_screen != null or _bag_screen != null:
		return
	var a_held: bool = PokeButton.held(PokeButton.A)
	if a_held and not _a_held:
		_press_a()
	_a_held = a_held
	var b_held: bool = PokeButton.held(PokeButton.B)
	if b_held and not _b_held:
		_press_b()
	_b_held = b_held


func _press_a() -> void:
	if _state == "menu":
		match _menu_items()[_menu_cursor]:
			"FIGHT":
				_state = "moves"
				_move_cursor = 0
			"BALL":
				_throw_safari_ball()
			"BAG":
				_open_bag()
			"POKéMON":
				_open_party()
			"RUN":
				_try_run()
	elif _state == "moves":
		var moves: Array = _ally.get("moves", [])
		var move_id: int = int(moves[_move_cursor]) if not moves.is_empty() else 0
		if _is_link():
			_link_act({"kind": "move", "move": move_id})
		else:
			_round(move_id)
	_draw()


func _press_b() -> void:
	if _state == "moves":
		_state = "menu"
		_draw()


func _menu_items() -> Array[String]:
	if _safari:
		return ["BALL", "RUN"]
	var items: Array[String] = []
	items.assign(MENU)
	return items


## The Safari Ball: the visit's own stock, the ROM's catch rate for
## the species, and RUN always walks in the park.
func _throw_safari_ball() -> void:
	if _events.safari_balls <= 0:
		_say("Out of Safari Balls!")
		_state = "menu"
		_draw()
		return
	_events.safari_balls -= 1
	var caught: Dictionary = Gen3CatchResolver.try_catch(_data, _events,
		int(_foe.get("species", 0)), int(_foe.get("level", 5)), int(_foe.get("hp", 0)), 23)
	if not caught.is_empty():
		_add_caught(caught)
		_finish(Gen3TrainerBattle.Outcome.CAUGHT)
		return
	_say("Oh no! It broke free!  (Balls: %d)" % _events.safari_balls)
	_state = "menu"
	_draw()


func _unhandled_input(event: InputEvent) -> void:
	if _state == "menu":
		if event.is_action_pressed(&"gen2_left"):
			_menu_cursor = posmod(_menu_cursor - 1, _menu_items().size())
			_draw()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"gen2_right"):
			_menu_cursor = (_menu_cursor + 1) % _menu_items().size()
			_draw()
			get_viewport().set_input_as_handled()
	elif _state == "moves":
		var moves: Array = _ally.get("moves", [])
		if event.is_action_pressed(&"gen2_up"):
			_move_cursor = posmod(_move_cursor - 1, maxi(moves.size(), 1))
			_draw()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"gen2_down"):
			_move_cursor = (_move_cursor + 1) % maxi(moves.size(), 1)
			_draw()
			get_viewport().set_input_as_handled()


func _next_foe() -> bool:
	while _foe_index < _foes.size():
		var row: Dictionary = _foes[_foe_index]
		_foe_index += 1
		if bool(row.get("egg", false)):
			continue
		var built: Dictionary = Gen3BattleResolver._combatant(_data, row)
		if not built.is_empty():
			built["link_i"] = int(row.get("i", -1))
			_foe = built
			return true
	return false


func _push_ally(index: int) -> void:
	_allies.clear()
	var party_index: int = 0
	for mon: Dictionary in _events.party:
		var row: int = party_index
		party_index += 1
		if bool(mon.get("egg", false)):
			continue
		if _events.nuzlocke and bool(mon.get("dead", false)):
			continue
		var built: Dictionary = Gen3BattleResolver._combatant(_data, mon)
		if not built.is_empty():
			built["party_ref"] = mon
			built["party_index"] = row
			_allies.append(built)
	_ally_index = clampi(index, 0, maxi(_allies.size() - 1, 0))
	_ally = _allies[_ally_index] if not _allies.is_empty() else {}


func _usable_ally_count() -> int:
	return _allies.size()


func _round(move_id: int) -> void:
	if _ally.is_empty() or _foe.is_empty():
		return
	var move: Dictionary = _data.move(move_id) if move_id > 0 else {}
	if move.is_empty() or int(move.get("power", 0)) <= 0:
		_say("%s has no usable move!" % _ally_name())
		_foe_turn()
		_after_round()
		return
	_say("%s used %s!" % [_ally_name(), String(move.get("name", ""))])
	if int(_ally.get("speed", 0)) >= int(_foe.get("speed", 0)):
		Gen3BattleResolver.strike(_data, _events, _ally, _foe, move)
		if int(_foe.get("hp", 0)) > 0:
			_say("Foe %s used %s!" % [_foe_name(), _foe_move_name()])
			Gen3BattleResolver.strike(_data, _events, _foe, _ally, _foe_move())
	else:
		_say("Foe %s used %s!" % [_foe_name(), _foe_move_name()])
		Gen3BattleResolver.strike(_data, _events, _foe, _ally, _foe_move())
		if int(_ally.get("hp", 0)) > 0:
			Gen3BattleResolver.strike(_data, _events, _ally, _foe, move)
	_after_round()


func _is_link() -> bool:
	return _link != null


## A link turn: the choice goes out with this party's HP, and the
## round runs once the peer's choice arrives.
func _link_act(choice: Dictionary) -> void:
	choice["hp"] = _party_hps()
	_link_sent = choice
	_link_remote = {}
	_link.send_link("round", choice)
	_state = "link_wait"
	_say("Waiting for %s..." % _trainer_name)
	_draw()


func _party_hps() -> Array:
	var out: Array = []
	for mon: Dictionary in _events.party:
		out.append(int(mon.get("hp", 0)))
	return out


func _drain_link_rounds() -> void:
	while not _link.inbox.is_empty():
		var msg: Dictionary = _link.inbox.pop_front()
		if String(msg.get("type", "")) == "round":
			_link_remote = msg
			_sync_foe_hp(msg)


## The peer's HP array keeps this side's record of their party, so a
## peer switch lands on the right HP on both phones.
func _sync_foe_hp(msg: Dictionary) -> void:
	var hps: Array = msg.get("hp", [])
	for index: int in hps.size():
		_link_foe_hp[index] = int(hps[index])


func _resolve_link_round() -> void:
	var mine: Dictionary = _link_sent
	var theirs: Dictionary = _link_remote
	_link_sent = {}
	_link_remote = {}
	if String(mine.get("kind", "")) == "forfeit" or String(theirs.get("kind", "")) == "forfeit":
		_say("You forfeit!" if String(mine.get("kind", "")) == "forfeit" else "%s forfeits!" % _trainer_name)
		_finish(Gen3TrainerBattle.Outcome.LOST if String(mine.get("kind", "")) == "forfeit" else Gen3TrainerBattle.Outcome.WON)
		return
	_apply_link_switch(mine, true)
	_apply_link_switch(theirs, false)
	var my_move: Dictionary = _data.move(int(mine.get("move", 0))) if String(mine.get("kind", "")) == "move" else {}
	var their_move: Dictionary = _data.move(int(theirs.get("move", 0))) if String(theirs.get("kind", "")) == "move" else {}
	if String(mine.get("kind", "")) == "item":
		_apply_link_item(mine, true)
	if String(theirs.get("kind", "")) == "item":
		_apply_link_item(theirs, false)
	if not my_move.is_empty() or not their_move.is_empty():
		if int(_ally.get("speed", 0)) >= int(_foe.get("speed", 0)):
			if not my_move.is_empty():
				_say("%s used %s!" % [_ally_name(), String(my_move.get("name", ""))])
				Gen3BattleResolver.strike_fixed(_data, _ally, _foe, my_move)
			if int(_foe.get("hp", 0)) > 0 and not their_move.is_empty():
				_say("Foe %s used %s!" % [_foe_name(), String(their_move.get("name", ""))])
				Gen3BattleResolver.strike_fixed(_data, _foe, _ally, their_move)
		else:
			if not their_move.is_empty():
				_say("Foe %s used %s!" % [_foe_name(), String(their_move.get("name", ""))])
				Gen3BattleResolver.strike_fixed(_data, _foe, _ally, their_move)
			if int(_ally.get("hp", 0)) > 0 and not my_move.is_empty():
				_say("%s used %s!" % [_ally_name(), String(my_move.get("name", ""))])
				Gen3BattleResolver.strike_fixed(_data, _ally, _foe, my_move)
	_after_link_round()


func _apply_link_switch(choice: Dictionary, own_side: bool) -> void:
	if String(choice.get("kind", "")) != "switch":
		return
	if own_side:
		_write_ally()
		_push_ally(int(choice.get("slot", 0)))
		_say("Come back! Go! %s!" % _ally_name())
	else:
		var slot: int = int(choice.get("slot", -1))
		for row: Variant in _foes:
			if int((row as Dictionary).get("i", -1)) == slot and not bool((row as Dictionary).get("egg", false)):
				_foe = Gen3BattleResolver._combatant(_data, row)
				_foe["link_i"] = slot
				_foe["hp"] = int(_link_foe_hp.get(slot, _foe.get("max_hp", 0)))
				_say("Foe sent out %s!" % _foe_name())
				break


func _apply_link_item(choice: Dictionary, own_side: bool) -> void:
	var item: int = int(choice.get("item", 0))
	if own_side:
		if _events.bag.remove(item, 1):
			var mon: Dictionary = _ally.get("party_ref", {})
			if apply_medicine(_data, _events, mon, item):
				_ally["hp"] = int(mon["hp"])
				_say("%s recovered HP!" % _ally_name())
	else:
		var mon: Dictionary = _foe.get("party_ref", {})
		if mon.is_empty():
			mon = {"hp": int(_foe.get("hp", 0)), "level": int(_foe.get("level", 5)),
				"species": int(_foe.get("species", 0)), "moves": (_foe.get("moves", []) as Array).duplicate()}
			_foe["party_ref"] = mon
		if apply_medicine(_data, _events, mon, item):
			_foe["hp"] = int(mon["hp"])


func _after_link_round() -> void:
	_write_ally()
	var foe_down: bool = int(_foe.get("hp", 0)) <= 0
	var ally_down: bool = int(_ally.get("hp", 0)) <= 0
	if foe_down:
		_say("Foe %s fainted!" % _foe_name())
		_link_foe_hp[int(_foe.get("link_i", -1))] = 0
		if not _next_link_foe():
			for built: Dictionary in _allies:
				if built.has("party_ref"):
					var mon: Dictionary = built["party_ref"]
					mon["hp"] = maxi(int(built.get("hp", 0)), 0)
			Gen3BattleResolver._grant_exp(_data, _events, _allies, _foes)
			_finish(Gen3TrainerBattle.Outcome.WON)
			return
		_say("Foe sent out %s!" % _foe_name())
	if ally_down:
		_say("%s fainted!" % _ally_name())
		_ally["party_ref"]["hp"] = 0
		if _events.nuzlocke:
			_ally["party_ref"]["dead"] = true
		_push_ally(_next_usable_ally())
		if _ally.is_empty():
			_finish(Gen3TrainerBattle.Outcome.LOST)
			return
		_say("Go! %s!" % _ally_name())
	_state = "menu"
	_draw()


func _next_link_foe() -> bool:
	for row: Variant in _foes:
		var index: int = int((row as Dictionary).get("i", -1))
		if bool((row as Dictionary).get("egg", false)):
			continue
		if _link_foe_hp.has(index) and int(_link_foe_hp[index]) <= 0:
			continue
		var built: Dictionary = Gen3BattleResolver._combatant(_data, row)
		if built.is_empty():
			continue
		built["link_i"] = index
		built["hp"] = int(_link_foe_hp.get(index, built.get("max_hp", 0)))
		if int(built["hp"]) <= 0:
			_link_foe_hp[index] = 0
			continue
		_foe = built
		return true
	return false


func _foe_move() -> Dictionary:
	return Gen3BattleResolver._best_move(_data, _foe, _ally)


func _foe_move_name() -> String:
	return String(_foe_move().get("name", ""))


func _foe_turn() -> void:
	_say("Foe %s used %s!" % [_foe_name(), _foe_move_name()])
	Gen3BattleResolver.strike(_data, _events, _foe, _ally, _foe_move())


func _after_round() -> void:
	_write_ally()
	var foe_down: bool = int(_foe.get("hp", 0)) <= 0
	var ally_down: bool = int(_ally.get("hp", 0)) <= 0
	if foe_down:
		_say("Foe %s fainted!" % _foe_name())
		if _next_foe():
			_say("Foe %s appeared!" % _foe_name())
		else:
			for built: Dictionary in _allies:
				if built.has("party_ref"):
					var mon: Dictionary = built["party_ref"]
					mon["hp"] = maxi(int(built.get("hp", 0)), 0)
			Gen3BattleResolver._grant_exp(_data, _events, _allies, _foes)
			_finish(Gen3TrainerBattle.Outcome.WON)
			return
	if ally_down:
		_say("%s fainted!" % _ally_name())
		_ally["party_ref"]["hp"] = 0
		if _events.nuzlocke:
			_ally["party_ref"]["dead"] = true
		_push_ally(_next_usable_ally())
		if _ally.is_empty():
			_finish(Gen3TrainerBattle.Outcome.LOST)
			return
		_say("Go! %s!" % _ally_name())
	_state = "menu"
	_draw()


func _next_usable_ally() -> int:
	for index: int in _allies.size():
		if int((_allies[index] as Dictionary).get("hp", 0)) > 0:
			return index
	return _allies.size()


func _write_ally() -> void:
	if _ally.has("party_ref"):
		var mon: Dictionary = _ally["party_ref"]
		mon["hp"] = maxi(int(_ally.get("hp", 0)), 0)


func _try_run() -> void:
	if _is_link():
		_say("You forfeit!")
		_link_act({"kind": "forfeit"})
		return
	if not _trainer_name.is_empty():
		_say("Can't escape!")
		_foe_turn()
		_after_round()
		return
	_say("Got away safely!")
	_finish(Gen3TrainerBattle.Outcome.RAN)


func _open_party() -> void:
	_party_screen = Gen3PartyScreen.new()
	_party_screen.setup(_data, _events, "switch")
	get_parent().add_child(_party_screen)
	_party_screen.chosen.connect(_on_party_chosen)
	_party_screen.cancelled.connect(_on_party_cancelled)


func _on_party_chosen(index: int) -> void:
	_party_screen.queue_free()
	_party_screen = null
	var target: int = -1
	for built_index: int in _allies.size():
		if int((_allies[built_index] as Dictionary)["party_index"]) == index:
			target = built_index
			break
	if target < 0 or target == _ally_index:
		_state = "menu"
		_draw()
		return
	_write_ally()
	_ally_index = target
	_ally = _allies[_ally_index]
	_say("Come back! Go! %s!" % _ally_name())
	if _is_link():
		_link_act({"kind": "switch", "slot": index})
		return
	_foe_turn() # The switch costs the turn, as in the ROM.
	_after_round()


func _on_party_cancelled() -> void:
	_party_screen.queue_free()
	_party_screen = null
	_state = "menu"
	_draw()


func _open_bag() -> void:
	_bag_screen = Gen3BagScreen.new()
	_bag_screen.setup(_data, _events.bag)
	get_parent().add_child(_bag_screen)
	_bag_screen.chosen.connect(_on_bag_chosen)
	_bag_screen.cancelled.connect(_on_bag_cancelled)


func _on_bag_chosen(item: int) -> void:
	_bag_screen.queue_free()
	_bag_screen = null
	if _is_link() and _is_ball(item):
		_say("Can't catch another trainer's Pokémon!")
		_state = "menu"
		_draw()
		return
	if _is_ball(item) and _trainer_name.is_empty():
		if _events.bag.remove(item, 1):
			var caught: Dictionary = Gen3CatchResolver.try_catch(_data, _events,
				int(_foe.get("species", 0)), int(_foe.get("level", 5)), int(_foe.get("hp", 0)), item)
			if not caught.is_empty():
				_add_caught(caught)
				_finish(Gen3TrainerBattle.Outcome.CAUGHT)
				return
			_say("Oh no! It broke free!")
			_foe_turn()
			_after_round()
			return
	elif _is_ball(item):
		_say("Can't catch a trainer's Pokémon!")
		_foe_turn()
		_after_round()
		return
	if _use_medicine(item):
		_foe_turn()
		_after_round()
		return
	_state = "menu"
	_draw()


func _on_bag_cancelled() -> void:
	_bag_screen.queue_free()
	_bag_screen = null
	_state = "menu"
	_draw()


func _is_ball(item: int) -> bool:
	return item >= 1 and item <= 27 # ITEM_POKE_BALL..ITEM_BEAST_BALL in the H&S table.


func _use_medicine(item: int) -> bool:
	if _is_link():
		_link_act({"kind": "item", "item": item})
		return true
	var mon: Dictionary = _ally.get("party_ref", {})
	if not apply_medicine(_data, _events, mon, item):
		_say("Can't use that now.")
		return false
	if not _events.bag.remove(item, 1):
		return false
	_say("%s recovered HP!" % _ally_name())
	_ally["hp"] = int(mon["hp"])
	return true


## Shared field/battle medicine: returns false with nothing consumed
## when the item cannot help this mon (wrong target, full HP).
static func apply_medicine(data: GameData, events: Gen3EventData, mon: Dictionary, item: int) -> bool:
	var kind: Dictionary = medicine_kind_for(data, item)
	if String(kind.get("kind", "")) == "none":
		return false
	var events_ref: Gen3EventData = events
	var fainted: bool = int(mon.get("hp", 0)) <= 0
	if String(kind["kind"]) == "revive":
		if not fainted or (bool(mon.get("dead", false)) and events_ref.nuzlocke):
			return false # The nuzlocke dead stay dead; revives cannot reach them.
	else:
		if fainted or int(mon.get("hp", 0)) >= Gen3BattleResolver.max_hp(data, mon):
			return false
	var full: int = Gen3BattleResolver.max_hp(data, mon)
	match String(kind["kind"]):
		"full":
			mon["hp"] = full
		"half":
			mon["hp"] = mini(int(mon.get("hp", 0)) + full / 2, full)
		"revive":
			mon["hp"] = full if bool(kind.get("full", false)) else full / 2
		_:
			mon["hp"] = mini(int(mon.get("hp", 0)) + int(kind.get("amount", 0)), full)
	mon.erase("status")
	if String(kind["kind"]) == "revive":
		mon.erase("dead")
	return true


## The ROM's own numbers, read from its own description text: full and
## half restores, revives (half unless the text promises full), and the
## flat "by N" amounts. Anything else is not field medicine.
static func medicine_kind_for(data: GameData, item: int) -> Dictionary:
	var text: String = String(_data.item(item).get("description", "")).to_upper()
	if text.contains("REVIVE"):
		return {"kind": "revive", "full": text.contains("FULLY") or text.contains("FULL HP")}
	if text.contains("FULLY") or text.contains("FULL HP"):
		return {"kind": "full"}
	if text.contains("HALF"):
		return {"kind": "half"}
	for word: String in text.split(" "):
		if word.is_valid_int() and word.to_int() > 0:
			return {"kind": "amount", "amount": word.to_int()}
	return {"kind": "none"}


func _add_caught(caught: Dictionary) -> void:
	_say("Gotcha! %s was caught!" % String(caught.get("nickname", "?")))
	caught["hp"] = int(caught.get("hp", 0))
	_events.dex_mark(int(caught.get("species", 0)), true)
	if _events.party.size() < 6:
		_events.party.append(caught)
	else:
		_events.pc_boxes.append(caught) # Full party: the ROM sends it to the Box.


func _finish(outcome: int) -> void:
	if _done:
		return
	_done = true
	finished.emit(outcome)
