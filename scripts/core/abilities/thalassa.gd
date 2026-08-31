extends Ability

## Tidal Surge — a line through the enemy board plus a fleet-wide heal. The line
## is taken through the current target, so what it catches is a positioning
## question rather than a targeting one.

func id() -> StringName:
	return &"thalassa"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	var damage := scaled(s, &"dmg")
	var heal := scaled(s, &"heal")
	sim.fx(&"wave", t, s, Color("5fd8ff"))
	for e in sim.line_targets(s, t, 5.0):
		sim.damage(s, e, damage, &"magic")
	for a in sim.living_allies(s.team):
		sim.heal(s, a, heal)
