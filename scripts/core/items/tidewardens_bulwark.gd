extends ItemEffect

## Tidewarden's Bulwark - the Aegis opening shield and the Anchor cast shield on
## one body, so the carrier covers the first exchange and then keeps covering the
## worst-off three for the rest of the fight.

func id() -> StringName:
	return &"tidewardens_bulwark"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 40.0
	u.armor += 35.0
	u.magic_resist += 35.0
	sim.add_max_hp(u, 400.0)
	u.gain_mana(20.0)
	sim.add_shield(u, 420.0, 10.0)

	var on_cast := func(unit: SimUnit) -> void:
		var mates := sim.living_allies(unit.team)
		mates.erase(unit)
		mates.sort_custom(func(a, b): return a.health_fraction() < b.health_fraction())
		var targets: Array[SimUnit] = [unit]
		targets.append_array(mates.slice(0, 2))
		for t in targets:
			sim.add_shield(t, 380.0, 6.0)
			sim.fx(&"pop", t, null, Color("7fe3ff"))
		sim.proc_text(unit, "BULWARK")

	u.hooks_on_cast.append(on_cast)
