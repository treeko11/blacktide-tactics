extends SeaEffect

## Rogue waves. A few lanes of the board are marked during planning, and every
## so often a wave rolls up one and shoves whoever is standing in it a hex
## sideways.
##
## This is the sea the whole system exists for: it is the only one that moves a
## formation the player built, so it is the only one that makes them build a
## formation that can survive being moved. Everything else here bends a stat.

const FOAM := Color("7fe3ff")


func id() -> StringName:
	return &"rogue_waves"


## Whole columns, drawn once per stage.
##
## The last column is never picked. A wave pushes toward +x, so a lane on the
## right-hand edge has nowhere to push anyone into and would be marked hazard on
## the board while doing nothing at all.
func cells(def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var columns: Array[int] = []
	for x in Hex.COLS - 1:
		columns.append(x)

	# Fisher-Yates through the run's own generator, so a seeded run gets the
	# same weather in the same places.
	for i in range(columns.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := columns[i]
		columns[i] = columns[j]
		columns[j] = swap

	columns.resize(mini(maxi(1, int(def.value(&"lanes", 2.0))), columns.size()))
	columns.sort()

	var out: Array[Vector2i] = []
	for x in columns:
		for y in Hex.ROWS:
			out.append(Vector2i(x, y))
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(v(context, &"first", 6.0), v(context, &"interval", 8.0),
		func(): _sweep(sim, context))


func _sweep(sim: Sim, context: Dictionary) -> void:
	# The wave is drawn along the whole lane, not only where someone is standing.
	# A wave that appears under two pirates and nowhere else reads as those two
	# pirates doing something.
	for cell in (context["cells"] as Array[Vector2i]):
		sim.fx_at(&"wave", Hex.to_pixel(cell), FOAM)

	var caught: Array[SimUnit] = []
	for u in sim.units:
		if u.alive and touches(context, u.cell):
			caught.append(u)

	# Rightmost first. Pushed the other way round, a unit tries to move into a
	# cell whose occupant has not been pushed out of it yet, and the front of
	# the lane never moves at all.
	caught.sort_custom(func(a: SimUnit, b: SimUnit) -> bool: return a.cell.x > b.cell.x)

	for u in caught:
		var to := u.cell + Vector2i(1, 0)
		if not sim.cell_free(to):
			continue
		sim.place(u, to)
		sim.float_text(u, "WASHED", &"proc")
