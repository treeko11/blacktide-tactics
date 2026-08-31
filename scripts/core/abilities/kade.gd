extends Ability

## Storm Rounds — three rounds, each arcing to a second enemy near the first.

func id() -> StringName:
	return &"kade"


func cast(sim: Sim, s: SimUnit) -> void:
	var damage := scaled(s, &"dmg")

	var round_shot := func() -> void:
		if not s.alive:
			return
		var t := sim.pick_target(s)
		if t == null:
			return
		sim.fx(&"bolt", t, s, Color("8fd4ff"))
		sim.damage(s, t, damage, &"magic")
		var nearby := sim.enemies_near_cell(s.team, t.cell, 2, t)
		if not nearby.is_empty():
			var arc: SimUnit = nearby[0]
			sim.fx(&"bolt", arc, t, Color("8fd4ff"))
			sim.damage(s, arc, damage * 0.5, &"magic")

	for i in 3:
		sim.delay(i * 0.16, round_shot)
