extends Ability

## Reef Bloom — splashes around the target and heals around the caster, so it
## wants to stand at the seam between the two lines.

func id() -> StringName:
	return &"coral"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	var damage := scaled(s, &"dmg")
	sim.fx(&"shock", t, null, Color("79ffd0"))
	sim.damage(s, t, damage, &"magic")
	for e in sim.enemies_near_cell(s.team, t.cell, 1, t):
		sim.damage(s, e, damage, &"magic")
	for a in sim.allies_near(s, 2):
		sim.heal(s, a, scaled(s, &"heal"))
