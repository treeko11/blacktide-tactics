extends Ability

## Gut Hook — physical plus true damage, and a Rend that its own Harpooner trait
## then feeds on.

func id() -> StringName:
	return &"finn"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	sim.fx(&"slash", t, s, Color("ff9d9d"))
	sim.damage(s, t, s.ad * v(s, &"dmg") / 100.0, &"physical")
	sim.damage(s, t, scaled(s, &"tr"), &"true")
	sim.apply_shred(t, 0.25, 5.0)
