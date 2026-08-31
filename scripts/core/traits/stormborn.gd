extends TraitEffect

## Stormborn — lightning on a timer, no unit required to survive for it.
##
## Damage is sourced from nobody (`null`), so it cannot crit, cannot be amplified
## by a champion's stats and cannot heal anyone through omnivamp. That is the
## point: it is weather, not an attack.

func id() -> StringName:
	return &"stormborn"


func apply(sim: Sim, context: Dictionary) -> void:
	var strikes := int(v(context, &"n"))
	var damage := v(context, &"dmg")
	var team_id: int = context["team_id"]

	var storm := func() -> void:
		var foes := sim.living_enemies(team_id)
		if foes.is_empty():
			return
		foes.sort_custom(func(a, b): return a.hp > b.hp)
		for k in mini(strikes, foes.size()):
			sim.fx(&"bolt", foes[k], null, Color("8fd4ff"))
			sim.damage(null, foes[k], damage, &"magic")

	sim.add_timer(3.0, 3.0, storm)
