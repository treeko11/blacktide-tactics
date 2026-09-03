extends SeaEffect

## Witchfire. Cold fire clings to the water over the middle of the board, and it
## builds on anything that stands in it.
##
## The only fair wind that has to be *held*. One pulse is worth little and four
## are worth a fight, so the decision is not "is that hex worth stepping into"
## but "can my line hold the middle for ten seconds" — which is the shape of
## decision the other four seas do not ask for.
##
## Fixed over the centre, like the red tide is fixed to the rim, so it can be
## learned rather than re-read every time it comes round. It sits exactly where
## the two lines meet anyway: the water is not a detour, it is a reason to win
## the ground the fight was going to happen on.

const FIRE := Color("d7b8ff")

## The middle ground: the two rows either side of the line, three columns wide.
const ROWS_HELD: Array[int] = [3, 4]


func id() -> StringName:
	return &"witchfire"


func cells(def: SeaDef, _rng: RandomNumberGenerator) -> Array[Vector2i]:
	var width := clampi(int(def.value(&"hexes", 3.0)), 1, Hex.COLS)
	var x0 := (Hex.COLS - width) / 2

	var out: Array[Vector2i] = []
	for y in ROWS_HELD:
		for i in width:
			out.append(Vector2i(x0 + i, y))
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(v(context, &"first", 2.0), v(context, &"interval", 3.0),
		func(): _kindle(sim, context))


func _kindle(sim: Sim, context: Dictionary) -> void:
	# A flat addition per pulse, each expiring on its own clock, which is what
	# makes it stack and what makes it fade. `add_buff` multiplies, so four
	# overlapping copies of it would compound into a number nobody authored —
	# the trap the following sea has to duck by expiring before its next swell.
	var stack := v(context, &"damage_amp", 8.0) / 100.0
	var duration := v(context, &"duration", 9.0)

	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		sim.add_flat(u, &"damage_amp", stack, duration)
		sim.fx(&"bolt", u, null, FIRE)
		sim.float_text(u, "WITCHFIRE", &"proc")
