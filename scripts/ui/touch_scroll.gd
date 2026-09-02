class_name TouchScroll
extends Node

## Drag-to-scroll for a `ScrollContainer` whose contents take their own input.
##
## Godot already scrolls a container with a finger — but it does it from
## `gui_input`, so the drag has to *reach* the container, and a `Button` is
## `MOUSE_FILTER_STOP`. The almanac's list is fifty-one rows with two points of
## separation between them, so the only place a phone could scroll it was those
## hairlines: every row swallowed the drag that started on it. The forge chart is
## worse — its cells are STOP so the item inspector can open on them, and there
## are no gaps at all.
##
## So the gesture is read in `_input`, which runs before any of that and sees the
## touch wherever it lands. Two consequences follow from taking it there:
##
## - **A drag that scrolls is marked handled**, so the container's own touch
##   handling never sees it as well. Without that, a drag begun in one of those
##   hairline gaps would scroll twice as far as the finger moved.
## - **A gesture that scrolled must not also press what it started on**, and the
##   press is Godot's, delivered by the emulated mouse. Nothing here cancels it:
##   changing a live press mid-gesture is what left this project's GUI
##   bookkeeping an event behind once already. Instead `TouchScroll.dragged()`
##   reports the gesture and the handler declines. A button acts on *release*, so
##   the flag is still standing when it is asked, and it is cleared by the next
##   press rather than by this one's release.
##
## Only real `InputEventScreenTouch`/`Drag` are watched, never the emulated
## mouse — the same rule press-and-hold follows in `Main`.

## How far a finger travels before it is scrolling rather than tapping.
const SLOP := 8.0

## A lifted finger keeps the list moving. Decay is per second, and anything
## slower than STOP is a finger that had already come to rest.
const FLING_DECAY := 5.0
const FLING_STOP := 12.0

## One gesture at a time, so one flag for all of them: the list and the page each
## have a driver and the finger is only ever in one.
static var _scrolled := false

var _scroll: ScrollContainer = null
var _index := -1
var _travel := 0.0
var _rest := 0.0
var _speed := 0.0


## Gives a ScrollContainer drag-to-scroll. The driver is a child of the
## container, so it is freed with it and survives a rotation the same way.
static func attach(scroll: ScrollContainer) -> TouchScroll:
	var driver := TouchScroll.new()
	driver.name = "TouchScroll"
	driver._scroll = scroll
	scroll.add_child(driver)
	return driver


## Whether the gesture in progress — or the one whose finger has just lifted —
## has scrolled. Anything that acts on a release inside a scrolling area asks
## this first, and does nothing if it is true.
static func dragged() -> bool:
	return _scrolled


func _ready() -> void:
	set_process(false)


func _input(event: InputEvent) -> void:
	if not _scroll.is_visible_in_tree():
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			# A new finger ends a fling and clears the verdict on the last one.
			_speed = 0.0
			set_process(false)
			_scrolled = false
			_travel = 0.0
			_rest = 0.0
			_index = event.index if _owns(event.position) else -1
		elif event.index == _index:
			_index = -1
			if _scrolled and absf(_speed) >= FLING_STOP:
				set_process(true)
		return

	if not (event is InputEventScreenDrag) or event.index != _index:
		return

	_travel += absf(event.relative.y)
	if _travel < SLOP:
		return
	_scrolled = true
	_speed = event.velocity.y
	_slide(-event.relative.y)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _index != -1 or absf(_speed) < FLING_STOP or not _slide(-_speed * delta):
		_speed = 0.0
		set_process(false)
		return
	_speed = move_toward(_speed, 0.0, absf(_speed) * FLING_DECAY * delta)


## Moves the view by `dy` points, and reports whether there was any room to move.
##
## `scroll_vertical` is an int, so the fraction is kept here: a slow drag arrives
## as a run of sub-pixel deltas, and rounding each one away on its own leaves a
## finger sliding over a list that never moves. A slide with nowhere left to go
## is what ends a fling, rather than a timer.
func _slide(dy: float) -> bool:
	_rest += dy
	var whole := int(_rest)
	_rest -= float(whole)
	if whole == 0:
		return true
	var was: int = _scroll.scroll_vertical
	_scroll.scroll_vertical = was + whole
	return _scroll.scroll_vertical != was


## Whether this container is the one the finger landed in.
##
## A hidden scrollbar means the content fits, and a swipe over something that
## cannot scroll belongs to whoever else wants it. The bar itself is excluded
## because it already drags itself.
func _owns(at: Vector2) -> bool:
	var bar := _scroll.get_v_scroll_bar()
	if not bar.visible:
		return false
	if bar.get_global_rect().has_point(at):
		return false
	return _scroll.get_global_rect().has_point(at)
