extends Ability

## Crimson Flurry — four strikes that can crit, retargeting between each. A
## fresh `pick_target` per strike means it rolls onto the next enemy rather than
## wasting the rest of the flurry on a corpse.

func id() -> StringName:
	return &"isla"


func cast(sim: Sim, s: SimUnit) -> void:
	var pct := v(s, &"dmg") / 100.0

	var strike := func() -> void:
		if not s.alive:
			return
		var t := sim.pick_target(s)
		if t == null:
			return
		sim.fx(&"slash", t, s, Color("ff6b6b"))
		sim.damage(s, t, s.ad * pct, &"physical", { "can_crit": true })

	for i in 4:
		sim.delay(i * 0.13, strike)
