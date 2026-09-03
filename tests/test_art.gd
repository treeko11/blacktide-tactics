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


## The rule the whole scheme rests on, and the one that drifted for months: a
## champion is drawn as a body one of its **own origins** licenses. Nine of them
## were wearing a faction they were not in, and nothing here could see it,
## because every one was a valid body with a unique colour.
func test_every_body_is_licensed_by_an_origin_the_champion_has() -> void:
	var wrong := PackedStringArray()
	for def in content().champions():
		if _is_monster(def):
			continue
		var licensed := _licensed_bodies(def)
		if not licensed.has(def.art_body):
			wrong.append("%s (%s) is drawn as %s, which needs %s" % [def.id,
				_origins_of(def), def.art_body, licensed])
	assert_true(wrong.is_empty(),
		"art promising a trait the champion does not have: %s" % ", ".join(wrong))


## The other direction, and the one a reader actually uses: seeing a wraith on
## the board has to mean Ghost Fleet, or the silhouette says nothing.
##
## Only the bodies outside `CREW_BODIES` can be read backwards. Corsair licenses
## `pirate` and `gunner`, which are also what a champion with no faction at all
## is drawn as — so a pirate means "not one of the bodied factions" and nothing
## more, which is exactly what it should mean.
func test_an_origin_body_is_worn_only_by_that_origin() -> void:
	var wrong := PackedStringArray()
	for def in content().champions():
		if _is_monster(def) or ArtTable.CREW_BODIES.has(def.art_body):
			continue
		for origin in ArtTable.ORIGIN_BODIES:
			var bodies: Array = ArtTable.ORIGIN_BODIES[origin]
			if bodies.has(def.art_body) and not def.has_trait(origin):
				wrong.append("%s is drawn as %s without %s" % [def.id, def.art_body, origin])
	assert_true(wrong.is_empty(),
		"a body that means a faction, worn by somebody outside it: %s" % ", ".join(wrong))


## Grull was a golem and Sable was a ship, which is what the Wreck Golem and the
## Ghost Skiff are. A pirate sharing a monster's silhouette reads as a monster.
func test_no_champion_wears_a_monster_body() -> void:
	var wrong := PackedStringArray()
	for def in content().champions():
		if not _is_monster(def) and ArtTable.MONSTER_BODIES.has(def.art_body):
			wrong.append("%s -> %s" % [def.id, def.art_body])
	assert_true(wrong.is_empty(),
		"these read as monsters on the board: %s" % ", ".join(wrong))


## A trait carried by a mark is carried by it on **every** champion that has the
## trait. Half a marked trait is worse than an unmarked one: it teaches the
## player a rule and then breaks it.
func test_a_traits_mark_is_on_every_champion_that_has_it() -> void:
	var missing := PackedStringArray()
	for trait_id in ArtTable.TRAIT_MARKS:
		var mark: StringName = ArtTable.TRAIT_MARKS[trait_id]["mark"]
		for def in content().champions():
			if def.has_trait(trait_id) and not def.art_marks.has(mark):
				missing.append("%s has %s but no %s" % [def.id, trait_id, mark])
	assert_true(missing.is_empty(),
		"a trait marked on some of its carriers and not others: %s" % ", ".join(missing))


## And an exclusive mark appears nowhere else, so the mark can be read backwards.
## `musket` is declared non-exclusive on purpose and is not checked here.
func test_an_exclusive_mark_is_worn_only_by_that_trait() -> void:
	var wrong := PackedStringArray()
	for trait_id in ArtTable.TRAIT_MARKS:
		if not ArtTable.TRAIT_MARKS[trait_id]["exclusive"]:
			continue
		var mark: StringName = ArtTable.TRAIT_MARKS[trait_id]["mark"]
		for def in content().champions():
			if _is_monster(def):
				continue
			if def.art_marks.has(mark) and not def.has_trait(trait_id):
				wrong.append("%s wears %s without %s" % [def.id, mark, trait_id])
	assert_true(wrong.is_empty(),
		"a mark that means a trait, worn by somebody without it: %s" % ", ".join(wrong))


## The anti-drift half. A fourteenth trait added to `data/traits/` fails here
## until somebody has decided whether it gets a body, a mark, or neither — which
## is the decision that never gets made when nothing asks for it.
func test_every_trait_has_decided_what_it_looks_like() -> void:
	var undecided := PackedStringArray()
	for trait_def in content().traits():
		var has_body: bool = ArtTable.ORIGIN_BODIES.has(trait_def.id) 			and not (ArtTable.ORIGIN_BODIES[trait_def.id] as Array).is_empty()
		var has_mark: bool = ArtTable.TRAIT_MARKS.has(trait_def.id)
		var declared_bare: bool = ArtTable.TRAITS_WITHOUT_ART.has(trait_def.id)
		if not (has_body or has_mark or declared_bare):
			undecided.append(String(trait_def.id))
	assert_true(undecided.is_empty(),
		"give these a body in ORIGIN_BODIES, a mark in TRAIT_MARKS, or list them "
		+ "in TRAITS_WITHOUT_ART: %s" % ", ".join(undecided))


## Every Origin has to answer the body question even if the answer is "none", so
## a new faction cannot arrive silently sharing somebody else's silhouette.
func test_every_origin_declares_which_bodies_it_licenses() -> void:
	var missing := PackedStringArray()
	for trait_def in content().traits():
		if trait_def.kind == TraitDef.Kind.ORIGIN 				and not ArtTable.ORIGIN_BODIES.has(trait_def.id):
			missing.append(String(trait_def.id))
	assert_true(missing.is_empty(),
		"add these to ArtTable.ORIGIN_BODIES, with [] if they get no body of "
		+ "their own: %s" % ", ".join(missing))


## Monsters are cost 0, carry no traits and are never in anybody's fleet, so
## every rule above is about champions and skips them.
func _is_monster(def: ChampionDef) -> bool:
	return def.cost <= 0


func _origins_of(def: ChampionDef) -> String:
	var out := PackedStringArray()
	for t in def.traits:
		if ArtTable.ORIGIN_BODIES.has(t):
			out.append(String(t))
	return ", ".join(out) if out.size() > 0 else "no origin"


func _licensed_bodies(def: ChampionDef) -> Array:
	var out: Array = []
	for t in def.traits:
		if not ArtTable.ORIGIN_BODIES.has(t):
			continue
		for body in ArtTable.ORIGIN_BODIES[t]:
			if not out.has(body):
				out.append(body)
	return out if not out.is_empty() else ArtTable.CREW_BODIES


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
