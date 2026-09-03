extends SeaEffect

## Sunlit shallows. The sun breaks through onto a bar of shallow water on each
## side of the board, and anything standing in it mends.
##
## The red tide read backwards, deliberately: the same continuous tick on the
## same kind of marked water, paying out instead of taking. That is what makes
## the pair legible — a player who has learned to walk out of one water has
## learned everything they need to walk into the other.
##
## A share of maximum health rather than a flat number, for the tide's reason:
## flat healing is a rounding error to a three-star carry and a full restore to a
## Deck Rat, and the water should not care which pirate stood in it.

const SUNLIGHT := Color("ffe6a3")

## Ticks a second, matching the tide. Anything faster banks into one popup
## anyway and only costs the sim the arithmetic.
const PERIOD := 1.0


func id() -> StringName:
	return &"sunlit_shallows"


## A short bar in the player's half and the same bar mirrored into the
## opponent's, so both captains are offered the same water in the same place
## relative to their own line. Wide rather than deep — a bar is a row of the
## board somebody has to hold, where a column would just be a lane to stand in
## and the following sea is already that.
func cells(def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var width := clampi(int(def.value(&"hexes", 3.0)), 1, Hex.COLS)
	var x0 := rng.randi_range(0, Hex.COLS - width)
	var y := rng.randi_range(Hex.PLAYER_ROW_MIN, Hex.ROWS - 1)

	var out: Array[Vector2i] = []
	for i in width:
		var cell := Vector2i(x0 + i, y)
		out.append(cell)
		var twin := Hex.mirror(cell)
		if not out.has(twin):
			out.append(twin)
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(PERIOD, PERIOD, func(): _mend(sim, context))


func _mend(sim: Sim, context: Dictionary) -> void:
	var share := v(context, &"hp_percent", 3.0) / 100.0
	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		# Through `Sim.heal`, so overtime cuts it the way it cuts every other
		# heal in the game. A sea that healed around the ramp would be the one
		# thing in the fight capable of holding a stalemate open.
		if sim.heal(null, u, u.max_hp * share) > 0.0:
			sim.fx(&"pop", u, null, SUNLIGHT)
