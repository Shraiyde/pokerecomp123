class_name Gen3BagScreen
extends Control

## The bag: all five pockets in order, every non-empty slot with its
## count. A picks a slot and reports it; the caller decides what that
## means (use a potion through the party screen, throw a ball in
## battle). B steps back out. Money rides the header.

signal chosen(item: int)
signal cancelled

const POCKET_NAMES: Array[String] = ["ITEMS", "KEY ITEMS", "POKé BALLS", "TMs & HMs", "BERRIES"]

var _data: GameData = null
var _bag: Gen3Bag = null
var _entries: Array[Dictionary] = []
var _list: ItemList = null


func setup(data: GameData, bag: Gen3Bag) -> void:
	_data = data
	_bag = bag


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.16, 0.38, 1.0)
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
	head.text = "BAG   ¥%d" % _bag.money
	head.add_theme_font_size_override("font_size", 24)
	body.add_child(head)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	body.add_child(_list)
	_fill()


func _fill() -> void:
	_entries.clear()
	_list.clear()
	var pockets: Array = _bag.to_dict().get("pockets", [])
	for pocket_index: int in pockets.size():
		var name: String = POCKET_NAMES[pocket_index] if pocket_index < POCKET_NAMES.size() else "POCKET %d" % (pocket_index + 1)
		var shown: bool = false
		for slot: Variant in pockets[pocket_index]:
			var item: int = int((slot as Array)[0])
			var count: int = int((slot as Array)[1])
			if item <= 0 or count <= 0:
				continue
			if not shown:
				_list.add_item("-- %s --" % name, null, false)
				_entries.append({"item": 0})
				shown = true
			_list.add_item("%s x%d" % [String(_data.item(item).get("name", "???")), count], null, true)
			_entries.append({"item": item})


func _on_selected(index: int) -> void:
	var item: int = int(_entries[index].get("item", 0))
	if item > 0:
		chosen.emit(item)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		cancelled.emit()
		get_viewport().set_input_as_handled()
