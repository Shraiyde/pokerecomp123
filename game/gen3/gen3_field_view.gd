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
var _money: Gen3MoneyScreen = null
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
	if _wall_clock != null or _naming != null or _battle != null or _menu_screen != null or _money != null:
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


var _battle: Gen3BattleScreen = null
var _menu_screen: Control = null
var _menu_party: Gen3PartyScreen = null
var _field_item: int = 0


## A battle opens over the field: the field pauses while it runs, and
## the outcome it reports settles through the host's finish calls.
func _open_battle_wild(row: Dictionary) -> void:
	if _battle != null:
		return
	_battle = Gen3BattleScreen.open_wild(get_parent(), screen.data,
		screen.host.objects.events, int(row.get("species", 0)), int(row.get("level", 5)),
		screen.host.objects.events.flag_get(int(Gen3FieldInput.FLAGS[screen.data.id]["safari"])))
	_battle.finished.connect(_on_battle_finished.bind(false))


func _open_battle_trainer(row: Dictionary) -> void:
	if _battle != null:
		return
	var foes: Array = []
	foes.append_array(row.get("party_a", []))
	foes.append_array(row.get("party_b", []))
	var name: String = String(row.get("trainer_name", ""))
	if name.is_empty():
		var opponent: int = int(row.get("opponent_a", 0))
		name = screen.data.trainer_name(opponent) if opponent > 0 else "Trainer"
	_battle = Gen3BattleScreen.open_trainer(get_parent(), screen.data,
		screen.host.objects.events, name, foes)
	_battle.finished.connect(_on_battle_finished.bind(true))


## A start-menu row with a screen now: the Pokédex, party, bag,
## Pokégear and trainer card all open over the frozen field and hand
## back to the start menu on close.
func _open_menu_screen(action: String) -> void:
	if _menu_screen != null:
		return
	match action:
		"pokedex":
			var dex := Gen3PokedexScreen.new()
			dex.setup(screen.data, screen.host.objects.events)
			_menu_screen = dex
		"pokemon":
			var party := Gen3PartyScreen.new()
			party.setup(screen.data, screen.host.objects.events, "view")
			_menu_screen = party
		"bag":
			var bag := Gen3BagScreen.new()
			bag.setup(screen.data, screen.host.objects.events.bag)
			_menu_screen = bag
			bag.chosen.connect(_on_field_bag_chosen)
		"pokenav":
			var gear := Gen3PokegearScreen.new()
			gear.setup(screen.data, screen.host.objects.events,
				int(screen.host.objects.camera.header.get("region_map_section", -1)))
			_menu_screen = gear
		"player":
			var card := Gen3TrainerCardScreen.new()
			card.setup(screen.data, screen.host.objects.events,
				screen.play_seconds())
			_menu_screen = card
	get_parent().add_child(_menu_screen)
	if _menu_screen.has_signal("cancelled"):
		_menu_screen.cancelled.connect(_close_menu_screen)
	if _menu_screen.has_signal("closed"):
		_menu_screen.closed.connect(_close_menu_screen)


func _close_menu_screen() -> void:
	if _menu_screen != null:
		_menu_screen.queue_free()
		_menu_screen = null
	screen.return_to_start_menu()


## Field bag use: medicine opens the party to pick a target, balls and
## TMs cannot be used outside battle, revives need a fainted mon.
func _on_field_bag_chosen(item: int) -> void:
	_field_item = item
	if item <= 0:
		return
	var info: Dictionary = screen.data.item(item)
	var kind: String = Gen3BattleScreen.medicine_kind_for(screen.data, item)
	if kind == "none":
		return # Balls, TMs and key items wait for their own screens.
	_menu_party = Gen3PartyScreen.new()
	_menu_party.setup(screen.data, screen.host.objects.events, "item")
	get_parent().add_child(_menu_party)
	_menu_party.chosen.connect(_on_field_item_target)
	_menu_party.cancelled.connect(_on_field_item_cancelled)


func _on_field_item_target(index: int) -> void:
	var mon: Dictionary = screen.host.objects.events.party[index]
	var events: Gen3EventData = screen.host.objects.events
	if Gen3BattleScreen.apply_medicine(screen.data, events, mon, _field_item):
		events.bag.remove(_field_item, 1)
	_close_party_to_menu()


func _on_field_item_cancelled() -> void:
	_close_party_to_menu()


func _close_party_to_menu() -> void:
	if _menu_party != null:
		_menu_party.queue_free()
		_menu_party = null
	if _menu_screen != null:
		_menu_screen.queue_free()
		_menu_screen = null
	screen.return_to_start_menu()


func _on_battle_finished(outcome: int, is_trainer: bool) -> void:
	if _battle != null:
		_battle.queue_free()
		_battle = null
	if is_trainer:
		_settle_result(screen.host.finish_battle(outcome))
	else:
		_settle_result(screen.host.finish_wild_battle(outcome))


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
			if row["action"] in ["pokedex", "pokemon", "bag", "pokenav", "player"]:
				_open_menu_screen(String(row["action"]))
			elif row["action"] == Gen3FieldStartMenu.OPTION:
				screen.open_options()
			elif row["action"] == Gen3FieldStartMenu.RETIRE:
				screen.host.input.exit_safari() # The menu already unfroze the field; RETIRE returns to it, it does not reopen the menu.
			elif row["action"] == Gen3FieldStartMenu.SAVE:
				screen.begin_save()
			else:
				screen.return_to_start_menu()
		"trainer_battle":
			_open_battle_trainer(row)
		"wild_battle":
			_open_battle_wild(row)
		"mart":
			screen.host.finish_wait()
		"field_special":
			var special_name: String = String(row.get("name", ""))
			if special_name in ["StartWallClock", "Special_ViewWallClock"]:
				_open_wall_clock(special_name == "Special_ViewWallClock")
			elif special_name in ["ChangePokemonNickname", "NameRival"]:
				_open_naming_screen(row)
			elif special_name == "MomAmountInput":
				_open_money_screen(row)
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


## Mom's amount input: confirm writes the amount the script reads from
## VAR_0x8000, backing out writes 0, exactly as `mom_savings.c` does.
func _open_money_screen(row: Dictionary) -> void:
	if _money != null:
		return
	var mode: String = String(row.get("mode", "deposit"))
	var bag: Gen3Bag = screen.host.objects.events.bag
	var ceiling: int = bag.money if bag != null and mode == "deposit" \
		else screen.host.objects.events.mom_balance
	_money = Gen3MoneyScreen.new()
	get_parent().add_child(_money)
	_money.set_anchors_preset(Control.PRESET_FULL_RECT)
	_money.finished.connect(_on_money_finished)
	_money.cancelled.connect(_on_money_cancelled)
	_money.open(ceiling)


func _on_money_finished(amount: int) -> void:
	_close_money()
	screen.host.objects.events.var_set(Gen3ScriptServices.VAR_0X8000, amount)
	screen.host.finish_wait()
	screen.host.resume()


func _on_money_cancelled() -> void:
	_close_money()
	screen.host.objects.events.var_set(Gen3ScriptServices.VAR_0X8000, 0)
	screen.host.finish_wait()
	screen.host.resume()


func _close_money() -> void:
	if _money != null:
		_money.queue_free()
		_money = null
