extends SeaEffect

## A following sea. One lane of the board runs with the current, and anyone
## standing in it when the swell comes through swings faster for a few seconds.
##
## The one sea worth standing in. Without it every round of weather is a tax,
## and a tax announced by a herald line is just a worse round with a nicer name —
## the decision "is that lane worth crowding into" is the opposite shape to
## "which hexes do I have to leave", and the system needs both to be a system.

const CURRENT := Color("7dffb0")


func id() -> StringName:
	return &"following_sea"


func cells(_def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var lane := rng.randi_range(0, Hex.COLS - 1)
	var out: Array[Vector2i] = []
	for y in Hex.ROWS:
		out.append(Vector2i(lane, y))
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(v(context, &"first", 3.0), v(context, &"interval", 4.0),
		func(): _swell(sim, context))


func _swell(sim: Sim, context: Dictionary) -> void:
	# The buff outlasts the swell but never the gap to the next one. Two of these
	# overlapping would multiply, and `add_buff` does not clamp — the unit would
	# come out of the fight permanently faster than it went in.
	var duration := minf(v(context, &"duration", 2.5),
		v(context, &"interval", 4.0) - 0.5)
	var mult := 1.0 + v(context, &"attack_speed", 30.0) / 100.0

	for cell in (context["cells"] as Array[Vector2i]):
		sim.fx_at(&"wave", Hex.to_pixel(cell), CURRENT)

	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		sim.add_buff(u, &"attack_speed", mult, duration)
		sim.float_text(u, "CURRENT", &"proc")
