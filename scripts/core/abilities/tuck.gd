extends Ability

## Chart the Course — fleet-wide mana and haste. The mana is what makes this
## worth a board slot long after its own damage stops mattering.

func id() -> StringName:
	return &"tuck"


func cast(sim: Sim, s: SimUnit) -> void:
	var mana := v(s, &"mana")
	var haste := 1.0 + v(s, &"as") / 100.0
	for a in sim.living_allies(s.team):
		a.gain_mana(mana)
		sim.add_buff(a, &"attack_speed", haste, 6.0)
		sim.fx(&"pop", a, null, Color("ffe9a8"))
