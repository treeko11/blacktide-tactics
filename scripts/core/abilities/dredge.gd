extends Ability

## Crushing Claw — a two-hex stun on everything nearby. The largest area lockdown
## available before tier four.

func id() -> StringName:
	return &"dredge"


func cast(sim: Sim, s: SimUnit) -> void:
	sim.fx(&"shock", s, null, Color("ff9166"))
	var damage := scaled(s, &"dmg")
	var duration := v(s, &"stun")
	for e in sim.enemies_near(s, 2):
		sim.damage(s, e, damage, &"magic")
		sim.stun(e, duration)
