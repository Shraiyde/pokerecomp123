class_name Gen3TrainerCardScreen
extends Control

## The trainer card: name and gender, the eight Johto badges
## (flags 0x880-0x887, the ROM's `FLAG_BADGE01_GET` row), play time
## and money. B steps back out.

signal closed

var _data: GameData = null
var _events: Gen3EventData = null
var _play_seconds: int = 0


func setup(data: GameData, events: Gen3EventData, play_seconds: int = 0) -> void:
	_data = data
	_events = events
	_play_seconds = play_seconds


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.55, 0.08, 0.10, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var title := Label.new()
	title.text = "TRAINER CARD"
	title.add_theme_font_size_override("font_size", 30)
	body.add_child(title)
	var name := Label.new()
	name.text = "NAME  %s   (%s)" % [_events.player_name,
		"GIRL" if _events.player_gender == 1 else "BOY"]
	name.add_theme_font_size_override("font_size", 24)
	body.add_child(name)
	var badges := Label.new()
	var rows: Array[String] = []
	for badge: int in 8:
		rows.append("[X]" if _events.flag_get(0x880 + badge) else "[ ]")
	badges.text = "BADGES  " + "  ".join(rows)
	badges.add_theme_font_size_override("font_size", 24)
	body.add_child(badges)
	var hours: int = _play_seconds / 3600
	var minutes: int = (_play_seconds % 3600) / 60
	var time := Label.new()
	time.text = "PLAY TIME  %d:%02d" % [hours, minutes]
	time.add_theme_font_size_override("font_size", 24)
	body.add_child(time)
	var money := Label.new()
	money.text = "MONEY  ¥%d" % (_events.bag.money if _events.bag != null else 0)
	money.add_theme_font_size_override("font_size", 24)
	body.add_child(money)
	var hint := Label.new()
	hint.text = "B: back"
	hint.add_theme_font_size_override("font_size", 18)
	body.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_b"):
		closed.emit()
		get_viewport().set_input_as_handled()
