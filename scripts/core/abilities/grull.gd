extends Ability

## Gorge — heals a share of *missing* health, so it is worth more the later it
## fires. A Grull at full health gains nothing from it.

func id() -> StringName:
	return &"grull"


func cast(sim: Sim, s: SimUnit) -> void:
	sim.heal(s, s, (s.max_hp - s.hp) * v(s, &"heal") / 100.0)
	sim.fx(&"shock", s, null, Color("ffb87a"))
	var pct := v(s, &"dmg") / 100.0
	for e in sim.enemies_near(s, 1):
		sim.damage(s, e, s.ad * pct, &"physical")
