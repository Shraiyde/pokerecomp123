class_name Gen3IntroScreen
extends Control

## The new-game intro the ROM runs before the bedroom (`oak_speech_hns.c`):
## the Boy/Girl menu writing `playerGender`, then the naming screen
## prefilled with the preset for that gender (GOLD / KRIS). Confirming the
## name, or backing out of it, starts the game; an empty entry keeps the
## preset, as the ROM's own naming screen does.

signal finished(player_name: String, gender: int)

const PRESET_NAMES: Array[String] = ["GOLD", "KRIS"]

var _gender: int = 0
var _naming: Gen3NamingScreen = null
var _done: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.09, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 18)
	center.add_child(body)
	var title := Label.new()
	title.text = "Are you a boy or a girl?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	body.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	body.add_child(row)
	var boy := Button.new()
	boy.text = "BOY"
	boy.custom_minimum_size = Vector2(140, 64)
	boy.pressed.connect(_choose_gender.bind(0))
	row.add_child(boy)
	var girl := Button.new()
	girl.text = "GIRL"
	girl.custom_minimum_size = Vector2(140, 64)
	girl.pressed.connect(_choose_gender.bind(1))
	row.add_child(girl)


func _choose_gender(gender: int) -> void:
	if _done or _naming != null:
		return
	_gender = gender
	_naming = Gen3NamingScreen.new()
	add_child(_naming)
	_naming.set_anchors_preset(Control.PRESET_FULL_RECT)
	_naming.finished.connect(_on_naming_finished)
	_naming.cancelled.connect(_on_naming_cancelled)
	_naming.open(PRESET_NAMES[gender], "What is your name?")


func _on_naming_finished(entered: String) -> void:
	_finish(entered if not entered.is_empty() else PRESET_NAMES[_gender])


func _on_naming_cancelled() -> void:
	_finish(PRESET_NAMES[_gender])


func _finish(player_name: String) -> void:
	if _done:
		return
	_done = true
	finished.emit(player_name, _gender)
