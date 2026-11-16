class_name Gen3NamingScreen
extends Control

## The naming screen the ROM opens for `ChangePokemonNickname` and
## `NameRival` (`naming_screen.c::DoNamingScreen`): a text-entry box over the
## field, prefilled with the current name. D-pad moves over the keyboard,
## A picks a letter (OK confirms), B deletes, or backs out with the old name
## when the box is empty. An empty confirm keeps the old name, as the ROM's
## `SaveInputText` only copies the entry when it holds a non-space character.
## The script that called the special faded the field to black first; this
## screen draws its own background, and the caller fades the field back when
## it closes.

signal finished(name: String)
signal cancelled

const MAX_CHARS: int = 10 # `POKEMON_NAME_LENGTH` / the rival name's 10.
const ROWS: Array = [
	["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"],
	["N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"],
	["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "!", "?"],
]
const WIDE_KEYS: Array = ["BACK", "SPACE", "OK"]
const WIDE_SPANS: Array[int] = [4, 5, 4] # Columns each wide key covers, of 13.
const KEY_HEIGHT: float = 46.0
const KEY_GAP: float = 6.0
const PANEL_PAD: float = 24.0
const PANEL_COLOR: Color = Color(0.08, 0.08, 0.12, 0.97)
const PANEL_BORDER: Color = Color(0.85, 0.82, 0.70)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.92)
const DIM_COLOR: Color = Color(0.60, 0.60, 0.58)
const CURSOR_COLOR: Color = Color(0.95, 0.80, 0.25)
const REPEAT_FRAMES: int = 7 # Frames a held direction waits before repeating.

var _text: String = ""
var _title: String = ""
var _row: int = 0
var _col: int = 0
var _a_held: bool = false
var _b_held: bool = false
var _done: bool = false
var _held_dir: int = 0 # -2 up, -1 left, 1 right, 2 down, while a direction is held.
var _repeat: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func open(default_text: String, title: String) -> void:
	_text = default_text
	_title = title
	_row = 0
	_col = 0
	# A button already held when the screen opens — the A that answered the
	# nickname YES/NO — is not a fresh press, so it must not type or confirm.
	_a_held = PokeButton.held(PokeButton.A)
	_b_held = PokeButton.held(PokeButton.B)
	_done = false
	_held_dir = 0
	_repeat = 0
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.85))
	var metrics: Dictionary = _metrics()
	var panel: Rect2 = metrics["panel"]
	draw_rect(panel, PANEL_COLOR)
	draw_rect(panel, PANEL_BORDER, false, 3.0)
	var font: Font = ThemeDB.fallback_font
	var title_size: Vector2 = font.get_string_size(_title, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
	draw_string(font, Vector2(panel.get_center().x - title_size.x * 0.5, panel.position.y + 44.0),
		_title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, TEXT_COLOR)
	var shown: String = _text
	while shown.length() < MAX_CHARS:
		shown += "_"
	var name_size: Vector2 = font.get_string_size(shown, HORIZONTAL_ALIGNMENT_CENTER, -1, 40)
	draw_string(font, Vector2(panel.get_center().x - name_size.x * 0.5, panel.position.y + 104.0),
		shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, TEXT_COLOR)
	for row: int in 4:
		for index: int in _row_keys(row).size():
			var key: Rect2 = _key_rect(metrics, row, index)
			var label: String = _row_keys(row)[index]
			if row == _row and index == _col:
				draw_rect(key, CURSOR_COLOR)
				draw_rect(key, PANEL_BORDER, false, 2.0)
			var label_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 26)
			draw_string(font, key.get_center() + Vector2(-label_size.x * 0.5, label_size.y * 0.35),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
				PANEL_COLOR if row == _row and index == _col else TEXT_COLOR)
	var hint: String = "A: select    B: delete / back"
	var hint_size: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
	draw_string(font, Vector2(panel.get_center().x - hint_size.x * 0.5, panel.end.y - 14.0),
		hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DIM_COLOR)


func _process(_delta: float) -> void:
	if _done:
		return
	var dir: int = 0
	if PokeButton.held(PokeButton.LEFT):
		dir = -1
	elif PokeButton.held(PokeButton.RIGHT):
		dir = 1
	elif PokeButton.held(PokeButton.UP):
		dir = -2
	elif PokeButton.held(PokeButton.DOWN):
		dir = 2
	if dir != _held_dir:
		_held_dir = dir
		_repeat = 0
		if dir != 0:
			_move(dir)
			queue_redraw()
	elif dir != 0:
		_repeat += 1
		if _repeat >= REPEAT_FRAMES:
			_repeat = 0
			_move(dir)
			queue_redraw()
	var a_held: bool = PokeButton.held(PokeButton.A)
	if a_held and not _a_held:
		_press_a()
	_a_held = a_held
	var b_held: bool = PokeButton.held(PokeButton.B)
	if b_held and not _b_held:
		_press_b()
	_b_held = b_held


func _move(dir: int) -> void:
	match dir:
		-1:
			_col = posmod(_col - 1, _row_keys(_row).size())
		1:
			_col = posmod(_col + 1, _row_keys(_row).size())
		-2:
			_row = maxi(_row - 1, 0)
			_col = mini(_col, _row_keys(_row).size() - 1)
		2:
			_row = mini(_row + 1, 3)
			_col = mini(_col, _row_keys(_row).size() - 1)


func _press_a() -> void:
	if _done:
		return
	if _row < 3:
		if _text.length() < MAX_CHARS:
			_text += String(_row_keys(_row)[_col])
			queue_redraw()
		return
	match String(WIDE_KEYS[_col]):
		"BACK":
			_press_b()
		"SPACE":
			if _text.length() < MAX_CHARS:
				_text += " "
				queue_redraw()
		"OK":
			_confirm()


func _press_b() -> void:
	if _done:
		return
	if not _text.is_empty():
		_text = _text.substr(0, _text.length() - 1)
		queue_redraw()
	else:
		_cancel()


func _confirm() -> void:
	if _done:
		return
	_done = true
	finished.emit(_text)


func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()


func _row_keys(row: int) -> Array:
	return WIDE_KEYS if row == 3 else ROWS[row]


func _metrics() -> Dictionary:
	var key_w: float = mini(46.0, (size.x * 0.94 - PANEL_PAD * 2.0 - KEY_GAP * 12.0) / 13.0)
	var panel_w: float = PANEL_PAD * 2.0 + key_w * 13.0 + KEY_GAP * 12.0
	var panel_h: float = PANEL_PAD * 2.0 + 116.0 + KEY_HEIGHT * 4.0 + KEY_GAP * 3.0 + 36.0
	# The skin cutout's centre, as the wall clock's: the panel sits in the
	# game screen, not the whole viewport.
	var center: Vector2 = size * Vector2(0.5, 0.28)
	return {"key_w": key_w, "panel": Rect2(center - Vector2(panel_w, panel_h) * 0.5, Vector2(panel_w, panel_h))}


func _key_rect(metrics: Dictionary, row: int, index: int) -> Rect2:
	var panel: Rect2 = metrics["panel"]
	var key_w: float = float(metrics["key_w"])
	var top: float = panel.position.y + PANEL_PAD + 116.0 + float(row) * (KEY_HEIGHT + KEY_GAP)
	if row < 3:
		var left: float = panel.position.x + PANEL_PAD + float(index) * (key_w + KEY_GAP)
		return Rect2(left, top, key_w, KEY_HEIGHT)
	var left: float = panel.position.x + PANEL_PAD
	for prior: int in index:
		left += float(WIDE_SPANS[prior]) * (key_w + KEY_GAP) - KEY_GAP
	var width: float = float(WIDE_SPANS[index]) * key_w + float(WIDE_SPANS[index] - 1) * KEY_GAP
	return Rect2(left, top, width, KEY_HEIGHT)


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed(&"gen2_a"):
		_press_a()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_b"):
		_press_b()
		get_viewport().set_input_as_handled()
