extends Ability

## Flagship Broadside — a huge area nuke plus permanent fleet-wide stats. The
## stats are the half that wins long fights.

func id() -> StringName:
	return &"nautica"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var cluster := sim.best_cluster(s.team, 2)
	if not cluster.is_empty():
		sim.fx_at(&"nova", cluster["pos"], Color("ffd27a"))
		var damage := scaled(s, &"dmg")
		for e in cluster["units"]:
			sim.damage(s, e, damage, &"magic")

	var resist := v(s, &"res")
	var power := v(s, &"ap")
	for a in sim.living_allies(s.team):
		a.armor += resist
		a.magic_resist += resist
		a.ability_power += power
		sim.fx(&"pop", a, null, Color("ffe9a8"))
