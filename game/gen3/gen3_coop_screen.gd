class_name Gen3CoopScreen
extends Control

## Host or join a co-op game: one player hosts and shows the four-digit
## PIN, the other types it in and joins. Once the peer is in, CLOSE
## returns to the game and the story syncs behind the field; LEAVE ends
## the session. The transport outlives this screen on the world screen,
## which polls it every frame.

signal closed()

var transport: Gen3CoopTransport = null

var _events: Gen3EventData = null
var _data: GameData = null
var _freeze: Callable = Callable()
var _unfreeze: Callable = Callable()
var _battle_screen: Gen3BattleScreen = null
var _party_screen: Gen3PartyScreen = null
var _trade_offer: Dictionary = {}
var _trade_mine: int = -1
var _challenge: Dictionary = {}


## The link session needs the field's events (party, name), and
## callables that freeze the field while a link battle or trade runs
## and give it back after.
func open(data: GameData, events: Gen3EventData, freeze: Callable, unfreeze: Callable) -> void:
	_data = data
	_events = events
	_freeze = freeze
	_unfreeze = unfreeze

var _status: Label = null
var _code_label: Label = null
var _code_input: LineEdit = null
var _host_button: Button = null
var _join_button: Button = null
var _battle_button: Button = null
var _trade_button: Button = null
var _leave_button: Button = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	_status = _label(body, "Host a game, or join one with its PIN.", 20)
	_code_label = _label(body, "", 30)
	_code_label.visible = false
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	body.add_child(join_row)
	_code_input = LineEdit.new()
	_code_input.placeholder_text = "PIN"
	_code_input.max_length = 4
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_input.virtual_keyboard_enabled = true
	join_row.add_child(_code_input)
	_join_button = _button(join_row, "JOIN", _on_join_pressed)
	_host_button = _button(body, "HOST", _on_host_pressed)
	_battle_button = _button(body, "BATTLE", _on_battle_pressed)
	_trade_button = _button(body, "TRADE", _on_trade_pressed)
	_battle_button.visible = false
	_trade_button.visible = false
	_leave_button = _button(body, "LEAVE", _on_leave_pressed)
	_leave_button.visible = false
	_button(body, "CLOSE", func() -> void: closed.emit())


func _process(_delta: float) -> void:
	if transport == null:
		_status.text = "Host a game, or join one with its PIN."
		return
	_drain_inbox()
	if transport.connected():
		_battle_button.visible = _battle_screen == null
		_trade_button.visible = _battle_screen == null
		if _battle_screen == null and _trade_offer.is_empty() and _challenge.is_empty():
			_status.text = "Playing with %s." % transport.peer_name \
				if not transport.peer_name.is_empty() else "Connected."
		_leave_button.visible = true
	elif transport.room_code.is_empty():
		_status.text = "Host a game, or join one with its PIN."
	else:
		_status.text = "Waiting for the other player..."
		_leave_button.visible = true


func _on_host_pressed() -> void:
	if transport != null:
		return
	transport = Gen3CoopTransport.host()
	transport.start()
	_code_label.text = "PIN: %s" % transport.room_code
	_code_label.visible = true
	_host_button.visible = false
	_join_button.visible = false
	_code_input.editable = false
	_leave_button.visible = true


func _on_join_pressed() -> void:
	if transport != null:
		return
	var code: String = _code_input.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_status.text = "Enter the four-digit PIN."
		return
	transport = Gen3CoopTransport.join(code)
	transport.start()
	_code_label.text = "PIN: %s" % transport.room_code
	_code_label.visible = true
	_host_button.visible = false
	_join_button.visible = false
	_code_input.editable = false
	_leave_button.visible = true


## Incoming challenges, answers and trade offers, oldest first.
func _drain_inbox() -> void:
	var kept: Array = []
	while not transport.inbox.is_empty():
		var msg: Dictionary = transport.inbox.pop_front()
		if String(msg.get("type", "")) == "round" and _battle_screen != null:
			kept.append(msg) # The link battle consumes its own rounds.
			continue
		_handle_link(msg)
	transport.inbox = kept + transport.inbox


func _handle_link(msg: Dictionary) -> void:
	match String(msg.get("type", "")):
		"battle":
			_challenge = msg
			_status.text = "%s wants to battle! A accepts, B declines." % String(msg.get("name", "???"))
		"battle_accept":
			_start_link_battle(msg)
		"battle_decline":
			_status.text = "%s declined." % transport.peer_name
		"trade":
			_trade_offer = msg
			_status.text = "%s offers %s! A picks yours, B declines." % [transport.peer_name, String(msg.get("nickname", "?"))]
		"trade_accept":
			if _trade_mine >= 0 and _trade_mine < _events.party.size():
				_do_trade_swap(_trade_mine, msg)
		"trade_decline":
			_status.text = "%s declined." % transport.peer_name
			_trade_offer = {}
			_trade_mine = -1


func _unhandled_input(event: InputEvent) -> void:
	if _battle_screen != null:
		return
	if not _challenge.is_empty():
		if event.is_action_pressed(&"gen2_a"):
			_accept_battle()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"gen2_b"):
			transport.send_link("battle_decline", {})
			_challenge = {}
			get_viewport().set_input_as_handled()
	elif not _trade_offer.is_empty():
		if event.is_action_pressed(&"gen2_a"):
			_open_trade_picker()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"gen2_b"):
			transport.send_link("trade_decline", {})
			_trade_offer = {}
			get_viewport().set_input_as_handled()


func _on_battle_pressed() -> void:
	if transport == null or not transport.connected() or _events == null:
		return
	transport.send_link("battle", {"name": _events.player_name,
		"party": Gen3CoopTransport.compact_party(_events.party)})
	_status.text = "Challenge sent..."


func _accept_battle() -> void:
	var foes: Array = _challenge.get("party", [])
	var peer: String = String(_challenge.get("name", ""))
	_challenge = {}
	transport.send_link("battle_accept", {"name": _events.player_name,
		"party": Gen3CoopTransport.compact_party(_events.party)})
	_open_link_battle(peer, foes, false)


func _start_link_battle(msg: Dictionary) -> void:
	_open_link_battle(String(msg.get("name", "")), msg.get("party", []), true)


func _open_link_battle(peer_name: String, foes: Array, is_challenger: bool) -> void:
	if _battle_screen != null or _events == null:
		return
	if _freeze.is_valid():
		_freeze.call()
	_battle_button.visible = false
	_trade_button.visible = false
	_battle_screen = Gen3BattleScreen.open_link(get_parent(), _data, _events,
		transport, peer_name, foes, _events.player_name)
	_battle_screen.finished.connect(_on_link_battle_finished)


func _on_link_battle_finished(_outcome: int) -> void:
	if _battle_screen != null:
		_battle_screen.queue_free()
		_battle_screen = null
	if _unfreeze.is_valid():
		_unfreeze.call()


func _on_trade_pressed() -> void:
	if transport == null or not transport.connected() or _events == null:
		return
	_open_trade_picker()


func _open_trade_picker() -> void:
	if _party_screen != null:
		return
	_party_screen = Gen3PartyScreen.new()
	_party_screen.setup(_data, _events, "trade")
	get_parent().add_child(_party_screen)
	_party_screen.chosen.connect(_on_trade_chosen)
	_party_screen.cancelled.connect(_on_trade_cancelled)


func _on_trade_chosen(index: int) -> void:
	var mon: Dictionary = _events.party[index]
	if _trade_offer.is_empty():
		_trade_mine = index
		transport.send_link("trade", _trade_mon(mon))
		_status.text = "Offer sent: %s. Waiting..." % String(mon.get("nickname", "?"))
	else:
		transport.send_link("trade_accept", _trade_mon(mon))
		_do_trade_swap(index, _trade_offer)
	_close_trade_picker()


func _on_trade_cancelled() -> void:
	if not _trade_offer.is_empty():
		transport.send_link("trade_decline", {})
		_trade_offer = {}
	_close_trade_picker()


func _close_trade_picker() -> void:
	if _party_screen != null:
		_party_screen.queue_free()
		_party_screen = null


func _trade_mon(mon: Dictionary) -> Dictionary:
	return {"nickname": String(mon.get("nickname", "?")), "species": int(mon.get("species", 0)),
		"level": int(mon.get("level", 5)), "moves": (mon.get("moves", []) as Array).duplicate(),
		"hp": int(mon.get("hp", 0)), "personality": int(mon.get("personality", 0)),
		"ot_id": int(mon.get("ot_id", 0)), "item": int(mon.get("item", 0))}


func _do_trade_swap(my_index: int, their: Dictionary) -> void:
	_events.party[my_index] = _events.party[my_index].duplicate()
	var mine: Dictionary = _events.party[my_index]
	_events.party[my_index] = {"species": int(their.get("species", 0)),
		"nickname": String(their.get("nickname", "?")), "level": int(their.get("level", 5)),
		"moves": (their.get("moves", []) as Array).duplicate(), "egg": false,
		"hp": Gen3BattleResolver.max_hp(_data, their), "personality": int(their.get("personality", 0)),
		"ot_id": int(their.get("ot_id", 0)), "status": 0, "item": int(their.get("item", 0))}
	_status.text = "Traded %s away." % String(mine.get("nickname", "?"))
	_events.dex_mark(int(their.get("species", 0)), true)
	_trade_offer = {}
	_trade_mine = -1


func _on_leave_pressed() -> void:
	if transport != null:
		transport.close()
		transport = null
	_code_label.visible = false
	_code_input.editable = true
	_code_input.text = ""
	_host_button.visible = true
	_join_button.visible = true
	_leave_button.visible = false


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button
