extends Ability

## Dirge of the Drowned — lands on the densest cluster rather than on a target,
## so it punishes a clumped enemy board however that board is positioned.

func id() -> StringName:
	return &"morgause"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var cluster := sim.best_cluster(s.team, 1)
	if cluster.is_empty():
		return
	sim.fx_at(&"nova", cluster["pos"], Color("c58bff"))
	for e in cluster["units"]:
		sim.damage(s, e, scaled(s, &"dmg"), &"magic")
