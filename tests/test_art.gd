extends TestCase

## The unit art: that every champion has one, that it is one the renderer knows
## how to draw, and that the file on disk agrees with the table it came from.
##
## **Nothing here draws anything, and nothing here can.** Godot refuses a draw
## call made outside a real `_draw()` — a test that makes them anyway gets
## fifteen errors and a green tick, because the loop counting them still
## finishes. So rendering is checked by `tools/art_sheet.gd`, which runs
## non-headless, draws every champion and every animation state over fourteen
## frames, and prints Godot's own complaint about any polygon that folded over
## itself. It has already caught two. This is the same split as the sound: the
## bank is testable here, the noise is not.
##
## What these catch is the silent half — a champion added to `data/` that nobody
## gave a body, a mark renamed in `UnitArt` and left behind in fifty `.tres`, and
## a table edited without re-running `assign_art.gd`, which changes nothing at
## all and looks exactly like it worked.


func test_every_champion_has_a_body_the_renderer_knows() -> void:
	var unknown := PackedStringArray()
	for def in content().champions():
		if not UnitArt.BODIES.has(def.art_body):
			unknown.append("%s -> %s" % [def.id, def.art_body])
	assert_true(unknown.is_empty(),
		"these would fall back to a plain pirate: %s" % ", ".join(unknown))


func test_every_mark_is_one_the_renderer_draws() -> void:
	var unknown := PackedStringArray()
	for def in content().champions():
		for mark in def.art_marks:
			if not UnitArt.MARKS.has(mark):
				unknown.append("%s -> %s" % [def.id, mark])
	assert_true(unknown.is_empty(),
		"these are silently ignored at draw time: %s" % ", ".join(unknown))


## A champion with no entry in the table is playable, on the board, and a default
## blue pirate — which is the one failure here that a screenshot would not make
## obvious, because a board of pirates looks like a board of pirates.
func test_every_champion_is_in_the_art_table() -> void:
	var missing := PackedStringArray()
	for def in content().champions():
		if not ArtTable.ART.has(def.id):
			missing.append(String(def.id))
	assert_true(missing.is_empty(),
		"add these to tools/art_table.gd and re-run assign_art.gd: %s"
		% ", ".join(missing))


## The `.tres` is what the game reads; the table is only what stamped it. Editing
## one without re-running `assign_art.gd` changes nothing and gives no sign.
func test_the_tres_files_match_the_table() -> void:
	var stale := PackedStringArray()
	for def in content().champions():
		if not ArtTable.ART.has(def.id):
			continue
		var art: Dictionary = ArtTable.lookup(def.id)
		var marks: Array[StringName] = []
		marks.assign(art["marks"])
		if def.art_body != art["body"] or def.art_tint != Color(art["tint"]) \
				or def.art_marks != marks:
			stale.append(String(def.id))
	assert_true(stale.is_empty(),
		"run: godot --headless --path . --script res://tools/assign_art.gd — "
		+ "stale: %s" % ", ".join(stale))


## Two champions the same colour is not a bug, but fifty-one champions drawn from
## a handful of colours is the failure this whole scheme has: a family plus a
## tint is only distinguishable if the tints actually differ.
func test_champions_sharing_a_body_do_not_share_a_colour() -> void:
	var seen := {}
	var clashes := PackedStringArray()
	for def in content().champions():
		var key := "%s/%s" % [def.art_body, def.art_tint.to_html(false)]
		if seen.has(key):
			clashes.append("%s and %s are both %s" % [seen[key], def.id, key])
		seen[key] = def.id
	assert_true(clashes.is_empty(),
		"indistinguishable on the board: %s" % ", ".join(clashes))


## The palette is where the flash, the fade and the drain are applied, so a body
## cannot forget one of them. If it ever stops doing that, every body stops
## reacting to being hit at once and nothing else says so.
func test_the_palette_carries_damage_and_death() -> void:
	var tint := Color("4fd6c9")

	var resting := UnitArt.Pose.new()
	var calm: Dictionary = UnitArt.palette(tint, resting)
	assert_almost_eq(calm["main"].a, 1.0, 0.001, "a resting unit is opaque")

	var hurt := UnitArt.Pose.new()
	hurt.recoil = 1.0
	var flashed: Dictionary = UnitArt.palette(tint, hurt)
	assert_gt(flashed["main"].get_luminance(), calm["main"].get_luminance(),
		"a unit taking a hit does not flash")

	var sinking := UnitArt.Pose.new()
	sinking.dead = 1.0
	var faded: Dictionary = UnitArt.palette(tint, sinking)
	assert_lt(faded["main"].a, 0.5, "a dead unit does not fade")

	var stunned := UnitArt.Pose.new()
	stunned.stunned = true
	var drained: Dictionary = UnitArt.palette(tint, stunned)
	assert_lt(_saturation(drained["main"]), _saturation(calm["main"]),
		"a stunned unit keeps its colour")


func _saturation(c: Color) -> float:
	return maxf(maxf(c.r, c.g), c.b) - minf(minf(c.r, c.g), c.b)
