class_name Gen3FieldView
extends TextureRect # [Gen3FieldScreen] in a window: the pad at the GBA's frame rate. Requests with no screen yet print and move on.

const FRAME_SECONDS: float = 280896.0 / 16777216.0
const MAX_CATCH_UP: int = 2
const REPORTED: Array[String] = ["start_menu_action", "trainer_battle", "wild_battle", "mart", "field_special", "dofieldeffect",
	"script_error", "white_out"]

var screen: Gen3FieldScreen
var _clock: float = 0.0
var _held: Array[int] = []
var _image_texture: ImageTexture
var _wall_clock: Gen3WallClock = null
var _naming: Gen3NamingScreen = null
var _naming_slot: int = -1
var _naming_dest: String = "mon"
var _naming_fade_back: bool = false


static func open(game: GameData, group: int, number: int, at: Vector2i) -> Gen3FieldView: # Null where the player cannot stand.
	return _wrap(Gen3FieldScreen.open(game, group, number, at))


## A new game after the intro: the chosen name and gender ride in on the
## event data, so the avatar, `checkplayergender` and the first save all
## agree from the first frame.
static func open_new(game: GameData, group: int, number: int, at: Vector2i,
		player_name: String, gender: int, randomizer: Dictionary = {},
		seed: int = 0, nuzlocke: bool = false) -> Gen3FieldView:
	var events := Gen3EventData.new(game.id)
	events.player_name = player_name
	events.player_gender = gender
	events.nuzlocke = nuzlocke
	for feature: String in events.randomizer:
		events.randomizer[feature] = bool(randomizer.get(feature, false))
	if events.randomizer.values().any(func(value: Variant) -> bool: return bool(value)):
		Gen3Randomizer.set_seed(events, seed)
	return _wrap(Gen3FieldScreen.open(game, group, number, at, 1, gender,
		Gen3PlayerAvatar.Flag.ON_FOOT, -1, events))


## A saved game, reopened where it was saved. Null where the save is not valid
## or the player cannot stand there.
static func open_from_save(game: GameData, save: Gen3SaveData) -> Gen3FieldView:
	return _wrap(Gen3FieldScreen.open_from_save(game, save))


static func _wrap(field: Gen3FieldScreen) -> Gen3FieldView:
	if field == null:
		return null
	var view := Gen3FieldView.new()
	view.screen = field
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view._image_texture = ImageTexture.create_from_image(field.picture())
	view.texture = view._image_texture
	return view


func _process(delta: float) -> void:
	if _wall_clock != null or _naming != null:
		return
	_clock += delta
	var frames: int = mini(int(_clock / FRAME_SECONDS), MAX_CATCH_UP)
	_clock = fposmod(_clock, FRAME_SECONDS)
	for frame: int in frames:
		advance()
	if frames > 0:
		_image_texture.update(screen.picture())


func advance() -> void:
	var held: Array[int] = []
	var pressed: Array[int] = []
	for button: int in PokeButton.ALL:
		if PokeButton.held(button):
			held.append(button)
			if button not in _held:
				pressed.append(button)
	_held = held
	for row: Dictionary in screen.frame(held, pressed):
		_settle(row)


## A battle's aftermath: a white out heals the party where it stands
## (the heal-point warp is not modelled yet) and gives the field back,
## so a loss never leaves the player locked in a stopped script.
func _settle_result(rows: Array) -> void:
	for row: Dictionary in rows:
		if String(row.get("kind", "")) != "white_out":
			continue
		for mon: Dictionary in screen.host.objects.events.party:
			if bool(mon.get("dead", false)):
				continue # The nuzlocke dead stay dead; a heal is not a revive.
			mon["hp"] = Gen3BattleResolver.max_hp(screen.data, mon)
		screen.host.unfreeze_field()
		screen.host.resume()


func _settle(row: Dictionary) -> void:
	var kind: String = row["kind"]
	if kind not in REPORTED:
		return
	print("gen3 field: ", row)
	match kind:
		"start_menu_action":
			if row["action"] == Gen3FieldStartMenu.OPTION:
				screen.open_options()
			elif row["action"] == Gen3FieldStartMenu.RETIRE:
				screen.host.input.exit_safari() # The menu already unfroze the field; RETIRE returns to it, it does not reopen the menu.
			elif row["action"] == Gen3FieldStartMenu.SAVE:
				screen.begin_save()
			else:
				screen.return_to_start_menu()
		"trainer_battle":
			var foes: Array = []
			foes.append_array(row.get("party_a", []))
			foes.append_array(row.get("party_b", []))
			var outcome: int = Gen3BattleResolver.resolve(screen.data,
				screen.host.objects.events, foes)
			_settle_result(screen.host.finish_battle(outcome))
		"wild_battle":
			var wild_outcome: int = Gen3BattleResolver.resolve_wild(screen.data,
				screen.host.objects.events, int(row.get("species", 0)), int(row.get("level", 5)))
			_settle_result(screen.host.finish_wild_battle(wild_outcome))
		"mart":
			screen.host.finish_wait()
		"field_special":
			var special_name: String = String(row.get("name", ""))
			if special_name in ["StartWallClock", "Special_ViewWallClock"]:
				_open_wall_clock(special_name == "Special_ViewWallClock")
			elif special_name in ["ChangePokemonNickname", "NameRival"]:
				_open_naming_screen(row)
			else:
				# A screen the engine does not draw still has to give the field
				# back: `ChooseStarter` is the one the ROM fades to black for
				# first, so its no-op close fades the field back with it.
				if bool(row.get("fade_back", false)):
					screen.weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)
				screen.host.finish_wait()
				screen.host.resume() # `_screen_special` waits the script when no `waitstate` follows; a screen with no close of its own still has to let it run on.


## The wall clock face: the field pauses while it is open, and the script
## that called `StartWallClock` waits until it closes. Confirming sets the
## in-game time; backing out leaves it where it was. `Special_ViewWallClock`
## opens the same face view-only: the time cannot be changed from it.
func _open_wall_clock(view_only: bool = false) -> void:
	if _wall_clock != null:
		return
	var clock := Gen3WallClock.new()
	_wall_clock = clock
	clock.finished.connect(_on_wall_clock_finished)
	clock.cancelled.connect(_on_wall_clock_cancelled)
	# Cover the whole view so the face is the only thing the player sees.
	get_parent().add_child(clock)
	clock.set_anchors_preset(Control.PRESET_FULL_RECT)
	# A Control added at runtime still reports size (0, 0) until the layout
	# pass runs, and the first draw happens before that: set the rect
	# explicitly so the face is drawn in the viewport, not at the corner.
	clock.position = Vector2.ZERO
	clock.size = get_viewport_rect().size
	clock.open(screen.host.objects.events.clock_hour, screen.host.objects.events.clock_minute, view_only)


func _on_wall_clock_finished(hour: int, minute: int) -> void:
	screen.host.objects.events.clock_hour = hour
	screen.host.objects.events.clock_minute = minute
	_close_wall_clock()


func _on_wall_clock_cancelled() -> void:
	_close_wall_clock()


func _close_wall_clock() -> void:
	if _wall_clock != null:
		_wall_clock.queue_free()
		_wall_clock = null
	# The clock script faded the field to black before the special, and the
	# ROM's clock fades back from black as it closes (`WallClockInit` fades
	# in, the exit fades out, `ReturnFromStartWallClock` returns to a field
	# that fades in again). Without this the palette stays at black: the
	# field keeps running under a black picture. Same call the field open
	# uses, so the fade animates back over the following frames.
	screen.weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)
	screen.host.finish_wait()
	screen.host.resume() # The clock script sits in WAITING on `waitstate`; `finish_wait` alone never wakes it, so the `setvar`/`setflag` after the clock never ran.


## The naming screen for `ChangePokemonNickname` (the party mon VAR_0x8004
## names) and `NameRival` (the rival, prefilled Silver): the field pauses
## while it is open, and the script that called the special waits until it
## closes. Confirming writes the entered name back; backing out, or
## confirming an empty entry, keeps the old one, as the ROM's `SaveInputText`
## only copies a non-blank entry.
func _open_naming_screen(row: Dictionary) -> void:
	if _naming != null:
		return
	_naming_dest = String(row.get("dest", "mon"))
	_naming_slot = int(row.get("slot", -1))
	_naming_fade_back = bool(row.get("fade_back", false))
	var naming := Gen3NamingScreen.new()
	_naming = naming
	naming.finished.connect(_on_naming_finished)
	naming.cancelled.connect(_on_naming_cancelled)
	get_parent().add_child(naming)
	naming.set_anchors_preset(Control.PRESET_FULL_RECT)
	naming.position = Vector2.ZERO
	naming.size = get_viewport_rect().size
	var title: String = "What is his name?"
	if _naming_dest != "rival":
		var species_name: String = String(screen.data.species(int(row.get("species", 0))).get("name", ""))
		title = "Give %s a nickname?" % species_name if not species_name.is_empty() else "Give a nickname?"
	naming.open(String(row.get("nickname", "")), title)


func _on_naming_finished(name: String) -> void:
	if not name.is_empty():
		if _naming_dest == "rival":
			screen.host.objects.events.rival_name = name
		elif _naming_slot >= 0 and _naming_slot < screen.host.objects.events.party.size():
			screen.host.objects.events.party[_naming_slot]["nickname"] = name
	_close_naming()


func _on_naming_cancelled() -> void:
	_close_naming()


func _close_naming() -> void:
	if _naming != null:
		_naming.queue_free()
		_naming = null
	# Only the nickname call sites faded the field to black first; the rival
	# naming sites did not, so only the nickname close fades it back.
	if _naming_fade_back:
		screen.weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)
	screen.host.finish_wait()
	screen.host.resume()
