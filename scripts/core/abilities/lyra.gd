extends Ability

## Piercing Shot — one shot down the whole line, each hit able to crit and
## ignoring most armour. Rewards lining your own board up with theirs.

func id() -> StringName:
	return &"lyra"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	sim.fx(&"beam", t, s, Color("ffe07a"))
	var amount := s.ad * v(s, &"dmg") / 100.0
	var options := { "can_crit": true, "penetration": v(s, &"pen") / 100.0 }
	for e in sim.line_targets(s, t, 6.0):
		sim.damage(s, e, amount, &"physical", options)
