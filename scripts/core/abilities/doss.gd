extends Ability

## Widow's Round — scales with how wounded the target already is, so it finishes
## rather than opens.

func id() -> StringName:
	return &"doss"


func scaling() -> Dictionary:
	return { &"dmg": &"ad" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.lowest_enemy(s.team)
	if t == null:
		return
	var missing := 1.0 - t.health_fraction()
	var amount := s.ad * v(s, &"dmg") / 100.0 * (1.0 + missing * v(s, &"amp") / 100.0)
	sim.fx(&"tracer", t, s, Color("ff5f5f"))
	sim.damage(s, t, amount, &"physical", { "can_crit": true })
