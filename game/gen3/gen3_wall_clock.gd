class_name Gen3WallClock
extends Control

## The wall clock face the bedroom clock opens: the ROM's `CB2_StartWallClock`.
## A round face with an hour hand and a minute hand, the time in digits below,
## and AM/PM. Left moves the hands back, Right moves them forward (hold to go
## faster), A confirms the time, B steps back out without changing it. The
## script that called `StartWallClock` waits on this screen, then carries on
## with the clock set and the story flag behind it.

signal finished(hour: int, minute: int)
signal cancelled

const FACE_RADIUS: float = 110.0
const HOUR_HAND: float = 62.0
const MINUTE_HAND: float = 92.0
const FACE_COLOR: Color = Color(0.96, 0.94, 0.88)
const FACE_BORDER: Color = Color(0.25, 0.20, 0.12)
const HAND_COLOR: Color = Color(0.12, 0.10, 0.08)
const TEXT_COLOR: Color = Color(0.95, 0.95, 0.92)

var hour: int = 12
var minute: int = 0

var _speed: int = 0
var _held_dir: int = 0
var _a_held: bool = false
var _b_held: bool = false
var _r_held: bool = false
var _done: bool = false
var _confirming: bool = false # A was pressed: A now means YES, B means NO.
var _hour_mode: bool = false # R toggles: LEFT/RIGHT move the hour hand instead of the minute hand.
var _view_only: bool = false # `Special_ViewWallClock` shows the time; only `StartWallClock` lets the player set it.


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw) # A layout resize after the first draw must redraw the face at the new size.


func open(start_hour: int, start_minute: int, view_only: bool = false) -> void:
	hour = start_hour % 24
	minute = start_minute % 60
	_view_only = view_only
	# A button already held when the face opens — the A that dismissed the
	# message before it — is not a fresh press, so it must not confirm.
	_a_held = PokeButton.held(PokeButton.A)
	_b_held = PokeButton.held(PokeButton.B)
	_r_held = PokeButton.held(PokeButton.R)
	_done = false
	_confirming = false
	_hour_mode = false
	queue_redraw()


func _draw() -> void:
	# The skin cutout's centre, not the viewport's: Gen3WorldScreen.SCREEN_RECT
	# is y 0.0888..0.4192, so 0.254 centres the face in the game screen.
	var center: Vector2 = size * Vector2(0.5, 0.254)
	# Face.
	draw_circle(center, FACE_RADIUS + 8.0, FACE_BORDER)
	draw_circle(center, FACE_RADIUS, FACE_COLOR)
	# Hour ticks.
	for i: int in 12:
		var angle: float = TAU * float(i) / 12.0 - PI / 2.0
		var inner: Vector2 = center + Vector2(cos(angle), sin(angle)) * (FACE_RADIUS - 12.0)
		var outer: Vector2 = center + Vector2(cos(angle), sin(angle)) * (FACE_RADIUS - 2.0)
		draw_line(inner, outer, FACE_BORDER, 3.0)
	# Hands. 12 o'clock is straight up.
	var minute_angle: float = TAU * float(minute) / 60.0 - PI / 2.0
	var hour_angle: float = TAU * (float(hour % 12) + float(minute) / 60.0) / 12.0 - PI / 2.0
	draw_line(center, center + Vector2(cos(minute_angle), sin(minute_angle)) * MINUTE_HAND, HAND_COLOR, 3.0)
	draw_line(center, center + Vector2(cos(hour_angle), sin(hour_angle)) * HOUR_HAND, HAND_COLOR, 5.0)
	draw_circle(center, 5.0, HAND_COLOR)
	# Digital time + AM/PM below the face.
	var text: String = _time_text()
	var font: Font = ThemeDB.fallback_font
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 44)
	draw_string(font, center + Vector2(-text_size.x * 0.5, FACE_RADIUS + 64.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, TEXT_COLOR)
	var hint: String = "B: back" if _view_only else ("Set the time to %s?  A: YES  B: NO" % _time_text() if _confirming else ("R: hour/minute    LEFT / RIGHT: %s    A: confirm    B: back" % ("HOUR" if _hour_mode else "MINUTES")))
	var hint_size: Vector2 = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
	draw_string(font, center + Vector2(-hint_size.x * 0.5, FACE_RADIUS + 104.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT_COLOR)


func _process(_delta: float) -> void:
	var dir: int = 0
	if PokeButton.held(PokeButton.LEFT):
		dir = -1
	elif PokeButton.held(PokeButton.RIGHT):
		dir = 1
	if dir != _held_dir:
		_held_dir = dir
		_speed = 0
	if dir != 0 and not _view_only and not _confirming:
		_speed = mini(_speed + 1, 12)
		# Step the selected hand; faster the longer it is held.
		var step: int = 1 if _speed < 6 else 5
		if _hour_mode:
			_advance_minutes(dir * step * 60)
		else:
			_advance_minutes(dir * step)
		queue_redraw()
	var r_held: bool = PokeButton.held(PokeButton.R)
	if r_held and not _r_held and not _view_only and not _confirming:
		_hour_mode = not _hour_mode # R switches the hand being set.
		queue_redraw()
	_r_held = r_held
	# A and B are polled like the directions, on the rising edge: the touch
	# pad's synthetic actions never reach `_unhandled_input`, so the face
	# could never be confirmed or cancelled from the on-screen buttons.
	var a_held: bool = PokeButton.held(PokeButton.A)
	if a_held and not _a_held:
		if _view_only:
			_cancel()
		else:
			_confirm()
	_a_held = a_held
	var b_held: bool = PokeButton.held(PokeButton.B)
	if b_held and not _b_held:
		if _confirming:
			_confirming = false # NO steps back to setting the time.
			queue_redraw()
		else:
			_cancel()
	_b_held = b_held


func _time_text() -> String:
	var period: String = "AM" if hour < 12 else "PM"
	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, period]


func _confirm() -> void:
	if _done:
		return
	if not _confirming:
		# A asks once more, as the ROM's clock does: YES sets it, NO steps back to setting.
		_confirming = true
		queue_redraw()
		return
	_done = true
	finished.emit(hour, minute)


func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()


func _advance_minutes(delta: int) -> void:
	var total: int = hour * 60 + minute + delta
	total = posmod(total, 24 * 60)
	hour = total / 60
	minute = total % 60


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"gen2_a"):
		if _view_only:
			_cancel()
		else:
			_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"gen2_b"):
		_cancel()
		get_viewport().set_input_as_handled()
