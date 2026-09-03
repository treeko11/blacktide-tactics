extends Ability

## Thunderhead — full damage to the target, half to whatever is beside it, and
## magic-resist shred on all of them so the follow-up lands harder.

func id() -> StringName:
	return &"mira"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	var damage := scaled(s, &"dmg")
	var shred := v(s, &"shred") / 100.0
	sim.fx(&"bolt", t, s, Color("8fd4ff"))
	sim.damage(s, t, damage, &"magic")
	sim.apply_shred_mr(t, shred, 6.0)
	for e in sim.enemies_near_cell(s.team, t.cell, 1, t):
		sim.damage(s, e, damage * 0.5, &"magic")
		sim.apply_shred_mr(e, shred, 6.0)
