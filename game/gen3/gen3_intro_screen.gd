class_name Gen3IntroScreen
extends Control

## The new-game intro the ROM runs before the bedroom (`oak_speech_hns.c`,
## `data/text/oak_speech_hns.inc`): Oak's welcome and main speech, the
## Boy/Girl menu writing `playerGender`, the naming screen prefilled with
## the gender's preset (GOLD / KRIS), the "So you're <PLAYER>?" confirm
## (No loops back to Boy/Girl), the challenge menu, and the ready speech.
## The randomizer choice is the challenge menu's: all `tx_Random_*`
## switches on with a fresh seed, or a vanilla game.

signal finished(player_name: String, gender: int, randomizer: Dictionary, seed: int, nuzlocke: bool)

const PRESET_NAMES: Array[String] = ["GOLD", "KRIS"]
const SPEECH_PAGES: Array[String] = [
	"Hi! Sorry to keep you waiting!\nWelcome to the world of POKEMON!\nMy name is OAK.\nPeople call me the POKEMON PROFESSOR.",
	"This world is widely inhabited by\ncreatures known as POKEMON.\nPeople and POKEMON live together,\nby supporting each other.",
	"Some people play with POKEMON,\nsome battle with them.\nBut we don't know everything about\nPOKEMON yet.",
	"There are still many mysteries\nto solve. That's why I study\nPOKEMON every day.",
	"And you are?",
]
const READY_PAGES: Array[String] = [
	"Your very own adventure is about\nto unfold.",
	"You'll face fun times and tough\nchallenges.\nA world of dreams and adventures\nwith POKEMON awaits! Let's go!\nI'll be seeing you later!",
]

var _gender: int = 0
var _name: String = ""
var _randomizer: Dictionary = {"wild": false, "trainer": false, "items": false, "starter": false}
var _nuzlocke: bool = false
var _seed: int = 0
var _stage: String = "speech"
var _page: int = 0
var _body: VBoxContainer = null
var _text_label: Label = null
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
	_body = VBoxContainer.new()
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_theme_constant_override("separation", 18)
	center.add_child(_body)
	_show_speech()


func _clear_body() -> void:
	for child: Node in _body.get_children():
		child.queue_free()
	_text_label = null


## Oak himself, from the ROM's own `graphics/oak_speech_hns/oak_hns.png`,
## shown while he speaks, as the ROM shows him.
func _add_oak() -> void:
	var oak := TextureRect.new()
	oak.texture = load("res://game/gen3/oak_hns.png")
	oak.custom_minimum_size = Vector2(192, 192)
	oak.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	oak.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	oak.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.add_child(oak)


func _add_text(text: String) -> Label:
	_text_label = Label.new()
	_text_label.text = text
	_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_label.add_theme_font_size_override("font_size", 26)
	_body.add_child(_text_label)
	return _text_label


func _add_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 60)
	button.pressed.connect(on_pressed)
	_body.add_child(button)
	return button


func _show_speech() -> void:
	_stage = "speech"
	_clear_body()
	_add_oak()
	_add_text(SPEECH_PAGES[_page])
	_add_button("NEXT", _next_speech)


func _next_speech() -> void:
	if _stage == "speech":
		_page += 1
		if _page < SPEECH_PAGES.size():
			_show_speech()
		else:
			_show_gender()
	elif _stage == "ready":
		_page += 1
		if _page < READY_PAGES.size():
			_clear_body()
			_add_text(READY_PAGES[_page])
			_add_button("NEXT", _next_speech)
		else:
			_finish()


func _show_gender() -> void:
	_stage = "gender"
	_clear_body()
	_add_oak()
	_add_text("Are you a boy?\nOr are you a girl?")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_body.add_child(row)
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
	_stage = "naming"
	_naming = Gen3NamingScreen.new()
	add_child(_naming)
	_naming.set_anchors_preset(Control.PRESET_FULL_RECT)
	_naming.finished.connect(_on_naming_finished)
	_naming.cancelled.connect(_on_naming_cancelled)
	_naming.open(PRESET_NAMES[gender], "And what's your name?")


func _on_naming_finished(entered: String) -> void:
	_name = entered if not entered.is_empty() else PRESET_NAMES[_gender]
	_naming.queue_free()
	_naming = null
	_show_confirm()


func _on_naming_cancelled() -> void:
	_name = PRESET_NAMES[_gender]
	_naming.queue_free()
	_naming = null
	_show_confirm()


func _show_confirm() -> void:
	_stage = "confirm"
	_clear_body()
	_add_oak()
	_add_text("Oh! So you're %s?" % _name)
	_add_button("YES", _show_challenge)
	_add_button("NO", _show_gender) # The ROM loops back to Boy/Girl.


func _show_challenge() -> void:
	_stage = "challenge"
	_clear_body()
	_add_oak()
	_add_text("What challenge are you\nexpecting?")
	_add_button("VANILLA", _choose_challenge.bind(0))
	_add_button("RANDOMIZER", _choose_challenge.bind(1))
	_add_button("NUZLOCKE", _choose_challenge.bind(2))


func _choose_challenge(mode: int) -> void:
	for feature: String in _randomizer:
		_randomizer[feature] = mode == 1
	_nuzlocke = mode == 2
	if mode == 1:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_seed = rng.randi()
	_stage = "ready"
	_page = 0
	_clear_body()
	_add_text("%s, are you ready?" % _name)
	_add_button("NEXT", _next_speech)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(_name, _gender, _randomizer.duplicate(), _seed, _nuzlocke)
