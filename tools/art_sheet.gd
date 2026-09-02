extends "res://tools/tool_script.gd"

## Draws every champion, or every animation state, onto one page.
##
##     Godot --path . --script res://tools/art_sheet.gd -- --out=sheet.png
##     Godot --path . --script res://tools/art_sheet.gd -- --poses --out=poses.png
##
## Must run **without** `--headless` — it is a renderer test.
##
## It exists because a figure is drawn from about a hundred polygons whose
## vertices are computed from an animated pose, and Godot answers a polygon that
## has folded over itself with "triangulation failed" printed once per frame
## rather than with a wrong shape on screen. A body that is fine standing still
## and degenerate mid-swing would otherwise be found by a player. Here every
## champion and every state is drawn at once, several frames apart, and any of
## them failing prints.
##
## The other half of its job is the one no test can do: showing all fifty-one
## next to each other, which is the only way to see that two 4-costs came out the
## same shade of teal.
##
## Built out of `UnitArt` alone rather than out of `UnitView`, because this is a
## `--script` target and a page of drawings needs neither the sim nor the HUD.
## Each figure is its own Node2D for the same reason the board gives each unit
## one: `draw_set_transform` **replaces** a CanvasItem's draw transform rather
## than composing with it, so a figure can only be moved by moving its node.

const CELL := Vector2(150.0, 156.0)
const COLUMNS := 9
const POSE_STATES := ["idle", "swing", "recoil", "cast", "moving", "stunned", "dead"]


func setup() -> void:
	var parts := arg("size", "1400x1000").split("x")
	if parts.size() == 2:
		root.size = Vector2i(int(parts[0]), int(parts[1]))
	startup_frames = int(arg("frames", "8"))


func run() -> void:
	# `run()` awaits, so it returns to the base class at the first frame it waits
	# for. Without this the tool quits before it has drawn anything.
	manual_quit = true

	var defs := _champions()
	if defs.is_empty():
		fail("Content reported no champions")
		finish()
		return

	var page := Page.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(page)

	var figures: Array[Figure] = []
	if has_flag("poses"):
		figures = _lay_out_poses(page, defs)
	else:
		figures = _lay_out_roster(page, defs)

	# Several frames at a moving clock, so every body is drawn at more than one
	# point of its idle cycle. A polygon that only folds at one phase of a sine
	# is exactly what this page exists to catch.
	for i in 14:
		for figure in figures:
			figure.pose.clock += 0.23
			figure.queue_redraw()
		await process_frame

	var image := root.get_texture().get_image()
	var out := arg("out", "user://art_sheet.png")
	var error := image.save_png(out)
	if error != OK:
		fail("could not write %s (error %d)" % [out, error])
	else:
		print("  %d figures drawn over 14 frames" % figures.size())
		print("  wrote %s" % ProjectSettings.globalize_path(out))
	finish()


## Every champion, idle, in id order — sorted so two runs of the page can be
## compared and so a new champion lands somewhere predictable.
func _lay_out_roster(page: Control, defs: Array) -> Array[Figure]:
	var out: Array[Figure] = []
	for i in defs.size():
		var def = defs[i]
		var at := Vector2(float(i % COLUMNS) + 0.5, float(i / COLUMNS)) * CELL
		at += Vector2(0.0, 62.0)

		var figure := Figure.new()
		figure.def = def
		figure.position = at
		figure.pose.clock = float(i) * 0.37
		page.add_child(figure)
		out.append(figure)

		page.labels.append({
			"at": at + Vector2(0.0, 48.0),
			"text": def.display_name,
			"size": 11, "color": Color("aebecb"),
		})
		page.labels.append({
			"at": at + Vector2(0.0, 61.0),
			"text": "%s %s" % [def.art_body, " ".join(def.art_marks)],
			"size": 9, "color": Color("5d7688"),
		})
	return out


## One body per row, every animation state across the columns. This is the half
## that catches a shape only degenerate while it is swinging.
func _lay_out_poses(page: Control, defs: Array) -> Array[Figure]:
	var out: Array[Figure] = []
	var seen: Array = []
	var row := 0
	for def in defs:
		if seen.has(def.art_body):
			continue
		seen.append(def.art_body)
		var y: float = 76.0 + row * 78.0
		page.labels.append({
			"at": Vector2(60.0, y - 30.0), "text": String(def.art_body),
			"size": 12, "color": Color("aebecb"),
		})
		for c in POSE_STATES.size():
			var figure := Figure.new()
			figure.def = def
			figure.position = Vector2(150.0 + c * 128.0, y)
			figure.pose.clock = float(row) * 0.4
			figure.pose.aim = Vector2(0.35, -1.0).normalized()
			match POSE_STATES[c]:
				"swing": figure.pose.swing = 0.85
				"recoil": figure.pose.recoil = 0.8
				"cast": figure.pose.cast = 1.0
				"moving": figure.pose.moving = 1.0
				"stunned": figure.pose.stunned = true
				"dead": figure.pose.dead = 0.6
			page.add_child(figure)
			out.append(figure)
			if row == 0:
				page.labels.append({
					"at": figure.position + Vector2(0.0, -44.0),
					"text": POSE_STATES[c], "size": 11, "color": Color("7c93a4"),
				})
		row += 1
	return out


func _champions() -> Array:
	var out: Array = []
	for def in content().champions():
		out.append(def)
	out.sort_custom(func(a, b): return String(a.id) < String(b.id))
	return out


# =============================================================================

## The page behind the figures: a dark ground and the captions.
class Page extends Control:

	var labels: Array[Dictionary] = []

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("071019"))
		var font := ThemeDB.fallback_font
		for entry in labels:
			var at: Vector2 = entry["at"]
			draw_string(font, at - Vector2(70.0, 0.0), entry["text"],
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, entry["size"], entry["color"])


## One figure, in its own node so it can be positioned at all.
class Figure extends Node2D:

	var def = null
	var pose := UnitArt.Pose.new()

	func _draw() -> void:
		if def == null:
			return
		UnitArt.draw_unit(self, def.art_body, def.art_tint, def.art_marks, pose,
			Color("5fe08a"), Color("e8b44a"))
