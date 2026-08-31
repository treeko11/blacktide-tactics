extends Ability

## Sovereign Storm — a four-second channel: a bolt at a random enemy every 0.4s,
## and a fleet-wide heal on every other one.
##
## Random targeting comes from the sim's own generator, not `randi()`, so a fight
## replayed with the same seed produces the same storm.

func id() -> StringName:
	return &"calypso"


func cast(sim: Sim, s: SimUnit) -> void:
	for i in 10:
		sim.delay(i * 0.4, _pulse.bind(sim, s, i))


func _pulse(sim: Sim, s: SimUnit, index: int) -> void:
	if not s.alive:
		return
	var foes := sim.living_enemies(s.team)
	if not foes.is_empty():
		var t: SimUnit = foes[sim.rng.randi_range(0, foes.size() - 1)]
		sim.fx(&"bolt", t, null, Color("a8e4ff"))
		sim.damage(s, t, scaled(s, &"dmg"), &"magic")
	if index % 2 == 0:
		var heal := scaled(s, &"heal") * 0.8
		for a in sim.living_allies(s.team):
			sim.heal(s, a, heal)
