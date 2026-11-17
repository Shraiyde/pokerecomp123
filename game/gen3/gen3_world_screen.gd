class_name Gen3WorldScreen
extends Control

## The Gen 3 overworld: a [Gen3FieldView] in a window, the pad at the GBA's
## frame rate. The Gen 2 intro, spawn and world are Gen 1/2 only, so a Gen 3
## cartridge starts here instead: the player's bedroom, in bed, waking up to
## the story the ROM's own scripts carry from there. The screen is a GBA SP
## skin: the game fills the skin's own screen cutout edge to edge, and the
## touch pad maps to the buttons drawn on the skin, so the phone reads as
## the hardware.

const LAUNCHER_SCENE: String = "res://game/main/main.tscn"
## The player's bedroom: group 1 (IndoorNewBark) number 4, warp 1 at (1, 6),
## the bed. new_game.c WarpToTruck sets exactly this warp for a new H&S game.
const START_GROUP: int = 1
const START_NUMBER: int = 4
const START_CELL: Vector2i = Vector2i(1, 6)
## The skin's screen cutout, as fractions of the skin (852x1846, measured
## from the image): the black screen is x 28..824, y 164..773.
const SCREEN_RECT: Rect2 = Rect2(0.0329, 0.0888, 0.9354, 0.3304)

var _view: Gen3FieldView = null
var _data: GameData = null
var _intro: Gen3IntroScreen = null
var _coop_screen: Gen3CoopScreen = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# `data_or_any` falls back to the first imported cartridge when the
	# selected game id is lost: a null here used to boot straight back to
	# the launcher with nothing loaded.
	var data: GameData = Gen2GameRuntime.data_or_any()
	if data == null:
		_back_to_launcher()
		return
	_data = data
	# A staged new game runs the ROM's intro first (gender, then name),
	# exactly as `oak_speech_hns.c` does before `CB2_NewGame` warps to
	# the bedroom. Anything else opens the field directly.
	var runtime: Gen2GameRuntime = Gen2GameRuntime.instance()
	if runtime != null and runtime.pending_new_game_slot >= 0:
		_intro = Gen3IntroScreen.new()
		add_child(_intro)
		_intro.finished.connect(_on_intro_finished)
		return
	_view = _open_field(data)
	if _view == null:
		_back_to_launcher()
		return
	_attach_view()


## The intro is done: the staged slot is consumed and the field opens in
## the bedroom with the chosen name and gender.
func _on_intro_finished(player_name: String, gender: int, randomizer: Dictionary, seed: int, nuzlocke: bool) -> void:
	var runtime: Gen2GameRuntime = Gen2GameRuntime.instance()
	var pending: Dictionary = runtime.take_pending_new_game() if runtime != null \
		else {"slot": -1}
	var slot: int = int(pending.get("slot", -1))
	if _intro != null:
		_intro.queue_free()
		_intro = null
	_view = Gen3FieldView.open_new(_data, START_GROUP, START_NUMBER, START_CELL,
		player_name, gender, randomizer, seed, nuzlocke)
	if _view == null:
		_back_to_launcher()
		return
	_view.screen.save_slot = maxi(slot, 0)
	_attach_view()


func _attach_view() -> void:
	add_child(_view)
	## The skin is the bottom layer; the game sits in its screen cutout on
	## top of it, and the pad sits on top of both. The game is not stretched
	## to fill the cutout: the map's own black border is supposed to show
	## at the edges, so the view keeps the game's aspect and centres in it.
	var skin: Control = get_node_or_null("Skin")
	if skin != null:
		move_child(skin, 0)
		# The skin art is the player's own file; when it sits beside the
		# scene it is used, and the game runs without it when it does not.
		if skin is TextureRect and (skin as TextureRect).texture == null \
				and ResourceLoader.exists("res://game/gen3/gba_skin.png"):
			(skin as TextureRect).texture = load("res://game/gen3/gba_skin.png")
	move_child(_view, 1)
	_view.anchor_left = SCREEN_RECT.position.x
	_view.anchor_top = SCREEN_RECT.position.y
	_view.anchor_right = SCREEN_RECT.position.x + SCREEN_RECT.size.x
	_view.anchor_bottom = SCREEN_RECT.position.y + SCREEN_RECT.size.y
	_view.offset_left = 0.0
	_view.offset_top = 0.0
	_view.offset_right = 0.0
	_view.offset_bottom = 0.0
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	## The pad is the scene's own child, so it sits under a view added after
	## it; the pad goes back on top, where a finger reaches it first.
	## Co-op lives above the pad: HOST shows the PIN, JOIN asks for it,
	## and the story syncs while both players walk their own games.
	var coop_button := Button.new()
	coop_button.text = "CO-OP"
	coop_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	coop_button.position = Vector2(-52, 8)
	coop_button.size = Vector2(104, 44)
	coop_button.custom_minimum_size = Vector2(104, 44)
	coop_button.pressed.connect(_open_coop)
	add_child(coop_button)
	var pad: Gen2TouchPad = get_node_or_null("%TouchPad") as Gen2TouchPad
	if pad != null:
		move_child(pad, get_child_count() - 1)
		## The pad measures against the whole viewport, not the safe area:
		## the skin fills the viewport edge to edge, so the notch and gesture
		## bar insets would shift every button off the drawn art.
		pad.use_full_rect_area = true
		_apply_skin_layout(pad)


func _open_coop() -> void:
	if _coop_screen == null:
		_coop_screen = Gen3CoopScreen.new()
		_coop_screen.closed.connect(func() -> void: _coop_screen.visible = false)
		add_child(_coop_screen)
	if _view != null:
		_coop_screen.open(screen_data(), screen_events(), _freeze_field, _unfreeze_field)
	_coop_screen.visible = true
	move_child(_coop_screen, get_child_count() - 1)


func screen_data() -> GameData:
	return _data


func screen_events() -> Gen3EventData:
	return _view.screen.host.objects.events if _view != null else null


func _freeze_field() -> void:
	if _view != null:
		_view.screen.host.freeze_for_menu()
		screen_events().controls_locked = true


func _unfreeze_field() -> void:
	if _view != null:
		_view.screen.host.unfreeze_field()


## The co-op pump: the transport rides the field's own frame, diffing the
## live flags/vars against what the peer already has.
func _process(_delta: float) -> void:
	if _coop_screen == null or _coop_screen.transport == null or _view == null:
		return
	_coop_screen.transport.poll(_view.screen.host.objects.events)


## How a Gen 3 game starts: a staged new game (the launcher's `begin_new_game`)
## always starts fresh in the bedroom, even when a save already sits in the
## slot; anything else continues the session slot's save when one exists, and
## starts fresh only when it does not. A save that fails to load is a fresh
## start rather than a dead screen.
func _open_field(data: GameData) -> Gen3FieldView:
	var runtime: Gen2GameRuntime = Gen2GameRuntime.instance()
	var pending: Dictionary = runtime.take_pending_new_game() if runtime != null \
		else {"slot": -1}
	var slot: int = int(pending.get("slot", -1))
	if slot >= 0:
		var fresh := Gen3FieldView.open(data, START_GROUP, START_NUMBER, START_CELL)
		if fresh != null:
			fresh.screen.save_slot = slot
		return fresh
	slot = runtime.selected_save_slot if runtime != null and runtime.has_selected_save_slot() else -1
	if slot < 0:
		# No slot was selected (the selection is lost on a game change):
		# continue the first save on disk rather than starting over.
		var occupied: Array[int] = Gen3SaveStore.occupied_slots(data.id, data.sha1)
		slot = occupied[0] if not occupied.is_empty() else 0
	var unreadable: bool = false
	if Gen3SaveStore.exists(data.id, data.sha1, slot):
		var loaded: Dictionary = Gen3SaveStore.load_result(data.id, data.sha1, slot, data)
		if loaded["ok"]:
			var resumed := Gen3FieldView.open_from_save(data, loaded["save"])
			if resumed != null:
				return resumed
		unreadable = true
	var view := Gen3FieldView.open(data, START_GROUP, START_NUMBER, START_CELL)
	if view != null:
		# An unreadable save is never overwritten: a fresh start writes to
		# the next free slot, so the file on disk survives for repair.
		view.screen.save_slot = Gen3SaveStore.next_free_slot(data.id, data.sha1) if unreadable else maxi(slot, 0)
	return view


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_back_to_launcher()
		get_viewport().set_input_as_handled()


## The touch zones sit on the buttons drawn on the skin, so a thumb lands
## where the hardware's own button is. The pad draws white outlines only, so
## the skin's buttons stay visible while the zones can be seen.
func _apply_skin_layout(pad: Control) -> void:
	var layout := PokeTouchLayout.new()
	var portrait: StringName = PokeTouchLayout.ORIENTATION_PORTRAIT
	## Centres measured from the skin itself (fractions of the viewport):
	## the D-pad, A, B, L, R, Select and Start sit on the buttons drawn
	## on the skin, so a thumb lands where the hardware's own button is.
	## Pixel centres in the 852x1846 image: pad (215, 1225), B (536, 1227),
	## A (735, 1225), L (159, 869), R (695, 869), Select (282, 1581),
	## Start (562, 1581).
	layout.anchors[portrait] = {
		PokeTouchLayout.GROUP_PAD: Vector2(0.252, 0.664),
		PokeTouchLayout.GROUP_B: Vector2(0.629, 0.664),
		PokeTouchLayout.GROUP_A: Vector2(0.863, 0.663),
		PokeTouchLayout.GROUP_L: Vector2(0.186, 0.471),
		PokeTouchLayout.GROUP_R: Vector2(0.815, 0.471),
		PokeTouchLayout.GROUP_SELECT: Vector2(0.331, 0.856),
		PokeTouchLayout.GROUP_START: Vector2(0.659, 0.856),
	}
	## No whole-cluster clamping: the big joystick is centred on the drawn
	## d-pad and its circle overhangs the drawn button, so clamping its box
	## inside the area would shove its centre off the art.
	layout.clamp_groups_to_area = false
	## Joystick d-pad (slide the thumb in the circle), big as it was;
	## face buttons at the skin's size so A and B stop overlapping, menu
	## and shoulder pills small so Select and Start stop blowing up.
	## White outlines only so the skin shows through.
	layout.joystick = true
	layout.outline_only = true
	layout.scale = 1.0
	layout.pad_scale = 2.0
	layout.face_scale = 1.3
	layout.menu_scale = 1.0
	layout.opacity = 1.0
	pad.set_layout(layout)


func go_launcher() -> void:
	_back_to_launcher()


func _back_to_launcher() -> void:
	get_tree().change_scene_to_file.call_deferred(LAUNCHER_SCENE)
