extends Ability

## Fleetbreaker — the five-cost that ends fights. Pulls, damages, stuns, then
## devours anything left under the execute threshold.
##
## The execute is checked after the damage, so it finishes what the pull softened
## rather than needing the target to arrive already wounded.

func id() -> StringName:
	return &"kraken"


func cast(sim: Sim, s: SimUnit) -> void:
	var foes := sim.enemies_near(s, 4)
	sim.fx(&"nova", s, null, Color("7a5fff"))
	var damage := scaled(s, &"dmg")
	var duration := v(s, &"stun")
	var threshold := v(s, &"ex") / 100.0
	for f in foes:
		sim.pull_to(s, f)
		sim.fx(&"chain", f, s, Color("9d7bff"))
		sim.damage(s, f, damage, &"magic")
		sim.stun(f, duration)
		if f.alive and f.health_fraction() <= threshold:
			sim.execute(s, f)
