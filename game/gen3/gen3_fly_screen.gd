class_name Gen3FlyScreen
extends Control

## Fly destinations: visited map sections with town-like names (routes,
## caves and roadside stops never take a landing). A flies there, B
## steps back out.

signal chosen(section: int)
signal cancelled

const SKIP_PREFIXES: Array[String] = ["ROUTE", "MT.", "MT ", "CAVE", "TUNNEL", "FOREST", "ROAD", "PATH", "GATE", "TOWER", "CAVERN", "DARK", "LIGHTHOUSE", "RUINS", "WELL", "PARK", "VALLEY", "HILL", "PASS", "FALLS", "ISLETS", "WHIRL", "CLIFF", "SLOWPOKE", "UNION", "VICTORY", "INDIGO", "SILVER", "SHRINE", "EMBEDDED", "DRAGONS", "ICE ", "MORTAR", "BURNED", "TIN ", "SPROUT", "BELL ", "NATIONAL"]

var _data: GameData = null
var _events: Gen3EventData = null
var _spots: Array = []
var _list: ItemList = null


func setup(data: GameData, events: Gen3EventData) -> void:
	_data = data
	_events = events


static func flyable(name: String) -> bool:
	var upper: String = name.to_upper()
	for prefix: String in SKIP_PREFIXES:
		if upper.begins_with(prefix):
			return false
	return not name.is_empty()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.12, 0.22, 1.0)
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
	head.text = "FLY TO..."
	head.add_theme_font_size_override("font_size", 24)
	body.add_child(head)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	body.add_child(_list)
	_fill()


func _fill() -> void:
	_spots.clear()
	_list.clear()
	var region: Dictionary = _data.world_region_map()
	var entries: Array = region.get("entries", [])
	for key: Variant in _events.visited_spots:
		var section: int = int(key)
		if section < 0 or section >= entries.size():
			continue
		var name: String = String((entries[section] as Dictionary).get("name", ""))
		if flyable(name):
			_spots.append(section)
			_list.add_item(name)


func _on_selected(index: int) -> void:
	if index >= 0 and index < _spots.size():
		chosen.emit(int(_spots[index]))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
