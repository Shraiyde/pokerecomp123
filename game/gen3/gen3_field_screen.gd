class_name Gen3FieldScreen
extends RefCounted # `overworld.c`'s field frame around [Gen3ScriptHost]: it answers the requests it can and returns those only a screen above it can: battles, the START menu, sounds.

const SIZE := Vector2i(240, 160)
const HOST_FINISHED: Array[String] = ["waitse", "waitfanfare", "waitmoncry", "fadeoutbgm", "hidemonpic"] # No GBA audio or pic windows yet.
const FADES: Array[String] = ["fadescreen", "fadescreenspeed", "fadescreenswapbuffers"]
const DOOR_COMMANDS: Array[String] = ["opendoor", "closedoor", "setdooropen", "setdoorclosed"]

var data: GameData
var host: Gen3ScriptHost
var vram: Gen3FieldVram
var weather: Gen3FieldWeather
var doors: Gen3FieldDoor
var warp: Gen3FieldWarp
var message: Gen3FieldMessage
var menu: Gen3FieldMenu
var start_menu: Gen3FieldStartMenu
var options_menu: Gen3FieldOptionsMenu
## The slot this session saves back to: 0 by default, or the slot it was
## loaded from. The world screen sets it; the launcher stages it.
var save_slot: int = 0
var _opened_ms: int = 0 # When this field opened, for the play timer.
var _play_base: int = 0 # Play seconds a loaded save already carried.
var _follower_slot: int = -1 # The follower mon's object slot, or -1 for none.
var _follower_species: int = 0
var _follower_map: String = ""
var _follower_trail: Array[Vector2i] = [] # The player's recent cells, newest first.
var _save_prompt: Gen3SavePrompt = null # The save sequence in progress, or null on the open field.
var _keys_held: bool = false
var _keys_pressed: bool = false
var _pressed: Array[int] = []
var _waiting: Callable = Callable()
var _requests: Array = []


static func open(game: GameData, group: int, number: int, at: Vector2i, direction: int = 1, gender: int = 0,
		flags: int = Gen3PlayerAvatar.Flag.ON_FOOT, forced_weather: int = -1,
		events: Gen3EventData = null) -> Gen3FieldScreen: # Standing on layout cell [param at]; null where the player cannot stand. A loaded save passes its own events in, so the objects spawn under the saved flags.
	var camera: Gen3FieldCamera = Gen3FieldCamera.open(game, group, number, at)
	if camera == null:
		return null
	var screen := Gen3FieldScreen.new()
	screen.data = game
	screen.vram = Gen3FieldVram.load(camera.grid.primary, camera.grid.secondary)
	events = events if events != null else Gen3EventData.new(game.id)
	if events.player_name.is_empty(): # oak_speech_hns.c presets the name GOLD (boy) / KRIS (girl); the intro that asks is skipped, so a new game otherwise talks to "<PLAYER>".
		events.player_name = "KRIS" if gender == 1 else "GOLD"
	var objects := Gen3ObjectEvents.new(camera, events, screen.vram.palette)
	screen.weather = Gen3FieldWeather.new(game, screen.vram.palette, events)
	objects.sprites.weather = screen.weather
	screen.weather.sprites.camera = camera
	if forced_weather < 0:
		screen.weather.set_saved_from_header(camera.header)
	else:
		screen.weather.set_saved(forced_weather)
	screen.weather.start()
	screen.weather.resume_paused()
	var avatar := Gen3PlayerAvatar.open(objects, at + Vector2i.ONE * Gen3MapGrid.MAP_OFFSET, direction, gender)
	if avatar == null:
		return null
	avatar.transition(flags)
	avatar.track_camera()
	objects.spawn_in_view()
	screen.host = Gen3ScriptHost.new(avatar)
	screen.host.field_tasks = screen._run_tasks
	screen.warp = Gen3FieldWarp.new(screen)
	screen.message = Gen3FieldMessage.new(game.world_text_box(), screen.host.input.engine, screen.vram.palette)
	screen.menu = Gen3FieldMenu.new(screen.message, screen.host.input.engine)
	screen.start_menu = Gen3FieldStartMenu.new(screen.message, screen.host.input.engine, game.world_start_menu(),
		screen.host.services.placeholders)
	screen.options_menu = Gen3FieldOptionsMenu.new(screen.message, screen.host.input.engine)
	screen._apply_options()
	screen.doors = Gen3FieldDoor.new(camera, screen.vram, screen.host.input, events)
	screen._opened_ms = Time.get_ticks_msec()
	screen.vram.palette.faded.fill(0) # FieldCB_FadeTryShowMapPopup's FadeInFromBlack.
	screen.weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)
	return screen


## A saved game, reopened where it was saved: the saved map, cell and facing,
## with the saved flags, vars, party, bag, clock and Mom's state behind it.
## Null where the save is not valid or the player cannot stand there.
static func open_from_save(game: GameData, save: Gen3SaveData) -> Gen3FieldScreen:
	if save == null:
		return null
	var events := Gen3EventData.from_dict(save.events, game)
	if events == null:
		return null
	var screen := open(game, save.map_group, save.map_number, save.player_cell, save.facing,
		events.player_gender, Gen3PlayerAvatar.Flag.ON_FOOT, -1, events)
	if screen != null:
		screen.save_slot = save.slot
		screen._play_base = save.play_time_seconds
	return screen


func frame(held: Array[int] = [], pressed: Array[int] = []) -> Array: # One frame: `CB1_Overworld`, then `OverworldBasic` and VBlank's palette transfer. What the field could not answer returns.
	var avatar: Gen3PlayerAvatar = host.avatar
	var previous: Vector2i = avatar.object().pixel_position
	_keys_held = PokeButton.A in held or PokeButton.B in held
	_keys_pressed = PokeButton.A in pressed or PokeButton.B in pressed
	_pressed = pressed
	var out: Array = _answer(host.step(held, pressed))
	out.append_array(_requests)
	_requests.clear()
	var camera: Gen3FieldCamera = host.objects.camera
	if host.avatar == avatar and camera.update(avatar.object().pixel_position - previous) != Vector2i.ZERO:
		host.objects.follow_camera()
	_update_follower()
	if camera.crossed:
		_cross_connection()
	weather.sprites.animate(camera.sprite_coord_offset())
	vram.palette.update_fade()
	vram.step()
	vram.palette.transfer()
	return out


## The follower mon (`follower_npc` in the ROM): the lead party mon's
## overworld sprite trailing one cell behind the player. It respawns on a
## map change, swaps when the lead changes, and never blocks a step.
func _update_follower() -> void:
	var objects: Gen3ObjectEvents = host.objects
	var events: Gen3EventData = objects.events
	if events.game != RomRegistry.HEARTSOUL:
		return
	var species: int = 0
	for mon: Dictionary in events.party:
		if not bool(mon.get("egg", false)):
			species = int(mon.get("species", 0))
			break
	var player: Gen3ObjectEvents.ObjectEvent = host.avatar.object()
	var map_key: String = "%d:%d" % [objects.camera.group, objects.camera.number]
	if map_key != _follower_map:
		_follower_map = map_key
		_follower_slot = -1
		_follower_trail.clear()
	if species == 0:
		if _follower_slot >= 0:
			objects.objects[_follower_slot].active = false
			_follower_slot = -1
			_follower_species = 0
		return
	if _follower_slot < 0:
		var template: Dictionary = Gen3ObjectEvents.EMPTY_TEMPLATE.duplicate()
		template.merge({"local_id": 0xFE, "graphics_id": 0x4000 | species,
			"movement_type": 0, "x": player.current.x - Gen3MapGrid.MAP_OFFSET,
			"y": player.current.y - Gen3MapGrid.MAP_OFFSET}, true)
		_follower_slot = objects.spawn(template, objects.camera.number, objects.camera.group)
		if _follower_slot < 0:
			return
		objects.objects[_follower_slot].is_follower = true
		_follower_species = species
		_follower_trail = [player.current]
		return
	var follower: Gen3ObjectEvents.ObjectEvent = objects.objects[_follower_slot]
	if species != _follower_species:
		_follower_species = species
		objects.set_graphics_id(follower, 0x4000 | species)
	if _follower_trail.is_empty() or _follower_trail[0] != player.current:
		_follower_trail.push_front(player.current)
		while _follower_trail.size() > 2:
			_follower_trail.pop_back()
		if _follower_trail.size() > 1 and follower.current != _follower_trail[1]:
			Gen3ObjectEvents.move_to_map_coords(follower, _follower_trail[1])
			var step: Vector2i = player.current - follower.current
			Gen3ObjectEvents.set_direction(follower,
				Gen3ObjectEvents.Direction.EAST if step.x > 0 else Gen3ObjectEvents.Direction.WEST \
				if step.x < 0 else Gen3ObjectEvents.Direction.SOUTH if step.y > 0 \
				else Gen3ObjectEvents.Direction.NORTH)


func picture() -> Image:
	var objects: Gen3ObjectEvents = host.objects
	var origin: Vector2i = objects.camera.screen_origin()
	var overlay: Dictionary = objects.field_move_mon.screen()
	return vram.draw_screen(objects.camera.grid, origin, SIZE, objects.sprites.oam(objects, origin), weather.bldalpha,
		overlay if not overlay.is_empty() else message.overlay())


func return_to_start_menu(faded: bool = true) -> void: # CB2_ReturnToFieldWithOpenMenu from a `start_menu_action`'s screen; a declined save never left the field.
	start_menu.open(host.objects.events)
	if faded:
		weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)


## SAVE from the Start menu: the Start menu window stays up under the prompt
## and the field stays frozen, exactly as the menu left it. A second SAVE
## while one is already running is ignored.
func begin_save() -> void:
	if _save_prompt != null:
		return
	var events: Gen3EventData = host.objects.events
	# start_menu.c::SaveFileExistsCallback: Heart & Soul skips the overwrite
	# question for the save already in the slot (`#if IS_HNS` goes straight
	# to the SAVING message); the slot is per-cartridge, so a file there is
	# always the same file. The other Gen 3 games still ask.
	var ask_overwrite: bool = data.id != RomRegistry.HEARTSOUL \
		and Gen3SaveStore.exists(data.id, data.sha1, save_slot)
	_save_prompt = Gen3SavePrompt.open(
		events.player_name,
		ask_overwrite,
		_write_save
	)


## The write the prompt runs: the field as it stands, into this session's slot.
func _write_save() -> Dictionary:
	var events: Gen3EventData = host.objects.events
	var player: Gen3ObjectEvents.ObjectEvent = host.avatar.object()
	var cell: Vector2i = player.current - Vector2i.ONE * Gen3MapGrid.MAP_OFFSET
	var save := Gen3SaveData.capture(data, save_slot, events,
		host.objects.camera.group, host.objects.camera.number, cell, player.facing,
		play_seconds())
	if save == null:
		return {"ok": false, "message": "the save could not be built"}
	return Gen3SaveStore.save(save, data)


## One frame of the save sequence, in place of the field's own message, menu
## and Start-menu steps: the prompt's answers are consumed here, never handed
## to the script host, whose `VAR_RESULT` and message state belong to scripts.
func _step_save(out: Array) -> void:
	var prompt := _save_prompt
	if prompt == null:
		return
	message.step(_keys_held, _keys_pressed, out)
	match prompt.step:
		Gen3SavePrompt.Step.ASK, Gen3SavePrompt.Step.OVERWRITE:
			if not prompt.text_shown:
				message.show(Gen3Text.encode(prompt.text()), "message", 0)
				prompt.text_shown = true
			elif not message.printing and not prompt.question_open:
				menu.open({"choices": ["YES", "NO"], "yes_no": true, "default": 0})
				prompt.question_open = true
			elif prompt.question_open:
				var choice: int = menu.step(_pressed, out)
				if choice != Gen3FieldMenu.NOTHING:
					prompt.answer(choice == 1)
					if prompt.finished():
						_end_save()
		Gen3SavePrompt.Step.SAVING:
			if not prompt.text_shown:
				message.show(Gen3Text.encode(prompt.text()), "messageinstant", 0)
				prompt.text_shown = true
				prompt.begin_write()
		Gen3SavePrompt.Step.SAVED, Gen3SavePrompt.Step.FAILED:
			if not prompt.text_shown:
				message.show(Gen3Text.encode(prompt.text()), "message", 0)
				prompt.text_shown = true
			elif not message.printing and (PokeButton.A in _pressed or PokeButton.B in _pressed):
				prompt.acknowledge()
				_end_save()


## The sequence is over, saved or declined: the message box goes away and the
## Start menu comes back up, unfaded, since SAVE never faded out of it.
func _end_save() -> void:
	_save_prompt = null
	message.hide()
	return_to_start_menu(false)


## OPTION from the Start menu: the field stays frozen (the menu froze it)
## until the player is back at the Start menu, which unfreezes exactly once
## on CLOSE. The fade from black is the same one [method return_to_start_menu] runs.
func open_options() -> void:
	options_menu.open()
	weather.fade_screen(Gen3FieldWeather.Fade.FROM_BLACK, 0)


## The stored text speed, applied to the message printer on field open and
## again when the OPTION screen closes; the other rows are stored for the
## screens that will read them (battles, button mode, frame).
func _apply_options() -> void:
	message.text_speed = Gen3Options.load().message_text_speed()


## Seconds on this clock: the loaded save's carried time plus this session.
func play_seconds() -> int:
	return _play_base + (Time.get_ticks_msec() - _opened_ms) / 1000


func request(row: Dictionary) -> void: # A task's request for the next [method frame]'s return.
	_requests.append(row)


func load_warp() -> void: # `WarpIntoMap` and `CB2_LoadMap`'s steps: everything the map load resets, around the host's own.
	var palette: Gen3Palette = vram.palette
	palette.reset_fade()
	weather.task = Gen3FieldWeather.Task.NONE
	_waiting = Callable()
	message.hide()
	var loaded: Array[Dictionary] = host.complete_warp()
	var camera: Gen3FieldCamera = host.objects.camera
	vram = Gen3FieldVram.load(camera.grid.primary, camera.grid.secondary, palette)
	doors = Gen3FieldDoor.new(camera, vram, host.input, host.objects.events)
	weather.sprites.camera = camera
	_requests.append_array(_answer(loaded))


func _run_tasks(requests: Array) -> Array:
	var out: Array = _answer(requests)
	if not _waiting.is_null() and _waiting.call():
		_waiting = Callable()
		host.finish_wait()
	warp.step(out)
	if _save_prompt != null:
		_step_save(out)
	else:
		if message.step(_keys_held, _keys_pressed, out):
			host.finish_message()
		var choice: int = menu.step(_pressed, out)
		if choice != Gen3FieldMenu.NOTHING:
			host.choose(choice)
		_step_start_menu(out)
		_step_options(out)
	doors.step()
	weather.run_tasks()
	return out


func _step_start_menu(out: Array) -> void:
	var action: String = start_menu.step(_pressed, out, vram.palette.fade_active)
	match action:
		"": pass
		Gen3FieldStartMenu.FADE: weather.fade_screen(Gen3FieldWeather.Fade.TO_BLACK, 0)
		Gen3FieldStartMenu.CLOSE: host.unfreeze_field()
		_:
			if action == Gen3FieldStartMenu.RETIRE:
				host.unfreeze_field()
			out.append({"kind": "start_menu_action", "action": action})


func _step_options(out: Array) -> void:
	var action: String = options_menu.step(_pressed, out, vram.palette.fade_active)
	match action:
		"": pass
		Gen3FieldOptionsMenu.FADE: weather.fade_screen(Gen3FieldWeather.Fade.TO_BLACK, 0)
		Gen3FieldOptionsMenu.CLOSE:
			_apply_options()
			return_to_start_menu()


func _cross_connection() -> void: # New tilesets and the door cells, which are BG tilemap writes the crossing's redraw replaces.
	var camera: Gen3FieldCamera = host.objects.camera
	vram.door_cells.clear()
	var palette: Gen3Palette = vram.palette
	vram = Gen3FieldVram.load(camera.grid.primary, camera.grid.secondary, palette)
	doors = Gen3FieldDoor.new(camera, vram, host.input, host.objects.events)


func _answer(requests: Array) -> Array:
	var out: Array = []
	for row: Dictionary in requests:
		if not _answered(row):
			out.append(row)
	return out


func _answered(row: Dictionary) -> bool:
	var kind: String = row["kind"]
	if kind == "warp":
		warp.begin(row, _requests)
	elif kind in HOST_FINISHED:
		host.finish_wait()
	elif kind in FADES:
		_fade(row)
	elif kind in DOOR_COMMANDS:
		_door(kind, row["operands"])
	elif kind == "message":
		message.show(Gen3Text.encode(row["text"]), row["mode"], int(row["color"]), host.signpost)
		if not message.printing:
			host.finish_message()
	elif kind == "close_message":
		message.hide()
	elif kind == "menu":
		menu.open(row)
	elif kind == "start_menu":
		host.freeze_for_menu()
		start_menu.open(host.objects.events)
	elif kind == "waitdooranim":
		_waiting = func() -> bool: return not doors.running
	elif kind == "waitfieldeffect":
		var effect: int = int(row["operands"][0])
		_waiting = func() -> bool: return not host.objects.field_effect_active(effect)
	else:
		return kind in ["map_loaded", "redraw_map"]
	return true


func _fade(row: Dictionary) -> void: # ScrCmd_fadescreen and its two kin hold on IsPaletteNotActive.
	var operands: Array = row["operands"]
	weather.fade_screen(int(operands[0]), int(operands[1]) if operands.size() > 1 else 0)
	_waiting = func() -> bool: return not vram.palette.fade_active


func _door(kind: String, operands: Array) -> void:
	var cell: Vector2i = Vector2i(int(operands[0]), int(operands[1])) + Vector2i.ONE * Gen3MapGrid.MAP_OFFSET
	match kind:
		"opendoor":
			_requests.append({"kind": "sound", "name": doors.sound(cell)})
			doors.open(cell)
		"closedoor": doors.close(cell)
		"setdooropen": doors.set_opened(cell)
		"setdoorclosed": doors.set_closed(cell)
