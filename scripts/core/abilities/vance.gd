extends Ability

## All Hands — the whole fleet is shielded and hastened, then the densest enemy
## cluster is bombarded. Both halves at once is what makes it a four-cost.

func id() -> StringName:
	return &"vance"


func cast(sim: Sim, s: SimUnit) -> void:
	var shield := scaled(s, &"shield")
	var haste := 1.0 + v(s, &"as") / 100.0
	for a in sim.living_allies(s.team):
		sim.add_shield(a, shield, 6.0)
		sim.add_buff(a, &"attack_speed", haste, 6.0)
		sim.fx(&"pop", a, null, Color("ffe9a8"))

	var cluster := sim.best_cluster(s.team, 1)
	if cluster.is_empty():
		return
	sim.fx_at(&"nova", cluster["pos"], Color("ffb44d"))
	for e in cluster["units"]:
		sim.damage(s, e, scaled(s, &"dmg"), &"magic")
