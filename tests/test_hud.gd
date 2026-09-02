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


func _collect_blockers(node: Node, path: String, into: PackedStringArray) -> void:
	for child in node.get_children():
		var where := "%s/%s" % [path, child.get_class()]
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append(where)
		_collect_blockers(child, where, into)
