class_name InputRing
extends RefCounted
## The player's input buffer: a ring of the current input frame plus the [constant HISTORY]
## frames before it that the player actually lived through (BUILD.md section 5, "Every cancel
## window is wider than it looks. Buffers are generous (8 f) and the buffer always stores the
## latest input"; ADR-0004). A press made 8 frames before a landing is therefore still in the
## ring on the landing frame (BUILD.md section 15, the first Movement line).
##
## Each tick the simulation either [method push]es a new frame (the player advanced) or
## [method merge]s it into the newest slot (the player is frozen in hitstop). Every press made
## during hitstop lands in that one slot, so on the first free frame it is only 1 frame old and
## fires there: hitstop never drops an input (BUILD.md section 6, "Hitstop is never applied to
## the player's own input reading").
##
## [method press_age] serves the latest unconsumed press of a button; [method consume] uses it
## and every older press of that button, so one press never fires two actions and an older tap
## never fires after a newer one. Hold durations are counted separately and are not limited by
## the ring's depth ([method held_frames]).

## Frames of history kept behind the current frame.
const HISTORY: int = 8
const SIZE: int = HISTORY + 1
## Hold counters saturate here (about 4.6 hours) so they never grow without bound.
const HOLD_CAP: int = 1000000

var _held: PackedInt32Array = PackedInt32Array()
var _pressed: PackedInt32Array = PackedInt32Array()
var _consumed: PackedInt32Array = PackedInt32Array()
## Presses spent by a parry ([method spend_presses]): a press parries once, used or not.
var _spent: PackedInt32Array = PackedInt32Array()
var _stick_x: PackedInt32Array = PackedInt32Array()
var _stick_y: PackedInt32Array = PackedInt32Array()
## Consecutive held frames per button, in InputFrame.BUTTONS order.
var _hold: PackedInt32Array = PackedInt32Array()
## Every button pressed in any slot (used or not): a query for a button with no press in the ring
## at all, the usual case, answers at once (the ring is read several times a tick).
var _any_pressed: int = 0
## Index of the newest slot.
var _head: int = 0
## How many slots hold real frames (grows to SIZE).
var _count: int = 0


func _init() -> void:
	_held.resize(SIZE)
	_pressed.resize(SIZE)
	_consumed.resize(SIZE)
	_spent.resize(SIZE)
	_stick_x.resize(SIZE)
	_stick_y.resize(SIZE)
	_hold.resize(InputFrame.BUTTONS.size())
	clear()


func clear() -> void:
	for i: int in range(SIZE):
		_held[i] = 0
		_pressed[i] = 0
		_consumed[i] = 0
		_spent[i] = 0
		_stick_x[i] = 0
		_stick_y[i] = 0
	_hold.fill(0)
	_any_pressed = 0
	_head = 0
	_count = 0


## The player advanced this tick: [param frame] becomes the newest slot.
func push(frame: InputFrame) -> void:
	_head = (_head + 1) % SIZE
	_count = mini(_count + 1, SIZE)
	_held[_head] = frame.held
	_pressed[_head] = frame.pressed
	_consumed[_head] = 0
	_spent[_head] = 0
	_stick_x[_head] = frame.stick_x
	_stick_y[_head] = frame.stick_y
	_any_pressed = 0
	for p: int in _pressed:
		_any_pressed |= p
	# A press starts a new hold even if the button never showed released between two frames (a
	# release and re-press inside one tick): a charged strike needs one unbroken hold (task 6
	# review, L1).
	for i: int in range(InputFrame.BUTTONS.size()):
		var bit: int = InputFrame.BUTTONS[i]
		if (frame.held & bit) == 0:
			_hold[i] = 0
		elif (frame.pressed & bit) != 0:
			_hold[i] = 1
		else:
			_hold[i] = mini(_hold[i] + 1, HOLD_CAP)


## The player is frozen this tick: fold [param frame] into the newest slot. Held state and stick
## take the latest values; presses accumulate.
func merge(frame: InputFrame) -> void:
	if _count == 0:
		push(frame)
		return
	_held[_head] = frame.held
	# A new press during hitstop is a fresh press even if the same button's earlier press in this
	# slot was already used: un-consume it.
	_consumed[_head] &= ~frame.pressed
	_spent[_head] &= ~frame.pressed
	_pressed[_head] |= frame.pressed
	_any_pressed |= frame.pressed
	# A button let go during hitstop starts its hold count again; re-pressing it does not
	# continue the old hold (a charged strike needs one unbroken hold).
	for i: int in range(InputFrame.BUTTONS.size()):
		if (
			(frame.held & InputFrame.BUTTONS[i]) == 0
			or (frame.pressed & InputFrame.BUTTONS[i]) != 0
		):
			_hold[i] = 0
	_stick_x[_head] = frame.stick_x
	_stick_y[_head] = frame.stick_y


## Age in player frames (0 = pressed this frame) of the latest unconsumed press of [param bit]
## no older than [param max_age], or -1 if there is none. [param max_age] is clamped to
## [constant HISTORY].
func press_age(bit: int, max_age: int = HISTORY) -> int:
	if max_age > HISTORY:
		assert(false, "input window %d exceeds the ring's %d frames" % [max_age, HISTORY])
	if (_any_pressed & bit) == 0:
		return -1
	var span: int = mini(mini(max_age, HISTORY) + 1, _count)
	var i: int = _head
	for age: int in range(span):
		if (_pressed[i] & ~_consumed[i] & bit) != 0:
			return age
		i = i - 1 if i > 0 else SIZE - 1
	return -1


## Age in player frames of the latest press of [param bit] no older than [param max_age], used or
## not, but not spent by a parry ([method spend_presses]), or -1 if there is none. A parry counts
## any attack press in its window, including one that also started a strike (docs/adr/0013).
func any_press_age(bit: int, max_age: int = HISTORY) -> int:
	if max_age > HISTORY:
		assert(false, "input window %d exceeds the ring's %d frames" % [max_age, HISTORY])
	if (_any_pressed & bit) == 0:
		return -1
	var span: int = mini(mini(max_age, HISTORY) + 1, _count)
	var i: int = _head
	for age: int in range(span):
		if (_pressed[i] & ~_spent[i] & bit) != 0:
			return age
		i = i - 1 if i > 0 else SIZE - 1
	return -1


## A parry spends every press of [param bit] in the ring: one press parries once, however long the
## parry's hitstop holds its age still (task 6 review, H4: one press parried every swing that
## landed in the 12 f). A press made during that hitstop is a fresh one ([method merge]).
func spend_presses(bit: int) -> void:
	for age: int in range(_count):
		_spent[_slot(age)] |= bit


## True if [param bit] has an unconsumed press no older than [param max_age] frames.
func has_press(bit: int, max_age: int = HISTORY) -> bool:
	return press_age(bit, max_age) >= 0


## Uses the latest press of [param bit]. Every older buffered press of the same button is used
## up with it: the buffer only ever serves the latest input (BUILD.md section 5), so an earlier
## tap can never fire a second action after the latest one did.
func consume(bit: int) -> void:
	for age: int in range(_count):
		_consumed[_slot(age)] |= bit


func is_held(bit: int) -> bool:
	return _count > 0 and (_held[_head] & bit) != 0


## Consecutive player frames, up to and including this one, that [param bit] has been held
## (0 if it is up). Not limited by the ring's depth, so long holds (the 24 f charged strike) work.
func held_frames(bit: int) -> int:
	var i: int = InputFrame.BUTTONS.find(bit)
	return _hold[i] if i >= 0 else 0


func stick_x() -> int:
	return _stick_x[_head] if _count > 0 else 0


func stick_y() -> int:
	return _stick_y[_head] if _count > 0 else 0


## The newest frame as an [InputFrame] (for display and tests).
func latest() -> InputFrame:
	if _count == 0:
		return InputFrame.new()
	return InputFrame.make(_held[_head], _pressed[_head], _stick_x[_head], _stick_y[_head])


## The frame [param age] frames ago, or an empty frame if the ring is not that deep yet.
func frame_at(age: int) -> InputFrame:
	if age < 0 or age >= _count:
		return InputFrame.new()
	var i: int = _slot(age)
	return InputFrame.make(_held[i], _pressed[i], _stick_x[i], _stick_y[i])


func depth() -> int:
	return _count


func hash_into(h: StateHasher) -> void:
	h.add_int(_count)
	for age: int in range(_count):
		var i: int = _slot(age)
		h.add_int(_held[i])
		h.add_int(_pressed[i])
		h.add_int(_consumed[i])
		h.add_int(_spent[i])
		h.add_int(_stick_x[i])
		h.add_int(_stick_y[i])
	for hold: int in _hold:
		h.add_int(hold)


func copy_from(other: InputRing) -> void:
	_held = other._held.duplicate()
	_pressed = other._pressed.duplicate()
	_consumed = other._consumed.duplicate()
	_spent = other._spent.duplicate()
	_stick_x = other._stick_x.duplicate()
	_stick_y = other._stick_y.duplicate()
	_hold = other._hold.duplicate()
	_head = other._head
	_count = other._count


func _slot(age: int) -> int:
	return (_head - age + SIZE) % SIZE
