extends Ability

## Feeding Frenzy — leaps at the weakest enemy and heals off the bite.

func id() -> StringName:
	return &"hookjaw"


func scaling() -> Dictionary:
	return { &"dmg": &"ad", &"heal": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.lowest_enemy(s.team)
	if t == null:
		return
	sim.blink_near(s, t)
	sim.fx(&"slash", t, s, Color("ff8f5c"))
	sim.damage(s, t, s.ad * v(s, &"dmg") / 100.0, &"physical", { "can_crit": true })
	sim.heal(s, s, scaled(s, &"heal"))
