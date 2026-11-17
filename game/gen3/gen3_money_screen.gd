class_name Gen3MoneyScreen
extends Control

## Mom's amount input (`mom_savings.c`): digits build the amount
## right to left, A confirms it into VAR_0x8000 and B cancels with 0.
## The cap is what the wallet can hold.

signal finished(amount: int)
signal cancelled

const MAX_AMOUNT: int = 999999

var _amount: int = 0
var _max: int = MAX_AMOUNT
var _label: Label = null
var _done: bool = false


func open(ceiling: int = MAX_AMOUNT) -> void:
	_max = mini(ceiling, MAX_AMOUNT)
	_amount = 0
	_done = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 12)
	center.add_child(body)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 48)
	body.add_child(_label)
	var hint := Label.new()
	hint.text = "LEFT / RIGHT: amount    A: confirm    B: back"
	hint.add_theme_font_size_override("font_size", 18)
	body.add_child(hint)
	_draw()


func _draw() -> void:
	_label.text = "¥%d" % _amount


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed(&"gen2_left"):
		_amount = maxi(_amount - _step(), 0)
		_draw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_right"):
		_amount = mini(_amount + _step(), _max)
		_draw()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_a"):
		_done = true
		finished.emit(_amount)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_b"):
		_done = true
		cancelled.emit()
		get_viewport().set_input_as_handled()


## Steps of 100, then 1000 once past a thousand: big savings should
## not take a thousand presses.
func _step() -> int:
	return 1000 if _amount >= 1000 else 100
