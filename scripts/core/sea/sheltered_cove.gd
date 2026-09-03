extends SeaEffect

## A sheltered cove. Two rows of the board lie out of the swell, and any crew
## that *starts* the fight standing in one is covered for the opening seconds.
##
## The one sea that is paid at the bell and never again. Every other fair wind
## rewards being somewhere when the swell comes through, which a unit can walk
## into halfway down the fight; this one rewards a decision made in the planning
## phase and cannot be walked into afterwards. That is the whole point of it —
## it is the sea that pays for the thing the sea system is for.
##
## The shield is a share of maximum health, so it is worth the same to the
## frontline whatever the frontline is made of.

const SHELTER := Color("8fe0d8")


func id() -> StringName:
	return &"sheltered_cove"


## Two whole rows at the same depth, one in each half.
##
## Never the back rows. A shield handed to a gunner nobody has reached yet is a
## gift that expires unspent, and a fair wind that pays nothing is worse than no
## fair wind at all — it teaches the player that the marked water is not worth
## reading.
func cells(_def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var depth := rng.randi_range(Hex.PLAYER_ROW_MIN, Hex.PLAYER_ROW_MIN + 1)
	var out: Array[Vector2i] = []
	for x in Hex.COLS:
		out.append(Vector2i(x, depth))
		out.append(Vector2i(x, Hex.ROWS - 1 - depth))
	return out


## Read at the bell, which is when this runs: the sea is applied as the fight is
## built, so `cell` is still the seat the captain gave the pirate.
func apply(sim: Sim, context: Dictionary) -> void:
	var share := v(context, &"shield", 25.0) / 100.0
	var duration := v(context, &"duration", 8.0)
	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		sim.add_shield(u, u.max_hp * share, duration)
		sim.fx(&"pop", u, null, SHELTER)
		sim.float_text(u, "SHELTERED", &"proc")
