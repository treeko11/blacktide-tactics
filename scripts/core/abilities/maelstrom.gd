extends Ability

## Whirlpool — drags the enemy board into one place and then grinds it. The
## damage ticks re-query who is in range, so anything that walks back out stops
## taking it.

func id() -> StringName:
	return &"maelstrom"


func cast(sim: Sim, s: SimUnit) -> void:
	for f in sim.enemies_near(s, 3):
		sim.pull_to(s, f)
		sim.fx(&"nova", f, null, Color("6ea8ff"))

	var per_tick := scaled(s, &"dmg") / 3.0
	var grind := func() -> void:
		for f in sim.enemies_near(s, 3):
			sim.damage(s, f, per_tick, &"magic")

	for i in 3:
		sim.delay(i * 0.9, grind)
