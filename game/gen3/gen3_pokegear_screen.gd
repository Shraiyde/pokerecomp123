class_name Gen3PokegearScreen
extends Control

## The Pokégear's map: Johto as the ROM maps it, drawn from the
## imported region entries and section grid, with the player's
## position marked. Phone and radio have no Gen 3 data import yet,
## so the gear opens on the one tab the cache can draw.

signal closed

const CELL: float = 22.0

var _data: GameData = null
var _section: int = -1
var _grid: Control = null
var _name_label: Label = null
var _cursor: int = 0
var _named: Array[int] = []


func setup(data: GameData, events: Gen3EventData, section: int) -> void:
	_data = data
	_section = section


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
	head.text = "POKéGEAR  -  MAP"
	head.add_theme_font_size_override("font_size", 24)
	body.add_child(head)
	_grid = _MapGrid.new()
	_grid.custom_minimum_size = Vector2(28 * CELL, 15 * CELL)
	(_grid as _MapGrid).screen = self
	body.add_child(_grid)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 24)
	body.add_child(_name_label)
	var hint := Label.new()
	hint.text = "LEFT / RIGHT: move    A: name    B: close"
	hint.add_theme_font_size_override("font_size", 18)
	body.add_child(hint)
	_collect()
	(_grid as _MapGrid).queue_redraw()
	_show_name()


class _MapGrid extends Control:
	var screen: Gen3PokegearScreen = null

	func _draw() -> void:
		if screen == null:
			return
		var region: Dictionary = screen._data.world_region_map()
		var grid: Array = region.get("grid", [])
		var width: int = int(region.get("width", 28))
		for index: int in grid.size():
			var col: int = index % width
			var row: int = index / width
			var filled: bool = int(grid[index]) != 0
			draw_rect(Rect2(col * CELL, row * CELL, CELL - 1, CELL - 1),
				Color(0.25, 0.55, 0.30) if filled else Color(0.05, 0.10, 0.16))
		for entry_index: int in screen._named:
			var entry: Dictionary = (region.get("entries", []) as Array)[entry_index]
			draw_rect(Rect2(int(entry.get("x", 0)) * CELL, int(entry.get("y", 0)) * CELL,
				maxi(int(entry.get("w", 1)), 1) * CELL - 1, maxi(int(entry.get("h", 1)), 1) * CELL - 1),
				Color(0.95, 0.85, 0.30), false, 2.0)
		var here: Vector2i = screen._player_cell(region)
		if here.x >= 0:
			draw_circle(Vector2(here) * CELL + Vector2(CELL, CELL) * 0.5, 7.0, Color(0.95, 0.20, 0.20))


func _collect() -> void:
	var region: Dictionary = _data.world_region_map()
	for index: int in (region.get("entries", []) as Array).size():
		var entry: Dictionary = (region.get("entries", []) as Array)[index]
		if not String(entry.get("name", "")).is_empty():
			_named.append(index)
	_grid.screen = _grid_screen()


func _player_cell(region: Dictionary) -> Vector2i:
	var entries: Array = region.get("entries", [])
	if _section >= 0 and _section < entries.size():
		var entry: Dictionary = entries[_section]
		if not String(entry.get("name", "")).is_empty():
			return Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0)))
	return Vector2i(-1, -1)


func _show_name() -> void:
	var region: Dictionary = _data.world_region_map()
	var entries: Array = region.get("entries", [])
	if _cursor >= 0 and _cursor < _named.size():
		_name_label.text = String((entries[_named[_cursor]] as Dictionary).get("name", "--"))
	else:
		_name_label.text = "--"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		closed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_left"):
		_cursor = posmod(_cursor - 1, maxi(_named.size(), 1))
		_show_name()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_right"):
		_cursor = (_cursor + 1) % maxi(_named.size(), 1)
		_show_name()
		get_viewport().set_input_as_handled()
