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


func _collect_blockers(node: Node, path: String, into: PackedStringArray) -> void:
	for child in node.get_children():
		var where := "%s/%s" % [path, child.get_class()]
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append(where)
		_collect_blockers(child, where, into)
