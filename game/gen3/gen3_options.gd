class_name Gen3Options
extends RefCounted

## Emerald's OPTION rows (`pokehns/src/option_menu.c`, `sTabItems_Main` and
## `sTabItems_Sound`'s SOUND row, `SetDefaultOptions` in `new_game.c`):
## TEXT SPEED SLOW/MID/FAST/FASTER, BATTLE SCENE ON/OFF, BATTLE STYLE
## SHIFT/SET, BUTTON MODE NORMAL/LR/L=A, FRAME TYPE 1-20, SOUND MONO/STEREO,
## CANCEL. The ROM's other tabs (FOLLOWER, AUTORUN, FAST BATTLES, MUSIC...)
## are H&S challenge settings with no engine consumer yet, so they are not
## rows here. `battle_scene`, `battle_style_set` and `stereo` live on the
## shared [Gen2Options] because both generations mean the same by them.

const OPT_TEXT_SPEED: int = 0
const OPT_BATTLE_SCENE: int = 1
const OPT_BATTLE_STYLE: int = 2
const OPT_BUTTON_MODE: int = 3
const OPT_FRAME: int = 4
const OPT_SOUND: int = 5
const OPT_CANCEL: int = 6
const NUM_OPTIONS: int = 7

const TEXT_SPEED_VALUES: Array[String] = ["SLOW", "MID", "FAST", "FASTER"]
const BUTTON_MODE_VALUES: Array[String] = ["NORMAL", "LR", "L=A"]
const FRAME_COUNT: int = 20 # `WINDOW_FRAMES_COUNT` in `text_window.h`.
const BUTTON_MODE_COUNT: int = 3 # `OPTIONS_BUTTON_MODE_[NORMAL/LR/L_EQUALS_A]`.

const ROWS: Array[Dictionary] = [
	{"index": OPT_TEXT_SPEED, "label": "TEXT SPEED"},
	{"index": OPT_BATTLE_SCENE, "label": "BATTLE SCENE"},
	{"index": OPT_BATTLE_STYLE, "label": "BATTLE STYLE"},
	{"index": OPT_BUTTON_MODE, "label": "BUTTON MODE"},
	{"index": OPT_FRAME, "label": "FRAME"},
	{"index": OPT_SOUND, "label": "SOUND"},
	{"index": OPT_CANCEL, "label": "CANCEL"},
]

## `OPTIONS_TEXT_SPEED_[SLOW/MID/FAST/INSTANT]`; new game defaults FAST.
var text_speed: int = 2
var battle_scene: bool = true
var battle_style_set: bool = false
var button_mode: int = 0
var frame: int = 0
var stereo: bool = false
var cursor: int = 0


func size() -> int:
	return ROWS.size()


func move(delta: int) -> bool:
	if delta == 0:
		return false
	cursor = wrapi(cursor + signi(delta), 0, size())
	return true


## CANCEL is the only row A answers: every other handler reads left and
## right alone, so A on them does nothing.
func is_cancel() -> bool:
	return cursor == size() - 1


## Left or right on the selected row; the toggles answer either direction
## with the other value, the cycles wrap. Returns whether a value changed.
func adjust(delta: int) -> bool:
	if delta == 0:
		return false
	var step: int = signi(delta)
	match cursor:
		OPT_TEXT_SPEED:
			text_speed = wrapi(text_speed + step, 0, TEXT_SPEED_VALUES.size())
		OPT_BATTLE_SCENE:
			battle_scene = not battle_scene
		OPT_BATTLE_STYLE:
			battle_style_set = not battle_style_set
		OPT_BUTTON_MODE:
			button_mode = wrapi(button_mode + step, 0, BUTTON_MODE_COUNT)
		OPT_FRAME:
			frame = wrapi(frame + step, 0, FRAME_COUNT)
		OPT_SOUND:
			stereo = not stereo
		_:
			return false
	return true


## The stored choices, shared with Gen 2 through [Gen2OptionsStore].
static func load() -> Gen3Options:
	var options := Gen3Options.new()
	var stored: Gen2Options = Gen2OptionsStore.current()
	options.text_speed = clampi(stored.gen3_text_speed, 0, TEXT_SPEED_VALUES.size() - 1)
	options.battle_scene = stored.battle_scene
	options.battle_style_set = stored.battle_style_set
	options.button_mode = clampi(stored.gen3_button_mode, 0, BUTTON_MODE_COUNT - 1)
	options.frame = clampi(stored.gen3_frame, 0, FRAME_COUNT - 1)
	options.stereo = stored.stereo
	return options


## Writes the choices back to the shared store, so they survive restarts.
func save() -> bool:
	var stored: Gen2Options = Gen2OptionsStore.current()
	stored.gen3_text_speed = text_speed
	stored.battle_scene = battle_scene
	stored.battle_style_set = battle_style_set
	stored.gen3_button_mode = button_mode
	stored.gen3_frame = frame
	stored.stereo = stereo
	return Gen2OptionsStore.save(stored)


## The [Gen3FieldMessage] speed index for this text speed: the ROM's
## `sTextSpeedFrameDelays` is 8/4/1/1, and the message's own `speeds` table
## is [8, 4, 1], so FASTER paces like FAST.
func message_text_speed() -> int:
	return mini(text_speed, 2)


## One `{index, label, value}` per row for a renderer; CANCEL carries an
## empty value, since the source prints no setting beside it.
func rows() -> Array:
	var built: Array = []
	for row: Dictionary in ROWS:
		built.append({
			"index": int(row["index"]),
			"label": String(row["label"]),
			"value": _value_label(int(row["index"])),
		})
	return built


func _value_label(index: int) -> String:
	match index:
		OPT_TEXT_SPEED:
			return TEXT_SPEED_VALUES[clampi(text_speed, 0, TEXT_SPEED_VALUES.size() - 1)]
		OPT_BATTLE_SCENE:
			return "ON" if battle_scene else "OFF"
		OPT_BATTLE_STYLE:
			return "SET" if battle_style_set else "SHIFT"
		OPT_BUTTON_MODE:
			return BUTTON_MODE_VALUES[clampi(button_mode, 0, BUTTON_MODE_COUNT - 1)]
		OPT_FRAME:
			return "TYPE %d" % (clampi(frame, 0, FRAME_COUNT - 1) + 1)
		OPT_SOUND:
			return "STEREO" if stereo else "MONO"
		_:
			return ""
