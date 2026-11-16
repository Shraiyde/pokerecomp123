class_name Gen3CoopScreen
extends Control

## Host or join a co-op game: one player hosts and shows the four-digit
## PIN, the other types it in and joins. Once the peer is in, CLOSE
## returns to the game and the story syncs behind the field; LEAVE ends
## the session. The transport outlives this screen on the world screen,
## which polls it every frame.

signal closed()

var transport: Gen3CoopTransport = null

var _status: Label = null
var _code_label: Label = null
var _code_input: LineEdit = null
var _host_button: Button = null
var _join_button: Button = null
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
	_leave_button = _button(body, "LEAVE", _on_leave_pressed)
	_leave_button.visible = false
	_button(body, "CLOSE", func() -> void: closed.emit())


func _process(_delta: float) -> void:
	if transport == null:
		_status.text = "Host a game, or join one with its PIN."
		return
	if transport.connected():
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
