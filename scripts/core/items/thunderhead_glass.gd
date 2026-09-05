extends ItemEffect

## Thunderhead Glass - the Windrunner chain fired at Stormglass speed, and the
## shred makes the chain and the carrier's own ability land harder together.
##
## Its own counter key rather than the Windrunner one, so a unit carrying both
## fires two independent chains instead of the pair sharing every third attack.

func id() -> StringName:
	return &"thunderhead_glass"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 45.0
	u.attack_speed *= 1.25
	u.gain_mana(15.0)

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		var fired: int = unit.scratch.get(&"thunderhead_glass", 0) + 1
		unit.scratch[&"thunderhead_glass"] = fired
		if fired % 3 != 0:
			return
		var foes := sim.living_enemies(unit.team)
		foes.sort_custom(func(a, b): return sim.distance(unit, a) < sim.distance(unit, b))
		for f in foes.slice(0, 3):
			sim.fx(&"chain", f, unit, Color("8fd4ff"))
			sim.damage(unit, f, 125.0, &"magic")
			sim.apply_shred_mr(f, 0.35, 5.0)

	var on_cast := func(unit: SimUnit) -> void:
		sim.add_buff(unit, &"attack_speed", 1.40, 5.0)
		sim.proc_text(unit, "HASTE")

	u.hooks_on_attack.append(on_attack)
	u.hooks_on_cast.append(on_cast)
