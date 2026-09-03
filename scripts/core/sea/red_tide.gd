extends SeaEffect

## Red tide. The water along both edges of the board is poison, and anything
## standing in it burns.
##
## The cells are fixed rather than drawn — the two outer columns, every round it
## comes up — because this one is about squeezing eighteen pirates into a
## narrower board than they were built for. A hazard that moved would be a
## different puzzle every time and never one worth learning.

const BLOOM := Color("d1466a")

## Ticks a second. Slow enough to be a cost rather than an execution, fast
## enough that standing in it is visibly a choice being made badly.
const PERIOD := 1.0


func id() -> StringName:
	return &"red_tide"


func cells(_def: SeaDef, _rng: RandomNumberGenerator) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Hex.ROWS:
		out.append(Vector2i(0, y))
		out.append(Vector2i(Hex.COLS - 1, y))
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(PERIOD, PERIOD, func(): _burn(sim, context))


func _burn(sim: Sim, context: Dictionary) -> void:
	# A share of max health, so it costs a five-cost carry the same fraction it
	# costs a Deck Rat. Flat damage there would be a rounding error to one and a
	# death sentence to the other.
	var share := v(context, &"hp_percent", 2.0) / 100.0
	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		sim.damage(null, u, u.max_hp * share, &"true")
		sim.fx(&"drain", u, null, BLOOM)
