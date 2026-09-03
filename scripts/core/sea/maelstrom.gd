extends SeaEffect

## A maelstrom. Two whirlpools open, one in each half of the board, and the
## water around each drags anything standing in it toward the eye.
##
## The other displacement sea, and deliberately the opposite shape to the rogue
## waves: those shove a lane sideways and break a formation apart, this one
## gathers one up. A crew dragged into a knot around an eye is a crew standing
## in exactly the shape every splash ability in the game is looking for, so the
## cost of ignoring it is paid by the enemy's carry rather than by the water.

const SWIRL := Color("3f8fd0")


func id() -> StringName:
	return &"maelstrom"


## A disc in the player's half and one in the opponent's.
##
## The two are drawn separately rather than one being mirrored, because a mirror
## flips the row parity and an offset-grid disc reflected that way is no longer
## a disc — it would mark a blob whose middle is not the middle, which is the one
## thing this sea cannot afford to get wrong.
##
## Inset a hex from every edge so the whole ring is on the board: a marked hex
## that promises water running off the side is water the player cannot use.
func cells(_def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var eye := Vector2i(rng.randi_range(1, Hex.COLS - 2),
		rng.randi_range(Hex.PLAYER_ROW_MIN + 1, Hex.ROWS - 2))

	var out: Array[Vector2i] = []
	for centre in [eye, Hex.mirror(eye)]:
		for cell in Hex.in_range(centre, 1, true):
			if Hex.on_board(cell) and not out.has(cell):
				out.append(cell)
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(v(context, &"first", 5.0), v(context, &"interval", 6.0),
		func(): _drag(sim, context))


## The still water at the middle of each whirlpool.
##
## Worked out from the marked cells rather than remembered. The cells are drawn
## once outside the fight and handed in, and that list is the only thing the sim
## is given — an eye kept anywhere else could disagree with the water the board
## is showing the player, which is the whole failure the handed-in cells exist to
## prevent. Inside a disc only the centre is surrounded on all six sides.
##
## **Six of them, and all six marked.** `Hex.neighbours` drops the neighbours
## that fall off the edge of the board, so "every neighbour is marked" is true of
## the corner of a disc lying against the side — the water it is missing is water
## nobody could have marked. Counting them is what tells the two apart, and it is
## what the inset in `cells()` is holding up: a whirlpool a hex in from every
## edge has all six of the eye's neighbours on the board, so the count costs a
## true eye nothing and costs a rim cell everything. Caught by the test on a seed
## that put a disc on the bottom row, reporting six eyes where there were two.
func _eyes(context: Dictionary) -> Array[Vector2i]:
	var marked: Array[Vector2i] = context["cells"]
	var out: Array[Vector2i] = []
	for cell in marked:
		var ring := Hex.neighbours(cell)
		if ring.size() < 6:
			continue
		var whole := true
		for n in ring:
			if not marked.has(n):
				whole = false
				break
		if whole:
			out.append(cell)
	return out


func _drag(sim: Sim, context: Dictionary) -> void:
	var eyes := _eyes(context)
	if eyes.is_empty():
		return

	# Drawn on the eyes rather than on whoever is being pulled, for the reason
	# the rogue waves draw the whole lane: an effect that appears only where
	# somebody is standing reads as that somebody doing something.
	for eye in eyes:
		sim.fx_at(&"shock", Hex.to_pixel(eye), SWIRL)

	var caught: Array[SimUnit] = []
	for u in sim.units:
		if u.alive and touches(context, u.cell):
			caught.append(u)

	# Innermost first. A unit one hex out cannot be dragged into a cell whose
	# occupant has not been dragged out of it yet, and pulled the other way round
	# the ring never closes at all — the same ordering trap as the waves, with
	# the sort running the other way because this pulls where they push.
	caught.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		return _to_eye(eyes, a.cell) < _to_eye(eyes, b.cell))

	for u in caught:
		var eye := _nearest_eye(eyes, u.cell)
		if u.cell == eye:
			continue
		var to := _inward(u.cell, eye)
		if to == u.cell or not sim.cell_free(to):
			continue
		sim.place(u, to)
		sim.float_text(u, "DRAGGED", &"proc")


func _to_eye(eyes: Array[Vector2i], cell: Vector2i) -> int:
	var best := 99
	for eye in eyes:
		best = mini(best, Hex.distance(cell, eye))
	return best


func _nearest_eye(eyes: Array[Vector2i], cell: Vector2i) -> Vector2i:
	var best := eyes[0]
	for eye in eyes:
		if Hex.distance(cell, eye) < Hex.distance(cell, best):
			best = eye
	return best


## One hex closer to the eye. Neighbours are walked in a fixed order and the
## first shortest wins, so a seeded fight drags the same crew the same way.
func _inward(from: Vector2i, eye: Vector2i) -> Vector2i:
	var best := from
	var best_d := Hex.distance(from, eye)
	for n in Hex.neighbours(from):
		if not Hex.on_board(n):
			continue
		var d := Hex.distance(n, eye)
		if d < best_d:
			best_d = d
			best = n
	return best
