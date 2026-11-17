class_name Gen3PartyScreen
extends Control

## The party list: six rows of name, level and HP bar, dead and egg rows
## marked and unusable. A picks a row; what that means is the caller's
## `purpose`: "switch" takes a usable battler, "item" takes any
## non-egg mon to use something on, "view" only shows the summary
## below. B always steps back out.

signal chosen(index: int)
signal fly_requested(index: int)
signal cancelled

var _events: Gen3EventData = null
var _data: GameData = null
var _purpose: String = "view"
var _rows: VBoxContainer = null
var _detail: Label = null
var _cursor: int = 0
var _summary_index: int = -1


func setup(data: GameData, events: Gen3EventData, purpose: String = "view") -> void:
	_data = data
	_events = events
	_purpose = purpose


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.23, 0.10, 1.0)
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
	body.add_theme_constant_override("separation", 6)
	margin.add_child(body)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	body.add_child(_rows)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 20)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_detail)
	_fill()


func _fill() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	for index: int in _events.party.size():
		_rows.add_child(_row(index))
	_show_summary(mini(_cursor, _events.party.size() - 1))


func _row(index: int) -> Control:
	var mon: Dictionary = _events.party[index]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	var dead: bool = bool(mon.get("dead", false))
	var egg: bool = bool(mon.get("egg", false))
	label.text = "%s  Lv%d%s" % [String(mon.get("nickname", "?")), int(mon.get("level", 5)),
		"  [dead]" if dead else ("  [egg]" if egg else "")]
	label.add_theme_font_size_override("font_size", 22)
	label.custom_minimum_size = Vector2(300, 0)
	row.add_child(label)
	if not egg:
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(180, 20)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = Gen3BattleResolver.max_hp(_data, mon)
		bar.value = int(mon.get("hp", 0))
		row.add_child(bar)
	if index == _cursor:
		var frame := ReferenceRect.new()
		frame.border_color = Color(1, 1, 1)
		frame.border_width = 2.0
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(frame)
	return row


func _show_summary(index: int) -> void:
	if index < 0 or index >= _events.party.size():
		_detail.text = ""
		return
	var mon: Dictionary = _events.party[index]
	var info: Dictionary = _data.species(int(mon.get("species", 0)))
	_detail.text = "%s  Lv%d  HP %d/%d\n%s" % [String(mon.get("nickname", "?")),
		int(mon.get("level", 5)), int(mon.get("hp", 0)),
		Gen3BattleResolver.max_hp(_data, mon),
		", ".join((mon.get("moves", []) as Array).map(
			func(move_id: Variant) -> String: return String(_data.move(int(move_id)).get("name", ""))))]


func _usable(index: int) -> bool:
	if index < 0 or index >= _events.party.size():
		return false
	var mon: Dictionary = _events.party[index]
	if bool(mon.get("egg", false)):
		return false
	if _purpose == "item":
		return true # Revives need the fainted; the item decides validity.
	if _purpose == "trade":
		return not bool(mon.get("dead", false)) and int(mon.get("hp", 0)) > 0
	if int(mon.get("hp", 0)) <= 0:
		return false
	if bool(mon.get("dead", false)):
		return false
	return true


func _knows_fly(index: int) -> bool:
	if index < 0 or index >= _events.party.size():
		return false
	for move_id: Variant in (_events.party[index].get("moves", []) as Array):
		if String(_data.move(int(move_id)).get("name", "")) == "FLY":
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_a"):
		if _purpose == "view" and _summary_index == _cursor and _knows_fly(_cursor):
			fly_requested.emit(_cursor)
		elif _purpose == "view" or not _usable(_cursor):
			_summary_index = _cursor
			_show_summary(_cursor)
		else:
			chosen.emit(_cursor)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_up"):
		_cursor = posmod(_cursor - 1, _events.party.size())
		_fill()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_down"):
		_cursor = (_cursor + 1) % _events.party.size()
		_fill()
		get_viewport().set_input_as_handled()
