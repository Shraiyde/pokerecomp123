class_name Gen2NetworkLinkScreen
extends Control

## Host or join a network link session: one player hosts and the other joins
## with the four-digit room code, and the broker relays the cable. Once the
## peer is in, the player closes this and walks to the cable club, where the
## trade and battle screens run on the network transport exactly as they did
## on a save slot. The transport stays installed after this closes; LEAVE
## disconnects it and hands the cable back to the save slots.

signal closed()

var _world: Gen2WorldAPI = null
var _save: Gen2SaveData = null
var _transport: Gen2NetworkLinkTransport = null
var _title: Label = null
var _status: Label = null
var _code_label: Label = null
var _code_input: LineEdit = null
var _host_button: Button = null
var _join_button: Button = null
var _leave_button: Button = null
var _close_button: Button = null


func set_context(world: Gen2WorldAPI, save: Gen2SaveData) -> void:
	_world = world
	_save = save


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = Vector2(Gen2Screen.WIDTH, Gen2Screen.HEIGHT)
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override(
		"panel", _panel_stylebox(Color(0.08, 0.08, 0.12, 0.96))
	)
	add_child(panel)
	var body := VBoxContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_theme_constant_override("separation", 10)
	body.add_theme_constant_override("margin_left", 16)
	body.add_theme_constant_override("margin_right", 16)
	body.add_theme_constant_override("margin_top", 12)
	body.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(body)
	_title = _label(body, "LINK", 28)
	_status = _label(body, "Host a room, or join one with its code.", 14)
	_code_label = _label(body, "", 24)
	_code_label.visible = false
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	body.add_child(join_row)
	_code_input = LineEdit.new()
	_code_input.placeholder_text = "Room code"
	_code_input.max_length = 4
	_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_input.virtual_keyboard_enabled = true
	join_row.add_child(_code_input)
	_join_button = _button(join_row, "JOIN", _on_join_pressed)
	_host_button = _button(body, "HOST", _on_host_pressed)
	_leave_button = _button(body, "LEAVE", _on_leave_pressed)
	_leave_button.visible = false
	_close_button = _button(body, "CLOSE", _on_close_pressed)


func _process(_delta: float) -> void:
	if _transport == null:
		return
	_transport.poll()
	if _transport.connected():
		var peer_name: String = String(_transport.peer.get("name", ""))
		_status.text = "Connected to %s." % peer_name if not peer_name.is_empty() \
			else "Connected."
		_host_button.visible = false
		_join_button.visible = false
		_code_input.editable = false
		_leave_button.visible = true
	elif _transport.room_code.is_empty():
		_status.text = "Host a room, or join one with its code."
	else:
		_status.text = "Waiting for the other player..."
		_leave_button.visible = true


func _local_peer() -> Dictionary:
	if _save == null:
		return {}
	return Gen2LinkTransport.peer_from_save(
		_save, Gen2LinkSession.CABLECLUBROOM_NULL
	)


func _on_host_pressed() -> void:
	if _transport != null:
		return
	var transport := Gen2NetworkLinkTransport.host(_local_peer())
	_install(transport)
	_code_label.text = "ROOM CODE: %s" % transport.room_code
	_code_label.visible = true
	_status.text = "Waiting for the other player..."
	_host_button.visible = false
	_join_button.visible = false
	_code_input.editable = false
	_leave_button.visible = true


func _on_join_pressed() -> void:
	if _transport != null:
		return
	var code: String = _code_input.text.strip_edges()
	if code.length() != 4 or not code.is_valid_int():
		_status.text = "Enter the four-digit room code."
		return
	var transport := Gen2NetworkLinkTransport.join(code, _local_peer())
	_install(transport)
	_code_label.text = "ROOM: %s" % transport.room_code
	_code_label.visible = true
	_status.text = "Joining room %s..." % transport.room_code
	_host_button.visible = false
	_join_button.visible = false
	_code_input.editable = false
	_leave_button.visible = true


func _on_leave_pressed() -> void:
	if _transport != null:
		_transport.close()
		_transport = null
	if _world != null and _world.state != null:
		_world.state.set_link_transport(null)
	_code_label.visible = false
	_code_input.editable = true
	_code_input.text = ""
	_status.text = "Host a room, or join one with its code."
	_host_button.visible = true
	_join_button.visible = true
	_leave_button.visible = false


func _on_close_pressed() -> void:
	closed.emit()


func _install(transport: Gen2NetworkLinkTransport) -> void:
	_transport = transport
	_transport.start()
	if _world != null and _world.state != null:
		_world.state.set_link_transport(_transport)


func _label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	parent.add_child(label)
	return label


func _button(parent: Control, text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


func _panel_stylebox(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(6)
	return box
