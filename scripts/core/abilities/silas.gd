extends Ability

## Barnacle Skin — a shield now and a three-second aura afterwards, so it wants
## to be surrounded when it casts.

func id() -> StringName:
	return &"silas"


func cast(sim: Sim, s: SimUnit) -> void:
	sim.add_shield(s, scaled(s, &"shield"), 8.0)
	var damage := scaled(s, &"dmg")

	var pulse := func() -> void:
		if not s.alive:
			return
		sim.fx(&"shock", s, null, Color("87f5b5"))
		for e in sim.enemies_near(s, 1):
			sim.damage(s, e, damage, &"magic")

	for i in 3:
		sim.delay(float(i), pulse)
