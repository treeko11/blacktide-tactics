extends Ability

## Keg Slam — the tier-one front-liner's shield-and-splash.

func id() -> StringName:
	return &"barnaby"


func cast(sim: Sim, s: SimUnit) -> void:
	sim.fx(&"shock", s, null, Color("ffb44d"))
	sim.add_shield(s, scaled(s, &"shield"), 8.0)
	for e in sim.enemies_near(s, 2):
		sim.damage(s, e, scaled(s, &"dmg"), &"magic")
