extends Ability

## Featherstep — hops to whoever is closest to dying and speeds up.

func id() -> StringName:
	return &"pip"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.lowest_enemy(s.team)
	if t == null:
		t = sim.pick_target(s)
	if t == null:
		return
	sim.blink_near(s, t)
	sim.fx(&"slash", t, s, Color("9ef0c0"))
	sim.damage(s, t, s.ad * v(s, &"dmg") / 100.0, &"physical")
	sim.add_buff(s, &"attack_speed", 1.0 + v(s, &"as") / 100.0, 5.0)
