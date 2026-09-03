extends Ability

## Whalesong — heals everyone and hurts whatever is standing next to it.

func id() -> StringName:
	return &"kelpar"


func scaling() -> Dictionary:
	return { &"dmg": &"ap", &"heal": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	for a in sim.living_allies(s.team):
		sim.heal(s, a, scaled(s, &"heal"))
		sim.fx(&"pop", a, null, Color("7fe3ff"))
	for e in sim.enemies_near(s, 1):
		sim.damage(s, e, scaled(s, &"dmg"), &"magic")
