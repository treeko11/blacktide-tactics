extends Ability

## Hull-Piercer — armour penetration rather than raw damage, which is what makes
## a one-cost relevant into a Leviathan board.

func id() -> StringName:
	return &"marlowe"


func scaling() -> Dictionary:
	return { &"dmg": &"ad" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	sim.fx(&"tracer", t, s, Color("cfe6ff"))
	sim.damage(s, t, s.ad * v(s, &"dmg") / 100.0, &"physical",
		{ "penetration": v(s, &"pen") / 100.0 })
