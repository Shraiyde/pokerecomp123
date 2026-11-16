class_name Gen3SavePrompt
extends RefCounted

## Emerald's save sequence, as the field drives it: the question, the
## overwrite question when a save already exists, `SAVING... DON'T TURN OFF
## THE POWER.` while the write runs, and `<PLAYER> saved the game.` Node free,
## with the write injected; the screen shows [member lines] and feeds answers
## back through [method answer]. A NO at either question, and a failed write,
## end the way a NO does: back to the Start menu, the field never frozen.

enum Step { ASK, OVERWRITE, SAVING, SAVED, FAILED, REFUSED, DONE }

const ASK_LINES: Array[String] = [
	"Would you like to", "save the game?",
]
const OVERWRITE_LINES: Array[String] = [
	"There is already a", "save file. Is it", "OK to overwrite it?",
]
const SAVING_LINES: Array[String] = [
	"SAVING... DON'T TURN", "OFF THE POWER.",
]
const SAVED_LINES: Array[String] = [
	"%s saved", "the game.",
]
const FAILED_LINES: Array[String] = [
	"The save failed.", "%s",
]

var step: Step = Step.ASK
var lines: Array[String] = []
## Whether the screen has shown this step's text yet, and whether its yes/no
## window is open; reset on every step change, so the screen never re-shows
## or re-opens what is already up.
var text_shown: bool = false
var question_open: bool = false
var result: Dictionary = {}
var _player_name: String = ""
var _write: Callable = Callable()
var _file_exists: bool = false


## [param write] takes no arguments and answers an "ok" key, with a "message"
## behind a false one. [param file_exists] is whether the slot already holds
## a save, which the overwrite question reads.
static func open(
	player_name: String, file_exists: bool, write: Callable
) -> Gen3SavePrompt:
	var prompt := Gen3SavePrompt.new()
	prompt._player_name = player_name
	prompt._file_exists = file_exists
	prompt._write = write
	prompt._enter(Step.ASK)
	return prompt


func text() -> String:
	return "\n".join(lines)


func finished() -> bool:
	return step in [Step.REFUSED, Step.DONE]


func answer(yes: bool) -> void:
	match step:
		Step.ASK:
			if not yes:
				_enter(Step.REFUSED)
			elif _file_exists:
				_enter(Step.OVERWRITE)
			else:
				_enter(Step.SAVING)
		Step.OVERWRITE:
			_enter(Step.SAVING if yes else Step.REFUSED)
		_:
			pass


## Runs the injected write once the SAVING text is up, and moves to the
## result step: SAVED on success, FAILED on a refusal.
func begin_write() -> void:
	if step != Step.SAVING:
		return
	result = _write.call() if _write.is_valid() \
		else {"ok": false, "message": "no save action"}
	_enter(Step.SAVED if bool(result.get("ok", false)) else Step.FAILED)


## The result text has been read; the sequence is over.
func acknowledge() -> void:
	match step:
		Step.SAVED:
			_enter(Step.DONE)
		Step.FAILED:
			_enter(Step.REFUSED)
		_:
			pass


func _enter(next: Step) -> void:
	step = next
	text_shown = false
	question_open = false
	match next:
		Step.ASK:
			lines.assign(ASK_LINES)
		Step.OVERWRITE:
			lines.assign(OVERWRITE_LINES)
		Step.SAVING:
			lines.assign(SAVING_LINES)
		Step.SAVED:
			lines.assign([SAVED_LINES[0] % _display_name(), SAVED_LINES[1]])
		Step.FAILED:
			lines.assign([
				FAILED_LINES[0],
				FAILED_LINES[1] % String(result.get("message", "unknown")).substr(0, 24),
			])
		_:
			lines.clear()


func _display_name() -> String:
	return _player_name if not _player_name.is_empty() else "PLAYER"
