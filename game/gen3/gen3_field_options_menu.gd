class_name Gen3FieldOptionsMenu
extends RefCounted # Emerald's OPTION screen (`option_menu.c`'s main tab) on [Gen3FieldMessage]'s BG0, the same window and cursor as [Gen3FieldStartMenu].

const FADE: String = "fade" # What [method step] returns besides "" and [constant CLOSE].
const CLOSE: String = "close"
const INPUT_DELAY: int = 2 # The A press that chose OPTION is spent by the time the fade ends; this is the same guard the menus use.
const CURSOR: int = 0xEF # gText_SelectorArrow3.
const CURSOR_SIZE := Vector2i(8, 14)
const LABEL_X: int = 8
const VALUE_RIGHT: int = 200 # Values end 8 px inside the window's right edge.
const VALUE_CLEAR_LEFT: int = 112 # Left of every value; the longest label, BATTLE STYLE, ends before it.

var active: bool = false
var _message: Gen3FieldMessage
var _engine: StringName
var _options: Gen3Options = null
var _area := Rect2i()
var _delay: int = 0
var _leaving: bool = false


func _init(message: Gen3FieldMessage, engine: StringName) -> void:
	_message = message
	_engine = engine


func open() -> void: # The window draws at once; the fade from black the field runs covers its appearance.
	_options = Gen3Options.load()
	_area = Rect2i(2, 1, 26, 16) # The ROM's options window, 26x10 cells inside its frame.
	_leaving = false
	_delay = INPUT_DELAY
	active = true
	_draw()


func step(pressed: Array[int], requests: Array, fading: bool) -> String:
	if not active:
		return ""
	if _delay > 0:
		_delay -= 1
		return ""
	if _leaving:
		return _leave(fading)
	if PokeButton.UP in pressed:
		_move(-1, requests)
	if PokeButton.DOWN in pressed:
		_move(1, requests)
	if PokeButton.LEFT in pressed or PokeButton.RIGHT in pressed:
		_adjust(1 if PokeButton.RIGHT in pressed else -1, requests)
	if PokeButton.A in pressed and _options.is_cancel():
		requests.append({"kind": "sound", "name": "select"})
		_leaving = true
		return FADE
	if PokeButton.B in pressed:
		requests.append({"kind": "sound", "name": "select"})
		_leaving = true
		return FADE
	return ""


func _leave(fading: bool) -> String: # The chosen close, which waits out the fade; the choices are written to the store here, not on every press.
	if fading:
		return ""
	_erase()
	_options.save()
	return CLOSE


func _erase() -> void:
	active = false
	_message.erase_window(_area)


func _draw() -> void:
	_message.draw_window(_area, Gen3FieldMessage.MENU_TILE)
	for row: Dictionary in _options.rows():
		_print_row(int(row["index"]))
	_draw_cursor()


func _print_row(index: int) -> void:
	var row: Dictionary = _options.rows()[index]
	var at := Vector2i(LABEL_X, _row(index))
	_message.print_on(Gen3FieldMessage.MENU_TILE, _area.size, at, Gen3Text.encode(String(row["label"])))
	_print_value(index)


func _print_value(index: int) -> void:
	var value: String = String(_options.rows()[index]["value"])
	if value.is_empty():
		return
	var bytes: PackedByteArray = Gen3Text.encode(value)
	var at := Vector2i(VALUE_RIGHT - _message.text_width(bytes), _row(index))
	_message.print_on(Gen3FieldMessage.MENU_TILE, _area.size, at, bytes)


func _row(index: int) -> int:
	return int(Gen3FieldStartMenu.FIRST_ROW[_engine]) + index * int(Gen3FieldStartMenu.ROW_HEIGHT[_engine])


func _draw_cursor() -> void:
	_message.print_on(Gen3FieldMessage.MENU_TILE, _area.size, Vector2i(0, _row(_options.cursor)), PackedByteArray([CURSOR]))


func _clear_cursor() -> void:
	_message.clear_rect_on(Gen3FieldMessage.MENU_TILE, _area.size, Rect2i(0, _row(_options.cursor), CURSOR_SIZE.x, CURSOR_SIZE.y))


func _move(delta: int, requests: Array) -> void: # Menu_MoveCursor wraps.
	requests.append({"kind": "sound", "name": "select"})
	_clear_cursor()
	_options.move(delta)
	_draw_cursor()


func _adjust(delta: int, requests: Array) -> void:
	if _options.is_cancel():
		return
	if not _options.adjust(delta):
		return
	requests.append({"kind": "sound", "name": "select"})
	var index: int = _options.cursor
	_message.clear_rect_on(Gen3FieldMessage.MENU_TILE, _area.size,
		Rect2i(VALUE_CLEAR_LEFT, _row(index), VALUE_RIGHT - VALUE_CLEAR_LEFT, 16))
	_print_value(index)
