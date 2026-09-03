extends Ability

## Salt Balm — the cheapest healer in the game.

func id() -> StringName:
	return &"nerida"


func scaling() -> Dictionary:
	return { &"heal": &"ap", &"shield": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var a := sim.lowest_ally(s.team)
	if a == null:
		a = s
	sim.heal(s, a, scaled(s, &"heal"))
	sim.add_shield(a, scaled(s, &"shield"), 6.0)
	sim.fx(&"pop", a, null, Color("7fe3ff"))
