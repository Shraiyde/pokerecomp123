class_name Gen3PokedexScreen
extends Control

## The Pokédex: every national number in order, seen ones named and
## selectable, unseen ones blank. A on a seen entry shows its detail
## (number, name, types, height, weight); B steps back out. Seen and
## caught come from the field (`dex_mark` on encounters and catches)
## and ride the save, so the count survives reloads.

signal closed()

var _data: GameData = null
var _events: Gen3EventData = null
var _list: ItemList = null
var _detail: Label = null


func setup(data: GameData, events: Gen3EventData) -> void:
	_data = data
	_events = events


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.75, 0.10, 0.12, 1.0)
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
	var head := Label.new()
	head.text = "POKéDEX   seen %d   caught %d" % [_events.dex_seen.size(), _events.dex_caught.size()]
	head.add_theme_font_size_override("font_size", 24)
	body.add_child(head)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 420)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	body.add_child(_list)
	_detail = Label.new()
	_detail.add_theme_font_size_override("font_size", 22)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_detail)
	var hint := Label.new()
	hint.text = "A: details    B: close"
	hint.add_theme_font_size_override("font_size", 18)
	body.add_child(hint)
	_fill()


func _fill() -> void:
	_list.clear()
	for number: int in range(1, _data.species_count() + 1):
		if number in _events.dex_caught:
			_list.add_item("%03d  %s  [caught]" % [number, String(_data.species(number).get("name", ""))])
		elif number in _events.dex_seen:
			_list.add_item("%03d  %s" % [number, String(_data.species(number).get("name", ""))])
		else:
			_list.add_item("%03d  -----" % number)


func _on_selected(index: int) -> void:
	_show_detail(index + 1)


func _show_detail(number: int) -> void:
	if not number in _events.dex_seen:
		_detail.text = "No data on #%03d yet." % number
		return
	var info: Dictionary = _data.species(number)
	var entry: Dictionary = _data.dex_entry(number)
	var types: Array = info.get("types", [])
	_detail.text = "#%03d %s\nType: %s\nHT %s   WT %s\n%s" % [
		number, String(info.get("name", "")),
		"/".join(types.map(func(t: Variant) -> String: return String(_data.type_name(int(t))))),
		String(entry.get("height", "?")), String(entry.get("weight", "?")),
		String(entry.get("category", ""))]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		closed.emit()
		get_viewport().set_input_as_handled()
