extends Ability

## Resupply — shields and mana for whoever is worst off. The mana is the reason
## Voss ends up in caster comps that do not need the shielding.

func id() -> StringName:
	return &"voss"


func scaling() -> Dictionary:
	return { &"shield": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var allies := sim.living_allies(s.team)
	allies.sort_custom(func(a, b): return a.health_fraction() < b.health_fraction())
	var shield := scaled(s, &"shield")
	var mana := v(s, &"mana")
	for a in allies.slice(0, 3):
		sim.add_shield(a, shield, 8.0)
		a.gain_mana(mana)
		sim.fx(&"pop", a, null, Color("ffe9a8"))
