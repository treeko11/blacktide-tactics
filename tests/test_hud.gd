extends TestCase

## Invariants of the HUD that are invisible until something stops responding.
##
## These are not "does it look right" tests — a screenshot answers that better.
## They are the rules whose breakage looks like the game ignoring the player, and
## which therefore get reported as something else entirely.

## Nothing in the toast layer may take a click.
##
## Toasts are decoration hovering over live controls, and `mouse_filter` is per
## node: setting IGNORE on the toast panel says nothing about the containers
## inside it, and a bare `Container` defaults to STOP where a `Label` defaults to
## IGNORE. So every toast was a five-second invisible hit-test blocker over
## whatever it covered — the cargo hold on a sideways phone, where press-and-hold
## stopped opening the inspector, and the right of the board on a desktop, where
## a pirate could not be dropped while one was up.
##
## Checked structurally rather than by aiming a click, because the failure is not
## about any one thing the toast happens to cover.
func test_nothing_in_the_toast_layer_is_hit_testable() -> void:
	var layer := ToastLayer.new()
	Engine.get_main_loop().root.add_child(layer)

	# A notice needs nothing from the content tables, so this stays a HUD test.
	events().notice.emit("Not enough gold", &"warn")
	assert_gt(layer.get_child_count(), 0, "the layer did not build a toast")

	var blockers := PackedStringArray()
	_collect_blockers(layer, "ToastLayer", blockers)
	assert_true(blockers.is_empty(),
		"these would swallow input aimed at whatever the toast covers: %s"
		% ", ".join(blockers))

	layer.free()


## `queue_free()` does not remove the node, and a loop that waits for it to spins
## forever.
##
## This is the fact the whole freeze rested on, so it is asserted rather than
## remembered: a child that has been queued is still a child, still counted, for
## the rest of the frame.
func test_queue_free_leaves_the_child_in_place() -> void:
	var box := VBoxContainer.new()
	Engine.get_main_loop().root.add_child(box)
	for i in 3:
		box.add_child(Label.new())

	box.get_child(2).queue_free()
	assert_eq(box.get_child_count(), 3,
		"queue_free() dropped the child immediately — if this ever becomes true, "
		+ "the comment in UITheme.trim_children is the thing to correct")

	box.remove_child(box.get_child(2))
	assert_eq(box.get_child_count(), 2, "remove_child() did not detach it either")

	box.free()


## The two helpers empty and trim *now*, not at the end of the frame.
func test_the_container_helpers_take_effect_immediately() -> void:
	var box := VBoxContainer.new()
	Engine.get_main_loop().root.add_child(box)

	for i in 6:
		var line := Label.new()
		line.name = "line%d" % i
		box.add_child(line)

	UITheme.trim_children(box, 4)
	assert_eq(box.get_child_count(), 4, "trim_children left the surplus in the tree")
	assert_eq(box.get_child(0).name, StringName("line0"), "it trimmed the wrong end")

	UITheme.trim_children(box, 2, true)
	assert_eq(box.get_child_count(), 2, "trimming from the front left the surplus")
	assert_eq(box.get_child(0).name, StringName("line2"),
		"from_front should have dropped the oldest two")

	UITheme.clear_children(box)
	assert_eq(box.get_child_count(), 0, "clear_children left children behind")

	box.free()


## The log panel survives its forty-first line.
##
## **A hang here is the bug, not a slow test.** The panel used to trim itself with
## `while get_child_count() > 40: get_child(...).queue_free()`, and because the
## count never drops the loop never ends: the game locked solid, on every device,
## a few rounds into every run — as soon as enough had happened to fill the log.
## No error, no crash, just a window that stopped.
func test_the_log_panel_survives_passing_its_limit() -> void:
	var panel := SidePanels.FleetPanel.new()
	Engine.get_main_loop().root.add_child(panel)

	for i in SidePanels.FleetPanel.MAX_LOG_LINES + 12:
		events().logged.emit("line %d" % i, &"")

	assert_eq(panel._log.get_child_count(), SidePanels.FleetPanel.MAX_LOG_LINES,
		"the log kept more lines than its limit")
	assert_eq(panel._log.get_child(0).text, "line %d" % (SidePanels.FleetPanel.MAX_LOG_LINES + 11),
		"the newest line should be at the top; the trim took the wrong end")

	panel.free()


## The sea must not be able to take a click.
##
## `Ocean` is a ColorRect covering the whole board panel, and `Control` defaults
## `mouse_filter` to STOP — so the default is an invisible sheet over the board
## that eats every press meant for it: no dragging a pirate onto a hex, no
## dropping an item on one, no inspecting anything, and nothing on screen to
## suggest why. That is the toast bug again with the blast radius of the board.
##
## Checked through a real BoardView rather than on a bare Ocean, because what
## matters is that the board *ends up* with nothing hit-testable in front of it.
func test_the_ocean_cannot_swallow_a_click_on_the_board() -> void:
	var board := BoardView.new()
	board.size = Vector2(600, 500)
	Engine.get_main_loop().root.add_child(board)

	var blockers := PackedStringArray()
	_collect_blockers(board, "BoardView", blockers)
	assert_true(blockers.is_empty(),
		"these sit over the board and would swallow a drag: %s" % ", ".join(blockers))

	var ocean := board.find_child("Ocean", false, false)
	assert_not_null(ocean, "BoardView built no Ocean")
	assert_true(ocean.show_behind_parent,
		"the sea is drawn over the grid instead of under it")

	board.free()


## A finger can scroll a panel made of buttons, and scrolling does not press one.
##
## Godot's own touch scrolling arrives through `gui_input`, so a `Button` — which
## is STOP — eats the drag that starts on it. The almanac's list is rows with two
## points between them, so on a phone the only draggable part of the whole
## reference was the hairlines, and the forge chart has no gaps at all.
##
## The layout that would size the scrollbar is deferred to the end of a frame and
## the runner has no frame to give it, so the bar is told here what a tall list
## would have told it.
func test_a_finger_scrolls_a_panel_of_buttons_without_pressing_one() -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 40)
	scroll.size = Vector2(200, 200)
	Engine.get_main_loop().root.add_child(scroll)

	var bar := scroll.get_v_scroll_bar()
	bar.visible = true
	bar.max_value = 800.0
	bar.page = 200.0

	var driver := TouchScroll.attach(scroll)
	var at := Vector2(140, 140)

	driver._input(_press(at, true))
	assert_false(TouchScroll.dragged(), "a finger that has only just landed has not scrolled")

	driver._input(_drag(at, Vector2(0, -4)))
	assert_false(TouchScroll.dragged(), "four points of wobble counted as a scroll")
	assert_eq(scroll.scroll_vertical, 0, "the list moved under a tap")

	driver._input(_drag(at, Vector2(0, -36)))
	assert_true(TouchScroll.dragged(), "a forty point drag did not scroll the list")
	# 36 rather than 40: the wobble that had not yet passed the slop is spent
	# deciding this is a scroll, so the list never jumps to catch up with it.
	assert_eq(scroll.scroll_vertical, 36, "the list did not follow the finger")

	# A button acts on release, so the verdict has to survive it — and be gone by
	# the time the next tap asks.
	driver._input(_press(at, false))
	assert_true(TouchScroll.dragged(),
		"the release cleared the verdict the button was about to ask for")
	driver._input(_press(at, true))
	assert_false(TouchScroll.dragged(), "the next press did not clear it")

	# A tap somewhere that cannot scroll belongs to whatever is under it.
	bar.visible = false
	driver._input(_press(at, true))
	driver._input(_drag(at, Vector2(0, -40)))
	assert_false(TouchScroll.dragged(), "a panel with nothing to scroll claimed the gesture")

	scroll.free()


## Turning a phone sideways does nothing at all.
##
## The game is played upright. A rotation is not a different layout and not a
## prompt — it is ignored, so the HUD keeps the size it had and the extra width
## becomes bars. The failure this guards is silent in both directions: a phone
## that quietly went back to reflowing looks exactly like a phone nobody tested,
## and it lands on a screen with 390 points of height, where the portrait
## furniture alone is 387 and the board is what gets the remainder — nothing.
##
## The same window driven by a *mouse* must still reflow, because a desktop
## window somebody dragged into that shape is not a phone and can be dragged
## back. Both halves are asserted here; `screenshot.gd --rotate=` is the
## end-to-end pair.
func test_turning_a_phone_does_not_reflow_the_hud() -> void:
	# A throwaway window rather than the root: `apply` writes content scaling to
	# whatever it is handed, and the root belongs to the rest of the run.
	var window := Window.new()

	Layout.touch_override = 1
	window.size = Vector2i(390, 844)
	Layout.apply(window)
	var upright := Layout.css_size
	assert_gt(upright.y, upright.x, "an upright phone should be taller than it is wide")

	window.size = Vector2i(844, 390)
	assert_false(Layout.apply(window), "turning the phone asked for a rebuild")
	assert_eq(Layout.css_size, upright, "turning the phone changed the layout size")
	assert_false(Layout.short(), "a phone was given the landscape layout")

	Layout.touch_override = 0
	window.size = Vector2i(390, 844)
	Layout.apply(window)
	window.size = Vector2i(844, 390)
	assert_true(Layout.apply(window),
		"a mouse-driven window that got short did not ask for a rebuild")
	assert_true(Layout.short(),
		"a short mouse-driven window did not get the landscape layout")

	window.free()


## Layout is static and shared, so a test that moved it puts it back.
func after_each() -> void:
	Layout.touch_override = -1
	var window := Window.new()
	window.size = Layout.DESIGN
	Layout.apply(window)
	window.free()


func _press(at: Vector2, down: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.pressed = down
	event.position = at
	return event


func _drag(at: Vector2, by: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = 0
	event.position = at + by
	event.relative = by
	return event


func _collect_blockers(node: Node, path: String, into: PackedStringArray) -> void:
	for child in node.get_children():
		var where := "%s/%s" % [path, child.get_class()]
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append(where)
		_collect_blockers(child, where, into)
